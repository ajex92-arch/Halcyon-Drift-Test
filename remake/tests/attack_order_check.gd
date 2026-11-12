extends Node
## WHAT THIS IS: the check that the Admiral can send a bought squadron to attack the enemy mothership, and that the squadron
## then attacks it: a right-click on an enemy sends Attack, and the squadron takes the unit as its target although, under the
## standard rules (ms:nosmall), a strike-craft brain never picks the mothership by itself.
##
## HOW IT WORKS: it waits for the HUD and the command view of an Admiral seat, strips the enemy's defences, and stands a
## squadron of three Lance fighters beside the enemy mothership. Then, through the real overlay: the right-click on the
## mothership with the squadron selected must send Attack ("Attack: 1 squadron"), the squadron's standing order must become
## an Attack on the mothership, a refused order (an Attack on our own mothership) must say so, and after some seconds the
## squadron's ships must have the mothership as their target and the mothership must have lost shield or hull. Then ("far") a
## squadron of Fighters at our own mothership is sent at it, with a scout beside the enemy mothership keeping it in sight,
## and ten seconds later it must be much nearer. It ends with "attack_order_check: N failures (M checks)" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --no-pilots --no-jungle --no-admiral-ai --seed=7 --test=attack_order_check
##
## WHO USES IT: main.gd loads it for --test=attack_order_check; run_checks has a row for it.

## The running match (set by setup()).
var world: World
## The HUD, once found.
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many checks failed and how many were made.
var failures := 0
var checks := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Quit after 150 s of real time; start once the HUD and the command view exist.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 150000:
		print("attack_order_check: timeout")
		get_tree().quit()
		return
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or hud.command_view == null or world.human == null or world.phase != "play" or world.tick_count < 30:
		return
	started = true
	_run()


## Count one check and print its line.
func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s attack_order_check: %s" % ["PASS" if ok else "FAIL", what])


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait until the match has run `n` more ticks.
func _ticks(n: int) -> void:
	var until := world.tick_count + n
	while world.tick_count < until:
		await get_tree().process_frame


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(20)
	hud._close_others(null)
	var view := hud.command_view
	if world.human_role != "admiral" or not view.is_showing():
		_check(false, "setup: an Admiral seat with the command view showing")
		_finish()
		return
	await _attack(view)
	await _far(view)
	_finish()


## The summary line and quit.
func _finish() -> void:
	print("attack_order_check: %d failures (%d checks)" % [failures, checks])
	get_tree().quit()


## The ships of squadron `sq` that are alive.
func _ships(sq: Squad) -> Array[Ship]:
	var out: Array[Ship] = []
	for uid in sq.member_uids:
		var s := world.by_uid.get(int(uid)) as Ship
		if s != null and is_instance_valid(s) and s.alive:
			out.append(s)
	return out


## Does any ship of `sq` have unit `t` as its target now?
func _aimed_at(sq: Squad, t: Unit) -> bool:
	for s in _ships(sq):
		var ai := s.controller as PilotAI
		if ai != null and ai.target == t:
			return true
	return false


## The whole attack: set up, the right-click, the order, the refusal, the fight.
func _attack(view: CommandView) -> void:
	var ov := view.overlay
	var team := view.team
	var ems := world.mothership(Rules.enemy_of(team))
	world.minion_director.next_wave = INF
	# The enemy's defences are taken out and its mothership has no guns, so a small squadron lives long enough to be judged.
	for u: Unit in world.units.duplicate():
		if u.team == ems.team and u.alive and u.is_structure() and u != ems:
			world.combat.kill_silently(u)
	ems.mounts.clear()
	var made: Dictionary = (world.teams[team] as TeamState).production.spawn_now("lance", 3)
	var sq: Squad = world.squads.get(int(made.get("squad", -1))) as Squad
	if sq == null:
		_check(false, "setup: a squadron of Lance fighters")
		return
	# Beside the enemy hull, on the side that faces the middle of the map (700 units off its edge).
	var away := (Vector2(MapLayout.CX, MapLayout.CY) - ems.global_position).normalized()
	var spot := ems.global_position + away * (ems.beam * 0.5 + 700.0)
	var ships := _ships(sq)
	for i in ships.size():
		ships[i].global_position = spot + Vector2(0.0, float(i) * 60.0)
		ships[i].velocity = Vector2.ZERO
	await _ticks(40)
	_check(ems.visible_to(team), "setup: the squadron sees the enemy mothership")
	var ids: Array[int] = [sq.id]
	ov.set_selection(ids, false)
	_check(RtsSquadOrders.target_kind_at(ov, ems.global_position) == "enemy", "right-click: the enemy mothership is an enemy under the pointer")
	# Our own mothership is no target: refused, and the squadron keeps its order.
	var own_ms := world.mothership(team)
	var before_id: int = world.orders.next_id
	var refused := world.orders.submit(Order.make(OrderKinds.ATTACK, team, Rules.ADMIRAL_SEAT, true, {}, [sq.id], "unit", own_ms.uid))
	_check(refused != "", "refusal: an Attack on our own mothership is refused (%s)" % refused)
	# The right-click on the enemy mothership.
	var shield_before := ems.shields.fraction()
	var hull_before := ems.hull
	var why := RtsSquadOrders.smart_order_at(ov, ems.global_position)
	_check(why == "" and ov.result_ok and ov.result_text.begins_with("Attack"), "right-click: the answer says Attack ('%s')" % ov.result_text)
	_check(world.orders.next_id > before_id, "right-click: an order went to the queue")
	await _ticks(3)
	_check(str(sq.order.get("kind", "")) == OrderKinds.ATTACK and int(sq.order.get("target", -1)) == ems.uid, "order: the squadron's standing order is Attack on the mothership (%s)" % str(sq.order))
	# The fight: some seconds later the ships aim at the mothership and it has lost something.
	var aimed := false
	for i in 20:
		await _ticks(30)
		if _aimed_at(sq, ems):
			aimed = true
	_check(aimed, "fight: the squadron's ships take the mothership as their target")
	var lost := (shield_before - ems.shields.fraction()) > 0.0 or (hull_before - ems.hull) > 0.0
	_check(lost, "fight: the mothership lost shield or hull (shield %.4f to %.4f, hull %.0f to %.0f)" % [shield_before, ems.shields.fraction(), hull_before, ems.hull])

## The squadron starts at our own mothership, far from the enemy one: a scout stands beside the enemy mothership so that the team
## sees it, the right-click sends the squadron, and some seconds later it is much nearer the mothership than it was.
func _far(view: CommandView) -> void:
	var ov := view.overlay
	var team := view.team
	var ems := world.mothership(Rules.enemy_of(team))
	var prod := (world.teams[team] as TeamState).production
	var eye_made: Dictionary = prod.spawn_now("scout", 1)
	var eye_sq: Squad = world.squads.get(int(eye_made.get("squad", -1))) as Squad
	var made: Dictionary = prod.spawn_now("fighter", 3)
	var sq: Squad = world.squads.get(int(made.get("squad", -1))) as Squad
	if eye_sq == null or sq == null:
		_check(false, "far: a scout and a squadron of Fighters at home")
		return
	var eye := _ships(eye_sq)[0]
	eye.controller = null
	eye.global_position = ems.global_position + Vector2.from_angle(ems.rotation + PI * 0.5) * (ems.beam * 0.5 + 700.0)
	eye.velocity = Vector2.ZERO
	await _ticks(60)
	_check(ems.visible_to(team), "far: the scout keeps the enemy mothership in sight")
	var ids: Array[int] = [sq.id]
	ov.set_selection(ids, false)
	var before := _gap(sq, ems)
	var why := RtsSquadOrders.smart_order_at(ov, ems.global_position)
	_check(why == "" and ov.result_ok and ov.result_text.begins_with("Attack"), "far: the right-click sends the squadron at home ('%s')" % ov.result_text)
	await _ticks(600)
	var after := _gap(sq, ems)
	_check(before - after > 1500.0, "far: ten seconds later the squadron is much nearer the mothership (%d to %d from its hull)" % [roundi(before), roundi(after)])


## How far the first living ship of `sq` is from the hull of mothership `ems` (INF when none lives).
func _gap(sq: Squad, ems: Mothership) -> float:
	var ships := _ships(sq)
	return ems.hull_dist(ships[0].global_position) if not ships.is_empty() else INF
