extends Node
## WHAT THIS IS: the replay check. It proves that a match repeats from its log: a match
## with a human Admiral who gives a fixed list of orders is played once with the match log
## on, and again from the log alone; and an all-computer match is played once with the log
## on and again with the computer Admirals' own orders played back instead of their
## thinking. Every fingerprint line of the second run must equal the first run's.
##
## HOW IT WORKS: this test node is the same in every run, so the runs have the same
## nodes. setup() adds the det_hash test as its child (it prints the hash lines the runs are
## compared by). With --script it also acts as the human Admiral: at fixed ticks it submits
## a list of orders (drones, a Research Module and a research, ships bought, held, moved and
## cancelled, a turret, a repair bay, wards, a waypoint; in a --late match a mothership move, a
## Destroyer bought, held and cancelled, and a siege waypoint) as seat 5 with
## `human` true, so they are marked "h" in the log and can be replayed. When the run ends it
## prints "order_replay: N failures": with --script it checks that every order that was
## accepted is in the log and that the log has its header, fingerprint lines and end line;
## during --replay or --admiral-replay it checks that the replay compared fingerprints, that
## the header agreed and that none differed. The driver script compares the runs' hash lines.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/; the driver in the lead's tools runs the whole sequence):
##   run 1: godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --seed=7 --secs=600 --script --order-log=<file> --test=order_replay
##   run 2: godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --seed=7 --secs=600 --replay=<file> --test=order_replay
##   computer: godot --headless --path remake --fixed-fps 60 -- --all-ai --no-admiral-field --seed=7 --secs=600 --order-log=<file> --test=order_replay
##             godot --headless --path remake --fixed-fps 60 -- --all-ai --no-admiral-field --seed=7 --secs=600 --admiral-replay=<file> --test=order_replay
## (add --late and --secs=300 for the late-game runs)
##
## WHO USES IT: main.gd loads it for --test=order_replay; the replay gate script runs it.

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## The hash test that prints the lines the runs are compared by.
var _det: Node
## The orders to give: [tick, kind, target_kind, target, settings], in tick order.
var _list: Array = []
## How many of them have been given.
var _given := 0
## How many were accepted by the queue.
var _accepted := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	_det = load("res://tests/det_hash.gd").new()
	add_child(_det)
	_det.call("setup", w)
	if bool(Game.opt("script", false)):
		_list = _late_list() if bool(Game.opt("late", false)) else _normal_list()


## The orders of the normal 600-second match: [tick, kind, target_kind, target, settings].
func _normal_list() -> Array:
	var spot := OrderCheckRefusals.open_spot(world)
	var sp := Order.point(spot)
	var node_id := ""
	for n in world.nodes:
		if n.side == world.human_team and n.free_slot() >= 0:
			node_id = n.node_id
			break
	var mid := Order.point(Vector2(MapLayout.CX, MapLayout.CY - 1400.0))
	return [
		[120, OrderKinds.DRONE, "none", 0, {"node": ""}],
		[600, OrderKinds.MODULE, "id", "research", {}],
		[900, OrderKinds.DRONE, "none", 0, {"node": ""}],
		[2400, OrderKinds.PRODUCE, "none", 0, {"hull": "fighter", "count": 3, "rally": "mothership"}],
		[3000, OrderKinds.HOLD_ITEM, "item", "@ship", {"hold": 1}],
		[3300, OrderKinds.HOLD_ITEM, "item", "@ship", {"hold": 0}],
		[3600, OrderKinds.PRODUCE, "none", 0, {"hull": "fighter", "count": 2, "rally": "lane", "repeat": 1}],
		[4200, OrderKinds.MOVE_ITEM, "item", "@ship", {"dir": 1}],
		[4800, OrderKinds.CANCEL, "item", "@ship", {}],
		[9000, OrderKinds.RESEARCH, "id", "repairBays", {}],
		[12000, OrderKinds.TURRET, "node", node_id, {"ttype": "pd"}],
		[15000, OrderKinds.BAY, "point", sp, {}],
		[15600, OrderKinds.WARD, "point", sp, {}],
		[15660, OrderKinds.WARD, "point", sp + Vector2i(120, -80), {}],
		[18000, OrderKinds.WAYPOINT, "point", mid, {"siege": 1}],
		[24000, OrderKinds.DRONE, "none", 0, {"node": ""}],
	]


## The orders of the late match (it starts at 25:00, everything unlocked and paid for).
func _late_list() -> Array:
	var spot := OrderCheckRefusals.open_spot(world)
	var enemy := world.mothership(Rules.enemy_of(world.human_team)).global_position
	return [
		[60, OrderKinds.MOTHERSHIP_MOVE, "point", Order.point(Vector2(MapLayout.CX, MapLayout.CY - 1400.0)), {}],
		[300, OrderKinds.PRODUCE, "none", 0, {"hull": "destroyer", "count": 1, "rally": "mothership"}],
		[600, OrderKinds.WARD, "point", Order.point(spot), {}],
		[900, OrderKinds.BAY, "point", Order.point(spot) + Vector2i(60, 60), {}],
		[1200, OrderKinds.HOLD_ITEM, "item", "@ship", {"hold": 1}],
		[1500, OrderKinds.HOLD_ITEM, "item", "@ship", {"hold": 0}],
		[2100, OrderKinds.PRODUCE, "none", 0, {"hull": "fighter", "count": 3, "rally": "lane"}],
		[2700, OrderKinds.CANCEL, "item", "@ship", {}],
		[3000, OrderKinds.WAYPOINT, "point", Order.point(enemy + Vector2(-2500.0, 0.0)), {"siege": 1}],
		[9000, OrderKinds.DRONE, "none", 0, {"node": ""}],
		[12000, OrderKinds.MOTHERSHIP_MOVE, "point", Order.point(world.map.mothership_pos[world.human_team]), {}],
	]


## Godot calls this every tick, after the World: give the orders whose tick has come.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	while _given < _list.size() and world.tick_count >= int((_list[_given] as Array)[0]):
		var row: Array = _list[_given]
		_given += 1
		var target = row[3]
		if str(target) == "@ship":
			target = _first_ship_item()
		var o := Order.make(str(row[1]), world.human_team, Rules.ADMIRAL_SEAT, true, row[4], [], str(row[2]), target)
		if world.orders.submit(o) == "":
			_accepted += 1


## The id of the first ship item in the human team's build list ("@ship" in the lists above stands for
## it, for the orders that name an item), or "" when the list has none.
func _first_ship_item() -> String:
	for it: Dictionary in world.teams[world.human_team].production.items:
		if it["kind"] == Production.SHIP:
			return str(it["id"])
	return ""


## The match is over (the hash test quit): print the verdict.
func _exit_tree() -> void:
	if world == null:
		return
	world.orders.flush()
	var q := world.orders
	if bool(Game.opt("script", false)):
		_check_log(q)
	if q.replay != null:
		var r := q.replay
		_check("the replay compared fingerprint lines (%d)" % r.compared, r.compared > 0)
		_check("the replay's header agreed with the match", r.header_ok)
		_check("no fingerprint line differed (%d differ)" % r.mismatches, r.mismatches == 0)
		_check("every order of the log was played (%d left over)" % r.left_over(), r.left_over() == 0)
	print("order_replay: %d failures" % fails)


## Count a failure and print a PASS or FAIL line.
func _check(what: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


## The scripted run's own log: every accepted order is in it, marked h; it has the header,
## fingerprint lines and the end line.
func _check_log(q: OrderQueue) -> void:
	_check("the script gave %d of its %d orders and the queue accepted %d" % [_given, _list.size(), _accepted], _given > 0 and _accepted > 0)
	if q.log == null:
		_check("the match log is open (use --order-log)", false)
		return
	var read := OrderLog.read(q.log.path)
	var human_lines := 0
	for o: Dictionary in read["orders"]:
		if Order.marker(o) == "h":
			human_lines += 1
	_check("every accepted order is in the log, marked h, or still waiting (%d lines + %d waiting)" % [human_lines, q.queue.size()], human_lines + q.queue.size() == _accepted)
	_check("the log has its header", str(read["header"]).begins_with("log v1 seed="))
	_check("the log has fingerprint lines (%d)" % (read["hashes"] as Dictionary).size(), (read["hashes"] as Dictionary).size() > 0)
	_check("the log has its end line", str(read["end"]) != "")
