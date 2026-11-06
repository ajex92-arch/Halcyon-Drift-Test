class_name DrawCache
extends Node2D
## WHAT THIS IS: a picture that is drawn once and then kept. A ship used to draw
## its whole body again on every frame, even when nothing about it had changed.
## A DrawCache is a small node that holds one such picture (the ship's hull, say)
## and is told, each frame, what the picture would look like now; it asks Godot
## for a new drawing only when that is different from the drawing it holds. It
## only helps with drawing and changes nothing in the game.
##
## HOW IT WORKS:
##   - The node sits in the unit's scene as a child of the unit itself, so it moves
##     and turns with the unit for free (the painter's own node turns the other
##     way, to keep bars and text upright, so a picture that must turn with the unit
##     lives here, drawn with the unit pointing along +x).
##   - The owner (ShipVisual, UnitVisual) connects this node's `draw` signal to the
##     function that paints the picture, and calls want() once a frame with the few
##     numbers the picture depends on. want() compares them with the numbers of the
##     picture it holds and calls queue_redraw() only when one differs.
##   - What the picture depends on is a KEY, never the hull alone: the hull id plus a
##     state number (STATE_BASE is the only state today; later art, such as damaged
##     sections or fitted modules, adds more states without changing this class), plus
##     `bits` (the on/off facts: hit flash, ace, human, heat, ...), plus `detail` (one
##     number that changes by itself, such as how far a gun is kicked back).
##   - The camera zoom is part of the key in steps: lines and sizes are drawn for the
##     zoom the picture was made at, and it is made again once the zoom has moved by
##     more than ZOOM_TOL (2%) from that, so a slow zoom makes a few new pictures and a
##     steady camera makes none.
##   - With --sim-only (Game.sim_only) nothing is drawn, so the node hides itself.
##
## WHO USES IT: the "Hull" node of scenes/entities/ship.tscn (ShipVisual) and the "Hull"
## node of the minion scene (UnitVisual). The owner stores the zoom it drew at with
## drawn_at() inside its drawing function.

## The one state a picture has today: the hull as it comes from the yard. Later art
## (damage, modules) adds states; a cache is always keyed on the hull id AND a state.
const STATE_BASE := 0
## How far (a fraction) the camera zoom may move from the zoom a picture was drawn at
## before the picture is drawn again.
const ZOOM_TOL := 0.02
## The camera zoom below which a picture is drawn "simpler": the usual play zoom and
## further out (the view is wider than about 2,600 screen pixels of the game's 1280-wide
## picture). At or above it (the mid and close-up zooms) everything is drawn as ever.
const CLOSE_ZOOM := 0.5
## The zoom the close look starts at right now: CLOSE_ZOOM, unless a picture test moved it
## (set_close_zoom()).
static var _close_zoom := CLOSE_ZOOM

## The hull id (or unit type) of the picture held ("" = nothing yet).
var hull_id := ""
## The state number of the picture held (STATE_BASE today).
var state := STATE_BASE
## The on/off facts of the picture held (-1 = nothing yet).
var bits := -1
## The one changing number of the picture held (for example a gun's kick-back).
var detail := 0.0
## The camera zoom the picture held was drawn at (0 = not drawn yet).
var zoom := 0.0


## With --sim-only nothing is ever drawn: hide the node for good.
func _ready() -> void:
	if Game.sim_only:
		visible = false


## Say what the picture should look like now: for hull `id` in state `st`, with
## the facts `new_bits`, the changing number `new_detail`, at camera zoom `z`.
## Asks for a new drawing only if any of them differs from the picture held (the
## zoom only when it has moved more than ZOOM_TOL).
func want(id: String, st: int, new_bits: int, new_detail: float, z: float) -> void:
	if zoom > 0.0 and bits == new_bits and detail == new_detail and state == st and hull_id == id and absf(z - zoom) <= zoom * ZOOM_TOL:
		return
	hull_id = id
	state = st
	bits = new_bits
	detail = new_detail
	queue_redraw()


## The drawing function calls this with the zoom it drew at, so the next want()
## compares with that zoom.
func drawn_at(z: float) -> void:
	zoom = z


## Is the camera zoom `z` a close one (CLOSE_ZOOM or more), where lines are drawn smooth
## (antialiased, which costs three drawing commands for each line) and arcs have all
## their segments? Further out they are drawn simpler, with the same shapes.
static func is_close(z: float) -> bool:
	return z >= _close_zoom


## Move the zoom the close look starts at (tests only: a picture test puts it at 0.0001 so that every
## picture is drawn the close way and can be compared with the old pictures pixel by pixel).
static func set_close_zoom(z: float) -> void:
	_close_zoom = maxf(0.0001, z)


## The same question for `px`, the world units per screen pixel (1 / the zoom).
static func is_close_px(px: float) -> bool:
	return px <= 1.0 / _close_zoom
