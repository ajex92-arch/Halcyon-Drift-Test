class_name CommandOrdersUi
extends RefCounted
## WHAT THIS IS: the command card's home for the orders that feature modules add (Sensor Sweep, Supply Drop, Barrage, Bounty,
## Fortify; see CommandOrders): one More entry on the Orders page for each. It shows nothing in today's game, because then no
## order is registered. (It was a part of the Admiral board's Fleet tab; the tab went with the command view.)
##
## HOW IT WORKS: only static functions. entries() lists the orders as {id, text, tip, off}: the name with its price and, while
## it recharges, the seconds left, and `off` while it cannot go (recharging or too dear). press() does what the click does: an order
## that needs a spot arms the map tool of the same name (the Admiral then clicks the map; the overlay's blocker says why a spot is
## refused), one that needs none is given at once. Every order goes through CommandOrders.run(), the same call the AI admiral uses.
##
## WHO USES IT: CommandCard (the Orders page's More pop-out).


## The entries for team `team`: [{id, text, tip, off}] in the order the orders were registered.
static func entries(world: World, team: int) -> Array:
	var out: Array = []
	var orders: Dictionary = world.command.orders
	for id in orders:
		var d: Dictionary = orders[id]
		var wait := CommandOrders.ready_in(world, str(id), team)
		var cost := CommandOrders.cost_of(d, team)
		var price := ("%d" % int(cost)) if cost > 0.0 else "free"
		var state := ("  (%ds)" % int(ceil(wait))) if wait > 0.0 else ""
		out.append({"id": str(id), "text": "%s  %s%s" % [d["label"], price, state], "tip": str(d.get("tip", d["hint"])),
			"off": wait > 0.0 or not (world.teams[team] as TeamState).can_afford(cost)})
	return out


## The Admiral clicked order `id`: arm its map tool, or give it straight away when it needs no spot. Does nothing while the human
## may not give orders.
static func press(view: CommandView, id: String) -> void:
	var ov := view.overlay
	if not ov.can_command():
		return
	if CommandOrders.needs_point(view.world, id):
		ov.arm(id)
		if ov.tool != "":
			ov.say(ov.tool_text(), true)
	else:
		var why: String = CommandOrders.run(view.world, id, view.team, Vector2.ZERO)
		ov.say("Ordered" if why == "" else why, why == "")