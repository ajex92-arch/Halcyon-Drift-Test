extends Node
## WHAT THIS IS: the scripted human of the match recorder's proof. It plays the human pilot's seat
## for a few minutes the way a player would (it presses the flight keys, moves the aim, fires, uses
## the special, kit, shield focus and energy routing, flies home to dock, shops in the hangar and
## launches again), so that a recording has every kind of `c` and `b` line in it. The same test,
## started with --replay=<recording>, does not play: it only checks that the replay reproduced
## the match.
##
## HOW IT WORKS: setup() adds the det_hash test as its child (it prints the hash lines the
## recorded run and its replay are compared by) and, when no replay is running, starts playing.
## _physics_process() runs before the World each tick (priority -100) and decides from the tick
## count and the state of the match: docked, it shops and launches through HumanCmd (the same door
## the hangar screens use); flying, it picks a target (the nearest enemy, else a point on the way
## to the enemy mothership, else home when hurt), aims at it through World.test_mouse, holds the
## thrust, fires when the target is close and taps the other keys on a fixed schedule. Nothing here
## draws a random number from the game's shared sequence. When the run ends it prints "record_drive: N
## failures": playing, it checks that the recording is on and has `c` and `b` lines; replaying, that
## the replay compared fingerprints, that the header agreed, that none differed and that every order,
## control and command of the recording was played (with --replay-until: that it stopped there).
##
## HOW TO RUN IT ("godot" is the Godot console program; the recording lands in <dir>):
##   record: godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --seed=7 --secs=330 --record --recordings-dir=<dir> --record-name=drive1 --test=record_drive
##   replay: godot --headless --path remake --fixed-fps 60 -- --seed=7 --secs=330 --replay=<dir>/drive1.log --test=record_drive
## (--replay brings the seat, the team and the rules from the log; add --record --recordings-dir=<dir>
## --record-name=drive2 to record the replay too: its log must equal the first byte for byte.)
##
## WHO USES IT: main.gd loads it for --test=record_drive; the recorder proof script runs it.

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## The hash test that prints the lines the runs are compared by.
var _det: Node
## True when this run plays the human (no replay is running).
var _driving := false
## Tick of the next shopping step while docked.
var _next_shop := 0
## How many times the pilot shopped (the rotation through hulls and gear).
var _shops := 0
## Actions pressed by a tap and the tick on which to let each go: action name -> tick.
var _release := {}
## The last tick on which the fire state changed (so the burst lengths vary).
var _fire_until := 0
## How many ships the pilot has launched in this run.
var _launches := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	# Run before the World each physics frame, so that a key pressed here is seen by the same tick.
	process_physics_priority = -100
	_det = load("res://tests/det_hash.gd").new()
	add_child(_det)
	_det.call("setup", w)
	_driving = not w.orders.replaying


## Godot calls this every tick, before the World's: play the human's seat.
func _physics_process(_dt: float) -> void:
	if world == null or not _driving or world.human == null:
		return
	var n := world.tick_count
	# Let go of the keys that were tapped.
	for action: String in _release.keys():
		if n >= int(_release[action]):
			Input.action_release(action)
			_release.erase(action)
	var h := world.human
	if h.state == "docked":
		_hangar(n)
	elif h.state == "flying" and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		_fly(n, h.ship)
	else:
		_stop_keys()


## Docked: every 90 ticks buy something from a rotation (some purchases are refused: that is
## recorded too) and launch.
func _hangar(n: int) -> void:
	_stop_keys()
	if n < _next_shop:
		return
	_next_shop = n + 90
	var hulls := Ships.HULLS.keys()
	var items := Items.ITEMS.keys()
	match _shops % 5:
		0:
			HumanCmd.run(world, "buy_kit")
		1:
			HumanCmd.run(world, "buy_gear", [str(items[_div(_shops, 5) % items.size()])])
		2:
			HumanCmd.run(world, "buy_hull", [str(hulls[_div(_shops, 5) % hulls.size()])])
		3:
			HumanCmd.run(world, "sell_slot", [_div(_shops, 5) % Items.SLOTS])
		4:
			var mods := Modules.MODULES.keys()
			HumanCmd.run(world, "toggle_module", [str(mods[_div(_shops, 5) % mods.size()])])
	_shops += 1
	if HumanCmd.run(world, "launch") == "":
		_launches += 1


## Flying: aim, thrust, fire and tap keys by the tick count and what is near.
func _fly(n: int, ship: Ship) -> void:
	var enemy := _nearest_foe(ship, 2200.0)
	var home := world.mothership(ship.team).global_position
	var foe := world.mothership(1 - ship.team).global_position
	var hurt := ship.hull_frac() < 0.4
	var target: Vector2
	if hurt:
		target = home
	elif enemy != null:
		target = enemy.global_position
	else:
		target = foe + Vector2(0.0, sin(float(n) / 300.0) * 3000.0)
	world.test_mouse = target
	Input.action_press("thrust_forward")
	# Drift sideways in a slow pattern; boost on the long straight runs.
	var side := _div(n, 45) % 4
	_hold("strafe_left", enemy != null and side == 1)
	_hold("strafe_right", enemy != null and side == 3)
	_hold("boost", enemy == null and _div(n, 200) % 2 == 0 and not hurt)
	_hold("thrust_back", _div(n, 700) % 9 == 8)
	# Fire in bursts when the target is close.
	if enemy != null and ship.global_position.distance_to(target) < 1400.0:
		if n >= _fire_until:
			_fire_until = n + 40 + (n * 7) % 90
			world.mouse_fire = not world.mouse_fire
	else:
		world.mouse_fire = false
	# One-tick taps on a schedule.
	if n % 500 == 250 and enemy != null:
		world.mouse_special = true
	elif world.mouse_special:
		world.mouse_special = false
	if n % 600 == 100 and hurt:
		_tap("use_kit", n)
	if hurt and ship.global_position.distance_to(home) < 1500.0 and n % 30 == 0:
		_tap("dock", n)
	var focus := ["shield_front", "shield_rear", "shield_left", "shield_right"]
	if n % 700 == 350:
		_tap(focus[_div(n, 700) % 4], n)
	var energy := ["energy_weapons", "energy_shields", "energy_thrusters", "energy_balanced"]
	if n % 900 == 450:
		_tap(energy[_div(n, 900) % 4], n)
	if n % 2400 == 1200:
		_tap("assist_toggle", n)


## Whole-number division, rounded down (the tick counts are whole numbers).
func _div(a: int, b: int) -> int:
	return floori(float(a) / float(b))


## The nearest live enemy unit of `ship` within `r` (a pilot ship, minion, turret or mothership), or
## null. It walks the unit list: this test runs before the World's tick, when the spatial hashes
## (World.nearest_enemy) may still hold a unit that died last tick.
func _nearest_foe(ship: Ship, r: float) -> Unit:
	var best: Unit = null
	var best_d := r
	for u in world.units:
		if not is_instance_valid(u) or not u.alive or u.team == ship.team or u.team > 1 or u.team < 0:
			continue
		if u.kind != Unit.K_SHIP and u.kind != Unit.K_MINION and u.kind != Unit.K_TURRET and u.kind != Unit.K_MOTHERSHIP:
			continue
		var d := ship.global_position.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best


## Press or let go of `action` to match `on`.
func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Press `action` now and let it go three ticks later.
func _tap(action: String, n: int) -> void:
	Input.action_press(action)
	_release[action] = n + 3


## No ship to fly: let go of everything.
func _stop_keys() -> void:
	for action in ["thrust_forward", "thrust_back", "strafe_left", "strafe_right", "boost"]:
		Input.action_release(action)
	world.mouse_fire = false
	world.mouse_special = false


## The match is over (the hash test quit): print the verdict.
func _exit_tree() -> void:
	if world == null or not is_instance_valid(world):
		return
	_stop_keys()
	var q := world.orders
	if q == null:
		return
	if _driving:
		_check_recording(q)
	elif q.replay != null:
		_check_replay(q)
	print("record_drive: %d failures" % fails)


## Count a failure and print a PASS or FAIL line.
func _check(what: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


## Playing: the recording is on and has flight controls and hangar commands.
func _check_recording(q: OrderQueue) -> void:
	_check("the pilot launched at least once (%d launches)" % _launches, _launches > 0)
	if q.log == null:
		_check("the match log is open (use --record or --order-log)", false)
		return
	var read := OrderLog.read(q.log.path)
	var controls := (read["controls"] as Array).size()
	var commands := (read["commands"] as Array).size()
	_check("the log has its v2 header", str(read["header"]).begins_with("log v2 seed="))
	_check("the log has flight control lines (%d)" % controls, controls > 100)
	_check("the log has hangar command lines (%d)" % commands, commands > 3)
	_check("the log has fingerprint lines (%d)" % (read["hashes"] as Dictionary).size(), (read["hashes"] as Dictionary).size() > 0)
	_check("the log has its end line", str(read["end"]) != "")


## Replaying: the replay reproduced the match.
func _check_replay(q: OrderQueue) -> void:
	var r := q.replay
	_check("the replay compared fingerprint lines (%d)" % r.compared, r.compared > 0)
	_check("the replay's header agreed with the match", r.header_ok)
	_check("no fingerprint line differed (%d differ)" % r.mismatches, r.mismatches == 0)
	_check("no hangar command gave another result (%d differ)" % r.command_diffs, r.command_diffs == 0)
	_check("flight controls were played (%d ticks)" % r.controls_played, r.controls_played > 100)
	if r.until >= 0.0:
		_check("the replay stopped at the match time asked for (%.2f, asked %.2f)" % [world.time, r.until], q.replay_stopped() and world.time >= r.until and world.time < r.until + 0.1)
	else:
		_check("every order of the log was played (%d left over)" % r.left_over(), r.left_over() == 0)
		_check("every hangar command of the log was played (%d left over)" % r.commands_left(), r.commands_left() == 0)
