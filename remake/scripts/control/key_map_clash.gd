class_name KeyMapClash
extends RefCounted
## WHAT THIS IS: the "is this key already taken?" part of the key map. It names every
## action that already uses a key a player wants to give another action, and every
## rule variant that reads the same key straight from the keyboard.
##
## HOW IT WORKS: two rows clash when they have the same key text in the same mode (the
## Shared group counts in every mode), on the same page of the command card or when
## either row has no page. A Shared row is checked against the rows of every mode. A link
## row (the camera keys follow the pilot's movement keys) is checked together with
## everything it follows and everything that follows it. A rule variant counts only
## while it is on (variant_on), because its key is then really read by that feature.
## mode_clashes() checks a whole mode as it stands, which the Controls page does when it
## opens and the settings file reader does after reading.
##
## WHO USES IT: KeyMap forwards conflicts(), mode_clashes(), variant_hits() and
## variant_on(); KeyMapStore, the Controls page and tests/key_map_check.gd call it
## through KeyMap.

## Keys that other features read straight from the keyboard when their rule variant is
## on: the key, the variant, how to name it, and the modes it works in (empty: all).
const VARIANT_KEYS := [
	{"key": "T", "variant": "recall", "label": "the recall variant", "modes": ["flying", "flying_board"]},
	{"key": "M", "variant": "mutiny", "label": "the mutiny variant", "modes": ["flying", "flying_board"]},
	{"key": "F10", "variant": "surrender", "label": "the surrender vote", "modes": []},
	{"key": "F11", "variant": "surrender", "label": "the surrender vote", "modes": []},
]

# --- clashes ---------------------------------------------------------------------------

## The rows a change to row `id` of `mode` edits: [[mode, id], ...], the row it
## resolves to first, then every row that follows it.
static func _edit_pairs(mode: String, id: String) -> Array:
	var t := KeyMap.resolve(mode, id)
	var pairs := [t]
	for m: String in KeyMapData.MODES:
		for r: Dictionary in KeyMap.rows(m):
			if String(r["link"]) == String(t[1]) and t[0] == "flying" and KeyMap.is_linked(m, String(r["id"])):
				pairs.append([m, String(r["id"])])
	return pairs


## Is rule variant `variant` on in the standard rules or either preset, or (with
## `launch`) in this run's rules?
static func variant_on(variant: String, launch: bool = true) -> bool:
	if String(Rules.VARIANT_DEFAULTS.get(variant, "off")) != "off":
		return true
	for p: String in CouncilPresets.VARIANTS:
		for pair in String(CouncilPresets.VARIANTS[p]).split(",", false):
			if String(pair).begins_with(variant + ":") and String(pair).get_slice(":", 1) != "off":
				return true
	return launch and not ["off", ""].has(Game.variant(variant))


## The keys read straight from the keyboard by a rule variant that clash with the key
## texts in `keys` in `mode`: [{key, variant, label, on}]. `on` says whether the
## variant is on (the Controls page only warns about those; the key check lists all).
static func variant_hits(mode: String, keys: Array) -> Array:
	var out := []
	var want := {}
	for k in keys:
		want[KeyCodes.canonical(String(k))] = true
	for v: Dictionary in VARIANT_KEYS:
		var modes: Array = v["modes"]
		if want.has(v["key"]) and (modes.is_empty() or modes.has(mode) or mode == "shared"):
			out.append({"key": v["key"], "variant": v["variant"], "label": v["label"], "on": variant_on(String(v["variant"]))})
	return out


## Every action that already has one of the key texts in `keys` where a change to
## row `id` of `mode` would use it. `page` is the row's command card page. Returns
## [{mode, action, label, fixed, variant}]: the actions, Shared ones and a rule
## variant that is on included ("variant" is "" for an action). A Shared row clashes
## with the rows of every mode; any other row with its own mode and the Shared rows.
static func conflicts(mode: String, id: String, keys: Array, page: String = "") -> Array:
	var want := {}
	for k in keys:
		var c := KeyCodes.canonical(String(k))
		if c != "":
			want[c] = true
	var out := []
	if want.is_empty():
		return out
	var pairs := _edit_pairs(mode, id)
	var seen := {}
	for pair: Array in pairs:
		seen["%s/%s" % [pair[0], pair[1]]] = true
	for pair: Array in pairs:
		var pg := page if (pair[0] == mode and pair[1] == id) else KeyMap.page_of(String(pair[0]), String(pair[1]))
		var scope: Array = ["home", "flying", "flying_board"] if pair[0] == "shared" else [pair[0]]
		for s: String in scope:
			for r: Dictionary in KeyMap.rows_in_force(s):
				var rk := "%s/%s" % [r["mode"], r["id"]]
				if seen.has(rk):
					continue
				var rp := KeyMap.page_of(String(r["mode"]), String(r["id"]))
				if pg != "" and rp != "" and pg != rp:
					continue
				for k in KeyMap.effective_keys(String(r["mode"]), String(r["id"])):
					if want.has(k):
						seen[rk] = true
						out.append({"mode": r["mode"], "action": r["id"], "label": r["label"], "fixed": bool(r["fixed"]), "variant": ""})
						break
	for h: Dictionary in variant_hits(String(pairs[0][0]) if String(pairs[0][0]) != "shared" else "flying", keys):
		if bool(h["on"]):
			out.append({"mode": "", "action": h["variant"], "label": h["label"], "fixed": true, "variant": h["variant"]})
	return out


## The clashes inside `mode` as it stands: [{mode, action, label, others}] for each
## row that shares a key with another (the page checks the whole mode when it
## opens). Empty when all is well.
static func mode_clashes(mode: String) -> Array:
	var out := []
	for r: Dictionary in KeyMap.rows_in_force(mode):
		var found := conflicts(String(r["mode"]), String(r["id"]), KeyMap.effective_keys(String(r["mode"]), String(r["id"])), KeyMap.page_of(String(r["mode"]), String(r["id"])))
		found = found.filter(func(c: Dictionary) -> bool: return String(c["variant"]) == "")
		if not found.is_empty():
			out.append({"mode": r["mode"], "action": r["id"], "label": r["label"], "others": found})
	return out


