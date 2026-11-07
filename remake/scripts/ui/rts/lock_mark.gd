class_name LockMark
extends Control
## WHAT THIS IS: a small padlock drawn in code (a body and a shackle), the sign of a locked card cell.
##
## HOW IT WORKS: a Control about 10 x 12 pixels that draws the shackle as an arc and the body as a filled box in the
## muted colour, in whatever size it is given. The mouse passes through it.
##
## WHO USES IT: CardCell (a locked cell wears it, so the lock is never shown by dimming alone).

## The colour of the padlock.
var tint := Palette.MIST


## Set the room the padlock needs and let the mouse pass through.
func _init() -> void:
	custom_minimum_size = Vector2(10.0, 12.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Draw the shackle (an arc over the body) and the body.
func _draw() -> void:
	var w := size.x
	var h := size.y
	var body_top := h * 0.45
	draw_arc(Vector2(w * 0.5, body_top), w * 0.28, PI, TAU, 10, tint, 1.5, true)
	draw_rect(Rect2(Vector2(w * 0.12, body_top), Vector2(w * 0.76, h - body_top)), tint)