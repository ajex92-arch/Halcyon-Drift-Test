extends Node
## WHAT THIS IS: the check of the computer Admiral's fleet layer (RT8 build 8a: scripts/ai/admiral_fleet.gd,
## admiral_posture.gd, lane_influence.gd and the outbox stub admiral_outbox.gd). Each case sets the scene by hand, lets the
## layer think by hand and reads the squadrons' standing orders and the outbox's counters.
##   - POSTURE: the share own / (own + enemy); the state falls back below 0.35 and goes back in above 0.60 (the edges 0.35
##     and 0.60 themselves keep the state); no switch for 10 s after the last switch, counted from the switch and not from
##     each verdict, through the state rule alone and through the part's own think.
##   - GOAL LANE: held 60 s (a choice 59 s old is kept, one 60 s old may change), a base alarm changes it at once to the
##     defend point's lane, and with the alarm over it changes at most once in the next 60 s however the scores move.
##   - TURRET REACH: no attack point inside an enemy lane turret's reach unless our minions are within reach of that turret.
##   - THE MIDDLE: past the lane's middle (0.5) the fleet goes only with at least 2 squadrons AND at least half of the attacking
##     strength within the together distance of one squadron's centre (a third squadron far away holding most of the strength
##     blocks it), else the point stays at the middle.
##   - THE OUTBOX (RT8 build 8b): an order decided at tick T is carried out at T+18, never earlier; in a scripted alarm burst (RT5's
##     12 Moves and the fleet's orders in four thinks) no 300 ticks hold more than 20 seat orders, the lowest priority is dropped
##     first, and the dropped squadrons are ordered again by the very next think; the alarm path through AdmiralAI's own think
##     (RT5 calls the near squadrons, the fleet orders nobody) and the alarm's end (RT5's rally Moves are not given a second order).
##   - THE STUCK COUNTER'S TEST (RT8 build 8c): the audit's is_parked says yes to a squadron standing on its Move's target and no to an
##     empty order and to one 3,000 units from its target.
##   - THE GOAL LANE IN THE LOG (RT8 build 8d): a change of the goal lane is written as an `f` line "goal" (and a second think inside the
##     hold writes none); read back and played through OrderQueue.replay_ai it sets the goal lane of a fleet that never thought, at the
##     logged tick, so the "lane" rally reads it; a decided record (a d word) is filed under its decision tick and queued, once.
##   - THE FLEET RULES: helpers out of our strength in the fight area; a standing order given by something else holds the squadron
##     from the fleet's orders; the waypoint and the "lane" rally follow the goal lane (the top lane with the switch off); the talk
##     lines (one every 10 s at most, the lowest rank first, none with log_feed off or during the alarm).
##   - HELP: the lane in worst need first and a human pilot's lane wins a tie (the recommended rule), or a human pilot's lane first
##     (the other rule); no lane under the edge gets help.
##   - THE FLEET: free squadrons get one Move to the goal lane's attack point (one order for all of them, none again inside the
##     resend gap); while the base alarm is on nothing is ordered; a squadron RT5's reaction called home or sent to fill in is
##     never ordered; in the retreat posture every group goes to the nearest own turret or the base, and the lockout keeps the
##     state for 10 s and then lets it go back in; no order is refused.
##
## HOW IT WORKS: setup() makes the world quiet; the cases all run in the first physics tick (the clock, the defend call and the
## squadrons are written by hand and put back). It prints a FAIL line for each failed check and
## "admiral_fleet_check: N failures (M checks)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --test=admiral_fleet_check
##
## WHO USES IT: main.gd loads it for --test=admiral_fleet_check (it calls setup()).

## The defend point the alarm cases use.
const P := Vector2(20000.0, 15000.0)

## The running match (set by setup()).
var world: World
## How many checks failed, and how many were made.
var fails := 0
var checks := 0  # how many checks were made
## True once the cases have run.
var _ran := false
## The lines heard on the team feed while _listen(true) is on: [text, tone, team].
var _heard: Array = []
## The profile switches decision_log and log_feed of team 0's Admiral before _listen(true) turned them on.
var _saved_feed: Array = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF


## Run every case in the first physics tick, print the result and quit.
func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	var saved_time := world.time
	_posture_cases()
	_goal_cases()
	_reach_cases()
	_middle_cases()
	_help_cases()
	_fleet_cases()
	_outbox_cases()
	_rules_cases()
	_lane_cases()
	_talk_cases()
	_stuck_cases()
	_near_cases()
	_unpark_cases()
	_unpark_path_cases()
	_dword_cases()
	_goal_replay_cases()
	_reset(0.0, 0.0)
	world.time = saved_time
	print("admiral_fleet_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -------------------------------------------------------------------------

## Count one check; print a FAIL line when it did not hold.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL %s %s" % [name, detail])


## Start (true) or stop (false) listening to the team feed: the lines go to _heard, and team 0's Admiral has its decision log
## and log feed switched on while listening (put back afterwards). Starting empties _heard.
func _listen(on: bool) -> void:
	var profile := _ai().profile
	if on:
		_heard.clear()
		_saved_feed = [profile.raw("decision_log"), profile.raw("log_feed")]
		profile.set_value("decision_log", 1)
		profile.set_value("log_feed", 1)
		if not Events.feed.is_connected(_on_feed):
			Events.feed.connect(_on_feed)
	else:
		if Events.feed.is_connected(_on_feed):
			Events.feed.disconnect(_on_feed)
		if not _saved_feed.is_empty():
			profile.set_value("decision_log", int(_saved_feed[0]))
			profile.set_value("log_feed", int(_saved_feed[1]))
			_saved_feed = []


## A line on the team feed (while listening).
func _on_feed(text: String, tone: String, tm: int) -> void:
	_heard.append([text, tone, tm])


## Team 0's state.
func _ts() -> TeamState:
	return world.teams[0]


## Team 0's yard.
func _prod() -> Production:
	return world.teams[0].production


## Team 0's Admiral.
func _ai() -> AdmiralAI:
	return world.admiral_ai[0]


## Team 0 back to an empty yard, no squadrons, no defend call, no siege, the clock at `at`, `money` credits.
func _reset(money: float, at: float = 500.0) -> void:
	var ts := _ts()
	var prod := ts.production
	prod.items.clear()
	prod.repeat.clear()
	prod.capacity.reserved = 0
	prod._cap_blocked = false
	ts.research.clear()
	ts.building.clear()
	ts.drone_queue.clear()
	ts.treasury = money
	for id: int in world.squads.keys():
		if (world.squads[id] as Squad).team == 0:
			world.squads.erase(id)
	ts.defend_point = Vector2.INF
	ts.defend_until = 0.0
	ts.siege_lane = ""
	ts.siege_phase = ""
	Game.unlock_everything = false
	ts.admiral = "ai"
	world.time = at


## The profile of a standard Admiral with the fleet layer on and the switches `on` turned on too. The outbox's order delay
## is `delay` ticks (0 unless a case passes one, so a case may read a squadron's order straight after a think).
func _prof(on: Array = [], delay: int = 0) -> AdmiralProfile:
	var p := AdmiralProfile.make("standard", 0)
	p.set_value("fleet_play", 1)
	p.set_value("fleet_order_delay_ticks", delay * 1000)
	for key: String in on:
		p.set_value(key, 1)
	return p


## A bought squad of `count` ships of `hull` at once (null when the fleet has no room).
func _squad(hull: String, count: int) -> Squad:
	var it := _prod().spawn_now(hull, count)
	if it.is_empty():
		return null
	return world.squads.get(int(it["squad"])) as Squad


## Put every ship of `rec` at `p` (spread a little so they do not stack).
func _place(rec: Squad, p: Vector2) -> void:
	var i := 0
	for uid: int in rec.member_uids:
		var s: Variant = world.by_uid.get(uid)
		if s != null and is_instance_valid(s):
			(s as Ship).global_position = p + Vector2(float(i) * 60.0, 0.0)
		i += 1


## Switch the base alarm on or off at point.
func _alarm(point: Vector2, on: bool) -> void:
	var ts := _ts()
	ts.defend_point = point
	ts.defend_until = world.time + 12.0 if on else 0.0


## The standing Move target of `rec` as a Vector2, or Vector2.INF when its order is not a Move.
func _target(rec: Squad) -> Vector2:
	if str(rec.order.get("kind", "")) != OrderKinds.MOVE:
		return Vector2.INF
	return Vector2(rec.order["target"] as Vector2i)


## How many orders fleet's outbox has carried out.
func _orders_ok(fleet: AdmiralFleet) -> int:
	return int(fleet.outbox.stats().get("ok", 0))


## The ticks of team 0's Admiral seat records (order_done or order_refused) from running index `from` on.
func _seat_ticks(from: int) -> Array:
	var out: Array = []
	for rec: Dictionary in world.events_rts.read_from(0, from):
		var k := str(rec["kind"])
		if (k == "order_done" or k == "order_refused") and int((rec["data"] as Dictionary).get("seat", -1)) == Rules.ADMIRAL_SEAT:
			out.append(int(rec["tick"]))
	return out


## The most of `ticks` (record ticks) that fall inside any 300 ticks.
func _most_in_300(ticks: Array) -> int:
	var best := 0
	for a: int in ticks:
		var n := 0
		for b: int in ticks:
			if b >= a and b < a + 300:
				n += 1
		best = maxi(best, n)
	return best


## `count` bought squads of one fighter each, placed at `p` (3,000 apart); the array is short when the fleet has no room.
func _singles(count: int, p: Vector2) -> Array:
	var out: Array = []
	for i in count:
		var rec := _squad("fighter", 1)
		if rec == null:
			break
		_place(rec, p + Vector2(float(i) * 3000.0, 0.0))
		out.append(rec)
	return out


# --- posture -------------------------------------------------------------------------

## The posture's thresholds, lockout and share.
func _posture_cases() -> void:
	var A := AdmiralPosture.ATTACK
	var R := AdmiralPosture.RETREAT
	_check("posture: 1 against 3 is a share of 0.25, and nothing against nothing is 1", is_equal_approx(AdmiralPosture.ratio_of(1.0, 3.0), 0.25) and AdmiralPosture.ratio_of(0.0, 0.0) == 1.0)
	_check("posture: below 0.35 the fleet falls back", AdmiralPosture.next_state(A, 0.34, -1000.0, 100.0, 0.35, 0.60, 10.0) == R)
	_check("posture: at exactly 0.35 it does not", AdmiralPosture.next_state(A, 0.35, -1000.0, 100.0, 0.35, 0.60, 10.0) == A)
	_check("posture: between the lines it keeps what it does", AdmiralPosture.next_state(A, 0.5, -1000.0, 100.0, 0.35, 0.60, 10.0) == A and AdmiralPosture.next_state(R, 0.5, -1000.0, 100.0, 0.35, 0.60, 10.0) == R)
	_check("posture: above 0.60 it goes back in", AdmiralPosture.next_state(R, 0.61, -1000.0, 100.0, 0.35, 0.60, 10.0) == A)
	_check("posture: at exactly 0.60 it does not", AdmiralPosture.next_state(R, 0.60, -1000.0, 100.0, 0.35, 0.60, 10.0) == R)
	_check("posture: a verdict 9.9 s after the switch is ignored", AdmiralPosture.next_state(A, 0.1, 100.0, 109.9, 0.35, 0.60, 10.0) == A)
	_check("posture: one 10 s after the switch counts", AdmiralPosture.next_state(A, 0.1, 100.0, 110.0, 0.35, 0.60, 10.0) == R)
	# Through the part's own think: the lockout is counted from the switch, not from each verdict.
	var po := AdmiralPosture.new(world, 0, _ai().lanes, _prof())
	_check("posture: a new posture starts in attack", po.state == A and po.switches == 0)
	po.think(100.0, 1.0, 3.0)
	_check("posture: a share of 0.25 sends it back at once (the first switch)", po.state == R and po.switches == 1 and is_equal_approx(po.ratio, 0.25))
	po.think(103.0, 9.0, 1.0)
	po.think(106.0, 9.0, 1.0)
	po.think(109.9, 9.0, 1.0)
	_check("posture: good verdicts at 3, 6 and 9.9 s change nothing (the lockout runs from the switch)", po.state == R and po.switches == 1)
	po.think(110.0, 9.0, 1.0)
	_check("posture: the next good verdict 10 s after the switch sends it in", po.state == A and po.switches == 2)
	po.think(112.0, 1.0, 9.0)
	_check("posture: a bad verdict 2 s after that switch is ignored", po.state == A and po.switches == 2)
	po.think(120.0, 1.0, 9.0)
	_check("posture: and counts 10 s after it", po.state == R and po.switches == 3)


# --- goal lane -------------------------------------------------------------------------

## The goal lane's hold and the alarm's change.
func _goal_cases() -> void:
	var sc := {"top": 1.0, "mid": 5.0, "bot": 2.0}
	_check("goal: with no goal yet the best lane is taken", LaneInfluence.pick(sc, "", -1.0, 100.0, 60.0, "") == "mid")
	_check("goal: a goal 59 s old is kept", LaneInfluence.pick(sc, "top", 100.0, 159.0, 60.0, "") == "top")
	_check("goal: one 60 s old may change", LaneInfluence.pick(sc, "top", 100.0, 160.0, 60.0, "") == "mid")
	_check("goal: a base alarm changes it at once, to the alarm's lane", LaneInfluence.pick(sc, "top", 100.0, 101.0, 60.0, "bot") == "bot")
	var ai := _ai()
	var inf := LaneInfluence.new(world, 0, ai.lanes, _prof())
	inf.think(200.0, false, Vector2.INF)
	_check("goal: the first think chooses a goal lane and counts no change", inf.goal != "" and inf.changes == 0, inf.goal)
	_check("goal: lane_of_point finds the lane a point is on", inf.lane_of_point(ai.lanes.lane_point("bot", 0.3)) == "bot" and inf.lane_of_point(ai.lanes.lane_point("top", 0.3)) == "top")
	inf.goal = "top"
	inf.goal_since = 300.0
	inf.think(330.0, false, Vector2.INF)
	_check("goal: 30 s after a choice the goal lane stays", inf.goal == "top" and inf.changes == 0)
	var mid_point := ai.lanes.lane_point("mid", 0.2)
	inf.think(330.0, true, mid_point)
	_check("goal: with the base alarm on and its point on the mid lane the goal is mid at once", inf.goal == "mid" and inf.changes == 1, inf.goal)
	inf.think(331.0, true, mid_point)
	_check("goal: and stays mid while the same alarm lasts", inf.goal == "mid" and inf.changes == 1)
	var before := inf.changes
	for second in range(332, 390):
		inf.think(float(second), false, Vector2.INF)
	_check("goal: with the alarm over it holds 60 s from the change (no change before 390)", inf.goal == "mid" and inf.changes == before, "%s %d" % [inf.goal, inf.changes])
	for second in range(390, 450):
		inf.think(float(second), false, Vector2.INF)
	_check("goal: and afterwards changes at most once in the next 60 s", inf.changes - before <= 1, str(inf.changes - before))


# --- turret reach -------------------------------------------------------------------------

## Turret reach and the attack point.
func _reach_cases() -> void:
	var lanes := _ai().lanes
	var po := AdmiralPosture.new(world, 0, lanes, _prof())
	var reach := 2500.0
	var tp := lanes.lane_point("mid", 0.62)
	_check("reach: a point 1,000 from a turret with no minion is in its reach", AdmiralPosture.in_reach(tp + Vector2(1000.0, 0.0), [tp], [], reach))
	_check("reach: with a minion of ours at the turret it is not", not AdmiralPosture.in_reach(tp + Vector2(1000.0, 0.0), [tp], [tp + Vector2(500.0, 0.0)], reach))
	_check("reach: a minion far from the turret does not cover it", AdmiralPosture.in_reach(tp + Vector2(1000.0, 0.0), [tp], [tp + Vector2(9000.0, 0.0)], reach))
	_check("reach: a point 3,000 from the turret is clear", not AdmiralPosture.in_reach(tp + Vector2(3000.0, 0.0), [tp], [], reach))
	var pushed := AdmiralPosture.clear_of_reach(tp + Vector2(100.0, 0.0), [tp], [], reach, Vector2.ZERO)
	_check("reach: clear_of_reach moves a point out of the reach", not AdmiralPosture.in_reach(pushed, [tp], [], reach) and pushed.distance_to(tp) > reach, str(pushed.distance_to(tp)))
	_check("reach: a covered or clear point is left where it is", AdmiralPosture.clear_of_reach(tp + Vector2(100.0, 0.0), [tp], [tp], reach, Vector2.ZERO) == tp + Vector2(100.0, 0.0))
	# The attack point: the front at 0.59 plus the step 0.03 is exactly the turret's place.
	var ap := po.attack_point("mid", 0.59, true, [tp], [])
	_check("reach: the attack point is out of the turret's reach with no minion there", ap.distance_to(tp) >= reach and not AdmiralPosture.in_reach(ap, [tp], [], reach), str(ap.distance_to(tp)))
	_check("reach: ... and still on the lane", Util.dist_to_polyline(ap, MapLayout.lane_points("mid", 0)) < 30.0)
	var ap2 := po.attack_point("mid", 0.59, true, [tp], [tp + Vector2(300.0, 0.0)])
	_check("reach: with our minions at the turret the point is the plain one (front plus the step)", ap2.is_equal_approx(lanes.lane_point("mid", 0.62)), str(ap2))


# --- the lane's middle -------------------------------------------------------------------------

## The lane's middle and two squadrons together.
func _middle_cases() -> void:
	var lanes := _ai().lanes
	var po := AdmiralPosture.new(world, 0, lanes, _prof())
	var a := po.attack_point("mid", 0.55, false, [], [])
	_check("middle: one squadron alone stops at the lane's middle", a.is_equal_approx(lanes.lane_point("mid", 0.5)), str(a))
	var b := po.attack_point("mid", 0.55, true, [], [])
	_check("middle: two together go beyond it (front 0.55 plus the step 0.03)", b.is_equal_approx(lanes.lane_point("mid", 0.58)), str(b))
	var c := po.attack_point("mid", 0.40, false, [], [])
	_check("middle: short of the middle nobody is held", c.is_equal_approx(lanes.lane_point("mid", 0.43)), str(c))
	_check("middle: two squadrons 3,000 apart are together, 5,000 apart are not, one alone is not",
		AdmiralPosture.gathered([Vector2(0.0, 0.0), Vector2(3000.0, 0.0)], [1.0, 1.0], 4000.0) and not AdmiralPosture.gathered([Vector2(0.0, 0.0), Vector2(5000.0, 0.0)], [1.0, 1.0], 4000.0) and not AdmiralPosture.gathered([Vector2(0.0, 0.0)], [1.0], 4000.0))
	# The rule: at least 2 squadrons AND at least half of the attacking strength within the distance of one squadron's centre.
	var far := Vector2(30000.0, 0.0)
	_check("middle: two squadrons side by side with a third far away holding most of the strength do not pass",
		not AdmiralPosture.gathered([Vector2(0.0, 0.0), Vector2(3000.0, 0.0), far], [1.0, 1.0, 8.0], 4000.0))
	_check("middle: the same two with a third far away holding less than their half pass",
		AdmiralPosture.gathered([Vector2(0.0, 0.0), Vector2(3000.0, 0.0), far], [3.0, 3.0, 2.0], 4000.0))
	_check("middle: exactly half of the strength passes, a little under half does not",
		AdmiralPosture.gathered([Vector2(0.0, 0.0), Vector2(3000.0, 0.0), far], [2.0, 2.0, 4.0], 4000.0) and not AdmiralPosture.gathered([Vector2(0.0, 0.0), Vector2(3000.0, 0.0), far], [2.0, 2.0, 4.1], 4000.0))
	_check("middle: the centre may be any squadron (the first that passes decides): the lone big one is no centre, the pair behind it is",
		AdmiralPosture.gathered([far, Vector2(0.0, 0.0), Vector2(3000.0, 0.0)], [1.0, 3.0, 3.0], 4000.0))
	var stretched := [Vector2(0.0, 0.0), Vector2(3500.0, 0.0), Vector2(7000.0, 0.0)]
	_check("middle: three in a row, each within the distance of the middle one only, pass when the middle one is the centre (3 of 3)",
		AdmiralPosture.gathered(stretched, [1.0, 1.0, 1.0], 4000.0))
	_check("middle: ... but not with a distance of 3,000 (each stands alone)", not AdmiralPosture.gathered(stretched, [1.0, 1.0, 1.0], 3000.0))


# --- help -------------------------------------------------------------------------

## Which lane gets help.
func _help_cases() -> void:
	var needs := {"top": {"need": 3.0, "human": false}, "mid": {"need": 5.0, "human": false}, "bot": {"need": 0.5, "human": false}}
	_check("help: the lane in worst need goes first (an edge of 1; the bot lane is under it)", AdmiralFleet.help_lane(needs, 1.0, false) == "mid")
	var tie := {"top": {"need": 4.0, "human": true}, "mid": {"need": 4.0, "human": false}}
	_check("help: a tie goes to the human pilot's lane (top)", AdmiralFleet.help_lane(tie, 1.0, false) == "top")
	var tie2 := {"top": {"need": 4.0, "human": false}, "mid": {"need": 4.0, "human": true}}
	_check("help: ... and the same tie with the human on mid goes to mid", AdmiralFleet.help_lane(tie2, 1.0, false) == "mid")
	var worse := {"top": {"need": 2.0, "human": true}, "mid": {"need": 5.0, "human": false}}
	_check("help: a human pilot's lane in less need does not jump the queue (worst first)", AdmiralFleet.help_lane(worse, 1.0, false) == "mid")
	_check("help: with the other rule the human pilot's lane goes first", AdmiralFleet.help_lane(worse, 1.0, true) == "top")
	var calm_human := {"top": {"need": 0.5, "human": true}, "mid": {"need": 5.0, "human": false}}
	_check("help: with the other rule a human pilot under the edge does not take the help", AdmiralFleet.help_lane(calm_human, 1.0, true) == "mid")
	var calm := {"top": {"need": 0.5, "human": false}, "mid": {"need": -2.0, "human": true}}
	_check("help: no lane at or over the edge gets no help", AdmiralFleet.help_lane(calm, 1.0, false) == "")
	_check("help: an empty list gets no help", AdmiralFleet.help_lane({}, 1.0, false) == "")
	_check("help: the rule's switch is 0 (worst need first) in the standard profile", not AdmiralProfile.make("standard", 0).on("fleet_help_pilot_first"))


# --- the fleet -------------------------------------------------------------------------

## The fleet on real squadrons: orders, alarm, called, filler, retreat, lockout, help.
func _fleet_cases() -> void:
	_reset(9000.0, 500.0)
	var ai := _ai()
	var ts := _ts()
	var s1 := _squad("fighter", 3)
	var s2 := _squad("fighter", 3)
	var s3 := _squad("fighter", 3)
	_check("fleet: three squadrons were made", s1 != null and s2 != null and s3 != null)
	if s1 == null or s2 == null or s3 == null:
		return
	_place(s1, P)
	_place(s2, P + Vector2(500.0, 0.0))
	_place(s3, Vector2(36000.0, 2000.0))
	var react := AdmiralReactions.new(world, 0, ai.lanes, ai.field, _prof(["react_under_attack"]))
	var fleet := AdmiralFleet.new(world, 0, ai.lanes, react, _prof())
	# A quiet think: one Move for all three, on the goal lane.
	fleet.think(ts)
	var t1 := _target(s1)
	_check("fleet: a quiet think gives every free squadron the same Move", t1 != Vector2.INF and _target(s2) == t1 and _target(s3) == t1, str([_target(s1), _target(s2), _target(s3)]))
	_check("fleet: ... as one order", _orders_ok(fleet) == 1, str(fleet.outbox.stats()))
	_check("fleet: ... on the goal lane", t1 != Vector2.INF and Util.dist_to_polyline(t1, MapLayout.lane_points(fleet.influence.goal, 0)) < 30.0, fleet.influence.goal)
	_check("fleet: ... with no order refused", int(fleet.outbox.stats().get("fail", 0)) == 0 and int(fleet.counters.get("refused", 0)) == 0)
	var fst := fleet.stats()
	_check("fleet: stats() times end_think: send_over_2ms (at most the thinks) and send_us_mean are there", fst.has("send_over_2ms") and fst.has("send_us_mean") and int(fst["send_over_2ms"]) >= 0 and int(fst["send_over_2ms"]) <= int(fst["thinks"]) and int(fst["send_us_mean"]) >= 0, str(fst))
	_check("fleet: with fleet_play on the fleet is in the attack posture at the start", fleet.posture.state == AdmiralPosture.ATTACK)
	world.time = 501.0
	fleet.think(ts)
	_check("fleet: a second think a second later orders nothing again", _orders_ok(fleet) == 1)
	# The alarm: RT5 calls the two near squadrons home; this layer orders nobody.
	world.time = 502.0
	_alarm(P, true)
	react.think(ts)
	_check("alarm: RT5's reaction called the two squadrons near the defend point", react._called.has(s1.id) and react._called.has(s2.id) and not react._called.has(s3.id), str(react._called.keys()))
	var o1 := s1.order.duplicate()
	var o2 := s2.order.duplicate()
	var o3 := s3.order.duplicate()
	var ok_before := _orders_ok(fleet)
	fleet.think(ts)
	_check("alarm: while the alarm is on this layer sends no order and changes no squadron", _orders_ok(fleet) == ok_before and s1.order == o1 and s2.order == o2 and s3.order == o3)
	_check("alarm: ... and counts the think as an alarm think", int(fleet.counters.get("alarm_thinks", 0)) == 1)
	# The alarm over but the squadrons still called: never ordered.
	world.time = 520.0
	_alarm(P, false)
	s3.order = {}
	fleet.think(ts)
	_check("called: a squadron RT5 called home is not ordered (the others are)", s1.order == o1 and s2.order == o2 and _target(s3) != Vector2.INF, str([s1.order == o1, s2.order == o2, _target(s3)]))
	_check("called: free_squads leaves the called ones out", fleet.free_squads().size() == 1 and fleet.free_squads()[0].id == s3.id)
	# A filler: not ordered either.
	react._called.clear()
	react._filler_id = s2.id
	world.time = 530.0
	s1.order = {}
	s3.order = {}
	o2 = s2.order.duplicate()
	fleet.think(ts)
	_check("filler: the squadron RT5 sent to fill in is not ordered (the others are)", s2.order == o2 and _target(s1) != Vector2.INF and _target(s3) != Vector2.INF)
	react._filler_id = 0
	# The retreat posture, and the lockout. From here the team feed is listened to (the Admiral's profile has its decision log and
	# log feed on): only the switch back in speaks, once.
	_listen(true)
	world.time = 540.0
	for rec: Squad in [s1, s2, s3]:
		rec.order = {}
	fleet.posture.state = AdmiralPosture.RETREAT
	fleet.posture.switched_at = world.time - 1.0
	var switches := fleet.posture.switches
	fleet.think(ts)
	_check("retreat: 1 s after a switch the lockout keeps the retreat although our side is far the stronger", fleet.posture.state == AdmiralPosture.RETREAT and fleet.posture.switches == switches, str(fleet.posture.ratio))
	var all_back := not fleet.groups.is_empty()
	for g: Dictionary in fleet.groups:
		var want := Order.point(fleet.posture.fall_back_point(g["centre"]))
		for id: int in g["ids"]:
			if _target(world.squads[id]) != Vector2(want):
				all_back = false
	_check("retreat: every group goes to the nearest turret of ours (or the base)", all_back, str(fleet.groups))
	_check("retreat: the fall-back point is one of our turrets", fleet.posture.fall_back_point(P) in fleet.view.own_turret_points() or fleet.posture.fall_back_point(P) == MapLayout.mothership_pos(0))
	world.time = 551.0
	for rec: Squad in [s1, s2, s3]:
		rec.order = {}
	fleet.think(ts)
	_check("retreat: 11 s after the switch the good share sends the fleet back in", fleet.posture.state == AdmiralPosture.ATTACK and fleet.posture.switches == switches + 1, "%s %d" % [fleet.posture.state, fleet.posture.switches])
	_check("retreat: ... with a Move to the attack point again", _target(s1) != Vector2.INF and Util.dist_to_polyline(_target(s1), MapLayout.lane_points(fleet.influence.goal, 0)) < 30.0)
	_check("talk: the whole retreat-to-attack scene gives exactly one line, \"Going back in\", on team 0's own feed", _heard.size() == 1 and str(_heard[0][0]) == "Going back in" and str(_heard[0][1]) == "team" and int(_heard[0][2]) == 0, str(_heard))
	_listen(false)
	_check("fleet: no order of the whole case was refused", int(fleet.outbox.stats().get("fail", 0)) == 0)
	# The help hook: a given need sends the nearest group, at most half of the free squadrons.
	world.time = 600.0
	for rec: Squad in [s1, s2, s3]:
		rec.order = {}
	var lane_pt := ai.lanes.lane_point("bot", 0.4)
	var given := {"bot": {"need": 4.0, "centre": lane_pt, "human": false}}
	# The orders go out when the think ends (the outbox's waiting list), so the hook is called between its two brackets.
	fleet.outbox.begin_think()
	var helping := fleet._help_think(fleet.free_squads(), world.time, given)
	fleet.outbox.end_think()
	_check("help: a lane in need sends a group, at most half of the free squadrons", helping.size() == 1, str(helping))
	var helper: Squad = null
	for id: int in helping:
		helper = world.squads[id]
	_check("help: ... with a Move to the pilots' lane", helper != null and _target(helper) != Vector2.INF and _target(helper).distance_to(lane_pt) < 100.0, str(_target(helper) if helper != null else "none"))
	var held_target := _target(helper) if helper != null else Vector2.INF
	world.time = 610.0
	fleet.outbox.begin_think()
	fleet._help_think(fleet.free_squads(), world.time, {"bot": {"need": 0.6, "centre": lane_pt, "human": false}})
	fleet.outbox.end_think()
	_check("help: the helper stays while the need is over half the edge", not fleet._help.is_empty() and helper != null and _target(helper) == held_target)
	fleet.outbox.begin_think()
	fleet._help_think(fleet.free_squads(), world.time, {"bot": {"need": 0.2, "centre": lane_pt, "human": false}})
	fleet.outbox.end_think()
	_check("help: and is let go under it", fleet._help.is_empty())
	_reset(0.0, 0.0)


# --- the outbox: the delay, the cap and the alarm path ---------------------------------------------------------------------

## The outbox's delay (a), the scripted alarm burst under the cap (b), the dropped squadrons sent again (b2) and the alarm
## path through AdmiralAI's own think with RT5's rally Moves left alone (c).
func _outbox_cases() -> void:
	var ai := _ai()
	var ts := _ts()
	var saved_tick := world.tick_count
	var base := 100000
	var orders := world.orders
	# (a) An order decided at tick T is applied at T + 18 and never earlier.
	_reset(9000.0, 500.0)
	var group := _singles(3, Vector2(30000.0, 6000.0))
	_check("outbox: three single squadrons were made", group.size() == 3)
	if group.size() < 3:
		return
	var a: Squad = group[0]
	var b: Squad = group[1]
	var c: Squad = group[2]
	orders.queue.clear()
	world.tick_count = base
	var out1 := AdmiralOutbox.new(world, 0, _prof([], 18))
	var dest := ai.lanes.lane_point("mid", 0.3)
	out1.begin_think()
	var sent := out1.send(AdmiralOutbox.PRI_ATTACK, "attack", OrderKinds.MOVE, {}, [a.id], "point", Order.point(dest))
	_check("delay: send puts the order on the waiting list and returns \"\", and nothing is carried out yet", sent == "" and a.order.is_empty())
	var dropped := out1.end_think()
	_check("delay: end_think sends it through the delayed door: not carried out yet, none dropped", dropped.is_empty() and a.order.is_empty() and out1.last_sent_ids == [a.id], str([a.order, out1.last_sent_ids]))
	world.tick_count = base + 17
	orders.run_due()
	_check("delay: at tick T+17 the squadron's standing order is unchanged", a.order.is_empty())
	world.tick_count = base + 18
	orders.run_due()
	_check("delay: at tick T+18 it is set, with the apply tick T+18", _target(a) == Vector2(Order.point(dest)) and int(a.order["tick"]) == base + 18, str(a.order))
	_check("delay: the outbox remembers the apply tick of its order", out1.own_ticks(a.id) == [base + 18] and out1.own_ticks(b.id).is_empty())
	orders.queue.clear()
	# (a2) The delay stays below the think gap: a gap of 0.1 s is 6 ticks, so the 18-tick delay is cut to 5; a gap of 1 s leaves 18.
	var gaps := {100: [1, 5], 1000: [18, 18]}
	for gap_th: int in gaps:
		var gp := _prof([], 18)
		gp.set_value("think_gap_s", gap_th)
		var og := AdmiralOutbox.new(world, 0, gp)
		world.tick_count = base + 300
		og.begin_think()
		og.send(AdmiralOutbox.PRI_ATTACK, "gap", OrderKinds.MOVE, {}, [b.id], "point", Order.point(dest))
		og.end_think()
		var span := -1
		if not orders.queue.is_empty():
			var qo: Dictionary = orders.queue.back()
			span = int(qo["apply_tick"]) - int(qo["tick"])
		var want: Array = gaps[gap_th]
		_check("delay: with think_gap_s %d and a delay of 18 the order lands %d to %d ticks on (%d)" % [gap_th, want[0], want[1], span], span >= int(want[0]) and span <= int(want[1]) and (gap_th != 1000 or span == 18))
		orders.queue.clear()
	_check("delay: delay_below_gap says no to 18 ticks against 0.1 s and yes against 1 s", not AdmiralOutbox.delay_below_gap(18000, 100) and AdmiralOutbox.delay_below_gap(18000, 1000))
	# (b) The scripted burst: RT5's 12 Moves and the fleet's orders in three thinks, all inside 100 ticks.
	_alarm(P, true)
	var react := AdmiralReactions.new(world, 0, ai.lanes, ai.field, _prof(["react_under_attack"]))
	var ob := AdmiralOutbox.new(world, 0, _prof([], 18))
	var from := world.events_rts.next_index(0)
	var squads: Array = [a, b, c]
	var offered := 0
	var t0 := base + 1000
	world.tick_count = t0
	var plan := {}
	for i in range(0, 40, 5):
		plan[i] = ["rt5", 1]  # eight of RT5's Moves, one every five ticks
	plan[40] = ["think", AdmiralOutbox.PRI_RETREAT, 6]
	for i in range(45, 65, 5):
		plan[i] = ["rt5", 1]  # four more
	plan[70] = ["think2"]
	plan[100] = ["think", AdmiralOutbox.PRI_ATTACK, 10]
	var last_dropped: Array = []
	var n := 0
	for k in range(0, 101):
		world.tick_count = t0 + k
		orders.run_due()
		if not plan.has(k):
			continue
		var step: Array = plan[k]
		match str(step[0]):
			"rt5":
				var sq: Squad = squads[offered % 3]
				var pt := ai.lanes.lane_point("top", 0.20 + 0.01 * float(offered))
				_check("burst: RT5's Move %d was carried out" % offered, react.send("attack", OrderKinds.MOVE, {}, [sq.id], "point", Order.point(pt)) == "")
				offered += 1
			"think":
				ob.begin_think()
				for i in int(step[2]):
					ob.send(int(step[1]), "burst", OrderKinds.MOVE, {}, [(squads[(n + i) % 3] as Squad).id], "point", Order.point(ai.lanes.lane_point("bot", 0.2 + 0.01 * float(n + i))))
				n += int(step[2])
				offered += int(step[2])
				last_dropped = ob.end_think()
			"think2":
				# Five attack orders called first and five help orders after them: the help ones go first.
				ob.begin_think()
				for i in 5:
					ob.send(AdmiralOutbox.PRI_ATTACK, "burst", OrderKinds.MOVE, {}, [(squads[i % 3] as Squad).id], "point", Order.point(ai.lanes.lane_point("mid", 0.2 + 0.01 * float(i))))
				for i in 5:
					ob.send(AdmiralOutbox.PRI_HELP, "burst", OrderKinds.MOVE, {}, [(squads[i % 3] as Squad).id], "point", Order.point(ai.lanes.lane_point("mid", 0.5 + 0.01 * float(i))))
				offered += 10
				ob.end_think()
	orders.run_due()
	var st := ob.stats()
	var ticks := _seat_ticks(from)
	_check("burst: at least 30 seat orders were offered inside the 100 ticks (RT5's 12 and the fleet's)", offered >= 30, str(offered))
	_check("burst: no 300 ticks hold more than 20 seat orders (the stream's records)", _most_in_300(ticks) <= 20, "%d of %d" % [_most_in_300(ticks), ticks.size()])
	_check("burst: the lowest priority was dropped (dropped_attack above 0) and the highest was not (dropped_retreat 0)", int(st.get("dropped_attack", 0)) > 0 and int(st.get("dropped_retreat", 0)) == 0, str(st))
	_check("burst: the help orders went before the attack orders called first (2 sent, 3 dropped)", int(st.get("sent_help", 0)) == 2 and int(st.get("dropped_help", 0)) == 3 and int(st.get("sent_attack", 0)) == 0, str(st))
	_check("burst: the last think's dropped squad ids come back from end_think", last_dropped == [a.id, b.id, c.id], str(last_dropped))
	_check("burst: no order was refused", int(st.get("fail", 0)) == 0 and ticks.size() == 20, str(st))
	orders.queue.clear()
	# (b2) A dropped squadron may be ordered again by the very next think (not only after the 5 s resend gap).
	_reset(9000.0, 600.0)
	_alarm(P, false)
	var pair := _singles(3, P)
	if pair.size() == 3:
		var cap1 := _prof()
		cap1.set_value("fleet_cap_orders", 1000)
		var f2 := AdmiralFleet.new(world, 0, ai.lanes, null, cap1)
		world.tick_count = base + 5000
		react.send("cap_full", OrderKinds.SET_REPEAT, {"repeat": 0}, [], "id", "fighter")
		f2.think(ts)
		_check("dropped: with the cap full the fleet's attack order is dropped and no squadron has an order", int(f2.outbox.stats().get("dropped_attack", 0)) == 1 and (pair[0] as Squad).order.is_empty() and (pair[2] as Squad).order.is_empty(), str(f2.outbox.stats()))
		_check("dropped: ... and the fleet does not hold the squadrons for the resend gap", f2._sent.is_empty(), str(f2._sent))
		world.tick_count = base + 5301
		f2.think(ts)
		_check("dropped: 301 ticks on (the window is empty) the very next think, at the same match second, sends the order", _target(pair[0]) != Vector2.INF and _target(pair[2]) == _target(pair[0]), str([(pair[0] as Squad).order, f2.outbox.stats()]))
	else:
		_check("dropped: three squadrons were made", false)
	orders.queue.clear()
	# (c) The alarm path through AdmiralAI's own think: RT5 calls the near squadrons from that same think and the fleet orders nobody.
	_reset(0.0, 500.0)
	var s1 := _squad("fighter", 3)
	var s2 := _squad("fighter", 3)
	var s3 := _squad("fighter", 3)
	if s1 == null or s2 == null or s3 == null:
		_check("alarm path: three squadrons were made", false)
	else:
		_place(s1, P)
		_place(s2, P + Vector2(500.0, 0.0))
		_place(s3, Vector2(36000.0, 2000.0))
		var saved := {}
		for key: String in ["fleet_play", "react_under_attack", "fleet_order_delay_ticks"]:
			saved[key] = ai.profile.raw(key)
		var saved_fleet := ai.fleet
		var saved_think := ai.think_t
		ai.profile.set_value("fleet_play", 1)
		ai.profile.set_value("react_under_attack", 1)
		ai.profile.set_value("fleet_order_delay_ticks", 0)
		ai.fleet = AdmiralFleet.new(world, 0, ai.lanes, ai.react, ai.profile)
		world.tick_count = base + 9000
		_alarm(P, true)
		ai.think_t = 0.0
		ai.tick(0.0)
		_check("alarm path: RT5 called the two near squadrons from that same think", ai.react._called.has(s1.id) and ai.react._called.has(s2.id) and not ai.react._called.has(s3.id), str(ai.react._called.keys()))
		_check("alarm path: the fleet counted one alarm think", int(ai.fleet.counters.get("alarm_thinks", 0)) == 1, str(ai.fleet.counters))
		_check("alarm path: the fleet sent no order and the far squadron's order is unchanged", ai.fleet.outbox.last_sent_ids.is_empty() and s3.order.is_empty(), str([ai.fleet.outbox.last_sent_ids, s3.order]))
		# The alarm ends 20 s on: RT5's _recall gives the called squadrons their rally Move in that think and the fleet does not
		# give them a second (8a's code sent one Move naming them in the same think).
		world.time += 20.0
		world.tick_count = base + 9000 + 1200
		_alarm(P, false)
		ai.think_t = 0.0
		ai.tick(0.0)
		_check("recall: RT5 gave the called squadrons their rally Move in that think, and it stands", _target(s1) == Vector2(Order.point(Vector2(s1.rally))) and int(s1.order["tick"]) == base + 10200 and _target(s2) == Vector2(Order.point(Vector2(s2.rally))), str([s1.order, s2.order]))
		_check("recall: no fleet order names the called squadrons; the far squadron gets its one", ai.fleet.outbox.last_sent_ids == [s3.id] and _orders_ok(ai.fleet) == 1, str([ai.fleet.outbox.last_sent_ids, ai.fleet.outbox.stats()]))
		# The switch turned on after the Admiral was made: no fleet object, and the think still runs.
		ai.fleet = null
		var thinks_before := ai.think_count
		ai.think_t = 0.0
		ai.tick(0.0)
		_check("recall: with fleet_play on and no fleet object the Admiral's think runs and does not crash", ai.think_count == thinks_before + 1)
		for key: String in saved:
			ai.profile.set_value(key, int(saved[key]))
		ai.fleet = saved_fleet
		ai.think_t = saved_think
		ai.react._called.clear()
	orders.queue.clear()
	world.tick_count = saved_tick
	_alarm(P, false)
	_reset(0.0, 0.0)


# --- the fleet rules: helpers out of the fight area, RT5's orders left alone -----------------------------------------------

## 2a: the helper group is left out of our strength in the fight area; 2d: a standing order given by something else holds the
## squadron from the fleet's orders for the resend gap, the layer's own orders do not.
func _rules_cases() -> void:
	var ai := _ai()
	var saved_tick := world.tick_count
	_reset(0.0, 700.0)
	var trio := _singles(3, Vector2(36000.0, 3000.0))
	if trio.size() < 3:
		_check("rules: three squadrons were made", false)
		return
	var x: Squad = trio[0]
	var y: Squad = trio[1]
	var z: Squad = trio[2]
	# 2a. Each single fighter at full hull is 1 point of strength.
	var f := AdmiralFleet.new(world, 0, ai.lanes, null, _prof())
	var area := Vector2(-20000.0, 20000.0)
	var free := f.free_squads()
	_check("helpers: with no helper group all three squadrons count (3 points)", is_equal_approx(f.own_strength(free, area), 3.0), str(f.own_strength(free, area)))
	f._help = {"lane": "mid", "ids": [x.id], "point": area}
	_check("helpers: the squadron of the helper group that is out adds no power (2 points)", is_equal_approx(f.own_strength(free, area), 2.0), str(f.own_strength(free, area)))
	_place(x, area)
	_check("helpers: ... also when it stands in the fight area (the second loop leaves it out too)", is_equal_approx(f.own_strength(free, area), 2.0), str(f.own_strength(free, area)))
	f._help = {}
	_check("helpers: with the group let go it counts again, once (3 points)", is_equal_approx(f.own_strength(free, area), 3.0), str(f.own_strength(free, area)))
	# 2d. What the fleet saw: a squadron ordered by something else is held for the resend gap.
	var base := 120000
	world.tick_count = base
	f._note_orders(700.0)
	_check("seen: a first look only records the squadrons' orders (nothing is held)", f._sent.is_empty() and int(f._seen.get(x.id, 0)) == -1 and int(f._seen.get(z.id, 0)) == -1, str([f._sent, f._seen]))
	x.order = {"kind": OrderKinds.MOVE, "target_kind": "point", "target": Vector2i(1000, 1000), "tick": base + 5, "settings": {}}
	f._note_orders(701.0)
	_check("seen: an order the layer did not give holds the squadron from the fleet (marked as ordered now)", is_equal_approx(float(f._sent.get(x.id, -1.0)), 701.0) and int(f._seen[x.id]) == base + 5 and not f._sent.has(y.id), str(f._sent))
	f.outbox.begin_think()
	f.outbox.send(AdmiralOutbox.PRI_MOVE, "seen", OrderKinds.MOVE, {}, [y.id], "point", Order.point(ai.lanes.lane_point("mid", 0.3)))
	f.outbox.end_think()
	f._note_orders(702.0)
	_check("seen: the layer's own order is not mistaken for another's", not f._sent.has(y.id) and int(f._seen[y.id]) == base, str([f._sent, f._seen, f.outbox.own_ticks(y.id)]))
	f._note_orders(703.0)
	_check("seen: an unchanged order changes nothing", is_equal_approx(float(f._sent.get(x.id, -1.0)), 701.0))
	_check("seen: a squadron with no order at two looks in a row is unordered, the ones with an order are not", f._unordered.has(z.id) and not f._unordered.has(x.id) and not f._unordered.has(y.id), str(f._unordered))
	# The held squadron gets no fleet order inside the gap, the others do.
	_alarm(P, false)
	world.time = 702.0
	f._sent[x.id] = 701.0
	y.order = {}
	z.order = {}
	x.order = {"kind": OrderKinds.MOVE, "target_kind": "point", "target": Vector2i(1000, 1000), "tick": base + 5, "settings": {}}
	f.think(_ts())
	_check("seen: a think inside the gap leaves the held squadron's order alone and orders the free ones", int((x.order["target"] as Vector2i).x) == 1000 and _target(z) != Vector2.INF, str([x.order, z.order]))
	world.tick_count = saved_tick
	_reset(0.0, 0.0)


# --- the waypoint and the "lane" rally follow the goal lane -----------------------------------------------------------------

## With the goal lane mid and our furthest minion on the top lane, the waypoint is placed on mid and the "lane" rally is mid's
## front point; with no fleet layer (fleet_play off) both still follow the top lane.
func _lane_cases() -> void:
	var ai := _ai()
	var ts := _ts()
	_reset(0.0, 700.0)
	var m := world.spawn_minion(0, "fighter", "top", ai.lanes.lane_point("top", 0.5))
	if m == null:
		_check("lane: a minion of ours was made on the top lane", false)
		return
	var saved_wp: Array = [ts.waypoint, ts.waypoint_until, ts.waypoint_by_human]
	var saved_fleet := ai.fleet
	_check("lane: our furthest minion is on the top lane (the push lane)", ai.lanes.push_lane() == "top")
	ai.fleet = null
	var wp := AdmiralWaypoint.new(world, 0, ai.lanes, ai.profile)
	wp.place(ts)
	_check("lane: with no fleet layer the waypoint goes down the top lane", ts.has_waypoint() and world.map.lane_for(ts.waypoint) == "top", str(ts.waypoint))
	_check("lane: ... and the \"lane\" rally is the top lane's front point", _prod().rally_point("lane", 0, 0) == ai.lanes.front_point("top"), str(_prod().rally_point("lane", 0, 0)))
	var fleet := AdmiralFleet.new(world, 0, ai.lanes, ai.react, _prof())
	ai.fleet = fleet
	wp.fleet = fleet
	fleet.influence.goal = ""
	ts.set_waypoint(Vector2.INF)
	wp.place(ts)
	_check("lane: a fleet layer with no goal lane yet changes nothing (the waypoint goes down the top lane)", world.map.lane_for(ts.waypoint) == "top" and _prod().rally_point("lane", 0, 0) == ai.lanes.front_point("top"))
	fleet.influence.goal = "mid"
	wp.place(ts)
	_check("lane: with the goal lane mid the waypoint is placed on the mid lane", world.map.lane_for(ts.waypoint) == "mid", str(ts.waypoint))
	_check("lane: ... and the \"lane\" rally is the mid lane's front point", _prod().rally_point("lane", 0, 0) == ai.lanes.front_point("mid"), str(_prod().rally_point("lane", 0, 0)))
	_check("lane: push_lane itself still says top", ai.lanes.push_lane() == "top")
	ai.fleet = null
	wp.fleet = null
	_check("lane: with the fleet layer off again the rally follows the top lane", _prod().rally_point("lane", 0, 0) == ai.lanes.front_point("top"))
	ai.fleet = saved_fleet
	ts.waypoint = saved_wp[0]
	ts.waypoint_until = saved_wp[1]
	ts.waypoint_by_human = saved_wp[2]
	m.alive = false
	_reset(0.0, 0.0)


# --- the talk lines --------------------------------------------------------------------------------------------------------

## The fleet's lines on the team feed: at most one every 10 s (the gap drops the others), the lowest rank of a think (posture,
## then goal lane, then help), none with log_feed off or while the base alarm is on.
func _talk_cases() -> void:
	var ai := _ai()
	var ts := _ts()
	_reset(9000.0, 3000.0)
	var trio: Array = []
	for i in 3:
		var rec := _squad("fighter", 3)
		if rec != null:
			_place(rec, P + Vector2(float(i) * 400.0, 0.0))
			trio.append(rec)
	if trio.size() < 3:
		_check("talk: three squadrons were made", false)
		return
	_listen(true)
	# The posture line, from the posture's state, once the gap has passed.
	var f := AdmiralFleet.new(world, 0, ai.lanes, null, _prof())
	f.posture.state = AdmiralPosture.RETREAT
	var said := f._talk_posture(3000.0)
	f._speak(3000.0)
	_check("talk: a posture in retreat says \"Fall back to our turrets\" once the gap has passed", said == "Fall back to our turrets" and _heard.size() == 1 and str(_heard[0][0]) == "Fall back to our turrets", str(_heard))
	f._lines.clear()
	f.posture.state = AdmiralPosture.ATTACK
	_check("talk: a posture in attack says \"Going back in\"", f._talk_posture(3001.0) == "Going back in")
	f._lines.clear()
	# The goal line: never "Pushing " with no lane.
	_check("talk: goal_line says nothing when the goal went to no lane", AdmiralFleet.goal_line("mid", "") == "")
	_check("talk: goal_line says \"Pushing top\" for the first pick from nothing", AdmiralFleet.goal_line("", "top") == "Pushing top")
	_check("talk: goal_line says nothing when the goal did not change", AdmiralFleet.goal_line("top", "top") == "")
	_check("talk: goal_line says the new lane when the goal changed", AdmiralFleet.goal_line("top", "mid") == "Pushing mid")
	# The ranks: posture before goal lane before help.
	f._said_at = -1000000.0
	f._line(2, "Help coming to mid")
	f._line(1, "Pushing top")
	f._speak(4000.0)
	_check("talk: the goal line goes before the help line", _heard.size() == 2 and str(_heard[1][0]) == "Pushing top", str(_heard))
	f._lines.clear()
	f._said_at = -1000000.0
	f._line(1, "Pushing top")
	f._line(0, "Going back in")
	f._line(2, "Help coming to mid")
	f._speak(4100.0)
	_check("talk: the posture line goes before them all, and only one is said", _heard.size() == 3 and str(_heard[2][0]) == "Going back in", str(_heard))
	f._lines.clear()
	# The gap: the first think picks the goal lane (a line), a pick 3 s later is dropped, the same pick 10 s after the first is said.
	var g := AdmiralFleet.new(world, 0, ai.lanes, null, _prof())
	_heard.clear()
	world.time = 5000.0
	g.think(ts)
	_check("talk: the first goal pick says \"Pushing <lane>\" (the first pick from nothing counts, and changes no count)", _heard.size() == 1 and str(_heard[0][0]) == "Pushing " + g.influence.goal and g.influence.changes == 0, str(_heard))
	g.influence.goal = ""
	world.time = 5003.0
	g.think(ts)
	_check("talk: a new goal pick 3 s after the first line is dropped by the gap", _heard.size() == 1 and g.influence.goal != "", str(_heard))
	g.influence.goal = ""
	world.time = 5010.0
	g.think(ts)
	_check("talk: ... and the same pick 10 s after the first line is said", _heard.size() == 2 and str(_heard[1][0]) == "Pushing " + g.influence.goal, str(_heard))
	_check("talk: the lines go to team 0's feed with the tone team", int(_heard[1][2]) == 0 and str(_heard[1][1]) == "team")
	# The help line, where a new help group is picked.
	g._lines.clear()
	world.time = 5100.0
	g._help = {}
	g.outbox.begin_think()
	g._help_think(g.free_squads(), world.time, {"bot": {"need": 4.0, "centre": ai.lanes.lane_point("bot", 0.4), "human": false}})
	g.outbox.end_think()
	g._speak(world.time)
	_check("talk: a new help group says \"Help coming to bot\"", _heard.size() == 3 and str(_heard[2][0]) == "Help coming to bot", str(_heard))
	# No line while the base alarm is on.
	world.time = 5200.0
	_alarm(P, true)
	g.influence.goal = ""
	g.think(ts)
	_check("talk: no line while the base alarm is on", _heard.size() == 3, str(_heard))
	_alarm(P, false)
	# log_feed off: nothing at all, though the fleet still speaks (counts) its line.
	var profile := ai.profile
	profile.set_value("log_feed", 0)
	g.influence.goal = ""
	world.time = 5300.0
	g.think(ts)
	_check("talk: with log_feed off no line reaches the feed", _heard.size() == 3, str(_heard))
	_listen(false)
	_reset(0.0, 0.0)


# --- the stuck squadrons ---------------------------------------------------------------------------------------------------

## The audit's parked test (RT8 build 8c, tests/admiral_audit.gd is_parked): a squadron given a Move and standing on its target is
## parked; one with an empty order is not (that is the idle counter's case); one 3,000 units from its target is not.
func _stuck_cases() -> void:
	var ai := _ai()
	_reset(9000.0, 500.0)
	var audit: Variant = load("res://tests/admiral_audit.gd")
	var dest := ai.lanes.lane_point("mid", 0.3)
	var on_it := _squad("fighter", 3)
	var empty := _squad("fighter", 3)
	var far := _squad("fighter", 3)
	if on_it == null or empty == null or far == null:
		_check("stuck: three squadrons were made", false)
		_reset(0.0, 0.0)
		return
	for rec: Squad in [on_it, far]:
		var why := world.orders.apply_now(Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, false, {}, [rec.id], "point", Order.point(dest)))
		_check("stuck: the Move to the test point was carried out", why == "" and _target(rec) != Vector2.INF, why)
	_place(on_it, dest)
	_place(empty, dest)
	_place(far, dest + Vector2(3000.0, 0.0))
	_check("stuck: a squadron given a Move and placed on its target is parked", audit.is_parked(on_it, world))
	_check("stuck: a squadron with an empty order is not parked", empty.order.is_empty() and not audit.is_parked(empty, world))
	_check("stuck: a squadron 3,000 units from its target is not parked", not audit.is_parked(far, world))
	_reset(0.0, 0.0)

# --- the idle-near squadrons -----------------------------------------------------------------------------------------------

## The audit's idle-near test (tests/admiral_audit.gd is_idle_near): a squadron with an empty order, or parked on its Move's target,
## with an enemy minion inside the reach is idle-near; the same with the enemy outside the reach is not; a squadron still travelling
## (its Move target 3,000 units away) is not, enemy near or not.
func _near_cases() -> void:
	var ai := _ai()
	_reset(9000.0, 500.0)
	var audit: Variant = load("res://tests/admiral_audit.gd")
	var reach: float = PilotTargeting.SEEK[0]
	var dest := ai.lanes.lane_point("mid", 0.3)
	var empty := _squad("fighter", 3)
	var parked := _squad("fighter", 3)
	var travelling := _squad("fighter", 3)
	if empty == null or parked == null or travelling == null:
		_check("near: three squadrons were made", false)
		_reset(0.0, 0.0)
		return
	for pair: Array in [[parked, dest], [travelling, dest + Vector2(3000.0, 0.0)]]:
		var rec: Squad = pair[0]
		var why := world.orders.apply_now(Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, false, {}, [rec.id], "point", Order.point(pair[1] as Vector2)))
		_check("near: the Move was carried out", why == "", why)
	_place(empty, dest)
	_place(parked, dest)
	_place(travelling, dest)
	var foe := world.spawn_minion(1, "fighter", "mid", dest + Vector2(reach - 400.0, 0.0))
	if foe == null:
		_check("near: an enemy minion was made", false)
		_reset(0.0, 0.0)
		return
	_check("near: an empty-order squadron with an enemy inside the reach is idle-near", empty.order.is_empty() and audit.is_idle_near(empty, world, reach))
	_check("near: a squadron parked on its Move target with an enemy inside the reach is idle-near", audit.is_idle_near(parked, world, reach))
	_check("near: a squadron 3,000 units from its Move target is not idle-near", not audit.is_idle_near(travelling, world, reach))
	foe.global_position = dest + Vector2(reach + 400.0, 0.0)
	_check("near: the same empty-order squadron with the enemy outside the reach is not idle-near", not audit.is_idle_near(empty, world, reach))
	foe.alive = false
	_reset(0.0, 0.0)

# --- the unpark step ----------------------------------------------------------------------------------------------------------

## The unpark step (AdmiralFleet._unpark, profile row fleet_unpark_s): with the row at 0 a parked squadron is never ordered; with the
## row above 0 a squadron parked longer than the row, with an enemy ship or minion the team sees inside fleet_unpark_reach, gets
## exactly one Attack order naming the nearest one (here a ship); with the enemy outside the reach it gets none; a squadron the reactions called is not free.
func _unpark_cases() -> void:
	var ai := _ai()
	_reset(9000.0, 500.0)
	var reach: float = _prof().f("fleet_unpark_reach")
	var dest := ai.lanes.lane_point("mid", 0.3)
	var rec := _squad("fighter", 3)
	var enemy_it := world.teams[1].production.spawn_now("fighter", 1)
	var enemy_squad: Squad = world.squads.get(int(enemy_it.get("squad", -1))) as Squad
	if rec == null or enemy_squad == null:
		_check("unpark: the squadrons were made", false)
		_reset(0.0, 0.0)
		return
	var foe: Ship = world.by_uid.get(int(enemy_squad.member_uids[0])) as Ship
	foe.visible_mask |= 1  # seen by team 0 now (the fog system sets this every tick; the world here is frozen)
	var park := func() -> void:
		rec.order = {}
		world.orders.apply_now(Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, false, {}, [rec.id], "point", Order.point(dest)))
		_place(rec, dest)
	var see := func(at: Vector2) -> void:
		foe.global_position = at
	var react := AdmiralReactions.new(world, 0, ai.lanes, ai.field, _prof())
	var off := AdmiralFleet.new(world, 0, ai.lanes, react, _prof())
	var on_prof := _prof()
	on_prof.set_value("fleet_unpark_s", 30000)
	var on := AdmiralFleet.new(world, 0, ai.lanes, react, on_prof)
	var rest: Array[Squad] = [rec]
	park.call()
	see.call(dest + Vector2(800.0, 0.0))
	var key := foe.get_instance_id()
	var seen := {"pos": foe.global_position, "hp": 1000, "si": 0, "seen": 500.0, "vis": true}
	off.view._ships[key] = seen
	on.view._ships[key] = seen
	for t in [600.0, 700.0]:
		off.outbox.begin_think()
		off._unpark(rest, t)
		off.outbox.end_think()
	_check("unpark: with the row at 0 a parked squadron is not ordered", _orders_ok(off) == 0 and str(rec.order.get("kind", "")) == OrderKinds.MOVE)
	on.outbox.begin_think()
	on._unpark(rest, 600.0)
	on.outbox.end_think()
	_check("unpark: parked for less than the row, no order", _orders_ok(on) == 0)
	on.outbox.begin_think()
	on._unpark(rest, 640.0)
	on.outbox.end_think()
	_check("unpark: parked longer than the row with an enemy ship in reach gets exactly one Attack order", _orders_ok(on) == 1 and str(rec.order.get("kind", "")) == OrderKinds.ATTACK, str([on.outbox.stats(), rec.order]))
	_check("unpark: ... naming that ship", typeof(rec.order.get("target")) == TYPE_INT and int(rec.order.get("target")) == foe.uid, str(rec.order))
	_check("unpark: ... and the attack point's Move leaves that squadron alone while the row is above 0, not while it is 0", on._on_unpark_job(rec) and not off._on_unpark_job(rec))
	park.call()
	see.call(dest + Vector2(reach + 400.0, 0.0))
	(on.view._ships[key] as Dictionary)["pos"] = foe.global_position
	on._parked_since.clear()
	on._sent.clear()
	for t in [700.0, 740.0]:
		on.outbox.begin_think()
		on._unpark(rest, t)
		on.outbox.end_think()
	_check("unpark: with the enemy outside the reach no order is sent", _orders_ok(on) == 1 and str(rec.order.get("kind", "")) == OrderKinds.MOVE, str(on.outbox.stats()))
	react._called[rec.id] = true
	_check("unpark: a squadron the reactions called home is not free, so never ordered here", on.free_squads().is_empty())
	react._called.clear()
	foe.alive = false
	_reset(0.0, 0.0)


# --- the unpark step through the whole layer ----------------------------------------------------------------------------

## The two enemy ships of the unpark path cases, made once and moved by each scene.
var _up_ships: Array = []
## The two enemy minions of the unpark path cases, made once and moved by each scene.
var _up_minions: Array = []


## The unpark step driven through fleet.think (not _unpark directly), so a deleted call or filter in _play turns a case red. Ten cases
## (T1 to T10, the names start "unpark2:"): the call, the filter, the sight test, the resend gap, a squadron still travelling, a minion
## as the target, the nearest of either kind, the reach row, the view off, a dead target skipped. The team view is switched on for
## the cases and put back, the enemy units are killed at the end.
func _unpark_path_cases() -> void:
	var ai := _ai()
	var tv_saved := ai.lanes.view.prof.raw("team_view")
	ai.lanes.view.prof.set_value("team_view", 1)
	var made := world.teams[1].production.spawn_now("fighter", 2)
	var enemy_squad: Squad = world.squads.get(int(made.get("squad", -1))) as Squad
	_up_ships = []
	_up_minions = []
	if enemy_squad != null:
		for uid: int in enemy_squad.member_uids:
			_up_ships.append(world.by_uid.get(uid))
	for k in 2:
		_up_minions.append(world.spawn_minion(1, "fighter", "mid", P + Vector2(0.0, 9000.0)))
	var made_ok := _up_ships.size() == 2 and _up_ships[0] is Ship and _up_ships[1] is Ship and _up_minions.size() == 2 and _up_minions[0] != null and _up_minions[1] != null
	_check("unpark2: set-up two enemy ships and two enemy minions were made", made_ok)
	if made_ok:
		_up_t1_t2()
		_up_t3()
		_up_t4()
		_up_t5()
		_up_t6()
		_up_t7()
		_up_t7b()
		_up_t8()
		_up_t9()
		_up_t10()
	for u: Variant in _up_ships + _up_minions:
		if u != null and is_instance_valid(u):
			(u as Unit).alive = false
	ai.lanes.view.prof.set_value("team_view", tv_saved)
	_reset(0.0, 0.0)


## A fresh scene: team 0 reset, a profile with fleet_unpark_s at 30 s, one squadron of three fighters, a new fleet on the Admiral's
## view (made afresh), every enemy unit hidden away, and the first think (world time 500 s), which gives the squadron its Move. The
## returned Dictionary holds "ok" (the squadron and its Move exist), "rec", "fleet", "prof", "target" (the Move's target) and
## "target_check" (true once the squadron stands on the target: every think then checks that the target did not move).
func _up_scene(label: String, view_on: bool = true) -> Dictionary:
	var ai := _ai()
	var sc := {"ok": false, "label": label, "target_check": false}
	_reset(9000.0, 500.0)
	ai.lanes.view.prof.set_value("team_view", 1 if view_on else 0)
	ai.lanes.view.reset()
	var prof := _prof()
	prof.set_value("fleet_unpark_s", 30000)
	sc["prof"] = prof
	var rec := _squad("fighter", 3)
	if rec == null:
		_check("unpark2: set-up the squadron was made", false, label)
		return sc
	_place(rec, P)
	var react := AdmiralReactions.new(world, 0, ai.lanes, ai.field, _prof())
	var fleet := AdmiralFleet.new(world, 0, ai.lanes, react, prof)
	sc["rec"] = rec
	sc["fleet"] = fleet
	_check("unpark2: set-up the team view is %s" % ("on" if view_on else "off"), fleet.view.enabled() == view_on, label)
	_up_stash()
	_up_think(sc, 500.0)
	var tgt := _target(rec)
	_check("unpark2: set-up the first think gave the squadron a Move", tgt != Vector2.INF, label)
	if tgt == Vector2.INF:
		return sc
	sc["target"] = tgt
	sc["ok"] = true
	return sc


## Every enemy unit of the cases moved away from the squadrons and hidden from team 0.
func _up_stash() -> void:
	for u: Variant in _up_ships + _up_minions:
		(u as Unit).global_position = P + Vector2(0.0, 9000.0)
		(u as Unit).visible_mask &= ~1


## One think of the scene at world time `at`: the view is brought up to date, the two set-up checks run (the posture is the attack
## posture; once the squadron stands on its target, the Move target has not moved), then the fleet thinks.
func _up_think(sc: Dictionary, at: float) -> void:
	var fleet: AdmiralFleet = sc["fleet"]
	world.time = at
	fleet.view.refresh()
	if bool(sc["target_check"]):
		_check("unpark2: set-up target moved", _target(sc["rec"] as Squad) == (sc["target"] as Vector2), "%s at %s: %s" % [sc["label"], str(at), str((sc["rec"] as Squad).order)])
	_check("unpark2: set-up posture", fleet.posture.state == AdmiralPosture.ATTACK, "%s at %s: %s" % [sc["label"], str(at), fleet.posture.state])
	fleet.think(_ts())


## Think at each of the world times in `times`, in order.
func _up_go(sc: Dictionary, times: Array) -> void:
	for at: float in times:
		_up_think(sc, at)


## Put the squadron on its Move target (from here on every think checks that the target did not move).
func _up_park(sc: Dictionary) -> void:
	_place(sc["rec"] as Squad, sc["target"] as Vector2)
	sc["target_check"] = true


## The centre of the squadron's living ships.
func _up_centre(sc: Dictionary) -> Vector2:
	var fleet: AdmiralFleet = sc["fleet"]
	return fleet._centre_of(fleet._ships_of(sc["rec"] as Squad))


## Put enemy unit `u` at `offset` from the squadron's centre, seen by team 0 (or not).
func _up_put(sc: Dictionary, u: Unit, offset: Vector2, seen: bool = true) -> void:
	u.global_position = _up_centre(sc) + offset
	if seen:
		u.visible_mask |= 1
	else:
		u.visible_mask &= ~1


## The kind of the squadron's standing order.
func _up_kind(sc: Dictionary) -> String:
	return str((sc["rec"] as Squad).order.get("kind", ""))


## Does the squadron stand an Attack order naming unit `u`?
func _up_hit(sc: Dictionary, u: Unit) -> bool:
	var o: Dictionary = (sc["rec"] as Squad).order
	return str(o.get("kind", "")) == OrderKinds.ATTACK and typeof(o.get("target")) == TYPE_INT and int(o.get("target")) == u.uid


## The value of the scene's fleet counter `name` (0 for none).
func _up_count(sc: Dictionary, name: String) -> int:
	return int((sc["fleet"] as AdmiralFleet).counters.get(name, 0))


## End a scene: the squadron's ships die, so the next scene starts with a clean world.
func _up_end(sc: Dictionary) -> void:
	if not sc.has("rec"):
		return
	for uid: int in (sc["rec"] as Squad).member_uids:
		var s: Variant = world.by_uid.get(uid)
		if s != null and is_instance_valid(s):
			(s as Unit).alive = false


## T1 (the call in _play): a ship in reach, the squadron parked on its Move target: at 20 s nothing, at 40 s one Attack naming the
## ship. T2 (the filter in _play), on the same fleet: after the resend gap and 5 s the order is the same Attack, no order was added
## and the counter is still 1 (the attack point's Move leaves the squadron alone).
func _up_t1_t2() -> void:
	var sa := _up_ships[0] as Ship
	var sc := _up_scene("T1")
	if bool(sc["ok"]):
		var fleet: AdmiralFleet = sc["fleet"]
		var rec: Squad = sc["rec"]
		_up_park(sc)
		_up_put(sc, sa, Vector2(800.0, 0.0))
		_up_go(sc, [510.0, 530.0])
		_check("unpark2: T1 parked 20 s: no Attack, the order is still the Move", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str(rec.order))
		var ok0 := _orders_ok(fleet)
		_up_go(sc, [550.0])
		_check("unpark2: T1 parked 40 s: exactly one Attack order", _up_kind(sc) == OrderKinds.ATTACK and _orders_ok(fleet) == ok0 + 1 and _up_count(sc, "unpark_orders") == 1, str([rec.order, _orders_ok(fleet), ok0]))
		_check("unpark2: T1 ... naming the ship", _up_hit(sc, sa), str(rec.order))
		_check("unpark2: T1 ... counted as a ship target and not as a minion target", _up_count(sc, "unpark_orders_ship") == 1 and _up_count(sc, "unpark_orders_minion") == 0)
		sc["target_check"] = false
		var attack := rec.order.duplicate()
		var ok1 := _orders_ok(fleet)
		_up_go(sc, [550.0 + (sc["prof"] as AdmiralProfile).f("react_resend_gap_s") + 5.0])
		_check("unpark2: T2 after the resend gap the order is the same Attack", rec.order == attack, str([rec.order, attack]))
		_check("unpark2: T2 ... no order was added and the unpark counter is still 1", _orders_ok(fleet) == ok1 and _up_count(sc, "unpark_orders") == 1, str([_orders_ok(fleet), ok1]))
	_up_end(sc)


## T3 (the sight test): a ship (whose record exists and is not seen) and a minion (which keeps no record), each alone and unseen for
## 40 s: no order; then seen: one Attack naming it.
func _up_t3() -> void:
	var sa := _up_ships[0] as Ship
	var ma := _up_minions[0] as Unit
	var sc := _up_scene("T3 ship")
	if bool(sc["ok"]):
		var fleet: AdmiralFleet = sc["fleet"]
		var rec: Squad = sc["rec"]
		var key := sa.get_instance_id()
		_up_park(sc)
		_up_put(sc, sa, Vector2(800.0, 0.0))
		fleet.view.refresh()
		_check("unpark2: set-up T3 ship the record exists before the ship is hidden", fleet.view._ships.has(key))
		sa.visible_mask &= ~1
		fleet.view.refresh()
		_check("unpark2: set-up T3 ship the record stays with vis false", fleet.view._ships.has(key) and not bool((fleet.view._ships[key] as Dictionary)["vis"]))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T3 ship hidden for 40 s: no order", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str(rec.order))
		sa.visible_mask |= 1
		_up_go(sc, [551.0])
		_check("unpark2: T3 ship seen again: one Attack naming the ship", _up_hit(sc, sa) and _up_count(sc, "unpark_orders") == 1, str(rec.order))
	_up_end(sc)
	sc = _up_scene("T3 minion")
	if bool(sc["ok"]):
		var rec2: Squad = sc["rec"]
		_up_park(sc)
		_up_put(sc, ma, Vector2(800.0, 300.0), false)
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T3 minion unseen for 40 s: no order", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str(rec2.order))
		ma.visible_mask |= 1
		_up_go(sc, [551.0])
		_check("unpark2: T3 minion seen again: one Attack naming the minion", _up_hit(sc, ma) and _up_count(sc, "unpark_orders") == 1, str(rec2.order))
	_up_end(sc)


## T4 (the resend gap): the row is half the gap, so the wait ends inside the gap the Move just opened: a think after the wait but
## inside the gap sends nothing; a think 1 s after the gap sends the Attack.
func _up_t4() -> void:
	var sa := _up_ships[0] as Ship
	var sc := _up_scene("T4")
	if bool(sc["ok"]):
		var prof: AdmiralProfile = sc["prof"]
		var rec: Squad = sc["rec"]
		var gap := prof.f("react_resend_gap_s")
		prof.set_value("fleet_unpark_s", roundi(gap * 500.0))
		_up_park(sc)
		_up_put(sc, sa, Vector2(800.0, 0.0))
		_up_go(sc, [501.0, 500.0 + gap - 1.0])
		_check("unpark2: T4 the wait is over but the gap is not: no order", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str(rec.order))
		_up_go(sc, [500.0 + gap + 1.0])
		_check("unpark2: T4 the gap plus 1 s after the Move: one Attack naming the ship", _up_hit(sc, sa) and _up_count(sc, "unpark_orders") == 1, str(rec.order))
	_up_end(sc)


## T5 (a squadron still travelling): farther from its Move target than react_resend_dist it is not ordered even after 90 s with a
## ship in reach; once it stands on the target the order comes after the wait counted from the arrival.
func _up_t5() -> void:
	var sa := _up_ships[0] as Ship
	var sc := _up_scene("T5")
	if bool(sc["ok"]):
		var fleet: AdmiralFleet = sc["fleet"]
		var rec: Squad = sc["rec"]
		var away := (sc["prof"] as AdmiralProfile).f("react_resend_dist") + 1500.0
		_place(rec, (sc["target"] as Vector2) + Vector2(away, 0.0))
		_up_put(sc, sa, Vector2(800.0, 0.0))
		var ok0 := _orders_ok(fleet)
		_up_go(sc, [510.0, 540.0, 570.0, 600.0])
		_check("unpark2: T5 travelling for 90 s with a ship in reach: no order", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0 and _orders_ok(fleet) == ok0, str(rec.order))
		_up_park(sc)
		_up_put(sc, sa, Vector2(800.0, 0.0))
		_up_go(sc, [610.0, 625.0])
		_check("unpark2: T5 15 s after arriving: no order yet", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str(rec.order))
		_up_go(sc, [650.0])
		_check("unpark2: T5 40 s after arriving: one Attack naming the ship", _up_hit(sc, sa) and _up_count(sc, "unpark_orders") == 1, str(rec.order))
	_up_end(sc)


## T6 (the new target kind): only an enemy minion in reach, no ship: one Attack naming the minion, counted as a minion target.
func _up_t6() -> void:
	var ma := _up_minions[0] as Unit
	var sc := _up_scene("T6")
	if bool(sc["ok"]):
		var rec: Squad = sc["rec"]
		_up_park(sc)
		_up_put(sc, ma, Vector2(800.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T6 a minion alone in reach: one Attack naming the minion", _up_hit(sc, ma) and _up_count(sc, "unpark_orders") == 1, str(rec.order))
		_check("unpark2: T6 ... counted as a minion target and not as a ship target", _up_count(sc, "unpark_orders_minion") == 1 and _up_count(sc, "unpark_orders_ship") == 0)
	_up_end(sc)


## T7 (the rule: the nearest enemy of either kind, a tie to the lower instance id): a ship at 600 and a minion at 300: the minion;
## swapped: the ship; the same distance on opposite sides: the lower instance id, once against each minion.
func _up_t7() -> void:
	var sa := _up_ships[0] as Ship
	var ma := _up_minions[0] as Unit
	var mb := _up_minions[1] as Unit
	var sc := _up_scene("T7 minion nearer")
	if bool(sc["ok"]):
		_up_park(sc)
		_up_put(sc, sa, Vector2(600.0, 0.0))
		_up_put(sc, ma, Vector2(0.0, 300.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T7 a minion at 300 and a ship at 600: the minion is named", _up_hit(sc, ma), str((sc["rec"] as Squad).order))
	_up_end(sc)
	sc = _up_scene("T7 ship nearer")
	if bool(sc["ok"]):
		_up_park(sc)
		_up_put(sc, sa, Vector2(0.0, 300.0))
		_up_put(sc, ma, Vector2(600.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T7 a ship at 300 and a minion at 600: the ship is named", _up_hit(sc, sa), str((sc["rec"] as Squad).order))
	_up_end(sc)
	for other: Unit in [ma, mb]:
		var lower: Unit = sa if sa.get_instance_id() < other.get_instance_id() else other
		var which := "ship" if lower == sa else "minion"
		sc = _up_scene("T7 tie")
		if bool(sc["ok"]):
			_up_park(sc)
			_up_put(sc, sa, Vector2(500.0, 0.0))
			_up_put(sc, other, Vector2(-500.0, 0.0))
			var c := _up_centre(sc)
			_check("unpark2: set-up T7 tie the two units are at the same distance", is_equal_approx(sa.global_position.distance_to(c), other.global_position.distance_to(c)))
			_up_go(sc, [510.0, 550.0])
			_check("unpark2: T7 the same distance on opposite sides: the lower instance id (a %s) is named" % which, _up_hit(sc, lower), str([(sc["rec"] as Squad).order, lower.uid]))
		_up_end(sc)


## T7b (the tie where the minion has the LOWER instance id): a minion and a ship made in that order (so the minion's id is lower,
## asserted in the case) at exactly the same distance on opposite sides: the one Attack order names the minion.
func _up_t7b() -> void:
	var sc := _up_scene("T7b tie, minion lower")
	if bool(sc["ok"]):
		var minion := world.spawn_minion(1, "fighter", "mid", P + Vector2(0.0, 9000.0)) as Unit
		var made := world.teams[1].production.spawn_now("fighter", 1)
		var squad: Squad = world.squads.get(int(made.get("squad", -1))) as Squad
		var ship: Ship = null
		if squad != null and not squad.member_uids.is_empty():
			ship = world.by_uid.get(int(squad.member_uids[0])) as Ship
		var made_ok := minion != null and ship != null
		_check("unpark2: set-up T7b a minion and then a ship were made", made_ok)
		if made_ok:
			_check("unpark2: set-up T7b the minion has the lower instance id", minion.get_instance_id() < ship.get_instance_id(), "%d %d" % [minion.get_instance_id(), ship.get_instance_id()])
			_up_park(sc)
			_up_put(sc, ship, Vector2(500.0, 0.0))
			_up_put(sc, minion, Vector2(-500.0, 0.0))
			var c := _up_centre(sc)
			_check("unpark2: set-up T7b tie the two units are at the same distance", is_equal_approx(ship.global_position.distance_to(c), minion.global_position.distance_to(c)))
			_up_go(sc, [510.0, 550.0])
			_check("unpark2: T7b the same distance, the minion has the lower instance id: the minion is named", _up_hit(sc, minion) and _up_count(sc, "unpark_orders") == 1, str([(sc["rec"] as Squad).order, minion.uid]))
		for u: Variant in [minion, ship]:
			if u != null and is_instance_valid(u):
				(u as Unit).alive = false
	_up_end(sc)


## T8 (the reach is the row): at the default reach R a ship at R - 400 is ordered and one at R + 400 is not; with the row at 2 R the
## ship at R + 400 is ordered; with the row at 0 nothing is ordered even at 100 units.
func _up_t8() -> void:
	var sa := _up_ships[0] as Ship
	var reach := 0.0
	var sc := _up_scene("T8 inside")
	if bool(sc["ok"]):
		reach = (sc["prof"] as AdmiralProfile).f("fleet_unpark_reach")
		_check("unpark2: set-up T8 the reach row is above 800 units by default", reach > 800.0, str(reach))
		_up_park(sc)
		_up_put(sc, sa, Vector2(reach - 400.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T8 a ship at the reach minus 400 units is ordered", _up_hit(sc, sa), str((sc["rec"] as Squad).order))
	_up_end(sc)
	sc = _up_scene("T8 outside")
	if bool(sc["ok"]):
		_up_park(sc)
		_up_put(sc, sa, Vector2(reach + 400.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T8 a ship at the reach plus 400 units is not ordered", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str((sc["rec"] as Squad).order))
	_up_end(sc)
	sc = _up_scene("T8 double")
	if bool(sc["ok"]):
		(sc["prof"] as AdmiralProfile).set_value("fleet_unpark_reach", roundi(reach * 2000.0))
		_up_park(sc)
		_up_put(sc, sa, Vector2(reach + 400.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T8 with the row at twice the reach the ship at the old reach plus 400 units is ordered", _up_hit(sc, sa), str((sc["rec"] as Squad).order))
	_up_end(sc)
	sc = _up_scene("T8 zero")
	if bool(sc["ok"]):
		(sc["prof"] as AdmiralProfile).set_value("fleet_unpark_reach", 0)
		_up_park(sc)
		_up_put(sc, sa, Vector2(100.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T8 with the row at 0 nothing is ordered even at 100 units", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str((sc["rec"] as Squad).order))
	_up_end(sc)


## T9 (the view off): with team_view off a seen enemy minion alone gets no order, while a hand-written ship record still does (the
## minions need the view on).
func _up_t9() -> void:
	var sa := _up_ships[0] as Ship
	var ma := _up_minions[0] as Unit
	var sc := _up_scene("T9 minion", false)
	if bool(sc["ok"]):
		_up_park(sc)
		_up_put(sc, ma, Vector2(800.0, 0.0))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T9 with the view off a seen minion alone gets no order", _up_kind(sc) == OrderKinds.MOVE and _up_count(sc, "unpark_orders") == 0, str((sc["rec"] as Squad).order))
	_up_end(sc)
	sc = _up_scene("T9 ship", false)
	if bool(sc["ok"]):
		var fleet: AdmiralFleet = sc["fleet"]
		_up_park(sc)
		_up_put(sc, sa, Vector2(800.0, 0.0))
		fleet.view._ships[sa.get_instance_id()] = {"pos": sa.global_position, "hp": 1000, "si": 0, "seen": 500.0, "vis": true}
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T9 with the view off a hand-written ship record still gets the order", _up_hit(sc, sa), str((sc["rec"] as Squad).order))
	_up_end(sc)


## T10 (a dead target is skipped): two enemy ships in reach, the nearer one's record kept but the unit dead and unseen, the farther one
## alive and seen: the farther one is named. The record of the dead ship must still exist before the think (else the case would not
## use the skip).
func _up_t10() -> void:
	var sa := _up_ships[0] as Ship
	var sb := _up_ships[1] as Ship
	var sc := _up_scene("T10")
	if bool(sc["ok"]):
		var fleet: AdmiralFleet = sc["fleet"]
		_up_park(sc)
		_up_put(sc, sa, Vector2(600.0, 0.0))
		_up_put(sc, sb, Vector2(1200.0, 0.0))
		fleet.view.refresh()
		_check("unpark2: set-up T10 both ship records exist", fleet.view._ships.has(sa.get_instance_id()) and fleet.view._ships.has(sb.get_instance_id()))
		sa.alive = false
		sa.visible_mask &= ~1
		fleet.view.refresh()
		_check("unpark2: set-up T10 record gone", fleet.view._ships.has(sa.get_instance_id()))
		_up_go(sc, [510.0, 550.0])
		_check("unpark2: T10 the nearer ship is dead: the farther one is named", _up_hit(sc, sb), str((sc["rec"] as Squad).order))
	_up_end(sc)


# --- the d word of the match log -------------------------------------------------------------------------------------------

## The log's d word (RT8 build 8c, Order.to_line / from_line / result_of): a computer order of the Admiral's seat decided before its
## apply tick ends with d<decision tick> and reads back with that tick and "decided"; a human order never gets one; a line with
## no d word reads as before; result_of ignores the word.
func _dword_cases() -> void:
	var pt := Order.point(Vector2(1000.0, 2000.0))
	var late := Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, false, {}, [4, 5], "point", pt)
	late["id"] = 77
	late["tick"] = 1000
	late["apply_tick"] = 1018
	var line := Order.to_line(late, "ok")
	var back := Order.from_line(line)
	_check("dword: a delayed computer order's line ends with d1000", line.ends_with(" ok d1000"), line)
	_check("dword: it reads back with the decision tick, the apply tick and the mark", int(back["tick"]) == 1000 and int(back["apply_tick"]) == 1018 and bool(back.get("decided", false)) and int(back["id"]) == 77, str(back))
	_check("dword: result_of still gives the code", Order.result_of(line) == "ok")
	var same_tick := late.duplicate(true)
	same_tick["tick"] = 1018
	var plain := Order.to_line(same_tick, "ok")
	var plain_back := Order.from_line(plain)
	_check("dword: an order decided on its apply tick has no d word and reads as before", plain.split(" ").size() == 9 and not plain_back.has("decided") and int(plain_back["tick"]) == 1018 and Order.result_of(plain) == "ok", plain)
	var human := Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, true, {}, [4], "point", pt)
	human["id"] = 78
	human["tick"] = 1017
	human["apply_tick"] = 1018
	var hline := Order.to_line(human, "ok")
	var hback := Order.from_line(hline)
	_check("dword: a human order never gets one (tick is apply tick minus 1)", hline.split(" ").size() == 9 and not hback.has("decided") and int(hback["tick"]) == 1017, hline)

# --- the goal lane in the match log and its replay ---------------------------------------------------------------------------

## RT8 build 8d: a change of the goal lane is an `f` line "goal" in the match log, and the replay of the computer Admirals (which runs no
## think) sets the goal lane from it, so that the "lane" rally reads the same goal there. The case writes a real log (one think of the
## fleet layer, a second think inside the 60 s hold), reads it back, files the line in a ReplayPlayer and plays it through
## OrderQueue.replay_ai on a fleet whose goal was cleared; a decided record (an order with a d word) is filed under its decision tick
## and replay_ai queues it instead of applying it.
func _goal_replay_cases() -> void:
	var ai := _ai()
	var ts := _ts()
	_reset(0.0, 700.0)
	var q := world.orders
	var saved: Array = [ai.fleet, q.replay, q.replaying_ai, q.log, world.tick_count, q.queue.size()]
	var base := 130000
	world.tick_count = base
	var fleet := AdmiralFleet.new(world, 0, ai.lanes, ai.react, _prof())
	ai.fleet = fleet
	var path := "user://admiral_fleet_check_goal.log"
	var lg := OrderLog.new()
	if not lg.open(path, world):
		_check("goalreplay: the scratch log was opened", false)
		ai.fleet = saved[0]
		_reset(0.0, 0.0)
		return
	q.log = lg
	lg.header()
	fleet.think(ts)
	var lane := fleet.influence.goal
	_check("goalreplay: the first think picked a goal lane", lane != "", lane)
	world.tick_count = base + 60
	world.time = 701.0
	fleet.think(ts)
	_check("goalreplay: a second think inside the hold keeps the goal", fleet.influence.goal == lane, fleet.influence.goal)
	q.log = null
	lg.close(world)
	var read := OrderLog.read(path)
	var goals: Array = []
	for f: Dictionary in read["field"]:
		if str(f["op"]) == "goal":
			goals.append(f)
	_check("goalreplay: the log has one goal line, on the tick of the change, for team 0, with the lane", goals.size() == 1 and int(goals[0]["apply_tick"]) == base and int(goals[0]["team"]) == 0 and str(goals[0]["a"]) == lane and str(goals[0]["b"]) == "", str(goals))
	# Play it back on a fleet that never thought: replay_ai sets the goal lane at the logged tick, and not before.
	var player := ReplayPlayer.new()
	_check("goalreplay: the scratch log was read by the replay", player.start(path, true))
	q.replay = player
	q.replaying_ai = true
	fleet.influence.goal = ""
	world.tick_count = base - 1
	q.replay_ai(0)
	_check("goalreplay: before the logged tick replay_ai leaves the goal alone", fleet.influence.goal == "")
	world.tick_count = base
	q.replay_ai(0)
	_check("goalreplay: at the logged tick replay_ai sets the goal lane the log has", fleet.influence.goal == lane, fleet.influence.goal)
	_check("goalreplay: ... and the \"lane\" rally then reads it (the front point of that lane)", _prod().rally_point("lane", 0, 0) == ai.lanes.front_point(lane), str(_prod().rally_point("lane", 0, 0)))
	# A goal line of a team with no fleet layer is skipped, not an error.
	var other := 1 if world.admiral_ai.size() > 1 and world.admiral_ai[1] != null and (world.admiral_ai[1] as AdmiralAI).fleet == null else -1
	player._file({"field": true, "apply_tick": base + 5, "team": other if other >= 0 else 0, "op": "goal", "a": "top", "b": ""})
	var keep := fleet.influence.goal
	world.tick_count = base + 5
	if other >= 0:
		q.replay_ai(0)
		_check("goalreplay: a goal line of a team with no fleet layer changes nothing here", fleet.influence.goal == keep)
	else:
		player.due(base + 5)
	# A decided record: filed under its decision tick, queued (not applied) by replay_ai, once.
	var pt := Order.point(Vector2(1000.0, 2000.0))
	var late := Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, false, {}, [4], "point", pt)
	late["id"] = 91
	late["tick"] = base + 10
	late["apply_tick"] = base + 28
	var rec := Order.from_line(Order.to_line(late, "ok"))
	var plain := Order.make(OrderKinds.MOVE, 0, Rules.ADMIRAL_SEAT, false, {}, [4], "point", pt)
	plain["id"] = 92
	plain["tick"] = base + 40
	plain["apply_tick"] = base + 40
	player._file(rec)
	player._file(Order.from_line(Order.to_line(plain, "ok")))
	_check("goalreplay: nothing is due before the decision tick", player.due(base + 9).is_empty() and player.due(base + 28).is_empty())
	var before := q.queue.size()
	world.tick_count = base + 10
	q.replay_ai(0)
	var queued := q.queue.size() == before + 1 and int((q.queue[q.queue.size() - 1] as Dictionary)["id"]) == 91
	_check("goalreplay: the decided record is queued at its decision tick (carried out later by run_due, not applied now)", queued, str(q.queue.size()))
	q.replay_ai(0)
	_check("goalreplay: ... and only once", q.queue.size() == before + 1)
	var due_plain := player.due(base + 40)
	_check("goalreplay: a record with no d word is filed under its apply tick", due_plain.size() == 1 and int((due_plain[0] as Dictionary)["id"]) == 92 and not (due_plain[0] as Dictionary).has("decided"), str(due_plain))
	# Put everything back.
	q.queue.resize(saved[5])
	q.replay = saved[1]
	q.replaying_ai = saved[2]
	q.log = saved[3]
	ai.fleet = saved[0]
	world.tick_count = saved[4]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_reset(0.0, 0.0)
