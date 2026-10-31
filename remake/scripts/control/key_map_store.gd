class_name KeyMapStore
extends RefCounted
## WHAT THIS IS: the part of the key map that keeps the player's changes in the game's
## settings file and reads them back.
##
## HOW IT WORKS: only the player's own changes are stored, in the section [keys] of the
## settings file the game already keeps (the same one that remembers the difficulty and
## the team): one entry per changed row, written "mode/action" = "KEY1|KEY2" (for
## example home/hangar = "K|Mouse5"), and one per picked preset, "preset/<group>" =
## "<id>". The defaults come from KeyMapData, so a new version of the game's keys reaches
## everyone who did not change that key. A bad entry never breaks the game: an unknown
## action or preset, a key we cannot read, a row that cannot be changed, or a key that
## clashes with another is left out (KeyMap.last_dropped says how many). Saving keeps the
## other sections of the file as they are. Both functions take a path so a test can use
## a temporary file; by default they use Game.SETTINGS_FILE.
##
## WHO USES IT: KeyMap forwards save() and load_from() here. Game.use_remembered_keys()
## reads at the start screen and the Controls page saves after each change.

## Write the player's changes and picked presets to the settings file at `path` ("" is
## Game.SETTINGS_FILE), leaving its other sections alone. Returns Godot's error code (OK
## when written).
static func save(path: String = "") -> int:
	var p := path if path != "" else Game.SETTINGS_FILE
	var cfg := ConfigFile.new()
	cfg.load(p)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	var over := KeyMap.overrides()
	for k: String in over:
		cfg.set_value("keys", k, "|".join(PackedStringArray(over[k])))
	var picks := KeyMap.choices()
	for g: String in picks:
		cfg.set_value("keys", "preset/" + g, picks[g])
	return cfg.save(p)


## Read the player's changes from the settings file at `path` ("" is Game.SETTINGS_FILE)
## and apply them: first the presets, then each change; an entry that is bad is left out
## (see the class note). A missing file or section leaves the defaults.
static func load_from(path: String = "") -> void:
	var p := path if path != "" else Game.SETTINGS_FILE
	var cfg := ConfigFile.new()
	KeyMap.replace_state({}, {})
	KeyMap.last_dropped = 0
	if cfg.load(p) != OK or not cfg.has_section("keys"):
		return
	var dropped := 0
	# Step 1: the presets first, because a row's keys depend on the chosen set.
	var picks := {}
	for k: String in cfg.get_section_keys("keys"):
		if not k.begins_with("preset/"):
			continue
		var g := KeyMap.preset_group(k.substr(7))
		var v := str(cfg.get_value("keys", k, ""))
		if g.is_empty() or not (g["presets"] as Dictionary).has(v):
			dropped += 1
		else:
			picks[k.substr(7)] = v
	KeyMap.replace_state({}, picks)
	# Step 2: each change that reads as keys on a row that can be changed.
	for k: String in cfg.get_section_keys("keys"):
		if k.begins_with("preset/"):
			continue
		var parts := k.split("/")
		var keys := _read_keys(str(cfg.get_value("keys", k, "")))
		var r: Dictionary = KeyMap.row(String(parts[0]), String(parts[1])) if parts.size() == 2 else {}
		if r.is_empty() or bool(r["fixed"]) or KeyMap.is_linked(String(parts[0]), String(parts[1])) or keys.is_empty():
			dropped += 1
		elif not KeyMap.set_keys(String(parts[0]), String(parts[1]), keys):
			dropped += 1
	# Step 3: a change that makes two rows share a key is taken off again (a swap is
	# two changes that are only right together, so this looks at the finished set).
	dropped += _drop_clashes()
	KeyMap.last_dropped = dropped


## The two keys of file text `text` ("KEY1|KEY2", either may be empty), or an empty list
## when the text holds a key we cannot read, Esc, a mouse button the page cannot capture, or
## more than two keys.
static func _read_keys(text: String) -> Array:
	var parts := text.split("|", true)
	if parts.size() > 2:
		return []
	var out := []
	for part in parts:
		var raw := String(part).strip_edges()
		var c := KeyCodes.canonical(raw)
		if raw != "" and (c == "" or c == "Esc" or c == "Mouse1" or c == "Mouse2"):
			return []
		out.append(c)
	return out


## Take the player's change off every row that shares a key with another row, until no
## clash is left. Returns how many changes were taken off.
static func _drop_clashes() -> int:
	var dropped := 0
	for _round in 200:
		var again := false
		for m: String in KeyMapData.MODES:
			for c: Dictionary in KeyMap.mode_clashes(m):
				var names: Array = [[c["mode"], c["action"]]]
				for o: Dictionary in c["others"]:
					names.append([o["mode"], o["action"]])
				for n: Array in names:
					if String(n[0]) != "" and KeyMap.is_changed(String(n[0]), String(n[1])):
						KeyMap.reset_row(String(n[0]), String(n[1]))
						dropped += 1
						again = true
						break
				if again:
					break
			if again:
				break
		if not again:
			break
	return dropped
