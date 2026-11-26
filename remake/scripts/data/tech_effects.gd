class_name TechEffects
extends RefCounted
## WHAT THIS IS: what each research gives, written as plain words with numbers: "Top speed: +0% -> +8%", "Repair bays:
## off -> on", "Unlocks: Bomber". The Research tab's hover line and the class cards read it, so the screen shows what the game
## does and no number is typed a second time in a text.
##
## HOW IT WORKS: ROWS has one row for each key a research's "effect" can hold (the keys are listed in the header of
## scripts/data/tech.gd). A row says the key's plain label, what kind of number it is (a percentage of a whole, a count, a bonus
## count, a switch, a ship unlock, or a per-class level) and the TeamState field the research adds to. lines() reads the
## team's field now and what it would be after the research, so the same function gives a "before -> after" pair while the
## research is open and "<value> now" once it is done. The drive and armor steps are the named constants below, the same
## numbers ShipStats multiplies by (tests/research_data_check.gd measures a real ship and fails if they differ). class_lines()
## gives the combined bonus a ship class has now.
## This is a "static library": plain functions with no state of their own. It reads the team and the tech tables and changes
## nothing.
##
## WHO USES IT: AdmiralBoardResearch (the hover line of a research card), StatCard (the class cards), MarksLayer (the number of
## marks a class carries), tests/research_data_check.gd.

## Top speed a ship gains for each drive level of its class: a fraction (0.08 = +8%).
const DRIVE_SPEED := 0.08
## Engine push (acceleration) a ship gains for each drive level of its class.
const DRIVE_ACCEL := 0.06
## Hull points a ship gains for each armor level of its class.
const ARMOR_HULL := 0.15

## A number that is a fraction of a whole, shown as a percentage ("+8%").
const K_PERCENT := 0
## A whole number the team's field holds as it is ("2").
const K_COUNT := 1
## A whole number added to nothing, shown with a plus ("+4").
const K_BONUS := 2
## A switch, shown "off" or "on".
const K_SWITCH := 3
## A ship the research lets pilots buy ("Unlocks: Bomber").
const K_UNLOCK := 4
## A per-class level (the drive and armor effects name a class).
const K_LEVEL := 5

## Every effect key -> {"label": the plain label, "kind": one of the K_ numbers, "field": the TeamState field it adds to
## ("" for a ship unlock; the per-class levels are TeamState.drive and TeamState.armor), "unit": text after the number}.
const ROWS := {
	"unlock_ship": {"label": "Unlocks", "kind": K_UNLOCK, "field": "", "unit": ""},
	"drive": {"label": "Top speed", "kind": K_LEVEL, "field": "drive", "unit": ""},
	"armor": {"label": "Hull", "kind": K_LEVEL, "field": "armor", "unit": ""},
	"fan_gain": {"label": "Bomber fan score a tick", "kind": K_BONUS, "field": "fan_gain", "unit": ""},
	"torp_hp": {"label": "Torpedo hit points", "kind": K_PERCENT, "field": "torp_hp_bonus", "unit": ""},
	"scout_emp": {"label": "Scout Ping stalls engines", "kind": K_SWITCH, "field": "scout_emp", "unit": ""},
	"repair_bays": {"label": "Repair bays", "kind": K_SWITCH, "field": "repair_bays", "unit": ""},
	"bay_drones": {"label": "Repair drones in each bay", "kind": K_COUNT, "field": "bay_drones", "unit": ""},
	"bay_defenses": {"label": "Bay shield and point defense", "kind": K_SWITCH, "field": "bay_defenses", "unit": ""},
	"drone_armor": {"label": "Mining drone hull", "kind": K_PERCENT, "field": "drone_armor", "unit": ""},
	"mining_capacity": {"label": "Ore a drone carries", "kind": K_PERCENT, "field": "mining_capacity", "unit": ""},
	"stipend": {"label": "Pilot pay at respawn", "kind": K_BONUS, "field": "stipend", "unit": " credits"},
	"turret_torp": {"label": "Torpedo turrets", "kind": K_SWITCH, "field": "turret_torp", "unit": ""},
	"turret_armor": {"label": "Turret hull", "kind": K_PERCENT, "field": "turret_armor", "unit": ""},
	"team_range": {"label": "Weapon range", "kind": K_PERCENT, "field": "team_range", "unit": ""},
	"ward_upgrade": {"label": "Ward sight", "kind": K_SWITCH, "field": "ward_upgrade", "unit": ""},
	"ms_hull": {"label": "Mothership hull", "kind": K_PERCENT, "field": "ms_hull", "unit": ""},
	"ms_shield": {"label": "Mothership shields", "kind": K_PERCENT, "field": "ms_shield", "unit": ""},
	"ms_pd": {"label": "Mothership point-defense guns", "kind": K_BONUS, "field": "ms_pd", "unit": ""},
	"ms_flak": {"label": "Mothership flak batteries", "kind": K_BONUS, "field": "ms_flak", "unit": ""},
	"ms_heavy": {"label": "Mothership heavy cannons", "kind": K_BONUS, "field": "ms_heavy", "unit": ""},
	"ms_ion": {"label": "Mothership ion lances", "kind": K_BONUS, "field": "ms_ion", "unit": ""},
	"minion_buff": {"label": "Minion hull and damage", "kind": K_PERCENT, "field": "minion_buff", "unit": ""},
	"wave_corvette": {"label": "Patrol Leaders in each free wave", "kind": K_BONUS, "field": "wave_corvettes", "unit": ""},
}


## The plain words for what research `id` gives team `ts`, one line for each effect (two for a drive: speed and acceleration).
## While the research is open each line reads "<label>: <now> -> <after>" (a switch "off -> on", a ship unlock "Unlocks:
## <hull name>"); once it is done each line reads "<label>: <now> now". A research with no effect of its own (a chassis that only
## opens a module) gives the one line "No bonus of its own".
static func lines(ts: TeamState, id: String) -> Array[String]:
	var out: Array[String] = []
	var effect: Dictionary = Tech.TECHS[id]["effect"]
	var done := ts.done.has(id)
	for key: String in effect:
		var row: Dictionary = ROWS.get(key, {})
		if row.is_empty():
			continue
		var v: Variant = effect[key]
		match int(row["kind"]):
			K_UNLOCK:
				out.append("%s: %s" % [row["label"], hull_label(str(v))])
			K_LEVEL:
				out.append_array(_level_lines(ts, key, str(v), done))
			K_SWITCH:
				var on := bool(ts.get(str(row["field"])))
				out.append("%s: %s" % [row["label"], "on now" if done and on else ("off -> on" if not on else "on -> on")])
			_:
				var now := _number(row, float(ts.get(str(row["field"]))))
				if done:
					out.append("%s: %s now" % [row["label"], now])
				else:
					out.append("%s: %s -> %s" % [row["label"], now, _number(row, float(ts.get(str(row["field"]))) + float(v))])
	if out.is_empty():
		out.append("No bonus of its own")
	return out


## The combined bonus ship class `tier` ("small", "medium", "large", "capital": Tech.TIERS) has now, as three short pieces:
## "Top speed +16%", "Acceleration +12%", "Hull +15%".
static func class_lines(ts: TeamState, tier: String) -> Array[String]:
	var d := ts.drive_level(tier)
	var a := ts.armor_level(tier)
	return [
		"Top speed %s" % _percent(DRIVE_SPEED * float(d)),
		"Acceleration %s" % _percent(DRIVE_ACCEL * float(d)),
		"Hull %s" % _percent(ARMOR_HULL * float(a)),
	]


## How many levels of effect `key` ("drive" or "armor") the research tree gives class `tier`: the research items whose effect
## names that class.
static func max_level(key: String, tier: String) -> int:
	var n := 0
	for id: String in Tech.ORDER:
		if str((Tech.TECHS[id]["effect"] as Dictionary).get(key, "")) == tier:
			n += 1
	return n


## The levels of class `tier` in words: "Drive 2 of 2 · Armor 0 of 0" (the most each the tree gives).
static func level_text(ts: TeamState, tier: String) -> String:
	return "Drive %d of %d · Armor %d of %d" % [ts.drive_level(tier), max_level("drive", tier), ts.armor_level(tier), max_level("armor", tier)]


## The player's word for ship class `tier`: the names of the hulls of that size, in the order the hangar lists them.
static func tier_label(tier: String) -> String:
	var size := Tech.TIERS.find(tier)
	var names: Array[String] = []
	for hull_id: String in Ships.ORDER:
		if Ships.size_of(hull_id) == size:
			names.append(hull_label(hull_id))
	return ", ".join(names)


## The name of hull `hull_id` as the hangar shows it ("?" for an id the table does not know).
static func hull_label(hull_id: String) -> String:
	if not Ships.HULLS.has(hull_id):
		return "?"
	return str(Ships.HULLS[hull_id]["label"])


## The two lines of a drive research, or the one line of an armor research, for class `tier`. The team's level now and one more
## (or just the level now once the research is done).
static func _level_lines(ts: TeamState, key: String, tier: String, done: bool) -> Array[String]:
	var level := ts.drive_level(tier) if key == "drive" else ts.armor_level(tier)
	var pairs: Array = []
	if key == "drive":
		pairs = [["Top speed", DRIVE_SPEED], ["Acceleration", DRIVE_ACCEL]]
	else:
		pairs = [["Hull", ARMOR_HULL]]
	var out: Array[String] = []
	for p: Array in pairs:
		var step := float(p[1])
		if done:
			out.append("%s: %s now" % [p[0], _percent(step * float(level))])
		else:
			out.append("%s: %s -> %s" % [p[0], _percent(step * float(level)), _percent(step * float(level + 1))])
	return out


## `value` as the row's kind writes it: a percentage ("+8%"), a count ("2"), a bonus ("+4 credits").
static func _number(row: Dictionary, value: float) -> String:
	match int(row["kind"]):
		K_PERCENT:
			return _percent(value)
		K_COUNT:
			return "%d%s" % [roundi(value), row["unit"]]
		_:
			return "+%d%s" % [roundi(value), row["unit"]]


## A fraction as a signed whole percentage: 0.08 -> "+8%".
static func _percent(fraction: float) -> String:
	return "+%d%%" % roundi(fraction * 100.0)
