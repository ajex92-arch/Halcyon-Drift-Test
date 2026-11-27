extends Node
## WHAT THIS IS: the check of gear and research against the armour sections: gear
## raises the armour value A (instead of cutting the hull after the armour), and
## the armour pool follows the hull when research makes it bigger. It prints one
## line per case and then "armour_gear_check: N failures" (0 means all is as it
## should be).
##
## HOW IT WORKS: it freezes the match, launches real ships, gives them the
## Armored Flight Suit and the Command Throne, and sends hits through
## Unit.take_hit(). It checks:
##   - the armour points of each item (ArmourSections.gear_a) for every hull, and
##     that two items add their points;
##   - a shot of the Fighter cannon loses about the item's share more at full armour
##     with the gear on (its wear on the section: the armour curve's own number),
##     on a Fighter too, where whole points round the share;
##   - on a black section the gear does nothing: the hit passes whole, the same as with
##     no gear;
##   - no gear gives A exactly as the hull's row, with no cut after the armour;
##   - a hull with no sections keeps gear's cut after the armour (fail closed);
##   - buying or losing gear mid-life changes A at once and leaves the pool as it is;
##   - research that grows the hull grows every section's armour so all sections
##     together hold 60 percent of the new hull, each keeps its share, a black section
##     stays black, and a new ship is whole.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=armour_gear_check
##
## WHO USES IT: main.gd loads it for --test=armour_gear_check; run_checks runs
## it. It changes only units of a frozen match that is thrown away.

## The Armored Flight Suit, a gear item that carries a hull resist (8%).
const SUIT := "suit_armored"
## The Command Throne, the other gear item that carries a hull resist (5%).
const CHAIR := "chair_command"
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
	_case_table()
	_case_cut_wear()
	_case_fighter()
	_case_black()
	_case_no_gear()
	_case_no_sections()
	_case_mid_life()
	_case_research()
	_case_research_black()
	print("armour_gear_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("armour_gear_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` (team 1) and stand it still at home, facing
## east, with its shields empty so every hit reaches the armour. `gear`: the ids of
## the gear items it carries.
func _ship(hid: String, gear: Array = []) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 20 + world.profiles.size(), false)
	p.hull_id = hid
	for i in gear.size():
		p.inventory[i] = {"id": gear[i], "count": 1}
	p.gear_changed()
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
## frame, ship at home facing east), skipping the shield.
func _note(amount: float, local: Vector2) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount
	d.kind = Rules.W_TORP
	d.from_pos = _home + local
	d.pierce = 1.0
	return d


## The front section's armour units a shot of strength `w` wears from ship `s`.
func _wear(s: Ship, w: float) -> int:
	var sec := s.armour.section_at(Vector2(300.0, 0.0))
	var before := int(s.armour.a_hp[sec])
	s.take_hit(_note(w, Vector2(300.0, 0.0)), w)
	return before - int(s.armour.a_hp[sec])


## The armour points of both items on every hull, and that two items add up.
func _case_table() -> void:
	var line := ""
	for hid: String in Ships.ORDER:
		var a := int(Ships.HULLS[hid].get("armour", 0))
		var gs := ArmourSections.gear_a(a, 0.08)
		var gc := ArmourSections.gear_a(a, 0.05)
		line += "%s A=%d suit +%d throne +%d; " % [hid, a, gs, gc]
		var s := _ship(hid, [SUIT, CHAIR])
		_expect(s.armour.armour_base == a, "%s base armour was %d, not %d" % [hid, s.armour.armour_base, a])
		_expect(s.armour.armour_value == a + gs + gc, "%s with both items had A %d, wanted %d" % [hid, s.armour.armour_value, a + gs + gc])
		_put(s)
	_expect(ArmourSections.gear_a(75, 0.0) == 0, "no resist gave armour points")
	print("armour_gear_check: A_gear per hull: %s" % line)


## At full armour a shot of the reference gun (the Fighter cannon, strength 5.5) wears
## the section about the item's share less: (W + A) / (W + A + A_gear) = 1 - g. The curve keeps
## a whole number of 256ths of the hit, which at a thick armour makes the measured
## share coarser, so the check allows five points either way. It reads the hulls where a 5.5
## shot does not glance (Flak Frigate A 25, Ion Frigate A 22, Logistics Corvette A 10): on the
## Destroyer (A 50) and the Battlecruiser (A 75) a 5.5 shot glances and wears nothing, ungeared or
## geared, by design (the glancing rule), so their small-gun wear is checked to be zero.
func _case_cut_wear() -> void:
	for hid: String in ["destroyer", "battlecruiser"]:
		for item: String in [SUIT, CHAIR]:
			var plain := _ship(hid)
			var geared := _ship(hid, [item])
			var w_plain := _wear(plain, 5.5)
			var w_gear := _wear(geared, 5.5)
			_expect(w_plain == 0 and w_gear == 0, "%s with %s: a 5.5 shot wore %d ungeared and %d geared, wanted 0 (it glances)" % [hid, item, w_plain, w_gear])
			_put(plain)
			_put(geared)
	print("armour_gear_check: a 5.5 shot glances on the Destroyer and the Battlecruiser, geared or not (wear 0)")
	for hid: String in ["flak", "ion", "logistics"]:
		for item: String in [SUIT, CHAIR]:
			var g := float(Items.ITEMS[item]["stats"]["hull_resist"])
			var plain := _ship(hid)
			var geared := _ship(hid, [item])
			var w_plain := _wear(plain, 5.5)
			var w_gear := _wear(geared, 5.5)
			var ratio := float(w_gear) / float(maxi(1, w_plain))
			_expect(absf(ratio - (1.0 - g)) < 0.05, "%s with %s: the 5.5 shot wore %.3f of the ungeared wear, wanted %.2f" % [hid, item, ratio, 1.0 - g])
			print("armour_gear_check: %s with %s, a 5.5 shot wears %.3f of the ungeared wear (1 - g = %.2f)" % [hid, item, ratio, 1.0 - g])
			_put(plain)
			_put(geared)


## On a Fighter (A 1) one whole point rounds the share: the geared Fighter takes less from a
## Fighter cannon shot at full armour, about the share less.
func _case_fighter() -> void:
	var plain := _ship("fighter")
	var geared := _ship("fighter", [SUIT])
	var h0 := plain.hull
	plain.take_hit(_note(5.5, Vector2(300.0, 0.0)), 5.5)
	var d_plain := h0 - plain.hull
	var h1 := geared.hull
	geared.take_hit(_note(5.5, Vector2(300.0, 0.0)), 5.5)
	var d_gear := h1 - geared.hull
	var ratio := d_gear / d_plain
	_expect(d_gear < d_plain, "the geared Fighter took %.3f, no less than the ungeared %.3f" % [d_gear, d_plain])
	_expect(absf(ratio - 0.92) < 0.07, "the geared Fighter's hull took %.3f of the ungeared hit, wanted about 0.92" % ratio)
	_expect(geared.hull_resist == 0.0, "the geared Fighter kept a cut after the armour (%.3f)" % geared.hull_resist)
	print("armour_gear_check: Fighter cannon on a Fighter: %.3f ungeared, %.3f with the suit (ratio %.3f)" % [d_plain, d_gear, ratio])
	_put(plain)
	_put(geared)


## A black section has no armour in force: the gear changes nothing.
func _case_black() -> void:
	for amount: float in [5.5, 70.0]:
		var plain := _ship("battlecruiser")
		var geared := _ship("battlecruiser", [SUIT, CHAIR])
		for s: Ship in [plain, geared]:
			for i in s.armour.count:
				s.armour.a_hp[i] = 0
		var h0 := plain.hull
		plain.take_hit(_note(amount, Vector2(300.0, 40.0)), amount)
		var h1 := geared.hull
		geared.take_hit(_note(amount, Vector2(300.0, 40.0)), amount)
		_expect(absf((h0 - plain.hull) - amount) < 0.01, "a black section let %.3f of %.1f through" % [h0 - plain.hull, amount])
		_expect(absf((h1 - geared.hull) - (h0 - plain.hull)) < 1.0e-4, "gear changed a hit on a black section: %.4f against %.4f" % [h1 - geared.hull, h0 - plain.hull])
		_put(plain)
		_put(geared)
	print("armour_gear_check: gear does nothing on a black section")


## No gear: A is the hull's row, there is no cut after the armour, and a hit is the
## curve's number alone.
func _case_no_gear() -> void:
	var s := _ship("battlecruiser")
	_expect(s.armour.armour_gear == 0, "no gear gave %d armour points" % s.armour.armour_gear)
	_expect(s.armour.armour_value == 75, "no gear gave A %d, not 75" % s.armour.armour_value)
	_expect(s.hull_resist == 0.0, "no gear gave a cut after the armour (%.3f)" % s.hull_resist)
	# A Battlecruiser's bow section holds 0.6 of a side section, so it wears through on the
	# fourth torpedo and the fifth passes whole.
	var want := [34.0, 38.0, 45.0, 58.0, 70.0]
	var at := Vector2(300.0, 40.0)
	for n in 5:
		var h0 := s.hull
		s.take_hit(_note(70.0, at), 70.0)
		_expect(absf((h0 - s.hull) - float(want[n])) <= 0.8, "torpedo %d took %.2f, wanted about %s" % [n + 1, h0 - s.hull, want[n]])
	_put(s)
	print("armour_gear_check: no gear gives the design example as before")


## A hull with no sections keeps gear's cut after the armour, as before.
func _case_no_sections() -> void:
	var s := _ship("fighter", [SUIT, CHAIR])
	s.def = s.def.duplicate()
	s.def.erase("sections")
	s.armour = null
	s.recompute_stats(false)
	_expect(absf(s.hull_resist - 0.13) < 1.0e-6, "a hull with no sections had a cut of %.4f, wanted 0.13" % s.hull_resist)
	var h0 := s.hull
	s.take_hit(_note(10.0, Vector2(300.0, 0.0)), 10.0)
	_expect(absf((h0 - s.hull) - 8.7) < 1.0e-4, "a hull with no sections took %.4f, wanted 8.7" % (h0 - s.hull))
	print("armour_gear_check: a hull with no sections keeps the cut")
	_put(s)


## Gear bought or lost mid-life changes A at once; the pool follows only the hull (the suit's +5% hull).
func _case_mid_life() -> void:
	var s := _ship("destroyer")
	var maxes := s.armour.a_max.duplicate()
	var sec := s.armour.section_at(Vector2(300.0, 0.0))
	_wear(s, 20.0)
	var held := s.armour.a_hp.duplicate()
	var p := s.profile
	_expect(s.armour.armour_value == 50, "before buying, A was %d" % s.armour.armour_value)
	p.inventory[0] = {"id": SUIT, "count": 1}
	p.gear_changed()
	s.recompute_stats(false)
	var want := 50 + ArmourSections.gear_a(50, 0.08)
	_expect(s.armour.armour_value == want, "after buying the suit A was %d, wanted %d" % [s.armour.armour_value, want])
	p.inventory[1] = {"id": CHAIR, "count": 1}
	p.gear_changed()
	s.recompute_stats(false)
	want += ArmourSections.gear_a(50, 0.05)
	_expect(s.armour.armour_value == want, "after buying the throne A was %d, wanted %d" % [s.armour.armour_value, want])
	p.inventory[0] = {}
	p.inventory[1] = {}
	p.gear_changed()
	s.recompute_stats(false)
	_expect(s.armour.armour_value == 50, "after losing the gear A was %d, not 50" % s.armour.armour_value)
	# The suit's +5% hull moved the pool with the hull (item 2); with the gear gone the hull is back, and the pool is within rounding of where it began.
	var drift := 0
	for i in s.armour.count:
		drift = maxi(drift, absi(s.armour.a_max[i] - int(maxes[i])))
		drift = maxi(drift, absi(s.armour.a_hp[i] - int(held[i])))
	_expect(drift <= 2, "gear left the pool %d units off after it was lost (section %d)" % [drift, sec])
	print("armour_gear_check: gear bought and lost mid-life moves A at once, not the pool")
	_put(s)


## The sum of a ship's section maxima, in armour units.
func _pool(s: Ship) -> int:
	var sum := 0
	for i in s.armour.count:
		sum += s.armour.a_max[i]
	return sum


## Research that makes the hull bigger (the two +15% hull items of a class: levels add, so
## 1 + 0.15 x level) grows every section's armour: together they stay 60% of the hull,
## and each section keeps its share of armour. A hull that shrinks again follows too.
func _case_research() -> void:
	for hid: String in ["fighter", "flak", "battlecruiser"]:
		var s := _ship(hid)
		var tier: String = Tech.TIERS[s.size_class]
		var base_hull := s.hull_max
		var sec := s.armour.section_at(Vector2(300.0, 0.0))
		s.armour.a_hp[sec] = s.armour.a_max[sec] / 2
		var share_before := float(s.armour.a_hp[sec]) / float(s.armour.a_max[sec])
		for level in [1, 2, 0]:
			world.teams[1].armor[tier] = level
			s.recompute_stats(false)
			var want_hull := base_hull * (1.0 + 0.15 * float(level))
			_expect(absf(s.hull_max - want_hull) < 0.01, "%s level %d: the hull was %.2f, wanted %.2f" % [hid, level, s.hull_max, want_hull])
			var want_pool := int(s.hull_max * 60.0 * 256.0 / 100.0)
			_expect(absi(_pool(s) - want_pool) <= s.armour.count, "%s level %d: the sections hold %d units, wanted %d (60%% of the hull)" % [hid, level, _pool(s), want_pool])
			var share := float(s.armour.a_hp[sec]) / float(s.armour.a_max[sec])
			_expect(absf(share - share_before) < 0.001, "%s level %d: the worn section's share went from %.4f to %.4f" % [hid, level, share_before, share])
			for i in s.armour.count:
				if i != sec:
					_expect(s.armour.a_hp[i] == s.armour.a_max[i], "%s level %d: whole section %d was not whole" % [hid, level, i])
			print("armour_gear_check: %s research level %d: hull %.1f, sections hold %d units (60%% of the hull is %d), the worn section keeps %.3f" % [hid, level, s.hull_max, _pool(s), want_pool, share])
		world.teams[1].armor[tier] = 0
		_put(s)
	# A new ship (docking and launching again) is whole at the researched size.
	var t := _ship("destroyer")
	var dtier: String = Tech.TIERS[t.size_class]
	world.teams[1].armor[dtier] = 2
	t.recompute_stats(false)
	for i in t.armour.count:
		t.armour.a_hp[i] = 0
	var p := t.profile
	_expect(world.try_dock(t, true), "the ship did not dock")
	var n := world.launch(p)
	_expect(n != null, "the pilot did not launch again")
	if n != null:
		var whole := true
		for i in n.armour.count:
			whole = whole and n.armour.a_hp[i] == n.armour.a_max[i]
		_expect(whole, "the new researched ship's sections are not whole")
		_expect(absi(_pool(n) - int(n.hull_max * 60.0 * 256.0 / 100.0)) <= n.armour.count, "the new ship's pool is %d for a hull of %.1f" % [_pool(n), n.hull_max])
		_put(n)
	world.teams[1].armor[dtier] = 0
	print("armour_gear_check: a new ship at research level 2 is whole, its pool 60% of its hull")


## A black section stays black when research grows the hull, and a section with any armour
## left does not turn black when it shrinks again.
func _case_research_black() -> void:
	var s := _ship("destroyer")
	var tier: String = Tech.TIERS[s.size_class]
	s.armour.a_hp[0] = 0
	s.armour.a_hp[1] = 1
	world.teams[1].armor[tier] = 2
	s.recompute_stats(false)
	_expect(s.armour.is_black(0), "a black section came back after research")
	_expect(s.armour.a_hp[1] >= 1 and not s.armour.is_black(1), "a nearly black section turned black after research")
	world.teams[1].armor[tier] = 0
	s.recompute_stats(false)
	_expect(s.armour.is_black(0), "a black section came back after the research was lost")
	_expect(not s.armour.is_black(1), "a nearly black section turned black when the hull shrank")
	print("armour_gear_check: a black section stays black through research")
	_put(s)


## Put unit `u` away in a far corner and make it dead.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()
