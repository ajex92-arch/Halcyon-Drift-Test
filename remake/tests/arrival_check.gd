extends Node
## WHAT THIS IS: the exact check for how bought ships arrive (Arrivals): where each ship
## appears, that the three ships of a squadron appear on one tick, where a capital ship's warp
## spot is (also after the mothership moved, and clear of what stands there), what an outage of
## the mothership does, and what the item's state text says at each step. It also checks the
## stand-in brain a bought ship gets, and that the fleet limit is held and given back.
##
## HOW IT WORKS: it runs in a small world, in the first tick, and drives team 0's build list by
## hand (Production.add_ship, Production.tick, setting an item's `done` count so it does not
## have to wait 20 or 60 seconds). It reads the ships, the squad record, the events and the
## state texts after each step.
##   - Slots: a squadron's ships stand at the mothership's launch spots numbered from the
##     record's id modulo 5, wrapping, one spot each; a corvette takes the first one.
##   - One tick: the ships of a squadron appear on one tick, one "ship_built" each.
##   - States: "waiting: ore (needs N)", "building N%", "waiting: mothership" and gone.
##   - Warp: the streak starts for the last 240 ticks ("launching"), the spot is the first free
##     one of the seven angles, found again after the mothership moved and skipping what
##     stands there; the ship is not in the game until the last tick.
##   - Outage: a mothership with a systems failure holds a squadron and a capital ship
##     until the first tick it can launch.
##   - Stand-in: the brain's skill and hold point, "just launched" every tick, a retreat turned
##     back into the lane job, no dock.
##   - Fleet limit: reserved at the start, the living ships count, a dead ship gives its place
##     back, a repeat stops at the limit and at the list depth.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=arrival_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <case> <details>" or "FAIL <case>
## <details>". The last line is "arrival_check: N failures (M checks)"; 0 failures means ships
## arrive as written.
##
## WHO USES IT: main.gd loads it for --test=arrival_check; run_checks runs it.

## One tick, in seconds.
const DT := 1.0 / 60.0

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True once the cases have run (they all run in the first tick).
var _ran := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF


## Run every case in the first tick, print the result and quit.
func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	_slot_cases()
	_state_cases()
	_warp_cases()
	_outage_cases()
	_stand_in_cases()
	_limit_cases()
	_reset(0.0)
	print("arrival_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------

## Print one PASS or FAIL line for the check `name` (`ok` = it passed), and count it.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Team 0's state.
func _ts() -> TeamState:
	return world.teams[0]


## Team 0's build list.
func _prod() -> Production:
	return world.teams[0].production


## Team 0's mothership.
func _ms() -> Mothership:
	return world.mothership(0)


## Put team 0 back to an empty list and fleet and `money` credits: every bought ship is taken
## out quietly, the records and queues are cleared, the mothership works.
func _reset(money: float = 0.0) -> void:
	var p := _prod()
	for s: Ship in world.ships.duplicate():
		if s.profile != null and s.profile.is_crew:
			world.combat.kill_silently(s)
	p.items.clear()
	p.repeat.clear()
	p.fx.clear()
	p.standins.clear()
	p.capacity.reserved = 0
	p._cap_blocked = false
	for id: int in world.squads.keys():
		world.squads.erase(id)
	_ts().research.clear()
	_ts().building.clear()
	_ts().drone_queue.clear()
	_ts().treasury = money
	_ms().failure_t = 0.0
	Game.unlock_everything = false
	_ts().admiral = "ai"


## Run team 0's build list for `n` ticks (the world's tick count goes up with it, since events
## carry it).
func _run(n: int) -> void:
	for i in n:
		world.tick_count += 1
		_prod().tick(DT)


## Unlock the Destroyer for team 0.
func _unlock_capital() -> void:
	_ts().done["destroyerChassis"] = true
	_ts().facilities["capital"] = true


## The crew ships of squad `sq`, in stored order.
func _ships_of(sq: Squad) -> Array:
	var out: Array = []
	for uid: int in sq.member_uids:
		var u: Variant = world.by_uid.get(uid)
		if u != null and is_instance_valid(u):
			out.append(u)
	return out


## The "ship_built" events of team 0 since index `cursor`.
func _built(cursor: int) -> Array:
	var out: Array = []
	for e: Dictionary in world.events_rts.read_from(0, cursor):
		if e["kind"] == "ship_built":
			out.append(e)
	return out


# --- the cases ---------------------------------------------------------------------

## Where the ships stand when they arrive.
func _slot_cases() -> void:
	_reset(0.0)
	var p := _prod()
	var ms := _ms()
	var it := p.spawn_now("fighter", 3)
	var sq: Squad = world.squads.get(int(it["squad"])) as Squad
	_check("slots: the squad record has its three ships", sq != null and sq.member_uids.size() == 3 and sq.kind == "squadron" and sq.brain == "standin")
	var ships := _ships_of(sq)
	var ok := ships.size() == 3
	var spots := {}
	for i in ships.size():
		var want := ms.launch_point((sq.id + i) % 5, float(Ships.get_def("fighter")["radius"]))
		ok = ok and (ships[i] as Ship).global_position.distance_to(want) < 0.01
		spots[(sq.id + i) % 5] = true
	_check("slots: the ships stand at the launch spots from the record's id modulo 5, wrapping", ok, "id %d" % sq.id)
	_check("slots: three different spots", spots.size() == 3)
	_check("slots: the ships face the way the mothership does", ships.size() == 3 and absf(angle_difference((ships[0] as Ship).rotation, ms.rotation)) < 0.001)
	var c := p.spawn_now("logistics", 1)
	var sq2: Squad = world.squads.get(int(c["squad"])) as Squad
	var cs := _ships_of(sq2)
	_check("slots: a corvette takes the first spot of its record", cs.size() == 1 and (cs[0] as Ship).global_position.distance_to(ms.launch_point(sq2.id % 5, float(Ships.get_def("logistics")["radius"]))) < 0.01 and sq2.kind == "ship")
	_check("slots: every ship has a crew in the world's list that is flying", cs.size() == 1 and (cs[0] as Ship).profile.is_crew and (cs[0] as Ship).profile.state == "flying" and world.profiles.has((cs[0] as Ship).profile))
	_check("slots: the rally is a point ahead of the bow", sq.rally != Vector2i.ZERO and Vector2(sq.rally).distance_to(ms.global_position) > ms.half_len + 1000.0, str(sq.rally))
	_check("slots: the fleet counts the ships and holds no place", p.capacity.alive() == 4 and p.capacity.reserved == 0, "alive %d reserved %d" % [p.capacity.alive(), p.capacity.reserved])


## The state text at each step, and the one-tick arrival of the three ships.
func _state_cases() -> void:
	_reset(100.0)
	var p := _prod()
	var cur: int = world.events_rts.next_index(0)
	var it := p.add_ship("fighter", 3)
	_run(2)
	_check("states: waiting for ore says what it needs", p.state_text(it) == "waiting: ore (needs 350)", p.state_text(it))
	_ts().treasury = 5000.0
	_run(1)
	_check("states: started it says building 0%", p.state_text(it) == "building 0%", p.state_text(it))
	it["done"] = 600
	_check("states: halfway it says building 50%", p.state_text(it) == "building 50%", p.state_text(it))
	var before := world.ships.size()
	it["done"] = int(it["ticks"]) - 1
	_run(1)
	_check("states: the three ships appear on one tick", world.ships.size() == before + 3 and p.find(str(it["id"])).is_empty(), "%d -> %d" % [before, world.ships.size()])
	var built := _built(cur)
	_check("states: one ship_built each, all on the same tick", built.size() == 3 and int(built[0]["tick"]) == int(built[1]["tick"]) and int(built[1]["tick"]) == int(built[2]["tick"]), str(built.size()))
	_check("states: the places the build reserved became living ships", p.capacity.reserved == 0 and p.capacity.used() == 3)
	var sq: Squad = null
	for id: int in world.squads:
		sq = world.squads[id]
	_check("states: the squad record is idle and holds the three uids", sq != null and sq.state == 0 and sq.member_uids.size() == 3)
	var uids_ok := built.size() == 3
	for e: Dictionary in built:
		uids_ok = uids_ok and sq != null and sq.member_uids.has(int(e["uid"]))
	_check("states: each event names its ship and the squad", uids_ok)


## A capital ship's warp: the streak, the spot, a moved mothership, what stands in the way.
func _warp_cases() -> void:
	_reset(9000.0)
	_unlock_capital()
	var p := _prod()
	var ms := _ms()
	var it := p.add_ship("destroyer", 1)
	_run(1)
	_check("warp: a Destroyer starts and pays", it["running"] and absf(_ts().treasury - 6800.0) < 0.001, p.state_text(it))
	var r := float(Ships.get_def("destroyer")["radius"])
	var dist := ms.half_len + ms.beam * 0.5 + r + 200.0
	it["done"] = int(it["ticks"]) - RtsHulls.WARP_TICKS - 1
	var before := world.ships.size()
	_run(1)
	_check("warp: the streak starts for the last 240 ticks and the ship is not in the game", it["warp"] and p.state_text(it) == "launching" and world.ships.size() == before, p.state_text(it))
	var spot := Vector2(float(it["spot_x"]), float(it["spot_y"]))
	_check("warp: the spot is beside the mothership at the first angle", absf(spot.distance_to(ms.global_position) - dist) < 1.5 and absf(angle_difference((spot - ms.global_position).angle(), ms.rotation + deg_to_rad(90.0))) < 0.01, "%.1f from the centre, wanted %.1f" % [spot.distance_to(ms.global_position), dist])
	var streak := 0
	for e: Dictionary in p.fx:
		if e["kind"] == "warp":
			streak += 1
	_check("warp: the streak's drawing data are there", streak == 1)
	it["done"] = int(it["ticks"]) - 1
	_run(1)
	var s := _newest_ship()
	_check("warp: the ship appears at the spot on the last tick", s != null and s.global_position.distance_to(spot) < 1.0 and p.find(str(it["id"])).is_empty() and world.ships.size() == before + 1)
	# Another team's mothership moved: the spot is found again around the new place.
	_reset(0.0)
	var old_pos := ms.global_position
	ms.global_position = old_pos + Vector2(2500.0, -1800.0)
	var spot2 := Arrivals.warp_spot(world, ms, "destroyer")
	_check("warp: after the mothership moved the spot is around its new place", absf(Vector2(spot2).distance_to(ms.global_position) - dist) < 1.5, "%.1f" % Vector2(spot2).distance_to(ms.global_position))
	# Something stands on the first spot: the next one is taken.
	var first := Vector2(Arrivals.warp_spot(world, ms, "destroyer"))
	var blocker := _crew_ship_at(first)
	world.registry.rebuild_hashes()
	var spot3 := Vector2(Arrivals.warp_spot(world, ms, "destroyer"))
	var second := ms.global_position + Vector2.from_angle(ms.rotation + deg_to_rad(-90.0)) * dist
	_check("warp: a ship on the first spot makes it take the second", first.distance_to(spot3) > 100.0 and spot3.distance_to(second) < 1.5, "%s" % str(spot3))
	# Every spot is blocked: the first is taken anyway.
	var blockers: Array = [blocker]
	for deg in [-90, 45, -45, 135, -135, 0]:
		blockers.append(_crew_ship_at(ms.global_position + Vector2.from_angle(ms.rotation + deg_to_rad(float(deg))) * dist))
	world.registry.rebuild_hashes()
	var spot4 := Vector2(Arrivals.warp_spot(world, ms, "destroyer"))
	_check("warp: with every spot taken the first is used anyway", spot4.distance_to(first) < 1.5, "%s vs %s" % [str(spot4), str(first)])
	ms.global_position = old_pos
	world.registry.rebuild_hashes()
	_reset(0.0)


## A newly arrived bought ship (the last one in the world's ship list).
func _newest_ship() -> Ship:
	for i in range(world.ships.size() - 1, -1, -1):
		var s: Ship = world.ships[i]
		if s.profile != null and s.profile.is_crew:
			return s
	return null


## A crew Fighter of team 0 standing at `at`, made through the yard, still.
func _crew_ship_at(at: Vector2) -> Ship:
	var it := _prod().spawn_now("fighter", 1)
	var sq: Squad = world.squads.get(int(it["squad"])) as Squad
	var s := _ships_of(sq)[0] as Ship
	s.global_position = at
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## An outage of the mothership holds the arrivals until it ends.
func _outage_cases() -> void:
	_reset(9000.0)
	_unlock_capital()
	var p := _prod()
	var ms := _ms()
	var it := p.add_ship("fighter", 3)
	_run(1)
	it["done"] = int(it["ticks"]) - 1
	ms.failure_t = 5.0
	var before := world.ships.size()
	_run(3)
	_check("outage: a complete squadron does not appear while the mothership cannot launch", world.ships.size() == before and p.state_text(it) == "waiting: mothership", p.state_text(it))
	_check("outage: and has paid, kept its place and is still building", it["running"] and p.capacity.reserved == 3 and int(it["paid"]) == 450)
	ms.failure_t = 0.0
	_run(1)
	_check("outage: the ships appear on the first tick it can launch", world.ships.size() == before + 3 and p.find(str(it["id"])).is_empty())
	var cap := p.add_ship("destroyer", 1)
	_run(1)
	cap["done"] = int(cap["ticks"]) - 1
	ms.failure_t = 5.0
	before = world.ships.size()
	_run(3)
	_check("outage: a complete capital ship waits too", world.ships.size() == before and p.state_text(cap) == "waiting: mothership", p.state_text(cap))
	ms.failure_t = 0.0
	_run(1)
	_check("outage: and warps in when the outage ends", world.ships.size() == before + 1)
	_reset(0.0)


## The stand-in brain of a bought ship.
func _stand_in_cases() -> void:
	_reset(0.0)
	var p := _prod()
	var it := p.spawn_now("fighter", 1)
	var sq: Squad = world.squads.get(int(it["squad"])) as Squad
	var ship := _ships_of(sq)[0] as Ship
	var ai := ship.controller as PilotAI
	_check("stand-in: the ship flies on a pilot brain at skill 0.77", ai != null and absf(ai.skill - RtsHulls.STANDIN_SKILL) < 0.0001)
	_check("stand-in: its hold point is the squadron's rally", ai != null and ai.hold_point.distance_to(Vector2(sq.rally)) < 0.01)
	world.time += 400.0
	Standin.keep_alive(world, p)
	_check("stand-in: it is told it has just launched every tick (so it never shops)", ai != null and absf(ai.launched_at - world.time) < 0.001 and ai.shopping.wants_shopping(ship) == "")
	# A retreat becomes the lane job again.
	ai.state = "retreat"
	ai.soft_retreat = true
	ship.controls.dock = true
	Standin._think(world, ship, ai)
	_check("stand-in: a retreat is turned back into the lane job with the hold point as its goal", ai.state == "lane" and not ai.soft_retreat and ai.goal.distance_to(ai.hold_point) < 0.01 and not ship.controls.dock)
	# A Stop order holds where the ship is; a Move order holds at its point.
	sq.order = {"kind": OrderKinds.MOVE, "target_kind": "point", "target": Vector2i(123, -456), "tick": 1, "settings": {}}
	Standin._think(world, ship, ai)
	_check("stand-in: a Move order is the hold point", ai.hold_point.distance_to(Vector2(123, -456)) < 0.01)
	sq.order = {"kind": OrderKinds.STOP, "target_kind": "none", "target": 0, "tick": 2, "settings": {}}
	ship.global_position = Vector2(77, 88)
	Standin._think(world, ship, ai)
	_check("stand-in: a Stop order holds where the ship is", ai.hold_point.distance_to(Vector2(77, 88)) < 0.01)
	# Ordered to retreat, the brain is left alone.
	sq.order = {"kind": OrderKinds.RETREAT, "target_kind": "none", "target": 0, "tick": 3, "settings": {}}
	ai.state = "retreat"
	Standin._think(world, ship, ai)
	_check("stand-in: ordered to retreat it retreats", ai.state == "retreat")
	# A pilot's brain is not touched by the hook.
	var pilot_ai: PilotAI = null
	for pp: PilotProfile in world.pilot_ai:
		pilot_ai = world.pilot_ai[pp]
		break
	if pilot_ai != null:
		var st := pilot_ai.state
		pilot_ai.state = "retreat"
		Standin._think(world, ship, pilot_ai)
		_check("stand-in: a pilot's brain is left alone", pilot_ai.state == "retreat")
		pilot_ai.state = st
	# The brain goes when the ship does.
	world.combat.kill_silently(ship)
	Standin.keep_alive(world, p)
	_check("stand-in: a lost ship's brain is forgotten", p.standins.is_empty())
	_reset(0.0)


## The fleet limit: reserved at the start, given back, and the repeat.
func _limit_cases() -> void:
	_reset(50000.0)
	var p := _prod()
	var a := p.add_ship("fighter", 3)
	_run(1)
	_check("limit: the places are reserved when the build starts", p.capacity.reserved == 3 and p.capacity.used() == 3)
	a["done"] = int(a["ticks"]) - 1
	_run(1)
	var sq: Squad = null
	for id: int in world.squads:
		sq = world.squads[id]
	_check("limit: after the arrival the ships count, the reservation is gone", p.capacity.reserved == 0 and p.capacity.used() == 3)
	var lost := _ships_of(sq)[0] as Ship
	var cur: int = world.events_rts.next_index(0)
	world.combat.kill(lost, DamageInfo.new())
	var n_lost := 0
	for e: Dictionary in world.events_rts.read_from(0, cur):
		if e["kind"] == "ship_lost":
			n_lost += 1
	_check("limit: a ship that dies gives its place back (one ship_lost)", p.capacity.used() == 2 and n_lost == 1, "used %d lost %d" % [p.capacity.used(), n_lost])
	_check("limit: and leaves its record", sq.member_uids.size() == 2)
	# Cancel of a started build gives its places back.
	var b := p.add_ship("fighter", 3)
	_run(1)
	_check("limit: a second build reserves three more", p.capacity.used() == 5)
	p.cancel(str(b["id"]))
	_check("limit: cancelling it gives them back", p.capacity.used() == 2)
	# Repeat: a finished item of a hull on repeat is queued again, until the limit or the depth.
	_reset(500000.0)
	p.set_repeat("fighter", true)
	var r := p.add_ship("fighter", 3)
	var rounds := 0
	while rounds < 12:
		_run(1)
		for it: Dictionary in p.items:
			if it["running"]:
				it["done"] = int(it["ticks"]) - 1
		_run(1)
		rounds += 1
	_check("limit: a repeat stops at the fleet limit", p.capacity.alive() == RtsHulls.CAP_IN_FORCE and p.capacity.used() <= RtsHulls.CAP_IN_FORCE, "alive %d used %d" % [p.capacity.alive(), p.capacity.used()])
	_check("limit: and the repeat flag stays on", int(p.repeat["fighter"]) == 1)
	_check("limit: the list holds nothing after the last arrival", p.ship_items() == 0, str(p.ship_items()))
	# The depth: with the yard busy, a requeue does not pass five items.
	_reset(500000.0)
	p.set_repeat("fighter", true)
	for i in 5:
		p.add_ship("scout", 1)
	var cap_before := p.ship_items()
	var fig := p.add_ship("fighter", 3)
	fig["started"] = true
	fig["running"] = true
	fig["done"] = int(fig["ticks"])
	p.capacity.reserve(3)
	p._make_squad(fig)
	p._progress_ships()
	_check("limit: a repeat does not queue past the depth of five", p.ship_items() == RtsHulls.DEPTH_SHIPS and cap_before == 5, str(p.ship_items()))
	_reset(0.0)
