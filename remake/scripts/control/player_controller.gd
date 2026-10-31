class_name PlayerController
extends RefCounted
## WHAT THIS IS: turns the human player's keyboard and mouse into orders for
## their ship. It fills in the ship's ShipControls, the same form the AI
## pilots (PilotAI) fill in, so humans and bots fly by the same rules.
##
## HOW IT WORKS: every tick (one small step of game time, 60 a second) the
## ship asks update() to read the keys and mouse and write them into
## ship.controls. The controls:
##   Mouse: aim. The hull turns toward the mouse, and big ships' turrets
##     track it.
##   Hold Ctrl: lock the hull's heading (for example to keep your strongest
##     shield facing a threat) while the turrets keep tracking the mouse.
##   W / S: thrust forward / brake and reverse.
##   A / D (or Q / E): strafe (slide) left / right.
##   Shift: boost.
##   Left click: fire. Right click or G: the hull's special ability. On a
##     Bomber's torpedo run (the hold, and the wait for the release) a right
##     click cancels the run instead; G stays the special.
##     (Space is not a flying key: it centers the camera, see CameraRig.)
##   Arrow keys: shield focus (put more shield on one side). Pressing the
##     side that is already focused goes back to balanced.
##   1-4: energy routing (weapons, shields, thrusters, balanced).
##   R: repair kit. F: dock. V: flight assist on/off.
## An Admiral who flies with the Admiral board open does not steer: at the end
## of update() BoardHold switches the engines off, holds the heading and
## brakes before a rock, a turret, a derelict or a mothership.
## The key names ("thrust_forward" and so on) are set up in Game
## (scripts/autoload/game.gd, _define_actions).
##
## Mouse buttons come from World (World.mouse_fire and World.mouse_special,
## which only count clicks the on-screen buttons didn't take), so clicking a
## HUD button never fires the guns.
##
## WHO USES IT: World makes one for the human pilot's ship when it launches
## (World.launch) and puts it in Ship.controller; Ship.sim_update() calls
## update() each tick. tests/bot_pilot.gd drives it by pressing the keys.

## The game world (for the mouse position, mouse buttons and match time).
var world: World
## Was the special-ability button held down last tick? Used to fire the
## ability only at the moment the button goes down, not every tick it is
## held.
var _special_was := false
## Was the right mouse button held down last tick? Used to find the moment it
## goes down.
var _right_was := false
## True while the right mouse button is held down after a click that cancelled a
## torpedo run: such a click is not read as the special.
var _right_cancel := false


## World makes this and passes itself in.
func _init(w: World) -> void:
	world = w


## Read the keyboard and mouse and fill in `ship`'s controls for this tick.
## `_dt` (seconds since the last tick) isn't needed here.
func update(ship: Ship, _dt: float) -> void:
	var c := ship.controls
	# Steps 1-2: engines. Each key gives 0..1, so forward is +1 (W), -1 (S)
	# or 0, and strafe is +1 (A, left), -1 (D, right) or 0.
	c.forward = Input.get_action_strength("thrust_forward") - Input.get_action_strength("thrust_back")
	c.strafe = Input.get_action_strength("strafe_left") - Input.get_action_strength("strafe_right")
	c.boost = Input.is_action_pressed("boost")
	# Step 3: guns. Fire while the left mouse button is held.
	c.fire = world.mouse_fire
	# Step 4: right click and the special ability. While a Bomber's torpedo run
	# is on (the hold or the wait for the release) a right-click press cancels the
	# run instead of using the special, and that click stays a cancel until the
	# button is let go. Outside a run the right click is the special, as always;
	# G is the special at any time. The special acts only on the press itself (the
	# button was up last tick and is down now). The ship clears `special` and
	# `cancel_run` after reading them.
	var right_now := world.mouse_special
	if right_now and not _right_was and ship.run_on():
		c.cancel_run = true
		_right_cancel = true
	if not right_now:
		_right_cancel = false
	_right_was = right_now
	var special_now := (right_now and not _right_cancel) or Input.is_physical_key_pressed(KEY_G)
	if special_now and not _special_was:
		c.special = true
	_special_was = special_now
	# Step 5: aim at the mouse. With Ctrl held, the hull keeps facing the way
	# it points now (a spot 600 units straight ahead); otherwise it turns to
	# face the mouse too.
	c.aim_point = world.mouse_world()
	if Input.is_physical_key_pressed(KEY_CTRL):
		c.face_point = ship.global_position + Vector2.from_angle(ship.rotation) * 600.0
	else:
		c.face_point = c.aim_point
	# Step 6: shield focus (arrow keys). Pressing the side already focused
	# asks for balanced shields instead.
	var focus_keys := [["shield_front", Rules.FOCUS_FRONT], ["shield_rear", Rules.FOCUS_REAR],
		["shield_left", Rules.FOCUS_LEFT], ["shield_right", Rules.FOCUS_RIGHT]]
	for fk: Array in focus_keys:
		if world.speed.just_pressed(fk[0]):
			c.focus_request = Rules.FOCUS_BALANCED if ship.shields.focus == int(fk[1]) else int(fk[1])
	# Step 7: energy routing (keys 1-4).
	var energy_keys := [["energy_weapons", Rules.ENERGY_WEAPONS], ["energy_shields", Rules.ENERGY_SHIELDS],
		["energy_thrusters", Rules.ENERGY_THRUSTERS], ["energy_balanced", Rules.ENERGY_BALANCED]]
	for ek: Array in energy_keys:
		if world.speed.just_pressed(ek[0]):
			c.energy_request = int(ek[1])
	# Step 8: repair kit (R).
	if world.speed.just_pressed("use_kit"):
		c.use_kit = true
	# Step 9: dock (F). Ignored for half a second after launch, because the
	# same F press that launched the ship from the hangar must not dock it
	# again straight away.
	if world.speed.just_pressed("dock") and world.time - ship.launched_at > 0.5:
		c.dock = true
	# Step 10: flight assist (V) toggles on the ship itself, with a short
	# pop-up message, and is copied into the controls every tick.
	if world.speed.just_pressed("assist_toggle"):
		ship.assist = not ship.assist
		Events.toast.emit("Flight assist %s" % ("on" if ship.assist else "off"))
	c.assist = ship.assist
	# Step 11: an Admiral flying with the board open coasts (BoardHold).
	BoardHold.hold(world, ship)
