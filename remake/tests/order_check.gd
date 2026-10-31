extends Node
## WHAT THIS IS: the order check. It proves the order record, the order queue, the
## refusals, the event stream, the alert list, the match log and the game speed order
## do what they promise: an order given at tick n is carried out at tick n+1 and not
## before, two orders in one tick go in (seat, id) order, an order given while the game
## is paused is carried out on the first tick after it resumes, every kind of refusal
## comes back with the right code, a written record reads back equal, and the computer
## Admiral's orders are in the log marked "a". It prints PASS or FAIL lines and a last
## line "order_check: N failures".
##
## HOW IT WORKS: setup() starts a coroutine. The checks that need no running match are
## in tests/lib/order_check_pure.gd (the records, the word list, the refusal texts, the
## alert list), the refusal table, the speed order, the stream and the lookups are in
## tests/lib/order_check_refusals.gd, and check (v) (the Admiral's screens) is in
## tests/lib/order_check_screens.gd and runs with --screens. The checks here use the
## queue between ticks and wait for physics frames: after `await physics_frame` the
## World has not yet taken that frame's tick, so one await is one tick.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=7 --check-log=<file> --test=order_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --screens --test=order_check
## --check-log is where the check writes its match log (a scratch file; without it the
## file goes to the game's user folder).
##
## WHO USES IT: main.gd loads it for --test=order_check; docs/CODE_GUIDE.md and the
## README list it.

## The checks that need no running match.
const Pure := preload("res://tests/lib/order_check_pure.gd")
## The refusal table, the speed order, the stream, the ship-lost record and the id lookup.
const Refusals := preload("res://tests/lib/order_check_refusals.gd")
## The Admiral's screens (check v).
const Screens := preload("res://tests/lib/order_check_screens.gd")

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## The order numbers a stub handler saw, in the order it saw them.
var _seen: Array = []
## Where this check writes its match log.
var _log_path := ""


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log_path = str(Game.opt("check-log", "user://order_check.log"))
	_run()


## Print a PASS or FAIL line for the check `what`, with a `detail`, and count failures.
func check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail if not ok else ""])
	if not ok:
		fails += 1


## One tick passes (the World takes the tick of the frame that follows).
func _tick() -> void:
	await get_tree().physics_frame


## The whole check, as a coroutine.
func _run() -> void:
	for i in 3:
		await _tick()
	if bool(Game.opt("screens", false)):
		await Screens.run(self)
	else:
		Pure.texts(self)
		Pure.words(self)
		Pure.round_trips(self)
		Pure.floats(self)
		Pure.alerts(self)
		Refusals.table(self)
		Refusals.hooks(self)
		Refusals.speed(self)
		Refusals.stream(self)
		Refusals.ship_lost(self)
		Refusals.by_uid(self)
		await _queue_checks()
		await _fingerprint_check()
	print("order_check: %d failures" % fails)
	get_tree().quit()


## Checks (a), (b), (c), (e), (h), (l), (m), (u), (x): the queue between and across ticks.
func _queue_checks() -> void:
	var q := world.orders
	var ts := world.teams[0]
	q.log = OrderLog.new()
	check("the match log opens", q.log.open(_log_path, world))
	q.log.header()
	ts.treasury = 20000.0
	# (a) An order submitted at tick n is carried out at tick n+1, and not before.
	var n0 := world.tick_count
	var drones0 := ts.drone_queue.size()
	var o := Refusals.rec(OrderKinds.DRONE, 5, true, {"node": ""})
	check("(a) the order is accepted", q.submit(o) == "")
	check("(a) it is stamped tick n and carried out at tick n+1", int(o["tick"]) == n0 and int(o["apply_tick"]) == n0 + 1 and int(o["id"]) > 0)
	check("(a) it is not carried out before the tick", ts.drone_queue.size() == drones0 and q.queue.size() == 1)
	await _tick()
	check("(a) it is carried out by the next tick", ts.drone_queue.size() == drones0 + 1 and q.queue.is_empty() and world.tick_count == n0 + 1)
	# (b) Two orders in one tick go in (seat, id) order.
	q.handlers[OrderKinds.PING] = func(r: Dictionary) -> String:
		_seen.append(int(r["id"]))
		return ""
	var late_seat := Refusals.rec(OrderKinds.PING, 3, true, {}, [], "point", Vector2i(1, 1))
	var early_a := Refusals.rec(OrderKinds.PING, 1, true, {}, [], "point", Vector2i(1, 1))
	var early_b := Refusals.rec(OrderKinds.PING, 1, true, {}, [], "point", Vector2i(1, 1))
	q.submit(late_seat)
	q.submit(early_a)
	q.submit(early_b)
	await _tick()
	q.handlers.erase(OrderKinds.PING)
	check("(b) two orders in one tick go in (seat, id) order", _seen == [int(early_a["id"]), int(early_b["id"]), int(late_seat["id"])], str(_seen))
	# (c) An order given while the game is paused is carried out on the first tick after.
	get_tree().paused = true
	await _tick()
	await _tick()
	var paused_tick := world.tick_count
	var before := ts.drone_queue.size()
	var held := Refusals.rec(OrderKinds.DRONE, 5, true, {"node": ""})
	check("(c) an order is accepted while paused", q.submit(held) == "")
	check("(c) a refusal comes back at once while paused", q.submit(Refusals.rec(OrderKinds.BAY, 5, true, {}, [], "point", Vector2i(5, 5))) != "")
	await _tick()
	await _tick()
	check("(c) nothing is carried out while paused", ts.drone_queue.size() == before and world.tick_count == paused_tick and q.queue.size() == 1)
	get_tree().paused = false
	await _tick()
	check("(c) it is carried out on the first tick after the resume", ts.drone_queue.size() == before + 1 and int(held["apply_tick"]) == paused_tick + 1 and world.tick_count == paused_tick + 1)
	# (e) A refusal at submit is not logged; one at apply is, with its code.
	q.flush()
	var logged_before := (OrderLog.read(_log_path)["orders"] as Array).size()
	var cursor := world.events_rts.next_index(0)
	var refused := q.submit(Refusals.rec(OrderKinds.BAY, 5, true, {}, [], "point", Vector2i(5, 5)))
	q.flush()
	var at_submit := ""
	for e: Dictionary in world.events_rts.read_from(0, cursor):
		if e["kind"] == "order_refused":
			at_submit = str((e["data"] as Dictionary)["at"])
	check("(e) a refusal at submit is not logged and its event says submit", refused != "" and at_submit == "submit" and (OrderLog.read(_log_path)["orders"] as Array).size() == logged_before, at_submit)
	ts.treasury = 20000.0
	var doomed := Refusals.rec(OrderKinds.DRONE, 5, true, {"node": ""})
	check("(e) an order that passes the first checks is accepted", q.submit(doomed) == "")
	ts.treasury = 0.0
	cursor = world.events_rts.next_index(0)
	await _tick()
	q.flush()
	var read := OrderLog.read(_log_path)
	var last_result := ""
	for i in (read["orders"] as Array).size():
		var r: Dictionary = (read["orders"] as Array)[i]
		if int(r["id"]) == int(doomed["id"]):
			last_result = str((read["results"] as Array)[i])
	var at_apply := ""
	for e: Dictionary in world.events_rts.read_from(0, cursor):
		if e["kind"] == "order_refused" and int((e["data"] as Dictionary)["id"]) == int(doomed["id"]):
			at_apply = str((e["data"] as Dictionary)["at"])
	check("(e) a refusal at apply is logged with its code and its event says apply", last_result == "money" and at_apply == "apply", "%s / %s" % [last_result, at_apply])
	ts.treasury = 20000.0
	# (h) The counters count submitted, carried out and refused per kind.
	var c0 := _kind_counts("DRONE")
	q.submit(Refusals.rec(OrderKinds.DRONE, 5, true, {"node": ""}))
	q.submit(Refusals.rec(OrderKinds.DRONE, 5, true, {"node": ""}))
	var saved_queue := ts.drone_queue.duplicate()
	for i in 6:
		ts.drone_queue.append("")
	q.submit(Refusals.rec(OrderKinds.DRONE, 5, true, {"node": ""}))
	ts.drone_queue = saved_queue
	await _tick()
	var c1 := _kind_counts("DRONE")
	check("(h) DRONE counters: 3 submitted, 2 carried out, 1 refused: room", c1[0] - c0[0] == 3 and c1[1] - c0[1] == 2 and c1[2] - c0[2] == 1, "%s -> %s" % [str(c0), str(c1)])
	# (l) The computer's direct orders are in the log with marker a and the tick of the call.
	ts.drone_queue.clear()
	var think_tick := world.tick_count
	check("(l) a direct call works at once", world.command.build_drone(0) == "")
	q.flush()
	var found := false
	for r: Dictionary in OrderLog.read(_log_path)["orders"]:
		if r["kind"] == OrderKinds.DRONE and Order.marker(r) == "a" and int(r["apply_tick"]) == think_tick:
			found = true
	check("(l) it is in the log with marker a and the tick of the call", found)
	# (m) set_siege writes the three fields as the old lines did.
	var cmd := world.command
	var saved_time := world.time
	ts.siege_lane = ""
	ts.siege_phase = ""
	ts.siege_t = 0.0
	world.time = 100.0
	cmd.set_siege(0, "mid", "gather")
	check("(m) a gather starts: lane, phase and the time it began", ts.siege_lane == "mid" and ts.siege_phase == "gather" and ts.siege_t == 100.0)
	world.time = 130.0
	cmd.set_siege(0, "top", "gather")
	check("(m) a change of lane alone leaves the time", ts.siege_lane == "top" and ts.siege_t == 100.0)
	cmd.set_siege(0, "top", "assault")
	check("(m) gather to assault sets the time", ts.siege_phase == "assault" and ts.siege_t == 130.0)
	world.time = 160.0
	cmd.set_siege(0, "", "")
	check("(m) a call-off clears lane and phase and leaves the time", ts.siege_lane == "" and ts.siege_phase == "" and ts.siege_t == 130.0)
	world.time = saved_time
	q.flush()
	var siege_lines := 0
	for r: Dictionary in OrderLog.read(_log_path)["orders"]:
		if r["kind"] == OrderKinds.SIEGE:
			siege_lines += 1
	check("(m) each siege call is one log line", siege_lines == 4, str(siege_lines))
	# (u) The switch that queues the computer's orders: on, a direct call waits for the next tick.
	ts.drone_queue.clear()
	var d0 := ts.drone_queue.size()
	OrderQueue.AI_THROUGH_QUEUE = true
	var queued := world.command.build_drone(0)
	OrderQueue.AI_THROUGH_QUEUE = false
	check("(u) with the switch on a direct call is queued, not carried out", queued == "" and q.queue.size() == 1 and ts.drone_queue.size() == d0)
	await _tick()
	check("(u) it is carried out on the next tick with the same result", q.queue.is_empty() and ts.drone_queue.size() == d0 + 1)
	var d1 := ts.drone_queue.size()
	world.command.build_drone(0)
	check("(u) with the switch off a direct call is carried out at once", ts.drone_queue.size() == d1 + 1 and q.queue.is_empty())
	# (x) During a replay of the computer's orders a direct call is refused and changes nothing.
	var counts_before := q.counters()
	var d2 := ts.drone_queue.size()
	var money := ts.treasury
	q.replaying_ai = true
	var direct := world.command.build_drone(0)
	q.replaying_ai = false
	check("(x) a direct call during a replay of the computer's orders changes nothing", direct == "" and ts.drone_queue.size() == d2 and ts.treasury == money and q.counters() == counts_before)


## The counters of kind `kind` for team 0 as [submitted, ok, refused (all codes)].
func _kind_counts(kind: String) -> Array:
	var row: Dictionary = (world.orders.counters().get("t0", {}) as Dictionary).get(kind, {})
	var refused := 0
	for code in (row.get("refused", {}) as Dictionary):
		refused += int((row["refused"] as Dictionary)[code])
	return [int(row.get("submitted", 0)), int(row.get("ok", 0)), refused]


## Check (g): the match log's fingerprint is the same text as the det_hash test's, tick
## for tick, for 60 ticks.
func _fingerprint_check() -> void:
	var det: Node = load("res://tests/det_hash.gd").new()
	det.set("world", world)
	var differ := 0
	for i in 60:
		await _tick()
		if OrderLog.fingerprint(world) != str(det.call("_fingerprint")):
			differ += 1
	det.free()
	check("(g) the log's fingerprint equals det_hash's for 60 ticks", differ == 0, "%d differ" % differ)
