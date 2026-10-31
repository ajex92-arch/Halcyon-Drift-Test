extends Node
## WHAT THIS IS: the paused-camera check. While the match is paused (P) the camera
## must still pan, zoom and follow, and nothing of the match may change: not the
## match clock, not a single unit, ship, shot or treasury, and the match must go on
## from the same place when it is unpaused. While the note box (F9) is open, typed
## keys must not move the camera.
##
## HOW IT WORKS: setup() gives the human a fighter that stays in the hangar. Then
## _physics_process() runs numbered steps, one after another, as
## tests/camera_check.gd does; this node keeps running while the game is paused
## (PROCESS_MODE_ALWAYS), because it is the one that unpauses. The steps:
##   - A (docked, so W / A / S / D pan): park the camera, write down a fingerprint
##     of the whole match (every unit's place, every pilot, both treasuries, the
##     shots) and the camera, pause, hold "move right" and "zoom in" and roll the
##     wheel for half a second, and check that the camera moved and zoomed while
##     the fingerprint, the clock and every unit's place are exactly as they were;
##     then unpause and check the clock goes on.
##   - B (flying): launch, hold W until the ship is moving, pause with W held: the
##     camera pans but the ship stands still; unpause and the ship goes on.
##   - C (follow): put the camera far from the ship in follow mode, pause, and check
##     it glides to the ship while paused.
##   - D (the note box, needs --force-hud): open it, hold D, W and = down for half a
##     second and check that the camera did not move; cancel it, hold D again and
##     check that the camera moves.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-admiral-ai --force-hud --test=camera_pause_check
## Without --force-hud step D is skipped (the note box lives in the HUD). In a window,
## --shots=<folder> also saves pictures of the screen before the first pause and after
## the zoom and the pan while paused (a_before.png, a_paused.png, b_paused.png), to look
## at how a paused match is drawn.
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what>
## <detail>". The last line is "camera_pause_check: N failures"; 0 means every check
## passed.
##
## WHO USES IT: main.gd loads it for --test=camera_pause_check. It drives CameraRig
## (scripts/camera/camera_rig.gd) with input actions and events and reads the match.

## Where the camera is parked before the first pause: far from everything.
const FAR_A := Vector2(30000, 4200)
## Where the ship hovers when it is launched.
const SPOT_A := Vector2(9000, MapLayout.CY)
## Frames the camera is given to settle in a spot.
const SETTLE_FRAMES := 90
## Frames the input is held while paused.
const HOLD_FRAMES := 30
## The least a held key must pan the camera in HOLD_FRAMES (world units).
const MIN_PAN := 100.0

## The running match (set by setup()).
var world: World
## The match's camera.
var cam: CameraRig
## The HUD (null without --force-hud).
var hud: Hud = null
## The human's ship once the test has launched it.
var ship: Ship = null
## Which step of the test we are on (see _physics_process).
var step := 0
## Frames since the current step began.
var step_frames := 0
## How many checks failed so far.
var fails := 0
## What the match looked like when the pause began: its fingerprint,
var _print0 := ""
## the match clock (seconds),
var _t0 := 0.0
## the places of the units,
var _places0 := PackedVector2Array()
## the camera's place,
var _cam0 := Vector2.ZERO
## the camera's zoom,
var _zoom0 := 0.0
## the ship's place
var _ship0 := Vector2.ZERO
## and the ship's velocity.
var _vel0 := Vector2.ZERO


## main.gd calls this once, right after the World is built. Run while paused too,
## let input events arrive at once, stop the minion waves and give the human a
## fighter (it stays in the hangar, so W / A / S / D pan the camera).
func setup(w: World) -> void:
	world = w
	cam = w.camera
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.use_accumulated_input = false
	world.minion_director.next_wave = INF
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	# A windowless run's mouse sits in the screen corner, where the edge pan and
	# the follow camera's edge peek would act: put it in the middle.
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * (get_viewport().get_visible_rect().size * 0.5)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	world.human.credits = 2000.0
	world.human.buy_hull("fighter", world.teams[0])
	# For the pictures: close the hangar, which opens over the whole match at the start.
	if hud != null and str(Game.opt("shots", "")) != "":
		hud._close_others(null)


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Move on to the next step and restart the frame count.
func _next() -> void:
	step += 1
	step_frames = 0


## The places of all live units, in list order.
func _places() -> PackedVector2Array:
	var out := PackedVector2Array()
	for u: Unit in world.units:
		if u.alive:
			out.append(u.global_position)
	return out


## One text that changes if anything about the match changes (the fingerprint of
## tests/det_hash.gd): every live unit, every pilot, both treasuries, the shots.
func _fingerprint() -> String:
	var parts := PackedStringArray()
	for u: Unit in world.units:
		if u.alive:
			parts.append("%d:%d:%f,%f:%f" % [u.kind, u.team, u.global_position.x, u.global_position.y, u.hull])
	for p: PilotProfile in world.profiles:
		parts.append("%s:%f:%s" % [p.callsign, p.credits, p.state])
	for t in 2:
		parts.append("tr%d:%f" % [t, world.teams[t].treasury])
	parts.append("proj:%d" % world.projectiles.count())
	return "%d units, %08x" % [world.units.size(), hash("|".join(parts))]


## Write down the match and the camera, as they are as the pause begins.
func _snapshot() -> void:
	_print0 = _fingerprint()
	_t0 = world.time
	_places0 = _places()
	_cam0 = cam.global_position
	_zoom0 = cam.zoom.x
	if ship != null and is_instance_valid(ship):
		_ship0 = ship.global_position
		_vel0 = ship.velocity


## Check that the match is exactly as _snapshot() found it.
func _check_match_frozen(what: String) -> void:
	_check("%s: the match clock stands still" % what, world.time == _t0, "%.6f -> %.6f" % [_t0, world.time])
	_check("%s: every unit is where it was (%d units)" % [what, _places0.size()], _places() == _places0)
	_check("%s: nothing of the match changed (units, pilots, treasuries, shots)" % what, _fingerprint() == _print0, "%s -> %s" % [_print0, _fingerprint()])


## Press key `code` down (`down` true) or let it go, as a keyboard does (the Input
## state follows, so "move right" and the rest read it).
func _key(code: Key, down: bool, unicode: int = 0) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	ev.unicode = unicode
	Input.parse_input_event(ev)


## Save a picture of the screen as `name` in the --shots folder, in a window only.
## It waits for the next drawn frame, so it shows what the screen holds then.
func _shot(name: String) -> void:
	var dir := str(Game.opt("shots", ""))
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


## Godot calls this every frame, paused or not.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	step_frames += 1
	match step:
		# A: park the camera far away and let the match run a few seconds.
		0:
			if step_frames == 1:
				cam.look_at_point(world.mothership(0).global_position + Vector2(1200, 0) if str(Game.opt("shots", "")) != "" else FAR_A)
			if step_frames >= SETTLE_FRAMES:
				_next()
		# A: write everything down, pause, and hold the pan and zoom input.
		1:
			_snapshot()
			_shot("a_before")
			get_tree().paused = true
			Input.action_press("strafe_right")
			Input.action_press("zoom_in")
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			Input.parse_input_event(wheel)
			_next()
		# A: half a second later the camera has moved and zoomed, the match has not.
		2:
			if step_frames >= HOLD_FRAMES:
				_check("A paused, docked: the camera pans (moved %.0f)" % _cam0.distance_to(cam.global_position), _cam0.distance_to(cam.global_position) > MIN_PAN)
				_check("A paused, docked: the camera zooms in (%.4f -> %.4f)" % [_zoom0, cam.zoom.x], cam.zoom.x > _zoom0 + 0.0001)
				_check_match_frozen("A paused, docked")
				_shot("a_paused")
				Input.action_release("strafe_right")
				Input.action_release("zoom_in")
				get_tree().paused = false
				_next()
		# A: unpaused, the match goes on from the same place.
		3:
			if step_frames >= HOLD_FRAMES:
				_check("A unpaused: the match clock goes on (%.3f -> %.3f)" % [_t0, world.time], world.time > _t0 + 0.4)
				_check("A unpaused: it goes on from where it stood (not a frame of lost or doubled time)", absf((world.time - _t0) - float(HOLD_FRAMES) / 60.0) < 0.1, "%.4f s of match in %d frames" % [world.time - _t0, HOLD_FRAMES])
				# B: launch the human's ship, still, and hold W so it builds speed.
				ship = world.launch(world.human)
				ship.global_position = SPOT_A
				ship.velocity = Vector2.ZERO
				cam.look_at_point(SPOT_A)
				Input.action_press("thrust_forward")
				_next()
		# B: after 45 frames of W the ship is moving: pause with W held.
		4:
			if step_frames >= 45:
				_snapshot()
				_check("B flying: the ship is moving before the pause (%.0f)" % _vel0.length(), _vel0.length() > 50.0)
				get_tree().paused = true
				_next()
		# B: paused with W held: the camera pans, the ship does not move.
		5:
			if step_frames >= HOLD_FRAMES:
				_check("B paused, flying: W pans the camera (moved %.0f)" % _cam0.distance_to(cam.global_position), _cam0.distance_to(cam.global_position) > MIN_PAN)
				_check("B paused, flying: the ship stands still and keeps its speed", ship.global_position == _ship0 and ship.velocity == _vel0, "%s %s" % [str(ship.global_position - _ship0), str(ship.velocity - _vel0)])
				_check_match_frozen("B paused, flying")
				_shot("b_paused")
				Input.action_release("thrust_forward")
				get_tree().paused = false
				_next()
		# B: unpaused, the ship flies on.
		6:
			if step_frames >= HOLD_FRAMES:
				_check("B unpaused: the ship flies on (moved %.0f)" % _ship0.distance_to(ship.global_position), _ship0.distance_to(ship.global_position) > 20.0)
				# C: the camera in follow mode, far from the ship, then pause.
				cam.free = false
				cam.global_position = ship.global_position + Vector2(3000, 1000)
				_cam0 = cam.global_position
				_snapshot()
				get_tree().paused = true
				_next()
		# C: paused, the follow camera glides to the ship.
		7:
			if step_frames >= 120:
				var d0 := _cam0.distance_to(ship.global_position)
				var d1 := cam.global_position.distance_to(ship.global_position)
				_check("C paused, follow: the camera glides to the ship (%.0f -> %.0f away)" % [d0, d1], d1 < d0 - 800.0)
				_check_match_frozen("C paused, follow")
				cam.free = true
				get_tree().paused = false
				_next()
		# D: the note box.
		8:
			if hud == null:
				print("camera_pause_check: SKIP D (no HUD: use --force-hud)")
				step = 99
				return
			hud._open_note()
			_snapshot()
			_check("D the note box pauses the match", get_tree().paused and hud._note_is_open())
			_key(KEY_D, true, int("d".unicode_at(0)))
			_key(KEY_W, true, int("w".unicode_at(0)))
			_key(KEY_EQUAL, true, int("=".unicode_at(0)))
			_next()
		9:
			if step_frames >= HOLD_FRAMES:
				_check("D typing in the note box: the camera does not pan (moved %.1f)" % _cam0.distance_to(cam.global_position), _cam0.distance_to(cam.global_position) < 0.01)
				_check("D typing in the note box: the camera does not zoom (%.4f -> %.4f)" % [_zoom0, cam.zoom.x], absf(cam.zoom.x - _zoom0) < 0.000001)
				_check("D typing in the note box: the keys went to the text (%s)" % hud.note_box.text(), hud.note_box.text().contains("d"))
				for code: Key in [KEY_D, KEY_W, KEY_EQUAL]:
					_key(code, false)
				hud.note_box.cancel()
				_check("D the note box is closed and the match runs again", not hud._note_is_open() and not get_tree().paused)
				# With the box closed the same keys pan again (pause once more: a flying ship's W and D steer it).
				get_tree().paused = true
				_cam0 = cam.global_position
				Input.action_press("strafe_right")
				_next()
		10:
			if step_frames >= HOLD_FRAMES:
				Input.action_release("strafe_right")
				get_tree().paused = false
				_check("D after the box is closed the keys pan the camera again (moved %.0f)" % _cam0.distance_to(cam.global_position), _cam0.distance_to(cam.global_position) > MIN_PAN)
				step = 99
		99:
			print("camera_pause_check: %d failures" % fails)
			get_tree().quit()
