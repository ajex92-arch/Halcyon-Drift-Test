class_name BuildStrip
extends Control
## WHAT THIS IS: the build strip under the Admiral's fleet wheel (OrderWheel): ten cells in two rows of five, one for
## each hull of Ships.ORDER, shown while the wheel is open. Each cell shows the hull's digit (the key that queues it
## while X is held), its name and a state line: its price when it is ready to queue, "short 450" when the treasury
## cannot pay yet (the order still goes in and waits for the ore), "fleet full", or "locked". A locked or full hull is
## drawn dim. It is the home command card's Build page in small, for the one-handed building the plan calls "a small menu".
##
## HOW IT WORKS: a Control, a child of the wheel, that takes no mouse of its own (the wheel takes the clicks and asks
## cell_at()). The cells are laid out in code: COLS by ROWS cells of CELL pixels with GAP between them, text 14 pixels.
## The state of a cell is CardState.snapshot() of the command card's Build page for that hull, the same words the card
## shows; the snapshot reads the match through the card's view, so the strip works while the card itself is hidden
## (field mode). The digit is KeyMap.first_key("wheel", "hull_N"), which follows the home hull row's key.
##
## WHO USES IT: OrderWheel makes one and places it under the ring; tests/field_wheel_check.gd measures it.

## Cells in a row.
const COLS := 5
## Rows of cells.
const ROWS := 2
## The size (pixels) of one cell: wide enough for "0 Battlecruiser" at 14 pixels.
const CELL := Vector2(112.0, 46.0)
## The space (pixels) between two cells.
const GAP := 6.0
## The text size (pixels).
const TEXT_SIZE := 14

## The HUD this belongs to.
var hud: Hud


## Called by OrderWheel.setup(): remember the HUD, take the strip's size and stay hidden until the wheel opens.
func setup(h: Hud) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = strip_size()
	visible = false


## The size (pixels) of the whole strip.
static func strip_size() -> Vector2:
	return Vector2(float(COLS) * CELL.x + float(COLS - 1) * GAP, float(ROWS) * CELL.y + float(ROWS - 1) * GAP)


## The rectangle (pixels, in the strip's own space) of cell `i` (0 to 9, the order of Ships.ORDER: the first row is
## hulls 1 to 5, the second 6 to 10).
static func cell_rect(i: int) -> Rect2:
	return Rect2(Vector2(float(i % COLS) * (CELL.x + GAP), float(floori(float(i) / float(COLS))) * (CELL.y + GAP)), CELL)


## The cell at point `p` (pixels, in the strip's own space), or -1.
static func cell_at(p: Vector2) -> int:
	for i in COLS * ROWS:
		if cell_rect(i).has_point(p):
			return i
	return -1


## What the card says of the hull in cell `i` now (CardState.snapshot of the Build page): {state, sub, ...}.
func snapshot(i: int) -> Dictionary:
	return CardState.snapshot(hud.command_view.card, "build", str(Ships.ORDER[i]))


## The two lines of cell `i`: the digit and the hull's short name, then the state line.
func lines(i: int) -> Array:
	return _lines(i, snapshot(i))


## The two lines of cell `i` from its snapshot `snap`.
func _lines(i: int, snap: Dictionary) -> Array:
	var hull := str(Ships.ORDER[i])
	var digit := KeyMap.first_key("wheel", "hull_%d" % (i + 1))
	return ["%s %s" % [digit, Formations.short_hull(hull)] if digit != "" else Formations.short_hull(hull), str(snap["sub"])]


## Redraw every frame while shown (the treasury and the queue change under the player's hand).
func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## Draw the ten cells.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var accent := UiKit.accent()
	var over := cell_at(get_local_mouse_position())
	for i in COLS * ROWS:
		var r := cell_rect(i)
		var snap := snapshot(i)
		var state := str(snap["state"])
		var dim := state == "locked" or state == "full"
		draw_rect(r, Palette.with_alpha(Palette.PANEL, 0.6 if dim else 0.85))
		if i == over and state != "locked":
			draw_rect(r, Palette.with_alpha(accent, 0.35))
		draw_rect(r, Palette.LINE, false, 1.5)
		var text := _lines(i, snap)
		draw_string(font, r.position + Vector2(0.0, 19.0), str(text[0]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, TEXT_SIZE, Palette.MIST if dim else Palette.ICE)
		var sub_color := Palette.AMBER if state == "cannot_pay" else (Palette.MIST if dim else accent)
		draw_string(font, r.position + Vector2(0.0, 38.0), str(text[1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, TEXT_SIZE, sub_color)
