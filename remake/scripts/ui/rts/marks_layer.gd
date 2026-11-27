class_name MarksLayer
extends Node2D
## WHAT THIS IS: the small upgrade marks on ships: next to each of your ships that research has upgraded, one short amber stripe for
## each armor level on its left side and one short ice-blue tick for each drive level on its right side. They are drawn by this one
## layer, in one pass, at close zoom only; no ship gets a node, and no hull changes its size or its picture.
##
## HOW IT WORKS: CommandOverlay makes one beside the far-zoom icon layer. Every frame it works out the camera zoom and whether the
## icon layer is on; while the icons are on (the view is wide) it holds nothing. Otherwise it takes a snapshot, one record for each
## ship of the viewer's team that is alive, seen, a ship (not a minion, not the mothership), has at least one level for its class
## and is drawn big enough on the screen (its radius times the zoom is at least MARK_MIN_RADIUS_PX), and draws the records once. A
## mark sits PAD_PX screen pixels beyond the hull's drawn half-length, measured the way the ship's own painter does (the hull's
## length times the zoom, never less than ShipVisual.MIN_PX), so it never touches the hull's own drawing. Every size is in screen
## pixels (the layer draws 1 / zoom world units to the pixel), and the marks turn with the ship. The levels are the team's
## (TeamState.drive_level and armor_level) for the ship's class (Tech.TIERS of its size); only the viewer's own team carries marks.
## It asks for a redraw only while it has records or had records the frame before. It only reads the match: the simulation never
## reads it; no timer, no tween, no input.
##
## WHO USES IT: CommandOverlay (makes it), tests/rts_tour_research.gd and tests/research_data_check.gd.

## Screen pixels between the hull's drawn half-length and the near edge of a mark.
const PAD_PX := 3.0
## The long side of a mark, in screen pixels (an armor stripe lies along the hull, a drive tick across it).
const MARK_LONG_PX := 5.0
## The short side of a mark, in screen pixels.
const MARK_SHORT_PX := 2.0
## The gap between two marks of the same flank, in screen pixels.
const MARK_GAP_PX := 1.5
## A ship carries marks only when its radius on the screen (its radius times the camera zoom) is at least this many pixels.
const MARK_MIN_RADIUS_PX := 6.0

## The game world (set by setup()).
var world: World
## The overlay that owns this layer (set by setup()).
var overlay: CommandOverlay
## The snapshot of what the next _draw() draws: records [x, y, heading, side_px, armor_marks, drive_marks, uid] (side_px is the
## distance from the ship's middle to the near edge of a mark, in screen pixels).
var _records: Array = []
## The camera zoom at the snapshot (the marks are drawn 1 / zoom world units to the pixel).
var _zoom := 1.0
## Did the last snapshot hold records (so the frame after them still redraws once, to clear)?
var _had := false
## How many ships the last _draw() drew marks for (the check reads it).
var marks_drawn := 0


## The marks for a class whose team has `ts`: x = armor stripes (the armor levels of class `tier`), y = drive ticks (its drive
## levels). The one rule that turns levels into marks.
static func counts(ts: TeamState, tier: String) -> Vector2i:
	return Vector2i(ts.armor_level(tier), ts.drive_level(tier))


## Remember the world and the overlay (CommandOverlay.setup() makes the layer and calls this).
func setup(w: World, ov: CommandOverlay) -> void:
	world = w
	overlay = ov


## Every frame: take the snapshot (empty while the icons are on) and ask for a redraw while there is something to draw or to clear.
func _process(_dt: float) -> void:
	if world == null or world.camera == null:
		return
	_zoom = maxf(0.0001, world.camera.zoom.x)
	if IconLayer.active:
		_records.clear()
	else:
		_snapshot()
	var has := not _records.is_empty()
	if has or _had:
		queue_redraw()
	_had = has


## The records to draw: see _records.
func _snapshot() -> void:
	_records.clear()
	var team := world.human_team
	var ts: TeamState = world.teams[team]
	var by_tier := {}
	for tier: String in Tech.TIERS:
		by_tier[tier] = counts(ts, tier)
	for u: Unit in world.units:
		if u == null or not is_instance_valid(u) or u.kind != Unit.K_SHIP or u.team != team or not u.alive or not u.visible:
			continue
		var ship := u as Ship
		if ship == null or u.radius * _zoom < MARK_MIN_RADIUS_PX:
			continue
		var c: Vector2i = by_tier[Tech.TIERS[u.size_class]]
		if c.x + c.y == 0:
			continue
		var length := float(ship.def["length"]) if ship.def.has("length") else u.radius * 2.0
		var half_px := maxf(length * _zoom, ShipVisual.MIN_PX) * 0.5
		_records.append([u.global_position.x, u.global_position.y, ship.rotation, half_px + PAD_PX, c.x, c.y, u.uid])


## The snapshot (the checks read it).
func records() -> Array:
	return _records


## Draw every record once: the armor stripes on the left flank (amber), the drive ticks on the right flank (ice blue), each row
## centred along the hull.
func _draw() -> void:
	marks_drawn = 0
	var inv := 1.0 / _zoom
	for r: Array in _records:
		draw_set_transform(Vector2(float(r[0]), float(r[1])), float(r[2]), Vector2(inv, inv))
		var side := float(r[3])
		var armor := int(r[4])
		var drive := int(r[5])
		for i in armor:
			var x := (float(i) - float(armor - 1) * 0.5) * (MARK_LONG_PX + MARK_GAP_PX)
			draw_rect(Rect2(Vector2(x - MARK_LONG_PX * 0.5, -side - MARK_SHORT_PX), Vector2(MARK_LONG_PX, MARK_SHORT_PX)), Palette.AMBER)
		for i in drive:
			var x := (float(i) - float(drive - 1) * 0.5) * (MARK_SHORT_PX + MARK_GAP_PX)
			draw_rect(Rect2(Vector2(x - MARK_SHORT_PX * 0.5, side), Vector2(MARK_SHORT_PX, MARK_LONG_PX)), Palette.ICE)
		marks_drawn += 1
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
