extends Node
## WHAT THIS IS: the check of the Admiral's fleet wheel and its build strip (OrderWheel, BuildStrip, FieldOrders, the field_*
## calls of Hud, HudInput's X handling by seat, RadialMenu), and of the pilot's X wheel next to it. The Admiral run
## flies a Fighter of its own, with two squadrons beside the mothership, and checks, one line each:
##   (a) X held past 130 ms opens the fleet wheel (never the wing wheel) and holds the aim (wheel_hold); let go over Move it
##       gives one MOVE order for the selected squadrons (every squadron when none is selected) at the world point the
##       mouse was on when X went down; over Stop one STOP; over Hold one HOLD for each squadron; over a dim slice or the
##       dead zone no order (a dim slice says "later stage"); the control: with the wheel closed, letting go of X gives none;
##   (b) a tap of X: the smart order (open ground gives MOVE, an enemy ATTACK), and with nothing selected no order and no pop-up;
##   (c) Esc closes the wheel with no order and wheel_hold goes false;
##   (d) docking while the wheel is open closes it;
##   (f) in field mode, and again in mode 3 (the command view open): a left click on a slice or on a strip cell sets no
##       mouse_fire and the ship's controls.fire stays false (the control: with the wheel closed the same click in field
##       mode does fire), and a click on a cell leaves the selection alone;
##   (g) keys 1 to 4 with the wheel open leave the ship's energy alone (the control: with it closed they route energy);
##   (h) the strip: key 2 queues one Fighter squadron, Shift+2 queues up to the cap, Alt+2 turns repeat on, a locked hull
##       answers with the queue's refusal and the research board stays shut, a click on a cell queues too, and the same
##       digits with the wheel closed queue nothing;
##   (k) a middle click at an enemy marks it as the target with the wheel closed, and with the wheel open it marks it too (the
##       open wheel passes the press to HudInput; the wheel stays open and files no order), and a middle drag that is still going
##       when the wheel opens ends there: the camera does not move with the mouse afterwards;
##   (i) the fit at 1280x720: for the wheel's middle at the four corners and the middle of the window, the ring and the strip
##       lie inside the window with 8 pixels to spare, the text is 14 pixels or more, each slice's label is no wider than
##       the slice's chord at the label's radius, and each strip cell holds its two lines;
##   (j) RadialMenu.slice_at for six slices names the same slice as WingWheel.hit_at at 24 angles (7.5 + 15 k degrees, never
##       on a slice's edge), and for eight slices the same slice as OrderWheel.hit_at (at 10.5 + 15 k degrees, also off every edge);
##   (l) a middle drag of the free camera whose release a cover takes (the note box, the pause menu, the help pages, the Controls
##       page, the hangar, and in the Admiral's seat the board) is over once the button is up: the camera does not follow a mouse
##       move afterwards (the control: a held button keeps the drag, and its release ends it).
## The pilot run (--role=pilot with a wing) does case (e): X held past 130 ms opens the wing wheel and never the fleet wheel,
## and checks that a middle click at an enemy with the wing wheel open marks it, with the wheel still open. It does (l) too.
##
## HOW IT WORKS: it waits for the HUD, makes the window 1280 x 720, launches the Admiral's ship and then runs the cases
## in order from one function. The X key and Esc go through HudInput.handle() (the order key times itself in real
## milliseconds, so the check waits that long), the mouse moves and clicks are real mouse events, the digits of (g) real key
## events (they reach the game's input state, which is how energy is read) and those of (h) go through HudInput.handle(). Each order is read from the order
## queue the moment it is filed (before the next tick carries it out).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-pilots --no-admiral-ai --force-hud --test=field_wheel_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --test-wing --seed=7 --test=field_wheel_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what> <detail>", the fit numbers, then
## "field_wheel_check: N failures" and a PROBE_JSON line. 0 failures means every check passed.
##
## WHO USES IT: main.gd loads it for --test=field_wheel_check. It reads Hud, HudInput, OrderWheel, BuildStrip, FieldOrders,
## RadialMenu, WingWheel and the order queue.

## The text the check puts in the HUD's pop-up before it acts, so a pop-up that shows afterwards can be told from it.
const MARK := "(probe)"
## The window size the fit is measured at.
const WINDOW := Vector2i(1280, 720)

## The running match (set by setup()).
var world: World
## The HUD (found once it exists).
var hud: Hud
## The seat: "pilot", "admiral" or "spectator".
var role := ""
## The Admiral's ship once launched.
var ship: Ship
## The first of the two squadrons of ours.
var squad_a: Squad
## The second.
var squad_b: Squad
## How many checks failed.
var fails := 0
## The point of open ground the orders are aimed at.
var ground := Vector2.ZERO
## Where the enemy squadron stands.
var foe_at := Vector2.ZERO


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	role = w.human_role
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.minion_director.next_wave = INF
	if role == "admiral" and world.human != null:
		world.teams[world.human_team].facilities["frigate"] = true
		world.human.credits = 6000.0
		var err := world.human.buy_hull("fighter", world.teams[world.human_team])
		if err != "":
			_check("the human can buy a Fighter", false, err)
	_run()


## A real-time guard: a check that has not finished within 150 seconds says so and quits.
func _process(_dt: float) -> void:
	if world != null and Time.get_ticks_msec() > 150000:
		print("field_wheel_check: timeout")
		get_tree().quit()


## Print one PASS or FAIL line for the check `what`, with the measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


# --- little helpers --------------------------------------------------------------------------------------

## Wait `n` ticks of the World.
func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait `ms` real milliseconds on the clock the order key times itself with, a frame at a time, then two frames more.
func _real_wait(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	await _frames(2)


## A key event for `code` (pressed or let go), with the modifiers named.
func _key(code: Key, pressed: bool, shift: bool = false, alt: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


## Move the mouse to the HUD point `p` (pixels) as a real mouse does, and let two frames deliver it.
func _mouse_to(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * p
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


## The left mouse button down or up at HUD point `p`.
func _click(p: Vector2, down: bool) -> void:
	var win := get_viewport().get_final_transform() * p
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = win
	ev.global_position = win
	Input.parse_input_event(ev)


## The middle mouse button down or up at HUD point `p`.
func _middle(p: Vector2, down: bool) -> void:
	var win := get_viewport().get_final_transform() * p
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = down
	ev.position = win
	ev.global_position = win
	Input.parse_input_event(ev)


## A real middle click at HUD point `p`: the press, three ticks (a real event reaches the game on the next frame), the release
## and three ticks more.
func _middle_click(p: Vector2) -> void:
	_middle(p, true)
	await _ticks(3)
	_middle(p, false)
	await _ticks(3)


## The point of slice `i`'s middle (pixels, the HUD's space) of the open fleet wheel.
func _slice_point(i: int) -> Vector2:
	var mid := deg_to_rad(-90.0 + 45.0 * float(i))
	return hud.order_wheel.center + Vector2.from_angle(mid) * ((OrderWheel.DEAD_R + OrderWheel.RING_R) * 0.5)


## The point (pixels, the HUD's space) of strip cell `i`'s middle.
func _cell_point(i: int) -> Vector2:
	return hud.order_wheel.strip_rect().position + BuildStrip.cell_rect(i).get_center()


## Hold X until the fleet wheel is open (real milliseconds), with the mouse put at `at` first. Returns true when it opened.
func _open_wheel(at: Vector2) -> bool:
	await _mouse_to(at)
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(250)
	return hud.order_wheel.is_open


## Let go of X (the wheel closes, giving the order under the mouse, if any).
func _release_x() -> void:
	hud.router.handle(_key(KEY_X, false))


## The orders filed since the order queue's counter stood at `id0`, as the queue holds them (nothing has been carried out yet).
func _orders_since(id0: int) -> Array:
	var out: Array = []
	for o: Dictionary in world.orders.queue:
		if int(o["id"]) >= id0:
			out.append(o)
	return out


## Do the two lists hold the same ids in the same order (a typed and an untyped list compare by what they hold)?
func _ids_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true


## The kinds of `orders`, as one line.
func _kinds(orders: Array) -> String:
	var out := PackedStringArray()
	for o: Dictionary in orders:
		out.append("%s%s" % [str(o["kind"]), str(o["subjects"])])
	return ",".join(out)


## A new bought squadron of `n` crew ships of hull "fighter" for `team`, placed at `at` (null controllers: they sit still).
func _squad(team: int, n: int, at: Vector2) -> Squad:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = "squadron"
	s.hull_id = "fighter"
	s.max_members = 3
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	for i in n:
		var p := Crew.make(world, team, "fighter", s, s.member_uids.size())
		world.profiles.append(p)
		var sh := world.spawner.spawn_pilot_ship(p, at + Vector2(float(i) * 60.0, 0.0), 0.0)
		sh.controller = null
		sh.velocity = Vector2.ZERO
		p.ship = sh
		p.state = "flying"
		s.member_uids.append(sh.uid)
	return s


## Wait for the HUD, then run the seat's cases.
func _run() -> void:
	for i in 1200:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.order_wheel != null and hud.command_view != null:
			break
		await get_tree().process_frame
	if hud == null:
		_check("the HUD exists (run with --force-hud)", false)
		_finish()
		return
	get_tree().root.size = WINDOW
	await _frames(10)
	if role == "admiral" and world.human != null:
		await _admiral_cases()
	elif role == "pilot" and world.human != null:
		await _pilot_case()
	else:
		print("SKIP field_wheel_check: only an Admiral or a pilot has an order wheel")
	_finish()


## Print the total and quit.
func _finish() -> void:
	print("field_wheel_check: %d failures" % fails)
	print("PROBE_JSON %s" % JSON.stringify({"test": "field_wheel_check", "role": role, "failures": fails}))
	get_tree().quit()


# --- the pilot's seat ------------------------------------------------------------------------------------

## Case (e): in the pilot's seat X held past 130 ms opens the wing wheel and never the fleet wheel.
func _pilot_case() -> void:
	var wing := hud.wing_wheel
	for i in 1800:
		hud._close_others(null)
		var flying := world.human.ship != null and is_instance_valid(world.human.ship) and world.human.ship.alive
		if flying and hud.wing_strip != null and hud.wing_strip.visible and hud.wing_ready():
			break
		await get_tree().process_frame
	await _frames(12)
	_check("(e) the pilot's order key is ready and the Admiral's is not", hud.wing_ready() and not hud.field_ready())
	await _mouse_to(Vector2(640.0, 330.0))
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(300)
	_check("(e) X held opens the wing wheel", wing.is_open and world.wheel_hold)
	_check("(e) and never the fleet wheel", not hud.order_wheel.is_open and not hud.order_wheel.visible)
	hud.router.handle(_key(KEY_X, false))
	_check("(e) letting go in the middle closes the wing wheel", not wing.is_open and not world.wheel_hold)
	_check("(e) the fleet wheel stayed shut", not hud.order_wheel.is_open)
	# The control: the same hold with the wheel's own gate closed (a panel open) opens nothing.
	hud._toggle_help()
	await _frames(2)
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(300)
	_check("(e) control: with the help open the X hold opens no wheel", not wing.is_open and not hud.order_wheel.is_open)
	hud.router.handle(_key(KEY_X, false))
	hud._toggle_help()
	await _frames(2)
	await _pilot_middle_probe()
	await _cover_drag_cases()


## The pilot's middle click at an enemy with the wing wheel open (the same shape as case (k)): the enemy is marked and the wheel
## stays open.
func _pilot_middle_probe() -> void:
	var me := world.human.ship
	if me == null or not is_instance_valid(me):
		_check("(e) the pilot has a ship for the middle click", false, "")
		return
	var team := world.human_team
	var at := me.global_position + Vector2(380.0, 40.0)
	var foe := _squad(1 - team, 1, at)
	await _ticks(3)
	var foe_ship: Ship = world.by_uid.get(foe.member_uids[0])
	if foe_ship == null:
		_check("(e) the enemy for the middle click is there", false, "")
		return
	foe_ship.visible_mask |= 1 << team
	var foe_uid := foe_ship.uid
	world.test_mouse = at
	me.controls.target_id = TargetKeys.NONE
	var click_p := Vector2(900.0, 200.0)
	await _mouse_to(Vector2(640.0, 330.0))
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(300)
	_check("(e) the wing wheel is open for the middle click", hud.wing_wheel.is_open, "")
	await _middle_click(click_p)
	_check("(e) with the wing wheel open a middle click at an enemy marks it", me.controls.target_id == foe_uid, "%d, the enemy is %d" % [me.controls.target_id, foe_uid])
	_check("(e) and the wing wheel is still open", hud.wing_wheel.is_open, "")
	hud.wing_wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	if is_instance_valid(me):
		me.controls.target_id = TargetKeys.NONE


# --- the Admiral's seat ----------------------------------------------------------------------------------

## The cases (a) to (d) and (f) to (j).
func _admiral_cases() -> void:
	var ts: TeamState = world.teams[world.human_team]
	var ov := hud.overlay
	var team := world.human_team
	ship = world.launch(world.human)
	if ship == null:
		_check("the Admiral launched a Fighter", false)
		return
	hud._close_others(null)
	await _ticks(10)
	_check("the Admiral is flying and may give a field order", hud.field_ready() and not hud.wing_ready())
	ground = ship.global_position + Vector2(0.0, -900.0)
	foe_at = ship.global_position + Vector2(380.0, 40.0)
	var ms := world.mothership(team)
	squad_a = _squad(team, 2, ms.global_position + Vector2(-500.0, 500.0))
	squad_b = _squad(team, 2, ms.global_position + Vector2(-500.0, 700.0))
	var all_ids: Array[int] = [squad_a.id, squad_b.id]
	await _ticks(5)
	var wing := hud.wing_wheel
	var wheel := hud.order_wheel
	var middle := Vector2(640.0, 330.0)

	# --- (a) the hold and the order under the mouse ---------------------------------------------------------
	world.test_mouse = ground
	ov.clear_selection()
	var id0 := world.orders.next_id
	_release_x()
	_check("(a) control: letting go of X with the wheel closed gives no order", world.orders.next_id == id0 and not wheel.is_open)
	var opened := await _open_wheel(middle)
	_check("(a) X held past 130 ms opens the fleet wheel and holds the aim", opened and world.wheel_hold and wheel.visible, "open %s" % opened)
	_check("(a) and never the wing wheel", not wing.is_open and not wing.visible)
	_check("(a) the strip shows under the ring", wheel.strip.visible and wheel.strip_rect().position.y >= wheel.center.y + OrderWheel.RING_R)
	world.test_mouse = ground + Vector2(2500.0, 0.0)
	await _mouse_to(_slice_point(1))
	_check("(a) the mouse is over Move here", str(wheel.hovered().get("name", "")) == "move", str(wheel.hovered()))
	id0 = world.orders.next_id
	_release_x()
	var got := _orders_since(id0)
	_check("(a) Move with nothing selected: one MOVE for every squadron at the press aim", got.size() == 1 and str(got[0]["kind"]) == OrderKinds.MOVE and _ids_equal(got[0]["subjects"], all_ids) and got[0]["target"] == Order.point(ground), _kinds(got))
	_check("(a) the wheel closed and the aim is free again", not wheel.is_open and not world.wheel_hold and not wheel.strip.visible)
	await _ticks(3)
	hud.toast_box.hide()
	# With a selection: only that squadron.
	world.test_mouse = ground
	ov.set_selection([squad_b.id], false)
	await _open_wheel(middle)
	await _mouse_to(_slice_point(1))
	id0 = world.orders.next_id
	_release_x()
	got = _orders_since(id0)
	_check("(a) Move with squadron B selected: one MOVE for B only", got.size() == 1 and str(got[0]["kind"]) == OrderKinds.MOVE and _ids_equal(got[0]["subjects"], [squad_b.id]), _kinds(got))
	await _ticks(3)
	# Stop.
	await _open_wheel(middle)
	await _mouse_to(_slice_point(3))
	id0 = world.orders.next_id
	_release_x()
	got = _orders_since(id0)
	_check("(a) Stop: one STOP for the selection", got.size() == 1 and str(got[0]["kind"]) == OrderKinds.STOP and _ids_equal(got[0]["subjects"], [squad_b.id]), _kinds(got))
	await _ticks(3)
	# Hold: one HOLD for each squadron, at its centre.
	ov.clear_selection()
	await _open_wheel(middle)
	await _mouse_to(_slice_point(2))
	id0 = world.orders.next_id
	_release_x()
	got = _orders_since(id0)
	var hold_ok := got.size() == 2
	for o: Dictionary in got:
		hold_ok = hold_ok and str(o["kind"]) == OrderKinds.HOLD and (o["subjects"] as Array).size() == 1
	_check("(a) Hold with nothing selected: one HOLD for each of the two squadrons", hold_ok, _kinds(got))
	if got.size() == 2:
		_check("(a) each HOLD is at its squadron's centre", got[0]["target"] == Order.point(RtsSelect.centre_of(world, squad_a)) and got[1]["target"] == Order.point(RtsSelect.centre_of(world, squad_b)))
	await _ticks(3)
	# The lit slices Defend here, Escort me and Push this lane (4, 5, 7) each give their order (RT12).
	world.test_mouse = Vector2(18800.0, 14200.0)
	var lit := [[4, OrderKinds.DEFEND], [5, OrderKinds.ESCORT], [7, OrderKinds.PUSH_LANE]]
	for pair: Array in lit:
		await _open_wheel(middle)
		await _mouse_to(_slice_point(int(pair[0])))
		id0 = world.orders.next_id
		_release_x()
		got = _orders_since(id0)
		_check("(a) slice %d (%s) is lit: one %s order" % [int(pair[0]), str((OrderWheel.SLICES[int(pair[0])] as Array)[0]), str(pair[1])], got.size() == 1 and str(got[0]["kind"]) == str(pair[1]), _kinds(got))
		await _ticks(3)
	# A dim slice and the dead zone: no order, and the dim one says "later stage".
	for i in [0, 6]:
		await _open_wheel(middle)
		await _mouse_to(_slice_point(i))
		hud.toast_box.show_text(MARK)
		id0 = world.orders.next_id
		_release_x()
		_check("(a) slice %d (%s) is dim: no order, and the pop-up says it comes later" % [i, str((OrderWheel.SLICES[i] as Array)[0])], world.orders.next_id == id0 and hud.toast_box._label.text == OrderKinds.TEXT_UNBUILT and hud.toast_box._danger, "%s / %s" % [hud.toast_box._label.text, str(world.orders.next_id - id0)])
	await _open_wheel(middle)
	await _mouse_to(wheel.center)
	id0 = world.orders.next_id
	_release_x()
	_check("(a) letting go in the dead zone gives no order and closes the wheel", world.orders.next_id == id0 and not wheel.is_open and not world.wheel_hold)

	# --- (b) the tap: the smart order ------------------------------------------------------------------------
	await _ticks(3)
	await _mouse_to(middle)
	ov.set_selection([squad_a.id], false)
	world.test_mouse = ground
	hud.toast_box.show_text(MARK)
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_X, true))
	hud.router.handle(_key(KEY_X, false))
	got = _orders_since(id0)
	_check("(b) a tap on open ground with A selected: one MOVE for A", got.size() == 1 and str(got[0]["kind"]) == OrderKinds.MOVE and _ids_equal(got[0]["subjects"], [squad_a.id]) and got[0]["target"] == Order.point(ground), _kinds(got))
	_check("(b) and the pop-up says so", hud.toast_box._label.text.begins_with("Move: 1 squadron"), hud.toast_box._label.text)
	await _ticks(3)
	var foe := _squad(1 - team, 1, foe_at)
	await _ticks(3)
	var foe_ship: Ship = world.by_uid.get(foe.member_uids[0])
	# The fog is not what this case tests: mark the enemy as seen by our team (the tap picks only an enemy the team sees).
	if foe_ship != null:
		foe_ship.visible_mask |= 1 << team
	_check("(b) the enemy squadron is there and visible to us", foe_ship != null and foe_ship.visible_to(team), "")
	world.test_mouse = foe_at
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_X, true))
	hud.router.handle(_key(KEY_X, false))
	got = _orders_since(id0)
	_check("(b) a tap on an enemy with A selected: one ATTACK", got.size() == 1 and str(got[0]["kind"]) == OrderKinds.ATTACK and _ids_equal(got[0]["subjects"], [squad_a.id]), _kinds(got))
	await _ticks(3)
	ov.clear_selection()
	world.test_mouse = ground
	hud.toast_box.show_text(MARK)
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_X, true))
	hud.router.handle(_key(KEY_X, false))
	_check("(b) a tap with nothing selected: no order and no pop-up", world.orders.next_id == id0 and hud.toast_box._label.text == MARK, hud.toast_box._label.text)

	# --- (c) Esc ---------------------------------------------------------------------------------------------
	await _ticks(3)
	opened = await _open_wheel(middle)
	_check("(c) control: the wheel is open before Esc", opened and world.wheel_hold)
	await _mouse_to(_slice_point(1))
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_ESCAPE, true))
	hud.router.handle(_key(KEY_ESCAPE, false))
	_check("(c) Esc closes the wheel and the aim is free", not wheel.is_open and not world.wheel_hold and not wheel.visible)
	_release_x()
	_check("(c) and letting go of X afterwards gives no order", world.orders.next_id == id0)

	# --- (d) docking while open ------------------------------------------------------------------------------
	await _ticks(3)
	opened = await _open_wheel(middle)
	_check("(d) control: the wheel is open before docking", opened)
	ts.admiral_docked = true
	await _frames(3)
	_check("(d) docking closes the wheel and frees the aim", not wheel.is_open and not world.wheel_hold)
	id0 = world.orders.next_id
	await _mouse_to(_slice_point(1))
	_release_x()
	_check("(d) and letting go gives no order", world.orders.next_id == id0)
	ts.admiral_docked = false
	await _ticks(3)

	# --- (f) clicks never fire the guns ---------------------------------------------------------------------------
	hud._close_others(null)
	await _frames(3)
	var map_point := Vector2(900.0, 200.0)
	await _mouse_to(map_point)
	_click(map_point, true)
	await _ticks(3)
	_check("(f) control: with the wheel closed a left click on the map in field mode fires", world.mouse_fire and ship.controls.fire)
	_click(map_point, false)
	await _ticks(3)
	ov.clear_selection()
	await _open_wheel(middle)
	var slice_p := _slice_point(0)
	await _mouse_to(slice_p)
	hud.toast_box.show_text(MARK)
	_click(slice_p, true)
	await _ticks(3)
	# During the hold: the click has arrived (the wheel took it and closed, with its pop-up) and fired nothing.
	_check("(f) field mode: the click on a dim slice reached the wheel (it closed and said so)", not wheel.is_open and hud.toast_box._label.text != MARK, hud.toast_box._label.text)
	_check("(f) field mode: held on a dim slice, no mouse_fire and controls.fire stays false", not world.mouse_fire and not ship.controls.fire)
	_click(slice_p, false)
	await _ticks(3)
	_check("(f) field mode: and still none after the release", not ship.controls.fire and not world.mouse_fire)
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	await _open_wheel(middle)
	var cell_p := _cell_point(2)
	await _mouse_to(cell_p)
	hud.toast_box.show_text(MARK)
	_click(cell_p, true)
	await _ticks(3)
	_check("(f) field mode: the click on a strip cell reached the wheel (its pop-up came) and the wheel stays open", wheel.is_open and hud.toast_box._label.text != MARK, hud.toast_box._label.text)
	_check("(f) field mode: held on a strip cell, no mouse_fire and controls.fire stays false", not world.mouse_fire and not ship.controls.fire)
	_click(cell_p, false)
	await _ticks(3)
	_check("(f) field mode: and still none after the release", not ship.controls.fire and not world.mouse_fire)
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	# Mode 3: Tab opens the command view.
	hud.router.handle(_key(KEY_TAB, true))
	hud.router.handle(_key(KEY_TAB, false))
	await _ticks(3)
	_check("(f) Tab opens the command view (mode 3)", world.view_open and world.mode3())
	ov.set_selection([squad_a.id], false)
	await _mouse_to(map_point)
	_click(map_point, true)
	await _ticks(2)
	_check("(f) mode 3 control: a left click on the map with the wheel closed fires nothing", not world.mouse_fire and not ship.controls.fire)
	_click(map_point, false)
	await _ticks(2)
	ov.set_selection([squad_a.id], false)
	opened = await _open_wheel(middle)
	_check("(f) the fleet wheel opens in mode 3 too", opened and wheel.is_open)
	slice_p = _slice_point(5)
	await _mouse_to(slice_p)
	hud.toast_box.show_text(MARK)
	_click(slice_p, true)
	await _ticks(3)
	_check("(f) mode 3: the click on a dim slice reached the wheel (it closed and said so)", not wheel.is_open and hud.toast_box._label.text != MARK, hud.toast_box._label.text)
	_check("(f) mode 3: held on a dim slice, no mouse_fire and controls.fire stays false", not world.mouse_fire and not ship.controls.fire)
	_click(slice_p, false)
	await _ticks(3)
	_check("(f) mode 3: and still none after the release", not ship.controls.fire and not world.mouse_fire)
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	await _open_wheel(middle)
	cell_p = _cell_point(3)
	await _mouse_to(cell_p)
	hud.toast_box.show_text(MARK)
	_click(cell_p, true)
	await _ticks(3)
	_check("(f) mode 3: the click on a strip cell reached the wheel (its pop-up came) and the wheel stays open", wheel.is_open and hud.toast_box._label.text != MARK, hud.toast_box._label.text)
	_check("(f) mode 3: held on a strip cell, no mouse_fire, controls.fire false and the selection untouched", not world.mouse_fire and not ship.controls.fire and _ids_equal(ov.sel_squads, [squad_a.id]), str(ov.sel_squads))
	_click(cell_p, false)
	await _ticks(3)
	_check("(f) mode 3: and still no fire after the release", not ship.controls.fire and not world.mouse_fire)
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	hud.router.handle(_key(KEY_TAB, true))
	hud.router.handle(_key(KEY_TAB, false))
	await _ticks(3)
	_check("(f) Tab closes mode 3 again", not world.view_open)

	# --- (g) keys 1 to 4 and energy ------------------------------------------------------------------------------
	ts.production.items.clear()
	ship.energy.mode = Rules.ENERGY_BALANCED
	ship.energy_cd = 0.0
	await _open_wheel(middle)
	Input.parse_input_event(_key(KEY_1, true))
	await _ticks(4)
	_check("(g) with the wheel open key 1 leaves the energy alone", ship.energy.mode == Rules.ENERGY_BALANCED, str(ship.energy.mode))
	Input.parse_input_event(_key(KEY_1, false))
	await _ticks(2)
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	await _ticks(2)
	ship.energy_cd = 0.0
	Input.parse_input_event(_key(KEY_1, true))
	await _ticks(4)
	_check("(g) control: with the wheel closed key 1 routes the energy to weapons", ship.energy.mode == Rules.ENERGY_WEAPONS, str(ship.energy.mode))
	Input.parse_input_event(_key(KEY_1, false))
	await _ticks(2)
	ship.energy.mode = Rules.ENERGY_BALANCED
	ship.energy_cd = 0.0

	# --- (h) the strip ----------------------------------------------------------------------------------------------
	ts.production.items.clear()
	await _ticks(2)
	# The control first: the digits with the wheel closed queue nothing.
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_2, true))
	_check("(h) control: key 2 with the wheel closed files no order", world.orders.next_id == id0)
	await _ticks(3)
	hud.router.handle(_key(KEY_2, false))
	ship.energy.mode = Rules.ENERGY_BALANCED
	await _open_wheel(middle)
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_2, true))
	got = _orders_since(id0)
	_check("(h) key 2 queues one Fighter squadron", got.size() == 1 and str(got[0]["kind"]) == OrderKinds.PRODUCE and str((got[0]["settings"] as Dictionary).get("hull", "")) == "fighter" and int((got[0]["settings"] as Dictionary).get("count", 0)) == 3, _kinds(got))
	_check("(h) the wheel stays open after a digit", wheel.is_open)
	_check("(h) and the pop-up says it", hud.toast_box._label.text.begins_with("Queued: "), hud.toast_box._label.text)
	await _ticks(3)
	hud.router.handle(_key(KEY_2, false))
	await _ticks(2)
	ts.production.items.clear()
	await _ticks(2)
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_2, true, true))
	got = _orders_since(id0)
	var cap_ok := got.size() >= 2 and got.size() <= RtsHulls.DEPTH_SHIPS
	for o: Dictionary in got:
		cap_ok = cap_ok and str(o["kind"]) == OrderKinds.PRODUCE and str((o["settings"] as Dictionary).get("hull", "")) == "fighter"
	_check("(h) Shift+2 queues up to the cap (%d of at most %d)" % [got.size(), RtsHulls.DEPTH_SHIPS], cap_ok, _kinds(got))
	await _ticks(3)
	hud.router.handle(_key(KEY_2, false, true))
	await _ticks(2)
	ts.production.items.clear()
	await _ticks(2)
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_2, true, false, true))
	got = _orders_since(id0)
	_check("(h) Alt+2 queues one Fighter squadron with repeat on", got.size() == 1 and int((got[0]["settings"] as Dictionary).get("repeat", 0)) == 1, _kinds(got))
	await _ticks(3)
	hud.router.handle(_key(KEY_2, false, false, true))
	await _ticks(2)
	ts.production.items.clear()
	# A locked hull: the queue's refusal, and the research board stays shut.
	var locked_i := -1
	for i in 10:
		if not UnlockAll.is_unlocked(ts) and not ts.ship_unlocked(str(Ships.ORDER[i])):
			locked_i = i
	_check("(h) a locked hull exists to try", locked_i >= 0)
	if locked_i >= 0:
		var code: Key = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0][locked_i]
		id0 = world.orders.next_id
		hud.toast_box.show_text(MARK)
		hud.router.handle(_key(code, true))
		_check("(h) a locked hull files no order and the pop-up gives the refusal", world.orders.next_id == id0 and hud.toast_box._danger and hud.toast_box._label.text != MARK and not FieldOrders.was_queued(hud.toast_box._label.text), hud.toast_box._label.text)
		_check("(h) and the research board stays shut", not world.board_open and (hud.board == null or not hud.board.visible))
		await _ticks(3)
		hud.router.handle(_key(code, false))
	# A click on a cell queues too (Fighter, cell 1), and the wheel stays open.
	ts.production.items.clear()
	await _ticks(2)
	cell_p = _cell_point(1)
	await _mouse_to(cell_p)
	id0 = world.orders.next_id
	_click(cell_p, true)
	await _frames(2)
	# The real click reaches the HUD on the next frame: read the order from the queue's last record.
	var last: Dictionary = world.orders.last_submitted
	_check("(h) a click on the Fighter cell queues one Fighter squadron and the wheel stays open", world.orders.next_id == id0 + 1 and str(last.get("kind", "")) == OrderKinds.PRODUCE and str((last.get("settings", {}) as Dictionary).get("hull", "")) == "fighter" and wheel.is_open, str(last.get("kind", "none")))
	_click(cell_p, false)
	await _ticks(3)
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	await _ticks(3)
	ts.production.items.clear()
	id0 = world.orders.next_id
	hud.router.handle(_key(KEY_2, true, true))
	_check("(h) control: Shift+2 with the wheel closed queues nothing", world.orders.next_id == id0)
	await _ticks(3)
	hud.router.handle(_key(KEY_2, false, true))
	ship.energy.mode = Rules.ENERGY_BALANCED

	# --- (k) the middle button with the wheel open -------------------------------------------------------------------
	await _middle_cases()

	# --- (i) the fit at 1280x720 --------------------------------------------------------------------------------------
	await _fit_cases()

	# --- (j) the 24 angles ----------------------------------------------------------------------------------------------
	_angle_cases()

	# --- (l) the middle drag that a cover takes the release of -------------------------------------------------------
	await _cover_drag_cases()


## True while the camera's middle-button drag is on.
func _dragging() -> bool:
	return world.camera.has_method("dragging") and bool(world.camera.call("dragging"))


## Case (k): a real middle click at an enemy marks it with the fleet wheel closed (the control) and marks nothing with it open
## (the wheel stays open and files no order), and a middle drag that is still going when the wheel opens ends there.
func _middle_cases() -> void:
	var wheel := hud.order_wheel
	var team := world.human_team
	var cam := world.camera
	var free_before := cam.free
	hud._close_others(null)
	await _frames(3)
	var click_p := Vector2(900.0, 200.0)
	var at := foe_at + Vector2(0.0, 300.0)
	var foe := _squad(1 - team, 1, at)
	await _ticks(3)
	var foe_ship: Ship = world.by_uid.get(foe.member_uids[0])
	if foe_ship != null:
		foe_ship.visible_mask |= 1 << team
	_check("(k) the enemy is there and visible to us", foe_ship != null and foe_ship.visible_to(team), "")
	if foe_ship == null:
		return
	world.test_mouse = at
	ship.controls.target_id = TargetKeys.NONE
	await _mouse_to(click_p)
	# (i) The control: the wheel closed.
	await _middle_click(click_p)
	_check("(k) control: with the wheel closed a middle click at an enemy marks it", ship.controls.target_id == foe_ship.uid, "%d, the enemy is %d" % [ship.controls.target_id, foe_ship.uid])
	# (ii) The wheel open: the wheel passes the press to HudInput, so the enemy is marked, the wheel stays open and no order is filed.
	ship.controls.target_id = TargetKeys.NONE
	var opened := await _open_wheel(Vector2(640.0, 330.0))
	_check("(k) the fleet wheel is open for the click", opened, "")
	var id0 := world.orders.next_id
	await _middle_click(click_p)
	_check("(k) with the wheel open a middle click at an enemy marks it", ship.controls.target_id == foe_ship.uid, "%d, the enemy is %d" % [ship.controls.target_id, foe_ship.uid])
	_check("(k) and the wheel is still open and no order was filed", wheel.is_open and world.orders.next_id == id0, "open %s, orders %d" % [wheel.is_open, world.orders.next_id - id0])
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	ship.controls.target_id = TargetKeys.NONE
	await _ticks(2)
	# (iv) The drag: a press with the wheel closed starts it, the wheel opening ends it, the release over the wheel is swallowed.
	cam.free = true
	await _frames(3)
	_middle(click_p, true)
	await _ticks(3)
	_check("(k) a middle press with the wheel closed starts the camera drag", _dragging(), "")
	var c0 := cam.global_position
	var moved_to := click_p + Vector2(80.0, 0.0)
	await _mouse_to(moved_to)
	await _frames(20)
	_check("(k) control: while the drag is on a mouse move pulls the camera", cam.global_position.distance_to(c0) > 1.0, "%.1f" % cam.global_position.distance_to(c0))
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(250)
	_check("(k) the fleet wheel opens over the drag", wheel.is_open, "")
	_middle(moved_to, false)
	await _ticks(3)
	_check("(k) the drag has ended with the wheel open", not _dragging() and wheel.is_open, "")
	# The open wheel also takes the mouse moves, so the drag shows only once it has closed again: close it, then move the mouse.
	wheel.close()
	hud.router.end_hold()
	hud.router.handle(_key(KEY_X, false))
	await _frames(60)
	var c1 := cam.global_position
	await _mouse_to(moved_to + Vector2(80.0, 0.0))
	await _frames(20)
	_check("(k) and with the wheel closed again a mouse move of 80 px does not move the camera", cam.global_position.distance_to(c1) < 1.0, "%.1f" % cam.global_position.distance_to(c1))
	cam.free = free_before
	ship.controls.target_id = TargetKeys.NONE
	await _ticks(2)


## Case (l): a middle drag of the free camera is over once the button is up, also when a cover opened over it and took the
## release (the note box, the pause menu, the help pages, the Controls page, the hangar and, in the Admiral's seat, the board;
## the end screen needs a finished match and is not driven). The control with no cover: a held button keeps the drag and its
## release ends it. For each cover: press (the drag starts), open the cover, let go over it (the drag is over), close it and
## move the mouse 80 px on from the release point (the camera stays). A pilot HUD control may sit on the press point: then
## the press is tried once more lower down. A line that cannot be measured prints "INFO", never a FAIL; in the pilot's seat a
## new ship during a cover (the camera would follow it) makes that cover run once more.
func _cover_drag_cases() -> void:
	var cam := world.camera
	var free_before := cam.free
	var p := Vector2(900.0, 200.0)
	var covers: Array[String] = ["note box", "pause menu", "help pages", "Controls page", "hangar"]
	if role == "admiral":
		covers.append("board")
	var open_cover := func(c: String) -> void:
		match c:
			"note box":
				hud._open_note()
			"pause menu":
				hud._toggle_pause_menu()
			"help pages":
				hud._toggle_help()
			"Controls page":
				hud._toggle_controls()
			"hangar":
				hud._open_hangar()
			"board":
				hud._toggle_board()
	var close_cover := func(c: String) -> void:
		match c:
			"note box":
				if hud.note_box != null:
					hud.note_box.cancel()
			"pause menu":
				if hud.pause_menu != null:
					hud.pause_menu.resume()
			_:
				hud._close_others(null)
	var cover_is_open := func(c: String) -> bool:
		match c:
			"note box":
				return hud._note_is_open()
			"pause menu":
				return hud.pause_menu != null and hud.pause_menu.active
			"help pages":
				return hud.help != null and hud.help.visible
			"Controls page":
				return hud.controls != null and hud.controls.visible
			"hangar":
				return hud.hangar != null and hud.hangar.visible
			"board":
				return hud.board != null and hud.board.visible
		return false
	var cover_panel := func(c: String) -> Control:
		match c:
			"pause menu":
				return hud.pause_menu
			"help pages":
				return hud.help
			"Controls page":
				return hud.controls
			"hangar":
				return hud.hangar
			"board":
				return hud.board
		return null
	# The control, no cover: a held middle button keeps the drag, its release ends it.
	hud._close_others(null)
	cam.free = true
	await _frames(3)
	_middle(p, true)
	await _frames(3)
	var on := _dragging()
	if not on and role == "pilot":
		_middle(p, false)
		await _frames(3)
		p = Vector2(900.0, 260.0)
		_middle(p, true)
		await _frames(3)
		on = _dragging()
	if not on:
		if role == "pilot":
			print("INFO (l) the middle press started no drag at either point in the pilot's seat: its cover cases are not run")
		else:
			_check("(l) control: the middle press starts the drag", false)
		_middle(p, false)
		await _frames(3)
		cam.end_drag()
		cam.free = free_before
		return
	await _frames(20)
	_check("(l) control: a held middle button keeps the drag through 20 frames", _dragging())
	_middle(p, false)
	await _frames(3)
	_check("(l) control: and the release ends it", not _dragging())
	# The covers.
	for cover in covers:
		var tries := 0
		while tries < 2:
			tries += 1
			if tries == 2:
				await _frames(60)
			var ship0: Ship = world.human.ship
			var redo := false
			# Step 1: the press starts the drag, with no cover open.
			hud._close_others(null)
			cam.free = true
			await _frames(3)
			_middle(p, true)
			await _frames(3)
			on = _dragging()
			if not on and role == "pilot":
				_middle(p, false)
				await _frames(3)
				p = Vector2(900.0, 260.0)
				_middle(p, true)
				await _frames(3)
				on = _dragging()
			_check("(l) %s: control, the middle press starts the drag" % cover, on)
			# Step 2: the cover opens over the held button, and the release point is on its panel.
			open_cover.call(cover)
			await _frames(3)
			var live: bool = cover_is_open.call(cover)
			_check("(l) %s is open" % cover, live)
			if not live:
				print("INFO (l) %s did not open: its lines are not measured" % cover)
			if live and cover != "note box":
				var panel: Control = cover_panel.call(cover)
				var on_panel := panel != null and panel.get_global_rect().has_point(p + Vector2(80.0, 0.0))
				if on_panel:
					_check("(l) %s: the release point is on its panel" % cover, true)
				else:
					print("INFO (l) %s: the release point is not on its panel: its lines are not measured" % cover)
					live = false
			# Step 3: the release over the cover.
			if live:
				_middle(p + Vector2(80.0, 0.0), false)
				await _frames(4)
				if role == "pilot" and world.human.ship != ship0:
					print("INFO (l) %s: the pilot's ship changed during the cover" % cover)
					redo = true
					live = false
			if live:
				_check("(l) %s: after the release the drag is over" % cover, not _dragging())
				# Step 4: close the cover and move the mouse on from the release point.
				close_cover.call(cover)
				await _frames(60)
				var c0 := cam.global_position
				await _mouse_to(p + Vector2(160.0, 0.0))
				await _frames(20)
				if role == "pilot" and world.human.ship != ship0:
					print("INFO (l) %s: the pilot's ship changed after the cover" % cover)
					redo = true
				else:
					var moved := cam.global_position.distance_to(c0)
					_check("(l) %s: and a mouse move from the release point does not move the camera" % cover, moved < 1.0, "%.1f" % moved)
			# Put everything back: the button up, the cover closed, no drag.
			_middle(p + Vector2(80.0, 0.0), false)
			close_cover.call(cover)
			await _frames(3)
			cam.end_drag()
			if not redo:
				break
			if tries == 2:
				print("INFO (l) %s: the ship changed twice, its lines are not measured" % cover)
	cam.free = free_before


## Case (i): the ring and the strip inside the window with 8 pixels to spare, text sizes, label widths and cell lines.
func _fit_cases() -> void:
	var wheel := hud.order_wheel
	var vp := hud.get_viewport_rect().size
	_check("(i) the window is %dx%d" % [WINDOW.x, WINDOW.y], vp.is_equal_approx(Vector2(WINDOW)), str(vp))
	var inside := Rect2(Vector2(8.0, 8.0), vp - Vector2(16.0, 16.0))
	var centres := {"top left": Vector2.ZERO, "top right": Vector2(vp.x, 0.0), "bottom left": Vector2(0.0, vp.y), "bottom right": vp, "middle": vp * 0.5}
	for where: String in centres:
		wheel.open_at(centres[where], Vector2.ZERO)
		_check("(i) %s: the ring lies inside the window with 8 px to spare" % where, inside.encloses(wheel.ring_rect()), "%s in %s" % [str(wheel.ring_rect()), str(inside)])
		_check("(i) %s: the strip lies inside the window with 8 px to spare" % where, inside.encloses(wheel.strip_rect()), "%s in %s" % [str(wheel.strip_rect()), str(inside)])
		_check("(i) %s: the strip is under the ring and is drawn there" % where, wheel.strip_rect().position.y >= wheel.ring_rect().end.y and wheel.strip.position.is_equal_approx(wheel.strip_rect().position))
		wheel.close()
	_check("(i) the text is 14 px or more", OrderWheel.TEXT_SIZE >= 14 and BuildStrip.TEXT_SIZE >= 14)
	var widest := 0.0
	for i in OrderWheel.SLICES.size():
		var w := wheel.label_width(i)
		widest = maxf(widest, w)
		_check("(i) slice %d (%s): its label (%.1f px) is no wider than the chord at the label's radius (%.1f px)" % [i, str((OrderWheel.SLICES[i] as Array)[0]), w, wheel.chord_at_label()], w <= wheel.chord_at_label())
	print("field_wheel_check FIT: RING_R %.0f, DEAD_R %.0f, LABEL_R %.0f, widest label %.1f px, chord at the label's radius %.1f px, strip %.0fx%.0f px (cells %.0fx%.0f)" % [OrderWheel.RING_R, OrderWheel.DEAD_R, OrderWheel.LABEL_R, widest, wheel.chord_at_label(), BuildStrip.strip_size().x, BuildStrip.strip_size().y, BuildStrip.CELL.x, BuildStrip.CELL.y])
	_check("(i) a strip cell is at least 84x44", BuildStrip.CELL.x >= 84.0 and BuildStrip.CELL.y >= 44.0)
	wheel.open_at(vp * 0.5, Vector2.ZERO)
	var font := ThemeDB.fallback_font
	var worst := 0.0
	for i in BuildStrip.COLS * BuildStrip.ROWS:
		for line: String in wheel.strip.lines(i):
			worst = maxf(worst, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BuildStrip.TEXT_SIZE).x)
	_check("(i) the widest strip line (%.1f px) fits a cell (%.0f px wide, 8 px to spare)" % [worst, BuildStrip.CELL.x], worst <= BuildStrip.CELL.x - 8.0)
	# The longest state line any cell can show.
	for line: String in ["short 1.1k", "fleet full", "locked", "9999", "0 Battlecruiser"]:
		_check("(i) the line '%s' fits a cell" % line, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BuildStrip.TEXT_SIZE).x <= BuildStrip.CELL.x - 8.0)
	wheel.close()
	hud.router.end_hold()


## Case (j): RadialMenu.slice_at against WingWheel.hit_at (six slices) and OrderWheel.hit_at (eight) at 24 angles.
func _angle_cases() -> void:
	var wing := hud.wing_wheel
	var wheel := hud.order_wheel
	wing.center = Vector2(640.0, 330.0)
	wheel.center = Vector2(640.0, 330.0)
	var same6 := 0
	var same8 := 0
	for k in 24:
		var a := 7.5 + 15.0 * float(k)
		var off := Vector2.from_angle(deg_to_rad(a - 90.0)) * 68.0
		# Eight slices have their edges at 22.5 + 45 m degrees, which 7.5 + 15 k hits: shift by 3 degrees for them.
		var off8 := Vector2.from_angle(deg_to_rad(a + 3.0 - 90.0)) * 68.0
		var hit := wing.hit_at(wing.center + off)
		var want := -1
		for i in WingWheel.SLICES.size():
			if str((WingWheel.SLICES[i] as Array)[0]) == str(hit.get("name", "")):
				want = i
		if RadialMenu.slice_at(off, 6, WingWheel.DEAD_R, WingWheel.RING_R) == want and want >= 0:
			same6 += 1
		var hit8 := wheel.hit_at(wheel.center + off8)
		if RadialMenu.slice_at(off8, OrderWheel.SLICES.size(), OrderWheel.DEAD_R, OrderWheel.RING_R) == int(hit8.get("index", -2)):
			same8 += 1
	_check("(j) slice_at for six slices names WingWheel.hit_at's slice at %d of 24 angles" % same6, same6 == 24)
	_check("(j) slice_at for eight slices names OrderWheel.hit_at's slice at %d of 24 angles" % same8, same8 == 24)
	_check("(j) the dead zone and the outside are -1", RadialMenu.slice_at(Vector2(10.0, 0.0), 8, OrderWheel.DEAD_R, OrderWheel.RING_R) == -1 and RadialMenu.slice_at(Vector2(0.0, 400.0), 8, OrderWheel.DEAD_R, OrderWheel.RING_R) == -1)
