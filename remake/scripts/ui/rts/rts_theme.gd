class_name RtsTheme
extends RefCounted
## WHAT THIS IS: the looks of the command view (the Admiral's docked screen): one cached box style for each
## look a card cell, a production row or a selection tag can have, and the theme variations that carry them.
## The four looks of a build or order cell are ready, cannot pay, locked and full; the others are the plain cell,
## the row, the picked row, the selection tag and the tag that is on.
##
## HOW IT WORKS: extend(theme) adds the looks to a theme the HUD already made with UiKit.make_theme(); it never
## replaces what UiKit made (the panels, buttons, tooltips and text colours of every other screen stay as they
## are), it only adds the Button variations RtsCellReady, RtsCellPay, RtsCellLocked, RtsCellFull, RtsCell,
## RtsRow, RtsRowPicked and RtsTag. A screen picks a look by `button.theme_type_variation = RtsTheme.variation_of(state)`,
## or draws a cell itself with `look_of(state)`. One StyleBoxFlat is made for each look (and each of its hover and
## pressed modes) and shared by every control that uses it: no control makes a style of its own. The cache is
## dropped when the accent colour changes (extend() is called again then). Colours come from Palette only; the
## full look borders in Palette.DANGER, so a cell that wears it must also draw the danger triangle (Glyphs.danger
## or DangerMark).
##
## WHO USES IT: Hud (calls extend() after every UiKit.make_theme()), CommandCard, SelectionPanel, ProductionPanel,
## TopStrip; tests/rts_tour.gd checks the four looks.

## The state words a cell can be in, in the order the design lists them.
const STATES := ["ready", "cannot_pay", "locked", "full"]
## The look names that are not states.
const PLAIN := ["cell", "row", "row_picked", "tag", "tag_on", "refused"]

## The box styles made so far, keyed by "<look>/<mode>" (mode: normal, hover, pressed, disabled).
static var _cache := {}


## Add the command view's looks to `t` (a theme made by UiKit.make_theme()). Drops the cached styles first, because
## the accent colour may have changed since the last call.
static func extend(t: Theme) -> void:
	_cache.clear()
	var names: Array = STATES + PLAIN
	for look: String in names:
		var variation := variation_name(look)
		t.set_type_variation(variation, "Button")
		for mode: String in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(mode, variation, _box(look, mode))
		t.set_stylebox("hover_pressed", variation, _box(look, "pressed"))
		t.set_stylebox("focus", variation, StyleBoxEmpty.new())
		t.set_color("font_color", variation, _text_color(look))
		t.set_color("font_hover_color", variation, _text_color(look))
		t.set_color("font_pressed_color", variation, _text_color(look))
		t.set_color("font_hover_pressed_color", variation, _text_color(look))
		t.set_color("font_disabled_color", variation, _text_color(look))
		t.set_font_size("font_size", variation, 11)
	# The strip's flat buttons: no box until the pointer is on them, then the accent border; words in ice, 11 px.
	t.set_type_variation("RtsStrip", "Button")
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 3
	flat.content_margin_right = 3
	flat.content_margin_top = 0
	flat.content_margin_bottom = 0
	for mode: String in ["normal", "disabled", "focus"]:
		t.set_stylebox(mode, "RtsStrip", flat)
	t.set_stylebox("hover", "RtsStrip", _box("tag_on", "hover"))
	t.set_stylebox("pressed", "RtsStrip", _box("tag_on", "pressed"))
	t.set_stylebox("hover_pressed", "RtsStrip", _box("tag_on", "pressed"))
	t.set_color("font_color", "RtsStrip", Palette.ICE)
	t.set_color("font_hover_color", "RtsStrip", Palette.ICE)
	t.set_color("font_pressed_color", "RtsStrip", Palette.ICE)
	t.set_font_size("font_size", "RtsStrip", 11)
	# The tiny button of a tag (its x): no box and no room around the word, so it never grows past its corner.
	t.set_type_variation("RtsMini", "Button")
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 1
	none.content_margin_right = 1
	none.content_margin_top = 0
	none.content_margin_bottom = 0
	for mode: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(mode, "RtsMini", none)
	t.set_color("font_color", "RtsMini", Palette.MIST)
	t.set_color("font_hover_color", "RtsMini", Palette.ICE)
	t.set_color("font_pressed_color", "RtsMini", Palette.ICE)
	t.set_font_size("font_size", "RtsMini", 10)


## The theme variation (a name) of a look: RtsCellReady for "ready", RtsCellPay for "cannot_pay", RtsRowPicked for
## "row_picked" and so on.
static func variation_name(look: String) -> String:
	match look:
		"ready":
			return "RtsCellReady"
		"cannot_pay":
			return "RtsCellPay"
		"locked":
			return "RtsCellLocked"
		"full":
			return "RtsCellFull"
		"cell":
			return "RtsCell"
		"row":
			return "RtsRow"
		"row_picked":
			return "RtsRowPicked"
		"tag":
			return "RtsTag"
		"tag_on":
			return "RtsTagOn"
		"refused":
			return "RtsCellRefused"
	return "RtsCell"


## The theme variation for a state word ("ready", "cannot_pay", "locked", "full"); an unknown word gives the plain cell.
static func variation_of(state: String) -> String:
	return variation_name(state) if STATES.has(state) else "RtsCell"


## The shared box style of the look for a state word, as drawn at rest. An unknown word gives the plain cell.
static func look_of(state: String) -> StyleBoxFlat:
	return look(state if STATES.has(state) else "cell")


## The shared box style of `look_name` (a state or one of PLAIN) as drawn at rest.
static func look(look_name: String) -> StyleBoxFlat:
	return _box(look_name, "normal")


## The colour of the words in a look: locked is dimmed, everything else is ice.
static func _text_color(look_name: String) -> Color:
	if look_name == "locked":
		return Palette.with_alpha(Palette.MIST, 0.8)
	return Palette.ICE


## The cached box style for `look_name` in `mode`.
static func _box(look_name: String, mode: String) -> StyleBoxFlat:
	var key := "%s/%s" % [look_name, mode]
	if _cache.has(key):
		return _cache[key]
	var s := _make(look_name, mode)
	_cache[key] = s
	return s


## Make one box style: fill and border by look, brightened by mode (hover borders in the accent colour, pressed
## fills darker). Corners 3 px, 2 px of room inside.
static func _make(look_name: String, mode: String) -> StyleBoxFlat:
	var hi := UiKit.accent()
	var fill := Palette.with_alpha(Palette.PANEL, 0.9)
	var edge := Palette.LINE
	match look_name:
		"cannot_pay":
			fill = Palette.with_alpha(Palette.INK, 0.9)
			edge = Palette.with_alpha(Palette.ORE, 0.55)
		"locked":
			fill = Palette.with_alpha(Palette.INK, 0.6)
			edge = Palette.with_alpha(Palette.LINE, 0.55)
		"full":
			fill = Palette.with_alpha(Palette.PANEL, 0.9)
			edge = Palette.DANGER
		"refused":
			# A locked cell whose research is missing (the Repair bay, the Torpedo turret): red, as a refusal is.
			fill = Palette.with_alpha(Palette.DANGER, 0.22)
			edge = Palette.DANGER
		"row":
			fill = Palette.with_alpha(Palette.INK, 0.8)
		"row_picked":
			fill = Palette.with_alpha(Palette.PANEL, 0.95)
			edge = hi
		"tag":
			fill = Palette.with_alpha(Palette.INK, 0.85)
		"tag_on":
			fill = Palette.with_alpha(Palette.PANEL, 0.95)
			edge = hi
	match mode:
		"hover":
			if look_name != "full" and look_name != "refused":
				edge = hi
		"pressed":
			fill = Palette.with_alpha(Palette.PANEL, 1.0)
			if look_name != "full" and look_name != "refused":
				edge = hi
		"disabled":
			fill = Palette.with_alpha(fill, fill.a * 0.6)
			edge = Palette.with_alpha(edge, edge.a * 0.6)
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s
