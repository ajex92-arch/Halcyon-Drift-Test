class_name AdmiralReactions
extends RefCounted
## WHAT THIS IS: the computer Admiral's reactions to what happens to its team (RT5 build 4a): a build that
## cannot start, a fleet at its limit, the base under attack, a pilot's ship lost. Each reaction is one switch of
## the Admiral's profile (react_build_blocked, react_cap_full, react_under_attack, react_ship_lost). All four are
## off in every profile until the lead's switch-on commit, and with a switch off its reaction sends no order, writes
## no log line and changes nothing in the match.
##
## HOW IT WORKS: once a think, before step 1 of AdmiralAI's list, think() reads this team's new records from the
## match's event stream (World.events_rts) with a cursor of its own, counts them (a record the stream dropped before
## it could be read goes into `missed`), and then lets each reaction whose switch is on act. A reaction never runs
## inside the event push: it runs at the next think, up to a second late, so it is part of the Admiral's own turn and
## draws no random number. Squadrons are always taken in id order. Every order goes through send(), the order queue's
## same-tick door from the Admiral's seat, exactly like the Admiral's other orders, so the match log's "a" lines and
## --admiral-replay carry it. Nothing here reads hidden enemy state: the inputs are the team's own yard, squadrons and
## pilots, the records of its own stream and the team's defend point (which TeamDefense builds only from ships the team
## sees).
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.react) and calls think() at the start of every think; the numbers are
## keys of the team's AdmiralProfile; tests/react_check.gd checks it and tests/admiral_audit.gd prints stats().

## The four switches, in the order the reactions run.
const SWITCHES := ["react_build_blocked", "react_cap_full", "react_under_attack", "react_ship_lost"]

## The game world.
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## This admiral's numbers and switches.
var prof: AdmiralProfile
## The lane helper (the front of a lane).
var lanes: AdmiralLanes
## The field-trip part (how many pilots are down, which lane to cover).
var field: AdmiralField
## The running index of the next record of our stream that think() has not read.
var cursor := 0
## Records the stream dropped (its ring is 512) before think() read them.
var missed := 0
## How many times think() has run.
var thinks := 0
## Counters by name: "seen_<what>" for the records read, "<reaction>_<ORDER>_ok" and "_fail" for the orders sent.
var counters := {}
## The treasury added up over the thinks at which the fleet was full (credit-seconds), the most it held, and how many
## thinks it was full: the ore that sat unspent at a full cap. Counted whether the switches are on or off.
var float_ore_sum := 0.0
var float_ore_max := 0.0
var float_thinks := 0
## Item id -> the match second its "unlock" block was first read (build blocked: cancelled after react_cancel_s).
var _unlock_since := {}
## True from a "cap_full" record until the cap-full reaction has looked at it.
var _cap_pending := false
## The squadrons called to the defend point: squad id -> {"point": the Vector2 it was last sent to, "t": the match second}.
var _called := {}
## True from a pilot's "ship_lost" record until fewer than field_min_down pilots are down.
var _lost_armed := false
## The squadron that fills in for dead pilots (0 for none), the point it was last sent to and the match second of that order.
var _filler_id := 0
var _filler_point := Vector2.ZERO
var _filler_t := 0.0


## Make the reactions of team `t` in world `w`. AdmiralAI makes this once.
func _init(w: World, t: int, l: AdmiralLanes, f: AdmiralField, p: AdmiralProfile = null) -> void:
	world = w
	team = t
	lanes = l
	field = f
	prof = p if p != null else AdmiralProfile.for_team(t, Game.options)
	# Only what happens from now on (a replacement Admiral after a mutiny does not react to the old Admiral's records).
	if w.events_rts != null:
		cursor = w.events_rts.next_index(t)


## True when at least one reaction is on.
func any_on() -> bool:
	for key: String in SWITCHES:
		if prof.on(key):
			return true
	return false


## One think, called before step 1: read the new records, then let each reaction that is on act.
func think(ts: TeamState) -> void:
	thinks += 1
	var recs := _read()
	_count_float(ts)
	for rec: Dictionary in recs:
		_see(rec)
	if prof.on("react_build_blocked"):
		_blocked_act(ts)
	if prof.on("react_cap_full"):
		_cap_act(ts)
	if prof.on("react_under_attack"):
		_attack_act(ts)
	if prof.on("react_ship_lost"):
		_lost_act()


## The new records of our stream since the last read, oldest first; the cursor moves to the end of them.
func _read() -> Array:
	if world.events_rts == null:
		return []
	var next := world.events_rts.next_index(team)
	var recs := world.events_rts.read_from(team, cursor)
	var owed := next - cursor
	if recs.size() < owed:
		missed += owed - recs.size()
	cursor = next
	return recs


## Count one record of the kinds the reactions care about.
func _see(rec: Dictionary) -> void:
	var rt := int(rec.get("team", -1))
	if rt != team and rt != -1:
		return
	var data: Dictionary = rec.get("data", {})
	match str(rec.get("kind", "")):
		"build_blocked":
			var reason := str(data.get("reason", "?"))
			_bump("seen_blocked_" + reason)
			if prof.on("react_build_blocked"):
				_note_blocked(reason, str(data.get("item", "")))
		"cap_full":
			_bump("seen_cap_full")
			if prof.on("react_cap_full"):
				_cap_pending = true
		"mothership_under_attack":
			_bump("seen_under_attack")
		"ship_lost":
			# Every lost ship files one (bought and wing ships too): only a pilot's ship counts, and not the Admiral's own.
			_bump("seen_ship_lost")
			if int(data.get("squad", 0)) == 0 and int(data.get("wing", 0)) == 0:
				if _is_admiral_ship(int(rec.get("uid", 0))):
					_bump("seen_admiral_lost")
				else:
					_bump("seen_pilot_lost")
					if prof.on("react_ship_lost"):
						_lost_armed = true


# --- build blocked (note A1) ---------------------------------------------------------------------------------------

## A "build_blocked" record was read: one "not yet" line for the item and the reason (the log keeps it to one per
## reason every 60 s and never repeats an item), and an "unlock" block starts its clock. Nothing else is done: a queued
## item is never ordered twice, and the other reasons (ore, room, line, mothership) are answered by the yard or clear
## themselves.
func _note_blocked(reason: String, id: String) -> void:
	var prod: Production = world.teams[team].production
	var it := prod.find(id)
	if it.is_empty():
		return
	if reason == "unlock" and not _unlock_since.has(id):
		_unlock_since[id] = world.time
	var what := prod.label(it)
	var text := ""
	match reason:
		"ore":
			text = "has %s waiting for ore: %d more credits are needed" % [what, int(it["need"])]
		"room":
			text = "has %s waiting for room: the fleet is at its limit" % what
		"line":
			text = "has %s waiting for a free build line" % what
		"unlock":
			text = "has %s that cannot be built yet: it needs %s" % [what, str(it["need_text"])]
		"mothership":
			text = "has %s built but the mothership cannot launch it yet" % what
		_:
			text = "has %s waiting (%s)" % [what, reason]
	AdmiralLog.of(world).not_yet(team, "react.blocked." + reason, id, text)


## Cancel an item that has been blocked by a missing unlock for react_cancel_s seconds (it refunds what it paid). The
## Admiral buys only unlocked hulls, so this is a safety net; an item that is gone, started or blocked by something
## else drops out of the list.
func _blocked_act(ts: TeamState) -> void:
	var prod := ts.production
	for id: String in _unlock_since.keys():
		var it := prod.find(id)
		if it.is_empty() or it["started"] or str(it["why"]) != "unlock":
			_unlock_since.erase(id)
			continue
		var waited := world.time - float(_unlock_since[id])
		if waited < prof.f("react_cancel_s"):
			continue
		AdmiralLog.of(world).expect(team, "CANCEL", "react.blocked", "cancels %s" % prod.label(it), "waiting on", "it has been blocked for %d seconds by a missing unlock (%s)" % [int(waited), str(it["need_text"])])
		send("blocked", OrderKinds.CANCEL, {}, [], "item", id)
		_unlock_since.erase(id)


# --- cap full (note A2) -------------------------------------------------------------------------------------------------

## True while some item of `prod` has not started and waits for room in the fleet.
static func waits_for_room(prod: Production) -> bool:
	for it: Dictionary in prod.items:
		if not it["started"] and str(it["why"]) == "room":
			return true
	return false


## After a "cap_full" record, or while an item waits for room: turn the Fighter repeat off (a repeat would only queue
## a squadron that waits for room). AdmiralProduction keeps it off while an item waits; once none does, its own repeat
## rule turns it back on if the fleet is below its target.
func _cap_act(ts: TeamState) -> void:
	var prod := ts.production
	if not (_cap_pending or waits_for_room(prod)):
		return
	_cap_pending = false
	if int(prod.repeat.get(Ships.DEFAULT_HULL, 0)) != 1:
		return
	AdmiralLog.of(world).expect(team, "SET_REPEAT", "react.cap_full", "turns the Fighter repeat off", "keeping it on", "the fleet is at its limit (%d of %d places), so another squadron would only wait for room" % [prod.capacity.used(), prod.capacity.limit()])
	send("cap_full", OrderKinds.SET_REPEAT, {"repeat": 0}, [], "id", Ships.DEFAULT_HULL)


# --- base under attack (note A3, "nearby ones") ---------------------------------------------------------------------------

## While the alarm is on (TeamState.defending: 2 or more visible enemy frigates or bigger at the base), every bought
## squadron or ship inside the pilots' reach (react_reach_small for strike craft, react_reach_big for the rest; the
## pilots' own 12,000 and 18,000) gets a Move to the defend point, one order each in squad-id order. A squadron that
## comes into reach later joins at the next think. A called squadron is sent again when the defend point has moved more
## than react_resend_dist, at most once every react_resend_gap_s. Nothing is sent while our siege survives the alarm
## (siege_lane still set: the assault is close to winning). At the first think without the alarm each called squadron
## gets a Move back to its own rally point.
func _attack_act(ts: TeamState) -> void:
	var now := world.time
	for id: int in _called.keys():
		var gone: Squad = world.squads.get(id) as Squad
		if gone == null or _ships_of(gone).is_empty():
			_called.erase(id)
	if not ts.defending(now):
		_recall()
		return
	if ts.siege_lane != "":
		return
	var point := ts.defend_point
	var first := _called.is_empty()
	var sent := 0
	for rec: Squad in _own_squads():
		var info: Dictionary = _called.get(rec.id, {})
		var ships := _ships_of(rec)
		if info.is_empty():
			var far := _reach_of(ships)
			if _centre_of(ships).distance_to(point) >= far:
				continue
			if _move(rec, point, "react.attack", "sends %s to the defend point" % _name_of(rec), "leaving it where it is",
					"the base is under attack and the squadron is within %d of the defend point" % roundi(far)):
				_called[rec.id] = {"point": point, "t": now}
				sent += 1
		elif point.distance_to(info["point"] as Vector2) > prof.f("react_resend_dist") and now - float(info["t"]) >= prof.f("react_resend_gap_s"):
			info["t"] = now
			if _move(rec, point, "react.attack", "sends %s to the defend point again" % _name_of(rec), "leaving it where it is",
					"the defend point has moved more than %d since the last order" % roundi(prof.f("react_resend_dist"))):
				info["point"] = point
	if first and sent > 0:
		AdmiralLog.feed(world, team, "The %s Admiral calls its fleet home to defend the base." % Rules.TEAM_DISPLAY[team])


## The alarm is over: every called squadron goes back to its own rally point.
func _recall() -> void:
	if _called.is_empty():
		return
	var ids: Array = _called.keys()
	ids.sort()
	var back := 0
	for id: int in ids:
		var rec: Squad = world.squads.get(id) as Squad
		if rec != null and not _ships_of(rec).is_empty():
			if _move(rec, Vector2(rec.rally), "react.attack", "sends %s back to its rally point" % _name_of(rec), "leaving it at the base",
					"the alarm is over"):
				back += 1
		_called.erase(id)
	if back > 0:
		AdmiralLog.feed(world, team, "The %s Admiral sends its fleet back to the lanes." % Rules.TEAM_DISPLAY[team])


## Send squadron `rec` a Move to `p`, with the log's note for it. Returns true when the order was carried out.
func _move(rec: Squad, p: Vector2, rule: String, chose: String, over: String, why: String) -> bool:
	AdmiralLog.of(world).expect(team, "MOVE", rule, chose, over, why)
	return send(rule.trim_prefix("react."), OrderKinds.MOVE, {}, [rec.id], "point", Order.point(p)) == ""


## Our bought squadrons and ships that have a ship alive, in id order.
func _own_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team == team and SquadOrders.is_bought(rec) and not _ships_of(rec).is_empty():
			out.append(rec)
	return out


## The ships of `rec` that are alive, in the record's order.
func _ships_of(rec: Squad) -> Array[Ship]:
	var out: Array[Ship] = []
	for uid: int in rec.member_uids:
		var u: Variant = world.by_uid.get(uid)
		if u != null and is_instance_valid(u) and (u as Unit).alive and u is Ship:
			out.append(u as Ship)
	return out


## The middle of `ships` (the origin for none).
func _centre_of(ships: Array[Ship]) -> Vector2:
	if ships.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for s: Ship in ships:
		sum += s.global_position
	return sum / float(ships.size())


## How far from the defend point a squadron of `ships` still answers the alarm: the pilots' rule (strike craft 12,000,
## the rest 18,000, read from the profile).
func _reach_of(ships: Array[Ship]) -> float:
	if ships.is_empty():
		return 0.0
	return prof.f("react_reach_small") if ships[0].is_small() else prof.f("react_reach_big")


## The squadron's name for the log: its hull and its ship count.
func _name_of(rec: Squad) -> String:
	return "the %s x%d" % [str(Ships.HULLS[rec.hull_id]["label"]), _ships_of(rec).size()]


# --- pilots lost (note A4, "a squadron fills in") ------------------------------------------------------------------------------

## After a pilot's ship was lost, while field_min_down (2) or more of our pilots are dead (on any lanes; the Admiral's own
## death does not count): our nearest bought squadron that is not called to defend gets a Move to the front of the first
## dead pilot's lane (the lowest seat's, AdmiralField.cover_lane; the point a lane rally uses). It goes back to its rally
## when fewer are dead. One squadron fills in at a time; it is sent again under the defence's re-send rule when the front
## moves.
func _lost_act() -> void:
	var now := world.time
	if _filler_id != 0:
		var held: Squad = world.squads.get(_filler_id) as Squad
		if held == null or _ships_of(held).is_empty() or _called.has(_filler_id):
			_filler_id = 0
	if not _lost_armed and _filler_id == 0:
		return
	var down := field.pilots_down()
	if down < prof.i("field_min_down"):
		_lost_armed = false
		_release_filler()
		return
	var lane := field.cover_lane()
	var point := Vector2(lanes.front_point(lane))
	if _filler_id == 0:
		var best: Squad = null
		var best_d := INF
		for rec: Squad in _own_squads():
			if _called.has(rec.id):
				continue
			var d := _centre_of(_ships_of(rec)).distance_to(point)
			if d < best_d:
				best_d = d
				best = rec
		if best != null and _move(best, point, "react.lost", "sends %s to the %s lane to fill in" % [_name_of(best), lane], "keeping it where it is",
				"%d of our pilots are down, so the nearest squadron holds the lane of the first of them" % down):
			_filler_id = best.id
			_filler_point = point
			_filler_t = now
	elif point.distance_to(_filler_point) > prof.f("react_resend_dist") and now - _filler_t >= prof.f("react_resend_gap_s"):
		var rec2: Squad = world.squads.get(_filler_id) as Squad
		_filler_t = now
		if _move(rec2, point, "react.lost", "sends %s to the front of the %s lane again" % [_name_of(rec2), lane], "keeping it where it is",
				"the front has moved more than %d since the last order" % roundi(prof.f("react_resend_dist"))):
			_filler_point = point


## Fewer pilots are down: the squadron that filled in goes back to its rally point.
func _release_filler() -> void:
	if _filler_id == 0:
		return
	var rec: Squad = world.squads.get(_filler_id) as Squad
	_filler_id = 0
	if rec != null and not _ships_of(rec).is_empty() and not _called.has(rec.id):
		_move(rec, Vector2(rec.rally), "react.lost", "sends %s back to its rally point" % _name_of(rec), "leaving it on the lane", "fewer than %d of our pilots are down" % prof.i("field_min_down"))


## Is the lost ship with unit id `uid` the Admiral's own (its record is still known and holds the Admiral's seat)?
func _is_admiral_ship(uid: int) -> bool:
	var u: Variant = world.by_uid.get(uid)
	if u == null or not is_instance_valid(u) or not (u is Ship):
		return false
	var p: PilotProfile = (u as Ship).profile
	return p != null and p.role == "admiral"


## The ore that sits unspent while the fleet is full (it changes no spending).
func _count_float(ts: TeamState) -> void:
	if ts.production.capacity.room_for(1):
		return
	float_thinks += 1
	float_ore_sum += ts.treasury
	float_ore_max = maxf(float_ore_max, ts.treasury)


## Add `n` to counter `name`.
func _bump(name: String, n: int = 1) -> void:
	counters[name] = int(counters.get(name, 0)) + n


## Send an order of the Admiral's seat through the order queue's same-tick door and count it under `which` (the
## reaction's name). Returns "" or the refusal text.
func send(which: String, kind: String, settings: Dictionary, subjects: Array, target_kind: String, target: Variant) -> String:
	var why := world.orders.apply_now(Order.make(kind, team, Deputy.computer_seat(world, team), false, settings, subjects, target_kind, target))
	_bump("%s_%s_%s" % [which, kind, "ok" if why == "" else "fail"])
	return why


## Everything the audit prints, as one Dictionary of numbers.
func stats() -> Dictionary:
	var out := counters.duplicate()
	out["thinks"] = thinks
	out["missed"] = missed
	out["float_thinks"] = float_thinks
	out["float_ore_sum"] = roundi(float_ore_sum)
	out["float_ore_max"] = roundi(float_ore_max)
	return out
