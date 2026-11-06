class_name OrderKinds
extends RefCounted
## WHAT THIS IS: the one list of order words. Every order in the game, from the
## Admiral's board to a pilot's wing command, is a small record (see Order) with
## a `kind`; this file names each kind and says what it may carry: which kinds of
## target it takes, which settings, who may send it, which word the toast shows
## for it, and which short code a refusal gets.
##
## HOW IT WORKS: only constants and static functions. TARGETS says which target
## kinds a kind accepts. SETTINGS says which keys its `settings` may hold: each key
## has a type ("str", "int" or "enum"), the allowed values, and whether it must be
## there. A key that is absent means "not given": no -1 and no null are ever
## stored. ACTION is the word the order carries to Events.admiral_result (the
## HUD's toast, the fun probe's decision counter), "none" for orders that make no
## toast. may_send() is the "who may send" rule. REASONS is one table of the
## start of every refusal text and the short code it belongs to, so no place that
## refuses an order has to change its words: reason_code() reads the text and
## gives the code (money, room, unlock, place, time, gone, late, online, seat,
## value, unbuilt, unknown, duplicate). The new refusal texts live here too.
##
## WHO USES IT: Order (the record), OrderQueue and OrderChecks (the tiers), AdmiralCommand
## (the words), RtsEvents and AlertList (the codes), the screens (to build records),
## and tests/order_check.gd, which walks every table. The squad kinds are
## only named here; the production kinds are registered by ProductionOrders.

# --- the kinds -----------------------------------------------------------------
## The Admiral's orders of today's game.
const DRONE := "DRONE"  # order one more mining drone
const MODULE := "MODULE"  # build a mothership module
const RESEARCH := "RESEARCH"  # start a research
const TURRET := "TURRET"  # build a turret at a node
const POST := "POST"  # rebuild a lane defense post
const BAY := "BAY"  # send out a repair bay
const WARD := "WARD"  # place a ward
const WAYPOINT := "WAYPOINT"  # set the rally waypoint (may declare a siege)
const MOTHERSHIP_MOVE := "MOTHERSHIP_MOVE"  # move the mothership
## The computer Admiral's siege call (a human declares a siege with a waypoint).
const SIEGE := "SIEGE"  # the computer Admiral's siege state
## Game speed (applied at once, never queued) and the reserved pause.
const GAME_SPEED := "GAME_SPEED"  # change the game speed
const PAUSE := "PAUSE"  # reserved: not built
## The seven squad orders (a pilot's wing, later the Admiral's squadrons).
const ESCORT := "ESCORT"  # a wing follows or defends a ship
const ATTACK := "ATTACK"  # attack a unit
const HOLD := "HOLD"  # hold a point
const MOVE := "MOVE"  # move to a point or to the leader
const GUARD := "GUARD"  # guard a big ship
const SET_FORMATION := "SET_FORMATION"  # choose the formation
const SET_STANCE := "SET_STANCE"  # choose the fire and move stances
## The ship yard's orders.
const PRODUCE := "PRODUCE"  # start building ships
const CANCEL := "CANCEL"  # cancel a build item
const MOVE_ITEM := "MOVE_ITEM"  # move an item up or down the build list
const HOLD_ITEM := "HOLD_ITEM"  # hold or resume a build item
const SET_REPEAT := "SET_REPEAT"  # repeat a hull
const SET_RALLY := "SET_RALLY"  # set a rally point
## Later kinds: the word exists now, and an order of one of them is refused
## "unbuilt" until its stage registers a handler.
const ATTACK_MOVE := "ATTACK_MOVE"  # later
const PATROL := "PATROL"  # later
const STOP := "STOP"  # later
const DEFEND := "DEFEND"  # later
const PUSH_LANE := "PUSH_LANE"  # later
const RETREAT := "RETREAT"  # later
const MERGE := "MERGE"  # later
const PING := "PING"  # later
const REQUEST := "REQUEST"  # later
const ANSWER := "ANSWER"  # later
const DEPUTY := "DEPUTY"  # later
const SET_POSTURE := "SET_POSTURE"  # later: reserved

## Every kind there is.
const ALL := [
	DRONE, MODULE, RESEARCH, TURRET, POST, BAY, WARD, WAYPOINT, MOTHERSHIP_MOVE,
	SIEGE, GAME_SPEED, PAUSE,
	ESCORT, ATTACK, HOLD, MOVE, GUARD, SET_FORMATION, SET_STANCE,
	PRODUCE, CANCEL, MOVE_ITEM, HOLD_ITEM, SET_REPEAT, SET_RALLY,
	ATTACK_MOVE, PATROL, STOP, DEFEND, PUSH_LANE, RETREAT, MERGE, PING, REQUEST, ANSWER, DEPUTY, SET_POSTURE,
]
## The squad orders.
const SQUADRON_KINDS := [ESCORT, ATTACK, HOLD, MOVE, GUARD, SET_FORMATION, SET_STANCE]
## The ship yard's orders.
const PRODUCTION_KINDS := [PRODUCE, CANCEL, MOVE_ITEM, HOLD_ITEM, SET_REPEAT, SET_RALLY]
## The kinds that AdmiralCommand carries out (the queue calls its functions).
const BUILT_IN := [DRONE, MODULE, RESEARCH, TURRET, POST, BAY, WARD, WAYPOINT, MOTHERSHIP_MOVE, SIEGE]
## Kinds that take effect the moment they are submitted, never queued.
const AT_ONCE := [GAME_SPEED]
## The game speeds an order may name, in whole hundredths of normal.
const SPEEDS := [50, 75, 100, 150, 200]

# --- who sends -----------------------------------------------------------------
## The deputy's seat (a later stage's computer helper).
const DEPUTY_SEAT := -1
## A test script's seat: it may send any kind.
const TEST_SEAT := -2

# --- what each kind carries ----------------------------------------------------
## The target kinds each order kind accepts. A point is a Vector2i for a human and
## a Vector2 for the computer Admiral; a unit or squadron target is an id number;
## a lane, node, item or id target is a String; "none" has the target 0.
const TARGETS := {
	DRONE: ["none"], MODULE: ["id"], RESEARCH: ["id"], TURRET: ["node"], POST: ["lane"],
	BAY: ["point"], WARD: ["point"], WAYPOINT: ["point"], MOTHERSHIP_MOVE: ["point"],
	SIEGE: ["lane", "none"], GAME_SPEED: ["none"], PAUSE: ["none"],
	ESCORT: ["unit"], ATTACK: ["unit"], HOLD: ["point"], MOVE: ["point", "unit"], GUARD: ["unit"],
	SET_FORMATION: ["none"], SET_STANCE: ["none"],
	PRODUCE: ["none"], CANCEL: ["item"], MOVE_ITEM: ["item"], HOLD_ITEM: ["item"], SET_REPEAT: ["id"],
	SET_RALLY: ["item", "squadron"],
	ATTACK_MOVE: ["point"], PATROL: ["point"], STOP: ["none"], DEFEND: ["point", "unit"], PUSH_LANE: ["lane"],
	RETREAT: ["none"], MERGE: ["squadron"], PING: ["point"], REQUEST: ["none"], ANSWER: ["none"],
	DEPUTY: ["none"], SET_POSTURE: ["none"],
}
## The settings each kind may carry: key -> [type, allowed, required]. Type "str"
## is a short word with no space or quote; "int" is a whole number inside the
## [low, high] range; "enum" is one of the listed values. A key that is not here
## for the kind is refused, and so is a missing required key.
const SETTINGS := {
	DRONE: {"node": ["str", [], true]},
	MODULE: {}, RESEARCH: {},
	TURRET: {"ttype": ["enum", ["pd", "torp"], true]},
	POST: {}, BAY: {}, WARD: {},
	WAYPOINT: {"siege": ["enum", [0, 1], true]},
	MOTHERSHIP_MOVE: {},
	SIEGE: {"phase": ["enum", ["gather", "assault", ""], true]},
	GAME_SPEED: {"hundredths": ["enum", [50, 75, 100, 150, 200], true]},
	PAUSE: {},
	ESCORT: {"role": ["enum", ["follow", "defend"], false]},
	ATTACK: {},
	HOLD: {"heading": ["int", [0, 359], false]},
	MOVE: {}, GUARD: {},
	SET_FORMATION: {"formation": ["enum", [0, 1, 2, 3], true]},
	SET_STANCE: {"fire": ["enum", [0, 1, 2], false], "move": ["enum", [0, 1, 2], false]},
	PRODUCE: {"hull": ["str", [], true], "count": ["int", [1, 3], true], "repeat": ["enum", [0, 1], false],
		"rally": ["enum", ["mothership", "lane", "point"], false], "rx": ["int", [-1000000, 1000000], false],
		"ry": ["int", [-1000000, 1000000], false], "fire": ["enum", [0, 1, 2], false], "move": ["enum", [0, 1, 2], false]},
	CANCEL: {},
	MOVE_ITEM: {"dir": ["enum", [-1, 1], true]},
	HOLD_ITEM: {"hold": ["enum", [0, 1], true]},
	SET_REPEAT: {"repeat": ["enum", [0, 1], true]},
	SET_RALLY: {"rally": ["enum", ["mothership", "lane", "point"], true], "rx": ["int", [-1000000, 1000000], false],
		"ry": ["int", [-1000000, 1000000], false]},
	ATTACK_MOVE: {}, PATROL: {}, STOP: {}, DEFEND: {}, PUSH_LANE: {}, RETREAT: {}, MERGE: {},
	PING: {}, REQUEST: {}, ANSWER: {},
	DEPUTY: {"preset": ["str", [], true]},
	SET_POSTURE: {},
}
## When each kind takes effect: "next" = a screen's order at the start of the next
## tick and the computer's in its think; "once" = at once (never queued); "same" =
## the computer's, in its think; "later" = reserved, no handler yet.
const APPLIES := {
	DRONE: "next", MODULE: "next", RESEARCH: "next", TURRET: "next", POST: "next", BAY: "next", WARD: "next",
	WAYPOINT: "next", MOTHERSHIP_MOVE: "next",
	SIEGE: "same", GAME_SPEED: "once", PAUSE: "later",
	ESCORT: "next", ATTACK: "next", HOLD: "next", MOVE: "next", GUARD: "next", SET_FORMATION: "next", SET_STANCE: "next",
	PRODUCE: "next", CANCEL: "next", MOVE_ITEM: "next", HOLD_ITEM: "next", SET_REPEAT: "next", SET_RALLY: "next",
	ATTACK_MOVE: "later", PATROL: "later", STOP: "later", DEFEND: "later", PUSH_LANE: "later", RETREAT: "later",
	MERGE: "later", PING: "later", REQUEST: "later", ANSWER: "later", DEPUTY: "later", SET_POSTURE: "later",
}
## The word Events.admiral_result carries for each kind ("none": no toast). The
## first nine are the words the HUD, the fun probe and the audits already read.
## A pilot's squad order sends no toast word (see action_word).
const ACTION := {
	DRONE: "drone", MODULE: "facility", RESEARCH: "research", TURRET: "turret", POST: "post", BAY: "bay",
	WARD: "ward", WAYPOINT: "waypoint", MOTHERSHIP_MOVE: "move",
	SIEGE: "none", GAME_SPEED: "none", PAUSE: "none",
	ESCORT: "squad_escort", ATTACK: "squad_attack", HOLD: "squad_hold", MOVE: "squad_move", GUARD: "squad_guard",
	SET_FORMATION: "squad_formation", SET_STANCE: "squad_stance",
	PRODUCE: "produce", CANCEL: "yard", MOVE_ITEM: "yard", HOLD_ITEM: "yard", SET_REPEAT: "yard", SET_RALLY: "yard",
	ATTACK_MOVE: "none", PATROL: "none", STOP: "none", DEFEND: "none", PUSH_LANE: "none", RETREAT: "none",
	MERGE: "none", PING: "none", REQUEST: "none", ANSWER: "none", DEPUTY: "none", SET_POSTURE: "none",
}

# --- refusal texts and codes ----------------------------------------------------
## The new refusal texts (today's texts stay where they are and are mapped below).
const TEXT_LATE := "Too late"
const TEXT_ONLINE := "Against the computer only"  # refusal text
const TEXT_SEAT := "Not yours to order"  # refusal text
const TEXT_VALUE := "That order is not valid"  # refusal text
const TEXT_SPEED := "Not a speed we have"  # refusal text
const TEXT_NO_ITEM := "No such item"  # refusal text
const TEXT_UNBUILT := "Comes with a later stage"  # refusal text
const TEXT_UNKNOWN := "Unknown order"  # refusal text
const TEXT_REPLAY := "Replaying a recorded match"  # refusal text
const TEXT_GONE_UNIT := "That unit is gone"  # refusal text
const TEXT_GONE_SQUAD := "That squadron is gone"  # refusal text
const TEXT_DUPLICATE := "Same order again"  # refusal text
## Every refusal text by its start, in the order they are tried: [prefix, code].
## One table, so no place that refuses an order needs to change its words.
const REASONS := [
	["Not enough in the team treasury", "money"],
	["Drone limit reached", "room"], ["Drone build queue is full", "room"], ["Build queue is full", "room"],
	["Research queue is full", "room"], ["You already have", "room"],
	["Every turret slot here is taken", "room"],
	["Needs ", "unlock"], ["Already built or being built", "unlock"], ["Already researched or queued", "unlock"],
	["That spot is inside an asteroid", "place"], ["The bay can't reach that spot", "place"],
	["Wards can only go where", "place"], ["No such node", "place"], ["No such post", "place"],
	["That turret site belongs", "place"], ["That jungle node belongs", "place"],
	["Torpedo turrets only go", "place"], ["The enemy has turrets here", "place"],
	["The mothership is too big for the jungle", "place"], ["Too big for the jungle", "place"],
	["The mothership can't find a way there", "place"], ["Too far for the wing", "place"],
	["The mothership's engines come online", "time"], ["The admiral must be docked", "time"],
	["The mothership can't move right now", "time"], ["The post stands", "time"],
	["The post is being rebuilt", "time"], ["The post was destroyed", "time"],
	["Enemy ships are too close", "time"], ["A turret was just destroyed here", "time"],
	[TEXT_GONE_UNIT, "gone"], [TEXT_GONE_SQUAD, "gone"], ["You have no wingmen", "gone"], ["Target not in sight", "gone"],
	[TEXT_SPEED, "value"], [TEXT_VALUE, "value"], [TEXT_NO_ITEM, "value"],
	["No target under the reticle", "value"], ["No big ship under the reticle", "value"],
	[TEXT_LATE, "late"], [TEXT_ONLINE, "online"], [TEXT_SEAT, "seat"], [TEXT_REPLAY, "seat"],
	[TEXT_UNBUILT, "unbuilt"], [TEXT_UNKNOWN, "unknown"], [TEXT_DUPLICATE, "duplicate"],
]
## Every code a refusal can have ("ok" is a success).
const CODES := ["money", "room", "unlock", "place", "time", "gone", "late", "online", "seat", "value", "unbuilt", "unknown", "duplicate"]


## The short code of a result text: "ok" for "" (the order worked), else the code
## of the first REASONS entry the text starts with. A text nothing maps counts as
## "value" (tests/order_check.gd proves every text the game has is mapped).
static func reason_code(msg: String) -> String:
	if msg == "":
		return "ok"
	for row: Array in REASONS:
		if msg.begins_with(str(row[0])):
			return str(row[1])
	return "value"


## The word Events.admiral_result carries for `kind` sent from `seat`: a pilot's
## squad order (seats 0-4) sends none, any other order its ACTION word.
static func action_word(kind: String, seat: int) -> String:
	if SQUADRON_KINDS.has(kind) and seat >= 0 and seat < Rules.PILOTS_PER_TEAM:
		return "none"
	return str(ACTION.get(kind, "none"))


## May `seat` send an order of `kind`? `squad` is the squadron the order is for (a
## squad record or a Dictionary with `owner_seat` and `kind`), or null. The Admiral
## (Rules.ADMIRAL_SEAT) sends the Admiral kinds, the deputy the ones marked for it,
## a pilot sends orders for their own wing and the game speed, a test script
## (TEST_SEAT) any kind. The game speed may be changed from every seat.
static func may_send(kind: String, seat: int, squad = null) -> bool:
	if not ALL.has(kind):
		return false
	if seat == TEST_SEAT or kind == GAME_SPEED:
		return true
	var admiral := seat == Rules.ADMIRAL_SEAT
	var deputy := seat == DEPUTY_SEAT
	if SQUADRON_KINDS.has(kind):
		if squad != null and str(_squad_field(squad, "kind", "")) == "wing":
			return int(_squad_field(squad, "owner_seat", -99)) == seat
		return admiral or deputy
	match kind:
		SIEGE, WAYPOINT, MOTHERSHIP_MOVE, DEPUTY:
			return admiral
		PING, REQUEST, ANSWER:
			return seat >= 0 and seat <= Rules.ADMIRAL_SEAT
		PAUSE, SET_POSTURE:
			return true
	return admiral or deputy


## Does the order record `o` carry only what its kind allows? Returns "" when it
## does, else the refusal text (TEXT_SPEED for a bad game speed, TEXT_VALUE for the rest).
static func value_check(o: Dictionary) -> String:
	var kind := str(o.get("kind", ""))
	if not TARGETS.has(kind):
		return TEXT_UNKNOWN
	var bad := TEXT_SPEED if kind == GAME_SPEED else TEXT_VALUE
	var tk := str(o.get("target_kind", ""))
	if not (TARGETS[kind] as Array).has(tk) or not _target_ok(tk, o.get("target")):
		return TEXT_VALUE
	for s in o.get("subjects", []):
		if typeof(s) != TYPE_INT:
			return TEXT_VALUE
	var rows: Dictionary = SETTINGS[kind]
	var settings: Dictionary = o.get("settings", {})
	for key in settings:
		if not rows.has(key) or not _setting_ok(rows[key], settings[key]):
			return bad
	for key in rows:
		if bool((rows[key] as Array)[2]) and not settings.has(key):
			return bad
	if kind == SET_STANCE and not settings.has("fire") and not settings.has("move"):
		return TEXT_VALUE
	return ""


## Does target `t` have the type that target kind `tk` needs?
static func _target_ok(tk: String, t) -> bool:
	match tk:
		"none":
			return typeof(t) == TYPE_INT and int(t) == 0
		"point":
			return t is Vector2i or t is Vector2
		"unit", "squadron":
			return typeof(t) == TYPE_INT
		"lane", "node", "item", "id":
			return typeof(t) == TYPE_STRING
	return false


## Is value `v` allowed by settings row `row` ([type, allowed, required])?
static func _setting_ok(row: Array, v) -> bool:
	var allowed: Array = row[1]
	match str(row[0]):
		"str":
			return typeof(v) == TYPE_STRING and not (" " in v or "\"" in v or "\n" in v)
		"int":
			return typeof(v) == TYPE_INT and int(v) >= int(allowed[0]) and int(v) <= int(allowed[1])
		"enum":
			if allowed.is_empty() or typeof(v) != typeof(allowed[0]):
				return false
			return allowed.has(v)
	return false


## Field `key` of a squad record that may be a Dictionary or an object, else `fallback`.
static func _squad_field(squad, key: String, fallback):
	if squad is Dictionary:
		return (squad as Dictionary).get(key, fallback)
	if squad is Object:
		var v = (squad as Object).get(key)
		return fallback if v == null else v
	return fallback
