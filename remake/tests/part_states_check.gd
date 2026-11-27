extends Node
## WHAT THIS IS: the check of the ship parts' states and hit paths (ShipSystems and the part calls in
## Unit.take_hit): a light part that sticks out of the hull is hit directly through a plate of its own,
## every part behind the armour takes half of what gets through the section over it, a covered light
## part is hit directly once its section is black, a part at 0 goes offline and climbs back by itself,
## a part on the hull's centre line is hosted by its x (a rear one by the rear section),
## and none of it touches a ship with the parts switch off. It prints one line per case ("PASS name"
## or "FAIL name: what") and then "part_states_check: N checks, K failures" (and, only when K is 0,
## "part_states_check: 0 failures").
##
## HOW IT WORKS: it builds the normal match, freezes it and launches real Battlecruisers (the worked
## example of the design is on one) with empty shields, so every hit reaches the parts and the armour.
## Hits are DamageInfo notes with a true impact point in the ship's own frame, applied through
## Unit.take_hit(); time is stepped by calling ShipSystems.tick() by hand. Every number is whole units
## (1/256 point) and checked to the unit. A control ship made with the switch off takes the same hits
## to show what the part rules leave alone. It loads the new classes only through ResourceLoader and
## calls them with no static type, so on a build without them it prints FAIL lines and still ends.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=part_states_check
##
## WHO USES IT: main.gd loads it for --test=part_states_check; run_checks runs it. It hurts only ships
## of a frozen match that is thrown away.

## Where the new class lives.
const SYSTEMS_PATH := "res://scripts/entities/ship_systems.gd"
## The ship's home spot (set by setup()).
var _home := Vector2.ZERO
## The running match (set by setup()).
var world: World
## How many checks were made.
var checks := 0
## How many went wrong.
var failures := 0
## A scout of team 0 that fires the beam.
var _shooter: Ship = null


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
		print("part_states_check: PASS %s" % case_name)
	else:
		failures += 1
		print("part_states_check: FAIL %s: %s" % [case_name, what])


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var has_class := ResourceLoader.exists(SYSTEMS_PATH)
	_expect(has_class, "ShipSystems is in this build", "ship_systems.gd is missing")
	if has_class:
		_shooter = _ship("scout", "off", 0)
		_shooter.global_position = Vector2(-5000.0, -5000.0)
		_case_worked_example()
		_case_covered_glance()
		_case_breach()
		_case_share()
		_case_centre_line()
		_case_black_passes()
		_case_offline_ignores()
		_case_climb()
		_case_ion()
		_case_gun_only()
		_case_beam_and_flak()
		_case_determinism()
		_case_switch_off()
	print("part_states_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("part_states_check: 0 failures")
	get_tree().quit()


## Launch a pilot ship of hull `hid` for `team` with the parts switch set to `mode` ("on" or "off") at
## the ship's making, standing at home facing east with empty shields.
func _ship(hid: String, mode: String, team := 1) -> Ship:
	var was = Game.options.get("parts", null)
	Game.options["parts"] = mode
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
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


## A note for a hit of strength `w` and size `raw` (points) whose true impact point is `local` (the ship's
## own frame, the ship at home facing east).
func _note(w: float, raw: float, local: Vector2, kind := Rules.W_BOLT) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = raw
	d.strength = w
	d.kind = kind
	d.from_pos = _home + local
	d.impact = _home + local
	d.pierce = 1.0
	return d


## Hit ship `s` with strength `w`, size `raw`, at `local`; returns the damage the hull took.
func _hit(s: Ship, w: float, raw: float, local: Vector2, kind := Rules.W_BOLT) -> float:
	return s.take_hit(_note(w, raw, local, kind), raw)


## The first part of ship `s` that is a light part with `exposed` as given, or -1.
func _first_light(p, exposed: bool) -> int:
	for i in int(p.count()):
		var row: Dictionary = p.rows[i]
		if int(row["cls"]) == 0 and bool(row["exposed"]) == exposed:
			return i
	return -1


## The first part of class `cls` that no exposed light part's circle (40 units round it) covers, so a hit at
## its place lands on it and not on the light part, or -1. With `crowded` it is the clear one whose section
## holds the most parts behind it (the first of them on a tie), so a shared section can be tested.
func _first_class(p, cls: int, crowded := false) -> int:
	var best := -1
	var best_n := -1
	for i in int(p.count()):
		var row: Dictionary = p.rows[i]
		if int(row["cls"]) != cls:
			continue
		var clear := true
		var behind := 0
		for j in int(p.count()):
			var other: Dictionary = p.rows[j]
			if j != i and int(other["cls"]) == 0 and bool(other["exposed"]) and (other["off"] as Vector2).distance_to(row["off"]) <= 40.0:
				clear = false
			if int(other["sec"]) == int(row["sec"]) and not (int(other["cls"]) == 0 and bool(other["exposed"])):
				behind += 1
		if not clear:
			continue
		if not crowded:
			return i
		if behind > best_n:
			best = i
			best_n = behind
	return best


## The offset of part `i`.
func _off(p, i: int) -> Vector2:
	return (p.rows[i] as Dictionary)["off"]


## Take part `i` offline through its own health: leave 1 unit, then hit its host section with a heavy shell.
func _knock_out(s: Ship, i: int) -> void:
	var p = s.get("parts")
	p.hp[i] = 1
	var row: Dictionary = p.rows[i]
	if int(row["cls"]) == 0 and bool(row["exposed"]):
		_hit(s, 5.5, 5.5, row["off"])
	else:
		_hit(s, 50.0, 50.0, row["off"], Rules.W_SHELL)


## Copy of ship `s`'s section armour, hull and part health, to compare two ships.
func _state(s: Ship) -> Array:
	var p = s.get("parts")
	var hp := []
	if p != null:
		for i in int(p.count()):
			hp.append(int(p.hp[i]))
			hp.append(int(p.offline[i]))
			hp.append(int(p.since[i]))
	return [Array(s.armour.a_hp), s.hull, hp]


## The design's worked example on a real Battlecruiser: a Fighter cannon bolt (strength 5.5) at an exposed
## point-defence gun takes 319 units off it through its plate and nothing off the hull or the section;
## the 51st bolt takes it to 0 and the rest goes on as a normal hit.
func _case_worked_example() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	_expect(p != null, "the Battlecruiser has parts", "no parts with the switch on")
	if p == null:
		_retire(s)
		return
	var e := _first_light(p, true)
	_expect(e >= 0, "the Battlecruiser has an exposed light part", "none exposed")
	if e < 0:
		_retire(s)
		return
	var row: Dictionary = p.rows[e]
	var def: Dictionary = s.def
	var hp_max := int(row["hp_max"])
	_expect(hp_max == maxi(40 * 256, int(def["hull"]) * 15 * 256 / 1000) and hp_max == 16128, "an exposed point-defence part holds 63 points", "hp_max %d" % hp_max)
	_expect(int(row["plate"]) == 4800, "the plate is armour 75 x 64 = 4800 units", "plate %d" % int(row["plate"]))
	var host := int(row["sec"])
	var hull0 := s.hull
	var sec0: Array = Array(s.armour.a_hp)
	var took := _hit(s, 5.5, 5.5, row["off"])
	_expect(took == 0.0 and hp_max - int(p.hp[e]) == 319, "one bolt takes 319 units off the part and nothing off the hull", "part lost %d, hull took %f" % [hp_max - int(p.hp[e]), took])
	_expect(s.hull == hull0 and Array(s.armour.a_hp) == sec0, "the hull and the section are whole while the part holds", "hull or section moved")
	_expect(int(p.state(e)) == 0 and int(p.last_hit) == e, "the part is working after one bolt", "state %d" % int(p.state(e)))
	for _k in 49:
		_hit(s, 5.5, 5.5, row["off"])
	var rest := hp_max - 50 * 319
	_expect(int(p.hp[e]) == rest and s.hull == hull0 and Array(s.armour.a_hp) == sec0, "50 bolts leave 178 units and a whole hull", "hp %d wanted %d" % [int(p.hp[e]), rest])
	var t_before := int(p.tick_n)
	_hit(s, 5.5, 5.5, row["off"])
	_expect(int(p.hp[e]) == 0 and int(p.offline[e]) == 1 and int(p.since[e]) == t_before, "the 51st bolt takes the part to 0 and offline", "hp %d offline %d" % [int(p.hp[e]), int(p.offline[e])])
	# The overflow: ru x (loss - held) / loss units go on, converted back to points once, and glance on the section.
	var over_ru := 1408 * (319 - rest) / 319
	var floor_u := over_ru * 15 / 100
	var lost := (hull0 - s.hull) * 256.0
	_expect(absf(lost - float(floor_u)) < 0.01 and Array(s.armour.a_hp) == sec0, "the overflow went on as a normal hit (a glance: %d units to the hull)" % floor_u, "hull lost %f units, wanted %d" % [lost, floor_u])
	_expect(int(s.armour.a_hp[host]) == int(s.armour.a_max[host]), "the host section is unworn", "worn")
	_retire(s)


## A hit at a covered part's place passes nothing to any part when it only glances.
func _case_covered_glance() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var c := _first_light(p, false)
	_expect(c >= 0, "the Battlecruiser has a covered light part", "none covered")
	if c < 0:
		_retire(s)
		return
	var before := _state(s)
	var took := _hit(s, 5.5, 5.5, _off(p, c))
	var after := _state(s)
	var same := true
	for i in int(p.count()):
		same = same and int(p.hp[i]) == int(before[2][i * 3])
	_expect(same and took > 0.0 and int(p.last_hit) == -1, "a glancing bolt at a covered part passes nothing to any part", "a part moved")
	_retire(s)


## The breach rule: a covered light part takes 50 percent of D while its section holds; once the section is black
## the next hit in it goes to the part directly through its plate; mended, it is back on the share.
func _case_breach() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var c := _first_light(p, false)
	if c < 0:
		_expect(false, "breach rule", "no covered part")
		_retire(s)
		return
	var row: Dictionary = p.rows[c]
	var host := int(row["sec"])
	var hp_max := int(row["hp_max"])
	_expect(hp_max == 4200 * 60 * 256 / 1000, "a covered light part holds 6 percent of the hull", "hp_max %d" % hp_max)
	# While the section holds: a heavy shell takes 50 percent of D off it.
	var d := _hit(s, 50.0, 50.0, row["off"], Rules.W_SHELL)
	var want := int(d * 256.0) * 50 / 100
	_expect(hp_max - int(p.hp[c]) == want and want > 0, "while its section holds the covered part takes 50 percent of D (%d units)" % want, "lost %d wanted %d" % [hp_max - int(p.hp[c]), want])
	# Black section: the next hit goes to the part through its plate, never 50 percent and never both.
	s.armour.a_hp[host] = 0
	var hull0 := s.hull
	var hp0 := int(p.hp[c])
	var arm0: Array = Array(s.armour.a_hp)
	var took := _hit(s, 5.5, 5.5, row["off"])
	_expect(hp0 - int(p.hp[c]) == 319, "once its section is black the part takes the hit through its plate (319 units)", "lost %d" % (hp0 - int(p.hp[c])))
	_expect(took == 0.0 and s.hull == hull0 and Array(s.armour.a_hp) == arm0 and int(p.last_hit) == c, "the section and the hull take nothing from a hit the part held", "hull or section moved")
	# Mended: back on the share.
	s.armour.repair_armour(host, 1000.0)
	_expect(not s.armour.is_black(host), "the mended section is not black", "still black")
	var hp1 := int(p.hp[c])
	var d2 := _hit(s, 50.0, 50.0, row["off"], Rules.W_SHELL)
	var want2 := int(d2 * 256.0) * 50 / 100
	_expect(hp1 - int(p.hp[c]) == want2 and int(p.last_hit) == -1, "a mended section puts the covered part back on the share", "lost %d wanted %d" % [hp1 - int(p.hp[c]), want2])
	_retire(s)


## A heavy shell on a whole section lowers each online heavy part and covered light part hosted by it by exactly
## 50 percent of D, and the section and hull equal what the same shell does with the switch off.
func _case_share() -> void:
	var s := _ship("battlecruiser", "on")
	var t := _ship("battlecruiser", "off")
	var p = s.get("parts")
	var g := _first_class(p, 1, true)
	var at := _off(p, g)
	var host := int((p.rows[g] as Dictionary)["sec"])
	var hp0 := []
	for i in int(p.count()):
		hp0.append(int(p.hp[i]))
	var d := _hit(s, 50.0, 50.0, at, Rules.W_SHELL)
	var dt := _hit(t, 50.0, 50.0, at, Rules.W_SHELL)
	var each := int(d * 256.0) * 50 / 100
	var ok := each > 0
	var moved := 0
	for i in int(p.count()):
		var row: Dictionary = p.rows[i]
		var takes := int(row["sec"]) == host and not (int(row["cls"]) == 0 and bool(row["exposed"]))
		var lost := int(hp0[i]) - int(p.hp[i])
		if takes:
			moved += 1
		ok = ok and lost == (each if takes else 0)
	_expect(ok and moved >= 2, "a heavy shell lowers each part behind its section by 50 percent of D (%d units, %d parts)" % [each, moved], "a part lost the wrong amount")
	_expect(d == dt and s.hull == t.hull and Array(s.armour.a_hp) == Array(t.armour.a_hp), "the section and the hull equal the switch-off twin", "hull %f vs %f" % [s.hull, t.hull])
	_retire(s)
	_retire(t)


## The covered light part of ship `s` that sits exactly on the hull's centre line behind the spine's middle
## (found by its offset, never by an id), or -1.
func _rear_centre_part(s: Ship) -> int:
	var p = s.get("parts")
	for i in int(p.count()):
		var row: Dictionary = p.rows[i]
		var off: Vector2 = row["off"]
		if int(row["cls"]) == 0 and not bool(row["exposed"]) and s.spine_len > 0.0 and off.y == 0.0 and off.x < s.spine_off and absf(off.x - s.spine_off) <= s.spine_len * 0.5:
			return i
	return -1


## A part on the hull's centre line behind the spine's middle is hosted by the rear section: a heavy shell in the
## rear section lowers it by 50 percent of D, and the same shell in the front section leaves it alone.
func _case_centre_line() -> void:
	var s := _ship("ion", "on")
	var p = s.get("parts")
	var i := _rear_centre_part(s)
	if i < 0:
		_expect(false, "centre line: a rear hit reaches the part", "could not check: no on-spine rear part")
		_expect(false, "centre line: a front hit does not", "could not check: no on-spine rear part")
		_retire(s)
		return
	var hp0 := int(p.hp[i])
	var d := _hit(s, 50.0, 50.0, Vector2(-200.0, 0.0), Rules.W_SHELL)
	var want := int(d * 256.0) * 50 / 100
	var lost := hp0 - int(p.hp[i])
	_expect(want > 0 and lost == want, "centre line: a rear hit reaches the part", "lost %d units, wanted %d (D %f)" % [lost, want, d])
	_retire(s)
	var t := _ship("ion", "on")
	var q = t.get("parts")
	var hp1 := int(q.hp[i])
	_hit(t, 50.0, 50.0, Vector2(200.0, 0.0), Rules.W_SHELL)
	_expect(int(q.hp[i]) == hp1, "centre line: a front hit does not", "the part lost %d units" % (hp1 - int(q.hp[i])))
	_retire(t)


## A hit on a black section passes the whole D to the parts behind it (a black section never glances).
func _case_black_passes() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var g := _first_class(p, 1)
	var at := _off(p, g)
	var host := int((p.rows[g] as Dictionary)["sec"])
	s.armour.a_hp[host] = 0
	# Take the covered light parts of that section offline so none of them is hit directly instead.
	for i in int(p.count()):
		if int((p.rows[i] as Dictionary)["cls"]) == 0 and not bool((p.rows[i] as Dictionary)["exposed"]) and int((p.rows[i] as Dictionary)["sec"]) == host:
			p.hp[i] = 0
			p.offline[i] = 1
	var hp0 := int(p.hp[g])
	var d := _hit(s, 5.5, 5.5, at)
	_expect(d == 5.5 and hp0 - int(p.hp[g]) == 1408 * 50 / 100, "a black section passes the whole hit, so the part takes 704 units", "D %f part lost %d" % [d, hp0 - int(p.hp[g])])
	_retire(s)


## A part that is offline ignores every hit: its health and its tick do not change.
func _case_offline_ignores() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var e := _first_light(p, true)
	if e < 0:
		_expect(false, "offline ignores hits", "no exposed part")
		_retire(s)
		return
	var row: Dictionary = p.rows[e]
	_knock_out(s, e)
	_expect(int(p.offline[e]) == 1 and int(p.hp[e]) == 0, "an exposed part at 0 is offline", "offline %d hp %d" % [int(p.offline[e]), int(p.hp[e])])
	var since := int(p.since[e])
	for _k in 30:
		p.tick()
	# A twin that took the same knock-out hit and nothing else shows what one more hit does to the section and hull.
	var t := _ship("battlecruiser", "off")
	t.hull = s.hull
	for i in s.armour.count:
		t.armour.a_hp[i] = s.armour.a_hp[i]
	var d1 := _hit(s, 5.5, 5.5, row["off"])
	var d2 := _hit(t, 5.5, 5.5, row["off"])
	_expect(int(p.hp[e]) == 0 and int(p.since[e]) == since and int(p.offline[e]) == 1, "a further hit changes nothing on an offline part", "hp %d since %d" % [int(p.hp[e]), int(p.since[e])])
	_expect(d1 == d2 and s.hull == t.hull and Array(s.armour.a_hp) == Array(t.armour.a_hp), "the hit goes on as a normal hit: the section and hull equal a switch-off twin", "hull %f vs %f" % [s.hull, t.hull])
	# A heavy part that is offline takes nothing from a share either.
	var g := _first_class(p, 1)
	_knock_out(s, g)
	var hp_g := int(p.hp[g])
	_hit(s, 50.0, 50.0, _off(p, g), Rules.W_SHELL)
	_expect(int(p.hp[g]) == hp_g and int(p.offline[g]) == 1, "an offline main gun takes nothing from a share", "hp %d" % int(p.hp[g]))
	_retire(s)
	_retire(t)


## The climb: 10 seconds' wait, then 20 seconds (gun) or 30 seconds (pod) to 15 percent, online and degraded;
## a hit during the climb is ignored; a second knock-out starts a new delay.
func _case_climb() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var g := _first_class(p, 1)
	var pod := int(p.pod_l)
	for pair in [[g, 1200, "main gun"], [pod, 1800, "pod"]]:
		var i := int(pair[0])
		var climb := int(pair[1])
		var nm := String(pair[2])
		if i < 0:
			_expect(false, "the %s climbs back" % nm, "no such part")
			continue
		var row: Dictionary = p.rows[i]
		_expect(int(row["climb"]) == climb, "the %s climb is %d ticks" % [nm, climb], "climb %d" % int(row["climb"]))
		_knock_out(s, i)
		var t0 := int(p.since[i])
		var line := 600 + climb
		for _k in 599:
			p.tick()
		_expect(int(p.offline[i]) == 1 and int(p.hp[i]) == 0, "the %s waits out its 10 seconds at 0" % nm, "hp %d" % int(p.hp[i]))
		for _k in 301:
			p.tick()
		var mid := int(p.hp[i])
		_expect(int(p.offline[i]) == 1 and mid > 0, "the %s is climbing after the wait" % nm, "hp %d offline %d" % [mid, int(p.offline[i])])
		# A hit during the climb is ignored.
		_hit(s, 50.0, 50.0, row["off"], Rules.W_SHELL)
		_expect(int(p.hp[i]) == mid and int(p.since[i]) == t0, "a hit during the %s's climb is ignored" % nm, "hp %d" % int(p.hp[i]))
		while int(p.tick_n) - t0 < line - 3:
			p.tick()
		_expect(int(p.offline[i]) == 1, "the %s is still offline 3 ticks before the end of its climb" % nm, "online early")
		while int(p.tick_n) - t0 < line + 2:
			p.tick()
		var top := int(row["hp_max"]) * 15 / 100
		_expect(int(p.offline[i]) == 0 and int(p.hp[i]) == top and int(p.state(i)) == 1, "the %s is back online at 15 percent, degraded, within 2 ticks of %d ticks" % [nm, line], "offline %d hp %d of %d state %d" % [int(p.offline[i]), int(p.hp[i]), top, int(p.state(i))])
		# It stays at the line: the climb brings it back, it does not heal it.
		for _k in 600:
			p.tick()
		_expect(int(p.hp[i]) == top, "the %s climbs to 15 percent and no higher" % nm, "hp %d" % int(p.hp[i]))
		# A second knock-out starts a new delay.
		p.hp[i] = 1
		_hit(s, 50.0, 50.0, row["off"], Rules.W_SHELL)
		_expect(int(p.offline[i]) == 1 and int(p.since[i]) == int(p.tick_n) and int(p.since[i]) > t0, "a second knock-out of the %s starts a new delay" % nm, "since %d now %d" % [int(p.since[i]), int(p.tick_n)])
		for _k in 599:
			p.tick()
		_expect(int(p.offline[i]) == 1 and int(p.hp[i]) == 0, "the second delay of the %s is a full 10 seconds" % nm, "hp %d" % int(p.hp[i]))
		# Bring it back for the next part.
		p.hp[i] = int(row["hp_max"])
		p.offline[i] = 0
	_retire(s)


## Ion hits leave every part untouched.
func _case_ion() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var before := _state(s)
	for i in int(p.count()):
		_hit(s, 80.0, 80.0, _off(p, i), Rules.W_ION)
	var after := _state(s)
	_expect(before == after, "ion hits leave the parts, the sections and the hull alone", "something moved")
	_retire(s)


## Gun only: taking a main gun offline changes nothing else: the section and the hull are exactly what the
## same hit does on a control ship with the switch off.
func _case_gun_only() -> void:
	var s := _ship("battlecruiser", "on")
	var t := _ship("battlecruiser", "off")
	var p = s.get("parts")
	var g := _first_class(p, 1)
	var at := _off(p, g)
	p.hp[g] = 1
	var d1 := _hit(s, 50.0, 50.0, at, Rules.W_SHELL)
	var d2 := _hit(t, 50.0, 50.0, at, Rules.W_SHELL)
	_expect(int(p.offline[g]) == 1, "the shell took the main gun offline", "not offline")
	_expect(d1 == d2 and s.hull == t.hull and Array(s.armour.a_hp) == Array(t.armour.a_hp) and Array(s.armour.wound) == Array(t.armour.wound), "knocking a main gun out gives the section and hull exactly what the same hit does with the switch off", "hull %f vs %f" % [s.hull, t.hull])
	_retire(s)
	_retire(t)


## A beam and a flak burst reach the same rules: both hurt an exposed part directly.
func _case_beam_and_flak() -> void:
	var s := _ship("battlecruiser", "on")
	var p = s.get("parts")
	var e := _first_light(p, true)
	if e < 0:
		_expect(false, "a beam and a flak burst reach the parts", "no exposed part")
		_retire(s)
		return
	var row: Dictionary = p.rows[e]
	var off: Vector2 = row["off"]
	# The outward direction from the spine to the part (a flank part sits beside the hull).
	var n := Vector2(0.0, signf(off.y) if absf(off.y) > 0.5 else 1.0)
	var hp0 := int(p.hp[e])
	var hull0 := s.hull
	var from := _home + off + n * (float(row["depth"]) + 300.0)
	_shooter.global_position = Vector2(-5000.0, -5000.0)
	world.combat.beam(_shooter, from, -n, 900.0, 40.0, Rules.W_LANCE, false, 20.0)
	var lost_beam := hp0 - int(p.hp[e])
	_expect(lost_beam > 0 and s.hull == hull0, "a beam on an exposed part hurts the part and not the hull", "part lost %d hull %f" % [lost_beam, hull0 - s.hull])
	var hp1 := int(p.hp[e])
	var info := DamageInfo.new()
	info.amount = 8.0
	info.kind = Rules.W_FLAK
	info.source_team = 0
	world.combat.area(info, _home + off, 16.0, 0)
	_expect(hp1 - int(p.hp[e]) > 0 and s.hull == hull0, "a flak burst on an exposed part hurts the part and not the hull", "part lost %d hull %f" % [hp1 - int(p.hp[e]), hull0 - s.hull])
	_retire(s)


## Determinism: two ships given the same hits have the same part state, to the unit.
func _case_determinism() -> void:
	var a := _ship("battlecruiser", "on")
	var b := _ship("battlecruiser", "on")
	var pa = a.get("parts")
	var spots := []
	for i in int(pa.count()):
		spots.append(_off(pa, i))
	for k in 200:
		var at: Vector2 = spots[k % spots.size()]
		var w := 5.5 if k % 3 != 0 else 50.0
		_hit(a, w, w, at, Rules.W_SHELL if w > 10.0 else Rules.W_BOLT)
		_hit(b, w, w, at, Rules.W_SHELL if w > 10.0 else Rules.W_BOLT)
		if k % 7 == 0:
			pa.tick()
			(b.get("parts")).tick()
	_expect(_state(a) == _state(b), "two ships with the same hits have the same part state", "they differ")
	_retire(a)
	_retire(b)


## With the switch off a ship has no parts and takes hits exactly as the armour alone gives.
func _case_switch_off() -> void:
	var t := _ship("battlecruiser", "off")
	_expect(t.get("parts") == null, "with the switch off a Battlecruiser has no parts", "has parts")
	var d := _hit(t, 5.5, 5.5, Vector2(180.0, 135.0))
	_expect(d > 0.0, "a ship with no parts takes the glancing floor as before", "took %f" % d)
	_retire(t)
