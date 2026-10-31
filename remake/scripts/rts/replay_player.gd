class_name ReplayPlayer
extends RefCounted
## WHAT THIS IS: the part of the order queue that plays a match log back. Two kinds:
## replay 1 (--replay=<file>) plays back the orders a human gave (the "h" lines) in
## place of the human, and replay 2 (--admiral-replay=<file>) plays back the computer
## Admirals' orders (the "a" lines) in place of their thinking. Either way the match
## is run again with the same seed and options, and at every fingerprint line of the
## log the live fingerprint must be the same: it prints "replay: ok t=<tick>" or
## "replay: MISMATCH t=<tick> log=<hash> run=<hash>", and at the end "replay: end ..."
## and a last "replay: ok" or "replay: MISMATCH".
##
## HOW IT WORKS: start() reads the file (OrderLog.read) and files the orders it plays
## by the tick they were carried out on. OrderQueue asks due(tick) at the top of each
## tick, asks check_header() once at the first tick (a log made with another seed,
## preset, rule variants, map or starting state refuses to replay, before any order),
## and calls compare() at every fingerprint tick. GAME_SPEED lines are skipped: a replay
## may run at any pace and the speed is never part of the fingerprint.
##
## WHO USES IT: OrderQueue (OrderQueue.replay); tests/order_replay.gd checks it.

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
	return true


## Do the log's header and the live match agree (seed, preset, rule variants, seat, map
## counts, wing switches and the starting fingerprint; a build label is ignored)? Prints
## "replay: header mismatch" and what differs when they do not.
func check_header(w: World) -> bool:
	var live := OrderLog.make_header(w)
	var logged: String = data["header"]
	var live_head := _head_of(live)
	var log_head: Dictionary = data["head"]
	var diffs := PackedStringArray()
	for key in live_head:
		if key != "build" and str(log_head.get(key, "")) != str(live_head[key]):
			diffs.append(str(key))
	for key in log_head:
		if key != "build" and not live_head.has(key):
			diffs.append(str(key))
	header_ok = diffs.is_empty() and logged != ""
	if not header_ok:
		print("replay: header mismatch (%s)" % ", ".join(diffs))
	return header_ok


## The orders to carry out on `tick`, in the file's order (each is returned once).
func due(tick: int) -> Array:
	if not _by_tick.has(tick):
		return []
	var list: Array = _by_tick[tick]
	_by_tick.erase(tick)
	return list


## How many of the orders to play have not been played yet (0 when the run reached the
## last of them).
func left_over() -> int:
	var n := 0
	for tick in _by_tick:
		n += (_by_tick[tick] as Array).size()
	return n


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


## The end of the run: print the closing lines. `fp` is the live "<units>,<hash8>".
func finish(tick: int, fp: String) -> void:
	var live_end := "%d %s" % [tick, fp.replace(",", " ")]
	print("replay: end %s" % live_end)
	var logged_end := str(data.get("end", ""))
	if logged_end != "" and logged_end != live_end:
		print("replay: the log's end line is %s" % logged_end)
	var ok := header_ok and mismatches == 0 and compared > 0
	print("replay: %s (%d fingerprint lines compared, %d differ)" % ["ok" if ok else "MISMATCH", compared, mismatches])


## The key=value words of a header line as a Dictionary.
func _head_of(line: String) -> Dictionary:
	var head := {}
	for word in line.split(" ", false):
		var eq := word.find("=")
		if eq > 0:
			head[word.substr(0, eq)] = word.substr(eq + 1)
	return head
