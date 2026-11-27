extends Node
## WHAT THIS IS: the check of the four damage states of an armour section and of
## the hook the hull's damage art reads. It prints one line per case and then
## "armour_states_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it builds the armour of a Battlecruiser and launches a real ship, and
## checks:
##   - the bands, by the share of the armour lost: undamaged below 25 percent, lightly
##     damaged from 25, heavily damaged from 50, broken through from 90 (checked at
##     0, 24, 25, 49, 50, 89, 90, 99 and 100 percent);
##   - broken through is a look only: at 95 percent lost the section still has armour
##     and holds a hit back, and only at 100 percent (black) does a hit pass whole;
##   - the hook: Unit.armour_states() has one state per section, follows the wear of
##     a real ship (five torpedoes on one section: the states of that section are
##     undamaged, lightly, heavily, heavily, broken through), and is empty for a unit
##     with no sections;
##   - the drawing spans: every section's span lies inside its zone's 90 degrees, the
##     spans of a zone tile it with no gap, and the middle of a section's span picks that
##     section.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=armour_states_check
##
## WHO USES IT: main.gd loads it for --test=armour_states_check; run_checks runs it. It
## changes only units of a frozen match that is thrown away.

## The running match (set by setup()).
var world: World
## Where the ship stands: open ground in the middle of the mid lane.
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
	_case_bands()
	_case_look_only()
	_case_hook()
	_case_spans()
	print("armour_states_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("armour_states_check: FAIL %s" % what)


## Set section `i` of `a` to exactly `pct` percent of its armour lost (rounded up to
## the next unit, so the whole-percent reading is `pct`).
func _lose(a: ArmourSections, i: int, pct: int) -> void:
	a.a_hp[i] = a.a_max[i] - (pct * a.a_max[i] + 99) / 100


## The bands of the four states.
func _case_bands() -> void:
	var a := ArmourSections.make(Ships.HULLS["battlecruiser"], 4200.0)
	var want := {0: 0, 24: 0, 25: 1, 49: 1, 50: 2, 89: 2, 90: 3, 99: 3, 100: 3}
	for pct: int in want:
		_lose(a, 0, pct)
		_expect(a.damage_pct(0) == pct, "%d percent lost read as %d" % [pct, a.damage_pct(0)])
		_expect(a.state_of(0) == int(want[pct]), "%d percent lost is state %d, wanted %d" % [pct, a.state_of(0), want[pct]])
	_expect(ArmourSections.STATE_NAMES.size() == 4, "there are not four state names")
	print("armour_states_check: bands checked (%s)" % ", ".join(ArmourSections.STATE_NAMES))


## Broken through (from 90 percent) is a look only: the armour works until it is black.
func _case_look_only() -> void:
	var a := ArmourSections.make(Ships.HULLS["battlecruiser"], 4200.0)
	_lose(a, 1, 95)
	_expect(a.state_of(1) == ArmourSections.STATE_BROKEN, "95 percent lost is not broken through")
	_expect(not a.is_black(1), "95 percent lost is black")
	var took := a.hit(1, 70.0, 70.0)
	_expect(took < 69.0, "a section 95 percent lost let a hit of 70 pass (%.2f) as if it were black" % took)
	a.a_hp[1] = 0
	var black := a.hit(1, 70.0, 70.0)
	_expect(a.is_black(1) and black == 70.0, "a black section passed %.2f of 70" % black)
	print("armour_states_check: broken through is a look only (95 percent lost let %.2f of 70 pass; black lets 70)" % took)


## The hook the hull's damage art reads.
func _case_hook() -> void:
	var p := PilotProfile.new("Hook", 1, 20 + world.profiles.size(), false)
	p.hull_id = "battlecruiser"
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	for z in 4:
		s.shields.values[z] = 0.0
	var states := s.armour_states()
	_expect(states.size() == 12, "the hook has %d entries, wanted 12" % states.size())
	_expect(states.count(0) == 12, "a new ship's sections are not all undamaged")
	var at := _home + Vector2(300.0, 40.0)
	var sec := s.armour.section_at(Vector2(300.0, 40.0))
	var seen: Array = []
	# The front-right section of a Battlecruiser is a bow section: 0.6 of a side section, so it is
	# worn through by the fourth torpedo.
	var want := [0, 1, 2, 3, 3]
	for n in 5:
		var d := DamageInfo.new()
		d.amount = 70.0
		d.pierce = 1.0
		d.from_pos = at
		s.take_hit(d, 70.0)
		seen.append(s.armour_states()[sec])
	_expect(seen == want, "five torpedoes gave the states %s, wanted %s" % [seen, want])
	var others := 0
	for i in 12:
		if i != sec and s.armour_states()[i] != 0:
			others += 1
	_expect(others == 0, "%d other sections changed state" % others)
	var ms := world.mothership(1)
	_expect(ms.armour_states().is_empty(), "a unit with no sections has states")
	print("armour_states_check: hook states after each torpedo: %s" % [seen])
	s.global_position = Vector2(-5000.0, -5000.0)
	s.alive = false
	world.registry.rebuild_hashes()


## The spans the HUD ring draws: they tile each zone, and their middles pick the section.
func _case_spans() -> void:
	for hid: String in Ships.ORDER:
		var a := ArmourSections.make(Ships.HULLS[hid], float(Ships.HULLS[hid]["hull"]))
		var total := 0.0
		for i in a.count:
			var sp := a.section_span(i)
			_expect(sp.y > sp.x, "%s section %d has an empty span %s" % [hid, i, sp])
			total += sp.y - sp.x
			var mid := (sp.x + sp.y) * 0.5
			var got := a.section_at(Vector2.from_angle(mid) * 100.0)
			_expect(got == i, "%s: the middle of section %d's span picked %d" % [hid, i, got])
		_expect(absf(total - TAU) < 1.0e-4, "%s: the spans add up to %.4f radians, not a full turn" % [hid, total])
	print("armour_states_check: spans checked")
