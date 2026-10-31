class_name MapBuilderEdge
extends RefCounted
## WHAT THIS IS: step 3 (second part) of the map maker (a part of MapBuilder,
## kept in its own file). It opens up the edge fields: the rock fields outside
## the top and bottom lanes, along the top and bottom edges of the map. Each
## field gets a few small openings in the lane's outer wall, and behind every
## opening a cluster of open pockets joined by short channels, where small craft
## can have a close fight among the rocks.
##
## HOW IT WORKS: for each side lane (top, then bottom) and each fraction in
## MapLayout.EDGE_OPENING_FRACTIONS (a fraction of the lane's length from
## Aurelian's mothership; the first ones are on Aurelian's half, the last one on
## the centre line), in order, and without any random numbers:
##   1. The opening: the point on the lane's centre line at that fraction, the
##      lane's edge on the outer side (away from the map's middle line), and the
##      inside point MapLayout.EDGE_GATE_DEPTH further out.
##   2. It is written as an entrance (flagged "edge_field", so the checks can tell
##      it from a jungle entrance) and as a gate for the lane wall step: two big
##      rocks MapLayout.CHOKE_GAP apart, which only small craft fit through, and a
##      short path through the gate that keeps the throat clear of filler rocks.
##   3. The pockets (MapLayout.EDGE_POCKETS): rocks must stay out of each one
##      (MapBuilder.keep_out), and a path runs from the inside point to the first
##      pocket and on to each next one, so there are route dots for small craft
##      (they are made from the paths like every jungle path).
## Everything is made for Aurelian's half and written again mirrored for Vhorr's
## half, except the opening on the centre line, which is made once and has its
## pockets straight behind it. A cluster is joined to nothing but its own opening,
## so no route leads from one cluster to another except along the lane: nobody
## gets round a lane turret through an edge field.
##
## WHO USES IT: only MapBuilder._run(), which makes one, calls run() once and
## throws it away. The entrances it writes are read like the jungle's (MapBuilderRoute,
## MapBuilderWalls, the checks in tests/map_check.gd).

## The map builder this part works for. We use its map (info) and its lists
## (corridors, keep_out, gates).
var mb: MapBuilder


## Remember the builder. MapBuilder makes this part once per map.
func _init(builder: MapBuilder) -> void:
	mb = builder


## Open every edge field (see HOW IT WORKS).
func run() -> void:
	for lane: String in ["top", "bot"]:
		var pts: PackedVector2Array = mb.info.lanes[lane]
		var total := Util.polyline_length(pts)
		for f: float in MapLayout.EDGE_OPENING_FRACTIONS:
			var s := total * f
			var c := Util.polyline_at(pts, s)
			# Which way the lane runs here, and the direction straight out of it
			# on the side away from the map's middle line.
			var run_dir := (Util.polyline_at(pts, s + 1.0) - Util.polyline_at(pts, s - 1.0)).normalized()
			var out := run_dir.orthogonal()
			if (out.y < 0.0) != (lane == "top"):
				out = -out
			_make_cluster(lane, s, c, out, float(mb.info.lane_half[lane]), absf(c.x - MapLayout.CX) < 1.0)


## Make the opening and the pockets behind it. `s` is how far along the lane
## (world units), `c` the point on its centre line, `out` the direction out of the
## lane there (length 1), `half` half the lane's width, and `on_line` says the
## opening is on the centre line of the map (made once).
func _make_cluster(lane: String, s: float, c: Vector2, out: Vector2, half: float, on_line: bool) -> void:
	var edge := c + out * half
	var inside := edge + out * MapLayout.EDGE_GATE_DEPTH
	# Step 2: the gate for the wall step (the wall is only walked on Aurelian's
	# half and the centre line; the rest is mirrored later) and the entrances.
	mb.gates.append({"corridor": lane, "s": s, "dir": out, "edge": edge})
	var top := lane == "top"
	var quad := ("tc" if top else "bc") if on_line else ("tl" if top else "bl")
	mb.info.entrances.append({"quad": quad, "lane": c, "inside": inside, "edge": edge, "edge_field": true})
	if not on_line:
		mb.info.entrances.append({"quad": "tr" if top else "br", "lane": MapLayout.mirror(c), "inside": MapLayout.mirror(inside),
			"edge": MapLayout.mirror(edge), "edge_field": true})
	_add_path(PackedVector2Array([edge - out * 40.0, inside]), on_line)
	# Step 3: the pockets, each joined to the one before (the first to the
	# inside point). The sideways shift goes toward the centre line.
	var toward_centre := 0.0 if on_line else signf(MapLayout.CX - c.x)
	var prev := inside
	for pk: Dictionary in MapLayout.EDGE_POCKETS:
		var at := edge + out * float(pk["depth"]) + Vector2(toward_centre * float(pk["side"]), 0.0)
		mb.keep_out.append({"c": at, "r": float(pk["radius"])})
		if not on_line:
			mb.keep_out.append({"c": MapLayout.mirror(at), "r": float(pk["radius"])})
		_add_path(PackedVector2Array([prev, (prev + at) * 0.5, at]), on_line)
		prev = at


## Add a path to the map's jungle paths, with its mirror copy unless the
## cluster it belongs to is on the centre line (its mirror copy would be itself).
func _add_path(pl: PackedVector2Array, on_line: bool) -> void:
	mb.info.jungle_paths.append(pl)
	if on_line:
		return
	var m := PackedVector2Array()
	for p in pl:
		m.append(MapLayout.mirror(p))
	mb.info.jungle_paths.append(m)
