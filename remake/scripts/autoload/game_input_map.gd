class_name GameInputMap
extends RefCounted
## WHAT THIS IS: the starting point of the game's controls: it makes the "input
## actions" (a named control such as "fire" that one or more keys or buttons can
## trigger) when the game starts. The keys themselves are not written here any
## more: they are rows of the key list (KeyMapData), so the Controls page, the Keys
## help page and the key check all read the same list.
##
## HOW IT WORKS: Godot works with "input actions". Game code asks
## Input.is_action_pressed("fire") instead of asking about one key, so a control can
## have several keys (strafe_left = A or Q). define_all() asks KeyMap to make every
## live action of the key list (the shared and flying rows, KeyMapData.LIVE_STAGES)
## and give it the events of its keys, in order. Keys are matched by their place on
## the keyboard (Godot's "physical" key code, named after a US keyboard), so the W/A/S/D
## block stays in the same spot on other keyboard layouts. The action names are
## the ones tests press by name ("thrust_forward" ... "slow_motion", "note").
## Besides the pilot's keys the list defines: "pause" (P), "slow_motion" (the backquote
## key) and "fast_motion" (Shift plus it), which step the world speed, "note" (F9), "help"
## (H and F12), "debug_launch" (Ctrl+F12, the text overlay's launch) and "wheel" (X and
## mouse button 5, held to open the order wheel, which HudInput reads for a pilot's
## wing) and the eight wing_* actions (no key under the standard wing preset).
##
## WHO USES IT: Game._ready() calls define_all() (through Game._define_actions()),
## and the player's own keys are put on top later by Game.use_remembered_keys() and the
## Controls page (KeyMap.apply_to_input_map()). The actions are read by PlayerController
## (the human's flying), HudInput (the screen keys, F9 "note", "pause" and the two speed
## keys), CameraRig (zoom keys, the move keys to pan the free camera, and Space,
## center_on_ship), WindowMode (F11 / Alt+Enter, the "toggle_fullscreen" action, which
## Game._input listens for), Main (the "debug_launch" key) and tests/bot_pilot.gd and
## tests/camera_check.gd, which press them like a player would.
##
## The function is "static": it belongs to the class itself and is called as
## GameInputMap.define_all(), without making an object first.


## Define every control of the key list (see HOW IT WORKS). Safe to call twice: an
## action's events are replaced, not added to.
static func define_all() -> void:
	KeyMap.apply_to_input_map()
