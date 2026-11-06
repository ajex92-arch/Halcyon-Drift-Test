extends Node
## WHAT THIS IS: the measurement for the lane turrets and the defense posts in
## ONE AI-against-AI match. It runs three of the usual probes side by side, so a
## single match gives all the numbers: pilot_audit (stuck episodes, rock contact,
## crash deaths), lane_probe (minion waves reaching each lane's end) and
## fun_probe (fights of 10 or more ships, match length, the winner). On top it
## counts what the structures change: the lane turrets lost per lane and team (and
## when), the defense posts lost and how long each lane stayed silent (from the
## post's death to the first minion launched on that lane afterwards), when and
## whether each post was rebuilt, the credits each admiral spent in the first 5
## minutes, the sieges (how many, how many reached within 3,000 and within 1,000
## of the enemy mothership's hull), how long each lane turret and post took to
## fall from the first hull damage it took to its death (and who dealt it: pilots,
## minions or others) and how the motherships ended. It only reads
## the match, and it also runs on builds without turret sites or posts (the
## numbers that do not exist there are empty), so the same file measures the
## "before" builds.
##
## HOW IT WORKS: setup() makes the three probes as child nodes and starts them
## (each prints its own result line when the match ends: AUDIT_JSON, LANE_JSON,
## FUN_JSON). This node listens to the turret and post messages and the minion
## launches, samples the sieges once a second, and prints one line at the end:
## S2_JSON {...}.
##
## A test option, --open-lane=<lane>:<team>:<seconds> (for example top:1:100), takes away
## (quietly) the three lane turrets of that team on that lane at that match time, so a
## push on the lane's defense post can be timed without waiting for the turrets to fall;
## without it the match is left alone.
##
## HOW TO RUN IT (from the project folder, the usual gate options):
##   godot --headless --path . --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --sim-only --test=stage2_gate --secs=1800
##
## WHO USES IT: main.gd loads it for --test=stage2_gate (tests/<name>.gd, added after
## the World, then setup() is called). The gate runs go through run_batch with this
## test, and tools/stage2_table.py reads its output.

## The enemy mothership counts as "reached" by a siege when one of our big ships is
## this close (world units) to its hull: the siege plan's own contact distance.
const CONTACT_FAR := 3000.0
## ...and this close, for the stricter count.
const CONTACT_NEAR := 1000.0
## The time (seconds) at which the admirals' spending is read.
const SPEND_AT := 300.0

## The match's World (set by setup()).
var world: World
## The seconds to watch at most (--secs, default 1800).
var secs := 1800.0
## True once S2_JSON was printed.
var _done := false
## The pilot_audit probe (a child node).
var _audit: Node
## The lane_probe probe (a child node).
var _lanes: Node
## The fun_probe probe (a child node).
var _fun: Node
## Lane turrets lost: [time, team, lane, node kind, node id].
var turrets_lost: Array = []
## Defense posts lost: [time, team, lane].
var posts_lost: Array = []
## Post state changes: [time, team, lane, state].
var post_log: Array = []
## Free-wave launches: key "team:lane" -> the match times (seconds) of the minions
## that launched there, in order.
var launches := {}
## The credits each team's admiral had spent at SPEND_AT (-1 = not read yet).
var spent_at := [-1.0, -1.0]
## The match time (seconds) at which each team first owned the Fleet Command Module
## (it has no job now); -1 = never.
var fleet_at := [-1.0, -1.0]
## Per team: the sieges so far, as [start time, reached CONTACT_FAR, reached
## CONTACT_NEAR, end time (-1 = still on)].
var sieges := [[], []]
## Structures that took hull damage and are still standing: instance id ->
## [first hit time, damage by pilots, by minions, by others, hits as [time, damage]].
var _hits := {}
## Turrets and posts destroyed, with how they fell: [kind name, team, lane, first hit
## time (-1 = none seen), death time, damage by pilots, by minions, by others, the
## shortest stretch of seconds in which 90% of the hull damage was dealt (the push)].
var structure_kills: Array = []
## The lane of --open-lane ("" = not asked for, or already done).
var _open_lane := ""
## The team whose lane turrets --open-lane takes away.
var _open_team := 0
## The match time (seconds) at which --open-lane takes them away.
var _open_at := 0.0
## Seconds until the next once-a-second sample.
var _sample_t := 1.0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	_audit = load("res://tests/pilot_audit.gd").new()
	_lanes = load("res://tests/lane_probe.gd").new()
	_fun = load("res://tests/fun_probe.gd").new()
	for probe: Node in [_audit, _lanes, _fun]:
		add_child(probe)
		probe.call("setup", w)
	var open_arg := str(Game.opt("open-lane", ""))
	if open_arg != "":
		var parts := open_arg.split(":")
		_open_lane = parts[0]
		_open_team = int(parts[1])
		_open_at = float(parts[2])
	Events.turret_destroyed.connect(_on_turret)
	Events.unit_killed.connect(_on_killed)
	Events.minion_launched.connect(_on_launch)
	Events.damage_applied.connect(_on_damage)
	if Events.has_signal("post_state_changed"):
		Events.connect("post_state_changed", _on_post_state)


## A turret was destroyed: note which lane site it stood on.
func _on_turret(turret: Node, _by_team: int) -> void:
	var tu := turret as Turret
	if tu == null or tu.node == null:
		return
	turrets_lost.append([snappedf(world.time, 0.1), tu.team, tu.node.lane, tu.node.node_kind, tu.node.node_id])


## A turret or a defense post took damage (only while a probe has switched the
## damage messages on, as pilot_audit does): note the first hit and who dealt what.
func _on_damage(target: Node, info: RefCounted, _amount: float, hull_dmg: float) -> void:
	var u := target as Unit
	if u == null or hull_dmg <= 0.0 or not _is_structure_of_interest(u):
		return
	var rec: Array = _hits.get(u.get_instance_id(), [snappedf(world.time, 0.1), 0.0, 0.0, 0.0, []])
	var di := info as DamageInfo
	var slot := 3
	if di != null and di.source_is_pilot:
		slot = 1
	elif di != null and di.source_is_minion:
		slot = 2
	rec[slot] = float(rec[slot]) + hull_dmg
	(rec[4] as Array).append([world.time, hull_dmg])
	_hits[u.get_instance_id()] = rec


## The shortest stretch of seconds in which at least 90% of the damage in `hits`
## ([time, damage] pairs in time order) was dealt: how long the real push took.
func _push_seconds(hits: Array) -> float:
	var total := 0.0
	for h: Array in hits:
		total += float(h[1])
	if total <= 0.0:
		return -1.0
	var best := INF
	for i in hits.size():
		var sum := 0.0
		for j in range(i, hits.size()):
			sum += float((hits[j] as Array)[1])
			if sum >= 0.9 * total:
				best = minf(best, float((hits[j] as Array)[0]) - float((hits[i] as Array)[0]))
				break
	return snappedf(best, 0.1) if best < INF else -1.0


## Is `u` a lane turret or a defense post (the structures this test times)?
func _is_structure_of_interest(u: Unit) -> bool:
	return u.kind == Unit.K_TURRET or (u.kind < Unit.KIND_NAMES.size() and Unit.KIND_NAMES[u.kind] == "defense post")


## A unit died: note a defense post (a unit of the kind named "defense post"), and
## how a turret or post fell.
func _on_killed(u: Node, _info: RefCounted) -> void:
	var unit := u as Unit
	if unit == null:
		return
	if unit.kind < Unit.KIND_NAMES.size() and Unit.KIND_NAMES[unit.kind] == "defense post":
		posts_lost.append([snappedf(world.time, 0.1), unit.team, str(unit.get("lane"))])
	if _is_structure_of_interest(unit):
		var rec: Array = _hits.get(unit.get_instance_id(), [-1.0, 0.0, 0.0, 0.0, []])
		var lane := ""
		if unit.kind == Unit.K_TURRET:
			lane = (unit as Turret).node.lane if (unit as Turret).node != null else ""
		else:
			lane = str(unit.get("lane"))
		structure_kills.append([Unit.KIND_NAMES[unit.kind], unit.team, lane, rec[0], snappedf(world.time, 0.1), snappedf(float(rec[1]), 1.0), snappedf(float(rec[2]), 1.0), snappedf(float(rec[3]), 1.0), _push_seconds(rec[4])])
		_hits.erase(unit.get_instance_id())


## A free-wave minion launched: note its lane and time.
func _on_launch(m: Node, _wave_id: float) -> void:
	var mm := m as Minion
	var key := "%d:%s" % [mm.team, mm.lane]
	if not launches.has(key):
		launches[key] = []
	(launches[key] as Array).append(snappedf(world.time, 0.1))


## A defense post changed state: note it.
func _on_post_state(team: int, lane: String, state: String, _tick: int) -> void:
	post_log.append([snappedf(world.time, 0.1), team, lane, state])


## The first launch on `key` ("team:lane") at or after match time `t`, or -1.
func _first_launch_after(key: String, t: float) -> float:
	for lt: float in launches.get(key, []):
		if lt >= t:
			return lt
	return -1.0


## Every tick: sample once a second, and print S2_JSON when the match ends (the
## same moment the three probes print theirs).
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	if spent_at[0] < 0.0 and world.time >= SPEND_AT:
		for t in 2:
			spent_at[t] = snappedf(float(world.teams[t].get("spent")) if world.teams[t].get("spent") != null else -1.0, 1.0)
	if _open_lane != "" and world.time >= _open_at:
		for t: Turret in world.turrets.duplicate():
			if t.team == _open_team and t.node != null and t.node.lane == _open_lane and MapLayout.is_lane_site_kind(t.node.node_kind):
				world.combat.kill_silently(t)
		_open_lane = ""
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 1.0
		_sample_sieges()
		for t in 2:
			if float(fleet_at[t]) < 0.0 and world.teams[t].facilities.has("fleet"):
				fleet_at[t] = snappedf(world.time, 1.0)
	if world.time >= secs or world.phase != "play":
		_done = true
		_print()


## Once a second: follow each team's siege and whether its big ships have come
## close to the enemy mothership's hull.
func _sample_sieges() -> void:
	for t in 2:
		var ts: TeamState = world.teams[t]
		var list: Array = sieges[t]
		var on := ts.siege_lane != ""
		var open: Array = list[list.size() - 1] if not list.is_empty() and float((list[list.size() - 1] as Array)[3]) < 0.0 else []
		if on and open.is_empty():
			list.append([snappedf(world.time, 1.0), false, false, -1.0])
			open = list[list.size() - 1]
		elif not on and not open.is_empty():
			open[3] = snappedf(world.time, 1.0)
			open = []
		if not open.is_empty():
			var ems := world.mothership(1 - t)
			if ems != null and ems.alive:
				for s: Ship in world.ships:
					if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE:
						var d := ems.hull_dist(s.global_position)
						if d < CONTACT_FAR:
							open[1] = true
						if d < CONTACT_NEAR:
							open[2] = true


## The hull fraction of each post that still stands, as [team, lane, fraction].
func _post_hulls() -> Array:
	var out: Array = []
	var posts: Variant = world.get("posts")
	if posts != null:
		for p: Unit in posts:
			if p.alive:
				out.append([p.team, str(p.get("lane")), snappedf(p.hull_frac(), 0.01)])
	return out


## Print the one line.
func _print() -> void:
	# The silent time of each lost post: from its death to the first launch on its
	# lane afterwards (-1 = none until the end).
	var silence: Array = []
	for pl: Array in posts_lost:
		var key := "%d:%s" % [int(pl[1]), str(pl[2])]
		var first := _first_launch_after(key, float(pl[0]))
		silence.append({"team": pl[1], "lane": pl[2], "died": pl[0], "next_launch": first, "silent_s": snappedf(first - float(pl[0]), 0.1) if first >= 0.0 else -1.0})
	var live_lane_turrets := [0, 0]
	for n: ResourceNode in world.nodes:
		if n.side >= 0 and n.node_kind != "jungle_team":
			live_lane_turrets[n.side] = int(live_lane_turrets[n.side]) + n.turret_count(n.side)
	var live_posts := [0, 0]
	var dp: Variant = world.get("defense_posts")
	if dp != null:
		for t in 2:
			live_posts[t] = int(dp.call("standing_count", t))
	var ms_hull := []
	for t in 2:
		var ms := world.mothership(t)
		ms_hull.append(snappedf(ms.hull_frac(), 0.01) if ms != null and ms.alive else 0.0)
	var siege_counts := []
	for t in 2:
		var all: Array = sieges[t]
		var far := 0
		var near := 0
		for sg: Array in all:
			far += 1 if bool(sg[1]) else 0
			near += 1 if bool(sg[2]) else 0
		siege_counts.append({"sieges": all.size(), "reached_3000": far, "reached_1000": near})
	print("S2_JSON ", JSON.stringify({
		"time": snappedf(world.time, 1.0),
		"turrets_lost": turrets_lost,
		"structure_kills": structure_kills,
		"post_hull_end": _post_hulls(),
		"posts_lost": posts_lost,
		"post_log": post_log,
		"silence": silence,
		"spent_300": spent_at,
		"fleet_at": fleet_at,
		"sieges": siege_counts,
		"live_lane_turrets": live_lane_turrets,
		"live_posts": live_posts,
		"ms_hull": ms_hull,
		"first_launch": {"0:top": _first_launch_after("0:top", 0.0), "0:mid": _first_launch_after("0:mid", 0.0), "0:bot": _first_launch_after("0:bot", 0.0)},
	}))
