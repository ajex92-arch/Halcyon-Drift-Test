class_name PartAim
extends RefCounted
## WHAT THIS IS: the scoring of which part of a big ship a strike craft pilot should shoot at. It is
## pure: every function works on plain numbers (no world, no ship), so a check can call it directly.
## PilotTargeting builds the list of candidate parts from the real target and asks it.
##
## HOW IT WORKS: each part of the target that the pilot could reach gets a score from its class:
## an engine pod 100 when the target is leaving (it moves away from the shooter), else 60; a main gun
## 90; a light part (point defence or flak gun) 70 for a fighter and 40 for a bomber; the sensor 50.
## Minus 15 for each friendly already aiming at that part (a part with 3 or more is skipped); plus 20
## for the part the pilot aimed at last time. A part is skipped (scores 0) when it is offline, when its
## shield zone still holds shield (unless the weapon pierces it), and, for a heavy or covered part, when
## the weapon would only glance off the armour over it (strength below 0.176 times the section's
## armour now, the glance line of ArmourSections.hit()): an exposed light part has a plate of its own
## and no such gate. The best score wins; a nearer part wins a tie, then the lower part number.
## The choice is held for HOLD_TICKS ticks (PilotTargeting keeps it) so the aim does not flicker.
##
## WHO USES IT: PilotTargeting.part_delta() (and so PilotCombat's two aim sites); the part AI check.

## How many ticks a part choice is held (half a second).
const HOLD_TICKS := 30
## Score of an engine pod when the target is not leaving.
const SCORE_POD := 60
## Score of an engine pod when the target is leaving.
const SCORE_POD_LEAVING := 100
## Score of a main gun.
const SCORE_MAIN := 90
## Score of a light part for a fighter (any strike craft that is not a bomber).
const SCORE_LIGHT_FIGHTER := 70
## Score of a light part for a bomber.
const SCORE_LIGHT_BOMBER := 40
## Score of the sensor.
const SCORE_SENSOR := 50
## What each friendly already aiming at a part costs its score.
const FRIEND_COST := 15
## A part that this many friendlies already aim at is skipped.
const FRIEND_CAP := 3
## What the part the pilot aimed at last time gains.
const HOLD_BONUS := 20
## A shot whose strength is below this share of a covered part's section armour would only glance.
const GLANCE_RATIO := 0.176
## A target counts as leaving when it moves away from the shooter faster than this (units per second).
const LEAVING_SPEED := 30.0


## The score of a part of class `cls` (ShipParts.CLASS_*) before any friend or hold term.
static func base_score(cls: int, leaving: bool, bomber: bool) -> int:
	match cls:
		ShipParts.CLASS_POD:
			return SCORE_POD_LEAVING if leaving else SCORE_POD
		ShipParts.CLASS_MAIN:
			return SCORE_MAIN
		ShipParts.CLASS_LIGHT:
			return SCORE_LIGHT_BOMBER if bomber else SCORE_LIGHT_FIGHTER
		ShipParts.CLASS_SENSOR:
			return SCORE_SENSOR
	return 0


## The score of candidate `cand` (a Dictionary: cls, offline, exposed, shield_up, a_eff in armour points,
## friends) for a shooter whose weapon has strength `strength` (damage points) and `pierces` shields, against a
## target that is `leaving`; `bomber`: the shooter is a bomber; `held`: it is the part aimed at last time.
## 0 means skipped.
static func score(cand: Dictionary, leaving: bool, bomber: bool, strength: float, pierces: bool, held: bool) -> int:
	if bool(cand["offline"]):
		return 0
	if bool(cand["shield_up"]) and not pierces:
		return 0
	var cls := int(cand["cls"])
	var exposed_light := cls == ShipParts.CLASS_LIGHT and bool(cand["exposed"])
	if not exposed_light and strength < GLANCE_RATIO * float(cand["a_eff"]):
		return 0
	var friends := int(cand["friends"])
	if friends >= FRIEND_CAP:
		return 0
	var s := base_score(cls, leaving, bomber) - FRIEND_COST * friends
	if held:
		s += HOLD_BONUS
	return maxi(s, 0)


## The index in `cands` (Dictionaries as in score(), each with `dist`, the shooter's distance to the part, and `id`,
## the part number) of the part to aim at, or -1 when none scores. `last` is the part number aimed at last time
## (-1 for none).
static func choose(cands: Array, leaving: bool, bomber: bool, strength: float, pierces: bool, last: int) -> int:
	var best := -1
	var best_s := 0
	for i in cands.size():
		var c: Dictionary = cands[i]
		var s := score(c, leaving, bomber, strength, pierces, int(c["id"]) == last)
		if s <= 0:
			continue
		if best < 0 or s > best_s:
			best = i
			best_s = s
		elif s == best_s:
			var cb: Dictionary = cands[best]
			if float(c["dist"]) < float(cb["dist"]) or (float(c["dist"]) == float(cb["dist"]) and int(c["id"]) < int(cb["id"])):
				best = i
	return best
