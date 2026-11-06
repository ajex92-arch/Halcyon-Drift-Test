class_name ShieldArcs
extends RefCounted
## WHAT THIS IS: the painter of the four shield arcs round a pilot ship (front,
## rear, left, right), and the small helper that says when they must be drawn
## again. It only draws; it changes nothing in the game.
##
## HOW IT WORKS:
##   - ShipVisual draws the arcs on a kept picture (DrawCache) that turns with the
##     ship, so every arc is drawn with the ship pointing along +x (front = angle 0,
##     rear = PI, left = -PI/2, right = PI/2). key() turns the four shield values into
##     one number that changes when an arc must look different (a zone's fill moved by
##     a thirty-second, a zone gone, the hit flash of the arcs started or ended), so
##     the picture is drawn again only then.
##   - Close up (the camera zoom at or above DrawCache.CLOSE_ZOOM) every arc is a smooth,
##     antialiased arc of 12 segments, one drawing command each (draw_full()).
##   - Far away and at the usual play zoom (below DrawCache.CLOSE_ZOOM) an arc is only a few
##     screen pixels long, so all four arcs together are drawn as ONE command
##     (draw_simple()): the same arcs (the same ring, the same angles, brightness and
##     thickness), each with only as many segments as its length on the screen needs
##     (3 to 8 instead of 12), and a soft edge made by fading the arc's two sides to
##     nothing in a fraction of a pixel (instead of the separate antialiasing commands).
##
## WHO USES IT: ShipVisual (the "Shield" picture of every pilot ship).

## Where each zone's arc is centred, in radians from the ship's nose, in the order
## front, rear, left, right (Rules.ZONE_FRONT .. ZONE_RIGHT).
const CENTERS := [0.0, PI, -PI / 2.0, PI / 2.0]
## How far each arc reaches to each side of its centre, in radians.
const HALF_SPAN := 0.7
## How many screen pixels long a segment of a simple arc is, about.
const SIMPLE_SEGMENT_PX := 6.0
## How wide, in screen pixels, the soft edge of a simple arc is on each side.
const SOFT_PX := 0.8
## A zone's arc is brighter for this many seconds after the shield was hit.
const HIT_GLOW_SECS := 0.25


## One number that changes when the arcs must look different (caps are the sizes of the
## four zones, ShieldZones.cap()): for each zone, its
## fill in thirty-seconds (0 for no zone), six bits each, then a bit for the hit
## glow, then (bit 25) whether this is the simple or the full look at zoom `z`.
static func key(sh: ShieldZones, caps: PackedFloat32Array, z: float) -> int:
	var bits := 0
	for zone in 4:
		var cap := caps[zone]
		if cap > 0.0:
			bits |= (1 + int(clampf(sh.values[zone] / cap, 0.0, 1.0) * 32.0)) << (zone * 6)
	if sh.since_hit < HIT_GLOW_SECS:
		bits |= 1 << 24
	if not DrawCache.is_close(z):
		bits |= 1 << 25
	return bits


## Draw the four arcs of shield `sh` on `ci`, on a ring of radius `sr` round the
## origin, with the ship pointing along +x (`px` is world units per screen pixel,
## `z` the camera zoom): the full look close up, the simple look further out.
static func draw(ci: CanvasItem, sh: ShieldZones, sr: float, px: float, z: float) -> void:
	if not DrawCache.is_close(z):
		draw_simple(ci, sh, sr, px)
	else:
		draw_full(ci, sh, sr, px)


## How bright a zone with fill `frac` (0..1) is: dim when empty, brighter when full,
## extra bright just after a hit.
static func _alpha(sh: ShieldZones, frac: float) -> float:
	var a := 0.12 + 0.45 * frac
	if sh.since_hit < HIT_GLOW_SECS:
		a += 0.35
	return a


## The full look: one smooth, antialiased 12-segment arc for each zone that has a
## share and some shield left, brighter and thicker when fuller, hidden when empty.
static func draw_full(ci: CanvasItem, sh: ShieldZones, sr: float, px: float) -> void:
	for zone in 4:
		var cap := sh.cap(zone)
		if cap <= 0.0:
			continue
		var frac := sh.values[zone] / cap
		if frac <= 0.01:
			continue
		var centre: float = CENTERS[zone]
		ci.draw_arc(Vector2.ZERO, sr, centre - HALF_SPAN, centre + HALF_SPAN, 12, Palette.with_alpha(Palette.SHIELD, _alpha(sh, frac)), (1.0 + 2.0 * frac) * px, true)


## The simple look: all the arcs in one command. Each arc is a strip of triangles
## along its ring, as thick as the full look's line, brightest in the middle and
## fading to nothing in SOFT_PX screen pixels at each side. The middle of the strip is
## made a little thinner by the soft edges, so the arc weighs the same as an
## antialiased line of that thickness.
static func draw_simple(ci: CanvasItem, sh: ShieldZones, sr: float, px: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# Step 1: how many segments an arc needs: about one for every SIMPLE_SEGMENT_PX of its length.
	var steps := clampi(roundi(2.0 * HALF_SPAN * sr / (px * SIMPLE_SEGMENT_PX)), 3, 8)
	var soft := SOFT_PX * px
	for zone in 4:
		var cap := sh.cap(zone)
		if cap <= 0.0:
			continue
		var frac := sh.values[zone] / cap
		if frac <= 0.01:
			continue
		# Step 2: this arc's brightness, thickness and the width of its flat middle.
		var col := Palette.with_alpha(Palette.SHIELD, _alpha(sh, frac))
		var none := Color(col.r, col.g, col.b, 0.0)
		var width := (1.0 + 2.0 * frac) * px
		var core := maxf(0.0, width - soft) * 0.5
		var outer := core + soft
		# Step 3: four points across the arc at every step along it: the soft edge on the
		# outside, the flat middle's outside and inside, the soft edge on the inside.
		var centre: float = CENTERS[zone]
		var first := pts.size()
		for i in steps + 1:
			var dir := Vector2.from_angle(centre - HALF_SPAN + 2.0 * HALF_SPAN * float(i) / float(steps))
			pts.append(dir * (sr + outer))
			pts.append(dir * (sr + core))
			pts.append(dir * (sr - core))
			pts.append(dir * (sr - outer))
			cols.append(none)
			cols.append(col)
			cols.append(col)
			cols.append(none)
		# Step 4: two triangles for every quad between one step's four points and the next's.
		for i in steps:
			for j in 3:
				var a := first + i * 4 + j
				var b := a + 4
				idx.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)
