extends Node
## WHAT THIS IS: the check of the figure on each ore node: "X/Y" (X the viewer's team's drones at the node, Y the most
## drones the node supports without running dry), its colour by how full the node is, the danger triangle's rule, the
## fade of the figure and the tint of the whole node as the camera pulls out, and that the key that decides when a node is
## drawn again holds what the figure shows. The model behind Y (the ore a drone really brings in each second over a whole
## trip) is held against a real drone's deliveries.
##
## HOW IT WORKS: setup() waits for the match's starting drones and then walks the cases: (a) the numbers of every node,
## (b) the pure arithmetic, (c) the bands on two real nodes with their ore set to chosen fractions (put back afterwards),
## (d) the colours and their distances from the team, scum and danger colours, (e) the fade, also through the real camera,
## (f) a measured case: one drone sent to the nearest ore node and timed over three deliveries, (g) the figure's words and
## the redraw key on a node of each kind with the camera on it, (h) the danger triangle's rule. The drawing itself is never
## run (a headless run draws nothing). It prints a FAIL line for every case that does not hold, each starting with its case
## letter, INFO lines for the numbers a person may want to read, then "node_numbers_check: N failures (M checks)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=node_numbers_check
##
## WHO USES IT: main.gd loads it for --test=node_numbers_check (it calls setup()); the lead's run_checks list.

## How far apart two look-alike colours must be: the game's own limit for team and highlight colours, as the flash check
## uses it (its LOOK_DISTANCE), measured in red, green and blue.
const LOOK_DISTANCE := 0.15

## The match.
var world: World
## How many checks ran.
var checks := 0
## How many of them failed.
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


## Count one check; print a FAIL line (starting with the case letter in `what`) when it does not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Wait `n` physics frames (one match tick each).
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The living drones of `team`, in their stored order.
func _drones_of(team: int) -> Array[MiningDrone]:
	var out: Array[MiningDrone] = []
	for d in world.mining_drones:
		if d.team == team and d.alive:
			out.append(d)
	return out


## The first node of kind `kind` that has ore rocks, or null.
func _first_of_kind(kind: String) -> ResourceNode:
	for n in world.nodes:
		if n.node_kind == kind and n.ore.size() > 0:
			return n
	return null


## The straight-line distance between two colours in red, green and blue.
func _dist(a: Color, b: Color) -> float:
	return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))


## Case (a): the numbers of every node.
func _case_a() -> void:
	var digits := RegEx.new()
	digits.compile("^[0-9]+/[0-9]+$")
	var mine_rate := float(Structures.MINING_DRONE["mine_rate"])
	var keys := ["drones", "refill", "draw", "breakeven", "fullness"]
	for n in world.nodes:
		if n.ore.size() == 0:
			_check("(a) %s has no rocks: numbers(0) is empty" % n.node_id, n.numbers(0).is_empty())
			_check("(a) %s has no rocks: figure_text(0) is empty" % n.node_id, n.figure_text(0) == "")
			continue
		var nums := n.numbers(0)
		var has_keys := nums.size() == keys.size()
		for k in keys:
			has_keys = has_keys and nums.has(k)
		_check("(a) %s: numbers(0) has exactly the five keys" % n.node_id, has_keys, str(nums.keys()))
		if not has_keys:
			continue
		var count := 0
		for d in world.mining_drones:
			if d.team == 0 and d.node_id == n.node_id:
				count += 1
		_check("(a) %s: drones is the count of team 0 drones there" % n.node_id, int(nums["drones"]) == count, "%d vs %d" % [int(nums["drones"]), count])
		var refill := MapLayout.ORE_REGEN * n.value * float(n.ore.size())
		_check("(a) %s: refill is regrowth x value x rocks" % n.node_id, is_equal_approx(float(nums["refill"]), refill), "%f vs %f" % [float(nums["refill"]), refill])
		var draw := float(nums["draw"])
		_check("(a) %s: 0 < draw < mine_rate" % n.node_id, draw > 0.0 and draw < mine_rate, "draw=%f" % draw)
		_check("(a) %s: breakeven x draw is refill" % n.node_id, absf(float(nums["breakeven"]) * draw - float(nums["refill"])) < 0.001)
		var full := n.total_ore() / n.total_ore_max()
		_check("(a) %s: fullness is ore left over most ore" % n.node_id, absf(float(nums["fullness"]) - full) < 0.000001, "%f vs %f" % [float(nums["fullness"]), full])
		_check("(a) %s: numbers(-1) is empty" % n.node_id, n.numbers(-1).is_empty())
		var text := n.figure_text(0)
		var want := "%d/%d" % [count, ResourceNode.drones_supported(float(nums["refill"]), draw)]
		_check("(a) %s: figure_text is drones/supported" % n.node_id, text == want, "%s vs %s" % [text, want])
		_check("(a) %s: figure_text is digits, a slash and digits" % n.node_id, digits.search(text) != null, text)
		var low := text.to_lower()
		_check("(a) %s: figure_text holds no nan, inf or null" % n.node_id, not ("nan" in low or "inf" in low or "null" in low), text)
		print("INFO (a) %s: figure %s, refill %.1f, draw %.2f, breakeven %.2f" % [n.node_id, text, float(nums["refill"]), draw, float(nums["breakeven"])])


## Case (b): the pure arithmetic.
func _case_b() -> void:
	_check("(b) trip_draw with no haul is the mining rate", is_equal_approx(ResourceNode.trip_draw(300.0, 40.0, 460.0, 0.0), 40.0))
	var long_trip := ResourceNode.trip_draw(300.0, 40.0, 460.0, 9200.0)
	_check("(b) trip_draw over a haul of 9200 is 300 / (7.5 + 40)", absf(long_trip - 300.0 / 47.5) < 0.01, "%f" % long_trip)
	_check("(b) drones_supported(30, 6.32) is 4", ResourceNode.drones_supported(30.0, 6.32) == 4)
	_check("(b) drones_supported(45, 9) is 5", ResourceNode.drones_supported(45.0, 9.0) == 5)
	_check("(b) drones_supported(30, 40) is 0", ResourceNode.drones_supported(30.0, 40.0) == 0)
	_check("(b) drones_supported(30, 0) is 0, never a division by zero", ResourceNode.drones_supported(30.0, 0.0) == 0)


## Set every rock of node `n` to `f` times its most ore.
func _fill(n: ResourceNode, f: float) -> void:
	for i in n.ore.size():
		n.ore[i] = n.ore_max[i] * f


## Case (c): the bands, on the pure function and on two real nodes.
func _case_c() -> void:
	_check("(c) fullness 1.0 is green", ResourceNode.fullness_band(1.0) == ResourceNode.BAND_GREEN)
	_check("(c) fullness 0.75 is green", ResourceNode.fullness_band(0.75) == ResourceNode.BAND_GREEN)
	_check("(c) fullness 0.7499 is yellow", ResourceNode.fullness_band(0.7499) == ResourceNode.BAND_YELLOW)
	_check("(c) fullness 0.15 is yellow", ResourceNode.fullness_band(0.15) == ResourceNode.BAND_YELLOW)
	_check("(c) fullness 0.1499 is low", ResourceNode.fullness_band(0.1499) == ResourceNode.BAND_LOW)
	_check("(c) fullness 0.0 is low", ResourceNode.fullness_band(0.0) == ResourceNode.BAND_LOW)
	var fractions := [1.0, 0.80, 0.70, 0.20, 0.10]
	var bands := [0, 0, 1, 1, 2]
	for kind in ["jungle_team", "jungle_shared"]:
		var n := _first_of_kind(kind)
		_check("(c) setup: the map has a %s node with ore" % kind, n != null)
		if n == null:
			continue
		var saved := n.ore.duplicate()
		var first_text := ""
		for i in fractions.size():
			var f: float = fractions[i]
			_fill(n, f)
			var nums := n.numbers(0)
			var fullness := float(nums["fullness"])
			_check("(c) %s at %.2f: fullness is %.2f" % [kind, f, f], absf(fullness - f) < 0.001, "%f" % fullness)
			_check("(c) %s at %.2f: the band is %d" % [kind, f, bands[i]], ResourceNode.fullness_band(fullness) == bands[i], "band %d" % ResourceNode.fullness_band(fullness))
			var text := n.figure_text(0)
			if i == 0:
				first_text = text
			_check("(c) %s at %.2f: the figure does not depend on the ore left" % [kind, f], text == first_text, "%s vs %s" % [text, first_text])
		n.ore = saved


## Case (d): the colours.
func _case_d() -> void:
	_check("(d) the low band is the game's danger colour", ResourceNode.band_color(ResourceNode.BAND_LOW) == Palette.DANGER)
	var g := ResourceNode.band_color(ResourceNode.BAND_GREEN)
	var y := ResourceNode.band_color(ResourceNode.BAND_YELLOW)
	var l := ResourceNode.band_color(ResourceNode.BAND_LOW)
	_check("(d) the three band colours are three different colours", g != y and y != l and g != l)
	print("INFO (d) the distance limit is %.2f (the flash check's LOOK_DISTANCE)" % LOOK_DISTANCE)
	var others := {"DANGER": Palette.DANGER, "AMBER": Palette.AMBER, "SCUM_HAZARD": Palette.SCUM_HAZARD, "SCUM_GLOW": Palette.SCUM_GLOW}
	var mine := {"NODE_GREEN": ResourceNode.NODE_GREEN, "NODE_YELLOW": ResourceNode.NODE_YELLOW}
	for mine_name in mine:
		for other_name in others:
			var dist := _dist(mine[mine_name], others[other_name])
			print("INFO (d) %s is %.3f from %s" % [mine_name, dist, other_name])
			_check("(d) %s is more than %.2f from %s" % [mine_name, LOOK_DISTANCE, other_name], dist > LOOK_DISTANCE, "%.3f" % dist)


## Case (e): the fade, on the pure functions and through the real camera.
func _case_e() -> void:
	var full_w := ResourceNode.FIGURE_FULL_VIEW_W
	var gone_w := ResourceNode.FIGURE_GONE_VIEW_W
	var mid_w := (full_w + gone_w) * 0.5
	_check("(e) the figure is fully shown at the near limit", is_equal_approx(ResourceNode.figure_alpha(full_w), 1.0))
	_check("(e) the figure is gone at the far limit", is_equal_approx(ResourceNode.figure_alpha(gone_w), 0.0))
	_check("(e) the figure is half shown in the middle", absf(ResourceNode.figure_alpha(mid_w) - 0.5) < 0.001)
	_check("(e) the figure is fully shown below the near limit", is_equal_approx(ResourceNode.figure_alpha(full_w - 500.0), 1.0))
	_check("(e) the figure is gone above the far limit", is_equal_approx(ResourceNode.figure_alpha(gone_w + 500.0), 0.0))
	_check("(e) no tint at the near limit", is_equal_approx(ResourceNode.tint_alpha(full_w), 0.0))
	_check("(e) the full tint at the far limit", is_equal_approx(ResourceNode.tint_alpha(gone_w), ResourceNode.TINT_ALPHA))
	_check("(e) half the tint in the middle", absf(ResourceNode.tint_alpha(mid_w) - ResourceNode.TINT_ALPHA * 0.5) < 0.001)
	_check("(e) the opening view (6000 across) shows no figure", is_equal_approx(ResourceNode.figure_alpha(6000.0), 0.0))
	_check("(e) the opening view (6000 across) shows the full tint", is_equal_approx(ResourceNode.tint_alpha(6000.0), ResourceNode.TINT_ALPHA))
	var n := _first_of_kind("jungle_team")
	if n == null or world.camera == null:
		_check("(e) setup: a node and the camera exist", false)
		return
	var vw := get_viewport().get_visible_rect().size.x
	for view in [2000.0, 8000.0]:
		world.camera.target_zoom = vw / view
		var settled := false
		for i in 120:
			if absf(world.camera.zoom.x - world.camera.target_zoom) <= 0.005 * world.camera.target_zoom:
				settled = true
				break
			await _frames(1)
		_check("(e) the camera reached the %d view (the camera never reached the close view)" % int(view), settled, "zoom %f target %f" % [world.camera.zoom.x, world.camera.target_zoom])
		var seen := n._view_w()
		var expect := vw / world.camera.zoom.x
		_check("(e) the node reads the view width at %d across" % int(view), absf(seen - expect) <= 0.01 * expect, "%f vs %f" % [seen, expect])
		if view < full_w:
			_check("(e) at %d across the figure shows fully" % int(view), is_equal_approx(ResourceNode.figure_alpha(seen), 1.0), "%f" % ResourceNode.figure_alpha(seen))
		else:
			_check("(e) at %d across the figure is gone" % int(view), is_equal_approx(ResourceNode.figure_alpha(seen), 0.0), "%f" % ResourceNode.figure_alpha(seen))
			_check("(e) at %d across the tint is full" % int(view), is_equal_approx(ResourceNode.tint_alpha(seen), ResourceNode.TINT_ALPHA), "%f" % ResourceNode.tint_alpha(seen))


## Case (f): a drone is sent to the nearest ore node and timed over three deliveries; the model's draw is held against it.
func _case_f() -> void:
	var mine := _drones_of(0)
	if mine.is_empty():
		_check("(f) setup: a living team 0 drone", false)
		return
	var d := mine[0]
	var home := world.mothership(0).global_position
	var near: ResourceNode = null
	for n in world.nodes:
		if n.ore.size() == 0 or (MapLayout.is_team_kind(n.node_kind) and n.side != 0):
			continue
		if near == null or n.global_position.distance_to(home) < near.global_position.distance_to(home):
			near = n
	if near == null:
		_check("(f) setup: an ore node the team may mine", false)
		return
	d.cargo = 0.0
	d.send_to(near.node_id)
	var times: Array[float] = []
	var loads: Array[float] = []
	var prev := d.cargo
	var start := world.time
	var died := false
	while times.size() < 3 and world.time - start < 240.0:
		await _tick()
		if not d.alive:
			died = true
			break
		if prev > 0.5 and d.cargo == 0.0:
			times.append(world.time)
			loads.append(prev)
		prev = d.cargo
	if died or times.size() < 3:
		_check("(f) the drone never finished three trips", false, "deliveries %d, died %s, time %.1f" % [times.size(), str(died), world.time - start])
		return
	var measured := (loads[1] + loads[2]) / (times[2] - times[0])
	var predicted := float(near.numbers(0)["draw"])
	var ratio := predicted / measured if measured > 0.0 else 0.0
	print("INFO (f) node %s: measured draw %.3f, predicted draw %.3f, predicted over measured %.3f" % [near.node_id, measured, predicted, ratio])
	_check("(f) the predicted draw is within a factor of 2 of the measured one", measured > 0.0 and predicted <= 2.0 * measured and predicted >= 0.5 * measured, "measured %.3f predicted %.3f" % [measured, predicted])


## Case (g): the figure on the nodes a player sees: the words and the redraw key, with the camera on one node of each kind.
func _case_g() -> void:
	if world.camera == null:
		_check("(g) setup: the camera exists", false)
		return
	for kind in ["jungle_team", "jungle_shared"]:
		var n := _first_of_kind(kind)
		_check("(g) setup: the map has a %s node with ore" % kind, n != null)
		if n == null:
			continue
		world.camera.look_at_point(n.global_position)
		await _frames(10)
		var text := n.figure_text(world.viewer_team)
		_check("(g) %s: the viewer's figure is not empty" % kind, text != "", text)
		_check("(g) %s: the node was asked for a picture while the camera was on it" % kind, n._look.size() > 0)
		var key := n._look_key()
		var nums := n.numbers(world.viewer_team)
		var band := ResourceNode.fullness_band(float(nums["fullness"]))
		var tail := key.slice(key.size() - 5)
		var want_y := ResourceNode.drones_supported(float(nums["refill"]), float(nums["draw"]))
		_check("(g) %s: the key ends with the band" % kind, tail[0] == band, str(tail))
		_check("(g) %s: the key holds X" % kind, tail[1] == int(nums["drones"]), str(tail))
		_check("(g) %s: the key holds Y" % kind, tail[2] == want_y, str(tail))
		_check("(g) %s: the key holds the triangle flag" % kind, tail[4] == (1 if ResourceNode.shows_danger(band) else 0), str(tail))


## Case (h): the danger triangle goes with the low band and with nothing else.
func _case_h() -> void:
	_check("(h) no triangle in the green band", not ResourceNode.shows_danger(ResourceNode.BAND_GREEN))
	_check("(h) no triangle in the yellow band", not ResourceNode.shows_danger(ResourceNode.BAND_YELLOW))
	_check("(h) a triangle in the low band", ResourceNode.shows_danger(ResourceNode.BAND_LOW))
	var fractions := [1.0, 0.80, 0.70, 0.20, 0.10]
	var want := [false, false, false, false, true]
	for kind in ["jungle_team", "jungle_shared"]:
		var n := _first_of_kind(kind)
		if n == null:
			_check("(h) setup: the map has a %s node with ore" % kind, false)
			continue
		var saved := n.ore.duplicate()
		for i in fractions.size():
			_fill(n, fractions[i])
			var shown := ResourceNode.shows_danger(ResourceNode.fullness_band(float(n.numbers(0)["fullness"])))
			_check("(h) %s at %.2f: the triangle is %s" % [kind, fractions[i], str(want[i])], shown == want[i], str(shown))
		n.ore = saved


## Wait for the starting drones, run the cases, print the result.
func _run() -> void:
	var ok := true
	for i in 120:
		if not _drones_of(0).is_empty():
			break
		await _tick()
	ok = not _drones_of(0).is_empty()
	_check("(setup) team 0 has a living drone", ok)
	if not ok:
		_finish()
		return
	_case_a()
	_case_b()
	_case_c()
	_case_d()
	_case_h()
	await _case_e()
	await _case_g()
	await _case_f()
	_finish()


## Print the result line and end the run.
func _finish() -> void:
	print("node_numbers_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()
