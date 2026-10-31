class_name ControlsRows
extends RefCounted
## WHAT THIS IS: the part of the Controls page that makes the list of rows for one tab.
##
## HOW IT WORKS: build() empties the list and fills it: first the Shared group (keys that work in
## every mode), then the tab's own rows under a small heading for each group (Camera, Selection,
## Orders, Build, Base, Pilot). The Flying with the board open tab lists only the rows that differ from
## Flying, under "Same as Flying, except these". A row has the action's name, two key buttons (a click
## waits for a key: ControlsPage.begin_capture), a small Reset that shows only when the player
## changed the row, a tag "differs in <mode>" where one of its keys means something else in
## another mode, and a grey note: the mouse way to do the same, why the key cannot be changed, what
## the row comes with when it does not work yet, and any extra keys. Text is never smaller than 14
## pixels. The key buttons are kept in `buttons` so the page can lock them while a clash waits.
##
## WHO USES IT: ControlsPage makes one and calls build().

## The order of the groups under a tab.
const GROUP_ORDER := ["Camera", "Selection", "Orders", "Build", "Base", "Pilot", "Shared"]

## The short names of the modes for the "differs in" tag.
const MODE_SHORT := {"home": "Home", "flying": "Flying", "flying_board": "Board open", "shared": "Every mode"}

## The page this part belongs to.
var page: ControlsPage
## Every key button of the list now showing (fixed ones carry the meta "fixed").
var buttons: Array[Button] = []
## The same buttons by "mode/action/slot" (a test or a picture script finds one here).
var by_key := {}


## Remember the page.
func _init(owner: ControlsPage) -> void:
	page = owner


## Empty `body` and make the rows of `mode` in it.
func build(body: VBoxContainer, mode: String) -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	buttons.clear()
	by_key.clear()
	var index := _key_index()
	_heading(body, "Every mode" if mode != "shared" else "Shared")
	for r: Dictionary in KeyMap.visible_rows("shared"):
		_add_row(body, "shared", r, mode, index)
	var rows_here := KeyMap.visible_rows(mode)
	if mode == "flying_board":
		_heading(body, "Same as Flying, except these")
	for g: String in GROUP_ORDER:
		var any := false
		for r: Dictionary in rows_here:
			if String(r["group"]) != g:
				continue
			if not any and mode != "flying_board":
				_heading(body, g)
			any = true
			_add_row(body, mode, r, mode, index)


## A small heading line.
func _heading(body: VBoxContainer, text: String) -> void:
	var l := UiKit.label(text.to_upper(), 14, UiKit.accent())
	l.custom_minimum_size.y = 26.0
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	body.add_child(l)


## Every key text in the three modes with the rows that use it: key -> list of [mode, action], so a row can
## find the keys that mean something else elsewhere.
func _key_index() -> Dictionary:
	var out := {}
	for m: String in ["home", "flying", "flying_board"]:
		for r: Dictionary in KeyMap.rows_in_force(m):
			var rm := String(r["mode"])
			if rm == "shared":
				continue
			for k in KeyMap.effective_keys(rm, String(r["id"])):
				if not out.has(k):
					out[k] = []
				(out[k] as Array).append([m, String(r["id"])])
	return out


## The modes (other than `mode`) where one of the keys of row `id` is used for a different action, as
## words: "Flying" or "Home, Flying". Empty when there is none.
func _differs(mode: String, id: String, keys: Array, index: Dictionary) -> String:
	var found := PackedStringArray()
	for k in keys:
		for pair: Array in index.get(k, []):
			if pair[0] != mode and pair[1] != id and not found.has(MODE_SHORT[pair[0]]):
				found.append(MODE_SHORT[pair[0]])
	return ", ".join(found)


## Add the row `r` (of mode `row_mode`) to `body`, on the tab `tab`.
func _add_row(body: VBoxContainer, row_mode: String, r: Dictionary, tab: String, index: Dictionary) -> void:
	var id := String(r["id"])
	var h := UiKit.hbox(8)
	body.add_child(h)
	var name_label := UiKit.label(String(r["label"]), 15)
	name_label.custom_minimum_size.x = 300.0
	name_label.clip_text = true
	h.add_child(name_label)
	var slots := KeyMap.slot_keys(row_mode, id)
	var locked := bool(r["fixed"])
	for slot in 2:
		var b := Button.new()
		b.text = KeyCodes.display(String(slots[slot])) if String(slots[slot]) != "" else "none"
		b.custom_minimum_size = Vector2(130.0, 28.0)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.disabled = locked
		if locked:
			b.set_meta("fixed", true)
		if String(slots[slot]) == "":
			b.add_theme_color_override("font_color", Palette.MIST)
			b.add_theme_color_override("font_disabled_color", Palette.MIST)
		b.pressed.connect(page.begin_capture.bind(row_mode, id, slot, b))
		h.add_child(b)
		buttons.append(b)
		by_key["%s/%s/%d" % [row_mode, id, slot]] = b
	# The little Reset, only on a row the player changed (a gap of the same width otherwise).
	var gap := Control.new()
	gap.custom_minimum_size.x = 64.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	if KeyMap.is_changed(row_mode, id):
		var rb := UiKit.button("Reset", page.reset_row.bind(row_mode, id), 28.0)
		rb.custom_minimum_size.x = 60.0
		gap.add_child(rb)
	var tag := _differs(tab, id, KeyMap.effective_keys(row_mode, id), index)
	if tag != "" and row_mode != "shared":
		h.add_child(UiKit.label("differs in " + tag, 14, UiKit.accent()))
	var note := UiKit.label(_note(row_mode, r, slots), 14, Palette.MIST)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(note)


## The grey note of a row: why it cannot change, what it follows, what it comes with, extra keys
## and the mouse way.
func _note(row_mode: String, r: Dictionary, slots: Array) -> String:
	var parts := PackedStringArray()
	if String(r["note"]) != "":
		parts.append(String(r["note"]))
	if KeyMap.is_linked(row_mode, String(r["id"])):
		var target := KeyMap.row("flying", String(r["link"]))
		parts.append("Same keys as %s (changing them here changes both)" % String(target["label"]))
	if not KeyMap.is_live(r):
		parts.append("Comes with " + String(KeyMapData.COMES_WITH.get(String(r["since"]), "a later stage")))
	elif row_mode == "home" and KeyMap.row("flying", String(r["id"])).is_empty() == false:
		parts.append("A change here takes effect when the command view is built")
	if slots.size() > 2:
		var more := PackedStringArray()
		for i in range(2, slots.size()):
			more.append(KeyCodes.display(String(slots[i])))
		parts.append("Also " + ", ".join(more))
	if String(r["route"]) != "":
		parts.append("Mouse: " + String(r["route"]))
	return "  ·  ".join(parts)
