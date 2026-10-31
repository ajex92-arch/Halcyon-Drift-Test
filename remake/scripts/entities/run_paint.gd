class_name RunPaint
extends RefCounted
## WHAT THIS IS: the painter of a torpedo run: the fan of lines that shows where
## the torpedoes will go, and the bar under the ship that shows how the run is
## going. A part of ShipVisual, kept in its own file.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## ShipVisual hands it the ship and the drawing scale on every frame. It paints
## by what the ship's run (RunGun) is doing:
##   - On a run (the hold, then the wait for the release): the fan, from the
##     first tick of the hold (FanPaint: the middle line with its hollow first
##     stretch, and the two fainter edges), and the bar just below the ship. The
##     bar fills as the hold goes on. When it is full it turns brighter and a thin
##     second bar under it drains toward the moment the torpedoes leave by
##     themselves. On the ship the human flies, a hint under the bars says
##     that a right click cancels.
##   - After a launch: the bar, dim, drains from full to empty over the reload.
##   - Otherwise, on the ship the human flies only: the pilot's sight, the two
##     faint edges of the fan, while an enemy lies inside it within the reach.
## Everyone sees the fan, the bar and the reload, for any Bomber they can see
## (they are drawn only where the ship itself is drawn, not inside the fog of
## war); only the pilot sees the hint and the sight.
##
## WHO USES IT: only ShipVisual._draw().

## How far (0..1) the colour of a bar that is not yet full is pulled from the
## full colour toward amber (0 = the same colour as a full bar).
const BAR_DIM := 0.55
## How strong (0..1) the bar is while it drains over the reload.
const RELOAD_ALPHA := 0.45
## The text on the pilot's own ship while a run is on.
const CANCEL_HINT := "RIGHT-CLICK: CANCEL"


## Draw the run of `ship` on `ci` (the ship's Visual node, whose _draw() is
## running; its origin is the ship's position and it is not turned). `px` is
## world units per screen pixel, `bar_y` how far below the ship's middle the
## bar sits and `bar_w` how wide it is (both world units). `is_human` is true on
## the ship the human flies. Draws nothing when there is nothing to show.
static func draw(ci: CanvasItem, ship: Ship, px: float, bar_y: float, bar_w: float, is_human: bool) -> void:
	var m := ship.run_mount
	if m == null:
		return
	var run := m.run
	# Step 1: a run is on: the fan and the bar.
	if run.on:
		FanPaint.draw_lines(ci, ship, px, false)
		var frac := run.wind_frac()
		var full := Palette.ACE
		_bar(ci, bar_y, bar_w, 3.5 * px, frac, full if frac >= 1.0 else full.lerp(Palette.AMBER, BAR_DIM))
		var below := bar_y + 3.5 * px
		# The wait for the release: a thin second bar that drains.
		if run.is_full():
			below += 1.5 * px
			_bar(ci, below, bar_w, 2.0 * px, run.ready_frac(), Palette.ICE)
			below += 2.0 * px
		if is_human:
			_hint(ci, below + 3.0 * px, px)
		return
	# Step 2: after a launch: the bar drains over the reload.
	if run.reload > 0:
		_bar(ci, bar_y, bar_w, 3.5 * px, run.reload_frac(), Palette.with_alpha(Palette.ACE, RELOAD_ALPHA))
	# Step 3: the pilot's own sight, before a run.
	if is_human and FanPaint.enemy_in_fan(ship):
		FanPaint.draw_lines(ci, ship, px, true)


## A bar `w` wide and `h` high, its top edge `y` below the ship's middle, on a dark
## backing: filled to `frac` (0..1) in colour `fill`.
static func _bar(ci: CanvasItem, y: float, w: float, h: float, frac: float, fill: Color) -> void:
	ci.draw_rect(Rect2(-w * 0.5, y, w, h), Palette.with_alpha(Palette.VOID, 0.75))
	ci.draw_rect(Rect2(-w * 0.5, y, w * frac, h), fill)


## The hint under the bars of the human's own ship, centred, its top edge `y`
## below the ship's middle.
static func _hint(ci: CanvasItem, y: float, px: float) -> void:
	var font := ThemeDB.fallback_font
	var size := int(10.0 * px)
	var width := font.get_string_size(CANCEL_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	ci.draw_string(font, Vector2(-width * 0.5, y + float(size) * 0.8), CANCEL_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Palette.with_alpha(Palette.ICE, 0.85))
