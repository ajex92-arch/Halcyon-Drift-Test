extends Node
## WHAT THIS IS: the check of the data the repair drones will read: the armour points
## of each section, the wound counter of each section, and the two separate repair
## calls (one for the armour, one for the hull). It prints one line per case and then
## "armour_repair_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it launches a real Battlecruiser with its shields empty, hits several
## sections, and checks:
##   - a section's wound counter is the hull damage that came through it, and the counters
##     add up to the hull the ship is missing (to within a unit per section);
##   - the sum stays right when the hull is changed behind the sections' back: a stray
##     write to the hull, and Unit.heal() (Emergency Repair's way);
##   - repair_armour() mends only the armour: the hull and the wounds stay as they were,
##     the section never goes above what it held whole, a mended black section is no
##     longer black, and the points it returns are the points really mended;
##   - repair_hull() mends only the hull (through heal(), never above hull_max): the
##     armour stays as it was, the mended points come off the named section's wound first
##     and then off the biggest wound, and the sum stays right;
##   - the hull is one number (no hull is kept per section), and the operational health
##     percent the drones' order will use is not set.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=armour_repair_check
##
## WHO USES IT: main.gd loads it for --test=armour_repair_check; run_checks runs it. It
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
	var s := _ship()
	_case_wounds(s)
	_case_stray_writes(s)
	_case_armour_repair(s)
	_case_hull_repair(s)
	_expect(ArmourSections.OPERATIONAL_HEALTH_PCT < 0, "the operational health percent is set (%d)" % ArmourSections.OPERATIONAL_HEALTH_PCT)
	print("armour_repair_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("armour_repair_check: FAIL %s" % what)


## A Battlecruiser (team 1) at home with its shields empty.
func _ship() -> Ship:
	var p := PilotProfile.new("Repair", 1, 20 + world.profiles.size(), false)
	p.hull_id = "battlecruiser"
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	for z in 4:
		s.shields.values[z] = 0.0
	return s


## Hit the ship with `amount` damage that skips the shield, from `local` in its own frame.
func _hit(s: Ship, amount: float, local: Vector2) -> float:
	var d := DamageInfo.new()
	d.amount = amount
	d.pierce = 1.0
	d.from_pos = _home + local
	return s.take_hit(d, amount)


## The sum of an array of whole numbers.
func _sum(a: PackedInt32Array) -> int:
	var t := 0
	for v in a:
		t += v
	return t


## The units of hull the ship is missing.
func _missing_units(s: Ship) -> int:
	return roundi((s.hull_max - s.hull) * 256.0)


## The wound counters follow the damage that came through each section.
func _case_wounds(s: Ship) -> void:
	var front_right := Vector2(300.0, 40.0)
	var right_nose := Vector2(100.0, 300.0)
	var a := _hit(s, 70.0, front_right)
	var b := _hit(s, 70.0, front_right)
	var c := _hit(s, 40.0, right_nose)
	var w := s.armour.wounds(s)
	var sec_a := s.armour.section_at(front_right)
	var sec_b := s.armour.section_at(right_nose)
	_expect(sec_a != sec_b, "the two points picked the same section")
	_expect(absf(float(w[sec_a]) / 256.0 - (a + b)) < 0.1, "the first section's wound is %.2f, wanted %.2f" % [float(w[sec_a]) / 256.0, a + b])
	_expect(absf(float(w[sec_b]) / 256.0 - c) < 0.1, "the second section's wound is %.2f, wanted %.2f" % [float(w[sec_b]) / 256.0, c])
	_expect(absi(_sum(w) - _missing_units(s)) <= s.armour.count, "the wounds add up to %d, the hull misses %d" % [_sum(w), _missing_units(s)])
	var others := 0
	for i in w.size():
		if i != sec_a and i != sec_b and w[i] != 0:
			others += 1
	_expect(others == 0, "%d other sections have a wound" % others)
	print("armour_repair_check: wounds %.2f and %.2f points, sum %d units, missing %d" % [float(w[sec_a]) / 256.0, float(w[sec_b]) / 256.0, _sum(w), _missing_units(s)])


## The sum stays right when the hull changes without the sections knowing.
func _case_stray_writes(s: Ship) -> void:
	s.hull -= 123.0
	var w := s.armour.wounds(s)
	_expect(absi(_sum(w) - _missing_units(s)) <= s.armour.count, "after a stray write the wounds add up to %d, the hull misses %d" % [_sum(w), _missing_units(s)])
	var healed := s.heal(50.0)
	_expect(healed == 50.0, "heal mended %s" % healed)
	var w2 := s.armour.wounds(s)
	_expect(absi(_sum(w2) - _missing_units(s)) <= s.armour.count, "after heal() the wounds add up to %d, the hull misses %d" % [_sum(w2), _missing_units(s)])
	print("armour_repair_check: stray writes keep the sum (%d units, missing %d)" % [_sum(w2), _missing_units(s)])


## repair_armour mends only the armour.
func _case_armour_repair(s: Ship) -> void:
	var sec := s.armour.section_at(Vector2(300.0, 40.0))
	# Take it to black first, then mend a part of it.
	s.armour.a_hp[sec] = 0
	var hull0 := s.hull
	var wounds0 := s.armour.wounds(s)
	var got := s.armour.repair_armour(sec, 40.0)
	_expect(absf(got - 40.0) < 0.01, "repair_armour returned %.2f for 40" % got)
	_expect(s.armour.a_hp[sec] == 40 * 256, "the section holds %d units after 40 points" % s.armour.a_hp[sec])
	_expect(not s.armour.is_black(sec), "the mended section is still black")
	_expect(s.armour.breach_time[sec] < 0.0, "a mended section still counts as breached")
	_expect(s.hull == hull0, "repair_armour changed the hull")
	_expect(s.armour.wounds(s) == wounds0, "repair_armour changed the wounds")
	# Never above whole.
	var more := s.armour.repair_armour(sec, 10000.0)
	_expect(s.armour.a_hp[sec] == s.armour.a_max[sec], "the section went above whole")
	_expect(absf(more - float(s.armour.a_max[sec] - 40 * 256) / 256.0) < 0.01, "repair_armour returned %.2f for the rest" % more)
	_expect(s.armour.repair_armour(sec, 5.0) == 0.0, "a whole section was mended")
	print("armour_repair_check: armour repair mended %.2f then %.2f points and left the hull alone" % [got, more])


## repair_hull mends only the hull.
func _case_hull_repair(s: Ship) -> void:
	var sec_a := s.armour.section_at(Vector2(300.0, 40.0))
	var sec_b := s.armour.section_at(Vector2(100.0, 300.0))
	var armour0 := s.armour.a_hp.duplicate()
	var w0 := s.armour.wounds(s)
	var hull0 := s.hull
	# Mend a little less than the first section's wound, aimed at it.
	var points := float(w0[sec_a]) / 256.0 * 0.5
	var healed := s.armour.repair_hull(s, points, sec_a)
	_expect(absf(healed - points) < 0.01, "repair_hull mended %.2f of %.2f" % [healed, points])
	_expect(absf((s.hull - hull0) - healed) < 0.01, "the hull rose by %.2f" % (s.hull - hull0))
	_expect(s.armour.a_hp == armour0, "repair_hull changed the armour")
	var w1 := s.armour.wounds(s)
	_expect(absi((w0[sec_a] - w1[sec_a]) - roundi(healed * 256.0)) <= s.armour.count, "the aimed section's wound fell by %d units, wanted about %d" % [w0[sec_a] - w1[sec_a], roundi(healed * 256.0)])
	_expect(absi(_sum(w1) - _missing_units(s)) <= s.armour.count, "the wounds add up to %d, the hull misses %d" % [_sum(w1), _missing_units(s)])
	# Mend more than that section's wound: the rest comes off the biggest wound.
	var big := float(w1[sec_a]) / 256.0 + 10.0
	var before_b := w1[sec_b]
	s.armour.repair_hull(s, big, sec_a)
	var w2 := s.armour.wounds(s)
	_expect(w2[sec_a] <= s.armour.count, "the aimed section keeps a wound of %d units" % w2[sec_a])
	_expect(w2[sec_b] < before_b, "the rest did not come off the other wound")
	_expect(absi(_sum(w2) - _missing_units(s)) <= s.armour.count, "after the second repair the wounds add up to %d, the hull misses %d" % [_sum(w2), _missing_units(s)])
	# Never above hull_max: a huge repair makes the hull whole and clears every wound.
	s.armour.repair_hull(s, 1.0e9)
	_expect(s.hull == s.hull_max, "the hull is not whole after a huge repair")
	_expect(_sum(s.armour.wounds(s)) == 0, "a whole hull still has wounds")
	_expect(typeof(s.hull) == TYPE_FLOAT and typeof(s.hull_max) == TYPE_FLOAT, "the hull is not one number")
	print("armour_repair_check: hull repair mended %.2f then the rest; the hull is one number (%s of %s)" % [healed, s.hull, s.hull_max])
