extends Node
## WHAT THIS IS: the check of the note key (F9). It presses the key the way a
## player does, types, and checks that the match pauses while the note box is
## open, that Enter saves a note file (and, in a game with a window, the
## screenshot taken just before the box opened) and that Esc saves nothing.
##
## HOW IT WORKS: it waits until the HUD exists, then runs these steps, each
## key a real key event pushed into the window (Viewport.push_input), so it
## takes the same path as a keyboard:
##   1. before F9 there is no note box and the match is not paused;
##   2. F9 opens the box and pauses the match; the match clock stands still
##      for 400 ms of real time;
##   3. typing menu keys (b, h, p, f, c, Tab ...) into the box types text and
##      opens no panel and does not unpause; the HUD's key router, called with
##      those keys itself, ignores them too while the box is open;
##   4. Enter saves: the box closes, the match runs again, and exactly one
##      note file exists with the right text, item, seat, ship, place,
##      credits, match time, seed and rules played (the preset: "pick", the
##      standard rules, unless --preset names another); with a window the PNG exists and is as
##      big as the screen, headless the note says it has no screenshot;
##   5. Esc cancels: nothing new is saved and the match runs again;
##   6. a match paused with P stays paused after a note;
##   7. Enter on an empty box saves a marker note;
##   8. a second F9 while the box is open changes nothing;
##   9. a fire button the game thinks is held is set back to the mouse's real
##      state when the box closes;
##  10. F9 also works once the match is over, and the note says so;
##  and NoteWriter.item_id() reads the IDs it should. For the browser build,
## whose own path cannot run here, it checks the pieces that can: the call that
## hands a file to the browser (JavaScriptBridge.download_buffer) exists in this
## engine; NoteWriter.browser_files() lists the note first and the picture
## second, under the folder's file names, with the right mime types and bytes
## that read back as what was given (the picture's bytes are those of a PNG file
## in the folder, and a note file is plain UTF-8 text, so its download is the
## same file); the help page's notes paragraph still ends
## with the sentence the browser build swaps for its own; and, in step 4, a
## save in this game ends with the plain pop-up "Note saved." and hands nothing
## to a browser.
## The notes go to the folder given by --feedback-dir (required, and never the
## real notes folder): the check clears the note files in that folder first.
## With a window, --shots=<folder> also saves two pictures of the open box
## (note_open.png, note_typed.png).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/; the folder name is up to you):
##   godot --headless --path remake -- --auto --role=pilot --force-hud --feedback-dir=user://feedback_check --test=note_check
##   godot --headless --path remake -- --auto --role=admiral --force-hud --feedback-dir=user://feedback_check --test=note_check
##   godot --path remake --resolution 1280x720 --position 30000,30000 -- --auto --role=pilot --feedback-dir=user://feedback_check --test=note_check
## The last one opens a window off the visible screen, so the screenshot is
## really taken and checked. To keep the check away from the player's own user
## data folder as well, start it with the environment variable APPDATA pointing
## at an empty scratch folder.
##
## HOW TO READ THE OUTPUT: one "note_check <step>: ok ..." line per step, or
## "FAIL note_check <step>: ..." for a broken one, then "note_check: N
## failures". If the run takes over 90 seconds of real time it prints
## "note_check: timeout" and quits.
##
## WHO USES IT: main.gd loads it for --test=note_check (see ui_tour.gd for how
## tests are loaded). It uses the HUD's note_box, NoteBox.open() through the
## F9 key, NoteWriter and the notes it wrote.

## The match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many expectations failed.
var failures := 0
## The folder the notes go to (NoteWriter.folder()).
var dir := ""
## The pop-up texts sent through Events.toast since the list was last cleared.
var toasts: Array[String] = []


## main.gd calls this once, right after the World is built. Remember the
## world and keep running even if the game pauses.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS


## Godot calls this every drawn frame. Quit after 90 s of real time; start
## the check once the HUD exists.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 90000:
		print("note_check: timeout")
		get_tree().quit()
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		return
	started = true
	_run()


## The whole check (see HOW IT WORKS), then the summary line and quit.
func _run() -> void:
	dir = NoteWriter.folder()
	if dir == NoteWriter.DEFAULT_DIR:
		_fail("setup", "start the check with --feedback-dir=user://<a scratch folder>, so it never writes among the real notes")
		_finish()
		return
	_clear(dir)
	await _frames(5)
	var windowed := DisplayServer.get_name() != "headless"
	_check_item_ids()
	_check_browser_api()
	_check_browser_files()
	_check_help_text()
	Events.toast.connect(_on_toast)

	# Step 1: nothing exists before the key is pressed.
	_expect(hud.note_box == null, "before F9", "no note box exists yet")
	_expect(not get_tree().paused, "before F9", "the match is not paused")
	_expect(NoteWriter.DEFAULT_DIR == "user://feedback", "before F9", "the default notes folder is user://feedback")

	# Step 2: F9 opens the box and pauses the match.
	var hangar_before := hud.hangar != null and hud.hangar.visible
	_press(KEY_F9)
	await _frames(3)
	_expect(hud.note_box != null and hud.note_box.is_open(), "F9", "the note box opened")
	_expect(get_tree().paused, "F9", "the match is paused while the box is open")
	var t_open := world.time
	await _wait_ms(400)
	_expect(world.time == t_open, "F9", "the match clock stood still for 400 ms (%.3f)" % t_open)
	await _shot("note_open")
	var ship: Ship = null
	if world.human != null and world.human.ship != null and is_instance_valid(world.human.ship):
		ship = world.human.ship
	var ship_at := ship.global_position if ship != null else Vector2.ZERO
	var credits_open := int(world.human.credits) if world.human != null else 0

	# Step 3: menu keys typed into the box are text.
	var typed := "T-99: b h p f c r v g 1 2 3 4 tab"
	for ch in typed:
		_type(ch)
	_key(KEY_TAB, true)
	await _frames(2)
	_expect(hud.note_box.text() == typed, "typing", "the box holds what was typed")
	await _shot("note_typed")
	_expect(get_tree().paused, "typing", "the match is still paused after typing P")
	_expect((hud.hangar != null and hud.hangar.visible) == hangar_before, "typing", "typing B did not open or close the hangar")
	_expect(hud.help == null or not hud.help.visible, "typing", "typing H did not open the help")
	_expect(hud.scoreboard == null or not hud.scoreboard.visible, "typing", "Tab (held) did not open the scoreboard")
	_expect(hud.board == null or not hud.board.visible, "typing", "Tab (held) did not open the Admiral board")
	_key(KEY_TAB, false)
	# The text box takes the letters before the HUD's key router sees them, so
	# call the router itself with each menu key, as a key nobody took would.
	for code: Key in [KEY_P, KEY_B, KEY_H, KEY_C, KEY_F, KEY_TAB]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = true
		hud.router.handle(ev)
	await _frames(2)
	_expect(hud.note_box.is_open() and get_tree().paused, "router", "the HUD key router ignored P, B, H, C, F and Tab: the box is open, the match paused")
	_expect((hud.hangar != null and hud.hangar.visible) == hangar_before, "router", "B left the hangar alone")
	_expect(hud.help == null or not hud.help.visible, "router", "H left the help alone")
	_expect(hud.scoreboard == null or not hud.scoreboard.visible, "router", "Tab left the scoreboard alone")
	_expect(hud.board == null or not hud.board.visible, "router", "Tab left the Admiral board alone")

	# Step 4: Enter saves.
	toasts.clear()
	_press(KEY_ENTER)
	await _frames(3)
	_expect(not hud.note_box.is_open(), "Enter", "the box closed")
	_expect(toasts.has("Note saved."), "Enter", "the pop-up says: Note saved.")
	_expect(not toasts.any(func(t: String) -> bool: return t.to_lower().contains("download")), "Enter", "this game is not a browser build, so no pop-up speaks of a download (%s)" % str(toasts))
	_expect(not get_tree().paused, "Enter", "the match runs again")
	var t_after := world.time
	await _wait_ms(400)
	_expect(world.time > t_after, "Enter", "the match clock moves again (%.3f to %.3f)" % [t_after, world.time])
	var files := _notes()
	_expect(files.size() == 1, "Enter", "one note file exists (%d)" % files.size())
	if files.size() == 1:
		var note := _read(files[0])
		var raw := FileAccess.get_file_as_bytes(dir + "/" + files[0])
		_expect(raw == FileAccess.get_file_as_string(dir + "/" + files[0]).to_utf8_buffer(), "Enter", "the note file is plain UTF-8 text, so its download (the text as UTF-8) is the same file (%d bytes)" % raw.size())
		_expect(str(note.get("text")) == typed, "Enter", "the note holds the typed text")
		_expect(str(note.get("item")) == "T-99", "Enter", "the item ID is T-99")
		_expect(str(note.get("saved_at")).length() == 19, "Enter", "the real date and time is there (%s)" % str(note.get("saved_at")))
		var m: Dictionary = note.get("match", {})
		_expect(is_equal_approx(float(m.get("time", -1.0)), snappedf(t_open, 0.1)), "Enter", "the match time is the time of the pause (%s)" % str(m.get("clock")))
		_expect(bool(m.get("paused_before", true)) == false, "Enter", "the note says the match was not paused before")
		_expect(m.has("world_speed") and is_equal_approx(float(m["world_speed"]), world.speed.factor), "Enter", "the note records the world speed (%s)" % str(m.get("world_speed")))
		var s: Dictionary = note.get("setup", {})
		_expect(str(s.get("seed")) == str(Game.opt("seed", "random")), "Enter", "the seed is %s" % str(s.get("seed")))
		# The note names the rules played: the standard rules ("pick") when the
		# check was started without --preset, else the preset it was given.
		var asked := str(Game.opt("preset", ""))
		var want_preset := asked if asked != "" else CouncilPresets.STANDARD
		_expect(str(s.get("preset")) == Game.preset and Game.preset == want_preset, "Enter", "the note names the preset played, '%s' (wanted '%s')" % [str(s.get("preset")), want_preset])
		_expect(CouncilPresets.LABELS.has(want_preset) and str(s.get("rule_set")) == str(CouncilPresets.LABELS[want_preset]), "Enter", "the note's rule_set says '%s'" % str(s.get("rule_set")))
		_expect(s.has("unlock_everything") and bool(s["unlock_everything"]) == Game.unlock_everything, "Enter", "the note records the Unlock everything switch (%s)" % str(s.get("unlock_everything")))
		_expect(s.has("fog_off") and bool(s["fog_off"]) == Game.fog_off, "Enter", "the note records the No fog switch (%s)" % str(s.get("fog_off")))
		var hm: Dictionary = note.get("human", {})
		_expect(str(hm.get("role")) == world.human_role, "Enter", "the seat is %s" % str(hm.get("role")))
		if ship != null:
			_expect(str(hm.get("ship")) == ship.hull_id, "Enter", "the ship is %s" % str(hm.get("ship")))
			var pos: Array = hm.get("position", [])
			_expect(pos.size() == 2 and int(pos[0]) == int(round(ship_at.x)) and int(pos[1]) == int(round(ship_at.y)), "Enter", "the position is the ship's (%s)" % str(pos))
			_expect(str(hm.get("position_is")) == "ship", "Enter", "the position says it is the ship's")
		else:
			_expect(str(hm.get("ship")) == "", "Enter", "no ship in space is named")
			_expect(str(hm.get("position_is")) == "camera", "Enter", "the position says it is the camera's")
		if world.human != null:
			_expect(int(hm.get("credits", -1)) == credits_open, "Enter", "the credits are %d" % credits_open)
		var win := Vector2i(get_window().size)
		var sc: Dictionary = note.get("screen", {})
		var sw: Array = sc.get("window", [])
		_expect(sw.size() == 2 and int(sw[0]) == win.x and int(sw[1]) == win.y, "Enter", "the note gives the window size (%s)" % str(sw))
		var png_name := str(note.get("screenshot"))
		if windowed:
			_expect(png_name != "" and FileAccess.file_exists(dir + "/" + png_name), "Enter", "the screenshot exists (%s)" % png_name)
			if png_name != "":
				var img := Image.load_from_file(ProjectSettings.globalize_path(dir + "/" + png_name))
				var size_text := "no image"
				var same := false
				if img != null:
					size_text = str(img.get_size())
					same = img.get_size() == win
				_expect(same, "Enter", "the screenshot is as big as the window (%s, window %s)" % [size_text, str(win)])
		else:
			_expect(png_name == "", "Enter", "a headless game draws nothing, so the note names no screenshot")
		_expect(_pngs().size() == (1 if windowed else 0), "Enter", "%d screenshot file(s) in the folder" % _pngs().size())
		print("note_check note: ", JSON.stringify(note))

	# Step 5: Esc cancels.
	_press(KEY_F9)
	await _frames(3)
	for ch in "cancel me":
		_type(ch)
	_press(KEY_ESCAPE)
	await _frames(3)
	_expect(not hud.note_box.is_open(), "Esc", "the box closed")
	_expect(not get_tree().paused, "Esc", "the match runs again")
	_expect(_notes().size() == 1, "Esc", "no new note was saved (%d files)" % _notes().size())
	_expect(hud.help == null or not hud.help.visible, "Esc", "Esc opened no panel")

	# Step 6: a match paused with P stays paused after a note.
	get_tree().paused = true
	_press(KEY_F9)
	await _frames(3)
	_expect(hud.note_box.is_open() and get_tree().paused, "paused first", "the box opened over a paused match")
	_type("x")
	_press(KEY_ENTER)
	await _frames(3)
	_expect(not hud.note_box.is_open(), "paused first", "the box closed")
	_expect(get_tree().paused, "paused first", "the match is still paused, as before the note")
	var twice := _notes()
	_expect(twice.size() == 2, "paused first", "a second note was saved (%d files)" % twice.size())
	if twice.size() == 2:
		var n2 := _read(twice[1])
		var m2: Dictionary = n2.get("match", {})
		_expect(bool(m2.get("paused_before", false)), "paused first", "the note says the match was paused before")
	get_tree().paused = false

	# Step 7: Enter on an empty box saves a marker note.
	_press(KEY_F9)
	await _frames(3)
	_press(KEY_ENTER)
	await _frames(3)
	var three := _notes()
	_expect(three.size() == 3, "empty", "an empty note was saved (%d files)" % three.size())
	if three.size() == 3:
		var n3 := _read(three[2])
		_expect(str(n3.get("text")) == "" and str(n3.get("item")) == "", "empty", "it has no text and no item")
	_expect(not get_tree().paused, "empty", "the match runs again")

	# Step 8: a second F9 while the box is open changes nothing.
	_press(KEY_F9)
	await _frames(3)
	_type("a")
	_press(KEY_F9)
	await _frames(3)
	_expect(hud.note_box.is_open() and hud.note_box.text() == "a", "second F9", "the box is still open with its text")
	_press(KEY_ESCAPE)
	await _frames(3)
	_expect(not hud.note_box.is_open() and not get_tree().paused, "second F9", "Esc closed it and the match runs")
	_expect(_notes().size() == 3, "second F9", "still three notes")

	# Step 9: a fire button the game thinks is held (a release that came while
	# the match was paused never reaches it) is set back to the real state of
	# the mouse when the box closes. No real button is down here.
	world.mouse_fire = true
	world.mouse_special = true
	_press(KEY_F9)
	await _frames(3)
	_press(KEY_ESCAPE)
	await _frames(3)
	_expect(world.mouse_fire == Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and world.mouse_special == Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), "mouse", "the mouse buttons are as they really are after the box closes")

	# Step 10: F9 also works once the match is over (the end screen is up), and
	# the note says so.
	var phase_before := world.phase
	world.phase = "end"
	_press(KEY_F9)
	await _frames(3)
	_expect(hud.note_box.is_open(), "after the match", "F9 opens the box when the match is over")
	_type("e")
	_press(KEY_ENTER)
	await _frames(3)
	var four := _notes()
	_expect(four.size() == 4, "after the match", "the note was saved (%d files)" % four.size())
	if four.size() == 4:
		var n4 := _read(four[3])
		var m4: Dictionary = n4.get("match", {})
		_expect(str(m4.get("phase")) == "end", "after the match", "the note says the match phase is end")
	world.phase = phase_before
	_expect(not get_tree().paused, "after the match", "the game is not left paused")

	_finish()


## Print the summary line and quit.
func _finish() -> void:
	print("note_check: %d failures" % failures)
	get_tree().quit()


## NoteWriter.item_id() reads the IDs it should.
func _check_item_ids() -> void:
	var cases := {"T-07: top lane falls": "T-07", "t-7 hello": "T-7", "  M-12:": "M-12", "hello T-07": "", "": "", "T-07a": "", "T07": "", "T-7": "T-7"}
	var bad := 0
	for text: String in cases:
		if NoteWriter.item_id(text) != cases[text]:
			bad += 1
			_fail("item ids", "\"%s\" gave \"%s\", wanted \"%s\"" % [text, NoteWriter.item_id(text), cases[text]])
	if bad == 0:
		print("note_check item ids: ok (%d cases)" % cases.size())


## The browser build's download call exists in this engine. The browser build
## itself cannot run here, but its call can be looked up: the class
## JavaScriptBridge (a stand-in on every platform but the web) and its method
## download_buffer.
func _check_browser_api() -> void:
	var has_class := ClassDB.class_exists("JavaScriptBridge")
	var has_call := has_class and ClassDB.class_has_method("JavaScriptBridge", "download_buffer")
	_expect(has_class, "browser api", "the class JavaScriptBridge exists in this engine")
	_expect(has_call, "browser api", "JavaScriptBridge has the method download_buffer")


## NoteWriter.browser_files() lists what the browser build hands over: the note
## first (a ".json" name, application/json, its text as UTF-8 bytes) and, when
## there is a picture, the picture second (a ".png" name, image/png, bytes that
## load back as a picture of the same size and equal the PNG file the same
## picture makes in the folder); without a picture, only the note.
func _check_browser_files() -> void:
	var stem := "note_20000101_000000_2"
	var text := "{\n  \"text\": \"caf" + String.chr(0xE9) + "\"\n}\n"
	var img := Image.create_empty(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.6))
	var both := NoteWriter.browser_files(stem, text, img)
	_expect(both.size() == 2, "browser files", "a note with a picture hands over two files (%d)" % both.size())
	if both.size() == 2:
		_expect(both[0]["name"] == stem + ".json" and both[0]["mime"] == "application/json", "browser files", "the note comes first, as %s (%s)" % [both[0]["name"], both[0]["mime"]])
		var back: PackedByteArray = both[0]["bytes"]
		_expect(back.get_string_from_utf8() == text and back == text.to_utf8_buffer(), "browser files", "the note's bytes are its text in UTF-8 (%d bytes)" % back.size())
		_expect(both[1]["name"] == stem + ".png" and both[1]["mime"] == "image/png", "browser files", "the picture comes second, as %s (%s)" % [both[1]["name"], both[1]["mime"]])
		var png := Image.new()
		var loaded := png.load_png_from_buffer(both[1]["bytes"])
		_expect(loaded == OK and png.get_size() == img.get_size(), "browser files", "the picture's bytes load back as a picture of the same size (%s)" % str(png.get_size()))
		# The picture handed to the browser is the very file that goes into the folder.
		DirAccess.make_dir_recursive_absolute(dir)
		var probe := dir + "/probe_picture.png"
		_expect(img.save_png(probe) == OK and FileAccess.get_file_as_bytes(probe) == both[1]["bytes"], "browser files", "the picture's bytes are the bytes of the PNG file in the folder")
		DirAccess.remove_absolute(probe)
	_expect(NoteWriter.browser_files(stem, text, null).size() == 1, "browser files", "a note without a picture hands over only the note")
	_expect(NoteWriter.browser_files(stem, text, Image.new()).size() == 1, "browser files", "an empty picture is left out too")


## The help page's notes paragraph (the Windows text) still ends with the
## sentence the browser build swaps for its own, and the browser's sentence
## tells the player about the two downloads, the browser's question and what
## to do after answering Block.
func _check_help_text() -> void:
	var paragraph := ""
	for entry: Array in HelpPanel.PAGES["The match"]:
		if entry[0] == "Notes (F9)":
			paragraph = str(entry[1])
	_expect(paragraph.ends_with(" " + HelpPanel.NOTES_WHERE) and HelpPanel.NOTES_WHERE == "Notes stay on this computer.", "help text", "the notes paragraph ends with: %s" % HelpPanel.NOTES_WHERE)
	var browser := HelpPanel.NOTES_WHERE_BROWSER
	_expect(browser.contains("two downloads") and browser.contains("several files") and browser.contains("allow it") and browser.contains("Block"), "help text", "the browser's sentence names the two downloads, the question to allow and what to do after a Block")


## Events.toast: remember the pop-up text.
func _on_toast(text: String) -> void:
	toasts.append(text)


## One key press and release, pushed into the window (key `code`).
func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


## Key `code` going down (`down` true) or coming up, pushed into the window.
func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	get_viewport().push_input(ev, true)


## One typed character `ch`: its key press and release, with the character
## itself attached (as a keyboard sends it).
func _type(ch: String) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		var code := ch.to_upper().unicode_at(0)
		ev.keycode = code as Key
		ev.physical_keycode = code as Key
		ev.unicode = ch.unicode_at(0) if down else 0
		ev.pressed = down
		get_viewport().push_input(ev, true)


## The note files (JSON) in the folder, in name order.
func _notes() -> Array:
	return _files(".json")


## The screenshot files (PNG) in the folder, in name order.
func _pngs() -> Array:
	return _files(".png")


## The files in the folder whose name ends with `ext`, in name order.
func _files(ext: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d != null:
		for fn in d.get_files():
			if fn.begins_with("note_") and fn.ends_with(ext):
				out.append(fn)
	out.sort()
	return out


## The note file `fn` as a dictionary (empty when it cannot be read).
func _read(fn: String) -> Dictionary:
	var f := FileAccess.open(dir + "/" + fn, FileAccess.READ)
	if f == null:
		_fail("read", "cannot open %s" % fn)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## Delete the note files (and screenshots) in `folder`, so the check can count.
func _clear(folder: String) -> void:
	var d := DirAccess.open(folder)
	if d == null:
		return
	for fn in d.get_files():
		if fn.begins_with("note_"):
			d.remove(fn)


## Count a failure and print it when `ok` is false, else print the good news.
func _expect(ok: bool, step: String, what: String) -> void:
	if ok:
		print("note_check %s: ok, %s" % [step, what])
	else:
		_fail(step, what)


## Print one failure for step `step` and count it.
func _fail(step: String, why: String) -> void:
	failures += 1
	print("FAIL note_check %s: %s" % [step, why])


## With --shots=<folder> and a window: save the screen as <folder>/<shot_name>.png
## (the box open, to see how it looks). Without them it does nothing.
func _shot(shot_name: String) -> void:
	var shots := str(Game.opt("shots", ""))
	if shots == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(shots)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, shot_name])
	print("note_check shot: %s/%s.png" % [shots, shot_name])


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait `ms` milliseconds of real time (frames and match ticks are not the same
## thing: a windowless run draws many frames between two ticks).
func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
