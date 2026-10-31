class_name AdmiralCommand
extends RefCounted
## WHAT THIS IS: the rule book for every order an admiral can give. The
## admiral is the team member who doesn't fly: they spend the team's shared
## money (the "treasury") on mining drones, mothership facilities,
## research, turrets, repair bays and wards, set the team waypoint, move the
## mothership, and (with the Fleet Command Module) buy and order minions
## (small computer-flown ships that push down the lanes).
##
## HOW IT WORKS: each order function first checks the rules (is it
## unlocked? is there room? can the team pay?). If the order is allowed, it
## pays from the treasury and carries the order out. It returns "" when the
## order worked, or a short message for the player saying why not (for
## example "Not enough in the team treasury (120 short)"). Every order is one
## order record (Order): _order() gets it, either the queued record that the order
## queue is carrying out now (`pending`) or, for a direct call, a new one for the
## computer Admiral; and every order ends in _done(), which logs it, counts it and
## sends the Events.admiral_result signal (a message any other part of the game
## can listen for), so the HUD can show the result. Functions whose names end in
## "_blocker" only check: they return the reason an order would fail, or "", and
## change nothing.
##
## WHO USES IT: World makes one (World.command, in World.setup). The human
## admiral's screens (AdmiralBoard in scripts/ui/admiral_board.gd and
## CommandOverlay in scripts/ui/command_overlay.gd) hand their orders to the
## order queue (World.orders), which calls these functions at the start of the next
## tick; the computer admiral (AdmiralAI and its parts in scripts/ai/) and the tests
## call them directly, so humans and the AI play by identical rules. The HUD
## (scripts/ui/hud.gd) listens to Events.admiral_result and shows a toast. The
## tests support_probe.gd and ui_tour.gd call it too. (`orders` below is the
## feature modules' list of extra orders; the order queue is World.orders.)
##
## DESIGN.md A11-A13 has the rules: drones, facilities, research, turrets at
## node slots, repair bays (they fly out and anchor), wards (only where the
## team can see), the waypoint, mothership moves (from 20:00, admiral
## docked) and Fleet Command minion purchases and orders.

## The refusal for a mothership move into the jungle (also used by the order
## queue's check that runs before the order is queued).
const JUNGLE_TEXT := "The mothership is too big for the jungle; pick a spot in a lane or base"

## The game world (teams, nodes, units, the map).
var world: World
## Feature hook: extra admiral orders that feature modules add (Sensor Sweep,
## Supply Drop, Barrage, Bounty, Fortify). order id -> a Dictionary that
## CommandOrders describes. The admiral board, the map tools and the HUD
## read this list to show a button, a map tool, a status tag and a help
## line for each order. Empty (the default) = the orders of today's game.
var orders := {}
## Feature hook: marks that feature modules want drawn on the map and the
## minimap (a ring with a label, such as the red Barrage circle). Each is
## a Dictionary that CommandOrders.add_mark() makes. Empty by default.
var marks: Array = []
## The queued order record that the order queue is carrying out right now, or {}
## for a direct call (the computer admiral's, a test's).
var pending: Dictionary = {}
## What an order function returns when _order() gave it no record to work on: ""
## (the order was queued for the next tick, or a replay refused a direct call) or the
## refusal text of the queue's checks.
var _early := ""


## World makes this once and passes itself in.
func _init(w: World) -> void:
	world = w


## Every order ends here. It logs and counts the order (the order queue), sends the
## Events.admiral_result signal (team, which action, whether it worked, the message)
## unless the kind has no toast word, and hands the message back, so an order can
## finish with `return _done(...)` in one line. `msg` is "" for success, or the
## reason it failed.
func _done(o: Dictionary, msg: String) -> String:
	if world.orders != null:
		world.orders.log_and_count(o, msg)
	var word := OrderKinds.action_word(str(o["kind"]), int(o["seat"]))
	if word != "none":
		Events.admiral_result.emit(int(o["team"]), word, msg == "", msg)
	return msg


## The order record the order function works on. While the order queue is carrying
## out a queued order that is `pending`. Otherwise this is a direct call (the computer
## admiral's or a test's): a new record with the admiral's seat, stamped with this
## tick and a number. Returns {} when there is no record to work on; the function then
## returns `_early`: a direct call during a replay of the computer's orders is refused
## and changes nothing, and with the switch OrderQueue.AI_THROUGH_QUEUE on a direct call
## is queued for the next tick like a human's (or refused at once).
func _order(team: int, kind: String, settings: Dictionary, target_kind: String = "none", target = null, subjects: Array = [], human: bool = false) -> Dictionary:
	if not pending.is_empty():
		return pending
	_early = ""
	var o := Order.make(kind, team, Rules.ADMIRAL_SEAT, human, settings, subjects, target_kind, target)
	var q := world.orders
	if q == null:
		o["id"] = 0
		o["tick"] = world.tick_count
		o["apply_tick"] = world.tick_count
		return o
	if not human:
		if q.replaying_ai:
			return {}
		if OrderQueue.AI_THROUGH_QUEUE:
			_early = q.submit(o)
			return {}
	o["tick"] = world.tick_count
	o["apply_tick"] = world.tick_count
	o["id"] = q.take_id()
	q.count_submitted(o)
	return o


## Why one more mining drone can't be ordered now, or "" if it can. Two rules: living
## drones plus queued ones must stay under the limit (14), and at most 6 drones may
## wait in the build queue. The price is not checked here.
func drone_blocker(team: int) -> String:
	var ts := world.teams[team]
	# Rule 1: living drones plus queued ones must stay under the limit (14).
	if world.mining_drone_count(team) + ts.drone_queue.size() >= int(Structures.MINING_DRONE["max"]):
		return "Drone limit reached (%d)" % int(Structures.MINING_DRONE["max"])
	# Rule 2: at most 6 drones waiting in the build queue.
	if ts.drone_queue.size() >= 6:
		return "Drone build queue is full (6 at a time)"
	return ""


## Order one more mining drone (a small robot ship that mines ore and brings
## it home, which pays the team and its pilots). It joins the mothership's
## build queue and appears when built (Structures.MINING_DRONE "build",
## 6 s each, one at a time).
## `node_id` is the resource node it should keep mining at, or "" to let
## the game pick a node each trip (World.best_node_for_drone). Costs 200
## credits (Structures.MINING_DRONE "cost").
func build_drone(team: int, node_id: String = "") -> String:
	var o := _order(team, OrderKinds.DRONE, {"node": node_id})
	if o.is_empty():
		return _early
	var ts := world.teams[team]
	# Rules 1 and 2: the limits (drone_blocker).
	var blocked := drone_blocker(team)
	if blocked != "":
		return _done(o, blocked)
	# Rule 3: pay for it.
	var cost: float = float(Structures.MINING_DRONE["cost"])
	if not ts.spend(cost):
		return _done(o, "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury)))
	# Queue it. If the queue was empty, start the build clock now, so this
	# drone takes the full build time. (TeamState._drone_line builds them.)
	if ts.drone_queue.is_empty():
		ts.drone_t = float(Structures.MINING_DRONE["build"])
	ts.drone_queue.append(node_id)
	return _done(o, "")


## Build facility `id` onto our mothership (a module from Tech.FACILITIES,
## such as the Research Module). TeamState.queue_facility() checks the
## rules, pays and queues it.
func build_facility(team: int, id: String) -> String:
	var o := _order(team, OrderKinds.MODULE, {}, "id", id)
	if o.is_empty():
		return _early
	return _done(o, world.teams[team].queue_facility(id))


## Start researching tech `id` (an upgrade from Tech.TECHS).
## TeamState.queue_research() checks the rules, pays and queues it.
func research(team: int, id: String) -> String:
	var o := _order(team, OrderKinds.RESEARCH, {}, "id", id)
	if o.is_empty():
		return _early
	return _done(o, world.teams[team].queue_research(id))


## Why a turret of type `ttype` ("pd" = point defence, "torp" = torpedo)
## can't be built at resource node `node_id` right now, or "" if it can.
## The price is not checked here.
func turret_blocker(team: int, node_id: String, ttype: String) -> String:
	var n := world.node_by_id(node_id)
	if n == null:
		return "No such node"
	# Torpedo turrets need the Platform Missiles research first (an unlocked
	# Admiral, UnlockAll, needs no research).
	if ttype == "torp" and not world.teams[team].turret_torp and not UnlockAll.is_unlocked(world.teams[team]):
		return "Needs Platform Missiles research"
	# The node itself checks the rest (ResourceNode.build_blocker): whose
	# side it is, a recently destroyed turret, torpedo turrets only at inner
	# nodes, enemy turrets there, a free slot, enemy ships close by.
	return n.build_blocker(team, ttype)


## Build a turret of type `ttype` in the first free slot at node `node_id`.
## Prices are in TurretData.TURRETS (450 credits for PD, 750 for torpedo).
func build_turret(team: int, node_id: String, ttype: String) -> String:
	var o := _order(team, OrderKinds.TURRET, {"ttype": ttype}, "node", node_id)
	if o.is_empty():
		return _early
	# Rule 1: allowed here?
	var b := turret_blocker(team, node_id, ttype)
	if b != "":
		return _done(o, b)
	# Rule 2: pay for it.
	var cost: float = float(TurretData.TURRETS[ttype]["cost"])
	var ts := world.teams[team]
	if not ts.spend(cost):
		return _done(o, "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury)))
	# Build it.
	var n := world.node_by_id(node_id)
	world.spawn_turret(team, n, n.free_slot(), ttype)
	return _done(o, "")


## Why team `team` can't rebuild its defense post on lane `lane` right now, or ""
## if it can. Only a destroyed post whose rebuild timer has run out (PostSite
## state "ready") can be rebuilt, and not while an enemy pilot ship or minion is
## within PostData.BUILD_CLEAR_RADIUS of its spot. The price is not checked here.
func post_blocker(team: int, lane: String) -> String:
	var ps := world.defense_posts.site_of(team, lane)
	if ps == null:
		return "No such post"
	match ps.state:
		PostSite.STANDING:
			return "The post stands"
		PostSite.BUILDING:
			return "The post is being rebuilt"
		PostSite.DESTROYED:
			return "The post was destroyed: %s" % PostData.rebuild_text(ps.ticks_left(world.tick_count))
	if world.any_enemy_ship_near(ps.pos, PostData.BUILD_CLEAR_RADIUS, team):
		return "Enemy ships are too close"
	return ""


## Rebuild team `team`'s defense post on lane `lane`: a PostData.POST price
## (450 credits, the same as a PD turret), then a build of PostData.POST "build"
## seconds before it launches waves again. Only the admiral rebuilds a post, and
## only after the rebuild timer (post_blocker says why not).
func rebuild_post(team: int, lane: String) -> String:
	var o := _order(team, OrderKinds.POST, {}, "lane", lane)
	if o.is_empty():
		return _early
	# Rule 1: allowed now?
	var b := post_blocker(team, lane)
	if b != "":
		return _done(o, b)
	# Rule 2: pay for it.
	var cost: float = float(PostData.POST["cost"])
	var ts := world.teams[team]
	if not ts.spend(cost):
		return _done(o, "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury)))
	# Build it.
	world.defense_posts.rebuild(team, lane)
	return _done(o, "")


## Why a repair bay can't be sent to `point` right now, or "" if it can.
## (A repair bay flies out from the mothership, anchors at the spot for
## good, and its drones heal nearby friendly ships.) The price is not
## checked here.
func bay_blocker(team: int, point: Vector2) -> String:
	var ts := world.teams[team]
	# Rule 1: needs the Repair Bays research (an unlocked Admiral, UnlockAll,
	# needs no research).
	if not ts.repair_bays and not UnlockAll.is_unlocked(ts):
		return "Needs Repair Bays research"
	# Rule 2: at most 3 living bays per team (Structures.REPAIR_BAY "max_per_team").
	var count := 0
	for b in world.bays:
		if b.team == team and b.alive:
			count += 1
	if count >= int(Structures.REPAIR_BAY["max_per_team"]):
		return "You already have %d repair bays" % int(Structures.REPAIR_BAY["max_per_team"])
	# Rule 3: not inside an asteroid (checked with a 60-unit radius).
	if world.asteroids.blocked(point, 60.0):
		return "That spot is inside an asteroid"
	# Rule 4: the bay must be able to fly there from our mothership (small
	# ships may also use the jungle paths, so `true`).
	if world.map.route.path(world.mothership(team).global_position, point, true).is_empty():
		return "The bay can't reach that spot"
	return ""


## Send a new repair bay to `point`. Costs 450 credits
## (Structures.REPAIR_BAY "cost").
func deploy_bay(team: int, point: Vector2) -> String:
	var o := _order(team, OrderKinds.BAY, {}, "point", point)
	if o.is_empty():
		return _early
	# Rule 1: allowed?
	var b := bay_blocker(team, point)
	if b != "":
		return _done(o, b)
	# Rule 2: pay for it.
	var cost: float = float(Structures.REPAIR_BAY["cost"])
	var ts := world.teams[team]
	if not ts.spend(cost):
		return _done(o, "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury)))
	# Launch it.
	world.spawn_bay(team, point)
	return _done(o, "")


## Why a ward can't be placed at `point` right now, or "" if it can. (A
## ward is a small drone that flies to the spot, anchors and keeps watch so
## the team can see there.) The price is not checked here.
func ward_blocker(team: int, point: Vector2) -> String:
	# Rule 1: only where our team can see right now.
	if not world.vision.is_visible(team, point):
		return "Wards can only go where your team can see right now"
	# Rule 2: not inside an asteroid (checked with a 20-unit radius).
	if world.asteroids.blocked(point, 20.0):
		return "That spot is inside an asteroid"
	return ""


## Place a ward at `point`. Costs 75 credits (Structures.WARD "cost"). A
## team may have 6 at once (Structures.WARD "max_per_team"): placing one
## more quietly removes our oldest ward.
func place_ward(team: int, point: Vector2) -> String:
	var o := _order(team, OrderKinds.WARD, {}, "point", point)
	if o.is_empty():
		return _early
	# Rule 1: allowed?
	var b := ward_blocker(team, point)
	if b != "":
		return _done(o, b)
	# Rule 2: pay for it.
	var cost: float = float(Structures.WARD["cost"])
	var ts := world.teams[team]
	if not ts.spend(cost):
		return _done(o, "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury)))
	# Over the cap: the oldest ward (earliest placed_at) shuts down. It is
	# simply removed, with no bounty (reward) for anyone.
	var mine: Array = []
	for w in world.wards:
		if w.team == team and w.alive:
			mine.append(w)
	if mine.size() >= int(Structures.WARD["max_per_team"]):
		mine.sort_custom(func(a, b): return a.placed_at < b.placed_at)
		world.combat.kill_silently(mine[0])
	# Launch the new one.
	world.spawn_ward(team, point)
	return _done(o, "")


## Set the team waypoint (a rally marker that lasts Rules.WAYPOINT_TIME,
## 75 s) at `point`. A waypoint within 6,000 units of the enemy mothership's
## hull also declares a siege on the nearest lane, already in its "assault"
## phase: AI big ships and bombers converge there and attack the enemy
## mothership (TeamState.siege_lane). A waypoint anywhere else calls any
## siege off. With `declare_siege` false (the AI admiral's own waypoint, see
## AdmiralWaypoint) only the marker moves and any siege is left alone: the
## AI starts and ends its sieges itself (AdmiralSiege). `by_human` says who
## placed it: true for a human admiral (the command overlay passes it), false
## for the AI admiral; it is kept in TeamState.waypoint_by_human, and in the
## opening AI pilots follow only a human's waypoint. It is a separate
## argument on purpose: it is not worked out from `declare_siege`.
func set_waypoint(team: int, point: Vector2, declare_siege: bool = true, by_human: bool = false) -> String:
	var o := _order(team, OrderKinds.WAYPOINT, {"siege": 1 if declare_siege else 0}, "point", point, [], by_human)
	if o.is_empty():
		return _early
	var ts := world.teams[team]
	ts.set_waypoint(point, by_human)
	if declare_siege:
		var ems := world.mothership(Rules.enemy_of(team))
		if ems != null and ems.alive and ems.hull_dist(point) < 6000.0:
			# A new assault starts now (siege_t is when its phase began).
			ts.siege_lane = world.map.lane_for(point)
			ts.siege_phase = "assault"
			ts.siege_t = world.time
		else:
			ts.siege_lane = ""
			ts.siege_phase = ""
	return _done(o, "")


## Set team `team`'s siege state: the lane being sieged ("" for none) and its phase
## ("gather", "assault" or "" for none). Only the computer admiral's siege plan
## (AdmiralSiege) calls this, so that its siege calls are orders in the match log
## like all the others. The time the phase began (siege_t) is set only when the new
## phase is a real one and differs from the old phase: a call-off and a change of lane
## alone leave it. Sends no toast.
func set_siege(team: int, lane: String, phase: String) -> String:
	var o := _order(team, OrderKinds.SIEGE, {"phase": phase}, "lane" if lane != "" else "none", lane if lane != "" else 0)
	if o.is_empty():
		return _early
	var ts := world.teams[team]
	var phase_changed := phase != "" and phase != ts.siege_phase
	ts.siege_lane = lane
	ts.siege_phase = phase
	if phase_changed:
		ts.siege_t = world.time
	return _done(o, "")


## Why our mothership can't be given a move order right now, or "" if it
## can. Its engines come online at 20:00 (Rules.MOTHERSHIP_MOVE_UNLOCK,
## 1200 s, read through Rules.move_unlock_time() so a feature module may
## tune it), and the admiral must be docked (not out flying a ship).
func move_blocker(team: int) -> String:
	var ms := world.mothership(team)
	var unlock := Rules.move_unlock_time()
	if world.time < unlock:
		return "The mothership's engines come online at %s" % Util.clock(unlock)
	# A feature (ms_move:flying) may let an admiral who flies a ship give the
	# order too: Rules.tune("mothership_move_needs_dock", true).
	if not world.teams[team].admiral_docked and bool(Rules.tune("mothership_move_needs_dock", true)):
		return "The admiral must be docked to move the mothership"
	# Mothership.can_move(): the engines are online and it isn't in the
	# middle of a hyperspace jump.
	if ms == null or not ms.can_move():
		return "The mothership can't move right now"
	return ""


## Order our mothership to fly to `point`. It must be open space (a lane,
## the crossing or a base, not the jungle), and it follows the lanes there.
func move_mothership(team: int, point: Vector2) -> String:
	var o := _order(team, OrderKinds.MOTHERSHIP_MOVE, {}, "point", point)
	if o.is_empty():
		return _early
	# Rule 1: allowed to move now?
	var b := move_blocker(team)
	if b != "":
		return _done(o, b)
	# Rule 2: the target must be in open space.
	if not world.map.in_open_lane(point):
		return _done(o, JUNGLE_TEXT)
	# Rule 3: find a route along the lanes (big-ship route edges, so `false`),
	# never straight through rocks.
	var ms := world.mothership(team)
	var path := world.map.route.path(ms.global_position, point, false)
	if path.is_empty():
		return _done(o, "The mothership can't find a way there through open space")
	ms.order_move(point, path)
	return _done(o, "")


## Fleet Command: buy one minion of type `type_id` (a key of Minions.TYPES)
## and send it down `lane`. MinionDirector.buy() checks the rules and pays.
func buy_minion(team: int, type_id: String, lane: String) -> String:
	var o := _order(team, OrderKinds.MINION_BUY, {"type": type_id, "lane": lane})
	if o.is_empty():
		return _early
	return _done(o, world.minion_director.buy(team, type_id, lane))


## Fleet Command: give an order to the minions with the ids in `uids` (a minion that
## is gone is skipped). `order` is a dictionary such as {"type": "lane", "lane": "mid"}
## or {"type": "move", "pos": a point} (see MinionDirector.set_order). Needs the Fleet
## Command Module.
func order_minions(team: int, uids: Array, order: Dictionary) -> String:
	var settings := {"type": str(order.get("type", ""))}
	var target_kind := "none"
	var target = null
	if order.has("pos"):
		target_kind = "point"
		target = order["pos"]
	elif order.has("lane"):
		settings["lane"] = str(order["lane"])
		target_kind = "lane"
		target = str(order["lane"])
	var o := _order(team, OrderKinds.MINION_ORDER, settings, target_kind, target, uids)
	if o.is_empty():
		return _early
	if not world.minion_director.controlled(team):
		return _done(o, "Needs the Fleet Command Module")
	# Look each id up; the gone ones are skipped.
	var minions: Array = []
	for uid in uids:
		var u: Unit = null
		if world.orders != null:
			u = world.orders.unit_by_uid(int(uid))
		if u != null:
			minions.append(u)
	world.minion_director.set_order(team, minions, order)
	return _done(o, "")
