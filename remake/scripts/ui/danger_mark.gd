class_name DangerMark
extends Control
## WHAT THIS IS: the danger triangle (Glyphs.danger) as a small control, so a row of a screen
## can hold it like a label.
##
## HOW IT WORKS: it asks for a little more room than the triangle (a 4 pixel margin) and
## draws the triangle in the middle of whatever size it gets. The mouse passes through it.
##
## WHO USES IT: the Controls page, beside the warning that a key is taken.

## The side of the triangle, in pixels (Glyphs.SIDE at the game's base size).
var side := Glyphs.SIDE


## Set the room the mark needs and let the mouse pass through.
func _init(triangle_side: float = Glyphs.SIDE) -> void:
	side = triangle_side
	custom_minimum_size = Vector2(side + 4.0, side * 0.866 + 4.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Draw the triangle in the middle of the control.
func _draw() -> void:
	Glyphs.danger(self, size * 0.5, side)
