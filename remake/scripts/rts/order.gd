class_name Order
extends RefCounted
## WHAT THIS IS: the order record. Every order is one small plain Dictionary, so
## it can be queued, written to the match log, read back and sent to another
## player: what to do, who asked, where, and on which tick. No node is ever kept
## in it: units are named by their id number, places by whole-number points.
##
## HOW IT WORKS: Order.make() builds the record with its twelve fields:
##   id          the order's number in this match (0 until OrderQueue gives one)
##   tick        the World tick count when it was submitted
##   apply_tick  the tick on which it is carried out
##   team, seat  who sent it (seat: a pilot 0-4, the Admiral 5, the deputy -1, a test -2)
##   human       true when it came from a human's screen
##   kind        a word from OrderKinds
##   subjects    the squadrons it is for
##   target_kind "none", "point", "unit", "lane", "node", "item", "squadron" or "id"
##   target      a Vector2i point (a human's) or Vector2 point (the computer's, kept
##               as it is), a unit or squadron id, a String id, or 0
##   mode        "replace" (the others are for later)
##   settings    the kind's other arguments: whole numbers and short words
## make() leaves id, tick and apply_tick at -1 because it has no World to read:
## OrderQueue.submit(), apply_now() and AdmiralCommand._order() fill them in.
## to_line() writes a record as one line of the match log and from_line() reads it
## back. The file reader gives every number back as a float, so from_line() turns
## the whole-number fields back into ints by the type each field has.
##
## WHO USES IT: the Admiral's screens (admiral_board_*.gd, command_overlay.gd) make
## records and submit them; AdmiralCommand makes the computer's; OrderQueue and
## OrderLog write and read them; tests/order_check.gd checks the round trip.

## How many ticks after it is submitted a screen's order is carried out (the order
## queue's input delay; the match log's line for a human's order has the later tick).
const INPUT_DELAY := 1

## A fresh record. `settings` and `subjects` are copied. A target of null becomes 0.
static func make(kind: String, team: int, seat: int, human: bool, settings: Dictionary = {}, subjects: Array = [], target_kind: String = "none", target = null) -> Dictionary:
	return {
		"id": -1, "tick": -1, "apply_tick": -1,
		"team": team, "seat": seat, "human": human,
		"kind": kind,
		"subjects": subjects.duplicate(),
		"target_kind": target_kind,
		"target": 0 if target == null else target,
		"mode": "replace",
		"settings": settings.duplicate(),
	}


## A world position as the whole-number point an order carries from a mouse click.
static func point(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.y))


## Who sent it, as the match log marks it: "t" for a test script (seat -2), "h" for
## a human, "a" for the computer.
static func marker(o: Dictionary) -> String:
	if int(o["seat"]) == OrderKinds.TEST_SEAT:
		return "t"
	return "h" if bool(o["human"]) else "a"


## The match log's line for record `o` and its result `code` ("ok" or a reason code):
## nine words separated by single spaces:
##   o <apply_tick> <team> <seat> <h|a|t> <id> <KIND> <json> <code>
## The json is compact and holds subjects, target_kind, target, mode and settings
## in that order. A point is [x,y]: whole numbers for a human, the exact decimal
## text of the number for the computer's float point.
static func to_line(o: Dictionary, code: String) -> String:
	var body := {
		"subjects": o["subjects"], "target_kind": o["target_kind"], "target": _target_json(o["target"]),
		"mode": o["mode"], "settings": o["settings"],
	}
	return "o %d %d %d %s %d %s %s %s" % [int(o["apply_tick"]), int(o["team"]), int(o["seat"]), marker(o), int(o["id"]), str(o["kind"]), JSON.stringify(body, "", false, true), code]


## The result word of a log line made by to_line() ("ok" or a reason code), or "".
static func result_of(line: String) -> String:
	var parts := line.split(" ", false, 8)
	return parts[8] if parts.size() >= 9 else ""


## Read a log line made by to_line() back into a record. Returns {} for anything
## that is not an order line. The tick is worked out: a human's order was submitted
## one input delay before it was carried out, the others on the same tick.
static func from_line(line: String) -> Dictionary:
	var parts := line.split(" ", false, 8)
	if parts.size() < 9 or parts[0] != "o":
		return {}
	var body = JSON.parse_string(parts[7])
	if typeof(body) != TYPE_DICTIONARY:
		return {}
	var kind := parts[6]
	var mark := parts[4]
	var human := mark == "h"
	var apply_tick := int(parts[1])
	var target_kind := str(body.get("target_kind", "none"))
	var o := make(kind, int(parts[2]), int(parts[3]), human, _settings_back(kind, body.get("settings", {})), _ints(body.get("subjects", [])), target_kind, _target_back(target_kind, body.get("target", 0), mark))
	o["id"] = int(parts[5])
	o["apply_tick"] = apply_tick
	o["tick"] = apply_tick - (INPUT_DELAY if human else 0)
	o["mode"] = str(body.get("mode", "replace"))
	return o


## A target as JSON can hold it: a point becomes [x, y].
static func _target_json(t):
	if t is Vector2i:
		return [(t as Vector2i).x, (t as Vector2i).y]
	if t is Vector2:
		return [(t as Vector2).x, (t as Vector2).y]
	return t


## A target read from JSON, turned back into the type its target kind has: a point
## is a Vector2 for the computer (mark "a", float numbers) and a Vector2i otherwise,
## a unit or squadron id an int, "none" the int 0, the rest Strings.
static func _target_back(target_kind: String, t, mark: String):
	match target_kind:
		"point":
			var arr: Array = t
			if mark == "a":
				return Vector2(float(arr[0]), float(arr[1]))
			return Vector2i(roundi(float(arr[0])), roundi(float(arr[1])))
		"unit", "squadron":
			return int(t)
		"none":
			return 0
	return str(t)


## The settings of kind `kind` read from JSON: values of an int row, and of an enum
## row whose values are ints, come back as ints.
static func _settings_back(kind: String, raw) -> Dictionary:
	var out := {}
	var rows: Dictionary = OrderKinds.SETTINGS.get(kind, {})
	for key in raw:
		var v = raw[key]
		if rows.has(key):
			var row: Array = rows[key]
			var is_int: bool = str(row[0]) == "int" or (str(row[0]) == "enum" and not (row[1] as Array).is_empty() and typeof((row[1] as Array)[0]) == TYPE_INT)
			if is_int and typeof(v) == TYPE_FLOAT:
				v = int(v)
		out[key] = v
	return out


## A list of numbers read from JSON, as ints.
static func _ints(raw) -> Array:
	var out: Array = []
	for v in raw:
		out.append(int(v))
	return out
