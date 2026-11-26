class_name HullTables
extends RefCounted
## WHAT THIS IS: the small tables that give each hull its own plain outline, its
## three-letter army-card tag, its icon shape and its practice trial, kept in one
## place beside the ship rows so that a new hull is added here and nowhere in the
## drawing or interface code.
##
## HOW IT WORKS: only constants. Each table has a row for every hull id of
## Ships.ORDER: OUTLINES (the corner points of the plain outline), TAGS (the
## three-letter tag of an army card), ICON_SHAPES (the name of the icon's shape in
## IconLayer.SHAPES) and TRIALS (the practice range's aim test of a hull, with
## GENERIC_TEXT as the words most of them share). A hull a table does not list
## falls back, in the code that reads the table, to the default hull's row, to its
## first three letters or to a chevron.
##
## WHO USES IT: ShipVisual (OUTLINES), ArmyCards (TAGS), IconLayer (ICON_SHAPES),
## PracticeTrials (TRIALS and GENERIC_TEXT) and the tests that check each hull has
## a row in every table.

## Each hull's plain outline: a list of corner points, nose pointing right (+x),
## for a ship 36 units long (they are scaled to the hull's real length). The
## Aurelian steel hulls (AurelianShapes) keep these sizes to within about a
## tenth (more only where a gun mount sits outside the plain outline: the
## Bomber's torpedo mount, the Destroyer's and Battlecruiser's point-defense
## mounts); this table is drawn only while the steel look is off, and is the size
## the hull gallery checks the Cinder shapes against. Hulls not listed here use
## the "fighter" shape.
const OUTLINES := {
	"scout": [Vector2(18, 0), Vector2(-10, 5), Vector2(-14, 0), Vector2(-10, -5)],
	"fighter": [Vector2(18, 0), Vector2(-8, 7), Vector2(-4, 0), Vector2(-8, -7)],
	"lance": [Vector2(20, 0), Vector2(2, 3), Vector2(-10, 8), Vector2(-6, 0), Vector2(-10, -8), Vector2(2, -3)],
	"bomber": [Vector2(16, 0), Vector2(4, 6), Vector2(-12, 8), Vector2(-8, 0), Vector2(-12, -8), Vector2(4, -6)],
	"logistics": [Vector2(14, 0), Vector2(8, 9), Vector2(-12, 9), Vector2(-14, 0), Vector2(-12, -9), Vector2(8, -9)],
	"support": [Vector2(12, 0), Vector2(-2, 5), Vector2(-10, 4), Vector2(-6, 0), Vector2(-10, -4), Vector2(-2, -5)],
	"flak": [Vector2(16, 0), Vector2(6, 10), Vector2(-14, 9), Vector2(-16, 0), Vector2(-14, -9), Vector2(6, -10)],
	"ion": [Vector2(18, 0), Vector2(14, 4), Vector2(-12, 7), Vector2(-16, 0), Vector2(-12, -7), Vector2(14, -4)],
	"destroyer": [Vector2(18, 0), Vector2(10, 4), Vector2(-2, 4.5), Vector2(-6, 6), Vector2(-17, 5), Vector2(-18, 0), Vector2(-17, -5), Vector2(-6, -6), Vector2(-2, -4.5), Vector2(10, -4)],
	"battlecruiser": [Vector2(18, 0), Vector2(12, 5), Vector2(0, 5), Vector2(-4, 7), Vector2(-16, 6), Vector2(-18, 0), Vector2(-16, -6), Vector2(-4, -7), Vector2(0, -5), Vector2(12, -5)],
}

## The three-letter tag of each hull.
const TAGS := {"scout": "SCT", "fighter": "FTR", "lance": "LNC", "bomber": "BMB", "logistics": "LOG", "support": "SUP",
	"flak": "FLK", "ion": "ION", "destroyer": "DST", "battlecruiser": "BC"}

## Which shape each hull wears.
const ICON_SHAPES := {
	"scout": "chevron", "fighter": "chevron", "lance": "chevron", "bomber": "bowtie",
	"logistics": "plus", "support": "plus", "flak": "hex_s", "ion": "hex_s",
	"destroyer": "hex_l", "battlecruiser": "hex_xl",
}

## The task of every class without a trial of its own, with its time limit.
const GENERIC_TEXT := "hit five moving drones with your main weapon in 60 seconds"
## The trials, a row for each ship class in the order of Ships.ORDER.
const TRIALS := [
	{"hull": "scout", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "scout_gun", "secs": 60.0},
	{"hull": "fighter", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "fighter_cannon", "secs": 60.0},
	{"hull": "lance", "text": "hit five moving drones with the Lance bolt", "target": "moving", "count": 5, "weapon": "lance_beam", "secs": 0.0},
	{"hull": "bomber", "text": "torpedo a drifting capital drone", "target": "capital", "count": 1, "weapon": "torpedo", "secs": 0.0},
	{"hull": "logistics", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "light_turret", "secs": 60.0},
	{"hull": "support", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "light_turret", "secs": 60.0},
	{"hull": "flak", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "flak_battery", "secs": 60.0},
	{"hull": "ion", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "ion_cannon", "secs": 60.0},
	{"hull": "destroyer", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "heavy_cannon", "secs": 60.0},
	{"hull": "battlecruiser", "text": GENERIC_TEXT, "target": "moving", "count": 5, "weapon": "ion_turret", "secs": 60.0},
]
