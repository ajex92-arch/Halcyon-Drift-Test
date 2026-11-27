class_name IconLayer
extends Node2D
## WHAT THIS IS: the far-zoom icon layer (RT6 C1, decisions 7 and 8). When the view is wider than the icon line (16,000 world
## units by default, which the player may move between 11,000 and 30,000 in the pause menu; there is no off switch) the ships are
## drawn as small flat class silhouettes of a constant size on the screen, one for each bought squadron or big ship, instead
## of their full drawings. Motherships and structures keep their own pictures. The minimap keeps its discs (decision 8).
##
## HOW IT WORKS: CommandOverlay makes one and puts it under itself (z_index -1, so the overlay's own marks stay above it), in the
## world, so positions are world positions. Every frame it works out the view's width (the viewport's width / the camera zoom)
## and whether the icons are on: on at or above `line_w`, off again only below line_w * (1 - RtsUiCalls.ICON_GAP), and in
## between it keeps what it was, so a view resting on the line never flickers. While on it takes a snapshot of what to
## draw (one record for each squadron at the middle of its ships that the viewer sees, with a pip for each ship of the
## squadron, lit if alive; one for each big ship; a small disc for a pilot's ship, at 70% for a wingman; a small mark for a
## minion) and draws it once, with fixed point lists and no node for any icon.
## The shapes (one for each class, never rotated, never the reserved ones):
##   chevron   Scout, Fighter, Lance (strike craft)       10 x 9
##   bowtie    Bomber                                      11 x 8
##   plus      Logistics, Support (corvettes)              10 x 10
##   hex_s     Flak, Ion (frigates)                        12 x 8
##   hex_l     Destroyer                                   20 x 7
##   hex_xl    Battlecruiser                               25 x 8.6
## Aurelian (team 0) is solid with a 1 px dark edge; Vhorr is hollow: a dark core inside a 1.4 px line in the team colour.
## Selected squadrons get four light corner brackets. The ships' own painters (ShipVisual, UnitVisual) hand over with one line
## each, takes_over(): while the layer is on they draw nothing and keep no picture up to date. The layer also sets the
## "Visual" node of each ship and minion hidden or shown the moment it switches, so a paused match changes at once too.
## It only reads the match; the simulation never reads it. No tween or timer.
##
## WHO USES IT: CommandOverlay (makes it), ShipVisual and UnitVisual (takes_over), the pause menu (the line row),
## tests/icon_layer_check.gd.

## The smallest and the largest icon line (world units across) and the step of the pause menu's row.
const LINE_MIN := 11000
const LINE_MAX := 30000
const LINE_STEP := 1000
## The class shapes: name -> {"fill": [polygons], "edge": the closed outline, "h": half the height (the pips go under it)}.
## The points are screen pixels from the icon's middle.
const SHAPES := {
	"chevron": {"fill": [[Vector2(0, -4.5), Vector2(5, 4.5), Vector2(0, 1.5), Vector2(-5, 4.5)]],
		"edge": [Vector2(0, -4.5), Vector2(5, 4.5), Vector2(0, 1.5), Vector2(-5, 4.5), Vector2(0, -4.5)], "h": 4.5, "w": 5.0},
	"bowtie": {"fill": [[Vector2(-5.5, -4), Vector2(0, 0), Vector2(-5.5, 4)], [Vector2(5.5, -4), Vector2(0, 0), Vector2(5.5, 4)]],
		"edge": [Vector2(-5.5, -4), Vector2(0, 0), Vector2(5.5, -4), Vector2(5.5, 4), Vector2(0, 0), Vector2(-5.5, 4), Vector2(-5.5, -4)], "h": 4.0, "w": 5.5},
	"plus": {"fill": [[Vector2(-1.7, -5), Vector2(1.7, -5), Vector2(1.7, -1.7), Vector2(5, -1.7), Vector2(5, 1.7), Vector2(1.7, 1.7),
			Vector2(1.7, 5), Vector2(-1.7, 5), Vector2(-1.7, 1.7), Vector2(-5, 1.7), Vector2(-5, -1.7), Vector2(-1.7, -1.7)]],
		"edge": [Vector2(-1.7, -5), Vector2(1.7, -5), Vector2(1.7, -1.7), Vector2(5, -1.7), Vector2(5, 1.7), Vector2(1.7, 1.7),
			Vector2(1.7, 5), Vector2(-1.7, 5), Vector2(-1.7, 1.7), Vector2(-5, 1.7), Vector2(-5, -1.7), Vector2(-1.7, -1.7), Vector2(-1.7, -5)], "h": 5.0, "w": 5.0},
	"hex_s": {"fill": [[Vector2(-6, 0), Vector2(-3.5, -4), Vector2(3.5, -4), Vector2(6, 0), Vector2(3.5, 4), Vector2(-3.5, 4)]],
		"edge": [Vector2(-6, 0), Vector2(-3.5, -4), Vector2(3.5, -4), Vector2(6, 0), Vector2(3.5, 4), Vector2(-3.5, 4), Vector2(-6, 0)], "h": 4.0, "w": 6.0},
	"hex_l": {"fill": [[Vector2(-10, 0), Vector2(-6.5, -3.5), Vector2(6.5, -3.5), Vector2(10, 0), Vector2(6.5, 3.5), Vector2(-6.5, 3.5)]],
		"edge": [Vector2(-10, 0), Vector2(-6.5, -3.5), Vector2(6.5, -3.5), Vector2(10, 0), Vector2(6.5, 3.5), Vector2(-6.5, 3.5), Vector2(-10, 0)], "h": 3.5, "w": 10.0},
	"hex_xl": {"fill": [[Vector2(-12.5, 0), Vector2(-8, -4.3), Vector2(8, -4.3), Vector2(12.5, 0), Vector2(8, 4.3), Vector2(-8, 4.3)]],
		"edge": [Vector2(-12.5, 0), Vector2(-8, -4.3), Vector2(8, -4.3), Vector2(12.5, 0), Vector2(8, 4.3), Vector2(-8, 4.3), Vector2(-12.5, 0)], "h": 4.3, "w": 12.5},
}
## The radius (screen pixels) of a pilot's disc, a wingman's (70%), and of a minion's mark.
const PILOT_R := 3.3
const WING_R := 2.3
const MINION_R := 2.2

## The icon line now (world units across the view): RtsUiCalls.ICON_VIEW_W until the player moves it. Static, so the pause menu
## sets it without a node. Saved in the [game] section of the settings file.
static var line_w: int = RtsUiCalls.ICON_VIEW_W
## Are the icons on now? (Static: ShipVisual and UnitVisual read it every frame through takes_over().)
static var active := false
static var _prefs_read := false

var world: World
var overlay: CommandOverlay
## The snapshot of what the next _draw() draws: records [kind, x, y, team, shape, alive, max, selected] (kind: 0 squadron or
## big ship, 1 pilot, 2 wingman, 3 minion).
var _items: Array = []
## The camera zoom at the snapshot (the icons are drawn 1 / zoom world units to the pixel).
var _zoom := 1.0
## How many icons the last _draw() drew (the check reads it).
var icons_drawn := 0
## The view's width in world units at the last frame.
var view_w := 0.0


## Read the saved line once. Not in a test run (--auto or --test): those never touch the profile.
static func read_prefs() -> void:
	if _prefs_read:
		return
	_prefs_read = true
	if Game.opt("auto", false) or Game.opt("test", "") != "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(Game.SETTINGS_FILE) != OK:
		return
	var v: Variant = cfg.get_value("game", "icon_line", RtsUiCalls.ICON_VIEW_W)
	line_w = clamp_line(int(v)) if typeof(v) == TYPE_INT else RtsUiCalls.ICON_VIEW_W


## `w` world units kept inside the allowed range and rounded to a step.
static func clamp_line(w: int) -> int:
	var lo := int(RtsUiCalls.ICON_VIEW_RANGE[0])
	var hi := int(RtsUiCalls.ICON_VIEW_RANGE[1])
	return clampi(int(round(float(w) / float(LINE_STEP))) * LINE_STEP, lo, hi)


## Move the icon line to `w` (kept in range) and, with `save`, remember it through Game._remember.
static func set_line(w: int, save: bool = true) -> void:
	line_w = clamp_line(w)
	if save:
		Game._remember("icon_line", line_w, "The icon line")


## Should the icons be on for a view `width` units across, when they were `was_on`? On from the line, off below the line less
## the gap, unchanged in between.
static func decide(width: float, was_on: bool, line: float = float(line_w)) -> bool:
	if width >= line:
		return true
	if width < line * (1.0 - RtsUiCalls.ICON_GAP):
		return false
	return was_on


## The shape name of hull `hull_id` ("chevron" for one this table does not know).
static func shape_of(hull_id: String) -> String:
	return str(HullTables.ICON_SHAPES.get(hull_id, "chevron"))


## The one line of ShipVisual and UnitVisual: true while the icon layer draws this unit instead of `v` (the unit's painter),
## which is then hidden. Motherships and structures are never handed over.
static func takes_over(v: CanvasItem, u: Unit) -> bool:
	var want := active and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION)
	if v.visible == want:
		v.visible = not want
	return want


## Remember the world and the overlay (CommandOverlay.setup() makes the layer and calls this).
func setup(w: World, ov: CommandOverlay) -> void:
	world = w
	overlay = ov
	read_prefs()
	active = false
	z_index = -1


func _process(_dt: float) -> void:
	if world == null or world.camera == null:
		return
	var cam := world.camera
	_zoom = maxf(0.0001, cam.zoom.x)
	view_w = get_viewport_rect().size.x / _zoom
	var on := decide(view_w, active)
	if on != active:
		active = on
		_hand_over(on)
	if active:
		_snapshot()
		queue_redraw()
	elif not _items.is_empty():
		_items.clear()
		queue_redraw()


## Hide (or show) the painter of every ship and minion that exists now. New ones are kept the same by takes_over().
func _hand_over(on: bool) -> void:
	for u: Unit in world.units:
		if u == null or not is_instance_valid(u) or not (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION):
			continue
		var v := u.get_node_or_null("Visual") as CanvasItem
		if v != null:
			v.visible = not on


## The records to draw: see _items.
func _snapshot() -> void:
	_items.clear()
	var sel: Array = overlay.sel_squads if overlay != null else []
	var bought := {}
	for rec: Squad in world.squads.values():
		if rec.kind != "squadron" and rec.kind != "ship":
			continue
		var sum := Vector2.ZERO
		var n := 0
		for uid: int in rec.member_uids:
			var u: Variant = world.by_uid.get(uid)
			if u == null or not is_instance_valid(u) or not (u as Unit).alive or not (u is Ship):
				continue
			bought[uid] = true
			if (u as Unit).visible:
				sum += (u as Unit).global_position
				n += 1
		if n == 0:
			continue
		var centre := sum / float(n)
		_items.append([0, centre.x, centre.y, rec.team, shape_of(rec.hull_id), n, rec.max_members if rec.kind == "squadron" else 0, sel.has(rec.id)])
	for u: Unit in world.units:
		if u == null or not is_instance_valid(u) or not u.alive or not u.visible:
			continue
		if u.kind == Unit.K_SHIP:
			if bought.has(u.uid):
				continue
			var crew := (u as Ship).profile
			var wing := crew != null and crew.slot >= Squads.CREW_SLOT_BASE
			_items.append([2 if wing else 1, u.global_position.x, u.global_position.y, u.team, "", 1, 0, false])
		elif u.kind == Unit.K_MINION:
			_items.append([3, u.global_position.x, u.global_position.y, u.team, "", 1, 0, false])


## How many records the snapshot holds now, by kind (0 squadrons and big ships, 1 pilots, 2 wingmen, 3 minions).
func count_of(kind: int) -> int:
	var n := 0
	for it: Array in _items:
		if int(it[0]) == kind:
			n += 1
	return n


## The snapshot (the check reads it).
func items() -> Array:
	return _items


func _draw() -> void:
	icons_drawn = 0
	if not active:
		return
	var inv := 1.0 / _zoom
	for it: Array in _items:
		draw_set_transform(Vector2(float(it[1]), float(it[2])), 0.0, Vector2(inv, inv))
		var team := int(it[3])
		var col := Palette.team(team)
		match int(it[0]):
			0:
				_draw_class(str(it[4]), team, col, int(it[5]), int(it[6]), bool(it[7]))
			1:
				_draw_disc(PILOT_R, team, col)
			2:
				_draw_disc(WING_R, team, col)
			3:
				_draw_mark(team, col)
		icons_drawn += 1
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One class silhouette at the transform's origin (pixels), its pips and its selection brackets.
func _draw_class(shape: String, team: int, col: Color, alive: int, most: int, selected: bool) -> void:
	var s: Dictionary = SHAPES[shape]
	var solid := team == Rules.HALCYON
	for poly: Array in s["fill"]:
		draw_colored_polygon(PackedVector2Array(poly), col if solid else Palette.VOID)
	var edge := PackedVector2Array(s["edge"] as Array)
	draw_polyline(edge, Palette.VOID if solid else col, 1.0 if solid else 1.4, true)
	var h := float(s["h"])
	for i in most:
		var x := (float(i) - float(most - 1) * 0.5) * 4.0
		draw_circle(Vector2(x, h + 3.5), 1.2, col if i < alive else Palette.with_alpha(col, 0.3))
	if selected:
		var w := float(s["w"]) + 2.5
		var below := h + (6.5 if most > 0 else 2.5)
		_brackets(Rect2(Vector2(-w, -h - 2.5), Vector2(w * 2.0, below + h + 2.5)))


## Four light corner brackets round `r` (pixels).
func _brackets(r: Rect2) -> void:
	var c := Palette.ICE
	var a := 3.0
	var tl := r.position
	var br := r.end
	var tr := Vector2(br.x, tl.y)
	var bl := Vector2(tl.x, br.y)
	draw_polyline(PackedVector2Array([tl + Vector2(0, a), tl, tl + Vector2(a, 0)]), c, 1.0)
	draw_polyline(PackedVector2Array([tr + Vector2(-a, 0), tr, tr + Vector2(0, a)]), c, 1.0)
	draw_polyline(PackedVector2Array([bl + Vector2(0, -a), bl, bl + Vector2(a, 0)]), c, 1.0)
	draw_polyline(PackedVector2Array([br + Vector2(-a, 0), br, br + Vector2(0, -a)]), c, 1.0)


## A pilot's disc (or a wingman's): Aurelian solid with a dark edge, Vhorr a ring round a dark core.
func _draw_disc(r: float, team: int, col: Color) -> void:
	if team == Rules.HALCYON:
		draw_circle(Vector2.ZERO, r, col)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 12, Palette.VOID, 1.0, true)
	else:
		draw_circle(Vector2.ZERO, r, Palette.VOID)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 12, col, 1.4, true)


## A minion's mark: Aurelian a small disc, Vhorr a small point-down triangle (the teams' map marks).
func _draw_mark(team: int, col: Color) -> void:
	if team == Rules.HALCYON:
		draw_circle(Vector2.ZERO, MINION_R, col)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-2.5, -2.0), Vector2(2.5, -2.0), Vector2(0.0, 2.5)]), col)
