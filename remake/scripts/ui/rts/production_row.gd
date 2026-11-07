class_name ProductionRow
extends Control
## WHAT THIS IS: one row of the production panel: one item of the build list in two lines: the grip with the item's place in the
## list, a kind mark, the name and price, the state in words (with the danger triangle when it waits for room), a 2 px bar, and the
## buttons Repeat (ships), Hold or Resume and Cancel; a click on the row picks it and shows Up and Down.
##
## HOW IT WORKS: a Control of 26 px that draws its box (the shared "row" or "row_picked" look) and its bar itself and holds a few
## small labels and buttons. It owns no rule: every press is sent on as a signal (`picked`, `repeat_pressed`, `hold_pressed`,
## `cancel_pressed`, `up_pressed`, `down_pressed`) and a drag of the grip as `grip_moved(y)` (the pointer's y in the panel, in
## pixels) and `grip_dropped`; the panel turns them into orders. show_data() writes one snapshot Dictionary and sets only what
## changed. The cancel button of a started item asks once more (the panel passes `sure` text for RtsUiCalls.CANCEL_STARTED_CONFIRM_S
## seconds): then the row's two lines read "sure? N% of the build lost;" and "the ore comes back in full".
##
## WHO USES IT: ProductionPanel (a pool of 16 rows).

## A press on the row itself (not on a button): pick this row.
signal picked
## The Repeat, Hold or Resume, Cancel, Up and Down buttons.
signal repeat_pressed
signal hold_pressed  # sent when hold pressed
signal cancel_pressed  # sent when cancel pressed
signal up_pressed  # sent when up pressed
signal down_pressed  # sent when down pressed
## The grip is being dragged (the pointer's y in the panel) and was let go.
signal grip_moved(y: float)
signal grip_dropped  # sent when grip dropped

## The row's height (pixels).
const H := 26.0

## The parts.
var _grip: Label
var _mark: ColorRect  # the mark
var _name: Label  # the name
var _state: Label  # the state
var _danger: DangerMark  # the danger
var _repeat: Button  # the repeat
var _hold: Button  # the hold
var _cancel: Button  # the cancel
var _up: Button  # the up
var _down: Button  # the down
## The last snapshot (the panel reads ids from it) and its signature.
var data: Dictionary = {}
var _sig := ""  # the sig
## True while the grip is held.
var _dragging := false
## How much of the bar is full (0..1) and whether the row is picked, for _draw().
var _frac := 0.0
var _is_picked := false  # the is picked


## Make the parts (once).
func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_grip = UiKit.label("", 10, Palette.MIST)
	_grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_grip)
	_mark = ColorRect.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)
	_name = UiKit.label("", 10, Palette.ICE)
	_name.clip_text = true
	add_child(_name)
	_state = UiKit.label("", 9, Palette.MIST)
	_state.clip_text = true
	add_child(_state)
	_danger = DangerMark.new(9.0)
	_danger.visible = false
	add_child(_danger)
	_repeat = _button("R", "Repeat: when this hull is done and there is room, the same item is queued again.", func() -> void: repeat_pressed.emit())
	_hold = _button("H", "Hold: stop this item and keep what it has paid and built. Click again to go on.", func() -> void: hold_pressed.emit())
	_cancel = _button("x", "Cancel this item.", func() -> void: cancel_pressed.emit())
	_up = _button("^", "Move up the list (it is paid for earlier).", func() -> void: up_pressed.emit())
	_down = _button("v", "Move down the list.", func() -> void: down_pressed.emit())
	for b: Button in [_up, _down]:
		b.theme_type_variation = &"RtsMini"
	visible = false


## A small row button.
func _button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"RtsCell"
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(on_press)
	add_child(b)
	return b


## Set the row's width and place its parts.
func fit(w: float) -> void:
	custom_minimum_size = Vector2(w, H)
	size = Vector2(w, H)
	_grip.position = Vector2(1.0, 6.0)
	_grip.size = Vector2(16.0, 14.0)
	_mark.position = Vector2(19.0, 4.0)
	_mark.size = Vector2(3.0, 17.0)
	_name.position = Vector2(25.0, 0.0)
	_state.position = Vector2(25.0, 12.0)
	var bx := w - 3.0
	for b: Button in [_cancel, _hold, _repeat]:
		bx -= 17.0
		b.position = Vector2(bx, 4.0)
		b.size = Vector2(16.0, 16.0)
		bx -= 1.0
	_up.position = Vector2(bx - 14.0, 1.0)
	_up.size = Vector2(14.0, 11.0)
	_down.position = Vector2(bx - 14.0, 13.0)
	_down.size = Vector2(14.0, 11.0)
	_name.size = Vector2(bx - 14.0 - 4.0 - 25.0, 13.0)
	_state.size = Vector2(bx - 14.0 - 4.0 - 25.0 - 12.0, 13.0)
	_sig = ""


## Write snapshot `d`: {n, name, price, state, danger, frac (0..1), kind, held, started, picked, can_repeat, repeat, up_ok, down_ok, pending, sure}.
func show_data(d: Dictionary) -> void:
	data = d
	var sig := str(d)
	if sig == _sig:
		return
	_sig = sig
	_frac = clampf(float(d["frac"]), 0.0, 1.0)
	_is_picked = bool(d["picked"])
	var sure := str(d.get("sure", ""))
	RtsBeat.set_if_changed(_grip, str(d["n"]))
	_mark.color = Color(d["color"])
	if sure != "":
		RtsBeat.set_if_changed(_name, sure.get_slice("|", 0))
		RtsBeat.set_if_changed(_state, sure.get_slice("|", 1))
		_name.add_theme_color_override("font_color", Palette.ICE)
	else:
		RtsBeat.set_if_changed(_name, "%s   %s" % [d["name"], d["price"]])
		var state := str(d["state"]) + (" · pending" if bool(d["pending"]) else "")
		RtsBeat.set_if_changed(_state, state)
		_name.add_theme_color_override("font_color", Palette.with_alpha(Palette.ICE, 0.6) if bool(d["held"]) else Palette.ICE)
	var danger := bool(d["danger"]) and sure == ""
	_state.add_theme_color_override("font_color", Palette.DANGER if danger else Palette.MIST)
	_danger.visible = danger
	_state.position.x = 25.0 + (11.0 if danger else 0.0)
	_danger.position = Vector2(24.0, 13.0)
	_danger.size = Vector2(11.0, 11.0)
	_repeat.visible = bool(d["can_repeat"])
	_repeat.theme_type_variation = &"RtsRowPicked" if bool(d["repeat"]) else &"RtsCell"
	_hold.text = ">" if bool(d["held"]) else "H"
	_hold.tooltip_text = "Resume: go on with this item." if bool(d["held"]) else "Hold: stop this item and keep what it has paid and built. Click again to go on."
	_up.visible = _is_picked
	_down.visible = _is_picked
	_up.disabled = not bool(d["up_ok"])
	_down.disabled = not bool(d["down_ok"])
	queue_redraw()


## Draw the box and the 2 px bar along the bottom.
func _draw() -> void:
	draw_style_box(RtsTheme.look("row_picked" if _is_picked else "row"), Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2(3.0, size.y - 3.0), Vector2(size.x - 6.0, 2.0)), Palette.with_alpha(Palette.LINE, 0.9))
	if _frac > 0.0:
		draw_rect(Rect2(Vector2(3.0, size.y - 3.0), Vector2((size.x - 6.0) * _frac, 2.0)), Palette.REPAIR)


## A press on the row: a press on the grip starts a drag (when the panel allows it), else the row is picked.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.position.x < 20.0 and RtsUiCalls.DRAG_REORDER_ON:
				_dragging = true
			picked.emit()
			accept_event()
		elif _dragging:
			_dragging = false
			grip_dropped.emit()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		grip_moved.emit(get_parent().get_local_mouse_position().y)
		accept_event()
