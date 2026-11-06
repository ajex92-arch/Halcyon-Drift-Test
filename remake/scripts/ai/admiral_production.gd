class_name AdmiralProduction
extends RefCounted
## WHAT THIS IS: how the computer Admiral buys fleet ships. It buys through the same build
## list and the same orders as a human Admiral, keeps the list funded, fills its fleet
## steadily, saves for a capital ship and never sits on money. Every buy and every hold goes
## into its log with the reason, as one plain line.
##
## HOW IT WORKS: run() is called once a second (step 8 of AdmiralAI's think) with the money
## to spare. It reads only what a player in its seat could see: its own list, its own
## treasury and its own unlocks, never the enemy's units. Its steps:
##   1. Income: the treasury's earnings of the last INCOME_WINDOW_S seconds, kept as a small
##      ring of whole numbers (one per think).
##   2. The fundable head: the item at the head of the list that only lacks ore holds the
##      ore turn. If its price is more than the treasury plus HEAD_WAIT_S seconds of income,
##      it is put on hold (HOLD_ITEM) so the item behind it can start; a held item goes on
##      again (HOLD_ITEM) when it has become fundable.
##   3. A capital ship: once a Capital Ship Facility stands and a capital hull is unlocked,
##      the Admiral saves for one (no other ship is queued meanwhile). The ship is queued only
##      when its price is within the treasury plus HEAD_WAIT_S seconds of income, so it is
##      never an unfunded head. The goal is given up after SAVING_LAPSE_S seconds, so money
##      does not float. Never more than CAPITAL_MAX_PERCENT of the fleet limit are capital ships.
##   4. The fill schedule: while the fleet (living, building and waiting ships) is below the
##      target for the time (RtsHulls.fill_target), the next item is queued if the list has room
##      and what is already waiting, plus the new item, is within the money to spare plus
##      HEAD_WAIT_S seconds of income, less RESERVE. The mix follows what is unlocked: Fighter
##      squadrons until the Corvette Facility; then one corvette per three squadrons; after the
##      Frigate Facility one frigate per two squadrons; one squadron in three a Lance or Bomber
##      squadron when its research is done. New ships gather on the lane being pushed.
##   5. Repeat: Fighter squadrons are kept on repeat while the fleet is below its target.
## Every number and switch is a named constant of RtsHulls.
##
## WHO USES IT: AdmiralAI makes one per computer team (AdmiralAI.production) and calls run()
## in step 8. Its orders are PRODUCE, HOLD_ITEM and SET_REPEAT, sent through the order
## queue's same-tick door, so they are in the match log as the computer's ("a" lines).

## The game world.
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The lane helper (for the lane we are pushing); the rally "lane" of a bought squadron uses it
## through Production.
var lanes: AdmiralLanes
## The earnings of the last think by think: [match second, credits earned] pairs, whole numbers.
var _earn: Array = []
## The treasury and the credits spent at the last think (to tell earnings from spending).
var _last_treasury := -1.0
var _last_spent := 0.0  # the credits the team had spent as of the last think
## The ids of the items this part put on hold.
var _held := {}
## Squadrons bought since the last corvette, the last frigate and the last special squadron.
var _since_corvette := 0
var _since_frigate := 0  # squadrons bought since the last frigate
var _since_special := 0  # squadrons bought since the last special squadron
## Flips between the two corvettes, the two frigates and the two special squadrons.
var _flip_corvette := 0
var _flip_frigate := 0  # which of the two frigates comes next
var _flip_special := 0  # which of the two special squadrons comes next
## The match second the saving goal began, or -1 for none; and the second before which no new
## goal starts (after one was given up).
var _saving_since := -1.0
var _no_saving_until := 0.0  # no saving goal starts before this match second
## Every line this part has logged (the last 200), for tests.
var log: Array[String] = []


## Remember the world, our team and the lane helper. AdmiralAI makes this part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## One think. `spare` is the credits the Admiral has to spare after its plan and its drones.
func run(ts: TeamState, spare: float) -> void:
	if not RtsHulls.COMPUTER_BUYS:
		return
	var prod := ts.production
	_note_income(ts)
	var income := _income_per_second()
	for r: Dictionary in prod.take_requeued():
		_say("repeats %s x%d (%d): Fighter squadrons are on repeat while the fleet is below its target" % [str(Ships.HULLS[str(r["hull"])]["label"]), int(r["count"]), int(r["price"])])
	if RtsHulls.COMPUTER_HOLDS_HEAD:
		_head_rule(ts, prod, income)
	var saving := false
	if RtsHulls.COMPUTER_SAVES_CAPITAL:
		saving = _capital_goal(ts, prod, income)
	var target := RtsHulls.fill_target(world.time, prod.capacity.limit())
	var total := prod.capacity.alive() + prod.ships_in_list()
	if not saving:
		_fill(ts, prod, income, spare, target, total)
	if RtsHulls.COMPUTER_REPEATS:
		_repeat(prod, total < target)


# --- income ------------------------------------------------------------------------------

## Write down what the treasury earned since the last think: its change plus what was spent.
func _note_income(ts: TeamState) -> void:
	if _last_treasury >= 0.0:
		var gained := (ts.treasury - _last_treasury) + (ts.spent - _last_spent)
		_earn.append([int(world.time), maxi(0, roundi(gained))])
	_last_treasury = ts.treasury
	_last_spent = ts.spent
	while not _earn.is_empty() and world.time - float((_earn[0] as Array)[0]) > RtsHulls.INCOME_WINDOW_S:
		_earn.pop_front()


## The earnings a second over the window (the match's age when it is younger than the window).
func _income_per_second() -> float:
	var sum := 0
	for e: Array in _earn:
		sum += int(e[1])
	return float(sum) / maxf(1.0, minf(RtsHulls.INCOME_WINDOW_S, world.time))


## Can an item of `price` be paid within HEAD_WAIT_S seconds, from the money `have` and the income?
func _fundable(price: float, have: float, income: float) -> bool:
	return price <= have + income * RtsHulls.HEAD_WAIT_S


# --- the fundable head -----------------------------------------------------------------------

## Put the head of the list on hold when it cannot be paid within HEAD_WAIT_S seconds and some
## other item waits behind it (so that one may start), and let a held item go on when the
## treasury can pay it now or nothing waits behind it any more.
func _head_rule(ts: TeamState, prod: Production, income: float) -> void:
	var waiting := 0
	for it: Dictionary in prod.items:
		if not it["started"] and not it["held"]:
			waiting += 1
	for id: String in _held.keys():
		var it := prod.find(id)
		if it.is_empty() or not it["held"]:
			_held.erase(id)
		elif float(it["price"]) <= ts.treasury or waiting == 0:
			if _send(OrderKinds.HOLD_ITEM, {"hold": 0}, "item", id) == "":
				_say("goes on with %s (%d): the treasury %d pays it now or nothing else waits" % [prod.label(it), int(it["price"]), int(ts.treasury)])
				_held.erase(id)
	for it: Dictionary in prod.items:
		if it["running"] or it["held"] or it["started"] or it["why"] != "ore":
			continue
		if waiting > 1 and not _fundable(float(it["price"]), ts.treasury, income):
			if _send(OrderKinds.HOLD_ITEM, {"hold": 1}, "item", str(it["id"])) == "":
				_held[str(it["id"])] = true
				_say("holds %s (%d): the treasury %d and the income %d a second do not pay it within %d seconds, so the next item may start" % [prod.label(it), int(it["price"]), int(ts.treasury), roundi(income), int(RtsHulls.HEAD_WAIT_S)])
		break


# --- a capital ship ---------------------------------------------------------------------------

## The best capital hull the Admiral may build now ("" for none): the Destroyer, else the Battlecruiser.
func _capital_hull(ts: TeamState) -> String:
	if not ts.facilities.has("capital"):
		return ""
	for hull: String in ["destroyer", "battlecruiser"]:
		if ts.ship_unlocked(hull):
			return hull
	return ""


## The saving goal for a capital ship. Returns true while the Admiral is saving (so it queues no
## other ship). Queues the ship when it is fundable within HEAD_WAIT_S seconds.
func _capital_goal(ts: TeamState, prod: Production, income: float) -> bool:
	var hull := _capital_hull(ts)
	if hull == "" or world.time < _no_saving_until:
		_saving_since = -1.0
		return false
	# One at a time, and not past the share of the fleet limit.
	var capitals := 0
	var listed := 0
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.profile != null and s.profile.is_crew and RtsHulls.is_capital(s.hull_id):
			capitals += 1
	for it: Dictionary in prod.items:
		if it["kind"] == Production.SHIP and RtsHulls.is_capital(str(it["what"])):
			capitals += 1
			listed += 1
	var most := maxi(1, floori(float(prod.capacity.limit()) * float(RtsHulls.CAPITAL_MAX_PERCENT) / 100.0))
	if capitals >= most or listed > 0:
		_saving_since = -1.0
		return false
	if not prod.capacity.room_for(1 + prod.ships_in_list() - _building_ships(prod)) or prod.ship_items() >= RtsHulls.DEPTH_SHIPS:
		_saving_since = -1.0
		return false
	var price := float(RtsHulls.price_of(hull, 1))
	if _saving_since < 0.0:
		_saving_since = world.time
		_say("saves for a %s (%d): the treasury %d" % [str(Ships.HULLS[hull]["label"]), int(price), int(ts.treasury)])
	if _fundable(price + _claims(prod), ts.treasury, income):
		if _send(OrderKinds.PRODUCE, {"hull": hull, "count": 1, "rally": "lane"}, "none", 0) == "":
			_say("buys a %s (%d): the treasury %d and the income %d a second pay it within %d seconds" % [str(Ships.HULLS[hull]["label"]), int(price), int(ts.treasury), roundi(income), int(RtsHulls.HEAD_WAIT_S)])
			_saving_since = -1.0
			return false
	if world.time - _saving_since > RtsHulls.SAVING_LAPSE_S:
		_say("gives up saving for a %s after %d seconds: the money goes to the fleet" % [str(Ships.HULLS[hull]["label"]), int(RtsHulls.SAVING_LAPSE_S)])
		_saving_since = -1.0
		_no_saving_until = world.time + RtsHulls.SAVING_LAPSE_S
		return false
	return true


## How many ships are being built (not waiting) in the list.
func _building_ships(prod: Production) -> int:
	var n := 0
	for it: Dictionary in prod.items:
		if it["kind"] == Production.SHIP and it["running"]:
			n += int(it["count"])
	return n


## The credits the items that wait for ore will take: the prices of the ones that have not started
## and are not on hold.
func _claims(prod: Production) -> float:
	var sum := 0.0
	for it: Dictionary in prod.items:
		if not it["started"] and not it["held"]:
			sum += float(it["price"])
	return sum


# --- the fill schedule ------------------------------------------------------------------------

## Queue the next item of the mix when the fleet is below its target (see the top of the file).
func _fill(ts: TeamState, prod: Production, income: float, spare: float, target: int, total: int) -> void:
	if total >= target or prod.ship_items() >= RtsHulls.DEPTH_SHIPS:
		return
	var pick := _next_hull(ts)
	var hull: String = pick[0]
	var count: int = pick[1]
	if hull == "" or total + count > prod.capacity.limit():
		return
	var price := float(RtsHulls.price_of(hull, count))
	var money := minf(spare, ts.treasury)
	if _claims(prod) + price > money + income * RtsHulls.HEAD_WAIT_S - float(RtsHulls.RESERVE):
		return
	if _send(OrderKinds.PRODUCE, {"hull": hull, "count": count, "rally": "lane"}, "none", 0) != "":
		return
	_note_bought(hull)
	_say("buys %s x%d (%d): the fleet is %d of %d wanted by %s, the treasury %d, %d to spare, the income %d a second" % [str(Ships.HULLS[hull]["label"]), count, int(price), total, target, Util.clock(world.time), int(ts.treasury), int(spare), roundi(income)])


## The next hull of the mix and how many ships it has: ["", 0] when nothing can be bought.
func _next_hull(ts: TeamState) -> Array:
	if ts.facilities.has("frigate") and _since_frigate >= RtsHulls.SQUADRONS_PER_FRIGATE:
		var frigate := "ion" if (_flip_frigate % 2 == 0 and ts.ship_unlocked("ion")) else "flak"
		if ts.ship_unlocked(frigate):
			return [frigate, 1]
	if ts.facilities.has("corvette") and _since_corvette >= RtsHulls.SQUADRONS_PER_CORVETTE:
		var corvette := "support" if (_flip_corvette % 2 == 1 and ts.ship_unlocked("support")) else "logistics"
		if ts.ship_unlocked(corvette):
			return [corvette, 1]
	if _since_special >= RtsHulls.SPECIAL_ONE_IN - 1:
		var special := "lance" if _flip_special % 2 == 0 else "bomber"
		if not ts.ship_unlocked(special):
			special = "bomber" if special == "lance" else "lance"
		if ts.ship_unlocked(special):
			return [special, 3]
	return ["fighter", 3]


## Remember that a ship of `hull` was bought, for the mix.
func _note_bought(hull: String) -> void:
	match RtsHulls.class_of(hull):
		"squadron":
			_since_corvette += 1
			_since_frigate += 1
			if hull == "fighter":
				_since_special += 1
			else:
				_since_special = 0
				_flip_special += 1
		"corvette":
			_since_corvette = 0
			_flip_corvette += 1
		"frigate":
			_since_frigate = 0
			_flip_frigate += 1


# --- repeat ------------------------------------------------------------------------------------

## Keep Fighter squadrons on repeat while the fleet is below its target (`below`), off otherwise.
func _repeat(prod: Production, below: bool) -> void:
	if (int(prod.repeat.get("fighter", 0)) == 1) == below:
		return
	_send(OrderKinds.SET_REPEAT, {"repeat": 1 if below else 0}, "id", "fighter")


# --- sending and logging -------------------------------------------------------------------------

## Send an order of the Admiral's seat through the queue's same-tick door. Returns "" or the
## refusal text.
func _send(kind: String, settings: Dictionary, target_kind: String, target) -> String:
	return world.orders.apply_now(Order.make(kind, team, Rules.ADMIRAL_SEAT, false, settings, [], target_kind, target))


## Write one plain line about a decision: into the log and onto the match's output.
func _say(text: String) -> void:
	var line := "YARD t=%d team=%d %s" % [int(world.time), team, text]
	log.append(line)
	if log.size() > 200:
		log.pop_front()
	print(line)
