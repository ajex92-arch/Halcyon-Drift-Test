extends Node
## WHAT THIS IS: the wing probe. It flies a scripted leader with a wing of three (a Scout, a Fighter and a
## Bomber) through the things a pilot does with a wing and prints, for each, what it measured and whether it
## is inside the range the design set: the launch, a turn at speed, the four shapes, an attack, a guard, a
## hold, a regroup, the leader shot down and relaunched, every refusal, the repeat window, the gestures and
## their order records, the HUD's wing strip, wheel and keys, and the order key (X) with the pause menu: a tap and
## a hold with the card showing, and in Look around, where an order waits for the resume.
##
## HOW IT WORKS: setup() starts one coroutine, _run(), that waits tick by tick (await physics_frame) and
## runs the items one after another. The leader is the human pilot's fighter with a small scripted
## controller in place of the keyboard; every order goes through the real order queue as the pilot's own seat
## (so a replay would take it). Each item prints "PASS <what> <detail>" or "FAIL <what> <detail>", and the
## last line is "wing_probe: N failures".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-admiral-ai --no-jungle --force-hud --seed=7 --test=wing_probe
## --no-pilots and --no-admiral-ai switch off the computer pilots and Admirals, so nothing interferes; the
## probe makes its own leader pilot and gives it the wing (so no --wingmen option is needed).
##
## WHO USES IT: main.gd loads it for --test=wing_probe (it calls setup()); the lead runs it through the queue.

## The leader's scripted controls: full throttle or none, the nose along `heading`.
class Scripted extends RefCounted:
	## The main engine setting, -1 to 1, used when `cruise` is 0.
	var throttle := 0.0
	## When above 0, the speed to hold (world units a second): the throttle follows the speed error.
	var cruise := 0.0
	## Where the nose points (radians).
	var heading := 0.0
	## The leader's aim point; zero = a point ahead.
	var aim := Vector2.ZERO
	## Boost on or off.
	var boost := false
	## True to hold the trigger.
	var fire := false
	## When not INF, fly to this point by the AI pilots' route finder (through the jungle gates).
	var goal := Vector2.INF
	## The brain whose route finder does that (set with `goal`).
	var nav: PilotAI = null

	## The ship calls this every tick, as it does for a keyboard.
	func update(ship: Ship, _dt: float) -> void:
		var c := ship.controls
		if goal != Vector2.INF and nav != null:
			nav.flight.travel(ship, goal, 150.0)
			c.aim_point = c.face_point
			c.fire = false
			c.assist = true
			return
		c.forward = throttle if cruise <= 0.0 else clampf((cruise - ship.velocity.length()) / 80.0, -1.0, 1.0)
		c.strafe = 0.0
		c.boost = boost
		c.face_point = ship.global_position + Vector2.from_angle(heading) * 600.0
		c.aim_point = aim if aim != Vector2.ZERO else c.face_point
		c.fire = fire
		c.assist = true

## The running match (set by setup()).
var world: World
## The human pilot (the leader).
var pilot: PilotProfile
## The leader's ship.
var leader: Ship
## The leader's scripted controls.
var script_ctl := Scripted.new()
## The wing's lead record.
var lead: Squad
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_physics_priority = -100
	world.minion_director.next_wave = INF
	# The leader: a pilot of team 0, seat 0, flying a Fighter, with a Scout, a Fighter and a Bomber behind it.
	pilot = PilotProfile.new("Lead", 0, 0, false)
	pilot.role = "mid"
	pilot.hull_id = "fighter"
	world.profiles.append(pilot)
	Squads.make_wing(world, pilot, PackedStringArray(["scout", "fighter", "bomber"]))
	Events.unit_killed.connect(_on_killed)
	# With --det the determinism test prints its hash lines too, so two runs (or a run and its replay) can be compared.
	if Game.opt("det") != null:
		var det: Node = load("res://tests/det_hash.gd").new()
		add_child(det)
		det.call("setup", w)
	_run()


# --- little helpers ------------------------------------------------------------------------------------

## A unit died: say so when it is the leader or a wingman (where, and who hit it).
func _on_killed(u: Node, info: RefCounted) -> void:
	if not (u is Ship):
		return
	var s := u as Ship
	if s != leader and s.profile != null and s.profile.slot < 200:
		return
	var di := info as DamageInfo
	print("  KILLED %s %s at (%.0f,%.0f) by team %d kind %d src %d" % ["LEADER" if s == leader else "wingman", s.display_name, s.global_position.x, s.global_position.y, di.source_team if di != null else -9, di.kind if di != null else -9, di.source_uid if di != null else -9])


## Print one PASS or FAIL line for the check `what` (`ok` = it passed) with a `detail`.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("%s %s  %s" % ["PASS" if ok else "FAIL", what, detail])


## Like _check, for a check on what the order queue answered to an order the probe itself filed: a replay
## files the logged orders and not the refused ones, so there is nothing to ask and the line says SKIP.
func _check_live(what: String, ok: bool, detail: String = "") -> void:
	if world.orders.replaying:
		print("SKIP %s  (a replay does not file it again)" % what)
		return
	_check(what, ok, detail)


## Wait for `n` ticks of the World.
func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## The wingmen's ships in slot order (null for one that is not flying).
func _wings() -> Array:
	var out: Array = []
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		var crew := Squads.crew_of(world, rec)
		var s: Variant = crew.ship if crew != null else null
		out.append(s if s != null and is_instance_valid(s) and (s as Ship).alive else null)
	return out


## Where slot `i` is right now (the leader's frame as the engine keeps it).
func _slot(i: int) -> Vector2:
	if not is_instance_valid(leader) or not leader.alive:
		return Vector2(1.0e9, 1.0e9)
	var s := SquadEngine.spacing(leader.radius)
	var jungle := SquadEngine.in_jungle(world, leader.global_position)
	var shape := SquadEngine.effective_formation(lead.formation, jungle)
	return SquadEngine.slot_target(leader.global_position, leader.velocity, float(lead.engine.get("hs", leader.rotation)), shape, i, s)


## How far wingman `i` is from its slot (INF when it is not flying).
func _off(i: int) -> float:
	var ships := _wings()
	if ships[i] == null:
		return INF
	return (ships[i] as Ship).global_position.distance_to(_slot(i))


## Put the leader at `pos` heading `heading` with speed `speed` and every wingman in its slot with the same
## velocity (a clean start for an item).
func _place(pos: Vector2, heading: float, speed: float) -> void:
	if not is_instance_valid(leader) or not leader.alive:
		return
	leader.global_position = pos
	leader.rotation = heading
	leader.velocity = Vector2.from_angle(heading) * speed
	script_ctl.heading = heading
	lead.engine["hs"] = heading
	lead.engine["hs_tick"] = world.tick_count
	var ships := _wings()
	for i in ships.size():
		if ships[i] != null:
			var s := ships[i] as Ship
			s.global_position = _slot(i)
			s.rotation = heading
			s.velocity = leader.velocity


## Give the wing a gesture as the pilot's own seat; returns what SquadOrders.send returned.
func _send(name: String, arg: int = 0, aim: Vector2 = Vector2.ZERO) -> Dictionary:
	if world.orders.replaying:
		return {"submitted": true, "text": ""}
	var g := SquadOrders.gesture(world, pilot, name, arg, aim)
	return SquadOrders.send(world, g)


## Give the order queue record `o` (nothing while a replay is playing the logged orders: the replay sends them).
func _submit(o: Dictionary) -> String:
	if world.orders.replaying:
		return ""
	return world.orders.submit(o)


## The first tick count at which `cond` holds for `hold` ticks in a row, within `limit` ticks; -1 when it
## never does.
func _until(cond: Callable, limit: int, hold: int = 30) -> int:
	var run := 0
	for i in limit:
		if bool(cond.call()):
			run += 1
			if run >= hold:
				return i - hold + 1
		else:
			run = 0
		await get_tree().physics_frame
	return -1


# --- the items --------------------------------------------------------------------------------------------

## The start of a straight run in the open lane, west toward our own mothership (the enemy's lane turrets
## stand east of x = 21,000): clear of rocks and enemy guns for 11,000 units.
const START := Vector2(19000.0, 15000.0)
## The heading of that run (radians): west.
const HEADING := PI
## The speed of a cruise (world units a second): under the Fighter's top speed, so a Fighter wingman can keep up.
const CRUISE := 420.0

## How many enemy ships have been made (for their names).
var _foes := 0
## Ships whose hull is filled up every tick, so they live through a fight (a stand-in for a huge hull: the
## ship works its hull maximum out again, so a bigger number set once would not stay).
var _tough: Array = []


## Every tick, before the World's: fill the hull of the tough ships.
func _physics_process(_dt: float) -> void:
	for s: Variant in _tough:
		if s != null and is_instance_valid(s) and (s as Ship).alive:
			(s as Ship).hull = (s as Ship).hull_max


## An enemy ship (team 1) of hull `hull` standing still at `pos`; with `tough` it has a huge hull so it lives.
func _foe(hull: String, pos: Vector2, tough: bool = false) -> Ship:
	var p := PilotProfile.new("Foe%d" % _foes, 1, _foes % 5, false)
	_foes += 1
	p.role = "mid"
	p.hull_id = hull
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = Scripted.new()
	s.global_position = pos
	s.velocity = Vector2.ZERO
	if tough:
		_tough.append(s)
	return s


## A line of facts for a log: the leader's place, speed and hull, and each wingman's distance from its slot,
## state and target.
func _snap(label: String) -> void:
	var line := "%s t=%d" % [label, world.tick_count]
	if is_instance_valid(leader) and leader.alive:
		line += " leader (%.0f,%.0f) v=%.0f hull=%.2f lane=%s" % [leader.global_position.x, leader.global_position.y, leader.velocity.length(), leader.hull_frac(), str(world.map.in_open_lane(leader.global_position))]
	else:
		line += " LEADER GONE"
	var ships := _wings()
	for i in ships.size():
		if ships[i] == null:
			line += " | W%d gone" % i
			continue
		var s := ships[i] as Ship
		var b := s.controller as WingmanAI
		var own := (b._slot(s).distance_to(s.global_position)) if b != null and b.rec != null else -1.0
		line += " | W%d off=%.0f own=%.0f hull=%.2f %s%s" % [i, _off(i), own, s.hull_frac(), b.mode if b != null else "?", (" ->" + (b.target.display_name if b.target != null and is_instance_valid(b.target) else "target")) if b != null and b.target != null else ""]
	print(line)


## Remove an enemy ship quietly.
func _remove(s) -> void:
	if s != null and is_instance_valid(s) and (s as Ship).alive:
		world.combat.kill_silently(s)


## The whole probe, one item after another.
func _run() -> void:
	await _ticks(2)
	# Item (a): the launch. Three wingmen are alive in the same tick as the leader's launch and in
	# their slots after 4 seconds at full throttle (the Scout) or at a cruise (the Fighter).
	leader = world.launch(pilot)
	leader.controller = script_ctl
	_tough.append(leader)
	lead = Squads.lead_record(world, pilot.team, pilot.slot)
	var ships := _wings()
	var alive := 0
	for s: Variant in ships:
		if s != null:
			alive += 1
	_check("(a) three wingmen alive at the leader's launch", alive == 3 and lead != null, "%d alive" % alive)
	script_ctl.throttle = 1.0
	script_ctl.heading = leader.rotation
	await _ticks(240)
	_check("(a) Scout in slot after 4 s at full throttle", _off(0) < 60.0, "%.0f from its slot" % _off(0))
	_check("(a) Fighter not catching up (under 2.5 S) after 4 s at full throttle", not SquadEngine.catching_up(_off(1), SquadEngine.spacing(leader.radius)), "%.0f from its slot" % _off(1))
	print("(a) Fighter %.0f, Bomber %.0f from their slots at full throttle (equal and lower top speed: they trail)" % [_off(1), _off(2)])
	_place(START, HEADING, CRUISE)
	script_ctl.throttle = 0.0
	script_ctl.cruise = CRUISE
	await _ticks(240)
	_check("(a) Scout in slot after 4 s at a cruise", _off(0) < 60.0, "%.0f" % _off(0))
	_check("(a) Fighter in slot after 4 s at a cruise", _off(1) < 60.0, "%.0f" % _off(1))
	# Item (b): a 90 degree turn at speed: the Scout and the Fighter are back in slot within 6 seconds.
	script_ctl.heading = HEADING - PI * 0.5
	var worst := 0.0
	var back := -1
	var calm := 0
	for i in 330:
		worst = maxf(worst, maxf(_off(0), _off(1)))
		if i % 60 == 0:
			_snap("  b")
		if _off(0) < 60.0 and _off(1) < 60.0:
			calm += 1
			if calm >= 30 and back < 0:
				back = i - 29
		else:
			calm = 0
			back = -1
		await get_tree().physics_frame
	_check("(b) Scout and Fighter back in slot within 6 s of a 90 degree turn and staying", back >= 0 and back <= 360, "in slot from %.1f s; worst %.0f off during the turn" % [float(back) / 60.0, worst])
	# Item (c): each shape settles within 6 s and holds for 20 s (95 percent of ticks within 120 of the slot).
	for f in Formations.COUNT:
		_place(START, HEADING, CRUISE)
		script_ctl.heading = HEADING
		await _ticks(30)
		var sent := _send("formation", f)
		await _ticks(2)
		_check("(c) the %s formation order is taken" % Formations.formation_name(f), bool(sent["submitted"]) and str(sent["text"]) == "" and lead.formation == f, str(sent))
		await _ticks(360)
		var good := 0
		for i in 1200:
			if _off(0) < 120.0 and _off(1) < 120.0:
				good += 1
			if i % 240 == 0:
				_snap("  c-%s" % Formations.formation_name(f))
			await get_tree().physics_frame
		_check("(c) %s: Scout and Fighter within 120 of their slots for 95 percent of 20 s" % Formations.formation_name(f), good >= 1140, "%.1f percent" % (float(good) / 12.0))
	await _item_d()
	await _item_e()
	await _item_f()
	await _item_g()
	await _item_h()
	await _item_j()
	await _item_m()
	await _item_l()
	await _item_p()
	_item_n()
	_item_o()
	await _item_beam()
	await _item_i()
	print("wing_probe: %d failures" % fails)
	get_tree().quit()

## A ship of our team (team 0) standing still at `pos`, with a huge hull; `hull` is its hull id.
func _ally(hull: String, pos: Vector2) -> Ship:
	var p := PilotProfile.new("Ally%d" % _foes, 0, 1 + _foes % 4, false)
	_foes += 1
	p.role = "mid"
	p.hull_id = hull
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = Scripted.new()
	s.global_position = pos
	s.velocity = Vector2.ZERO
	_tough.append(s)
	return s


## Wingman `i`'s brain, or null.
func _brain(i: int) -> WingmanAI:
	var ships := _wings()
	if ships[i] == null:
		return null
	return (ships[i] as Ship).controller as WingmanAI


## Does any wingman have `foe` as its target?
func _anyone_targets(foe: Unit) -> bool:
	for i in 3:
		var b := _brain(i)
		if b != null and b.target == foe:
			return true
	return false


## Give the wing back to a calm start: the leader at START cruising, "follow me", every wingman in slot.
func _reset(order_first: bool = true) -> void:
	await _ensure_leader()
	_place(START, HEADING, CRUISE)
	script_ctl.throttle = 0.0
	script_ctl.cruise = CRUISE
	script_ctl.heading = HEADING
	script_ctl.aim = Vector2.ZERO
	if order_first:
		_send("follow")
	await _ticks(10)


## If the leader was lost (a rock, a gun), wait for its respawn and launch it again with its wing.
func _ensure_leader() -> void:
	if is_instance_valid(leader) and leader.alive:
		return
	print("  (the leader was lost: relaunching)")
	await _until(func() -> bool: return pilot.state == "docked", 3600, 1)
	pilot.hull_id = "fighter"
	leader = world.launch(pilot)
	leader.controller = script_ctl
	_tough.append(leader)


## Item (e): ATTACK. The wing engages within 5 s, a Bomber given the order fires, the order lapses to
## follow when the target dies and when the leader is driven 3,200 away.
func _item_e() -> void:
	await _reset()
	script_ctl.cruise = 0.0
	leader.velocity = Vector2.ZERO
	var ahead := Vector2.from_angle(HEADING)
	var foe := _foe("fighter", START + ahead * 1500.0 + Vector2(0, -500), true)
	await _ticks(90)
	var sent := _send("attack", 0, foe.global_position)
	_check("(e) the attack order is taken", bool(sent["submitted"]) and str(sent["text"]) == "", str(sent))
	await _ticks(2)
	_check("(e) the wing's order is ATTACK on the foe", str(lead.order.get("kind")) == OrderKinds.ATTACK and int(lead.order.get("target", 0)) == foe.uid, str(lead.order))
	var engaged := await _until(func() -> bool: return _anyone_targets(foe), 300, 1)
	_check("(e) the wing engages within 5 s", engaged >= 0, "after %.1f s" % (float(engaged) / 60.0))
	await _ticks(240)
	var all := 0
	for i in 3:
		if _brain(i) != null and _brain(i).target == foe:
			all += 1
	_check("(e) all three wingmen fight the target", all == 3, "%d of 3" % all)
	# The tail gun does 3 a hit; a torpedo does far more, so over 30 means the fan was fired.
	var hurt := await _until(func() -> bool: return _bomber_damage(foe) > 30.0, 1800, 1)
	_check("(e) the Bomber wingman given ATTACK fires its fan (a torpedo hits) within 30 s", hurt >= 0, "damage %.0f, after %.1f s" % [_bomber_damage(foe), float(hurt) / 60.0])
	# The leader is driven 3,200 away: the order lapses to follow.
	leader.global_position = foe.global_position - ahead * 3400.0
	await _ticks(60)
	_check("(e) the attack lapses to follow when the leader is 3,200 away", str(lead.order.get("kind")) == OrderKinds.ESCORT, str(lead.order.get("kind")))
	_remove(foe)
	# The target dies: the order lapses.
	await _reset()
	var foe2 := _foe("fighter", START + ahead * 1200.0 + Vector2(0, -400), true)
	await _ticks(90)
	_send("attack", 0, foe2.global_position)
	await _ticks(120)
	_remove(foe2)
	await _ticks(45)
	_check("(e) the attack lapses to follow when the target dies", str(lead.order.get("kind")) == OrderKinds.ESCORT, str(lead.order.get("kind")))


## How much damage the Bomber wingman has dealt to `foe` (its damage log is keyed by the attacker's uid).
func _bomber_damage(foe: Ship) -> float:
	var bship: Variant = _wings()[2]
	if bship == null or foe == null or not is_instance_valid(foe):
		return 0.0
	var e: Array = foe.damage_log.get((bship as Ship).uid, [0.0, 0.0, null])
	return float(e[0])


## Item (f): GUARD on a Destroyer, then on the mothership.
func _item_f() -> void:
	await _reset()
	var ward := _ally("destroyer", START + Vector2(0, -900))
	(ward.controller as Scripted).heading = 0.0
	ward.rotation = 0.0
	script_ctl.cruise = 0.0
	await _ticks(60)
	var sent := _send("guard", 0, ward.global_position)
	_check("(f) the guard order is taken", bool(sent["submitted"]) and str(sent["text"]) == "", str(sent))
	await _ticks(720)
	var cone := SquadEngine.guard_cone(Ships.get_def("destroyer"))
	var good := 0
	var total := 0
	for i in 1200:
		var ok_all := true
		var ships := _wings()
		for k in 3:
			if ships[k] == null:
				ok_all = false
				continue
			var p := (ships[k] as Ship).global_position
			var ang := fposmod(rad_to_deg((p - ward.global_position).angle() - ward.rotation), 360.0)
			var d := p.distance_to(ward.global_position)
			var lo := 180.0 - cone * 0.5 - 10.0
			var hi := 180.0 + cone * 0.5 + 10.0
			if ang < lo or ang > hi or d < 400.0 - 80.0 or d > 600.0 + 80.0:
				ok_all = false
		total += 1
		if ok_all:
			good += 1
		if i % 150 == 0:
			_snap("  f")
			var sh := _wings()
			for k in 3:
				if sh[k] != null:
					var pp := (sh[k] as Ship).global_position
					print("     W%d angle %.0f distance %.0f" % [k, fposmod(rad_to_deg((pp - ward.global_position).angle() - ward.rotation), 360.0), pp.distance_to(ward.global_position)])
		await get_tree().physics_frame
	_check("(f) unengaged, every wingman is in the pocket (+-10 degrees, 320 to 680) for 90 percent of 20 s", good >= 1080, "%.1f percent" % (float(good) / 12.0))
	# An enemy wave attacks the Destroyer.
	var foes: Array[Ship] = []
	for k in 2:
		foes.append(_aggressor(ward.global_position + Vector2(2200.0, -300.0 + 600.0 * k), ward.global_position))
	var t0 := world.tick_count
	var engaged := await _until(func() -> bool: return _any_target_among(foes), 600, 1)
	_check("(f) the wingmen engage the attackers within 5 s", engaged >= 0 and engaged <= 300, "after %.1f s" % (float(engaged) / 60.0))
	var lane_ticks := 0
	for i in 600:
		(ward.controller as Scripted).aim = foes[0].global_position if is_instance_valid(foes[0]) and foes[0].alive else Vector2.ZERO
		var ships := _wings()
		for k in 3:
			if ships[k] != null:
				var c := (ships[k] as Ship).controls
				var b := _brain(k)
				if c.fire and b != null and b.target != null and is_instance_valid(b.target) and SquadEngine.in_fire_lane(ward.global_position, (ward.controller as Scripted).aim, b.target.global_position):
					lane_ticks += 1
		await get_tree().physics_frame
	_check("(f) no wingman fires into the Destroyer's fire lane", lane_ticks == 0, "%d ticks" % lane_ticks)
	for fo in foes:
		_remove(fo)
	(ward.controller as Scripted).aim = Vector2.ZERO
	var resumed := -1
	var run_ok := 0
	for i in 900:
		if _guard_ok(ward, cone):
			run_ok += 1
			if run_ok >= 60 and resumed < 0:
				resumed = i - 59
		else:
			run_ok = 0
		if i % 150 == 0:
			_snap("  f-after")
			var sh2 := _wings()
			for k in 3:
				if sh2[k] != null:
					print("     W%d is %.0f from its guard slot" % [k, (sh2[k] as Ship).global_position.distance_to(SquadEngine.guard_slot(ward.global_position, ward.rotation, ward.radius, cone, k))])
		await get_tree().physics_frame
	_check("(f) the wingmen resume the slots within 10 s after the attackers die", resumed >= 0 and resumed <= 600, "after %.1f s" % (float(resumed) / 60.0))
	_remove(ward)
	# The mothership: flank slots.
	var ms := world.mothership(0)
	leader.global_position = ms.global_position + Vector2.from_angle(ms.rotation) * 1500.0
	leader.velocity = Vector2.ZERO
	script_ctl.cruise = 0.0
	var ship_list := _wings()
	for k in 3:
		if ship_list[k] != null:
			(ship_list[k] as Ship).global_position = ms.global_position + Vector2.from_angle(ms.rotation) * 1500.0
			(ship_list[k] as Ship).velocity = Vector2.ZERO
	await _ticks(30)
	var msent := _send("guard", 0, ms.global_position + Vector2.from_angle(ms.rotation) * 100.0)
	_check("(f) the guard order on the mothership is taken", bool(msent["submitted"]) and str(msent["text"]) == "", str(msent))
	await _ticks(1500)
	var mgood := 0
	for i in 600:
		var ok2 := true
		var ships2 := _wings()
		for k in 3:
			if ships2[k] == null:
				ok2 = false
				continue
			var p2 := (ships2[k] as Ship).global_position
			var want := SquadEngine.mothership_slot(ms.global_position, ms.rotation, ms.half_len, ms.beam, k)
			if p2.distance_to(want) > 120.0:
				ok2 = false
		if ok2:
			mgood += 1
		if i % 150 == 0:
			var sh3 := _wings()
			for k in 3:
				if sh3[k] != null:
					print("     (mothership) W%d is %.0f from its flank slot at (%.0f,%.0f); mothership at (%.0f,%.0f)" % [k, (sh3[k] as Ship).global_position.distance_to(SquadEngine.mothership_slot(ms.global_position, ms.rotation, ms.half_len, ms.beam, k)), (sh3[k] as Ship).global_position.x, (sh3[k] as Ship).global_position.y, ms.global_position.x, ms.global_position.y])
		await get_tree().physics_frame
	_check("(f) on the mothership every wingman is within 120 of its flank slot for 90 percent of 10 s", mgood >= 540, "%.1f percent" % (float(mgood) / 6.0))
	await _reset()


## An enemy fighter with an AI brain that holds `at` and shoots what comes into range, made at `pos`.
func _aggressor(pos: Vector2, at: Vector2) -> Ship:
	var p := PilotProfile.new("Raider%d" % _foes, 1, _foes % 5, false)
	_foes += 1
	p.role = "mid"
	p.hull_id = "fighter"
	world.profiles.append(p)
	var ai := PilotAI.new(world, p)
	world.pilot_ai[p] = ai
	var s := world.launch(p)
	s.global_position = pos
	s.velocity = Vector2.ZERO
	s.rotation = (at - pos).angle()
	ai._reset_after_launch()
	ai.hold_point = at
	return s


## Does any wingman have one of `foes` as its target?
func _any_target_among(foes: Array[Ship]) -> bool:
	for f in foes:
		if is_instance_valid(f) and f.alive and _anyone_targets(f):
			return true
	return false


## Are all three wingmen in the guard pocket of `ward` (slots within 120)?
func _guard_ok(ward: Ship, cone: float) -> bool:
	var ships := _wings()
	for k in 3:
		if ships[k] == null:
			return false
		var want := SquadEngine.guard_slot(ward.global_position, ward.rotation, ward.radius, cone, k)
		if (ships[k] as Ship).global_position.distance_to(want) > 120.0:
			return false
	return true


## Item (g): HOLD. No wingman strays more than 250 from its slot over 20 s with an enemy passing 1,500 away.
func _item_g() -> void:
	await _reset()
	await _ticks(60)
	var sent := _send("hold")
	_check("(g) the hold order is taken", bool(sent["submitted"]) and str(sent["text"]) == "", str(sent))
	await _ticks(2)
	var pt: Vector2i = lead.order.get("target", Vector2i.ZERO)
	var heading := float((lead.order.get("settings", {}) as Dictionary).get("heading", 0))
	var s := SquadEngine.spacing(leader.radius)
	# The leader flies on; an enemy fighter passes 1,500 away from the held point.
	script_ctl.cruise = CRUISE
	var foe := _foe("fighter", Vector2(pt) + Vector2(1500.0, -300.0), true)
	var worst := 0.0
	for i in 1200:
		for k in 3:
			var ships := _wings()
			if ships[k] != null and i >= 180:
				var want := SquadEngine.hold_slot(Vector2(pt), heading, lead.formation, k, s)
				if k < 2:
					worst = maxf(worst, (ships[k] as Ship).global_position.distance_to(want))
		if i % 300 == 0:
			_snap("  g")
		await get_tree().physics_frame
	_check("(g) Scout and Fighter stay within 250 of their hold slots (after 3 s to settle) for 20 s", worst <= 250.0, "worst %.0f" % worst)
	_remove(foe)
	await _reset()


## Item (h): MOVE (regroup). Spread out wingmen with an enemy beside them fire nothing until formed.
func _item_h() -> void:
	await _reset()
	script_ctl.cruise = 0.0
	leader.velocity = Vector2.ZERO
	await _ticks(60)
	var foe := _foe("fighter", START + Vector2(0, 700), true)
	var ships := _wings()
	for k in 3:
		if ships[k] != null:
			(ships[k] as Ship).global_position = START + Vector2(0.0, 700.0 + 250.0 * k) + Vector2(-300.0, 0.0)
	await _ticks(30)
	var sent := _send("regroup")
	_check("(h) the regroup order is taken", bool(sent["submitted"]) and str(sent["text"]) == "", str(sent))
	await _ticks(3)
	var fired := 0
	var formed := -1
	for i in 600:
		var all_in := true
		var ships2 := _wings()
		for k in 3:
			if ships2[k] != null:
				if (ships2[k] as Ship).controls.fire:
					fired += 1
				if _off(k) > 60.0:
					all_in = false
		if all_in and formed < 0:
			formed = i
		if formed >= 0:
			break
		if i >= 360:
			break
		await get_tree().physics_frame
	_check("(h) no shot is fired until formed or 360 ticks", fired == 0, "%d ticks of fire" % fired)
	print("(h) formed after %d ticks" % formed)
	await _until(func() -> bool: return str(lead.order.get("kind")) == OrderKinds.ESCORT, 420, 1)
	_check("(h) the regroup lapses to follow", str(lead.order.get("kind")) == OrderKinds.ESCORT, str(lead.order.get("kind")))
	_remove(foe)
	await _reset()


## Item (j): every refusal reason once, and the repeat window.
func _item_j() -> void:
	await _reset()
	var cursor := world.events_rts.next_index(0)
	var foe := _foe("fighter", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, -300), true)
	await _ticks(90)
	# seat: another seat may not order this wing.
	var other := PilotProfile.new("Other", 0, 3, false)
	var o := Order.make(OrderKinds.ESCORT, 0, 3, true, {"role": "follow"}, [lead.wing_id], "unit", leader.uid)
	var why := _submit(o)
	_check_live("(j) another seat is refused 'Not yours to order'", why == OrderKinds.TEXT_SEAT, why)
	# no wingmen: a pilot with no wing builds no order.
	var g := SquadOrders.gesture(world, other, "follow")
	_check("(j) a pilot with no wing is told 'You have no wingmen'", str(g["text"]) == SquadOrders.TEXT_NO_WING and (g["order"] as Dictionary).is_empty(), str(g["text"]))
	# nothing under the reticle.
	var g2 := SquadOrders.gesture(world, pilot, "attack", 0, START + Vector2(0, 5000))
	_check("(j) attack with no enemy near the reticle: 'No target under the reticle'", str(g2["text"]) == SquadOrders.TEXT_NO_TARGET, str(g2["text"]))
	var g3 := SquadOrders.gesture(world, pilot, "guard", 0, START + Vector2(0, 5000))
	_check("(j) guard with no big ship near the reticle: 'No big ship under the reticle'", str(g3["text"]) == SquadOrders.TEXT_NO_BIG, str(g3["text"]))
	# not in sight: an enemy the team cannot see.
	var hidden := _foe("fighter", START + Vector2(0, 9000), true)
	hidden.visible_mask = 0
	var o2 := Order.make(OrderKinds.ATTACK, 0, 0, true, {}, [lead.wing_id], "unit", hidden.uid)
	var why2 := _submit(o2)
	_check_live("(j) an unseen target is refused 'Target not in sight'", why2 == SquadOrders.TEXT_NOT_SEEN, why2)
	# too far: seen, but more than 3,200 from the leader.
	hidden.visible_mask = 3
	var o3 := Order.make(OrderKinds.ATTACK, 0, 0, true, {}, [lead.wing_id], "unit", hidden.uid)
	var why3 := _submit(o3)
	_check_live("(j) a target 3,200 away is refused 'Too far for the wing'", why3 == SquadOrders.TEXT_FAR, why3)
	var ward := _ally("destroyer", START + Vector2(0, 9000))
	var o4 := Order.make(OrderKinds.GUARD, 0, 0, true, {}, [lead.wing_id], "unit", ward.uid)
	var why4 := _submit(o4)
	_check_live("(j) a ward 3,200 away is refused 'Too far for the wing'", why4 == SquadOrders.TEXT_FAR, why4)
	var o5 := Order.make(OrderKinds.GUARD, 0, 0, true, {}, [lead.wing_id], "unit", foe.uid)
	var why5 := _submit(o5)
	_check_live("(j) guarding an enemy is refused 'No big ship under the reticle'", why5 == SquadOrders.TEXT_NO_BIG, why5)
	# a duplicate within 30 ticks is dropped at apply, logged, with no toast.
	var before := lead.order.duplicate(true)
	var s1 := _send("regroup")
	var s2 := _send("regroup")
	await _ticks(3)
	var dup_seen := false
	for ev: Dictionary in world.events_rts.read_from(0, cursor):
		if str(ev["kind"]) == "order_refused" and str((ev["data"] as Dictionary).get("reason", "")) == "duplicate":
			dup_seen = true
	_check("(j) the first regroup is taken", bool(s1["submitted"]) and str(s1["text"]) == "", str(s1))
	_check("(k) a repeat within 30 ticks is dropped at apply and filed as 'duplicate'", bool(s2["submitted"]) and dup_seen, "event seen: %s" % str(dup_seen))
	print("(j) the order before the repeat: %s" % str(before.get("kind")))
	_remove(foe)
	_remove(hidden)
	_remove(ward)
	await _reset()


## Item (m): each gesture builds the exact record and goes through the order queue.
func _item_m() -> void:
	await _reset()
	var foe := _foe("fighter", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, -300), true)
	var ward := _ally("destroyer", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, 500))
	await _ticks(90)
	var wid := lead.wing_id
	var want_follow := Order.make(OrderKinds.ESCORT, 0, 0, true, {"role": "follow"}, [wid], "unit", leader.uid)
	var want_cover := Order.make(OrderKinds.ESCORT, 0, 0, true, {"role": "defend"}, [wid], "unit", leader.uid)
	var want_attack := Order.make(OrderKinds.ATTACK, 0, 0, true, {}, [wid], "unit", foe.uid)
	var want_guard := Order.make(OrderKinds.GUARD, 0, 0, true, {}, [wid], "unit", ward.uid)
	var want_hold := Order.make(OrderKinds.HOLD, 0, 0, true, {"heading": posmod(roundi(rad_to_deg(leader.rotation)), 360)}, [wid], "point", Order.point(leader.global_position))
	var want_move := Order.make(OrderKinds.MOVE, 0, 0, true, {}, [wid], "unit", leader.uid)
	_gesture_is("tap on an enemy", "tap", 0, foe.global_position, want_attack)
	_gesture_is("tap on our big ship", "tap", 0, ward.global_position, want_guard)
	_gesture_is("tap over nothing", "tap", 0, START + Vector2(0, 6000), want_follow)
	_gesture_is("wheel: form on me", "follow", 0, Vector2.ZERO, want_follow)
	_gesture_is("wheel: cover me", "cover", 0, Vector2.ZERO, want_cover)
	_gesture_is("wheel: attack my target", "attack", 0, foe.global_position, want_attack)
	_gesture_is("wheel: guard that ship", "guard", 0, ward.global_position, want_guard)
	_gesture_is("wheel: hold here", "hold", 0, Vector2.ZERO, want_hold)
	_gesture_is("wheel: regroup", "regroup", 0, Vector2.ZERO, want_move)
	for n in 4:
		_gesture_is("formation chip %d" % n, "formation", n, Vector2.ZERO, Order.make(OrderKinds.SET_FORMATION, 0, 0, true, {"formation": n}, [wid]))
	for n in 3:
		_gesture_is("fire chip %d" % n, "fire", n, Vector2.ZERO, Order.make(OrderKinds.SET_STANCE, 0, 0, true, {"fire": n}, [wid]))
	lead.formation = 3
	_gesture_is("next formation from Loose wraps to Wedge", "next_formation", 0, Vector2.ZERO, Order.make(OrderKinds.SET_FORMATION, 0, 0, true, {"formation": 0}, [wid]))
	lead.fire_stance = 2
	_gesture_is("next fire setting from Hold fire wraps to At will", "next_fire", 0, Vector2.ZERO, Order.make(OrderKinds.SET_STANCE, 0, 0, true, {"fire": 0}, [wid]))
	lead.formation = 0
	lead.fire_stance = 0
	# And the queue got exactly that record.
	var g := SquadOrders.gesture(world, pilot, "tap", 0, foe.global_position)
	if not world.orders.replaying:
		SquadOrders.send(world, g)
	var last := world.orders.last_submitted
	_check_live("(m) the tap's record is the one the order queue was given", str(last.get("kind")) == OrderKinds.ATTACK and int(last.get("target", 0)) == foe.uid and int(last.get("seat", -1)) == 0 and bool(last.get("human", false)), str(last.get("kind")))
	await _ticks(3)
	_check("(m) the wing carries the order out", str(lead.order.get("kind")) == OrderKinds.ATTACK, str(lead.order.get("kind")))
	_remove(foe)
	_remove(ward)
	await _reset()


## Compare gesture `name` with the record `want` (ids and ticks left out).
func _gesture_is(what: String, name: String, arg: int, aim: Vector2, want: Dictionary) -> void:
	var g := SquadOrders.gesture(world, pilot, name, arg, aim)
	var got: Dictionary = g["order"]
	var same := not got.is_empty()
	for key in ["team", "seat", "human", "kind", "subjects", "target_kind", "target", "mode", "settings"]:
		if not got.has(key) or str(got[key]) != str(want[key]):
			same = false
	_check("(m) %s builds the exact record" % what, same, "got %s" % str(got) if not same else "")


## Item (i): the leader is shot down: every wingman docks within 60 s; the leader relaunches and the wingmen
## are beside it at once.
func _item_i() -> void:
	await _reset()
	await _ticks(60)
	var cursor := world.events_rts.next_index(0)
	world.combat.kill_silently(leader)
	await _ticks(2)
	var home_event := false
	for ev: Dictionary in world.events_rts.read_from(0, cursor):
		if str(ev["kind"]) == Squads.EVENT_HOME:
			home_event = true
	_check("(i) the 'wing heading home' event is filed", home_event)
	var docked := await _until(func() -> bool: return _crews_docked(), 3600, 1)
	_check("(i) every wingman docks within 60 s", docked >= 0, "after %.1f s" % (float(docked) / 60.0))
	var back := await _until(func() -> bool: return pilot.state == "docked", 3600, 1)
	print("(i) the leader's respawn took %.1f s" % (float(back) / 60.0))
	pilot.hull_id = "fighter"
	leader = world.launch(pilot)
	leader.controller = script_ctl
	_tough.append(leader)
	var near := 0
	var ships := _wings()
	for k in 3:
		if ships[k] != null and _off(k) < 100.0:
			near += 1
	_check("(i) the leader relaunches and all three wingmen are in their slots at once", near == 3, "%d in slot" % near)
	await _ticks(300)
	_snap("  i")


## Are all the wing's crew docked?
func _crews_docked() -> bool:
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		var crew := Squads.crew_of(world, rec)
		if crew != null and crew.state != "docked":
			return false
	return true

## A key event for `code` (pressed or let go), with Shift held when `shift` is true.
func _key(code: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	ev.shift_pressed = shift
	return ev


## A press and a release of key `code` at once (a tap), through the HUD's key router.
func _tap_key(hud: Hud, code: Key, shift: bool = false) -> void:
	hud.router.handle(_key(code, true, shift))
	hud.router.handle(_key(code, false, shift))


## The text the probe puts in the HUD's pop-up before it acts, so a pop-up that shows afterwards (a refusal, a
## confirmation) can be told from it.
const MARK := "(probe)"


## Wait `ms` real milliseconds on the clock the order key times itself with (Time.get_ticks_msec), a frame at a
## time, then two frames more so the HUD's own frame has run. It works while the game is paused and does not depend
## on the time scale or on how fast the frames come (a windowless run with --fixed-fps takes them as fast as it can).
func _real_wait(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


## While the game is paused: wait 300 real milliseconds and five physics frames, so a tick that should not come has
## the time to.
func _paused_wait() -> void:
	await _real_wait(300)
	await _ticks(5)


## Move the mouse to the HUD point `p` (pixels) as a real mouse does, and let two frames deliver it.
func _mouse_to(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * p
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


## Is the HUD's pop-up a refusal (the danger look) that is not the probe's own mark?
func _refused(hud: Hud) -> bool:
	return hud.toast_box._danger and hud.toast_box._label.text != MARK


## How many "order_done" events of the order kind `kind` team 0 has filed since the stream position `cursor`.
func _done_since(cursor: int, kind: String) -> int:
	var n := 0
	for ev: Dictionary in world.events_rts.read_from(0, cursor):
		if str(ev["kind"]) == "order_done" and str((ev["data"] as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


## Was a regroup (MOVE) carried out since the stream position `cursor`? The queue must have filed exactly one MOVE, and the
## wing's order is MOVE or the "follow me" it lapses to. A regroup ends at the first scheduled think after every wingman
## reports being in its place, so a wing that already stands in its places ends it a few ticks after the key, and when
## that falls before the read depends only on the tick the key came on, not on the key.
func _regroup_taken(cursor: int) -> bool:
	if _done_since(cursor, OrderKinds.MOVE) != 1:
		return false
	var kind := str(lead.order.get("kind"))
	var role := str((lead.order.get("settings", {}) as Dictionary).get("role", ""))
	return kind == OrderKinds.MOVE or (kind == OrderKinds.ESCORT and role == "follow")


## Item (l): the HUD's strip and wheel, the tap and the hold, every slice and chip, the pop-ups and preset B's keys
## (needs --force-hud).
func _item_l() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("(l) the HUD exists (run with --force-hud)", false)
		return
	await _reset()
	world.human = pilot
	world.human_role = "pilot"
	script_ctl.cruise = 0.0
	leader.velocity = Vector2.ZERO
	var foe := _foe("fighter", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, -300), true)
	var ward := _ally("destroyer", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, 500))
	await _ticks(90)
	hud._refresh()
	_check("(l) the wing strip shows with a wing and a ship", hud.wing_strip.visible)
	var names := PackedStringArray()
	for i in 3:
		names.append(str((hud.wing_strip.chips[i] as Dictionary).get("name", "-")))
	_check("(l) the chips read Scout, Fighter, Bomber", names == PackedStringArray(["Scout", "Fighter", "Bomber"]), ",".join(names))
	_check("(l) the strip is a child of the ship readout (it follows the layout)", hud.wing_strip.get_parent() == hud.status)
	# The wheel's geometry: every slice and every chip is found at its own place; the middle and the outside are nothing.
	var wheel := hud.wing_wheel
	wheel.open_at(Vector2(640.0, 330.0), foe.global_position)
	_check("(l) the wheel opens and freezes the aim (wheel_hold)", wheel.is_open and world.wheel_hold)
	for i in 6:
		var mid := deg_to_rad(-90.0 + 60.0 * float(i))
		var hit := wheel.hit_at(wheel.center + Vector2.from_angle(mid) * 68.0)
		_check("(l) the slice %d is %s" % [i, str((WingWheel.SLICES[i] as Array)[0])], str(hit.get("name", "")) == str((WingWheel.SLICES[i] as Array)[0]), str(hit))
	for i in 4:
		_check("(l) shape chip %d is found" % i, str(wheel.hit_at(wheel.shape_chip(i).get_center()).get("name", "")) == "formation" and int(wheel.hit_at(wheel.shape_chip(i).get_center()).get("arg", -1)) == i)
	for i in 3:
		_check("(l) fire chip %d is found" % i, str(wheel.hit_at(wheel.fire_chip(i).get_center()).get("name", "")) == "fire" and int(wheel.hit_at(wheel.fire_chip(i).get_center()).get("arg", -1)) == i)
	_check("(l) the dead zone and the outside are nothing", wheel.hit_at(wheel.center).is_empty() and wheel.hit_at(wheel.center + Vector2(300.0, -300.0)).is_empty())
	_check("(l) the wheel's chips are 14 px text or more and clear the window at 1280x720", WingWheel.TEXT_SIZE >= 14 and wheel.fire_chip(2).end.y <= 720.0 and wheel.fire_chip(0).position.x >= 0.0)
	print("(l) a UI dump of the HUD with the wheel open follows")
	const UiDump := preload("res://tests/lib/ui_dump.gd")
	UiDump.dump(hud, "wing_wheel", false)
	wheel.close()
	_check("(l) closing the wheel lets the aim go again", not wheel.is_open and not world.wheel_hold)
	# Every slice and chip applies when clicked.
	script_ctl.aim = Vector2.ZERO
	for i in 6:
		var mid2 := deg_to_rad(-90.0 + 60.0 * float(i))
		wheel.open_at(Vector2(640.0, 330.0), foe.global_position if i == 2 else ward.global_position, true)
		var cursor_w := world.events_rts.next_index(0)
		wheel.click_at(wheel.center + Vector2.from_angle(mid2) * 68.0)
		await _ticks(3)
		var want := [OrderKinds.ESCORT, OrderKinds.ESCORT, OrderKinds.ATTACK, OrderKinds.GUARD, OrderKinds.HOLD, OrderKinds.MOVE][i] as String
		var slice_ok := _regroup_taken(cursor_w) if want == OrderKinds.MOVE else str(lead.order.get("kind")) == want
		_check("(l) clicking the slice %d carries out %s" % [i, want], slice_ok, str(lead.order.get("kind")))
		await _ticks(35)
		hud.toast_box.hide()
	_check("(l) Cover me stored the data word 'defend' (the wheel's own label stays Cover me)", str(SquadOrders.ROLE_LABELS["defend"]) == "Cover me")
	for i in 4:
		wheel.open_at(Vector2(640.0, 330.0), Vector2.ZERO, true)
		wheel.click_at(wheel.shape_chip(i).get_center())
		await _ticks(3)
		_check("(l) clicking the %s chip sets the formation" % Formations.formation_name(i), lead.formation == i, str(lead.formation))
		await _ticks(35)
	for i in 3:
		wheel.open_at(Vector2(640.0, 330.0), Vector2.ZERO, true)
		wheel.click_at(wheel.fire_chip(i).get_center())
		await _ticks(3)
		_check("(l) clicking the %s chip sets the fire setting" % str(Formations.FIRE_NAMES[i]), lead.fire_stance == i, str(lead.fire_stance))
		await _ticks(35)
	await _ticks(3)
	_check("(l) the carried-out order is confirmed by a pop-up", hud.toast_box._label.text.begins_with("Wing: "), hud.toast_box._label.text)
	wheel.open_at(Vector2(640.0, 330.0), Vector2.ZERO, true)
	wheel.click_at(Vector2(5.0, 5.0))
	_check("(l) a click outside closes the click wheel", not wheel.is_open)
	# A refusal is a pop-up in the danger colour with the triangle.
	hud.wing_command("attack", 0, START + Vector2(0, 6000))
	_check("(l) a refusal is a danger pop-up with the text 'No target under the reticle'", hud.toast_box._label.text == SquadOrders.TEXT_NO_TARGET and hud.toast_box._danger, hud.toast_box._label.text)
	# The tap and the hold through the key router.
	await _ticks(35)
	script_ctl.aim = foe.global_position
	await _ticks(2)
	_tap_key(hud, KEY_X)
	await _ticks(3)
	_check("(l) tap X on an enemy: the wing attacks it", str(lead.order.get("kind")) == OrderKinds.ATTACK and int(lead.order.get("target", 0)) == foe.uid, str(lead.order.get("kind")))
	await _ticks(35)
	script_ctl.aim = ward.global_position
	await _ticks(2)
	_tap_key(hud, KEY_X)
	await _ticks(3)
	_check("(l) tap X on our big ship: the wing guards it", str(lead.order.get("kind")) == OrderKinds.GUARD and int(lead.order.get("target", 0)) == ward.uid, str(lead.order.get("kind")))
	await _ticks(35)
	script_ctl.aim = START + Vector2(0, 6000)
	await _ticks(2)
	_tap_key(hud, KEY_X)
	await _ticks(3)
	_check("(l) tap X over nothing: the wing forms on the leader", str(lead.order.get("kind")) == OrderKinds.ESCORT and str((lead.order.get("settings", {}) as Dictionary).get("role")) == "follow", str(lead.order))
	await _ticks(35)
	# The mouse's fifth button is the same key.
	var m5 := InputEventMouseButton.new()
	m5.button_index = MOUSE_BUTTON_XBUTTON2
	m5.pressed = true
	script_ctl.aim = foe.global_position
	await _ticks(2)
	hud.router.handle(m5)
	var m5up := InputEventMouseButton.new()
	m5up.button_index = MOUSE_BUTTON_XBUTTON2
	m5up.pressed = false
	hud.router.handle(m5up)
	await _ticks(3)
	_check("(l) a tap of the mouse's fifth button is the same as X", str(lead.order.get("kind")) == OrderKinds.ATTACK, str(lead.order.get("kind")))
	await _ticks(35)
	# A hold opens the wheel after 130 ms and Esc closes it with no order.
	var before := str(lead.order.get("kind"))
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(400)
	_check("(l) holding X opens the wheel after a moment and freezes the aim", wheel.is_open and world.wheel_hold)
	hud.router.handle(_key(KEY_ESCAPE, true))
	_check("(l) Esc closes the wheel and gives no order", not wheel.is_open and not world.wheel_hold and str(lead.order.get("kind")) == before)
	hud.router.handle(_key(KEY_X, false))
	await _real_wait(200)
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(400)
	hud.router.handle(_key(KEY_X, false))
	_check("(l) letting go in the dead zone gives no order and closes the wheel", not wheel.is_open and not world.wheel_hold and str(lead.order.get("kind")) == before)
	# Key preset B: the eight keys build the exact records; with preset A they do nothing.
	await _ticks(35)
	_tap_key(hud, KEY_Y)
	await _ticks(3)
	_check("(l) preset A: Y does nothing", str(lead.order.get("kind")) == before)
	KeyMap.set_preset("wing_commands", "B")
	script_ctl.aim = foe.global_position
	var steps := [[KEY_Y, false, OrderKinds.ESCORT, "follow"], [KEY_U, false, OrderKinds.ESCORT, "defend"], [KEY_I, false, OrderKinds.ATTACK, ""],
		[KEY_K, false, OrderKinds.HOLD, ""], [KEY_L, false, OrderKinds.MOVE, ""]]
	for st: Array in steps:
		await _ticks(35)
		var cursor_k := world.events_rts.next_index(0)
		_tap_key(hud, st[0] as Key, bool(st[1]))
		await _ticks(3)
		var order: Dictionary = lead.order
		var ok := str(order.get("kind")) == str(st[2]) and ((st[3] as String) == "" or str((order.get("settings", {}) as Dictionary).get("role")) == str(st[3]))
		if str(st[2]) == OrderKinds.MOVE:
			ok = _regroup_taken(cursor_k)
		_check("(l) preset B key %s carries out %s %s" % [OS.get_keycode_string(st[0] as Key), str(st[2]), str(st[3])], ok, str(order))
	await _ticks(35)
	script_ctl.aim = ward.global_position
	await _ticks(2)
	_tap_key(hud, KEY_O)
	await _ticks(3)
	_check("(l) preset B key O guards the ship under the reticle", str(lead.order.get("kind")) == OrderKinds.GUARD and int(lead.order.get("target", 0)) == ward.uid, str(lead.order.get("kind")))
	lead.formation = 1
	await _ticks(35)
	_tap_key(hud, KEY_N)
	await _ticks(3)
	_check("(l) preset B key N sends the next formation as an explicit value (Line -> Column)", lead.formation == 2, str(lead.formation))
	lead.fire_stance = 0
	await _ticks(35)
	_tap_key(hud, KEY_N, true)
	await _ticks(3)
	_check("(l) preset B key Shift+N sends the next fire setting as an explicit value (At will -> Return fire)", lead.fire_stance == 1, str(lead.fire_stance))
	KeyMap.set_preset("wing_commands", "A")
	# The pilot's key line shows the order key.
	hud._refresh()
	_check("(l) the pilot's key line shows the order key", hud.slots._keys.text.contains("wing orders"), hud.slots._keys.text)
	_remove(foe)
	_remove(ward)
	world.human = null
	world.human_role = "spectator"
	await _reset()


## Item (p): the order key (X) with the pause menu (needs --force-hud). (1) Unpaused, a tap gives an order and it is
## carried out within a few ticks. (2) Under the pause card a tap and a hold give nothing and the wheel does not
## open. (3) In Look around (the card hidden, the game paused) a tap is accepted with no refusal, waits while the game
## is paused and is carried out on the first ticks after the resume. (4) In Look around a hold opens the wheel, and
## letting go over a slice queues that order, which is carried out after the resume. (5) Esc with the wheel open
## closes the wheel and stays in the look-around; the next Esc brings the card back. Times are real milliseconds.
func _item_p() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("(p) the HUD exists (run with --force-hud)", false)
		return
	await _reset()
	world.human = pilot
	world.human_role = "pilot"
	script_ctl.cruise = 0.0
	leader.velocity = Vector2.ZERO
	var foe := _foe("fighter", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, -300), true)
	var ward := _ally("destroyer", START + Vector2.from_angle(HEADING) * 900.0 + Vector2(0, 500))
	await _ticks(90)
	hud._refresh()
	var wheel := hud.wing_wheel
	await _mouse_to(Vector2(640.0, 330.0))
	var mouse_now := hud.get_viewport().get_mouse_position()
	_check("(p) the probe's mouse is where it was put (the mouse moves in this run)", mouse_now.distance_to(Vector2(640.0, 330.0)) < 2.0, str(mouse_now))
	# Step 1, the control: unpaused, a tap of X (press and let go at once, the mouse still) sends a wing order.
	_check("(p) step 1: in flight the order key is ready", hud.wing_ready())
	script_ctl.aim = foe.global_position
	await _ticks(2)
	hud.toast_box.show_text(MARK)
	world.orders.last_submitted = {}
	var cursor1 := world.events_rts.next_index(0)
	_tap_key(hud, KEY_X)
	var rec1: Dictionary = world.orders.last_submitted
	_check("(p) step 1: unpaused, a tap of X sends an ATTACK order and shows no refusal", int(rec1.get("id", 0)) > 0 and str(rec1.get("kind", "")) == OrderKinds.ATTACK and not _refused(hud), "%s, pop-up '%s'" % [str(rec1.get("kind", "no order")), hud.toast_box._label.text])
	await _ticks(3)
	_check("(p) step 1: the order is carried out within a few ticks", str(lead.order.get("kind")) == OrderKinds.ATTACK and int(lead.order.get("target", 0)) == foe.uid and _done_since(cursor1, OrderKinds.ATTACK) == 1, "%s, %d order_done" % [str(lead.order.get("kind")), _done_since(cursor1, OrderKinds.ATTACK)])
	# Step 2, the pause card showing: a tap and a hold give nothing, the wheel stays shut.
	await _ticks(35)
	script_ctl.aim = ward.global_position
	await _ticks(2)
	hud._toggle_pause_menu()
	var menu := hud.pause_menu
	_check("(p) step 2: the Menu route opens the pause card and pauses the game", menu != null and menu.visible and menu.active and not menu.looking and get_tree().paused)
	_check("(p) step 2: under the card the order key is not ready", not hud.wing_ready())
	hud.toast_box.show_text(MARK)
	world.orders.last_submitted = {}
	_tap_key(hud, KEY_X)
	_check("(p) step 2: a tap of X under the card gives no order and no pop-up", world.orders.last_submitted.is_empty() and world.orders.queue.is_empty() and hud.toast_box._label.text == MARK, str(world.orders.last_submitted.get("kind", "no order")))
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(350)
	_check("(p) step 2: a hold of X under the card does not open the wheel", not wheel.is_open and not world.wheel_hold and hud.router._wheel_down < 0, "open %s, wheel_hold %s" % [wheel.is_open, world.wheel_hold])
	hud.router.handle(_key(KEY_X, false))
	_check("(p) step 2: letting go of X under the card gives no order", world.orders.last_submitted.is_empty() and world.orders.queue.is_empty() and hud.toast_box._label.text == MARK)
	# Step 3, Look around: a tap is accepted, waits while paused, and is carried out after the resume.
	menu.look_around()
	await _ticks(2)
	_check("(p) step 3: Look around hides the card, keeps the session and the pause", menu.looking and menu.active and not menu.visible and get_tree().paused, "looking %s, active %s, card visible %s, paused %s" % [menu.looking, menu.active, menu.visible, get_tree().paused])
	_check("(p) step 3: while looking around the order key is ready", hud.wing_ready())
	var t_pause := world.tick_count
	var kind_before := str(lead.order.get("kind"))
	var cursor3 := world.events_rts.next_index(0)
	hud.toast_box.show_text(MARK)
	world.orders.last_submitted = {}
	_tap_key(hud, KEY_X)
	var rec3: Dictionary = world.orders.last_submitted
	_check("(p) step 3: a tap of X while looking around is accepted (a GUARD order) and shows no refusal", int(rec3.get("id", 0)) > 0 and str(rec3.get("kind", "")) == OrderKinds.GUARD and not _refused(hud), "%s, pop-up '%s'" % [str(rec3.get("kind", "no order")), hud.toast_box._label.text])
	await _paused_wait()
	_check("(p) step 3: while still paused the order waits (the clock stands still, nothing carried out)", world.tick_count == t_pause and world.orders.queue.size() == 1 and str(lead.order.get("kind")) == kind_before and _done_since(cursor3, OrderKinds.GUARD) == 0, "tick %d -> %d, %d queued, order %s, %d order_done" % [t_pause, world.tick_count, world.orders.queue.size(), str(lead.order.get("kind")), _done_since(cursor3, OrderKinds.GUARD)])
	_tap_key(hud, KEY_P)
	_check("(p) step 3: P resumes the match", not get_tree().paused and not menu.active and not menu.looking)
	var got3 := await _until(func() -> bool: return str(lead.order.get("kind")) == OrderKinds.GUARD, 8, 1)
	_check("(p) step 3: after the resume the order is carried out on the first ticks", got3 >= 0 and got3 <= 4 and int(lead.order.get("target", 0)) == ward.uid and _done_since(cursor3, OrderKinds.GUARD) == 1, "after %d ticks, apply_tick %d (paused at %d), %d order_done" % [got3, int(rec3.get("apply_tick", -1)), t_pause, _done_since(cursor3, OrderKinds.GUARD)])
	_check("(p) step 3: the carried-out order is confirmed by a pop-up", hud.toast_box._label.text.begins_with("Wing: "), hud.toast_box._label.text)
	# Step 4, Look around, the hold: the wheel opens while paused, letting go over a slice queues the order.
	await _ticks(35)
	hud._toggle_pause_menu()
	menu.look_around()
	await _mouse_to(Vector2(640.0, 330.0))
	var t4 := world.tick_count
	var kind4 := str(lead.order.get("kind"))
	var cursor4 := world.events_rts.next_index(0)
	hud.toast_box.show_text(MARK)
	world.orders.last_submitted = {}
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(350)
	_check("(p) step 4: holding X while looking around opens the wheel and the game stays paused", wheel.is_open and world.wheel_hold and menu.looking and get_tree().paused, "open %s, wheel_hold %s, looking %s, paused %s" % [wheel.is_open, world.wheel_hold, menu.looking, get_tree().paused])
	var slice_at := wheel.center + Vector2.from_angle(deg_to_rad(-90.0 + 60.0 * 4.0)) * 68.0
	await _mouse_to(slice_at)
	var over := wheel.hovered()
	_check("(p) step 4: the mouse is over the 'hold here' slice", str(over.get("name", "")) == "hold", "%s at %s (wheel at %s)" % [str(over), str(hud.get_viewport().get_mouse_position()), str(wheel.center)])
	hud.router.handle(_key(KEY_X, false))
	var rec4: Dictionary = world.orders.last_submitted
	_check("(p) step 4: letting go closes the wheel and queues a HOLD order, with no refusal", not wheel.is_open and not world.wheel_hold and int(rec4.get("id", 0)) > 0 and str(rec4.get("kind", "")) == OrderKinds.HOLD and not _refused(hud), "open %s, order %s, pop-up '%s'" % [wheel.is_open, str(rec4.get("kind", "no order")), hud.toast_box._label.text])
	await _paused_wait()
	_check("(p) step 4: while still paused the held order waits (the clock stands still, nothing carried out)", world.tick_count == t4 and world.orders.queue.size() == 1 and str(lead.order.get("kind")) == kind4 and _done_since(cursor4, OrderKinds.HOLD) == 0, "tick %d -> %d, %d queued, order %s, %d order_done" % [t4, world.tick_count, world.orders.queue.size(), str(lead.order.get("kind")), _done_since(cursor4, OrderKinds.HOLD)])
	_tap_key(hud, KEY_P)
	var got4 := await _until(func() -> bool: return str(lead.order.get("kind")) == OrderKinds.HOLD, 8, 1)
	_check("(p) step 4: after the resume the held order is carried out on the first ticks", not get_tree().paused and got4 >= 0 and got4 <= 4 and _done_since(cursor4, OrderKinds.HOLD) == 1, "after %d ticks, apply_tick %d (paused at %d), %d order_done" % [got4, int(rec4.get("apply_tick", -1)), t4, _done_since(cursor4, OrderKinds.HOLD)])
	# Step 5, Esc with the wheel open while looking around: the wheel closes first and the look-around stays.
	await _ticks(35)
	hud._toggle_pause_menu()
	menu.look_around()
	await _mouse_to(Vector2(640.0, 330.0))
	hud.router.handle(_key(KEY_X, true))
	await _real_wait(350)
	_check("(p) step 5: the wheel is open in the look-around before Esc", wheel.is_open and menu.looking and not menu.visible and get_tree().paused)
	world.orders.last_submitted = {}
	hud.router.handle(_key(KEY_ESCAPE, true))
	hud.router.handle(_key(KEY_ESCAPE, false))
	_check("(p) step 5: Esc closes the wheel first", not wheel.is_open and not world.wheel_hold, "open %s, wheel_hold %s" % [wheel.is_open, world.wheel_hold])
	_check("(p) step 5: and the look-around stays (the card hidden, the game paused, no order)", menu.looking and menu.active and not menu.visible and get_tree().paused and world.orders.last_submitted.is_empty(), "looking %s, card visible %s, paused %s, order %s" % [menu.looking, menu.visible, get_tree().paused, str(world.orders.last_submitted.get("kind", "no order"))])
	hud.router.handle(_key(KEY_X, false))
	_check("(p) step 5: letting go of X afterwards gives no order", world.orders.last_submitted.is_empty() and world.orders.queue.is_empty(), str(world.orders.last_submitted.get("kind", "no order")))
	hud.router.handle(_key(KEY_ESCAPE, true))
	hud.router.handle(_key(KEY_ESCAPE, false))
	_check("(p) step 5: the next Esc brings the card back (the game stays paused)", menu.visible and menu.active and not menu.looking and get_tree().paused, "card visible %s, looking %s, active %s, paused %s" % [menu.visible, menu.looking, menu.active, get_tree().paused])
	# Put everything back: the wheel shut, no key held, the game running, the human gone.
	wheel.close()
	hud.router._wheel_down = -1
	if menu.active:
		_tap_key(hud, KEY_P)
	get_tree().paused = false
	await _ticks(40)
	hud.toast_box.hide()
	_remove(foe)
	_remove(ward)
	world.human = null
	world.human_role = "spectator"
	await _reset()


## Item (n): the start screen's two switches: first-run defaults, and a run with no start screen reads no file.
func _item_n() -> void:
	_check("(n) a run with no start screen and no option has no wings for anybody", Game.wing_hulls_for(true).is_empty() and Game.wing_hulls_for(false).is_empty())
	var test_before := Game.test_wing
	var cpu_before := Game.cpu_wings
	var test_open := Game._test_wing_open
	var cpu_open := Game._cpu_wings_open
	_check("(n) nothing has read the settings file yet", Game._test_wing_open and Game._cpu_wings_open, "open flags %s %s" % [Game._test_wing_open, Game._cpu_wings_open])
	var marker := str(Game.opt("settings-check", ""))
	var dir := OS.get_user_data_dir()
	if marker == "" or not dir.contains(marker):
		print("(n) the remembered-setting writes are skipped: run with --settings-check=<marker> and APPDATA pointing at a folder whose name holds it")
		if not FileAccess.file_exists(Game.SETTINGS_FILE):
			Game.use_remembered_wings()
			_check("(n) first run (no file): the human's test wing is off and the computer pilots' wings are on", not Game.test_wing and Game.cpu_wings, "%s %s" % [Game.test_wing, Game.cpu_wings])
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
		Game._test_wing_open = true
		Game._cpu_wings_open = true
		Game.use_remembered_wings()
		_check("(n) first run (no file): the human's test wing is off and the computer pilots' wings are on", not Game.test_wing and Game.cpu_wings, "%s %s" % [Game.test_wing, Game.cpu_wings])
		Game.choose_test_wing(true)
		Game.choose_cpu_wings(false)
		Game._test_wing_open = true
		Game._cpu_wings_open = true
		Game.test_wing = false
		Game.cpu_wings = true
		Game.use_remembered_wings()
		_check("(n) the remembered switches come back on the next start", Game.test_wing and not Game.cpu_wings, "%s %s" % [Game.test_wing, Game.cpu_wings])
		var cfg := ConfigFile.new()
		cfg.load(Game.SETTINGS_FILE)
		_check("(n) the file holds the two entries in [game]", cfg.get_value("game", "test_wing", null) == true and cfg.get_value("game", "cpu_wings", null) == false)
		Game.choose_test_wing(false)
		Game.choose_cpu_wings(true)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	Game.test_wing = test_before
	Game.cpu_wings = cpu_before
	Game._test_wing_open = test_open
	Game._cpu_wings_open = cpu_open


## Item (o): a wingman's crew is not a pilot: it is not counted as an AI pilot and is in no brain list.
func _item_o() -> void:
	var crews := 0
	var bad := 0
	for p: PilotProfile in world.profiles:
		if Squads.is_crew(p):
			crews += 1
			if p.is_ai_pilot() or world.pilot_ai.has(p):
				bad += 1
	_check("(o) the wingmen's crews are not AI pilots and are in no brain list", crews >= 3 and bad == 0, "%d crews, %d miscounted" % [crews, bad])

## Item (d): a run into the jungle through a gate. The wing turns into the tight column, no wingman unsticks
## itself or dies on a rock, and the leader is not pushed about by the wingmen (the separation).
func _item_d() -> void:
	var gate := {}
	for e: Dictionary in world.map.entrances:
		if str(e["quad"]) in ["tl", "bl"]:
			gate = e
			break
	if gate.is_empty():
		_check("(d) the map has a jungle gate on our side", false)
		return
	var camp := Vector2.INF
	for cm: Dictionary in world.map.camps:
		if str(cm["quad"]) == str(gate["quad"]):
			camp = cm["pos"] as Vector2
			break
	if camp == Vector2.INF:
		_check("(d) the map has a camp behind the gate", false)
		return
	await _ensure_leader()
	var lane_pt := gate["lane"] as Vector2
	var inside := gate["inside"] as Vector2
	var dir := (inside - lane_pt).normalized()
	_place(lane_pt - dir * 700.0, dir.angle(), 300.0)
	var nav := PilotAI.new(world, pilot)
	script_ctl.nav = nav
	script_ctl.goal = camp
	script_ctl.cruise = 0.0
	await _ticks(60)
	var column_ticks := 0
	var jungle_ticks := 0
	var unsticks := 0
	var lost := 0
	var prev := leader.global_position
	var push := 0.0
	for i in 2400:
		if not is_instance_valid(leader) or not leader.alive:
			lost += 1
			break
		var r := leader.global_position - prev - leader.velocity * SquadEngine.TICK_DT
		if r.length() < 30.0:
			push += r.length()
		prev = leader.global_position
		if SquadEngine.in_jungle(world, leader.global_position):
			jungle_ticks += 1
			var cols := 0
			for k in 3:
				var b := _brain(k)
				if b != null and b.shape == Formations.JUNGLE:
					cols += 1
				if b != null and b.flight._unstick_t > 0.0:
					unsticks += 1
			if cols == 3 and jungle_ticks > 120:
				column_ticks += 1
		if leader.global_position.distance_to(camp) < 300.0:
			break
		if i % 300 == 0:
			_snap("  d")
		await get_tree().physics_frame
	var alive := 0
	for s: Variant in _wings():
		if s != null:
			alive += 1
	_check("(d) the leader gets through the gate into the jungle", jungle_ticks > 120, "%d ticks in the jungle" % jungle_ticks)
	_check("(d) the wing flies the column while the leader is in the jungle", jungle_ticks > 120 and column_ticks >= (jungle_ticks - 120) * 8 / 10, "%d of %d ticks" % [column_ticks, jungle_ticks - 120])
	_check("(d) no wingman's route finder unsticks itself", unsticks == 0, "%d ticks of unsticking" % unsticks)
	_check("(d) no rock death: leader and wingmen alive at the end", lost == 0 and alive == 3, "%d wingmen alive, leader lost %d" % [alive, lost])
	_check("(d) the leader was pushed by separation less than 10 units in all", push < 10.0, "%.1f units" % push)
	script_ctl.goal = Vector2.INF
	script_ctl.nav = null


## The measurement the design asked for: does a beam stop on a friendly hull? A friendly Lance shoots at an enemy with
## our Destroyer between them; the damage log says what the beam hit.
func _item_beam() -> void:
	await _reset()
	var ahead := Vector2.from_angle(HEADING)
	var shooter := _ally("lance", START + ahead * 300.0)
	var ward := _ally("destroyer", START + ahead * 600.0)
	var foe := _foe("fighter", START + ahead * 900.0, true)
	var ctl := shooter.controller as Scripted
	ctl.fire = true
	ctl.aim = foe.global_position
	ctl.heading = ahead.angle()
	shooter.rotation = ahead.angle()
	await _ticks(300)
	var on_friend := ward.damage_log.has(shooter.uid)
	var on_foe := foe.damage_log.has(shooter.uid)
	print("(beam) a friendly Lance's beam through our Destroyer: hit the friend %s, hit the enemy behind it %s" % [str(on_friend), str(on_foe)])
	_check("(beam) the beam does not stop on a friendly hull: the enemy behind it is hit and the friend is not", on_foe and not on_friend)
	ctl.fire = false
	_remove(shooter)
	_remove(ward)
	_remove(foe)
	await _reset()
