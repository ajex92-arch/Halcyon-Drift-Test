extends Node
## WHAT THIS IS: the check of the admiral sending a mining drone to a chosen ore node. A drone that is sent keeps
## its new node (`assign` and `node_id`) at once, whatever mood it is in, keeps the ore it carries, tops up at the
## new node and delivers on its next trip home, and goes back to the same node afterwards. It also holds the order
## DRONE_SEND (its refusals) and the words that say how much ore a drone carries.
##
## HOW IT WORKS: setup() waits for the drones each team starts with, picks two ore nodes the team may mine (neither
## is what the automatic choice would pick now, so a drone that forgot its order would go elsewhere), and walks the
## cases one after the other, setting a drone's position and cargo the way other checks do (a test spawns no drone:
## spawning draws a random number). It prints a FAIL line for every case that does not hold, each starting with its
## case letter, then "drone_send_check: N failures (M checks)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=drone_send_check
##
## WHO USES IT: main.gd loads it for --test=drone_send_check (it calls setup()); the lead's run_checks list.

## The match.
var world: World
## How many checks ran.
var checks := 0
## How many of them failed.
var fails := 0
## A living drone of team 0 (the one the node cases use).
var drone_a: MiningDrone
## Another living drone of team 0 (the order cases use it).
var drone_b: MiningDrone
## A living drone of team 1 (the other team's drone).
var drone_t1: MiningDrone
## The first node chosen for the cases.
var node_1: ResourceNode
## The second node chosen for the cases.
var node_2: ResourceNode


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


## Count one check; print a FAIL line (starting with the case letter in `what`) when it does not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Wait `n` physics frames (one match tick each).
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait until `cond` is true, at most `max_ticks` ticks; true when it became true.
func _until(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if bool(cond.call()):
			return true
		await _tick()
	return bool(cond.call())


## The living drones of `team`, in their stored order.
func _drones_of(team: int) -> Array[MiningDrone]:
	var out: Array[MiningDrone] = []
	for d in world.mining_drones:
		if d.team == team and d.alive:
			out.append(d)
	return out


## May `team` mine at node `n` (it has ore rocks and is not the other team's own jungle node, as WorldMining decides)?
func _mineable(n: ResourceNode, team: int) -> bool:
	return n.ore.size() > 0 and not (MapLayout.is_team_kind(n.node_kind) and n.side != team)


## Choose the two nodes: each one mineable for team 0, not the automatic choice of drone `d`, and the second is also
## not the first and not where `d` is going now. Returns true when both were found.
func _choose_nodes(d: MiningDrone) -> bool:
	var best := world.best_node_for_drone(0, d.global_position)
	var started_at := d.node_id
	node_1 = null
	node_2 = null
	for n in world.nodes:
		if not _mineable(n, 0) or n.node_id == best:
			continue
		if node_1 == null:
			node_1 = n
		elif node_2 == null and n.node_id != started_at:
			node_2 = n
	return node_1 != null and node_2 != null


## Put drone `d` at the drop-off point beside its mothership, where a drone in the "home" mood hands its ore over.
func _at_home(d: MiningDrone) -> void:
	d.position = world.drop_off_point(d.team, d.position)


## The cases of item 1: a drone that is sent keeps its node and its ore.
func _node_cases() -> void:
	var d := drone_a
	# (a) a drone with an empty hold, sent: the node is its own at once and it heads out.
	d.cargo = 0.0
	d.send_to(node_1.node_id)
	_check("(a) a sent drone's assign is the chosen node at once", d.assign == node_1.node_id, "assign=%s want %s" % [d.assign, node_1.node_id])
	_check("(a) a sent drone's node_id is the chosen node at once", d.node_id == node_1.node_id, "node_id=%s want %s" % [d.node_id, node_1.node_id])
	_check("(a) a sent drone is out at once", d.state == "out", "state=%s" % d.state)
	# (b) a drone with ore that was turned for home, sent elsewhere: it goes straight there and keeps the ore.
	d.cargo = 50.0
	d._go_home()
	_check("(b) setup: the drone is on its way home", d.state == "home", "state=%s" % d.state)
	d.send_to(node_2.node_id)
	_check("(b) a sent drone on its way home takes the new assign at once", d.assign == node_2.node_id, "assign=%s want %s" % [d.assign, node_2.node_id])
	_check("(b) a sent drone on its way home takes the new node_id at once", d.node_id == node_2.node_id, "node_id=%s want %s" % [d.node_id, node_2.node_id])
	_check("(b) a sent drone on its way home goes out, it does not go home first", d.state == "out", "state=%s" % d.state)
	_check("(b) a sent drone keeps its ore", is_equal_approx(d.cargo, 50.0), "cargo=%f" % d.cargo)
	# (c) it tops up at the new node, delivers on its next trip home and keeps the new node.
	var rk := node_2.best_rock(d.position)
	if rk < 0:
		_check("(c) the second node has a rock to mine", false, "node %s is dry" % node_2.node_id)
		return
	d.position = node_2.ore_pos[rk]
	var mining := await _until(func() -> bool: return d.state == "mine" and d.cargo > 51.0, 60)
	_check("(c) the drone tops up at the new node (state mine, cargo above 51)", mining, "state=%s cargo=%f" % [d.state, d.cargo])
	_check("(c) the ore it carried is not lost while it tops up", d.cargo > 0.0, "cargo=%f" % d.cargo)
	d.cargo = d.capacity - 0.5
	var full := await _until(func() -> bool: return d.state == "home", 30)
	_check("(c) a full hold sends the drone home", full, "state=%s" % d.state)
	_at_home(d)
	var delivered := await _until(func() -> bool: return d.cargo == 0.0, 30)
	_check("(c) the ore is delivered at home", delivered, "cargo=%f state=%s" % [d.cargo, d.state])
	_check("(c) after the first delivery the drone keeps the new node", d.node_id == node_2.node_id and d.assign == node_2.node_id, "node_id=%s assign=%s want %s" % [d.node_id, d.assign, node_2.node_id])
	# The second delivery: it is out again after the first, so turn it for home once more.
	d.cargo = 50.0
	d._go_home()
	_at_home(d)
	delivered = await _until(func() -> bool: return d.cargo == 0.0, 30)
	_check("(c) the second delivery happens", delivered, "cargo=%f state=%s" % [d.cargo, d.state])
	_check("(c) after the second delivery the drone still keeps the new node", d.node_id == node_2.node_id and d.assign == node_2.node_id, "node_id=%s assign=%s want %s" % [d.node_id, d.assign, node_2.node_id])


## Submit a DRONE_SEND order of team `team` for unit `uid` to node id `node`, as a test script (any seat may send); returns the
## order queue's answer ("" for accepted, else the refusal text).
func _submit(team: int, uid: int, node: String) -> String:
	return world.orders.submit(Order.make(OrderKinds.DRONE_SEND, team, OrderKinds.TEST_SEAT, false, {"node": node}, [], "unit", uid))


## The cases of item 2: the order DRONE_SEND carries a drone to a node, and its refusals have the right texts and codes.
func _order_cases() -> void:
	# (d) an own drone with ore, sent through the order queue: the node is its own and the ore is kept.
	var d := drone_b
	var target := node_1 if d.node_id != node_1.node_id else node_2
	if d.state == "home":
		d._go_out()
	d.cargo = 50.0
	var answer := _submit(0, d.uid, target.node_id)
	_check("(d) the order is accepted", answer == "", answer)
	var moved := await _until(func() -> bool: return d.node_id == target.node_id, 60)
	_check("(d) the drone's node_id is the ordered node (within 60 ticks)", moved, "node_id=%s want %s" % [d.node_id, target.node_id])
	_check("(d) the drone's assign is the ordered node", d.assign == target.node_id, "assign=%s want %s" % [d.assign, target.node_id])
	_check("(d) the drone keeps its ore", d.cargo >= 50.0, "cargo=%f" % d.cargo)
	# (e) a drone of the other team: refused "value", and it keeps its own node choice.
	var before := drone_t1.assign
	answer = _submit(0, drone_t1.uid, node_1.node_id)
	_check("(e) another team's drone is refused with the value text", answer == OrderKinds.TEXT_VALUE, answer)
	_check("(e) the refusal code is value", OrderKinds.reason_code(answer) == "value", OrderKinds.reason_code(answer))
	await _tick(3)
	_check("(e) the other team's drone's assign is unchanged", drone_t1.assign == before, "assign=%s was %s" % [drone_t1.assign, before])
	# (f) a node that does not exist: "No such node", code place.
	answer = _submit(0, d.uid, "missing_" + node_1.node_id)
	_check("(f) a missing node is refused with No such node", answer == "No such node", answer)
	_check("(f) the refusal code is place", OrderKinds.reason_code(answer) == "place", OrderKinds.reason_code(answer))
	# (g) a lane turret site has no ore rocks: refused "value".
	var site: ResourceNode = null
	for n in world.nodes:
		if n.ore.size() == 0:
			site = n
			break
	_check("(g) setup: the map has a node with no ore rocks", site != null)
	if site != null:
		answer = _submit(0, d.uid, site.node_id)
		_check("(g) a node with no ore rocks is refused with the value text", answer == OrderKinds.TEXT_VALUE, answer)
		_check("(g) the refusal code is value", OrderKinds.reason_code(answer) == "value", OrderKinds.reason_code(answer))
	# (h) the mothership is not a drone: refused "value".
	answer = _submit(0, world.mothership(0).uid, node_1.node_id)
	_check("(h) the mothership is refused with the value text", answer == OrderKinds.TEXT_VALUE, answer)
	_check("(h) the refusal code is value", OrderKinds.reason_code(answer) == "value", OrderKinds.reason_code(answer))
	# (i) no such unit: refused "gone" before any other rule.
	answer = _submit(0, -1, node_1.node_id)
	_check("(i) an unknown unit is refused with the gone text", answer == OrderKinds.TEXT_GONE_UNIT, answer)
	_check("(i) the refusal code is gone", OrderKinds.reason_code(answer) == "gone", OrderKinds.reason_code(answer))


## The cases of item 4: the words that say how much ore a drone carries, and when they show.
func _cargo_cases() -> void:
	# (j) the words.
	_check("(j) 120 of 300 reads Ore 120/300", MiningDrone.cargo_words(120.0, 300.0) == "Ore 120/300", MiningDrone.cargo_words(120.0, 300.0))
	_check("(j) 0 of 300 reads Ore 0/300", MiningDrone.cargo_words(0.0, 300.0) == "Ore 0/300", MiningDrone.cargo_words(0.0, 300.0))
	_check("(j) 119.6 of 300 rounds to Ore 120/300", MiningDrone.cargo_words(119.6, 300.0) == "Ore 120/300", MiningDrone.cargo_words(119.6, 300.0))
	var d := drone_a
	d.cargo = 75.0
	var want := "Ore 75/%d" % roundi(d.capacity)
	_check("(j) a real drone's words follow its cargo", MiningDrone.cargo_words(d.cargo, d.capacity) == want, MiningDrone.cargo_words(d.cargo, d.capacity))
	# (k) when they show.
	_check("(k) the pointer on the drone shows the words", MiningDrone.cargo_shown(Vector2.ZERO, Vector2.ZERO, 1.0, 12.0, false))
	_check("(k) a pointer 500 away does not show them", not MiningDrone.cargo_shown(Vector2(500.0, 0.0), Vector2.ZERO, 1.0, 12.0, false))
	_check("(k) the same pointer at a far zoom (40 world units a pixel) shows them", MiningDrone.cargo_shown(Vector2(500.0, 0.0), Vector2.ZERO, 40.0, 12.0, false))
	_check("(k) a selected drone shows them wherever the pointer is", MiningDrone.cargo_shown(Vector2(500.0, 0.0), Vector2.ZERO, 1.0, 12.0, true))


## Wait for the starting drones, choose the nodes, run the cases, print the result.
func _run() -> void:
	var ok := await _until(func() -> bool: return not _drones_of(0).is_empty() and not _drones_of(1).is_empty(), 120)
	_check("(setup) both teams have a living drone", ok)
	if not ok:
		_finish()
		return
	var mine := _drones_of(0)
	drone_a = mine[0]
	drone_b = mine[1] if mine.size() > 1 else mine[0]
	drone_t1 = _drones_of(1)[0]
	var found := _choose_nodes(drone_a)
	_check("(setup) two ore nodes were found that team 0 may mine and the automatic choice does not pick", found)
	if not found:
		_finish()
		return
	await _node_cases()
	await _order_cases()
	_cargo_cases()
	_finish()


## Print the result line and end the run.
func _finish() -> void:
	print("drone_send_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()
