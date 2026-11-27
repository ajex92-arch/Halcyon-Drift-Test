class_name AdmiralAI
extends RefCounted
## WHAT THIS IS: the computer "admiral" for one team. The admiral is the
## player who doesn't fly a ship: they spend the team's shared money (the
## "treasury") and give the big orders. DESIGN.md A14 describes the AI one.
## Everything it does goes through AdmiralCommand, so it plays by exactly
## the same rules as a human admiral.
##
## HOW IT WORKS: once a second it "thinks" and works down a to-do list, in
## this order (the order matters, because money spent early is gone for
## the later steps):
##   0. Before the list, the reactions (AdmiralReactions): the team's new event
##      records are read, and a reaction whose profile switch is on acts (all four
##      are off until the lead's switch-on commit).
##   1. Mining drones come first. They mine ore, and delivered ore pays the
##      treasury and the pilots (Economy.deliver_ore), so a thin drone line
##      jumps every queue. The number it wants grows with match time.
##   2. A destroyed defense post rebuilt once its timer has run out
##      (AdmiralBuilder.rebuild_posts), then a PD turret (point defence: a
##      fast-firing defence gun) back at each of our lane turret sites that
##      lost its turret (the 18 lane turrets stand from the start;
##      AdmiralBuilder.rebuy_lost_sites).
##   3. The next step of the build PLAN: facilities (modules built onto the
##      mothership) and research, bought as soon as we can afford them
##      (AdmiralPlan).
##   4. With money to spare: more drones, repair bays behind
##      the lanes and wards (small watch drones) at jungle entrances
##      (AdmiralBuilder).
##   5. The team waypoint, a rally point on the lane we are pushing or on
##      the siege lane (AdmiralWaypoint).
##   6. After 20:00, sieges: attacks on the enemy mothership with our big
##      ships, the frigates and capital ships (AdmiralSiege).
##   7. After 20:00, moving our mothership up the mid lane (always mid)
##      when we are at least as strong as the enemy
##      (AdmiralMothershipMover).
##   8. Buying fleet ships: the computer's yard, the fundable head, the fill
##      schedule and a capital ship to save for (AdmiralProduction).
##   8b. With the profile switch fleet_play on (RT8; off in every profile until the lead's switch-on commit), the fleet
##      layer plays the bought squadrons: base defence first, the goal lane, attack or retreat, help for outnumbered
##      pilots (AdmiralFleet).
##   9. Taking the field: launching the admiral's own ship when the base is
##      attacked or 2 or more pilots are down, and docking it again when
##      that is over (AdmiralField). The thinking above carries on while the
##      ship is out, once a second as always. While the mothership is hurt
##      and far from home the ship stays docked, or is recalled at once: only
##      a docked admiral can order the fall-back (step 7).
##
## Before step 1 of its very first think, an admiral whose team holds the test
## tool "ai_calib" (--variant-team0=ai_calib:on, see Rules.VARIANT_DEFAULTS)
## draws one random number and throws it away: it shifts the shared random
## sequence so that the lane's luck check can play a seed twice as different
## matches. It is off in every normal match, and then nothing is drawn.
##
## WHO USES IT: World makes one for each team whose admiral is the computer
## (World.admiral_ai, in World.setup) and calls tick() every physics frame
## while the match is being played.
## Its parts live next to it in scripts/ai/: admiral_plan.gd,
## admiral_lanes.gd, admiral_builder.gd, admiral_waypoint.gd,
## admiral_siege.gd, admiral_mothership_mover.gd,
## admiral_production.gd and admiral_field.gd. (A "part" is a helper
## object that does one job for this admiral.) This file keeps the timers
## and the order of the to-do list; the parts do the work.
##
## Note for programmers: the parts are given the world, our team number and
## the shared AdmiralLanes helper, not a link back to this admiral. Two
## RefCounted objects that hold each other are never freed (a "reference
## cycle"), so a back-link would leak every admiral and its parts when a
## match ends.

## The build order, kept here under its old name. The real list (and the
## explanation) lives in AdmiralPlan.PLAN.
const PLAN := AdmiralPlan.PLAN
## How far ahead the plan may skip blocked steps; see AdmiralPlan.LOOKAHEAD.
const LOOKAHEAD := AdmiralPlan.LOOKAHEAD

## The game world (all ships, nodes, teams and the AdmiralCommand).
var world: World
## Which team this admiral runs: 0 = Aurelian, 1 = Vhorr.
var team := 0
## Seconds until the next think. The two teams start half a second apart
## (0.5 s and 1.0 s) so they don't think on the same frame, then each
## thinks once every 1.0 s.
var think_t := 1.0
## Seconds until we may try to place another ward (the first try after
## 30 s, then at most one try every 45 s).
var ward_t := 30.0
## Seconds until we re-place the team waypoint (first after 60 s, then
## every Rules.WAYPOINT_TIME = 75 s). Set to 0 when the siege starts,
## changes or ends (see _siege), to move the waypoint at the next think.
var waypoint_t := 60.0
## Seconds until we may try to launch another repair bay (at most one try
## every 40 s).
var bay_t := 0.0
## How many times this admiral has thought so far (once a second, whether
## its own ship is out or not). Tests use it to see that the thinking goes
## on during a field trip.
var think_count := 0
## True for a deliberately weak admiral (test option --admiral-ai=weak, see
## AdmiralWeak). Always false in the game itself.
var weak := false
## Seconds until a weak admiral may start another plan step (counts down;
## unused when `weak` is false).
var weak_plan_t := 0.0
## The numbers and switches of this admiral (AdmiralProfile: standard, v0 or weak, then any
## --admiral-set); every part is handed it.
var profile: AdmiralProfile

## Our parts (see the list at the top), made once in _init().
## What our team knows: its own units exactly, the enemy as far as it has been seen (TeamView). Every part reads the world through it.
var view: TeamView
## Questions about lanes and fleet strength (the other parts share it).
var lanes: AdmiralLanes
## Where turrets, repair bays and wards go.
var builder: AdmiralBuilder
## Where the team waypoint goes.
var waypoint: AdmiralWaypoint
## Late-game attacks on the enemy mothership.
var siege: AdmiralSiege
## Moving our own mothership after 20:00.
var mothership_mover: AdmiralMothershipMover
## Buying fleet ships (the yard's build list).
var production: AdmiralProduction
## Taking the field in the admiral's own ship (needs the admiral's seat and
## pilot brain that WorldSetup makes before this admiral).
var field: AdmiralField
## The reactions to what happens to our team (RT5 build 4a): read once a think, before step 1; each is off until its profile switch is on.
var react: AdmiralReactions
## The fleet layer (RT8 build 8a): plays the bought squadrons as one fleet after step 8. Null unless the profile switch fleet_play is on.
var fleet: AdmiralFleet
## The research steps this Admiral's profile puts in front of the plan (a preset's research order; empty for
## standard, v0 and weak). AdmiralPlan.next_step reads them at step 3.
var plan_front: Array = []
## The deputy this Admiral is the hands of, or null for a normal computer Admiral. A deputy's Admiral skips the steps
## that only the human seat has (Deputy.allows): the waypoint, sieges, the mothership move, the field, and the fleet
## layer while the human is there.
var deputy: Deputy


## Set up the admiral for team `t` in world `w`, and make its parts.
func _init(w: World, t: int, p: AdmiralProfile = null) -> void:
	world = w
	team = t
	profile = p if p != null else AdmiralProfile.for_team(t, Game.options)
	plan_front = AdmiralProfile.plan_front(profile.profile_name)
	think_t = profile.f("think_start_s") + float(t) * profile.f("think_stagger_s")
	ward_t = profile.f("ward_first_s")
	waypoint_t = profile.f("waypoint_first_s")
	bay_t = profile.f("bay_first_s")
	weak = profile.on("is_weak")
	# The team view first (it holds this team's profile), then the lane helper: every other part is handed them.
	view = TeamView.of(w, t, profile)
	lanes = AdmiralLanes.new(w, t)
	builder = AdmiralBuilder.new(w, t, lanes, profile)
	waypoint = AdmiralWaypoint.new(w, t, lanes, profile)
	siege = AdmiralSiege.new(w, t, lanes, profile)
	mothership_mover = AdmiralMothershipMover.new(w, t, lanes, profile)
	production = AdmiralProduction.new(w, t, lanes, profile)
	field = AdmiralField.new(w, t, profile)
	react = AdmiralReactions.new(w, t, lanes, field, profile)
	# The fleet layer is made only while its switch is on: with it off no object, order or read is added to the match.
	if profile.on("fleet_play"):
		fleet = AdmiralFleet.new(w, t, lanes, react, profile)
		waypoint.fleet = fleet
	# The decision log (made now, so it hears every order of the match; it writes only with --admiral-log).
	AdmiralLog.of(w)
	# One line per team per match when this team's profile is not the plain standard one (a second Admiral made for
	# the same team, for example by the mutiny, prints nothing more).
	var switch_text := AdmiralProfile.switch_line(profile)
	if switch_text != "" and not w.has_meta("admiral_switch_line_%d" % t):
		w.set_meta("admiral_switch_line_%d" % t, true)
		print(switch_text)


## Called by World every physics frame (a "tick": one small step of game
## time, 60 a second). `dt` is the seconds since the last tick. The timers
## count down every tick; the real thinking happens once a second.
func tick(dt: float) -> void:
	# Count the timers down.
	think_t -= dt
	ward_t -= dt
	waypoint_t -= dt
	bay_t -= dt
	weak_plan_t -= dt
	if think_t > 0.0:
		return
	think_t = profile.f("think_gap_s")
	think_count += 1
	# What the team knows is brought up to date once per think (nothing while the team view is off).
	view.think()
	# The calibration switch (Rules.VARIANT_DEFAULTS "ai_calib", a test tool): the
	# team that holds it draws ONE extra number from the shared random sequence
	# at its first think, and throws it away. The teams' first thinks are at
	# 0.5 s and 1.0 s, so a seed run with the switch on for team 0 and again on
	# for team 1 shifts the sequence at two different points and plays two
	# different matches. A team that does not hold it draws nothing.
	if think_count == 1 and FeatureRegistry.is_on_for(team, "ai_calib"):
		randf()
	var ts := world.teams[team]
	var cmd := world.command
	var lg := AdmiralLog.of(world)
	# The reactions (RT5 build 4a): the new records of our team's stream are read, and each reaction that is switched on acts, before the to-do list.
	react.think(ts)
	# Step 1: drones (counting the ones still being built). The economy
	# comes first: a thin drone line (fewer than 4, or fewer than 60% of the
	# target) jumps every queue (playtest: a team that lost its drones never
	# recovered). The target is 6, plus 1 for every 75 s of match time, up
	# to the drone limit (14). A drone costs 200 credits.
	var drones := world.mining_drone_count(team) + ts.drones_queued()
	var want_drones := mini(int(Structures.MINING_DRONE["max"]), profile.i("drone_base") + int(world.time / profile.f("drone_every_s")))
	# Not while the build queue is full (6 at a time): the order would only
	# fail with "Drone build queue is full", every second.
	var drone_floor := maxi(profile.i("drone_min"), int(want_drones * profile.f("drone_floor")))
	if drones < drone_floor and ts.can_afford(profile.f("drone_cost")) and ts.drones_queued() < RtsHulls.DEPTH_DRONES:
		lg.expect(team, "DRONE", "drones.floor", "orders a mining drone", "a fleet ship", "only %d drones (counting the ones building) against %d wanted, and the floor is %d" % [drones, want_drones, drone_floor])
		cmd.build_drone(team)
	# Step 2: a destroyed defense post is rebuilt (once its timer has run out),
	# then a lost lane turret is bought again.
	builder.rebuild_posts(ts)
	builder.rebuy_lost_sites(ts)
	# Step 3: the tech plan. If we can't afford the next step yet, keep
	# half its price back ("reserve") so spare spending doesn't starve it.
	var step := AdmiralPlan.next_step(ts, profile.i("plan_lookahead"), plan_front)
	# A weak admiral (test option) starts a plan step only every 90 s (the profile's plan_gap_s; 0 = no gap).
	var plan_gap := profile.f("plan_gap_s")
	if plan_gap > 0.0 and weak_plan_t > 0.0:
		step = {}
	var reserve := 0.0
	if not step.is_empty():
		reserve = float(step["cost"])
		if ts.can_afford(reserve):
			lg.expect(team, "MODULE" if step["kind"] == "f" else "RESEARCH", "plan.step", "%s %s" % ["builds" if step["kind"] == "f" else "researches", str(step["id"])],
				"the steps behind it in the plan", "it is the next step of the build plan and the treasury %d pays its %d" % [int(ts.treasury), int(step["cost"])])
			if step["kind"] == "f":
				cmd.build_facility(team, step["id"])
			else:
				cmd.research(team, step["id"])
			reserve = 0.0
			weak_plan_t = plan_gap
	# Step 4: spend spare money (the treasury minus half the plan's reserve).
	# Another drone if we're under the target...
	var spare := ts.treasury - reserve * profile.f("plan_reserve")
	# Step 1 may just have queued a drone: count again, so one think never
	# queues two (and not into a full queue, as in step 1).
	drones = world.mining_drone_count(team) + ts.drones_queued()
	if drones < want_drones and spare > profile.f("drone_spare") and ts.drones_queued() < RtsHulls.DEPTH_DRONES:
		lg.expect(team, "DRONE", "drones.target", "orders a mining drone", "keeping the money", "%d drones against %d wanted and %d credits to spare" % [drones, want_drones, int(spare)])
		cmd.build_drone(team)
		spare -= profile.f("drone_cost")
	# ...a repair bay (once researched, a try at most every 40 s) with over
	# 500 spare, and a ward (a try at most every 45 s) while the treasury
	# holds over 300. (A weak admiral places neither.)
	if ts.repair_bays and bay_t <= 0.0 and spare > profile.f("bay_spare") and profile.on("bays"):
		bay_t = profile.f("bay_gap_s")
		builder.place_bay()
	if ward_t <= 0.0 and ts.treasury > profile.f("ward_treasury") and profile.on("wards"):
		ward_t = profile.f("ward_gap_s")
		builder.place_ward()
	# Step 5: the waypoint, when its timer runs out (never a deputy's).
	if waypoint_t <= 0.0:
		waypoint_t = profile.f("waypoint_gap_s")
		if deputy == null or deputy.allows("waypoint"):
			waypoint.place(ts)
	# While our base is under attack (and we aren't sieging), cap the timer
	# at 1 s, so the waypoint is re-placed every second instead of every
	# 75 s.
	if ts.defending(world.time) and ts.siege_lane == "":
		waypoint_t = minf(waypoint_t, profile.f("waypoint_defend_s"))
	# Step 6: sieges (a weak admiral declares none).
	if profile.on("siege") and (deputy == null or deputy.allows("siege")):
		_siege(ts)
	# Step 7: moving our mothership, once its engines are online (20:00,
	# Rules.move_unlock_time(), which a feature module may tune). A weak
	# admiral never moves it.
	if world.time > Rules.move_unlock_time() and profile.on("mover") and (deputy == null or deputy.allows("mover")):
		mothership_mover.maybe_move()
	# Step 8: buy fleet ships (a weak admiral buys none).
	if profile.on("buys"):
		production.run(ts, spare)
	# Step 8b (RT8): the fleet layer plays the bought squadrons (off, and not even made, until the lead's switch-on commit).
	if fleet != null and (deputy == null or deputy.allows("fleet")):
		fleet.think(ts)
	# Step 9: take the field, or dock again (AdmiralField). All of the above
	# ran as usual whether the admiral's own ship is out or not. (Never a deputy's: the ship is the human's.)
	if deputy == null or deputy.allows("field"):
		field.update(ts)


## Turn the fleet layer on or off while the match runs (the deputy does this when the human goes away and comes back).
## On: the profile's fleet_play switch is set through the range-checked setter and the layer is made as _init makes
## it. Off: the switch is cleared and the layer is let go. Nothing happens when it is already so.
func set_fleet(on: bool) -> void:
	if on == (fleet != null):
		return
	if on:
		profile.set_value("fleet_play", 1)
		fleet = AdmiralFleet.new(world, team, lanes, react, profile)
		waypoint.fleet = fleet
	else:
		profile.set_value("fleet_play", 0)
		fleet = null
		waypoint.fleet = null


## The siege step (other files' notes, such as TeamState's, point here).
## The real code is AdmiralSiege.update(). When the siege starts, changes
## or ends, the waypoint timer is set to 0 so the waypoint moves at the
## next think.
func _siege(ts: TeamState) -> void:
	if siege.update(ts):
		waypoint_t = 0.0
