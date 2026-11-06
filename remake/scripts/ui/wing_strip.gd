class_name WingStrip
extends Control
## WHAT THIS IS: the small strip above the pilot's ship readout that shows the wing: one chip for each of
## the three places in the wing (the hull's short name and a thin hull bar), and a "Wing" button at its left
## that opens the order wheel for a player who has no order key to hold. A chip says how the wingman is doing:
## its name is bright while it is in its place and grey while it is catching up, regrouping or going home; its
## border takes the interface colour while an attack, a guard or a hold stands; the bar goes to the danger
## colour with the danger triangle below 35 percent hull; a place with no wingman is a hollow chip with a dash.
##
## HOW IT WORKS: it is a child of the ship readout (ShipStatus), so it sits over it, moves with it when the
## layout shifts it sideways, and is hidden with it. Hud._refresh() calls refresh() ten times a second: it
## shows the strip only when the human flies a ship, has a wing and no big panel is open, and redraws it. The
## chips are drawn in code in _draw() (a handful of commands). confirm() starts the one 120 ms pulse of the
## border in ICE that says an order was carried out (never repeated, and at most one in 334 ms: the flash
## table row "wing confirm").
##
## WHO USES IT: Hud.setup() makes it and Hud._refresh() refreshes it; Hud.wing_command() asks it to confirm; HudLayout
## reads whether it shows to lift the pop-up hint above it. It reads World.squads (the records) only.

## Width of one chip (pixels).
const CHIP_W := 64.0
## Height of the strip, chips and button (pixels).
const CHIP_H := 26.0
## Space between two chips (pixels).
const GAP := 6.0
## Width of the Wing button (pixels).
const BUTTON_W := 40.0
## How far above the ship readout's top edge the strip sits (pixels).
const LIFT := 6.0
## The text size of a chip (pixels).
const TEXT_SIZE := 14
## How long (milliseconds) the confirm pulse lasts.
const PULSE_MS := 120
## The shortest gap (milliseconds) between two confirm pulses: three a second at most.
const PULSE_GAP_MS := 334
## A hull bar below this fraction turns to the danger colour.
const LOW_HULL := 0.35
## The height of a chip's hull bar (pixels).
const BAR_H := 2.0

## The HUD this belongs to.
var hud: Hud
## The "Wing" button.
var button: Button
## When the confirm pulse began (Time.get_ticks_msec()), or -10000.
var _pulse_at := -10000
## What each chip shows, refreshed every tenth of a second: for slot 0 to 2 a Dictionary {state, name, hull, in_slot}.
var chips: Array = [{}, {}, {}]
## True when the standing order is an attack, a guard or a hold (the borders take the interface colour).
var marked := false


## Called by Hud.setup(): remember the HUD, make the button and put the strip above the readout.
func setup(h: Hud) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_STOP
	var total := BUTTON_W + GAP + CHIP_W * 3.0 + GAP * 2.0
	custom_minimum_size = Vector2(total, CHIP_H)
	size = Vector2(total, CHIP_H)
	# The three chips are centred over the readout; the button hangs at their left.
	var chips_w := CHIP_W * 3.0 + GAP * 2.0
	position = Vector2((ShipStatus.W - chips_w) * 0.5 - (BUTTON_W + GAP), -(CHIP_H + LIFT))
	button = UiKit.button("Wing", func() -> void: hud.wing_wheel_toggle(), CHIP_H)
	button.custom_minimum_size = Vector2(BUTTON_W, CHIP_H)
	button.size = Vector2(BUTTON_W, CHIP_H)
	button.position = Vector2.ZERO
	button.add_theme_font_size_override("font_size", TEXT_SIZE)
	button.tooltip_text = "Wing orders: click, then pick an order. Or hold X, or tap it with the mouse on an enemy, one of your big ships or empty space."
	for sb_name: String in ["normal", "hover", "pressed", "focus"]:
		var sb := button.get_theme_stylebox(sb_name)
		if sb is StyleBoxFlat:
			var flat := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			flat.content_margin_left = 2.0
			flat.content_margin_right = 2.0
			flat.content_margin_top = 2.0
			flat.content_margin_bottom = 2.0
			button.add_theme_stylebox_override(sb_name, flat)
	add_child(button)
	visible = false


## The place of chip `i` (0 to 2) inside the strip (pixels).
func chip_rect(i: int) -> Rect2:
	return Rect2(BUTTON_W + GAP + float(i) * (CHIP_W + GAP), 0.0, CHIP_W, CHIP_H)


## Look at the wing and redraw: shown only with a ship, a wing and no big panel open.
func refresh() -> void:
	var w := hud.world
	var lead: Squad = null
	if w.human != null and w.human_role == "pilot" and w.human.ship != null and is_instance_valid(w.human.ship) and w.human.ship.alive:
		lead = Squads.lead_record(w, w.human.team, w.human.slot)
	if lead == null or hud._any_panel_open() or not Squads.wing_alive(w, lead.wing_id):
		visible = false
		return
	visible = true
	var kind := str(lead.order.get("kind", ""))
	marked = kind == OrderKinds.ATTACK or kind == OrderKinds.GUARD or kind == OrderKinds.HOLD
	for i in 3:
		chips[i] = {}
	for rec: Squad in Squads.wing_records(w, lead.wing_id):
		if rec.slot_index < 0 or rec.slot_index > 2:
			continue
		chips[rec.slot_index] = _chip_of(w, rec)
	queue_redraw()


## What chip shows for record `rec`: {} for a wingman that is gone, else its state, name, hull fraction and
## whether it is in its place.
func _chip_of(w: World, rec: Squad) -> Dictionary:
	var crew := Squads.crew_of(w, rec)
	if crew == null:
		return {}
	var hull := 0.0
	var flying := false
	var s: Variant = crew.ship
	if s != null and is_instance_valid(s) and (s as Ship).alive:
		hull = (s as Ship).hull_frac()
		flying = true
	var state := "flying"
	if not flying:
		state = "docked"
	elif rec.state == Squads.STATE_HOME:
		state = "home"
	return {"state": state, "name": Formations.short_hull(rec.hull_id), "hull": hull,
		"in_slot": bool(rec.engine.get("in_slot", false)) and not bool(rec.engine.get("catching", false))}


## Start the confirm pulse (one pulse of PULSE_MS milliseconds; ignored when one ran less than PULSE_GAP_MS ago).
func confirm() -> void:
	var now := Time.get_ticks_msec()
	if now - _pulse_at < PULSE_GAP_MS:
		return
	_pulse_at = now


## Is the confirm pulse lit now?
func pulsing() -> bool:
	return Time.get_ticks_msec() - _pulse_at < PULSE_MS


## Every frame while the pulse runs, draw again (and once more when it ends).
func _process(_dt: float) -> void:
	if visible and Time.get_ticks_msec() - _pulse_at < PULSE_MS + 40:
		queue_redraw()


## Draw the three chips.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var lit := pulsing()
	for i in 3:
		var r := chip_rect(i)
		var chip: Dictionary = chips[i]
		draw_rect(r, Palette.PANEL)
		var border := Palette.ICE if lit else (UiKit.accent() if marked and not chip.is_empty() else Palette.LINE)
		draw_rect(r, border, false, 1.0)
		if chip.is_empty():
			# A place with no wingman: a hollow chip with a dash.
			draw_string(font, r.position + Vector2(0.0, 18.0), "-", HORIZONTAL_ALIGNMENT_CENTER, CHIP_W, TEXT_SIZE, Palette.MIST)
			continue
		var bright := str(chip["state"]) == "flying" and bool(chip["in_slot"])
		var col := Palette.ICE if bright else Palette.MIST
		var hull := float(chip["hull"])
		var low := str(chip["state"]) != "docked" and hull < LOW_HULL
		var text_x := 10.0 if low else 0.0
		draw_string(font, r.position + Vector2(text_x, 16.0), str(chip["name"]), HORIZONTAL_ALIGNMENT_CENTER, CHIP_W - text_x, TEXT_SIZE, col)
		var bar_w := (CHIP_W - 6.0) * clampf(hull if str(chip["state"]) != "docked" else 1.0, 0.0, 1.0)
		var bar_col := Palette.DANGER if low else Palette.REPAIR
		if str(chip["state"]) == "docked":
			bar_col = Palette.LINE
		draw_rect(Rect2(r.position + Vector2(3.0, CHIP_H - 4.0), Vector2(bar_w, BAR_H)), bar_col)
		if low:
			Glyphs.danger(self, r.position + Vector2(9.0, 11.0), 10.0)
