extends Node
## WHAT THIS IS: the check of the computer Admiral's four event reactions (scripts/ai/admiral_reactions.gd, RT5 build 4a):
## a build that cannot start, a fleet at its cap, the base under attack and pilots lost. Each case sets the scene with the
## test seat's tools (the yard's list, spawn_now, the team's defend call, test pilot records), lets the reactions think by
## hand and reads the orders the Admiral's seat sent from the match's event stream.
##   - BUILD BLOCKED: an item it cannot afford and one that is locked: no second PRODUCE for either, one "not yet" line per
##     reason a minute (and never the same item twice), no CANCEL before the unlock block is 60 s old and one CANCEL for each
##     locked item just after, no refused order.
##   - CAP FULL: the fleet filled to its limit with the Fighter repeat on: SET_REPEAT 0 in one think, the repeat stays off
##     (AdmiralProduction) while an item waits for room, and comes back once none does; with the switch off none of it happens.
##   - UNDER ATTACK: the squadrons within the pilots' reach (12,000 strike craft, 18,000 the rest) get one Move each to the
##     defend point in id order, the others hold; no re-send under 2,000 of movement or inside 5 s; a squadron that comes into
##     reach joins; no Move while our siege survives; every called squadron is sent back to its own rally when the alarm ends.
##   - PILOTS LOST: a pilot's loss counts, a crew ship's loss does not; one dead pilot does nothing, two send the nearest
##     free squadron to the first dead pilot's lane front (the Admiral's own death does not count) and it goes back when fewer
##     are dead; a squadron called to defend does not fill in.
##   - SWITCHES OFF: the same scenes with every switch off give no order, no log line and no change of any squadron, while
##     the records are still counted and the ore at a full cap is still added up.
##
## HOW IT WORKS: setup() makes the world quiet; the cases all run in the first physics tick (the clock, the defend call and
## the pilot records are written by hand and put back). It prints a FAIL line for each failed check and
## "react_check: N failures (M checks)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --test=react_check
##
## WHO USES IT: main.gd loads it for --test=react_check (it calls setup()).

## The running match (set by setup()).
var world: World
## How many checks failed, and how many were made.
var fails := 0
var checks := 0
## True once the cases have run.
var _ran := false
## The defend point the attack cases use (far from every squadron until a case moves them).
const P := Vector2(20000.0, 15000.0)
## The test pilot records that _pilot() gave a brain in the world's list; _reset() takes the brains out again.
var _brained: Array[PilotProfile] = []


func setup(w: World) -> void:
	world = w
	SquadronRules.use_squad_brain = false  # this check pins the stand-in's own internals
	world.minion_director.next_wave = INF


func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	var saved_time := world.time
	_blocked_cases()
	_cap_cases()
	_attack_cases()
	_lost_cases()
	_off_cases()
	_seam_cases()
	_reset(0.0)
	world.time = saved_time
	print("react_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -------------------------------------------------------------------------

func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL %s %s" % [name, detail])


func _ts() -> TeamState:
	return world.teams[0]


func _prod() -> Production:
	return world.teams[0].production


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
	for bp: PilotProfile in _brained:
		world.pilot_ai.erase(bp)
	_brained.clear()
	ts.defend_point = Vector2.INF
	ts.defend_until = 0.0
	ts.siege_lane = ""
	ts.siege_phase = ""
	Game.unlock_everything = false
	ts.admiral = "ai"
	world.time = at


func _run(n: int) -> void:
	for i in n:
		_prod().tick(1.0 / 60.0)


## The profile of a standard Admiral with the switches `on` turned on.
func _prof(on: Array) -> AdmiralProfile:
	var p := AdmiralProfile.make("standard", 0)
	for key: String in on:
		p.set_value(key, 1)
	return p


## Reactions of team 0 with the switches `on`, on the match's own lane helper and field part.
func _react(on: Array) -> AdmiralReactions:
	var ai: AdmiralAI = world.admiral_ai[0]
	return AdmiralReactions.new(world, 0, ai.lanes, ai.field, _prof(on))


## The orders of the Admiral's seat filed since stream index `cursor` (of kind `kind` when it is not "").
func _orders(cursor: int, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in world.events_rts.read_from(0, cursor):
		var k := str(e["kind"])
		if k != "order_done" and k != "order_refused":
			continue
		var d: Dictionary = e["data"]
		if int(d.get("seat", -1)) != Rules.ADMIRAL_SEAT:
			continue
		if kind != "" and str(d.get("kind", "")) != kind:
			continue
		out.append(e)
	return out


func _cursor() -> int:
	return world.events_rts.next_index(0)


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


## The point of the standing Move order of `rec`, or Vector2i(-1, -1) when its order is not a Move.
func _move_target(rec: Squad) -> Vector2i:
	if str(rec.order.get("kind", "")) != OrderKinds.MOVE:
		return Vector2i(-1, -1)
	return Vector2i(rec.order["target"])


func _alarm(point: Vector2, on: bool) -> void:
	var ts := _ts()
	ts.defend_point = point
	ts.defend_until = world.time + 12.0 if on else 0.0


## A test pilot record of team 0 in seat `seat`, with the role `role` and the state `state`, in the world's list.
func _pilot(seat: int, role: String, state: String) -> PilotProfile:
	var p := PilotProfile.new("react%d" % seat, 0, seat, false)
	p.role = role
	p.state = state
	world.profiles.append(p)
	# A seat with no pilot brain is an empty seat and never counts as a pilot down (AdmiralField.pilots_down).
	world.pilot_ai[p] = PilotAI.new(world, p)
	_brained.append(p)
	return p


func _pilot_lost_record() -> void:
	world.events_rts.push({"kind": "ship_lost", "team": 0, "uid": 0, "data": {"squad": 0, "wing": 0}})


# --- build blocked ---------------------------------------------------------------------

func _blocked_cases() -> void:
	_reset(0.0, 100.0)
	var lg := AdmiralLog.of(world)
	var lg_was := lg.enabled
	lg.enabled = true
	var lines0 := lg.lines
	var r := _react(["react_build_blocked"])
	var prod := _prod()
	var fighter := prod.add_ship("fighter", 3)
	var bomber := prod.add_ship("bomber", 3)
	var lance := prod.add_ship("lance", 3)
	_run(3)
	_check("blocked: the fighter lacks ore, the bomber and the lance lack an unlock", fighter["why"] == "ore" and bomber["why"] == "unlock" and lance["why"] == "unlock")
	var cur := _cursor()
	r.think(_ts())
	_check("blocked: the records are counted (one ore, two unlock)", int(r.counters.get("seen_blocked_ore", 0)) == 1 and int(r.counters.get("seen_blocked_unlock", 0)) == 2, str(r.counters))
	_check("blocked: one not-yet line per reason, two items of one reason write one", lg.lines - lines0 == 2, str(lg.lines - lines0))
	var named := 0
	for line: String in lg.recent.slice(-2):
		if line.contains("react.blocked."):
			named += 1
	_check("blocked: the lines are the reactions' own (their rule names)", named == 2, str(lg.recent.slice(-2)))
	r.think(_ts())
	world.time = 130.0
	r.think(_ts())
	_check("blocked: no second line for the same items", lg.lines - lines0 == 2, str(lg.lines - lines0))
	_check("blocked: no PRODUCE, no refused order, no order at all while the block is young", _orders(cur).is_empty(), str(_orders(cur).size()))
	world.time = 159.0
	r.think(_ts())
	_check("blocked: no CANCEL before 60 s of the unlock block", _orders(cur, OrderKinds.CANCEL).is_empty())
	world.time = 161.0
	r.think(_ts())
	var cancels := _orders(cur, OrderKinds.CANCEL)
	_check("blocked: each locked item is cancelled once after 60 s", cancels.size() == 2 and cancels.all(func(e: Dictionary) -> bool: return e["kind"] == "order_done"), str(cancels.size()))
	_check("blocked: the locked items are gone, the fighter waits on", prod.find(str(bomber["id"])).is_empty() and prod.find(str(lance["id"])).is_empty() and not prod.find(str(fighter["id"])).is_empty())
	r.think(_ts())
	world.time = 400.0
	r.think(_ts())
	_check("blocked: no more orders afterwards and none of them was a PRODUCE", _orders(cur).size() == 2 and _orders(cur, OrderKinds.PRODUCE).is_empty())
	# A not-yet line comes again after 60 s for a new item (the rule's gap), not for the same one.
	var more := prod.add_ship("lance", 3)
	_run(1)
	r.think(_ts())
	_check("blocked: a new item blocked after the gap writes a line", lg.lines - lines0 == 3, str(lg.lines - lines0))
	prod.cancel(str(more["id"]))
	lg.enabled = lg_was


# --- cap full ---------------------------------------------------------------------

func _cap_cases() -> void:
	_reset(9000.0)
	var prod := _prod()
	prod.set_repeat("fighter", true)
	var r := _react(["react_cap_full"])
	prod.capacity.reserve(RtsHulls.CAP_IN_FORCE - 2)
	var waiting := prod.add_ship("fighter", 3)
	_run(3)
	_check("cap: the squadron waits for room", waiting["why"] == "room")
	var cur := _cursor()
	r.think(_ts())
	var sets := _orders(cur, OrderKinds.SET_REPEAT)
	_check("cap: one think sends SET_REPEAT 0 for the Fighters", sets.size() == 1 and int(prod.repeat.get("fighter", 1)) == 0, str(sets.size()))
	r.think(_ts())
	_check("cap: and nothing more while it waits", _orders(cur).size() == 1)
	# AdmiralProduction keeps the repeat off while an item waits for room, and turns it on when none does.
	var ai: AdmiralAI = world.admiral_ai[0]
	var yard_on := AdmiralProduction.new(world, 0, ai.lanes, _prof(["react_cap_full"]))
	var yard_off := AdmiralProduction.new(world, 0, ai.lanes, _prof([]))
	yard_on._repeat(prod, true)
	_check("cap: the yard keeps the repeat off while an item waits for room", int(prod.repeat.get("fighter", 1)) == 0)
	yard_off._repeat(prod, true)
	_check("cap: with the switch off the old rule turns the repeat on at once", int(prod.repeat.get("fighter", 0)) == 1)
	prod.set_repeat("fighter", false)
	prod.cancel(str(waiting["id"]))
	yard_on._repeat(prod, true)
	_check("cap: once nothing waits for room the repeat comes back (the fleet is below target)", int(prod.repeat.get("fighter", 0)) == 1)
	# The ore left at a full cap is added up.
	_reset(9000.0)
	var r2 := _react([])
	r2.think(_ts())
	_check("cap: below the limit no ore is counted", r2.float_thinks == 0)
	prod.capacity.reserve(RtsHulls.CAP_IN_FORCE)
	r2.think(_ts())
	r2.think(_ts())
	_check("cap: at the limit the treasury is added up each think", r2.float_thinks == 2 and roundi(r2.float_ore_sum) == 18000 and roundi(r2.float_ore_max) == 9000, str(r2.stats()))


# --- base under attack --------------------------------------------------------------------

func _attack_cases() -> void:
	_reset(0.0, 500.0)
	var a := _squad("fighter", 3)
	var b := _squad("fighter", 3)
	var c := _squad("logistics", 1)
	var d := _squad("support", 1)
	_check("attack: four squadrons were made", a != null and b != null and c != null and d != null)
	if a == null or b == null or c == null or d == null:
		return
	_place(a, P + Vector2(5000.0, 0.0))
	_place(b, P + Vector2(-14000.0, 0.0))
	_place(c, P + Vector2(15000.0, 0.0))
	_place(d, P + Vector2(-20000.0, 0.0))
	_check("attack: the shared reaches are the pilots' 12,000 and 18,000", PilotGoals.DEFEND_REACH_SMALL == 12000.0 and PilotGoals.DEFEND_REACH_BIG == 18000.0 and _prof([]).f("react_reach_small") == 12000.0 and _prof([]).f("react_reach_big") == 18000.0)
	var r := _react(["react_under_attack"])
	var cur := _cursor()
	r.think(_ts())
	_check("attack: no alarm, no order", _orders(cur).is_empty())
	world.events_rts.push({"kind": "mothership_under_attack", "team": 0})
	_alarm(P, true)
	r.think(_ts())
	var moves := _orders(cur, OrderKinds.MOVE)
	_check("attack: two orders, the strike squadron in 12,000 and the corvette in 18,000", moves.size() == 2, str(moves.size()))
	if moves.size() == 2:
		_check("attack: in squad-id order", int((moves[0] as Dictionary)["data"]["squad"]) == a.id and int((moves[1] as Dictionary)["data"]["squad"]) == c.id)
	_check("attack: the called hold the defend point", _move_target(a) == Order.point(P) and _move_target(c) == Order.point(P))
	_check("attack: the others stay (no order)", b.order.is_empty() and d.order.is_empty())
	_check("attack: the hold point the stand-in flies to is the defend point", Standin.hold_point_of(a, world.by_uid[a.member_uids[0]] as Ship) == Vector2(Order.point(P)))
	_check("attack: the alarm record is counted", int(r.counters.get("seen_under_attack", 0)) == 1)
	# No re-send: unchanged point; a small move; a big move inside 5 s.
	world.time = 501.0
	_alarm(P, true)
	r.think(_ts())
	_check("attack: the next think sends nothing", _orders(cur, OrderKinds.MOVE).size() == 2)
	world.time = 510.0
	_alarm(P + Vector2(1500.0, 0.0), true)
	r.think(_ts())
	_check("attack: a defend point that moved 1,500 is not sent again", _orders(cur, OrderKinds.MOVE).size() == 2)
	world.time = 511.0
	var p2 := P + Vector2(2500.0, 0.0)
	_alarm(p2, true)
	r.think(_ts())
	_check("attack: moved over 2,000 and over 5 s since the last send: both are sent again", _orders(cur, OrderKinds.MOVE).size() == 4 and _move_target(a) == Order.point(p2))
	world.time = 512.0
	var p3 := P + Vector2(5000.0, 0.0)
	_alarm(p3, true)
	r.think(_ts())
	_check("attack: a further move 1 s later is held back (at most one send in 5 s)", _orders(cur, OrderKinds.MOVE).size() == 4)
	world.time = 517.0
	r.think(_ts())
	_check("attack: and goes out once 5 s have passed", _orders(cur, OrderKinds.MOVE).size() == 6 and _move_target(c) == Order.point(p3))
	# A squadron that comes into reach joins; one that is already in reach and not called stays out only if it was out.
	_place(d, p3 + Vector2(3000.0, 0.0))
	world.time = 518.0
	r.think(_ts())
	var joined := _orders(cur, OrderKinds.MOVE)
	_check("attack: a squadron that comes into reach joins at the next think, alone", joined.size() == 7 and int((joined[6] as Dictionary)["data"]["squad"]) == d.id and _move_target(d) == Order.point(p3))
	# While our siege survives: no Move.
	_place(b, p3 + Vector2(2000.0, 0.0))
	_ts().siege_lane = "mid"
	world.time = 519.0
	r.think(_ts())
	_check("attack: no Move while our siege survives the alarm", _orders(cur, OrderKinds.MOVE).size() == 7 and b.order.is_empty())
	_ts().siege_lane = ""
	# The alarm ends: everyone called goes back to its own rally.
	_alarm(p3, false)
	world.time = 520.0
	r.think(_ts())
	var back := _orders(cur, OrderKinds.MOVE)
	_check("attack: the alarm over: a Move back for each of the three called", back.size() == 10, str(back.size()))
	_check("attack: each called squadron holds its own rally again", _move_target(a) == a.rally and _move_target(c) == c.rally and _move_target(d) == d.rally)
	_check("attack: the stand-in's hold point is the rally", Standin.hold_point_of(c, world.by_uid[c.member_uids[0]] as Ship) == Vector2(c.rally))
	_check("attack: the one that was never called was never ordered", b.order.is_empty())
	r.think(_ts())
	_check("attack: and nothing after that", _orders(cur, OrderKinds.MOVE).size() == 10)
	_check("attack: the orders per kind are counted", int(r.counters.get("attack_MOVE_ok", 0)) == 10, str(r.counters))


# --- pilots lost ---------------------------------------------------------------------

func _lost_cases() -> void:
	_reset(0.0, 600.0)
	var ai: AdmiralAI = world.admiral_ai[0]
	var near := _squad("fighter", 3)
	var far := _squad("fighter", 3)
	var lane_point := Vector2(ai.lanes.front_point("top"))
	if near == null or far == null:
		_check("lost: two squadrons were made", false)
		return
	_place(near, lane_point + Vector2(800.0, 0.0))
	_place(far, lane_point + Vector2(30000.0, 0.0))
	var admiral := _pilot(Rules.ADMIRAL_SEAT, "admiral", "dead")
	var one := _pilot(2, "bot", "dead")
	var r := _react(["react_ship_lost"])
	var cur := _cursor()
	# A crew ship's loss is no pilot's loss; the Admiral's own is not counted; one dead pilot does nothing.
	world.events_rts.push({"kind": "ship_lost", "team": 0, "uid": 0, "data": {"squad": near.id, "wing": 0}})
	world.events_rts.push({"kind": "ship_lost", "team": 0, "uid": 0, "data": {"squad": 77, "wing": 1}})
	r.think(_ts())
	_check("lost: a crew ship and a wing ship are not pilots", int(r.counters.get("seen_ship_lost", 0)) == 2 and int(r.counters.get("seen_pilot_lost", 0)) == 0)
	_pilot_lost_record()
	r.think(_ts())
	_check("lost: a pilot's loss is counted", int(r.counters.get("seen_pilot_lost", 0)) == 1)
	_check("lost: the Admiral's own death and one dead pilot make no order", _orders(cur).is_empty())
	# The Admiral's own ship lost (its record names a ship that holds the Admiral's seat).
	var ship0 := world.by_uid[far.member_uids[0]] as Ship
	var saved_role := ship0.profile.role
	ship0.profile.role = "admiral"
	world.events_rts.push({"kind": "ship_lost", "team": 0, "uid": ship0.uid, "data": {"squad": 0, "wing": 0}})
	r.think(_ts())
	ship0.profile.role = saved_role
	_check("lost: the Admiral's ship lost is told from a pilot's", int(r.counters.get("seen_admiral_lost", 0)) == 1 and int(r.counters.get("seen_pilot_lost", 0)) == 1)
	# Two pilots dead (the lowest seat holds the top lane): the nearest squadron goes to the top lane's front.
	var two := _pilot(0, "top", "dead")
	_pilot_lost_record()
	r.think(_ts())
	var moves := _orders(cur, OrderKinds.MOVE)
	_check("lost: two dead pilots send one squadron", moves.size() == 1, str(moves.size()))
	_check("lost: the nearest one, to the first dead pilot's lane front", _move_target(near) == Vector2i(lane_point) and far.order.is_empty() and moves.size() == 1 and int((moves[0] as Dictionary)["data"]["squad"]) == near.id)
	r.think(_ts())
	_check("lost: nothing more while they stay down", _orders(cur, OrderKinds.MOVE).size() == 1)
	# The rule the helper above had to follow: a dead seat with no pilot brain is an empty seat, not a pilot down.
	var down_before: int = ai.field.pilots_down()
	var empty_seat := PilotProfile.new("react-empty", 0, 3, false)
	empty_seat.role = "bot"
	empty_seat.state = "dead"
	world.profiles.append(empty_seat)
	var down_after: int = ai.field.pilots_down()
	world.profiles.erase(empty_seat)
	_check("lost: a dead seat with no pilot brain is not a pilot down", down_before == 2 and down_after == down_before, "%d then %d" % [down_before, down_after])
	# Fewer than two are down: it goes back to its rally.
	two.state = "docked"
	r.think(_ts())
	_check("lost: with fewer than two dead it goes back to its rally", _orders(cur, OrderKinds.MOVE).size() == 2 and _move_target(near) == near.rally)
	r.think(_ts())
	_check("lost: and stays there", _orders(cur, OrderKinds.MOVE).size() == 2)
	# A squadron called to defend does not fill in: the next nearest does.
	two.state = "dead"
	_pilot_lost_record()
	var r2 := _react(["react_ship_lost", "react_under_attack"])
	var q := lane_point + Vector2(60000.0, 0.0)
	_place(near, q + Vector2(2000.0, 0.0))
	_place(far, lane_point + Vector2(9000.0, 0.0))
	_alarm(q, true)
	var cur2 := _cursor()
	_pilot_lost_record()
	r2.think(_ts())
	var both := _orders(cur2, OrderKinds.MOVE)
	_check("lost: the squadron called to defend does not fill in, the other one does", both.size() == 2 and int((both[0] as Dictionary)["data"]["squad"]) == near.id and int((both[1] as Dictionary)["data"]["squad"]) == far.id and _move_target(far) == Vector2i(lane_point), str(both.size()))
	world.profiles.erase(admiral)
	world.profiles.erase(one)
	world.profiles.erase(two)
	_alarm(P, false)


# --- every switch off --------------------------------------------------------------------

func _off_cases() -> void:
	_reset(9000.0, 700.0)
	var ai: AdmiralAI = world.admiral_ai[0]
	var lg := AdmiralLog.of(world)
	var lg_was := lg.enabled
	lg.enabled = true
	var lines0 := lg.lines
	var prod := _prod()
	prod.set_repeat("fighter", true)
	var a := _squad("fighter", 3)
	if a == null:
		_check("off: a squadron was made", false)
		return
	_place(a, P + Vector2(1000.0, 0.0))
	var p1 := _pilot(0, "top", "dead")
	var p2 := _pilot(1, "mid", "dead")
	var r := _react([])
	prod.capacity.reserve(RtsHulls.CAP_IN_FORCE - prod.capacity.used() - 2)
	var locked := prod.add_ship("bomber", 3)
	var waiting := prod.add_ship("fighter", 3)
	_run(3)
	_alarm(P, true)
	_pilot_lost_record()
	world.events_rts.push({"kind": "mothership_under_attack", "team": 0})
	var cur := _cursor()
	r.think(_ts())
	world.time = 900.0
	_alarm(P, true)
	r.think(_ts())
	_check("off: no order of any kind", _orders(cur).is_empty(), str(_orders(cur).size()))
	_check("off: no log line", lg.lines == lines0, str(lg.lines - lines0))
	_check("off: the squadron, the repeat and the items are as they were", a.order.is_empty() and int(prod.repeat.get("fighter", 0)) == 1 and not prod.find(str(locked["id"])).is_empty() and not prod.find(str(waiting["id"])).is_empty())
	_check("off: the records are still counted", int(r.counters.get("seen_blocked_unlock", 0)) == 1 and int(r.counters.get("seen_blocked_room", 0)) >= 1 and int(r.counters.get("seen_cap_full", 0)) == 1 and int(r.counters.get("seen_under_attack", 0)) == 1 and int(r.counters.get("seen_pilot_lost", 0)) == 1, str(r.counters))
	_check("off: the ore at the cap is not counted while there is room", r.float_thinks == 0)
	_check("off: the Admiral's own reactions are off in every profile", not ai.react.any_on() and not AdmiralProfile.make("v0", 0).on("react_cap_full") and not AdmiralProfile.make("weak", 1).on("react_under_attack"))
	world.profiles.erase(p1)
	world.profiles.erase(p2)
	_alarm(P, false)
	lg.enabled = lg_was


# --- the seam to AdmiralAI --------------------------------------------------------------------

## A think of the match's own Admiral runs the reactions once (and reads the stream).
func _seam_cases() -> void:
	_reset(0.0, 800.0)
	var ai: AdmiralAI = world.admiral_ai[0]
	var thinks0 := ai.react.thinks
	ai.think_t = 0.0
	ai.tick(0.0)
	_check("seam: one think of the Admiral runs the reactions once", ai.react.thinks == thinks0 + 1, str(ai.react.thinks))
	_check("seam: the cursor has moved on and is not past the stream", ai.react.cursor <=world.events_rts.next_index(0), str(ai.react.cursor))
	_check("seam: the stats name the counters", ai.react.stats().has("thinks") and ai.react.stats().has("missed") and ai.react.stats().has("float_ore_sum"))
