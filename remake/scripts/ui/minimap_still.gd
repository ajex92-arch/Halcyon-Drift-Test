class_name MinimapStill
extends Control
## WHAT THIS IS: one of the three layers of the minimap that hardly ever change: the background with the lanes and the derelict
## camps (Minimap.PART_BASE), the resource nodes with their rings and turret squares (PART_NODES), or the cover patches
## (PART_COVER). DESIGN.md A15.
##
## HOW IT WORKS: it is a child of the Minimap that draws behind its parent (show_behind_parent), so it sits
## under the fog, the ships and the marks the Minimap itself draws. A canvas item keeps what it drew until
## it is told to draw again, so a layer costs nothing per frame: the Minimap asks it to redraw only when
## the list of what it shows (Minimap._still_signature()) has changed. The three are children in order, so they are drawn
## in the order the minimap always drew them. _draw() hands over to Minimap.draw_still(), where the drawing code lives.
##
## WHO USES IT: Minimap makes three in _ready() and sets `map` and `part`.

## The minimap this layer belongs to (set by Minimap._ready()).
var map: Minimap = null
## Which layer this is (Minimap.PART_BASE, PART_NODES or PART_COVER; set by Minimap._ready()).
var part := 0


## Draw behind the parent, cover it, and let the mouse pass through to the Minimap.
func _init() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Draw the layer (Minimap.draw_still()).
func _draw() -> void:
	if map != null:
		map.draw_still(self, part)
