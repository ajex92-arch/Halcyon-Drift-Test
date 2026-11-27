class_name AdmiralMothershipMover
extends RefCounted
## WHAT THIS IS: the part of the AI admiral that moves our mothership (the
## huge home ship that is our base) around the map late in the match.
##
## HOW IT WORKS: motherships can only move from 20:00
## (Rules.MOTHERSHIP_MOVE_UNLOCK, 1200 s; Rules.move_unlock_time()). Each
## admiral think it decides:
##   - Hurt (under half hull) and away from home: fly back home.
##   - Hurt, or our base is under attack: otherwise stay where it is.
##   - Otherwise, when our fleet is at least as strong as theirs, go 35% of
##     the way up the mid lane (ADVANCE_LANE, ADVANCE_FRAC). It is always the
##     mid lane, also during a siege. (If each admiral follows its own push
##     lane, or the lane the other mothership is on, the two motherships
##     park on different lanes, top against bottom some 30,000 units apart,
##     and chase each other from lane to lane: no siege meets anything and
##     no match ends. On the shortest lane they meet.)
##     (DESIGN.md C19 also tested "only during a siege" and "never"; the
##     "advance" rule ended the most matches.)
## While the admiral is out flying its own ship (AdmiralField) no move order
## can be given (the admiral must be docked, AdmiralCommand.move_blocker()),
## so it does not try: nothing fails every second, and the 2-minute timer is
## not used up. It decides again when the admiral is back on the bridge.
## The fall-back is the one order that cannot wait for a trip to end, so
## AdmiralField asks fallback_due(): while it is due the admiral does not
## launch, and a ship in the field is recalled at once. The order then goes
## out in the think after the seat is back in the chair.
## No new order is given while the last move is still under way. Apart from
## the fall-back when hurt, a new move order comes at most once every
## 2 minutes (120 s, MOVE_GAP). ADVANCE_FRAC and MOVE_GAP are tuned
## numbers: a feature module may change them for one match
## ("mothership_advance_frac", "mothership_move_gap"; see Rules.tune).
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.mothership_mover) and its
## tick() calls maybe_move(), but only after 20:00. The order goes through
## AdmiralCommand.move_mothership(), which also checks the rules. The siege
## plan (AdmiralSiege) follows the enemy mothership to the lane it is parked
## on (the mid lane when the other admiral is an AI too). AdmiralField calls
## fallback_due() to keep the chair free for the fall-back.

## The lane our mothership always advances up (see HOW IT WORKS). Mid is
## the shortest lane (33,600 units against 44,200 for top and bottom), so a
## fleet and the enemy mothership meet soonest there.
const ADVANCE_LANE := "mid"
## How far up the mid lane the mothership advances, as a fraction of the
## lane's length from our end (0.35 = 35%; tuned "mothership_advance_frac").
const ADVANCE_FRAC := AdmiralProfileData.TABLE["advance_frac"][0] / 1000.0
## The fewest seconds between two "advance" move orders (tuned
## "mothership_move_gap").
const MOVE_GAP := AdmiralProfileData.TABLE["move_gap_s"][0] / 1000.0
## The fall-back is due when the mothership's hull is under this fraction...
const FALLBACK_HULL := AdmiralProfileData.TABLE["fallback_hull"][0] / 1000.0
## ...and it is farther than this (world units) from its home spot.
const FALLBACK_FAR := AdmiralProfileData.TABLE["fallback_far"][0] / 1000.0

## The game world (teams, the map, match time; the motherships are read through the team view).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (fleet strength, lane points).
var lanes: AdmiralLanes
## What our team knows (our own mothership exactly: TeamView).
var view: TeamView
## This admiral's numbers (AdmiralProfile); the constants above are its standard values.
var prof: AdmiralProfile
## Match time (seconds) of our last "advance" move order (not counting the
## fall-back when hurt). Starts far in the past (-999) so the first move
## can happen at once.
var last_move_t := -999.0


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes, p: AdmiralProfile = null) -> void:
	world = w
	team = t
	lanes = l
	prof = p if p != null else AdmiralProfile.for_team(t, Game.options)
	view = TeamView.of(w, t, prof)


## Is team `team`'s fall-back due? True when its mothership is alive, under
## half hull (FALLBACK_HULL) and more than FALLBACK_FAR from its home spot:
## the one move the mover makes whatever else is going on. maybe_move() uses
## it for the order; AdmiralField uses it to keep the admiral in the chair.
static func fallback_due(world: World, team: int, prof: AdmiralProfile = null) -> bool:
	var ms := TeamView.of(world, team).own_ms()
	if ms == null or not ms.alive:
		return false
	var home: Vector2 = world.map.mothership_pos[team]
	var hull_limit := FALLBACK_HULL if prof == null else prof.f("fallback_hull")
	var far := FALLBACK_FAR if prof == null else prof.f("fallback_far")
	return ms.hull_frac() < hull_limit and ms.global_position.distance_to(home) > far


## Decide whether to move our mothership now, and order the move if so.
## (See the notes at the top for the rules.)
func maybe_move() -> void:
	# Step 1: no mothership, or it is still flying to its last target
	# (move_target is "INF", meaning "none", when it isn't moving).
	var ms := view.own_ms()
	if ms == null or ms.move_target != Vector2.INF:
		return
	var ts := world.teams[team]
	# The admiral is out in its own ship: no move order is possible now.
	if not ts.admiral_docked:
		return
	# Step 2: under attack or badly hurt: fall back to the home position
	# (where it started the match).
	var home: Vector2 = world.map.mothership_pos[team]
	if ms.hull_frac() < prof.f("fallback_hull") or ts.defending(world.time):
		if fallback_due(world, team, prof):
			AdmiralLog.of(world).expect(team, "MOTHERSHIP_MOVE", "mover.fallback", "pulls the mothership back home", "staying and fighting", "its hull is at %d%% and it is far from home" % roundi(ms.hull_frac() * 100.0))
			AdmiralLog.of(world).feed(world, team, "The %s mothership is falling back to its home position." % Rules.TEAM_DISPLAY[team])
			world.command.move_mothership(team, home)
		return
	# Step 3: advance up the mid lane (ADVANCE_LANE) when we're at least
	# even, whatever lane we are pushing or sieging. That means shorter trips
	# for respawned pilots, its guns join the fights, and sieges reach the
	# enemy before their defenders respawn. (Playtest: with both motherships
	# at home, 50-minute matches never ended. And when the lane followed the
	# push or siege lane, it hopped lanes as that flickered, and pilots
	# flying home chased it across the map for minutes.)
	if lanes.measure(team) < lanes.measure(1 - team) * prof.f("mover_edge"):
		var lg := AdmiralLog.of(world)
		if lg.wants(team):
			lg.not_yet(team, "mover.hold", "weaker", "holds the mothership: %s%s, it needs %.1f times" % [lanes.versus(), lanes.measure_tag(), prof.f("mover_edge")])
		return
	# Step 4: the spot 35% up that lane (ADVANCE_FRAC). Go if it is over
	# 2,500 away, at most one new move every 2 minutes (MOVE_GAP).
	var p := lanes.lane_point(ADVANCE_LANE, float(Rules.tune("mothership_advance_frac", prof.f("advance_frac"))))
	if ms.global_position.distance_to(p) > prof.f("advance_dist") and world.time - last_move_t > float(Rules.tune("mothership_move_gap", prof.f("move_gap_s"))):
		last_move_t = world.time
		var lg2 := AdmiralLog.of(world)
		if lg2.wants(team):
			lg2.expect(team, "MOTHERSHIP_MOVE", "mover.advance", "advances the mothership up the %s lane" % ADVANCE_LANE, "staying at home", "%s%s" % [lanes.versus(), lanes.measure_tag()])
		AdmiralLog.feed(world, team, "The %s mothership is moving up the %s lane." % [Rules.TEAM_DISPLAY[team], ADVANCE_LANE])
		world.command.move_mothership(team, p)
