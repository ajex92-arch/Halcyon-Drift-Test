extends Node
## WHAT THIS IS: the check of the research effects written as words (TechEffects) and of the rule that turns a class's levels
## into marks on its ships (MarksLayer.counts). It proves five things: every effect key of every research has a row; every line
## the Research tab can show is plain (no "nan", "inf", "null" or "<"); the "after" of a line equals the "before" of the same
## line read after the effect is applied (a round trip over all the research, in board order); a drive step and an armor step
## in the words equal what a real ship of each class gets in the game (top speed, engine push and hull, level 0 against level 2);
## and every unlock line names a hull the table knows. The marks rule is checked for all four classes at levels 0, 1 and 2.
##
## HOW IT WORKS: setup() builds one ship of each class beside our mothership (as tests/icon_layer_check.gd does), reads its top
## speed, engine push and hull at level 0, sets the team's drive and armor level for the class to 2, makes the ship work its
## numbers out again and compares the ratios with 1 + step * 2. The levels are put back. The round trip then applies every
## research of Tech.ORDER to the team in order. It prints a FAIL line for every check that does not hold, then
## "research_data_check: N failures (M checks)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=research_data_check
##
## WHO USES IT: main.gd loads it for --test=research_data_check (it calls setup()); the lead's run_checks list.

## How far a measured ratio may be from the written one.
const TOLERANCE := 0.001
## The words no line of the Research tab may hold.
const BAD_WORDS := ["nan", "inf", "null", "<"]

## The running match.
var world: World
## The team the Admiral commands.
var team := 0
## How many checks were made.
var checks := 0
## How many of them failed.
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


## Count one check; a failing one prints its FAIL line.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Wait `n` physics frames.
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## The first hull of Ships.ORDER of size `tier_index` (0 small to 3 capital).
func _hull_of(tier_index: int) -> String:
	for hull_id: String in Ships.ORDER:
		if Ships.size_of(hull_id) == tier_index:
			return hull_id
	return ""


## A new squad of one crew ship of hull `hull`, beside our mothership (as tests/icon_layer_check.gd makes one). Returns the ship.
func _ship(hull: String) -> Ship:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = RtsHulls.record_kind(hull)
	s.hull_id = hull
	s.max_members = RtsHulls.max_count(hull)
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	var p := Crew.make(world, team, hull, s, 0)
	world.profiles.append(p)
	var ms := world.mothership(team)
	var ship := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
	ship.controller = null
	ship.velocity = Vector2.ZERO
	p.ship = ship
	p.state = "flying"
	s.member_uids.append(ship.uid)
	return ship


## Does `text` hold a word no line may hold?
func _bad(text: String) -> String:
	var low := text.to_lower()
	for w: String in BAD_WORDS:
		if low.contains(w):
			return w
	return ""


## The whole check (see HOW IT WORKS).
func _run() -> void:
	await _tick(3)
	team = world.human_team
	var ts: TeamState = world.teams[team]
	# (a) every effect key of every research has a row.
	var missing: Array[String] = []
	for id: String in Tech.ORDER:
		for key: String in (Tech.TECHS[id]["effect"] as Dictionary):
			if not TechEffects.ROWS.has(key):
				missing.append("%s/%s" % [id, key])
	_check("every effect key of the %d research rows has a row in TechEffects" % Tech.ORDER.size(), missing.is_empty(), ", ".join(missing))
	_check("the board's order lists every research row once", Tech.ORDER.size() == Tech.TECHS.size())
	# (b) every line is plain, for every row and every class.
	var bad := 0
	for id: String in Tech.ORDER:
		var ls := TechEffects.lines(ts, id)
		_check("%s has at least one line" % id, not ls.is_empty())
		for l: String in ls:
			if l == "" or _bad(l) != "":
				bad += 1
				_check("%s line is plain" % id, false, l)
	_check("every line of every research row is plain (no nan, inf, null or <)", bad == 0)
	for tier: String in Tech.TIERS:
		for l: String in TechEffects.class_lines(ts, tier):
			_check("class line of %s is plain" % tier, l != "" and _bad(l) == "", l)
		_check("level text of %s is plain" % tier, _bad(TechEffects.level_text(ts, tier)) == "")
		_check("the word for class %s names a hull" % tier, TechEffects.tier_label(tier) != "" and not TechEffects.tier_label(tier).contains("?"))
	# (d) a drive step and an armor step equal the game: a real ship of each class, level 0 against level 2.
	for i in Tech.TIERS.size():
		var tier: String = Tech.TIERS[i]
		var hull := _hull_of(i)
		_check("the table has a hull of class %s" % tier, hull != "")
		if hull == "":
			continue
		var ship := _ship(hull)
		await _tick(2)
		var d0: int = ts.drive[tier]
		var a0: int = ts.armor[tier]
		ts.drive[tier] = 0
		ts.armor[tier] = 0
		ShipStats.recompute(ship, false)
		var speed0 := ship.f_max
		var accel0 := ship.f_accel
		var hull0 := ship.hull_max
		ts.drive[tier] = 2
		ts.armor[tier] = 2
		ship.stats_dirty = true
		ShipStats.recompute(ship, false)
		var speed_ratio := ship.f_max / speed0
		var accel_ratio := ship.f_accel / accel0
		var hull_ratio := ship.hull_max / hull0
		print("research_data_check measured %s (%s): speed x%.4f accel x%.4f hull x%.4f" % [tier, hull, speed_ratio, accel_ratio, hull_ratio])
		_check("%s: two drive levels give 1 + DRIVE_SPEED * 2 top speed" % tier, absf(speed_ratio - (1.0 + TechEffects.DRIVE_SPEED * 2.0)) <= TOLERANCE, "%.4f" % speed_ratio)
		_check("%s: two drive levels give 1 + DRIVE_ACCEL * 2 engine push" % tier, absf(accel_ratio - (1.0 + TechEffects.DRIVE_ACCEL * 2.0)) <= TOLERANCE, "%.4f" % accel_ratio)
		_check("%s: two armor levels give 1 + ARMOR_HULL * 2 hull" % tier, absf(hull_ratio - (1.0 + TechEffects.ARMOR_HULL * 2.0)) <= TOLERANCE, "%.4f" % hull_ratio)
		ts.drive[tier] = d0
		ts.armor[tier] = a0
		ship.stats_dirty = true
		ShipStats.recompute(ship, false)
	# (e) every unlock line names a hull the table knows.
	for id: String in Tech.ORDER:
		var effect: Dictionary = Tech.TECHS[id]["effect"]
		if effect.has("unlock_ship"):
			var hull_id := str(effect["unlock_ship"])
			var want := "Unlocks: %s" % str(Ships.HULLS[hull_id]["label"]) if Ships.HULLS.has(hull_id) else "?"
			_check("%s names its hull in Ships.HULLS" % id, Ships.HULLS.has(hull_id) and TechEffects.lines(ts, id).has(want), str(TechEffects.lines(ts, id)))
	# (g) the marks rule, for all four classes at levels 0, 1 and 2: the stripes are the armor levels, the ticks the drive levels.
	for tier: String in Tech.TIERS:
		var d0: int = ts.drive[tier]
		var a0: int = ts.armor[tier]
		for lv in 3:
			ts.drive[tier] = lv
			ts.armor[tier] = 2 - lv
			var c := MarksLayer.counts(ts, tier)
			_check("marks rule: %s at drive %d armor %d gives %d stripes and %d ticks" % [tier, lv, 2 - lv, 2 - lv, lv], c.x == ts.armor_level(tier) and c.y == ts.drive_level(tier) and c.x == 2 - lv and c.y == lv, str(c))
		ts.drive[tier] = d0
		ts.armor[tier] = a0
	# (c) the round trip: apply every research in board order; the "after" of a line is the "before" of the same line read next.
	var pairs := 0
	for id: String in Tech.ORDER:
		var before := TechEffects.lines(ts, id)
		ts.apply_effect(Tech.TECHS[id]["effect"])
		var after := TechEffects.lines(ts, id)
		_check("%s: the line count holds across the apply" % id, before.size() == after.size(), "%d then %d" % [before.size(), after.size()])
		for i in mini(before.size(), after.size()):
			if not before[i].contains(" -> "):
				continue
			var b_parts := before[i].split(" -> ")
			var a_parts := after[i].split(" -> ")
			pairs += 1
			var now_part := String(a_parts[0]).get_slice(": ", 1)
			_check("%s: line %d round trip (%s | %s)" % [id, i, before[i], after[i]], b_parts[1] == now_part, "%s | %s" % [before[i], after[i]])
	_check("the round trip compared many lines (%d)" % pairs, float(pairs) > float(Tech.ORDER.size()) * 0.5)
	# With every research applied no class line or class card text can be odd.
	for tier: String in Tech.TIERS:
		for l: String in TechEffects.class_lines(ts, tier):
			_check("class line of %s after everything is plain" % tier, _bad(l) == "", l)
	print("research_data_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()
