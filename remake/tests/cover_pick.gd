extends Node
## WHAT THIS IS: a helper for placing gas clouds and hidden pockets. It reads
## the finished map and lists open spots where a patch of a given size would
## fit: mostly open ground (ships can fly in), outside every lane corridor, and
## clear of ore nodes, camps and motherships. With --pockets it lists nooks
## instead: small open rooms ringed by rocks that a small ship can reach. It
## changes nothing.
##
## HOW IT WORKS: setup() takes the finished World; the first physics tick scans
## Aurelian's half of the map on a 200-unit grid. For every spot it counts how
## much of an ellipse (the `--size=` width and height) is open ground, and how
## far the spot is from the nearest lane line, ore node, camp and mothership. It
## prints the best spots of each region as lines "PICK x y open=.. lane=.. node=..
## camp=.. base=..", then quits. With --pockets the lines read "POCKET x y
## open=.. ring=.. cloud=.. node=.. camp=.. lane=..": `open` is the open share of
## the room (--size=w,h, default 800,800), `ring` the share of rock around it (a
## ring 700 to 1,000 out), `cloud` the distance to the nearest planned cloud.
## Only rooms a small ship can reach from the lane are listed.
##
## HOW TO RUN IT (from the project folder):
##   godot --headless --path . --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=cover_pick --size=1400,1000
##   (add --pockets, and for example --size=800,800, to look for nooks; --ring=0.3
##   lowers the least share of rock around a nook, 0.45 by default)
##
## WHO USES IT: main.gd loads it for --test=cover_pick. The clouds and pockets
## in MapCover are placed by hand; this only helps choose the spots.

## The least share of the patch's cells that must be open ground (0..1).
const MIN_OPEN := 0.75
## How far a patch's middle must be from a lane line beyond the lane's own half
## width (world units), so it lies in the jungle and not in a corridor.
const LANE_GAP := 500.0
## The nearest a patch's middle may be to an ore node's middle (world units).
const NODE_GAP := 1500.0
## The nearest a patch's middle may be to a camp's middle (world units).
const CAMP_GAP := 1400.0
## The nearest a patch's middle may be to a mothership (world units).
const BASE_GAP := 3500.0
## How many spots are printed for each region.
const PER_REGION := 6
## The least share of rock in the ring around a nook (0..1), with --pockets.
const MIN_RING := 0.45
## The nearest a nook may be to a planned cloud (world units), with --pockets.
const CLOUD_GAP := 1200.0
## The width of a step of the reach test (world units), with --pockets. Fine
## enough to find its way through the 70-unit gaps of the lane walls.
const STEP := 40.0
## The radius of the smallest ship that must be able to reach a nook (world
## units), with --pockets.
const SHIP_R := 9.0

## The running match (set by setup()).
var world: World
## True once the scan is done (it is made once).
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Godot calls this every tick. On the first one, scan, print and quit.
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	_done = true
	_run()
	get_tree().quit()


## Scan Aurelian's half of the map and print the best spots of each region.
func _run() -> void:
	var pockets := bool(Game.opt("pockets", false))
	var size := Vector2(800, 800) if pockets else Vector2(1400, 1000)
	var text := str(Game.opt("size", ""))
	if text != "":
		var v := text.split(",")
		if v.size() == 2:
			size = Vector2(float(v[0]), float(v[1]))
	var half := size * 0.5
	var cell := Rules.VISION_CELL
	if pockets:
		_run_pockets(half, cell)
		return
	var found: Array = []
	var y := 2000.0
	while y < MapLayout.H - 2000.0:
		var x := 3000.0
		while x < MapLayout.CX - 1000.0:
			var at := Vector2(x, y)
			var row := _score(at, half, cell)
			if not row.is_empty():
				found.append(row)
			x += cell
		y += cell
	# Print the best of each region: a third of the width, top or bottom half.
	for yi in 2:
		for xi in 3:
			var list: Array = []
			for row: Dictionary in found:
				var p: Vector2 = row["pos"]
				if (p.y < MapLayout.CY) == (yi == 0) and clampi(int((p.x - 3000.0) / 5600.0), 0, 2) == xi:
					list.append(row)
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
			print("REGION %s x%d: %d spots" % ["top" if yi == 0 else "bottom", xi, list.size()])
			for i in mini(PER_REGION, list.size()):
				var r: Dictionary = list[i]
				var p: Vector2 = r["pos"]
				print("PICK %d %d open=%.2f lane=%d node=%d camp=%d base=%d" % [int(p.x), int(p.y), float(r["open"]), int(r["lane"]), int(r["node"]), int(r["camp"]), int(r["base"])])


## One spot's numbers, or {} when it is not allowed. "score" is the open share
## plus a little for staying clear of the nearest lane, node and camp.
func _score(at: Vector2, half: Vector2, cell: float) -> Dictionary:
	# Distances to the things a patch must keep clear of.
	var lane := INF
	for id: String in world.map.lanes:
		var d := _line_dist(at, world.map.lanes[id])
		lane = minf(lane, d - float(world.map.lane_half[id]))
	var node := INF
	for nd: Dictionary in world.map.nodes:
		node = minf(node, at.distance_to(nd["pos"]))
	var camp := INF
	for c: Dictionary in world.map.camps:
		camp = minf(camp, at.distance_to(c["pos"]))
	var base := INF
	for mp: Vector2 in world.map.mothership_pos:
		base = minf(base, at.distance_to(mp))
	if lane < LANE_GAP + half.length() or node < NODE_GAP or camp < CAMP_GAP or base < BASE_GAP:
		return {}
	# The open share of the cells inside the ellipse.
	var total := 0
	var open := 0
	var x0 := int((at.x - half.x) / cell)
	var x1 := int((at.x + half.x) / cell)
	var y0 := int((at.y - half.y) / cell)
	var y1 := int((at.y + half.y) / cell)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)
			var dx := (c.x - at.x) / half.x
			var dy := (c.y - at.y) / half.y
			if dx * dx + dy * dy > 1.0:
				continue
			total += 1
			if not world.asteroids.blocked(c, 40.0):
				open += 1
	if total == 0 or float(open) / float(total) < MIN_OPEN:
		return {}
	var share := float(open) / float(total)
	var score := share + minf(node, 4000.0) / 40000.0 + minf(camp, 4000.0) / 40000.0 + minf(lane, 3000.0) / 30000.0
	return {"pos": at, "open": share, "lane": lane, "node": node, "camp": camp, "base": base, "score": score}


## The distance from `p` to the polyline `pts` (world units).
func _line_dist(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		best = minf(best, p.distance_to(q))
	return best


## --pockets: list the nooks. A nook is a spot whose room (the ellipse of half
## size `half`) is nearly all open, ringed by rock, reachable by a small ship
## from the top lane, and clear of lanes, nodes, camps, motherships and the
## planned clouds. Printed best first (the most enclosed), the best 12 for each
## quarter of Aurelian's half (0 to 3) and for the edge fields above (4) and
## below (5) the side lanes.
func _run_pockets(half: Vector2, cell: float) -> void:
	var reach := _reachable()
	var found: Array = []
	var y := 700.0
	while y < MapLayout.H - 700.0:
		var x := 3000.0
		while x < MapLayout.CX - 1000.0:
			var at := Vector2(x, y)
			var row := _nook(at, half, cell, reach)
			if not row.is_empty():
				found.append(row)
			x += cell
		y += cell
	for q in 6:
		var list: Array = []
		for row: Dictionary in found:
			var p: Vector2 = row["pos"]
			# Quarters 0 to 3: the jungle (top-left, top-right, bottom-left, bottom-right of
			# Aurelian's half); 4 and 5: the edge fields above and below the side lanes.
			var quarter := (0 if p.y < MapLayout.CY else 2) + (0 if p.x < 11500.0 else 1)
			if p.y < 3000.0:
				quarter = 4
			elif p.y > MapLayout.H - 3000.0:
				quarter = 5
			if quarter == q:
				list.append(row)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ring"]) > float(b["ring"]))
		print("QUARTER %d: %d nooks" % [q, list.size()])
		for i in mini(12, list.size()):
			var r: Dictionary = list[i]
			var p: Vector2 = r["pos"]
			print("POCKET %d %d open=%.2f ring=%.2f cloud=%d node=%d camp=%d lane=%d" % [int(p.x), int(p.y), float(r["open"]), float(r["ring"]), int(r["cloud"]), int(r["node"]), int(r["camp"]), int(r["lane"])])


## The map as a grid of STEP-wide squares: 1 where a small ship (radius SHIP_R)
## can be and that is joined to the top lane through such squares, else 0. A
## flood fill from the middle of the top lane. Index: ix + iy * columns.
func _reachable() -> PackedByteArray:
	var cols := int(ceil(MapLayout.W / STEP))
	var rows := int(ceil(MapLayout.H / STEP))
	var free := PackedByteArray()
	free.resize(cols * rows)
	for iy in rows:
		for ix in cols:
			if not world.asteroids.blocked(Vector2((float(ix) + 0.5) * STEP, (float(iy) + 0.5) * STEP), SHIP_R):
				free[ix + iy * cols] = 1
	# Flood fill from the top lane's centre line (the lane is open ground).
	var lane: PackedVector2Array = world.map.lanes["top"]
	var start := Util.polyline_at(lane, Util.polyline_length(lane) * 0.3)
	var out := PackedByteArray()
	out.resize(cols * rows)
	var stack: Array = [int(start.x / STEP) + int(start.y / STEP) * cols]
	out[stack[0]] = 1
	while not stack.is_empty():
		var c: int = stack.pop_back()
		var cx := c % cols
		var cy := c / cols
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var n := nx + ny * cols
			if out[n] == 0 and free[n] == 1:
				out[n] = 1
				stack.append(n)
	return out


## One nook's numbers, or {} when the spot is not a nook.
func _nook(at: Vector2, half: Vector2, cell: float, reach: PackedByteArray) -> Dictionary:
	var lane := INF
	for id: String in world.map.lanes:
		lane = minf(lane, _line_dist(at, world.map.lanes[id]) - float(world.map.lane_half[id]))
	var node := INF
	for nd: Dictionary in world.map.nodes:
		node = minf(node, at.distance_to(nd["pos"]))
	var camp := INF
	for c: Dictionary in world.map.camps:
		camp = minf(camp, at.distance_to(c["pos"]))
	var base := INF
	for mp: Vector2 in world.map.mothership_pos:
		base = minf(base, at.distance_to(mp))
	var cloud := INF
	for p: Dictionary in MapCover.patches():
		cloud = minf(cloud, at.distance_to(p["pos"]))
	if lane < LANE_GAP or node < 1100.0 or camp < 1000.0 or base < BASE_GAP or cloud < CLOUD_GAP:
		return {}
	# The room: nearly all open, and the middle must be reachable.
	var cols := int(ceil(MapLayout.W / STEP))
	if reach[int(at.x / STEP) + int(at.y / STEP) * cols] == 0:
		return {}
	var total := 0
	var open := 0
	for cy in range(int((at.y - half.y) / cell), int((at.y + half.y) / cell) + 1):
		for cx in range(int((at.x - half.x) / cell), int((at.x + half.x) / cell) + 1):
			var c := Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)
			var dx := (c.x - at.x) / half.x
			var dy := (c.y - at.y) / half.y
			if dx * dx + dy * dy > 1.0:
				continue
			total += 1
			if not world.asteroids.blocked(c, 40.0):
				open += 1
	if total == 0 or float(open) / float(total) < 0.9:
		return {}
	# The ring: 24 samples round the room, 700 to 1,000 out, how many are rock.
	var rock := 0
	var samples := 0
	for r in [700.0, 850.0, 1000.0]:
		for k in 8:
			samples += 1
			if world.asteroids.blocked(at + Vector2.from_angle(float(k) * TAU / 8.0 + r * 0.001) * r, 30.0):
				rock += 1
	var ring := float(rock) / float(samples)
	if ring < float(Game.opt("ring", MIN_RING)):
		return {}
	return {"pos": at, "open": float(open) / float(total), "ring": ring, "cloud": cloud, "node": node, "camp": camp, "lane": lane}
