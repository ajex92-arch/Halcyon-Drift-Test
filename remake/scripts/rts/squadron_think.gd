class_name SquadronThink
extends RefCounted
## WHAT THIS IS: the thinking of a bought squadron, one think for the whole squadron (not one per ship). It
## reads what the squadron was told (a one-off order, else its goal, else nothing) and works out the three
## things its ships need: the anchor (the one point or ship the squadron belongs to), the one target to fight
## (at most one pick per think) and the facts for the strip (the state). The ships' brains (SquadronBrain) only
## fly what this writes.
##
## HOW IT WORKS: Production calls tick_team() every tick for its own team; a squadron whose brain value is
## "squad" thinks every SquadronRules.THINK_EVERY ticks (staggered by its id), and at once on the tick after a new
## order, goal, stance or formation. A think writes its plan into the record's `engine` notes (not hashed, no
## dice): "mode" (idle, move, hold, stop, attack, defend, escort or push), "anchor", "anchored" (the ships hold
## slots round the anchor; else the guide, the first living ship, flies to it and the others fly slots round the
## guide), "heading" (degrees, for the slots), "target" (a unit id or 0), "leash" ("slot" or "point"), "leash_at",
## "chase", "charge" and "pocket" (an escort), "stand_firm", "catching" and "idle_t" (ticks with no target).
## The jobs: a standing one-off order (Move, Hold, Stop, Attack) wins over the goal; Hold keeps the goal but
## pauses it while it stands; a Move or an Attack that has run and ended gives the squadron back to its goal
## (an Attack with no goal turns into a Stop, as the stand-in did). Goals: Defend (a point, a unit or a lane),
## Escort (any friendly ship) and Push lane. A goal that cannot be reached (the guide gains under 300 on the
## anchor in 600 ticks) is held where the guide is, one "squadron_blocked" event is filed and it is tried
## again every 1,800 ticks; the goal is kept. An escort whose charge is gone holds its last spot and goes idle;
## one more than 6,000 units from its charge for 1,200 ticks ends its goal where it stands.
##
## WHO USES IT: Production (tick_team, once a tick per team), SquadronBrain (slot_of, stand_firm facts) and
## tests/squad_check.gd.

## The list the spatial hash fills while a target is looked for (kept so none is made each time).
static var _scratch: Array = []


## Think for every due squadron of `team` whose brain value is "squad", in record-id order.
static func tick_team(w: World, team: int) -> void:
	var ids: Array = []
	for id: Variant in w.squads:
		var rec: Squad = w.squads[id]
		if rec.team == team and rec.brain == SquadronRules.BRAIN_SQUAD:
			ids.append(int(id))
	if ids.is_empty():
		return
	ids.sort()
	for id: int in ids:
		var rec: Squad = w.squads[id]
		if _due(w, rec):
			think(w, rec)


## Is squadron `rec` due to think now (its turn in the staggered cycle, or something changed since its last think)?
static func _due(w: World, rec: Squad) -> bool:
	if w.tick_count % SquadronRules.THINK_EVERY == rec.id % SquadronRules.THINK_EVERY:
		return true
	var e := rec.engine
	return int(rec.order.get("tick", -1)) != int(e.get("seen_order", -2)) or int(rec.goal.get("tick", -1)) != int(e.get("seen_goal", -2)) \
		or rec.fire_stance != int(e.get("seen_fire", -1)) or rec.move_stance != int(e.get("seen_move", -1)) or rec.formation != int(e.get("seen_form", -1))


## The living ships of `rec`, in member order (the first is the guide).
static func live_ships(w: World, rec: Squad) -> Array[Ship]:
	var out: Array[Ship] = []
	for uid: int in rec.member_uids:
		var u: Variant = w.by_uid.get(uid)
		if u != null and is_instance_valid(u) and (u as Unit).alive and u is Ship:
			out.append(u as Ship)
	return out


## The point of an order target `t` (a Vector2i for a human, a Vector2 for the computer).
static func point_of(t: Variant) -> Vector2:
	if t is Vector2 or t is Vector2i:
		return Vector2(t)
	return Vector2.ZERO


## Does squadron `rec` stand under a one-off order that makes its ships stand firm under turret fire (Move, Hold or Stop)?
static func stands_firm(rec: Squad) -> bool:
	var kind := str(rec.order.get("kind", ""))
	return kind == OrderKinds.MOVE or kind == OrderKinds.HOLD or kind == OrderKinds.STOP


## One think of squadron `rec` (see the top). Writes the plan into rec.engine and the state into rec.state.
static func think(w: World, rec: Squad) -> void:
	var e := rec.engine
	var tick := w.tick_count
	var changed := int(rec.order.get("tick", -1)) != int(e.get("seen_order", -2)) or int(rec.goal.get("tick", -1)) != int(e.get("seen_goal", -2))
	e["seen_order"] = int(rec.order.get("tick", -1))
	e["seen_goal"] = int(rec.goal.get("tick", -1))
	e["seen_fire"] = rec.fire_stance
	e["seen_move"] = rec.move_stance
	e["seen_form"] = rec.formation
	var ships := live_ships(w, rec)
	if ships.is_empty():
		# No ship yet (the record of a build that has not arrived is "launching") or none left: the state is left as it is.
		e["target"] = 0
		e["mode"] = "idle"
		return
	var guide: Ship = ships[0]
	var uids: Array = []
	for s: Ship in ships:
		uids.append(s.uid)
	e["uids"] = uids
	e["guide"] = guide.uid
	var reach := PilotTargeting.main_reach(guide)
	e["reach"] = reach
	var sp := SquadEngine.spacing(guide.radius)
	e["spacing"] = sp
	var jungle := SquadEngine.in_jungle(w, guide.global_position)
	e["jungle"] = jungle
	e["shape"] = SquadEngine.effective_formation(rec.formation, jungle)
	if changed:
		# A new order or goal: go at once, and judge the way again.
		e["idle_t"] = SquadronRules.RESUME_TICKS
		e.erase("prog_t")
		e.erase("blocked_until")
		e["anchored"] = false
	_end_finished_order(w, rec, guide)
	var j := _resolve(w, rec, guide)
	var mode := str(j["mode"])
	var anchor: Vector2 = j["anchor"]
	var stance := int(j["stance"])
	# The arrived mark: the guide close to its anchor, the ships hold slots round it.
	var anchored := false
	var blocked := false
	if mode == "escort" or mode == "attack" or mode == "stop":
		e["anchored"] = false
	else:
		anchored = bool(e.get("anchored", false))
		var d := guide.global_position.distance_to(anchor)
		# Unreachable: no gain on the anchor for BLOCKED_TICKS ticks. A held goal is tried again when its time is up.
		if e.has("blocked_until") and tick >= int(e["blocked_until"]):
			e.erase("blocked_until")
			e.erase("prog_t")
		if tick < int(e.get("blocked_until", -1)):
			blocked = true
			anchor = e.get("blocked_at", guide.global_position)
			anchored = true
		elif d > SquadronRules.ANCHOR_NEAR and int(e.get("target", 0)) == 0:
			if not e.has("prog_t") or (e.get("prog_anchor", Vector2.INF) as Vector2).distance_to(anchor) > 600.0:
				e["prog_t"] = tick
				e["prog_d"] = d
				e["prog_anchor"] = anchor
			elif tick - int(e["prog_t"]) >= SquadronRules.BLOCKED_TICKS:
				if float(e["prog_d"]) - d < SquadronRules.BLOCKED_GAIN:
					e["blocked_until"] = tick + SquadronRules.RETRY_TICKS
					e["blocked_at"] = guide.global_position
					_file_blocked(w, rec, guide)
					blocked = true
					anchor = guide.global_position
					anchored = true
				e["prog_t"] = tick
				e["prog_d"] = d
		else:
			e.erase("prog_t")
		if not blocked:
			var d2 := guide.global_position.distance_to(anchor)
			if anchored and d2 > SquadronRules.ANCHOR_FAR:
				anchored = false
			elif not anchored and d2 <= SquadronRules.ANCHOR_NEAR:
				anchored = true
				if float(j["heading"]) == INF:
					e["heading"] = rad_to_deg(SquadEngine.frame_heading(e, tick, guide.velocity, guide.rotation))
		e["anchored"] = anchored
	if float(j["heading"]) != INF:
		e["heading"] = float(j["heading"])
	elif not e.has("heading"):
		e["heading"] = rad_to_deg(guide.rotation)
	e["mode"] = mode
	e["anchor"] = anchor
	e["blocked"] = blocked
	e["charge"] = int(j["charge"])
	e["pocket"] = bool(j["pocket"])
	e["cone"] = float(j["cone"])
	e["stand_firm"] = stands_firm(rec)
	# The leash of the ships and where the squadron looks.
	var scan_at: Vector2 = anchor
	var radius := SquadronRules.scan_radius(stance, reach)
	var keep := SquadronRules.keep_limit(stance, reach)
	e["leash"] = "slot"
	e["chase"] = SquadronRules.HOLD_CHASE
	e["leash_at"] = anchor
	if mode == "escort":
		var charge := w.orders.unit_by_uid(int(j["charge"]))
		scan_at = charge.global_position if charge != null else anchor
		radius = SquadEngine.GUARD_ENGAGE if bool(j["pocket"]) else SquadEngine.COVER_RADIUS
		keep = SquadEngine.GUARD_LEASH if bool(j["pocket"]) else SquadEngine.COVER_LEASH
		e["leash"] = "point"
		e["chase"] = keep
		e["leash_at"] = scan_at
	elif mode == "attack":
		e["leash"] = "point"
		e["chase"] = INF
	elif mode == "stop":
		scan_at = guide.global_position if not e.has("stop_pts") else _stop_point(e, guide)
	elif not anchored:
		# On the way: shoot what is in gun reach of the place, chase no further than the hold leash.
		scan_at = guide.global_position
		radius = SquadronRules.scan_radius(0, reach)
		keep = SquadronRules.keep_limit(0, reach)
	elif stance != 0:
		e["leash"] = "point"
		e["chase"] = SquadronRules.chase_limit(stance, reach)
	# The one target.
	var target := _pick(w, rec, ships, j, scan_at, radius, keep)
	e["target"] = target.uid if target != null else 0
	if target == null:
		e["idle_t"] = mini(int(e.get("idle_t", SquadronRules.RESUME_TICKS)) + SquadronRules.THINK_EVERY, 100000)
	else:
		e["idle_t"] = 0
	# The facts for the strip.
	var catching := false
	var all_in := true
	for s: Ship in ships:
		var d3 := s.global_position.distance_to(slot_of(w, rec, s))
		if s != guide or mode == "escort":
			catching = catching or SquadEngine.catching_up(d3, sp)
		all_in = all_in and d3 <= SquadEngine.IN_SLOT * 2.0
	e["catching"] = catching
	if blocked:
		rec.state = 0
	elif target != null:
		rec.state = Squads.STATE_FIGHTING
	elif mode == "stop" or ((anchored or mode == "escort") and all_in):
		rec.state = Squads.STATE_IDLE
	else:
		rec.state = Squads.STATE_MOVING


## The captured stop place of the guide (Stop: each ship stands where it was when the order applied).
static func _stop_point(e: Dictionary, guide: Ship) -> Vector2:
	var pts: Dictionary = e["stop_pts"]
	var p: Variant = pts.get(guide.uid)
	return p as Vector2 if p is Vector2 else guide.global_position


## File the one "squadron blocked" event of a goal that cannot be reached.
static func _file_blocked(w: World, rec: Squad, guide: Ship) -> void:
	if w.events_rts == null:
		return
	w.events_rts.push({"kind": "squadron_blocked", "team": rec.team, "pos": RtsEvents.point_of(guide.global_position), "uid": 0, "data": {"squad": rec.id}})


## End a one-off order that has run its course: an Attack whose unit is gone, a Move that arrived (when a goal waits behind it).
## An Attack with no goal becomes a Stop where the ships stand (what the stand-in did); otherwise the order is cleared and the
## squadron goes back to its goal.
static func _end_finished_order(w: World, rec: Squad, guide: Ship) -> void:
	var e := rec.engine
	var kind := str(rec.order.get("kind", ""))
	if kind == OrderKinds.ATTACK:
		var u := w.orders.unit_by_uid(int(rec.order.get("target", 0)))
		if u == null or not u.alive:
			e["idle_spot"] = guide.global_position
			if rec.goal.is_empty():
				rec.order = {"kind": OrderKinds.STOP, "target_kind": "none", "target": 0, "tick": w.tick_count, "settings": {}}
			else:
				rec.order = {}
	elif kind == OrderKinds.MOVE and not rec.goal.is_empty():
		var p := point_of(rec.order.get("target"))
		if guide.global_position.distance_to(p) <= SquadronRules.MOVE_END and int(e.get("idle_t", SquadronRules.RESUME_TICKS)) >= SquadronRules.RESUME_TICKS:
			e["idle_spot"] = p
			rec.order = {}


## What the squadron is doing now: a Dictionary with "mode", "anchor", "stance" (the move stance to use), "heading" (degrees, or
## INF for none), "charge", "pocket" and "cone" (an escort). May end a goal (an escort that lost its charge or its straggler time).
static func _resolve(w: World, rec: Squad, guide: Ship) -> Dictionary:
	var e := rec.engine
	var team := rec.team
	var tick := w.tick_count
	var j := {"mode": "idle", "anchor": Vector2.ZERO, "stance": rec.move_stance, "heading": INF, "charge": 0, "pocket": false, "cone": 70.0}
	var kind := str(rec.order.get("kind", ""))
	match kind:
		OrderKinds.MOVE:
			j["mode"] = "move"
			j["anchor"] = point_of(rec.order.get("target"))
			return j
		OrderKinds.HOLD:
			j["mode"] = "hold"
			j["anchor"] = point_of(rec.order.get("target"))
			j["stance"] = 0
			var st: Dictionary = rec.order.get("settings", {})
			if st.has("heading"):
				j["heading"] = float(int(st["heading"]))
			return j
		OrderKinds.STOP:
			j["mode"] = "stop"
			j["stance"] = 0
			if int(e.get("stop_tick", -1)) != int(rec.order.get("tick", -1)) or not e.has("stop_pts"):
				var pts := {}
				for s: Ship in live_ships(w, rec):
					pts[s.uid] = s.global_position
				e["stop_pts"] = pts
				e["stop_tick"] = int(rec.order.get("tick", -1))
			j["anchor"] = _stop_point(e, guide)
			return j
		OrderKinds.ATTACK:
			var u := w.orders.unit_by_uid(int(rec.order.get("target", 0)))
			j["mode"] = "attack"
			j["anchor"] = u.global_position if u != null else guide.global_position
			j["charge"] = int(rec.order.get("target", 0))
			return j
	var spot: Vector2 = e.get("idle_spot", Vector2(rec.rally))
	var gk := str(rec.goal.get("kind", ""))
	var tk := str(rec.goal.get("target_kind", ""))
	var gt: Variant = rec.goal.get("target")
	if gk == OrderKinds.DEFEND:
		var anchor := spot
		if tk == "point":
			anchor = point_of(gt)
		elif tk == "unit":
			var du := w.orders.unit_by_uid(int(gt))
			if du != null and du.alive:
				e["defend_last"] = du.global_position
			anchor = e.get("defend_last", spot)
		elif tk == "lane":
			anchor = GoalPoints.lane_anchor(w, team, str(gt))
		j["mode"] = "defend"
		j["anchor"] = anchor
		var ms := w.mothership(team)
		if ms != null and ms.global_position.distance_to(anchor) > 1.0:
			j["heading"] = rad_to_deg((anchor - ms.global_position).angle())
		return j
	if gk == OrderKinds.ESCORT:
		var charge := w.orders.unit_by_uid(int(gt))
		if charge == null or not charge.alive or charge.team != team:
			# The charge died or docked: hold its last spot, then the idle rule.
			spot = e.get("charge_last", guide.global_position)
			e["idle_spot"] = spot
			e["idle_t"] = SquadronRules.RESUME_TICKS
			rec.goal = {}
		else:
			e["charge_last"] = charge.global_position
			var st_t := SquadEngine.straggler_ticks(int(e.get("strag", 0)), guide.global_position.distance_to(charge.global_position), SquadronRules.THINK_EVERY)
			e["strag"] = st_t
			if SquadEngine.is_straggler(st_t):
				# Too far behind for too long: the goal ends where the squadron is.
				e.erase("strag")
				e["idle_spot"] = guide.global_position
				e["idle_t"] = SquadronRules.RESUME_TICKS
				spot = guide.global_position
				rec.goal = {}
			else:
				j["mode"] = "escort"
				j["anchor"] = charge.global_position
				j["charge"] = charge.uid
				var big := SquadOrders.is_ward(charge, team)
				j["pocket"] = big
				if charge is Ship:
					j["cone"] = SquadEngine.guard_cone(Ships.get_def((charge as Ship).hull_id))
				return j
	elif gk == OrderKinds.PUSH_LANE:
		var lane := str(gt)
		if not e.has("push_at") or tick - int(e.get("push_t", -100000)) >= SquadronRules.PUSH_EVERY or str(e.get("push_lane", "")) != lane:
			e["push_at"] = GoalPoints.push_point(w, team, lane)
			e["push_t"] = tick
			e["push_lane"] = lane
		j["mode"] = "push"
		j["anchor"] = e["push_at"]
		return j
	j["anchor"] = spot
	return j


## Where ship `ship` of squadron `rec` should be: its slot in the plan the last think wrote (see the top). Stop: where the ship
## stood; Attack: where it is; Escort: round the charge (the guard pocket for a big charge); anchored: the frozen shape round
## the anchor; else the guide's slot is the anchor and the others fly the shape round the guide.
static func slot_of(w: World, rec: Squad, ship: Ship) -> Vector2:
	var e := rec.engine
	var mode := str(e.get("mode", "idle"))
	var uids: Array = e.get("uids", [])
	var idx := maxi(uids.find(ship.uid), 0)
	var sp := float(e.get("spacing", 110.0))
	var shape := int(e.get("shape", 0))
	var anchor: Vector2 = e.get("anchor", ship.global_position)
	if mode == "stop":
		var pts: Dictionary = e.get("stop_pts", {})
		var p: Variant = pts.get(ship.uid)
		return p as Vector2 if p is Vector2 else ship.global_position
	if mode == "attack":
		return ship.global_position
	if mode == "escort":
		var charge := w.orders.unit_by_uid(int(e.get("charge", 0)))
		if charge == null:
			return anchor
		if bool(e.get("pocket", false)):
			if charge is Mothership:
				var ms := charge as Mothership
				return SquadEngine.mothership_slot(ms.global_position, ms.rotation, ms.half_len, ms.beam, idx)
			return SquadEngine.guard_slot(charge.global_position, charge.rotation, charge.radius, float(e.get("cone", 70.0)), idx)
		var hc := SquadEngine.frame_heading(e, w.tick_count, charge.velocity, charge.rotation)
		return SquadEngine.slot_target(charge.global_position, charge.velocity, hc, shape, idx, sp)
	if bool(e.get("anchored", false)):
		return SquadEngine.hold_slot(anchor, float(e.get("heading", 0.0)), shape, idx, sp)
	var guide_uid := int(e.get("guide", -1))
	if ship.uid == guide_uid:
		return anchor
	var gu: Variant = w.by_uid.get(guide_uid)
	if gu == null or not is_instance_valid(gu) or not (gu as Unit).alive:
		return anchor
	var g := gu as Ship
	var hg := SquadEngine.frame_heading(e, w.tick_count, g.velocity, g.rotation)
	return SquadEngine.slot_target(g.global_position, g.velocity, hg, shape, maxi(idx - 1, 0), sp)


## The one target of this think: the order's unit for an Attack; else the target kept from the last think while it is
## still alive, seen and within `keep` of `scan_at`; else a new pick within `radius` of `scan_at` as the fire stance allows
## (at will: the nearest enemy; return fire: whoever hurt a member or the charge lately; hold fire: nobody). Null for none.
static func _pick(w: World, rec: Squad, ships: Array[Ship], j: Dictionary, scan_at: Vector2, radius: float, keep: float) -> Unit:
	var team := rec.team
	var e := rec.engine
	if str(j["mode"]) == "attack":
		var u := w.orders.unit_by_uid(int(j["charge"]))
		return u
	var cur := w.orders.unit_by_uid(int(e.get("target", 0)))
	if cur != null and cur.alive and cur.team == Rules.enemy_of(team) and cur.visible_to(team) and scan_at.distance_to(cur.global_position) <= keep:
		return cur
	var fire := rec.fire_stance
	if fire == 2:
		return null
	var sources: Array = []
	for s: Ship in ships:
		sources.append(s)
	var charge: Unit = null
	if str(j["mode"]) == "escort":
		charge = w.orders.unit_by_uid(int(j["charge"]))
		if charge != null:
			sources = [charge] if bool(j["pocket"]) else sources + [charge]
	if str(j["mode"]) == "defend" and str(rec.goal.get("target_kind", "")) == "unit":
		var du := w.orders.unit_by_uid(int(rec.goal.get("target", 0)))
		if du != null and du.alive:
			var hurt := WingTargets.attackers(w, team, [du], scan_at)
			if hurt != null and scan_at.distance_to(hurt.global_position) <= keep:
				return hurt
	if fire == 1:
		var t1 := WingTargets.attackers(w, team, sources, scan_at)
		if t1 != null and scan_at.distance_to(t1.global_position) <= keep:
			return t1
		return null
	return nearest_enemy(w, team, scan_at, radius)

## The nearest visible enemy ship or minion within `radius` of `center`, or null. The spatial hash is filled once a tick, so a unit
## in it may have been freed since: each is checked before it is used.
static func nearest_enemy(w: World, team: int, center: Vector2, radius: float) -> Unit:
	var best: Unit = null
	var best_d := radius
	_scratch.clear()
	for u: Variant in w.unit_hash.query(center, radius, _scratch):
		if u == null or not is_instance_valid(u):
			continue
		var unit := u as Unit
		if not unit.alive or unit.team != Rules.enemy_of(team) or not unit.visible_to(team):
			continue
		if unit.kind != Unit.K_SHIP and unit.kind != Unit.K_MINION:
			continue
		var d := center.distance_to(unit.global_position)
		if d <= best_d:
			best_d = d
			best = unit
	return best
