extends Node
## WHAT THIS IS: the jungle-minion probe. It plays an AI-vs-AI match and, once a second, looks at every lane minion
## of both teams: how far it is from the three lanes and what it is doing. The numbers it exists for (a player's F9
## note: "a minion shouldnt be in the jungle like this"): per match, the minion-seconds spent more than OFF_MARGIN
## world units outside every lane's corridor, and the most any minion strays, with what it was doing then. It
## changes nothing in the match; it only reads.
##
## HOW IT WORKS: every 60 ticks (a second of match time) it goes through World.minions. For each live minion it
## finds the distance to each lane's centre line (Util.dist_to_polyline) less that lane's half width: the minion's
## "excess" is the smallest of the three, so a minion inside any corridor has an excess of 0 or less. A minion
## whose excess is over `off_margin` is "off the lanes" for that second. Its state is one of: "walk" (no target,
## flying its lane's path), "fight:<kind>" (a target of that kind, see Unit.KIND_NAMES; "mothership" for the enemy
## mothership), plus "+leash" when the target itself is further than Minion.LEASH from the minion's lane anchor
## (that is not meant to happen: the targeting never keeps such a target) and ":order" when the minion carries a
## move or hold order. A "JM" line is printed for each off-lane minion-second (unless --jm-quiet): who, where, how far
## out, the state and target, its speed, the push the rocks give it, and the lane point it is flying to. At the end
## (--secs, default 900 seconds of match time, or when a mothership dies) it prints one "JM_JSON {...}" line:
## the minion-seconds seen, the off-lane seconds in all and by state, the number of minions that were ever off the
## lanes, the farthest stray (with the minion's type, team, lane, time, place, state and target), then
## "jungle_minion_probe: N failures" and quits. The failures are the check: with --jm-limit=<seconds> the match
## fails when its off-lane minion-seconds exceed the limit (without it the probe only measures, 0 failures).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --sim-only --seed=7 --difficulty=hard --secs=900 --test=jungle_minion_probe
## Options of its own: --jm-margin=<units> (the off-lane line, default 600), --jm-limit=<seconds> (the check),
## --jm-quiet (no JM lines, only the summary).
##
## WHO USES IT: main.gd loads it for --test=jungle_minion_probe (it calls setup()); run_checks runs it as a check;
## the lead runs it through the queue for the many-seed measurement.

## A minion is off the lanes while it is further than this many world units outside every lane's corridor (the
## corridor is the lane's centre line plus its half width). The jungle starts at the corridor's edge.
const OFF_MARGIN := 600.0
## How many seconds of match time a run lasts when --secs is not given.
const DEFAULT_SECS := 900.0

## The running match (set by setup()).
var world: World
## When the run ends (seconds of match time).
var secs_total := DEFAULT_SECS
## The off-lane line in force (the constant, or the option).
var off_margin := OFF_MARGIN
## The check limit in off-lane minion-seconds (-1 = measure only).
var limit := -1.0
## True when no JM lines are printed.
var quiet := false
## The lanes' centre lines (team 0's direction; the distance does not depend on it), by lane id.
var _lane_pts := {}
## The last tick that was sampled.
var _last_tick := -1
## True once the summary was printed.
var _done := false
## Minion-seconds seen (every live minion, every second).
var _seen := 0
## Off-lane minion-seconds.
var _off := 0
## Off-lane minion-seconds by state.
var _by_state := {}
## The uids of the minions that were ever off the lanes.
var _off_uids := {}
## The farthest stray so far: a record of the minion's excess (INF-free: starts at -INF) and what it was doing.
var _far := {"excess": -INF}
## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_physics_priority = -100
	secs_total = float(Game.opt("secs", DEFAULT_SECS))
	off_margin = float(Game.opt("jm-margin", OFF_MARGIN))
	limit = float(Game.opt("jm-limit", -1.0))
	quiet = Game.opt("jm-quiet", false) != false
	for lane: String in MapLayout.LANE_ORDER:
		_lane_pts[lane] = MapLayout.lane_points(lane, 0)
	# A match that ends before --secs (a mothership dies) makes main.gd quit at once: the summary must be printed
	# in the same signal, so connect here (main.gd connected first and only asked to quit).
	Events.match_over.connect(_on_match_over)
	print("jungle_minion_probe: secs=%.0f margin=%.0f preset=%s difficulty=%s seed=%s" % [secs_total, off_margin, Game.preset, Game.difficulty, str(Game.opt("seed", -1))])


## The excess of position `p` and the lane it is nearest to: the distance to that lane's centre line less its half
## width (negative inside its corridor). Returns {"excess": float, "lane": String}.
func _excess_at(p: Vector2) -> Dictionary:
	var best := INF
	var best_lane := ""
	for lane: String in MapLayout.LANE_ORDER:
		var e := Util.dist_to_polyline(p, _lane_pts[lane]) - float(MapLayout.LANES[lane]["half"])
		if e < best:
			best = e
			best_lane = lane
	return {"excess": best, "lane": best_lane}


## What minion `m` is doing: "walk", or "fight:<kind of target>" (see the top of this file), with "+leash" and ":order" marks.
func _state_of(m: Minion) -> String:
	var s := "walk"
	if m.target != null and is_instance_valid(m.target) and m.target.alive:
		s = "fight:" + ("mothership" if m.target is Mothership else str(Unit.KIND_NAMES[m.target.kind]))
		if MinionTargeting.target_point(m).distance_to(MinionTargeting.lane_anchor(m)) >= Minion.LEASH:
			s += "+leash"
	if str(m.order.get("type", "lane")) != "lane":
		s += ":order"
	return s


## Every tick, before the World's: sample once a second and end the run on time.
@warning_ignore("integer_division")
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	var tick := world.tick_count
	if tick == _last_tick:
		return
	_last_tick = tick
	if tick > 0 and tick % 60 == 0:
		_sample(tick / 60)
	if world.time >= secs_total or world.phase != "play":
		_finish()


## One second's sample of every live minion (second number `sec` of the run).
func _sample(sec: int) -> void:
	for m: Minion in world.minions:
		if not m.alive:
			continue
		_seen += 1
		var at := _excess_at(m.global_position)
		var ex: float = at["excess"]
		if ex <= off_margin:
			continue
		var state := _state_of(m)
		_off += 1
		_by_state[state] = int(_by_state.get(state, 0)) + 1
		_off_uids[m.uid] = true
		var tgt := "-"
		if m.target != null and is_instance_valid(m.target) and m.target.alive:
			tgt = "%s@%.0f,%.0f" % [m.target.display_name, m.target.global_position.x, m.target.global_position.y]
		if not quiet:
			# Where it is heading (its lane's next point), how fast it flies, and how hard the rocks push it.
			var goal := Vector2.INF
			if not m.path.is_empty():
				goal = m.path[mini(m.path_i, m.path.size() - 1)]
			print("JM t=%d uid=%d team=%d lane=%s %s x=%.0f y=%.0f out=%.0f near=%s state=%s tgt=%s v=%.0f rock=%.0f pi=%d/%d goal=%.0f,%.0f" % [sec, m.uid, m.team, m.lane, m.mtype, m.global_position.x, m.global_position.y, ex, at["lane"], state, tgt, m.velocity.length(), m._rock_push.length(), m.path_i, m.path.size(), goal.x, goal.y])
		if ex > float(_far["excess"]):
			_far = {"excess": snappedf(ex, 1.0), "t": sec, "uid": m.uid, "team": m.team, "lane": m.lane, "type": m.mtype, "x": snappedf(m.global_position.x, 1.0), "y": snappedf(m.global_position.y, 1.0), "state": state, "target": tgt, "near": at["lane"]}


## The match ended on its own (a mothership was destroyed): print the summary now.
func _on_match_over(_winner: int, _reason: String) -> void:
	if not _done:
		_finish()


## The end: the summary line, the check, and quit.
func _finish() -> void:
	if _done:
		return
	_done = true
	if limit >= 0.0 and float(_off) > limit:
		_fails += 1
		print("FAIL %d minion-seconds more than %.0f units outside every lane (limit %.0f)" % [_off, off_margin, limit])
	var summary := {"seed": int(Game.opt("seed", -1)), "secs": snappedf(world.time, 0.1), "margin": off_margin, "minion_secs": _seen, "off_secs": _off, "off_minions": _off_uids.size(), "by_state": _by_state, "farthest": _far if float(_far["excess"]) > -INF else {}}
	print("JM_JSON %s" % JSON.stringify(summary))
	print("jungle_minion_probe: %d failures" % _fails)
	get_tree().quit()
