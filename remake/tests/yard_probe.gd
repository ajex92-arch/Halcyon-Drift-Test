extends Node
## WHAT THIS IS: the measurement of the computer Admirals' buying in a whole match: how full
## their fleets are, how much money they sit on, how often the head of the build list waits for ore,
## and how many of their orders are refused. It changes nothing in the match.
##
## HOW IT WORKS: once a second it looks at both teams' build lists; once a minute it prints one
## line per team:
##   YARD_ROW m=<minute> team=<t> fleet=<living+building+waiting>/<limit> used=<living+building>
##   target=<the fill schedule> treasury=<credits> lost=<bought ships lost so far>
##   pilots_income=<credits the team's pilots earned this minute>
## At the end it prints the numbers of the gates, per team and for both:
##   YARD_END used_from_12=<mean share of the limit used from minute 12, percent>
##   treasury_median_after_10=<credits> blocked_head=<percent of the match the head waited for ore>
##   refused=<percent of the computer's yard orders refused> yard_orders=<how many>
## and "yard_probe: gates ..." with the four gates: used at least 70 percent from 12:00, the
## treasury median after 10:00 at most 1,500, a blocked head under 10 percent, refused orders at
## most 2 percent.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/; the match is all computer):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --skill-jitter --secs=1800 --seed=301 --test=yard_probe
##
## WHO USES IT: the builder of the yard (the twelve-match set), the lead.

## The yard's order kinds, for counting refusals.
const YARD_KINDS := ["PRODUCE", "CANCEL", "MOVE_ITEM", "HOLD_ITEM", "SET_REPEAT", "SET_RALLY"]

## The running match.
var world: World
## The match second of the next sample.
var _next_sample := 1.0
## The match second of the next printed minute.
var _next_minute := 60.0
## Per team: seconds sampled.
var _seconds := [0, 0]
## Per team: seconds the head waited for ore.
var _blocked := [0, 0]
## Per team: the share of the limit used, one number per minute from minute 12.
var _used := [[], []]
## Per team: the treasury at each minute after minute 10.
var _treasury := [[], []]
## Per team: the pilots' credits earned at the start of the minute.
var _earned := [0.0, 0.0]
## Bought ships lost, per team.
var _lost := [0, 0]


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	Events.unit_killed.connect(_on_killed)


## A unit died: count a bought ship.
func _on_killed(u: Node, _info: RefCounted) -> void:
	var s := u as Ship
	if s != null and s.profile != null and s.profile.is_crew:
		_lost[s.team] = int(_lost[s.team]) + 1


## Every tick: sample every second, print every minute, end at --secs.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= _next_sample:
		_next_sample += 1.0
		_sample()
	if world.time >= _next_minute:
		_next_minute += 60.0
		_minute()
	if world.time >= float(Game.opt("secs", 1800)) or world.phase != "play":
		_end()
		get_tree().quit()


## One second: did the head of each team's list wait for ore?
func _sample() -> void:
	for t in 2:
		_seconds[t] = int(_seconds[t]) + 1
		var prod: Production = world.teams[t].production
		for it: Dictionary in prod.items:
			if it["running"] or it["held"] or it["started"]:
				continue
			if it["why"] == "ore":
				_blocked[t] = int(_blocked[t]) + 1
			break


## One minute: print each team's row and keep the numbers for the gates.
func _minute() -> void:
	var m := int(world.time / 60.0)
	for t in 2:
		var ts: TeamState = world.teams[t]
		var prod := ts.production
		var limit := prod.capacity.limit()
		var earned := 0.0
		for p: PilotProfile in world.profiles:
			if p.team == t and not p.is_crew and p.role != "admiral":
				earned += p.earned
		var income := earned - float(_earned[t])
		_earned[t] = earned
		var used := prod.capacity.used()
		if m >= 12:
			(_used[t] as Array).append(float(used) / float(limit))
		if m >= 10:
			(_treasury[t] as Array).append(ts.treasury)
		print("YARD_ROW m=%d team=%d fleet=%d/%d used=%d target=%d treasury=%d lost=%d pilots_income=%d" % [m, t, prod.capacity.alive() + prod.ships_in_list(), limit, used, RtsHulls.fill_target(world.time, limit), int(ts.treasury), int(_lost[t]), int(income)])


## The end: the gates' numbers.
func _end() -> void:
	var counts := world.orders.counters()
	var all_ok := true
	for t in 2:
		var used_mean := _mean(_used[t])
		var median := _median(_treasury[t])
		var blocked := 100.0 * float(_blocked[t]) / maxf(1.0, float(_seconds[t]))
		var orders := 0
		var refused := 0
		var row: Dictionary = counts.get("t%d" % t, {})
		for kind: String in YARD_KINDS:
			if row.has(kind):
				orders += int((row[kind] as Dictionary)["submitted"])
				for code in (row[kind] as Dictionary)["refused"]:
					refused += int(((row[kind] as Dictionary)["refused"] as Dictionary)[code])
		var refused_pct := 100.0 * float(refused) / maxf(1.0, float(orders))
		print("YARD_END team=%d used_from_12=%.1f treasury_median_after_10=%d blocked_head=%.1f refused=%.1f yard_orders=%d bought_lost=%d" % [t, 100.0 * used_mean, int(median), blocked, refused_pct, orders, int(_lost[t])])
		all_ok = all_ok and used_mean >= 0.70 and median <= 1500.0 and blocked < 10.0 and refused_pct <= 2.0
	print("yard_probe: gates %s (used >= 70%% from 12:00, treasury median after 10:00 <= 1500, blocked head < 10%%, refused <= 2%%)" % ("PASS" if all_ok else "MISS"))


## The mean of a list of numbers (0 for none).
func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var sum := 0.0
	for v in a:
		sum += float(v)
	return sum / float(a.size())


## The median of a list of numbers (0 for none).
func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() >> 1])
