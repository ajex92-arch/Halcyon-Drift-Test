extends Node
## WHAT THIS IS: the key check. It proves the key list (KeyMapData) is sound: today's
## controls are unchanged, no key does two things, the keys other features own are where
## they were, and the screens that print keys print what the list says.
##
## HOW IT WORKS: setup() runs the checks in order and prints "key_map_check: N failures"
## (and one FAIL line for each failure, one line of warnings). Check 0, the parity test, keeps a hand copy of
## the controls the game had before the key list existed (_oracle) and compares the events
## of every InputMap action with what GameInputMap.define_all() made from the list: they must
## be equal, in order (the HUD's key line reads the first key), with exactly the differences the
## list brings on purpose (_new_actions and the extra F12 on "help"). The test reads no
## settings file: it runs on the standard keys. The rules of the key check then run once for every
## combination of the key presets (every layout of every group together, so 3 now): in each mode (the
## shared keys included) no key does two things on the same page; the flying rows are today's keys plus
## the team wheel; Z is unbound in the flying modes (and at home under layout B) until the Vent row binds
## it, and Shift+Z, the key the Vent row takes in layout C, is free in the flying modes; no default
## uses Alt with an F-key, Alt+Tab or Alt+F4, only full screen uses Alt+Enter, and Esc is cancel only; the keys other
## items own (F9, P, the backquote, Ctrl+F12) are where their owners read them and used by nobody else; a
## key a rule variant reads straight from the keyboard clashes only as a warning while that variant is off in
## the standard rules and both presets, and fails when it is on; every row has a mouse route (a warning
## for the rows that work now, a failure for any later row); the Keys page and the key line are made from
## the list and come out the same every time; and the data round-trips through a settings file.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/):
##   godot --headless --path remake -- --auto --all-ai --test=key_map_check
##
## WHO USES IT: main.gd loads it for --test=key_map_check (it calls setup()); run_checks runs it.

## The events (a key text for each) the game's controls had before the key list: action -> list of
## events, as `describe()` writes them. "k" is a key by its place on the keyboard, "m" a mouse button; a
## trailing "+a" is Alt held.
static func _oracle() -> Dictionary:
	var o := {
		"thrust_forward": [_k(KEY_W)], "thrust_back": [_k(KEY_S)], "strafe_left": [_k(KEY_A), _k(KEY_Q)],
		"strafe_right": [_k(KEY_D), _k(KEY_E)], "boost": [_k(KEY_SHIFT)], "fire": [_m(MOUSE_BUTTON_LEFT)],
		"special": [_k(KEY_G), _m(MOUSE_BUTTON_RIGHT)], "shield_front": [_k(KEY_UP)], "shield_rear": [_k(KEY_DOWN)],
		"shield_left": [_k(KEY_LEFT)], "shield_right": [_k(KEY_RIGHT)], "energy_weapons": [_k(KEY_1)],
		"energy_shields": [_k(KEY_2)], "energy_thrusters": [_k(KEY_3)], "energy_balanced": [_k(KEY_4)],
		"use_kit": [_k(KEY_R)], "assist_toggle": [_k(KEY_V)], "hangar": [_k(KEY_B)], "dock": [_k(KEY_F)],
		"admiral_board": [_k(KEY_TAB)], "help": [_k(KEY_H)], "center_camera": [_k(KEY_C)],
		"center_on_ship": [_k(KEY_SPACE)], "zoom_in": [_k(KEY_EQUAL), _k(KEY_KP_ADD)],
		"zoom_out": [_k(KEY_MINUS), _k(KEY_KP_SUBTRACT)], "cancel": [_k(KEY_ESCAPE)],
		"toggle_fullscreen": [_k(KEY_ENTER, "a"), _k(KEY_KP_ENTER, "a")], "note": [_k(KEY_F9)],
		"slow_motion": [_k(KEY_QUOTELEFT)],
	}
	# F11 comes first, except in the web build, which leaves it to the browser.
	if not OS.has_feature("web"):
		(o["toggle_fullscreen"] as Array).push_front(_k(KEY_F11))
	return o

## The actions the key list adds on purpose, with their events: pause, the faster speed, the debug launch
## and the order wheel.
static func _new_actions() -> Dictionary:
	return {
		"pause": [_k(KEY_P)], "fast_motion": [_k(KEY_QUOTELEFT, "s")], "debug_launch": [_k(KEY_F12, "c")],
		"wheel": [_k(KEY_X), _m(MOUSE_BUTTON_XBUTTON2)],
	}

## How many checks failed.
var _fails := 0
## How many rows that work now have no mouse route.
var _no_route_now := 0
## How many rows that come with later parts have no mouse route (each of them fails).
var _no_route_later := 0
## The clashes with the keys of rule variants that are off (warnings), each as a line of words.
var _variant_warnings := []
## The key reminder lines (Admiral, pilot, spectator) the game had before the key list existed.
const OLD_LINES := {
	"admiral": "Tab Admiral board · B hangar · C camera · Space center camera (hold to follow) · H help · P pause · F9 note",
	"pilot": "B hangar · F dock/launch · R repair kit · Space center camera (hold to follow) · hold Tab scores · H help · P pause · F9 note",
	"spectator": "H help · P pause · F9 note",
}


## main.gd calls this once, right after the World is built (the World is not needed).
func setup(_w: World) -> void:
	_parity()
	_rows_sane()
	_presets_sane()
	var t0 := Time.get_ticks_msec()
	var combos := _combos()
	for combo: Dictionary in combos:
		_rules(combo)
	print("key_map_check: %d preset combinations checked in %d ms; %d rows without a mouse route (%d work now, %d come later); %d clashes with the keys of rule variants that are off" % [combos.size(), Time.get_ticks_msec() - t0, _no_route_now + _no_route_later, _no_route_now, _no_route_later, _variant_warnings.size()])
	for w in _variant_warnings:
		print("key_map_check: warning: ", w)
	_texts()
	_sources()
	_file_round_trip()
	print("key_map_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## A key by its place on the keyboard; `mods` holds "s" (Shift), "c" (Ctrl) or "a" (Alt).
static func _k(code: int, mods: String = "") -> String:
	return "k%d%s" % [code, ("+" + mods) if mods != "" else ""]


## A mouse button.
static func _m(button: int) -> String:
	return "m%d" % button


## The event `ev` written like _k() and _m() do.
static func describe(ev: InputEvent) -> String:
	var mods := ""
	var w := ev as InputEventWithModifiers
	if w != null:
		mods = ("s" if w.shift_pressed else "") + ("c" if w.ctrl_pressed else "") + ("a" if w.alt_pressed else "")
	if ev is InputEventKey:
		return _k(int((ev as InputEventKey).physical_keycode), mods)
	if ev is InputEventMouseButton:
		return "m%d%s" % [int((ev as InputEventMouseButton).button_index), ("+" + mods) if mods != "" else ""]
	return "?"


## The events of InputMap action `a` written as a list.
func _events_of(a: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(a):
		out.append(describe(ev))
	return out


## Check 0: every old action has the old events in the old order, the new actions are exactly
## the four the list adds, "help" has F12 after H, and no other action exists.
func _parity() -> void:
	var oracle := _oracle()
	var added := _new_actions()
	for a: String in oracle:
		_check("parity: action %s exists" % a, InputMap.has_action(a))
		if not InputMap.has_action(a):
			continue
		var want: Array = (oracle[a] as Array).duplicate()
		if a == "help":
			want.append(_k(KEY_F12))
		_check("parity: events of %s" % a, _events_of(a) == want, "%s != %s" % [str(_events_of(a)), str(want)])
	for a: String in added:
		_check("parity: new action %s exists with its events" % a, InputMap.has_action(a) and _events_of(a) == added[a], str(_events_of(a)))
	for a in InputMap.get_actions():
		var n := String(a)
		if n.begins_with("ui_") or oracle.has(n) or added.has(n):
			continue
		_check("parity: no other action (found %s)" % n, false)


## The rows themselves: each id is used once per mode, each key text reads, and each link follows a
## flying action.
func _rows_sane() -> void:
	for m: String in KeyMapData.MODES:
		var seen := {}
		for r: Dictionary in KeyMap.rows(m):
			var id := String(r["id"])
			_check("rows: %s/%s is unique" % [m, id], not seen.has(id))
			seen[id] = true
			for k in String(r["keys"]).split("|", false):
				_check("rows: %s/%s key '%s' reads" % [m, id, k], KeyCodes.canonical(String(k)) != "")
			if String(r["link"]) != "":
				_check("rows: %s/%s follows a flying action" % [m, id], not KeyMap.row("flying", String(r["link"])).is_empty())

## The fields, pages and stages of every row, and the key sets (presets).
func _presets_sane() -> void:
	var live_or_known := KeyMapData.LIVE_STAGES + KeyMapData.COMES_WITH.keys()
	var shared_ids := {}
	for r: Dictionary in KeyMap.rows("shared"):
		shared_ids[r["id"]] = true
	for m: String in KeyMapData.MODES:
		for r: Dictionary in KeyMap.rows(m):
			var n := "%s/%s" % [m, r["id"]]
			_check("rows: %s has a label" % n, String(r["label"]) != "")
			_check("rows: %s has a known page" % n, ["", "orders", "build", "base"].has(String(r["page"])))
			_check("rows: %s has a known stage (%s)" % [n, r["since"]], live_or_known.has(String(r["since"])))
			_check("rows: %s is in a group the page lists" % n, ControlsRows.GROUP_ORDER.has(String(r["group"])), String(r["group"]))
			_check("rows: %s is not both a link and fixed" % n, not (String(r["link"]) != "" and bool(r["fixed"])))
			if m == "flying":
				_check("rows: %s is not also a shared action (the InputMap is flat)" % n, not shared_ids.has(r["id"]))
	for g: Dictionary in KeyMapData.PRESETS:
		var gid := String(g["id"])
		_check("presets: group %s has its default" % gid, (g["presets"] as Dictionary).has(g["default"]))
		_check("presets: group %s names a tab" % gid, KeyMapData.MODES.has(String(g["tab"])))
		for pid: String in g["presets"]:
			var p: Dictionary = g["presets"][pid]
			_check("presets: %s/%s has a label and a line of words" % [gid, pid], String(p["label"]) != "" and String(p["text"]) != "")
			for m: String in p["rows"]:
				_check("presets: %s/%s names a mode that exists (%s)" % [gid, pid, m], KeyMapData.MODES.has(m))
				for a: String in p["rows"][m]:
					var v: Variant = p["rows"][m][a]
					var txt := String(v) if v is String else String((v as Dictionary).get("keys", ""))
					_check("presets: %s/%s lists a row that exists (%s/%s)" % [gid, pid, m, a], not KeyMap.row(m, a).is_empty())
					for k in txt.split("|", false):
						_check("presets: %s/%s key '%s' of %s reads" % [gid, pid, k, a], KeyCodes.canonical(String(k)) != "")


## Every combination of the key presets: one preset of every group, as {group id: preset id}. Three today
## (the home layouts); a second group of presets multiplies the number.
func _combos() -> Array:
	var out := [{}]
	for g: Dictionary in KeyMapData.PRESETS:
		var next := []
		for combo: Dictionary in out:
			for pid: String in g["presets"]:
				var c := combo.duplicate()
				c[g["id"]] = pid
				next.append(c)
		out = next
	return out


## The pilot's keys as the game had them (and the team wheel): action -> key texts. The flying rows must be exactly these
## (the Vent row, when it is added, is allowed on top).
const FLYING_KEYS := {
	"thrust_forward": ["W"], "thrust_back": ["S"], "strafe_left": ["A", "Q"], "strafe_right": ["D", "E"], "boost": ["Shift"],
	"fire": ["Mouse1"], "special": ["G", "Mouse2"], "face_lock": ["Ctrl"], "shield_front": ["Up"], "shield_rear": ["Down"],
	"shield_left": ["Left"], "shield_right": ["Right"], "energy_weapons": ["1"], "energy_shields": ["2"], "energy_thrusters": ["3"],
	"energy_balanced": ["4"], "use_kit": ["R"], "assist_toggle": ["V"], "hangar": ["B"], "dock": ["F"], "help": ["H", "F12"],
	"center_camera": ["C"], "team_wheel": ["T", "Mouse4"],
}
## The keys other parts of the game own, by action: they must be where their owners read them and nobody else uses them.
const OWNED := {"note": "F9", "pause": "P", "slow_motion": "QuoteLeft", "fast_motion": "Shift+QuoteLeft", "debug_launch": "Ctrl+F12"}


## The rules of the key check for one combination of key presets, `combo`.
func _rules(combo: Dictionary) -> void:
	KeyMap.reset_to_defaults()
	var names := PackedStringArray()
	for g: String in combo:
		KeyMap.set_preset(g, combo[g])
		names.append("%s=%s" % [g, combo[g]])
	var tag := " [%s]" % ", ".join(names)
	var layout := String(combo.get("home_layout", "B"))
	# Rule 1: in each mode (the shared keys included) no key does two things on the same page.
	for m: String in KeyMapData.MODES:
		var found := KeyMap.mode_clashes(m)
		var words := []
		for c: Dictionary in found:
			words.append("%s with %s" % [c["label"], ", ".join(PackedStringArray((c["others"] as Array).map(func(o: Dictionary) -> String: return String(o["label"]))))])
		_check("no key does two things in %s%s" % [m, tag], found.is_empty(), "; ".join(PackedStringArray(words)))
	# Rule 2: the flying rows are today's keys plus the team wheel (and the Vent row once it exists).
	var seen := {}
	for r: Dictionary in KeyMap.rows("flying"):
		var id := String(r["id"])
		seen[id] = true
		if id == "vent":
			continue
		_check("flying/%s is a key of today's pilot%s" % [id, tag], FLYING_KEYS.has(id))
		if FLYING_KEYS.has(id):
			var want: Array = FLYING_KEYS[id]
			if id == "help":
				want = ["H", "F12"]
			_check("flying/%s has the keys %s%s" % [id, str(want), tag], KeyMap.effective_keys("flying", id) == want, str(KeyMap.effective_keys("flying", id)))
	for id: String in FLYING_KEYS:
		_check("flying/%s is still there%s" % [id, tag], seen.has(id))
	# Rule 3: Z is reserved for the Vent row; Shift+Z is free in the flying modes (layout C gives it to Vent).
	var has_vent := not KeyMap.row("flying", "vent").is_empty()
	for m: String in ["flying", "flying_board"]:
		for r: Dictionary in KeyMap.rows_in_force(m):
			var keys := KeyMap.effective_keys(String(r["mode"]), String(r["id"]))
			if String(r["id"]) != "vent":
				_check("Z is unbound in %s (%s)%s" % [m, r["label"], tag], not keys.has("Z"))
				_check("Shift+Z is free in %s (%s)%s" % [m, r["label"], tag], not keys.has("Shift+Z"))
	if layout == "B":
		for r: Dictionary in KeyMap.rows_in_force("home"):
			_check("Z is unbound at home under layout B (%s)" % r["label"], not KeyMap.effective_keys(String(r["mode"]), String(r["id"])).has("Z"))
	if has_vent:
		var want_vent := ["Shift+Z"] if layout == "C" else ["Z"]
		_check("the Vent row has %s%s" % [str(want_vent), tag], KeyMap.effective_keys("flying", "vent") == want_vent, str(KeyMap.effective_keys("flying", "vent")))
	# Rule 4: no default uses Alt with an F-key, Alt+Tab or Alt+F4; Alt+Enter only for full screen; Esc is cancel only.
	for m: String in KeyMapData.MODES:
		for r: Dictionary in KeyMap.rows_in_force(m):
			for k in KeyMap.effective_keys(String(r["mode"]), String(r["id"])):
				var p := KeyCodes.parse(String(k))
				var who := "%s/%s key %s%s" % [r["mode"], r["id"], k, tag]
				if bool(p["alt"]) and not bool(p["mouse"]):
					var code := int(p["code"])
					_check("%s: no Alt with an F-key" % who, not (code >= KEY_F1 and code <= KEY_F12))
					_check("%s: no Alt+Tab" % who, code != KEY_TAB)
					if code == KEY_ENTER or code == KEY_KP_ENTER:
						_check("%s: Alt+Enter is for full screen only" % who, String(r["id"]) == "toggle_fullscreen")
				if k == "Esc":
					_check("%s: Esc is cancel only" % who, String(r["id"]) == "cancel")
	# Rule 5: the keys other parts own are where they were, and nobody else uses them.
	for a: String in OWNED:
		_check("%s is %s%s" % [a, OWNED[a], tag], KeyMap.effective_keys("shared", a).has(OWNED[a]))
		for m: String in KeyMapData.MODES:
			for r: Dictionary in KeyMap.rows_in_force(m):
				if String(r["id"]) != a and KeyMap.effective_keys(String(r["mode"]), String(r["id"])).has(OWNED[a]):
					_check("%s: nobody else uses %s (%s/%s does)%s" % [a, OWNED[a], r["mode"], r["id"], tag], false)
	# The keys a rule variant reads from the keyboard: a failure when that variant is on in the standard rules or either
	# preset, a warning when it is off.
	for m: String in KeyMapData.MODES:
		for r: Dictionary in KeyMap.rows_in_force(m):
			for h: Dictionary in KeyMap.variant_hits(m, KeyMap.effective_keys(String(r["mode"]), String(r["id"]))):
				var line := "%s/%s (%s) is also the key %s of %s" % [r["mode"], r["id"], r["label"], h["key"], h["label"]]
				if KeyMap.variant_on(String(h["variant"]), false):
					_check("variant keys: %s, which is on" % line, false)
				elif not _variant_warnings.has(line + ", which is off"):
					_variant_warnings.append(line + ", which is off")
	# Rule 6: a mouse route for every row: a warning for a row that works now, a failure for a later one (counted once).
	if _no_route_now + _no_route_later == 0:
		for m: String in KeyMapData.MODES:
			for r: Dictionary in KeyMap.rows(m):
				if String(r["route"]) == "":
					if KeyMap.is_live(r):
						_no_route_now += 1
					else:
						_no_route_later += 1
						_check("%s/%s comes with a later part and must have a mouse route" % [m, r["id"]], false)


## Rule 7: the Keys page and the key line come from the list and come out the same every time, as the hand-written
## ones did, and follow a change and its undoing.
func _texts() -> void:
	KeyMap.reset_to_defaults()
	var text := KeyMapText.help_text()
	_check("the Keys page text is the same when made again", KeyMapText.help_text() == text)
	for role: String in OLD_LINES:
		_check("the %s key line reads as the hand-written one did" % role, KeyMap.key_line(role) == OLD_LINES[role], KeyMap.key_line(role))
	_check("the hints say H and Tab", KeyMapText.key_of("help") == "H" and KeyMapText.key_of("admiral_board") == "Tab")
	KeyMap.set_slot("flying", "hangar", 0, "K")
	_check("the key line follows a change", KeyMap.key_line("pilot").begins_with("K hangar") and KeyMapText.help_text() != text)
	KeyMap.reset_all()
	_check("and its undoing", KeyMap.key_line("pilot") == OLD_LINES["pilot"] and KeyMapText.help_text() == text)
	# The help panel's Keys page draws exactly the table.
	var hp: HelpPanel = load("res://scenes/ui/help_panel.tscn").instantiate()
	add_child(hp)
	hp._show("Keys")
	_check("the Keys page has a table for each mode", hp.keys_grids.size() == KeyMapData.MODES.size())
	for i in hp.keys_grids.size():
		var table := KeyMapText.help_table(KeyMapData.MODES[i])
		var grid := hp.keys_grids[i]
		_check("the %s table has a row for every action" % KeyMapData.MODES[i], grid.get_child_count() == 4 * (table.size() + 1), "%d cells for %d rows" % [grid.get_child_count(), table.size()])
		for j in table.size():
			var cell := grid.get_child(4 * (j + 1)) as Label
			if cell == null or cell.text != String(table[j]["label"]):
				_check("the %s table row %d names %s" % [KeyMapData.MODES[i], j, table[j]["label"]], false)
				break
	hp.queue_free()


## The owners read the actions the check names (a file that stops reading one would make the check true for nothing).
func _sources() -> void:
	var need := {
		"res://scripts/main.gd": ["is_action(\"debug_launch\", true)"],
		"res://scripts/ui/hud_input.gd": ["is_action(\"pause\", true)", "is_action(\"fast_motion\", true)", "is_action(\"slow_motion\", true)", "is_action(\"note\")"],
		"res://scripts/features/recall.gd": ["KEY_T"], "res://scripts/features/mutiny.gd": ["KEY_M"],
		"res://scripts/features/surrender.gd": ["KEY_F10", "KEY_F11"],
	}
	for path: String in need:
		var src := FileAccess.get_file_as_string(path)
		for s: String in need[path]:
			_check("%s still reads %s" % [path.get_file(), s], src.contains(s))


## Rule 8: the player's changes round-trip through a settings file, for every combination.
func _file_round_trip() -> void:
	var tmp := OS.get_cache_dir().path_join("hd_key_map_check_%d.cfg" % OS.get_process_id())
	for combo: Dictionary in _combos():
		KeyMap.reset_to_defaults()
		for g: String in combo:
			KeyMap.set_preset(g, combo[g])
		KeyMap.set_slot("flying", "use_kit", 0, "K")
		KeyMap.set_slot("home", "idle_next", 1, "Mouse3")
		var want := KeyMapText.help_text()
		_check("round trip: the file is written", KeyMap.save(tmp) == OK)
		KeyMap.reset_to_defaults()
		KeyMap.load_from(tmp)
		_check("round trip: the keys come back (%s)" % str(combo), KeyMapText.help_text() == want and KeyMap.last_dropped == 0)
	DirAccess.remove_absolute(tmp)
	KeyMap.reset_to_defaults()