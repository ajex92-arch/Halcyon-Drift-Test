class_name AdmiralSiege
extends RefCounted
## WHAT THIS IS: the AI admiral's late-game attack plan. A "siege" sends
## our big ships (frigates and capital ships) and bombers together down one
## lane to attack the enemy mothership. Destroying the enemy mothership
## wins the match.
##
## HOW IT WORKS: after 20:00 (1200 s of match time), if we have at least 2
## healthy big ships and the upper hand, it picks the lane where the enemy has
## the fewest lane defences (its outer, inner and inhibitor turret and its
## defense post) and declares a siege there (unless the enemy mothership is
## parked up a lane, more than PARKED_DIST (2,500) from its home spot: then
## the siege goes to the lane it is on). A siege has two phases, stored in
## TeamState.siege_phase:
##   "gather":  big ships meet at a staging point part-way down the lane,
##              so the slow capital ships arrive together.
##   "assault": everyone closes on the enemy mothership.
## It calls the siege off when no big ships are left, or when the assault
## stalls (_run_siege() explains how it decides that). After a call-off it
## waits 60 s before it may declare another siege.
## (Playtest: 50-minute matches never touched a mothership while the big
## ships kept to their separate lane posts; sieges fixed that.)
## The constants below are the standard column of AdmiralProfileData; the admiral reads its own
## team's AdmiralProfile (prof). Every number of the plan (PARKED_DIST aside) is also
## a "tuned number": it is read through Rules.tune(name, constant), so a
## feature module may change it for one match (the names are in
## Rules.TUNABLES, all starting with "siege_"). With no feature on, the
## constants are used as they are.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.siege) and calls update()
## once a second (through AdmiralAI._siege). PilotAI reads
## TeamState.siege_lane and siege_phase to send big ships and bombers.
## AdmiralWaypoint puts the team waypoint on the siege lane while one runs.
## TeamState can also call our siege off when the enemy attacks our own
## base.

## Match time (seconds) before which no siege is declared: 1200 s = 20:00
## (tuned "siege_start").
const START_TIME := AdmiralProfileData.TABLE["siege_start_s"][0] / 1000.0
## Healthy big ships (over half their hull) needed to declare a siege
## (tuned "siege_min_healthy").
const MIN_HEALTHY := AdmiralProfileData.TABLE["siege_min_healthy"][0] / 1000.0
## To declare a siege our fleet strength (AdmiralLanes.fleet_power) must
## be at least this many times the enemy's (tuned "siege_power_edge")...
const POWER_EDGE := AdmiralProfileData.TABLE["siege_power_edge"][0] / 1000.0
## ...unless the enemy mothership's hull fraction is already this low or
## lower (0.6 = 60%; tuned "siege_ms_hurt").
const MS_HURT := AdmiralProfileData.TABLE["siege_ms_hurt"][0] / 1000.0
## Big ships massed at the staging point that start the assault (tuned
## "siege_gather_count").
const GATHER_COUNT := AdmiralProfileData.TABLE["siege_gather_count"][0] / 1000.0
## Seconds of gathering after which whoever is there attacks (tuned
## "siege_gather_time").
const GATHER_TIME := AdmiralProfileData.TABLE["siege_gather_time_s"][0] / 1000.0
## How close (world units) to the staging point a big ship must be to
## count as massed (tuned "siege_gather_radius").
const GATHER_RADIUS := AdmiralProfileData.TABLE["siege_gather_radius"][0] / 1000.0
## How close (world units) to the enemy mothership's hull a big ship must
## get to count as "contact" (tuned "siege_contact_dist").
const CONTACT_DIST := AdmiralProfileData.TABLE["siege_contact_dist"][0] / 1000.0
## Seconds after contact at which the stall check is made (tuned
## "siege_stall_time")...
const STALL_TIME := AdmiralProfileData.TABLE["siege_stall_time_s"][0] / 1000.0
## ...by then the enemy mothership must have lost this hull fraction (0.15
## = 15%), or the assault has stalled (tuned "siege_stall_frac").
const STALL_FRAC := AdmiralProfileData.TABLE["siege_stall_frac"][0] / 1000.0
## Seconds of assault with no contact at all after which it has stalled
## (tuned "siege_no_contact_time").
const NO_CONTACT_TIME := AdmiralProfileData.TABLE["siege_no_contact_s"][0] / 1000.0
## Seconds after a call-off before another siege may be declared (tuned
## "siege_cooldown").
const COOLDOWN := AdmiralProfileData.TABLE["siege_cooldown_s"][0] / 1000.0
## How far (world units) the enemy mothership may be off the siege lane
## before the siege follows it to the lane it is on now (tuned
## "siege_follow_dist").
const FOLLOW_DIST := AdmiralProfileData.TABLE["siege_follow_dist"][0] / 1000.0
## How far (world units) the enemy mothership must be from its home spot to
## count as "parked up a lane": a new siege then goes to the lane it is on.
## (Not a tuned number.)
const PARKED_DIST := AdmiralProfileData.TABLE["siege_parked_dist"][0] / 1000.0

## The game world (the map and the match time; ships, nodes and motherships are read through the team view).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (we use its fleet strength measure).
var lanes: AdmiralLanes
## What our team knows: our own ships exactly, the enemy mothership, fleet and turrets as far as seen (TeamView).
var view: TeamView
## This admiral's numbers (AdmiralProfile).
var prof: AdmiralProfile
## Match time (seconds) before which we won't declare a new siege: set to
## COOLDOWN (60 s) after a siege is called off.
var cooldown_until := 0.0
## Match time (seconds) when our first big ship got within CONTACT_DIST
## (3,000 units) of the enemy mothership's hull in this assault. 0 =
## nobody has got there yet.
var contact_t := 0.0
## The enemy mothership's hull fraction (how much hull it has left: 1.0 =
## full, 0.0 = destroyed) when our first big ship got there. It is also set
## when the assault starts, then measured again on contact. The stall check
## compares against it.
var contact_ms_hp := 1.0


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes, p: AdmiralProfile = null) -> void:
	world = w
	team = t
	lanes = l
	prof = p if p != null else AdmiralProfile.for_team(t, Game.options)
	view = TeamView.of(w, t, prof)


## Run the siege plan for one admiral think (once a second). With a siege on,
## it checks whether to call it off, follows the enemy mothership if it has
## moved to another lane, and moves "gather" on to "assault". With no siege,
## it decides whether to start one. `ts` is our team's shared state.
## Returns true when the siege started, changed or ended, so the admiral
## should move the team waypoint at its next think.
func update(ts: TeamState) -> bool:
	# Step 1: count our big ships, and how many have over half their hull.
	var bigs := 0
	var healthy := 0
	for s: Ship in view.own_bigs():
		bigs += 1
		if s.hull_frac() > prof.f("siege_healthy_hull"):
			healthy += 1
	if ts.siege_lane != "":
		return _run_siege(ts, bigs)
	# Step 2: no siege yet. Only after 20:00 (START_TIME), with 2+ healthy
	# big ships (MIN_HEALTHY), while our base isn't under attack, and not
	# right after a call-off.
	var start := float(Rules.tune("siege_start", prof.f("siege_start_s")))
	var min_healthy := int(Rules.tune("siege_min_healthy", prof.i("siege_min_healthy")))
	if world.time < start or healthy < min_healthy or ts.defending(world.time) or world.time < cooldown_until:
		var lg := AdmiralLog.of(world)
		if lg.wants(team):
			if world.time < start:
				lg.not_yet(team, "siege.gate", "early", "no siege before %s: it is too early" % Util.clock(start))
			elif healthy < min_healthy:
				lg.not_yet(team, "siege.gate", "healthy", "no siege yet: %d healthy big ships, it needs %d" % [healthy, min_healthy])
			elif ts.defending(world.time):
				lg.not_yet(team, "siege.gate", "defending", "no siege yet: our base is under attack")
			else:
				lg.not_yet(team, "siege.gate", "cooldown", "no siege yet: it waits %d seconds after the last call-off" % roundi(prof.f("siege_cooldown_s")))
		return false
	# Step 3: only go when we have the edge (we won a fight: their ships are
	# dead or out of position), like a MOBA team going for the base after a
	# teamfight, or when the enemy mothership is already hurt. Our fleet must
	# be at least 1.2 times theirs (POWER_EDGE; AdmiralLanes.measure: fleet_power, or the fitted strength while the profile switch fitted_strength is on), or
	# their mothership down to 60% hull or less (MS_HURT). (Playtest: sieges
	# at even strength always met the whole defending fleet at its own guns.)
	var ems2_present := view.enemy_ms_present()
	var edge := float(Rules.tune("siege_power_edge", prof.f("siege_power_edge")))
	var hurt := float(Rules.tune("siege_ms_hurt", prof.f("siege_ms_hurt")))
	if lanes.measure(team) < lanes.measure(1 - team) * edge and (not ems2_present or view.enemy_ms_hull() > hurt):
		var lg2 := AdmiralLog.of(world)
		if lg2.wants(team):
			lg2.not_yet(team, "siege.edge", "edge", "no siege yet: %s last seen%s, it needs %.1f times" % [lanes.versus(), lanes.measure_tag(), edge])
		return false
	# Step 4: pick the lane where the enemy has the fewest lane turrets (on a
	# tie, the first in top, mid, bot order).
	var best := ""
	var fewest := 99
	var counts := {}
	for lane: String in MapLayout.LANE_ORDER:
		# The enemy's lane turrets and its defense post on the lane (one more defence), as far as we know.
		var n := view.enemy_turrets(lane)
		counts[lane] = n
		if n < fewest:
			fewest = n
			best = lane
	# The enemy mothership is parked up a lane (it is, from 20:00 on): siege
	# that lane at once. With the fewest-turret lane the siege would be
	# re-aimed a second later at the lane the enemy mothership is on (step 3
	# of _run_siege).
	if ems2_present and view.enemy_ms_pos().distance_to(world.map.mothership_pos[1 - team]) > prof.f("siege_parked_dist"):
		best = world.map.lane_for(view.enemy_ms_pos())
	# Step 5: declare it and start gathering. (We return true below, so the
	# waypoint moves at once.)
	var lg3 := AdmiralLog.of(world)
	if lg3.wants(team):
		var others := PackedStringArray()
		for lane: String in MapLayout.LANE_ORDER:
			if lane != best:
				others.append("the %s lane (%d defences)" % [lane, int(counts.get(lane, 0))])
		lg3.expect(team, "SIEGE", "siege.declare", "declares a siege on the %s lane" % best, " and ".join(others),
			"%s last seen%s (it needs %.1f times) and %d big ships are healthy" % [lanes.versus(), lanes.measure_tag(), edge, healthy])
	world.command.set_siege(team, best, "gather")
	# "team" tone: only our side's HUD shows this, so the enemy doesn't get
	# our plan.
	Events.feed.emit("The %s fleet is massing to assault the %s mothership (%s)." % [Rules.TEAM_DISPLAY[team], Rules.TEAM_DISPLAY[1 - team], MapLayout.LANES[best]["label"].to_lower()], "team", team)
	return true


## A siege is on: call it off if it is lost or stalled, follow the enemy
## mothership to its new lane, and switch "gather" to "assault" when the
## fleet is ready. `bigs` is how many big ships we have alive. Returns true
## when any of that happened (the waypoint should move).
func _run_siege(ts: TeamState, bigs: int) -> bool:
	var move_waypoint := false
	var ems_present := view.enemy_ms_present()
	# Step 1: is the assault stalled? A stalled assault is called off so the
	# fleet can regroup (playtest: one ran for 15 minutes). Stalled means:
	# the enemy mothership lost less than 15% hull (STALL_FRAC) in the 120 s
	# (STALL_TIME) after our first big ship got within 3,000 (CONTACT_DIST)
	# of it, or nobody got there at all in 300 s (NO_CONTACT_TIME). (When
	# this was timed from the assault order instead, slow capital ships
	# arrived with about 30 s left, and every siege was called off right at
	# the enemy hull.)
	var stalled := false
	if ts.siege_phase == "assault" and ems_present:
		# Note the moment our first big ship gets close, and the enemy hull then.
		if contact_t <= 0.0:
			var contact_dist := float(Rules.tune("siege_contact_dist", prof.f("siege_contact_dist")))
			for s: Ship in view.own_bigs():
				if view.enemy_ms_hull_dist(s.global_position) < contact_dist:
					contact_t = world.time
					contact_ms_hp = view.enemy_ms_hull()
					break
		if contact_t > 0.0:
			var stall_time := float(Rules.tune("siege_stall_time", prof.f("siege_stall_time_s")))
			var stall_frac := float(Rules.tune("siege_stall_frac", prof.f("siege_stall_frac")))
			stalled = world.time - contact_t > stall_time and view.enemy_ms_hull() > contact_ms_hp - stall_frac
		else:
			stalled = world.time - ts.siege_t > float(Rules.tune("siege_no_contact_time", prof.f("siege_no_contact_s")))
	# Step 2: call it off: no big ships left, or stalled. No new siege for
	# 60 s (COOLDOWN).
	if bigs < 1 or stalled:
		AdmiralLog.of(world).expect(team, "SIEGE", "siege.off", "calls off the siege", "pressing on", "no big ships are left" if bigs < 1 else "the assault stalled")
		AdmiralLog.feed(world, team, "The %s fleet calls off its assault on the %s mothership." % [Rules.TEAM_DISPLAY[team], Rules.TEAM_DISPLAY[1 - team]])
		world.command.set_siege(team, "", "")
		cooldown_until = world.time + float(Rules.tune("siege_cooldown", prof.f("siege_cooldown_s")))
		return true
	# Step 3: the enemy mothership has moved more than 4,000 units
	# (FOLLOW_DIST) off our siege lane (it can move from 20:00): siege the
	# lane it is on now.
	if ems_present and float(view.enemy_ms_on_lane(ts.siege_lane)["dist"]) > float(Rules.tune("siege_follow_dist", prof.f("siege_follow_dist"))):
		AdmiralLog.of(world).expect(team, "SIEGE", "siege.follow", "moves the siege to the %s lane" % world.map.lane_for(view.enemy_ms_pos()), "staying on the %s lane" % ts.siege_lane, "the enemy mothership has moved more than %d units off it" % roundi(prof.f("siege_follow_dist")))
		world.command.set_siege(team, world.map.lane_for(view.enemy_ms_pos()), ts.siege_phase)
		move_waypoint = true
	if ts.siege_phase == "gather":
		# Step 4: go when two big ships (GATHER_COUNT) have massed within
		# 3,000 (GATHER_RADIUS) of the staging point (or after 45 s,
		# GATHER_TIME: whoever is there goes).
		var stage := view.stage_point(ts.siege_lane)
		var radius := float(Rules.tune("siege_gather_radius", prof.f("siege_gather_radius")))
		var massed := 0
		for s: Ship in view.own_bigs():
			if s.global_position.distance_to(stage) < radius:
				massed += 1
		if massed >= int(Rules.tune("siege_gather_count", prof.i("siege_gather_count"))) or world.time - ts.siege_t > float(Rules.tune("siege_gather_time", prof.f("siege_gather_time_s"))):
			AdmiralLog.of(world).expect(team, "SIEGE", "siege.assault", "starts the assault on the %s lane" % ts.siege_lane, "waiting for more big ships", "%d massed of %d needed, and %d seconds of gathering" % [massed, int(Rules.tune("siege_gather_count", prof.i("siege_gather_count"))), roundi(world.time - ts.siege_t)])
			world.command.set_siege(team, ts.siege_lane, "assault")
			contact_t = 0.0
			contact_ms_hp = view.enemy_ms_hull() if ems_present else 1.0
			move_waypoint = true
	return move_waypoint
