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
## diamond; one of ours that fell is its outline with an X in it, or a plus once it may be rebuilt; T-126a: the team sets the fill of
## every icon, Aurelian solid and Vhorr hollow, and minions, drones and wards take the team marks themselves: TeamMarks), our own ship (ring
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
## SIZE (T-125): the minimap has a size of its own, 80% to 140% (Game.minimap_pct, the pause menu's slider). Everything is still drawn
## in the 300-pixel base picture (k, the icon sizes, the line widths) and the whole picture is scaled by the size: draw_set_transform()
## in _draw() and in draw_still(), and the control is that much bigger. So every size, even an icon that a later stage draws, scales
## without being touched; only the words under the shared points keep a floor of 8 pixels on the screen. A click works out the world
## spot with the scaled factor (to_world()). When T-24 adds a HUD size, it must not multiply this one.
## Clicks: everyone left-clicks (or drags) to move the camera there (an
## Admiral who follows their ship with C keeps the camera on it); with an
## Admiral map tool armed, a left click places it there instead
## (CommandOverlay.apply_at). A right click cancels an armed map tool; with none armed (and the Admiral's selection not
## empty) it gives the selected squadrons a Move to that point, never an Attack (CommandOverlay.order_at, RT6 B1; the setting
## Minimap.orders_on, on by default, turns it off). The left route is the Move verb on the card, then a left click here.
## RT6 marks (drawn in the same 5 Hz _draw, for the Admiral only): a dashed rally line from each selected squadron to the
## point of its order (dotted and tagged "on resume" while the match is held paused), the flag of the rally spot the Admiral
## picked, a ring at each alert the feed has a place for (two pulses at 2 Hz when raised, then steady; the expired alerts of the
## jump chain are faint), and three layer buttons on the top edge (Fleet, Alerts, Lines, all on): a left click on one toggles it.
## S7A adds last-seen marks: an enemy ship that the fog now hides stays on the map as a faint disc at the place our team last saw it,
## fading out over LastSeen.LAST_SEEN_FADE_S seconds (ships only; a structure keeps the last-known picture it always had; with No fog
## on none are made). LastSeen holds them; they are drawn in the same 5 Hz redraw, so nothing is timed.
## RT7 adds a group flash: in field mode (FieldMode) a double tap of a group's key (Groups.double_tapped) draws one steady ring round the
## dot of each squadron of the group for 0.3 s, at most one flash every 334 ms, on the same 5 Hz redraw (no tween, no timer node).
##
## WHO USES IT: Hud makes it from scenes/ui/minimap.tscn and calls
## setup(world, overlay). MinimapStill calls draw_still(). It reads World, MapInfo (world.map), Vision
## (what each team has explored, and the cover patches) and CameraRig. LastSeen remembers the enemy ships the fog hides.

## Width of the minimap (pixels). Its height keeps the world's shape.
const MAP_W := 300.0
## T-126a: the scale every team-mark icon size below is written as a multiple of (1.0 for now; a later minimap size multiplies it, line
## widths too, never under 1 pixel: see _w()).
const ICON_K := 1.0
## How far (pixels at 100%) the thin ring around the dots of our own wingmen lies outside the ship's dot.
const WING_RING_GAP := 1.6
## The radius (pixels at 100%) of the dot of each ship size class: small to big.
const SHIP_DOT_R := [3.3, 4.0, 4.7, 5.4]
## The radius of the ring round a resource node, and its line (pixels at 100%).
const NODE_RING_R := 7.0
const NODE_RING_W := 1.5
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
## Shrink factor of the base picture: minimap pixels per world unit at 100% (MAP_W / MapLayout.W). The size on the screen is
## `k * size_scale()` (see SIZE in HOW IT WORKS).
var k := 1.0
## The minimap's size as a factor (Game.minimap_pct / 100: 0.8 to 1.4), set by apply_size().
var _s := 1.0
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
## RT6 S5: the layer buttons. Fleet: the ship and minion discs; Alerts: the alert rings; Lines: the rally lines and the rally flag.
var layer_fleet := true
var layer_alerts := true
var layer_lines := true
## RT7: the group flash. The squadrons ringed now, when the last flash began (milliseconds on the Groups' clock, which a test may
## set, and on the real clock, which times the ring's 0.3 s), how many flashes have begun (a test reads it) and the Groups this
## minimap listens to (found through the command view, like the alert feed).
var _flash_ids: Array[int] = []
var _flash_at := -1000000  # when the last flash began, on the Groups' clock (milliseconds)
var _flash_real := -1000000  # when the last flash began, on the real clock (milliseconds)
var flash_count := 0  # how many flashes have begun (a test reads it)
var _groups_hooked: Groups = null  # the Groups this minimap listens to (null until found)
## S7A: where each enemy ship was when our team last saw it (LastSeen). _draw_units() feeds it and draws its faint marks.
var last_seen := LastSeen.new()
## S7A: how strong a last-seen mark is next to the live disc of the same ship (times the mark's own fade).
const LAST_SEEN_ALPHA := 0.5

## RT6 S5: the setting "Minimap orders" (RtsUiCalls.MINIMAP_ORDERS_ON until the player changes it). Static, so CommandOverlay
## reads it without a node, and the pause menu sets it with set_orders(). Saved in the [game] section of the settings file.
static var orders_on: bool = RtsUiCalls.MINIMAP_ORDERS_ON
static var _prefs_read := false

## The layer buttons' size and place in the 300-pixel base picture (top edge, from the left).
const CHIP_W := 34.0
const CHIP_H := 11.0
const CHIP_GAP := 2.0
const LAYER_NAMES := ["Fleet", "Alerts", "Lines"]
## The alert ring's pulse: two pulses (a pulse is 0.5 s: on, then off) from the moment the alert was raised, then steady.
const ALERT_PULSES := 2
## RT7: the ring a double tap of a group key draws round each squadron's dot of that group, in field mode: how long it stays
## (seconds, steady), the least time between two such rings (milliseconds: at most three a second) and its radius in the 300-pixel
## base picture.
const GROUP_FLASH_S := 0.3
const GROUP_FLASH_GAP_MS := 334  # the least time between two flashes (milliseconds)
const GROUP_FLASH_R := 7.0  # the ring's radius in the 300-pixel base picture


## Read the saved setting once (the first Minimap made). Not in a test run (--auto or --test): those never touch the profile.
static func read_prefs() -> void:
	if _prefs_read:
		return
	_prefs_read = true
	if Game.opt("auto", false) or Game.opt("test", "") != "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(Game.SETTINGS_FILE) != OK:
		return
	var v: Variant = cfg.get_value("game", "minimap_orders", RtsUiCalls.MINIMAP_ORDERS_ON)
	orders_on = not (typeof(v) == TYPE_BOOL and not v)


## Switch "Minimap orders" on or off and (with `save`) remember it through Game._remember.
static func set_orders(on: bool, save: bool = true) -> void:
	orders_on = on
	if save:
		Game._remember("minimap_orders", on, "Minimap orders")


## Called once when the node joins the scene: take mouse clicks and size
## ourselves to MAP_W wide with the world's shape.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	k = MAP_W / MapLayout.W
	tooltip_text = ""
	apply_size()


## The minimap's size as a factor (1.0 = the 300-pixel picture).
func size_scale() -> float:
	return _s


## The base picture's size (pixels at 100%): the world's shape, MAP_W wide.
func base_size() -> Vector2:
	return Vector2(MAP_W, MapLayout.H * k)


## Take the size from Game.minimap_pct (at once: the pause menu's slider calls it after each change): the control is that much
## bigger or smaller and every layer is drawn again.
func apply_size() -> void:
	_s = clampf(float(Game.minimap_pct) / 100.0, float(Game.MINIMAP_PCT_MIN) / 100.0, float(Game.MINIMAP_PCT_MAX) / 100.0)
	var want := base_size() * _s
	custom_minimum_size = want
	# The minimap is anchored to the bottom-right corner (hud.tscn): put its top-left edge the size away from its fixed
	# right and bottom edges. (A smaller minimum does not shrink a control that is bigger already, and setting `size`
	# would move the corner the wrong way.)
	offset_left = offset_right - want.x
	offset_top = offset_bottom - want.y
	if world != null:
		forget_still()
	queue_redraw()



## Remember the world and the map-tool layer, and borrow the fog picture
## from the world's "FogView" node (only if it is showing).
func setup(w: World, ov: CommandOverlay) -> void:
	world = w
	overlay = ov
	read_prefs()
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
			if _groups_hooked == null:
				hook_groups()
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


## A minimap spot (pixels on the screen, from the minimap's top-left corner) -> the world position, kept inside the world. It follows
## the size: a click on a corner lands on that corner of the map at any size.
func to_world(m: Vector2) -> Vector2:
	var f := k * _s
	return Vector2(clampf(m.x / f, 0.0, MapLayout.W), clampf(m.y / f, 0.0, MapLayout.H))


## Mouse input on the minimap (see "Clicks" in HOW IT WORKS).
func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			# A left or right press: the click is ours (not the game's).
			accept_event()
			# The layer buttons on the top edge take the left click (a right click on one does nothing).
			var chip := chip_at(mb.position)
			if chip >= 0:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					toggle_layer(chip)
				return
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
			# Right: cancel an armed map tool, else Move for the selection (the overlay decides; see "Clicks").
			elif overlay != null:
				overlay.order_at(p)
				_t = minf(_t, REDRAW_DRAG_S)
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = false
	elif event is InputEventMouseMotion and _drag:
		world.camera.look_at_point(to_world((event as InputEventMouseMotion).position))
		_t = minf(_t, REDRAW_DRAG_S)


# --- RT6 S5: the layer buttons and the marks of the orders and the alerts --------------------------------------

## The rectangle of layer button `i` (0 Fleet, 1 Alerts, 2 Lines) in the 300-pixel base picture: along the top edge, from the left.
func chip_rect(i: int) -> Rect2:
	return Rect2(Vector2(2.0 + float(i) * (CHIP_W + CHIP_GAP), 2.0), Vector2(CHIP_W, CHIP_H))


## The layer button under minimap pixel `m` (the control's own pixels, so scaled by the size), or -1.
func chip_at(m: Vector2) -> int:
	var b := m / _s
	for i in LAYER_NAMES.size():
		if chip_rect(i).has_point(b):
			return i
	return -1


## Switch layer button `i` on or off (a screen state only: nothing reads it but the drawing).
func toggle_layer(i: int) -> void:
	match i:
		0:
			layer_fleet = not layer_fleet
		1:
			layer_alerts = not layer_alerts
		2:
			layer_lines = not layer_lines
	queue_redraw()


## Is layer `i` on?
func layer_on(i: int) -> bool:
	match i:
		0:
			return layer_fleet
		1:
			return layer_alerts
	return layer_lines


## The Admiral's marks, on the moving layer: the rally lines and flag, then the alert rings. Nothing for anyone else.
func _draw_marks(vt: int) -> void:
	if overlay == null or not overlay.is_admiral() or vt != overlay.team:
		return
	if layer_lines:
		_draw_rally_lines()
	if layer_alerts:
		_draw_alert_rings()
	_draw_group_flash()


## RT7: listen to the Admiral's Groups for a double tap (found through the command view; the redraw beat calls this until it finds
## them, and a test may call it). Does nothing when the Groups are not there or are already heard.
func hook_groups() -> void:
	var g := _groups()
	if g != null and g != _groups_hooked:
		_groups_hooked = g
		g.double_tapped.connect(_on_group_double_tap)


## RT7: a group was tapped twice. In field mode (the camera stays on the ship) it starts a flash: one ring round each squadron
## of the group for GROUP_FLASH_S, at most one flash every GROUP_FLASH_GAP_MS (the Groups' clock). Docked or with the view open
## the double tap centres the camera and no ring is drawn. Screen state only: no order, no random number.
func _on_group_double_tap(n: int) -> void:
	if world == null or overlay == null or _groups_hooked == null or not FieldMode.active(world, overlay.team):
		return
	var now := _groups_hooked.now_ms()
	if now - _flash_at < GROUP_FLASH_GAP_MS:
		return
	var ids := _groups_hooked.members(n)
	if ids.is_empty():
		return
	_flash_at = now
	_flash_real = Time.get_ticks_msec()
	_flash_ids = ids
	flash_count += 1
	_t = minf(_t, REDRAW_DRAG_S)


## RT7: the squadrons ringed by the group flash now (empty when no flash is on).
func flash_ids() -> Array[int]:
	if _flash_ids.is_empty() or float(Time.get_ticks_msec() - _flash_real) / 1000.0 >= GROUP_FLASH_S:
		return []
	if world == null or overlay == null or not FieldMode.active(world, overlay.team):
		return []
	return _flash_ids


## RT7: the group flash ring: a steady ice ring round the dot of each squadron of the tapped group, on the 5 Hz redraw.
func _draw_group_flash() -> void:
	for id: int in flash_ids():
		var rec: Squad = world.squads.get(id)
		if rec != null:
			draw_arc(to_map(RtsSelect.centre_of(world, rec)), GROUP_FLASH_R, 0.0, TAU, 20, Palette.ICE, 1.5, true)


## The Groups of the Admiral's command view (the HUD above this node holds the view), or null.
func _groups() -> Groups:
	var p := get_parent()
	if p != null and "command_view" in p:
		var cv: Variant = p.get("command_view")
		if cv != null and "groups" in cv:
			return cv.get("groups") as Groups
	return null


## A dashed light line from each selected squadron to the point of its order, an end ring on the point, and the flag of the
## rally spot (a dashed line from our mothership in the accent colour). While the match is held paused the lines are dotted
## and tagged "on resume" (an order waits in the queue until then).
func _draw_rally_lines() -> void:
	var held := get_tree().paused
	var dash := 1.0 if held else 4.0
	var line := Palette.with_alpha(Palette.ICE, 0.75)
	var queued := _queued_points()
	var tagged := false
	for id in overlay.sel_squads:
		var rec: Squad = world.squads.get(id)
		if rec == null:
			continue
		var to: Variant = queued.get(id, null)
		if to == null:
			to = order_point(rec)
		if to == null:
			continue
		var a := to_map(RtsSelect.centre_of(world, rec))
		var b := to_map(Vector2(to))
		if a.distance_to(b) < 3.0:
			continue
		draw_dashed_line(a, b, line, 1.0, dash, true)
		draw_arc(b, 2.5, 0.0, TAU, 10, line, 1.0, true)
		if held and not tagged and queued.has(id):
			tagged = true
			_note(b + Vector2(4.0, -3.0), "on resume", line)
	if overlay.rally_set:
		var ms := world.mothership(overlay.team)
		var flag := to_map(Vector2(overlay.rally_spot))
		var acc := UiKit.accent()
		if ms != null and is_instance_valid(ms):
			draw_dashed_line(to_map(ms.global_position), flag, acc, 1.0, dash, true)
		draw_line(flag, flag + Vector2(0.0, -7.0), acc, 1.0, true)
		draw_colored_polygon(PackedVector2Array([flag + Vector2(0.0, -7.0), flag + Vector2(5.0, -5.0), flag + Vector2(0.0, -3.0)]), acc)


## The world point of the standing order of `rec` when it has one (a Move, an Attack-move or the like, with a point), else null.
static func order_point(rec: Squad) -> Variant:
	var o: Dictionary = rec.order
	if o.is_empty() or str(o.get("target_kind", "")) != "point":
		return null
	var t: Variant = o.get("target")
	return Vector2(t) if t is Vector2i or t is Vector2 else null


## Squad id -> the point of the newest order for it that is still in the order queue (waiting to be applied): while the
## match is held paused, these are the orders given in the pause.
func _queued_points() -> Dictionary:
	var out := {}
	if world.orders == null:
		return out
	for o: Dictionary in world.orders.queue:
		if str(o.get("target_kind", "")) != "point" or not bool(o.get("human", false)):
			continue
		var t: Variant = o.get("target")
		if not (t is Vector2i or t is Vector2):
			continue
		for id: Variant in o.get("subjects", []):
			out[int(id)] = Vector2(t)
	return out


## A ring at each alert with a place (alert_marks: every live one, and the expired ones of the jump chain, fainter): danger
## colour for the priorities 1 to 4, ice for the rest. A new alert pulses twice at 2 Hz (it is on for the first half second
## of each pulse), then holds steady. Drawn on the 5 Hz beat, so a pulse is two or three pictures.
func _draw_alert_rings() -> void:
	var tick := world.tick_count
	for a: Dictionary in alert_marks():
		var live := int(a["expires"]) > tick
		var col := Palette.DANGER if int(a["priority"]) <= 4 else Palette.ICE
		var m := to_map(Vector2(a["pos"]))
		if not live:
			draw_arc(m, 4.0, 0.0, TAU, 12, Palette.with_alpha(col, 0.35), 1.0, true)
			continue
		var age := float(tick - int(a["raised"])) / 60.0
		var r := 5.5
		var alpha := 0.95
		if age < float(ALERT_PULSES) * 0.5:
			var on := int(age * 4.0) % 2 == 0
			r = 7.0 if on else 4.0
			alpha = 1.0 if on else 0.45
		draw_arc(m, r, 0.0, TAU, 16, Palette.with_alpha(col, alpha), 1.5, true)


## The alerts that get a ring: the feed's jump chain first (its live alerts, then its expired ones), then every other
## live alert with a place that the player has not hidden, so no live placed alert is left without a ring when more
## are alive than the chain holds. With no feed: the list's live alerts with a place.
func alert_marks() -> Array:
	var tick := world.tick_count
	var out: Array = []
	var live: Array = (world.alerts[overlay.team] as AlertList).live(tick)
	var feed := _alert_feed()
	var seen := {}
	if feed != null:
		out = feed.chain()
		for a: Dictionary in out:
			seen[str(a["key"])] = true
		live = feed._unhidden(live)
	for a: Dictionary in live:
		if a["pos"] is Vector2i and not seen.has(str(a["key"])):
			out.append(a)
	return out


## The alert feed of the Admiral's command view (the HUD above this node holds it), or null.
func _alert_feed() -> AlertFeed:
	var p := get_parent()
	if p != null and "command_view" in p:
		var cv: Variant = p.get("command_view")
		if cv != null and "alert_feed" in cv:
			return cv.get("alert_feed") as AlertFeed
	return null


## The three layer buttons on the top edge: a dark chip with the name, lit in the accent colour when its layer is on.
func _draw_chips() -> void:
	var font := ThemeDB.fallback_font
	# The type never reads smaller than 8 pixels on the screen (the picture is scaled by the size).
	var fs := maxi(8, int(ceil(8.0 / _s)))
	for i in LAYER_NAMES.size():
		var r := chip_rect(i)
		var on := layer_on(i)
		draw_rect(r, Palette.with_alpha(Palette.VOID, 0.8))
		draw_rect(r, UiKit.accent() if on else Palette.LINE, false, 1.0)
		draw_string(font, r.position + Vector2(0.0, CHIP_H - 2.5), LAYER_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Palette.ICE if on else Palette.MIST)


## Small type at minimap spot `m` (the "on resume" tag), never under 8 pixels on the screen.
func _note(m: Vector2, text: String, col: Color) -> void:
	var fs := maxi(8, int(ceil(8.0 / _s)))
	draw_string_outline(ThemeDB.fallback_font, m, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 3, Palette.VOID)
	draw_string(ThemeDB.fallback_font, m, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


## Draw still layer `part` (MinimapStill calls this) on canvas item `ci`: PART_BASE is the background, the lanes and the camps,
## then each resource node (part 1 is the first), then the cover patches; in that order, bottom first (see HOW IT WORKS). vt is
## the team we see as (-1 = a spectator who sees everything).
func draw_still(ci: CanvasItem, part: int) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	if part == PART_BASE:
		ci.draw_rect(Rect2(Vector2.ZERO, base_size()), Palette.with_alpha(Palette.VOID, 0.92))
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
	# Scum dens (the derelict camps), once our team has explored their spot: a hazard-yellow 5 px square with the Scum's
	# cross at half size inside it (a hollow square alone is a Vhorr turret now).
	for c: Dictionary in world.map.camps:
		var cp: Vector2 = c["pos"]
		if vt < 0 or fog_off or world.vision.is_explored(vt, cp):
			var m := to_map(cp)
			var den_col := Palette.with_alpha(Palette.SCUM_HAZARD, 0.75)
			var den_h := 2.5 * ICON_K
			ci.draw_rect(Rect2(m - Vector2(den_h, den_h), Vector2(den_h * 2.0, den_h * 2.0)), den_col, false, _w(1.0))
			_scum_cross(ci, m, 0.5, 1.0, den_col)


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
		# A ring that shows a team colour follows HELD (the team's mark, and Vhorr's teeth); a plain grey one stays plain.
		if holder >= 0:
			SiteMarks.draw_ring(ci, m, NODE_RING_R * ICON_K, SiteMarks.held_view(holder), _w(NODE_RING_W), ICON_K, false)
		else:
			ci.draw_arc(m, NODE_RING_R * ICON_K, 0.0, TAU, 24, col, _w(NODE_RING_W), true)
	else:
		SiteMarks.draw_ring(ci, m, NODE_RING_R * ICON_K, v, _w(NODE_RING_W), ICON_K, false)
		# The real build circle only while something is going on there (not
		# OPEN or HELD), and the word for a shared site.
		if n.node_kind == "jungle_shared":
			if String(v["state"]) != TurretSite.OPEN and String(v["state"]) != TurretSite.HELD:
				SiteMarks.dashed_circle(ci, m, n.site.build_radius * k, Palette.with_alpha(Palette.ICE, 0.6), 1.0)
			_mini_word(ci, m, SiteMarks.word(v))
	var nt := maxi(n.turret_count(0), n.turret_count(1))
	for i in nt:
		ci.draw_rect(Rect2(m + Vector2(-4.0 + float(i) * 3.5, 9.5), Vector2(2.5, 2.5)), col)


## Draw the moving layer on top of the still one, bottom first (see HOW IT WORKS): the fog, the
## motherships, the units, and the marks and the camera box. vt is the team we see as (-1 = a spectator who sees everything).
func _draw() -> void:
	# Everything below is drawn at the 300-pixel base size and scaled by the minimap's own size (see SIZE in HOW IT WORKS).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	var rect := Rect2(Vector2.ZERO, base_size())
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
		# Aurelian: a plain line. Vhorr: a hollow bar, a bit thicker, with a 1.4 px VOID line down its middle.
		var a := to_map(ms.global_position - f)
		var b := to_map(ms.global_position + f)
		if ms.team == Rules.CINDER:
			draw_line(a, b, col, maxf(3.6 * ICON_K, ms.beam * k), true)
			draw_line(a, b, Palette.with_alpha(Palette.VOID, 0.9 if ms.alive else 0.3), _w(1.4), true)
		else:
			draw_line(a, b, col, maxf(3.0 * ICON_K, ms.beam * k), true)
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
	# RT6 S5: the Admiral's order lines and alert rings, and the layer buttons on the top edge.
	_draw_marks(vt)
	_draw_chips()


## S7A: let the last-seen memory look at the units once for viewing team `vt` (the same "does the fog hide enemies" decision the
## unit loop below makes; with No fog on or no viewing team the memory is empty). _draw_units() calls it at the top of each redraw;
## a check may call it without drawing, with a match time of its own as `now` (a negative `now`: the World's clock).
func update_last_seen(vt: int, now: float = -1.0) -> void:
	last_seen.update(world.units, vt, vt >= 0 and not FogOff.is_on(), world.time if now < 0.0 else now)


## Draw every live unit our team (`vt`) can see, as a small mark in its
## team colour (a different shape per kind), then our own ship on top.
## S7A: then the faint last-seen discs of the enemy ships the fog hides (LastSeen).
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
	update_last_seen(vt)
	var hiders := _contact_hiders()
	var cols := [Palette.team(Rules.HALCYON), Palette.team(Rules.CINDER), Palette.DERELICT]
	var minion_cols := [Palette.with_alpha(cols[0], 0.85), Palette.with_alpha(cols[1], 0.85), Palette.with_alpha(cols[2], 0.85)]
	for u: Unit in world.units:
		if not u.alive or u.kind == Unit.K_MOTHERSHIP:
			continue
		# The Fleet layer button: with it off the ship and minion discs are not drawn (our own ship's ring below still is).
		if not layer_fleet and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION):
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
			# T-126a: the kind keeps its base shape and the team sets the fill (TeamMarks): Aurelian solid, Vhorr hollow.
			# Ships: a disc that is bigger for bigger ship sizes.
			Unit.K_SHIP:
				var r: float = SHIP_DOT_R[clampi(u.size_class, 0, 3)] * ICON_K
				TeamMarks.icon(self, TeamMarks.DISC, m, r * 2.0, ti, 1.0, false, col)
				# Our own wingmen get a thin white ring (their crew's seat number says whose they are).
				var crew := (u as Ship).profile
				if my_wing_seat >= 0 and u.team == vt and crew != null and crew.slot >= Squads.CREW_SLOT_BASE and Squads.crew_seat(crew.slot) == my_wing_seat:
					draw_arc(m, r + WING_RING_GAP * ICON_K, 0.0, TAU, 12, Palette.ICE, _w(1.0), true)
			# Minions and drones are too small to be hollow: they take the team marks themselves (a disc, a wedge), filled.
			Unit.K_MINION:
				TeamMarks.fill(self, m, 5.0 * ICON_K, ti, minion_cols[ti])
			Unit.K_TURRET:
				TeamMarks.icon(self, TeamMarks.SQUARE, m, 6.0 * ICON_K, ti, 1.0, true, col)
			Unit.K_POST:
				# A defense post: a diamond (a turret is a square, a repair bay a square with a plus).
				TeamMarks.icon(self, TeamMarks.DIAMOND, m, 8.4 * ICON_K, ti, 1.0, true, col)
			Unit.K_BAY:
				TeamMarks.icon(self, TeamMarks.SQUARE, m, 6.5 * ICON_K, ti, 1.0, true, col)
				_plus(m, 2.2, 1.2, Palette.REPAIR)
			Unit.K_WARD:
				TeamMarks.fill(self, m, 4.0 * ICON_K, ti, Palette.VEIL)
			Unit.K_MINING_DRONE:
				TeamMarks.fill(self, m, 5.0 * ICON_K, ti, minion_cols[ti])
			# A Scum ship: the lopsided cross of its hull art in hazard yellow with a green dot; a Scum Fighter the same
			# at 0.6 size, thinner and all green.
			Unit.K_MONSTER:
				_scum_cross(self, m, 1.0, 1.5, Palette.SCUM_HAZARD)
				draw_circle(m, 0.9 * ICON_K, Palette.SCUM_GLOW)
			Unit.K_SNUB:
				_scum_cross(self, m, 0.6, 1.0, Palette.SCUM_GLOW)
	# S7A: the last-seen marks of enemy ships the fog now hides: the ship's disc, fainter than a live one, fading out (LastSeen).
	if layer_fleet and fog_hides:
		for mk: Dictionary in last_seen.marks(world.time):
			var mti := 0 if int(mk["team"]) == Rules.HALCYON else (1 if int(mk["team"]) == Rules.CINDER else 2)
			var mr: float = SHIP_DOT_R[clampi(int(mk["size_class"]), 0, 3)] * ICON_K
			var mcol: Color = Palette.with_alpha(cols[mti], LAST_SEEN_ALPHA * float(mk["alpha"]))
			TeamMarks.icon(self, TeamMarks.DISC, (mk["pos"] as Vector2) * k, mr * 2.0, mti, 1.0, false, mcol)
	# Our own ship: a white ring with a line showing where its nose points.
	if me != null and me.alive:
		var m := to_map(me.global_position)
		draw_arc(m, 5.0, 0.0, TAU, 16, Palette.ICE, 1.5, true)
		draw_line(m, m + Vector2.from_angle(me.rotation) * 8.0, Palette.ICE, 1.5, true)


## Where the baseline of a site's word is, below the spot (pixels of the 300-pixel picture): under the turret squares
## (which end 12 px below the spot), whose room the type (10 px at the 80% size, its top 9 px above the baseline, and its
## 1.5 px outline) must not reach into.
const WORD_DY := 24.0


## Write `text` (a SiteMarks word) in small type under minimap spot `m` on canvas item `ci`, centred, below the turret
## squares of a held site.
func _mini_word(ci: CanvasItem, m: Vector2, text: String) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	# The picture is scaled by the minimap's size: the type is made bigger below 100% so it never reads smaller than 8 pixels.
	var fs := maxi(8, int(ceil(8.0 / _s)))
	ci.draw_string_outline(font, m + Vector2(-40.0, WORD_DY), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, fs, 3, Palette.VOID)
	ci.draw_string(font, m + Vector2(-40.0, WORD_DY), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, fs, Palette.ICE)


## Draw a diamond of half-size `r` pixels at minimap spot `m`: filled in `col`, or
## only its outline.
func _diamond(m: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, 1.0, true)


## A line width in the 300-pixel base picture: `w` times the icon scale, never under 1 pixel.
func _w(w: float) -> float:
	return maxf(1.0, w * ICON_K)


## Draw a plus at minimap spot `m`: two lines, each `arm` long to each side of the middle, `width` wide, in `col`.
func _plus(m: Vector2, arm: float, width: float, col: Color) -> void:
	var a := arm * ICON_K
	draw_line(m + Vector2(-a, 0.0), m + Vector2(a, 0.0), col, _w(width))
	draw_line(m + Vector2(0.0, -a), m + Vector2(0.0, a), col, _w(width))


## Draw an X at minimap spot `m`: two lines, each `arm` long to each side of the middle, `width` wide, in `col`.
func _cross_x(m: Vector2, arm: float, width: float, col: Color) -> void:
	var a := arm * ICON_K
	draw_line(m + Vector2(-a, -a), m + Vector2(a, a), col, _w(width))
	draw_line(m + Vector2(-a, a), m + Vector2(a, -a), col, _w(width))


## The Scum's lopsided cross from their hull art (ScumShapes.RAIDER_TAPE): a long arm 7 pixels and a short one 4 pixels,
## both through the middle `m`, at `scale` of that size, `width` wide, in `col`, on canvas item `ci` (2 calls).
func _scum_cross(ci: CanvasItem, m: Vector2, scale: float, width: float, col: Color) -> void:
	var long_dir := Vector2(-0.76, 0.65)
	var short_dir := Vector2(-0.8, -0.6)
	var hl := 3.5 * scale * ICON_K
	var hs := 2.0 * scale * ICON_K
	ci.draw_line(m - long_dir * hl, m + long_dir * hl, col, _w(width))
	ci.draw_line(m - short_dir * hs, m + short_dir * hs, col, _w(width))


## Mark each of our own defense posts that is not standing: its diamond outline
## (at 0.6) with an X in it while its rebuild timer runs, and a plus in it once the
## admiral may rebuild it (never a plain hollow diamond: that is a Vhorr post now).
## Only the owner's team (and a spectator) sees this; the other team sees the
## post's fall in the news.
func _draw_post_sites(vt: int) -> void:
	for ps: PostSite in world.defense_posts.sites:
		if ps.state != PostSite.DESTROYED and ps.state != PostSite.READY:
			continue
		if vt >= 0 and ps.team != vt:
			continue
		var m := to_map(ps.pos)
		var col := Palette.with_alpha(Palette.team(ps.team), 0.6)
		_diamond(m, 4.2 * ICON_K, col, false)
		if ps.state == PostSite.READY:
			_plus(m, 1.8, 1.0, col)
		else:
			_cross_x(m, 1.4, 1.0, col)


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
