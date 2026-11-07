class_name CommandOverlayDraw
extends RefCounted
## WHAT THIS IS: the drawing half of CommandOverlay (the Admiral's map
## tools): what those tools paint on the map.
##
## HOW IT WORKS: CommandOverlay._draw() calls draw(overlay) every frame.
## It paints, in this order:
##   1. for everyone on a team: the rally waypoint (a ring, a cross and
##      "Rally point (Ns)" with the seconds it has left);
##   (in the command pause the human's waiting Move and Hold orders are drawn as dotted lines tagged "on resume")
##   2. for the Admiral only: our repair bays' healing range, a ring
##      around each selected squadron, the mothership's ring, a dashed hover ring and the box being dragged;
##   3. while a tool is armed: a preview at the mouse, a ring as big as
##      what the tool covers, green (repair colour) where it is allowed
##      and in the danger colour with the danger triangle where it isn't, with the reason or the instruction.
## Everything is drawn in world positions. To keep lines and text the same
## size on screen whatever the camera zoom, sizes are multiplied by `px`:
## how many world units one screen pixel covers right now (1 / zoom).
## This is a "static library": plain functions with no state of their own.
## As a part of CommandOverlay it reads the overlay's own fields directly.
##
## WHO USES IT: only CommandOverlay._draw().


## Draw everything (see HOW IT WORKS). The draw_* calls go to `ov`, the
## overlay being drawn.
static func draw(ov: CommandOverlay) -> void:
	var world := ov.world
	if world == null:
		return
	var z := world.camera.zoom.x
	var px := 1.0 / maxf(0.0001, z)
	var vt := world.viewer_team
	# 1. The team waypoint (everyone on the team sees it).
	if vt >= 0 and world.teams[vt].has_waypoint():
		_draw_waypoint(ov, vt, px)
	# 1b. The marks that feature modules add (Barrage circle, bounty
	# diamonds, Fortify shimmer ...); nothing in today's game.
	if not world.command.marks.is_empty():
		CommandOrders.draw_marks(ov, vt, px)
	if not ov.is_admiral():
		return
	# 2. The Admiral's own marks.
	_draw_admiral_marks(ov, px)
	if ov.tool == "":
		return
	# 3. The armed tool's preview at the mouse.
	_draw_tool_preview(ov, px)


## The rally waypoint of team `vt`: a faint ring as big as its area, a
## cross 120 world units wide, and its label with the seconds left, all in the
## interface's highlight colour (amber, or red when the human plays Vhorr).
static func _draw_waypoint(ov: CommandOverlay, vt: int, px: float) -> void:
	var world := ov.world
	var wp := world.teams[vt].waypoint
	var hi := UiKit.accent()
	ov.draw_arc(wp, Rules.WAYPOINT_RADIUS, 0.0, TAU, 64, Palette.with_alpha(hi, 0.55), 2.0 * px, true)
	ov.draw_line(wp + Vector2(-60, 0), wp + Vector2(60, 0), hi, 2.0 * px)
	ov.draw_line(wp + Vector2(0, -60), wp + Vector2(0, 60), hi, 2.0 * px)
	_label(ov, wp + Vector2(0, -Rules.WAYPOINT_RADIUS - 30.0 * px), "Rally point (%ds)" % int(world.teams[vt].waypoint_until - world.time), hi, px)


## The Admiral's marks: our live repair bays' healing range (so the
## Admiral can plan where ships get healed), a thin ice ring around each
## selected squadron (and our mothership), a dashed ring on the squadron
## under the pointer, and the dashed selection box while dragging.
static func _draw_admiral_marks(ov: CommandOverlay, px: float) -> void:
	var world := ov.world
	for b: RepairBay in world.bays:
		if b.team == ov.team and b.alive:
			ov.draw_arc(b.global_position, float(Structures.REPAIR_BAY["range"]), 0.0, TAU, 48, Palette.with_alpha(Palette.REPAIR, 0.25), 1.5 * px, true)
	# Selected squadrons: one ring each around all its ships.
	for id in ov.sel_squads:
		_ring(ov, world.squads.get(id), px, false)
	if ov.sel_base:
		var ms := world.mothership(ov.team)
		if ms != null and is_instance_valid(ms):
			ov.draw_arc(ms.global_position, float(Structures.MOTHERSHIP["length"]) * 0.5 + 24.0 * px, 0.0, TAU, 48, Palette.ICE, 1.5 * px, true)
	if ov.hover_squad >= 0 and not ov.sel_squads.has(ov.hover_squad):
		_ring(ov, world.squads.get(ov.hover_squad), px, true)
	# Orders given in the command pause wait in the queue (they run on the first tick after the pause): a dotted line from each
	# squadron to its point, tagged "on resume".
	if ov.get_tree().paused:
		_draw_pending(ov, px)
	# The drag box: a faint fill and a dashed outline.
	if ov._drag_from != Vector2.INF:
		var r := Rect2(ov._drag_from, Vector2.ZERO).expand(ov._drag_to)
		ov.draw_rect(r, Palette.with_alpha(Palette.ICE, 0.08))
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			ov.draw_dashed_line(corners[i], corners[(i + 1) % 4], Palette.ICE, 1.5 * px, 8.0 * px)


## The human's Move and Hold orders of our team that wait in the order queue (an order given in the command pause is stamped
## for the next tick): a dotted line from each squadron's centre to the point, and "on resume" there.
static func _draw_pending(ov: CommandOverlay, px: float) -> void:
	var world := ov.world
	for o: Dictionary in world.orders.queue:
		if not bool(o.get("human", false)) or int(o["team"]) != ov.team or int(o["apply_tick"]) <= world.tick_count:
			continue
		if str(o["kind"]) != OrderKinds.MOVE and str(o["kind"]) != OrderKinds.HOLD:
			continue
		var to: Variant = o["target"]
		if not (to is Vector2i or to is Vector2):
			continue
		var point := Vector2(to)
		for sid in o["subjects"]:
			var rec: Squad = world.squads.get(int(sid))
			if rec != null:
				ov.draw_dashed_line(RtsSelect.centre_of(world, rec), point, Palette.with_alpha(Palette.ICE, 0.8), 1.5 * px, 3.0 * px)
		ov.draw_circle(point, 4.0 * px, Palette.ICE)
		_label(ov, point + Vector2(0.0, -14.0 * px), "on resume", Palette.ICE, px)


## A ring around squad record `rec` (a Squad or null): about all its ships, 10 screen pixels clear of the farthest
## hull. `dashed` draws it as short arcs with gaps (the hover look); else one thin ice line.
static func _ring(ov: CommandOverlay, rec: Variant, px: float, dashed: bool) -> void:
	if rec == null:
		return
	var squad := rec as Squad
	var c := RtsSelect.centre_of(ov.world, squad)
	var rad := RtsSelect.reach_of(ov.world, squad, c) + 10.0 * px
	if not dashed:
		ov.draw_arc(c, rad, 0.0, TAU, 40, Palette.ICE, 1.5 * px, true)
		return
	var steps := 12
	for i in steps:
		var a0 := TAU * float(i) / float(steps)
		ov.draw_arc(c, rad, a0, a0 + TAU / float(steps) * 0.55, 6, Palette.with_alpha(Palette.ICE, 0.8), 1.5 * px, true)


## The armed tool's preview at the mouse: a ring as big as the area the
## tool covers (default 300 world units), a dot, and a label: the reason
## it can't go here (red), or the tool's instruction (green).
static func _draw_tool_preview(ov: CommandOverlay, px: float) -> void:
	var world := ov.world
	var p := ov.get_global_mouse_position()
	var b := ov.blocker_at(p)
	var col := Palette.REPAIR if b == "" else Palette.DANGER
	# The ring's size: a bay's healing range, a ward's sight (40% more
	# with the ward upgrade), the waypoint's area, or half the mothership.
	var rad := 300.0
	match ov.tool:
		"bay":
			rad = float(Structures.REPAIR_BAY["range"])
		"ward":
			rad = float(Structures.WARD["vision"]) * (1.4 if world.teams[ov.team].ward_upgrade else 1.0)
		"waypoint":
			rad = Rules.WAYPOINT_RADIUS
		"move":
			rad = float(Structures.MOTHERSHIP["length"]) * 0.5
		_:
			# An order that a feature module added (CommandOrders).
			rad = CommandOrders.radius(world, ov.tool)
	ov.draw_arc(p, rad, 0.0, TAU, 64, Palette.with_alpha(col, 0.8), 2.0 * px, true)
	ov.draw_circle(p, 6.0 * px, col)
	# A refused spot also carries the danger triangle (colour is never the only sign); a verb prints its name first.
	var words := b if b != "" else ov.tool_text()
	if ov.verb_label() != "":
		words = "%s: %s" % [ov.verb_label(), words]
	if b != "":
		Glyphs.danger(ov, p + Vector2(0, -22.0 * px), Glyphs.SIDE * px)
	_label(ov, p + Vector2(0, 26.0 * px), words, col, px)


## Draw text `t` centred on world point `p`, in colour `col` with a dark
## shadow 1 pixel down-right. The text is scaled by `px` so it is always
## 14 screen pixels tall, whatever the zoom; draw_set_transform moves and
## scales everything drawn after it, so we reset it at the end.
static func _label(ov: CommandOverlay, p: Vector2, t: String, col: Color, px: float) -> void:
	ov.draw_set_transform(p, 0.0, Vector2(px, px))
	var w := ov._font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ov.draw_string(ov._font, Vector2(-w * 0.5 + 1.0, 1.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.VOID)
	ov.draw_string(ov._font, Vector2(-w * 0.5, 0.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	ov.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
