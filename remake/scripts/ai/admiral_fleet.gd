class_name AdmiralFleet
extends RefCounted
## WHAT THIS IS: the computer Admiral's fleet layer (RT8 build 8a): once a think it plays the bought squadrons as one
## fleet, in four jobs. It exists only while the profile switch fleet_play is on (AdmiralAI makes it then); with the switch
## off no object, no order, no read and no random number is added to the match.
##   1. BASE DEFENCE FIRST. While the base alarm is on (TeamState.defending) the fleet declares no push and sends no order:
##      RT5's react_under_attack (AdmiralReactions) calls the squadrons within reach home. A squadron that reaction has
##      called home or sent to fill in for dead pilots (its _called and _filler_id) is never ordered by this layer. Only
##      the goal lane may change at once (LaneInfluence).
##   2. THE GOAL LANE (LaneInfluence): the lane to push, chosen by advantage and held 60 s.
##   3. ATTACK OR RETREAT (AdmiralPosture): our fleet against the enemy in the fight area of the goal lane. Falling back is
##      a Move to the nearest turret of ours, else the base; going in is a Move to the attack point beyond the front of our
##      minions (not past the lane's middle without two squadrons together, never inside an enemy turret's reach without
##      our minions there).
##   4. HELP BEFORE BEING ASKED: a free group of squadrons goes to the lane where our living pilots are most outnumbered by
##      the enemy ships the team sees (RT5 already covers two or more dead pilots). With two lanes in need the lane in worst
##      need goes first and a human pilot's lane wins a tie (profile fleet_help_pilot_first = 0, the recommended rule), or a
##      human pilot's own lane goes first (= 1).
##
## HOW IT WORKS: think() runs after the Admiral's buying (step 8 of AdmiralAI). The "free" squadrons are our bought
## squadrons and ships with a ship alive that RT5 has not called or sent to fill in, in squadron-id order. They are put in
## GROUPS (lists of squadron ids; squadrons within fleet_group_join of each other form one group), and a group's order is
## one order naming all its squadrons, as a human's box-select is. A squadron whose standing order already is a Move to
## the wanted point (within react_resend_dist), or that was ordered less than react_resend_gap_s ago, is not ordered
## again. Every order is a Move from the Admiral's seat through the outbox (AdmiralOutbox, the seat door), so the match
## log's "a" lines and --admiral-replay carry it. Everything is read through TeamView; there is no Input, no frame time in
## any decision (the think's own run time is only measured for stats()), and no random number.
## Build 8b added: the orders cap, the 0.3 s delay and the waiting list by priority (the outbox's full version; orders are put
## on its list during a think and go out at the end of it, and a squadron whose order was dropped may be ordered again at the
## next think), the helper group left out of our strength in the fight area, a squadron that something else ordered (RT5's
## reactions, the stand-in brain) held from this layer's orders for the resend gap (_note_orders), the waypoint and the "lane"
## rally following the goal lane, and the talk lines on the team feed (at most one every fleet_talk_gap_s, none while the
## base alarm is on: "Pushing <lane>", "Fall back to our turrets", "Going back in", "Help coming to <lane>").
## Replay of the goal lane: every change of influence.goal is written to the match log as an `f` line "goal" (_note_goal), and
## --admiral-replay, which runs no think, sets the goal lane from it (replay_goal), so the "lane" rally reads the same goal there.
## The unpark step (profile row fleet_unpark_s, 0 = off): a free squadron parked on its Move's target for that many seconds with an
## enemy ship or minion in reach (profile row fleet_unpark_reach) gets an Attack order on the nearest of either kind. Apart from that
## this layer sends Moves only.
##
## WHO USES IT: AdmiralAI makes one when fleet_play is on (AdmiralAI.fleet) and calls think() after step 8;
## tests/admiral_fleet_check.gd checks it; tests/admiral_audit.gd prints stats().

## How near a pilot is to a lane's path to count as on that lane (world units).
const LANE_BAND := 3000.0
## The share of fleet_help_edge below which a helper group is let go (so help does not flap at the edge).
const HELP_KEEP := 0.5

## The game world.
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The lane helper.
var lanes: AdmiralLanes
## What the team knows.
var view: TeamView
## The reactions part: its _called and _filler_id name the squadrons this layer never orders.
var react: AdmiralReactions
## This Admiral's numbers.
var prof: AdmiralProfile
## The goal lane choice, the attack or retreat state and the door the orders go through.
var influence: LaneInfluence
var posture: AdmiralPosture  # the attack or retreat state
var outbox: AdmiralOutbox  # the door the orders go through
## How many times think() has run.
var thinks := 0
## Squad id -> the match second this layer last ordered it (or last saw something else order it: see _note_orders).
var _sent := {}
## Squad id -> the "tick" of the standing order this layer last saw on that squadron (-1 for none).
var _seen := {}
## Squad id -> true while the squadron has had no standing order at two looks in a row (the "unordered" count).
var _unordered := {}
## The talk lines of the think now going, as [rank, text] (rank 0 posture, 1 goal lane, 2 help), and the match second the last
## line was spoken (a long time ago to start with).
var _lines: Array = []
var _said_at := -1000000.0  # the match second the last line was spoken
## Squad id -> the match second this layer first saw the squadron parked on its Move's target (the unpark step; empty while the row is 0).
var _parked_since := {}
## The helper group: {"lane": String, "ids": Array, "point": Vector2}; empty for none.
var _help := {}
## The last groups, Array of {"ids": Array, "centre": Vector2}.
var groups: Array = []
## Counters by name (see stats()).
var counters := {}
## The longest think and the sum of all thinks, in microseconds (measured, never read by a decision).
var think_us_max := 0
var think_us_sum := 0  # the sum of all think times, in microseconds
## How many thinks took longer than 2 ms (measured wall time, so a busy PC adds to it).
var think_over_2ms := 0
## How many thinks took longer than 2 ms without the time the order queue spent carrying the orders out, the longest of that time in one think, and the time spent on orders in the think now going.
var decide_over_2ms := 0
var send_us_max := 0  # the longest order-carrying time in one think
## How many thinks spent more than 2 ms in end_think (the order-carrying time, _send_us), and the sum of that time over all thinks, in microseconds (for the mean).
var send_over_2ms := 0
var send_us_sum := 0  # the sum of the order-carrying times of all thinks
var _send_us := 0  # the order-carrying time of the think now going
## Our minions' places and the think they were worked out in (see _minion_points).
var _mp: Array = []
var _mp_think := -1  # the think the places were worked out in


## Make the fleet layer of team `t` in world `w`. AdmiralAI makes this once, only while fleet_play is on. `r` is the
## reactions part of the same Admiral (null in a test with no reactions: nothing is then called or filling in).
func _init(w: World, t: int, l: AdmiralLanes, r: AdmiralReactions, p: AdmiralProfile) -> void:
	world = w
	team = t
	lanes = l
	view = l.view
	react = r
	prof = p
	influence = LaneInfluence.new(w, t, l, p)
	posture = AdmiralPosture.new(w, t, l, p)
	outbox = AdmiralOutbox.new(w, t, p)


## One think, called after step 8 of AdmiralAI's list.
func think(ts: TeamState) -> void:
	var t0 := Time.get_ticks_usec()
	_send_us = 0
	thinks += 1
	var now := world.time
	_note_orders(now)
	outbox.begin_think()
	_lines.clear()
	var alarm := ts.defending(now)
	var goal_before := influence.goal
	influence.think(now, alarm, ts.defend_point)
	if influence.goal != goal_before:
		_note_goal()
	var goal_text := goal_line(goal_before, influence.goal)
	if goal_text != "":
		_line(1, goal_text)
	if alarm:
		# Base defence first: RT5's reaction calls the squadrons within reach; this layer declares no push and orders nobody.
		_bump("alarm_thinks")
	else:
		_play(now)
	# The waiting list goes out now (the cap, the delay and the priorities are the outbox's); a squadron whose order was
	# dropped may be ordered again at the next think, not only after the resend gap.
	var s0 := Time.get_ticks_usec()
	var dropped := outbox.end_think()
	_send_us += Time.get_ticks_usec() - s0
	for id: int in dropped:
		_sent.erase(id)
	if outbox.last_refused > 0:
		_bump("refused", outbox.last_refused)
	# One talk line at most, the lowest rank of the think; none while the base alarm is on (RT5 speaks its own then).
	if not alarm:
		_speak(now)
	_lines.clear()
	var us := Time.get_ticks_usec() - t0
	think_us_sum += us
	think_us_max = maxi(think_us_max, us)
	if us > 2000:
		think_over_2ms += 1
	# The part of the think that was the order queue carrying the orders out (not this layer's own deciding).
	send_us_max = maxi(send_us_max, _send_us)
	send_us_sum += _send_us
	if _send_us > 2000:
		send_over_2ms += 1
	if us - _send_us > 2000:
		decide_over_2ms += 1


## Look at the standing order of every bought squadron of ours that has a ship alive (the start of every think, the alarm's
## included). A standing order of a bought squadron holds no id, only its "tick" (the apply tick, SquadOrders._handle_bought).
## One whose tick changed since the last look and is not among the apply ticks of this layer's own orders
## (AdmiralOutbox.own_ticks) was ordered by something else (RT5's reactions or the stand-in brain): it is marked as just
## ordered, so the resend gap holds it from the fleet's orders. A squadron seen for the first time is only recorded.
func _note_orders(now: float) -> void:
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team != team or not SquadOrders.is_bought(rec) or _ships_of(rec).is_empty():
			continue
		var tk := int(rec.order.get("tick", -1)) if not rec.order.is_empty() else -1
		if _seen.has(id) and tk != int(_seen[id]) and tk != -1 and not outbox.own_ticks(id).has(tk):
			_sent[id] = now
		# No order at this look and none at the last one either: a whole think went by without the squadron getting one (an order
		# of this think is only carried out at its end, or 18 ticks later, so the count cannot be taken at the end of the think).
		if tk == -1 and _seen.has(id) and int(_seen[id]) == -1:
			_unordered[id] = true
		else:
			_unordered.erase(id)
		_seen[id] = tk


## The squadrons this layer may order, in id order: our bought squadrons and ships with a ship alive that RT5 has not
## called home and has not sent to fill in.
func free_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team != team or not SquadOrders.is_bought(rec) or _ships_of(rec).is_empty():
			continue
		if react != null and (react._called.has(rec.id) or react._filler_id == rec.id):
			continue
		out.append(rec)
	return out


## The groups of `recs`: squadrons within fleet_group_join of a squadron of a group join it (squadron-id order, so the same
## match always makes the same groups). Each group is {"ids": Array of squad ids, "centre": Vector2 (the mean of its
## squadrons' places)}.
func make_groups(recs: Array[Squad]) -> Array:
	var join := prof.f("fleet_group_join")
	var sets: Array = []
	for rec: Squad in recs:
		var c := _centre_of(_ships_of(rec))
		var placed := false
		for g: Dictionary in sets:
			for gc: Vector2 in g["cs"]:
				if gc.distance_to(c) <= join:
					(g["ids"] as Array).append(rec.id)
					(g["cs"] as Array).append(c)
					placed = true
					break
			if placed:
				break
		if not placed:
			sets.append({"ids": [rec.id], "cs": [c]})
	var out: Array = []
	for g: Dictionary in sets:
		var sum := Vector2.ZERO
		for gc: Vector2 in g["cs"]:
			sum += gc
		out.append({"ids": g["ids"], "centre": sum / float((g["cs"] as Array).size())})
	return out


## Our side's strength for the posture: every ship of the free squadrons `free` wherever it is (it is ours to bring), and every
## other ship of ours in the fight area around `area`. The helper group that is out now (_help["ids"] as the last think left
## it; none when _help is empty) is not in the fight area: its ships add no power, and are marked so the second loop does not
## count them either.
func own_strength(free: Array[Squad], area: Vector2) -> float:
	var r := prof.f("fleet_area_radius")
	var helping := {}
	for hid: int in _help.get("ids", []):
		helping[hid] = true
	var members := {}
	var own := 0.0
	for rec: Squad in free:
		var away := helping.has(rec.id)
		for s: Ship in _ships_of(rec):
			members[s.uid] = true
			if not away:
				own += _power(s)
	for s: Ship in view.own_ships():
		if not members.has(s.uid) and s.global_position.distance_to(area) <= r:
			own += _power(s)
	return own


## The play of a quiet think (no base alarm): posture, then retreat or help and attack.
func _play(now: float) -> void:
	var free := free_squads()
	groups = make_groups(free)
	var goal := influence.goal
	var area: Vector2 = influence.areas[goal] if influence.areas.has(goal) else influence.area_point(goal)
	var own := own_strength(free, area)
	var enemy := posture.enemy_power(area)
	var switches_before := posture.switches
	var state := posture.think(now, own, enemy)
	if posture.switches != switches_before:
		_talk_posture(now)
	_bump(state + "_thinks")
	if free.is_empty():
		return
	if state == AdmiralPosture.RETREAT:
		_help = {}
		_retreat(free, now)
		return
	var helpers := _help_think(free, now)
	var rest: Array[Squad] = []
	for rec: Squad in free:
		if not helpers.has(rec.id) and not _on_unpark_job(rec):
			rest.append(rec)
	_attack(rest, goal, now)
	_unpark(rest, now)
	# The idle count: a free squadron that has had no standing order for a whole think (see _note_orders).
	for rec: Squad in free:
		if _unordered.has(rec.id):
			_bump("unordered_squad_thinks")


## Fall back: every group goes to the nearest turret of ours (the base when none stands); groups with the same place
## are one order.
func _retreat(free: Array[Squad], now: float) -> void:
	var by_point := {}
	var order_of_points: Array = []
	for g: Dictionary in make_groups(free):
		var dest := posture.fall_back_point(g["centre"])
		var key := "%d,%d" % [roundi(dest.x), roundi(dest.y)]
		if not by_point.has(key):
			by_point[key] = {"dest": dest, "ids": []}
			order_of_points.append(key)
		(by_point[key]["ids"] as Array).append_array(g["ids"])
	for key: String in order_of_points:
		var entry: Dictionary = by_point[key]
		var ids: Array = entry["ids"]
		ids.sort()
		_dispatch(AdmiralOutbox.PRI_RETREAT, "retreat", entry["dest"], ids, now,
			"sends %d squadrons back to the nearest turret of ours or the base" % ids.size(), "holding the lane",
			"our fleet is %d%% of the strength in the fight area, under the %d%% line" % [roundi(posture.ratio * 100.0), roundi(prof.f("fleet_retreat_below") * 100.0)])


## Go in: the squadrons `rest` all go to the attack point of the goal lane.
func _attack(rest: Array[Squad], goal: String, now: float) -> void:
	if rest.is_empty() or goal == "":
		return
	var centres: Array = []
	var strengths: Array = []
	var ids: Array = []
	for rec: Squad in rest:
		var ships := _ships_of(rec)
		var strength := 0.0
		for s: Ship in ships:
			strength += _power(s)
		centres.append(_centre_of(ships))
		strengths.append(strength)
		ids.append(rec.id)
	var together := AdmiralPosture.gathered(centres, strengths, prof.f("fleet_together_dist"))
	var dest := posture.attack_point(goal, influence.front_of(goal), together, view.enemy_turret_points(), _minion_points())
	_dispatch(AdmiralOutbox.PRI_ATTACK, "attack", dest, ids, now,
		"sends %d squadrons to push the %s lane" % [ids.size(), goal], "holding where they are",
		"our fleet is %d%% of the strength in the fight area, over the %d%% line" % [roundi(posture.ratio * 100.0), roundi(prof.f("fleet_return_above") * 100.0)])


## The unpark step (profile row fleet_unpark_s; 0 = off): a free squadron that has stood parked on its Move's target (the centre
## of its ships within react_resend_dist of the point) for fleet_unpark_s seconds or more, while an enemy ship or minion the team
## sees now is within fleet_unpark_reach of its centre, gets a standing Attack order on the nearest of either kind (the lower
## instance id on a tie; TeamView.nearest_seen_enemy_unit). An enemy turret is never the target (the turret rule of the attack
## point stays); a squadron ordered less than react_resend_gap_s ago waits. `rest` holds only free squadrons, so one the reactions
## called or sent to fill in is never ordered here.
func _unpark(rest: Array[Squad], now: float) -> void:
	var wait := prof.f("fleet_unpark_s")
	if wait <= 0.0:
		_parked_since.clear()
		return
	var arrived := prof.f("react_resend_dist")
	var gap := prof.f("react_resend_gap_s")
	var reach := prof.f("fleet_unpark_reach")
	var live := {}
	for rec: Squad in rest:
		var centre := _centre_of(_ships_of(rec))
		if str(rec.order.get("kind", "")) != OrderKinds.MOVE or not (rec.order.get("target") is Vector2i):
			continue
		if centre.distance_to(Vector2(rec.order["target"] as Vector2i)) > arrived:
			continue
		live[rec.id] = true
		if not _parked_since.has(rec.id):
			_parked_since[rec.id] = now
		if now - float(_parked_since[rec.id]) < wait or now - float(_sent.get(rec.id, -1000000.0)) < gap:
			continue
		var foe := view.nearest_seen_enemy_unit(centre, reach)
		if foe == null:
			continue
		AdmiralLog.of(world).expect(team, "ATTACK", "fleet.unpark", "sends squadron %d at an enemy unit in reach" % rec.id, "standing parked",
			"parked %d s with an enemy ship or minion in reach" % roundi(now - float(_parked_since[rec.id])))
		outbox.send(AdmiralOutbox.PRI_MOVE, "unpark", OrderKinds.ATTACK, {}, [rec.id], "unit", foe.uid)
		_sent[rec.id] = now
		_parked_since.erase(rec.id)
		live.erase(rec.id)
		_bump("unpark_orders")
		_bump("unpark_orders_ship" if foe is Ship else "unpark_orders_minion")
	for id: int in _parked_since.keys():
		if not live.has(id):
			_parked_since.erase(id)


## Is squadron `rec` on the job the unpark step gave it (a standing Attack order while the row fleet_unpark_s is above 0)? The attack
## point's Move leaves it alone until the target is gone and the stand-in turns the order into a Stop.
func _on_unpark_job(rec: Squad) -> bool:
	return prof.f("fleet_unpark_s") > 0.0 and str(rec.order.get("kind", "")) == OrderKinds.ATTACK


# --- help before being asked ------------------------------------------------------------------------------------------

## The need of each lane that has living pilots of ours: lane -> {"need": the enemy strength the team sees around them minus
## theirs (the size count), "centre": the mean place of the pilots there, "human": a human pilot is among them}. Only lanes
## with at least one living pilot appear.
func help_needs() -> Dictionary:
	var by_lane := {}
	for s: Ship in view.own_ships():
		var p := s.profile
		if p == null or p.is_crew or p.role == "admiral":
			continue
		var best := ""
		var best_d := LANE_BAND
		for lane: String in MapLayout.LANE_ORDER:
			var d := Util.dist_to_polyline(s.global_position, influence.lane_pts(lane))
			if d <= best_d:
				best_d = d
				best = lane
		if best == "":
			continue
		if not by_lane.has(best):
			by_lane[best] = {"own": 0.0, "sum": Vector2.ZERO, "n": 0, "human": false}
		var e: Dictionary = by_lane[best]
		e["own"] = float(e["own"]) + _power(s)
		e["sum"] = (e["sum"] as Vector2) + s.global_position
		e["n"] = int(e["n"]) + 1
		e["human"] = bool(e["human"]) or p.is_human
	var out := {}
	var r := prof.f("fleet_area_radius")
	for lane: String in MapLayout.LANE_ORDER:
		if not by_lane.has(lane):
			continue
		var e2: Dictionary = by_lane[lane]
		var centre: Vector2 = (e2["sum"] as Vector2) / float(int(e2["n"]))
		var enemy := float(view.enemy_near(centre, r)) / 1000.0
		out[lane] = {"need": enemy - float(e2["own"]), "centre": centre, "human": bool(e2["human"])}
	return out


## The lane that gets help from `needs` (help_needs()): among the lanes whose need is at least `edge`, the lane in worst
## need (a human pilot's lane wins a tie, then the lane order) when `pilot_first` is false, or the lane of a human pilot
## first (the lane order among them) when it is true. "" when no lane is in need.
static func help_lane(needs: Dictionary, edge: float, pilot_first: bool) -> String:
	var best := ""
	var best_need := -INF
	var best_human := false
	for lane: String in MapLayout.LANE_ORDER:
		if not needs.has(lane):
			continue
		var e: Dictionary = needs[lane]
		var need := float(e["need"])
		if need < edge:
			continue
		var human := bool(e["human"])
		var better := false
		if best == "":
			better = true
		elif pilot_first and human != best_human:
			better = human
		elif need > best_need + 0.000001:
			better = true
		elif absf(need - best_need) <= 0.000001 and human and not best_human:
			better = true
		if better:
			best = lane
			best_need = need
			best_human = human
	return best


## Help for outnumbered pilots (see the top): keep, pick or let go of the helper group, and send it. Returns the set of squad
## ids that are helping now (squad id -> true), which the attack order leaves alone.
@warning_ignore("integer_division")
func _help_think(free: Array[Squad], now: float, given: Dictionary = {}) -> Dictionary:
	# `given` is for a test: the needs to act on in place of the ones read from the pilots.
	var needs := given if not given.is_empty() else help_needs()
	var edge := prof.f("fleet_help_edge")
	var lane := help_lane(needs, edge, prof.on("fleet_help_pilot_first"))
	# A helper group already out stays while its lane's need is still half the edge.
	if not _help.is_empty():
		var held_lane := str(_help["lane"])
		if needs.has(held_lane) and float((needs[held_lane] as Dictionary)["need"]) >= edge * HELP_KEEP:
			lane = held_lane
		elif lane == "" or lane != held_lane:
			_help = {}
	if lane == "":
		_help = {}
		return {}
	var centre: Vector2 = (needs[lane] as Dictionary)["centre"]
	var turrets := view.enemy_turret_points()
	var dest := AdmiralPosture.clear_of_reach(centre, turrets, _minion_points(), prof.f("fleet_turret_reach"), MapLayout.mothership_pos(team))
	var free_ids := {}
	for rec: Squad in free:
		free_ids[rec.id] = true
	# Keep the helper ids that are still free; pick the nearest group when there are none.
	var ids: Array = []
	if not _help.is_empty():
		for id: int in _help["ids"]:
			if free_ids.has(id):
				ids.append(id)
	if ids.is_empty():
		var best_g := {}
		var best_d := INF
		for g: Dictionary in groups:
			var d := (g["centre"] as Vector2).distance_to(dest)
			if d < best_d:
				best_d = d
				best_g = g
		if best_g.is_empty():
			_help = {}
			return {}
		# The nearest group helps, but never more than half of the free squadrons (at least one): the push goes on.
		var near: Array = []
		for id: int in best_g["ids"]:
			var rec: Squad = world.squads.get(id) as Squad
			near.append([_centre_of(_ships_of(rec)).distance_to(dest), id])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var most := maxi(1, free.size() / 2)
		for i in mini(near.size(), most):
			ids.append(near[i][1])
		_bump("help_groups")
		_line(2, "Help coming to " + lane)
	_help = {"lane": lane, "ids": ids, "point": dest}
	_dispatch(AdmiralOutbox.PRI_HELP, "help", dest, ids, now,
		"sends %d squadrons to help our pilots on the %s lane" % [ids.size(), lane], "keeping them with the fleet",
		"our pilots there are outnumbered by %d points of ships the team sees" % roundi(float((needs[lane] as Dictionary)["need"])))
	var helping := {}
	for id: int in ids:
		helping[id] = true
	return helping


# --- the talk lines ----------------------------------------------------------------------------------------------------------

## The posture switched (called by _play): the line for the state now (retreat "Fall back to our turrets", attack "Going back
## in") goes on the think's candidates with rank 0, the first to be spoken. Returns the text.
func _talk_posture(_now: float) -> String:
	var text := "Fall back to our turrets" if posture.state == AdmiralPosture.RETREAT else "Going back in"
	_line(0, text)
	return text


## The goal lane's talk line: "Pushing <now>" when the goal lane `now` is not "" and differs from `before` (the first pick from
## "" counts), else "" (no line: a goal that went back to no lane says nothing).
static func goal_line(before: String, now: String) -> String:
	if now != "" and now != before:
		return "Pushing " + now
	return ""


## Write a change of the goal lane to the match log (an `f` line "goal" with the lane, OrderQueue.record_field), so that a
## replay of the computer Admirals (--admiral-replay), which runs no think, can set the same goal lane: the "lane" rally
## (Production.rally_point) reads it. Does nothing when no log is open.
func _note_goal() -> void:
	if world.orders != null:
		world.orders.record_field(team, "goal", influence.goal, "")


## A replay of the computer Admirals calls this for each `f` line "goal" of the match log, on the line's tick, in place of
## the think: the goal lane is set as the log has it. Nothing is decided here.
func replay_goal(lane: String) -> void:
	influence.goal = lane
	influence.goal_since = world.time


## Add a candidate line of rank `rank` (0 posture, 1 goal lane, 2 help) to the think now going.
func _line(rank: int, text: String) -> void:
	_lines.append([rank, text])


## Speak the candidate of the lowest rank of this think (the first one added on a tie), if there is one.
func _speak(now: float) -> void:
	var best: Array = []
	for line: Array in _lines:
		if best.is_empty() or int(line[0]) < int(best[0]):
			best = line
	if not best.is_empty():
		_say(str(best[1]), now)


## Put `text` on the team's own feed (AdmiralLog.feed: only while the profile's decision_log and log_feed are on) unless the last
## line was spoken less than fleet_talk_gap_s ago: then the line is dropped, not queued.
func _say(text: String, now: float) -> void:
	if now - _said_at < prof.f("fleet_talk_gap_s"):
		return
	_said_at = now
	_bump("talk_lines")
	AdmiralLog.feed(world, team, text)


# --- the orders --------------------------------------------------------------------------------------------------------------

## Send a Move of the squadrons `ids` to `dest` unless each already stands that order (within react_resend_dist) or was
## ordered less than react_resend_gap_s ago. One order names every squadron that needs it. `chose`, `over` and `why` are
## the decision log's words.
func _dispatch(priority: int, which: String, dest: Vector2, ids: Array, now: float, chose: String, over: String, why: String) -> void:
	var tolerance := prof.f("react_resend_dist")
	var gap := prof.f("react_resend_gap_s")
	var want := Order.point(dest)
	var need: Array = []
	for id: int in ids:
		var rec: Squad = world.squads.get(id) as Squad
		if rec == null:
			continue
		var cur: Dictionary = rec.order
		if str(cur.get("kind", "")) == OrderKinds.MOVE and cur.get("target") is Vector2i and Vector2(cur["target"] as Vector2i).distance_to(Vector2(want)) <= tolerance:
			continue
		if now - float(_sent.get(id, -1000000.0)) < gap:
			continue
		need.append(id)
	if need.is_empty():
		return
	need.sort()
	AdmiralLog.of(world).expect(team, "MOVE", "fleet." + which, chose, over, why)
	outbox.send(priority, which, OrderKinds.MOVE, {}, need, "point", want)
	for id: int in need:
		_sent[id] = now


# --- small helpers -----------------------------------------------------------------------------------------------------------

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


## One ship's strength, the size count: 1, 2, 3, 4 times 0.4 + 0.6 x its hull.
func _power(s: Ship) -> float:
	return float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())


## The places of our living minions, worked out once a think.
func _minion_points() -> Array:
	if _mp_think != thinks:
		_mp_think = thinks
		_mp.clear()
		for m in view.own_minions():
			_mp.append((m as Node2D).global_position)
	return _mp


## Add `n` to counter `name`.
func _bump(name: String, n: int = 1) -> void:
	counters[name] = int(counters.get(name, 0)) + n


## Everything the audit prints, as one Dictionary of numbers: the goal lane's changes, the posture's switches, the thinks, the
## orders the outbox sent and refused, the longest and the mean think in microseconds.
func stats() -> Dictionary:
	var out := counters.duplicate()
	out["thinks"] = thinks
	out["goal_changes"] = influence.changes
	out["posture_switches"] = posture.switches
	for k: String in outbox.stats():
		out["outbox_" + k] = int(outbox.stats()[k])
	out["think_us_max"] = think_us_max
	out["think_over_2ms"] = think_over_2ms
	out["decide_over_2ms"] = decide_over_2ms
	out["send_us_max"] = send_us_max
	out["send_over_2ms"] = send_over_2ms
	out["send_us_mean"] = roundi(float(send_us_sum) / float(maxi(thinks, 1)))
	out["think_us_mean"] = roundi(float(think_us_sum) / float(maxi(thinks, 1)))
	return out
