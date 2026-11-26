class_name SelectionTag
extends Button
## WHAT THIS IS: one tag of the selection panel: a small button for one selected squadron (or, past twelve
## squadrons, one class of them, or the mothership): its name and what it is doing, a pip for each ship alive, a
## thin hull bar and an x that takes it out of the selection.
##
## HOW IT WORKS: the tag is a Button with the shared "tag" look (RtsTheme) and, inside it, small ColorRects: up to
## three pips (the ships of a squadron), a hull bar (a dark strip and a fill), a badge in the bottom right corner with the
## key label of the squadron's group ("F1", from the key map; hidden for a squadron in no group) and the x as its own small Button
## (a click on it never reaches the tag). `show_data()` writes one snapshot (a Dictionary the panel builds: name,
## state word, pips, hull fraction, tooltip) and sets only what changed. `compact` is the small look used when
## there are many tags: only the short name, the pips and the bar. The panel keeps 24 of them and shows as many as
## it needs (pooled: no tag is made or freed while playing).
##
## WHO USES IT: SelectionPanel.

## The x was pressed: take this tag's squadrons out of the selection.
signal remove_pressed

## The group badge's size (pixels): 17 x 11, as the design draws it.
const BADGE_W := 17.0
const BADGE_H := 11.0

## The three ship pips (a pip is lit for a ship alive).
var _pips: Array[ColorRect] = []
## The hull bar's dark strip and its fill.
var _bar_bg: ColorRect
var _bar: ColorRect  # the bar
## The x button in the top right corner.
var _x: Button
## The group badge in the bottom right corner ("F1": the key label of the squadron's group, from the key map).
var _badge: Label
## What the tag shows now, so a snapshot that has not changed writes nothing.
var _shown := ""
## The small look (see the top).
var compact := false


## Make the tag's parts. Called once when the panel makes the pool.
func setup() -> void:
	theme_type_variation = &"RtsTag"
	focus_mode = Control.FOCUS_NONE
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for i in 3:
		var p := ColorRect.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size = Vector2(8.0, 4.0)
		add_child(p)
		_pips.append(p)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Palette.with_alpha(Palette.LINE, 0.8)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Palette.REPAIR
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_x = Button.new()
	_x.text = "x"
	_x.focus_mode = Control.FOCUS_NONE
	_x.theme_type_variation = &"RtsMini"
	_x.tooltip_text = "Take out of the selection"
	_x.pressed.connect(func() -> void: remove_pressed.emit())
	add_child(_x)
	# The group badge (the F key of the squadron's group), small, dark with a light edge; it lets the mouse through.
	_badge = UiKit.label("", 8, Palette.ICE)
	var box := UiKit.box(Palette.INK, Palette.ICE, 0)
	box.set_corner_radius_all(2)
	box.content_margin_left = 1.0
	box.content_margin_right = 1.0
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	_badge.add_theme_stylebox_override("normal", box)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.clip_text = true
	_badge.visible = false
	add_child(_badge)
	visible = false


## Set the tag's size and place its parts for it (the compact look drops the x).
func fit(tag_size: Vector2, small: bool) -> void:
	compact = small
	custom_minimum_size = tag_size
	size = tag_size
	var w := tag_size.x
	var h := tag_size.y
	for i in 3:
		_pips[i].position = Vector2(4.0 + float(i) * 10.0, h - 11.0)
	_bar_bg.position = Vector2(3.0, h - 5.0)
	_bar_bg.size = Vector2(w - 6.0, 2.0)
	_x.visible = not small
	_x.size = Vector2(14.0, 14.0)
	_x.position = Vector2(w - 15.0, 1.0)
	_x.custom_minimum_size = Vector2(14.0, 14.0)
	_badge.custom_minimum_size = Vector2(BADGE_W, BADGE_H)
	_badge.size = Vector2(BADGE_W, BADGE_H)
	_badge.position = Vector2(w - BADGE_W - 3.0, h - BADGE_H - 5.0)
	_shown = ""


## Write snapshot `d`: {text, tip, ships (pips lit, 0-3), pips (shown, 0-3), hull (0..1), on (the tag is part of the
## selection's focus), badge (the group's key label, "" for no group)}. Only what differs from the last snapshot is written.
func show_data(d: Dictionary) -> void:
	var badge := str(d.get("badge", ""))
	var sig := "%s|%s|%s|%s|%s|%s" % [d["text"], d["ships"], d["pips"], int(float(d["hull"]) * 50.0), d.get("on", false), badge]
	if sig == _shown:
		return
	_shown = sig
	_badge.visible = badge != ""
	RtsBeat.set_if_changed(_badge, badge)
	RtsBeat.set_if_changed(self, str(d["tiny"]) if compact else str(d["text"]))
	tooltip_text = str(d["tip"])
	for i in 3:
		_pips[i].visible = i < int(d["pips"])
		_pips[i].color = Palette.ICE if i < int(d["ships"]) else Palette.with_alpha(Palette.MIST, 0.35)
	var frac := clampf(float(d["hull"]), 0.0, 1.0)
	_bar.position = _bar_bg.position
	_bar.size = Vector2((size.x - 6.0) * frac, 2.0)
	theme_type_variation = &"RtsTagOn" if bool(d.get("on", false)) else &"RtsTag"
