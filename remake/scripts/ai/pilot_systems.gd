class_name PilotSystems
extends RefCounted
## WHAT THIS IS: the AI pilot's hand on the ship's power switches (a part of
## PilotAI): energy routing (send extra power to weapons, shields or
## thrusters) and shield focus (move most of the shield to the side that is
## being shot at).
##
## HOW IT WORKS: after every think, set_energy_and_shields() picks:
##   - energy: when retreating or below the low-hull share of hull, shields if
##     we were just hit, else thrusters; otherwise weapons while we really
##     fight a target (not one we only fly past on the way home, nor a push
##     target that is still far away), thrusters when the goal is far, and
##     balanced the rest of the time;
##   - shield focus: the side facing the nearest threat (an enemy ship,
##     turret or minion within the threat range, or the jungle monster we are
##     fighting)
##     when we were just hit, or always for large and capital ships;
##     otherwise balanced.
## Only skilled pilots touch the switches: energy routing needs a skill above
## the energy skill number, shield focus a skill above the focus skill number.
## (PilotEnergyRules holds those two numbers, the low-hull share, the far-goal
## distance and the threat range: one row, read once per think. Rules.ENERGY_*
## and Rules.FOCUS_* list the settings. The ship only switches when its switch
## cooldown is over, and each switch starts a new cooldown; a request made during
## the cooldown is dropped, but the brain asks again on its next think.)
##
## WHO USES IT: PilotAI._think() calls set_energy_and_shields() at the end
## of every think. It fills ShipControls.energy_request and focus_request.

## The pilot brain this part belongs to (we read its state, target, goal
## and skill). It is reached through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## Energy routing and shield focus for this think (see HOW IT WORKS).
func set_energy_and_shields(ship: Ship) -> void:
	var brain := ai
	var world := brain.world
	var c := ship.controls
	var rules := PilotEnergyRules.row(brain.profile)
	var low_hull := float(rules["low_hull"])
	var far_goal := float(rules["far_goal"])
	var threat_range := float(rules["threat_range"])
	# "Just hit" = any damage in the last 1.5 seconds.
	var hit_recently := world.time - ship.last_damage_time < 1.5
	var fighting := brain.target != null and is_instance_valid(brain.target)
	# Only a target we really fight counts: not one we fly home past, nor a
	# push target still far away (PilotCombat travels to that one instead).
	if fighting:
		fighting = brain.state != "home" and not brain.combat.target_far(ship)
	# Step 1: energy. Retreating or below the low-hull share: shields while
	# under fire, else thrusters to get away. Fighting: weapons. Farther from the
	# goal than the far-goal distance: thrusters.
	var want_energy := Rules.ENERGY_BALANCED
	if brain.state == "retreat" or ship.hull_frac() < low_hull:
		want_energy = Rules.ENERGY_SHIELDS if hit_recently else Rules.ENERGY_THRUSTERS
	elif fighting:
		want_energy = Rules.ENERGY_WEAPONS
	elif ship.global_position.distance_to(brain.goal) > far_goal:
		want_energy = Rules.ENERGY_THRUSTERS
	if brain.skill > float(rules["energy_skill"]):
		c.energy_request = want_energy
	# Step 2: face the shields toward whoever is shooting at us. We turn the
	# threat's position into the ship's own frame (as if the ship always
	# pointed east) to find which side it is on: front, rear, left or right.
	var want_focus := Rules.FOCUS_BALANCED
	var threat := world.nearest_enemy(ship.global_position, threat_range, ship.team, func(u: Unit) -> bool: return u.kind == Unit.K_SHIP or u.kind == Unit.K_TURRET or u.kind == Unit.K_MINION)
	# nearest_enemy() skips neutral units, so a jungler hit by a derelict or a
	# snub fighter found no threat: use the monster we are fighting when it is
	# close.
	if threat == null and brain.target != null and is_instance_valid(brain.target) and brain.target.team == Rules.NEUTRAL and brain.target.global_position.distance_to(ship.global_position) < threat_range:
		threat = brain.target
	if threat != null and (hit_recently or ship.size_class >= Rules.SIZE_LARGE):
		var local := ArmourSections.from_spine((threat.global_position - ship.global_position).rotated(-ship.rotation), ship.spine_len, ship.spine_off)
		var zone := ShieldZones.zone_for_local(local)
		want_focus = [Rules.FOCUS_FRONT, Rules.FOCUS_REAR, Rules.FOCUS_LEFT, Rules.FOCUS_RIGHT][zone]
	# Ask only when it differs from the current focus.
	if brain.skill > float(rules["focus_skill"]) and want_focus != ship.shields.focus:
		c.focus_request = want_focus
