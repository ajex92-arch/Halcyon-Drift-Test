class_name ProductionPanel
extends Control
## WHAT THIS IS: the production panel at the top right of the command view (C1, the list): the build list as one row per item in
## the order ore is paid (ships, research, modules and drones together), each with its state in words, a bar and buttons, and below it
## the choices for new ships (squadron size, repeat, rally). It folds to its 26 px header. It replaces the Yard tab.
##
## HOW IT WORKS: a Control of 280 x 280 with a header (the count and the list's need, the filters All, Ships, Research and Drones, and
## Fold), a clipped area of 16 pooled ProductionRows of which 8 show (the list scrolls with the wheel; the picked row stays in view) and a
## footer. refresh() runs on the view's 4 Hz beat: it builds one snapshot per row from the team's list (identical waiting drones stack
## into one row with a count) and writes only what changed. Every edit is an order through the order queue
## (`world.orders.submit(Order.make(kind, team, ADMIRAL_SEAT, true, settings, [], "item", id))`): CANCEL, HOLD_ITEM, MOVE_ITEM, and
## SET_REPEAT (target a hull id). Cancel of a started item asks once more for RtsUiCalls.CANCEL_STARTED_CONFIRM_S seconds ("sure? N% of the
## build lost; the ore comes back in full": a started cancel gives back all it paid); an item not started cancels at once. A click picks a
## row and shows Up and Down (the route that needs no drag); a drag on the grip reorders when RtsUiCalls.DRAG_REORDER_ON (one MOVE_ITEM per
## step, in order). The state words: "building 60%", "needs 1,050 ore in 0:34", "waits behind Destroyer", "held 30% - keeps 1,250", "needs
## Command Systems", "waiting: fleet full" (danger colour with the triangle). A row whose edit waits in the queue (an order given in the
## command pause) says "pending".
##
## WHO USES IT: CommandView (makes it, places it, refreshes it); TopStrip and CommandCard fold and open it; tests/rts_tour.gd.

## The panel's width and the rows' height (pixels), how many rows show, and the pool.
const W := 280.0
const HEAD_H := 26.0  # HEAD H (pixels or a count)
const ROW_H := 26.0  # ROW H (pixels or a count)
const SHOWN := 8  # SHOWN (pixels or a count)
const POOL := 16  # POOL (pixels or a count)
## Where the footer starts.
const FOOT_Y := HEAD_H + 2.0 + float(SHOWN) * ROW_H + 4.0

## The command view (set by setup()).
var view: CommandView
## True while the panel is folded to its header.
var folded := false
## The filter: "all", "ships", "research" or "drones".
var filter := "all"
## The picked item's id ("" for none).
var _picked := ""
## The first row shown (the scroll, in rows).
var _scroll := 0
## The header's words, the filter buttons, the Fold button.
var _count: Label
var _filters := {}  # the filters
var _fold: Button  # the fold
## The clipped area and the rows in it.
var _area: Control
var _rows: Array[ProductionRow] = []  # the rows
## The entries the rows stand for now: {ids, index (place in the whole list), it}.
var _entries: Array = []
## The footer's buttons.
var _sizes: Array[Button] = []
var _repeat: Button  # the repeat
var _rally := {}  # the rally
## The item whose started Cancel is asked again, and until when (real milliseconds).
var _confirm_id := ""
var _confirm_until := 0  # the confirm until
## The row index where a drag of the grip is now (-1 for none).
var _drag_to := -1


## Make the parts and remember the view.
func setup(v: CommandView) -> void:
	view = v
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	_count = UiKit.label("", 10, Palette.ICE)
	_count.clip_text = true
	add_child(_count)
	for f: String in ["all", "ships", "research", "drones"]:
		var b := _small(f.capitalize(), "Show %s." % ("every item" if f == "all" else f), func() -> void: _set_filter(f))
		_filters[f] = b
	_fold = _small("-", "Fold the production panel to its header.", func() -> void: set_folded(not folded))
	_area = Control.new()
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_area)
	for i in POOL:
		var r := ProductionRow.new()
		r.setup()
		r.mouse_force_pass_scroll_events = false
		var idx := i
		r.picked.connect(func() -> void: _pick(idx))
		r.repeat_pressed.connect(func() -> void: _repeat_row(idx))
		r.hold_pressed.connect(func() -> void: _hold_row(idx))
		r.cancel_pressed.connect(func() -> void: _cancel_row(idx))
		r.up_pressed.connect(func() -> void: _move_row(idx, -1))
		r.down_pressed.connect(func() -> void: _move_row(idx, 1))
		r.grip_moved.connect(func(y: float) -> void: _drag_to = clampi(_scroll + floori((y - HEAD_H - 2.0) / ROW_H), 0, maxi(0, _entries.size() - 1)))
		r.grip_dropped.connect(func() -> void: _drop(idx))
		_area.add_child(r)
		_rows.append(r)
	for n in [1, 2, 3]:
		var count: int = n
		_sizes.append(_small(str(n), "Ships in a squadron: %d (small hulls)." % n, func() -> void: view.yard["count"] = count))
	_repeat = _small("Repeat", "Repeat: when a build of the hull you buy is done, the same item is queued again if the list and the fleet have room.", func() -> void: view.yard["repeat"] = not bool(view.yard["repeat"]))
	for kind: String in ["mothership", "lane", "point"]:
		var k := kind
		_rally[kind] = _small({"mothership": "Base", "lane": "Lane", "point": "Spot"}[kind], "Where new ships gather: %s." % {"mothership": "ahead of the mothership", "lane": "on the lane you push", "point": "at a spot you pick on the map"}[kind], func() -> void: _pick_rally(k))


## A small panel button (the plain cell look, 10 px words).
func _small(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"RtsCell"
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(on_press)
	add_child(b)
	return b


## Fold the panel to its header, or open it again.
func set_folded(on: bool) -> void:
	folded = on
	if view != null:
		view.layout(view.get_viewport_rect().size)
		refresh()


## Place the header, the rows and the footer for the panel's size.
func relayout() -> void:
	var x := W - 4.0
	_fold.size = Vector2(20.0, 20.0)
	x -= 20.0
	_fold.position = Vector2(x, 3.0)
	var widths := {"all": 24.0, "ships": 34.0, "research": 50.0, "drones": 38.0}
	for f: String in ["drones", "research", "ships", "all"]:
		var b: Button = _filters[f]
		x -= 2.0 + float(widths[f])
		b.position = Vector2(x, 3.0)
		b.size = Vector2(float(widths[f]), 20.0)
	_count.position = Vector2(6.0, 6.0)
	_count.size = Vector2(maxf(30.0, x - 8.0), 14.0)
	_area.position = Vector2(2.0, HEAD_H + 2.0)
	_area.size = Vector2(W - 4.0, float(SHOWN) * ROW_H)
	for r in _rows:
		r.fit(W - 4.0)
	var fx := 4.0
	for b in _sizes:
		b.position = Vector2(fx, FOOT_Y + 2.0)
		b.size = Vector2(22.0, 22.0)
		fx += 24.0
	_repeat.position = Vector2(fx + 2.0, FOOT_Y + 2.0)
	_repeat.size = Vector2(48.0, 22.0)
	fx += 54.0
	for kind: String in ["mothership", "lane", "point"]:
		var b: Button = _rally[kind]
		b.position = Vector2(fx + 4.0, FOOT_Y + 2.0)
		b.size = Vector2(38.0, 22.0)
		fx += 40.0
	queue_redraw()


## Draw the panel's box (the shared row look).
func _draw() -> void:
	draw_style_box(RtsTheme.look("row"), Rect2(Vector2.ZERO, size))


## The wheel scrolls the list.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP:
			_scroll = maxi(0, _scroll - 1)
			accept_event()
		elif b == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = mini(maxi(0, _entries.size() - SHOWN), _scroll + 1)
			accept_event()


## Choose the filter `f`.
func _set_filter(f: String) -> void:
	filter = f
	_scroll = 0
	refresh()


## Does item `it` pass the filter?
func _passes(it: Dictionary) -> bool:
	match filter:
		"ships":
			return it["kind"] == Production.SHIP
		"research":
			return it["kind"] == Production.RESEARCH or it["kind"] == Production.MODULE
		"drones":
			return it["kind"] == Production.DRONE
	return true


## The team's build list.
func _prod() -> Production:
	return (view.world.teams[view.team] as TeamState).production


## Rebuild the rows from the team's list (the view's beat).
func refresh() -> void:
	var p := _prod()
	var shown := not folded
	for c: Control in [_area, _repeat]:
		c.visible = shown
	for b in _sizes:
		b.visible = shown
	for k: String in _rally:
		(_rally[k] as Button).visible = shown
	for f: String in _filters:
		(_filters[f] as Button).theme_type_variation = &"RtsRowPicked" if f == filter else &"RtsCell"
	RtsBeat.set_if_changed(_fold, "+" if folded else "-")
	_fold.tooltip_text = "Open the production panel." if folded else "Fold the production panel to its header."
	# The header: how many items and what the list still needs.
	var total := 0.0
	for it: Dictionary in p.items:
		if not bool(it["started"]):
			total += float(it["price"])
	var need := total - (view.world.teams[view.team] as TeamState).treasury
	RtsBeat.set_if_changed(_count, ("%d  needs %s" % [p.items.size(), Util.money(need)]) if need > 0.0 else "%d items" % p.items.size())
	if not shown:
		return
	# The entries (stacking identical waiting drones), the pending edits, the picked row in view.
	_entries = _build_entries(p)
	var pending := _pending_ids()
	var found := false
	for i in _entries.size():
		if (_entries[i]["ids"] as Array).has(_picked):
			found = true
			if i < _scroll:
				_scroll = i
			elif i >= _scroll + SHOWN:
				_scroll = i - SHOWN + 1
	if not found:
		_picked = ""
	_scroll = clampi(_scroll, 0, maxi(0, _entries.size() - SHOWN))
	for i in POOL:
		var r := _rows[i]
		r.visible = i < _entries.size()
		if i < _entries.size():
			r.position = Vector2(0.0, float(i - _scroll) * ROW_H)
			r.show_data(_snapshot(p, _entries[i], pending))
	for i in _sizes.size():
		_sizes[i].theme_type_variation = &"RtsRowPicked" if int(view.yard["count"]) == i + 1 else &"RtsCell"
	_repeat.theme_type_variation = &"RtsRowPicked" if bool(view.yard["repeat"]) else &"RtsCell"
	for k: String in _rally:
		(_rally[k] as Button).theme_type_variation = &"RtsRowPicked" if str(view.yard["rally"]) == k else &"RtsCell"


## The entries of the list after the filter: {ids, index, it}; identical waiting drones stack into the first one.
func _build_entries(p: Production) -> Array:
	var out: Array = []
	var stacks := {}
	for i in p.items.size():
		var it: Dictionary = p.items[i]
		if not _passes(it):
			continue
		if it["kind"] == Production.DRONE and not bool(it["started"]) and not bool(it["held"]):
			var key := "%s|%s" % [it["kind"], it["what"]]
			if stacks.has(key):
				((stacks[key] as Dictionary)["ids"] as Array).append(str(it["id"]))
				continue
			var e := {"ids": [str(it["id"])], "index": i, "it": it}
			stacks[key] = e
			out.append(e)
			continue
		out.append({"ids": [str(it["id"])], "index": i, "it": it})
	return out


## The ids of the items an order in the queue (given in the command pause) is about.
func _pending_ids() -> Dictionary:
	var out := {}
	var w := view.world
	for o: Dictionary in w.orders.queue:
		if bool(o.get("human", false)) and OrderKinds.PRODUCTION_KINDS.has(str(o["kind"])) and int(o["apply_tick"]) > w.tick_count:
			out[str(o["target"])] = true
	return out


## The snapshot of the row for `e`.
func _snapshot(p: Production, e: Dictionary, pending: Dictionary) -> Dictionary:
	var it: Dictionary = e["it"]
	var ids: Array = e["ids"]
	var kind := str(it["kind"])
	var title := p.label(it)
	if ids.size() > 1:
		title += " x%d" % ids.size()
	var state := _state_text(p, it)
	var danger := str(it["why"]) == "room" and not bool(it["running"]) and not bool(it["held"])
	var id := str(ids[0])
	var sure := ""
	if _confirm_id == id and Time.get_ticks_msec() < _confirm_until:
		sure = "sure? %d%% of the build lost;|the ore comes back in full" % p.percent(it)
	return {"n": int(e["index"]) + 1, "name": title, "price": Util.money(float(it["price"]) * float(ids.size())), "state": state, "danger": danger,
		"frac": float(p.percent(it)) / 100.0 if bool(it["started"]) else 0.0,
		"color": str(_kind_color(kind).to_html()), "held": bool(it["held"]), "started": bool(it["started"]), "picked": ids.has(_picked),
		"can_repeat": kind == Production.SHIP, "repeat": bool(p.repeat.get(str(it["what"]), false)),
		"up_ok": int(e["index"]) > 0, "down_ok": int(e["index"]) < p.items.size() - 1, "pending": pending.has(id), "sure": sure}


## The colour of the kind mark.
func _kind_color(kind: String) -> Color:
	match kind:
		Production.RESEARCH:
			return Palette.VEIL
		Production.MODULE:
			return Palette.REPAIR
		Production.DRONE:
			return Palette.ORE
	return Palette.ICE


## The state of item `it` in words (see the top).
func _state_text(p: Production, it: Dictionary) -> String:
	if bool(it["held"]):
		var keeps := "  keeps %s" % Util.money(float(it["paid"])) if int(it["paid"]) > 0 else ""
		return "held %d%%%s" % [p.percent(it), keeps] if bool(it["started"]) else "held"
	if bool(it["running"]):
		return p.state_text(it)
	match str(it["why"]):
		"ore":
			var inc: float = view.strip.income / 60.0
			var when := " in %s" % Util.clock(float(it["need"]) / inc) if inc > 0.01 else ""
			return "needs %s ore%s" % [Util.money(float(it["need"])), when]
		"turn":
			for other: Dictionary in p.items:
				if str(other["why"]) == "ore":
					return "waits behind %s" % p.label(other)
			return "waiting: turn"
		"unlock":
			return "needs %s" % str(it["need_text"])
	return p.state_text(it)


# --- the clicks ------------------------------------------------------------------------------------

## The entry of pool row `i` ({} when there is none).
func _entry(i: int) -> Dictionary:
	return _entries[i] if i < _entries.size() else {}


## Send an order about an item through the queue; a refusal is said on the card's result line.
func _send(kind: String, settings: Dictionary, target: String, target_kind: String = "item") -> void:
	var why: String = view.world.orders.submit(Order.make(kind, view.team, Rules.ADMIRAL_SEAT, true, settings, [], target_kind, target))
	if why != "":
		view.overlay.say(why, false)
	refresh()


## A press on row `i`: pick it.
func _pick(i: int) -> void:
	var e := _entry(i)
	if not e.is_empty():
		_picked = str((e["ids"] as Array)[0])
		refresh()


## Repeat for the hull of row `i`.
func _repeat_row(i: int) -> void:
	var e := _entry(i)
	if e.is_empty():
		return
	var hull := str((e["it"] as Dictionary)["what"])
	_send(OrderKinds.SET_REPEAT, {"repeat": 0 if bool(_prod().repeat.get(hull, false)) else 1}, hull, "id")


## Hold or Resume row `i`.
func _hold_row(i: int) -> void:
	var e := _entry(i)
	if not e.is_empty():
		_send(OrderKinds.HOLD_ITEM, {"hold": 0 if bool((e["it"] as Dictionary)["held"]) else 1}, str((e["ids"] as Array)[0]))


## Cancel row `i`: at once for an item not started; a started one asks once more for CANCEL_STARTED_CONFIRM_S seconds.
func _cancel_row(i: int) -> void:
	var e := _entry(i)
	if e.is_empty():
		return
	var id := str((e["ids"] as Array).back())
	var started := bool((e["it"] as Dictionary)["started"]) and (e["ids"] as Array).size() == 1
	if started and RtsUiCalls.CANCEL_STARTED_CONFIRM_S > 0.0 and not (_confirm_id == id and Time.get_ticks_msec() < _confirm_until):
		_confirm_id = id
		_confirm_until = Time.get_ticks_msec() + int(RtsUiCalls.CANCEL_STARTED_CONFIRM_S * 1000.0)
		refresh()
		return
	_confirm_id = ""
	_send(OrderKinds.CANCEL, {}, id)


## Move row `i` one place up (-1) or down (1).
func _move_row(i: int, dir: int) -> void:
	var e := _entry(i)
	if not e.is_empty():
		_send(OrderKinds.MOVE_ITEM, {"dir": dir}, str((e["ids"] as Array)[0]))


## The grip of row `i` was let go: move the item to the row under the pointer, one MOVE_ITEM per step, in order.
func _drop(i: int) -> void:
	var e := _entry(i)
	var to := _drag_to
	_drag_to = -1
	if e.is_empty() or to < 0 or to >= _entries.size() or to == i:
		return
	var delta := int(_entries[to]["index"]) - int(e["index"])
	var dir := 1 if delta > 0 else -1
	for s in absi(delta):
		var why: String = view.world.orders.submit(Order.make(OrderKinds.MOVE_ITEM, view.team, Rules.ADMIRAL_SEAT, true, {"dir": dir}, [], "item", str((e["ids"] as Array)[0])))
		if why != "":
			view.overlay.say(why, false)
			break
	refresh()


## A rally button: choose where new ships gather ("point" arms the map tool: the next click picks the spot).
func _pick_rally(kind: String) -> void:
	view.yard["rally"] = kind
	if kind == "point":
		view.overlay.arm("rally")
