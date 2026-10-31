class_name ProjectilesDraw
extends RefCounted
## WHAT THIS IS: draws the rounds in flight and the beam lines on the
## screen. A part of Projectiles, kept in its own file. Drawing only: it
## never changes the game.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## When Godot redraws the screen it calls Projectiles._draw(), which hands
## itself to draw_all(). We work out the part of the map the camera shows
## (plus a 200 world-unit margin) and skip rounds outside it. Enemy rounds
## in fog the viewing team can't see are skipped too; our own are always
## drawn. Each round is drawn along its flight:
##   torpedo: a small dart with a bar of tail fins, a hot motor dot and a
##            faint plume behind it (4 drawing commands); a Bomber's torpedo
##            that is not armed yet is the dart dimmed, without the motor dot
##            and the plume (2 drawing commands);
##   shell:   a thick streak;
##   flak:    a short streak;
##   others (bolts, point defense): a thin streak.
## Beams are a wide faint glow with a thin bright core. Ion beams are
## shield-blue; other beams take the team's bolt colour. An enemy beam is
## hidden only when the viewer can see neither of its two ends.
##
## Sizes are multiplied by "px" (one screen pixel in world units, which
## depends on the camera zoom), so streaks keep the same size on screen at
## any zoom.
##
## A torpedo's drawing is sized by its radius, but the radius used is never
## under 3 screen pixels, so the picture is never smaller than the hit circle
## that point defense and flak shoot at. At the start zoom that floor rules, and
## all torpedoes are the same size. The motor dot beats about twice a second:
## the beat comes from the match clock alone, nothing random, so every
## torpedo beats together and the beat stops while the match is paused.
##
## WHO USES IT: only Projectiles._draw().

## How strong (0..1) the hull and the fins of a torpedo that is not armed yet are
## drawn.
const COLD_ALPHA := 0.7


## Draw every visible round and last tick's beam lines onto `proj` (the
## Projectiles node). Only call this from Projectiles._draw().
static func draw_all(proj: Projectiles) -> void:
	# Step 1: the part of the map the camera shows (plus a margin), and how
	# big one screen pixel is in world units.
	var cam := proj.get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam != null else 1.0
	var view := proj.get_viewport_rect().size / zoom
	var center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var rect := Rect2(center - view * 0.5, view).grow(200.0)
	var px := 1.0 / maxf(0.02, zoom)
	var world := proj.world
	var viewer_team := proj.viewer_team
	var live := proj.live
	var pos := proj.pos
	var team := proj.team
	var kind := proj.kind
	var vel := proj.vel
	var radius := proj.radius
	# The torpedo motor's beat (about 0.8 to 1.2): worked out once here, from the
	# match clock, for every torpedo.
	var pulse := 1.0 + 0.2 * sin(14.0 * world.time)
	# Step 2: each live round on screen that the viewer may see.
	for i in proj.active:
		if live[i] == 0:
			continue
		var p := pos[i]
		if not rect.has_point(p):
			continue
		if viewer_team >= 0 and team[i] != viewer_team and not world.vision.is_visible(viewer_team, p):
			continue
		# Its colour, and the direction it flies (straight right if it is
		# not moving), so the streak can point backwards.
		var col := Palette.bolt(team[i])
		var k := kind[i]
		var v := vel[i]
		var sp := v.length()
		var dir := v / sp if sp > 0.0 else Vector2.RIGHT
		# Step 3: its shape depends on the weapon kind.
		match k:
			Rules.W_TORP:
				_draw_torpedo(proj, p, dir, maxf(radius[i], 3.0 * px), col, px, pulse, proj.armed(i))
			Rules.W_SHELL:
				proj.draw_line(p, p - dir * 16.0 * px, col, 3.0 * px)
			Rules.W_FLAK:
				proj.draw_line(p, p - dir * 6.0 * px, Palette.with_alpha(col, 0.9), 2.0 * px)
			_:
				proj.draw_line(p, p - dir * 9.0 * px, col, 1.6 * px)
	# Step 4: the beams, each [a, b, team, width, kind]: a wide faint glow
	# under a thin bright core (at least 2 screen pixels wide).
	for bm: Array in proj.beams_draw:
		var bt: int = bm[2]
		var a: Vector2 = bm[0]
		var b: Vector2 = bm[1]
		if viewer_team >= 0 and bt != viewer_team and not world.vision.is_visible(viewer_team, a) and not world.vision.is_visible(viewer_team, b):
			continue
		var w := maxf(float(bm[3]), 2.0 * px)
		var col := Palette.SHIELD if int(bm[4]) == Rules.W_ION else Palette.bolt(bt)
		proj.draw_line(a, b, Palette.with_alpha(col, 0.35), w * 2.5)
		proj.draw_line(a, b, col, w)


## Draw one torpedo on `proj` as a spindle, in four drawing commands (the last
## one lies on top): a faint plume behind it, a dart-shaped hull, a bar of
## tail fins and a hot motor dot. A torpedo that is not armed yet (`armed` is
## false) is the same dart cold: the hull and the fins at 70% strength, and no
## plume and no motor dot (two drawing commands), so the motor and the plume
## light up at the arming distance. `p` is the torpedo's position (the centre of
## its hit circle), `dir` the unit vector it flies along, `r` its drawn radius
## (world units), `col` its team's bolt colour, `px` one screen pixel in world
## units and `pulse` the motor dot's size factor for this frame. Drawing only.
static func _draw_torpedo(proj: Projectiles, p: Vector2, dir: Vector2, r: float, col: Color, px: float, pulse: float, armed: bool) -> void:
	# The sideways direction (at right angles to the flight).
	var side := dir.orthogonal()
	# Step 1: the plume, a faint line behind the motor (armed torpedoes only).
	if armed:
		proj.draw_line(p - dir * 2.2 * r, p - dir * 7.2 * r, Palette.with_alpha(col, 0.3), maxf(px, 0.4 * r))
	# Step 2: the hull, a five-point dart: nose, two shoulders, two tail corners.
	proj.draw_colored_polygon(PackedVector2Array([
		p + dir * 2.0 * r,
		p + dir * 0.6 * r + side * 0.8 * r,
		p - dir * 2.0 * r + side * 0.45 * r,
		p - dir * 2.0 * r - side * 0.45 * r,
		p + dir * 0.6 * r - side * 0.8 * r,
	]), col if armed else Palette.with_alpha(col, COLD_ALPHA))
	# Step 3: the tail fins, a bar across the flight just ahead of the tail.
	proj.draw_line(p - dir * 1.6 * r - side * 1.3 * r, p - dir * 1.6 * r + side * 1.3 * r, Palette.with_alpha(col, 0.85 if armed else COLD_ALPHA), maxf(px, 0.3 * r))
	# Step 4: the motor, a dot at the tail, pulled 60% toward white, on top
	# (armed torpedoes only).
	if armed:
		proj.draw_circle(p - dir * 2.2 * r, 0.55 * r * pulse, col.lerp(Color.WHITE, 0.6))
