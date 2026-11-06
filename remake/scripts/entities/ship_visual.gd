class_name ShipVisual
extends Node2D
## WHAT THIS IS: the "painter" of a pilot ship. It draws the ship's shape in
## its team colour, its four shield arcs, its hull and shield bars and its
## name, plus the engine flames, and (on the ship the human flies, and on no
## other) an arrow showing where it is drifting. It changes nothing in the
## game; it only draws.
##
## HOW IT WORKS:
##   - It is the "Visual" child node of every Ship (scenes/entities/
##     ship.tscn). Each frame, _process() updates the flames and asks Godot
##     to redraw; Godot then calls _draw().
##   - The ship node turns with the ship, and so would this child. To keep
##     the arrow, the bars and the name upright, this node turns itself back
##     the other way ("counter-rotates"), so its drawing frame always lines
##     up with the world. The ship's shape is then turned by hand.
##   - The hull itself is not drawn again every frame. It is drawn on a kept
##     picture, a DrawCache node called "Hull" on a "Spin" node that turns with the
##     ship (so its picture is drawn with the nose along +x), and _update_hull() tells it
##     once a frame what the hull looks like now. It is drawn again only when
##     something it shows changes: the hit flash, ace, the human's ship, how hot
##     the engines glow, a nose gun's kick, the pulse of the veins of a big Cinder
##     hull, the camera zoom (by 2%) or a test switch of DrawParts. The four shield
##     arcs have a kept picture of their own on the same "Spin" node (ShieldArcs:
##     drawn again when a zone's fill moves by a thirty-second or the hit glow starts
##     or ends; the usual play zoom and further out draw all four arcs as one command),
##     and the bars and the name have one of their own that stays upright (drawn again
##     when a bar moves by a 64th). What changes by the frame stays on this node's own
##     picture: the heads of the turning guns, a Bomber's torpedo run and the human's
##     drift arrow; a ship with none of those asks for no redraw of its own at all. A ship the fog hides,
##     or one far from the camera's view (ViewCull), is not brought up to date until it shows or comes near again.
##   - The camera can zoom far out (a "Homeworld" zoom, after the space game
##     of that name). Ships are drawn bigger than life when needed so they
##     are always at least MIN_PX screen pixels long, and lines are
##     multiplied by `px` (world units per screen pixel) so they keep the
##     same thickness on screen at any zoom.
##   - The flames are CPUParticles2D nodes (small dots of light fired out by
##     Godot): one for the main engine and one for each side thruster. At the usual
##     play zoom and further out (camera zoom under DrawCache.CLOSE_ZOOM) each holds
##     half its dots, and far out (under FAR_FLAMES_ZOOM) the flames are stopped and
##     hidden. The three emitters are made all the same (each takes a number from the
##     match's shared random sequence), only their dots change.
##   - The four big hulls of both teams (EngineStreams.HULLS) have several engine
##     nozzles and show an engine stream from each one. It is still the one main
##     flame emitter, starting its dots from one point, but each frame the point
##     moves to the next nozzle of a fixed round (EngineStreams.plan() and spot()),
##     so every nozzle gets its share of the dots and leaves a trail of its own.
##     No emitter is added and the emitter starts its dots from one point as
##     always, because every extra emitter, and every list of starting points,
##     would take numbers from the match's shared random sequence. A stream is
##     sized to its nozzle (its length, its width and its dots follow the nozzle's
##     width), not a fixed number of screen pixels as the one stream was. The small
##     craft and the Bomber keep one stream, and the side thrusters are as they were.
##   - Cinder (the red team) wears an alien look: a Cinder ship's shape is
##     drawn by CinderPaint from the tables in CinderShapes (dark, bladed hulls
##     with glowing veins) instead of from HULLS below, and its flames come
##     out of the alien hull's own engines, a quarter smaller than Aurelian's
##     (CINDER_JET_SIZE). Each Cinder hull keeps the length and width of its
##     Aurelian hull; shield arcs, bars, name and the arrow are drawn as
##     before.
##   - Aurelian (the amber team) wears a steel look: a hull is drawn by
##     AurelianPaint from the named pieces in AurelianShapes (armour plates,
##     glass canopies, engine nozzles) inside an amber outline, and its flames
##     come out of the hull's own engines. The plain outlines of HULLS below are
##     drawn only while the steel look is off (the hull gallery's measurements).
##   - Every gun that turns (a turret or an automatic mount) is drawn as a small
##     turret on the hull by TurretPaint, turned the way the gun points; a fixed
##     gun gets none.
##   - A Bomber on a torpedo run gets the fan of its three torpedoes' lines and a
##     bar under it, for everyone to see; after a launch the bar drains over the
##     reload; the Bomber the human flies also shows a hint and a sight (RunPaint,
##     FanPaint).
##   - When a gun fires, its barrel kicks back and slides home (GunKick): each frame
##     _update_hull() lets the ship's GunKick look at the guns' cooldowns (it reads
##     them, it never changes them) and _draw() hands it to TurretPaint, and the hull
##     picture to AurelianPaint for the amber hulls' nose guns.
##   - With --sim-only (Game.sim_only) it draws nothing at all: it hides
##     itself, makes no flames and does no per-frame work. One detail keeps
##     the match exactly the same: making a CPUParticles2D takes one number
##     from the game's shared random sequence, so _ready() takes the same
##     three numbers itself (see there).
##   - Test only: the switches of DrawParts (--bench-off=flames,arcs,arrow,
##     bars,name,outline,redraw) turn one part of all this off, so a test can
##     measure what that part costs. With no switch given every part is
##     drawn as always. The three flame emitters are still made with "flames"
##     off, for the same random-number reason as above.
##
## WHO USES IT: Godot runs it as part of ship.tscn (it makes the DrawCache of the hull
## itself, when it starts). It reads the Ship's
## thrust_* values, boosting, ace_t, flash, shields, velocity and f_max,
## and the pilot profile's is_human, and the ship's mounts. AurelianPaint draws
## the Aurelian hulls, CinderPaint the Cinder hulls (and tints their flames),
## TurretPaint the turrets, EngineStreams works out the big hulls' stream places.
## DrawParts holds the test-only switches it reads. ShieldArcs draws the shield arcs.

## Each hull's plain outline: a list of corner points, nose pointing right (+x),
## for a ship 36 units long (they are scaled to the hull's real length). The
## Aurelian steel hulls (AurelianShapes) keep these sizes to within about a
## tenth (more only where a gun mount sits outside the plain outline: the
## Bomber's torpedo mount, the Destroyer's and Battlecruiser's point-defense
## mounts); this table is drawn only while the steel look is off, and is the size
## the hull gallery checks the Cinder shapes against. Hulls not listed here use
## the "fighter" shape.
const HULLS := {
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
## Minimum drawn length of a ship, in screen pixels.
const MIN_PX := 16.0
## How big a Cinder ship's engine flames are next to Aurelian's: 0.75 = a
## quarter smaller (smaller dots, and plumes a quarter shorter and narrower),
## so they do not drown out the alien hull itself (the user, Sun 2026-10-18:
## "The engine effects are too large and overwhelm the design").
const CINDER_JET_SIZE := 0.75
## How many dots a flame emitter holds close up (the side flames always; the main flame
## of a ship with one stream, see EngineStreams.dots()).
const JET_DOTS := 24
## The share of its dots an emitter holds at the usual play zoom and further out (the
## camera zoom under DrawCache.CLOSE_ZOOM).
const PLAY_DOT_SHARE := 0.5
## The fewest dots an emitter is ever cut down to.
const FEWEST_DOTS := 4
## The camera zoom under which a ship shows no flames at all (the view is wider than
## about 8,500 screen pixels of the game's 1280-wide picture: the widest pilot zoom-out
## and the admiral's overview). The emitters are still there, stopped and hidden.
const FAR_FLAMES_ZOOM := 0.15

## The ship we draw (our parent node).
var ship: Ship
## Flames of the main engine.
var main_jet: CPUParticles2D
## Flames of the port (left-pushing) thruster.
var port_jet: CPUParticles2D
## Flames of the starboard (right-pushing) thruster.
var star_jet: CPUParticles2D
## True when the human player flies this ship (drawn bolder, named "YOU").
var is_human := false
## True once the flames of a Cinder ship have been given their own colours
## (CinderPaint.tint_jets). It happens on the first frame, because the ship's
## team is not known yet when _ready() runs.
var _tinted := false
## True once _draw() has drawn this ship at least once. With the test switch
## DrawParts.redraw off we ask for a new picture only until this is true.
var _drawn := false
## True while the three flame emitters are parked (stopped and hidden) because
## the test switch DrawParts.flames is off.
var _jets_hidden := false
## The share of its dots each emitter holds now (1 close up, PLAY_DOT_SHARE further out).
var _dot_share := 1.0
## The speed the three flame emitters run at: the world's speed (WorldSpeed;
## 1.0 normal, less in slow motion), set when it changes.
var _jet_speed := 1.0
## How many engine streams the main flame emitter is set up for (set_streams()):
## 1 = the one stream of every ship, more = one for each nozzle of a big hull.
var _streams := 1
## The nozzle list of the streams (empty for one stream).
var _nozzles: Array = []
## When each of the ship's guns last fired, as the painter has seen it (GunKick).
var _kicks := GunKick.new()
## The round the emitter visits the nozzles' starting places in (EngineStreams.plan()).
var _plan := {}
## Which step of the round the emitter is on: it moves on one step every frame.
var _hop := 0
## The node the kept pictures hang on (made in _ready()). It turns with the ship, so
## their pictures are drawn with the nose pointing along +x.
var _spin: Node2D
## The kept picture of the hull (a child of _spin).
var _hull: DrawCache
## True while the hull's kept picture has glowing veins that pulse (a big Cinder
## hull), so the picture is drawn again each time the pulse takes a new step.
var _pulses := false
## The kept picture of the four shield arcs (a child of _spin, over the hull).
var _shield: DrawCache
## The size of each shield zone (front, rear, left, right) as of the last look (worked out again
## only when the shield total or focus change).
var _caps := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## The shield total the sizes in _caps were worked out for (-1 = not yet).
var _caps_total := -1.0
## The shield focus the sizes in _caps were worked out for (-1 = not yet).
var _caps_focus := -1
## The kept picture of the hull bar, the shield bar and the name (upright, drawn
## over this node's own drawing).
var _gauges: DrawCache
## True when the last _draw() of this node drew something (guns' heads, a torpedo
## run, the drift arrow), so the next frame asks for one more drawing that clears it
## once nothing is left to draw.
var _live_drawn := false
## The mount list the flags below were worked out for (a new list means new flags).
var _mounts_seen: Array = []
## How many mounts the list had then.
var _mounts_n := -1
## True when any of the ship's guns turns (so a head is drawn for it, each frame).
var _has_heads := false


## Find our ship and make the three flame emitters. With --sim-only
## (Game.sim_only) nothing is ever drawn, so we make no flames, hide
## ourselves and stop our per-frame work for good: the simulation never reads
## this node. One thing must still happen: Godot's CPUParticles2D picks its
## own random seed from the game's shared random sequence when it is made (it
## takes one number from it), and that is the very sequence the AI and the
## guns use. So the three flames cost three numbers of the sequence, and we
## take the same three here, or every later dice roll would be different and
## the match would no longer be the same match. For the same reason the three
## emitters are made even when the test switch DrawParts.flames is off (it
## only stops and hides them, in _update_jets()).
func _ready() -> void:
	ship = get_parent() as Ship
	if Game.sim_only:
		visible = false
		set_process(false)
		for _i in 3:
			randi()
		return
	DrawParts.read_options()
	# The kept pictures that turn with the ship (see DrawCache) hang on one node, the
	# "Spin", which turns the way the ship turns and is drawn behind everything this
	# node draws. The hull's is the first.
	_spin = Node2D.new()
	_spin.name = "Spin"
	_spin.show_behind_parent = true
	add_child(_spin)
	_hull = DrawCache.new()
	_hull.name = "Hull"
	_hull.draw.connect(_draw_hull_layer)
	_spin.add_child(_hull)
	_shield = DrawCache.new()
	_shield.name = "Shield"
	_shield.draw.connect(_draw_shield_layer)
	_spin.add_child(_shield)
	# The bars and the name stay upright and are drawn over everything else of this node.
	_gauges = DrawCache.new()
	_gauges.name = "Gauges"
	_gauges.draw.connect(_draw_gauges_layer)
	add_child(_gauges)
	main_jet = _jet(Color(1.0, 0.85, 0.6))
	port_jet = _jet(Palette.SIDE_JET)
	star_jet = _jet(Palette.SIDE_JET)


## Make one flame emitter in colour `col`: 24 dots that live 0.35 s and fade
## out. It is "top level", so it ignores our turning and we place it in
## world coordinates ourselves.
func _jet(col: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	# How many dots, how long they live, how they fly.
	p.amount = JET_DOTS
	p.lifetime = 0.35
	p.local_coords = false
	p.emitting = false
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	# Fade from 90% to fully see-through over each dot's life.
	var grad := Gradient.new()
	grad.set_color(0, Palette.with_alpha(col, 0.9))
	grad.set_color(1, Palette.with_alpha(col, 0.0))
	p.color_ramp = grad
	p.top_level = true
	add_child(p)
	return p


## Every frame: counter-rotate, refresh the flames, tell the kept pictures (hull,
## shield arcs, bars) what they should look like, and ask for a redraw of this node's
## own picture only while it has something that changes by the frame: the heads of
## the turning guns, a Bomber's torpedo run or the human's drift arrow. (Test only:
## with DrawParts.redraw off we ask for a redraw just until the first picture is
## drawn; Godot keeps that picture.)
func _process(_dt: float) -> void:
	if ship == null or not ship.alive:
		return
	rotation = -ship.rotation
	# A ship nobody can see (the fog hides it) needs no update: it is brought up to date on the
	# first frame it shows again (a gun's kick starts over after a gap, see GunKick).
	if not is_visible_in_tree():
		return
	# Nor is one far from the camera's view (see ViewCull): it is brought up to date on the first
	# frame it comes near.
	if not ViewCull.near(get_viewport(), ship.global_position, ship.radius + 900.0):
		return
	is_human = ship.profile != null and ship.profile.is_human
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	_update_jets(z)
	_update_hull(z)
	_update_shield(z)
	_update_gauges(z)
	var live := _wants_live(z)
	if not _drawn or (DrawParts.redraw and (live or _live_drawn)):
		queue_redraw()
	_live_drawn = live


## Does this ship have something to draw on this node's own picture that changes from
## frame to frame (and so needs a new drawing every frame)? That is the heads of its
## turning guns (when the ship is big enough on the screen to show them), a torpedo
## run's fan and the human's drift arrow.
func _wants_live(z: float) -> bool:
	if is_human or ship.run_mount != null:
		return true
	if not TurretPaint.is_on():
		return false
	if ship.mounts.size() != _mounts_n or not is_same(ship.mounts, _mounts_seen):
		_mounts_seen = ship.mounts
		_mounts_n = ship.mounts.size()
		_has_heads = false
		for m: WeaponMount in ship.mounts:
			if m.mount_type != WeaponMount.FIXED:
				_has_heads = true
				break
	return _has_heads and maxf(float(ship.def.get("length", 26.0)) * z, MIN_PX) >= TurretPaint.HIDE_SHIP_PX


## How much bigger than life to draw the ship (1 = true size) so it is at
## least MIN_PX screen pixels long at the current camera zoom.
func _scale() -> float:
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var length := float(ship.def.get("length", 26.0))
	return maxf(1.0, MIN_PX / maxf(0.001, length * z))


## Set up the main flame emitter for the engine nozzles `nozzle_list` (empty, or a
## single one: the one stream every ship had; two or more: the stream of each
## nozzle of a big hull). It works out the round of starting places and changes how
## many dots the emitter holds (EngineStreams.dots()), and only when the nozzles
## change, which is once for a ship. It makes no emitter and does not change the
## emitter's way of starting dots (always from one point).
func set_streams(nozzle_list: Array) -> void:
	var n := nozzle_list.size() if nozzle_list.size() >= 2 else 1
	if n == _streams and (n == 1 or is_same(nozzle_list, _nozzles)):
		return
	_streams = n
	_nozzles = nozzle_list if n >= 2 else []
	_plan = EngineStreams.plan(_nozzles) if n >= 2 else {}
	_hop = 0
	main_jet.amount = _dots(EngineStreams.dots(n))
	main_jet.spread = EngineStreams.FAN_DEG if n >= 2 else 12.0


## How many dots an emitter that holds `full` dots at the close zooms holds now: all of
## them close up, half of them (at least FEWEST_DOTS) at the usual play zoom and further
## out, where the dots are a pixel or two each and half as many read the same.
func _dots(full: int) -> int:
	return full if _dot_share >= 1.0 else maxi(FEWEST_DOTS, int(float(full) * _dot_share))


## Place and switch the three flame emitters: the main flame at the tail
## (bigger and faster while boosting; a big hull's main flame is a stream from
## each of its engine nozzles), the side flames on each flank. (Test
## only: with DrawParts.flames off the emitters are parked instead, stopped and
## hidden, and none of the work below is done; they come back when it is on.)
func _update_jets(z: float) -> void:
	# Step 0: the test switch for the flames (normally on), and no flames at all far out
	# (the camera zoom under FAR_FLAMES_ZOOM: the dots are specks there).
	if not DrawParts.flames or z < FAR_FLAMES_ZOOM:
		if not _jets_hidden:
			_jets_hidden = true
			for j: CPUParticles2D in [main_jet, port_jet, star_jet]:
				j.emitting = false
				j.visible = false
		return
	if _jets_hidden:
		_jets_hidden = false
		for j: CPUParticles2D in [main_jet, port_jet, star_jet]:
			j.visible = true
	# Half the dots from the usual play zoom outward (see _dots()); all of them close up.
	var share := 1.0 if DrawCache.is_close(z) else PLAY_DOT_SHARE
	if share != _dot_share:
		_dot_share = share
		main_jet.amount = _dots(EngineStreams.dots(_streams))
		port_jet.amount = _dots(JET_DOTS)
		star_jet.amount = _dots(JET_DOTS)
	# A ship whose engines are all off and whose three emitters have stopped has nothing to place.
	if ship.thrust_main <= 0.1 and ship.thrust_port <= 0.1 and ship.thrust_star <= 0.1 and not (main_jet.emitting or port_jet.emitting or star_jet.emitting):
		return
	# In slow motion (WorldSpeed) the flames run at the world's speed too. At a
	# faster speed Godot has already scaled the frame time, so it counts as 1.
	var world_speed := minf(ship.world.speed.factor, 1.0) if ship.world != null else 1.0
	if world_speed != _jet_speed:
		_jet_speed = world_speed
		for j: CPUParticles2D in [main_jet, port_jet, star_jet]:
			j.speed_scale = world_speed
	# Zoom helpers: px = world units per screen pixel; k = drawing scale.
	var px := 1.0 / maxf(0.02, z)
	var k := _scale()
	var length := float(ship.def.get("length", 26.0)) * k
	var f := Vector2.from_angle(ship.rotation)
	var port := Util.port_of(ship.rotation)
	var g := ship.global_position
	# Where the flames start: the main flame behind the middle (45% of the
	# length), the side flames 25% of the length out to each side.
	var main_at := g - f * length * 0.45
	var side := port * length * 0.25
	var side_shift := Vector2.ZERO
	# How big the flames are: 1 = Aurelian's size. Their dots and their speed
	# are both multiplied by it, so a plume shrinks the same way in length and
	# width (a dot's distance is its speed times its fixed life).
	var jet_size := 1.0
	# Both teams' hulls have their engines in places of their own: the flames
	# follow them (each hull's own points, in its 36-unit design space). Cinder's
	# flames also get their own colours the first time we see a Cinder ship, and
	# are a quarter smaller (CINDER_JET_SIZE).
	var jets: Array = []
	if CinderPaint.alien(ship.team):
		if not _tinted:
			_tinted = true
			CinderPaint.tint_jets(main_jet, port_jet, star_jet)
		jets = CinderPaint.jets(ship.hull_id)
		jet_size = CINDER_JET_SIZE
	elif AurelianPaint.on(ship.team):
		jets = AurelianPaint.jets(ship.hull_id)
	var un := length / 36.0
	if not jets.is_empty():
		var main_spot: Vector2 = jets[0]
		var side_spot: Vector2 = jets[1]
		main_at = g + f * (main_spot.x * un) - port * (main_spot.y * un)
		side = port * (side_spot.y * un)
		side_shift = f * (side_spot.x * un)
	# A big hull (EngineStreams) has several engine nozzles and the main flame is a
	# stream from each. It is still the one emitter, starting its dots from one point,
	# and each frame that point moves to the next nozzle of a fixed round (a nozzle's
	# share of the round is by its radius, and a smaller nozzle's dots start slower, so
	# its stream is shorter). So no emitter is made and nothing takes a number from the
	# match's dice rolls. A ship with no nozzle list keeps its one stream.
	set_streams(EngineStreams.nozzles(ship.team, ship.hull_id))
	# The one stream's speed and dot size (in screen pixels, so the same on every ship), or
	# a big hull's: sized to its nozzles (EngineStreams.speed_range() and dot_range()).
	var speeds := Vector2((90.0 if not ship.boosting else 180.0) * px * 0.4 * jet_size, (150.0 if not ship.boosting else 260.0) * px * 0.4 * jet_size)
	var dots := Vector2(2.0 * px * jet_size, 3.5 * px * (1.5 if ship.boosting else 1.0) * jet_size)
	if _streams >= 2:
		main_at = g + EngineStreams.spot(_nozzles, _plan, _hop, un, f, port, EngineStreams.back(ship.team))
		speeds = EngineStreams.speed_range(_plan, _hop, un, px, ship.boosting, jet_size)
		dots = EngineStreams.dot_range(_plan, un, px, ship.boosting, jet_size)
		_hop += 1
	# Main engine: behind the ship, blowing backwards (against the way the
	# engines push, which a ship of the line swivels: Ship.swivel).
	main_jet.global_position = main_at
	main_jet.direction = -Vector2.from_angle(ship.rotation + ship.swivel)
	main_jet.emitting = ship.thrust_main > 0.1
	main_jet.initial_velocity_min = speeds.x
	main_jet.initial_velocity_max = speeds.y
	main_jet.scale_amount_min = dots.x
	main_jet.scale_amount_max = dots.y
	# Port thrust pushes the hull to port, so its exhaust vents starboard.
	port_jet.global_position = g - side + side_shift
	port_jet.direction = -port
	port_jet.emitting = ship.thrust_port > 0.1
	star_jet.global_position = g + side + side_shift
	star_jet.direction = port
	star_jet.emitting = ship.thrust_star > 0.1
	# Both side flames: smaller and slower than the main one.
	for j: CPUParticles2D in [port_jet, star_jet]:
		j.initial_velocity_min = 60.0 * px * 0.4 * jet_size
		j.initial_velocity_max = 100.0 * px * 0.4 * jet_size
		j.scale_amount_min = 1.5 * px * jet_size
		j.scale_amount_max = 2.5 * px * jet_size


## Draw the ship (Godot calls this after queue_redraw()). The drift arrow is
## only for the human's own ship, at any zoom; the bars and the name also show
## on other ships when zoomed in close enough. (Test only: DrawParts can leave
## out the shield arcs, the arrow, the bars, the name and the hull outline;
## each is drawn as always when its switch is on.)
func _draw() -> void:
	if ship == null or not ship.alive:
		return
	_drawn = true
	# Zoom helpers: z = camera zoom (bigger = closer), px = world units per
	# screen pixel, k = drawing scale, u = shape scale.
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var px := 1.0 / maxf(0.02, z)
	var k := _scale()
	var length := float(ship.def.get("length", 26.0))
	var u := length * k / 36.0
	var rot := ship.rotation
	# The hull, the shield arcs and the bars are not drawn here but on their kept
	# pictures. While the game is paused _process() does not run, so the camera asks
	# for this redraw and the kept pictures are brought up to date from here.
	if get_tree().paused:
		_update_hull(z)
		_update_shield(z)
		_update_gauges(z)
	# The guns that turn, as small turrets on the hull (a fixed gun gets none).
	TurretPaint.draw_mounts(self, ship, k, u, px, rot, _kicks)
	# A Bomber's torpedo run: the fan of lines and the bar (RunPaint).
	if ship.run_mount != null:
		var sr := maxf(length * k * 0.62, ship.radius * 1.3)
		RunPaint.draw(self, ship, px, sr + 8.0 * px, maxf(34.0 * px, minf(140.0 * px, length * k * 0.9)), is_human)
	# Velocity arrow: only on the ship the human flies, at any zoom.
	if DrawParts.arrow and is_human:
		_velocity_arrow(px)


## The ship's shape at scale `u`, turned to `rot`: filled and outlined in the
## team colour (Palette.ACE while "ace"; thicker for the human). A hit shows on
## the outline, not on the fill: for a moment after it the line turns toward
## white and gets thicker (Palette.hit_edge, Palette.hit_width). A Cinder ship
## is drawn by CinderPaint instead: a dark bladed hull with the same outline
## rules, glowing veins and engine lights (its engines glow harder the harder
## they burn). (Test only: the outline is left out when DrawParts.outline is
## off, and the hit flash with it; the fill stays.)
func _draw_hull(ci: CanvasItem, u: float, rot: float, col: Color, px: float) -> void:
	var edge := Palette.ACE if ship.ace_t > 0.0 else col
	var edge_w := 2.2 if is_human else 1.4
	# The hit flash strength (0 = not hit just now).
	var hit := Palette.HIT_FLASH if ship.flash > 0.0 else 0.0
	# How hot the engines glow, 0..1.
	var heat := _heat()
	if CinderPaint.alien(ship.team):
		CinderPaint.draw_shape(ci, CinderPaint.hull(ship.hull_id), Vector2(u, u), rot, px, edge, edge_w, hit, heat, float(ship.uid) * 1.7)
		return
	if AurelianPaint.on(ship.team):
		# The nose guns of the amber hulls kick back too (they are part of the hull's picture).
		var nose_age := _kicks.fixed_age
		AurelianPaint.draw_shape(ci, AurelianPaint.hull(ship.hull_id), u, rot, px, edge, edge_w, hit, heat, 1.0, GunKick.fixed_back(_kicks.fixed_weapon, nose_age), GunKick.is_flash(nose_age))
		return
	var pts := PackedVector2Array()
	for p: Vector2 in HULLS.get(ship.hull_id, HULLS["fighter"]):
		pts.append((p * u).rotated(rot))
	ci.draw_colored_polygon(pts, Palette.HULL_FILL)
	if DrawParts.outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		if hit > 0.0:
			edge = Palette.hit_edge(edge, hit)
			edge_w = Palette.hit_width(edge_w, hit)
		ci.draw_polyline(closed, edge, edge_w * px, true)


## How hot the engines glow, 0..1: a low glow at rest, more with the main engine's
## push, and more again while boosting.
func _heat() -> float:
	return clampf(0.35 + 0.65 * ship.thrust_main + (0.3 if ship.boosting else 0.0), 0.0, 1.0)


## Tell the hull's kept picture what the hull looks like now (once a frame, `z` is
## the camera zoom), so it is drawn again only when that changed (see DrawCache). The
## picture depends on: whether the hull is hit, ace or the human's, which look is on,
## how hot the engines glow (in steps of 1/8), the veins' pulse (a big Cinder hull),
## how far the nose guns are kicked back and whether they flash, the camera zoom (in
## steps of 2%, and whether it is a close one: DrawCache.is_close()) and the test switches of DrawParts. It also lets the ship's GunKick
## look at the guns once a frame, which has to happen on every frame (a shot is seen
## as a jump of a gun's cooldown), and turns the kept pictures with the ship.
func _update_hull(z: float) -> void:
	_spin.rotation = ship.rotation
	_kicks.look_all(ship.mounts, ship.world.time if ship.world != null else 0.0)
	var nose_age := _kicks.fixed_age
	var bits := (1 if ship.ace_t > 0.0 else 0) | (2 if is_human else 0) | (4 if ship.flash > 0.0 else 0)
	bits |= (8 if CinderPaint.alien(ship.team) else 0) | (16 if AurelianPaint.on(ship.team) else 0) | (32 if GunKick.is_flash(nose_age) else 0)
	bits |= (int(_heat() * 8.0) << 6) | (DrawParts.version << 28) | ((1 << 26) if DrawCache.is_close(z) else 0)
	if _pulses:
		bits |= CinderPaint.pulse_step(float(ship.uid) * 1.7) << 20
	_hull.want(ship.hull_id, DrawCache.STATE_BASE, bits, GunKick.fixed_back(_kicks.fixed_weapon, nose_age), z)


## Tell the shield arcs' kept picture what the arcs look like now (see ShieldArcs.key()).
func _update_shield(z: float) -> void:
	var sh := ship.shields
	if sh.max_total != _caps_total or sh.focus != _caps_focus:
		_caps_total = sh.max_total
		_caps_focus = sh.focus
		for zone in 4:
			_caps[zone] = sh.cap(zone)
	_shield.want(ship.hull_id, DrawCache.STATE_BASE, ShieldArcs.key(sh, _caps, z) | (DrawParts.version << 28), 0.0, z)


## Tell the bars' kept picture what the bars and the name look like now: nothing at all
## when they are not shown (too far out), else the hull and shield fill in 64ths and
## whether the name is shown (the name itself in `detail`, as a number).
func _update_gauges(z: float) -> void:
	var bits := 0
	var detail := 0.0
	if (DrawParts.bars or DrawParts.name_tag) and (is_human or z > 0.3):
		bits = 1 | (int(ship.hull_frac() * 64.0) << 1) | (int(ship.shields.fraction() * 64.0) << 8) | (DrawParts.version << 28)
		if is_human or z > 0.45:
			bits |= (1 << 16) | ((1 << 17) if is_human else 0)
			detail = float(ship.display_name.hash() & 0xFFFFFF)
	_gauges.want(ship.hull_id, DrawCache.STATE_BASE, bits, detail, z)


## Draw the hull on its kept picture (the `draw` signal of _hull): the ship pointing
## along +x, because the picture turns with the ship, at the camera zoom of now.
func _draw_hull_layer() -> void:
	if ship == null or not ship.alive:
		return
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	_hull.drawn_at(z)
	var px := 1.0 / maxf(0.02, z)
	var u := float(ship.def.get("length", 26.0)) * _scale() / 36.0
	# A big Cinder hull has veins that pulse: its picture is drawn again at each pulse step.
	_pulses = CinderPaint.alien(ship.team) and CinderPaint.has_pulse(CinderPaint.hull(ship.hull_id), u, px)
	_draw_hull(_hull, u, 0.0, Palette.team(ship.team), px)


## The radius of the ring the shield arcs sit on, and the bars sit above: 62% of the
## drawn length, at least 1.3 times the ship's radius.
func _ring_radius(z: float) -> float:
	var length := float(ship.def.get("length", 26.0))
	return maxf(length * _scale() * 0.62, ship.radius * 1.3)


## Draw the four shield arcs on their kept picture (the `draw` signal of _shield): the
## ship pointing along +x, because the picture turns with the ship. Which look the arcs
## get depends on the zoom (ShieldArcs).
func _draw_shield_layer() -> void:
	if ship == null or not ship.alive:
		return
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	_shield.drawn_at(z)
	if DrawParts.arcs:
		ShieldArcs.draw(_shield, ship.shields, _ring_radius(z), 1.0 / maxf(0.02, z), z)


## Draw the hull bar, the shield bar and the name on their kept picture (the `draw`
## signal of _gauges), when they are shown at the zoom of now.
func _draw_gauges_layer() -> void:
	if ship == null or not ship.alive:
		return
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	_gauges.drawn_at(z)
	if (DrawParts.bars or DrawParts.name_tag) and (is_human or z > 0.3):
		_draw_bars_and_name(_gauges, _ring_radius(z), float(ship.def.get("length", 26.0)) * _scale(), Palette.team(ship.team), 1.0 / maxf(0.02, z), z)


## The hull bar (team colour), the thin shield bar above it, and (when
## close enough, or for the human) the name above them, drawn on `ci`. `drawn_len` is
## the ship's drawn length; the bars sit just above the shield ring `sr`. (Test
## only: DrawParts.bars and DrawParts.name_tag can each leave their part out.)
func _draw_bars_and_name(ci: CanvasItem, sr: float, drawn_len: float, col: Color, px: float, z: float) -> void:
	var bw := maxf(34.0 * px, minf(140.0 * px, drawn_len * 0.9))
	var by := -sr - 10.0 * px
	if DrawParts.bars:
		ci.draw_rect(Rect2(-bw / 2.0, by, bw, 3.0 * px), Palette.with_alpha(Palette.VOID, 0.75))
		ci.draw_rect(Rect2(-bw / 2.0, by, bw * ship.hull_frac(), 3.0 * px), col)
		ci.draw_rect(Rect2(-bw / 2.0, by - 4.0 * px, bw * ship.shields.fraction(), 2.0 * px), Palette.SHIELD)
	if DrawParts.name_tag and (is_human or z > 0.45):
		var font := ThemeDB.fallback_font
		var label := "YOU" if is_human else ship.display_name.to_upper()
		ci.draw_string(font, Vector2(-60.0 * px, by - 8.0 * px), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * px, int(11.0 * px), Palette.ICE if is_human else Palette.NEUTRAL)

## An arrow showing which way and how fast the ship drifts (its velocity),
## up to 1.45x its top-speed length. Over top speed (by more than 4%) it
## turns the Palette.ACE colour. When the nose points away from the drift, a small "slip" line
## joins the two directions. Only the human's own ship gets one (_draw() asks).
func _velocity_arrow(px: float) -> void:
	var v := ship.velocity
	var sp := v.length()
	if sp < 12.0:
		return
	# Arrow length and colour.
	var cap := maxf(80.0, ship.f_max)
	var length := minf(1.45, sp / cap) * 80.0 * px
	var n := v / sp
	var over := sp > cap * 1.04
	var col := Palette.ACE if over else Palette.with_alpha(Palette.ICE, 0.9)
	# The line and its triangle tip.
	var tip := n * length
	draw_line(Vector2.ZERO, tip, col, 2.0 * px, true)
	var perp := Vector2(-n.y, n.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - n * 7.0 * px + perp * 4.0 * px, tip - n * 7.0 * px - perp * 4.0 * px]), col)
	# Nose-vs-velocity slip tick.
	var f := Vector2.from_angle(ship.rotation)
	if absf(f.angle_to(n)) > 0.18 and sp > 40.0:
		draw_line(f * 18.0 * px, n * 18.0 * px, Palette.with_alpha(Palette.VEIL, 0.8), 1.0 * px)
