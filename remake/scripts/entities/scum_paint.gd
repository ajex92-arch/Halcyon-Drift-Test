class_name ScumPaint
extends RefCounted
## WHAT THIS IS: the painter of the Scum ships, the pirate faction of the jungle: the Scum
## Raider (the Gunship camp, and the bigger den ships scaled up), the Scum Carrier and the Scum
## Fighter the Carrier launches. It only draws; it changes nothing in the game. The shapes are in
## ScumShapes and the colours are the SCUM_ constants of Palette.
##
## HOW IT WORKS:
##   - UnitVisual calls draw_den_ship() for a camp's ship and draw_fighter() for a Fighter,
##     from its own _draw(). They work from the unit's fields (rotation, flash, id, radius).
##   - The point lists of ScumShapes are turned into packed arrays once (prepare()) and turned
##     with the ship by one Transform2D times each array, so a frame makes no new lists but
##     one per piece. Every piece is one drawing command: the Raider is 12, the Carrier 11 and
##     the Fighter 4 (and the hull bar when the ship is hurt).
##   - Lines are n times `px` (world units per screen pixel) wide, so they keep their width on the
##     screen at any zoom; the Carrier's wider girders and tape keep a floor of 1.5 pixels.
##   - What moves is only the engine glow, from the match clock and the ship's id (no random
##     numbers, no particles): a few percent of size, a slow flutter and a faster one, a
##     different one for every ship so a den's ships do not pulse together.
##   - Zoomed far out (the Raider's radius under 1.4 percent of the view's width, complete under
##     1.0 percent: the widest play zoom, 6000 units across, is 0.83 percent) the Raider's
##     harpoon reaches further ahead of the nose and its edge turns bare metal, so the ship's
##     heading still reads when the whole ship is about 32 pixels across. In between it slides in,
##     and closer in the Raider is drawn exactly as designed. It reads only the camera's zoom
##     (_far()), never the match, and it makes no new drawing command (it copies the harpoon's two
##     point lists once a frame while it is on).
##   - A hit shows on the outline (it turns toward white and gets thicker), as on every other
##     unit; the fills never change.
##   - The guns' heads (TurretPaint, in the Scum style) are drawn by UnitVisual on top of the
##     sockets this painter leaves at each gun spot.
##   - Test only: DrawParts.outline off leaves the outlines out.
##
## WHO USES IT: UnitVisual (_draw_derelict() and the snub fighter's branch of _draw()). The hull
## gallery's tests read nothing from it.

## How big the heads of the guns are drawn, as a fraction of the ship's radius (world units per
## turret unit; a Raider of radius 50 gets 8).
const HEAD_FRACTION := 0.16
## The radius of the dark socket under each gun, in world units for a Raider of radius 50 (it
## grows with the bigger ships).
const SOCKET_R := 7.0
## The far look of the Raider (see _far()): at a ship radius of this share of the view's width or
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
## only, never the match.
static func _far(ci: CanvasItem, radius: float, px: float) -> float:
	var view_w := maxf(1.0, ci.get_viewport_rect().size.x * px)
	return clampf((FAR_FROM - radius / view_w) / (FAR_FROM - FAR_TO), 0.0, 1.0)


## The outline colour of a unit that flashes `flash` (0 = not hit just now).
static func _edge(flash: float) -> Color:
	return Palette.hit_edge(Palette.SCUM_EDGE, flash)


## The match time of unit `u` (0 before it has a world).
static func _time(u: Unit) -> float:
	return u.world.time if u.world != null else 0.0


## Draw the ship of den ship `d` (its camp type picks the Carrier or the Raider; the bigger
## den ships are Raiders scaled up) on `ci`, with a socket under each of its guns. `px` is world
## units per screen pixel, `flash` the hit flash strength, `phase` the unit's own number.
static func draw_den_ship(ci: CanvasItem, d: Derelict, px: float, flash: float, phase: float) -> void:
	prepare()
	if d.ctype == "carrier":
		_draw_carrier(ci, d, px, flash, phase)
	else:
		_draw_raider(ci, d, px, flash, phase)


## The Raider: a dented hulk dragging a harpoon down its right side, a hole punched in its left
## side with the frame showing, and one huge engine in the back left corner. `d.radius` over
## ScumShapes.RAIDER_RADIUS scales everything (1 for the Gunship).
static func _draw_raider(ci: CanvasItem, d: Derelict, px: float, flash: float, phase: float) -> void:
	var k := d.radius / ScumShapes.RAIDER_RADIUS
	var xf := Transform2D(d.rotation, Vector2(k, k), 0.0, Vector2.ZERO)
	var edge := _edge(flash)
	var edge_w := Palette.hit_width(2.0 * px, flash)
	# 1-2: the hull and its outline.
	ci.draw_colored_polygon(xf * _p("raider_hull"), Palette.SCUM_IRON)
	if DrawParts.outline:
		ci.draw_polyline(xf * _p("raider_hull_closed"), edge, edge_w, true)
	# 3-4: the harpoon, rust-grey with the dark red edge of the Vhorr blade it was. Zoomed far out
	# its point reaches further ahead of the nose and its edge turns bare metal, so the spike shows
	# against the dark and says which way the ship points.
	var far := _far(ci, d.radius, px)
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
		ci.draw_polyline(xf * blade_closed, blade_edge, 2.0 * px, true)
	# 5: the straps and the Scum mark, one command.
	ci.draw_multiline(xf * _p("raider_tape"), Palette.SCUM_HAZARD, 3.0 * px)
	# 6-7: the hole in the left side and the girders across it.
	ci.draw_colored_polygon(xf * _p("raider_hole"), Palette.SCUM_IRON_DARK)
	ci.draw_multiline(xf * _p("raider_girders"), Palette.with_alpha(Palette.SCUM_EDGE, 0.6), 1.5 * px)
	# 8-10: the engine bell, its glow and its flame.
	ci.draw_colored_polygon(xf * _p("raider_bell"), Palette.SCUM_PLATE)
	var f := flutter(_time(d), phase)
	ci.draw_circle(xf * ScumShapes.RAIDER_GLOW_AT, ScumShapes.RAIDER_GLOW_R * k * f, Palette.SCUM_GLOW)
	ci.draw_colored_polygon(xf * _p("raider_flame"), Palette.with_alpha(Palette.SCUM_GLOW, 0.45))
	# 11-12: a socket under each gun.
	_sockets(ci, d, k)


## The Carrier: a stolen Aurelian hull and a stolen Vhorr hull lashed side by side and crooked with
## girders; the gap between them is the launch channel, lit by guide lights, the gun stands on the
## forward bridge, and a rust beak is welded on the steel hull. The Carrier design's colours map
## onto the Scum family: its iron (bare girders) is SCUM_PLATE, its tan edge SCUM_EDGE, its rust
## SCUM_RUST, its hazard SCUM_HAZARD and its green SCUM_GLOW; the two hulls keep the stolen
## Aurelian and Vhorr colours.
static func _draw_carrier(ci: CanvasItem, d: Derelict, px: float, flash: float, phase: float) -> void:
	var k := d.radius / ScumShapes.CARRIER_RADIUS
	var xf := Transform2D(d.rotation, Vector2(k, k), 0.0, Vector2.ZERO)
	var edge := _edge(flash)
	var edge_w := Palette.hit_width(2.0 * px, flash)
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
	# 7-8: the two engine glows, set in the stern before the outlines go on.
	var t := _time(d)
	for e: Dictionary in ScumShapes.CARRIER_ENGINES:
		var f := flutter(t, phase + float(e["k"]))
		ci.draw_circle(xf * (e["at"] as Vector2), float(e["r"]) * k * f, Palette.with_alpha(Palette.SCUM_GLOW, 0.9))
	# 9-10: the outlines, after the glows, the girders and the beak, so the hull edge runs over
	# the rim of each nozzle and over the ends of the girders and the beak.
	if DrawParts.outline:
		ci.draw_polyline(xf * _p("carrier_steel_closed"), edge, edge_w, true)
		ci.draw_polyline(xf * _p("carrier_crescent_closed"), edge, edge_w, true)
	# 11: a socket under the gun.
	_sockets(ci, d, k)


## A dark socket under each of the ship's guns, where the head of the gun sits.
static func _sockets(ci: CanvasItem, d: Derelict, k: float) -> void:
	for m: WeaponMount in d.mounts:
		ci.draw_circle(m.offset.rotated(d.rotation), SOCKET_R * k, Palette.SCUM_IRON_DARK)


## The Scum Fighter: a fat engine bell glowing toxic green with a long bare needle out of its
## front and a yellow weld collar where they join. It is drawn at least 6 screen pixels long (the
## shape grows with `px` once it would be smaller), as the old dart was.
static func draw_fighter(ci: CanvasItem, s: SnubFighter, px: float, flash: float) -> void:
	prepare()
	var k := maxf(1.0, 6.0 * px / ScumShapes.FIGHTER_UNIT)
	var xf := Transform2D(s.rotation, Vector2(k, k), 0.0, Vector2.ZERO)
	# 1-2: the body and its outline.
	ci.draw_colored_polygon(xf * _p("fighter_body"), Palette.SCUM_IRON)
	if DrawParts.outline:
		ci.draw_polyline(xf * _p("fighter_body_closed"), _edge(flash), Palette.hit_width(1.2 * px, flash), true)
	# 3: the engine glow.
	var f := flutter(_time(s), float(s.uid) * 1.7)
	ci.draw_circle(xf * ScumShapes.FIGHTER_GLOW_AT, ScumShapes.FIGHTER_GLOW_R * k * f, Palette.SCUM_GLOW)
	# 4: the weld collar.
	var c: Array = ScumShapes.FIGHTER_COLLAR
	ci.draw_line(xf * (c[0] as Vector2), xf * (c[1] as Vector2), Palette.SCUM_HAZARD, maxf(2.0 * k, 2.0 * px))

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
