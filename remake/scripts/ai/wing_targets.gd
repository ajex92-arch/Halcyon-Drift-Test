class_name WingTargets
extends RefCounted
## WHAT THIS IS: the wingmen's eyes. It answers "what should this wingman shoot?" for each order the
## wing can be under: the fire setting decides how freely a wingman fights (at will, only the ones
## that shot at us, or not at all), and the order decides where it looks (around its place, around
## the leader for "Cover me", around the ward for a guard).
##
## HOW IT WORKS: static functions, nothing kept. attackers() finds the nearest visible enemy that
## hurt one of a list of units in the last six seconds (every unit remembers who hurt it: its
## damage log). around() finds the nearest visible enemy ship or minion to a point. pick() puts
## the fire setting on top: "at will" uses the AI pilots' own target choice (PilotTargeting, which
## measures from the ship), "return fire" uses attackers(), "hold fire" gives nobody.
##
## WHO USES IT: WingmanAI (its think).

## Words used here: an "enemy" is a unit of the other team that the wingman's team can see.


## The nearest visible enemy to point `from` that hurt any unit in `sources` in the last
## SquadEngine.RETURN_FIRE_SECS seconds (the units' damage logs hold who and when), or null.
static func attackers(w: World, team: int, sources: Array, from: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for src: Variant in sources:
		if src == null or not is_instance_valid(src):
			continue
		for uid: Variant in (src as Unit).damage_log:
			var entry: Array = (src as Unit).damage_log[uid]
			if w.time - float(entry[1]) > SquadEngine.RETURN_FIRE_SECS:
				continue
			var u: Variant = w.by_uid.get(uid)
			if u == null or not is_instance_valid(u) or not _is_enemy(u as Unit, team):
				continue
			var d := from.distance_to((u as Unit).global_position)
			if d < best_d:
				best_d = d
				best = u as Unit
	return best


## The nearest visible enemy ship or minion within `radius` of `center`, or null. `scratch` is a
## list the spatial hash may fill (the caller keeps it, so nothing is made each time).
static func around(w: World, team: int, center: Vector2, radius: float, scratch: Array) -> Unit:
	var best: Unit = null
	var best_d := radius
	for u: Unit in w.unit_hash.query(center, radius, scratch):
		if not _is_enemy(u, team) or (u.kind != Unit.K_SHIP and u.kind != Unit.K_MINION):
			continue
		var d := center.distance_to(u.global_position)
		if d <= best_d:
			best_d = d
			best = u
	return best


## The fire setting applied to a free choice of target. `fire` is the wing's fire stance (0 at will, 1
## return fire, 2 hold fire); `radius` how far from the ship the AI pilots' own choice looks;
## `sources` the units whose attackers count for "return fire"; `scratch` as above. Null when
## nothing qualifies.
static func pick(brain: WingmanAI, ship: Ship, fire: int, radius: float, sources: Array) -> Unit:
	match fire:
		2:
			return null
		1:
			return attackers(brain.world, ship.team, sources, ship.global_position)
	return brain.targeting.pick_target(ship, radius)


## Is unit `u` alive, of the other team than `team` (not neutral), and visible to `team`?
static func _is_enemy(u: Unit, team: int) -> bool:
	return u.alive and u.team == Rules.enemy_of(team) and u.visible_to(team)
