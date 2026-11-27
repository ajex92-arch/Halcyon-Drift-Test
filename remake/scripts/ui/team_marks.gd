class_name TeamMarks
extends RefCounted
## WHAT THIS IS: the team marks (T-126, Set 1, "Disc and Wedge"): a second sign of the team beside its colour, so the
## two teams differ in shape as well as hue. Aurelian (team 0, amber) is a round dot; Vhorr (team 1, red) is a small
## wedge, a triangle that points DOWN (never upright: the upright triangle is the danger sign, Glyphs.danger).
## It only draws: it changes nothing in the match, uses no random numbers and makes no particles.
##
## HOW IT WORKS: every shape comes from its corners (wedge(), tooth(), shape_points()), so a test can measure it.
## `size` is the width of the disc (its diameter); the wedge is 1.2 x size wide and 1.04 x size tall, centred on its
## box. `unit` multiplies every length here (sizes, the dark rim, the hollow line): 1.0 on a screen or on the minimap's
## 300-pixel picture, and the world's px (world units per screen pixel) for a mark drawn in the world, so it keeps its
## size on the screen at any zoom. Three drawing entries:
##   mark()   the mark over a dark VOID shape of the same kind with a 1.1 px rim all round (the disc 2.2 px larger across; the
##            wedge grown outward by 1.1 px on every side, wedge_rim()): 2 calls.
##   icon()   a map icon of a base shape (disc, square, diamond): solid for Aurelian, hollow for Vhorr (a 1.4 px line
##            in the team colour round a VOID core at 0.9, the line's outer edge being the icon's edge): 1 or 2 calls.
##   teeth()  isosceles triangles that stand on a ring's outer edge and point outward, Vhorr's cue on a ring.
## fill() is the mark without the rim (small minimap marks, which have no outline).
##
## WHO USES IT: Minimap, SiteMarks (rings), the hull bars of UnitVisual and ShipVisual, HudFeed (a mark before a team
## name), Scoreboard (before a heading); tests/team_marks_check.gd measures the shapes.

## A mark as a Control, so a row of a screen can hold it like a label (the kill feed's team names, the scoreboard's headings):
## the mark's own width wide (`mark_size` for the disc, 1.2 x that for the wedge: TeamMarks.mark_width()), with room to its
## left for the dark rim (TeamMarks.rim_left(), so nothing pokes out left), then a 4 px gap to what follows, as tall as the
## text line it stands in (`line_h`), the mark centred on that line's middle. The mouse passes through it.
class View extends Control:
	## The gap between the mark and the text after it (pixels).
	const GAP := 4.0
	var team := 0
	var mark_size := 10.0
	## The room left of the mark for its dark rim (pixels).
	var _pad := 0.0

	func _init(for_team: int, size_px: float, line_h: float) -> void:
		team = for_team
		mark_size = size_px
		_pad = TeamMarks.rim_left(team, size_px)
		custom_minimum_size = Vector2(_pad + TeamMarks.mark_width(team, size_px) + GAP, line_h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		TeamMarks.mark(self, Vector2(_pad + TeamMarks.mark_width(team, mark_size) * 0.5, size.y * 0.5), mark_size, team)


## The base shapes of icon().
const DISC := 0
const SQUARE := 1
const DIAMOND := 2

## How much larger across the dark shape under a mark is (pixels): a rim of half of it on every side.
const GROW := 2.2
## The line of a hollow icon (pixels) and the see-through amount of its VOID core.
const HOLLOW_LINE := 1.4
const HOLLOW_CORE_ALPHA := 0.9
## The wedge's half-width and half-height, as multiples of the disc's size.
const WEDGE_HALF_W := 0.6
const WEDGE_HALF_H := 0.52


## Does team `team` get the wedge (Vhorr)? Anything else gets the disc.
static func is_wedge(team: int) -> bool:
	return team == Rules.CINDER


## How wide the mark of `team` is when its disc is `size` across: `size` for the disc, 1.2 x that for the wedge.
static func mark_width(team: int, size: float) -> float:
	return WEDGE_HALF_W * 2.0 * size if is_wedge(team) else size


## How far the dark rim of the mark of `team` reaches left of the mark's own left edge (pixels): half of GROW for the disc;
## for the wedge what wedge_rim() measures at the corner.
static func rim_left(team: int, size: float) -> float:
	if not is_wedge(team):
		return GROW * 0.5
	var least := 0.0
	for p: Vector2 in wedge_rim(Vector2.ZERO, size, GROW * 0.5):
		least = minf(least, p.x)
	return -WEDGE_HALF_W * size - least


## The dark rim of the wedge: the wedge of `size` at `centre` grown outward by `rim` pixels on every side
## (Geometry2D.offset_polygon, mitred corners), so the slanted sides keep the full rim too. Falls back to the scaled
## wedge if the engine returns nothing.
static func wedge_rim(centre: Vector2, size: float, rim: float) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(wedge(centre, size), rim, Geometry2D.JOIN_MITER)
	if grown.is_empty() or (grown[0] as PackedVector2Array).size() < 3:
		return wedge(centre, size + 2.0 * rim)
	return grown[0]


## The three corners of the wedge of `size` centred at `centre`: the two top corners (left, then right), then the
## point at the bottom. It points down.
static func wedge(centre: Vector2, size: float) -> PackedVector2Array:
	return PackedVector2Array([
		centre + Vector2(-WEDGE_HALF_W * size, -WEDGE_HALF_H * size),
		centre + Vector2(WEDGE_HALF_W * size, -WEDGE_HALF_H * size),
		centre + Vector2(0.0, WEDGE_HALF_H * size),
	])


## The corners of a square (side `size`) or a diamond (corner to corner `size`) centred at `centre`: the square top
## left, top right, bottom right, bottom left; the diamond top, right, bottom, left.
static func shape_points(base: int, centre: Vector2, size: float) -> PackedVector2Array:
	var h := size * 0.5
	if base == DIAMOND:
		return PackedVector2Array([centre + Vector2(0.0, -h), centre + Vector2(h, 0.0), centre + Vector2(0.0, h), centre + Vector2(-h, 0.0)])
	return PackedVector2Array([centre + Vector2(-h, -h), centre + Vector2(h, -h), centre + Vector2(h, h), centre + Vector2(-h, h)])


## The corners of one tooth: an isosceles triangle whose base (`base` long) lies on the tangent at angle `angle`
## (radians, 0 = right, y down) of the circle of radius `r_out` round `centre`, and whose point is `length` further
## out on the same ray: base left, base right, point.
static func tooth(centre: Vector2, r_out: float, angle: float, base: float, length: float) -> PackedVector2Array:
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal()
	var foot := centre + dir * r_out
	return PackedVector2Array([foot - side * base * 0.5, foot + side * base * 0.5, foot + dir * length])


## `count` angles (radians) round a circle, `first` for the first, evenly spaced.
static func ring_angles(count: int, first: float) -> Array[float]:
	var out: Array[float] = []
	for i in count:
		out.append(first + TAU * float(i) / float(count))
	return out


## The mark of `team` at `centre`, `size` wide, in `col` (null: the team's colour), with no rim: a disc or a wedge.
static func fill(ci: CanvasItem, centre: Vector2, size: float, team: int, col: Variant = null, unit: float = 1.0) -> void:
	var c: Color = Palette.team(team) if col == null else col
	if is_wedge(team):
		ci.draw_colored_polygon(wedge(centre, size * unit), c)
	else:
		ci.draw_circle(centre, size * unit * 0.5, c)


## The mark of `team` at `centre`, `size` wide, over a VOID shape of the same kind with a 1.1 px rim (2 calls).
## `col` null: the team's colour. `unit` multiplies size and rim (see HOW IT WORKS).
static func mark(ci: CanvasItem, centre: Vector2, size: float, team: int, unit: float = 1.0, col: Variant = null) -> void:
	var c: Color = Palette.team(team) if col == null else col
	var big := (size + GROW) * unit
	if is_wedge(team):
		ci.draw_colored_polygon(wedge_rim(centre, size * unit, GROW * 0.5 * unit), Palette.VOID)
		ci.draw_colored_polygon(wedge(centre, size * unit), c)
	else:
		ci.draw_circle(centre, big * 0.5, Palette.VOID)
		ci.draw_circle(centre, size * unit * 0.5, c)


## A map icon of base shape `base` (DISC, SQUARE or DIAMOND) at `centre`, `size` across, in `col` (null: the team's
## colour). Vhorr's is hollow: the shape in the team colour, then a VOID core at 0.9 inside it, a 1.4 px line left (2
## calls). Anyone else's is solid, with a 1 px VOID edge when `edge` is true (1 or 2 calls).
static func icon(ci: CanvasItem, base: int, centre: Vector2, size: float, team: int, unit: float = 1.0, edge: bool = false, col: Variant = null) -> void:
	var c: Color = Palette.team(team) if col == null else col
	var s := size * unit
	_shape(ci, base, centre, s, c)
	if is_wedge(team):
		var line := HOLLOW_LINE * unit
		# The line is measured square on to the edge: a diamond's corner is further in by the root of two.
		var inset := line * (sqrt(2.0) if base == DIAMOND else 1.0)
		var core := maxf(0.0, s - 2.0 * inset)
		if core > 0.0:
			_shape(ci, base, centre, core, Palette.with_alpha(Palette.VOID, HOLLOW_CORE_ALPHA))
	elif edge:
		_outline(ci, base, centre, s, Palette.VOID, unit)


## Vhorr's teeth on a ring: for each angle in `angles` (radians) one tooth (tooth()) standing on the circle of radius
## `r_out` (the ring's OUTER edge) round `centre`, `base` wide and `length` long, in `col`. `unit` multiplies base and length.
static func teeth(ci: CanvasItem, centre: Vector2, r_out: float, angles: Array[float], base: float, length: float, col: Color, unit: float = 1.0) -> void:
	for a in angles:
		ci.draw_colored_polygon(tooth(centre, r_out, a, base * unit, length * unit), col)


## Fill a base shape of `s` across.
static func _shape(ci: CanvasItem, base: int, centre: Vector2, s: float, c: Color) -> void:
	if base == DISC:
		ci.draw_circle(centre, s * 0.5, c)
	else:
		ci.draw_colored_polygon(shape_points(base, centre, s), c)


## Outline a base shape of `s` across, `unit` wide, drawn inside its edge.
static func _outline(ci: CanvasItem, base: int, centre: Vector2, s: float, c: Color, unit: float) -> void:
	if base == DISC:
		ci.draw_arc(centre, maxf(0.0, s * 0.5 - unit * 0.5), 0.0, TAU, 16, c, unit, true)
		return
	var inner := maxf(0.0, s - unit * (sqrt(2.0) if base == DIAMOND else 1.0))
	var pts := shape_points(base, centre, inner)
	pts.append(pts[0])
	ci.draw_polyline(pts, c, unit, true)
