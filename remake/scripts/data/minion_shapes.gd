class_name MinionShapes
extends RefCounted
## WHAT THIS IS: the Aurelian (amber) pictures of the three lane minions: the
## Snub-Fighter (type "fighter", drawn as the Anvil), the Light Bomber ("bomber",
## the Ingot) and the Patrol Leader ("corvette", the Outrider). They are pictures
## only: hit circles, sizes and every number stay as they are in minions.gd, and
## the match plays exactly as before.
##
## HOW IT WORKS: a minion's picture is an outline plus a list of marks. The
## outline (AURELIAN) is a list of corner points, nose pointing right (+x) and +y
## the minion's right side, about one unit long and wide: UnitVisual scales it by
## the minion's size. The marks (AURELIAN_MARKS) are flat paint on the plate,
## listed in the order they are drawn. A minion is meant to read as the basic kind
## of ship and never to be mistaken for a pilot ship (ShipVisual.HULLS), so:
##   - each outline is one plain plate with a flat tail: no notch, no swept
##     wings, no point on the tail. It has 3 to 6 corners (the Snub-Fighter's
##     stepped plate has 8: MAX_CORNERS). A pilot hull is a dart or a hexagon
##     with a notched or pointed tail;
##   - UnitVisual fills it solid, with the team colour mixed into the Aurelian
##     hull steel (FILL_MIX), where a pilot ship is a dark hull seen through its
##     outline, and draws the outline a little bolder (EDGE_PX);
##   - the marks are paint inside the plate: a lighter deck, a dark engine block,
##     an amber stripe, nozzle glows, a seam and, on the Patrol Leader, a gun
##     socket. They never change the silhouette, and UnitVisual leaves them out
##     while one drawing unit is under MARKS_MIN_UNIT_PX screen pixels long. The
##     only parts outside a plate are the Patrol Leader's two engine pods ("pod"
##     marks, always drawn, under the plate); they end exactly on the tail line,
##     so the stern is still flat;
##   - the Vhorr (Cinder) minions follow the same rule in their own alien style
##     (CinderShapes.MINIONS): smooth, soft shells with one engine light, no
##     horns, claws or plates, and a solid body colour.
## When the pilot ships are redrawn, keep their noses pointed and their tails
## notched or pointed, and leave these outlines as they are:
## tests/lib/gallery_checks.gd checks the corner count and the flat tail of each,
## that every mark lies on its plate or pod, and that every pod is flush with the
## tail.
##
## The solid parts of a picture (the pods, the plate's fill and the marks) never
## change from frame to frame, so they are built once, as a mesh of triangles in
## unit space with a colour on every corner, for each minion type and team colour
## (mesh()): UnitVisual draws a whole part with one command, turned and scaled to
## the minion. Only what depends on the screen is drawn line by line each frame:
## the outlines and the one-pixel seam (outline_closed(), pod_outlines(),
## line_marks() give their points in unit space).
##
## WHO USES IT: UnitVisual draws them for a minion of the Aurelian team (and of
## either team inside the hull gallery's plain look); the hull gallery
## (tests/hull_gallery.gd, tests/lib/gallery_checks.gd) sizes its pictures by
## their footprint and checks the Cinder shells against it.

## The outlines: minion type id -> corner points (nose right, unit space). The
## Snub-Fighter (the Anvil) is a stepped plate: a narrow nose block and a wide
## stern block, the step square on each flank. The Light Bomber (the Ingot) is a
## squat box with its nose corners cut off. The Patrol Leader (the Outrider) is a
## plain five-corner plate with a pointed nose and square shoulders.
const AURELIAN := {
	"fighter": [Vector2(1.0, 0.26), Vector2(0.1, 0.26), Vector2(0.1, 0.55), Vector2(-0.6, 0.55), Vector2(-0.6, -0.55), Vector2(0.1, -0.55), Vector2(0.1, -0.26), Vector2(1.0, -0.26)],
	"bomber": [Vector2(0.95, 0.28), Vector2(0.6, 0.5), Vector2(-0.8, 0.5), Vector2(-0.8, -0.5), Vector2(0.6, -0.5), Vector2(0.95, -0.28)],
	"corvette": [Vector2(1, 0), Vector2(0.1, 0.4), Vector2(-0.9, 0.38), Vector2(-0.9, -0.38), Vector2(0.1, -0.4)],
}
## The most corners a plate may have, by minion type id. A type that is not
## listed may have DEFAULT_MAX_CORNERS (the gallery check reads max_corners()).
const MAX_CORNERS := {"fighter": 8}
## The corner limit of a plate whose type is not in MAX_CORNERS.
const DEFAULT_MAX_CORNERS := 6
## The marks: minion type id -> a list of marks, in the order they are drawn (the
## "pod" marks first, under the plate's fill; every other mark after the fill and
## before the outline). A mark is a Dictionary with "kind" and either "pts" (the
## corners of a polygon, or the two ends of a "line") or "at" (a centre) and "r"
## (a radius) for a disc, in the same unit space as AURELIAN. The kinds and their
## colours (see mark_color()): pod (a polygon outside the plate, flush with its
## tail: dark steel with a thin outline of its own), plate (a lighter deck), dark
## (dark engine steel), stripe (the team colour), barrel (a gun barrel), line (a
## one-pixel seam), glow (a disc: a warm nozzle light), nozzle (a disc: a steel
## ring round a warm light), socket (a disc: the base of a gun mount), cap (a
## disc: the cap of a gun mount, drawn after its barrel). Both sides of a minion
## are written out; nothing is mirrored by code. A "line" is drawn on its own
## after the mesh that holds the other marks (its width is one screen pixel), so
## list it last.
const AURELIAN_MARKS := {
	# Anvil: a lighter deck down the nose block, a dark nacelle with a glow on each
	# side of the stern block, one amber stripe across the nose block.
	"fighter": [
		{"kind": "plate", "pts": [Vector2(0.85, 0.16), Vector2(-0.45, 0.16), Vector2(-0.45, -0.16), Vector2(0.85, -0.16)]},
		{"kind": "dark", "pts": [Vector2(0.1, 0.3), Vector2(0.1, 0.55), Vector2(-0.6, 0.55), Vector2(-0.6, 0.3)]},
		{"kind": "dark", "pts": [Vector2(0.1, -0.3), Vector2(0.1, -0.55), Vector2(-0.6, -0.55), Vector2(-0.6, -0.3)]},
		{"kind": "stripe", "pts": [Vector2(0.74, 0.26), Vector2(0.64, 0.26), Vector2(0.64, -0.26), Vector2(0.74, -0.26)]},
		{"kind": "glow", "at": Vector2(-0.5, 0.425), "r": 0.09},
		{"kind": "glow", "at": Vector2(-0.5, -0.425), "r": 0.09},
	],
	# Ingot: two lighter decks, a dark engine block across the tail, a dark torpedo
	# tube down the middle with an amber warhead tip, two nozzle glows, one seam where
	# the nose cap starts.
	"bomber": [
		{"kind": "plate", "pts": [Vector2(0.5, 0.42), Vector2(-0.58, 0.42), Vector2(-0.58, 0.17), Vector2(0.5, 0.17)]},
		{"kind": "plate", "pts": [Vector2(0.5, -0.42), Vector2(-0.58, -0.42), Vector2(-0.58, -0.17), Vector2(0.5, -0.17)]},
		{"kind": "dark", "pts": [Vector2(-0.64, 0.42), Vector2(-0.8, 0.42), Vector2(-0.8, -0.42), Vector2(-0.64, -0.42)]},
		{"kind": "dark", "pts": [Vector2(0.9, 0.1), Vector2(0.9, -0.1), Vector2(-0.15, -0.1), Vector2(-0.15, 0.1)]},
		{"kind": "stripe", "pts": [Vector2(0.9, 0.08), Vector2(0.9, -0.08), Vector2(0.8, -0.08), Vector2(0.8, 0.08)]},
		{"kind": "glow", "at": Vector2(-0.73, 0.22), "r": 0.07},
		{"kind": "glow", "at": Vector2(-0.73, -0.22), "r": 0.07},
		{"kind": "line", "pts": [Vector2(0.6, 0.48), Vector2(0.6, -0.48)]},
	],
	# Outrider: two engine pods outside the plate (drawn under it, flush with its tail
	# at x = -0.9), a lighter deck, a nozzle and an amber tip on each pod, amber
	# chevrons on the shoulders, a gun socket with its barrel and cap, one seam.
	"corvette": [
		{"kind": "pod", "pts": [Vector2(-0.22, 0.39), Vector2(-0.32, 0.58), Vector2(-0.9, 0.58), Vector2(-0.9, 0.39)]},
		{"kind": "pod", "pts": [Vector2(-0.22, -0.39), Vector2(-0.32, -0.58), Vector2(-0.9, -0.58), Vector2(-0.9, -0.39)]},
		{"kind": "plate", "pts": [Vector2(0.45, 0), Vector2(0.05, 0.24), Vector2(-0.72, 0.24), Vector2(-0.72, -0.24), Vector2(0.05, -0.24)]},
		{"kind": "nozzle", "at": Vector2(-0.82, 0.485), "r": 0.075},
		{"kind": "nozzle", "at": Vector2(-0.82, -0.485), "r": 0.075},
		{"kind": "stripe", "pts": [Vector2(-0.26, 0.41), Vector2(-0.34, 0.56), Vector2(-0.4, 0.56), Vector2(-0.32, 0.41)]},
		{"kind": "stripe", "pts": [Vector2(-0.26, -0.41), Vector2(-0.34, -0.56), Vector2(-0.4, -0.56), Vector2(-0.32, -0.41)]},
		{"kind": "stripe", "pts": [Vector2(0.16, 0.34), Vector2(0.08, 0.34), Vector2(0, 0.22), Vector2(0.08, 0.22)]},
		{"kind": "stripe", "pts": [Vector2(0.16, -0.34), Vector2(0.08, -0.34), Vector2(0, -0.22), Vector2(0.08, -0.22)]},
		{"kind": "socket", "at": Vector2(-0.1, 0), "r": 0.15},
		{"kind": "barrel", "pts": [Vector2(-0.1, -0.03), Vector2(0.24, -0.03), Vector2(0.24, 0.03), Vector2(-0.1, 0.03)]},
		{"kind": "cap", "at": Vector2(-0.1, 0), "r": 0.085},
		{"kind": "line", "pts": [Vector2(-0.72, -0.24), Vector2(-0.72, 0.24)]},
	],
}
## How much of the team colour is mixed into the Aurelian hull steel for a
## minion's fill (and into a "plate" mark): 0 = the pilot ships' steel, 1 = the
## team colour itself.
const FILL_MIX := 0.32
## The width of a minion's outline in screen pixels (a pilot ship's is 1.4).
const EDGE_PX := 1.3
## The see-through amount of a "stripe" mark (1 = solid).
const STRIPE_ALPHA := 0.85
## The marks other than pods are drawn only while one drawing unit (the minion's
## size) is at least this many screen pixels long; under it they would be smaller
## than a pixel and only cost drawing work.
const MARKS_MIN_UNIT_PX := 10.0
## A pod's outline is EDGE_PX times this wide, and this see-through (1 = solid), so
## the plate's own outline stays the boldest line.
const POD_EDGE_MUL := 0.8
## The see-through amount of a pod's outline (1 = solid).
const POD_EDGE_ALPHA := 0.7
## The size of a "nozzle" mark's light disc as a share of its ring's radius.
const NOZZLE_LIGHT := 0.55
## How many corners a disc mark gets in a mesh (Godot's own draw_circle() uses 64).
const DISC_SEGMENTS := 64
## The part of a picture that mesh() builds for the pods: their fills (nothing for
## a minion with no pods).
const PART_PODS := "pods"
## The part of a picture that mesh() builds for the plate: its fill.
const PART_PLATE := "plate"
## The part of a picture that mesh() builds for the plate with its marks: the
## fill with every mark but the pods and the seam on top of it.
const PART_MARKED := "marked"

## The meshes built so far: minion type id -> team colour as a number -> part -> mesh.
static var _meshes := {}
## The closed outlines (first corner repeated) built so far: minion type id -> points.
static var _closed := {}
## The closed outlines of the pods built so far: minion type id -> list of points.
static var _pod_edges := {}
## The seam lines built so far: minion type id -> list of points.
static var _seams := {}


## The outline of minion type `type_id` ("fighter" for an unknown type).
static func aurelian(type_id: String) -> Array:
	return AURELIAN.get(type_id, AURELIAN["fighter"])


## The marks of minion type `type_id` (the Snub-Fighter's for an unknown type),
## in the order they are drawn.
static func marks(type_id: String) -> Array:
	return AURELIAN_MARKS.get(type_id, AURELIAN_MARKS["fighter"])


## The corners of everything solid in the picture of minion type `type_id`: the
## plate's corners and the corners of its pods. The hull gallery measures this, so
## a pod counts as part of the minion's length and width.
static func footprint(type_id: String) -> Array:
	var out: Array = aurelian(type_id).duplicate()
	for mark: Dictionary in marks(type_id):
		if mark["kind"] == "pod":
			out.append_array(mark["pts"])
	return out


## The most corners the plate of minion type `type_id` may have.
static func max_corners(type_id: String) -> int:
	return int(MAX_CORNERS.get(type_id, DEFAULT_MAX_CORNERS))


## The solid fill of a plate: the Aurelian hull steel with the team colour
## `team_col` mixed in by FILL_MIX.
static func plate_fill(team_col: Color) -> Color:
	return Palette.AUREL_HULL.lerp(team_col, FILL_MIX)


## The colour of a mark of kind `kind` for a minion of team colour `team_col`.
## (A "nozzle" is two discs, a ring and a light: mesh() builds both.)
static func mark_color(kind: String, team_col: Color) -> Color:
	match kind:
		"plate":
			return Palette.AUREL_PLATE.lerp(team_col, FILL_MIX)
		"stripe":
			return Palette.with_alpha(team_col, STRIPE_ALPHA)
		"glow":
			return Palette.AUREL_GLOW
		"socket":
			return Palette.TURRET_AUREL_BASE
		"cap":
			return Palette.TURRET_AUREL_CAP
		"barrel":
			return Palette.TURRET_AUREL_BARREL
		"line":
			return Palette.AUREL_SEAM
	return Palette.AUREL_SHADE

## The type id whose picture is used for `type_id`: itself, or "fighter" when the
## type is not in AURELIAN.
static func _known(type_id: String) -> String:
	return type_id if AURELIAN.has(type_id) else "fighter"


## The outline of minion type `type_id` as a closed line (its first corner repeated
## at the end), in unit space, ready for draw_polyline(). Built once per type.
static func outline_closed(type_id: String) -> PackedVector2Array:
	var t := _known(type_id)
	if not _closed.has(t):
		_closed[t] = _closed_line(AURELIAN[t])
	return _closed[t]


## The outlines of the pods of minion type `type_id`, a closed line each (as
## outline_closed()), in table order: an empty list for a minion with no pods.
static func pod_outlines(type_id: String) -> Array:
	var t := _known(type_id)
	if not _pod_edges.has(t):
		var lines: Array = []
		for mark: Dictionary in AURELIAN_MARKS[t]:
			if mark["kind"] == "pod":
				lines.append(_closed_line(mark["pts"]))
		_pod_edges[t] = lines
	return _pod_edges[t]


## The "line" marks (the seams) of minion type `type_id`: the two ends of each, in
## unit space, in table order.
static func line_marks(type_id: String) -> Array:
	var t := _known(type_id)
	if not _seams.has(t):
		var lines: Array = []
		for mark: Dictionary in AURELIAN_MARKS[t]:
			if mark["kind"] == "line":
				lines.append(PackedVector2Array(mark["pts"]))
		_seams[t] = lines
	return _seams[t]


## The solid part `part` (PART_PODS, PART_PLATE or PART_MARKED) of the picture of
## minion type `type_id` for team colour `team_col`, as a mesh in unit space with
## the colours in it, built the first time it is asked for and kept: draw it with
## draw_mesh() and a transform that turns and scales unit space to the minion. The
## triangles are in the order the shapes are drawn (the last on top), and every
## polygon is cut into triangles by Geometry2D.triangulate_polygon(), as
## draw_colored_polygon() does. Returns null for PART_PODS of a minion with no pods.
static func mesh(type_id: String, team_col: Color, part: String) -> ArrayMesh:
	var t := _known(type_id)
	if not _meshes.has(t):
		_meshes[t] = {}
	var by_colour: Dictionary = _meshes[t]
	var colour_key := team_col.to_rgba32()
	if not by_colour.has(colour_key):
		by_colour[colour_key] = {}
	var by_part: Dictionary = by_colour[colour_key]
	if not by_part.has(part):
		by_part[part] = _build_mesh(t, team_col, part)
	return by_part[part]


## Build the mesh of part `part` of the picture of the known type `t` (see mesh()).
static func _build_mesh(t: String, team_col: Color, part: String) -> ArrayMesh:
	var verts := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	if part == PART_PODS:
		for mark: Dictionary in AURELIAN_MARKS[t]:
			if mark["kind"] == "pod":
				_add_polygon(verts, colours, indices, mark["pts"], mark_color("pod", team_col))
	else:
		_add_polygon(verts, colours, indices, AURELIAN[t], plate_fill(team_col))
		if part == PART_MARKED:
			for mark: Dictionary in AURELIAN_MARKS[t]:
				var kind: String = mark["kind"]
				if kind == "pod" or kind == "line":
					continue
				if mark.has("at"):
					var at: Vector2 = mark["at"]
					var r := float(mark["r"])
					if kind == "nozzle":
						_add_disc(verts, colours, indices, at, r, Palette.AUREL_HULL)
						_add_disc(verts, colours, indices, at, r * NOZZLE_LIGHT, Palette.with_alpha(Palette.AUREL_GLOW, 0.9))
					else:
						_add_disc(verts, colours, indices, at, r, mark_color(kind, team_col))
				else:
					_add_polygon(verts, colours, indices, mark["pts"], mark_color(kind, team_col))
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


## The points `pts` as a closed line: the first point repeated at the end.
static func _closed_line(pts: Array) -> PackedVector2Array:
	var line := PackedVector2Array(pts)
	line.append(line[0])
	return line


## Add the polygon `pts` in colour `color` to the mesh arrays, cut into triangles.
static func _add_polygon(verts: PackedVector2Array, colours: PackedColorArray, indices: PackedInt32Array, pts: Array, color: Color) -> void:
	var poly := PackedVector2Array(pts)
	var base := verts.size()
	verts.append_array(poly)
	for _i in poly.size():
		colours.append(color)
	for corner: int in Geometry2D.triangulate_polygon(poly):
		indices.append(base + corner)


## Add a disc of radius `r` round `centre` in colour `color` to the mesh arrays, as
## a fan of DISC_SEGMENTS triangles.
static func _add_disc(verts: PackedVector2Array, colours: PackedColorArray, indices: PackedInt32Array, centre: Vector2, r: float, color: Color) -> void:
	var base := verts.size()
	verts.append(centre)
	colours.append(color)
	for i in DISC_SEGMENTS:
		verts.append(centre + Vector2.from_angle(TAU * float(i) / float(DISC_SEGMENTS)) * r)
		colours.append(color)
	for i in DISC_SEGMENTS:
		indices.append(base)
		indices.append(base + 1 + i)
		indices.append(base + 1 + (i + 1) % DISC_SEGMENTS)
