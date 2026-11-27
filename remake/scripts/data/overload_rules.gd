class_name OverloadRules
extends RefCounted
## WHAT THIS IS: the numbers of hard energy, the overload lockout and the Vent action.
## One place for every constant, so a re-tune is a change here and in no other file.
##
## HOW IT WORKS: a ship's battery has two kinds of use. "Soft" energy is what it can still
## spend (guns, boost, specials). "Hard" energy is the part of the battery held by shield
## damage the shield has blocked: every point the shield soaks loads some of the battery
## (HARD_SHARE says how much: a whole shield's worth of blocked damage fills HARD_SHARE of an
## empty battery on any hull). Hard energy cannot be spent; it drains away slowly (see
## HARD_DRAIN_PER_REGEN and DRAIN_ONLY_RESTING). A blocked hit that no longer fits in the
## battery overloads the ship: for a lockout (class_seconds() for its hull plus one second
## per PER_STRENGTH points blocked in that tick, never more than MAX_S) its guns, boost and
## special are off and its shield zones are dark. Vent is the pilot's own way to clear the
## battery faster: movement only, hard energy drains at VENT_DRAIN_MULT times the normal
## speed and the soft part refills at VENT_REFILL_MULT times, until both are done.
## Every number is a playtest starting point taken from the combat research notes
## (a lockout of 4 to 10 seconds by hull size plus a second per 25 points, at most 15).
##
## WHO USES IT: Ship (the overload step each tick, the Vent request), EnergyPool (the drain
## rate), ShieldZones (whether an ion hit loads hard energy), the computer pilots' vent rules
## and the checks. Nothing here runs by itself.

## The share of an empty battery that a whole shield's worth of blocked damage fills with
## hard energy (a starting point).
const HARD_SHARE := 0.6
## Hard energy drains this many points a second for each point a second of the battery's own
## regeneration (1.0: as fast as the battery refills).
const HARD_DRAIN_PER_REGEN := 1.0
## True: hard energy drains only while the shield is resting (no hit for the shield's wait);
## false: it drains all the time. A lockout and a Vent drain it whatever this says.
const DRAIN_ONLY_RESTING := true
## True: an ion hit that the shield soaks loads hard energy like any blocked hit; false:
## ion hits load none.
const ION_LOADS_HARD := true
## One more second of lockout for this many points blocked in the tick that overloads.
const PER_STRENGTH := 25.0
## The longest lockout, in seconds.
const MAX_S := 15.0
## The speed hard energy drains at during a lockout, as a share of the normal speed.
const REST_HALF := 0.5
## The speed hard energy drains at during a Vent, as a multiple of the normal speed.
const VENT_DRAIN_MULT := 2.0
## The speed the soft energy refills at during a Vent, as a multiple of the normal speed.
const VENT_REFILL_MULT := 2.0
## The lockout seconds of a hull id that is not in CLASS_S (the small craft's value).
const DEFAULT_S := 2.0
## The lockout seconds the hull alone gives, by hull id. The Fighter, the corvettes, the
## frigates, the Destroyer and the Battlecruiser sit at the middles of the research ranges.
const CLASS_S := {
	"scout": 2.0, "fighter": 2.0, "lance": 2.0, "bomber": 2.0,
	"logistics": 3.5, "support": 3.5,
	"flak": 5.5, "ion": 5.5,
	"destroyer": 7.5, "battlecruiser": 10.0,
}


## The lockout seconds the hull `hull_id` gives before any attack-strength seconds are added.
## A hull id that is not in the table gets DEFAULT_S.
static func class_seconds(hull_id: String) -> float:
	return float(CLASS_S.get(hull_id, DEFAULT_S))


## The whole lockout for hull `hull_id` when `blocked` points were soaked in the tick that
## overloaded the ship: the hull's seconds plus a second for every whole PER_STRENGTH points,
## never above MAX_S.
static func lockout_seconds(hull_id: String, blocked: float) -> float:
	return minf(MAX_S, class_seconds(hull_id) + floorf(maxf(0.0, blocked) / PER_STRENGTH))
