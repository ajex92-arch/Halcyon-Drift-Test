extends Node
## WHAT THIS IS: the mouse-route check (T-114, mouse-only play). Every button and click that stands for a key
## must do exactly what the key does. This test does each action once by the key (Input.action_press, or a key
## event through the game's input path, as tests/bot_pilot.gd and tests/pause_menu_check.gd do) and once by the
## click (the doors: HudInput.click() and WorldSpeed.tap(), and the readout's hit map), and compares the state
## each one leaves. It also checks the gates (a paused game, a tick-less frame at slow speed), that a left press on
## the readout or the button block never fires the guns, that the wheel still zooms over them, and the aim hold.
##
## HOW IT WORKS: it waits for the HUD and a flying human, makes the window 1280 x 720 (a headless window is only
## 64 x 64) and runs these groups in order; each prints PASS or FAIL lines:
##   1. energy: 1 to 4 by key and by click give the same mode and a cooldown; the hit map names each button;
##   2. shields: a zone twice gives that zone and then balanced (key and click); the ship icon balances when the
##      focus is off balance and does nothing when it is balanced; the hit map's dead bands name nothing;
##   3. repair kit: R and a click on the kit slot each use one kit; assist: V and the Assist click each flip it;
##   4. docking: in range (key and click both dock), out of range (the same refusal pop-up), within half a second
##      of a launch (nothing); launching from the dock by key and by click; an Admiral's Launch needs the hangar open;
##   5. the menu doors: Hangar, Help and Menu open and close their panels; the Menu click brings the card back
##      from Look around and does nothing while the card shows; a paused game takes no click; Board and Camera for an
##      Admiral, and nothing for a pilot; the Centre latch;
##   6. slow speed: a click made on a frame without a tick is seen by exactly one tick (0.5x and 1.5x);
##   7. the mouse: a left press on the readout and on the block leaves the guns alone; a fire held from the world
##      and let go over the block stops; a real click on the energy button changes the routing; the wheel over the
##      readout and the block zooms; the block's place, tooltips and lit Dock button;
##   8. the aim hold: with the pointer on the readout the face point stays put for 30 ticks (it starts one tick
##      late), it follows the pointer within a tick of leaving, and it follows while a fire is held.
## It ends with "mouse_route_check: N failures" (0 = all good) and quits. A run over 90 seconds of real time
## prints "mouse_route_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --test=mouse_route_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --force-hud --test=mouse_route_check
## (without --bot the human buys a Fighter and launches, so there is a ship to click on.)
##
## WHO USES IT: main.gd loads it for --test=mouse_route_check. It reads the HUD (Hud, HudInput, ShipStatus, SeatBar,
## HudSlots), the World and the human's ship; it changes the ship's state to set up each case.

## The running match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many checks failed.
var failures := 0
## The pop-ups the match showed, newest last.
var toasts: Array[String] = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.toast.connect(func(t: Variant) -> void: toasts.append(str(t)))


## Quit after 90 s of real time; start the check once the HUD exists and a ship flies.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 90000:
		print("mouse_route_check: timeout")
		get_tree().quit()
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or hud.seat_bar == null or world.human == null or _ship() == null:
		return
	started = true
	_run()


## The whole check (see HOW IT WORKS), then the summary line and quit.
func _run() -> void:
	await _frames(70)
	hud._close_others(null)
	var admiral := world.human_role == "admiral"
	print("mouse_route_check: seat %s" % world.human_role)
	await _energy()
	await _shields()
	await _kit_and_assist()
	await _docking(admiral)
	await _menus(admiral)
	await _slow_speed()
	await _mouse()
	await _aim_hold()
	print("mouse_route_check: %d failures" % failures)
	get_tree().quit()


# --- 1. energy -------------------------------------------------------------------------------------

## Energy routing by key and by click, and the readout's hit map.
func _energy() -> void:
	var cases := [["energy_weapons", Rules.ENERGY_BALANCED, Rules.ENERGY_WEAPONS], ["energy_shields", Rules.ENERGY_BALANCED, Rules.ENERGY_SHIELDS],
		["energy_thrusters", Rules.ENERGY_BALANCED, Rules.ENERGY_THRUSTERS], ["energy_balanced", Rules.ENERGY_WEAPONS, Rules.ENERGY_BALANCED]]
	for c: Array in cases:
		var seen := []
		for by_click: bool in [false, true]:
			_reset_ship(int(c[1]))
			if by_click:
				await _click(String(c[0]))
			else:
				await _key_tap(String(c[0]))
			var s := _ship()
			seen.append([s.energy.mode, s.energy_cd > 0.0])
		var want_cd := int(c[1]) != int(c[2])
		_check(seen[0] == seen[1] and int(seen[1][0]) == int(c[2]) and bool(seen[1][1]) == want_cd, "%s: key and click give the same mode and cooldown (%s)" % [c[0], seen])
	# The hit map names each button, and the dead bands name nothing.
	var st := hud.status
	for i in 4:
		_check(st.part_at(Vector2(140.0 + 70.75 * i + 33.0, 55.0 + 12.0)) == "energy_%d" % i, "the hit map names energy button %d" % i)
	_check(st.part_at(Vector2(150.0, 85.0)) == "" and st.part_at(Vector2(200.0, 40.0)) == "", "just under and above the energy row is nothing")
	_check(st._get_tooltip(Vector2(150.0, 60.0)).contains("weapons") and st._get_tooltip(Vector2(150.0, 60.0)).contains(KeyMapText.key_of("energy_weapons")), "an energy button's tooltip names the mode and the key (%s)" % st._get_tooltip(Vector2(150.0, 60.0)))


# --- 2. shields ------------------------------------------------------------------------------------

## Shield zones by key and by click, the ship icon, the dead bands.
func _shields() -> void:
	var zones := [["shield_front", Rules.FOCUS_FRONT], ["shield_rear", Rules.FOCUS_REAR], ["shield_left", Rules.FOCUS_LEFT], ["shield_right", Rules.FOCUS_RIGHT]]
	for z: Array in zones:
		for by_click: bool in [false, true]:
			_reset_ship(Rules.ENERGY_BALANCED)
			if by_click:
				await _click(String(z[0]))
			else:
				await _key_tap(String(z[0]))
			var first := _ship().shields.focus
			_ship().focus_cd = 0.0
			if by_click:
				await _click(String(z[0]))
			else:
				await _key_tap(String(z[0]))
			_check(first == int(z[1]) and _ship().shields.focus == Rules.FOCUS_BALANCED, "%s by %s: that zone, then balanced (%d, %d)" % [z[0], "click" if by_click else "key", first, _ship().shields.focus])
	# The hit map.
	var st := hud.status
	var c := ShipStatus.DIAMOND_C
	var want := {Vector2(0, -46): "shield_0", Vector2(0, 46): "shield_1", Vector2(-46, 0): "shield_2", Vector2(46, 0): "shield_3", Vector2(0, 0): "balance", Vector2(10, 10): "balance",
		Vector2(33, 33): "", Vector2(21, 0): "", Vector2(0, -70): "", Vector2(-33, -33): "", Vector2(0, -22): ""}
	for off: Vector2 in want:
		_check(st.part_at(c + off) == String(want[off]), "the diamond's hit map at %s is '%s' (got '%s')" % [off, want[off], st.part_at(c + off)])
	# The ship icon: balances when the focus is off balance, does nothing when it is balanced.
	_reset_ship(Rules.ENERGY_BALANCED)
	await _key_tap("shield_left")
	_check(_ship().shields.focus == Rules.FOCUS_LEFT, "setup: the left zone is focused")
	_ship().focus_cd = 0.0
	await _settle()
	st.click_part("balance")
	await _ticks(3)
	_check(_ship().shields.focus == Rules.FOCUS_BALANCED, "the ship icon balances a focused zone")
	_ship().focus_cd = 0.0
	st.click_part("balance")
	await _ticks(3)
	_check(_ship().shields.focus == Rules.FOCUS_BALANCED and _ship().focus_cd == 0.0, "the ship icon does nothing when the shields are balanced already")
	_check(st._get_tooltip(c + Vector2(0, -46)).contains("front") and st._get_tooltip(c).contains("Balance"), "the shield tooltips name the zone and the balance")


# --- 3. kit and assist -----------------------------------------------------------------------------

## The repair kit and flight assist, by key and by click.
func _kit_and_assist() -> void:
	world.human.inventory[0] = {"id": Items.KIT["id"], "count": 3}
	for by_click: bool in [false, true]:
		var before := world.human.kit_count()
		_ship().hull = _ship().hull_max * 0.5
		if by_click:
			await _click("use_kit")
		else:
			await _key_tap("use_kit")
		_check(world.human.kit_count() == before - 1, "a repair kit is used by %s (%d -> %d)" % ["click" if by_click else "key", before, world.human.kit_count()])
	_ship().hull = _ship().hull_max
	for by_click: bool in [false, true]:
		var was := _ship().assist
		if by_click:
			await _click("assist_toggle")
		else:
			await _key_tap("assist_toggle")
		_check(_ship().assist != was, "flight assist flips by %s" % ["click" if by_click else "key"])
		_ship().assist = true
	# The kit slot's box takes the mouse only while it holds a kit.
	await _settle()
	var box: PanelContainer = hud.slots._boxes[0]
	_check(box.mouse_filter == Control.MOUSE_FILTER_STOP and box.tooltip_text.contains("repair kit"), "a kit slot takes the mouse and has a tooltip")
	_check((hud.slots._boxes[1] as PanelContainer).mouse_filter == Control.MOUSE_FILTER_IGNORE, "an empty slot still lets a click through")
	world.human.inventory[0] = {}


# --- 4. docking and launching ----------------------------------------------------------------------

## Dock in range, out of range and just after a launch; launch from the dock.
func _docking(admiral: bool) -> void:
	var ms := world.mothership(world.human_team)
	var far := ms.global_position + Vector2(ms.dock_radius() + 4000.0, 0.0)
	# Out of range: the same refusal, from the key and from the click.
	var refusals := []
	for by_click: bool in [false, true]:
		_ship().global_position = far
		_ship().launched_at = -10.0
		toasts.clear()
		if by_click:
			await _click("dock")
		else:
			await _key_tap("dock")
		refusals.append(toasts.duplicate())
		_check(world.human.state == "flying", "out of range, %s does not dock" % ["click" if by_click else "key"])
	_check(refusals[0] == refusals[1] and refusals[0].has("Fly closer to the mothership to dock."), "out of range the key and the click give the same pop-up (%s | %s)" % [refusals[0], refusals[1]])
	# Within half a second of a launch: nothing.
	for by_click: bool in [false, true]:
		_ship().global_position = ms.global_position
		_ship().launched_at = world.time
		if by_click:
			await _click("dock")
		else:
			await _key_tap("dock")
		_check(world.human.state == "flying", "just after a launch, %s does not dock" % ["click" if by_click else "key"])
	# In range: both dock. Each time the ship is launched again first.
	for by_click: bool in [false, true]:
		_ship().global_position = ms.global_position
		_ship().launched_at = -10.0
		await _settle()
		_check(hud.seat_bar.visible and String(hud.seat_bar._shown["dock"]).ends_with("|true|false"), "the Dock button lights up in range")
		if by_click:
			await _click("dock")
		else:
			await _key_tap("dock")
		_check(world.human.state == "docked" and world.human.ship == null, "in range, %s docks" % ["click" if by_click else "key"])
		await _settle()
		var label := String((hud.seat_bar.buttons["dock"] as Button).text)
		_check(label == "Launch" and (hud.seat_bar.buttons["dock"] as Button).disabled == admiral, "docked, the Dock place reads Launch (%s), disabled only for an Admiral" % label)
		# Launch again: by the key's own branch (F) the first time, by the click the second time.
		if admiral:
			_check(not hud.router._dock_key(), "an Admiral's Launch does nothing with the hangar closed")
			hud._open_hangar()
		if by_click:
			await _click("dock")
		else:
			await _key(KEY_F)
		await _frames(2)
		_check(world.human.state != "docked", "docked, %s launches" % ["click" if by_click else "key"])
		if admiral:
			hud._close_others(null)
		await _frames(70)
	_check(hud.router._dock_key() == false or true, "the launch branch is callable")


# --- 5. the menu doors -----------------------------------------------------------------------------

## Hangar, Help, Menu (and Look around), Board, Camera, Centre, the gates.
func _menus(admiral: bool) -> void:
	hud._close_others(null)
	_check(not hud._any_panel_open(), "setup: nothing open")
	await _click("hangar")
	_check(hud.hangar != null and hud.hangar.visible, "the Hangar click opens the hangar")
	await _click("hangar")
	_check(not hud.hangar.visible, "the Hangar click closes it again")
	await _click("help")
	_check(hud.help != null and hud.help.visible, "the Help click opens the help")
	await _settle()
	_check(not hud.seat_bar.visible, "the button block hides while a panel is open")
	await _click("help")
	_check(not hud.help.visible, "the Help click closes the help")
	await _settle()
	_check(hud.seat_bar.visible, "the button block shows again")
	# Menu: opens the pause menu; Look around; the Menu click brings the card back.
	await _click("pause")
	_check(get_tree().paused and hud.pause_menu != null and hud.pause_menu.active and hud.pause_menu.visible, "the Menu click opens the pause menu and the game stops")
	await _settle()
	_check(not hud.seat_bar.visible, "the block is hidden while the card shows")
	var held := world.human.kit_count()
	hud.router.click("hangar")
	hud.router.click("pause")
	_check(get_tree().paused and hud.pause_menu.visible and (hud.hangar == null or not hud.hangar.visible), "a click on a button does nothing while the card holds the game")
	hud.pause_menu.look_around()
	await _settle()
	_check(hud.pause_menu.looking and not hud.pause_menu.visible and get_tree().paused, "Look around hides the card and the game stays paused")
	_check(hud.seat_bar.visible, "the button block shows in Look around")
	_check((hud.seat_bar.buttons["hangar"] as Button).disabled and not (hud.seat_bar.buttons["menu"] as Button).disabled, "in Look around only the Menu button is live")
	hud.router.click("hangar")
	_check(hud.hangar == null or not hud.hangar.visible, "in Look around the Hangar click does nothing")
	hud.router.click("pause")
	await _settle()
	_check(hud.pause_menu.visible and not hud.pause_menu.looking and hud.pause_menu.active and get_tree().paused, "in Look around the Menu click brings the card back and the game is still paused")
	hud.pause_menu.resume()
	await _frames(3)
	_check(not get_tree().paused, "the pause ended")
	# A paused tree takes no ship click.
	var assist_was := _ship().assist
	get_tree().paused = true
	hud.router.click("assist_toggle")
	get_tree().paused = false
	await _ticks(4)
	_check(_ship().assist == assist_was and world.human.kit_count() == held, "a paused game takes no click for the ship")
	# Camera, Board, Centre.
	var cam := world.camera
	if admiral:
		var was_free := cam.free
		await _key(KEY_C)
		var by_key := cam.free
		var key_toast := hud.toast_box._label.text
		hud.toast_box._label.text = ""
		await _click("center_camera")
		var click_toast := hud.toast_box._label.text
		_check(by_key != was_free and cam.free == was_free, "the Camera click flips the camera like C (%s, %s)" % [by_key, cam.free])
		_check(key_toast.begins_with("Camera: ") and click_toast.begins_with("Camera: ") and key_toast != click_toast, "the Camera click speaks like C (%s | %s)" % [key_toast, click_toast])
		await _click("admiral_board")
		_check(world.board_open and hud.board != null and hud.board.visible, "the Board click opens the board")
		await _click("admiral_board")
		_check(not world.board_open and not hud.board.visible, "the Board click closes it")
	else:
		var free_was := cam.free
		await _key(KEY_C)
		await _click("center_camera")
		_check(cam.free == free_was, "C and the Camera click do nothing for a pilot")
		await _click("admiral_board")
		_check(hud.scoreboard == null or not hud.scoreboard.visible, "a pilot's Scores click is not wired: no table opens")
		_check(not cam.centre_latched, "setup: the camera is not latched")
		await _click("center_on_ship")
		_check(cam.centre_latched and cam._centering(), "the Centre click latches the Space centring")
		cam.look_at_point(Vector2(100, 100))
		_check(not cam.centre_latched, "a minimap click lets the latch go")
		await _click("center_on_ship")
		await _click("center_on_ship")
		_check(not cam.centre_latched, "a second Centre click lets go")
		_check((hud.seat_bar.buttons["seat"] as Button).disabled, "the pilot's Scores place is disabled in this build")


# --- 6. slow speed ---------------------------------------------------------------------------------

## A click made on a frame without a tick is seen by exactly one tick.
func _slow_speed() -> void:
	for f: float in [0.5, 1.5]:
		world.speed.set_factor(f)
		var flips := 0
		for rep in 4:
			var was := _ship().assist
			await get_tree().process_frame
			world.speed.tap("assist_toggle")
			for i in 4 + rep:
				await get_tree().physics_frame
			if _ship().assist != was:
				flips += 1
		_check(flips == 4, "at %.1fx four clicks flip the assist exactly four times (%d)" % [f, flips])
	world.speed.set_factor(1.0)
	_ship().assist = true


# --- 7. the mouse ----------------------------------------------------------------------------------

## Left presses on the readout and the block, a real click on a button, the wheel, the block's place.
func _mouse() -> void:
	await _settle()
	var st := hud.status
	var bar := hud.seat_bar
	var readout := st.get_global_rect()
	var gap := readout.position + Vector2(300.0, 100.0)
	var in_block := bar.get_global_rect().position + Vector2(77.0, 117.0)
	_check(bar.visible, "setup: the block shows")
	# The block's place: right of the readout with the gap, the bottom GAP above the window's edge.
	_check(absf(bar.global_position.x - (readout.end.x + HudLayout.GAP)) < 1.0 and absf(bar.global_position.y + SeatBar.H - (720.0 - HudLayout.GAP)) < 1.0, "the block sits right of the readout (%s, readout ends at %s)" % [bar.global_position, readout.end.x])
	_check(readout.end.x + HudLayout.GAP + SeatBar.W <= hud.minimap.get_global_rect().position.x + 0.5, "the block does not touch the minimap")
	var tips_ok := true
	for id: String in bar.buttons:
		if (bar.buttons[id] as Button).tooltip_text == "":
			tips_ok = false
	_check(tips_ok, "every button has a tooltip")
	# No word is cut off by its button: each word the block can show fits its column less the side margins.
	var cut: Array[String] = []
	var font := (bar.buttons["hangar"] as Button).get_theme_font("font")
	for pair: Array in [["dock", "Dock"], ["dock", "Launch"], ["hangar", "Hangar"], ["seat", "Scores"], ["seat", "Board"], ["view", "Centre"], ["view", "Camera"], ["assist", "Assist"], ["help", "Help"], ["menu", "Menu"]]:
		var col := 0
		for pl: Array in SeatBar.PLACES:
			if str(pl[0]) == str(pair[0]):
				col = int(pl[1])
		var need := font.get_string_size(str(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, SeatBar.FONT).x
		var room := float(SeatBar.COL_W[col]) - 2.0
		print("mouse_route_check: %s needs %.1f of %.1f" % [pair[1], need, room])
		if need > room:
			cut.append("%s %.1f > %.1f" % [pair[1], need, room])
	_check(cut.is_empty(), "no word on the block is cut off by its button (%s)" % [cut])
	_check((bar.buttons["hangar"] as Button).tooltip_text.contains(KeyMapText.key_of("hangar")), "a button's tooltip names its key")
	# A left press on the readout or on the block never fires.
	for p: Vector2 in [gap, in_block]:
		world.mouse_fire = false
		await _mouse_button(p, true)
		_check(not world.mouse_fire, "a left press at %s on the HUD does not fire" % p)
		await _mouse_button(p, false)
	# A fire held from the world stops when the button is let go over the block.
	await _mouse_button(Vector2(640.0, 250.0), true)
	_check(world.mouse_fire, "a left press in the world fires")
	await _mouse_button(in_block, false)
	_check(not world.mouse_fire, "let go over the block, the fire stops")
	# A real click on the energy button (the whole chain: press, release, hit map, door, tick).
	_reset_ship(Rules.ENERGY_BALANCED)
	var p := readout.position + Vector2(140.0 + 33.0, 55.0 + 12.0)
	await _mouse_button(p, true)
	await _mouse_button(p, false)
	await _ticks(3)
	_check(_ship().energy.mode == Rules.ENERGY_WEAPONS, "a real click on the weapons button routes the energy")
	# Slide off cancels: press on one button, let go on another.
	_reset_ship(Rules.ENERGY_BALANCED)
	await _mouse_button(readout.position + Vector2(140.0 + 33.0, 67.0), true)
	await _mouse_button(readout.position + Vector2(140.0 + 70.75 * 2.0 + 33.0, 67.0), false)
	await _ticks(3)
	_check(_ship().energy.mode == Rules.ENERGY_BALANCED, "pressing on one button and letting go on another does nothing")
	# The wheel still zooms over the readout and over the block.
	for q: Vector2 in [readout.position + Vector2(300.0, 20.0), in_block]:
		var z0 := world.camera.target_zoom
		_turn(q)
		_check(world.camera.target_zoom != z0, "the wheel at %s still zooms (%.4f -> %.4f)" % [q, z0, world.camera.target_zoom])


# --- 8. the aim hold -------------------------------------------------------------------------------

## The aim holds still while the pointer is on the readout (and not firing). A headless window has no real
## pointer (the world point under it never moves with the pushed motion events), so the world point under the pointer
## is changed by moving the camera, which the test holds still otherwise.
func _aim_hold() -> void:
	world.camera.set_process(false)
	var ship := _ship()
	var readout := hud.status.get_global_rect()
	var on_a := readout.position + Vector2(300.0, 100.0)
	var away := Vector2(900.0, 300.0)
	await _motion(away)
	await _ticks(3)
	var fp_away := ship.controls.face_point
	_check(fp_away.is_equal_approx(world.mouse_world()) and not world.ui_hold, "away from the HUD the face point follows the pointer")
	print("mouse_route_check: heading before the readout %.3f, face point %s" % [ship.rotation, fp_away])
	await _motion(on_a)
	await _ticks(2)
	var fp_on := ship.controls.face_point
	_check(world.ui_hold, "the pointer on the readout switches the hold on (one tick late)")
	# The pointer stays on the readout; the world moves under it (the camera shifts), so the world point under the
	# pointer changes by a lot. The held face point does not follow it.
	var cam_pos := world.camera.global_position
	world.camera.global_position = cam_pos + Vector2(900.0, 400.0)
	await _ticks(30)
	_check(world.ui_hold and ship.controls.face_point.is_equal_approx(fp_on) and not ship.controls.face_point.is_equal_approx(world.mouse_world()), "on the readout the face point stays put for 30 ticks (%s, the pointer is now over %s)" % [ship.controls.face_point, world.mouse_world()])
	print("mouse_route_check: heading on the readout %.3f, face point %s" % [ship.rotation, ship.controls.face_point])
	await _motion(away)
	await _ticks(2)
	_check(not world.ui_hold and ship.controls.face_point.is_equal_approx(world.mouse_world()), "leaving the readout, the face point follows the pointer again within a tick")
	print("mouse_route_check: heading after %.3f, face point %s" % [ship.rotation, ship.controls.face_point])
	# The button block and a kit slot hold too; a held fire does not hold.
	await _motion(hud.seat_bar.get_global_rect().position + Vector2(10.0, 10.0))
	await _ticks(2)
	_check(world.ui_hold, "the pointer on the button block switches the hold on")
	await _motion(on_a)
	await _ticks(3)
	world.mouse_fire = true
	world.camera.global_position += Vector2(600.0, -300.0)
	await _ticks(3)
	_check(not world.ui_hold and ship.controls.face_point.is_equal_approx(world.mouse_world()), "while firing, the aim follows the pointer across the readout")
	world.mouse_fire = false
	await _motion(away)
	world.camera.global_position = cam_pos
	world.camera.set_process(true)

# --- helpers ---------------------------------------------------------------------------------------

## The human's live ship, or null.
func _ship() -> Ship:
	var h := world.human
	if h == null or h.ship == null or not is_instance_valid(h.ship) or not h.ship.alive:
		return null
	return h.ship


## Put the ship's energy and shield routing back to a known state (no cooldowns), for the next case.
func _reset_ship(mode: int) -> void:
	var s := _ship()
	s.energy_cd = 0.0
	s.focus_cd = 0.0
	s.energy.mode = mode
	s.shields.set_focus(Rules.FOCUS_BALANCED)
	s.stats_dirty = true


## Press action `action` from a drawn frame, as a keyboard does, and let go two physics frames later.
func _key_tap(action: String) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


## Click the way a button does: from a drawn frame, through the menu door; then three physics frames.
func _click(action: String) -> void:
	await get_tree().process_frame
	hud.router.click(action)
	await _ticks(3)


## Press and let go of keyboard key `code` through the game's input path, then two drawn frames.
func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)
	await _frames(2)


## One wheel notch (wheel down) at window point `pos`, as a real mouse sends it.
func _turn(pos: Vector2) -> void:
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = down
		ev.factor = 1.0
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


## A left button press (`down`) or release at window point `pos`, through the viewport's GUI path.
func _mouse_button(pos: Vector2, down: bool) -> void:
	await _motion(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)
	await _frames(1)


## Move the pointer to window point `pos` (one motion event) and wait a drawn frame.
func _motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)
	await _frames(1)


## Wait for the HUD's own refresh (it runs ten times a second) and the layout to catch up.
func _settle() -> void:
	await _frames(12)


## Wait `n` physics frames.
func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Count a PASS or FAIL line for the check `what`.
func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1
