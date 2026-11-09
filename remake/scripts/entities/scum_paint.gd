class_name ScumPaint
extends RefCounted
## WHAT THIS IS: the painter of the Scum ships, the pirate faction of the jungle: the Scum
## Raider (the Gunship camp, and the bigger den ships scaled up), the Scum Carrier and the Scum
## Fighter the Carrier launches. It only draws; it changes nothing in the game. The shapes are in
## ScumShapes and the colours are the SCUM_ constants of Palette.
##
## HOW IT WORKS:
##   - UnitVisual draws a den ship or a Fighter in two parts. Its body is a kept picture (DrawCache):
##     drawn once, with the ship pointing along +x, on a node that turns with the ship, and drawn
##     again only when what it shows changes (the hit flash, whether the zoom is a close one, the
##     camera zoom by 2 percent, and for a Raider how far the far look has slid). What changes by
##     the frame is drawn over it on the painter's own picture, every frame: a Raider's engine glow,
##     flame and gun sockets, a Carrier's gun socket, a Fighter's engine glow. The Carrier is
##     three pictures in this order, because the design puts its outlines over its glows: the body
##     (kept), the two engine glows (by the frame), the outlines (kept).
##   - draw_raider_body(), draw_carrier_body(), draw_carrier_edge() and draw_fighter_body() are the
##     kept pictures; draw_raider_live(), draw_den_live(), draw_carrier_glow() and
##     draw_fighter_glow() are the parts drawn by the frame. The drawing order of the design is
##     kept exactly (the numbers in the comments are the design's steps).
##   - The point lists of ScumShapes are turned into packed arrays once (prepare()) and turned
##     with the ship by one Transform2D times each array, so a redraw makes no new lists but
##     one per piece. Every piece is one drawing command: the Raider is 12, the Carrier 11 and
##     the Fighter 4 (and the hull bar when the ship is hurt).
##   - Lines are n times `px` (world units per screen pixel) wide, so they keep their width on the
##     screen at any zoom; the Carrier's wider girders and tape keep a floor of 1.5 pixels. The
##     outlines are smooth (antialiased) at the close zooms and plain under zoom 0.5 (the usual play
##     zoom and further out), as every other hull's are.
##   - What moves is only the engine glow, from the match clock and the ship's id (no random
##     numbers, no particles): a few percent of size, a slow flutter and a faster one, a
##     different one for every ship so a den's ships do not pulse together.
##   - Zoomed far out (the Raider's radius under 1.4 percent of the view's width, complete under
##     1.0 percent: the widest play zoom, 6000 units across, is 0.83 percent) the Raider's
##     harpoon reaches further ahead of the nose and its edge turns bare metal, so the ship's
##     heading still reads when the whole ship is about 32 pixels across. In between it slides in,
##     and closer in the Raider is drawn exactly as designed. It reads only the camera's zoom
##     (far_look()), never the match, and it makes no new drawing command (it copies the harpoon's two
##     point lists while it is on). Its value is part of the body picture's key, so the picture is
##     drawn again while the zoom moves through the slide and not otherwise.
##   - A hit shows on the outline (it turns toward white and gets thicker), as on every other
##     unit; the fills never change.
##   - The guns' heads (TurretPaint, in the Scum style) are drawn by UnitVisual on top of the
##     sockets this painter leaves at each gun spot.
##   - Test only: DrawParts.outline off leaves the outlines out.
##
## WHO USES IT: UnitVisual (the kept pictures of a den ship and of a Fighter, and the parts drawn by
## the frame). The hull gallery's tests read nothing from it.
## How big the heads of the guns are drawn, as a fraction of the ship's radius (world units per
## turret unit; a Raider of radius 50 gets 8).
const HEAD_FRACTION := 0.16
## The radius of the dark socket under each gun, in world units for a Raider of radius 50 (it
## grows with the bigger ships).
const SOCKET_R := 7.0
## The far look of the Raider (see far_look()): at a ship radius of this share of the view's width or
## more, the Raider is drawn exactly as designed (close up).
const FAR_FROM := 0.014
## At a ship radius of this share of the view's width or less, the far look is complete (the usual
## play zoom, 6000 units across, shows a Raider of radius 50 at 0.0083). In between it grows smoothly.
const FAR_TO := 0.010

## The packed lists, made by prepare(): name -> PackedVector2Array.
static var _packed := {}


## Turn the lists of ScumShapes into packed arrays (once), and add the closed versions the
## outlines need.
static func prepare() -> void:
	if not _packed.is_empty():
		return
	for pair: Array in [
		["raider_hull", ScumShapes.RAIDER_HULL], ["raider_blade", ScumShapes.RAIDER_BLADE],
		["raider_tape", ScumShapes.RAIDER_TAPE], ["raider_hole", ScumShapes.RAIDER_HOLE],
		["raider_girders", ScumShapes.RAIDER_GIRDERS], ["raider_bell", ScumShapes.RAIDER_BELL],
		["raider_flame", ScumShapes.RAIDER_FLAME], ["carrier_steel", ScumShapes.CARRIER_STEEL],
		["carrier_crescent", ScumShapes.CARRIER_CRESCENT], ["carrier_girders", ScumShapes.CARRIER_GIRDERS],
		["carrier_tape", ScumShapes.CARRIER_TAPE], ["carrier_beak", ScumShapes.CARRIER_BEAK],
		["carrier_lights", ScumShapes.CARRIER_LIGHTS], ["fighter_body", ScumShapes.FIGHTER_BODY],
	]:
		_packed[pair[0]] = PackedVector2Array(pair[1])
	for key: String in ["raider_hull", "raider_blade", "carrier_steel", "carrier_crescent", "fighter_body"]:
		var closed: PackedVector2Array = _packed[key].duplicate()
		closed.append(closed[0])
		_packed[key + "_closed"] = closed


## The packed list called `name` (made by prepare()).
static func _p(name: String) -> PackedVector2Array:
	return _packed[name]


## The flutter of an engine glow, around 1 (0.7 to 1.0 of its size): `t` is the match time in
## seconds and `phase` a number that is different for every ship.
static func flutter(t: float, phase: float) -> float:
	return 0.85 + 0.10 * sin(t * 21.0 + phase) + 0.05 * sin(t * 5.3 + phase)


## How far zoomed out the view is for a ship of radius `radius` drawn on `ci`: 0 while the ship is
## big on the screen (it is drawn as designed), 1 once it is small (the Raider is about 32 pixels
## across at the widest play zoom), and a smooth slide in between. It reads the camera's zoom
## only, never the match. UnitVisual asks it once a frame for a Raider and hands the answer to the
## kept body picture as its "changing number" (see DrawCache), so the picture is drawn again while
## the zoom slides through the band and never otherwise.
static func far_look(ci: CanvasItem, radius: float, px: float) -> float:
	var view_w := maxf(1.0, ci.get_viewport_rect().size.x * px)
	return clampf((FAR_FROM - radius / view_w) / (FAR_FROM - FAR_TO), 0.0, 1.0)


## The outline colour of a unit that flashes `flash` (0 = not hit just now).
static func _edge(flash: float) -> Color:
	return Palette.hit_edge(Palette.SCUM_EDGE, flash)


## The match time of unit `u` (0 before it has a world).
static func _time(u: Unit) -> float:
	return u.world.time if u.world != null else 0.0


## The transform of a ship drawn with its nose along +x (a kept picture, which turns with the
## ship), scaled by `k`.
static func _upright(k: float) -> Transform2D:
	return Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)


## The id of the kept body picture of Scum unit `u` (UnitVisual keys its DrawCache on it).
static func body_id(u: Unit) -> String:
	if u is Derelict:
		return "scum_carrier" if (u as Derelict).ctype == "carrier" else "scum_raider"
	return "scum_fighter"


# --- the Raider ------------------------------------------------------------------------------

## The Raider's body on `ci` (its kept picture, the ship pointing along +x): a dented hulk dragging
## a harpoon down its right side, a hole punched in its left side with the frame showing, and the
## engine bell in the back left corner. `d.radius` over ScumShapes.RAIDER_RADIUS scales everything
## (1 for the Gunship). `far` is far_look() for this ship. The engine glow, the flame and the
## sockets are drawn over it every frame (draw_raider_live()).
static func draw_raider_body(ci: CanvasItem, d: Derelict, px: float, flash: float, far: float) -> void:
	prepare()
	var k := d.radius / ScumShapes.RAIDER_RADIUS
	var xf := _upright(k)
	var edge := _edge(flash)
	var edge_w := Palette.hit_width(2.0 * px, flash)
	# Smooth (antialiased) lines cost three drawing commands each; far out they are drawn plain.
	var smooth := DrawCache.is_close_px(px)
	# 1-2: the hull and its outline.
	ci.draw_colored_polygon(xf * _p("raider_hull"), Palette.SCUM_IRON)
	if DrawParts.outline:
		ci.draw_polyline(xf * _p("raider_hull_closed"), edge, edge_w, smooth)
	# 3-4: the harpoon, rust-grey with the dark red edge of the Vhorr blade it was. Zoomed far out
	# its point reaches further ahead of the nose and its edge turns bare metal, so the spike shows
	# against the dark and says which way the ship points.
	var blade := _p("raider_blade")
	var blade_closed := _p("raider_blade_closed")
	var blade_edge := Palette.VHORR_SEAM
	if far > 0.0:
		var tip := (ScumShapes.RAIDER_BLADE[0] as Vector2).lerp(ScumShapes.RAIDER_SPIKE_FAR, far)
		blade = blade.duplicate()
		blade[0] = tip
		blade_closed = blade_closed.duplicate()
		blade_closed[0] = tip
		blade_closed[blade_closed.size() - 1] = tip
		blade_edge = Palette.VHORR_SEAM.lerp(Palette.SCUM_EDGE, far)
	ci.draw_colored_polygon(xf * blade, Palette.SCUM_PLATE)
	if DrawParts.outline:
		ci.draw_polyline(xf * blade_closed, blade_edge, 2.0 * px, smooth)
	# 5: the straps and the Scum mark, one command.
	ci.draw_multiline(xf * _p("raider_tape"), Palette.SCUM_HAZARD, 3.0 * px)
	# 6-7: the hole in the left side and the girders across it.
	ci.draw_colored_polygon(xf * _p("raider_hole"), Palette.SCUM_IRON_DARK)
	ci.draw_multiline(xf * _p("raider_girders"), Palette.with_alpha(Palette.SCUM_EDGE, 0.6), 1.5 * px)
	# 8: the engine bell.
	ci.draw_colored_polygon(xf * _p("raider_bell"), Palette.SCUM_PLATE)


## The parts of the Raider that change by the frame or sit over the engine glow, drawn on `ci` (the
## painter's own picture, not turned with the ship, so the ship's rotation is applied here): the
## engine glow, which flutters with the match clock and `phase`, the faint flame behind the bell,
## and a socket under each gun.
static func draw_raider_live(ci: CanvasItem, d: Derelict, phase: float) -> void:
	prepare()
	var k := d.radius / ScumShapes.RAIDER_RADIUS
	var xf := Transform2D(d.rotation, Vector2(k, k), 0.0, Vector2.ZERO)
	# 9-10: the glow and the flame.
	var f := flutter(_time(d), phase)
	ci.draw_circle(xf * ScumShapes.RAIDER_GLOW_AT, ScumShapes.RAIDER_GLOW_R * k * f, Palette.SCUM_GLOW)
	ci.draw_colored_polygon(xf * _p("raider_flame"), Palette.with_alpha(Palette.SCUM_GLOW, 0.45))
	# 11-12: a socket under each gun.
	_sockets(ci, d, k)


# --- the Carrier -----------------------------------------------------------------------------

## The Carrier's body on `ci` (its kept picture, the ship pointing along +x): a stolen Aurelian hull
## and a stolen Vhorr hull lashed side by side and crooked with girders; the gap between them is the
## launch channel, lit by guide lights, the gun stands on the forward bridge, and a rust beak is
## welded on the steel hull. The Carrier design's colours map onto the Scum family: its iron (bare
## girders) is SCUM_PLATE, its tan edge SCUM_EDGE, its rust SCUM_RUST, its hazard SCUM_HAZARD and
## its green SCUM_GLOW; the two hulls keep the stolen Aurelian and Vhorr colours. The two engine
## glows go over this picture (draw_carrier_glow()) and the outlines over the glows
## (draw_carrier_edge()), so the hull edge runs over the rim of each nozzle, as designed.
static func draw_carrier_body(ci: CanvasItem, d: Derelict, px: float) -> void:
	prepare()
	var k := d.radius / ScumShapes.CARRIER_RADIUS
	var xf := _upright(k)
	var floor_w := 1.5 * px
	# 1-2: the two hulls.
	ci.draw_colored_polygon(xf * _p("carrier_steel"), Palette.AUREL_HULL)
	ci.draw_colored_polygon(xf * _p("carrier_crescent"), Palette.VHORR_SHADES[2])
	# 3-4: the girders and chain cross, then the tape and the Scum mark.
	ci.draw_multiline(xf * _p("carrier_girders"), Palette.SCUM_PLATE, maxf(5.0 * k, floor_w))
	ci.draw_multiline(xf * _p("carrier_tape"), Palette.SCUM_HAZARD, maxf(2.5 * k, floor_w))
	# 5-6: the beak and the guide lights.
	ci.draw_colored_polygon(xf * _p("carrier_beak"), Palette.SCUM_RUST)
	ci.draw_multiline(xf * _p("carrier_lights"), Palette.SCUM_GLOW, maxf(2.0 * k, floor_w))


## The Carrier's two engine glows on `ci` (a picture that turns with the ship, redrawn every frame,
## between the body and the outlines): they flutter with the match clock and `phase`.
static func draw_carrier_glow(ci: CanvasItem, d: Derelict, phase: float) -> void:
	var k := d.radius / ScumShapes.CARRIER_RADIUS
	var xf := _upright(k)
	# 7-8: the two engine glows, set in the stern before the outlines go on.
	var t := _time(d)
	for e: Dictionary in ScumShapes.CARRIER_ENGINES:
		var f := flutter(t, phase + float(e["k"]))
		ci.draw_circle(xf * (e["at"] as Vector2), float(e["r"]) * k * f, Palette.with_alpha(Palette.SCUM_GLOW, 0.9))


## The Carrier's outlines on `ci` (its second kept picture, over the glows, the ship pointing along
## +x): drawn after the glows, the girders and the beak, so the hull edge runs over the rim of each
## nozzle and over the ends of the girders and the beak.
static func draw_carrier_edge(ci: CanvasItem, d: Derelict, px: float, flash: float) -> void:
	prepare()
	var xf := _upright(d.radius / ScumShapes.CARRIER_RADIUS)
	var edge := _edge(flash)
	var edge_w := Palette.hit_width(2.0 * px, flash)
	# 9-10: the outlines.
	if DrawParts.outline:
		var smooth := DrawCache.is_close_px(px)
		ci.draw_polyline(xf * _p("carrier_steel_closed"), edge, edge_w, smooth)
		ci.draw_polyline(xf * _p("carrier_crescent_closed"), edge, edge_w, smooth)


# --- the parts every den ship draws by the frame -----------------------------------------------

## What a den ship draws on the painter's own picture, over its kept body (UnitVisual draws the
## guns' heads and the hull bar after it): a Raider's engine glow, flame and sockets, a Carrier's
## socket (its glows have a picture of their own, under its outlines).
static func draw_den_live(ci: CanvasItem, d: Derelict, phase: float) -> void:
	if d.ctype == "carrier":
		_sockets(ci, d, d.radius / ScumShapes.CARRIER_RADIUS)
	else:
		draw_raider_live(ci, d, phase)


## A dark socket under each of the ship's guns, where the head of the gun sits.
static func _sockets(ci: CanvasItem, d: Derelict, k: float) -> void:
	for m: WeaponMount in d.mounts:
		ci.draw_circle(m.offset.rotated(d.rotation), SOCKET_R * k, Palette.SCUM_IRON_DARK)


# --- the Fighter -------------------------------------------------------------------------------

## The scale of the Fighter's drawing at `px` world units per screen pixel: 1 at its true size, and
## bigger once it would be under 6 screen pixels long, as the old dart was.
static func _fighter_k(px: float) -> float:
	return maxf(1.0, 6.0 * px / ScumShapes.FIGHTER_UNIT)


## The Scum Fighter's body on `ci` (its kept picture, the ship pointing along +x): a fat engine bell
## with a long bare needle out of its front and a yellow weld collar where they join. It is drawn at
## least 6 screen pixels long (the shape grows with `px` once it would be smaller). The engine glow
## goes over it every frame (draw_fighter_glow()); the collar and the glow do not touch.
static func draw_fighter_body(ci: CanvasItem, px: float, flash: float) -> void:
	prepare()
	var k := _fighter_k(px)
	var xf := _upright(k)
	# 1-2: the body and its outline.
	ci.draw_colored_polygon(xf * _p("fighter_body"), Palette.SCUM_IRON)
	if DrawParts.outline:
		ci.draw_polyline(xf * _p("fighter_body_closed"), _edge(flash), Palette.hit_width(1.2 * px, flash), DrawCache.is_close_px(px))
	# 4: the weld collar.
	var c: Array = ScumShapes.FIGHTER_COLLAR
	ci.draw_line(xf * (c[0] as Vector2), xf * (c[1] as Vector2), Palette.SCUM_HAZARD, maxf(2.0 * k, 2.0 * px))


## The Scum Fighter's engine glow on `ci` (the painter's own picture, not turned with the ship, so
## the ship's rotation is applied here), flickering with the match clock and the ship's id.
static func draw_fighter_glow(ci: CanvasItem, s: SnubFighter, px: float) -> void:
	var k := _fighter_k(px)
	var xf := Transform2D(s.rotation, Vector2(k, k), 0.0, Vector2.ZERO)
	# 3: the engine glow.
	var f := flutter(_time(s), float(s.uid) * 1.7)
	ci.draw_circle(xf * ScumShapes.FIGHTER_GLOW_AT, ScumShapes.FIGHTER_GLOW_R * k * f, Palette.SCUM_GLOW)


## The Scum den ship's death, on top of what the unit does: a green flash from the engines (the
## explosion, in toxic green: its ring, its sparks and its boom), a puff of rusted plate (the ram or
## jaw tumbling away), a puff of gunmetal shards, and a few hazard-yellow scraps, the last to fade.
## Nothing red and nothing organic. `effects` is the match's Effects, `at` where the ship was,
## `radius` its radius.
static func burst(effects: Effects, at: Vector2, radius: float) -> void:
	effects.explosion(at, radius * 2.0, Palette.SCUM_GLOW)
	effects.puff(at, Palette.SCUM_RUST, 10, 150.0 + radius)
	effects.puff(at, Palette.SCUM_PLATE, 8, 110.0 + radius)
	effects.puff(at, Palette.SCUM_HAZARD, 5, 90.0)


## The Scum Fighter's death: a quiet green puff from the bell and one bare-metal splinter.
static func fighter_burst(effects: Effects, at: Vector2) -> void:
	effects.puff(at, Palette.SCUM_GLOW, 8)
	effects.puff(at, Palette.SCUM_EDGE, 2, 200.0)
