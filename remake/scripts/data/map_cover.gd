class_name MapCover
extends RefCounted
## WHAT THIS IS: the plan of the map's cover: where the gas clouds and the
## hidden pockets are. A cover patch is a place on the map where ships can hide:
## a ship standing in it is not seen by the other team from outside (the fog of
## war's cover rule, see VisionCover), while shots and ships pass through it
## freely. A gas cloud is open space; a hidden pocket is a small room ringed by
## rocks, and a ship that fires from either is seen by everyone for 2 seconds.
## DESIGN.md A4.
##
## HOW IT WORKS: Halcyon's half is authored here and the other half is its
## mirror image across x = MapLayout.CX, like the rest of the map, so neither
## team gets better cover. Each patch is an ellipse: its middle `pos` and its
## whole `size` (width, height), in world units. Vision turns an ellipse into
## whole fog cells (the cells whose centres lie inside it) when it is set up.
## Clouds lie in the jungle, in open ground beside the rock fields; pockets sit
## in the jungle's rock nooks that a small ship can reach. All keep well clear of
## every lane line, ore node, turret slot, camp and mothership
## (tests/cover_check.gd checks this on the finished map).
##
## To move or add a patch: change CLOUDS or POCKETS, then run tests/cover_pick.gd
## (with --pockets for nooks) to see good spots and tests/cover_check.gd to check
## the rules.
##
## WHO USES IT: Vision.setup() reads patches() and marks the cells; CoverView
## and the Minimap draw the patches from Vision; tests/cover_check.gd reads
## patches().

## The kind name of a gas cloud.
const CLOUD := "cloud"
## The kind name of a hidden pocket.
const POCKET := "pocket"

## Halcyon's clouds: id, middle (world units) and size (width and height, world
## units, each between 800 and 1600). Two lie in the top jungle (one near the
## top lane, one beside the mid lane's rock wall) and one in the bottom jungle.
const CLOUDS := [
	{"id": "jungle_north", "pos": Vector2(15300, 6800), "size": Vector2(1400, 1000)},
	{"id": "jungle_inner", "pos": Vector2(11400, 11200), "size": Vector2(1200, 1000)},
	{"id": "jungle_south", "pos": Vector2(15300, 24400), "size": Vector2(1400, 1000)},
]


## Halcyon's hidden pockets: id, middle and size like CLOUDS (each 800 across).
## Two lie in the top jungle (the west room just inside a lane gate, and one in
## the middle of the jungle) and two in the bottom jungle; one lies in the top
## edge field and one in the bottom edge field (dogfight rooms behind the small
## gaps in the side lanes' outer walls).
const POCKETS := [
	{"id": "pocket_north_west", "pos": Vector2(8200, 9200), "size": Vector2(800, 800)},
	{"id": "pocket_north_mid", "pos": Vector2(17800, 9400), "size": Vector2(800, 800)},
	{"id": "pocket_south_west", "pos": Vector2(8000, 22000), "size": Vector2(800, 800)},
	{"id": "pocket_south_mid", "pos": Vector2(17200, 20600), "size": Vector2(800, 800)},
	{"id": "pocket_edge_north", "pos": Vector2(13200, 1100), "size": Vector2(800, 1000)},
	{"id": "pocket_edge_south", "pos": Vector2(17000, 30100), "size": Vector2(800, 1000)},
]


## Every patch on the map, as dictionaries {"id", "kind", "pos", "size"}:
## Halcyon's clouds, their mirror images for Vhorr (the id ends in "_m"), then
## Halcyon's pockets and theirs. Vision.setup() adds them in this order, so a
## patch's number is its place in this list, counting from 1.
static func patches() -> Array:
	var out: Array = []
	for c: Dictionary in CLOUDS:
		out.append({"id": c["id"], "kind": CLOUD, "pos": c["pos"], "size": c["size"]})
	for c: Dictionary in CLOUDS:
		out.append({"id": str(c["id"]) + "_m", "kind": CLOUD, "pos": MapLayout.mirror(c["pos"]), "size": c["size"]})
	for c: Dictionary in POCKETS:
		out.append({"id": c["id"], "kind": POCKET, "pos": c["pos"], "size": c["size"]})
	for c: Dictionary in POCKETS:
		out.append({"id": str(c["id"]) + "_m", "kind": POCKET, "pos": MapLayout.mirror(c["pos"]), "size": c["size"]})
	return out
