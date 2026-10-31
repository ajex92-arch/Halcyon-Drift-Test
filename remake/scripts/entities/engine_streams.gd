class_name EngineStreams
extends RefCounted
## WHAT THIS IS: the rules for the engine streams of the four big hulls (Flak
## Frigate, Ion Frigate, Destroyer, Battlecruiser) of both teams. A big ship has
## several engine nozzles across its stern, and each nozzle shows a stream of
## its own, like the rows of engines on a big movie warship. Every other ship
## (the small craft, the Bomber) keeps one stream. It only works out where
## and how big; it draws nothing and changes nothing in the game.
##
## HOW IT WORKS:
##   - Which ships: HULLS names them. The nozzles of a hull are its drawn engines:
##     AurelianShapes' "nozzles" for the amber team (through AurelianPaint) and
##     CinderShapes' "nozzles" for the red team (through CinderPaint), each as
##     Vector3(x, y, radius) in the hull's 36-unit design space, the same points
##     the engine lights are drawn at. nozzles() returns them, or an empty list
##     for a ship that keeps one stream.
##   - One emitter, hopping: the ship's main flame is one CPUParticles2D emitter
##     (ShipVisual), and it stays the only one, and it keeps starting its dots
##     from one point. Two other ways change the match and are not used: making a
##     second flame emitter takes one more number from the match's shared dice rolls
##     (PITFALLS: a particle node uses a random number), and giving the one emitter a
##     list of starting points makes it take a number from the shared dice for every
##     dot it starts (Godot 4.7.2; tests/stream_check.gd shows it). Either would
##     change every roll after it. So the streams are made another way: each frame
##     ShipVisual moves the one emitter's single starting point to the next place of
##     a fixed round (plan() and spot()): to nozzle 1, then nozzle 2, then nozzle 3
##     and round again, so every nozzle gets a share of the dots and a stream of its
##     own. The dots of a stream stay where they were made (they are not moved with
##     the emitter), so each nozzle leaves its own trail.
##   - How big a stream is: it is sized to its nozzle. A nozzle's share of the round
##     is in proportion to its radius (a bigger nozzle starts more of the dots, so its
##     stream is denser), its starting places are spread across its width (so its
##     stream is as wide as the nozzle), the dots start at a speed that carries them
##     LENGTH_K nozzle widths before they fade (speed_range(): a bigger nozzle's
##     stream is longer), and the dots are DOT_K of the hull's average nozzle width
##     across (dot_range()). So a stream keeps its look next to its hull at every
##     zoom, where the one stream every ship had was the same few screen pixels on a
##     fighter and on a battlecruiser; a screen floor keeps far-away streams visible.
##     They are still bigger and faster while boosting, and the red team's are
##     still a quarter smaller (ShipVisual's jet_size, as for one stream).
##   - The side thrusters keep their own two emitters and are not touched.
##   - Test only: set_on() switches the streams off (every ship has the one stream it
##     had before), so the hull gallery can measure what the streams cost in a match,
##     and set_size() makes them bigger or smaller (the gallery's --stream-size).
##
## WHO USES IT: ShipVisual (_update_jets) every frame for a ship of the big
## hulls; tests/stream_check.gd checks the nozzles, the rules and that the dice
## stay untouched; the hull gallery's stream pictures (tests/lib/gallery_streams.gd).

## The hulls whose every nozzle gets its own stream (both teams). The small craft
## and the Bomber keep one stream.
const HULLS := ["flak", "ion", "destroyer", "battlecruiser"]
## The dots of the one stream every ship had before (the emitter of ShipVisual).
const BASE_DOTS := 24
## How many dots the emitter holds for each stream of a hull with several.
const DOTS_PER_STREAM := 36
## How long a stream is, in nozzle widths (the nozzle's diameter), at cruising speed.
const LENGTH_K := 1.8
## How big a dot is, as a fraction of the hull's average nozzle width.
const DOT_K := 0.15
## How far the dots of a stream fan out, in degrees either way (the one stream's is 12):
## a stream from a nozzle is a narrow jet, not a cloud.
const FAN_DEG := 3.0
## A stream is never shorter than this many screen pixels (a far-away or small nozzle's
## stream would vanish).
const MIN_LENGTH_PX := 7.0
## A dot is never smaller than this many screen pixels (a smaller one does not show).
const MIN_DOT_PX := 1.6
## How much longer the streams are while boosting (the dots' speed; the one stream's
## was about 1.8 times as fast).
const BOOST_REACH := 1.8
## How long a dot lives, in seconds (the emitter's lifetime, ShipVisual._jet()).
const DOT_LIFE := 0.35
## How many places all the nozzles of a hull share between them in one round (each
## nozzle gets its share by radius, and at least one).
const TOTAL_PLACES := 12
## How much of a nozzle's width its stream starts across: 0.6 = from the middle
## 60% of the nozzle's opening, so the stream sits inside the nozzle.
const SPREAD := 0.6
## The size of the streams next to the rule (1), unless a test sets another.
static var _size := 1.0
## 1 = the big hulls show a stream from each nozzle (always, in play), 0 = they show the
## one stream every ship had (only while the gallery test compares the two, to measure
## what the streams cost).
static var _mode := 1

## How far behind a nozzle's middle its stream starts, as a fraction of its
## radius, for the amber team: its nozzles are drawn with their middle on the
## hull's rear edge (AurelianShapes), so the stream starts right there.
const AURELIAN_BACK := 0.0
## The same for the red team: its nozzles are drawn inside the hull's stern
## (CinderShapes), so the stream starts at the nozzle's back rim, a whole radius
## behind its middle.
const CINDER_BACK := 1.0


## The engine nozzles of a ship of hull `hull_id` on `team`, each as Vector3(x,
## y, radius) in the hull's 36-unit design space (x forward, y to starboard), or
## an empty list when the ship keeps one stream: a small craft, the Bomber, or
## a team drawn the plain old way (the gallery's comparison look).
static func nozzles(team: int, hull_id: String) -> Array:
	if _mode == 0 or not HULLS.has(hull_id):
		return []
	if CinderPaint.alien(team):
		return CinderPaint.nozzles(hull_id)
	if AurelianPaint.on(team):
		return AurelianPaint.nozzles(hull_id)
	return []


## Switch the streams on or off while the game runs. Tests use it to measure the
## streams against the one stream every ship had (the hull gallery's --live-look=streams).
static func set_on(is_on: bool) -> void:
	_mode = 1 if is_on else 0


## Make the streams `s` times as long and their dots `s` times as big while the game
## runs (1 = the rule). Tests use it to look at other sizes (the hull gallery's
## --stream-size=N).
static func set_size(s: float) -> void:
	_size = s


## How many dots the emitter holds for `count` streams: DOTS_PER_STREAM for each, or
## the 24 dots of the one stream every ship had.
static func dots(count: int) -> int:
	if count <= 1:
		return BASE_DOTS
	return DOTS_PER_STREAM * count


## How far behind a nozzle's middle the streams of `team`'s ships start, as a
## fraction of the nozzle's radius (AURELIAN_BACK or CINDER_BACK).
static func back(team: int) -> float:
	return CINDER_BACK if team == Rules.CINDER else AURELIAN_BACK


## The round the emitter visits the starting places in, one place a frame, for the
## nozzle list `nozzle_list`:
##   "nozzle"  PackedInt32Array, the nozzle of each step
##   "across"  PackedFloat32Array, the place across the nozzle's width, -1 to 1
##   "radius"  PackedFloat32Array, the radius of each step's nozzle (design units)
##   "mean_r"  the average radius of all the nozzles (design units)
## Each nozzle has places in proportion to its radius (at least one), spread evenly
## across its width. The places of one nozzle are spread evenly through the round, and
## the nozzles start at different moments of it, so a nozzle's stream is made of evenly
## spaced bursts of dots and a nozzle with company is not asked twice in a row more
## than its share needs.
static func plan(nozzle_list: Array) -> Dictionary:
	var count := nozzle_list.size()
	var total_r := 0.0
	for nz: Vector3 in nozzle_list:
		total_r += nz.z
	# Every place as [its moment in the round (0 to 1), its nozzle, its place across the nozzle].
	var places: Array = []
	for i in count:
		var nz: Vector3 = nozzle_list[i]
		var k := maxi(1, roundi(float(TOTAL_PLACES) * nz.z / maxf(0.001, total_r)))
		for j in k:
			places.append([(float(j) + (float(i) + 0.5) / float(count)) / float(k), i, (float(j) + 0.5) / float(k) * 2.0 - 1.0])
	places.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var which := PackedInt32Array()
	var across := PackedFloat32Array()
	var radius := PackedFloat32Array()
	for pl: Array in places:
		which.append(int(pl[1]))
		across.append(float(pl[2]))
		radius.append((nozzle_list[int(pl[1])] as Vector3).z)
	return {"nozzle": which, "across": across, "radius": radius, "mean_r": total_r / maxf(1.0, float(count))}


## Where the emitter starts its dots on step `step` of `the_plan` (it wraps round), as
## an offset from the ship's middle in world units, for a ship whose design space is
## scaled by `un` (world units per design unit), facing along `f` with `port` its
## left-hand side: `behind` radii behind the nozzle's middle (see back()), and
## across the nozzle's width by the plan's place.
static func spot(nozzle_list: Array, the_plan: Dictionary, step: int, un: float, f: Vector2, port: Vector2, behind: float) -> Vector2:
	var which: PackedInt32Array = the_plan["nozzle"]
	var across: PackedFloat32Array = the_plan["across"]
	var at := step % which.size()
	var nz: Vector3 = nozzle_list[which[at]]
	return f * ((nz.x - nz.z * behind) * un) - port * (nz.y * un) + port * (across[at] * nz.z * un * SPREAD)


## The speed range (minimum, maximum; world units a second) of the dots started on step
## `step` of `the_plan`: they travel LENGTH_K nozzle widths (never under MIN_LENGTH_PX
## screen pixels, `px` world units each) in their life, more when `boosting`, and `jet_size`
## is ShipVisual's team size (1, or 0.75 for the red team). A bigger nozzle's stream is longer.
static func speed_range(the_plan: Dictionary, step: int, un: float, px: float, boosting: bool, jet_size: float) -> Vector2:
	var radius: PackedFloat32Array = the_plan["radius"]
	var width := 2.0 * radius[step % radius.size()] * un
	var length := maxf(LENGTH_K * width * _size, MIN_LENGTH_PX * px) * jet_size * (BOOST_REACH if boosting else 1.0)
	var mean := length / DOT_LIFE
	return Vector2(0.75 * mean, 1.25 * mean)


## The size range (smallest, biggest; world units) of the dots of a hull with the plan
## `the_plan`: DOT_K of the hull's average nozzle width (never under MIN_DOT_PX screen
## pixels, `px` world units each), the biggest a half bigger again while `boosting`.
static func dot_range(the_plan: Dictionary, un: float, px: float, boosting: bool, jet_size: float) -> Vector2:
	var width := 2.0 * float(the_plan["mean_r"]) * un
	var base := maxf(DOT_K * width * _size, MIN_DOT_PX * px) * jet_size
	return Vector2(0.65 * base, 1.15 * base * (1.5 if boosting else 1.0))
