extends Node
## WHAT THIS IS: the check that the computer pilots' energy and shield rules
## (PilotEnergyRules) hold the numbers the AI always used, and that
## PilotSystems acts on exactly those numbers.
##
## HOW IT WORKS: it freezes the match, launches a Flak Frigate for team 0 with a
## computer pilot's brain, and an enemy Fighter for team 1, and calls the
## brain's PilotSystems.set_energy_and_shields() by hand (the call PilotAI makes
## at the end of every think). First it compares the row with the numbers as
## plain figures (energy skill 0.55, focus skill 0.6, low hull 0.4, far goal
## 3,000, threat range 1,600). Then it plays the rules out:
##   - energy: no request at skill 0.55, a request at 0.56 (a ship in no
##     trouble, no target, its goal at hand asks for Balanced);
##   - focus: no request at skill 0.6, a request at 0.61, with the enemy inside
##     the threat range (a frigate is a large ship, so it needs no recent hit)
##     and the ship's focus Balanced;
##   - low hull: at 39% hull (not just hit) the pilot asks for Thrusters, at 41%
##     for Balanced;
##   - far goal: with the goal 3,001 away the pilot asks for Thrusters, 2,999
##     away for Balanced;
##   - threat range: an enemy 1,599 away is a threat (a focus request), one
##     1,601 away is not.
## "No request" means ShipControls.energy_request or focus_request still reads
## -1. It prints "pilot_energy_rules_check: N failures" (0 means all is as it
## should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=pilot_energy_rules_check
##
## WHO USES IT: main.gd loads it for --test=pilot_energy_rules_check. It changes
## only units of a frozen match that is thrown away.

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## The ship under test (a Flak Frigate).
var _ship: Ship
## The computer pilot's brain that flies it.
var _brain: PilotAI
## The enemy Fighter placed near it (or far from it).
var _enemy: Ship
## Where the ship is put for every case: open ground between the lanes.
var _home := Vector2.ZERO


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Run every group of checks, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_make_ships()
	_check_numbers()
	_check_energy_skill()
	_check_focus_skill()
	_check_low_hull()
	_check_far_goal()
	_check_threat_range()
	print("pilot_energy_rules_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("pilot_energy_rules_check: FAIL %s" % what)


## Launch the Flak Frigate (with a brain) and the enemy Fighter.
func _make_ships() -> void:
	var p := PilotProfile.new("energy-frigate", 0, 1, false)
	p.hull_id = "flak"
	p.role = "mid"
	world.profiles.append(p)
	_brain = PilotAI.new(world, p)
	world.pilot_ai[p] = _brain
	_ship = world.launch(p)
	var e := PilotProfile.new("energy-enemy", 1, 21, false)
	e.hull_id = "fighter"
	world.profiles.append(e)
	_enemy = world.launch(e)
	_enemy.controller = null


## Put the ship in its plain state (full hull, not hit, balanced shields, the
## goal at hand, no target, enemy far away, no requests) with skill `skill`.
func _reset(skill: float) -> void:
	_ship.global_position = _home
	_ship.rotation = 0.0
	_ship.hull = _ship.hull_max
	_ship.last_damage_time = -999.0
	_ship.shields.focus = Rules.FOCUS_BALANCED
	_brain.skill = skill
	_brain.state = "lane"
	_brain.target = null
	_brain.goal = _home
	_enemy.global_position = _home + Vector2(9000.0, 0.0)
	world.registry.rebuild_hashes()
	_ship.controls.energy_request = -1
	_ship.controls.focus_request = -1


## Run the pilot's energy and shield call once.
func _think() -> void:
	_brain.systems.set_energy_and_shields(_ship)


## The row holds the plain numbers.
func _check_numbers() -> void:
	var rules := PilotEnergyRules.row(_brain.profile)
	_expect(float(rules["energy_skill"]) == 0.55, "energy skill %s, wanted 0.55" % rules["energy_skill"])
	_expect(float(rules["focus_skill"]) == 0.6, "focus skill %s, wanted 0.6" % rules["focus_skill"])
	_expect(float(rules["low_hull"]) == 0.4, "low hull %s, wanted 0.4" % rules["low_hull"])
	_expect(float(rules["far_goal"]) == 3000.0, "far goal %s, wanted 3000" % rules["far_goal"])
	_expect(float(rules["threat_range"]) == 1600.0, "threat range %s, wanted 1600" % rules["threat_range"])
	print("pilot_energy_rules_check: row %s" % [rules])


## Energy routing is asked for above skill 0.55 only.
func _check_energy_skill() -> void:
	_reset(0.55)
	_think()
	_expect(_ship.controls.energy_request == -1, "an energy request at skill 0.55")
	_reset(0.56)
	_think()
	_expect(_ship.controls.energy_request == Rules.ENERGY_BALANCED, "energy request %d at skill 0.56, wanted Balanced" % _ship.controls.energy_request)


## Shield focus is asked for above skill 0.6 only (enemy inside the threat
## range, the ship's focus Balanced).
func _check_focus_skill() -> void:
	_reset(0.6)
	_enemy.global_position = _home + Vector2(500.0, 0.0)
	world.registry.rebuild_hashes()
	_think()
	_expect(_ship.controls.focus_request == -1, "a focus request at skill 0.6")
	_reset(0.61)
	_enemy.global_position = _home + Vector2(500.0, 0.0)
	world.registry.rebuild_hashes()
	_think()
	_expect(_ship.controls.focus_request != -1, "no focus request at skill 0.61 with an enemy at 500")


## Below 40% hull a pilot that was not just hit asks for Thrusters; above it,
## Balanced.
func _check_low_hull() -> void:
	_reset(0.9)
	_ship.hull = _ship.hull_max * 0.39
	_think()
	_expect(_ship.controls.energy_request == Rules.ENERGY_THRUSTERS, "energy request %d at 39%% hull, wanted Thrusters" % _ship.controls.energy_request)
	_reset(0.9)
	_ship.hull = _ship.hull_max * 0.41
	_think()
	_expect(_ship.controls.energy_request == Rules.ENERGY_BALANCED, "energy request %d at 41%% hull, wanted Balanced" % _ship.controls.energy_request)


## A goal more than 3,000 away asks for Thrusters; nearer, Balanced.
func _check_far_goal() -> void:
	_reset(0.9)
	_brain.goal = _home + Vector2(3001.0, 0.0)
	_think()
	_expect(_ship.controls.energy_request == Rules.ENERGY_THRUSTERS, "energy request %d with the goal 3001 away, wanted Thrusters" % _ship.controls.energy_request)
	_reset(0.9)
	_brain.goal = _home + Vector2(2999.0, 0.0)
	_think()
	_expect(_ship.controls.energy_request == Rules.ENERGY_BALANCED, "energy request %d with the goal 2999 away, wanted Balanced" % _ship.controls.energy_request)


## An enemy 1,599 away is a threat (the shields turn toward it); one 1,601 away
## is not.
func _check_threat_range() -> void:
	_reset(0.9)
	_enemy.global_position = _home + Vector2(1599.0, 0.0)
	world.registry.rebuild_hashes()
	_think()
	_expect(_ship.controls.focus_request != -1, "no focus request with an enemy 1599 away")
	_reset(0.9)
	_enemy.global_position = _home + Vector2(1601.0, 0.0)
	world.registry.rebuild_hashes()
	_think()
	_expect(_ship.controls.focus_request == -1, "a focus request with an enemy 1601 away")
