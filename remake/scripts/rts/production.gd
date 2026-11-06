class_name Production
extends RefCounted
## WHAT THIS IS: the yard's build list of one team. Everything the Admiral buys with
## the team's ore goes through this one ordered list: fleet ships, research,
## modules and mining drones. Each item waits for its turn, pays when it starts,
## builds on its own line, and can be moved, held or cancelled.
##
## HOW IT WORKS: `items` is the list in the order the player set. An item is a small
## plain Dictionary (see _new_item). Five lines build side by side: the yard (two
## ships that are not capital ships), the warp line (one capital ship), the
## laboratory, the module dock and the drone bay (one item each). Every tick,
##   1. an item of research, a module or a drone that has left the team's old queue
##      (TeamState.research, .building or .drone_queue, which hold only the item
##      being built) is finished and leaves the list;
##   2. the ships being built count up one tick, and one whose time is complete
##      arrives (Arrivals) and leaves the list;
##   3. the ore turn walks the list in order. An item that is on hold, or blocked by a
##      busy line, a full fleet or a missing unlock, is passed over and does not hold
##      the turn. The first item whose only blocker is ore holds the turn: nothing
##      behind it starts. An item with no blocker pays and starts.
## Paying takes the whole price from the team's treasury when the item starts, so a
## waiting item has paid nothing. Cancelling an item that has started gives back
## everything it paid and its place in the fleet. Holding a started item keeps its
## progress, its paid ore and its place and frees its line.
## A research, module or drone item that is building also sits in the old queue the
## rest of the game reads (the board, the HUD, the computer's plan); holding it takes
## it out of there and putting it back is the "resume".
## A ship item makes its squad record (Squad) when it starts, so events can name it.
## All numbers are whole; the timers of ships count ticks.
##
## WHO USES IT: TeamState makes one per team (ts.production) and ticks it; TeamTech,
## TeamDrones and AdmiralCommand put items in it; the order handlers
## (ProductionOrders) change it; the Yard tab and the computer Admiral read it;
## Arrivals makes the ships.

## The kinds of item.
const SHIP := "ship"
const RESEARCH := "research"  # a research item (the lab)
const MODULE := "module"  # a mothership module (the dock)
const DRONE := "drone"  # a mining drone (the drone bay)

## The team's state (reached through a weak link, see _ts_ref).
var ts: TeamState:
	get:
		return _ts_ref.get_ref() as TeamState

## A weak link to the team: TeamState holds this part with a normal link.
var _ts_ref: WeakRef
## The world.
var world: World
## The team: 0 or 1.
var team := 0
## The fleet limit of the team.
var capacity: Capacity
## The list, in order. Each entry is an item Dictionary.
var items: Array = []
## Hull id -> 1 for the hulls that are bought again when an item of them is done.
var repeat := {}
## Ticks this part has run.
var ticks := 0
## The arrival pictures: Dictionaries Arrivals fills and RtsFx draws.
var fx: Array = []
## The stand-in brains (PilotAI) of the bought ships that are alive (Standin).
var standins: Array = []
## The items a repeat queued again, as {"hull", "count", "price"}, until the one who reads them
## (the computer Admiral's log) takes them with take_requeued().
var requeued: Array = []
## The number of the next item.
var _next_n := 1
## True while some item is blocked by a full fleet (so "cap_full" is filed once).
var _cap_blocked := false
## The lane helper for the "lane" rally (made when first needed).
var _lanes: AdmiralLanes


## Make the list of the team `owner`. TeamState makes this once.
func _init(owner: TeamState) -> void:
	_ts_ref = weakref(owner)
	world = owner.world
	team = owner.team
	capacity = Capacity.new(world, team)


# --- making items -------------------------------------------------------------------

## A new item of `kind` ("ship", "research", "module" or "drone") for `what` (a hull id,
## a tech id, a facility id or a mining node id), not yet in the list.
func _new_item(kind: String, what: String) -> Dictionary:
	var item := {
		"id": "t%di%d" % [team, _next_n], "kind": kind, "what": what, "count": 1,
		"price": 0, "paid": 0, "started": false, "running": false, "held": false,
		"ticks": 0, "done": 0, "left": 0.0, "total": 0.0, "squad": 0, "warp": false,
		"rally": "mothership", "rx": 0, "ry": 0, "fire": 0, "move": 1,
		"why": "", "need": 0, "need_text": "", "seat": Rules.ADMIRAL_SEAT, "queued": world.tick_count,
	}
	_next_n += 1
	return item


## Put a ship item in the list: `count` ships of `hull`, bought by `seat`, going to the
## rally `rally` ("mothership", "lane" or "point", with the point rx, ry). Returns the item.
## The caller has checked the rules (ProductionOrders.check_produce).
func add_ship(hull: String, count: int, seat: int = Rules.ADMIRAL_SEAT, rally: String = "mothership", rx: int = 0, ry: int = 0, fire: int = 0, move: int = 1) -> Dictionary:
	var item := _new_item(SHIP, hull)
	item["count"] = clampi(count, 1, RtsHulls.max_count(hull))
	item["price"] = RtsHulls.price_of(hull, int(item["count"]))
	item["ticks"] = RtsHulls.build_ticks(hull)
	item["seat"] = seat
	item["rally"] = rally
	item["rx"] = rx
	item["ry"] = ry
	item["fire"] = fire
	item["move"] = move
	items.append(item)
	return item


## The items a repeat queued again since the last call, as {"hull", "count", "price"}; the list
## is emptied.
func take_requeued() -> Array:
	var out := requeued.duplicate()
	requeued.clear()
	return out


## For tests and tools: `count` ships of `hull` that skip the waiting, the paying and the
## building. The item is made started and complete, its squad record is made and its ships
## arrive at once (Arrivals), so they exist when this returns. The fleet limit still binds:
## with no room an empty Dictionary comes back and nothing is made. Returns the item (it
## has left the list when the ships have arrived).
func spawn_now(hull: String, count: int, seat: int = Rules.ADMIRAL_SEAT, rally: String = "mothership", rx: int = 0, ry: int = 0) -> Dictionary:
	var it := add_ship(hull, count, seat, rally, rx, ry)
	if not capacity.room_for(int(it["count"])):
		items.erase(it)
		return {}
	it["started"] = true
	it["running"] = true
	it["done"] = int(it["ticks"])
	capacity.reserve(int(it["count"]))
	_make_squad(it)
	if Arrivals.arrive(world, self, it):
		_finish_ship(it)
	return it


## Put research `id` in the list. TeamTech.queue_research() has checked the rules.
func add_research(id: String) -> Dictionary:
	var item := _new_item(RESEARCH, id)
	item["price"] = roundi(float(Tech.TECHS[id]["cost"]))
	items.append(item)
	return item


## Put module (facility) `id` in the list. TeamTech.queue_facility() has checked the rules.
func add_module(id: String) -> Dictionary:
	var item := _new_item(MODULE, id)
	item["price"] = roundi(float(Tech.FACILITIES[id]["cost"]))
	items.append(item)
	return item


## Put one mining drone for ore node `node_id` ("" = it picks) in the list.
## AdmiralCommand.build_drone() has checked the rules.
func add_drone(node_id: String) -> Dictionary:
	var item := _new_item(DRONE, node_id)
	item["price"] = roundi(float(Structures.MINING_DRONE["cost"]))
	items.append(item)
	return item


# --- questions ------------------------------------------------------------------------

## The item with id `id`, or an empty Dictionary.
func find(id: String) -> Dictionary:
	for it: Dictionary in items:
		if it["id"] == id:
			return it
	return {}


## How many items of `kind` are in the list in all (building, waiting and held).
func count_kind(kind: String) -> int:
	var n := 0
	for it: Dictionary in items:
		if it["kind"] == kind:
			n += 1
	return n


## How many items of `kind` are in the list and not building: waiting or on hold.
## (The item being built is also in the team's old queue, which counts it.)
func idle_count(kind: String) -> int:
	var n := 0
	for it: Dictionary in items:
		if it["kind"] == kind and not it["running"]:
			n += 1
	return n


## Is there an item of `kind` for `what` in the list that is not building (waiting or held)?
func has_idle(kind: String, what: String) -> bool:
	for it: Dictionary in items:
		if it["kind"] == kind and it["what"] == what and not it["running"]:
			return true
	return false


## The `what` of every idle (waiting or held) item of `kind`, in list order.
func idle_whats(kind: String) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		if it["kind"] == kind and not it["running"]:
			out.append(it["what"])
	return out


## How many ship items are in the list (building, waiting and held).
func ship_items() -> int:
	return count_kind(SHIP)


## How many ships are building, waiting or held, counting the ships of every item.
func ships_in_list() -> int:
	var n := 0
	for it: Dictionary in items:
		if it["kind"] == SHIP:
			n += int(it["count"])
	return n


## How many ship items are building (not held).
func ships_building() -> int:
	var n := 0
	for it: Dictionary in items:
		if it["kind"] == SHIP and it["running"]:
			n += 1
	return n


## The ore the first waiting item still needs, or 0 (for the status line).
func ore_short() -> int:
	for it: Dictionary in items:
		if it["why"] == "ore":
			return int(it["need"])
	return 0


## The item's text for its state: "building 40%", "on hold", "launching", or
## "waiting: ore (needs 120)" / "waiting: fleet full" / "waiting: line" / "waiting: unlock
## (needs X)" / "waiting: mothership" / "waiting: turn".
func state_text(it: Dictionary) -> String:
	if it["held"]:
		return "on hold"
	if it["running"]:
		if it["kind"] == SHIP:
			if it["why"] == "mothership":
				return "waiting: mothership"
			if it["warp"]:
				return "launching"
		return "building %d%%" % percent(it)
	match str(it["why"]):
		"ore":
			return "waiting: ore (needs %d)" % int(it["need"])
		"room":
			return "waiting: fleet full"
		"line":
			return "waiting: line"
		"unlock":
			return "waiting: unlock (needs %s)" % str(it["need_text"])
		"mothership":
			return "waiting: mothership"
		"turn":
			return "waiting: turn"
	return "waiting"


## How far item `it` is, 0 to 100. A ship counts its ticks; other items read the team's
## queue (or their saved time when on hold).
func percent(it: Dictionary) -> int:
	if it["kind"] == SHIP:
		return clampi(floori(100.0 * float(it["done"]) / float(maxi(1, int(it["ticks"])))), 0, 100)
	var left: float = float(it["left"])
	var total: float = float(it["total"])
	var e := _line_entry(it)
	if not e.is_empty():
		left = float(e["left"])
		total = float(e["total"])
	if total <= 0.0:
		return 0
	return clampi(int(100.0 * (1.0 - left / total)), 0, 100)


## A plain name for item `it`, for the list rows: "Fighter x3", "Destroyer", a research or
## module name, "Mining drone".
func label(it: Dictionary) -> String:
	match str(it["kind"]):
		SHIP:
			var name := str(Ships.HULLS[str(it["what"])]["label"])
			return "%s x%d" % [name, int(it["count"])] if int(it["count"]) > 1 else name
		RESEARCH:
			return str(Tech.TECHS[str(it["what"])]["label"])
		MODULE:
			return str(Tech.FACILITIES[str(it["what"])]["label"])
	return "Mining drone"


# --- the tick -------------------------------------------------------------------------

## One tick (TeamState.tick calls this while the mothership lives, before the old queues
## move on). `_dt` is not used: the timers count ticks.
func tick(_dt: float) -> void:
	ticks += 1
	_note_finished()
	_progress_ships()
	_ore_turn()
	Standin.keep_alive(world, self)


## Step 1: an item that was building in the team's old queue and is not there any more
## is finished: it leaves the list and the event is filed.
func _note_finished() -> void:
	for it: Dictionary in items.duplicate():
		if it["kind"] == SHIP or not it["running"] or it["held"]:
			continue
		if _line_entry(it).is_empty():
			items.erase(it)
			_push("build_done", it)


## Step 2: count up the ships being built; one whose time is complete arrives (Arrivals).
## While the mothership cannot launch it waits, complete, with the reason "mothership".
func _progress_ships() -> void:
	for it: Dictionary in items.duplicate():
		if it["kind"] != SHIP or not it["running"] or it["held"]:
			continue
		if int(it["done"]) < int(it["ticks"]):
			it["done"] = int(it["done"]) + 1
		Arrivals.on_progress(world, self, it)
		if int(it["done"]) < int(it["ticks"]):
			continue
		if Arrivals.arrive(world, self, it):
			_finish_ship(it)
		else:
			_set_why(it, "mothership")


## A ship item has arrived: its reserved places go (the living ships count now), it leaves
## the list, the event is filed, and a hull on repeat is queued again.
func _finish_ship(it: Dictionary) -> void:
	capacity.release(int(it["count"]))
	items.erase(it)
	_push("build_done", it)
	if int(repeat.get(str(it["what"]), 0)) == 1:
		_requeue(it)


## Repeat: queue the same item again at the end if the list has room for another ship item
## and the fleet has room for its ships at this moment. Otherwise nothing is queued and
## the hull stays on repeat for the next time.
func _requeue(old: Dictionary) -> void:
	if ship_items() >= RtsHulls.DEPTH_SHIPS or not capacity.room_for(int(old["count"])):
		return
	add_ship(str(old["what"]), int(old["count"]), int(old["seat"]), str(old["rally"]), int(old["rx"]), int(old["ry"]), int(old["fire"]), int(old["move"]))
	requeued.append({"hull": str(old["what"]), "count": int(old["count"]), "price": int(old["price"])})
	if requeued.size() > 50:
		requeued.pop_front()


## Step 3: the ore turn (see the top of the file).
func _ore_turn() -> void:
	var holding := false
	var blocked_by_cap := false
	for it: Dictionary in items:
		if it["running"] or it["held"]:
			continue
		# A held-and-resumed item has paid already: it only needs its line back.
		if it["started"]:
			if _line_busy(it):
				_set_why(it, "line")
			else:
				_resume(it)
			continue
		# An item that has not started: first every blocker that is not ore.
		var why := _blocker(it)
		if why == "room":
			blocked_by_cap = true
		if why == "":
			if holding:
				why = "turn"
			elif ts.can_afford(float(it["price"])):
				_start(it)
				_set_why(it, "")
				continue
			else:
				why = "ore"
				it["need"] = int(ceil(float(it["price"]) - ts.treasury))
				holding = true
		_set_why(it, why)
	# "cap_full" is filed once, when the fleet limit first blocks an item.
	if blocked_by_cap and not _cap_blocked:
		_push("cap_full", {})
	_cap_blocked = blocked_by_cap


## The reason item `it` (not started) cannot start, apart from ore: "unlock", "room"
## (the fleet is full), "line" (its line is busy), or "" when only ore can stop it.
func _blocker(it: Dictionary) -> String:
	match str(it["kind"]):
		SHIP:
			var hull := str(it["what"])
			if not UnlockAll.is_unlocked(ts) and not ts.ship_unlocked(hull):
				it["need_text"] = Tech.ship_unlock_label(hull)
				return "unlock"
			if not capacity.room_for(int(it["count"])):
				return "room"
		RESEARCH:
			var b := "" if UnlockAll.is_unlocked(ts) else Tech.tech_blocker(str(it["what"]), ts.facilities, ts.done)
			if b != "":
				it["need_text"] = b.trim_prefix("Needs the ").trim_prefix("Needs ")
				return "unlock"
		MODULE:
			var b2 := "" if UnlockAll.is_unlocked(ts) else Tech.facility_blocker(str(it["what"]), ts.facilities, ts.done)
			if b2 != "":
				it["need_text"] = b2.trim_prefix("Needs the ").trim_prefix("Needs ")
				return "unlock"
	if _line_busy(it):
		return "line"
	return ""


## Is the line of item `it` full?
func _line_busy(it: Dictionary) -> bool:
	match str(it["kind"]):
		SHIP:
			var line := RtsHulls.line_of(str(it["what"]))
			return _ships_on_line(line) >= (RtsHulls.LINE_WARP if line == "warp" else RtsHulls.LINE_YARD)
		RESEARCH:
			return ts.research.size() >= RtsHulls.LINE_LAB
		MODULE:
			return ts.building.size() >= RtsHulls.LINE_DOCK
	return ts.drone_queue.size() >= RtsHulls.LINE_DRONE


## How many ships are building (not held) on `line` ("yard" or "warp").
func _ships_on_line(line: String) -> int:
	var n := 0
	for it: Dictionary in items:
		if it["kind"] == SHIP and it["running"] and RtsHulls.line_of(str(it["what"])) == line:
			n += 1
	return n


## The entry of the team's old queue that item `it` is building as, or an empty Dictionary.
## A ship has none.
func _line_entry(it: Dictionary) -> Dictionary:
	match str(it["kind"]):
		RESEARCH:
			for e: Dictionary in ts.research:
				if e["id"] == it["what"]:
					return e
		MODULE:
			for e2: Dictionary in ts.building:
				if e2["id"] == it["what"]:
					return e2
		DRONE:
			if not ts.drone_queue.is_empty():
				return {"left": ts.drone_t, "total": float(Structures.MINING_DRONE["build"])}
	return {}


# --- starting, resuming ----------------------------------------------------------------

## Pay for item `it` and start it. An unlocked Admiral (UnlockAll) pays nothing.
func _start(it: Dictionary) -> void:
	var price := int(it["price"])
	ts.spend(float(price))
	it["paid"] = 0 if UnlockAll.is_unlocked(ts) else price
	it["started"] = true
	it["running"] = true
	match str(it["kind"]):
		SHIP:
			it["done"] = 0
			capacity.reserve(int(it["count"]))
			_make_squad(it)
		RESEARCH:
			ts.tech.start_research(str(it["what"]))
		MODULE:
			ts.tech.start_facility(str(it["what"]))
		DRONE:
			ts.drone_queue.append(str(it["what"]))
			ts.drone_t = float(Structures.MINING_DRONE["build"])
	_push("build_started", it)


## Put a held item back on its line. It has paid already.
func _resume(it: Dictionary) -> void:
	it["running"] = true
	match str(it["kind"]):
		RESEARCH:
			ts.tech.start_research(str(it["what"]), float(it["left"]))
		MODULE:
			ts.tech.start_facility(str(it["what"]), float(it["left"]))
		DRONE:
			ts.drone_queue.append(str(it["what"]))
			ts.drone_t = float(it["left"])
	_set_why(it, "")


## The squad record of ship item `it`, made when its build starts so events can name it.
## It has no ships yet and the state "launching".
func _make_squad(it: Dictionary) -> void:
	var s := Squad.new()
	s.id = world.registry.next_uid()
	s.team = team
	s.owner_seat = int(it["seat"])
	s.kind = RtsHulls.record_kind(str(it["what"]))
	s.hull_id = str(it["what"])
	s.max_members = RtsHulls.max_count(str(it["what"]))
	s.fire_stance = int(it["fire"])
	s.move_stance = int(it["move"])
	s.state = 6
	s.brain = "standin"
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	it["squad"] = s.id


# --- changing the list (the order handlers call these) ---------------------------------

## Cancel item `id`. A waiting item just leaves; one that has started gives back all it paid
## and its place in the fleet. Returns "" or the refusal text.
func cancel(id: String) -> String:
	var it := find(id)
	if it.is_empty():
		return OrderKinds.TEXT_NO_ITEM
	var refund := 0
	if it["started"]:
		refund = int(it["paid"])
		_leave_line(it)
		if it["kind"] == SHIP:
			capacity.release(int(it["count"]))
			world.squads.erase(int(it["squad"]))
		ts.treasury += float(refund)
	items.erase(it)
	_push("item_cancelled", it, {"refund": refund})
	return ""


## Hold item `id` (`hold` true) or let it go on (false). A held item that has started keeps
## its progress, its paid ore and its place in the fleet, and frees its line. Returns ""
## or the refusal text.
func hold(id: String, hold_it: bool) -> String:
	var it := find(id)
	if it.is_empty():
		return OrderKinds.TEXT_NO_ITEM
	if bool(it["held"]) == hold_it:
		return ""
	it["held"] = hold_it
	if hold_it:
		if it["running"]:
			_leave_line(it, true)
		it["why"] = ""
		_push("item_held", it, {"held": 1})
	else:
		_push("item_held", it, {"held": 0})
	return ""


## Move item `id` one place up (`dir` -1) or down (1) the list. At the end of the list
## nothing happens. Returns "" or the refusal text.
func move(id: String, dir: int) -> String:
	var i := -1
	for k in items.size():
		if items[k]["id"] == id:
			i = k
	if i < 0:
		return OrderKinds.TEXT_NO_ITEM
	var j := i + dir
	if j < 0 or j >= items.size():
		return ""
	var tmp: Dictionary = items[i]
	items[i] = items[j]
	items[j] = tmp
	return ""


## Turn the repeat of hull `hull` on or off. Returns "".
func set_repeat(hull: String, on: bool) -> String:
	repeat[hull] = 1 if on else 0
	return ""


## Give item `id` (a ship item) a new rally: `kind` is "mothership", "lane" or "point"
## (the point rx, ry). Returns "" or the refusal text.
func set_item_rally(id: String, kind: String, rx: int, ry: int) -> String:
	var it := find(id)
	if it.is_empty() or it["kind"] != SHIP:
		return OrderKinds.TEXT_NO_ITEM
	it["rally"] = kind
	it["rx"] = rx
	it["ry"] = ry
	return ""


## The rally point, in whole world units, for a rally of `kind` ("mothership", "lane" or
## "point" with the point rx, ry). "mothership" is RtsHulls.RALLY_AHEAD past the bow;
## "lane" is a point on the lane our team is pushing, a little on our side of the front
## of our minions (the lane that changes every minute while no minion has got out).
func rally_point(kind: String, rx: int, ry: int) -> Vector2i:
	if kind == "point":
		return Vector2i(rx, ry)
	var ms := world.mothership(team)
	if kind == "lane":
		if _lanes == null:
			_lanes = AdmiralLanes.new(world, team)
		var lane := _lanes.push_lane()
		if lane == "":
			lane = MapLayout.LANE_ORDER[int(world.time / 60.0) % 3]
		var frac := clampf(_lanes.front_frac(lane) - 0.04, 0.10, 0.85)
		return Order.point(_lanes.lane_point(lane, frac))
	if ms == null:
		return Vector2i.ZERO
	return Order.point(ms.global_position + Vector2.from_angle(ms.rotation) * (ms.half_len + ms.beam * 0.5 + RtsHulls.RALLY_AHEAD))


## Take item `it` off its line. `keep` true keeps what a later resume needs (the time left
## of a research, a module or a drone); a ship item only stops counting.
func _leave_line(it: Dictionary, keep: bool = false) -> void:
	if not it["running"]:
		return
	it["running"] = false
	match str(it["kind"]):
		SHIP:
			if it["warp"]:
				Arrivals.on_removed(world, self, it)
				it["warp"] = false
		RESEARCH:
			for k in ts.research.size():
				if ts.research[k]["id"] == it["what"]:
					if keep:
						it["left"] = float(ts.research[k]["left"])
						it["total"] = float(ts.research[k]["total"])
					ts.research.remove_at(k)
					break
		MODULE:
			for k2 in ts.building.size():
				if ts.building[k2]["id"] == it["what"]:
					if keep:
						it["left"] = float(ts.building[k2]["left"])
						it["total"] = float(ts.building[k2]["total"])
					ts.building.remove_at(k2)
					break
		DRONE:
			if keep:
				it["left"] = ts.drone_t
				it["total"] = float(Structures.MINING_DRONE["build"])
			ts.drone_queue.clear()


# --- events -----------------------------------------------------------------------------

## Remember why item `it` waits and file "build_blocked" when the reason changes to a
## new one (ore, room, line, unlock, mothership). "turn" is not filed.
func _set_why(it: Dictionary, why: String) -> void:
	if it["why"] == why:
		return
	it["why"] = why
	if why != "" and why != "turn":
		_push("build_blocked", it, {"reason": why})


## File an event of `kind` about item `it` (an empty Dictionary for none) in the stream, with
## the item's id, the squad's id and anything in `extra`.
func _push(kind: String, it: Dictionary, extra: Dictionary = {}) -> void:
	if world.events_rts == null:
		return
	var data := extra.duplicate()
	if not it.is_empty():
		data["item"] = str(it["id"])
		if int(it["squad"]) != 0:
			data["squad"] = int(it["squad"])
	var ms := world.mothership(team)
	world.events_rts.push({"kind": kind, "team": team, "pos": RtsEvents.point_of(ms.global_position) if ms != null else null, "data": data})
