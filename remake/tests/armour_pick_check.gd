extends Node
## WHAT THIS IS: the check of the armour sections' layout and pick: how many
## sections each hull has, how much armour each holds, and which section an
## impact point lands on. It prints one line per hull and then
## "armour_pick_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it reads every pilot hull's row (Ships.HULLS), builds its
## ArmourSections and checks:
##   - the counts: light craft 4 sections, corvettes 6, frigates 8, the
##     Destroyer 10, the Battlecruiser 12, and every section inside its own
##     shield zone;
##   - the armour: all sections together hold 60 percent of the hull's points
##     (in units of 1/256 point, to within one unit per section), shared by
##     weight;
##   - the pick: a point at the middle of each section's slice of its zone (the
##     zone's 90 degrees split evenly) lands on that section, and so do points
##     half a degree inside each of its borders; the point in the middle of a
##     zone's edge goes to the zone the shields pick;
##   - ties: a point exactly on a border goes to the lower section number;
##   - a circle (spine length 0) measures from the centre, a spine of 200 world
##     units from the nearest point of the spine;
##   - a hull with a capsule hit shape sorts a hit on its flank by where it is
##     along the spine (nose to tail, the same length each), the ends keep the
##     angle borders, and a spine of 0 gives exactly the old pick;
##   - a row with no `sections` gives no armour at all (null), and a lookup with
##     no section there (an empty zone) answers -1.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=armour_pick_check
##
## WHO USES IT: main.gd loads it for --test=armour_pick_check; run_checks runs
## it. It builds plain objects only and changes nothing in the match.

## The sections each hull should have: front, rear, side (per side).
const WANT := {
	"scout": [1, 1, 1], "fighter": [1, 1, 1], "lance": [1, 1, 1], "bomber": [1, 1, 1],
	"logistics": [1, 1, 2], "support": [1, 1, 2], "flak": [1, 1, 3], "ion": [1, 1, 3],
	"destroyer": [2, 2, 3], "battlecruiser": [2, 2, 4],
}
## How far (degrees) inside a border a probing point is put.
const EDGE_DEG := 0.5
## How many things have gone wrong so far.
var failures := 0


## main.gd calls this once, right after the World is built. Run the check on
## the next frame.
func setup(_w: World) -> void:
	_run.call_deferred()


## Check every hull, print the verdict and quit.
func _run() -> void:
	await get_tree().process_frame
	for hid: String in Ships.ORDER:
		_check_hull(hid)
	_check_ties()
	_check_spine()
	_check_capsule_sides()
	_check_empty()
	print("armour_pick_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("armour_pick_check: FAIL %s" % what)


## A point `r` world units from the middle, `deg` degrees from the nose, in the
## ship's own frame (+y to the right).
func _at(deg: float, r: float = 100.0) -> Vector2:
	return Vector2.from_angle(deg_to_rad(deg)) * r


## Check hull `hid`: counts, armour, and the pick at every slice's middle and
## borders.
func _check_hull(hid: String) -> void:
	var def: Dictionary = Ships.HULLS[hid]
	var hull_pts := float(def["hull"])
	var a := ArmourSections.make(def, hull_pts)
	_expect(a != null, "%s has no sections" % hid)
	if a == null:
		return
	var want: Array = WANT[hid]
	_expect(a.zone_count[0] == want[0] and a.zone_count[1] == want[1] and a.zone_count[2] == want[2] and a.zone_count[3] == want[2], "%s zone counts %s" % [hid, a.zone_count])
	_expect(a.count == int(want[0]) + int(want[1]) + 2 * int(want[2]), "%s has %d sections" % [hid, a.count])
	var sum_max := 0
	for i in a.count:
		sum_max += a.a_max[i]
		_expect(a.a_hp[i] == a.a_max[i], "%s section %d starts at %d of %d" % [hid, i, a.a_hp[i], a.a_max[i]])
	var pool := hull_pts * 0.6 * 256.0
	_expect(absf(float(sum_max) - pool) <= float(a.count), "%s holds %d units, wanted %s" % [hid, sum_max, pool])
	# The zones, in the order front, rear, left, right, with the angle (degrees from
	# the nose) of each zone's first edge and the direction the sections run in
	# (+1 = rising angle, -1 = falling): the front and the rear run left to right,
	# the sides nose to tail.
	var zones := [
		{"zone": Rules.ZONE_FRONT, "from": -45.0, "dir": 1.0},
		{"zone": Rules.ZONE_REAR, "from": 135.0, "dir": 1.0},
		{"zone": Rules.ZONE_LEFT, "from": -45.0, "dir": -1.0},
		{"zone": Rules.ZONE_RIGHT, "from": 45.0, "dir": 1.0},
	]
	var picks := 0
	for zd: Dictionary in zones:
		var z: int = zd["zone"]
		var n := a.zone_count[z]
		var step := 90.0 / float(n)
		for k in n:
			# The slice's own angles, in the order of the section numbers.
			var lo := 0.0
			if z == Rules.ZONE_FRONT:
				lo = -45.0 + float(k) * step
			elif z == Rules.ZONE_REAR:
				# The rear zone, seen from the tail, runs left to right: angle falls from 225 to 135 degrees.
				lo = 225.0 - float(k + 1) * step
			elif z == Rules.ZONE_LEFT:
				# The left zone runs from the nose edge (-45 degrees) to the tail edge (-135).
				lo = -45.0 - float(k + 1) * step
			else:
				lo = 45.0 + float(k) * step
			var mid := lo + step * 0.5
			var got := a.section_at(_at(mid))
			_expect(got == a.zone_first[z] + k, "%s zone %d slice %d: its middle (%.1f deg) picked %d, wanted %d" % [hid, z, k, mid, got, a.zone_first[z] + k])
			var inside_lo := a.section_at(_at(lo + EDGE_DEG))
			var inside_hi := a.section_at(_at(lo + step - EDGE_DEG))
			_expect(inside_lo == a.zone_first[z] + k, "%s zone %d slice %d: just inside its low border picked %d" % [hid, z, k, inside_lo])
			_expect(inside_hi == a.zone_first[z] + k, "%s zone %d slice %d: just inside its high border picked %d" % [hid, z, k, inside_hi])
			picks += 3
	print("armour_pick_check: %s %d sections (%d front, %d rear, %d per side), %d units, %d picks" % [hid, a.count, a.zone_count[0], a.zone_count[1], a.zone_count[2], sum_max, picks])


## A point exactly on a border goes to the lower section number.
func _check_ties() -> void:
	# A Battlecruiser front has two sections, the border at the nose line: a point
	# straight ahead (y = 0) is a tie and goes to section 0.
	var bc := ArmourSections.make(Ships.HULLS["battlecruiser"], 4200.0)
	_expect(bc.section_at(Vector2(100.0, 0.0)) == 0, "a tie on the nose line picked %d, wanted 0" % bc.section_at(Vector2(100.0, 0.0)))
	_expect(bc.section_at(Vector2(100.0, 0.07)) == 1, "just right of the nose line picked %d, wanted 1" % bc.section_at(Vector2(100.0, 0.07)))
	_expect(bc.section_at(Vector2(100.0, -0.07)) == 0, "just left of the nose line picked %d, wanted 0" % bc.section_at(Vector2(100.0, -0.07)))
	# A Battlecruiser side has four sections: the border at 22.5 degrees from the
	# side line has slope 106/256. The point x = 106/16, across = 256/16 = 16 is exactly on it.
	var tie := Vector2(106.0 / 16.0, 16.0)
	var right_first: int = bc.zone_first[Rules.ZONE_RIGHT]
	_expect(ShieldZones.zone_for_local(tie) == Rules.ZONE_RIGHT, "the tie point is not in the right zone")
	_expect(bc.section_at(tie) == right_first, "a tie on a side border picked %d, wanted the lower number %d" % [bc.section_at(tie), right_first])
	# The two sides of that border, a hair either way.
	_expect(bc.section_at(Vector2(106.0 / 16.0 + 0.2, 16.0)) == right_first, "just nose-ward of the border picked %d" % bc.section_at(Vector2(106.0 / 16.0 + 0.2, 16.0)))
	_expect(bc.section_at(Vector2(106.0 / 16.0 - 0.2, 16.0)) == right_first + 1, "just tail-ward of the border picked %d" % bc.section_at(Vector2(106.0 / 16.0 - 0.2, 16.0)))
	print("armour_pick_check: ties checked")


## A circle (spine length 0) measures from the centre; a spine of 200 world units
## from its nearest point.
func _check_spine() -> void:
	var p := Vector2(300.0, 40.0)
	_expect(ArmourSections.from_spine(p, 0.0) == p, "a circle changed the point")
	_expect(ArmourSections.from_spine(p, 200.0) == Vector2(200.0, 40.0), "a spine of 200 gave %s" % ArmourSections.from_spine(p, 200.0))
	_expect(ArmourSections.from_spine(Vector2(-300.0, -40.0), 200.0) == Vector2(-200.0, -40.0), "a spine of 200 behind gave a wrong point")
	_expect(ArmourSections.from_spine(Vector2(50.0, 90.0), 200.0) == Vector2(0.0, 90.0), "a point beside the spine gave a wrong point")
	# Against a long spine a hit near the nose end is a side hit, not a nose hit.
	var bc := ArmourSections.make(Ships.HULLS["battlecruiser"], 4200.0)
	var side := bc.section_at(ArmourSections.from_spine(Vector2(150.0, 60.0), 400.0))
	_expect(side >= bc.zone_first[Rules.ZONE_RIGHT], "a hit beside a long hull picked the section %d, not a side one" % side)
	print("armour_pick_check: spine checked")


## A hull with a capsule hit shape sorts a hit on its flank by where it is along
## the spine: nose to tail, four equal lengths on the Battlecruiser's side, three
## on a frigate's; the ends keep the angle borders; a spine of 0 is the old pick.
func _check_capsule_sides() -> void:
	var bc := ArmourSections.make(Ships.HULLS["battlecruiser"], 4200.0)
	var len_bc := float(Ships.HULLS["battlecruiser"]["spine"])
	var off_bc := float(Ships.HULLS["battlecruiser"]["spine_off"])
	var right_first: int = bc.zone_first[Rules.ZONE_RIGHT]
	var left_first: int = bc.zone_first[Rules.ZONE_LEFT]
	var across := float(Ships.HULLS["battlecruiser"]["hit_r"])
	# A point on the flank every 10 percent of the length (from 4 percent, so none
	# stands on a border): the four side sections in order, nose first, on both sides.
	for step in 10:
		var frac := 0.04 + 0.1 * float(step)
		var x := off_bc + len_bc * 0.5 - frac * len_bc
		var want := int(frac * 4.0)
		var got_r := bc.section_on_spine(Vector2(x, across), len_bc, off_bc)
		var got_l := bc.section_on_spine(Vector2(x, -across), len_bc, off_bc)
		_expect(got_r == right_first + want, "right flank at %d percent picked %d, wanted %d" % [int(frac * 100.0), got_r, right_first + want])
		_expect(got_l == left_first + want, "left flank at %d percent picked %d, wanted %d" % [int(frac * 100.0), got_l, left_first + want])
	# The two ends of the spine and the round ends beyond them: the angle borders.
	var nose := off_bc + len_bc * 0.5
	var tail := off_bc - len_bc * 0.5
	_expect(bc.section_on_spine(Vector2(nose + 150.0, 20.0), len_bc, off_bc) == bc.zone_first[Rules.ZONE_FRONT] + 1, "a hit ahead and right of the nose picked the wrong front section")
	_expect(bc.section_on_spine(Vector2(nose + 150.0, -20.0), len_bc, off_bc) == bc.zone_first[Rules.ZONE_FRONT], "a hit ahead and left of the nose picked the wrong front section")
	_expect(bc.section_on_spine(Vector2(tail - 150.0, 20.0), len_bc, off_bc) == bc.zone_first[Rules.ZONE_REAR] + 1, "a hit astern and right picked the wrong rear section")
	_expect(bc.section_on_spine(Vector2(tail - 150.0, -20.0), len_bc, off_bc) == bc.zone_first[Rules.ZONE_REAR], "a hit astern and left picked the wrong rear section")
	# A near-broadside hit on the round end (a side hit by angle, past an end of
	# the spine) lands on that end's section: the nose section from the nose end,
	# the tail section from the tail end, on both sides.
	var on_end := Vector2(nose + 10.0, 150.0)
	_expect(bc.section_on_spine(on_end, len_bc, off_bc) == right_first, "a side hit on the nose end did not land on the nose section")
	_expect(bc.section_on_spine(Vector2(nose + 10.0, -150.0), len_bc, off_bc) == left_first, "a left side hit on the nose end did not land on the nose section")
	_expect(bc.section_on_spine(Vector2(tail - 10.0, 150.0), len_bc, off_bc) == right_first + 3, "a side hit on the tail end did not land on the tail section")
	_expect(bc.section_on_spine(Vector2(tail - 10.0, -150.0), len_bc, off_bc) == left_first + 3, "a left side hit on the tail end did not land on the tail section")
	# A point exactly on a border between two side sections (a quarter, a half and
	# three quarters of the way from the nose) goes to the lower number.
	for k in 3:
		var border_x := nose - float(k + 1) * 0.25 * len_bc
		_expect(bc.section_on_spine(Vector2(border_x, across), len_bc, off_bc) == right_first + k, "the right border %d did not go to the lower section" % k)
		_expect(bc.section_on_spine(Vector2(border_x, -across), len_bc, off_bc) == left_first + k, "the left border %d did not go to the lower section" % k)
	# The frigate: three side sections.
	var fl := ArmourSections.make(Ships.HULLS["flak"], 1000.0)
	var len_fl := float(Ships.HULLS["flak"]["spine"])
	var off_fl := float(Ships.HULLS["flak"]["spine_off"])
	var across_fl := float(Ships.HULLS["flak"]["hit_r"])
	var fl_right: int = fl.zone_first[Rules.ZONE_RIGHT]
	for k in 3:
		var x := off_fl + len_fl * 0.5 - (float(k) + 0.5) / 3.0 * len_fl
		_expect(fl.section_on_spine(Vector2(x, across_fl), len_fl, off_fl) == fl_right + k, "flak flank slice %d picked the wrong section" % k)
	# A spine of 0 is exactly the old pick, on every angle.
	var bad := 0
	for deg in range(0, 360, 7):
		var p := Vector2.from_angle(deg_to_rad(float(deg))) * 120.0
		if bc.section_on_spine(p, 0.0, 0.0) != bc.section_at(p):
			bad += 1
	_expect(bad == 0, "a spine of 0 differs from section_at() at %d angles" % bad)
	# Points that stand on the spine itself (no side hit) are front, as in section_at().
	_expect(bc.section_on_spine(Vector2(off_bc, 0.0), len_bc, off_bc) == bc.section_at(Vector2.ZERO), "a point on the spine did not pick the old way")
	print("armour_pick_check: capsule sides checked")


## A row with no sections gives no armour; an empty zone gives -1.
func _check_empty() -> void:
	_expect(ArmourSections.make({"hull": 100.0}, 100.0) == null, "a row with no sections made armour")
	_expect(ArmourSections.make({"sections": [0, 0, 0]}, 100.0) == null, "a row of no sections made armour")
	var odd := ArmourSections.make({"sections": [1, 0, 1]}, 100.0)
	_expect(odd != null and odd.section_at(Vector2(-100.0, 0.0)) == -1, "the empty rear zone did not answer -1")
	print("armour_pick_check: empty rows checked")
