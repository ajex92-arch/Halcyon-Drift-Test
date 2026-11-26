class_name TargetCard
extends Control
## WHAT THIS IS: the card on the pilot's target (the "Frame" card): a square frame round the target whose four sides are its four
## shield zones, each with a bar that shows how full that zone is, and under it a small strip with the hull's outline, a few pips for
## its size and a hull bar. It tells the pilot which side of the target is open to shoot at. Drawing only: it reads the target and
## changes nothing in the game (no field of a Unit, a Ship, the shots or the World is written).
##
## HOW IT WORKS: it belongs to the HUD, covers the whole screen and lets the mouse through. The target is the unit the human's ship
## holds in ShipControls.target_id (TargetKeys). The card is live only while the human's team can see the target now
## (Unit.visible_to): a target that is held but out of sight gets NOTHING drawn, not even an empty frame, because a frame would show
## where an unseen unit is, and the target's old values are never read. Two small Node2D children keep the card's pictures, and
## each is drawn again only when its key changes (every shield fill in 64ths, the flash, the preset, the frame's side in whole
## pixels, the hull fill, the hull and size), the way ShipVisual keeps its arcs; most frames only move them:
##   - the FRAME child (the target's own frame, nose along +x) is moved to the target's place on the screen and turned to its heading
##     every frame without drawing again. It is a square of side 1.7 x the target's drawn length, 34 to 120 pixels. Each side is one
##     zone: side k faces ShieldArcs.CENTERS[k] and spans the angles ShieldZones.zone_for_local() gives that zone (the square's
##     shape is read from there, so a later change of the zone spans shows). A 1 pixel track (MIST) on each side stops 3 pixels short of
##     the corners; the zone's bar is centred on it, (side - 6) x the zone's fill long, 2 to 4 pixels wide by the zone's share of the
##     shield (the focus), SHIELD at 0.45 + 0.55 x fill; a 5 pixel nose tick in the team colour marks the front. A target with one shield
##     pool (shields null or single: minions, turrets, the mothership) shows all four sides as that one pool;
##   - the STRIP child (upright) is only moved: 32 pixels below the target's middle, 54 x 12 on a VOID backing: the hull's outline at 11
##     pixels (an Aurelian hull: AurelianPaint.outline(); a Vhorr hull: its CinderShapes table; any other unit a 4 pixel square), 1 to 4
##     pips of 3 x 3 pixels for the size classes small to capital (never a round dot; a structure or mothership gets one 8 x 3 bar) and a 20
##     x 4 hull bar in the target's team colour.
## Presets (Game.card_preset): Full = frame and strip; Compact = the frame alone; Minimal = the bare frame, its track only, as the mark
## on the target. Colours: the frame is the target's own team colour for its nose tick and hull bar; the shields are SHIELD, the bare
## Minimal frame is ICE; DANGER is never used. The only motion is the zone-broke flash: the broken side's bar flashes toward ICE and fades
## over 0.4 s, once for each break, and a break less than FLASH_GAP after the card's last flash is not drawn (so at most 3 a second). Room
## for the later section colours is left inside the frame, nothing is drawn there yet.
##
## WHO USES IT: Hud.setup() makes one after the ring and gives it the world. Not made in --sim-only runs. tests/ship_ring_check.gd checks it.

## The frame's side is this many times the target's drawn length, and is kept between FRAME_MIN and FRAME_MAX (pixels).
const FRAME_SCALE := 1.7
## The smallest frame side (pixels).
const FRAME_MIN := 34.0
## The biggest frame side (pixels).
const FRAME_MAX := 120.0
## A side's track stops this many pixels short of the corners; its colour strength.
const CORNER_GAP := 3.0
## How strong a side's track is (0 to 1).
const TRACK_ALPHA := 0.35
## The width of a zone's bar (pixels) at the smallest and the largest share of the shield (10% and 50%).
const BAR_MIN_W := 2.0
## The width of a zone's bar at a 50% share of the shield (pixels).
const BAR_MAX_W := 4.0
## The nose tick: its length and width (pixels).
const NOSE_LEN := 5.0
## The nose tick's width (pixels).
const NOSE_W := 1.5
## The strip: how far below the target's middle its top is, its size, and its backing's strength.
const STRIP_TOP := 32.0
## The strip's width (pixels).
const STRIP_W := 54.0
## The strip's height (pixels).
const STRIP_H := 12.0
## How strong the strip's backing is (0 to 1).
const STRIP_ALPHA := 0.6
## The outline's length in the strip (pixels).
const SIL_PX := 11.0
## A pip: its side and the gap between two (pixels); the structure bar's length.
const PIP := 3.0
## The gap between two pips (pixels).
const PIP_GAP := 1.0
## The length of the one bar a structure or mothership gets instead of pips (pixels).
const BAR_PIP_LEN := 8.0
## The hull bar: its length and height (pixels).
const HULL_BAR_W := 20.0
## The hull bar's height (pixels).
const HULL_BAR_H := 4.0
## How long a zone's flash lasts (seconds of match time), and the least time between the starts of two flashes.
const FLASH_SECS := 0.4
## The least time between the starts of two zone flashes (seconds of match time), so they never pass three a second.
const FLASH_GAP := 0.334
## The flash is drawn in this many steps (the picture is drawn again at each).
const FLASH_STEPS := 4

## The game world (set by setup()).
var world: World
## How many drawing commands the card's pictures hold now (0 when nothing is shown): the check reads it.
var drawn := 0
## How many times a picture has been drawn again, and how many zone flashes were started: the check reads them.
var redraws := 0
## How many zone flashes the card has started (the check reads it).
var flashes := 0
## The two pictures.
var _frame: Node2D
## The strip picture (an upright Node2D).
var _strip: Node2D
## Each picture's key (see HOW IT WORKS) and how many drawing commands its last drawing made.
var _frame_key := -1
## The strip picture's key: what it was last drawn for (-1 for never).
var _strip_key := -1
## How many drawing commands the frame picture's last drawing made.
var _frame_cmds := 0
## How many drawing commands the strip picture's last drawing made.
var _strip_cmds := 0
## What the frame picture shows (made when its key changes): the four fills, the four bar widths, the four flash levels (0 to 1), the
## side (pixels), the target's team and the preset.
var _fills := [0.0, 0.0, 0.0, 0.0]
## What the frame picture shows: the width of each zone's bar (pixels).
var _widths := [2.75, 2.75, 2.75, 2.75]
## What the frame picture shows: how strong each zone's flash is (0 to 1).
var _levels := [0.0, 0.0, 0.0, 0.0]
## What the frame picture shows: the frame's side (pixels, a whole number).
var _side := FRAME_MIN
## What the frame picture shows: the target's team (its colour).
var _team := 0
## What the picture shows: the preset (0 Full, 1 Compact, 2 Minimal).
var _preset := 0
## What the strip picture shows: the hull fill, the target's size class, hull id and whether it is a ship.
var _hull := 1.0
## What the strip picture shows: the target's size class.
var _size_class := 0
## What the strip picture shows: the target ship's hull id (its outline).
var _hull_id := ""
## What the strip picture shows: whether the target is a ship (a ship shows an outline, any other unit a small square).
var _is_ship := true
## The match time each zone's flash started (-99 for none), the card's last flash start, and whether each zone's break flash was running on
## the last frame.
var _flash_at := [-99.0, -99.0, -99.0, -99.0]
## The match time the card's last zone flash started (-99 for none).
var _last_flash := -99.0
## Per zone: was its break flash running on the last frame?
var _flash_was := [false, false, false, false]
## The uid of the target the flash memory belongs to (-1 for none).
var _target_uid := -1
## The silhouettes, by hull id and look: key -> PackedVector2Array of the outline scaled to SIL_PX, centred, nose to the right.
static var _sils := {}
## The half angle (radians) the front zone spans each side of the nose, read from ShieldZones.zone_for_local() once.
static var _front_half := -1.0


## Remember the world, cover the whole screen and let the mouse through. Hud.setup() calls this once.
func setup(w: World) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Node2D.new()
	_strip = Node2D.new()
	add_child(_frame)
	add_child(_strip)
	_frame.draw.connect(_draw_frame)
	_strip.draw.connect(_draw_strip)
	_frame.visible = false
	_strip.visible = false
	visible = true


## Every frame: find the target, show nothing unless the human's team sees it now, draw a picture again only when its key changed and
## move the pictures to the target.
func _process(_dt: float) -> void:
	if world == null:
		return
	var ship := TargetKeys.my_ship(world)
	var target := TargetKeys.held_unit(world, ship) if ship != null else null
	if target == null or not target.visible_to(world.human_team):
		_hide()
		if target == null:
			_target_uid = -1
		return
	if target.uid != _target_uid:
		_adopt(target)
	var xf := get_viewport().get_canvas_transform()
	var z := xf.get_scale().x
	var p := xf * target.global_position
	_preset = clampi(Game.card_preset, 0, Game.CARD_PRESETS.size() - 1)
	# The frame: its side, fills and flash levels make its key.
	var length := 2.0 * target.radius
	if target is Ship:
		length = float((target as Ship).def.get("length", 26.0))
	var drawn_len := maxf(length * z, ShipVisual.MIN_PX)
	var side := roundf(clampf(FRAME_SCALE * drawn_len, FRAME_MIN, FRAME_MAX))
	_watch_flash(target)
	var key := _frame_key_of(target, side)
	if key != _frame_key:
		_frame_key = key
		_side = side
		_team = target.team
		_frame.queue_redraw()
	# The strip (Full only): the hull fill, the size and the hull make its key.
	var strip_on := _preset == 0
	if strip_on:
		var skey := (int(clampf(target.hull_frac(), 0.0, 1.0) * 64.0)) | (target.size_class << 8) | (target.team << 12) | ((hash((target as Ship).hull_id if target is Ship else "") & 0xFFFFFF) << 16)
		if skey != _strip_key:
			_strip_key = skey
			_hull = float(skey & 0xFF) / 64.0
			_size_class = target.size_class
			_hull_id = (target as Ship).hull_id if target is Ship else ""
			_is_ship = target is Ship
			_strip.queue_redraw()
	_frame.visible = true
	_strip.visible = strip_on
	_frame.position = p
	_frame.rotation = target.rotation
	_strip.position = p
	drawn = _frame_cmds + (_strip_cmds if strip_on else 0)


## Show nothing: both pictures hidden, no commands. (Their kept pictures stay, and are drawn again only if their keys change.)
func _hide() -> void:
	if _frame != null:
		_frame.visible = false
		_strip.visible = false
	drawn = 0


## The target is new to the card: forget the last target's flash memory, taking its running flashes as already seen.
func _adopt(target: Unit) -> void:
	_target_uid = target.uid
	_flash_at = [-99.0, -99.0, -99.0, -99.0]
	_flash_was = [false, false, false, false]
	_last_flash = -99.0
	_frame_key = -1
	_strip_key = -1
	if target.shields != null and not target.shields.single:
		for k in 4:
			_flash_was[k] = target.shields.flash[k] > 0.0


## Watch the target's shield zones for a break: a zone's flash that starts after a frame without one starts the card's flash, unless the
## card's last flash began less than FLASH_GAP ago (then that break is not drawn).
func _watch_flash(target: Unit) -> void:
	var sh := target.shields
	if sh == null or sh.single:
		return
	for k in 4:
		var on: bool = sh.flash[k] > 0.0
		if on and not _flash_was[k]:
			if world.time - _last_flash >= FLASH_GAP:
				_flash_at[k] = world.time
				_last_flash = world.time
				flashes += 1
		_flash_was[k] = on


## The frame picture's key for `target` at frame side `side`: each zone's fill in 64ths and its flash step, the side in whole pixels, the
## preset and the team. Also sets the fills, widths and flash levels the picture will show.
func _frame_key_of(target: Unit, side: float) -> int:
	var sh := target.shields
	var parts := PackedInt32Array([int(side), _preset, target.team])
	for k in 4:
		var fill := 0.0
		var share := 0.25
		if sh != null and sh.max_total > 0.0:
			if sh.single:
				fill = clampf(sh.values[0] / sh.max_total, 0.0, 1.0)
			else:
				var cap := sh.cap(k)
				fill = clampf(sh.values[k] / cap, 0.0, 1.0) if cap > 0.0 else 0.0
				share = cap / sh.max_total
		var q := int(fill * 64.0)
		var level := clampf(1.0 - (world.time - float(_flash_at[k])) / FLASH_SECS, 0.0, 1.0)
		var step := int(ceilf(level * float(FLASH_STEPS)))
		_fills[k] = float(q) / 64.0
		_levels[k] = float(step) / float(FLASH_STEPS)
		_widths[k] = BAR_MIN_W + (BAR_MAX_W - BAR_MIN_W) * clampf((share - 0.1) / 0.4, 0.0, 1.0)
		parts.append(q)
		parts.append(step)
		parts.append(int((float(_widths[k]) - BAR_MIN_W) * 8.0))
	return hash(parts)


## The half angle (radians) the front zone spans each side of the nose, read from ShieldZones.zone_for_local() (45 degrees today).
static func front_half_angle() -> float:
	if _front_half < 0.0:
		var a := 0.0
		while a < PI and ShieldZones.zone_for_local(Vector2.from_angle(a)) == Rules.ZONE_FRONT:
			a += 0.0025
		# The edge lies between a - 0.0025 and a: narrow it down to a millionth of a radian.
		var lo := maxf(0.0, a - 0.0025)
		var hi := a
		for i in 24:
			var mid := (lo + hi) * 0.5
			if ShieldZones.zone_for_local(Vector2.from_angle(mid)) == Rules.ZONE_FRONT:
				lo = mid
			else:
				hi = mid
		_front_half = lo
	return _front_half


## Where side `k` of a frame with half width `h` lies, in the target's own frame (nose along +x): [the middle of the side, the direction
## along it]. Front and rear sides stand at x = +-h; the left and right sides at y = -+(h x tan of the front zone's half angle), which makes
## the frame a square while every zone spans 90 degrees.
static func side_of(k: int, h: float) -> Array:
	var d := Vector2.from_angle(float(ShieldArcs.CENTERS[k]))
	var reach := h if k == Rules.ZONE_FRONT or k == Rules.ZONE_REAR else h * tan(front_half_angle())
	return [d * reach, d.orthogonal()]


## Draw the frame picture (the child's `draw` signal): the track, a bar for each zone and the nose tick, by preset.
func _draw_frame() -> void:
	redraws += 1
	_frame_cmds = 0
	var h := _side * 0.5
	var bare := _preset == 2
	var track := PackedVector2Array()
	for k in 4:
		var s := side_of(k, h)
		var mid: Vector2 = s[0]
		var along: Vector2 = s[1]
		var half := _half_len(k, h) - CORNER_GAP
		track.append(mid + along * half)
		track.append(mid - along * half)
	_frame.draw_multiline(track, Palette.with_alpha(Palette.ICE, 0.85) if bare else Palette.with_alpha(Palette.MIST, TRACK_ALPHA), 1.0, true)
	_frame_cmds += 1
	if bare:
		return
	# A bar for each zone: as long as the zone is full (while it flashes, as long as the flash is strong), centred on its side.
	for k in 4:
		var fill := float(_fills[k])
		var level := float(_levels[k])
		var amount := maxf(fill, level)
		if amount <= 0.0:
			continue
		var s := side_of(k, h)
		var mid: Vector2 = s[0]
		var along: Vector2 = s[1]
		var half := (_half_len(k, h) - CORNER_GAP) * amount
		var col := Palette.SHIELD.lerp(Palette.ICE, level)
		_frame.draw_line(mid + along * half, mid - along * half, Palette.with_alpha(col, 0.45 + 0.55 * maxf(fill, level)), float(_widths[k]), true)
		_frame_cmds += 1
	# The nose tick: a short line out from the middle of the front side, in the team colour.
	var front := side_of(Rules.ZONE_FRONT, h)
	var nose: Vector2 = front[0]
	_frame.draw_line(nose, nose + Vector2.RIGHT * NOSE_LEN, Palette.team(_team), NOSE_W, true)
	_frame_cmds += 1


## Half the length of side `k` of a frame with half width `h`: h for the front and rear sides' span across, h x tan for the others.
static func _half_len(k: int, h: float) -> float:
	var vertical := k == Rules.ZONE_FRONT or k == Rules.ZONE_REAR
	return h * tan(front_half_angle()) if vertical else h


## Draw the strip picture (the child's `draw` signal): the backing, the outline, the pips and the hull bar.
func _draw_strip() -> void:
	redraws += 1
	_strip_cmds = 0
	var left := -STRIP_W * 0.5
	var mid_y := STRIP_TOP + STRIP_H * 0.5
	_strip.draw_rect(Rect2(left, STRIP_TOP, STRIP_W, STRIP_H), Palette.with_alpha(Palette.VOID, STRIP_ALPHA))
	_strip_cmds += 1
	var team_col := Palette.team(_team)
	# The outline (two commands: the fill and the edge), or a 4 pixel square for a unit that is not a ship.
	var sil_at := Vector2(left + 2.0 + SIL_PX * 0.5, mid_y)
	if _is_ship:
		var pts := silhouette(_hull_id, _team)
		if pts.size() >= 3:
			var moved := PackedVector2Array()
			for pt in pts:
				moved.append(sil_at + pt)
			_strip.draw_colored_polygon(moved, Palette.with_alpha(team_col, 0.4))
			moved.append(moved[0])
			_strip.draw_polyline(moved, team_col, 1.0, true)
			_strip_cmds += 2
	else:
		_strip.draw_rect(Rect2(sil_at - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), team_col)
		_strip_cmds += 1
	# The pips: 1 to 4 squares, or one bar for a structure or mothership (one command: each is a short thick line).
	var px := left + 2.0 + SIL_PX + 3.0
	var seg := PackedVector2Array()
	if _size_class >= Rules.SIZE_STRUCTURE:
		seg.append(Vector2(px, mid_y))
		seg.append(Vector2(px + BAR_PIP_LEN, mid_y))
	else:
		for i in pip_count(_size_class):
			seg.append(Vector2(px + float(i) * (PIP + PIP_GAP), mid_y))
			seg.append(Vector2(px + float(i) * (PIP + PIP_GAP) + PIP, mid_y))
	_strip.draw_multiline(seg, Palette.with_alpha(Palette.ICE, 0.85), PIP)
	_strip_cmds += 1
	# The hull bar: a VOID track and the hull fill in the team colour.
	var bx := STRIP_W * 0.5 - 2.0 - HULL_BAR_W
	_strip.draw_rect(Rect2(bx, mid_y - HULL_BAR_H * 0.5, HULL_BAR_W, HULL_BAR_H), Palette.VOID)
	_strip_cmds += 1
	if _hull > 0.0:
		_strip.draw_rect(Rect2(bx, mid_y - HULL_BAR_H * 0.5, HULL_BAR_W * clampf(_hull, 0.0, 1.0), HULL_BAR_H), team_col)
		_strip_cmds += 1


## How many pips the strip shows for size class `size_class`: 1 to 4 squares for small to capital ships, and one bar for a structure or
## a mothership.
static func pip_count(size_class: int) -> int:
	return 1 if size_class >= Rules.SIZE_STRUCTURE else clampi(size_class, 0, Rules.SIZE_CAPITAL) + 1


## The outline of hull `id` for a team's look, scaled so it is SIL_PX long, centred on the origin with the nose to the right. An
## Aurelian hull uses AurelianPaint.outline(); a Vhorr hull its CinderShapes table (the fighter's when the id is not there).
static func silhouette(id: String, team: int) -> PackedVector2Array:
	var vhorr := CinderPaint.alien(team)
	var key := "%s|%d" % [id, 1 if vhorr else 0]
	if _sils.has(key):
		return _sils[key]
	var raw: Array = []
	if vhorr:
		raw = (CinderShapes.HULLS.get(id, CinderShapes.HULLS[Ships.DEFAULT_HULL]) as Dictionary)["sil"]
	else:
		raw = AurelianPaint.outline(id)
	var out := PackedVector2Array()
	if raw.size() >= 3:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for pt: Vector2 in raw:
			lo = Vector2(minf(lo.x, pt.x), minf(lo.y, pt.y))
			hi = Vector2(maxf(hi.x, pt.x), maxf(hi.y, pt.y))
		var scale := SIL_PX / maxf(0.001, hi.x - lo.x)
		var mid := (lo + hi) * 0.5
		for pt: Vector2 in raw:
			out.append((pt - mid) * scale)
	_sils[key] = out
	return out
