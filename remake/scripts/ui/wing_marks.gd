class_name WingMarks
extends Node2D
## WHAT THIS IS: the marks the pilot's wing puts on the map: two small corner brackets around the
## target of an attack or the ship being guarded, and, while the order key is held, a thin line from
## each wingman to the leader and a small ring where each wingman's place is. Nothing is drawn
## otherwise.
##
## HOW IT WORKS: a Node2D the HUD adds to the World next to the Admiral's overlay, drawn just under it
## (z_index 19). It reads the human pilot's wing record (the order that stands, the formation) and
## draws in world coordinates, with every size multiplied by `px` (how many world units one screen
## pixel covers, 1 / camera zoom) so the marks keep their size on the screen at any zoom. It asks to be
## redrawn every frame only while there is something to show, and once more when the last mark goes.
## The brackets are one drawing command (draw_multiline), the lines one, each ring one: a few commands.
##
## WHO USES IT: Hud.setup() makes it; WingWheel sets World.wheel_hold, which this reads for the held
## marks. It only reads the game.

## How long (screen pixels) each leg of a corner bracket is.
const BRACKET_PX := 8.0
## The alpha of the brackets.
const BRACKET_ALPHA := 0.8
## The alpha of the lines from the wingmen to the leader.
const LINE_ALPHA := 0.4
## The radius (screen pixels) of the ring that marks a place in the shape.
const RING_PX := 6.0
## Corners are drawn this many screen pixels outside the unit's body.
const PAD_PX := 6.0

## The HUD this belongs to.
var hud: Hud
## True when the last frame drew something (so one more redraw clears it).
var _drawn := false


## Called by Hud.setup(): remember the HUD and sit just under the Admiral's overlay.
func setup(h: Hud) -> void:
	hud = h
	z_index = 19


## Redraw while there is something to show (and once more when it goes).
func _process(_dt: float) -> void:
	var want := _wants()
	if want or _drawn:
		queue_redraw()
	_drawn = want


## Is there a mark to draw now: a standing attack or guard, or the order key held?
func _wants() -> bool:
	if hud == null or hud.world == null or hud.world.human == null or hud.world.human_role != "pilot":
		return false
	var lead := Squads.lead_record(hud.world, hud.world.human.team, hud.world.human.slot)
	if lead == null:
		return false
	if hud.world.wheel_hold:
		return true
	var kind := str(lead.order.get("kind", ""))
	return kind == OrderKinds.ATTACK or kind == OrderKinds.GUARD


## Draw the brackets and, while the key is held, the lines and rings.
func _draw() -> void:
	if not _wants():
		return
	var w := hud.world
	var lead := Squads.lead_record(w, w.human.team, w.human.slot)
	var px := 1.0 / maxf(w.camera.zoom.x, 0.0001)
	var kind := str(lead.order.get("kind", ""))
	if kind == OrderKinds.ATTACK or kind == OrderKinds.GUARD:
		var u := w.orders.unit_by_uid(int(lead.order.get("target", 0)))
		if u != null:
			_brackets(u, px)
	if w.wheel_hold:
		_held_marks(lead, px)


## Two opposite corner brackets around unit `u`, 8 screen pixels long, in ICE.
func _brackets(u: Unit, px: float) -> void:
	var half := (u.radius + PAD_PX * px) if not (u is Mothership) else ((u as Mothership).half_len + PAD_PX * px)
	var c := u.global_position
	var leg := BRACKET_PX * px
	var tl := c + Vector2(-half, -half)
	var br := c + Vector2(half, half)
	var pts := PackedVector2Array([
		tl, tl + Vector2(leg, 0.0), tl, tl + Vector2(0.0, leg),
		br, br + Vector2(-leg, 0.0), br, br + Vector2(0.0, -leg),
	])
	draw_multiline(pts, Palette.with_alpha(Palette.ICE, BRACKET_ALPHA), 1.5 * px)


## While X is held: a line from each wingman to the leader (ICE, faint) and a ring at each place in LINE.
func _held_marks(lead: Squad, px: float) -> void:
	var w := hud.world
	var leader := Squads.leader_ship(w, lead)
	if leader == null:
		return
	var s := SquadEngine.spacing(leader.radius)
	var shape := SquadEngine.effective_formation(lead.formation, SquadEngine.in_jungle(w, leader.global_position))
	var heading := float(lead.engine.get("hs", leader.rotation))
	var lines := PackedVector2Array()
	for rec: Squad in Squads.wing_records(w, lead.wing_id):
		var crew := Squads.crew_of(w, rec)
		if crew == null:
			continue
		var slot_at := SquadEngine.slot_target(leader.global_position, leader.velocity, heading, shape, rec.slot_index, s)
		draw_arc(slot_at, RING_PX * px, 0.0, TAU, 12, Palette.LINE, 1.0 * px, true)
		var ship: Variant = crew.ship
		if ship != null and is_instance_valid(ship) and (ship as Ship).alive:
			lines.append((ship as Ship).global_position)
			lines.append(leader.global_position)
	if not lines.is_empty():
		draw_multiline(lines, Palette.with_alpha(Palette.ICE, LINE_ALPHA), 1.0 * px)
