class_name RtsFx
extends RefCounted
## WHAT THIS IS: the two drawings of a bought ship's arrival: the slide of a small ship out of the
## mothership and the warp streak of a capital ship across the map. They are pictures only. The
## ship is in the game from its first tick (Arrivals); nothing here is read by the rules, and
## with --sim-only (Effects draws nothing) none of it runs.
##
## HOW IT WORKS: Effects calls draw() at the end of its own drawing, every frame. draw() reads the
## arrival data Arrivals wrote into each team's Production.fx (a Dictionary per picture with its
## kind, its start and end tick, where from and where to) and works out how far each one has got
## from the world's tick count, so the pictures follow the game's speed and stop when it is paused.
##   - "slide" (SLIDE_TICKS, 1.5 seconds): the ship is drawn moving from the mothership's middle to
##     its launch spot. The ship's drawing node (its "Visual" child) is moved by the missing part of
##     the way and put back at the end; the ship itself stands at its spot all the time.
##   - "warp" (WARP_TICKS, 4 seconds): a streak runs from the nearest map edge to the warp spot, a
##     bright head with a fading trail, and a faint ring grows at the spot. The ship is not in the
##     game yet and cannot be shot.
##   - "warp_land" (SLIDE_TICKS): a ring opens round the ship on the tick it appears.
## Every picture only grows, moves or fades once: nothing blinks (the flash table lists the slide
## and the streak at 0 flashes a second). No random numbers are used, no node is made and no
## timer or tween runs: the shapes are lines, arcs and circles drawn in the team's colour and the
## warm white of Palette.BOOST.
##
## WHO USES IT: Effects._draw (one line); Arrivals writes the data; tests/yard_shots.gd looks at it.

## How far behind its head the streak's trail reaches, as a share of the whole way.
const TRAIL := 0.3


## Draw every arrival picture of both teams on `fx` (the Effects node, which is being drawn), with
## `px` the size of one screen pixel in world units.
static func draw(fx: Effects, world: World, px: float) -> void:
	if world.teams.size() < 2:
		return
	var now := world.tick_count
	for t in 2:
		var prod: Production = world.teams[t].production
		if prod == null:
			continue
		for e: Dictionary in prod.fx:
			var span := maxi(1, int(e["t1"]) - int(e["t0"]))
			var k := clampf(float(now - int(e["t0"])) / float(span), 0.0, 1.0)
			match str(e["kind"]):
				"slide":
					_slide(world, e, k)
				"warp":
					_streak(fx, e, k, px, Palette.team(t))
				"warp_land":
					_landing(fx, e, k, px, Palette.team(t))


## Move the ship's drawing node back by the part of the slide that is left (k goes 0 to 1).
static func _slide(world: World, e: Dictionary, k: float) -> void:
	var ship := world.by_uid.get(int(e["uid"])) as Ship
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	var visual := ship.get_node_or_null("Visual") as Node2D
	if visual == null:
		return
	var eased := k * k * (3.0 - 2.0 * k)
	var missing := (Vector2(e["from"]) - Vector2(e["to"])) * (1.0 - eased)
	visual.global_position = ship.global_position + missing


## The warp streak at progress `k` (0 at the edge, 1 at the spot).
static func _streak(fx: Effects, e: Dictionary, k: float, px: float, color: Color) -> void:
	var a := Vector2(e["from"])
	var b := Vector2(e["to"])
	if not fx._seen(b):
		return
	var head := a.lerp(b, k)
	var tail := a.lerp(b, maxf(0.0, k - TRAIL))
	# The whole way, faintly, so the eye can follow where it goes.
	fx.draw_line(a, b, Palette.with_alpha(color, 0.12), 2.0 * px)
	# The trail, wide and dim, then a narrower brighter part, then the head.
	fx.draw_line(tail, head, Palette.with_alpha(color, 0.35), 7.0 * px)
	fx.draw_line(a.lerp(b, maxf(0.0, k - TRAIL * 0.4)), head, Palette.with_alpha(Palette.BOOST, 0.8), 3.0 * px)
	fx.draw_circle(head, 6.0 * px, Palette.BOOST)
	# At the spot a ring opens as the streak nears it.
	fx.draw_arc(b, 90.0 * k, 0.0, TAU, 48, Palette.with_alpha(color, 0.45 * k), 2.0 * px, true)


## The ring that opens round a capital ship as it appears (k goes 0 to 1).
static func _landing(fx: Effects, e: Dictionary, k: float, px: float, color: Color) -> void:
	var at := Vector2(e["to"])
	if not fx._seen(at):
		return
	var r := float(Ships.get_def(str(e["hull"]))["radius"])
	fx.draw_arc(at, r * (0.6 + 1.8 * k), 0.0, TAU, 64, Palette.with_alpha(Palette.BOOST, (1.0 - k) * 0.7), 3.0 * px, true)
	fx.draw_arc(at, r * (0.4 + 1.2 * k), 0.0, TAU, 64, Palette.with_alpha(color, (1.0 - k) * 0.5), 2.0 * px, true)
