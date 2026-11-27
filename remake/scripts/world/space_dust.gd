class_name SpaceDust
extends Node2D
## WHAT THIS IS: the parallax dust: three layers of faint one-pixel specks in the space under the ships, which drift across the screen
## slower than the map does (at 0.3, 0.6 and 0.9 of the camera's own motion). When the camera moves, the specks slide behind the ships
## and the stars, so the pilot feels the speed and the distance. Drawing only: it changes nothing in the game, and it uses no random
## numbers (every speck's place comes from a fixed whole-number hash of its cell).
##
## HOW IT WORKS: the node lies under the units (z -9, above the map's own picture). It makes three child nodes, one for each layer,
## and each child draws all its specks with ONE drawing command (draw_multiline). A layer with factor f is a sheet of specks
## placed on a grid of CELLS (a different size for each layer, in world units); a cell holds one speck, or none, at a place worked out
## from the hash of the cell's numbers. Each frame the node moves each child to (1 - f) times the camera's place, which makes the
## sheet slide across the screen at f times the camera's motion. A layer's specks are made again only when the cells the screen
## shows change (the camera crossed a cell line) or the zoom moved a step (so a speck stays about one screen pixel across); Godot
## keeps the drawing between those moments. With Blink.reduced_motion on, or in --sim-only runs (nothing is drawn there), the node is
## hidden and does no work; so is it when the camera is not zoom-limited (an Admiral's free camera or a spectator's, which can show the whole map). It keeps working while the match is paused, so panning a paused match moves the dust too.
##
## WHO USES IT: the World scene has one, the "SpaceDust" node, under "Asteroids" and above "Units" in the tree (it makes its own
## layers in _ready()). tests/flight_cues_check.gd checks it.

## The layers: how much of the camera's motion each follows (0.3 is the farthest and slowest), the size of its cells (world units), the
## chance (in 100) that a cell holds a speck, and how strong the speck is (alpha of ICE).
const LAYERS := [
	{"factor": 0.3, "cell": 700.0, "chance": 70, "alpha": 0.20},
	{"factor": 0.6, "cell": 560.0, "chance": 70, "alpha": 0.28},
	{"factor": 0.9, "cell": 460.0, "chance": 70, "alpha": 0.36},
]
## How many pixels long a speck is (and how wide).
const SPECK_LEN := 1.5
## One zoom step: the speck's world size is made again when the zoom has moved by this factor.
const ZOOM_STEP := 1.15
## A different number for each layer in the hash, so the layers do not repeat one another's places.
const SALT := [3, 7, 11]

## The three child nodes, one for each layer (empty in --sim-only runs).
var _sheets: Array[Node2D] = []
## What each layer's specks were made for: Vector4i(first cell x, last cell x, first cell y, last cell y).
var _cells: Array[Vector4i] = []
## The zoom step each layer's specks were made for.
var _steps: Array[int] = []
## The specks of each layer, as point pairs in the layer's own coordinates.
var _specks: Array[PackedVector2Array] = []
## How many drawing commands each layer made the last time it drew (1, or 0 for a layer with no specks): the check reads it.
var drawn := PackedInt32Array([0, 0, 0])


## Make the three layers (nothing to do in a --sim-only run).
func _ready() -> void:
	if Game.sim_only:
		visible = false
		set_process(false)
		return
	z_index = -9
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in LAYERS.size():
		var sheet := Node2D.new()
		add_child(sheet)
		sheet.draw.connect(_draw_layer.bind(i))
		_sheets.append(sheet)
		_cells.append(Vector4i(1, 0, 1, 0))
		_steps.append(-9999)
		_specks.append(PackedVector2Array())


## Every frame: move each layer to its place, and make its specks again if the screen shows other cells or the zoom stepped.
func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_2d()
	# The dust is for a pilot's zoom range. A camera that is not zoom-limited (an Admiral's free camera, a spectator's) may show the
	# whole map, where one layer would hold thousands of cells: the dust is hidden there and no cell window is made.
	var rig := cam as CameraRig
	var on := not Blink.reduced_motion and (rig == null or rig.zoom_limited())
	if on != visible:
		visible = on
	if not on:
		return
	if cam == null:
		return
	var centre := cam.get_screen_center_position()
	var z := maxf(0.02, cam.zoom.x)
	var half := get_viewport_rect().size / (2.0 * z)
	var step := roundi(log(1.0 / z) / log(ZOOM_STEP))
	for i in LAYERS.size():
		var f := float(LAYERS[i]["factor"])
		var cell := float(LAYERS[i]["cell"])
		# The sheet's place: a point at p on the sheet is at p + (1 - f) x centre in the world, so it is f x centre from the middle
		# of the screen in its own coordinates.
		_sheets[i].position = centre * (1.0 - f)
		var mid := centre * f
		var cells := Vector4i(floori((mid.x - half.x) / cell) - 1, floori((mid.x + half.x) / cell) + 1, floori((mid.y - half.y) / cell) - 1, floori((mid.y + half.y) / cell) + 1)
		if cells != _cells[i] or step != _steps[i]:
			_cells[i] = cells
			_steps[i] = step
			_specks[i] = make_specks(i, cells, pow(ZOOM_STEP, float(step)))
			_sheets[i].queue_redraw()


## The specks of layer `layer` for the cells in `cells` (first x, last x, first y, last y) as point pairs: each speck is a short line
## `px` world units wide (the zoom's step: about one screen pixel) and SPECK_LEN times that long. The places depend on the layer and
## the cell only.
static func make_specks(layer: int, cells: Vector4i, px: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cell := float(LAYERS[layer]["cell"])
	var chance := int(LAYERS[layer]["chance"])
	var salt := int(SALT[layer])
	for ix in range(cells.x, cells.y + 1):
		for iy in range(cells.z, cells.w + 1):
			var h := cell_hash(ix, iy, salt)
			if h % 100 >= chance:
				continue
			var at := Vector2(float(ix) + float((h >> 8) % 1000) / 1000.0, float(iy) + float((h >> 20) % 1000) / 1000.0) * cell
			out.append(at)
			out.append(at + Vector2(px * SPECK_LEN, 0.0))
	return out


## A whole-number hash of a cell (x, y) and a layer's number: the same three numbers always give the same result, on every machine.
## Positive, at most 32 bits.
static func cell_hash(ix: int, iy: int, salt: int) -> int:
	var h := (ix * 374761393 + iy * 668265263 + salt * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 2246822519) & 0xFFFFFFFF
	return (h ^ (h >> 13)) & 0x7FFFFFFF


## Draw layer `layer`: all its specks in one command, on the layer's own node (this runs when that node draws).
func _draw_layer(layer: int) -> void:
	drawn[layer] = 0
	var pts := _specks[layer]
	if pts.is_empty():
		return
	var px := pow(ZOOM_STEP, float(_steps[layer]))
	_sheets[layer].draw_multiline(pts, Palette.with_alpha(Palette.ICE, float(LAYERS[layer]["alpha"])), px)
	drawn[layer] = 1
