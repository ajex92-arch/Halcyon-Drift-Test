class_name Formations
extends RefCounted
## WHAT THIS IS: the shapes a pilot's wing can fly in, as plain data. A shape says where each
## of the three wingmen sits around the leader, how far a wingman may chase an enemy away from
## its place, and what the shape is called on the screen. It also holds the short words the
## wing strip and the pop-ups use (the fire settings, the hulls' short names).
##
## HOW IT WORKS: only constants and small static functions. A place ("slot") is a pair of
## numbers in the leader's own frame, measured in units of S, the wing's spacing (SquadEngine
## .spacing()): x is how far AHEAD of the leader (negative = behind it), y is how far to its
## STARBOARD side (the right-hand side; negative = to its port side). Slot 0, 1 and 2 belong to
## the first, second and third wingman and never move while that wingman lives. The four
## shapes the pilot can choose are WEDGE, LINE, COLUMN and LOOSE. JUNGLE is the fifth shape:
## the game flies it by itself, whatever was chosen, while the leader is in the asteroid
## jungle, because the passages there are narrow.
##
## WHO USES IT: SquadEngine (the maths), SquadOrders (the labels and the cycling), WingmanAI
## (the leash), WingWheel, WingStrip and the HUD pop-ups (the names), tests/squad_engine_check.gd.

## The wedge (the value 0 of the SET_FORMATION order): two wingmen behind the leader's quarters, the third behind them.
const WEDGE := 0
## The line abreast (the value 1): the wingmen side by side with the leader.
const LINE := 1
## The column (the value 2): the wingmen one behind another, behind the leader.
const COLUMN := 2
## The loose escort (the value 3): the wingmen far out to the sides and behind.
const LOOSE := 3
## The shape the game uses by itself in the jungle. Never the value of an order.
const JUNGLE := 4
## How many shapes a pilot can choose (the values 0 to COUNT - 1).
const COUNT := 4

## The name of each shape, index = shape (JUNGLE last).
const NAMES := ["Wedge", "Line", "Column", "Loose", "Jungle"]

## The places, per shape and slot, in units of S: Vector2(x ahead, y to starboard).
const SLOTS := [
	[Vector2(-1.1, -1.0), Vector2(-1.1, 1.0), Vector2(-2.2, 0.0)],
	[Vector2(0.0, -1.5), Vector2(0.0, 1.5), Vector2(0.0, -3.0)],
	[Vector2(-1.4, 0.0), Vector2(-2.8, 0.0), Vector2(-4.2, 0.0)],
	[Vector2(-1.6, -2.6), Vector2(-1.6, 2.6), Vector2(-3.4, 0.0)],
	[Vector2(-1.0, 0.0), Vector2(-2.0, 0.0), Vector2(-3.0, 0.0)],
]

## How far (world units) a wingman may chase an enemy away from its place before it gives
## the chase up and returns, per shape.
const LEASHES := [900.0, 900.0, 700.0, 1600.0, 400.0]

## The jungle shape is drawn tighter than its table: S is multiplied by this.
const JUNGLE_SCALE := 0.8

## The three fire settings (SET_STANCE "fire"), by value: the name on the wheel and the
## words of the pop-up that confirms it.
const FIRE_NAMES := ["At will", "Return fire", "Hold fire"]
## The pop-up words for each fire setting.
const FIRE_TOASTS := ["fire at will", "return fire", "hold fire"]

## The short name of each hull on the wing strip and in the pop-ups.
const HULL_SHORT := {
	"scout": "Scout", "fighter": "Fighter", "lance": "Lance", "bomber": "Bomber",
	"logistics": "Logistics", "support": "Support", "flak": "Flak", "ion": "Ion",
	"destroyer": "Destroyer", "battlecruiser": "Battlecruiser",
}


## The slot's place in units of S (x ahead, y to starboard) for shape `formation`, slot
## `index` (0 to 2). A value that is not a shape gives the wedge.
static func slot(formation: int, index: int) -> Vector2:
	var f := formation if formation >= 0 and formation < SLOTS.size() else WEDGE
	return (SLOTS[f] as Array)[clampi(index, 0, 2)]


## The name of shape `formation` ("Wedge", "Line", "Column", "Loose" or "Jungle").
static func formation_name(formation: int) -> String:
	if formation < 0 or formation >= NAMES.size():
		return str(NAMES[WEDGE])
	return str(NAMES[formation])


## The chase limit of shape `formation`, in world units.
static func leash_of(formation: int) -> float:
	if formation < 0 or formation >= LEASHES.size():
		return float(LEASHES[WEDGE])
	return float(LEASHES[formation])


## The next shape after `formation` in the list of four (the key preset's "next
## formation" computes an explicit value with this, so a toggle never reaches an order).
static func next_formation(formation: int) -> int:
	return (formation + 1) % COUNT


## The next fire setting after `fire` in the list of three (the key preset's "next fire
## setting").
static func next_fire(fire: int) -> int:
	return (fire + 1) % FIRE_NAMES.size()


## The short name of hull `hull_id` for the strip and the pop-ups (the hull's own label if it
## has no short name).
static func short_hull(hull_id: String) -> String:
	if HULL_SHORT.has(hull_id):
		return str(HULL_SHORT[hull_id])
	return hull_id.capitalize()
