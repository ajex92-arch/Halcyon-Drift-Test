class_name WingmanAI
extends PilotAI
## WHAT THIS IS: the brain of one wingman. It flies a pilot's wingman the way an AI pilot flies,
## using the same parts (fighting, route finding, target picking and the power switches), but it
## takes its orders from the wing's record instead of choosing a lane job. It keeps its place in the
## shape around the leader, fights what the fire setting lets it, and flies home when the leader is
## shot down or docks.
##
## HOW IT WORKS: it thinks four times a second (every 15 ticks, the first time at the tick that is its
## unit id modulo 15) and steers every second tick (every tick during a Bomber's torpedo run). A
## think reads the wing's lead record and the standing order and decides the mode: follow ("Form on
## me"), cover ("Cover me"), attack, guard, hold, regroup or home. It finds the leader (or the ward
## for a guard), works out what to shoot and writes its facts into its record (state, in slot,
## catching up). A steer works out the place in the shape (SquadEngine) and either fights the
## target (PilotCombat.fight) or flies to the place: very far or past a rock by the route finder
## (PilotFlight.travel), near by the velocity rule (the leader's velocity plus a pull toward the
## place). The leader is never slowed: a slower hull trails behind. In the asteroid jungle the shape
## is the tight column. A wingman that is going home uses the AI pilots' own going-home code.
##
## WHO USES IT: Squads.launch_wingman() makes one for each wingman that launches and puts it in the
## ship's `controller`; the ship calls update() every tick. It is never in World.pilot_ai, so the
## shopping code never runs for it. PilotAI._init draws one random number for the first think time
## (the parent's constructor cannot skip it); nothing else here rolls dice.

## The pilot skill of every wingman: the skill whose aim equals today's Snub-Fighter.
const WING_SKILL := 0.77
## Ticks between two thinks (four a second).
const THINK_EVERY := 15
## A wingman steers on every this-many'th tick.
const STEER_EVERY := 2
## The orbit direction flips every this many ticks (2.5 seconds).
const ORBIT_FLIP_TICKS := 150
## A prime that spreads the orbit flips of different wingmen apart.
const ORBIT_SPREAD := 37
## Boost only with at least this fraction of the battery.
const BOOST_ENERGY := 0.5
## The longest straight line to the place that is checked for rocks (world units). A wingman farther away than this is
## treated as having a rock in the way, so it flies the route.
const DIRECT_MAX := 14000.0
## While a wingman flies a route it keeps one route goal and takes the place as the new goal only when the place has moved this
## far from it (a goal that moves with the leader makes the route finder plan a new route every second).
const ROUTE_GOAL_STEP := 2500.0
## ... or when the wingman is this close to the route goal.
const ROUTE_GOAL_NEAR := 1000.0
## How many of a new route's first points are looked at for one that lies behind the wingman (see _plan_route).
const ROUTE_SKIP_LOOK := 6
## A new route starts at a point that lies within this many radians of the way the wingman is going (see _plan_route).
const ROUTE_START_TURN := 1.0
## A route's point this close to the wingman counts as reached (PilotFlight.travel() reaches a waypoint within 350, less in the jungle).
const ROUTE_REACH := 350.0

## This wingman's record in World.squads (null until it starts).
var rec: Squad = null
## The wing's lead record.
var lead: Squad = null
## The mode this think chose: "follow", "cover", "attack", "guard", "hold", "regroup" or "home".
var mode := "follow"
## The leader's ship (check is_instance_valid before use).
var leader: Ship = null
## The ward of a guard (a Ship or the Mothership), or null.
var ward: Unit = null
## The spacing S of the wing this think.
var spacing_s := 110.0
## True while the leader is in the jungle (the wing flies the tight column).
var jungle := false
## The shape flown this think (the chosen one, or the jungle column).
var shape := Formations.WEDGE
## The point and heading (degrees) of a "Hold here".
var hold_at := Vector2.ZERO
## The heading (degrees) of a "Hold here".
var hold_heading := 0.0
## The guard pocket's half-angle for the ward's hull (degrees).
var cone := 70.0
## True when a rock lies across the straight line to the place (checked at each think; a place farther than DIRECT_MAX counts as blocked).
var rock_between := false
## The point the route is flown to while a route is flown (see ROUTE_GOAL_STEP), or INF when no route is being flown.
var route_goal := Vector2.INF
## A list the spatial hash fills (kept so no list is made each time).
var scratch: Array = []
## The tick of the standing order, the fire stance and the formation at the last think (a change makes the
## wingman think at once).
var seen_order_tick := -1
## The fire stance at the last think.
var seen_fire := 0
## The formation at the last think.
var seen_formation := 0


## Make the brain for crew profile `p`. The parent makes the parts and draws one random number for its
## first think time; the skill is then set.
func _init(w: World, p: PilotProfile) -> void:
	super(w, p)
	skill = WING_SKILL


## Called once by Squads when the wingman's ship `ship` has launched: find the records and start fresh.
## It does not think yet: a launch can come between two ticks (from the hangar's button), when the
## spatial hash still holds ships that have since been freed. The first update, inside a tick, thinks.
func start(ship: Ship) -> void:
	_reset_after_launch()
	route_goal = Vector2.INF
	rec = Squads.record_of(world, profile)
	ship.controls.assist = true
	seen_order_tick = -2


## A wingman never shops: nothing happens while it is docked (a crew is never in World.pilot_ai, so
## this is not even called).
func update_docked(_dt: float) -> void:
	pass


## Every tick while flying (the ship calls it through its controller): think now and then, steer
## on every second tick. A Bomber in a torpedo run steers every tick, because the run counts calls.
func update(ship: Ship, _dt: float) -> void:
	var tick := world.tick_count
	var thought := tick % THINK_EVERY == ship.uid % THINK_EVERY or _orders_changed()
	if thought:
		_think(ship)
	if thought or (tick + ship.uid) % STEER_EVERY == 0 or run.phase != PilotRun.IDLE:
		orbit = _orbit_sign(tick, ship.uid)
		_steer(ship)


## Has the wing been given a new order, formation or fire setting since the last think? Then the
## wingman thinks at once instead of waiting for its turn, so an order is felt the tick after it is applied.
func _orders_changed() -> bool:
	return rec != null and (int(rec.order.get("tick", -1)) != seen_order_tick or rec.fire_stance != seen_fire or rec.formation != seen_formation)


## Which way to slide sideways while fighting: flips every ORBIT_FLIP_TICKS ticks, from the tick
## count and the unit id (no dice).
@warning_ignore("integer_division")
func _orbit_sign(tick: int, uid: int) -> float:
	return 1.0 if ((tick + uid * ORBIT_SPREAD) / ORBIT_FLIP_TICKS) % 2 == 0 else -1.0


# --- thinking ------------------------------------------------------------------------------------

## One think: find the leader, decide the mode, choose the target and note the facts in the record.
func _think(ship: Ship) -> void:
	var w := world
	if rec == null:
		rec = Squads.record_of(w, profile)
	if rec == null:
		mode = "hold"
		return
	seen_order_tick = int(rec.order.get("tick", -1))
	seen_fire = rec.fire_stance
	seen_formation = rec.formation
	lead = w.squads.get(rec.wing_id)
	if lead == null:
		lead = rec
	Squads.sync(w, rec, profile)
	leader = Squads.leader_ship(w, rec)
	var lp := Squads.leader_profile(w, rec)
	# Step 1: straggling and the leader's state. The leader docked or dead, or a wingman too far from the
	# leader for too long, goes home.
	var dist_leader := INF if leader == null else ship.global_position.distance_to(leader.global_position)
	# (A wing that guards or holds stays with its ward or its point wherever the leader goes.)
	var anchored := mode == "guard" or mode == "hold"
	var strag := SquadEngine.straggler_ticks(int(rec.engine.get("strag", 0)), 0.0 if anchored else dist_leader, THINK_EVERY)
	rec.engine["strag"] = strag
	if SquadEngine.is_straggler(strag):
		rec.engine["strayed"] = true
	elif dist_leader < SquadEngine.STRAGGLER_DIST * 0.5:
		rec.engine.erase("strayed")
	var leader_gone := leader == null or lp == null or lp.state != "flying"
	if leader_gone or bool(rec.engine.get("strayed", false)):
		if leader_gone:
			Squads.note_home(w, lead)
		_think_home(ship)
		return
	# Step 2: the standing order gives the mode; the shape and the spacing come from the leader.
	state = "lane"
	spacing_s = SquadEngine.spacing(leader.radius)
	jungle = SquadEngine.in_jungle(w, leader.global_position)
	shape = SquadEngine.effective_formation(rec.formation, jungle)
	_read_order(ship)
	# Step 3: what to shoot, then the facts for the strip.
	var t := _choose_target(ship)
	target = t
	lock_target = t
	goal = _slot(ship)
	var d := ship.global_position.distance_to(goal)
	rock_between = d > DIRECT_MAX or not w.asteroids.segment_hit(ship.global_position, goal, ship.radius + 8.0).is_empty()
	rec.engine["in_slot"] = SquadEngine.in_slot(d)
	rec.engine["catching"] = SquadEngine.catching_up(d, spacing_s)
	if t != null:
		rec.state = Squads.STATE_FIGHTING
	elif mode == "hold" and SquadEngine.in_slot(d):
		rec.state = Squads.STATE_IDLE
	else:
		rec.state = Squads.STATE_MOVING
	systems.set_energy_and_shields(ship)


## Going home: the AI pilots' own code flies to the mothership and asks to dock when close.
func _think_home(ship: Ship) -> void:
	mode = "home"
	state = "home"
	target = null
	lock_target = null
	intent = ""
	var ms := world.mothership(ship.team)
	if ms != null:
		goals.think_home(ship, ms)
	# A dock request that works removes the ship at once: note it in the record now (the next think of a
	# ship that did not dock puts the facts right again).
	if ship.controls.dock:
		rec.member_uids.clear()
		rec.state = Squads.STATE_DOCKED
	else:
		rec.state = Squads.STATE_HOME
	rec.engine["catching"] = true
	rec.engine["in_slot"] = false
	systems.set_energy_and_shields(ship)


## Read the standing order into the mode, the ward and the hold point. An order whose target is gone
## (the ward docked or died, the attack target died or is out of reach) lapses to "follow me".
func _read_order(ship: Ship) -> void:
	var o := rec.order
	var settings: Dictionary = o.get("settings", {})
	ward = null
	intent = ""
	match str(o.get("kind", OrderKinds.ESCORT)):
		OrderKinds.ATTACK:
			mode = "attack"
			intent = "prey"
		OrderKinds.GUARD:
			mode = "guard"
			ward = world.orders.unit_by_uid(int(o.get("target", 0)))
			if ward == null or ward.team != ship.team:
				_lapse()
				return
			cone = SquadEngine.guard_cone(Ships.get_def((ward as Ship).hull_id)) if ward is Ship else SquadEngine.GUARD_CONE_MAX
		OrderKinds.HOLD:
			mode = "hold"
			var p: Vector2i = o.get("target", Vector2i.ZERO)
			hold_at = Vector2(p)
			hold_heading = float(settings.get("heading", 0))
		OrderKinds.MOVE:
			mode = "regroup"
			_read_regroup()
		_:
			mode = "cover" if str(settings.get("role", "follow")) == "defend" else "follow"


## Put the wing back to "follow me" (the standing order lapsed) and follow now.
func _lapse() -> void:
	Squads.lapse_to_follow(world, lead)
	mode = "follow"
	ward = null
	intent = ""


## A regroup ends when every wingman that flies is in its place, or after REGROUP_TICKS.
func _read_regroup() -> void:
	var late := world.tick_count - int(lead.engine.get("regroup_t", 0)) >= SquadEngine.REGROUP_TICKS
	var all_in := true
	for sib: Squad in Squads.wing_records(world, lead.wing_id):
		if sib.state != Squads.STATE_DOCKED and sib.state != Squads.STATE_HOME and not bool(sib.engine.get("in_slot", false)):
			all_in = false
	if late or all_in:
		_lapse()


## What to shoot this think: nothing in a regroup or under "hold fire"; the attack target of an
## attack; else the nearest or best target the fire setting and the order allow. A target past the
## leash of its order is given up for a while.
func _choose_target(ship: Ship) -> Unit:
	var fire := rec.fire_stance
	if fire == 2 or mode == "regroup" or mode == "home":
		return null
	var t: Unit = null
	var slot := _slot(ship)
	match mode:
		"attack":
			t = _attack_target(ship)
		"hold":
			t = WingTargets.pick(self, ship, fire, PilotTargeting.main_reach(ship) + SquadEngine.HOLD_REACH_PAD, [leader, ship])
		"cover":
			if fire == 1:
				t = WingTargets.attackers(world, ship.team, [leader, ship], leader.global_position)
				if t != null and leader.global_position.distance_to(t.global_position) > SquadEngine.COVER_RADIUS:
					t = null
			else:
				t = WingTargets.around(world, ship.team, leader.global_position, SquadEngine.COVER_RADIUS, scratch)
		"guard":
			t = WingTargets.attackers(world, ship.team, [ward], ward.global_position)
			if t == null and fire == 0:
				t = WingTargets.around(world, ship.team, ward.global_position, SquadEngine.GUARD_ENGAGE, scratch)
		_:
			t = WingTargets.pick(self, ship, fire, SquadEngine.PICK_RADIUS, [leader, ship])
			if t != null and slot.distance_to(t.global_position) > SquadEngine.PICK_RADIUS:
				t = null
	if t == null:
		return null
	# A target past the leash is given up for a while; one in the lane the ward is firing along is not shot.
	if mode != "attack" and ship.global_position.distance_to(_leash_point(slot)) > _leash_length():
		_skip(t)
		return null
	if mode == "guard" and _in_ward_lane(t):
		return null
	return t


## The attack target of an ATTACK order, or null: the order lapses to "follow me" when the target
## is gone, farther from the leader than the wing may go, or has stayed hidden for 3 seconds.
func _attack_target(ship: Ship) -> Unit:
	var t := world.orders.unit_by_uid(int(rec.order.get("target", 0)))
	if t == null:
		_lapse()
		return null
	var reach := (t as Mothership).hull_dist(leader.global_position) if t is Mothership else leader.global_position.distance_to(t.global_position)
	if reach > SquadEngine.ATTACK_LEASH:
		_lapse()
		return null
	if t.visible_to(ship.team):
		lead.engine["attack_hidden"] = 0
		return t
	var hidden := int(lead.engine.get("attack_hidden", 0)) + THINK_EVERY
	lead.engine["attack_hidden"] = hidden
	if hidden >= SquadEngine.ATTACK_HIDDEN_TICKS:
		_lapse()
	return null


## Give target `t` up for SKIP_SECS seconds (the target pickers pass over it).
func _skip(t: Unit) -> void:
	skip_id = t.get_instance_id()
	skip_until = world.time + SquadEngine.SKIP_SECS


## The point the leash is measured from: the ward for a guard, the leader for "Cover me", else the place.
func _leash_point(slot: Vector2) -> Vector2:
	if mode == "guard" and ward != null:
		return ward.global_position
	if mode == "cover":
		return leader.global_position
	return slot


## How far (world units) a wingman may chase from the leash point in the current mode.
func _leash_length() -> float:
	match mode:
		"guard":
			return SquadEngine.GUARD_LEASH
		"cover":
			return SquadEngine.COVER_LEASH
		"hold":
			return SquadEngine.HOLD_LEASH
	return SquadEngine.leash(shape, jungle)


## Is unit `u` still there (not freed, not dead)?
func _alive(u) -> bool:
	return u != null and is_instance_valid(u) and (u as Unit).alive


## Is target `t` on the line the ward is firing along (a Ship ward only: the mothership's guns aim by
## themselves)?
func _in_ward_lane(t: Unit) -> bool:
	if not (ward is Ship):
		return false
	return SquadEngine.in_fire_lane(ward.global_position, (ward as Ship).controls.aim_point, t.global_position)


# --- the place in the shape ---------------------------------------------------------------------

## The world point of this wingman's place: around the leader in the frame, around the hold point, or in
## the guard pocket (flank slots for the mothership).
func _slot(ship: Ship) -> Vector2:
	var idx := rec.slot_index
	if mode == "hold":
		return SquadEngine.hold_slot(hold_at, hold_heading, shape, idx, spacing_s)
	if mode == "guard" and ward != null and is_instance_valid(ward) and ward.alive:
		if ward is Mothership:
			var ms := ward as Mothership
			return SquadEngine.mothership_slot(ms.global_position, ms.rotation, ms.half_len, ms.beam, idx)
		return SquadEngine.guard_slot(ward.global_position, ward.rotation, ward.radius, cone, idx)
	if leader != null and is_instance_valid(leader) and leader.alive:
		var h := Squads.frame_heading(world, lead, leader)
		return SquadEngine.slot_target(leader.global_position, leader.velocity, h, shape, idx, spacing_s)
	return ship.global_position


## The velocity the place itself moves with: the ward's in a guard, none in a hold, else the leader's.
func _place_velocity() -> Vector2:
	if mode == "hold":
		return Vector2.ZERO
	if mode == "guard" and ward != null and is_instance_valid(ward):
		return ward.velocity
	if leader != null and is_instance_valid(leader):
		return leader.velocity
	return Vector2.ZERO


# --- steering --------------------------------------------------------------------------------------

## Every steer: fight the target, or fly to the place. Going home is the AI pilots' own steering.
func _steer(ship: Ship) -> void:
	# A leader or ward that vanished since the last think (shot down, docked) is noticed at once.
	if mode != "home" and rec != null and (not _alive(leader) or (mode == "guard" and not _alive(ward))):
		_think(ship)
	if mode == "home" or rec == null:
		# The flight home plans its route here (the same start rule as the flight to the place), so that travel() finds a route
		# for its goal already and keeps it.
		if mode == "home" and goal != Vector2.INF and (ship.global_position.distance_to(goal) > 2500.0 or not world.map.in_open_lane(ship.global_position)):
			_plan_route(ship, goal)
		combat.steer(ship)
		return
	var c := ship.controls
	c.fire = false
	c.boost = false
	c.special = false
	if target != null and (not is_instance_valid(target) or not target.alive):
		target = null
	var slot := _slot(ship)
	var fighting := target != null and not combat.target_far(ship)
	if fighting and mode != "attack" and ship.global_position.distance_to(_leash_point(slot)) > _leash_length():
		_skip(target)
		target = null
		lock_target = null
		fighting = false
	if fighting and mode == "guard" and _in_ward_lane(target):
		fighting = false
	if fighting:
		combat.fight(ship)
		if rec.fire_stance == 2:
			c.fire = false
	else:
		if run.phase != PilotRun.IDLE:
			run.abandon()
		_fly_to(ship, slot)
	if ship.run_mount != null:
		run.settle(ship)


## Fly to `slot` with no target: far or past a rock by the route finder, near by the velocity rule.
func _fly_to(ship: Ship, slot: Vector2) -> void:
	var c := ship.controls
	var p := ship.global_position
	var d := p.distance_to(slot)
	if rock_between:
		if route_goal == Vector2.INF or slot.distance_to(route_goal) > ROUTE_GOAL_STEP or p.distance_to(route_goal) < ROUTE_GOAL_NEAR:
			route_goal = slot
		_plan_route(ship, route_goal)
		flight.travel(ship, route_goal, SquadEngine.IN_SLOT)
		c.aim_point = c.face_point
		return
	route_goal = Vector2.INF
	# No route is flown now: forget the last one, so a later route is not joined to a stale waypoint (see _plan_route).
	if path_goal != Vector2.INF:
		path = PackedVector2Array()
		path_goal = Vector2.INF
	var vel := _place_velocity()
	var wanted := SquadEngine.wanted_velocity(vel, slot, p, ship.f_max, jungle)
	var sticks := SquadEngine.stick_values(wanted, ship.velocity, ship.rotation)
	c.forward = sticks.x
	c.strafe = sticks.y
	# The nose follows the wanted velocity; nearly still, it follows the place's heading.
	if wanted.length() > 20.0:
		c.face_point = p + wanted.normalized() * 400.0
	else:
		c.face_point = p + Vector2.from_angle(_place_heading()) * 400.0
	c.aim_point = c.face_point
	var open_here := world.map.in_open_lane(p)
	var open_slot := world.map.in_open_lane(slot)
	var boost_ok := SquadEngine.may_boost(d, spacing_s, open_here, open_slot)
	if mode == "regroup":
		boost_ok = d > 2.0 * SquadEngine.IN_SLOT and open_here and open_slot
	c.boost = boost_ok and not jungle and ship.can_boost and ship.energy.fraction() > BOOST_ENERGY
	flight.avoid_rocks(ship)


## Plan the route to a goal the way PilotFlight.travel() would (when none is held or the goal is over 600 from the held route's goal), but start it
## without a turn: the route finder starts at the point of its graph nearest the ship, which can lie behind it, and a Bomber (1.15 radians a second)
## lost most of its speed turning back to it. A route being flown is continued through the waypoint the ship is heading for; a first route starts at
## the first of its first ROUTE_SKIP_LOOK points that is within ROUTE_START_TURN of the way the ship is going and has a clear line (else at the first
## point). travel() then finds a route that fits the goal and keeps it. The flight home plans its route through here too.
func _plan_route(ship: Ship, to: Vector2) -> void:
	if path_goal != Vector2.INF and path_goal.distance_to(to) <= 600.0 and not path.is_empty():
		return
	var p := ship.global_position
	# A route being flown goes on through the waypoint the ship is heading for (when that waypoint is nearer the new goal than the
	# ship is and the line to it is clear): the new route is planned from there, so the ship does not turn back to the route
	# finder's nearest point (the measured turns of 1.3 to 2.5 radians at each new route of a Bomber 6,000 behind its pilot).
	if path_goal != Vector2.INF and path_goal.distance_to(to) <= 2.0 * ROUTE_GOAL_STEP and not path.is_empty() and path_i < path.size() - 1:
		var wp := path[path_i]
		if wp.distance_to(to) < p.distance_to(to) and world.asteroids.segment_hit(p, wp, ship.radius + 8.0).is_empty():
			var rest := JungleBigFeature.plan_route(world.map.route, ship, wp, to)
			if not rest.is_empty():
				var joined := PackedVector2Array([wp])
				joined.append_array(rest)
				path = joined
				path_goal = to
				path_i = 0
				return
	path = JungleBigFeature.plan_route(world.map.route, ship, p, to)
	path_goal = to
	path_i = 0
	# A new route starts at the first of its first points that is within ROUTE_START_TURN of the way the ship is going (its
	# velocity, or its nose when nearly still) and has a clear line; when none is, at the first point (a flight home from
	# straight away from home is a real U-turn).
	# (Points within ROUTE_REACH of the ship count as reached: travel() skips them at once.)
	var heading := ship.velocity.angle() if ship.velocity.length() > 60.0 else ship.rotation
	var first := 0
	while first < path.size() - 1 and p.distance_to(path[first]) < ROUTE_REACH:
		first += 1
	path_i = first
	for k in range(first, mini(path.size(), first + ROUTE_SKIP_LOOK)):
		if absf(Util.ang_diff(heading, (path[k] - p).angle())) < ROUTE_START_TURN and (k == first or world.asteroids.segment_hit(p, path[k], ship.radius + 8.0).is_empty()):
			path_i = k
			return

## The heading (radians) the wing faces: the hold heading in a hold, the ward's in a guard, else the leader's.
func _place_heading() -> float:
	if mode == "hold":
		return deg_to_rad(hold_heading)
	if mode == "guard" and ward != null and is_instance_valid(ward):
		return ward.rotation
	if leader != null and is_instance_valid(leader):
		return leader.rotation
	return 0.0
