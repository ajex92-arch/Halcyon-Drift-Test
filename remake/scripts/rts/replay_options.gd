class_name ReplayOptions
extends RefCounted
## WHAT THIS IS: what lets `--replay=<file>` start the match the recording came from with no
## other option. A bug report is "here is the recording": the person who reads it types one
## option and gets the same match, the same rules, the same seat, instead of having to guess
## the seed, the team, the difficulty and the test switches that were on.
##
## HOW IT WORKS: Game calls fill() while it reads the launch options, before anything else
## reads them. fill() reads the first line of the log (its header) and, for each setting the
## header names, adds the matching launch option unless one was given on the command line (an
## option typed by hand always wins, and then the replay's header check says that the match
## differs). It also adds --auto and --bot=replay so that the match starts at once and nothing
## buys or launches for the human: the log's own commands do that. The header's rule variants are
## returned in `variants` for Game to use as they are. The header keeps four groups of
## settings, written by OrderLog.make_header(): the seed, role, team and preset; `play=`
## (difficulty, Unlock everything, the damage and flight switches); `opts=` (the test options
## that change the simulation, such as no-jungle); and the wings. Display-only switches (`screen=`,
## such as No fog) are not applied: they never change the match.
## parse_until() turns the text of --replay-until (seconds, or minutes and seconds as m:ss)
## into seconds.
##
## WHO USES IT: Game._parse_options() (fill); OrderQueue.configure() (parse_until).

## The test options that change the simulation and that the header lists in `opts=`.
const SIM_OPTIONS := ["no-pilots", "no-jungle", "no-admiral-ai", "no-admiral-field", "no-tail-gun", "skill-jitter", "admiral-ai"]


## The header line of the log in `path` as {key: value}, or {} when it cannot be read or is not
## a match log.
static func header_of(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var line := f.get_line().strip_edges()
	if not line.begins_with("log "):
		return {}
	var head := {}
	for word in line.split(" ", false):
		var eq := word.find("=")
		if eq > 0:
			head[word.substr(0, eq)] = word.substr(eq + 1)
	return head


## Add to `options` the launch options the header of the --replay log asks for (see HOW IT
## WORKS). Returns the header's rule variants as a Dictionary, or {} when there are none or
## there is no replay.
static func fill(options: Dictionary) -> Dictionary:
	var file: Variant = options.get("replay")
	if not (file is String) or (file as String) == "":
		return {}
	var head := header_of(file as String)
	if head.is_empty():
		return {}
	_give(options, "auto", true)
	_give(options, "bot", "replay")
	var role := str(head.get("role", "pilot"))
	if role == "spectator":
		_give(options, "all-ai", true)
	else:
		_give(options, "role", role)
		_give(options, "team", "vhorr" if str(head.get("team", "0")) == "1" else "aurelian")
	if str(head.get("seed", "")).is_valid_int():
		_give(options, "seed", str(head["seed"]))
	if str(head.get("preset", "")) != "":
		_give(options, "preset", str(head["preset"]))
	_play_options(options, str(head.get("play", "")))
	_sim_options(options, str(head.get("opts", "")))
	_wing_options(options, str(head.get("wings", "off")), str(head.get("cwings", "0")))
	var variants = JSON.parse_string(str(head.get("variants", "")))
	return variants if typeof(variants) == TYPE_DICTIONARY else {}


## `--replay-until`'s text as seconds of match time: "150" or "2:30" is 150. Returns -1.0 when the
## text is not a time.
static func parse_until(text: String) -> float:
	var t := text.strip_edges()
	if t.contains(":"):
		var parts := t.split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_float():
			return -1.0
		return float(int(parts[0])) * 60.0 + parts[1].to_float()
	return t.to_float() if t.is_valid_float() else -1.0


## Add option `key` = `value` unless the command line gave it.
static func _give(options: Dictionary, key: String, value: Variant) -> void:
	if not options.has(key):
		options[key] = value


## The `play=` word ("difficulty:medium,unlock:0,dmg:1,flight:1") as launch options.
static func _play_options(options: Dictionary, word: String) -> void:
	for pair in word.split(",", false):
		var kv := pair.split(":")
		if kv.size() != 2:
			continue
		match kv[0]:
			"difficulty":
				_give(options, "difficulty", kv[1])
			"unlock":
				_give(options, "unlock-all", kv[1])
			"dmg":
				_give(options, "damage-modifiers-removed", kv[1])
			"flight":
				_give(options, "big-hull-flight", kv[1])


## The `opts=` word ("no-jungle,skill-jitter:0.2" or "none") as launch options.
static func _sim_options(options: Dictionary, word: String) -> void:
	if word == "none" or word == "":
		return
	for item in word.split(",", false):
		var colon := item.find(":")
		var key := item if colon < 0 else item.substr(0, colon)
		if SIM_OPTIONS.has(key):
			_give(options, key, true if colon < 0 else item.substr(colon + 1))


## The wings: `wings` is the human seat's wing ("off" or "hull,hull,hull"), `cwings` is 1 when the
## computer pilots' seats have the test wing too.
static func _wing_options(options: Dictionary, wings: String, cwings: String) -> void:
	if wings == "off" or wings == "":
		_give(options, "test-wing", "0")
	elif wings == ",".join(PackedStringArray(Game.TEST_WING)):
		_give(options, "test-wing", "1")
	else:
		_give(options, "wingmen", wings)
	_give(options, "cpu-wings", "1" if cwings == "1" else "0")
