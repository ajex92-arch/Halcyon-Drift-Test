extends Node
## WHAT THIS IS: the check of mode 3 and the coast (CoastController, World.mode3(), World.view_open): an Admiral who
## flies a ship of their own and opens the command view (Tab) does not steer it. board_hold_check is the older check of
## the board's hold and of the point-defence guns; this one is the plan's RT7 list. It flies a Flak Frigate and checks,
## one line each:
##   - Tab while flying opens the command view (World.view_open, mode3(), the coast applies, the camera is free) and
##     Tab closes it again; Esc closes it too; the camera setting from before (following) comes back;
##   - a right click and a left click on the map in mode 3 fire nothing and use no special (World.mouse_fire and
##     mouse_special stay off), while with mode 3 closed the same clicks set them (so the test can see a click work);
##   - under home layout A (the arrow keys move the home camera) the arrows in mode 3 are shield focus only: the
##     camera does not move on them, and W A S D Q E pan it instead (the ship takes no thrust from W);
##   - docking ends mode 3 (the HUD clears World.view_open), so the next launch flies;
##   - a mouse button still held when the P pause, the pause menu or the note box closes is read again (mouse_fire, mouse_special)
##     with mode 3 closed and is not in mode 3;
##   - a C press in mode 3 (through the HUD, and as the camera's own toggle) leaves the view free and is kept: the camera is free
##     when the view closes (the control: with no press the follow camera comes back);
##   - the coast, 20 runs: the ship is flown at a rock, a turret, a derelict and our mothership (5 speeds each, mode 3
##     open, no keys): it stops short of each, never touches it and its hull never takes damage.
## A pilot or a spectator has no command view: the check prints SKIP and passes.
##
## HOW IT WORKS: setup() gives the human a Flak Frigate. _physics_process() runs numbered steps one after another, as
## tests/board_hold_check.gd does; it runs after the World each tick (process_physics_priority), so the ship it places is
## the one the next tick flies. Tab and Esc go through HudInput (the HUD must exist: start with --force-hud), the clicks
## are real mouse events, the arrows and W real key events.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-pilots --no-admiral-ai --force-hud --test=coast_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what> <detail>", then
## "coast_check: N failures" and a PROBE_JSON line (the result line the queue, run_batch.ps1, looks for). 0 failures
## means every check passed.
##
## WHO USES IT: main.gd loads it for --test=coast_check. It reads CoastController, World, Hud, HudInput, CameraRig and
## PlayerController's effect on the ship.

## What the coast is run at, one after another (rock, turret, derelict, mothership; each at every speed in SPEEDS).
const KINDS := ["rock", "turret", "derelict", "mothership"]
## The speeds (world units a second) the ship is flown at each of them: 4 kinds x 5 speeds = the plan's 20 runs.
const SPEEDS := [100.0, 150.0, 200.0, 250.0, 300.0]
## How far from the rock the run starts (world units).
const RUN_START := 1600.0
## The speed the control runs start at.
const SLOW := 100.0
## Longest time (seconds) one run may take.
const RUN_MAX := 25.0
## Under this speed (world units a second) the ship counts as stopped.
const STOPPED := 1.5
## How far along the run the turret and the derelict stand (world units).
const OBSTACLE_AT := 1000.0

## The running match (set by setup()).
var world: World
## The match's camera.
var cam: CameraRig
## The HUD (found once it exists).
var hud: Hud
## The seat: "pilot", "admiral" or "spectator".
var role := ""
## The human's ship once launched.
var ship: Ship
## Which step we are on.
var step := 0
## The seconds since the step began.
var step_t := 0.0
## How many checks failed.
var fails := 0
## The centre of the rock the run flies at, and its radius.
var rock_pos := Vector2.ZERO
var rock_rad := 0.0
## The direction of the run (a unit vector) and the start spot in front of the rock.
var dir := Vector2.RIGHT
var start := Vector2.ZERO
## The ship's heading, and the camera's place, when a step began.
var mark_heading := 0.0
var mark_cam := Vector2.ZERO
## The smallest gap seen between the ship's hull and the thing, how many ticks it touched anything, how far the ship got
## from the start spot, and the lowest hull seen during a run (with the hull the run began with).
var min_gap := INF
var touches := 0
var travelled := 0.0
var hull_min := 0.0
var hull_at_start := 0.0
## The obstacle of the current run (null for the rock).
var obstacle: Unit
## Which run of the 20 is next.
var run_i := 0
## The screen point the clicks go to (set when the clicks begin).
var click_at := Vector2.ZERO
## Has the Esc press of the Esc step been sent?
var esc_sent := false
## Which part of a step with several parts is next (reset by _next()).
var sub := 0
## The hull the check flies: the Flak Frigate, or with --coast-hull=<id> another one (a Fighter run: the rock only, with a trace).
var hull_id := "flak"
## What the runs are at: KINDS for the Flak Frigate, the rock alone for another hull.
var kinds: Array = KINDS
## When the last trace line of a run was printed (the step clock).
var trace_t := 0.0
## Which round of the camera step is on: 0 presses C through the HUD, 1 calls the camera's own toggle.
var cam_round := 0


## main.gd calls this once, right after the World is built. Give the human a Flak Frigate and look for a rock.
func setup(w: World) -> void:
	world = w
	cam = w.camera
	role = w.human_role
	process_physics_priority = 100
	world.minion_director.next_wave = INF
	if world.human == null:
		return
	hull_id = str(Game.opt("coast-hull", "flak"))
	if hull_id != "flak":
		kinds = ["rock"]
	# The step clock must run while the match is paused (the pause-close tests below).
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.teams[0].facilities["frigate"] = true
	world.human.credits = 6000.0
	var err := world.human.buy_hull(hull_id, world.teams[0])
	if err != "":
		_check("the human can buy a Flak Frigate", false, err)
		return
	var found := _find_rock()
	if found != "":
		_check("a rock with a clear run to it was found", false, found)
		world.human = null


## Print one PASS or FAIL line for the check `name`, with the measured `detail`, and count the failures.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Move on to the next step and restart the step clock.
func _next() -> void:
	step += 1
	step_t = 0.0
	sub = 0


## Find a rock of the map (not an ore rock, not a huge one) that a straight run from RUN_START units away reaches first,
## with no other rock within 300 units of the run's line until 500 short of the rock, and none within 200 behind the
## start. Sets rock_pos, rock_rad, dir and start. Returns "" or how far the search got (for the failure line).
func _find_rock() -> String:
	var f := world.asteroids
	var pad := float(Ships.get_def(hull_id)["radius"]) + CoastController.LINE_PAD
	var seen := [0, 0, 0, 0]
	for i in f.pos.size():
		if f.alive[i] == 0 or f.node_rock[i] == 1 or f.rad[i] < 40.0 or f.rad[i] > 250.0:
			continue
		seen[0] += 1
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var s: Vector2 = f.pos[i] - d * RUN_START
			if s.x < 1000.0 or s.x > MapLayout.W - 1000.0 or s.y < 1000.0 or s.y > MapLayout.H - 1000.0:
				continue
			seen[1] += 1
			var hit := f.segment_hit(s, f.pos[i], pad)
			if hit.is_empty() or int(hit["index"]) != i:
				continue
			seen[2] += 1
			if not f.segment_hit(s, f.pos[i] - d * (f.rad[i] + 500.0), 300.0).is_empty():
				continue
			seen[3] += 1
			if not f.segment_hit(s - d * 700.0, s, 200.0).is_empty():
				continue
			rock_pos = f.pos[i]
			rock_rad = f.rad[i]
			dir = d
			start = s
			return ""
	return "rocks %d, runs inside the map %d, first hit is the rock %d, open beside the line %d" % seen


## Put the ship at the start spot of the run, heading along the run, moving at `speed` along `d`, not turning and with
## its engines straight (see board_hold_check: a ship of the line keeps its spin and its brake timer from tick to tick).
func _place(speed: float, d: Vector2) -> void:
	ship.global_position = start
	ship.rotation = dir.angle()
	ship.velocity = d * speed
	ship.ang_vel = 0.0
	ship.swivel = 0.0
	ship.brake_t = 0.0
	ship.throttle = 0.0
	ship.controls.face_point = start + dir * 600.0
	min_gap = INF
	touches = 0
	travelled = 0.0


## Put the mouse a quarter of the way in from the screen's top left corner, and park the camera (goal included) so that
## this screen point is world point `p`: the camera has room to pan.
func _aim_mouse_at(p: Vector2) -> void:
	var vs := cam.get_viewport_rect().size
	var m := vs * Vector2(0.25, 0.25)
	var at := p - (m - vs * 0.5) / cam.zoom.x
	cam.look_at_point(at)
	cam.global_position = at
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * m
	ev.global_position = ev.position
	Input.parse_input_event(ev)


## A key event, as the keyboard would send it (pressed or let go).
func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	return e


## Press Tab or Esc once through the HUD's key router (a press, then the release), as a player's key would arrive.
func _tap(code: Key) -> void:
	hud.router.handle(_key(code, true))
	hud.router.handle(_key(code, false))


## Press (`down` true) or let go of a key for the game's input state (the arrows, W).
func _hold(code: Key, down: bool) -> void:
	Input.parse_input_event(_key(code, down))


## Send mouse button `button` down or up at screen point `p`.
func _click(button: MouseButton, down: bool) -> void:
	var win := get_viewport().get_final_transform() * click_at
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = down
	ev.position = win
	ev.global_position = win
	Input.parse_input_event(ev)


## How far the ship's hull is from the thing it runs at (world units; negative when they overlap).
func _gap() -> float:
	if obstacle == null:
		return ship.global_position.distance_to(rock_pos) - rock_rad - ship.radius
	if obstacle is Mothership:
		return (obstacle as Mothership).hull_dist(ship.global_position) - ship.radius
	return ship.global_position.distance_to(obstacle.global_position) - obstacle.radius - ship.radius


## Print the total and quit.
func _finish() -> void:
	Input.action_release("thrust_forward")
	print("coast_check: %d failures" % fails)
	print("PROBE_JSON %s" % JSON.stringify({"test": "coast_check", "role": role, "failures": fails}))
	get_tree().quit()


## Godot calls this every tick. Run the current step.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	if world.human == null or role != "admiral":
		if role != "admiral":
			print("SKIP coast_check: only an Admiral has the command view")
		_finish()
		return
	step_t += dt
	var first := step_t <= dt * 1.5
	var ts: TeamState = world.teams[world.human_team]
	match step:
		0:
			# Wait for the HUD, then launch (the Admiral is out flying: not docked).
			hud = get_tree().root.find_child("Hud", true, false) as Hud
			if hud == null:
				return
			ship = world.launch(world.human)
			if ship == null:
				_check("the human launched the Flak Frigate", false)
				_finish()
				return
			ts.admiral_docked = false
			_next()
		1:
			# Tab opens mode 3: the flag, the predicate, the coast, a free camera (it was following).
			if first:
				cam.free = false
				_place(SLOW, dir)
				_tap(KEY_TAB)
			if step_t >= 0.3:
				_check("Tab while flying opens the command view (view_open, mode3, the coast applies)", world.view_open and world.mode3() and CoastController.holding(world))
				_check("mode 3 leaves the board closed", not world.board_open and (hud.board == null or not hud.board.visible))
				_check("mode 3 frees the camera", cam.free)
				_next()
		2:
			# Tab again closes it and the camera setting from before comes back.
			if first:
				_tap(KEY_TAB)
			if step_t >= 0.3:
				_check("Tab again closes mode 3 (view_open and mode3 are false)", not world.view_open and not world.mode3() and not CoastController.holding(world))
				_check("leaving mode 3 puts the follow camera back", not cam.free)
				cam.free = true
				_next()
		3:
			# Esc closes mode 3 too.
			if first:
				_tap(KEY_TAB)
			if step_t >= 0.1 and not esc_sent:
				esc_sent = true
				_tap(KEY_ESCAPE)
			if step_t >= 0.4:
				_check("Esc closes mode 3 (view_open is false)", not world.view_open)
				_next()
		4:
			# Control: with mode 3 closed a right and a left click on the map set the fire and special flags.
			if first:
				var vs := cam.get_viewport_rect().size
				click_at = vs * Vector2(0.6, 0.4)
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_LEFT, true)
			if step_t >= 0.15:
				_check("control: with mode 3 closed a right click sets mouse_special", world.mouse_special)
				_check("control: with mode 3 closed a left click sets mouse_fire", world.mouse_fire)
				_click(MOUSE_BUTTON_RIGHT, false)
				_click(MOUSE_BUTTON_LEFT, false)
				_next()
		5:
			# In mode 3 neither click fires or uses the special (nothing is selected).
			if first:
				_tap(KEY_TAB)
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_LEFT, true)
			if step_t >= 0.15:
				_check("mode 3 is open for the click test", world.view_open)
				_check("nothing is selected for the click test", hud.overlay.sel_squads.is_empty() and hud.overlay.tool == "")
				_check("mode 3: a right click with nothing selected does not use the special", not world.mouse_special)
				_check("mode 3: a left click does not fire", not world.mouse_fire)
				_click(MOUSE_BUTTON_RIGHT, false)
				_click(MOUSE_BUTTON_LEFT, false)
				_next()
		6:
			# Layout A: the arrows are shield focus only in mode 3; W pans the camera instead of thrusting.
			if first:
				KeyMap.set_preset("home_layout", "A")
				_place(SLOW, dir)
				_aim_mouse_at(start + Util.port_of(dir.angle()) * 2500.0)
				mark_cam = cam.global_position
				_hold(KEY_UP, true)
			if step_t >= 0.6:
				var moved := cam.global_position.distance_to(mark_cam)
				_check("layout A, mode 3: the Up arrow gives shield focus front", ship.shields.focus == Rules.FOCUS_FRONT, "focus %d" % ship.shields.focus)
				_check("layout A, mode 3: the Up arrow does not pan the camera", moved < 2.0, "moved %.1f" % moved)
				_hold(KEY_UP, false)
				_next()
		7:
			if first:
				_place(SLOW, dir)
				_aim_mouse_at(start + Util.port_of(dir.angle()) * 2500.0)
				mark_cam = cam.global_position
				_hold(KEY_W, true)
			if step_t >= 0.8:
				var panned := mark_cam.y - cam.global_position.y
				var speed := ship.velocity.length()
				_check("layout A, mode 3: W pans the camera up", panned > 100.0, "panned %.0f" % panned)
				_check("layout A, mode 3: W gives the ship no thrust", speed < SLOW + 1.0, "speed %.1f from %.0f" % [speed, SLOW])
				_hold(KEY_W, false)
				KeyMap.set_preset("home_layout", "B")
				_next()
		8:
			# Docking ends mode 3.
			if first:
				ts.admiral_docked = true
			if step_t >= 0.3:
				_check("docking closes mode 3 (the HUD clears view_open)", not world.view_open and not world.mode3())
				ts.admiral_docked = false
				_next()
		9:
			# A left button held across Tab fires nothing in mode 3 (the controls' fire is cleared; with mode 3 closed it is set).
			if sub == 0:
				click_at = cam.get_viewport_rect().size * Vector2(0.6, 0.4)
				_click(MOUSE_BUTTON_LEFT, true)
				sub = 1
				step_t = 0.0
			elif sub == 1 and step_t >= 0.15:
				_check("control: the left button held with mode 3 closed fires (controls.fire)", ship.controls.fire)
				_tap(KEY_TAB)
				sub = 2
				step_t = 0.0
			elif sub == 2 and step_t >= 0.15:
				_check("mode 3: a left button held across Tab fires nothing (controls.fire is false)", world.view_open and not ship.controls.fire)
				_click(MOUSE_BUTTON_LEFT, false)
				_tap(KEY_TAB)
				_next()
		10:
			# A right button held while the P pause closes uses no special in mode 3 (control: with mode 3 closed it does).
			if sub == 0:
				hud.panels.toggle_command_pause()
				_click(MOUSE_BUTTON_RIGHT, true)
				sub = 1
				step_t = 0.0
			elif sub == 1 and step_t >= 0.1:
				hud.panels.toggle_command_pause()
				sub = 2
				step_t = 0.0
			elif sub == 2 and step_t >= 0.05:
				_check("control: a right button held while the pause closes sets mouse_special (mode 3 closed)", world.mouse_special)
				_click(MOUSE_BUTTON_RIGHT, false)
				sub = 3
				step_t = 0.0
			elif sub == 3 and step_t >= 0.1:
				_next()
		11:
			if sub == 0:
				_tap(KEY_TAB)
				hud.panels.toggle_command_pause()
				_click(MOUSE_BUTTON_RIGHT, true)
				sub = 1
				step_t = 0.0
			elif sub == 1 and step_t >= 0.1:
				hud.panels.toggle_command_pause()
				sub = 2
				step_t = 0.0
			elif sub == 2 and step_t >= 0.05:
				_check("mode 3: a right button held while the pause closes uses no special", world.view_open and not world.mouse_special)
				_click(MOUSE_BUTTON_RIGHT, false)
				_tap(KEY_TAB)
				_next()
		12:
			# A mouse button held while the pause menu closes: the buttons are read again on resume, but not in mode 3. The buttons go
			# down first (the menu's card is not under them) and the menu opens and closes over them.
			if sub == 0:
				click_at = cam.get_viewport_rect().size * Vector2(0.6, 0.4)
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_LEFT, true)
				sub = 1
				step_t = 0.0
			elif sub == 1 and step_t >= 0.1:
				hud.panels.toggle_pause_menu()
				sub = 2
				step_t = 0.0
			elif sub == 2 and step_t >= 0.1:
				hud.pause_menu.resume()
				sub = 3
				step_t = 0.0
			elif sub == 3 and step_t >= 0.05:
				_check("control: the pause menu closing with the right button held sets mouse_special (mode 3 closed)", world.mouse_special)
				_check("control: and with the left button held sets mouse_fire", world.mouse_fire)
				_click(MOUSE_BUTTON_RIGHT, false)
				_click(MOUSE_BUTTON_LEFT, false)
				sub = 4
				step_t = 0.0
			elif sub == 4 and step_t >= 0.1:
				_tap(KEY_TAB)
				sub = 5
				step_t = 0.0
			elif sub == 5 and step_t >= 0.1:
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_LEFT, true)
				sub = 6
				step_t = 0.0
			elif sub == 6 and step_t >= 0.1:
				hud.panels.toggle_pause_menu()
				sub = 7
				step_t = 0.0
			elif sub == 7 and step_t >= 0.1:
				hud.pause_menu.resume()
				sub = 8
				step_t = 0.0
			elif sub == 8 and step_t >= 0.05:
				_check("mode 3: the pause menu closing with the right button held uses no special", world.view_open and not world.mouse_special)
				_check("mode 3: and with the left button held fires nothing", not world.mouse_fire and not ship.controls.fire)
				_click(MOUSE_BUTTON_RIGHT, false)
				_click(MOUSE_BUTTON_LEFT, false)
				_tap(KEY_TAB)
				_next()
		13:
			# The same with the note box: opened over the held buttons and closed by its own cancel.
			if sub == 0:
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_LEFT, true)
				sub = 1
				step_t = 0.0
			elif sub == 1 and step_t >= 0.1:
				hud._open_note()
				sub = 2
				step_t = 0.0
			elif sub == 2 and step_t >= 0.1:
				_check("the note box is open over the held buttons", hud._note_is_open())
				hud.note_box.cancel()
				sub = 3
				step_t = 0.0
			elif sub == 3 and step_t >= 0.05:
				_check("control: the note box closing with the right button held sets mouse_special (mode 3 closed)", not hud._note_is_open() and world.mouse_special)
				_check("control: and with the left button held sets mouse_fire", world.mouse_fire)
				_click(MOUSE_BUTTON_RIGHT, false)
				_click(MOUSE_BUTTON_LEFT, false)
				sub = 4
				step_t = 0.0
			elif sub == 4 and step_t >= 0.1:
				_tap(KEY_TAB)
				sub = 5
				step_t = 0.0
			elif sub == 5 and step_t >= 0.1:
				_click(MOUSE_BUTTON_RIGHT, true)
				_click(MOUSE_BUTTON_LEFT, true)
				sub = 6
				step_t = 0.0
			elif sub == 6 and step_t >= 0.1:
				hud._open_note()
				sub = 7
				step_t = 0.0
			elif sub == 7 and step_t >= 0.1:
				hud.note_box.cancel()
				sub = 8
				step_t = 0.0
			elif sub == 8 and step_t >= 0.05:
				_check("mode 3: the note box closing with the right button held uses no special", world.view_open and not world.mouse_special)
				_check("mode 3: and with the left button held fires nothing", not world.mouse_fire and not ship.controls.fire)
				_click(MOUSE_BUTTON_RIGHT, false)
				_click(MOUSE_BUTTON_LEFT, false)
				_tap(KEY_TAB)
				_next()
		14:
			# A C press in mode 3 sets what the camera does when the command view closes (the view itself stays free). Round 0 presses
			# the key through the HUD, round 1 calls the camera's own toggle (what the alert feed's Back button calls).
			if sub == 0:
				# Let the camera settle first (it puts its own setting back on the frame after a view closes).
				sub = 7
				step_t = 0.0
			elif sub == 7 and step_t >= 0.3:
				cam.free = false
				_tap(KEY_TAB)
				sub = 1
				step_t = 0.0
			elif sub == 1 and step_t >= 0.2:
				_check("camera round %d: Tab opens mode 3 and the view is free" % cam_round, world.view_open and world.mode3() and cam.free)
				if cam_round == 0:
					_tap(KEY_C)
				else:
					cam.toggle_free()
				sub = 2
				step_t = 0.0
			elif sub == 2 and step_t >= 0.2:
				_check("camera round %d: the press leaves the view free while mode 3 is open" % cam_round, cam.free)
				_tap(KEY_TAB)
				sub = 3
				step_t = 0.0
			elif sub == 3 and step_t >= 0.3:
				_check("camera round %d: Tab closes mode 3 and the press was kept (the camera is free now)" % cam_round, not world.view_open and cam.free)
				_tap(KEY_C)
				sub = 4
				step_t = 0.0
			elif sub == 4 and step_t >= 0.1:
				_check("camera round %d: a C press with the view closed follows the ship again" % cam_round, not cam.free)
				if cam_round == 0:
					_tap(KEY_TAB)
					sub = 5
				else:
					cam_round = 0
					_next()
				step_t = 0.0
			elif sub == 5 and step_t >= 0.2:
				_tap(KEY_TAB)
				sub = 6
				step_t = 0.0
			elif sub == 6 and step_t >= 0.3:
				_check("control: Tab, Tab with no C press puts the follow camera back", not world.view_open and not cam.free)
				cam_round = 1
				sub = 0
				step_t = 0.0
		15:
			# Each of the 20 runs: mode 3 open, the thing put on the ship's line.
			if first:
				if not world.view_open:
					_tap(KEY_TAB)
				if not _make_obstacle(kinds[floori(float(run_i) / SPEEDS.size())]):
					_finish()
					return
			if step_t >= 0.5:
				_next()
		16:
			if not is_instance_valid(ship) or not ship.alive:
				_check("the ship survived run %d" % (run_i + 1), false)
				_finish()
				return
			var kind: String = kinds[floori(float(run_i) / SPEEDS.size())]
			var speed0: float = SPEEDS[run_i % SPEEDS.size()]
			if first:
				_place(speed0, dir)
				mark_heading = ship.rotation
				hull_at_start = ship.hull
				hull_min = ship.hull
			min_gap = minf(min_gap, _gap())
			hull_min = minf(hull_min, ship.hull)
			if ship.get_slide_collision_count() > 0:
				touches += 1
			travelled = ship.global_position.distance_to(start)
			if hull_id != "flak" and step_t - trace_t >= 0.5:
				trace_t = step_t
				print("TRACE %.1f s speed %.1f toward %.1f gap %.0f forward %.2f strafe %.2f" % [step_t, ship.velocity.length(), ship.velocity.dot(dir), _gap(), ship.controls.forward, ship.controls.strafe])
			if ship.velocity.length() < STOPPED or step_t >= RUN_MAX:
				var tag := "run %d (%s at %.0f)" % [run_i + 1, kind, speed0]
				print("END %s hull %s: speed %.1f, %.1f toward the thing (negative = away), gap %.0f, after %.1f s" % [tag, hull_id, ship.velocity.length(), ship.velocity.dot(dir), _gap(), step_t])
				_check("%s: mode 3 was open all the way" % tag, world.view_open)
				_check("%s: the ship stopped" % tag, ship.velocity.length() < STOPPED, "speed %.1f after %.1f s" % [ship.velocity.length(), step_t])
				_check("%s: it never touched the %s" % [tag, kind], touches == 0 and min_gap > 0.0, "touches %d, closest gap %.0f" % [touches, min_gap])
				_check("%s: the hull took no damage" % tag, hull_min >= hull_at_start - 0.001, "hull %.1f of %.1f" % [hull_min, hull_at_start])
				_remove_obstacle()
				trace_t = 0.0
				run_i += 1
				if run_i < kinds.size() * SPEEDS.size():
					step = 15
					step_t = 0.0
				else:
					_finish()


## Put the thing of `kind` on the ship's line. The rock is the real one the search found; a turret and a derelict stand
## OBSTACLE_AT units along the run, where nothing else is; the mothership run starts 1,700 units in front of our
## mothership's bow and flies at it. Returns false (with a failed check) when it cannot be set up.
func _make_obstacle(kind: String) -> bool:
	match kind:
		"rock":
			obstacle = null
		"turret":
			# Any node with a free slot will do; the turret is moved onto the ship's line below.
			var n: ResourceNode = null
			for cand: ResourceNode in world.nodes:
				if cand.free_slot() >= 0:
					n = cand
					break
			var slot := n.free_slot() if n != null else -1
			if slot < 0:
				_check("a free turret slot was found", false)
				return false
			var t := world.spawn_turret(0, n, slot, "pd", true)
			t.global_position = start + dir * OBSTACLE_AT
			obstacle = t
		"derelict":
			var d := world.spawn_derelict("coast_check_%d" % run_i, "gunship", start + dir * OBSTACLE_AT)
			d.think_t = 1.0e9
			obstacle = d
		_:
			var ms := world.mothership(0)
			var f := Vector2.from_angle(ms.rotation)
			dir = -f
			start = ms.global_position + f * (ms.half_len + ms.beam * 0.5 + 1700.0)
			if not world.asteroids.segment_hit(start, ms.global_position, 300.0).is_empty():
				_check("a clear run to the friendly mothership was found", false, "a rock is in the way")
				return false
			obstacle = ms
	return true


## Take the obstacle away again (a mothership stays).
func _remove_obstacle() -> void:
	if obstacle != null and is_instance_valid(obstacle) and not (obstacle is Mothership):
		world.combat.kill_silently(obstacle)
	obstacle = null
