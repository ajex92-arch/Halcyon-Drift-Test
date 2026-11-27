extends Node
## WHAT THIS IS: the picture script for the camera-return flash (T-125, F40a). It saves what the white outline flash on your own ship
## looks like, at the closest and the farthest pilot zoom, so a person can look at it and measure how much of the screen it lights.
##
## HOW IT WORKS: it waits until the human pilot's ship is flying (as return_flash_check does), then for the closest zoom and again
## for the farthest zoom:
##   0. it closes the hangar, which opens over the whole screen at the start of a match (and opens it again at the end);
##   1. it sets the zoom, puts the camera away from the ship (a fifth and a bit of the view's width to the side, so the ship stays on
##      the screen while the camera slides back to it) and waits for a still frame;
##   2. it saves <prefix>_before.png (one frame before the press), presses Space (Input.action_press, then release one frame later)
##      and saves <prefix>_000.png at the frame of the press, then _015, _030 and _045 at the first frame drawn 0.15, 0.3 and 0.45 s
##      after the press (times read from Time.get_ticks_msec). <prefix> is flash_close or flash_far.
## Then it pauses the match, starts a pulse with CameraRig.pulse_return() and saves flash_paused_mid.png about 0.15 s in.
## T-125 round 2, two options for the clean figure of the bright area: --still takes the closest and the farthest series in a
## PAUSED match instead (the picture before, then the pulse, then the four pictures; the same names, no flash_paused_mid), so the
## world does not move between the pictures; --flash-off sets Game.return_flash to false for the run (the member only; the settings
## file is never written), so the same pictures show no flash: the control. Both together give the control of the still series.
## It puts back what it moved (the zoom, the pause, the camera, the pulse memory). The real millisecond of each picture after the
## press goes into flash_times.txt beside the pictures. It prints "flash_shots: done N pictures" and quits; after 90 s of real time it
## prints "flash_shots: timeout". Headless there is nothing to take a picture of: it prints what it would save and saves nothing.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --path remake --resolution 1280x720 -- --auto --role=pilot --force-hud --seed=7 --test=flash_shots --shots=<dir>
##   godot --headless --path remake -- --auto --role=pilot --force-hud --seed=7 --test=flash_shots
##   add --still, and --flash-off for the control, after --test=flash_shots (a window; the folder is --shots=<dir>)
## (No --bot=input: the game must buy and launch the pilot's ship itself.)
##
## WHO USES IT: main.gd loads it for --test=flash_shots. It reads CameraRig, ShipVisual and Game; it changes nothing else.

## Seconds after the press at which the four flash pictures are taken, and the name suffix of each.
const OFFSETS_MS: Array[int] = [0, 150, 300, 450]
const SUFFIXES: Array[String] = ["000", "015", "030", "045"]

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## True once the run has started (it runs once).
var _started := false
## True once it has ended (so the timeout cannot fire after the end).
var _ended := false
## How many pictures were saved (or, headless, would have been).
var _count := 0
## The pictures kept in memory until the end, and their names.
var _images: Array[Image] = []
var _names: PackedStringArray = PackedStringArray()
## The lines of flash_times.txt.
var _times: PackedStringArray = PackedStringArray()
## True in a window with no picture to take (headless).
var _headless := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	if not _headless:
		DirAccess.make_dir_recursive_absolute(dir)


## Every frame: time out after 90 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _ended:
		return
	if Time.get_ticks_msec() > 90000:
		_ended = true
		print("flash_shots: timeout")
		get_tree().quit()
		return
	if _started:
		return
	if get_tree().root.find_child("Hud", true, false) == null or world.camera == null:
		return
	if world.camera.followed() == null:
		return
	_started = true
	_run()


## The whole script, then the summary line and quit.
func _run() -> void:
	var cam := world.camera
	await _frames(3)
	var ship := cam.followed()
	var vis: ShipVisual = null
	if ship != null:
		vis = ship.get_node_or_null("Visual") as ShipVisual
	if ship == null or vis == null:
		print("flash_shots: no ship to take pictures of")
		_finish()
		return
	# What it moves, to put back.
	var was_free := cam.free
	var was_pos := cam.global_position
	var was_free_pos := cam._free_pos
	var was_target := cam.target_zoom
	var was_zoom := cam.zoom
	var was_paused := get_tree().paused
	# The hangar opens over the whole screen at the start of a match: close it for the pictures, open it again at the end.
	var hud := get_tree().root.find_child("Hud", true, false)
	var hangar := hud.get("hangar") as Control if hud != null else null
	var hangar_was := hangar != null and hangar.visible
	if hangar != null:
		hangar.visible = false
	await _smooth_frames()
	var lim := cam.zoom_limits()
	# T-125 round 2: --flash-off turns the setting off for the run (the member only, never the settings file); --still takes the
	# pictures in a paused match, so nothing but the flash differs between the picture before and the ones after.
	var was_flash := Game.return_flash
	if Game.opt("flash-off", false) == true:
		Game.return_flash = false
	if Game.opt("still", false) == true:
		await _still_sequence(cam, ship, vis, lim.y, "flash_close")
		await _still_sequence(cam, ship, vis, lim.x, "flash_far")
	else:
		await _sequence(cam, ship, vis, lim.y, "flash_close")
		await _sequence(cam, ship, vis, lim.x, "flash_far")
		await _paused_mid(cam, ship, vis, lim.y)
	Game.return_flash = was_flash
	# Put everything back.
	get_tree().paused = was_paused
	if hangar != null:
		hangar.visible = hangar_was
	_reset(cam, vis)
	cam.free = was_free
	cam.global_position = was_pos
	cam._free_pos = was_free_pos
	cam.target_zoom = was_target
	cam.zoom = was_zoom
	await _frames(2)
	_finish()


## One zoom: the picture before, the press, and the four pictures after it.
func _sequence(cam: CameraRig, ship: Ship, vis: ShipVisual, z: float, prefix: String) -> void:
	_set_zoom(cam, z)
	_reset(cam, vis)
	_away(cam, ship)
	await _frames(30)
	_away(cam, ship)
	await _frames(2)
	await _save(prefix + "_before")
	# The press is made right after a frame starts (before the camera's own frame), or the camera would not see it as a new press.
	await get_tree().process_frame
	Input.action_press("center_on_ship")
	var t0 := Time.get_ticks_msec()
	for i in OFFSETS_MS.size():
		while Time.get_ticks_msec() - t0 < OFFSETS_MS[i]:
			await get_tree().process_frame
		var name := "%s_%s" % [prefix, SUFFIXES[i]]
		var ms := await _save(name)
		if i == 0:
			Input.action_release("center_on_ship")
		_times.append("%s %d ms after the press (pulse running: %s)" % [name, ms - t0, str(vis.return_active())])
	# Let the pulse end and the one-a-second memory clear before anything else.
	await _wait_ms(1200)


## T-125 round 2 (--still): one zoom in a PAUSED match. The camera is put away from the ship and the match paused, so the world cannot
## move; the picture before is taken, a pulse started with CameraRig.pulse_return() and the four pictures taken at the real times
## of OFFSETS_MS under the same names as _sequence() gives them. The pictures then differ only by the flash. With --flash-off the
## pulse does not start (the setting is off), so the same pictures are the control: they must not differ at all.
func _still_sequence(cam: CameraRig, ship: Ship, vis: ShipVisual, z: float, prefix: String) -> void:
	_set_zoom(cam, z)
	_reset(cam, vis)
	_away(cam, ship)
	await _frames(30)
	_away(cam, ship)
	await _frames(2)
	get_tree().paused = true
	await _frames(6)
	await _settle_still(prefix)
	await _save(prefix + "_before")
	var t0 := Time.get_ticks_msec()
	cam.pulse_return()
	for i in OFFSETS_MS.size():
		while Time.get_ticks_msec() - t0 < OFFSETS_MS[i]:
			await get_tree().process_frame
		var shot_name := "%s_%s" % [prefix, SUFFIXES[i]]
		var ms := await _save(shot_name)
		_times.append("%s %d ms after the pulse started while paused (pulse running: %s)" % [shot_name, ms - t0, str(vis.return_active())])
	get_tree().paused = false
	await _wait_ms(1200)


## T-125 round 2: in the paused match the camera still eases a little (the zoom that follows the ship's speed), so wait until the
## window's picture has not changed for 8 frames in a row (the picture is compared whole), for at most 6 s, and say how it went in
## flash_times.txt. A picture that never settles is reported, and the control shows how much the scene still moves. Headless there
## is no picture to compare.
func _settle_still(prefix: String) -> void:
	if _headless:
		return
	var t_start := Time.get_ticks_msec()
	var last := -1
	var same := 0
	var frames := 0
	while same < 8 and Time.get_ticks_msec() - t_start < 6000:
		await RenderingServer.frame_post_draw
		var h: int = hash(get_viewport().get_texture().get_image().get_data())
		same = same + 1 if h == last else 0
		last = h
		frames += 1
	_times.append("%s paused picture settled: %s after %d frames, %d ms" % [prefix, "yes" if same >= 8 else "NO", frames, Time.get_ticks_msec() - t_start])


## The paused match: start a pulse while paused and save a picture about 0.15 s in.
func _paused_mid(cam: CameraRig, ship: Ship, vis: ShipVisual, z: float) -> void:
	_set_zoom(cam, z)
	_reset(cam, vis)
	_away(cam, ship)
	await _frames(10)
	get_tree().paused = true
	await _frames(2)
	var t0 := Time.get_ticks_msec()
	cam.pulse_return()
	while Time.get_ticks_msec() - t0 < 150:
		await get_tree().process_frame
	var ms := await _save("flash_paused_mid")
	_times.append("flash_paused_mid %d ms after the pulse started while paused (pulse running: %s)" % [ms - t0, str(vis.return_active())])
	get_tree().paused = false
	await _wait_ms(700)


## Take the picture `name`: in a window wait for the frame to be drawn and keep its image in memory (writing a PNG takes about
## 0.4 s, which would hide the steps of 0.15 s; _finish() writes them all at the end); headless just print what would be saved.
## Both count it. Returns the Time.get_ticks_msec() reading of the drawn frame.
func _save(name: String) -> int:
	_count += 1
	if _headless:
		print("flash_shots would save ", name, ".png")
		return Time.get_ticks_msec()
	await RenderingServer.frame_post_draw
	var ms := Time.get_ticks_msec()
	_names.append(name)
	_images.append(get_viewport().get_texture().get_image())
	return ms


## The summary line (and the times file in a window), then quit.
func _finish() -> void:
	if _ended:
		return
	_ended = true
	for i in _images.size():
		var path := dir.path_join(_names[i] + ".png")
		_images[i].save_png(path)
		print("shot ", path)
	if not _headless and not _times.is_empty():
		var f := FileAccess.open(dir.path_join("flash_times.txt"), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_times) + "\n")
			f.close()
	print("flash_shots: done %d pictures" % _count)
	get_tree().quit()


## Zoom to `z` at once (the camera takes a zoom written from outside as the wheel's choice).
func _set_zoom(cam: CameraRig, z: float) -> void:
	cam.target_zoom = z
	cam.zoom = Vector2(z, z)


## Forget every pulse and the camera's one-a-second memory.
func _reset(cam: CameraRig, vis: ShipVisual) -> void:
	vis._return_ms = -100000
	cam._flash_ms = -100000
	Input.action_release("center_on_ship")
	cam.centre_latched = false


## Put the camera to the side of the ship by a fifth and a bit of the view's width (the camera's centre limit is 15%): it stays free
## there, and the ship is still on the screen, so the flash can be seen as the camera slides back.
func _away(cam: CameraRig, ship: Ship) -> void:
	var view_w := get_viewport().get_visible_rect().size.x / maxf(0.02, cam.zoom.x)
	cam.free = true
	cam.global_position = ship.global_position + Vector2(view_w * 0.25, 0.0)
	cam._free_pos = cam.global_position
	cam._latch_was = cam.centre_latched


## A window's first seconds can draw slowly (a frame of half a second would hide a 0.15 s step): wait until 20 frames in a row each
## took 45 ms or less, for at most 40 s, and print how it went. Headless there is nothing to wait for.
func _smooth_frames() -> void:
	if _headless:
		await _frames(5)
		return
	var t_start := Time.get_ticks_msec()
	var last := t_start
	var run := 0
	var worst := 0
	while run < 20 and Time.get_ticks_msec() - t_start < 40000:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var d := now - last
		last = now
		worst = maxi(worst, d)
		run = run + 1 if d <= 45 else 0
	_times.append("smooth frames: %d in a row after %d ms (worst frame %d ms)" % [run, Time.get_ticks_msec() - t_start, worst])


## Wait `ms` real milliseconds (drawn frames).
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
