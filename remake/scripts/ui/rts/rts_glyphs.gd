class_name RtsGlyphs
extends RefCounted
## WHAT THIS IS: the small signs of the Admiral's awareness screens, drawn in code: the kind of an alert (a
## check for something done, a flask for research), the state of a squadron (moving, fighting, idle or holding,
## retreating, docked), the win-odds mark of an army card (an up chevron, two level bars, a down chevron) and the grey x of an
## order that did nothing. The danger triangle stays Glyphs.danger.
##
## HOW IT WORKS: every sign is a fixed list of strokes (SHAPES), each stroke a list of points in a box that
## runs from -0.5 to 0.5 both ways (x to the right, y down). draw() scales the strokes to `size` pixels round
## `centre` and draws them as lines on the canvas item that asked, from its _draw(): no node per sign and
## nothing that moves. Each sign has its own shape, so it reads without colour; the callers draw it in the
## light colour (Palette.ICE) or the grey one (Palette.MIST), which draw_x() uses.
##
## WHO USES IT: the alert feed, the army cards, the selection tags and the order feedback marks (the screens of
## the awareness stage); tests/rts_glyphs_check.gd draws each one once.

## The side of a sign's box at the game's base size (pixels).
const SIZE := 12.0

## The signs: name -> its strokes, each a list of points in the -0.5 to 0.5 box.
const SHAPES := {
	# Alert kinds.
	"check": [[Vector2(-0.42, 0.02), Vector2(-0.12, 0.34), Vector2(0.44, -0.36)]],
	"flask": [
		[Vector2(-0.22, -0.46), Vector2(0.22, -0.46)],
		[Vector2(-0.12, -0.46), Vector2(-0.12, -0.10), Vector2(-0.42, 0.44), Vector2(0.42, 0.44), Vector2(0.12, -0.10), Vector2(0.12, -0.46)],
		[Vector2(-0.27, 0.18), Vector2(0.27, 0.18)],
	],
	# Squadron states.
	"moving": [
		[Vector2(-0.45, 0.0), Vector2(0.42, 0.0)],
		[Vector2(0.10, -0.32), Vector2(0.45, 0.0), Vector2(0.10, 0.32)],
	],
	"fighting": [[
		Vector2(0.0, -0.48), Vector2(0.12, -0.12), Vector2(0.48, 0.0), Vector2(0.12, 0.12),
		Vector2(0.0, 0.48), Vector2(-0.12, 0.12), Vector2(-0.48, 0.0), Vector2(-0.12, -0.12), Vector2(0.0, -0.48),
	]],
	"idle": [
		[Vector2(-0.18, -0.38), Vector2(-0.18, 0.38)],
		[Vector2(0.18, -0.38), Vector2(0.18, 0.38)],
	],
	"retreating": [
		[Vector2(0.30, 0.42), Vector2(0.30, -0.10), Vector2(0.18, -0.32), Vector2(0.0, -0.40), Vector2(-0.18, -0.32), Vector2(-0.30, -0.10), Vector2(-0.30, 0.40)],
		[Vector2(-0.48, 0.16), Vector2(-0.30, 0.42), Vector2(-0.12, 0.16)],
	],
	"docked": [
		[Vector2(-0.42, -0.30), Vector2(-0.30, 0.40), Vector2(0.30, 0.40), Vector2(0.42, -0.30)],
		[Vector2(-0.10, 0.02), Vector2(0.10, 0.02)],
	],
	# The win-odds mark of an army card: an up chevron (likely win), two level bars (even), a down chevron (likely loss).
	"odds_win": [[Vector2(-0.42, 0.22), Vector2(0.0, -0.26), Vector2(0.42, 0.22)]],
	"odds_even": [
		[Vector2(-0.40, -0.16), Vector2(0.40, -0.16)],
		[Vector2(-0.40, 0.16), Vector2(0.40, 0.16)],
	],
	"odds_loss": [[Vector2(-0.42, -0.22), Vector2(0.0, 0.26), Vector2(0.42, -0.22)]],
	# An order that did nothing.
	"x": [
		[Vector2(-0.36, -0.36), Vector2(0.36, 0.36)],
		[Vector2(-0.36, 0.36), Vector2(0.36, -0.36)],
	],
}

## The five squadron states, in the order the screens list them.
const STATES := ["moving", "fighting", "idle", "retreating", "docked"]

## The three win-odds marks' signs, in the order of WinOdds.MARKS (win, even, loss).
const ODDS := ["odds_win", "odds_even", "odds_loss"]


## Is `kind` a sign this file draws?
static func has(kind: String) -> bool:
	return SHAPES.has(kind)


## The strokes of sign `kind` on the screen: its box `size` pixels wide with its middle at `centre`. An unknown
## kind gives no strokes.
static func strokes(kind: String, centre: Vector2, size: float = SIZE) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for stroke: Array in SHAPES.get(kind, []):
		var pts := PackedVector2Array()
		for p: Vector2 in stroke:
			pts.append(centre + p * size)
		out.append(pts)
	return out


## Draw sign `kind` on canvas item `ci` with its middle at `centre`, `size` pixels wide, in `colour` (the light
## colour unless the caller greys it). Call it from the item's _draw(). An unknown kind draws nothing.
static func draw(ci: CanvasItem, kind: String, centre: Vector2, size: float = SIZE, colour: Color = Palette.ICE) -> void:
	var line := clampf(1.5 * size / SIZE, 1.0, 3.0)
	for pts: PackedVector2Array in strokes(kind, centre, size):
		ci.draw_polyline(pts, colour, line, true)


## Draw the grey x of an order that did nothing.
static func draw_x(ci: CanvasItem, centre: Vector2, size: float = SIZE) -> void:
	draw(ci, "x", centre, size, Palette.MIST)
