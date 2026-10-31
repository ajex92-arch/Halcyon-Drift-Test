extends Node
## WHAT THIS IS: the check of the speed control and (in later parts) the Controls page: it presses the
## speed keys in a real match and clicks the speed row, and proves the world speed, the HUD tag and the
## refusals are what the speed lists say.
##
## HOW IT WORKS: setup() starts run(), which waits for the HUD and for play, then runs the parts in order
## and prints "controls_page_check: N failures" (a FAIL line for each failure). The speed part: the
## backquote key steps 1x, 0.75x, 0.5x, 1x and the top bar's tag follows; Shift plus it steps the faster
## list (SpeedControl.fast_steps()) and, while that list is empty, changes nothing and says so (which also
## proves the plain key's action does not fire for Shift plus the key); a faster speed that is asked for
## and is not on the list is refused; the buttons of a SpeedRow set the speed and show the one in force;
## the row can be greyed with a reason. The seam part (_seam) proves that a speed change is a GAME_SPEED order
## in the order queue from the human's seat, and that two human seats refuse it with the control's words.
## Keys are pushed into the window the way a keyboard does, so the
## HUD's real key handling runs. The parts that need no match work the same way in a headless run.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --test=controls_page_check
##
## WHO USES IT: main.gd loads it for --test=controls_page_check (it calls setup()); run_checks runs it.

## The running match.
var world: World
## The HUD, found once it exists.
var hud: Hud = null
## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	_run.call_deferred()


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Wait for the HUD and for play, run the parts, print the result and quit.
func _run() -> void:
	for _i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and world.phase == "play":
			break
		await get_tree().process_frame
	if hud == null:
		_check("the HUD exists (use --force-hud)", false)
	else:
		await get_tree().process_frame
		await _speed()
		_seam()
	await _page()
	print("controls_page_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Key `code` (with Shift when `shift`) going down and up, pushed into the window as a keyboard sends it.
func _tap_key(code: Key, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.shift_pressed = shift
		ev.pressed = down
		get_viewport().push_input(ev, true)


## The HUD's tag line text ("" when it is hidden), after the top bar redrew it.
func _tag_text() -> String:
	hud.top_bar.refresh(world)
	var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
	return tags.text if tags.visible else ""


## The words of the HUD's pop-up hint now.
func _toast_text() -> String:
	return (hud.toast_box.get_node("Text") as Label).text


## The speed part (see HOW IT WORKS).
func _speed() -> void:
	_check("the match starts at normal speed with no tag", world.speed.factor == 1.0 and _tag_text() == "", _tag_text())
	# Step 1: the slower key, three presses and back.
	var seen := []
	var tags := []
	for i in 3:
		_tap_key(KEY_QUOTELEFT)
		seen.append(world.speed.factor)
		tags.append(_tag_text())
	_check("the backquote key steps 0.75x, 0.5x, 1x", seen == [0.75, 0.5, 1.0], str(seen))
	_check("the tag follows (SPEED 0.75x, SPEED 0.5x, none)", tags == ["SPEED 0.75x", "SPEED 0.5x", ""], str(tags))
	# Step 2: the faster key. With no faster speed it changes nothing (and the plain key's action must
	# not fire for Shift plus the key); with a list it steps through it.
	var fast := SpeedControl.fast_steps()
	if fast.is_empty():
		_tap_key(KEY_QUOTELEFT, true)
		_check("no faster speeds yet: Shift plus the key changes nothing", world.speed.factor == 1.0, str(world.speed.factor))
		_check("no faster speeds yet: it says so", _toast_text() == SpeedControl.NO_FAST_YET, _toast_text())
		_check("the row has no faster speeds: 150 and 200 are refused", SpeedControl.send(world, 150) == SpeedControl.NOT_READY and SpeedControl.send(world, 200) == SpeedControl.NOT_READY)
	else:
		var got := []
		for i in fast.size():
			_tap_key(KEY_QUOTELEFT, true)
			got.append(roundi(world.speed.factor * 100.0))
		var want := []
		for i in fast.size():
			want.append(fast[(i + 1) % fast.size()])
		_check("Shift plus the key steps the faster list %s" % str(fast), got == want, str(got))
		_tap_key(KEY_QUOTELEFT, true)
		world.speed.set_factor(1.0)
	_check("a number that is not a speed is refused", SpeedControl.send(world, 175) == SpeedControl.NOT_A_SPEED)
	# Step 3: a slow speed, then Shift plus the key goes through normal first.
	_tap_key(KEY_QUOTELEFT)
	_tap_key(KEY_QUOTELEFT, true)
	_check("Shift plus the key from 0.75x goes to normal first (it does nothing while there is no faster list)", is_equal_approx(world.speed.factor, 1.0 if not fast.is_empty() else 0.75), str(world.speed.factor))
	world.speed.set_factor(1.0)
	# Step 4: the row.
	var row := SpeedRow.new()
	hud.add_child(row)
	row.setup(world)
	await get_tree().process_frame
	var want_buttons: Array = SpeedControl.all_steps()
	var have: Array = row._buttons.keys()
	have.sort()
	_check("the row has a button for every speed in the lists %s" % str(want_buttons), have == want_buttons, str(have))
	row._buttons[50].pressed.emit()
	_check("the 0.5x button sets 0.5x", world.speed.factor == 0.5, str(world.speed.factor))
	await get_tree().process_frame
	_check("the row shows 0.5x as the one in force", (row._buttons[50] as Button).button_pressed and not (row._buttons[100] as Button).button_pressed)
	_check("the tag says SPEED 0.5x", _tag_text() == "SPEED 0.5x", _tag_text())
	row._buttons[100].pressed.emit()
	_check("the 1x button goes back to normal", world.speed.factor == 1.0 and _tag_text() == "")
	row._buttons[75].pressed.emit()
	_check("the 0.75x button sets 0.75x", world.speed.factor == 0.75)
	for f: int in [150, 200]:
		_check("the row has %d only if the faster list has it" % f, row._buttons.has(f) == fast.has(f))
	_check("with no faster speeds the row says so", not fast.is_empty() or row._note.text == "faster: with the orders stage", row._note.text)
	row.show_blocked(SpeedControl.ONLINE)
	var all_off := true
	for b: Button in row._buttons.values():
		all_off = all_off and b.disabled
	_check("a blocked row greys every button and says why", all_off and row._note.text == SpeedControl.ONLINE)
	row.show_blocked("")
	_check("an unblocked row works again", not (row._buttons[100] as Button).disabled)
	world.speed.set_factor(1.0)
	row.queue_free()


## How many GAME_SPEED orders the human's team has submitted so far (the order queue's counter).
func _speed_orders() -> int:
	var rows: Dictionary = world.orders.counters().get("t%d" % world.human_team, {})
	return int((rows.get(OrderKinds.GAME_SPEED, {}) as Dictionary).get("submitted", 0))


## The seam to the order queue (see HOW IT WORKS): a speed change is a GAME_SPEED order from the human's
## seat; a faster speed is accepted; two human seats refuse it with the control's words; a number that is
## not a speed makes no order.
func _seam() -> void:
	var q := world.orders
	var seat: int = Rules.ADMIRAL_SEAT if world.human_role == "admiral" else world.human.slot
	var first := _speed_orders()
	var applied_before := q.applied
	_check("the seam: the match has one human seat, so the control allows a change", q.human_seats() == 1 and SpeedControl.allowed(world), str(q.human_seats()))
	_check("the seam: 1.5x is accepted", SpeedControl.send(world, 150) == "" and is_equal_approx(world.speed.factor, 1.5), str(world.speed.factor))
	var o: Dictionary = q.last_submitted
	_check("the seam: it was a GAME_SPEED order of 150 from the human's seat and team", str(o.get("kind", "")) == OrderKinds.GAME_SPEED and int((o.get("settings", {}) as Dictionary).get("hundredths", 0)) == 150 and int(o.get("seat", -9)) == seat and bool(o.get("human", false)) and int(o.get("team", -1)) == world.human_team, str(o))
	_check("the seam: the queue counted it as submitted and carried out", _speed_orders() == first + 1 and q.applied == applied_before + 1, "%d/%d applied %d/%d" % [_speed_orders(), first + 1, q.applied, applied_before + 1])
	_check("the seam: the top bar tag says SPEED 1.5x", _tag_text() == "SPEED 1.5x", _tag_text())
	_check("the seam: 2x is accepted", SpeedControl.send(world, 200) == "" and is_equal_approx(world.speed.factor, 2.0) and _tag_text() == "SPEED 2x", _tag_text())
	_check("the seam: a number that is not a speed is refused by the control and makes no order", SpeedControl.send(world, 175) == SpeedControl.NOT_A_SPEED and _speed_orders() == first + 2 and is_equal_approx(world.speed.factor, 2.0))
	q.human_seats_override = 2
	_check("the seam: with two human seats the control does not allow a change", not SpeedControl.allowed(world))
	_check("the seam: and the queue's refusal 'online' comes back as the control's words", SpeedControl.send(world, 100) == SpeedControl.ONLINE and is_equal_approx(world.speed.factor, 2.0))
	_check("the seam: the refused order was counted too (refused, online)", _speed_orders() == first + 3 and int((((q.counters().get("t%d" % world.human_team, {}) as Dictionary).get(OrderKinds.GAME_SPEED, {}) as Dictionary).get("refused", {}) as Dictionary).get("online", 0)) == 1)
	q.human_seats_override = -1
	_check("the seam: one human seat again, the change goes through", SpeedControl.allowed(world) and SpeedControl.send(world, 100) == "" and is_equal_approx(world.speed.factor, 1.0) and _tag_text() == "")
	world.speed.set_factor(1.0)


# --- the Controls page ----------------------------------------------------------------------

## A new page in the test, saving to a temporary file (never the player's settings file), on the standard keys.
func _new_page(path: String) -> ControlsPage:
	KeyMap.reset_to_defaults()
	var page: ControlsPage = load("res://scenes/ui/controls_page.tscn").instantiate()
	page.save_path = path
	add_child(page)
	return page


## The first key of row `id` of `m`, or "" when it has none.
func _key(m: String, id: String) -> String:
	var k := KeyMap.effective_keys(m, id)
	return String(k[0]) if not k.is_empty() else ""


## Press `text` as the key a player chose for the awaited slot (the same path a key press takes).
func _choose(page: ControlsPage, m: String, id: String, slot: int, text: String, btn: Button = null) -> void:
	var began := page.begin_capture(m, id, slot, btn)
	_check("capture can begin for %s/%s" % [m, id], began)
	page.capture_text(text)


## A key press event for the page's capture, as a keyboard sends it.
func _key_event(code: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.shift_pressed = shift
	return ev


## No mode has two rows with the same key.
func _no_clashes(what: String) -> void:
	for m: String in KeyMapData.MODES:
		_check("%s: no clash is left in %s" % [what, m], KeyMap.mode_clashes(m).is_empty(), str(KeyMap.mode_clashes(m)))


## The page part (see the file's header): capture, clashes, swap, keep, resets, key sets and the file.
func _page() -> void:
	var tmp := OS.get_cache_dir().path_join("hd_controls_check_%d.cfg" % OS.get_process_id())
	DirAccess.remove_absolute(tmp)
	var page := _new_page(tmp)
	_check("the page does not save to the player's settings file", page.save_path != Game.SETTINGS_FILE and page._path() != Game.SETTINGS_FILE)
	await get_tree().process_frame
	# Step 1: every tab builds, with its rows; the Home tab has the layout picker.
	for m: String in ["home", "flying", "flying_board"]:
		page.show_mode(m)
		_check("tab %s lists rows" % m, page.rows_part.buttons.size() >= 20, str(page.rows_part.buttons.size()))
	page.show_mode("home")
	_check("the Home tab has the layout picker", page._pickers.visible and page._pickers.get_child_count() >= 3)
	page.show_mode("flying")
	_check("the Flying tab has no layout picker", not page._pickers.visible)
	# Step 2: capture and Esc.
	var btn := Button.new()
	btn.text = "R"
	add_child(btn)
	page.begin_capture("flying", "use_kit", 0, btn)
	_check("a click waits for a key and says so", page.capture.active and btn.text == "Press a key (Esc cancels)", btn.text)
	_check("Esc cancels the wait and is used up", page.capture.handle(_key_event(KEY_ESCAPE, true)) and not page.capture.active and btn.text == "R")
	_check("a cancelled capture changed nothing", _key("flying", "use_kit") == "R")
	# Step 3: a free key is taken at once, applied to the controls and saved.
	_choose(page, "flying", "use_kit", 0, "K")
	_check("a free key is taken", _key("flying", "use_kit") == "K")
	_check("the InputMap follows (use_kit is K)", InputMap.action_get_events("use_kit").size() == 1 and int((InputMap.action_get_events("use_kit")[0] as InputEventKey).physical_keycode) == KEY_K)
	var cfg := ConfigFile.new()
	_check("the change is saved to the file", cfg.load(tmp) == OK and str(cfg.get_value("keys", "flying/use_kit", "")) == "K|", str(cfg.get_value("keys", "flying/use_kit", "")))
	_check("a changed row shows its Reset", _count_resets(page) == 1)
	# Step 4: a clash shows the warning with the triangle and names every action; it stays.
	_choose(page, "flying", "use_kit", 0, "W")
	_check("a clash is pending", not page.pending.is_empty())
	_check("the warning is shown", page._warn.visible and page._warn_text.text.contains("Thrust forward") and page._warn_text.text.contains("Swap, or keep the old one."), page._warn_text.text)
	_check("the warning has the danger triangle", page._warn.get_child(0) is DangerMark and page._warn_text.get_theme_color("font_color") == Palette.DANGER)
	_check("the key was not taken", _key("flying", "use_kit") == "K" and _key("flying", "thrust_forward") == "W")
	_check("the page is locked while the clash waits", not page.begin_capture("flying", "use_kit", 1) and (page._tabs["home"] as Button).disabled and page.rows_part.buttons[0].disabled)
	await get_tree().create_timer(0.6).timeout
	_check("the warning stays (no timer takes it away)", page._warn.visible and not page.pending.is_empty())
	page.choose_keep()
	_check("Keep changes nothing and clears the warning", not page._warn.visible and page.pending.is_empty() and _key("flying", "use_kit") == "K" and _key("flying", "thrust_forward") == "W")
	_check("after Keep the page works again", not (page._tabs["home"] as Button).disabled)
	# Step 5: Swap exchanges the two.
	KeyMap.reset_all()
	_choose(page, "flying", "use_kit", 0, "V")
	_check("one clash that can change offers Swap", not (page.pending.get("swap", {}) as Dictionary).is_empty() and page._swap_button.visible)
	page.choose_swap()
	_check("Swap: use_kit has V and Flight assist has R", _key("flying", "use_kit") == "V" and _key("flying", "assist_toggle") == "R", "%s %s" % [_key("flying", "use_kit"), _key("flying", "assist_toggle")])
	_no_clashes("after Swap")
	# A swap that would make a new clash is not offered: R would be the camera key at home, where the grid has R.
	KeyMap.reset_all()
	_choose(page, "flying", "use_kit", 0, "W")
	_check("a swap that would clash somewhere else offers Keep only", not page.pending.is_empty() and (page.pending["swap"] as Dictionary).is_empty() and not page._swap_button.visible and page._keep_button.visible, page._warn_text.text)
	page.choose_keep()
	# Step 6: several clashes, a fixed row and a rule variant give Keep only.
	KeyMap.reset_all()
	page.show_mode("home")
	_choose(page, "home", "idle_next", 0, "R")
	_check("a key on three pages: all three are named and only Keep is offered", page.pending["clashes"].size() == 3 and not page._swap_button.visible and page._keep_button.visible, str(page.pending.get("clashes", []).size()))
	page.choose_keep()
	page.show_mode("flying")
	_choose(page, "flying", "use_kit", 0, "G")
	_check("a fixed row's key (G, the ability) gives Keep only", not page.pending.is_empty() and not page._swap_button.visible)
	page.choose_keep()
	Game.variants["surrender"] = "on"
	_choose(page, "flying", "use_kit", 0, "F10")
	_check("a key a rule variant that is on reads gives Keep only", not page.pending.is_empty() and not page._swap_button.visible and page._warn_text.text.contains("surrender"), page._warn_text.text)
	page.choose_keep()
	Game.variants["surrender"] = "off"
	_choose(page, "flying", "use_kit", 0, "F10")
	_check("the same key is free while that variant is off", _key("flying", "use_kit") == "F10")
	KeyMap.reset_all()
	page.rebuild()
	# Step 7: fixed rows refuse a capture.
	for id in ["fire", "special", "face_lock"]:
		_check("%s cannot be changed" % id, not page.begin_capture("flying", id, 0))
	# Step 8: real key events: Shift+K, Shift alone, a side mouse button.
	page.begin_capture("flying", "use_kit", 0, btn)
	page.capture.handle(_key_event(KEY_SHIFT, true, true))
	page.capture.handle(_key_event(KEY_K, true, true))
	_check("Shift then K is Shift+K", _key("flying", "use_kit") == "Shift+K", _key("flying", "use_kit"))
	page.begin_capture("flying", "assist_toggle", 0, btn)
	page.capture.handle(_key_event(KEY_SHIFT, true, true))
	page.capture.handle(_key_event(KEY_SHIFT, false))
	_check("Shift let go alone is the key Shift, which Boost has: a clash", not page.pending.is_empty() and page._warn_text.text.contains("Boost"), page._warn_text.text)
	page.choose_keep()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	page.begin_capture("flying", "assist_toggle", 1, btn)
	_check("a side mouse button is used up", page.capture.handle(mb))
	_check("mouse button 4 clashes with the team wheel", not page.pending.is_empty() and page._warn_text.text.contains("Team wheel"), page._warn_text.text)
	page.choose_keep()
	var lb := InputEventMouseButton.new()
	lb.button_index = MOUSE_BUTTON_LEFT
	lb.pressed = true
	page.begin_capture("flying", "assist_toggle", 1, btn)
	_check("the left mouse button is the click and cannot be chosen", not page.capture.handle(lb) and page.capture.active)
	page.capture.cancel()
	# Step 9: resets ask once.
	KeyMap.reset_all()
	_choose(page, "flying", "use_kit", 0, "K")
	_choose(page, "flying", "assist_toggle", 0, "J")
	page.ask_reset_mode()
	_check("Reset this mode asks first", page._ask_box.visible and _key("flying", "use_kit") == "K")
	page.confirm_no()
	_check("No leaves the keys", _key("flying", "use_kit") == "K" and not page._ask_box.visible)
	page.ask_reset_mode()
	page.confirm_yes()
	_check("Yes puts the tab's keys back", _key("flying", "use_kit") == "R" and _key("flying", "assist_toggle") == "V")
	_choose(page, "flying", "use_kit", 0, "K")
	page.reset_row("flying", "use_kit")
	_check("a row's own Reset puts it back", _key("flying", "use_kit") == "R" and _count_resets(page) == 0)
	_choose(page, "flying", "use_kit", 0, "K")
	page.ask_reset_all()
	page.confirm_yes()
	_check("Reset all puts everything back", _key("flying", "use_kit") == "R" and KeyMap.overrides().is_empty() and KeyMap.choices().is_empty())
	# Step 10: the key sets.
	page.show_mode("home")
	_check("the default layout is B", KeyMap.preset_choice("home_layout") == "B" and _key("home", "order_attack_move") == "R" and _key("home", "hangar") == "B" and _key("home", "help") == "F12")
	_choose(page, "home", "order_attack_move", 0, "K")
	_check("a change on a row of the layout", _key("home", "order_attack_move") == "K")
	page.pick_preset("home_layout", "A")
	_check("picking a layout asks first", page._ask_box.visible and KeyMap.preset_choice("home_layout") == "B")
	page.confirm_yes()
	_check("layout A: Q W E R / A S D F / Z X C V", KeyMap.preset_choice("home_layout") == "A" and _key("home", "order_move") == "Q" and _key("home", "order_attack_move") == "A" and _key("home", "base_turret") == "Q" and _key("home", "camera_up") == "Up")
	_check("layout A: the change on a row it lists was cleared", not KeyMap.is_changed("home", "order_attack_move"))
	_check("layout A: B is the hangar everywhere, C is not the camera key", _key("home", "hangar") == "B" and KeyMap.page_of("home", "hangar") == "" and _key("home", "center_camera") == "" and _key("home", "help") == "H")
	_check("layout A has no key of layout B's grid (order_goal is hidden)", not KeyMap.is_visible("home", "order_goal"))
	page.pick_preset("home_layout", "C")
	page.confirm_yes()
	_check("layout C: R attack-move, N merge, Z hold, no grid", _key("home", "order_attack_move") == "R" and _key("home", "order_merge") == "N" and _key("home", "order_hold") == "Z" and not KeyMap.is_visible("home", "build_fighter"))
	_check("layout C: the camera follows the pilot's keys again", KeyMap.is_linked("home", "camera_up") and _key("home", "camera_up") == "W")
	page.pick_preset("home_layout", "B")
	page.confirm_yes()
	_check("layout B again", _key("home", "order_attack_move") == "R" and _key("home", "base_ward") == "H" and _key("home", "help") == "F12" and _key("home", "team_wheel") == "Mouse4")
	cfg = ConfigFile.new()
	_check("the choice is saved", cfg.load(tmp) == OK and str(cfg.get_value("keys", "preset/home_layout", "")) == "B")
	_no_clashes("after the layouts")
	# Step 11: a link row edits the pilot's key, in one place.
	page.show_mode("flying_board")
	_choose(page, "flying_board", "camera_up", 0, "O")
	_check("changing the board's camera key changes the flying key", _key("flying", "thrust_forward") == "O" and _key("flying_board", "camera_up") == "O" and _key("home", "camera_up") == "O")
	_check("the InputMap follows (thrust_forward is O)", int((InputMap.action_get_events("thrust_forward")[0] as InputEventKey).physical_keycode) == KEY_O)
	_no_clashes("after the camera key")
	KeyMap.reset_all()
	# Step 12: the settings file round trip and bad entries.
	await _file_part(tmp)
	DirAccess.remove_absolute(tmp)
	page.queue_free()
	btn.queue_free()
	KeyMap.reset_to_defaults()
	_check("the controls are back to the standard ones", InputMap.action_get_events("use_kit").size() == 1 and int((InputMap.action_get_events("use_kit")[0] as InputEventKey).physical_keycode) == KEY_R)


## How many little Reset buttons the page shows now.
func _count_resets(page: ControlsPage) -> int:
	var n := 0
	for h in page._body.get_children():
		if h is HBoxContainer:
			for c in h.get_children():
				for g in c.get_children():
					if g is Button and (g as Button).text == "Reset":
						n += 1
	return n


## The settings file: a round trip, a bad entry falling back, no duplicate kept, a missing file.
func _file_part(tmp: String) -> void:
	KeyMap.reset_to_defaults()
	KeyMap.set_slot("flying", "use_kit", 0, "K")
	KeyMap.set_slot("home", "idle_next", 1, "Mouse3")
	KeyMap.set_preset("home_layout", "A")
	KeyMap.set_slot("home", "order_move", 0, "G")
	var want := {"use": KeyMap.effective_keys("flying", "use_kit"), "idle": KeyMap.effective_keys("home", "idle_next"), "move": KeyMap.effective_keys("home", "order_move"), "text": KeyMapText.help_text()}
	_check("the file is written", KeyMap.save(tmp) == OK)
	KeyMap.reset_to_defaults()
	_check("back to the defaults", _key("flying", "use_kit") == "R" and KeyMap.preset_choice("home_layout") == "B")
	KeyMap.load_from(tmp)
	_check("the data round-trips through the file", KeyMap.effective_keys("flying", "use_kit") == want["use"] and KeyMap.effective_keys("home", "idle_next") == want["idle"] and KeyMap.effective_keys("home", "order_move") == want["move"] and KeyMap.preset_choice("home_layout") == "A", str(KeyMap.overrides()))
	_check("the Keys page text is the same after the round trip", KeyMapText.help_text() == want["text"])
	_check("a clean file drops nothing", KeyMap.last_dropped == 0, str(KeyMap.last_dropped))
	# Bad entries: an unknown action, an unreadable key, a fixed row, Esc, a clash, three keys, an unknown set.
	var bad := ConfigFile.new()
	bad.load(tmp)
	bad.set_value("keys", "flying/no_such_action", "A|B")
	bad.set_value("keys", "flying/boost", "Banana")
	bad.set_value("keys", "flying/fire", "K")
	bad.set_value("keys", "flying/dock", "Esc")
	bad.set_value("keys", "flying/assist_toggle", "W")
	bad.set_value("keys", "flying/shield_front", "A|B|C")
	bad.set_value("keys", "preset/home_layout", "Z")
	bad.set_value("keys", "preset/no_such_group", "A")
	bad.set_value("game", "difficulty", "hard")
	bad.save(tmp)
	KeyMap.load_from(tmp)
	_check("bad entries fall back to the defaults", _key("flying", "boost") == "Shift" and _key("flying", "fire") == "Mouse1" and _key("flying", "dock") == "F" and _key("flying", "assist_toggle") == "V" and _key("flying", "shield_front") == "Up")
	_check("an unknown key set is dropped and the default one stays", KeyMap.preset_choice("home_layout") == "B")
	_check("each bad entry was counted (8)", KeyMap.last_dropped == 8, str(KeyMap.last_dropped))
	_no_clashes("after a bad file")
	# Saving keeps the other sections of the file and writes no duplicate.
	KeyMap.save(tmp)
	var after := ConfigFile.new()
	_check("saving keeps the file's other sections", after.load(tmp) == OK and str(after.get_value("game", "difficulty", "")) == "hard")
	# Two rows saved with the same key: one is left out.
	var dup := ConfigFile.new()
	dup.set_value("keys", "flying/use_kit", "K")
	dup.set_value("keys", "flying/assist_toggle", "K")
	dup.save(tmp)
	KeyMap.load_from(tmp)
	_check("no duplicate is ever kept within a mode", not (_key("flying", "use_kit") == "K" and _key("flying", "assist_toggle") == "K") and KeyMap.last_dropped >= 1)
	_no_clashes("after a file with a duplicate")
	# A swap is two changes that are right only together: it must load.
	KeyMap.reset_to_defaults()
	KeyMap.set_slot("flying", "use_kit", 0, "K")
	KeyMap.swap("flying", "assist_toggle", 0, "K", "flying", "use_kit")
	KeyMap.save(tmp)
	var swapped := [_key("flying", "assist_toggle"), _key("flying", "use_kit")]
	KeyMap.load_from(tmp)
	_check("a swap loads as it was saved", [_key("flying", "assist_toggle"), _key("flying", "use_kit")] == swapped and KeyMap.last_dropped == 0, str(swapped))
	DirAccess.remove_absolute(tmp)
	KeyMap.load_from(tmp)
	_check("a missing file leaves the defaults", _key("flying", "use_kit") == "R" and KeyMap.overrides().is_empty() and KeyMap.last_dropped == 0)
	KeyMap.reset_to_defaults()
