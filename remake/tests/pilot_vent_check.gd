extends Node
## WHAT THIS IS: the check of the computer pilots' Vent: when they press it, and that they
## prize an enemy that cannot fire. It prints one line per case and then
## "pilot_vent_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it freezes the match, launches real ships and asks PilotVent.wants_vent()
## directly (no pilot brain is needed for that), then makes one real brain (PilotAI) think
## once to show that the brain really presses Vent. It checks:
##   - (a) below the skill gate (and exactly at it), with a light battery load, or with an
##     enemy ship inside the safe range, a pilot never vents; above the gate, with a loaded
##     battery and nobody near, it does;
##   - (b) never in a lockout or in a Vent already, and never with a battery that cannot
##     refill;
##   - (c) the Vent a pilot starts ends by itself with a clear battery;
##   - (d) a real PilotAI ship that thinks once sets the Vent edge (the brain calls PilotVent);
##   - (e) an overloaded enemy, or a venting one, beats the same enemy that is not by the
##     row's target_bonus (within 2 units) when a pilot picks a target; the measure is never
##     clamped (the scanned enemy alone is the pick at every scan step, and no reading touches
##     the scan's ends);
##   - (f) a pilot with no one near and a clear battery does not vent (nothing to do).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=pilot_vent_check
##
## WHO USES IT: main.gd loads it for --test=pilot_vent_check; run_checks runs it. It changes
## only units of a frozen match that is thrown away.

## One physics tick, in seconds.
const DT := 1.0 / 60.0
## How far (world units) the chosen spot must be from every enemy unit.
const QUIET_R := 3600.0
## Case (e): how far (world units) the enemy that is not scanned stands from the pilot.
const SCAN_BASE := 600.0
## Case (e): how many units nearer than SCAN_BASE the scanned enemy starts.
const SCAN_BACK := 450
## Case (e): how many units farther than SCAN_BASE the scanned enemy ends. The bonus (300) puts the end of its
## winning range 300 past the base, far inside this.
const SCAN_FWD := 450
## The running match (set by setup()).
var world: World
## Where the ships stand: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## How many things have gone wrong so far.
var failures := 0
## The one rules row every pilot uses.
var _row: Dictionary = PilotVentRules.DEFAULT


## main.gd calls this once, right after the World is built. Freeze the match and
## start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_home = _quiet_spot()
	_case_gate()
	_case_refused()
	_case_ends()
	_case_brain()
	_case_target()
	_case_idle()
	print("pilot_vent_check: %d failures" % failures)
	get_tree().quit()


## A point on the map with no enemy ship, turret or minion of team 1 within QUIET_R of it (the
## default home spot has the lane's own units about). Falls back to the home spot.
func _quiet_spot() -> Vector2:
	var pred := func(u: Unit) -> bool: return u.kind == Unit.K_SHIP or u.kind == Unit.K_TURRET or u.kind == Unit.K_MINION
	for gy in range(-8, 9):
		for gx in range(-8, 9):
			var p := Vector2(MapLayout.CX + float(gx) * 1500.0, MapLayout.CY + float(gy) * 1500.0)
			if world.nearest_enemy(p, QUIET_R, 1, pred) == null and _clear_dir(p) != Vector2.ZERO:
				return p
	return _home


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("pilot_vent_check: FAIL %s" % what)


## Launch a ship of hull `hid` for `team` and stand it still at `at`, facing east, with its
## shields and battery full and not just hit.
func _ship(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 80 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = at
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.shields.fill()
	s.shields.since_hit = 999.0
	s.fill_energy()
	s.visible_mask = 0xFF
	world.registry.rebuild_hashes()
	return s


## A team 1 Fighter at home with `hard` hard energy and `value` soft energy.
func _loaded(hard: float, value: float) -> Ship:
	var s := _ship("fighter", 1, _home)
	s.energy.hard = hard
	s.energy.value = value
	return s


## Put unit `u` away in a far corner and make it dead.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()


## Step `s` for `n` ticks of one sixtieth of a second.
func _tick(s: Ship, n: int = 1) -> void:
	for _i in n:
		world.time += DT
		s.sim_update(DT)


## (a) The skill gate, the load gate and the safe range.
func _case_gate() -> void:
	var s := _loaded(30.0, 30.0)
	_expect(s.energy.load_frac() >= float(_row["vent_load"]), "(a) the setup is not loaded enough (%s)" % s.energy.load_frac())
	_expect(PilotVent.wants_vent(s, world, 0.9, _row), "(a) a skilled pilot with a loaded battery and nobody near did not vent")
	_expect(not PilotVent.wants_vent(s, world, 0.5, _row), "(a) a pilot below the skill gate vented")
	_expect(not PilotVent.wants_vent(s, world, float(_row["vent_skill"]), _row), "(a) a pilot exactly at the skill gate vented")
	var light := _loaded(10.0, 60.0)
	_expect(light.energy.load_frac() < float(_row["vent_load"]), "(a) the light setup is not light (%s)" % light.energy.load_frac())
	_expect(not PilotVent.wants_vent(light, world, 0.9, _row), "(a) a pilot with a light load vented")
	var edge := _loaded(0.0, 100.0 - 100.0 * float(_row["vent_load"]) - 0.01)
	_expect(edge.energy.load_frac() > float(_row["vent_load"]) - 1.0e-6, "(a) the edge setup is not at the load line")
	_expect(PilotVent.wants_vent(edge, world, 0.9, _row), "(a) a pilot at the load line did not vent")
	# An enemy ship inside the safe range stops it; outside it, it does not.
	var near := _ship("fighter", 0, _home + Vector2(0.0, float(_row["safe_range"]) - 100.0))
	_expect(not PilotVent.wants_vent(s, world, 0.9, _row), "(a) a pilot vented with an enemy ship inside the safe range")
	near.global_position = _home + Vector2(0.0, float(_row["safe_range"]) + 100.0)
	world.registry.rebuild_hashes()
	_expect(PilotVent.wants_vent(s, world, 0.9, _row), "(a) a pilot did not vent with the enemy just outside the safe range")
	print("pilot_vent_check: (a) skill 0.9 vents (0.5 and exactly %.2f do not); a light load does not; an enemy inside %.0f stops it, outside does not" % [float(_row["vent_skill"]), float(_row["safe_range"])])
	_put(s)
	_put(light)
	_put(edge)
	_put(near)


## (b) Never in a lockout, in a Vent, or with a battery that cannot refill.
func _case_refused() -> void:
	var s := _loaded(30.0, 30.0)
	s.overload_left = 2.0
	_expect(not PilotVent.wants_vent(s, world, 0.9, _row), "(b) a pilot vented during a lockout")
	s.overload_left = 0.0
	s.venting = true
	_expect(not PilotVent.wants_vent(s, world, 0.9, _row), "(b) a pilot vented during a Vent")
	s.venting = false
	s.energy.regen = 0.0
	_expect(not PilotVent.wants_vent(s, world, 0.9, _row), "(b) a pilot vented with a battery that cannot refill")
	print("pilot_vent_check: (b) no Vent in a lockout, in a Vent, or with no regeneration")
	_put(s)


## (c) The Vent a pilot starts ends by itself with a clear battery.
func _case_ends() -> void:
	var s := _loaded(40.0, 20.0)
	s.controls.vent = PilotVent.wants_vent(s, world, 0.9, _row)
	_expect(s.controls.vent, "(c) the setup did not ask for a Vent")
	_tick(s)
	_expect(s.venting, "(c) the ship did not start the Vent")
	var ticks := 1
	while s.venting and ticks < 3000:
		_tick(s)
		ticks += 1
	_expect(not s.venting and s.energy.hard <= 0.0 and s.energy.value >= s.energy.max_value, "(c) the Vent did not end clear after %d ticks (hard %s, soft %s)" % [ticks, s.energy.hard, s.energy.value])
	_expect(not PilotVent.wants_vent(s, world, 0.9, _row), "(c) a pilot with a clear battery wants another Vent")
	print("pilot_vent_check: (c) a pilot's Vent from 40 hard and 20 soft ended clear after %d ticks (%.2f s); it asks for none after" % [ticks, float(ticks) * DT])
	_put(s)


## (d) A real brain that thinks once presses Vent.
func _case_brain() -> void:
	var s := _loaded(40.0, 20.0)
	var brain := PilotAI.new(world, s.profile)
	brain.skill = 0.9
	s.controls.vent = false
	brain._think(s)
	_expect(s.controls.vent, "(d) a PilotAI think did not set the vent edge on a loaded ship with nobody near")
	var q := _ship("fighter", 1, _home + Vector2(400.0, 0.0))
	var brain_q := PilotAI.new(world, q.profile)
	brain_q.skill = 0.3
	q.energy.hard = 40.0
	q.energy.value = 20.0
	q.controls.vent = false
	brain_q._think(q)
	_expect(not q.controls.vent, "(d) an unskilled PilotAI vented")
	print("pilot_vent_check: (d) a PilotAI of skill 0.9 set the vent edge in one think; one of skill 0.3 did not")
	_put(s)
	_put(q)


## A direction from `from` along which no rock stands within 1,700 units, or Vector2.ZERO when every direction has one (a rock between a pilot
## and an enemy makes the enemy score worse, which would hide the bonus this case measures).
func _clear_dir(from: Vector2) -> Vector2:
	for i in 24:
		var d := Vector2.from_angle(float(i) * TAU / 24.0)
		if not world.asteroids.segment_blocked(from, from + d * 1700.0):
			return d
	return Vector2.ZERO


## The target the pilot brain `brain` picks for ship `me` within `r`, taken from a brain with no
## current target (the one it is shooting would count as better and hide the bonus).
func _pick(brain: PilotAI, me: Ship, r: float) -> Unit:
	brain.target = null
	brain.lock_target = null
	return brain.targeting.pick_target(me, r)


## Where enemy b stands for scan step `step`: SCAN_BASE plus the step units from the pilot me, on the line dir.
func _scan_put(me: Ship, b: Ship, dir: Vector2, step: int) -> void:
	b.global_position = me.global_position + dir * (SCAN_BASE + float(step))
	world.registry.rebuild_hashes()


## How many units farther than the other enemy (which stands SCAN_BASE from the pilot me, on the line dir) b can stand
## and still be the pilot's pick: scanned from SCAN_BACK nearer to SCAN_FWD farther, the last step where b wins.
func _slide_limit(brain: PilotAI, me: Ship, b: Ship, dir: Vector2, r: float) -> int:
	var last_win := -9999
	for step in range(-SCAN_BACK, SCAN_FWD + 1):
		_scan_put(me, b, dir, step)
		if _pick(brain, me, r) == b:
			last_win = step
	return last_win


## Proof that the scan is never clamped: with the other enemy parked out of reach, b alone is the pick at every scan
## step (a rock, a turret or anything else that hid b at some distance shows here). Returns the number of steps where
## it was not, and writes the first such step into first_miss[0].
func _alone_misses(brain: PilotAI, me: Ship, b: Ship, dir: Vector2, r: float, first_miss: Array) -> int:
	var misses := 0
	first_miss[0] = 9999
	for step in range(-SCAN_BACK, SCAN_FWD + 1):
		_scan_put(me, b, dir, step)
		if _pick(brain, me, r) != b:
			misses += 1
			first_miss[0] = mini(int(first_miss[0]), step)
	return misses


## (e) An overloaded or venting enemy beats the same enemy that is not by exactly target_bonus.
## The two enemies stand on one line from the pilot, so a rock or anything else treats them alike. The scan is
## unsaturated: enemy a stands SCAN_BASE (600) from the pilot, so b wins out to about 600 plus the bonus (900), a
## distance where b alone is the pick at every step (proved first), and a reading cannot run into the scan's end.
func _case_target() -> void:
	var me := _ship("fighter", 1, _home)
	var brain := PilotAI.new(world, me.profile)
	brain.state = "lane"
	var bonus := float(_row["target_bonus"])
	var dir := _clear_dir(_home)
	var far := Vector2(-5000.0, -5000.0)
	var a := _ship("fighter", 0, far)
	var b := _ship("fighter", 0, far)
	var r := 1600.0
	# Proof 1: with a out of reach, b alone is picked at every step: plain, overloaded and venting.
	var first: Array = [0]
	var miss_plain := _alone_misses(brain, me, b, dir, r, first)
	var first_plain := int(first[0])
	b.overload_left = 4.0
	var miss_over := _alone_misses(brain, me, b, dir, r, first)
	b.overload_left = 0.0
	b.venting = true
	var miss_vent := _alone_misses(brain, me, b, dir, r, first)
	b.venting = false
	_expect(miss_plain == 0 and miss_over == 0 and miss_vent == 0, "(e) b alone was not picked at every scan step (misses %d, %d, %d; the first plain miss at step %d)" % [miss_plain, miss_over, miss_vent, first_plain])
	# Proof 2: a stands in. How much farther than a can b stand and still be picked: plain, overloaded, venting.
	a.global_position = me.global_position + dir * SCAN_BASE
	world.registry.rebuild_hashes()
	var plain := _slide_limit(brain, me, b, dir, r)
	b.overload_left = 4.0
	var over := _slide_limit(brain, me, b, dir, r)
	b.overload_left = 0.0
	b.venting = true
	var vent := _slide_limit(brain, me, b, dir, r)
	b.venting = false
	_expect(plain > -SCAN_BACK and over > -SCAN_BACK and vent > -SCAN_BACK, "(e) the other enemy was never picked (%d, %d, %d)" % [plain, over, vent])
	_expect(plain < SCAN_FWD and over < SCAN_FWD and vent < SCAN_FWD, "(e) a reading ran into the scan's far end (%d, %d, %d of %d): the scan is clamped" % [plain, over, vent, SCAN_FWD])
	_expect(absi(over - plain - int(bonus)) <= 2, "(e) the overload moved the winning distance from %d to %d, not by the bonus %s (within 2)" % [plain, over, bonus])
	_expect(absi(vent - plain - int(bonus)) <= 2, "(e) the Vent moved the winning distance from %d to %d, not by the bonus %s (within 2)" % [plain, vent, bonus])
	print("pilot_vent_check: (e) b alone is picked at all %d steps; next to a it wins up to %d farther; %d when overloaded, %d when venting: the bonus is %.0f" % [SCAN_BACK + SCAN_FWD + 1, plain, over, vent, bonus])
	_put(me)
	_put(a)
	_put(b)

## (f) A clear battery with nobody near: nothing to vent.
func _case_idle() -> void:
	var s := _ship("fighter", 1, _home)
	_expect(s.energy.load_frac() == 0.0, "(f) a fresh ship's battery is not clear (%s)" % s.energy.load_frac())
	_expect(not PilotVent.wants_vent(s, world, 0.9, _row), "(f) a pilot with a clear battery wanted to vent")
	print("pilot_vent_check: (f) a clear battery never asks for a Vent")
	_put(s)
