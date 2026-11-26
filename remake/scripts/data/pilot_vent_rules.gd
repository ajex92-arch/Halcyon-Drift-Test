class_name PilotVentRules
extends RefCounted
## WHAT THIS IS: the computer pilots' Vent rules, as data: when a pilot presses Vent and how
## much the others prize a target that cannot fire. One row that a later difficulty setting
## can replace per pilot.
##
## HOW IT WORKS: DEFAULT is the one row. row() hands out the row for a pilot's profile
## (today every pilot gets DEFAULT, whatever the profile). Nothing here runs by itself. The
## fields of a row:
##   vent_skill     a pilot vents only when its skill is above this [0..1] (the same gate
##                  as its energy routing)
##   vent_load      a pilot vents when its battery's load (spent plus hard energy, as a
##                  share of the battery) is at least this [0..1]
##   safe_range     no enemy ship, turret or minion may be within this distance [world
##                  units]: a Vent leaves the ship unable to fire and shieldless
##   target_bonus   how much better (lower) an enemy pilot that is overloaded or venting
##                  scores when a pilot picks a target [world units of distance]
##
## WHO USES IT: PilotVent (when to press Vent), PilotTargeting.pick_target() (the bonus)
## and tests/pilot_vent_check.gd.

## The row every pilot uses (the fields are explained at the top of this file).
const DEFAULT := {
	"vent_skill": 0.55,
	"vent_load": 0.6,
	"safe_range": 2400.0,
	"target_bonus": 300.0,
}


## The Vent rules for the pilot with profile `profile` (a PilotProfile; today every pilot
## gets the same row).
static func row(_profile: PilotProfile) -> Dictionary:
	return DEFAULT
