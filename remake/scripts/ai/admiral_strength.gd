class_name AdmiralStrength
extends RefCounted
## WHAT THIS IS: the fitted strength of a fleet, as one whole number: the sum over its ships of one
## weight per hull class (the four classes of RtsHulls.class_of: squadron, corvette, frigate, capital),
## scaled by how much hull each ship has left. It is the planned replacement of AdmiralLanes.fleet_power
## under the profile switch fitted_strength. Nothing calls it yet (RT5 build 4 does the wiring).
##
## HOW IT WORKS: only whole numbers. A weight is in thousandths ("1000" is 1.0), as the rows of
## AdmiralProfileData. A hull fraction is in permille (1000 = undamaged). One ship counts
##   weight * (HULL_FLOOR + (1000 - HULL_FLOOR) * permille / 1000) / 1000
## so an undamaged ship counts its whole weight and a badly damaged one never less than HULL_FLOOR
## permille of it (the same 0.4 floor as fleet_power: a damaged ship still shoots at full power).
## The weights come in as an Array of four whole numbers in the order of CLASSES. SIZE_WEIGHTS is
## today's size count (1, 2, 3, 4) in the same form, so the two can be compared.
## The functions draw no random number and write nothing.
##
## WHO USES IT: tests/strength_fit.gd (the fit and its 75% held-out check). RT5 build 4: the computer
## Admiral's siege edge and mothership mover, with the weights of the profile table.

## The four hull classes, in the order of every weights Array.
const CLASSES := ["squadron", "corvette", "frigate", "capital"]
## Today's size count as weights (thousandths): 1, 2, 3 and 4 (AdmiralLanes.fleet_power).
const SIZE_WEIGHTS := [1000, 2000, 3000, 4000]
## A ship never counts less than this many permille of its weight, however damaged.
const HULL_FLOOR := 400


## The place of hull `hull_id`'s class in CLASSES (0 to 3).
static func class_index(hull_id: String) -> int:
	return CLASSES.find(RtsHulls.class_of(hull_id))


## A hull fraction (0..1) as whole permille, 0 to 1000.
static func permille(hull_frac: float) -> int:
	return clampi(roundi(hull_frac * 1000.0), 0, 1000)


## The strength of one ship of hull `hull_id` with `hull_permille` of its hull left (thousandths).
@warning_ignore("integer_division")
static func ship_strength(hull_id: String, hull_permille: int, weights: Array) -> int:
	var w := int(weights[class_index(hull_id)])
	var share := HULL_FLOOR + (1000 - HULL_FLOOR) * clampi(hull_permille, 0, 1000) / 1000
	return w * share / 1000


## The strength of a list of ships given as [hull id, hull permille] pairs (thousandths). This is the
## form the team view's records take.
static func of_entries(entries: Array, weights: Array) -> int:
	var total := 0
	for e: Array in entries:
		total += ship_strength(str(e[0]), int(e[1]), weights)
	return total


## The strength of undamaged ships given by their hull ids (thousandths).
static func of_hulls(hull_ids: Array, weights: Array) -> int:
	var total := 0
	for hid in hull_ids:
		total += ship_strength(str(hid), 1000, weights)
	return total


## The strength of team `team`'s living ships among `ships` (Ship nodes), in thousandths.
static func of_ships(ships: Array, team: int, weights: Array) -> int:
	var total := 0
	for s in ships:
		if is_instance_valid(s) and s.alive and s.team == team:
			total += ship_strength(s.hull_id, permille(s.hull_frac()), weights)
	return total
