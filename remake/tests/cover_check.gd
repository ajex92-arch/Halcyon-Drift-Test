extends Node
## WHAT THIS IS: the scripted check of the fog of war's "hidden from outside"
## rule (cover patches: gas clouds and hidden pockets). It checks the map's own
## patches (MapCover: how many, mirrored, their size, clear of lanes, nodes,
## turrets, camps and motherships), then puts a test cloud on open ground in the
## mid lane, stands a few test ships in and around it, and checks who is seen by
## whom, and that a shot from inside the cloud shows the shooter for 120 ticks.
##
## HOW IT WORKS: setup() starts run(), a coroutine (a function that can stop
## and wait with `await`) that runs the checks one after another, waiting game
## time between them (wait()), and prints a PASS or FAIL line for each. Test
## ships are launched with no brain, so they stand still. It ends with
## "cover_check: N failures" and quits.
##
## HOW TO RUN IT (from the project folder):
##   godot --headless --path . --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=cover_check
##
## WHO USES IT: main.gd loads it for --test=cover_check (tests/<name>.gd, added
## after the World, then setup() is called). It reads the game and never changes
## it, apart from the test cloud and test ships it makes itself.

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Where the watching Halcyon ship stands (open ground in the mid lane).
const OBSERVER := Vector2(7600, 15600)
## The middle of the test cloud (world units).
const CLOUD := Vector2(9100, 15600)
## The test cloud's half width and half height (world units).
const CLOUD_HALF := 500.0
## A Vhorr ship beyond the cloud, in the open, in line with the cloud.
const BEYOND := Vector2(10400, 15600)


## main.gd calls this once, right after the World is built: stop the minion
## waves and start the checks.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	run()


## Print one PASS or FAIL line for check `name` and count the failures.
func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Wait `secs` seconds of game time (physics frames).
func wait(secs: float) -> void:
	var end := world.time + secs
	while world.time < end:
		await get_tree().physics_frame


## Launch a test ship of hull `hid` for team `team` at `at`, standing still
## and with no brain. Returns the ship.
func spawn(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new("Test-" + hid, team, 40 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.global_position = at
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## Remove a test ship quietly (no kill reward, no message).
func remove(s: Ship) -> void:
	world.combat.kill_silently(s)


## Run every check, then quit.
func run() -> void:
	# The mining drones fly about and would stand in the test cloud: remove them.
	for d in world.mining_drones.duplicate():
		world.combat.kill_silently(d)
	check("the test ground is open space", not world.asteroids.blocked(CLOUD, 60.0) and not world.asteroids.blocked(OBSERVER, 60.0) and not world.asteroids.blocked(BEYOND, 60.0))
	check_map_plan()
	await check_cloud()
	await check_fire_reveal()
	print("cover_check: %d failures" % fails)
	get_tree().quit()


## The rule itself, on a test cloud made here: with no cloud the Vhorr ships are
## seen; with it, the one inside is hidden from outside, the one beyond is not,
## and the five ways in work (touch, a unit inside, a reveal) or do not (a ray).
func check_cloud() -> void:
	var me := spawn("scout", 0, OBSERVER)
	var inside := spawn("fighter", 1, CLOUD)
	var beyond := spawn("fighter", 1, BEYOND)
	await wait(1.0)
	check("no cloud: the ship in the open is seen", inside.visible_to(0))
	check("no cloud: the ship beyond is seen", beyond.visible_to(0))
	# Make the cloud: whole fog cells inside an ellipse.
	var id := world.vision.cover.add_ellipse("cloud", CLOUD, CLOUD_HALF, CLOUD_HALF)
	check("the cloud was made from whole cells", id > 0 and world.vision.cover.cells[id].size() >= 4, str(world.vision.cover.cells[id].size()) if id > 0 else "no id")
	check("the cloud covers its middle", world.vision.cover.patch_at(CLOUD) == id and world.vision.cover.patch_at(OBSERVER) == 0)
	await wait(1.0)
	check("cloud: the ship inside is hidden from outside", not inside.visible_to(0))
	check("cloud: its point is not seen either", not world.vision.is_visible(0, CLOUD))
	check("cloud: sight passes through it to the ship beyond", beyond.visible_to(0))
	check("cloud: its own team still sees the ship inside", inside.visible_to(1))
	check("cloud: the ship inside sees out (the watcher is seen by it)", me.visible_to(1))
	# Touch range: a Halcyon ship just outside the cloud, within touch of a
	# Vhorr ship inside near its edge, sees it.
	var edge := spawn("fighter", 1, CLOUD + Vector2(350, 0))
	await wait(1.0)
	check("cloud: a ship near the edge is hidden too", not edge.visible_to(0))
	var toucher := spawn("fighter", 0, CLOUD + Vector2(680, 0))
	await wait(1.0)
	check("cloud: touch range shows a ship inside", edge.visible_to(0), "gap %d" % int(toucher.global_position.distance_to(edge.global_position)))
	check("cloud: touch shows only the ship that is touched", not inside.visible_to(0))
	remove(toucher)
	remove(edge)
	await wait(1.0)
	# One of the team's own units inside the same patch opens it.
	var partner := spawn("fighter", 0, CLOUD + Vector2(-480, 0))
	await wait(1.0)
	var gap := partner.global_position.distance_to(inside.global_position)
	check("cloud: a unit of ours inside the same cloud shows the others (gap %d, out of touch)" % int(gap), inside.visible_to(0) and gap > Rules.VISION_TOUCH + 60.0)
	remove(partner)
	await wait(1.0)
	check("cloud: it hides again once that unit is gone", not inside.visible_to(0))
	# A reveal circle (the Scout Ping) shows everything inside it.
	world.vision.reveal(0, CLOUD, 400.0, 3.0)
	await wait(1.0)
	check("cloud: a reveal shows the ship inside", inside.visible_to(0))
	await wait(3.5)
	check("cloud: it hides again when the reveal ends", not inside.visible_to(0))
	remove(me)
	remove(inside)
	remove(beyond)


## The map's own patches (MapCover): all of them are on the map, each Vhorr patch
## is the mirror image of a Halcyon one, each is a sensible size, and none lies
## over a lane line, an ore node or its turret slots, a standing turret, a camp
## or a mothership.
func check_map_plan() -> void:
	var cover := world.vision.cover
	var vision := world.vision
	var plan := MapCover.patches()
	check("every planned patch is on the map (%d)" % plan.size(), cover.count() == plan.size() and plan.size() >= 6)
	var id_of := {}
	for i in plan.size():
		id_of[str(plan[i]["id"])] = i + 1
		check("patch %s is a %s" % [plan[i]["id"], plan[i]["kind"]], str(cover.names[i + 1]) == str(plan[i]["id"]) and str(cover.kinds[i + 1]) == str(plan[i]["kind"]))
	# Mirror images: every cell of a Halcyon patch has its mirror cell in the twin.
	for key: String in id_of.keys():
		if key.ends_with("_m") or not id_of.has(key + "_m"):
			continue
		var twin: PackedInt32Array = cover.cells[id_of[key + "_m"]]
		var mine: PackedInt32Array = cover.cells[id_of[key]]
		var all_in := twin.size() == mine.size()
		for c in mine:
			var mirrored: int = (c / vision.cols) * vision.cols + (vision.cols - 1 - c % vision.cols)
			if not twin.has(mirrored):
				all_in = false
		check("patch %s has its mirror image" % key, all_in)
	# Size and place.
	var clear_fails := 0
	for i in plan.size():
		var id: int = i + 1
		var lo := Vector2i(vision.cols, vision.rows)
		var hi := Vector2i(-1, -1)
		for c in cover.cells[id] as PackedInt32Array:
			lo = Vector2i(mini(lo.x, c % vision.cols), mini(lo.y, c / vision.cols))
			hi = Vector2i(maxi(hi.x, c % vision.cols), maxi(hi.y, c / vision.cols))
		var w := float(hi.x - lo.x + 1) * vision.cell
		var h := float(hi.y - lo.y + 1) * vision.cell
		check("patch %s is about 800 to 1,600 across (%d x %d)" % [plan[i]["id"], int(w), int(h)], w >= 800.0 and w <= 1800.0 and h >= 800.0 and h <= 1800.0)
		# A pocket must be a room a ship can fly into: nearly all of its cells are open ground.
		if str(plan[i]["kind"]) == "pocket":
			var open := 0
			var all := cover.cells[id] as PackedInt32Array
			for c in all:
				if not world.asteroids.blocked(Vector2((float(c % vision.cols) + 0.5) * vision.cell, (float(c / vision.cols) + 0.5) * vision.cell), 25.0):
					open += 1
			check("pocket %s is open ground (%d of %d cells)" % [plan[i]["id"], open, all.size()], float(open) >= 0.75 * float(all.size()))
		var worst := _clearance(id)
		if worst != "":
			clear_fails += 1
		check("patch %s keeps clear of lanes, nodes, slots, turrets, camps and motherships" % plan[i]["id"], worst == "", worst)
	check("no patch is over anything it must keep clear of", clear_fails == 0)


## "" if every cell of patch `id` keeps clear of the lane lines (500), ore nodes
## (900), node turret slots (500), standing turrets (500), camps (800) and
## motherships (3,000); otherwise a short text naming the first thing too close.
func _clearance(id: int) -> String:
	var vision := world.vision
	for c in vision.cover.cells[id] as PackedInt32Array:
		var p := Vector2((float(c % vision.cols) + 0.5) * vision.cell, (float(c / vision.cols) + 0.5) * vision.cell)
		for lane_id: String in world.map.lanes:
			if _line_dist(p, world.map.lanes[lane_id]) < 500.0:
				return "lane " + lane_id + " at " + str(p)
		for n in world.nodes:
			if p.distance_to(n.global_position) < 900.0:
				return "node " + str(n.node_name) + " at " + str(p)
			for sp in n.slot_pos:
				if p.distance_to(sp) < 500.0:
					return "a slot of node " + str(n.node_name) + " at " + str(p)
		for t in world.turrets:
			if p.distance_to(t.global_position) < 500.0:
				return "a turret at " + str(p)
		for camp: Dictionary in world.map.camps:
			if p.distance_to(camp["pos"]) < 800.0:
				return "camp " + str(camp["id"]) + " at " + str(p)
		for mp: Vector2 in world.map.mothership_pos:
			if p.distance_to(mp) < 3000.0:
				return "a mothership at " + str(p)
	return ""


## The distance from `p` to the polyline `pts` (world units).
func _line_dist(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


## A unit that fires from inside a cover patch is seen by everyone for
## Rules.COVER_REVEAL_TICKS ticks, counted in whole ticks; a shot from open
## ground starts nothing. Uses the test cloud made by check_cloud().
func check_fire_reveal() -> void:
	var me := spawn("scout", 0, OBSERVER)
	var inside := spawn("fighter", 1, CLOUD)
	var open := spawn("fighter", 1, BEYOND)
	await wait(1.0)
	check("fire: the ship in the cloud is hidden before it fires", not inside.visible_to(0))
	check("fire: nothing was set yet", inside.revealed_until < 0 and open.revealed_until < 0)
	# Both Vhorr ships pull the trigger for a moment.
	inside.controls.fire = true
	open.controls.fire = true
	await wait(0.4)
	inside.controls.fire = false
	open.controls.fire = false
	var left := inside.revealed_until - world.visibility.ticks
	check("fire: a shot from the cloud sets the reveal (%d ticks left, at most %d)" % [left, Rules.COVER_REVEAL_TICKS], inside.revealed_until >= 0 and left > Rules.COVER_REVEAL_TICKS - 40 and left <= Rules.COVER_REVEAL_TICKS)
	check("fire: a shot from open ground sets nothing", open.revealed_until < 0)
	# Seen while the ticks last.
	var last := inside.revealed_until
	while world.visibility.ticks < last - 20:
		await get_tree().physics_frame
	check("fire: the shooter is seen while the reveal lasts", inside.visible_to(0))
	# Hidden again once the last tick is past (the next vision update at most 12 ticks later).
	while world.visibility.ticks <= last + 14:
		await get_tree().physics_frame
	check("fire: it is hidden again after %d ticks" % Rules.COVER_REVEAL_TICKS, not inside.visible_to(0))
	remove(me)
	remove(inside)
	remove(open)
