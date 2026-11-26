class_name SquadronBrain
extends WingmanAI
## WHAT THIS IS: the brain of one ship of a bought squadron. It flies what the squadron's think (SquadronThink)
## decided and nothing more: the guide (the first living ship) flies to the anchor, the other ships fly the slots
## round the guide (or round the charge in an escort), and the ship fights the one target of the squadron while it
## stays inside its leash. It never goes shopping (it is not in World.pilot_ai), never retreats and never docks, as
## the stand-in did. It scans nothing itself.
##
## HOW IT WORKS: it is a WingmanAI whose thinking and steering are replaced (the wingman's route finding and
## slot-flying are reused: the velocity rule near a slot, the route finder past rocks). Every tick it asks whether it
## is its turn: it steers on every second tick and thinks about itself every 15 ticks (a turret that hunts it
## makes a small or medium ship step away for 2.5 seconds, unless the squadron stands under a Move, Hold or Stop
## order: then it stands firm). A steer reads the plan the squadron wrote in its record's engine notes: the target, the
## leash, the slot. An Attack order is flown with the pilot brain's own steering (the standoff point of the unit,
## the mothership too). With no target for RESUME_TICKS ticks the ships go back to their slots; sooner they stand
## still. While a member is catching up the guide flies at SquadronRules.CATCH_THROTTLE of the throttle. The brain
## draws one random number when it is made (the parent's constructor), so a match with bought ships has its own
## baseline.
##
## WHO USES IT: Arrivals attaches one to each ship of a squadron whose brain value is "squad"; PilotAI asks
## holds_position() before it steps away from a turret; tests/squad_check.gd.

## The share of the ship's braking push the closing speed may use (the rest is room for error).
const BRAKE_SHARE := 0.5
## Until this tick the ship steps away from the turret that hunted it (-1: not stepping away).
var evade_until := -1
## The ship that steers now (its unit id), for the place-velocity and heading questions.
var _me_uid := 0


## Make the brain for crew profile `p` at the stand-in's skill.
func _init(w: World, p: PilotProfile) -> void:
	super(w, p)
	skill = RtsHulls.STANDIN_SKILL


## Give `ship` (flown by a crew of `squad`) the squadron brain.
static func attach(world: World, ship: Ship, squad: Squad) -> SquadronBrain:
	var ai := SquadronBrain.new(world, ship.profile)
	ai.sq = squad
	ai._reset_after_launch()
	ai.route_goal = Vector2.INF
	ship.controls.assist = true
	ship.controller = ai
	return ai


## The squadron record this ship belongs to (found again after a merge moved the ship to another record).
var sq: Squad = null


## Does p fly a crew whose squadron stands under a Move, Hold or Stop order (new brain) or a Move or Hold order
## (stand-in)? Then the ship does not step away from a turret that hunts it. False for a pilot, for a crew with no
## order and for an Attack or Retreat order.
static func holds_position(w: World, p: PilotProfile) -> bool:
	if p == null or not p.is_crew:
		return false
	var squad: Squad = w.squads.get(p.squad_id) as Squad
	if squad == null:
		return false
	if squad.brain == SquadronRules.BRAIN_SQUAD:
		return SquadronThink.stands_firm(squad)
	return Standin.holds_position(w, p)


## Every tick while flying (the ship calls it through its controller): think about itself now and then, steer on
## every second tick (every tick during a Bomber's torpedo run).
func update(ship: Ship, _dt: float) -> void:
	if sq == null or sq.id != profile.squad_id:
		sq = world.squads.get(profile.squad_id) as Squad
	if sq == null:
		return
	var tick := world.tick_count
	var thought := tick % SquadronRules.THINK_EVERY == ship.uid % SquadronRules.THINK_EVERY
	if thought:
		_think_ship(ship)
	if thought or (tick + ship.uid) % STEER_EVERY == 0 or run.phase != PilotRun.IDLE:
		orbit = _orbit_sign(tick, ship.uid)
		_steer(ship)


## The ship's own think: step away from a hunting turret (unless standing firm), note whether a rock lies across
## the line to its slot, and set the energy routing.
func _think_ship(ship: Ship) -> void:
	var hunter := senses.turret_targeting(ship)
	if hunter != null and ship.size_class < Rules.SIZE_LARGE and not holds_position(world, profile):
		evade_until = world.tick_count + 150
		evade_from = hunter.global_position
		evade_t = 2.5
	if sq.engine.has("mode"):
		var slot := SquadronThink.slot_of(world, sq, ship)
		var d := ship.global_position.distance_to(slot)
		rock_between = d > DIRECT_MAX or not world.asteroids.segment_hit(ship.global_position, slot, ship.radius + 8.0).is_empty()
	systems.set_energy_and_shields(ship)


## Every steer: step away from a turret, fly an Attack, or fight the squadron's target inside the leash, else fly to
## the slot (standing still while the squadron has just lost its target).
func _steer(ship: Ship) -> void:
	var e := sq.engine
	if not e.has("mode"):
		return
	_me_uid = ship.uid
	var c := ship.controls
	var tick := world.tick_count
	var mode := str(e["mode"])
	# The seconds of stepping away left, kept in the parent's own member so a check can read both brains alike.
	evade_t = maxf(0.0, float(evade_until - tick) / 60.0)
	if tick < evade_until:
		var away := (ship.global_position - evade_from).normalized()
		goal = evade_from + away * 2600.0
		target = null
		lock_target = null
		intent = ""
		state = "lane"
		combat.steer(ship)
		return
	var t: Unit = null
	var tu := int(e.get("target", 0))
	if tu != 0:
		t = world.orders.unit_by_uid(tu)
		if t != null and (not is_instance_valid(t) or not t.alive):
			t = null
	if mode == "attack" and t != null:
		target = t
		lock_target = t
		intent = "push"
		state = "lane"
		goal = PilotTargeting.standoff(ship, t, ship.global_position)
		combat.steer(ship)
		return
	spacing_s = float(e.get("spacing", 110.0))
	jungle = bool(e.get("jungle", false))
	var slot := SquadronThink.slot_of(world, sq, ship)
	# The big ships' fight code holds its station on the brain's goal: the slot.
	goal = slot
	intent = ""
	var fighting := false
	if t != null:
		target = t
		lock_target = t
		fighting = not combat.target_far(ship)
		if fighting:
			var lp: Vector2 = slot if str(e.get("leash", "slot")) == "slot" else (e.get("leash_at", slot) as Vector2)
			if ship.global_position.distance_to(lp) > float(e.get("chase", SquadronRules.HOLD_CHASE)):
				fighting = false
		if not fighting:
			target = null
			lock_target = null
	else:
		target = null
		lock_target = null
	c.fire = false
	c.boost = false
	c.special = false
	if fighting:
		combat.fight(ship)
	else:
		if run.phase != PilotRun.IDLE:
			run.abandon()
		if t == null and int(e.get("idle_t", SquadronRules.RESUME_TICKS)) < SquadronRules.RESUME_TICKS and bool(e.get("anchored", false)):
			# A fight just ended: stand still for a moment before going back to the slot.
			var sticks := SquadEngine.stick_values(Vector2.ZERO, ship.velocity, ship.rotation)
			c.forward = sticks.x
			c.strafe = sticks.y
			c.aim_point = c.face_point
		else:
			_fly_to(ship, slot)
			if ship.uid == int(e.get("guide", -1)) and bool(e.get("catching", false)) and mode != "escort":
				c.forward = minf(c.forward, SquadronRules.CATCH_THROTTLE)
				c.boost = false
	if ship.run_mount != null:
		run.settle(ship)


## Fly to `slot` with no target. Past a rock it is the wingman's route flying; otherwise the wingman's velocity rule with one change: the
## speed that closes on the slot is held to what the ship's own brakes can stop in the distance left (a heavy hull with weak brakes
## overshot the slot and swung round it without that).
func _fly_to(ship: Ship, slot: Vector2) -> void:
	if rock_between:
		super(ship, slot)
		return
	var c := ship.controls
	var p := ship.global_position
	var d := p.distance_to(slot)
	route_goal = Vector2.INF
	if path_goal != Vector2.INF:
		path = PackedVector2Array()
		path_goal = Vector2.INF
	var vel := _place_velocity()
	var brake := minf(ship.f_reverse, ship.f_strafe)
	if brake <= 0.0:
		brake = ship.f_accel
	var close := (slot - p) * SquadEngine.SLOT_PULL
	close = close.limit_length(sqrt(2.0 * BRAKE_SHARE * brake * d))
	var wanted := (vel + close).limit_length(ship.f_max)
	var sticks := SquadEngine.stick_values(wanted, ship.velocity, ship.rotation)
	c.forward = sticks.x
	c.strafe = sticks.y
	if wanted.length() > 20.0:
		c.face_point = p + wanted.normalized() * 400.0
	else:
		c.face_point = p + Vector2.from_angle(_place_heading()) * 400.0
	c.aim_point = c.face_point
	var open_here := world.map.in_open_lane(p)
	var open_slot := world.map.in_open_lane(slot)
	c.boost = SquadEngine.may_boost(d, spacing_s, open_here, open_slot) and not jungle and ship.can_boost and ship.energy.fraction() > BOOST_ENERGY
	flight.avoid_rocks(ship)


## The velocity the place itself moves with: the charge's in an escort, the guide's for a follower on the move,
## none for the guide, for ships holding slots round an anchor and for a Stop.
func _place_velocity() -> Vector2:
	var e := sq.engine
	var mode := str(e.get("mode", "idle"))
	if mode == "escort":
		var charge := world.orders.unit_by_uid(int(e.get("charge", 0)))
		return charge.velocity if charge != null else Vector2.ZERO
	if mode == "stop" or mode == "attack" or bool(e.get("anchored", false)) or _me_uid == int(e.get("guide", -1)):
		return Vector2.ZERO
	var g: Variant = world.by_uid.get(int(e.get("guide", -1)))
	if g != null and is_instance_valid(g) and (g as Unit).alive:
		return (g as Unit).velocity
	return Vector2.ZERO


## The heading (radians) the squadron faces: the frozen heading round an anchor, the charge's in an escort,
## else the guide's.
func _place_heading() -> float:
	var e := sq.engine
	if str(e.get("mode", "idle")) == "escort":
		var charge := world.orders.unit_by_uid(int(e.get("charge", 0)))
		return charge.rotation if charge != null else 0.0
	if bool(e.get("anchored", false)):
		return deg_to_rad(float(e.get("heading", 0.0)))
	var g: Variant = world.by_uid.get(int(e.get("guide", -1)))
	if g != null and is_instance_valid(g) and (g as Unit).alive:
		return (g as Unit).rotation
	return 0.0
