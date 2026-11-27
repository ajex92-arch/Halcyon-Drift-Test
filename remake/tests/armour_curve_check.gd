extends Node
## WHAT THIS IS: the check of the armour curve in a real hit: how much a shot
## loses in an armour section, how the section wears, and what a breached
## (black) section does. It prints one line per case and then
## "armour_curve_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it freezes the match, launches real ships, empties their
## shields so every hit reaches the armour, and sends hits through
## Unit.take_hit() (and one through Combat.apply_damage()). It checks:
##   - the design's example: a torpedo of strength 70 that skips the shield,
##     five times at a Battlecruiser's front-right section (a bow section, 0.6 of
##     a side section), does about 34, 38, 45, 58 and 70 to the hull and leaves
##     the section black on the fourth; a sixth passes whole;
##   - a Fighter's bolt (5.5) against a Battlecruiser's whole section does the
##     floor, 15 percent of the hit;
##   - GLANCING: a shot too weak for an unbroken section (W under 0.176 x A on a whole
##     section) does the floor and wears nothing: the edges per hull, gear raising the
##     edge, a section worn to 35% yielding to small guns, the tiny-hit rounding, every
##     other hit equal to the plain curve's numbers, a black section never glancing, and
##     the Elder Core's extra hit glancing by the same rule;
##   - the weakest shot of every weapon in the game against a black section
##     passes 100 percent, with no floor and no cut (the section arithmetic
##     itself, and a real hit on a real ship);
##   - the section hit is the one at the point of impact, and the others stay whole;
##   - the curve fails closed: a ship with no sections, a section lookup that finds
##     no section, and a unit whose row has none (the mothership) all hurt the
##     hull as the flat resistance always did;
##   - the Elder Core's extra hit goes through the same path: it wears armour, with
##     the original hit's impact point and a strength equal to its own amount;
##   - docking and launching again gives a new ship with every section whole.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=armour_curve_check
##
## WHO USES IT: main.gd loads it for --test=armour_curve_check; run_checks runs
## it. It changes only units of a frozen match that is thrown away.

## How close (damage points) a measured number must be to the wanted one.
const TOL := 0.8
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
	_case_design_example()
	_case_floor()
	_case_glance()
	_case_black_weakest()
	_case_section_picked()
	_case_fail_closed()
	_case_elder()
	_case_elder_glance()
	_case_docking()
	print("armour_curve_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("armour_curve_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` (team 1) and stand it still at home, facing
## east, with its shields empty so every hit reaches the armour.
func _ship(hid: String) -> Ship:
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
	return s


## A hit note of `amount` damage points for a shot from `local` (the ship's own
## frame, ship at home facing east), skipping the shield when `skip`.
func _note(amount: float, local: Vector2, skip: bool = true) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount
	d.kind = Rules.W_TORP
	d.from_pos = _home + local
	d.pierce = 1.0 if skip else 0.0
	return d


## The design's example, on a real Battlecruiser.
func _case_design_example() -> void:
	var s := _ship("battlecruiser")
	# The front-right section: the front zone's second section (a point ahead and a little to the right).
	var at := Vector2(300.0, 40.0)
	# The front-right section is a bow section: 0.6 of a side section, so it wears through on
	# the fourth torpedo and the fifth passes whole.
	var want := [34.0, 38.0, 45.0, 58.0, 70.0]
	var sec := s.armour.section_at(at)
	_expect(sec == 1, "the front-right section was %d, not 1" % sec)
	for n in 5:
		var h0 := s.hull
		s.take_hit(_note(70.0, at), 70.0)
		var took := h0 - s.hull
		_expect(absf(took - float(want[n])) <= TOL, "torpedo %d took %.2f from the hull, wanted about %s" % [n + 1, took, want[n]])
		print("armour_curve_check: torpedo %d took %.2f (wanted about %s), the section holds %d of %d" % [n + 1, took, want[n], s.armour.a_hp[sec], s.armour.a_max[sec]])
	_expect(s.armour.a_hp[sec] == 0, "the section holds %d after five torpedoes, not 0" % s.armour.a_hp[sec])
	var h1 := s.hull
	s.take_hit(_note(70.0, at), 70.0)
	_expect(absf((h1 - s.hull) - 70.0) < 0.01, "a sixth torpedo on the black section took %.3f, not 70" % (h1 - s.hull))
	# Every other section is still whole.
	for i in s.armour.count:
		if i != sec:
			_expect(s.armour.a_hp[i] == s.armour.a_max[i], "section %d was hurt" % i)
	_put(s)


## A Fighter's bolt against a whole Battlecruiser section does the floor.
func _case_floor() -> void:
	var s := _ship("battlecruiser")
	var h0 := s.hull
	s.take_hit(_note(5.5, Vector2(300.0, 40.0)), 5.5)
	var took := h0 - s.hull
	_expect(absf(took - 5.5 * 0.15) < 0.01, "a 5.5 bolt on a whole section took %.3f, wanted the floor 0.825" % took)
	print("armour_curve_check: a Fighter bolt on a whole Battlecruiser section took %.3f" % took)
	_put(s)


## The armour units that a shot of strength `w` and `amount` damage points wears from section
## `i` of `a` (0 = it glanced).
func _wear_of(a: ArmourSections, i: int, w: float, amount: float) -> int:
	var before := int(a.a_hp[i])
	a.hit(i, w, amount)
	return before - int(a.a_hp[i])


## A whole section of hull `hid` (a fresh ArmourSections), its pool the hull's own, with `gear` armour points added.
func _whole(hid: String, gear: int = 0) -> ArmourSections:
	var a := ArmourSections.make(Ships.HULLS[hid], float(Ships.HULLS[hid]["hull"]))
	a.set_gear(gear)
	return a


## GLANCING: a shot too weak for an unbroken section does the floor and wears nothing.
func _case_glance() -> void:
	# (a) 100 Fighter bolts on a whole Battlecruiser section: the floor each, the section untouched.
	var s := _ship("battlecruiser")
	var at := Vector2(300.0, 40.0)
	var sec := s.armour.section_at(at)
	var whole_hp := int(s.armour.a_hp[sec])
	var h0 := s.hull
	for _n in 100:
		s.take_hit(_note(5.5, at), 5.5)
	_expect(s.armour.a_hp[sec] == whole_hp, "100 Fighter bolts wore a whole Battlecruiser section from %d to %d" % [whole_hp, s.armour.a_hp[sec]])
	_expect(absf((h0 - s.hull) - 100.0 * 5.5 * 0.15) < 1.0, "100 Fighter bolts took %.3f from the hull, wanted about 82.5" % (h0 - s.hull))
	print("armour_curve_check: 100 Fighter bolts on a whole Battlecruiser section: hull took %.2f, the section wore %d units" % [h0 - s.hull, whole_hp - int(s.armour.a_hp[sec])])
	# The glance counts in the section's wound (the hull damage that came through it).
	_expect(s.armour.wound[sec] > 0, "a glancing shot left no wound in the section")
	_put(s)
	# (b) The edges: Battlecruiser A 75 (13.2), Destroyer A 50 (8.8), Flak Frigate A 25 (4.4), Ion Frigate A 22 (3.9).
	var bc := _whole("battlecruiser")
	_expect(_wear_of(bc, 0, 12.0, 50.0) == 0, "W 12 wore a whole Battlecruiser section")
	_expect(_wear_of(bc, 1, 14.0, 50.0) > 0, "W 14 did not wear a whole Battlecruiser section")
	var ds := _whole("destroyer")
	_expect(_wear_of(ds, 0, 8.0, 50.0) == 0, "W 8 wore a whole Destroyer section")
	_expect(_wear_of(ds, 1, 10.0, 50.0) > 0, "W 10 did not wear a whole Destroyer section")
	var fl := _whole("flak")
	_expect(_wear_of(fl, 0, 5.5, 50.0) > 0, "W 5.5 did not wear a whole Flak Frigate section")
	_expect(_wear_of(fl, 1, 3.0, 50.0) == 0, "W 3 wore a whole Flak Frigate section")
	var io := _whole("ion")
	_expect(_wear_of(io, 0, 3.5, 50.0) == 0, "W 3.5 wore a whole Ion Frigate section")
	_expect(_wear_of(io, 1, 4.5, 50.0) > 0, "W 4.5 did not wear a whole Ion Frigate section")
	# The weapons: the Fighter cannon, the Snub-Fighter gun and the battleship gun glance on a Battlecruiser;
	# the Dreadnought gun and the Lance beam (strength 17) do not.
	var line := ""
	for wid: String in ["fighter_cannon", "scout_gun", "lance_beam"]:
		if Weapons.WEAPONS.has(wid):
			var def: Dictionary = Weapons.WEAPONS[wid]
			var w := float(def["dps"]) * 0.5 if bool(def.get("beam", false)) else float(def["dmg"])
			line += "%s W %s %s; " % [wid, w, "glances" if _wear_of(_whole("battlecruiser"), 0, w, 50.0) == 0 else "wears"]
	print("armour_curve_check: on a whole Battlecruiser section: %s" % line)
	_expect(_wear_of(_whole("battlecruiser"), 0, 17.0, 50.0) > 0, "the Lance's strength 17 glanced off a whole Battlecruiser section")
	# The measured thresholds, per hull: the weakest W (steps of 0.02, a hit of 50 points so the floor does not round) that wears a whole section.
	var thr := ""
	for hid: String in Ships.ORDER:
		var a_val := int(Ships.HULLS[hid].get("armour", 0))
		var found := -1.0
		var w := 0.1
		while w < 30.0:
			if _wear_of(_whole(hid), 0, w, 50.0) > 0:
				found = w
				break
			w += 0.02
		var want := 15.0 * float(a_val) / 85.0
		thr += "%s A %d: W %.2f (formula %.2f); " % [hid, a_val, found, want]
		_expect(found > 0.0 and absf(found - want) <= maxf(0.1, want * 0.03), "%s: the glance threshold was W %.2f, the formula says %.2f" % [hid, found, want])
	print("armour_curve_check: glance thresholds: %s" % thr)
	# Light craft (A 1 to 3): a shot of W 1 wears.
	for hid: String in ["scout", "fighter", "lance", "bomber"]:
		_expect(_wear_of(_whole(hid), 0, 1.0, 50.0) > 0, "W 1 glanced off a whole %s section" % hid)
	# Gear raises A, so the threshold: both items on a Battlecruiser (A 86): W 14 glances, W 16.5 wears; ungeared W 14 wears.
	var geared := _whole("battlecruiser", ArmourSections.gear_a(75, 0.08) + ArmourSections.gear_a(75, 0.05))
	_expect(geared.armour_value == 86, "the geared Battlecruiser had A %d, not 86" % geared.armour_value)
	_expect(_wear_of(geared, 0, 14.0, 50.0) == 0, "W 14 wore a whole geared Battlecruiser section")
	_expect(_wear_of(geared, 1, 16.5, 50.0) > 0, "W 16.5 did not wear a whole geared Battlecruiser section")
	_expect(_wear_of(_whole("battlecruiser"), 0, 14.0, 50.0) > 0, "W 14 did not wear an ungeared Battlecruiser section")
	# (e) With the gear on, a black section still passes every hit whole.
	var black := _whole("battlecruiser", 11)
	black.a_hp[0] = 0
	_expect(black.hit(0, 1.0, 5.0) == 5.0, "a black geared section did not pass a W 1 hit whole")
	_expect(black.a_hp[0] == 0 and black.is_black(0), "a black geared section changed")
	# (d) A section worn to about 35% by torpedoes: the Fighter bolt now wears it, and the small guns finish it.
	var worn := _whole("battlecruiser")
	_expect(_wear_of(worn, 0, 5.5, 50.0) == 0, "a whole section was worn by a 5.5 bolt")
	var torps := 0
	while worn.a_hp[0] * 100 / worn.a_max[0] > 35 and torps < 1000:
		worn.hit(0, 70.0, 70.0)
		torps += 1
	_expect(torps < 1000, "torpedoes did not wear the section to 35%")
	var before := int(worn.a_hp[0])
	_expect(_wear_of(worn, 0, 5.5, 50.0) > 0, "a 5.5 bolt did not wear a section worn to 35%")
	var bolts := 0
	while not worn.is_black(0) and bolts < 200000:
		worn.hit(0, 5.5, 5.5)
		bolts += 1
	_expect(worn.is_black(0), "Fighter bolts did not finish a section worn to 35% (%d left after %d)" % [worn.a_hp[0], bolts])
	print("armour_curve_check: a section worn to 35%% by %d torpedoes (%d units left) was finished by %d Fighter bolts" % [torps, before, bolts])
	# (h) Every hit that does not glance does today's arithmetic (e9340527's formula), and a glance wears 0 and does the floor.
	var checked := 0
	var glanced := 0
	for hid: String in Ships.ORDER:
		for w: float in [1.0, 3.0, 5.5, 8.0, 12.0, 15.0, 17.0, 25.0, 70.0]:
			for share: int in [100, 60, 20, 5, 0]:
				var a := _whole(hid)
				a.a_hp[0] = a.a_max[0] * share / 100
				var amount := 30.0
				var ru := int(amount * 256.0)
				var wu := maxi(1, int(w * 256.0))
				var a_eff := 0
				if a.a_max[0] > 0:
					a_eff = a.armour_value * 256 * a.a_hp[0] / a.a_max[0]
				var keep := wu * 256 / (wu + a_eff)
				var by_curve := ru * keep / 256
				var floor_u := maxi(ru * 15 / 100, 1)
				var left := int(a.a_hp[0])
				var got := a.hit(0, w, amount)
				checked += 1
				var glances := left > 0 and by_curve < floor_u
				if glances:
					glanced += 1
					_expect(a.a_hp[0] == left, "%s W %s share %d: a glancing shot wore the section" % [hid, w, share])
					_expect(absf(got - float(floor_u) / 256.0) < 0.002, "%s W %s share %d: a glance took %.4f, wanted the floor %.4f" % [hid, w, share, got, float(floor_u) / 256.0])
				else:
					_expect(a.a_hp[0] == left - mini(by_curve, left), "%s W %s share %d: wear %d, wanted %d" % [hid, w, share, left - int(a.a_hp[0]), mini(by_curve, left)])
					var hull_u := mini(ru, maxi(by_curve, floor_u))
					_expect(absf(got - float(hull_u) / 256.0) < 0.002, "%s W %s share %d: hull took %.4f, wanted %.4f" % [hid, w, share, got, float(hull_u) / 256.0])
				if share == 0:
					_expect(not glances and got == amount, "%s W %s: a black section did not pass the hit whole" % [hid, w])
	print("armour_curve_check: %d hits compared with the plain curve, %d glanced, the rest took and wore exactly the curve's numbers" % [checked, glanced])
	# A tiny hit under 7 units: the floor is one unit (the rounding edge), and the glance still wears nothing.
	var tiny := _whole("battlecruiser")
	var tiny_held := int(tiny.a_hp[0])
	var tiny_got := tiny.hit(0, 5.5, 5.0 / 256.0)
	_expect(tiny.a_hp[0] == tiny_held, "a 5-unit hit wore a whole Battlecruiser section")
	_expect(absf(tiny_got - 1.0 / 256.0) < 1.0e-6, "a 5-unit glancing hit took %.6f, wanted 1 unit" % tiny_got)
	# A hull with no armour pool (a_max 0) and one with zero armour never glance.
	var none := ArmourSections.make({"sections": [1, 1, 1], "armour": 0}, 100.0)
	_expect(_wear_of(none, 0, 1.0, 10.0) > 0, "a section of A 0 glanced")


## The weakest shot of every weapon passes whole through a black section.
func _case_black_weakest() -> void:
	var weakest := 1.0e9
	var weakest_id := ""
	var checked := 0
	for wid: String in Weapons.WEAPONS.keys():
		var def: Dictionary = Weapons.WEAPONS[wid]
		var is_beam := bool(def.get("beam", false))
		# The strength of one shot, and what one hit or one tick of it delivers.
		var strength := float(def["dps"]) * 0.5 if is_beam else float(def["dmg"])
		var amount := float(def["dps"]) / 60.0 if is_beam else float(def["dmg"])
		if strength < weakest:
			weakest = strength
			weakest_id = wid
		for hid: String in Ships.ORDER:
			var a := ArmourSections.make(Ships.HULLS[hid], float(Ships.HULLS[hid]["hull"]))
			for i in a.count:
				a.a_hp[i] = 0
				var got := a.hit(i, strength, amount)
				checked += 1
				_expect(got == amount, "%s against a black %s section %d: %s of %s passed" % [wid, hid, i, got, amount])
				_expect(a.a_hp[i] == 0, "a black section changed")
	print("armour_curve_check: %d black-section hits, all passed whole; the weakest shot is %s (strength %s)" % [checked, weakest_id, weakest])
	# A real hit on a real Battlecruiser: its weakest-weapon strength against a black front-right section.
	var s := _ship("battlecruiser")
	var at := Vector2(300.0, 40.0)
	var sec := s.armour.section_at(at)
	s.armour.a_hp[sec] = 0
	var h0 := s.hull
	s.take_hit(_note(weakest, at, false), weakest)
	_expect(absf((h0 - s.hull) - weakest) < 1.0e-4, "the weakest shot on a black section took %.4f, not %s" % [h0 - s.hull, weakest])
	_put(s)


## The section hit is the one at the point of impact; the others stay whole.
func _case_section_picked() -> void:
	var s := _ship("destroyer")
	# The Destroyer: 2 front, 2 rear, 3 per side. A shot from the right side, near the tail.
	var at := Vector2(-150.0, 300.0)
	var sec := s.armour.section_at(at)
	_expect(sec >= s.armour.zone_first[Rules.ZONE_RIGHT], "the pick %d is not a right-side section" % sec)
	s.take_hit(_note(80.0, at), 80.0)
	for i in s.armour.count:
		_expect((s.armour.a_hp[i] < s.armour.a_max[i]) == (i == sec), "section %d wear is wrong (picked %d)" % [i, sec])
	# The same shot through Combat.apply_damage on a shield that is not empty goes through the shield first.
	var t := _ship("destroyer")
	for z in 4:
		t.shields.values[z] = t.shields.cap(z)
	var di := _note(80.0, at, false)
	di.kind = Rules.W_BOLT
	world.combat.apply_damage(t, di)
	_expect(t.hull == t.hull_max, "the shield did not take the hit first")
	for i in t.armour.count:
		_expect(t.armour.a_hp[i] == t.armour.a_max[i], "section %d wore under a shield that held" % i)
	_put(s)
	_put(t)


## No sections, no section found, and a unit with none all hurt the hull as the flat
## resistance always did.
func _case_fail_closed() -> void:
	var s := _ship("battlecruiser")
	s.armour = null
	s.hull_resist = 0.2
	var h0 := s.hull
	s.take_hit(_note(50.0, Vector2(300.0, 40.0)), 50.0)
	_expect(absf((h0 - s.hull) - 40.0) < 1.0e-4, "a ship with no sections took %.4f, wanted 40" % (h0 - s.hull))
	# Sections with none in the rear zone: a shot from behind finds no section.
	var t := _ship("fighter")
	t.armour = ArmourSections.make({"sections": [1, 0, 1], "armour": 50}, t.hull_max)
	t.hull_resist = 0.0
	var h1 := t.hull
	_expect(t.armour.section_at(Vector2(-100.0, 0.0)) == -1, "the rear lookup found a section")
	t.take_hit(_note(10.0, Vector2(-100.0, 0.0)), 10.0)
	_expect(absf((h1 - t.hull) - 10.0) < 1.0e-4, "a hit that found no section took %.4f, wanted 10" % (h1 - t.hull))
	for i in t.armour.count:
		_expect(t.armour.a_hp[i] == t.armour.a_max[i], "a hit that found no section wore section %d" % i)
	# The mothership's row has no sections: its flat resistance works.
	var ms := world.mothership(1)
	_expect(ms.armour == null, "the mothership has armour sections")
	for z in 4:
		ms.shields.values[z] = 0.0
	var h2 := ms.hull
	ms.take_hit(_note(100.0, Vector2(0.0, 0.0)), 100.0)
	_expect(absf((h2 - ms.hull) - 100.0 * (1.0 - ms.hull_resist)) < 1.0e-3, "the mothership took %.4f, wanted %.4f" % [h2 - ms.hull, 100.0 * (1.0 - ms.hull_resist)])
	ms.hull = ms.hull_max
	ms.shields.fill()
	print("armour_curve_check: fail-closed cases checked")
	_put(s)
	_put(t)


## The Elder Core's extra hit goes through the same path and wears armour.
func _case_elder() -> void:
	var ms := world.mothership(1)
	ms.armour = ArmourSections.make({"sections": [1, 1, 1], "armour": 50}, ms.hull_max)
	for z in 4:
		ms.shields.values[z] = 0.0
	# Where the first section sits: a hit from straight ahead of the mothership.
	var local := Vector2(2000.0, 0.0)
	var di := DamageInfo.new()
	di.amount = 100.0
	di.strength = 123.0
	di.from_pos = ms.global_position + local.rotated(ms.rotation)
	var sec := ms.armour.section_at(ArmourSections.from_spine(local, ms.spine_len))
	_expect(sec >= 0, "no section found on the mothership")
	var before := int(ms.armour.a_hp[sec])
	var took := EpicNeutralFeature.bonus_hit(ms, di, 25.0)
	_expect(ms.armour.a_hp[sec] < before, "the Elder Core's extra hit did not wear armour")
	_expect(took > 0.0, "the extra hit did nothing to the hull")
	_expect(di.strength == 123.0, "the extra hit left the note's strength at %s" % di.strength)
	# Its strength is its own amount: the same hit with strength 25 wears the same.
	var other := ArmourSections.make({"sections": [1, 1, 1], "armour": 50}, ms.hull_max)
	other.hit(sec, 25.0, 25.0)
	_expect(other.a_hp[sec] == ms.armour.a_hp[sec], "the extra hit wore %d, a hit of strength 25 wears %d" % [before - ms.armour.a_hp[sec], before - other.a_hp[sec]])
	print("armour_curve_check: Elder Core extra hit wore %d units from section %d" % [before - ms.armour.a_hp[sec], sec])
	ms.armour = null
	ms.hull = ms.hull_max
	ms.shields.fill()


## The Elder Core's extra hit has strength equal to its own amount, so it glances by the same
## rule: 25 points against a section of A 200 (the threshold is W 35) does the floor and wears nothing;
## against a black section it passes whole.
func _case_elder_glance() -> void:
	var ms := world.mothership(1)
	ms.armour = ArmourSections.make({"sections": [1, 1, 1], "armour": 200}, ms.hull_max)
	for z in 4:
		ms.shields.values[z] = 0.0
	var local := Vector2(2000.0, 0.0)
	var di := DamageInfo.new()
	di.amount = 100.0
	di.strength = 123.0
	di.from_pos = ms.global_position + local.rotated(ms.rotation)
	var sec := ms.armour.section_at(ArmourSections.from_spine(local, ms.spine_len))
	_expect(sec >= 0, "no section found on the mothership")
	var before := int(ms.armour.a_hp[sec])
	var h0 := ms.hull
	var took := EpicNeutralFeature.bonus_hit(ms, di, 25.0)
	_expect(ms.armour.a_hp[sec] == before, "the Elder Core's extra hit wore a section it should glance off (%d units)" % (before - ms.armour.a_hp[sec]))
	_expect(took > 0.0 and took < 25.0, "the glancing extra hit took %.4f from the hull" % took)
	print("armour_curve_check: Elder Core extra hit glanced off a whole section of A 200: hull took %.3f of 25, section wore %d units" % [h0 - ms.hull, before - int(ms.armour.a_hp[sec])])
	ms.armour.a_hp[sec] = 0
	var h1 := ms.hull
	EpicNeutralFeature.bonus_hit(ms, di, 25.0)
	# The mothership keeps its flat resistance after the armour, so a whole pass is 25 x (1 - resist).
	var passed := 25.0 * (1.0 - ms.hull_resist)
	_expect(absf((h1 - ms.hull) - passed) < 0.01, "the extra hit on a black section took %.4f, wanted %.4f" % [h1 - ms.hull, passed])
	ms.armour = null
	ms.hull = ms.hull_max
	ms.shields.fill()


## Docking and launching again gives a new ship with every section whole.
func _case_docking() -> void:
	var s := _ship("battlecruiser")
	for i in s.armour.count:
		s.armour.a_hp[i] = 0
	var p := s.profile
	var docked := world.try_dock(s, true)
	_expect(docked, "the ship did not dock")
	if docked:
		var n := world.launch(p)
		_expect(n != null, "the pilot did not launch again")
		if n != null:
			var whole := true
			for i in n.armour.count:
				whole = whole and n.armour.a_hp[i] == n.armour.a_max[i]
			_expect(whole, "the new ship's sections are not whole")
			_expect(n != s, "launch gave back the same ship")
			print("armour_curve_check: docking and launching again gave whole sections")
			_put(n)


## Put unit `u` away in a far corner and make it dead.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()
