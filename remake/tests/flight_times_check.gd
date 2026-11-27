extends Node
## WHAT THIS IS: the check that the turn and stop times published on the
## hangar's ship cards (FlightTimes) are the times the ships really have.
##
## HOW IT WORKS: it freezes the match and checks three things:
##   - every hull of Ships.ORDER has a row in FlightTimes.TIMES, and
##     FlightTimes.line_for() gives a sentence for each one with the
##     ships-of-the-line flight on; with it off (Game.big_hull_flight set to
##     false, as the --big-hull-flight=0 option does) the six hulls of the line
##     give "" and the strike craft still give their sentence;
##   - the card's text (HangarShips.card_text) is built from that table: it ends
##     with the sentence (a hull whose data sets side_battery has the reach line
##     after it: the sentence is a line of its own), and holds the hull's class
##     and short text;
##   - the shown number is the behaviour: it makes a flight table probe as
##     main.gd does (without calling its setup, which would print and quit),
##     gives it this match and the same home spot, launches each hull with it and
##     flies the probe's own measures for the stop from top speed and the 180
##     degree turn from a stop. A table value that differs from the measured one
##     by more than TOLERANCE seconds is a failure. The probe has no dice and a
##     fixed start, so its runs repeat to the last digit.
## It prints one line per hull and then "flight_times_check: N failures" (0 means
## all is as it should be). When a change moves how a hull turns or stops this
## check fails on purpose: update FlightTimes.TIMES from the probe.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=flight_times_check
##
## WHO USES IT: main.gd loads it for --test=flight_times_check. It changes only
## units of a frozen match that is thrown away.

## How far (seconds) a published time may be from the measured one.
const TOLERANCE := 0.15

## The hulls whose data sets side_battery (C2's two ships of the line), written out on purpose: the card's
## extra reach line is expected from the hull data, so without this list a build with no side_battery
## anywhere would pass the card checks by the old rule.
const SIDE_BATTERY_HULLS := ["destroyer", "battlecruiser"]

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## Where the probe's ships are measured: open ground between the lanes.
var _home := Vector2.ZERO


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Run every group of checks, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_check_rows_and_switch()
	_check_card_text()
	_check_against_the_flight()
	print("flight_times_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("flight_times_check: FAIL %s" % what)


## Every hull has a row and a sentence; with the model off the hulls of the line
## have none, and the strike craft keep theirs.
func _check_rows_and_switch() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		_expect(FlightTimes.TIMES.has(hid), "%s has no row in the table" % hid)
		_expect(FlightTimes.line_for(hid) != "", "%s has no card sentence with the model on" % hid)
	var line_hulls := 0
	Game.big_hull_flight = false
	for hid: String in Ships.ORDER:
		if Handling.has_line(hid):
			line_hulls += 1
			_expect(FlightTimes.line_for(hid) == "", "%s shows a sentence with the model off: %s" % [hid, FlightTimes.line_for(hid)])
		else:
			_expect(FlightTimes.line_for(hid) != "", "%s (a strike craft) has no card sentence with the model off" % hid)
	Game.big_hull_flight = was
	_expect(line_hulls == 6, "%d hulls have a line entry, wanted 6" % line_hulls)
	_expect(FlightTimes.line_for("no_such_hull") == "", "an unknown hull has a sentence")


## The card text is made from the table: class line, short text, then the sentence.
func _check_card_text() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in SIDE_BATTERY_HULLS:
		_expect(bool(Ships.HULLS[hid].get("side_battery", false)), "%s does not set side_battery, so its card has no reach line" % hid)
	for hid: String in Ships.ORDER:
		var text := HangarShips.card_text(hid)
		var want := FlightTimes.line_for(hid)
		# A hull whose data sets side_battery (the two ships of the line, C2) has one more card line, the
		# reach line, after the sentence: the sentence is then a line of its own, not the end of the text.
		var extra := 1 if bool(Ships.HULLS[hid].get("side_battery", false)) else 0
		var rows := text.split("\n")
		if extra == 0:
			_expect(text.ends_with(want), "%s card text does not end with its sentence: %s" % [hid, text])
		else:
			_expect(rows.has(want), "%s card text has no line that is its sentence: %s" % [hid, text])
		_expect(text.contains(Ships.blurb(hid)), "%s card text lacks the short text: %s" % [hid, text])
		_expect(rows.size() == 3 + extra, "%s card text is not %d lines: %s" % [hid, 3 + extra, text])
	Game.big_hull_flight = false
	for hid: String in Ships.ORDER:
		var lines := HangarShips.card_text(hid).split("\n").size()
		var wanted := (2 if Handling.has_line(hid) else 3) + (1 if bool(Ships.HULLS[hid].get("side_battery", false)) else 0)
		_expect(lines == wanted, "%s card text has %d lines with the model off, wanted %d" % [hid, lines, wanted])
	Game.big_hull_flight = was


## Fly every hull as the flight table probe does and compare the table with it.
func _check_against_the_flight() -> void:
	var probe: Node = load("res://tests/flight_table_probe.gd").new()
	add_child(probe)
	probe.set("world", world)
	probe.set("_home", _home)
	for hid: String in Ships.ORDER:
		var s: Ship = probe.call("_launch", hid)
		var a: Dictionary = probe.call("_accel_run", s)
		var st: Dictionary = probe.call("_stop_run", s, float(a["top"]))
		var tn: Dictionary = probe.call("_turn_run", s, 180.0, 0.0, 0.0)
		var row: Dictionary = FlightTimes.TIMES[hid]
		var stop_t := float(st["t"])
		var turn_t := float(tn["t"])
		print("flight_times_check: %s table turn %.1f stop %.1f, measured turn %.2f stop %.2f" % [hid, float(row["turn180"]), float(row["stop"]), turn_t, stop_t])
		_expect(absf(float(row["stop"]) - stop_t) <= TOLERANCE, "%s stop time: table %.1f, measured %.2f" % [hid, float(row["stop"]), stop_t])
		_expect(absf(float(row["turn180"]) - turn_t) <= TOLERANCE, "%s turn time: table %.1f, measured %.2f" % [hid, float(row["turn180"]), turn_t])
		probe.call("_put", s)
	probe.queue_free()
