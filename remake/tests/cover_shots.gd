extends Node
## WHAT THIS IS: a photo tour of the map's cover, run with a window. For one gas
## cloud and one hidden pocket of Halcyon's it takes two pictures each: from
## outside (two Vhorr ships stand inside the patch and are hidden from the
## Halcyon watcher) and from inside (a Halcyon ship stands in the patch too, so
## the patch is open and the ships are seen). It is for looking at how the cover
## is drawn and what the fog does with it.
##
## HOW IT WORKS: setup() starts run(), a coroutine (a function that can stop and
## wait with `await`) that does the patches one after another. For each patch it
## finds a spot of open ground about 1,500 units from the patch's middle from
## which the fog's rays reach the middle, stands a Halcyon scout there to light
## the place, puts two Vhorr fighters in the patch, frees the camera, points it
## at the patch, waits for the frame to be drawn and saves it. Then it adds a
## Halcyon fighter inside the patch and saves the second picture. It prints
## "seen N of 2 Vhorr ships" for each picture (0 from outside, 2 from inside)
## and "cover_shots: done, N failures", then quits.
##
## HOW TO RUN IT (from the folder that holds remake/; "godot" is the Godot console
## program):
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --no-pilots --no-admiral-ai --no-jungle --test=cover_shots --shots=<dir>
## No --headless here: it needs a window. --shots is the folder for the pictures
## (default: Godot's user data folder); --patches=a,b picks other patches than the
## default two. The files are cover_<patch>_outside.png
## and cover_<patch>_inside.png.
##
## WHO USES IT: main.gd loads it for --test=cover_shots. It moves the World's
## CameraRig and makes test ships; it changes nothing else in the match.

## How many world units fit across the picture (the zoom).
const VIEW_WIDTH := 3600.0
## The patches to photograph by default (their names in MapCover); --patches=a,b
## names others.
const PATCHES := ["jungle_north", "pocket_north_mid"]

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## How many checks failed.
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.minion_director.next_wave = INF
	run()


## Wait `secs` seconds of game time (physics frames).
func wait(secs: float) -> void:
	var end := world.time + secs
	while world.time < end:
		await get_tree().physics_frame


## Launch a test ship of hull `hid` for team `team` at `at`, standing still.
func spawn(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new("Test-" + hid, team, 40 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.global_position = at
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## The middle of patch `id` (the mean of its cell centres).
func patch_middle(id: int) -> Vector2:
	var vision := world.vision
	var sum := Vector2.ZERO
	var cells: PackedInt32Array = vision.cover.cells[id]
	for c in cells:
		sum += Vector2((float(c % vision.cols) + 0.5) * vision.cell, (float(c / vision.cols) + 0.5) * vision.cell)
	return sum / float(cells.size())


## A spot of open ground about `radius` from `middle` from which the fog's rays
## reach `middle`, or Vector2.INF if there is none.
func watch_spot(middle: Vector2, radius: float) -> Vector2:
	var vision := world.vision
	var target := vision.cell_of(middle)
	for k in 32:
		var spot := middle + Vector2.from_angle(float(k) * TAU / 32.0) * radius
		if world.asteroids.blocked(spot, 40.0):
			continue
		var rc := int(ceil(radius / vision.cell)) + 2
		if (vision.rays.cells_seen(vision.cell_of(spot), rc) as PackedInt32Array).has(target):
			return spot
	return Vector2.INF


## Point the free camera at `p` and save the picture to `name`.
func shoot(p: Vector2, name: String) -> void:
	var z := get_viewport().get_visible_rect().size.x / VIEW_WIDTH
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.look_at_point(p)
	world.camera.global_position = p
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	await wait(0.5)
	await RenderingServer.frame_post_draw
	var path := dir.path_join(name)
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	world.camera.set_process(true)


## Take the two pictures of every patch, then quit.
func run() -> void:
	await wait(1.0)
	for d in world.mining_drones.duplicate():
		world.combat.kill_silently(d)
	var names: PackedStringArray = PackedStringArray(PATCHES)
	if Game.opt("patches", null) != null:
		names = str(Game.opt("patches")).split(",")
	for pname: String in names:
		var id := world.vision.cover.names.find(pname)
		if id < 1:
			print("FAIL no patch named ", pname)
			fails += 1
			continue
		var mid := patch_middle(id)
		var spot := Vector2.INF
		for radius in [1500.0, 1100.0, 1900.0, 800.0, 2300.0]:
			if spot == Vector2.INF:
				spot = watch_spot(mid, radius)
		if spot == Vector2.INF:
			print("FAIL no watch spot for ", pname)
			fails += 1
			continue
		var watcher := spawn("scout", 0, spot)
		var a := spawn("fighter", 1, mid + Vector2(-120, 0))
		var b := spawn("fighter", 1, mid + Vector2(140, 90))
		await wait(1.5)
		var seen := int(a.visible_to(0)) + int(b.visible_to(0))
		print("%s from outside: seen %d of 2 Vhorr ships (watcher at %s, patch at %s)" % [pname, seen, spot, mid])
		if seen != 0:
			fails += 1
		await shoot(mid, "cover_%s_outside.png" % pname)
		var friend := spawn("fighter", 0, mid + Vector2(0, -160))
		await wait(1.5)
		seen = int(a.visible_to(0)) + int(b.visible_to(0))
		print("%s from inside: seen %d of 2 Vhorr ships" % [pname, seen])
		if seen != 2:
			fails += 1
		await shoot(mid, "cover_%s_inside.png" % pname)
		for s: Ship in [watcher, a, b, friend]:
			world.combat.kill_silently(s)
	print("cover_shots: done, %d failures" % fails)
	get_tree().quit()
