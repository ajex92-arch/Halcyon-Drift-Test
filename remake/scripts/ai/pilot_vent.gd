class_name PilotVent
extends RefCounted
## WHAT THIS IS: the AI pilot's hand on the Vent key (a part of PilotAI): it presses Vent
## when its battery is loaded and nothing can punish a ship that cannot fire or use its shield.
##
## HOW IT WORKS: after every think, think() asks wants_vent(): the pilot must be skilled
## enough (PilotVentRules vent_skill, the gate of its energy routing), must not be in a
## lockout or a Vent already, its battery's load (spent plus hard energy) must be at least
## vent_load, the battery must be able to refill, and no enemy ship, turret or minion may be
## within safe_range. Then it sets the Vent edge on the ship's controls, the same one the
## human's key sets. Everything else (the quiet guns, the dark zones, the end of the Vent)
## is the ship's own business.
##
## WHO USES IT: PilotAI._think() calls think() at the end of every think, beside
## PilotSystems; tests/pilot_vent_check.gd calls wants_vent() on its own.

## The pilot brain this part belongs to (we read its world, skill and profile). It is
## reached through a weak link: see `_ai_ref`.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain (the brain holds this part strongly; a strong link back would
## keep both alive for ever).
var _ai_ref: WeakRef


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## Press Vent for this think if the rules say so (see HOW IT WORKS).
func think(ship: Ship) -> void:
	var brain := ai
	if wants_vent(ship, brain.world, brain.skill, PilotVentRules.row(brain.profile)):
		ship.controls.vent = true


## True when a pilot of skill `skill` flying `ship` in `world` should press Vent now, by the
## rules in `row` (a PilotVentRules row).
static func wants_vent(ship: Ship, world: World, skill: float, row: Dictionary) -> bool:
	if skill <= float(row["vent_skill"]) or ship.systems_off():
		return false
	if ship.energy.load_frac() < float(row["vent_load"]) or ship.energy.regen <= 0.0:
		return false
	var near := world.nearest_enemy(ship.global_position, float(row["safe_range"]), ship.team, func(u: Unit) -> bool: return u.kind == Unit.K_SHIP or u.kind == Unit.K_TURRET or u.kind == Unit.K_MINION)
	return near == null
