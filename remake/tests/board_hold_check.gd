extends Node
## WHAT THIS IS: the check of the board hold (BoardHold): an Admiral who
## flies a ship of their own with the Admiral board open does not steer it.
## It flies a Flak Frigate (two automatic point-defence guns) at a rock of
## the real map and checks, one line each:
##   - control: with the board closed, W thrusts and the mouse turns the hull
##     (so the checks below can see a ship that is not held);
##   - the board opens through the HUD's own toggle and World.board_open
##     follows it, closed again the same way;
##   - hold: with the board open and W held down and the mouse off to the
##     side, the ship keeps its speed (no thrust) and its heading, and W pans
##     the camera instead;
##   - the rock guard: flying at the rock at 200 units a second with the
##     board open, the ship slows down, stops short of the rock and never
##     touches it, after coasting a good way (it is not pinned at the start);
##   - the point-defence guns keep firing while the ship is held (an enemy
##     Scout rides beside it);
##   - with no rock ahead (flying away from it) the ship is not braked;
##   - the same run at the other things a ship bumps into, one after another:
##     a friendly turret, a derelict that picks no target and our mothership: the
##     ship stops short of each without touching it;
##   - a pilot (no Admiral board) is never held, even with World.board_open
##     forced on.
## A spectator has no ship: the check prints SKIP and passes.
##
## HOW IT WORKS: setup() gives the human a Flak Frigate. _physics_process()
## runs numbered steps one after another, as tests/camera_check.gd does; it
## runs after the World each tick (process_physics_priority), so the ship it
## places is the one the next tick flies. Keys are pressed with
## Input.action_press(), the board is opened with Hud._toggle_board() (the
## HUD must exist: start with --force-hud).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-pilots --no-admiral-ai --force-hud --test=board_hold_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=board_hold_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>" (the detail is the number measured), then
## "board_hold_check: N failures" and a PROBE_JSON line (the result line the
## queue, run_batch.ps1, looks for). 0 failures means every check passed.
##
## WHO USES IT: main.gd loads it for --test=board_hold_check. It reads
## BoardHold, World.board_open, CameraRig and PlayerController's effect on
## the ship.

## How fast the ship flies at the rock (world units a second).
const RUN_SPEED := 200.0
## How far from the rock the run starts (world units).
const RUN_START := 1600.0
## The speed the control runs start at.
const SLOW := 100.0
## Longest time (seconds) the rock run may take.
const RUN_MAX := 25.0
## Under this speed (world units a second) the ship counts as stopped.
const STOPPED := 1.5
## How far along the rock run the turret and the derelict stand (world units).
const OBSTACLE_AT := 1000.0
## What the ship is run at after the rocks, one after another.
const OBSTACLES := ["turret", "derelict", "mothership"]

## The running match (set by setup()).
var world: World
## The match's camera.
var cam: CameraRig
## The HUD (found once it exists; admiral runs only).
var hud: Hud
## The seat: "pilot", "admiral" or "spectator".
var role := ""
## The human's ship once launched.
var ship: Ship
## The enemy Scout that rides beside the ship in the rock run.
var dummy: Ship
## Which step we are on.
var step := 0
## The seconds since the step began.
var step_t := 0.0
## How many checks failed.
var fails := 0
## The centre of the rock the run flies at.
var rock_pos := Vector2.ZERO
## The radius of that rock.
var rock_rad := 0.0
## The direction of the run (a unit vector).
var dir := Vector2.RIGHT
## The start spot of the run (the place in front of the rock).
var start := Vector2.ZERO
## The ship's heading when a step began.
var mark_heading := 0.0
## The camera's place when a step began.
var mark_cam := Vector2.ZERO
## The smallest gap seen between the ship's hull and the rock.
var min_gap := INF
## How many ticks the ship touched anything.
var touches := 0
## How far the ship got from the start spot.
var travelled := 0.0
## How many ticks had point-defence rounds in the air.
var pd_ticks := 0
## The biggest turn of the heading away from mark_heading (radians).
var heading_drift := 0.0
## The obstacle of the current structure run (a turret, a derelict or our mothership).
var obstacle: Unit
## Which of OBSTACLES the structure runs are at.
var obs_i := 0


## main.gd calls this once, right after the World is built. Give the human a
## Flak Frigate and look for a rock to fly at.
func setup(w: World) -> void:
	world = w
	cam = w.camera
	role = w.human_role
	process_physics_priority = 100
	world.minion_director.next_wave = INF
	if world.human == null:
		return
	world.teams[0].facilities["frigate"] = true
	world.human.credits = 6000.0
	var err := world.human.buy_hull("flak", world.teams[0])
	if err != "":
		_check("the human can buy a Flak Frigate", false, err)
		return
	var found := _find_rock()
	if found != "":
		_check("a rock with a clear run to it was found", false, found)
		world.human = null


## Print one PASS or FAIL line for the check `name`, with the measured
## `detail`, and count the failures.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Move on to the next step and restart the step clock.
func _next() -> void:
	step += 1
	step_t = 0.0


## Find a rock of the map (not an ore rock, not a huge one) that a straight
## run from RUN_START units away reaches first, with no other rock within
## 300 units of the run's line until 500 short of the rock, and none within
## 200 behind the start. Sets rock_pos, rock_rad, dir and start. Returns "" or
## how far the search got (for the failure line).
func _find_rock() -> String:
	var f := world.asteroids
	var pad := float(Ships.get_def("flak")["radius"]) + BoardHold.LINE_PAD
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

## Put the ship at the start spot of the run, heading along the run, moving
## at `speed` along `d` (the run's direction or its opposite), not turning and
## with its engines straight: a ship of the line keeps its turning speed, the
## swing of its engines and its brake timer from tick to tick, so the case
## before would otherwise leave its spin in this one (a Flak Frigate that the
## mouse had turned still spins at about 0.6 radians a second and the hold
## takes 0.9 s to stop it: 0.23 radians of heading).
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
	pd_ticks = 0
	heading_drift = 0.0


## Press (`down` true) or release the thrust-forward key.
func _w(down: bool) -> void:
	if down:
		Input.action_press("thrust_forward")
	else:
		Input.action_release("thrust_forward")


## Put the mouse a quarter of the way in from the screen's top left corner,
## and park the camera (goal included) so that this screen point is world
## point `p`: the mouse then points the hull at `p`, away from the screen's
## edges, and the camera has room to pan.
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


## The angle between the ship's heading and `a` (radians, 0..PI).
func _off(a: float) -> float:
	return absf(Util.ang_diff(ship.rotation, a))


## Launch an enemy Scout that stands where it is put (no driver).
func _launch_dummy() -> Ship:
	var p := PilotProfile.new("Rider", 1, 20 + world.profiles.size(), false)
	p.hull_id = "scout"
	world.profiles.append(p)
	var s := world.launch(p)
	if s != null:
		s.controller = null
	return s


## How many point-defence rounds of team 0 are in the air now.
func _pd_rounds() -> int:
	var pr := world.projectiles
	var n := 0
	for i in pr.cap:
		if pr.live[i] == 1 and pr.kind[i] == Rules.W_PD and pr.team[i] == 0:
			n += 1
	return n


## Print the total and quit.
func _finish() -> void:
	_w(false)
	print("board_hold_check: %d failures" % fails)
	print("PROBE_JSON %s" % JSON.stringify({"test": "board_hold_check", "role": role, "failures": fails}))
	get_tree().quit()


## Godot calls this every tick. Run the current step.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	if world.human == null:
		if role == "spectator":
			print("SKIP board_hold_check: a spectator has no ship")
		_finish()
		return
	step_t += dt
	var first := step_t <= dt * 1.5
	match step:
		0:
			# Wait for the HUD (an Admiral needs it for the board), then launch.
			if role == "admiral":
				hud = get_tree().root.find_child("Hud", true, false) as Hud
				if hud == null:
					return
			ship = world.launch(world.human)
			if ship == null:
				_check("the human launched the Flak Frigate", false)
				_finish()
				return
			_next()
		1:
			# Control: board closed, W held, mouse off to the side. Thrust must
			# add speed and the hull must turn toward the mouse.
			if first:
				_place(SLOW, dir)
				_aim_mouse_at(start + Util.port_of(dir.angle()) * 2500.0)
				_w(true)
				mark_heading = ship.rotation
			if step_t >= 0.5:
				_w(false)
				var speed := ship.velocity.length()
				var turned := absf(Util.ang_diff(mark_heading, ship.rotation))
				_check("control: with the board closed W thrusts", speed > SLOW + 20.0, "speed %.0f from %.0f" % [speed, SLOW])
				_check("control: with the board closed the hull turns to the mouse", turned > 0.1, "turned %.3f rad" % turned)
				_next()
		2:
			# The board opens through the HUD and World.board_open follows. A
			# pilot has no board: force the flag instead (it must not matter).
			if role == "admiral":
				hud._toggle_board()
				_check("the board opens and World.board_open is true", hud.board.visible and world.board_open)
				_check("the hold applies to the Admiral", BoardHold.holding(world))
			else:
				world.board_open = true
				_check("the hold does not apply to a pilot", not BoardHold.holding(world))
			_next()
		3:
			# Hold: board open (or forced), W held, mouse off to the side.
			if first:
				_place(SLOW, dir)
				_aim_mouse_at(start + Util.port_of(dir.angle()) * 2500.0)
				_w(true)
				mark_heading = ship.rotation
				mark_cam = cam.global_position
			if step_t >= 1.0:
				_w(false)
				var speed := ship.velocity.length()
				var turned := absf(Util.ang_diff(mark_heading, ship.rotation))
				var panned := mark_cam.y - cam.global_position.y
				if role == "admiral":
					_check("hold: W adds no speed with the board open", speed > SLOW - 15.0 and speed < SLOW + 1.0, "speed %.1f from %.0f" % [speed, SLOW])
					_check("hold: the heading stays", turned < 0.02, "turned %.4f rad" % turned)
					_check("hold: W pans the camera instead", panned > 100.0, "panned %.0f up" % panned)
					hud._toggle_board()
					_check("the board closes and World.board_open is false", not hud.board.visible and not world.board_open)
				else:
					_check("a pilot is not held: W thrusts with World.board_open on", speed > SLOW + 20.0, "speed %.0f" % speed)
					world.board_open = false
					_finish()
					return
				_next()
		4:
			# The board closed again: W thrusts, as in the control.
			if first:
				_place(SLOW, dir)
				_w(true)
			if step_t >= 0.5:
				_w(false)
				var speed := ship.velocity.length()
				_check("board closed again: W thrusts", speed > SLOW + 20.0, "speed %.0f" % speed)
				_next()
		5:
			# The rock run, board open, no keys: the ship must stop short of the
			# rock without touching it, with an enemy Scout riding beside it.
			if first:
				hud._toggle_board()
				dummy = _launch_dummy()
				_place(RUN_SPEED, dir)
				mark_heading = ship.rotation
			if dummy != null and dummy.alive:
				dummy.global_position = ship.global_position + Util.port_of(ship.rotation) * 300.0
				dummy.velocity = ship.velocity
			var gap := ship.global_position.distance_to(rock_pos) - rock_rad - ship.radius
			min_gap = minf(min_gap, gap)
			if ship.get_slide_collision_count() > 0:
				touches += 1
			travelled = ship.global_position.distance_to(start)
			heading_drift = maxf(heading_drift, _off(mark_heading))
			if _pd_rounds() > 0:
				pd_ticks += 1
			if ship.velocity.length() < STOPPED or step_t >= RUN_MAX:
				_check("rock guard: the ship stopped", ship.velocity.length() < STOPPED, "speed %.1f after %.1f s" % [ship.velocity.length(), step_t])
				_check("rock guard: it coasted a good way first", travelled > 600.0, "travelled %.0f" % travelled)
				_check("rock guard: it never touched the rock", touches == 0 and min_gap > 0.0, "touches %d, closest gap %.0f" % [touches, min_gap])
				_check("rock guard: it kept its heading all the way", heading_drift < 0.02, "drift %.4f rad" % heading_drift)
				_check("the point-defence guns kept firing while it was held", pd_ticks >= 10, "%d ticks with rounds in the air" % pd_ticks)
				if dummy != null and dummy.alive:
					world.combat.kill(dummy, DamageInfo.new())
				_next()
		6:
			# Flying away from the rock: nothing ahead, so no braking.
			if first:
				_place(RUN_SPEED, -dir)
			if step_t >= 1.0:
				var speed := ship.velocity.length()
				_check("no rock ahead: the ship is not braked", speed > RUN_SPEED - 10.0, "speed %.1f from %.0f" % [speed, RUN_SPEED])
				_next()
		7:
			# The structures a ship bumps into: a friendly turret, a derelict
			# that picks no target and the friendly mothership, one after the
			# other, each put on the ship's line (board open, no keys).
			if first:
				if not _make_obstacle(OBSTACLES[obs_i]):
					_finish()
					return
			if step_t >= 0.5:
				_next()
		8:
			if not is_instance_valid(ship) or not ship.alive:
				_check("the ship survived the run at the %s" % OBSTACLES[obs_i], false)
				_finish()
				return
			if first:
				_place(RUN_SPEED, dir)
				mark_heading = ship.rotation
			var gap := _gap_to(obstacle)
			min_gap = minf(min_gap, gap)
			if ship.get_slide_collision_count() > 0:
				touches += 1
			travelled = ship.global_position.distance_to(start)
			heading_drift = maxf(heading_drift, _off(mark_heading))
			if ship.velocity.length() < STOPPED or step_t >= RUN_MAX:
				var what: String = OBSTACLES[obs_i]
				_check("%s guard: the ship stopped" % what, ship.velocity.length() < STOPPED, "speed %.1f after %.1f s" % [ship.velocity.length(), step_t])
				_check("%s guard: it coasted a good way first" % what, travelled > 300.0, "travelled %.0f" % travelled)
				_check("%s guard: it never touched the %s" % [what, what], touches == 0 and min_gap > 0.0, "touches %d, closest gap %.0f" % [touches, min_gap])
				_check("%s guard: it kept its heading all the way" % what, heading_drift < 0.02, "drift %.4f rad" % heading_drift)
				_remove_obstacle()
				obs_i += 1
				if obs_i < OBSTACLES.size():
					step = 7
					step_t = 0.0
				else:
					_finish()


## Put the next obstacle of OBSTACLES on the ship's line. A turret and a derelict
## stand OBSTACLE_AT units along the rock run, where nothing else is; the
## mothership run starts 1,700 units in front of our mothership's bow and flies
## at it. Returns false (with a failed check) when it cannot be set up.
func _make_obstacle(kind: String) -> bool:
	match kind:
		"turret":
			# Any node with a free slot will do (the lane sites hold their turrets
			# from the start); the turret is moved onto the ship's line below.
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
			var d := world.spawn_derelict("bh_check", "gunship", start + dir * OBSTACLE_AT)
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


## How far the ship's hull is from the obstacle's surface (world units;
## negative when they overlap).
func _gap_to(o: Unit) -> float:
	if o is Mothership:
		return (o as Mothership).hull_dist(ship.global_position) - ship.radius
	return ship.global_position.distance_to(o.global_position) - o.radius - ship.radius
