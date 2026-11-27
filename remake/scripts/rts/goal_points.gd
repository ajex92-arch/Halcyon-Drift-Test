class_name GoalPoints
extends RefCounted
## WHAT THIS IS: the places a squadron's goal talks about. It turns a click into the nearest named thing (an
## ore node, a lane turret site or a monster camp) or the lane band under it, and it answers the questions
## the jobs ask of the map: where our foremost turret or post on a lane stands, where the enemy's lane
## turrets and posts stand, where our minion wave has got to, and the points a push may use.
##
## HOW IT WORKS: static functions that only read the world (World.nodes, the map's camps and lanes, the
## minions, the defense posts). snap() and lane_at() are the click's door; the order carries the whole-number
## point, so a replay needs no names. Lanes are walked as a team walks them (MapLayout.lane_points): the list
## starts at the team's own mothership and ends at the enemy's, so "ahead" is always toward the enemy.
##
## WHO USES IT: SquadronThink (the anchors of Defend and Push lane), the Orders cells and the right-click
## (the snapped point and the lane under a click) and tests/squad_check.gd.

## A click this close (world units) to a named thing snaps to it (the beacons' contest radius).
const SNAP_RADIUS := 1500.0


## The nearest named thing (a node of the map or a monster camp) within SNAP_RADIUS of `p`, as a whole-number
## point; else `p` itself as a whole-number point.
static func snap(w: World, p: Vector2) -> Vector2i:
	var best := Vector2.INF
	var best_d := SNAP_RADIUS
	if w != null and w.map != null:
		for nd: Variant in w.map.nodes:
			var np: Vector2 = (nd as Dictionary)["pos"]
			var d := p.distance_to(np)
			if d <= best_d:
				best_d = d
				best = np
		for cp: Variant in w.map.camps:
			var cpos: Vector2 = (cp as Dictionary)["pos"]
			var d2 := p.distance_to(cpos)
			if d2 <= best_d:
				best_d = d2
				best = cpos
	if best == Vector2.INF:
		return Order.point(p)
	return Order.point(best)


## The id of the lane whose band holds `p` (the lane whose centre line is nearest, when `p` is within its half
## width), or "" when `p` is in no lane.
static func lane_at(w: World, p: Vector2) -> String:
	var best := ""
	var best_d := INF
	if w == null or w.map == null:
		return ""
	for id: String in MapLayout.LANE_ORDER:
		if not w.map.lanes.has(id):
			continue
		var d := Util.dist_to_polyline(p, w.map.lanes[id])
		if d <= float(w.map.lane_half.get(id, 0.0)) and d < best_d:
			best_d = d
			best = id
	return best


## The lane `lane` as team `team` walks it (from its own mothership to the enemy's).
static func lane_line(team: int, lane: String) -> PackedVector2Array:
	return MapLayout.lane_points(lane, team)


## The live turret places of `side`'s lane turret sites on `lane`, plus the post when a defense post stands
## there. In the world's own order.
static func lane_structures(w: World, side: int, lane: String) -> Array:
	var out := []
	for node in w.nodes:
		if node.side == side and node.lane == lane and MapLayout.is_lane_site_kind(node.node_kind):
			for t in node.slots:
				if t != null and is_instance_valid(t) and t.alive and t.team == side:
					out.append((t as Node2D).global_position)
	if w.defense_posts != null and w.defense_posts.standing(side, lane):
		out.append(w.defense_posts.site_of(side, lane).pos)
	return out


## How far along `lane` (world units from `team`'s end) the point `p` lies.
static func along(team: int, lane: String, p: Vector2) -> float:
	return float(Util.project_on_polyline(p, lane_line(team, lane))["s"])


## Our foremost living turret or post on `lane` (the one farthest along toward the enemy), else the lane's point
## nearest our base. This is where a Defend on a lane holds; it steps back when that turret falls.
static func lane_anchor(w: World, team: int, lane: String) -> Vector2:
	var best := Vector2.INF
	var best_s := -1.0
	for p: Vector2 in lane_structures(w, team, lane):
		var s := along(team, lane, p)
		if s > best_s:
			best_s = s
			best = p
	if best != Vector2.INF:
		return best
	return Util.polyline_at(lane_line(team, lane), 500.0)


## How far along `lane` the front of `team`'s minion wave has got (world units from its own end; only minions
## within SquadronRules.FRONT_BAND of the lane line count), or -1 with no wave out.
static func front_s(w: World, team: int, lane: String) -> float:
	var pts := lane_line(team, lane)
	var best := -1.0
	for m in w.minions:
		if m.team != team or not m.alive or m.lane != lane:
			continue
		var pr := Util.project_on_polyline(m.global_position, pts)
		if float(pr["dist"]) <= SquadronRules.FRONT_BAND:
			best = maxf(best, float(pr["s"]))
	return best


## The places of `team`'s live minions on `lane`.
static func minion_places(w: World, team: int, lane: String) -> Array:
	var out := []
	for m in w.minions:
		if m.team == team and m.alive and m.lane == lane:
			out.append(m.global_position)
	return out


## The point a squadron pushing `lane` for `team` goes to: SquadronRules.PUSH_LEAD ahead of our minion front,
## moved back out of every enemy lane turret's reach that none of our minions stands within reach of
## (AdmiralPosture.clear_of_reach, the fleet's own rule). With no wave out it is our foremost turret or post on
## the lane (the squadron waits for a wave); with no enemy structure left on the lane it is the lane's far
## end, kept SquadronRules.MOTHERSHIP_KEEP clear of the enemy mothership.
static func push_point(w: World, team: int, lane: String) -> Vector2:
	var enemy := Rules.enemy_of(team)
	var pts := lane_line(team, lane)
	var total := Util.polyline_length(pts)
	var foes := lane_structures(w, enemy, lane)
	var fs := front_s(w, team, lane)
	if fs < 0.0:
		return lane_anchor(w, team, lane)
	var p := Util.polyline_at(pts, minf(fs + SquadronRules.PUSH_LEAD, total))
	if foes.is_empty():
		var ems := w.mothership(enemy)
		if ems != null:
			var s := minf(fs + SquadronRules.PUSH_LEAD, total)
			while s > 0.0 and Util.polyline_at(pts, s).distance_to(ems.global_position) < SquadronRules.MOTHERSHIP_KEEP:
				s -= 100.0
			p = Util.polyline_at(pts, maxf(s, 0.0))
		return p
	var minions := minion_places(w, team, lane)
	var own_ms := w.mothership(team)
	var home := own_ms.global_position if own_ms != null else Vector2.ZERO
	return AdmiralPosture.clear_of_reach(p, foes, minions, SquadronRules.TURRET_REACH, home)
