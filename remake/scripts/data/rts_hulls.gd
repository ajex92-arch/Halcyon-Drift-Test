class_name RtsHulls
extends RefCounted
## WHAT THIS IS: the numbers of the yard in one place: how many ships a team may
## have, what a bought ship costs the Admiral, how long each kind of ship takes to
## build, how many things build side by side, how long the queues may be, how the
## arrivals are drawn, and how the computer Admiral decides what to buy. Nothing
## here is tuned in code: every number is a named constant with its unit, so a
## later answer from the player is a one-line change.
##
## HOW IT WORKS: only constants and small static functions. A hull belongs to a
## class by its size class (Ships.size_of): "squadron" (the small hulls, bought
## in threes), "corvette", "frigate" or "capital". The class decides the build
## time, the line it builds on (the yard builds every ship except the capital
## ships, the warp line builds those) and how many ships one item holds. The price
## of a bought ship is the pilot's price times ADMIRAL_PRICE_SHARE percent.
##
## WHO USES IT: Production (the build list), Capacity (the fleet limit), Arrivals
## and RtsFx (where and how a new ship appears), Standin (the skill of a bought
## ship's brain), AdmiralProduction (the computer's buying), the Yard tab and the
## tests.

# --- the fleet limit -----------------------------------------------------------------

## How many ships of the fleet a team may have at once, counted by ship (a squadron
## of three counts 3, a big ship 1). A place is taken when a build starts and given
## back when the ship dies or a started build is cancelled. This is the one home of
## the limit; it changes only in a commit of its own.
const CAP_IN_FORCE := 18

# --- prices ----------------------------------------------------------------------------

## What the Admiral pays for a bought ship, as a whole-number percent of the price a
## pilot pays for the same hull (Ships.HULLS "price"). 100 means the same price.
const ADMIRAL_PRICE_SHARE := 100
## What a squadron of three Scouts costs the Admiral, in credits (a pilot's Scout is
## free, but a free squadron would fill the fleet limit for nothing).
const SCOUT_SQUAD_PRICE := 150
## How many ships a squadron of small hulls has when it is full.
const SQUADRON_SIZE := 3

# --- build times, in ticks (a tick is a sixtieth of a second) --------------------------

## A squadron of small ships: 20 seconds.
const BUILD_TICKS_SQUADRON := 1200
## One corvette: 25 seconds.
const BUILD_TICKS_CORVETTE := 1500
## One frigate: 40 seconds.
const BUILD_TICKS_FRIGATE := 2400
## One capital ship: 60 seconds, the last WARP_TICKS of which are the warp streak.
const BUILD_TICKS_CAPITAL := 3600
## The warp streak of a capital ship, in ticks: 4 seconds.
const WARP_TICKS := 240
## One mining drone: 6 seconds (Structures.MINING_DRONE "build").
const BUILD_TICKS_DRONE := 360

# --- lines: how many items build side by side --------------------------------------------

## The yard builds this many ships at once (every ship except the capital ships).
const LINE_YARD := 2
## The warp line builds this many capital ships at once.
const LINE_WARP := 1
## The laboratory researches this many projects at once.
const LINE_LAB := 1
## The module dock builds this many modules at once.
const LINE_DOCK := 1
## The drone bay builds this many mining drones at once.
const LINE_DRONE := 1

# --- queue depths: how many items one kind may have in the list -------------------------

## Ship items in the list, counting the ones building, waiting and on hold (the yard
## and the warp line together).
const DEPTH_SHIPS := 5
## Research items in the list.
const DEPTH_RESEARCH := 3
## Module items in the list.
const DEPTH_MODULES := 2
## Mining drones in the list.
const DEPTH_DRONES := 6

# --- arrivals ---------------------------------------------------------------------------

## How long a small ship takes to slide out of the mothership, in ticks: 1.5 seconds.
## It is only drawn; the ship is in its place from the first tick.
const SLIDE_TICKS := 90
## The angles, in degrees from the mothership's heading, where a capital ship's warp
## spot is tried, in this order.
const WARP_ANGLES := [90, -90, 45, -45, 135, -135, 0]
## How far past the mothership's outline a capital ship's spot is, in world units, on
## top of half the beam and the ship's own radius.
const WARP_BEYOND := 200.0
## How much room a capital ship's spot needs, in world units past its radius.
const WARP_CLEAR := 60.0
## How far ahead of the bow the "mothership" rally point is, in world units.
const RALLY_AHEAD := 1200.0

# --- the bought ships' brain ---------------------------------------------------------------

## The skill (0 to 1) of the pilot brain that flies a bought ship until the squad
## engine exists. 0.77 is the pilot skill whose aim equals a minion's.
const STANDIN_SKILL := 0.77

# --- the computer Admiral's buying ----------------------------------------------------------------

## The master switch: false and the computer Admiral buys no fleet ships.
const COMPUTER_BUYS := true
## Switch: the computer holds an unfundable head of the list so the next item can start.
const COMPUTER_HOLDS_HEAD := true
## Switch: the computer saves for a capital ship once it can build one.
const COMPUTER_SAVES_CAPITAL := true
## Switch: the computer keeps Fighter squadrons on repeat while it is below its fill target.
const COMPUTER_REPEATS := true
## An item at the head of the list whose price is more than the treasury plus this many seconds
## of income is held, so the item behind it can start.
const HEAD_WAIT_S := 20.0
## The income is the treasury's earnings over this many seconds.
const INCOME_WINDOW_S := 60.0
## The fill schedule: the match times (seconds) at which the fleet (living, building and waiting
## ships) must be at least the matching percent of the fleet limit. Between two times the target
## rises in a straight line, from 0 at the start of the match.
const FILL_SECONDS := [360.0, 720.0, 1080.0]
const FILL_PERCENT := [30, 70, 90]  # the percents of the fleet limit, one for each time in FILL_SECONDS
## The credits the computer keeps back from its fleet buying, outside a saving goal.
const RESERVE := 300
## A saving goal for a capital ship is given up after this many seconds.
const SAVING_LAPSE_S := 180.0
## The mix: one corvette per this many squadrons once the Corvette Facility stands, one frigate per
## this many once the Frigate Facility stands, and one squadron in this many a Lance or Bomber
## squadron once the research is done.
const SQUADRONS_PER_CORVETTE := 3
const SQUADRONS_PER_FRIGATE := 2  # one frigate per this many squadrons
const SPECIAL_ONE_IN := 3  # one squadron in this many is a special squadron
## The most capital ships (alive, building and waiting) the computer keeps, as a percent of the
## fleet limit (34 of 18 is 6).
const CAPITAL_MAX_PERCENT := 34


## The percent of the fleet limit the computer's fleet should be at `seconds` into the match.
static func fill_percent(seconds: float) -> float:
	var x0 := 0.0
	var y0 := 0.0
	for i in FILL_SECONDS.size():
		var x1: float = FILL_SECONDS[i]
		var y1 := float(FILL_PERCENT[i])
		if seconds <= x1:
			return y0 + (y1 - y0) * (maxf(seconds, 0.0) - x0) / (x1 - x0)
		x0 = x1
		y0 = y1
	return y0


## How many ships the computer's fleet should have at `seconds` into the match, for a fleet limit
## of `cap`: the schedule's percent of the limit, rounded up.
static func fill_target(seconds: float, cap: int = CAP_IN_FORCE) -> int:
	return ceili(float(cap) * fill_percent(seconds) / 100.0 - 0.0001)


# --- the kinds of hull ------------------------------------------------------------------------

## The class name of hull `hull_id`: "squadron" (size 0), "corvette" (size 1), "frigate"
## (size 2) or "capital" (size 3).
static func class_of(hull_id: String) -> String:
	match Ships.size_of(hull_id):
		0:
			return "squadron"
		1:
			return "corvette"
		2:
			return "frigate"
	return "capital"


## Is `hull_id` a capital ship (built on the warp line)?
static func is_capital(hull_id: String) -> bool:
	return class_of(hull_id) == "capital"


## The record kind a bought hull makes: "squadron" for the small hulls, "ship" for the
## rest (the kinds of the Squad record).
static func record_kind(hull_id: String) -> String:
	return "squadron" if class_of(hull_id) == "squadron" else "ship"


## How many ships an item of `hull_id` may hold at most: 3 for the small hulls, 1 for
## the others.
static func max_count(hull_id: String) -> int:
	return SQUADRON_SIZE if class_of(hull_id) == "squadron" else 1


## The line `hull_id` builds on: "warp" for the capital ships, "yard" for the rest.
static func line_of(hull_id: String) -> String:
	return "warp" if is_capital(hull_id) else "yard"


## How many ticks an item of `hull_id` takes to build.
static func build_ticks(hull_id: String) -> int:
	match class_of(hull_id):
		"squadron":
			return BUILD_TICKS_SQUADRON
		"corvette":
			return BUILD_TICKS_CORVETTE
		"frigate":
			return BUILD_TICKS_FRIGATE
	return BUILD_TICKS_CAPITAL


## What the Admiral pays for one ship of `hull_id`, in whole credits: the pilot's price
## times ADMIRAL_PRICE_SHARE percent, except a Scout, whose squadron costs
## SCOUT_SQUAD_PRICE for the three.
static func unit_price(hull_id: String) -> int:
	if hull_id == "scout":
		return roundi(float(SCOUT_SQUAD_PRICE) / float(SQUADRON_SIZE))
	return roundi(float(Ships.HULLS[hull_id]["price"]) * float(ADMIRAL_PRICE_SHARE) / 100.0)


## What the Admiral pays for an item of `count` ships of `hull_id`, in whole credits.
static func price_of(hull_id: String, count: int) -> int:
	return unit_price(hull_id) * count
