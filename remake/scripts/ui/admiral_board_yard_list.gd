class_name AdmiralBoardYardList
extends RefCounted
## WHAT THIS IS: the build list on the Yard tab of the Admiral board: one row for every
## item of the team's build list (ships, research, modules and mining drones), with
## what it is, its state, how far it is, and the buttons Cancel, Hold (or Resume), Up and
## Down.
##
## HOW IT WORKS: build() makes a pool of 16 rows once (the longest list there can be:
## 5 ships, 3 research, 2 modules and 6 drones) and hides them. refresh() fills the first
## rows with the items in list order and hides the rest, 4 times a second, and sets a
## text only when it changed. A row's state text comes from Production.state_text();
## "waiting: fleet full" and "waiting: mothership" are shown in the danger colour with
## the danger triangle, a building item in ICE, a waiting or held item in MIST. Each
## button sends an order about the item the row shows now (CANCEL, HOLD_ITEM, MOVE_ITEM)
## through AdmiralBoardFleet.send(); Up is greyed on the first row and Down on the last.
## This is a "static library": plain functions with no state of their own.
##
## WHO USES IT: AdmiralBoardFleet.build() and AdmiralBoardFleet.refresh().

## How many rows the pool has.
const ROWS := 16


## Make the pool of rows under the tab's content on board `b`.
static func build(b: AdmiralBoard) -> void:
	var rows: Array = []
	for i in ROWS:
		var row := UiKit.hbox(6)
		row.visible = false
		var mark := DangerMark.new(12.0)
		mark.visible = false
		var name_label := UiKit.label("", 14, Palette.ICE)
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.clip_text = true
		var mid := UiKit.vbox(2)
		mid.custom_minimum_size = Vector2(230, 0)
		var state := UiKit.label("", 13, Palette.MIST)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(state)
		mid.add_child(bar)
		var cancel := UiKit.button("Cancel", func() -> void: _send(b, row, OrderKinds.CANCEL, {}), 28)
		var hold := UiKit.button("Hold", func() -> void: _send(b, row, OrderKinds.HOLD_ITEM, {"hold": 0 if bool(row.get_meta("held", false)) else 1}), 28)
		var up := UiKit.button("Up", func() -> void: _send(b, row, OrderKinds.MOVE_ITEM, {"dir": -1}), 28)
		var down := UiKit.button("Down", func() -> void: _send(b, row, OrderKinds.MOVE_ITEM, {"dir": 1}), 28)
		for c: Control in [mark, name_label, mid, cancel, hold, up, down]:
			row.add_child(c)
		b._content.add_child(row)
		rows.append({"row": row, "mark": mark, "name": name_label, "state": state, "bar": bar, "cancel": cancel, "hold": hold, "up": up, "down": down})
	b._cards["yard_rows"] = rows


## Fill the rows from the team's build list.
static func refresh(b: AdmiralBoard) -> void:
	if not b._cards.has("yard_rows"):
		return
	var p := b._ts().production
	var rows: Array = b._cards["yard_rows"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var row: Control = r["row"]
		if i >= p.items.size():
			if row.visible:
				row.visible = false
			continue
		var it: Dictionary = p.items[i]
		if not row.visible:
			row.visible = true
		row.set_meta("item", str(it["id"]))
		row.set_meta("held", bool(it["held"]))
		UiKit.set_text(r["name"], "%s  ·  %d" % [p.label(it), int(it["price"])])
		var text := p.state_text(it)
		UiKit.set_text(r["state"], text)
		var danger: bool = text == "waiting: fleet full" or text == "waiting: mothership"
		var color: Color = Palette.DANGER if danger else (Palette.ICE if it["running"] else Palette.MIST)
		if (r["state"] as Label).get_theme_color("font_color") != color:
			(r["state"] as Label).add_theme_color_override("font_color", color)
		var mark: Control = r["mark"]
		if mark.visible != danger:
			mark.visible = danger
		var bar: ProgressBar = r["bar"]
		var pct := float(p.percent(it)) if it["started"] else 0.0
		if bar.value != pct:
			bar.value = pct
		UiKit.set_text(r["hold"], "Resume" if it["held"] else "Hold")
		var up: Button = r["up"]
		var down: Button = r["down"]
		if up.disabled != (i == 0):
			up.disabled = i == 0
		if down.disabled != (i == p.items.size() - 1):
			down.disabled = i == p.items.size() - 1


## A row's button was pressed: send `kind` about the item the row shows now.
static func _send(b: AdmiralBoard, row: Control, kind: String, settings: Dictionary) -> void:
	if not row.has_meta("item"):
		return
	AdmiralBoardFleet.send(b, Order.make(kind, b.team, Rules.ADMIRAL_SEAT, true, settings, [], "item", str(row.get_meta("item"))))
