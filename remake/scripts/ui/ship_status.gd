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
##   boost and warnings. The energy bar shows the hard part (blocked shield
##   damage the battery holds) in teal from its right end, with "held" in its
##   text, and "Overloaded 4.2 s" or "Venting" on its right; the Vent button
##   sits at the bottom right, under the speed line, so that no line of text reaches it. The ability
##   line says "offline" (not "ready") during a lockout or a Vent.
## The readout takes the mouse (T-114, mouse-only play): a left click on an
## energy button, on a shield zone or on the ship icon does what the key does,
## through HudInput.click() (the zone's arrow key again means balanced; the
## icon presses the focused zone's key, so it balances; it does nothing when
## the shields are balanced already). part_at() is the hit map; a press picks
## the part, the release acts only on the same part, and a slide off cancels. A
## left press anywhere on the readout is used up here, so it never fires the
## guns; the wheel still passes through to the camera's zoom. The right button
## over the readout no longer uses the ability (as over the wing strip).
## RT7: while the Admiral's ship is under fire (a hull hit under 3 seconds ago, FIRE_EDGE_S) the readout wears a steady 2 pixel
## edge in the danger colour, the mark of the "Under Fire!" alert (set from state in _process(); no blink, nothing times it).
##
## WHO USES IT: Hud makes it from scenes/ui/ship_status.tscn, gives it
## `hud` and calls
## set_ship() 10 times a second (null while there is no live ship). It
## reads Ship, ShieldZones (ship.shields) and the energy system
## (ship.energy).

## RT7: how long (seconds) after a hull hit on the ship the readout wears its danger edge (the mark of the "Under Fire!" alert),
## and the edge's width (pixels).
const FIRE_EDGE_S := 3.0
const FIRE_EDGE_W := 2.0  # the edge's width (pixels)
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

## Radius (pixels) of the armour ring, inside the shield arcs.
const ARMOUR_R := 30.0
## Thickness (pixels) of the armour ring.
const ARMOUR_W := 3.0
## The gap (radians) left between two neighbouring armour sections.
const ARMOUR_GAP := 0.05
## Below this share of its armour a section is drawn in the red end of its colours.
const ARMOUR_LOW := 0.34
## How long (seconds) a section pulses after it turns black.
const ARMOUR_PULSE := 0.4
## Half the length (pixels) of the part pips' span on the ship icon: the hull's length fills twice this, nose to tail.
const PIP_SPAN := 14.0
## The radius (pixels) of a part pip.
const PIP_R := 1.8
## The colour of the hard part of the energy bar (blocked shield damage the battery holds):
## teal, which is neither the bar's amber nor a team colour.
const HARD_COLOUR := Palette.VEIL
## Where the Vent button sits: its left edge, from the readout's left edge (pixels).
const VENT_X := 340.0
## Where the Vent button sits: its top edge, from the readout's top edge (pixels), on the bottom row,
## under the speed line (so the ability line, at its longest, and the speed line never reach it).
const VENT_Y := 115.0
## How wide the Vent button is (pixels).
const VENT_W := 80.0
## How tall the Vent button is (pixels).
const VENT_H := 16.0
## How wide (pixels) the box is that the state words ("Overloaded 4.2 s", "Venting") are right-aligned in, on the energy bar's row.
const STATE_W := 100.0
## How far left of the energy bar's right end (pixels) the state words' box starts, so the words end inside the readout.
const STATE_BACK := 104.0
## Where the ability line starts, from the readout's top edge (pixels): under the routing buttons' thin cooldown bar.
const ABILITY_Y := 84.0
## The ability line's text size (pixels).
const ABILITY_SIZE := 12
## Where the speed line starts, from the readout's top edge (pixels).
const SPEED_Y := 100.0
## The speed line's text size (pixels).
const SPEED_SIZE := 11
## The ship we show, or null (then only the empty background is drawn).
var ship: Ship = null
## The font for all our text (Godot's built-in default font).
var font: Font
## The HUD (set by Hud.setup()): a click goes to its router (HudInput.click()).
var hud: Hud = null
## The part a left press started on ("" when none): the release acts only on the same part.
var _press_part := ""
## RT7: is the danger edge on now (set from the ship's state in _process(): a hull hit under FIRE_EDGE_S seconds ago)?
var _fire := false


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
## buttons), "vent" (the Vent button), "shield_0" to "shield_3" (the zones: front, rear, left, right), "balance"
## (the ship icon) or "".
## The diamond's rule: within CENTRE_R of the middle is balance; between ZONE_INNER and ZONE_OUTER and within
## ZONE_HALF_DEG of a zone's direction is that zone; anything else (the diagonal gaps, the ring between) is
## nothing. The rear zone's wedge reaches down over the "Focus" line, so a click on those words picks the rear zone.
func part_at(p: Vector2) -> String:
	var w := W - ROUTE_X - 10.0
	var bw := (w - 9.0) / 4.0
	for i in 4:
		if Rect2(ROUTE_X + float(i) * (bw + 3.0), ROUTE_Y, bw, ROUTE_H).has_point(p):
			return "energy_%d" % i
	if vent_rect().has_point(p):
		return "vent"
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
	elif part == "vent":
		hud.router.click("vent")
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
	if part == "vent":
		return "Vent the energy (%s): the battery clears faster, but guns, boost and shields are off until it is clear. Not in a lockout." % KeyMapText.key_of("vent")
	return ""


## Every frame, set the danger edge from the ship's state and, while visible, ask Godot to redraw us (queue_redraw makes
## Godot call _draw() again).
func _process(_dt: float) -> void:
	_fire = under_fire()
	if visible:
		queue_redraw()


## RT7: did the ship take a hull hit under FIRE_EDGE_S seconds of match time ago (the readout's danger edge is on)? A shield hit
## does not count: only last_hull_damage_time does, as for the "Under Fire!" alert. Only the Admiral's readout wears it (the alert
## is the Admiral's; the pilot's readout is as it was).
func under_fire() -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.alive or ship.world == null:
		return false
	if hud == null or hud.world == null or hud.world.human_role != "admiral":
		return false
	return ship.world.time - ship.last_hull_damage_time < FIRE_EDGE_S


## RT7: is the danger edge on (the check reads it)?
func fire_edge_on() -> bool:
	return _fire


## Draw the readout: the background box, the danger edge while the ship is under fire, then (with a live ship) the
## shield diamond and the bars.
func _draw() -> void:
	draw_style_box(UiKit.box(Palette.with_alpha(Palette.PANEL, 0.9), Palette.LINE, 0), Rect2(Vector2.ZERO, size))
	# The steady danger edge (the colour of the army card's attacked frame): no blink, nothing times it.
	if _fire:
		draw_rect(Rect2(1.0, 1.0, size.x - 2.0, size.y - 2.0), Palette.DANGER, false, FIRE_EDGE_W)
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
	_draw_armour_ring(c)
	# Ship icon, nose up. Its colour slides ("lerps", short for linear
	# interpolation: mixes in a straight line) from green to red as the
	# hull drops.
	var pts := PackedVector2Array([c + Vector2(0, -15), c + Vector2(10, 11), c + Vector2(0, 6), c + Vector2(-10, 11)])
	var hull_col := Palette.REPAIR.lerp(Palette.CINDER, 1.0 - ship.hull_frac())
	draw_colored_polygon(pts, Palette.with_alpha(hull_col, 0.85))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.ICE, 1.0, true)
	_draw_part_pips(c)
	# The focus line: in the highlight colour when focus can be changed, grey
	# with the seconds left while it is cooling down.
	var focus_text := "Focus: %s" % Rules.FOCUS_NAMES[sh.focus]
	if ship.focus_cd > 0.0:
		focus_text += " (%.1fs)" % ship.focus_cd
	_text(Vector2(8, H - 8), focus_text, 11, UiKit.accent() if ship.focus_cd <= 0.0 else Palette.MIST)


## Draw the armour ring inside the shield arcs: one tiled arc for each armour section,
## bright green when whole, then darker red as the armour is lost, then black with a
## light outline once the section is breached (no armour left). No number and no bar,
## and a section never gets its colour back. A section that just turned black pulses for
## ARMOUR_PULSE seconds (once: it can only turn black once).
func _draw_armour_ring(c: Vector2) -> void:
	var a := ship.armour
	if a == null:
		return
	var now := ship.world.time if ship.world != null else 0.0
	for i in a.count:
		var span := a.section_span(i)
		# The ship's own angles have the nose at 0; the readout has the nose up.
		var a0 := span.x - PI * 0.5 + ARMOUR_GAP
		var a1 := span.y - PI * 0.5 - ARMOUR_GAP
		var frac := float(a.a_hp[i]) / float(maxi(1, a.a_max[i]))
		if a.is_black(i):
			draw_arc(c, ARMOUR_R, a0, a1, 8, Color(0.02, 0.02, 0.03, 0.95), ARMOUR_W, true)
			draw_arc(c, ARMOUR_R + ARMOUR_W * 0.5, a0, a1, 8, Palette.with_alpha(Palette.ICE, 0.55), 1.0, true)
			draw_arc(c, ARMOUR_R - ARMOUR_W * 0.5, a0, a1, 8, Palette.with_alpha(Palette.ICE, 0.55), 1.0, true)
		else:
			draw_arc(c, ARMOUR_R, a0, a1, 8, _armour_colour(frac), ARMOUR_W, true)
		var since := now - a.breach_time[i]
		if since >= 0.0 and since < ARMOUR_PULSE:
			draw_arc(c, ARMOUR_R, a0, a1, 8, Palette.with_alpha(Palette.ICE, 0.85 * (1.0 - since / ARMOUR_PULSE)), ARMOUR_W + 3.0, true)


## The colour of a section holding frac (0..1] of its armour: bright green when whole,
## fading to a red at ARMOUR_LOW, then to a dark red as the last of it goes (green and red
## differ in brightness, so the fade reads without telling the hues apart).
func _armour_colour(frac: float) -> Color:
	var red := Palette.CINDER.darkened(0.2)
	if frac >= ARMOUR_LOW:
		return red.lerp(Palette.REPAIR, clampf((frac - ARMOUR_LOW) / (1.0 - ARMOUR_LOW), 0.0, 1.0))
	return red.darkened(0.55 * (1.0 - frac / ARMOUR_LOW))


## Draw one small pip on the ship icon for each part of a big ship that has parts (PartRings, the own ship: always
## visible): placed by the part's offset over the hull's length, green when working, dark red when hurt, black when
## offline; an offline part has a light arc round its pip that grows to a full circle as it climbs back to its
## 15 percent line. No number and no text.
func _draw_part_pips(c: Vector2) -> void:
	var list := PartRings.rings(ship, ship.team)
	if list.is_empty():
		return
	var k := PIP_SPAN / maxf(1.0, float(ship.def.get("length", 26.0)))
	for r: Dictionary in list:
		var off: Vector2 = r["off"]
		var p := c + Vector2(off.y, -off.x) * k
		draw_circle(p, PIP_R, r["colour"])
		if int(r["state"]) == ShipSystems.OFF:
			draw_arc(p, PIP_R + 1.5, -PI * 0.5, -PI * 0.5 + TAU * float(r["climb"]), 10, Palette.with_alpha(Palette.ICE, 0.8), 1.0, true)


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
	# The part of the battery held by blocked shield damage (hard energy) in its own colour,
	# from the right end of the bar.
	if ship.energy.hard > 0.0 and ship.energy.max_value > 0.0:
		var hw := w * clampf(ship.energy.hard / ship.energy.max_value, 0.0, 1.0)
		draw_rect(Rect2(x + w - hw, y, hw, 13), HARD_COLOUR)
		draw_rect(Rect2(x, y, w, 13), Palette.LINE, false, 1.0)
	var energy_text := "Energy %d / %d" % [int(ship.energy.value), int(ship.energy.max_value)]
	if ship.energy.hard > 0.0:
		energy_text += "  held %d" % int(ship.energy.hard)
	_text(Vector2(x + 4, y + 10), energy_text, 10, Palette.ICE, true)
	var state := state_text(ship)
	if state != "":
		var box := state_box(x, y, w)
		draw_string(font, Vector2(box.position.x, y + 10), state, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x, 10, Palette.VOID)
		draw_string(font, Vector2(box.position.x - 1.0, y + 9), state, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x, 10, Palette.ICE)
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
	_draw_vent_button()
	y = ABILITY_Y
	# Step 4: the ability: active (seconds left), cooling down, systems off,
	# not enough energy, or ready (see ability_line()).
	var line := ability_line(ship)
	_text(Vector2(x, y + 10), String(line["text"]), ABILITY_SIZE, line["col"] as Color)
	y = SPEED_Y
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
	_text(Vector2(x, y + 10), spd + boost + extra, SPEED_SIZE, Palette.MIST)


## The words for the state of ship `s`'s systems: "Overloaded 4.2 s" in a lockout, "Venting"
## in a Vent, else "". A static function so a check can call it.
static func state_text(s: Ship) -> String:
	if s == null:
		return ""
	if s.overload_left > 0.0:
		return "Overloaded %.1f s" % s.overload_left
	if s.venting:
		return "Venting"
	return ""


## The box (readout pixels) the state words are drawn right-aligned in, on the energy bar's row: the bar's left
## edge `x`, its row's top `y` and its width `w` go in. The box is STATE_W wide, 13 tall (the bar's height) and
## starts STATE_BACK left of the bar's right end, so the words end inside the readout. A static function so
## the drawing and a check use one number.
static func state_box(x: float, y: float, w: float) -> Rect2:
	return Rect2(Vector2(x + w - STATE_BACK, y), Vector2(STATE_W, 13.0))


## The ability line of ship `s`: {"text": the words, "col": their colour}. A charge (the Broadside's, the
## Overcharge's warning) shows "charging" and its seconds left. Active shows the seconds left
## (highlight colour), a cooldown shows its seconds, a lockout or a Vent (systems_off()) says "offline"
## (the unavailable colour: the special cannot be used then, whatever the energy), too little energy says
## what it needs, and only a ship that can use it now says "ready". A static function so a check can call it.
static func ability_line(s: Ship) -> Dictionary:
	var label: String = s.def.get("special_label", "Ability")
	if s.charge_t > 0.0:
		return {"text": "%s: charging %.1fs" % [label, s.charge_t], "col": UiKit.accent()}
	if s.special_t > 0.0:
		return {"text": "%s: active %.1fs" % [label, s.special_t], "col": UiKit.accent()}
	if s.special_cd > 0.0:
		return {"text": "%s: %.1fs" % [label, s.special_cd], "col": Palette.MIST}
	if s.systems_off():
		return {"text": "%s: offline" % label, "col": Palette.MIST}
	if s.energy.value < float(s.def["special_energy"]):
		return {"text": "%s: needs %d energy" % [label, int(s.def["special_energy"])], "col": Palette.MIST}
	return {"text": "%s: ready (right-click / G)" % label, "col": Palette.ICE}


## The rectangle (readout pixels) that the ability line's text `t` covers when drawn with `font`: from the
## routing buttons' left edge, on the line's baseline, as tall as the font's ascent and descent.
static func ability_text_rect(t: String, font: Font) -> Rect2:
	var base := ABILITY_Y + 10.0
	var asc := font.get_ascent(ABILITY_SIZE)
	var width := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ABILITY_SIZE).x
	return Rect2(ROUTE_X, base - asc, width, asc + font.get_descent(ABILITY_SIZE))


## The Vent button's rectangle (readout pixels): the click part and the drawing.
static func vent_rect() -> Rect2:
	return Rect2(VENT_X, VENT_Y, VENT_W, VENT_H)


## Draw the Vent button (a click part, see part_at()): filled in the highlight colour while
## the Vent runs, plain while a Vent can start, dim when it cannot (a lockout, or nothing to
## clear). The key shows in brackets.
func _draw_vent_button() -> void:
	var r := vent_rect()
	var can := not ship.systems_off() and ship.energy.load_frac() > 0.0
	draw_rect(r, UiKit.accent() if ship.venting else Palette.INK)
	draw_rect(r, Palette.LINE, false, 1.0)
	var col := Palette.VOID if ship.venting else (Palette.ICE if can else Palette.MIST)
	_text(r.position + Vector2(5, 12), "Vent (%s)" % KeyMapText.key_of("vent"), 10, col)


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
