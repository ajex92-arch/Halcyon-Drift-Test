class_name NoteWriter
extends RefCounted
## WHAT THIS IS: the part of the note key (F9) that puts a note on the disk. A
## note is one small text file (JSON) and, in a game with a window, a picture
## (PNG) of the screen as it was when the key was pressed. Both go into one
## folder of the game's user data folder, so every note is in one place. In the
## browser build the same two files are also handed to the browser as
## downloads, because a browser keeps the user data folder inside its own
## storage, where nobody can read the notes from outside.
##
## HOW IT WORKS: save() asks describe() for the note's contents, picks a file
## name from the real date and time ("note_20261021_184207"; a second note in
## the same second gets _2, _3 ...), writes "<name>.json" (one top-level entry
## per line, so it reads easily) and, when there is a picture, "<name>.png"
## beside it. Then, in the browser build only, it hands both files to the
## browser: browser_files() lists them (the note first, then the picture, under
## the names they have in the folder) and _hand_to_browser() makes one
## download of each. A browser build without the download call keeps the note
## and says so in the log. On every other platform nothing is handed over.
## describe() reads the match and returns plain data: the real date
## and time, how far the match had got and at what world speed (slow motion),
## the seed, the rules played (the preset's name, "pick" for the standard
## rules, and a label for it), difficulty and test options (Unlock everything and No fog),
## what the human plays (seat, ship, place, credits) and the typed text. A text
## that starts with an item ID ("T-7: the
## top lane falls too fast") also gets an "item" entry, so the notes can be
## sorted by item. Nothing here changes the match: it only reads it and draws
## no random number, so a match plays out the same with or without notes.
## The folder is user://feedback, which on Windows is
## %APPDATA%\Godot\app_userdata\Halcyon Drift\feedback. The launch option
## --feedback-dir=<folder> picks another one (tests/note_check.gd uses it, so
## a test never writes among the real notes).
##
## WHO USES IT: NoteBox calls save() when the player presses Enter;
## tests/note_check.gd reads the files it wrote and checks browser_files().

## The folder notes go to when no --feedback-dir is given.
const DEFAULT_DIR := "user://feedback"
## The most characters one note may hold (the text box stops there).
const MAX_TEXT := 500


## The folder notes are written to: the value of --feedback-dir, or DEFAULT_DIR.
static func folder() -> String:
	var d := str(Game.opt("feedback-dir", DEFAULT_DIR))
	if d == "" or d == "true":
		return DEFAULT_DIR
	return d.rstrip("/\\")


## The item ID that `text` starts with ("T-7" for "T-7: the top lane ..."),
## upper-cased, or "" when it does not start with one.
static func item_id(text: String) -> String:
	var rx := RegEx.new()
	rx.compile("^\\s*([A-Za-z]-\\d+)\\b")
	var m := rx.search(text)
	return m.get_string(1).to_upper() if m != null else ""


## Write the note for match `world` with the typed `text` into folder(). `picture`
## is the screen as it was when F9 was pressed (null when the game has no
## window); `paused_before` says whether the match was already paused (P) at
## that moment. In the browser build the saved files are also handed to the
## browser as downloads. Returns {"ok": bool, "json": path, "png": path or "",
## "downloaded": bool, "error": text}: "downloaded" is true only when the
## browser was handed the files, so it is always false outside a browser. A
## folder or file that cannot be written gives ok = false and says why.
static func save(world: World, text: String, picture: Image, paused_before: bool) -> Dictionary:
	var dir := folder()
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return {"ok": false, "json": "", "png": "", "downloaded": false, "error": "cannot make the folder %s (error %d)" % [dir, made]}
	# Step 1: a file name that is free: the date and time, then _2, _3 ... if needed.
	var stem := _free_stem(dir)
	# Step 2: the picture, if there is one.
	var png_name := ""
	var png_path := "%s/%s.png" % [dir, stem]
	if picture != null and not picture.is_empty():
		if picture.save_png(png_path) == OK:
			png_name = stem + ".png"
	# Step 3: the note itself.
	var clipped := text.substr(0, MAX_TEXT)
	var json_path := "%s/%s.json" % [dir, stem]
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "json": "", "png": "", "downloaded": false, "error": "cannot write %s (error %d)" % [json_path, FileAccess.get_open_error()]}
	var json_text := _to_text(describe(world, clipped, paused_before, png_name))
	f.store_string(json_text)
	f.close()
	# Step 4: in the browser build only, hand the same two files to the browser.
	# The picture goes along only when it was saved, so the downloads are exactly
	# the files that are in the folder.
	var downloaded := false
	if OS.has_feature("web"):
		downloaded = _hand_to_browser(browser_files(stem, json_text, picture if png_name != "" else null))
	return {"ok": true, "json": json_path, "png": png_path if png_name != "" else "", "downloaded": downloaded, "error": ""}


## The files a note hands to the browser, in the order they are handed over:
## the note "<stem>.json" first (its text as UTF-8, mime application/json) and,
## when there is a `picture`, "<stem>.png" (mime image/png). The names are the
## ones the files have in the folder, so downloaded notes sit together like the
## folder's own. Each entry is {"name": String, "mime": String, "bytes":
## PackedByteArray}. The note comes first so that a browser that lets only one
## download through gives the player the note.
static func browser_files(stem: String, json_text: String, picture: Image) -> Array[Dictionary]:
	var files: Array[Dictionary] = [{"name": stem + ".json", "mime": "application/json", "bytes": json_text.to_utf8_buffer()}]
	if picture != null and not picture.is_empty():
		files.append({"name": stem + ".png", "mime": "image/png", "bytes": picture.save_png_to_buffer()})
	return files


## Browser build only: make one browser download of each of `files` (the list
## browser_files() returns), in order. Returns true when that was done and false
## when this build has no JavaScriptBridge.download_buffer; the note is then
## kept in the game's own storage only, and the log says so. Browsers may ask
## the player once before they allow several downloads in a row.
static func _hand_to_browser(files: Array[Dictionary]) -> bool:
	if not ClassDB.class_has_method("JavaScriptBridge", "download_buffer"):
		print("note: this build cannot hand files to the browser (no JavaScriptBridge.download_buffer); the note stays in the game's own storage")
		return false
	var names := PackedStringArray()
	for file in files:
		var bytes: PackedByteArray = file["bytes"]
		JavaScriptBridge.download_buffer(bytes, str(file["name"]), str(file["mime"]))
		names.append(str(file["name"]))
	print("note: handed to the browser as downloads: ", ", ".join(names))
	return true


## The note as plain data (see HOW IT WORKS). `picture_name` is the file name
## of the screenshot saved with it, or "" when there is none.
static func describe(world: World, text: String, paused_before: bool, picture_name: String) -> Dictionary:
	var h := world.human
	# The human's ship, while it exists and is alive.
	var ship: Ship = null
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		ship = h.ship
	# Where the camera looks, and where the human is: at their ship, or (docked,
	# dead, no ship, watching) where the camera looks.
	var cam := Vector2.ZERO
	if world.camera != null:
		cam = world.camera.get_screen_center_position()
	var at := ship.global_position if ship != null else cam
	var human := {"role": world.human_role, "team": "", "state": "", "ship": "", "next_hull": "", "modules": [],
		"position": [int(round(at.x)), int(round(at.y))], "position_is": "ship" if ship != null else "camera",
		"hull_percent": null, "credits": null, "treasury": null, "kills": null, "deaths": null, "assists": null}
	if h != null:
		human["team"] = Rules.TEAM_DISPLAY[h.team]
		human["state"] = h.state
		human["next_hull"] = h.hull_id
		human["credits"] = int(h.credits)
		human["treasury"] = int(world.teams[h.team].treasury)
		human["kills"] = h.kills
		human["deaths"] = h.deaths
		human["assists"] = h.assists
	if ship != null:
		human["ship"] = ship.hull_id
		human["modules"] = ship.modules.duplicate()
		human["hull_percent"] = int(round(100.0 * ship.hull / maxf(1.0, ship.hull_max)))
	var window_size := world.get_window().size
	return {
		"tool": "note_key", "version": 1,
		"text": text, "item": item_id(text),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"match": {"time": snappedf(world.time, 0.1), "clock": Util.clock(world.time), "phase": world.phase, "paused_before": paused_before,
			"world_speed": world.speed.factor},
		"setup": {"seed": str(Game.opt("seed", "random")), "preset": Game.preset,
			"rule_set": str(CouncilPresets.LABELS.get(Game.preset, "unknown (--preset was not understood)")),
			"variants_changed": _changed_variants(), "difficulty": Game.difficulty,
			"damage_modifiers_removed": Rules.damage_modifiers_removed(),
			"unlock_everything": Game.unlock_everything, "fog_off": Game.fog_off},
		"human": human,
		"screen": {"window": [window_size.x, window_size.y], "camera": [int(round(cam.x)), int(round(cam.y))]},
		"screenshot": picture_name,
		"godot": str(Engine.get_version_info()["string"]),
	}


## The note as the text of the file: JSON with one top-level entry per line
## (nested values stay on their line), so a note reads easily as it is.
static func _to_text(note: Dictionary) -> String:
	var lines := PackedStringArray()
	for k: String in note:
		lines.append("  %s: %s" % [JSON.stringify(k), JSON.stringify(note[k], "", false)])
	return "{\n" + ",\n".join(lines) + "\n}\n"


## The rule variants of this match that differ from Rules.VARIANT_DEFAULTS
## (the old standard rules, preset "none"): name -> value. A match on the
## standard rules lists the pairs of its preset ("pick") and any --variant
## pair; a "none" match lists only --variant pairs.
static func _changed_variants() -> Dictionary:
	var out := {}
	for k: String in Game.variants:
		if str(Game.variants[k]) != str(Rules.VARIANT_DEFAULTS.get(k, "")):
			out[k] = Game.variants[k]
	return out


## A file name (without its extension) for a note written now: the real local
## date and time ("note_20261021_184207"), with _2, _3 ... added when a note
## of that second exists in `dir`.
static func _free_stem(dir: String) -> String:
	var t := Time.get_datetime_dict_from_system(false)
	var stem := "note_%04d%02d%02d_%02d%02d%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]
	var candidate := stem
	var n := 1
	while FileAccess.file_exists("%s/%s.json" % [dir, candidate]):
		n += 1
		candidate = "%s_%d" % [stem, n]
	return candidate
