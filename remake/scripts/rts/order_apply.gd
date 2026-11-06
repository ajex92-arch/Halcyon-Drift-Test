class_name OrderApply
extends RefCounted
## WHAT THIS IS: two small jobs of the order queue that sit in a file of their own: calling the
## Admiral's rule book for one of today's order kinds, and filing the event that tells what became of
## an order.
##
## HOW IT WORKS: static functions. call_built_in() takes an order record and calls the
## AdmiralCommand function for its kind with the record's fields (a point turned back into a
## Vector2). The function
## logs the order itself, because AdmiralCommand has set `pending` to the record. file_event()
## puts "order_done" or "order_refused" into the event stream, with the sender's seat, the first
## subject's id, the place (for a point target) and the unit (for a unit target).
##
## WHO USES IT: OrderQueue (apply() and log_and_count()).

## Carry out order record `o` of a built-in kind by calling the AdmiralCommand function for it.
## Returns what the function returns ("" or the reason text), or "Comes with a later stage" for
## a kind that is not built in.
static func call_built_in(w: World, o: Dictionary) -> String:
	var cmd := w.command
	var team := int(o["team"])
	var s: Dictionary = o["settings"]
	var target = o["target"]
	match str(o["kind"]):
		OrderKinds.DRONE:
			return cmd.build_drone(team, str(s["node"]))
		OrderKinds.MODULE:
			return cmd.build_facility(team, str(target))
		OrderKinds.RESEARCH:
			return cmd.research(team, str(target))
		OrderKinds.TURRET:
			return cmd.build_turret(team, str(target), str(s["ttype"]))
		OrderKinds.POST:
			return cmd.rebuild_post(team, str(target))
		OrderKinds.BAY:
			return cmd.deploy_bay(team, Vector2(target))
		OrderKinds.WARD:
			return cmd.place_ward(team, Vector2(target))
		OrderKinds.WAYPOINT:
			return cmd.set_waypoint(team, Vector2(target), int(s["siege"]) == 1, bool(o["human"]))
		OrderKinds.MOTHERSHIP_MOVE:
			return cmd.move_mothership(team, Vector2(target))
		OrderKinds.SIEGE:
			return cmd.set_siege(team, str(target) if str(o["target_kind"]) == "lane" else "", str(s["phase"]))
	return OrderKinds.TEXT_UNBUILT


## File "order_done" (code "ok") or "order_refused" (any other code) for record `o` in the event
## stream. `at` says where a refusal happened: "submit" or "apply".
static func file_event(w: World, o: Dictionary, code: String, at: String) -> void:
	if w.events_rts == null:
		return
	var subjects: Array = o["subjects"]
	var data := {"kind": str(o["kind"]), "id": int(o["id"]), "seat": int(o["seat"]), "squad": int(subjects[0]) if not subjects.is_empty() else 0}
	var pos: Variant = null
	var uid := 0
	var target: Variant = o["target"]
	match str(o["target_kind"]):
		"point":
			if target is Vector2 or target is Vector2i:
				pos = Order.point(Vector2(target))
		"unit":
			if typeof(target) == TYPE_INT:
				uid = int(target)
	if code == "ok":
		w.events_rts.push({"kind": "order_done", "team": int(o["team"]), "pos": pos, "uid": uid, "data": data})
		return
	data["reason"] = code
	data["at"] = at
	w.events_rts.push({"kind": "order_refused", "team": int(o["team"]), "pos": pos, "uid": uid, "data": data})
