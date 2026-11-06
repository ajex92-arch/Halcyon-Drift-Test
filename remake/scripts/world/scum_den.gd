class_name ScumDen
extends Node2D
## WHAT THIS IS: the scrap and wreckage heaped round one Scum den (one jungle camp): torn-off
## armour slabs, broken girders, a ring of hazard tape on the ground and three warning
## beacons. It stays on the map when the den ship is shot down and waits for the next one. It
## is only decoration: it changes nothing in the game, and nothing in the simulation reads it.
##
## HOW IT WORKS: MapDecor makes one for every camp (setup()). The drawing is made once, from a
## random number maker of its own (Mulberry, seeded from the camp's name), so every match
## has the same heaps and no other random numbers are disturbed. Godot remembers the drawing,
## so _draw() runs once; lines are in world units, because a remembered drawing cannot follow
## the zoom. It is a node per camp, not one big drawing, so a camp off the screen costs nothing.
## It is drawn under the ships (MapDecor lies at z -10).
##
## WHO USES IT: MapDecor.setup() makes them. It reads Palette (the SCUM_ colours) and SiteMarks
## (the dashed ring).

## How many scrap slabs lie round a den.
const SLABS := 11
## The nearest a slab lies to the middle, as a multiple of the den ship's radius.
const SLAB_NEAR := 1.5
## The farthest a slab lies from the middle, as a multiple of the den ship's radius.
const SLAB_FAR := 2.9
## The ring of hazard tape lies at this many radii.
const RING := 3.4
## How many warning beacons stand on the ring.
const BEACONS := 3
## The width, in world units, of a slab's outline.
const EDGE_WIDTH := 3.0
## The width, in world units, of a broken girder.
const GIRDER_WIDTH := 4.0

## The radius of the den ship that lives here, in world units.
var _radius := 50.0
## Where the random numbers of this den start (made from the camp's name).
var _seed := 1


## Put the den at `at`, for a den ship of radius `radius`; `seed_value` makes the heaps
## different from den to den (and the same every match). Then ask Godot to draw once.
func setup(at: Vector2, radius: float, seed_value: int) -> void:
	position = at
	_radius = radius
	_seed = seed_value
	queue_redraw()


## Draw the heaps, the tape ring and the beacons (once; Godot keeps the picture).
func _draw() -> void:
	var rng := Mulberry.new(_seed)
	# Step 1: the ring of hazard tape, broken into dashes, on the ground.
	SiteMarks.dashed_circle(self, Vector2.ZERO, _radius * RING, Palette.with_alpha(Palette.SCUM_HAZARD, 0.28), EDGE_WIDTH + 1.0)
	# Step 2: scrap slabs, spread round the den: each a torn, many-cornered piece of plate in
	# gunmetal, grey or rust, with a bare-metal edge.
	for i in SLABS:
		var angle := (float(i) + rng.next() * 0.8) * TAU / float(SLABS)
		var dist := _radius * (SLAB_NEAR + rng.next() * (SLAB_FAR - SLAB_NEAR))
		var centre := Vector2.from_angle(angle) * dist
		var size := _radius * (0.12 + rng.next() * 0.2)
		var turn := rng.next() * TAU
		var corners := 4 + int(rng.next() * 2.0)
		var pts := PackedVector2Array()
		for j in corners:
			var a := turn + TAU * float(j) / float(corners) + (rng.next() - 0.5) * 0.5
			pts.append(centre + Vector2.from_angle(a) * size * (0.6 + rng.next() * 0.7))
		var pick := rng.next()
		var fill := Palette.SCUM_IRON
		if pick > 0.62:
			fill = Palette.SCUM_RUST
		elif pick > 0.3:
			fill = Palette.SCUM_PLATE
		draw_colored_polygon(pts, Palette.with_alpha(fill, 0.92))
		pts.append(pts[0])
		draw_polyline(pts, Palette.with_alpha(Palette.SCUM_EDGE, 0.5), EDGE_WIDTH, true)
	# Step 3: broken girders lying about: short bare-metal bars at odd angles.
	var girders := PackedVector2Array()
	for i in 4:
		var angle := rng.next() * TAU
		var from := Vector2.from_angle(angle) * _radius * (1.6 + rng.next() * 1.3)
		var bar := Vector2.from_angle(rng.next() * TAU) * _radius * (0.35 + rng.next() * 0.4)
		girders.append(from)
		girders.append(from + bar)
	draw_multiline(girders, Palette.with_alpha(Palette.SCUM_PLATE, 0.9), GIRDER_WIDTH)
	# Step 4: the warning beacons, spaced round the ring: a green glow, a dark ring and a
	# hazard-yellow lamp.
	var first := rng.next() * TAU
	for i in BEACONS:
		var at := Vector2.from_angle(first + TAU * float(i) / float(BEACONS)) * _radius * RING
		draw_circle(at, 26.0, Palette.with_alpha(Palette.SCUM_GLOW, 0.13))
		draw_circle(at, 11.0, Palette.SCUM_IRON_DARK)
		draw_circle(at, 7.0, Palette.SCUM_HAZARD)
