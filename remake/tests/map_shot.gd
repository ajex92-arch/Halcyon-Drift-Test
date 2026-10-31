extends Node
## WHAT THIS IS: a windowed picture of the whole map as the game draws it: the
## camera is put in the middle of the map and zoomed out until the whole map is in
## the window, and one screenshot is saved. (tests/map_picture.gd draws the map
## plan without a window; this one shows the real drawing: rocks, lane bands, node
## rings, camps, the fog, the minimap.)
##
## HOW IT WORKS: setup() takes the finished World; after WAIT_FRAMES drawn frames
## the camera is made free, its own work is switched off (a fresh window reports
## the mouse at (0, 0), which would pan the camera), it is moved and zoomed, and the
## picture is saved after the frame has been drawn (`frame_post_draw`). Then the
## test quits. A headless run draws nothing, so it saves nothing.
##
## HOW TO RUN IT (a window opens: park it off-screen so nothing shows on the
## monitor):
##   godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --test=map_shot --shots=<dir> --secs=<match seconds to let pass>
## The picture is <dir>/map_full.png. --secs (default 5) is how many game seconds
## to let pass first, so ships and minions are out.
##
## WHO USES IT: main.gd loads it for --test=map_shot. It only reads the match and
## moves the camera.

## How many drawn frames to wait before the picture (the first frames are not
## complete).
const WAIT_FRAMES := 30
## The space left round the map in the picture (1.05 = 5% on every side).
const MARGIN := 1.05

## The running match (set by setup()).
var world: World
## Drawn frames counted so far.
var _frames := 0
## True once the picture has been taken.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Godot calls this every frame: count frames, then take the picture once.
func _process(_dt: float) -> void:
	if world == null or _done:
		return
	_frames += 1
	if _frames >= WAIT_FRAMES and world.time >= float(Game.opt("secs", 5.0)):
		_done = true
		_shoot()


## Zoom out to the whole map, save the picture and quit.
func _shoot() -> void:
	if DisplayServer.get_name() == "headless":
		print("map_shot: headless, no picture")
		get_tree().quit()
		return
	# Step 1: the camera on the middle of the map, zoomed so that the whole map
	# fits the window with a little room round it.
	var size := get_viewport().get_visible_rect().size
	var z := minf(size.x / (MapLayout.W * MARGIN), size.y / (MapLayout.H * MARGIN))
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.global_position = Vector2(MapLayout.CX, MapLayout.CY)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	# Step 2: let the frame be drawn, then save it.
	await RenderingServer.frame_post_draw
	var dir := str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("map_full.png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("map_shot: %dx%d window, zoom %.4f, saved %s (error %d)" % [int(size.x), int(size.y), z, path, err])
	print("RESULT map_shot %d" % err)
	get_tree().quit()
