class_name AdmiralBoardFleet
extends RefCounted
## WHAT THIS IS: the Fleet tab of the Admiral board, shown as "Yard": the rally
## waypoint and the yard where the Admiral buys fleet ships.
##
## HOW IT WORKS: build() makes the tab once, in two parts:
##   1. Rally waypoint: a button that arms the "waypoint" map tool (the Admiral then
##      clicks the map), and a line saying where the waypoint is and for how long. Then
##      the buttons of the orders that feature modules add (none in today's game).
##   2. The Yard: the fleet line ("Fleet 12/18, 3 building, 6 waiting", or "Fleet full" in
##      the danger colour with the danger triangle), the answer to the last refused order
##      (danger colour and triangle), one buy button per hull of Ships.ORDER (name, "x3" for
##      a squadron, the Admiral's price, the build time; greyed with "needs X" when locked,
##      never greyed for money, because an item waits for ore), the squadron size, the
##      repeat switch, the rally (mothership, push lane or a spot picked on the map), and
##      the build list (AdmiralBoardYardList).
## Every button sends an order through World.orders.submit(); the tab never changes the
## game itself. refresh() rewrites the lines 4 times a second and sets a text only when it
## changed. Colours are values of Palette: ICE for what is building or normal, MIST for what
## waits, DANGER (always with the triangle) for a full fleet, a refusal and "waiting:
## mothership". Nothing here uses AMBER or CINDER for a state.
## This is a "static library": plain functions with no state of their own. As a part of
## AdmiralBoard it reads the board's fields directly (the choices are in AdmiralBoard.yard).
##
## WHO USES IT: AdmiralBoard._set_tab() calls build() and AdmiralBoard._refresh() calls
## refresh() for the Fleet tab; AdmiralBoardYardList draws the list under it.

## How many buy buttons sit in a row.
const BUY_COLUMNS := 2
## How long (seconds of match time) the answer to a refused order stays on the tab.
const MESSAGE_SECONDS := 8.0


## Build the Fleet tab's cards on board `b` (see HOW IT WORKS).
static func build(b: AdmiralBoard) -> void:
	# Step 1: the rally waypoint button and its status line.
	b._content.add_child(UiKit.heading("Rally waypoint"))
	var wr := UiKit.hbox(10)
	b._content.add_child(wr)
	var wb := UiKit.button("Set the rally waypoint: pick a spot", func() -> void: b._arm("waypoint"), 34)
	b._hover(wb, "For %ds, our ships inside the circle get +8%% speed, +25%% shield regeneration and +15%% vision, and AI pilots group up there. Place it within 6,000 of the enemy mothership to order a SIEGE: our AI frigates, capital ships and bombers converge on that lane and attack the mothership." % int(Rules.WAYPOINT_TIME))
	wr.add_child(wb)
	var wl := UiKit.label("", 13, Palette.MIST)
	wr.add_child(wl)
	b._cards["wp"] = wl
	# Step 1b: the orders that feature modules add (Sensor Sweep, ...); this
	# adds nothing in today's game.
	CommandOrdersUi.build(b)
	# Step 2: the Yard. First the fleet line and the answer to a refused order.
	b._content.add_child(UiKit.heading("Yard"))
	var fleet_row := UiKit.hbox(8)
	b._content.add_child(fleet_row)
	var fleet_mark := DangerMark.new()
	fleet_mark.visible = false
	fleet_row.add_child(fleet_mark)
	var fleet_label := UiKit.label("", 15, Palette.ICE)
	fleet_row.add_child(fleet_label)
	b._cards["yard_fleet_mark"] = fleet_mark
	b._cards["yard_fleet"] = fleet_label
	var msg_row := UiKit.hbox(8)
	msg_row.visible = false
	b._content.add_child(msg_row)
	msg_row.add_child(DangerMark.new())
	var msg_label := UiKit.label("", 14, Palette.DANGER)
	msg_row.add_child(msg_label)
	b._cards["yard_msg_row"] = msg_row
	b._cards["yard_msg"] = msg_label
	# The buy buttons, one per hull.
	b._content.add_child(UiKit.heading("Buy ships: you pay when a build starts, and an item waits for ore"))
	var grid := b._grid(BUY_COLUMNS)
	for hull: String in Ships.ORDER:
		var h := hull
		var btn := UiKit.button("", func() -> void: _buy(b, h), 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(btn)
		b._cards["yard_buy:" + hull] = btn
		b._hover(btn, "%s: %s" % [Ships.HULLS[hull]["label"], Ships.blurb(hull)])
	# The squadron size, the repeat switch and the rally.
	var opts := UiKit.hbox(8)
	b._content.add_child(opts)
	opts.add_child(UiKit.label("Ships in a squadron:", 13, Palette.MIST))
	for n in [1, 2, 3]:
		var count: int = n
		var cb := UiKit.button(str(n), func() -> void: b.yard["count"] = count, 30)
		cb.custom_minimum_size = Vector2(36, 30)
		opts.add_child(cb)
		b._cards["yard_count:%d" % n] = cb
	var rep := UiKit.button("", func() -> void: b.yard["repeat"] = not bool(b.yard["repeat"]), 30)
	b._hover(rep, "Repeat: when a build of the hull you buy is done, the same item is queued again if the list and the fleet have room.")
	opts.add_child(rep)
	b._cards["yard_repeat"] = rep
	var rally := UiKit.hbox(8)
	b._content.add_child(rally)
	rally.add_child(UiKit.label("Rally:", 13, Palette.MIST))
	for kind in ["mothership", "lane", "point"]:
		var k: String = kind
		var rb := UiKit.button("", func() -> void: _pick_rally(b, k), 30)
		rally.add_child(rb)
		b._cards["yard_rally:" + kind] = rb
	var rally_text := UiKit.label("", 13, Palette.MIST)
	rally.add_child(rally_text)
	b._cards["yard_rally_text"] = rally_text
	# The build list.
	b._content.add_child(UiKit.heading("Build list (ore is paid in this order)"))
	AdmiralBoardYardList.build(b)


## Rewrite the Fleet tab on board `b`: the waypoint line, the fleet line, the answer to a
## refused order, the buy buttons, the choices and the build list.
static func refresh(b: AdmiralBoard) -> void:
	var ts := b._ts()
	# Step 1: "Active at <place> for <seconds>s", or "No waypoint set".
	if b._cards.has("wp"):
		var wl: Label = b._cards["wp"]
		wl.text = ("Active at %s for %ds" % [Rules.display_label(b.world.place_name(ts.waypoint)), int(ts.waypoint_until - b.world.time)]) if ts.has_waypoint() else "No waypoint set"
	# Step 1b: the buttons of the orders that feature modules add.
	CommandOrdersUi.refresh(b)
	if not b._cards.has("yard_fleet"):
		return
	# Step 2: the fleet line.
	_refresh_fleet(b, ts)
	# Step 3: the answer to a refused order, until it is old.
	var msg_row: Control = b._cards["yard_msg_row"]
	var msg: Label = b._cards["yard_msg"]
	var show_msg: bool = msg.text != "" and b.world.time < float(msg.get_meta("until", 0.0))
	if msg_row.visible != show_msg:
		msg_row.visible = show_msg
	# Step 4: the buy buttons, the choices and the list.
	for hull: String in Ships.ORDER:
		_refresh_buy(b, ts, hull)
	for n in [1, 2, 3]:
		var cb: Button = b._cards["yard_count:%d" % n]
		_mark_chosen(cb, int(b.yard["count"]) == n)
	var rep: Button = b._cards["yard_repeat"]
	UiKit.set_text(rep, "Repeat: on" if bool(b.yard["repeat"]) else "Repeat: off")
	_mark_chosen(rep, bool(b.yard["repeat"]))
	_refresh_rally(b)
	AdmiralBoardYardList.refresh(b)


## The fleet line: "Fleet 12/18  ·  3 building  ·  6 waiting", or "Fleet full" in the
## danger colour with the triangle when every place is used.
static func _refresh_fleet(b: AdmiralBoard, ts: TeamState) -> void:
	var p := ts.production
	var used := p.capacity.used()
	var limit := p.capacity.limit()
	var building := 0
	var waiting := 0
	for it: Dictionary in p.items:
		if it["kind"] != Production.SHIP:
			continue
		if it["running"]:
			building += int(it["count"])
		else:
			waiting += int(it["count"])
	var full := used >= limit
	var label: Label = b._cards["yard_fleet"]
	UiKit.set_text(label, "%s %d/%d  ·  %d building  ·  %d waiting" % ["Fleet full" if full else "Fleet", used, limit, building, waiting])
	_color(label, Palette.DANGER if full else Palette.ICE)
	var mark: Control = b._cards["yard_fleet_mark"]
	if mark.visible != full:
		mark.visible = full


## One buy button: its name, the squadron size, the price and the time; or "needs X" and
## greyed when the hull is locked. Money never greys it.
static func _refresh_buy(b: AdmiralBoard, ts: TeamState, hull: String) -> void:
	var btn: Button = b._cards["yard_buy:" + hull]
	var count := _count_for(b, hull)
	var name := str(Ships.HULLS[hull]["label"])
	if RtsHulls.max_count(hull) > 1:
		name += " x%d" % count
	var locked := not UnlockAll.is_unlocked(ts) and not ts.ship_unlocked(hull)
	var text := ""
	if locked:
		text = "%s  ·  needs %s" % [name, Tech.ship_unlock_label(hull)]
	else:
		text = "%s  ·  %d  ·  %d s" % [name, RtsHulls.price_of(hull, count), roundi(float(RtsHulls.build_ticks(hull)) / 60.0)]
	UiKit.set_text(btn, text)
	if btn.disabled != locked:
		btn.disabled = locked


## The rally buttons and the line that says where new ships go.
static func _refresh_rally(b: AdmiralBoard) -> void:
	var names := {"mothership": "Mothership", "lane": "Push lane", "point": "Pick a spot"}
	for kind: String in names:
		var rb: Button = b._cards["yard_rally:" + kind]
		UiKit.set_text(rb, str(names[kind]))
		_mark_chosen(rb, str(b.yard["rally"]) == kind)
	var text := "New ships gather ahead of the mothership"
	if str(b.yard["rally"]) == "lane":
		text = "New ships gather on the lane we are pushing"
	elif str(b.yard["rally"]) == "point":
		text = "New ships gather at the spot you picked" if b.overlay != null and b.overlay.rally_set else "Pick a spot on the map (right-click or Esc cancels)"
	UiKit.set_text(b._cards["yard_rally_text"], text)


# --- the buttons -----------------------------------------------------------------------

## The number of ships a squadron of `hull` has under the player's choice: the chosen
## size for a small hull, 1 for the others.
static func _count_for(b: AdmiralBoard, hull: String) -> int:
	return mini(int(b.yard["count"]), RtsHulls.max_count(hull))


## The rally settings of a PRODUCE order from the player's choice: the mothership, the
## push lane, or the picked spot (the mothership while no spot has been picked).
static func rally_settings(b: AdmiralBoard) -> Dictionary:
	var kind := str(b.yard["rally"])
	if kind == "point" and b.overlay != null and b.overlay.rally_set:
		return {"rally": "point", "rx": b.overlay.rally_spot.x, "ry": b.overlay.rally_spot.y}
	if kind == "lane":
		return {"rally": "lane"}
	return {"rally": "mothership"}


## A buy button was pressed: send a PRODUCE order for `hull`.
static func _buy(b: AdmiralBoard, hull: String) -> void:
	if not b._ok():
		return
	var settings := rally_settings(b)
	settings["hull"] = hull
	settings["count"] = _count_for(b, hull)
	settings["repeat"] = 1 if bool(b.yard["repeat"]) else 0
	send(b, Order.make(OrderKinds.PRODUCE, b.team, Rules.ADMIRAL_SEAT, true, settings))


## A rally button was pressed: choose the rally; "point" arms the map tool, where a left
## click picks the spot and a right click or Esc cancels.
static func _pick_rally(b: AdmiralBoard, kind: String) -> void:
	b.yard["rally"] = kind
	if kind == "point":
		b._arm("rally")


## Send order record `o` and show the answer when it is refused at once.
static func send(b: AdmiralBoard, o: Dictionary) -> void:
	if not b._ok():
		return
	var msg := b.world.orders.submit(o)
	if not b._cards.has("yard_msg"):
		return
	var label: Label = b._cards["yard_msg"]
	label.text = msg
	label.set_meta("until", b.world.time + MESSAGE_SECONDS)


# --- small helpers ---------------------------------------------------------------------

## Set label `l`'s text colour to `c` only when it differs.
static func _color(l: Control, c: Color) -> void:
	if l.get_theme_color("font_color") != c:
		l.add_theme_color_override("font_color", c)


## Show button `bt` as chosen (the interface's highlight colour) or not.
static func _mark_chosen(bt: Button, chosen: bool) -> void:
	_color(bt, UiKit.accent() if chosen else Palette.ICE)
