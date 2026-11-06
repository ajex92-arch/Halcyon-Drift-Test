class_name FanPaint
extends RefCounted
## WHAT THIS IS: the painter of a Bomber's fan: the lines that show where the
## three torpedoes of its run will fly. A part of RunPaint (which paints the bar
## and calls this), kept in its own file. Drawing only: it never changes the game.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
##   - While a run is on, draw_lines() draws all three lanes from the gun, the
##     way a launch this tick would send them (RunFan.lanes()): the middle line
##     dashed and clear, the two edges of the fan fainter. Each line ends at the
##     torpedoes' reach (their speed times their flight time, from the lane's own
##     velocity) or at the first rock, which would stop the torpedo. The first
##     stretch of the middle line, as long as the arming distance, is not a
##     dashed line but a hollow strip (an outline): a torpedo that touches
##     something there is a dud, so a launch that close is wasted.
##   - Before a run, the pilot's own sight (draw_lines() with `sight` set) draws
##     only the two faint edges, and only while an enemy lies inside the fan
##     within the reach (enemy_in_fan()), so it is a sight and not clutter.
##
## WHO USES IT: only RunPaint.draw().

## How clear (0..1) the middle line is.
const CENTER_ALPHA := 0.5
## How clear the two edges of the fan are while a run is on.
const EDGE_ALPHA := 0.3
## How clear the edges of the pilot's own sight are before a run.
const SIGHT_ALPHA := 0.18
## How long one dash is, in screen pixels.
const DASH_PX := 14.0


## Draw the lanes of `ship`'s fan on `ci` (the ship's Visual node, whose _draw() is
## running; its origin is the ship's position and it is not turned). `px` is world
## units per screen pixel. With `sight` set only the two faint edges are drawn.
static func draw_lines(ci: CanvasItem, ship: Ship, px: float, sight: bool) -> void:
	var m := ship.run_mount
	var life := float(m.def["life"]) * ship.range_mult
	var radius := float(m.def.get("radius", 3.0))
	var arm := float(m.def.get("arm", 0.0))
	var col := Palette.bolt(ship.team)
	var lane_list := RunFan.lanes(m, ship.fan_points)
	var middle := lane_list.size() / 2
	for k in lane_list.size():
		var is_middle := k == middle
		if sight and is_middle:
			continue
		# Step 1: the line's length: the reach, or up to the first rock.
		var l: Array = lane_list[k]
		var from: Vector2 = l[0]
		var vel: Vector2 = l[1]
		var unit := vel.normalized()
		var length := vel.length() * life
		var rock := ship.world.asteroids.segment_hit(from, from + unit * length, radius)
		if not rock.is_empty():
			length *= clampf(float(rock["t"]), 0.0, 1.0)
		var a := from - ship.global_position
		# Step 2: the edges are one faint dashed line each.
		if not is_middle:
			ci.draw_dashed_line(a, a + unit * length, Palette.with_alpha(col, SIGHT_ALPHA if sight else EDGE_ALPHA), 1.2 * px, DASH_PX * px)
			continue
		# Step 3: the middle line: a hollow strip as long as the arming distance
		# (an outline as wide as the torpedo), then the dashed line.
		var hollow := minf(arm, length)
		if hollow > 0.0:
			var side := unit.orthogonal() * maxf(radius, 2.0 * px)
			var edge_col := Palette.with_alpha(col, CENTER_ALPHA)
			ci.draw_line(a + side, a + side + unit * hollow, edge_col, 1.2 * px)
			ci.draw_line(a - side, a - side + unit * hollow, edge_col, 1.2 * px)
			ci.draw_line(a + unit * hollow + side, a + unit * hollow - side, edge_col, 1.2 * px)
		if length > hollow:
			ci.draw_dashed_line(a + unit * hollow, a + unit * length, Palette.with_alpha(col, CENTER_ALPHA), 1.5 * px, DASH_PX * px)


## True when an enemy of `ship` that its team can see (an enemy ship, minion,
## turret or derelict, or an enemy mothership) lies inside the fan a launch now
## would make, within the torpedoes' reach: the cone of the two edges touches the
## enemy's hit circle. The pilot's sight shows only then. Reads the game and
## changes nothing.
static func enemy_in_fan(ship: Ship) -> bool:
	var m := ship.run_mount
	var w := ship.world
	var lane_list := RunFan.lanes(m, ship.fan_points)
	var mid: Array = lane_list[lane_list.size() / 2]
	var from: Vector2 = mid[0]
	var vel: Vector2 = mid[1]
	var dir := vel.normalized()
	var reach := vel.length() * float(m.def["life"]) * ship.range_mult
	var half := RunFan.half_angle(m.def, ship.fan_points)
	var heading := dir.angle()
	# Step 1: the units near the fan (the same two searches the rounds use).
	var centre := from + dir * reach * 0.5
	var near: Array = []
	w.unit_hash.query(centre, reach * 0.5 + Projectiles.HASH_PAD, near)
	if w.big_count > 0:
		near.append_array(w.big_hash.query(centre, reach * 0.5 + Projectiles.HASH_PAD + Projectiles.BIG_PAD, []))
	for u: Unit in near:
		if not u.alive or u.team == ship.team or not (FogOff.is_on() or w.vision.is_visible(ship.team, u.global_position)):
			continue
		if _cone_touches(from, heading, half, reach, u.global_position, u.hit_radius()):
			return true
	# Step 2: the enemy mothership: its hull is long, so its nearest spine point
	# stands for it.
	for ms: Mothership in w.motherships:
		if ms == null or not ms.alive or ms.team == ship.team:
			continue
		var spine := Vector2.from_angle(ms.rotation) * ms.half_len
		var nearest := Util.closest_on_segment(from, ms.position + spine, ms.position - spine)
		if (FogOff.is_on() or w.vision.is_visible(ship.team, nearest)) and _cone_touches(from, heading, half, reach, nearest, ms.beam * 0.5):
			return true
	return false


## Does the cone from `from`, pointing `heading` (radians) and `half` wide each
## way, reach out to `reach`, touch the circle at `c` of radius `r`?
static func _cone_touches(from: Vector2, heading: float, half: float, reach: float, c: Vector2, r: float) -> bool:
	var d := c - from
	var dist := d.length()
	if dist > reach + r:
		return false
	if dist <= r:
		return true
	return absf(Util.ang_diff(heading, d.angle())) <= half + asin(minf(1.0, r / dist))
