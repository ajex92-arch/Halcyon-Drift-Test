extends RtsUiCheckBase
## WHAT THIS IS: the check of the control groups (E1): F1 to F8 through the HUD's real key router: a tap selects, Ctrl sets,
## Shift adds, one group per squadron, a second tap within GROUP_DOUBLE_TAP_S centres the camera (and frees a camera that
## follows the ship), an empty group says so and leaves the selection alone, and while flying with the board closed a
## group is only picked, the camera staying where it is. Dead squadrons drop out of a group. RT7 7c adds the double tap's flash:
## in field mode a second tap flashes the group's squadrons on the minimap (once a double tap, at most one flash in 334 ms,
## none for an empty group, the camera staying put); in mode 3 and docked the signal is emitted and no ring is drawn.
##
## HOW IT WORKS: the base fills both fleets and finds the HUD; each case selects squadrons through the overlay, sends keys
## through hud.router.handle() and reads Groups (hud.command_view.groups), the overlay's selection and the camera. The
## double tap uses the groups' own test clock (fake_ms), so no case waits.
##
## HOW TO RUN IT: see RtsUiCheckBase (--test=rts_groups_check).
##
## WHO USES IT: main.gd loads it for --test=rts_groups_check; the run_checks list has a row for it.


func _init() -> void:
	label = "rts_groups_check"


func run() -> void:
	var g := hud.command_view.groups
	var ov := hud.overlay
	var all := squads()
	check("setup: the fleet fill made at least 5 squadrons", all.size() >= 5, "%d" % all.size())
	if all.size() < 5:
		return
	var a := all[0].id
	var b := all[1].id
	var c := all[2].id
	var d := all[3].id
	var e := all[4].id
	check("setup: the groups start empty and the key rows are live", g.members(1).is_empty() and g.first_free() == 1 and not KeyMap.effective_keys("shared", "group_1").is_empty())
	# Ctrl+F1 sets group 1 to the selection; the group keeps the order of the selection.
	ov.set_selection([a, b, c], false)
	key(KEY_F1, true)
	check("set: Ctrl+F1 sets group 1 to the three selected squadrons", g.members(1) == [a, b, c], str(g.members(1)))
	check("set: group_of says 1 for each, 0 for another", g.group_of(a) == 1 and g.group_of(c) == 1 and g.group_of(d) == 0)
	check("set: the first free group moves on to 2", g.first_free() == 2)
	# F1 selects it, replacing the selection, without moving the camera.
	ov.clear_selection()
	var before: Vector2 = world.camera._free_pos
	g.fake_ms = 100000
	key(KEY_F1)
	check("pick: F1 selects group 1", ov.sel_squads == [a, b, c], str(ov.sel_squads))
	check("pick: one tap does not move the camera", world.camera._free_pos.is_equal_approx(before))
	check("pick: the group is current", g.current == 1)
	# One group per squadron: Ctrl+F2 on [a, d] takes a out of group 1.
	ov.set_selection([a, d], false)
	key(KEY_F2, true)
	check("one per squad: group 2 is a and d", g.members(2) == [a, d], str(g.members(2)))
	check("one per squad: a left group 1", g.members(1) == [b, c], str(g.members(1)))
	# Shift+F1 adds the selection to group 1 (and takes it out of group 2).
	ov.set_selection([d, e], false)
	key(KEY_F1, false, true)
	check("add: Shift+F1 adds d and e to group 1", g.members(1) == [b, c, d, e], str(g.members(1)))
	check("add: d left group 2", g.members(2) == [a], str(g.members(2)))
	# The Add toggle: a pick adds to the selection instead of replacing it.
	ov.set_selection([a], false)
	ov.add_mode = true
	key(KEY_F1)
	check("pick with Add on: F1 adds group 1 to the selection", ov.sel_squads.size() == 5 and ov.sel_squads.has(a) and ov.sel_squads.has(e), str(ov.sel_squads))
	ov.add_mode = false
	# An empty group changes nothing and says so.
	ov.set_selection([a], false)
	key(KEY_F5)
	check("empty: F5 leaves the selection alone", ov.sel_squads == [a])
	check("empty: and says it is empty", not ov.result_ok and ov.result_text.contains("empty"), ov.result_text)
	# Ctrl+F with nothing selected is refused, the group is not wiped.
	ov.clear_selection()
	key(KEY_F1, true)
	check("refuse: Ctrl+F1 with no selection keeps group 1", g.members(1) == [b, c, d, e] and not ov.result_ok, ov.result_text)
	# The double tap centres the camera on the group's middle.
	var middle := Vector2.ZERO
	for id in g.members(1):
		middle += RtsSelect.centre_of(world, world.squads[id])
	middle /= 4.0
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	g.fake_ms = 200000
	key(KEY_F1)
	g.fake_ms = 200200
	key(KEY_F1)
	check("double tap: the second F1 within the tap time centres the camera on the group", world.camera._free_pos.distance_to(middle) < 1.0, "%s vs %s" % [str(world.camera._free_pos), str(middle)])
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	g.fake_ms = 300000
	key(KEY_F1)
	g.fake_ms = 300000 + int(RtsUiCalls.GROUP_DOUBLE_TAP_S * 1000.0) + 50
	key(KEY_F1)
	check("double tap: a second tap that is too late does not centre", world.camera._free_pos.distance_to(middle) > 1000.0)
	g.fake_ms = 400000
	key(KEY_F1)
	g.fake_ms = 400100
	key(KEY_F2)
	check("double tap: two different groups do not centre", world.camera._free_pos.distance_to(middle) > 1000.0)
	# A camera that follows the ship is let go by the jump.
	world.camera.free = false
	g.fake_ms = 500000
	key(KEY_F1)
	g.fake_ms = 500100
	key(KEY_F1)
	check("double tap: a following camera is freed and centred", world.camera.free and world.camera._free_pos.distance_to(middle) < 1.0)
	# Flying with the board closed: the group is picked, the camera stays.
	var ts: TeamState = world.teams[world.human_team]
	var was_docked := ts.admiral_docked
	var was_board := world.board_open
	ts.admiral_docked = false
	world.board_open = false
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	var away: Vector2 = world.camera._free_pos
	ov.clear_selection()
	g.fake_ms = 600000
	hud.command_view.select_key(_press(KEY_F1))
	g.fake_ms = 600100
	hud.command_view.select_key(_press(KEY_F1))
	check("flying: F1 picks the group", ov.sel_squads == [b, c, d, e], str(ov.sel_squads))
	check("flying: even a double tap leaves the camera alone", world.camera._free_pos.is_equal_approx(away))
	world.board_open = true
	g.fake_ms = 700000
	hud.command_view.select_key(_press(KEY_F1))
	g.fake_ms = 700100
	hud.command_view.select_key(_press(KEY_F1))
	check("flying with the board open: a double tap centres", world.camera._free_pos.distance_to(middle) < 1.0)
	ts.admiral_docked = was_docked
	world.board_open = was_board
	_flash(g, ov, ts, middle)
	# Squadrons that no longer exist drop out of a group.
	g.set_group(7, [999991, a])
	check("dead: an unknown squadron id is not a member", g.members(7) == [a], str(g.members(7)))
	# A key that is no group key is not taken, and Alt never counts.
	var plain := _press(KEY_F9)
	check("keys: F9 is not a group key", Groups.key_group(plain).is_empty())
	var alt := _press(KEY_F1)
	alt.alt_pressed = true
	check("keys: Alt+F1 is not a group key", Groups.key_group(alt).is_empty())
	check("keys: Ctrl+F3 decodes as set 3 and Shift+F8 as add 8", Groups.key_group(_press(KEY_F3, true))["how"] == "set" and Groups.key_group(_press(KEY_F8, false, true)) == {"n": 8, "how": "add"})
	# A click route for the same actions exists on the army row (checked by rts_army_check); here the data side:
	g.set_group(1, [])
	check("clear: a group set to nothing is empty again", g.members(1).is_empty())


## RT7 7c: a double tap of a group key flashes the group on the minimap in field mode only. The minimap spaces its flashes by the
## groups' own test clock, so no case waits. Group 1 holds four squadrons here; `middle` is where a centring would put the camera.
func _flash(g: Groups, ov: CommandOverlay, ts: TeamState, middle: Vector2) -> void:
	var mm := hud.minimap
	mm.hook_groups()
	var was_docked: bool = ts.admiral_docked
	var was_board := world.board_open
	var was_view := world.view_open
	var heard := [0]
	g.double_tapped.connect(func(_n: int) -> void: heard[0] += 1)
	# Field mode: flying with the view and the board closed.
	ts.admiral_docked = false
	world.board_open = false
	world.view_open = false
	check("flash: this is field mode", FieldMode.active(world, world.human_team))
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	var away: Vector2 = world.camera._free_pos
	var n0: int = mm.flash_count
	g.fake_ms = 800000
	hud.command_view.select_key(_press(KEY_F1))
	check("flash: a single tap draws no flash", mm.flash_count == n0 and heard[0] == 0)
	g.fake_ms = 800000 + int(RtsUiCalls.GROUP_DOUBLE_TAP_S * 1000.0) - 50
	hud.command_view.select_key(_press(KEY_F1))
	check("flash: a second tap inside GROUP_DOUBLE_TAP_S flashes the group", mm.flash_count == n0 + 1 and heard[0] == 1, "%d flashes, %d heard" % [mm.flash_count - n0, heard[0]])
	var ringed := mm.flash_ids()
	var members := g.members(1)
	check("flash: one ring round each squadron of the group", ringed.size() == members.size() and members.all(func(id: int) -> bool: return ringed.has(id)), str(ringed))
	check("flash: in field mode the camera does not move", world.camera._free_pos.is_equal_approx(away))
	# Taps at 0, 100, 200 and 300 ms: the first pair flashes; the second pair (the 300 ms tap is 200 ms after the flash) does not.
	var t0 := 900000
	var n1: int = mm.flash_count
	for dt: int in [0, 100, 200, 300]:
		g.fake_ms = t0 + dt
		hud.command_view.select_key(_press(KEY_F1))
	check("flash: of taps at 0, 100, 200 and 300 ms the first pair flashes and the second pair adds none", mm.flash_count == n1 + 1 and heard[0] == 3, "%d flashes, %d heard" % [mm.flash_count - n1, heard[0]])
	# A pair that completes 334 ms or more after the flash flashes again (the flash began at the 100 ms tap).
	g.fake_ms = t0 + 400
	hud.command_view.select_key(_press(KEY_F1))
	g.fake_ms = t0 + 100 + Minimap.GROUP_FLASH_GAP_MS
	hud.command_view.select_key(_press(KEY_F1))
	check("flash: a pair that completes 334 ms after the flash flashes again", mm.flash_count == n1 + 2 and heard[0] == 4, "%d flashes, %d heard" % [mm.flash_count - n1, heard[0]])
	# One that completes 333 ms after the flash (the last one began at the tap of t0 + 434) does not.
	var last_flash := t0 + 100 + Minimap.GROUP_FLASH_GAP_MS
	g.fake_ms = last_flash + 100
	hud.command_view.select_key(_press(KEY_F1))
	g.fake_ms = last_flash + Minimap.GROUP_FLASH_GAP_MS - 1
	hud.command_view.select_key(_press(KEY_F1))
	check("flash: a pair that completes 333 ms after the flash adds none", mm.flash_count == n1 + 2 and heard[0] == 5, "%d flashes, %d heard" % [mm.flash_count - n1, heard[0]])
	# An empty group never flashes.
	var n3: int = mm.flash_count
	var h3: int = heard[0]
	g.fake_ms = 1000000
	hud.command_view.select_key(_press(KEY_F6))
	g.fake_ms = 1000100
	hud.command_view.select_key(_press(KEY_F6))
	check("flash: an empty group never flashes", g.members(6).is_empty() and mm.flash_count == n3 and heard[0] == h3)
	# Mode 3 (the view open): the double tap centres the camera and is heard, but no ring is drawn.
	world.view_open = true
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	var n4: int = mm.flash_count
	var h4: int = heard[0]
	g.fake_ms = 2000000
	hud.command_view.select_key(_press(KEY_F1))
	g.fake_ms = 2000100
	hud.command_view.select_key(_press(KEY_F1))
	check("flash: in mode 3 the signal is emitted and no ring is drawn", heard[0] == h4 + 1 and mm.flash_count == n4)
	check("flash: in mode 3 the double tap still centres the camera", world.camera._free_pos.distance_to(middle) < 1.0)
	# Docked: the same.
	world.view_open = false
	ts.admiral_docked = true
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	g.fake_ms = 3000000
	hud.command_view.select_key(_press(KEY_F1))
	g.fake_ms = 3000100
	hud.command_view.select_key(_press(KEY_F1))
	check("flash: docked the signal is emitted and no ring is drawn", heard[0] == h4 + 2 and mm.flash_count == n4)
	check("flash: docked the double tap still centres the camera", world.camera._free_pos.distance_to(middle) < 1.0)
	g.fake_ms = -1
	ts.admiral_docked = was_docked
	world.board_open = was_board
	world.view_open = was_view
	ov.clear_selection()


## A key-press event, not sent anywhere.
func _press(code: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e
