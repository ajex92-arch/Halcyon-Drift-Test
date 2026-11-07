extends Node
## WHAT THIS IS: the shield-click check (the user's F9 note of Thu 2026-11-05: "click a shield direction button in the UI
## while pressing a direction key (w, s, d, a) and the ship stops moving in the direction I am pressing and starts to fly
## around randomly"). A pilot holds a flying key (W, A, S, D, one at a time and in pairs), moves the pointer onto a part of
## the ship readout (each of the four shield zones, each of the four energy buttons and the ship icon), clicks it, rests on
## it and moves back. The check logs the hull's heading and the ship's velocity every tick and says how far they go from
## where they were when the click started.
##
## HOW IT WORKS: it waits for the HUD and a flying human, makes the window 1280 x 720 (a headless window is only 64 x 64)
## and then runs one scenario per (key set, part), 220 physics ticks each, after the camera has caught up with the teleported ship, on the same spot, teleporting the ship back
## to its start and giving it full hull first:
##   ticks   0-59   the keys are down, the pointer is out in the world ahead of the ship;
##   ticks  60-89   the pointer travels onto the part (as a hand does it, half a second);
##   ticks  90-119  it rests on the part;
##   tick  120      the left button goes down on the part, and up at tick 126 (the click);
##   ticks 126-199  the pointer stays on the part, the keys stay down;
##   ticks 200-219  the pointer goes back to where it started.
## A headless window has no real pointer (and no canvas transform that follows the camera), so the world point under the
## pointer is worked out from the camera's place and zoom each tick and given to World.test_mouse (as tests/record_drive.gd does); the readout still sees real
## motion and button events through the viewport's GUI path, so World.ui_hold and the click route run as in play.
## What it measures per scenario, over ticks 120-199 (the click and the 1.2 s after it, pointer still on the readout):
##   turn    the most the hull's heading leaves its heading at tick 120 (degrees);
##   path    the total angle the heading turns through (degrees; a ship that flies around makes this big);
##   off     how many ticks the heading is more than 10 degrees from its heading at tick 120;
##   vturn   the angle between the velocity at tick 120 and at tick 199 (degrees).
## It fails a scenario when turn is over 3 degrees, or the click did nothing (shield zones and energy buttons 1-3).
## The first scenarios of the W and A key sets also print a line per tick (the trace).
## The approach (shield-aim-hold, Fri 2026-11-06): a click scenario also measures "drift", the angle the hull's heading turns
## through between the tick the pointer leaves the world spot (tick 60) and the tick the button goes down (tick 120), the
## turn the aim makes on the pointer's way down to the readout. It prints the mean and the worst of the drift over all the
## click scenarios. After the click scenarios three sweeps run with W held and the pointer on a straight path over about
## 1.1 s: "beside" (past the readout, 130 pixels above it, never near it), "through" (across the readout at its middle
## height, without stopping) and "short" (straight down at the readout's middle at the same pace, stopping 80 pixels above
## it). Each prints how many ticks World.ui_hold was on, how far the ship's face point was from the pointer's world point
## on the ticks it was off, and (through) how early the hold began before the pointer reached the readout.
## It fails when the mean drift is over MAX_DRIFT_MEAN_DEG or the worst over MAX_DRIFT_WORST_DEG (the hold must start
## before the pointer arrives); "beside" must never hold and must keep the face point on the pointer; "through" must hold
## before the pointer is inside; "short" must hold on the way and let go within 15 ticks of the pointer's stopping.
## Without the fix the ship, which holds a frozen WORLD point as its face point while the pointer is on the readout,
## chases that point as it flies (the hold keeps a world point, not a direction), and "turn" and "path" are big.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --test=shield_click_check
## It ends with "shield_click_check: N failures" (0 = all good) and quits. A run over 400 s of real time prints
## "shield_click_check: timeout".
##
## WHO USES IT: main.gd loads it for --test=shield_click_check. It reads the HUD (Hud, ShipStatus), the World and the
## human's ship; it moves the ship and sets its energy and shield state to set up each case.

## Physics ticks of one scenario.
const TICKS := 220
## The tick the pointer starts to travel onto the part.
const T_MOVE := 60
## The tick the pointer arrives on the part.
const T_ARRIVE := 90
## The tick the button goes down.
const T_PRESS := 120
## The tick the button goes up.
const T_RELEASE := 126
## The tick the pointer starts back.
const T_BACK := 200
## The tick the pointer is back where it started.
const T_HOME := 220
## The most the heading may turn after the click started (degrees) before a scenario fails.
const MAX_TURN_DEG := 3.0
## The most the mean drift of the click scenarios may be (degrees); the worst of them may not pass MAX_DRIFT_WORST_DEG.
## Measured with the hold's lead at 0.4 s: 28.3 and 43.8; with no lead 93.1 and 119.3.
const MAX_DRIFT_MEAN_DEG := 40.0
## The most the worst drift of the click scenarios may be (degrees).
const MAX_DRIFT_WORST_DEG := 60.0
## A heading further than this from the click's start counts as "off" (degrees).
const OFF_DEG := 10.0
## The tick a sweep's pointer starts, and the tick it arrives (60 ticks is a second; 90 ticks cover about 1.1 s).
const SW_START := 60
## The tick the "beside" and "through" sweeps arrive at their end ("short" is quicker: see _sw_end).
const SW_END := 150
## The key sets: each is a list of actions held together. W+S and A+D cancel each other, so they are left out.
const KEY_SETS := [
	["thrust_forward"], ["strafe_left"], ["thrust_back"], ["strafe_right"],
	["thrust_forward", "strafe_left"], ["thrust_forward", "strafe_right"],
	["thrust_back", "strafe_left"], ["thrust_back", "strafe_right"],
]

## The running match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many checks failed.
var failures := 0
## Where the human's ship is put at the start of each scenario.
var _start_pos := Vector2.ZERO
## The heading the human's ship is given at the start of each scenario (radians).
var _start_rot := 0.0
## The key set of the scenario that runs.
var _keys: Array = []
## The readout part the scenario that runs clicks ("shield_0", "energy_2", "balance").
var _part := ""
## The tick the scenario is on (-1: none is running).
var _t := -1
## Where the pointer starts (window pixels).
var _from := Vector2.ZERO
## Where the pointer goes: the middle of the part (window pixels).
var _to := Vector2.ZERO
## The hull's heading at each tick of this scenario (radians).
var _head: Array[float] = []
## The ship's velocity at each tick of this scenario.
var _vel: Array[Vector2] = []
## World.ui_hold at each tick of this scenario.
var _hold: Array[bool] = []
## The shield focus the ship had at the start of the scenario.
var _focus0 := 0
## The energy mode the ship had at the start of the scenario.
var _mode0 := 0
## How many traces have been printed for each key set.
var _traced := {}
## The drift (degrees) of each click scenario that ran (see the header).
var _drifts: Array[float] = []
## What the running scenario is: "click" (a part of the readout), or a sweep: "beside", "through" or "short".
var _kind := "click"
## The pointer's window pixel at each tick of this scenario.
var _ptr: Array[Vector2] = []
## How far the ship's face point was from the pointer's world point at each tick (world units).
var _dev: Array[float] = []
## Where a sweep's pointer starts (window pixels).
var _sw_a := Vector2.ZERO
## Where a sweep's pointer ends (window pixels).
var _sw_b := Vector2.ZERO
## The tick a sweep's pointer arrives at its end.
var _sw_end := SW_END


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run before the world's own tick, so a scenario's tick n is read by the tick after it.
	process_physics_priority = -1000


## Quit after 400 s of real time; start the check once the HUD exists and a ship flies.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 400000:
		print("shield_click_check: timeout")
		get_tree().quit()
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or hud.status == null or world.human == null or _ship() == null:
		return
	started = true
	_run()


## The whole check (see HOW IT WORKS), then the summary line and quit.
func _run() -> void:
	for i in 70:
		await get_tree().process_frame
	hud._close_others(null)
	# The pilot's camera is on the ship (the Centre latch), as in the user's note.
	world.camera.centre_latched = true
	var ship := _ship()
	var home := world.mothership(ship.team).global_position
	var foe := world.mothership(1 - ship.team).global_position
	var dir := (foe - home).normalized()
	_start_pos = home + dir * 1500.0
	_start_rot = dir.angle()
	print("shield_click_check: seat %s, start %s, heading %.1f deg" % [world.human_role, _start_pos, rad_to_deg(_start_rot)])
	for ks: Array in KEY_SETS:
		for part: String in _parts():
			await _scenario(ks, part)
	_print_drift()
	for kind: String in ["beside", "through", "short"]:
		await _sweep(kind)
	for a: String in ["thrust_forward", "thrust_back", "strafe_left", "strafe_right"]:
		Input.action_release(a)
	print("shield_click_check: %d failures" % failures)
	get_tree().quit()


## The parts to click, in order: the four shield zones, the four energy buttons, the ship icon.
func _parts() -> Array[String]:
	return ["shield_0", "shield_1", "shield_2", "shield_3", "energy_0", "energy_1", "energy_2", "energy_3", "balance"]


## The ship's own pixels of the middle of `part`, then the window pixels.
func _part_window_pos(part: String) -> Vector2:
	var st := hud.status
	var local := Vector2.ZERO
	if part == "balance":
		local = ShipStatus.DIAMOND_C
	elif part.begins_with("shield_"):
		var z := int(part.substr(7))
		local = ShipStatus.DIAMOND_C + Vector2.from_angle(float(ShipStatus.ZONE_ANGLE[z])) * 44.0
	else:
		var i := int(part.substr(7))
		var w := ShipStatus.W - ShipStatus.ROUTE_X - 10.0
		var bw := (w - 9.0) / 4.0
		local = Vector2(ShipStatus.ROUTE_X + float(i) * (bw + 3.0) + bw * 0.5, ShipStatus.ROUTE_Y + ShipStatus.ROUTE_H * 0.5)
	return st.get_global_rect().position + local


## One scenario: put the ship back, hold the keys, move the pointer, click, rest, go back, and score it.
func _scenario(keys: Array, part: String) -> void:
	var ship := await _prepare()
	if ship == null:
		print("FAIL %s %s: no live ship" % [keys, part])
		failures += 1
		return
	_kind = "click"
	_start_run(keys)
	_part = part
	_from = _ahead_screen(ship)
	_to = _part_window_pos(part)
	var hit := hud.status.part_at(_to - hud.status.get_global_rect().position)
	if hit != part:
		print("FAIL %s %s: the aim point lands on '%s'" % [keys, part, hit])
		failures += 1
	await _run_ticks(keys)
	_score(keys, part)
	# Let the pointer go back to the world and the button state settle before the next scenario.
	for i in 6:
		await get_tree().process_frame


## Put the ship back at the start (place, heading, full hull, balanced, no speed), wait for the camera, and return the
## ship (null when none lives).
func _prepare() -> Ship:
	var ship := _ship()
	if ship == null:
		return null
	# Set the ship up: the start place, heading and the full hull; no speed, no cooldowns, balanced.
	ship.global_position = _start_pos
	ship.rotation = _start_rot
	ship.velocity = Vector2.ZERO
	ship.controls.face_point = _start_pos + Vector2.from_angle(_start_rot) * 600.0
	ship.controls.aim_point = ship.controls.face_point
	ship.energy_cd = 0.0
	ship.focus_cd = 0.0
	ship.energy.mode = Rules.ENERGY_BALANCED
	ship.shields.set_focus(Rules.FOCUS_BALANCED)
	ship.stats_dirty = true
	ship.hull = ship.hull_max
	world.mouse_fire = false
	world.mouse_special = false
	_focus0 = ship.shields.focus
	_mode0 = ship.energy.mode
	# The camera follows the ship with a delay: wait until the ship's place on the screen stops moving.
	world.test_mouse = ship.global_position + Vector2.from_angle(_start_rot) * 500.0
	var last := Vector2(-1.0e9, -1.0e9)
	var still := 0
	for i in 400:
		await get_tree().process_frame
		var sp := _screen_of(ship.global_position)
		still = still + 1 if sp.distance_to(last) < 0.3 else 0
		last = sp
		if still >= 12:
			break
	return ship


## The window pixel of the world spot 500 units ahead of the ship (where the pointer starts), kept on the screen.
func _ahead_screen(ship: Ship) -> Vector2:
	var p := _screen_of(ship.global_position + Vector2.from_angle(_start_rot) * 500.0)
	return Vector2(clampf(p.x, 60.0, 1220.0), clampf(p.y, 60.0, 560.0))


## Clear the samples and name the keys of the scenario that is about to run.
func _start_run(keys: Array) -> void:
	_keys = keys
	_head.clear()
	_vel.clear()
	_hold.clear()
	_ptr.clear()
	_dev.clear()


## Hold the keys, run the scenario's ticks (_physics_process moves the pointer) and let the keys go.
func _run_ticks(keys: Array) -> void:
	for a: String in ["thrust_forward", "thrust_back", "strafe_left", "strafe_right"]:
		Input.action_release(a)
	for a: String in keys:
		Input.action_press(a)
	_t = 0
	while _t >= 0:
		await get_tree().physics_frame
	for a: String in keys:
		Input.action_release(a)


## One sweep (see the header): W held, the pointer on a straight path, then the numbers.
func _sweep(kind: String) -> void:
	var ship := await _prepare()
	if ship == null:
		print("FAIL sweep %s: no live ship" % kind)
		failures += 1
		return
	_kind = kind
	_part = ""
	_start_run(["thrust_forward"])
	var r := hud.status.get_global_rect()
	_sw_a = Vector2(40.0, r.position.y - 130.0)
	_sw_b = Vector2(1240.0, r.position.y - 130.0)
	if kind == "through":
		_sw_a = Vector2(r.position.x - 350.0, r.get_center().y)
		_sw_b = Vector2(r.end.x + 350.0, r.get_center().y)
	_sw_end = SW_END
	if kind == "short":
		# Straight down at the readout's middle, the same pace as the others (about 800 pixels a second), stopping short.
		_sw_b = Vector2(r.get_center().x, r.position.y - 80.0)
		_sw_a = _sw_b - Vector2(0.0, 400.0)
		_sw_end = SW_START + 30
	await _run_ticks(["thrust_forward"])
	if not _score_sweep(kind, r):
		failures += 1
	for i in 6:
		await get_tree().process_frame


## Each physics tick of a running scenario: move the pointer (and the world point it stands for), press or let go of
## the button, and take the sample of the tick before.
func _physics_process(_dt: float) -> void:
	if _t < 0:
		return
	var ship := _ship()
	if ship == null:
		_t = -1
		return
	# The sample of this tick (the world's tick runs after this node: priority), then the pointer for the next one.
	_head.append(ship.rotation)
	_vel.append(ship.velocity)
	_hold.append(world.ui_hold)
	if world.test_mouse != null:
		_dev.append(ship.controls.face_point.distance_to(world.test_mouse as Vector2))
	else:
		_dev.append(0.0)
	var line := ""
	if _traced.get(str(_keys), 0) < 2 and (_part == "shield_0" or _part == "energy_0") and (_t % 6 == 0 or (_t >= T_PRESS - 2 and _t <= T_RELEASE + 12)):
		line = "trace %s %s t=%03d head=%7.2f vel=(%7.1f,%7.1f) |v|=%6.1f vdir=%7.2f face=(%8.1f,%8.1f) fwd=%.1f str=%.1f hold=%s focus=%d mode=%d pos=(%.0f,%.0f) on_screen=(%.0f,%.0f)" % [
			_keys, _part, _t, rad_to_deg(ship.rotation), ship.velocity.x, ship.velocity.y, ship.velocity.length(), rad_to_deg(ship.velocity.angle()),
			ship.controls.face_point.x, ship.controls.face_point.y, ship.controls.forward, ship.controls.strafe, str(world.ui_hold), ship.shields.focus, ship.energy.mode, ship.global_position.x, ship.global_position.y, _screen_of(ship.global_position).x, _screen_of(ship.global_position).y]
	if line != "":
		print(line)
	# Where the pointer is for this tick.
	var pos := _pointer_at(_t)
	_ptr.append(pos)
	_move_pointer(pos)
	if _kind == "click":
		if _t == T_PRESS:
			_button(pos, true)
		elif _t == T_RELEASE:
			_button(pos, false)
	_t += 1
	if _t >= TICKS:
		_t = -1
		if _traced.get(str(_keys), 0) < 2 and (_part == "energy_0"):
			_traced[str(_keys)] = _traced.get(str(_keys), 0) + 2


## Where the pointer is at tick `t`: a click scenario goes from the world spot onto the part and back; a sweep goes
## from its start to its end in a straight line and stays there.
func _pointer_at(t: int) -> Vector2:
	if _kind != "click":
		return _sw_a.lerp(_sw_b, clampf(float(t - SW_START) / float(_sw_end - SW_START), 0.0, 1.0))
	if t >= T_BACK:
		return _to.lerp(_from, clampf(float(t - T_BACK) / float(T_HOME - T_BACK), 0.0, 1.0))
	if t >= T_MOVE:
		return _from.lerp(_to, clampf(float(t - T_MOVE) / float(T_ARRIVE - T_MOVE), 0.0, 1.0))
	return _from


## Move the pointer to window point `pos`: a motion event through the GUI path, and the world point under it for the
## game's aim (World.test_mouse), worked out from the camera's place and zoom as the real pointer's would be.
func _move_pointer(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)
	world.test_mouse = _world_of(pos)


## The left button down (`down`) or up at window point `pos`, through the viewport's GUI path.
func _button(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)


## Score the finished scenario: print its numbers and count a failure when the heading turned or the click did nothing.
func _score(keys: Array, part: String) -> void:
	var ship := _ship()
	var n := _head.size()
	if n < TICKS - 2:
		print("FAIL %s %s: only %d samples" % [keys, part, n])
		failures += 1
		return
	var h0 := _head[T_PRESS]
	var turn := 0.0
	var path := 0.0
	var off := 0
	for i in range(T_PRESS, T_BACK):
		var d := absf(rad_to_deg(angle_difference(h0, _head[i])))
		turn = maxf(turn, d)
		if d > OFF_DEG:
			off += 1
		if i > T_PRESS:
			path += absf(rad_to_deg(angle_difference(_head[i - 1], _head[i])))
	var app := 0.0
	for i in range(T_MOVE, T_PRESS):
		app = maxf(app, absf(rad_to_deg(angle_difference(_start_rot, _head[i]))))
	var vturn := 0.0
	if _vel[T_PRESS].length() > 1.0 and _vel[T_BACK - 1].length() > 1.0:
		vturn = absf(rad_to_deg(_vel[T_PRESS].angle_to(_vel[T_BACK - 1])))
	var drift := absf(rad_to_deg(angle_difference(_head[T_MOVE], _head[T_PRESS])))
	_drifts.append(drift)
	var first_hold := -1
	for i in range(T_MOVE, T_PRESS):
		if _hold[i]:
			first_hold = i
			break
	var speed := _vel[T_PRESS].length()
	var held := 0
	for i in range(T_PRESS, T_BACK):
		if _hold[i]:
			held += 1
	# Did the click do what the key does? (zones and the first three energy buttons; the icon and Balanced may change nothing)
	var acted := true
	var how := ""
	if ship != null:
		if part.begins_with("shield_"):
			acted = ship.shields.focus == int(part.substr(7)) + 1
			how = "focus %d" % ship.shields.focus
		elif part.begins_with("energy_") and part != "energy_3":
			acted = ship.energy.mode == ShipStatus.ROUTE_ORDER[int(part.substr(7))]
			how = "mode %d" % ship.energy.mode
	var ok := turn <= MAX_TURN_DEG and acted
	print("%s %s %s: turn %.1f deg, path %.1f deg, off %d ticks, vturn %.1f deg, approach turn %.1f deg, drift %.1f deg, hold from tick %d (arrive %d), speed %.0f, hold %d/%d ticks, click %s%s" % [
		"PASS" if ok else "FAIL", keys, part, turn, path, off, vturn, app, drift, first_hold, T_ARRIVE, speed, held, T_BACK - T_PRESS, "worked" if acted else "DID NOTHING", " (" + how + ")" if how != "" else ""])
	if not ok:
		failures += 1


## The mean and the worst drift of all the click scenarios (see the header), and the mean of each key set.
func _print_drift() -> void:
	if _drifts.is_empty():
		print("FAIL: no drift measured")
		failures += 1
		return
	var sum := 0.0
	var worst := 0.0
	for d: float in _drifts:
		sum += d
		worst = maxf(worst, d)
	var per := PackedStringArray()
	var n_parts := _parts().size()
	for k in KEY_SETS.size():
		var s := 0.0
		for i in n_parts:
			s += _drifts[k * n_parts + i]
		per.append("%s %.1f" % [str(KEY_SETS[k]), s / float(n_parts)])
	var mean := sum / float(_drifts.size())
	print("shield_click_check: approach drift mean %.1f deg, worst %.1f deg over %d scenarios (by key set: %s)" % [mean, worst, _drifts.size(), "; ".join(per)])
	if mean > MAX_DRIFT_MEAN_DEG or worst > MAX_DRIFT_WORST_DEG:
		print("FAIL: the hull turns too far on the pointer's way to the readout (mean %.1f deg over %.1f, worst %.1f deg over %.1f)" % [mean, MAX_DRIFT_MEAN_DEG, worst, MAX_DRIFT_WORST_DEG])
		failures += 1


## The numbers of a finished sweep (see the header): the ticks World.ui_hold was on, how many ticks the pointer was inside
## the readout (`r`), the hold's first tick against the pointer's first tick inside, the hold's last tick, the largest
## distance of the face point from the pointer's world point on the ticks the hold was off, the heading at the end.
func _score_sweep(kind: String, r: Rect2) -> bool:
	var held := 0
	var inside := 0
	var first_hold := -1
	var last_hold := -1
	var first_in := -1
	var dev_off := 0.0
	for i in range(1, _hold.size()):
		var in_r := r.has_point(_ptr[i - 1])
		if in_r:
			inside += 1
			if first_in < 0:
				first_in = i
		if _hold[i]:
			held += 1
			if first_hold < 0:
				first_hold = i
			last_hold = i
		elif not _hold[i - 1]:
			dev_off = maxf(dev_off, _dev[i])
	print("sweep %s: held %d ticks (first %d, last %d), pointer inside the readout %d ticks (first %d), face point off the pointer by up to %.2f units on free ticks, heading at tick 105 %.2f and at the end %.2f deg, speed at the end %.0f" % [
		kind, held, first_hold, last_hold, inside, first_in, dev_off, rad_to_deg(_head[105]), rad_to_deg(_head[_head.size() - 1]), _vel[_vel.size() - 1].length()])
	var ok := true
	if kind == "beside":
		ok = held == 0 and dev_off < 0.5
	elif kind == "through":
		ok = first_hold > 0 and first_in > 0 and first_hold < first_in
	elif kind == "short":
		var late := 0
		for i in range(_sw_end + 15, _hold.size()):
			if _hold[i]:
				late += 1
		ok = held > 0 and late == 0 and dev_off < 0.5
	if not ok:
		print("FAIL sweep %s: the aim hold is wrong (see the line above)" % kind)
	return ok


## The human's live ship, or null.
func _ship() -> Ship:
	var h := world.human
	if h == null or h.ship == null or not is_instance_valid(h.ship) or not h.ship.alive:
		return null
	return h.ship


## The window pixel that world point p is drawn at, with the camera where it is (the camera sits in the middle of the window).
func _screen_of(p: Vector2) -> Vector2:
	var cam := world.camera
	return (p - cam.global_position) * cam.zoom.x + get_viewport().get_visible_rect().size * 0.5


## The world point under window pixel s: the inverse of _screen_of().
func _world_of(s: Vector2) -> Vector2:
	var cam := world.camera
	return cam.global_position + (s - get_viewport().get_visible_rect().size * 0.5) / cam.zoom.x
