class_name AdmiralOutbox
extends RefCounted
## WHAT THIS IS: the one door the computer Admiral's fleet layer (AdmiralFleet) sends its orders through (RT8). Every
## order is a record made by Order.make from the Admiral's seat (Rules.ADMIRAL_SEAT, not a human), so the match log's "a"
## lines and --admiral-replay carry it. This is the FULL outbox of build 8b: the orders cap, the reaction delay and the
## waiting list by priority.
##
## HOW IT WORKS: one Admiral think is bracketed by begin_think() and end_think(). begin_think() empties the waiting list;
## send() only adds the order to it (and returns ""); end_think() sends it on:
##   1. it reads the new records of the team's order stream (order_done and order_refused of the Admiral's seat, every
##      order of the seat, the reactions' (AdmiralReactions) and the production's included) and keeps the ticks of those in
##      the last fleet_cap_window_ticks (300);
##   2. it sorts the list by priority (a lower number first, call order inside a priority: PRI_DEFENCE, retreat, help,
##      attack, move);
##   3. it sends each entry through OrderQueue.apply_later (the delay of fleet_order_delay_ticks, 18 = 0.3 s, cut to one tick
##      below the think gap, think_gap_s, so a delayed order lands before the next think) while the cap
##      allows, and drops the rest. The cap test is the window's records plus the slots held for orders still waiting in the
##      queue (an order sent with a delay holds one from its decision until its own record arrives, matched by the record's
##      id) below fleet_cap_orders (20). The reactions' orders count toward the 20 but are never delayed or held.
## The list is rebuilt every think, so no stale order is ever carried. end_think() returns the squad ids named by the
## dropped orders, so the fleet may send them again at the next think.
## The outbox draws no random number and reads no world state but the order stream and the tick count.
##
## WHO USES IT: AdmiralFleet makes one (AdmiralFleet.outbox) and sends every order of the fleet layer through it;
## tests/admiral_fleet_check.gd and tests/admiral_audit.gd read stats().

## The order priorities, most urgent first (the outbox serves a lower number before a higher one).
const PRI_DEFENCE := 0
const PRI_RETREAT := 1  # retreat orders
const PRI_HELP := 2  # help orders
const PRI_ATTACK := 3  # attack (go-in) orders
const PRI_MOVE := 4  # plain move orders
## The names of the priorities, in order (for the counters).
const PRI_NAMES := ["defence", "retreat", "help", "attack", "move"]
## How many apply ticks are kept per squadron (own_ticks).
const OWN_TICKS_KEPT := 4
## The physics ticks in one second of play (project.godot, physics_ticks_per_second).
const TICKS_A_SECOND := 60

## The game world.
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## This Admiral's numbers (the cap, the window and the delay).
var prof: AdmiralProfile
## Counters by name: "sent_<priority>", "ok", "fail", "fail_<refusal text>", "<which>_ok", "<which>_fail", "dropped" and
## "dropped_<priority name>".
var counters := {}
## The squad ids named by the orders the last end_think() sent, sorted.
var last_sent_ids: Array = []
## How many orders the last end_think() sent that were refused at once (at submit).
var last_refused := 0
## The waiting list of the think now going: entries {"pri", "seq", "which", "kind", "settings", "subjects", "target_kind", "target"}.
var _list: Array = []
## How many orders have been put on the list (the call order).
var _seq := 0
## The running index of the next record of the team's stream to read.
var _cursor := 0
## The ticks of the Admiral seat's records inside the cap window (oldest first).
var _ticks: Array = []
## Order id -> the tick it was sent: the slots held by orders still waiting in the queue.
var _reserved := {}
## Squad id -> the apply ticks of the last orders this outbox sent that name it.
var _own := {}


## Make the outbox of team `t` in world `w` with the numbers of profile `p` (null: the team's standard profile). AdmiralFleet
## makes this once. Only the records from now on are read.
func _init(w: World, t: int, p: AdmiralProfile = null) -> void:
	world = w
	team = t
	prof = p if p != null else AdmiralProfile.for_team(t, Game.options)
	if w.events_rts != null:
		_cursor = w.events_rts.next_index(t)


## An Admiral think is starting: the waiting list is emptied.
func begin_think() -> void:
	_list.clear()


## Put one order of the Admiral's seat on the waiting list: `kind` (Move, Hold, Stop or Attack) for the squadrons `subjects`
## (a list of squadron ids) with `target_kind` and `target`, at `priority` (a PRI_ constant). `which` names the rule that sent
## it (for the counters). Nothing is carried out until end_think(), so this always returns "".
func send(priority: int, which: String, kind: String, settings: Dictionary, subjects: Array, target_kind: String, target: Variant) -> String:
	_seq += 1
	_list.append({"pri": clampi(priority, 0, PRI_NAMES.size() - 1), "seq": _seq, "which": which, "kind": kind, "settings": settings,
		"subjects": subjects.duplicate(), "target_kind": target_kind, "target": target})
	return ""


## An Admiral think is over: read the stream, sort the list by priority and send each entry through the delayed door while
## the cap allows; the rest is dropped. Returns the squad ids named by the dropped orders (sorted, each once).
func end_think() -> Array:
	last_sent_ids = []
	last_refused = 0
	_read()
	_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["pri"]) < int(b["pri"]) or (int(a["pri"]) == int(b["pri"]) and int(a["seq"]) < int(b["seq"])))
	# The delay stays below the think gap, so a delayed order always lands before the Admiral's next think.
	var gap_ticks := roundi(prof.f("think_gap_s") * TICKS_A_SECOND)
	var delay := maxi(0, mini(prof.i("fleet_order_delay_ticks"), gap_ticks - 1))
	var cap := prof.i("fleet_cap_orders")
	var sent := {}
	var dropped := {}
	for e: Dictionary in _list:
		var pname := str(PRI_NAMES[int(e["pri"])])
		if _load() >= cap:
			_bump("dropped")
			_bump("dropped_" + pname)
			for id: int in e["subjects"]:
				dropped[id] = true
			continue
		var o := Order.make(str(e["kind"]), team, Deputy.computer_seat(world, team), false, e["settings"], e["subjects"], str(e["target_kind"]), e["target"])
		var why := world.orders.apply_later(o, delay)
		_bump("sent_" + pname)
		_bump("%s_%s" % [str(e["which"]), "ok" if why == "" else "fail"])
		_bump("ok" if why == "" else "fail")
		if why == "":
			var oid := int(o["id"])
			if oid > 0:
				_reserved[oid] = world.tick_count
			for id: int in e["subjects"]:
				sent[id] = true
				var mine: Array = _own.get(id, [])
				mine.append(int(o["apply_tick"]))
				while mine.size() > OWN_TICKS_KEPT:
					mine.pop_front()
				_own[id] = mine
		else:
			_bump("fail_" + why)
			last_refused += 1
		# The records this very send filed (a refusal, or an order applied at once) count from now on.
		_read()
	_list.clear()
	last_sent_ids = sent.keys()
	last_sent_ids.sort()
	var out: Array = dropped.keys()
	out.sort()
	return out


## True when an order delay of `delay_th` ticks stays below a think gap of `gap_th` seconds, both in thousandths as
## AdmiralProfileData.value gives them (so the gap in ticks, in thousandths, is gap_th * 60). end_think() clamps the
## delay to this, and the profile check holds the three profiles to it.
static func delay_below_gap(delay_th: int, gap_th: int) -> bool:
	return delay_th < gap_th * TICKS_A_SECOND


## The apply ticks of the last orders (at most 4) this outbox sent that name squadron `id`, oldest first: an order a
## squadron stands that is not among them was given by something else.
func own_ticks(id: int) -> Array:
	return (_own.get(id, []) as Array).duplicate()


## The seat's slots in use now: the records inside the window plus the orders still waiting in the queue.
func _load() -> int:
	var now := world.tick_count
	var window := prof.i("fleet_cap_window_ticks")
	var kept: Array = []
	for t: int in _ticks:
		if t > now - window:
			kept.append(t)
	_ticks = kept
	for oid: int in _reserved.keys():
		if now - int(_reserved[oid]) > window:
			_reserved.erase(oid)
	return _ticks.size() + _reserved.size()


## Read the new records of the team's stream: each order of the Admiral's seat done or refused adds its tick to the window
## and frees the slot held for its id.
func _read() -> void:
	if world.events_rts == null:
		return
	var next := world.events_rts.next_index(team)
	for rec: Dictionary in world.events_rts.read_from(team, _cursor):
		var k := str(rec.get("kind", ""))
		if k != "order_done" and k != "order_refused":
			continue
		var data: Dictionary = rec.get("data", {})
		if int(data.get("seat", -1)) != Deputy.computer_seat(world, team):
			continue
		_ticks.append(int(rec.get("tick", 0)))
		_reserved.erase(int(data.get("id", 0)))
	_cursor = next


## Add `n` to counter `name`.
func _bump(name: String, n: int = 1) -> void:
	counters[name] = int(counters.get(name, 0)) + n


## Everything the audit prints, as one Dictionary of numbers.
func stats() -> Dictionary:
	return counters.duplicate()
