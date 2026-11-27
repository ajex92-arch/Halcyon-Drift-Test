extends Node
## WHAT THIS IS: the check of the part rows (ShipParts): the parts of the four big hulls, their
## classes, host sections, health and which light parts are exposed. It prints the parts and the
## exposure table (the exposed light parts at part radii 30, 40 and 60) and then
## "parts_data_check: N checks, K failures" (and, only when K is 0, "parts_data_check: 0 failures").
##
## HOW IT WORKS: it builds the normal match and freezes it. For each hull it builds the rows
## from the hull's own armour sections and tests them against what the hull row's `mounts` say
## (the counts are derived from the row at run time, never from a literal list): one part for
## each mount with the right class, two pods and a sensor, every part with a host section inside
## the hull's section count, positive whole-number health, the exposure sets growing with the
## radius, the pods mirrored and inside the hull. A part on a hull's centre line (found by its
## offset, never by an id) is hosted in the front zone's sections when it is ahead of the
## spine's middle and in the rear zone's when it is behind, and a few points on the
## Battlecruiser's spine are tried the same way. A hull that is not one of the four gets no
## parts; with the parts switch off a launched ship has none, with it on it has the rows.
## It loads the new classes only through ResourceLoader and calls them with no static type, so
## on a build without them it prints FAIL lines and still runs to its last line.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=parts_data_check
##
## WHO USES IT: main.gd loads it for --test=parts_data_check; run_checks runs it. It only reads
## the game: the match stands still.

## The hulls that carry parts.
const WITH_PARTS := ["flak", "ion", "destroyer", "battlecruiser"]
## Hulls that must get no parts.
const WITHOUT := ["scout", "fighter", "lance", "bomber", "logistics", "support"]
## The part radii the exposure table is printed at.
const RADII := [30.0, 40.0, 60.0]
## Where the new class lives.
const PARTS_PATH := "res://scripts/data/ship_parts.gd"

## The running match (set by setup()).
var world: World
## How many checks were made.
var checks := 0
## How many went wrong.
var failures := 0
## The ShipParts script, or null when this build has none.
var _sp = null
## What went wrong with the parts on a hull's centre line, over all four hulls ("" when nothing did).
var _centre_bad := ""


## main.gd calls this once, right after the World is built. Freeze the match and start the run
## on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Count one check and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("parts_data_check: FAIL %s" % what)


## Count one named case: print "PASS name" for a good one and "FAIL name: what" for a bad one.
func _case(ok: bool, case_name: String, what: String = "") -> void:
	checks += 1
	if ok:
		print("parts_data_check: PASS %s" % case_name)
	else:
		failures += 1
		print("parts_data_check: FAIL %s: %s" % [case_name, what])


## Run every group, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	if ResourceLoader.exists(PARTS_PATH):
		_sp = load(PARTS_PATH)
	_expect(_sp != null, "ShipParts (ship_parts.gd) is missing from this build")
	if _sp != null:
		for hid: String in WITH_PARTS:
			_check_hull(hid)
		_case(_centre_bad == "", "centre line: hosted by x", _centre_bad)
		_case_centre_points()
		for hid: String in WITHOUT:
			_check_none(hid)
		_check_launch()
	print("parts_data_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("parts_data_check: 0 failures")
	get_tree().quit()


## True when mount weapon `wid` is a light part (point defence or flak).
func _is_light(wid: String) -> bool:
	var k := Weapons.kind_id(Weapons.get_def(wid))
	return k == Rules.W_PD or k == Rules.W_FLAK


## The part rows of hull `hid` for part radius `r`.
func _rows(hid: String, r: float) -> Array:
	var def: Dictionary = Ships.get_def(hid)
	var armour := ArmourSections.make(def, float(def["hull"]))
	return _sp.build(hid, armour, r)


## Test one hull's rows against its row in ships.gd, print them and the exposure table.
func _check_hull(hid: String) -> void:
	var def: Dictionary = Ships.get_def(hid)
	var armour := ArmourSections.make(def, float(def["hull"]))
	var rows: Array = _sp.build(hid, armour)
	var mounts: Array = def["mounts"]
	var want_light := 0
	var want_main := 0
	for m: Dictionary in mounts:
		if _is_light(String(m["w"])):
			want_light += 1
		else:
			want_main += 1
	var got := {0: 0, 1: 0, 2: 0, 3: 0}
	for row: Dictionary in rows:
		got[int(row["cls"])] = int(got[int(row["cls"])]) + 1
	_expect(rows.size() == mounts.size() + 3, "%s: %d parts, wanted %d mounts + 2 pods + 1 sensor" % [hid, rows.size(), mounts.size()])
	_expect(int(got[0]) == want_light, "%s: %d light parts, the row's mounts say %d" % [hid, int(got[0]), want_light])
	_expect(int(got[1]) == want_main, "%s: %d main parts, the row's mounts say %d" % [hid, int(got[1]), want_main])
	_expect(int(got[2]) == 2 and int(got[3]) == 1, "%s: %d pods and %d sensors, wanted 2 and 1" % [hid, int(got[2]), int(got[3])])
	print("parts_data_check: %s has %d parts: %d light, %d main, 2 pods, 1 sensor (hull %d, armour %d, %d sections)" % [hid, rows.size(), int(got[0]), int(got[1]), int(def["hull"]), int(def["armour"]), armour.count])
	# Every mount has its part, in the right class; every part has a host section and whole-number health.
	for i in mounts.size():
		var found := false
		for row: Dictionary in rows:
			if int(row["mount"]) == i:
				found = true
				var light := _is_light(String((mounts[i] as Dictionary)["w"]))
				_expect((int(row["cls"]) == 0) == light, "%s: mount %d has the wrong class %d" % [hid, i, int(row["cls"])])
		_expect(found, "%s: mount %d has no part" % [hid, i])
	for row: Dictionary in rows:
		var id := String(row["id"])
		var sec := int(row["sec"])
		_expect(sec >= 0 and sec < armour.count, "%s %s: host section %d is outside the %d sections" % [hid, id, sec, armour.count])
		_expect(int(row["hp_max"]) > 0, "%s %s: health %d is not above 0" % [hid, id, int(row["hp_max"])])
		_expect(typeof(row["hp_max"]) == TYPE_INT and typeof(row["plate"]) == TYPE_INT and typeof(row["climb"]) == TYPE_INT, "%s %s: the numbers are not whole" % [hid, id])
		var cls := int(row["cls"])
		if cls == 0:
			_expect(int(row["plate"]) == int(def["armour"]) * 64, "%s %s: the plate is %d, wanted armour x 64" % [hid, id, int(row["plate"])])
		_expect(int(row["climb"]) == (1800 if cls == 2 else 1200), "%s %s: climb %d ticks" % [hid, id, int(row["climb"])])
		var off: Vector2 = row["off"]
		print("parts_data_check:   %-7s %-6s at (%7.1f, %7.1f) section %d hp %d%s depth %.1f%s" % [id, _sp.CLASS_NAMES[cls], off.x, off.y, sec, int(row["hp_max"]),
			" plate %d" % int(row["plate"]) if cls == 0 else "", float(row["depth"]), " EXPOSED" if bool(row["exposed"]) else ""])
	# The parts on the hull's centre line (exactly on its spine) sit in the front zone's sections when they
	# are ahead of the spine's middle and in the rear zone's when they are behind it.
	var spine := float(def.get("spine", 0.0))
	var spine_off := float(def.get("spine_off", 0.0))
	var centre_ids := ""
	for row: Dictionary in rows:
		var c_off: Vector2 = row["off"]
		if spine > 0.0 and c_off.y == 0.0 and absf(c_off.x - spine_off) <= spine * 0.5:
			centre_ids += " " + String(row["id"])
			var zone: int = Rules.ZONE_REAR if c_off.x < spine_off else Rules.ZONE_FRONT
			var first := int(armour.zone_first[zone])
			var c_sec := int(row["sec"])
			if c_sec < first or c_sec >= first + int(armour.zone_count[zone]):
				_centre_bad += "%s %s at x %.1f is in section %d, outside zone %d's sections; " % [hid, String(row["id"]), c_off.x, c_sec, zone]
	print("parts_data_check: centre-line parts: %s%s" % [hid, centre_ids])
	# The pods: mirrored, behind the middle, inside the hull's hit shape; a proposed offset is said.
	var pl := -1
	var pr := -1
	for k in rows.size():
		if String((rows[k] as Dictionary)["id"]) == "pod_l":
			pl = k
		elif String((rows[k] as Dictionary)["id"]) == "pod_r":
			pr = k
	if pl >= 0 and pr >= 0:
		var a: Vector2 = (rows[pl] as Dictionary)["off"]
		var b: Vector2 = (rows[pr] as Dictionary)["off"]
		_expect(a.x == b.x and a.y == -b.y and a.y < 0.0, "%s: the pods are not a mirrored pair: %s and %s" % [hid, a, b])
		_expect(float((rows[pl] as Dictionary)["depth"]) > 0.0, "%s: the pod sits outside the hull's hit shape" % hid)
		print("parts_data_check: %s pods at (%.1f, -+%.1f)%s" % [hid, b.x, b.y, " PROPOSED offset" if _sp.pods_proposed(hid) else " (the hull's own side flames)"])
	else:
		_expect(false, "%s: a pod is missing" % hid)
	# The exposure table at the three radii; the sets only grow with the radius.
	var sets: Array = []
	for r: float in RADII:
		var ids: Array = []
		for row: Dictionary in _rows(hid, r):
			if int(row["cls"]) == 0 and bool(row["exposed"]):
				ids.append(String(row["id"]))
		sets.append(ids)
		print("EXPOSURE %s radius %d: %d of %d light parts exposed: %s" % [hid, int(r), ids.size(), want_light, ", ".join(PackedStringArray(ids))])
	for k in 2:
		for id: String in sets[k]:
			_expect((sets[k + 1] as Array).has(id), "%s: %s is exposed at radius %d but not at %d" % [hid, id, int(RADII[k]), int(RADII[k + 1])])
	# The depth of each light part under the hit surface.
	var line := "EXPOSURE %s depth under the hit surface (world units):" % hid
	for row: Dictionary in rows:
		if int(row["cls"]) == 0:
			line += " %s %.1f" % [String(row["id"]), float(row["depth"])]
	print(line)


## True when section `sec` of `armour` is one of the sections of zone `zone`.
func _in_zone(armour: ArmourSections, sec: int, zone: int) -> bool:
	var first := int(armour.zone_first[zone])
	return sec >= first and sec < first + int(armour.zone_count[zone])


## Points on the Battlecruiser's spine are hosted by where they sit along it: behind its middle in the rear
## zone, ahead of it or level with it in the front zone; a point beside the spine keeps the hull's own pick.
func _case_centre_points() -> void:
	var def: Dictionary = Ships.get_def("battlecruiser")
	var armour := ArmourSections.make(def, float(def["hull"]))
	var spine_off := float(def["spine_off"])
	var rear := int(_sp.host_section(def, armour, Vector2(-100.0, 0.0)))
	_case(_in_zone(armour, rear, Rules.ZONE_REAR), "centre line: rear point", "a point behind the spine's middle is in section %d, not in the rear zone" % rear)
	var front := int(_sp.host_section(def, armour, Vector2(100.0, 0.0)))
	_case(_in_zone(armour, front, Rules.ZONE_FRONT), "centre line: front point", "a point ahead of the spine's middle is in section %d, not in the front zone" % front)
	var tie := int(_sp.host_section(def, armour, Vector2(spine_off, 0.0)))
	_case(_in_zone(armour, tie, Rules.ZONE_FRONT), "centre line: tie goes forward", "a point at the spine's middle is in section %d, not in the front zone" % tie)
	var beside := int(_sp.host_section(def, armour, Vector2(-100.0, 60.0)))
	_case(_in_zone(armour, beside, Rules.ZONE_LEFT) or _in_zone(armour, beside, Rules.ZONE_RIGHT), "centre line: beside the spine unchanged", "a point beside the spine is in section %d, not in a side zone" % beside)


## A hull that carries no parts gets none.
func _check_none(hid: String) -> void:
	var def: Dictionary = Ships.get_def(hid)
	var armour := ArmourSections.make(def, float(def["hull"]))
	var rows: Array = _sp.build(hid, armour)
	_expect(rows.is_empty(), "%s is not one of the four hulls but got %d parts" % [hid, rows.size()])


## With --parts=off a launched ship has no parts; with it on it has exactly the rows.
func _check_launch() -> void:
	var was = Game.options.get("parts", null)
	Game.options["parts"] = "off"
	var s := _launch("battlecruiser")
	_expect(s.get("parts") == null, "with the parts switch off a Battlecruiser has parts")
	_retire(s)
	Game.options["parts"] = "on"
	var on := _launch("battlecruiser")
	var live = on.get("parts")
	_expect(live != null, "with the parts switch on a Battlecruiser has no parts")
	if live != null:
		var rows: Array = _sp.build("battlecruiser", on.armour)
		_expect(int(live.count()) == rows.size(), "the live parts number %d, the rows %d" % [int(live.count()), rows.size()])
		for i in rows.size():
			_expect(int(live.hp[i]) == int((rows[i] as Dictionary)["hp_max"]), "part %d does not start whole" % i)
	_retire(on)
	var small := _launch("fighter")
	_expect(small.get("parts") == null, "a Fighter has parts")
	_retire(small)
	if was == null:
		Game.options.erase("parts")
	else:
		Game.options["parts"] = was


## Launch a pilot ship of hull `hid` (team 1) standing still.
func _launch(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Put ship `s` away and make it dead so nothing looks at it again.
func _retire(s: Ship) -> void:
	s.global_position = Vector2(-5000.0, -5000.0)
	s.alive = false
