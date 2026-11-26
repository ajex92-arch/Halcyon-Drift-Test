extends Node
## WHAT THIS IS: a bug hunt for the AI admiral. Once a second it samples
## both teams' admiral-level state and keeps counters and a short timeline:
## treasury, build-plan steps finished, drones (and how many sit idle),
## turrets, repair bays (and their lane), wards, the waypoint's lane, the
## "push lane" (how often it
## flips, and whether it agrees with the lane whose minions are furthest as
## a FRACTION of the lane), sieges (declared, phases, why they ended, hull
## the enemy mothership lost during our assaults), mothership moves and how
## long it stays up a lane, who kills our repair bays, wards, turrets and
## mining drones (killer kind, place, age), credits spent per sink, how far
## apart the motherships are, where our pilots stand per lane, the admiral's
## field trips in its own ship (how many, why, how long, how they ended, and
## whether its thinking went on while it flew), and how the match ended.
##
## HOW IT WORKS: setup() connects to the admiral's order results
## (Events.admiral_result), its field trips (Events.admiral_field), kills
## (Events.unit_killed) and the end of the match. _physics_process() calls
## _sample() for each computer admiral once a second, prints one "ADM" line
## every 60 game seconds and, at the end, one "AUDIT_JSON {...}" line with
## every counter, the build-plan finish times, the event timeline, the
## structure deaths and each team's field trips ("field_trips": the records
## of AdmiralField.trips; a trip still running at the end has "end": -1).
##
## The fleet layer's counters (RT8 build 8a; only while the profile switch fleet_play is on): "fleet_<name>" for each entry of
## AdmiralFleet.stats() (goal_changes, posture_switches, thinks, alarm_thinks, attack_thinks, retreat_thinks, help_groups, refused,
## unordered_squad_thinks, outbox_* by priority, think_us_max and think_us_mean in microseconds; send_us_max, send_us_mean and send_over_2ms time end_think, the order-carrying part of a think). Every team also gets
## "orders_300_max", the most orders of the Admiral's seat (carried out or refused) inside any 300 ticks, and "orders_refused_total".
##
## The idle bought squadrons (T-13 note 30; RT8 build 8b): once a second per team the bought squadrons with a ship alive and an empty
## standing order are looked at: "idle_squad_max_s" (the longest run of seconds one squadron had no order), "idle_stack_max" (the
## most idle squadrons, the squadron itself counted, within 1,500 units of one idle squadron's centre in one sample),
## "idle_at_742" and "idle_stack_at_742" (the squadrons idle and the stack at the sample nearest 742 s, 12:22; "idle_742_sample_s"
## is that sample's second) and "idle_spans" (rows [squad id, first second, last second] for runs of 10 s or more, at most 40).
## The outbox's "dropped" and "dropped_<priority>" counters are printed with the other outbox counters ("fleet_outbox_*").
##
## The stuck squadrons (RT8 build 8c; a readout only, no pass mark): once a second per team a bought squadron with a ship alive is
## PARKED when its standing order is a Move and the centre of its living ships is within ARRIVED_DIST (2,000 units) of the Move's
## target (is_parked); a run is the samples in a row it was parked under the same order (the order's "tick" did not change).
## Printed per team: "stuck_squad_max_s" (the longest run of one squadron, in seconds), "stuck_squads_max" (the most squadrons
## whose run had lasted STUCK_SPAN_MIN_S, 30 s, or more in one sample) and "stuck_spans" (rows [squad id, first second, last
## second] for runs of 30 s or more, at most 40). A group held at an attack point on purpose counts too.
##
## The idle-near squadrons (the bought squadrons with no job and an enemy close; a readout only, no pass mark): a squadron is IDLE-NEAR
## when it has a ship alive, its order is empty or it is parked (is_parked), and an enemy ship or minion is within the reach (the
## strike squadron's target-search range) of the centre of its living ships (is_idle_near). Printed per team: "idle_near_max_s" (the
## longest run of seconds one squadron was idle-near), "idle_near_spans" (rows [squad id, first second, last second] for runs of
## 10 s or more, at most 40) and "still_stack_max" (the most squadrons that are idle or parked, the squadron itself counted, within
## 1,500 units of one such squadron's centre in one sample: the picture the web notes showed). Each row of "stuck_spans" also
## carries three numbers read at the span's start: the distance to the nearest enemy turret, the enemy ships and minions within the
## reach and our minions within the reach.
##
## Every order of the Admiral's seat is also counted by its own kind name, from the order event stream
## (Events.rts_event: order_done / order_refused): "ord_<KIND>_ok" and "ord_<KIND>_fail" for each kind (DRONE,
## MODULE, RESEARCH, TURRET, POST, BAY, WARD, WAYPOINT, MOTHERSHIP_MOVE, SIEGE, PRODUCE, HOLD_ITEM, SET_REPEAT,
## CANCEL, MOVE_ITEM, SET_RALLY), plus "ord_<KIND>_fail_<code>" for the refusal code (RT5 build 4a: MOVE, CANCEL and SET_REPEAT
## now include the reactions' orders; the "react_<reaction>_<KIND>_ok" counters, the "react_seen_*" records read and the
## "react_float_*" ore left unspent at a full fleet cap tell them apart, from AdmiralReactions.stats()). The older "cmd_<action>_ok"
## counters stay, where HOLD_ITEM, SET_REPEAT, CANCEL, MOVE_ITEM and SET_RALLY are all the one word "yard".
##
## The base alarm (only while the profile switch fleet_play is on; a read-out, no pass mark): once a second per team the sample
## looks at TeamState.defending. "alarm_rows" holds one row per finished alarm episode, [first second, last second, fleet alarm
## thinks, fleet orders, AdmiralReactions Moves], at most 20 per team; "alarm_s" is the seconds (samples) the alarm was on. The thinks and the
## orders are the fleet layer's own counters (alarm_thinks; the outbox's ok plus fail) as they stood at the last second the alarm
## was on, less their value at the sample before it began; the Moves are AdmiralReactions' "attack_MOVE_ok" count up to the first sample after the
## alarm (the calls and the recall). The timeline gets "alarm_on" (the lane of the defend point) and "alarm_off" (the seconds), and
## the match end prints "ALARM_ROWS team=.. episodes=.. alarm_s=.. fleet_thinks=.. fleet_orders=.. rt5_moves=.." for a team with a
## row. With fleet_play off none of these exist and the AUDIT_JSON is what it was.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --test=admiral_audit --secs=1800
## --late starts at 25:00 fully teched (LateGame.apply) and --secs then
## counts from there (for example --late --secs=900).
##
## WHO USES IT: main.gd loads it for --test=admiral_audit. It only reads the
## game (and connects to Events); it adds no orders and changes nothing in
## the match.


## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1800.0
## Seconds until the next once-a-second sample.
var _t := 0.0
## Game time of the next ADM line.
var _report_t := 60.0
## Per team: counters (name -> number).
var c := [{}, {}]
## Per team: match time each build-plan step was finished.
var plan_t := [{}, {}]
## Timeline of events: [time, team, what, detail].
var ev := []
## Our structures that died: [time, team, what, detail] (kept apart so the
## main timeline never fills up).
var deaths := []
## Per team: last values (push lane, siege lane/phase, ms move target...).
var _last := [{}, {}]
## Birth time of each bay / ward / turret we have seen: instance id -> time.
var _born := {}
## Last hull fraction of each mothership (to add up the hull it lost).
var _ms_hp := [1.0, 1.0]
## Why the match ended (from Events.match_over); empty until it does.
var _end_reason := ""
## The winning team (from Events.match_over); -2 until the match ends.
var _end_winner := -2
## Per team: the ticks of the Admiral seat's orders still inside the last 300 ticks (the window of orders_300_max).
var _order_ticks := [[], []]
## Per team: the idle runs going now (squad id -> [first sample second, last sample second, samples]), and the runs of 10 or more
## samples that have ended: rows [squad id, first second, last second] (at most IDLE_SPANS_MAX per team).
var _idle_runs := [{}, {}]
var _idle_spans := [[], []]  # the rows of the idle runs that lasted 10 s or more
## Per team: how far from 742 s (12:22, the lead's proof second) the sample used for idle_at_742 was.
var _idle_742_diff := [INF, INF]
## The most idle-run rows kept per team, the radius of an idle stack and the shortest run that is kept as a span (seconds).
const IDLE_SPANS_MAX := 40
const IDLE_STACK_RADIUS := 1500.0  # the radius of an idle stack, in world units
const IDLE_SPAN_MIN_S := 10  # the shortest idle run kept as a span
## Per team: the base alarm episode open now ({} while the alarm is off): "first" and "last" (the first and last sample second it was on),
## "n" (samples on), "base" (thinks, orders and Moves at the sample before it began) and "seen" (the same three at the last sample
## it was on); the rows of the episodes that have ended: [first second, last second, fleet alarm thinks, fleet orders, AdmiralReactions Moves].
var _alarm_open := [{}, {}]
var _alarm_rows := [[], []]  # the finished episodes, at most ALARM_ROWS_MAX per team
## Per team: the seconds (samples) the base alarm was on, and the three counters of the previous sample.
var _alarm_s := [0, 0]
var _alarm_prev := [[0, 0, 0], [0, 0, 0]]  # the three alarm counters of the previous sample, per team
const ALARM_ROWS_MAX := 20  # the most alarm rows kept per team
## Per team: the parked runs going now (squad id -> [first sample second, last sample second, samples, the order's tick]), and the
## rows [squad id, first second, last second] of the parked runs of STUCK_SPAN_MIN_S or more samples that have ended.
var _stuck_runs := [{}, {}]
var _stuck_spans := [[], []]  # the rows of the parked runs that lasted 30 s or more
## The most parked-run rows kept per team, the shortest parked run kept as a span (seconds) and how near the target a squadron
## counts as arrived (world units; react_resend_dist is 2,000 in every profile).
const STUCK_SPANS_MAX := 40  # the most parked-run rows kept per team
const STUCK_SPAN_MIN_S := 30  # the shortest parked run kept as a span (seconds)
const ARRIVED_DIST := 2000.0  # how near its target a squadron counts as arrived (world units)
## Per team: the idle-near runs going now (squad id -> [first sample second, last sample second, samples]) and the rows
## [squad id, first second, last second] of the runs of IDLE_SPAN_MIN_S or more samples that have ended.
var _near_runs := [{}, {}]
var _near_spans := [[], []]  # the rows of the idle-near runs that lasted 10 s or more
## How far an enemy ship or minion may be from a squadron's centre for the squadron to count as idle-near (world units): the
## target-search range of a strike squadron's size class, read from the pilots' own table.
var _reach: float = PilotTargeting.SEEK[0]


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	if Game.opt("late", false):
		LateGame.apply(world)
		secs += LateGame.START
		_report_t = LateGame.START + 60.0
	Events.admiral_result.connect(_on_result)
	Events.rts_event.connect(_on_order_event)
	Events.admiral_field.connect(_on_field)
	Events.unit_killed.connect(_on_killed)
	Events.match_over.connect(_on_over)


## The admiral took the field or came back (Events.admiral_field): count
## the starts by reason and the ends by how they ended, add up the seconds
## spent out, and put it on the timeline.
func _on_field(team: int, started: bool, reason: String) -> void:
	if team < 0 or team > 1:
		return
	if started:
		_add(team, "field_start")
		_add(team, "field_start_" + reason)
		_last[team]["field_t"] = world.time
	else:
		_add(team, "field_end_" + reason)
		_add(team, "field_secs", world.time - float(_last[team].get("field_t", world.time)))
	_event(team, "field_start" if started else "field_end", reason)


## The match ended (Events.match_over): remember who won and why.
func _on_over(winner: int, reason: String) -> void:
	_end_winner = winner
	_end_reason = reason


## Every admiral order's result (AdmiralCommand._done): count ok/failed by
## action, and failures by reason (numbers cut off).
func _on_result(team: int, action: String, ok: bool, msg: String) -> void:
	if team < 0 or team > 1:
		return
	_add(team, "cmd_%s_%s" % [action, "ok" if ok else "fail"])
	if not ok:
		# Cut the numbers off ("no building for 12s" -> "no building for s").
		var key := msg.get_slice("(", 0).strip_edges()
		for d in "0123456789":
			key = key.replace(d, "")
		_add(team, "fail_%s: %s" % [action, key])


## An order of the Admiral's seat was carried out or refused (Events.rts_event): count it by its own kind name.
func _on_order_event(ev: Dictionary) -> void:
	var k := str(ev.get("kind", ""))
	if k != "order_done" and k != "order_refused":
		return
	var data: Dictionary = ev.get("data", {})
	var team := int(ev.get("team", -1))
	if team < 0 or team > 1 or int(data.get("seat", -1)) != Rules.ADMIRAL_SEAT:
		return
	var kind := str(data.get("kind", ""))
	# The most orders of the seat in any 300 ticks (RT8: the cap the next build adds is 20).
	var window: Array = _order_ticks[team]
	var tick := world.tick_count
	window.append(tick)
	while window[0] <= tick - 300:
		window.pop_front()
	c[team]["orders_300_max"] = maxf(float(c[team].get("orders_300_max", 0.0)), float(window.size()))
	if k == "order_done":
		_add(team, "ord_%s_ok" % kind)
	else:
		_add(team, "ord_%s_fail" % kind)
		_add(team, "ord_%s_fail_%s" % [kind, str(data.get("reason", "?"))])
		_add(team, "orders_refused_total")


## Add `n` to counter `k` of team `t`.
func _add(t: int, k: String, n: float = 1.0) -> void:
	c[t][k] = float(c[t].get(k, 0.0)) + n


## Add a line to the timeline (at most 400 lines).
func _event(t: int, what: String, detail: Variant) -> void:
	if ev.size() < 400:
		ev.append([snappedf(world.time, 1.0), t, what, detail])


## Who dealt the killing blow, as a short word.
func _killer(info: DamageInfo) -> String:
	if info == null:
		return "none"
	if info.source_team == Rules.NEUTRAL:
		return "neutral"
	var big := info.source_size >= Rules.SIZE_LARGE
	if info.source_is_pilot:
		return "pilot_big" if big else "pilot_small"
	if info.source_is_minion:
		return "minion"
	var s: Unit = info.source if is_instance_valid(info.source) else null
	if s != null:
		match s.kind:
			Unit.K_TURRET:
				return "turret"
			Unit.K_MOTHERSHIP:
				return "mothership"
			Unit.K_SHIP:
				return "ship_ai_big" if big else "ship_ai_small"
			Unit.K_MINION:
				return "minion"
			Unit.K_MONSTER:
				return "monster"
	return "other"


## Something died (Events.unit_killed). We record deaths of our own
## structures and mining drones: who killed it, where, how old it was.
func _on_killed(unit: Node, info: RefCounted) -> void:
	if world == null or not is_instance_valid(unit):
		return
	var u := unit as Unit
	if u == null or u.team < 0 or u.team > 1:
		return
	var t := u.team
	var di := info as DamageInfo
	var who := _killer(di)
	var age := -1.0
	var uid := u.get_instance_id()
	if _born.has(uid):
		age = world.time - float(_born[uid])
	match u.kind:
		Unit.K_BAY:
			_add(t, "bay_died")
			_add(t, "bay_died_by_" + who)
			if age >= 0.0:
				_add(t, "bay_life_sum", age)
			var b := u as RepairBay
			var lane := world.map.lane_for(u.global_position)
			var pts := MapLayout.lane_points(lane, t)
			var pr := Util.project_on_polyline(u.global_position, pts)
			# Enemy things near it at the time.
			var near_ships := 0
			var near_big := 0
			var near_min := 0
			for s: Ship in world.ships:
				if s.team != t and s.alive and s.global_position.distance_to(u.global_position) < 2500.0:
					if s.size_class >= Rules.SIZE_LARGE:
						near_big += 1
					else:
						near_ships += 1
			for m in world.minions:
				if m.team != t and m.alive and m.global_position.distance_to(u.global_position) < 2500.0:
					near_min += 1
			var own_near := 0
			for m in world.minions:
				if m.team == t and m.alive and m.global_position.distance_to(u.global_position) < 2500.0:
					own_near += 1
			_add(t, "bay_died_" + ("anchored" if b != null and b.is_anchored() else "flying"))
			if deaths.size() < 300:
				deaths.append([snappedf(world.time, 1.0), t, "bay", {"lane": lane, "frac": snappedf(float(pr["s"]) / Util.polyline_length(pts), 0.01),
					"off": roundi(float(pr["dist"])), "age": roundi(age), "by": who, "state": b.state if b != null else "?", "def": b.has_defenses if b != null else false,
					"e_small": near_ships, "e_big": near_big, "e_min": near_min, "own_min": own_near, "x": roundi(u.global_position.x), "y": roundi(u.global_position.y)}])
		Unit.K_WARD:
			_add(t, "ward_died")
			_add(t, "ward_died_by_" + who)
			if age >= 0.0:
				_add(t, "ward_life_sum", age)
		Unit.K_TURRET:
			var tu := u as Turret
			var nk := "?"
			if tu != null and tu.node != null:
				nk = tu.node.node_kind
			_add(t, "turret_died_" + nk)
			_add(t, "turret_died_by_" + who)
			_add(t, "turret_lost_credits", float(TurretData.TURRETS[tu.ttype]["cost"]) if tu != null else 0.0)
		Unit.K_MINING_DRONE:
			_add(t, "drone_died")
			_add(t, "drone_died_by_" + who)
		Unit.K_MOTHERSHIP:
			_event(t, "ms_died", who)


## Every tick: sample both admirals once a second, print the minute lines and,
## when the time is up (or the match is over), print the final JSON line and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		for t in 2:
			if world.admiral_ai[t] != null:
				_sample(t)
	if world.time >= _report_t:
		_report_t += 60.0
		var parts := []
		for t in 2:
			var ts := world.teams[t]
			var ms := world.mothership(t)
			parts.append("T%d tre=%d push=%s wp=%s siege=%s/%s ms_away=%d hull=%.2f bays=%d wards=%d plan=%d" % [t, int(ts.treasury), _last[t].get("push", "-"),
				world.map.lane_for(ts.waypoint) if ts.has_waypoint() else "-", ts.siege_lane, ts.siege_phase,
				roundi(ms.global_position.distance_to(world.map.mothership_pos[t])) if ms != null else -1, ms.hull_frac() if ms != null else 0.0,
				_count(world.bays, t), _count(world.wards, t), (plan_t[t] as Dictionary).size()])
		print("ADM t=%d  %s" % [int(world.time), "  |  ".join(parts)])
	if world.time >= secs or world.phase != "play":
		# A trip still out ends with the run (it gets its FIELD_TRIP line).
		world.end_field_trips("match_end")
		for t in 2:
			var ms := world.mothership(t)
			# The idle runs still going end with the run; the spans of 10 s or more are printed with the counters.
			for sid: int in (_idle_runs[t] as Dictionary).keys():
				_close_idle_run(t, sid)
			c[t]["idle_spans"] = _idle_spans[t]
			for sid: int in (_stuck_runs[t] as Dictionary).keys():
				_close_stuck_run(t, sid)
			c[t]["stuck_spans"] = _stuck_spans[t]
			for sid: int in (_near_runs[t] as Dictionary).keys():
				_close_near_run(t, sid)
			c[t]["idle_near_spans"] = _near_spans[t]
			c[t]["end_ms_hull"] = ms.hull_frac() if ms != null and ms.alive else 0.0
			c[t]["end_treasury"] = world.teams[t].treasury
			# Credits spent on the plan steps that finished.
			var plan_cost := 0.0
			for s: Array in AdmiralPlan.PLAN:
				if (plan_t[t] as Dictionary).has(s[1]):
					plan_cost += float(Tech.FACILITIES[s[1]]["cost"]) if s[0] == "f" else float(Tech.TECHS[s[1]]["cost"])
			c[t]["spent_plan"] = plan_cost
			c[t]["spent_bays"] = float(c[t].get("cmd_bay_ok", 0.0)) * float(Structures.REPAIR_BAY["cost"])
			c[t]["spent_wards"] = float(c[t].get("cmd_ward_ok", 0.0)) * float(Structures.WARD["cost"])
			c[t]["spent_drones"] = float(c[t].get("cmd_drone_ok", 0.0)) * float(Structures.MINING_DRONE["cost"])
			# The event reactions' own counters (AdmiralReactions.stats): the records read, the orders each reaction sent by kind
			# ("react_attack_MOVE_ok" ...), the records missed, and the ore left unspent at a full cap (credit-seconds, thinks, peak).
			var rai := world.admiral_ai[t] as AdmiralAI
			if rai != null and rai.react != null:
				var rs := rai.react.stats()
				for rk: String in rs:
					c[t]["react_" + rk] = float(rs[rk])
			# The fleet layer's counters (RT8 build 8a), only when the layer is on.
			if rai != null and rai.fleet != null:
				var fs := rai.fleet.stats()
				for fk: String in fs:
					c[t]["fleet_" + fk] = float(fs[fk])
				# The base alarm's episodes (an episode still open ends with the match).
				_close_alarm(t, int(_alarm_counts(rai)[2]))
				c[t]["alarm_rows"] = _alarm_rows[t]
				c[t]["alarm_s"] = _alarm_s[t]
		# Each team's field trips (AdmiralField.trips), the first 60 of them.
		var trips := [[], []]
		for t in 2:
			var ai := world.admiral_ai[t] as AdmiralAI
			if ai != null:
				trips[t] = ai.field.trips.slice(0, 60)
		for t in 2:
			var arows: Array = _alarm_rows[t]
			if not arows.is_empty():
				var sums := [0, 0, 0]
				for row: Array in arows:
					for k in 3:
						sums[k] = int(sums[k]) + int(row[2 + k])
				print("ALARM_ROWS team=%d episodes=%d alarm_s=%d fleet_thinks=%d fleet_orders=%d rt5_moves=%d" % [t, arows.size(), int(_alarm_s[t]), sums[0], sums[1], sums[2]])
		print("AUDIT_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "phase": world.phase, "winner": _end_winner, "reason": _end_reason,
			"counters": c, "plan_t": plan_t, "events": ev, "deaths": deaths, "field_trips": trips}))
		get_tree().quit()


## Alive things of team t in list `arr` (bays, wards, turrets).
func _count(arr: Array, t: int) -> int:
	var n := 0
	for u in arr:
		if u.team == t and u.alive:
			n += 1
	return n


## The once-a-second look at team `t`'s admiral: treasury, plan, lanes,
## sieges, mothership, structures and fleet (see the file header).
func _sample(t: int) -> void:
	var ts := world.teams[t]
	var ai := world.admiral_ai[t] as AdmiralAI
	var L: Dictionary = _last[t]
	_add(t, "samples")
	# The admiral's own ship: seconds in space, and how often the admiral has
	# thought (once a second, out or not).
	if ai.field.profile != null and ai.field.profile.state == "flying":
		_add(t, "field_flying_s")
	# Seconds with 2 or more pilots down (the "down" call for the admiral).
	if ai.field.pilots_down() >= AdmiralField.MIN_DOWN:
		_add(t, "pilots_down2_s")
	c[t]["admiral_thinks"] = ai.think_count
	# Treasury: average, peak, time above 2k / 5k / 10k.
	_add(t, "tre_sum", ts.treasury)
	c[t]["tre_max"] = maxf(float(c[t].get("tre_max", 0.0)), ts.treasury)
	for lim in [2000, 5000, 10000]:
		if ts.treasury > lim:
			_add(t, "tre_over_%d_s" % lim)
	# Build plan: when each step got finished.
	for s: Array in AdmiralPlan.PLAN:
		var id: String = s[1]
		var fin: bool = ts.facilities.has(id) if s[0] == "f" else ts.done.has(id)
		if fin and not (plan_t[t] as Dictionary).has(id):
			plan_t[t][id] = snappedf(world.time, 1.0)
	if (plan_t[t] as Dictionary).size() == AdmiralPlan.PLAN.size() and not L.has("plan_done"):
		L["plan_done"] = true
		c[t]["plan_done_t"] = world.time
	# Push lane: share per lane, flips, and agreement with the lane whose
	# minions are furthest as a fraction of the lane's length.
	var pl := ai.lanes.push_lane()
	_add(t, "push_" + (pl if pl != "" else "none"))
	if pl != L.get("push", ""):
		_add(t, "push_flips")
	L["push"] = pl
	var best_f := -1.0
	var best_l := ""
	for lane: String in MapLayout.LANE_ORDER:
		var f := ai.lanes.front_frac(lane)
		if f > best_f:
			best_f = f
			best_l = lane
	_add(t, "fracfront_" + best_l)
	if pl != "" and pl != best_l:
		_add(t, "push_ne_fracfront")
	# Waypoint lane.
	if ts.has_waypoint():
		var wl := world.map.lane_for(ts.waypoint)
		_add(t, "wp_" + wl)
		if wl != L.get("wl", wl):
			_add(t, "wp_flips")
		L["wl"] = wl
	# Where our pilots stand (ships within 2,500 of a lane line count for it).
	for s: Ship in world.ships:
		if s.team == t and s.alive:
			var ln := world.map.lane_for(s.global_position)
			if Util.dist_to_polyline(s.global_position, MapLayout.lane_points(ln, t)) < 2500.0:
				_add(t, "pil_" + ln)
			else:
				_add(t, "pil_other")
	# Sieges.
	var ems := world.mothership(1 - t)
	var sl := ts.siege_lane
	var sp := ts.siege_phase
	if sl != L.get("sl", "") or sp != L.get("sp", ""):
		if L.get("sl", "") == "" and sl != "":
			_add(t, "siege_declared")
			L["siege_start"] = world.time
			L["siege_hp0"] = ems.hull_frac() if ems != null else 1.0
			_event(t, "siege", [sl, snappedf(L["siege_hp0"], 0.01)])
		elif sl == "" and L.get("sl", "") != "":
			_add(t, "siege_off")
			var dur := roundi(world.time - float(L.get("siege_start", world.time)))
			# Why it ended: the defend call renewed this second, or the
			# admiral's own call-off (no big ships / stalled).
			var by_def := ts.defend_until - world.time > 10.5
			var why := "defend" if by_def else "admiral"
			var hp1 := ems.hull_frac() if ems != null and ems.alive else 0.0
			_add(t, "siege_off_" + why)
			_add(t, "siege_off_" + L.get("sp", "") + "_" + why)
			_add(t, "siege_dur_sum", dur)
			_event(t, "siege_off", {"phase": L.get("sp", ""), "dur": dur, "why": why, "hp0": snappedf(float(L.get("siege_hp0", 1.0)), 0.01), "hp1": snappedf(hp1, 0.01)})
		elif sl != L.get("sl", ""):
			_event(t, "siege_lane", sl)
		elif sp != L.get("sp", ""):
			_event(t, "siege_phase", sp)
	L["sl"] = sl
	L["sp"] = sp
	if sl != "":
		_add(t, "siege_s_" + sp)
	# Siege readiness: could the admiral start one now? (After 20:00, two
	# healthy big ships, the edge, no cooldown.) Split by the defend call.
	if sl == "" and world.time >= 1200.0 and world.time >= ai.siege.cooldown_until:
		var healthy := 0
		for s: Ship in world.ships:
			if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE and s.hull_frac() > 0.5:
				healthy += 1
		var edge := ai.lanes.fleet_power(t) >= ai.lanes.fleet_power(1 - t) * 1.2 or (ems != null and ems.hull_frac() <= 0.6)
		if healthy >= AdmiralSiege.MIN_HEALTHY and edge:
			_add(t, "siege_ready_s")
			if ts.defending(world.time):
				_add(t, "siege_ready_blocked_def_s")
	# Enemy mothership hull lost: in total, and while our assault runs.
	if ems != null:
		var hp := ems.hull_frac() if ems.alive else 0.0
		var drop: float = _ms_hp[1 - t] - hp
		if drop > 0.0:
			_add(t, "ems_hull_lost", drop)
			if sp == "assault":
				_add(t, "ems_hull_lost_assault", drop)
		_ms_hp[1 - t] = hp
		# Our bigs near the enemy hull during an assault.
		if sp == "assault":
			var near := 0
			for s: Ship in world.ships:
				if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE and ems.hull_dist(s.global_position) < 3000.0:
					near += 1
			_add(t, "assault_bigs_near_sum", near)
			if near > 0:
				_add(t, "assault_contact_s")
	# Our mothership: moves, time away from home, lane while away.
	var ms := world.mothership(t)
	if ms != null and ms.alive:
		var home: Vector2 = world.map.mothership_pos[t]
		if ms.move_target != Vector2.INF and ms.move_target != L.get("mt", Vector2.INF):
			_add(t, "ms_moves")
			var el := world.map.lane_for(ems.global_position) if ems != null else "-"
			_event(t, "ms_move", {"lane": world.map.lane_for(ms.move_target), "from_home": roundi(ms.move_target.distance_to(home)), "hull": snappedf(ms.hull_frac(), 0.01), "enemy_ms_lane": el})
		L["mt"] = ms.move_target
		if ms.move_target != Vector2.INF:
			_add(t, "ms_moving_s")
		if ms.global_position.distance_to(home) > 2500.0:
			_add(t, "ms_away_s")
			_add(t, "ms_lane_" + world.map.lane_for(ms.global_position))
		if ems != null and ems.alive:
			_add(t, "ms_gap_sum", ms.hull_dist(ems.global_position))
	# Structures and economy.
	_add(t, "bays_sum", _count(world.bays, t))
	_add(t, "wards_sum", _count(world.wards, t))
	_add(t, "turrets_sum", _count(world.turrets, t))
	_add(t, "drones_sum", world.mining_drone_count(t))
	# Idle mining drones: ones with no ore node to work, waiting beside the
	# mothership (MiningDrone state "idle"). Drone-seconds spent idle, and the
	# seconds in which at least one drone was idle.
	var idle := 0
	for d: MiningDrone in world.mining_drones:
		if d.team == t and d.alive and d.state == "idle":
			idle += 1
	_add(t, "drones_idle_sum", idle)
	if idle > 0:
		_add(t, "drones_idle_s")
	for b in world.bays:
		if b.team == t and b.alive and not _born.has(b.get_instance_id()):
			_born[b.get_instance_id()] = world.time
			_add(t, "bays_made")
			var bl := world.map.lane_for(b.anchor)
			_add(t, "bays_made_" + bl)
			_event(t, "bay", {"lane": bl, "anchor": [roundi(b.anchor.x), roundi(b.anchor.y)]})
	for w in world.wards:
		if w.team == t and w.alive and not _born.has(w.get_instance_id()):
			_born[w.get_instance_id()] = world.time
			_add(t, "wards_made")
	for tu in world.turrets:
		if tu.team == t and tu.alive and not _born.has(tu.get_instance_id()):
			_born[tu.get_instance_id()] = world.time
			_add(t, "turrets_made")
			_add(t, "spent_turrets", float(TurretData.TURRETS[tu.ttype]["cost"]))
	# Big ships and fleet power.
	var bigs := 0
	for s: Ship in world.ships:
		if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE:
			bigs += 1
	_add(t, "bigs_sum", bigs)
	if ts.defending(world.time):
		_add(t, "defending_s")
		if ms != null and ms.global_position.distance_to(world.map.mothership_pos[t]) > 2500.0:
			_add(t, "defending_away_s")
	if ai.lanes.fleet_power(t) >= ai.lanes.fleet_power(1 - t) * 1.2:
		_add(t, "fleet_edge_s")
	_sample_idle(t)
	_sample_stuck(t)
	_sample_near(t)
	_sample_alarm(t, ai)


## The three alarm counters of team `ai`'s fleet layer now: [fleet alarm thinks, seat orders its outbox carried out or refused,
## AdmiralReactions Moves carried out]. Only for an Admiral with a fleet layer.
func _alarm_counts(ai: AdmiralAI) -> Array:
	var ob: Dictionary = ai.fleet.outbox.stats()
	var moves := 0
	if ai.react != null:
		moves = int(ai.react.stats().get("attack_MOVE_ok", 0))
	return [int(ai.fleet.counters.get("alarm_thinks", 0)), int(ob.get("ok", 0)) + int(ob.get("fail", 0)), moves]


## The once-a-second look at team `t`'s base alarm (TeamState.defending), only while its Admiral has a fleet layer: opens an
## episode when the alarm rises, keeps the counters seen while it is on and closes it at the first sample after it falls.
func _sample_alarm(t: int, ai: AdmiralAI) -> void:
	if ai.fleet == null:
		return
	var ts := world.teams[t]
	var now := roundi(world.time)
	var cur := _alarm_counts(ai)
	var open: Dictionary = _alarm_open[t]
	if ts.defending(world.time):
		if open.is_empty():
			open = {"first": now, "last": now, "n": 0, "base": _alarm_prev[t], "seen": cur}
			_alarm_open[t] = open
			_event(t, "alarm_on", world.map.lane_for(ts.defend_point))
		open["last"] = now
		open["n"] = int(open["n"]) + 1
		open["seen"] = cur
	elif not open.is_empty():
		_close_alarm(t, int(cur[2]))
	_alarm_prev[t] = cur


## The alarm episode open for team `t` is over (or the match is): keep its row (the Moves counted up to `moves_now`), add its
## seconds to alarm_s and put "alarm_off" on the timeline. Does nothing when no episode is open.
func _close_alarm(t: int, moves_now: int) -> void:
	var open: Dictionary = _alarm_open[t]
	if open.is_empty():
		return
	_alarm_open[t] = {}
	var base: Array = open["base"]
	var seen: Array = open["seen"]
	_alarm_s[t] = int(_alarm_s[t]) + int(open["n"])
	var rows: Array = _alarm_rows[t]
	if rows.size() < ALARM_ROWS_MAX:
		rows.append([int(open["first"]), int(open["last"]), int(seen[0]) - int(base[0]), int(seen[1]) - int(base[1]), moves_now - int(base[2])])
	_event(t, "alarm_off", int(open["n"]))


## The once-a-second look at the bought squadrons of team `t` that have a ship alive and no standing order (the web notes' idle
## squadrons, T-13 note 30). Keeps "idle_squad_max_s" (the longest run of samples one squadron had no order), "idle_stack_max"
## (the most idle squadrons, the squadron itself counted, within IDLE_STACK_RADIUS of one idle squadron's centre in one sample),
## "idle_at_742" and "idle_stack_at_742" (the idle squadrons and the stack at the sample nearest 742 s) and the idle spans
## (runs of IDLE_SPAN_MIN_S or more samples; the rows are printed with the counters at the end).
func _sample_idle(t: int) -> void:
	var now := roundi(world.time)
	var idle: Array = []
	var centres := {}
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team != t or not SquadOrders.is_bought(rec) or not rec.order.is_empty():
			continue
		var sum := Vector2.ZERO
		var n := 0
		for uid: int in rec.member_uids:
			var u: Variant = world.by_uid.get(uid)
			if u != null and is_instance_valid(u) and (u as Unit).alive and u is Ship:
				sum += (u as Ship).global_position
				n += 1
		if n > 0:
			idle.append(id)
			centres[id] = sum / float(n)
	var runs: Dictionary = _idle_runs[t]
	for id: int in runs.keys():
		if not idle.has(id):
			_close_idle_run(t, id)
	for id: int in idle:
		if runs.has(id):
			var run: Array = runs[id]
			run[1] = now
			run[2] = int(run[2]) + 1
		else:
			runs[id] = [now, now, 1]
		c[t]["idle_squad_max_s"] = maxf(float(c[t].get("idle_squad_max_s", 0.0)), float((runs[id] as Array)[2]))
	var stack := 0
	for a: int in idle:
		var near := 0
		for b: int in idle:
			if (centres[a] as Vector2).distance_to(centres[b] as Vector2) <= IDLE_STACK_RADIUS:
				near += 1
		stack = maxi(stack, near)
	c[t]["idle_stack_max"] = maxf(float(c[t].get("idle_stack_max", 0.0)), float(stack))
	var diff := absf(world.time - 742.0)
	if diff < float(_idle_742_diff[t]):
		_idle_742_diff[t] = diff
		c[t]["idle_at_742"] = float(idle.size())
		c[t]["idle_stack_at_742"] = float(stack)
		c[t]["idle_742_sample_s"] = float(now)


## The centre of the living ships of `rec`, or Vector2.INF when it has none.
static func _living_centre(rec: Squad, world: World) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for uid: int in rec.member_uids:
		var u: Variant = world.by_uid.get(uid)
		if u != null and is_instance_valid(u) and (u as Unit).alive and u is Ship:
			sum += (u as Ship).global_position
			n += 1
	return sum / float(n) if n > 0 else Vector2.INF


## Is squadron `rec` parked: a bought squadron with a ship alive whose standing order is a Move to a point and whose living
## ships have their centre within ARRIVED_DIST of that point? (An empty order is the idle counter's case, not this one.)
static func is_parked(rec: Squad, world: World) -> bool:
	if rec == null or not SquadOrders.is_bought(rec):
		return false
	if str(rec.order.get("kind", "")) != OrderKinds.MOVE or not (rec.order.get("target") is Vector2i):
		return false
	var centre := _living_centre(rec, world)
	if centre == Vector2.INF:
		return false
	return centre.distance_to(Vector2(rec.order["target"] as Vector2i)) <= ARRIVED_DIST


## The once-a-second look at the bought squadrons of team `t` that stand parked on a Move's target (the idle counter's
## partner: it sees empty orders only). Keeps "stuck_squad_max_s" (the longest parked run of one squadron, in samples = seconds), "stuck_squads_max"
## (the most squadrons whose run had lasted STUCK_SPAN_MIN_S or more in one sample) and the spans (printed with the counters).
func _sample_stuck(t: int) -> void:
	var now := roundi(world.time)
	var runs: Dictionary = _stuck_runs[t]
	var parked := {}
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team != t or not is_parked(rec, world):
			continue
		parked[id] = true
		var tk := int(rec.order.get("tick", -1))
		if runs.has(id) and int((runs[id] as Array)[3]) == tk:
			var run: Array = runs[id]
			run[1] = now
			run[2] = int(run[2]) + 1
		else:
			_close_stuck_run(t, id)
			runs[id] = [now, now, 1, tk, _span_context(rec, world, _reach)]
		c[t]["stuck_squad_max_s"] = maxf(float(c[t].get("stuck_squad_max_s", 0.0)), float((runs[id] as Array)[2]))
	for id: int in runs.keys():
		if not parked.has(id):
			_close_stuck_run(t, id)
	var long_runs := 0
	for id: int in runs:
		if int((runs[id] as Array)[2]) >= STUCK_SPAN_MIN_S:
			long_runs += 1
	c[t]["stuck_squad_max_s"] = float(c[t].get("stuck_squad_max_s", 0.0))
	c[t]["stuck_squads_max"] = maxf(float(c[t].get("stuck_squads_max", 0.0)), float(long_runs))


## The parked run of squadron `id` of team `t` is over (or the match is): keep it as a span when it lasted long enough.
func _close_stuck_run(t: int, id: int) -> void:
	var runs: Dictionary = _stuck_runs[t]
	if not runs.has(id):
		return
	var run: Array = runs[id]
	runs.erase(id)
	var spans: Array = _stuck_spans[t]
	if int(run[2]) >= STUCK_SPAN_MIN_S and spans.size() < STUCK_SPANS_MAX:
		var row: Array = [id, int(run[0]), int(run[1])]
		row.append_array(run[4] as Array)
		spans.append(row)


## Is squadron `rec` idle-near: a bought squadron with a ship alive whose order is empty or which is parked (is_parked), and an
## enemy ship or minion within `reach` of the centre of its living ships?
static func is_idle_near(rec: Squad, world: World, reach: float) -> bool:
	if rec == null or not SquadOrders.is_bought(rec):
		return false
	var centre := _living_centre(rec, world)
	if centre == Vector2.INF:
		return false
	if not rec.order.is_empty() and not is_parked(rec, world):
		return false
	return _enemies_within(rec.team, centre, world, reach) > 0


## How many living enemy ships and minions (of the side opposing `team`) are within `reach` of point `p`.
static func _enemies_within(team: int, p: Vector2, world: World, reach: float) -> int:
	var n := 0
	for s: Ship in world.ships:
		if s.team != team and s.alive and s.global_position.distance_to(p) <= reach:
			n += 1
	for m in world.minions:
		if m.team != team and m.alive and m.global_position.distance_to(p) <= reach:
			n += 1
	return n


## The three numbers kept at the start of a parked run of squadron `rec`: the distance from its centre to the nearest enemy
## turret (-1 when there is none), the enemy ships and minions within `reach` and our minions within `reach`.
static func _span_context(rec: Squad, world: World, reach: float) -> Array:
	var centre := _living_centre(rec, world)
	var turret_d := -1.0
	for tu in world.turrets:
		if tu.team != rec.team and tu.alive:
			var d: float = tu.global_position.distance_to(centre)
			if turret_d < 0.0 or d < turret_d:
				turret_d = d
	var own := 0
	for m in world.minions:
		if m.team == rec.team and m.alive and m.global_position.distance_to(centre) <= reach:
			own += 1
	return [roundi(turret_d), _enemies_within(rec.team, centre, world, reach), own]


## The once-a-second look at the bought squadrons of team `t` that are idle-near (is_idle_near). Keeps "idle_near_max_s" (the
## longest run of samples one squadron was idle-near), the spans (printed with the counters) and "still_stack_max" (the most
## squadrons that are idle or parked within IDLE_STACK_RADIUS of one such squadron's centre in one sample).
func _sample_near(t: int) -> void:
	var now := roundi(world.time)
	var near: Array = []
	var still: Array = []
	var centres := {}
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team != t or not SquadOrders.is_bought(rec):
			continue
		var centre := _living_centre(rec, world)
		if centre == Vector2.INF:
			continue
		if rec.order.is_empty() or is_parked(rec, world):
			still.append(id)
			centres[id] = centre
			if _enemies_within(t, centre, world, _reach) > 0:
				near.append(id)
	var runs: Dictionary = _near_runs[t]
	for id: int in runs.keys():
		if not near.has(id):
			_close_near_run(t, id)
	for id: int in near:
		if runs.has(id):
			var run: Array = runs[id]
			run[1] = now
			run[2] = int(run[2]) + 1
		else:
			runs[id] = [now, now, 1]
		c[t]["idle_near_max_s"] = maxf(float(c[t].get("idle_near_max_s", 0.0)), float((runs[id] as Array)[2]))
	c[t]["idle_near_max_s"] = float(c[t].get("idle_near_max_s", 0.0))
	var stack := 0
	for a: int in still:
		var close := 0
		for b: int in still:
			if (centres[a] as Vector2).distance_to(centres[b] as Vector2) <= IDLE_STACK_RADIUS:
				close += 1
		stack = maxi(stack, close)
	c[t]["still_stack_max"] = maxf(float(c[t].get("still_stack_max", 0.0)), float(stack))


## The idle-near run of squadron `id` of team `t` is over (or the match is): keep it as a span when it lasted long enough.
func _close_near_run(t: int, id: int) -> void:
	var runs: Dictionary = _near_runs[t]
	if not runs.has(id):
		return
	var run: Array = runs[id]
	runs.erase(id)
	var spans: Array = _near_spans[t]
	if int(run[2]) >= IDLE_SPAN_MIN_S and spans.size() < IDLE_SPANS_MAX:
		spans.append([id, int(run[0]), int(run[1])])


## The idle run of squadron `id` of team `t` is over (or the match is): keep it as a span when it lasted long enough.
func _close_idle_run(t: int, id: int) -> void:
	var runs: Dictionary = _idle_runs[t]
	if not runs.has(id):
		return
	var run: Array = runs[id]
	runs.erase(id)
	var spans: Array = _idle_spans[t]
	if int(run[2]) >= IDLE_SPAN_MIN_S and spans.size() < IDLE_SPANS_MAX:
		spans.append([id, int(run[0]), int(run[1])])
