class_name FieldOrders
extends RefCounted
## WHAT THIS IS: the orders the Admiral gives while flying (field mode and mode 3) from the fleet wheel (OrderWheel):
## Move here, Hold here, Stop, Defend here (the snapped point under the mouse), Escort me (the Admiral's own ship) and Push this lane
## (the lane under the mouse) to the chosen squadrons, and the hulls of the build strip. The wheel's other slices (Attack-move,
## Retreat) are orders that come with later stages: they send nothing and answer with the "later stage" text.
##
## HOW IT WORKS: only static functions that take the World, so a script (the order replay test) can use them with no
## HUD. Every order is `world.orders.submit(Order.make(kind, team, Rules.ADMIRAL_SEAT, true, ...))` with human = true,
## the same record RtsSquadOrders and CardActions send, so the order queue logs it and a replay refuses it. ids_for()
## says who gets an order: the squadrons the map layer has selected, else every squadron of the team. give() sends one
## order of the wheel (Move and Stop one order for all the squadrons, Hold one per squadron at its centre) and returns
## the refusal text, "" when it went in. queue_hull() queues a ship of the build strip by the same rule as the command
## card's build keys, except that a locked hull only answers with the queue's refusal (it never opens the research board).
##
## WHO USES IT: Hud (field_command(), field_tap()), OrderWheel (the strip's keys and clicks), tests/field_wheel_check.gd
## and tests/order_replay.gd.

## The text for an order that needs squadrons when there are none to give it to.
const NO_SQUADS := "Select squadrons first"
## What the text of a queued build starts with.
const QUEUED := "Queued: "
## The wheel's live orders: gesture name -> the word the pop-up uses ("Move: 2 squadrons").
const LIVE := {"move": "Move", "hold": "Hold", "stop": "Stop", "defend": "Defend", "escort": "Escort", "push": "Push lane"}


## The ids of the squadrons an order from the wheel goes to: the selected ones that still have a ship, else every
## squadron of the team (an empty list when it has none).
static func ids_for(overlay: CommandOverlay, world: World) -> Array[int]:
	var ids: Array[int] = []
	if overlay != null and not overlay.sel_squads.is_empty():
		ids = RtsSelect.live_ids(world, world.human_team, overlay.sel_squads)
	if ids.is_empty():
		for rec: Squad in RtsSelect.our_squads(world, world.human_team):
			ids.append(rec.id)
	return ids


## Give order `name` ("move", "hold", "stop", "defend", "escort" or "push") to squadrons `ids`, `aim` being the world point Move goes to. Returns the
## refusal text, "" when the order went in; any other name is an order of a later stage (OrderKinds.TEXT_UNBUILT).
static func give(world: World, name: String, ids: Array[int], aim: Vector2) -> String:
	if not LIVE.has(name):
		return OrderKinds.TEXT_UNBUILT
	if ids.is_empty():
		return NO_SQUADS
	match name:
		"move":
			return _send(world, OrderKinds.MOVE, "point", Order.point(aim), ids)
		"stop":
			return _send(world, OrderKinds.STOP, "none", 0, ids)
		"defend":
			return _send(world, OrderKinds.DEFEND, "point", GoalPoints.snap(world, aim), ids)
		"escort":
			var me: Ship = world.human.ship if world.human != null else null
			if me == null or not is_instance_valid(me) or not me.alive:
				return OrderKinds.TEXT_GONE_UNIT
			return _send(world, OrderKinds.ESCORT, "unit", me.uid, ids)
		"push":
			var lane := GoalPoints.lane_at(world, aim)
			if lane == "":
				return "%s: no lane there" % OrderKinds.TEXT_VALUE
			return _send(world, OrderKinds.PUSH_LANE, "lane", lane, ids)
	# Hold: one order for each squadron, at its own centre.
	var made := 0
	for id: int in ids:
		var rec: Squad = world.squads.get(id)
		if rec == null:
			continue
		var at := Order.point(RtsSelect.centre_of(world, rec))
		var why := world.orders.submit(Order.make(OrderKinds.HOLD, world.human_team, Rules.ADMIRAL_SEAT, true, {}, [id], "point", at))
		if why != "":
			return why
		made += 1
	return "" if made > 0 else NO_SQUADS


## Queue hull `hull` from the build strip, by the rule of the command card's build keys (CardActions.buy): the squadron
## size from the view's yard choices (never more than the hull allows), repeat from the yard or `alt`, the rally the
## yard says, and with `shift` as many items as still fit in the build list ("to the cap"; the queue refuses what does
## not). Returns the text for a pop-up: "Queued: Fighter" (it begins with QUEUED) when at least one went in, else the
## queue's refusal (a locked hull: "Needs ...", where the card's click would also open the research board; the strip
## never does).
static func queue_hull(world: World, view: CommandView, hull: String, shift: bool, alt: bool) -> String:
	var ts: TeamState = world.teams[view.team]
	var settings := CardActions.rally_settings(view)
	settings["hull"] = hull
	settings["count"] = mini(int(view.yard["count"]), RtsHulls.max_count(hull))
	settings["repeat"] = 1 if (bool(view.yard["repeat"]) or alt) else 0
	var tries := maxi(1, RtsHulls.DEPTH_SHIPS - ts.production.ship_items()) if shift else 1
	var made := 0
	var why := ""
	for i in tries:
		why = world.orders.submit(Order.make(OrderKinds.PRODUCE, view.team, Rules.ADMIRAL_SEAT, true, settings.duplicate()))
		if why != "":
			break
		made += 1
	if made == 0:
		return why
	var name := str(Ships.HULLS[hull]["label"])
	return "%s%s%s" % [QUEUED, name if made == 1 else "%d %s items" % [made, name], "" if why == "" else " (then: %s)" % why]


## Did the text queue_hull() returned say something was queued (not a refusal)?
static func was_queued(text: String) -> bool:
	return text.begins_with(QUEUED)


## One order of `kind` for all of `ids` (the refusal text, or "").
static func _send(world: World, kind: String, target_kind: String, target: Variant, ids: Array[int]) -> String:
	return world.orders.submit(Order.make(kind, world.human_team, Rules.ADMIRAL_SEAT, true, {}, ids.duplicate(), target_kind, target))
