extends Node
## WHAT THIS IS: the check of the hull data that game code reads instead of naming a hull: the
## role tags on each hull row (Ships.has_role), the default and free hull, the test wing, the
## special id of each hull (ten behaviour lines read it instead of the hull id), the wish lists
## and the Admiral's pairs in the data layer, and that every table keyed by hull has a row for
## every hull of Ships.ORDER.
##
## HOW IT WORKS: setup() runs the parts and prints "hull_data_check: N failures" (a FAIL line,
## labelled with the case's name, for each). The expected tags and specials are typed in this
## file from the hull table's own description, not read from it, so a wrong tag on a row shows.
## The moved lists are compared with the values they had before they moved (OLD_HULL_PREF and
## OLD_MOD_PREF, copied as text from the shopping code).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=hull_data_check
##
## WHO USES IT: main.gd loads it for --test=hull_data_check (it calls setup()), and the check list
## runs it as the row hull_data.

## The ids each role tag must list, in the order of Ships.ORDER.
const EXPECTED_ROLES := {
	"torpedo": ["bomber"],
	"siege": ["bomber"],
	"heavy_hitter": ["lance", "bomber", "ion", "destroyer", "battlecruiser"],
	"no_hunt": ["scout", "logistics"],
	"beam": ["lance"],
	"fixed_beam": ["ion"],
}
## The special ability id of each hull.
const EXPECTED_SPECIAL := {
	"scout": "ping", "fighter": "snap", "lance": "overload", "bomber": "focus", "logistics": "emergency_repair",
	"support": "jam", "flak": "brace", "ion": "capdump", "destroyer": "overcharge", "battlecruiser": "broadside",
}
## The hull wish lists as they were before they moved into Ships.
const OLD_HULL_PREF := {
	"heavy": ["battlecruiser", "destroyer", "flak", "ion", "fighter"],
	"heavy_ion": ["battlecruiser", "destroyer", "ion", "flak", "fighter"],
	"striker": ["bomber", "lance", "fighter"],
	"support": ["support", "logistics", "fighter"],
	"dog": ["fighter"],
	"lancer": ["lance", "fighter"],
	"jungle": ["lance", "fighter"],
}
## The module lists as they were before they moved into Ships.
const OLD_MOD_PREF := {
	"scout": ["engines"], "fighter": ["weapons", "engines"], "lance": ["capacitor", "weapons"],
	"bomber": ["weapons", "shield_booster"], "logistics": ["shield_booster", "plating"],
	"support": ["sensor_suite", "shield_booster"], "flak": ["plating", "shield_booster"],
	"ion": ["capacitor", "plating"], "destroyer": ["plating", "weapons"], "battlecruiser": ["plating", "shield_booster"],
}

## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built.
func setup(_w: World) -> void:
	_roles()
	_constants()
	_specials()
	_lists()
	_tables()
	print("hull_data_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## The role tags: every row has a list of known tags, each tag lists exactly its hulls, has_role answers right.
func _roles() -> void:
	var all_known := true
	for id: String in Ships.ORDER:
		var row: Dictionary = Ships.HULLS[id]
		if not row.has("roles") or not (row["roles"] is Array):
			all_known = false
			continue
		for tag: Variant in (row["roles"] as Array):
			if not (tag is String) or not Ships.ROLE_TAGS.has(tag):
				all_known = false
	_check("roles: every hull has a roles list of known tags", all_known)
	for tag: String in EXPECTED_ROLES:
		var got: Array[String] = []
		for id: String in Ships.ORDER:
			if Ships.has_role(id, tag):
				got.append(id)
		var want: Array = EXPECTED_ROLES[tag]
		_check("roles: %s lists exactly %s" % [tag, ", ".join(PackedStringArray(want))], str(got) == str(want), "got %s" % str(got))
	_check("roles: ROLE_TAGS holds the six tags", str(Ships.ROLE_TAGS) == str(EXPECTED_ROLES.keys()), str(Ships.ROLE_TAGS))
	var answers := Ships.has_role("bomber", "torpedo") and not Ships.has_role("fighter", "torpedo")
	answers = answers and not Ships.has_role("", "torpedo") and not Ships.has_role("no_such_hull", "torpedo")
	answers = answers and not Ships.has_role("bomber", "no_such_tag")
	_check("roles: has_role answers by hull and tag", answers)


## The default hull, the free hull and the test wing.
func _constants() -> void:
	_check("hulls: DEFAULT_HULL is fighter and costs credits", Ships.DEFAULT_HULL == "fighter" and float(Ships.HULLS[Ships.DEFAULT_HULL]["price"]) > 0.0)
	_check("hulls: FREE_HULL is scout and is free", Ships.FREE_HULL == "scout" and float(Ships.HULLS[Ships.FREE_HULL]["price"]) == 0.0)
	_check("hulls: TEST_WING is scout, fighter, bomber", str(Ships.TEST_WING) == str(["scout", "fighter", "bomber"]))


## The special id of every hull: the lines that read it instead of the hull id depend on these.
func _specials() -> void:
	for id: String in Ships.ORDER:
		var want := String(EXPECTED_SPECIAL.get(id, ""))
		var got := String(Ships.HULLS[id].get("special", ""))
		_check("special: %s is %s" % [id, want], got == want, "got %s" % got)


## The lists in the data layer: every hull they name exists, and the moved lists are the old ones.
func _lists() -> void:
	var named: Array[String] = []
	for k: String in Ships.HULL_PREF:
		named.append_array(_strings(Ships.HULL_PREF[k]))
	named.append_array(_strings(Ships.MOD_PREF.keys()))
	named.append_array(_strings(Ships.WISH_LATE_FIRST.values()))
	for k: String in Ships.WISH_CALL:
		named.append_array(_strings(Ships.WISH_CALL[k]))
	named.append(Ships.WISH_CALL_FIRST)
	named.append_array(_strings(Ships.TEST_WING))
	named.append_array(_strings(RtsHulls.FRIGATE_PAIR))
	named.append_array(_strings(RtsHulls.CORVETTE_PAIR))
	named.append_array(_strings(RtsHulls.SPECIAL_PAIR))
	var missing: Array[String] = []
	for id: String in named:
		if not Ships.ORDER.has(id):
			missing.append(id)
	_check("lists: every hull named in a data list exists", missing.is_empty(), "unknown: %s" % str(missing))
	_check("lists: the moved lists equal their old values", _same_lists(Ships.HULL_PREF, OLD_HULL_PREF) and _same_lists(Ships.MOD_PREF, OLD_MOD_PREF))


## Every hull of Ships.ORDER has a row in each table keyed by hull.
func _tables() -> void:
	_has_rows("Ships.HULLS", Ships.HULLS.keys())
	_has_rows("Handling.TABLE", Handling.TABLE.keys())
	_has_rows("AurelianShapes.HULLS", AurelianShapes.HULLS.keys())
	_has_rows("CinderShapes.HULLS", CinderShapes.HULLS.keys())
	_has_rows("Formations.HULL_SHORT", Formations.HULL_SHORT.keys())
	_has_rows("Ships.MOD_PREF", Ships.MOD_PREF.keys())
	_has_rows("HullTables.OUTLINES", HullTables.OUTLINES.keys())
	_has_rows("HullTables.TAGS", HullTables.TAGS.keys())
	_has_rows("HullTables.ICON_SHAPES", HullTables.ICON_SHAPES.keys())
	var trial_hulls: Array = []
	for r: Dictionary in HullTables.TRIALS:
		trial_hulls.append(r["hull"])
	_has_rows("HullTables.TRIALS", trial_hulls)


## One case: `keys` holds every hull of Ships.ORDER.
func _has_rows(table: String, keys: Array) -> void:
	var missing: Array[String] = []
	for id: String in Ships.ORDER:
		if not keys.has(id):
			missing.append(id)
	_check("tables: %s has a row for every hull" % table, missing.is_empty(), "missing: %s" % str(missing))


## `values` as a list of texts (a value that is not a text is kept as its text form, so it can never match an id).
func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in values:
		out.append(str(v))
	return out


## Do two tables of lists hold the same keys with the same lists, in the same order?
func _same_lists(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in a:
		if not b.has(k) or str(a[k]) != str(b[k]):
			return false
	return true
