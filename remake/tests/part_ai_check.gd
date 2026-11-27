extends Node
## WHAT THIS IS: the check of the AI's part pick (PartAim and the part call in PilotTargeting): which part of a
## big ship a strike craft pilot aims at. It prints one line per case ("PASS name" or "FAIL name: what") and then
## "part_ai_check: N checks, K failures" (and, only when K is 0, "part_ai_check: 0 failures").
##
## HOW IT WORKS: the scoring is a function of plain numbers, so the first groups call PartAim directly with
## made-up candidate parts (each term of the score, the cap of 3 friendlies, the hold bonus, the nearer part, the
## number tie, every skip). The last groups use a real Battlecruiser with real parts and a real PilotAI: a Fighter
## (whose guns glance off every section it faces) aims at an exposed point-defence gun and not at a main gun, a
## Bomber's torpedo (which pierces) aims at an engine pod of a target that is leaving, the choice holds for 30
## ticks, PilotCombat's aim point moves by exactly the part's offset, with the parts switch off the aim is the
## middle of the ship, and a part on an Ion Frigate's centre line behind the middle is judged by the rear
## shield zone. It loads the new classes only through ResourceLoader and calls them with no static type, so
## on a build without them it prints FAIL lines and still ends.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=part_ai_check
##
## WHO USES IT: main.gd loads it for --test=part_ai_check; run_checks runs it. It only reads the game: the match
## stands still.

## Where the new class lives.
const AIM_PATH := "res://scripts/ai/part_aim.gd"
## The part classes (ShipParts.CLASS_*), copied here so the check needs no static class.
const LIGHT := 0
## Class number of a main gun.
const MAIN := 1
## Class number of an engine pod.
const POD := 2
## Class number of the sensor.
const SENSOR := 3

## The ship's home spot (set by setup()).
var _home := Vector2.ZERO
## The running match (set by setup()).
var world: World
## How many checks were made.
var checks := 0
## How many went wrong.
var failures := 0
## The PartAim script, or null when this build has none.
var _pa = null


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
		print("part_ai_check: PASS %s" % case_name)
	else:
		failures += 1
		print("part_ai_check: FAIL %s: %s" % [case_name, what])


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	if ResourceLoader.exists(AIM_PATH):
		_pa = load(AIM_PATH)
	_expect(_pa != null, "PartAim is in this build", "part_aim.gd is missing")
	_case_off_centre()
	if _pa != null:
		_case_scores()
		_case_skips()
		_case_choose()
		_case_fighter()
		_case_bomber()
		_case_hold()
		_case_combat_aim()
		_case_centre_shield()
	print("part_ai_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("part_ai_check: 0 failures")
	get_tree().quit()


## A candidate part for the score table: class, and the terms that skip it, at a clean state.
func _c(cls: int, id := 0, dist := 100.0) -> Dictionary:
	return {"id": id, "cls": cls, "offline": false, "exposed": false, "shield_up": false, "a_eff": 0.0, "friends": 0, "dist": dist}


## The score of candidate `c` for a fighter (5.5) at a target that is not leaving, with no hold.
func _s(c: Dictionary, leaving := false, bomber := false, strength := 5.5, pierces := false, held := false) -> int:
	return int(_pa.score(c, leaving, bomber, strength, pierces, held))


## Each term of the score.
func _case_scores() -> void:
	_expect(_s(_c(POD)) == 60 and _s(_c(POD), true) == 100, "a pod scores 60, and 100 when the target is leaving", "%d %d" % [_s(_c(POD)), _s(_c(POD), true)])
	_expect(_s(_c(MAIN)) == 90, "a main gun scores 90", "%d" % _s(_c(MAIN)))
	_expect(_s(_c(LIGHT)) == 70 and _s(_c(LIGHT), false, true) == 40, "a light part scores 70 for a fighter and 40 for a bomber", "%d %d" % [_s(_c(LIGHT)), _s(_c(LIGHT), false, true)])
	_expect(_s(_c(SENSOR)) == 50, "the sensor scores 50", "%d" % _s(_c(SENSOR)))
	var one := _c(MAIN)
	one["friends"] = 1
	var two := _c(MAIN)
	two["friends"] = 2
	var three := _c(MAIN)
	three["friends"] = 3
	_expect(_s(one) == 75 and _s(two) == 60, "each friendly on a part takes 15 off", "%d %d" % [_s(one), _s(two)])
	_expect(_s(three) == 0, "a part with 3 friendlies on it is skipped", "%d" % _s(three))
	_expect(_s(_c(MAIN), false, false, 5.5, false, true) == 110, "the part aimed at last time gains 20", "%d" % _s(_c(MAIN), false, false, 5.5, false, true))


## Each skip.
func _case_skips() -> void:
	var off := _c(MAIN)
	off["offline"] = true
	_expect(_s(off) == 0, "an offline part is skipped", "%d" % _s(off))
	var up := _c(MAIN)
	up["shield_up"] = true
	_expect(_s(up) == 0 and _s(up, false, false, 5.5, true) == 90, "a part whose shield zone holds is skipped unless the weapon pierces", "%d %d" % [_s(up), _s(up, false, false, 5.5, true)])
	var covered := _c(MAIN)
	covered["a_eff"] = 75.0
	_expect(_s(covered) == 0 and _s(covered, false, false, 13.3) == 90, "a heavy part behind a whole section is skipped when the shot would glance (5.5 under 13.2, 13.3 over)", "%d %d" % [_s(covered), _s(covered, false, false, 13.3)])
	var plate := _c(LIGHT)
	plate["a_eff"] = 75.0
	plate["exposed"] = true
	_expect(_s(plate) == 70, "an exposed light part has no glance gate", "%d" % _s(plate))
	var cover_l := _c(LIGHT)
	cover_l["a_eff"] = 75.0
	_expect(_s(cover_l) == 0, "a covered light part is glance-gated", "%d" % _s(cover_l))
	var black := _c(MAIN)
	black["a_eff"] = 0.0
	_expect(_s(black) == 90, "a heavy part behind a black section is not glance-gated", "%d" % _s(black))


## The pick among candidates: the best score, the nearer part, the lower number.
func _case_choose() -> void:
	var cands := [_c(MAIN, 0, 300.0), _c(MAIN, 1, 200.0), _c(POD, 2, 50.0), _c(SENSOR, 3, 10.0)]
	var k := int(_pa.choose(cands, false, false, 5.5, false, -1))
	_expect(k == 1, "of equal scores the nearer part wins", "picked %d" % k)
	var tie := [_c(MAIN, 5, 100.0), _c(MAIN, 4, 100.0)]
	k = int(_pa.choose(tie, false, false, 5.5, false, -1))
	_expect(int((tie[k] as Dictionary)["id"]) == 4, "of equal scores at equal distance the lower part number wins", "picked %d" % k)
	k = int(_pa.choose(cands, true, false, 5.5, false, -1))
	_expect(k == 2, "a pod beats the main guns when the target is leaving", "picked %d" % k)
	k = int(_pa.choose(cands, false, false, 5.5, false, 3))
	_expect(k == 1, "the hold bonus does not lift the sensor over a main gun (50 + 20 against 90)", "picked %d" % k)
	var offs := [_c(MAIN, 0, 50.0), _c(POD, 1, 50.0)]
	(offs[0] as Dictionary)["offline"] = true
	k = int(_pa.choose(offs, false, false, 5.5, false, -1))
	_expect(k == 1, "an offline part is never picked", "picked %d" % k)
	_expect(int(_pa.choose([], false, false, 5.5, false, -1)) == -1, "no candidates gives no pick", "")


## Launch a pilot ship of hull `hid` for `team` with the parts switch set to `mode` at its making, at `at` facing east, with empty shields.
func _ship(hid: String, mode: String, team: int, at: Vector2) -> Ship:
	var was = Game.options.get("parts", null)
	Game.options["parts"] = mode
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = at
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


## The delta the targeting part gives for pilot `ship` and `target` (ZERO when this build has no part call).
func _delta(brain: PilotAI, ship: Ship, target: Unit) -> Vector2:
	if not brain.targeting.has_method("part_delta"):
		return Vector2.ZERO
	return brain.targeting.part_delta(ship, target)


## A Fighter at a Battlecruiser with its shields down aims at an exposed point-defence gun and never at a main gun.
func _case_fighter() -> void:
	var bc := _ship("battlecruiser", "on", 1, _home)
	var f := _ship("fighter", "off", 0, _home + Vector2(-1500.0, 0.0))
	var brain := PilotAI.new(world, f.profile)
	var d := _delta(brain, f, bc)
	var p = bc.get("parts")
	var idx := int(brain.targeting.get("part_idx")) if p != null else -1
	var row: Dictionary = p.rows[idx] if idx >= 0 else {}
	_expect(d != Vector2.ZERO and idx >= 0 and int(row["cls"]) == LIGHT and bool(row["exposed"]), "a Fighter at a Battlecruiser aims at an exposed point-defence gun", "delta %s part %d" % [str(d), idx])
	_expect(d == (row["off"] as Vector2).rotated(bc.rotation) if idx >= 0 else false, "the aim offset is that part's place on the hull", "delta %s" % str(d))
	# With the shields up on every zone nothing scores (the Fighter's slugs do not pierce): the middle.
	for z in 4:
		bc.shields.values[z] = 500.0
	var b2 := PilotAI.new(world, f.profile)
	_expect(_delta(b2, f, bc) == Vector2.ZERO, "with the shield zones up the Fighter aims at the middle", "delta %s" % str(_delta(b2, f, bc)))
	_retire(bc)
	_retire(f)


## A Bomber's torpedo (it pierces the shield and no armour glances it) aims at an engine pod of a target that is leaving.
func _case_bomber() -> void:
	var bc := _ship("battlecruiser", "on", 1, _home)
	var b := _ship("bomber", "off", 0, _home + Vector2(-1500.0, 0.0))
	bc.velocity = Vector2(120.0, 0.0)
	for z in 4:
		bc.shields.values[z] = 500.0
	var brain := PilotAI.new(world, b.profile)
	var d := _delta(brain, b, bc)
	var p = bc.get("parts")
	var idx := int(brain.targeting.get("part_idx")) if p != null else -1
	var row: Dictionary = p.rows[idx] if idx >= 0 else {}
	_expect(d != Vector2.ZERO and idx >= 0 and int(row["cls"]) == POD, "a Bomber's torpedo aims at an engine pod of a target that is leaving", "delta %s part %d" % [str(d), idx])
	_retire(bc)
	_retire(b)


## The choice is held for 30 ticks, whole-tick stable, and then looked at again.
func _case_hold() -> void:
	var bc := _ship("battlecruiser", "on", 1, _home)
	var f := _ship("fighter", "off", 0, _home + Vector2(-1500.0, 0.0))
	var brain := PilotAI.new(world, f.profile)
	var t0 := world.tick_count
	var d0 := _delta(brain, f, bc)
	var p = bc.get("parts")
	if p == null:
		_expect(false, "the part choice is held for 30 ticks", "no parts")
		_retire(bc)
		_retire(f)
		return
	var first := int(brain.targeting.get("part_idx"))
	# Three other pilots now aim at the chosen part: a fresh pick would skip it.
	for k in 3:
		p.mark_aim(9000 + k, 0, first, t0 + 1000)
	var stable := true
	for k in 30:
		world.tick_count = t0 + k
		stable = stable and _delta(brain, f, bc) == d0 and int(brain.targeting.get("part_idx")) == first
	_expect(stable, "the pick holds for 30 ticks whatever happens to the scores", "it moved inside the hold")
	world.tick_count = t0 + 30
	var d1 := _delta(brain, f, bc)
	_expect(int(brain.targeting.get("part_idx")) != first and d1 != d0, "after 30 ticks the pick is made again (and skips a part three friendlies are on)", "part %d" % int(brain.targeting.get("part_idx")))
	world.tick_count = t0
	_retire(bc)
	_retire(f)


## PilotCombat's aim point moves by exactly the part's offset; with the switch off it is the middle as before.
func _case_combat_aim() -> void:
	var f := _ship("fighter", "off", 0, _home + Vector2(-1500.0, 0.0))
	var bc := _ship("battlecruiser", "on", 1, _home)
	var brain := PilotAI.new(world, f.profile)
	brain.state = "lane"
	brain.target = bc
	brain.combat.fight(f)
	var aim_on := f.controls.aim_point
	var delta := _delta(brain, f, bc)
	_retire(bc)
	var twin := _ship("battlecruiser", "off", 1, _home)
	var brain2 := PilotAI.new(world, f.profile)
	brain2.state = "lane"
	brain2.target = twin
	brain2.combat.fight(f)
	var aim_off := f.controls.aim_point
	_expect(twin.get("parts") == null and _delta(brain2, f, twin) == Vector2.ZERO, "with the switch off the part call gives no offset", "delta %s" % str(_delta(brain2, f, twin)))
	_expect(aim_off.distance_to(twin.global_position) < 150.0, "with the switch off the aim is the middle of the ship (within the pilot's own aim error)", "aim %s ship %s" % [str(aim_off), str(twin.global_position)])
	_expect(delta != Vector2.ZERO and aim_on.distance_to(aim_off + delta) < 0.01, "the aim point moved by exactly the part's offset (%s)" % str(delta), "on %s off %s delta %s" % [str(aim_on), str(aim_off), str(delta)])
	_retire(twin)
	_retire(f)


## A part on the hull's centre line behind the spine's middle is read in the rear shield zone: with that zone's
## shield down and its armour black the Fighter aims at it, though the front zone's shield is up.
func _case_centre_shield() -> void:
	var label := "centre line: the shield skip reads the host zone"
	var ion := _ship("ion", "on", 1, _home)
	var f := _ship("fighter", "off", 0, _home + Vector2(-1500.0, 0.0))
	var p = ion.get("parts")
	var idx := -1
	for i in int(p.count()):
		var row: Dictionary = p.rows[i]
		var off: Vector2 = row["off"]
		if idx < 0 and int(row["cls"]) == LIGHT and not bool(row["exposed"]) and ion.spine_len > 0.0 and off.y == 0.0 and off.x < ion.spine_off and absf(off.x - ion.spine_off) <= ion.spine_len * 0.5:
			idx = i
	if idx < 0:
		_expect(false, label, "could not check: no on-spine rear part")
		_retire(ion)
		_retire(f)
		return
	# Every other part is out, so only that one can be picked.
	for i in int(p.count()):
		if i != idx:
			p.hp[i] = 0
			p.offline[i] = 1
	var first := int(ion.armour.zone_first[Rules.ZONE_REAR])
	for k in int(ion.armour.zone_count[Rules.ZONE_REAR]):
		ion.armour.a_hp[first + k] = 0
	for z in 4:
		ion.shields.values[z] = 0.0 if z == Rules.ZONE_REAR else 500.0
	var brain := PilotAI.new(world, f.profile)
	var d := _delta(brain, f, ion)
	var want: Vector2 = ((p.rows[idx] as Dictionary)["off"] as Vector2).rotated(ion.rotation)
	_expect(want != Vector2.ZERO and d == want, label, "delta %s, the part's place is %s" % [str(d), str(want)])
	_retire(ion)
	_retire(f)


## Control: with the switch off, a ship with no parts gets no offset, so the aim is the middle (no new class needed).
func _case_off_centre() -> void:
	var f := _ship("fighter", "off", 0, _home + Vector2(-1500.0, 0.0))
	var bc := _ship("battlecruiser", "off", 1, _home)
	var brain := PilotAI.new(world, f.profile)
	_expect(_delta(brain, f, bc) == Vector2.ZERO, "with the switch off the aim at a Battlecruiser is the middle of the ship", "delta %s" % str(_delta(brain, f, bc)))
	_retire(bc)
	_retire(f)
