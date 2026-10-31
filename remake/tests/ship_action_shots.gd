extends Node
## WHAT THIS IS: a picture test for how ships look in a real fight. During an
## AI match it photographs one ship of every hull type, for each team, while an
## enemy is near it ("in action"), with a caption (team, hull, match clock,
## enemies near). Hulls that never meet an enemy get a fallback picture at the
## end, marked "(no enemy near)"; hulls that never appear at all are listed in
## the last line. It joined the test branch on 2026-10-18 (T-22, from a side
## session) as a check for visual items next to the hull gallery's frozen sheets.
##
## HOW IT WORKS: every 20th frame it looks for the ship still without a picture
## that has the most enemy ships and minions within --near. It then pauses the
## match (physics off, camera still), puts the camera on that ship at --view
## world units across, waits 20 frames for the drawing to settle, saves the
## frame and lets the match go on. It needs a window (not --headless).
##
## RUN (from the folder that holds remake/):
##   godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --seed=7 --speed=4 --test=ship_action_shots --secs=1200 --shots=<dir>
## Options: --view=1600 (world units across the picture), --near=900 (enemy radius),
## --hulls=a,b,c (hull ids to look for), --late (start at 25:00 fully teched, as perf_probe --late),
## --clip=0 (make no video clip), --clip-fps=N (the clip's frames a second, default 12).
## OUTPUT: "shot <path>  enemies near N" per picture; files action_<nn>_<team>_<hull>_<clock>.png;
## then one "clip ..." line: the pictures, in the order they were taken, stitched into action_clip.mp4
## with ffmpeg (a short video that a phone plays; tests/lib/shot_clip.gd has the settings), or why there
## is none (no ffmpeg on the PATH);
## last line "ship_action_shots: done N pictures, missing M: <team:hull ...>".
##
## WHO USES IT: the lead and builders, for visual items on the test branch
## (pictures in action, next to tests/hull_gallery.gd's frozen sheets). It hands its pictures to
## ShotClip.make() (tests/lib/shot_clip.gd) for the clip.

## The clip maker (tests/lib/shot_clip.gd; it has no class_name).
const ShotClip := preload("res://tests/lib/shot_clip.gd")

## The match world (Main hands it over in setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## How long to watch, in game seconds from the start (--secs).
var secs := 1200.0
## The world time when watching started (25:00 with --late).
var start_t := 0.0
## How wide each picture is, in world units (--view).
var view_w := 1600.0
## How close an enemy must be to count as near, in world units (--near).
var near := 900.0
## The hull ids to photograph (--hulls).
var hulls: Array = []
## The (team, hull) pairs still without a picture, as "team:hull" keys.
var pending := {}
## Pictures saved so far.
var taken := 0
## The file names of the pictures saved so far, in the order they were taken;
## the clip is made from them.
var saved := PackedStringArray()
## True while a picture is being taken (the per-frame search waits).
var busy := false
## True once the fallback pictures and the summary have started.
var finishing := false
## Frames counted, so the search runs only every 20th frame.
var frame := 0
## The caption drawn over each picture.
var caption: Label


## Main calls this once the match is built: read the options, apply --late,
## add the caption layer and free the camera.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	secs = float(Game.opt("secs", 1200.0))
	view_w = float(Game.opt("view", 1600.0))
	near = float(Game.opt("near", 900.0))
	for h in str(Game.opt("hulls", "scout,fighter,lance,bomber,logistics,support,flak,ion,destroyer,battlecruiser")).split(","):
		hulls.append(h.strip_edges())
	for t in [0, 1]:
		for h in hulls:
			pending["%d:%s" % [t, h]] = true
	if Game.opt("late", false):
		LateGame.apply(world)
		print("ship_action_shots: late start at ", Util.clock(world.time))
	start_t = world.time
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24, 24)
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.visible = false
	layer.add_child(caption)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.camera.free = true


## Every 20th frame: photograph the waiting ship with the most enemies near
## it. When the time is up or every pair has its picture: _finish().
func _process(_dt: float) -> void:
	if world == null or busy:
		return
	if world.time - start_t >= secs or pending.is_empty():
		_finish()
		return
	frame += 1
	if frame % 20 != 0:
		return
	var pick := _best_pending(true)
	if pick.is_empty():
		return
	busy = true
	await _photograph(pick[0], int(pick[1]), "")
	busy = false


## The pending (team, hull) ship with the most enemies near it: [ship, enemies], or [].
func _best_pending(need_enemy: bool) -> Array:
	var best: Array = []
	var best_n := -1
	var scratch: Array = []
	for s: Ship in world.ships:
		if not is_instance_valid(s) or not s.alive or s.team > 1:
			continue
		if not pending.has("%d:%s" % [s.team, s.hull_id]):
			continue
		var n := 0
		for obj in world.unit_hash.query(s.global_position, near, scratch):
			if not is_instance_valid(obj):
				continue
			var u: Unit = obj
			if u.alive and u.team != s.team and u.team <= 1 and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION):
				n += 1
		if need_enemy and n == 0:
			continue
		if n > best_n:
			best_n = n
			best = [s, n]
	return best


## Freeze the match, put the camera on the ship, caption it, save the frame.
func _photograph(s: Ship, n_enemies: int, note: String) -> void:
	world.set_physics_process(false)
	world.camera.set_process(false)
	var z: float = get_viewport().get_visible_rect().size.x / view_w
	world.camera.global_position = s.global_position
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	var team_name: String = Rules.TEAM_DISPLAY[s.team]
	var clock := Util.clock(world.time)
	caption.text = "%s  %s    %s    enemies near: %d %s" % [team_name, s.hull_id, clock, n_enemies, note]
	caption.visible = true
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	taken += 1
	var file := "action_%02d_%s_%s_%s.png" % [taken, team_name.to_lower(), s.hull_id, clock.replace(":", "m")]
	var path := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	saved.append(file)
	print("shot ", path, "  enemies near ", n_enemies, " ", note)
	caption.visible = false
	pending.erase("%d:%s" % [s.team, s.hull_id])
	world.camera.set_process(true)
	world.set_physics_process(true)


## Fallback pictures for hulls that never met an enemy, then the summary, then quit.
func _finish() -> void:
	if finishing:
		return
	finishing = true
	busy = true
	while true:
		var pick := _best_pending(false)
		if pick.is_empty():
			break
		await _photograph(pick[0], int(pick[1]), "(no enemy near)")
	var missing := PackedStringArray()
	for k in pending.keys():
		missing.append(str(k))
	ShotClip.make(dir, saved, "action_clip.mp4")
	print("ship_action_shots: done %d pictures, missing %d: %s" % [taken, missing.size(), ", ".join(missing)])
	get_tree().quit()
