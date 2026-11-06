class_name WingWheel
extends Control
## WHAT THIS IS: the order wheel of the pilot's wing. Hold X and it opens under the mouse: six orders in a
## ring (Form on me, Cover me, Attack my target, Guard that ship, Hold here, Regroup), and under it four
## chips for the shapes (Wedge, Line, Column, Loose) and three for the fire settings (At will, Return fire,
## Hold fire). Let go of the key over an order or a chip and it is given; let go in the middle, or press
## Esc, and nothing is. A left click on an order or a chip gives it too. The "Wing" button on the strip opens
## the same wheel as a click wheel (the next click gives an order or closes it).
##
## HOW IT WORKS: a Control that covers the whole HUD while it is open (so no click goes through it to the
## guns) and is hidden otherwise. open_at() puts the middle of the wheel at the mouse (kept 110 pixels from
## the window's edges and high enough that the chips fit) and sets World.wheel_hold, which freezes the
## pilot's aim. hovered() says which order or chip is under the mouse from the mouse's distance and angle
## from the middle (the dead zone is 36 pixels). close_and_apply() gives the hovered order through
## Hud.wing_command() and closes. Everything is drawn in code in _draw(): the ring slices in the panel
## colour, the one under the mouse in the interface colour, text 14 pixels, the wing's current shape and fire
## setting outlined in the interface colour.
##
## WHO USES IT: Hud.setup() makes it; HudInput opens it on the press of the order key (after 130 ms) and
## closes it on the release; the strip's Wing button toggles it.

## The radius (pixels) of the dead zone in the middle.
const DEAD_R := 36.0
## The outer radius (pixels) of the ring of orders.
const RING_R := 100.0
## The wheel's middle stays at least this far (pixels) from every window edge.
const EDGE_MARGIN := 110.0
## Where the shape chips sit: this far (pixels) under the middle.
const SHAPE_Y := 112.0
## Where the fire chips sit: this far (pixels) under the middle.
const FIRE_Y := 142.0
## The size (pixels) of a shape chip.
const SHAPE_CHIP := Vector2(64.0, 24.0)
## The size (pixels) of a fire chip.
const FIRE_CHIP := Vector2(84.0, 24.0)
## The space (pixels) between two chips.
const CHIP_GAP := 6.0
## The text size (pixels).
const TEXT_SIZE := 14
## How many segments make the curve of a slice's edge.
const ARC_STEPS := 8
## The orders in the ring, clockwise from the top: [the gesture's name, its label lines].
const SLICES := [
	["follow", ["Form on", "me"]], ["cover", ["Cover me"]], ["attack", ["Attack", "my target"]],
	["guard", ["Guard", "that ship"]], ["hold", ["Hold here"]], ["regroup", ["Regroup"]],
]

## The HUD this belongs to.
var hud: Hud
## True while the wheel is open.
var is_open := false
## True when the Wing button opened it (a click wheel): it stays until a click.
var click_mode := false
## The middle of the wheel (pixels, in the HUD's own space).
var center := Vector2.ZERO
## The world point under the reticle when the order key was pressed: "Attack my target" and "Guard that
## ship" pick near it.
var press_aim := Vector2.ZERO


## Called by Hud.setup(): remember the HUD; the wheel starts hidden and covers the whole HUD when shown.
func setup(h: Hud) -> void:
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	z_index = 10
	visible = false


## Open the wheel under `at` (pixels) with `aim` as the reticle's world point at the press. `clicks` is
## true for the click wheel the Wing button opens.
func open_at(at: Vector2, aim: Vector2, clicks: bool = false) -> void:
	var vp := hud.get_viewport_rect().size
	var low := minf(vp.y - EDGE_MARGIN, vp.y - (FIRE_Y + FIRE_CHIP.y + 8.0))
	center = Vector2(clampf(at.x, EDGE_MARGIN, maxf(EDGE_MARGIN, vp.x - EDGE_MARGIN)), clampf(at.y, EDGE_MARGIN, maxf(EDGE_MARGIN, low)))
	press_aim = aim
	click_mode = clicks
	is_open = true
	visible = true
	hud.world.wheel_hold = true
	queue_redraw()


## Close the wheel without giving an order.
func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	hud.world.wheel_hold = false


## Give the order under the mouse (nothing in the dead zone or off the wheel) and close.
func close_and_apply() -> void:
	if not is_open:
		return
	var hit := hovered()
	close()
	if hit.is_empty():
		return
	hud.wing_command(str(hit["name"]), int(hit.get("arg", 0)), press_aim)


## What is under the mouse: {} for nothing, else {name, arg}: an order of the ring ("follow", "cover",
## "attack", "guard", "hold", "regroup"), a shape chip ("formation", the shape's value) or a fire chip ("fire", its value).
func hovered() -> Dictionary:
	return hit_at(get_local_mouse_position())


## What is at point `p` (pixels, the HUD's space), as hovered() says.
func hit_at(p: Vector2) -> Dictionary:
	var d := p - center
	var r := d.length()
	if r >= DEAD_R and r <= RING_R:
		# The angle clockwise from the top; slice 0 is centred on the top.
		var a := fposmod(rad_to_deg(d.angle()) + 90.0 + 30.0, 360.0)
		return {"name": str((SLICES[int(a / 60.0) % 6] as Array)[0]), "arg": 0}
	for i in Formations.COUNT:
		if shape_chip(i).has_point(p):
			return {"name": "formation", "arg": i}
	for i in 3:
		if fire_chip(i).has_point(p):
			return {"name": "fire", "arg": i}
	return {}


## The rectangle of shape chip `i` (pixels, the HUD's space).
func shape_chip(i: int) -> Rect2:
	var total := SHAPE_CHIP.x * float(Formations.COUNT) + CHIP_GAP * float(Formations.COUNT - 1)
	return Rect2(center + Vector2(-total * 0.5 + float(i) * (SHAPE_CHIP.x + CHIP_GAP), SHAPE_Y), SHAPE_CHIP)


## The rectangle of fire chip `i` (pixels, the HUD's space).
func fire_chip(i: int) -> Rect2:
	var total := FIRE_CHIP.x * 3.0 + CHIP_GAP * 2.0
	return Rect2(center + Vector2(-total * 0.5 + float(i) * (FIRE_CHIP.x + CHIP_GAP), FIRE_Y), FIRE_CHIP)


## A click on the wheel (the wheel is open and covers the HUD): left click on an order or a chip gives it;
## a click elsewhere closes a click wheel and is swallowed by a held one.
func _gui_input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventMouseButton):
		return
	# The order key's second binding is the mouse's fifth button: while this control covers the HUD it
	# takes that event too, so it passes it on (the release is what closes the wheel).
	if event.is_action("wheel"):
		hud.router.handle(event)
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	accept_event()
	click_at(mb.position)


## A left click at point `p` (the HUD's space) while the wheel is open: an order or a chip is given and the
## wheel closes; a click elsewhere closes a click wheel and is swallowed by a held one.
func click_at(p: Vector2) -> void:
	var hit := hit_at(p)
	if hit.is_empty():
		if click_mode:
			close()
		return
	close()
	hud.wing_command(str(hit["name"]), int(hit.get("arg", 0)), press_aim)


## Redraw every frame while open (the hovered order follows the mouse).
func _process(_dt: float) -> void:
	if is_open:
		queue_redraw()


## Draw the ring, the chips and their labels.
func _draw() -> void:
	if not is_open:
		return
	var font := ThemeDB.fallback_font
	var hit := hovered()
	var accent := UiKit.accent()
	for i in 6:
		var mid := deg_to_rad(-90.0 + 60.0 * float(i))
		var a0 := mid - deg_to_rad(30.0)
		var a1 := mid + deg_to_rad(30.0)
		var pts := PackedVector2Array()
		for k in ARC_STEPS + 1:
			pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / float(ARC_STEPS))) * RING_R)
		for k in ARC_STEPS + 1:
			pts.append(center + Vector2.from_angle(lerpf(a1, a0, float(k) / float(ARC_STEPS))) * DEAD_R)
		draw_colored_polygon(pts, Palette.with_alpha(Palette.PANEL, 0.85))
		if str(hit.get("name", "")) == str((SLICES[i] as Array)[0]):
			draw_colored_polygon(pts, Palette.with_alpha(accent, 0.35))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Palette.LINE, 1.5, true)
		# The label: one or two lines, centred in the slice.
		var lines: Array = (SLICES[i] as Array)[1]
		var at := center + Vector2.from_angle(mid) * ((DEAD_R + RING_R) * 0.5)
		for j in lines.size():
			var y := at.y + 5.0 + (float(j) - float(lines.size() - 1) * 0.5) * 16.0
			draw_string(font, Vector2(at.x - 40.0, y), str(lines[j]), HORIZONTAL_ALIGNMENT_CENTER, 80.0, TEXT_SIZE, Palette.ICE)
	# The chips: shapes, then fire settings.
	var lead := Squads.lead_record(hud.world, hud.world.human.team, hud.world.human.slot) if hud.world.human != null else null
	var shape := lead.formation if lead != null else -1
	var fire := lead.fire_stance if lead != null else -1
	for i in Formations.COUNT:
		var r := shape_chip(i)
		var on := str(hit.get("name", "")) == "formation" and int(hit.get("arg", -1)) == i
		draw_rect(r, Palette.with_alpha(accent, 0.35) if on else Palette.with_alpha(Palette.PANEL, 0.85))
		draw_rect(r, accent if i == shape else Palette.LINE, false, 1.5 if i == shape else 1.0)
		_shape_dots(r, i)
		draw_string(font, r.position + Vector2(0.0, 16.0), Formations.formation_name(i), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, TEXT_SIZE, Palette.ICE)
	for i in 3:
		var r2 := fire_chip(i)
		var on2 := str(hit.get("name", "")) == "fire" and int(hit.get("arg", -1)) == i
		draw_rect(r2, Palette.with_alpha(accent, 0.35) if on2 else Palette.with_alpha(Palette.PANEL, 0.85))
		draw_rect(r2, accent if i == fire else Palette.LINE, false, 1.5 if i == fire else 1.0)
		draw_string(font, r2.position + Vector2(0.0, 16.0), str(Formations.FIRE_NAMES[i]), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x, TEXT_SIZE, Palette.ICE)


## Three 3 pixel dots along the bottom of shape chip `r` showing the shape (the places of shape `shape`
## seen from above, the leader's heading up: further behind is lower).
func _shape_dots(r: Rect2, shape: int) -> void:
	var c := r.position + Vector2(r.size.x * 0.5, 18.0)
	for i in 3:
		var o := Formations.slot(shape, i)
		draw_circle(c + Vector2(o.y * 3.0, -o.x * 0.9), 1.5, Palette.MIST)
