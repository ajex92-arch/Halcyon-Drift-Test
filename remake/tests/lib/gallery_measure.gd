class_name GalleryMeasure
extends RefCounted
## WHAT THIS IS: the frame-time measurements of the hull gallery
## (tests/hull_gallery.gd): what the Cinder alien drawing costs per frame,
## compared with the plain outlines, and what each part of the per-unit
## drawing costs. Three ways: bench() with a frozen crowd of ships,
## bench_parts() with the same crowd and the parts switches of DrawParts, and
## live() inside a real match.
##
## HOW IT WORKS: all flip CinderPaint.set_alien() between the alien look and
## the plain outlines (the old look) while the game runs, and
## record how long each frame takes (Time.get_ticks_usec() between frames)
## and how long Godot's "process" step takes (Performance.TIME_PROCESS, which
## includes every _process and _draw call of the ships and units; Godot only
## refreshes it once a second, with the slowest frame of that second, so it is
## a rough hint and not an average). bench() and the parts bench also split each
## frame at the start of its drawing (the RenderingServer's frame_pre_draw
## signal) into the game's own work (script ms) and Godot's drawing (render ms).
## The looks are interleaved, so a slow patch of the computer hits all of them alike.
##   - bench(): spreads 70 ships and 70 minions per team over a play-zoom view,
##     freezes nothing but moves nothing (the gallery stopped the match), and
##     measures three looks: only the Aurelian half drawn, both teams drawn
##     with Cinder alien, both teams with Cinder plain. What differs between
##     the looks is the cost of drawing. It prints the frame mean, the 95th
##     percentile, the median, the draw calls and the script and render split.
##   - bench_parts() (the draw-cost table): the same crowd and
##     looks, but each look is measured once per SWITCH SET of DrawParts: all
##     parts on, each part off alone, all parts off. What differs between the
##     sets is what that part costs. It prints one DRAWCOST line per
##     measurement (read by tools/draw_cost_table.py, which makes the table) and
##     a readable summary at the end. The reference crowd stands still: its
##     ships do not drift (no arrow), burn no engine (no flames) and are
##     unhurt, and at play zoom no name is drawn, so those parts would cost
##     nothing there. --bench-busy therefore makes the crowd drift, burn and
##     take damage (like a fight), and --bench-view=2200 shows the names.
##   - live(): plays a real match with the camera on the busiest fight at play
##     zoom (like spectate_shots, but the camera is held where it is put) and
##     switches the look every 5 seconds of match time, so both looks are
##     measured in the same match.
## The options (all text numbers; the defaults are the reference bench):
## --bench-view=N (world units across, default the gallery's play view 4500),
## --bench-rounds=N (default 4; 3 for the parts bench), --bench-frames=N
## (default 240 per measurement), --bench-busy and, for the parts bench,
## --bench-parts (read by the hull gallery, which chooses bench_parts()).
##
## WHO USES IT: tests/hull_gallery.gd makes one (GalleryMeasure.new(self)) for
## --bench and --live. It uses the gallery's world, home, units, make_ship(),
## aim_camera() and wait_frames(), and DrawParts for the switch sets.

## The three looks the bench compares, in the order it measures them.
const LOOKS := ["aurelian only", "cinder alien", "cinder plain"]
## The three looks of the steel measurements (--bench-look=steel and
## --live-look=steel), in the order they are measured: Aurelian's steel hulls with
## the turrets of both teams (the game as it is), the steel hulls without turrets,
## and the plain old outlines without turrets.
const STEEL_LOOKS := ["steel+turrets", "steel", "plain"]
## The two looks of the stream measurement (--live-look=streams), in the order they are
## measured: the big hulls with a stream from each nozzle (the game as it is) and the one
## stream every ship had before.
const STREAM_LOOKS := ["streams", "one stream"]
## The two looks of the gun-kick measurements (--live-look=kick and --bench-look=kick), in the
## order they are measured: guns that kick back when they fire (the game as it is) and guns that
## sit still.
const KICK_LOOKS := ["kick", "no kick"]
## How many times the bench goes round the three looks.
const BENCH_ROUNDS := 4
## How many times the parts bench goes round its looks and switch sets (the
## official table uses 3 interleaved rounds).
const PARTS_ROUNDS := 3
## How many frames each bench measurement takes.
const BENCH_FRAMES := 240
## How many seconds of match time live() leaves out at the start, so the
## first minute's small crowd does not count.
const LIVE_SKIP := 60.0
## The look switches every this many frames in live() (300 = 5 s at 60 frames
## per second).
const LIVE_STRETCH := 300

## The hull gallery test that owns this part.
var gallery: Node
## How many frames each measurement takes (BENCH_FRAMES, or --bench-frames=N).
var frames := BENCH_FRAMES
## The pilot ships whose guns the gun-kick bench makes fire on every frame (empty otherwise).
var _firing: Array = []
## Which way the gun-kick bench's cooldowns went on the last frame.
var _flip := false
## The frame times (ms, sorted) of the latest _measure(), so bench() can take the
## median over all its rounds.
var last_times: Array = []


## Remember the gallery that made us, and read --bench-frames.
func _init(g: Node) -> void:
	gallery = g
	frames = maxi(10, int(Game.opt("bench-frames", BENCH_FRAMES)))


# --- bench ------------------------------------------------------------------------------------------

## Make the bench's crowd: 70 ships and 70 minions per team at fixed random
## spots over a view `z` zoom on a screen `size` pixels big (a generator of its
## own, so the match's random numbers are untouched), and hide the gallery's own
## one-of-each units. Returns every unit of the crowd.
func _make_crowd(size: Vector2, z: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var crowd: Array = []
	for t in 2:
		for i in 70:
			var s: Ship = gallery.make_ship(t, Ships.ORDER[_pick_hull(rng)])
			s.thrust_main = 0.0
			crowd.append(s)
			_scatter(s, rng, size, z)
		for i in 70:
			var m: Minion = gallery.world.spawn_minion(t, Minions.TYPES.keys()[rng.randi() % 3], "mid", gallery.home)
			crowd.append(m)
			_scatter(m, rng, size, z)
	# The gallery's own one-of-each units stay out of the picture.
	for key: String in gallery.units[0]:
		gallery.units[0][key].visible = false
		gallery.units[1][key].visible = false
	return crowd


## Run the bench at a view `view` world units wide (or --bench-view=N) and
## print, for each look, the average and the 95th percentile of the frame time,
## the average process time, and the draw calls of the last frame, then the
## median of all the frames of all the rounds and the average script and render
## split (see _measure(); both are 0 in a headless run, which has no renderer).
func bench(view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	# Step 1: the crowd.
	var crowd := _make_crowd(size, z)
	await gallery.wait_frames(30)
	# Step 2: go round the looks several times; keep every measurement and every frame time.
	var results := {}
	var pooled := {}
	for look: String in LOOKS:
		results[look] = []
		pooled[look] = []
	for _r in int(Game.opt("bench-rounds", BENCH_ROUNDS)):
		for look: String in LOOKS:
			for u: Unit in crowd:
				u.visible = look != "aurelian only" or u.team == 0
			CinderPaint.set_alien(look != "cinder plain")
			results[look].append(await _measure())
			pooled[look].append_array(last_times)
	CinderPaint.set_alien(true)
	# Step 3: print the average over the rounds, and the median of all the frames.
	for look: String in LOOKS:
		var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for r: Array in results[look]:
			for i in 6:
				sums[i] += float(r[i])
		var n := float(results[look].size())
		var all_times: Array = pooled[look]
		all_times.sort()
		var median := float(all_times[int(all_times.size() * 0.5)]) if not all_times.is_empty() else 0.0
		print("bench %-14s: frame mean %.2f ms, p95 %.2f ms, game work (process) %.2f ms, draw calls %d, median %.2f ms, script %.2f ms, render %.2f ms" % [look, sums[0] / n, sums[1] / n, sums[2] / n, int(sums[3] / n), median, sums[4] / n, sums[5] / n])


## The steel bench (--bench-look=steel): the same crowd as bench(), measured for
## the three ways of drawing the pilot ships' look (see STEEL_LOOKS): Aurelian's
## steel hulls with the turrets of both teams, the steel hulls alone, and the plain
## old outlines without turrets. Both teams are drawn in every look (Cinder's alien
## look stays on), so what differs is the steel hulls and the turrets.
func bench_steel(view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	var crowd := _make_crowd(size, z)
	await gallery.wait_frames(30)
	var results := {}
	for look: String in STEEL_LOOKS:
		results[look] = []
	for _r in int(Game.opt("bench-rounds", BENCH_ROUNDS)):
		for look: String in STEEL_LOOKS:
			for u: Unit in crowd:
				u.visible = true
			set_steel_look(look)
			results[look].append(await _measure())
	set_steel_look(STEEL_LOOKS[0])
	for look: String in STEEL_LOOKS:
		var sums := [0.0, 0.0, 0.0, 0.0]
		for r: Array in results[look]:
			for i in 4:
				sums[i] += float(r[i])
		var n := float(results[look].size())
		print("bench %-14s: frame mean %.2f ms, p95 %.2f ms, game work (process) %.2f ms, draw calls %d" % [look, sums[0] / n, sums[1] / n, sums[2] / n, int(sums[3] / n)])


## The gun-kick bench (--bench-look=kick): the same crowd as bench(), with every gun of every
## pilot ship made to fire again on every frame (the cooldown goes up and down, so each frame
## the painters see a new shot: all guns at the full kick, and the muzzles bright, all the
## time, the worst case), measured with the kick on and with the kick off (GunKick.set_on()),
## interleaved in rounds. What differs is the cost of the kick at its worst. The crowd keeps
## its spots, the match is frozen, and nothing in the match changes.
func bench_kick(view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	var crowd := _make_crowd(size, z)
	for u: Unit in crowd:
		if u is Ship:
			_firing.append(u)
	await gallery.wait_frames(30)
	var results := {}
	for look: String in KICK_LOOKS:
		results[look] = []
	for _r in int(Game.opt("bench-rounds", BENCH_ROUNDS)):
		for look: String in KICK_LOOKS:
			for u: Unit in crowd:
				u.visible = true
			GunKick.set_on(look == "kick")
			results[look].append(await _measure())
	GunKick.set_on(true)
	var guns := 0
	for s: Ship in _firing:
		guns += s.mounts.size()
	print("bench kick: %d pilot ships, %d guns, every gun fires on every frame" % [_firing.size(), guns])
	_firing.clear()
	for look: String in KICK_LOOKS:
		var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for r: Array in results[look]:
			for i in 6:
				sums[i] += float(r[i])
		var n := float(results[look].size())
		print("bench %-14s: frame mean %.2f ms, p95 %.2f ms, game work (process) %.2f ms, draw calls %d, script %.2f ms, render %.2f ms" % [look, sums[0] / n, sums[1] / n, sums[2] / n, int(sums[3] / n), sums[4] / n, sums[5] / n])


## Make every gun of the bench's pilot ships fire again: the cooldown goes up on one frame
## and down on the next, the way a gun that fires and recovers does.
func _fire_all() -> void:
	_flip = not _flip
	for s: Ship in _firing:
		for m: WeaponMount in s.mounts:
			m.cd = 0.5 if _flip else 0.0


## The stream bench (--bench-look=streams): the same busy crowd as bench() with
## --bench-busy (the ships burn their engines; about one ship in five is a big hull, far
## more than a real fight has), measured for the two looks of STREAM_LOOKS, interleaved:
## the big hulls with a stream from each nozzle, and the one stream every ship had. What
## differs is the cost of the streams (the per-frame hop and the extra dots).
func bench_streams(view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	var crowd := _make_crowd(size, z)
	_make_busy(crowd)
	var big := 0
	for u: Unit in crowd:
		if u is Ship and EngineStreams.HULLS.has((u as Ship).hull_id):
			big += 1
	print("bench streams: %d ships of the crowd are big hulls" % big)
	await gallery.wait_frames(30)
	var results := {}
	for look: String in STREAM_LOOKS:
		results[look] = []
	for _r in int(Game.opt("bench-rounds", BENCH_ROUNDS)):
		for look: String in STREAM_LOOKS:
			EngineStreams.set_on(look == "streams")
			# Let the flames settle after the switch (every big hull changes its dot count).
			await gallery.wait_frames(40)
			results[look].append(await _measure())
	EngineStreams.set_on(true)
	for look: String in STREAM_LOOKS:
		var sums := [0.0, 0.0, 0.0, 0.0]
		for r: Array in results[look]:
			for i in 4:
				sums[i] += float(r[i])
		var n := float(results[look].size())
		print("bench %-10s: frame mean %.2f ms, p95 %.2f ms, game work (process) %.2f ms, draw calls %d" % [look, sums[0] / n, sums[1] / n, sums[2] / n, int(sums[3] / n)])


## Switch to the steel look `look` of STEEL_LOOKS: the steel hulls and the
## turrets each on or off.
func set_steel_look(look: String) -> void:
	AurelianPaint.set_on(look != "plain")
	TurretPaint.set_on(look == "steel+turrets")


## A hull number for the bench: mostly strike craft, some corvettes, a few
## frigates and capital ships, like a big fight.
func _pick_hull(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.55:
		return rng.randi() % 4
	if r < 0.8:
		return 4 + rng.randi() % 2
	if r < 0.93:
		return 6 + rng.randi() % 2
	return 8 + rng.randi() % 2


## Put unit `u` at a random spot of the view, facing a random way.
func _scatter(u: Unit, rng: RandomNumberGenerator, size: Vector2, z: float) -> void:
	var spot := Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.08, 0.92) * size.y)
	u.global_position = gallery.home + (spot - size * 0.5) / z
	u.rotation = rng.randf() * TAU
	u.velocity = Vector2.ZERO


## When the drawing of the latest frame began, in microseconds
## (Time.get_ticks_usec()); written by _on_pre_draw() while _measure() runs.
var _pre_draw_usec := 0
## When the drawing of the latest frame ended, in microseconds; written by
## _on_post_draw() while _measure() runs.
var _post_draw_usec := 0


## RenderingServer.frame_pre_draw: the game's own work of this frame (all
## _process and _draw calls) is done, Godot starts drawing.
func _on_pre_draw() -> void:
	_pre_draw_usec = Time.get_ticks_usec()


## RenderingServer.frame_post_draw: Godot has drawn the frame.
func _on_post_draw() -> void:
	_post_draw_usec = Time.get_ticks_usec()


## Measure `frames` frames (after at least 20 frames and half a second to
## settle, so the flames, which live 0.35 s, are full again): returns [mean
## frame time ms, 95th percentile ms, "process" ms, draw calls of the last
## frame, mean script ms, mean render ms]. "process" is Godot's own
## Performance.TIME_PROCESS monitor, which it refreshes once a second with the
## SLOWEST frame of that second, so it is not an average: read it as a rough
## hint and use the next two. Script ms is the time from the start of a frame to
## the start of its drawing: every _process and _draw call of the game (this is
## where the ships' own drawing code runs). Render ms is the drawing itself
## (Godot turning the drawing commands into graphics calls and sending them).
## With `redraw_off` the every-frame redraw (DrawParts.redraw) is switched off
## AFTER the settling frames, so every picture is drawn once with the switches
## of this measurement and then kept; it is switched on again at the end.
func _measure(redraw_off := false) -> Array:
	var settle_from := Time.get_ticks_msec()
	await gallery.wait_frames(20)
	while Time.get_ticks_msec() - settle_from < 500:
		await gallery.get_tree().process_frame
	if redraw_off:
		DrawParts.redraw = false
		await gallery.wait_frames(2)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	var times: Array = []
	var process_ms := 0.0
	var script_us := 0.0
	var render_us := 0.0
	var split_n := 0
	var last := Time.get_ticks_usec()
	for _i in frames:
		# The gun-kick bench: every gun fires again before each frame.
		if not _firing.is_empty():
			_fire_all()
		await gallery.get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		# The frame that just ended began at `last`: split it where its drawing began.
		if _pre_draw_usec > last and _post_draw_usec >= _pre_draw_usec:
			script_us += float(_pre_draw_usec - last)
			render_us += float(_post_draw_usec - _pre_draw_usec)
			split_n += 1
		last = now
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	times.sort()
	last_times = times
	var total := 0.0
	for ms: float in times:
		total += ms
	var splits := float(maxi(1, split_n)) * 1000.0
	var result := [total / times.size(), times[int(times.size() * 0.95)], process_ms / frames, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), script_us / splits, render_us / splits]
	DrawParts.redraw = true
	return result


# --- parts bench -------------------------------------------------------------------------------------

## The parts bench: the crowd of bench(), measured for each look
## once per switch set of DrawParts, round after round. The sets are "none" (all
## parts on), each of DrawParts.PARTS off alone, "drawing" (the six drawn parts
## off, the every-frame redraw of the hull fills stays), "all" (every part off) and
## "empty" (every unit hidden, their _process work still running: what the rest of
## the scene costs by itself). A
## warm-up pass (round 0: each look once, all parts on) comes first and is
## printed too, but the table maker skips it. Every measurement prints one line:
##   DRAWCOST scenario=<still|busy> view=<world units> round=<n> look=<look>
##     off=<set> units=<n> frame_ms=<mean> p95_ms=<95th percentile>
##     script_ms=<game's own work> render_ms=<drawing> process_ms=<Godot's
##     slowest-frame monitor> draw_calls=<n>
## (script_ms + render_ms is the part of the frame the game and Godot's renderer
## work on the processor; the rest of the frame is waiting, mostly for the
## graphics card.)
## and at the end a readable summary per look and set (the average over the
## rounds). The order of the sets is reversed in every second round, so a
## slowly warming or cooling computer favours no set. See _make_busy() for the
## busy scenario. `view` is the width of the view in world units (or
## --bench-view=N); --bench-rounds=N sets the rounds (default PARTS_ROUNDS).
func bench_parts(view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	# Step 1: the crowd, and the busy version of it when asked for.
	var crowd := _make_crowd(size, z)
	var busy_text := str(Game.opt("bench-busy", "false"))
	var busy := busy_text != "false" and busy_text != "0"
	if busy:
		_make_busy(crowd)
	var scenario := "busy" if busy else "still"
	await gallery.wait_frames(30)
	# Step 2: the switch sets: all on, each part off alone, the six drawing parts
	# off together (only the redraw of the hull fills stays), all off, and the
	# empty scene (every unit hidden, so only the rest of the scene is drawn).
	var sets: Array = ["none"]
	sets.append_array(DrawParts.PARTS)
	sets.append("drawing")
	sets.append("all")
	sets.append("empty")
	var rounds := maxi(1, int(Game.opt("bench-rounds", PARTS_ROUNDS)))
	print("bench-parts: scenario=%s view=%d size=%dx%d rounds=%d frames=%d sets=%d looks=%d" % [scenario, int(view), int(size.x), int(size.y), rounds, frames, sets.size(), LOOKS.size()])
	# Step 3: the warm-up (round 0), then the rounds; keep every measurement of rounds 1 and up.
	var results := {}
	for r in rounds + 1:
		for look: String in LOOKS:
			var order: Array = sets.duplicate()
			if r == 0:
				order = ["none"]
			elif r % 2 == 0:
				order.reverse()
			for off: String in order:
				var m: Array = await _measure_set(look, off, crowd)
				print("DRAWCOST scenario=%s view=%d round=%d look=%s off=%s units=%d frame_ms=%.3f p95_ms=%.3f script_ms=%.3f render_ms=%.3f process_ms=%.3f draw_calls=%d" % [scenario, int(view), r, look.replace(" ", "_"), off, int(m[6]), m[0], m[1], m[4], m[5], m[2], int(m[3])])
				if r > 0:
					var key := look + "|" + off
					if not results.has(key):
						results[key] = []
					results[key].append(m)
	CinderPaint.set_alien(true)
	DrawParts.set_off("none")
	# Step 4: print the average over the rounds, per look and set.
	for look: String in LOOKS:
		for off: String in sets:
			var list: Array = results.get(look + "|" + off, [])
			if list.is_empty():
				continue
			var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			for m: Array in list:
				for i in 6:
					sums[i] += float(m[i])
			var n := float(list.size())
			print("bench-parts %-14s off=%-8s: frame mean %.2f ms, p95 %.2f ms, script %.2f ms, render %.2f ms, process (slowest frame of the second) %.2f ms, draw calls %d" % [look, off, sums[0] / n, sums[1] / n, sums[4] / n, sums[5] / n, sums[2] / n, int(sums[3] / n)])
	print("bench-parts: done %s" % scenario)


## One measurement of the parts bench: show the units of `look` (only the
## Aurelian half for "aurelian only"), switch to that look, apply the switch set
## `off` of DrawParts ("none", one part, "drawing" or "all"), or hide every unit
## ("empty": every unit hidden and the redraw off, so only their _process work is left), and measure. Returns what
## _measure() returns plus the number of units drawn as a seventh entry.
func _measure_set(look: String, off: String, crowd: Array) -> Array:
	var shown := 0
	var empty := off == "empty"
	for u: Unit in crowd:
		u.visible = (look != "aurelian only" or u.team == 0) and not empty
		if u.visible:
			shown += 1
	CinderPaint.set_alien(look != "cinder plain")
	# The empty scene keeps every part on but the redraw: hidden units then ask for no new picture.
	DrawParts.set_off("redraw" if empty else off)
	# The every-frame redraw is switched off only after the settling frames
	# (see _measure()), so keep it on for now.
	var redraw_off := not DrawParts.redraw
	DrawParts.redraw = true
	var m: Array = await _measure(redraw_off)
	DrawParts.set_off("none")
	m.append(shown)
	return m


## Make the crowd busy, like a fight, for the parts bench's busy scenario: every
## ship drifts at 60% of its top speed with its nose up to half a radian off
## the drift (a ship only draws the drift arrow and its slip tick when the human
## flies it, so this crowd of AI ships draws none), burns its main
## engine at 0.7, and a quarter of the ships each fire a side thruster at 0.5
## (the flames); every minion has lost 30% of its hull (so its bar is drawn).
## The positions stay the same as in the reference bench. The match is frozen,
## so nobody really moves. A generator of its own keeps the match's random
## numbers untouched.
func _make_busy(crowd: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for u: Unit in crowd:
		if u is Ship:
			var s := u as Ship
			s.velocity = Vector2.from_angle(s.rotation + rng.randf_range(-0.5, 0.5)) * 0.6 * maxf(80.0, s.f_max)
			s.thrust_main = 0.7
			var side := rng.randf()
			s.thrust_port = 0.5 if side < 0.25 else 0.0
			s.thrust_star = 0.5 if side >= 0.75 else 0.0
		elif u is Minion:
			u.hull = u.hull_max * 0.7


# --- live match ------------------------------------------------------------------------------------

## Play the real match until --secs of match time (default 480), the camera on
## the busiest fight at a view `view` world units wide, and print for each look
## the number of frames, the average frame time, the average process time and
## the average number of units near the camera (so the numbers can be read
## against how busy the picture was).
## The camera is put by hand: left to itself, the free camera pans toward a
## corner of the map when the game window is not the one with the mouse over
## it (as with a window parked off screen), and would look at nothing.
func live(view: float) -> void:
	var secs := float(Game.opt("secs", 480.0))
	var world: World = gallery.world
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	# Per look: [frame ms, process ms, frames, units near the camera, of them Cinder's, samples].
	var sums := {true: [0.0, 0.0, 0, 0, 0, 0], false: [0.0, 0.0, 0, 0, 0, 0]}
	var alien := true
	var stretch := 0
	var last := Time.get_ticks_usec()
	var scratch: Array = []
	while world.time < secs:
		await gallery.get_tree().process_frame
		var now := Time.get_ticks_usec()
		stretch += 1
		if stretch % 120 == 1:
			world.camera.global_position = _busiest(world)
		if world.time > LIVE_SKIP:
			var s: Array = sums[alien]
			s[0] += float(now - last) / 1000.0
			s[1] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			s[2] += 1
			if stretch % 30 == 0:
				# Everything within the screen's half-diagonal of the camera.
				for obj in world.unit_hash.query(world.camera.global_position, view * 0.58, scratch):
					# A unit freed this frame can still be in the grid.
					if is_instance_valid(obj) and (obj as Unit).alive:
						s[3] += 1
						s[4] += 1 if (obj as Unit).team == Rules.CINDER else 0
				s[5] += 1
		last = now
		if stretch >= LIVE_STRETCH:
			stretch = 0
			alien = not alien
			CinderPaint.set_alien(alien)
	for look: bool in [true, false]:
		var s: Array = sums[look]
		var frames := maxf(1.0, s[2])
		var samples := maxf(1.0, s[5])
		print("live %-12s: %d frames, frame mean %.2f ms, game work (process) %.2f ms, %.0f units near the camera (%.0f Cinder's)" % ["cinder alien" if look else "cinder plain", s[2], s[0] / frames, s[1] / frames, s[3] / samples, s[4] / samples])


## The steel look inside a real match (--live-look=steel): like live(), but the
## look rotates through the three of STEEL_LOOKS every 5 seconds of match time
## (Cinder's alien look stays on), so the cost of the steel hulls and of the
## turrets is measured in the same match, in the same fights.
func live_steel(view: float) -> void:
	var secs := float(Game.opt("secs", 480.0))
	var world: World = gallery.world
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	# Per look: [frame ms, process ms, frames, units near the camera, samples].
	var sums := {}
	for look: String in STEEL_LOOKS:
		sums[look] = [0.0, 0.0, 0, 0, 0]
	var which := 0
	set_steel_look(STEEL_LOOKS[which])
	var stretch := 0
	var last := Time.get_ticks_usec()
	var scratch: Array = []
	while world.time < secs:
		await gallery.get_tree().process_frame
		var now := Time.get_ticks_usec()
		stretch += 1
		if stretch % 120 == 1:
			world.camera.global_position = _busiest(world)
		if world.time > LIVE_SKIP:
			var s: Array = sums[STEEL_LOOKS[which]]
			s[0] += float(now - last) / 1000.0
			s[1] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			s[2] += 1
			if stretch % 30 == 0:
				for obj in world.unit_hash.query(world.camera.global_position, view * 0.58, scratch):
					if is_instance_valid(obj) and (obj as Unit).alive:
						s[3] += 1
				s[4] += 1
		last = now
		if stretch >= LIVE_STRETCH:
			stretch = 0
			which = (which + 1) % STEEL_LOOKS.size()
			set_steel_look(STEEL_LOOKS[which])
	set_steel_look(STEEL_LOOKS[0])
	for look: String in STEEL_LOOKS:
		var s: Array = sums[look]
		var frames := maxf(1.0, s[2])
		var samples := maxf(1.0, s[4])
		print("live %-14s: %d frames, frame mean %.2f ms, game work (process) %.2f ms, %.0f units near the camera" % [look, s[2], s[0] / frames, s[1] / frames, s[3] / samples])


## The engine streams inside a real match (--live-look=streams): like live_steel(), but
## the big hulls' flames switch between a stream from each nozzle and the one stream every
## ship had (EngineStreams.set_on()) every 5 seconds of match time, so what the streams
## cost is measured in the same match, in the same fights. With --late the match starts at
## 25:00, fully teched, with capital ships (give --secs as the match time to stop at).
func live_streams(view: float) -> void:
	var secs := float(Game.opt("secs", 480.0))
	var world: World = gallery.world
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	# Per look: [frame ms, process ms, frames, units near the camera, big hulls near the camera, samples].
	var sums := {}
	for look: String in STREAM_LOOKS:
		sums[look] = [0.0, 0.0, 0, 0, 0, 0]
	var which := 0
	EngineStreams.set_on(true)
	# The match time to leave out the first minute from (a late match starts at 25:00).
	var start := world.time
	var stretch := 0
	var last := Time.get_ticks_usec()
	var scratch: Array = []
	while world.time < secs:
		await gallery.get_tree().process_frame
		var now := Time.get_ticks_usec()
		stretch += 1
		if stretch % 120 == 1:
			world.camera.global_position = _busiest(world)
		if world.time > start + LIVE_SKIP:
			var s: Array = sums[STREAM_LOOKS[which]]
			s[0] += float(now - last) / 1000.0
			s[1] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			s[2] += 1
			if stretch % 30 == 0:
				for obj in world.unit_hash.query(world.camera.global_position, view * 0.58, scratch):
					if is_instance_valid(obj) and (obj as Unit).alive:
						s[3] += 1
						s[4] += 1 if obj is Ship and EngineStreams.HULLS.has((obj as Ship).hull_id) else 0
				s[5] += 1
		last = now
		if stretch >= LIVE_STRETCH:
			stretch = 0
			which = (which + 1) % STREAM_LOOKS.size()
			EngineStreams.set_on(which == 0)
	EngineStreams.set_on(true)
	for look: String in STREAM_LOOKS:
		var s: Array = sums[look]
		var frames := maxf(1.0, s[2])
		var samples := maxf(1.0, s[5])
		print("live %-10s: %d frames, frame mean %.2f ms, game work (process) %.2f ms, %.0f units near the camera (%.1f of them big hulls)" % [look, s[2], s[0] / frames, s[1] / frames, s[3] / samples, s[4] / samples])


## The gun kick inside a real match (--live-look=kick): like live_streams(), but the guns
## switch between kicking back when they fire and sitting still (GunKick.set_on()) every 5
## seconds of match time, so what the kick costs is measured in the same match, in the same
## fights. It also counts, per look, the ship guns near the camera whose cooldown is running
## when it samples (they have just fired), so the numbers can be read against how much
## firing there was. With --late the match starts at 25:00, fully teched, with capital ships
## (give --secs as the match time to stop at).
func live_kick(view: float) -> void:
	var secs := float(Game.opt("secs", 480.0))
	var world: World = gallery.world
	var size := gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	# Per look: [frame ms, process ms, frames, units near the camera, guns kicking, samples].
	var sums := {}
	for look: String in KICK_LOOKS:
		sums[look] = [0.0, 0.0, 0, 0, 0, 0]
	var which := 0
	GunKick.set_on(true)
	# The match time to leave out the first minute from (a late match starts at 25:00).
	var start := world.time
	var stretch := 0
	var last := Time.get_ticks_usec()
	var scratch: Array = []
	while world.time < secs:
		await gallery.get_tree().process_frame
		var now := Time.get_ticks_usec()
		stretch += 1
		if stretch % 120 == 1:
			world.camera.global_position = _busiest(world)
		if world.time > start + LIVE_SKIP:
			var s: Array = sums[KICK_LOOKS[which]]
			s[0] += float(now - last) / 1000.0
			s[1] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			s[2] += 1
			if stretch % 30 == 0:
				for obj in world.unit_hash.query(world.camera.global_position, view * 0.58, scratch):
					if is_instance_valid(obj) and (obj as Unit).alive:
						s[3] += 1
						# The guns that have just fired are the ones with a cooldown running.
						if obj is Ship:
							for m: WeaponMount in (obj as Ship).mounts:
								s[4] += 1 if m.cd > 0.0 else 0
				s[5] += 1
		last = now
		if stretch >= LIVE_STRETCH:
			stretch = 0
			which = (which + 1) % KICK_LOOKS.size()
			GunKick.set_on(which == 0)
	GunKick.set_on(true)
	for look: String in KICK_LOOKS:
		var s: Array = sums[look]
		var frames := maxf(1.0, s[2])
		var samples := maxf(1.0, s[5])
		print("live %-8s: %d frames, frame mean %.2f ms, game work (process) %.2f ms, %.0f units near the camera (%.1f ship guns on cooldown)" % [look, s[2], s[0] / frames, s[1] / frames, s[3] / samples, s[4] / samples])


## The centre of the densest knot of pilot ships and minions (the spot
## spectate_shots photographs): the pilot ship with the most pilot ships and
## minions within about 1,500 world units. The Aurelian mothership's spot if
## no pilot ship is alive.
func _busiest(world: World) -> Vector2:
	var best := world.mothership(0).global_position
	var best_n := -1
	var scratch: Array = []
	for s: Ship in world.ships:
		if not s.alive:
			continue
		var n := 0
		for obj in world.unit_hash.query(s.global_position, 1500.0, scratch):
			# A unit freed this frame can still be in the grid.
			if is_instance_valid(obj) and (obj as Unit).alive and ((obj as Unit).kind == Unit.K_SHIP or (obj as Unit).kind == Unit.K_MINION):
				n += 1
		if n > best_n:
			best_n = n
			best = s.global_position
	return best
