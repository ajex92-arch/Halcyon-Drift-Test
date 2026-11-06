class_name GalleryScum
extends RefCounted
## WHAT THIS IS: the Scum pictures and the Scum cost bench of the hull gallery
## (tests/hull_gallery.gd). The Scum are the pirate faction that lives in the jungle: the
## Raider and the Carrier (the two kinds of den ship) and the Fighter the Carrier launches.
## Three things:
##   - --scum: the pictures of the three ships, close up, at the usual play zoom next to
##     one pilot ship of each team for scale, and the Raider turned eight ways at the play
##     zoom (to judge how well its heading reads), plus one den as it stands on the map.
##   - --scum-fight: plays a real AI match and photographs the first fight at a den (a
##     jungler against a den ship), wide and near, at the same instant.
##   - --bench --bench-look=scum: the cost of drawing a crowd of Scum ships, far bigger
##     than a real match ever has (BENCH_RAIDERS, BENCH_CARRIERS and BENCH_FIGHTERS in one
##     view), so the cost of the Scum drawing shows up in the frame time.
## The same code runs on any version of the game, so an old and a new version give pictures
## and numbers that can be put side by side.
##
## HOW IT WORKS: the pictures use the frozen gallery world (nothing moves): the ships are
## made the normal way, stood where the picture wants them, and the camera is aimed at
## them. The bench scatters its crowd with a random number maker of its own (seed 11), so
## the match's random numbers are untouched, and measures with GalleryMeasure._measure().
## The fight waits for a den ship that is hurt and fighting a pilot ship, then stops the
## match clock and saves two pictures of that instant.
##
## WHO USES IT: tests/hull_gallery.gd makes one (GalleryScum.new(self)) for the three
## options above. It uses the gallery's world, dir, count, home, units, labels,
## aim_camera(), wait_frames() and _label().

## The width (world units across the screen) of the usual play zoom the Scum designs were
## drawn for.
const PLAY_VIEW := 6000.0
## The width of the near play view.
const MID_VIEW := 2400.0
## The width of the den picture.
const DEN_VIEW := 1100.0
## The width of the near picture of the fight.
const FIGHT_NEAR_VIEW := 1300.0
## The zoom of the close-up of each kind of den ship (screen pixels per world unit), by
## camp type; "snub" is the Fighter.
const CLOSE_ZOOM := {"gunship": 5.0, "carrier": 3.6, "snub": 16.0}
## The crowd of the bench: how many Raiders are in the view.
const BENCH_RAIDERS := 40
## How many Carriers are in the view.
const BENCH_CARRIERS := 20
## How many Fighters are in the view.
const BENCH_FIGHTERS := 120
## Seconds of waiting after the camera moves.
const SETTLE := 0.5
## The match seconds before the fight is looked for, and the most it waits (--secs).
const FIGHT_START := 20.0
## Frames between two looks for a fight.
const FIGHT_CHECK := 20

## The hull gallery test that owns this part.
var gallery: Node


## Remember the gallery that made us.
func _init(g: Node) -> void:
	gallery = g


# --- the pictures ------------------------------------------------------------------------------

## Take the pictures: scum_raider_close, scum_carrier_close, scum_fighter_close, scum_play,
## scum_heading_play, scum_heading_mid and scum_den.
func pictures() -> void:
	_hide_everything()
	var home: Vector2 = gallery.home
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	# The close-ups.
	var raider := _make("gunship", home)
	var carrier := _make("carrier", home)
	var fighter := _make_fighter(carrier, home)
	for pair: Array in [[raider, "gunship", "Scum Raider"], [carrier, "carrier", "Scum Carrier"], [fighter, "snub", "Scum Fighter"]]:
		var u: Unit = pair[0]
		_only(u)
		var z: float = CLOSE_ZOOM[pair[1]]
		gallery.aim_camera(home, z)
		u.global_position = home
		u.rotation = 0.0
		await _snap("scum_%s_close" % str(pair[1]).replace("gunship", "raider"), "%s (zoom %.1f)" % [pair[2], z])
	# The play zoom, next to one pilot ship of each team for scale.
	var z_play: float = size.x / PLAY_VIEW
	gallery.aim_camera(home, z_play)
	var ordered := [gallery.units[0]["ship:fighter"], gallery.units[1]["ship:fighter"], fighter, raider, carrier]
	var xs := [-0.40, -0.30, -0.20, 0.0, 0.22]
	_only_all(ordered)
	for i in ordered.size():
		gallery._put(ordered[i], home + Vector2(float(xs[i]) * PLAY_VIEW, 0.0))
	await _snap("scum_play", "Aurelian Fighter, Vhorr Fighter, Scum Fighter, Scum Raider, Scum Carrier (play zoom)")
	# The Raider turned eight ways, at the play zoom and at a nearer one.
	for pair: Array in [[PLAY_VIEW, "scum_heading_play"], [MID_VIEW, "scum_heading_mid"]]:
		var view: float = pair[0]
		gallery.aim_camera(home, size.x / view)
		_only_all([raider])
		var spots: Array = []
		for i in 8:
			var r := _make("gunship", home) if i > 0 else raider
			r.visible = true
			r.rotation = float(i) * TAU / 8.0
			r.global_position = home + Vector2((float(i % 4) - 1.5) * view * 0.22, (float(i / 4) - 0.5) * view * 0.30)
			spots.append(r)
		await _snap(str(pair[1]), "Scum Raider turned eight ways (%d world units across)" % int(view))
		for i in range(1, 8):
			(spots[i] as Node2D).visible = false
	# One den as it stands on the map: asteroids back on, the camera on the first camp.
	gallery.world.get_node("Asteroids").visible = true
	var camp: Dictionary = gallery.world.map.camps[0]
	var den: Derelict = null
	for u: Unit in gallery.world.units:
		if u is Derelict and (u as Derelict).camp_id == str(camp["id"]):
			den = u
	for u: Unit in gallery.world.units:
		if u is Derelict or u is SnubFighter:
			u.visible = false
	if den != null:
		den.visible = true
		for m: WeaponMount in den.mounts:
			m.angle = m.face + 0.6
	gallery.aim_camera(camp["pos"], size.x / DEN_VIEW)
	await _snap("scum_den", "A Scum den (%d world units across)" % int(DEN_VIEW))
	print("hull_gallery: done %d pictures" % gallery.count)


## Make a den ship of camp type `type_id` at `at`, nose right, its guns turned a little.
func _make(type_id: String, at: Vector2) -> Derelict:
	var d: Derelict = gallery.world.spawn_derelict("gallery_" + type_id, type_id, at)
	d.rotation = 0.0
	var i := 0
	for m: WeaponMount in d.mounts:
		m.angle = m.face + (0.5 if i % 2 == 0 else -0.5)
		i += 1
	return d


## Make a Fighter that belongs to den ship `carrier`, at `at`, nose right.
func _make_fighter(carrier: Derelict, at: Vector2) -> SnubFighter:
	var s: SnubFighter = gallery.world.spawn_snub(carrier)
	s.global_position = at
	s.rotation = 0.0
	return s


## Hide every unit the gallery made and every den ship of the match.
func _hide_everything() -> void:
	gallery._show([])
	for u: Unit in gallery.world.units:
		if u is Derelict or u is SnubFighter:
			u.visible = false


## Show only unit `u` of the units the sheet made (the others stay hidden).
func _only(u: Unit) -> void:
	_only_all([u])


## Show only the units in `list`.
func _only_all(list: Array) -> void:
	_hide_everything()
	for u: Node2D in list:
		u.visible = true


## Save the picture `file` (a frame after the camera is in place), with `title` written
## on it, and take the words off again.
func _snap(file: String, title: String) -> void:
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	gallery._label(title, Vector2(size.x * 0.5, 22.0), 20, Palette.ICE)
	await gallery.wait_frames(int(SETTLE * 60.0))
	await RenderingServer.frame_post_draw
	var path: String = gallery.dir.path_join(file + ".png")
	gallery.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	gallery.count += 1
	for l in gallery.labels.get_children():
		l.queue_free()


# --- the fight -----------------------------------------------------------------------------------

## Play the real match until a den ship that is hurt is fighting a pilot ship, then stop
## the match clock and save scum_fight_play and scum_fight_near of that instant. Gives up
## at --secs of match time (default 600) and says so.
func fight() -> void:
	var world: World = gallery.world
	world.camera.free = true
	var hud := gallery.get_tree().root.find_child("Hud", true, false)
	if hud != null:
		hud.visible = false
	var limit := float(Game.opt("secs", 600.0))
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	while world.time < limit:
		await gallery.wait_frames(FIGHT_CHECK)
		if world.time < FIGHT_START:
			continue
		var den := _hurt_den(world)
		if den == null:
			continue
		world.set_physics_process(false)
		world.camera.set_process(false)
		# The camera sits a third of the way from the den ship to the pilot it is fighting.
		var at := den.global_position
		if den.target != null and is_instance_valid(den.target):
			at = den.global_position.lerp(den.target.global_position, 0.3)
		for pair: Array in [[MID_VIEW, "scum_fight_play"], [FIGHT_NEAR_VIEW, "scum_fight_near"]]:
			gallery.aim_camera(at, size.x / float(pair[0]))
			await gallery.wait_frames(int(SETTLE * 60.0))
			await RenderingServer.frame_post_draw
			var path: String = gallery.dir.path_join(str(pair[1]) + ".png")
			gallery.get_viewport().get_texture().get_image().save_png(path)
			print("shot ", path)
			gallery.count += 1
		print("hull_gallery: scum fight at t=%d, %s" % [int(world.time), den.ctype])
		return
	print("hull_gallery: no fight at a den before t=%d" % int(limit))


## A den ship that is hurt and fighting a pilot ship right now, or null.
func _hurt_den(world: World) -> Derelict:
	for u in world.units:
		if is_instance_valid(u) and u is Derelict:
			var d := u as Derelict
			if d.alive and d.hull < d.hull_max * 0.9 and d.is_engaged() and d.target.kind == Unit.K_SHIP:
				return d
	return null


# --- the bench -----------------------------------------------------------------------------------

## The cost bench (--bench --bench-look=scum): a crowd of den ships and Fighters in one view
## of `view` world units (or --bench-view=N), measured --bench-rounds times (default 4).
## Prints one "bench scum" line, in the format of the plain bench's lines: the average over
## the rounds of the frame mean, the 95th percentile, the game work and the script and render
## split in milliseconds, the draw calls of the last frame, and the median of all the frames.
func bench(view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	_hide_everything()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var crowd: Array = []
	var carriers: Array = []
	for i in BENCH_RAIDERS:
		crowd.append(_make("gunship", _spot(rng, size, z)))
	for i in BENCH_CARRIERS:
		var c := _make("carrier", _spot(rng, size, z))
		carriers.append(c)
		crowd.append(c)
	for i in BENCH_FIGHTERS:
		var f := _make_fighter(carriers[i % carriers.size()], _spot(rng, size, z))
		f.rotation = rng.randf() * TAU
		crowd.append(f)
	for u: Unit in crowd:
		u.visible = true
		if u is Derelict:
			u.rotation = rng.randf() * TAU
	await gallery.wait_frames(30)
	var measure := GalleryMeasure.new(gallery)
	var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var pooled: Array = []
	var rounds := int(Game.opt("bench-rounds", GalleryMeasure.BENCH_ROUNDS))
	for _r in rounds:
		var res: Array = await measure._measure()
		for i in 6:
			sums[i] += float(res[i])
		pooled.append_array(measure.last_times)
	var n := float(rounds)
	pooled.sort()
	var median := float(pooled[int(pooled.size() * 0.5)]) if not pooled.is_empty() else 0.0
	print("bench scum: %d raiders, %d carriers, %d fighters in a view %d units wide" % [BENCH_RAIDERS, BENCH_CARRIERS, BENCH_FIGHTERS, int(view)])
	print("bench %-14s: frame mean %.2f ms, p95 %.2f ms, game work (process) %.2f ms, draw calls %d, median %.2f ms, script %.2f ms, render %.2f ms" % ["scum", sums[0] / n, sums[1] / n, sums[2] / n, int(sums[3] / n), median, sums[4] / n, sums[5] / n])


## A random spot of the view (screen size `size`, zoom `z`), in world units.
func _spot(rng: RandomNumberGenerator, size: Vector2, z: float) -> Vector2:
	var spot := Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.08, 0.92) * size.y)
	return gallery.home + (spot - size * 0.5) / z
