extends Node
## WHAT THIS IS: the check that the bounty on a streak holder grows 5 s after each
## kill (the user test fork). Today's rule paid the whole streak bonus the moment the
## holder died; the new rule counts a kill of the streak in the bounty only once it is
## Rules.BOUNTY_GROW_DELAY (5 s) old, so a holder who dies inside 5 s of a kill (two
## pilots who kill each other in a trade) pays no step for that kill. The first kill of
## a streak grows nothing (Rules.BOUNTY_GROW_FREE_KILLS, 1), as before.
##
## HOW IT WORKS: --bounty-case=logic (the default) runs the cases on the real Economy in
## a small world, in the first tick. Pilot A has a ship, so A can be the killer and the
## victim: A makes kills on a ship of the other team through Economy.on_unit_killed() at
## match times set by hand, then pilot B (the other team) kills A's ship. What B is paid
## is the bounty, and every wanted number is worked here from Rules.KILL_BASE,
## Rules.KILL_VALUE_SHARE, the ship's bounty_value() and Rules.SHUTDOWN_PER_STREAK,
## never from Economy.grown_kills(). Each case also checks that the total paid is
## exactly the bounty. The cases are lettered, and every check line starts with its
## letter:
##   - A: three kills at t, t+1, t+2, killed at t+4.9: no kill is 5 s old, no growth.
##   - B: the same, killed at t+5.0: one kill landed, minus the free kill, no growth.
##   - C: killed at t+6.0: two landed, one step; killed at t+7.0: three landed, two steps.
##   - D: the delay tuned to 0: every kill counts at once, today's bounty exactly.
##   - E: the trade: kills at t and t+10, killed at t+12: no growth (the old rule paid one).
##   - F: a death empties the kill list and the streak; the next life starts clean.
##   - G: "shutdown_per_streak" tuned to 0 (the catch-up bounties switch): no growth.
##   - H: a minion kill or a bought ship's kill adds no entry to the kill list.
## --bounty-case=live runs on the real match (pilots, junglers and the admiral on): a
## bounty hook that returns 0 and so changes nothing records, at each pilot death, the
## streak and how many kills had landed. At --secs (or when the match ends) it prints
## "BOUNTY_LIVE deaths=<n> streak_deaths=<k> cut_deaths=<c> old_bonus=<credits>
## new_bonus=<credits>": the deaths, those with a streak of 2 or more, those where fewer
## kills had landed than the streak, and what the old and the new rule would pay. It
## fails if the landed kills ever exceed the streak, if the kill list and the streak
## disagree, or if the new bonus is above the old one.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --sim-only --test=bounty_grow_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --sim-only --secs=900 --test=bounty_grow_check --bounty-case=live
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <case> <details>" or "FAIL <case>
## <details>". The last line is "bounty_grow_check: N failures (M checks)"; 0 failures
## means the bounty grows as written.
##
## WHO USES IT: main.gd loads it for --test=bounty_grow_check. It is one of the checks
## of the Feature lane for anything that changes the bounty or the kill streak.

## A payout may differ from the wanted amount by this much (credits), for rounding in
## floating point numbers.
const EPS := 0.0001
## The match time that the cases count from (far from the real clock of the first tick).
const T0 := 1000.0

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True once the cases have run (they all run in the first tick).
var _ran := false
## The case that runs: "logic" or "live" (--bounty-case).
var _case := "logic"
## What each pilot was paid in the case that is running: profile -> reason -> credits.
var _paid := {}
## The id number used in damage logs for each pilot: profile -> uid.
var _uids := {}
## The next id number to give out (far above the ids of real units).
var _next_uid := 90000
## A Vhorr ship that plays the victim of A's kills.
var _victim_ship: Ship = null
## A's ship: A kills with it and is killed in it.
var _a_ship: Ship = null
## Pilot B of the other team: the one who kills A.
var _b: PilotProfile = null
## The match time at which the live case prints and quits (--secs).
var _secs := 900.0
## True once the live line is printed.
var _live_done := false
## Live: pilot deaths seen by the hook.
var _deaths := 0
## Live: deaths with a streak of 2 or more.
var _streak_deaths := 0
## Live: deaths where fewer kills had landed than the streak.
var _cut_deaths := 0
## Live: what the old rule would have added to the bounties (credits).
var _old_bonus := 0.0
## Live: what the new rule would have added to the bounties (credits).
var _new_bonus := 0.0
## Live: the most landed kills of any death (a check that it never exceeds the streak).
var _landed_over_streak := 0
## Live: deaths where the kill list and the streak disagreed in size.
var _size_mismatch := 0


## main.gd calls this once, right after the World is built. The logic case stops the
## minion waves and listens to the payments; the live case adds its hook.
func setup(w: World) -> void:
	world = w
	_case = str(Game.opt("bounty-case", "logic"))
	if _case == "live":
		_secs = float(Game.opt("secs", 900.0))
		world.bounty_hooks.append(_hook)
		Events.match_over.connect(_on_match_over)
	else:
		world.minion_director.next_wave = INF
		Events.credits_earned.connect(_on_paid)


## A pilot was paid: add it to what that pilot has been paid in this case.
func _on_paid(p: RefCounted, amount: float, reason: String) -> void:
	if not _paid.has(p):
		_paid[p] = {}
	var d: Dictionary = _paid[p]
	d[reason] = float(d.get(reason, 0.0)) + amount


## Run the logic cases in the first tick and quit; the live case waits for its time.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if _case == "live":
		if not _live_done and (world.time >= _secs or world.phase != "play"):
			_finish_live()
			get_tree().quit()
		return
	if _ran:
		return
	_ran = true
	_victim_ship = _spawn_ship("Victim", 1)
	_a_ship = _spawn_ship("A", 0)
	_b = _pilot("B", 1)
	_cases_a_to_c()
	_case_d()
	_case_e()
	_case_f()
	_case_g()
	_case_h()
	print("bounty_grow_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers for the cases ---------------------------------------------------------

## Print one PASS or FAIL line for the check `name` (`ok` = it passed), with the
## `detail`, and count it.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## A new pilot record `name` of team `team`. It has no ship; its id number is made
## when it first hits something.
func _pilot(name: String, team: int) -> PilotProfile:
	return PilotProfile.new(name, team, 40 + _uids.size(), false)


## The id number that pilot `p`'s hits carry in a damage log.
func _uid(p: PilotProfile) -> int:
	if not _uids.has(p):
		_uids[p] = _next_uid
		_next_uid += 1
	return _uids[p]


## Launch a still ship for a new pilot `name` of team `team` (in a Fighter), and
## return the ship.
func _spawn_ship(name: String, team: int) -> Ship:
	var p := PilotProfile.new(name, team, 40 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	var s := world.launch(p)
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## Write into `victim`'s damage log that pilot `p` did `dmg` damage, `age` seconds ago.
func _hit(victim: Unit, p: PilotProfile, dmg: float, age: float = 0.0) -> void:
	victim.damage_log[_uid(p)] = [dmg, world.time - age, p]


## The killing blow. `who` is a PilotProfile (a pilot's blow), "minion" (a minion's) or
## "turret" (a turret's). The last two carry no pilot profile.
func _blow(who: Variant) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = 1.0
	d.kind = Rules.W_PURE
	if who is PilotProfile:
		var p: PilotProfile = who
		d.source_uid = _uid(p)
		d.source_team = p.team
		d.source_is_pilot = true
		d.source_profile = p
	elif str(who) == "minion":
		d.source_uid = 99991
		d.source_team = 0
		d.source_is_minion = true
	else:
		d.source_uid = 99992
		d.source_team = 0
	return d


## What `p` was paid for `reason` in this case (0 if nothing).
func _got(p: PilotProfile, reason: String) -> float:
	if not _paid.has(p):
		return 0.0
	return float((_paid[p] as Dictionary).get(reason, 0.0))


## Compare what was paid in this case with `want` (profile -> reason -> fraction of
## `base`), and print one line. Every payment must be wanted, and every wanted payment
## must be there, so the total paid is exactly the bounty.
func _compare(label: String, base: float, want: Dictionary) -> void:
	var ok := true
	var parts := PackedStringArray()
	var total := 0.0
	for p: PilotProfile in want:
		for reason: String in want[p]:
			var wanted := base * float(want[p][reason])
			var got := _got(p, reason)
			if absf(got - wanted) > EPS:
				ok = false
			parts.append("%s %s %.3f/%.3f" % [p.callsign, reason, got, wanted])
	for p: PilotProfile in _paid:
		for reason: String in _paid[p]:
			total += float(_paid[p][reason])
			if not (want.has(p) and (want[p] as Dictionary).has(reason)):
				ok = false
				parts.append("UNEXPECTED %s %s %.3f" % [p.callsign, reason, float(_paid[p][reason])])
	parts.append("total %.3f of %.3f" % [total, base])
	_check(label, ok, "; ".join(parts))


## Make a Vhorr minion of type `type_id` to be the victim.
func _minion(type_id: String) -> Minion:
	return world.spawn_minion(1, type_id, "mid", world.mothership(1).global_position)


## A new squad record in World.squads: team `team`, kind `kind`, hull `hull`.
func _squad(team: int, kind: String, hull: String) -> Squad:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = kind
	s.hull_id = hull
	s.max_members = 3 if kind == "squadron" else 1
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	return s


## A crew ship of hull `hull` for team `team` in `squad`, launched beside its own
## mothership, still, with no brain. The crew is in World.profiles, "flying".
func _crew_ship(team: int, hull: String, squad: Squad) -> Ship:
	var p := Crew.make(world, team, hull, squad, squad.member_uids.size())
	world.profiles.append(p)
	var ms := world.mothership(team)
	var s := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
	s.controller = null
	s.velocity = Vector2.ZERO
	p.ship = s
	p.state = "flying"
	squad.member_uids.append(s.uid)
	return s


## The bounty on A's ship now with `steps` growth steps of `per_step` credits each:
## Rules.KILL_BASE plus its share of the ship's value plus the steps.
func _want(steps: int, per_step: float = Rules.SHUTDOWN_PER_STREAK) -> float:
	return Rules.KILL_BASE + _a_ship.bounty_value() * Rules.KILL_VALUE_SHARE + per_step * float(steps)


## Start a fresh life for A: no streak, no kills on the list.
func _reset_a() -> void:
	_a_ship.profile.streak = 0
	_a_ship.profile.kill_times.clear()


## A kills the victim ship at match time `t` (A's streak and kill list grow by one).
func _a_kills(t: float) -> void:
	world.time = t
	_victim_ship.damage_log.clear()
	Economy.on_unit_killed(world, _victim_ship, _blow(_a_ship.profile))


## B kills A's ship at match time `t` and the payment is compared with the bounty `want`
## under `label`: B alone is paid all of it, and nobody else is paid.
func _b_kills_a(label: String, t: float, want: float) -> void:
	world.time = t
	_a_ship.damage_log.clear()
	_paid.clear()
	Economy.on_unit_killed(world, _a_ship, _blow(_b))
	_compare(label, want, {_b: {"kill": 1.0}})


## A makes one kill at each of the match-time offsets `kills` from T0, then is killed at
## offset `die_at`: `label` names the check, `steps` the growth steps the bounty must
## carry, and a setup line checks that the streak and the kill list hold every kill.
func _streak_case(label: String, kills: Array, die_at: float, steps: int, per_step: float = Rules.SHUTDOWN_PER_STREAK) -> void:
	_reset_a()
	for k: float in kills:
		_a_kills(T0 + k)
	var a := _a_ship.profile
	_check(label + " setup: every kill is on the streak and the list", a.streak == kills.size() and a.kill_times.size() == kills.size(), "streak %d list %d of %d" % [a.streak, a.kill_times.size(), kills.size()])
	_b_kills_a(label, T0 + die_at, _want(steps, per_step))


# --- the cases ---------------------------------------------------------------------

## A, B and C: three kills at t, t+1, t+2 and a death at 4.9, 5.0, 6.0 and 7.0 s.
func _cases_a_to_c() -> void:
	var kills := [0.0, 1.0, 2.0]
	_streak_case("A: three kills, killed at t+4.9 (none 5 s old), no growth", kills, 4.9, 0)
	_streak_case("B: three kills, killed at t+5.0 (one landed, one free), no growth", kills, 5.0, 0)
	_streak_case("C-6.0: three kills, killed at t+6.0 (two landed), one step", kills, 6.0, 1)
	_streak_case("C-7.0: three kills, killed at t+7.0 (three landed), two steps", kills, 7.0, 2)


## D: the delay tuned to 0 pays every kill at once, today's bounty.
func _case_d() -> void:
	Game.tunables["bounty_grow_delay"] = 0.0
	_streak_case("D: delay 0, three kills killed at once, two steps (today's bounty)", [0.0, 1.0, 2.0], 2.0, 2)
	_streak_case("D: delay 0, four kills killed at once, three steps (today's bounty)", [0.0, 1.0, 2.0, 3.0], 3.0, 3)
	Game.tunables.erase("bounty_grow_delay")


## E: the trade. Two kills 10 s apart and a death 2 s after the second: no growth.
func _case_e() -> void:
	_streak_case("E: kills at t and t+10, killed at t+12 (the second is 2 s old), no growth", [0.0, 10.0], 12.0, 0)


## F: a death empties the kill list and the streak, and the next life starts clean.
func _case_f() -> void:
	_streak_case("F: three kills, killed at t+7.0, two steps", [0.0, 1.0, 2.0], 7.0, 2)
	var a := _a_ship.profile
	_check("F: after the death the kill list is empty and the streak is 0", a.kill_times.is_empty() and a.streak == 0, "list %d streak %d" % [a.kill_times.size(), a.streak])
	_a_kills(T0 + 10.0)
	_b_kills_a("F: the next life, a kill and a death 3 s later, no growth", T0 + 13.0, _want(0))
	_a_kills(T0 + 20.0)
	_b_kills_a("F: the next life again, a kill and a death 6 s later, no growth (no old kill is left)", T0 + 26.0, _want(0))


## G: the catch-up switch ("shutdown_per_streak" 0) with delay 0 adds no step.
func _case_g() -> void:
	Game.tunables["shutdown_per_streak"] = 0.0
	Game.tunables["bounty_grow_delay"] = 0.0
	_streak_case("G: step tuned to 0, three kills killed at once, no growth", [0.0, 1.0, 2.0], 2.0, 0, 0.0)
	Game.tunables.erase("shutdown_per_streak")
	Game.tunables.erase("bounty_grow_delay")


## H: a minion kill and a bought ship's kill add no entry to A's kill list.
func _case_h() -> void:
	_reset_a()
	_a_kills(T0)
	var a := _a_ship.profile
	var before := a.kill_times.size()
	world.time = T0 + 1.0
	var m := _minion("bomber")
	_hit(m, a, 40.0)
	Economy.on_unit_killed(world, m, _blow(a))
	world.combat.kill_silently(m)
	_check("H: a minion kill adds no entry", a.kill_times.size() == before and a.streak == 1, "list %d of %d, streak %d" % [a.kill_times.size(), before, a.streak])
	var squad := _squad(1, "squadron", "fighter")
	var crew := _crew_ship(1, "fighter", squad)
	Economy.on_unit_killed(world, crew, _blow(a))
	_check("H: a bought ship's kill adds no entry", a.kill_times.size() == before and a.streak == 1, "list %d of %d, streak %d" % [a.kill_times.size(), before, a.streak])
	_reset_a()


# --- the live case -----------------------------------------------------------------

## The bounty hook of the live case: pilot `victim`'s ship `_ship` was destroyed.
## Record the streak and how many kills had landed, print the running totals, and
## add nothing to the bounty (it returns 0 and draws no random number).
func _hook(victim: PilotProfile, _ship: Ship) -> float:
	var landed := Economy.grown_kills(victim, world.time)
	_deaths += 1
	if victim.streak >= 2:
		_streak_deaths += 1
	if landed < victim.streak:
		_cut_deaths += 1
	if landed > victim.streak:
		_landed_over_streak += 1
	if victim.kill_times.size() != victim.streak:
		_size_mismatch += 1
	_old_bonus += Rules.SHUTDOWN_PER_STREAK * float(maxi(0, victim.streak - 1))
	_new_bonus += Rules.SHUTDOWN_PER_STREAK * float(maxi(0, landed - Rules.BOUNTY_GROW_FREE_KILLS))
	print("BOUNTY_LIVE_RUN t=%d deaths=%d streak_deaths=%d cut_deaths=%d old_bonus=%d new_bonus=%d" % [int(world.time), _deaths, _streak_deaths, _cut_deaths, int(_old_bonus), int(_new_bonus)])
	return 0.0


## The match is over (Events.match_over): print the live line now, before the run quits.
func _on_match_over(_winner: int, _reason: String) -> void:
	if not _live_done:
		_finish_live()


## Print the live line once, then the checks and the last line.
func _finish_live() -> void:
	_live_done = true
	print("BOUNTY_LIVE deaths=%d streak_deaths=%d cut_deaths=%d old_bonus=%d new_bonus=%d" % [_deaths, _streak_deaths, _cut_deaths, int(_old_bonus), int(_new_bonus)])
	_check("LIVE: no kill landed beyond the streak", _landed_over_streak == 0, "%d deaths" % _landed_over_streak)
	_check("LIVE: the kill list and the streak agree in size", _size_mismatch == 0, "%d deaths" % _size_mismatch)
	_check("LIVE: the new bonus is not above the old one", _new_bonus <= _old_bonus, "new %.0f old %.0f" % [_new_bonus, _old_bonus])
	_check("LIVE: at least one pilot death was seen", _deaths > 0, "%d deaths" % _deaths)
	print("bounty_grow_check: %d failures (%d checks)" % [fails, checks])
