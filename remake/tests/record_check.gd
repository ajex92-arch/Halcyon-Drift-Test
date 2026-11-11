extends Node
## WHAT THIS IS: the check of the match recorder's parts. It proves the text of the new log lines
## reads back exactly (a replay must fly the course the player flew, so a number may not change
## by a hair), that the hangar door (HumanCmd) records its commands and refuses a screen's command
## during a replay, that a `c` line is written only when the controls change, that the header
## names the build and the switches, and that --replay=<file> brings the settings its log was made
## with, a team's own rule variant (--variant-team0 or --variant-team1) included: named in the header
## when one is given, brought back by --replay, a typed one that disagrees losing. The end-to-end
## proof (a recorded match played again) is tests/record_drive.gd.
##
## HOW IT WORKS: setup() runs the checks that need no match (the number text, the line round trips,
## the option helpers) and then plays 240 ticks of a match with the recorder on: it gives hangar
## commands, holds and lets go of a key, and reads the log back. The last step prints
## "record_check: N failures" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program; <dir> is a folder for the recording):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --seed=7 --record --recordings-dir=<dir> --record-name=check --test=record_check
##
## The same with a team variant (the header must then name it):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --seed=7 --record --recordings-dir=<dir> --record-name=check --variant-team0=eff:on --test=record_check
##
## WHO USES IT: main.gd loads it for --test=record_check; run_checks lists it.

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## Ticks taken since setup().
var _ticks := 0
## The ship of the human pilot (set when it is flying).
var _ship: Ship = null


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_physics_priority = -100
	_check_numbers()
	_check_lines()
	_check_options()
	_check_default()
	_check_start()


## Count a failure and print a PASS or FAIL line.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## HumanLines.num(): every number reads back as exactly itself, for 32-bit and 64-bit numbers.
func _check_numbers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bad32 := 0
	var bad64 := 0
	var longest := 0
	for i in 30000:
		var x32 := Vector2(rng.randf_range(-1000.0, 45000.0) if i % 3 != 0 else rng.randf_range(0.0, 64.0), 0.0).x
		var t32 := HumanLines.num(x32, true)
		if Vector2(t32.to_float(), 0.0).x != x32:
			bad32 += 1
		longest = maxi(longest, t32.length())
		var x64 := rng.randf() * 2.0 - 1.0
		var t64 := HumanLines.num(x64, false)
		if HumanLines.read_num(t64) != x64:
			bad64 += 1
	_check("32-bit numbers read back exactly (30000 tried, longest text %d)" % longest, bad32 == 0, "bad %d" % bad32)
	_check("64-bit numbers read back exactly (30000 tried)", bad64 == 0, "bad %d" % bad64)
	_check("whole numbers and zero are short", HumanLines.num(0.0, true) == "0" and HumanLines.num(-1.0, false) == "-1" and HumanLines.num(12345.0, true) == "12345" and HumanLines.num(0.5, true) == "0.5")


## The `c` and `b` lines and their readers.
func _check_lines() -> void:
	var c := ShipControls.new()
	c.aim_point = Vector2(12345.678, 23456.789)
	c.face_point = c.aim_point
	c.forward = 1.0
	c.strafe = -1.0
	c.fire = true
	c.special = true
	c.focus_request = 2
	var body := HumanLines.controls_body(c)
	var vec := HumanLines.parse_controls(body)
	var d := ShipControls.new()
	HumanLines.apply_controls(vec, d)
	_check("a c line reads back into the same controls", d.aim_point == c.aim_point and d.face_point == c.face_point and d.forward == 1.0 and d.strafe == -1.0 and d.fire and d.special and not d.boost and d.assist == c.assist and d.focus_request == 2 and d.energy_request == -1 and not d.dock, body)
	c.face_point = Vector2(1.5, -2.25)
	c.assist = false
	body = HumanLines.controls_body(c)
	HumanLines.apply_controls(HumanLines.parse_controls(body), d)
	_check("a separate face point and flight assist off read back", d.face_point == Vector2(1.5, -2.25) and not d.assist, body)
	var line := HumanLines.command_line(1200, 0, "buy_gear", ["helmet_a"], "refused")
	var cmd := HumanLines.parse_command(line)
	_check("a b line reads back", cmd.get("tick") == 1200 and cmd.get("kind") == "buy_gear" and cmd.get("args") == ["helmet_a"] and cmd.get("result") == "refused", line)
	_check("a line that is not a b line is not read", HumanLines.parse_command("o 1 2 3").is_empty())
	var whole := HumanLines.parse_command("b 5 0 sell_slot [0] ok")
	_check("a whole number in a b line is an int again", typeof((whole["args"] as Array)[0]) == TYPE_INT and HumanLines.command_line(5, 0, "sell_slot", whole["args"], "ok") == "b 5 0 sell_slot [0] ok")


## The option helpers: --replay-until's time, the build name, and --replay's settings.
func _check_options() -> void:
	_check("replay-until reads seconds and m:ss", ReplayOptions.parse_until("150") == 150.0 and ReplayOptions.parse_until("2:30") == 150.0 and ReplayOptions.parse_until("0:07.5") == 7.5)
	_check("replay-until refuses a word", ReplayOptions.parse_until("soon") < 0.0 and ReplayOptions.parse_until("1:xx") < 0.0)
	_check("a build name is made safe", BuildId.clean("my build\t1") == "my_build_1" and BuildId.clean("") == BuildId.UNKNOWN and BuildId.clean("x".repeat(80)).length() == BuildId.MAX_LENGTH)
	# A made-up header: --replay must turn it into launch options, and an option typed by hand must win.
	var dir := MatchRecorder.folder()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("check_header.log")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("log v2 seed=42 preset=none variants={\"retreat\":\"none\",\"gear_mk2\":\"on\"} role=admiral team=1 rocks=1 nodes=1 camps=1 route_nodes=1 wings=scout,fighter,bomber cwings=0 play=difficulty:hard,unlock:1,dmg:0,flight:0 opts=no-jungle,skill-jitter:0.2 screen=fog:1 fp0=1,2 build=abc\n")
	f = null
	var options := {"replay": path, "seed": "9"}
	var variants := ReplayOptions.fill(options)
	_check("--replay brings the seat, team and settings of the log", str(options.get("role")) == "admiral" and str(options.get("team")) == "vhorr" and str(options.get("difficulty")) == "hard" and str(options.get("unlock-all")) == "1" and str(options.get("damage-modifiers-removed")) == "0" and str(options.get("big-hull-flight")) == "0" and options.get("no-jungle") == true and str(options.get("skill-jitter")) == "0.2" and str(options.get("test-wing")) == "1" and str(options.get("cpu-wings")) == "0" and str(options.get("preset")) == "none", str(options))
	_check("--replay starts at once with nobody pressing the buy keys", options.get("auto") == true and str(options.get("bot")) == "replay")
	_check("an option typed by hand wins over the log", str(options.get("seed")) == "9")
	_check("the log's rule variants come back as they are", variants.get("gear_mk2") == "on" and variants.get("retreat") == "none" and variants.size() == 2, str(variants))
	_check("a screen switch is not turned into an option", not options.has("fog-off"))
	_check("a header without a variants_team word leaves the team options alone", not options.has("variant-team0") and not options.has("variant-team1"))
	var typed_old := {"replay": path, "variant-team1": "eff:on"}
	ReplayOptions.fill(typed_old)
	_check("an older recording replays with its team option typed again", str(typed_old.get("variant-team1")) == "eff:on", str(typed_old))
	_check_team_variants(dir)


## The per-team rule variants (--variant-team0 and --variant-team1) in the header: a replay applies
## them, and a typed option that disagrees loses with one line saying so.
func _check_team_variants(dir: String) -> void:
	var path := dir.path_join("check_header_variants.log")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("log v2 seed=42 preset=none variants={\"retreat\":\"none\"} variants_team0={\"eff\":\"on\",\"ms\":\"nosmall\"} role=pilot team=0 rocks=1 nodes=1 camps=1 route_nodes=1 wings=off cwings=0 play=difficulty:medium,unlock:0,dmg:1,flight:1 opts=none screen=fog:0 fp0=1,2 build=abc\n")
	f = null
	var plain := {"replay": path}
	ReplayOptions.fill(plain)
	_check("--replay brings a team's variants from the header, with no option typed", str(plain.get("variant-team0")) == "eff:on,ms:nosmall" and not plain.has("variant-team1"), str(plain))
	var agree := {"replay": path, "variant-team0": "ms:nosmall,eff:on"}
	ReplayOptions.fill(agree)
	_check("a typed option that says the same changes nothing", str(agree.get("variant-team0")) == "eff:on,ms:nosmall")
	var clash := {"replay": path, "variant-team0": "ai_calib:on", "variant-team1": "eff:on"}
	ReplayOptions.fill(clash)
	_check("a typed option that disagrees loses to the header, and a team the header does not name has none", str(clash.get("variant-team0")) == "eff:on,ms:nosmall" and not clash.has("variant-team1"), str(clash))
	var script: Script = load("res://scripts/rts/replay_options.gd")
	var line := ""
	if script.has_method("conflict_line"):
		line = str(script.call("conflict_line", 0, "ai_calib:on", {"eff": "on"}))
	_check("the disagreement is said in one line that names the option", line.begins_with("replay: --variant-team0=ai_calib:on") and not line.contains("\n"), line)


## The recorder's default: a match a person plays is recorded, a test run is not, and the options
## say otherwise.
func _check_default() -> void:
	var yes := MatchRecorder.decide(true, false, {}, false)
	_check("a match a person plays (a seat, a window, no options) is recorded", yes)
	_check("a test run (--auto, --all-ai, --test, --replay) is not recorded by default", not MatchRecorder.decide(true, false, {"auto": true}, false) and not MatchRecorder.decide(true, false, {"all-ai": true}, false) and not MatchRecorder.decide(true, false, {"test": "x"}, false) and not MatchRecorder.decide(true, false, {"replay": "f"}, false))
	_check("no window or no human seat: not recorded by default", not MatchRecorder.decide(true, true, {}, false) and not MatchRecorder.decide(false, false, {}, false))
	_check("--record records a test run, even with no window and no human", MatchRecorder.decide(false, true, {"record": true, "auto": true}, false))
	_check("--no-record wins over everything, and the web build records nothing", not MatchRecorder.decide(true, false, {"record": true, "no-record": true}, false) and not MatchRecorder.decide(true, false, {}, true) and not MatchRecorder.decide(true, false, {"record": true}, true))
	_check("a recording name: the given one, then _2 for a second match", MatchRecorder.name_for(1) == str(Game.opt("record-name", MatchRecorder.name_for(1))) and MatchRecorder.name_for(2).ends_with("_2"))


## The start of the match: the recorder is on, the header is complete.
func _check_start() -> void:
	_check("this run records (the test needs --record)", MatchRecorder.wanted(world))
	_check("the match log is open", world.orders.log != null and world.orders.log.is_open())
	_check("the match has a seed", Game.match_seed >= 0)
	var head := OrderLog.make_header(world)
	_check("the header is version 2 and names the seed", head.begins_with("log v2 seed=%d " % Game.match_seed), head.left(40))
	for key in ["play=", "opts=", "screen=", "build=", "fp0=", "variants="]:
		_check("the header has %s" % key, head.contains(" %s" % key))
	_check("the header's last word is the build", head.get_slice(" ", head.count(" ")).begins_with("build="))
	# The per-team variants: named in the header when a team holds one (the run with --variant-team0 or
	# --variant-team1), and absent otherwise, so the header of an ordinary match is what it always was.
	for team in range(2):
		var own: Dictionary = Game.team_variants[team]
		var word := "variants_team%d=" % team
		if own.is_empty():
			_check("no variant for team %d: the header has no %s word" % [team, word], not head.contains(word), head)
		else:
			_check("the header names team %d's variants (%s)" % [team, JSON.stringify(own, "", true)], head.contains(" %s%s " % [word, JSON.stringify(own, "", true)]), head)
	if not Game.has_team_variants():
		_check("no team variant at all: the header has no variants_team word", not head.contains("variants_team"))
	_check("the log is in the recordings folder", world.orders.log.path.begins_with(MatchRecorder.folder()), world.orders.log.path)


## Godot calls this every tick, before the World's: the scripted steps.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	_ticks += 1
	var h := world.human
	if h == null:
		return
	world.test_mouse = Vector2(5000.0, 5000.0)
	match _ticks:
		1:
			# The recorder wrote the automatic Fighter and launch of the test run already.
			_ship = h.ship
			_check("the human flies (main.gd's automatic launch went through the door)", _ship != null and h.state == "flying")
			var before := _log_lines("b ")
			var err := HumanCmd.run(world, "buy_kit")
			_check("a hangar command is answered with its result", true, err)
			world.orders.replaying = true
			var refused := HumanCmd.run(world, "buy_kit")
			world.orders.replaying = false
			_check("a screen's command during a replay is refused", refused == HumanCmd.TEXT_REPLAYING)
			world.orders.flush()
			_check("the commands were queued as b lines (%d before)" % before, true)
		60:
			Input.action_press("thrust_forward")
		120:
			Input.action_release("thrust_forward")
		240:
			_finish()


## The number of lines of the log file so far that start with `prefix` (the log is flushed first).
func _log_lines(prefix: String) -> int:
	world.orders.flush()
	var f := FileAccess.open(world.orders.log.path, FileAccess.READ)
	var n := 0
	while f != null and not f.eof_reached():
		if f.get_line().begins_with(prefix):
			n += 1
	return n


## The end: read the log back and check what it holds, then print the verdict and quit.
func _finish() -> void:
	world.orders.flush()
	var read := OrderLog.read(world.orders.log.path)
	var controls: Array = read["controls"]
	var commands: Array = read["commands"]
	_check("the log has the header written at the first tick", str(read["header"]).begins_with("log v2 seed="))
	_check("the c lines are few: only changes are written (%d for 240 ticks)" % controls.size(), controls.size() >= 2 and controls.size() <= 12)
	var kinds := PackedStringArray()
	for cmd: Dictionary in commands:
		kinds.append(str(cmd["kind"]))
	_check("the automatic buy and launch are b lines", kinds.has("buy_hull") and kinds.has("launch"), ",".join(kinds))
	var kits := 0
	for k in kinds:
		if k == "buy_kit":
			kits += 1
	_check("the refused buy during the pretend replay was not run, so it is not a line", kits == 1, ",".join(kinds))
	# The thrust key shows in the c lines: some line has forward 1 and a later one has it back at 0.
	var up := false
	var back := false
	for row: Array in controls:
		var vec := HumanLines.parse_controls(str(row[2]))
		if float(vec["forward"]) == 1.0:
			up = true
		elif up and float(vec["forward"]) == 0.0:
			back = true
	_check("holding W and letting go show in the c lines", up and back)
	# A replay player over this very log: the lines come back in order.
	var player := ReplayPlayer.new()
	_check("a replay reads the log", player.start(world.orders.log.path, false))
	var cmd_tick0: Array = player.commands_due(0)
	_check("the commands given before the first tick come back at tick 0", cmd_tick0.size() >= 2 and str((cmd_tick0[0] as Dictionary)["kind"]) == "buy_hull")
	var at100 := player.controls_at(100, world.human.slot)
	var at200 := player.controls_at(200, world.human.slot)
	_check("the controls at tick 100 have the thrust on and at tick 200 off", not at100.is_empty() and float(at100["forward"]) == 1.0 and float(at200["forward"]) == 0.0)
	_check("the recording knows its last tick", player.stop_tick >= 1)
	print("record_check: %d failures" % fails)
	get_tree().quit()
