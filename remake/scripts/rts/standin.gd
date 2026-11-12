class_name Standin
extends RefCounted
## WHAT THIS IS: the brain a bought ship flies on until the squad engine exists. It is the
## pilot brain (PilotAI) at a fixed skill, held to three habits: it stays where it was sent,
## it never goes shopping, and it never retreats or docks. So a bought squadron goes to its
## rally spot, sits there and fights whatever comes close.
##
## HOW IT WORKS: attach() gives a ship its own PilotAI at RtsHulls.STANDIN_SKILL with the
## hold point set to the squadron's rally spot, and remembers the brain in the team's
## Production (so keep_alive() can reach it). The pilot brain walks three habits out of its
## own rules, with no edit of its code:
##   - Hold: PilotAI pins its goal to `hold_point` last; the stand-in sets `hold_point` to the
##     point of the squadron's standing order (Move or Hold: the point; Stop: where the ship
##     is), else the rally.
##   - Never shops: the brain asks "have I just launched?" before shopping, so keep_alive()
##     (called by Production every tick) says "just launched" every tick.
##   - Never retreats: a hook in World.pilot_think_hooks (install() adds it once) runs after
##     the brain has chosen its job. For a crew's brain whose squad is not ordered to retreat,
##     "retreat" and "home" become "lane" again, its goal the hold point, and the dock control
##     is cleared (WorldHangar.try_dock refuses a crew anyway). The brain re-decides a retreat
##     at every think, so the hook runs at every think. One thing it cannot stop: a turret
##     hunting a small or medium ship makes the brain step away for 2.5 seconds, and then it
##     comes back.
##   - Attack: a squadron whose standing order is Attack makes the order's unit its target at
##     every think, wherever the unit is (the enemy mothership too, which the rule ms:nosmall
##     keeps the brain from picking by itself), and its goal the unit's gun-reach point
##     (PilotTargeting.standoff). When the unit is gone the squadron stops where it stands.
## The formation and the stances of the squadron record are ignored here; the record keeps
## them for the squad engine. The brain keeps its own few dice (its first think time and the
## way it circles a target), so the bought ships' matches have their own baselines.
##
## WHO USES IT: WorldSetup calls install(); Arrivals calls attach(); Production calls
## keep_alive() every tick; tests/crew_check.gd and tests/arrival_check.gd check it.

## Put the hook that keeps a crew's brain from retreating into the match's think hooks.
static func install(w: World) -> void:
	w.pilot_think_hooks.append(func(ship: Ship, brain: PilotAI) -> void: _think(w, ship, brain))


## Give `ship` (flown by a crew of `squad`) the stand-in brain.
static func attach(world: World, ship: Ship, squad: Squad) -> PilotAI:
	var ai := PilotAI.new(world, ship.profile)
	ai.skill = RtsHulls.STANDIN_SKILL
	ai.hold_point = Vector2(squad.rally)
	ai._reset_after_launch()
	ship.controller = ai
	world.teams[squad.team].production.standins.append(ai)
	return ai


## Say "just launched" on every living stand-in brain of team production `prod` (so none goes
## shopping) and forget the brains of ships that are gone. Production calls it every tick.
static func keep_alive(world: World, prod: Production) -> void:
	var i := prod.standins.size() - 1
	while i >= 0:
		var ai: PilotAI = prod.standins[i]
		if ai.profile == null or ai.profile.ship == null:
			prod.standins.remove_at(i)
		else:
			ai.launched_at = world.time
		i -= 1


## Where a crew of `squad` should hold: the point of its standing Move or Hold order, where
## the ship is for a Stop order, else the squadron's rally spot.
static func hold_point_of(squad: Squad, ship: Ship) -> Vector2:
	if squad == null:
		return ship.global_position
	var kind := str(squad.order.get("kind", ""))
	if kind == OrderKinds.STOP:
		return ship.global_position
	if kind == OrderKinds.MOVE or kind == OrderKinds.HOLD:
		var t: Variant = squad.order.get("target")
		if t is Vector2 or t is Vector2i:
			return Vector2(t)
	return Vector2(squad.rally)


## The think hook: for a crew's brain, keep the hold point and turn a retreat into the lane job
## (see the top).
static func _think(w: World, ship: Ship, brain: PilotAI) -> void:
	var p := brain.profile
	if p == null or not p.is_crew:
		return
	var squad: Squad = w.squads.get(p.squad_id) as Squad
	brain.hold_point = hold_point_of(squad, ship)
	if brain.state == "retreat" or brain.state == "home":
		if squad == null or str(squad.order.get("kind", "")) != OrderKinds.RETREAT:
			brain.state = "lane"
			brain.soft_retreat = false
			brain.goal = brain.hold_point
	ship.controls.dock = false
	if squad != null and str(squad.order.get("kind", "")) == OrderKinds.ATTACK:
		_attack(w, ship, brain, squad)


## A standing Attack order (see the top): the brain's target is the order's unit and its goal the unit's gun-reach point,
## as seen from the ship's own place. A unit that is gone turns the order into a Stop where the ship is. A unit the brain
## gave up on for a while (it stayed hidden behind rocks, PilotAI.skip_until) is left alone until the pause ends.
static func _attack(w: World, ship: Ship, brain: PilotAI, squad: Squad) -> void:
	var t := w.orders.unit_by_uid(int(squad.order.get("target", 0)))
	if t == null:
		squad.order = {"kind": OrderKinds.STOP, "target_kind": "none", "target": 0, "tick": w.tick_count, "settings": {}}
		brain.hold_point = ship.global_position
		return
	if brain.skip_id == t.get_instance_id() and w.time < brain.skip_until:
		return
	brain.target = t
	brain.lock_target = t
	brain.intent = "push"
	brain.goal = PilotTargeting.standoff(ship, t, ship.global_position)
