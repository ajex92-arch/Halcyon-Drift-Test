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
## T-126b: the team shapes (Set 3, "Bead and Barb"). Aurelian rounds are round and solid, Vhorr rounds angular, and hollow
## where drawn 5 pixels wide or more; the Scum's rounds, torpedoes and beams (no team) keep the plain drawing above.
##   bolt, point defense, flak, shell: the head is R = the hit circle's radius in pixels, never under the kind's floor
##            (1.3, 1.5, 1.8 pixels); the tail is max(base, 3 R) long and max(base, R) wide. Aurelian: the tail line and a
##            bead at the head (2 commands). Vhorr: one seven-point polygon, a barbed head on the tail (1 command), with a
##            VOID triangle that hollows a head 5 pixels across or more (2 commands). A minion's round is 0.85 of every
##            fixed size, as well as 0.6 dim.
##   torpedo: Aurelian a nose disc ahead of the dart; Vhorr a VOID core in the dart (5 commands armed, 3 not armed).
##   beams (Lance, ion): at the far end Aurelian a bead (radius 2.2 pixels), Vhorr a barb, and a Vhorr core 3 pixels wide or
##            more a VOID centre line (3 commands, 4 for that core, with the glow and the core). Ion beams stay shield blue
##            for both teams, so the shape is the only team cue on them.
##
## Sizes are multiplied by "px" (one screen pixel in world units, which
## depends on the camera zoom), so streaks keep the same size on screen at
## any zoom. Every streak is at least as wide as its round's hit circle
## (streak_width()); the rounds are drawn friendly first and hostile last
## (draw_order()), so a hostile round is never hidden under a friendly one; a
## round a minion fired is drawn at 0.6 of its colour (round_alpha()); a round
## that is no longer live is not drawn.
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
	# Step 2: each live round on screen that the viewer may see: the viewer's own and friendly rounds first, hostile rounds last (so a
	# hostile round is never hidden under a friendly one). A round that is not live (it stopped being dangerous this tick) is not in the order.
	for i in draw_order(proj):
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
		# A minion's round is drawn dimmer than a pilot's.
		var dim := round_alpha(proj.src_minion[i])
		if dim < 1.0:
			col = Palette.with_alpha(col, dim)
		# Step 3: its shape depends on the weapon kind; every streak is at least as wide as the round's hit circle.
		if k == Rules.W_TORP:
			_draw_torpedo(proj, p, dir, maxf(radius[i], 3.0 * px), col, px, pulse, proj.armed(i), team[i])
		elif team[i] == Rules.HALCYON or team[i] == Rules.CINDER:
			_draw_round(proj, k, p, dir, radius[i], col, px, team[i], dim, proj.src_minion[i])
		else:
			# The Scum's rounds (no team) stay a plain streak.
			match k:
				Rules.W_SHELL:
					proj.draw_line(p, p - dir * 16.0 * px, col, streak_width(k, radius[i], px))
				Rules.W_FLAK:
					proj.draw_line(p, p - dir * 6.0 * px, Palette.with_alpha(col, 0.9 * dim), streak_width(k, radius[i], px))
				_:
					proj.draw_line(p, p - dir * 9.0 * px, col, streak_width(k, radius[i], px))
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
		# T-126b: the team's shape at the far end (the Scum's beam, with no team, keeps the plain two lines).
		if bt == Rules.HALCYON or bt == Rules.CINDER:
			_draw_beam_end(proj, a, b, bt, w, col, px)


## The width (world units) of the streak of a round of weapon kind `k` whose hit circle has radius `radius`, where `px` is one screen pixel
## in world units: the kind's fixed screen width (a shell 3 pixels, flak 2, anything else 1.6), never less than the hit circle's
## diameter, so a round is never drawn thinner than the circle that hits things.
static func streak_width(k: int, radius: float, px: float) -> float:
	var fixed := 3.0 * px if k == Rules.W_SHELL else (2.0 * px if k == Rules.W_FLAK else 1.6 * px)
	return maxf(fixed, 2.0 * radius)


## How strong a round's colour is: 0.6 for a round a minion fired (`minion` is 1), 1 for every other.
static func round_alpha(minion: int) -> float:
	return 0.6 if minion == 1 else 1.0


## Is a round of team `round_team` hostile to the viewer? The viewer is a team (`viewer_team`, 0 or 1: every other team is hostile) or, for
## a viewer below 0 who sees everything, the side of the Aurelian team (everything else is hostile).
static func is_hostile(round_team: int, viewer_team: int) -> bool:
	if viewer_team >= 0:
		return round_team != viewer_team
	return round_team != Rules.HALCYON


## The slots of the live rounds in the order they are drawn: the viewer's own and friendly rounds first, then the hostile ones, each group
## in the order of the live list (a round that is not live is left out).
static func draw_order(proj: Projectiles) -> PackedInt32Array:
	var order := PackedInt32Array()
	var hostile := PackedInt32Array()
	for i in proj.active:
		if proj.live[i] == 0:
			continue
		if is_hostile(proj.team[i], proj.viewer_team):
			hostile.append(i)
		else:
			order.append(i)
	order.append_array(hostile)
	return order


## Draw one torpedo on `proj` as a spindle, in four drawing commands (the last
## one lies on top): a faint plume behind it, a dart-shaped hull, a bar of
## tail fins and a hot motor dot. A torpedo that is not armed yet (`armed` is
## false) is the same dart cold: the hull and the fins at 70% strength, and no
## plume and no motor dot (two drawing commands), so the motor and the plume
## light up at the arming distance. `p` is the torpedo's position (the centre of
## its hit circle), `dir` the unit vector it flies along, `r` its drawn radius
## (world units), `col` its team's bolt colour, `px` one screen pixel in world
## units and `pulse` the motor dot's size factor for this frame. T-126b: `team` Aurelian adds a nose disc and Vhorr a VOID core
## in the dart (one more drawing command each: 5 armed, 3 not armed); any other team keeps the plain torpedo. Drawing only.
static func _draw_torpedo(proj: Projectiles, p: Vector2, dir: Vector2, r: float, col: Color, px: float, pulse: float, armed: bool, team: int = Rules.NEUTRAL) -> void:
	# The sideways direction (at right angles to the flight).
	var side := dir.orthogonal()
	# Step 1: the plume, a faint line behind the motor (armed torpedoes only).
	if armed:
		proj.draw_line(p - dir * 2.2 * r, p - dir * 7.2 * r, Palette.with_alpha(col, 0.3), maxf(px, 0.4 * r))
	# Step 2: the hull, a five-point dart: nose, two shoulders, two tail corners.
	var hull_col := col if armed else Palette.with_alpha(col, COLD_ALPHA)
	proj.draw_colored_polygon(dart(p, dir, r), hull_col)
	# T-126b, the team's shape: Vhorr's dart has a dark core (the dart at half size about the centre); Aurelian's has a round
	# nose disc (centre 1.2 r ahead, radius 0.8 r). The Scum's torpedo keeps the plain dart.
	if team == Rules.CINDER:
		proj.draw_colored_polygon(dart(p, dir, r * 0.5), Palette.VOID)
	elif team == Rules.HALCYON:
		proj.draw_circle(p + dir * 1.2 * r, 0.8 * r, hull_col)
	# Step 3: the tail fins, a bar across the flight just ahead of the tail.
	proj.draw_line(p - dir * 1.6 * r - side * 1.3 * r, p - dir * 1.6 * r + side * 1.3 * r, Palette.with_alpha(col, 0.85 if armed else COLD_ALPHA), maxf(px, 0.3 * r))
	# Step 4: the motor, a dot at the tail, pulled 60% toward white, on top
	# (armed torpedoes only).
	if armed:
		proj.draw_circle(p - dir * 2.2 * r, 0.55 * r * pulse, col.lerp(Color.WHITE, 0.6))


## The five corners of a torpedo's dart at `p` flying along `dir`, drawn radius `r` (world units): nose, shoulder, two tail
## corners, shoulder. Scaled about `p` by the radius, so the core of a Vhorr torpedo is dart() at half the radius.
static func dart(p: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var side := dir.orthogonal()
	return PackedVector2Array([
		p + dir * 2.0 * r,
		p + dir * 0.6 * r + side * 0.8 * r,
		p - dir * 2.0 * r + side * 0.45 * r,
		p - dir * 2.0 * r - side * 0.45 * r,
		p + dir * 0.6 * r - side * 0.8 * r,
	])


## T-126b: the size of a round a minion fired against a pilot's (`minion` is 1 for a minion's round): 0.85, else 1. It scales the
## round's fixed sizes (tail, head floor), never the part that covers its hit circle.
static func minion_size(minion: int) -> float:
	return 0.85 if minion == 1 else 1.0


## The floor of a round's head half-width in screen pixels, by weapon kind: 1.5 for flak, 1.8 for a shell, 1.3 for any other.
static func head_floor(k: int) -> float:
	return 1.8 if k == Rules.W_SHELL else (1.5 if k == Rules.W_FLAK else 1.3)


## The tail of a round, as (length, width) in screen pixels at its base: a shell 16 x 3, flak 6 x 2, any other 9 x 1.6.
static func tail_base(k: int) -> Vector2:
	return Vector2(16.0, 3.0) if k == Rules.W_SHELL else (Vector2(6.0, 2.0) if k == Rules.W_FLAK else Vector2(9.0, 1.6))


## The head half-width R (screen pixels) of a round of kind `k` with hit radius `radius` (world units): the hit circle's radius
## in pixels, but never under the kind's floor (head_floor(), x `size`).
static func head_radius(k: int, radius: float, px: float, size: float = 1.0) -> float:
	return maxf(radius / px, head_floor(k) * size)


## The tail of a round (screen pixels): its length max(base length, 3 R) and its width max(base width, R), the bases x `size`.
static func tail(k: int, big_r: float, size: float = 1.0) -> Vector2:
	var b := tail_base(k) * size
	return Vector2(maxf(b.x, 3.0 * big_r), maxf(b.y, big_r))


## The half-width H (screen pixels) of a Vhorr round's barbed head: max(R, tail width / 2 + 0.9).
static func barb_half(big_r: float, tail_w: float) -> float:
	return maxf(big_r, tail_w * 0.5 + 0.9)


## The seven corners of a Vhorr round's barbed head and tail, in world units: `p` is the head, `dir` the flight, `h` the head's
## half-width, `length` and `width` the tail, all in world units (screen pixels x px): the point, two barbs, two shoulders
## where the tail starts, two tail corners.
static func barb_polygon(p: Vector2, dir: Vector2, h: float, length: float, width: float) -> PackedVector2Array:
	var side := dir.orthogonal()
	var hw := width * 0.5
	return PackedVector2Array([
		p + dir * 0.9 * h,
		p - dir * h + side * h,
		p - dir * 0.5 * h + side * hw,
		p - dir * length + side * hw,
		p - dir * length - side * hw,
		p - dir * 0.5 * h - side * hw,
		p - dir * h - side * h,
	])


## Draw one bolt, point-defense, flak or shell round of Aurelian (`round_team` 0) or Vhorr (1) on `proj`. R is the head's half-width
## (head_radius()), the tail follows tail(). Aurelian: the tail line and a round bead at the head of radius max(R, tail width / 2
## + 0.6) (2 drawing commands). Vhorr: one seven-point polygon, a barbed head on the tail (barb_polygon()), and, where the
## head is 5 screen pixels across or more, a VOID triangle that hollows it (1 or 2 commands). `dim` is the round's colour strength
## (flak's tail is 0.9 of it); `minion` (1 or 0) makes every fixed size 0.85. Drawing only.
static func _draw_round(proj: Projectiles, k: int, p: Vector2, dir: Vector2, radius: float, col: Color, px: float, round_team: int, dim: float, minion: int) -> void:
	var size := minion_size(minion)
	var big_r := head_radius(k, radius, px, size)
	var t := tail(k, big_r, size)
	if round_team == Rules.HALCYON:
		var tail_col := Palette.with_alpha(col, 0.9 * dim) if k == Rules.W_FLAK else col
		proj.draw_line(p, p - dir * t.x * px, tail_col, t.y * px)
		proj.draw_circle(p, maxf(big_r, t.y * 0.5 + 0.6) * px, col)
		return
	var h := barb_half(big_r, t.y)
	proj.draw_colored_polygon(barb_polygon(p, dir, h * px, t.x * px, t.y * px), col)
	if 2.0 * h >= 5.0:
		var side := dir.orthogonal()
		var hp := h * px
		proj.draw_colored_polygon(PackedVector2Array([
			p + dir * 0.3 * hp,
			p - dir * 0.55 * hp + side * 0.45 * hp,
			p - dir * 0.55 * hp - side * 0.45 * hp,
		]), Palette.VOID)


## T-126b: the team's shape at the far end `b` of a beam (a Lance or ion beam of Aurelian or Vhorr) from `a`, whose core is `w` wide
## (world units) in `col`: Aurelian a bead of radius 2.2 screen pixels (1 command, 3 with the glow and the core); Vhorr a barb, a
## triangle (the end + 2.6 px ahead; the end - 2.4 px back, 2.8 px to either side) and, for a core 3 pixels wide or more, a VOID
## centre line 0.4 of the core's width along the beam (2 commands, 4 with the glow and the core). Drawing only.
static func _draw_beam_end(proj: Projectiles, a: Vector2, b: Vector2, round_team: int, w: float, col: Color, px: float) -> void:
	var span := b - a
	var dir := span / span.length() if span.length() > 0.0 else Vector2.RIGHT
	if round_team == Rules.HALCYON:
		proj.draw_circle(b, 2.2 * px, col)
		return
	var side := dir.orthogonal()
	proj.draw_colored_polygon(PackedVector2Array([
		b + dir * 2.6 * px,
		b - dir * 2.4 * px + side * 2.8 * px,
		b - dir * 2.4 * px - side * 2.8 * px,
	]), col)
	if w >= 3.0 * px:
		proj.draw_line(a, b, Palette.VOID, 0.4 * w)
