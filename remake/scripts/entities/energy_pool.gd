class_name EnergyPool
extends RefCounted
## WHAT THIS IS: a pilot ship's battery (its "capacitor") plus the switch
## that decides where extra power goes ("energy routing"). DESIGN.md A5.
##
## HOW IT WORKS: the battery holds up to `max_value` energy and refills by
## `regen` energy per second. Guns (per shot; beams per second of firing),
## boosting and specials spend from it; if there isn't enough, the action
## simply doesn't happen. The routing `mode` is one of four settings in
## Rules.ENERGY_MODES (Balanced, Weapons, Shields, Thrusters). Each setting
## is a set of multipliers that trade fire rate, shield regeneration,
## shield resistance, thrust, turning and boost cost against each other
## (Weapons: guns fire 25% faster, but shields refill slower and the ship
## is a bit slower). This file only stores the mode; Ship applies the
## multipliers (m()).
##
## Part of the battery can be held by blocked shield damage: that "hard" energy
## (`hard`) cannot be spent and only drains away with time (drain_hard()); the
## battery refills only up to `max_value - hard`. A blocked hit that no longer
## fits overflows the battery and the ship overloads (Ship, OverloadRules).
##
## WHO USES IT: every Ship owns one (Ship.energy) and sets it up, refills
## it, changes its mode and reads m(). WeaponMount.update() spends from it
## when a gun fires (minions, turrets and monsters pass null instead and
## shoot for free). The HUD and the AI pilots read value, fraction() and
## mode.

## The most energy the battery can hold.
var max_value := 100.0
## The energy in the battery right now that can still be spent (the soft part).
var value := 100.0
## The part of the battery held by blocked shield damage (the hard part): it cannot be
## spent and drains away slowly (drain_hard()). `value` plus `hard` never exceeds
## `max_value`.
var hard := 0.0
## Everything spend() has taken so far, in energy points: a running total that only counts
## (a check reads it at the start and the end of a duel). It changes no behaviour.
var spent := 0.0
## How fast the battery refills, in energy per second.
var regen := 25.0
## The routing setting: one of Rules.ENERGY_BALANCED, ENERGY_WEAPONS,
## ENERGY_SHIELDS or ENERGY_THRUSTERS (0..3).
var mode := Rules.ENERGY_BALANCED


## Start full: `capacity` energy, refilling at `regen_rate` per second.
func setup(capacity: float, regen_rate: float) -> void:
	max_value = capacity
	value = capacity
	hard = 0.0
	regen = regen_rate


## Change the battery size (e.g. a module or upgrade) keeping the same
## fraction full: a half-full battery stays half full, and the hard part keeps
## its share of the battery too (never more than the room the soft part leaves).
func set_max(capacity: float) -> void:
	var f := value / max_value if max_value > 0.0 else 1.0
	var hf := hard / max_value if max_value > 0.0 else 0.0
	max_value = capacity
	value = capacity * f
	hard = clampf(capacity * hf, 0.0, maxf(0.0, capacity - value))


## Fill the battery: the soft part to the top and no hard energy.
func fill() -> void:
	value = max_value
	hard = 0.0


## Refill for one tick of `dt` seconds, never above the room the hard part leaves
## (`max_value - hard`). `mult` scales the refill speed (a Vent doubles it).
func tick(dt: float, mult: float = 1.0) -> void:
	value = minf(maxf(0.0, max_value - hard), value + regen * mult * dt)


## Load `points` of blocked shield damage into the battery: the same points leave the soft
## part and join the hard part. Returns true when the soft part could not hold them all
## (the battery overflowed): the soft part is then 0 and the hard part took only what
## was left, so `value` plus `hard` still never exceeds `max_value`.
func add_blocked(points: float) -> bool:
	if points <= 0.0:
		return false
	if points <= value:
		value -= points
		hard += points
		return false
	hard += value
	value = 0.0
	return true


## Drain the hard part for one tick of `dt` seconds at the normal speed (the battery's own
## regeneration, OverloadRules.HARD_DRAIN_PER_REGEN) times `mult`. Never below 0.
func drain_hard(dt: float, mult: float) -> void:
	if hard > 0.0:
		hard = maxf(0.0, hard - regen * OverloadRules.HARD_DRAIN_PER_REGEN * mult * dt)


## How much of the battery is not free to spend, as a 0..1 fraction: the spent part
## and the hard part together (0 if it has no size). 0 means a full, clear battery.
func load_frac() -> float:
	return (max_value - value) / max_value if max_value > 0.0 else 0.0


## Try to spend `amount` energy. Returns true and takes it if there is
## enough; otherwise returns false and takes nothing.
func spend(amount: float) -> bool:
	if value < amount:
		return false
	value -= amount
	spent += amount
	return true


## How full the battery is, as a 0..1 fraction (0 if it has no size).
func fraction() -> float:
	return value / max_value if max_value > 0.0 else 0.0


## One multiplier from the current routing setting. `key` is one of:
## "fire" (fire rate), "regen" (shield refill speed), "sresist" (extra
## shield resistance, a 0..1 fraction to add), "thrust" (engine push and
## top speed), "turn" (turning speed) or "boost_cost" (boost energy cost).
func m(key: String) -> float:
	return float(Rules.ENERGY_MODES[mode][key])
