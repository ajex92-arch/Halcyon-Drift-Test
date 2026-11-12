class_name RtsSquadOrders
extends RefCounted
## WHAT THIS IS: the orders the Admiral's screens send to the selected squadrons (Move, Hold, Stop, and Attack through the
## smart right-click), as functions on the map layer (CommandOverlay), which keeps the selection and the answer line.
##
## HOW IT WORKS: only static functions that take the overlay. Every order is
## `world.orders.submit(Order.make(kind, team, Rules.ADMIRAL_SEAT, true, {}, subjects, target_kind, target))` with
## human = true, so a replay refuses it and the match recorder logs it. Nothing here changes the match itself: the
## order queue does, on the next tick (the first tick after a pause ends). The answer of each click is said on the
## overlay's result line: the refusal text the queue gives at once, or "Move: 3 squadrons", with "; the mothership
## stays: Base, Move" when the mothership is selected too (a squadron order never goes to it). The smart right-click
## is Move on open ground and Attack on an enemy unit the team sees (the enemy mothership too); our pilot, a structure
## of ours or our mothership says "<Verb>: later stage" and sends nothing (those orders come with a later stage).
##
## WHO USES IT: CommandOverlay (the armed Move verb, the right click), CommandCard (Hold, Stop), tests/rts_tour.gd.

## "3 squadrons" / "1 squadron".
static func squads_word(n: int) -> String:
	return "%d squadron%s" % [n, "" if n == 1 else "s"]


## Send one order of `kind` to squadrons `ids` (every one of them) through the order queue and say the answer on
## the overlay's result line (see the top). Returns the refusal text, "" for success.
static func send(ov: CommandOverlay, kind: String, target_kind: String, target: Variant, ids: Array[int], label: String) -> String:
	if ids.is_empty():
		ov.say("Select squadrons first", false)
		return "Select squadrons first"
	var why := ov.world.orders.submit(Order.make(kind, ov.team, Rules.ADMIRAL_SEAT, true, {}, ids.duplicate(), target_kind, target))
	if why != "":
		ov.say(why, false)
		return why
	ov.say(_done_text(ov, label, ids.size()), true)
	return ""


## The success line: "<label>: 3 squadrons", with the mothership's note when it is selected too.
static func _done_text(ov: CommandOverlay, label: String, n: int) -> String:
	var text := "%s: %s" % [label, squads_word(n)]
	if ov.sel_base:
		text += "; the mothership stays: Base, Move"
	return text


## The Hold verb: every selected squadron holds where it is now (one Hold order each, at its centre).
static func hold(ov: CommandOverlay) -> String:
	var recs := ov.selected_records()
	if recs.is_empty():
		ov.say("Select squadrons first", false)
		return "Select squadrons first"
	for rec in recs:
		var at := Order.point(RtsSelect.centre_of(ov.world, rec))
		var why := ov.world.orders.submit(Order.make(OrderKinds.HOLD, ov.team, Rules.ADMIRAL_SEAT, true, {}, [rec.id], "point", at))
		if why != "":
			ov.say(why, false)
			return why
	ov.say(_done_text(ov, "Hold", recs.size()), true)
	return ""


## The Stop verb: every selected squadron stops where it is (one Stop order for all of them).
static func stop(ov: CommandOverlay) -> String:
	return send(ov, OrderKinds.STOP, "none", 0, ov.sel_squads, "Stop")


## The enemy unit under world point `p` for a right click, or null: the enemy mothership when its hull is within the
## pick radius, else the nearest enemy unit (the Scum too) the team sees. A unit the team does not see now is never
## picked.
static func enemy_at(ov: CommandOverlay, p: Vector2) -> Unit:
	var world := ov.world
	var team := ov.team
	var px := 1.0 / maxf(0.0001, world.camera.zoom.x)
	var r := RtsSelect.PICK_PX * px
	var enemy_ms := world.mothership(Rules.enemy_of(team))
	if enemy_ms != null and is_instance_valid(enemy_ms) and enemy_ms.alive and enemy_ms.hull_dist(p) <= r and enemy_ms.visible_to(team):
		return enemy_ms
	var best: Unit = null
	var best_d := INF
	var seen: Array = []
	for u in world.unit_hash.query(p, r + 200.0, seen):
		if u == null or not is_instance_valid(u) or not (u as Unit).alive:
			continue
		var unit := u as Unit
		var d := maxf(0.0, unit.global_position.distance_to(p) - unit.radius)
		if d > r or unit.team == team or not unit.visible_to(team) or unit.kind == Unit.K_MOTHERSHIP:
			continue
		if d < best_d:
			best_d = d
			best = unit
	return best


## What world point `p` is, for a right click: "base" (our mothership), "enemy" (anything of theirs we see, or the
## Scum), "pilot" (our own pilot's ship), "structure" (ours) or "ground". Enemy beats pilot beats structure.
static func target_kind_at(ov: CommandOverlay, p: Vector2) -> String:
	var world := ov.world
	var team := ov.team
	var px := 1.0 / maxf(0.0001, world.camera.zoom.x)
	var r := RtsSelect.PICK_PX * px
	if RtsSelect.base_at(world, team, p, px):
		return "base"
	if enemy_at(ov, p) != null:
		return "enemy"
	var pilot := false
	var structure := false
	var seen: Array = []
	for u in world.unit_hash.query(p, r + 200.0, seen):
		if u == null or not is_instance_valid(u) or not (u as Unit).alive:
			continue
		var unit := u as Unit
		if maxf(0.0, unit.global_position.distance_to(p) - unit.radius) > r:
			continue
		if unit.team != team:
			continue
		if unit is Ship and (unit as Ship).profile != null and not (unit as Ship).profile.is_crew:
			pilot = true
		elif [Unit.K_TURRET, Unit.K_BAY, Unit.K_WARD, Unit.K_POST, Unit.K_EXTRACTOR].has(unit.kind):
			structure = true
	if pilot:
		return "pilot"
	if structure:
		return "structure"
	return "ground"


## The smart right-click at world point `p` with squadrons selected: open ground sends Move to the selection, an enemy
## sends Attack on it (the enemy mothership too); our pilot, a structure of ours or our mothership say "<Verb>: later
## stage" and send nothing. Returns the refusal text ("" for a sent order or a later-stage verb).
static func smart_order_at(ov: CommandOverlay, p: Vector2) -> String:
	if ov.sel_squads.is_empty():
		return ""
	var what := target_kind_at(ov, p)
	if what == "ground":
		return send(ov, OrderKinds.MOVE, "point", Order.point(p), ov.sel_squads, "Move")
	if what == "enemy":
		return send(ov, OrderKinds.ATTACK, "unit", enemy_at(ov, p).uid, ov.sel_squads, "Attack")
	ov.say("%s: later stage" % str(CommandOverlay.LATER_VERBS[what]), false)
	return ""
