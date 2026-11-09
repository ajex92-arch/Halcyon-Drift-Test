class_name HumanLines
extends RefCounted
## WHAT THIS IS: the text of the two kinds of lines the match recorder adds to the match log
## for the human at the keyboard: `c`, what a human pilot's ship was told to do on one tick
## (the flight controls), and `b`, a command the human gave on a screen (a hangar buy, a
## launch). It writes them and reads them back, nothing else; OrderLog stores the lines and
## ReplayPlayer plays them.
##
## HOW IT WORKS: the words of a line are separated by single spaces.
##   c <tick> <seat> <aim x> <aim y> <face x> <face y> <forward> <strafe> <flags> <focus> <energy>
## The aim and face points are in world units, written so that reading them back gives the
## very same number (a replay must fly exactly the course the player flew, so nothing is
## rounded); the face point is written "=" when it equals the aim point. `forward` and `strafe`
## are the stick values, `flags` is a number that adds up boost 1, fire 2, special 4,
## cancel_run 8, use_kit 16, dock 32 and assist 64, `focus` and `energy` are the shield focus
## and energy routing asked for (-1 for no change). The line holds what the ship's controls
## were at the END of PlayerController.update() on that tick, which is what the tick used.
##   b <tick> <seat> <command> <json list of arguments> <ok or refused>
## `tick` is the World's tick count when the command was given (the number of ticks taken so
## far). The commands are the words of HumanCmd.
##
## WHO USES IT: OrderLog (it writes the lines), ReplayPlayer (it reads them back), PlayerController
## and HumanCmd (through OrderQueue); tests/record_check.gd checks the round trip.

## The flag bits of a `c` line: boost.
const F_BOOST := 1
## Flag bit: the guns are firing.
const F_FIRE := 2
## Flag bit: the special ability (an edge: one tick).
const F_SPECIAL := 4
## Flag bit: cancel the torpedo run (an edge).
const F_CANCEL_RUN := 8
## Flag bit: use a repair kit (an edge).
const F_KIT := 16
## Flag bit: dock at the mothership (an edge).
const F_DOCK := 32
## Flag bit: flight assist is on.
const F_ASSIST := 64


## A number as the shortest plain decimal text that reads back as exactly the same number.
## `single` is true for a 32-bit number (a Vector2 coordinate), false for a 64-bit one.
static func num(x: float, single: bool) -> String:
	if x == 0.0:
		return "0"
	if x == floorf(x) and absf(x) < 1.0e9:
		return str(int(x))
	for decimals in range(1, 18):
		var s := _trim(String.num(x, decimals))
		if _reads_back(s, x, single):
			return s
	# A 64-bit number the engine's reader cannot give back from any decimal (its reader is not
	# exact for every 64-bit decimal): write its 64 bits, "x" and 16 hex digits.
	var bytes := PackedFloat64Array([x]).to_byte_array()
	return "x%08x%08x" % [bytes.decode_u32(4), bytes.decode_u32(0)]


## The number that text `s` (made by num()) stands for.
static func read_num(s: String) -> float:
	if s.begins_with("x") and s.length() == 17:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_u32(4, ("0x" + s.substr(1, 8)).hex_to_int())
		bytes.encode_u32(0, ("0x" + s.substr(9, 8)).hex_to_int())
		return bytes.decode_double(0)
	return s.to_float()


## Is text `s` the number `x` once it is read back as a 32-bit or 64-bit number?
static func _reads_back(s: String, x: float, single: bool) -> bool:
	var back := s.to_float()
	if single:
		return Vector2(back, 0.0).x == x
	return back == x


## `s` without the zeros at the end of its decimals (and without a lone point).
static func _trim(s: String) -> String:
	if not s.contains("."):
		return s
	var end := s.length()
	while end > 0 and s[end - 1] == "0":
		end -= 1
	if end > 0 and s[end - 1] == ".":
		end -= 1
	return s.substr(0, end)


## The flag number of controls `c`.
static func flags_of(c: ShipControls) -> int:
	var f := 0
	if c.boost:
		f |= F_BOOST
	if c.fire:
		f |= F_FIRE
	if c.special:
		f |= F_SPECIAL
	if c.cancel_run:
		f |= F_CANCEL_RUN
	if c.use_kit:
		f |= F_KIT
	if c.dock:
		f |= F_DOCK
	if c.assist:
		f |= F_ASSIST
	return f


## The part of a `c` line after the seat, for controls `c`: what has to change for a new line
## to be written.
static func controls_body(c: ShipControls) -> String:
	var face := "=" if c.face_point == c.aim_point else "%s %s" % [num(c.face_point.x, true), num(c.face_point.y, true)]
	return "%s %s %s %s %s %d %d %d" % [num(c.aim_point.x, true), num(c.aim_point.y, true), face,
		num(c.forward, false), num(c.strafe, false), flags_of(c), c.focus_request, c.energy_request]


## Read the part of a `c` line after the seat (the text controls_body() made). Returns
## {aim, face, forward, strafe, flags, focus, energy}, or {} when it cannot be read.
static func parse_controls(body: String) -> Dictionary:
	var w := body.split(" ", false)
	if w.size() < 7:
		return {}
	var aim := Vector2(w[0].to_float(), w[1].to_float())
	var i := 2
	var face := aim
	if w[i] == "=":
		i += 1
	else:
		face = Vector2(w[i].to_float(), w[i + 1].to_float())
		i += 2
	if w.size() < i + 5:
		return {}
	return {
		"aim": aim, "face": face, "forward": read_num(w[i]), "strafe": read_num(w[i + 1]),
		"flags": int(w[i + 2]), "focus": int(w[i + 3]), "energy": int(w[i + 4]),
	}


## Put a parsed `c` line `vec` (see parse_controls) into controls `c`.
static func apply_controls(vec: Dictionary, c: ShipControls) -> void:
	var f := int(vec["flags"])
	c.aim_point = vec["aim"]
	c.face_point = vec["face"]
	c.forward = float(vec["forward"])
	c.strafe = float(vec["strafe"])
	c.boost = f & F_BOOST != 0
	c.fire = f & F_FIRE != 0
	c.special = f & F_SPECIAL != 0
	c.cancel_run = f & F_CANCEL_RUN != 0
	c.use_kit = f & F_KIT != 0
	c.dock = f & F_DOCK != 0
	c.assist = f & F_ASSIST != 0
	c.focus_request = int(vec["focus"])
	c.energy_request = int(vec["energy"])


## The `b` line of command `kind` with `args` (a list of whole numbers and short words) given
## on tick `tick` by `seat`, and its result word `result` ("ok" or "refused").
static func command_line(tick: int, seat: int, kind: String, args: Array, result: String) -> String:
	return "b %d %d %s %s %s" % [tick, seat, kind, JSON.stringify(args, "", false), result]


## Read a `b` line. Returns {tick, seat, kind, args, result}, or {} when it is not one.
static func parse_command(line: String) -> Dictionary:
	var w := line.split(" ", false, 5)
	if w.size() < 6 or w[0] != "b":
		return {}
	var args = JSON.parse_string(w[4])
	if typeof(args) != TYPE_ARRAY:
		return {}
	# The reader gives every number as a float: a whole number is an int again, as it was given.
	var back: Array = []
	for a in args:
		back.append(int(a) if typeof(a) == TYPE_FLOAT and a == floorf(a) else a)
	return {"tick": int(w[1]), "seat": int(w[2]), "kind": w[3], "args": back, "result": w[5]}
