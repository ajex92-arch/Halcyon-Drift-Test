extends Node
## WHAT THIS IS: a pixel check of the minimap's drawing (the HUD cost cuts: the minimap keeps its still layers' picture, the
## cheaper unit loop). It saves the minimap's own pixels at chosen match times, so two builds can be compared pixel by pixel,
## and (for a build that caches the still layers) checks that the cached picture equals a full redraw at many moments.
##
## HOW IT WORKS: setup() takes the finished World. At each time of --look-times (match seconds, default 60,180,420,780) the
## world is stopped for a few frames (its nodes stop processing, so the picture depends on that match tick alone), the
## minimap is made to redraw at once, and the pixels under it are saved to <dir>/m_<seat>_<time>.png after the frame is drawn
## (`frame_post_draw`). Every --look-every match seconds (default 5, 0 = never) the same is done twice, once as the minimap
## redraws by itself and once after its still layer's memory is wiped (`forget_still()`; a build without it just draws twice), and the two
## pictures must be identical. The run ends at --look-end match seconds (default 900) with "minimap_look: done N checks, M
## mismatches". Run it with a fixed frame step so the frames fall the same in every run.
##
## HOW TO RUN IT (a window opens: park it off-screen):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy --fixed-fps 60 -- --auto --role=pilot --seed=7 --test=minimap_look --shots=<dir>
## (--all-ai instead of --auto --role=pilot for the spectator's minimap, which has no fog.)
##
## WHO USES IT: main.gd loads it for --test=minimap_look. It only reads the match and stops and restarts its nodes.

## How many frames the stopped world is left to draw the minimap before a picture is taken.
const SETTLE_FRAMES := 3

## The running match (set by setup()).
var world: World
## The HUD.
var _hud: Hud
## The minimap under test.
var _mm: Minimap
## The folder the pictures go into.
var _dir := ""
## How many checks were made.
var _checks := 0
## How many of them failed.
var _bad := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


## The whole run (see HOW IT WORKS).
func _run() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	while hud == null:
		await get_tree().process_frame
		hud = get_tree().root.find_child("Hud", true, false) as Hud
	_hud = hud
	_mm = hud.minimap
	var looks: Array = []
	for s in str(Game.opt("look-times", "60,180,420,780")).split(",", false):
		looks.append(float(s))
	var every := float(Game.opt("look-every", 5.0))
	var end := float(Game.opt("look-end", 900.0))
	var next_check := every
	while world.time < end:
		await get_tree().process_frame
		if not looks.is_empty() and world.time >= float(looks[0]):
			var t: float = looks.pop_front()
			var img := await _picture()
			if img != null:
				img.save_png("%s/m_%s_%d.png" % [_dir, world.human_role, int(t)])
				print("minimap_look: saved %d s (%s)" % [int(t), world.human_role])
		elif every > 0.0 and world.time >= next_check:
			next_check += every
			await _check(world.time)
	print("minimap_look: done %d checks, %d mismatches" % [_checks, _bad])
	get_tree().quit()


## Close any big panel (a pilot's hangar covers the minimap) and lay the HUD out again.
func _clear_panels() -> void:
	_hud.call("_close_others", null)
	_hud.call("_refresh")


## Stop the world, redraw the minimap now and return its pixels (null when it is not on screen).
func _picture() -> Image:
	_clear_panels()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_mm._t = 0.0
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = null
	if _mm.is_visible_in_tree():
		img = get_viewport().get_texture().get_image().get_region(Rect2i(_mm.get_global_rect()))
	world.process_mode = Node.PROCESS_MODE_INHERIT
	return img


## The same moment twice, as the minimap draws by itself and after its still layer's memory is wiped (a build without that memory just draws twice), and the two must match. Every build goes through the same stops of the world, so two builds' matches stay the same match.
func _check(at: float) -> void:
	_clear_panels()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_mm._t = 0.0
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not _mm.is_visible_in_tree():
		world.process_mode = Node.PROCESS_MODE_INHERIT
		return
	var rect := Rect2i(_mm.get_global_rect())
	var a := get_viewport().get_texture().get_image().get_region(rect)
	if _mm.has_method("forget_still"):
		_mm.call("forget_still")
	_mm._t = 0.0
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var b := get_viewport().get_texture().get_image().get_region(rect)
	world.process_mode = Node.PROCESS_MODE_INHERIT
	_checks += 1
	if a.get_data() != b.get_data():
		_bad += 1
		print("FAIL minimap_look: at %d s the cached still layer differs from a full redraw" % int(at))
