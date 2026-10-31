extends Node
## WHAT THIS IS: a photo tour of the new structures, run with a window: the home
## end of a lane (the three lane turrets, the defense post beside the inhibitor
## turret and the five launch pads), and the four shared jungle nodes in the states
## the contested-point display shows (HELD, BUILDING, LOCKED, CONTESTED, CLEAR and
## OPEN), with the minimap in the corner. It only reads the match and builds a few
## ships and turrets of its own for the pictures.
##
## HOW IT WORKS: a frozen match (physics off between steps, as the hull gallery
## does) in stages. Stage A shows the lane's home end. Stage B builds the states:
## a finished turret at Top Jungle South (HELD), one being built at Bottom Jungle
## North (BUILDING), a destroyed one at Bottom Jungle South (LOCKED), and one
## Aurelian and two Vhorr pilot ships at Top Jungle North (CONTESTED); the match
## runs 20 ticks so the sites count who is inside, then it takes the pictures of
## the top pair and the bottom pair. Stage C takes the Vhorr ships away (CLEAR, for
## Aurelian) and the turret at Top Jungle South away (it locks: LOCKED), runs again
## and takes the top pair once more; the last picture has no ships (OPEN).
## The camera's own per-frame work is off while it is placed by hand, as in
## spectate_shots.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/; no --headless, it needs a window; park it off the screen):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --all-ai --no-pilots --test=structure_shots --shots=<dir>
## It saves struct_01_home_end.png ... struct_06_open.png into <dir> and prints
## "structure_shots: done N pictures".
##
## WHO USES IT: main.gd loads it for --test=structure_shots. It moves the World's
## CameraRig and makes two pilot ships, a turret and a destroyed turret of its own.

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## Where the tour is.
var stage := 0
## Pictures taken so far.
var taken := 0
## The tick at which the current stage began.
var stage_tick := 0
## The ships made for the pictures.
var ships: Array[Ship] = []
## True while a picture is being taken.
var busy := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS


## A pilot ship of `team` standing at `pos`, without a driver.
func _ship(team: int, pos: Vector2) -> Ship:
	var p := PilotProfile.new("Shot%d" % world.profiles.size(), team, 20 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = pos
	s.velocity = Vector2.ZERO
	return s


## Point the camera at `p`, zoomed so `across` world units fit across the window.
func _aim(p: Vector2, across: float) -> void:
	var z := get_viewport().get_visible_rect().size.x / across
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.look_at_point(p)
	world.camera.global_position = p
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)


## Save the picture `name` of what the window shows now.
func _shot(name: String) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	taken += 1
	var path := dir.path_join("struct_%02d_%s.png" % [taken, name])
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	busy = false


## Every frame: move the tour on.
func _process(_dt: float) -> void:
	if world == null or busy or stage >= 7:
		return
	# Frozen: only the explicit "run" steps let the world tick.
	match stage:
		0:
			if world.tick_count < 5:
				return
			world.set_physics_process(false)
			var site := world.defense_posts.site_of(Rules.HALCYON, "top")
			var inh: ResourceNode = null
			for n: ResourceNode in world.nodes:
				if n.node_kind == "inhibitor" and n.side == Rules.HALCYON and n.lane == "top":
					inh = n
			_aim((site.pos + inh.slot_pos[0]) * 0.5 + Vector2(0.0, 150.0), 2600.0)
			await _shot("home_end")
			# Stage B: build the states.
			var js := world.node_by_id("j_top_s")
			world.spawn_turret(Rules.HALCYON, js, 0, "pd", true)
			var bn := world.node_by_id("j_bot_n")
			world.spawn_turret(Rules.HALCYON, bn, 0, "pd", false)
			var bs := world.node_by_id("j_bot_s")
			var dead := world.spawn_turret(Rules.CINDER, bs, 0, "pd", true)
			world.combat.kill(dead, DamageInfo.new())
			var tn := world.node_by_id("j_top_n")
			ships.append(_ship(Rules.HALCYON, tn.global_position + Vector2(300.0, 0.0)))
			ships.append(_ship(Rules.CINDER, tn.global_position + Vector2(-300.0, 0.0)))
			ships.append(_ship(Rules.CINDER, tn.global_position + Vector2(-300.0, 250.0)))
			stage = 1
			stage_tick = world.tick_count
			world.set_physics_process(true)
		1:
			if world.tick_count - stage_tick < 20:
				return
			world.set_physics_process(false)
			var top := (world.node_by_id("j_top_n").global_position + world.node_by_id("j_top_s").global_position) * 0.5
			_aim(top, 5200.0)
			await _shot("top_pair_contested_held")
			var bot := (world.node_by_id("j_bot_n").global_position + world.node_by_id("j_bot_s").global_position) * 0.5
			_aim(bot, 5200.0)
			await _shot("bottom_pair_building_locked")
			# Stage C: the Vhorr ships leave (CLEAR for Aurelian) and the turret at Top Jungle South falls (LOCKED).
			world.combat.kill_silently(ships[1])
			world.combat.kill_silently(ships[2])
			world.combat.kill(world.node_by_id("j_top_s").slots[0] as Turret, DamageInfo.new())
			stage = 2
			stage_tick = world.tick_count
			world.set_physics_process(true)
		2:
			if world.tick_count - stage_tick < 20:
				return
			world.set_physics_process(false)
			_aim((world.node_by_id("j_top_n").global_position + world.node_by_id("j_top_s").global_position) * 0.5, 5200.0)
			await _shot("top_pair_clear_locked")
			world.combat.kill_silently(ships[0])
			stage = 3
			stage_tick = world.tick_count
			world.set_physics_process(true)
		3:
			if world.tick_count - stage_tick < 20:
				return
			world.set_physics_process(false)
			await _shot("top_pair_open")
			print("structure_shots: done %d pictures" % taken)
			stage = 7
			get_tree().quit()
