class_name AdmiralBuilder
extends RefCounted
## WHAT THIS IS: the part of the AI admiral that decides WHERE to build
## things: defence turrets at resource nodes, repair bays behind the lanes,
## and wards at jungle entrances.
##
## HOW IT WORKS: each function walks a list of spots in a fixed order and
## builds at the first good one (or, for rebuy_lost_sites(), at every
## good one). The one exception: the first lane turret bought back goes to the
## outer site where most of our own pilots and minions are. A few words:
##   - A "resource node" is a place with turret slots, with ore rocks in the
##     jungle. A team's three lane turret sites on a lane ("outer", "inner"
##     and "inhibitor") only take that side's turrets, and a turret stands on
##     each from the first second.
##   - A "PD turret" (point defence) fires fast and shreds small craft. A
##     "torp turret" fires homing torpedoes at big ships; it needs the
##     Platform Missiles research and only fits at the inner and inhibitor
##     sites.
##   - A "repair bay" flies out, anchors, and its drones heal our ships.
##   - A "ward" is a small drone that anchors and keeps watch, so our team
##     can see that spot.
## Every build goes through AdmiralCommand (world.command), the same checked
## orders a human admiral uses, so the AI can't cheat.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.builder) and its tick() calls
## these once a second, only when the money and timers allow it.

## How far (world units) from an outer lane turret site a pilot ship or minion
## of ours still counts as "there" when the admiral picks the site for its
## first turret bought back (rebuy_order()). The same 1,500-unit disc in which
## an enemy ship stops us from building at a lane site
## (TurretData.BUILD_CLEAR_RADIUS).
const PRESENCE_R := TurretData.BUILD_CLEAR_RADIUS

## How many lane turrets this admiral has bought back so far this match (the
## first one is picked by rebuy_order() where our own ships are).
var rebought := 0
## The game world (nodes, bays, wards, the map and the AdmiralCommand).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (for points along a lane).
var lanes: AdmiralLanes
## A reusable list the spatial hash fills with nearby units (reusing one list
## avoids making a new one for every question; see _ours_near()).
var _scratch: Array = []


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## The ore nodes in the order the turret builders visit them: the map's own
## order (World.nodes), except under the "node_persist" variant
## (NodePersistFeature), where the node nearest our own mothership comes
## first, so a lost turret near home is rebuilt before a far one.
func _nodes_in_order() -> Array:
	if not world.features.is_empty() and world.features.has("node_persist"):
		return world.features["node_persist"].call("nodes_by_distance", team)
	return world.nodes


## Put a PD turret back at each of our lane turret sites (outer, inner and
## inhibitor) that has no turret of ours, while we have 450 credits (the PD
## turret's price). The 18 lane turrets stand from the first second, so this
## only has work after one was destroyed. It runs early in the admiral's
## think, before the tech plan, so a lost defence is replaced first. It may
## build at several sites in one go, in the order rebuy_order() gives. A site
## whose turret was just destroyed is locked (TurretData.REBUILD_LOCK, 150 s
## with node_persist, tuned "rebuild_lock"), and no turret may go up while
## enemy ships are close (ResourceNode.build_blocker): such a site is skipped
## until the command allows a build there again, instead of failing the same
## order every second.
func rebuy_lost_sites(ts: TeamState) -> void:
	var cmd := world.command
	for n: ResourceNode in rebuy_order():
		if MapLayout.is_lane_site_kind(n.node_kind) and n.side == team and n.turret_count(team) == 0:
			if cmd.turret_blocker(team, n.node_id, "pd") != "":
				continue
			if ts.can_afford(450.0) and cmd.build_turret(team, n.node_id, "pd") == "":
				rebought += 1


## Rebuild each of our defense posts that is ready to be rebuilt (destroyed,
## its timer run out, no enemy ships close), while we have its price. The lane
## is silent until we do, so this comes before the lane turrets in the admiral's
## think. AdmiralCommand.post_blocker says whether a post may be rebuilt. A team
## that owns Fleet Command rebuilds none: its free waves have stopped, so a post
## would launch nothing.
func rebuild_posts(ts: TeamState) -> void:
	var cmd := world.command
	# A post only launches free waves, and a team with Fleet Command has none.
	if world.minion_director.controlled(team):
		return
	for lane: String in MapLayout.LANE_ORDER:
		if cmd.post_blocker(team, lane) != "":
			continue
		if ts.can_afford(float(PostData.POST["cost"])):
			cmd.rebuild_post(team, lane)


## The nodes in the order rebuy_lost_sites() tries them. Normally that is
## _nodes_in_order(). Only the FIRST turret bought back differs: while we have
## bought none back, the allowed one of our lost OUTER lane sites (no turret of
## ours there and AdmiralCommand.turret_blocker has no objection) with the most
## of our own pilots and minions within PRESENCE_R of it comes first, then the
## rest in the usual order. A tie keeps the earlier site in the usual order, and
## with none of our ships near any allowed outer site the usual order stands.
## Only the world as it is now decides: no random numbers.
func rebuy_order() -> Array:
	var usual := _nodes_in_order()
	if rebought > 0:
		return usual
	var first: ResourceNode = null
	var most := 0
	for n: ResourceNode in usual:
		if n.node_kind != "outer" or n.side != team or n.turret_count(team) >= 1:
			continue
		if world.command.turret_blocker(team, n.node_id, "pd") != "":
			continue
		var here := _ours_near(n.global_position)
		if here > most:
			first = n
			most = here
	if first == null:
		return usual
	var order: Array = [first]
	for n in usual:
		if n != first:
			order.append(n)
	return order


## How many of our live pilot ships and minions are within PRESENCE_R of point
## `p`. (The spatial hash may list units a little outside the circle, so the
## distance is checked.)
func _ours_near(p: Vector2) -> int:
	var count := 0
	for u: Unit in world.unit_hash.query(p, PRESENCE_R, _scratch):
		if u.alive and u.team == team and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION) and u.global_position.distance_to(p) < PRESENCE_R:
			count += 1
	return count

## Launch one repair bay, if we are under the team limit
## (Structures.REPAIR_BAY "max_per_team", 3). It goes a third of the way
## down a lane from our base, beside the lane.
func place_bay() -> void:
	# Step 1: count our living bays; stop at the limit.
	var have := 0
	for b in world.bays:
		if b.team == team and b.alive:
			have += 1
	if have >= int(Structures.REPAIR_BAY["max_per_team"]):
		return
	# Step 2: try the lanes in the order mid, top, bot, and use the first
	# lane whose spot has no bay of ours yet. The spot is 900 units off the
	# lane line (450 on a narrow side lane), up for mid and top and down for
	# bot, so minions don't fight over it.
	# The places to try: [lane, fraction of the lane]. Features that have a
	# bay_spots() function (Forward Redeploy, bayA) may change the list.
	var spots: Array = [["mid", 0.33], ["top", 0.33], ["bot", 0.33]]
	for f in world.features.values():
		if f.has_method("bay_spots"):
			spots = f.bay_spots(world, team, spots, lanes)
	for spot: Array in spots:
		var lane: String = spot[0]
		var p := lanes.lane_point(lane, float(spot[1]))
		# 900 off the line, or half the lane's half-width where the lane is narrow.
		var off := minf(900.0, float(world.map.lane_half[lane]) * 0.5)
		p += Vector2(0, -off if lane != "bot" else off)
		# A bay of ours within 1,500 units already covers this spot.
		var covered := false
		for b in world.bays:
			if b.team == team and b.alive and b.anchor.distance_to(p) < 1500.0:
				covered = true
		# Bays only go in open space (a lane, the crossing or a base).
		if covered or not world.map.in_open_lane(p):
			continue
		world.command.deploy_bay(team, p)
		return


## Place one ward at a jungle entrance on our side of the map that has no
## ward of ours yet, if the spot is allowed (wards only go where our team
## can see right now). The ward goes on the lane end of the entrance path.
func place_ward() -> void:
	# Step 1: at the limit (Structures.WARD "max_per_team", 6), placing
	# another would just retire our oldest ward, so don't.
	var mine := 0
	for w in world.wards:
		if w.team == team and w.alive:
			mine += 1
	if mine >= int(Structures.WARD["max_per_team"]):
		return
	# Step 2: go through the jungle entrances. Which side owns an entrance
	# goes by its quarter of the map ("tl"/"bl" = Aurelian's left half,
	# "tr"/"br" = Vhorr's right half). Some entrances sit exactly on the
	# centre line, and each side has its own copy of those, so judging by
	# the x position alone would hand all of them to one team.
	for e: Dictionary in world.map.entrances:
		var p: Vector2 = e["lane"]
		var q: String = e["quad"]
		var ours := (q == "tl" or q == "bl") == (team == Rules.HALCYON)
		if not ours:
			continue
		# Step 3: skip it if one of our wards is already within 1,500 units.
		var taken := false
		for w in world.wards:
			if w.team == team and w.alive and w.anchor.distance_to(p) < 1500.0:
				taken = true
				break
		if taken:
			continue
		# Step 4: place it if the rules allow (we can see it, no asteroid).
		if world.command.ward_blocker(team, p) == "":
			world.command.place_ward(team, p)
			return
