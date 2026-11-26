class_name CameraRig
extends Camera2D
## WHAT THIS IS: the camera. It decides which part of the map is on the
## screen and how far zoomed in it is (DESIGN.md A15, the "Camera" line).
##
## HOW IT WORKS: it has two modes.
##   - Free mode (pilots, admirals and spectators all start in it): the
##     camera stays where you put it, anywhere on the map. The mouse wheel
##     zooms; the move keys (W/A/S/D, also Q/E) pan when you are not flying
##     (while you fly they steer the ship, except an Admiral flying with the
##     mode 3: CoastController); the screen edges pan; dragging
##     with the middle mouse button pulls the map; minimap clicks jump the
##     camera (look_at_point()). The Space key centers the camera on your
##     ship (with no ship, docked or dead, on the human's own mothership), and
##     holding it keeps the camera centered on the ship as it moves; let go
##     and the camera is free again from where it is. The HUD's Centre button
##     "latches" Space for the mouse (centre_latched): one click holds it, the
##     next lets go (a minimap click or a middle-button drag lets go too). A pilot's camera also
##     jumps to the ship whenever it launches, so a new ship is never off
##     screen. How far you may zoom out depends on the seat: admirals and
##     spectators see the whole map; a pilot sees only a piece of it
##     (PILOT_VIEW_WIDTH: small craft see roughly their lane, capital ships
##     a bit more) and moves that piece around the map.
##   - Follow mode (an Admiral who pressed C, or a pilot who pressed C or chose it in the pause menu): the camera glides after
##     your ship and looks a little ahead, toward the mouse pointer and
##     where the ship is going. The Admiral's holds the mouse at a screen edge to "peek" a
##     little further that way. The zoom-out limit is a pilot's. With no
##     ship (docked or dead), the camera looks at the human's own mothership.
##     A pilot's follow camera is the leaning one (S1): it aims at the ship plus a share of the way to the mouse pointer
##     (PILOT_LEAN, at most PILOT_LEAN_CAP of half the view's width) and a look-ahead along the velocity that is longer and slower for
##     heavier hulls (PILOT_AHEAD, PILOT_SETTLE), and settles on that goal with a critically damped step. A pilot's camera starts free
##     (PILOT_FOLLOW_DEFAULT; the pause menu's Camera row remembers the choice). Holding Space as a pilot centres on the same leaning goal.
##   - The speed zoom (S1, pilots only, in either mode): the faster the ship flies (and the more it boosts), the further the shown
##     zoom backs out, by at most SPEED_ZOOM_OUT of the view's width (12%), eased and never past the zoom-out limit. It is a factor on
##     the shown zoom: the wheel's choice (target_zoom) stays the player's. The pause menu's Speed zoom button switches it off
##     (Game.speed_zoom); reduced motion turns it off too.
##   - The teammate watch (a pilot with no ship: dead, or docked after a death): `watched` is a living teammate's ship that the free
##     camera follows the way holding Space follows your own ship; the zoom-out limit is that ship's size class, and the speed zoom
##     and the lean stay off (they belong to your own ship). It ends with Space, any manual move (the move keys, the screen edges, a
##     middle drag, a minimap click, the pause menu's Camera row) or a launch; when the watched ship dies or docks the camera stays
##     where it was and the watch stays until one of those ends it. watch_next(), watch_ship() and watch_clear() are its doors (the
##     C key and the death card's buttons use them). It only moves the view: no field of any unit is written.
## Every frame _process() works out where the camera wants to be and how
## far zoomed in, and slides part of the way there, so it moves smoothly.
## The camera keeps working while the match is paused (P): it is the one part of
## the match that does (process_mode "always"), so a paused match can be looked
## around, zoomed and followed. It only moves the view: it gives no order, makes no
## click on the map and holds no timer of the match. The paused match shows a
## still picture, so whenever the view moves, the pictures that depend on it (the
## units, the shots, the effects) are asked to draw themselves again
## (_redraw_if_paused()). While a text box has the keyboard (the note box, F9) the
## camera ignores every key and the mouse, so typing never moves it.
##
## WHO USES IT: it is the "CameraRig" node in scenes/world/world.tscn.
## WorldSetup calls setup() and keeps it as World.camera. The minimap and
## the admiral board call look_at_point(); HudInput calls toggle_free()
## (the C key of the Admiral and of the pilot; the pause menu's Camera row calls it too); ZoomMaxFeature asks zoom_limited(); the command
## overlay asks followed() and reads the zoom; HudInput and HudDeathCard call watch_next(), watch_ship() and watch_clear();
## Sfx reads the camera to make
## far-away sounds quieter; tests also move it.
##
## "Pixels" in this file are the game's own pixels, not the monitor's: the
## project stretches the whole picture to the window (project.godot, canvas
## items stretch, base size 1280 x 720), so the viewport size, the mouse
## position and the screen-edge distances below are all in the base pixels
## (a window twice as big draws each one as 2 x 2 real pixels). Because the
## zoom limits below are worked out from the viewport's width, how many
## world units fit across the screen never depended on the window size.
##
## Words used here: "zoom" is how big things look. At zoom 1 one world unit
## is one pixel; a smaller zoom shows more of the map (zoomed out). So the
## visible world width = screen width in pixels / zoom. "lerp" means moving
## part of the way from one value to another. Using 1 - exp(-k * dt) as
## that part makes the slide equally smooth at any frame rate (a bigger k
## slides faster). `dt` is the time since the last frame, in seconds.

## How wide a piece of the world (in world units) a pilot sees when zoomed
## all the way out, by the followed ship's size class: small, medium,
## large, capital.
const PILOT_VIEW_WIDTH := [5200.0, 6400.0, 8000.0, 10000.0]
## The narrowest view anyone can zoom in to (world units across the
## screen).
const MIN_VIEW_WIDTH := 1100.0
## How fast the free camera slides toward its goal (the k in 1 - exp(-k *
## dt)): about a quarter of a second to get there.
const FREE_SLIDE := 12.0
## S1: does a pilot's camera start in follow mode (the leaning camera)? One constant: today's free camera until the designer's play says
## otherwise. Game.pilot_follow starts from it, and the pause menu's Camera row remembers a pilot's own choice over it.
const PILOT_FOLLOW_DEFAULT := false
## S1: how much of the way from the ship to the mouse pointer a pilot's follow camera leans (the range 0.2 to 0.5).
const PILOT_LEAN := 0.3
## S1: the lean is at most this share of HALF the view's width.
const PILOT_LEAN_CAP := 0.30
## S1: the seconds of the ship's velocity a pilot's follow camera looks ahead, by size class (small, medium, large, capital): more
## for the heavier hulls.
const PILOT_AHEAD := [0.30, 0.38, 0.48, 0.60]
## S1: the seconds a pilot's follow camera takes to settle on its goal (a critically damped step), by size class: slower for the
## heavier hulls.
const PILOT_SETTLE := [0.20, 0.28, 0.38, 0.50]
## S1: the look-ahead is at most this share of the view's width.
const PILOT_AHEAD_CAP := 0.10
## S1: the lean and the look-ahead together never push the ship further from the middle of the screen than this share of the view's
## width (the ship stays on screen), nor further than this share of the ship's sight radius.
const PILOT_OFFSET_CAP := 0.25
## S1: a pilot's Space centring only starts to lean toward the mouse after Space (or the Centre latch) has been held this many seconds, so a tap
## still centres exactly on the ship.
const PILOT_HOLD_DELAY := 0.25
## S1: the seconds the lean then takes to grow from nothing to its full length.
const PILOT_HOLD_RAMP := 0.25
## S1: the share of the ship's sight radius the camera may look away from the ship (see PILOT_OFFSET_CAP).
const PILOT_SIGHT_SHARE := 0.5
## S1: the most the speed zoom widens the view, as a share of its width (0.12 = 12%; the range is 0 to SPEED_ZOOM_MAX).
const SPEED_ZOOM_OUT := 0.12
## S1: the speed zoom never widens the view by more than this share, whatever SPEED_ZOOM_OUT says (15%).
const SPEED_ZOOM_MAX := 0.15
## S1: how fast the speed zoom eases toward its goal (the k in 1 - exp(-k x dt): about half a second).
const SPEED_ZOOM_EASE := 2.0
## The first press of the watch key picks the teammate who took or dealt a hit within this many seconds of match time (the latest
## one); with none, the lowest seat.
const WATCH_HIT_S := 5.0

## The running match. Set by setup().
var world: World
## True in free mode (the camera stays where you put it; everybody starts
## here), false while an Admiral who pressed C has the camera follow their
## ship.
var free := true
## The zoom the camera is sliding toward; the wheel and the zoom keys
## change it. 0.25 is only a starting value until setup() runs.
var target_zoom := 0.25
## The edge peek: how far (world units) the view is pushed toward the
## screen edge the mouse is at. Only used in follow mode.
var peek := Vector2.ZERO
## True while the Centre button has "latched" the Space key down: the free camera then stays on the ship (or
## the mothership) as if Space were held, until the button is clicked again, a minimap click jumps the camera
## or a middle-button drag starts (the HUD's Centre button sets it; HudInput.click()).
var centre_latched := false
## T-125: when the camera last pulsed the return flash (real milliseconds; far in the past = never), for the one-a-second limit.
var _flash_ms := -100000
## T-125: was the Centre button's latch on at the last frame? (A latch turned on counts as a press of Space.)
var _latch_was := false
## True while the middle mouse button is dragging the free camera.
var _drag := false
## Where the mouse was (screen pixels) at the last drag step.
var _drag_last := Vector2.ZERO
## Where the free camera wants to be (world units); the camera slides
## toward it.
var _free_pos := Vector2.ZERO
## Did the human have a ship that was alive in the last frame? A change from
## no to yes is a launch (see _process()).
var _was_flying := false
## RT7: was the human Admiral in mode 3 (with a live ship) at the last frame? A change is the start or the end of mode 3
## (see _move()).
var _m3_was := false
## RT7: the camera's free setting and the Centre latch from before mode 3 began, put back when it ends.
var _m3_free_before := true
var _m3_latch_before := false
## The camera's place and zoom (x, y, zoom) at the end of the last frame: while the
## match is paused it says whether the view moved (see _redraw_if_paused()).
var _last_view := Vector3.ZERO
## S1: how fast a pilot's follow camera is moving now (world units a second): the critically damped step keeps it between frames.
var _follow_vel := Vector2.ZERO
## S1: how long Space or the Centre latch has been held (seconds; 0 when neither is): the pilot's lean grows in after PILOT_HOLD_DELAY.
var _hold_t := 0.0
## S1: the zoom the wheel and the zoom keys chose, eased (the zoom the camera shows before the speed zoom widens it).
var _base_zoom := 0.25
## S1: how much the speed zoom has widened the view now (0 to SPEED_ZOOM_OUT), eased.
var _speed_out := 0.0
## S1: the zoom this script set at the last frame (to tell a zoom written from outside).
var _shown_zoom := 0.0
## The teammate's ship a dead (or docked after a death) pilot's camera is following; null when no watch is on. It is only a
## reading: the camera moves, nothing of the match does. A ship that dies or docks stays here (the camera then stays where it was
## and the card says so) until the watch ends. watch_next(), watch_ship() and watch_clear() are the doors in and out.
var watched: Ship = null
## What the watch copied about the watched pilot when it began (for the card's label after the ship is gone): "name" (callsign),
## "hull" (the hull's short name) and "profile" (the PilotProfile).
var watch_info := {}
## True when the watch switched a follow camera to free for itself, so the launch gives the follow camera back.
var _watch_was_follow := false


## Get ready for match `w`. Everyone starts in free mode. Start 1800 world
## units in front of the human's mothership's spot (to the right of Aurelian's,
## to the left of Vhorr's; a spectator starts at Aurelian's), zoomed so 6000
## world units fit across the screen, and become the screen's camera.
func setup(w: World) -> void:
	world = w
	# A pilot may start in the follow camera when Game.pilot_follow says so (it starts as PILOT_FOLLOW_DEFAULT: free).
	free = not (w.human_role == "pilot" and Game.pilot_follow)
	# Step 0: the camera keeps working while the match is paused, so a paused
	# match can be looked around (the rest of the match stops, as before).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Step 1: the starting spot (also the free camera's goal): in front of the
	# human's own mothership, toward the middle of the map.
	var home: Vector2 = w.map.mothership_pos[w.human_team]
	var toward_middle := 1.0 if w.human_team == Rules.HALCYON else -1.0
	global_position = home + Vector2(1800.0 * toward_middle, 0)
	_free_pos = global_position
	# Step 2: the starting zoom. Godot's own smoothing is off because
	# _process() does its own; make_current() makes this the camera the
	# screen shows.
	target_zoom = _vw() / 6000.0
	zoom = Vector2(target_zoom, target_zoom)
	_base_zoom = target_zoom
	_shown_zoom = target_zoom
	_speed_out = 0.0
	position_smoothing_enabled = false
	make_current()
	# --sim-only (Game.sim_only): nothing is drawn, so the camera never needs
	# to move: switch the per-frame work off.
	if Game.sim_only:
		set_process(false)


## The screen's width in pixels (the "viewport" is the area the game draws
## into).
func _vw() -> float:
	return get_viewport_rect().size.x


## The human's ship while it exists and is alive, otherwise null. Follow
## mode and the Space key (centering) look at it.
func followed() -> Ship:
	var h := world.human
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		return h.ship
	return null


## Is the zoom-out limit a pilot's (PILOT_VIEW_WIDTH by the ship's size)?
## True for a pilot in any mode, and for an Admiral who pressed C to follow
## their ship. A free Admiral camera and a spectator's may zoom out over the
## whole map.
func zoom_limited() -> bool:
	return not free or (world != null and world.human_role == "pilot")


## The allowed zoom range, as Vector2(most zoomed out, most zoomed in).
## Most zoomed in always shows MIN_VIEW_WIDTH (1100) world units across.
## Most zoomed out: the whole map width (MapLayout.W) plus 10% when the
## limit is not a pilot's; otherwise PILOT_VIEW_WIDTH for the followed
## ship's size (small when there is no ship), see zoom_limited().
func zoom_limits() -> Vector2:
	var vw := _vw()
	var min_z: float
	if not zoom_limited():
		min_z = vw / (MapLayout.W * 1.1)
	else:
		var s := followed()
		# A watched teammate's ship sets the limit while the pilot has no ship of their own.
		if s == null:
			s = watched_ship()
		var size := s.size_class if s != null else Rules.SIZE_SMALL
		min_z = vw / (float(PILOT_VIEW_WIDTH[Rules.size_index(size)]) * ZoomMaxFeature.factor())
	return Vector2(min_z, vw / MIN_VIEW_WIDTH)


## Jump the free camera to world point `p` (minimap clicks, the admiral
## board, tests). It slides there over the next frames. Does nothing in
## follow mode (an Admiral who pressed C): that camera is on their ship.
func look_at_point(p: Vector2) -> void:
	centre_latched = false
	watch_clear()
	if free:
		_free_pos = p


## Switch between free and follow mode. An Admiral and a pilot can (the C key, the Admiral's Camera button, the pilot's Camera row in
## the pause menu); for anyone else (a spectator) this does nothing. The free camera starts from where the camera is now. It
## remembers nothing: the pause menu's row keeps a pilot's choice (Game.choose_pilot_follow()). In mode 3 the view stays free
## whatever the press: it flips the setting that comes back when the command view closes.
func toggle_free() -> void:
	if world.human_role == "admiral" or world.human_role == "pilot":
		# A choice of mode ends a teammate watch and is the pilot's own word on free or follow.
		watch_clear()
		_watch_was_follow = false
		# In mode 3 the view is always free: the press changes what the camera does when the command view closes.
		if _mode3_on():
			_m3_free_before = not _m3_free_before
			return
		free = not free
		_free_pos = global_position
		_follow_vel = Vector2.ZERO
		# T-125: an Admiral or a pilot who switches to follow mode while flying comes back to their ship.
		if not free:
			pulse_return()


## The watched teammate's ship while it still flies (it exists and is alive), otherwise null (no watch, or it was shot down or docked).
func watched_ship() -> Ship:
	if watched != null and is_instance_valid(watched) and watched.alive:
		return watched
	return null


## The living teammates a dead or docked pilot can watch, in seat order: the human team's pilots (and its Admiral's ship) with a
## ship in flight, never the human and never the crew of a bought ship. Empty for anyone who is not a pilot.
func watch_candidates() -> Array[Ship]:
	var out: Array[Ship] = []
	var h := world.human
	if h == null or world.human_role != "pilot":
		return out
	var mates: Array[PilotProfile] = []
	for p: PilotProfile in world.profiles:
		if p == h or p.team != h.team or p.is_crew:
			continue
		if p.ship == null or not is_instance_valid(p.ship) or not p.ship.alive:
			continue
		mates.append(p)
	mates.sort_custom(func(a: PilotProfile, b: PilotProfile) -> bool: return a.slot < b.slot)
	for p: PilotProfile in mates:
		out.append(p.ship)
	return out


## The key and the Next button: watch the next living teammate. The first press picks the teammate who took or dealt a hit in the
## last WATCH_HIT_S seconds (the latest one), else the lowest seat; later presses go on in seat order and wrap round. Returns false
## (and changes nothing) when the pilot has a ship of their own or no teammate is in flight.
func watch_next() -> bool:
	if world.human_role != "pilot" or followed() != null:
		return false
	var list := watch_candidates()
	if list.is_empty():
		return false
	var i := list.find(watched) if watched != null and is_instance_valid(watched) else -1
	if i >= 0:
		return watch_ship(list[(i + 1) % list.size()])
	var pick := list[0]
	var best := -INF
	for s: Ship in list:
		var t := maxf(s.last_damage_time, s.aggro_time)
		if t >= world.time - WATCH_HIT_S and t > best:
			best = t
			pick = s
	return watch_ship(pick)


## Start watching teammate ship `s` (a teammate button's click): the camera goes free and follows it. Refused (false) for a ship
## that is not a living teammate of a pilot who has no ship of their own. A follow camera is made free for the watch and given
## back at the next launch.
func watch_ship(s: Ship) -> bool:
	if world.human_role != "pilot" or followed() != null or not watch_candidates().has(s):
		return false
	if not free:
		_watch_was_follow = true
		free = true
	centre_latched = false
	_follow_vel = Vector2.ZERO
	watched = s
	watch_info = {"name": s.profile.callsign, "hull": Formations.short_hull(s.hull_id), "profile": s.profile}
	return true


## End a teammate watch (Space, the My view button, a manual move of the camera, a launch). The camera stays where it is, free. Does
## nothing when no watch is on.
func watch_clear() -> void:
	if watched == null and watch_info.is_empty():
		return
	watched = null
	watch_info = {}


## Godot sends here the mouse input that no screen used. The wheel zooms
## (in any mode; each notch is 12%). The middle button drags the free
## camera: moving the mouse pulls the map along with the pointer.
func _unhandled_input(event: InputEvent) -> void:
	_end_stale_drag()
	if _typing():
		return
	if event is InputEventMouseButton:
		# Wheel up zooms in, wheel down zooms out; the middle button starts
		# a drag (only in free mode) and letting go ends it.
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom *= 1.12
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom /= 1.12
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				centre_latched = false
				watch_clear()
			_drag = mb.pressed and free
			_drag_last = mb.position
	elif event is InputEventMouseMotion and _drag:
		# Dragging: move the goal the opposite way to the mouse, turning
		# screen pixels into world units (divide by the zoom).
		var mm := event as InputEventMouseMotion
		_free_pos -= (mm.position - _drag_last) / zoom.x
		_drag_last = mm.position


## End a middle-button drag whose button is no longer down. A cover that opens over the drag can take the release (the note
## box holds the keyboard), and then nothing else would end it.
func _end_stale_drag() -> void:
	if _drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_drag = false


## Stop a middle-button drag now (an order wheel opening over a drag that is still going calls it: the release would
## go to the wheel and never reach here).
func end_drag() -> void:
	_drag = false


## True while the middle button is dragging the free camera.
func dragging() -> bool:
	return _drag


## Godot calls this on window events. When the game loses focus (Alt+Tab,
## the Windows key) during a middle drag, the button's release never comes
## here, so the drag ends now; otherwise every later mouse move would drag
## the map.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_drag = false


## Godot calls this every drawn frame. Update the zoom, then the position:
## in free mode slide toward the free goal (which the Space key, the edges,
## the move keys and the mouse move); in follow mode slide toward the ship
## (plus look-ahead and edge peek), or toward the mothership when there is
## no ship. It also runs while the match is paused (see the top of the file).
func _process(dt: float) -> void:
	_end_stale_drag()
	if world == null or _typing():
		return
	_move(dt)
	_redraw_if_paused()
	_redraw_pulse_if_paused()


## Is a text box (the note box) holding the keyboard? Then typed keys are text:
## the camera ignores the keys and the mouse until the box lets go.
func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## While the match is paused and the view moved this frame, ask every picture
## that depends on the view to draw itself again. A paused match draws nothing
## new, so without this a zoom would leave the ships, shots and effects drawn
## for the old zoom, and a move would show no shots in the part of the map that
## was off screen before (the shots are only drawn inside the view). Only the
## pictures are asked: nothing of the match changes.
func _redraw_if_paused() -> void:
	var now := Vector3(global_position.x, global_position.y, zoom.x)
	var moved := now != _last_view
	_last_view = now
	if not moved or not get_tree().paused:
		return
	world.projectiles.queue_redraw()
	world.effects.queue_redraw()
	for u: Unit in world.units:
		var v := u.get_node_or_null("Visual") as CanvasItem
		if v != null:
			v.queue_redraw()
	for n in world.get_children():
		if n is CommandOverlay:
			(n as CommandOverlay).queue_redraw()


## One frame of camera work: zoom, then position (see _process()).
func _move(dt: float) -> void:
	# Step 1: the zoom keys change the goal smoothly while held (by
	# 1.5 x dt per frame); keep it inside the allowed range, then slide the
	# real zoom toward it (k = 10).
	if Input.is_action_pressed("zoom_in"):
		target_zoom *= 1.0 + 1.5 * dt
	if Input.is_action_pressed("zoom_out"):
		target_zoom /= 1.0 + 1.5 * dt
	var lim := zoom_limits()
	target_zoom = clampf(target_zoom, lim.x, lim.y)
	# S1: the speed zoom is a factor on the SHOWN zoom: the wheel's zoom (`_base_zoom`, eased toward target_zoom as always) is the player's
	# own and is never touched by speed. A zoom set from outside (the camera's zoom written by a test) is taken as the wheel's.
	if absf(zoom.x - _shown_zoom) > 0.000001:
		_base_zoom = zoom.x
		_speed_out = 0.0
	_base_zoom = lerpf(_base_zoom, target_zoom, 1.0 - exp(-10.0 * dt))
	_speed_out = lerpf(_speed_out, _speed_out_goal(), 1.0 - exp(-SPEED_ZOOM_EASE * dt))
	var z := _base_zoom
	if _speed_out > 0.0:
		# Back out by the eased amount, but never past the zoom-out limit (a view already past it is left as it was).
		z = maxf(_base_zoom / (1.0 + _speed_out), minf(_base_zoom, lim.x))
	_shown_zoom = z
	zoom = Vector2(z, z)
	# `view` is how much of the world fits on the screen (world units).
	var view := get_viewport_rect().size / z
	# Step 2: a pilot's ship has just appeared (it launched): put the free
	# camera's goal on it, so a new ship is never off screen because the
	# camera was left somewhere else. An Admiral who launches keeps their
	# camera where it is (they are still commanding the map).
	var s := followed()
	if s != null and not _was_flying and world.human_role == "pilot":
		_free_pos = s.global_position
		pulse_return()
	# A ship of the pilot's own ends a teammate watch, and a follow camera that the watch made free comes back.
	if s != null:
		watch_clear()
		if _watch_was_follow:
			_watch_was_follow = false
			free = false
	_was_flying = s != null
	# Step 2b: mode 3 (the command view or the board open while flying). The camera goes free and starts on the ship;
	# it pans on the flying_board rows (_free_pan). When mode 3 ends the camera setting from before comes back (the
	# free or follow choice, and the Centre latch).
	var m3 := _mode3_on()
	if m3 and not _m3_was:
		_m3_free_before = free
		_m3_latch_before = centre_latched
		free = true
		centre_latched = false
		_free_pos = _center_goal(s)
	elif _m3_was and not m3:
		free = _m3_free_before
		centre_latched = _m3_latch_before
	_m3_was = m3
	if m3:
		free = true
	# Step 3: free mode: while Space is down the goal sits on the ship (or the
	# mothership); otherwise pan the goal. Then slide toward it.
	if free:
		# T-125: a Space press (not the hold), or the Centre button's latch turned on, while the ship is more than 15% of the view's
		# width from the screen's centre, flashes the ship's outline. A tap while centred gives none.
		var pressed := Input.is_action_just_pressed("center_on_ship") or (centre_latched and not _latch_was)
		_latch_was = centre_latched
		if pressed and s != null and world.human != null:
			if (s.global_position - global_position).length() > view.x * float(FlashTable.RETURN_FLASH["centre_frac"]):
				pulse_return()
		var held := centre_latched or Input.is_action_pressed("center_on_ship")
		_hold_t = _hold_t + dt if held else 0.0
		if _centering():
			# Space is the pilot's own view: it ends a teammate watch.
			watch_clear()
			_free_pos = _center_goal(s)
		elif not watch_info.is_empty() and _pan_dir() == Vector2.ZERO:
			# Watching a teammate: the goal follows their ship the way holding Space follows your own (it stays where it was once the
			# ship is gone).
			var w := watched_ship()
			if w != null:
				_free_pos = _center_goal(w)
		else:
			# A manual move (the move keys, the screen edges) ends a teammate watch and leaves the camera free where it is.
			watch_clear()
			_free_pan(dt, view)
		global_position = global_position.lerp(_free_pos, 1.0 - exp(-FREE_SLIDE * dt))
		return
	# Step 4 for a pilot with a ship (S1): the leaning camera. It aims at pilot_goal() and settles on it with a critically damped step
	# (pilot_step()), slower for heavier hulls. The return flash works here too: a Space press while the camera is far from where it settles.
	if s != null and world.human_role == "pilot":
		var pressed := Input.is_action_just_pressed("center_on_ship") or (centre_latched and not _latch_was)
		_latch_was = centre_latched
		var goal := pilot_goal(s, view)
		# The lean and the look-ahead put the ship off the middle on purpose: the flash is for a camera that is not where it settles
		# (the goal) by more than the box, so a Space press with the camera already following is silent.
		if pressed and world.human != null and (goal - global_position).length() > view.x * float(FlashTable.RETURN_FLASH["centre_frac"]):
			pulse_return()
		var stepped := pilot_step(global_position, goal, _follow_vel, Rules.size_index(s.size_class), dt)
		global_position = stepped[0]
		_follow_vel = stepped[1]
		return
	_follow_vel = Vector2.ZERO
	# Step 4: follow mode with a ship: look toward the mouse (at most 12% of
	# the view width), a quarter of a second ahead of where the ship is
	# moving, plus the edge peek.
	var want: Vector2
	if s != null:
		var aim := (world.mouse_world() - s.global_position)
		var look := aim.limit_length(view.x * 0.12)
		want = s.global_position + look + s.velocity * 0.25
		_edge_peek(dt, view)
		want += peek
	else:
		# Step 5: no ship (docked or dead): look at the spot in front of the
		# human's mothership.
		want = _home_spot()
	# Step 6: slide toward that spot (k = 6).
	global_position = global_position.lerp(want, 1.0 - exp(-6.0 * dt))


## S1: how much the speed zoom wants to widen the view now: SPEED_ZOOM_OUT (at most SPEED_ZOOM_MAX) times the share of its top speed the
## pilot's ship flies at (speed over Ship.f_max, times the boost cap for a ship that can boost, so a boosting ship reaches the full
## amount). 0 for anyone but a pilot with a live ship, with the switch off (Game.speed_zoom) or with reduced motion.
func _speed_out_goal() -> float:
	if not Game.speed_zoom or Blink.reduced_motion or world.human_role != "pilot":
		return 0.0
	var s := followed()
	if s == null:
		return 0.0
	var top := s.f_max * (s.f_boost_cap if s.can_boost else 1.0)
	if top <= 0.0:
		return 0.0
	return minf(SPEED_ZOOM_OUT, SPEED_ZOOM_MAX) * clampf(s.velocity.length() / top, 0.0, 1.0)


## T-125: the one place the "camera comes back to your ship" flash starts from, so every route gets it: the Space press and the
## Centre button's latch (_move()), the launch jump (_move()) and an Admiral's switch to follow mode (toggle_free()). It starts the
## outline flash on the human's ship (ShipVisual.pulse_return()) unless the setting is off (Game.return_flash), there is no live ship
## (docked, dead or a spectator: Space then looks at the mothership) or the last pulse was less than RETURN_FLASH["min_gap_ms"] ago.
## The death screen's teammate view (T-118) does not exist yet: when it hands the camera back to the new ship it calls this too.
func pulse_return() -> void:
	if not Game.return_flash:
		return
	var s := followed()
	if s == null:
		return
	var now := Time.get_ticks_msec()
	if now - _flash_ms < int(FlashTable.RETURN_FLASH["min_gap_ms"]):
		return
	var vis := s.get_node_or_null("Visual") as ShipVisual
	if vis == null:
		return
	_flash_ms = now
	vis.pulse_return()


## T-125: while the match is paused ShipVisual._process() does not run, so ask for a new picture of the human's ship at each frame of
## a pulse (a paused match only redraws when the view moves).
func _redraw_pulse_if_paused() -> void:
	if not get_tree().paused:
		return
	var s := followed()
	if s == null:
		return
	var vis := s.get_node_or_null("Visual") as ShipVisual
	if vis != null and vis.return_active():
		vis.queue_redraw()


## The spot the camera looks at when there is no ship (docked or dead): 900
## world units in front of the human's mothership (Aurelian's for a spectator),
## in the direction it faces. Where the camera already is if there is no
## mothership.
func _home_spot() -> Vector2:
	var ms := world.mothership(world.human_team)
	if ms == null or not is_instance_valid(ms):
		return global_position
	return ms.global_position + Vector2.from_angle(ms.rotation) * 900.0


## Is the Space key ("center_on_ship") down, or was it pressed this frame, or
## has the Centre button latched it (centre_latched)?
## A spectator has no ship to center on, so for them it is never.
func _centering() -> bool:
	if world.human == null:
		return false
	return centre_latched or Input.is_action_pressed("center_on_ship") or Input.is_action_just_pressed("center_on_ship")


## Where the free camera's goal goes while Space is down: on ship `s`, a
## little ahead of it by its speed / FREE_SLIDE, which is exactly how far
## the slide lags behind a moving goal, so a ship flying steadily stays in
## the middle of the screen. With no ship (`s` is null): the home spot.
## S1: for a pilot the goal also leans toward the mouse pointer once Space has been held a moment (a tap still centres exactly), as the follow
## camera does (pilot_lean(), capped as the follow camera is, so the ship stays on screen).
func _center_goal(s: Ship) -> Vector2:
	if s != null:
		var off := s.velocity / FREE_SLIDE
		if world.human_role == "pilot":
			var view := get_viewport_rect().size / maxf(0.02, zoom.x)
			var grow := clampf((_hold_t - PILOT_HOLD_DELAY) / PILOT_HOLD_RAMP, 0.0, 1.0)
			return s.global_position + _cap_offset(off + pilot_lean(s, view) * grow, s, view)
		return s.global_position + off
	return _home_spot()


## S1: the lean of a pilot's camera for ship `s`: PILOT_LEAN of the way from the ship to the mouse pointer, at most PILOT_LEAN_CAP of
## half of the view's width (`view` is the view size in world units).
func pilot_lean(s: Ship, view: Vector2) -> Vector2:
	return ((world.mouse_world() - s.global_position) * PILOT_LEAN).limit_length(view.x * 0.5 * PILOT_LEAN_CAP)


## S1: where a pilot's follow camera aims for ship `s`: the ship plus the lean plus a look-ahead along the velocity (the camera rests
## PILOT_AHEAD seconds of velocity ahead by size class, at most PILOT_AHEAD_CAP of the view's width; the aim also adds the
## PILOT_SETTLE seconds the damped step trails by; none with reduced motion), the two together kept inside _cap_offset().
func pilot_goal(s: Ship, view: Vector2) -> Vector2:
	var off := pilot_lean(s, view)
	if not Blink.reduced_motion:
		# The damped step trails a goal that moves at velocity v by PILOT_SETTLE x v, so the goal is aimed that much further on: the camera
		# then rests PILOT_AHEAD x v ahead of the ship (this lead, not the aim, is the one held to PILOT_AHEAD_CAP).
		var idx := Rules.size_index(s.size_class)
		var ahead := s.velocity * float(PILOT_AHEAD[idx])
		off += ahead.limit_length(view.x * PILOT_AHEAD_CAP) + s.velocity * float(PILOT_SETTLE[idx])
	return s.global_position + _cap_offset(off, s, view)


## S1: `off` (the camera's offset from the ship) kept short enough that the ship stays on screen (PILOT_OFFSET_CAP of the view's
## width) and the camera looks no further than PILOT_SIGHT_SHARE of the ship's sight radius (Unit.vision_radius, the "vision" of
## the hull's row) from the ship.
func _cap_offset(off: Vector2, s: Ship, view: Vector2) -> Vector2:
	var cap := view.x * PILOT_OFFSET_CAP
	if s.vision_radius > 0.0:
		cap = minf(cap, s.vision_radius * PILOT_SIGHT_SHARE)
	return off.limit_length(cap)


## S1: one critically damped step of a camera at `pos`, moving at `vel`, toward `goal`, in `dt` seconds: the camera settles on the goal
## in about PILOT_SETTLE seconds for the size index `size_idx` (0 to 3), without overshooting, whatever the frame time. Returns the new
## position and the new velocity as [Vector2, Vector2].
static func pilot_step(pos: Vector2, goal: Vector2, vel: Vector2, size_idx: int, dt: float) -> Array:
	var omega := 2.0 / float(PILOT_SETTLE[clampi(size_idx, 0, 3)])
	var x := omega * dt
	var damp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := pos - goal
	var temp := (vel + omega * change) * dt
	return [goal + (change + temp) * damp, (vel - omega * temp) * damp]


## Follow mode's edge peek. While the mouse is within 16 pixels of a screen
## edge, `peek` grows toward that edge by 60% of the view width per second,
## up to a quarter of the view each way. Away from the edges, or with the
## pointer outside the window, it slides back to zero (k = 3). `view` is the
## view size in world units.
func _edge_peek(dt: float, view: Vector2) -> void:
	# Step 1: which edges the mouse is at (-1, 0 or 1 across and up-down).
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	var dir := Vector2.ZERO
	var m := 16.0
	if _pointer_inside(mp, vs):
		if mp.x < m:
			dir.x = -1.0
		elif mp.x > vs.x - m:
			dir.x = 1.0
		if mp.y < m:
			dir.y = -1.0
		elif mp.y > vs.y - m:
			dir.y = 1.0
	# Step 2: no edge: ease back to the centre. An edge: push that way,
	# but never past a quarter of the view.
	var max_peek := view * 0.25
	if dir == Vector2.ZERO:
		peek = peek.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * dt))
	else:
		peek += dir * view.x * 0.6 * dt
		peek = Vector2(clampf(peek.x, -max_peek.x, max_peek.x), clampf(peek.y, -max_peek.y, max_peek.y))


## Free mode's panning: move the free camera's goal with the move keys
## (only when the human is not flying, because then those keys fly the
## ship; an Admiral's mode 3 frees them, see CoastController) and with the mouse at a screen edge (within 6 pixels, only while
## the game window is focused and the pointer is inside it). It moves at 80%
## of the view width per second and stays inside the map. `view` is the
## view size in world units.
func _free_pan(dt: float, view: Vector2) -> void:
	var dir := _pan_dir()
	# Step 3: move the goal, and keep it inside the map
	# (0..MapLayout.W across, 0..MapLayout.H down).
	_free_pos += dir * view.x * 0.8 * dt
	_free_pos = Vector2(clampf(_free_pos.x, 0.0, MapLayout.W), clampf(_free_pos.y, 0.0, MapLayout.H))


## The direction the move keys and the screen edges ask the free camera to pan this frame (Vector2.ZERO for none): the work of the
## first two steps of _free_pan(), apart so that a teammate watch can tell a manual move from none.
func _pan_dir() -> Vector2:
	# Step 1: the move keys (D/E right, A/Q left, S down, W up). While the match is
	# paused a flying ship does not fly, so the keys pan the camera then too. The
	# same holds for an Admiral flying in mode 3 (CoastController).
	var flying := followed() != null and not get_tree().paused and not CoastController.holding(world)
	var dir := Vector2.ZERO
	if not flying:
		# Mode 3 (the view or the board open while flying) reads the flying keys, the rows of "flying with the board open" (W A S D Q E,
		# whatever the home layout is), so the arrows stay the shield focus keys under layout A.
		if KeyMap.preset_choice("home_layout") == "A" and not _mode3_on():
			# Home layout A (the classic grid): W A S D are card keys, so the camera moves on the arrow keys.
			dir.x = _home_key("camera_right") - _home_key("camera_left")
			dir.y = _home_key("camera_down") - _home_key("camera_up")
		else:
			dir.x = Input.get_action_strength("strafe_right") - Input.get_action_strength("strafe_left")
			dir.y = Input.get_action_strength("thrust_back") - Input.get_action_strength("thrust_forward")
	# Step 2: the screen edges; they win over the keys on their own axis.
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	if get_window().has_focus() and _pointer_inside(mp, vs):
		if mp.x < 6.0:
			dir.x = -1.0
		elif mp.x > vs.x - 6.0:
			dir.x = 1.0
		if mp.y < 6.0:
			dir.y = -1.0
		elif mp.y > vs.y - 6.0:
			dir.y = 1.0
	return dir


## Is the human Admiral in mode 3 with a live ship (the ship coasts and the camera is the Admiral's)? An Admiral who is
## docked with the board open is not: that is the home camera.
func _mode3_on() -> bool:
	return followed() != null and CoastController.holding(world)


## 1.0 while a key of the home-mode camera row id ("camera_up", "camera_down", "camera_left" or "camera_right") is
## held down, else 0.0. The row's keys come from the key map (layout A gives them the arrow keys); a key is read by
## its place on the keyboard, so a card key that shares a letter never moves the camera under another layout.
func _home_key(id: String) -> float:
	for k in KeyMap.effective_keys("home", id):
		var p := KeyCodes.parse(String(k))
		if bool(p["ok"]) and not bool(p["mouse"]) and Input.is_physical_key_pressed(int(p["code"]) as Key):
			return 1.0
	return 0.0


## Is the mouse pointer `mp` (screen pixels) inside the game's screen of size
## `vs`? On a desktop Godot reports the pointer even when it is outside the
## window (on a second monitor, or on the title bar), and such a position
## would count as "at the edge" and pan the camera without end.
func _pointer_inside(mp: Vector2, vs: Vector2) -> bool:
	return Rect2(Vector2.ZERO, vs).has_point(mp)
