class_name FlightTimes
extends RefCounted
## WHAT THIS IS: the published turn and stop times of the ten pilot hulls: how
## long a hull takes to swing its nose half way round from a stop, and how long
## it takes to stop from top speed. They are shown on each hull's card in the
## hangar. They are for display only: nothing in the match reads them.
##
## HOW IT WORKS: TIMES holds, for each hull of Ships.ORDER, two numbers in whole
## tenths of a second, copied from the flight table probe (the probe's turn180
## and stop_t columns): "turn180" is the time from a stop until the nose is
## within 2 degrees of the way pointing 180 degrees round, "stop" the time from
## top speed until the ship has stopped, braking along its line. line_for()
## turns one row into the card's sentence.
## A hull of the line (a corvette, frigate, destroyer or battlecruiser) flies
## by these numbers only while the build has the ships-of-the-line flight on
## (Rules.big_hull_flight()); with it off the sentence is empty for those hulls.
## The strike craft's numbers are the same either way.
## The check tests/flight_times_check.gd flies every hull as the probe does and
## fails when a number here differs from the measured one by more than 0.15 s.
## When a change moves how a hull turns or stops, that check fails on purpose:
## the builder of the change updates this table (from the probe) in the same
## commit.
##
## WHO USES IT: HangarShips (the card text), tests/flight_times_check.gd.

## Every hull's published times: hull id -> {"turn180": seconds, "stop": seconds}.
const TIMES := {
	"scout": {"turn180": 0.9, "stop": 1.9},
	"fighter": {"turn180": 1.0, "stop": 1.8},
	"lance": {"turn180": 1.1, "stop": 1.8},
	"bomber": {"turn180": 2.7, "stop": 2.6},
	"logistics": {"turn180": 2.3, "stop": 1.9},
	"support": {"turn180": 2.0, "stop": 2.0},
	"flak": {"turn180": 4.7, "stop": 2.8},
	"ion": {"turn180": 4.4, "stop": 2.7},
	"destroyer": {"turn180": 8.2, "stop": 3.5},
	"battlecruiser": {"turn180": 11.3, "stop": 4.0},
}


## The card's sentence for hull `hull_id`, for example "Turns round in 11.3 s,
## stops in 4.5 s". Empty when the hull has no row, or when it is a hull of the
## line and the build flies without the ships-of-the-line model.
static func line_for(hull_id: String) -> String:
	if not TIMES.has(hull_id):
		return ""
	if Handling.has_line(hull_id) and not Rules.big_hull_flight():
		return ""
	var row: Dictionary = TIMES[hull_id]
	return "Turns round in %.1f s, stops in %.1f s" % [float(row["turn180"]), float(row["stop"])]
