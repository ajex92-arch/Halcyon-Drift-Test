class_name MatchRecorder
extends Node
## WHAT THIS IS: the match recorder. It decides whether a match is recorded and, if so, keeps the
## recording's files together: the match log (the setup, the human's orders, flight controls and
## hangar commands, and a fingerprint of the game every five seconds; OrderLog), the match's stats
## (StatsRecorder) and the match series for the end-of-match graph (MatchSeries). The point of a
## recording is that the match can be played again exactly (--replay=<file>): an agent can then see
## what the person saw and check that a bug repeats, or that a fix changes it.
##
## HOW IT WORKS: main.gd makes one after the World is built (before the first tick) and calls
## setup(). Whether a match is recorded (wanted()): --record says yes and --no-record says no;
## otherwise a match a person plays from the start screen (a seat at the keyboard, a window, no
## --auto, --all-ai, --test or --replay) is recorded and a test run is not, so the checks never
## fill the player's recordings. The files go to the folder of --recordings-dir (default
## user://recordings, which on Windows is the game's data folder, in the folder "recordings") as
## <name>.log, <name>.stats.json and <name>.series.json; the name is --record-name, else "match_"
## and the real date and time, then the seed. A second match in the same run adds _2, _3, ... The
## web build writes nothing. The recorder only reads the match: a match plays out the same with
## recording on or off (tests/det_hash.gd proves it). The log is written once a minute of game time
## and when the match ends; the stats once a minute and when it ends. When the program is closed
## or the player leaves the match (the pause menu's Restart or Quit to start), the recorder writes
## the log's last line, so a match left half way still replays up to where it stopped.
##
## WHO USES IT: main.gd (it makes the recorder, passes it the series and calls finish_match());
## tests/record_check.gd and tests/record_drive.gd check it.

## The folder recordings go to when --recordings-dir is not given.
const DEFAULT_DIR := "user://recordings"

## How many recorders this program run has made: the second match gets a name with _2, and so on.
static var _made := 0

## The running match.
var world: World
## The recording's path without the extension ("" when the match is not recorded).
var base := ""
## The stats recorder of this recording (null when none).
var stats: StatsRecorder = null
## True once the recording has been closed.
var _finished := false


## Is the match in `w` to be recorded (see HOW IT WORKS)?
static func wanted(w: World) -> bool:
	return decide(w.human != null, DisplayServer.get_name() == "headless", Game.options, OS.has_feature("web"))


## The rule of wanted() on plain values, so that a test can try every case: is a match recorded
## when it has a human seat (`has_human`), runs with no window (`headless`) or in the web build
## (`web`), and the launch options are `opts`?
static func decide(has_human: bool, headless: bool, opts: Dictionary, web: bool) -> bool:
	if web or opts.has("no-record"):
		return false
	if opts.has("record"):
		return true
	if not has_human or headless:
		return false
	for key in ["auto", "all-ai", "test", "replay", "admiral-replay"]:
		if opts.has(key):
			return false
	return true


## The folder the recordings go to: --recordings-dir, else DEFAULT_DIR.
static func folder() -> String:
	var dir: Variant = Game.opt("recordings-dir")
	return str(dir) if dir is String and (dir as String) != "" else DEFAULT_DIR


## The recording's name without the extension for match number `n` of this run.
static func name_for(n: int) -> String:
	var given: Variant = Game.opt("record-name")
	var stem := str(given) if given is String and (given as String) != "" else ""
	if stem == "":
		var t := Time.get_datetime_dict_from_system()
		stem = "match_%04d%02d%02d_%02d%02d%02d_s%s" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"], OrderLog.seed_text()]
	return stem if n <= 1 else "%s_%d" % [stem, n]


## Start recording match `w` if it is to be recorded. Opens the log, makes the stats recorder and
## tells the match series where to save. Returns true when a recording was started. Call it after
## the World is built and before its first tick.
func setup(w: World, series: Variant = null) -> bool:
	world = w
	if not wanted(w):
		return false
	var dir := folder()
	DirAccess.make_dir_recursive_absolute(dir)
	_made += 1
	base = dir.path_join(name_for(_made))
	if w.orders.log == null and not w.orders.open_log(base + ".log"):
		print("recorder: cannot write %s.log; the match is not recorded" % base)
		base = ""
		return false
	if Game.opt("record-stats") == null:
		stats = StatsRecorder.new()
		add_child(stats)
		stats.setup(w, base + ".stats.json", true)
	if series != null:
		series.set("save_path", base + ".series.json")
	Events.match_over.connect(_on_match_over)
	print("recorder: recording this match to %s.*" % base)
	return true


## The match is over: the log has its last line already (OrderQueue); the stats get theirs.
func _on_match_over(winner: int, reason: String) -> void:
	if stats != null:
		stats.finish("%s wins: %s" % [Rules.TEAM_NAMES[winner], reason])


## The window is being closed: close the recording.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close()


## The program is stopping or the player left the match (the world is still whole at this point:
## the recorder was added after it, so it leaves the tree first): close the recording.
func _exit_tree() -> void:
	if Events.match_over.is_connected(_on_match_over):
		Events.match_over.disconnect(_on_match_over)
	_close()


## Write the log's last line (once). The stats and the series write their own last file when their
## node leaves the tree.
func _close() -> void:
	if _finished or base == "" or world == null or not is_instance_valid(world) or world.orders == null:
		return
	_finished = true
	world.orders.close(world)
