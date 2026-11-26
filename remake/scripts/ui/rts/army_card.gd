class_name ArmyCard
extends Button
## WHAT THIS IS: one card of the army row (D1): a small button for a control group (F1), for the squadrons of one hull that are
## in no group (FTR), for the folded class cards ("+N"), for the empty "F5 + save" slot, or for the idle squadrons (I). It shows
## the key label and the class tag, "3 sq - 8/9" (squadrons, ships alive of ships bought), a 2 px hull bar and a state sign
## (RtsGlyphs); while its squadrons are under attack it wears a steady danger-colour frame with the triangle. With the win-odds
## option on, a card of squadrons that has enemy ships in sight near it also wears a small win-odds mark (WinOdds) at the right end
## of the count line.
##
## HOW IT WORKS: the card is a Button in the shared "cell" look (the picked look while all its squadrons are selected) with
## three small Labels and one Control that draws the sign, the bar and the frame. `show_data()` writes one snapshot (a
## Dictionary ArmyCards builds) and changes only what differs from the last one. A press on it is told to ArmyCards with
## the Shift and double-click flags (`clicked`), which does what the card's kind means. The hover and the held key are
## read by ArmyCards, which also owns the detail. The pool lives in ArmyCards (21 cards, none made or freed in play).
##
## WHO USES IT: ArmyCards; tests/rts_army_check.gd.

## A left press on the card: Shift was held, and whether it was the second click of a double-click.
signal clicked(shift: bool, double: bool)

## The card's normal width and height (pixels).
const W := 74.0
const H := 30.0
## The win-odds mark's size (pixels), its middle's distance from the card's right edge and from its top (on the count line), and the
## room the mark takes off the count line's width.
const ODDS_SIZE := 9.0
const ODDS_RIGHT := 8.0
const ODDS_Y := 19.5
const ODDS_ROOM := 12.0

## The kind of card: "group", "class", "fold", "save" or "idle" (set by ArmyCards).
var kind := ""
## The snapshot shown now (see ArmyCards._entry()).
var data := {}
## How many times the art was drawn (a test reads it).
var draws := 0
## The key label, the class tag and the count line.
var _key: Label
var _tag: Label
var _count: Label
## The drawing layer: the state sign, the hull bar and the danger frame.
var _art: Control
## What the card shows now, so an unchanged snapshot writes nothing.
var _shown := ""


## Make the card's parts. Called once when ArmyCards makes the pool.
func setup() -> void:
	theme_type_variation = &"RtsCell"
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_key = UiKit.label("", 9, Palette.MIST)
	add_child(_key)
	_tag = UiKit.label("", 9, Palette.ICE)
	add_child(_tag)
	_count = UiKit.label("", 9, Palette.MIST)
	add_child(_count)
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)
	gui_input.connect(_on_gui_input)
	visible = false


## Set the card's size and place its parts for it.
func fit(width: float) -> void:
	custom_minimum_size = Vector2(width, H)
	size = Vector2(width, H)
	_art.size = size
	_key.position = Vector2(4.0, 1.0)
	_count.position = Vector2(4.0, 14.0)
	_place_count()
	_place_tag()
	_shown = ""


## Size the count line: the full width, or less the room of the win-odds mark at its right end while the card wears one (the text
## is clipped there, so it never runs under the mark).
func _place_count() -> void:
	var marked := str(data.get("odds", "")) != ""
	_count.clip_text = marked
	_count.size = Vector2(maxf(10.0, size.x - 8.0 - (ODDS_ROOM if marked else 0.0)), 12.0)


## Put the class tag after the key label (or at the left edge when the card has no key label).
func _place_tag() -> void:
	_key.size = _key.get_minimum_size()
	var x := 4.0 if _key.text == "" else 4.0 + _key.size.x + 3.0
	_tag.position = Vector2(x, 1.0)
	_tag.size = Vector2(maxf(10.0, size.x - x - 12.0), 12.0)


## Write snapshot `d`: {kind, key, tag, count, state ("" or a sign of RtsGlyphs), hull (0..1 or -1 for no bar), danger, picked,
## tip, odds ("", "win", "even" or "loss": the win-odds mark, optional)}. Only what differs from the last snapshot is written.
func show_data(d: Dictionary) -> void:
	var sig := "%s|%s|%s|%s|%s|%d|%s|%s|%d|%s" % [d["kind"], d["key"], d["tag"], d["count"], d["state"], int(float(d["hull"]) * 50.0), d["danger"], d["picked"], int(size.x), d.get("odds", "")]
	if sig == _shown:
		return
	_shown = sig
	data = d
	kind = str(d["kind"])
	RtsBeat.set_if_changed(_key, str(d["key"]))
	RtsBeat.set_if_changed(_tag, str(d["tag"]))
	RtsBeat.set_if_changed(_count, str(d["count"]))
	_place_count()
	_place_tag()
	var muted := kind == "save"
	_tag.add_theme_color_override("font_color", Palette.MIST if muted else Palette.ICE)
	theme_type_variation = &"RtsRowPicked" if bool(d["picked"]) else &"RtsCell"
	tooltip_text = str(d["tip"])
	_art.queue_redraw()


## Draw the hull bar, the state sign, the win-odds mark (when there is one) and (when under attack) the danger frame with its triangle.
func _draw_art() -> void:
	draws += 1
	var w := size.x
	var h := size.y
	var frac := float(data.get("hull", -1.0))
	if frac >= 0.0:
		_art.draw_rect(Rect2(3.0, h - 5.0, w - 6.0, 2.0), Palette.with_alpha(Palette.LINE, 0.9))
		_art.draw_rect(Rect2(3.0, h - 5.0, (w - 6.0) * clampf(frac, 0.0, 1.0), 2.0), Palette.REPAIR)
	var state := str(data.get("state", ""))
	if state != "":
		var colour := Palette.MIST if state == "idle" or state == "docked" else Palette.ICE
		RtsGlyphs.draw(_art, state, Vector2(w - 8.0, 8.0), 9.0, colour)
	# The win-odds mark (an option): the count line's right end, in the light for a win or a loss and the grey for even; the three
	# differ in shape, not only in colour.
	var odds := str(data.get("odds", ""))
	if odds != "":
		RtsGlyphs.draw(_art, "odds_" + odds, Vector2(w - ODDS_RIGHT, ODDS_Y), ODDS_SIZE, Palette.MIST if odds == "even" else Palette.ICE)
	if bool(data.get("danger", false)):
		_art.draw_rect(Rect2(1.0, 1.0, w - 2.0, h - 2.0), Palette.DANGER, false, 2.0)
		Glyphs.danger(_art, Vector2(w - 20.0, 8.0), 9.0)


## A left press: tell ArmyCards (Shift and the double-click flag with it).
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(mb.shift_pressed, mb.double_click)
