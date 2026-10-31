extends Node
## WHAT THIS IS: a picture test for the Bomber, run with a window during an AI
## match. It waits for the moments worth a picture and saves each one: a Bomber
## halfway through a torpedo run (the bar and the fan of lines), once for each
## team; a torpedo in flight; the rear gun firing; a Bomber of each team at rest;
## a pilot's torpedo of each team close up, with the camera right on it; and, for
## each team, scenes of the new run set up for the picture (the fan at 0, half
## and full tightness, the wait for the release, the unarmed torpedoes, a dud,
## the pilot's sight and the alarm's edge marker: see `wanted`). Every picture has
## a caption (the team, what it shows, the match clock).
##
## HOW IT WORKS: every frame it looks for the next moment on its list. When one
## shows up it pauses the match (physics off, camera still), puts the camera
## where the thing is, waits 20 frames for the drawing to settle, saves the
## frame and lets the match go on. After the list is done, or --secs of match
## time have passed, it prints one summary line and quits. It needs a window
## (not --headless).
##
## HOW TO RUN IT (from the folder that holds remake/):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=spectator --late --speed=4 --test=bomber_shots --secs=900 --shots=<dir>
## --late starts at 25:00 with both sides fully teched, so Bombers are about.
## --view=N is how many world units fit across a picture (default 1400).
## OUTPUT: "shot <path>" per picture, files bomber_<nn>_<what>_<clock>.png, each
## followed by "shot_info torpedoes=<n> unarmed=<n> draw_calls=<n>" (the
## torpedoes in flight, how many of them are not armed yet, and the frame's draw
## calls), and the last line "bomber_shots: done N pictures, missing M: <names>".
##
## WHO USES IT: main.gd loads it for --test=bomber_shots. The lead and builders,
## for the Bomber's pictures. It reads the ships' runs and guns and the
## projectile lists, and moves the World's CameraRig.

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## How long to watch, in game seconds from the start (--secs).
var secs := 900.0
## The world time when watching began.
var start_t := 0.0
## How wide each picture is, in world units (--view).
var view_w := 1400.0
## The pictures still wanted, in this order of preference. Each name says what
## to wait for: run_0 / run_1 (a Bomber of that team at least half way through
## a torpedo run), flight (a Bomber's torpedo in the air), tail (a Bomber
## whose rear gun has a target), rest_0 / rest_1 (a Bomber of that team that
## is not on a run), torp_0 / torp_1 (a pilot's torpedo of that team, 0.2 to
## 1.1 seconds after its launch, the camera right on it, --view units across).
## The rest are scenes set up for the picture while the match is frozen (the
## match is thrown away afterwards): fan_wide / fan_half / fan_tight (a Bomber of
## that team on a run, its fan set to 0, 180 and 360 points), ready (the bar full
## and the wait for the release half drained, on the ship the human flies), unarmed
## (the three torpedoes of a run just after the launch, dimmed because they are not
## armed yet), dud (a torpedo that touches an enemy ship inside its arming
## distance), sight (a Bomber not on a run with an enemy in its fan, on the ship
## the human flies) and alarm (an enemy pilot ship in the fan of a Bomber's run, as
## the human's ship: the alarm's edge marker). Every name has the team after it.
var wanted: Array = ["run_0", "run_1", "flight", "tail", "rest_0", "rest_1", "torp_0", "torp_1",
	"fan_wide_0", "fan_half_0", "fan_tight_0", "fan_wide_1", "fan_half_1", "fan_tight_1",
	"ready_0", "ready_1", "unarmed_0", "unarmed_1", "dud_0", "dud_1", "sight_0", "sight_1", "alarm_0", "alarm_1"]
## Pictures saved so far.
var taken := 0
## True while a picture is being taken.
var busy := false
## The caption drawn over each picture.
var caption: Label


## Main calls this once the match is built: read the options, apply --late,
## add the caption layer and free the camera.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	secs = float(Game.opt("secs", 900.0))
	view_w = float(Game.opt("view", 1400.0))
	if Game.opt("late", false):
		LateGame.apply(world)
	start_t = world.time
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24, 24)
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.visible = false
	layer.add_child(caption)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.camera.free = true


## Every frame: look for the next wanted moment; at the end, print the summary.
func _process(_dt: float) -> void:
	if world == null or busy:
		return
	if world.time - start_t >= secs or wanted.is_empty():
		_finish()
		return
	for want: String in wanted:
		var spot := _find(want)
		if spot.is_empty():
			continue
		busy = true
		await _photograph(want, spot[0], float(spot[1]), spot[2] if spot.size() > 2 else null)
		busy = false
		return


## Look for the moment `want` (see `wanted`). Returns [world point to look at,
## picture width in world units], or [] when it is not there now.
func _find(want: String) -> Array:
	match want:
		"run_0", "run_1":
			for s: Ship in world.ships:
				if s.alive and s.hull_id == "bomber" and s.team == int(want.substr(4)) and s.run_frac() >= 0.5 and s.run_frac() < 0.95:
					# The ship sits a little behind the middle, so its bar and the
					# line ahead of it are both in the picture.
					return [s.global_position + Vector2.from_angle(s.rotation) * 250.0, view_w * 0.9]
		"flight":
			var p := world.projectiles
			for i in p.active:
				if p.live[i] == 1 and p.kind[i] == Rules.W_TORP and p.src_pilot[i] == 1 and p.life[i] < 1.9 and p.life[i] > 1.4:
					# Half a second after the launch: look between the torpedo and
					# the ship that fired it, when that ship is still there.
					var src = p.src_ref[i]
					if src != null and is_instance_valid(src):
						return [(p.pos[i] + (src as Unit).global_position) * 0.5, view_w * 0.8]
					return [p.pos[i], view_w * 0.5]
		"tail":
			for s: Ship in world.ships:
				if s.alive and s.hull_id == "bomber":
					for m: WeaponMount in s.mounts:
						if m.weapon_id == "tail_gun" and m.engaged and m.cd > 0.1:
							return [s.global_position, view_w * 0.25]
		"rest_0", "rest_1":
			for s: Ship in world.ships:
				if s.alive and s.hull_id == "bomber" and s.team == int(want.substr(5)) and s.run_frac() == 0.0:
					return [s.global_position, view_w * 0.3]
		"torp_0", "torp_1":
			var p := world.projectiles
			for i in p.active:
				# A torpedo starts with 2.3 seconds of life, so 0.2 to 1.1 seconds
				# after its launch it has 2.1 down to 1.2 seconds left.
				if p.live[i] == 1 and p.kind[i] == Rules.W_TORP and p.src_pilot[i] == 1 and p.team[i] == int(want.substr(5)) and p.life[i] >= 1.2 and p.life[i] <= 2.1:
					return [p.pos[i], view_w]
		"fan_wide_0", "fan_half_0", "fan_tight_0", "fan_wide_1", "fan_half_1", "fan_tight_1", "ready_0", "ready_1":
			# A Bomber of that team on a run, between the start of the hold and its end.
			var team := int(want.right(1))
			for s: Ship in world.ships:
				if s.alive and s.hull_id == "bomber" and s.team == team and s.run_on() and s.run_frac() >= 0.3 and s.run_frac() < 0.95:
					# The ship low in the picture, so its bars and the first stretch of the fan are in it.
					return [s.global_position + Vector2.from_angle(s.rotation) * 150.0, view_w * 0.8, s]
		"unarmed_0", "unarmed_1":
			# The three torpedoes of a run that left less than 0.15 seconds ago: not armed yet.
			var p := world.projectiles
			var sum := Vector2.ZERO
			var n := 0
			for i in p.active:
				if p.live[i] == 1 and p.lane[i] >= 0 and p.team[i] == int(want.right(1)) and not p.armed(i) and p.life[i] > 2.15:
					sum += p.pos[i]
					n += 1
			if n >= 3:
				return [sum / float(n), view_w * 0.5]
		"dud_0", "dud_1", "alarm_0", "alarm_1":
			# A Bomber of that team that is on a run (alarm) or not (dud), and an enemy pilot ship to use.
			var team := int(want.right(1))
			for s: Ship in world.ships:
				if s.alive and s.hull_id == "bomber" and s.team == team and (s.run_on() == want.begins_with("alarm")) and _enemy_ship(s) != null:
					return [s.global_position, view_w * (1.2 if want.begins_with("alarm") else 0.35), s]
		"sight_0", "sight_1":
			# A Bomber of that team not on a run, with an enemy in its fan.
			var team := int(want.right(1))
			for s: Ship in world.ships:
				if s.alive and s.hull_id == "bomber" and s.team == team and not s.run_on() and FanPaint.enemy_in_fan(s):
					return [s.global_position + Vector2.from_angle(s.rotation) * 250.0, view_w * 0.8, s]
	return []


## The nearest enemy pilot ship of Bomber `s` (a live ship of the other team), or null.
func _enemy_ship(s: Ship) -> Ship:
	var best: Ship = null
	for e: Ship in world.ships:
		if e.alive and e.team != s.team and e.profile != null and (best == null or e.global_position.distance_squared_to(s.global_position) < best.global_position.distance_squared_to(s.global_position)):
			best = e
	return best


## Set up the scene of picture `want` for Bomber `s` while the match is frozen (see
## `wanted`). Returns what to put back afterwards, and "look" (the world point to
## put the camera on) when the scene moves it.
func _stage(want: String, s: Ship) -> Dictionary:
	var undo := {}
	if s == null:
		return undo
	if want.begins_with("fan_"):
		undo["fan_points"] = s.fan_points
		s.fan_points = {"wide": 0, "half": 180, "tight": 360}[want.get_slice("_", 1)]
	elif want.begins_with("ready_"):
		# The bar full, the wait for the release half gone, on the human's ship (it shows the hint).
		undo["human"] = s.profile.is_human
		undo["wind"] = s.run_mount.run.wind
		undo["ready"] = s.run_mount.run.ready
		s.profile.is_human = true
		s.run_mount.run.wind = s.run_mount.run.wind_ticks
		s.run_mount.run.ready = s.run_mount.run.ready_ticks / 2
	elif want.begins_with("sight_"):
		undo["human"] = s.profile.is_human
		s.profile.is_human = true
	elif want.begins_with("dud_"):
		# A torpedo 120 units short of an enemy ship's edge: it touches it unarmed.
		var e := _enemy_ship(s)
		var from := e.global_position + Vector2(-(e.hit_radius() + 120.0), 0.0)
		world.projectiles.spawn(from, Vector2(520.0, 0.0), 2.3, 100.0, Rules.W_TORP, Weapons.get_def("torpedo"), s, null)
		for _i in 20:
			world.projectiles.tick(1.0 / 60.0)
		undo["look"] = e.global_position + Vector2(-(e.hit_radius() + 100.0), 0.0)
	elif want.begins_with("alarm_"):
		# An enemy pilot ship 700 units ahead in the fan, flown by the human.
		var e := _enemy_ship(s)
		undo["ship"] = e
		undo["at"] = e.global_position
		undo["human"] = world.human
		e.global_position = s.run_mount.world_pos() + Vector2.from_angle(s.rotation) * 700.0
		world.registry.rebuild_hashes()
		world.human = e.profile
		undo["look"] = e.global_position
	return undo


## Put back what _stage() changed.
func _unstage(want: String, s: Ship, undo: Dictionary) -> void:
	if s == null:
		return
	if want.begins_with("fan_"):
		s.fan_points = int(undo["fan_points"])
	elif want.begins_with("ready_"):
		s.profile.is_human = bool(undo["human"])
		s.run_mount.run.wind = int(undo["wind"])
		s.run_mount.run.ready = int(undo["ready"])
	elif want.begins_with("sight_"):
		s.profile.is_human = bool(undo["human"])
	elif want.begins_with("alarm_"):
		(undo["ship"] as Ship).global_position = undo["at"]
		world.human = undo["human"]
		world.registry.rebuild_hashes()


## Freeze the match, put the camera on `at`, caption the picture and save it,
## then print the "shot" line and the "shot_info" line.
func _photograph(want: String, at: Vector2, width: float, ship: Ship = null) -> void:
	world.set_physics_process(false)
	world.camera.set_process(false)
	# A staged scene is set up first (see `wanted`); it may move the camera's target.
	var undo := _stage(want, ship)
	if undo.has("look"):
		at = undo["look"]
	var z: float = get_viewport().get_visible_rect().size.x / width
	world.camera.global_position = at
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	var clock := Util.clock(world.time)
	caption.text = "%s    %s" % [want, clock]
	if want.begins_with("fan_") and ship != null:
		caption.text += "    %d points, half-angle %.1f degrees" % [ship.fan_points, rad_to_deg(RunFan.half_angle(ship.run_mount.def, ship.fan_points))]
	caption.visible = true
	# A puff of smoke is short-lived: take the dud's picture soon.
	for i in (5 if want.begins_with("dud_") else 20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	taken += 1
	var path := dir.path_join("bomber_%02d_%s_%s.png" % [taken, want, clock.replace(":", "m")])
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	# The torpedoes in flight (live slots of the torpedo kind) and the draw
	# calls of the frame just drawn.
	var torpedoes := 0
	var unarmed := 0
	var rounds := world.projectiles
	for j in rounds.active:
		if rounds.live[j] == 1 and rounds.kind[j] == Rules.W_TORP:
			torpedoes += 1
			if not rounds.armed(j):
				unarmed += 1
	print("shot_info torpedoes=%d unarmed=%d draw_calls=%d" % [torpedoes, unarmed, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	caption.visible = false
	wanted.erase(want)
	_unstage(want, ship, undo)
	world.camera.set_process(true)
	world.set_physics_process(true)


## The summary line, then quit.
func _finish() -> void:
	busy = true
	print("bomber_shots: done %d pictures, missing %d: %s" % [taken, wanted.size(), ", ".join(PackedStringArray(wanted))])
	get_tree().quit()
