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
##
## WHO USES IT: Hud.setup() makes one and gives it the world. Sfx plays the
## "alarm" cue. Not made in --sim-only runs (they have no HUD).

## Seconds between two looks for a lane that will cross the pilot's ship.
const LOOK_EVERY := 0.1
## How far in from the edge of the screen the triangle's middle sits, in pixels.
const MARGIN := 30.0
## How big the triangle is, in pixels from its middle to its point.
const SIZE := 14.0

## The game world (set by setup()).
var world: World
## Seconds until the next look.
var _t := 0.0
## The run each Bomber last alarmed for: ship uid -> RunGun.serial.
var _alarmed := {}
## The Bombers marked now (Ship nodes).
var _marks: Array = []


## Remember the world, cover the whole screen and let the mouse through. Hud.setup()
## calls this once.
func setup(w: World) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Every frame: look again every LOOK_EVERY seconds, drop the marks whose run is
## over, and redraw while there is a mark.
func _process(dt: float) -> void:
	if world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = LOOK_EVERY
		_look()
	# A pilot who is not flying (dead, docked) has no ship to warn: no marks.
	var me := world.human
	if me == null or me.state != "flying" or me.ship == null or not is_instance_valid(me.ship) or not me.ship.alive:
		_marks.clear()
	for i in range(_marks.size() - 1, -1, -1):
		var b = _marks[i]
		if not is_instance_valid(b) or not (b as Ship).alive or not (b as Ship).run_on():
			_marks.remove_at(i)
	visible = not _marks.is_empty()
	if visible:
		queue_redraw()


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
