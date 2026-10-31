class_name KeyMap
extends RefCounted
## WHAT THIS IS: the game's key bindings: which key does what in each mode, with
## the player's own changes and the chosen key preset applied on top of the list in
## KeyMapData. It answers "what are the keys of this action", "is this key already
## taken", and it keeps the game's InputMap in step with the answer.
##
## HOW IT WORKS: the keys of a row are, in order of strength: the player's change (an
## override, kept for the row), else the chosen preset's key for that row (KeyMapData
## PRESETS), else the row's own keys. A row can follow another action (`link`): the
## camera keys are the pilot's movement keys, so there is one binding, edited in one
## place and shown in each tab. Two keys clash when they are the same key text in
## the same mode (the Shared group counts in every mode), on the same page of the
## command card or when either row has no page; conflicts() names every clash. A key
## bound to two actions is never saved: the Controls page asks swap or keep first.
## apply_to_input_map() makes the InputMap actions of the live rows (the shared and
## flying modes) from these answers; it is also how GameInputMap.define_all() works.
## `version` goes up on every change, so a screen that shows keys can rebuild itself
## only when needed. The settings file part (save, load) is KeyMapStore, the help
## table and the key line are KeyMapText; this class forwards to both.
##
## WHO USES IT: GameInputMap (the live actions), Game (the remembered keys), the
## Controls page and its parts, HelpPanel (the Keys page), HudSlots (the key line),
## Hud (two hints), and tests/key_map_check.gd and tests/controls_page_check.gd.
## All functions are "static": call them as KeyMap.effective_keys(...).

## Goes up by one on every change of a binding or a preset. A screen compares it
## with the value it last saw.
static var version := 0
## How many entries the last load from a settings file left out because they were
## bad (an unknown action, a key we cannot read, a clash).
static var last_dropped := 0

## The player's changes: "mode/action" -> two key texts (either may be "").
static var _overrides := {}
## The presets the player picked: group id -> preset id.
static var _choice := {}
## The rows by mode (made once from KeyMapData.ROWS): mode -> Array of row Dictionaries.
static var _by_mode := {}
## The same rows by "mode/action".
static var _by_id := {}
## Answers kept for the current ersion (made again after any change): the visible rows of a mode,
## the rows in force in a mode and the keys of a row. They make the clash check fast.
static var _memo_version := -1
static var _memo_visible := {}
static var _memo_force := {}
static var _memo_keys := {}



# --- the rows ----------------------------------------------------------------------

## Make the row tables the first time they are asked for: every row of
## KeyMapData.ROWS with each missing field filled in.
static func _build() -> void:
	if not _by_mode.is_empty():
		return
	for m: String in KeyMapData.MODES:
		_by_mode[m] = []
	for src: Dictionary in KeyMapData.ROWS:
		var r := {
			"id": src["id"], "mode": src["mode"], "label": src["label"], "keys": src["keys"],
			"route": src.get("route", ""), "since": src.get("since", "today"), "group": src.get("group", "Shared"),
			"page": src.get("page", ""), "link": src.get("link", ""), "fixed": src.get("fixed", false),
			"action": src.get("action", true), "web_skip": src.get("web_skip", ""), "note": src.get("note", ""),
		}
		(_by_mode[r["mode"]] as Array).append(r)
		_by_id["%s/%s" % [r["mode"], r["id"]]] = r


## Forget the kept answers when a change has happened since they were made.
static func _fresh() -> void:
	if _memo_version != version:
		_memo_version = version
		_memo_visible.clear()
		_memo_force.clear()
		_memo_keys.clear()


## Every row of `mode` in the order of the data (hidden preset rows too).
static func rows(mode: String) -> Array:
	_build()
	return _by_mode.get(mode, [])


## Row `id` of `mode` ({} when there is none).
static func row(mode: String, id: String) -> Dictionary:
	_build()
	return _by_id.get("%s/%s" % [mode, id], {})


## Does the row work in today's game (its stage is in KeyMapData.LIVE_STAGES)?
static func is_live(r: Dictionary) -> bool:
	return KeyMapData.LIVE_STAGES.has(String(r["since"]))


## The preset the player picked for group `group` (the group's default when none).
static func preset_choice(group: String) -> String:
	for g: Dictionary in KeyMapData.PRESETS:
		if g["id"] == group:
			return String(_choice.get(group, g["default"]))
	return ""


## The group of presets `group` (a Dictionary of KeyMapData.PRESETS), or {}.
static func preset_group(group: String) -> Dictionary:
	for g: Dictionary in KeyMapData.PRESETS:
		if g["id"] == group:
			return g
	return {}


## What the chosen presets say about row `id` of `mode`: the key text, a
## Dictionary {keys, page}, or null when no chosen preset lists the row.
static func _preset_entry(mode: String, id: String) -> Variant:
	for g: Dictionary in KeyMapData.PRESETS:
		var p: Dictionary = (g["presets"] as Dictionary).get(preset_choice(String(g["id"])), {})
		var rows_of: Dictionary = (p.get("rows", {}) as Dictionary).get(mode, {})
		if rows_of.has(id):
			return rows_of[id]
	return null


## Is row `id` of `mode` listed by some preset (any, chosen or not)?
static func _in_some_preset(mode: String, id: String) -> bool:
	for g: Dictionary in KeyMapData.PRESETS:
		for pid: String in g["presets"]:
			if (((g["presets"][pid] as Dictionary).get("rows", {}) as Dictionary).get(mode, {}) as Dictionary).has(id):
				return true
	return false


## Does the page show this row? A row only some key sets use (a command card cell)
## is hidden while the chosen set does not list it; every other row shows.
static func is_visible(mode: String, id: String) -> bool:
	var r := row(mode, id)
	if r.is_empty():
		return false
	if String(r["keys"]) != "" or String(r["link"]) != "" or _preset_entry(mode, id) != null:
		return true
	return not _in_some_preset(mode, id)


## The rows the page lists for `mode`: its own visible rows, in data order.
static func visible_rows(mode: String) -> Array:
	_fresh()
	if _memo_visible.has(mode):
		return (_memo_visible[mode] as Array).duplicate()
	var out := []
	for r: Dictionary in rows(mode):
		if is_visible(mode, String(r["id"])):
			out.append(r)
	_memo_visible[mode] = out
	return out.duplicate()


## Every visible row that is in force in `mode`, for the clash check: the mode's own
## rows, the flying rows the board mode inherits (unless it has a row of the same
## name), and the shared rows.
static func rows_in_force(mode: String) -> Array:
	_fresh()
	if _memo_force.has(mode):
		return (_memo_force[mode] as Array).duplicate()
	var out := visible_rows(mode)
	if mode == "flying_board":
		var own := {}
		for r: Dictionary in out:
			own[r["id"]] = true
		for r: Dictionary in visible_rows("flying"):
			if not own.has(r["id"]):
				out.append(r)
	if mode != "shared":
		out.append_array(visible_rows("shared"))
	_memo_force[mode] = out
	return out.duplicate()


# --- the keys of a row -----------------------------------------------------------------

## Is the row a link that follows another action (no preset gives it keys of its own)?
static func is_linked(mode: String, id: String) -> bool:
	return String(row(mode, id).get("link", "")) != "" and _preset_entry(mode, id) == null


## The row whose keys a change to row `id` of `mode` edits: the row itself, or for a
## link the flying action it follows. Returns [mode, id].
static func resolve(mode: String, id: String) -> Array:
	if is_linked(mode, id):
		return ["flying", String(row(mode, id)["link"])]
	return [mode, id]


## The key texts a text "KEY1|KEY2" holds, in the standard form; a text we cannot read
## becomes "" (an empty slot stays in its place).
static func split_keys(text: String) -> Array:
	var out := []
	if text == "":
		return out
	for part in text.split("|", true):
		out.append(KeyCodes.canonical(String(part)))
	return out


## The command card page of the row: the chosen preset's page for it, else the row's.
static func page_of(mode: String, id: String) -> String:
	var p: Variant = _preset_entry(mode, id)
	if p is Dictionary and (p as Dictionary).has("page"):
		return String((p as Dictionary)["page"])
	return String(row(mode, id).get("page", ""))


## The keys of row `id` of `mode` without the player's change: the chosen preset's,
## else the row's own (in the web build without the keys the browser keeps).
static func default_slots(mode: String, id: String) -> Array:
	var r := row(mode, id)
	if r.is_empty():
		return []
	var txt := String(r["keys"])
	var p: Variant = _preset_entry(mode, id)
	if p is String:
		txt = p
	elif p is Dictionary:
		txt = String((p as Dictionary).get("keys", txt))
	var out := split_keys(txt)
	if OS.has_feature("web") and String(r["web_skip"]) != "":
		var skip := KeyCodes.canonical(String(r["web_skip"]))
		out = out.filter(func(k: String) -> bool: return k != skip)
	return out


## The key slots of the row, the player's change included: at least two entries
## (either may be ""), and any extra keys after them. A link gives the slots of the
## action it follows.
static func slot_keys(mode: String, id: String) -> Array:
	var t := resolve(mode, id)
	var d := default_slots(String(t[0]), String(t[1]))
	var o: Variant = _overrides.get("%s/%s" % [t[0], t[1]])
	var out := []
	if o is Array:
		out = [(o as Array)[0], (o as Array)[1]]
		for i in range(2, d.size()):
			out.append(d[i])
	else:
		out = d.duplicate()
	while out.size() < 2:
		out.append("")
	return out


## The keys the row is bound to, in order, without the empty slots.
static func effective_keys(mode: String, id: String) -> Array:
	_fresh()
	var key := "%s/%s" % [mode, id]
	if _memo_keys.has(key):
		return (_memo_keys[key] as Array).duplicate()
	var out := slot_keys(mode, id).filter(func(k: String) -> bool: return k != "")
	_memo_keys[key] = out
	return out.duplicate()


## The first key of the row, in the short form for screens ("" when it has none).
static func first_key(mode: String, id: String) -> String:
	var k := effective_keys(mode, id)
	return KeyCodes.display(String(k[0])) if not k.is_empty() else ""


## Has the player changed the keys of this row (the row a link follows included)?
static func is_changed(mode: String, id: String) -> bool:
	var t := resolve(mode, id)
	return _overrides.has("%s/%s" % [t[0], t[1]])


## All the player's changes as "mode/action" -> [key1, key2] (a copy).
static func overrides() -> Dictionary:
	return _overrides.duplicate(true)


## All the presets the player picked, group id -> preset id (a copy).
static func choices() -> Dictionary:
	return _choice.duplicate()


# --- clashes (the work is in KeyMapClash) --------------------------------------------------

## Is rule variant `variant` on in the standard rules or either preset, or (with `launch`) in
## this run's rules? Forwards to KeyMapClash.variant_on().
static func variant_on(variant: String, launch: bool = true) -> bool:
	return KeyMapClash.variant_on(variant, launch)


## The keys read straight from the keyboard by a rule variant that clash with `keys` in
## `mode`. Forwards to KeyMapClash.variant_hits().
static func variant_hits(mode: String, keys: Array) -> Array:
	return KeyMapClash.variant_hits(mode, keys)


## Every action that already has one of the key texts in `keys` where a change to row `id` of
## `mode` (on command card page `page`) would use it. Forwards to KeyMapClash.conflicts().
static func conflicts(mode: String, id: String, keys: Array, page: String = "") -> Array:
	return KeyMapClash.conflicts(mode, id, keys, page)


## The clashes inside `mode` as it stands. Forwards to KeyMapClash.mode_clashes().
static func mode_clashes(mode: String) -> Array:
	return KeyMapClash.mode_clashes(mode)


# --- changing keys ---------------------------------------------------------------------

## Bring the InputMap up to date after a change (a no-op for rows the game does not read).
static func _changed() -> void:
	version += 1
	apply_to_input_map()


## Are two slot lists the same two keys?
static func _same(a: Array, b: Array) -> bool:
	for i in 2:
		var x := String(a[i]) if i < a.size() else ""
		var y := String(b[i]) if i < b.size() else ""
		if x != y:
			return false
	return true


## Give row `id` of `mode` the keys in `keys` (the first two are its slots; an empty
## text leaves a slot empty). Does nothing and returns false for a row that is fixed
## or missing. A link changes the action it follows. The caller has already settled
## any clash (conflicts()). A row whose new keys equal its defaults loses its override.
static func set_keys(mode: String, id: String, keys: Array) -> bool:
	var t := resolve(mode, id)
	var r := row(String(t[0]), String(t[1]))
	if r.is_empty() or bool(r["fixed"]):
		return false
	var slots := [KeyCodes.canonical(String(keys[0])) if keys.size() > 0 else "", KeyCodes.canonical(String(keys[1])) if keys.size() > 1 else ""]
	var key := "%s/%s" % [t[0], t[1]]
	if _same(slots, default_slots(String(t[0]), String(t[1]))):
		_overrides.erase(key)
	else:
		_overrides[key] = slots
	_changed()
	return true


## Put key `key` in slot `slot` (0 or 1) of the row, keeping the other slot.
static func set_slot(mode: String, id: String, slot: int, key: String) -> bool:
	var s := slot_keys(mode, id)
	s[slot] = key
	return set_keys(mode, id, s)


## Like set_keys() for a change that comes from a settings file or a test: it also
## refuses unreadable keys, mouse buttons the page cannot capture, Esc, and any key
## that clashes. Returns true when the keys were taken.
static func try_set(mode: String, id: String, keys: Array) -> bool:
	var r := row(mode, id)
	if r.is_empty() or bool(r["fixed"]) or (String(r["link"]) != "" and is_linked(mode, id)):
		return false
	for k in keys:
		if String(k) == "":
			continue
		var c := KeyCodes.canonical(String(k))
		if c == "" or c == "Esc" or c == "Mouse1" or c == "Mouse2":
			return false
	if not conflicts(mode, id, keys, page_of(mode, id)).is_empty():
		return false
	return set_keys(mode, id, keys)


## Swap: row `id` of `mode` takes key `key` in slot `slot`, and the clashing row
## (`other_mode`, `other_id`) takes the key the first row gave up in the slot where
## it had `key`. Refused (false, nothing changed) when the other key is not in a
## slot, the rows are not rebindable, or the swap would make a new clash.
static func swap(mode: String, id: String, slot: int, key: String, other_mode: String, other_id: String) -> bool:
	var snapshot := _overrides.duplicate(true)
	var a := slot_keys(mode, id)
	var b := slot_keys(other_mode, other_id)
	var j := -1
	for i in range(0, mini(2, b.size())):
		if KeyCodes.canonical(String(b[i])) == KeyCodes.canonical(key):
			j = i
	if j < 0 or bool(row(mode, id).get("fixed", true)) or bool(row(other_mode, other_id).get("fixed", true)):
		return false
	var old: String = a[slot]
	a[slot] = key
	b[j] = old
	var ok := set_keys(mode, id, a) and set_keys(other_mode, other_id, b)
	for pair in [[mode, id], [other_mode, other_id]]:
		if ok and not conflicts(String(pair[0]), String(pair[1]), effective_keys(String(pair[0]), String(pair[1])), page_of(String(pair[0]), String(pair[1]))).filter(func(c: Dictionary) -> bool: return String(c["variant"]) == "").is_empty():
			ok = false
	if not ok:
		_overrides = snapshot
		_changed()
	return ok


## Pick preset `preset_id` of group `group`. The player's changes to every row that group
## lists are cleared (they were made against the old set). Returns false for an unknown
## group or preset.
static func set_preset(group: String, preset_id: String) -> bool:
	var g := preset_group(group)
	if g.is_empty() or not (g["presets"] as Dictionary).has(preset_id):
		return false
	for pid: String in g["presets"]:
		var rows_by_mode: Dictionary = ((g["presets"][pid] as Dictionary).get("rows", {}) as Dictionary)
		for m: String in rows_by_mode:
			for a: String in rows_by_mode[m]:
				_overrides.erase("%s/%s" % [m, a])
	_choice[group] = preset_id
	_changed()
	return true


## Take the player's change off row `id` of `mode` (the row a link follows).
static func reset_row(mode: String, id: String) -> void:
	var t := resolve(mode, id)
	if _overrides.erase("%s/%s" % [t[0], t[1]]):
		_changed()


## Take the player's changes off every row of `mode` (the presets stay).
static func reset_mode(mode: String) -> void:
	for k: String in _overrides.keys():
		if k.begins_with(mode + "/"):
			_overrides.erase(k)
	_changed()


## Back to the defaults everywhere: no changes, every preset group on its default.
static func reset_all() -> void:
	_overrides.clear()
	_choice.clear()
	_changed()


## Like reset_all(), for tests: also forgets how many entries the last load dropped.
static func reset_to_defaults() -> void:
	last_dropped = 0
	reset_all()


# --- the InputMap, the file and the texts -------------------------------------------------

## Make the InputMap actions of the live rows of the shared and flying modes (an action
## that does not exist yet is made), with the events of their keys in order. Run at start
## (GameInputMap.define_all()) and after every change; the actions keep their names.
static func apply_to_input_map() -> void:
	for m: String in ["shared", "flying"]:
		for r: Dictionary in rows(m):
			if not is_live(r) or not bool(r["action"]):
				continue
			var a := StringName(String(r["id"]))
			if not InputMap.has_action(a):
				InputMap.add_action(a)
			InputMap.action_erase_events(a)
			for k in effective_keys(m, String(r["id"])):
				var ev := KeyCodes.make_event(String(k))
				if ev != null:
					InputMap.action_add_event(a, ev)


## Write the player's changes to the settings file (see KeyMapStore).
static func save(path: String = "") -> int:
	return KeyMapStore.save(path)


## Read the player's changes from the settings file (see KeyMapStore).
static func load_from(path: String = "") -> void:
	KeyMapStore.load_from(path)


## Put a changed set into the tables in one go; used by KeyMapStore.load_from().
static func replace_state(over: Dictionary, choice: Dictionary) -> void:
	_overrides = over
	_choice = choice
	_changed()


## The rows of `mode` as the Keys help page shows them (see KeyMapText).
static func help_table(mode: String) -> Array:
	return KeyMapText.help_table(mode)


## The key reminder line for a seat (see KeyMapText).
static func key_line(role: String) -> String:
	return KeyMapText.key_line(role)
