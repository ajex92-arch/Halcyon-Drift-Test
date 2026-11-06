class_name ScumShapes
extends RefCounted
## WHAT THIS IS: the drawings of the Scum, the pirate faction that lives in the jungle,
## as lists of points. Three ships: the Scum Raider ("Hookfang": a dented hulk dragging a
## harpoon down one side), the Scum Carrier ("Chained Wrecks": a stolen Aurelian hull and a
## stolen Vhorr hull lashed together with girders, the Fighters leaving through the gap) and
## the Scum Fighter ("Nail": a fat engine bell with a needle welded to its front). The
## tables are only pictures: they change nothing in the game.
##
## HOW IT WORKS: every list is a polygon or a set of line segments in world units from the
## ship's middle, with the nose along +x and +y toward the ship's right side (down on the screen
## when the nose points right). The Raider's lists are drawn for a hull of radius RAIDER_RADIUS
## (the bigger den ships scale them), the Carrier's for CARRIER_RADIUS, and the Fighter's for a
## shape unit of FIGHTER_UNIT (it grows when the unit is drawn bigger than its true size, so it
## stays readable far away). ScumPaint draws the lists and turns them with the ship. The colours
## are the SCUM_ constants of Palette.
##
## WHO USES IT: ScumPaint reads the lists; the hull gallery's size check keeps each ship inside
## the hit circle its hull radius gives it.

## The radius of the Raider the lists below are drawn for (the Gunship camp, Jungle.CAMPS).
const RAIDER_RADIUS := 50.0
## The radius of the Carrier the lists below are drawn for.
const CARRIER_RADIUS := 70.0
## The length of the Fighter's old dart in world units; the Fighter's lists are drawn for this
## size and scaled up with the old size floor (see ScumPaint.draw_fighter()).
const FIGHTER_UNIT := 11.2

## The Raider's hull: a rounded, dented hulk.
const RAIDER_HULL := [
	Vector2(34, -2), Vector2(30, 12), Vector2(16, 26), Vector2(-4, 32), Vector2(-24, 30), Vector2(-40, 18),
	Vector2(-46, 0), Vector2(-40, -18), Vector2(-26, -30), Vector2(-6, -32), Vector2(12, -26), Vector2(28, -14),
]
## The harpoon: a long blade lashed down the Raider's right side; it sticks out past the nose.
const RAIDER_BLADE := [Vector2(50, 12), Vector2(36, 5), Vector2(-14, 8), Vector2(-14, 18), Vector2(36, 19)]
## Where the harpoon's point is drawn when the view is zoomed far out (ScumPaint._far()): 76 units
## from the ship's middle instead of 50, 42 units ahead of the hull's nose instead of 16, so the
## spike still shows when the whole ship is about 32 pixels across.
const RAIDER_SPIKE_FAR := Vector2(76, 12)
## The straps that hold the harpoon (three bars across it) and the Scum mark on the hump behind
## it (a lopsided cross), as pairs of points: one hazard-yellow multiline.
const RAIDER_TAPE := [
	Vector2(24, 3), Vector2(24, 21), Vector2(6, 4), Vector2(6, 22), Vector2(-10, 5), Vector2(-10, 21),
	Vector2(-18, 12), Vector2(-32, 24), Vector2(-20, 22), Vector2(-28, 16),
]
## The panel punched out of the Raider's left side: an open hole with the frame showing.
const RAIDER_HOLE := [Vector2(12, -12), Vector2(14, -24), Vector2(-12, -30), Vector2(-18, -14)]
## The girders across the hole, as pairs of points.
const RAIDER_GIRDERS := [Vector2(12, -12), Vector2(-12, -30), Vector2(14, -24), Vector2(-18, -14), Vector2(0, -13), Vector2(-2, -29)]
## The engine bell shoved into the back left corner; it sticks out past the hull.
const RAIDER_BELL := [Vector2(-22, -6), Vector2(-22, -24), Vector2(-44, -26), Vector2(-50, -14), Vector2(-44, -4)]
## The middle of the Raider's engine glow, in the bell.
const RAIDER_GLOW_AT := Vector2(-40, -15)
## The radius of the Raider's engine glow, in world units (it flutters a little).
const RAIDER_GLOW_R := 8.0
## The flame behind the bell (a faint green triangle).
const RAIDER_FLAME := [Vector2(-49, -21), Vector2(-49, -7), Vector2(-60, -14)]

## The Carrier's right-hand hull: a stolen Aurelian slab.
const CARRIER_STEEL := [
	Vector2(60, 14), Vector2(78, 20), Vector2(64, 36), Vector2(58, 54), Vector2(20, 60),
	Vector2(-26, 58), Vector2(-54, 50), Vector2(-68, 32), Vector2(-62, 16), Vector2(-20, 14),
]
## The Carrier's left-hand hull: a stolen Vhorr crescent. Its inner edge and the steel hull's
## top edge make the launch channel, 28 wide at the stern and 44 at the mouth.
const CARRIER_CRESCENT := [
	Vector2(34, -30), Vector2(52, -38), Vector2(48, -50), Vector2(22, -60), Vector2(-12, -64),
	Vector2(-44, -56), Vector2(-64, -40), Vector2(-70, -24), Vector2(-56, -10), Vector2(-20, -14),
]
## The girders lashing the two hulls: the forward bridge (the gun stands on it), the aft bridge
## and a chain cross between them, as pairs of points.
const CARRIER_GIRDERS := [
	Vector2(44, -34), Vector2(44, 18), Vector2(-52, -14), Vector2(-52, 20),
	Vector2(-40, -12), Vector2(-28, 16), Vector2(-28, -12), Vector2(-40, 16),
]
## The hazard tape on the bridge (two stripes) and the Scum mark on the steel hull (three slashes
## leaning back), as pairs of points.
const CARRIER_TAPE := [
	Vector2(41, -8), Vector2(47, -2), Vector2(41, 4), Vector2(47, 10),
	Vector2(4, 30), Vector2(-4, 46), Vector2(-2, 30), Vector2(-10, 46), Vector2(-8, 30), Vector2(-16, 46),
]
## The ram beak welded on the steel hull's nose.
const CARRIER_BEAK := [Vector2(60, 14), Vector2(78, 20), Vector2(64, 36), Vector2(54, 22)]
## The launch guide lights down the channel, as pairs of points.
const CARRIER_LIGHTS := [Vector2(26, -8), Vector2(18, -7), Vector2(4, -5), Vector2(-4, -4), Vector2(-18, -2), Vector2(-26, -1)]
## The two engines: the middle, the radius and a number that keeps the two from pulsing together.
const CARRIER_ENGINES := [
	{"at": Vector2(-66, 36), "r": 13.0, "k": 0.0},
	{"at": Vector2(-66, -32), "r": 9.0, "k": 2.1},
]

## The Fighter's body at the true size: the engine bell and the needle welded to its front, one
## polygon.
const FIGHTER_BODY := [
	Vector2(12, 0), Vector2(2.5, 1.2), Vector2(1.5, 3.6), Vector2(-0.5, 6.8), Vector2(-5.5, 6.8), Vector2(-8, 4),
	Vector2(-8, -4), Vector2(-5.5, -6.8), Vector2(-0.5, -6.8), Vector2(1.5, -3.6), Vector2(2.5, -1.2),
]
## The middle of the Fighter's engine glow, in the bell.
const FIGHTER_GLOW_AT := Vector2(-5.5, 0)
## The radius of the Fighter's engine glow, in world units (it flutters a little).
const FIGHTER_GLOW_R := 4.2
## The two ends of the yellow weld collar across the bell's front face.
const FIGHTER_COLLAR := [Vector2(1.9, -3.4), Vector2(1.9, 3.4)]
