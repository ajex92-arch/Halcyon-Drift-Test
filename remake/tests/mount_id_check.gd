extends Node
## WHAT THIS IS: the check of the gun names (mount ids) of the two capital hulls,
## the Destroyer and the Battlecruiser. Each gun row of those hulls in Ships has an
## "id": a short lowercase name, unique inside its hull, that is also the name of
## the piece the Aurelian drawing gives that gun's socket (with "mount_" in front
## and a trailing "_port" or "_stbd" cut off, because one mirrored piece serves
## both sides). A launched gun carries the same name as WeaponMount.id.
##
## HOW IT WORKS: setup() runs everything straight away, then quits. Part 1 reads
## data only: the rows of Ships and the pieces of AurelianShapes (counts, spelling,
## uniqueness, the exact names, a drawing piece for each, and no names on the other
## hulls). Part 2 launches each capital for each team and compares every gun of the
## ship with its row (id, weapon, mount type, offset, arc, face, in the row's
## order); launches a Scout and the two frigates, whose guns must carry "" as id; and
## launches a capital with the PD Module, whose extra gun must come last with "".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=mount_id_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL
## <what> <detail>". The last line is "mount_id_check: N failures"; 0 means every
## check passed.
##
## WHO USES IT: main.gd loads it for --test=mount_id_check. It launches extra
## ships into the match it builds, so it is only for this check.

## The names of the Destroyer's guns, in the order of its row.
const DESTROYER_IDS := ["heavy_fore_port", "heavy_fore_stbd", "heavy_aft_port", "heavy_aft_stbd", "chaser_fore", "chaser_aft", "pd_fore_port", "pd_fore_stbd", "pd_aft", "flak_port", "flak_stbd"]
## The names of the Battlecruiser's guns, in the order of its row.
const BATTLECRUISER_IDS := ["ion_port", "ion_stbd", "heavy_fore_port", "heavy_fore_stbd", "heavy_aft_port", "heavy_aft_stbd", "chaser_fore", "chaser_aft", "pd_fore_port", "pd_fore_stbd", "pd_aft_port", "pd_aft_stbd", "flak_port", "flak_stbd"]

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Run every check and
## quit.
func setup(w: World) -> void:
	world = w
	print("mount_id_check: seat=%s" % world.human_role)
	var named := {"destroyer": DESTROYER_IDS, "battlecruiser": BATTLECRUISER_IDS}
	for hid: String in named:
		_check_rows(hid, named[hid])
		_check_drawing(hid)
	_check_unnamed_hulls(named)
	for hid: String in named:
		for team in [Rules.HALCYON, Rules.CINDER]:
			_check_launched(hid, team)
	_check_nameless_launches()
	_check_module_gun()
	print("mount_id_check: %d failures" % fails)
	get_tree().quit()


## Check the rows of hull `hid` in Ships against the names `want`: as many rows as
## names, each id a non-empty lowercase word list with underscores (no space, no
## capital, no digit, so no ticket word), unique, and the set exactly `want`.
func _check_rows(hid: String, want: Array) -> void:
	var rows: Array = Ships.HULLS[hid]["mounts"]
	_check("%s has %d mount rows" % [hid, want.size()], rows.size() == want.size(), str(rows.size()))
	var pattern := RegEx.new()
	pattern.compile("^[a-z]+(_[a-z]+)*$")
	var seen := {}
	var spelled := true
	var typed := true
	for row: Dictionary in rows:
		var v: Variant = row.get("id", null)
		if not (v is String) or String(v) == "":
			typed = false
			continue
		var s := String(v)
		spelled = spelled and pattern.search(s) != null
		seen[s] = true
	_check("%s: every row has a non-empty String id" % hid, typed)
	_check("%s: every id is lowercase words joined by underscores" % hid, spelled)
	_check("%s: the ids are unique" % hid, seen.size() == rows.size(), "%d distinct of %d rows" % [seen.size(), rows.size()])
	var ids: Array = seen.keys()
	ids.sort()
	var sorted_want := want.duplicate()
	sorted_want.sort()
	_check("%s: the ids are exactly the agreed set" % hid, ids == sorted_want, str(ids))
	var in_order := rows.size() == want.size()
	for i in mini(rows.size(), want.size()):
		in_order = in_order and String((rows[i] as Dictionary).get("id", "")) == String(want[i])
	_check("%s: the ids follow the order of the rows" % hid, in_order)


## Check that every id of hull `hid` has its piece in the Aurelian drawing: a piece
## whose "id" is "mount_" plus the gun's id with a trailing "_port" or "_stbd" cut
## off.
func _check_drawing(hid: String) -> void:
	var piece_ids := {}
	for piece: Dictionary in AurelianShapes.HULLS[hid]["pieces"]:
		piece_ids[String(piece["id"])] = true
	var missing: Array[String] = []
	for row: Dictionary in Ships.HULLS[hid]["mounts"]:
		var id := String(row.get("id", ""))
		var base := id
		for tail in ["_port", "_stbd"]:
			if base.ends_with(tail):
				base = base.trim_suffix(tail)
		if not piece_ids.has("mount_" + base):
			missing.append(id)
	_check("%s: every id has its mount piece in the Aurelian drawing" % hid, missing.is_empty(), str(missing))


## Check that no hull but the two capitals has an id key in any gun row (the other
## hulls are not named yet). `named` holds the two capital hull ids as keys.
func _check_unnamed_hulls(named: Dictionary) -> void:
	var stray: Array[String] = []
	var others := 0
	for hid: String in Ships.HULLS:
		if named.has(hid):
			continue
		others += 1
		for row: Dictionary in Ships.HULLS[hid]["mounts"]:
			if row.has("id"):
				stray.append(hid)
	_check("the %d other hulls have no id in any gun row" % others, stray.is_empty(), str(stray))


## Make a docked pilot of `team` in hull `hid` with module list `mods`, launch it,
## and return the ship (null if it did not launch).
func _launch(hid: String, team: int, mods: Array[String] = []) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	p.modules = mods
	world.profiles.append(p)
	var s := world.launch(p)
	if s != null:
		s.controller = null
	return s


## Launch capital `hid` for `team` and compare every gun of the ship with its row:
## the id, the weapon, the mount type, the offset, the arc and the face, in the row's
## order.
func _check_launched(hid: String, team: int) -> void:
	var tname := "Halcyon" if team == Rules.HALCYON else "Cinder"
	var label := "%s %s" % [tname, hid]
	var s := _launch(hid, team)
	if s == null:
		_check("%s launched" % label, false)
		return
	var rows: Array = Ships.HULLS[hid]["mounts"]
	_check("%s: the ship holds one gun per row" % label, s.mounts.size() == rows.size(), "%d guns, %d rows" % [s.mounts.size(), rows.size()])
	var bad: Array[String] = []
	for i in mini(s.mounts.size(), rows.size()):
		var m: WeaponMount = s.mounts[i]
		var row: Dictionary = rows[i]
		var same := m.id == String(row["id"]) and m.weapon_id == String(row["w"])
		same = same and m.mount_type == int(WeaponMount.TYPE_IDS[row["type"]])
		same = same and m.offset == (row["off"] as Vector2)
		same = same and m.arc == deg_to_rad(float(row["arc"]))
		same = same and m.face == deg_to_rad(float(row.get("face", 0.0)))
		if not same:
			bad.append("%d:%s" % [i, m.id])
	_check("%s: every gun carries its row's id, weapon, type, offset, arc and face" % label, bad.is_empty(), str(bad))


## Launch a Scout and the two frigates for each team: none of their guns has a
## name yet, so every id must be "".
func _check_nameless_launches() -> void:
	for team in [Rules.HALCYON, Rules.CINDER]:
		for hid in ["scout", "flak", "ion"]:
			var s := _launch(hid, team)
			if s == null:
				_check("%s launched (team %d)" % [hid, team], false)
				continue
			var named := 0
			for m: WeaponMount in s.mounts:
				if m.id != "":
					named += 1
			_check("%s (team %d): %d guns, none with an id" % [hid, team, s.mounts.size()], named == 0 and s.mounts.size() > 0, "%d named" % named)


## Launch each capital with the PD Module fitted: the ship holds one more gun than
## its row, the extra gun is the last and has id "", and the guns of the row keep
## their ids.
func _check_module_gun() -> void:
	for hid in ["destroyer", "battlecruiser"]:
		var s := _launch(hid, Rules.HALCYON, ["pd_module"] as Array[String])
		if s == null:
			_check("%s with the PD Module launched" % hid, false)
			continue
		var rows: Array = Ships.HULLS[hid]["mounts"]
		_check("%s with the PD Module: one more gun than the row" % hid, s.mounts.size() == rows.size() + 1, "%d guns, %d rows" % [s.mounts.size(), rows.size()])
		var last: WeaponMount = s.mounts[s.mounts.size() - 1]
		_check("%s with the PD Module: the extra gun is the last, with id empty" % hid, last.id == "" and last.weapon_id == "pd_gun", "id '%s' weapon %s" % [last.id, last.weapon_id])
		var kept := true
		for i in rows.size():
			kept = kept and (s.mounts[i] as WeaponMount).id == String((rows[i] as Dictionary)["id"])
		_check("%s with the PD Module: the row's guns keep their ids" % hid, kept)


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
