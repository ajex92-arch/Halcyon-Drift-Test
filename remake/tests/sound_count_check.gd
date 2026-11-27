extends Node
## WHAT THIS IS: the sound counter. It counts the sound cues the simulation sends (Events.cue), per
## cue name and per match second, and flags two things in the printed log: SPAM (one cue name sent
## more than 20 times in one second) and SILENCE (a fight in which nothing at all was sent for 5
## seconds in a row). A match that is deafening or dead during a fight shows up in numbers, so nobody
## has to listen to find it. It only reads the match: it draws no random number, changes no world
## state and sends no cue, so the match plays out exactly the same with it.
##
## HOW IT WORKS: setup() connects to Events.cue. The counter takes every name the simulation sends,
## with no position or volume filter: it counts triggers, not what the sound player (Sfx) turns into
## sound (Sfx skips unknown names and quiet ones). The source of a cue is its name, because the cue
## carries no sender. The match second is world.tick_count / 60 (60 physics ticks a second). At the
## first tick of each second _physics_process() calls start_second(), which closes the second that
## just ended: a name with more than SPAM_ABOVE (20) triggers prints
##   SOUND_SPAM <name> second=<s> count=<n>
## once per name and second. A FIGHT second is one in which a live pilot ship had been hit, within the
## last FightWatch.HOT (4) seconds, by a pilot of the other team (the damage-log rule of FightWatch;
## hits by minions and turrets do not count, and the crowd-size rule is not used). SILENT_RUN (5)
## fight seconds in a row with no cue of any name print, once per run,
##   SOUND_SILENT from=<s> to=<s>
## A second that is not a fight, or that holds any cue, ends the run of silent seconds. A cue counts
## in the second the counter had open when the cue arrived. When match time reaches --secs the
## counter prints one summary line and quits:
##   SOUND_COUNT cues=<n> sources=<k> spam=<s> silent=<r> fight_seconds=<f>
## (cues: all triggers; sources: different names; spam: SPAM lines; silent: SILENT lines, 0 or 1;
## fight_seconds: the fight seconds seen).
## With --sound-case=logic the same functions run on made-up input instead of the match (count_cue()
## and start_second() are what the live counter calls; live_ok() and hit_heard() are checked on made-up
## input), and the run ends with "sound_count_check: <n> failures". The live case ends the same way,
## after two checks: live_ok() fails the run when no cue at all reached the counter, and hit_heard()
## fails it when no hit cue (hit or shield_hit) did.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --sim-only --test=sound_count_check --sound-case=logic
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-jungle --no-admiral-ai --sim-only=0 --test=sound_count_check --sound-case=live --seed=7 --secs=120
## --sound-case is "live" (the default) or "logic". The live case must run with the simulation's cues on
## (--sim-only=0): with --sim-only the simulation sends no weapon, hit or explosion cues, a few cues of
## other kinds still arrive, so "cues were heard" alone would pass and "hit cues were heard" fails the
## run. It must also run with the pilots on (no --no-pilots) and long enough for a hit (the check-list
## rows use --secs=120): without a pilot no hit has a pilot attacker, so no fight second can exist.
##
## HOW TO READ THE OUTPUT: the live case prints the SOUND_SPAM and SOUND_SILENT lines, then the
## SOUND_COUNT line, then one PASS or FAIL line for "live: cues were heard", one for "live: hit cues
## were heard", then "sound_count_check: <n> failures" (0 when it passes). The logic case prints one
## PASS or FAIL line per check and "sound_count_check: 0 failures" when all pass.
##
## WHO USES IT: main.gd loads it for --test=sound_count_check; run_checks runs both cases.

## A cue name sent more often than this in one second is spam.
const SPAM_ABOVE := 20
## This many fight seconds in a row with no cue at all make a silent fight.
const SILENT_RUN := 5
## Physics ticks in one match second.
const TICKS_PER_SECOND := 60

## The running match (set by setup()).
var world: World
## "live" (count the match) or "logic" (run the made-up cases).
var sound_case := "live"
## Match time (seconds) at which the live counter prints its summary and stops.
var secs := 1800.0
## How many logic checks failed.
var fails := 0
## All triggers counted so far.
var cues := 0
## How many SOUND_SPAM lines were printed.
var spam_count := 0
## How many SOUND_SILENT lines were printed (0 or 1).
var silent_count := 0
## How many fight seconds have ended.
var fight_seconds := 0
## The cue names seen so far (name -> true).
var _sources := {}
## The triggers of the open second (name -> count).
var _counts := {}
## The open second (-1 before the first).
var _second := -1
## Whether the open second is a fight second.
var _fight := false
## The first second of the run of silent fight seconds going now.
var _quiet_from := -1
## How many silent fight seconds are in that run (0 = no run).
var _quiet_len := 0
## Every counter line made so far, printed or not (the logic checks read it).
var _lines: Array[String] = []
## Whether a counter line is also printed (false in the logic case).
var _echo := true
## True once the run has been wrapped up.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	sound_case = str(Game.opt("sound-case", "live"))
	secs = float(Game.opt("secs", 1800.0))
	if sound_case != "logic":
		Events.cue.connect(_on_cue)


## Events.cue: count the trigger. The position is not used.
func _on_cue(cue_name: String, _pos: Vector2) -> void:
	count_cue(cue_name)


## Count one trigger of `cue_name` in the open second.
func count_cue(cue_name: String) -> void:
	cues += 1
	_sources[cue_name] = true
	_counts[cue_name] = int(_counts.get(cue_name, 0)) + 1


## Open second `sec`; `fight` says whether it is a fight second. Every second before it that is still
## open is closed first (its SPAM and SILENT lines are printed). A second that is already open is left
## as it is. A second skipped between two calls closes as a quiet second that is not a fight.
func start_second(sec: int, fight: bool) -> void:
	if sec == _second:
		return
	if _second >= 0 and sec > _second:
		_close_second(_second, _fight)
		_counts = {}
		for gap in range(_second + 1, sec):
			_close_second(gap, false)
	_second = sec
	_fight = fight


## Close second `sec` (`fight`: it was a fight second): print a SPAM line for each name over the limit
## and update the run of silent fight seconds.
func _close_second(sec: int, fight: bool) -> void:
	# Step 1: spam, in name order so the lines never change order between runs.
	var names: Array = _counts.keys()
	names.sort()
	for n: String in names:
		var k := int(_counts[n])
		if k > SPAM_ABOVE:
			spam_count += 1
			_emit("SOUND_SPAM %s second=%d count=%d" % [n, sec, k])
	# Step 2: silence. Only a fight second with no cue at all adds to the run; any other second ends it.
	if fight:
		fight_seconds += 1
	if fight and _counts.is_empty():
		if _quiet_len == 0:
			_quiet_from = sec
		_quiet_len += 1
		if _quiet_len >= SILENT_RUN and silent_count == 0:
			silent_count += 1
			_emit("SOUND_SILENT from=%d to=%d" % [_quiet_from, sec])
	else:
		_quiet_len = 0


## Keep one counter line, and print it unless the logic case is running.
func _emit(line: String) -> void:
	_lines.append(line)
	if _echo:
		print(line)


## The summary line (see HOW IT WORKS).
func summary_line() -> String:
	return "SOUND_COUNT cues=%d sources=%d spam=%d silent=%d fight_seconds=%d" % [cues, _sources.size(), spam_count, silent_count, fight_seconds]


## Is a live pilot ship being hit by an enemy pilot right now: some ship's damage log holds a pilot of
## the other team whose last hit was FightWatch.HOT seconds ago or less? (The damage log is attacker id
## -> [damage, time of the last hit, the attacker's PilotProfile or null]; only pilots have a profile.)
func _fight_now() -> bool:
	var now := world.time
	for s: Ship in world.ships:
		if not s.alive:
			continue
		for uid in s.damage_log:
			var e: Array = s.damage_log[uid]
			if e[2] != null and now - float(e[1]) <= FightWatch.HOT and (e[2] as PilotProfile).team != s.team:
				return true
	return false


## The live verdict from the counts: true when at least one cue reached the counter, false when none
## did (`n_cues` is 0: the counter never got a cue from the match, so its other numbers mean nothing).
## It prints nothing and counts no failure; the caller wraps it in _check().
func live_ok(n_cues: int) -> bool:
	return n_cues > 0


## True when a "hit" or "shield_hit" cue is among the names counted. Only a damage hit sends them (the combat code), and only when the simulation sends cues, so a run made with --sim-only fails this even though a few other cues still arrive. The caller wraps it in _check().
func hit_heard(names: Dictionary) -> bool:
	return names.has("hit") or names.has("shield_hit")


## Live case: open each new match second, and print the summary, the "cues were heard" and "hit cues
## were heard" checks and the failures line, then quit when --secs is reached (or the match is over).
## The logic case runs its checks on the first tick instead.
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	if sound_case == "logic":
		_done = true
		_run_logic()
		get_tree().quit()
		return
	var sec := int(float(world.tick_count) / TICKS_PER_SECOND)
	if sec != _second:
		start_second(sec, _fight_now())
	if world.tick_count >= int(secs * TICKS_PER_SECOND) or world.phase != "play":
		_done = true
		print(summary_line())
		_check("live: cues were heard", live_ok(cues), "cues=%d" % cues)
		_check("live: hit cues were heard", hit_heard(_sources), "sources=%d" % _sources.size())
		print("sound_count_check: %d failures" % fails)
		get_tree().quit()


## Forget everything counted, for the next logic case.
func _reset() -> void:
	cues = 0
	spam_count = 0
	silent_count = 0
	fight_seconds = 0
	_sources = {}
	_counts = {}
	_second = -1
	_fight = false
	_quiet_from = -1
	_quiet_len = 0
	_lines = []


## How many kept counter lines start with `prefix`.
func _lines_with(prefix: String) -> int:
	var n := 0
	for l in _lines:
		if l.begins_with(prefix):
			n += 1
	return n


## Print one PASS or FAIL line for the check `name` (`ok` = it passed), and count a failure.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Make `n` made-up quiet fight seconds, from second `first`: each is opened as a fight second with no cue.
func _silent_fight_seconds(first: int, n: int) -> void:
	for i in n:
		start_second(first + i, true)


## The logic case: made-up input through count_cue() and start_second(), the functions the live counter
## uses. Prints PASS or FAIL lines and the final "sound_count_check: <n> failures" line.
func _run_logic() -> void:
	_echo = false
	# Spam: 21 triggers of one name in second 3 is one line; closing the second again adds nothing.
	_reset()
	start_second(3, false)
	for _i in 21:
		count_cue("hit")
	start_second(4, false)
	start_second(4, false)
	_check("21 triggers in one second print one SPAM line", _lines.size() == 1 and _lines[0] == "SOUND_SPAM hit second=3 count=21", str(_lines))
	# Spam: 20 triggers is not spam.
	_reset()
	start_second(3, false)
	for _i in 20:
		count_cue("hit")
	start_second(4, false)
	_check("20 triggers in one second print nothing", _lines.is_empty(), str(_lines))
	# Spam is per name: two names over the limit make two lines, in name order.
	_reset()
	start_second(7, false)
	for _i in 25:
		count_cue("fire")
		count_cue("boom")
	start_second(8, false)
	_check("two spamming names print two lines in name order", _lines.size() == 2 and _lines[0] == "SOUND_SPAM boom second=7 count=25" and _lines[1] == "SOUND_SPAM fire second=7 count=25", str(_lines))
	# Spam is per second: 15 triggers in each of two seconds is not spam.
	_reset()
	start_second(1, false)
	for _i in 15:
		count_cue("hit")
	start_second(2, false)
	for _i in 15:
		count_cue("hit")
	start_second(3, false)
	_check("15 triggers in each of two seconds print nothing", _lines.is_empty(), str(_lines))
	# Silence: 4 quiet fight seconds print nothing.
	_reset()
	_silent_fight_seconds(0, 4)
	start_second(4, false)
	_check("4 silent fight seconds print nothing", _lines.is_empty(), str(_lines))
	# Silence: 5 quiet fight seconds print one line.
	_reset()
	_silent_fight_seconds(0, 5)
	start_second(5, false)
	_check("5 silent fight seconds print one SILENT line", _lines.size() == 1 and _lines[0] == "SOUND_SILENT from=0 to=4", str(_lines))
	# Silence prints once per run, however long it goes on.
	_reset()
	_silent_fight_seconds(10, 12)
	start_second(22, false)
	_check("12 silent fight seconds still print one SILENT line", _lines_with("SOUND_SILENT") == 1 and silent_count == 1, str(_lines))
	# A cue inside a run of silent seconds resets the run: 3, a cue, 4 more is no silent fight.
	_reset()
	_silent_fight_seconds(0, 3)
	start_second(3, true)
	count_cue("ui")
	_silent_fight_seconds(4, 4)
	start_second(8, false)
	_check("a cue inside the run resets it (3 + cue + 4)", _lines.is_empty(), str(_lines))
	# ... and 5 quiet seconds after the cue make the line, counted from the second after the cue.
	_reset()
	_silent_fight_seconds(0, 3)
	start_second(3, true)
	count_cue("ui")
	_silent_fight_seconds(4, 5)
	start_second(9, false)
	_check("5 silent fight seconds after the cue print one line", _lines.size() == 1 and _lines[0] == "SOUND_SILENT from=4 to=8", str(_lines))
	# Quiet seconds that are not a fight never count.
	_reset()
	for i in 10:
		start_second(i, false)
	start_second(10, false)
	_check("10 quiet seconds without a fight print nothing", _lines.is_empty(), str(_lines))
	# A second that is not a fight ends the run too.
	_reset()
	_silent_fight_seconds(0, 3)
	start_second(3, false)
	_silent_fight_seconds(4, 4)
	start_second(8, false)
	_check("a second without a fight ends the run (3 + gap + 4)", _lines.is_empty(), str(_lines))
	# The summary line.
	_reset()
	start_second(0, true)
	count_cue("hit")
	count_cue("hit")
	count_cue("boom")
	start_second(1, false)
	_check("the summary line counts cues, sources and fight seconds", summary_line() == "SOUND_COUNT cues=3 sources=2 spam=0 silent=0 fight_seconds=1", summary_line())
	# The live verdict: no cue at all is a failure of the live case, so the check here expects false.
	_check("live_ok rejects zero cues", not live_ok(0))
	_check("live_ok accepts cues", live_ok(3))
	# The hit verdict: no hit cue among the names is a failure of the live case, so the first two expect false.
	_check("hit_heard rejects no names", not hit_heard({}))
	_check("hit_heard rejects names with no hit", not hit_heard({"fire": true, "ui": true}))
	_check("hit_heard accepts hit", hit_heard({"hit": true}))
	_check("hit_heard accepts shield_hit", hit_heard({"shield_hit": true}))
	print("sound_count_check: %d failures" % fails)
