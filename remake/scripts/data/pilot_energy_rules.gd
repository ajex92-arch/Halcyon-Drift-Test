class_name PilotEnergyRules
extends RefCounted
## WHAT THIS IS: the computer pilots' energy and shield rules, as data: the
## numbers at which a pilot switches its energy routing and turns its shields
## toward a threat. They used to sit inside PilotSystems as plain numbers; here
## they are one row that a later difficulty setting can replace per pilot.
##
## HOW IT WORKS: DEFAULT is the one row. row() hands out the row for a pilot's
## profile (today every pilot gets DEFAULT, whatever the profile). Nothing here
## runs by itself. The fields of a row:
##   energy_skill   energy routing is asked for only by a pilot whose skill is
##                  above this [0..1]
##   focus_skill    the same for shield focus [0..1]
##   low_hull       a ship under this share of its hull asks for shields (when
##                  just hit) or thrusters (otherwise) [0..1]
##   far_goal       a goal farther away than this asks for thrusters [world
##                  units]
##   threat_range   an enemy ship, turret or minion within this distance, or the
##                  jungle monster being fought, is the threat the shields turn
##                  toward [world units]
##
## WHO USES IT: PilotSystems.set_energy_and_shields(), once per call;
## tests/pilot_energy_rules_check.gd.

## The row every pilot uses (the fields are explained at the top of this file).
const DEFAULT := {
	"energy_skill": 0.55,
	"focus_skill": 0.6,
	"low_hull": 0.4,
	"far_goal": 3000.0,
	"threat_range": 1600.0,
}


## The energy and shield rules for the pilot with profile `profile` (a
## PilotProfile; today every pilot gets the same row).
static func row(_profile: PilotProfile) -> Dictionary:
	return DEFAULT
