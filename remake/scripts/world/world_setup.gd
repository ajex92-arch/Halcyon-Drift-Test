class_name WorldSetup
extends RefCounted
## WHAT THIS IS: the recipe that builds a match. It runs once, when a match
## starts, and fills in the World: map, systems, teams, motherships, ore
## nodes, pilots, admirals, starting drones and jungle camps.
##
## HOW IT WORKS: build() goes down a fixed list of steps:
##   1. Remember the human's role, the team the human plays for (Aurelian
##      unless Game.human_team says Vhorr) and whose fog the screen shows, take
##      the launch options --slow and --fast (WorldSpeed), and start with no tuned numbers
##      and no usage counts (Game.tunables, Game.usage), so nothing is left
##      over from an earlier match.
##   2. Build the map (MapBuilder) and the asteroid rocks, and close the
##      tight gaps between rocks that a ship could wedge itself in
##      (AsteroidField.seal_tight_gaps()).
##   3. Make the game systems: the two spatial hashes, vision,
##      projectiles, effects, combat, match rules and the admiral desk.
##   4. Make the two teams (giving each its income multiplier from the
##      difficulty setting, Difficulty), the two motherships, the ore nodes and
##      turret sites, the 18 lane turrets that stand on the lane sites from the
##      start, and the 6 lane defense posts.
##   5. Make 5 pilots per team (one on the human's team may be the human) and
##      their AI brains; each pilot gets their team's income multiplier. The
##      human admiral also gets an own profile (the admiral's seat).
##   6. Apply the test switches and make the AI admirals, each with its own
##      admiral-seat profile (with the team's income multiplier) and pilot
##      brain (for its field trips).
##   7. Launch the starting mining drones, make the directors and spawn
##      the jungle camps.
##   8. Set up the map decoration, the fog drawing and the camera, then
##      work out the first fog of war for both teams.
##   9. Install the feature modules whose rule variant is switched on
##      (FeatureRegistry). With every variant at its default there are
##      none, and the match is exactly today's game.
## The order must stay exactly as it is. Some steps use random numbers
## (each starting mining drone appears at a random spot), and the whole
## game draws from one shared random sequence, so moving a step would
## change everything that happens after it.
##
## WHO USES IT: World.setup() calls build(); main.gd calls World.setup().
## build() calls FeatureRegistry.install() last.
## (A "static" function, like build(), belongs to the class itself: it is
## called as WorldSetup.build(...) without making a WorldSetup object.)

## The mothership scene (one is made per team).
const MOTHERSHIP_SCENE := preload("res://scenes/entities/mothership.tscn")
## The ore node scene (one per node in the map).
const NODE_SCENE := preload("res://scenes/entities/resource_node.tscn")


## Build the match into world `w`. `role` is what the human plays:
## "pilot" | "admiral" | "spectator".
static func build(w: World, role: String) -> void:
	# Step 1: who is playing, and whose fog the screen shows (a spectator
	# sees everything, -1). Everything else reaches the match via Game.world.
	w.human_role = role
	# The side the human plays for is Game.human_team (Aurelian unless they chose
	# Vhorr); a spectator has no side and keeps Aurelian, for the camera's start.
	w.human_team = Rules.HALCYON if role == "spectator" else Game.human_team
	w.viewer_team = -1 if role == "spectator" else w.human_team
	Game.world = w
	# The world speed: normal, unless the launch option --slow=<0.05 to 1> asks
	# for a slowed match from the start (a test option; WorldSpeed).
	if Game.opt("slow") != null:
		w.speed.set_from_option(str(Game.opt("slow")))
	# ...or --fast=<1 to 2> for a faster one (a determinism run tries 2 and 1.5).
	if Game.opt("fast") != null:
		w.speed.set_from_fast_option(str(Game.opt("fast")))
	# A fresh match: no tuned numbers and no usage counts from an earlier
	# match (the feature modules of step 9 fill them again).
	Game.tunables.clear()
	Game.usage.clear()
	# Step 2: the map and the asteroid rocks.
	w.map = MapBuilder.build()
	w.map.warm_up()
	w.asteroids = w.get_node("Asteroids")
	w.asteroids.build(w.map)
	# Close the gaps between rocks that a ship could wedge itself in.
	w.asteroids.seal_tight_gaps()
	# The map's route finder asks this whether a straight hop from a to b
	# misses every rock (with 16 world units to spare).
	w.map.route.clear_fn = func(a: Vector2, b: Vector2) -> bool: return w.asteroids.segment_hit(a, b, 16.0).is_empty()

	# Step 3: the systems. Each spatial hash covers the whole map
	# (MapLayout.W by MapLayout.H world units).
	w.unit_hash = SpatialHash.new(MapLayout.W, MapLayout.H)
	w.big_hash = SpatialHash.new(MapLayout.W, MapLayout.H)
	w.vision = Vision.new()
	w.vision.setup(w)
	# Rocks block sight, so Vision must hear when one is shot apart.
	w.asteroids.rock_destroyed.connect(func(_i: int) -> void: w.vision.on_rock_destroyed())
	# Projectiles and effects are child nodes; they also need to know
	# whose fog the screen shows (none while the No fog option is on: FogOff).
	w.projectiles = w.get_node("Projectiles")
	w.projectiles.setup(w)
	w.projectiles.viewer_team = -1 if FogOff.is_on() else w.viewer_team
	w.effects = w.get_node("Effects")
	w.effects.setup(w)
	w.effects.viewer_team = -1 if FogOff.is_on() else w.viewer_team
	w.combat = Combat.new(w)
	w.rules = MatchRules.new(w)
	w.command = AdmiralCommand.new(w)
	w.orders = OrderQueue.new(w)
	# The match log and the replays (--order-log, --replay, --admiral-replay); the
	# log's header waits for the first tick.
	w.orders.configure()
	w.events_rts = RtsEvents.new(w)
	# The yard: its six orders (buy ships, cancel, move, hold, repeat, rally) and the
	# think hook that keeps a bought ship's brain from retreating.
	ProductionOrders.install(w)
	Standin.install(w)
	# The squad orders (a pilot's wing) get their checker and handler.
	Squads.register(w)
	w.alerts = [AlertList.new(0), AlertList.new(1)]
	w.units_root = w.get_node("Units")
	w.camera = w.get_node("CameraRig")

	# Step 4: the two teams. The human's team gives its admiral seat to the
	# human if they chose to be admiral, otherwise to the computer; the other
	# team's admiral is always the computer.
	for t in 2:
		w.teams.append(TeamState.new(t, w))
	w.teams[w.human_team].admiral = "human" if role == "admiral" else "ai"
	# The difficulty (Difficulty): with a human seat, the team without the human
	# earns the chosen level's multiple of its normal income. With no human seat
	# (a spectator), and for the human's own team, the multiplier is exactly 1.0.
	var seat_team := w.human_team if role == "pilot" or role == "admiral" else -1
	for t in 2:
		w.teams[t].income_mult = Difficulty.team_income_mult(seat_team, t)
	if seat_team >= 0:
		print("difficulty: %s, the enemy team earns x%.2f" % [Game.difficulty, w.teams[Rules.enemy_of(seat_team)].income_mult])
		if seat_team != Rules.HALCYON:
			print("team: the human plays for %s" % Rules.TEAM_DISPLAY[seat_team])
	else:
		print("difficulty: none (no human seat), both teams earn x1.00")
	# The motherships, made the usual way (see WorldRegistry), but also
	# kept in their own list: index = team.
	for t in 2:
		var ms: Mothership = MOTHERSHIP_SCENE.instantiate()
		w.registry.attach(ms)
		ms.setup(w, t, w.map.mothership_pos[t], w.map.mothership_facing[t])
		w.motherships.append(ms)
		w.registry.index(ms)
	# The ore nodes (they are not units; they live under the "Nodes" child).
	for nd: Dictionary in w.map.nodes:
		var n: ResourceNode = NODE_SCENE.instantiate()
		n.setup(w, nd)
		w.get_node("Nodes").add_child(n)
		w.nodes.append(n)
	# The lane turrets stand from the first second: a finished PD turret (full
	# hull) on each team's outer, inner and inhibitor site of every lane, 18 in
	# all. The admiral buys one again only after it was destroyed.
	for n: ResourceNode in w.nodes:
		if MapLayout.is_lane_site_kind(n.node_kind):
			w.spawn_turret(n.side, n, 0, "pd", true)
	# The six lane defense posts stand from the first second too, one for each team
	# and lane beside its inhibitor turret; the lanes' waves launch from them.
	w.defense_posts = DefensePosts.new(w)
	w.defense_posts.make_all()

	# Step 5: the pilots, 5 per side (Rules.PILOTS_PER_TEAM). A human pilot
	# takes slot 0 of the human's team. Each slot gets a lane role from
	# PilotAI.ROLE_PLAN; every AI pilot gets its own PilotAI brain.
	for t in 2:
		for s in Rules.PILOTS_PER_TEAM:
			var is_human := role == "pilot" and t == w.human_team and s == 0
			var p := PilotProfile.new(Roster.callsign(t, s), t, s, is_human)
			p.income_mult = w.teams[t].income_mult
			p.role = PilotAI.ROLE_PLAN[s % PilotAI.ROLE_PLAN.size()]
			w.profiles.append(p)
			if is_human:
				w.human = p
			else:
				w.pilot_ai[p] = PilotAI.new(w, p)
	# A human admiral gets an extra profile (the admiral's seat, slot 5), so
	# they can launch a ship of their own.
	if role == "admiral":
		var ap := PilotProfile.new("Admiral", w.human_team, Rules.ADMIRAL_SEAT, true)
		ap.income_mult = w.teams[w.human_team].income_mult
		ap.role = "admiral"
		w.profiles.append(ap)
		w.admiral_profile[w.human_team] = ap
		w.human = ap

	# Step 6: test switches strip systems so others can be tested alone.
	# "no-pilots" removes every AI pilot.
	if Game.opt("no-pilots", false):
		for p: PilotProfile in w.pilot_ai.keys():
			w.profiles.erase(p)
		w.pilot_ai.clear()
	# The test wings (--wingmen, the start screen's two switches): after the switch above, so a pilot it
	# removed gets none. Nothing happens when no wing is asked for.
	Squads.make_test_wings(w)
	# A computer admiral for each team whose seat is "ai" (unless the
	# "no-admiral-ai" switch is on). It gets the admiral's seat too: a profile
	# (callsign from Roster, role "admiral") and a pilot brain, so it can take
	# the field (AdmiralField). The brain is made after the "no-pilots" clear
	# above, so that switch leaves it alone.
	for t in 2:
		if w.teams[t].admiral == "ai" and not Game.opt("no-admiral-ai", false):
			var ap := PilotProfile.new(Roster.callsign(t, Rules.ADMIRAL_SEAT), t, Rules.ADMIRAL_SEAT, false)
			ap.income_mult = w.teams[t].income_mult
			ap.role = "admiral"
			w.profiles.append(ap)
			w.admiral_profile[t] = ap
			w.pilot_ai[ap] = PilotAI.new(w, ap)
			w.admiral_ai[t] = AdmiralAI.new(w, t)

	# Step 7: the starting mining drones (Structures.MINING_DRONE "start",
	# 4 per team), Aurelian's first. Each one uses a random number.
	for t in 2:
		for i in int(Structures.MINING_DRONE["start"]):
			w.spawn_mining_drone(t, "")
	# The directors. Jungle camps only spawn without the "no-jungle" switch.
	w.minion_director = MinionDirector.new(w)
	w.jungle_director = JungleDirector.new(w)
	if not Game.opt("no-jungle", false):
		w.jungle_director.setup()

	# Step 8: the map decoration, the fog drawing and the camera...
	w.get_node("MapDecor").setup(w)
	# The cover patches (gas clouds) are drawn by a node made here, not part of
	# the World scene.
	var cover_view := CoverView.new()
	cover_view.name = "CoverView"
	w.add_child(cover_view)
	cover_view.setup(w)
	w.get_node("FogView").setup(w)
	w.camera.setup(w)
	# ...then the first fog of war for both teams, and which units each
	# team can see, so nothing pops in on the first frames.
	for t in 2:
		w.vision.update_team(t, w._viewers(t))
	w.visibility.refresh(0)
	w.visibility.refresh(1)

	# Step 9: the feature modules whose rule variant is on (none by default,
	# and then this changes nothing). See FeatureRegistry.
	FeatureRegistry.install(w)
