class_name OrderWheel
extends Control
## WHAT THIS IS: the Admiral's fleet wheel. Hold X while flying (field mode, or mode 3 with the command view open)
## and it opens under the mouse: eight orders in a ring, clockwise from the top (Attack-move here, Move here, Hold
## here, Stop, Defend here, Escort me, Retreat, Push this lane). All but Attack-move and Retreat work; those two are drawn
## dim with "later stage" under their name and give no order. Let go of the key over an order and it is given to the
## selected squadrons (every squadron when none is selected), aimed where the mouse was when the key went down; let
## go in the middle, or press Esc, and nothing is. A left click on an order gives it too. A tap of the key (not a
## hold) is the smart order (Hud.field_tap). Under the ring the build strip (BuildStrip) shows the ten hulls: while the
## wheel is open the digit keys (the home hull rows' keys) or a click on a cell queue that hull, Shift up to the cap and
## Alt with repeat, and the wheel stays open. This is "building through a small menu".
##
## HOW IT WORKS: a Control that covers the whole HUD while it is open (so no click goes through it to the guns) and is
## hidden otherwise. open_at() puts the middle of the wheel at the mouse, kept inside the window, and sets
## World.wheel_hold, which freezes the ship's aim and keeps the digit keys from routing energy. hovered() says which
## order is under the mouse (RadialMenu.slice_at from the mouse's offset from the middle; the dead zone is DEAD_R
## pixels). close_and_apply() gives the hovered order through Hud.field_command() and closes. The wheel closes by
## itself when the Admiral may no longer give a field order (Hud.field_ready(): docked, a panel open). The ring is
## drawn by RadialMenu, text 14 pixels.
##
## WHO USES IT: Hud.setup() makes it; HudInput opens it after WHEEL_OPEN_MS of the order key being held and closes it
## on the release or Esc; tests/field_wheel_check.gd.

## The radius (pixels) of the dead zone in the middle.
const DEAD_R := 44.0
## The outer radius (pixels) of the ring of orders.
const RING_R := 160.0
## The radius (pixels) the labels are centred on.
const LABEL_R := 118.0
## The width (pixels) a label's lines are centred in.
const LABEL_W := 120.0
## The wheel (ring and strip) stays at least this far (pixels) from every window edge.
const MARGIN := 12.0
## The space (pixels) between the ring and the build strip under it.
const STRIP_GAP := 12.0
## The text size (pixels).
const TEXT_SIZE := 14
## The orders in the ring, clockwise from the top: [the order's name, its label lines, whether it works now].
const SLICES := [
	["attack_move", ["Attack-move", "later stage"], false], ["move", ["Move here"], true], ["hold", ["Hold here"], true],
	["stop", ["Stop"], true], ["defend", ["Defend here"], true], ["escort", ["Escort me"], true],
	["retreat", ["Retreat", "later stage"], false], ["push", ["Push lane"], true],
]

## The HUD this belongs to.
var hud: Hud
## True while the wheel is open.
var is_open := false
## The build strip under the ring (shown while the wheel is open).
var strip: BuildStrip
## The middle of the wheel (pixels, in the HUD's own space).
var center := Vector2.ZERO
## The world point under the mouse when the order key was pressed: Move here goes there.
var press_aim := Vector2.ZERO


## Called by Hud.setup(): remember the HUD; the wheel starts hidden and covers the whole HUD when shown.
func setup(h: Hud) -> void:
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	z_index = 10
	visible = false
	strip = BuildStrip.new()
	add_child(strip)
	strip.setup(h)


## The space (pixels) the wheel needs under its middle: the ring, the gap and the build strip.
func room_below() -> float:
	return RING_R + STRIP_GAP + BuildStrip.strip_size().y


## Half the width (pixels) the wheel needs either side of its middle: the ring or the strip, whichever is wider.
func half_width() -> float:
	return maxf(RING_R, BuildStrip.strip_size().x * 0.5)


## The rectangle (pixels, the HUD's space) the ring takes: the square round the circle.
func ring_rect() -> Rect2:
	return Rect2(center - Vector2(RING_R, RING_R), Vector2(RING_R, RING_R) * 2.0)


## The rectangle (pixels, the HUD's space) the build strip takes, under the ring and centred on it.
func strip_rect() -> Rect2:
	var s := BuildStrip.strip_size()
	return Rect2(center + Vector2(-s.x * 0.5, RING_R + STRIP_GAP), s)


## Open the wheel under `at` (pixels) with `aim` as the mouse's world point at the press. The ring and the strip under
## it are kept MARGIN pixels inside the window.
func open_at(at: Vector2, aim: Vector2) -> void:
	var vp := hud.get_viewport_rect().size
	var lo_x := half_width() + MARGIN
	var lo_y := RING_R + MARGIN
	var hi_y := vp.y - MARGIN - room_below()
	center = Vector2(clampf(at.x, lo_x, maxf(lo_x, vp.x - lo_x)), clampf(at.y, lo_y, maxf(lo_y, hi_y)))
	press_aim = aim
	is_open = true
	visible = true
	strip.position = strip_rect().position
	strip.visible = true
	hud.world.wheel_hold = true
	# A middle drag that is still going would never see its release (the wheel takes it): it ends now.
	if hud.world.camera != null:
		hud.world.camera.end_drag()
	queue_redraw()


## Close the wheel without giving an order.
func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	strip.visible = false
	hud.world.wheel_hold = false


## Give the order under the mouse (nothing in the dead zone or off the wheel) and close.
func close_and_apply() -> void:
	if not is_open:
		return
	var hit := hovered()
	close()
	if hit.is_empty():
		return
	hud.field_command(str(hit["name"]), press_aim)


## What is under the mouse: {} for nothing, else {name, index, live} (see hit_at()).
func hovered() -> Dictionary:
	return hit_at(get_local_mouse_position())


## What is at point `p` (pixels, the HUD's space): {} for the dead zone and the outside, else the slice's {name, index,
## live}.
func hit_at(p: Vector2) -> Dictionary:
	var i := RadialMenu.slice_at(p - center, SLICES.size(), DEAD_R, RING_R)
	if i < 0:
		return {}
	var s: Array = SLICES[i]
	return {"name": str(s[0]), "index": i, "live": bool(s[2])}


## A click on the wheel (the wheel is open and covers the HUD): a left click on an order gives it, a left click
## elsewhere is swallowed. A middle click (the target button) marks the enemy under the pointer and the wheel stays
## open (HudInput.wheel_target(): no order is filed, no drag starts). A click of any other button is swallowed.
func _gui_input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventMouseButton):
		return
	# The order key's second binding is the mouse's fifth button: while this control covers the HUD it takes that
	# event too, so it passes it on (the release is what closes the wheel).
	if event.is_action("wheel"):
		hud.router.handle(event)
		accept_event()
		return
	var mb := event as InputEventMouseButton
	# The target button (the middle click) marks the enemy under the pointer and the wheel stays open: no order is filed.
	if hud.router.wheel_target(mb):
		accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	accept_event()
	click_at(mb.position, mb.shift_pressed, mb.alt_pressed)


## A left click at point `p` (the HUD's space) while the wheel is open: a cell of the build strip queues its hull
## (Shift: up to the cap, Alt: repeat) and the wheel stays open; an order of the ring is given and the wheel closes
## (the key may still be down: that hold is over); a click elsewhere is swallowed.
func click_at(p: Vector2, shift: bool = false, alt: bool = false) -> void:
	if not is_open:
		return
	var cell := BuildStrip.cell_at(p - strip_rect().position)
	if cell >= 0:
		queue_cell(cell, shift, alt)
		return
	var hit := hit_at(p)
	if hit.is_empty():
		return
	close()
	hud.router.end_hold()
	hud.field_command(str(hit["name"]), press_aim)


## Queue the hull of strip cell `i` (0 to 9) with the modifiers held, and say the answer in a pop-up (a refusal in the
## danger colour). Returns the text FieldOrders.queue_hull() gave.
func queue_cell(i: int, shift: bool, alt: bool) -> String:
	var text := FieldOrders.queue_hull(hud.world, hud.command_view, str(Ships.ORDER[i]), shift, alt)
	hud.toast(text, not FieldOrders.was_queued(text))
	return text


## A key press while the wheel is open: when it is one of the build strip's digits (the "wheel" rows of the key map,
## which follow the home hull rows) the hull is queued (Shift: to the cap, Alt: repeat) and the key is used up; the wheel
## stays open. The key is read like the command card's digits are: its place on the keyboard, no Ctrl or Meta. A key
## that is held down and repeats is used up and queues nothing more. True when the key was one of the digits.
func strip_key(k: InputEventKey) -> bool:
	if not is_open or k.ctrl_pressed or k.meta_pressed:
		return false
	for i in BuildStrip.COLS * BuildStrip.ROWS:
		for text in KeyMap.effective_keys("wheel", "hull_%d" % (i + 1)):
			var p := KeyCodes.parse(String(text))
			if bool(p["ok"]) and not bool(p["mouse"]) and k.physical_keycode == int(p["code"]):
				if k.pressed and not k.echo:
					queue_cell(i, k.shift_pressed, k.alt_pressed)
				return true
	return false


## Every frame while open: close it when a field order can no longer be given, else redraw (the order under the mouse
## follows the mouse).
func _process(_dt: float) -> void:
	if not is_open:
		return
	if not hud.field_ready():
		close()
		hud.router.end_hold()
		return
	queue_redraw()


## The label lines of every slice, and which of them are dim (an order that comes later), for RadialMenu.
func _labels() -> Array:
	var out: Array = []
	for s: Array in SLICES:
		out.append(s[1])
	return out


## Whether each slice is dim.
func _dim() -> Array:
	var out: Array = []
	for s: Array in SLICES:
		out.append(not bool(s[2]))
	return out


## The width (pixels) of the widest label line of slice `i` (what the fit check measures).
func label_width(i: int) -> float:
	var font := ThemeDB.fallback_font
	var w := 0.0
	for line: String in (SLICES[i] as Array)[1]:
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE).x)
	return w


## How wide (pixels) slice `i` is at the radius its label sits on: the chord of its arc there.
func chord_at_label() -> float:
	return 2.0 * LABEL_R * sin(PI / float(SLICES.size()))


## Draw the ring and its labels.
func _draw() -> void:
	if not is_open:
		return
	var hit := hovered()
	RadialMenu.draw_ring(self, center, _labels(), DEAD_R, RING_R, int(hit.get("index", -1)), _dim(), UiKit.accent(), ThemeDB.fallback_font, TEXT_SIZE, LABEL_R, LABEL_W)
