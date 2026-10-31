extends Node
## WHAT THIS IS: a measuring tool for the lane turret sites (its name is the old
## one, from the days of the Crossings). It answers: when does a team lose a lane
## turret, when does it get one back, what stops it from building one back when
## it wants to, and which site does its admiral pick for the first one it buys
## back?
##
## HOW IT WORKS: once a game second it looks at the 18 lane turret sites (kinds
## "outer", "inner" and "inhibitor") and the four shared jungle nodes. For every
## turret slot it notes when a live turret first appears (a turret that stands
## from the start has time 0), when it finishes building (Turret.is_built()) and
## when it is gone. For each site that belongs to a team (and for both teams at
## a shared node) it also asks the same question the admiral's build order asks
## (AdmiralCommand.turret_blocker for a PD turret) and counts the seconds per
## answer: free ("" = it could build), "enemy_near" (an enemy ship or minion
## within the site's build circle), "enemy_turret" (the other team holds the
## node), "lock" (a turret died here recently), "full" (the slot is taken) or
## "other". Beside each answer it counts the team's own pilots and minions within
## PRESENCE_R of the site (the disc the admiral looks at when it picks the outer
## site for its first turret bought back). The first time a team has a turret
## on a lane site again after losing one it writes "first": the site, the time,
## and for the team's outer sites [answer, own ships near] in the sample just
## before the turret was seen and in the sample that saw it. It also notes, per
## team, the time of every lane turret lost ("lost": [time, site]) and every 300
## s the number of live lane turrets and the treasury. At the end it prints one
## "CROSSING_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --test=crossing_probe --secs=900 --skill-jitter
##
## WHO USES IT: main.gd loads it for --test=crossing_probe. It only reads the
## game; it changes nothing in the match.

## The radius (world units) around a site within which the team's own pilots and
## minions are counted. The same disc as the one in which an enemy ship stops a
## team from building on a lane site (TurretData.BUILD_CLEAR_RADIUS, 1,500), and
## the one the admiral's choice of its first turret bought back uses.
const PRESENCE_R := 1500.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 900.0
## Seconds until the next 1 s sample.
var _sample_t := 0.0
## Per turret (key: its instance id) on a watched site: node id, team, game time
## it appeared, game time it finished building (-1 = not yet) and game time it was
## gone (-1 = still there).
var _turrets := {}
## Seconds per answer of the build check: key "node_id:team", value a
## Dictionary answer -> seconds.
var _blocked := {}
## Per team (key "0" or "1"): its first lane turret bought back: "node" (id),
## "t" (game time it was first seen), "before" and "after": for each outer site
## of the team (node id) [build-check answer, own pilots and minions within
## PRESENCE_R], in the sample before the turret was seen and in the one that
## saw it.
var _first := {}
## The last sample's [answer, own ships near] per "team:node_id".
var _prev := {}
## Per team: the game time and site of every lane turret lost, as [time, site].
var _lost := [[], []]
## Every 300 s: [time, live lane turrets of team 0, of team 1, treasury 0,
## treasury 1].
var _timeline := []
## The next game time of a timeline note.
var _timeline_t := 300.0
## A reusable list for the spatial hash (see _own_near()).
var _scratch: Array = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 900.0))


## Every tick: sample once a second, and at the end print the JSON line and
## quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 1.0
		_sample()
	if world.time >= secs or world.phase != "play":
		_finish()


## Is `n` a site the probe watches: a lane turret site or a shared jungle node?
func _watched(n: ResourceNode) -> bool:
	return MapLayout.is_lane_site_kind(n.node_kind) or n.node_kind == "jungle_shared"


## The 1 s checks (see the top of this file).
func _sample() -> void:
	var live := {}
	var now := {}
	var fresh := []
	for n in world.nodes:
		if not _watched(n):
			continue
		for t in n.slots:
			if t != null and is_instance_valid(t) and t.alive:
				live[t.get_instance_id()] = true
				var rec: Dictionary = _turrets.get(t.get_instance_id(), {})
				if rec.is_empty():
					rec = {"node": n.node_id, "team": t.team, "t": snappedf(world.time, 0.1), "ready": -1.0, "gone": -1.0}
					_turrets[t.get_instance_id()] = rec
					# A turret that appears after the start on a lane site is one
					# bought back; the team's first is noted.
					if world.time > 1.0 and MapLayout.is_lane_site_kind(n.node_kind) and not _first.has(str(t.team)):
						fresh.append([t.team, n.node_id])
				if float(rec["ready"]) < 0.0 and t.is_built():
					rec["ready"] = snappedf(world.time, 0.1)
		for team in 2:
			if n.side >= 0 and n.side != team:
				continue
			var key := "%s:%d" % [n.node_id, team]
			var d: Dictionary = _blocked.get(key, {})
			var answer := _category(world.command.turret_blocker(team, n.node_id, "pd"))
			d[answer] = float(d.get(answer, 0.0)) + 1.0
			_blocked[key] = d
			now["%d:%s" % [team, n.node_id]] = [answer, _own_near(team, n.global_position)]
	for id: int in _turrets:
		var rec: Dictionary = _turrets[id]
		if float(rec["gone"]) < 0.0 and not live.has(id):
			rec["gone"] = snappedf(world.time, 0.1)
			var lost_node := world.node_by_id(str(rec["node"]))
			if lost_node != null and MapLayout.is_lane_site_kind(lost_node.node_kind):
				(_lost[int(rec["team"])] as Array).append([snappedf(world.time, 0.1), rec["node"]])
	for f: Array in fresh:
		if not _first.has(str(f[0])):
			_first[str(f[0])] = {"node": f[1], "t": snappedf(world.time, 0.1), "before": _picture(_prev, int(f[0])), "after": _picture(now, int(f[0]))}
	_prev = now
	if world.time >= _timeline_t:
		var counts := [0, 0]
		for n in world.nodes:
			if MapLayout.is_lane_site_kind(n.node_kind):
				counts[n.side] = int(counts[n.side]) + n.turret_count(n.side)
		_timeline.append([roundi(world.time), counts[0], counts[1], roundi(world.teams[0].treasury), roundi(world.teams[1].treasury)])
		_timeline_t += 300.0


## How many live pilots and minions of `team` are within PRESENCE_R of point
## `pos` (the spatial hash may list units a little outside the circle, so the
## distance is checked).
func _own_near(team: int, pos: Vector2) -> int:
	var c := 0
	for u: Unit in world.unit_hash.query(pos, PRESENCE_R, _scratch):
		if u.alive and u.team == team and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION) and u.global_position.distance_to(pos) < PRESENCE_R:
			c += 1
	return c


## From a sample ("team:node_id" -> [answer, own near]) the entries of `team`'s
## outer sites as node id -> [answer, own near]; empty before the first sample.
func _picture(sample: Dictionary, team: int) -> Dictionary:
	var out := {}
	for n in world.nodes:
		if n.node_kind == "outer" and n.side == team and sample.has("%d:%s" % [team, n.node_id]):
			out[n.node_id] = sample["%d:%s" % [team, n.node_id]]
	return out


## A short word for a build-check answer (the sentence from
## ResourceNode.build_blocker, or "" for "it could build").
func _category(sentence: String) -> String:
	if sentence == "":
		return "free"
	if sentence.begins_with("Enemy ships"):
		return "enemy_near"
	if sentence.begins_with("The enemy has"):
		return "enemy_turret"
	if sentence.begins_with("A turret was just"):
		return "lock"
	if sentence.begins_with("Every turret"):
		return "full"
	return "other"


## Print the result and quit.
func _finish() -> void:
	print("CROSSING_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "turrets": _turrets.values(), "blocked": _blocked, "first": _first, "lost": _lost, "timeline": _timeline}))
	get_tree().quit()
