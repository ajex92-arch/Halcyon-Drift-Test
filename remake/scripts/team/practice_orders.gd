class_name PracticeOrders
extends RefCounted
## WHAT THIS IS: the practice range's one order, PRACTICE: the record the panel sends for each
## of its switches (PracticeSwitches), the checks that refuse it, and the handler that carries
## it out. The panel never changes the world itself: it sends this order, and the world applies
## it at the start of the next tick, stamped with its tick like any order.
##
## HOW IT WORKS: static functions. install() puts the handler and the checker into the match's
## OrderQueue in EVERY match, so a match that is not a practice range refuses the order with the
## range's own words ("Only in the practice range") instead of "Comes with a later stage"; a
## refusal at the door is never queued, never logged and takes no order number, so it cannot
## touch the match. make() builds the record for the human's seat (the pilot's slot or the
## Admiral's seat) with the switch word in its settings, `on` for the toggles and, for one camp,
## the camp's id as the target. send() submits it and gives back the refusal text or "". The
## checker runs at the door and again on the tick the order is carried out; it asks, in this
## order: is this a practice range, is the seat the human's own (the treasury: the Admiral's),
## then the limit or the wait of the switch. The handler runs the switch through PracticeActions
## and, on a success, counts it in Game.usage ("practice_<switch>") and in PracticeRange.uses.
##
## WHO USES IT: WorldSetup (install, in every match), PracticePanel (send), the replay (the
## logged order lines go through the same handler), tests/practice_switch_check.gd.

## Put the handler and the checker of PRACTICE into `w.orders`.
static func install(w: World) -> void:
	var q := w.orders
	q.handlers[OrderKinds.PRACTICE] = func(o: Dictionary) -> String: return handle(w, o)
	q.checkers[OrderKinds.PRACTICE] = func(o: Dictionary) -> String: return check(w, o)


## The record of switch `switch` (a word of PracticeSwitches.WORDS) for the human's seat of
## world `w`. `on` (0 or 1) is given for the toggles and left out (-1) for the rest; `camp` is
## the camp id the order is about (only for the nearest camp).
static func make(w: World, switch: String, on: int = -1, camp: String = "") -> Dictionary:
	var settings := {"switch": switch}
	if on >= 0:
		settings["on"] = on
	var team := 0
	var seat: int = OrderKinds.TEST_SEAT
	var human := false
	if w.human != null:
		team = w.human.team
		seat = w.human.slot
		human = true
	if camp != "":
		return Order.make(OrderKinds.PRACTICE, team, seat, human, settings, [], "id", camp)
	return Order.make(OrderKinds.PRACTICE, team, seat, human, settings)


## Submit switch `switch` for the human's seat of `w` and give back "" (it was accepted and will
## be carried out on the next tick) or the reason it was refused. Only the panel and the tests call it.
static func send(w: World, switch: String, on: int = -1, camp: String = "") -> String:
	return w.orders.submit(make(w, switch, on, camp))


## "" when record `o` may be carried out now, else the refusal text. Asked when the order is
## submitted and again when it is carried out.
static func check(w: World, o: Dictionary) -> String:
	if not w.practice:
		return PracticeSwitches.TEXT_ONLY_RANGE
	var seat := int(o["seat"])
	if w.human == null or (seat != w.human.slot and seat != OrderKinds.TEST_SEAT) or int(o["team"]) != w.human.team:
		return OrderKinds.TEXT_SEAT
	var s: Dictionary = o["settings"]
	var sw := str(s.get("switch", ""))
	var camp := sw == PracticeSwitches.CAMP_NEAR
	if (str(o["target_kind"]) == "id") != camp:
		return OrderKinds.TEXT_VALUE
	if PracticeSwitches.TOGGLES.has(sw) != s.has("on"):
		return OrderKinds.TEXT_VALUE
	match sw:
		PracticeSwitches.WAVE:
			return w.minion_director.wave_refusal()
		PracticeSwitches.CAMPS:
			if w.jungle_director.camps.is_empty():
				return PracticeSwitches.TEXT_NO_JUNGLE
		PracticeSwitches.CAMP_NEAR:
			if not w.jungle_director.camps.has(str(o["target"])):
				return PracticeSwitches.TEXT_NO_CAMP
		PracticeSwitches.CD_RESET:
			if PracticeActions.nothing_to_reset(w):
				return PracticeSwitches.TEXT_NOTHING_TO_RESET
		PracticeSwitches.TREASURY:
			if seat != Rules.ADMIRAL_SEAT:
				return OrderKinds.TEXT_SEAT
			if w.teams[w.human.team].treasury >= PracticeSwitches.LIMIT:
				return PracticeSwitches.TEXT_TREASURY_FULL
		PracticeSwitches.MONEY:
			if w.human.credits >= PracticeSwitches.LIMIT:
				return PracticeSwitches.TEXT_PURSE_FULL
	return ""


## Carry out record `o` (the queue calls this on the tick after it was submitted): run the
## switch, and on a success count it. Returns "" or the refusal text.
static func handle(w: World, o: Dictionary) -> String:
	var s: Dictionary = o["settings"]
	var sw := str(s.get("switch", ""))
	var msg := PracticeActions.run(w, sw, int(s.get("on", 0)) == 1, str(o["target"]))
	if msg == "":
		Game.count_usage("practice_" + sw)
		if w.practice_range != null:
			w.practice_range.note_use(sw, w.tick_count)
	return msg
