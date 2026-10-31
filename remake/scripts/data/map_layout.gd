class_name MapLayout
extends RefCounted
## WHAT THIS IS: the hand-made plan of the battlefield ("theater"): how big
## it is, where the motherships start, where the three lanes run, and where
## the ore nodes, monster camps and jungle entrances are. DESIGN.md A4.
##
## HOW IT WORKS: Aurelian's half is authored here; MapBuilder mirrors it
## across x = CX for Vhorr so neither side gets a better map. ("Mirror" =
## flip left-right across the centre line, like a reflection.) Lanes are
## shared polylines from Aurelian's mothership to Vhorr's (a "polyline" is
## a path of straight pieces joining the listed points in order).
## Asteroids are generated around this skeleton by MapBuilder from SEED.
## Positions are in world units (1 world unit is about one pixel at normal
## zoom). (0, 0) is the top-left corner: x grows to the right and y grows
## downward, so the "top" lane has small y values.
##
## WHO USES IT: MapBuilder and its parts (MapBuilderNodes, MapBuilderJungle,
## MapBuilderWalls, MapBuilderFill, MapBuilderRoute) build the map from it;
## MapInfo, MapDecor, the Minimap and the CameraRig read the sizes and
## lanes; WorldSetup sizes the spatial hashes (grids for finding nearby
## units) with W and H; Vision sizes its grid; ResourceNode reads the ore
## numbers; Mulberry and AsteroidField start from SEED; the AI (AdmiralLanes,
## PilotGoals, TeamSiege), MinionDirector and WorldQueries walk the lanes.
##
## To change the map: move lanes/nodes/camps here, then check that the
## jungle chokes still stop big ships and that strike craft can still reach
## every camp. (DESIGN.md names a tests/unit_checks.gd for these checks,
## but that file is not in the project at the moment.)

## The map's width (world units).
const W := 40000.0
## The map's height (world units).
const H := 31200.0
## The x of the map's centre line (W / 2). Vhorr's half is Aurelian's half
## mirrored across it.
const CX := 20000.0
## The y of the map's horizontal middle line (H / 2). Both motherships start
## on it and the mid lane runs along it; the top and bottom lanes lie the same
## distance above and below it.
const CY := 15600.0
## The "seed" number that starts the map's random number sequence, so the
## generated asteroids come out the same in every match (MapBuilder; the
## asteroid shapes use SEED + 77).
const SEED := 4141

## Where each mothership starts, by team (0 Aurelian, 1 Vhorr): its
## position and its facing, an angle in radians (0 = pointing right, PI =
## pointing left, so they face each other).
const MOTHERSHIPS := [
	{"pos": Vector2(3600, 15600), "facing": 0.0},
	{"pos": Vector2(36400, 15600), "facing": PI},
]
## No random asteroids within this distance (world units) of a mothership's
## starting spot, so each base has open space. MapDecor draws this circle
## faintly in the team colour.
const BASE_CLEAR_RADIUS := 6000.0

## Lane polylines run Aurelian -> Vhorr. half = corridor half-width.
## lane id -> label (the name players see), half (half the corridor's
## width, in world units: the top and bottom lanes are 1800 wide, the mid
## lane 5400) and points (the polyline). All three lanes start at Aurelian's
## mothership and end at Vhorr's; the middle lane has a small bend around the
## centre. The top and bottom lanes lie 11400 above and below the middle line,
## which leaves a rock field 3300 deep outside each of them, along the map's
## edge.
const LANES := {
	"top": {"label": "Top lane", "half": 900.0, "points": [Vector2(3600, 15600), Vector2(8200, 4200), Vector2(31800, 4200), Vector2(36400, 15600)]},
	"mid": {"label": "Mid lane", "half": 2700.0, "points": [Vector2(3600, 15600), Vector2(16500, 15600), Vector2(18800, 14200), Vector2(21200, 14200), Vector2(23500, 15600), Vector2(36400, 15600)]},
	"bot": {"label": "Bottom lane", "half": 900.0, "points": [Vector2(3600, 15600), Vector2(8200, 27000), Vector2(31800, 27000), Vector2(36400, 15600)]},
}
## The lane ids in their usual order, top to bottom.
const LANE_ORDER := ["top", "mid", "bot"]

## The nodes: the ore nodes of the jungle (listed in NODES) and the turret sites in the lanes (made by lane_sites()). A
## node is a round area (NODE_RADIUS) with turret slots next to it; an ore node
## also holds ore rocks that mining drones harvest. The kinds:
##   "jungle_team"    an ore node in the jungle that belongs to one team: only
##                    that team may build its turret (PD only). Authored for
##                    Aurelian and mirrored for Vhorr.
##   "jungle_shared"  an ore node in the jungle on the centre line, shared:
##                    either team may build its turret (PD only). Made once.
##   "outer"          a lane turret site, the one of the team's three on a lane
##                    that lies nearest the lane's middle, with no ore: only
##                    that team may build there. One turret slot. Not in NODES:
##                    lane_sites() makes it.
##   "inner"          the team's middle lane turret site on a lane (see
##                    "outer").
##   "inhibitor"      the team's lane turret site nearest its mothership (see
##                    "outer").
## Fields:
##   id, name   the node's id and the name players see. A mirrored copy
##              gets "cin" instead of "h" in its id and "Cinder" instead of
##              "Halcyon" in its name (Halcyon's own copy gets "hal").
##   pos        its centre [world units]
##   kind       one of the kinds above
##   lane       the lane it sits on, or the lane its jungle lies by
##   value      ore multiplier: each rock holds ORE_PER_ROCK x value and
##              regrows ORE_REGEN x value per second
##   slots      how many turrets can stand there
##   ore        how many ore rocks it has (a node without this field has
##              ORE_ROCKS); 0 for a turret site
##   gate       (jungle nodes) the index in ENTRANCES of the gate whose inside
##              point the node's road starts from; the road and the node's ore
##              rocks leave a straight lane between them free of rocks
##   slot_dir   (optional) the direction from the node's centre to its first
##              turret slot; without it the slots face the nearest lane
## There are 8 ore nodes, all in the jungle: 2 per team ("jungle_team", one in
## the top jungle and one in the bottom jungle) and 4 shared ("jungle_shared",
## two in each jungle, on the centre line); the 18 turret sites in the lanes (an
## "outer", an "inner" and an "inhibitor" for each team on each lane) are made by
## lane_sites(). There is no turret site in the middle of a lane.
const NODES := [
	{"id": "h_jtop", "name": "Halcyon Top Jungle", "pos": Vector2(11000, 9300), "kind": "jungle_team", "lane": "top", "value": 1.0, "slots": 1, "gate": 4, "slot_dir": Vector2(0, -1)},
	{"id": "h_jbot", "name": "Halcyon Bottom Jungle", "pos": Vector2(11000, 21900), "kind": "jungle_team", "lane": "bot", "value": 1.0, "slots": 1, "gate": 9, "slot_dir": Vector2(0, 1)},
	{"id": "j_top_n", "name": "Top Jungle North", "pos": Vector2(20000, 6600), "kind": "jungle_shared", "lane": "top", "value": 1.25, "slots": 1, "ore": 6, "gate": 3, "slot_dir": Vector2(0, -1)},
	{"id": "j_top_s", "name": "Top Jungle South", "pos": Vector2(20000, 10000), "kind": "jungle_shared", "lane": "mid", "value": 1.25, "slots": 1, "ore": 6, "gate": 3, "slot_dir": Vector2(0, 1)},
	{"id": "j_bot_n", "name": "Bottom Jungle North", "pos": Vector2(20000, 19700), "kind": "jungle_shared", "lane": "mid", "value": 1.25, "slots": 1, "ore": 6, "gate": 8, "slot_dir": Vector2(0, -1)},
	{"id": "j_bot_s", "name": "Bottom Jungle South", "pos": Vector2(20000, 23300), "kind": "jungle_shared", "lane": "bot", "value": 1.25, "slots": 1, "ore": 6, "gate": 8, "slot_dir": Vector2(0, 1)},
]
## The size of a node's area (world units): its ore rocks lie inside this
## circle, normal asteroids are kept out of it, and the turret slots sit
## just outside it (140 further out).
const NODE_RADIUS := 560.0
## Ore rocks per node that has no "ore" field of its own in NODES.
const ORE_ROCKS := 5
## Ore in one full rock, before the node's value multiplier (1 ore is
## worth 1 credit when a drone brings it home).
const ORE_PER_ROCK := 1600.0
## Ore each rock regrows per second (times the node's value), up to full.
const ORE_REGEN := 6.0

## Monster camps on Aurelian's side (top-left and bottom-left quadrants).
## id, type (a camp type from Jungle.CAMPS: "gunship" or "carrier"), pos
## [world units] and quad ("tl" = top-left quarter, "bl" = bottom-left).
## Mirrored copies become "tr" and "br" (ids like "tr_a").
const CAMPS := [
	{"id": "tl_a", "type": "gunship", "pos": Vector2(9800, 7400), "quad": "tl"},
	{"id": "tl_b", "type": "carrier", "pos": Vector2(13600, 9800), "quad": "tl"},
	{"id": "tl_c", "type": "gunship", "pos": Vector2(16800, 7800), "quad": "tl"},
	{"id": "bl_a", "type": "gunship", "pos": Vector2(9800, 23800), "quad": "bl"},
	{"id": "bl_b", "type": "carrier", "pos": Vector2(13600, 21400), "quad": "bl"},
	{"id": "bl_c", "type": "gunship", "pos": Vector2(16800, 23400), "quad": "bl"},
]
## The camps on the centre line (x = CX), one in the top jungle and one in the
## bottom jungle, which the two halves share: each is made once, not mirrored
## (a mirror copy would stand on top of it). Same fields as CAMPS; quad "tc" =
## top centre, "bc" = bottom centre. MapBuilderJungle links each into its
## half's winding paths, and the mirror copies of those paths join the two
## halves of the jungle across the centre line there.
const CAMPS_CENTRE := [
	{"id": "tc_a", "type": "carrier", "pos": Vector2(20000, 8300), "quad": "tc"},
	{"id": "bc_a", "type": "carrier", "pos": Vector2(20000, 21500), "quad": "bc"},
]
## The extra camps of the "camp4" variant (fork teamfights_jungle, idea D7):
## one more camp per quadrant on Halcyon's side, between the lane-side
## clearing (tl_a / bl_a) and the centre (tl_c / bl_c), in the open part of
## the jungle. MapBuilderJungle adds them to CAMPS ONLY while
## Game.variant("camp4") is on (the map is then built differently); with it
## off this list is never read. Same fields as CAMPS; the type is the
## existing medium camp, the carrier.
const CAMPS_EXTRA := [
	{"id": "tl_d", "type": "carrier", "pos": Vector2(12000, 11200), "quad": "tl"},
	{"id": "bl_d", "type": "carrier", "pos": Vector2(12000, 20000), "quad": "bl"},
]
## Asteroids are kept at least this far (world units) from each camp's
## spot (MapBuilderJungle).
const CAMP_CLEAR_RADIUS := 650.0

## Jungle entrances on Aurelian's side: `lane` is a point on the corridor
## centreline, `inside` is just inside the jungle. The path between them
## passes a choke 70 u wide (strike craft only).
## ("u" = world units; a "choke" is a narrow gap between rocks.) `quad`
## says which jungle quarter the entrance leads into.
const ENTRANCES := [
	{"quad": "tl", "lane": Vector2(11500, 4200), "inside": Vector2(11500, 5600)},
	{"quad": "tl", "lane": Vector2(16000, 4200), "inside": Vector2(16000, 5600)},
	{"quad": "tl", "lane": Vector2(11000, 15600), "inside": Vector2(11000, 12400)},
	{"quad": "tl", "lane": Vector2(15200, 15600), "inside": Vector2(15200, 12400)},
	{"quad": "tl", "lane": Vector2(6360, 8760), "inside": Vector2(7660, 9280)},
	{"quad": "bl", "lane": Vector2(11500, 27000), "inside": Vector2(11500, 25600)},
	{"quad": "bl", "lane": Vector2(16000, 27000), "inside": Vector2(16000, 25600)},
	{"quad": "bl", "lane": Vector2(11000, 15600), "inside": Vector2(11000, 18800)},
	{"quad": "bl", "lane": Vector2(15200, 15600), "inside": Vector2(15200, 18800)},
	{"quad": "bl", "lane": Vector2(6360, 22440), "inside": Vector2(7660, 21920)},
]
## Jungle path half-width and choke opening (gap between rock edges).
## Half the width of the jungle paths kept clear of filler asteroids
## (world units).
const PATH_HALF := 150.0
## The choke opening: the gap between the edges of the two rocks at each
## entrance (world units). Small ships (radius up to 17) pass; corvettes
## and bigger (radius 44 and more) do not. The rocks' hit circles are 5%
## smaller than they are drawn, which makes the gap a ship really meets
## 15 wider: 85, under the 88 a corvette needs.
const CHOKE_GAP := 70.0

## Where each team's three lane turrets stand on a side or mid lane, as
## fractions (0 to 1) of the lane's length measured from that team's own
## mothership: the inhibitor turret nearest the mothership, the inner turret,
## and the outer turret, which is the one nearest the lane's middle. A team's
## turrets are at these fractions; the other team's are at 1 minus them. The
## openings of the edge fields (EDGE_OPENING_FRACTIONS) lie between them.
const LANE_TURRET_FRACTIONS := {"inhibitor": 0.30, "inner": 0.38, "outer": 0.46}
## The kinds of lane turret site, from the lane's middle toward the team's own
## mothership. Each team has one of each on each of the three lanes: 9 sites a
## team, 18 in all, and a turret stands on each from the first second.
const LANE_SITE_KINDS := ["outer", "inner", "inhibitor"]
## The lane site kinds nearer the team's own mothership than the "outer" one:
## the home end of a lane (torpedo turrets may stand there, TurretData).
const HOME_SITE_KINDS := ["inner", "inhibitor"]
## The name of each lane site kind as players read it.
const LANE_SITE_LABELS := {"outer": "Outer", "inner": "Inner", "inhibitor": "Inhibitor"}
## Which side of its lane's centre line a lane turret stands on: +1 is the side
## to the south of a lane that runs east (the lane's points run from
## Aurelian's mothership to Vhorr's), -1 the side to the north. The turrets of
## the top and bottom lanes stand on the side toward the middle of the map, the
## mid lane's to the south.
const LANE_SITE_SIDE := {"top": 1.0, "mid": 1.0, "bot": -1.0}
## How far (world units) off its lane's centre line a lane turret stands: never
## on the line, where a ship passes. 400 in the narrow top and bottom lanes
## (their walls are 900 off the line), 500 in the wide mid lane.
const LANE_SITE_OFFSET := {"top": 400.0, "mid": 500.0, "bot": 400.0}
## Where the openings in the outer walls of the top and bottom lanes are, as
## fractions of the lane's length measured from Aurelian's mothership. Each lies
## between two lane turrets (0.34 between Aurelian's inhibitor and inner turret,
## 0.42 between its inner and outer turret, 0.50 between the two outer
## turrets); the openings of Vhorr's half are the mirror images, at 1 minus
## these fractions, and the one at 0.50 is on the centre line and made once.
## Each opening is a gate like a jungle gate (CHOKE_GAP wide: small craft only)
## into one edge field cluster of its own: a few open pockets joined by
## short channels, with no way from one cluster to another except the lane, so
## no route leads round a lane turret.
const EDGE_OPENING_FRACTIONS := [0.34, 0.42, 0.50]
## How far (world units) inside an edge opening the road into its cluster
## starts, measured from the lane's edge (the same distance as a jungle gate).
const EDGE_GATE_DEPTH := 500.0
## The pockets of one edge field cluster, in the order they are joined: each is
## `depth` (world units from the lane's edge, away from the lane), `side`
## (world units sideways from the opening toward the centre line; the cluster
## of the opening on the centre line has none) and `radius` (the open room:
## no rock lies within it). A channel as wide as a
## jungle path (2 x PATH_HALF plus the filler rocks' gap) joins each pocket to
## the one before, the first to the opening.
const EDGE_POCKETS := [
	{"depth": 1300.0, "side": 0.0, "radius": 480.0},
	{"depth": 2300.0, "side": 800.0, "radius": 420.0},
]


## The mirror image of point `p` across the centre line: (W - x, y). This
## is how Aurelian's half becomes Vhorr's. MapBuilder and its parts use it.
static func mirror(p: Vector2) -> Vector2:
	return Vector2(W - p.x, p.y)


## How many ore rocks the plan's node `nd` (an entry of NODES) has.
static func ore_rocks_of(nd: Dictionary) -> int:
	return int(nd.get("ore", ORE_ROCKS))


## Aurelian's nine lane turret sites in the form of an entry of NODES, in the
## order top lane, mid lane, bottom lane and on each lane outer, inner,
## inhibitor (MapBuilderNodes mirrors them for Vhorr). Site `kind` of a lane
## stands at LANE_TURRET_FRACTIONS[kind] of the lane's length from Aurelian's
## mothership, LANE_SITE_OFFSET off the centre line on the LANE_SITE_SIDE side.
## The node's centre lies a turret slot's reach (NODE_RADIUS + 140) behind that
## spot, so the node's one slot ("slot_dir" faces away from the centre) is the
## spot itself. The ids are "h_<lane>_<kind>" ("h_top_outer"), the names
## "Halcyon <Lane> <Kind>" ("Halcyon Top Outer"). No random numbers.
static func lane_sites() -> Array:
	var out: Array = []
	for lane: String in LANE_ORDER:
		var pts := PackedVector2Array(LANES[lane]["points"])
		var total := Util.polyline_length(pts)
		var short := str(LANES[lane]["label"]).trim_suffix(" lane")
		for kind: String in LANE_SITE_KINDS:
			# Step 1: the spot on the lane line, and the way across the lane.
			var s := total * float(LANE_TURRET_FRACTIONS[kind])
			var on_line := Util.polyline_at(pts, s)
			var along := (Util.polyline_at(pts, s + 1.0) - Util.polyline_at(pts, s - 1.0)).normalized()
			var across := Vector2(-along.y, along.x) * float(LANE_SITE_SIDE[lane])
			# Step 2: where the turret stands, and the node centre behind it.
			var stands := on_line + across * float(LANE_SITE_OFFSET[lane])
			var centre := (stands - across * (NODE_RADIUS + 140.0)).round()
			out.append({"id": "h_%s_%s" % [lane, kind], "name": "Halcyon %s %s" % [short, LANE_SITE_LABELS[kind]], "pos": centre,
				"kind": kind, "lane": lane, "value": 1.0, "slots": 1, "ore": 0, "slot_dir": across})
	return out


## Where team `team`'s defense post on lane `lane` stands and its minions
## launch, as a dictionary: "pos" (the post's centre, on the same side of the
## lane's centre line as the lane's inhibitor turret, PostData.BACK along the
## lane toward the team's own mothership from that turret), "launch" (the
## centre of the five launch spots, on the lane's centre line PostData.
## LAUNCH_AHEAD toward the enemy from the post), "side" (a length-1 arrow across
## the lane, along which the launch spots are spread) and "along" (a length-1
## arrow along the lane toward the enemy). Vhorr's are the mirror images of
## Aurelian's. No random numbers.
static func lane_post(lane: String, team: int) -> Dictionary:
	var pts := PackedVector2Array(LANES[lane]["points"])
	var s := Util.polyline_length(pts) * float(LANE_TURRET_FRACTIONS["inhibitor"]) - PostData.BACK
	var on_line := Util.polyline_at(pts, s)
	var along := (Util.polyline_at(pts, s + 1.0) - Util.polyline_at(pts, s - 1.0)).normalized()
	var side := Vector2(-along.y, along.x)
	var stands := on_line + side * float(LANE_SITE_SIDE[lane]) * float(LANE_SITE_OFFSET[lane])
	var launch := Util.polyline_at(pts, s + PostData.LAUNCH_AHEAD)
	if team == Rules.CINDER:
		stands = mirror(stands)
		launch = mirror(launch)
		along = Vector2(-along.x, along.y)
		side = Vector2(-side.x, side.y)
	return {"pos": stands, "launch": launch, "side": side, "along": along}


## Every node of the plan in the order the map maker builds them: the lane turret
## sites first (lane_sites()), then NODES.
static func plan_nodes() -> Array:
	var out := lane_sites()
	out.append_array(NODES)
	return out


## Does a node of kind `kind` belong to one team (only that team may build
## there, and the map maker writes it once for each team)? True for the lane
## turret sites and the team's own jungle nodes; false for the shared nodes.
static func is_team_kind(kind: String) -> bool:
	return kind in LANE_SITE_KINDS or kind == "jungle_team"


## Is `kind` one of the lane turret sites ("outer", "inner" or "inhibitor")?
static func is_lane_site_kind(kind: String) -> bool:
	return kind in LANE_SITE_KINDS


## The entry of the plan (plan_nodes()) that the built node with id `node_id`
## comes from: the entry with that id, or, for a team's copy of a mirrored node
## ("hal_top_outer" and "cin_top_outer" come from "h_top_outer"), the entry it
## was made from. An empty dictionary if there is none.
static func plan_node(node_id: String) -> Dictionary:
	for nd: Dictionary in plan_nodes():
		var plan_id := str(nd["id"])
		if plan_id == node_id:
			return nd
		if plan_id.begins_with("h") and (node_id.begins_with("hal") or node_id.begins_with("cin")) and node_id.substr(3) == plan_id.substr(1):
			return nd
	return {}


## The starting position of `team`'s mothership. (No script calls this at
## the moment.)
static func mothership_pos(team: int) -> Vector2:
	return MOTHERSHIPS[team]["pos"]


## Lane polyline as walked by `team` (Aurelian walks it as authored).
## Vhorr walks it backwards, so for both teams the list starts at their
## own mothership and ends at the enemy's.
static func lane_points(lane: String, team: int) -> PackedVector2Array:
	var pts := PackedVector2Array(LANES[lane]["points"])
	if team == Rules.CINDER:
		pts.reverse()
	return pts
