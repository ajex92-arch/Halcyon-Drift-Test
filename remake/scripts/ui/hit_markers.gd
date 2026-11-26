class_name HitMarkers
extends Control
## WHAT THIS IS: the hit markers (#111, the picture half; the sound is a later stage's): a small cross that shows the pilot where a
## shot of theirs landed, in three strengths so the player can tell a shot the shields took from one that reached the hull from one
## that broke a shield zone. Drawing only: it listens to Events.hit_landed and changes nothing in the game (no field of a Unit, a
## Ship or the World is written).
##
## HOW IT WORKS: it belongs to the HUD, covers the whole screen and lets the mouse through (the shape of HudAlarm). Combat sends
## Events.hit_landed(target, info, hull_dmg, zone_broke) for every applied hit; on_hit() keeps only the hits whose source is the
## ship the human flies, and only while the human flies. The kind of the marker follows the hit: "shield" (the hull took nothing: the
## shields soaked it), "hull" (the hull took damage) and "zone" (the hit broke a shield zone: the strongest, drawn larger, wider and
## brighter than the others). Where it goes: a hit on a small craft is drawn at the pointer (where the player is aiming, the eye is
## already there); a hit on anything bigger is drawn where the fire struck, the point on the target's hit circle on the line from the
## shooter to the target, by the canvas transform (so it follows the camera). A marker lives LIFE_S seconds of match time, fading out
## in a straight line: it never blinks. FLASH RULE: a marker that would start less than GAP_MS after the last one is not drawn, so
## the markers appear at most three times a second; the one exception is a "zone" marker inside that gap, which replaces a weaker
## marker (and does not start the gap again). Nothing is timed: no tween, no timer; the markers' ages are read from the match
## clock in _process().
## A marker is a Dictionary {"kind", "pos" (Vector2), "screen" (true: pos is a place on the screen, false: a world place), "t0"
## (match time it started)}.
##
## WHO USES IT: Hud.setup() makes one and gives it the world, before the alarm so the alarm draws over it. Combat sends the hits.
## Not made in --sim-only runs. tests/hit_marker_check.gd checks it.

## The three kinds, weakest first.
const KIND_SHIELD := "shield"
## The hull took damage.
const KIND_HULL := "hull"
## A shield zone broke in the hit.
const KIND_ZONE := "zone"
## How long a marker stays (seconds of match time).
const LIFE_S := 0.4
## The least time (milliseconds of match time) between the starts of two markers: at most three a second (the flash rule).
const GAP_MS := 334
## How far from the centre the cross's strokes start and end, for each kind (pixels): the zone marker is the biggest.
const R_IN := {"shield": 4.0, "hull": 4.0, "zone": 5.0}
## The far end of the strokes for each kind (pixels).
const R_OUT := {"shield": 9.0, "hull": 12.0, "zone": 18.0}
## The width of the strokes for each kind (pixels).
const WIDTH := {"shield": 1.5, "hull": 2.5, "zone": 3.5}
## The most markers kept at once (life 0.4 s and a gap of 334 ms leave two; this is a ceiling for a clock that jumps).
const KEEP := 4

## The game world (set by setup()).
var world: World
## The markers now, oldest first (see HOW IT WORKS).
var markers: Array = []
## The match time (milliseconds) the last marker started, for the gap.
var _last_ms := -1.0e12
## How many markers the last _draw() drew (a check reads it).
var drawn := 0


## Remember the world, cover the whole screen, let the mouse through and listen to the hits. Hud.setup() calls this once.
func setup(w: World) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if not Events.hit_landed.is_connected(on_hit):
		Events.hit_landed.connect(on_hit)


## Stop listening when the markers leave the tree.
func _exit_tree() -> void:
	if Events.hit_landed.is_connected(on_hit):
		Events.hit_landed.disconnect(on_hit)


## Forget every marker and the gap (a check starts clean with it).
func clear() -> void:
	markers.clear()
	_last_ms = -1.0e12


## The kind a hit makes: "zone" when it broke a shield zone, else "hull" when the hull took damage, else "shield".
static func kind_of(hull_dmg: float, zone_broke: bool) -> String:
	if zone_broke:
		return KIND_ZONE
	return KIND_HULL if hull_dmg > 0.0 else KIND_SHIELD


## Does the human fly a living ship now? Nothing is drawn or kept otherwise.
func _flying() -> bool:
	var me := world.human if world != null else null
	return not (me == null or me.state != "flying" or me.ship == null or not is_instance_valid(me.ship) or not me.ship.alive)


## A hit landed on `target` (Events.hit_landed). Only a hit of the human's own ship counts, while the human flies. `now` is the match
## time (a negative value: the World's clock now; a check gives its own).
func on_hit(target: Node, info: RefCounted, hull_dmg: float, zone_broke: bool, now: float = -1.0) -> void:
	if world == null or target == null or not is_instance_valid(target) or info == null or not _flying():
		return
	var d := info as DamageInfo
	if d == null or d.source == null or not is_instance_valid(d.source) or d.source != world.human.ship:
		return
	var u := target as Unit
	if u == null:
		return
	var t := world.time if now < 0.0 else now
	var kind := kind_of(hull_dmg, zone_broke)
	var rec := {"kind": kind, "t0": t}
	if u.size_class <= Rules.SIZE_SMALL:
		# A small craft: where the pointer is (a place on the screen).
		rec["pos"] = get_viewport().get_canvas_transform() * world.mouse_world()
		rec["screen"] = true
	else:
		# Anything bigger: the point on its hit circle toward the shooter (a world place).
		var away := d.from_pos - u.global_position
		var dir := away.normalized() if away.length() > 0.001 else Vector2.ZERO
		rec["pos"] = u.global_position + dir * u.hit_radius()
		rec["screen"] = false
	_add(rec, t * 1000.0)


## Keep marker `rec` if the gap allows it. A "zone" marker inside the gap replaces a weaker marker instead (the gap does not start
## again); any other marker inside the gap is not kept.
func _add(rec: Dictionary, now_ms: float) -> void:
	if now_ms >= _last_ms and now_ms - _last_ms < float(GAP_MS):
		if rec["kind"] == KIND_ZONE and not markers.is_empty() and (markers.back() as Dictionary)["kind"] != KIND_ZONE:
			markers[markers.size() - 1] = rec
		return
	markers.append(rec)
	if markers.size() > KEEP:
		markers.pop_front()
	_last_ms = now_ms


## Every frame: drop the markers whose life is over (and all of them when the human does not fly), and draw again while any is left.
func _process(_dt: float) -> void:
	if world == null:
		return
	if not _flying():
		markers.clear()
	for i in range(markers.size() - 1, -1, -1):
		if world.time - float((markers[i] as Dictionary)["t0"]) >= LIFE_S:
			markers.remove_at(i)
	visible = not markers.is_empty()
	if visible:
		queue_redraw()


## Draw each marker: a cross of four strokes (a VOID stroke under a coloured one so it reads on any ground), fading out over LIFE_S.
func _draw() -> void:
	drawn = 0
	if world == null:
		return
	var xf := get_viewport().get_canvas_transform()
	for m: Dictionary in markers:
		var kind: String = m["kind"]
		var a := clampf(1.0 - (world.time - float(m["t0"])) / LIFE_S, 0.0, 1.0)
		if a <= 0.0:
			continue
		var at: Vector2 = m["pos"] if bool(m["screen"]) else xf * (m["pos"] as Vector2)
		var col := _colour(kind)
		var w: float = WIDTH[kind]
		for corner in 4:
			var dir := Vector2.from_angle(PI * 0.25 + float(corner) * PI * 0.5)
			var from: Vector2 = at + dir * float(R_IN[kind])
			var to: Vector2 = at + dir * float(R_OUT[kind])
			draw_line(from, to, Palette.with_alpha(Palette.VOID, 0.8 * a), w + 2.0, true)
			draw_line(from, to, Palette.with_alpha(col, a), w, true)
		drawn += 1


## The colour of a kind: ICE for a hit the shields took, AMBER for one that reached the hull, CINDER for a broken zone.
static func _colour(kind: String) -> Color:
	if kind == KIND_ZONE:
		return Palette.CINDER
	return Palette.AMBER if kind == KIND_HULL else Palette.ICE
