class_name CircleBatch
extends RefCounted
## WHAT THIS IS: a way to draw hundreds of flat circles with a handful of drawing
## commands instead of one command for each. The starfield (1,400 stars) and the
## haze of the cover patches (about 900 discs) are made of circles that never
## change, and drawing each with its own draw_circle() call costs one draw call
## apiece on every frame. A batch collects them and hands the renderer a few big
## triangle lists instead. It only draws; it changes nothing in the game.
##
## HOW IT WORKS:
##   - add() puts one circle (its middle, radius and colour) into the batch. A
##     circle is a fan of 64 triangles round its middle, the same shape draw_circle()
##     makes, so the picture is the same. The 65 corner points of a circle (64 on
##     the rim and the middle) come from one ring of unit length that is moved and
##     sized with a single multiplication (a Transform2D times a packed array,
##     which Godot does in its own fast code), so adding a circle takes no loop.
##   - A command may hold at most PER_CHUNK circles (the points of one command must
##     stay under 65,536), so a batch fills one chunk after another.
##   - draw() hands every chunk to the renderer on a canvas item (the node whose
##     _draw() is running), in the order the circles were added, so circles that
##     overlap blend in the same order as when drawn one by one.
##
## WHO USES IT: MapDecor (the stars) and CoverView (the gas clouds and pockets).

## How many triangles one circle is made of (draw_circle() makes 64).
const SEGMENTS := 64
## How many points one circle has: the rim, then the middle.
const POINTS := SEGMENTS + 1
## How many circles one drawing command holds at most (1,000 x 65 points = 65,000).
const PER_CHUNK := 1000

## The corner points of a circle of radius 1 round (0, 0): the rim, then the middle.
## Made on first use.
static var _ring := PackedVector2Array()
## The triangles of PER_CHUNK circles one after another, as numbers pointing into
## their points (circle k uses points k x 65 to k x 65 + 64). A chunk of fewer circles
## uses the front part of it. Made on first use.
static var _index := PackedInt32Array()

## The points of the chunk being filled.
var _pts := PackedVector2Array()
## The colours of the chunk being filled, one for each point.
var _cols := PackedColorArray()
## The finished chunks: [points, colours, circles].
var _done: Array = []


## Put a circle of radius `radius` round `at`, in colour `color`, into the batch.
func add(at: Vector2, radius: float, color: Color) -> void:
	_make_templates()
	_pts.append_array(Transform2D(0.0, Vector2(radius, radius), 0.0, at) * _ring)
	var block := PackedColorArray()
	block.resize(POINTS)
	block.fill(color)
	_cols.append_array(block)
	if _pts.size() >= PER_CHUNK * POINTS:
		_close_chunk()


## How many circles the batch holds.
func size() -> int:
	var n := _pts.size() / POINTS
	for chunk: Array in _done:
		n += int(chunk[2])
	return n


## Draw every circle of the batch on `ci` (the node whose _draw() is running), in the
## order they were added: one command for each chunk of PER_CHUNK circles.
func draw(ci: CanvasItem) -> void:
	_close_chunk()
	for chunk: Array in _done:
		var n: int = chunk[2]
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _index.slice(0, n * SEGMENTS * 3), chunk[0], chunk[1])


## Finish the chunk being filled (if it holds any circle) and start a new one.
func _close_chunk() -> void:
	if _pts.is_empty():
		return
	_done.append([_pts, _cols, _pts.size() / POINTS])
	_pts = PackedVector2Array()
	_cols = PackedColorArray()


## Make the ring and the triangle numbers once.
static func _make_templates() -> void:
	if not _ring.is_empty():
		return
	for i in SEGMENTS:
		var angle := float(i) / float(SEGMENTS) * TAU
		_ring.append(Vector2(cos(angle), sin(angle)))
	_ring.append(Vector2.ZERO)
	for k in PER_CHUNK:
		var base := k * POINTS
		for i in SEGMENTS:
			_index.append(base + SEGMENTS)
			_index.append(base + i)
			_index.append(base + (i + 1) % SEGMENTS)
