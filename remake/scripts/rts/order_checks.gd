class_name OrderChecks
extends RefCounted
## WHAT THIS IS: the two tiers of checks an order goes through before it is carried
## out. The "at once" tier runs the moment an order is submitted, even while the game
## is paused, so a refusal the game can know at once comes back at once. The "recheck"
## tier runs again on the tick the order is carried out, because the world has moved on.
##
## HOW IT WORKS: static functions that only read the world. at_once() asks, in order:
## is the kind known, does it have anything to carry it out, is the sender allowed,
## are the target and settings valid, is a speed change allowed (not with two human
## seats), do the units and squadrons it names still exist, do the Admiral's own
## rules say no (the same *_blocker functions the map tools use for the green and red
## ring), can the team pay, and does a registered checker say no. recheck() repeats
## the cheap ones (sender, values, units, checkers); the rules and the price are
## checked by AdmiralCommand when it carries the order out, which is the real answer.
## Every refusal is one of the texts that OrderKinds maps to a code, and the
## Admiral's rules keep their own words.
##
## WHO USES IT: OrderQueue.submit() calls at_once(), OrderQueue.apply() calls
## recheck(); tests/order_check.gd drives both.

## Run the "at once" checks on record `o` for queue `q`. Returns "" if the order may
## be queued, else the refusal text. Nothing is changed.
static func at_once(w: World, q: OrderQueue, o: Dictionary) -> String:
	var kind := str(o.get("kind", ""))
	if not OrderKinds.ALL.has(kind):
		return OrderKinds.TEXT_UNKNOWN
	if not q.has_applier(kind) or str(o.get("mode", "replace")) != "replace":
		return OrderKinds.TEXT_UNBUILT
	if q.replaying and kind != OrderKinds.GAME_SPEED:
		return OrderKinds.TEXT_REPLAY
	if not OrderKinds.may_send(kind, int(o["seat"]), _squad_of(w, o)):
		return OrderKinds.TEXT_SEAT
	var v := OrderKinds.value_check(o)
	if v != "":
		return v
	if kind == OrderKinds.GAME_SPEED:
		var h := int(o["settings"]["hundredths"])
		var f: float = WorldSpeed.HUNDREDTHS.get(h, 0.0)
		if not WorldSpeed.STEPS.has(f) and not WorldSpeed.FAST_STEPS.has(f):
			return OrderKinds.TEXT_SPEED
		if q.human_seats() >= 2:
			return OrderKinds.TEXT_ONLINE
	var g := gone(w, q, o)
	if g != "":
		return g
	var b := blocker(w, o)
	if b != "":
		return b
	return _checker(q, o)


## Run the "recheck" checks on the tick an order is carried out: the sender, the
## values, the units and squadrons it names, and its registered checker. Returns "" or
## the refusal text.
static func recheck(w: World, q: OrderQueue, o: Dictionary) -> String:
	var kind := str(o.get("kind", ""))
	if not OrderKinds.may_send(kind, int(o["seat"]), _squad_of(w, o)):
		return OrderKinds.TEXT_SEAT
	var v := OrderKinds.value_check(o)
	if v != "":
		return v
	var g := gone(w, q, o)
	if g != "":
		return g
	return _checker(q, o)


## Do the units and squadrons the order names still exist? Each squadron an order names
## (its subjects) must be in World.squads, and a target unit or squadron must be there.
static func gone(w: World, q: OrderQueue, o: Dictionary) -> String:
	var subjects: Array = o["subjects"]
	for sid in subjects:
		if not w.squads.has(int(sid)):
			return OrderKinds.TEXT_GONE_SQUAD
	match str(o["target_kind"]):
		"unit":
			if q.unit_by_uid(int(o["target"])) == null:
				return OrderKinds.TEXT_GONE_UNIT
		"squadron":
			if not w.squads.has(int(o["target"])):
				return OrderKinds.TEXT_GONE_SQUAD
	return ""


## The Admiral's own rules for the order, read from the same *_blocker functions the
## map tools use, plus the price (not for a drone, a module or a research, which wait in
## the build list and pay when they start). Returns "" or the same text AdmiralCommand
## would give. The point is the order's own (already rounded for a human).
static func blocker(w: World, o: Dictionary) -> String:
	var kind := str(o["kind"])
	var team := int(o["team"])
	var cmd := w.command
	var ts := w.teams[team]
	var s: Dictionary = o["settings"]
	var target = o["target"]
	var b := ""
	match kind:
		# A drone, a module or a research waits in the build list and pays when it
		# starts, so no price is asked when it is ordered.
		OrderKinds.DRONE:
			return cmd.drone_blocker(team)
		OrderKinds.MODULE:
			var fid := str(target)
			if not Tech.FACILITIES.has(fid):
				return OrderKinds.TEXT_NO_ITEM
			return ts.facility_blocker(fid)
		OrderKinds.RESEARCH:
			var tid := str(target)
			if not Tech.TECHS.has(tid):
				return OrderKinds.TEXT_NO_ITEM
			return ts.tech_blocker(tid)
		OrderKinds.TURRET:
			b = cmd.turret_blocker(team, str(target), str(s["ttype"]))
			return b if b != "" else price(ts, float(TurretData.TURRETS[str(s["ttype"])]["cost"]))
		OrderKinds.POST:
			b = cmd.post_blocker(team, str(target))
			return b if b != "" else price(ts, float(PostData.POST["cost"]))
		OrderKinds.BAY:
			b = cmd.bay_blocker(team, Vector2(target))
			return b if b != "" else price(ts, float(Structures.REPAIR_BAY["cost"]))
		OrderKinds.WARD:
			b = cmd.ward_blocker(team, Vector2(target))
			return b if b != "" else price(ts, float(Structures.WARD["cost"]))
		OrderKinds.MOTHERSHIP_MOVE:
			b = cmd.move_blocker(team)
			if b == "" and not w.map.in_open_lane(Vector2(target)):
				b = AdmiralCommand.JUNGLE_TEXT
			return b
	return ""


## "Not enough in the team treasury (N short)" when team state `ts` cannot pay
## `cost`, else "". An unlocked Admiral (UnlockAll) can always pay.
static func price(ts: TeamState, cost: float) -> String:
	if ts.can_afford(cost):
		return ""
	return "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury))


## The squadron record the order is for (its first subject), or null.
static func _squad_of(w: World, o: Dictionary):
	var subjects: Array = o.get("subjects", [])
	if subjects.is_empty() or not OrderKinds.SQUADRON_KINDS.has(str(o.get("kind", ""))):
		return null
	return w.squads.get(int(subjects[0]))


## The registered checker's answer for the order's kind, or "" when there is none.
static func _checker(q: OrderQueue, o: Dictionary) -> String:
	var c: Callable = q.checkers.get(str(o["kind"]), Callable())
	if c.is_valid():
		return str(c.call(o))
	return ""
