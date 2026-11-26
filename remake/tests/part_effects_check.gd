extends Node
## WHAT THIS IS: the check of what the ship parts do (item 3 of the parts build): a gun that is offline
## fires nothing and a hurt one fires at half rate, the two engine pods set the ship's push, top speed and
## turning by the stepped table, unequal pods pull the ship toward the weaker one, the sensor slows the
## turrets, and a computer captain whose ship has a pod out starts no retreat, shopping trip or camp
## retreat for a while. It prints one line per case ("PASS name" or "FAIL name: what") and then
## "part_effects_check: N checks, K failures" (and, only when K is 0, "part_effects_check: 0 failures").
##
## HOW IT WORKS: it builds the normal match, freezes it and launches real Battlecruisers with empty
## shields. A part's state is set through its health (WORKING at full, DEGRADED under half, OFF at 0 and
## offline), then the ship works its numbers out again (recompute_stats) and the real functions run: the
## gun loop (Ship._weapons), the flight functions and a real PilotAI thinking once. Shots are counted by
## watching each gun's cooldown. A ship made with the switch off is the control. It loads the new classes
## only through ResourceLoader and calls them with no static type, so on a build without them it prints
## FAIL lines and still ends.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=part_effects_check
##
## WHO USES IT: main.gd loads it for --test=part_effects_check; run_checks runs it. It only hurts ships of
## a frozen match that is thrown away.

## Where the new class lives.
const SYSTEMS_PATH := "res://scripts/entities/ship_systems.gd"
## The length of a tick (seconds).
const DT := 1.0 / 60.0

## The ship's home spot (set by setup()).
var _home := Vector2.ZERO
## The running match (set by setup()).
var world: World
## How many checks were made.
var checks := 0
## How many went wrong.
var failures := 0


## main.gd calls this once, right after the World is built. Freeze the match and start the run
## on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Count one check, say what went wrong when `ok` is false, and print the PASS line of a good one.
func _expect(ok: bool, case_name: String, what: String = "") -> void:
	checks += 1
	if ok:
		print("part_effects_check: PASS %s" % case_name)
	else:
		failures += 1
		print("part_effects_check: FAIL %s: %s" % [case_name, what])


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var has_class := ResourceLoader.exists(SYSTEMS_PATH)
	_expect(has_class, "ShipSystems is in this build", "ship_systems.gd is missing")
	_case_switch_off()
	if has_class:
		_case_guns()
		_case_beam()
		_case_pods()
		_case_pull()
		_case_sensor()
		_case_module_mount()
		_case_hold()
	print("part_effects_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("part_effects_check: 0 failures")
	get_tree().quit()


## Launch a pilot ship of hull `hid` for team 1 with the parts switch set to `mode` ("on" or "off") at the
## ship's making, standing at home facing east with empty shields and a full battery.
func _ship(hid: String, mode: String) -> Ship:
	var was = Game.options.get("parts", null)
	Game.options["parts"] = mode
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	for z in 4:
		s.shields.values[z] = 0.0
	if was == null:
		Game.options.erase("parts")
	else:
		Game.options["parts"] = was
	world.registry.rebuild_hashes()
	return s


## Put ship `s` away and make it dead.
func _retire(s: Ship) -> void:
	s.global_position = Vector2(-5000.0, -5000.0)
	s.alive = false


## The index of the part with id `id` in ship `s`'s parts.
func _idx(s: Ship, id: String) -> int:
	return int((s.get("parts")).index_of(id))


## Set part `i` of ship `s` to state `st` (0 WORKING, 1 DEGRADED, 2 OFF) and work the ship's numbers out again.
func _put_state(s: Ship, i: int, st: int) -> void:
	var p = s.get("parts")
	var full := int((p.rows[i] as Dictionary)["hp_max"])
	if st == 0:
		p.hp[i] = full
		p.offline[i] = 0
	elif st == 1:
		p.hp[i] = full / 4
		p.offline[i] = 0
	else:
		p.hp[i] = 0
		p.offline[i] = 1
		p.since[i] = int(p.tick_n)
	s.recompute_stats()


## Run ship `s`'s guns for `ticks` ticks with the trigger held and the aim straight ahead (out along its own
## side for a broadside battery gun); returns how many
## shots mount `mi` fired (each shot raises its cooldown) and whether its beam was ever firing.
func _fire(s: Ship, mi: int, ticks: int) -> Array:
	var m: WeaponMount = s.mounts[mi]
	s.controls.fire = true
	# A broadside battery gun follows only a reticle inside its own arc, which faces the beam: aim out along its side.
	s.controls.aim_point = _home + (Vector2(m.offset.x, signf(m.offset.y) * 3000.0) if m.battery else Vector2(3000.0, 0.0))
	var shots := 0
	var beam := false
	for _t in ticks:
		s.energy.value = s.energy.max_value
		var before := m.cd
		s._weapons(DT)
		if m.cd > before:
			shots += 1
		beam = beam or m.beam_firing
	s.controls.fire = false
	return [shots, beam]


## Gun states: an offline gun fires nothing while a working one does; a hurt gun fires at half rate.
func _case_guns() -> void:
	var work := _ship("battlecruiser", "on")
	var off := _ship("battlecruiser", "on")
	var hurt := _ship("battlecruiser", "on")
	# The heavy cannon: mount 2 of the Battlecruiser's row (found by weapon, not by a number).
	var mi := 0
	for k in work.mounts.size():
		if (work.mounts[k] as WeaponMount).weapon_id == "heavy_cannon":
			mi = k
	var part := int((work.get("parts")).mount_part[mi])
	_put_state(off, part, 2)
	_put_state(hurt, part, 1)
	var n_work := int(_fire(work, mi, 300)[0])
	var n_off := int(_fire(off, mi, 300)[0])
	_expect(n_work >= 1 and n_off == 0, "an offline gun fires nothing in 5 s while a working one fires %d" % n_work, "working %d, offline %d" % [n_work, n_off])
	var full10 := int(_fire(work, mi, 600)[0])
	var half10 := int(_fire(hurt, mi, 600)[0])
	_expect(absf(float(full10) * 0.5 - float(half10)) <= 1.0 and half10 >= 1 and half10 < full10, "a hurt gun fires at half rate (%d shots in 10 s against %d)" % [half10, full10], "hurt %d full %d" % [half10, full10])
	# Back to working: it fires again.
	_put_state(off, part, 0)
	var n_back := int(_fire(off, mi, 300)[0])
	_expect(n_back >= 1, "a gun that is working again fires again", "shots %d" % n_back)
	_retire(work)
	_retire(off)
	_retire(hurt)


## A beam gun stops while it is offline.
func _case_beam() -> void:
	var work := _ship("battlecruiser", "on")
	var off := _ship("battlecruiser", "on")
	var mi := 0
	for k in work.mounts.size():
		if (work.mounts[k] as WeaponMount).is_beam:
			mi = k
			break
	var part := int((work.get("parts")).mount_part[mi])
	_put_state(off, part, 2)
	var w := _fire(work, mi, 600)
	var o := _fire(off, mi, 600)
	var m: WeaponMount = off.mounts[mi]
	_expect(bool(w[1]) and not bool(o[1]) and m.beam_on == 0.0 and not m.beam_firing, "a beam gun fires its burst while working and never while offline", "working %s offline %s" % [str(w[1]), str(o[1])])
	_retire(work)
	_retire(off)


## The engine pods set the push, the top speed and the turning by the stepped table; reverse and the side
## thrusters are not pods.
func _case_pods() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var a0 := s.f_accel
	var v0 := s.f_max
	var t0 := s.f_turn
	var r0 := s.f_reverse
	var st0 := s.f_strafe
	var pl := _idx(s, "pod_l")
	var pr := _idx(s, "pod_r")
	# Each row: left state, right state, thrust factor, speed and turn factor.
	var table := [[0, 0, 1.0, 1.0, "both working"], [2, 0, 0.6, 0.8, "one pod off"], [0, 2, 0.6, 0.8, "the other pod off"],
		[2, 2, 0.2, 0.6, "both pods off"], [1, 0, 0.85, 0.925, "one pod degraded"], [1, 1, 0.7, 0.85, "both degraded"], [2, 1, 0.45, 0.725, "one off, one degraded"]]
	for row in table:
		_put_state(s, pl, int(row[0]))
		_put_state(s, pr, int(row[1]))
		var tf := float(row[2])
		var vf := float(row[3])
		var ok := absf(s.f_accel - a0 * tf) <= 0.0001 * a0 and absf(s.f_max - v0 * vf) <= 0.0001 * v0 and absf(s.f_turn - t0 * vf) <= 0.0001 * t0
		_expect(ok, "pods: %s gives push x%s, top speed and turning x%s" % [row[4], str(tf), str(vf)], "accel %f of %f, max %f of %f, turn %f of %f" % [s.f_accel, a0, s.f_max, v0, s.f_turn, t0])
		_expect(s.f_reverse == r0 and s.f_strafe == st0, "pods: reverse and side thrust unchanged with %s" % row[4], "reverse %f vs %f, strafe %f vs %f" % [s.f_reverse, r0, s.f_strafe, st0])
	# A pod's state change dirties the stats (the ship works its numbers out again by itself).
	_put_state(s, pl, 0)
	_put_state(s, pr, 0)
	s.stats_dirty = false
	p.hp[pl] = 0
	p.offline[pl] = 1
	p.since[pl] = int(p.tick_n)
	p.dirty = true
	s._timers(DT)
	_expect(s.stats_dirty, "a change of pod state sets stats_dirty", "not set")
	_retire(s)


## The pull aside: toward the weaker pod, never above 30 percent of the turn rate, none with equal pods or no throttle;
## and in the real flight the nose swings that way.
func _case_pull() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var pl := _idx(s, "pod_l")
	var pr := _idx(s, "pod_r")
	var turn := s.f_turn
	_put_state(s, pl, 0)
	_put_state(s, pr, 0)
	_expect(p.pull_aside(turn, 1.0) == 0.0, "no pull with equal working pods", "pull %f" % float(p.pull_aside(turn, 1.0)))
	_put_state(s, pl, 2)
	_put_state(s, pr, 2)
	_expect(p.pull_aside(turn, 1.0) == 0.0, "no pull with both pods off", "pull %f" % float(p.pull_aside(turn, 1.0)))
	_put_state(s, pl, 2)
	_put_state(s, pr, 0)
	var left := float(p.pull_aside(turn, 1.0))
	_put_state(s, pl, 0)
	_put_state(s, pr, 2)
	var right := float(p.pull_aside(turn, 1.0))
	_expect(left < 0.0 and right > 0.0, "the pull is toward the weaker pod's side", "left %f right %f" % [left, right])
	_expect(absf(left) <= 0.30 * turn and absf(right) <= 0.30 * turn and absf(left) == absf(right), "the pull never exceeds 30 percent of the turn rate", "pull %f of turn %f" % [left, turn])
	_expect(p.pull_aside(turn, 0.0) == 0.0, "no pull at zero throttle", "pull at 0 throttle")
	# The real flight: one tick of full ahead with the nose told to hold the heading it has.
	var rots := []
	for case_pair in [[0, 0], [2, 0], [0, 2]]:
		_put_state(s, pl, int(case_pair[0]))
		_put_state(s, pr, int(case_pair[1]))
		s.global_position = _home
		s.rotation = 0.0
		s.velocity = Vector2.ZERO
		s.set("ang_vel", 0.0)
		s.set("swivel", 0.0)
		s.throttle = 0.0
		s.controls.forward = 1.0
		s.controls.strafe = 0.0
		s.controls.face_point = _home + Vector2(1000000.0, 0.0)
		ShipFlight.fly(s, DT)
		rots.append(s.rotation)
	_expect(absf(float(rots[0])) < 0.000001 and float(rots[1]) < 0.0 and float(rots[2]) > 0.0, "in flight the nose swings toward the weaker pod (equal %g, left out %g, right out %g)" % [rots[0], rots[1], rots[2]], "equal %g, left out %g, right out %g" % [rots[0], rots[1], rots[2]])
	_retire(s)


## The sensor slows the turrets' swing: 0.75 degraded, 0.5 offline, and a turret really turns that much slower.
func _case_sensor() -> void:
	var s := _ship("battlecruiser", "on")
	var si := _idx(s, "sensor")
	var mi := 0
	for k in s.mounts.size():
		if (s.mounts[k] as WeaponMount).weapon_id == "heavy_cannon":
			mi = k
	var m: WeaponMount = s.mounts[mi]
	var swings := []
	for st in 3:
		_put_state(s, si, st)
		m.angle = 0.0
		s.controls.fire = false
		s.controls.aim_point = _home + Vector2(0.0, 3000.0)
		for _t in 30:
			s._weapons(DT)
		swings.append(m.angle)
		_expect(float(m.get("slew_mult")) == [1.0, 0.75, 0.5][st], "the sensor in state %d sets the swing factor %s" % [st, str([1.0, 0.75, 0.5][st])], "slew_mult %s" % str(m.get("slew_mult")))
	_expect(absf(float(swings[1]) / float(swings[0]) - 0.75) < 0.02 and absf(float(swings[2]) / float(swings[0]) - 0.5) < 0.02, "the turret really swings at 0.75 and 0.5 of its rate", "swings %s" % str(swings))
	_retire(s)


## A gun a module added (a mount past the hull's own) ignores the parts.
func _case_module_mount() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	for i in int(p.count()):
		_put_state(s, i, 2)
	var extra := WeaponMount.new(s, "heavy_cannon", "turret", Vector2(0.0, 0.0), 150.0)
	s.mounts.append(extra)
	var shots_extra := 0
	var shots_base := 0
	s.controls.fire = true
	s.controls.aim_point = _home + Vector2(3000.0, 0.0)
	for _t in 300:
		s.energy.value = s.energy.max_value
		var before := extra.cd
		var base_cds := []
		for k in s.base_mounts:
			base_cds.append((s.mounts[k] as WeaponMount).cd)
		s._weapons(DT)
		if extra.cd > before:
			shots_extra += 1
		for k in s.base_mounts:
			if (s.mounts[k] as WeaponMount).cd > float(base_cds[k]):
				shots_base += 1
	s.controls.fire = false
	_expect(shots_extra >= 1 and shots_base == 0, "a module-added gun fires while every hull gun is offline", "extra %d base %d" % [shots_extra, shots_base])
	_retire(s)


## With the switch off the numbers are the ones a ship with working parts has, and it has no parts.
func _case_switch_off() -> void:
	var off := _ship("battlecruiser", "off")
	var on := _ship("battlecruiser", "on")
	_expect(off.get("parts") == null, "with the switch off a ship has no parts", "has parts")
	var same := off.f_accel == on.f_accel and off.f_max == on.f_max and off.f_turn == on.f_turn and off.f_reverse == on.f_reverse and off.f_strafe == on.f_strafe
	_expect(same, "with the switch off every flight number equals a ship with working parts (and so the base)", "accel %f vs %f, max %f vs %f, turn %f vs %f" % [off.f_accel, on.f_accel, off.f_max, on.f_max, off.f_turn, on.f_turn])
	# The old rows: with the switch off the guns' rate multiplier and the swing are untouched.
	var untouched := true
	for m: WeaponMount in off.mounts:
		untouched = untouched and float(m.get("slew_mult") if m.get("slew_mult") != null else 1.0) == 1.0
	_expect(untouched, "with the switch off no gun's swing is changed", "a swing factor moved")
	_retire(off)
	_retire(on)


## The captain's hold, one case for each of the three paths: held while a pod is offline inside 3600 ticks,
## released after them and when the pod is back. A control ship with its pods working takes each path.
func _case_hold() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var pl := _idx(s, "pod_l")
	# Path 1: the retreat decision (a hull under 35 percent).
	s.hull = s.hull_max * 0.30
	var brain := PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.state = "lane"
	brain._think(s)
	_expect(brain.state == "retreat", "control: a Battlecruiser under 35 percent hull starts a retreat", "state %s" % brain.state)
	_put_state(s, pl, 2)
	brain = PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.state = "lane"
	brain._think(s)
	_expect(brain.state != "retreat", "a pod out holds the retreat decision", "state %s" % brain.state)
	# A retreat already running is not touched.
	brain.state = "retreat"
	brain._think(s)
	_expect(brain.state == "retreat", "a retreat already running is not touched by the hold", "state %s" % brain.state)
	# Released after 3600 ticks, and when the pod is back.
	p.since[pl] = int(p.tick_n) - 3700
	brain = PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.state = "lane"
	brain._think(s)
	_expect(brain.state == "retreat", "the hold is released after 3600 ticks with the pod still out", "state %s" % brain.state)
	_put_state(s, pl, 0)
	brain = PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.state = "lane"
	brain._think(s)
	_expect(brain.state == "retreat", "the hold is released when the pod is back", "state %s" % brain.state)
	# Path 2: the shopping trip. A ship with full hull near its mothership and plenty of credits wants to shop.
	s.hull = s.hull_max
	var ms := world.mothership(1)
	if ms != null:
		s.global_position = ms.global_position + Vector2(2500.0, 0.0)
	s.profile.credits = 1000000.0
	brain = PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.launched_at = -1000.0
	brain.state = "lane"
	world.time = 5000.0
	brain._think(s)
	var control_trip := brain.state == "home"
	_expect(control_trip, "control: a Battlecruiser with a big bank and nothing near starts a shopping trip", "state %s" % brain.state)
	_put_state(s, pl, 2)
	brain = PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.launched_at = -1000.0
	brain.state = "lane"
	brain._think(s)
	_expect(brain.state != "home", "a pod out holds the shopping trip", "state %s" % brain.state)
	p.since[pl] = int(p.tick_n) - 3700
	brain = PilotAI.new(world, s.profile)
	brain.opening_done = true
	brain.launched_at = -1000.0
	brain.state = "lane"
	brain._think(s)
	_expect(brain.state == "home", "the shopping hold is released after 3600 ticks", "state %s" % brain.state)
	_put_state(s, pl, 0)
	world.time = 0.0
	_retire(s)
	# Path 3: the camp retreat (a small ship's job: a Fighter is given the Battlecruiser's parts to reach it).
	var donor := _ship("battlecruiser", "on")
	var f := _ship("fighter", "off")
	f.global_position = _home
	f.hull = f.hull_max * 0.5
	brain = PilotAI.new(world, f.profile)
	brain.opening_done = true
	brain.camp = null
	brain.state = "jungle"
	brain.goals.think_jungle(f)
	_expect(brain.state == "retreat", "control: a ship under 60 percent hull with no camp starts a camp retreat", "state %s" % brain.state)
	f.set("parts", donor.get("parts"))
	_put_state(donor, _idx(donor, "pod_r"), 2)
	brain = PilotAI.new(world, f.profile)
	brain.opening_done = true
	brain.camp = null
	brain.state = "jungle"
	brain.goals.think_jungle(f)
	_expect(brain.state != "retreat", "a pod out holds the camp retreat", "state %s" % brain.state)
	var dp = donor.get("parts")
	dp.since[_idx(donor, "pod_r")] = int(dp.tick_n) - 3700
	brain = PilotAI.new(world, f.profile)
	brain.opening_done = true
	brain.camp = null
	brain.state = "jungle"
	brain.goals.think_jungle(f)
	_expect(brain.state == "retreat", "the camp hold is released after 3600 ticks", "state %s" % brain.state)
	_put_state(donor, _idx(donor, "pod_r"), 0)
	f.set("parts", null)
	_retire(donor)
	_retire(f)
