extends Node
## WHAT THIS IS: the pictures of the yard, and the tour of its tab, run with a window and a human
## Admiral. It saves: the Yard tab with a mixed list (a building row with its percent, a row
## "waiting: ore (needs N)", a row waiting for an unlock, an item on hold, locked hulls "needs X");
## the tab with the fleet full ("Fleet full" in the danger colour with the triangle); a refused order's
## answer under the fleet line and its toast; three Fighters in the middle of their slide out of the bow;
## a Destroyer's warp streak crossing the map and the ship just arrived beside the mothership; and
## a fleet holding its rally.
##
## HOW IT WORKS: setup() finds nothing yet; the first physics frames start the tour, a coroutine
## that sets each scene up through the yard's own functions (the build list, FleetFill, the buy buttons),
## waits some frames, writes the picture and goes on. The match keeps running between pictures (the
## slide and the streak are drawn from the tick count). With --headless there is nothing to draw: the
## tour runs and only prints the lines, which is how it is tried without a window. The caption of each
## picture names what it shows and the match clock.
##
## HOW TO RUN IT (from the folder that holds remake/; pictures need a window):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=admiral --force-hud --seed=7 --test=yard_shots --shots=<dir>
## OUTPUT: "shot <path>" per picture (yard_<nn>_<what>.png) and the last line "yard_shots: done N pictures".
##
## WHO USES IT: main.gd loads it for --test=yard_shots; the builder of the yard, the lead.

## The running match.
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## Pictures saved so far.
var taken := 0
## True once the tour was started.
var _started := false
## The caption drawn over each picture.
var _caption: Label


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 650)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.visible = false
	layer.add_child(_caption)


## Start the tour on the first frame (the HUD is built by then).
func _physics_process(_dt: float) -> void:
	if world == null or _started:
		return
	_started = true
	_tour()


## Wait `n` physics frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Save the picture `what` with its caption after a few drawn frames.
func _shot(what: String, note: String) -> void:
	_caption.text = "%s    %s" % [note, Util.clock(world.time)]
	_caption.visible = true
	for i in 6:
		await get_tree().process_frame
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		await RenderingServer.frame_post_draw
	taken += 1
	var path := dir.path_join("yard_%02d_%s.png" % [taken, what])
	if not headless:
		get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	_caption.visible = false


## Put the camera on `at`, `width` world units across the picture.
func _look(at: Vector2, width: float) -> void:
	world.camera.free = true
	var z: float = get_viewport().get_visible_rect().size.x / width
	# The free camera slides toward its goal: set the goal and the place together, so it stays.
	world.camera.look_at_point(at)
	world.camera.global_position = at
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)


## The middle of the given ships' positions (Vector2.ZERO for none).
func _centre(ships: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for s: Ship in ships:
		if is_instance_valid(s) and s.alive:
			sum += s.global_position
			n += 1
	return sum / float(n) if n > 0 else Vector2.ZERO


## The living bought ships of 	eam (crew ships), optionally of one hull.
func _bought(team: int, hull: String = "") -> Array:
	var out := []
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.profile != null and s.profile.is_crew and (hull == "" or s.hull_id == hull):
			out.append(s)
	return out


## The whole tour.
func _tour() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		print("yard_shots: no HUD (use --force-hud --role=admiral)")
		get_tree().quit()
		return
	await _frames(60)
	var team := world.human_team
	var ts := world.teams[team]
	var prod := ts.production
	var ms := world.mothership(team)
	# Scene 1: the Yard tab with a mixed list.
	ts.facilities["research"] = true
	ts.treasury = 500.0
	var building := prod.add_ship("fighter", 3)
	prod.add_ship("fighter", 3)
	prod.add_ship("flak", 1)
	var held := prod.add_research("lanceBeams")
	await _frames(3)
	building["done"] = 600
	prod.hold(str(held["id"]), true)
	hud._toggle_board()
	hud.board._set_tab("Fleet")
	await _frames(20)
	await _shot("mixed_list", "Yard tab: the buy grid, locked hulls say what they need")
	var scroll := hud.board.get_node("Col/Scroll") as ScrollContainer
	scroll.scroll_vertical = 100000
	await _frames(10)
	await _shot("mixed_list_rows", "Yard tab, scrolled down: a building row, rows waiting for ore and for an unlock, an item on hold")
	scroll.scroll_vertical = 0
	# Scene 2: the fleet full.
	FleetFill.apply(world)
	prod.add_ship("fighter", 3)
	await _frames(20)
	await _shot("fleet_full", "Yard: the fleet at 18/18 (Fleet full in the danger colour with the triangle)")
	# Scene 3: a refused order's answer and its toast.
	(hud.board._cards["yard_buy:bomber"] as Button).pressed.emit()
	await _frames(20)
	await _shot("refused", "Yard: a refused order (a locked hull): the answer, in the danger colour with the triangle")
	hud._toggle_board()
	await _frames(5)
	# Scene 4: three Fighters in the middle of their slide out of the bow.
	prod.items.clear()
	for sq_id: int in world.squads.keys():
		if (world.squads[sq_id] as Squad).team == team:
			world.squads.erase(sq_id)
	for s: Ship in world.ships.duplicate():
		if s.profile != null and s.profile.is_crew and s.team == team:
			world.combat.kill_silently(s)
	prod.capacity.reserved = 0
	ts.treasury = 5000.0
	var slide := prod.add_ship("fighter", 3)
	await _frames(3)
	slide["done"] = int(slide["ticks"]) - 1
	await _frames(2)
	await _frames((RtsHulls.SLIDE_TICKS >> 1) - 2)
	var fresh := _bought(team, "fighter")
	var bow := ms.global_position + Vector2.from_angle(ms.rotation) * ms.half_len
	_look((_centre(fresh) + bow) * 0.5 if not fresh.is_empty() else bow, 1400.0)
	await _frames(2)
	await _shot("slide_mid", "three Fighters part-way through their slide out of the bow")
	# Scene 5: a Destroyer's warp streak, then the ship just arrived.
	Game.unlock_everything = true
	ts.admiral = "human"
	var warp := prod.add_ship("destroyer", 1)
	await _frames(3)
	warp["done"] = int(warp["ticks"]) - RtsHulls.WARP_TICKS - 1
	await _frames(RtsHulls.WARP_TICKS >> 1)
	if warp.has("spot_x"):
		var spot := Vector2(float(warp["spot_x"]), float(warp["spot_y"]))
		_look((spot + Vector2(ms.global_position)) * 0.5 + Vector2(0, 0), 9000.0)
	await _shot("warp_streak", "a Destroyer's warp streak crossing the map")
	warp["done"] = int(warp["ticks"]) - 1
	await _frames(12)
	var ds := _bought(team, "destroyer")
	_look(_centre(ds) if not ds.is_empty() else ms.global_position, 1500.0)
	await _frames(2)
	await _shot("warp_arrived", "the Destroyer just arrived beside the mothership (the ring is the landing)")
	Game.unlock_everything = false
	ts.admiral = "human"
	# Scene 6: a fleet of 18 holding its place (the enemy's is hidden by the fog of war, so the picture shows our own; both teams' bought ships fly the same stand-in brain).
	FleetFill.apply(world)
	await _frames(600)
	var ours := _bought(team)
	_look(_centre(ours) if not ours.is_empty() else ms.global_position, 3000.0)
	print("yard_shots: our team has %d bought ships" % ours.size())
	await _frames(2)
	await _shot("fleet_holding", "a fleet of 18 holding its rally ahead of the mothership")
	print("yard_shots: done %d pictures" % taken)
	get_tree().quit()
