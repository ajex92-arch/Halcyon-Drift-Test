extends RtsUiCheckBase
## WHAT THIS IS: the check of the idle keys: I selects the next idle squadron (state idle and no order) and centres the
## camera on it, pressing it again walks on and wraps, Ctrl+I selects every idle squadron and leaves the camera alone, a
## squadron with an order is not idle, with none idle the key says so and changes nothing, and while flying the keys work
## only with the board open (the flying_board row) and are the pilot's otherwise.
##
## HOW IT WORKS: the base fills both fleets and finds the HUD; the case sets the state and order of the squad records
## itself (all in one frame, before the match takes a tick), sends I and Ctrl+I through hud.router.handle() and reads the
## overlay's selection and the camera's goal.
##
## HOW TO RUN IT: see RtsUiCheckBase (--test=rts_idle_check).
##
## WHO USES IT: main.gd loads it for --test=rts_idle_check; the run_checks list has a row for it.


func _init() -> void:
	label = "rts_idle_check"


func run() -> void:
	var ov := hud.overlay
	var all := squads()
	check("setup: the fleet fill made at least 5 squadrons", all.size() >= 5, "%d" % all.size())
	if all.size() < 5:
		return
	var a := all[0]
	var b := all[1]
	var c := all[2]
	var d := all[3]
	# a, b and c are idle; every other squadron is moving; d is idle in state but holds an order.
	for rec in all:
		rec.state = 1
		rec.order = {"kind": "move", "tick": 0}
	for rec in [a, b, c]:
		rec.state = 0
		rec.order = {}
	d.state = 0
	check("idle: a squadron with an order is not idle", not SelectionTools.is_idle(d) and SelectionTools.is_idle(a))
	check("idle: the idle list is a, b, c", hud.command_view.tools.idle_ids() == [a.id, b.id, c.id], str(hud.command_view.tools.idle_ids()))
	ov.clear_selection()
	_far()
	key(KEY_I)
	check("I: selects the first idle squadron", ov.sel_squads == [a.id], str(ov.sel_squads))
	check("I: centres the camera on it", world.camera._free_pos.distance_to(RtsSelect.centre_of(world, a)) < 1.0)
	key(KEY_I)
	check("I again: the next one, b", ov.sel_squads == [b.id], str(ov.sel_squads))
	key(KEY_I)
	key(KEY_I)
	check("I again: past c it wraps to a", ov.sel_squads == [a.id], str(ov.sel_squads))
	# Ctrl+I: every idle squadron, the camera stays.
	_far()
	var away: Vector2 = world.camera._free_pos
	key(KEY_I, true)
	check("Ctrl+I: selects every idle squadron", ov.sel_squads == [a.id, b.id, c.id], str(ov.sel_squads))
	check("Ctrl+I: the camera does not move", world.camera._free_pos.is_equal_approx(away))
	# The Add toggle adds instead of replacing.
	ov.set_selection([d.id], false)
	ov.add_mode = true
	key(KEY_I, true)
	check("Ctrl+I with Add on: adds to the selection", ov.sel_squads.size() == 4 and ov.sel_squads.has(d.id), str(ov.sel_squads))
	ov.add_mode = false
	# A following camera is let go by the jump of I.
	world.camera.free = false
	hud.command_view.tools.last = -1
	key(KEY_I)
	check("I: a following camera is freed and centred", world.camera.free and world.camera._free_pos.distance_to(RtsSelect.centre_of(world, a)) < 1.0)
	# Flying: the keys work only with the board open.
	var ts: TeamState = world.teams[world.human_team]
	var was_docked := ts.admiral_docked
	var was_board := world.board_open
	ts.admiral_docked = false
	world.board_open = false
	ov.clear_selection()
	check("flying: I is not taken with the board closed", not hud.command_view.select_key(_press(KEY_I)) and ov.sel_squads.is_empty())
	world.board_open = true
	check("flying with the board open: I is taken", hud.command_view.select_key(_press(KEY_I)) and ov.sel_squads.size() == 1, str(ov.sel_squads))
	ov.clear_selection()
	check("flying with the board open: Ctrl+I is not a row there, so it is not taken", not hud.command_view.select_key(_press(KEY_I, true)) and ov.sel_squads.is_empty())
	ts.admiral_docked = was_docked
	world.board_open = was_board
	# None idle: the key says so and changes nothing.
	for rec in all:
		rec.state = 1
	ov.set_selection([d.id], false)
	key(KEY_I)
	check("none idle: I leaves the selection alone", ov.sel_squads == [d.id], str(ov.sel_squads))
	check("none idle: and says so", ov.result_text.contains("No idle"), ov.result_text)
	key(KEY_I, true)
	check("none idle: Ctrl+I leaves the selection alone too", ov.sel_squads == [d.id], str(ov.sel_squads))
	# The key labels come from the key map rows.
	check("rows: idle_next is I and idle_all is Ctrl+I in the home mode", KeyMap.first_key("home", "idle_next") == "I" and KeyMap.first_key("home", "idle_all") == "Ctrl+I")


## Put the camera's goal far from every squadron.
func _far() -> void:
	world.camera.free = true
	world.camera.look_at_point(Vector2(60000.0, 60000.0))


## A key-press event, not sent anywhere.
func _press(code: Key, ctrl: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e
