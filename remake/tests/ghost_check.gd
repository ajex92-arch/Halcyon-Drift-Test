extends Node
## WHAT THIS IS: the check that an enemy mothership the viewer's team has seen once, and cannot see now, stays drawn where it
## was last seen (DESIGN: "Enemy structures, once seen, stay drawn as last-known ghosts") and does not follow the ship, which
## would show where it really goes.
##
## HOW IT WORKS: it waits for the match, then stands a scout of the viewer's team beside the enemy mothership until the team
## sees it, and notes where the mothership's picture (its "Visual" node, UnitVisual) is: on the ship. It takes the scout away
## (the team no longer sees the ship but has seen it), moves the enemy mothership 1,500 units, and checks that the picture
## stayed at the place of the last sight and now says it is a ghost (UnitVisual.is_ghost), then moves the ship again and
## checks the picture has not followed. With the scout back beside the ship the picture follows it again. It prints PASS or
## FAIL lines that start with "ghost_check" and "ghost_check: N failures (M checks)", then quits. Only the drawing is looked
## at: nothing it moves is read by the match afterwards. Windowed with --shots=<folder> it saves three pictures (the ship in
## sight, just after it moved unseen, and after it moved again), each a wide view over both the old and the new place.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --no-pilots --no-jungle --no-admiral-ai --seed=7 --test=ghost_check
## Pictures need a window (PITFALLS: windowed runs):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=admiral --bot=input --force-hud --no-pilots --no-jungle --no-admiral-ai --seed=7 --test=ghost_check --shots=<dir>
##
## WHO USES IT: main.gd loads it for --test=ghost_check; run_checks has a row for it.

## How far the enemy mothership is moved each time (world units).
const MOVE := 1500.0

## The running match (set by setup()).
var world: World
## True once the check has started (it runs once).
var started := false
## How many checks failed and how many were made.
var failures := 0
var checks := 0
## The folder the pictures go into (--shots), or "" for none.
var dir := ""
## Pictures saved so far.
var taken := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.opt("shots") != null and DisplayServer.get_name() != "headless":
		dir = str(Game.opt("shots"))
		DirAccess.make_dir_recursive_absolute(dir)


## Quit after 120 s of real time; start once the match is on.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 120000:
		print("ghost_check: timeout")
		get_tree().quit()
		return
	if started or world.phase != "play" or world.tick_count < 30:
		return
	started = true
	_run()


## Count one check and print its line.
func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s ghost_check: %s" % ["PASS" if ok else "FAIL", what])


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait until the match has run `n` more ticks (the fog is looked at again every 12 of them).
func _ticks(n: int) -> void:
	var until := world.tick_count + n
	while world.tick_count < until:
		await get_tree().process_frame


## The whole check, then the summary line and quit.
func _run() -> void:
	world.minion_director.next_wave = INF
	var vt := world.viewer_team
	if vt < 0 or FogOff.is_on():
		_check(false, "setup: a viewer with the fog on")
		_finish()
		return
	var ms := world.mothership(Rules.enemy_of(vt))
	var visual := ms.get_node("Visual") as UnitVisual
	var bit := 1 << vt
	# A scout of the viewer's team without a driver, so it stays where it is put.
	var made: Dictionary = (world.teams[vt] as TeamState).production.spawn_now("scout", 1)
	var scout: Ship = null
	if not made.is_empty():
		var rec: Squad = world.squads.get(int(made["squad"])) as Squad
		if rec != null and not rec.member_uids.is_empty():
			scout = world.by_uid.get(int(rec.member_uids[0])) as Ship
	if scout == null:
		_check(false, "setup: a scout to look with")
		_finish()
		return
	scout.controller = null
	var own := world.mothership(vt).global_position
	# 1. The scout stands beside the enemy mothership: the team sees it and the picture is on it.
	_stand(scout, ms)
	await _ticks(30)
	_check(ms.visible_to(vt) and (ms.seen_mask & bit) != 0, "in sight: the team sees the enemy mothership")
	_check(visual.global_position.distance_to(ms.global_position) < 1.0, "in sight: the picture is on the ship")
	var seen_at := ms.global_position
	await _shot("1_in_sight", seen_at, seen_at + Vector2(0.0, MOVE))
	# 2. The scout leaves, the ship moves: the picture stays where it was last seen.
	scout.global_position = own + Vector2(0.0, 900.0)
	await _ticks(30)
	_check(not ms.visible_to(vt) and (ms.seen_mask & bit) != 0, "out of sight: seen once, not seen now")
	ms.global_position = seen_at + Vector2(0.0, MOVE)
	await _frames(6)
	_check(visual.global_position.distance_to(seen_at) < 1.0, "moved unseen: the picture stays at the last seen place (%.0f from it)" % visual.global_position.distance_to(seen_at))
	_check(ms.global_position.distance_to(seen_at) > MOVE - 1.0, "moved unseen: the ship itself is %.0f away from that place" % ms.global_position.distance_to(seen_at))
	_check(visual.has_method("is_ghost") and bool(visual.call("is_ghost")), "moved unseen: the picture is a ghost")
	await _shot("2_moved_unseen", seen_at, ms.global_position)
	ms.global_position = seen_at + Vector2(MOVE, MOVE)
	await _ticks(60)
	_check(visual.global_position.distance_to(seen_at) < 1.0, "moved again: the picture is still at the last seen place (%.0f from it)" % visual.global_position.distance_to(seen_at))
	await _shot("3_moved_again", seen_at, ms.global_position)
	# 3. The scout comes back beside the ship: the picture follows it again.
	_stand(scout, ms)
	await _ticks(30)
	_check(ms.visible_to(vt), "back in sight: the team sees the enemy mothership again")
	_check(visual.global_position.distance_to(ms.global_position) < 1.0 and not (visual.has_method("is_ghost") and bool(visual.call("is_ghost"))), "back in sight: the picture is on the ship again and no ghost")
	_finish()


## Stand `scout` beside the hull of mothership `ms` (700 units off its side).
func _stand(scout: Ship, ms: Mothership) -> void:
	scout.global_position = ms.global_position + Vector2.from_angle(ms.rotation + PI * 0.5) * (ms.beam * 0.5 + 700.0)
	scout.velocity = Vector2.ZERO


## The summary line and quit.
func _finish() -> void:
	print("ghost_check: %d failures (%d checks)" % [failures, checks])
	get_tree().quit()


## With --shots: a wide picture of what the window shows with the camera over the middle of `a` and `b`.
func _shot(name: String, a: Vector2, b: Vector2) -> void:
	if dir == "":
		return
	world.camera.free = true
	world.camera.set_process(false)
	var mid := (a + b) * 0.5
	var z := get_viewport().get_visible_rect().size.x / (a.distance_to(b) + 3600.0)
	world.camera.look_at_point(mid)
	world.camera.global_position = mid
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	await _frames(3)
	await RenderingServer.frame_post_draw
	taken += 1
	var path := dir.path_join("ghost_%02d_%s.png" % [taken, name])
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
