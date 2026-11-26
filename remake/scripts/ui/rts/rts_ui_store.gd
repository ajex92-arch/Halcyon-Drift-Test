class_name RtsUiStore
extends RefCounted
## WHAT THIS IS: the part of the awareness screens that keeps the player's own choices in the game's settings file and
## reads them back: today the auto-join choice of each hull ("New Fighter join F2"). It is written the way KeyMapStore
## writes the [keys] section, in a section of its own, [rts_ui].
##
## HOW IT WORKS: one entry per choice, written "join/<hull id>" = <group number 1 to 8> (a hull with no choice has no
## entry). Saving keeps every other section of the file, and every entry of the [rts_ui] section whose name does not
## start with the prefix being saved (a later screen keeps its own entries there). A bad entry never breaks the game:
## an unknown hull, a group outside 1 to 8 or text that is no number is left out. Both functions take a path, so a
## test can use a file of its own; by default they use Game.SETTINGS_FILE.
##
## WHO USES IT: Groups (loads the joins when a match starts, saves when the choice changes); tests/rts_ui_check.gd.

## The section of the settings file.
const SECTION := "rts_ui"
## The prefix of an auto-join entry.
const JOIN := "join/"


## Write `entries` (name -> value) as the section's entries whose names start with `prefix`, replacing the old ones of
## that prefix and keeping the rest of the file. Returns Godot's error code (OK when written).
static func replace_prefix(prefix: String, entries: Dictionary, path: String = "") -> int:
	var p := path if path != "" else Game.SETTINGS_FILE
	var cfg := ConfigFile.new()
	cfg.load(p)
	if cfg.has_section(SECTION):
		for k: String in cfg.get_section_keys(SECTION):
			if k.begins_with(prefix):
				cfg.erase_section_key(SECTION, k)
	for k: String in entries:
		cfg.set_value(SECTION, k, entries[k])
	return cfg.save(p)


## Save the auto-join choices {hull id -> group 1 to 8}.
static func save_joins(joins: Dictionary, path: String = "") -> int:
	var entries := {}
	for hull: String in joins:
		if int(joins[hull]) > 0:
			entries[JOIN + hull] = int(joins[hull])
	return replace_prefix(JOIN, entries, path)


## The auto-join choices of the file: {hull id -> group 1 to 8}; empty when the file or the section is missing.
static func load_joins(path: String = "") -> Dictionary:
	var p := path if path != "" else Game.SETTINGS_FILE
	var out := {}
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK or not cfg.has_section(SECTION):
		return out
	for k: String in cfg.get_section_keys(SECTION):
		if not k.begins_with(JOIN):
			continue
		var hull := k.substr(JOIN.length())
		var n := int(str(cfg.get_value(SECTION, k, "0")))
		if Ships.HULLS.has(hull) and n >= 1 and n <= Groups.COUNT:
			out[hull] = n
	return out
