class_name ArcView
extends RefCounted
## WHAT THIS IS: the pilot's view of a ship of the line's guns: faint wedges that show where the
## turrets can shoot (their arc, out to the weapon's reach: the range bands), and an always-on
## mark at the reticle that says which side will fire and how many main guns bear on it.
##
## HOW IT WORKS: a "static library" with no memory of its own.
##   - wedges(ship, ctrl_down) returns one record per turret of a ship of the line (the heavy
##     cannons, the ion turrets and the light chasers; never the point defence or the flak):
##     {"id", "centre" (world angle), "half" (half the arc), "reach" (world units)}. It returns
##     none unless the Ctrl key is down or the cue (Ship.arc_cue_t) is running.
##   - mark(ship, aim) returns {"side": +1 or -1 (the side of the reticle), "bearing": how many
##     main (battery) guns of that side can turn to it, "dim": none can}.
##   - bearing_count() counts the battery guns of the whole ship that can turn to a point, and
##     cue_tick() turns "the count fell from one or more to none" into the 1 s cue.
##   - draw() paints both on a ship's own picture (ShipVisual calls it for the human's ship only).
## The mark never blinks: its brightness is one of two constant values.
## The wedge reach is the weapon's own reach times the ship's range multiplier, so the bands
## are the same numbers the hangar card lists (HangarShips.reach_line).
##
## WHO USES IT: ShipVisual._draw() (the drawing), PlayerController (cue_tick), the hangar card
## (not this class), and tests/broadside_check.gd.

## How long the wedges stay drawn after the reticle leaves every main arc, in seconds.
const CUE_TIME := 1.0
## How far past a gun's arc the reticle still counts as on it, in radians (the gun's own firing slack).
const BEAR_SLACK := 0.05
## The mark's brightness when a gun bears (constant: the mark never blinks).
const MARK_ALPHA := 0.9
## The mark's brightness when no gun bears (also constant).
const MARK_DIM_ALPHA := 0.35
## The wedge fill brightness.
const WEDGE_FILL := 0.07
## The wedge edge brightness.
const WEDGE_EDGE := 0.3


## The wedges to draw for `ship` (see HOW IT WORKS): empty unless `ctrl_down` or the ship's
## arcs cue is running. A ship that is not a ship of the line has none.
static func wedges(ship: Ship, ctrl_down: bool) -> Array:
	var out: Array = []
	if not ctrl_down and ship.arc_cue_t <= 0.0:
		return out
	if not bool(ship.def.get("side_battery", false)):
		return out
	for m: WeaponMount in ship.mounts:
		if m.mount_type != WeaponMount.TURRET:
			continue
		out.append({"id": m.id, "centre": ship.rotation + m.face, "half": m.arc, "reach": m.reach * ship.range_mult})
	return out


## The mark of `ship` for the reticle at `aim` (see HOW IT WORKS).
static func mark(ship: Ship, aim: Vector2) -> Dictionary:
	var side := ship.side_of(aim)
	var n := 0
	for m: WeaponMount in ship.mounts:
		if m.battery and int(signf(m.offset.y)) == side and _bears(ship, m, aim):
			n += 1
	return {"side": side, "bearing": n, "dim": n == 0}


## How many battery guns of `ship`, on either side, can turn to the point `aim`.
static func bearing_count(ship: Ship, aim: Vector2) -> int:
	var n := 0
	for m: WeaponMount in ship.mounts:
		if m.battery and _bears(ship, m, aim):
			n += 1
	return n


## One tick of the cue: `prev` is the count of the last tick, `aim` the reticle now. When the count
## falls from one or more to none, the ship's arcs cue starts (Ship.arc_cue_t = CUE_TIME); it is not
## restarted while the reticle stays out. Returns this tick's count, for the caller to keep.
static func cue_tick(ship: Ship, aim: Vector2, prev: int) -> int:
	var n := bearing_count(ship, aim)
	if prev > 0 and n == 0:
		ship.arc_cue_t = CUE_TIME
	return n


## Can battery gun `m` of `ship` turn to the point `aim` (inside its arc plus the firing slack)?
static func _bears(ship: Ship, m: WeaponMount, aim: Vector2) -> bool:
	var desired := Util.ang_diff(ship.rotation, (aim - m.world_pos()).angle())
	return m.in_swing(desired, BEAR_SLACK)


## Paint the arcs view and the mark on `ci` (a ShipVisual, whose own frame is the world turned back
## so that its x axis is the world's x axis and its origin is the ship), for the human's ship.
## `px` = world units per screen pixel.
static func draw(ci: CanvasItem, ship: Ship, px: float) -> void:
	if not bool(ship.def.get("side_battery", false)):
		return
	var col := Palette.team(ship.team)
	var origin := ship.global_position
	for w: Dictionary in wedges(ship, Input.is_physical_key_pressed(KEY_CTRL)):
		var m := _mount_of(ship, String(w["id"]))
		if m == null:
			continue
		var at := m.world_pos() - origin
		var pts := PackedVector2Array([at])
		var steps := 12
		for i in steps + 1:
			var a := float(w["centre"]) - float(w["half"]) + 2.0 * float(w["half"]) * float(i) / float(steps)
			pts.append(at + Vector2.from_angle(a) * float(w["reach"]))
		ci.draw_colored_polygon(pts, Palette.with_alpha(col, WEDGE_FILL))
		var edge := PackedVector2Array(pts)
		edge.append(at)
		ci.draw_polyline(edge, Palette.with_alpha(col, WEDGE_EDGE), 1.2 * px)
	# The mark at the reticle.
	var aim := ship.controls.aim_point
	var mk := mark(ship, aim)
	var alpha := MARK_DIM_ALPHA if bool(mk["dim"]) else MARK_ALPHA
	var mc := Palette.with_alpha(Palette.ICE, alpha)
	var p := aim - origin
	var side_dir := Vector2.from_angle(ship.rotation + float(mk["side"]) * PI * 0.5)
	# A short tick on the side that will fire, and one pip for each gun that bears.
	ci.draw_line(p + side_dir * 14.0 * px, p + side_dir * 26.0 * px, mc, 2.0 * px)
	var along := side_dir.rotated(PI * 0.5)
	for i in int(mk["bearing"]):
		ci.draw_circle(p + side_dir * 34.0 * px + along * (float(i) - float(int(mk["bearing"]) - 1) * 0.5) * 8.0 * px, 2.6 * px, mc)


## The mount of `ship` called `id`, or null.
static func _mount_of(ship: Ship, id: String) -> WeaponMount:
	for m: WeaponMount in ship.mounts:
		if m.id == id:
			return m
	return null
