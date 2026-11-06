class_name UnitVisual
extends Node2D
## WHAT THIS IS: the "painter" for every unit that is not a pilot ship:
## minions, mining and repair drones, wards, turrets, defense posts, repair bays, derelict
## camps, snub fighters and the mothership. It changes nothing in the game;
## it only draws. (Pilot ships have their own painter, ShipVisual.)
##
## HOW IT WORKS:
##   - It is the "Visual" child node in each of those units' scenes
##     (scenes/entities/*.tscn). Each frame, _process() asks Godot to redraw;
##     Godot then calls _draw(), which picks a drawing function by the
##     unit's kind (Unit.K_*).
##   - Like ShipVisual, it turns itself back against the unit's turning
##     ("counter-rotates"), so bars and text stay upright; shapes are turned
##     by hand.
##   - A minion is not drawn again every frame. Its body is a kept picture (DrawCache) on
##     a "Spin" node that turns with it (so the picture is drawn with the minion pointing
##     along +x), and its hull bar a second, upright one; _update_body() tells them
##     once a frame what the minion looks like now, and each is drawn again only when
##     the hit flash, the pulse of its veins, how hurt it is or the camera zoom (by 2%)
##     changed. A minion asks for no redraw of this node's own picture at all. A lane tower,
##     a repair bay and a mothership keep their bodies on a kept picture too (the tower faded
##     while it is built, the mothership's alien gun dots with it); their guns' heads, bars,
##     rings, lines and texts change by the frame and are drawn on this node's own picture.
##     A unit the fog hides, or one far from the camera's view (ViewCull), is not brought up to date until it shows or comes near again.
##   - Lines are multiplied by `px` (world units per screen pixel) so they
##     keep the same thickness on screen at any zoom, and small units are
##     never drawn smaller than a few screen pixels.
##   - The lane minions of both teams are drawn plain and solid, so they are
##     never taken for pilot ships: Aurelian's are flat-tailed plates from
##     MinionShapes (the Aurelian hull steel with the team colour mixed in, a
##     bold outline), with flat paint marks on them once one drawing unit is big
##     enough on the screen (_draw_minion_plate()); Cinder's are smooth shells
##     with no blades (CinderShapes.MINIONS,
##     with a solid body tint).
##   - Cinder (the red team) wears an alien look: its minions, drones, wards
##     and mothership are drawn by CinderPaint from the tables in CinderShapes
##     (dark, bladed shapes with glowing veins) in the same size as the plain
##     outlines below. Bars, rings, beams and the other extras are drawn as
##     before. The Scum (the jungle's derelict camps and the snub fighters they launch) are
##     drawn by ScumPaint in their own gunmetal-and-rust look, from the tables in ScumShapes, with
##     a jury-rigged TurretPaint head on each gun of a den ship.
##   - The lane towers (point defense and torpedo), the Repair Bay and the
##     Aurelian mothership are drawn by AurelianPaint from the tables in
##     StructureShapes, for both teams: the towers and the bay in the Aurelian
##     steel dress or the Vhorr dress (Cinder's colours and thorns), the mothership
##     in steel. TurretPaint draws the head of each of their guns on top (the
##     Cinder mothership keeps its citadel and its gun dots). When a gun fires, its
##     head kicks back and slides home (GunKick): _look_kicks() lets the unit's
##     GunKick read the guns' cooldowns each frame, and TurretPaint does the drawing.
##     The guns of minions, drones and wards are not drawn as separate pieces, so they do not kick.
##   - With --sim-only (Game.sim_only) it draws nothing at all: it hides
##     itself and does no per-frame work.
##   - Test only: the switches of DrawParts (--bench-off=...) can leave out the
##     hull outline (_poly(), _draw_minion_plate() for an Aurelian minion, the
##     mothership's line, CinderPaint), the bars (_bar()) and the every-frame
##     redraw, so a test can measure what they cost. With no switch given
##     everything is drawn as always.
##
## WHO USES IT: Godot runs it as part of the minion, mining_drone,
## repair_drone, ward, turret, repair_bay, derelict, snub_fighter and
## mothership scenes. It reads each unit's own fields (cargo, build timer,
## target, anchor...). CinderPaint draws the Cinder shapes and ScumPaint the Scum ones.
## DrawParts holds the test-only switches it reads.

## The mining drone's outline, nose pointing right (+x), 1 unit long (scaled by the
## unit's size). The lane minions have their own, MinionShapes.
const DRONE := [Vector2(1, 0), Vector2(0.3, 0.75), Vector2(-0.8, 0.6), Vector2(-0.8, -0.6), Vector2(0.3, -0.75)]
## The plain outline of the mothership, in world units for a ship 510 long and
## 140 wide (stretched to the real length and beam). Nothing is drawn with it any
## more; the hull gallery's size check keeps the Cinder citadel the size of it.
const MOTHER := [Vector2(260, 0), Vector2(80, 70), Vector2(-220, 48), Vector2(-180, 0), Vector2(-220, -48), Vector2(80, -70)]
## The plain mothership's engine block at the tail (same scale as MOTHER).
const MOTHER_ENGINE := [Vector2(-200, 0), Vector2(-250, 16), Vector2(-250, -16)]

## The unit we draw (our parent node).
var unit: Unit
## True once _draw() has drawn this unit at least once. With the test switch
## DrawParts.redraw off we ask for a new picture only until this is true.
var _drawn := false
## When each of the unit's guns last fired, as the painter has seen it (GunKick).
var _kicks := GunKick.new()
## The node the kept pictures hang on (null for the kinds of unit that have none). It
## turns with the unit, so a kept picture is drawn with the unit pointing along +x.
var _spin: Node2D
## True for a minion (it has kept pictures and no picture of its own).
var _is_minion := false
## The kept picture of a body (a minion's, or a tower's, repair bay's or mothership's;
## a child of _spin).
var _body: DrawCache
## The kept picture of a minion's hull bar (upright, drawn over this node).
var _gauge: DrawCache
## True while the body's kept picture has glowing veins that pulse, so the picture is
## drawn again at each step of the pulse.
var _pulses := false


## Find our unit. The mothership is drawn one layer lower (z_index -1) so
## the small ships around it are drawn on top. With --sim-only (Game.sim_only)
## nothing is ever drawn, so we hide ourselves and stop our per-frame work
## for good: the simulation never reads this node.
func _ready() -> void:
	unit = get_parent() as Unit
	if Game.sim_only:
		visible = false
		set_process(false)
		return
	DrawParts.read_options()
	if unit is Mothership:
		z_index = -1
	# A minion is drawn on kept pictures (see DrawCache), drawn again only when something
	# they show changes: its body on a node that turns with it, its hull bar upright. A tower,
	# a repair bay and a mothership keep their bodies the same way (their guns' heads, bars,
	# rings and lines change by the frame and stay on this node's own picture).
	if unit is Minion or unit is Turret or unit is RepairBay or unit is Mothership:
		_is_minion = unit is Minion
		_spin = Node2D.new()
		_spin.name = "Spin"
		_spin.show_behind_parent = true
		add_child(_spin)
		_body = DrawCache.new()
		_body.name = "Body"
		_body.draw.connect(_draw_body_layer)
		_spin.add_child(_body)
		if _is_minion:
			_gauge = DrawCache.new()
			_gauge.name = "Gauge"
			_gauge.draw.connect(_draw_gauge_layer)
			add_child(_gauge)


## Every frame: counter-rotate and ask for a redraw. A minion asks for none: it tells
## its kept pictures what it looks like now instead (_update_body()). (Test only: with
## DrawParts.redraw off we ask for a redraw just until the first picture is drawn;
## Godot keeps that picture.)
func _process(_dt: float) -> void:
	if unit == null or not unit.alive:
		return
	rotation = -unit.rotation
	if _body != null:
		# Nobody sees a unit the fog hides, so it is brought up to date when it shows again.
		if not is_visible_in_tree():
			return
		_update_body()
		if _is_minion:
			return
	# A unit far from the camera's view is not drawn again (its picture is brought up to date on
	# the first frame it comes near).
	if not ViewCull.near(get_viewport(), unit.global_position, _cull_margin()):
		return
	if DrawParts.redraw or not _drawn:
		queue_redraw()


## How far beyond the camera's view (world units) this unit's picture must still be kept up to
## date: its own size and a margin for the lines it draws away from itself (a tower's line to
## its target, a repair bay's line to its anchor, a drone's beam). A mothership draws a line to
## wherever it is going, so it is never left out.
func _cull_margin() -> float:
	match unit.kind:
		Unit.K_MOTHERSHIP:
			return 1.0e9
		Unit.K_TURRET:
			return unit.radius + 2600.0
		Unit.K_BAY:
			return unit.radius + 4000.0
		Unit.K_REPAIR_DRONE:
			return unit.radius + 1600.0
	return unit.radius + 700.0


## The camera zoom now (1 with no camera).
func _zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam != null else 1.0


## Tell a minion's kept pictures what it looks like now (once a frame), so each is drawn
## again only when that changed (see DrawCache). The body depends on the hit flash, which
## look is on, the pulse of its veins (a big Cinder minion), the camera zoom (in steps of
## 2%) and the test switches of DrawParts; the hull bar on how hurt the minion is (in 64ths).
func _update_body() -> void:
	_spin.rotation = unit.rotation
	var z := _zoom()
	var bits := (1 if unit.flash > 0.0 else 0) | (2 if CinderPaint.alien(unit.team) else 0) | (4 if DrawCache.is_close(z) else 0) | (DrawParts.version << 28)
	if _pulses:
		bits |= CinderPaint.pulse_step(0.0 if unit is Mothership else _phase()) << 8
	# A tower under construction is drawn faded; a finished one solid.
	if unit is Turret and (unit as Turret).is_built():
		bits |= 16
	_body.want(_body_id(), DrawCache.STATE_BASE, bits, 0.0, z)
	if not _is_minion:
		return
	var mtype := (unit as Minion).mtype
	var bar := 0
	if DrawParts.bars and 1.0 / maxf(0.02, z) < 3.0 and unit.hull < unit.hull_max:
		bar = 1 + int(unit.hull_frac() * 64.0)
	_gauge.want(mtype, DrawCache.STATE_BASE, bar | (DrawParts.version << 28), 0.0, z)


## Draw a minion's body on its kept picture (the `draw` signal of _body): the unit
## pointing along +x, because the picture turns with the minion.
func _draw_body_layer() -> void:
	if unit == null or not unit.alive:
		return
	var z := _zoom()
	_body.drawn_at(z)
	var px := 1.0 / maxf(0.02, z)
	var col := Palette.team(unit.team)
	if unit is Minion:
		var m := unit as Minion
		var size := maxf(m.radius * 1.3, 6.0 * px)
		if CinderPaint.alien(m.team):
			var rec := CinderPaint.minion(m.mtype)
			_pulses = CinderPaint.has_pulse(rec, size, px)
			CinderPaint.draw_shape(_body, rec, Vector2(size, size), 0.0, px, Palette.with_alpha(col, 0.85), 1.0, _flash(), 0.5, _phase())
		else:
			_pulses = false
			_draw_minion_plate(_body, m, size, col, px, 0.0)
	elif unit is Turret:
		_draw_turret_body(_body, px, col)
	elif unit is RepairBay:
		_draw_bay_body(_body, px, col)
	else:
		_draw_mothership_body(_body, px, col)


## The name of the kept body picture of this unit: the minion type, or the structure's
## drawing (and its dress, for the team that wears the Vhorr one).
func _body_id() -> String:
	if unit is Minion:
		return (unit as Minion).mtype
	var dress := "|vhorr" if unit.team == Rules.CINDER else ""
	if unit is Turret:
		return ("torp_tower" if (unit as Turret).ttype == "torp" else "pd_tower") + dress
	if unit is RepairBay:
		return "repair_bay" + dress
	return "mothership" + dress

## Draw a minion's hull bar on its kept picture (the `draw` signal of _gauge): only once
## it is damaged, and only when zoomed in enough (px below 3).
func _draw_gauge_layer() -> void:
	if unit == null or not unit.alive:
		return
	var z := _zoom()
	_gauge.drawn_at(z)
	var px := 1.0 / maxf(0.02, z)
	if px < 3.0 and unit.hull < unit.hull_max:
		var m := unit as Minion
		var size := maxf(m.radius * 1.3, 6.0 * px)
		_bar_on(_gauge, -size - 6.0 * px, maxf(20.0 * px, size * 2.0), unit.hull_frac(), Palette.team(m.team), px)


## World units per screen pixel at the current camera zoom (zoom limited
## to at least 0.02).
func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(0.02, cam.zoom.x if cam != null else 1.0)


## Draw `shape` (a list of corner points) scaled by `size` and turned with
## the unit: filled with `fill` and outlined in `edge`, `width` thick. A hit
## shows on the outline, not on the fill: for a moment after it the line turns
## toward white and gets thicker (Palette.hit_edge, Palette.hit_width). (Test
## only: the outline, and the hit flash with it, is left out when
## DrawParts.outline is off.)
func _poly(shape: Array, size: float, fill: Color, edge: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in shape:
		pts.append((p * size).rotated(unit.rotation))
	draw_colored_polygon(pts, fill)
	if DrawParts.outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		if unit.flash > 0.0:
			edge = Palette.hit_edge(edge, Palette.HIT_FLASH)
			width = Palette.hit_width(width, Palette.HIT_FLASH)
		draw_polyline(closed, edge, width, DrawCache.is_close_px(_px()))


## The hit flash strength of this unit: Palette.HIT_FLASH for the first moments
## after a hit, else 0. CinderPaint takes it as a number (how far its outline
## turns toward white and how much thicker it gets); the plain outlines do the
## same in _poly(). The fill never changes.
func _flash() -> float:
	return Palette.HIT_FLASH if unit.flash > 0.0 else 0.0


## Look at the guns `mounts` of this unit and note which have just fired (GunKick reads
## their cooldowns and changes nothing), then hand the result to TurretPaint so the heads
## of the guns can kick back.
func _look_kicks(mounts: Array) -> GunKick:
	_kicks.look_all(mounts, unit.world.time if unit.world != null else 0.0)
	return _kicks


## A number that is different for every unit (its id times 1.7), so the veins
## of different Cinder units do not all pulse at the same moment.
func _phase() -> float:
	return float(unit.uid) * 1.7


## A bar `w` wide at height `y`: a dark background and a `frac` (0..1)
## filled part in colour `col`. (Test only: nothing is drawn when DrawParts.bars
## is off.)
func _bar(y: float, w: float, frac: float, col: Color, px: float) -> void:
	_bar_on(self, y, w, frac, col, px)


## The same bar drawn on `ci` (a kept picture, or this node).
func _bar_on(ci: CanvasItem, y: float, w: float, frac: float, col: Color, px: float) -> void:
	if not DrawParts.bars:
		return
	ci.draw_rect(Rect2(-w / 2.0, y, w, 3.0 * px), Palette.with_alpha(Palette.VOID, 0.75))
	ci.draw_rect(Rect2(-w / 2.0, y, w * clampf(frac, 0.0, 1.0), 3.0 * px), col)


## Draw the unit (Godot calls this after queue_redraw()): work out the
## shared colours, then hand over to the drawing function for its kind.
func _draw() -> void:
	if unit == null or not unit.alive:
		return
	_drawn = true
	# A minion has no picture of its own here: its kept pictures are drawn instead. While
	# the game is paused _process() does not run, so the camera asks for this redraw and
	# the kept pictures are brought up to date from here.
	if _is_minion:
		if get_tree().paused:
			_update_body()
		return
	# A tower, bay or mothership: its body is on its kept picture; while the game is paused the
	# camera's redraw brings that picture up to date from here.
	if _body != null and get_tree().paused:
		_update_body()
	var px := _px()
	var col := Palette.team(unit.team)
	# The dark fill inside the plain unit shapes. A hit does not change it: only
	# the outline flashes (see _poly() and _flash()).
	var fill := Palette.HULL_FILL
	match unit.kind:
		Unit.K_MINING_DRONE:
			_draw_mining_drone(px, col, fill)
		Unit.K_REPAIR_DRONE:
			_draw_repair_drone(px)
		Unit.K_WARD:
			_draw_ward(px, col)
		Unit.K_TURRET:
			_draw_turret(px, col)
		Unit.K_POST:
			_draw_post(px, col)
		Unit.K_BAY:
			_draw_bay(px, col)
		Unit.K_MONSTER:
			_draw_derelict(px)
		Unit.K_SNUB:
			# A Scum Fighter: an engine bell with a needle welded to its front.
			ScumPaint.draw_fighter(self, unit as SnubFighter, px, _flash())
		Unit.K_MOTHERSHIP:
			_draw_mothership(px, col)


## An Aurelian minion `m` of drawing size `size` and team colour `col`, drawn on `ci`
## (its kept body picture) and turned to `rot`: its plate
## and marks from MinionShapes, drawn in this order, the last on top: the pods
## (parts outside the plate, under it) and their outlines, the plate's solid fill
## with the other marks in table order (only while one drawing unit is at least
## MinionShapes.MARKS_MIN_UNIT_PX screen pixels long), the one-pixel seams, and the
## plate's outline. The solid parts are meshes built once (MinionShapes.mesh())
## and drawn with one command each, turned and scaled to the minion; the outlines
## and seams are lines of a screen-pixel width, so they are drawn each frame. A hit
## shows on the outlines, as in _poly(). (Test only: the outlines, and the hit
## flash with them, are left out when DrawParts.outline is off.)
func _draw_minion_plate(ci: CanvasItem, m: Minion, size: float, col: Color, px: float, rot: float) -> void:
	var flash := _flash()
	# Smooth (antialiased) lines cost three drawing commands each; far out they are drawn plain.
	var smooth := DrawCache.is_close_px(px)
	var c := cos(rot) * size
	var s := sin(rot) * size
	var turn := Transform2D(Vector2(c, s), Vector2(-s, c), Vector2.ZERO)
	var pods := MinionShapes.mesh(m.mtype, col, MinionShapes.PART_PODS)
	if pods != null:
		ci.draw_mesh(pods, null, turn)
		if DrawParts.outline:
			var pod_edge := Palette.hit_edge(Palette.with_alpha(col, MinionShapes.POD_EDGE_ALPHA), flash)
			var pod_width := Palette.hit_width(MinionShapes.EDGE_PX * MinionShapes.POD_EDGE_MUL * px, flash)
			for pod: PackedVector2Array in MinionShapes.pod_outlines(m.mtype):
				ci.draw_polyline(turn * pod, pod_edge, pod_width, smooth)
	var marked := size / px >= MinionShapes.MARKS_MIN_UNIT_PX
	ci.draw_mesh(MinionShapes.mesh(m.mtype, col, MinionShapes.PART_MARKED if marked else MinionShapes.PART_PLATE), null, turn)
	if marked:
		for seam: PackedVector2Array in MinionShapes.line_marks(m.mtype):
			ci.draw_polyline(turn * seam, MinionShapes.mark_color("line", col), px)
	if DrawParts.outline:
		var edge := Palette.hit_edge(Palette.with_alpha(col, 0.95), flash)
		var width := Palette.hit_width(MinionShapes.EDGE_PX * px, flash)
		ci.draw_polyline(turn * MinionShapes.outline_closed(m.mtype), edge, width, smooth)


## A mining drone: its outline (a Cinder drone is a dark scarab with grabbing
## claws), an ore dot that grows with its cargo, and while mining a thin beam
## to the rock it is mining.
func _draw_mining_drone(px: float, col: Color, fill: Color) -> void:
	var d := unit as MiningDrone
	var size := maxf(d.radius * 1.2, 6.0 * px)
	if CinderPaint.alien(d.team):
		CinderPaint.draw_shape(self, CinderPaint.unit_shape("mining_drone"), Vector2(size, size), d.rotation, px, col, 1.2, _flash(), 0.5, _phase())
	else:
		_poly(DRONE, size, fill, col, 1.2 * px)
	if d.cargo > 1.0:
		draw_circle(Vector2.ZERO, size * 0.35 * (d.cargo / d.capacity), Palette.ORE)
	if d.state == "mine" and d.rock >= 0:
		var n := d.world.node_by_id(d.node_id)
		if n != null:
			draw_line(Vector2.ZERO, (n.ore_pos[d.rock] - d.global_position).rotated(0.0), Palette.with_alpha(col, 0.5), 1.0 * px)


## A repair drone: a green plus sign (on a Cinder drone: a small green plus
## on a dark spinning thorn star), and a line to the unit it is healing.
func _draw_repair_drone(px: float) -> void:
	var r := unit as RepairDrone
	var s := maxf(6.0, 4.0 * px)
	if CinderPaint.alien(r.team):
		CinderPaint.draw_shape(self, CinderPaint.unit_shape("repair_drone"), Vector2(s, s), r.rotation, px, Palette.CINDER, 1.0, _flash(), 0.5, _phase())
		draw_line(Vector2(-s * 0.5, 0), Vector2(s * 0.5, 0), Palette.REPAIR, 1.6 * px)
		draw_line(Vector2(0, -s * 0.5), Vector2(0, s * 0.5), Palette.REPAIR, 1.6 * px)
	else:
		draw_line(Vector2(-s, 0), Vector2(s, 0), Palette.REPAIR, 2.0 * px)
		draw_line(Vector2(0, -s), Vector2(0, s), Palette.REPAIR, 2.0 * px)
	if r.healing and r.target != null and is_instance_valid(r.target):
		draw_line(Vector2.ZERO, r.target.global_position - r.global_position, Palette.with_alpha(Palette.REPAIR, 0.6), 1.5 * px)


## A ward: a diamond (a Cinder ward is a dark thorn star with a glowing
## pupil), and once anchored a faint ring showing how far it sees.
func _draw_ward(px: float, col: Color) -> void:
	var w := unit as Ward
	var s := maxf(10.0, 5.0 * px)
	if CinderPaint.alien(w.team):
		CinderPaint.draw_shape(self, CinderPaint.unit_shape("ward"), Vector2(s, s), w.rotation, px, col, 1.2, _flash(), 0.8, _phase())
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)]), Palette.with_alpha(col, 0.8))
	if w.is_anchored():
		draw_arc(Vector2.ZERO, w.vision_radius, 0.0, TAU, 64, Palette.with_alpha(col, 0.12), 1.5 * px, true)


## A turret: a lane tower, faded while still being built, with its gun head on
## top (the head turns to the way it shoots), hull and shield bars, a line to
## what it is shooting, and a "BUILDING" countdown while unfinished. The point-defense
## tower is the "Anchor" (a hub with three legs, the stem leg toward its node) and
## the torpedo tower the "Rampart" (a wide bar across the lane with three fixed
## torpedo cells on each side); both teams use the same drawing, Cinder's in the
## Vhorr dress (StructureShapes, AurelianPaint).
func _draw_turret(px: float, col: Color) -> void:
	var t := unit as Turret
	var s := maxf(t.radius, 10.0 * px)
	# Body and head.
	var built_a := 1.0 if t.is_built() else 0.45
	var id := "torp_tower" if t.ttype == "torp" else "pd_tower"
	var u := s * 2.0 / 36.0
	# (The body is on the kept picture: _draw_turret_body().)
	TurretPaint.draw_unit_mounts(self, t.mounts, t.team, float(TurretShapes.HULL_TU[id]) * u, px, t.rotation, built_a, _look_kicks(t.mounts))
	# Bars.
	_bar(s + 6.0 * px, s * 2.4, t.hull_frac(), col, px)
	if t.shields != null:
		_bar(s + 11.0 * px, s * 2.4, t.shields.fraction(), Palette.SHIELD, px)
	# Aggro tether: who this turret is shooting (brighter for pilot ships).
	if t.target != null and is_instance_valid(t.target) and t.target.alive and t.is_built():
		var tc := Palette.CINDER if t.target.kind == Unit.K_SHIP else Palette.with_alpha(col, 0.35)
		draw_line(Vector2.ZERO, t.target.global_position - t.global_position, Palette.with_alpha(tc, 0.5), 1.5 * px)
	if not t.is_built():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-60.0 * px, -s - 8.0 * px), "BUILDING %ds" % int(ceil(t.build_left)), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * px, int(10.0 * px), col)


## A lane tower's body on `ci` (its kept picture), the tower pointing along +x: the Anchor
## or the Rampart, faded while still being built. The head of its gun is drawn by _draw_turret().
func _draw_turret_body(ci: CanvasItem, px: float, col: Color) -> void:
	var t := unit as Turret
	var s := maxf(t.radius, 10.0 * px)
	var built_a := 1.0 if t.is_built() else 0.45
	var id := "torp_tower" if t.ttype == "torp" else "pd_tower"
	var u := s * 2.0 / 36.0
	AurelianPaint.draw_shape(ci, AurelianPaint.structure(id, t.team == Rules.CINDER), u, 0.0, px, Palette.with_alpha(col, built_a), 2.0, _flash(), 0.5, built_a)


## A repair bay's body (the Clover) on `ci` (its kept picture), the bay pointing along +x.
func _draw_bay_body(ci: CanvasItem, px: float, col: Color) -> void:
	var b := unit as RepairBay
	var s := maxf(b.radius, 9.0 * px)
	var u := s * 2.0 / 36.0
	AurelianPaint.draw_shape(ci, AurelianPaint.structure("repair_bay", b.team == Rules.CINDER), u, 0.0, px, col, 1.6, _flash(), 0.5)


## A mothership's body on `ci` (its kept picture), the ship pointing along +x: the
## Slipway in steel, or the alien citadel (stretched to the real length and beam) with a
## dot for each gun. Its gun heads, bars and move line are drawn by _draw_mothership().
func _draw_mothership_body(ci: CanvasItem, px: float, col: Color) -> void:
	var ms := unit as Mothership
	var hit := Palette.HIT_FLASH_MOTHER if ms.flash > 0.0 else 0.0
	if CinderPaint.alien(ms.team):
		# The alien hull is drawn for a 1600 x 340 ship; stretch it to the real size.
		var stretch := Vector2(float(ms.def["length"]) / 1600.0, ms.beam / 340.0)
		_pulses = CinderPaint.has_pulse(CinderPaint.mothership(), stretch.x, px)
		CinderPaint.draw_shape(ci, CinderPaint.mothership(), stretch, 0.0, px, col, 3.0, hit, 0.7, 0.0)
		# Gun dots.
		for m in ms.mounts:
			ci.draw_circle(m.offset, 10.0, Palette.with_alpha(col, 0.7))
	else:
		var u := float(ms.def["length"]) / 36.0
		AurelianPaint.draw_shape(ci, AurelianPaint.structure("mothership", false), u, 0.0, px, col, 3.0, hit, 0.6)

## A lane defense post: a hexagonal plate in the team colour with a ring in the
## middle and five small launch pads on the side that faces down the lane (where
## its minions launch), faded and with a "REBUILDING" countdown while it is being
## built, and a hull bar. It has no gun, so nothing else is drawn.
func _draw_post(px: float, col: Color) -> void:
	var p := unit as DefensePost
	var s := maxf(p.radius, 10.0 * px)
	var a := 1.0 if p.is_built() else 0.45
	var hex: Array = []
	for i in 6:
		hex.append(Vector2.from_angle(PI / 6.0 + PI / 3.0 * float(i)))
	_poly(hex, s, Palette.with_alpha(Palette.HULL_FILL.lerp(col, 0.25), a), Palette.with_alpha(col, a), 2.5 * px)
	draw_arc(Vector2.ZERO, s * 0.5, 0.0, TAU, 24, Palette.with_alpha(col, a), 1.6 * px, true)
	for i in 5:
		draw_circle(Vector2(s * 0.78, (float(i) - 2.0) * s * 0.26).rotated(p.rotation), maxf(s * 0.07, 1.5 * px), Palette.with_alpha(col, a))
	_bar(s + 6.0 * px, s * 2.4, p.hull_frac(), col, px)
	if not p.is_built():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-70.0 * px, -s - 8.0 * px), "REBUILDING %ds" % int(ceil(p.build_left)), HORIZONTAL_ALIGNMENT_CENTER, 140.0 * px, int(10.0 * px), col)


## A repair bay: the "Clover", four berth pads with a green end each round a hub
## (the repair plus as a body; both teams, Cinder's in the Vhorr dress, StructureShapes
## and AurelianPaint), the head of its defense gun on the hub once Bay Defenses
## research gives it one, and a hull bar. Once anchored, a ring shows its repair
## range (fainter when it can't repair right now); before that, a faint line
## points to its `anchor` point.
func _draw_bay(px: float, col: Color) -> void:
	var b := unit as RepairBay
	var s := maxf(b.radius, 9.0 * px)
	var u := s * 2.0 / 36.0
	# (The body is on the kept picture: _draw_bay_body().)
	TurretPaint.draw_unit_mounts(self, b.mounts, b.team, float(TurretShapes.HULL_TU["repair_bay"]) * u, px, b.rotation, 1.0, _look_kicks(b.mounts))
	if b.is_anchored():
		draw_arc(Vector2.ZERO, float(Structures.REPAIR_BAY["range"]), 0.0, TAU, 64, Palette.with_alpha(Palette.REPAIR, 0.15 if b.can_repair() else 0.05), 2.0 * px, true)
	else:
		draw_line(Vector2.ZERO, b.anchor - b.global_position, Palette.with_alpha(col, 0.25), 1.0 * px)
	_bar(s + 6.0 * px, s * 2.4, b.hull_frac(), col, px)


## A Scum den ship (a "derelict" camp in the code): the Scum Raider, or the Scum Carrier for the
## Carrier camp (ScumPaint draws the hull, with a dark socket under each gun), the head of each of
## its guns on top (TurretPaint, in the Scum style: jury-rigged, and it kicks back when it fires),
## and a hull bar once damaged.
func _draw_derelict(px: float) -> void:
	var d := unit as Derelict
	var s := d.radius
	ScumPaint.draw_den_ship(self, d, px, _flash(), _phase())
	TurretPaint.draw_unit_mounts(self, d.mounts, d.team, s * ScumPaint.HEAD_FRACTION, px, d.rotation, 1.0, _look_kicks(d.mounts))
	if d.hull < d.hull_max:
		_bar(s + 8.0 * px, s * 2.0, d.hull_frac(), Palette.SCUM_EDGE, px)


## The mothership, with wide hull and shield bars and a line to where it is
## moving (if it has a move order). The Aurelian mothership is the "Slipway" (two
## parallel hulls with a dark slip between them, two cross-decks, a V prow, StructureShapes
## and AurelianPaint, drawn as long as its real length; its outline flashes for a
## moment after a hit, more gently than a ship's) with a socket under each of its 21
## gun spots and the head of every gun it has on top. The Cinder mothership is an
## alien citadel (CinderPaint, stretched to its real length and beam) with a dot for
## each gun; its engines are lights in the shape.
func _draw_mothership(px: float, col: Color) -> void:
	var ms := unit as Mothership
	# (The body, and the alien citadel's gun dots, are on the kept picture: _draw_mothership_body().)
	if not CinderPaint.alien(ms.team):
		var u := float(ms.def["length"]) / 36.0
		TurretPaint.draw_unit_mounts(self, ms.mounts, ms.team, float(TurretShapes.HULL_TU["mothership"]) * u, px, ms.rotation, 1.0, _look_kicks(ms.mounts))
	# Bars (900 world units wide) and the move line.
	var w := 900.0
	_bar(ms.beam * 0.5 + 40.0, w, ms.hull_frac(), col, px * 2.0)
	_bar(ms.beam * 0.5 + 40.0 + 9.0 * px, w, ms.shields.fraction(), Palette.SHIELD, px * 2.0)
	if ms.move_target != Vector2.INF:
		draw_line(Vector2.ZERO, ms.move_target - ms.global_position, Palette.with_alpha(col, 0.3), 2.0 * px)
