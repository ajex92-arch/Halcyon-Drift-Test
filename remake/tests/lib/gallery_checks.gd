class_name GalleryChecks
extends RefCounted
## WHAT THIS IS: the shape checks of the hull gallery (tests/hull_gallery.gd).
## They test the Cinder shape tables (CinderShapes) and the Aurelian minion
## outlines and marks (MinionShapes) without drawing anything, so a bad table is caught by
## a pass/fail run (hull_gallery --check) and not by someone looking at a
## picture.
##
## HOW IT WORKS: run() makes four checks and prints a summary line for each
## (and a "FAIL ..." line for every shape that fails):
##   - every polygon can be filled: Godot cuts a polygon into triangles to
##     fill it, and cannot for one that crosses itself;
##   - the shape's outline is within 10% of the length and width of the
##     Aurelian shape it replaces, so hits and ranges read the same (the lane
##     minions' Cinder shells against the Aurelian MinionShapes footprints: the
##     plate and, for the Patrol Leader, its engine pods);
##   - the Aurelian minion outlines stay plain: at most MinionShapes.max_corners()
##     corners (6; 8 for the Snub-Fighter's stepped plate) and a flat tail (two
##     corners at the back, none on the middle line), unlike a pilot hull's
##     notched or pointed tail, which keeps a minion from looking like one;
##   - the Aurelian minions' marks stay on the picture: every mark lies on its
##     plate or on one of its pods (within MARK_SLACK of an edge counts), and
##     every pod is flush with the tail (two corners on the plate's back line,
##     none behind it, none on the middle line).
##
## WHO USES IT: tests/hull_gallery.gd calls run() at the start of every run
## (with --check that is the whole run), and box() to size its pictures.


## How far (in unit space) a mark's point may sit outside its plate or pod and
## still count as on it: a mark that runs to an edge of the plate ends exactly on
## that edge, and an exact inside test of such a point is not reliable.
const MARK_SLACK := 0.02


## Run the four checks and print the results; returns the number of failures.
static func run() -> int:
	var bad := 0
	var total := 0
	# Step 1: every polygon of every shape can be cut into triangles.
	var tables := {"hull": CinderShapes.HULLS, "minion": CinderShapes.MINIONS, "unit": CinderShapes.UNITS, "mothership": {"citadel": CinderShapes.MOTHERSHIP}}
	for kind: String in tables:
		for id: String in tables[kind]:
			var raw: Dictionary = tables[kind][id]
			var polys := {"outline": raw["sil"]}
			for i in (raw["parts"] as Array).size():
				polys["plate %d" % i] = raw["parts"][i]["pts"]
			for label: String in polys:
				total += 1
				if Geometry2D.triangulate_polygon(PackedVector2Array(polys[label])).is_empty():
					bad += 1
					print("FAIL polygon %s %s %s" % [kind, id, label])
	print("cinder polygons: %d checked, %d cannot be filled" % [total, bad])
	# Step 2: the size of each outline against the Aurelian shape it replaces:
	# length and half-width within 10% (for a minion, the plate and its pods).
	var pairs: Array = []
	for hid: String in Ships.ORDER:
		pairs.append([hid, CinderShapes.HULLS[hid]["sil"], ShipVisual.HULLS[hid]])
	for mt: String in Minions.TYPES:
		pairs.append(["minion " + mt, CinderShapes.MINIONS[mt]["sil"], MinionShapes.footprint(mt)])
	pairs.append(["mining drone", CinderShapes.UNITS["mining_drone"]["sil"], UnitVisual.DRONE])
	# The small units whose Aurelian look is a plain box, diamond or plus sign.
	pairs.append(["pd turret", CinderShapes.UNITS["pd"]["sil"], [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]])
	pairs.append(["torpedo turret", CinderShapes.UNITS["torp"]["sil"], [Vector2(1.2, 0), Vector2(0, 1.2), Vector2(-1.2, 0), Vector2(0, -1.2)]])
	pairs.append(["repair bay", CinderShapes.UNITS["repair_bay"]["sil"], [Vector2(-1, -0.7), Vector2(1, -0.7), Vector2(1, 0.7), Vector2(-1, 0.7)]])
	pairs.append(["ward", CinderShapes.UNITS["ward"]["sil"], [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]])
	pairs.append(["repair drone", CinderShapes.UNITS["repair_drone"]["sil"], [Vector2(-1, -0.2), Vector2(1, -0.2), Vector2(1, 0.2), Vector2(-1, 0.2), Vector2(-0.2, -1), Vector2(0.2, 1)]])
	pairs.append(["mothership", CinderShapes.MOTHERSHIP["sil"], _stretched(UnitVisual.MOTHER + UnitVisual.MOTHER_ENGINE)])
	var off := 0
	for pr: Array in pairs:
		var mine := box(pr[1])
		var theirs := box(pr[2])
		if absf(mine.x / theirs.x - 1.0) > 0.1 or absf(mine.y / theirs.y - 1.0) > 0.1:
			off += 1
			print("FAIL size %s: length %.2f vs %.2f, width %.2f vs %.2f" % [pr[0], mine.x, theirs.x, mine.y, theirs.y])
	print("cinder sizes: %d shapes checked, %d outside 10%% of the Aurelian shape" % [pairs.size(), off])
	# Step 3: the Aurelian minion outlines are plain: at most max_corners() corners
	# (6, or 8 for the Snub-Fighter) and a flat tail (two corners at the back, and
	# none of them on the middle line).
	var not_plain := 0
	for mt: String in MinionShapes.AURELIAN:
		var pts: Array = MinionShapes.AURELIAN[mt]
		var back := INF
		for p: Vector2 in pts:
			back = minf(back, p.x)
		var at_back := 0
		var on_axis := false
		for p: Vector2 in pts:
			if is_equal_approx(p.x, back):
				at_back += 1
				on_axis = on_axis or is_zero_approx(p.y)
		var plain := pts.size() <= MinionShapes.max_corners(mt) and at_back == 2 and not on_axis and not Geometry2D.triangulate_polygon(PackedVector2Array(pts)).is_empty()
		if not plain:
			not_plain += 1
			print("FAIL plain minion %s: %d corners, %d at the back%s" % [mt, pts.size(), at_back, ", one on the middle line" if on_axis else ""])
	print("minion looks: %d outlines checked, %d not plain" % [MinionShapes.AURELIAN.size(), not_plain])
	# Step 4: the marks stay on the picture (every point of a mark lies on the plate
	# or on a pod), and every pod is flush with the tail: two corners on the plate's
	# back line, none behind it, none on the middle line.
	var mark_count := 0
	var bad_marks := 0
	for mt: String in MinionShapes.AURELIAN_MARKS:
		var plate: Array = MinionShapes.AURELIAN[mt]
		var back_x := INF
		for p: Vector2 in plate:
			back_x = minf(back_x, p.x)
		var areas: Array = [plate]
		for mark: Dictionary in MinionShapes.AURELIAN_MARKS[mt]:
			if mark["kind"] == "pod":
				areas.append(mark["pts"])
		for mark: Dictionary in MinionShapes.AURELIAN_MARKS[mt]:
			mark_count += 1
			var kind: String = mark["kind"]
			var ok := true
			if kind == "pod":
				var pod_pts: Array = mark["pts"]
				var at_tail := 0
				for p: Vector2 in pod_pts:
					if is_equal_approx(p.x, back_x):
						at_tail += 1
					if p.x < back_x - 0.001 or is_zero_approx(p.y):
						ok = false
				ok = ok and at_tail == 2
			else:
				for p: Vector2 in _mark_points(mark):
					if not _on_areas(p, areas):
						ok = false
			if not ok:
				bad_marks += 1
				print("FAIL minion mark %s %s" % [mt, kind])
	print("minion marks: %d marks checked, %d outside the plate" % [mark_count, bad_marks])
	return bad + off + not_plain + bad_marks


## The length and width of a shape given as a list of points (its width is
## twice its widest reach from the middle line).
static func box(pts: Array) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	return Vector2(hi.x - lo.x, maxf(absf(lo.y), absf(hi.y)) * 2.0)


## The points of a mark that must lie on the picture: its corners, or, for a disc,
## its centre and the four points `r` away from it along the axes.
static func _mark_points(mark: Dictionary) -> Array:
	if not mark.has("at"):
		return mark["pts"]
	var c: Vector2 = mark["at"]
	var r: float = mark["r"]
	return [c, c + Vector2(r, 0), c - Vector2(r, 0), c + Vector2(0, r), c - Vector2(0, r)]


## True when point `p` is inside one of the polygons in `areas` or within
## MARK_SLACK of one of their edges.
static func _on_areas(p: Vector2, areas: Array) -> bool:
	for poly: Array in areas:
		var pv := PackedVector2Array(poly)
		if Geometry2D.is_point_in_polygon(p, pv):
			return true
		for i in pv.size():
			var q := Geometry2D.get_closest_point_to_segment(p, pv[i], pv[(i + 1) % pv.size()])
			if p.distance_to(q) <= MARK_SLACK:
				return true
	return false


## The Aurelian mothership outline stretched to the real 1600 x 340 ship
## (UnitVisual stretches it from its 510 x 140 drawing the same way).
static func _stretched(pts: Array) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append(Vector2(p.x * float(Structures.MOTHERSHIP["length"]) / 510.0, p.y * float(Structures.MOTHERSHIP["beam"]) / 140.0))
	return out
