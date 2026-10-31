extends Node
## WHAT THIS IS: the check of the engine streams of the big ships (EngineStreams,
## ShipVisual): every nozzle of the four big hulls of both teams shows a stream of
## its own, the other ships keep one, and drawing the streams leaves the match's
## shared random numbers alone.
##
## HOW IT WORKS: setup() freezes the match and then checks, in this order:
##   1. the tables: the big hulls have the nozzle counts they are drawn with (Flak 3,
##      Ion 3, Destroyer 4, Battlecruiser 5, both teams), every nozzle lies inside its
##      hull's outline, no two nozzles of a hull overlap, and every other hull has no
##      nozzle list (one stream);
##   2. the rules of EngineStreams: one stream is today's (24 dots), more streams have 36
##      dots each, the round of starting places gives a nozzle places in proportion to its
##      radius, spread through the round, behind the nozzle and across its width, and the
##      streams are sized to their nozzles (a bigger nozzle's is longer, boosting is
##      longer, the red team's a quarter shorter, a screen floor for tiny ones);
##   3. the dice: one flame-like emitter is run for a while in six ways and the shared
##      random sequence after each is compared with the one after the plain emitter. The
##      ways ShipVisual uses (more dots; the starting point moved every frame, with a
##      different dot speed each time) must leave it in the same place. The ways it does
##      not use (a list of starting points, an area to start from) are run too and
##      printed as INFO, not judged: with Godot 4.7.2 the list of starting points takes
##      numbers from the sequence for every dot it starts (that is why the streams are
##      made by moving the one point) and the area does not. A CPUParticles2D takes one
##      number when it is made, the same for all six;
##   4. the ships: it launches every hull for both teams, lets the painters run a few
##      frames, and checks each ship's flames: still three emitters (none was added),
##      the main one starting its dots from one point, holding 24 dots for a ship with one
##      stream and EngineStreams.dots() dots for a big hull, and its starting point visiting
##      one place for a ship with one stream and a place per nozzle (at least) for a big hull.
## It prints one line per check ("PASS ..." or "FAIL ...") and then
## "stream_check: N failures" (0 means every check passed).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=stream_check
## (Not with --sim-only: that draws nothing and makes no flames.)
##
## WHO USES IT: main.gd loads it for --test=stream_check. It changes only a frozen match
## that is thrown away.

## The expected nozzle count of each big hull, the same for both teams.
const COUNTS := {"flak": 3, "ion": 3, "destroyer": 4, "battlecruiser": 5}
## How many frames the dice check lets its emitters run.
const DICE_FRAMES := 90
## The six ways of running the dice check's emitter: [name, whether ShipVisual does it].
const DICE_WAYS := [
	["plain", true], ["plain again", true], ["more dots", true], ["one point moved every frame", true],
	["a list of starting points", false], ["an area to start from", false],
]

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Run every check and quit.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Every check, then the verdict.
func _run() -> void:
	for _i in 3:
		await get_tree().process_frame
	if Game.sim_only:
		_check("run without --sim-only (it draws nothing and makes no flames)", false)
	_tables()
	_rules()
	await _dice()
	await _ships()
	print("stream_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed) and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Check 1: the nozzle tables of both teams.
func _tables() -> void:
	for team in [Rules.HALCYON, Rules.CINDER]:
		var tname := "Aurelian" if team == Rules.HALCYON else "Cinder"
		for hid: String in Ships.ORDER:
			var nz := EngineStreams.nozzles(team, hid)
			if not COUNTS.has(hid):
				_check("%s %s keeps one stream (no nozzle list)" % [tname, hid], nz.is_empty(), str(nz.size()))
				continue
			_check("%s %s has %d nozzles" % [tname, hid, COUNTS[hid]], nz.size() == COUNTS[hid], str(nz.size()))
			var outline: PackedVector2Array = PackedVector2Array(AurelianPaint.outline(hid)) if team == Rules.HALCYON else CinderPaint.hull(hid)["sil"]
			var inside := 0
			for n: Vector3 in nz:
				if Geometry2D.is_point_in_polygon(Vector2(n.x, n.y), outline):
					inside += 1
			_check("%s %s: every nozzle's middle lies inside its outline" % [tname, hid], inside == nz.size(), "%d of %d" % [inside, nz.size()])
			var overlaps := 0
			for i in nz.size():
				for j in range(i + 1, nz.size()):
					var a: Vector3 = nz[i]
					var b: Vector3 = nz[j]
					if Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) < a.z + b.z - 0.001:
						overlaps += 1
			_check("%s %s: no two nozzles overlap" % [tname, hid], overlaps == 0, str(overlaps))


## Check 2: the numbers and the round of EngineStreams.
func _rules() -> void:
	_check("one stream: 24 dots", EngineStreams.dots(1) == 24)
	for n in range(2, 7):
		_check("%d streams: %d dots each, so %d" % [n, EngineStreams.DOTS_PER_STREAM, EngineStreams.dots(n)], EngineStreams.dots(n) == EngineStreams.DOTS_PER_STREAM * n)
	# A hull facing right (+x; port is up the screen), one big and one half-size nozzle.
	var f := Vector2.RIGHT
	var port := Util.port_of(0.0)
	var list: Array = [Vector3(-10, 0, 1.0), Vector3(-9, 3, 0.5)]
	var the_plan := EngineStreams.plan(list)
	var which: PackedInt32Array = the_plan["nozzle"]
	var big := 0
	for i in which.size():
		big += 1 if which[i] == 0 else 0
	_check("the round: the nozzle twice as big has twice the places", which.size() == 12 and big == 8, "%d of %d" % [big, which.size()])
	var adjacent := 0
	for i in which.size():
		adjacent += 1 if which[i] == 1 and which[(i + 1) % which.size()] == 1 else 0
	_check("the round: every nozzle is in it, and the smaller one is never asked twice in a row", which.has(0) and which.has(1) and adjacent == 0, str(which))
	var behind := true
	var across := true
	for step in which.size():
		var p := EngineStreams.spot(list, the_plan, step, 10.0, f, port, 1.0)
		var n: Vector3 = list[which[step]]
		behind = behind and absf(p.x - (n.x - n.z) * 10.0) < 0.01
		across = across and absf(absf(p.y) - absf(n.y * 10.0)) <= n.z * 10.0 * EngineStreams.SPREAD + 0.01
	_check("the round: every place sits on its nozzle's back rim and inside its width", behind and across)
	_check("the round: it wraps", EngineStreams.spot(list, the_plan, 3, 10.0, f, port, 1.0) == EngineStreams.spot(list, the_plan, 3 + which.size(), 10.0, f, port, 1.0))
	# The sizes: sized to the nozzle (big zoomed in), longer boosting, shorter for the red team, never under the screen floor.
	var big_step: int = which.find(0)
	var small_step: int = which.find(1)
	var big_v := EngineStreams.speed_range(the_plan, big_step, 20.0, 1.0, false, 1.0)
	var small_v := EngineStreams.speed_range(the_plan, small_step, 20.0, 1.0, false, 1.0)
	_check("the sizes: the bigger nozzle's dots are faster, so its stream is longer", big_v.y > small_v.y and big_v.x < big_v.y, "%s against %s" % [str(big_v), str(small_v)])
	_check("the sizes: boosting is faster", EngineStreams.speed_range(the_plan, big_step, 20.0, 1.0, true, 1.0).y > big_v.y * 1.5)
	_check("the sizes: the red team's streams are 0.75 as long", absf(EngineStreams.speed_range(the_plan, big_step, 20.0, 1.0, false, 0.75).y - 0.75 * big_v.y) < 0.01)
	_check("the sizes: the floor keeps a tiny nozzle's stream at 7 screen pixels", EngineStreams.speed_range(the_plan, small_step, 0.01, 1.0, false, 1.0).y * EngineStreams.DOT_LIFE >= EngineStreams.MIN_LENGTH_PX * 1.2)
	var dr := EngineStreams.dot_range(the_plan, 20.0, 1.0, false, 1.0)
	_check("the sizes: the dots are a fraction of the nozzle width, bigger boosting", dr.x < dr.y and EngineStreams.dot_range(the_plan, 20.0, 1.0, true, 1.0).y > dr.y and dr.y > 1.0, str(dr))
	_check("the sizes: a tiny hull's dots keep the screen floor", EngineStreams.dot_range(the_plan, 0.01, 1.0, false, 1.0).x >= 0.65 * EngineStreams.MIN_DOT_PX - 0.001)

## Check 3: the dice. For each of the DICE_WAYS, the shared random sequence after the
## emitter has run is compared with the one after the plain emitter.
func _dice() -> void:
	var control := await _dice_run("plain")
	for way: Array in DICE_WAYS:
		var got := await _dice_run(str(way[0]))
		var same := got == control
		if bool(way[1]):
			_check("the dice: %s leaves the next three random numbers where they were" % way[0], same, "%s against %s" % [str(got), str(control)])
		else:
			print("INFO the dice: %s %s the sequence (ShipVisual does not use it)" % [way[0], "leaves" if same else "moves"])


## One run of the dice check: seed the shared sequence, run one flame-like emitter for
## DICE_FRAMES frames the way `way` says (a name of DICE_WAYS), free it and return the
## next three numbers of the sequence.
func _dice_run(way: String) -> Array:
	seed(4242)
	var p := CPUParticles2D.new()
	p.amount = 24
	p.lifetime = 0.35
	p.local_coords = false
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.top_level = true
	p.emitting = true
	add_child(p)
	var list: Array = [Vector3(-10, 0, 1.2), Vector3(-9, 3, 0.7), Vector3(-9, -3, 0.7), Vector3(-8, 5, 0.5), Vector3(-8, -5, 0.5)]
	var the_plan := EngineStreams.plan(list)
	match way:
		"more dots":
			p.amount = EngineStreams.dots(5)
		"one point moved every frame":
			p.amount = EngineStreams.dots(5)
			p.spread = EngineStreams.FAN_DEG
		"a list of starting points":
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
			p.emission_points = PackedVector2Array([Vector2(0, 0), Vector2(0, 20), Vector2(0, -20)])
		"an area to start from":
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = Vector2(2.0, 20.0)
	for i in DICE_FRAMES:
		if way == "one point moved every frame":
			p.global_position = EngineStreams.spot(list, the_plan, i, 10.0, Vector2.RIGHT, Vector2.UP, 1.0)
			var speeds := EngineStreams.speed_range(the_plan, i, 10.0, 1.0, false, 1.0)
			p.initial_velocity_min = speeds.x
			p.initial_velocity_max = speeds.y
		await get_tree().process_frame
	p.queue_free()
	await get_tree().process_frame
	return [randi(), randi(), randi()]


## Check 4: real ships of every hull and both teams.
func _ships() -> void:
	var ships: Array[Ship] = []
	for team in [Rules.HALCYON, Rules.CINDER]:
		for hid: String in Ships.ORDER:
			var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
			p.hull_id = hid
			world.profiles.append(p)
			var s := world.launch(p)
			s.controller = null
			s.thrust_main = 0.7
			ships.append(s)
	for _i in 5:
		await get_tree().process_frame
	# Watch where each ship's main emitter stands over the next frames.
	var spots := {}
	for s: Ship in ships:
		spots[s] = {}
	for _i in 40:
		await get_tree().process_frame
		for s: Ship in ships:
			var v := s.get_node("Visual") as ShipVisual
			spots[s][str(v.main_jet.global_position.snappedf(0.01))] = true
	for s: Ship in ships:
		var v := s.get_node("Visual") as ShipVisual
		var tname := "Aurelian" if s.team == Rules.HALCYON else "Cinder"
		var label := "%s %s" % [tname, s.hull_id]
		var emitters := 0
		for c in v.get_children():
			if c is CPUParticles2D:
				emitters += 1
		_check("%s: three flame emitters, none added" % label, emitters == 3, str(emitters))
		_check("%s: the main flame starts its dots from one point" % label, v.main_jet.emission_shape == CPUParticles2D.EMISSION_SHAPE_POINT)
		var want: int = COUNTS.get(s.hull_id, 1)
		var places: int = (spots[s] as Dictionary).size()
		if want == 1:
			_check("%s: one stream, 24 dots, a 12 degree fan, one place" % label, v.main_jet.amount == 24 and is_equal_approx(v.main_jet.spread, 12.0) and places == 1, "%d dots, %d places" % [v.main_jet.amount, places])
		else:
			_check("%s: %d streams, %d dots, a narrow fan, at least a place for each" % [label, want, EngineStreams.dots(want)], v.main_jet.amount == EngineStreams.dots(want) and is_equal_approx(v.main_jet.spread, EngineStreams.FAN_DEG) and places >= want, "%d dots, fan %.1f, %d places" % [v.main_jet.amount, v.main_jet.spread, places])
		_check("%s: the main flame burns" % label, v.main_jet.emitting)
