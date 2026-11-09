class_name CardActions
extends RefCounted
## WHAT THIS IS: what a click or a key on a cell of the command card does: send a squadron order, queue a ship, arm
## a map tool, open a board page or change one of the player's choices. The answer of each is said on the card's result
## line (the overlay's `result_text`).
##
## HOW IT WORKS: static functions that take the card. Every order goes through the order queue as
## `world.orders.submit(Order.make(kind, team, Rules.ADMIRAL_SEAT, true, ...))`: no screen changes the match itself.
## Orders cells: Move arms the verb (the next left click sends it), Hold and Stop act at once on the selection
## (RtsSquadOrders); every other verb says "Comes with a later stage". Build cells send PRODUCE like the old Yard tab
## did: the hull, the squadron size from the view's yard choices (never more than the hull allows), repeat and the
## rally. Shift on a build key queues up to the list's depth ("to the cap"; the queue refuses what does not fit), Alt
## turns repeat on for that order. A locked hull is refused by the queue and the click then opens the research board. Base cells arm the map tools
## ("turret", "torpedo", "bay", "ward", "waypoint", "move", "rally"), open the board at the page that holds the facts
## the card has no cell for (option P), cancel the newest list item, fold the production panel or open the hangar.
##
## WHO USES IT: CommandCard (a click on a cell, a card key, the digit keys).


## Run cell `id` of page `page_id`. `shift` and `alt` are the modifier keys held (Build cells).
static func run(card: CommandCard, page_id: String, id: String, shift: bool = false, alt: bool = false) -> void:
	match page_id:
		"orders":
			_orders(card, id)
		"build":
			_build(card, id, shift, alt)
		"base":
			_base(card, id)
	card.after_action()


## An Orders cell.
static func _orders(card: CommandCard, id: String) -> void:
	var ov := card.view.overlay
	var kind := str(CardPages.cell("orders", id).get("kind", ""))
	if kind == "" or not OrderKinds.BOUGHT_KINDS.has(kind):
		ov.say(OrderKinds.TEXT_UNBUILT, false)
		return
	if ov.sel_squads.is_empty():
		ov.say("Select squadrons first", false)
		return
	match id:
		"move":
			ov.arm("verb_move")
			if ov.tool == "verb_move":
				ov.say(ov.tool_text(), true)
		"hold":
			RtsSquadOrders.hold(ov)
		"stop":
			RtsSquadOrders.stop(ov)


## A Build cell (or a build key).
static func _build(card: CommandCard, id: String, shift: bool, alt: bool) -> void:
	var view := card.view
	var ov := view.overlay
	if Ships.HULLS.has(id):
		buy(card, id, shift, alt)
		return
	match id:
		"capitals":
			card.toggle_list("pop")
		"drone":
			_drone(card)
		"size":
			view.yard["count"] = int(view.yard["count"]) % 3 + 1
			ov.say("Ships in a squadron: %d" % int(view.yard["count"]), true)
		"repeat":
			view.yard["repeat"] = not bool(view.yard["repeat"])
			ov.say("Repeat is %s" % ("on" if bool(view.yard["repeat"]) else "off"), true)


## Queue hull `hull` (see the top). A locked hull opens the research board.
static func buy(card: CommandCard, hull: String, shift: bool, alt: bool) -> void:
	var view := card.view
	var ov := view.overlay
	var ts: TeamState = view.world.teams[view.team]
	var settings := rally_settings(view)
	settings["hull"] = hull
	settings["count"] = mini(int(view.yard["count"]), RtsHulls.max_count(hull))
	settings["repeat"] = 1 if (bool(view.yard["repeat"]) or alt) else 0
	var tries := maxi(1, RtsHulls.DEPTH_SHIPS - ts.production.ship_items()) if shift else 1
	var made := 0
	var why := ""
	for i in tries:
		why = view.world.orders.submit(Order.make(OrderKinds.PRODUCE, view.team, Rules.ADMIRAL_SEAT, true, settings.duplicate()))
		if why != "":
			break
		made += 1
	if made == 0:
		ov.say(why, false)
		# A locked hull is refused by the queue ("Needs ..."); the click then goes to where it is fixed, the research board.
		if OrderKinds.reason_code(why) == "unlock":
			view.hud.panels.open_board_at("Research")
	else:
		var name := str(Ships.HULLS[hull]["label"])
		ov.say("Queued: %s%s" % [name if made == 1 else "%d %s items" % [made, name], "" if why == "" else " (then: %s)" % why], true)


## The rally settings of a PRODUCE order from the view's choice: the mothership, the push lane, or the picked spot (the
## mothership while no spot has been picked).
static func rally_settings(view: CommandView) -> Dictionary:
	var kind := str(view.yard["rally"])
	if kind == "point" and view.overlay.rally_set:
		return {"rally": "point", "rx": view.overlay.rally_spot.x, "ry": view.overlay.rally_spot.y}
	if kind == "lane":
		return {"rally": "lane"}
	return {"rally": "mothership"}


## Order one mining drone.
static func _drone(card: CommandCard) -> void:
	var view := card.view
	var why: String = view.world.orders.submit(Order.make(OrderKinds.DRONE, view.team, Rules.ADMIRAL_SEAT, true, {"node": ""}))
	view.overlay.say("Mining drone queued" if why == "" else why, why == "")


## A Base cell.
static func _base(card: CommandCard, id: String) -> void:
	var view := card.view
	var ov := view.overlay
	var panels := view.hud.panels
	match id:
		"research":
			panels.open_board_at("Research")
		"drone":
			_drone(card)
		"deputy", "deputy_preset":
			ov.say("Comes with the deputy stage", false)
		"turret", "torpedo", "waypoint", "ward", "move", "rally":
			if id == "rally":
				view.yard["rally"] = "point"
			ov.arm(id)
			if ov.tool != "":
				ov.say(ov.tool_text(), true)
		"repair":
			ov.arm("bay")
			if ov.tool != "":
				ov.say(ov.tool_text(), true)
		"cancel":
			_cancel_newest(card)
		"production":
			view.prod.set_folded(not view.prod.folded)
		"hangar":
			view.hud.router.click("hangar")
		"defenses", "turret_list":
			panels.open_board_at("Build")
		"ms_status", "doctrine":
			panels.open_board_at("Mothership")


## Cancel the newest item of the build list (the last one in it).
static func _cancel_newest(card: CommandCard) -> void:
	var view := card.view
	var items: Array = (view.world.teams[view.team] as TeamState).production.items
	if items.is_empty():
		view.overlay.say("The build list is empty", false)
		return
	var it: Dictionary = items.back()
	var why: String = view.world.orders.submit(Order.make(OrderKinds.CANCEL, view.team, Rules.ADMIRAL_SEAT, true, {}, [], "item", str(it["id"])))
	view.overlay.say("Cancelled the newest item" if why == "" else why, why == "")
