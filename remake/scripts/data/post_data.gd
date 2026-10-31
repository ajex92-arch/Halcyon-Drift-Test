class_name PostData
extends RefCounted
## WHAT THIS IS: the numbers for the lane defense posts. A defense post is an
## unarmed station at the home end of a lane, beside the lane's inhibitor
## turret, from which that lane's minion waves launch. Each team has one on each
## lane (6 in all), standing from the first second. DESIGN.md A9.
##
## HOW IT WORKS: POST holds the post's facts (the same price and build time as a
## PD turret, its own hull and armour); the constants below place it and time
## its rebuild. While a team's post on a lane is destroyed (or being rebuilt)
## no new free wave launches on that lane for that team: waves already out go
## on. Only the admiral rebuilds a destroyed post, and only after REBUILD_TICKS
## ticks (5 minutes at 60 ticks a second).
##
## WHO USES IT: DefensePost reads POST; DefensePosts (the director of the six
## posts) and PostSite read the placement and the timer; AdmiralCommand takes
## the price for a rebuild; the admiral board shows the price and the time left.

## The facts of a defense post. Fields:
##   label    the name players see
##   cost     the price of a rebuild [credits, from the team treasury]: a PD
##            turret's (TurretData.TURRETS["pd"])
##   build    how long a rebuild takes [seconds]; the post launches no wave
##            until it is finished: a PD turret's build time
##   hull     hit points
##   resist   the share (0..1) of hull damage it shrugs off (armour)
##   radius   size, a circle [world units]
##   vision   how far it sees [world units]
##   blurb    what it does, in words for players
const POST := {
	"label": "Defense Post", "cost": 450.0, "build": 25.0, "hull": 2500.0, "resist": 0.0, "radius": 70.0, "vision": 1500.0,
	"blurb": "An unarmed station beside the lane's inhibitor turret. This lane's minion waves launch from it. If it is destroyed no new wave launches from it, until the admiral rebuilds it (after the timer runs out).",
}
## How long a destroyed post waits before the admiral may rebuild it, in whole
## ticks: 18,000 ticks = 5 minutes at 60 ticks a second.
const REBUILD_TICKS := 18000
## How far (world units) toward the team's own mothership, along the lane, the post
## stands from the lane's inhibitor turret: next to it, not on it.
const BACK := 300.0
## How far (world units) along the lane toward the enemy from the post the centre
## of the five launch spots lies, so a launching minion does not appear inside the
## post.
const LAUNCH_AHEAD := 200.0
## The distance (world units) between two neighbouring launch spots, across the
## lane (five spots, like the mothership's bow).
const LAUNCH_SPACING := 90.0
## No enemy pilot ship or minion within this distance (world units) of a destroyed
## post's spot when the admiral rebuilds it: the same circle as a lane turret site's
## build circle (TurretData.BUILD_CLEAR_RADIUS).
const BUILD_CLEAR_RADIUS := TurretData.BUILD_CLEAR_RADIUS


## The text players read for the rebuild timer's time left: "rebuild in 3:21".
static func rebuild_text(ticks_left: int) -> String:
	return "rebuild in %s" % Util.clock(float(ticks_left) / float(TurretSite.TICKS_PER_SECOND))
