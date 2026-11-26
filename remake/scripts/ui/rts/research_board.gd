class_name ResearchBoard
extends RefCounted
## WHAT THIS IS: the filters and the search box of the Admiral board's Research tab: a row of switches above the eight research
## columns that narrows the research cards to the ones the player is looking for, and a line "Showing n of N".
##
## HOW IT WORKS: the switches are independent and all of them must hold for a card to show: the class (All, or one research
## column), "Can afford" (the card is not blocked and the treasury covers it, the same test that makes a card dim),
## "Queued" (the research is being done or waits in the team's build list; a flag beside the other states, not a state of its
## own), "Not done" (hides finished research), and a search box (a piece of the name or of the description, in any
## letter case). The choices live in one small Dictionary kept on the board itself (set_meta), so they survive a tab change and
## a window resize, which rebuild the tab's nodes. build_row() makes the row; apply() decides each research card's `visible`
## and does it only when the answer changed, so the board's four refreshes a second change nothing most of the time. A hidden
## card keeps its node and its key ("tech:<id>"), and a column whose cards are all hidden is hidden whole (its name and its
## "Needs the ..." line with it). The module grid above the columns is never filtered.
## The search box takes the keyboard only when it is clicked. Enter gives it back; Esc gives it back first and closes the
## board only on the next press; while it holds the keyboard the game's own keys (B, P, U, ...) type letters instead.
## This is a "static library": plain functions with no state of their own, except `changes`.
##
## WHO USES IT: AdmiralBoardResearch (build() makes the row, refresh() calls apply()), tests/rts_tour_research.gd.

## The key of the board's meta that holds the choices.
const META := "rb_state"
## The key of the board's meta that holds the row's widgets (so a Clear can put them back).
const META_WIDGETS := "rb_widgets"
## The longest search the box takes.
const SEARCH_MAX := 40
## The three flag switches: choice key -> button text.
const FLAGS := {"afford": "Can afford", "queued": "Queued", "undone": "Not done"}

## How many times apply() changed a card's or a column's `visible` since the game started (the check counts a run of refreshes).
static var changes := 0


## The choices on board `b`, made with nothing chosen the first time: {"cls": "" (all) or a column id, "afford", "queued",
## "undone": bool, "search": String}.
static func state(b: AdmiralBoard) -> Dictionary:
	if not b.has_meta(META):
		b.set_meta(META, {"cls": "", "afford": false, "queued": false, "undone": false, "search": ""})
	return b.get_meta(META)


## Is any choice made on board `b`?
static func active(b: AdmiralBoard) -> bool:
	var st := state(b)
	return st["cls"] != "" or st["afford"] or st["queued"] or st["undone"] or st["search"] != ""


## Should research card `id` show for team `ts` under choices `st`? Every switch that is on must hold.
static func shows(ts: TeamState, id: String, st: Dictionary) -> bool:
	var d: Dictionary = Tech.TECHS[id]
	if st["cls"] != "" and d["column"] != st["cls"]:
		return false
	if st["undone"] and ts.done.has(id):
		return false
	var term := String(st["search"]).strip_edges().to_lower()
	if term != "" and not (String(d["label"]).to_lower().contains(term) or Tech.blurb(id).to_lower().contains(term)):
		return false
	if st["afford"] and not (ts.tech_blocker(id) == "" and ts.can_afford(float(d["cost"]))):
		return false
	if st["queued"] and not is_queued(ts, id):
		return false
	return true


## Is research `id` being done, or waiting in the team's build list?
static func is_queued(ts: TeamState, id: String) -> bool:
	return ts.is_researching(id) or AdmiralBoardResearch._list_text(ts, Production.RESEARCH, id) != ""


## Make the filter row on board `b`'s Research tab and add it to the tab's content: the class buttons, the three flags, the
## search box, Clear and the count. It wraps onto more lines in a narrow window.
static func build_row(b: AdmiralBoard) -> void:
	var st := state(b)
	var widgets := {"cls": {}, "flags": {}}
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.custom_minimum_size = Vector2(b._inner_w(), 0.0)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b._content.add_child(flow)
	# The class: All, then one button for each research column (a radio group: exactly one is on).
	var group := ButtonGroup.new()
	var entries: Array = [["", "All"]]
	for col: String in Tech.COLUMNS:
		entries.append([col, String(Tech.COLUMN_LABEL[col])])
	for e: Array in entries:
		var value := String(e[0])
		var btn := _chip(String(e[1]))
		btn.button_group = group
		btn.button_pressed = st["cls"] == value
		btn.toggled.connect(func(on: bool) -> void:
			if on:
				st["cls"] = value
				apply(b))
		flow.add_child(btn)
		(widgets["cls"] as Dictionary)[value] = btn
	# The three flags.
	for key: String in FLAGS:
		var fk := key
		var fb := _chip(String(FLAGS[key]))
		fb.button_pressed = bool(st[key])
		fb.toggled.connect(func(on: bool) -> void:
			st[fk] = on
			apply(b))
		flow.add_child(fb)
		(widgets["flags"] as Dictionary)[key] = fb
	# The search box, Clear and the count.
	var box := LineEdit.new()
	box.placeholder_text = "Search research"
	box.max_length = SEARCH_MAX
	box.custom_minimum_size = Vector2(170.0, 30.0)
	box.focus_mode = Control.FOCUS_CLICK
	box.text = String(st["search"])
	box.add_theme_font_size_override("font_size", 13)
	box.text_changed.connect(func(t: String) -> void:
		st["search"] = t
		apply(b))
	box.text_submitted.connect(func(_t: String) -> void: box.release_focus())
	box.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			box.release_focus()
			box.accept_event())
	box.visibility_changed.connect(func() -> void:
		if not box.is_visible_in_tree():
			box.release_focus())
	flow.add_child(box)
	widgets["search"] = box
	var clear := UiKit.button("Clear", func() -> void: clear_choices(b), 30.0)
	clear.add_theme_font_size_override("font_size", 13)
	flow.add_child(clear)
	var count := UiKit.label("", 13, Palette.MIST)
	count.custom_minimum_size = Vector2(0.0, 30.0)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flow.add_child(count)
	widgets["count"] = count
	b.set_meta(META_WIDGETS, widgets)


## Put every choice back to nothing chosen, the buttons and the box with them, and show every card.
static func clear_choices(b: AdmiralBoard) -> void:
	var st := state(b)
	st["cls"] = ""
	st["afford"] = false
	st["queued"] = false
	st["undone"] = false
	st["search"] = ""
	var widgets: Dictionary = b.get_meta(META_WIDGETS, {})
	if not widgets.is_empty():
		for value: String in (widgets["cls"] as Dictionary):
			((widgets["cls"] as Dictionary)[value] as Button).set_pressed_no_signal(value == "")
		for key: String in (widgets["flags"] as Dictionary):
			((widgets["flags"] as Dictionary)[key] as Button).set_pressed_no_signal(false)
		(widgets["search"] as LineEdit).text = ""
	apply(b)


## Show or hide every research card of board `b`'s Research tab by the choices, and write the count. A card's or a column's
## `visible` is set only when the answer changed. Does nothing on another tab (the Mothership tab shares the card code).
static func apply(b: AdmiralBoard) -> void:
	if b.tab != "Research" or not b.has_meta(META):
		return
	var ts := b._ts()
	var st := state(b)
	var shown := 0
	var per_column := {}
	for id: String in Tech.ORDER:
		var card := b._cards.get("tech:" + id) as Control
		if card == null or not is_instance_valid(card):
			continue
		var want := shows(ts, id, st)
		if card.visible != want:
			card.visible = want
			changes += 1
		if want:
			shown += 1
			per_column[Tech.TECHS[id]["column"]] = true
	for col: String in Tech.COLUMNS:
		var cv := b._cards.get("col:" + col) as Control
		if cv != null and is_instance_valid(cv):
			var col_want := per_column.has(col)
			if cv.visible != col_want:
				cv.visible = col_want
				changes += 1
	var widgets: Dictionary = b.get_meta(META_WIDGETS, {})
	if widgets.has("count"):
		UiKit.set_text(widgets["count"] as Label, "Showing %d of %d" % [shown, Tech.ORDER.size()])


## A small toggle button (13 px text, 30 px tall) that never takes the keyboard.
static func _chip(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0.0, 30.0)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 13)
	return btn
