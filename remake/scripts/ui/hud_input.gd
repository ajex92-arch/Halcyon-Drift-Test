class_name HudInput
extends RefCounted
## WHAT THIS IS: the part of the HUD that decides what the menu keys do:
## P pause menu, the backquote key (slower world speeds) and Shift plus it (faster ones),
## Tab (Admiral board or scoreboard), B hangar, H help, Esc cancel / close / pause menu
## (Esc closes the order wheel first), C camera, F launch, F9 the note box, X the order
## key (tap or hold: the pilot's wing wheel, the flying Admiral's fleet wheel) and the wing keys (preset B: Y U I O K L N
## Shift+N).
##
## HOW IT WORKS: Godot gives the HUD every key press the game didn't use
## (Hud._unhandled_input) and the HUD passes it to handle(). Keys only work
## while the match is being played (F9 also works after it), and a key held
## down long enough to repeat ("echo") is ignored. The one exception is the
## order key (X or the mouse's fifth button): _wing_key() reads it first and
## handles its repeats itself (it swallows them while the key is down) and its
## release, which tells a tap from a hold. While the note box is open
## every key press is left to its text box. Each key that does something is
## marked "handled", so nothing else reacts to it as well. The key names
## ("hangar", "dock", "note", ...) are actions set up in Game
## (autoload/game.gd) from the key list (KeyMapData), for example "dock" is F,
## "admiral_board" is Tab and "note" is F9. The pause key and the two speed keys
## are read with an exact match (is_action(name, true)): Godot's plain match lets
## an action with no modifier fire when Shift or Ctrl is held too, which would make
## Shift plus the backquote key also fire the slower key. The speed keys only ask
## SpeedControl, which changes the speed (or says why it cannot).
## The pause key opens the pause menu from anywhere, and ends the pause when the
## menu holds it. Esc works from the most urgent thing down: it cancels an armed
## map tool, else closes the open panels, else opens the pause menu. While the
## pause menu holds the game, the other keys stay quiet: H shows the help pages
## over it, Esc steps back (help to menu, question to buttons, menu to game; from
## Look around, with the card hidden, back to the card).
##
## Every key that opens or switches something has a click twin: click(action) (the HUD's buttons, the
## readout, the Kit slot) runs the same function as the key's branch above (_hangar_key(), _camera_key(),
## _dock_key()), or the same forwarding call, or marks the action for the next tick (WorldSpeed.tap()), so a
## click and a key give the same result, with the same gates.
##
## WHO USES IT: Hud makes one (hud.router) and calls handle() for each key; the SeatBar, ShipStatus and
## HudSlots call click().
## It opens panels through the Hud's forwarding functions (HudPanels does
## the work), cancels CommandOverlay map tools, and switches the camera
## (CameraRig.toggle_free).

## The HUD this part belongs to (we read its world, panels and overlay).
var hud: Hud
## When the order key went down (real milliseconds, Time.get_ticks_msec()), or -1 while it is up.
var _wheel_down := -1
## Where the mouse was when the order key went down (pixels).
var _wheel_pos := Vector2.ZERO
## The world point under the reticle when the order key went down.
var _wheel_aim := Vector2.ZERO
## True from the target button going down (the middle click) while a press would count, until it goes up.
var _target_down := false
## Where the target button went down (screen pixels).
var _target_pos := Vector2.ZERO

## Released within this many milliseconds, with the mouse moved less than TAP_PX, the order key is a tap.
const TAP_MS := 250
## The most the mouse may move (pixels) during a tap.
const TAP_PX := 12.0
## The order wheel is drawn this many milliseconds after the key goes down.
const WHEEL_OPEN_MS := 130
## The target button (the middle click) released less than this many pixels from where it went down is a target click; a longer
## move is a drag, which still pans the free camera.
const TARGET_CLICK_PX := 6.0
## The wing preset's keys: [action, gesture, value]. Shift+N is listed first (an exact match, so N never takes it).
const WING_KEYS := [
	["wing_fire", "next_fire", 0], ["wing_formation", "next_formation", 0], ["wing_follow", "follow", 0],
	["wing_cover", "cover", 0], ["wing_attack", "attack", 0], ["wing_guard", "guard", 0],
	["wing_hold", "hold", 0], ["wing_regroup", "regroup", 0],
]


## Remember which HUD we belong to.
func _init(owner: Hud) -> void:
	hud = owner


## Tell Godot this key press is used up, so no other node reacts to it.
func _handled() -> void:
	hud.get_viewport().set_input_as_handled()


## A speed key was pressed: step the world speed to the next one on that key's list (`faster`
## true: 1.5x, 2x; false: 0.75x, 0.5x) and say so in a pop-up, or say why it could not be done
## (SpeedControl: no faster speed yet, or the change was refused).
func _step_speed(faster: bool) -> void:
	var to := SpeedControl.next(hud.world, faster)
	if to < 0:
		hud.toast(SpeedControl.NO_FAST_YET)
		return
	var why := SpeedControl.send(hud.world, to)
	hud.toast("World speed: %s" % hud.world.speed.label() if why == "" else why)


## React to one key press or release (see HOW IT WORKS).
func handle(event: InputEvent) -> void:
	var world := hud.world
	if world == null:
		return
	# Step 0: the order key (X, or the mouse's fifth button): the pilot's wing wheel, or the flying Admiral's fleet wheel. It comes before the key-only
	# test below because its second binding is a mouse button, and before the "only when pressed" test, which
	# would drop the release: a tap or a hold is told apart by the release.
	if event.is_action("wheel") and _wing_key(event):
		return
	# Step 0b: the target's mouse button (the middle click). It never marks the event used, so the camera still gets the press and the
	# release and a drag still pans; a release near the press (a click, not a drag) marks a target.
	if event is InputEventMouseButton and event.is_action("target", true):
		_target_mouse(event as InputEventMouseButton)
		return
	# Step 0c: while the fleet wheel is open, the build strip's digits (the "wheel" rows of the key map) queue a hull
	# and are used up (the wheel stays open); every other key goes on as usual.
	if event is InputEventKey and hud.order_wheel.is_open and hud.order_wheel.strip_key(event as InputEventKey):
		_handled()
		return
	# Step 1: only real key presses during play.
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.echo:
		return
	# Step 1b: while the note box is open every key press belongs to its text
	# box, so typing "b" or "p" does not open the hangar or pause the game. (A
	# key let go still goes on, so a Tab let go still hides the scoreboard.)
	if k.pressed and hud._note_is_open():
		return
	# Step 1c: F9 opens the note box. It works in every seat and also after the
	# match is over, so it is checked before the "only during play" test below.
	if k.pressed and event.is_action("note"):
		hud._open_note()
		_handled()
		return
	if world.phase != "play":
		return
	# Step 2: P (the "pause" action) pauses the whole game without a menu (in every screen state),
	# or ends the pause when the menu holds it.
	if k.pressed and event.is_action("pause", true):
		hud.panels.toggle_command_pause()
		_handled()
		return
	# Step 2b: the speed keys. Shift plus the backquote key (left of 1) steps the
	# faster world speeds (normal, 1.5x, 2x), the backquote key alone the slower
	# ones (normal, 0.75x, 0.5x). The faster key is asked first, and both match
	# exactly (see the top of this file). They work while paused too, and the
	# speed is kept through a pause.
	if k.pressed and event.is_action("fast_motion", true):
		_step_speed(true)
		_handled()
		return
	if k.pressed and event.is_action("slow_motion", true):
		_step_speed(false)
		_handled()
		return
	# Step 2c: while the pause menu holds the game, the other keys stay quiet. H
	# shows the help pages over the menu; Esc closes an open order wheel first, else steps back; the rest do nothing.
	if hud._pause_menu_active():
		if k.pressed and event.is_action("help"):
			hud._toggle_help()
			_handled()
		elif k.pressed and event.is_action("cancel"):
			if hud.wing_wheel.is_open or hud.order_wheel.is_open or _wheel_down >= 0:
				# The order wheel (the fleet wheel or the wing wheel) closes first, giving no order (also over the pause
				# menu and in Look around).
				_wheel_down = -1
				hud.wing_wheel.close()
				hud.order_wheel.close()
			else:
				hud.pause_menu.back()
			_handled()
		return
	# Step 3: Tab. The Admiral docked toggles their board on each press; an Admiral flying toggles the command
	# view (mode 3: the ship coasts, the camera is free, map clicks select) and Tab closes the board too; a pilot
	# sees the scoreboard only while Tab is held down (press shows it, release hides it).
	if event.is_action("admiral_board"):
		if world.human_role == "admiral":
			if k.pressed:
				if world.teams[world.human_team].admiral_docked:
					hud._toggle_board()
				else:
					hud.panels.toggle_view()
		else:
			hud._show_scoreboard(k.pressed)
		_handled()
		return
	# Every other key only reacts when pressed, not when let go.
	if not k.pressed:
		return
	# Step 3a: the target key (Caps Lock): mark the enemy nearest the pointer, or the last attacker when that one is marked already.
	# It is used up only when the pilot flies (TargetKeys.my_ship); the pause menu and the note box were handled above.
	if event.is_action("target", true) and TargetKeys.my_ship(world) != null:
		TargetKeys.press(world, hud)
		_handled()
		return
	# Step 3b: the wing's key preset (flying; the actions have keys only while that preset is chosen).
	if _wing_preset_key(event):
		return
	# Step 3c: the Admiral's command view: M selects every squadron, and the card's keys of the page in force (the grid, the digits)
	# are taken before B, F and H below mean the hangar, dock or help.
	if hud.command_view != null and hud.command_view.key(event):
		_handled()
		return
	# Step 3d: the selection keys (F1 to F8) also work with the board open, when the view itself is hidden under the board.
	if hud.command_view != null and not hud.command_view.is_showing() and hud.command_view.select_key(event):
		_handled()
		return
	# Step 4: B opens the hangar, or closes it if it is showing.
	if event.is_action("hangar"):
		_hangar_key()
		_handled()
	# Step 5: H shows or hides the help pages.
	elif event.is_action("help"):
		hud._toggle_help()
		_handled()
	# Step 6: Esc cancels an armed map tool first; otherwise it closes
	# every panel; with nothing to cancel or close it opens the pause menu.
	elif event.is_action("cancel"):
		if hud.wing_wheel.is_open or hud.order_wheel.is_open or _wheel_down >= 0:
			# The order wheel (the fleet wheel or the wing wheel) closes first, giving no order.
			_wheel_down = -1
			hud.wing_wheel.close()
			hud.order_wheel.close()
		elif hud.overlay.tool != "":
			hud.overlay.disarm()
		elif hud._any_panel_open():
			hud._close_others(null)
		elif hud.command_view != null and hud.command_view.cancel_key():
			pass
		elif world.view_open:
			# Mode 3 closes: the Admiral flies again.
			world.view_open = false
		elif TargetKeys.clear(world):
			# The target is let go (the panels and the command view closed first, above).
			pass
		else:
			hud._toggle_pause_menu()
		_handled()
	# Step 7: C switches the camera between free and following your ship, for
	# the Admiral and for a pilot (the pilot's follow camera leans toward the
	# mouse, see CameraRig; Space centers either one while it is held). The
	# pilot's mouse route is the pause menu's Camera row.
	elif event.is_action("center_camera"):
		_camera_key()
		_handled()
	# Step 8: F launches when docked. A pilot can always do this; an
	# Admiral only while the hangar is open. The hangar does the
	# launching, so it is made (and hidden again) if it doesn't exist yet.
	# The key counts as used only if the launch worked.
	elif event.is_action("dock"):
		if _dock_key():
			_handled()


# --- clicks that do what a key does -----------------------------------------------------------------

## B: open the hangar, or close it if it is showing.
func _hangar_key() -> void:
	if hud.hangar != null and hud.hangar.visible:
		hud.hangar.visible = false
	else:
		hud._open_hangar()


## C: the Admiral's or a pilot's camera goes between free and following their ship (a spectator has no ship: nothing happens).
## The toast names the new mode; a pilot's follow camera also leans toward the mouse. A pilot who has no ship after a death (the
## death card is up) gets the teammate watch from C instead: the next living teammate, or the pop-up "No teammate in flight".
func _camera_key() -> void:
	var role := hud.world.human_role
	# A pilot with no ship after a death: C watches the next living teammate (and says so when there is none).
	if hud.death_card != null and hud.death_card.watch_allowed():
		if not hud.world.camera.watch_next():
			hud.toast("No teammate in flight")
		return
	if role == "admiral" or role == "pilot":
		hud.world.camera.toggle_free()
		var now_free := hud.world.camera.free
		if role == "admiral":
			hud.toast("Camera: %s" % ("free (WASD / edges / minimap)" if now_free else "following your ship"))
		else:
			hud.toast("Camera: %s" % ("free (%s centres it on your ship)" % KeyMapText.key_of("center_on_ship") if now_free else "following your ship, leaning toward the mouse"))


## F while docked: launch. A pilot can always do this; an Admiral only while the hangar is open. The
## hangar does the launching, so it is made (and hidden again) if it doesn't exist yet. Returns true
## only if the launch worked (the key counts as used then).
func _dock_key() -> bool:
	var world := hud.world
	var h := world.human
	var may := world.human_role == "pilot" or (hud.hangar != null and hud.hangar.visible)
	if h != null and h.state == "docked" and may:
		if hud.hangar == null:
			hud._open_hangar()
			hud.hangar.visible = false
		return hud.hangar.launch()
	return false


## A click on a button stands for key `action` (an action name such as "hangar", "dock" or "energy_shields"),
## and does exactly what that key does, through the same lines. The gates are the keys' own: the match is
## being played, the note box is closed and the game is not paused. The one thing that works while the game is
## held paused is the Menu button in Look around (the pause menu's card is hidden, and the button brings it
## back, as Esc does). Ship actions (energy, shield zones, kit, assist, dock in flight) go to WorldSpeed.tap(),
## so the next tick runs PlayerController's own lines for them; menu actions run the key's branch of handle().
## A pilot's Scores click is not wired in this build (the table closes only when Tab is let go).
func click(action: String) -> void:
	var world := hud.world
	if world == null or world.phase != "play" or hud._note_is_open():
		return
	if hud.get_tree().paused and not hud.panels.command_paused:
		if action == "pause" and hud._pause_menu_active() and hud.pause_menu.looking:
			hud.pause_menu.show_card()
		return
	match action:
		"hangar":
			_hangar_key()
		"help":
			hud._toggle_help()
		"pause":
			hud._toggle_pause_menu()
		"admiral_board":
			if world.human_role == "admiral":
				hud._toggle_board()
		"center_camera":
			_camera_key()
		"center_on_ship":
			world.camera.centre_latched = not world.camera.centre_latched
		"dock":
			var h := world.human
			if h != null and h.state == "docked":
				_dock_key()
			else:
				world.speed.tap("dock")
		_:
			world.speed.tap(action)


# --- the pilot's wing ----------------------------------------------------------------------------

## The order key (the "wheel" action: X, or the mouse's fifth button) went down or up. Pressed, in a pilot
## seat with a wing (Hud.wing_ready) or in the seat of an Admiral who is flying (Hud.field_ready), it starts the
## timing: released within TAP_MS with the mouse moved under TAP_PX it is a tap (the pilot's order for what the mouse
## is on, the Admiral's smart order); otherwise the wheel (the wing wheel or the fleet wheel) is drawn from
## WHEEL_OPEN_MS after the press and the release gives the order under the mouse. The times are real milliseconds,
## so it works while the game is paused or slowed. Returns true when the event was used.
func _wing_key(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).echo:
		return _wheel_down >= 0
	var admiral := hud.world.human_role == "admiral"
	if event.is_pressed():
		if _wheel_down >= 0:
			return true
		if hud.world.phase != "play" or hud._note_is_open() or not (hud.field_ready() if admiral else hud.wing_ready()):
			return false
		_wheel_down = Time.get_ticks_msec()
		_wheel_pos = hud.get_viewport().get_mouse_position()
		_wheel_aim = hud.field_aim() if admiral else hud.wing_aim()
		_handled()
		return true
	if _wheel_down < 0:
		return false
	var held := Time.get_ticks_msec() - _wheel_down
	var moved := hud.get_viewport().get_mouse_position().distance_to(_wheel_pos)
	_wheel_down = -1
	if held < TAP_MS and moved < TAP_PX:
		if admiral:
			hud.order_wheel.close()
			hud.field_tap(_wheel_aim)
		else:
			hud.wing_wheel.close()
			hud.wing_command("tap", 0, _wheel_aim)
	elif admiral and hud.order_wheel.is_open:
		hud.order_wheel.close_and_apply()
	elif hud.wing_wheel.is_open:
		hud.wing_wheel.close_and_apply()
	_handled()
	return true


## Once a frame (Hud._process): draw the order wheel (the Admiral's fleet wheel, or the pilot's wing wheel) when the key
## has been down for WHEEL_OPEN_MS.
func wing_tick() -> void:
	if _wheel_down < 0 or Time.get_ticks_msec() - _wheel_down < WHEEL_OPEN_MS:
		return
	if hud.world.human_role == "admiral":
		if hud.order_wheel.is_open:
			return
		if hud.field_ready():
			hud.order_wheel.open_at(_wheel_pos, _wheel_aim)
		else:
			_wheel_down = -1
	elif not hud.wing_wheel.is_open:
		if hud.wing_ready():
			hud.wing_wheel.open_at(_wheel_pos, _wheel_aim)
		else:
			_wheel_down = -1


## The target button (the "target" action's mouse button, the middle one) went down or up. Down: remember where, when a press
## would count. Up: a click (released less than TARGET_CLICK_PX from where it went down) marks the target; a longer move was a drag
## and marks nothing. The event is never used up here: the camera reads the same button for its drag.
func _target_mouse(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		_target_down = _target_may_act()
		_target_pos = mb.position
		return
	if not _target_down:
		return
	_target_down = false
	if mb.position.distance_to(_target_pos) < TARGET_CLICK_PX and _target_may_act():
		TargetKeys.press(hud.world, hud)


## An open order wheel (the fleet wheel or the wing wheel) covers the HUD and takes every mouse press itself, so the middle click
## never reaches handle(). The wheel hands the event here instead. A target-button press marks the enemy under the pointer on the
## press itself (the same pick and the same rules as a click above: TargetKeys.press, only while the human flies a ship and the
## game is being played); no order is filed and the wheel is left as it is. The release marks nothing, and no camera drag can start
## or end, because the camera never sees either event. Returns true when `mb` is the target button (press or release), so the
## wheel uses it up; false for any other button, which the wheel treats as before.
func wheel_target(mb: InputEventMouseButton) -> bool:
	if not mb.is_action("target", true):
		return false
	if mb.pressed:
		_target_down = false
		if _target_may_act():
			TargetKeys.press(hud.world, hud)
	return true


## May the target's key or click act now? The match is being played, the note box is closed, the pause menu does not hold the game
## and the human flies a ship.
func _target_may_act() -> bool:
	var world := hud.world
	return world != null and world.phase == "play" and not hud._note_is_open() and not hud._pause_menu_active() and TargetKeys.my_ship(world) != null


## Once a frame (Hud._process): a target that died is replaced by the next enemy nearest the pointer (TargetKeys.tick).
func target_tick() -> void:
	if hud.world != null and hud.world.phase == "play":
		TargetKeys.tick(hud.world)


## The order key's hold is over without its release (a click on the open fleet wheel used it, or the wheel closed
## because a field order can no longer be given): forget it, so the wheel does not open again while the key is down.
func end_hold() -> void:
	_wheel_down = -1


## A key of the wing preset (Y U I O K L N and Shift+N when preset B is chosen, or any key the player gave the
## eight wing actions) was pressed: build the order the same way the wheel does. The next formation and the
## next fire setting are computed here as explicit values; no toggle reaches an order. Returns true when used.
func _wing_preset_key(event: InputEvent) -> bool:
	for row: Array in WING_KEYS:
		if InputMap.has_action(str(row[0])) and event.is_action(str(row[0]), true):
			if not hud.wing_ready():
				return false
			hud.wing_command(str(row[1]), int(row[2]))
			_handled()
			return true
	return false
