class_name OrderCheckRefusals
extends RefCounted
## WHAT THIS IS: the checks of tests/order_check.gd that look at refusals, the game
## speed order, the event stream, the ship-lost record and the unit-id lookup. They
## run inside a match (the test passes itself in) and set up the state each needs.
##
## HOW IT WORKS: static functions; each takes the checking test `t`, which has the
## match as `t.world` and `check(what, ok, detail)`. They submit order records to
## World.orders between ticks, so none of them needs a tick to pass, and they put
## back what they change (the treasury, the queues, the speed).
##
## WHO USES IT: tests/order_check.gd.

## A pilot record flagged as a crew ship's (is_crew is true), not a pilot's.
class CrewProfile extends PilotProfile:
	## A crew record for team 0, slot 200.
	func _init() -> void:
		super("Crew W1", 0, 200, false)
		is_crew = true


## A record from seat `seat` for team 0.
static func rec(kind: String, seat: int = 5, human: bool = true, settings: Dictionary = {}, subjects: Array = [], target_kind: String = "none", target = null) -> Dictionary:
	return Order.make(kind, 0, seat, human, settings, subjects, target_kind, target)


## A spot near our mothership where a ward and a repair bay can go (both blockers say
## yes once the repair bay research flag is on), or Vector2.INF if none was found.
static func open_spot(w: World) -> Vector2:
	var home := w.mothership(0).global_position
	for r in [500.0, 800.0, 1100.0, 1400.0]:
		for k in 12:
			var p := home + Vector2.from_angle(float(k) * TAU / 12.0) * float(r)
			if w.command.ward_blocker(0, p) == "" and w.command.bay_blocker(0, p) in ["", "Needs Repair Bays research"]:
				return p
	return Vector2.INF


## Submit `o` and check the refusal maps to `code` ("ok" for accepted).
static func expect(t, label: String, o: Dictionary, code: String) -> void:
	var msg: String = t.world.orders.submit(o)
	t.check("(d) %s: %s" % [label, code], OrderKinds.reason_code(msg) == code, "got '%s'" % msg)
	# An accepted order would be carried out later; this table only asks.
	if msg == "":
		t.world.orders.queue.erase(o)


## Check (d): every group of refusals comes back at once with the right code.
static func table(t) -> void:
	var w: World = t.world
	var ts := w.teams[0]
	var q := w.orders
	var spot := open_spot(w)
	var free_node: ResourceNode = null
	var lane_node: ResourceNode = null
	var enemy_node: ResourceNode = null
	for n in w.nodes:
		if free_node == null and n.free_slot() >= 0 and n.build_blocker(0, "pd") == "":
			free_node = n
		if lane_node == null and MapLayout.is_lane_site_kind(n.node_kind) and n.side == 0:
			lane_node = n
		if enemy_node == null and MapLayout.is_lane_site_kind(n.node_kind) and n.side == 1:
			enemy_node = n
	t.check("(d) the test found its spot and nodes", spot != Vector2.INF and free_node != null and lane_node != null and enemy_node != null)
	var spot_i := Order.point(spot)
	var saved_money := ts.treasury
	# ATTACK has a handler only for this table (a stage that builds it registers its own).
	q.handlers[OrderKinds.ATTACK] = func(_o: Dictionary) -> String: return ""
	q.handlers[OrderKinds.SET_STANCE] = func(_o: Dictionary) -> String: return ""
	# money
	ts.treasury = 0.0
	# A drone, a module and a research are not refused for money: they wait in the build
	# list and pay when they start.
	expect(t, "DRONE with no money waits in the list", rec(OrderKinds.DRONE, 5, true, {"node": ""}), "ok")
	expect(t, "MODULE with no money waits in the list", rec(OrderKinds.MODULE, 5, true, {}, [], "id", "research"), "ok")
	expect(t, "TURRET with no money", rec(OrderKinds.TURRET, 5, true, {"ttype": "pd"}, [], "node", free_node.node_id), "money")
	ts.repair_bays = true
	expect(t, "BAY with no money", rec(OrderKinds.BAY, 5, true, {}, [], "point", spot_i), "money")
	expect(t, "WARD with no money", rec(OrderKinds.WARD, 5, true, {}, [], "point", spot_i), "money")
	ts.repair_bays = false

	ts.treasury = 5000.0
	# room
	var drones := ts.drone_queue.duplicate()
	for i in 6:
		ts.drone_queue.append("")
	expect(t, "DRONE with a full build queue", rec(OrderKinds.DRONE, 5, true, {"node": ""}), "room")
	ts.drone_queue = drones
	var building := ts.building.duplicate()
	ts.building = [{"id": "x1", "left": 1.0, "total": 1.0}, {"id": "x2", "left": 1.0, "total": 1.0}]
	expect(t, "MODULE with a full build queue", rec(OrderKinds.MODULE, 5, true, {}, [], "id", "research"), "room")
	ts.building = building
	expect(t, "TURRET at a site with no free slot", rec(OrderKinds.TURRET, 5, true, {"ttype": "pd"}, [], "node", lane_node.node_id), "room")
	# unlock
	expect(t, "BAY without the research", rec(OrderKinds.BAY, 5, true, {}, [], "point", spot_i), "unlock")
	expect(t, "TURRET torp without the research", rec(OrderKinds.TURRET, 5, true, {"ttype": "torp"}, [], "node", free_node.node_id), "unlock")

	expect(t, "RESEARCH without the Research Module", rec(OrderKinds.RESEARCH, 5, true, {}, [], "id", "repairBays"), "unlock")
	# place
	var far := Order.point(w.mothership(1).global_position)
	expect(t, "WARD where the team cannot see", rec(OrderKinds.WARD, 5, true, {}, [], "point", far), "place")
	expect(t, "TURRET at no node", rec(OrderKinds.TURRET, 5, true, {"ttype": "pd"}, [], "node", "zz"), "place")
	expect(t, "TURRET at the enemy's site", rec(OrderKinds.TURRET, 5, true, {"ttype": "pd"}, [], "node", enemy_node.node_id), "place")
	# time
	expect(t, "POST that stands", rec(OrderKinds.POST, 5, true, {}, [], "lane", "top"), "time")
	expect(t, "MOTHERSHIP_MOVE before the engines", rec(OrderKinds.MOTHERSHIP_MOVE, 5, true, {}, [], "point", spot_i), "time")
	# gone

	expect(t, "ATTACK at a unit that is gone", rec(OrderKinds.ATTACK, -2, false, {}, [], "unit", 987654), "gone")
	expect(t, "ATTACK for a squadron that is gone", rec(OrderKinds.ATTACK, -2, false, {}, [4242], "unit", 1), "gone")
	# online (two human seats), seat, value, unbuilt, unknown
	q.human_seats_override = 2
	expect(t, "GAME_SPEED with two human seats", rec(OrderKinds.GAME_SPEED, 5, true, {"hundredths": 200}), "online")
	q.human_seats_override = -1
	expect(t, "DRONE from a pilot's seat", rec(OrderKinds.DRONE, 3, true, {"node": ""}), "seat")
	expect(t, "WAYPOINT from the deputy", rec(OrderKinds.WAYPOINT, -1, false, {"siege": 0}, [], "point", spot_i), "seat")
	expect(t, "SIEGE from a pilot", rec(OrderKinds.SIEGE, 2, false, {"phase": ""}), "seat")
	expect(t, "BAY with a lane target", rec(OrderKinds.BAY, 5, true, {}, [], "lane", "mid"), "value")
	expect(t, "TURRET of a type that does not exist", rec(OrderKinds.TURRET, 5, true, {"ttype": "x"}, [], "node", "n1"), "value")
	expect(t, "GAME_SPEED of 137", rec(OrderKinds.GAME_SPEED, -2, false, {"hundredths": 137}), "value")
	expect(t, "a DRONE with a stray setting", rec(OrderKinds.DRONE, 5, true, {"node": "", "x": 1}), "value")
	expect(t, "a DRONE missing its setting", rec(OrderKinds.DRONE, 5, true, {}), "value")
	expect(t, "a point that is a string", rec(OrderKinds.BAY, 5, true, {}, [], "point", "x"), "value")
	expect(t, "SET_STANCE with no key", rec(OrderKinds.SET_STANCE, -2, false, {}), "value")
	expect(t, "PAUSE", rec(OrderKinds.PAUSE, 5, true), "unbuilt")
	expect(t, "STOP with no handler", rec(OrderKinds.STOP, -2, false), "unbuilt")
	var appended := rec(OrderKinds.DRONE, 5, true, {"node": ""})
	appended["mode"] = "append"
	expect(t, "DRONE in mode append", appended, "unbuilt")
	expect(t, "an order that does not exist", rec("NOPE", 5, true), "unknown")
	# A late order is refused when it is carried out.
	var late := rec(OrderKinds.DRONE, 5, true, {"node": ""})
	late["id"] = q.take_id()
	late["tick"] = w.tick_count - 2
	late["apply_tick"] = w.tick_count - 1
	t.check("(d) an order that is late is refused: late", w.tick_count >= 2 and OrderKinds.reason_code(q.apply(late)) == "late")
	q.handlers.erase(OrderKinds.ATTACK)
	q.handlers.erase(OrderKinds.SET_STANCE)
	ts.treasury = saved_money


## Check (r): a checker refuses at submit (nothing logged), a handler that answers
## "Same order again" is logged with the code duplicate and files that reason.
static func hooks(t) -> void:
	var w: World = t.world
	var q := w.orders
	var counts_before := q.counters()
	q.handlers[OrderKinds.HOLD] = func(_o: Dictionary) -> String: return ""
	q.checkers[OrderKinds.HOLD] = func(_o: Dictionary) -> String: return "Too far for the wing"
	var o := rec(OrderKinds.HOLD, -2, false, {}, [], "point", Vector2i(5, 5))
	var msg := q.submit(o)
	q.checkers.erase(OrderKinds.HOLD)
	q.handlers.erase(OrderKinds.HOLD)
	t.check("(r) a checker refuses at submit", msg == "Too far for the wing" and int(o["id"]) == 0 and q.queue.is_empty(), msg)
	var dup_cursor := w.events_rts.next_index(0)
	q.handlers[OrderKinds.PATROL] = func(_o: Dictionary) -> String: return OrderKinds.TEXT_DUPLICATE
	var d := rec(OrderKinds.PATROL, 5, false, {}, [], "point", Vector2i(2, 2))
	d["id"] = q.take_id()
	d["tick"] = w.tick_count
	d["apply_tick"] = w.tick_count
	var dmsg := q.apply(d)
	q.handlers.erase(OrderKinds.PATROL)
	var evs := w.events_rts.read_from(0, dup_cursor)
	var reason := ""
	for e: Dictionary in evs:
		if e["kind"] == "order_refused":
			reason = str((e["data"] as Dictionary).get("reason", ""))
	t.check("(r) a duplicate is refused when carried out and files the reason duplicate", OrderKinds.reason_code(dmsg) == "duplicate" and reason == "duplicate", "%s / %s" % [dmsg, reason])
	var unbuilt := rec(OrderKinds.ATTACK_MOVE, -2, false, {}, [], "point", Vector2i(1, 1))
	t.check("(r) a kind with no handler is unbuilt", OrderKinds.reason_code(q.submit(unbuilt)) == "unbuilt")
	var after := q.counters()
	var t0: Dictionary = after.get("t0", {})
	t.check("(h) the counters count what was submitted and refused", int((t0.get("HOLD", {}) as Dictionary).get("submitted", 0)) >= 1 and int(((t0.get("HOLD", {}) as Dictionary).get("refused", {}) as Dictionary).get("place", 0)) >= 1 and counts_before != after)


## Check (k): the game speed order.
static func speed(t) -> void:
	var w: World = t.world
	var q := w.orders
	var base_ticks := Engine.physics_ticks_per_second
	var base_scale := Engine.time_scale
	var cursor := w.events_rts.next_index(0)
	var g := rec(OrderKinds.GAME_SPEED, -2, false, {"hundredths": 200})
	t.check("(k) GAME_SPEED 200 is accepted and applied at once", q.submit(g) == "" and int(g["apply_tick"]) == w.tick_count and w.speed.factor == 2.0)
	t.check("(k) 200 sets 120 ticks a second and a time scale of 2", Engine.physics_ticks_per_second == 120 and Engine.time_scale == 2.0, "%d, %s" % [Engine.physics_ticks_per_second, str(Engine.time_scale)])
	t.check("(k) the speed order is never queued", q.queue.is_empty())
	t.check("(k) 50 sets the factor 0.5 and leaves the engine's numbers", q.submit(rec(OrderKinds.GAME_SPEED, -2, false, {"hundredths": 50})) == "" and w.speed.factor == 0.5 and Engine.physics_ticks_per_second == base_ticks and Engine.time_scale == base_scale)
	t.check("(k) 137 is refused: value", OrderKinds.reason_code(q.submit(rec(OrderKinds.GAME_SPEED, -2, false, {"hundredths": 137}))) == "value" and w.speed.factor == 0.5)
	var wants_150 := WorldSpeed.FAST_STEPS.has(1.5)
	var m150 := q.submit(rec(OrderKinds.GAME_SPEED, -2, false, {"hundredths": 150}))
	t.check("(k) 150 is %s" % ("accepted: 1.5x ships" if wants_150 else "refused: value (1.5x does not ship)"), (m150 == "" and w.speed.factor == 1.5 and Engine.physics_ticks_per_second == 90) if wants_150 else (OrderKinds.reason_code(m150) == "value"), m150)
	t.check("(k) 100 puts everything back", q.submit(rec(OrderKinds.GAME_SPEED, -2, false, {"hundredths": 100})) == "" and w.speed.factor == 1.0 and Engine.physics_ticks_per_second == base_ticks and Engine.time_scale == base_scale)
	var kinds := PackedStringArray()
	for e: Dictionary in w.events_rts.read_from(0, cursor):
		kinds.append("%s:%s" % [e["kind"], str((e["data"] as Dictionary).get("hundredths", ""))])
	t.check("(k) a game_speed event is filed for each change", kinds.count("game_speed:200") == 1 and kinds.count("game_speed:50") == 1 and kinds.count("game_speed:100") == 1, ",".join(kinds))


## Check (j): the event stream.
static func stream(t) -> void:
	var w: World = t.world
	var ev := w.events_rts
	var c0 := ev.next_index(0)
	Events.research_done.emit(0, "testtech")
	Events.facility_done.emit(0, "testmodule")
	var got := ev.read_from(0, c0)
	t.check("(j) research_done and facility_done become events with tick, team and id", got.size() == 2 and got[0]["kind"] == "research_done" and int(got[0]["tick"]) == w.tick_count and int(got[0]["team"]) == 0 and (got[0]["data"] as Dictionary)["id"] == "testtech" and got[1]["kind"] == "module_done")
	var other := ev.next_index(1)
	t.check("(j) the other team's ring did not see them", ev.read_from(1, other).is_empty())
	var both0 := ev.next_index(0)
	var both1 := ev.next_index(1)
	ev.push({"kind": "test_both", "team": -1})
	t.check("(j) a record for team -1 goes to both rings", ev.next_index(0) == both0 + 1 and ev.next_index(1) == both1 + 1)
	var a := ev.next_index(0)
	for i in 3:
		ev.push({"kind": "test_a", "team": 0})
	var b := ev.next_index(0)
	for i in 2:
		ev.push({"kind": "test_b", "team": 0})
	t.check("(j) two cursors read independently", ev.read_from(0, a).size() == 5 and ev.read_from(0, b).size() == 2)
	var start := ev.next_index(0)
	for i in 600:
		ev.push({"kind": "test_ring", "team": 0, "data": {"n": i}})
	var kept := ev.read_from(0, start)
	t.check("(j) the ring keeps the newest 512 and drops the oldest", kept.size() == RtsEvents.RING and int((kept[0]["data"] as Dictionary)["n"]) == 600 - RtsEvents.RING and ev.next_index(0) == start + 600, str(kept.size()))
	var seen := []
	var listener := func(e: Dictionary) -> void: seen.append(e["kind"])
	Events.rts_event.connect(listener)
	ev.push({"kind": "test_signal", "team": 0})
	Events.rts_event.disconnect(listener)
	t.check("(j) every record is sent on Events.rts_event", seen == ["test_signal"])
	# The defend call turning on files a mothership_under_attack record once.
	var c := ev.next_index(0)
	var ts := w.teams[0]
	var saved_point = ts.defend_point
	var saved_until = ts.defend_until
	ts.defend_point = w.mothership(0).global_position
	ts.defend_until = w.time + 5.0
	ev.tick()
	ev.tick()
	ts.defend_point = saved_point
	ts.defend_until = saved_until
	ev.tick()
	var attack := 0
	for e: Dictionary in ev.read_from(0, c):
		if e["kind"] == "mothership_under_attack":
			attack += 1
	t.check("(j) the mothership under attack is filed once, on the edge", attack == 1, str(attack))


## Check (s): a pilot's death files one ship_lost, a crew ship's none.
static func ship_lost(t) -> void:
	var w: World = t.world
	var ev := w.events_rts
	var pilot := Ship.new()
	var crew := Ship.new()
	w.add_child(pilot)
	w.add_child(crew)
	pilot.team = 0
	crew.team = 0
	pilot.profile = PilotProfile.new("Test", 0, 0, false)
	crew.profile = CrewProfile.new()
	var c := ev.next_index(0)
	Events.unit_killed.emit(crew, null)
	var after_crew := ev.read_from(0, c).size()
	Events.unit_killed.emit(pilot, null)
	var lost := 0
	for e: Dictionary in ev.read_from(0, c):
		if e["kind"] == "ship_lost":
			lost += 1
	t.check("(s) a crew ship's death files nothing, a pilot's exactly one ship_lost", after_crew == 0 and lost == 1, "%d, %d" % [after_crew, lost])
	pilot.free()
	crew.free()


## Check (t): a unit is in by_uid from index() to remove(), and nothing loops over it.
static func by_uid(t) -> void:
	var w: World = t.world
	var d := w.spawn_mining_drone(0, "")
	var uid := d.uid
	t.check("(t) a new unit is found by its id", w.by_uid.get(uid) == d and w.orders.unit_by_uid(uid) == d)
	w.registry.remove(d)
	t.check("(t) after remove a lookup is null", w.by_uid.get(uid) == null and w.orders.unit_by_uid(uid) == null)
	var loops := PackedStringArray()
	_scan("res://scripts", loops)
	t.check("(t) no script loops over by_uid", loops.is_empty(), "; ".join(loops))


## Add to `found` each line under folder `dir` that loops over or lists World.by_uid.
static func _scan(dir: String, found: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + sub, found)
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(dir + "/" + f)
		for line in text.split("\n"):
			var s := line.strip_edges()
			if s.begins_with("#") or not s.contains("by_uid"):
				continue
			if s.contains(".keys()") or s.contains(".values()") or s.contains("in world.by_uid") or s.contains("in w.by_uid") or s.contains("in by_uid"):
				found.append("%s/%s: %s" % [dir.trim_prefix("res://"), f, s.left(60)])
