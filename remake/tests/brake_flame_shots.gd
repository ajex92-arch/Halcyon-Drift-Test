extends Node
## WHAT THIS IS: a picture test for the main flame of a ship of the line while it
## brakes. Each hull with a "line" handling entry (at most the first MAX_HULLS of
## them, in Ships.ORDER) is launched clear of everything, run up to top speed and
## then braked straight (S held, nose ahead), and the screen is saved at 0.3, 1.0
## and 2.0 seconds into the brake. Next to each picture a FLAME line prints the
## engines' swing and toe and the direction of the main flame, so the numbers sit
## beside the picture and the question "does the one flame draw across the hull?"
## can be answered by looking. It needs a window (not --headless).
##
## HOW IT WORKS: it freezes the match, makes a flight table probe as the other
## flight checks do and uses its own launch, acceleration, reset and step: the real
## flight function flies the ship one step on every physics tick, so the engines
## swing, the flame is placed and the dots stream out in real time as in play. The
## camera is put on the ship each tick, at a zoom where the hull (drawn nose to the
## right, so its length runs across the picture) is half the picture height long, and the
## HUD is hidden as the hull gallery does. Before each picture a ZOOM line prints the
## hull's drawn length in pixels beside the picture height, and an AT line prints where
## the main flame starts, in the ship's own frame. At the second and third picture time a
## control picture follows the real one, taken with the main flame hidden, so what the
## flame draws and what is something else can be told apart. When a hull is done its
## flames are put out before the ship is put away, so a dead ship's flames do not burn
## on in the world where the next hull flies past. At each picture time the
## line is printed and the frame saved without stopping the brake. No random numbers are
## used.
##
## RUN (from the folder that holds remake/):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=brake_flame_shots --shots=<dir>
## OUTPUT: per picture "ZOOM <hull> <ms> hull_px=<n> of <picture height> beam_px=<m> zoom=<z>"
## (the hull's drawn length and width in pixels), then
## "AT <hull> <ms> main_at=(<x>,<y>) of length <L> streams=<n>" (the flame's start in the
## ship's frame: x ahead, y to starboard, in world units), then
## "FLAME <hull> <ms> swivel=<deg> toe=<deg> jet=<deg from the nose> speed=<units/s>"
## then "shot <path>", and files brake_<hull>_<ms>.png (and brake_<hull>_<ms>_nojet.png,
## the control, at 1000 and 2000); the last line is "brake_flame_shots: <n> pictures"
## (the real pictures only). The exit code is 1 when fewer than 3 pictures per hull were
## saved.
##
## WHO USES IT: the lead and builders, to look at the braking flame of the ships of the
## line (ship_visual.gd, _update_jets). It changes only a frozen match that is thrown away.

## The step of the flight, in seconds (the probe's: 60 steps a second).
const DT := 1.0 / 60.0
## The most hulls photographed (the first ones with a line entry, in Ships.ORDER).
const MAX_HULLS := 4
## The picture times, in milliseconds into the brake.
const SHOT_MS := [300, 1000, 2000]
## How much of the picture height the hull's drawn length fills (a share).
const FILL := 0.5
## The picture times that also get a control picture with the main flame hidden.
const CONTROL_MS := [1000, 2000]
## Frames to wait after placing a ship before it brakes, so it is drawn at its start.
const SETTLE_FRAMES := 12

## The running match (main.gd hands it over in setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## The flight table probe whose launch, acceleration, reset and step are used.
var _probe: Node
## Where the ships start: open ground between the lanes (the probe's value).
var _home := Vector2.ZERO
## Pictures saved so far.
var _saved := 0
## Pictures asked for but not yet saved.
var _pending := 0
## Hulls photographed so far.
var _hulls_done := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Photograph every hull, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var hud := get_tree().root.find_child("Hud", true, false)
	if hud != null:
		hud.visible = false
	world.camera.free = true
	world.camera.set_process(false)
	_probe = load("res://tests/flight_table_probe.gd").new()
	add_child(_probe)
	_probe.set("world", world)
	_probe.set("_home", _home)
	Game.big_hull_flight = true
	var hulls: Array = []
	for hid: String in Ships.ORDER:
		if Handling.has_line(hid) and hulls.size() < MAX_HULLS:
			hulls.append(hid)
	for hid: String in hulls:
		await _brake_one(hid)
	while _pending > 0:
		await get_tree().process_frame
	print("brake_flame_shots: %d pictures" % _saved)
	get_tree().quit(0 if _saved >= 3 * hulls.size() and _hulls_done == hulls.size() else 1)


## Launch one hull, run it to top speed, put it back at the start at that speed and
## brake it straight, saving a picture at each of SHOT_MS.
func _brake_one(hid: String) -> void:
	var s: Ship = _probe.call("_launch", hid)
	var acc: Dictionary = _probe.call("_accel_run", s)
	_probe.call("_reset", s, float(acc["top"]))
	var v := s.get_node("Visual") as ShipVisual
	var length := float(s.def.get("length", 26.0))
	var view_h := get_viewport().get_visible_rect().size.y
	# The outline is drawn `span.x` design units long (a hull's design space is 36 units to
	# a ship's length, and the drawing scale is 1 at this zoom), so a zoom of FILL * the
	# picture height / (the outline's drawn length at zoom 1) makes the hull FILL of the
	# height long. Hulls fill their design length differently, so the span is the outline's.
	var z := view_h * FILL / (_span(s).x * length / 36.0)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	world.camera.global_position = s.global_position
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	s.controls.forward = -1.0
	var last_tick := int(round(float(SHOT_MS[SHOT_MS.size() - 1]) / 1000.0 / DT))
	for tick in range(1, last_tick + 1):
		await get_tree().physics_frame
		_probe.call("_step", s)
		world.camera.global_position = s.global_position
		for ms: int in SHOT_MS:
			if tick == int(round(float(ms) / 1000.0 / DT)):
				_shoot(s, v, hid, ms)
	_hulls_done += 1
	# Let the last picture of this hull be saved before the ship is put away.
	while _pending > 0:
		await get_tree().process_frame
	s.controls.forward = 0.0
	# A ship put away is dead, and a dead ship's drawing stops updating, which would leave its
	# flames burning in place where the next hull flies past. Put the flames out first.
	for j: CPUParticles2D in [v.main_jet, v.port_jet, v.star_jet]:
		j.emitting = false
		j.visible = false
	_probe.call("_put", s)


## The hull's outline as Vector2(length, width) in its design space (36 units to a ship's
## length): what AurelianPaint or CinderPaint keep for the hull ("len", and "hw", the
## widest half-width, which only an Aurelian hull has).
func _span(s: Ship) -> Vector2:
	var rec: Dictionary = CinderPaint.hull(s.hull_id) if CinderPaint.alien(s.team) else AurelianPaint.hull(s.hull_id)
	return Vector2(float(rec["len"]), 2.0 * float(rec.get("hw", 0.0)))


## Print the FLAME line for ship `s` now and save the frame after it is drawn; the
## brake goes on meanwhile.
func _shoot(s: Ship, v: ShipVisual, hid: String, ms: int) -> void:
	var jet := rad_to_deg(absf(Vector2.from_angle(s.rotation).angle_to(v.main_jet.direction)))
	var length := float(s.def.get("length", 26.0))
	var z := world.camera.zoom.x
	var px_per_unit := length * float(v.call("_scale")) / 36.0 * z
	var span := _span(s)
	print("ZOOM %s %d hull_px=%d of %d beam_px=%d zoom=%.2f" % [hid, ms, int(round(span.x * px_per_unit)), int(get_viewport().get_visible_rect().size.y), int(round(span.y * px_per_unit)), z])
	var at := (v.main_jet.global_position - s.global_position).rotated(-s.rotation)
	print("AT %s %d main_at=(%.1f,%.1f) of length %.0f streams=%d" % [hid, ms, at.x, at.y, length, v._streams])
	print("FLAME %s %d swivel=%.2f toe=%.2f jet=%.2f speed=%.0f" % [hid, ms, rad_to_deg(s.swivel), rad_to_deg(s.toe), jet, s.velocity.length()])
	_pending += 1
	_save_frame(v, hid, ms)


## Wait for the frame to be drawn, then save it as brake_<hull>_<ms>.png. At the
## CONTROL_MS times a second frame follows with the main flame hidden, saved as
## brake_<hull>_<ms>_nojet.png (it is not counted in the pictures).
func _save_frame(v: ShipVisual, hid: String, ms: int) -> void:
	await RenderingServer.frame_post_draw
	var path := dir.path_join("brake_%s_%d.png" % [hid, ms])
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err == OK:
		_saved += 1
		print("shot ", path)
	else:
		print("brake_flame_shots: FAIL could not save ", path, " (error ", err, ")")
	if ms in CONTROL_MS:
		v.main_jet.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var cpath := dir.path_join("brake_%s_%d_nojet.png" % [hid, ms])
		if get_viewport().get_texture().get_image().save_png(cpath) == OK:
			print("control ", cpath)
		else:
			print("brake_flame_shots: FAIL could not save ", cpath)
		v.main_jet.visible = true
	_pending -= 1
