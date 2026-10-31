class_name KeyCodes
extends RefCounted
## WHAT THIS IS: the translator between a key written as text ("A",
## "Shift+QuoteLeft", "Ctrl+F12", "Mouse4") and the thing Godot understands (a
## keyboard or mouse-button event), plus the words the screens show for a key.
##
## HOW IT WORKS: a key text is the modifiers Ctrl, Alt and Shift (always in this order)
## joined by "+" to one key or mouse button. A key is named by its place on the
## keyboard (Godot's "physical" key code, named after a US keyboard), so W A S D
## stay in the same spot on every keyboard layout. Letters, digits and F1 to F12
## are written as they are; the few others have a fixed name (NAMES). Mouse
## buttons are Mouse1 to Mouse5 (left, right, middle, and the two side buttons);
## only 3 to 5 can be chosen on the Controls page, because 1 and 2 are the click.
## canonical() writes any valid text in the one standard form, so two spellings of
## a key compare equal. event_text() goes the other way, for the key a player just
## pressed. display() turns a text into the short form for screens ("QuoteLeft"
## becomes "`").
##
## WHO USES IT: KeyMap and its parts (bindings, storage, the Keys help page), the
## Controls page (capture), and tests/key_map_check.gd.

## The keys that have a name of their own, and the keys the translator writes in
## words: text -> Godot key code.
const NAMES := {
	"Esc": KEY_ESCAPE, "Tab": KEY_TAB, "Space": KEY_SPACE, "Enter": KEY_ENTER, "KPEnter": KEY_KP_ENTER,
	"KPAdd": KEY_KP_ADD, "KPSubtract": KEY_KP_SUBTRACT, "Backspace": KEY_BACKSPACE, "QuoteLeft": KEY_QUOTELEFT,
	"Equal": KEY_EQUAL, "Minus": KEY_MINUS, "Up": KEY_UP, "Down": KEY_DOWN, "Left": KEY_LEFT, "Right": KEY_RIGHT,
	"Shift": KEY_SHIFT, "Ctrl": KEY_CTRL, "Alt": KEY_ALT,
}

## The mouse buttons by text: text -> Godot button index (3 is the middle button,
## 4 and 5 the two side buttons).
const MOUSE := {
	"Mouse1": MOUSE_BUTTON_LEFT, "Mouse2": MOUSE_BUTTON_RIGHT, "Mouse3": MOUSE_BUTTON_MIDDLE,
	"Mouse4": MOUSE_BUTTON_XBUTTON1, "Mouse5": MOUSE_BUTTON_XBUTTON2,
}

## The shorter words screens show for some keys: text -> what is shown.
const SHORT := {
	"QuoteLeft": "`", "Equal": "=", "Minus": "-", "KPAdd": "Num +", "KPSubtract": "Num -", "KPEnter": "Num Enter",
}

## The modifier key codes: pressing one alone is a key of its own (Shift boosts)
## but also the start of a combination (Ctrl+K).
const MODIFIER_CODES := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


## The standard form of key text `text` ("shift+a" becomes "Shift+A"), or "" when
## it is not a key we can bind.
static func canonical(text: String) -> String:
	var p := parse(text)
	if not bool(p["ok"]):
		return ""
	return _write(p)


## Take key text `text` apart: {ok, mouse (true for a mouse button), code (the key
## code or the button index), ctrl, alt, shift}. ok is false for text that is not a
## key.
static func parse(text: String) -> Dictionary:
	var out := {"ok": false, "mouse": false, "code": 0, "ctrl": false, "alt": false, "shift": false}
	var parts := text.strip_edges().split("+", false)
	if parts.is_empty():
		return out
	# The last part is the key; every part before it must be a modifier.
	for i in parts.size() - 1:
		match String(parts[i]).to_lower():
			"ctrl":
				out["ctrl"] = true
			"alt":
				out["alt"] = true
			"shift":
				out["shift"] = true
			_:
				return out
	var last := String(parts[parts.size() - 1])
	for m: String in MOUSE:
		if m.to_lower() == last.to_lower():
			out["mouse"] = true
			out["code"] = MOUSE[m]
			out["ok"] = true
			return out
	var code := _code_of(last)
	if code != 0:
		out["code"] = code
		out["ok"] = true
	return out


## Godot's key code for key name `name`, or 0 when there is none: our fixed
## names first, then letters, digits and F-keys as Godot spells them.
static func _code_of(name: String) -> int:
	for n: String in NAMES:
		if n.to_lower() == name.to_lower():
			return int(NAMES[n])
	if name.length() == 1 or (name.length() >= 2 and name.length() <= 3 and name.to_upper().begins_with("F") and name.substr(1).is_valid_int()):
		return int(OS.find_keycode_from_string(name.to_upper()))
	return 0


## The text of a parsed key (the standard form).
static func _write(p: Dictionary) -> String:
	var s := ""
	for m: Array in [["ctrl", "Ctrl+"], ["alt", "Alt+"], ["shift", "Shift+"]]:
		if bool(p[m[0]]):
			s += String(m[1])
	if bool(p["mouse"]):
		for m: String in MOUSE:
			if int(MOUSE[m]) == int(p["code"]):
				return s + m
		return ""
	return s + _name_of(int(p["code"]))


## The text for key code `code` (see _code_of).
static func _name_of(code: int) -> String:
	for n: String in NAMES:
		if int(NAMES[n]) == code:
			return n
	return OS.get_keycode_string(code as Key)


## A new keyboard or mouse event for key text `text`, as an InputMap action takes
## it, or null when the text is not a key. Keys are matched by place on the keyboard
## (physical_keycode); modifiers are part of the event.
static func make_event(text: String) -> InputEvent:
	var p := parse(text)
	if not bool(p["ok"]):
		return null
	var ev: InputEvent
	if bool(p["mouse"]):
		var mb := InputEventMouseButton.new()
		mb.button_index = int(p["code"]) as MouseButton
		ev = mb
	else:
		var k := InputEventKey.new()
		k.physical_keycode = int(p["code"]) as Key
		ev = k
	var mods := ev as InputEventWithModifiers
	mods.ctrl_pressed = bool(p["ctrl"])
	mods.alt_pressed = bool(p["alt"])
	mods.shift_pressed = bool(p["shift"])
	return ev


## The key text for the key or mouse button `ev` is pressing, or "" when it cannot be
## a binding: a key let go, a lone modifier (see MODIFIER_CODES), the left and right
## mouse buttons (they are the click), the wheel, or an unnamed key.
static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed:
			return ""
		var code := int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		if code == 0 or MODIFIER_CODES.has(code):
			return ""
		return _write({"ok": true, "mouse": false, "code": code, "ctrl": k.ctrl_pressed, "alt": k.alt_pressed, "shift": k.shift_pressed})
	if ev is InputEventMouseButton:
		var m := ev as InputEventMouseButton
		var b := int(m.button_index)
		if not m.pressed or (b != MOUSE_BUTTON_MIDDLE and b != MOUSE_BUTTON_XBUTTON1 and b != MOUSE_BUTTON_XBUTTON2):
			return ""
		return _write({"ok": true, "mouse": true, "code": b, "ctrl": m.ctrl_pressed, "alt": m.alt_pressed, "shift": m.shift_pressed})
	return ""


## The text of a lone modifier key `ev` that was just let go ("Shift"), or "" when
## `ev` is not one. The page uses it so Shift alone can be a binding while Ctrl+K
## can still be typed.
static func modifier_release_text(ev: InputEvent) -> String:
	if ev is InputEventKey and not (ev as InputEventKey).pressed:
		var k := ev as InputEventKey
		var code := int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		if MODIFIER_CODES.has(code) and code != KEY_META:
			return _name_of(code)
	return ""


## The short form of key text `text` for screens: "Shift+`" for "Shift+QuoteLeft", "" for "".
static func display(text: String) -> String:
	if text == "":
		return ""
	var parts := text.split("+", false)
	var out := PackedStringArray()
	for p in parts:
		out.append(String(SHORT.get(String(p), String(p))))
	return "+".join(out)
