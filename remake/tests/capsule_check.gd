extends Node
## WHAT THIS IS: the check of the hull hit capsule: the frigates, the Destroyer
## and the Battlecruiser are hit as a capsule (a line along the hull with a round
## end at each end), every other ship is hit as a circle exactly as before. It
## prints one line per group and then "capsule_check: N failures" (0 means all is
## as it should be).
##
## HOW IT WORKS: it builds the normal match and freezes it, launches one ship of
## each hull and tests:
##   - the geometry: with a segment of length 0 (a circle) Util.seg_capsule_t
##     gives exactly Util.seg_circle_t on a set of random segments; with a real
##     spine its answer matches a slow march along the segment, and the point it
##     names lies on the capsule's edge;
##   - the four capsule hulls, at 8 headings: a swept line that ends 2 world units
##     inside the rim hits, one that ends 2 units outside misses, at the bow tip,
##     the stern tip, the flank and a diagonal; every gun mount of the hull lies
##     inside its capsule; hit_reach() is the farthest point of the capsule from
##     the centre;
##   - the impact point: a bolt that hits the Battlecruiser's flank makes a note
##     whose impact point is the point where it touched the hull, not where it was
##     a tick before; the same bolt at a circle hull gives the old note (the
##     point one tick before); a beam from the same muzzle gives the same shield
##     zone and armour section as the bolt (both read the true point);
##   - the circles: the six other pilot hulls give exactly the old circle test
##     (Util.seg_circle_t over hit_radius() + pad) on 200 random segments, and
##     their reach and edge distance are the old ones; the mothership has no
##     capsule shape of its own (its hull test is its own).
## The random numbers come from a generator with a fixed seed, in this test only.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=capsule_check
##
## WHO USES IT: main.gd loads it for --test=capsule_check (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()); run_checks
## runs it. It only reads the game: the match stands still.

## The hulls hit as a capsule.
const CAPSULES := ["flak", "ion", "destroyer", "battlecruiser"]
## The hulls hit as a circle.
const CIRCLES := ["scout", "fighter", "lance", "bomber", "logistics", "support"]
## How many headings each capsule is tried at.
const HEADINGS := 8
## How far (world units) inside or outside the rim a probe line ends.
const RIM := 2.0
## How many random segments the circle and geometry tests use.
const SEGMENTS := 200
## How many steps the slow march along a segment takes.
const MARCH := 4000

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## The random numbers of this test (a fixed seed).
var rng := RandomNumberGenerator.new()
## The note of the last hit that was applied (Events.damage_applied), or null.
var last_note: DamageInfo = null


## main.gd calls this once, right after the World is built. Freeze the match and
## start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Run every group, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	rng.seed = 56
	_check_geometry()
	var home := Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	for hid: String in CAPSULES:
		var ship := _launch(hid)
		ship.global_position = home
		_check_capsule(ship, hid)
		ship.global_position = Vector2(-5000.0, -5000.0)
		ship.alive = false
	for hid: String in CIRCLES:
		var ship := _launch(hid)
		ship.global_position = home
		_check_circle(ship, hid)
		ship.global_position = Vector2(-5000.0, -5000.0)
		ship.alive = false
	_check_mothership()
	_check_impact(home)
	print("capsule_check: %d failures" % failures)
	get_tree().quit()


## Count one failure and say what it was.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("capsule_check: FAIL %s" % what)


## A random point in a 1,200 by 1,200 box round the origin.
func _rand_point() -> Vector2:
	return Vector2(rng.randf_range(-600.0, 600.0), rng.randf_range(-600.0, 600.0))


## The geometry of Util.seg_capsule_t and Util.capsule_edge_dist.
func _check_geometry() -> void:
	var bad := 0
	# A capsule with no spine is the circle, exactly.
	for i in SEGMENTS:
		var a := _rand_point()
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 700.0)
		var c := _rand_point() * 0.4
		var r := rng.randf_range(20.0, 200.0)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		if Util.seg_capsule_t(a, b, c, dir, 0.0, r) != Util.seg_circle_t(a, b, c, r):
			bad += 1
		if absf(Util.capsule_edge_dist(a, c, dir, 0.0, r) - (a.distance_to(c) - r)) > 0.001:
			bad += 1
	_expect(bad == 0, "a capsule with no spine differs from the circle %d times" % bad)
	print("capsule_check: spine 0 equals the circle, %d segments, %d wrong" % [SEGMENTS, bad])
	# A real spine: the answer matches a slow march, and the entry point is on the edge.
	bad = 0
	var hits := 0
	for i in SEGMENTS:
		var half := rng.randf_range(10.0, 300.0)
		var r := rng.randf_range(20.0, 200.0)
		var c := _rand_point() * 0.4
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var a := _rand_point()
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 900.0)
		var t := Util.seg_capsule_t(a, b, c, dir, half, r)
		var ref := -1.0
		for k in MARCH + 1:
			var s := float(k) / float(MARCH)
			if Util.capsule_edge_dist(a.lerp(b, s), c, dir, half, r) <= 0.0:
				ref = s
				break
		if t >= 0.0:
			hits += 1
			var on_edge := absf(Util.capsule_edge_dist(a.lerp(b, t), c, dir, half, r))
			if t > 0.0 and on_edge > 0.05:
				bad += 1
			if ref >= 0.0 and (t > ref + 0.0001 or t < ref - 1.5 / float(MARCH)):
				bad += 1
		elif ref >= 0.0:
			bad += 1
	_expect(bad == 0, "the capsule test and the slow march differ %d times" % bad)
	_expect(hits > 20, "only %d of the random segments hit a capsule" % hits)
	print("capsule_check: spine tests, %d segments (%d hits), %d wrong" % [SEGMENTS, hits, bad])


## The probe spots of one capsule hull in the ship's own frame: [rim point,
## outward direction].
func _probes(ship: Ship) -> Array:
	var half := ship.spine_len * 0.5
	var r := ship.hit_r
	var off := ship.spine_off
	var diag := Vector2.from_angle(PI * 0.25)
	return [
		[Vector2(off + half + r, 0.0), Vector2.RIGHT],
		[Vector2(off - half - r, 0.0), Vector2.LEFT],
		[Vector2(off, r), Vector2.DOWN],
		[Vector2(off + half, 0.0) + diag * r, diag],
		[Vector2(off - half, 0.0) + Vector2(-diag.x, -diag.y) * r, Vector2(-diag.x, -diag.y)],
	]


## One capsule hull: the rim probes at 8 headings, the mounts, the reach.
func _check_capsule(ship: Ship, hid: String) -> void:
	var bad := 0
	var tried := 0
	_expect(ship.hit_r > 0.0 and ship.spine_len > 0.0, "%s has no capsule" % hid)
	for h in HEADINGS:
		ship.rotation = float(h) * TAU / float(HEADINGS)
		for pr: Array in _probes(ship):
			var rim: Vector2 = ship.global_position + (pr[0] as Vector2).rotated(ship.rotation)
			var n: Vector2 = (pr[1] as Vector2).rotated(ship.rotation)
			var out := rim + n * 40.0
			tried += 1
			if ship.hit_t(out, rim - n * RIM, 0.0) < 0.0:
				bad += 1
				print("capsule_check: %s heading %d: a line ending %s inside the rim missed" % [hid, h, RIM])
			if ship.hit_t(out, rim + n * RIM, 0.0) >= 0.0:
				bad += 1
				print("capsule_check: %s heading %d: a line ending %s outside the rim hit" % [hid, h, RIM])
	# The mounts all lie inside the capsule.
	var outside := 0
	for m: Dictionary in Ships.HULLS[hid]["mounts"]:
		var off: Vector2 = m["off"]
		if Util.capsule_edge_dist(off, Vector2(ship.spine_off, 0.0), Vector2.RIGHT, ship.spine_len * 0.5, ship.hit_r) > 0.0:
			outside += 1
	_expect(outside == 0, "%s has %d mounts outside its capsule" % [hid, outside])
	# The reach: the farthest point of the capsule from the centre.
	var want := absf(ship.spine_off) + ship.spine_len * 0.5 + ship.hit_r
	_expect(ship.hit_reach() == want, "%s reach %s, wanted %s" % [hid, ship.hit_reach(), want])
	ship.rotation = 0.0
	var tip := ship.global_position + Vector2(ship.spine_off + ship.spine_len * 0.5 + ship.hit_r, 0.0)
	_expect(absf(ship.edge_dist(tip)) < 0.001, "%s edge distance at the bow tip is %s" % [hid, ship.edge_dist(tip)])
	_expect(ship.edge_dist(ship.global_position) < 0.0, "%s centre is not inside" % hid)
	_expect(ship.radius == float(Ships.HULLS[hid]["radius"]), "%s body radius changed" % hid)
	failures += bad
	print("capsule_check: %s capsule hit_r %s spine %s off %s, %d probes, reach %s, %d wrong" % [hid, ship.hit_r, ship.spine_len, ship.spine_off, tried, ship.hit_reach(), bad])


## One circle hull: the old test, exactly.
func _check_circle(ship: Ship, hid: String) -> void:
	var bad := 0
	ship.rotation = 0.7
	for i in SEGMENTS:
		var a := ship.global_position + _rand_point() * 0.2
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 120.0)
		var pad := rng.randf_range(0.0, 6.0)
		if ship.hit_t(a, b, pad) != Util.seg_circle_t(a, b, ship.global_position, ship.hit_radius() + pad):
			bad += 1
		var p := ship.global_position + _rand_point() * 0.2
		if ship.edge_dist(p) != p.distance_to(ship.global_position) - ship.hit_radius():
			bad += 1
	_expect(ship.hit_r == 0.0 and ship.spine_off == 0.0, "%s has capsule numbers" % hid)
	_expect(ship.hit_reach() == ship.hit_radius(), "%s reach is not its hit radius" % hid)
	failures += bad
	print("capsule_check: %s circle, %d segments, %d wrong" % [hid, SEGMENTS, bad])


## The mothership: no capsule numbers on it, its own hull test untouched.
func _check_mothership() -> void:
	var ms := world.mothership(1)
	var bad := 0
	for i in SEGMENTS:
		var a := ms.global_position + _rand_point()
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 400.0)
		var pad := rng.randf_range(0.0, 6.0)
		if ms.hit_t(a, b, pad) != MothershipHull.hit_t(ms, a, b, pad):
			bad += 1
	_expect(ms.hit_r == 0.0 and ms.spine_off == 0.0, "the mothership has capsule numbers")
	_expect(ms.hit_reach() == ms.hit_radius(), "the mothership reach is not its hit radius")
	failures += bad
	print("capsule_check: mothership, %d segments, %d wrong" % [SEGMENTS, bad])


## Remember the note of every hit that is applied.
func _on_hit(_target: Node, info: RefCounted, _amount: float, _hull_dmg: float) -> void:
	last_note = info as DamageInfo


## Fly a bolt from `from` along `dir` until it hits something (at most 200
## ticks) and return its slot number; the note it made is in last_note.
func _fire_bolt(from: Vector2, dir: Vector2) -> int:
	last_note = null
	var proj := world.projectiles
	var i := proj.spawn(from, dir * 1000.0, 3.0, 40.0, Rules.W_BOLT, {"radius": 3.0}, null, null)
	for _t in 200:
		if proj.live[i] == 0:
			break
		proj._step(i, 0.016)
	return i


## The impact point of a hit on a capsule hull and on a circle hull, and the
## beam and the bolt reading the same point.
func _check_impact(home: Vector2) -> void:
	world.combat.emit_damage_events = true
	Events.damage_applied.connect(_on_hit)
	var proj := world.projectiles
	var bad := 0
	# The Battlecruiser, nose along +x; the bolt comes at its starboard flank, 200
	# units ahead of its centre, from a muzzle well ahead and out to the side.
	var bc := _launch("battlecruiser")
	bc.global_position = home
	bc.rotation = 0.0
	world.registry.rebuild_hashes()
	var flank := home + Vector2(200.0, 0.0)
	var muzzle := home + Vector2(900.0, 400.0)
	var aim := Vector2(200.0, bc.hit_r) - Vector2(900.0, 400.0)
	var i := _fire_bolt(muzzle, aim.normalized())
	var bolt_note := last_note
	_expect(bolt_note != null, "the bolt made no note")
	var bolt_zone := -1
	var bolt_section := -2
	if bolt_note != null:
		# The point one round radius off the hull's flank, where the padded shape is touched.
		_expect(bolt_note.impact.distance_to(proj.pos[i]) < 0.001, "the bolt's impact point %s is not its hit point %s" % [bolt_note.impact, proj.pos[i]])
		_expect(bolt_note.impact.distance_to(proj.prev[i]) > 1.0, "the bolt's impact point is a tick back")
		_expect(absf(bolt_note.impact.x - flank.x) < 15.0 and absf(bolt_note.impact.y - (home.y + bc.hit_r)) < 8.0, "the bolt's impact point %s is not on the flank" % bolt_note.impact)
		_expect(bolt_note.from_pos.distance_to(proj.prev[i]) < 0.001, "the bolt's from_pos moved")
		var raw := (bolt_note.impact_point() - bc.global_position).rotated(-bc.rotation)
		bolt_zone = ShieldZones.zone_for_local(ArmourSections.from_spine(raw, bc.spine_len, bc.spine_off))
		bolt_section = bc.armour.section_on_spine(raw, bc.spine_len, bc.spine_off)
		# 209 units ahead of the centre is the first fifth of the right side from the nose: its first section.
		_expect(bolt_section == bc.armour.zone_first[Rules.ZONE_RIGHT], "the flank hit landed on section %d, wanted the first right one %d" % [bolt_section, bc.armour.zone_first[Rules.ZONE_RIGHT]])
	# A beam from the same muzzle at the same spot.
	var shooter := _launch("scout", 0)
	shooter.global_position = Vector2(-5000.0, -5000.0)
	last_note = null
	world.combat.beam(shooter, muzzle, aim.normalized(), 900.0, 40.0, Rules.W_LANCE, false)
	var beam_note := last_note
	_expect(beam_note != null, "the beam made no note")
	if beam_note != null and bolt_note != null:
		_expect(beam_note.from_pos.distance_to(muzzle) < 0.001, "the beam's from_pos is not the muzzle")
		_expect(beam_note.impact.distance_to(bolt_note.impact) < 8.0, "the beam's impact point %s and the bolt's %s differ" % [beam_note.impact, bolt_note.impact])
		var raw := (beam_note.impact_point() - bc.global_position).rotated(-bc.rotation)
		var beam_zone := ShieldZones.zone_for_local(ArmourSections.from_spine(raw, bc.spine_len, bc.spine_off))
		var beam_section := bc.armour.section_on_spine(raw, bc.spine_len, bc.spine_off)
		_expect(beam_zone == bolt_zone, "the beam's zone %d and the bolt's %d differ" % [beam_zone, bolt_zone])
		_expect(beam_section == bolt_section, "the beam's section %d and the bolt's %d differ" % [beam_section, bolt_section])
		# The muzzle lies ahead of the hull: by bearing the beam would have been a front hit.
		_expect(ShieldZones.zone_for_local((muzzle - bc.global_position).rotated(-bc.rotation)) == Rules.ZONE_FRONT, "the muzzle is not in the front zone by bearing")
		_expect(bolt_zone == Rules.ZONE_RIGHT, "the flank hit is in zone %d, wanted the right zone" % bolt_zone)
	bc.global_position = Vector2(-5000.0, -5000.0)
	bc.alive = false
	# The same bolt at a circle hull: the old note (the point one tick before).
	var lg := _launch("logistics")
	lg.global_position = home
	lg.rotation = 0.0
	world.registry.rebuild_hashes()
	i = _fire_bolt(home + Vector2(300.0, 100.0), (Vector2(0.0, 0.0) - Vector2(300.0, 100.0)).normalized())
	if last_note == null:
		bad += 1
		print("capsule_check: the bolt at the circle hull made no note")
	else:
		_expect(last_note.impact == last_note.from_pos, "a circle hull's impact point moved off from_pos")
		_expect(last_note.from_pos == proj.prev[i], "a circle hull's from_pos is not the round's last position")
	lg.global_position = Vector2(-5000.0, -5000.0)
	lg.alive = false
	shooter.alive = false
	Events.damage_applied.disconnect(_on_hit)
	world.combat.emit_damage_events = false
	failures += bad
	print("capsule_check: impact point, bolt zone %d section %d, %d wrong" % [bolt_zone, bolt_section, bad])


## Launch a pilot ship of hull `hid` for team `team` (a pilot named after the
## hull), standing still.
func _launch(hid: String, team := 1) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s
