extends Node
## WHAT THIS IS: the exact check for stealable drone ore. A mining drone that is
## shot down while it holds ore drops the whole hold to the killer's team, and the
## computer pilots rate a fuller drone a better target. This check shoots drones
## with known holds and compares what each team and pilot was paid, and what the
## computer pilots pick, with the numbers the rule says (worked out here, never
## copied from the game).
##
## HOW IT WORKS: it freezes the match, stops the minion waves, and listens to
## Events.credits_earned to add up what each pilot was paid per reason. Pilots are
## plain records (three of team 0, one of team 1 for the victim's escort). It takes
## four of the drones each team starts with (a test spawns no drone: spawning draws a
## random number) and kills them one case at a time, either by calling
## Economy.on_unit_killed() with a hand-built killing blow, or, in the last payout
## case, through Combat.kill() with a real ship's blow. Every reading of a name that
## an older build lacks (the counters, the switch, the pull function) goes through
## get() or call(), so a missing one is a FAIL line and never a script error.
##   - (a) a full hold: 60% to the killer's treasury, 40% shared by the living
##     pilots as "ore stolen", the flat bounty to the killer, the counters, and no
##     credits made beyond the hold and the bounty;
##   - (b) an empty hold pays only the flat bounty;
##   - (c) every mood of the drone pays the same;
##   - (d) the drone's own team's blow pays nothing;
##   - (e) a turret's or a minion's blow pays the hold (no flat bounty), a blow from
##     no team pays nothing;
##   - (f) the victim's escorts are paid nothing;
##   - (g) delivered ore pays as before, and a steal pays the same shares as a
##     delivery of the same ore;
##   - (h) the switch turns it all off;
##   - (i) the earnings line has a plain word for the new reason and the killer hears
##     of the payment;
##   - (j) the live caller, Combat.kill(), pays the hold;
##   - (k) the pull a fuller drone gets in the computer pilots' target score;
##   - (l) the pick of a computer pilot between two drones.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=7 --test=drone_steal_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <label> <details>" or "FAIL
## <label> <details>". The last line is "drone_steal_check: N failures (M checks)";
## 0 failures means the steal pays exactly as written.
##
## WHO USES IT: main.gd loads it for --test=drone_steal_check (it calls setup()); the
## lead's check list.

## A payout may differ from the wanted amount by this much (credits).
const EPS := 0.0001
## The ore in a full hold in the cases.
const HOLD := 300.0
## How far (world units) the chosen spot of the pick cases must be from every unit of team 1.
const QUIET_R := 3600.0
## The range the pick cases give the pilot's search.
const PICK_R := 1600.0
## How far from the pilot the nearer drone of a pick case stands.
const PICK_BASE := 600.0
## The pull used by the pick cases when the build has no DRONE_ORE_PULL (so the labels fail by value).
const PULL_GUESS := 200.0

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True once the cases have started (they run once).
var _ran := false
## What each pilot was paid in the case that is running: profile -> reason -> credits.
var _paid := {}
## Every payment of the case that is running, in order: [profile, credits, reason].
var _events: Array = []
## The readings of the last _living_paid() call, as text for a detail.
var _last_detail := ""
## The readings taken before the shot of the case that is running.
var _before := {}
## The share of delivered ore that goes to the treasury (0.6).
var _share := 0.6
## The three pilots of team 0.
var _pa: PilotProfile
## The second pilot of team 0.
var _pb: PilotProfile
## The third pilot of team 0.
var _pc: PilotProfile
## The pilot of team 1 who escorts the victim.
var _pe: PilotProfile
## The drone of team 1 the payout cases shoot.
var d1a: MiningDrone
## A drone of team 1 for the pick cases.
var d1b: MiningDrone
## The other drone of team 1 for the pick cases.
var d1c: MiningDrone
## The drone of team 1 that the Combat.kill case shoots.
var d1d: MiningDrone
## The drone of team 0 whose own team's blow shoots it.
var d0a: MiningDrone
## The spot of the pick cases, and the pilot's ship and brain there.
var _home := Vector2.ZERO
## The team 0 ship that picks in the pick cases.
var _me: Ship
## The brain of that ship.
var _brain: PilotAI


## main.gd calls this once, right after the World is built. Freeze the match,
## stop the minion waves, listen to the payments and start the run on a later frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	world.minion_director.next_wave = INF
	Events.credits_earned.connect(_on_paid)
	_run.call_deferred()


## A pilot was paid: add it to what that pilot has been paid in this case.
func _on_paid(p: RefCounted, amount: float, reason: String) -> void:
	if not _paid.has(p):
		_paid[p] = {}
	var d: Dictionary = _paid[p]
	d[reason] = float(d.get(reason, 0.0)) + amount
	_events.append([p, amount, reason])


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_ran = true
	_share = float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE))
	_pa = _pilot("A", 0)
	_pb = _pilot("B", 0)
	_pc = _pilot("C", 0)
	_pe = _pilot("E", 1)
	if _setup_ok():
		_case_a()
		_case_b()
		_case_d()
		_case_e()
		_case_f()
		_case_g()
		_case_c()
		_case_h()
		_case_i()
		_case_j()
		_case_k()
		_case_l()
	print("drone_steal_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers ------------------------------------------------------------------------

## Print one PASS or FAIL line for the check `label` (`ok` = it passed), with the
## `detail`, and count it.
func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


## A new pilot record `name` of team `team`, added to the match's records. It has no ship.
func _pilot(name: String, team: int) -> PilotProfile:
	var p := PilotProfile.new(name, team, 60 + world.profiles.size(), false)
	world.profiles.append(p)
	return p


## The living drones of `team`, in their stored order.
func _drones_of(team: int) -> Array[MiningDrone]:
	var out: Array[MiningDrone] = []
	for d in world.mining_drones:
		if d.team == team and d.alive:
			out.append(d)
	return out


## Take the drones and check that the match is as the cases need it. False when a case cannot run.
func _setup_ok() -> bool:
	var t1 := _drones_of(1)
	var t0 := _drones_of(0)
	var have := t1.size() >= 4 and t0.size() >= 1
	_check("setup: four drones of team 1 and one of team 0 are alive", have, "team 1 has %d, team 0 has %d" % [t1.size(), t0.size()])
	if not have:
		return false
	d1a = t1[0]
	d1b = t1[1]
	d1c = t1[2]
	d1d = t1[3]
	d0a = t0[0]
	var plain := world.teams[0].income_mult == 1.0 and world.teams[1].income_mult == 1.0
	for p: PilotProfile in world.profiles:
		if p.income_mult != 1.0:
			plain = false
	_check("setup: no income scaling", plain, "team 0 x%.2f, team 1 x%.2f" % [world.teams[0].income_mult, world.teams[1].income_mult])
	_check("setup: the match is younger than ten minutes", world.time < 600.0, "t=%.2f" % world.time)
	return plain and world.time < 600.0


## The living pilots of `team`: not dead, not a crew.
func _living(team: int) -> Array:
	var out := []
	for p: PilotProfile in world.profiles:
		if p.team == team and p.state != "dead" and not p.is_crew:
			out.append(p)
	return out


## What `p` was paid for `reason` in this case (0 if nothing).
func _got(p: PilotProfile, reason: String) -> float:
	if not _paid.has(p):
		return 0.0
	return float((_paid[p] as Dictionary).get(reason, 0.0))


## How many payments of `reason` the case saw, for every pilot (the whole match).
func _count_reason(reason: String) -> int:
	var n := 0
	for e: Array in _events:
		if e[2] == reason:
			n += 1
	return n


## The counter `key` of team `team`, read without naming it, or NAN when the build has no such counter.
func _counter(team: int, key: String) -> float:
	var v: Variant = (world.teams[team] as Object).get(key)
	if v == null:
		return NAN
	return float(v)


## The flat bounty pilot `p` is paid for a drone: the tuned bounty times the pilot's own gear bonus.
func _flat(p: PilotProfile) -> float:
	return float(Rules.tune("mining_drone_bounty", Rules.MINING_DRONE_BOUNTY)) * Economy._bounty_mult(p)


## All the readings that a shot changes: both treasuries, all pilots' credits, ore delivered, and the counters.
func _snap() -> Dictionary:
	var credits := 0.0
	for p: PilotProfile in world.profiles:
		credits += p.credits
	return {
		"t0": world.teams[0].treasury, "t1": world.teams[1].treasury, "credits": credits,
		"delivered": world.teams[0].ore_delivered,
		"stolen": _counter(0, "ore_stolen"), "stolen10": _counter(0, "ore_stolen_10m"), "stolen_t1": _counter(1, "ore_stolen"),
	}


## Start a case: clear what was paid and take the readings before the shot.
func _begin() -> void:
	_paid.clear()
	_events.clear()
	_before = _snap()


## Shoot `victim` (a drone) with `blow` the way Economy is told of a kill.
func _shoot(victim: MiningDrone, blow: DamageInfo) -> void:
	_begin()
	Economy.on_unit_killed(world, victim, blow)


## How much team `team`'s treasury rose since _begin().
func _treasury_rise(team: int) -> float:
	return float(world.teams[team].treasury) - float(_before["t%d" % team])


## How much all pilots' credits and both treasuries rose together since _begin().
func _money_made() -> float:
	var s := _snap()
	return (float(s["credits"]) - float(_before["credits"])) + (float(s["t0"]) - float(_before["t0"])) + (float(s["t1"]) - float(_before["t1"]))


## How much the counter `key` of team 0 rose since _begin() (stored as `snap_key`), or NAN when it is missing.
func _counter_rise(key: String, snap_key: String) -> float:
	return _counter(0, key) - float(_before[snap_key])


## Is `x` a number (not NAN) within EPS of `want`?
func _near(x: float, want: float) -> bool:
	return not is_nan(x) and absf(x - want) <= EPS


## The killing blow of pilot `p` (a ship's hit), as assist_check builds one.
func _blow_of(p: PilotProfile) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = 1.0
	d.kind = Rules.W_PURE
	d.source_uid = 91000 + p.slot
	d.source_team = p.team
	d.source_is_pilot = true
	d.source_profile = p
	return d


## The killing blow of a minion ("minion"), of a turret ("turret") or of no team ("none"), all with no pilot profile.
func _blow(who: String) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = 1.0
	d.kind = Rules.W_PURE
	if who == "minion":
		d.source_uid = 99991
		d.source_team = 0
		d.source_is_minion = true
	elif who == "turret":
		d.source_uid = 99992
		d.source_team = 0
	else:
		d.source_uid = -1
		d.source_team = Rules.NEUTRAL
	return d


## True when every living pilot of team 0 was paid `each` under `reason`; the readings are left in _last_detail.
func _living_paid(reason: String, each: float) -> bool:
	var ok := true
	var parts: Array[String] = []
	for p: PilotProfile in _living(0):
		var got := _got(p, reason)
		parts.append("%s %s %.3f/%.3f" % [p.callsign, reason, got, each])
		if absf(got - each) > EPS:
			ok = false
	_last_detail = "; ".join(parts)
	return ok


## True when no pilot at all was paid under `reason` in this case.
func _nobody_paid(reason: String) -> bool:
	return _count_reason(reason) == 0


## True when nobody of team 1 was paid anything in this case.
func _team1_unpaid() -> bool:
	for p: PilotProfile in _living(1):
		if _paid.has(p):
			return false
	return true


## Put `d` back to a plain full or empty drone of mood `mood`.
func _ready_drone(d: MiningDrone, cargo: float, mood: String) -> void:
	d.cargo = cargo
	d.state = mood
	d.escorts = {}


# --- (a) a full hold ----------------------------------------------------------------

## (a) A full hold shot down by a pilot of team 0.
func _case_a() -> void:
	_ready_drone(d1a, HOLD, "out")
	var n := float(_living(0).size())
	_shoot(d1a, _blow_of(_pa))
	_check("(a) a full hold shot down pays the killer's treasury 60% of 300", _near(_treasury_rise(0), HOLD * _share), "treasury rose %.3f, wanted %.3f" % [_treasury_rise(0), HOLD * _share])
	var ok := _living_paid("ore stolen", HOLD * (1.0 - _share) / n)
	_check("(a) each living pilot of the killer's team is paid 40% of 300 shared, reason ore stolen", ok, _last_detail)
	var flat := _flat(_pa)
	_check("(a) the killing pilot also gets the flat bounty and nothing under reason ore", absf(_got(_pa, "drone") - flat) <= EPS and _nobody_paid("ore"), "A drone %.3f/%.3f, ore payments %d" % [_got(_pa, "drone"), flat, _count_reason("ore")])
	var delivered_same := absf(float(world.teams[0].ore_delivered) - float(_before["delivered"])) <= EPS
	var counted := _near(_counter_rise("ore_stolen", "stolen"), HOLD) and _near(_counter_rise("ore_stolen_10m", "stolen10"), HOLD)
	_check("(a) ore delivered is unchanged and ore stolen counts 300", delivered_same and counted, "delivered same %s, ore_stolen rose %s, ore_stolen_10m rose %s" % [delivered_same, _counter_rise("ore_stolen", "stolen"), _counter_rise("ore_stolen_10m", "stolen10")])
	_check("(a) credits created are the hold plus the flat bounty and no more", absf(_money_made() - (HOLD + flat)) <= EPS, "made %.3f, wanted %.3f" % [_money_made(), HOLD + flat])


# --- (b) an empty hold --------------------------------------------------------------

## (b) The same drone with an empty hold: only the flat bounty.
func _case_b() -> void:
	_ready_drone(d1a, 0.0, "out")
	_shoot(d1a, _blow_of(_pa))
	var flat := _flat(_pa)
	var ok := absf(_got(_pa, "drone") - flat) <= EPS and absf(_treasury_rise(0)) <= EPS and _count_reason("ore stolen") == 0
	ok = ok and _near(_counter_rise("ore_stolen", "stolen"), 0.0)
	_check("(b) an empty hold pays only the flat bounty", ok, "A drone %.3f/%.3f, treasury rose %.3f, ore stolen payments %d, counter rose %s" % [_got(_pa, "drone"), flat, _treasury_rise(0), _count_reason("ore stolen"), _counter_rise("ore_stolen", "stolen")])


# --- (c) every mood -----------------------------------------------------------------

## (c) The pick "Any drone with ore": a drone pays its hold in every mood.
func _case_c() -> void:
	for mood in ["out", "mine", "home", "idle"]:
		_ready_drone(d1a, 50.0, mood)
		var n := float(_living(0).size())
		_shoot(d1a, _blow_of(_pa))
		var paid := _living_paid("ore stolen", 50.0 * (1.0 - _share) / n)
		var ok := _near(_treasury_rise(0), 50.0 * _share) and paid
		_check("(c) a drone in mood %s holding 50 ore pays 50" % mood, ok, "treasury rose %.3f, wanted %.3f; %s" % [_treasury_rise(0), 50.0 * _share, _last_detail])
	_ready_drone(d1a, 0.0, "out")


# --- (d) the drone's own team -------------------------------------------------------

## (d) A drone shot down by its own team's blow pays nothing.
func _case_d() -> void:
	_ready_drone(d0a, HOLD, "out")
	_shoot(d0a, _blow_of(_pa))
	var ok := absf(_treasury_rise(0)) <= EPS and absf(_treasury_rise(1)) <= EPS and _events.is_empty()
	ok = ok and _near(_counter_rise("ore_stolen", "stolen"), 0.0)
	_check("(d) a drone shot down by its own team's blow pays nothing", ok, "treasury rose %.3f and %.3f, %d payments, counter rose %s" % [_treasury_rise(0), _treasury_rise(1), _events.size(), _counter_rise("ore_stolen", "stolen")])
	_ready_drone(d0a, 0.0, "out")


# --- (e) turret, minion and no team -------------------------------------------------

## (e) A kill by a turret and by a minion pays the hold; a blow from no team pays nothing.
func _case_e() -> void:
	for who in ["turret", "minion"]:
		_ready_drone(d1a, HOLD, "out")
		var n := float(_living(0).size())
		_shoot(d1a, _blow(who))
		var paid := _living_paid("ore stolen", HOLD * (1.0 - _share) / n)
		var ok := _near(_treasury_rise(0), HOLD * _share) and paid
		ok = ok and _nobody_paid("drone") and _near(_counter_rise("ore_stolen", "stolen"), HOLD)
		_check("(e) a %s's kill pays the treasury and the living pilots" % who, ok, "treasury rose %.3f, wanted %.3f, flat bounty payments %d; %s" % [_treasury_rise(0), HOLD * _share, _count_reason("drone"), _last_detail])
	_ready_drone(d1a, HOLD, "out")
	_shoot(d1a, _blow("none"))
	var none_ok := absf(_treasury_rise(0)) <= EPS and absf(_treasury_rise(1)) <= EPS and _events.is_empty() and _near(_counter_rise("ore_stolen", "stolen"), 0.0)
	_check("(e) a blow from no team pays nothing", none_ok, "treasury rose %.3f and %.3f, %d payments, counter rose %s" % [_treasury_rise(0), _treasury_rise(1), _events.size(), _counter_rise("ore_stolen", "stolen")])
	_ready_drone(d1a, 0.0, "out")


# --- (f) escorts --------------------------------------------------------------------

## (f) The victim's escorts are its own team's pilots and are paid nothing.
func _case_f() -> void:
	_ready_drone(d1a, HOLD, "out")
	d1a.escorts[_pe] = true
	_shoot(d1a, _blow_of(_pa))
	var ok := not _paid.has(_pe) and _nobody_paid("escort") and _team1_unpaid()
	_check("(f) the victim's escorts are paid nothing", ok, "E paid %s, escort payments %d" % [_paid.has(_pe), _count_reason("escort")])
	_ready_drone(d1a, 0.0, "out")


# --- (g) delivered ore --------------------------------------------------------------

## (g) Delivered ore pays as before, and a steal pays the same shares as a delivery of the same ore.
func _case_g() -> void:
	var n := float(_living(0).size())
	_begin()
	Economy.deliver_ore(world, 0, 100.0, null)
	var paid := _living_paid("ore", 100.0 * (1.0 - _share) / n)
	var ok := _near(float(world.teams[0].ore_delivered) - float(_before["delivered"]), 100.0) and _near(_treasury_rise(0), 100.0 * _share) and paid
	_check("(g) delivered ore pays as before", ok, "delivered rose %.3f, treasury rose %.3f; %s" % [float(world.teams[0].ore_delivered) - float(_before["delivered"]), _treasury_rise(0), _last_detail])
	# A delivery of 300, then a steal of 300 by a turret (no flat bounty added): the same pay.
	_begin()
	Economy.deliver_ore(world, 0, HOLD, null)
	var d_treasury := _treasury_rise(0)
	var d_each := {}
	for p: PilotProfile in _living(0):
		d_each[p] = _got(p, "ore")
	_ready_drone(d1a, HOLD, "out")
	_shoot(d1a, _blow("turret"))
	var same := absf(_treasury_rise(0) - d_treasury) <= EPS
	var parts := PackedStringArray()
	for p: PilotProfile in _living(0):
		var s := _got(p, "ore stolen")
		parts.append("%s %.3f/%.3f" % [p.callsign, s, float(d_each[p])])
		if absf(s - float(d_each[p])) > EPS:
			same = false
	_check("(g) a steal of 300 pays the same treasury and living shares as a delivery of 300", same, "treasury %.3f/%.3f; %s" % [_treasury_rise(0), d_treasury, "; ".join(parts)])
	_ready_drone(d1a, 0.0, "out")


# --- (h) the switch -----------------------------------------------------------------

## The switch Game.drone_ore_steal: 1 for on, 0 for off, -1 when the build has none.
func _switch_value() -> int:
	var v: Variant = Game.get("drone_ore_steal")
	if v == null:
		return -1
	return 1 if bool(v) else 0


## Put the switch on or off (nothing happens when the build has none).
func _set_switch(on: bool) -> void:
	Game.set("drone_ore_steal", on)


## (h) With the switch off a full hold pays only the flat bounty.
func _case_h() -> void:
	_check("(h) the switch drone_ore_steal exists", "drone_ore_steal" in Game, "")
	_set_switch(false)
	_ready_drone(d1a, HOLD, "out")
	_shoot(d1a, _blow_of(_pa))
	var flat := _flat(_pa)
	var ok := absf(_got(_pa, "drone") - flat) <= EPS and absf(_treasury_rise(0)) <= EPS and _count_reason("ore stolen") == 0
	ok = ok and _near(_counter_rise("ore_stolen", "stolen"), 0.0)
	_check("(h) with the switch off a full hold pays only the flat bounty", ok, "A drone %.3f/%.3f, treasury rose %.3f, ore stolen payments %d, counter rose %s" % [_got(_pa, "drone"), flat, _treasury_rise(0), _count_reason("ore stolen"), _counter_rise("ore_stolen", "stolen")])
	_set_switch(true)
	_check("(h) the switch reads on after it is put back", _switch_value() == 1, "reads %d" % _switch_value())
	_ready_drone(d1a, 0.0, "out")


# --- (i) the earnings line ----------------------------------------------------------

## (i) The earnings line has a plain word for the new reason, and the killer hears of the payment.
func _case_i() -> void:
	var word := str(HudMePanel.EARN_REASON.get("ore stolen", ""))
	_check("(i) the killing pilot's earnings line has a plain-word reason", word != "" and not word.contains("_"), "word '%s'" % word)
	_ready_drone(d1a, HOLD, "out")
	var credits_before := _pa.credits
	_shoot(d1a, _blow_of(_pa))
	var rise := _pa.credits - credits_before
	var own := _got(_pa, "ore stolen")
	var heard := 0
	for e: Array in _events:
		if e[0] == _pa and e[2] == "ore stolen":
			heard += 1
	var ok := heard == 1 and absf(own - (rise - _flat(_pa))) <= EPS
	_check("(i) the killing pilot hears of the payment", ok, "payments %d, ore stolen %.3f, credits rose %.3f, flat %.3f" % [heard, own, rise, _flat(_pa)])
	_ready_drone(d1a, 0.0, "out")


# --- (j) the live caller ------------------------------------------------------------

## (j) A drone shot down through Combat.kill() pays the hold (the hold is still full when Economy runs).
func _case_j() -> void:
	var p := PilotProfile.new("J", 0, 60 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	var ship := world.launch(p)
	ship.velocity = Vector2.ZERO
	ship.controller = null
	_ready_drone(d1d, HOLD, "mine")
	var n := float(_living(0).size())
	_begin()
	world.combat.kill(d1d, DamageInfo.from_unit(ship, 1.0, Rules.W_PURE, d1d.global_position))
	var paid := _living_paid("ore stolen", HOLD * (1.0 - _share) / n)
	var ok := _near(_treasury_rise(0), HOLD * _share) and _near(_counter_rise("ore_stolen", "stolen"), HOLD) and paid
	_check("(j) a drone shot down through Combat.kill pays the hold", ok, "treasury rose %.3f, wanted %.3f, counter rose %s; %s" % [_treasury_rise(0), HOLD * _share, _counter_rise("ore_stolen", "stolen"), _last_detail])


# --- (k) the pull of a fuller drone -------------------------------------------------

## The constant DRONE_ORE_PULL of the computer pilots' targeting, or NAN when the build has none.
func _pull_const() -> float:
	var scr: Script = PilotTargeting
	var m: Dictionary = scr.get_script_constant_map()
	if not m.has("DRONE_ORE_PULL"):
		return NAN
	return float(m["DRONE_ORE_PULL"])


## What drone_ore_pull(cargo, capacity) answers, or NAN when the build has no such function.
func _pull(cargo: float, capacity: float) -> float:
	var scr: Script = PilotTargeting
	if not scr.has_method("drone_ore_pull"):
		return NAN
	return float(scr.call("drone_ore_pull", cargo, capacity))


## (k) The pull is 0 for an empty hold, the whole constant for a full one, in proportion between, and never more.
func _case_k() -> void:
	var p := _pull_const()
	_check("(k) the pull of an empty hold is 0", _near(_pull(0.0, 300.0), 0.0) and _near(_pull(0.0, 0.0), 0.0) and _near(_pull(0.0, 1000.0), 0.0) and _near(_pull(-5.0, 300.0), 0.0), "pulls %s %s %s %s" % [_pull(0.0, 300.0), _pull(0.0, 0.0), _pull(0.0, 1000.0), _pull(-5.0, 300.0)])
	_check("(k) the pull of a full hold is DRONE_ORE_PULL", _near(_pull(300.0, 300.0), p) and _near(_pull(450.0, 450.0), p), "pulls %s %s, constant %s" % [_pull(300.0, 300.0), _pull(450.0, 450.0), p])
	_check("(k) a half hold pulls half of DRONE_ORE_PULL", _near(_pull(150.0, 300.0), p * 0.5), "pull %s, wanted %s" % [_pull(150.0, 300.0), p * 0.5])
	_check("(k) the pull never exceeds DRONE_ORE_PULL", _near(_pull(900.0, 300.0), p) and _near(_pull(301.0, 300.0), p), "pulls %s %s, constant %s" % [_pull(900.0, 300.0), _pull(301.0, 300.0), p])


# --- (l) the pick -------------------------------------------------------------------

## A direction from `from` along which no rock stands within 1,700 units, or Vector2.ZERO when every direction has one
## (a rock between a pilot and a drone makes the drone score worse, which would hide the pull these cases measure).
func _clear_dir(from: Vector2) -> Vector2:
	for i in 24:
		var d := Vector2.from_angle(float(i) * TAU / 24.0)
		if not world.asteroids.segment_blocked(from, from + d * 1700.0):
			return d
	return Vector2.ZERO


## A point with no ship, turret or minion of team 1 within QUIET_R of it and a clear direction, else the home spot.
func _quiet_spot() -> Vector2:
	var pred := func(u: Unit) -> bool: return u.kind == Unit.K_SHIP or u.kind == Unit.K_TURRET or u.kind == Unit.K_MINION
	for gy in range(-8, 9):
		for gx in range(-8, 9):
			var p := Vector2(MapLayout.CX + float(gx) * 1500.0, MapLayout.CY + float(gy) * 1500.0)
			if world.nearest_enemy(p, QUIET_R, 0, pred) == null and _clear_dir(p) != Vector2.ZERO:
				return p
	return Vector2(MapLayout.CX, MapLayout.CY - 1400.0)


## Stand drone `d` at `at`, alive and visible to team 0, and rebuild the spatial hashes.
func _stand(d: MiningDrone, at: Vector2) -> void:
	d.global_position = at
	d.alive = true
	d.visible_mask = 0xFF
	world.registry.rebuild_hashes()


## Make the pilot ship and its brain of the pick cases at the quiet spot, and send the spare drones far away.
func _make_picker() -> void:
	_home = _quiet_spot()
	var p := PilotProfile.new("Picker", 0, 60 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	_me = world.launch(p)
	_me.controller = null
	_me.global_position = _home
	_me.rotation = 0.0
	_me.velocity = Vector2.ZERO
	_me.shields.fill()
	_me.shields.since_hit = 999.0
	_me.fill_energy()
	_me.visible_mask = 0xFF
	_brain = PilotAI.new(world, _me.profile)
	_brain.state = "lane"
	_stand(d1a, Vector2(-5000.0, -5000.0))
	for d in _drones_of(1):
		if d != d1b and d != d1c:
			_stand(d, Vector2(-5000.0, -5000.0))


## The drone the picker takes between `d1b` (hold `b_cargo`, `b_extra` units beyond PICK_BASE) and `d1c` (hold
## `c_cargo`, `c_extra` beyond PICK_BASE), both on one line from the pilot, taken from a brain with no current target.
func _pick(b_cargo: float, b_extra: float, c_cargo: float, c_extra: float) -> Unit:
	var dir := _clear_dir(_home)
	d1b.cargo = b_cargo
	d1c.cargo = c_cargo
	_stand(d1b, _home + dir * (PICK_BASE + b_extra))
	_stand(d1c, _home + dir * (PICK_BASE + c_extra))
	_brain.target = null
	_brain.lock_target = null
	return _brain.targeting.pick_target(_me, PICK_R)


## (l) Between a fuller and an emptier drone the pilot picks by the pull; with the switch off, as before.
func _case_l() -> void:
	_make_picker()
	var c := _pull_const()
	_check("(l) the constant DRONE_ORE_PULL exists", not is_nan(c), "constant %s" % c)
	var pull := PULL_GUESS if is_nan(c) else c
	var cap := d1b.capacity
	var pick := _pick(cap, pull - 50.0, 0.0, 0.0)
	_check("(l) a full drone P minus 50 farther than an empty one is picked", pick == d1b, "picked %s" % ("full" if pick == d1b else ("empty" if pick == d1c else "other")))
	pick = _pick(cap, pull + 50.0, 0.0, 0.0)
	_check("(l) a full drone P plus 50 farther than an empty one is not picked", pick == d1c, "picked %s" % ("full" if pick == d1b else ("empty" if pick == d1c else "other")))
	pick = _pick(cap * 0.5, pull * 0.5 - 25.0, 0.0, 0.0)
	_check("(l) a half-full drone P/2 minus 25 farther is picked", pick == d1b, "picked %s" % ("half" if pick == d1b else ("empty" if pick == d1c else "other")))
	pick = _pick(cap * 0.5, pull * 0.5 + 25.0, 0.0, 0.0)
	_check("(l) a half-full drone P/2 plus 25 farther is not picked", pick == d1c, "picked %s" % ("half" if pick == d1b else ("empty" if pick == d1c else "other")))
	pick = _pick(0.0, 0.0, 0.0, 100.0)
	_check("(l) two empty drones: the nearer is picked as today", pick == d1b, "picked %s" % ("nearer" if pick == d1b else ("farther" if pick == d1c else "other")))
	_set_switch(false)
	pick = _pick(cap, 10.0, 0.0, 0.0)
	_check("(l) with the switch off the fuller drone gets no pull", pick == d1c, "picked %s" % ("full" if pick == d1b else ("empty" if pick == d1c else "other")))
	_set_switch(true)
