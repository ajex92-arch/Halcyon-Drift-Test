class_name TurnCues
extends Control
## WHAT THIS IS: the three turn cues of the pilot's own ship, drawn on the HUD layer: a short heading tick toward the mouse pointer,
## a dotted turn-radius arc, and four small corner marks where the ship would stop if it braked now (the stop-here ghost). They tell
## the pilot where the nose is going, how wide the turn at this speed is, and how far the ship still drifts. Drawing only: they read
## the ship and the pointer and change nothing in the game (no field of a Unit, a Ship, the shots or the World is written).
##
## HOW IT WORKS: it belongs to the HUD, covers the whole screen and lets the mouse through (the shape of HudAlarm). It shows only for
## the ship the human flies, only while that ship moves faster than MIN_SPEED world units a second (the drift arrow's own floor), and
## only for the parts ShipRingParts.shown() says are on (the presets and the single switches of the pause menu). Every frame it draws again:
##   - the heading tick: a 1.5 pixel line from 2 pixels outside the ring to 22 pixels outside it, toward the pointer. The ring is
##     the pilot's ring set's radius, max(24, the world shield ring on screen + 8) pixels (ring_px());
##   - the turn arc: it starts at the ship along its velocity and curves to the pointer's side through the angle between the nose and
##     the pointer (at most 180 degrees), on a circle of radius speed / turn rate (turn_radius(): the turn rate falls with speed, as
##     in ShipFlight and ShipLineFlight). Drawn as dashes, 2 pixels on and 5 off, and never longer than ARC_MAX_PX on the screen;
##   - the ghost: four corner marks (3 pixel legs) at the ship's drawn size, facing as the ship faces now, at the point
##     v squared over twice the strongest braking along the velocity, plus the time a ship of the line's engines need to swing round
##     times v (stop_distance()).
## Colours are ICE with a fade (never the danger colour), nothing moves by itself and nothing blinks. The picture uses three drawing
## commands at most (one line, two multilines), counted in `drawn` for the check.
##
## WHO USES IT: Hud.setup() makes one under the torpedo alarm and gives it the world. Not made in --sim-only runs (they have no HUD).
## tests/flight_cues_check.gd checks it.

## The slowest speed (world units a second) at which the cues show: the drift arrow's own floor.
const MIN_SPEED := 12.0
## The heading tick starts this many pixels outside the ring.
const TICK_START := 2.0
## The heading tick ends this many pixels outside the ring.
const TICK_END := 22.0
## The smallest ring radius (pixels).
const RING_MIN := 24.0
## The ring is the world shield ring on screen plus this many pixels.
const RING_PAD := 8.0
## The width of every line (pixels).
const LINE_W := 1.5
## The dashes of the turn arc: pixels on and pixels off.
const DASH_ON := 2.0
const DASH_OFF := 5.0  # (pixels off)
## The turn arc is never drawn longer than this on the screen (pixels).
const ARC_MAX_PX := 640.0
## The legs of the ghost's corner marks (pixels).
const GHOST_LEG := 3.0
## The shortest side of the ghost's box (pixels): the ship's drawn size is never less (ShipVisual.MIN_PX).
const GHOST_MIN_PX := 16.0
## The ghost's box is this share as wide as it is long.
const GHOST_BEAM := 0.6
## The strengths of the three parts (alpha of ICE): the heading tick, the turn arc and the ghost.
const TICK_ALPHA := 0.5
const ARC_ALPHA := 0.35  # (the turn arc's)
const GHOST_ALPHA := 0.4  # (the ghost's)

## The game world (set by setup()).
var world: World
## How many drawing commands the last _draw() made (0 to 3): the check reads it.
var drawn := 0


## Remember the world, cover the whole screen and let the mouse through. Hud.setup() calls this once.
func setup(w: World) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Every frame: show only while the human flies fast enough, and draw again then (the pointer moves).
func _process(_dt: float) -> void:
	if world == null:
		return
	var s := cue_ship()
	var on := s != null and s.velocity.length() > MIN_SPEED
	if on != visible:
		visible = on
		if not on:
			drawn = 0
	if on:
		queue_redraw()


## The ship the cues belong to: the one the human flies, while it is flying and alive; otherwise null. No other ship ever gets cues, and
## none while the command view or the Admiral's board is open over the flight (the ship coasts then).
func cue_ship() -> Ship:
	var me := world.human if world != null else null
	if me == null or me.state != "flying" or me.ship == null or not is_instance_valid(me.ship) or not me.ship.alive or world.mode3():
		return null
	return me.ship


## The radius (world units) of the turn at speed `sp`: speed over the turn rate at that speed. The turn rate is the hull's own, less at
## speed (turn x (1 - bleed x share of top speed)), as ShipFlight works it out. 0 when the ship cannot turn.
static func turn_radius(sp: float, f_turn: float, f_bleed: float, f_max: float) -> float:
	var frac := minf(1.0, sp / f_max) if f_max > 0.0 else 0.0
	var rate := f_turn * (1.0 - f_bleed * frac)
	return sp / rate if rate > 0.001 else 0.0


## How far (world units) the ship still goes when it brakes at its strongest from speed `sp`: v squared over twice the braking, plus
## the speed times the seconds a ship of the line's engines need to swing round (0 for every other hull). 0 when it cannot brake.
static func stop_distance(sp: float, f_brake: float, f_brake_lag: float) -> float:
	if f_brake <= 0.001:
		return 0.0
	return sp * sp / (2.0 * f_brake) + sp * f_brake_lag


## The ring radius (pixels) the heading tick starts from: max(24, the world shield ring on screen + 8). `ring_world` is the shield ring's
## radius in world units (ShipVisual._ring_radius()); `z` the zoom.
static func ring_px(ring_world: float, z: float) -> float:
	return maxf(RING_MIN, ring_world * z + RING_PAD)


## Draw the three parts for the ship the human flies.
func _draw() -> void:
	drawn = 0
	var s := cue_ship()
	if s == null:
		return
	var sp := s.velocity.length()
	if sp <= MIN_SPEED:
		return
	var xf := get_viewport().get_canvas_transform()
	var z := xf.get_scale().x
	var p := xf * s.global_position
	var aim := world.mouse_world() - s.global_position
	var ice := Palette.ICE
	# Part 1: the heading tick, toward the pointer, from the ring's edge outward.
	if ShipRingParts.shown("heading_tick") and aim.length() * z > ring_px(_ring_world(s, z), z) + TICK_START:
		var r := ring_px(_ring_world(s, z), z)
		var d := aim.normalized()
		draw_line(p + d * (r + TICK_START), p + d * (r + TICK_END), Palette.with_alpha(ice, TICK_ALPHA), LINE_W, true)
		drawn += 1
	# Part 2: the turn arc, dashes along a circle that starts at the ship along its velocity and curves to the pointer's side.
	if ShipRingParts.shown("turn_arc") and aim.length_squared() > 1.0:
		var pts := _arc_dashes(s, p, sp, z, aim)
		if not pts.is_empty():
			draw_multiline(pts, Palette.with_alpha(ice, ARC_ALPHA), LINE_W, true)
			drawn += 1
	# Part 3: the ghost, four corner marks where the ship would stop.
	if ShipRingParts.shown("ghost"):
		var pts := _ghost_corners(s, p, sp, z)
		if not pts.is_empty():
			draw_multiline(pts, Palette.with_alpha(ice, GHOST_ALPHA), LINE_W, true)
			drawn += 1


## The world shield ring's radius (world units) of ship `s` at zoom `z`: its picture's own number when it has one.
func _ring_world(s: Ship, z: float) -> float:
	var vis := s.get_node_or_null("Visual") as ShipVisual
	if vis != null:
		return vis._ring_radius(z)
	var length := float(s.def.get("length", 26.0))
	return maxf(length * maxf(1.0, GHOST_MIN_PX / maxf(0.001, length * z)) * 0.62, s.radius * 1.3)


## The dashes of the turn arc as a list of point pairs (screen pixels), or an empty list when there is no arc to show.
func _arc_dashes(s: Ship, p: Vector2, sp: float, z: float, aim: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := turn_radius(sp, s.f_turn, s.f_bleed, s.f_max) * z
	if r < 2.0:
		return out
	# The angle between the nose and the pointer, at most 180 degrees, and which side it turns to (clockwise on screen is positive).
	var nose := Vector2.from_angle(s.rotation)
	var turn := nose.angle_to(aim)
	var side := 1.0 if turn >= 0.0 else -1.0
	var sweep := minf(absf(turn), PI)
	# The circle's middle is a radius to the side of the velocity; the arc runs from the ship round it through `sweep`.
	var heading := s.velocity / sp
	var centre := p + heading.rotated(side * PI * 0.5) * r
	var from := p - centre
	var length := minf(r * sweep, ARC_MAX_PX)
	var step := DASH_ON + DASH_OFF
	var at := 0.0
	while at < length:
		var end := minf(at + DASH_ON, length)
		out.append(centre + from.rotated(side * at / r))
		out.append(centre + from.rotated(side * end / r))
		at += step
	return out


## The four corner marks of the ghost as a list of point pairs (screen pixels), or an empty list when the ship cannot brake or the
## mark would be far off screen.
func _ghost_corners(s: Ship, p: Vector2, sp: float, z: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dist := stop_distance(sp, s.f_brake, s.f_brake_lag) * z
	if dist <= 0.0:
		return out
	var centre := p + (s.velocity / sp) * dist
	var room := Rect2(Vector2.ZERO, size).grow(80.0)
	if not room.has_point(centre):
		return out
	var length := maxf(float(s.def.get("length", 26.0)) * z, GHOST_MIN_PX)
	var half := Vector2(length * 0.5, length * 0.5 * GHOST_BEAM)
	var rot := s.rotation
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := Vector2(half.x * sx, half.y * sy)
			out.append(centre + corner.rotated(rot))
			out.append(centre + (corner + Vector2(-sx * GHOST_LEG, 0.0)).rotated(rot))
			out.append(centre + corner.rotated(rot))
			out.append(centre + (corner + Vector2(0.0, -sy * GHOST_LEG)).rotated(rot))
	return out
