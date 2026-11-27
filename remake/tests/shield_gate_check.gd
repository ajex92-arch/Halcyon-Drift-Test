extends Node
## WHAT THIS IS: the check of shield gating (T-28 step 4): a hit that breaks a shield
## zone loses its spill-over, and the zone is then immune for a gate that is longer
## for bigger shields. It prints one line per case and then
## "shield_gate_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it freezes the match, launches real ships, and sends hits through
## Unit.take_hit() (and Combat.apply_damage() once), stepping ShieldZones.tick() by hand
## where time must pass. It checks:
##   - (a) a Fighter (shield 200, 50 a zone): a hit of 80 on the front zone empties it,
##     reaches neither the hull nor the armour, and starts a gate of gate_seconds();
##   - the scale: a pool of 120 or fewer gets 0.33 s, 3,000 or more 2.25 s, a Battlecruiser
##     2.25 s, in between a straight line (computed here from the constants);
##   - (b) during the gate a hit on that zone changes nothing anywhere; a hit on another zone
##     drains that zone and does not gate it;
##   - (c) the gate counts down in seconds and ends (a tick more or less), then a hit passes
##     through the empty zone whole, as a control ship with no gate takes it;
##   - (d) a hit that drains a zone exactly to 0, or leaves points in it, starts no gate;
##   - (e) a full pierce never touches the shield or the gate; a half pierce that breaks a
##     zone: the hull takes the piercing half and not the soaked half's spill;
##   - (f) an ion hit that breaks a zone empties it, starts no gate and hurts no hull; the next
##     other hit on that empty zone passes whole;
##   - (g) the one-pool shields (a Minion, the Mothership, a RepairBay, a bare pool): a break
##     passes its spill to the hull as before and never gates;
##   - (h) a unit with no shield, and a Ship whose shield is empty before the hit, take hits as
##     before;
##   - (i) fill() ends a running gate; set_focus() and set_max() keep it, and set_max() changes
##     only the next gate;
##   - (j) the Lance beam and the Fighter cannon on a Fighter: the rounds and beam ticks lost
##     to the gate (reported), and the hits that pass whole afterwards;
##   - (k) a hit through Combat.apply_damage on a shielded Destroyer behaves as take_hit does;
##   - (l) the glow: ShipVisual's gate state for a zone is on while the gate runs and off after,
##     and the shield picture's key differs in the gate bits (and only when a gate starts or ends).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=shield_gate_check
## With --shots-dir=<folder> (in a window, not headless) it also saves a picture of a Fighter
## with a gated front zone as <folder>/shield_gate_fighter.png.
##
## WHO USES IT: main.gd loads it for --test=shield_gate_check; run_checks runs it. It
## changes only units of a frozen match that is thrown away.

## How close a measured damage number must be to the wanted one.
const TOL := 0.01
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
	_case_break()
	_case_scale()
	_case_during()
	_case_ends()
	_case_exact()
	_case_pierce()
	_case_ion()
	_case_pools()
	_case_no_shield()
	_case_keep()
	_case_weapons()
	_case_apply_damage()
	_case_glow()
	await _shot()
	print("shield_gate_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("shield_gate_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` (team 1) and stand it still at home, facing
## east, with its shields full and not just hit.
func _ship(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.shields.fill()
	s.shields.since_hit = 999.0
	return s


## A hit note of kind `kind` and pierce share `pierce` for a shot from `local` (the ship's own
## frame, ship at home facing east).
func _note(local: Vector2, kind: int = Rules.W_BOLT, pierce: float = 0.0) -> DamageInfo:
	var d := DamageInfo.new()
	d.kind = kind
	d.from_pos = _home + local
	d.pierce = pierce
	return d


## The point the shots come from at the ship's front.
func _front() -> Vector2:
	return Vector2(300.0, 0.0)


## The point the shots come from behind the ship.
func _rear() -> Vector2:
	return Vector2(-300.0, 0.0)


## The share of a raw hit a shield of ship `s` lets drain its zone (its resistance).
func _keep(s: Unit) -> float:
	return 1.0 - clampf(s.shields.resist + s.shield_resist_bonus(), 0.0, 0.9)


## The gate length the design says for a shield of `pool` points (the formula, here from the
## constants, so a wrong gate_seconds() shows).
func _gate_for(pool: float) -> float:
	var t := clampf((pool - 120.0) / (3000.0 - 120.0), 0.0, 1.0)
	return 0.33 + t * (2.25 - 0.33)


## A copy of the armour section hit points of `s`.
func _hp(s: Ship) -> Array:
	return Array(s.armour.a_hp)


## True when the hull and every armour section of `s` are as `hull` and `hp` say.
func _unchanged(s: Ship, hull: float, hp: Array) -> bool:
	return s.hull == hull and _hp(s) == hp


## Break the front zone of `s` with a hit that is 1.6 times what the zone can hold. Returns the
## hull damage the hit did (0 when the spill is dropped).
func _break_front(s: Ship) -> float:
	var raw := s.shields.values[Rules.ZONE_FRONT] / _keep(s) * 1.6
	return s.take_hit(_note(_front()), raw)


## (a) A Fighter's front zone breaks: no spill-over, the zone is empty, the gate runs.
func _case_break() -> void:
	var s := _ship("fighter")
	_expect(is_equal_approx(s.shields.max_total, 200.0), "the Fighter's shield is %s, not 200" % s.shields.max_total)
	var cap := s.shields.cap(Rules.ZONE_FRONT)
	_expect(is_equal_approx(cap, 50.0), "the Fighter's front zone holds %s, not 50" % cap)
	var h0 := s.hull
	var hp0 := _hp(s)
	var took := s.take_hit(_note(_front()), 80.0)
	_expect(took == 0.0, "(a) the breaking hit took %.3f from the hull, not 0" % took)
	_expect(_unchanged(s, h0, hp0), "(a) the breaking hit reached the hull or the armour")
	_expect(s.shields.values[Rules.ZONE_FRONT] == 0.0, "(a) the front zone holds %s after a break" % s.shields.values[Rules.ZONE_FRONT])
	var want := _gate_for(200.0)
	_expect(absf(s.shields.gate_left[Rules.ZONE_FRONT] - want) < 1.0e-4, "(a) the gate is %s, wanted %s" % [s.shields.gate_left[Rules.ZONE_FRONT], want])
	_expect(absf(s.shields.gate_seconds() - 0.38333) < 1.0e-3, "(a) a Fighter's gate_seconds() is %s, not about 0.383" % s.shields.gate_seconds())
	for z in [Rules.ZONE_REAR, Rules.ZONE_LEFT, Rules.ZONE_RIGHT]:
		_expect(s.shields.gate_left[z] == 0.0 and s.shields.values[z] == cap, "(a) zone %d changed" % z)
	print("shield_gate_check: (a) a Fighter's front zone broke by 80 on 50: hull took %.3f, gate %.4f s (the formula says %.4f)" % [took, s.shields.gate_left[Rules.ZONE_FRONT], want])
	_put(s)


## The scale: the two ends, the line between them, a capital.
func _case_scale() -> void:
	var sh := ShieldZones.new()
	for pool: float in [0.0, 60.0, 120.0, 200.0, 420.0, 1000.0, 1800.0, 3000.0, 3500.0, 9000.0]:
		sh.setup(pool, 10.0, 3.5)
		var got := sh.gate_seconds()
		_expect(absf(got - _gate_for(pool)) < 1.0e-5, "scale: a pool of %s gives %s, wanted %s" % [pool, got, _gate_for(pool)])
	sh.setup(120.0, 10.0, 3.5)
	_expect(absf(sh.gate_seconds() - 0.33) < 1.0e-6, "scale: a pool of 120 gives %s, not 0.33" % sh.gate_seconds())
	sh.setup(80.0, 10.0, 3.5)
	_expect(absf(sh.gate_seconds() - 0.33) < 1.0e-6, "scale: a pool under 120 gives %s, not 0.33" % sh.gate_seconds())
	sh.setup(3000.0, 10.0, 3.5)
	_expect(absf(sh.gate_seconds() - 2.25) < 1.0e-6, "scale: a pool of 3000 gives %s, not 2.25" % sh.gate_seconds())
	sh.setup(5000.0, 10.0, 3.5)
	_expect(absf(sh.gate_seconds() - 2.25) < 1.0e-6, "scale: a pool over 3000 gives %s, not 2.25" % sh.gate_seconds())
	# A capital, for real: a Battlecruiser's front zone breaks and gets the longest gate; a Scout the shortest.
	var bc := _ship("battlecruiser")
	var h0 := bc.hull
	var took := _break_front(bc)
	_expect(took == 0.0 and bc.hull == h0, "scale: the Battlecruiser's breaking hit hurt the hull (%.3f)" % took)
	_expect(absf(bc.shields.gate_left[Rules.ZONE_FRONT] - 2.25) < 1.0e-4, "scale: the Battlecruiser's gate is %s, not 2.25" % bc.shields.gate_left[Rules.ZONE_FRONT])
	var sc := _ship("scout")
	_break_front(sc)
	_expect(absf(sc.shields.gate_left[Rules.ZONE_FRONT] - 0.33) < 1.0e-4, "scale: the Scout's gate is %s, not 0.33" % sc.shields.gate_left[Rules.ZONE_FRONT])
	var ds := _ship("destroyer")
	_break_front(ds)
	_expect(absf(ds.shields.gate_left[Rules.ZONE_FRONT] - _gate_for(1800.0)) < 1.0e-4, "scale: the Destroyer's gate is %s, wanted %s" % [ds.shields.gate_left[Rules.ZONE_FRONT], _gate_for(1800.0)])
	print("shield_gate_check: scale: Scout %.3f s, Fighter %.3f s, Destroyer %.3f s, Battlecruiser %.3f s" % [sc.shields.gate_left[Rules.ZONE_FRONT], _gate_for(200.0), ds.shields.gate_left[Rules.ZONE_FRONT], bc.shields.gate_left[Rules.ZONE_FRONT]])
	_put(bc)
	_put(sc)
	_put(ds)


## (b) During the gate a hit on the gated zone changes nothing; a hit on another zone drains it
## and does not gate it or end the front's gate.
func _case_during() -> void:
	var s := _ship("fighter")
	s.take_hit(_note(_front()), 80.0)
	var gate0 := s.shields.gate_left[Rules.ZONE_FRONT]
	var h0 := s.hull
	var hp0 := _hp(s)
	var vals0 := Array(s.shields.values)
	var took := s.take_hit(_note(_front()), 20.0)
	_expect(took == 0.0, "(b) a hit during the gate took %.3f from the hull" % took)
	_expect(_unchanged(s, h0, hp0), "(b) a hit during the gate changed the hull or the armour")
	_expect(Array(s.shields.values) == vals0, "(b) a hit during the gate changed the shield")
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == gate0, "(b) a hit during the gate changed the gate (%s to %s)" % [gate0, s.shields.gate_left[Rules.ZONE_FRONT]])
	_expect(s.shields.since_hit == 0.0, "(b) a hit during the gate did not restart the refill wait")
	# A big hit during the gate is swallowed whole too.
	took = s.take_hit(_note(_front()), 500.0)
	_expect(took == 0.0 and _unchanged(s, h0, hp0), "(b) a hit of 500 during the gate got through")
	# The rear zone in the same moment: drained, not gated.
	var rear0 := s.shields.values[Rules.ZONE_REAR]
	took = s.take_hit(_note(_rear()), 20.0)
	_expect(took == 0.0, "(b) a rear hit took %.3f from the hull" % took)
	_expect(absf(s.shields.values[Rules.ZONE_REAR] - (rear0 - 20.0)) < 1.0e-3, "(b) the rear zone holds %s, wanted %s" % [s.shields.values[Rules.ZONE_REAR], rear0 - 20.0])
	_expect(s.shields.gate_left[Rules.ZONE_REAR] == 0.0, "(b) a rear hit that did not break the zone started a gate")
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == gate0, "(b) the rear hit changed the front's gate")
	print("shield_gate_check: (b) during the gate: front hits of 20 and 500 swallowed, a rear hit drained the rear zone only")
	_put(s)


## (c) The gate counts down with the ticks and ends; then the empty zone lets a hit through whole,
## as a control ship with no gate lets it through.
func _case_ends() -> void:
	var s := _ship("fighter")
	s.take_hit(_note(_front()), 80.0)
	var want_ticks := ceili(_gate_for(200.0) / DT)
	var ticks := 0
	while s.shields.gate_left[Rules.ZONE_FRONT] > 0.0 and ticks < 600:
		s.shields.tick(DT, 1.0)
		ticks += 1
	_expect(absi(ticks - want_ticks) <= 1, "(c) the gate lasted %d ticks, wanted %d (plus or minus one)" % [ticks, want_ticks])
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == 0.0, "(c) the gate did not end")
	# The gate also stays correct when the world speed gives longer ticks: half the time in two ticks of the other half.
	s.shields.fill()
	s.shields.since_hit = 999.0
	_break_front(s)
	var g := s.shields.gate_left[Rules.ZONE_FRONT]
	s.shields.tick(g * 0.5, 1.0)
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] > 0.0 and absf(s.shields.gate_left[Rules.ZONE_FRONT] - g * 0.5) < 1.0e-4, "(c) half the gate's time left %s of %s" % [s.shields.gate_left[Rules.ZONE_FRONT], g])
	s.shields.tick(g * 0.5 + 0.01, 1.0)
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == 0.0, "(c) the gate did not end after its whole time")
	# After the gate: a hit passes whole through the (still empty) zone, as on a control ship.
	var c := _ship("fighter")
	c.shields.values[Rules.ZONE_FRONT] = 0.0
	s.shields.fill()
	s.shields.values[Rules.ZONE_FRONT] = 0.0
	s.hull = s.hull_max
	s.armour.a_hp = s.armour.a_max.duplicate()
	var took_s := s.take_hit(_note(_front()), 20.0)
	var took_c := c.take_hit(_note(_front()), 20.0)
	_expect(took_s > 1.0 and absf(took_s - took_c) < 1.0e-4, "(c) after the gate a hit took %.4f, the control took %.4f" % [took_s, took_c])
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == 0.0, "(c) a hit on an empty zone after the gate started a gate")
	print("shield_gate_check: (c) the gate ended after %d ticks (wanted %d); after it a hit took %.3f from the hull (control %.3f)" % [ticks, want_ticks, took_s, took_c])
	_put(s)
	_put(c)


## (d) A hit that drains a zone exactly to 0, or leaves points in it, starts no gate.
func _case_exact() -> void:
	var sh := ShieldZones.new()
	sh.setup(200.0, 10.0, 3.5)
	var back := sh.absorb(Rules.ZONE_FRONT, 50.0)
	_expect(back == 0.0 and sh.values[Rules.ZONE_FRONT] == 0.0, "(d) an exact hit left %s and gave back %s" % [sh.values[Rules.ZONE_FRONT], back])
	_expect(sh.gate_left[Rules.ZONE_FRONT] == 0.0, "(d) a hit that drained the zone exactly to 0 started a gate")
	sh.fill()
	back = sh.absorb(Rules.ZONE_FRONT, 49.0)
	_expect(back == 0.0 and absf(sh.values[Rules.ZONE_FRONT] - 1.0) < 1.0e-4, "(d) a hit that left a point left %s" % sh.values[Rules.ZONE_FRONT])
	_expect(sh.gate_left[Rules.ZONE_FRONT] == 0.0, "(d) a hit that left points started a gate")
	# The next hit on the exactly emptied zone is a break with a gate? No: the zone is empty, so it passes whole (as before).
	sh.fill()
	sh.absorb(Rules.ZONE_FRONT, 50.0)
	back = sh.absorb(Rules.ZONE_FRONT, 30.0)
	_expect(back == 30.0 and sh.gate_left[Rules.ZONE_FRONT] == 0.0, "(d) a hit on a zone emptied exactly gave back %s (wanted 30, no gate)" % back)
	# On a real ship the same, with a hit of exactly the zone's size (no resistance on a Fighter).
	var s := _ship("fighter")
	var h0 := s.hull
	s.take_hit(_note(_front()), 50.0)
	_expect(s.hull == h0 and s.shields.values[Rules.ZONE_FRONT] == 0.0 and s.shields.gate_left[Rules.ZONE_FRONT] == 0.0, "(d) a Fighter's exact hit: zone %s, gate %s" % [s.shields.values[Rules.ZONE_FRONT], s.shields.gate_left[Rules.ZONE_FRONT]])
	print("shield_gate_check: (d) an exact drain and a drain that leaves points start no gate")
	_put(s)


## (e) A full pierce never touches the shield or the gate; a half pierce that breaks a zone sends
## the piercing half to the hull and drops the soaked half's spill.
func _case_pierce() -> void:
	var s := _ship("fighter")
	var shield0 := s.shields.total()
	var h0 := s.hull
	var info := _note(_front(), Rules.W_TORP, 1.0)
	s.take_hit(info, 90.0)
	_expect(s.shields.total() == shield0 and s.shields.since_hit == 999.0, "(e) a full pierce touched the shield")
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == 0.0, "(e) a full pierce started a gate")
	_expect(h0 - s.hull > 1.0, "(e) a full pierce did not reach the hull")
	# A full pierce during a gate is not swallowed.
	_break_front(s)
	var gate0 := s.shields.gate_left[Rules.ZONE_FRONT]
	var h1 := s.hull
	var took := s.take_hit(info, 40.0)
	_expect(took > 1.0 and s.hull < h1, "(e) a full pierce during a gate was swallowed (took %.3f)" % took)
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == gate0, "(e) a full pierce during a gate changed the gate")
	# A half pierce that breaks the zone: zone value 10, a hit of 60: 30 pierce, 30 soaked (10 held, 20 spill dropped).
	var a := _ship("fighter")
	a.shields.values[Rules.ZONE_FRONT] = 10.0
	var ha := a.hull
	var ia := _note(_front(), Rules.W_TORP, 0.5)
	ia.strength = 60.0
	var took_a := a.take_hit(ia, 60.0)
	_expect(a.shields.values[Rules.ZONE_FRONT] == 0.0 and a.shields.gate_left[Rules.ZONE_FRONT] > 0.0, "(e) a half pierce that broke the zone: zone %s, gate %s" % [a.shields.values[Rules.ZONE_FRONT], a.shields.gate_left[Rules.ZONE_FRONT]])
	# The control: a ship whose zone is empty with no gate takes a full pierce of the piercing half (30), the same strength 60.
	var b := _ship("fighter")
	b.shields.values[Rules.ZONE_FRONT] = 0.0
	var ib := _note(_front(), Rules.W_TORP, 1.0)
	ib.strength = 60.0
	var took_b := b.take_hit(ib, 30.0)
	_expect(took_a > 1.0 and absf(took_a - took_b) < 1.0e-4, "(e) a half pierce took %.4f, the piercing half alone takes %.4f" % [took_a, took_b])
	_expect(absf((ha - a.hull) - took_a) < 1.0e-4, "(e) the hull lost %.4f, the hit reported %.4f" % [ha - a.hull, took_a])
	print("shield_gate_check: (e) a full pierce never gates and is never swallowed; a half pierce that broke a zone hurt the hull by %.3f (the piercing half alone: %.3f)" % [took_a, took_b])
	_put(s)
	_put(a)
	_put(b)


## (f) An ion hit that breaks a zone empties it, starts no gate and hurts no hull; the next hit of
## another kind on that empty zone passes whole.
func _case_ion() -> void:
	var s := _ship("fighter")
	var h0 := s.hull
	var hp0 := _hp(s)
	var took := s.take_hit(_note(_front(), Rules.W_ION), 300.0)
	_expect(took == 0.0 and _unchanged(s, h0, hp0), "(f) an ion hit that broke the zone hurt the hull (%.3f)" % took)
	_expect(s.shields.values[Rules.ZONE_FRONT] == 0.0, "(f) an ion hit did not empty the zone (%s)" % s.shields.values[Rules.ZONE_FRONT])
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == 0.0, "(f) an ion break started a gate (%s)" % s.shields.gate_left[Rules.ZONE_FRONT])
	var took2 := s.take_hit(_note(_front()), 20.0)
	_expect(took2 > 1.0, "(f) the next hit on the ion-emptied zone took %.3f, not whole" % took2)
	# An ion hit during another kind's gate is swallowed (the zone is immune to everything).
	var t := _ship("fighter")
	_break_front(t)
	var vals := Array(t.shields.values)
	var hulls := t.hull
	t.take_hit(_note(_front(), Rules.W_ION), 100.0)
	_expect(Array(t.shields.values) == vals and t.hull == hulls, "(f) an ion hit during a gate changed something")
	print("shield_gate_check: (f) an ion break emptied the zone, started no gate and hurt no hull; the next hit took %.3f" % took2)
	_put(s)
	_put(t)


## (g) One-pool shields keep today's spill-over and never gate.
func _case_pools() -> void:
	# A bare single pool.
	var sh := ShieldZones.new()
	sh.setup(160.0, 10.0, 4.0, true)
	var back := sh.absorb(0, 300.0)
	_expect(absf(back - 140.0) < 1.0e-4, "(g) a bare pool gave back %s of 300 on 160, wanted 140" % back)
	_expect(sh.gate_left[0] == 0.0 and sh.values[0] == 0.0, "(g) a bare pool gated or kept points")
	back = sh.absorb(0, 50.0)
	_expect(back == 50.0, "(g) a hit on the emptied pool gave back %s, wanted 50" % back)
	# A Minion.
	var m := world.spawn_minion(1, "corvette", "mid", _home + Vector2(0.0, 600.0))
	_expect(m.shields != null and m.shields.single, "(g) the corvette minion has no single pool")
	var mh := m.hull
	var pool := m.shields.values[0]
	m.take_hit(_note(Vector2(300.0, 0.0)), pool * 2.0 + 10.0)
	_expect(m.hull < mh, "(g) a minion's breaking hit did not pass its spill to the hull")
	_expect(m.shields.values[0] == 0.0 and _gates(m.shields) == 0.0, "(g) a minion's pool gated (%s)" % _gates(m.shields))
	m.hull = mh
	var h2 := m.hull
	m.take_hit(_note(Vector2(300.0, 0.0)), 10.0)
	_expect(m.hull < h2, "(g) a hit on a minion's empty pool did not pass whole")
	# The Mothership.
	var ms := world.mothership(1)
	_expect(ms.shields != null and ms.shields.single, "(g) the mothership has no single pool")
	var msh := ms.hull
	ms.shields.values[0] = 10.0
	ms.take_hit(_note(Vector2(2000.0, 0.0)), 100.0)
	_expect(ms.hull < msh, "(g) the mothership's breaking hit did not pass its spill to the hull")
	_expect(ms.shields.values[0] == 0.0 and _gates(ms.shields) == 0.0, "(g) the mothership's pool gated")
	ms.hull = msh
	ms.shields.fill()
	# A RepairBay with its defences (the 400-point pool of Structures).
	var ts: TeamState = world.teams[1]
	var was := ts.bay_defenses
	ts.bay_defenses = true
	var bay := world.spawn_bay(1, _home + Vector2(700.0, 0.0))
	bay._refresh_defenses()
	ts.bay_defenses = was
	_expect(bay.shields != null and bay.shields.single, "(g) the repair bay has no single pool")
	if bay.shields != null:
		var bh := bay.hull
		bay.shields.values[0] = 10.0
		bay.take_hit(_note(Vector2(300.0, 0.0)), 100.0)
		_expect(bay.hull < bh, "(g) the repair bay's breaking hit did not pass its spill to the hull")
		_expect(bay.shields.values[0] == 0.0 and _gates(bay.shields) == 0.0, "(g) the repair bay's pool gated")
	print("shield_gate_check: (g) a bare pool, a Minion, the Mothership and a RepairBay pass the spill to the hull and never gate")
	_put(m)
	_put(bay)


## Every zone's gate time added up.
func _gates(sh: ShieldZones) -> float:
	return sh.gate_left[0] + sh.gate_left[1] + sh.gate_left[2] + sh.gate_left[3]


## (h) A unit with no shields, and a Ship whose shield is empty before the hit, take hits as before.
func _case_no_shield() -> void:
	var s := _ship("fighter")
	s.shields = null
	var h0 := s.hull
	var took := s.take_hit(_note(_front()), 20.0)
	_expect(took > 1.0 and absf((h0 - s.hull) - took) < 1.0e-4, "(h) a unit with no shield took %.3f" % took)
	# A shield that was empty before the hit: the hit passes whole, no gate.
	var e := _ship("fighter")
	var c := _ship("fighter")
	for z in 4:
		e.shields.values[z] = 0.0
		c.shields.values[z] = 0.0
	var took_e := e.take_hit(_note(_front()), 20.0)
	_expect(took_e > 1.0 and _gates(e.shields) == 0.0, "(h) a hit on an empty shield took %.3f, gates %s" % [took_e, _gates(e.shields)])
	# A turret has no shield today: its hits go straight to the hull.
	var turret_hit := false
	for t: Turret in world.turrets:
		if t.shields == null:
			var th := t.hull
			t.take_hit(_note(Vector2(300.0, 0.0)), 5.0)
			_expect(t.hull < th, "(h) a turret with no shield did not lose hull (%s before, %s after)" % [th, t.hull])
			turret_hit = true
			break
	_expect(turret_hit, "(h) no turret without a shield was found to hit")
	_expect(took_e == c.take_hit(_note(_front()), 20.0), "(h) two empty-shield ships took different hits")
	print("shield_gate_check: (h) no shield: took %.3f; empty shield: took %.3f, no gate" % [took, took_e])
	_put(s)
	_put(e)
	_put(c)


## (i) fill() ends a running gate; set_focus() and set_max() keep it; set_max() changes the next gate.
func _case_keep() -> void:
	var s := _ship("fighter")
	_break_front(s)
	var g := s.shields.gate_left[Rules.ZONE_FRONT]
	_expect(g > 0.0, "(i) no gate to keep")
	s.shields.set_focus(Rules.FOCUS_REAR)
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == g, "(i) set_focus changed the gate (%s to %s)" % [g, s.shields.gate_left[Rules.ZONE_FRONT]])
	s.shields.set_max(400.0)
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] == g, "(i) set_max changed a running gate (%s to %s)" % [g, s.shields.gate_left[Rules.ZONE_FRONT]])
	# The next gate follows the new pool.
	_expect(absf(s.shields.gate_seconds() - _gate_for(400.0)) < 1.0e-5, "(i) after set_max(400) gate_seconds() is %s, wanted %s" % [s.shields.gate_seconds(), _gate_for(400.0)])
	s.shields.fill()
	_expect(_gates(s.shields) == 0.0, "(i) fill() left a gate running (%s)" % _gates(s.shields))
	# A new launch starts whole: dock, launch again, no gate.
	var t := _ship("fighter")
	_break_front(t)
	var p := t.profile
	var docked := world.try_dock(t, true)
	_expect(docked, "(i) the ship did not dock")
	if docked:
		var n := world.launch(p)
		_expect(n != null and _gates(n.shields) == 0.0, "(i) a launched ship started with a gate")
		if n != null:
			_put(n)
	print("shield_gate_check: (i) set_focus and set_max keep a running gate, fill() and a new launch end it")
	_put(s)


## (j) The Fighter cannon and the Lance beam on a Fighter's front zone: the rounds or ticks the gate
## swallows, and what passes whole afterwards.
func _case_weapons() -> void:
	# The Fighter cannon: 6.5 rounds a second of 5.5.
	var cd: Dictionary = Weapons.WEAPONS["fighter_cannon"]
	var rate := float(cd["rate"])
	var dmg := float(cd["dmg"])
	var s := _ship("fighter")
	var swallowed := 0
	var passed_after := 0
	var broke := false
	var broke_at := -1
	var shots := 0
	var t := 0.0
	var ticks := 0
	while ticks < 480:
		# A round leaves each time the clock passes a multiple of 1/rate.
		var fire := floorf((t + DT) * rate) > floorf(t * rate)
		if fire:
			shots += 1
			var h0 := s.hull
			var gated := s.shields.gate_left[Rules.ZONE_FRONT] > 0.0
			s.take_hit(_note(_front()), dmg)
			if broke and gated:
				swallowed += 1
				_expect(s.hull == h0, "(j) a cannon round during the gate hurt the hull")
			elif broke and not gated and s.hull < h0:
				passed_after += 1
			if not broke and s.shields.gate_left[Rules.ZONE_FRONT] > 0.0:
				broke = true
				broke_at = shots
		s.shields.tick(DT, 1.0)
		t += DT
		ticks += 1
		if passed_after >= 3:
			break
	_expect(broke, "(j) the cannon never broke the zone")
	_expect(swallowed >= 2 and swallowed <= 3, "(j) the gate swallowed %d cannon rounds, about two or three were wanted" % swallowed)
	_expect(passed_after >= 1, "(j) no cannon round passed whole after the gate")
	print("shield_gate_check: (j) the Fighter cannon: the zone broke on round %d, the gate swallowed %d rounds, %d passed whole after it" % [broke_at, swallowed, passed_after])
	_put(s)
	# The Lance beam: 34 a second in ticks of 1/60, strength 17.
	var ld: Dictionary = Weapons.WEAPONS["lance_beam"]
	var dps := float(ld["dps"])
	var b := _ship("fighter")
	var lost_ticks := 0
	var broke_tick := -1
	var pass_ticks := 0
	var n := 0
	while n < 600:
		var info := _note(_front(), Rules.W_LANCE)
		info.strength = dps * 0.5
		var gated := b.shields.gate_left[Rules.ZONE_FRONT] > 0.0
		var h0 := b.hull
		b.take_hit(info, dps * DT)
		if broke_tick >= 0 and gated:
			lost_ticks += 1
			_expect(b.hull == h0, "(j) a beam tick during the gate hurt the hull")
		elif broke_tick >= 0 and not gated and b.hull < h0:
			pass_ticks += 1
		if broke_tick < 0 and b.shields.gate_left[Rules.ZONE_FRONT] > 0.0:
			broke_tick = n
			_expect(b.hull == h0, "(j) the beam tick that broke the zone hurt the hull")
		b.shields.tick(DT, 1.0)
		n += 1
		if pass_ticks >= 5:
			break
	var want_lost := ceili(_gate_for(200.0) / DT)
	_expect(broke_tick > 0, "(j) the beam never broke the zone")
	_expect(absi(lost_ticks - want_lost) <= 2, "(j) the gate swallowed %d beam ticks, about %d were wanted" % [lost_ticks, want_lost])
	_expect(pass_ticks >= 5, "(j) the beam did not pass whole after the gate (%d ticks)" % pass_ticks)
	print("shield_gate_check: (j) the Lance beam: the zone broke on tick %d, the gate swallowed %d ticks (%.2f s), then %d ticks passed whole" % [broke_tick, lost_ticks, float(lost_ticks) * DT, pass_ticks])
	_put(b)


## (k) A hit through Combat.apply_damage on a shielded Destroyer behaves as take_hit does.
func _case_apply_damage() -> void:
	var s := _ship("destroyer")
	var t := _ship("destroyer")
	var h0 := s.hull
	var info := _note(_front())
	info.amount = 2000.0
	info.small_bonus = 1.0
	var took := world.combat.apply_damage(s, info)
	_expect(took == 0.0 and s.hull == h0, "(k) apply_damage's breaking hit hurt the hull (%.3f)" % took)
	_expect(s.shields.gate_left[Rules.ZONE_FRONT] > 0.0 and s.shields.values[Rules.ZONE_FRONT] == 0.0, "(k) apply_damage's breaking hit did not break and gate the zone")
	# A second one during the gate: swallowed (0 to the hull, shield unchanged).
	var info2 := _note(_front())
	info2.amount = 300.0
	var took2 := world.combat.apply_damage(s, info2)
	_expect(took2 == 0.0 and s.hull == h0 and s.shields.values[Rules.ZONE_FRONT] == 0.0, "(k) apply_damage's hit during the gate got through (%.3f)" % took2)
	# The same two hits through take_hit on a twin give the same shield and hull.
	var took3 := t.take_hit(info, 2000.0)
	_expect(took3 == 0.0 and t.shields.gate_left[Rules.ZONE_FRONT] > 0.0, "(k) take_hit's breaking hit on the twin: took %.3f" % took3)
	print("shield_gate_check: (k) Combat.apply_damage on a Destroyer: the breaking hit took %.3f, the hit in the gate %.3f, gate %.3f s" % [took, took2, s.shields.gate_left[Rules.ZONE_FRONT]])
	_put(s)
	_put(t)


## (l) The glow: ShipVisual's gate state and the shield picture's key.
func _case_glow() -> void:
	var s := _ship("fighter")
	var sh := s.shields
	_expect(ShipVisual.gate_mask(sh) == 0, "(l) a whole shield has gate bits %d" % ShipVisual.gate_mask(sh))
	_expect(ShipVisual.gate_mask(null) == 0, "(l) no shield has gate bits")
	var v := s.get_node_or_null("Visual") as ShipVisual
	var cache: DrawCache = v._shield if v != null else null
	if not Game.sim_only:
		_expect(cache != null, "(l) outside --sim-only the ship has no shield picture to check (visual %s)" % [v != null])
	var key0 := 0
	if cache != null:
		v._update_shield(1.0)
		key0 = cache.bits
		_expect(((key0 >> ShipVisual.GATE_BITS_SHIFT) & 15) == 0, "(l) a whole shield has gate bits in its picture's key")
		v._update_shield(1.0)
		_expect(cache.bits == key0, "(l) the key moved with nothing changed")
	_break_front(s)
	_expect(ShipVisual.gate_mask(sh) == (1 << Rules.ZONE_FRONT), "(l) the gate mask is %d while the front is gated" % ShipVisual.gate_mask(sh))
	var key1 := 0
	if cache != null:
		v._update_shield(1.0)
		key1 = cache.bits
		_expect(((key1 >> ShipVisual.GATE_BITS_SHIFT) & 15) == (1 << Rules.ZONE_FRONT), "(l) the picture's gate bits are %d while the front is gated" % ((key1 >> ShipVisual.GATE_BITS_SHIFT) & 15))
		_expect(key1 != key0, "(l) the picture's key did not change when the gate started")
		# A tick that moves the gate (but does not end it) changes no bit.
		sh.tick(DT, 1.0)
		v._update_shield(1.0)
		_expect(cache.bits == key1, "(l) the key moved while the gate only counted down")
	# The gate ends: the mask and the bits go off.
	var n := 0
	while sh.gate_left[Rules.ZONE_FRONT] > 0.0 and n < 600:
		sh.tick(DT, 1.0)
		n += 1
	_expect(ShipVisual.gate_mask(sh) == 0, "(l) the gate mask is %d after the gate" % ShipVisual.gate_mask(sh))
	if cache != null:
		v._update_shield(1.0)
		_expect(((cache.bits >> ShipVisual.GATE_BITS_SHIFT) & 15) == 0, "(l) the picture's gate bits stayed on after the gate")
		_expect(cache.bits != key1, "(l) the picture's key did not change when the gate ended")
	else:
		print("shield_gate_check: (l) no shield picture here (--sim-only): only the gate mask was checked")
	print("shield_gate_check: (l) the glow's gate state: on at the break (mask %d), off after %d ticks; the picture's key changed at both ends" % [1 << Rules.ZONE_FRONT, n])
	_put(s)


## With --shots-dir=<folder> in a window: save a picture of a Fighter with its front zone gated.
func _shot() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			dir = a.substr(12)
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	var s := _ship("fighter")
	s.global_position = _home
	_break_front(s)
	var cam := Camera2D.new()
	cam.position = _home
	cam.zoom = Vector2(6.0, 6.0)
	world.add_child(cam)
	cam.make_current()
	s.shields.gate_left[Rules.ZONE_FRONT] = 1.0
	for _i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(dir.path_join("shield_gate_fighter.png"))
	print("shield_gate_check: picture saved (error code %d)" % err)
	cam.queue_free()
	_put(s)


## Put unit `u` away in a far corner and make it dead.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()
