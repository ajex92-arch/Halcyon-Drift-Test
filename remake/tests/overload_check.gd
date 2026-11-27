extends Node
## WHAT THIS IS: the check of hard energy and the overload lockout. It prints one line per
## case and then "overload_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it freezes the match, launches real ships, sends hits through
## Unit.take_hit() and then steps ONE ship tick (Ship.sim_update()) before it reads, because
## the battery moves in the ship's own tick. It checks:
##   - (a) a blocked hit of `d` points moves `hard` and `value` by k*d (k = HARD_SHARE times
##     the battery over the shield), never below 0, and the hard part plus the spent part
##     never goes above the battery;
##   - (b) a hit that overfills the battery starts a lockout of the hull's seconds plus a
##     second for every 25 points blocked, never above 15 s: a Scout, a corvette, a frigate,
##     the Destroyer and the Battlecruiser (one case with a lot blocked at once);
##   - (c) during the lockout a held trigger makes no shot (the Bomber's torpedo run
##     included), boost does nothing, the special is not ready, the ship still turns and
##     flies, and the zones are dark: a hit passes whole to the hull and changes no zone,
##     gate or battery number; a torpedo run a lockout ends is counted under its own reason
##     (torpedo_runs_cancel_overload), never as a rock cancel;
##   - (d) the lockout ends after its seconds (a tick more or less), the zones are lit
##     again, and the hard part drained at half speed meanwhile;
##   - (e) a full pierce adds nothing; an ion hit follows OverloadRules.ION_LOADS_HARD;
##     a one-pool shield, a Minion, a Turret and the Mothership have no battery and never
##     overload;
##   - (f) the hard part drains as OverloadRules.DRAIN_ONLY_RESTING says, and the soft part
##     never refills above the battery minus the hard part;
##   - (g) filling the battery, and a new launch, clear hard energy, the lockout and the Vent;
##   - (h) a hull whose shield is gone behaves as before;
##   - (i) the picture: the overload ring's state (ShipVisual.overload_on) is off before the
##     lockout, on during it and off after; the readout's words say "Overloaded" with the
##     seconds, "Venting" in a Vent and nothing otherwise; the shield picture's key differs
##     in the overload and dark bits while the lockout runs, and only then;
##   - (j) the readout: the ability line says "offline" (the unavailable colour), never "ready", while
##     the systems are off (a lockout or a Vent, even with a full battery) and "ready" again after; and the
##     Vent button's rectangle meets no line of text of the readout at its longest (the ability line of every
##     hull in every state, the speed line with every warning), measured with the readout's font;
##   - (j2) the RoleHud strip (escort words, overcharge, charged, pip), as it is drawn (short words, size 10), keeps
##     clear of the Vent button, packed from RoleHud.STRIP_RIGHT, with every item at its longest, for both escort
##     words (ESC x3 and ISOLATED), and never starts left of RoleHud.X; the drawn texts are shorter than the full words;
##   - (j3) the words "Overloaded 99.9 s" and "Venting" are drawn in ShipStatus.state_box(): the box
##     and both words stay inside the readout, and the words stay clear of the energy label.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=overload_check
##
## WHO USES IT: main.gd loads it for --test=overload_check; run_checks runs it. It changes
## only units of a frozen match that is thrown away.

## How close a measured number must be to the wanted one.
const TOL := 0.001
## One physics tick, in seconds.
const DT := 1.0 / 60.0
## The running match (set by setup()).
var world: World
## Where the ships stand: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## How many things have gone wrong so far.
var failures := 0


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
	_case_load()
	_case_lockout()
	_case_cap()
	_case_during()
	_case_ends()
	_case_kinds()
	_case_drain()
	_case_fill()
	_case_no_shield()
	_case_hud()
	_case_readout()
	_case_role_strip()
	_case_state_box()
	print("overload_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("overload_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` (team 1) and stand it still at home, facing east, with its
## shields and battery full and not just hit.
func _ship(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 40 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.shields.fill()
	s.shields.since_hit = 999.0
	s.fill_energy()
	return s


## A hit note of kind `kind` and pierce share `pierce` for a shot from the ship's front.
func _note(kind: int = Rules.W_BOLT, pierce: float = 0.0, local: Vector2 = Vector2(300.0, 0.0)) -> DamageInfo:
	var d := DamageInfo.new()
	d.kind = kind
	d.from_pos = _home + local
	d.pierce = pierce
	return d


## The share of a raw hit that drains a zone of ship `s` (one minus its resistance).
func _keep(s: Unit) -> float:
	return 1.0 - clampf(s.shields.resist + s.shield_resist_bonus(), 0.0, 0.9)


## Send a hit to the front zone of `s` that soaks exactly `points` shield points (resist
## applied). Returns what the hull took.
func _soak(s: Ship, points: float, kind: int = Rules.W_BOLT) -> float:
	return s.take_hit(_note(kind), points / _keep(s))


## Step `s` for `n` ticks of one sixtieth of a second.
func _tick(s: Ship, n: int = 1) -> void:
	for _i in n:
		world.time += DT
		s.sim_update(DT)


## The share of the battery one blocked shield point loads (the design's k).
func _k(s: Ship) -> float:
	return OverloadRules.HARD_SHARE * s.energy.max_value / s.shields.max_total


## The hull's lockout seconds written out here, so a wrong table in the data file shows.
func _class_s(hid: String) -> float:
	match hid:
		"scout", "fighter", "lance", "bomber":
			return 2.0
		"logistics", "support":
			return 3.5
		"flak", "ion":
			return 5.5
		"destroyer":
			return 7.5
		"battlecruiser":
			return 10.0
	return 2.0


## Put unit `u` away in a far corner and make it dead.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()


## (a) A blocked hit loads the battery by k per point; the soft part never goes below 0 and the
## hard part plus the spent part never goes above the battery.
func _case_load() -> void:
	var s := _ship("fighter")
	var k := _k(s)
	var maxv := s.energy.max_value
	_expect(absf(k - 0.3) < TOL, "(a) the Fighter's k is %s, not 0.3 (battery %s over shield %s)" % [k, maxv, s.shields.max_total])
	_soak(s, 30.0)
	_tick(s)
	_expect(absf(s.energy.hard - k * 30.0) < TOL, "(a) hard is %s after 30 blocked, wanted %s" % [s.energy.hard, k * 30.0])
	_expect(absf(s.energy.value - (maxv - k * 30.0)) < TOL, "(a) value is %s, wanted %s" % [s.energy.value, maxv - k * 30.0])
	_expect(s.overload_left == 0.0, "(a) a hit that fits the battery overloaded the ship")
	# Two hits in one tick add up, whatever the order.
	var t := _ship("fighter")
	_soak(t, 10.0)
	_soak(t, 15.0)
	_tick(t)
	_expect(absf(t.energy.hard - k * 25.0) < TOL, "(a) two hits in a tick: hard is %s, wanted %s" % [t.energy.hard, k * 25.0])
	# Overflow: only what is left joins the hard part, the soft part is 0, the hit is still blocked.
	var u := _ship("fighter")
	u.energy.value = 5.0
	var h0 := u.hull
	var took := _soak(u, 40.0)
	_tick(u)
	_expect(took == 0.0 and u.hull == h0, "(a) an overfilling hit still reached the hull (%s)" % took)
	_expect(u.energy.value >= 0.0 and u.energy.value < TOL, "(a) the soft part is %s after an overflow" % u.energy.value)
	_expect(absf(u.energy.hard - 5.2) < 0.3, "(a) hard is %s after an overflow from 5 soft (about 5.2 wanted)" % u.energy.hard)
	_expect(u.energy.value + u.energy.hard <= maxv + TOL, "(a) soft %s plus hard %s is above the battery %s" % [u.energy.value, u.energy.hard, maxv])
	# The sum never passes the battery over many tough hits and ticks.
	var w := _ship("fighter")
	var worst := 0.0
	for i in 60:
		w.shields.fill()
		_soak(w, 20.0)
		_tick(w)
		worst = maxf(worst, w.energy.value + w.energy.hard)
		_expect(w.energy.value >= 0.0, "(a) the soft part went below 0 (%s)" % w.energy.value)
	_expect(worst <= maxv + TOL, "(a) soft plus hard reached %s, above the battery %s" % [worst, maxv])
	print("overload_check: (a) 30 blocked on a Fighter: hard %.3f (k %.3f), value %.3f; overflow left value %.3f hard %.3f; 60 hits: soft plus hard at most %.3f of %.0f" % [s.energy.hard, k, s.energy.value, u.energy.value, u.energy.hard, worst, maxv])
	_put(s)
	_put(t)
	_put(u)
	_put(w)


## (b) An overfilling hit starts a lockout of the hull's seconds plus a second per 25 points
## blocked, for a hull of each size step.
func _case_lockout() -> void:
	var line := ""
	for hid: String in ["scout", "logistics", "flak", "destroyer", "battlecruiser"]:
		var s := _ship(hid)
		s.energy.value = 0.0
		var front := s.shields.cap(Rules.ZONE_FRONT)
		var blocked := front * 0.8
		_soak(s, blocked)
		_tick(s)
		var want := minf(15.0, _class_s(hid) + floorf(blocked / 25.0))
		_expect(absf(s.overload_left - want) < TOL, "(b) %s: lockout %s s, wanted %s (class %s, %s blocked)" % [hid, s.overload_left, want, _class_s(hid), blocked])
		_expect(s.systems_off(), "(b) %s: systems_off() is false in a lockout" % hid)
		_expect(absf(OverloadRules.class_seconds(hid) - _class_s(hid)) < TOL, "(b) %s: the table says %s, wanted %s" % [hid, OverloadRules.class_seconds(hid), _class_s(hid)])
		line += " %s %.2f s;" % [hid, s.overload_left]
		_put(s)
	_expect(absf(OverloadRules.class_seconds("no_such_hull") - 2.0) < TOL, "(b) an id not in the table gets %s, not 2" % OverloadRules.class_seconds("no_such_hull"))
	print("overload_check: (b) lockouts of the five size steps:%s" % line)


## (b) Many points blocked at once: the lockout stops at the longest, 15 s.
func _case_cap() -> void:
	var s := _ship("battlecruiser")
	s.energy.value = 0.0
	var total := 0.0
	var locals := [Vector2(300.0, 0.0), Vector2(-300.0, 0.0), Vector2(0.0, -300.0), Vector2(0.0, 300.0)]
	for z in 4:
		var raw := s.shields.values[z] / _keep(s)
		total += s.shields.values[z]
		s.take_hit(_note(Rules.W_BOLT, 0.0, locals[z]), raw)
	_tick(s)
	_expect(absf(s.overload_left - OverloadRules.MAX_S) < TOL, "(b) a whole Battlecruiser shield blocked (%s) gave %s s, wanted %s" % [total, s.overload_left, OverloadRules.MAX_S])
	_expect(absf(OverloadRules.MAX_S - 15.0) < TOL, "(b) the longest lockout is %s, not 15" % OverloadRules.MAX_S)
	print("overload_check: (b) %.0f points blocked at once on a Battlecruiser: lockout %.2f s (the longest is %.0f)" % [total, s.overload_left, OverloadRules.MAX_S])
	_put(s)


## (c) During the lockout: a held trigger makes no shot, boost and the special do nothing, the
## ship still flies and turns, and the zones are dark.
func _case_during() -> void:
	var s := _ship("fighter")
	s.energy.value = 0.0
	s.energy.hard = 40.0
	_soak(s, 30.0)
	_tick(s)
	_expect(s.overload_left > 0.0, "(c) the setup did not overload the Fighter")
	# The held trigger.
	s.controls.fire = true
	s.controls.aim_point = _home + Vector2(1000.0, 0.0)
	s.energy.value = 50.0
	var shots := false
	for _i in 30:
		_tick(s)
		for m in s.mounts:
			if m.cd > 0.0 or m.beam_firing:
				shots = true
	_expect(not shots, "(c) a gun fired during the lockout")
	_expect(not s.special_ready(), "(c) the special is ready in a lockout")
	# Boost and flight.
	s.controls.fire = false
	s.controls.boost = true
	s.controls.forward = 1.0
	s.controls.face_point = _home + Vector2(0.0, 1000.0)
	var rot0 := s.rotation
	var pos0 := s.global_position
	for _i in 30:
		_tick(s)
	_expect(not s.boosting, "(c) the ship boosted in a lockout")
	_expect(absf(Util.wrap_angle(s.rotation - rot0)) > 0.01, "(c) the ship did not turn in a lockout")
	_expect(s.global_position.distance_to(pos0) > 1.0, "(c) the ship did not fly in a lockout")
	s.controls.boost = false
	s.controls.forward = 0.0
	# Dark zones: a hit passes whole, as on a ship whose zone is empty.
	s.global_position = _home
	s.rotation = 0.0
	var c := _ship("fighter")
	for z in 4:
		c.shields.values[z] = 0.0
	var vals0 := Array(s.shields.values)
	var gates0 := Array(s.shields.gate_left)
	var hard0 := s.energy.hard
	var value0 := s.energy.value
	var took_s := s.take_hit(_note(), 20.0)
	var took_c := c.take_hit(_note(), 20.0)
	_expect(took_s > 1.0 and absf(took_s - took_c) < 1.0e-4, "(c) a hit in the lockout took %.4f, the control took %.4f" % [took_s, took_c])
	_expect(Array(s.shields.values) == vals0, "(c) a hit in the lockout changed a shield zone")
	_expect(Array(s.shields.gate_left) == gates0, "(c) a hit in the lockout changed a gate")
	_expect(s.shields.last_blocked == 0.0, "(c) a hit in the lockout counted as blocked (%s)" % s.shields.last_blocked)
	_expect(s.energy.hard == hard0 and s.energy.value == value0, "(c) a hit in the lockout moved the battery before its tick")
	# A break-sized hit on a gate: also passes whole.
	var took_big := s.take_hit(_note(), 500.0)
	_expect(took_big > took_s, "(c) a hit of 500 in the lockout took %.3f, not more than %.3f" % [took_big, took_s])
	# The Bomber's torpedo run: a held trigger never starts it in a lockout.
	var b := _ship("bomber")
	b.energy.value = 0.0
	_soak(b, 30.0)
	_tick(b)
	_expect(b.overload_left > 0.0, "(c) the setup did not overload the Bomber")
	b.energy.value = b.energy.max_value - b.energy.hard
	b.controls.fire = true
	var started0 := int(Game.usage.get("torpedo_runs_started", 0))
	var launched0 := int(Game.usage.get("torpedo_runs_launched", 0))
	var ticks := mini(int(b.overload_left * 60.0) - 5, 300)
	for _i in ticks:
		_tick(b)
	_expect(b.run_mount != null and not b.run_mount.run.on, "(c) a torpedo run is on in the lockout")
	_expect(int(Game.usage.get("torpedo_runs_started", 0)) == started0, "(c) a torpedo run started in the lockout")
	_expect(int(Game.usage.get("torpedo_runs_launched", 0)) == launched0, "(c) torpedoes left in the lockout")
	# A run that is on when the lockout begins is cancelled free: nothing launches.
	var r := _ship("bomber")
	r.controls.fire = true
	for _i in 400:
		_tick(r)
		if r.run_mount.run.on and r.run_mount.run.is_full():
			break
	var was_on := r.run_mount.run.on and r.run_mount.run.is_full()
	_expect(was_on, "(c) the Bomber's run did not fill its bar with the trigger held")
	launched0 = int(Game.usage.get("torpedo_runs_launched", 0))
	var cancelled0 := int(Game.usage.get("torpedo_runs_cancelled", 0))
	var rock0 := int(Game.usage.get("torpedo_runs_cancel_rock", 0))
	var over0 := int(Game.usage.get("torpedo_runs_cancel_overload", 0))
	r.overload_left = 3.0
	for _i in 120:
		_tick(r)
	_expect(not r.run_mount.run.on and int(Game.usage.get("torpedo_runs_launched", 0)) == launched0, "(c) a run on at the start of a lockout was not ended free (on %s)" % r.run_mount.run.on)
	# The cancel has its own reason: the overload count rises by one, the rock count does not move.
	var over1 := int(Game.usage.get("torpedo_runs_cancel_overload", 0))
	var rock1 := int(Game.usage.get("torpedo_runs_cancel_rock", 0))
	_expect(over1 == over0 + 1, "(c) the run ended by the lockout raised torpedo_runs_cancel_overload from %d to %d, not by one" % [over0, over1])
	_expect(rock1 == rock0, "(c) the run ended by the lockout was counted as a rock cancel (%d to %d)" % [rock0, rock1])
	_expect(int(Game.usage.get("torpedo_runs_cancelled", 0)) == cancelled0 + 1, "(c) the run ended by the lockout was not counted once in torpedo_runs_cancelled")
	print("overload_check: (c) in the lockout: no shot in 30 ticks, no boost, no special, the Fighter turned and flew; a hit took %.3f (control %.3f), no zone or gate moved; the Bomber started no run" % [took_s, took_c])
	_put(s)
	_put(c)
	_put(b)
	_put(r)


## (d) The lockout ends after its seconds, the zones are lit again, and the hard part drained
## at half speed meanwhile.
func _case_ends() -> void:
	var s := _ship("fighter")
	s.energy.value = 0.0
	s.energy.hard = 40.0
	_soak(s, 30.0)
	_tick(s)
	var secs := s.overload_left
	_expect(secs > 0.0 and s.shields.dark, "(d) the setup did not start a lockout with dark zones")
	var hard0 := s.energy.hard
	s.shields.since_hit = 999.0
	_tick(s, 30)
	var drop := hard0 - s.energy.hard
	var want := s.energy.regen * OverloadRules.HARD_DRAIN_PER_REGEN * OverloadRules.REST_HALF * DT * 30.0
	_expect(absf(drop - want) < 0.01, "(d) hard dropped %s in 30 ticks of the lockout, wanted %s (half speed)" % [drop, want])
	var ticks := 30
	while s.overload_left > 0.0 and ticks < 2000:
		_tick(s)
		ticks += 1
	var want_ticks := ceili(secs / DT)
	_expect(absi(ticks - want_ticks) <= 1, "(d) the lockout lasted %d ticks, wanted %d (plus or minus one)" % [ticks, want_ticks])
	_expect(not s.shields.dark and not s.systems_off(), "(d) the zones are still dark after the lockout")
	var z0 := s.shields.values[Rules.ZONE_FRONT]
	_soak(s, 10.0)
	_expect(absf(s.shields.values[Rules.ZONE_FRONT] - (z0 - 10.0)) < 0.01, "(d) after the lockout a hit left the zone at %s, wanted %s" % [s.shields.values[Rules.ZONE_FRONT], z0 - 10.0])
	# Guns work again.
	s.controls.fire = true
	s.controls.aim_point = _home + Vector2(1000.0, 0.0)
	var fired := false
	for _i in 10:
		_tick(s)
		for m in s.mounts:
			if m.cd > 0.0:
				fired = true
	_expect(fired, "(d) the guns did not fire after the lockout")
	print("overload_check: (d) the lockout of %.3f s lasted %d ticks (wanted %d); hard dropped %.3f in 30 ticks of it (half speed: %.3f); zones lit again, guns fire" % [secs, ticks, want_ticks, drop, want])
	_put(s)


## (e) A full pierce adds nothing; an ion hit follows ION_LOADS_HARD; a one-pool shield and the
## units with no battery never overload.
func _case_kinds() -> void:
	var s := _ship("fighter")
	s.take_hit(_note(Rules.W_TORP, 1.0), 90.0)
	_tick(s)
	_expect(s.energy.hard == 0.0 and s.overload_left == 0.0, "(e) a full pierce loaded hard energy (%s)" % s.energy.hard)
	# A half pierce: only the soaked half loads.
	var h := _ship("fighter")
	var info := _note(Rules.W_TORP, 0.5)
	info.strength = 40.0
	h.take_hit(info, 40.0)
	_tick(h)
	_expect(absf(h.energy.hard - _k(h) * 20.0) < TOL, "(e) a half pierce of 40 loaded %s, wanted %s (only the soaked 20)" % [h.energy.hard, _k(h) * 20.0])
	# An ion hit.
	var i := _ship("fighter")
	_soak(i, 30.0, Rules.W_ION)
	_tick(i)
	var want_ion := _k(i) * 30.0 if OverloadRules.ION_LOADS_HARD else 0.0
	_expect(absf(i.energy.hard - want_ion) < TOL, "(e) an ion hit of 30 loaded %s (ION_LOADS_HARD is %s), wanted %s" % [i.energy.hard, OverloadRules.ION_LOADS_HARD, want_ion])
	# A one-pool shield and the units with no battery.
	var m := world.spawn_minion(1, "corvette", "mid", _home + Vector2(0.0, 600.0))
	_expect(m.shields != null and m.shields.single, "(e) the corvette minion has no single pool")
	m.take_hit(_note(), 50.0)
	_expect(m.shields.last_blocked == 0.0, "(e) a one-pool shield counted blocked points (%s)" % m.shields.last_blocked)
	_expect(not ("energy" in m) and not ("overload_left" in m), "(e) a Minion has a battery")
	var ms := world.mothership(1)
	ms.take_hit(_note(), 50.0)
	_expect(ms.shields.last_blocked == 0.0 and not ("energy" in ms), "(e) the Mothership counted blocked points or has a battery")
	for t: Turret in world.turrets:
		_expect(not ("energy" in t) and not ("overload_left" in t), "(e) a Turret has a battery")
		break
	print("overload_check: (e) a full pierce loads nothing; a half pierce loads the soaked half (%.3f); an ion hit loaded %.3f (ION_LOADS_HARD %s); a Minion, the Mothership and a Turret have no battery" % [h.energy.hard, i.energy.hard, OverloadRules.ION_LOADS_HARD])
	_put(s)
	_put(h)
	_put(i)
	_put(m)


## (f) Hard energy drains as DRAIN_ONLY_RESTING says; the soft part never refills above the
## battery minus the hard part.
func _case_drain() -> void:
	var s := _ship("fighter")
	var maxv := s.energy.max_value
	s.energy.hard = 50.0
	s.energy.value = 10.0
	# While the shield is not resting: no drain (the default rule), the soft part rises only to max - hard.
	var drained_hot := 0.0
	for _i in 600:
		s.shields.since_hit = 0.0
		var before := s.energy.hard
		_tick(s)
		drained_hot += before - s.energy.hard
	if OverloadRules.DRAIN_ONLY_RESTING:
		_expect(drained_hot < TOL, "(f) hard drained %s while the shield was not resting" % drained_hot)
		_expect(absf(s.energy.value - (maxv - 50.0)) < TOL, "(f) the soft part is %s after 10 s, the ceiling is %s" % [s.energy.value, maxv - 50.0])
	else:
		_expect(drained_hot > 0.0, "(f) hard did not drain while the shield was not resting (DRAIN_ONLY_RESTING is false)")
	_expect(s.energy.value <= maxv - s.energy.hard + TOL, "(f) the soft part %s is above the battery %s minus hard %s" % [s.energy.value, maxv, s.energy.hard])
	# Resting: the normal speed.
	var t := _ship("fighter")
	t.energy.hard = 50.0
	t.energy.value = maxv - 50.0
	t.shields.since_hit = 999.0
	var h0 := t.energy.hard
	_tick(t, 60)
	var drop := h0 - t.energy.hard
	var want := t.energy.regen * OverloadRules.HARD_DRAIN_PER_REGEN * 1.0
	_expect(absf(drop - want) < 0.01, "(f) hard dropped %s in a second at rest, wanted %s" % [drop, want])
	# The soft part follows the ceiling up as the hard part drains.
	_expect(t.energy.value <= maxv - t.energy.hard + TOL, "(f) the soft part %s is above the ceiling %s" % [t.energy.value, maxv - t.energy.hard])
	print("overload_check: (f) not resting: hard drained %.3f in 10 s (DRAIN_ONLY_RESTING %s), soft stopped at %.3f of the ceiling %.3f; resting: %.3f in a second (wanted %.3f)" % [drained_hot, OverloadRules.DRAIN_ONLY_RESTING, s.energy.value, maxv - s.energy.hard, drop, want])
	_put(s)
	_put(t)


## (g) Filling the battery, and a new launch, clear hard energy, the lockout and the Vent.
func _case_fill() -> void:
	var s := _ship("fighter")
	s.energy.hard = 30.0
	s.energy.value = 10.0
	s.overload_left = 5.0
	s.venting = true
	s.shields.dark = true
	s.fill_energy()
	_expect(s.energy.hard == 0.0 and s.energy.value == s.energy.max_value, "(g) fill left hard %s value %s" % [s.energy.hard, s.energy.value])
	_expect(s.overload_left == 0.0 and not s.venting and not s.shields.dark and not s.systems_off(), "(g) fill left the lockout, the Vent or the dark zones")
	# Dock and launch again: a new ship starts clean.
	var t := _ship("fighter")
	t.energy.value = 0.0
	_soak(t, 30.0)
	_tick(t)
	_expect(t.overload_left > 0.0, "(g) the setup did not overload the ship before docking")
	var p := t.profile
	var docked := world.try_dock(t, true)
	_expect(docked, "(g) the ship did not dock")
	if docked:
		var n := world.launch(p)
		_expect(n != null and n.energy.hard == 0.0 and n.overload_left == 0.0 and not n.venting and not n.shields.dark, "(g) a launched ship started with hard energy, a lockout or a Vent")
		if n != null:
			_put(n)
	print("overload_check: (g) fill_energy() and a new launch clear hard energy, the lockout, the Vent and the dark zones")
	_put(s)


## (h) A ship with no shield, and one whose shield size is 0, never loads or overloads.
func _case_no_shield() -> void:
	var s := _ship("fighter")
	s.shields = null
	var h0 := s.hull
	var took := s.take_hit(_note(), 20.0)
	# A whole ship tick needs a shield, so the overload step is called by itself here.
	for _i in 10:
		s._overload_step(DT)
	_expect(took > 1.0 and s.hull < h0, "(h) a ship with no shield took %.3f" % took)
	_expect(s.energy.hard == 0.0 and s.overload_left == 0.0 and not s.systems_off(), "(h) a ship with no shield loaded or overloaded")
	var e := _ship("fighter")
	e.shields.max_total = 0.0
	e.shields.values = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	e.take_hit(_note(), 20.0)
	_tick(e, 10)
	_expect(e.energy.hard == 0.0 and e.overload_left == 0.0, "(h) a ship with a zero shield loaded or overloaded")
	print("overload_check: (h) a ship with no shield, or a zero shield, takes hits and never loads or overloads")
	_put(s)
	_put(e)


## (i) The picture: the ring's state, the readout's words and the shield picture's key.
func _case_hud() -> void:
	var s := _ship("fighter")
	_expect(not ShipVisual.overload_on(s), "(i) a fresh ship shows an overload ring")
	_expect(not ShipVisual.overload_on(null), "(i) no ship shows an overload ring")
	_expect(ShipStatus.state_text(s) == "" and ShipStatus.state_text(null) == "", "(i) the readout has words for a ship at rest (%s)" % ShipStatus.state_text(s))
	var v := s.get_node_or_null("Visual") as ShipVisual
	var cache: DrawCache = v._shield if v != null else null
	if not Game.sim_only:
		_expect(cache != null, "(i) outside --sim-only the ship has no shield picture to check")
	var key0 := 0
	if cache != null:
		v._update_shield(1.0)
		key0 = cache.bits
		_expect(((key0 >> ShipVisual.OVERLOAD_BIT_SHIFT) & 3) == 0, "(i) a ship at rest has overload or dark bits in its picture's key")
	s.energy.value = 0.0
	_soak(s, 30.0)
	_tick(s)
	_expect(s.overload_left > 0.0, "(i) the setup did not overload the ship")
	_expect(ShipVisual.overload_on(s), "(i) an overloaded ship shows no ring")
	var words := ShipStatus.state_text(s)
	_expect(words.begins_with("Overloaded ") and words.ends_with(" s"), "(i) the readout says '%s' in a lockout" % words)
	var key1 := 0
	if cache != null:
		v._update_shield(1.0)
		key1 = cache.bits
		_expect(((key1 >> ShipVisual.OVERLOAD_BIT_SHIFT) & 3) == 3, "(i) the picture's overload and dark bits are %d in a lockout" % ((key1 >> ShipVisual.OVERLOAD_BIT_SHIFT) & 3))
		_expect(key1 != key0, "(i) the picture's key did not change when the lockout began")
		# A tick that only counts the lockout down changes no bit.
		_tick(s)
		v._update_shield(1.0)
		_expect(cache.bits == key1, "(i) the key moved while the lockout only counted down")
	var n := 0
	while s.overload_left > 0.0 and n < 2000:
		_tick(s)
		n += 1
	_expect(not ShipVisual.overload_on(s), "(i) the ring is still on after the lockout")
	_expect(ShipStatus.state_text(s) == "", "(i) the readout still has words after the lockout (%s)" % ShipStatus.state_text(s))
	if cache != null:
		v._update_shield(1.0)
		_expect(((cache.bits >> ShipVisual.OVERLOAD_BIT_SHIFT) & 3) == 0, "(i) the overload and dark bits stayed on after the lockout")
	# A Vent: dark zones, words, no ring.
	s.fill_energy()
	s.energy.hard = 30.0
	s.energy.value = 20.0
	s.controls.vent = true
	_tick(s)
	_expect(s.venting and not ShipVisual.overload_on(s), "(i) a Vent shows an overload ring")
	_expect(ShipStatus.state_text(s) == "Venting", "(i) the readout says '%s' in a Vent" % ShipStatus.state_text(s))
	if cache != null:
		v._update_shield(1.0)
		_expect(((cache.bits >> ShipVisual.OVERLOAD_BIT_SHIFT) & 3) == 2, "(i) a Vent's picture bits are %d, not dark only" % ((cache.bits >> ShipVisual.OVERLOAD_BIT_SHIFT) & 3))
	print("overload_check: (i) the ring state is off, on in a lockout (%s) and off after %d ticks; a Vent says 'Venting' with dark zones and no ring" % [words, n])
	_put(s)

## (j) The ability line and the Vent button's place in the readout.
func _case_readout() -> void:
	var s := _ship("fighter")
	var rest := String(ShipStatus.ability_line(s)["text"])
	_expect(rest.ends_with("ready (right-click / G)"), "(j) a ship at rest has the ability line '%s', not ready" % rest)
	s.energy.value = s.energy.max_value
	s.overload_left = 3.0
	var lock := ShipStatus.ability_line(s)
	_expect(s.systems_off() and String(lock["text"]).ends_with(": offline") and (lock["col"] as Color) == Palette.MIST, "(j) in a lockout (full battery) the ability line is '%s' in colour %s, not offline in the unavailable colour" % [lock["text"], lock["col"]])
	s.overload_left = 0.0
	s.venting = true
	var vent := ShipStatus.ability_line(s)
	_expect(s.systems_off() and String(vent["text"]).ends_with(": offline") and (vent["col"] as Color) == Palette.MIST, "(j) in a Vent (full battery) the ability line is '%s' in colour %s, not offline in the unavailable colour" % [vent["text"], vent["col"]])
	s.venting = false
	var after := String(ShipStatus.ability_line(s)["text"])
	_expect(not s.systems_off() and after.ends_with("ready (right-click / G)"), "(j) after the lockout and the Vent the ability line is '%s', not ready" % after)
	s.energy.value = 0.0
	var low := String(ShipStatus.ability_line(s)["text"])
	_expect(low.contains("needs") and not low.contains("offline"), "(j) a ship with a low battery has the ability line '%s', not the needs line" % low)
	# The Vent button against the text: every hull's ability line in every state, and the speed line with every warning.
	var font: Font = ThemeDB.fallback_font
	var measured := font.get_string_size("Emergency repair", HORIZONTAL_ALIGNMENT_LEFT, -1, ShipStatus.ABILITY_SIZE).x > 10.0
	var button := ShipStatus.vent_rect()
	var widest := 0.0
	var widest_text := ""
	var hits := 0
	for hid in Ships.HULLS:
		var label := String(Dictionary(Ships.HULLS[hid]).get("special_label", "Ability"))
		for tmpl: String in ["%s: ready (right-click / G)", "%s: offline", "%s: needs 100 energy", "%s: active 99.9s", "%s: 99.9s"]:
			var t := tmpl % label
			var rect := ShipStatus.ability_text_rect(t, font)
			if not measured:
				rect = Rect2(ShipStatus.ROUTE_X, ShipStatus.ABILITY_Y, 7.0 * float(t.length()), 16.0)
			if rect.intersects(button):
				hits += 1
			if rect.end.x > widest:
				widest = rect.end.x
				widest_text = t
	var speed := "Speed 9999 / 9999  ·  BOOST  ·  Assist OFF (V)  ·  ACE 99s  ·  ENGINES STALLED  ·  SLIPSTREAM"
	var sw := font.get_string_size(speed, HORIZONTAL_ALIGNMENT_LEFT, -1, ShipStatus.SPEED_SIZE).x if measured else 7.0 * float(speed.length())
	var base := ShipStatus.SPEED_Y + 10.0
	var srect := Rect2(ShipStatus.ROUTE_X, base - font.get_ascent(ShipStatus.SPEED_SIZE), sw, font.get_ascent(ShipStatus.SPEED_SIZE) + font.get_descent(ShipStatus.SPEED_SIZE))
	if not measured:
		srect = Rect2(ShipStatus.ROUTE_X, ShipStatus.SPEED_Y, sw, 16.0)
	_expect(hits == 0, "(j) %d ability line texts meet the Vent button %s" % [hits, button])
	_expect(not srect.intersects(button), "(j) the speed line with every warning %s meets the Vent button %s" % [srect, button])
	_expect(Rect2(Vector2.ZERO, Vector2(ShipStatus.W, ShipStatus.H)).encloses(button), "(j) the Vent button %s is not inside the readout" % button)
	# The readout's other click parts keep their places: no energy button reaches the Vent button.
	var w := ShipStatus.W - ShipStatus.ROUTE_X - 10.0
	var bw := (w - 9.0) / 4.0
	var clash := false
	for i in 4:
		if Rect2(ShipStatus.ROUTE_X + float(i) * (bw + 3.0), ShipStatus.ROUTE_Y, bw, ShipStatus.ROUTE_H).intersects(button):
			clash = true
	_expect(not clash, "(j) an energy button meets the Vent button %s" % button)
	print("overload_check: (j) the ability line says '%s' in a lockout and a Vent (it said ready before); the longest ability text ends at x %.0f ('%s', %s font width), the speed line at x %.0f; the Vent button is x %.0f-%.0f, y %.0f-%.0f: no overlap" % [lock["text"], widest, widest_text, "measured" if measured else "estimated", srect.end.x, button.position.x, button.end.x, button.position.y, button.end.y])
	_put(s)


## (j2) The RoleHud strip (the escort words, OVERCHARGE, CHARGED and the pip) keeps clear of the Vent button, even with
## all of its items at their longest: no rectangle of it meets the button, no two meet each other, every one is inside the
## readout and none starts left of RoleHud.X (so the strip cannot run over the "Focus: ..." line). With only the escort
## words showing, they start at RoleHud.X. The rectangles come from RoleHud.strip_rects(), the function the drawing uses,
## which measures the short texts the drawing draws. The case runs once for each escort word the status can return
## ("ESCORTED x3", the widest count at MAX_SUPPORT 3, and "ISOLATED"), and one more clause holds that the drawn
## texts are shorter than the full words, so an edit that puts the full words back is caught even where they fit.
## The line it prints for each word shows the measured widths and the room whether the case passes or not.
func _case_role_strip() -> void:
	var font: Font = ThemeDB.fallback_font
	var measured := font.get_string_size("OVERCHARGE", HORIZONTAL_ALIGNMENT_LEFT, -1, RoleHud.SIZE).x > 10.0
	var button := ShipStatus.vent_rect()
	var readout := Rect2(Vector2.ZERO, Vector2(ShipStatus.W, ShipStatus.H))
	for words: String in ["ESCORTED x3", "ISOLATED"]:
		var all := RoleHud.strip_rects(words, Rules.ENERGY_WEAPONS, RoutingPayoffFeature.OVERCHARGE_TIME, font, ShipStatus.H)
		var alone := RoleHud.strip_rects(words, -1, 0.0, font, ShipStatus.H)
		var names: Array = all.keys()
		var left := ShipStatus.W
		var widths := ""
		_expect(names.size() == 4, "(j2) the strip with every item shows %d items, not 4" % names.size())
		for k: String in names:
			var r: Rect2 = all[k]
			left = minf(left, r.position.x)
			widths += " %s %.0f;" % [k, r.size.x]
			if not measured:
				continue
			_expect(not r.intersects(button), "(j2) the strip's %s %s meets the Vent button %s" % [k, r, button])
			_expect(readout.encloses(r), "(j2) the strip's %s %s is not inside the readout %s" % [k, r, readout])
			_expect(r.position.x >= RoleHud.X, "(j2) the strip's %s %s starts left of the strip's left bound %.1f" % [k, r, RoleHud.X])
		if measured:
			for i in names.size():
				for j in range(i + 1, names.size()):
					var a: Rect2 = all[names[i]]
					var b: Rect2 = all[names[j]]
					_expect(not a.intersects(b), "(j2) the strip's %s %s meets its %s %s" % [names[i], a, names[j], b])
		_expect(alone.size() == 1 and alone.has("words") and (alone["words"] as Rect2).position.x == RoleHud.X, "(j2) the escort words alone do not start at %.1f: %s" % [RoleHud.X, alone])
		print("overload_check: (j2) the strip with every item at its longest (%s, drawn %s); widths:%s the leftmost starts at x %.1f, left bound %.1f, the strip's right edge %.1f (room %.1f); the Vent button starts at x %.0f; %s font width" % [words, RoleHud.short_words(words), widths, left, RoleHud.X, RoleHud.STRIP_RIGHT, RoleHud.STRIP_RIGHT - RoleHud.X, button.position.x, "measured" if measured else "estimated, the width clauses were not checked"])
	var over_text: String = RoleHud.OVER_FORMAT % 2.0
	_expect(RoleHud.short_words("ESCORTED x3").length() < "ESCORTED x3".length(), "(j2) the escort words are drawn as '%s', not shorter than ESCORTED x3" % RoleHud.short_words("ESCORTED x3"))
	_expect(RoleHud.CHARGED_TEXT.length() < "CHARGED".length(), "(j2) the charged text '%s' is not shorter than CHARGED" % RoleHud.CHARGED_TEXT)
	_expect(over_text.length() < "OVERCHARGE 2.0s".length(), "(j2) the overcharge text '%s' is not shorter than OVERCHARGE 2.0s" % over_text)


## (j3) The words "Overloaded 99.9 s" and "Venting" are drawn right-aligned in ShipStatus.state_box() on the
## energy bar's row: the box and both words stay inside the readout, and the words stay clear of the energy
## label at its longest. Measured with the readout's font, as (j) does.
func _case_state_box() -> void:
	var font: Font = ThemeDB.fallback_font
	var fsize := 10
	var measured := font.get_string_size("Overloaded", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > 10.0
	# These three lines mirror ShipStatus._draw_bars: x is the bars' left edge (ROUTE_X), w is
	# W - x - 10, and the energy bar's row is y 37 (the hull bar at 6, then 16 more, then 15 more).
	var x := ShipStatus.ROUTE_X
	var w := ShipStatus.W - ShipStatus.ROUTE_X - 10.0
	var y := 37.0
	var box := ShipStatus.state_box(x, y, w)
	var readout := Rect2(Vector2.ZERO, Vector2(ShipStatus.W, ShipStatus.H))
	_expect(readout.encloses(box), "(j3) the state words' box %s is not inside the readout %s" % [box, readout])
	var asc := font.get_ascent(fsize) if measured else 10.0
	var desc := font.get_descent(fsize) if measured else 3.0
	# The energy label at its longest, drawn from x + 4 on the same baseline (y + 10).
	var label := "Energy 9999 / 9999  held 9999"
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x if measured else 6.0 * float(label.length())
	var label_rect := Rect2(x + 4.0, y + 10.0 - asc, label_w, asc + desc)
	var line := ""
	for words: String in ["Overloaded 99.9 s", "Venting"]:
		var tw := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x if measured else 6.0 * float(words.length())
		# Right-aligned in the box, so the words end at the box's right edge.
		var trect := Rect2(box.end.x - tw, y + 10.0 - asc, tw, asc + desc)
		_expect(tw <= box.size.x, "(j3) '%s' is %.0f wide, wider than its box (%.0f)" % [words, tw, box.size.x])
		_expect(readout.encloses(trect), "(j3) '%s' %s is not inside the readout %s" % [words, trect, readout])
		_expect(not trect.intersects(label_rect), "(j3) '%s' %s meets the energy label %s" % [words, trect, label_rect])
		line += " '%s' x %.0f-%.0f;" % [words, trect.position.x, trect.end.x]
	print("overload_check: (j3) the state box is x %.0f-%.0f (the readout ends at %.0f);%s the energy label at its longest ends at x %.0f (%s font width)" % [box.position.x, box.end.x, ShipStatus.W, line, label_rect.end.x, "measured" if measured else "estimated"])