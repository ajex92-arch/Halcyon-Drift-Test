extends Node
## WHAT THIS IS: the check of the bought squadrons' jobs engine (RT12 part A): the new brain that flies a bought
## squadron (SquadronBrain, thought for by SquadronThink), the goals (Defend, Escort, Push lane), Stop and Hold,
## the stances, the merge and the Orders-page hookup. One group of cases for each item of the build.
##
## HOW IT WORKS: it runs in a small match (no waves, no computer pilots), buys squadrons for team 0 the way
## arrival_check does (Production.spawn_now), puts them where a case wants them and lets the world tick (the
## cases wait on the physics frames, one frame is one tick). Enemies of a case are bought for team 1 and made
## inert (no brain). The test names no class that this build added except through load() behind
## ResourceLoader.exists, so on the base commit it prints FAIL lines for those cases and never fails to parse
## (the probe depends on that). Cases that only use classes the base has are controls: they pass on the base too.
## Each case prints "squad_check: PASS <name>" or "squad_check: FAIL <name>: <what>"; the last lines are
## "squad_check: <n> checks, <k> failures" and, only when k is 0, "squad_check: 0 failures".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=squad_check
##
## WHO USES IT: main.gd loads it for --test=squad_check; the lead's check list runs it.

## One tick, in seconds.
const DT := 1.0 / 60.0

## The running match (set by setup()).
var world: World
## How many checks were made.
var checks := 0
## How many checks failed.
var fails := 0
## True once the cases have started.
var _started := false
## How many times the ship stepped away (its evade time went from nothing to something) in the last _turret_case.
var _turret_evades := 0
## The kind of the standing order of the squadron after the last _turret_case (the Standin hook rewrote a no-order crew to Stop).
var _turret_order_after := ""
## The inert enemies of the running case (their visibility is kept on every tick).
var _enemies: Array = []
## SquadronRules, loaded when this build has it (null on the base commit).
var R: Variant = null
## SquadronThink (null on the base commit).
var TH: Variant = null
## SquadronBrain (null on the base commit).
var BR: Variant = null
## GoalPoints (null on the base commit).
var GP: Variant = null


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	R = _cls("rts/squadron_rules")
	TH = _cls("rts/squadron_think")
	BR = _cls("ai/squadron_brain")
	GP = _cls("rts/goal_points")


## The script of scripts/<name>.gd when this build has it, else null.
func _cls(name: String) -> Variant:
	var path := "res://scripts/%s.gd" % name
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Run every group in the first frame (the groups wait on the physics frames themselves).
func _physics_process(_dt: float) -> void:
	if _started or world == null:
		return
	_started = true
	_run()


## Every group, then the result.
func _run() -> void:
	await _cases_item1()
	await _cases_item2()
	await _cases_tables()
	await _cases_item3()
	await _cases_item4()
	await _cases_item5()
	await _cases_position()
	_reset()
	print("squad_check: %d checks, %d failures" % [checks, fails])
	if fails == 0:
		print("squad_check: 0 failures")
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------

## Print one PASS or FAIL line for the case `name`.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("squad_check: PASS %s" % name)
	else:
		fails += 1
		print("squad_check: FAIL %s: %s" % [name, detail])


## Is the new engine in this build (else its cases fail with that reason)?
func _built() -> bool:
	return R != null and TH != null and BR != null


## Has unit `u` been destroyed or hurt (hull and shields under 95 percent)?
func _hurt(u: Variant) -> bool:
	return not is_instance_valid(u) or not (u as Unit).alive or (u as Unit).total_frac() < 0.95


## The hull and shield percent of unit `u` (0 for a destroyed one).
func _pct(u: Variant) -> int:
	return 0 if (not is_instance_valid(u) or not (u as Unit).alive) else int((u as Unit).total_frac() * 100.0)


## Let `n` ticks pass (the enemies stay visible).
func _ticks(n: int) -> void:
	for i in n:
		for e: Variant in _enemies:
			if is_instance_valid(e):
				(e as Ship).visible_mask |= 1
		await get_tree().physics_frame


## Team `t`'s production.
func _prod(t: int) -> Production:
	return world.teams[t].production


## Take every bought ship out quietly and clear the records, so a case starts empty (as arrival_check does).
func _reset() -> void:
	for s: Ship in world.ships.duplicate():
		if s.profile != null and s.profile.is_crew:
			world.combat.kill_silently(s)
	for t in 2:
		var p := _prod(t)
		p.items.clear()
		p.repeat.clear()
		p.fx.clear()
		p.standins.clear()
		p.capacity.reserved = 0
		p._cap_blocked = false
	for id: int in world.squads.keys():
		world.squads.erase(id)
	_enemies.clear()
	for t in 2:
		world.teams[t].treasury = 0.0
		world.teams[t].admiral = "ai"


## Buy `count` ships of `hull` for team `team` now, stand them round `at` (a line, 150 apart), at rest, and return the record.
func _spawn(team: int, hull: String, count: int, at: Vector2) -> Squad:
	var it := _prod(team).spawn_now(hull, count)
	var sq: Squad = world.squads.get(int(it["squad"])) as Squad
	var ships := _ships(sq)
	for i in ships.size():
		var s := ships[i]
		s.global_position = at + Vector2(0.0, float(i - 1) * 150.0)
		s.velocity = Vector2.ZERO
		s.rotation = 0.0
	sq.rally = Vector2i(at)
	return sq


## The living ships of record `sq`, in member order.
func _ships(sq: Squad) -> Array[Ship]:
	var out: Array[Ship] = []
	for uid: int in sq.member_uids:
		var u: Variant = world.by_uid.get(uid)
		if u != null and is_instance_valid(u) and (u as Unit).alive:
			out.append(u as Ship)
	return out


## An inert enemy ship (team 1, no brain, always seen by team 0) of `hull` at `at`.
func _enemy(at: Vector2, hull: String = "fighter") -> Ship:
	var it := _prod(1).spawn_now(hull, 1)
	var sq: Squad = world.squads.get(int(it["squad"])) as Squad
	var s := _ships(sq)[0]
	s.controller = null
	s.global_position = at
	s.velocity = Vector2.ZERO
	s.visible_mask |= 1
	_enemies.append(s)
	return s


## Send an order from the Admiral's seat of team 0 and let it apply. Returns the refusal text ("" for none).
func _order(kind: String, ids: Array, target_kind: String = "none", target: Variant = 0, settings: Dictionary = {}) -> String:
	var r := world.orders.submit(Order.make(kind, 0, Rules.ADMIRAL_SEAT, true, settings, ids, target_kind, target))
	await _ticks(2)
	return r


## The largest distance of any ship of `sq` from `p`.
func _far_from(sq: Squad, p: Vector2) -> float:
	var far := 0.0
	for s in _ships(sq):
		far = maxf(far, s.global_position.distance_to(p))
	return far


## The fastest speed of any ship of `sq`.
func _top_speed(sq: Squad) -> float:
	var top := 0.0
	for s in _ships(sq):
		top = maxf(top, s.velocity.length())
	return top


## The mothership of team 0.
func _ms0() -> Vector2:
	return world.mothership(0).global_position


## A clear starting place on the mid lane and a point 6,000 units east of it.
func _lane_start() -> Vector2:
	return Vector2(8000.0, 15600.0)


## Run a Move of a fresh squadron of three fighters over 6,000 units; returns the tick the ships were settled
## (all within 450 of the point and slower than 50), or -1 within `limit` ticks. `squad_brain` picks the brain.
func _move_settle(squad_brain: bool, limit: int) -> int:
	_reset()
	if R != null:
		R.set_switch(squad_brain)
	var start := _lane_start()
	var goal := start + Vector2(6000.0, 0.0)
	var sq := _spawn(0, "fighter", 3, start)
	await _ticks(5)
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(goal))
	var settled := -1
	for k in limit:
		await _ticks(1)
		if _far_from(sq, goal) <= 450.0 and _top_speed(sq) < 50.0:
			settled = k + 2
			break
	if R != null:
		R.set_switch(true)
	return settled


# --- item 1: the new brain -----------------------------------------------------------

## Move, Hold, Stop and Attack reach their end states (controls: the stand-in does them too), the switch, the settle time against the
## stand-in, three routes, the stand-firm rule, the idle rule, the leashes and the fire stances.
func _cases_item1() -> void:
	# The four end states.
	_reset()
	var start := _lane_start()
	var goal := start + Vector2(4000.0, 0.0)
	var sq := _spawn(0, "fighter", 3, start)
	await _ticks(5)
	var r := await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(goal))
	await _ticks(1500)
	_check("item1 end state: Move reaches its point", r == "" and _far_from(sq, goal) <= 450.0 and _top_speed(sq) < 60.0, "refusal '%s', farthest ship %d, top speed %d" % [r, int(_far_from(sq, goal)), int(_top_speed(sq))])
	_reset()
	sq = _spawn(0, "fighter", 3, start)
	await _ticks(5)
	r = await _order(OrderKinds.HOLD, [sq.id], "point", Vector2i(goal))
	await _ticks(1500)
	_check("item1 end state: Hold reaches its point", r == "" and _far_from(sq, goal) <= 450.0 and _top_speed(sq) < 60.0, "refusal '%s', farthest ship %d" % [r, int(_far_from(sq, goal))])
	_reset()
	sq = _spawn(0, "fighter", 3, start)
	await _ticks(5)
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(goal))
	await _ticks(60)
	r = await _order(OrderKinds.STOP, [sq.id])
	var stopped_at := _ships(sq)[0].global_position
	await _ticks(600)
	var drift := _ships(sq)[0].global_position.distance_to(stopped_at)
	_check("item1 end state: Stop stands where the squadron is", r == "" and drift <= 700.0 and _top_speed(sq) < 60.0 and _far_from(sq, goal) > 1500.0, "refusal '%s', drift %d" % [r, int(drift)])
	_reset()
	sq = _spawn(0, "fighter", 3, start)
	var foe := _enemy(start + Vector2(3000.0, 0.0), "logistics")
	await _ticks(5)
	r = await _order(OrderKinds.ATTACK, [sq.id], "unit", foe.uid)
	await _ticks(1500)
	_check("item1 end state: Attack goes for its unit and hurts it", r == "" and _hurt(foe), "refusal '%s', foe at %d" % [r, _pct(foe)])
	# The stand-firm rule (a control for Move and Hold; the Stop part is the build's).
	var hold_far := await _turret_case(OrderKinds.HOLD)
	var hold_ev := _turret_evades
	var move_far := await _turret_case(OrderKinds.MOVE)
	var move_ev := _turret_evades
	var none_far := await _turret_case("")
	var none_ev := _turret_evades
	var none_order := _turret_order_after
	var stop_far := await _turret_case(OrderKinds.STOP)
	var stop_ev := _turret_evades
	_check("item1 stand firm: a Move or a Hold squadron does not step away from a hunting turret and a no-order one does",
		hold_far >= 0.0 and move_far >= 0.0 and none_far >= 0.0 and hold_ev == 0 and move_ev == 0 and none_ev >= 1,
		"evade cycles: hold %d, move %d, none %d" % [hold_ev, move_ev, none_ev])
	_check("item1 stand firm: a held or moved ship stays within 700 of its point under fire", hold_far >= 0.0 and hold_far <= 700.0 and move_far <= 700.0, "hold %d, move %d (none %d)" % [int(hold_far), int(move_far), int(none_far)])
	_check("item1 stand firm: a squadron under turret fire steps away and is not rewritten to Stop (the stand-in's think hook never runs for the new brain)", _built() and none_ev >= 1 and none_order == "", "evades %d, order kind '%s'" % [none_ev, none_order])
	_check("item1 stand firm: a Stop squadron does not step away either (new brain)", _built() and stop_far >= 0.0 and stop_ev == 0, "stop: evade cycles %d, far %d" % [stop_ev, int(stop_far)])
	# The switch and the brain value.
	_reset()
	var yard := _prod(0).spawn_now("fighter", 3)
	var ysq: Squad = world.squads.get(int(yard["squad"])) as Squad
	_check("item1 switch: the yard writes the squad brain and the ships fly it", _built() and R.switch_on() and ysq.brain == "squad" and _ships(ysq)[0].controller != null and _ships(ysq)[0].controller.get_script() == BR, "brain '%s'" % ysq.brain)
	if _built():
		R.set_switch(false)
		_reset()
		var old := _prod(0).spawn_now("fighter", 1)
		var osq: Squad = world.squads.get(int(old["squad"])) as Squad
		_check("item1 switch: with the switch off the old stand-in runs (brain 'standin', a pilot brain at skill 0.77)", osq.brain == "standin" and (_ships(osq)[0].controller as PilotAI).skill == RtsHulls.STANDIN_SKILL, "brain '%s'" % osq.brain)
		R.set_switch(true)
	else:
		_check("item1 switch: with the switch off the old stand-in runs", false, "SquadronRules is not in this build")
	# The settle time against the stand-in on the same 6,000-unit move.
	var t_old := await _move_settle(false, 3000)
	var t_new := await _move_settle(true, 3000)
	print("squad_check: INFO settle ticks stand-in %d, squad brain %d" % [t_old, t_new])
	_check("item1 settle: the squadron settles on a 6,000-unit Move within 1.5 times the stand-in's time", _built() and t_old > 0 and t_new > 0 and float(t_new) <= 1.5 * float(t_old), "stand-in %d, new %d" % [t_old, t_new])
	if _built():
		_reset()
		sq = _spawn(0, "fighter", 3, start)
		await _ticks(5)
		await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(goal))
		await _ticks(1800)
		var worst := 0.0
		for s in _ships(sq):
			worst = maxf(worst, s.global_position.distance_to(TH.slot_of(world, sq, s)))
		_check("item1 settle: the three ships stand in their formation slots", worst <= 130.0, "farthest from its slot %d" % int(worst))
	else:
		_check("item1 settle: the three ships stand in their formation slots", false, "SquadronThink is not in this build")
	await _cases_item1_routes()
	await _cases_item1_fight()


## A squadron over three fixed routes (the three lane corners, through the jungle between them) ends near its point: none stuck in
## rocks. A route that fails is flown again by the stand-in, and both ends are printed.
func _cases_item1_routes() -> void:
	var points: Array[Vector2] = [Vector2(16500.0, 15600.0), Vector2(8200.0, 4200.0), Vector2(8200.0, 27000.0)]
	var ok_all := _built()
	var detail := ""
	for k in points.size():
		var far := await _route_far(points[k], true)
		detail += "route %d: %d; " % [k, int(far)]
		if far > 900.0:
			var old := await _route_far(points[k], false)
			print("squad_check: INFO route %d ends %d from its point (the stand-in: %d)" % [k, int(far), int(old)])
		ok_all = ok_all and far <= 900.0
	_check("item1 routes: none stuck in rocks on three fixed routes", ok_all, detail)


## Fly a fresh squadron from the lane start to `point` for 3,000 ticks with the new brain (or the stand-in) and return the farthest ship's distance.
func _route_far(point: Vector2, squad_brain: bool) -> float:
	_reset()
	if R != null:
		R.set_switch(squad_brain)
	var sq := _spawn(0, "fighter", 3, _lane_start())
	await _ticks(5)
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(point))
	await _ticks(3000)
	var far := _far_from(sq, point)
	if R != null:
		R.set_switch(true)
	return far

## Fighting: the idle rule, the leashes and the fire stances.
func _cases_item1_fight() -> void:
	await _attack_under_hold_fire()
	if not _built():
		for n in ["idle rule: a squadron with no order fights what comes into the scan radius and returns to its anchor",
				"leash: the chase numbers of hold, manoeuvre and roam", "leash: a hold squadron picks inside the scan radius and not outside it",
				"leash: a roam squadron keeps a target to 3,200 from its anchor and drops it past that",
				"leash: a manoeuvre squadron keeps a target to its gun reach plus 1,200 and drops it past that",
				"fire stance: at will picks the nearest enemy", "fire stance: return fire picks only the unit that hurt a member",
				"fire stance: hold fire picks nobody"]:
			_check("item1 " + n, false, "the new engine is not in this build")
		return
	# The chase numbers.
	var reach := 700.0
	_check("item1 leash: the chase numbers of hold, manoeuvre and roam", R.chase_limit(0, reach) == 250.0 and R.chase_limit(1, reach) == reach + 1200.0 and R.chase_limit(2, reach) == 3200.0 and R.scan_radius(0, reach) == reach + 200.0 and R.scan_radius(1, reach) == 1400.0 and R.scan_radius(2, reach) == 2000.0)
	# The idle rule.
	_reset()
	var spot := _lane_start()
	var sq := _spawn(0, "fighter", 3, spot)
	await _ticks(300)
	var foe := _enemy(spot + Vector2(1000.0, 0.0), "logistics")
	await _ticks(900)
	var hurt := _hurt(foe)
	if is_instance_valid(foe) and foe.alive:
		world.combat.kill_silently(foe)
	await _ticks(1200)
	_check("item1 idle rule: a squadron with no order fights what comes into the scan radius and returns to its anchor", hurt and _far_from(sq, spot) <= 500.0, "enemy hurt %s, farthest ship from the spot %d" % [str(hurt), int(_far_from(sq, spot))])
	# The picks: the think reads positions, so no ticks pass.
	_reset()
	sq = _spawn(0, "fighter", 3, spot)
	var guide := _ships(sq)[0]
	var rch := float(PilotTargeting.main_reach(guide))
	sq.move_stance = 0
	var e_in := _enemy(spot + Vector2(rch + 150.0, 0.0))
	await _ticks(3)
	TH.think(world, sq)
	_check("item1 leash: a hold squadron picks inside the scan radius and not outside it", int(sq.engine.get("target", 0)) == e_in.uid, "target %d" % int(sq.engine.get("target", 0)))
	e_in.global_position = spot + Vector2(rch + 400.0, 0.0)
	sq.engine["target"] = 0
	TH.think(world, sq)
	_check("item1 leash: a hold squadron does not pick outside the scan radius", int(sq.engine.get("target", 0)) == 0, "target %d" % int(sq.engine.get("target", 0)))
	# Keep limits: roam 3,200 and manoeuvre reach + 1,200, measured from the anchor with a target already held.
	sq.move_stance = 2
	e_in.global_position = spot + Vector2(3100.0, 0.0)
	sq.engine["target"] = e_in.uid
	TH.think(world, sq)
	var kept_roam := int(sq.engine.get("target", 0)) == e_in.uid
	e_in.global_position = spot + Vector2(3300.0, 0.0)
	sq.engine["target"] = e_in.uid
	TH.think(world, sq)
	var dropped_roam := int(sq.engine.get("target", 0)) != e_in.uid
	_check("item1 leash: a roam squadron keeps a target to 3,200 from its anchor and drops it past that", kept_roam and dropped_roam, "kept %s dropped %s" % [str(kept_roam), str(dropped_roam)])
	sq.move_stance = 1
	e_in.global_position = spot + Vector2(rch + 1150.0, 0.0)
	sq.engine["target"] = e_in.uid
	TH.think(world, sq)
	var kept_man := int(sq.engine.get("target", 0)) == e_in.uid
	e_in.global_position = spot + Vector2(rch + 1250.0, 0.0)
	sq.engine["target"] = e_in.uid
	TH.think(world, sq)
	var dropped_man := int(sq.engine.get("target", 0)) != e_in.uid
	_check("item1 leash: a manoeuvre squadron keeps a target to its gun reach plus 1,200 and drops it past that", kept_man and dropped_man, "kept %s dropped %s" % [str(kept_man), str(dropped_man)])
	# Fire stances.
	sq.move_stance = 1
	e_in.global_position = spot + Vector2(900.0, 0.0)
	var e_far := _enemy(spot + Vector2(1300.0, 0.0))
	await _ticks(3)
	sq.engine["target"] = 0
	sq.fire_stance = 0
	TH.think(world, sq)
	_check("item1 fire stance: at will picks the nearest enemy", int(sq.engine.get("target", 0)) == e_in.uid, "target %d" % int(sq.engine.get("target", 0)))
	sq.fire_stance = 1
	sq.engine["target"] = 0
	TH.think(world, sq)
	var none_hurt := int(sq.engine.get("target", 0)) == 0
	guide.damage_log[e_far.uid] = [10.0, world.time]
	sq.engine["target"] = 0
	TH.think(world, sq)
	_check("item1 fire stance: return fire picks only the unit that hurt a member", none_hurt and int(sq.engine.get("target", 0)) == e_far.uid, "target %d" % int(sq.engine.get("target", 0)))
	sq.fire_stance = 2
	sq.engine["target"] = 0
	TH.think(world, sq)
	_check("item1 fire stance: hold fire picks nobody", int(sq.engine.get("target", 0)) == 0)


## A direct Attack beats hold fire: a squadron set to hold fire still fires on the unit it is ordered to attack (a control: the
## stand-in ignores stances, so it does too).
func _attack_under_hold_fire() -> void:
	_reset()
	var spot := _lane_start()
	var sq := _spawn(0, "fighter", 3, spot)
	sq.fire_stance = 2
	var tgt := _enemy(spot + Vector2(2500.0, 0.0), "logistics")
	await _ticks(5)
	await _order(OrderKinds.ATTACK, [sq.id], "unit", tgt.uid)
	await _ticks(1500)
	_check("item1 fire stance: a direct Attack beats hold fire", _hurt(tgt), "enemy at %d" % _pct(tgt))

## Put one hunting turret and a held ship together as standin_hold_check does and return the farthest the ship got from its
## place in 600 ticks (-1 when the scenario cannot be made). `kind` is the order ("" for none).
func _turret_case(kind: String) -> float:
	_reset()
	var ms0 := world.mothership(0)
	var turret: Turret = null
	var best := INF
	for t: Turret in world.turrets:
		if t.team != 1 or not t.alive or not t.is_built():
			continue
		var d := t.global_position.distance_to(ms0.global_position)
		if d < best:
			best = d
			turret = t
	if turret == null:
		return -1.0
	var base := (ms0.global_position - turret.global_position).angle()
	var place := Vector2.INF
	var victim := Vector2.ZERO
	var spots: Array[Vector2] = []
	for k in 25:
		var steps := int(float(k + 1) * 0.5)
		var ang := base + deg_to_rad(float(steps * 15) * (1.0 if k % 2 == 1 else -1.0))
		var dir := Vector2.from_angle(ang)
		var at := turret.global_position + dir * (turret.range_r - 300.0)
		var inner := turret.global_position + dir * (turret.range_r - 800.0)
		if world.asteroids.blocked(at, 120.0) or world.asteroids.segment_blocked(turret.global_position, at):
			continue
		var side := Vector2(-dir.y, dir.x)
		var ok := true
		var sp: Array[Vector2] = []
		for j in 3:
			var pt := inner + side * float(j - 1) * 250.0
			if world.asteroids.blocked(pt, 60.0):
				ok = false
			sp.append(pt)
		if not ok:
			continue
		place = at
		victim = inner
		spots = sp
		break
	if place == Vector2.INF:
		return -1.0
	var sq := _spawn(0, "logistics", 1, place)
	var ship := _ships(sq)[0]
	ship.rotation = (turret.global_position - place).angle() + PI
	var minions: Array = []
	for pt: Vector2 in spots:
		minions.append(world.spawn_minion(0, "fighter", "mid", pt))
	await _ticks(2)
	if kind != "":
		await _order(kind, [sq.id], "none" if kind == OrderKinds.STOP else "point", 0 if kind == OrderKinds.STOP else Vector2i(place))
	var far := 0.0
	_turret_evades = 0
	var prev_evade := 0.0
	for k in 600:
		for i in minions.size():
			var m: Variant = minions[i]
			if is_instance_valid(m) and (m as Minion).alive:
				(m as Minion).global_position = spots[i]
				(m as Minion).hull = (m as Minion).hull_max
		ship.hull = ship.hull_max
		ship.aggro_time = world.time
		ship.aggro_victim_pos = victim
		await _ticks(1)
		far = maxf(far, ship.global_position.distance_to(place))
		var ev := float(ship.controller.get("evade_t")) if ship.controller != null and "evade_t" in ship.controller else 0.0
		if prev_evade <= 0.0 and ev > 0.0:
			_turret_evades += 1
		prev_evade = ev
	_turret_order_after = str(sq.order.get("kind", ""))
	for m: Variant in minions:
		if is_instance_valid(m) and (m as Minion).alive:
			world.combat.kill_silently(m as Unit)
	return far


# --- items 2 to 4 ---------------------------------------------------------------------

## Fail every name in `names` because the new engine is not in this build.
func _fail_all(names: Array) -> void:
	for n: String in names:
		_check(n, false, "the new engine is not in this build")


## Put a goal straight into record `sq` (as the goal order would) without an order's wait.
func _set_goal(sq: Squad, kind: String, target_kind: String, target: Variant) -> void:
	sq.goal = {"kind": kind, "target_kind": target_kind, "target": target, "tick": world.tick_count, "settings": {}, "phase": ""}
	sq.order = {}


## The plan's anchor of record `sq` (as the last think wrote it).
func _anchor(sq: Squad) -> Vector2:
	return sq.engine.get("anchor", Vector2.INF)


## The enemy structure places of lane `lane` for team 0's push, nearest our side first.
func _foes(lane: String) -> Array:
	var foes: Array = GP.lane_structures(world, 1, lane)
	foes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return GP.along(0, lane, a) < GP.along(0, lane, b))
	return foes


## Goals: Defend, Escort, Push lane, the failure cases, the one-off that returns to the goal, a new goal that replaces, the named points.
func _cases_item2() -> void:
	if not _built():
		_fail_all(["item2 defend point: the goal is written and the squadron holds the point, facing away from our mothership",
			"item2 defend point: a Stop ends it", "item2 defend a unit: when it dies the squadron defends its spot",
			"item2 defend lane: the anchor is our foremost turret and steps back when that turret dies", "item2 defend lane: the order is accepted and anchors there",
			"item2 escort: the squadron follows a moving friendly ship", "item2 escort: the charge dies, the squadron holds its last spot and goes idle", "item2 escort: the charge docks, the squadron holds its last spot and goes idle",
			"item2 escort: more than 6,000 for 1,200 ticks ends the goal", "item2 escort: one tick before the line it still escorts", "item2 escort: exactly 6,000 away is not behind",
			"item2 escort: a big friendly ship is guarded from the pocket", "item2 push lane: waits outside 2,500 of an enemy turret with no minion of ours inside",
			"item2 push lane: goes in when a minion of ours is inside the turret's reach", "item2 push lane: a direct Attack commits it",
			"item2 push lane: with no minion front it holds at our foremost turret", "item2 push lane: the anchor follows the front",
			"item2 failure: an unreachable goal is held, one blocked event is filed and it is tried again later", "item2 failure: a straggler stays in the record",
			"item2 failure: outnumbered ships never retreat or dock", "item2 one-off: a Move mid-goal runs and the squadron goes back to its goal",
			"item2 one-off: an Attack that ends gives the squadron back to its goal", "item2 new goal: replaces the old goal and the standing one-off",
			"item2 goal points: a click snaps to a named thing inside 1,500 and not outside", "item2 goal points: lane_at names the lane band under a point",
			"item2 control: a squadron with a Move order goes where it is told"])
		return
	var P := _lane_start()
	var ms0 := _ms0()
	# Defend a point.
	_reset()
	var sq := _spawn(0, "fighter", 3, P + Vector2(-3000.0, 0.0))
	await _ticks(5)
	var r := await _order(OrderKinds.DEFEND, [sq.id], "point", Vector2i(P))
	var written := r == "" and str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and sq.order.is_empty()
	await _ticks(1800)
	var away := absf(angle_difference(deg_to_rad(float(sq.engine.get("heading", 0.0))), (P - ms0).angle())) < 0.02
	_check("item2 defend point: the goal is written and the squadron holds the point, facing away from our mothership", written and _far_from(sq, P) <= 500.0 and sq.state == 0 and away, "refusal '%s', far %d, state %d, away %s" % [r, int(_far_from(sq, P)), sq.state, str(away)])
	await _order(OrderKinds.STOP, [sq.id])
	_check("item2 defend point: a Stop ends it", sq.goal.is_empty() and str(sq.order.get("kind", "")) == OrderKinds.STOP)
	# Defend a unit of ours; when it dies the squadron defends its spot.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	var ward_sq := _spawn(0, "logistics", 1, P + Vector2(2000.0, 1500.0))
	var ward := _ships(ward_sq)[0]
	await _ticks(5)
	r = await _order(OrderKinds.DEFEND, [sq.id], "unit", ward.uid)
	TH.think(world, sq)
	var on_ward := _anchor(sq).distance_to(ward.global_position) < 5.0
	var last := ward.global_position
	world.combat.kill_silently(ward)
	TH.think(world, sq)
	_check("item2 defend a unit: when it dies the squadron defends its spot", r == "" and on_ward and _anchor(sq).distance_to(last) < 5.0 and str(sq.goal.get("kind", "")) == OrderKinds.DEFEND, "refusal '%s', on ward %s" % [r, str(on_ward)])
	# Defend a lane: our foremost turret, and the step back when it dies.
	_reset()
	var a1: Vector2 = GP.lane_anchor(world, 0, "top")
	var killed := false
	for node in world.nodes:
		if node.side == 0 and node.lane == "top" and MapLayout.is_lane_site_kind(node.node_kind):
			for t in node.slots:
				if t != null and is_instance_valid(t) and t.alive and (t as Node2D).global_position.distance_to(a1) < 1.0 and not killed:
					world.combat.kill_silently(t as Unit)
					killed = true
	var a2: Vector2 = GP.lane_anchor(world, 0, "top")
	_check("item2 defend lane: the anchor is our foremost turret and steps back when that turret dies", killed and a2 != a1 and GP.along(0, "top", a2) < GP.along(0, "top", a1), "killed %s, along %d then %d" % [str(killed), int(GP.along(0, "top", a1)), int(GP.along(0, "top", a2))])
	sq = _spawn(0, "fighter", 3, P)
	await _ticks(5)
	r = await _order(OrderKinds.DEFEND, [sq.id], "lane", "top")
	TH.think(world, sq)
	_check("item2 defend lane: the order is accepted and anchors there", r == "" and _anchor(sq).distance_to(GP.lane_anchor(world, 0, "top")) < 1.0, "refusal '%s'" % r)
	# Escort: a moving friendly ship.
	_reset()
	var ch_sq := _spawn(0, "fighter", 1, P)
	var charge := _ships(ch_sq)[0]
	sq = _spawn(0, "fighter", 3, P + Vector2(-1500.0, 0.0))
	await _ticks(5)
	r = await _order(OrderKinds.ESCORT, [sq.id], "unit", charge.uid)
	var escort_ok := r == "" and str(sq.goal.get("kind", "")) == OrderKinds.ESCORT
	await _order(OrderKinds.MOVE, [ch_sq.id], "point", Vector2i(P + Vector2(5000.0, 0.0)))
	await _ticks(1800)
	var near := _far_from(sq, charge.global_position)
	_check("item2 escort: the squadron follows a moving friendly ship", escort_ok and charge.global_position.x > P.x + 3000.0 and near <= 900.0, "refusal '%s', charge x %d, farthest ship %d" % [r, int(charge.global_position.x), int(near)])
	last = charge.global_position
	world.combat.kill_silently(charge)
	await _ticks(40)
	_check("item2 escort: the charge dies, the squadron holds its last spot and goes idle", sq.goal.is_empty() and str(sq.engine.get("mode", "")) == "idle" and (sq.engine.get("idle_spot", Vector2.INF) as Vector2).distance_to(last) < 5.0, "goal %s mode %s" % [str(sq.goal), str(sq.engine.get("mode", ""))])
	# The charge docks (a pilot's ship goes back into the mothership: it leaves the match, as a death does).
	_reset()
	var dock_p := PilotProfile.new("dockcheck", 0, 0, false)
	dock_p.hull_id = "fighter"
	dock_p.role = "mid"
	world.profiles.append(dock_p)
	var dock_ship := world.launch(dock_p)
	var dock_ok := false
	if dock_ship != null:
		dock_ship.global_position = P
		sq = _spawn(0, "fighter", 3, P + Vector2(-1500.0, 0.0))
		_set_goal(sq, OrderKinds.ESCORT, "unit", dock_ship.uid)
		TH.think(world, sq)
		var dock_last := dock_ship.global_position
		var docked := world.try_dock(dock_ship, true)
		TH.think(world, sq)
		dock_ok = docked and sq.goal.is_empty() and str(sq.engine.get("mode", "")) == "idle" and (sq.engine.get("idle_spot", Vector2.INF) as Vector2).distance_to(dock_last) < 5.0
	world.profiles.erase(dock_p)
	_check("item2 escort: the charge docks, the squadron holds its last spot and goes idle", dock_ok, "launched %s" % str(dock_ship != null))
	# Escort give-up: more than 6,000 for 1,200 ticks (the think adds 15 a time).
	var ended := await _escort_gap(6001.0, 1185)
	_check("item2 escort: more than 6,000 for 1,200 ticks ends the goal", ended)
	ended = await _escort_gap(6001.0, 1184)
	_check("item2 escort: one tick before the line it still escorts", not ended)
	ended = await _escort_gap(6000.0, 1185)
	_check("item2 escort: exactly 6,000 away is not behind", not ended)
	# A big friendly ship is guarded from the pocket.
	_reset()
	var big_sq := _spawn(0, "logistics", 1, P)
	var big := _ships(big_sq)[0]
	sq = _spawn(0, "fighter", 3, P + Vector2(-1500.0, 0.0))
	_set_goal(sq, OrderKinds.ESCORT, "unit", big.uid)
	TH.think(world, sq)
	var pocket := bool(sq.engine.get("pocket", false))
	var want_slot := SquadEngine.guard_slot(big.global_position, big.rotation, big.radius, float(sq.engine.get("cone", 70.0)), 1)
	var got_slot: Vector2 = TH.slot_of(world, sq, _ships(sq)[1])
	_check("item2 escort: a big friendly ship is guarded from the pocket", pocket and got_slot.distance_to(want_slot) < 1.0, "pocket %s" % str(pocket))
	await _cases_item2_push()
	await _cases_item2_failure()


## The Escort give-up with a guide `dist` from the charge and `strag` ticks already counted: true when the goal ended.
func _escort_gap(dist: float, strag: int) -> bool:
	_reset()
	var c_sq := _spawn(0, "fighter", 1, _lane_start())
	var c := _ships(c_sq)[0]
	var sq := _spawn(0, "fighter", 3, _lane_start() + Vector2(0.0, 3000.0))
	_ships(sq)[0].global_position = c.global_position + Vector2(dist, 0.0)
	_set_goal(sq, OrderKinds.ESCORT, "unit", c.uid)
	sq.engine["strag"] = strag
	TH.think(world, sq)
	return sq.goal.is_empty()


## Push lane: the keep-out, the minions inside the reach, a direct Attack, no front, the follow.
func _cases_item2_push() -> void:
	var lane := "top"
	_reset()
	var foes := _foes(lane)
	if foes.is_empty():
		_fail_all(["item2 push lane: waits outside 2,500 of an enemy turret with no minion of ours inside", "item2 push lane: goes in when a minion of ours is inside the turret's reach",
			"item2 push lane: a direct Attack commits it", "item2 push lane: with no minion front it holds at our foremost turret", "item2 push lane: the anchor follows the front"])
		return
	var T: Vector2 = foes[0]
	var pts: PackedVector2Array = GP.lane_line(0, lane)
	var sT := float(GP.along(0, lane, T))
	var none_p: Vector2 = GP.push_point(world, 0, lane)
	_check("item2 push lane: with no minion front it holds at our foremost turret", none_p.distance_to(GP.lane_anchor(world, 0, lane)) < 1.0)
	var m := world.spawn_minion(0, "fighter", lane, Util.polyline_at(pts, sT - 3000.0))
	var p_out: Vector2 = GP.push_point(world, 0, lane)
	_check("item2 push lane: waits outside 2,500 of an enemy turret with no minion of ours inside", p_out.distance_to(T) >= 2499.0, "distance %d" % int(p_out.distance_to(T)))
	var sq := _spawn(0, "fighter", 3, Util.polyline_at(pts, sT - 5000.0))
	_set_goal(sq, OrderKinds.PUSH_LANE, "lane", lane)
	TH.think(world, sq)
	_check("item2 push lane: the anchor follows the front", _anchor(sq).distance_to(p_out) < 1.0, "anchor %s, push point %s" % [str(_anchor(sq)), str(p_out)])
	m.global_position = Util.polyline_at(pts, sT - 1500.0)
	var p_in: Vector2 = GP.push_point(world, 0, lane)
	_check("item2 push lane: goes in when a minion of ours is inside the turret's reach", p_in.distance_to(T) < 2500.0, "distance %d" % int(p_in.distance_to(T)))
	var tower: Turret = null
	for t: Turret in world.turrets:
		if t.team == 1 and t.alive and t.global_position.distance_to(T) < 1.0:
			tower = t
	if tower != null:
		tower.visible_mask |= 1
		await _order(OrderKinds.ATTACK, [sq.id], "unit", tower.uid)
		TH.think(world, sq)
	_check("item2 push lane: a direct Attack commits it", tower != null and str(sq.engine.get("mode", "")) == "attack" and _anchor(sq).distance_to(T) < 1.0, "mode %s" % str(sq.engine.get("mode", "")))
	world.combat.kill_silently(m)


## The failure cases, the one-off that returns, the new goal, the named points.
func _cases_item2_failure() -> void:
	var P := _lane_start()
	# Unreachable: no gain on the anchor in 600 ticks.
	_reset()
	var sq := _spawn(0, "fighter", 3, P)
	var cursor: int = world.events_rts.next_index(0)
	_set_goal(sq, OrderKinds.DEFEND, "point", Vector2i(P + Vector2(9000.0, 0.0)))
	var saved_tick := world.tick_count
	TH.think(world, sq)
	world.tick_count += 600
	TH.think(world, sq)
	var blocked := bool(sq.engine.get("blocked", false)) and sq.state == 0
	var n_events := 0
	for e: Dictionary in world.events_rts.read_from(0, cursor):
		if str(e["kind"]) == "squadron_blocked":
			n_events += 1
	world.tick_count += 1800
	TH.think(world, sq)
	var retried := not bool(sq.engine.get("blocked", false)) and str(sq.goal.get("kind", "")) == OrderKinds.DEFEND
	world.tick_count = saved_tick
	_check("item2 failure: an unreachable goal is held, one blocked event is filed and it is tried again later", blocked and n_events == 1 and retried, "blocked %s, events %d, retried %s" % [str(blocked), n_events, str(retried)])
	# A straggler stays in the record and has a place to fly to.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	_set_goal(sq, OrderKinds.DEFEND, "point", Vector2i(P))
	var lag := _ships(sq)[2]
	lag.global_position += Vector2(7000.0, 0.0)
	TH.think(world, sq)
	var lag_slot: Vector2 = TH.slot_of(world, sq, lag)
	_check("item2 failure: a straggler stays in the record", sq.member_uids.has(lag.uid) and lag_slot.distance_to(lag.global_position) > 1000.0)
	# Outnumbered ships fight on: nothing here retreats or docks them.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	for s in _ships(sq):
		s.hull = s.hull_max * 0.1
	for k in 6:
		_enemy(P + Vector2(1500.0, float(k - 3) * 200.0))
	await _ticks(200)
	var fled := false
	for s in _ships(sq):
		var ai := s.controller as PilotAI
		fled = fled or ai.state == "retreat" or ai.state == "home" or s.controls.dock
	_check("item2 failure: outnumbered ships never retreat or dock", not fled)
	# A Move mid-goal runs and the squadron goes back to its goal.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	await _ticks(5)
	await _order(OrderKinds.DEFEND, [sq.id], "point", Vector2i(P))
	await _ticks(300)
	var Q := P + Vector2(2500.0, 0.0)
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(Q))
	var kept := str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and str(sq.order.get("kind", "")) == OrderKinds.MOVE
	await _ticks(2600)
	_check("item2 one-off: a Move mid-goal runs and the squadron goes back to its goal", kept and sq.order.is_empty() and _far_from(sq, P) <= 700.0, "kept %s, order %s, far %d" % [str(kept), str(sq.order), int(_far_from(sq, P))])
	# An Attack that ends gives the squadron back to its goal.
	var foe := _enemy(P + Vector2(2500.0, 0.0))
	await _order(OrderKinds.ATTACK, [sq.id], "unit", foe.uid)
	var on := str(sq.order.get("kind", "")) == OrderKinds.ATTACK
	world.combat.kill_silently(foe)
	TH.think(world, sq)
	_check("item2 one-off: an Attack that ends gives the squadron back to its goal", on and sq.order.is_empty() and str(sq.goal.get("kind", "")) == OrderKinds.DEFEND, "order %s" % str(sq.order))
	# A new goal replaces the old goal and the standing one-off.
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(Q))
	await _order(OrderKinds.PUSH_LANE, [sq.id], "lane", "mid")
	_check("item2 new goal: replaces the old goal and the standing one-off", str(sq.goal.get("kind", "")) == OrderKinds.PUSH_LANE and sq.order.is_empty() and str(sq.goal.get("target", "")) == "mid")
	# The named points.
	var nd: Vector2 = (world.map.nodes[0] as Dictionary)["pos"]
	var corner := Vector2(200.0, 200.0)
	_check("item2 goal points: a click snaps to a named thing inside 1,500 and not outside",
		GP.snap(world, nd + Vector2(1400.0, 0.0)) == Order.point(nd) and GP.snap(world, corner) == Order.point(corner))
	_check("item2 goal points: lane_at names the lane band under a point", GP.lane_at(world, Vector2(20000.0, 4200.0)) == "top" and GP.lane_at(world, Vector2(31000.0, 27000.0)) == "bot" and GP.lane_at(world, corner) == "")
	# The positive control: a Move goes where it is told (item 1 holds the long version).
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	await _ticks(5)
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(P + Vector2(0.0, -2500.0)))
	await _ticks(1500)
	_check("item2 control: a squadron with a Move order goes where it is told", _far_from(sq, P + Vector2(0.0, -2500.0)) <= 450.0)


## Stop, Hold and the stances: Stop clears a goal, Hold pauses it, a new goal replaces it, the stance and formation orders, the keep-target rule.
func _cases_item3() -> void:
	if not _built():
		_fail_all(["item3 stop: clears a goal and its one-off", "item3 hold: pauses the goal and a later Move returns to it", "item3 hold: a new goal after a Hold replaces it",
			"item3 stance: SET_STANCE and SET_FORMATION change the record and the brain obeys at the next think", "item3 stance: a Move no longer resets a Roam squadron's stance",
			"item3 stance: nine fire and move stance pairs each keep the current target when changed", "item3 stance: Hold keeps the hold leash by the order, not by the stored stance"])
		return
	var P := _lane_start()
	_reset()
	var sq := _spawn(0, "fighter", 3, P)
	await _ticks(5)
	await _order(OrderKinds.DEFEND, [sq.id], "point", Vector2i(P))
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(P + Vector2(500.0, 0.0)))
	await _order(OrderKinds.STOP, [sq.id])
	_check("item3 stop: clears a goal and its one-off", sq.goal.is_empty() and str(sq.order.get("kind", "")) == OrderKinds.STOP)
	# Hold pauses the goal.
	await _order(OrderKinds.DEFEND, [sq.id], "point", Vector2i(P))
	var Q := P + Vector2(2000.0, 0.0)
	await _order(OrderKinds.HOLD, [sq.id], "point", Vector2i(Q))
	var paused := str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and str(sq.engine.get("mode", "")) == "hold" and _anchor(sq).distance_to(Q) < 1.0
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(Q))
	_ships(sq)[0].global_position = Q
	sq.engine["idle_t"] = 180
	TH.think(world, sq)
	var back := sq.order.is_empty() and str(sq.engine.get("mode", "")) == "defend" and _anchor(sq).distance_to(P) < 1.0
	_check("item3 hold: pauses the goal and a later Move returns to it", paused and back, "paused %s, back %s, mode %s" % [str(paused), str(back), str(sq.engine.get("mode", ""))])
	await _order(OrderKinds.HOLD, [sq.id], "point", Vector2i(Q))
	await _order(OrderKinds.ESCORT, [sq.id], "unit", _ships(_spawn(0, "fighter", 1, P))[0].uid)
	_check("item3 hold: a new goal after a Hold replaces it", str(sq.goal.get("kind", "")) == OrderKinds.ESCORT and sq.order.is_empty())
	# The stance and formation orders.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	await _ticks(5)
	var r1 := await _order(OrderKinds.SET_STANCE, [sq.id], "none", 0, {"fire": 1, "move": 2})
	var r2 := await _order(OrderKinds.SET_FORMATION, [sq.id], "none", 0, {"formation": 2})
	TH.think(world, sq)
	_check("item3 stance: SET_STANCE and SET_FORMATION change the record and the brain obeys at the next think", r1 == "" and r2 == "" and sq.fire_stance == 1 and sq.move_stance == 2 and sq.formation == 2 and int(sq.engine.get("shape", -1)) == 2, "refusals '%s' '%s', shape %d" % [r1, r2, int(sq.engine.get("shape", -1))])
	var rm := await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(P + Vector2(500.0, 0.0)))
	_check("item3 stance: a Move no longer resets a Roam squadron's stance", rm == "" and sq.move_stance == 2)
	await _order(OrderKinds.HOLD, [sq.id], "point", Vector2i(P))
	_check("item3 stance: Hold keeps the hold leash by the order, not by the stored stance", sq.move_stance == 2 and float(sq.engine.get("chase", 0.0)) == 250.0 and str(sq.engine.get("leash", "")) == "slot")
	# Nine pairs each keep the current target.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	var foe := _enemy(P + Vector2(800.0, 0.0))
	await _ticks(3)
	var bad := ""
	for f in 3:
		for m in 3:
			sq.fire_stance = 0
			sq.move_stance = 1
			sq.engine["target"] = 0
			TH.think(world, sq)
			var first := int(sq.engine.get("target", 0))
			sq.fire_stance = f
			sq.move_stance = m
			TH.think(world, sq)
			if first != foe.uid or int(sq.engine.get("target", 0)) != foe.uid:
				bad += "(%d,%d) " % [f, m]
	_check("item3 stance: nine fire and move stance pairs each keep the current target when changed", bad == "", "lost at " + bad)


## Merge: two short squadrons, a leftover, the refusals, the host's goal, the emptied donor, and the replay.
func _cases_item4() -> void:
	if not _built():
		_fail_all(["item4 merge: two short squadrons of one hull merge into one of three", "item4 merge: the leftover stays short in the donor",
			"item4 merge: across hulls is refused with the merge text", "item4 merge: a full host is refused with the merge text", "item4 merge: the host keeps its goal and the ships' crews follow it",
			"item4 merge: the emptied donor is kept as an idle record with no members", "item4 replay: the same scripted orders twice give the same ships and states"])
		return
	var P := _lane_start()
	_reset()
	var host_it := _prod(0).spawn_now("fighter", 1)
	var host: Squad = world.squads.get(int(host_it["squad"])) as Squad
	var don_it := _prod(0).spawn_now("fighter", 2)
	var donor: Squad = world.squads.get(int(don_it["squad"])) as Squad
	host.goal = {"kind": OrderKinds.DEFEND, "target_kind": "point", "target": Vector2i(P), "tick": world.tick_count, "settings": {}, "phase": ""}
	var moved_uids: Array = donor.member_uids.duplicate()
	var r := await _order(OrderKinds.MERGE, [donor.id], "squadron", host.id)
	_check("item4 merge: two short squadrons of one hull merge into one of three", r == "" and host.member_uids.size() == 3 and donor.member_uids.is_empty(), "refusal '%s', host %d, donor %d" % [r, host.member_uids.size(), donor.member_uids.size()])
	var crews_ok := true
	for uid: int in moved_uids:
		crews_ok = crews_ok and ((world.by_uid.get(uid) as Ship).profile.squad_id == host.id)
	_check("item4 merge: the host keeps its goal and the ships' crews follow it", crews_ok and str(host.goal.get("kind", "")) == OrderKinds.DEFEND)
	_check("item4 merge: the emptied donor is kept as an idle record with no members", world.squads.has(donor.id) and donor.member_uids.is_empty() and donor.state == 0 and donor.order.is_empty() and donor.goal.is_empty())
	# A leftover: a host with two takes one of a donor's two.
	_reset()
	var h2: Squad = world.squads.get(int(_prod(0).spawn_now("fighter", 2)["squad"])) as Squad
	var d2: Squad = world.squads.get(int(_prod(0).spawn_now("fighter", 2)["squad"])) as Squad
	r = await _order(OrderKinds.MERGE, [d2.id], "squadron", h2.id)
	_check("item4 merge: the leftover stays short in the donor", r == "" and h2.member_uids.size() == 3 and d2.member_uids.size() == 1, "refusal '%s', host %d, donor %d" % [r, h2.member_uids.size(), d2.member_uids.size()])
	# Refusals.
	_reset()
	var a: Squad = world.squads.get(int(_prod(0).spawn_now("fighter", 1)["squad"])) as Squad
	var b: Squad = world.squads.get(int(_prod(0).spawn_now("lance", 1)["squad"])) as Squad
	r = await _order(OrderKinds.MERGE, [b.id], "squadron", a.id)
	_check("item4 merge: across hulls is refused with the merge text", r == "That order is not valid: only the same ship type can merge" and a.member_uids.size() == 1, "refusal '%s'" % r)
	_reset()
	var full: Squad = world.squads.get(int(_prod(0).spawn_now("fighter", 3)["squad"])) as Squad
	var one: Squad = world.squads.get(int(_prod(0).spawn_now("fighter", 1)["squad"])) as Squad
	r = await _order(OrderKinds.MERGE, [one.id], "squadron", full.id)
	_check("item4 merge: a full host is refused with the merge text", r == "That order is not valid: that squadron is full" and full.member_uids.size() == 3, "refusal '%s'" % r)
	await _cases_item4_replay()


## Run the same scripted orders (a goal, a Hold, a Move) twice from the same random seed and compare every ship's place and every
## squadron's state at the same later tick. (One world, started again and seeded again: the match log's own replay needs two processes.)
func _cases_item4_replay() -> void:
	var first := await _scripted_run()
	var second := await _scripted_run()
	_check("item4 replay: the same scripted orders twice give the same ships and states", first != "" and first == second, "first %s | second %s" % [first.left(120), second.left(120)])


## One scripted run, returned as a text of every ship's place and every squadron's state.
func _scripted_run() -> String:
	_reset()
	# The same ship numbers and the same tick phase in both runs (the brains think on uid and tick residues).
	var uid_now := world.registry.next_uid()
	while uid_now % 30 != 29:
		uid_now = world.registry.next_uid()
	while world.tick_count % 30 != 0:
		await _ticks(1)
	seed(7)
	var P := _lane_start()
	var sq := _spawn(0, "fighter", 3, P)
	var merge_host := _spawn(0, "fighter", 1, P + Vector2(0.0, 1500.0))
	await _ticks(5)
	await _order(OrderKinds.DEFEND, [sq.id], "point", Vector2i(P + Vector2(1500.0, 0.0)))
	await _ticks(300)
	await _order(OrderKinds.HOLD, [sq.id], "point", Vector2i(P + Vector2(0.0, -1500.0)))
	await _ticks(300)
	await _order(OrderKinds.MOVE, [sq.id], "point", Vector2i(P + Vector2(2500.0, -500.0)))
	await _ticks(300)
	await _order(OrderKinds.MERGE, [merge_host.id], "squadron", sq.id)
	await _ticks(300)
	var out := ""
	for s in _ships(sq):
		out += "%.3f,%.3f;" % [s.global_position.x, s.global_position.y]
	out += "state %d goal %s order %s members %d" % [sq.state, str(sq.goal.get("kind", "")), str(sq.order.get("kind", "")), sq.member_uids.size()]
	return out


# --- item 5: the Orders-page hookup ---------------------------------------------------

## The Orders cells and the wheel send their orders and the lit cells match the orders a bought squadron takes.
func _cases_item5() -> void:
	var RSO: Variant = _cls("ui/rts/rts_squad_orders")
	var names := ["item5 cells: the Goal cell is lit (kind DEFEND) and the Position cell is lit (kind SET_STANCE)", "item5 cells: Defend sends a goal on a point (snapped) and on a unit of ours",
		"item5 cells: Escort sends a goal on a friendly ship", "item5 cells: Push lane sends a goal on the lane band under the click", "item5 cells: Merge gives the selected ships to the squadron clicked",
		"item5 cells: Goal on an enemy ship is refused with the Harass text", "item5 cells: Goal on a friendly ship is Escort, on a lane band Push lane, elsewhere Defend",
		"item5 cells: the Stance cell cycles the fire stance only and leaves the move stance", "item5 cells: the Formation cell cycles the formation",
		"item5 cells: with none selected a cell says Select squadrons first", "item5 wheel: the slices 4, 5 and 7 are lit and 0 and 6 are dim",
		"item5 wheel: Defend here and Push this lane give their orders", "item5 right-click: a friendly ship is Escort and a structure of ours is Defend"]
	if not _built() or RSO == null or RSO.get_script_method_list().filter(func(m: Dictionary) -> bool: return str(m["name"]) == "cycle_stance").is_empty():
		_fail_all(names)
		return
	var P := _lane_start()
	_reset()
	var ov := CommandOverlay.new()
	ov.world = world
	ov.team = 0
	var goal_kind := str(CardPages.cell("orders", "goal")["kind"])
	var lit_ok := OrderKinds.BOUGHT_KINDS.has(goal_kind) and str(CardPages.cell("orders", "position")["kind"]) == OrderKinds.SET_STANCE
	for id: String in ["defend", "escort", "push_lane", "merge", "stance", "formation"]:
		lit_ok = lit_ok and OrderKinds.BOUGHT_KINDS.has(str(CardPages.cell("orders", id)["kind"]))
	_check("item5 cells: the Goal cell is lit (kind DEFEND) and the Position cell is lit (kind SET_STANCE)", lit_ok and goal_kind == OrderKinds.DEFEND)
	var sq := _spawn(0, "fighter", 3, P)
	var friend_sq := _spawn(0, "fighter", 1, P + Vector2(0.0, 2200.0))
	var friend := _ships(friend_sq)[0]
	var host_sq := _spawn(0, "fighter", 1, P + Vector2(0.0, -2200.0))
	var host_ship := _ships(host_sq)[0]
	await _ticks(3)
	ov.sel_squads = [sq.id]
	# Defend: a point (snapped) and a unit of ours.
	var click := P + Vector2(500.0, 1000.0)
	RSO.defend_at(ov, click)
	await _ticks(3)
	var on_point: bool = str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and str(sq.goal.get("target_kind", "")) == "point" and sq.goal.get("target") == GP.snap(world, click)
	RSO.defend_at(ov, friend.global_position)
	await _ticks(3)
	_check("item5 cells: Defend sends a goal on a point (snapped) and on a unit of ours", on_point and str(sq.goal.get("target_kind", "")) == "unit" and int(sq.goal.get("target", 0)) == friend.uid, str(sq.goal))
	RSO.escort_at(ov, friend.global_position)
	await _ticks(3)
	_check("item5 cells: Escort sends a goal on a friendly ship", str(sq.goal.get("kind", "")) == OrderKinds.ESCORT and int(sq.goal.get("target", 0)) == friend.uid, str(sq.goal))
	RSO.push_at(ov, Vector2(20000.0, 4200.0))
	await _ticks(3)
	_check("item5 cells: Push lane sends a goal on the lane band under the click", str(sq.goal.get("kind", "")) == OrderKinds.PUSH_LANE and str(sq.goal.get("target", "")) == "top", str(sq.goal))
	RSO.merge_at(ov, host_ship.global_position)
	await _ticks(3)
	_check("item5 cells: Merge gives the selected ships to the squadron clicked", host_sq.member_uids.size() == 3 and sq.member_uids.size() == 1, "host %d, donor %d" % [host_sq.member_uids.size(), sq.member_uids.size()])
	# The Goal cell's routing.
	var enemy := _enemy(P + Vector2(3000.0, 3000.0))
	await _ticks(3)
	var before := str(sq.goal)
	var why: String = RSO.goal_at(ov, enemy.global_position)
	await _ticks(3)
	_check("item5 cells: Goal on an enemy ship is refused with the Harass text", why == "Harass: comes with a later stage" and str(sq.goal) == before, why)
	RSO.goal_at(ov, friend.global_position)
	await _ticks(3)
	var g_escort := str(sq.goal.get("kind", "")) == OrderKinds.ESCORT
	RSO.goal_at(ov, Vector2(31000.0, 27000.0))
	await _ticks(3)
	var g_push := str(sq.goal.get("kind", "")) == OrderKinds.PUSH_LANE and str(sq.goal.get("target", "")) == "bot"
	RSO.goal_at(ov, Vector2(200.0, 200.0))
	await _ticks(3)
	var g_def := str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and str(sq.goal.get("target_kind", "")) == "point"
	_check("item5 cells: Goal on a friendly ship is Escort, on a lane band Push lane, elsewhere Defend", g_escort and g_push and g_def, "%s %s %s" % [str(g_escort), str(g_push), str(g_def)])
	# Stance and Formation.
	sq.move_stance = 2
	sq.fire_stance = 0
	RSO.cycle_stance(ov)
	await _ticks(3)
	var s1 := sq.fire_stance == 1 and sq.move_stance == 2
	RSO.cycle_stance(ov)
	await _ticks(3)
	var s2 := sq.fire_stance == 2 and sq.move_stance == 2
	_check("item5 cells: the Stance cell cycles the fire stance only and leaves the move stance", s1 and s2, "fire %d move %d" % [sq.fire_stance, sq.move_stance])
	var f0 := sq.formation
	RSO.cycle_formation(ov)
	await _ticks(3)
	_check("item5 cells: the Formation cell cycles the formation", sq.formation != f0, "formation %d" % sq.formation)
	ov.sel_squads = []
	RSO.cycle_stance(ov)
	_check("item5 cells: with none selected a cell says Select squadrons first", ov.result_text == "Select squadrons first", ov.result_text)
	ov.sel_squads = [sq.id]
	# The wheel.
	var sl: Array = OrderWheel.SLICES
	_check("item5 wheel: the slices 4, 5 and 7 are lit and 0 and 6 are dim", bool((sl[4] as Array)[2]) and bool((sl[5] as Array)[2]) and bool((sl[7] as Array)[2]) and not bool((sl[0] as Array)[2]) and not bool((sl[6] as Array)[2]))
	var w1 := FieldOrders.give(world, "defend", [sq.id], click)
	await _ticks(3)
	var d_ok: bool = w1 == "" and str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and sq.goal.get("target") == GP.snap(world, click)
	var w2 := FieldOrders.give(world, "push", [sq.id], Vector2(20000.0, 4200.0))
	await _ticks(3)
	var p_ok := w2 == "" and str(sq.goal.get("kind", "")) == OrderKinds.PUSH_LANE and str(sq.goal.get("target", "")) == "top"
	var w3 := FieldOrders.give(world, "push", [sq.id], Vector2(200.0, 200.0))
	_check("item5 wheel: Defend here and Push this lane give their orders", d_ok and p_ok and w3.begins_with("That order is not valid"), "%s | %s | %s" % [w1, w2, w3])
	# The right-click.
	var tower: Turret = null
	for t: Turret in world.turrets:
		if t.team == 0 and t.alive and t.global_position.distance_to(_ms0()) > 4000.0:
			tower = t
			break
	RSO.smart_order_at(ov, friend.global_position)
	await _ticks(3)
	var rc_ship := str(sq.goal.get("kind", "")) == OrderKinds.ESCORT and int(sq.goal.get("target", 0)) == friend.uid
	var rc_struct := false
	if tower != null:
		RSO.smart_order_at(ov, tower.global_position)
		await _ticks(3)
		rc_struct = str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and int(sq.goal.get("target", 0)) == tower.uid
	_check("item5 right-click: a friendly ship is Escort and a structure of ours is Defend", rc_ship and rc_struct, "ship %s struct %s (tower %s)" % [str(rc_ship), str(rc_struct), str(tower != null)])
	ov.free()


# --- item 6: the Position pick ---------------------------------------------------------

## The Position pick (hold, manoeuvre, roam on the Orders page): the pick list and its cells, the move-only stance order it sends
## through RtsSquadOrders.set_position, and what the brain and the answer line do with it. A build without set_position prints FAIL
## lines for every case here and never fails to parse (nothing this build adds is named except through _cls, get and a Variant).
func _cases_position() -> void:
	var RSO: Variant = _cls("ui/rts/rts_squad_orders")
	var names := ["item6 position: the Orders page has a pick list of hold, manoeuvre and roam in layouts A and B",
		"item6 position: each pick sets the move stance and leaves the fire stance and the formation",
		"item6 position: the pick sends only the move setting", "item6 position: one pick sets every selected squadron",
		"item6 position: the answer line names the pick and the count",
		"item6 position: with none selected it says Select squadrons first and sends nothing",
		"item6 position: the brain reads the picked stance at its next think", "item6 position: a pick leaves a standing goal and order alone",
		"item6 position: the pick words are the move stance's names"]
	if not _built() or RSO == null or RSO.get_script_method_list().filter(func(m: Dictionary) -> bool: return str(m["name"]) == "set_position").is_empty():
		_fail_all(names)
		return
	var P := _lane_start()
	_reset()
	# (a) The pick list and its cells.
	var list_ok := true
	var list_detail := ""
	for preset: String in ["A", "B"]:
		var pop: Array = CardPages.page(preset, "orders").get("pop", [])
		list_ok = list_ok and pop == ["pos_hold", "pos_manoeuvre", "pos_roam"]
		list_detail += "%s %s; " % [preset, str(pop)]
	for id: String in ["pos_hold", "pos_manoeuvre", "pos_roam"]:
		var rec: Dictionary = CardPages.cell("orders", id)
		list_ok = list_ok and str(rec.get("kind", "")) == OrderKinds.SET_STANCE and str(rec.get("row", "x")) == ""
	_check(names[0], list_ok, list_detail)
	var ov := CommandOverlay.new()
	ov.world = world
	ov.team = 0
	# (b) Each pick sets the move stance only.
	var sq := _spawn(0, "fighter", 3, P)
	await _ticks(3)
	sq.fire_stance = 2
	sq.formation = 3
	ov.sel_squads = [sq.id]
	var got: Array = []
	for m: int in [0, 2, 1]:
		RSO.set_position(ov, m)
		await _ticks(3)
		got.append(sq.move_stance)
	_check(names[1], got == [0, 2, 1] and sq.fire_stance == 2 and sq.formation == 3, "move stances %s, fire %d, formation %d" % [str(got), sq.fire_stance, sq.formation])
	# (c) The order carries only the move setting.
	RSO.set_position(ov, 2)
	var o: Dictionary = world.orders.last_submitted
	var settings: Dictionary = o.get("settings", {})
	var subjects: Array = o.get("subjects", [])
	_check(names[2], str(o.get("kind", "")) == OrderKinds.SET_STANCE and settings.keys() == ["move"] and int(settings.get("move", -1)) == 2 and subjects.size() == 1 and int(subjects[0]) == sq.id, "order %s" % str(o))
	await _ticks(3)
	# (d) and (e) Two squadrons with different stances take one pick, and the answer line names it.
	_reset()
	var a := _spawn(0, "fighter", 3, P)
	var b := _spawn(0, "fighter", 3, P + Vector2(0.0, 1500.0))
	await _ticks(3)
	a.move_stance = 0
	b.move_stance = 1
	ov.sel_squads = [a.id, b.id]
	RSO.set_position(ov, 2)
	var line := ov.result_text
	await _ticks(3)
	_check(names[3], a.move_stance == 2 and b.move_stance == 2, "stances %d and %d" % [a.move_stance, b.move_stance])
	_check(names[4], line == "Position roam: 2 squadrons", line)
	# (f) With none selected nothing is sent.
	ov.sel_squads = []
	var next_before: int = world.orders.next_id
	var last_before: Dictionary = world.orders.last_submitted
	var why: String = RSO.set_position(ov, 1)
	_check(names[5], why == "Select squadrons first" and ov.result_text == "Select squadrons first" and world.orders.next_id == next_before and is_same(world.orders.last_submitted, last_before), "text '%s', next id %d to %d" % [why, next_before, world.orders.next_id])
	# (g) The brain reads the picked stance at its next think.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	await _ticks(3)
	ov.sel_squads = [sq.id]
	RSO.set_position(ov, 2)
	await _ticks(3)
	TH.think(world, sq)
	var seen_roam := int(sq.engine.get("seen_move", -1))
	RSO.set_position(ov, 0)
	await _ticks(3)
	TH.think(world, sq)
	var seen_hold := int(sq.engine.get("seen_move", -1))
	_check(names[6], seen_roam == 2 and seen_hold == 0, "seen %d then %d" % [seen_roam, seen_hold])
	# (h) A standing goal is left alone.
	_reset()
	sq = _spawn(0, "fighter", 3, P)
	await _ticks(3)
	ov.sel_squads = [sq.id]
	RSO.defend_at(ov, P + Vector2(500.0, 1000.0))
	await _ticks(3)
	var goal_before: Dictionary = sq.goal.duplicate(true)
	RSO.set_position(ov, 2)
	await _ticks(3)
	_check(names[7], not goal_before.is_empty() and sq.goal == goal_before, "goal %s then %s" % [str(goal_before), str(sq.goal)])
	# (i) The words.
	var F: Variant = _cls("data/formations")
	var consts: Dictionary = (F as Script).get_script_constant_map() if F != null else {}
	_check(names[8], consts.get("MOVE_NAMES", []) == ["Hold", "Manoeuvre", "Roam"] and consts.get("MOVE_SUBS", []) == ["stays close", "chases a little", "chases far"], "%s | %s" % [str(consts.get("MOVE_NAMES", [])), str(consts.get("MOVE_SUBS", []))])
	ov.free()


## The order tables: the new kinds are in BOUGHT_KINDS, have their own target kinds and apply at the next tick, and the queue has a handler for each.
func _cases_tables() -> void:
	var kinds: Array = [OrderKinds.DEFEND, OrderKinds.ESCORT, OrderKinds.PUSH_LANE, OrderKinds.MERGE, OrderKinds.SET_STANCE, OrderKinds.SET_FORMATION]
	var all_in := true
	for k: String in kinds:
		all_in = all_in and OrderKinds.BOUGHT_KINDS.has(k) and world.orders.has_applier(k)
	var next_ok := str(OrderKinds.APPLIES[OrderKinds.DEFEND]) == "next" and str(OrderKinds.APPLIES[OrderKinds.PUSH_LANE]) == "next" and str(OrderKinds.APPLIES[OrderKinds.MERGE]) == "next"
	var targets_ok := (OrderKinds.TARGETS[OrderKinds.DEFEND] as Array).has("lane") and (OrderKinds.TARGETS[OrderKinds.PUSH_LANE] as Array).has("lane") and (OrderKinds.TARGETS[OrderKinds.MERGE] as Array).has("squadron")
	_check("item2 tables: Defend, Escort, Push lane, Merge, Stance and Formation are bought kinds with a handler, apply next tick and take their own targets", _built() and all_in and next_ok and targets_ok, "all_in %s next %s targets %s" % [str(all_in), str(next_ok), str(targets_ok)])
	# A stance order never overwrites a standing goal or order.
	if not _built():
		_check("item3 stance: a stance or formation order never overwrites a standing goal or order", false, "the new engine is not in this build")
		return
	_reset()
	var sq := _spawn(0, "fighter", 3, _lane_start())
	await _ticks(3)
	await _order(OrderKinds.DEFEND, [sq.id], "point", Vector2i(_lane_start()))
	await _order(OrderKinds.SET_STANCE, [sq.id], "none", 0, {"fire": 2})
	await _order(OrderKinds.SET_FORMATION, [sq.id], "none", 0, {"formation": 1})
	_check("item3 stance: a stance or formation order never overwrites a standing goal or order", str(sq.goal.get("kind", "")) == OrderKinds.DEFEND and sq.order.is_empty() and sq.fire_stance == 2 and sq.formation == 1)
