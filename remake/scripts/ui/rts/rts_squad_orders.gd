class_name RtsSquadOrders
extends RefCounted
## WHAT THIS IS: the orders the Admiral's screens send to the selected squadrons (Move, Hold, Stop, the stance, formation
## and Position settings, and Attack through the smart right-click), as functions on the map layer (CommandOverlay), which keeps the selection and the answer line.
##
## HOW IT WORKS: only static functions that take the overlay. Every order is
## `world.orders.submit(Order.make(kind, team, Rules.ADMIRAL_SEAT, true, {}, subjects, target_kind, target))` with
## human = true, so a replay refuses it and the match recorder logs it. Nothing here changes the match itself: the
## order queue does, on the next tick (the first tick after a pause ends). The answer of each click is said on the
## overlay's result line: the refusal text the queue gives at once, or "Move: 3 squadrons", with "; the mothership
## stays: Base, Move" when the mothership is selected too (a squadron order never goes to it). The smart right-click
## is Move on open ground and Attack on an enemy unit the team sees (the enemy mothership too), Escort on any friendly ship and
## Defend on a structure of ours; our mothership says "Retreat: later stage" and sends nothing (that order comes with a later stage).
##
## WHO USES IT: CommandOverlay (the armed Move verb, the right click), CommandCard (Hold, Stop, Stance, Formation and the
## Position pick), tests/rts_tour.gd.

## "3 squadrons" / "1 squadron".
static func squads_word(n: int) -> String:
	return "%d squadron%s" % [n, "" if n == 1 else "s"]


## World units per screen pixel now (1 with no camera, as in a headless check).
static func view_px(world: World) -> float:
	if world.camera == null:
		return 1.0
	return 1.0 / maxf(0.0001, world.camera.zoom.x)


## The cursor word and the banner of each armed squadron verb (the tools of the card's Orders cells; Goal picks its order by
## what is clicked).
const VERB_LABELS := {"verb_move": "Move", "verb_defend": "Defend", "verb_escort": "Escort", "verb_push": "Push lane", "verb_merge": "Merge", "verb_goal": "Goal"}
## The refusal text of Goal on an enemy ship: Harass comes with a later stage.
const TEXT_HARASS_LATER := "Harass: comes with a later stage"


## The friendly unit under world point `p` (nearest, within the pick radius): a ship of ours (a pilot's or a bought one), or
## with `ships_only` false also a structure of ours or our mothership. Null for none.
static func ours_at(ov: CommandOverlay, p: Vector2, ships_only: bool) -> Unit:
	var world := ov.world
	var team := ov.team
	var px := view_px(world)
	var r := RtsSelect.PICK_PX * px
	var best: Unit = null
	var best_d := INF
	var seen: Array = []
	for u in world.unit_hash.query(p, r + 200.0, seen):
		if u == null or not is_instance_valid(u) or not (u as Unit).alive:
			continue
		var unit := u as Unit
		if unit.team != team:
			continue
		var is_ship := unit is Ship
		if not is_ship and (ships_only or not [Unit.K_TURRET, Unit.K_BAY, Unit.K_WARD, Unit.K_POST, Unit.K_EXTRACTOR].has(unit.kind)):
			continue
		var d := maxf(0.0, unit.global_position.distance_to(p) - unit.radius)
		if d <= r and d < best_d:
			best_d = d
			best = unit
	return best


## The armed verb `tool` at world point `p`: Move sends Move, the others send their goal order (see the functions below). Returns
## the refusal text, "" for a sent order.
static func verb_at(ov: CommandOverlay, tool: String, p: Vector2) -> String:
	match tool:
		"verb_move":
			return send(ov, OrderKinds.MOVE, "point", Order.point(p), ov.sel_squads, "Move")
		"verb_defend":
			return defend_at(ov, p)
		"verb_escort":
			return escort_at(ov, p)
		"verb_push":
			return push_at(ov, p)
		"verb_merge":
			return merge_at(ov, p)
		"verb_goal":
			return goal_at(ov, p)
	return ""


## Defend: one of our units or structures under the click, else the point snapped to the nearest named thing.
static func defend_at(ov: CommandOverlay, p: Vector2) -> String:
	var u := ours_at(ov, p, false)
	if u != null:
		return send(ov, OrderKinds.DEFEND, "unit", u.uid, ov.sel_squads, "Defend")
	return send(ov, OrderKinds.DEFEND, "point", GoalPoints.snap(ov.world, p), ov.sel_squads, "Defend")


## Escort: a friendly ship under the click (a big one too).
static func escort_at(ov: CommandOverlay, p: Vector2) -> String:
	var u := ours_at(ov, p, true)
	if u == null:
		ov.say("Click one of your ships to escort", false)
		return "No ship"
	return send(ov, OrderKinds.ESCORT, "unit", u.uid, ov.sel_squads, "Escort")


## Push lane: the lane band under the click.
static func push_at(ov: CommandOverlay, p: Vector2) -> String:
	var lane := GoalPoints.lane_at(ov.world, p)
	if lane == "":
		ov.say("Click inside a lane to push it", false)
		return "No lane"
	return send(ov, OrderKinds.PUSH_LANE, "lane", lane, ov.sel_squads, "Push lane")


## Merge: the selected squadrons (but the host) give their ships to the squadron under the click.
static func merge_at(ov: CommandOverlay, p: Vector2) -> String:
	var px := view_px(ov.world)
	var host := RtsSelect.squad_at(ov.world, ov.team, p, px)
	if host < 0:
		ov.say("Click the squadron to merge into", false)
		return "No squadron"
	var ids: Array[int] = []
	for id in ov.sel_squads:
		if id != host:
			ids.append(id)
	if ids.is_empty():
		ov.say("Select other squadrons to merge into it", false)
		return "No donors"
	return send(ov, OrderKinds.MERGE, "squadron", host, ids, "Merge")


## Goal: an enemy ship is refused (Harass comes with a later stage), a friendly ship is Escort, one of our structures is Defend
## on it, a lane band is Push lane, and anything else is Defend on the point snapped to the nearest named thing.
static func goal_at(ov: CommandOverlay, p: Vector2) -> String:
	if enemy_at(ov, p) != null:
		ov.say(TEXT_HARASS_LATER, false)
		return TEXT_HARASS_LATER
	var ship := ours_at(ov, p, true)
	if ship != null:
		return send(ov, OrderKinds.ESCORT, "unit", ship.uid, ov.sel_squads, "Escort")
	var structure := ours_at(ov, p, false)
	if structure != null:
		return send(ov, OrderKinds.DEFEND, "unit", structure.uid, ov.sel_squads, "Defend")
	var lane := GoalPoints.lane_at(ov.world, p)
	if lane != "":
		return send(ov, OrderKinds.PUSH_LANE, "lane", lane, ov.sel_squads, "Push lane")
	return send(ov, OrderKinds.DEFEND, "point", GoalPoints.snap(ov.world, p), ov.sel_squads, "Defend")


## One order with settings for every selected squadron (the stance and formation cells). Says `text` on success.
static func send_set(ov: CommandOverlay, kind: String, settings: Dictionary, text: String) -> String:
	if ov.sel_squads.is_empty():
		ov.say("Select squadrons first", false)
		return "Select squadrons first"
	var why := ov.world.orders.submit(Order.make(kind, ov.team, Rules.ADMIRAL_SEAT, true, settings, ov.sel_squads.duplicate(), "none", 0))
	if why != "":
		ov.say(why, false)
		return why
	ov.say(_done_text(ov, text, ov.sel_squads.size()), true)
	return ""


## The Stance cell: cycle the fire stance of the selected squadrons (at will, return fire, hold fire) from the first one's
## stance. The move stance is not touched (the order carries only "fire").
static func cycle_stance(ov: CommandOverlay) -> String:
	var recs := ov.selected_records()
	if recs.is_empty():
		ov.say("Select squadrons first", false)
		return "Select squadrons first"
	var next := Formations.next_fire((recs[0] as Squad).fire_stance)
	return send_set(ov, OrderKinds.SET_STANCE, {"fire": next}, str(Formations.FIRE_TOASTS[clampi(next, 0, 2)]))


## The Position pick: set the chase setting (the move stance: 0 hold, 1 manoeuvre, 2 roam) of every selected squadron to
## `move`. The order names only "move", so the fire stance, the formation and any goal are left alone; a mixed selection takes
## the one pick. With none selected it says "Select squadrons first" and sends nothing. Returns the refusal text, "" for success.
static func set_position(ov: CommandOverlay, move: int) -> String:
	var m := clampi(move, 0, 2)
	return send_set(ov, OrderKinds.SET_STANCE, {"move": m}, "Position %s" % str(Formations.MOVE_NAMES[m]).to_lower())


## The Formation cell: cycle the formation of the selected squadrons from the first one's.
static func cycle_formation(ov: CommandOverlay) -> String:
	var recs := ov.selected_records()
	if recs.is_empty():
		ov.say("Select squadrons first", false)
		return "Select squadrons first"
	var next := Formations.next_formation((recs[0] as Squad).formation)
	return send_set(ov, OrderKinds.SET_FORMATION, {"formation": next}, "%s formation" % Formations.formation_name(next))


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
	var px := view_px(world)
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
## Scum), "pilot" (any ship of ours), "structure" (ours) or "ground". Enemy beats pilot beats structure.
static func target_kind_at(ov: CommandOverlay, p: Vector2) -> String:
	var world := ov.world
	var team := ov.team
	var px := view_px(world)
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
		if unit is Ship:
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
	if what == "pilot":
		return escort_at(ov, p)
	if what == "structure":
		return defend_at(ov, p)
	ov.say("%s: later stage" % str(CommandOverlay.LATER_VERBS[what]), false)
	return ""
