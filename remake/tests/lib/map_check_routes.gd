extends RefCounted
## WHAT THIS IS: the "roads" half of the map check (tests/map_check.gd): the
## route graph (the road map that AI ships and drones follow) against the
## places on the map. Can strike craft get from each mothership to every
## monster camp and every ore node? Does every ore node have a road for
## mining drones? How close do those drone roads come to a monster camp? Are
## the edge fields separate from each other and from the jungle?
##
## HOW IT WORKS:
##   - Strike craft ask RouteGraph.path(from, to, true), the call the AI
##     pilots make ("true" = small ships may use the jungle roads). They start
##     where a ship launches (Mothership.launch_point) and go to each camp and
##     node. An empty answer means no road.
##   - Mining drones are not copied here but really made: for every ore node
##     (a node with ore rocks) and every team that may mine it, a real
##     MiningDrone is created with
##     the node as its order. Its own code plans the trip out (when it is
##     made) and, when we tell it to go home from the node's richest rock, the
##     trip home. So whatever rule MiningDrone and WorldMining use today
##     (big-ship roads only, to the mothership's drop-off point), the test
##     follows it by itself. Each road is then held against the monster camps:
##     a camp shoots anything that comes within its "aggro" range and watches
##     out to its "leash" range (Jungle.CAMPS); a drone road that comes
##     that close is reported as a WARN (not a failure: a map may choose to
##     have such roads, but someone should know).
##   - The ore nodes themselves are also held against the camps: drones mine
##     at the node's ore rocks.
##   - Every road link is checked for rocks in the way of a ship (information
##     only).
##
## WHO USES IT: tests/map_check.gd. It uses add() and check() of
## tests/lib/map_check_layout.gd and ship_radii() of map_check_choke.gd.

const Layout := preload("res://tests/lib/map_check_layout.gd")
const Choke := preload("res://tests/lib/map_check_choke.gd")


## Strike craft from each mothership can reach every camp and every node on
## the route graph.
static func reach(w: World, rows: Array, nums: Dictionary) -> void:
	var route := w.map.route
	var missing: Array = []
	var asked := 0
	var longest := 0.0
	for t in 2:
		var from: Vector2 = w.mothership(t).launch_point(2)
		for c: Dictionary in w.map.camps:
			asked += 1
			var path := route.path(from, c["pos"], true)
			if path.is_empty():
				missing.append("%s to camp %s" % [Rules.TEAM_NAMES[t], c["id"]])
			else:
				longest = maxf(longest, Util.polyline_length(path))
		for n: ResourceNode in w.nodes:
			asked += 1
			var path := route.path(from, n.global_position, true)
			if path.is_empty():
				missing.append("%s to node %s" % [Rules.TEAM_NAMES[t], n.node_id])
			else:
				longest = maxf(longest, Util.polyline_length(path))
	Layout.check(rows, "strike craft reach every camp and node from both motherships", missing.is_empty(),
		"%d routes asked (%d camps and %d nodes, from 2 motherships); longest %d%s" % [asked, w.map.camps.size(), w.nodes.size(), roundi(longest), "" if missing.is_empty() else "; no road: " + ", ".join(missing.slice(0, 8))])
	nums["strike_routes"] = {"asked": asked, "no_road": missing.size(), "longest": roundi(longest)}


## The edge fields (MapBuilderEdge): every opening in a side lane's outer wall
## lies between two lane turrets (the plan's fractions, one opening to a gap
## between two turrets), and no route leads round a lane turret: each field's
## cluster of pockets is joined to nothing but its own opening, so a ship that
## goes in comes out of the same opening. The second is checked on the route
## graph itself: from each opening's inside dot, walk only the small-craft (jungle)
## dots; the walk must meet no other edge opening and nothing of the jungle (no
## jungle entrance, camp or node). Strike craft from both motherships must reach
## the farthest dot of every cluster.
static func edges(w: World, rows: Array, nums: Dictionary) -> void:
	var info := w.map
	var route := info.route
	# Part 1: the plan. Every lane turret of both teams, and every opening, as a
	# fraction of the lane's length from Aurelian's mothership.
	var turrets: Array = []
	for v in MapLayout.LANE_TURRET_FRACTIONS.values():
		turrets.append(float(v))
		turrets.append(1.0 - float(v))
	turrets.sort()
	var openings: Array = []
	for v in MapLayout.EDGE_OPENING_FRACTIONS:
		openings.append(float(v))
		if absf(float(v) - 0.5) > 0.0001:
			openings.append(1.0 - float(v))
	var plan_problems: Array = []
	var per_gap := {}
	for f: float in openings:
		var below := 0
		for t: float in turrets:
			if absf(t - f) < 0.005:
				plan_problems.append("opening %.2f is on a turret" % f)
			if t < f:
				below += 1
		if below == 0 or below == turrets.size():
			plan_problems.append("opening %.2f is beyond the outer turrets" % f)
		per_gap[below] = int(per_gap.get(below, 0)) + 1
	for g in per_gap:
		if int(per_gap[g]) > 1:
			plan_problems.append("%d openings between the same two turrets" % int(per_gap[g]))
	Layout.check(rows, "edge openings lie between the lane turrets", plan_problems.is_empty(),
		"%d openings per side lane, %d turrets per lane (the plan's fractions)%s" % [openings.size(), turrets.size(), "" if plan_problems.is_empty() else "; " + "; ".join(plan_problems.slice(0, 4))])
	# Part 2: the route graph. The dot at each opening's inside point, and the
	# dots that belong to the jungle (its entrances, camps and nodes).
	var edge_dots: Array = []
	var jungle_dots := {}
	var no_dot: Array = []
	for e: Dictionary in info.entrances:
		var d := _dot_at(route, e["inside"])
		if d < 0:
			no_dot.append("(%d,%d)" % [roundi((e["inside"] as Vector2).x), roundi((e["inside"] as Vector2).y)])
		elif bool(e.get("edge_field", false)):
			edge_dots.append(d)
		else:
			jungle_dots[d] = true
	for c: Dictionary in info.camps:
		jungle_dots[_dot_at(route, c["pos"])] = true
	for n: Dictionary in info.nodes:
		if not (n["ore"] as Array).is_empty():
			jungle_dots[_dot_at(route, n["pos"])] = true
	var leaks: Array = []
	var farthest: Array = []
	var sizes: Array = []
	for d0: int in edge_dots:
		var seen := {d0: true}
		var queue: Array = [d0]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for l: Array in route.adj[cur]:
				var nb: int = l[0]
				if route.jungle[nb] == 0 or seen.has(nb):
					continue
				seen[nb] = true
				queue.append(nb)
		sizes.append(seen.size())
		var far := d0
		for d1: int in seen:
			if route.pos[d1].distance_to(route.pos[d0]) > route.pos[far].distance_to(route.pos[d0]):
				far = d1
			if d1 != d0 and edge_dots.has(d1):
				leaks.append("the field at (%d,%d) reaches another opening" % [roundi(route.pos[d0].x), roundi(route.pos[d0].y)])
			elif jungle_dots.has(d1):
				leaks.append("the field at (%d,%d) reaches the jungle" % [roundi(route.pos[d0].x), roundi(route.pos[d0].y)])
		farthest.append(far)
	Layout.check(rows, "edge fields are separate: no route leads round a lane turret", leaks.is_empty() and no_dot.is_empty() and not edge_dots.is_empty(),
		"%d openings, each field's dots %s%s%s" % [edge_dots.size(), str(sizes), "" if leaks.is_empty() else "; " + "; ".join(leaks.slice(0, 4)),
			"" if no_dot.is_empty() else "; no route dot at " + ", ".join(no_dot.slice(0, 4))])
	# Part 3: strike craft from each mothership reach the farthest dot of every field.
	var missing: Array = []
	for t in 2:
		var from: Vector2 = w.mothership(t).launch_point(2)
		for d: int in farthest:
			if route.path(from, route.pos[d], true).is_empty():
				missing.append("%s to (%d,%d)" % [Rules.TEAM_NAMES[t], roundi(route.pos[d].x), roundi(route.pos[d].y)])
	Layout.check(rows, "strike craft reach every edge field from both motherships", missing.is_empty() and not farthest.is_empty(),
		"%d fields%s" % [farthest.size(), "" if missing.is_empty() else "; no road: " + ", ".join(missing.slice(0, 4))])
	nums["edge_fields"] = {"openings": edge_dots.size(), "dots": sizes, "leaks": leaks.size(), "unreached": missing.size()}


## The route dot standing at `p` (within 30 world units), or -1.
static func _dot_at(route: RouteGraph, p: Vector2) -> int:
	for i in route.pos.size():
		if route.pos[i].distance_to(p) < 30.0:
			return i
	return -1


## Every ore node has a mining-drone road out and home, built by the drone's
## own code; and how close those roads (and the nodes' ore rocks) lie to the
## monster camps.
static func drones(w: World, rows: Array, nums: Dictionary) -> void:
	var made: Array = []
	var no_road: Array = []
	var near_aggro := 0
	var near_leash := 0
	var closest := INF
	var closest_name := ""
	for n: ResourceNode in w.nodes:
		# A turret site has no ore, so no drone goes there.
		if n.ore_pos.is_empty():
			continue
		var served := false
		for t in 2:
			# The rule of WorldMining.best_node_for_drone: a team never works
			# the other team's own node (near its mothership or in its jungle).
			if MapLayout.is_team_kind(n.node_kind) and n.side != t:
				continue
			var d := w.spawn_mining_drone(t, n.node_id)
			var out_path := d.path.duplicate()
			var rock := n.best_rock(d.global_position)
			if rock >= 0:
				d.global_position = n.ore_pos[rock]
			d._go_home()
			var home_path := d.path.duplicate()
			w.combat.kill_silently(d)
			for leg in 2:
				var path: PackedVector2Array = out_path if leg == 0 else home_path
				var label := "%s %s %s" % [Rules.TEAM_NAMES[t], n.node_id, "out" if leg == 0 else "home"]
				if path.size() < 2:
					no_road.append(label)
					continue
				if leg == 1:
					served = true
				var near := _nearest_camp(w, path)
				if near["dist"] < closest:
					closest = near["dist"]
					closest_name = "%s to camp %s" % [label, near["id"]]
				var level := ""
				if near["dist"] < near["aggro"]:
					level = "aggro"
					near_aggro += 1
				elif near["dist"] < near["leash"]:
					level = "leash"
					near_leash += 1
				made.append({"route": label, "length": roundi(Util.polyline_length(path)), "camp": near["id"], "dist": roundi(near["dist"]),
					"aggro": roundi(near["aggro"]), "leash": roundi(near["leash"]), "level": level})
				# Every road gets its line: a WARN when it comes within a camp's
				# range, else an INFO with its closest approach.
				var where := "closest camp %s at %d (it shoots within %d, its aggro range, and watches out to %d, its leash range)" % [near["id"], roundi(near["dist"]), roundi(near["aggro"]), roundi(near["leash"])]
				if level == "aggro":
					Layout.add(rows, "warn", "drone road %s passes camp %s" % [label, near["id"]], "INSIDE ITS AGGRO RANGE: " + where)
				elif level == "leash":
					Layout.add(rows, "warn", "drone road %s passes camp %s" % [label, near["id"]], "inside its leash range, outside its aggro range: " + where)
				else:
					Layout.add(rows, "info", "drone road %s" % label, where)
		if not served:
			no_road.append("node %s has no road home for any team" % n.node_id)
	Layout.check(rows, "every ore node has a mining-drone road out and home", no_road.is_empty() and not made.is_empty(),
		"%d roads planned by real drones%s" % [made.size(), "" if no_road.is_empty() else "; missing: " + ", ".join(no_road.slice(0, 8))])
	Layout.add(rows, "info", "drone roads and monster camps",
		"closest approach %d (%s); %d roads inside a camp's aggro range, %d more inside a leash range" % [roundi(closest), closest_name, near_aggro, near_leash])
	nums["drone_roads"] = {"roads": made, "inside_aggro": near_aggro, "inside_leash": near_leash, "closest": roundi(closest) if closest < INF else -1}
	_nodes_vs_camps(w, rows, nums)


## The camp closest to the road `path`: {id, dist, aggro, leash}, where dist
## is the distance from the camp's spot to the nearest point of the road, and
## aggro and leash are that camp type's ranges (Jungle.CAMPS).
static func _nearest_camp(w: World, path: PackedVector2Array) -> Dictionary:
	var best := {"id": "-", "dist": INF, "aggro": 0.0, "leash": 0.0}
	for c: Dictionary in w.map.camps:
		var def: Dictionary = Jungle.CAMPS[c["type"]]
		var dist := Util.dist_to_polyline(c["pos"], path)
		if dist < float(best["dist"]):
			best = {"id": c["id"], "dist": dist, "aggro": float(def["aggro"]), "leash": float(def["leash"])}
	return best


## Drones mine at a node's ore rocks. How close does the nearest ore rock of
## each node lie to a camp, compared with the camp's aggro range?
static func _nodes_vs_camps(w: World, rows: Array, nums: Dictionary) -> void:
	var out: Array = []
	for n: ResourceNode in w.nodes:
		var best := INF
		var best_id := "-"
		var aggro := 0.0
		for c: Dictionary in w.map.camps:
			for p: Vector2 in n.ore_pos:
				var d := p.distance_to(c["pos"])
				if d < best:
					best = d
					best_id = c["id"]
					aggro = float(Jungle.CAMPS[c["type"]]["aggro"])
		out.append({"node": n.node_id, "camp": best_id, "ore_to_camp": roundi(best), "aggro": roundi(aggro)})
		if best < aggro:
			Layout.add(rows, "warn", "drones mining at node %s are inside camp %s's aggro range" % [n.node_id, best_id], "%d from the camp's spot; aggro %d" % [roundi(best), roundi(aggro)])
	nums["node_vs_camps"] = out
	# Turret slots: a camp shoots a turret that stands within its aggro range,
	# built or not, so every slot must lie farther from every camp than that.
	var closest := INF
	var closest_name := ""
	var too_close: Array = []
	for n: ResourceNode in w.nodes:
		for sp: Vector2 in n.slot_pos:
			for c: Dictionary in w.map.camps:
				var d := sp.distance_to(c["pos"])
				var aggro := float(Jungle.CAMPS[c["type"]]["aggro"])
				if d < closest:
					closest = d
					closest_name = "%s to camp %s" % [n.node_id, c["id"]]
				if d <= aggro:
					too_close.append("%s to camp %s at %d" % [n.node_id, c["id"], roundi(d)])
	Layout.check(rows, "turret slots keep out of every camp's aggro range", too_close.is_empty(),
		"closest %d (%s)%s" % [roundi(closest), closest_name, "" if too_close.is_empty() else "; too close: " + ", ".join(too_close.slice(0, 5))])
	nums["slot_vs_camps_closest"] = roundi(closest)


## Every link of the route graph, held against the rocks: is a rock in the
## way of a ship of the right size (strike craft on jungle roads, corvettes
## on lane roads)? Information only: the AI steers around rocks, and a graph
## link does not promise a straight clear flight.
static func links(w: World, rows: Array, nums: Dictionary) -> void:
	var route := w.map.route
	var radii := Choke.ship_radii()
	var checked := 0
	var blocked := 0
	var example := ""
	for a in route.adj.size():
		for e: Array in route.adj[a]:
			var b: int = e[0]
			if b < a:
				continue
			checked += 1
			var pad: float = radii["strike"] if bool(e[1]) else radii["corvette"]
			if not w.asteroids.segment_hit(route.pos[a], route.pos[b], pad).is_empty():
				blocked += 1
				if example == "":
					example = "(%d,%d) to (%d,%d)" % [roundi(route.pos[a].x), roundi(route.pos[a].y), roundi(route.pos[b].x), roundi(route.pos[b].y)]
	Layout.add(rows, "info", "route links with a rock in the way",
		"%d of %d links%s" % [blocked, checked, "" if example == "" else " (e.g. " + example + ")"])
	nums["route_graph"] = {"nodes": route.node_count(), "links": checked, "links_with_rock": blocked}
