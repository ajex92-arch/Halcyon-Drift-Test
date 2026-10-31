class_name PilotRunFan
extends RefCounted
## WHAT THIS IS: the fan rules of an AI Bomber's torpedo run: how tight its fan
## must be before the pilot commits to a target, and how close to the target it
## may launch. A part of PilotRun, kept in its own file.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## A Bomber's fan narrows only while it flies straight (RunFan: the tightness
## score, 0 to 360 points, +2 a tick of steady flight, -6 a tick of steering or
## sideways thrust). The computer pilot gets it by flying to its launch window,
## braking, turning the nose to the lead point and then giving no steering
## input and no boost, so the wait for the fan is at most 1.5 s for the tight
## fan a big target needs. The score it must have reached:
##   - 180 points (a fan of 10.5 degrees either side or tighter) against
##     medium and bigger ships, structures and motherships, which are wide
##     targets;
##   - 90 points (14.25 degrees) against small ships.
## The pilot commits at that score and lets go of the fire button once the bar is
## full and the score is still at least that, which a locked heading always keeps
## true (it keeps gaining during the hold). The nearest it may launch from is the
## larger of the share of the torpedoes' reach it picked and the arming distance
## plus the target's size plus a guard: a torpedo that touches the target before
## it is armed is a dud.
##
## WHO USES IT: only PilotRun.

## The tightness score a pilot needs against medium and bigger ships, structures
## and motherships, in points.
const NEED_BIG := 180
## The tightness score a pilot needs against small ships, in points.
const NEED_SMALL := 90
## World units added to the arming distance and the target's size for the nearest
## launch distance.
const ARM_GUARD := 60.0


## The tightness score `target` needs the pilot to have before a run on it.
static func need(target: Unit) -> int:
	if target.is_structure() or target is Mothership or target.size_class >= Rules.SIZE_MEDIUM:
		return NEED_BIG
	return NEED_SMALL


## The nearest distance (world units from the target's middle) a pilot of the
## torpedo gun `m` may launch from at a target of size `hit_size`, given the
## nearest the pilot's own share of the reach gives (`share_near`): never closer
## than the arming distance plus the target's size plus the guard.
static func near_edge(m: WeaponMount, hit_size: float, share_near: float) -> float:
	return maxf(share_near, float(m.def.get("arm", 0.0)) + hit_size + ARM_GUARD)
