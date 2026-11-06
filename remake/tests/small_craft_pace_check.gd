extends Node
## WHAT THIS IS: the check that the small craft fly at Rules.SMALL_CRAFT_PACE of
## their table speed and pushes, and that nothing else does. It asks the real
## game code for the numbers of every pilot hull, every minion type, the jungle
## snub fighter and the two drones, and compares each with its data row.
##
## HOW IT WORKS: it freezes the match and launches one ship of each hull with
## nobody at the controls. For the pilot hulls it checks, with the team's small
## Drive level at 0, 1 and 2 (Fighter Drive 1 and 2):
##   - a small craft (Scout, Fighter, Lance Fighter, Bomber): top speed is its
##     row's "max" x the pace x (1 + 0.08 x level), the main, reverse and side
##     pushes are the row's x the pace x (1 + 0.06 x level), so each level adds
##     8% (6%) of the NEW value; turn, turn bleed, flight assist, cap pull and
##     the boost multipliers are the row's, untouched;
##   - every bigger hull: top speed and main push are exactly the row's x its
##     drive level, and the same turn and boost numbers.
## Then each minion type (speed and accel x the pace of its row: 0.8 for the
## Snub-Fighter; the Patrol Leader and the Light Bomber, whose row says "pace"
## 1.0, at their table numbers, the Light Bomber's 380 and 320 checked as plain
## numbers so it keeps up with its wave; turn untouched), a jungle snub fighter
## (0.8), and a mining drone and a repair drone (their rows' speeds, as they
## were). It prints one line per unit and then
## "small_craft_pace_check: N failures" (0 means all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=small_craft_pace_check
##
## WHO USES IT: main.gd loads it for --test=small_craft_pace_check. It changes
## only units of a frozen match that is thrown away.

## How close a measured number must be to the wanted one (a share of it).
const TOLERANCE := 1e-6

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Check every unit, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	for hid: String in Ships.ORDER:
		_check_hull(hid)
	for type_id: String in Minions.TYPES:
		_check_minion(type_id)
	_check_snub()
	_check_drones()
	print("small_craft_pace_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("small_craft_pace_check: FAIL %s" % what)


## Is `got` the wanted number, to within TOLERANCE of it?
func _near(got: float, want: float) -> bool:
	return absf(got - want) <= TOLERANCE * maxf(1.0, absf(want))


## Launch a pilot ship of hull `hid` for team 0 with nobody at the controls.
func _launch(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 0, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Check the flying numbers of pilot hull `hid` at Drive levels 0, 1 and 2.
func _check_hull(hid: String) -> void:
	var s := _launch(hid)
	var h := Handling.row(hid)
	var small := s.size_class == Rules.SIZE_SMALL
	var pace := Rules.SMALL_CRAFT_PACE if small else 1.0
	var tier: String = Tech.TIERS[s.size_class]
	var ts: TeamState = world.teams[0]
	var base_max := 0.0
	var base_accel := 0.0
	for level in 3:
		ts.drive[tier] = level
		s.recompute_stats(false)
		var label := "%s drive %d" % [hid, level]
		var want_max := float(h["max"]) * pace * (1.0 + 0.08 * level)
		var want_accel := float(h["accel"]) * pace * (1.0 + 0.06 * level)
		_expect(_near(s.f_max, want_max), "%s top speed %s, wanted %s" % [label, s.f_max, want_max])
		_expect(_near(s.f_accel, want_accel), "%s main push %s, wanted %s" % [label, s.f_accel, want_accel])
		if not s.f_line:
			var want_rev := float(h["reverse"]) * pace * (1.0 + 0.06 * level)
			var want_side := float(h["strafe"]) * pace * (1.0 + 0.06 * level)
			_expect(_near(s.f_reverse, want_rev), "%s reverse push %s, wanted %s" % [label, s.f_reverse, want_rev])
			_expect(_near(s.f_strafe, want_side), "%s side push %s, wanted %s" % [label, s.f_strafe, want_side])
		if level == 0:
			base_max = s.f_max
			base_accel = s.f_accel
		else:
			# Each Drive level adds 8% of the top speed and 6% of the push the
			# craft has without it (so of the new, slower value).
			_expect(_near(s.f_max, base_max * (1.0 + 0.08 * level)), "%s drive adds %s of the new top speed" % [label, s.f_max / base_max - 1.0])
			_expect(_near(s.f_accel, base_accel * (1.0 + 0.06 * level)), "%s drive adds %s of the new push" % [label, s.f_accel / base_accel - 1.0])
	ts.drive[tier] = 0
	s.recompute_stats(false)
	_expect(_near(s.f_turn, float(h["turn"])), "%s turn %s, wanted %s" % [hid, s.f_turn, h["turn"]])
	_expect(_near(s.f_bleed, float(h["turn_bleed"])), "%s turn bleed %s" % [hid, s.f_bleed])
	_expect(_near(s.f_assist, float(h["assist"])), "%s flight assist %s" % [hid, s.f_assist])
	_expect(_near(s.f_cap_rate, float(h["cap_rate"])), "%s cap pull %s" % [hid, s.f_cap_rate])
	if bool(h["has_boost"]):
		_expect(_near(s.f_boost_mul, float(h["boost_mul"])), "%s boost push multiplier %s" % [hid, s.f_boost_mul])
		_expect(_near(s.f_boost_cap, float(h["boost_cap"])), "%s boost speed multiplier %s" % [hid, s.f_boost_cap])
	print("small_craft_pace_check: ship %s top %.1f push %.1f reverse %.1f side %.1f turn %.2f (table top %.0f)" % [
		hid, s.f_max, s.f_accel, s.f_reverse, s.f_strafe, s.f_turn, float(h["max"])])
	s.alive = false


## Check minion type `type_id`: speed and accel x the pace of its row (the row's
## own "pace" when it has one, else the small craft's pace for size class 0). The
## Light Bomber is also checked against the plain numbers 380 and 320: it flies
## at its table speed and accel, so it keeps up with its wave.
func _check_minion(type_id: String) -> void:
	var m := world.spawn_minion(1, type_id, "mid", Vector2(MapLayout.CX, MapLayout.H * 0.3))
	var row: Dictionary = Minions.TYPES[type_id]
	var pace := Rules.SMALL_CRAFT_PACE if int(row["size"]) == Rules.SIZE_SMALL else 1.0
	if row.has("pace"):
		pace = float(row["pace"])
	if type_id == "bomber":
		_expect(_near(m.speed, 380.0), "Light Bomber minion speed %s, wanted 380" % m.speed)
		_expect(_near(m.accel, 320.0), "Light Bomber minion accel %s, wanted 320" % m.accel)
		_expect(m.speed >= Minions.FORMATION_SPEED, "Light Bomber minion speed %s is below the wave's pace %s" % [m.speed, Minions.FORMATION_SPEED])
	_expect(_near(m.speed, float(row["speed"]) * pace), "minion %s speed %s, wanted %s" % [type_id, m.speed, float(row["speed"]) * pace])
	_expect(_near(m.accel, float(row["accel"]) * pace), "minion %s accel %s, wanted %s" % [type_id, m.accel, float(row["accel"]) * pace])
	_expect(_near(m.turn, float(row["turn"])), "minion %s turn %s, wanted %s" % [type_id, m.turn, row["turn"]])
	print("small_craft_pace_check: minion %s speed %.1f accel %.1f turn %.2f (table speed %.0f)" % [type_id, m.speed, m.accel, m.turn, float(row["speed"])])
	m.alive = false


## Check the jungle snub fighter: speed and accel x the pace.
func _check_snub() -> void:
	var carrier := world.spawn_derelict("pace_check", "carrier", Vector2(MapLayout.CX, MapLayout.H * 0.3))
	var s := world.spawn_snub(carrier)
	var row: Dictionary = Jungle.SNUB
	var pace := Rules.SMALL_CRAFT_PACE if int(row["size"]) == Rules.SIZE_SMALL else 1.0
	_expect(_near(s.speed, float(row["speed"]) * pace), "snub fighter speed %s, wanted %s" % [s.speed, float(row["speed"]) * pace])
	_expect(_near(s.accel, float(row["accel"]) * pace), "snub fighter accel %s, wanted %s" % [s.accel, float(row["accel"]) * pace])
	_expect(_near(s.turn, float(row["turn"])), "snub fighter turn %s, wanted %s" % [s.turn, row["turn"]])
	print("small_craft_pace_check: snub fighter speed %.1f accel %.1f turn %.2f (table speed %.0f)" % [s.speed, s.accel, s.turn, float(row["speed"])])
	s.alive = false
	carrier.alive = false


## Check that the mining and repair drones keep the speeds of their rows.
func _check_drones() -> void:
	var mine := world.spawn_mining_drone(0, "")
	_expect(_near(mine.speed, float(Structures.MINING_DRONE["speed"])), "mining drone speed %s, wanted %s" % [mine.speed, Structures.MINING_DRONE["speed"]])
	_expect(_near(mine.accel, float(Structures.MINING_DRONE["accel"])), "mining drone accel %s, wanted %s" % [mine.accel, Structures.MINING_DRONE["accel"]])
	print("small_craft_pace_check: mining drone speed %.1f accel %.1f" % [mine.speed, mine.accel])
	var owner := _launch("fighter")
	var fix := world.spawn_repair_drone(owner, 0, owner.global_position, RepairDrone.MODE_KIT)
	_expect(_near(fix.speed, float(Structures.REPAIR_DRONE["speed"])), "repair drone speed %s, wanted %s" % [fix.speed, Structures.REPAIR_DRONE["speed"]])
	print("small_craft_pace_check: repair drone speed %.1f" % fix.speed)
	mine.alive = false
	fix.alive = false
	owner.alive = false
