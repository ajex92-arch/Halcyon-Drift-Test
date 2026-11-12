extends Node
## WHAT THIS IS: a quick scenario test for the AI lane's stuck-flak item: one
## Flak Frigate per team flies from its mothership to a goal on the mid lane
## with nothing else in the way (no minions, no other pilots), and the test
## says whether each one gets there or sits still short of it. It exists
## because the wedge it looks for (a flak jammed between a lane turret and the
## defense post 300 units from it) shows up in about one full match in four,
## which is too rare to measure with matches.
##
## HOW IT WORKS: setup() stops the minion waves and launches one Flak
## Frigate for each team with a brain that is told to hold a goal point (the
## brain's hold_point), the way tests/arena.gd does. Team 1's goal is
## --wedge-goal; team 0 gets its mirror image across the map's centre line.
## --wedge-start puts team 1's ship at a point instead of at its launch spot
## (team 0 gets the mirror image again). Every 2 s the test applies the same
## stuck rule as tests/farming_probe.gd (it moved under 150 over the last 8 s,
## it is more than 800 from its goal, and it is not fighting) and adds up the
## stuck seconds. After --wedge-secs game seconds it prints one
## "FLAK_WEDGE_PROBE_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --sim-only --test=flak_wedge_check --wedge-goal=22201,14566 --wedge-secs=150
## The options of this test: --wedge-goal=x,y (default 22201,14566),
## --wedge-start=x,y (default: the launch spot), --wedge-secs=<seconds>
## (default 150), --wedge-hull=<hull id> (default flak).
##
## HOW TO READ THE OUTPUT: FLAK_WEDGE_PROBE_JSON holds "ships", one row per
## team: "team", "reached" (true when the ship ended within ARRIVE_WITHIN of
## its goal), "end" (its place), "goal", "goal_d" (its distance from the
## goal at the end), "best_d" (the nearest it came), "stuck_s" (stuck
## seconds), "colliders" (what its last move slid along), "alive" (false when
## the ship died; "end" is then its last place) and "t_reached" (the game
## second it first came within ARRIVE_WITHIN, or -1) and "trail" (its place
## every 10 s as [second, x, y]); and "passed", true when every ship reached
## its goal and lived.
##
## WHO USES IT: main.gd loads it for --test=flak_wedge_check. It reads and
## flies the game the way tests/arena.gd does (through tests/lib/arena_kit.gd's
## conventions), and changes nothing else.

## How near (world units) to its goal a ship counts as having arrived.
const ARRIVE_WITHIN := 800.0
## Seconds of game time between two position samples.
const POSITION_EVERY := 2.0

## The running match (set by setup()).
var world: World
## Seconds this test has run.
var t := 0.0
## Seconds to run (--wedge-secs).
var secs := 150.0
## Game time of the next position sample, in seconds of this test.
var _next_pos := 0.0
## The test's ships: one Dictionary per team (see _add_ship()).
var _ships: Array = []


## main.gd calls this once, right after the World is built: stop the minion
## waves and launch one ship for each team.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	secs = float(Game.opt("wedge-secs", 150.0))
	var hull := str(Game.opt("wedge-hull", "flak"))
	var goal := _point(str(Game.opt("wedge-goal", "22201,14566")), Vector2(22201, 14566))
	var start_opt := str(Game.opt("wedge-start", ""))
	for team in [Rules.CINDER, Rules.HALCYON]:
		var g := goal if team == Rules.CINDER else MapLayout.mirror(goal)
		var st := Vector2.INF
		if start_opt != "":
			st = _point(start_opt, Vector2.ZERO)
			if team == Rules.HALCYON:
				st = MapLayout.mirror(st)
		_add_ship(team, hull, g, st)


## Read "x,y" text into a point (`fallback` when it does not parse).
func _point(text: String, fallback: Vector2) -> Vector2:
	var bits := text.split(",")
	if bits.size() != 2:
		return fallback
	return Vector2(float(bits[0]), float(bits[1]))


## Make a pilot record and brain for team `team` flying `hull`, launch it, hold
## `goal` as its goal, and put it at `start` unless that is INF.
func _add_ship(team: int, hull: String, goal: Vector2, start: Vector2) -> void:
	var p := PilotProfile.new("%s-%d" % [hull, team], team, 1, false)
	p.hull_id = hull
	p.role = "mid"
	world.profiles.append(p)
	var ai := PilotAI.new(world, p)
	world.pilot_ai[p] = ai
	var s := world.launch(p)
	if start != Vector2.INF:
		s.global_position = start
		s.velocity = Vector2.ZERO
	ai._reset_after_launch()
	ai.hold_point = goal
	_ships.append({"team": team, "ship": s, "ai": ai, "goal": goal, "pos": [], "stuck_s": 0.0, "best_d": INF, "t_reached": -1.0, "n": 0, "trail": []})


## Every tick: sample the ships when due; at the end print the JSON and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	# A pilot must not fly home to shop during the test.
	for e: Dictionary in _ships:
		(e["ai"] as PilotAI).launched_at = world.time
	if t >= _next_pos:
		_next_pos += POSITION_EVERY
		_sample()
	if t >= secs:
		_finish()


## Every POSITION_EVERY seconds: remember each ship's place, apply the stuck
## rule, and note how near to its goal it has been.
func _sample() -> void:
	for e: Dictionary in _ships:
		if not is_instance_valid(e["ship"]):
			continue
		var s := e["ship"] as Ship
		if not s.alive:
			continue
		e["last"] = s.global_position
		e["n"] = int(e["n"]) + 1
		if int(e["n"]) % 5 == 1:
			(e["trail"] as Array).append([roundi(t), roundi(s.global_position.x), roundi(s.global_position.y)])
		var ai := e["ai"] as PilotAI
		var goal: Vector2 = e["goal"]
		var d := s.global_position.distance_to(goal)
		e["best_d"] = minf(float(e["best_d"]), d)
		if d <= ARRIVE_WITHIN and float(e["t_reached"]) < 0.0:
			e["t_reached"] = t
		var ps: Array = e["pos"]
		ps.append(s.global_position)
		if ps.size() > 5:
			ps.pop_front()
		if ps.size() < 5:
			continue
		var moved := 0.0
		for q: Vector2 in ps:
			moved = maxf(moved, q.distance_to(ps[0]))
		var has_t := ai.target != null and is_instance_valid(ai.target) and ai.target.alive
		var fighting := has_t and ai.state != "home" and ai.state != "retreat" and not ai.combat.target_far(s)
		if moved < 150.0 and d > 800.0 and not fighting:
			e["stuck_s"] = float(e["stuck_s"]) + POSITION_EVERY


## What the ship's last move slid along: unit kinds with their places, and
## "rock" for anything that is not a unit, as text.
func _colliders(s: Ship) -> String:
	var out := []
	for i in s.get_slide_collision_count():
		var col := s.get_slide_collision(i).get_collider()
		if col is Unit:
			out.append("u%d@%d,%d" % [(col as Unit).kind, roundi((col as Node2D).global_position.x), roundi((col as Node2D).global_position.y)])
		else:
			out.append("rock")
	return ";".join(out)


## Print the FLAK_WEDGE_PROBE_JSON line (see HOW TO READ THE OUTPUT) and end
## the run.
func _finish() -> void:
	var rows: Array = []
	var passed := true
	for e: Dictionary in _ships:
		var s: Ship = null
		if is_instance_valid(e["ship"]):
			s = e["ship"] as Ship
		var alive := s != null and s.alive
		var end: Vector2 = s.global_position if alive else e.get("last", Vector2.INF)
		var d := end.distance_to(e["goal"]) if end != Vector2.INF else -1.0
		var reached := alive and d <= ARRIVE_WITHIN
		passed = passed and reached
		rows.append({"team": e["team"], "alive": alive, "reached": reached,
				"end": [roundi(end.x), roundi(end.y)] if end != Vector2.INF else [], "goal": [roundi((e["goal"] as Vector2).x), roundi((e["goal"] as Vector2).y)],
				"goal_d": roundi(d), "best_d": roundi(float(e["best_d"])) if float(e["best_d"]) != INF else -1,
				"stuck_s": e["stuck_s"], "colliders": _colliders(s) if alive else "", "t_reached": snappedf(float(e["t_reached"]), 0.1), "trail": e["trail"]})
	print("FLAK_WEDGE_PROBE_JSON ", JSON.stringify({"secs": secs, "passed": passed, "usage": Game.usage, "ships": rows}))
	get_tree().quit()
