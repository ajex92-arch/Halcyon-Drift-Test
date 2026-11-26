extends Node
## WHAT THIS IS: the check of the pilot's target keys: Caps Lock and the middle click pick the enemy nearest the pointer that the
## human's team can see; a second press on that enemy picks the last attacker; the target moves on when it dies; Esc lets it go after
## everything that closes first. It also proves the target is only a mark: the match log's controls line never names it and a press
## writes no field but ShipControls.target_id.
##
## HOW IT WORKS: it waits until the human pilot's ship is flying, pauses the match (so no tick changes who is seen) and then runs
## the cases with real units of the match: it clears or sets the fog bit of each enemy by hand, puts the pointer where it wants it
## (World.test_mouse) and presses the keys through HudInput, or the middle button through the engine's own input path (so the camera sees
## the same press and release and a drag still pans). The cases:
##   1. nobody unseen is picked, held or drawn: a neutral unit is never picked either;
##   2. the nearest enemy to the pointer is picked; a tie goes to the lower uid; a second press on the target picks the last
##      attacker (the newest hit that a candidate made); with no candidate attacker the target stays;
##   3. when the target dies (or is gone) the next nearest takes its place, or the target is let go when none is left; a target that is
##      only unseen stays held;
##   4. Esc: the order wheel, the panels and the command view close first, then the target goes, then the pause menu opens;
##   5. the middle button: a press and release under 6 pixels apart targets, a longer move does not, and the camera still pans;
##   6. nothing happens while the note box is open or the pause menu holds the game, nor in mode 3 (the view open over the flight);
##   7. the match log's controls line is the same with and without a target, and a press changes no other field of the ship.
## It ends with "target_check: N failures" (0 = all good) and quits; after 120 s of real time "target_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=target_check
##
## WHO USES IT: main.gd loads it for --test=target_check. It sets no Game field and writes no settings file.

## The running match (set by setup()).
var world: World
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false
## The HUD (found when the check starts).
var _hud: Hud
## The human's ship.
var _ship: Ship
## The enemy units the cases use (live units of the other team, found when the check starts).
var _enemy: Array[Unit] = []
## The visible_mask each enemy had when the check started (put back at the end): uid -> mask.
var _masks := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 120 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 120000:
		print("target_check: timeout")
		get_tree().quit()
		return
	if get_tree().root.find_child("Hud", true, false) == null or world.camera == null:
		return
	if world.camera.followed() == null:
		return
	_started = true
	_run()


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(3)
	_hud = get_tree().root.find_child("Hud", true, false)
	_ship = world.camera.followed()
	var was_mouse: Variant = world.test_mouse
	var other := Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON
	for i in world.units.size():
		var o: Variant = world.units[i]
		if o != null and is_instance_valid(o) and (o as Unit).alive and (o as Unit).team == other and _enemy.size() < 6:
			_enemy.append(o as Unit)
	for u: Unit in _enemy:
		_masks[u.uid] = u.visible_mask
	_expect(_enemy.size() >= 5, "setup: the match has at least five live enemy units to work with (%d)" % _enemy.size())
	_expect(TargetKeys.my_ship(world) == _ship and _ship.controls.target_id == -1, "setup: the human's flying ship is my_ship() and starts with no target")
	if _enemy.size() >= 5:
		# The match stays paused from here, so no tick changes the fog bits or the places set by hand.
		get_tree().paused = true
		await _frames(2)
		_unseen_neutral()
		_nearest_and_ties()
		_last_attacker()
		_auto_next()
		_esc_order()
		await _middle_button()
		await _blocked()
		_log_and_fields()
		get_tree().paused = false
	for u: Unit in _enemy:
		if is_instance_valid(u):
			u.visible_mask = int(_masks[u.uid])
	_ship.controls.target_id = -1
	world.test_mouse = was_mouse
	print("target_check: %d failures" % failures)
	get_tree().quit()


## Part 1: an enemy the team cannot see is never picked, and a neutral unit never is.
func _unseen_neutral() -> void:
	var a := _enemy[0]
	_only_seen([])
	world.test_mouse = a.global_position
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == -1 and TargetKeys.nearest(world, a.global_position) == null, "an unseen enemy is never picked, even under the pointer")
	_only_seen([a])
	var b := _enemy[1]
	world.test_mouse = b.global_position
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == a.uid, "with one enemy seen, the pointer on an unseen one still picks the seen one")
	# Held but unseen: nothing is shown or changed, and the target stays held (the card draws nothing: ship_ring_check).
	_only_seen([])
	TargetKeys.tick(world)
	_expect(_ship.controls.target_id == a.uid and TargetKeys.held_unit(world, _ship) == a, "a held target that goes unseen stays held")
	_ship.controls.target_id = -1
	var neutral: Unit = null
	for i in world.units.size():
		var o: Variant = world.units[i]
		if o != null and is_instance_valid(o) and (o as Unit).alive and (o as Unit).team == Rules.NEUTRAL:
			neutral = o as Unit
			break
	if neutral != null:
		var was := neutral.visible_mask
		neutral.visible_mask = 3
		world.test_mouse = neutral.global_position
		TargetKeys.press(world, null)
		_expect(_ship.controls.target_id == -1 and not TargetKeys.is_candidate(world, neutral), "a neutral unit is never picked")
		neutral.visible_mask = was
	else:
		_expect(true, "(this match has no neutral unit: the neutral case is skipped)")
	var friend: Unit = null
	for i in world.units.size():
		var o: Variant = world.units[i]
		if o != null and is_instance_valid(o) and (o as Unit).alive and (o as Unit).team == world.human_team and o != _ship:
			friend = o as Unit
			break
	_expect(friend != null and not TargetKeys.is_candidate(world, friend), "a unit of the human's own team is never picked")


## Part 2a: the nearest enemy to the pointer, the tie, and the pick again (the last attacker) in the next part.
func _nearest_and_ties() -> void:
	var a := _enemy[0]
	var b := _enemy[1]
	var c := _enemy[2]
	var places := {}
	for u: Unit in [a, b, c]:
		places[u.uid] = u.global_position
	var p := Vector2(5000.0, 5000.0)
	# Three enemies on a line: the pointer is nearest the middle one.
	a.global_position = p + Vector2(-300.0, 0.0)
	b.global_position = p + Vector2(40.0, 0.0)
	c.global_position = p + Vector2(500.0, 0.0)
	_only_seen([a, b, c])
	world.test_mouse = p
	_ship.controls.target_id = -1
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == b.uid, "the enemy nearest the pointer is picked (the middle of three)")
	world.test_mouse = p + Vector2(-250.0, 0.0)
	_ship.controls.target_id = -1
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == a.uid, "moving the pointer picks the other nearest enemy")
	# A tie: two enemies the same distance from the pointer; the lower uid wins, whichever side it is on.
	a.global_position = p + Vector2(-100.0, 0.0)
	b.global_position = p + Vector2(100.0, 0.0)
	_only_seen([a, b])
	world.test_mouse = p
	var low := a if a.uid < b.uid else b
	_ship.controls.target_id = -1
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == low.uid, "a tie goes to the lower uid")
	a.global_position = p + Vector2(100.0, 0.0)
	b.global_position = p + Vector2(-100.0, 0.0)
	_ship.controls.target_id = -1
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == low.uid, "a tie goes to the lower uid on the other side too")
	for u: Unit in [a, b, c]:
		u.global_position = places[u.uid]
	_ship.controls.target_id = -1


## Part 2b: a second press on the target picks the last attacker.
func _last_attacker() -> void:
	var a := _enemy[0]
	var b := _enemy[1]
	var c := _enemy[2]
	var d := _enemy[3]
	var friend := _friend()
	var was_log := _ship.damage_log
	_only_seen([a, b, c, d])
	world.test_mouse = a.global_position
	_ship.controls.target_id = a.uid
	# The log: b hit at 5 s, c at 9 s, d at 7 s, and a friendly unit at 12 s, the newest of all: the friend never counts.
	_ship.damage_log = {b.uid: [10.0, 5.0, null], c.uid: [10.0, 9.0, null], d.uid: [10.0, 7.0, null]}
	if friend != null:
		_ship.damage_log[friend.uid] = [10.0, 12.0, null]
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == c.uid, "a press on the target picks the last attacker: the newest hit that a candidate made (c at 9 s)")
	# The pointer on another enemy picks that one (not the attacker).
	world.test_mouse = d.global_position
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == d.uid, "a press with another enemy under the pointer picks that enemy, not the attacker")
	# The same time twice: the lower uid.
	_ship.damage_log = {b.uid: [10.0, 9.0, null], c.uid: [10.0, 9.0, null]}
	_ship.controls.target_id = d.uid
	TargetKeys.press(world, null)
	var low := b if b.uid < c.uid else c
	_expect(_ship.controls.target_id == low.uid, "two attackers at the same time: the lower uid")
	# No attacker qualifies (one unseen, one dead): the target stays.
	_ship.damage_log = {b.uid: [10.0, 5.0, null], c.uid: [10.0, 9.0, null]}
	_only_seen([a, d])
	_ship.controls.target_id = d.uid
	world.test_mouse = d.global_position
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == d.uid, "when no attacker is a candidate the target stays")
	_ship.damage_log = {}
	_ship.controls.target_id = d.uid
	TargetKeys.press(world, null)
	_expect(_ship.controls.target_id == d.uid, "with an empty damage log a second press leaves the target")
	_ship.damage_log = was_log
	_ship.controls.target_id = -1


## Part 3: the target dies and the next nearest takes its place.
func _auto_next() -> void:
	var a := _enemy[0]
	var b := _enemy[1]
	var c := _enemy[2]
	var places := {}
	for u: Unit in [a, b, c]:
		places[u.uid] = u.global_position
	var p := Vector2(6000.0, 6000.0)
	a.global_position = p
	b.global_position = p + Vector2(80.0, 0.0)
	c.global_position = p + Vector2(900.0, 0.0)
	_only_seen([a, b, c])
	world.test_mouse = p
	_ship.controls.target_id = a.uid
	a.alive = false
	TargetKeys.tick(world)
	_expect(_ship.controls.target_id == b.uid, "when the target dies the enemy nearest the pointer takes its place")
	b.alive = false
	TargetKeys.tick(world)
	_expect(_ship.controls.target_id == c.uid, "and again when that one dies")
	c.alive = false
	TargetKeys.tick(world)
	_expect(_ship.controls.target_id == -1, "when no enemy is left the target is let go")
	a.alive = true
	b.alive = true
	c.alive = true
	# An id nobody holds any more (a unit freed): the same.
	_ship.controls.target_id = 987654
	TargetKeys.tick(world)
	_expect(_ship.controls.target_id == a.uid, "a target that is gone (freed) is replaced the same way")
	# A target that is alive and seen is left alone by the once-a-frame call.
	_ship.controls.target_id = c.uid
	TargetKeys.tick(world)
	_expect(_ship.controls.target_id == c.uid, "a living target is not changed by the frame call")
	for u: Unit in [a, b, c]:
		u.global_position = places[u.uid]
	_ship.controls.target_id = -1
	_expect(TargetKeys.AUTO_NEXT, "auto-next is on (a constant)")
	_expect(ShipControls.new().target_id == -1, "a new ship starts with no target")


## Part 4: the order Esc works through.
func _esc_order() -> void:
	var a := _enemy[0]
	_only_seen([a])
	var router := _hud.router
	_ship.controls.target_id = a.uid
	# The order wheel first.
	router._wheel_down = Time.get_ticks_msec()
	_key(router, KEY_ESCAPE)
	_expect(router._wheel_down == -1 and _ship.controls.target_id == a.uid, "Esc closes the order wheel first and the target stays")
	# Then a panel (the help pages).
	_hud._toggle_help()
	_expect(_hud._any_panel_open(), "setup: the help pages are open")
	_key(router, KEY_ESCAPE)
	_expect(not _hud._any_panel_open() and _ship.controls.target_id == a.uid and not _hud._pause_menu_active(), "with a panel open, Esc closes the panel and the target stays")
	# Then the command view (mode 3: view_open): it closes before the target goes.
	world.view_open = true
	_key(router, KEY_ESCAPE)
	_expect(not world.view_open and _ship.controls.target_id == a.uid, "with the command view open over the flight, Esc closes it and the target stays")
	# Then the target.
	_key(router, KEY_ESCAPE)
	_expect(_ship.controls.target_id == -1 and not _hud._pause_menu_active(), "with nothing else to close, Esc lets the target go and does not open the pause menu")
	# Then the pause menu.
	_key(router, KEY_ESCAPE)
	_expect(_hud._pause_menu_active(), "with no target, Esc opens the pause menu")
	_hud.pause_menu.resume()
	get_tree().paused = true


## Part 5: the middle button. A click marks the target, a drag does not, and the camera still pans.
func _middle_button() -> void:
	var a := _enemy[0]
	var b := _enemy[1]
	_only_seen([a, b])
	var cam := world.camera
	var was_free := cam.free
	cam.free = true
	cam._free_pos = cam.global_position
	world.test_mouse = a.global_position
	_ship.controls.target_id = -1
	var spot := Vector2(640.0, 400.0)
	# A click: down and up 3 pixels apart.
	_mouse_button(true, spot)
	await _frames(1)
	_expect(cam._drag, "the camera gets the middle press (its drag starts) although the target key reads it too")
	_mouse_button(false, spot + Vector2(2.0, 2.0))
	await _frames(2)
	_expect(_ship.controls.target_id == a.uid and not cam._drag, "a middle press and release 3 pixels apart marks the target, and the camera's drag ends")
	# A drag: down and up 40 pixels apart. No target, and the camera moved.
	_ship.controls.target_id = -1
	var before := cam._free_pos
	_mouse_button(true, spot)
	await _frames(1)
	_mouse_motion(spot + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	await _frames(1)
	var moved := cam._free_pos.distance_to(before)
	_mouse_button(false, spot + Vector2(40.0, 0.0))
	await _frames(2)
	_expect(_ship.controls.target_id == -1, "a middle press and release 40 pixels apart (a drag) marks nothing")
	_expect(moved > 5.0, "the middle drag still pans the free camera (%.1f world units)" % moved)
	# Just under and just over the limit.
	world.test_mouse = b.global_position
	_mouse_button(true, spot)
	_mouse_button(false, spot + Vector2(5.0, 0.0))
	await _frames(2)
	_expect(_ship.controls.target_id == b.uid, "5 pixels apart is still a click")
	_ship.controls.target_id = -1
	_mouse_button(true, spot)
	_mouse_button(false, spot + Vector2(6.0, 0.0))
	await _frames(2)
	_expect(_ship.controls.target_id == -1, "6 pixels apart is a drag")
	# The same press twice picks the last attacker (the mouse route of the second press).
	var was_log := _ship.damage_log
	_ship.damage_log = {a.uid: [5.0, 3.0, null]}
	_ship.controls.target_id = b.uid
	_mouse_button(true, spot)
	_mouse_button(false, spot)
	await _frames(2)
	_expect(_ship.controls.target_id == a.uid, "a second middle click on the target picks the last attacker")
	_ship.damage_log = was_log
	_ship.controls.target_id = -1
	cam.free = was_free


## Part 6: nothing happens while the note box is open, the pause menu holds the game, or the command view is open over the flight.
func _blocked() -> void:
	var a := _enemy[0]
	_only_seen([a])
	world.test_mouse = a.global_position
	var router := _hud.router
	var spot := Vector2(640.0, 400.0)
	# The note box has the keyboard.
	_hud._open_note()
	_expect(_hud._note_is_open(), "setup: the note box is open")
	_key(router, KEY_CAPSLOCK)
	_mouse_button(true, spot)
	_mouse_button(false, spot)
	await _frames(2)
	_expect(_ship.controls.target_id == -1, "while the note box is open the key and the click do nothing")
	_hud.note_box.cancel()
	get_tree().paused = true
	# The pause menu holds the game.
	_hud._toggle_pause_menu()
	_expect(_hud._pause_menu_active(), "setup: the pause menu holds the game")
	_key(router, KEY_CAPSLOCK)
	_mouse_button(true, spot)
	_mouse_button(false, spot)
	await _frames(2)
	_expect(_ship.controls.target_id == -1, "while the pause menu holds the game the key and the click do nothing")
	_hud.pause_menu.resume()
	get_tree().paused = true
	await _frames(1)
	# Mode 3: the view is open over the flight, the ship coasts: no cues, no ring, no target.
	var cues: TurnCues = null
	for c in _hud.get_children():
		if c is TurnCues:
			cues = c
	world.view_open = true
	_expect(cues != null and cues.cue_ship() == null and TargetKeys.my_ship(world) == null, "with the command view open over the flight, the cues and the target keys have no ship")
	_key(router, KEY_CAPSLOCK)
	_expect(_ship.controls.target_id == -1, "with the command view open a Caps Lock press changes nothing")
	world.view_open = false
	_expect(cues != null and cues.cue_ship() == _ship, "the cues come back when the view closes")
	# The key itself, with everything open to it: it marks the target.
	_key(router, KEY_CAPSLOCK)
	_expect(_ship.controls.target_id == a.uid, "Caps Lock marks the enemy nearest the pointer when nothing blocks it")
	_ship.controls.target_id = -1


## Part 7: the match log never names the target, and a press writes nothing but target_id.
func _log_and_fields() -> void:
	var a := _enemy[0]
	_only_seen([a])
	world.test_mouse = a.global_position
	_ship.controls.target_id = -1
	var line_without := HumanLines.controls_body(_ship.controls)
	var ship_before := _fields(_ship)
	var controls_before := _fields(_ship.controls)
	_key(_hud.router, KEY_CAPSLOCK)
	_expect(_ship.controls.target_id == a.uid, "setup: the key marked a target")
	var line_with := HumanLines.controls_body(_ship.controls)
	_expect(line_with == line_without, "the match log's controls line is the same with and without a target")
	var controls_after := _fields(_ship.controls)
	controls_before.erase("target_id")
	controls_after.erase("target_id")
	_expect(controls_before == controls_after, "a press changes no other field of the ship's controls")
	_expect(_fields(_ship) == ship_before, "a press changes no field of the ship itself")
	_ship.controls.target_id = -1


## Make exactly the enemy units in `seen` visible to the human's team (every other enemy of the check unseen).
func _only_seen(seen: Array) -> void:
	var bit := 1 << world.human_team
	for u: Unit in _enemy:
		u.visible_mask &= ~bit
	for o: Variant in seen:
		(o as Unit).visible_mask |= bit


## A live unit of the human's own team that is not the human's ship (the mothership, a turret), or null.
func _friend() -> Unit:
	for i in world.units.size():
		var o: Variant = world.units[i]
		if o != null and is_instance_valid(o) and (o as Unit).alive and (o as Unit).team == world.human_team and o != _ship:
			return o as Unit
	return null


## Press and let go of key `code` through HudInput.handle() (the same path the HUD's own key input takes).
func _key(router: HudInput, code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		router.handle(ev)


## Send mouse button `middle` down or up at screen point `at` through the engine's input path (the HUD and the camera both see it).
func _mouse_button(down: bool, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


## Send a mouse move to `at` (by `rel`) through the engine's input path.
func _mouse_motion(at: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.relative = rel
	Input.parse_input_event(ev)


## Every script variable of `n` as a Dictionary name -> value (a copy, to compare before and after).
func _fields(n: Object) -> Dictionary:
	var out := {}
	for p: Dictionary in n.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			var v: Variant = n.get(String(p["name"]))
			out[String(p["name"])] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## Count a PASS or FAIL line for the check `what`.
func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
