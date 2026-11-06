class_name ShipStatus
extends Control
## WHAT THIS IS: the readout of the human's own ship, at the bottom centre
## of the HUD: shields, hull, energy, energy routing, the ship's special
## ability, boost and speed. DESIGN.md A15.
##
## HOW IT WORKS: it draws itself with lines, arcs and text every frame
## while it is visible (its only child is the WingStrip, added by the HUD).
##   Left: the "shield diamond", four arcs around a small ship icon (nose
##   up), one arc per shield zone: front (top), rear (bottom), left, right.
##   An arc's thickness is the share of the shield that the current focus
##   gives that zone; how much of its length is filled is how full that
##   zone is. The focused zone gets an outline in the interface's highlight
##   colour (amber, or red when the human plays Vhorr), and a zone that just
##   broke flashes red. The icon's colour goes from green (full hull) to
##   red (no hull). Under it: the shield focus and its cooldown.
##   Right: hull / shields / energy bars, the four energy routing buttons
##   (keys 1-4) with a thin cooldown bar, the ability's state, then speed,
##   boost and warnings.
## The readout takes the mouse (T-114, mouse-only play): a left click on an
## energy button, on a shield zone or on the ship icon does what the key does,
## through HudInput.click() (the zone's arrow key again means balanced; the
## icon presses the focused zone's key, so it balances; it does nothing when
## the shields are balanced already). part_at() is the hit map; a press picks
## the part, the release acts only on the same part, and a slide off cancels. A
## left press anywhere on the readout is used up here, so it never fires the
## guns; the wheel still passes through to the camera's zoom. The right button
## over the readout no longer uses the ability (as over the wing strip).
##
## WHO USES IT: Hud makes it from scenes/ui/ship_status.tscn, gives it
## `hud` and calls
## set_ship() 10 times a second (null while there is no live ship). It
## reads Ship, ShieldZones (ship.shields) and the energy system
## (ship.energy).

## Width of the readout (pixels).
const W := 430.0
## Height of the readout (pixels).
const H := 132.0
## Centre of the shield diamond, from the readout's top-left (pixels).
const DIAMOND_C := Vector2(66, 66)
## Radius of the shield arcs (pixels).
const DIAMOND_R := 46.0
## Screen direction of each zone: front up, rear down, left, right.
## (Angles in radians: a full turn is 2 x PI; 0 points right, PI / 2
## points down.)
const ZONE_ANGLE := [-PI / 2.0, PI / 2.0, PI, 0.0]
## The energy routing modes in button order (keys 1 to 4).
const ROUTE_ORDER := [Rules.ENERGY_WEAPONS, Rules.ENERGY_SHIELDS, Rules.ENERGY_THRUSTERS, Rules.ENERGY_BALANCED]
## The text on each energy routing button.
const ROUTE_SHORT := {Rules.ENERGY_WEAPONS: "1 Weapons", Rules.ENERGY_SHIELDS: "2 Shields", Rules.ENERGY_THRUSTERS: "3 Engines", Rules.ENERGY_BALANCED: "4 Balanced"}
## The key actions behind the four energy buttons (same order as ROUTE_ORDER).
const ROUTE_ACTIONS := ["energy_weapons", "energy_shields", "energy_thrusters", "energy_balanced"]
## The key actions behind the four shield zones (same order as ZONE_ANGLE: front, rear, left, right).
const ZONE_ACTIONS := ["shield_front", "shield_rear", "shield_left", "shield_right"]
## Where the energy routing buttons start, from the readout's left edge (pixels).
const ROUTE_X := 140.0
## Where the energy routing buttons start, from the readout's top edge (pixels).
const ROUTE_Y := 55.0
## How tall the energy routing buttons are (pixels): 24, so a click lands easily (the WCAG 2.5.8 floor).
const ROUTE_H := 24.0
## The radius (pixels) of the click circle on the ship icon in the middle of the shield diamond (balance).
const CENTRE_R := 18.0
## How near the middle (pixels) a click on a zone can be. Between CENTRE_R and this, and outside the zone wedges, a
## click does nothing, so a small slip never picks a neighbour.
const ZONE_INNER := 24.0
## How far from the middle (pixels) a click on a zone can be.
const ZONE_OUTER := 62.0
## How far (degrees) either side of its direction a zone takes a click: the same 38 degrees the arcs are drawn with.
const ZONE_HALF_DEG := 38.0

## The ship we show, or null (then only the empty background is drawn).
var ship: Ship = null
## The font for all our text (Godot's built-in default font).
var font: Font
## The HUD (set by Hud.setup()): a click goes to its router (HudInput.click()).
var hud: Hud = null
## The part a left press started on ("" when none): the release acts only on the same part.
var _press_part := ""


## Called once when the node joins the scene: fix our size, take the mouse (a press on the
## readout is used up here and never fires the guns) and pick the font.
func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# `_get_tooltip` gives the words; the placeholder makes sure Godot starts the tooltip timer.
	tooltip_text = " "
	font = ThemeDB.fallback_font


## Show ship `s` (or nothing, with null) and redraw.
func set_ship(s: Ship) -> void:
	ship = s
	queue_redraw()


## Which clickable part is under point `p` (the readout's own pixels): "energy_0" to "energy_3" (the energy
## buttons), "shield_0" to "shield_3" (the zones: front, rear, left, right), "balance" (the ship icon) or "".
## The diamond's rule: within CENTRE_R of the middle is balance; between ZONE_INNER and ZONE_OUTER and within
## ZONE_HALF_DEG of a zone's direction is that zone; anything else (the diagonal gaps, the ring between) is
## nothing. The rear zone's wedge reaches down over the "Focus" line, so a click on those words picks the rear zone.
func part_at(p: Vector2) -> String:
	var w := W - ROUTE_X - 10.0
	var bw := (w - 9.0) / 4.0
	for i in 4:
		if Rect2(ROUTE_X + float(i) * (bw + 3.0), ROUTE_Y, bw, ROUTE_H).has_point(p):
			return "energy_%d" % i
	var v := p - DIAMOND_C
	var d := v.length()
	if d <= CENTRE_R:
		return "balance"
	if d >= ZONE_INNER and d <= ZONE_OUTER:
		for z in 4:
			if absf(angle_difference(v.angle(), float(ZONE_ANGLE[z]))) <= deg_to_rad(ZONE_HALF_DEG):
				return "shield_%d" % z
	return ""


## Do what a click on `part` (see part_at()) does: the same as the key, through HudInput.click(). The ship icon
## presses the key of the zone that is focused (the same side again means balanced), and does nothing when the
## shields are balanced already.
func click_part(part: String) -> void:
	if hud == null or ship == null or not is_instance_valid(ship):
		return
	if part.begins_with("energy_"):
		hud.router.click(String(ROUTE_ACTIONS[int(part.substr(7))]))
	elif part.begins_with("shield_"):
		hud.router.click(String(ZONE_ACTIONS[int(part.substr(7))]))
	elif part == "balance" and ship.shields.focus != Rules.FOCUS_BALANCED:
		hud.router.click(String(ZONE_ACTIONS[ship.shields.focus - 1]))


## A left press picks the part under it; the release acts only if it is on the same part (sliding off cancels).
## Left events are used up here so they never reach the guns; the wheel and the other buttons pass through as
## before (the wheel still zooms over the readout).
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_part = part_at(mb.position)
	else:
		var part := part_at(mb.position)
		if part != "" and part == _press_part:
			click_part(part)
		_press_part = ""
	accept_event()


## The words of the tooltip over a part (Godot asks with the pointer's place in our pixels).
func _get_tooltip(at_position: Vector2) -> String:
	var part := part_at(at_position)
	if part.begins_with("energy_"):
		var i := int(part.substr(7))
		return "Route energy: %s (%s)" % [String(ROUTE_SHORT[ROUTE_ORDER[i]]).substr(2).to_lower(), KeyMapText.key_of(String(ROUTE_ACTIONS[i]))]
	if part.begins_with("shield_"):
		var z := int(part.substr(7))
		return "Reinforce the %s shield (%s). Click it again to balance." % [String(Rules.FOCUS_NAMES[z + 1]).to_lower(), KeyMapText.key_of(String(ZONE_ACTIONS[z]))]
	if part == "balance":
		return "Balance the shields"
	return ""


## Every frame, while visible, ask Godot to redraw us (queue_redraw makes
## Godot call _draw() again).
func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## Draw the readout: the background box, then (with a live ship) the
## shield diamond and the bars.
func _draw() -> void:
	draw_style_box(UiKit.box(Palette.with_alpha(Palette.PANEL, 0.9), Palette.LINE, 0), Rect2(Vector2.ZERO, size))
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	_draw_diamond()
	_draw_bars()
	RoleHud.draw(self, ship)


## Draw the left half: four shield arcs, the ship icon and the focus line.
func _draw_diamond() -> void:
	var sh := ship.shields
	var c := DIAMOND_C
	for z in 4:
		# Step 1: thickness from this zone's share of the whole shield:
		# 3 px plus up to 14 px more (a zone with half the shield is 17 px).
		var share := sh.cap(z) / maxf(1.0, sh.max_total)
		var thick := 3.0 + 14.0 * share / 0.5
		var mid: float = ZONE_ANGLE[z]
		# Each arc covers 38 degrees either side of its direction.
		var half := deg_to_rad(38.0)
		var r := DIAMOND_R
		# Step 2: a faint full arc, then the filled part, grown from the
		# middle outward by how full the zone is (0..1).
		draw_arc(c, r, mid - half, mid + half, 18, Palette.with_alpha(Palette.SHIELD, 0.16), thick, true)
		var frac := clampf(sh.values[z] / sh.cap(z), 0.0, 1.0) if sh.cap(z) > 0.0 else 0.0
		if frac > 0.0:
			var col := Palette.SHIELD.lerp(Palette.ICE, 0.15)
			draw_arc(c, r, mid - half * frac, mid + half * frac, 18, col, thick, true)
		# Step 3: a red flash on a zone that just broke (flash fades to 0).
		if sh.flash[z] > 0.0:
			draw_arc(c, r, mid - half, mid + half, 18, Palette.with_alpha(Palette.CINDER, sh.flash[z] * 2.0), thick + 2.0, true)
		# Step 4: an outline in the highlight colour on the focused zone. Focus
		# numbers are zone + 1 (Rules.FOCUS_FRONT = 1 ... FOCUS_RIGHT = 4; 0 =
		# balanced).
		var focused := sh.focus != Rules.FOCUS_BALANCED and sh.focus - 1 == z
		if focused:
			draw_arc(c, r + thick * 0.5 + 3.0, mid - half, mid + half, 18, UiKit.accent(), 2.0, true)
	# Ship icon, nose up. Its colour slides ("lerps", short for linear
	# interpolation: mixes in a straight line) from green to red as the
	# hull drops.
	var pts := PackedVector2Array([c + Vector2(0, -15), c + Vector2(10, 11), c + Vector2(0, 6), c + Vector2(-10, 11)])
	var hull_col := Palette.REPAIR.lerp(Palette.CINDER, 1.0 - ship.hull_frac())
	draw_colored_polygon(pts, Palette.with_alpha(hull_col, 0.85))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.ICE, 1.0, true)
	# The focus line: in the highlight colour when focus can be changed, grey
	# with the seconds left while it is cooling down.
	var focus_text := "Focus: %s" % Rules.FOCUS_NAMES[sh.focus]
	if ship.focus_cd > 0.0:
		focus_text += " (%.1fs)" % ship.focus_cd
	_text(Vector2(8, H - 8), focus_text, 11, UiKit.accent() if ship.focus_cd <= 0.0 else Palette.MIST)


## Draw the right half, top to bottom: three bars, the energy routing
## buttons, the ability line and the speed line. (x, y) is where the next
## row starts, in pixels.
func _draw_bars() -> void:
	var x := 140.0
	var w := W - x - 10.0
	# The bars sit a little higher (hull 6, shields 22, energy 37) so the energy buttons
	# can be 24 tall, a target a click lands on, without moving anything below them.
	var y := 6.0
	# Step 1: hull bar. It is green from 62.5% hull up (1 / 1.6 = 0.625)
	# and slides to red as the hull drops toward 0.
	_bar(Rect2(x, y, w, 14), ship.hull_frac(), Palette.REPAIR.lerp(Palette.CINDER, clampf(1.0 - ship.hull_frac() * 1.6, 0.0, 1.0)))
	_text(Vector2(x + 4, y + 11), "Hull %d / %d" % [int(ship.hull), int(ship.hull_max)], 11, Palette.ICE, true)
	y += 16.0
	# Step 2: shield and energy bars.
	_bar(Rect2(x, y, w, 13), ship.shields.fraction(), Palette.SHIELD)
	_text(Vector2(x + 4, y + 10), "Shields %d / %d" % [int(ship.shields.total()), int(ship.shields.max_total)], 10, Palette.ICE, true)
	y += 15.0
	# The energy bar is amber for both teams: amber means energy here, it is not
	# the interface's highlight colour.
	_bar(Rect2(x, y, w, 13), ship.energy.fraction(), Palette.AMBER)
	_text(Vector2(x + 4, y + 10), "Energy %d / %d" % [int(ship.energy.value), int(ship.energy.max_value)], 10, Palette.ICE, true)
	y += 18.0
	# Step 3: energy routing: four buttons with 3-pixel gaps; the active
	# one is filled with the highlight colour. They are clickable (part_at()).
	var bw := (w - 9.0) / 4.0
	for i in 4:
		var mode: int = ROUTE_ORDER[i]
		var r := Rect2(x + float(i) * (bw + 3.0), y, bw, ROUTE_H)
		var on := ship.energy.mode == mode
		draw_rect(r, UiKit.accent() if on else Palette.INK)
		draw_rect(r, Palette.LINE, false, 1.0)
		_text(r.position + Vector2(5, 16), ROUTE_SHORT[mode], 11, Palette.VOID if on else Palette.MIST)
	# Under the buttons, a thin bar shrinks while routing is cooling down.
	# The full cooldown depends on ship size (Rules.ENERGY_COOLDOWN, seconds).
	if ship.energy_cd > 0.0:
		var total := float(Rules.ENERGY_COOLDOWN[Rules.size_index(ship.size_class)])
		var k := clampf(ship.energy_cd / total, 0.0, 1.0)
		draw_rect(Rect2(x, y + ROUTE_H + 1.0, w * k, 2), Palette.MIST)
	y += 32.0
	# Step 4: the ability: active (seconds left), cooling down, not enough
	# energy, or ready.
	var sp_label: String = ship.def.get("special_label", "Ability")
	var sp_text: String
	var sp_col := Palette.ICE
	if ship.special_t > 0.0:
		sp_text = "%s: active %.1fs" % [sp_label, ship.special_t]
		sp_col = UiKit.accent()
	elif ship.special_cd > 0.0:
		sp_text = "%s: %.1fs" % [sp_label, ship.special_cd]
		sp_col = Palette.MIST
	elif ship.energy.value < float(ship.def["special_energy"]):
		sp_text = "%s: needs %d energy" % [sp_label, int(ship.def["special_energy"])]
		sp_col = Palette.MIST
	else:
		sp_text = "%s: ready (right-click / G)" % sp_label
	_text(Vector2(x, y + 10), sp_text, 12, sp_col)
	y += 18.0
	# Step 5: speed (world units per second, now / top speed), then boost,
	# flight assist off, the ACE bonus timer and an EMP stall warning.
	var spd := "Speed %d / %d" % [int(ship.velocity.length()), int(ship.f_max)]
	var boost := ""
	if ship.boosting:
		boost = "  ·  BOOST"
	elif ship.can_boost:
		boost = "  ·  Shift boost"
	var extra := ""
	if not ship.assist:
		extra += "  ·  Assist OFF (V)"
	if ship.ace_t > 0.0:
		extra += "  ·  ACE %ds" % int(ship.ace_t)
	if ship.emp_t > 0.0:
		extra += "  ·  ENGINES STALLED"
	if ship.slip:
		extra += "  ·  SLIPSTREAM"
	_text(Vector2(x, y + 10), spd + boost + extra, 11, Palette.MIST)


## Draw one bar in rectangle `r`: a dark background, the filled part
## (`frac` = 0..1 of the width) in colour `col`, and a thin border.
func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Palette.INK)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Palette.LINE, false, 1.0)


## Draw text `t` at point `p` (its left end, on the text's baseline), size
## `sz` pixels, colour `col`. With `shadow`, a dark copy is drawn 1 pixel
## down-right first so it reads on top of a bar.
func _text(p: Vector2, t: String, sz: int, col: Color, shadow: bool = false) -> void:
	if shadow:
		draw_string(font, p + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Palette.VOID)
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
