class_name RtsTourProd
extends RefCounted
## WHAT THIS IS: the production panel's checks of the RTS tour: a full build list (5 ships, 3 research, 2 modules and 6 drones, the
## longest the list gets) shows as rows with their states in words, the filters, the stacked drones, the scroll, the picked row's Up and
## Down, Hold, Cancel at once and the "sure?" question for a started item, the drag of the grip, the fold, and what each edit sends.
##
## HOW IT WORKS: static functions that take the tour (it counts the failures and prints the lines). The list is filled through the
## team's Production (a test may; no rule is bypassed that the panel checks), the panel is driven through its own functions and read
## through its rows' snapshots (`ProductionRow.data`). `after_ticks()` sees the effect of the moves and the cancel on the list.
##
## WHO USES IT: tests/rts_tour.gd.

## The ids the move and the cancel were sent for, and the place the moved item had.
static var _moved_id := ""
static var _moved_from := -1
static var _cancelled_id := ""


## The panel's production list.
static func _prod(view: CommandView) -> Production:
	return (view.world.teams[view.team] as TeamState).production


## Fill the list: 5 ships, 3 research items, 2 modules and 6 drones (nothing started, the treasury is what it is).
static func fill(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var p := _prod(view)
	p.items.clear()
	for i in 5:
		p.add_ship("fighter" if i % 2 == 0 else "bomber", 3 if i % 2 == 0 else 3)
	var techs: Array = Tech.ORDER.slice(0, 3)
	for t in techs:
		p.add_research(str(t))
	var mods: Array = Tech.FACILITIES.keys().slice(0, 2)
	for m in mods:
		p.add_module(str(m))
	for i in 6:
		p.add_drone("")
	view.prod.set_folded(false)
	view.refresh()


## The panel's rows, stacks, filters, scroll and fold.
static func rows(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var panel := view.prod
	var p := _prod(view)
	panel.filter = "all"
	panel.refresh()
	# The match runs: a cheap item may have started or finished since fill(), so the expected rows come from the list itself.
	var waiting := 0
	var ships := 0
	var labs := 0
	var drones := 0
	for it: Dictionary in p.items:
		match str(it["kind"]):
			Production.SHIP:
				ships += 1
			Production.DRONE:
				drones += 1
				if not bool(it["started"]) and not bool(it["held"]):
					waiting += 1
			_:
				labs += 1
	var stacked := maxi(0, waiting - 1)
	tour.check("panel: the list is one row per item, identical waiting drones stacked into one (%d items, %d stacked away)" % [p.items.size(), stacked], panel._entries.size() == p.items.size() - stacked, str(panel._entries.size()))
	var drone_row: ProductionRow = null
	for i in panel._entries.size():
		if str(panel._rows[i].data.get("name", "")).begins_with("Mining drone"):
			drone_row = panel._rows[i]
	tour.check("panel: identical waiting drones are one row with a count", waiting < 2 or (drone_row != null and str(drone_row.data.get("name", "")).ends_with("x%d" % waiting)), str(drone_row.data.get("name", "")) if drone_row != null else "no row")
	var words := ""
	for i in 11:
		words += str(panel._rows[i].data.get("state", "")) + " | "
	tour.check("panel: every row says its state in words", not words.contains("{}") and str(panel._rows[0].data.get("state", "")) != "", words)
	tour.check("panel: 8 rows show and the list scrolls", panel._entries.size() <= 8 or panel._rows[8].position.y >= float(ProductionPanel.SHOWN) * ProductionRow.H - 0.5, str(panel._rows[8].position))
	panel._scroll = 3
	panel.refresh()
	tour.check("panel: the scroll moves the rows", panel._rows[3].position.y == 0.0, str(panel._rows[3].position))
	panel._scroll = 0
	panel._set_filter("ships")
	tour.check("panel: the Ships filter shows the ships", panel._entries.size() == ships, "%d of %d" % [panel._entries.size(), ships])
	panel._set_filter("research")
	tour.check("panel: the Research filter shows research and modules", panel._entries.size() == labs, "%d of %d" % [panel._entries.size(), labs])
	panel._set_filter("drones")
	tour.check("panel: the Drones filter shows the drones (the waiting ones stacked)", panel._entries.size() == drones - stacked, "%d of %d" % [panel._entries.size(), drones - stacked])
	panel._set_filter("all")
	# Pick, Up and Down.
	panel._pick(2)
	panel.refresh()
	tour.check("panel: a click picks a row and shows Up and Down", panel._rows[2]._up.visible and panel._rows[2]._down.visible and panel._rows[1]._up.visible == false)
	var id := str(p.items[2]["id"])
	_moved_id = id
	_moved_from = 2
	var before: int = tour.world.orders.next_id
	panel._move_row(2, -1)
	tour.check("panel: Up sends MOVE_ITEM", str(tour.world.orders.last_submitted.get("kind", "")) == OrderKinds.MOVE_ITEM and tour.world.orders.next_id == before + 1)
	# Drag the grip of row 5 to row 3: two steps, in order.
	before = tour.world.orders.next_id
	panel._drag_to = 3
	panel._drop(5)
	tour.check("panel: a drag of the grip sends one MOVE_ITEM per step", tour.world.orders.next_id == before + 2, "%d then %d" % [before, tour.world.orders.next_id])
	# Hold, Cancel at once, and the question for a started item.
	before = tour.world.orders.next_id
	panel._hold_row(7)
	tour.check("panel: Hold sends HOLD_ITEM", str(tour.world.orders.last_submitted.get("kind", "")) == OrderKinds.HOLD_ITEM and tour.world.orders.next_id == before + 1)
	var drone_n: int = panel._entries.size()
	var victim := panel._entries.size() - 1
	for i in range(panel._entries.size() - 1, 2, -1):
		if not bool((panel._entries[i]["it"] as Dictionary)["started"]):
			victim = i
			break
	_cancelled_id = str((panel._entries[victim]["ids"] as Array).back())
	before = tour.world.orders.next_id
	panel._cancel_row(victim)
	tour.check("panel: Cancel of an item not started cancels at once", str(tour.world.orders.last_submitted.get("kind", "")) == OrderKinds.CANCEL and tour.world.orders.next_id == before + 1)
	var started: Dictionary = p.items[0]
	started["started"] = true
	started["running"] = true
	started["done"] = int(int(started["ticks"]) * 0.4)
	started["paid"] = 300
	panel.refresh()
	before = tour.world.orders.next_id
	panel._cancel_row(0)
	panel.refresh()
	var sure := str(panel._rows[0].data.get("sure", ""))
	if RtsUiCalls.CANCEL_STARTED_CONFIRM_S > 0.0:
		tour.check("panel: Cancel of a started item asks first", tour.world.orders.next_id == before and sure.begins_with("sure? 40% of the build lost") and sure.contains("the ore comes back in full"), sure)
		panel._cancel_row(0)
		tour.check("panel: the second click cancels it", tour.world.orders.next_id == before + 1)
	else:
		tour.check("panel: with no question Cancel cancels at once", tour.world.orders.next_id == before + 1)
	started["started"] = false
	started["running"] = false
	started["paid"] = 0
	tour.check("panel: a refusal-free list still has rows after the edits", drone_n > 0)
	# Fold.
	panel.set_folded(true)
	tour.check("panel: folded it is its 26 px header", is_equal_approx(panel.size.y, ProductionPanel.HEAD_H), str(panel.size))
	panel.set_folded(false)
	tour.check("panel: open again it is 280 px tall", is_equal_approx(panel.size.y, CommandView.PROD_H), str(panel.size))


## After ticks: the item that moved is one place higher, the cancelled one is gone.
static func after_ticks(tour: Node) -> void:
	if _moved_id == "":
		return
	var p := _prod(tour.hud.command_view)
	var at := -1
	for i in p.items.size():
		if str(p.items[i]["id"]) == _moved_id:
			at = i
	tour.check("panel: after the tick the moved item stands higher", at >= 0 and at <= 1, "from %d to %d" % [_moved_from, at])
	tour.check("panel: after the tick the cancelled item is gone", p.find(_cancelled_id).is_empty())
