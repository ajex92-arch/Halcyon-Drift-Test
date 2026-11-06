class_name ViewCull
extends RefCounted
## WHAT THIS IS: a quick answer to "is this spot near enough to the camera's view that its picture
## must be kept up to date?". A unit far from the camera cannot be seen, but Godot still asks its
## painter for a new picture every frame; with this, a painter can leave the far ones alone and
## bring them up to date on the first frame they come near. It only helps with drawing and
## changes nothing in the game.
##
## HOW IT WORKS: once a frame (the first caller of the frame does it) it reads the camera's
## centre and how much of the world the window shows at the camera's zoom. near() then says
## whether a spot is inside that view, widened by a margin the caller gives (the room a picture
## may reach beyond its own spot: a gun's line to its target, a ship's torpedo fan). With no
## camera everything is near.
##
## WHO USES IT: ShipVisual and UnitVisual (the units' painters) and ResourceNode (the ore
## nodes), before they ask for a new picture.

## The frame the camera numbers below were read in.
static var _frame := -1
## The camera's centre, in world units.
static var _centre := Vector2.ZERO
## Half the width and half the height of the view, in world units (huge with no camera).
static var _half := Vector2(1.0e9, 1.0e9)


## Is `at` (world units) inside the camera's view widened by `margin` world units on every side?
static func near(vp: Viewport, at: Vector2, margin: float) -> bool:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		var cam := vp.get_camera_2d()
		if cam == null:
			_half = Vector2(1.0e9, 1.0e9)
		else:
			_centre = cam.get_screen_center_position()
			_half = vp.get_visible_rect().size / (2.0 * cam.zoom)
	return absf(at.x - _centre.x) <= _half.x + margin and absf(at.y - _centre.y) <= _half.y + margin
