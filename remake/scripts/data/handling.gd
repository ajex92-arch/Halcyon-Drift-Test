class_name Handling
extends RefCounted
## WHAT THIS IS: the handling table: how every pilot hull flies, in one place.
## For each hull it holds top speed, engine push, turning, reverse and side
## push, flight assist, the cap pull, boost and engine spool-up. (How a hull
## looks, what it costs and what it shoots is in Ships.HULLS; this table is
## only about flying.) DESIGN.md A5.
##
## HOW IT WORKS: TABLE is a dictionary (a lookup table): hull id, such as
## "fighter" -> that hull's flying numbers. row() hands one hull's numbers out.
## ShipStats reads them every time it works out a ship's stats, and the AI
## reads a hull's top speed through top_speed(). Nothing here runs by itself.
##
## The fields of each hull ([units] in brackets). The flight is "Newtonian-lite"
## (like real space, a ship keeps drifting until thrust pushes it elsewhere,
## with helpers that make it easy to fly; see ShipFlight):
##   max          top speed, a soft cap [world units per second]
##   accel        main engine push [world units per second, per second]
##   reverse      backward thruster push [same unit]
##   strafe       sideways ("lateral") thruster push [same unit]
##   turn         turning speed [radians per second; a full turn is about
##                6.28 radians, so 3.14 = half a turn per second]
##   turn_bleed   the share of the turning speed lost at top speed [0..1]
##   assist       flight-assist strength: how fast sideways drift is damped
##                away when not strafing [per second; higher = grippier]
##   cap_rate     how fast a speed over the cap is pulled back to it [per
##                second; higher = faster]
##   has_boost    true = a booster is built in (Shift)
##   boost_mul    main engine push is multiplied by this while boosting
##   boost_cap    top speed is multiplied by this while boosting (1.3 =
##                boost can push 30% over the cap)
##   boost_drain  energy spent per second while boosting
##   spool        seconds the main engine takes to go from idle to its full
##                push; 0 = it answers at once (every hull today)
## (A hull without a booster can get one from the Boost Cell module. ShipStats
## then uses its own push and cap numbers instead of this hull's boost_mul and
## boost_cap; boost_drain is still used.)
## The numbers above are the table's. A small craft (size class 0 in
## Ships.HULLS: Scout, Fighter, Lance Fighter, Bomber) flies at
## Rules.SMALL_CRAFT_PACE (0.8) of "max", "accel", "reverse" and "strafe":
## ShipStats multiplies the pace in with gear and research, so the boost
## multipliers, the turning numbers and Fighter Drive keep their meaning.
##
## The four big classes (corvettes, frigates, destroyers, battlecruisers) also
## have a "line" entry: the numbers of the ships-of-the-line flight model
## (ShipLineFlight), which these hulls fly by while Rules.big_hull_flight() is
## on. Then the reverse and side-thruster shares replace "reverse" and
## "strafe" above, and "turn" is the fastest the nose may spin. The classes are
## named for the sailing rates of the ships of the line: a first-rate ship is
## the heaviest, a sixth-rate the lightest (about 2,000 tons and more, 1,500,
## 1,000 and 500 tons), and the heavier the class, the slower its engines
## swivel (the speeds go with the square root of the weight).
##   rate           the sailing rate: 1 battlecruiser, 3 destroyer, 4 frigate,
##                  6 corvette
##   swivel_max     how far the main engines turn away from "pushing straight
##                  ahead" [radians, each way; 0 = they do not turn]
##   swivel_rate    how fast they turn [radians per second]
##   reverse_share  the reverse thrusters' push as a share of the main engine
##                  push [0..1]
##   strafe_share   the side thrusters' push (each side) as a share of the main
##                  engine push [0..1]
##   engine_arm     how far behind the centre of mass the main engines push,
##                  as a share of the hull's length [0..0.5]
##   side_arm       the same for the side thrusters, which sit just fore of the
##                  engines
##   gyration       how far from the centre of mass the hull's weight is spread
##                  (radius of gyration), as a share of the hull's length: the
##                  bigger it is, the harder the hull is to spin
##
## WHO USES IT: ShipStats (every ship's flight numbers), PilotAI (a hull's top
## speed), ShipLineFlight (through ShipStats), tests/flight_table_probe.gd.
##
## To change how a hull flies, change its row here; to add a hull, add a row
## here as well as the entry in Ships.HULLS.

## Every pilot hull's handling: hull id -> its flying numbers (the fields are
## explained at the top of this file).
const TABLE := {
	# Scout: the fastest ship.
	"scout": {
		"accel": 600.0, "reverse": 380.0, "strafe": 440.0, "max": 720.0, "turn": 3.6, "turn_bleed": 0.04,
		"assist": 0.6, "cap_rate": 2.8, "boost_mul": 1.8, "boost_cap": 1.3, "has_boost": true, "boost_drain": 30.0,
		"spool": 0.0,
	},
	# Fighter: the all-round dogfighter.
	"fighter": {
		"accel": 540.0, "reverse": 360.0, "strafe": 420.0, "max": 640.0, "turn": 3.2, "turn_bleed": 0.05,
		"assist": 0.7, "cap_rate": 2.6, "boost_mul": 1.9, "boost_cap": 1.34, "has_boost": true, "boost_drain": 32.0,
		"spool": 0.0,
	},
	# Lance Fighter: a heavier beam fighter.
	"lance": {
		"accel": 480.0, "reverse": 330.0, "strafe": 360.0, "max": 600.0, "turn": 2.9, "turn_bleed": 0.07,
		"assist": 0.8, "cap_rate": 2.5, "boost_mul": 1.8, "boost_cap": 1.3, "has_boost": true, "boost_drain": 32.0,
		"spool": 0.0,
	},
	# Bomber: small, but slow and without a booster.
	"bomber": {
		"accel": 220.0, "reverse": 150.0, "strafe": 100.0, "max": 400.0, "turn": 1.15, "turn_bleed": 0.22,
		"assist": 1.5, "cap_rate": 2.1, "boost_mul": 1.35, "boost_cap": 1.14, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
	},
	# Logistics Corvette: a sixth-rate hull.
	"logistics": {
		"accel": 250.0, "reverse": 190.0, "strafe": 155.0, "max": 350.0, "turn": 1.55, "turn_bleed": 0.12,
		"assist": 1.8, "cap_rate": 2.3, "boost_mul": 1.3, "boost_cap": 1.12, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
		"line": {
			"rate": 6, "swivel_max": 2.79, "swivel_rate": 2.5, "reverse_share": 0.33, "strafe_share": 0.41,
			"engine_arm": 0.45, "side_arm": 0.38, "gyration": 0.3,
		},
	},
	# Support Corvette: a sixth-rate hull.
	"support": {
		"accel": 290.0, "reverse": 210.0, "strafe": 200.0, "max": 430.0, "turn": 1.9, "turn_bleed": 0.1,
		"assist": 1.2, "cap_rate": 2.4, "boost_mul": 1.4, "boost_cap": 1.16, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
		"line": {
			"rate": 6, "swivel_max": 2.79, "swivel_rate": 2.5, "reverse_share": 0.33, "strafe_share": 0.41,
			"engine_arm": 0.45, "side_arm": 0.38, "gyration": 0.3,
		},
	},
	# Flak Frigate: a fourth-rate hull.
	"flak": {
		"accel": 125.0, "reverse": 95.0, "strafe": 52.0, "max": 250.0, "turn": 0.78, "turn_bleed": 0.36,
		"assist": 2.6, "cap_rate": 1.5, "boost_mul": 1.22, "boost_cap": 1.1, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
		"line": {
			"rate": 4, "swivel_max": 2.79, "swivel_rate": 1.75, "reverse_share": 0.3, "strafe_share": 0.375,
			"engine_arm": 0.45, "side_arm": 0.38, "gyration": 0.3,
		},
	},
	# Ion Frigate: a fourth-rate hull.
	"ion": {
		"accel": 135.0, "reverse": 100.0, "strafe": 60.0, "max": 260.0, "turn": 0.85, "turn_bleed": 0.34,
		"assist": 2.6, "cap_rate": 1.5, "boost_mul": 1.22, "boost_cap": 1.1, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
		"line": {
			"rate": 4, "swivel_max": 2.79, "swivel_rate": 1.75, "reverse_share": 0.3, "strafe_share": 0.375,
			"engine_arm": 0.45, "side_arm": 0.38, "gyration": 0.3,
		},
	},
	# Destroyer: a third-rate hull.
	"destroyer": {
		"accel": 70.0, "reverse": 50.0, "strafe": 25.0, "max": 175.0, "turn": 0.45, "turn_bleed": 0.4,
		"assist": 3.0, "cap_rate": 1.2, "boost_mul": 1.15, "boost_cap": 1.05, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
		"line": {
			"rate": 3, "swivel_max": 2.79, "swivel_rate": 1.4, "reverse_share": 0.27, "strafe_share": 0.34,
			"engine_arm": 0.45, "side_arm": 0.38, "gyration": 0.3,
		},
	},
	# Battlecruiser: the heaviest hull, a first-rate ship of the line.
	"battlecruiser": {
		"accel": 55.0, "reverse": 40.0, "strafe": 18.0, "max": 150.0, "turn": 0.32, "turn_bleed": 0.45,
		"assist": 3.2, "cap_rate": 1.1, "boost_mul": 1.12, "boost_cap": 1.04, "has_boost": false, "boost_drain": 30.0,
		"spool": 0.0,
		"line": {
			"rate": 1, "swivel_max": 2.79, "swivel_rate": 1.2, "reverse_share": 0.25, "strafe_share": 0.31,
			"engine_arm": 0.45, "side_arm": 0.38, "gyration": 0.3,
		},
	},
}


## The handling of hull `id` (its entry in TABLE). ShipStats uses it when it
## works out a ship's stats.
static func row(id: String) -> Dictionary:
	return TABLE[id]


## The top speed of hull `id`, in world units per second, before gear and
## upgrades: the table's "max", times the small craft's pace
## (Rules.SMALL_CRAFT_PACE) for a small craft. PilotAI uses it to judge whether
## a hyperspace jump saves time.
static func top_speed(id: String) -> float:
	return float(TABLE[id]["max"]) * Rules.craft_pace(Ships.size_of(id))


## Does hull `id` have a "line" entry, the numbers of the ships-of-the-line
## flight model? True for corvettes, frigates, destroyers and battlecruisers.
static func has_line(id: String) -> bool:
	return TABLE[id].has("line")
