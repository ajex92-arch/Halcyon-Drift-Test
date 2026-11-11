class_name CommandCard
extends Control
## WHAT THIS IS: the command card at the bottom left of the command view: the grid of orders, ships and base tools the
## Admiral clicks (or presses the key of), in the AoE and StarCraft way. Three pages, Orders, Build and Base, a tab row
## to switch, the grid of the home layout in force (B and C: 3x3, R T Y / F G H / V B N; A: 4x3, Q W E R / A S D F /
## Z X C V), a fixed extra row of three buttons and More (a pop-out of up to 8 entries), and a result line.
##
## HOW IT WORKS: a Control with a pool of 12 grid cells, 3 extra cells, a More button, 8 pop-out entries and 3 tab
## buttons (CardCell is the cell; CardPages is the table of what goes where; CardState says what each cell shows and
## which of the four looks it wears; CardActions does what a click does). The page follows the selection (squadrons:
## Orders; the mothership alone: Base; nothing: Build; squadrons and the mothership: RtsUiCalls.MIXED_SELECTION_PAGE)
## whenever the selection changes, and a click on a tab switches by hand. Every 0.25 s refresh() writes each shown
## cell's snapshot (only what changed is set). The cell labels show the key from the key map in force (KeyMap), so a
## rebind or another layout shows at once; the labels let the mouse through. key() takes a key press and runs the cell
## whose key it is: an exact match (Shift+V is not V), only for cells on the page in force (the digits 1-0 queue the ten
## hulls on every page: Shift to the cap, Alt repeat; a click carries its own Shift and Alt, never the game's key state,
## which can hold a key whose release was lost). While a verb or tool is armed the last extra cell reads "Cancel
## (Esc)". The result line shows the answer of the last click (the overlay's result_text), in the danger colour with
## the triangle for a refusal.
##
## WHO USES IT: CommandView (makes it, sizes it, refreshes it, passes it the keys); tests/rts_tour.gd.

## The cell height in the grid and in the extra row (pixels).
const CELL_H := 40.0
const EXTRA_H := 28.0  # EXTRA H (pixels or a count)
## The gap between cells (pixels) and the room inside the card.
const GAP := 4.0
const PAD := 4.0  # PAD (pixels or a count)
## Where the grid starts, from the top of the card (the tab row is above it).
const GRID_Y := 28.0
## The pool of grid cells (a 4x3 grid has 12).
const GRID_CELLS := 12
## Pop-out entries.
const LIST_ENTRIES := 8
## How long (match seconds) a result line stays.
const RESULT_LIFE := 12.0

## The command view (set by setup()).
var view: CommandView
## The page shown: "orders", "build" or "base".
var page := "build"
## The tab buttons, by page.
var _tabs := {}
## The grid cells, the extra cells and the More button.
var _grid: Array[CardCell] = []
var _extra: Array[CardCell] = []  # the extra
var _more: Button  # the more
## The pop-out: its entries and which list it shows ("" closed, "more" or "pop").
var _entries: Array[Button] = []
var _open := ""  # the open
## The ids the grid and the extra row hold now ("" for a blank place).
var _grid_ids: Array[String] = []
var _extra_ids: Array[String] = []  # the extra ids
## The result line: the danger triangle and the words, and the time they were set.
var _mark: DangerMark
var _result: Label  # the result
var _result_at := -100.0  # the result at
## The selection and the layout the page was last chosen for.
var _sel_sig := ""
var _layout_sig := ""  # the layout sig
## The Shift and Alt that the last mouse click on a cell or an entry carried. A click takes them from itself, never from the
## game's key state, which can still hold a key whose release never reached the window (a click would then count as
## Alt+click: every Build click turned Repeat on). A press that is not a click (a test's) carries none.
var _click_shift := false
var _click_alt := false  # the click's Alt


## Make the parts and remember the view.
func setup(v: CommandView) -> void:
	view = v
	mouse_filter = Control.MOUSE_FILTER_STOP
	for p: String in CardPages.PAGES:
		var b := Button.new()
		b.text = str(CardPages.LABELS[p])
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = &"RtsCell"
		b.add_theme_font_size_override("font_size", 11)
		var pg := p
		b.pressed.connect(func() -> void: set_page(pg))
		add_child(b)
		_tabs[p] = b
	for i in GRID_CELLS:
		var c := CardCell.new()
		c.setup()
		var idx := i
		c.pressed.connect(func() -> void: _cell_pressed(false, idx))
		c.gui_input.connect(_note_click)
		add_child(c)
		_grid.append(c)
		_grid_ids.append("")
	for i in 3:
		var c := CardCell.new()
		c.setup()
		var idx := i
		c.pressed.connect(func() -> void: _cell_pressed(true, idx))
		c.gui_input.connect(_note_click)
		add_child(c)
		_extra.append(c)
		_extra_ids.append("")
	_more = Button.new()
	_more.text = "More"
	_more.focus_mode = Control.FOCUS_NONE
	_more.theme_type_variation = &"RtsCell"
	_more.add_theme_font_size_override("font_size", 10)
	_more.tooltip_text = "More orders on this page."
	_more.pressed.connect(func() -> void: toggle_list("more"))
	add_child(_more)
	for i in LIST_ENTRIES:
		var e := Button.new()
		e.focus_mode = Control.FOCUS_NONE
		e.theme_type_variation = &"RtsCell"
		e.alignment = HORIZONTAL_ALIGNMENT_LEFT
		e.clip_text = true
		e.add_theme_font_size_override("font_size", 11)
		var idx := i
		e.pressed.connect(func() -> void: _entry_pressed(idx))
		e.gui_input.connect(_note_click)
		e.visible = false
		add_child(e)
		_entries.append(e)
	_mark = DangerMark.new(10.0)
	_mark.visible = false
	add_child(_mark)
	_result = UiKit.label("", 10, Palette.MIST, true)
	_result.clip_text = true
	add_child(_result)
	view.overlay.result_changed.connect(_on_result)
	view.overlay.selection_changed.connect(func() -> void: _open = "")


## The preset of the home layout in force ("A", "B" or "C").
func _preset() -> String:
	return KeyMap.preset_choice("home_layout")


## Place the tabs, the cells, the More button, the pop-out and the result line for the card's size.
func relayout() -> void:
	var preset := _preset()
	var cols := int((CardPages.page(preset, page) as Dictionary)["cols"])
	var inner := size.x - 2.0 * PAD
	var tab_w := (inner - 2.0 * GAP) / 3.0
	var i := 0
	for p: String in CardPages.PAGES:
		var b: Button = _tabs[p]
		b.position = Vector2(PAD + float(i) * (tab_w + GAP), 3.0)
		b.size = Vector2(tab_w, 22.0)
		i += 1
	var cw := floorf((inner - float(cols - 1) * GAP) / float(cols))
	for n in GRID_CELLS:
		var c := _grid[n]
		c.fit(Vector2(cw, CELL_H))
		c.position = Vector2(PAD + float(n % cols) * (cw + GAP), GRID_Y + float(floori(float(n) / float(cols))) * (CELL_H + GAP))
	var ey := GRID_Y + 3.0 * CELL_H + 2.0 * GAP + GAP
	var ew := floorf((inner - 3.0 * GAP) / 4.0)
	for n in 3:
		_extra[n].fit(Vector2(ew, EXTRA_H))
		_extra[n].position = Vector2(PAD + float(n) * (ew + GAP), ey)
	_more.position = Vector2(PAD + 3.0 * (ew + GAP), ey)
	_more.size = Vector2(ew, EXTRA_H)
	for n in LIST_ENTRIES:
		_entries[n].position = Vector2(PAD, GRID_Y + float(n) * 22.0)
		_entries[n].size = Vector2(inner, 20.0)
	var ry := ey + EXTRA_H + GAP
	_mark.position = Vector2(PAD, ry + 1.0)
	_mark.size = Vector2(13.0, 13.0)
	_result.position = Vector2(PAD + 15.0, ry)
	_result.size = Vector2(inner - 15.0, size.y - ry - 3.0)
	_layout_sig = ""
	queue_redraw()


## Draw the card's box (the shared cell look).
func _draw() -> void:
	draw_style_box(RtsTheme.look("cell"), Rect2(Vector2.ZERO, size))


## Choose page `p` by hand (a click on a tab).
func set_page(p: String) -> void:
	if p == page:
		return
	page = p
	_open = ""
	_layout_sig = ""
	relayout()
	refresh()


## The page the selection asks for (see the top).
func auto_page() -> String:
	var ov := view.overlay
	var squads := not ov.sel_squads.is_empty()
	if squads and ov.sel_base:
		return RtsUiCalls.MIXED_SELECTION_PAGE
	if squads:
		return "orders"
	if ov.sel_base:
		return "base"
	return "build"


## Open the pop-out `which` ("more" or "pop"), or close it when it is open already.
func toggle_list(which: String) -> void:
	_open = "" if _open == which else which
	_layout_sig = ""
	refresh()


## The ids of the More list of the page in force: its cells, and on the Orders page one "feat:<id>" entry for each order a feature
## module added (none in today's game).
func _more_ids() -> Array:
	var p := CardPages.page(_preset(), page)
	var out: Array = (p["more"] as Array).duplicate()
	if page == "base" and DoctrineFeature.current() == null:
		out.erase("doctrine")
	if page == "orders":
		for e: Dictionary in CommandOrdersUi.entries(view.world, view.team):
			out.append("feat:" + str(e["id"]))
	return out.slice(0, LIST_ENTRIES)


## The ids of the open pop-out's entries.
func _list_ids() -> Array:
	var p := CardPages.page(_preset(), page)
	return _more_ids() if _open == "more" else (p["pop"] if _open == "pop" else [])


## Close the pop-out if it is open. True when it was.
func close_list() -> bool:
	if _open == "":
		return false
	_open = ""
	_layout_sig = ""
	refresh()
	return true


## Something was done through the card: close the pop-out and refresh at once.
func after_action() -> void:
	_open = ""
	_layout_sig = ""
	refresh()


## Say the overlay's answer on the result line.
func _on_result() -> void:
	var ov := view.overlay
	_result_at = view.world.time
	RtsBeat.set_if_changed(_result, ov.result_text)
	_result.add_theme_color_override("font_color", Palette.ICE if ov.result_ok else Palette.DANGER)
	_mark.visible = not ov.result_ok and ov.result_text != ""
	_result.position.x = PAD + (15.0 if _mark.visible else 0.0)


## A mouse event reached a cell or an entry: note the Shift and Alt it carries (the release comes after the press, so the
## release's are the ones that count when the button reports its press).
func _note_click(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		_click_shift = m.shift_pressed
		_click_alt = m.alt_pressed


## A grid cell or an extra cell was clicked.
func _cell_pressed(extra: bool, idx: int) -> void:
	var id := _extra_ids[idx] if extra else _grid_ids[idx]
	var shift := _click_shift
	var alt := _click_alt
	_click_shift = false
	_click_alt = false
	if extra and idx == 2 and view.overlay.tool != "":
		view.overlay.disarm()
		view.overlay.say("Cancelled", true)
		after_action()
		return
	if id != "":
		CardActions.run(self, page, id, shift, alt)


## A pop-out entry was clicked.
func _entry_pressed(idx: int) -> void:
	var shift := _click_shift
	var alt := _click_alt
	_click_shift = false
	_click_alt = false
	var ids := _list_ids()
	if idx < ids.size():
		if str(ids[idx]).begins_with("feat:"):
			CommandOrdersUi.press(view, str(ids[idx]).substr(5))
			after_action()
			return
		CardActions.run(self, page if _open == "more" else "build", str(ids[idx]), shift, alt)


## Rewrite the card from the match (the view's beat calls this): the page, the cells' snapshots, the pop-out.
func refresh() -> void:
	var ov := view.overlay
	var sig := "%s|%s" % [str(ov.sel_squads), ov.sel_base]
	if sig != _sel_sig:
		_sel_sig = sig
		var want := auto_page()
		if want != page:
			page = want
			_open = ""
			relayout()
	var preset := _preset()
	var p := CardPages.page(preset, page)
	var lay := "%s|%s|%s|%s|%s" % [preset, page, _open, KeyMap.version, view.card_width()]
	var rebuilt := lay != _layout_sig
	if rebuilt:
		_layout_sig = lay
		_assign(p)
	for i in _tabs.size():
		var pg: String = CardPages.PAGES[i]
		var b: Button = _tabs[pg]
		var cur := pg == page
		b.theme_type_variation = &"RtsRowPicked" if cur else (&"RtsCellLocked" if pg == "orders" and ov.sel_squads.is_empty() else &"RtsCell")
		b.tooltip_text = "Orders: select squadrons first." if pg == "orders" and ov.sel_squads.is_empty() else "%s page" % CardPages.LABELS[pg]
	for i in GRID_CELLS:
		if _grid_ids[i] != "":
			_grid[i].show_data(CardState.snapshot(self, page, _grid_ids[i]))
	for i in 3:
		if i == 2 and ov.tool != "":
			_extra[i].show_data({"state": "ready", "name": "Cancel", "sub": "", "key": "Esc", "digit": "", "count": "", "tip": "Cancel the armed tool (Esc).", "share": 1.0, "short": 0.0, "picked": true})
		elif _extra_ids[i] != "":
			_extra[i].show_data(CardState.snapshot(self, page, _extra_ids[i]))
	_more.visible = not _more_ids().is_empty()
	_more.theme_type_variation = &"RtsRowPicked" if _open == "more" else &"RtsCell"
	var ids := _list_ids()
	for i in LIST_ENTRIES:
		var shown := i < ids.size()
		_entries[i].visible = shown
		if shown:
			var epage := page if _open == "more" else "build"
			if str(ids[i]).begins_with("feat:"):
				for e: Dictionary in CommandOrdersUi.entries(view.world, view.team):
					if "feat:" + str(e["id"]) == str(ids[i]):
						RtsBeat.set_if_changed(_entries[i], str(e["text"]))
						_entries[i].tooltip_text = str(e["tip"])
						_entries[i].disabled = bool(e["off"])
				continue
			_entries[i].disabled = false
			var snap := CardState.snapshot(self, epage, str(ids[i]))
			var key := str(snap["key"])
			RtsBeat.set_if_changed(_entries[i], "%s%s%s" % [snap["name"], ("   " + str(snap["sub"])) if str(snap["sub"]) != "" else "", ("   (%s)" % key) if key != "" else ""])
			_entries[i].tooltip_text = str(snap["tip"])
	if view.world.time - _result_at > RESULT_LIFE and _result.text != "":
		_result.text = ""
		_mark.visible = false


## Give the grid and the extra row the cells of page `p` (a page entry of CardPages) and hide the unused cells. The grid
## cells are hidden under the pop-out while it is open.
func _assign(p: Dictionary) -> void:
	var grid: Array = p["grid"]
	var extra: Array = p["extra"]
	for i in GRID_CELLS:
		var id := str(grid[i]) if i < grid.size() else ""
		_grid_ids[i] = id
		_grid[i].visible = id != "" and _open == ""
		_grid[i]._shown = ""
	for i in 3:
		var id := str(extra[i]) if i < extra.size() else ""
		_extra_ids[i] = id
		_extra[i].visible = id != ""
		_extra[i]._shown = ""


## A key press for the card: true when the page in force owns the key (an exact match; the digits 1-0 queue the hulls).
func key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return false
	# The digits: row hull_1 .. hull_10 queue the ten hulls on every page; Shift = to the cap, Alt = repeat.
	for i in 10:
		var keys := KeyMap.effective_keys("home", "hull_%d" % (i + 1))
		for text in keys:
			var p := KeyCodes.parse(String(text))
			if bool(p["ok"]) and not bool(p["mouse"]) and k.physical_keycode == int(p["code"]) and not k.ctrl_pressed and not k.meta_pressed:
				CardActions.run(self, "build", str(Ships.ORDER[i]), k.shift_pressed, k.alt_pressed)
				return true
	# The cells of the page in force, by their key rows.
	for id: String in CardPages.all_ids(_preset(), page):
		var row := str(CardPages.cell(page, id).get("row", ""))
		if row == "":
			continue
		for text in KeyMap.effective_keys("home", row):
			var ev := KeyCodes.make_event(String(text))
			if ev != null and ev.is_match(event, true):
				CardActions.run(self, page, id, false, false)
				return true
	return false
