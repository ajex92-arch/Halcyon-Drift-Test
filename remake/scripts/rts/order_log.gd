class_name OrderLog
extends RefCounted
## WHAT THIS IS: the match log. A plain text file with the match's header, one line
## for every order carried out or refused (who sent it, which tick), and a
## fingerprint of the game every 300 ticks (5 seconds). Playing the orders back
## into the same seed must reproduce every fingerprint: that is how a replay proves
## itself, and what online play, saved games and bug reports will stand on.
##
## HOW IT WORKS: the lines are plain UTF-8 text, words separated by single spaces:
##   log v1 seed=<n> preset=<name> variants=<json> role=<role> team=<n> rocks=<n> nodes=<n>
##       camps=<n> route_nodes=<n> wings=<off or hull,hull,hull> cwings=<0 or 1> fp0=<units>,<hash8> [build=<text>]
##   (wings= is the wing the human's seat gets, cwings= is 1 when the computer pilots' seats get one: Squads)
##   o <apply_tick> <team> <seat> <h|a|t> <id> <KIND> <json> <ok or reason code>   (see Order)
##   h <tick> <units> <hash8>      the fingerprint at the top of that tick, every 300 ticks
##   end <tick> <units> <hash8>    the last line, written once
## (A "c" line for a human pilot's flight controls is defined in docs/RTS_ORDERS.md and is
## written by the recorder that owns it.) The header holds only the seed, the options,
## the map's counts and a fingerprint: nothing about the computer or the player.
## It is written at the first tick, so the fingerprint `fp0` sees everything setup, a
## late-game start and a test have done. Lines are kept in memory and written once a minute
## of game time (FLUSH_EVERY ticks), at the end and when the world leaves the tree. The web
## build writes no log. fingerprint() is a copy of the one in tests/det_hash.gd, so that the
## two agree line for line; game code does not load files from tests/.
##
## WHO USES IT: OrderQueue opens one (--order-log) and calls header(), record(),
## hash_line() and close(); the replay reads one with read(); tests/order_check.gd and
## tests/order_replay.gd check it.

## How many ticks of lines are kept in memory before they are written (a minute).
const FLUSH_EVERY := 3600

## Where the log goes.
var path := ""
## The match.
var world: World
## The open file, or null when none is open.
var _file: FileAccess = null
## Lines waiting to be written.
var _buf := PackedStringArray()
## Order lines that came before the first tick (a speed change in setup): they go in
## right after the header, which is always the first line.
var _early := PackedStringArray()
## True once the header line is in.
var header_written := false
## True once the end line is in; nothing is written after it.
var closed := false
## The tick of the last write to the file.
var _last_flush := 0


## Open `file_path` for writing (a path starting "user://" or a full path). Returns
## false, and writes nothing, in the web build or when the file cannot be made.
func open(file_path: String, w: World) -> bool:
	world = w
	if OS.has_feature("web"):
		return false
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_warning("order log: cannot write %s" % file_path)
		return false
	path = file_path
	return true


## Is the log open for writing?
func is_open() -> bool:
	return _file != null and not closed


## The header line for the match `w` is in now. The same text is worked out by a
## replay to compare with the file's header. `--build=<text>` is added last when given.
static func make_header(w: World) -> String:
	var seed_opt: Variant = Game.opt("seed")
	var parts := PackedStringArray([
		"log", "v1",
		"seed=%s" % (str(int(seed_opt)) if seed_opt != null else "none"),
		"preset=%s" % Game.preset,
		"variants=%s" % JSON.stringify(Game.variants, "", true),
		"role=%s" % w.human_role, "team=%d" % w.human_team,
		"rocks=%d" % w.asteroids.pos.size(), "nodes=%d" % w.nodes.size(),
		"camps=%d" % w.map.camps.size(), "route_nodes=%d" % w.map.route.node_count(),
		"wings=%s" % Squads.wings_text(), "cwings=%d" % Squads.cwings_flag(),
		"fp0=%s" % fingerprint_pair(w),
	])
	var build: Variant = Game.opt("build")
	if build is String and (build as String) != "":
		parts.append("build=%s" % (build as String).replace(" ", "_"))
	return " ".join(parts)


## Write the header line (once, at the first tick).
func header() -> void:
	if header_written or not is_open():
		return
	header_written = true
	_buf.append(make_header(world))
	_buf.append_array(_early)
	_early.clear()


## Add the line for order `o` and its result `code` ("ok" or a reason code).
func record(o: Dictionary, code: String) -> void:
	if not is_open():
		return
	if header_written:
		_buf.append(Order.to_line(o, code))
	else:
		_early.append(Order.to_line(o, code))


## Add the fingerprint line for the top of tick `tick`.
func hash_line(tick: int) -> void:
	if not is_open():
		return
	_buf.append("h %d %s" % [tick, fingerprint_pair(world).replace(",", " ")])
	if tick - _last_flush >= FLUSH_EVERY:
		flush()
		_last_flush = tick


## Write the end line (once: the first call wins) and close the file.
func close(w: World) -> void:
	if not is_open():
		return
	_buf.append("end %d %s" % [w.tick_count, fingerprint_pair(w).replace(",", " ")])
	flush()
	closed = true
	_file.close()
	_file = null


## Write the lines waiting in memory.
func flush() -> void:
	if _file == null or _buf.is_empty():
		return
	_file.store_string("\n".join(_buf) + "\n")
	_file.flush()
	_buf.clear()


## One string that changes if anything about the match changes: every live unit's
## kind, team, position and hull (rounded), every pilot's credits and state, both
## treasuries and the projectile count, hashed. The same text as the det_hash test's.
static func fingerprint(w: World) -> String:
	var parts := PackedStringArray()
	# Every live unit: "kind:team:x,y:hull" (whole numbers).
	for u: Unit in w.units:
		if u.alive:
			parts.append("%d:%d:%d,%d:%d" % [u.kind, u.team, roundi(u.global_position.x), roundi(u.global_position.y), roundi(u.hull)])
	# Every pilot: "callsign:credits:state".
	for p: PilotProfile in w.profiles:
		parts.append("%s:%d:%s" % [p.callsign, roundi(p.credits), p.state])
	# Both treasuries, and how many shots are in flight.
	for t in 2:
		parts.append("tr%d:%d" % [t, roundi(w.teams[t].treasury)])
	parts.append("proj:%d" % w.projectiles.count())
	# Join it all into one long text and hash it (%08x = 8 hex digits).
	var s := "|".join(parts)
	return "%d units, %08x" % [w.units.size(), hash(s)]


## The fingerprint as "<units>,<hash8>" (the form the header's fp0 and the lines use).
static func fingerprint_pair(w: World) -> String:
	var fp := fingerprint(w)
	return "%s,%s" % [fp.get_slice(" ", 0), fp.get_slice(", ", 1)]


## Read a log file. Returns {"header": the header line, "head": its key=value words as a
## Dictionary, "orders": the order records in file order, "results": their result words,
## "hashes": tick -> "<units> <hash8>", "end": the end line's "<tick> <units> <hash8>" or ""}.
## An unreadable file gives an empty header.
static func read(file_path: String) -> Dictionary:
	var out := {"header": "", "head": {}, "orders": [], "results": [], "hashes": {}, "end": ""}
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("log "):
			out["header"] = line
			var head := {}
			for word in line.split(" ", false):
				var eq := word.find("=")
				if eq > 0:
					head[word.substr(0, eq)] = word.substr(eq + 1)
			out["head"] = head
		elif line.begins_with("o "):
			var o := Order.from_line(line)
			if not o.is_empty():
				(out["orders"] as Array).append(o)
				(out["results"] as Array).append(Order.result_of(line))
		elif line.begins_with("h "):
			var w := line.split(" ", false)
			if w.size() >= 4:
				(out["hashes"] as Dictionary)[int(w[1])] = "%s %s" % [w[2], w[3]]
		elif line.begins_with("end "):
			out["end"] = line.substr(4)
	return out
