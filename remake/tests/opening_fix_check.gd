extends Node
## WHAT THIS IS: a check of the third-round rules of the AI opening
## (DESIGN.md A14 and C25), in an all-AI match:
##   1. The AI admiral's own waypoint (it goes up at 60 s) does not pull the
##      rally seats (4, 5, 6 and the flex pilot) off their anchors (their own
##      outer lane turrets) in the opening: their goal stays the opening spot.
##   2. A waypoint a human admiral places (AdmiralCommand.set_waypoint with
##      by_human) does: the rally seats of that team leave for it, and the
##      other team's seats stay put.
##   3. The opening cannot start a second time: once our first wave has
##      reached a lane's anchor, a pilot that was away (its opening_done is
##      put back to false by hand) and finds the wave dead is done at once.
##   4. The admiral's first turret bought back: while a team has bought none
##      back, the order AdmiralBuilder tries its sites in starts with the
##      allowed lost outer site that has the most of the team's own pilots and
##      minions within 1,500 (counted here by looking at every ship and minion,
##      not through the spatial hash), the earlier site on a tie, and the usual
##      order when none is near; once the team has bought one back, it is the
##      usual order. The test takes the outer turrets of both teams away once
##      (quietly, at 200 s), stands friendly minions at two of the lost sites,
##      compares the order with the count, and then looks at whether the
##      admiral buys the sites back.
## Prints PASS / FAIL lines.
##
## HOW IT WORKS: _physics_process() runs numbered steps (`step`) by the match
## clock. Every 0.25 s the rally seats are sampled (_sample_rally()): a seat
## counts only when it has been doing the plain opening job (flying, lane
## state, opening on, no fall-back, no turret evasion, no hold point) for the
## last CLEAN_FOR seconds, so a goal that is a moment old does not count.
## Step 0 runs until 70 s with only the AI admirals' waypoints up (check 1's
## samples), puts a human waypoint up for Aurelian, and step 1 samples from
## 72.5 s to 88 s (check 2's samples) and then judges checks 1 and 2. Step 2
## does check 3 at 135 s (it removes the middle-lane minions of both teams
## once). Step 3 runs until 520 s and prints the total. Check 4 compares the
## order with the usual one every 5 s from 20 s on, and runs its scenario at
## 200 s, beside the steps. The match goes on as it is while the checks run.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --test=opening_fix_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>". The last line is "opening_fix_check: N failures"; 0
## means all four rules hold.
##
## WHO USES IT: main.gd loads it for --test=opening_fix_check. It reads the
## AI pilots' brains (PilotAI), the teams (TeamState) and the admiral's
## builder; it changes the match only in the ways above and two more: the first
## minion wave is held back to T_FIRST_WAVE (a wave launches from a defense post
## a third of the way down its lane and reaches the anchor about 16 to 23 s later,
## so with the usual 45 s start the opening is over at about 61 to 69 s, when the AI
## admirals' own waypoints go up), and each AI admiral's waypoint is put up by
## hand at T_AI_AT, by the same order the admiral gives (not a human's).

## Seconds of match time from which check 1 samples the rally seats (the AI
## admirals place their first waypoints at 60.5 to 61.5 s).
const T_AI_FROM := 63.0
## Seconds at which a human waypoint goes up for Aurelian.
const T_HUMAN_AT := 70.0
## Seconds from which check 2 samples (the pilots have had time to react).
const T_HUMAN_FROM := 72.5
## Seconds at which the rally samples end and checks 1 and 2 are judged.
const T_RALLY_TO := 88.0
## Seconds at which check 3 runs.
const T_SECOND_OPENING := 135.0
## Seconds at which the test ends.
const T_END := 520.0
## How long (seconds) a rally seat must have been doing the plain opening job
## to count in a sample.
const CLEAN_FOR := 0.6
## How many samples a rally check needs at least.
const MIN_SAMPLES := 8
## The share of a rally check's samples that must be right.
const SHARE := 0.9
## How far (world units) a pilot's goal may be from its opening spot and still
## count as "at the opening spot".
const SAME_SPOT := 1.0
## How far (world units) away from the opening spot a rally goal has to be to
## count as "pulled away".
const PULLED_AWAY := 300.0
## The disc (world units) around an outer lane site in which own ships count for
## the admiral's first turret bought back (AdmiralBuilder.PRESENCE_R).
const PRESENCE_R := 1500.0
## The match time (seconds) at which the test makes the first minion wave
## launch (MinionDirector.next_wave), so the opening lasts through checks 1 and
## 2 and ends before check 3 at T_SECOND_OPENING.
const T_FIRST_WAVE := 90.0
## The match time (seconds) at which the test puts each AI admiral's own waypoint
## up (the real one goes up at 60 s once a wave is out; the first wave is held back
## here, so no wave is out then).
const T_AI_AT := 60.5
## The match time (seconds) at which check 4 takes the outer turrets away.
const T_REBUY := 200.0
## How long (seconds) after that the admiral has to buy turrets back.
const REBUY_WINDOW := 20.0
## A unit this close (world units) to the edge of that disc is "on the edge":
## the spatial hash can be a few units behind, so such a sample is skipped.
const EDGE_BAND := 60.0

## The running match (set by setup()).
var world: World
## Which step of the test we are on (0-3, then 4 = done).
var step := 0
## How many checks failed so far.
var fails := 0
## True once the AI admirals' waypoints were put up (T_AI_AT).
var _ai_marked := false
## The match time of the next rally sample.
var _next_rally := 0.0
## The match time of the next check-4 sample.
var _next_sample := 20.0
## Per brain (key: its instance id): the match time at which it was last NOT
## plainly doing the opening job.
var _unclean := {}
## Rally samples, key "a0", "a1" (AI waypoint only, team 0 / 1) and "h0", "h1"
## (after the human waypoint): [seat samples, samples that were right]. Right
## means "goal on the opening spot", except for "h0": "goal pulled away".
var _rally := {"a0": [0, 0], "a1": [0, 0], "h0": [0, 0], "h1": [0, 0]}
## Per team: was the AI admiral's waypoint up (and not a human's) when the
## human waypoint was placed?
var _ai_waypoint_up := [false, false]
## How many times check 4 compared the builder's order with the count of own
## ships near the lost outer sites (two teams, once each).
var _compared := 0
## How many of those had a team that had bought none back and a lost allowed
## outer site with some of its ships near.
var _active := 0
## How many of those put a site other than the first of the usual order first.
var _moved := 0
## How many comparisons were skipped (a unit on the edge of a disc).
var _skipped := 0
## Where check 4's scenario is: 0 = waiting for T_REBUY, 1 = the turrets are
## taken away (compare on the next tick), 2 = waiting REBUY_WINDOW seconds, 3 =
## done.
var _rebuy := 0
## The match time (seconds) at which check 4's scenario started.
var _rebuy_t := 0.0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = T_FIRST_WAVE


## Every tick: the rally sample and the check-4 sample when due, then the step
## whose time has come.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= _next_rally and world.time < T_RALLY_TO:
		_next_rally = world.time + 0.25
		_sample_rally()
	if world.time >= _next_sample and step < 4:
		_next_sample += 5.0
		_sample_order()
	_rebuy_step()
	if not _ai_marked and world.time >= T_AI_AT:
		_ai_marked = true
		for t in 2:
			var ai0: AdmiralAI = world.admiral_ai[t]
			world.command.set_waypoint(t, ai0.lanes.lane_point("mid", 0.55), false, false)
	match step:
		0:
			if world.time >= T_HUMAN_AT:
				# Both AI waypoints should be up by now. A human admiral for
				# Aurelian then places a waypoint on the middle lane (the spot
				# the AI picks), the way the command overlay does.
				for t in 2:
					_ai_waypoint_up[t] = world.teams[t].has_waypoint() and not world.teams[t].waypoint_by_human
				var ai: AdmiralAI = world.admiral_ai[0]
				world.command.set_waypoint(0, ai.lanes.lane_point("mid", 0.55), true, true)
				step = 1
		1:
			if world.time >= T_RALLY_TO:
				_judge_rally()
				step = 2
		2:
			if world.time >= T_SECOND_OPENING:
				_check_second_opening_blocked()
				step = 3
		3:
			if world.time >= T_END:
				_check("first turret bought back: rule compared with the count", _rebuy == 3 and _compared >= 1 and _active >= 1, "%d compared, %d with ships near a lost outer site (%d put a later site first), %d skipped" % [_compared, _active, _moved, _skipped])
				print("opening_fix_check: %d failures" % fails)
				step = 4
				get_tree().quit()


## Move check 4's scenario on (see _rebuy).
func _rebuy_step() -> void:
	if _rebuy == 0 and world.time >= T_REBUY:
		_rebuy_take_away()
		_rebuy = 1
		_rebuy_t = world.time
	elif _rebuy == 1:
		_rebuy_compare()
		_rebuy = 2
	elif _rebuy == 2 and world.time >= _rebuy_t + REBUY_WINDOW:
		_rebuy_judge()
		_rebuy = 3


## Record one check.
func _check(what: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])


## One rally sample: note which rally seats are not plainly doing the opening
## job, and, for the ones that are (for CLEAN_FOR seconds), count whether their
## goal is on their opening spot (before the human waypoint and for Vhorr) or
## pulled away from it (Aurelian, after the human waypoint).
func _sample_rally() -> void:
	for p: PilotProfile in world.profiles:
		var brain: PilotAI = world.pilot_ai.get(p)
		if p.is_human or brain == null or not (p.slot in [4, 5, 6] or p.role == "flex"):
			continue
		var ship := p.ship
		var id := brain.get_instance_id()
		var flying := ship != null and is_instance_valid(ship) and ship.alive
		if not flying or brain.state != "lane" or brain.opening_done or brain.fallback_t > 0.0 or brain.evade_t > 0.0 or brain.hold_point != Vector2.INF:
			_unclean[id] = world.time
			continue
		if world.time - float(_unclean.get(id, -99.0)) < CLEAN_FOR:
			continue
		var gap := brain.goal.distance_to(brain.goals.opening_goal(ship))
		var key := ""
		var right := gap <= SAME_SPOT
		if world.time >= T_HUMAN_FROM:
			key = "h%d" % p.team
			right = gap > PULLED_AWAY if p.team == 0 else gap <= SAME_SPOT
		elif world.time >= T_AI_FROM and world.time < T_HUMAN_AT:
			key = "a%d" % p.team
		if key != "":
			var r: Array = _rally[key]
			r[0] = int(r[0]) + 1
			if right:
				r[1] = int(r[1]) + 1


## Checks 1 and 2, from the rally samples (check 1 over both teams together).
func _judge_rally() -> void:
	# Check 1 counts both teams together (a team whose rally seats were all
	# away or fighting in the window has too few clean samples on its own).
	var a0: Array = _rally["a0"]
	var a1: Array = _rally["a1"]
	var a_all := int(a0[0]) + int(a1[0])
	var a_right := int(a0[1]) + int(a1[1])
	_check("AI waypoints ignored in the opening", _ai_waypoint_up[0] and _ai_waypoint_up[1] and a_all >= MIN_SAMPLES and float(a_right) >= SHARE * float(a_all),
			"AI waypoints up: %s and %s, %d of %d rally-seat samples on the opening spot (Aurelian %d of %d, Vhorr %d of %d)" % [_ai_waypoint_up[0], _ai_waypoint_up[1], a_right, a_all, int(a0[1]), int(a0[0]), int(a1[1]), int(a1[0])])
	var h0: Array = _rally["h0"]
	_check("human waypoint obeyed in the opening (Aurelian)", world.teams[0].has_waypoint() and world.teams[0].waypoint_by_human and int(h0[0]) >= MIN_SAMPLES and float(h0[1]) >= SHARE * float(h0[0]),
			"by a human: %s, %d of %d rally-seat samples more than %d from the opening spot" % [world.teams[0].waypoint_by_human, int(h0[1]), int(h0[0]), int(PULLED_AWAY)])
	var h1: Array = _rally["h1"]
	_check("AI waypoint still ignored (Vhorr)", world.teams[1].has_waypoint() and not world.teams[1].waypoint_by_human and int(h1[0]) >= MIN_SAMPLES and float(h1[1]) >= SHARE * float(h1[0]),
			"%d of %d rally-seat samples on the opening spot" % [int(h1[1]), int(h1[0])])


## Check 3: the first wave has reached the mid lane's anchor (noted in
## TeamState.first_wave_at); a pilot of the middle lane whose opening_done is
## put back to false, with the middle-lane wave dead, is done at once.
func _check_second_opening_blocked() -> void:
	for team in 2:
		var ts := world.teams[team]
		var noted := ts.first_wave_at.has("mid")
		var victim: PilotAI = null
		for p: PilotProfile in world.profiles:
			var brain: PilotAI = world.pilot_ai.get(p)
			if not p.is_human and brain != null and p.team == team and brain.goals.opening_lane() == "mid":
				victim = brain
				break
		if victim == null:
			_check("no second opening (team %d)" % team, false, "no pilot with the middle lane")
			continue
		# The pilot was away when the wave arrived; the wave has died since.
		victim.opening_done = false
		var dead := []
		for m in world.minions:
			if m.team == team and m.alive and m.lane == "mid":
				dead.append(m)
		for m in dead:
			world.combat.kill_silently(m)
		var front := victim.goals.wave_front_s("mid", team)
		var active := victim.goals.opening_active()
		_check("no second opening (team %d)" % team, noted and front < 0.0 and not active and victim.opening_done,
				"first mid wave noted: %s, front after the kills: %.0f, opening active again: %s" % [ts.first_wave_at.get("mid", "no"), front, active])


## Check 4, the periodic sample: while a team has bought no lane turret back and
## none of its sites is open, the admiral's order is the usual one (the first
## node of the usual order comes first).
func _sample_order() -> void:
	for team in 2:
		var ai: AdmiralAI = world.admiral_ai[team]
		if ai == null or _lost_outer(team) or ai.builder.rebought > 0:
			continue
		var order: Array = ai.builder.rebuy_order()
		var usual: Array = ai.builder._nodes_in_order()
		# The order always holds every node once.
		if order.size() != world.nodes.size():
			_check("first turret bought back: order complete (team %d)" % team, false, "%d nodes in the order, %d on the map" % [order.size(), world.nodes.size()])
			continue
		if order[0] != usual[0]:
			_check("first turret bought back: usual order with nothing lost (team %d, t=%.0f)" % [team, world.time], false, "starts with %s, the usual order with %s" % [order[0].node_id, usual[0].node_id])


## True when team `team` has an outer lane site without a turret of its own.
func _lost_outer(team: int) -> bool:
	for n: ResourceNode in world.nodes:
		if n.node_kind == "outer" and n.side == team and n.turret_count(team) == 0:
			return true
	return false


## Check 4, the scenario, part 1 (at T_REBUY): both teams lose their three outer
## turrets (quietly: no reward and no rebuild lock), and own minions stand at
## the lost sites of the mid lane (two of them) and the top lane (one), for each
## team. The count of ships near each site is read a tick later (part 2), when
## the spatial hash has them.
func _rebuy_take_away() -> void:
	for t: Turret in world.turrets.duplicate():
		if t.node != null and t.node.node_kind == "outer":
			world.combat.kill_silently(t)
	var minions_at := {"mid": 2, "top": 1}
	for n: ResourceNode in world.nodes:
		if n.node_kind == "outer" and minions_at.has(n.lane):
			for k in int(minions_at[n.lane]):
				world.spawn_minion(n.side, "fighter", n.lane, n.global_position + Vector2(-300.0 + 40.0 * float(k), 0.0))

## Check 4, the scenario, part 2 (a tick after part 1): compare each admiral's
## order with the count of own ships near each lost outer site.
func _rebuy_compare() -> void:
	for team in 2:
		var ai: AdmiralAI = world.admiral_ai[team]
		if ai == null:
			continue
		var order: Array = ai.builder.rebuy_order()
		var usual: Array = ai.builder._nodes_in_order()
		if order.size() != world.nodes.size():
			_check("first turret bought back: order complete (team %d)" % team, false, "%d nodes in the order, %d on the map" % [order.size(), world.nodes.size()])
			continue
		# What the order should start with: the usual order's first node, or, while
		# the team has bought none back, the allowed lost outer site with the most
		# own ships near (the earlier one in the usual order on a tie).
		var expect: ResourceNode = usual[0]
		var best := 0
		var edge := false
		if ai.builder.rebought == 0:
			for n: ResourceNode in usual:
				if n.node_kind != "outer" or n.side != team or n.turret_count(team) > 0 or world.command.turret_blocker(team, n.node_id, "pd") != "":
					continue
				var inside := _count_near(team, n.global_position, PRESENCE_R)
				if inside != _count_near(team, n.global_position, PRESENCE_R + EDGE_BAND) or inside != _count_near(team, n.global_position, PRESENCE_R - EDGE_BAND):
					edge = true
				if inside > best:
					best = inside
					expect = n
		if edge:
			_skipped += 1
			continue
		_compared += 1
		if ai.builder.rebought == 0 and best > 0:
			_active += 1
			if expect != usual[0]:
				_moved += 1
		if order[0] != expect:
			_check("first turret bought back: order (team %d, t=%.0f)" % [team, world.time], false, "starts with %s, the count says %s (%d ships near), bought back so far: %d" % [order[0].node_id, expect.node_id, best, ai.builder.rebought])


## Check 4, the scenario, part 3 (REBUY_WINDOW seconds after part 1): each admiral
## has bought a lane turret back, or could not (a site blocked, or not enough
## money for one).
func _rebuy_judge() -> void:
	for team in 2:
		var ai: AdmiralAI = world.admiral_ai[team]
		if ai == null:
			continue
		var back := 0
		var blocked := 0
		for n: ResourceNode in world.nodes:
			if n.node_kind == "outer" and n.side == team:
				if n.turret_count(team) > 0:
					back += 1
				elif world.command.turret_blocker(team, n.node_id, "pd") != "":
					blocked += 1
		var poor: bool = not world.teams[team].can_afford(float(TurretData.TURRETS["pd"]["cost"]))
		_check("lost outer turrets bought back (team %d)" % team, back >= 1 or blocked == 3 or poor, "%d of 3 outer sites have a turret, %d are blocked, the admiral's count: %d, can pay: %s" % [back, blocked, ai.builder.rebought, not poor])


## How many live ships and minions of `team` are within `r` of point `p`,
## counted by looking at every one of them.
func _count_near(team: int, p: Vector2, r: float) -> int:
	var count := 0
	for s in world.ships:
		if s.team == team and s.alive and s.global_position.distance_to(p) < r:
			count += 1
	for m in world.minions:
		if m.team == team and m.alive and m.global_position.distance_to(p) < r:
			count += 1
	return count
