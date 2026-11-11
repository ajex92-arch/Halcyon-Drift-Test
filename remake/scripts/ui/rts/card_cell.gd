class_name CardCell
extends Button
## WHAT THIS IS: one cell of the command card: a button for one order, ship or base tool. It shows the cell's key
## (top left), the build digit (top right), its name, a second line (price, "short 100", "fleet full", "later
## stage"), a count (bottom right) and, by its state, the look of DESIGN 5.4: ready, cannot pay (the cell stays live), locked
## (dimmed, with a padlock) or full (with the danger triangle).
##
## HOW IT WORKS: a Button with no text of its own (the words are small Labels inside it, each in its own place, so
## nothing overlaps) and the shared look of its state from RtsTheme. show_data() writes one snapshot (a Dictionary
## the card builds) and sets only what changed. The cannot-pay look follows RtsUiCalls.CANNOT_PAY_LOOK: "wash" puts a
## wash of the danger colour over the cell, deeper the bigger the shortfall, "bar" a 2 px bar of the share of the
## price you have; either way the cell carries the danger triangle or the bar and the words "short N", and a click
## still works. The key label lets the mouse through and follows RtsUiCalls.KEY_LABELS_ON.
##
## WHO USES IT: CommandCard (a pool of 12 grid cells and 4 extra cells).

## True for the small extra-row cell (28 px high): only its name shows (the rest is in its tip).
var slim := false
## The cell's parts.
var _wash: ColorRect
var _bar_bg: ColorRect  # the bar bg
var _bar: ColorRect  # the bar
var _key: Label  # the key
var _digit: Label  # the digit
var _name: Label  # the name
var _sub: Label  # the sub
var _count: Label  # the count
var _mark: DangerMark  # the mark
var _lock: LockMark  # the lock
## What the cell shows now, so an unchanged snapshot writes nothing.
var _shown := ""
## The last snapshot written (the card reads the state and id from it).
var data: Dictionary = {}


## Make the cell's parts (once).
func setup() -> void:
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"RtsCellReady"
	_wash = ColorRect.new()
	_wash.color = Palette.with_alpha(Palette.DANGER, 0.0)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wash)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Palette.with_alpha(Palette.LINE, 0.9)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Palette.ORE
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_key = UiKit.label("", 9, Palette.MIST)
	_digit = UiKit.label("", 9, Palette.MIST)
	_digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name = UiKit.label("", 10, Palette.ICE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = UiKit.label("", 9, Palette.MIST)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count = UiKit.label("", 10, Palette.ICE)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l: Label in [_key, _digit, _name, _sub, _count]:
		l.clip_text = true
		l.add_theme_constant_override("line_spacing", 0)
		add_child(l)
	_mark = DangerMark.new(10.0)
	add_child(_mark)
	_lock = LockMark.new()
	add_child(_lock)
	visible = false


## Set the cell's size and place its parts. A cell under 34 px high is slim: its name only, in 9 pixels.
func fit(cell_size: Vector2) -> void:
	slim = cell_size.y < 34.0
	_name.add_theme_font_size_override("font_size", 9 if slim else 10)
	custom_minimum_size = cell_size
	size = cell_size
	var w := cell_size.x
	var h := cell_size.y
	_wash.position = Vector2(1.0, 1.0)
	_wash.size = Vector2(w - 2.0, h - 2.0)
	_bar_bg.position = Vector2(3.0, h - 4.0)
	_bar_bg.size = Vector2(w - 6.0, 2.0)
	_key.position = Vector2(3.0, 0.0)
	_key.size = Vector2(w * 0.5, 11.0)
	_digit.position = Vector2(w - 15.0, 0.0)
	_digit.size = Vector2(12.0, 11.0)
	_name.position = Vector2(2.0, 11.0)
	_name.size = Vector2(w - 4.0, 13.0)
	_mark.position = Vector2(2.0, h - 17.0)
	_mark.size = Vector2(13.0, 13.0)
	_lock.position = Vector2(3.0, h - 16.0)
	_lock.size = Vector2(10.0, 12.0)
	_shown = ""


## Write snapshot `d`: {state ("ready", "cannot_pay", "locked", "full"), name, sub, key, digit, count, tip, share (0..1 of the
## price you have), short (0..1 of the price missing), picked (the cell's tool is armed)}.
func show_data(d: Dictionary) -> void:
	data = d
	var sig := str(d)
	if sig == _shown:
		return
	_shown = sig
	var state := str(d["state"])
	var wash := state == "cannot_pay" and RtsUiCalls.CANNOT_PAY_LOOK == "wash"
	var bar := state == "cannot_pay" and RtsUiCalls.CANNOT_PAY_LOOK == "bar"
	var red := state == "locked" and bool(d.get("red", false))
	theme_type_variation = &"RtsRowPicked" if bool(d.get("picked", false)) else StringName(RtsTheme.variation_name("refused") if red else RtsTheme.variation_of("ready" if wash else state))
	tooltip_text = str(d["tip"])
	RtsBeat.set_if_changed(_name, str(d["name"]))
	RtsBeat.set_if_changed(_key, str(d["key"]) if RtsUiCalls.KEY_LABELS_ON else "")
	RtsBeat.set_if_changed(_digit, str(d.get("digit", "")) if RtsUiCalls.KEY_LABELS_ON else "")
	RtsBeat.set_if_changed(_count, str(d.get("count", "")))
	RtsBeat.set_if_changed(_sub, str(d["sub"]))
	_name.add_theme_color_override("font_color", Palette.with_alpha(Palette.MIST, 0.8) if state == "locked" and not red else Palette.ICE)
	var mark := state == "full" or wash
	var lock := state == "locked"
	_mark.visible = mark
	_lock.visible = lock
	_lock.tint = Palette.DANGER if red else Palette.MIST
	_lock.queue_redraw()
	if slim:
		mark = false
		lock = false
		_mark.visible = false
		_lock.visible = false
		_sub.visible = false
		_count.visible = false
		_wash.visible = false
		_bar_bg.visible = false
		_bar.visible = false
		return
	_sub.visible = true
	_count.visible = true
	var left := 15.0 if (mark or lock) else 2.0
	var counted := str(d.get("count", "")) != ""
	var room := size.x - left - 2.0 - (30.0 if counted else 0.0)
	_sub.position = Vector2(left, size.y - 17.0)
	_sub.size = Vector2(maxf(10.0, room), 13.0)
	_count.position = Vector2(size.x - 32.0, size.y - 17.0)
	_count.size = Vector2(30.0, 13.0)
	_wash.visible = wash
	if wash:
		_wash.color = Palette.with_alpha(Palette.DANGER, clampf(0.20 + 0.36 * float(d.get("short", 0.0)), 0.20, 0.56))
	_bar_bg.visible = bar
	_bar.visible = bar
	if bar:
		_bar.position = _bar_bg.position
		_bar.size = Vector2((size.x - 6.0) * clampf(float(d.get("share", 0.0)), 0.0, 1.0), 2.0)