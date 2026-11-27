class_name AdmiralLog
extends RefCounted
## WHAT THIS IS: the computer Admirals' decision log. One plain line for every order an Admiral sends, with
## the choice it did not take (the runner-up) and why, then a short machine tail for tools; and a "not yet"
## line when a decision is held back, only when its reason changes and at most once per rule every 60
## seconds. One file for the whole match holds both teams. It is written only when the launch option
## --admiral-log=<file> names a file, so a normal match writes nothing (and the web build never does).
##
## A line looks like this (the first is an order, the second a "not yet"):
##   12:34 Aurelian Admiral buys Corvette x1 (600) over a Fighter squadron: the fleet is 9 of 14 wanted ...  [rule=yard.fill kind=PRODUCE res=ok id=41 team=0 t=754]
##   21:10 Vhorr Admiral no siege yet: our fleet 14.2 against their 16.0, it needs 1.2 times  [rule=siege.edge nogo=1 team=1 t=1270]
## Team names are Rules.TEAM_DISPLAY. The tail after the square bracket is for tools and counters (the sample
## tool strips it): rule= names the rule, kind= is the order kind, res= is "ok" or the refusal code.
##
## HOW IT WORKS: the writer listens to Events.rts_event. Every order the Admiral's seat (Rules.ADMIRAL_SEAT)
## carries out or has refused reaches the order queue's event stream (order_done / order_refused), whatever
## part sent it, so every order gets exactly one line and the count of the "a" lines of the match log equals
## the count of the order lines here. The part that decides tells the writer why just before it sends the
## order (expect()); an order with no such note gets a plain line from KIND_WORDS. A rule that holds back
## calls not_yet(). note() writes a line that is no order (saving for a capital ship). feed() puts a big
## line in the team feed (Events.feed, "team" tone) for the team's own Admiral when its profile's log_feed
## is on; the enemy's lines never reach the feed. A team's lines are written only while its profile's
## decision_log is on.
## The same file also holds one line for each change of a computer pilot's plan or target (pilot(), written by
## PilotLog). It says "pilot <callsign>" (or "Admiral's ship <callsign>") where an Admiral line says "Admiral",
## it is counted in pilot_lines and kept in pilot_recent, and it is never an order line, so the counts of the
## Admiral lines stay as they were.
## The log draws no random number and writes no game state: it only reads and writes its own file, so a
## match is the same with it on or off.
##
## WHO USES IT: AdmiralAI, AdmiralSiege, AdmiralMothershipMover, AdmiralProduction, AdmiralBuilder and
## AdmiralWaypoint call it at their decisions, and PilotLog calls pilot() for the pilots; tests/admiral_log_check.gd
## and tests/bar7_log_check.gd check it.

## The shortest gap (seconds of match time) between two "not yet" lines of one rule.
const NOT_YET_GAP := 60.0
## How many lines are kept in memory for tests.
const KEEP := 400
## The words of an order that its part gave no reason for, by kind.
const KIND_WORDS := {
	"DRONE": "orders a mining drone", "MODULE": "builds a module", "RESEARCH": "starts a research",
	"TURRET": "buys a turret", "POST": "rebuilds a defense post", "BAY": "sends out a repair bay",
	"WARD": "places a ward", "WAYPOINT": "sets the team waypoint", "MOTHERSHIP_MOVE": "moves the mothership",
	"SIEGE": "changes the siege", "PRODUCE": "buys ships", "HOLD_ITEM": "holds or resumes a build item",
	"SET_REPEAT": "changes a repeat", "CANCEL": "cancels a build item", "MOVE_ITEM": "moves a build item",
	"SET_RALLY": "sets a rally point",
}

## The match.
var world: World
## True while the file is open: the log is on for this match.
var enabled := false
## The file's path ("" when none).
var path := ""
## The lines written so far (all kinds), the order lines among them.
var lines := 0
var order_lines := 0
## The last KEEP lines, for tests.
var recent: Array[String] = []
## The pilot lines written so far (kept apart from `lines`).
var pilot_lines := 0
## The last KEEP pilot lines, for tests.
var pilot_recent: Array[String] = []
## How many of the pilot lines were a change of target inside one plan.
var pilot_swaps := 0
## How many plan or target changes were held back because they did not last PilotLog.PLAN_HOLD seconds.
var pilot_held := 0
## PilotProfile -> the plan that pilot last wrote and the change waiting to be written (PilotLog keeps it).
var pilot_plans := {}
var _file: FileAccess = null
## team -> order kind -> the note the part left: {"rule", "chose", "over", "why", "extra"}.
var _pending := [{}, {}]
## "team:rule" -> [reason key, match second] of the last "not yet" line.
var _not_yet := {}


## The log of match `w` (made and kept on the world the first time it is asked for).
static func of(w: World) -> AdmiralLog:
	if w == null:
		return null
	if w.has_meta("admiral_log"):
		return w.get_meta("admiral_log") as AdmiralLog
	var l := AdmiralLog.new(w)
	w.set_meta("admiral_log", l)
	return l


func _init(w: World) -> void:
	world = w
	var want: Variant = Game.opt("admiral-log", "")
	if want == null or str(want) == "" or OS.has_feature("web"):
		return
	path = "user://admiral_log.txt" if want is bool else str(want)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("admiral log: cannot write %s" % path)
		path = ""
		return
	enabled = true
	_file.store_line("# the computer Admirals' decision log: one line per order, then the tail [rule=.. kind=.. res=..] for tools; times are m:ss of match time")
	Events.rts_event.connect(_on_event)
	w.tree_exiting.connect(close)


## Stop listening and close the file (the world is leaving the tree, or a test is done).
func close() -> void:
	if Events.rts_event.is_connected(_on_event):
		Events.rts_event.disconnect(_on_event)
	if _file != null:
		var pending := 0
		for entry: Variant in pilot_plans.values():
			if bool((entry as Dictionary).get("has_cand", false)):
				pending += 1
		if pilot_lines + pilot_held + pending > 0:
			_file.store_line("# pilot plan changes shorter than %.1f s were not written: %d" % [PilotLog.PLAN_HOLD, pilot_held + pending])
		_file.flush()
		_file = null
	enabled = false


## Does the log write for team `team` now (the file is open and the team's profile has decision_log on)?
func wants(team: int) -> bool:
	if not enabled or team < 0 or team > 1:
		return false
	var ai: AdmiralAI = world.admiral_ai[team]
	return ai != null and ai.profile != null and ai.profile.on("decision_log")


## The part that decides says what the order it is about to send is: `rule` names the rule, `chose` is the
## phrase after "Admiral", `over` the runner-up ("" for none), `why` the reason, `extra` more tail words.
## Call it right before the order; the writer takes it when the order's event comes.
func expect(team: int, kind: String, rule: String, chose: String, over: String, why: String, extra: Dictionary = {}) -> void:
	if not wants(team):
		return
	(_pending[team] as Dictionary)[kind] = {"rule": rule, "chose": chose, "over": over, "why": why, "extra": extra}


## A decision held back ("not yet"): written when its reason (`reason_key`, a short word) differs from the
## rule's last one and the rule has not written for NOT_YET_GAP seconds. `text` is the phrase after "Admiral".
func not_yet(team: int, rule: String, reason_key: String, text: String, extra: Dictionary = {}) -> void:
	if not wants(team):
		return
	var key := "%d:%s" % [team, rule]
	var prev: Variant = _not_yet.get(key)
	if prev != null and (str((prev as Array)[0]) == reason_key or world.time - float((prev as Array)[1]) < NOT_YET_GAP):
		return
	_not_yet[key] = [reason_key, world.time]
	var tail := {"rule": rule, "nogo": 1}
	tail.merge(extra)
	_write(team, text, tail)


## A line that is no order (for example "saves for a capital ship"): `text` is the phrase after "Admiral".
func note(team: int, rule: String, text: String, extra: Dictionary = {}) -> void:
	if not wants(team):
		return
	var tail := {"rule": rule}
	tail.merge(extra)
	_write(team, text, tail)


## A pilot's line (PilotLog calls it): `who` is the words that name the pilot, `text` the whole sentence (what it
## chose, what it almost chose and why, joined by PilotLog), `kind` is "launch", "plan" or "swap" and `extra` holds
## the tail words (rule, state, prev, seat). Written only while the team's decision_log is on.
func pilot(team: int, who: String, text: String, kind: String, extra: Dictionary = {}) -> void:
	if not wants(team):
		return
	var tail := {"rule": str(extra.get("rule", "pilot")), "change": kind}
	for key: Variant in extra:
		if str(key) != "rule":
			tail[key] = extra[key]
	_write(team, text, tail, who)


## Put a big line in the team feed, for team `team`'s own Admiral, when its profile's log_feed (and decision_log) is on.
static func feed(w: World, team: int, text: String) -> void:
	if w == null or team < 0 or team > 1:
		return
	var ai: AdmiralAI = w.admiral_ai[team]
	if ai != null and ai.profile != null and ai.profile.on("decision_log") and ai.profile.on("log_feed"):
		Events.feed.emit(text, "team", team)


## An order event (order_done or order_refused) of an Admiral's seat: write its line.
func _on_event(ev: Dictionary) -> void:
	var k := str(ev.get("kind", ""))
	if k != "order_done" and k != "order_refused":
		return
	var data: Dictionary = ev.get("data", {})
	var team := int(ev.get("team", -1))
	if int(data.get("seat", -1)) != Deputy.computer_seat(world, team) or not wants(team):
		return
	var kind := str(data.get("kind", ""))
	var code := "ok" if k == "order_done" else str(data.get("reason", "?"))
	var held: Dictionary = (_pending[team] as Dictionary).get(kind, {})
	(_pending[team] as Dictionary).erase(kind)
	var chose := str(held.get("chose", KIND_WORDS.get(kind, kind.to_lower())))
	var over := str(held.get("over", ""))
	var why := str(held.get("why", ""))
	var text := chose
	if code != "ok":
		text = "%s, but it was refused (%s)" % [chose, code]
	if over != "":
		text += " over " + over
	if why != "":
		text += ": " + why
	var tail := {"rule": str(held.get("rule", "other")), "kind": kind, "res": code, "id": int(data.get("id", 0))}
	tail.merge(held.get("extra", {}))
	order_lines += 1
	_write(team, text, tail)


## Write one line: the clock, the team and who writes it ("Admiral" or a pilot), the text, then the tail. An
## Admiral line is counted in `lines` and kept in `recent`; a pilot line in `pilot_lines` and `pilot_recent`.
func _write(team: int, text: String, tail: Dictionary, who: String = "Admiral") -> void:
	tail["team"] = team
	tail["t"] = int(world.time)
	var parts := PackedStringArray()
	for key: Variant in tail:
		parts.append("%s=%s" % [str(key), str(tail[key])])
	var line := "%s %s %s %s  [%s]" % [Util.clock(world.time), Rules.TEAM_DISPLAY[team], who, text, " ".join(parts)]
	if who == "Admiral":
		lines += 1
		recent.append(line)
		if recent.size() > KEEP:
			recent.pop_front()
	else:
		pilot_lines += 1
		if str(tail.get("change", "")) == "swap":
			pilot_swaps += 1
		pilot_recent.append(line)
		if pilot_recent.size() > KEEP:
			pilot_recent.pop_front()
	if _file != null:
		_file.store_line(line)
		_file.flush()
