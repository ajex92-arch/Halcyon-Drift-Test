class_name SquadOrders
extends RefCounted
## WHAT THIS IS: the squad orders of a pilot's wing: the rules that say whether an order is allowed
## (check), the carrying out of it (handle), the choice of what the mouse is pointing at
## (pick_under_reticle), and one function for each thing a pilot can do with the wing (the
## gestures: tap, "Form on me", "Cover me", "Attack my target", "Guard that ship", "Hold here",
## "Regroup", a formation, a fire setting) that builds the order record for the order queue.
##
## HOW IT WORKS: register() hands check() and handle() to the world's OrderQueue for the seven
## squad kinds (ESCORT, ATTACK, HOLD, MOVE, GUARD, SET_FORMATION, SET_STANCE). check() answers "" or
## a refusal text and runs when the order is submitted and again when it is carried out. handle()
## runs at the start of the next tick: it drops a repeat of the wing's last order (the same kind and
## target within 30 ticks), then writes the order, the formation or the stances into every record of
## the wing. The wing's brains read the records. A gesture function never changes the game: it only
## returns the order record (Order.make) the pilot's screen submits, or the text of why it can't.
## The words on the screen ("Cover me", "Wing: attacking Vhorr-2") come from the label functions
## here, so no screen keeps a second copy.
##
## WHO USES IT: Squads.register() (the registration), the wing wheel, the tap and the preset B
## keys through Hud.wing_command() (the gestures), the HUD's order listener (confirm_text),
## tests/wing_probe.gd and tests/squad_engine_check.gd.

# The refusal texts of the wing orders (OrderKinds maps each to its code).
## The pilot has no wingman left.
const TEXT_NO_WING := "You have no wingmen"
## The target is not visible to the pilot's team any more (or never was).
const TEXT_NOT_SEEN := "Target not in sight"
## The mouse is not on an enemy.
const TEXT_NO_TARGET := "No target under the reticle"
## The mouse is not on one of our big ships.
const TEXT_NO_BIG := "No big ship under the reticle"
## The target or the ward is farther from the leader than the wing may go.
const TEXT_FAR := "Too far for the wing"

## An enemy this close (world units) to the reticle can be picked.
const PICK_ENEMY_RADIUS := 300.0
## One of our big ships this close to the reticle can be picked.
const PICK_BIG_RADIUS := 600.0

## The shown name of each ESCORT role (the data word "defend" shows as "Cover me").
const ROLE_LABELS := {"follow": "Form on me", "defend": "Cover me"}


# --- registering ------------------------------------------------------------------------------

## Hand the checker and the handler of the seven squad kinds to world `w`'s order queue.
static func register(w: World) -> void:
	for kind: String in OrderKinds.SQUADRON_KINDS:
		w.orders.checkers[kind] = func(o: Dictionary) -> String: return check(w, o)
		w.orders.handlers[kind] = func(o: Dictionary) -> String: return handle(w, o)


# --- the checks ---------------------------------------------------------------------------------

## The lead record of the wing order `o` is for: its first subject, or the lead of the wing that
## record belongs to (a sibling's own id is accepted). Null when the order names no wing record.
static func wing_of(w: World, o: Dictionary) -> Squad:
	var subjects: Array = o.get("subjects", [])
	if subjects.is_empty():
		return null
	var rec: Squad = w.squads.get(int(subjects[0]))
	if rec == null or rec.kind != "wing":
		return null
	return w.squads.get(rec.wing_id)


## May the wing order `o` be given now? Returns "" or the refusal text. It runs at submit and again
## when the order is carried out (it does not look for repeats: handle() does).
static func check(w: World, o: Dictionary) -> String:
	var kind := str(o.get("kind", ""))
	var subjects: Array = o.get("subjects", [])
	if subjects.is_empty():
		return OrderKinds.TEXT_VALUE
	var first: Variant = w.squads.get(int(subjects[0]))
	if first == null:
		return OrderKinds.TEXT_GONE_SQUAD
	# Only a pilot's wing has a brain in part 1; the Admiral's squadrons come later.
	var lead := wing_of(w, o)
	if lead == null:
		return OrderKinds.TEXT_UNBUILT
	if not Squads.wing_alive(w, lead.wing_id):
		return TEXT_NO_WING
	var leader := Squads.leader_ship(w, lead)
	if leader == null:
		return OrderKinds.TEXT_GONE_UNIT
	var target_kind := str(o.get("target_kind", "none"))
	match kind:
		OrderKinds.ESCORT, OrderKinds.MOVE:
			if target_kind != "unit" or int(o["target"]) != leader.uid:
				return OrderKinds.TEXT_VALUE
		OrderKinds.ATTACK:
			var t := w.orders.unit_by_uid(int(o["target"]))
			if t == null or t.team != Rules.enemy_of(lead.team) or not t.visible_to(lead.team):
				return TEXT_NOT_SEEN
			if _reach(leader, t) > SquadEngine.ATTACK_LEASH:
				return TEXT_FAR
		OrderKinds.GUARD:
			var g := w.orders.unit_by_uid(int(o["target"]))
			if g == null or not is_ward(g, lead.team) or g == leader:
				return TEXT_NO_BIG
			if _reach(leader, g) > SquadEngine.ATTACK_LEASH:
				return TEXT_FAR
	return ""


## The distance from the leader to unit `u` for the 3,200 rule: from the unit's hull for a
## mothership, else between the centres.
static func _reach(leader: Ship, u: Unit) -> float:
	if u is Mothership:
		return (u as Mothership).hull_dist(leader.global_position)
	return leader.global_position.distance_to(u.global_position)


## Is unit `u` something team `team` may guard: a friendly ship of a corvette's size or more, or
## the team's own mothership?
static func is_ward(u: Unit, team: int) -> bool:
	if u == null or not u.alive or u.team != team:
		return false
	if u is Mothership:
		return true
	return u is Ship and u.size_class >= Rules.SIZE_MEDIUM


# --- carrying out ---------------------------------------------------------------------------------

## Carry out wing order `o` (the queue calls it at the start of the next tick, after check()).
## Returns "" or the refusal text; a repeat of the wing's last order within 30 ticks is refused
## "Same order again" (code duplicate), which is logged and never shown.
static func handle(w: World, o: Dictionary) -> String:
	var lead := wing_of(w, o)
	if lead == null:
		return OrderKinds.TEXT_GONE_SQUAD
	var kind := str(o["kind"])
	var key := dedup_key(o)
	var apply_tick := int(o["apply_tick"])
	if SquadEngine.is_duplicate(lead.engine, kind, key, apply_tick):
		return OrderKinds.TEXT_DUPLICATE
	SquadEngine.note_order(lead.engine, kind, key, apply_tick)
	var settings: Dictionary = o["settings"]
	var recs := Squads.wing_records(w, lead.wing_id)
	for rec: Squad in recs:
		match kind:
			OrderKinds.SET_FORMATION:
				rec.formation = int(settings["formation"])
			OrderKinds.SET_STANCE:
				if settings.has("fire"):
					rec.fire_stance = int(settings["fire"])
				if settings.has("move"):
					rec.move_stance = int(settings["move"])
			_:
				rec.order = {"kind": kind, "target_kind": str(o["target_kind"]), "target": o["target"], "tick": apply_tick, "settings": settings.duplicate()}
				rec.move_stance = 0 if kind == OrderKinds.HOLD else 1
	if kind == OrderKinds.MOVE:
		lead.engine["regroup_t"] = w.tick_count
		# Nobody counts as in its place until its own next think says so.
		for rec: Squad in recs:
			rec.engine["in_slot"] = false
	if kind != OrderKinds.SET_FORMATION and kind != OrderKinds.SET_STANCE:
		# A new standing order clears the old order's private notes.
		lead.engine.erase("attack_hidden")
		lead.engine.erase("guard_idle")
	return ""


## What makes two orders "the same order" for the repeat window: the target, the role of an
## ESCORT, the value of a formation or stance order.
static func dedup_key(o: Dictionary) -> String:
	var settings: Dictionary = o.get("settings", {})
	match str(o["kind"]):
		OrderKinds.SET_FORMATION:
			return "f%d" % int(settings.get("formation", -1))
		OrderKinds.SET_STANCE:
			return "s%d/%d" % [int(settings.get("fire", -1)), int(settings.get("move", -1))]
		OrderKinds.ESCORT:
			return "%s/%s" % [str(o["target"]), str(settings.get("role", "follow"))]
	return str(o["target"])


# --- what the mouse is on ------------------------------------------------------------------------

## The tap's pick from two lists of candidates, each entry a Dictionary {uid, d}: `d` the distance
## from the reticle (for a mothership, from its hull). The nearest enemy within PICK_ENEMY_RADIUS
## gives {"kind": "attack", "uid"}; else the nearest big friendly ship within PICK_BIG_RADIUS gives
## {"kind": "guard", "uid"}; else {"kind": "none", "uid": 0}.
static func pick_from(enemies: Array, bigs: Array) -> Dictionary:
	var e := _nearest(enemies, PICK_ENEMY_RADIUS)
	if e >= 0:
		return {"kind": "attack", "uid": int((enemies[e] as Dictionary)["uid"])}
	var b := _nearest(bigs, PICK_BIG_RADIUS)
	if b >= 0:
		return {"kind": "guard", "uid": int((bigs[b] as Dictionary)["uid"])}
	return {"kind": "none", "uid": 0}


## The index of the entry of `list` with the smallest `d` that is within `radius` (the first one
## on a tie, so the stored order decides), or -1.
static func _nearest(list: Array, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in list.size():
		var d := float((list[i] as Dictionary)["d"])
		if d <= radius and (best < 0 or d < best_d):
			best_d = d
			best = i
	return best


## What team `team` has under the reticle at world point `aim`: the two candidate lists of
## pick_from() read from the world (an enemy unit our team can see, nearest first; a friendly ship
## of a corvette's size or more that is not `leader`, or our mothership). The units come from the
## spatial hash; a mothership is measured to its hull.
static func candidates_at(w: World, team: int, aim: Vector2, leader: Ship) -> Dictionary:
	var enemies: Array = []
	var bigs: Array = []
	var seen: Array = []
	for u: Unit in w.unit_hash.query(aim, PICK_BIG_RADIUS, seen):
		if not u.alive:
			continue
		var d := aim.distance_to(u.global_position)
		if u.team == Rules.enemy_of(team):
			if d <= PICK_ENEMY_RADIUS and u.visible_to(team):
				enemies.append({"uid": u.uid, "d": d})
		elif u.team == team and u != leader and u is Ship and u.size_class >= Rules.SIZE_MEDIUM and d <= PICK_BIG_RADIUS:
			bigs.append({"uid": u.uid, "d": d})
	for t in 2:
		var ms := w.mothership(t)
		if ms == null or not ms.alive:
			continue
		var md := ms.hull_dist(aim)
		if t == team and md <= PICK_BIG_RADIUS:
			bigs.append({"uid": ms.uid, "d": maxf(md, 0.0)})
		elif t != team and md <= PICK_ENEMY_RADIUS and ms.visible_to(team):
			enemies.append({"uid": ms.uid, "d": maxf(md, 0.0)})
	return {"enemies": enemies, "bigs": bigs}


## The tap's pick at `aim` for the wing of `pilot` (see pick_from()).
static func pick_under_reticle(w: World, team: int, aim: Vector2, leader: Ship = null) -> Dictionary:
	var c := candidates_at(w, team, aim, leader)
	return pick_from(c["enemies"], c["bigs"])


# --- the gestures -----------------------------------------------------------------------------------

## The result of a gesture that built an order: {"order": the record to submit, "text": ""}.
static func _built(o: Dictionary) -> Dictionary:
	return {"order": o, "text": ""}


## The result of a gesture that built nothing: {"order": {}, "text": why}.
static func _nothing(text: String) -> Dictionary:
	return {"order": {}, "text": text}


## The order record for `kind` from `pilot` to their wing, with `target_kind` and `target` and the
## settings; a wing that does not exist gives "You have no wingmen" instead.
static func _record(w: World, pilot: PilotProfile, kind: String, settings: Dictionary, target_kind: String, target: Variant) -> Dictionary:
	var lead := Squads.lead_record(w, pilot.team, pilot.slot)
	if lead == null or not Squads.wing_alive(w, lead.wing_id):
		return _nothing(TEXT_NO_WING)
	return _built(Order.make(kind, pilot.team, pilot.slot, true, settings, [lead.wing_id], target_kind, target))


## The pilot's ship, or null.
static func _ship_of(pilot: PilotProfile) -> Ship:
	var s: Variant = pilot.ship
	if s == null or not is_instance_valid(s) or not (s as Ship).alive:
		return null
	return s as Ship


## "Form on me" (`role` "follow") or "Cover me" (`role` "defend"): ESCORT on the leader's ship.
static func escort(w: World, pilot: PilotProfile, role: String) -> Dictionary:
	var ship := _ship_of(pilot)
	if ship == null:
		return _nothing(TEXT_NO_WING)
	return _record(w, pilot, OrderKinds.ESCORT, {"role": role}, "unit", ship.uid)


## "Attack my target": ATTACK on the enemy nearest the reticle `aim`, or "No target under the reticle".
static func attack(w: World, pilot: PilotProfile, aim: Vector2) -> Dictionary:
	var pick := pick_under_reticle(w, pilot.team, aim, _ship_of(pilot))
	if str(pick["kind"]) != "attack":
		return _nothing(TEXT_NO_TARGET)
	return _record(w, pilot, OrderKinds.ATTACK, {}, "unit", int(pick["uid"]))


## "Guard that ship": GUARD on our big ship (or the mothership) nearest the reticle `aim`, or "No
## big ship under the reticle". An enemy near the reticle does not stop it: the nearest big ship
## of ours counts.
static func guard(w: World, pilot: PilotProfile, aim: Vector2) -> Dictionary:
	var c := candidates_at(w, pilot.team, aim, _ship_of(pilot))
	var pick := pick_from([], c["bigs"])
	if str(pick["kind"]) != "guard":
		return _nothing(TEXT_NO_BIG)
	return _record(w, pilot, OrderKinds.GUARD, {}, "unit", int(pick["uid"]))


## "Hold here": HOLD at the leader's position (whole numbers) with the leader's heading in whole degrees.
static func hold(w: World, pilot: PilotProfile) -> Dictionary:
	var ship := _ship_of(pilot)
	if ship == null:
		return _nothing(TEXT_NO_WING)
	var heading := posmod(roundi(rad_to_deg(ship.rotation)), 360)
	return _record(w, pilot, OrderKinds.HOLD, {"heading": heading}, "point", Order.point(ship.global_position))


## "Regroup": MOVE to the leader (the target is the leader's ship uid).
static func regroup(w: World, pilot: PilotProfile) -> Dictionary:
	var ship := _ship_of(pilot)
	if ship == null:
		return _nothing(TEXT_NO_WING)
	return _record(w, pilot, OrderKinds.MOVE, {}, "unit", ship.uid)


## A formation chip: SET_FORMATION with the explicit value `formation`.
static func set_formation(w: World, pilot: PilotProfile, formation: int) -> Dictionary:
	return _record(w, pilot, OrderKinds.SET_FORMATION, {"formation": formation}, "none", 0)


## A fire chip: SET_STANCE with the explicit fire setting `fire`.
static func set_fire(w: World, pilot: PilotProfile, fire: int) -> Dictionary:
	return _record(w, pilot, OrderKinds.SET_STANCE, {"fire": fire}, "none", 0)


## The tap: ATTACK on an enemy within 300 of the reticle, else GUARD on a big ship of ours within
## 600, else "Form on me".
static func tap(w: World, pilot: PilotProfile, aim: Vector2) -> Dictionary:
	var pick := pick_under_reticle(w, pilot.team, aim, _ship_of(pilot))
	match str(pick["kind"]):
		"attack":
			return _record(w, pilot, OrderKinds.ATTACK, {}, "unit", int(pick["uid"]))
		"guard":
			return _record(w, pilot, OrderKinds.GUARD, {}, "unit", int(pick["uid"]))
	return escort(w, pilot, "follow")


## The next formation after the wing's current one, as an explicit SET_FORMATION (key preset B's
## "next formation": the key layer computes the value, no toggle reaches the record).
static func next_formation(w: World, pilot: PilotProfile) -> Dictionary:
	var lead := Squads.lead_record(w, pilot.team, pilot.slot)
	if lead == null:
		return _nothing(TEXT_NO_WING)
	return set_formation(w, pilot, Formations.next_formation(lead.formation))


## The next fire setting after the wing's current one, as an explicit SET_STANCE.
static func next_fire(w: World, pilot: PilotProfile) -> Dictionary:
	var lead := Squads.lead_record(w, pilot.team, pilot.slot)
	if lead == null:
		return _nothing(TEXT_NO_WING)
	return set_fire(w, pilot, Formations.next_fire(lead.fire_stance))


## The gesture named `name` ("tap", "follow", "cover", "attack", "guard", "hold", "regroup",
## "formation", "fire", "next_formation", "next_fire") for `pilot`; `arg` is the value of a
## formation or fire chip and `aim` the reticle. This is the one door the wheel, the tap and the
## key preset use. Returns {"order": record or {}, "text": why not}.
static func gesture(w: World, pilot: PilotProfile, name: String, arg: int = 0, aim: Vector2 = Vector2.ZERO) -> Dictionary:
	match name:
		"tap":
			return tap(w, pilot, aim)
		"follow":
			return escort(w, pilot, "follow")
		"cover":
			return escort(w, pilot, "defend")
		"attack":
			return attack(w, pilot, aim)
		"guard":
			return guard(w, pilot, aim)
		"hold":
			return hold(w, pilot)
		"regroup":
			return regroup(w, pilot)
		"formation":
			return set_formation(w, pilot, arg)
		"fire":
			return set_fire(w, pilot, arg)
		"next_formation":
			return next_formation(w, pilot)
		"next_fire":
			return next_fire(w, pilot)
	return _nothing(OrderKinds.TEXT_VALUE)


## Give a gesture's order to the order queue. Returns {"submitted": true, "text": ""} when the queue
## took it, {"submitted": true, "text": why} when the queue refused it at once (its event is filed;
## the screen shows `text`), and {"submitted": false, "text": why} when no order could be built
## (nothing under the reticle; the screen shows `text`, nothing is logged).
static func send(w: World, g: Dictionary) -> Dictionary:
	if (g["order"] as Dictionary).is_empty():
		return {"submitted": false, "text": str(g["text"])}
	return {"submitted": true, "text": w.orders.submit(g["order"])}


# --- the words ------------------------------------------------------------------------------------------

## The name of unit `u` for a pop-up: a pilot's callsign, else a ship's short hull name, else the
## kind of unit.
static func unit_name(u: Unit) -> String:
	if u == null:
		return "target"
	if u is Mothership:
		return "the mothership"
	if u.display_name != "":
		return u.display_name
	if u is Ship:
		return Formations.short_hull((u as Ship).hull_id)
	return str(Unit.KIND_NAMES[u.kind]).capitalize()


## The pop-up that confirms a wing order that was carried out: "Wing: forming on you", "Wing: covering
## you", "Wing: attacking <name>", "Wing: guarding <name>", "Wing: holding here", "Wing: regrouping",
## "Wing: <Wedge> formation", "Wing: fire at will" (or return fire, hold fire). It reads the wing's
## lead record (`squad_id` is the wing's id), so it says what the record says.
static func confirm_text(w: World, kind: String, squad_id: int) -> String:
	var lead: Squad = w.squads.get(squad_id)
	if lead == null:
		return ""
	match kind:
		OrderKinds.ESCORT:
			var role := str((lead.order.get("settings", {}) as Dictionary).get("role", "follow"))
			return "Wing: covering you" if role == "defend" else "Wing: forming on you"
		OrderKinds.ATTACK:
			return "Wing: attacking %s" % unit_name(w.orders.unit_by_uid(int(lead.order.get("target", 0))))
		OrderKinds.GUARD:
			return "Wing: guarding %s" % unit_name(w.orders.unit_by_uid(int(lead.order.get("target", 0))))
		OrderKinds.HOLD:
			return "Wing: holding here"
		OrderKinds.MOVE:
			return "Wing: regrouping"
		OrderKinds.SET_FORMATION:
			return "Wing: %s formation" % Formations.formation_name(lead.formation)
		OrderKinds.SET_STANCE:
			return "Wing: %s" % str(Formations.FIRE_TOASTS[clampi(lead.fire_stance, 0, 2)])
	return ""


## The pop-up for an order refused by its reason `code` when it was carried out (the screen that
## submitted it shows its own refusal text at once). "" for a code that is not shown (a repeat).
static func refusal_text(code: String) -> String:
	match code:
		"gone":
			return TEXT_NOT_SEEN
		"place":
			return TEXT_FAR
		"value":
			return OrderKinds.TEXT_VALUE
		"seat":
			return OrderKinds.TEXT_SEAT
		"late":
			return OrderKinds.TEXT_LATE
	return ""
