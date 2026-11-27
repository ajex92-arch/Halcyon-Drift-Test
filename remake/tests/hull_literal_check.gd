extends Node
## WHAT THIS IS: the hull-literal check. It fails when a hull id written as a text ("scout",
## "bomber"...) turns up in game code outside scripts/data/, unless the allowlist below names
## that line. Game code asks a hull's role tag (Ships.has_role) or the ship's own special, never
## the hull id, so a new hull needs no hunt through the code for hull-name tests.
##
## HOW IT WORKS: setup() runs the scanner on its own sample lines first (the scan: cases), then
## reads every .gd file under res://scripts except res://scripts/data/ (a file that cannot be
## opened is a failure, and so is a walk that finds no file). A hit is a line whose code part
## (a trailing comment is cut off) holds a double-quoted text equal to a hull id of Ships.ORDER,
## or to "build/<id>" or "build_<id>". The ids are read from Ships.ORDER when the check runs.
## ALLOW lists the hits that are not hulls (sound cues, weapon classes, minion types, damage
## families) or that stay where they are on purpose (a partial table, the card pages), each as
## the file, a piece of the line's code and a one-sentence reason. A hit no entry allows is a
## "hull literal" failure; an entry that allows no hit is a "stale allowlist entry" failure.
## The result line is "hull_literal_check: N failures", and one INFO line gives the counts.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=hull_literal_check
##
## WHO USES IT: main.gd loads it for --test=hull_literal_check (it calls setup()), and the check
## list runs it as the row hull_literals.

## The folder the scan walks.
const SCAN_ROOT := "res://scripts"
## The folder inside it that is left out (the data scripts hold hull ids on purpose).
const SKIP_DIR := "res://scripts/data/"
## The hits that are allowed: {file (relative to res://), code (a piece of the line, at least 6
## characters), reason (one plain sentence)}.
const ALLOW := [
	{"file": "scripts/audio/sfx.gd", "code": "const MIN_GAP := {\"fire\": 0.06", "reason": "sound cue names, not hulls"},
	{"file": "scripts/audio/sfx.gd", "code": "_streams[\"flak\"] = SfxSynth.bake(", "reason": "a sound cue name, not a hull"},
	{"file": "scripts/audio/sfx.gd", "code": "cue in [\"fire\", \"pd\", \"hit\", \"flak\"]", "reason": "sound cue names, not hulls"},
	{"file": "scripts/entities/gun_kick.gd", "code": "\"flak\": {\"dist\": 0.55", "reason": "a weapon class row of the kick table, not a hull"},
	{"file": "scripts/entities/gun_kick.gd", "code": "\"ion\": {\"dist\": 0.80", "reason": "a weapon class row of the kick table, not a hull"},
	{"file": "scripts/entities/minion.gd", "code": "var mtype := \"fighter\"", "reason": "a minion type, not a hull"},
	{"file": "scripts/entities/minion_flight.gd", "code": "\"fighter\":", "reason": "a minion type arm, not a hull"},
	{"file": "scripts/entities/minion_flight.gd", "code": "\"bomber\":", "reason": "a minion type arm, not a hull"},
	{"file": "scripts/entities/minion_targeting.gd", "code": "m.mtype != \"fighter\"", "reason": "a minion type, not a hull"},
	{"file": "scripts/entities/minion_targeting.gd", "code": "m.mtype == \"bomber\"", "reason": "a minion type, not a hull"},
	{"file": "scripts/entities/cinder_paint.gd", "code": "CinderShapes.MINIONS[\"fighter\"]", "reason": "the shape of a minion type, not a hull"},
	{"file": "scripts/entities/mothership.gd", "code": "var applied := {\"pd\": 0, \"flak\": 0", "reason": "the gun research kinds of the mothership, not hulls"},
	{"file": "scripts/entities/mothership_guns.gd", "code": "ts.ms_flak, \"flak\")", "reason": "a mothership gun kind, not a hull"},
	{"file": "scripts/entities/mothership_guns.gd", "code": "ts.ms_ion, \"ion\")", "reason": "a mothership gun kind, not a hull"},
	{"file": "scripts/entities/weapon_mount.gd", "code": "return \"flak\"", "reason": "a weapon class, not a hull"},
	{"file": "scripts/world/projectiles.gd", "code": "(\"pd\" if k == Rules.W_PD else \"flak\")", "reason": "a shot kind, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "return \"flak\"", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "return \"ion\"", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "\"ion\": 0.0", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "out[\"ion\"]", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "const RULE_ORDER := [\"pierce\", \"ion\"", "reason": "the name of a death rule, a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "\"ion\": \"Ion: drains shields", "reason": "the words of the death rule for the ion damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "\"ion\":", "reason": "the damage family arm of the death rule choice, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "float(s.get(\"ion\", 0.0))", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": ">= ion else \"ion\"", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/death_recap.gd", "code": "{\"rule\": \"ion\", \"text\"", "reason": "the name of a death rule, not a hull"},
	{"file": "scripts/ui/hud_death_card.gd", "code": "s[\"ion\"]", "reason": "a damage family, not a hull"},
	{"file": "scripts/ui/kill_icons.gd", "code": "\"flak\",", "reason": "a weapon family icon, not a hull"},
	{"file": "scripts/ui/hangar_ships.gd", "code": "\"ion_turret\": \"ion\"", "reason": "a weapon id to short label table, not a hull"},
	{"file": "scripts/ai/pilot_ai.gd", "code": "temperament = \"support\"", "reason": "a temperament name, not a hull"},
	{"file": "scripts/entities/engine_streams.gd", "code": "const HULLS := [\"flak\", \"ion\", \"destroyer\", \"battlecruiser\"]", "reason": "a partial table by design: the four hulls with one stream per nozzle"},
	{"file": "scripts/ui/rts/card_pages.gd", "code": "const CAPITALS := [\"destroyer\", \"battlecruiser\"]", "reason": "the UI list of the capital buttons"},
	{"file": "scripts/ui/rts/card_pages.gd", "code": "\"cols\": 3, \"grid\": [\"fighter\"", "reason": "the button layout of the second card page"},
	{"file": "scripts/ui/rts/card_pages.gd", "code": "\"cols\": 4, \"grid\": [\"scout\"", "reason": "the button layout of the third card page"},
	{"file": "scripts/ui/rts/card_pages.gd", "code": "\"pop\": [\"destroyer\", \"battlecruiser\"]", "reason": "the capitals popup of the second and third card page layouts"},
	{"file": "scripts/ui/rts/card_pages.gd", "code": "\"row\": \"build_", "reason": "the ten card page rows; the key-map names live in the key map data"},
]

## How many checks failed.
var _fails := 0
## Files scanned.
var _files := 0
## Hits found.
var _hits := 0
## Hits an allowlist entry allows.
var _allowed := 0


## main.gd calls this once, right after the World is built.
func setup(_w: World) -> void:
	_scanner_cases()
	_allow_shape()
	_scan_tree()
	print("INFO hull_literal_check: %d files scanned, %d hits, %d allowed" % [_files, _hits, _allowed])
	print("hull_literal_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Every hull id of Ships.ORDER, plus "build/<id>" and "build_<id>" for each: the texts that count as a hit.
static func hit_texts() -> Array[String]:
	var out: Array[String] = []
	for id: String in Ships.ORDER:
		out.append(id)
		out.append("build/" + id)
		out.append("build_" + id)
	return out


## The double-quoted texts of the code part of `line`: a trailing comment (from the first # that is not
## inside a double-quoted text) is cut off first.
static func code_texts(line: String) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	var in_text := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if in_text:
			if c == "\\":
				cur += line.substr(i, 2)
				i += 2
				continue
			if c == "\"":
				out.append(cur)
				cur = ""
				in_text = false
			else:
				cur += c
		else:
			if c == "#":
				break
			if c == "\"":
				in_text = true
		i += 1
	return out


## Is `line` a hit: not only a comment, and its code part holds one of the texts in `texts`?
static func is_hit(line: String, texts: Array[String]) -> bool:
	if line.strip_edges().begins_with("#"):
		return false
	for t: String in code_texts(line):
		if texts.has(t):
			return true
	return false


## The scanner on lines of its own: what is a hit and what is not.
func _scanner_cases() -> void:
	var texts := hit_texts()
	_check("scan: a code line with a hull test is one hit", is_hit("if ship.hull_id == \"bomber\":", texts))
	_check("scan: a comment-only line is none", not is_hit("# the \"bomber\" flies torpedoes", texts))
	_check("scan: an indented doc comment line is none", not is_hit("\t## the \"lance\" beam", texts))
	_check("scan: a trailing comment holding a hull is none", not is_hit("var x := 3  # the \"lance\" case", texts))
	_check("scan: a text before a trailing comment is a hit", is_hit("var x := \"lance\"  # one", texts))
	_check("scan: \"build_scout\" is a hit", is_hit("\"row\": \"build_scout\"", texts))
	_check("scan: \"build/ion\" is a hit", is_hit("\"build/ion\": {}", texts))
	_check("scan: \"scout_gun\" is none", not is_hit("\"w\": \"scout_gun\"", texts))
	_check("scan: \"Scout\" is none", not is_hit("\"label\": \"Scout\"", texts))
	_check("scan: \"ion_turret\" is none", not is_hit("\"w\": \"ion_turret\"", texts))
	_check("scan: a # inside a text does not start a comment", is_hit("var t := \"a#b\" + \"flak\"", texts))
	var two := 0
	if is_hit("x in [\"scout\", \"logistics\"]", texts):
		two += 1
	_check("scan: a line with two ids is one hit", two == 1)


## The allowlist's own shape: a file, a code of at least 6 characters and a reason.
func _allow_shape() -> void:
	for e: Dictionary in ALLOW:
		var ok := String(e.get("file", "")) != "" and String(e.get("code", "")).length() >= 6 and String(e.get("reason", "")).strip_edges() != ""
		_check("allowlist entry has no reason or a code under 6 characters: %s" % str(e), ok)


## Walks res://scripts, finds the hits, and compares them with ALLOW.
func _scan_tree() -> void:
	var texts := hit_texts()
	var files: Array[String] = []
	_walk(SCAN_ROOT, files)
	_files = files.size()
	_check("walk: at least one file under %s" % SCAN_ROOT, _files >= 1)
	var used := {}
	for path: String in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_check("could not read %s" % path, false)
			continue
		var lines := f.get_as_text().split("\n")
		f.close()
		var rel := path.trim_prefix("res://")
		for i in lines.size():
			var line: String = lines[i].trim_suffix("\r")
			if not is_hit(line, texts):
				continue
			_hits += 1
			var idx := _allowing_entries(rel, line)
			if not idx.is_empty():
				_allowed += 1
				for k: int in idx:
					used[k] = true
			else:
				_check("hull literal: %s:%d  %s" % [rel, i + 1, line.strip_edges().left(100)], false)
	for k in ALLOW.size():
		if not used.has(k):
			_check("stale allowlist entry: %s %s" % [ALLOW[k]["file"], ALLOW[k]["code"]], false)


## The indexes of the ALLOW entries that allow this line of file `rel` (empty when none does).
func _allowing_entries(rel: String, line: String) -> Array[int]:
	var out: Array[int] = []
	for k in ALLOW.size():
		var e: Dictionary = ALLOW[k]
		if e["file"] == rel and line.contains(String(e["code"])):
			out.append(k)
	return out


## Adds to `out` every .gd file under `dir` (and below) outside SKIP_DIR, as a res:// path.
func _walk(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		var sub := dir.path_join(d)
		if (sub + "/") == SKIP_DIR or (sub + "/").begins_with(SKIP_DIR):
			continue
		_walk(sub, out)
