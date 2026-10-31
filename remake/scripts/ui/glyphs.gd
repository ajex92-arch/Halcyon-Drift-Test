class_name Glyphs
extends RefCounted
## WHAT THIS IS: small signs drawn in code. For now one: the danger triangle, the sign that
## always goes with the danger colour, so danger is never shown by colour alone.
##
## HOW IT WORKS: danger() draws an upright equilateral triangle (a point at the top)
## whose side is `size` pixels (14 at the game's base size of 1280x720, 16 at 1080p). It has
## a flat fill of the panel colour, an outline of Palette.DANGER (2 pixels, a little less
## when the sign is tiny) and, inside, a bar with a dot under it in the same colour, the
## sign for a hazard. Everything is drawn from the triangle's corners (triangle()), so a
## test can measure it. It must still read as a solid dark shape at 10 pixels, where the
## fill and the bar merge into the outline. It is not the map icon of strike craft, which
## is a triangle in a team colour with no mark inside; this one is always upright and
## always carries the bar.
##
## WHO USES IT: DangerMark (a control that draws it in a row) and any screen that shows a
## refused or lost state with Palette.DANGER; tests/flash_check.gd measures its shape.

## The side of the triangle at the game's base size (pixels).
const SIDE := 14.0


## The three corners of an upright equilateral triangle with side `side` whose middle
## (its centre of gravity) is at `centre`: the top point first, then bottom right, bottom left.
static func triangle(centre: Vector2, side: float) -> PackedVector2Array:
	var h := side * sqrt(3.0) * 0.5
	return PackedVector2Array([
		centre + Vector2(0.0, -2.0 * h / 3.0),
		centre + Vector2(side * 0.5, h / 3.0),
		centre + Vector2(-side * 0.5, h / 3.0),
	])


## Draw the danger sign on canvas item `ci` with its middle at `centre` and its side `size`
## pixels (see HOW IT WORKS). Call it from the item's _draw().
static func danger(ci: CanvasItem, centre: Vector2, size: float = SIDE) -> void:
	var pts := triangle(centre, size)
	# Step 1: the flat fill, then the outline over it.
	ci.draw_colored_polygon(pts, Palette.PANEL)
	var line := clampf(2.0 * size / SIDE, 1.5, 3.0)
	var closed := PackedVector2Array([pts[0], pts[1], pts[2], pts[0]])
	ci.draw_polyline(closed, Palette.DANGER, line, true)
	# Step 2: the hazard mark: a bar over a dot, on the triangle's middle line.
	var h := size * sqrt(3.0) * 0.5
	var bar_w := maxf(1.5, line)
	var top := centre.y - h * 0.16
	var bar_h := h * 0.30
	ci.draw_rect(Rect2(centre.x - bar_w * 0.5, top, bar_w, bar_h), Palette.DANGER)
	ci.draw_circle(Vector2(centre.x, top + bar_h + bar_w * 1.1), bar_w * 0.65, Palette.DANGER)
