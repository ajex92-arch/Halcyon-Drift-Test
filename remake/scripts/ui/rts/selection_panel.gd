class_name SelectionPanel
extends Control
## WHAT THIS IS: the Admiral's selection panel at the bottom centre of the command view: with nothing selected a one-line
## hint, with a selection a header (what is selected and the buttons Add, the same class on screen or on the map, every
## squadron) and a tag for each selected squadron (name and state, a pip for each ship alive, a hull bar, an x). The
## mothership, when selected, has a tag of its own. Past twelve squadrons the tags beyond the twelfth merge into one
## class tag per hull ("Fighter x7"), and the tags get smaller, so 21 squadrons show as 12 tags plus class tags.
##
## HOW IT WORKS: a plain Control (no container, so its size is exactly what CommandView gives it) that draws its own
## box in the shared "row" look and holds the header, a pool of 24 SelectionTags and the hint label. refresh() runs
## on the view's 4 Hz beat: it asks the overlay for the selected squadron records, builds one snapshot per tag
## (`_tag_data`) and writes only what changed. A click on a tag narrows the selection to it when
## RtsUiCalls.CHIP_CLICK_NARROWS (else it does nothing); Shift+click and the x take it out. Add is the sticky Shift
## for a mouse-only player (the overlay's `add_mode`). The buttons "On screen" and "On map" take every squadron of
## the first selected squadron's hull inside the view or on the whole map (the double-click routes), All takes every
## squadron (the M key). Every selection change goes through the overlay.
##
## WHO USES IT: CommandView (makes it, sizes it, calls refresh()); tests/rts_tour.gd.

## The most squadrons that get a tag of their own; the rest merge into class tags.
const MAX_SINGLE := 12
## The tags in the pool (twelve squadrons plus up to ten class tags, with room to spare).
const POOL := 24
## Tag sizes: [normal, compact] (pixels).
const TAG_NORMAL := Vector2(102.0, 38.0)
const TAG_COMPACT := Vector2(50.0, 28.0)  # TAG COMPACT (pixels or a count)
## The gap between tags (pixels).
const TAG_GAP := 4.0
## What a squad's state number says (Squad.state).
const STATE_WORDS := ["idle", "moving", "fighting", "retreating", "docked", "refitting", "launching"]

## The command view this belongs to (set by setup()).
var view: CommandView
## The header's words: what is selected.
var _head: Label
## The hint line shown with nothing selected.
var _hint: Label
## The buttons of the header.
var _add: Button
var _screen: Button  # the screen
var _map: Button  # the map
var _all: Button  # the all
## The pooled tags and the squad ids each stands for (an empty list for a hidden tag, [-1] for the mothership).
var _tags: Array[SelectionTag] = []
var _tag_ids: Array = []  # the tag ids
## True when a selection is shown (else the hint line).
var _has := false
## What the last refresh made, so an unchanged snapshot writes nothing.
var _sig := ""


## Make the parts (once) and remember the view.
func setup(v: CommandView) -> void:
	view = v
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hint = UiKit.label("", 12, Palette.MIST)
	_hint.clip_text = true
	add_child(_hint)
	_head = UiKit.label("", 12, Palette.ICE)
	_head.clip_text = true
	add_child(_head)
	_add = _button("Add", "Add on: every click or box adds to the selection (the Shift key for the mouse). Click again to switch off.", func() -> void: _toggle_add())
	_screen = _button("On screen", "Select every squadron of this kind that you can see (double-click a ship).", func() -> void: _same_class(false))
	_map = _button("On map", "Select every squadron of this kind on the whole map (Ctrl and double-click a ship).", func() -> void: _same_class(true))
	_all = _button("All", "Select every squadron (the M key).", func() -> void: view.overlay.select_all_squadrons())
	for i in POOL:
		var t := SelectionTag.new()
		t.setup()
		var idx := i
		t.pressed.connect(func() -> void: _tag_pressed(idx))
		t.remove_pressed.connect(func() -> void: _tag_removed(idx))
		add_child(t)
		_tags.append(t)
		_tag_ids.append([])


## A header button in the plain cell look.
func _button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"RtsCell"
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(on_press)
	add_child(b)
	return b


## Is a selection being shown (not the hint line)?
func has_selection() -> bool:
	return _has


## The size the panel wants inside `room_w` pixels of width: the hint line is 24 px tall, with a selection it is 112 px.
func wanted_size(room_w: float) -> Vector2:
	var w := minf(CommandView.SEL_W, room_w)
	return Vector2(w, CommandView.SEL_H if _has else CommandView.SEL_HINT_H)


## Draw the box (the shared row look).
func _draw() -> void:
	draw_style_box(RtsTheme.look("row"), Rect2(Vector2.ZERO, size))


## Put the header, the hint and the tags where the panel's size says (called when the size or the tag count changes).
func relayout() -> void:
	_hint.position = Vector2(8.0, 4.0)
	_hint.size = Vector2(maxf(40.0, size.x - 16.0), 16.0)
	# The header: the text at the left, the buttons right to left.
	var x := size.x - 6.0
	for pair: Array in [[_all, 34.0], [_map, 52.0], [_screen, 66.0], [_add, 40.0]]:
		var b: Button = pair[0]
		var w: float = pair[1]
		x -= w
		b.position = Vector2(x, 3.0)
		b.size = Vector2(w, 20.0)
		x -= 4.0
	_head.position = Vector2(8.0, 5.0)
	_head.size = Vector2(maxf(40.0, x - 8.0), 16.0)
	_place_tags()


## Lay out the visible tags in rows (a tag is hidden when it has no squadrons).
func _place_tags() -> void:
	var shown := 0
	for i in POOL:
		if not (_tag_ids[i] as Array).is_empty():
			shown += 1
	var compact := shown > MAX_SINGLE
	var ts := TAG_COMPACT if compact else TAG_NORMAL
	var cols := maxi(1, int((size.x - 12.0 + TAG_GAP) / (ts.x + TAG_GAP)))
	var n := 0
	for i in POOL:
		var t := _tags[i]
		if (_tag_ids[i] as Array).is_empty():
			continue
		t.fit(ts, compact)
		t.position = Vector2(6.0 + float(n % cols) * (ts.x + TAG_GAP), 28.0 + float(floori(float(n) / float(cols))) * (ts.y + TAG_GAP))
		n += 1


## Rebuild the snapshot from the overlay's selection (4 times a second).
func refresh() -> void:
	var ov := view.overlay
	var recs := ov.selected_records()
	var has := not recs.is_empty() or ov.sel_base
	if has != _has:
		_has = has
		view.layout(view.get_viewport_rect().size)
	_hint.visible = not has
	_head.visible = has
	for b: Button in [_add, _screen, _map, _all]:
		b.visible = has
	if not has:
		RtsBeat.set_if_changed(_hint, _hint_text())
		_hide_tags(0)
		return
	var items := _items(recs, ov.sel_base)
	var sig := "%s|%s|%s" % [str(items.map(func(it: Dictionary) -> Variant: return it["ids"])), ov.add_mode, ov.sel_base]
	var text := _head_text(recs, ov.sel_base)
	RtsBeat.set_if_changed(_head, text)
	_add.theme_type_variation = &"RtsRowPicked" if ov.add_mode else &"RtsCell"
	_screen.disabled = recs.is_empty()
	_map.disabled = recs.is_empty()
	var changed_shape := sig != _sig
	_sig = sig
	var n := mini(items.size(), POOL)
	for i in POOL:
		if i < n:
			_tag_ids[i] = items[i]["ids"]
			_tags[i].visible = true
			_tags[i].show_data(items[i])
		else:
			_tag_ids[i] = []
			_tags[i].visible = false
	if changed_shape:
		_place_tags()
		for i in n:
			_tags[i]._shown = ""
			_tags[i].show_data(items[i])


## Hide every tag from index `from` on and forget what they stood for.
func _hide_tags(from: int) -> void:
	for i in range(from, POOL):
		_tag_ids[i] = []
		_tags[i].visible = false
	_sig = ""


## The hint line for an empty selection.
func _hint_text() -> String:
	return "Click a ship or drag a box to select squadrons, %s selects them all, right-click sends them to Move." % KeyMap.first_key("shared", "all_squadrons")


## The header: "3 squadrons selected" (and "and the mothership").
func _head_text(recs: Array[Squad], base: bool) -> String:
	var ships := 0
	for rec in recs:
		ships += RtsSelect.ships_of(view.world, rec).size()
	var parts: Array[String] = []
	if not recs.is_empty():
		parts.append("%s selected (%d ships)" % [RtsSquadOrders.squads_word(recs.size()), ships])
	if base:
		parts.append("the mothership" if recs.is_empty() else "and the mothership")
	return " ".join(parts)


## The snapshots of every tag, in order: the mothership first, then the squadrons (the first twelve one by one, the
## rest merged into one class tag per hull).
func _items(recs: Array[Squad], base: bool) -> Array:
	var out: Array = []
	if base:
		out.append(_base_item())
	var singles := mini(recs.size(), MAX_SINGLE)
	for i in singles:
		out.append(_squad_item(recs[i]))
	var classes := {}
	var order: Array[String] = []
	for i in range(singles, recs.size()):
		var hull := recs[i].hull_id
		if not classes.has(hull):
			classes[hull] = []
			order.append(hull)
		(classes[hull] as Array).append(recs[i])
	for hull in order:
		out.append(_class_item(hull, classes[hull]))
	return out


## The snapshot of the mothership's tag.
func _base_item() -> Dictionary:
	var ms := view.world.mothership(view.team)
	var frac := ms.hull_frac() if ms != null and is_instance_valid(ms) else 0.0
	return {"ids": [-1], "text": "Mothership  %d%%" % int(frac * 100.0), "tiny": "Base", "ships": 1, "pips": 1, "hull": frac, "on": false,
		"tip": "Your mothership, hull %d%%. Click to select only it. Squadron orders do not go to it." % int(frac * 100.0)}


## The snapshot of one squadron's tag.
func _squad_item(rec: Squad) -> Dictionary:
	var ships := RtsSelect.ships_of(view.world, rec)
	var frac := _hull_of(ships)
	var state := str(STATE_WORDS[clampi(rec.state, 0, STATE_WORDS.size() - 1)])
	var short := Formations.short_hull(rec.hull_id)
	return {"ids": [rec.id], "text": "%s  %s" % [short, state], "tiny": short.left(4), "ships": ships.size(), "pips": mini(3, rec.max_members), "hull": frac, "on": false,
		"tip": "%s: %d of %d ships, hull %d%%, %s. Click to select only this squadron; Shift+click or the x takes it out." % [str(Ships.HULLS[rec.hull_id]["label"]), ships.size(), rec.max_members, int(frac * 100.0), state]}


## The snapshot of a class tag: every merged squadron of hull `hull`.
func _class_item(hull: String, recs: Array) -> Dictionary:
	var ids: Array = []
	var ships := 0
	var frac := 0.0
	for rec: Squad in recs:
		ids.append(rec.id)
		var s := RtsSelect.ships_of(view.world, rec)
		ships += s.size()
		frac += _hull_of(s)
	frac /= float(maxi(1, recs.size()))
	var label := str(Ships.HULLS[hull]["label"])
	return {"ids": ids, "text": "%s x%d" % [Formations.short_hull(hull), recs.size()], "tiny": "%s x%d" % [Formations.short_hull(hull).left(3), recs.size()], "ships": mini(3, ships), "pips": 3, "hull": frac, "on": false,
		"tip": "%d %s squadrons (%d ships), hull %d%%. Click to select only these; Shift+click or the x takes them out." % [recs.size(), label, ships, int(frac * 100.0)]}


## The mean hull of `ships` (0 with none).
func _hull_of(ships: Array[Ship]) -> float:
	if ships.is_empty():
		return 0.0
	var sum := 0.0
	for s in ships:
		sum += s.hull_frac()
	return sum / float(ships.size())


# --- the clicks ----------------------------------------------------------------------------------

## The Add toggle.
func _toggle_add() -> void:
	view.overlay.add_mode = not view.overlay.add_mode
	refresh()


## "On screen" / "On map": every squadron of the first selected squadron's hull.
func _same_class(whole_map: bool) -> void:
	var recs := view.overlay.selected_records()
	if recs.is_empty():
		return
	var area := Rect2() if whole_map else RtsSelect.view_rect(view.world)
	view.overlay.set_selection(RtsSelect.same_hull(view.world, view.team, recs[0].hull_id, area), false, view.overlay.add_mode)
	refresh()


## A tag was clicked: narrow the selection to it (RtsUiCalls.CHIP_CLICK_NARROWS), or take it out with Shift.
func _tag_pressed(i: int) -> void:
	var ids: Array = _tag_ids[i]
	if ids.is_empty():
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_tag_removed(i)
		return
	if not RtsUiCalls.CHIP_CLICK_NARROWS:
		return
	var squads: Array[int] = []
	for id: int in ids:
		if id >= 0:
			squads.append(id)
	view.overlay.set_selection(squads, ids.has(-1))
	refresh()


## A tag's x (or Shift+click): take the squadrons of the tag out of the selection.
func _tag_removed(i: int) -> void:
	var ids: Array = _tag_ids[i]
	for id: int in ids:
		if id < 0:
			if view.overlay.sel_base:
				view.overlay.toggle_base()
		else:
			view.overlay.remove_squad(id)
	refresh()
