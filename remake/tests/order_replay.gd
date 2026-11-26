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
## remake/; the driver in the lead's tools runs the whole sequence). Two runs at the same time must not share a log file:
## give each pair its own file name (the same <file> in a pair's run 1 and run 2, another one for every other pair):
##   run 1: godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --seed=7 --secs=600 --script --order-log=<file> --test=order_replay
##   run 2: godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --seed=7 --secs=600 --replay=<file> --test=order_replay
##   computer: godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --secs=600 --order-log=<file> --test=order_replay
##             godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --secs=600 --admiral-replay=<file> --test=order_replay
## RT7: in the normal Admiral runs the human also flies a Fighter for a while (the coast step, COAST_AT): it is bought and launched by hangar
## commands in the --script run (the log's b lines, replayed in the other run), put 1,000 units from a rock, flown with W for a third of a second,
## then Mode 3 (World.view_open) opens at a fixed tick and the ship coasts (CoastController holds its controls; W has turned it, so it slides past the rock
## and the rock guard never has to brake), and it closes again after 1,000 ticks; S then backs away. The key presses of the --script run are recorded as c lines;
## the replay flies from them. Both runs check that the ship coasted with the view open and that nothing on its line was hit; the brake itself is
## tested in coast_check. The coast must repeat exactly in the replay.
## RT7 7b: the --script run also gives the Admiral's fleet wheel orders (a Move and a Stop for every squadron, through FieldOrders.give at WHEEL_MOVE_AT and
## WHEEL_STOP_AT, no HUD needed); they are logged like the other orders, so the replay plays them again.
## RT12 Position pick: the --script run also gives the Position pick (roam) for every squadron at POSITION_AT, through RtsSquadOrders (what a click on
## the Roam entry sends), and both runs read the squadrons' move stance at POSITION_SAMPLE_AT: the replay run proves the order round-trips through the log.
## (add --late and --secs=300 for the late-game runs; the computer Admiral's field trips are in the log
## as `f` lines and are replayed, so --no-admiral-field is not needed: F461)
##
## WHO USES IT: main.gd loads it for --test=order_replay; the replay gate script runs it.

## The ticks the fleet wheel's Move and Stop are given at (before the coast step; the 200-second rows have 12000 ticks).
const WHEEL_MOVE_AT := 8000
## The tick of the Stop (after the Move).
const WHEEL_STOP_AT := 9000
## The tick the Position pick (roam) is given at: after the wheel's Move and before its Stop (the 200-second rows have 12000 ticks).
const POSITION_AT := 8500
## The tick the squadrons' move stance is read at, 60 ticks after the pick (both runs).
const POSITION_SAMPLE_AT := 8560
## The first tick of the coast step (the match has to run at least to COAST_AT + 1160 ticks; the 200-second rows have 12000).
const COAST_AT := 10000
## How far from the rock the Fighter is put (world units), and its speed then.
const COAST_RUN := 1000.0
const COAST_SPEED := 150.0
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
## Does this run have the coast step (a human Admiral, the normal match, a --script or --replay run)?
var _coast := false
## The rock of the coast step (its place and radius), the direction of the run and its start; the Fighter once launched.
var _rock_pos := Vector2.ZERO
var _rock_rad := 0.0
var _run_dir := Vector2.RIGHT
var _run_start := Vector2.ZERO
var _fighter: Ship
## What the coast step saw: the smallest gap to the rock, how many ticks the ship touched anything, whether it had stopped when
## the view closed, whether the view was open at all, and whether the ship was placed.
var _min_gap := INF
var _touches := 0
var _stopped := false
## The ship's speed when the view closed (in this match the W press turns the Fighter, so it ends sliding sideways at about 19 units a second past the rock, 277 units off: the coast only brakes motion that is aimed at something solid, so it is judged slow, not stopped; coast_check's Fighter run judges it stopped).
var _end_speed := 0.0
var _view_ticks := 0
var _placed := false
## Were the Fighter bought and launched (the --script run only)?
var _bought := false
## How many orders the fleet wheel's step gave (the --script run only).
var _wheel_given := 0
## How many of them the queue accepted.
var _wheel_ok := 0
## Does this run have the Position step (a human Admiral, the normal match, a --script or --replay run)?
var _pos := false
## Was the Position pick given (1 once, the --script run only)?
var _pos_given := 0
## Did the order queue accept it (1 when it did)?
var _pos_ok := 0
## How many of the team's squadrons held the roam stance at POSITION_SAMPLE_AT (-1 before the reading).
var _roam_seen := -1


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	_det = load("res://tests/det_hash.gd").new()
	add_child(_det)
	_det.call("setup", w)
	if bool(Game.opt("script", false)):
		_list = _late_list() if bool(Game.opt("late", false)) else _normal_list()
	_coast = world.human != null and world.human_role == "admiral" and not bool(Game.opt("late", false)) and (bool(Game.opt("script", false)) or Game.opt("replay") != null)
	_pos = world.human != null and world.human_role == "admiral" and not bool(Game.opt("late", false)) and (bool(Game.opt("script", false)) or Game.opt("replay") != null)
	if _coast and not _find_run():
		_coast = false


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
	if _coast:
		_coast_tick()
	if bool(Game.opt("script", false)) and not bool(Game.opt("late", false)):
		_wheel_tick()
	if _pos:
		_position_tick()
	while _given < _list.size() and world.tick_count >= int((_list[_given] as Array)[0]):
		var row: Array = _list[_given]
		_given += 1
		var target = row[3]
		if str(target) == "@ship":
			target = _first_ship_item()
		var o := Order.make(str(row[1]), world.human_team, Rules.ADMIRAL_SEAT, true, row[4], [], str(row[2]), target)
		if world.orders.submit(o) == "":
			_accepted += 1


## The Position step, one tick. In the --script run only, at POSITION_AT: the Position pick (roam) for every squadron of the team,
## through RtsSquadOrders.set_position on an overlay that selects them (what a click on the Roam entry sends); a squadron's
## "move" setting is the only thing the order names. A pick that was accepted counts in _accepted, like the list's. In both runs, at
## POSITION_SAMPLE_AT, count the team's squadrons that hold the roam stance (a bought squadron starts at manoeuvre, so a roam can
## only come from the pick, which the replay plays from the log).
func _position_tick() -> void:
	var tick := world.tick_count
	if bool(Game.opt("script", false)) and _pos_given == 0 and tick >= POSITION_AT:
		_pos_given = 1
		var ids := FieldOrders.ids_for(null, world)
		var ov := CommandOverlay.new()
		ov.world = world
		ov.team = world.human_team
		ov.sel_squads = ids
		var rso: Variant = load("res://scripts/ui/rts/rts_squad_orders.gd")
		if not rso.get_script_method_list().filter(func(m: Dictionary) -> bool: return str(m["name"]) == "set_position").is_empty():
			var why: String = rso.set_position(ov, 2)
			if why == "":
				_pos_ok = 1
				_accepted += 1
		ov.free()
	if _roam_seen < 0 and tick >= POSITION_SAMPLE_AT:
		var n := 0
		for rec: Squad in RtsSelect.our_squads(world, world.human_team):
			if rec.move_stance == 2:
				n += 1
		_roam_seen = n


## The fleet wheel's step, one tick (the --script run only): at WHEEL_MOVE_AT a Move to the middle of the map and at WHEEL_STOP_AT a Stop,
## each for every squadron of the team, through FieldOrders.give (what a release over a slice of the wheel sends). Accepted orders count in
## _accepted, like the list's: the check that every accepted order is in the log covers them.
func _wheel_tick() -> void:
	var tick := world.tick_count
	var due := (_wheel_given == 0 and tick >= WHEEL_MOVE_AT) or (_wheel_given == 1 and tick >= WHEEL_STOP_AT)
	if not due:
		return
	var ids := FieldOrders.ids_for(null, world)
	var why := FieldOrders.give(world, "move" if _wheel_given == 0 else "stop", ids, Vector2(MapLayout.CX, MapLayout.CY - 1400.0))
	_wheel_given += 1
	if why == "":
		_wheel_ok += 1
		_accepted += 1


## The coast step, one tick (the same in the --script run and in the replay, except that only the --script run gives the
## commands and presses the keys: the replay plays them from the log). The ticks, from COAST_AT: +0 buy and launch a
## Fighter; +60 put it 1,000 units from the rock, heading at it; W for 20 ticks; +100 mode 3 opens (World.view_open):
## the ship coasts (it slides past the rock; the rock guard has nothing to brake); +1100 mode 3 closes; S for 60 ticks backs away.
func _coast_tick() -> void:
	var at := world.tick_count - COAST_AT
	var scripted := bool(Game.opt("script", false))
	if at == 0 and scripted and not _bought:
		_bought = true
		HumanCmd.run(world, "buy_hull", ["fighter"])
		HumanCmd.run(world, "launch")
	var h := world.human
	_fighter = h.ship if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive else null
	if _fighter == null:
		return
	if at == 60 and not _placed:
		_placed = true
		_fighter.global_position = _run_start
		_fighter.rotation = _run_dir.angle()
		_fighter.velocity = _run_dir * COAST_SPEED
		_fighter.ang_vel = 0.0
		_fighter.swivel = 0.0
		_fighter.brake_t = 0.0
		_fighter.throttle = 0.0
		_fighter.controls.face_point = _run_start + _run_dir * 600.0
	if scripted:
		if at == 60:
			Input.action_press("thrust_forward")
		elif at == 80:
			Input.action_release("thrust_forward")
		elif at == 1100:
			Input.action_press("thrust_back")
		elif at == 1160:
			Input.action_release("thrust_back")
	if at == 100:
		world.view_open = true
	elif at == 1100:
		_end_speed = _fighter.velocity.length()
		_stopped = _end_speed < COAST_SPEED * 0.25
		world.view_open = false
	if _placed and world.view_open:
		_view_ticks += 1
		_min_gap = minf(_min_gap, _fighter.global_position.distance_to(_rock_pos) - _rock_rad - _fighter.radius)
		if _fighter.get_slide_collision_count() > 0:
			_touches += 1


## Find a rock (not an ore rock, not a huge one) that a straight run from COAST_RUN units away reaches first, with no other
## rock near the line and none behind the start, for the coast step. Sets _rock_pos, _rock_rad, _run_dir and _run_start.
## False when the map has none (the step is then left out of both runs alike).
func _find_run() -> bool:
	var f := world.asteroids
	var pad := float(Ships.get_def("fighter")["radius"]) + CoastController.LINE_PAD
	for i in f.pos.size():
		if f.alive[i] == 0 or f.node_rock[i] == 1 or f.rad[i] < 40.0 or f.rad[i] > 250.0:
			continue
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var s: Vector2 = f.pos[i] - d * COAST_RUN
			if s.x < 1000.0 or s.x > MapLayout.W - 1000.0 or s.y < 1000.0 or s.y > MapLayout.H - 1000.0:
				continue
			var hit := f.segment_hit(s, f.pos[i], pad)
			if hit.is_empty() or int(hit["index"]) != i:
				continue
			if not f.segment_hit(s, f.pos[i] - d * (f.rad[i] + 500.0), 300.0).is_empty():
				continue
			if not f.segment_hit(s - d * 700.0, s, 200.0).is_empty():
				continue
			_rock_pos = f.pos[i]
			_rock_rad = f.rad[i]
			_run_dir = d
			_run_start = s
			return true
	return false

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
	if q.log != null and q.replay == null and not bool(Game.opt("script", false)):
		_check_fleet_log(q)
	# A replay that was asked for but could not start (the log file is missing or unreadable) leaves q.replay empty; without this
	# check an all-computer row would end with no failure having replayed nothing.
	if Game.opt("replay") is String or Game.opt("admiral-replay") is String:
		_check("the replay started (the log could be read)", q.replay != null)
	if q.replay != null:
		var r := q.replay
		# The replay itself only prints a warning for a log made by another build, which is easy to miss in a gate; a log
		# overwritten by another run's build shows up here. A build that is not known on either side cannot be judged and passes.
		var logged_build := str((r.data["head"] as Dictionary).get("build", ""))
		var live_build := BuildId.get_id()
		var builds_known := logged_build != "" and logged_build != BuildId.UNKNOWN and live_build != BuildId.UNKNOWN
		_check("the log was written by build %s, this run is build %s" % [logged_build, live_build], not builds_known or logged_build == live_build)
		_check("the replay compared fingerprint lines (%d)" % r.compared, r.compared > 0)
		_check("the replay's header agreed with the match", r.header_ok)
		_check("no fingerprint line differed (%d differ)" % r.mismatches, r.mismatches == 0)
		_check("every order of the log was played (%d left over)" % r.left_over(), r.left_over() == 0)
	if _coast:
		_check_coast()
	if _pos:
		_check("a squadron holds the roam stance 60 ticks after the pick (%d)" % _roam_seen, _roam_seen >= 1)
	print("order_replay: %d failures" % fails)


## Count a failure and print a PASS or FAIL line.
func _check(what: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


## The coast step's own verdict (both runs): the Fighter was launched and put by the rock, mode 3 was open for the coast
## (about 1000 ticks), the ship was coasting slowly when the view closed (under a quarter of its start speed) and nothing on its line was hit.
## It does not test the rock guard's brake: the controls are zero while the view is open, so the guard never has to act (coast_check tests it).
func _check_coast() -> void:
	_check("the coast step: the Fighter was launched and put by the rock", _placed)
	_check("the coast step: mode 3 was open for %d ticks" % _view_ticks, _view_ticks >= 900)
	_check("the coast step: the ship coasted at under a quarter of its start speed when the view closed (speed %.1f)" % _end_speed, _stopped)
	_check("the coast step: nothing on its line was hit while the view was open (closest gap to the rock %.0f, %d touches)" % [_min_gap, _touches], _min_gap > 0.0 and _touches == 0)

## An all-computer --order-log run whose Admiral has the fleet play on (RT8 build 8c): its log must hold at least one delayed fleet
## order, a computer line with the d word (the decision tick), or the replay of it proves nothing about the delay, and (build 8d) at
## least one goal lane line (the f line "goal"), or the replay of it proves nothing about the goal lane. A run with the
## fleet play off is not judged here (no order is delayed, no d word is written).
func _check_fleet_log(q: OrderQueue) -> void:
	var ai := world.admiral_ai[0] as AdmiralAI
	if ai == null or ai.fleet == null:
		return
	var read := OrderLog.read(q.log.path)
	var n := 0
	for o: Dictionary in read["orders"]:
		if o.has("decided"):
			n += 1
	_check("the log of a fleet-play match has delayed orders with a d word (%d)" % n, n > 0)
	var goals := 0
	for f: Dictionary in read["field"]:
		if str(f["op"]) == "goal":
			goals += 1
	_check("the log of a fleet-play match has goal lane lines, the f line goal (%d)" % goals, goals > 0)


## The scripted run's own log: every accepted order is in it, marked h; it has the header,
## fingerprint lines and the end line.
func _check_log(q: OrderQueue) -> void:
	_check("the script gave %d of its %d orders and the queue accepted %d" % [_given, _list.size(), _accepted], _given > 0 and _accepted > 0)
	_check("the fleet wheel's Move and Stop were given through FieldOrders and accepted (%d of %d)" % [_wheel_ok, _wheel_given], _wheel_given == 2 and _wheel_ok == 2)
	_check("the Position pick (roam) was given through RtsSquadOrders for every squadron and accepted (%d of %d)" % [_pos_ok, _pos_given], _pos_given == 1 and _pos_ok == 1)
	if q.log == null:
		_check("the match log is open (use --order-log)", false)
		return
	var read := OrderLog.read(q.log.path)
	var human_lines := 0
	for o: Dictionary in read["orders"]:
		if Order.marker(o) == "h":
			human_lines += 1
	_check("every accepted order is in the log, marked h, or still waiting (%d lines + %d waiting)" % [human_lines, q.queue.size()], human_lines + q.queue.size() == _accepted)
	_check("the log has its header", str(read["header"]).begins_with("log v2 seed="))
	_check("the log has fingerprint lines (%d)" % (read["hashes"] as Dictionary).size(), (read["hashes"] as Dictionary).size() > 0)
	_check("the log has its end line", str(read["end"]) != "")
