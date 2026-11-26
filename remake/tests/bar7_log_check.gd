extends Node
## WHAT THIS IS: the check of the pilot lines in the computer Admirals' decision log (scripts/ai/pilot_log.gd
## and the pilot part of scripts/ai/admiral_log.gd) and of the line that says an Admiral switch took
## (AdmiralProfile.switch_line). It proves that a pilot's plan and a change of its target each write one plain
## line (what it chose, what it almost chose, why) only after they held PLAN_HOLD seconds, that a change that
## did not hold is counted and not written, that every plan and every swap has all three parts in plain words,
## that a pilot line is neither an order line nor an Admiral line, that a team whose decision_log is off and a
## brain that is not a seat pilot write nothing, that an Admiral line is unchanged, and that the switch line is
## empty for the standard profile and names the profile and each changed row in the option's own form.
##
## HOW IT WORKS: setup() runs the cases that need no pilot (the Admiral line and the four switch-line cases)
## and then waits: every physics tick it looks for a team-0 seat pilot that is flying (not the Admiral's own
## ship). The moment it finds one it runs every pilot case in one call, with no wait inside it (so no think of
## the brain runs between two steps), on a log of its own that writes no file and with a clock the check sets
## and puts back. Every access to the new code is untyped, so a tree without it fails by assertion and never by
## a parse error. If no pilot flies within WAIT_SECS of match time the check fails; it never hangs.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --secs=240 --test=bar7_log_check
##
## WHO USES IT: main.gd loads it for --test=bar7_log_check (it calls setup()).

## Match seconds to wait for a flying seat pilot before the check fails.
const WAIT_SECS := 120.0
## The clock the pilot cases run on (match seconds).
const T := 1000.0
## The plan words that must not show up in a line a player reads.
const CODE_WORDS := ["_", "::", "res://", "null"]
## The count of pilot cases (they are all skipped together when no pilot is found).
const PILOT_CASES := 17

## How many checks failed.
var _fails := 0
## How many cases were skipped (a green run has none).
var _skipped := 0
## The match the check runs in.
var _world: World
## The PilotLog script, or null when the tree has none.
var _plog: Variant = null
## The AdmiralProfile script (for the untyped call of switch_line).
var _apc: Variant = null
## True while the check waits for a flying seat pilot.
var _waiting := false
## The match second the wait began.
var _wait_start := 0.0
## True once the result line is printed.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	_world = w
	var path := "res://scripts/ai/pilot_log.gd"
	_plog = load(path) if ResourceLoader.exists(path) else null
	_apc = load("res://scripts/ai/admiral_profile.gd")
	_check("pilot_log.gd exists", _plog != null)
	_admiral_line(w)
	_switch_cases()
	if _plog == null:
		_finish()
		return
	var have: bool = _has_static(_plog, "watch") and _has_static(_plog, "words")
	var consts: Dictionary = (_plog as Script).get_script_constant_map()
	have = have and consts.has("PLAN_HOLD") and consts.has("PLANS")
	_check("pilot_log.gd has watch, words, PLAN_HOLD and PLANS", have)
	if not have:
		_finish()
		return
	_wait_start = w.time
	_waiting = true


## Look each tick for the pilot the cases read; run them all when one is flying.
func _physics_process(_dt: float) -> void:
	if _world == null or not _waiting or _done:
		return
	var brain := _find_pilot()
	if brain != null:
		_waiting = false
		_pilot_cases(_world, brain)
		_finish()
	elif _world.time - _wait_start > WAIT_SECS:
		_waiting = false
		_check("pilot: a team-0 seat pilot is flying within 120 s", false, "match time %.0f" % _world.time)
		_skipped += PILOT_CASES
		_finish()


## Print the result line and stop soon after.
func _finish() -> void:
	if _done:
		return
	_done = true
	if _plog != null:
		_check("no case is skipped", _skipped == 0, str(_skipped))
	print("bar7_log_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Does script `s` have a function called `fname` (static ones count)?
func _has_static(s: Variant, fname: String) -> bool:
	for m: Dictionary in (s as Script).get_script_method_list():
		if str(m.get("name", "")) == fname:
			return true
	return false


## The number a member of the log holds (-1 when it has none, so a missing member fails its case).
func _n(lg: Variant, member: String) -> int:
	var v: Variant = (lg as Object).get(member)
	return int(v) if v is int else -1


## The lines a log kept for pilots (empty when it has no such member).
func _pilot_recent(lg: Variant) -> Array:
	var v: Variant = (lg as Object).get("pilot_recent")
	return v as Array if v is Array else []


## A log of its own: no file, on, and made from the match's own world.
func _own_log(w: World, on: bool) -> Variant:
	var lg: Variant = AdmiralLog.new(w)
	lg.enabled = on
	return lg


## The first team-0 seat pilot that is flying a valid ship and is not the Admiral's own ship, or null.
func _find_pilot() -> PilotAI:
	for key: Variant in _world.pilot_ai:
		var brain := _world.pilot_ai[key] as PilotAI
		if brain == null or brain.profile.team != 0 or brain.profile.role == "admiral":
			continue
		if brain.profile.state == "flying" and brain.profile.ship != null and is_instance_valid(brain.profile.ship):
			return brain
	return null


## watch() of the new code at match second `T + x`.
func _watch(brain: PilotAI, lg: Variant, x: float) -> void:
	_world.time = T + x
	(_plog as Object).call("watch", brain, brain.profile.ship, lg)


## words() of the new code, as a Dictionary ({} when it gave none).
func _words(plan: String, facts: Dictionary) -> Dictionary:
	var v: Variant = (_plog as Object).call("words", plan, facts)
	return v as Dictionary if v is Dictionary else {}


## An Admiral line is written as before (the word "Admiral" and no pilot word).
func _admiral_line(w: World) -> void:
	if w.admiral_ai[0] == null:
		_check("log: team 0 has a computer Admiral", false)
		return
	var lg: Variant = _own_log(w, true)
	var saved_time := w.time
	w.time = 100.0
	lg.note(0, "yard.save", "saves for a Destroyer (3000)")
	var recent: Array = (lg as Object).get("recent")
	_check("log: an Admiral line is unchanged", recent.size() == 1 and str(recent[0]).begins_with("1:40 Aurelian Admiral saves for a Destroyer"), str(recent))
	w.time = saved_time
	lg.enabled = false


## The four cases of the switch line (no pilot, no world).
func _switch_cases() -> void:
	var has := _apc != null and _has_static(_apc, "switch_line")
	var std := AdmiralProfile.for_team(0, {})
	var line := _switch(has, std)
	_check("switch line: none for the standard profile", has and line == "", "'%s'" % line)
	var opts := {"admiral-set": "0:fleet_play=1;0:team_view=1"}
	var l0 := _switch(has, AdmiralProfile.for_team(0, opts))
	var l1 := _switch(has, AdmiralProfile.for_team(1, opts))
	var ok := has and l0.contains("team 0") and l0.contains("Aurelian") and l0.contains("profile=standard") and l0.contains("fleet_play=1") and l0.contains("team_view=1") and l1 == ""
	_check("switch line: names the profile and each changed row in the option's form", ok, "'%s' '%s'" % [l0, l1])
	var same := _switch(has, AdmiralProfile.for_team(0, {"admiral-set": "0:fleet_play=0"}))
	_check("switch line: a row set to its own standard value is no change", has and same == "", "'%s'" % same)
	var named := _switch(has, AdmiralProfile.for_team(1, {"admiral-profile": "1:weak"}))
	_check("switch line: a named profile is a change", has and named.contains("profile=weak"), "'%s'" % named)


## The switch line of record `p` ("" when the tree has no switch_line).
func _switch(has: bool, p: AdmiralProfile) -> String:
	if not has:
		return ""
	return str((_apc as Object).call("switch_line", p))


## Every pilot case, in one call with no wait: the brain `brain` (a flying team-0 seat pilot) on a log of its own.
func _pilot_cases(w: World, brain: PilotAI) -> void:
	var consts: Dictionary = (_plog as Script).get_script_constant_map()
	var hold := float(consts["PLAN_HOLD"])
	var plans: Variant = consts["PLANS"]
	# The two enemy turrets of the swap cases.
	var enemy: Array[Turret] = []
	for t: Turret in w.turrets:
		if t.team != brain.profile.team and t.alive and t.is_built():
			enemy.append(t)
	var have_two := enemy.size() >= 2
	_check("pilot: two enemy turrets stand to swap between", have_two)
	var t_a: Turret = enemy[0] if enemy.size() > 0 else null
	var t_b: Turret = enemy[1] if have_two else null
	# Save what the call sets, and put it back at the end.
	var saved_time := w.time
	var s_state := brain.state
	var s_soft := brain.soft_retreat
	var s_recalled := brain.recalled
	var s_reason := brain.home_reason
	var s_intent := brain.intent
	var s_target := brain.target
	var s_evade := brain.evade_t
	var s_fallback := brain.fallback_t
	var s_skip_id := brain.skip_id
	var s_skip_until := brain.skip_until
	brain.evade_t = 0.0
	brain.fallback_t = 0.0
	brain.skip_id = 0
	brain.skip_until = 0.0
	var lg: Variant = _own_log(w, true)
	var before := [lg.lines, lg.order_lines, (lg.recent as Array).size()]
	var x := 0.0
	var step := hold + 0.1
	# step 1: with the log off nothing is written and nothing is kept.
	var off_lg: Variant = _own_log(w, false)
	brain.state = "lane"
	brain.intent = "push"
	brain.target = t_a
	_watch(brain, off_lg, x)
	_watch(brain, off_lg, x + step)
	var kept: Variant = (off_lg as Object).get("pilot_plans")
	_check("pilot: with the log off nothing is written and nothing is kept", _n(off_lg, "pilot_lines") == 0 and kept is Dictionary and (kept as Dictionary).is_empty())
	# step 2: the first plan is written only after it has held PLAN_HOLD seconds.
	_watch(brain, lg, x)
	var at_once := _n(lg, "pilot_lines")
	x += step
	_watch(brain, lg, x)
	var pr := _pilot_recent(lg)
	var head := "%s %s pilot %s (" % [Util.clock(w.time), Rules.TEAM_DISPLAY[brain.profile.team], brain.profile.callsign]
	_check("pilot: the first plan is written only after it has held PLAN_HOLD seconds", at_once == 0 and _n(lg, "pilot_lines") == 1 and pr.size() == 1 and str(pr[0]).begins_with(head) and str(pr[0]).contains("launches and attacks an enemy turret"), "%d %s" % [at_once, str(pr)])
	# step 3: a change writes one line with the runner-up.
	brain.state = "retreat"
	brain.soft_retreat = false
	x += 0.1
	_watch(brain, lg, x)
	x += step
	_watch(brain, lg, x)
	pr = _pilot_recent(lg)
	_check("pilot: a change writes one line with the runner-up", _n(lg, "pilot_lines") == 2 and pr.size() == 2 and str(pr[1]).contains("turns back to repair over") and str(pr[1]).contains("%"), str(pr))
	# step 4: a plan shorter than PLAN_HOLD is held back and counted.
	brain.state = "home"
	brain.recalled = true
	x += 0.1
	_watch(brain, lg, x)
	brain.state = "retreat"
	brain.recalled = false
	x += 0.1
	_watch(brain, lg, x)
	_check("pilot: a plan shorter than PLAN_HOLD is held back and counted", _n(lg, "pilot_lines") == 2 and _n(lg, "pilot_held") == 1, "%d %d" % [_n(lg, "pilot_lines"), _n(lg, "pilot_held")])
	# step 5: no change, no line.
	x += step
	_watch(brain, lg, x)
	x += step
	_watch(brain, lg, x)
	_check("pilot: no change, no line", _n(lg, "pilot_lines") == 2 and _n(lg, "pilot_held") == 1, "%d %d" % [_n(lg, "pilot_lines"), _n(lg, "pilot_held")])
	# step 6: a target change in a plan with no target in its key writes nothing.
	brain.target = t_a
	_watch(brain, lg, x + 0.1)
	brain.target = t_b if have_two else t_a
	_watch(brain, lg, x + 0.2)
	x += step + 0.2
	_watch(brain, lg, x)
	_check("pilot: a target change in a plan with no target in its key writes nothing", _n(lg, "pilot_lines") == 2 and _n(lg, "pilot_held") == 1, "%d %d" % [_n(lg, "pilot_lines"), _n(lg, "pilot_held")])
	if not have_two:
		_skipped += 5
		_pilot_tail(w, brain, lg, plans, before, x)
		_restore(w, brain, [saved_time, s_state, s_soft, s_recalled, s_reason, s_intent, s_target, s_evade, s_fallback, s_skip_id, s_skip_until])
		lg.enabled = false
		return
	# step 7: a target swap writes one line that names the new target and the old.
	brain.state = "lane"
	brain.intent = "push"
	brain.target = t_a
	x += 0.1
	_watch(brain, lg, x)
	x += step
	_watch(brain, lg, x)
	var plan_line_ok := _n(lg, "pilot_lines") == 3
	brain.target = t_b
	x += 0.1
	_watch(brain, lg, x)
	x += step
	_watch(brain, lg, x)
	pr = _pilot_recent(lg)
	var last := str(pr[pr.size() - 1]) if pr.size() > 0 else ""
	_check("pilot: a target swap writes one line that names the new target and the old", plan_line_ok and _n(lg, "pilot_lines") == 4 and _n(lg, "pilot_swaps") == 1 and last.contains("switches to an enemy turret over staying on an enemy turret") and last.contains("the new one is the better pick") and last.contains("change=swap"), last)
	# step 8: a swap says when its old target is gone.
	var was_alive := t_b.alive
	t_b.alive = false
	brain.target = t_a
	x += 0.1
	_watch(brain, lg, x)
	x += step
	_watch(brain, lg, x)
	t_b.alive = was_alive
	pr = _pilot_recent(lg)
	last = str(pr[pr.size() - 1]) if pr.size() > 0 else ""
	_check("pilot: a swap says when its old target is gone", _n(lg, "pilot_lines") == 5 and _n(lg, "pilot_swaps") == 2 and last.contains("its old target is gone"), last)
	# step 9: a swap says when it gave up on the old target behind rocks.
	brain.target = t_b
	brain.skip_id = t_a.get_instance_id()
	brain.skip_until = w.time + 100.0
	x += 0.1
	_watch(brain, lg, x)
	x += step
	_watch(brain, lg, x)
	pr = _pilot_recent(lg)
	last = str(pr[pr.size() - 1]) if pr.size() > 0 else ""
	_check("pilot: a swap says when it gave up on the old target behind rocks", _n(lg, "pilot_lines") == 6 and last.contains("it gave up on the old one behind the rocks"), last)
	brain.skip_id = s_skip_id
	brain.skip_until = s_skip_until
	# step 10: a swap shorter than PLAN_HOLD is held back and counted.
	brain.target = t_a
	x += 0.1
	_watch(brain, lg, x)
	brain.target = t_b
	x += 0.1
	_watch(brain, lg, x)
	_check("pilot: a swap shorter than PLAN_HOLD is held back and counted", _n(lg, "pilot_lines") == 6 and _n(lg, "pilot_held") == 2, "%d %d" % [_n(lg, "pilot_lines"), _n(lg, "pilot_held")])
	# step 11: swaps are counted apart from plan lines.
	_check("pilot: swaps are counted apart from plan lines", _n(lg, "pilot_swaps") == 3 and _n(lg, "pilot_lines") == 6, "%d %d" % [_n(lg, "pilot_swaps"), _n(lg, "pilot_lines")])
	_pilot_tail(w, brain, lg, plans, before, x)
	_restore(w, brain, [saved_time, s_state, s_soft, s_recalled, s_reason, s_intent, s_target, s_evade, s_fallback, s_skip_id, s_skip_until])
	lg.enabled = false


## Steps 12 to 17 of the pilot call (they read the log the steps before made, and the words).
func _pilot_tail(w: World, brain: PilotAI, lg: Variant, plans: Variant, before: Array, x_in: float) -> void:
	var x := x_in
	var hold := float(((_plog as Script).get_script_constant_map())["PLAN_HOLD"])
	var step := hold + 0.1
	# step 12: every line has a runner-up and a reason.
	var rx := RegEx.create_from_string(r"^\d+:\d\d (Aurelian|Vhorr) .+ over .+: .+  \[rule=pilot\.")
	var pr := _pilot_recent(lg)
	var all_ok := pr.size() >= 1
	var bad := ""
	for line: Variant in pr:
		var s := str(line)
		var tail_ok := true
		for part: String in ["change=", "state=", "prev=", "seat=", "team=", "t="]:
			tail_ok = tail_ok and s.contains(" " + part)
		if rx.search(s) == null or not tail_ok:
			all_ok = false
			bad = s
	_check("pilot: every line has a runner-up and a reason", all_ok and pr.size() == _n(lg, "pilot_lines"), bad)
	# step 13: a pilot line is no order line and no Admiral line.
	_check("pilot: a pilot line is no order line and no Admiral line", lg.lines == before[0] and lg.order_lines == before[1] and (lg.recent as Array).size() == before[2] and pr.size() == _n(lg, "pilot_lines"), "%d %d %d" % [lg.lines, lg.order_lines, (lg.recent as Array).size()])
	# step 14: a team whose decision_log is off writes nothing.
	var ai: AdmiralAI = w.admiral_ai[brain.profile.team]
	var count := _n(lg, "pilot_lines")
	if ai != null:
		var was_on := ai.profile.raw("decision_log")
		ai.profile.set_value("decision_log", 0)
		brain.state = "home"
		brain.recalled = true
		x += 9.0 * hold
		_watch(brain, lg, x)
		x += step
		_watch(brain, lg, x)
		_watch(brain, lg, x + step)
		ai.profile.set_value("decision_log", was_on)
		_check("pilot: a team whose decision_log is off writes nothing", _n(lg, "pilot_lines") == count)
	else:
		_check("pilot: a team whose decision_log is off writes nothing", false, "team has no Admiral")
	# step 15: a brain that is not a seat pilot writes nothing.
	var standin := PilotAI.new(w, brain.profile)
	standin.state = "lane"
	x += step
	_watch(standin, lg, x)
	x += step
	_watch(standin, lg, x)
	standin.state = "retreat"
	x += step
	_watch(standin, lg, x)
	x += step
	_watch(standin, lg, x)
	_check("pilot: a brain that is not a seat pilot writes nothing", _n(lg, "pilot_lines") == count, str(_n(lg, "pilot_lines")))
	# step 16: every plan has all three parts and plain words.
	var bad16 := ""
	var tword := "an enemy turret"
	for key: Variant in plans:
		for ms: bool in ([false, true] if str(key) == "lane|push" else [false]):
			var w16 := _words(str(key), _facts(tword, "alive", false, ms))
			bad16 += _parts_bad("%s%s" % [key, " (mothership)" if ms else ""], w16, "")
	_check("pilot: every plan has all three parts and plain words", bad16 == "" and plans != null, bad16)
	# step 17: every swap has all three parts and plain words.
	var bad17 := ""
	for key: String in ["lane|push", "lane|prey", "lane|farm", "lane|fight", "jungle|fight", "jungle|camp"]:
		for old_state: String in ["alive", "gone", "hidden"]:
			var w17 := _words(key, _facts(tword, old_state, true, false))
			bad17 += _parts_bad("%s swap %s" % [key, old_state], w17, "goes to another" if key == "jungle|camp" else "switches to")
	_check("pilot: every swap has all three parts and plain words", bad17 == "", bad17)


## The facts a words() call reads, made up (see PilotLog.facts_of for the real ones).
func _facts(tword: String, old_state: String, swap: bool, mothership: bool) -> Dictionary:
	return {
		"first": false, "swap": swap, "hull_pct": 31, "total_pct": 24, "hull_label": "Destroyer",
		"gear_label": "Neural-Link Helmet", "tword": tword, "old_tword": "an enemy turret",
		"old_state": old_state, "mothership": mothership, "opening": false,
	}


## A note naming `what` when a words() result lacks a part, has a part over 200 characters, holds a code word
## or does not begin with `chose_start` ("" for any start); "" when it is fine.
func _parts_bad(what: String, parts: Dictionary, chose_start: String) -> String:
	for part: String in ["chose", "over", "why"]:
		var text := str(parts.get(part, ""))
		if text == "" or text.length() > 200:
			return "[%s: %s is empty or too long] " % [what, part]
		for word: String in CODE_WORDS:
			if text.contains(word):
				return "[%s: %s holds '%s'] " % [what, part, word]
	if chose_start != "" and not str(parts.get("chose", "")).begins_with(chose_start):
		return "[%s: chose does not begin with %s] " % [what, chose_start]
	return ""


## Put back what the pilot call set.
func _restore(w: World, brain: PilotAI, saved: Array) -> void:
	w.time = float(saved[0])
	brain.state = str(saved[1])
	brain.soft_retreat = bool(saved[2])
	brain.recalled = bool(saved[3])
	brain.home_reason = str(saved[4])
	brain.intent = str(saved[5])
	brain.target = saved[6] as Unit
	brain.evade_t = float(saved[7])
	brain.fallback_t = float(saved[8])
	brain.skip_id = int(saved[9])
	brain.skip_until = float(saved[10])
