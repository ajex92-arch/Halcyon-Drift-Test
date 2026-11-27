class_name RoleHud
extends RefCounted
## WHAT THIS IS: the small bit of the pilot's ship status panel (ShipStatus)
## that belongs to the combat_roles features: the words ESCORTED or ISOLATED
## for a big ship (escort_pd variant), and a pip that lights when the ship's
## energy routing is charged, with the seconds left of a weapons overcharge
## (routing_payoff variant).
##
## HOW IT WORKS: ShipStatus calls draw() at the end of its own drawing. When
## no feature of this fork is on (World.features has no entry for the two
## keys) it returns at once and draws nothing. Otherwise it writes the
## words in the empty strip at the bottom right of the panel, and draws a
## coloured pip (amber = Weapons, blue = Shields, green = Thrusters) at the
## right end of that strip while the ship is charged. The words are drawn
## short, at text size 10 (SIZE): ESC x3 for ESCORTED x3 (short_words()),
## CHRG for CHARGED and OVC 2.0s for OVERCHARGE 2.0s; ISOLATED stays as it is.
## strip_rects() measures those short texts and draw() draws the same ones.
## The right end of the strip is STRIP_RIGHT, left of the Vent button. When a
## routing item (the pip, CHRG or OVC) shows, the items are packed leftwards
## from STRIP_RIGHT with STRIP_GAP between them, each at its own measured width
## (strip_rects()); the escort words alone stay at X.
##
## WHO USES IT: ShipStatus._draw() (one line). It reads EscortPdFeature
## and RoutingPayoffFeature through World.features.

## Where the strip starts, from the panel's left edge (pixels): the same x as
## the bars above it.
const X := 140.0
## The strip's baseline, from the panel's bottom edge (pixels up).
const BASE_UP := 6.0
## The strip's right edge, from the panel's left edge (pixels): 8 pixels left of the Vent button, so
## no item of the strip is drawn over it.
const STRIP_RIGHT := ShipStatus.VENT_X - 8.0
## The space between two items of the strip (pixels).
const STRIP_GAP := 6.0
## The text size of the strip's words, 10 pixels: the smallest size the readout's other text uses.
const SIZE := 10
## The radius of the routing pip (pixels).
const PIP_R := 5.0
## The first word of the escort status when a big ship has support ("ESCORTED x2").
const ESCORT_FULL := "ESCORTED"
## What is drawn in place of ESCORT_FULL ("ESC x2"); the number after it stays.
const ESCORT_SHORT := "ESC"
## The text drawn when the ship's energy routing is charged.
const CHARGED_TEXT := "CHRG"
## The text drawn while a weapons overcharge runs, with the seconds left in it.
const OVER_FORMAT := "OVC %.1fs"


## The escort words as the strip draws them: ESCORT_SHORT plus the rest of `words` when `words` begins with
## ESCORT_FULL ("ESCORTED x3" gives "ESC x3"), otherwise `words` unchanged ("ISOLATED" stays).
static func short_words(words: String) -> String:
	if words.begins_with(ESCORT_FULL):
		return ESCORT_SHORT + words.substr(ESCORT_FULL.length())
	return words


## Where the items of the strip sit, as rectangles in the panel's pixels (a text's rectangle is as wide as
## the text in `font` at size SIZE, from its ascent above the baseline to its descent below it; the pip's is
## its circle's square). The keys are only those of the items shown: "words" (the escort words `words`, drawn
## as short_words() gives them, when not empty), "over" (the OVER_FORMAT text, when `over` seconds are above 0),
## "charged" (the CHARGED_TEXT text) and "pip" (the pip), the last two when `mode` is 0 or more. A text's own
## left end is its rectangle's position.x. `panel_h` is the panel's height. When no routing item shows, the
## escort words start at X; otherwise the items are packed from STRIP_RIGHT to the left, in the order escort
## words, overcharge, charged, pip, STRIP_GAP apart, and an item that is not shown takes no room. A static
## function so draw() and a check use the same numbers and the same texts.
static func strip_rects(words: String, mode: int, over: float, font: Font, panel_h: float) -> Dictionary:
	var rects := {}
	var base := panel_h - BASE_UP
	var asc := font.get_ascent(SIZE)
	var high := asc + font.get_descent(SIZE)
	var routing := mode >= 0 or over > 0.0
	var drawn := short_words(words)
	if not routing:
		if words != "":
			var ww := font.get_string_size(drawn, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
			rects["words"] = Rect2(X, base - asc, ww, high)
		return rects
	var right := STRIP_RIGHT
	if mode >= 0:
		rects["pip"] = Rect2(right - 2.0 * PIP_R, base - 4.0 - PIP_R, 2.0 * PIP_R, 2.0 * PIP_R)
		right -= 2.0 * PIP_R + STRIP_GAP
		var cw := font.get_string_size(CHARGED_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		rects["charged"] = Rect2(right - cw, base - asc, cw, high)
		right -= cw + STRIP_GAP
	if over > 0.0:
		var ow := font.get_string_size(OVER_FORMAT % over, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		rects["over"] = Rect2(right - ow, base - asc, ow, high)
		right -= ow + STRIP_GAP
	if words != "":
		var ww2 := font.get_string_size(drawn, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		rects["words"] = Rect2(right - ww2, base - asc, ww2, high)
	return rects


## Draw the feature words and pip for `ship` onto panel `panel`. Called from
## inside the panel's _draw(). Each item is placed by strip_rects().
static func draw(panel: Control, ship: Ship) -> void:
	var feats := ship.world.features if ship.world != null else {}
	if feats.is_empty():
		return
	var y := panel.size.y - BASE_UP
	var font := ThemeDB.fallback_font
	# The escort status of a big ship.
	var words := ""
	var esc = feats.get(EscortPdFeature.KEY)
	if esc != null:
		words = (esc as EscortPdFeature).status(ship)
	# The routing pip, and the overcharge timer.
	var mode := -1
	var over := 0.0
	var rp = feats.get(RoutingPayoffFeature.KEY)
	if rp != null:
		var r := rp as RoutingPayoffFeature
		mode = r.charged_mode(ship)
		over = r.overcharge_left(ship)
	var rects := strip_rects(words, mode, over, font, panel.size.y)
	if rects.has("words"):
		var col := Palette.REPAIR if words.begins_with("ESCORTED") else Palette.CINDER
		panel.draw_string(font, Vector2((rects["words"] as Rect2).position.x, y), short_words(words),HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, col)
	if rects.has("pip"):
		var pip := Palette.AMBER
		if mode == Rules.ENERGY_SHIELDS:
			pip = Palette.SHIELD
		elif mode == Rules.ENERGY_THRUSTERS:
			pip = Palette.REPAIR
		panel.draw_circle((rects["pip"] as Rect2).get_center(), PIP_R, pip)
		panel.draw_string(font, Vector2((rects["charged"] as Rect2).position.x, y), CHARGED_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, pip)
	if rects.has("over"):
		panel.draw_string(font, Vector2((rects["over"] as Rect2).position.x, y), OVER_FORMAT % over, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Palette.AMBER)