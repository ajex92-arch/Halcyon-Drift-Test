class_name MapBuilderJungle
extends RefCounted
## WHAT THIS IS: step 3 of the map maker (a part of MapBuilder, kept in its
## own file). It lays out the jungle: the rocky areas between the lanes,
## with monster camps, entrances from the lanes, and winding paths that
## small ships can follow.
##
## HOW IT WORKS: the map is split into four quarters: "tl" (top-left),
## "bl" (bottom-left), "tr" (top-right) and "br" (bottom-right). MapLayout
## only lists Aurelian's two quarters (tl and bl); the right-hand ones are
## mirror copies.
##   1. Camps: every camp in MapLayout.CAMPS is written into the map twice
##      (as authored, and mirrored into tr or br), and fill rocks must stay
##      MapLayout.CAMP_CLEAR_RADIUS away from both. The camps on the centre
##      line (MapLayout.CAMPS_CENTRE) are written once: they belong to both
##      halves.
##   2. Entrances: for every entrance in MapLayout.ENTRANCES, we find the
##      corridor it opens from, note a gate for the lane wall step
##      (MapBuilder.gates), write the entrance into the map twice, and add
##      a short path from just inside the corridor to the jungle side.
##   3. Winding paths: in each of Aurelian's quarters we join up all the
##      entrance and camp points (the quarter's centre camp too) with the
##      shortest set of straight links that connects them all (a "minimum
##      spanning tree"), plus the one shortest extra link, so there is a
##      loop to run around. Each link gets a random bend in the middle (this
##      uses random numbers).
##   4. Roads to the ore nodes: every ore node in the jungle (MapLayout.NODES
##      with a "gate") gets a straight road from the inside point of its gate
##      to its centre, which the mining drones follow. The road does not pass
##      a camp: the nodes are not part of the winding paths of step 3.
## Every path is added together with its mirror copy (_add_path()). A path
## that ends at a centre camp meets its mirror copy there, which is what
## joins the jungle of Aurelian's half to the jungle of Vhorr's half: the
## top jungle is one jungle, and so is the bottom one. A road to a shared
## ore node on the centre line meets its mirror copy at the node in the same
## way.
##
## WHO USES IT: only MapBuilder._run(), which makes one, calls run() once
## and throws it away. The paths it makes are used by the fill step (no
## rocks on paths) and the route step (route dots along paths).

## How close (world units) to a lane's edge a winding path may bend before it
## is bent the other way round (_bend_point()).
const WALL_SHY := 700.0

## The map builder this part works for. We use its random numbers (rng),
## its map (info) and its lists (corridors, keep_out, gates).
var mb: MapBuilder


## Remember the builder. MapBuilder makes this part once per map.
func _init(builder: MapBuilder) -> void:
	mb = builder


## Lay out the camps, the entrances and the paths (see HOW IT WORKS).
func run() -> void:
	# The camps to lay out: MapLayout.CAMPS, plus (only for the "camp4"
	# variant, fork teamfights_jungle idea D7) MapLayout.CAMPS_EXTRA. With the
	# variant off this is MapLayout.CAMPS itself, so the map is built exactly
	# as before.
	var camp_list: Array = MapLayout.CAMPS
	var camp4 := Game.variant("camp4")
	if camp4 != "" and camp4 != "off":
		camp_list = MapLayout.CAMPS + MapLayout.CAMPS_EXTRA
	# Step 1: camps. A mirrored camp's id swaps its quarter: "tl_a" becomes
	# "tr_a", "bl_b" becomes "br_b".
	for cd: Dictionary in camp_list:
		var p: Vector2 = cd["pos"]
		mb.info.camps.append({"id": cd["id"], "type": cd["type"], "pos": p, "quad": cd["quad"]})
		var mq: String = "tr" if cd["quad"] == "tl" else "br"
		mb.info.camps.append({"id": mq + str(cd["id"]).substr(2), "type": cd["type"], "pos": MapLayout.mirror(p), "quad": mq})
		mb.keep_out.append({"c": p, "r": MapLayout.CAMP_CLEAR_RADIUS})
		mb.keep_out.append({"c": MapLayout.mirror(p), "r": MapLayout.CAMP_CLEAR_RADIUS})
	# The camps on the centre line: once each, since a mirror copy would stand
	# on the camp itself.
	for cd: Dictionary in MapLayout.CAMPS_CENTRE:
		mb.info.camps.append({"id": cd["id"], "type": cd["type"], "pos": cd["pos"], "quad": cd["quad"]})
		mb.keep_out.append({"c": cd["pos"], "r": MapLayout.CAMP_CLEAR_RADIUS})
	# Step 2: entrances and gates. `by_quad` collects the jungle-side point
	# of every entrance, per quarter, for step 3.
	var by_quad := {"tl": [], "bl": []}
	for e: Dictionary in MapLayout.ENTRANCES:
		# `lane_pt` is on the corridor's centre line, `inside` is just inside
		# the jungle. `edge` is where the line between them crosses the
		# corridor's edge, and `s` how far along the corridor that is.
		var lane_pt: Vector2 = e["lane"]
		var inside: Vector2 = e["inside"]
		var corr := _corridor_at(lane_pt)
		var dir := (inside - lane_pt).normalized()
		var edge := lane_pt + dir * float(corr["half"])
		var proj := Util.project_on_polyline(lane_pt, corr["pts"])
		mb.gates.append({"corridor": corr["id"], "s": float(proj["s"]), "dir": dir, "edge": edge})
		# The entrance as authored (t = 0) and mirrored (t = 1).
		for t in 2:
			var ent := {"quad": e["quad"] if t == 0 else ("tr" if e["quad"] == "tl" else "br"),
				"lane": lane_pt if t == 0 else MapLayout.mirror(lane_pt),
				"inside": inside if t == 0 else MapLayout.mirror(inside),
				"edge": edge if t == 0 else MapLayout.mirror(edge)}
			mb.info.entrances.append(ent)
		(by_quad[e["quad"]] as Array).append(inside)
		# The short path through the gate: from 40 units inside the corridor
		# to the jungle side.
		_add_path(PackedVector2Array([edge - dir * 40.0, inside]))
	# Step 3: winding paths. Per quarter: a minimum spanning tree over its
	# entrances and camps, plus one loop.
	for q: String in ["tl", "bl"]:
		# The points to join: this quarter's entrances, then its camps.
		var pts: Array = (by_quad[q] as Array).duplicate()
		for cd: Dictionary in camp_list:
			if cd["quad"] == q:
				pts.append(cd["pos"])
		# The centre camp of this half of the jungle (quad "tc" belongs with
		# "tl", "bc" with "bl"), last, so the order of the others is unchanged.
		for cd: Dictionary in MapLayout.CAMPS_CENTRE:
			if (cd["quad"] == "tc") == (q == "tl"):
				pts.append(cd["pos"])
		var edges := _mst(pts)
		edges.append_array(_extra_edges(pts, edges, 1))
		# Each link a-b becomes a 3-point path whose middle point is pushed
		# sideways by a random amount: up to 15% of the link's length to
		# either side (one random number per link), unless that would bring
		# the path close to a lane wall (see _bend_point()).
		for e2: Array in edges:
			var a: Vector2 = pts[e2[0]]
			var b: Vector2 = pts[e2[1]]
			var mid := _bend_point(a, b, (mb.rng.next() - 0.5) * 0.3)
			_add_path(PackedVector2Array([a, mid, b]))
	# Step 4: the road to every ore node in the jungle: from the inside point
	# of its gate to its centre, in a straight line (a middle point on the line
	# makes the route step put dots along it).
	for nd: Dictionary in MapLayout.NODES:
		if nd.has("gate"):
			var from: Vector2 = MapLayout.ENTRANCES[int(nd["gate"])]["inside"]
			var to: Vector2 = nd["pos"]
			_add_path(PackedVector2Array([from, (from + to) * 0.5, to]))


## The middle point of the winding path from `a` to `b`: the middle of the
## link pushed sideways by `k` times its length (`k` is the random amount).
## A path whose middle would come within WALL_SHY of a lane's edge bends the
## other way round instead, away from the wall, so no jungle path runs into the
## wall rocks.
func _bend_point(a: Vector2, b: Vector2, k: float) -> Vector2:
	var side := (b - a).orthogonal().normalized() * (b - a).length()
	var mid := (a + b) * 0.5 + side * k
	if _lane_gap(mid) < WALL_SHY:
		var other := (a + b) * 0.5 - side * k
		if _lane_gap(other) > _lane_gap(mid):
			mid = other
	return mid


## How far (world units) point `p` is from the edge of the nearest lane.
func _lane_gap(p: Vector2) -> float:
	var best := INF
	for c: Dictionary in mb.corridors:
		best = minf(best, Util.dist_to_polyline(p, c["pts"]) - float(c["half"]))
	return best


## Add a jungle path to the map, followed by its mirror copy on Vhorr's
## half.
func _add_path(pl: PackedVector2Array) -> void:
	mb.info.jungle_paths.append(pl)
	var m := PackedVector2Array()
	for p in pl:
		m.append(MapLayout.mirror(p))
	mb.info.jungle_paths.append(m)


## The minimum spanning tree of `pts`: the shortest set of straight links
## that joins every point to every other (through other points). Returns
## the links as [[i, j], ...] (indexes into `pts`). It grows a tree from
## point 0: each round it adds the shortest link from a point already in
## the tree to a point not yet in it (this is called Prim's method). On a
## tie, the link found first wins.
func _mst(pts: Array) -> Array:
	var n := pts.size()
	var in_tree := {0: true}
	var edges: Array = []
	while in_tree.size() < n:
		# Find the shortest link from the tree to a point outside it.
		var best := INF
		var be := [-1, -1]
		for i: int in in_tree:
			for j in n:
				if in_tree.has(j):
					continue
				var d := (pts[i] as Vector2).distance_to(pts[j])
				if d < best:
					best = d
					be = [i, j]
		# (Can't happen with real points, but never loop forever.)
		if be[0] < 0:
			break
		# Take that link and bring its far point into the tree.
		edges.append(be)
		in_tree[be[1]] = true
	return edges


## The `k` shortest links between points of `pts` that are not already in
## `existing`, as [[i, j], ...] with i < j. Used to add a loop to the tree.
func _extra_edges(pts: Array, existing: Array, k: int) -> Array:
	# Remember the links we already have (smaller index first).
	var used := {}
	for e: Array in existing:
		used[Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))] = true
	# Every other pair of points, as [length, i, j], shortest first.
	var cand: Array = []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if not used.has(Vector2i(i, j)):
				cand.append([(pts[i] as Vector2).distance_to(pts[j]), i, j])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	# Take the first k.
	var out: Array = []
	for c: Array in cand:
		if out.size() >= k:
			break
		out.append([c[1], c[2]])
	return out


## The corridor (lane or connector, from MapBuilder.corridors) whose centre
## line is closest to `p`. On a tie, the one listed first wins.
func _corridor_at(p: Vector2) -> Dictionary:
	var best: Dictionary = mb.corridors[0]
	var bd := INF
	for c: Dictionary in mb.corridors:
		var d := Util.dist_to_polyline(p, c["pts"])
		if d < bd:
			bd = d
			best = c
	return best
