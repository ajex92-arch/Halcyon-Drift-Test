class_name ControlsPage
extends PanelContainer
## WHAT THIS IS: the Controls page: where the player sees every key of the game and changes
## them. It reads the key list (KeyMap) and needs no match, so the pause menu, the help's Keys
## page and the settings screen can all open the same scene.
##
## HOW IT WORKS: the layout is the scene scenes/ui/controls_page.tscn: a title row with a tab
## for each mode (Home, Flying, Flying with the board open) and Close; a bar with "Reset this
## mode" and "Reset all" (each asks once, in the bar); the key set pickers of the tab (the home
## layout on the Home tab, the wing commands on the Flying tab); the clash warning; and a
## scrolling list of rows made by ControlsRows. A row shows
## the action's name, two key buttons and a short note. A click on a key button waits for a key
## or mouse button 3 to 5 (ControlsCapture; Esc cancels). A key that another action in the same
## mode (or every mode) already uses is not taken: the page shows a warning in the danger colour
## with the danger triangle that names every action that has it, and keeps it on the screen,
## with the rest of the page locked, until the player picks Swap (the other action gets the key
## this one gave up; offered only when exactly one action that can change has the key and the
## swap makes no new clash) or Keep (the old key stays). No key is ever saved twice in a mode.
## Every change is applied to the controls at once (KeyMap) and saved to the settings file
## (save_path). The page does not read the settings file: the start screen did, once.
## Public functions such as begin_capture(), choose_swap() and pick_preset() are what the mouse
## clicks call, so a test can do the same without a window.
##
## WHO USES IT: HudPanels makes it from its scene (Hud._toggle_controls(), opened by the help
## panel's "Change keys" button, and by the pause menu's Controls button when that joins); the
## test tests/controls_page_check.gd and the picture tour tests/controls_shots.gd.

## Sent when the player presses Close.
signal closed
## Sent after the player changed a key, a key set or reset keys (the controls are already up to
## date and saved).
signal changed

## Where changes are written: "" is the game's settings file (Game.SETTINGS_FILE). A test points
## it at a temporary file so it never writes the player's own.
var save_path := ""
## False: changes are applied but not written at all (the picture tour).
var autosave := true
## The mode whose tab is showing: "home", "flying" or "flying_board".
var mode := "home"
## The part that makes the rows of the list.
var rows_part: ControlsRows
## The part that waits for the key.
var capture: ControlsCapture
## The clash that waits for Swap or Keep: {mode, action, slot, key, clashes, swap} or {} when none.
var pending := {}

## The tab buttons by mode.
@onready var _tabs := {"home": $Col/Head/Home, "flying": $Col/Head/Flying, "flying_board": $Col/Head/Board}
## The close button.
@onready var _close: Button = $Col/Head/Close
## The two reset buttons.
@onready var _reset_mode: Button = $Col/Bar/ResetMode
@onready var _reset_all: Button = $Col/Bar/ResetAll
## The "are you sure" box in the bar: the question and its two buttons.
@onready var _ask_box: HBoxContainer = $Col/Bar/Ask
@onready var _ask_text: Label = $Col/Bar/Ask/Question
@onready var _ask_yes: Button = $Col/Bar/Ask/Yes
@onready var _ask_no: Button = $Col/Bar/Ask/No
## The column of key set pickers of the tab.
@onready var _pickers: VBoxContainer = $Col/Pickers
## The warning row: the triangle, the words and the two choices.
@onready var _warn: HBoxContainer = $Col/Warn
## The scrolling area and the column of rows in it.
@onready var _scroll: ScrollContainer = $Col/Scroll
@onready var _body: VBoxContainer = $Col/Scroll/Body

## The words of the warning (made in code, after the triangle).
var _warn_text: Label
## The Swap button of the warning (shown only when a swap can be made).
var _swap_button: Button
## The "Keep the old one" button of the warning.
var _keep_button: Button
## What "Yes" does in the bar's question (empty: no question is open).
var _on_yes := Callable()


## Called once when the node joins the scene: make the parts and the warning row, connect the
## buttons and show the first tab.
func _ready() -> void:
	rows_part = ControlsRows.new(self)
	capture = ControlsCapture.new(self)
	_warn.add_child(DangerMark.new())
	_warn_text = UiKit.label("", 15, Palette.DANGER, true)
	_warn_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warn.add_child(_warn_text)
	_swap_button = UiKit.button("Swap", choose_swap, 30.0)
	_keep_button = UiKit.button("Keep the old one", choose_keep, 30.0)
	_warn.add_child(_swap_button)
	_warn.add_child(_keep_button)
	for m: String in _tabs:
		(_tabs[m] as Button).pressed.connect(show_mode.bind(m))
	_close.pressed.connect(func() -> void: closed.emit())
	# A key being awaited is given up when the page is hidden (by Close, Esc through another panel, or H).
	visibility_changed.connect(func() -> void:
		if not visible:
			capture.cancel())
	_reset_mode.pressed.connect(ask_reset_mode)
	_reset_all.pressed.connect(ask_reset_all)
	_ask_yes.pressed.connect(confirm_yes)
	_ask_no.pressed.connect(confirm_no)
	show_mode(mode)


## Where the page writes: save_path, or the game's settings file.
func _path() -> String:
	return save_path if save_path != "" else Game.SETTINGS_FILE


## Show the tab of `m` ("home", "flying" or "flying_board"): mark its button and make the list.
func show_mode(m: String) -> void:
	mode = m
	pending = {}
	_ask_box.visible = false
	rebuild()


## Make the pickers, the warning and the list again for the mode now showing, keeping the scroll
## position.
func rebuild() -> void:
	var keep := _scroll.scroll_vertical
	for m: String in _tabs:
		(_tabs[m] as Button).add_theme_color_override("font_color", UiKit.accent() if m == mode else Palette.ICE)
	rows_part.build(_body, mode)
	_build_pickers()
	_show_warning()
	_lock(not pending.is_empty())
	_scroll.set_deferred("scroll_vertical", keep)


## Scroll the list so that row `action` of `row_mode` shows (a test or a picture script uses it).
func scroll_to_row(row_mode: String, action: String) -> void:
	var b: Button = rows_part.by_key.get("%s/%s/0" % [row_mode, action])
	if b != null:
		_scroll.ensure_control_visible.call_deferred(b)


## One picker per key set group whose tab is the one showing: its name, a button for each set (the
## one in force highlighted), the chosen set's one-line description and the note that the layouts
## do not change play yet.
func _build_pickers() -> void:
	for c in _pickers.get_children():
		c.queue_free()
		_pickers.remove_child(c)
	var note := ""
	if mode == "home":
		note = "These layouts take effect when the command view is built; for now your keys play as before."
	elif mode == "flying_board":
		note = "Same as Flying, except the rows below. The movement keys only move the camera here, and the ship coasts."
	for g: Dictionary in KeyMapData.PRESETS:
		if String(g["tab"]) != mode:
			continue
		var row := UiKit.hbox(8)
		row.add_child(UiKit.label(String(g["label"]), 15, UiKit.accent()))
		var chosen := KeyMap.preset_choice(String(g["id"]))
		for pid: String in g["presets"]:
			var b := UiKit.button(String(g["presets"][pid]["label"]), pick_preset.bind(String(g["id"]), pid), 30.0)
			b.toggle_mode = true
			b.button_pressed = pid == chosen
			row.add_child(b)
		_pickers.add_child(row)
		_pickers.add_child(UiKit.label(String(g["presets"][chosen]["text"]), 14, Palette.MIST, true))
	if note != "":
		_pickers.add_child(UiKit.label(note, 14, Palette.MIST, true))
	_pickers.visible = _pickers.get_child_count() > 0


# --- keys, clashes -----------------------------------------------------------------------

## Start waiting for a key for slot `slot` (0 or 1) of row `action` of `row_mode`; `button` is the
## key button that shows "Press a key (Esc cancels)". Returns false and does nothing when a clash is
## waiting for an answer, or the row cannot be changed.
func begin_capture(row_mode: String, action: String, slot: int, button: Button = null) -> bool:
	if not pending.is_empty() or bool(KeyMap.row(row_mode, action).get("fixed", true)):
		return false
	return capture.begin(row_mode, action, slot, button)


## The key `text` was chosen for the slot being waited on (what a key press does, for a test that
## has no keyboard): it is taken, or the clash warning is shown.
func capture_text(text: String) -> void:
	capture.accept(text)


## A key change was made: save it, make the list again and say so.
func after_change() -> void:
	if autosave:
		var err := KeyMap.save(_path())
		if err != OK:
			push_warning("controls: cannot write %s (error %d); the keys will not be remembered" % [_path(), err])
	rebuild()
	changed.emit()


## The key `key` for slot `slot` of row `action` of `row_mode` clashes with `clashes` (the result of
## KeyMap.conflicts()). Show the warning and wait for the player's answer.
func show_clash(row_mode: String, action: String, slot: int, key: String, clashes: Array) -> void:
	var swap_with := {}
	var movable := clashes.filter(func(c: Dictionary) -> bool: return not bool(c["fixed"]) and String(c["variant"]) == "")
	if movable.size() == 1 and clashes.size() == 1 and _can_swap(row_mode, action, slot, key, movable[0]):
		swap_with = movable[0]
	pending = {"mode": row_mode, "action": action, "slot": slot, "key": key, "clashes": clashes, "swap": swap_with}
	_show_warning()
	_lock(true)


## Would Swap work (it makes no new clash and both rows can change)? Tried and undone.
func _can_swap(row_mode: String, action: String, slot: int, key: String, other: Dictionary) -> bool:
	var over := KeyMap.overrides()
	var picks := KeyMap.choices()
	var ok := KeyMap.swap(row_mode, action, slot, key, String(other["mode"]), String(other["action"]))
	KeyMap.replace_state(over, picks)
	return ok


## Put the pending clash (or the clash that a freshly loaded mode already has) in the warning row.
func _show_warning() -> void:
	if pending.is_empty():
		var found := KeyMap.mode_clashes(mode)
		_warn.visible = not found.is_empty()
		_swap_button.visible = false
		_keep_button.visible = false
		if not found.is_empty():
			var names := PackedStringArray()
			for c: Dictionary in found:
				names.append(String(c["label"]))
			_warn_text.text = "Two actions in this mode have the same key: %s. Change one of them." % ", ".join(names)
		return
	var names := PackedStringArray()
	for c: Dictionary in pending["clashes"]:
		names.append(String(c["label"]))
	var can_swap := not (pending["swap"] as Dictionary).is_empty()
	_warn.visible = true
	_warn_text.text = "%s: also %s. %s" % [KeyCodes.display(String(pending["key"])), ", ".join(names), "Swap, or keep the old one." if can_swap else "Keep the old one."]
	_swap_button.visible = can_swap
	_keep_button.visible = true


## The player chose Swap: the other action takes the key this one gave up.
func choose_swap() -> void:
	if pending.is_empty() or (pending["swap"] as Dictionary).is_empty():
		return
	var p := pending
	var o: Dictionary = p["swap"]
	pending = {}
	KeyMap.swap(String(p["mode"]), String(p["action"]), int(p["slot"]), String(p["key"]), String(o["mode"]), String(o["action"]))
	after_change()


## The player chose Keep: nothing changes and the warning goes.
func choose_keep() -> void:
	if pending.is_empty():
		return
	pending = {}
	rebuild()


## While a clash waits for an answer the rest of the page is locked: the tabs, the resets, the
## pickers and the key buttons. Close stays.
func _lock(on: bool) -> void:
	for m: String in _tabs:
		(_tabs[m] as Button).disabled = on
	_reset_mode.disabled = on
	_reset_all.disabled = on
	for p in _pickers.get_children():
		for c in p.get_children():
			if c is Button:
				(c as Button).disabled = on
	for b: Button in rows_part.buttons:
		b.disabled = on or b.has_meta("fixed")


# --- resets and key sets -------------------------------------------------------------------

## Ask `question` in the bar; `on_yes` runs if the player says Yes.
func ask(question: String, on_yes: Callable) -> void:
	_ask_text.text = question
	_on_yes = on_yes
	_ask_box.visible = true


## The player answered Yes to the bar's question.
func confirm_yes() -> void:
	var f := _on_yes
	_on_yes = Callable()
	_ask_box.visible = false
	if f.is_valid():
		f.call()


## The player answered No.
func confirm_no() -> void:
	_on_yes = Callable()
	_ask_box.visible = false


## "Reset this mode": ask once, then take the player's changes off every row of the tab.
func ask_reset_mode() -> void:
	ask("Put every key of this tab back to its default?", func() -> void:
		KeyMap.reset_mode(mode)
		after_change())


## "Reset all": ask once, then take every change and every picked key set back to the defaults.
func ask_reset_all() -> void:
	ask("Put every key of every tab, and the layout, back to the defaults?", func() -> void:
		KeyMap.reset_all()
		after_change())


## Pick key set `preset_id` of group `group`: ask once, because the keys the player changed for the rows
## the sets list are cleared.
func pick_preset(group: String, preset_id: String) -> void:
	if preset_id == KeyMap.preset_choice(group) and KeyMap.choices().has(group):
		return
	var label := String(KeyMap.preset_group(group)["presets"][preset_id]["label"])
	ask("Switch to %s? The keys you changed for it go back to its own." % label, func() -> void:
		KeyMap.set_preset(group, preset_id)
		after_change())


## Put the key in a row back to its default (the little Reset on a changed row).
func reset_row(row_mode: String, action: String) -> void:
	KeyMap.reset_row(row_mode, action)
	after_change()


## While a key is awaited, this page takes the key before anything else sees it, so it never also
## pauses, opens the note box or closes the panel.
func _input(event: InputEvent) -> void:
	if capture != null and capture.active and capture.handle(event):
		get_viewport().set_input_as_handled()
