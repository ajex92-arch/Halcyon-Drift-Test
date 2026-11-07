class_name RtsTourCard
extends RefCounted
## WHAT THIS IS: the command card's checks of the RTS tour: that every key row of a page has a cell in every home layout and no
## key does two things on a page, that the page follows the selection, that the Orders cells light only for Move, Hold and Stop,
## the four looks of a Build cell (ready, cannot pay with the wash, locked, full), what a click and a key send, and Cancel
## while a tool is armed.
##
## HOW IT WORKS: static functions that take the tour (it counts the failures and prints the lines). The card is driven
## through its own functions (set_page, refresh, CardActions.run, view.key with a built key event) and read through the
## snapshots it shows (`CardCell.data`). The treasury and the fleet counter are changed to make each look and put back at
## the end; the checks never wait for a tick except the last one (`after_ticks`), which sees the queued ship in the list.
##
## WHO USES IT: tests/rts_tour.gd.

## The hull queued by the click check, to find it in the list after the ticks.
static var _queued_hull := ""
## How many items the list had before the click.
static var _items_before := 0


## A key press of physical key `code` (with Shift or Alt) as the keyboard sends it.
static func _key(code: Key, shift: bool = false, alt: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	e.alt_pressed = alt
	return e


## The snapshot the cell `id` of the current page shows, after refreshing the card ({} when it is not in the grid or the extra row).
static func shown(card: CommandCard, id: String) -> Dictionary:
	card.refresh()
	var i := card._grid_ids.find(id)
	if i >= 0:
		return card._grid[i].data
	i = card._extra_ids.find(id)
	return card._extra[i].data if i >= 0 else {}


## Every key row with a page has a cell on its page in layouts B, A and C, and no key does two things on a page.
static func table(tour: Node) -> void:
	var before := KeyMap.preset_choice("home_layout")
	for preset: String in ["B", "A", "C"]:
		KeyMap.set_preset("home_layout", preset)
		var missing := CardPages.rows_without_cell(preset)
		tour.check("card layout %s: every key row of a page has a cell on its page" % preset, missing.is_empty(), str(missing))
		var clashes: Array[String] = []
		for pg: String in CardPages.PAGES:
			var seen := {}
			for id: String in CardPages.all_ids(preset, pg):
				var row := str(CardPages.cell(pg, id).get("row", ""))
				if row == "":
					continue
				for k in KeyMap.effective_keys("home", row):
					var key := "%s|%s" % [pg, KeyCodes.canonical(String(k))]
					if seen.has(key) and seen[key] != row:
						clashes.append("%s: %s and %s on %s" % [pg, seen[key], row, k])
					seen[key] = row
		tour.check("card layout %s: no key does two things on a page" % preset, clashes.is_empty(), str(clashes))
	KeyMap.set_preset("home_layout", before)


## The page follows the selection, and the Orders cells light for Move, Hold and Stop only.
static func pages_and_orders(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var card := view.card
	var ov := view.overlay
	var recs := RtsSelect.our_squads(tour.world, tour.world.human_team)
	ov.clear_selection()
	card.refresh()
	tour.check("card: nothing selected shows the Build page", card.page == "build", card.page)
	ov.set_selection([recs[0].id], false)
	card.refresh()
	tour.check("card: squadrons selected show the Orders page", card.page == "orders", card.page)
	ov.set_selection([], true)
	card.refresh()
	tour.check("card: the mothership alone shows the Base page", card.page == "base", card.page)
	ov.set_selection([recs[0].id], true)
	card.refresh()
	tour.check("card: squadrons and the mothership show the page of RtsUiCalls.MIXED_SELECTION_PAGE", card.page == RtsUiCalls.MIXED_SELECTION_PAGE, card.page)
	ov.set_selection([recs[0].id], false)
	card.set_page("orders")
	var live: Array[String] = []
	var locked_ok := true
	for pg_id: String in CardPages.all_ids(card._preset(), "orders"):
		var d := CardState.snapshot(card, "orders", pg_id)
		var kind := str(CardPages.cell("orders", pg_id)["kind"])
		var want_live := OrderKinds.BOUGHT_KINDS.has(kind)
		if str(d["state"]) == "ready":
			live.append(pg_id)
		if want_live != (str(d["state"]) == "ready"):
			locked_ok = false
		if not want_live and str(d["sub"]) != "later stage":
			locked_ok = false
	live.sort()
	tour.check("card: only Move, Hold and Stop are lit on the Orders page", live == ["hold", "move", "stop"] and locked_ok, str(live))
	ov.clear_selection()
	var none_live := true
	for pg_id: String in ["move", "hold", "stop"]:
		none_live = none_live and str(CardState.snapshot(card, "orders", pg_id)["state"]) == "locked"
	tour.check("card: with no squadron selected the Orders cells are locked ('select first')", none_live)
	card.set_page("build")


## The four looks of a Build cell, the wash, and what a click and a key send.
static func build_looks(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var card := view.card
	var world: World = tour.world
	var ts: TeamState = world.teams[view.team]
	var p := ts.production
	card.set_page("build")
	var saved_money := ts.treasury
	var saved_reserved := p.capacity.reserved
	var price := RtsHulls.price_of("fighter", mini(int(view.yard["count"]), RtsHulls.max_count("fighter")))
	# The fleet fill left the fleet at its limit: make room for the ready and cannot-pay looks (reserved places can be set
	# below zero for a moment), and put it back for the full look.
	var roomy := saved_reserved - (p.capacity.used() - 5)
	p.capacity.reserved = roomy
	ts.treasury = 1.0e9
	var d := shown(card, "fighter")
	tour.check("card build: a hull you can pay for is ready", str(d.get("state", "")) == "ready" and str(d.get("sub", "")) == str(price), str(d))
	ts.treasury = float(price) * 0.25
	d = shown(card, "fighter")
	tour.check("card build: short of ore the cell is cannot_pay with 'short N' and stays live", str(d.get("state", "")) == "cannot_pay" and str(d.get("sub", "")).begins_with("short "), str(d))
	var i := card._grid_ids.find("fighter")
	var cell := card._grid[i]
	tour.check("card build: the cannot-pay look follows RtsUiCalls.CANNOT_PAY_LOOK (%s)" % RtsUiCalls.CANNOT_PAY_LOOK, _look_ok(cell, d), str(d))
	var deep := float(d.get("short", 0.0))
	ts.treasury = float(price) * 0.75
	d = shown(card, "fighter")
	tour.check("card build: the wash is deeper the bigger the shortfall", float(d.get("short", 0.0)) < deep, "%s then %s" % [deep, d.get("short", 0.0)])
	tour.check("card build: a cell short of ore is not disabled", not cell.disabled)
	ts.treasury = 1.0e9
	p.capacity.reserved = saved_reserved
	d = shown(card, "fighter")
	tour.check("card build: a full fleet shows 'fleet full' with the triangle and stays clickable", str(d.get("state", "")) == "full" and str(d.get("sub", "")) == "fleet full" and not card._grid[card._grid_ids.find("fighter")].disabled and card._grid[card._grid_ids.find("fighter")]._mark.visible, str(d))
	p.capacity.reserved = roomy
	var locked_hull := ""
	for h: String in Ships.ORDER:
		if not UnlockAll.is_unlocked(ts) and not ts.ship_unlocked(h):
			locked_hull = h
			break
	if locked_hull != "":
		d = CardState.snapshot(card, "build", locked_hull)
		tour.check("card build: a locked hull is dimmed with its reason", str(d["state"]) == "locked" and str(d["tip"]).contains("Needs"), str(d))
	# A click sends PRODUCE; the ship is in the list after a tick.
	ts.treasury = 1.0e9
	_items_before = p.items.size()
	_queued_hull = "fighter"
	CardActions.run(card, "build", "fighter")
	var sent: Dictionary = world.orders.last_submitted
	tour.check("card build: a click on Fighter sends PRODUCE for the hull", str(sent.get("kind", "")) == OrderKinds.PRODUCE and str((sent["settings"] as Dictionary).get("hull", "")) == "fighter", str(sent))
	tour.check("card build: the result line says what was queued", view.overlay.result_text.begins_with("Queued"), view.overlay.result_text)
	# Keys: R is the Fighter under layout B, 2 is the Fighter everywhere; Shift queues up to the list's depth.
	var kept := KeyMap.preset_choice("home_layout")
	KeyMap.set_preset("home_layout", "B")
	card.set_page("build")
	var next_before: int = world.orders.next_id
	tour.check("card keys: R (layout B, Build page) is taken by the card", view.key(_key(KEY_R)))
	tour.check("card keys: R sent an order", world.orders.next_id == next_before + 1)
	var n2: int = world.orders.next_id
	tour.check("card keys: the digit 2 queues the Fighter on any page", view.key(_key(KEY_2)) and world.orders.next_id == n2 + 1)
	tour.check("card keys: a key the page does not own is left alone", not view.key(_key(KEY_J)))
	KeyMap.set_preset("home_layout", kept)
	ts.treasury = saved_money
	p.capacity.reserved = saved_reserved
	tour.hud._close_others(null)
	card.refresh()


## Does the cannot-pay cell wear the look RtsUiCalls.CANNOT_PAY_LOOK names: the wash (with the triangle) or the ore bar?
static func _look_ok(cell: CardCell, d: Dictionary) -> bool:
	if RtsUiCalls.CANNOT_PAY_LOOK == "wash":
		return cell._wash.visible and cell._mark.visible and not cell._bar.visible and cell._wash.color.a > 0.1 and float(d["short"]) > 0.0
	return cell._bar.visible and not cell._wash.visible and float(d["share"]) < 1.0


## Cancel while a tool is armed, and a base tool arming.
static func armed(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var card := view.card
	var ov := view.overlay
	card.set_page("base")
	CardActions.run(card, "base", "ward")
	card.refresh()
	tour.check("card base: the Ward cell arms the ward tool", ov.tool == "ward")
	var last: Dictionary = card._extra[2].data
	tour.check("card: while a tool is armed the last extra cell reads Cancel (Esc)", str(last.get("name", "")) == "Cancel" and str(last.get("key", "")) == "Esc", str(last))
	card._cell_pressed(true, 2)
	tour.check("card: a click on Cancel disarms the tool", ov.tool == "")
	card.set_page("build")


## Put the treasury at `money` ore (-1 puts back what was there) and show the Build page: the picture of the cannot-pay look
## wants some cells paid for and some not.
static var _kept_money := -1.0
static var _kept_reserved := 0  # the reserved places before


## Put the treasury at `money` ore (-1 puts back what was there) and show the Build page with room in the fleet: the picture of the cannot-pay look
## wants some cells paid for and some not.
static func prep_money(tour: Node, money: float) -> void:
	var view: CommandView = tour.hud.command_view
	var ts: TeamState = tour.world.teams[view.team]
	var cap := ts.production.capacity
	if money >= 0.0:
		if _kept_money < 0.0:
			_kept_money = ts.treasury
			_kept_reserved = cap.reserved
		ts.treasury = money
		cap.reserved = _kept_reserved - (cap.used() - 5)
		view.card.set_page("build")
	elif _kept_money >= 0.0:
		ts.treasury = _kept_money
		cap.reserved = _kept_reserved
		_kept_money = -1.0
	view.refresh()


## After ticks: the Fighter the click queued is in the list (or has started).
static func after_ticks(tour: Node) -> void:
	if _queued_hull == "":
		return
	var view: CommandView = tour.hud.command_view
	var p: Production = (tour.world.teams[view.team] as TeamState).production
	var found := false
	for it: Dictionary in p.items:
		if str(it["what"]) == _queued_hull:
			found = true
	tour.check("card build: the queued Fighter is in the build list (or already out)", found or p.items.size() > _items_before or tour.world.teams[view.team].production.ships_building() > 0)
