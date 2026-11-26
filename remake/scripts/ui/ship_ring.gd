class_name ShipRing
extends Control
## WHAT THIS IS: the ring round the pilot's own ship, drawn on the HUD layer: four short shield brackets that turn with the ship, a
## fixed "chin" under it that shows the hull and the energy route, and the torpedo warning: one notched arrowhead for each enemy
## torpedo that is heading for the ship, closing in as it gets nearer, a danger sign in the last second, the seconds to impact, a
## notch where a shooter off the screen hit the ship, and a beep that quickens; and the empty-energy warning: one short pulse and its
## own beep when the battery can no longer pay a gun. Drawing and sound only: it reads the ship, the shots and the pointer and changes
## nothing in the game (no field of a Unit, a Ship, the shots or the World is written).
##
## HOW IT WORKS: it belongs to the HUD, covers the whole screen and lets the mouse through (the shape of HudAlarm). It shows only for
## the ship the human flies (TargetKeys.my_ship(): never another ship, a dead or docked pilot, a spectator, or the flight under the
## command view) and only the parts ShipRingParts.shown() says are on (the presets and the single switches of the pause menu). R is
## the ring's radius in pixels, TurnCues.ring_px() (at least 24, else the world shield ring on screen plus 8); every line width is in
## screen pixels, so the ring looks the same on a Scout and a Battlecruiser. Every frame _process() keeps its small memory and
## draws again:
##   - shield_arcs: four brackets of 50 degrees at R - 2, 3.5 pixels wide (5.5 for the focused zone), centred on the ship's nose, tail
##     and flanks (they turn with the ship), SHIELD at 0.25 + 0.65 x the zone's fill. A zone that broke shows a 1 pixel track, the arc
##     growing back from its middle as the refill wait runs out, and two 5 pixel caps at its ends for one second;
##   - hull_arc: the chin, a 100 degree arc straight below the ship at R + 5 that does not turn: a 1 pixel track and the hull fill in
##     the team colour, from its left end rightward;
##   - route_triangle: a solid 5 x 4 pixel triangle pointing up at the chin, at its left end for Weapons, bottom for Shields, right end
##     for Engines (Balanced shows none);
##   - warning_marks: one arrowhead (8 pixels long, 7 wide, a 2 pixel notch in its back) for each enemy torpedo the team can see whose
##     path will cross the ship's hit circle (the lane test HudAlarm uses, run on the live torpedo) and that will be armed when it
##     arrives, on the bearing to the torpedo and pointing at the ship, its tip at R + 4 + 18 x (seconds to impact / 3) pixels. In the
##     last second the arrowheads turn DANGER and one danger sign stands at the ring's top left; the nearest one pulses at 2 Hz (steady
##     under reduced motion). A beep (the "torp_warn" cue) sounds while any arrowhead is shown, faster as the nearest one gets closer;
##   - impact_number: the seconds to impact ("1.4") beside the nearest arrowhead;
##   - hit_notch: a 10 degree notch on the ring toward a shooter that hit the ship from off the screen, fading over one second of match
##     time. It shows a direction only, never who or where the shooter is;
##   - energy_empty: when the battery turns from able to unable to pay the cheapest gun of the ship (energy_empty(); not while an
##     overload or a Vent already says so on the energy bar), one pulse of 120 ms (480 ms under reduced motion) lights a full circle
##     at R in DANGER with the danger sign straight below the ship, ENERGY_SIGN_OUT pixels outside the ring, and the "energy_empty"
##     cue sounds once. At most one pulse every ENERGY_GAP seconds of match time; steady for its whole length, never blinking. It has no
##     switch of its own in the pause menu.
## Colours: SHIELD, the team colour, ICE; DANGER only together with its sign. Nothing here moves by itself except the one pulse above,
## the empty-energy pulse (real time) and the notch's fade, all read from the clocks. A room for a later lock bar is left on the
## chin's track.
##
## WHO USES IT: Hud.setup() makes one after the turn cues and gives it the world. Not made in --sim-only runs. Sfx plays "torp_warn"
## and "energy_empty".
## tests/ship_ring_check.gd checks it.

## How far (pixels) the shield brackets sit inside the ring.
const BRACKET_IN := 2.0
## The half width of a shield bracket, in degrees (a bracket is 50 degrees).
const BRACKET_HALF_DEG := 25.0
## The width of a shield bracket (pixels), and of the focused zone's.
const BRACKET_W := 3.5
## The width of the focused zone's bracket (pixels).
const BRACKET_W_FOCUS := 5.5
## The width of the track a broken zone shows (pixels) and how strong it is.
const TRACK_W := 1.0
## How strong the broken zone's track is (0 to 1).
const TRACK_ALPHA := 0.2
## The length of a cap at the end of a zone that just broke (pixels), and how long the caps stay (seconds of match time).
const CAP_LEN := 5.0
## How long the caps stay (seconds of match time).
const CAP_SECS := 1.0
## How far (pixels) the chin is outside the ring, and half of its span (degrees; the chin is 100 degrees, straight below the ship).
const CHIN_OUT := 5.0
## Half the chin's span, in degrees (the chin is 100 degrees, straight below the ship).
const CHIN_HALF_DEG := 50.0
## The widths (pixels) of the chin's track and of the hull fill, and how strong each is.
const CHIN_TRACK_W := 1.0
## How strong the chin's track is (0 to 1).
const CHIN_TRACK_ALPHA := 0.4
## The width of the hull fill on the chin (pixels).
const HULL_W := 2.5
## How strong the hull fill is (0 to 1).
const HULL_ALPHA := 0.85
## The route triangle: its width and height (pixels) and how far outside the ring it sits.
const ROUTE_W := 5.0
## The route triangle's height (pixels).
const ROUTE_H := 4.0
## How far outside the ring the route triangle's middle sits (pixels).
const ROUTE_OUT := 11.0
## The warning arrowhead: its length, width and the notch in its back (pixels).
const ARROW_LEN := 8.0
## The warning arrowhead's width across its back (pixels).
const ARROW_W := 7.0
## How deep the notch in the arrowhead's back is (pixels).
const ARROW_NOTCH := 2.0
## The arrowhead's tip is this many pixels outside the ring when the torpedo arrives, and this many more at WARN_SECS out.
const ARROW_BASE := 4.0
## How many more pixels outside the ring the tip is when the torpedo is WARN_SECS from the ship.
const ARROW_TRAVEL := 18.0
## A torpedo further than this many seconds out is shown at this place (seconds).
const WARN_SECS := 3.0
## The last seconds before impact (the arrowheads turn DANGER and the danger sign shows).
const DANGER_SECS := 1.0
## The strength of an arrowhead, and the sign's side (pixels) and place (degrees from straight right, clockwise on the screen: 225 is
## the top left).
const ARROW_ALPHA := 0.85
## The danger sign's side (pixels).
const SIGN_SIDE := 10.0
## Where the danger sign stands on the ring, in degrees from straight right, clockwise on the screen (225 is the top left).
const SIGN_DEG := 225.0
## The nearest arrowhead pulses between these strengths in its last second, at this many times a second.
const PULSE_LOW := 0.6
## How many times a second the nearest arrowhead pulses in its last second.
const PULSE_HZ := 2.0
## The seconds-to-impact number's text size (pixels).
const NUMBER_PX := 8
## The hit notch: its span (degrees), its width (pixels), how far outside the ring (pixels) and how long it lasts (seconds of match time).
const NOTCH_DEG := 10.0
## The hit notch's width (pixels).
const NOTCH_W := 4.0
## How far outside the ring the hit notch sits (pixels).
const NOTCH_OUT := 4.0
## How long the hit notch lasts (seconds of match time).
const NOTCH_SECS := 1.0
## A torpedo closing slower than this (world units a second) is not coming at the ship.
const MIN_CLOSE := 1.0
## The beep's gap (seconds of match time): WARN_SECS out it is PACE_MAX; at half a second or less out it is PACE_MIN, never under it.
const PACE_MIN := 0.34
## The beep's gap when the nearest torpedo is WARN_SECS out (seconds).
const PACE_MAX := 1.0
## The least match time (seconds) between two empty-energy pulses: never more than one a second.
const ENERGY_GAP := 1.0
## Where the empty-energy sign stands, in degrees from straight right, clockwise on the screen (90 is straight below the ship; the
## torpedo sign is at SIGN_DEG).
const ENERGY_SIGN_DEG := 90.0
## How many pixels outside the ring the empty-energy sign stands.
const ENERGY_SIGN_OUT := 24.0
## The width (pixels) of the empty-energy pulse's circle.
const ENERGY_ARC_W := 3.0
## How strong the empty-energy pulse's circle is (0 to 1).
const ENERGY_ARC_ALPHA := 0.9

## The game world (set by setup()).
var world: World
## How many drawing commands the last _draw() made: the check reads it.
var drawn := 0
## The arrowheads now: one Dictionary for each, {"bearing" (the direction from the ship to the torpedo, radians), "t" (seconds to
## impact, 0 to 3), "d" (world units to the hit circle), "slot" (the shot's number)}, nearest first.
var marks: Array = []
## How many beeps this ring has sent (the check reads it).
var beeps := 0
## Per zone: the match time the zone was seen to break (the caps stay one second).
var _broke_at: Array[float] = [-99.0, -99.0, -99.0, -99.0]
## Per zone: was its "just broke" flash running on the last frame?
var _flash_was := [false, false, false, false]
## The instance id of the ship the memory belongs to (0 for none).
var _ship_id := 0
## The newest hit time in the ship's damage log that has been seen.
var _hit_seen := -999.0
## The match time the hit notch started, or -99 for none, and the bearing it shows (radians).
var _notch_at := -99.0
## The bearing the hit notch shows (radians, from the ship toward the shooter).
var _notch_dir := 0.0
## The match time the next beep is due.
var _beep_at := 0.0
## How many empty-energy pulses this ring has started (the check reads it).
var energy_pulses := 0
## Could the battery not pay a gun on the last frame? A pulse starts only on the frame it turns true.
var _energy_was_empty := false
## The match time of the last empty-energy pulse, or -99 for none.
var _energy_pulse_at := -99.0
## The real time (milliseconds, Time.get_ticks_msec()) the last empty-energy pulse started, a long time ago for none.
var _energy_pulse_ms := -1000000


## Remember the world, cover the whole screen and let the mouse through. Hud.setup() calls this once.
func setup(w: World) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Every frame: show only for the ship the human flies, keep the memory (broken zones, the hit notch, the arrowheads, the beep) and
## draw again (the ring turns and moves with the ship).
func _process(_dt: float) -> void:
	if world == null:
		return
	var s := TargetKeys.my_ship(world)
	if s == null:
		if visible:
			visible = false
		drawn = 0
		marks.clear()
		_ship_id = 0
		return
	if s.get_instance_id() != _ship_id:
		_adopt(s)
	_track(s)
	visible = true
	queue_redraw()


## The ship `s` is new to the ring (the first frame, or after a respawn): forget the last ship's memory, taking its flashes and its
## newest hit as already seen.
func _adopt(s: Ship) -> void:
	_ship_id = s.get_instance_id()
	_broke_at = [-99.0, -99.0, -99.0, -99.0]
	_flash_was = [false, false, false, false]
	if s.shields != null:
		for k in 4:
			_flash_was[k] = s.shields.flash[k] > 0.0
	_hit_seen = float(_newest_hit(s)[1])
	_notch_at = -99.0
	_beep_at = 0.0
	_energy_was_empty = energy_empty(s)
	_energy_pulse_ms = -1000000
	_energy_pulse_at = -99.0
	marks.clear()


## Update the memory for ship `s` once a frame.
func _track(s: Ship) -> void:
	# Broken zones: a zone's flash that starts after a frame without one is a break.
	if s.shields != null and not s.shields.single:
		for k in 4:
			var on: bool = s.shields.flash[k] > 0.0
			if on and not _flash_was[k]:
				_broke_at[k] = world.time
			_flash_was[k] = on
	# The hit notch: a newer hit than the last one seen, from a shooter off the screen.
	var newest := _newest_hit(s)
	if float(newest[1]) > _hit_seen:
		_hit_seen = float(newest[1])
		var shooter: Variant = world.by_uid.get(int(newest[0]))
		if shooter != null and is_instance_valid(shooter):
			var xf := get_viewport().get_canvas_transform()
			if not Rect2(Vector2.ZERO, size).has_point(xf * (shooter as Unit).global_position):
				_notch_at = world.time
				_notch_dir = ((shooter as Unit).global_position - s.global_position).angle()
	# The empty-energy warning: one pulse and one beep on the frame the battery turns unable to pay a gun, at most ENERGY_GAP apart.
	var empty := energy_empty(s)
	if empty and not _energy_was_empty and world.time - _energy_pulse_at >= ENERGY_GAP:
		_energy_pulse_at = world.time
		_energy_pulse_ms = Time.get_ticks_msec()
		energy_pulses += 1
		Events.cue.emit("energy_empty", Vector2.ZERO)
	_energy_was_empty = empty
	# The arrowheads and the beep.
	marks = marks_of(s) if ShipRingParts.shown("warning_marks") else []
	if marks.is_empty():
		_beep_at = 0.0
		return
	if world.time >= _beep_at:
		Events.cue.emit("torp_warn", Vector2.ZERO)
		beeps += 1
		_beep_at = world.time + pace(float(marks[0]["t"]))


## The seconds between two beeps when the nearest torpedo is `t` seconds from the ship: PACE_MAX at WARN_SECS out, PACE_MIN at half a
## second or less, a straight line between, never under PACE_MIN.
static func pace(t: float) -> float:
	return maxf(PACE_MIN, lerpf(PACE_MIN, PACE_MAX, clampf((t - 0.5) / (WARN_SECS - 0.5), 0.0, 1.0)))


## The newest hit in ship `s`'s damage log as [the attacker's uid, the time], the lower uid on a tie; [-1, -999] when it has none.
func _newest_hit(s: Ship) -> Array:
	var best_uid := -1
	var best_t := -999.0
	for uid: Variant in s.damage_log:
		var t := float((s.damage_log[uid] as Array)[1])
		if t > best_t or (t == best_t and int(uid) < best_uid):
			best_t = t
			best_uid = int(uid)
	return [best_uid, best_t]


## The arrowheads for ship `s` as a list, nearest first (see `marks`): every live torpedo of another team that the human's team can see,
## whose lane (the line it flies along, cut at the first rock) crosses the ship's hit circle, that closes in at MIN_CLOSE units a
## second or more and will be armed when it arrives. The seconds to impact are the distance to the hit circle over the closing speed,
## kept between 0 and WARN_SECS.
func marks_of(s: Ship) -> Array:
	var out: Array = []
	var proj := world.projectiles
	var at := s.global_position
	for n in proj.active.size():
		var i := proj.active[n]
		if proj.live[i] != 1 or proj.kind[i] != Rules.W_TORP or proj.team[i] == s.team:
			continue
		var from := proj.pos[i]
		if not world.vision.is_visible(world.human_team, from):
			continue
		var v := proj.vel[i]
		var sp := v.length()
		if sp < 0.001:
			continue
		var unit := v / sp
		var length := sp * proj.life[i]
		var pad := proj.radius[i]
		var rock := world.asteroids.segment_hit(from, from + unit * length, pad)
		if not rock.is_empty():
			length *= clampf(float(rock["t"]), 0.0, 1.0)
		if not Util.seg_hits_circle(from, from + unit * length, at, s.hit_radius() + pad):
			continue
		var to := at - from
		var dist := to.length()
		var closing := v.dot(to / dist) if dist > 0.001 else sp
		if closing < MIN_CLOSE:
			continue
		var d := maxf(0.0, dist - s.hit_radius())
		if proj.arm_left[i] > d:
			continue
		out.append({"bearing": (from - at).angle(), "t": clampf(d / closing, 0.0, WARN_SECS), "d": d, "slot": i})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	return out


## The ring's radius in world units for ship `s` at zoom `z`: its picture's own number when it has one (ShipVisual.ring_radius_world()).
func ring_world(s: Ship, z: float) -> float:
	var vis := s.get_node_or_null("Visual") as ShipVisual
	if vis != null:
		return vis.ring_radius_world(z)
	var length := float(s.def.get("length", 26.0))
	return maxf(length * maxf(1.0, ShipVisual.MIN_PX / maxf(0.001, length * z)) * 0.62, s.radius * 1.3)


## Draw the parts for the ship the human flies.
func _draw() -> void:
	drawn = 0
	var s := TargetKeys.my_ship(world) if world != null else null
	if s == null:
		return
	var xf := get_viewport().get_canvas_transform()
	var z := xf.get_scale().x
	var c := xf * s.global_position
	var r := TurnCues.ring_px(ring_world(s, z), z)
	if ShipRingParts.shown("shield_arcs"):
		_draw_shields(s, c, r)
	if ShipRingParts.shown("hull_arc"):
		_draw_chin(s, c, r)
	if ShipRingParts.shown("route_triangle"):
		_draw_route(s, c, r)
	if ShipRingParts.shown("warning_marks"):
		_draw_marks(c, r)
	if ShipRingParts.shown("hit_notch"):
		_draw_notch(c, r)
	if energy_pulse_on(_energy_pulse_ms, Time.get_ticks_msec()):
		_draw_energy(c, r)


## The four shield brackets, and for a zone that broke its track, regrowth and caps.
func _draw_shields(s: Ship, c: Vector2, r: float) -> void:
	var sh := s.shields
	if sh == null or sh.single or sh.max_total <= 0.0:
		return
	var radius := r - BRACKET_IN
	var half := deg_to_rad(BRACKET_HALF_DEG)
	for k in 4:
		var cap := sh.cap(k)
		if cap <= 0.0:
			continue
		var mid: float = s.rotation + float(ShieldArcs.CENTERS[k])
		var fill := clampf(sh.values[k] / cap, 0.0, 1.0)
		if sh.values[k] <= 0.0:
			# Broken: a thin track, the arc growing back from the middle while the refill wait runs out.
			draw_arc(c, radius, mid - half, mid + half, 8, Palette.with_alpha(Palette.SHIELD, TRACK_ALPHA), TRACK_W, true)
			drawn += 1
			var grow := clampf(sh.since_hit / maxf(0.1, sh.delay), 0.0, 1.0)
			if grow > 0.02:
				draw_arc(c, radius, mid - half * grow, mid + half * grow, 8, Palette.with_alpha(Palette.SHIELD, 0.5), BRACKET_W * 0.6, true)
				drawn += 1
		else:
			var w := BRACKET_W_FOCUS if sh.focus == k + 1 else BRACKET_W
			draw_arc(c, radius, mid - half, mid + half, 8, Palette.with_alpha(Palette.SHIELD, 0.25 + 0.65 * fill), w, true)
			drawn += 1
		if world.time - _broke_at[k] < CAP_SECS and world.time >= _broke_at[k]:
			var pts := PackedVector2Array()
			for e: float in [mid - half, mid + half]:
				var dir := Vector2.from_angle(e)
				pts.append(c + dir * (radius - CAP_LEN * 0.5))
				pts.append(c + dir * (radius + CAP_LEN * 0.5))
			draw_multiline(pts, Palette.with_alpha(Palette.ICE, 0.9), 1.5, true)
			drawn += 1


## The chin: a track and the hull fill, screen-fixed straight below the ship.
func _draw_chin(s: Ship, c: Vector2, r: float) -> void:
	var radius := r + CHIN_OUT
	var down := PI * 0.5
	var half := deg_to_rad(CHIN_HALF_DEG)
	draw_arc(c, radius, down - half, down + half, 16, Palette.with_alpha(Palette.MIST, CHIN_TRACK_ALPHA), CHIN_TRACK_W, true)
	drawn += 1
	var frac := clampf(s.hull_frac(), 0.0, 1.0)
	if frac > 0.005:
		# From the chin's left end (the larger angle) rightward: the fill is the span from there back by 100 degrees x the hull.
		draw_arc(c, radius, down + half - 2.0 * half * frac, down + half, 16, Palette.with_alpha(Palette.team(s.team), HULL_ALPHA), HULL_W, true)
		drawn += 1


## The route triangle: pointing up, at the chin's left end (Weapons), bottom (Shields) or right end (Engines).
func _draw_route(s: Ship, c: Vector2, r: float) -> void:
	var at := _route_place(s.energy.mode)
	if at < -900.0:
		return
	var q := c + Vector2.from_angle(at) * (r + ROUTE_OUT)
	draw_colored_polygon(PackedVector2Array([q + Vector2(0.0, -ROUTE_H * 0.5), q + Vector2(ROUTE_W * 0.5, ROUTE_H * 0.5), q + Vector2(-ROUTE_W * 0.5, ROUTE_H * 0.5)]), Palette.ICE)
	drawn += 1


## Where the route triangle sits for energy route `mode`, as an angle in radians (screen, clockwise from straight right); -999 when
## Balanced shows none.
static func _route_place(mode: int) -> float:
	match mode:
		Rules.ENERGY_WEAPONS:
			return PI * 0.5 + deg_to_rad(CHIN_HALF_DEG)
		Rules.ENERGY_SHIELDS:
			return PI * 0.5
		Rules.ENERGY_THRUSTERS:
			return PI * 0.5 - deg_to_rad(CHIN_HALF_DEG)
	return -999.0


## The arrowheads, the danger sign in the last second and the number beside the nearest one.
func _draw_marks(c: Vector2, r: float) -> void:
	if marks.is_empty():
		return
	var danger := false
	for n in marks.size():
		var m: Dictionary = marks[n]
		var t := float(m["t"])
		var dir := Vector2.from_angle(float(m["bearing"]))
		var side := dir.orthogonal()
		var tip := c + dir * arrow_tip_px(r, t)
		var back := tip + dir * ARROW_LEN
		var poly := PackedVector2Array([tip, back + side * ARROW_W * 0.5, back - dir * ARROW_NOTCH, back - side * ARROW_W * 0.5])
		var col := Palette.with_alpha(Palette.ICE, ARROW_ALPHA)
		if t < DANGER_SECS:
			danger = true
			col = Palette.with_alpha(Palette.DANGER, danger_alpha(world.time, n == 0))
		draw_colored_polygon(poly, col)
		drawn += 1
	if danger:
		Glyphs.danger(self, c + Vector2.from_angle(deg_to_rad(SIGN_DEG)) * r, SIGN_SIDE)
		drawn += 4
	if ShipRingParts.shown("impact_number"):
		var near: Dictionary = marks[0]
		var dir := Vector2.from_angle(float(near["bearing"]))
		var at := c + dir * (arrow_tip_px(r, float(near["t"])) + ARROW_LEN + 3.0)
		var text := "%.1f" % float(near["t"])
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_PX).x
		var origin := at + Vector2(0.0 if dir.x >= 0.0 else -width, float(NUMBER_PX) * 0.5)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_PX, Palette.ICE)
		drawn += 1


## The strength (0 to 1) of an arrowhead in its last second at match time `time_s`: the nearest one pulses between PULSE_LOW and 1 at
## PULSE_HZ times a second (read from the match clock, nothing random); every other one, and every one under reduced motion, is 1.
static func danger_alpha(time_s: float, nearest: bool) -> float:
	if not nearest or Blink.reduced_motion:
		return 1.0
	return PULSE_LOW + (1.0 - PULSE_LOW) * Blink.pulse_at(int(time_s * 1000.0), PULSE_HZ)


## The distance (pixels) from the ship's middle to an arrowhead's tip when the torpedo is `t` seconds out and the ring's radius is `r`:
## R + 4 + 18 x (t / 3).
static func arrow_tip_px(r: float, t: float) -> float:
	return r + ARROW_BASE + ARROW_TRAVEL * clampf(t / WARN_SECS, 0.0, 1.0)


## Can ship `s`'s battery not pay for its cheapest gun? False for no ship, a dead ship, and a ship whose systems are off (an overload or
## a Vent already says so on the energy bar). A gun costs its "energy" a shot; a beam pays that every physics tick, so its cost here is
## that over the ticks a second. A mount with no energy cost counts for none, so a ship with no energy-spending mount is never empty.
static func energy_empty(s: Ship) -> bool:
	if s == null or not s.alive or s.systems_off():
		return false
	var need := INF
	for m: WeaponMount in s.mounts:
		var cost := float(m.def.get("energy", 0.0))
		if cost <= 0.0:
			continue
		if m.is_beam:
			cost /= float(Engine.physics_ticks_per_second)
		need = minf(need, cost)
	return need < INF and s.energy.value < need


## Is an empty-energy pulse that started at `started_ms` lit at `now_ms`? 120 ms, or 480 ms under reduced motion (Blink.confirm()).
static func energy_pulse_on(started_ms: int, now_ms: int) -> bool:
	return Blink.confirm(started_ms, now_ms) > 0.0


## The colour of every look of the empty-energy warning: the danger colour (no new palette colour; it always comes with its sign).
static func energy_colour() -> Color:
	return Palette.DANGER


## The empty-energy pulse: one circle at the ring's radius and the danger sign straight below the ship, outside the ring.
func _draw_energy(c: Vector2, r: float) -> void:
	draw_arc(c, r, 0.0, TAU, 48, Palette.with_alpha(energy_colour(), ENERGY_ARC_ALPHA), ENERGY_ARC_W, true)
	drawn += 1
	Glyphs.danger(self, c + Vector2.from_angle(deg_to_rad(ENERGY_SIGN_DEG)) * (r + ENERGY_SIGN_OUT), SIGN_SIDE)
	drawn += 4


## The hit notch: a short arc on the ring toward the shooter that hit the ship from off the screen, fading out over a second.
func _draw_notch(c: Vector2, r: float) -> void:
	var age := world.time - _notch_at
	if age < 0.0 or age >= NOTCH_SECS:
		return
	var half := deg_to_rad(NOTCH_DEG) * 0.5
	draw_arc(c, r + NOTCH_OUT, _notch_dir - half, _notch_dir + half, 6, Palette.with_alpha(Palette.ICE, 1.0 - age / NOTCH_SECS), NOTCH_W, true)
	drawn += 1
