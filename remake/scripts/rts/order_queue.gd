class_name OrderQueue
extends RefCounted
## WHAT THIS IS: the desk every order passes through. A human Admiral's screen
## hands it an order record (Order); it checks what the game can know at once, and
## carries the order out at the start of the next tick (a sixtieth of a second later).
## The computer Admiral keeps carrying its orders out at once, inside its own
## thinking. Both end in the same place, which logs the order, counts it and files it in
## the event stream.
##
## HOW IT WORKS: submit() stamps the record (tick, number), runs the "at once" checks
## (OrderChecks.at_once): a refusal comes back as text straight away, even while the game
## is paused, and nothing is queued or logged. Otherwise the record waits in `queue`, kept
## in the order (apply_tick, seat, id). While the game is paused no tick runs, so the
## order is carried out on the first tick after the game resumes. A game speed change
## (GAME_SPEED) is the exception: it is applied the moment it is submitted. At the top of
## every tick World calls run_due(): it writes the fingerprint line every 300 ticks, lets
## a replay put its orders in, then carries out every record that is due with apply(). apply()
## checks again, then either calls the AdmiralCommand function for today's kinds
## (AdmiralCommand sets `pending` to the record so the function acts on it and logs it) or
## the handler that a later stage registered for the kind. A kind without either is refused
## "unbuilt". log_and_count() is the one place that writes the log line, counts the order and
## files order_done or order_refused. The match log and the two replays are described in
## OrderLog and ReplayPlayer.
## The numbers: INPUT_DELAY is 1 tick. `AI_THROUGH_QUEUE` is the switch that, once on, makes
## the computer Admiral's orders queue like a human's; it is off, and a test turns it on.
##
## WHO USES IT: World keeps one (World.orders) and calls run_due() each tick; WorldSetup makes
## it; the Admiral's screens call submit(); AdmiralCommand calls log_and_count(), take_id()
## and count_submitted(); later stages fill `handlers` and `checkers`; main_report prints
## counters(); tests/order_check.gd and tests/order_replay.gd check it.

## Ticks between a screen submitting an order and the game carrying it out.
const INPUT_DELAY := Order.INPUT_DELAY
## Ticks between two fingerprint lines in the match log.
const HASH_EVERY := 300
## When true, the computer Admiral's direct orders queue for the next tick like a human's.
## Off: the computer's orders are carried out at once inside its think, as in all play today.
static var AI_THROUGH_QUEUE := false

## The game world.
var world: World
## The orders waiting, sorted by (apply_tick, seat, id).
var queue: Array = []
## The number the next order gets (one counter for both teams and all doors).
var next_id := 1
## Kind -> Callable(record) -> String for kinds a later stage carries out: returns ""
## when it worked, or the reason text. Filled by the stage that builds the kind.
var handlers := {}
## Kind -> Callable(record) -> String run in both checking tiers: "" or a refusal text.
var checkers := {}
## A test sets this (0 or more) to pretend the match has that many human seats.
var human_seats_override := -1
## The open match log, or null.
var log: OrderLog = null
## The log being played back (--replay: the human's orders; --admiral-replay: the computer's).
var replay: ReplayPlayer = null
## True while replay 1 plays a human's orders: a screen's submit is refused.
var replaying := false
## True while replay 2 plays the computer's orders in place of its thinking.
var replaying_ai := false
## How many orders have been carried out (counted ok), for the second fingerprint line.
var applied := 0
## The last record submit() was given, whether it was accepted or not (a test reads it
## to see exactly what a screen sent).
var last_submitted: Dictionary = {}
## Counters: "t0" / "t1" -> kind -> {"submitted", "ok", "refused": {code: n}}.
var _counts := {}
## True once the first tick has started (the header and the replay's header check).
var _started := false
## True once close() has run.
var _closed := false


## Remember the world. Teams do not exist yet, so nothing else is touched.
func _init(w: World) -> void:
	world = w


## Read the launch options --order-log, --replay and --admiral-replay (WorldSetup calls
## this once the match is built). The header itself waits for the first tick.
func configure() -> void:
	var out: Variant = Game.opt("order-log")
	if out != null:
		var path: String = out if out is String and (out as String) != "" else "user://orders_%s.log" % str(Game.opt("seed", "x"))
		log = OrderLog.new()
		if not log.open(path, world):
			log = null
	var human_file: Variant = Game.opt("replay")
	var ai_file: Variant = Game.opt("admiral-replay")
	if human_file is String or ai_file is String:
		var player := ReplayPlayer.new()
		var as_computer := not (human_file is String)
		if player.start(str(human_file if human_file is String else ai_file), as_computer):
			replay = player
			replaying = not as_computer
			replaying_ai = as_computer
	if log != null or replay != null:
		Events.match_over.connect(_on_match_over)
		world.tree_exiting.connect(_leave)


## Submit a screen's order. Returns "" when it was accepted (queued, or for the game speed
## applied), else the reason text. The record is stamped here: `tick` is the last tick
## taken, `apply_tick` the next, `id` a new number (0 for a refused order).
func submit(o: Dictionary) -> String:
	o["tick"] = world.tick_count
	o["apply_tick"] = world.tick_count + INPUT_DELAY
	o["id"] = 0
	last_submitted = o
	count_submitted(o)
	var msg := OrderChecks.at_once(world, self, o)
	if msg != "":
		_refuse_at_submit(o, msg)
		return msg
	o["id"] = take_id()
	if OrderKinds.AT_ONCE.has(str(o["kind"])):
		o["apply_tick"] = world.tick_count
		return _apply_speed(o)
	_insert(o)
	return ""


## Carry out an order on this very tick (the computer pilots' door). Runs the "at once"
## checks, then apply(). Returns "" or the reason.
func apply_now(o: Dictionary) -> String:
	o["tick"] = world.tick_count
	o["apply_tick"] = world.tick_count
	o["id"] = 0
	count_submitted(o)
	var msg := OrderChecks.at_once(world, self, o)
	if msg != "":
		_refuse_at_submit(o, msg)
		return msg
	o["id"] = take_id()
	return apply(o)


## Top of the World's tick (step 1a): the fingerprint line, the replay's orders, then every
## order that is due, in stored order.
func run_due() -> void:
	var tc := world.tick_count
	if not _started:
		_started = true
		if log != null:
			log.header()
		if replay != null and not replay.check_header(world):
			world.get_tree().quit()
			return
	if tc % HASH_EVERY == 0 and (log != null or replay != null):
		if log != null:
			log.hash_line(tc)
		if replay != null:
			replay.compare(tc, OrderLog.fingerprint_pair(world))
	if replaying:
		for o: Dictionary in replay.due(tc):
			count_submitted(o)
			_insert(o)
	while not queue.is_empty() and int((queue[0] as Dictionary)["apply_tick"]) <= tc:
		apply(queue.pop_front())


## Replay 2: the computer Admirals' logged orders for this tick, in the logged order,
## carried out in place of the Admirals' thinking. Called once a tick (for team 0) where
## the Admirals would think; it plays both teams' lines.
func replay_ai(_team: int) -> void:
	if replay == null:
		return
	for o: Dictionary in replay.due(world.tick_count):
		count_submitted(o)
		apply(o)


## Carry out record `o` now: check it again, then run its applier. Returns "" or the reason.
func apply(o: Dictionary) -> String:
	var msg := ""
	if int(o["apply_tick"]) < world.tick_count:
		msg = OrderKinds.TEXT_LATE
	else:
		msg = OrderChecks.recheck(world, self, o)
	if msg != "":
		report(o, msg)
		return msg
	var kind := str(o["kind"])
	var cmd := world.command
	if OrderKinds.BUILT_IN.has(kind):
		cmd.pending = o
		msg = OrderApply.call_built_in(world, o)
		cmd.pending = {}
	elif handlers.has(kind):
		cmd.pending = o
		msg = str((handlers[kind] as Callable).call(o))
		cmd.pending = {}
		report(o, msg)
	else:
		msg = OrderKinds.TEXT_UNBUILT
		report(o, msg)
	return msg


## The end of every order: log it, count it, file order_done / order_refused, and
## tell the screens (Events.admiral_result) unless the kind sends no toast word.
func report(o: Dictionary, msg: String) -> void:
	log_and_count(o, msg)
	var word := OrderKinds.action_word(str(o["kind"]), int(o["seat"]))
	if word != "none":
		Events.admiral_result.emit(int(o["team"]), word, msg == "", msg)


## Log the order `o` with its result text `msg` (one line), count it, and file the
## event. The one place that does this for an order that was carried out or refused
## at apply.
func log_and_count(o: Dictionary, msg: String) -> void:
	var code := OrderKinds.reason_code(msg)
	_bump(o, code)
	if code == "ok":
		applied += 1
	if log != null:
		log.record(o, code)
	OrderApply.file_event(world, o, code, "apply")


## The next order number.
func take_id() -> int:
	var n := next_id
	next_id += 1
	return n


## Count order `o` as submitted (once per order).
func count_submitted(o: Dictionary) -> void:
	var row := _row(o)
	row["submitted"] = int(row["submitted"]) + 1


## How many human seats the match has: 1 when a human plays, else 0 (a test may set it).
func human_seats() -> int:
	if human_seats_override >= 0:
		return human_seats_override
	return 1 if world.human != null else 0


## Does anything carry out orders of `kind`? The Admiral's kinds, the game speed, or a
## registered handler.
func has_applier(kind: String) -> bool:
	return OrderKinds.BUILT_IN.has(kind) or kind == OrderKinds.GAME_SPEED or handlers.has(kind)


## The unit with id `uid`, or null if it is gone (never made, dead, or freed).
func unit_by_uid(uid: int) -> Unit:
	var u: Variant = world.by_uid.get(uid)
	if u == null or not is_instance_valid(u) or not (u as Unit).alive:
		return null
	return u as Unit


## The counters as a Dictionary: "t0" / "t1" -> kind -> {"submitted": n, "ok": n,
## "refused": {code: n}}.
func counters() -> Dictionary:
	return _counts.duplicate(true)


## Write the waiting log lines to the file.
func flush() -> void:
	if log != null:
		log.flush()


## The match is over (or the test is): write the end line once (the first call wins) and
## close the log; a replay prints its closing lines.
func close(w: World) -> void:
	if _closed:
		return
	_closed = true
	if log != null:
		log.close(w)
	if replay != null:
		replay.finish(w.tick_count, OrderLog.fingerprint_pair(w))


## Put record `o` into the queue, keeping (apply_tick, seat, id) order.
func _insert(o: Dictionary) -> void:
	var i := queue.size()
	while i > 0 and _before(o, queue[i - 1]):
		i -= 1
	queue.insert(i, o)


## Does record `a` go before record `b` in the queue?
func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["apply_tick"]) != int(b["apply_tick"]):
		return int(a["apply_tick"]) < int(b["apply_tick"])
	if int(a["seat"]) != int(b["seat"]):
		return int(a["seat"]) < int(b["seat"])
	return int(a["id"]) < int(b["id"])


## A game speed order: set the speed now, log it, file the events. Returns "" or the reason.
func _apply_speed(o: Dictionary) -> String:
	var h := int(o["settings"]["hundredths"])
	var msg := "" if world.speed.set_hundredths(h) else OrderKinds.TEXT_SPEED
	report(o, msg)
	if msg == "" and world.events_rts != null:
		world.events_rts.push({"kind": "game_speed", "team": int(o["team"]), "data": {"hundredths": h, "seat": int(o["seat"])}})
	return msg


## A refusal at submit: count it, file the event, tell the screens. Not logged.
func _refuse_at_submit(o: Dictionary, msg: String) -> void:
	var code := OrderKinds.reason_code(msg)
	_bump(o, code)
	OrderApply.file_event(world, o, code, "submit")
	var word := OrderKinds.action_word(str(o.get("kind", "")), int(o.get("seat", 0)))
	if word != "none":
		Events.admiral_result.emit(int(o["team"]), word, false, msg)


## The counters row of record `o`'s team and kind (made when first needed).
func _row(o: Dictionary) -> Dictionary:
	var team_key := "t%d" % int(o.get("team", 0))
	if not _counts.has(team_key):
		_counts[team_key] = {}
	var kinds: Dictionary = _counts[team_key]
	var kind := str(o.get("kind", ""))
	if not kinds.has(kind):
		kinds[kind] = {"submitted": 0, "ok": 0, "refused": {}}
	return kinds[kind]


## Count a result of record `o`: "ok", or the reason code.
func _bump(o: Dictionary, code: String) -> void:
	var row := _row(o)
	if code == "ok":
		row["ok"] = int(row["ok"]) + 1
		return
	var refused: Dictionary = row["refused"]
	refused[code] = int(refused.get(code, 0)) + 1


## The match ended: write the end line (OrderLog) and close.
func _on_match_over(_winner: int, _reason: String) -> void:
	close(world)


## The world is leaving the tree: stop listening and write what is waiting.
func _leave() -> void:
	if Events.match_over.is_connected(_on_match_over):
		Events.match_over.disconnect(_on_match_over)
	flush()
