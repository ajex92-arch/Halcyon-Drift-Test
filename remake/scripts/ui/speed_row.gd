class_name SpeedRow
extends HBoxContainer
## WHAT THIS IS: a row of buttons for the game speed, 0.5x 0.75x 1x and, when the game can run
## faster, 1.5x 2x, with the speed the world has now in the highlight colour. It is standalone so
## the pause menu only adds it.
##
## HOW IT WORKS: setup() gives it the match; the buttons are made from SpeedControl.all_steps(), so
## the row shows exactly the speeds the game has. A click asks SpeedControl.send(); a refusal is
## shown in the small note after the buttons. While there is no faster speed, the note says
## "faster: with the orders stage". When the match does not allow changing the speed
## (SpeedControl.allowed(), or the refusal "Against the computer only"), every button is greyed and
## the note says why (show_blocked()). With no match at all, the buttons are greyed too. The row
## looks at the world's speed every frame, so the highlight follows the keys as well.
##
## WHO USES IT: the pause menu (one block that adds a SpeedRow), tests/controls_page_check.gd and
## tests/controls_shots.gd.

## The match this row changes (null: no match, the buttons are greyed).
var world: World = null
## The speed buttons by speed in hundredths.
var _buttons := {}
## The small grey line after the buttons: why they are greyed, a refusal, or the faster note.
var _note: Label = null
## Why the row is greyed ("" when it is not).
var _blocked := ""
## Picture scripts only: when not -1, the row shows this speed (in hundredths) as the one in force
## instead of the world's. -1 in the game.
var forced_current := -1


## Build the row's buttons and note.
func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UiKit.label("Game speed", 15, Palette.MIST))
	for h: int in SpeedControl.all_steps():
		var b := UiKit.button(SpeedControl.label_of(h), _on_press.bind(h), 32.0)
		b.toggle_mode = true
		b.custom_minimum_size.x = 64.0
		add_child(b)
		_buttons[h] = b
	_note = UiKit.label("", 14, Palette.MIST)
	add_child(_note)
	_show_default_note()
	refresh()


## Give the row the match it changes.
func setup(w: World) -> void:
	world = w
	refresh()


## Grey every button and say `reason` in the note, as when a match with other people does not
## allow changing the speed. Pass "" to allow it again.
func show_blocked(reason: String) -> void:
	_blocked = reason
	if reason == "":
		_show_default_note()
	else:
		_note.text = reason
	refresh()


## The note when nothing is wrong: "faster: with the orders stage" while there is no faster speed.
func _show_default_note() -> void:
	_note.text = "faster: with the orders stage" if SpeedControl.fast_steps().is_empty() else ""


## Make the button for `hundredths` the highlighted one (the world's speed) and grey the row when it
## has no match or is blocked.
func refresh() -> void:
	var cur := forced_current if forced_current >= 0 else (SpeedControl.current(world) if world != null else -1)
	var off := world == null or _blocked != "" or not SpeedControl.allowed(world)
	for h: int in _buttons:
		var b: Button = _buttons[h]
		b.set_pressed_no_signal(h == cur)
		b.disabled = off


## Keep the highlight in step with the world, whoever changed its speed.
func _process(_dt: float) -> void:
	if world != null:
		refresh()


## A button was clicked: ask for its speed; show the refusal if there is one.
func _on_press(hundredths: int) -> void:
	if world == null:
		return
	var why := SpeedControl.send(world, hundredths)
	if why == SpeedControl.ONLINE:
		show_blocked(why)
	elif why != "":
		_note.text = why
	else:
		_show_default_note()
	refresh()
