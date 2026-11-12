class_name Minimap
extends Control
## WHAT THIS IS: a small map of the whole battlefield in the bottom-right
## corner of the HUD. DESIGN.md A15.
##
## HOW IT WORKS: 5 times a second it redraws itself, layer by layer:
## lanes, derelict camps (once explored), resource nodes
## coloured by who holds them (with a dot per turret), the map's cover
## patches (gas clouds, hidden pockets: a faint square per fog cell), the fog
## of war (the dark cover over places our team can't see: FogView's picture), the
## motherships, every unit our team can see right now (a defense post is a
## diamond; one of ours that fell is a hollow diamond), our own ship (ring
## and nose line), chevrons that feature modules ask for (a breached lane,
## FeatureRegistry.minimap_chevrons()), the rings and diamonds of feature
## modules that have minimap_marks(vt) (_draw_feature_marks), the rally
## waypoint and a box for what the camera shows.
## The bottom layers (the background with the lanes and camps, each resource node, and the cover patches) hardly ever change, so
## each is a child, a MinimapStill, that keeps its picture and is drawn again only when _still_signature() says that what it shows
## has changed (a node changed hands, a site started building, a camp was explored ...); the Minimap's own _draw() paints
## the rest on top, 5 times a second. They are separate so that a site that is being built, which changes its own ring every
## tick, does not make the lanes, the other nodes and the cover patches be drawn again with it.
## The whole 40,000 x 31,200 world is shrunk to 300 pixels wide: k is that
## shrink factor (map pixels per world unit, 300 / 40,000 = 0.0075).
## Clicks: everyone left-clicks (or drags) to move the camera there (an
## Admiral who follows their ship with C keeps the camera on it); with an
## Admiral map tool armed, a left click places it there instead
## (CommandOverlay.apply_at). A right click cancels an armed tool
## (CommandOverlay.order_at).
##
## WHO USES IT: Hud makes it from scenes/ui/minimap.tscn and calls
## setup(world, overlay). MinimapStill calls draw_still(). It reads World, MapInfo (world.map), Vision
## (what each team has explored, and the cover patches) and CameraRig.

## Width of the minimap (pixels). Its height keeps the world's shape.
const MAP_W := 300.0
## The radius (pixels) of the thin ring around the dots of our own wingmen.
const WING_RING_R := 3.2
## Seconds between two redraws: 5 a second. A ship moves under one pixel of the 300-pixel map in this time.
const REDRAW_S := 0.2
## The still layers (see _stills): part 0 is the background with the lanes and camps, then one part for each resource node
## (part 1 is world.nodes[0]), then the cover patches last.
const PART_BASE := 0
## Seconds to the next redraw at most while a click or a drag moves the camera: the camera box follows the pointer 10 times a
## second, as it always did.
const REDRAW_DRAG_S := 0.1

## The game world (set by setup()).
var world: World
## The Admiral's map tools, so a click can place an armed tool.
var overlay: CommandOverlay = null
## Shrink factor: minimap pixels per world unit (MAP_W / MapLayout.W).
var k := 1.0
## Seconds until the next redraw (counts down from REDRAW_S).
var _t := 0.0
## The fog-of-war picture from the world's FogView, or null if the fog is
## not shown.
var _fog_tex: Texture2D = null
## True while the left mouse button is held after a camera click, so
## dragging keeps moving the camera.
var _drag := false
## The layers under the moving one, bottom first (made by setup()): PART_BASE (the background, the lanes and the camps), one
## for each resource node, and the cover patches last. Each keeps its picture until its _still_signature() changes.
var _stills: Array[MinimapStill] = []
## What _still_signature() was when each still layer was last drawn (empty: draw it).
var _still_keys: Array = []
## The cover patches' squares as meshes with their colours (made the first time they are drawn; empty before): see _make_cover_meshes().
var _cover_meshes: Array = []


## Called once when the node joins the scene: take mouse clicks and size
## ourselves to MAP_W wide with the world's shape.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	k = MAP_W / MapLayout.W
	custom_minimum_size = Vector2(MAP_W, MapLayout.H * k)
	tooltip_text = ""



## Remember the world and the map-tool layer, and borrow the fog picture
## from the world's "FogView" node (only if it is showing).
func setup(w: World, ov: CommandOverlay) -> void:
	world = w
	overlay = ov
	var fog := w.get_node_or_null("FogView") as Sprite2D
	if fog != null and fog.visible:
		_fog_tex = fog.texture
	_make_stills()
	forget_still()


## Make the still layers (see _stills), once the world's resource nodes are known.
func _make_stills() -> void:
	for s in _stills:
		s.queue_free()
	_stills.clear()
	for p in world.nodes.size() + 2:
		var s := MinimapStill.new()
		s.map = self
		s.part = p
		add_child(s)
		_stills.append(s)


## Forget what the still layers last drew, so each is drawn again at the next redraw (setup() and tests/minimap_look.gd).
func forget_still() -> void:
	_still_keys = []
	for s in _stills:
		_still_keys.append([])
		s.queue_redraw()


## Every frame: every REDRAW_S seconds while we are on screen, redraw the moving layer
## (queue_redraw makes Godot call _draw() again), and redraw each still layer too if what it
## shows has changed (see _still_signature()).
func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0 and is_visible_in_tree():
		_t = REDRAW_S
		if world != null:
			# A resource node added or removed (none are in today's game): make the layers again.
			if _stills.size() != world.nodes.size() + 2:
				_make_stills()
				forget_still()
			for p in _stills.size():
				var sig := _still_signature(p)
				if sig != _still_keys[p]:
					_still_keys[p] = sig
					_stills[p].queue_redraw()
		queue_redraw()


## Everything still layer `part` is made from, as a flat list. PART_BASE: the team we see as, the No fog switch and whether each
## camp is shown (the lanes never change during a match). A node's part: the same two and the colour that node is
## drawn in, its SiteMarks view (state, team, seconds left, progress, pilots) and its turret count. The last part, the cover:
## whether the map has cover patches (they never change). When this list is the same as at the last drawing, the picture is too.
func _still_signature(part: int) -> Array:
	if part == _stills.size() - 1:
		return [world.vision.cover.any]
	var vt := world.viewer_team
	var fog_off := FogOff.is_on()
	var key: Array = [vt, fog_off]
	if part == PART_BASE:
		for c: Dictionary in world.map.camps:
			key.append(vt < 0 or fog_off or world.vision.is_explored(vt, c["pos"]))
		return key
	var n: ResourceNode = world.nodes[part - 1]
	key.append(_node_colour_team(n, vt, fog_off))
	var v := SiteMarks.view(world, n, vt)
	key.append(v["state"])
	key.append(v["team"])
	key.append(v["left"])
	key.append(v["progress"])
	key.append(v["p0"])
	key.append(v["p1"])
	key.append(maxi(n.turret_count(0), n.turret_count(1)))
	key.append(n.site.build_radius)
	return key

## Which team's colour resource node `n` is drawn in on the minimap (-1: grey, when nobody holds it, or when it is the
## enemy's and we haven't explored it).
func _node_colour_team(n: ResourceNode, vt: int, fog_off: bool) -> int:
	var holder := n.owner_team()
	if holder >= 0 and (holder == vt or vt < 0 or fog_off or world.vision.is_explored(vt, n.global_position)):
		return holder
	return -1


## A world position -> the same spot on the minimap (pixels).
func to_map(p: Vector2) -> Vector2:
	return p * k


## A minimap spot (pixels) -> the world position, kept inside the world.
func to_world(m: Vector2) -> Vector2:
	return Vector2(clampf(m.x / k, 0.0, MapLayout.W), clampf(m.y / k, 0.0, MapLayout.H))


## Mouse input on the minimap (see "Clicks" in HOW IT WORKS).
func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			# A left or right press: the click is ours (not the game's).
			accept_event()
			var p := to_world(mb.position)
			# Left: place the armed map tool, or move the camera and start
			# a drag. (CameraRig.look_at_point only moves a free camera,
			# so an Admiral who follows their ship stays on it.)
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if overlay != null and overlay.tool != "":
					overlay.apply_at(p)
				else:
					world.camera.look_at_point(p)
					_drag = true
					_t = minf(_t, REDRAW_DRAG_S)
			# Right: cancel an armed tool.
			elif overlay != null:
				overlay.order_at(p)
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = false
	elif event is InputEventMouseMotion and _drag:
		world.camera.look_at_point(to_world((event as InputEventMouseMotion).position))
		_t = minf(_t, REDRAW_DRAG_S)


## Draw still layer `part` (MinimapStill calls this) on canvas item `ci`: PART_BASE is the background, the lanes and the camps,
## then each resource node (part 1 is the first), then the cover patches; in that order, bottom first (see HOW IT WORKS). vt is
## the team we see as (-1 = a spectator who sees everything).
func draw_still(ci: CanvasItem, part: int) -> void:
	if part == PART_BASE:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Palette.with_alpha(Palette.VOID, 0.92))
	if world == null:
		return
	if part == _stills.size() - 1:
		# Cover patches (gas clouds): a faint square for every cell, under the fog
		# so a cloud nobody has explored stays dark.
		_draw_cover(ci)
		return
	var vt := world.viewer_team
	var fog_off := FogOff.is_on()
	if part != PART_BASE:
		_draw_node(ci, world.nodes[part - 1], vt, fog_off)
		return
	# Lanes, drawn as lines as wide as the real lanes (a lane's half-width
	# defaults to 1,800 world units).
	for id: String in world.map.lanes:
		var pts: PackedVector2Array = world.map.lanes[id]
		var half: float = float(world.map.lane_half.get(id, 1800.0))
		_poly(ci, pts, Palette.with_alpha(Palette.LANE, 0.55), half * 2.0 * k)
	# Scum dens (the derelict camps), once our team has explored their spot: a hazard-yellow square.
	for c: Dictionary in world.map.camps:
		var cp: Vector2 = c["pos"]
		if vt < 0 or fog_off or world.vision.is_explored(vt, cp):
			var m := to_map(cp)
			ci.draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), Palette.with_alpha(Palette.SCUM_HAZARD, 0.75), false, 1.0)


## Draw resource node `n` (its still layer) for the team `vt` we see as.
func _draw_node(ci: CanvasItem, n: ResourceNode, vt: int, fog_off: bool) -> void:
	# A resource node: a ring in the holder's colour (grey when nobody holds
	# it, or when it is the enemy's and we haven't explored it), with one
	# small square per turret under it.
	var holder := _node_colour_team(n, vt, fog_off)
	var col := Palette.team(holder) if holder >= 0 else Palette.NEUTRAL
	var m := to_map(n.global_position)
	# A shared jungle node, and any site being built or locked, shows its
	# state as a ring style and a word (SiteMarks); the others a plain ring.
	var v := SiteMarks.view(world, n, vt)
	if String(v["state"]) == SiteMarks.PLAIN:
		ci.draw_arc(m, 5.0, 0.0, TAU, 16, col, 1.5, true)
	else:
		SiteMarks.draw_ring(ci, m, 5.0, v, 1.5)
		# The real build circle only while something is going on there (not
		# OPEN or HELD), and the word for a shared site.
		if n.node_kind == "jungle_shared":
			if String(v["state"]) != TurretSite.OPEN and String(v["state"]) != TurretSite.HELD:
				SiteMarks.dashed_circle(ci, m, n.site.build_radius * k, Palette.with_alpha(Palette.ICE, 0.6), 1.0)
			_mini_word(ci, m, SiteMarks.word(v))
	var nt := maxi(n.turret_count(0), n.turret_count(1))
	for i in nt:
		ci.draw_rect(Rect2(m + Vector2(-4.0 + float(i) * 3.5, 7.0), Vector2(2.5, 2.5)), col)


## Draw the moving layer on top of the still one, bottom first (see HOW IT WORKS): the fog, the
## motherships, the units, and the marks and the camera box. vt is the team we see as (-1 = a spectator who sees everything).
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if world == null:
		return
	var vt := world.viewer_team
	# The fog of war, stretched over the whole minimap (not for spectators).
	if _fog_tex != null and vt >= 0:
		draw_texture_rect(_fog_tex, rect, false)
	# Motherships: a thick line along each hull (faded once destroyed).
	for ms: Mothership in world.motherships:
		if ms == null:
			continue
		var f := Vector2.from_angle(ms.rotation) * ms.half_len
		var col := Palette.team(ms.team)
		if not ms.alive:
			col = Palette.with_alpha(col, 0.3)
		draw_line(to_map(ms.global_position - f), to_map(ms.global_position + f), col, maxf(3.0, ms.beam * k), true)
	_draw_units(vt)
	_draw_post_sites(vt)
	# Marks from feature modules (lane breach chevrons ...): a chevron in the
	# owner's colour, pointing the way that team attacks. Only when a feature
	# is on.
	if not world.features.is_empty():
		for mk: Dictionary in FeatureRegistry.minimap_chevrons(world):
			var mt := int(mk["team"])
			_chevron(to_map(mk["pos"]), Palette.team(mt), 1.0 if mt == Rules.HALCYON else -1.0)
	# Rings and diamonds from feature modules (the Dreadnought, beacons).
	_draw_feature_marks(vt)
	# The rally waypoint: a ring in the highlight colour as big as its real area.
	if vt >= 0 and world.teams[vt].has_waypoint():
		var wp := to_map(world.teams[vt].waypoint)
		draw_arc(wp, Rules.WAYPOINT_RADIUS * k, 0.0, TAU, 20, UiKit.accent(), 1.2, true)
	# The marks that feature modules add (Barrage circle, bounty diamonds,
	# Fortify shimmer ...); nothing in today's game.
	if not world.command.marks.is_empty():
		CommandOrders.draw_minimap(self, vt)
	# The camera's view: the part of the world the screen shows right now
	# (window size / zoom), cut to the minimap's edges. Then a border.
	var cam := world.camera
	var view := get_viewport_rect().size / cam.zoom.x
	var cr := Rect2(to_map(cam.global_position - view * 0.5), view * k)
	draw_rect(cr.intersection(rect), Palette.with_alpha(Palette.ICE, 0.7), false, 1.0)
	draw_rect(rect, Palette.LINE, false, 1.0)


## Draw every live unit our team (`vt`) can see, as a small mark in its
## team colour (a different shape per kind), then our own ship on top.
## Enemy structures we saw once stay drawn even when out of sight now
## (seen_mask is a row of on/off switches, one per team: bit 1 << vt is on
## once team vt has seen it).
func _draw_units(vt: int) -> void:
	var me: Ship = null
	if world.human != null and world.human.ship != null and is_instance_valid(world.human.ship):
		me = world.human.ship
	# The seat of the human pilot whose wing is ringed (-1: nobody's).
	var my_wing_seat := world.human.slot if world.human != null and world.human_role == "pilot" else -1
	# What the loop asks of every unit is worked out once here, not once a unit: whether the fog hides enemies we can't see, the
	# colours (a team's, and its minion dot's fainter one), the dot radius of each ship size and the feature modules that may
	# black a contact out (none in most matches).
	var fog_hides := vt >= 0 and not FogOff.is_on()
	var hiders := _contact_hiders()
	var cols := [Palette.team(Rules.HALCYON), Palette.team(Rules.CINDER), Palette.DERELICT]
	var minion_cols := [Palette.with_alpha(cols[0], 0.85), Palette.with_alpha(cols[1], 0.85), Palette.with_alpha(cols[2], 0.85)]
	var ship_r := [2.2, 2.2 + 1.0 * 0.8, 2.2 + 2.0 * 0.8, 2.2 + 3.0 * 0.8]
	for u: Unit in world.units:
		if not u.alive or u.kind == Unit.K_MOTHERSHIP:
			continue
		# Skip enemies we can't see now (except structures seen before; with No fog on, FogOff, none are skipped).
		if fog_hides and u.team != vt and (u.visible_mask & (1 << vt)) == 0:
			if not (u.is_structure() and (u.seen_mask & (1 << vt)) != 0):
				continue
		# A feature module may black a contact out (the beacons variant).
		if not hiders.is_empty() and _feature_hides(hiders, u, vt):
			continue
		var m := u.global_position * k
		var ti := 0 if u.team == Rules.HALCYON else (1 if u.team == Rules.CINDER else 2)
		var col: Color = cols[ti]
		match u.kind:
			# Ships: a dot that is bigger for bigger ship sizes.
			Unit.K_SHIP:
				var r: float = ship_r[clampi(u.size_class, 0, 3)]
				draw_circle(m, r, col)
				# Our own wingmen get a thin white ring (their crew's seat number says whose they are).
				var crew := (u as Ship).profile
				if my_wing_seat >= 0 and u.team == vt and crew != null and crew.slot >= Squads.CREW_SLOT_BASE and Squads.crew_seat(crew.slot) == my_wing_seat:
					draw_arc(m, WING_RING_R, 0.0, TAU, 12, Palette.ICE, 1.0, true)
			Unit.K_MINION:
				draw_rect(Rect2(m - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), minion_cols[ti])
			Unit.K_TURRET:
				draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), col)
				draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), Palette.VOID, false, 1.0)
			Unit.K_POST:
				# A defense post: a filled diamond (a turret is a square, a repair
				# bay a hollow square).
				_diamond(m, 3.5, col, true)
				_diamond(m, 3.5, Palette.VOID, false)
			Unit.K_BAY:
				draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), Palette.REPAIR, false, 1.5)
			Unit.K_WARD:
				draw_circle(m, 1.5, Palette.VEIL)
			Unit.K_MINING_DRONE:
				draw_circle(m, 1.0, Palette.with_alpha(Palette.ORE, 0.9))
			# A Scum ship: a toxic-green dot in a hazard-yellow ring; a Scum Fighter a plain green dot.
			Unit.K_MONSTER:
				draw_circle(m, 2.4, Palette.SCUM_HAZARD)
				draw_circle(m, 1.2, Palette.SCUM_GLOW)
			Unit.K_SNUB:
				draw_circle(m, 1.3, Palette.SCUM_GLOW)
	# Our own ship: a white ring with a line showing where its nose points.
	if me != null and me.alive:
		var m := to_map(me.global_position)
		draw_arc(m, 5.0, 0.0, TAU, 16, Palette.ICE, 1.5, true)
		draw_line(m, m + Vector2.from_angle(me.rotation) * 8.0, Palette.ICE, 1.5, true)


## Write `text` (a SiteMarks word) in small type under minimap spot `m` on canvas item `ci`, centred.
func _mini_word(ci: CanvasItem, m: Vector2, text: String) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	ci.draw_string_outline(font, m + Vector2(-40.0, 17.0), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 8, 3, Palette.VOID)
	ci.draw_string(font, m + Vector2(-40.0, 17.0), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 8, Palette.ICE)


## Draw a diamond of half-size `r` pixels at minimap spot `m`: filled in `col`, or
## only its outline.
func _diamond(m: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, 1.0, true)


## Mark each of our own defense posts that is not standing: a hollow diamond
## while its rebuild timer runs, with a dot in it once the admiral may rebuild
## it. Only the owner's team (and a spectator) sees this; the other team sees the
## post's fall in the news.
func _draw_post_sites(vt: int) -> void:
	for ps: PostSite in world.defense_posts.sites:
		if ps.state != PostSite.DESTROYED and ps.state != PostSite.READY:
			continue
		if vt >= 0 and ps.team != vt:
			continue
		var m := to_map(ps.pos)
		_diamond(m, 3.5, Palette.with_alpha(Palette.team(ps.team), 0.8), false)
		if ps.state == PostSite.READY:
			draw_circle(m, 1.2, Palette.team(ps.team))


## Draw a chevron (a ">" or "<") at minimap spot `m` in colour `col`;
## `dir` is 1.0 for ">" (pointing right) and -1.0 for "<".
func _chevron(m: Vector2, col: Color, dir: float) -> void:
	draw_polyline(PackedVector2Array([m + Vector2(-3.0 * dir, -5.0), m + Vector2(3.0 * dir, 0.0), m + Vector2(-3.0 * dir, 5.0)]), col, 2.0, true)


## Feature hook: the feature modules in World.features that have minimap_hides(u, vt) -> bool (BeaconsFeature, during a
## blackout), worked out once for a redraw. Empty in most matches.
func _contact_hiders() -> Array:
	var out: Array = []
	for f: Object in world.features.values():
		if f.has_method("minimap_hides"):
			out.append(f)
	return out


## Feature hook: does one of the `hiders` (see _contact_hiders()) black unit `u` out of the minimap
## for the team `vt` we see as?
func _feature_hides(hiders: Array, u: Unit, vt: int) -> bool:
	for f: Object in hiders:
		if f.call("minimap_hides", u, vt):
			return true
	return false


## Feature hook: draw the marks of the feature modules that have
## minimap_marks(vt) -> Array of {pos, color, shape ("ring" or "diamond"),
## r}: the Dreadnought and the salvage beacons.
func _draw_feature_marks(vt: int) -> void:
	if world.features.is_empty():
		return
	for f: Object in world.features.values():
		if not f.has_method("minimap_marks"):
			continue
		for mk: Dictionary in f.call("minimap_marks", vt):
			var m := to_map(mk["pos"])
			var col: Color = mk["color"]
			var r := float(mk.get("r", 4.0))
			if str(mk.get("shape", "ring")) == "diamond":
				draw_colored_polygon(PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0)]), col)
			else:
				draw_arc(m, r, 0.0, TAU, 16, col, 1.5, true)


## Draw the line through world points `pts` on the minimap (on canvas item `ci`), `width` pixels
## wide (nothing for fewer than 2 points).
func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var out := PackedVector2Array()
	for p in pts:
		out.append(to_map(p))
	ci.draw_polyline(out, col, width, true)


## Draw the map's cover patches (gas clouds, hidden pockets): one faint square
## in the patch's colour for every fog cell of every patch, on canvas item `ci`. Nothing when the map
## has none. The squares never change during a match, so they are made into two meshes (the gas cells and the pocket
## cells) the first time and drawn with one call each (they were one draw call each cell: about 250 of the minimap's calls).
func _draw_cover(ci: CanvasItem) -> void:
	var cover := world.vision.cover
	if not cover.any:
		return
	if _cover_meshes.is_empty():
		_cover_meshes = _make_cover_meshes()
	for part: Array in _cover_meshes:
		ci.draw_mesh(part[0] as ArrayMesh, null, Transform2D.IDENTITY, part[1] as Color)


## The cover patches' squares as meshes: [[mesh, colour], ...], one for the gas cells and one for the pocket cells (a
## cell is in one patch only, so the two never overlap and their order does not matter). The squares are white and the
## colour is given at draw time: a vertex colour is stored in 8 bits and would round the faint 0.45 alpha off by one level.
func _make_cover_meshes() -> Array:
	var cover := world.vision.cover
	var side := world.vision.cell * k
	var out: Array = []
	for kind in ["cloud", "pocket"]:
		var verts := PackedVector2Array()
		var idx := PackedInt32Array()
		for id in range(1, cover.cells.size()):
			if (str(cover.kinds[id]) == "pocket") != (kind == "pocket"):
				continue
			for c in cover.cells[id] as PackedInt32Array:
				var at := Vector2(float(c % world.vision.cols), float(c / world.vision.cols)) * side
				var b := verts.size()
				verts.append(at)
				verts.append(at + Vector2(side, 0.0))
				verts.append(at + Vector2(side, side))
				verts.append(at + Vector2(0.0, side))
				idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
		if verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var col := Palette.POCKET if kind == "pocket" else Palette.GAS
		out.append([mesh, Palette.with_alpha(col, 0.45)])
	return out
