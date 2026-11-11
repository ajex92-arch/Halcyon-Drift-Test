extends Node
## WHAT THIS IS: the "flak trace probe": a measuring tool that follows the AI
## pilots' ships of one hull (the Flak Frigate by default) through an AI-vs-AI
## match and writes down, for every time one of them sits still far from its
## goal, where it is, what its brain wants, and what is around it. It also
## counts every AI pilot's flying seconds by hull, so "stuck seconds per
## flying hour" can be worked out for one hull and for all the others.
##
## HOW IT WORKS: every POSITION_EVERY (2) game seconds it looks at every
## flying AI pilot ship and applies the same "stuck" rule as tests/
## farming_probe.gd and tests/pilot_audit.gd: it moved under 150 over the
## last 8 s, it is more than 800 from its goal, and it is not fighting (it has
## no live target, or its state is home or retreat, or the target is far). For
## the traced hull each stuck sample also writes one row (the ship's place,
## speed, nose, goal, brain state and intent, target, route, the flight part's
## timers, the controls, the admiral's orders for the team, and what solid
## things, ships and minions are near). At most ROWS_PER_EPISODE rows are kept
## for one stuck episode and ROWS_MAX for the whole match. It only reads the
## game and draws no random numbers, so the match plays exactly as without it.
## At the end (--secs, or when a mothership dies) it prints one
## "FLAK_TRACE_PROBE_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=346 --skill-jitter --sim-only --test=flak_trace_probe --secs=1800
## --secs is how many game seconds to watch (default 1800). --trace-hull=<id>
## picks the hull to trace (default flak). With --late the match starts at
## 25:00 and --secs counts from there (--symmetric keeps the mid lane turrets
## of both teams, as in tests/fun_probe.gd).
##
## HOW TO READ THE OUTPUT: FLAK_TRACE_PROBE_JSON holds
##   "time", "ended", "winner", "hull"  the match clock at the end, whether a
##                mothership died, the winning team, and the traced hull;
##   "fly_s"      flying seconds by hull, all AI pilots that are not crew
##                (sampled every 2 s); "stuck_s" and "stuck_n" the stuck seconds
##                and stuck episodes by hull; "crew_fly_s", "crew_stuck_s" the
##                same for crew ships (bought stand-ins), apart;
##   "by_state"   stuck seconds of the traced hull by brain state, and
##                "by_cause" by what the hold looks like (see _cause());
##   "usage"      the game's own usage counters (Game.usage), for example how many
##                detours the ail_c4_flak fix made (ail_c4_gap_detours);
##   "episodes"   one row per stuck episode of the traced hull: start time,
##                length in seconds, team, seat, state at the start, how far
##                from its goal, and the cause word at the start;
##   "rows"       the written-down stuck samples of the traced hull (see _row()).
##
## WHO USES IT: main.gd loads it for --test=flak_trace_probe. It is the AI
## lane's position trace for the stuck-ship item (the AI list's C4).

## Seconds of game time between two position samples.
const POSITION_EVERY := 2.0
## Most trace rows kept for one stuck episode.
const ROWS_PER_EPISODE := 30
## Most trace rows kept for the whole match.
const ROWS_MAX := 2500
## How far (world units) the "what is near" look reaches.
const NEAR_RADIUS := 2000.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1800.0
## The hull whose stuck samples are traced.
var hull := "flak"
## Game time of the next position sample.
var _next_pos := 0.0
## Per ship (instance id): its last positions (every POSITION_EVERY seconds).
var _pos := {}
## Per ship (instance id): the episode going on, or absent. The episode is a
## Dictionary: start time, rows so far, seconds so far.
var _ep := {}
## Flying seconds by hull (pilots, not crew).
var _fly := {}
## Stuck seconds by hull (pilots, not crew).
var _stuck_s := {}
## Stuck episodes by hull (pilots, not crew).
var _stuck_n := {}
## Flying seconds by hull, crew ships only.
var _crew_fly := {}
## Stuck seconds by hull, crew ships only.
var _crew_stuck := {}
## Stuck seconds of the traced hull by brain state.
var _by_state := {}
## Stuck seconds of the traced hull by cause word.
var _by_cause := {}
## One row per finished or running stuck episode of the traced hull.
var _episodes: Array = []
## The written-down stuck samples of the traced hull.
var _rows: Array = []
## A list the unit query fills (reused to save work).
var _tmp: Array = []
## A list the rock query fills (reused to save work).
var _rocks := PackedInt32Array()
## Per ship (instance id): was it stuck at the last sample?
var _was := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	var h = Game.opt("trace-hull")
	if h is String and h != "":
		hull = h
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
		secs += LateGame.START
	_next_pos = world.time


## Add `n` to counter `key` of dictionary `d`.
func _bump(d: Dictionary, key: String, n: float = 1.0) -> void:
	d[key] = float(d.get(key, 0.0)) + n


## Does the brain have a live target?
func _has_target(ai: PilotAI) -> bool:
	return ai.target != null and is_instance_valid(ai.target) and ai.target.alive


## Every tick: take the sample when it is due, and at the end print the JSON
## line and quit.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= _next_pos:
		_next_pos += POSITION_EVERY
		_positions()
	if world.time >= secs or world.phase != "play":
		_finish()


## Every POSITION_EVERY seconds: count each flying AI pilot ship, apply the
## stuck rule, and trace the stuck ones of the traced hull.
func _positions() -> void:
	var alive_ids := {}
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var ai := s.controller as PilotAI
		var id := s.get_instance_id()
		alive_ids[id] = true
		var crew := ai.profile != null and ai.profile.is_crew
		var fly: Dictionary = _crew_fly if crew else _fly
		_bump(fly, s.hull_id, POSITION_EVERY)
		var ps: Array = _pos.get(id, [])
		_pos[id] = ps
		ps.append(s.global_position)
		if ps.size() > 5:
			ps.pop_front()
		if ps.size() < 5:
			continue
		var moved := 0.0
		for q: Vector2 in ps:
			moved = maxf(moved, q.distance_to(ps[0]))
		var fighting := _has_target(ai) and ai.state != "home" and ai.state != "retreat" and not ai.combat.target_far(s)
		var far := s.global_position.distance_to(ai.goal) > 800.0
		var stuck := moved < 150.0 and far and not fighting
		var stuck_d: Dictionary = _crew_stuck if crew else _stuck_s
		if stuck:
			_bump(stuck_d, s.hull_id, POSITION_EVERY)
			if not crew and not bool(_was.get(id, false)):
				_bump(_stuck_n, s.hull_id)
		_was[id] = stuck
		if s.hull_id != hull or crew:
			continue
		if stuck:
			var cause := _cause(s, ai)
			_bump(_by_state, ai.state, POSITION_EVERY)
			_bump(_by_cause, cause, POSITION_EVERY)
			if not _ep.has(id):
				var e := {"t": snappedf(world.time, 0.1), "n": 0, "s": 0.0, "team": ai.profile.team, "slot": ai.profile.slot,
						"state": ai.state, "gd": roundi(s.global_position.distance_to(ai.goal)), "cause": cause}
				_ep[id] = e
				_episodes.append(e)
			var ep: Dictionary = _ep[id]
			ep["s"] = float(ep["s"]) + POSITION_EVERY
			if int(ep["n"]) < ROWS_PER_EPISODE and _rows.size() < ROWS_MAX:
				ep["n"] = int(ep["n"]) + 1
				_rows.append(_row(s, ai, ep, moved, cause))
		else:
			_ep.erase(id)
	# Forget ships that are gone, so the tables stay small.
	for id in _pos.keys():
		if not alive_ids.has(id):
			_pos.erase(id)
			_ep.erase(id)
			_was.erase(id)


## A short word for what the hold looks like, from the brain's own fields, in
## this order: an order from the team (siege, defend), a hold point, a retreat
## or home trip, a target that is far away, no target at all (a lane station).
func _cause(s: Ship, ai: PilotAI) -> String:
	var ts: TeamState = world.teams[s.team]
	if ai.state == "retreat" or ai.state == "home":
		return ai.state
	if ai.hold_point != Vector2.INF:
		return "hold_point"
	if ts.siege_lane != "" and (not s.is_small() or s.hull_id == "bomber"):
		return "siege_" + str(ts.siege_phase)
	if ts.defending(world.time):
		return "defend"
	if _has_target(ai):
		return "target_far:" + ai.intent
	return "station" if ai.intent == "" else ("no_target:" + ai.intent)


## The trace row for one stuck sample of ship `s`.
func _row(s: Ship, ai: PilotAI, ep: Dictionary, moved: float, cause: String) -> Dictionary:
	var ts: TeamState = world.teams[s.team]
	var wp := ai.path[ai.path_i] if (not ai.path.is_empty() and ai.path_i < ai.path.size()) else Vector2.INF
	var to_goal := ai.goal - s.global_position
	var tgt := {}
	if _has_target(ai):
		var t := ai.target
		tgt = {"kind": t.kind, "team": t.team, "d": roundi(s.global_position.distance_to(t.global_position)), "far": ai.combat.target_far(s)}
	var c := s.controls
	var face_err := absf(Util.ang_diff(s.rotation, (c.face_point - s.global_position).angle())) if c.face_point != Vector2.ZERO else -1.0
	var rock_d := -1.0
	if not world.asteroids.clear_at(s.global_position, s.radius + 600.0):
		world.asteroids.nearby(s.global_position, s.radius + 700.0, _rocks)
		rock_d = INF
		for i in _rocks:
			rock_d = minf(rock_d, s.global_position.distance_to(world.asteroids.pos[i]) - world.asteroids.rad[i] - s.radius)
	var oms := world.mothership(s.team)
	var ems := world.mothership(1 - s.team)
	return {"t": snappedf(world.time, 0.1), "ep": ep["t"], "team": s.team, "slot": ai.profile.slot, "state": ai.state, "intent": ai.intent,
			"cause": cause, "x": roundi(s.global_position.x), "y": roundi(s.global_position.y), "gx": roundi(ai.goal.x), "gy": roundi(ai.goal.y),
			"gd": roundi(to_goal.length()), "moved": roundi(moved), "speed": roundi(s.velocity.length()),
			"rot_goal": snappedf(absf(Util.ang_diff(s.rotation, to_goal.angle())), 0.01), "ang_vel": snappedf(s.ang_vel, 0.01),
			"fwd": snappedf(c.forward, 0.01), "strafe": snappedf(c.strafe, 0.01), "face_err": snappedf(face_err, 0.01),
			"path": ai.path.size(), "path_i": ai.path_i,
			"wp": [roundi(wp.x), roundi(wp.y)] if wp != Vector2.INF else [],
			"wp_d": roundi(s.global_position.distance_to(wp)) if wp != Vector2.INF else -1,
			"stuck_t": snappedf(ai.flight._stuck_t, 0.1), "unstick_t": snappedf(ai.flight._unstick_t, 0.1),
			"escape": ai.flight.escape.is_active(), "fallback": snappedf(ai.fallback_t, 0.1), "evade": snappedf(ai.evade_t, 0.1),
			"opening_done": ai.opening_done, "since_launch": roundi(world.time - ai.launched_at),
			"hull_frac": snappedf(s.hull_frac(), 0.01), "open_lane": world.map.in_open_lane(s.global_position),
			"siege": [str(ts.siege_lane), str(ts.siege_phase)], "defend": ts.defending(world.time), "wp_order": ts.has_waypoint(),
			"target": tgt, "rock_d": roundi(rock_d) if rock_d != INF else -2,
			"own_ms_hd": roundi(oms.hull_dist(s.global_position)) if oms != null else -1,
			"enemy_ms_hd": roundi(ems.hull_dist(s.global_position)) if ems != null else -1,
			"rot": snappedf(s.rotation, 0.01), "colliders": _colliders(s), "wps": _wps(ai), "near": _near(s)}


## The next waypoints of the brain's route from the one it flies to (up to
## four, as whole-number [x, y] pairs).
func _wps(ai: PilotAI) -> Array:
	var out: Array = []
	for k in range(ai.path_i, mini(ai.path_i + 4, ai.path.size())):
		out.append([roundi(ai.path[k].x), roundi(ai.path[k].y)])
	return out


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


## What is around `s` within NEAR_RADIUS, as "<kind><a|e>": [count, nearest
## distance] (a = own team, e = the other team, n = neutral). Kinds are the
## Unit.K_* numbers.
func _near(s: Ship) -> Dictionary:
	var out := {}
	_tmp.clear()
	for u: Unit in world.unit_hash.query(s.global_position, NEAR_RADIUS, _tmp):
		if u == s or not u.alive:
			continue
		var side := "n" if u.team > 1 else ("a" if u.team == s.team else "e")
		var key := "k%d%s" % [u.kind, side]
		var d := s.global_position.distance_to(u.global_position)
		var cur: Array = out.get(key, [0, INF])
		cur[0] = int(cur[0]) + 1
		cur[1] = minf(float(cur[1]), d)
		out[key] = cur
	for k: String in out.keys():
		out[k] = [int((out[k] as Array)[0]), roundi(float((out[k] as Array)[1]))]
	return out


## Print the FLAK_TRACE_PROBE_JSON line (see HOW TO READ THE OUTPUT) and end
## the run.
func _finish() -> void:
	var ended := world.phase != "play"
	print("FLAK_TRACE_PROBE_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "ended": ended, "winner": world.winner, "hull": hull,
			"fly_s": _fly, "stuck_s": _stuck_s, "stuck_n": _stuck_n, "crew_fly_s": _crew_fly, "crew_stuck_s": _crew_stuck,
			"by_state": _by_state, "by_cause": _by_cause, "usage": Game.usage, "episodes": _episodes, "rows": _rows}))
	get_tree().quit()
