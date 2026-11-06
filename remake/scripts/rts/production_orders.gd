class_name ProductionOrders
extends RefCounted
## WHAT THIS IS: the yard's six orders: PRODUCE (buy ships), CANCEL, MOVE_ITEM,
## HOLD_ITEM, SET_REPEAT and SET_RALLY. For each there is a handler that carries
## the order out on the team's build list (Production) and a checker that says
## "no" for the reasons the game can know at once.
##
## HOW IT WORKS: static functions. install() puts the six handlers and the six checkers
## in OrderQueue.handlers and OrderQueue.checkers once, when the match is built. The
## queue calls a checker both when an order is submitted and again when it is carried
## out; a checker returns "" or the refusal text (a code of OrderKinds.REASONS). A
## handler returns "" when it worked, or the refusal text; the queue files the event
## and the toast. PRODUCE is refused at once only for a value that is not allowed, a
## hull that is locked, or a full ship list; it is never refused for money or a full
## fleet: such an order is accepted and waits in the list ("waiting: ore", "waiting:
## fleet full"). The computer Admiral sends the same orders through apply_now().
##
## WHO USES IT: WorldSetup calls install(); the Yard tab and the computer Admiral send
## the orders; tests/production_check.gd checks them.

## Put the six handlers and checkers into `w.orders`.
static func install(w: World) -> void:
	var q := w.orders
	q.handlers[OrderKinds.PRODUCE] = func(o: Dictionary) -> String: return handle_produce(w, o)
	q.handlers[OrderKinds.CANCEL] = func(o: Dictionary) -> String: return handle_cancel(w, o)
	q.handlers[OrderKinds.MOVE_ITEM] = func(o: Dictionary) -> String: return handle_move_item(w, o)
	q.handlers[OrderKinds.HOLD_ITEM] = func(o: Dictionary) -> String: return handle_hold_item(w, o)
	q.handlers[OrderKinds.SET_REPEAT] = func(o: Dictionary) -> String: return handle_set_repeat(w, o)
	q.handlers[OrderKinds.SET_RALLY] = func(o: Dictionary) -> String: return handle_set_rally(w, o)
	q.checkers[OrderKinds.PRODUCE] = func(o: Dictionary) -> String: return check_produce(w, o)
	q.checkers[OrderKinds.CANCEL] = func(o: Dictionary) -> String: return check_item(w, o)
	q.checkers[OrderKinds.MOVE_ITEM] = func(o: Dictionary) -> String: return check_item(w, o)
	q.checkers[OrderKinds.HOLD_ITEM] = func(o: Dictionary) -> String: return check_item(w, o)
	q.checkers[OrderKinds.SET_REPEAT] = func(o: Dictionary) -> String: return check_set_repeat(w, o)
	q.checkers[OrderKinds.SET_RALLY] = func(o: Dictionary) -> String: return check_set_rally(w, o)


## The build list of the team that sent order `o`.
static func _prod(w: World, o: Dictionary) -> Production:
	return w.teams[int(o["team"])].production


# --- checkers -------------------------------------------------------------------------

## PRODUCE: "" or why not. The hull must be a hull of the game and the count one the hull
## allows (1 to 3 for a small hull, 1 for a larger one), a rally of "point" needs its
## point, the hull must be unlocked (not asked of an unlocked Admiral) and the ship list
## must have room (Production's depth). Money and the fleet limit are not asked.
static func check_produce(w: World, o: Dictionary) -> String:
	var s: Dictionary = o["settings"]
	var hull := str(s.get("hull", ""))
	if not Ships.ORDER.has(hull):
		return OrderKinds.TEXT_VALUE
	if int(s.get("count", 0)) > RtsHulls.max_count(hull):
		return OrderKinds.TEXT_VALUE
	if str(s.get("rally", "mothership")) == "point" and not (s.has("rx") and s.has("ry")):
		return OrderKinds.TEXT_VALUE
	var ts: TeamState = w.teams[int(o["team"])]
	if not UnlockAll.is_unlocked(ts) and not ts.ship_unlocked(hull):
		return "Needs %s" % Tech.ship_unlock_label(hull)
	if ts.production.ship_items() >= RtsHulls.DEPTH_SHIPS:
		return "Build queue is full (%d at a time)" % RtsHulls.DEPTH_SHIPS
	return ""


## CANCEL, MOVE_ITEM and HOLD_ITEM: the item must be in the team's list.
static func check_item(w: World, o: Dictionary) -> String:
	if _prod(w, o).find(str(o["target"])).is_empty():
		return OrderKinds.TEXT_NO_ITEM
	return ""


## SET_REPEAT: the target is a hull id of the game.
static func check_set_repeat(_w: World, o: Dictionary) -> String:
	if not Ships.ORDER.has(str(o["target"])):
		return OrderKinds.TEXT_NO_ITEM
	return ""


## SET_RALLY: the target is a ship item of the team's list, or one of its squadrons; a
## rally of "point" needs its point.
static func check_set_rally(w: World, o: Dictionary) -> String:
	var s: Dictionary = o["settings"]
	if str(s.get("rally", "")) == "point" and not (s.has("rx") and s.has("ry")):
		return OrderKinds.TEXT_VALUE
	if str(o["target_kind"]) == "squadron":
		var sq: Squad = w.squads.get(int(o["target"])) as Squad
		if sq == null or sq.team != int(o["team"]) or sq.kind == "wing":
			return OrderKinds.TEXT_GONE_SQUAD
		return ""
	var it := _prod(w, o).find(str(o["target"]))
	if it.is_empty() or it["kind"] != Production.SHIP:
		return OrderKinds.TEXT_NO_ITEM
	return ""


# --- handlers -------------------------------------------------------------------------

## PRODUCE: put the ships in the list. With a `repeat` setting the hull's repeat is set
## too. Returns "" (the checker has run).
static func handle_produce(w: World, o: Dictionary) -> String:
	var s: Dictionary = o["settings"]
	var p := _prod(w, o)
	var hull := str(s["hull"])
	p.add_ship(hull, int(s["count"]), int(o["seat"]), str(s.get("rally", "mothership")), int(s.get("rx", 0)), int(s.get("ry", 0)), int(s.get("fire", 0)), int(s.get("move", 1)))
	if s.has("repeat"):
		p.set_repeat(hull, int(s["repeat"]) == 1)
	return ""


## CANCEL: cancel the item (a started build gives back all it paid).
static func handle_cancel(w: World, o: Dictionary) -> String:
	return _prod(w, o).cancel(str(o["target"]))


## MOVE_ITEM: move the item one place up (dir -1) or down (dir 1).
static func handle_move_item(w: World, o: Dictionary) -> String:
	return _prod(w, o).move(str(o["target"]), int(o["settings"]["dir"]))


## HOLD_ITEM: hold the item (hold 1) or let it go on (hold 0).
static func handle_hold_item(w: World, o: Dictionary) -> String:
	return _prod(w, o).hold(str(o["target"]), int(o["settings"]["hold"]) == 1)


## SET_REPEAT: turn the hull's repeat on (repeat 1) or off (repeat 0).
static func handle_set_repeat(w: World, o: Dictionary) -> String:
	return _prod(w, o).set_repeat(str(o["target"]), int(o["settings"]["repeat"]) == 1)


## SET_RALLY: give a ship item (that has not arrived) or an arrived squadron a new rally.
## A squadron gets the rally as a point at once.
static func handle_set_rally(w: World, o: Dictionary) -> String:
	var s: Dictionary = o["settings"]
	var p := _prod(w, o)
	var kind := str(s["rally"])
	var rx := int(s.get("rx", 0))
	var ry := int(s.get("ry", 0))
	if str(o["target_kind"]) == "squadron":
		(w.squads[int(o["target"])] as Squad).rally = p.rally_point(kind, rx, ry)
		return ""
	return p.set_item_rally(str(o["target"]), kind, rx, ry)
