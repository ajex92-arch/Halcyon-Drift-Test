class_name PracticeDrones
extends RefCounted
## WHAT THIS IS: the numbers of the practice range's target drones: the three
## kinds of drone, how long a destroyed one takes to come back, and where the
## default set of drones is put on the map. Nothing here runs by itself.
##
## HOW IT WORKS: ROWS is one table, one row for each kind of drone ("still",
## "moving" and "capital"). Every row has the same five fields:
##   label     the name the drone shows
##   radius    its hit circle [world units]
##   hull      its hit points
##   speed     how fast it moves along its loop [world units a second]; 0 = it
##             stays where it is
##   sections  how many armour sections it has (1 for now: a drone wears as a
##             whole, like a minion)
## A moving or drifting drone (speed above 0) flies round a circle whose
## length is LOOP_LEN, starting at its home place, and faces the way it flies.
## The default set the range puts on the map is a table of points
## (PLACEMENT, CAPITAL_AT): each is worked out from a team's lane post, so it
## follows the map. Change a number here and the whole range follows.
##
## WHO USES IT: PracticeDrone reads its row when it is made; PracticeRange
## makes the default set and the replacements; PracticeTrials names the kinds
## in its trials; UnitVisual draws a drone from its row's radius.

## The rows, by kind of drone.
const ROWS := {
	"still": {"label": "Target drone", "radius": 12.0, "hull": 400.0, "speed": 0.0, "sections": 1},
	"moving": {"label": "Moving target drone", "radius": 12.0, "hull": 400.0, "speed": 300.0, "sections": 1},
	"capital": {"label": "Capital target drone", "radius": 180.0, "hull": 6000.0, "speed": 40.0, "sections": 1},
}
## The length of the circle a moving or drifting drone flies round [world units].
const LOOP_LEN := 1200.0
## How long a destroyed drone takes to come back, in the same place [seconds].
const REPLACE_S := 3.0
## How many ticks that is (a timer counts ticks, not seconds).
const REPLACE_TICKS := 180
## The lane whose post the default set stands beside, for each team.
const POST_LANE := "top"
## The default set beside a team's lane post: for each kind, how far along the
## lane toward the enemy from the post it stands [world units], and how far
## across the lane each of its drones is [world units]. One drone for each
## number in "side".
const PLACEMENT := {
	"still": {"along": 900.0, "side": [-600.0, -200.0, 200.0, 600.0]},
	"moving": {"along": 1700.0, "side": [-675.0, -225.0, 225.0, 675.0]},
}
## Where the capital drone drifts: the middle lane's centre line at the middle
## of the map.
const CAPITAL_AT := Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
## The most steps a drone's place is moved to clear a rock [steps].
const NUDGE_STEPS := 12
## How far each step of that move is [world units].
const NUDGE := 250.0


## True when `id` is a kind of drone this table has a row for.
static func has_row(id: String) -> bool:
	return ROWS.has(id)


## The row of kind `id`, or an empty dictionary for a kind it has no row for.
static func row(id: String) -> Dictionary:
	return ROWS.get(id, {})


## The radius of the circle a moving or drifting drone of kind `id` flies round
## [world units]; 0 for a drone that stays where it is.
static func loop_radius(id: String) -> float:
	if float(row(id).get("speed", 0.0)) <= 0.0:
		return 0.0
	return LOOP_LEN / TAU
