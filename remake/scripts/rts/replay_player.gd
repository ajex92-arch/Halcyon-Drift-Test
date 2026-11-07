class_name ReplayPlayer
extends RefCounted
## WHAT THIS IS: the part of the order queue that plays a match log back. Two kinds:
## replay 1 (--replay=<file>) plays back what a human did (the "h" order lines, the "c" flight
## controls of the human pilot and the "b" hangar commands) in place of the human, and replay 2
## (--admiral-replay=<file>) plays back the computer Admirals' orders (the "a" lines) in place of
## their thinking. Either way the match is run again with the same seed and options, and at every
## fingerprint line of the log the live fingerprint must be the same: it prints "replay: ok
## t=<tick>" or "replay: MISMATCH t=<tick> log=<hash> run=<hash>", and at the end "replay: end ..."
## and a last "replay: ok" or "replay: MISMATCH".
##
## HOW IT WORKS: start() reads the file (OrderLog.read) and files the orders it plays
## by the tick they were carried out on. OrderQueue asks due(tick) at the top of each
## tick, asks check_header() once at the first tick (a log made with another seed,
## preset, rule variants, map or starting state refuses to replay, before any order),
## and calls compare() at every fingerprint tick. GAME_SPEED lines are skipped: a replay
## may run at any pace and the speed is never part of the fingerprint.
## Replay 1 also plays the human's two other kinds of lines. controls_at(tick, seat) gives the
## flight controls the pilot's ship used on that tick (the last `c` line at or before it), which
## PlayerController puts into the ship in place of the keys and the mouse. commands_due(tick)
## gives the hangar commands given when that many ticks had been taken, which OrderQueue runs
## between two ticks through HumanCmd. A log made by another build still plays, with a warning
## that names both builds. `until` (--replay-until) is the match time at which the replay stops;
## so does the end of the recording (stop_tick).
##
## WHO USES IT: OrderQueue (OrderQueue.replay); PlayerController (through OrderQueue);
## tests/order_replay.gd and tests/record_check.gd check it.

## Header keys a replay does not compare: the build (a warning instead) and what only the screen shows.
const IGNORED_KEYS := ["build", "screen"]
## Header keys a version 1 log does not have.
const NEW_KEYS := ["play", "opts"]

## The log's contents (OrderLog.read), or empty.
var data := {}
## True for replay 2 (the computer's orders), false for replay 1 (the human's).
var as_computer := false
## The orders to play, by the tick they were carried out on: tick -> Array of records.
var _by_tick := {}
## How many fingerprint lines were compared.
var compared := 0
## How many of them differed.
var mismatches := 0
## True if the log's header and the live match agree.
var header_ok := true
## The match time (seconds) at which the replay stops, or -1.0 for "at the end of the recording".
var until := -1.0
## The last tick the recording knows (its end line, else the highest tick of any line).
var stop_tick := 0
## How many ticks the recorded flight controls were put into the pilot's ship.
var controls_played := 0
## How many hangar commands were run.
var commands_played := 0
## How many hangar commands gave another result than the recording says.
var command_diffs := 0
## Where the next `c` line to read is in data["controls"].
var _c_next := 0
## The newest `c` line read for each seat: seat -> HumanLines.parse_controls() result.
var _c_now := {}
## Where the next `b` command to run is in data["commands"].
var _b_next := 0


## Read `file_path` and file the orders to play. Returns false if it cannot be read.
func start(file_path: String, computer: bool) -> bool:
	as_computer = computer
	data = OrderLog.read(file_path)
	if str(data["header"]) == "":
		print("replay: cannot read a match log from the file given")
		return false
	var want := "a" if computer else "h"
	for o: Dictionary in data["orders"]:
		if Order.marker(o) != want or str(o["kind"]) == OrderKinds.GAME_SPEED:
			continue
		var tick := int(o["apply_tick"])
		if not _by_tick.has(tick):
			_by_tick[tick] = []
		(_by_tick[tick] as Array).append(o)
	stop_tick = int(data["last_tick"])
	return true


## Do the log's header and the live match agree (seed, preset, rule variants, seat, map
## counts, wing switches, play switches and the starting fingerprint; the build and the screen
## switches are not compared)? Prints "replay: header mismatch" and what differs when they do
## not; a log from another build prints a warning and still plays.
func check_header(w: World) -> bool:
	var live := OrderLog.make_header(w)
	var logged: String = data["header"]
	var live_head := _head_of(live)
	var log_head: Dictionary = data["head"]
	var old_log := int(data.get("version", 1)) < 2
	var diffs := PackedStringArray()
	for key in live_head:
		if IGNORED_KEYS.has(key) or (old_log and NEW_KEYS.has(key)):
			continue
		if str(log_head.get(key, "")) != str(live_head[key]):
			diffs.append(str(key))
	for key in log_head:
		if not IGNORED_KEYS.has(key) and not live_head.has(key):
			diffs.append(str(key))
	header_ok = diffs.is_empty() and logged != ""
	if not header_ok:
		print("replay: header mismatch (%s)" % ", ".join(diffs))
		for key in diffs:
			print("replay: header %s: log %s / run %s" % [key, str(log_head.get(key, "-")).left(80), str(live_head.get(key, "-")).left(80)])
	_warn_build(str(log_head.get("build", "")), str(live_head.get("build", BuildId.UNKNOWN)))
	return header_ok


## Say so when the log was made by another build than this one (the replay still runs).
func _warn_build(logged: String, live: String) -> void:
	if logged == live and logged != BuildId.UNKNOWN:
		return
	if logged == "":
		print("replay: warning: the recording does not name its build (an older log); this build is %s" % live)
	elif logged == live:
		print("replay: warning: the build is not known (both are \"%s\"), so the replay cannot tell if the code is the same" % live)
	else:
		print("replay: warning: the recording was made by build %s and this is build %s; the replay still runs, but another build may play differently" % [logged, live])


## The orders to carry out on `tick`, in the file's order (each is returned once).
func due(tick: int) -> Array:
	if not _by_tick.has(tick):
		return []
	var list: Array = _by_tick[tick]
	_by_tick.erase(tick)
	return list


## The flight controls of the pilot in `seat` on `tick`: the newest `c` line at or before it,
## read by HumanLines.parse_controls(). {} when the recording has none for that seat yet.
func controls_at(tick: int, seat: int) -> Dictionary:
	var lines: Array = data["controls"]
	while _c_next < lines.size() and int((lines[_c_next] as Array)[0]) <= tick:
		var row: Array = lines[_c_next]
		_c_next += 1
		var vec := HumanLines.parse_controls(str(row[2]))
		if not vec.is_empty():
			_c_now[int(row[1])] = vec
	return _c_now.get(seat, {})


## The hangar commands to run now: every `b` command given when `tick` ticks or fewer had been
## taken and not run yet, in the file's order (each is returned once).
func commands_due(tick: int) -> Array:
	var out: Array = []
	var cmds: Array = data["commands"]
	while _b_next < cmds.size() and int((cmds[_b_next] as Dictionary)["tick"]) <= tick:
		out.append(cmds[_b_next])
		_b_next += 1
	return out


## How many of the orders to play have not been played yet (0 when the run reached the
## last of them).
func left_over() -> int:
	var n := 0
	for tick in _by_tick:
		n += (_by_tick[tick] as Array).size()
	return n


## How many hangar commands of the recording have not been run yet.
func commands_left() -> int:
	return (data["commands"] as Array).size() - _b_next


## Compare the live fingerprint `fp` ("<units>,<hash8>") with the log's line for `tick`,
## if it has one. Prints "replay: ok t=<tick>" or, the first time they differ, the
## MISMATCH line.
func compare(tick: int, fp: String) -> void:
	var hashes: Dictionary = data["hashes"]
	if not hashes.has(tick):
		return
	compared += 1
	var logged := str(hashes[tick])
	var live := fp.replace(",", " ")
	if logged == live:
		print("replay: ok t=%d" % tick)
		return
	mismatches += 1
	if mismatches == 1:
		print("replay: MISMATCH t=%d log=%s run=%s" % [tick, logged.get_slice(" ", 1), live.get_slice(" ", 1)])


## A hangar command gave `got` ("" for success) but the recording says `logged` ("ok" or
## "refused"): count it and say so the first time.
func note_command(cmd: Dictionary, got: String) -> void:
	commands_played += 1
	var now := "ok" if got == "" else "refused"
	if now == str(cmd["result"]):
		return
	command_diffs += 1
	if command_diffs == 1:
		print("replay: a command gave another result than the recording: t=%d %s was %s, now %s" % [int(cmd["tick"]), str(cmd["kind"]), str(cmd["result"]), now])


## The end of the run: print the closing lines. `fp` is the live "<units>,<hash8>".
func finish(tick: int, fp: String) -> void:
	var live_end := "%d %s" % [tick, fp.replace(",", " ")]
	print("replay: end %s" % live_end)
	var logged_end := str(data.get("end", ""))
	if logged_end != "" and logged_end != live_end:
		print("replay: the log's end line is %s" % logged_end)
	if not as_computer:
		print("replay: %d control lines and %d hangar commands played (%d commands gave another result)" % [controls_played, commands_played, command_diffs])
	var ok := header_ok and mismatches == 0 and compared > 0 and command_diffs == 0
	print("replay: %s (%d fingerprint lines compared, %d differ)" % ["ok" if ok else "MISMATCH", compared, mismatches])


## The key=value words of a header line as a Dictionary.
func _head_of(line: String) -> Dictionary:
	var head := {}
	for word in line.split(" ", false):
		var eq := word.find("=")
		if eq > 0:
			head[word.substr(0, eq)] = word.substr(eq + 1)
	return head
