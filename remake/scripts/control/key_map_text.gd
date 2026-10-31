class_name KeyMapText
extends RefCounted
## WHAT THIS IS: the words about keys that other screens print, made from the key list so
## they follow every change: the table of the "Keys" page of the help, and the one-line
## key reminder at the bottom left of the HUD.
##
## HOW IT WORKS: help_table() turns the rows of one mode into display rows (name, first
## key, second key, and for a row that does not work yet, what it comes with). help_text()
## writes all four modes as plain text; the test builds it twice to prove it does not
## depend on anything but the list. key_line() fills a template with the first key of each
## action: with the standard keys the three lines (Admiral, pilot, spectator) read exactly
## as the hand-written reminders did. Lines are kept until KeyMap.version changes, because
## the HUD asks ten times a second.
##
## WHO USES IT: KeyMap forwards help_table() and key_line(); HelpPanel draws the table; HudSlots
## shows the key line; Hud builds two hints with first_key(); tests/key_map_check.gd.

## The reminder pieces of a seat: [action, words]. The key comes first: "Tab Admiral board".
const ADMIRAL_PIECES := [["admiral_board", "Admiral board"], ["hangar", "hangar"], ["center_camera", "camera"], ["center_on_ship", "center camera (hold to follow)"]]
## The pilot's reminder pieces (see ADMIRAL_PIECES); the last one, the scoreboard, is
## written "hold Tab scores".
const PILOT_PIECES := [["hangar", "hangar"], ["dock", "dock/launch"], ["use_kit", "repair kit"], ["center_on_ship", "center camera (hold to follow)"], ["admiral_board", "hold %s scores"]]
## The pieces every seat ends with.
const COMMON_PIECES := [["help", "help"], ["pause", "pause"], ["note", "note"]]

## The lines made so far, by seat, and the key map version they were made for.
static var _lines := {}
static var _lines_version := -1


## The mode in which action `action` lives for the live keys: "shared" or "flying".
static func _mode_of(action: String) -> String:
	return "shared" if not KeyMap.row("shared", action).is_empty() else "flying"


## The first key of action `action` as screens show it, or "none" when it is unbound.
static func key_of(action: String) -> String:
	var k := KeyMap.first_key(_mode_of(action), action)
	return k if k != "" else "none"


## One piece of a reminder: "<key> <words>", or "hold <key> scores" for the scoreboard.
static func _piece(p: Array) -> String:
	if String(p[1]).contains("%s"):
		return String(p[1]) % key_of(String(p[0]))
	return "%s %s" % [key_of(String(p[0])), p[1]]


## The key reminder for seat `role` ("admiral", "pilot" or "spectator").
static func key_line(role: String) -> String:
	if _lines_version != KeyMap.version:
		_lines.clear()
		_lines_version = KeyMap.version
	if _lines.has(role):
		return _lines[role]
	var pieces := PackedStringArray()
	var list: Array = ADMIRAL_PIECES if role == "admiral" else (PILOT_PIECES if role == "pilot" else [])
	for p: Array in list + COMMON_PIECES:
		pieces.append(_piece(p))
	var line := " · ".join(pieces)
	_lines[role] = line
	return line


## The rows of `mode` for the Keys page: [{label, key1, key2, more, comes, live, note}], keys in
## the short form, `more` any keys after the first two, `comes` what a row that is not live yet
## comes with.
static func help_table(mode: String) -> Array:
	var out := []
	for r: Dictionary in KeyMap.visible_rows(mode):
		var k := KeyMap.slot_keys(mode, String(r["id"]))
		var more := PackedStringArray()
		for i in range(2, k.size()):
			more.append(KeyCodes.display(String(k[i])))
		var live := KeyMap.is_live(r)
		out.append({
			"label": String(r["label"]), "key1": KeyCodes.display(String(k[0])), "key2": KeyCodes.display(String(k[1])),
			"more": ", ".join(more), "live": live,
			"comes": "" if live else "comes with " + String(KeyMapData.COMES_WITH.get(String(r["since"]), "a later stage")),
			"note": String(r["note"]),
		})
	return out


## The whole Keys page as plain text, one block per mode: "== Home ==" and a line per row.
## The test builds it twice (and after a reset) and compares.
static func help_text() -> String:
	var lines := PackedStringArray()
	for m: String in KeyMapData.MODES:
		lines.append("== %s ==" % KeyMapData.MODE_LABELS[m])
		for t: Dictionary in help_table(m):
			lines.append("%s | %s | %s | %s | %s" % [t["label"], t["key1"], t["key2"], t["more"], t["comes"]])
	return "\n".join(lines)
