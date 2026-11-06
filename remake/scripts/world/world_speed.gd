class_name WorldSpeed
extends RefCounted
## WHAT THIS IS: the world-speed setting of a match: how fast the game world runs
## compared with real time. It is one number (`factor`: 1.0 is normal, 0.75 and
## 0.5 are the slow motion, 2.0 is double speed) and the small counter that turns
## the number into "this physics frame the World takes a tick, or not". Only the
## game world changes pace: the camera, the HUD, the menus, the note box and the
## pause keep their normal speed (at double speed Godot's own clock doubles their
## frame time too: see the faster paragraph below).
##
## HOW IT WORKS: Godot calls World._physics_process 60 times a second, and the
## step it hands over is always 1/60 of a second. A slowed world does not make
## that step shorter (a tick of another length would play a different match, and
## ships move with Godot's own physics step, which would shrink too). It runs its
## tick on some frames only, and every tick it does run is the full length. step()
## is that choice: it adds `factor` to a counter every physics frame and says "tick"
## whenever the counter reaches 1, then takes 1 off. At 0.5 that is every second
## frame; at 0.75, three frames in four; at 1.0, every frame. 0.75 and 0.5 are
## exact in binary arithmetic, so the pattern repeats without drift. The counter
## lives here, with the match: a new match starts at 1x (or at the launch option
## --slow), and a pause (which stops the World's frames) keeps both the factor and
## the counter.
## Two things would be lost or changed on the frames without a tick. A key tapped
## on such a frame is "just pressed" for that frame only, and the code that reads
## keys (PlayerController) runs inside the tick: step() therefore notes every
## action pressed on a frame without a tick, and just_pressed() answers for the
## tick that follows, so no tap is lost. A click on a HUD button that stands for a
## key (energy, shield zone, kit, assist, dock) is the same: tap() marks the action,
## the next tick moves it to `_clicked_now`, and just_pressed() answers true for it
## on that tick only, so the click runs the key's own lines once. And Godot's physics server steps once at
## the end of every physics frame; a step also reorders its collision search tree,
## and a ship sliding along rocks then resolves its bump a little differently. So
## that a slowed match plays out exactly like the same match at normal speed, the
## server is switched off (PhysicsServer2D.set_active(), the switch the pause
## uses) on the frames without a tick: it steps once per World tick, as at normal
## speed.
## The faster speeds are made the way the Godot editor's own speed buttons make
## them: the engine's physics ticks per second and its time scale are raised
## together (2x: 120 ticks a second and a scale of 2). Godot then runs twice as
## many physics frames each real second, and hands each one a step of
## (1/120) x 2 = 1/60 of a second, so every World tick is still the full length
## and the 2D physics server still steps once per World tick. Every physics frame
## takes a tick, so step() answers true and the counter stays at 0. A factor above
## 1 changes the pace of real time only, never what a tick does. The engine's two
## numbers are remembered at the first change and put back when the speed drops to
## 1 or less and when the World leaves the tree.
## What is left of the engine's clock at a faster speed is drawing only: the HUD,
## the camera and anything counted in `_process` time run at double pace.
##
## WHO USES IT: World keeps one (World.speed) and calls step() at the top of its
## tick; WorldSetup reads the launch options --slow and --fast into it; HudInput
## cycles it with the backquote key; the HUD's top bar shows tag() and limited();
## the order queue changes it through set_hundredths() (the GAME_SPEED order);
## Effects and ShipVisual scale their frame-time animations with the slow part of
## factor; PlayerController and RecallFeature read taps with just_pressed(); HudInput.click()
## (the HUD's buttons, the readout's clicks) marks a click with tap();
## tests/speed_check.gd measures it.

## The slow speeds the key cycles through, in order: normal, three quarters, a half.
const STEPS := [1.0, 0.75, 0.5]
## The faster speeds that play the same match as normal speed (each was proved by a
## determinism run), normal speed first. The order queue and the speed row offer
## only speeds that are in STEPS or here.
const FAST_STEPS := [1.0, 1.5, 2.0]
## Every speed in whole hundredths of normal (the form an order carries) and the
## factor it means.
const HUNDREDTHS := {50: 0.5, 75: 0.75, 100: 1.0, 150: 1.5, 200: 2.0}
## The top speed (times normal). At a faster speed the engine is asked for 60 times
## the factor in physics ticks a second.
const MAX_FACTOR := 2.0
## The engine's own physics ticks per second at normal speed.
const BASE_TICKS := 60

## How fast the world runs: 1.0 normal, below 1.0 slowed, above 1.0 faster. Set it
## with set_factor().
var factor := 1.0
## False for a throwaway WorldSpeed (a test that only counts frames) so it never
## changes Godot's global speed numbers; the one a World keeps leaves it true.
var touches_engine := true
## How many ticks step() has said yes to (used by limited()).
var ticks_taken := 0
## The counter step() adds `factor` to every frame (0 up to just under 1).
var _acc := 0.0
## For each action pressed on a frame without a tick: the physics frame it was
## pressed on. just_pressed() uses the ones newer than the last tick.
var _tapped := {}
## Actions a mouse click stands in for, not yet seen by a tick (tap() adds one; the next
## tick moves them to `_clicked_now`).
var _clicked := {}
## The actions the tick now running was handed by a click: just_pressed() answers true for
## them, on this tick only.
var _clicked_now := {}
## The physics frame of the tick before the one now running.
var _prev_tick_frame := -1
## The physics frame of the last tick (the one now running, inside it).
var _last_tick_frame := -1
## True while Godot's 2D physics server is switched on (it is, at normal speed).
## step() switches it off on the frames without a tick.
var _physics_on := true
## True once this object has changed Godot's physics ticks per second and time
## scale; the two numbers below are then what they were before that.
var _engine_set := false
## Godot's physics ticks per second before this object first changed it.
var _engine_ticks := BASE_TICKS
## Godot's time scale before this object first changed it (a launch option
## --speed=N sets it, so it is not always 1).
var _engine_scale := 1.0
## The real time (milliseconds) of the last limited() sample, or -1 before the first.
var _sample_ms := -1
## ticks_taken at the last limited() sample.
var _sample_ticks := 0
## The answer limited() gave at the last sample.
var _limited := false


## Use speed `f` from now on (clamped to 0.05 .. 2.0). Above 1 the engine's ticks
## per second and time scale are raised together; at 1 or less they are put back
## first. The counter starts so that the very next frame takes a tick.
func set_factor(f: float) -> void:
	factor = clampf(f, 0.05, MAX_FACTOR)
	if factor > 1.0:
		_set_engine(roundi(float(BASE_TICKS) * factor), factor)
		_acc = 0.0
	else:
		_restore_engine()
		_acc = 1.0 - factor
	_sample_ms = -1
	_limited = false


## Read a launch option value such as "0.5" or "0.75": a number from 0.05 to 1.0 is
## the speed, anything else leaves normal speed (and says so on the console).
## Returns the speed that was set.
func set_from_option(text: String) -> float:
	if text.is_valid_float() and float(text) >= 0.05 and float(text) <= 1.0:
		set_factor(float(text))
	else:
		print("slow: ignoring \"%s\" (--slow wants a number from 0.05 to 1, such as 0.75 or 0.5)" % text)
	return factor


## Read the launch option --fast=<1 to 2> such as "2" or "1.5": a number from 1 to 2
## is the speed, anything else leaves normal speed (and says so on the console).
## Any number in the range is taken, so a determinism run can try a speed before it
## is offered to players. Returns the speed that was set.
func set_from_fast_option(text: String) -> float:
	if text.is_valid_float() and float(text) >= 1.0 and float(text) <= MAX_FACTOR:
		set_factor(float(text))
	else:
		print("fast: ignoring \"%s\" (--fast wants a number from 1 to 2, such as 2 or 1.5)" % text)
	return factor


## Use the speed `h` hundredths of normal (50, 75, 100, 150 or 200), if it is one
## the game offers: a key of HUNDREDTHS whose factor is in STEPS or FAST_STEPS.
## Returns false, and changes nothing, for any other number. It sets the speed only;
## the order queue logs the order and tells the event stream.
func set_hundredths(h: int) -> bool:
	if not HUNDREDTHS.has(h):
		return false
	var f: float = HUNDREDTHS[h]
	if not STEPS.has(f) and not FAST_STEPS.has(f):
		return false
	set_factor(f)
	return true


## The key's step: normal -> 0.75 -> 0.5 -> normal. A speed that is not on the list
## (a launch option such as 0.3, or a faster speed) goes to normal.
func cycle() -> void:
	var i := STEPS.find(factor)
	set_factor(float(STEPS[(i + 1) % STEPS.size()]) if i >= 0 else 1.0)


## Is the world slowed?
func is_slow() -> bool:
	return factor < 1.0


## Is the world faster than normal?
func is_fast() -> bool:
	return factor > 1.0


## The speed as players read it: "1x", "0.75x", "0.5x" or "2x" (two decimals at most).
func label() -> String:
	return "%sx" % ("%.2f" % factor).rstrip("0").rstrip(".")


## The HUD tag: "" at normal speed, else "SPEED 0.75x", "SPEED 0.5x" or "SPEED 2x".
func tag() -> String:
	if not is_slow() and not is_fast():
		return ""
	return "SPEED " + label()


## Does the World take a tick on this physics frame? Call it once per frame, at the
## top of World._physics_process. At normal speed and above every frame ticks. Below
## 1 it says no on some frames: it then notes the actions that were pressed on the
## frame (see just_pressed()), and the physics server does not step at the end of
## the frame.
func step() -> bool:
	if factor >= 1.0:
		_acc = 0.0
		_take_tick()
		return true
	_acc += factor
	if _acc >= 1.0:
		_acc -= 1.0
		_take_tick()
		return true
	_note_taps()
	_switch_physics(false)
	return false


## Note that a tick is being taken on this frame (for just_pressed() and limited()),
## with the physics server switched on.
func _take_tick() -> void:
	# A click that stood in for a key press is seen by this tick and no other.
	_clicked_now = _clicked
	_clicked = {}
	_prev_tick_frame = _last_tick_frame
	_last_tick_frame = Engine.get_physics_frames()
	ticks_taken += 1
	_switch_physics(true)


## Give Godot's 2D physics server back, switched on, and Godot's own physics ticks
## per second and time scale back as they were (the World is leaving the tree: a new
## match, or the game closing).
func restore_physics() -> void:
	if not _physics_on:
		PhysicsServer2D.set_active(true)
		_physics_on = true
	_restore_engine()


## Is the world running slower than its speed asks for? True when, over the last real
## second, fewer than 90 percent of the ticks that the speed asks for (60 times the
## factor) were taken: the computer is too slow for this speed. It is false while no
## tick was taken in that second (a pause). For the screen only: the answer is
## sampled once a real second and no game rule reads it. This is the one place that
## reads the clock.
func limited() -> bool:
	var now := Time.get_ticks_msec()
	if _sample_ms < 0:
		_sample_ms = now
		_sample_ticks = ticks_taken
		return false
	var span := now - _sample_ms
	if span >= 1000:
		var took := ticks_taken - _sample_ticks
		var wanted := float(BASE_TICKS) * factor * float(span) / 1000.0
		_limited = took > 0 and float(took) < 0.9 * wanted
		_sample_ms = now
		_sample_ticks = ticks_taken
	return _limited


## Switch Godot's 2D physics server on (a frame with a tick) or off (a frame
## without one), so it steps once per World tick whatever the speed. At normal
## speed it is on and this does nothing. The pause switches the server too, so
## while the factor is below 1 this asks every frame (a pause may have changed it).
func _switch_physics(on: bool) -> void:
	if factor >= 1.0 and _physics_on:
		return
	PhysicsServer2D.set_active(on)
	_physics_on = on


## Set Godot's physics ticks per second and time scale, remembering what they were
## the first time. Does nothing for a throwaway object (touches_engine false).
func _set_engine(ticks: int, scale: float) -> void:
	if not touches_engine:
		return
	if not _engine_set:
		_engine_ticks = Engine.physics_ticks_per_second
		_engine_scale = Engine.time_scale
		_engine_set = true
	Engine.physics_ticks_per_second = ticks
	Engine.time_scale = scale


## Put Godot's physics ticks per second and time scale back to what they were before
## this object first changed them. Does nothing if it never changed them.
func _restore_engine() -> void:
	if not touches_engine or not _engine_set:
		return
	Engine.physics_ticks_per_second = _engine_ticks
	Engine.time_scale = _engine_scale
	_engine_set = false


## Remember the actions pressed on this frame (which has no tick).
func _note_taps() -> void:
	for action: StringName in InputMap.get_actions():
		if Input.is_action_just_pressed(action):
			_tapped[action] = Engine.get_physics_frames()


## Was action `action` just pressed, as the tick now running sees it? Like
## Input.is_action_just_pressed(), and also true for a press on one of the frames
## without a tick since the previous tick. At normal speed there are no such
## frames and it is the same as Input.is_action_just_pressed().
func just_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action) or int(_tapped.get(action, -1)) > _prev_tick_frame or _clicked_now.has(action)


## A mouse click stands in for a press of action `action` (the HUD's buttons call this): the next
## tick sees it through just_pressed() exactly as it sees a key tap, once. It adds nothing to the
## simulation: PlayerController runs the same lines for the click as for the key.
func tap(action: String) -> void:
	_clicked[action] = true
