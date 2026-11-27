class_name RtsTourCard
extends RefCounted
## WHAT THIS IS: the command card's checks of the RTS tour: that every key row of a page has a cell in every home layout and no
## key does two things on a page, that the page follows the selection, that the Orders cells light for the orders a bought squadron takes (Position and its three pick entries included) and the goal cells arm their tools,
## the Position pick (it opens only with a squadron selected, a click on an entry sends the move-only stance order and closes it, Esc and a selection change close it),
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


## The page follows the selection, and the Orders cells light for the kinds a bought squadron takes (Move, Hold, Stop, Defend, Escort,
## Push lane, Merge, Stance, Formation, Position with its three pick entries, and the Goal cell); then the Position pick.
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
	tour.check("card: the cells of the orders a bought squadron takes are lit on the Orders page, the rest locked", live == ["defend", "escort", "formation", "goal", "hold", "merge", "move", "pos_hold", "pos_manoeuvre", "pos_roam", "position", "push_lane", "stance", "stop"] and locked_ok, str(live))
	var pos_d := CardState.snapshot(card, "orders", "position")
	tour.check("card: the Position cell is lit with a squadron selected and says its current setting", str(pos_d["state"]) == "ready" and str(pos_d["sub"]) != "", str(pos_d))
	ov.set_selection([recs[0].id], false)
	var arm_ok := true
	for pair: Array in [["defend", "verb_defend"], ["escort", "verb_escort"], ["push_lane", "verb_push"], ["merge", "verb_merge"], ["goal", "verb_goal"]]:
		ov.disarm()
		CardActions.run(card, "orders", str(pair[0]))
		arm_ok = arm_ok and ov.tool == str(pair[1])
	ov.disarm()
	tour.check("card: the Defend, Escort, Push lane, Merge and Goal cells arm their click tools", arm_ok)
	ov.clear_selection()
	var none_live := true
	for pg_id: String in ["move", "hold", "stop"]:
		none_live = none_live and str(CardState.snapshot(card, "orders", pg_id)["state"]) == "locked"
	tour.check("card: with no squadron selected the Orders cells are locked ('select first')", none_live)
	position_pick(tour)
	card.set_page("build")


## Open the Position pick for the first squadron under layout `preset` ("A": the extra cell; "B" and "C": the More list) and return
## the ids of the list that is open ([] when no pick opened). The selection comes first and the list is closed after it, since a
## selection change closes an open pick and the same selection again emits nothing.
static func _open_pick(tour: Node, preset: String) -> Array:
	var view: CommandView = tour.hud.command_view
	var card := view.card
	var recs := RtsSelect.our_squads(tour.world, tour.world.human_team)
	KeyMap.set_preset("home_layout", preset)
	view.overlay.set_selection([recs[0].id], false)
	card.close_list()
	card.set_page("orders")
	card.refresh()
	if preset == "A":
		var xi := card._extra_ids.find("position")
		if xi >= 0:
			card._extra[xi].pressed.emit()
	else:
		card._more.pressed.emit()
		var pi := card._list_ids().find("position")
		if pi >= 0:
			card._entries[pi].pressed.emit()
	return card._list_ids() if card._open == "pop" else []


## The Position pick: the cell opens a pick of three entries, an entry sends the move-only stance order and closes it, Esc and a
## selection change close it, the second line says the current setting, a click with nothing selected opens nothing, the key opens
## it, and the Capitals pick of the Build page still opens (a control). The order is read from the queue's last record (no tick
## passes inside a tour step), the first squadron is put back to manoeuvre at the end and the layout preset as it was.
static func position_pick(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var card := view.card
	var ov := view.overlay
	var recs := RtsSelect.our_squads(tour.world, tour.world.human_team)
	var kept := KeyMap.preset_choice("home_layout")
	var words := ["Hold", "Manoeuvre", "Roam"]
	var p1_ok := true
	var p1_detail := ""
	for preset: String in ["B", "A", "C"]:
		var ids := _open_pick(tour, preset)
		var ok := card._open == "pop" and ids == ["pos_hold", "pos_manoeuvre", "pos_roam"]
		if ok:
			for i in 3:
				ok = ok and card._entries[i].visible and card._entries[i].text.begins_with(str(words[i]))
			ok = ok and not card._entries[3].visible
		p1_ok = p1_ok and ok
		p1_detail += "%s: open '%s' ids %s; " % [preset, card._open, str(ids)]
		card.close_list()
	tour.check("card position: the Position cell opens a pick of three entries (Hold, Manoeuvre, Roam) in layouts B, A and C", p1_ok, p1_detail)
	# P2: a click on an entry sends the move-only stance order for the selection and closes the pick.
	var ids2 := _open_pick(tour, "B")
	var p2_ok := card._open == "pop" and ids2.size() == 3
	var sent: Dictionary = {}
	if p2_ok:
		card._entries[2].pressed.emit()
		sent = tour.world.orders.last_submitted
		var settings: Dictionary = sent.get("settings", {})
		var subjects: Array = sent.get("subjects", [])
		p2_ok = str(sent.get("kind", "")) == OrderKinds.SET_STANCE and settings.keys() == ["move"] and int(settings.get("move", -1)) == 2 \
			and subjects.size() == 1 and int(subjects[0]) == recs[0].id and card._open == "" and ov.result_text.begins_with("Position roam")
		# Put the first squadron back to manoeuvre through the same pick, so the tour's squadron is not left roaming.
		var back := _open_pick(tour, "B")
		if back.size() == 3:
			card._entries[1].pressed.emit()
	tour.check("card position: a click on an entry sends the move-only stance order for the selection and closes the pick", p2_ok, "ids %s order %s result '%s'" % [str(ids2), str(sent), ov.result_text])
	# P3: Esc closes the pick and keeps the selection.
	var ids3 := _open_pick(tour, "B")
	var p3_open: bool = card._open == "pop" and ids3.size() == 3
	var esc := view.cancel_key()
	tour.check("card position: Esc closes the pick and keeps the selection", p3_open and esc and card._open == "" and ov.sel_squads.has(recs[0].id), "open %s, esc %s, now '%s', selected %s" % [str(p3_open), str(esc), card._open, str(ov.sel_squads)])
	# P4: a selection change closes the pick.
	var ids4 := _open_pick(tour, "B")
	var p4_open: bool = card._open == "pop" and ids4.size() == 3
	ov.set_selection([], false)
	tour.check("card position: a selection change closes the pick", p4_open and card._open == "", "open before %s, now '%s'" % [str(p4_open), card._open])
	# P5: the second line says the current setting, and mixed.
	if recs.size() < 2:
		tour.check("card position: the Position cell's second line says the current setting and mixed", false, "two squadrons exist: %d" % recs.size())
	else:
		var m0: int = recs[0].move_stance
		var m1: int = recs[1].move_stance
		recs[0].move_stance = 2
		ov.set_selection([recs[0].id], false)
		var one := CardState.snapshot(card, "orders", "position")
		recs[1].move_stance = 0
		ov.set_selection([recs[0].id, recs[1].id], false)
		var two := CardState.snapshot(card, "orders", "position")
		recs[0].move_stance = m0
		recs[1].move_stance = m1
		tour.check("card position: the Position cell's second line says the current setting and mixed", str(one["sub"]) == "roam" and str(one["tip"]).contains("Now roam") and str(two["sub"]) == "mixed", "one '%s', two '%s'" % [str(one["sub"]), str(two["sub"])])
	# P6: with none selected the click answers and opens no pick.
	ov.clear_selection()
	card.close_list()
	CardActions.run(card, "orders", "position")
	tour.check("card position: with none selected the click answers Select squadrons first and opens no pick", card._open == "" and ov.result_text == "Select squadrons first", "open '%s', result '%s'" % [card._open, ov.result_text])
	# P7: the Position key (layout B, Shift+V) opens the pick.
	KeyMap.set_preset("home_layout", "B")
	ov.set_selection([recs[0].id], false)
	card.close_list()
	card.set_page("orders")
	var took := view.key(_key(KEY_V, true))
	tour.check("card position: the Position key (layout B, Shift+V) opens the pick", took and card._open == "pop", "took %s, open '%s'" % [str(took), card._open])
	card.close_list()
	# P8, a control: the Build page's Capitals pick still opens and lists the two capital hulls.
	ov.clear_selection()
	card.close_list()
	card.set_page("build")
	CardActions.run(card, "build", "capitals")
	tour.check("card position: the Capitals pop-out still opens on the Build page and lists destroyer then battlecruiser", card._open == "pop" and card._list_ids() == ["destroyer", "battlecruiser"], "open '%s', ids %s" % [card._open, str(card._list_ids())])
	card.close_list()
	KeyMap.set_preset("home_layout", kept)
	card.refresh()


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
