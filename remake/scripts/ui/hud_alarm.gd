class_name HudAlarm
extends Control
## WHAT THIS IS: the warning for the pilot a Bomber is aiming at: a short alarm
## sound, and a small triangle at the edge of the screen that points toward the
## Bomber while its run is on. Drawing and sound only: it reads the game and
## changes nothing in it.
##
## HOW IT WORKS: it belongs to the HUD and covers the whole screen (the mouse
## passes through it; it is hidden whenever there is nothing to show).
##   - Ten times a second it looks at every enemy Bomber that is on a torpedo run
##     (Ship.run_on()) and asks whether any of the three lanes of its fan, as
##     they would fly if it launched now, will cross the hit circle of the ship
##     the human pilot flies, within the torpedoes' reach (a rock in the way
##     stops a lane). The first time that is true in a run, the alarm plays once
##     ("alarm" cue, two short tones) and the Bomber is marked. A run is told
##     from the next by RunGun.serial, so each run alarms at most once.
##   - A marked Bomber gets the triangle for as long as its run is on (and the pilot flies). It sits at
##     the edge of the screen on the line from the middle of the screen to the
##     Bomber, in the Bomber's team colour, with its point toward the Bomber.
## Only the human's own ship is warned: computer pilots have no ears, and
## turrets and motherships do not count as pilot ships. A human who is not
## flying (docked, dead, an Admiral with no ship in the field) sees nothing.
##   - S7A, edge wedges (#107, part two; one kind): when the human's own mothership comes under attack (the World's event stream,
##     Events.rts_event, kind "mothership_under_attack" of the human's team, with a place) a wedge stands at the edge of the screen
##     toward that place, but only while the place is off the screen. It stands while the human team's defend call is on (the game's
##     own "defend the mothership" call, which runs on while the attack goes on) and for WEDGE_LIFE_S seconds of match time more
##     after the call goes off; it is made by the record, or by the renewal that follows the mothership while the call is on. It is a
##     filled DANGER wedge pointing at the place, with the upright danger sign inside it (the colour never stands alone), steady, and
##     it fades out once in its last WEDGE_FADE_S seconds: it never blinks. At most WEDGE_MAX are drawn; the later ones fold into the last one
##     as a "+N" beside it. The Bomber triangles keep their own drawing and are not counted in the four. wedge_layout() works out
##     where each wedge goes from plain numbers, so a check can call it. Other kinds (a capital about to fire, a wingman calling, a
##     seeker) and the torpedo wedge (the ship ring already draws that arrowhead) are not here.
##
## WHO USES IT: Hud.setup() makes one and gives it the world. Sfx plays the
## "alarm" cue. Not made in --sim-only runs (they have no HUD). tests/edge_wedge_check.gd checks the wedges.

## Seconds between two looks for a lane that will cross the pilot's ship.
const LOOK_EVERY := 0.1
## How far in from the edge of the screen the triangle's middle sits, in pixels.
const MARGIN := 30.0
## How big the triangle is, in pixels from its middle to its point.
const SIZE := 14.0
## S7A: the seconds an edge wedge stays after its last renewal, which is after the attack call went off (seconds of match time). The
## number is the lead's call.
const WEDGE_LIFE_S := 8.0
## S7A: the last seconds of a wedge's life in which it fades out (steadily, once; it never blinks).
const WEDGE_FADE_S := 1.0
## S7A: the most wedges drawn at once; a fifth and later fold into the last one as a "+N" count.
const WEDGE_MAX := 4
## S7A: a second record for a place within this many world units of a live wedge renews that wedge instead of adding another.
const WEDGE_SAME := 60.0
## S7A: the wedge's strength (the Bomber triangle's is 0.9).
const WEDGE_ALPHA := 0.9
## S7A: the size of the "+N" text beside the last wedge (pixels).
const WEDGE_TEXT_PX := 12

## The game world (set by setup()).
var world: World
## Seconds until the next look.
var _t := 0.0
## The run each Bomber last alarmed for: ship uid -> RunGun.serial.
var _alarmed := {}
## The Bombers marked now (Ship nodes).
var _marks: Array = []
## S7A: the edge wedges now, oldest first: one Dictionary for each, {"pos" (Vector2, world units), "t0" (match time it was made or
## last renewed)}.
var _wedges: Array = []
## S7A: how many Bomber triangles and how many wedges the last _draw() drew (a check reads them).
var drawn_bombers := 0
## S7A: how many wedges the last _draw() drew.
var drawn_wedges := 0
## S7A fix: the strength the danger sign was drawn with on the wedge drawn last by the last _draw() (1 full, 0 gone; -1 when no wedge was drawn).
var drawn_sign_alpha := -1.0
## S7A fix: the strength of the wedge drawn last by the last _draw() (1 full, 0 gone; -1 when no wedge was drawn).
var drawn_wedge_alpha := -1.0


## Remember the world, cover the whole screen and let the mouse through. Hud.setup()
## calls this once. S7A: it also listens to the World's event stream for the mothership under attack.
func setup(w: World) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if not Events.rts_event.is_connected(_on_rts_event):
		Events.rts_event.connect(_on_rts_event)


## S7A: stop listening when the alarm leaves the tree.
func _exit_tree() -> void:
	if Events.rts_event.is_connected(_on_rts_event):
		Events.rts_event.disconnect(_on_rts_event)


## Every frame: look again every LOOK_EVERY seconds, drop the marks whose run is
## over, and redraw while there is a mark (or an edge wedge).
func _process(dt: float) -> void:
	if world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = LOOK_EVERY
		_look()
	# A pilot who is not flying (dead, docked) has no ship to warn: no marks, no wedges.
	if not _flying():
		_marks.clear()
		_wedges.clear()
	_renew_while_attacked()
	for i in range(_marks.size() - 1, -1, -1):
		var b = _marks[i]
		if not is_instance_valid(b) or not (b as Ship).alive or not (b as Ship).run_on():
			_marks.remove_at(i)
	prune_wedges(world.time)
	visible = not _marks.is_empty() or not _wedges.is_empty()
	if visible:
		queue_redraw()


## S7A: does the human fly a living ship now (the rule for every mark and wedge here)?
func _flying() -> bool:
	var me := world.human
	return not (me == null or me.state != "flying" or me.ship == null or not is_instance_valid(me.ship) or not me.ship.alive)


## S7A: is the human team's defend call on now (the game's own call for an attack on its mothership)? False when the human's team
## number has no team in the world.
func _attacked() -> bool:
	var t := world.human_team
	if t < 0 or t >= world.teams.size():
		return false
	var ts: TeamState = world.teams[t]
	return ts != null and ts.defending(world.time)


## S7A: while the human team's defend call is on and the human flies, keep one wedge toward the human's own mothership: a wedge
## within WEDGE_SAME of it is renewed (it follows the mothership), otherwise one is added; a wedge elsewhere is not renewed and runs
## out. Nothing when the call is off, the human is not flying or the team has no mothership.
func _renew_while_attacked() -> void:
	if not _attacked() or not _flying():
		return
	var ms := world.mothership(world.human_team)
	if ms == null or not is_instance_valid(ms):
		return
	add_wedge(Vector2(RtsEvents.point_of(ms.global_position)))


## S7A: the World's event stream: a "mothership_under_attack" record of the human's team with a place makes a wedge there. A record
## with no place (the team has no mothership: RtsEvents sends null) adds nothing. The place is a Vector2i in the record.
func _on_rts_event(ev: Dictionary) -> void:
	if world == null or str(ev.get("kind", "")) != "mothership_under_attack" or int(ev.get("team", -1)) != world.human_team:
		return
	var p: Variant = ev.get("pos", null)
	if p is Vector2i:
		add_wedge(Vector2(p as Vector2i))
	elif p is Vector2:
		add_wedge(p as Vector2)


## S7A: put a wedge at world place `pos` now (a place within WEDGE_SAME of a live wedge renews that one). Nothing when the human is
## not flying.
func add_wedge(pos: Vector2) -> void:
	if world == null or not _flying():
		return
	for w: Dictionary in _wedges:
		if (w["pos"] as Vector2).distance_to(pos) <= WEDGE_SAME:
			w["pos"] = pos
			w["t0"] = world.time
			return
	_wedges.append({"pos": pos, "t0": world.time})


## S7A: drop the wedges whose WEDGE_LIFE_S is over at match time `now`.
func prune_wedges(now: float) -> void:
	for i in range(_wedges.size() - 1, -1, -1):
		if now - float((_wedges[i] as Dictionary)["t0"]) >= WEDGE_LIFE_S:
			_wedges.remove_at(i)


## S7A: the wedges at match time `now` as the layout takes them: one Dictionary for each live wedge, oldest first, {"at" (the place
## on the screen under canvas transform `xf`), "alpha" (1, falling in a straight line to 0 over the last WEDGE_FADE_S seconds)}.
func wedge_entries(xf: Transform2D, now: float) -> Array:
	var out: Array = []
	for w: Dictionary in _wedges:
		var left := WEDGE_LIFE_S - (now - float(w["t0"]))
		if left <= 0.0:
			continue
		out.append({"at": xf * (w["pos"] as Vector2), "alpha": clampf(left / WEDGE_FADE_S, 0.0, 1.0)})
	return out


## S7A: where the wedges go. `list` is entries as wedge_entries() makes them ({"at", "alpha"}), `centre` the middle of the screen
## (so the screen is the rectangle from the origin to twice `centre`) and `room` the half sizes of the rectangle inside the margin
## that the wedge walks out to. An entry whose place is on the screen gets no wedge. The first WEDGE_MAX of the rest get one each,
## in order; any later ones fold into the last wedge, which carries their number in "more". Each wedge is a Dictionary {"at" (the
## wedge's middle, on the edge walk), "dir" (the unit direction from the middle of the screen to the place), "alpha", "more"}.
static func wedge_layout(list: Array, centre: Vector2, room: Vector2) -> Array:
	var out: Array = []
	var screen := Rect2(Vector2.ZERO, centre * 2.0)
	var extra := 0
	for e: Dictionary in list:
		var at: Vector2 = e["at"]
		if screen.has_point(at):
			continue
		var dir := at - centre
		if dir.length() < 1.0:
			continue
		if out.size() >= WEDGE_MAX:
			extra += 1
			continue
		dir = dir.normalized()
		var k := minf(room.x / maxf(absf(dir.x), 0.0001), room.y / maxf(absf(dir.y), 0.0001))
		out.append({"at": centre + dir * k, "dir": dir, "alpha": float(e["alpha"]), "more": 0})
	if extra > 0 and not out.is_empty():
		(out[out.size() - 1] as Dictionary)["more"] = extra
	return out


## Look at every enemy Bomber on a run: the first time a lane of its fan will cross
## the hit circle of the human's ship in a run, sound the alarm and mark it.
func _look() -> void:
	var me := world.human
	if me == null or me.state != "flying" or me.ship == null or not is_instance_valid(me.ship) or not me.ship.alive:
		return
	var target: Ship = me.ship
	for b: Ship in world.ships:
		if not b.alive or b.run_mount == null or b.team == target.team or not b.run_on():
			continue
		var serial := b.run_mount.run.serial
		if int(_alarmed.get(b.uid, -1)) == serial:
			continue
		if _lane_crosses(b, target):
			_alarmed[b.uid] = serial
			_marks.append(b)
			Events.cue.emit("alarm", Vector2.ZERO)


## Will a lane of Bomber `b`'s fan, if it launched now, cross `target`'s hit circle
## within the torpedoes' reach? The torpedo's own radius counts as part of the
## circle.
func _lane_crosses(b: Ship, target: Ship) -> bool:
	var m := b.run_mount
	var life := float(m.def["life"]) * b.range_mult
	var radius := float(m.def.get("radius", 3.0))
	for l: Array in RunFan.lanes(m, b.fan_points):
		var from: Vector2 = l[0]
		var vel: Vector2 = l[1]
		var unit := vel.normalized()
		var length := vel.length() * life
		var rock := world.asteroids.segment_hit(from, from + unit * length, radius)
		if not rock.is_empty():
			length *= clampf(float(rock["t"]), 0.0, 1.0)
		if Util.seg_hits_circle(from, from + unit * length, target.global_position, target.hit_radius() + radius):
			return true
	return false


## Draw a triangle for each marked Bomber at the edge of the screen, pointing at it.
func _draw() -> void:
	var xf := get_viewport().get_canvas_transform()
	var centre := size * 0.5
	drawn_bombers = 0
	drawn_wedges = 0
	drawn_sign_alpha = -1.0
	drawn_wedge_alpha = -1.0
	for b: Ship in _marks:
		if not is_instance_valid(b):
			continue
		# The Bomber on the screen, and the direction from the middle to it.
		var on_screen: Vector2 = xf * b.global_position
		var dir := on_screen - centre
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		# Walk out along that direction to the edge of the room inside the margin.
		var room := centre - Vector2(MARGIN, MARGIN)
		var k := minf(room.x / maxf(absf(dir.x), 0.0001), room.y / maxf(absf(dir.y), 0.0001))
		var at := centre + dir * k
		var side := dir.orthogonal()
		var tri := PackedVector2Array([at + dir * SIZE, at - dir * SIZE * 0.6 + side * SIZE * 0.7, at - dir * SIZE * 0.6 - side * SIZE * 0.7])
		draw_colored_polygon(tri, Palette.with_alpha(Palette.bolt(b.team), 0.9))
		var closed := tri.duplicate()
		closed.append(tri[0])
		draw_polyline(closed, Palette.with_alpha(Palette.VOID, 0.9), 2.0, true)
		drawn_bombers += 1
	# S7A: the edge wedges (steady, in the danger colour, each with the upright danger sign; never blinking).
	if world != null and not _wedges.is_empty():
		var room := centre - Vector2(MARGIN, MARGIN)
		for w: Dictionary in wedge_layout(wedge_entries(xf, world.time), centre, room):
			_draw_wedge(w)
			drawn_wedges += 1


## S7A: draw one wedge from wedge_layout(): a filled DANGER triangle with its point toward the place, a VOID outline, the upright danger
## sign inward of it, and the "+N" count of the wedges folded into it beside it.
func _draw_wedge(w: Dictionary) -> void:
	var at: Vector2 = w["at"]
	var dir: Vector2 = w["dir"]
	var a := float(w["alpha"])
	var side := dir.orthogonal()
	var tri := PackedVector2Array([at + dir * SIZE, at - dir * SIZE * 0.6 + side * SIZE * 0.7, at - dir * SIZE * 0.6 - side * SIZE * 0.7])
	draw_colored_polygon(tri, Palette.with_alpha(Palette.DANGER, WEDGE_ALPHA * a))
	var closed := tri.duplicate()
	closed.append(tri[0])
	draw_polyline(closed, Palette.with_alpha(Palette.VOID, 0.9 * a), 2.0, true)
	# The danger sign always goes with the danger colour; it sits inward of the wedge, toward the middle of the screen.
	# The sign fades with the wedge (the same strength), so the colour never fades alone.
	Glyphs.danger(self, at - dir * SIZE * 1.9, Glyphs.SIDE, a)
	drawn_wedge_alpha = a
	drawn_sign_alpha = a
	var more := int(w["more"])
	if more > 0:
		var font := ThemeDB.fallback_font
		var text := "+%d" % more
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, WEDGE_TEXT_PX).x
		var origin := at + side * (SIZE * 1.2) + Vector2(-width * 0.5, float(WEDGE_TEXT_PX) * 0.35)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, WEDGE_TEXT_PX, Palette.with_alpha(Palette.ICE, a))
