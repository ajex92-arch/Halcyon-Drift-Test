class_name OrderCheckPure
extends RefCounted
## WHAT THIS IS: the checks of tests/order_check.gd that need no running match: the
## order records, the word list, the refusal texts, the alert list. Each function
## takes the checking test (it has `check(what, ok, detail)`) and reports through it.
##
## HOW IT WORKS: static functions, one per group of checks, lettered as the checks
## are in the order check's header (f, i, n, o, p, q, w). They only call the order
## code's static functions and build their own small objects; they change nothing.
##
## WHO USES IT: tests/order_check.gd.

## The fun probe's economy part, whose NOT_DECISIONS list the action words are checked against.
const EconomyPart := preload("res://tests/lib/fun_probe_economy.gd")

## Every refusal text the game has (one example of each), and the code it must map to.
const TEXTS := [
	["Not enough in the team treasury (120 short)", "money"], ["Not enough in the team treasury", "money"],
	["Drone limit reached (14)", "room"], ["Drone build queue is full (6 at a time)", "room"],
	["Build queue is full (2 at a time)", "room"], ["Research queue is full (3 at a time)", "room"],
	["You already have 3 repair bays", "room"], ["Minion cap reached (12)", "room"],
	["Every turret slot here is taken", "room"],
	["Needs Platform Missiles research", "unlock"], ["Needs Repair Bays research", "unlock"],
	["Needs the Fleet Command Module", "unlock"], ["Needs the Research Module", "unlock"],
	["Needs Lance Beams research", "unlock"], ["Already built or being built", "unlock"],
	["Already researched or queued", "unlock"],
	["That spot is inside an asteroid", "place"], ["The bay can't reach that spot", "place"],
	["Wards can only go where your team can see right now", "place"], ["No such node", "place"],
	["No such post", "place"], ["That turret site belongs to the enemy team", "place"],
	["That jungle node belongs to the enemy team", "place"],
	["Torpedo turrets only go at the inner and inhibitor sites near our mothership", "place"],
	["The enemy has turrets here", "place"],
	["The mothership is too big for the jungle; pick a spot in a lane or base", "place"],
	["Too big for the jungle: pick a lane or the base", "place"],
	["The mothership can't find a way there through open space", "place"], ["Too far for the wing", "place"],
	["The mothership's engines come online at 20:00", "time"], ["The admiral must be docked to move the mothership", "time"],
	["The mothership can't move right now", "time"], ["The post stands", "time"],
	["The post is being rebuilt", "time"], ["The post was destroyed: rebuild in 4:10", "time"],
	["Enemy ships are too close", "time"], ["Enemy ships are too close: 2 pilot ships within 900, nearest 400", "time"],
	["A turret was just destroyed here: no building for 30s", "time"], ["The mothership can't launch minions", "time"],
	["That unit is gone", "gone"], ["That squadron is gone", "gone"], ["You have no wingmen", "gone"],
	["Target not in sight", "gone"],
	["Not a speed we have", "value"], ["That order is not valid", "value"], ["No such item", "value"],
	["No target under the reticle", "value"], ["No big ship under the reticle", "value"],
	["Too late", "late"], ["Against the computer only", "online"], ["Not yours to order", "seat"],
	["Replaying a recorded match", "seat"], ["Comes with a later stage", "unbuilt"], ["Unknown order", "unknown"],
	["Same order again", "duplicate"],
]


## Check (p): every refusal text maps to its code, and "" is "ok".
static func texts(t) -> void:
	var bad := PackedStringArray()
	for row: Array in TEXTS:
		if OrderKinds.reason_code(str(row[0])) != str(row[1]):
			bad.append("%s -> %s" % [row[0], OrderKinds.reason_code(str(row[0]))])
	t.check("(p) every refusal text maps to its code (%d texts)" % TEXTS.size(), bad.is_empty(), "; ".join(bad))
	t.check("(p) a success maps to ok", OrderKinds.reason_code("") == "ok")
	var codes := {}
	for row: Array in OrderKinds.REASONS:
		codes[str(row[1])] = true
	var missing := PackedStringArray()
	for code: String in OrderKinds.CODES:
		if not codes.has(code):
			missing.append(code)
	t.check("(p) every code has a text", missing.is_empty(), ", ".join(missing))


## Check (n) and (o): the word list is whole, and the action words are as promised.
static func words(t) -> void:
	var missing := PackedStringArray()
	for kind: String in OrderKinds.ALL:
		var ok: bool = OrderKinds.TARGETS.has(kind) and OrderKinds.SETTINGS.has(kind) and OrderKinds.APPLIES.has(kind) and OrderKinds.ACTION.has(kind)
		for seat in [-2, -1, 0, 5]:
			OrderKinds.may_send(kind, seat, null)
		if not ok:
			missing.append(kind)
	t.check("(n) every kind has a TARGETS row, a SETTINGS row, an applies mode, an action word and a who-may-send rule (%d kinds)" % OrderKinds.ALL.size(), missing.is_empty(), ", ".join(missing))
	t.check("(n) the tables hold no kind that ALL lacks", OrderKinds.TARGETS.size() == OrderKinds.ALL.size() and OrderKinds.SETTINGS.size() == OrderKinds.ALL.size() and OrderKinds.ACTION.size() == OrderKinds.ALL.size())
	# The eleven words that already existed belong to the eleven old kinds.
	var old_kinds := [OrderKinds.DRONE, OrderKinds.MODULE, OrderKinds.RESEARCH, OrderKinds.TURRET, OrderKinds.POST, OrderKinds.BAY, OrderKinds.WARD, OrderKinds.WAYPOINT, OrderKinds.MOTHERSHIP_MOVE, OrderKinds.MINION_BUY, OrderKinds.MINION_ORDER]
	var seen := {}
	var problems := PackedStringArray()
	var not_decisions: Array = EconomyPart.NOT_DECISIONS
	for kind: String in OrderKinds.ALL:
		var word: String = OrderKinds.ACTION[kind]
		if word != "none" and word != "yard":
			if seen.has(word):
				problems.append("%s used twice" % word)
			seen[word] = kind
		if Hud.RESULT_OK.has(word) and not old_kinds.has(kind):
			problems.append("%s equals a toast word" % word)
		if word in not_decisions and not (word == "yard" or word.begins_with("squad_") or word == "drone" or word == "waypoint" or word == "order"):
			problems.append("%s equals a NOT_DECISIONS entry" % word)
	t.check("(o) action words are unique except none and yard, and clash with no toast word or NOT_DECISIONS entry", problems.is_empty(), "; ".join(problems))
	t.check("(o) \"move\" belongs only to MOTHERSHIP_MOVE", OrderKinds.ACTION[OrderKinds.MOTHERSHIP_MOVE] == "move" and _count_word("move") == 1)
	var yard_ok := true
	for kind: String in OrderKinds.PRODUCTION_KINDS:
		if kind != OrderKinds.PRODUCE:
			yard_ok = yard_ok and OrderKinds.ACTION[kind] == "yard"
	t.check("(o) the yard orders after PRODUCE share the word yard, which is not a decision", yard_ok and "yard" in not_decisions and not Hud.RESULT_OK.has("yard"))
	var squad_ok := true
	for kind: String in OrderKinds.SQUADRON_KINDS:
		squad_ok = squad_ok and (OrderKinds.ACTION[kind] as String) in not_decisions and OrderKinds.action_word(kind, 2) == "none" and OrderKinds.action_word(kind, 5) == OrderKinds.ACTION[kind]
	t.check("(o) the squad words are not decisions, and a pilot's squad order sends no toast word", squad_ok)
	t.check("(o) the speed lists agree with the order words", OrderKinds.SPEEDS == WorldSpeed.HUNDREDTHS.keys())


## How many kinds have the action word `word`.
static func _count_word(word: String) -> int:
	var n := 0
	for kind: String in OrderKinds.ALL:
		if OrderKinds.ACTION[kind] == word:
			n += 1
	return n


## A record of each kind with plausible contents, for the round trip.
static func sample_records() -> Array:
	var out: Array = []
	var p := Vector2i(4210, -880)
	var f := Vector2(4210.123456, -880.5)
	out.append(Order.make(OrderKinds.DRONE, 0, 5, true, {"node": "n12"}))
	out.append(Order.make(OrderKinds.DRONE, 1, 5, false, {"node": ""}))
	out.append(Order.make(OrderKinds.MODULE, 0, 5, true, {}, [], "id", "research"))
	out.append(Order.make(OrderKinds.RESEARCH, 1, 5, false, {}, [], "id", "repairBays"))
	out.append(Order.make(OrderKinds.TURRET, 0, 5, true, {"ttype": "torp"}, [], "node", "n7"))
	out.append(Order.make(OrderKinds.POST, 0, 5, true, {}, [], "lane", "mid"))
	out.append(Order.make(OrderKinds.BAY, 0, 5, true, {}, [], "point", p))
	out.append(Order.make(OrderKinds.BAY, 1, 5, false, {}, [], "point", f))
	out.append(Order.make(OrderKinds.WARD, 1, 5, false, {}, [], "point", Vector2(0.1, 1000.0)))
	out.append(Order.make(OrderKinds.WAYPOINT, 0, 5, true, {"siege": 1}, [], "point", p))
	out.append(Order.make(OrderKinds.WAYPOINT, 1, 5, false, {"siege": 0}, [], "point", f))
	out.append(Order.make(OrderKinds.MOTHERSHIP_MOVE, 0, 5, true, {}, [], "point", p))
	out.append(Order.make(OrderKinds.MINION_BUY, 0, 5, true, {"type": "fighter", "lane": "top"}))
	out.append(Order.make(OrderKinds.MINION_ORDER, 0, 5, true, {"type": "move"}, [12, 13], "point", p))
	out.append(Order.make(OrderKinds.MINION_ORDER, 0, 5, true, {"type": "lane", "lane": "bot"}, [12], "lane", "bot"))
	out.append(Order.make(OrderKinds.SIEGE, 1, 5, false, {"phase": "gather"}, [], "lane", "mid"))
	out.append(Order.make(OrderKinds.SIEGE, 1, 5, false, {"phase": ""}))
	out.append(Order.make(OrderKinds.GAME_SPEED, 0, -2, false, {"hundredths": 200}))
	out.append(Order.make(OrderKinds.ESCORT, 0, 2, true, {"role": "defend"}, [3], "unit", 918))
	out.append(Order.make(OrderKinds.ATTACK, 0, 2, true, {}, [3], "unit", 918))
	out.append(Order.make(OrderKinds.HOLD, 0, 2, true, {"heading": 270}, [3], "point", p))
	out.append(Order.make(OrderKinds.HOLD, 0, 2, true, {}, [3], "point", p))
	out.append(Order.make(OrderKinds.MOVE, 0, 2, true, {}, [3], "unit", 40))
	out.append(Order.make(OrderKinds.MOVE, 0, 5, true, {}, [3], "point", p))
	out.append(Order.make(OrderKinds.GUARD, 0, 2, true, {}, [3], "unit", 41))
	out.append(Order.make(OrderKinds.SET_FORMATION, 0, 2, true, {"formation": 2}, [3]))
	out.append(Order.make(OrderKinds.SET_STANCE, 0, 2, true, {"fire": 2}, [3]))
	out.append(Order.make(OrderKinds.SET_STANCE, 0, 2, true, {"fire": 1, "move": 0}, [3]))
	out.append(Order.make(OrderKinds.PRODUCE, 0, 5, true, {"hull": "fighter", "count": 3, "repeat": 1, "rally": "point", "rx": -4200, "ry": 910}))
	out.append(Order.make(OrderKinds.CANCEL, 0, 5, true, {}, [], "item", "i7"))
	out.append(Order.make(OrderKinds.MOVE_ITEM, 0, 5, true, {"dir": -1}, [], "item", "i7"))
	out.append(Order.make(OrderKinds.SET_RALLY, 0, 5, true, {"rally": "lane"}, [], "squadron", 12))
	out.append(Order.make(OrderKinds.PING, 0, 3, true, {}, [], "point", p))
	out.append(Order.make(OrderKinds.DEPUTY, 0, 5, true, {"preset": "balanced"}))
	return out


## Check (q) and (f): every sample record, and 50 more, survive a write and a read with
## every field equal in value and type; the whole numbers come back as ints.
static func round_trips(t) -> void:
	var recs := sample_records()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 50:
		var r := Order.make(OrderKinds.BAY, i % 2, 5, i % 3 != 0, {}, [], "point", Vector2i(rng.randi_range(-9000, 9000), rng.randi_range(-9000, 9000)))
		if i % 3 == 0:
			r["target"] = Vector2(rng.randf_range(-9000.0, 9000.0), rng.randf_range(-9000.0, 9000.0))
		recs.append(r)
	var bad := PackedStringArray()
	var n := 0
	for r: Dictionary in recs:
		n += 1
		r["id"] = n
		r["apply_tick"] = 100 + n
		r["tick"] = 100 + n - (Order.INPUT_DELAY if bool(r["human"]) else 0)
		var line := Order.to_line(r, "ok")
		var back := Order.from_line(line)
		var same := back.size() == r.size() and line.split(" ").size() == 9 and Order.result_of(line) == "ok"
		for k in r:
			if typeof(back.get(k)) != typeof(r[k]) or back.get(k) != r[k]:
				same = false
		if not same:
			bad.append("%s %s" % [r["kind"], line.left(80)])
	t.check("(f, q) %d records written and read back are equal in value and type" % recs.size(), bad.is_empty(), "; ".join(bad))
	var line := Order.to_line(Order.make(OrderKinds.DRONE, 0, 5, true, {"node": ""}), "money")
	t.check("(f) the result word is the last one", Order.result_of(line) == "money" and Order.from_line("junk").is_empty())


## Check (w): a float written by the log reads back to the same number, over 1000
## random doubles (and 1000 float points).
static func floats(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# The only floats the log holds are a Vector2's components (32-bit numbers). 1000
	# random points, from tiny to the size of the map, are written and read back: every
	# one must come back as the same point.
	var bad := 0
	for i in 1000:
		var scale := pow(10.0, float(rng.randi_range(-6, 0)))
		var v := Vector2(rng.randf_range(-30000.0, 30000.0) * scale, rng.randf_range(-30000.0, 30000.0) * scale)
		var r := Order.make(OrderKinds.WARD, 1, 5, false, {}, [], "point", v)
		r["id"] = 1
		r["apply_tick"] = 5
		var back := Order.from_line(Order.to_line(r, "ok"))
		if back.is_empty() or back["target"] != v:
			bad += 1
	t.check("(w) 1000 random float points (from tiny to map-sized) read back to the same point", bad == 0, "%d differ" % bad)
	# Information only: Godot's number reader is not exact for every double. A written
	# decimal that is read back as a double can land one step off (about one in ten for
	# random 64-bit numbers); a point survives because it is a 32-bit number, which
	# absorbs the step.
	var wide := 0
	for i in 1000:
		var d := rng.randf_range(-30000.0, 30000.0) * pow(10.0, float(rng.randi_range(-6, 2)))
		var back = JSON.parse_string(JSON.stringify([d], "", false, true))
		if typeof(back) != TYPE_ARRAY or float(back[0]) != d:
			wide += 1
	print("info: (w) of 1000 random 64-bit doubles, %d read back one step off as a double" % wide)


## Check (i): the alert list. Priorities sort; two events in one 2,000-unit square merge
## to a count of 2; an alert expires at its lifetime; sounds are capped and keep their
## text; a muted kind is not raised; expired alerts go to `recent`.
static func alerts(t) -> void:
	var a := AlertList.new(0)
	var ev := func(kind: String, pos: Vector2i, data: Dictionary = {}, uid: int = 0, team: int = 0) -> Dictionary:
		return {"tick": 0, "kind": kind, "team": team, "pos": pos, "uid": uid, "data": data}
	a.on_event(ev.call("research_done", Vector2i(0, 0)), 10)
	a.on_event(ev.call("ship_lost", Vector2i(100, 100), {}, 5), 10)
	a.on_event(ev.call("mothership_under_attack", Vector2i(9000, 0)), 10)
	var order: Array = []
	for al: Dictionary in a.live(11):
		order.append(al["kind"])
	t.check("(i) priorities sort (mothership first, research last)", order == ["mothership_under_attack", "ship_lost", "research_done"], str(order))
	var merged := a.on_event(ev.call("ship_lost", Vector2i(1500, 1900), {}, 6), 20)
	t.check("(i) two events in one 2,000-unit square merge to a count of 2", int(merged["count"]) == 2 and String(merged["text"]).ends_with("x2") and a.live(21).size() == 3, str(merged.get("count")))
	var apart := a.on_event(ev.call("ship_lost", Vector2i(5200, 100), {}, 7), 30)
	t.check("(i) an event in another square is another alert", int(apart["count"]) == 1 and a.live(31).size() == 4)
	t.check("(i) jump_pos gives the top alert's place", a.jump_pos(31) == Vector2i(9000, 0), str(a.jump_pos(31)))
	t.check("(i) another team's event is ignored", a.on_event(ev.call("ship_lost", Vector2i(0, 0), {}, 8, 1), 30).is_empty())
	var life := int((AlertList.KINDS["research_done"] as Dictionary)["life"])
	t.check("(i) an alert is alive until its lifetime ends", _has_kind(a.live(10 + life - 1), "research_done") and not _has_kind(a.live(10 + life), "research_done"))
	t.check("(i) an expired alert is in `recent`", a.recent.size() >= 1 and String((a.recent[0] as Dictionary)["kind"]) == "research_done")
	# The sounds: the first may sound; the same kind from the same source inside 15 s may not;
	# the whole list sounds at most once a second.
	var v := AlertList.new(0)
	var first := v.on_event(ev.call("ship_lost", Vector2i(0, 0), {}, 50), 1000)
	var second := v.on_event(ev.call("turret_lost", Vector2i(9000, 9000), {}, 51), 1010)
	var third := v.on_event(ev.call("ship_lost", Vector2i(30000, 0), {}, 50), 1500)
	var fourth := v.on_event(ev.call("ship_lost", Vector2i(30000, 9000), {}, 52), 1100)
	t.check("(i) the first sound is allowed", bool(first["voice"]))
	t.check("(i) a second sound inside one second is capped, its text kept", not bool(second["voice"]) and String(second["text"]) == "Turret lost")
	t.check("(i) the same source may not raise the same kind again inside 15 s", not bool(third["voice"]) and String(third["text"]) == "Ship lost")
	t.check("(i) another source is heard after the global gap", bool(fourth["voice"]))
	var m := AlertList.new(0)
	m.mute["ship_lost"] = true
	t.check("(i) a muted kind is not raised", m.on_event(ev.call("ship_lost", Vector2i(0, 0)), 5).is_empty() and m.live(6).is_empty())


## Does the list of alerts hold one of kind `kind`?
static func _has_kind(list: Array, kind: String) -> bool:
	for al: Dictionary in list:
		if al["kind"] == kind:
			return true
	return false
