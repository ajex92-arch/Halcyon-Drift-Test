extends Node
## WHAT THIS IS: the exact check for the yard's build list (Production): what is paid
## and when, the order the ore goes in, cancel, hold, reorder, the queue depths, and
## what an unlocked Admiral skips.
##
## HOW IT WORKS: it runs in a small world, in the first tick, and drives the list of
## team 0 by hand: it sets the treasury, puts items in with Production.add_ship() and
## the other add functions (or the real queue_research() and AdmiralCommand
## functions), calls Production.tick() a few times and reads the list, the treasury,
## the old queues and the fleet limit. It puts the team back to empty between cases.
##   - Paying: a waiting item has paid nothing; an item pays its whole price when it
##     starts; an item with a missing unlock, a busy line or a full fleet does not
##     hold the ore turn, the first item that only lacks ore does.
##   - Cancel: a waiting item leaves free; a started item gives back all it paid, its
##     place in the fleet and its squad record.
##   - Hold: a held started item keeps its progress, its paid ore and its place and
##     frees its line; resuming it pays nothing again.
##   - Reorder moves an item one place; the queue depths (research 3, modules 2,
##     drones 6, ships 5) refuse the next one; no research twice, also against a
##     waiting copy.
##   - An unlocked Admiral (the test option) pays nothing and skips the unlock check,
##     and the fleet limit still binds.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=production_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <case> <details>" or "FAIL <case>
## <details>". The last line is "production_check: N failures (M checks)"; 0 failures
## means the list pays and orders as written.
##
## WHO USES IT: main.gd loads it for --test=production_check; run_checks runs it.

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True once the cases have run (they all run in the first tick).
var _ran := false
## One tick, in seconds.
const DT := 1.0 / 60.0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF


## Run every case in the first tick, print the result and quit.
func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	_pay_cases()
	_order_cases()
	_cancel_hold_cases()
	_depth_cases()
	_unlock_cases()
	_yard_order_cases()
	_computer_cases()
	_reset()
	print("production_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------

## Print one PASS or FAIL line for the check `name` (`ok` = it passed), and count it.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Team 0's state and its build list.
func _ts() -> TeamState:
	return world.teams[0]


## Team 0's build list.
func _prod() -> Production:
	return world.teams[0].production


## Put team 0 back to an empty list, empty queues, an empty fleet and `money` credits.
func _reset(money: float = 0.0) -> void:
	var ts := _ts()
	ts.production.items.clear()
	ts.production.repeat.clear()
	ts.production.capacity.reserved = 0
	ts.production._cap_blocked = false
	ts.research.clear()
	ts.building.clear()
	ts.drone_queue.clear()
	ts.treasury = money
	for id: int in world.squads.keys():
		if (world.squads[id] as Squad).team == 0:
			world.squads.erase(id)
	Game.unlock_everything = false
	ts.admiral = "ai"


## Run the list of team 0 for `n` ticks.
func _run(n: int) -> void:
	for i in n:
		_prod().tick(DT)


## The item with id `id` of team 0's list, or an empty Dictionary.
func _item(id: String) -> Dictionary:
	return _prod().find(id)


## How many events of kind `kind` team 0 has filed since index `cursor`.
func _events(kind: String, cursor: int) -> Array:
	var out: Array = []
	for e: Dictionary in world.events_rts.read_from(0, cursor):
		if e["kind"] == kind:
			out.append(e)
	return out


# --- the cases ---------------------------------------------------------------------

## Paying at the start and nothing before it.
func _pay_cases() -> void:
	_reset(5000.0)
	var p := _prod()
	var cur: int = world.events_rts.next_index(0)
	var a := p.add_ship("fighter", 3)
	_check("pay: a Fighter squadron costs the pilot's price times three", int(a["price"]) == 450, str(a["price"]))
	_check("pay: before the first tick nothing is paid", _ts().treasury == 5000.0 and int(a["paid"]) == 0 and not a["started"])
	_run(1)
	_check("pay: the item pays its whole price when it starts", absf(_ts().treasury - 4550.0) < 0.001 and int(a["paid"]) == 450 and a["running"], "treasury %.1f" % _ts().treasury)
	_check("pay: build_started is filed once", _events("build_started", cur).size() == 1)
	_check("pay: the squad record exists and is launching", world.squads.has(int(a["squad"])) and (world.squads[int(a["squad"])] as Squad).state == 6 and (world.squads[int(a["squad"])] as Squad).kind == "squadron")
	_check("pay: its three places are reserved", p.capacity.reserved == 3 and p.capacity.used() == 3)
	_run(30)
	_check("pay: it keeps counting up and pays nothing more", int(a["done"]) == 30 and absf(_ts().treasury - 4550.0) < 0.001, "done %d" % int(a["done"]))
	# A waiting item has paid nothing.
	_reset(100.0)
	var b := _prod().add_ship("fighter", 3)
	_run(3)
	_check("pay: a waiting item has paid nothing and says what it needs", int(b["paid"]) == 0 and not b["started"] and _ts().treasury == 100.0 and p.state_text(b) == "waiting: ore (needs 350)", p.state_text(b))
	# The prices of the table, whole numbers.
	var want := {"fighter": 450, "lance": 900, "bomber": 1050, "logistics": 500, "support": 550, "flak": 1100, "ion": 1250, "destroyer": 2200, "battlecruiser": 3800, "scout": 150}
	var ok := true
	for hull: String in want:
		var n := RtsHulls.max_count(hull)
		ok = ok and RtsHulls.price_of(hull, n) == int(want[hull])
	_check("pay: the Admiral price of every hull is the table's", ok)
	_check("pay: the build times of the classes", RtsHulls.build_ticks("fighter") == 1200 and RtsHulls.build_ticks("logistics") == 1500 and RtsHulls.build_ticks("flak") == 2400 and RtsHulls.build_ticks("destroyer") == 3600)


## The order of the ore turn.
func _order_cases() -> void:
	# Strict order: a cheap item behind an unaffordable head does not start.
	_reset(300.0)
	var p := _prod()
	var head := p.add_ship("fighter", 3)
	var cheap := p.add_drone("")
	_run(2)
	_check("order: a cheap item behind an unaffordable head waits", not head["started"] and not cheap["started"] and cheap["why"] == "turn", "%s / %s" % [p.state_text(head), p.state_text(cheap)])
	_ts().treasury = 500.0
	_run(1)
	_check("order: when the head can pay it starts first", head["started"] and not cheap["started"])
	_run(1)
	_check("order: then the next waits for its own ore", not cheap["started"] and cheap["why"] == "ore" and int(cheap["need"]) == 150, "need %d" % int(cheap["need"]))
	_ts().treasury += 1000.0
	_run(1)
	_check("order: and starts once it can pay", cheap["started"] and cheap["running"] and _ts().drone_queue.size() == 1)
	# A missing unlock does not hold the turn.
	_reset(5000.0)
	var locked := p.add_ship("bomber", 3)
	var open := p.add_ship("fighter", 3)
	_run(2)
	_check("order: an item with a missing unlock is skipped, the next one starts", not locked["started"] and locked["why"] == "unlock" and open["started"], p.state_text(locked))
	_check("order: the locked item says what it needs", p.state_text(locked).begins_with("waiting: unlock (needs "), p.state_text(locked))
	# A busy line does not hold the turn.
	_reset(9000.0)
	var s1 := p.add_ship("fighter", 3)
	var s2 := p.add_ship("fighter", 3)
	var s3 := p.add_ship("fighter", 3)
	var dr := p.add_drone("")
	_run(2)
	_check("order: the yard builds two at once", s1["running"] and s2["running"] and not s3["started"] and s3["why"] == "line", p.state_text(s3))
	_check("order: a busy line does not hold the turn: the drone behind starts", dr["started"] and dr["running"])
	# A full fleet does not hold the turn either, and files cap_full once.
	_reset(9000.0)
	var cur: int = world.events_rts.next_index(0)
	p.capacity.reserve(RtsHulls.CAP_IN_FORCE - 2)  # two places are left: a squadron of three does not fit
	var big := p.add_ship("fighter", 3)
	var small := p.add_drone("")
	_run(3)
	_check("order: a full fleet blocks the squadron with its reason", not big["started"] and big["why"] == "room" and p.state_text(big) == "waiting: fleet full", p.state_text(big))
	_check("order: and does not hold the turn: the drone starts", small["started"])
	_check("order: cap_full is filed once", _events("cap_full", cur).size() == 1, str(_events("cap_full", cur).size()))
	# Reorder.
	_reset(0.0)
	var r1 := p.add_ship("fighter", 3)
	var r2 := p.add_ship("fighter", 2)
	var r3 := p.add_ship("fighter", 1)
	_check("reorder: down one place", p.move(str(r1["id"]), 1) == "" and p.items[0] == r2 and p.items[1] == r1 and p.items[2] == r3)
	_check("reorder: up one place", p.move(str(r3["id"]), -1) == "" and p.items[1] == r3 and p.items[2] == r1)
	_check("reorder: at the end nothing happens", p.move(str(r2["id"]), -1) == "" and p.items[0] == r2)
	_check("reorder: an unknown item is refused", p.move("nope", 1) == OrderKinds.TEXT_NO_ITEM)
	# The order decides who is paid first when money arrives.
	_ts().treasury = 450.0
	_run(1)
	_check("reorder: the new head is paid first", r2["started"] and r3["started"] and not r1["started"], "%s / %s / %s" % [p.state_text(r2), p.state_text(r3), p.state_text(r1)])


## Cancel and hold of started items.
func _cancel_hold_cases() -> void:
	_reset(5000.0)
	var p := _prod()
	var cur: int = world.events_rts.next_index(0)
	var a := p.add_ship("fighter", 3)
	_run(10)
	var sid := int(a["squad"])
	_check("cancel: started and paid", a["running"] and absf(_ts().treasury - 4550.0) < 0.001)
	_check("cancel: a started build gives back all it paid", p.cancel(str(a["id"])) == "" and absf(_ts().treasury - 5000.0) < 0.001, "treasury %.1f" % _ts().treasury)
	_check("cancel: and its place and its squad record", p.capacity.reserved == 0 and not world.squads.has(sid) and p.items.is_empty())
	var ev := _events("item_cancelled", cur)
	_check("cancel: item_cancelled carries the refund", ev.size() == 1 and int(ev[0]["data"]["refund"]) == 450, str(ev))
	_reset(100.0)
	var w := p.add_ship("fighter", 3)
	_check("cancel: a waiting item leaves and refunds nothing", p.cancel(str(w["id"])) == "" and _ts().treasury == 100.0 and p.items.is_empty())
	_check("cancel: an unknown item is refused", p.cancel("nope") == OrderKinds.TEXT_NO_ITEM)
	# Hold keeps progress, paid ore and the place, and frees the line.
	_reset(9000.0)
	var h1 := p.add_ship("fighter", 3)
	var h2 := p.add_ship("fighter", 3)
	var h3 := p.add_ship("fighter", 3)
	_run(100)
	var done_before := int(h1["done"])
	var paid_before := int(h1["paid"])
	var money_before := _ts().treasury
	_check("hold: two building, the third waits for a line", h1["running"] and h2["running"] and not h3["started"])
	_check("hold: holding a started item succeeds", p.hold(str(h1["id"]), true) == "" and h1["held"] and not h1["running"])
	_check("hold: it keeps its progress, its paid ore and its place", int(h1["done"]) == done_before and int(h1["paid"]) == paid_before and p.capacity.reserved >= 3 and p.state_text(h1) == "on hold")
	_run(1)
	_check("hold: its line is free for the next item", h3["started"] and h3["running"], p.state_text(h3))
	_run(50)
	_check("hold: a held item does not count up", int(h1["done"]) == done_before, "%d vs %d" % [int(h1["done"]), done_before])
	var money_mid := _ts().treasury
	_check("hold: the next item paid its own price only", absf(money_before - money_mid - 450.0) < 0.001, "%.1f -> %.1f" % [money_before, money_mid])
	# Resume needs a free line; it pays nothing again.
	_check("hold: resuming marks it ready", p.hold(str(h1["id"]), false) == "" and not h1["held"])
	_run(1)
	_check("hold: with no free line it waits for one", not h1["running"] and h1["why"] == "line")
	p.cancel(str(h2["id"]))
	_run(1)
	_check("hold: with a free line it goes on, keeping its progress, paying nothing", h1["running"] and int(h1["done"]) >= done_before and absf(_ts().treasury - (money_mid + 450.0)) < 0.001, "done %d, treasury %.1f" % [int(h1["done"]), _ts().treasury])
	# Hold of a research: it leaves the old queue and comes back with its time left.
	_reset(5000.0)
	_ts().facilities["research"] = true
	_check("hold: a research queues", _ts().queue_research("lanceBeams") == "")
	_run(1)
	_check("hold: it started and sits in the research queue", _ts().research.size() == 1 and absf(_ts().treasury - 4450.0) < 0.001)
	_ts().research[0]["left"] = 20.0
	var rid := str((p.items[0] as Dictionary)["id"])
	_check("hold: holding it takes it out of the queue", p.hold(rid, true) == "" and _ts().research.is_empty() and absf(float(p.items[0]["left"]) - 20.0) < 0.001)
	_check("hold: it still counts as researching", _ts().is_researching("lanceBeams") and _ts().planned_tech().has("lanceBeams"))
	p.hold(rid, false)
	_run(1)
	_check("hold: resumed it is back with its time and nothing paid again", _ts().research.size() == 1 and absf(float(_ts().research[0]["left"]) - 20.0) < 0.001 and absf(_ts().treasury - 4450.0) < 0.001)
	_check("cancel: a started research gives back its price", p.cancel(rid) == "" and absf(_ts().treasury - 5000.0) < 0.001 and _ts().research.is_empty())


## The queue depths and "never twice".
func _depth_cases() -> void:
	_reset(0.0)
	var ts := _ts()
	var p := _prod()
	ts.facilities["research"] = true
	ts.facilities["fighter"] = true
	ts.done["corvetteChassis"] = true
	# Research: three in all, the third counted even when the first started.
	_check("depth: research 1", ts.queue_research("fusionBombs") == "")
	_check("depth: research 2", ts.queue_research("lanceBeams") == "")
	_check("depth: research 3", ts.queue_research("scoutEmp") == "")
	var full := ts.queue_research("fighterDrive1")
	_check("depth: the fourth research is refused", full.begins_with("Research queue is full"), full)
	_check("depth: no research twice, also against a waiting copy", ts.queue_research("lanceBeams").begins_with("Already researched or queued"))
	# A chain can be stacked: a research needing a waiting one is accepted.
	_reset(0.0)
	ts.facilities["research"] = true
	ts.facilities["fighter"] = true
	_check("depth: a chain stacks (Fusion Bombs then Steady Sights)", ts.queue_research("fusionBombs") == "" and ts.queue_research("improvedBombs") == "")
	_ts().treasury = 100000.0
	_run(2)
	var second: Dictionary = p.items[1]
	_check("depth: the second of the chain waits for the first (unlock)", second["why"] == "unlock" or second["why"] == "line", str(second["why"]))
	# Modules: two.
	_reset(0.0)
	ts.facilities["research"] = true
	ts.done["corvetteChassis"] = true
	_check("depth: module 1", ts.queue_facility("platform") == "")
	_check("depth: module 2", ts.queue_facility("sensors") == "")
	var mfull := ts.queue_facility("corvette")
	_check("depth: the third module is refused", mfull.begins_with("Build queue is full"), mfull)
	_check("depth: no module twice", ts.queue_facility("platform").begins_with("Already built or being built"))
	# Drones: six in the list, and the order function counts them.
	_reset(0.0)
	var cmd := world.command
	var refused := ""
	var queued := 0
	for i in 8:
		var r := cmd.build_drone(0, "")
		if r == "":
			queued += 1
		else:
			refused = r
	_check("depth: six drones queue, the seventh is refused", queued == 6 and refused.begins_with("Drone build queue is full"), "%d, %s" % [queued, refused])
	_check("depth: drones_queued counts the waiting ones", ts.drones_queued() == 6)
	_check("depth: queuing a drone paid nothing", ts.treasury == 0.0)


## The computer Admiral's buying (AdmiralProduction): the fill schedule, the mix, the fundable head, the
## saving goal for a capital ship and the repeat.
func _computer_cases() -> void:
	var ts := _ts()
	var p := _prod()
	var ap := AdmiralProduction.new(world, 0, AdmiralLanes.new(world, 0))
	var saved_time := world.time
	# The fill schedule: the schedule's percents of the fleet limit, rounded up, wanted by 6:00, 12:00 and 18:00
	# (30, 70 and 90 percent today). The expected numbers come from RtsHulls.FILL_PERCENT and CAP_IN_FORCE, never typed.
	var aims: Array[int] = []
	var aims_ok := true
	for i in RtsHulls.FILL_SECONDS.size():
		aims.append(ceili(float(RtsHulls.CAP_IN_FORCE * int(RtsHulls.FILL_PERCENT[i])) / 100.0))
		aims_ok = aims_ok and RtsHulls.fill_target(float(RtsHulls.FILL_SECONDS[i])) == aims[i]
	_check("computer: the fill targets are the schedule's percents of the fleet limit, rounded up", aims_ok and RtsHulls.fill_target(0.0) == 0 and RtsHulls.fill_target(5000.0) == aims[aims.size() - 1], "%s of %d" % [str(aims), RtsHulls.CAP_IN_FORCE])
	# The buying cases below start six ships short of the 6:00 target, whatever the limit is.
	_reset(5000.0)
	_pad_fleet(aims[0] - 6)
	world.time = 360.0
	ap.run(ts, 5000.0)
	_check("computer: below the target it buys a Fighter squadron for the push lane", p.ship_items() == 1 and p.items[0]["what"] == "fighter" and int(p.items[0]["count"]) == 3 and p.items[0]["rally"] == "lane", str(p.items.size()))
	_check("computer: while below the target the Fighter squadrons repeat", int(p.repeat.get("fighter", 0)) == 1)
	ap.run(ts, 5000.0)
	_check("computer: and again until the target is met", p.ship_items() == 2, str(p.ship_items()))
	ap.run(ts, 5000.0)
	_check("computer: then it stops (the 6:00 target is met)", p.ship_items() == 2)
	_check("computer: at the target the repeat goes off", int(p.repeat.get("fighter", 1)) == 0)
	_check("computer: every buy has a logged reason", ap.log.size() >= 2 and (ap.log[0] as String).begins_with("YARD t=360 team=0 buys Fighter x3 (450)"), ap.log[0] if not ap.log.is_empty() else "")

	# Money: it does not queue what the treasury cannot pay within 20 seconds, less the reserve.
	_reset(500.0)
	world.time = 700.0
	var ap2 := AdmiralProduction.new(world, 0, AdmiralLanes.new(world, 0))
	ap2.run(ts, 500.0)
	_check("computer: it does not buy what the money to spare cannot carry", p.ship_items() == 0)
	# The mix follows the unlocks.
	_reset(100000.0)
	world.time = 1100.0
	ts.facilities["corvette"] = true
	var ap3 := AdmiralProduction.new(world, 0, AdmiralLanes.new(world, 0))
	var seq: Array = []
	for i in 5:
		ap3.run(ts, 100000.0)
		if p.ship_items() > seq.size():
			seq.append(str((p.items[p.items.size() - 1] as Dictionary)["what"]))
		for it: Dictionary in p.items:
			it["started"] = true
			it["running"] = false
			it["held"] = true
	_check("computer: Fighter squadrons, then a corvette after three", seq.size() >= 4 and seq[0] == "fighter" and seq[1] == "fighter" and seq[2] == "fighter" and seq[3] == "logistics", str(seq))
	ts.facilities.erase("corvette")
	# The fundable head is held, and goes on when it can be paid.
	_reset(300.0)
	world.time = 800.0
	var ap4 := AdmiralProduction.new(world, 0, AdmiralLanes.new(world, 0))
	var big := p.add_ship("flak", 1)
	ts.facilities["frigate"] = true
	_run(2)
	_check("computer: a big item waits for ore at the head", big["why"] == "ore")
	ap4.run(ts, 100.0)
	_check("computer: alone in the list it is not held (nothing could start)", not big["held"])
	var small := p.add_ship("fighter", 1)
	_run(2)
	ap4.run(ts, 100.0)
	_check("computer: with another item waiting behind, it holds an unfundable head", big["held"] and not ap4.log.is_empty() and (ap4.log[ap4.log.size() - 1] as String).contains("holds Flak Frigate"), str(ap4.log))
	_run(2)
	_check("computer: and the item behind may start", small["started"], p.state_text(small))
	ts.treasury = 5000.0
	ap4.run(ts, 5000.0)
	_check("computer: it lets the held item go on when the treasury pays it", not big["held"])
	ts.facilities.erase("frigate")
	# The saving goal for a capital ship.
	_reset(700.0)
	world.time = 1000.0
	_unlock_capital_for_test()
	var ap5 := AdmiralProduction.new(world, 0, AdmiralLanes.new(world, 0))
	ap5.run(ts, 700.0)
	_check("computer: with a Capital Ship Facility it saves for a Destroyer and queues no other ship", p.ship_items() == 0 and ap5._saving_since >= 0.0 and (ap5.log[0] as String).contains("saves for a Destroyer (2200)"), str(ap5.log))
	ts.treasury = 2300.0
	ap5.run(ts, 2300.0)
	_check("computer: it queues the Destroyer when it is fundable", p.ship_items() == 1 and p.items[0]["what"] == "destroyer", str(p.items.size()))
	_reset(100.0)
	_unlock_capital_for_test()
	var ap6 := AdmiralProduction.new(world, 0, AdmiralLanes.new(world, 0))
	world.time = 1000.0
	ap6.run(ts, 100.0)
	world.time = 1000.0 + RtsHulls.SAVING_LAPSE_S + 5.0
	ap6.run(ts, 100.0)
	_check("computer: the saving goal is given up after 180 seconds", ap6._saving_since < 0.0 and ap6._no_saving_until > world.time and (ap6.log[ap6.log.size() - 1] as String).contains("gives up saving"), str(ap6.log))
	world.time = saved_time
	ts.done.erase("destroyerChassis")
	ts.facilities.erase("capital")
	_reset(0.0)


## Put `n` living fleet ships into team 0's squad records (plain unit numbers, no ships in the world), so a
## case can start with a fleet of a known size whatever the fleet limit is. _reset() clears them. Nothing
## is made for `n` of 0 or less.
func _pad_fleet(n: int) -> void:
	if n <= 0:
		return
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = 0
	s.kind = "ship"
	s.max_members = n
	for i in n:
		s.member_uids.append(-1 - i)
	world.squads[s.id] = s


## Unlock the Destroyer for team 0 (the Capital Ship Facility and the chassis research).
func _unlock_capital_for_test() -> void:
	_ts().done["destroyerChassis"] = true
	_ts().facilities["capital"] = true


## An unlocked Admiral, and the fleet limit.
func _unlock_cases() -> void:
	_reset(100.0)
	var p := _prod()
	var ts := _ts()
	Game.unlock_everything = true
	ts.admiral = "human"
	var b := p.add_ship("bomber", 3)
	_run(2)
	_check("unlock: a locked hull starts at once for an unlocked Admiral", b["started"] and b["running"])
	_check("unlock: and pays nothing", ts.treasury == 100.0 and int(b["paid"]) == 0)
	_check("unlock: cancelling it refunds nothing", p.cancel(str(b["id"])) == "" and ts.treasury == 100.0)
	# The limit still binds.
	p.capacity.reserve(RtsHulls.CAP_IN_FORCE - 2)  # two places are left: a squadron of three does not fit, one of two does
	var c := p.add_ship("fighter", 3)
	_run(2)
	_check("unlock: the fleet limit still binds", not c["started"] and c["why"] == "room", p.state_text(c))
	var d := p.add_ship("fighter", 2)
	_run(2)
	_check("unlock: a squadron of two still fits under the limit", d["started"] and p.capacity.used() == RtsHulls.CAP_IN_FORCE, str(p.capacity.used()))
	# An unlocked Admiral queues a research with no prerequisite.
	_reset(0.0)
	ts.facilities.erase("research")
	Game.unlock_everything = true
	ts.admiral = "human"
	_check("unlock: an unlocked Admiral queues research with nothing built", ts.queue_research("fusionBombs") == "")
	_run(1)
	_check("unlock: it starts and costs nothing", ts.research.size() == 1 and ts.treasury == 0.0)
	_reset(0.0)

## Send one order of the Admiral's seat through the queue's same-tick door. Returns "" or the reason.
func _send(kind: String, settings: Dictionary = {}, target_kind: String = "none", target = null) -> String:
	return world.orders.apply_now(Order.make(kind, 0, Rules.ADMIRAL_SEAT, false, settings, [], target_kind, target))


## The six yard orders through the order queue.
func _yard_order_cases() -> void:
	_reset(5000.0)
	var p := _prod()
	var cur: int = world.events_rts.next_index(0)
	var r := _send(OrderKinds.PRODUCE, {"hull": "fighter", "count": 3, "repeat": 1, "rally": "point", "rx": 100, "ry": -200})
	_check("orders: PRODUCE is accepted", r == "", r)
	var a: Dictionary = p.items[0] if not p.items.is_empty() else {}
	_check("orders: it puts the item in the list with its rally and stance", not a.is_empty() and a["what"] == "fighter" and int(a["count"]) == 3 and a["rally"] == "point" and int(a["rx"]) == 100 and int(a["ry"]) == -200)
	_check("orders: the repeat of the hull is on", int(p.repeat.get("fighter", 0)) == 1)
	_check("orders: order_done is filed for it", _events("order_done", cur).size() == 1)
	_run(1)
	_check("orders: it pays at its start", a["started"] and absf(_ts().treasury - 4550.0) < 0.001)
	# Refusals at once.
	var locked := _send(OrderKinds.PRODUCE, {"hull": "bomber", "count": 3})
	_check("orders: a locked hull is refused: unlock", OrderKinds.reason_code(locked) == "unlock" and locked.begins_with("Needs "), locked)
	var many := _send(OrderKinds.PRODUCE, {"hull": "destroyer", "count": 3})
	_check("orders: a count of 3 for a large ship is refused: value", OrderKinds.reason_code(many) == "value", many)
	var norx := _send(OrderKinds.PRODUCE, {"hull": "fighter", "count": 1, "rally": "point"})
	_check("orders: a rally point without its point is refused: value", OrderKinds.reason_code(norx) == "value", norx)
	var nohull := _send(OrderKinds.PRODUCE, {"hull": "nope", "count": 1})
	_check("orders: an unknown hull is refused: value", OrderKinds.reason_code(nohull) == "value", nohull)
	# Never refused for money or a full fleet.
	_reset(0.0)
	_check("orders: PRODUCE with no money is accepted and waits", _send(OrderKinds.PRODUCE, {"hull": "fighter", "count": 3}) == "")
	p.capacity.reserve(RtsHulls.CAP_IN_FORCE)
	_check("orders: PRODUCE with a full fleet is accepted and waits", _send(OrderKinds.PRODUCE, {"hull": "fighter", "count": 3}) == "")
	_run(2)
	_check("orders: both say the fleet is full", p.state_text(p.items[0]) == "waiting: fleet full" and p.state_text(p.items[1]) == "waiting: fleet full", "%s / %s" % [p.state_text(p.items[0]), p.state_text(p.items[1])])
	# The ship list holds five.
	_reset(0.0)
	var accepted := 0
	var last := ""
	for i in 7:
		var res := _send(OrderKinds.PRODUCE, {"hull": "fighter", "count": 1})
		if res == "":
			accepted += 1
		else:
			last = res
	_check("orders: five ship items fit, the next is refused: room", accepted == 5 and OrderKinds.reason_code(last) == "room", "%d, %s" % [accepted, last])
	# CANCEL, MOVE_ITEM, HOLD_ITEM, SET_REPEAT and SET_RALLY.
	_reset(5000.0)
	var x := p.add_ship("fighter", 3)
	var y := p.add_ship("fighter", 2)
	_run(1)
	cur = world.events_rts.next_index(0)
	_check("orders: MOVE_ITEM moves an item down", _send(OrderKinds.MOVE_ITEM, {"dir": 1}, "item", str(x["id"])) == "" and p.items[1] == x)
	_check("orders: HOLD_ITEM holds a started item", _send(OrderKinds.HOLD_ITEM, {"hold": 1}, "item", str(x["id"])) == "" and x["held"] and not x["running"])
	_check("orders: and lets it go on", _send(OrderKinds.HOLD_ITEM, {"hold": 0}, "item", str(x["id"])) == "" and not x["held"])
	_check("orders: SET_REPEAT turns a hull's repeat on and off", _send(OrderKinds.SET_REPEAT, {"repeat": 1}, "id", "lance") == "" and int(p.repeat["lance"]) == 1 and _send(OrderKinds.SET_REPEAT, {"repeat": 0}, "id", "lance") == "" and int(p.repeat["lance"]) == 0)
	_check("orders: SET_RALLY gives a ship item a new rally", _send(OrderKinds.SET_RALLY, {"rally": "point", "rx": 5, "ry": 6}, "item", str(y["id"])) == "" and y["rally"] == "point" and int(y["rx"]) == 5 and int(y["ry"]) == 6)
	var money := _ts().treasury
	_check("orders: CANCEL takes an item out and refunds a started one", _send(OrderKinds.CANCEL, {}, "item", str(x["id"])) == "" and _ts().treasury > money and p.find(str(x["id"])).is_empty())
	var gone := _send(OrderKinds.CANCEL, {}, "item", "t0i999")
	_check("orders: an item that is not there is refused: value", OrderKinds.reason_code(gone) == "value", gone)
	var dr := p.add_drone("")
	var notship := _send(OrderKinds.SET_RALLY, {"rally": "mothership"}, "item", str(dr["id"]))
	_check("orders: SET_RALLY on a drone is refused", notship != "", notship)
	var lance := _send(OrderKinds.SET_REPEAT, {"repeat": 1}, "id", "zz")
	_check("orders: SET_REPEAT of no hull is refused", lance != "", lance)
	_check("orders: the rally points are whole numbers on the map", p.rally_point("point", 7, 8) == Vector2i(7, 8) and p.rally_point("mothership", 0, 0) != Vector2i.ZERO and p.rally_point("lane", 0, 0) != Vector2i.ZERO)
	_reset(0.0)