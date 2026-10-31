class_name ControlsCapture
extends RefCounted
## WHAT THIS IS: the part of the Controls page that waits for the player to press the new key of
## a row and decides what happens with it.
##
## HOW IT WORKS: begin() marks one key button "Press a key (Esc cancels)" and starts waiting. While
## it waits, the page hands every input to handle() first, and handle() uses up (returns true for)
## every key, so nothing else reacts to it. Esc cancels. The next key with its Ctrl, Alt and Shift, or
## mouse button 3, 4 or 5, is the new key; the left and right buttons are the click and cannot be chosen.
## A modifier pressed alone is waited on: if another key follows it is part of the new key (Ctrl+K), and
## if it is let go alone it is the key itself (Shift). accept() then asks KeyMap.conflicts(): no clash,
## the key is set (KeyMap.set_slot) and the page saves and shows it; a clash, the page shows the
## warning (ControlsPage.show_clash). Choosing the key the slot already has, or the one in the row's
## other slot, changes nothing.
##
## WHO USES IT: ControlsPage makes one; the page's _input() calls handle(); tests call accept() with a
## key text instead of a keyboard.

## The page this part belongs to.
var page: ControlsPage
## True while a key is awaited.
var active := false
## The mode of the row being changed.
var mode := ""
## The action (the row's id) being changed.
var action := ""
## The key slot being changed: 0 for the first key, 1 for the second.
var slot := 0
## The key button showing "Press a key (Esc cancels)" (may be null in a test).
var button: Button = null
## The text the button had before the wait.
var _old_text := ""
## The modifier key code that was pressed and not yet let go or combined (0: none).
var _held_modifier := 0


## Remember the page.
func _init(owner: ControlsPage) -> void:
	page = owner


## Start waiting for the new key of slot `key_slot` of row `row_action` of `row_mode`. Another wait that
## was open is cancelled first. Returns true.
func begin(row_mode: String, row_action: String, key_slot: int, key_button: Button) -> bool:
	cancel()
	mode = row_mode
	action = row_action
	slot = key_slot
	button = key_button
	active = true
	_held_modifier = 0
	if button != null:
		_old_text = button.text
		button.text = "Press a key (Esc cancels)"
	return true


## Stop waiting and put the button's old words back.
func cancel() -> void:
	if active and button != null and is_instance_valid(button):
		button.text = _old_text
	active = false
	_held_modifier = 0


## Look at one input while waiting. Returns true when it was used up (the page then marks it handled).
func handle(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		if k.pressed and (int(k.keycode) == KEY_ESCAPE or code == KEY_ESCAPE):
			cancel()
			return true
		# A modifier on its own: wait to see whether a key follows.
		if k.pressed and KeyCodes.MODIFIER_CODES.has(code):
			_held_modifier = code
			return true
		if not k.pressed:
			var alone := KeyCodes.modifier_release_text(event)
			if alone != "" and _held_modifier != 0:
				_held_modifier = 0
				accept(alone)
			return true
		_held_modifier = 0
		var text := KeyCodes.event_text(event)
		if text != "":
			accept(text)
		return true
	if event is InputEventMouseButton:
		var text := KeyCodes.event_text(event)
		if text != "":
			accept(text)
			return true
	return false


## The new key is `text`. Set it, or show the clash warning.
func accept(text: String) -> void:
	if not active:
		return
	var c := KeyCodes.canonical(text)
	var row_mode := mode
	var row_action := action
	var key_slot := slot
	cancel()
	if c == "":
		return
	var slots := KeyMap.slot_keys(row_mode, row_action)
	if KeyCodes.canonical(String(slots[key_slot])) == c or KeyCodes.canonical(String(slots[1 - key_slot])) == c:
		return
	var clashes := KeyMap.conflicts(row_mode, row_action, [c], KeyMap.page_of(row_mode, row_action))
	if clashes.is_empty():
		KeyMap.set_slot(row_mode, row_action, key_slot, c)
		page.after_change()
	else:
		page.show_clash(row_mode, row_action, key_slot, c, clashes)
