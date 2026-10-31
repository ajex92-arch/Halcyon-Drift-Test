class_name NoteBox
extends Control
## WHAT THIS IS: the note box: the one-line text box that opens when the
## player presses F9 in a match. The match is paused while it is open. Enter
## saves the note (NoteWriter puts it, with a picture of the screen, in the
## game's user data folder; in the browser build it also hands both files to
## the browser as downloads); Esc cancels. Either way the match carries on as
## it was.
##
## HOW IT WORKS: the layout is the scene scenes/ui/note_box.tscn: a cover over
## the whole window (the box itself takes every click, so nothing behind it
## can be pressed, and its Backdrop dims the game) and, in the middle, a card
## (the "HelpLook" box) holding Title, Line (the text box) and Hint. Hud makes the
## box the first time F9 is pressed and calls open(); until then it does not
## exist. open() does three things in this order:
##   1. it takes a picture of the screen (the frame the player was looking at;
##      a game without a window has none);
##   2. it pauses the match, remembering whether P had paused it already;
##   3. it shows the card and gives the text box the keyboard.
## While it is open HudInput ignores the keys (so typing "b" or "p" does not
## open the hangar or unpause), the guns get no input, because the paused match
## gets none, and the camera (which keeps working in a pause) ignores every key
## and the mouse as long as the text box has the keyboard (CameraRig._typing()). Enter makes the text box send
## text_submitted, which saves the note and shows a short pop-up ("Note
## saved.", or "Note saved and downloaded." when the browser was handed the
## files); Esc is caught in _input() before the text box sees it and cancels.
## _close() hides the card, gives the pause back as it was (a match paused
## with P stays paused) and copies the real state of the mouse buttons back to
## the World, because a button let go while the match was paused never reached
## it.
## An empty note is saved too: it marks the moment (the picture and the
## match details).
##
## WHO USES IT: Hud (it makes the box and calls open(); _note_is_open() asks
## is_open()), HudInput (opens it on F9, and ignores keys while it is open),
## HudBanner (leaves out "Press P to resume" while it is open) and
## tests/note_check.gd.

## The cover that dims the game (its colour is set in _ready from Palette).
@onready var _backdrop: ColorRect = $Backdrop
## The first line of the card.
@onready var _title: Label = $Card/Col/Title
## The one-line text box.
@onready var _line: LineEdit = $Card/Col/Line

## The match the note is about (set by open()).
var world: World
## The picture of the screen taken when the box opened (null: none).
var _shot: Image = null
## True if the match was already paused (P) when the box opened.
var _was_paused := false
## True while the box is open.
var _open := false


## Godot calls this when the box joins the HUD: colours from Palette, the look
## of the text box, and the Enter key.
func _ready() -> void:
	visible = false
	set_process(false)
	_backdrop.color = Palette.with_alpha(Palette.VOID, 0.55)
	var hi := UiKit.accent()
	_title.add_theme_color_override("font_color", hi)
	_line.max_length = NoteWriter.MAX_TEXT
	_line.add_theme_stylebox_override("normal", UiKit.box(Palette.INK, Palette.LINE, 6))
	_line.add_theme_stylebox_override("focus", UiKit.box(Palette.INK, hi, 6))
	_line.add_theme_color_override("font_color", Palette.ICE)
	_line.add_theme_color_override("caret_color", hi)
	_line.add_theme_color_override("font_placeholder_color", Palette.MIST)
	_line.add_theme_color_override("selection_color", Palette.with_alpha(hi, 0.4))
	_line.text_submitted.connect(_on_submitted)


## Is the box open?
func is_open() -> bool:
	return _open


## The text now in the text box (what Enter would save).
func text() -> String:
	return _line.text


## Open the box for match `w` (see HOW IT WORKS). Does nothing if it is open.
func open(w: World) -> void:
	if _open:
		return
	world = w
	# Step 1: the picture, before anything on the screen changes.
	_shot = _grab_picture()
	# Step 2: pause the match; give the pause back as it was when the box closes.
	_was_paused = get_tree().paused
	get_tree().paused = true
	# Step 3: show the card on top of everything and give it the keyboard.
	_open = true
	_line.text = ""
	visible = true
	move_to_front()
	_line.grab_focus()
	set_process(true)


## Close without saving (what Esc does).
func cancel() -> void:
	if _open:
		_close()


## Esc cancels. This runs before the text box sees the key, and marks it used
## up so nothing else (HudInput's "close every panel") reacts to it too.
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		cancel()


## While open, keep the keyboard on the text box (a click on the cover could
## have taken it away).
func _process(_dt: float) -> void:
	if _open and not _line.has_focus():
		_line.grab_focus()


## Enter was pressed in the text box: save the note (an empty text is a
## marker note), say so in a pop-up and close. In the browser build the pop-up
## also says that the files were downloaded.
func _on_submitted(typed: String) -> void:
	if not _open:
		return
	var res := NoteWriter.save(world, typed.strip_edges(), _shot, _was_paused)
	if bool(res["ok"]):
		print("note: saved ", str(res["json"]))
		Events.toast.emit("Note saved and downloaded." if bool(res["downloaded"]) else "Note saved.")
	else:
		print("note: CANNOT SAVE: ", res["error"])
		Events.toast.emit("Could not save the note.")
	_close()


## Hide the box and put things back: the pause as it was, and the mouse
## buttons as they really are now.
func _close() -> void:
	_open = false
	set_process(false)
	visible = false
	_shot = null
	_line.release_focus()
	get_tree().paused = _was_paused
	if world != null:
		world.mouse_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		world.mouse_special = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


## A picture of the screen as it is now (the last frame drawn), or null in a
## game without a window, which draws nothing.
func _grab_picture() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return null
	return img
