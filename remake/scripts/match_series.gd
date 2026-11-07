class_name MatchSeries
extends Node
## WHAT THIS IS: the match series. A read-only observer that writes down, every ten seconds of
## match time, what each team holds (ships, ship modules and pilot gear at their list prices), how
## much hull and shield each mothership has left, the pilots' unspent credits, the treasuries and
## how many pilot ships are in space; and, as they happen, the pilot ships that die, the turrets,
## defense posts and repair bays that are destroyed and the mothership that falls. The end-of-match
## graph reads it (EndScreen gets it as an optional fourth argument), and the match recorder saves
## it beside the recording. It only reads the match: it never draws a random number and never
## changes anything, so a match plays out the same with it, and the same match always gives the
## same series (a replay of a recording writes a byte-identical file).
##
## HOW IT WORKS: main.gd makes one in every match, headless or windowed, recorded or not, right
## after the World, so that it works after the World's tick (like StatsRecorder), and setup() hears
## about the kills (Events.unit_killed) and the end of the match. Each World tick it checks the
## match clock (counting only the World's own ticks: world.ticked); the first tick takes the first
## sample, so a late-game start begins at its own time, and after that a sample is taken when the
## clock passes the next multiple of EVERY (10 s). A sample is a Dictionary:
##   t     the match time in seconds, to 0.1
##   val   per team [ships, modules, gear], whole credits: the list price of the hull each pilot
##         owns (a pilot who is dead holds nothing; the ship's modules go with the ship), of the
##         modules on it, and of the pilot's gear (a Mk II item at what it cost in all; repair kits
##         are left out); unlocking everything does not change what a thing is worth
##   ms    per team the mothership's hull as a fraction, to 0.001
##   sh    per team the mothership's shield as a fraction, to 0.001
##   cr    per team the pilots' unspent credits (whole)
##   tr    per team the treasury (whole)
##   fly   per team how many pilot ships are in space
## The pilots counted are the pilots of the team, the Admiral's seat included; the ships a team
## bought in the yard are not. An event is a Dictionary with t and k ("ship", "turret", "post",
## "bay" or "mothership") and these fields: for a ship death team (the victim's), by (the scoring
## team, or -1 for none), pilot (a pilot landed the killing blow), victim and killer (callsigns;
## killer is "" when no pilot did it), hull, size (0 to 3), lost (the ship's bounty_value),
## cause ("pilot", "turret", "minion", "mothership", "derelict", "crash" or "other") and where (a
## place name); for a turret team, by, label and where; for a post team, by and lane; for a bay
## team, by and where; for the mothership team. A last sample is added when the match ends
## (final_sample() is also what the end screen calls: it adds one when the newest is older than
## the match clock). The file (JSON, one sample or event to a line) is written when the match
## ends, when the program is closed or the player leaves the match, and once a minute, to
## `save_path` (set by MatchRecorder; empty means no file).
##
## WHO USES IT: main.gd (makes it and hands it to the HUD); MatchRecorder (sets save_path);
## EndScreen (reads samples and events, for the graph); tests/series_check.gd checks it.

## Seconds of match time between two samples.
const EVERY := 10.0
## Seconds of match time between two writes of the file.
const WRITE_EVERY := 60.0

## The running match.
var world: World
## Where the file goes ("" = no file).
var save_path := ""
## The samples taken so far, oldest first.
var samples: Array = []
## The events so far, in the order they happened.
var events: Array = []
## The match time of the first sample (set when it is taken).
var start_t := 0.0
## The winning team (set when the match ends; -1 until then).
var winner := -1
## True once the match has ended and the last sample is in.
var is_final := false
## True once the first sample has been taken.
var _started := false
## Match time of the next sample.
var _next := 0.0
## Match time of the next write of the file.
var _next_write := 0.0
## The match clock as of the last tick (kept for the last write at exit, when the World may be gone).
var _t := 0.0


## main.gd calls this once, right after the match is built. Listens for the kills and the end.
func setup(w: World) -> void:
	world = w
	Events.unit_killed.connect(_on_killed)
	Events.match_over.connect(_on_match_over)


## Godot calls this every tick, after the World. The first tick takes the first sample, and a
## sample follows each time the clock passes a multiple of EVERY.
func _physics_process(_dt: float) -> void:
	if world == null or is_final or world.phase != "play" or not world.ticked:
		return
	_t = world.time
	if not _started:
		_started = true
		start_t = _q(world.time, 10.0)
		_take()
		_next = (floorf(world.time / EVERY) + 1.0) * EVERY
		_next_write = (floorf(world.time / WRITE_EVERY) + 1.0) * WRITE_EVERY
		return
	if world.time >= _next:
		_take()
		_next = (floorf(world.time / EVERY) + 1.0) * EVERY
	if world.time >= _next_write:
		_next_write = (floorf(world.time / WRITE_EVERY) + 1.0) * WRITE_EVERY
		save(false)


## The match is over: the last sample and the last write.
func _on_match_over(winning_team: int, _reason: String) -> void:
	winner = winning_team
	final_sample()
	is_final = true
	save(true)


## Make sure the newest sample is as new as the match clock (the end screen calls this before it
## draws; the end of the match and the exit of the program call it too). Does nothing when the
## newest sample already has the clock's time, or when the match never started.
func final_sample() -> void:
	if world == null or not is_instance_valid(world) or not _started:
		return
	_t = world.time
	if samples.is_empty() or float((samples[samples.size() - 1] as Dictionary)["t"]) < _q(world.time, 10.0):
		_take()


## A unit died (Events.unit_killed, sent just before the unit is removed): file the kinds the
## graph marks. `info` is the killing blow's DamageInfo, valid for this call only.
func _on_killed(unit: Node, info: RefCounted) -> void:
	if world == null or is_final or not _started:
		return
	var u := unit as Unit
	var di := info as DamageInfo
	if u == null or not is_instance_valid(u):
		return
	match u.kind:
		Unit.K_SHIP:
			_ship_died(u as Ship, di)
		Unit.K_TURRET:
			_event({"k": "turret", "team": u.team, "by": Rules.enemy_of(u.team), "label": str((u as Turret).tdef.get("label", "Turret")), "where": world.place_name(u.global_position)})
		Unit.K_POST:
			_event({"k": "post", "team": u.team, "by": Rules.enemy_of(u.team), "lane": (u as DefensePost).lane})
		Unit.K_BAY:
			_event({"k": "bay", "team": u.team, "by": Rules.enemy_of(u.team), "where": world.place_name(u.global_position)})
		Unit.K_MOTHERSHIP:
			_event({"k": "mothership", "team": u.team})


## A pilot's ship died (a bought ship, whose profile is a crew, is not a pilot ship).
func _ship_died(ship: Ship, di: DamageInfo) -> void:
	var p := ship.profile
	if p == null or Squads.is_crew(p):
		return
	var killer: PilotProfile = null
	var cause := "other"
	var by := -1
	if di != null:
		killer = di.source_profile as PilotProfile
		if killer != null and Squads.is_crew(killer):
			killer = null
		if di.kind == Rules.W_COLLISION:
			cause = "crash"
		elif di.source_is_minion:
			cause = "minion"
		elif di.source_is_pilot:
			cause = "pilot" if killer != null else "other"
		elif di.source != null and is_instance_valid(di.source):
			match (di.source as Unit).kind:
				Unit.K_TURRET:
					cause = "turret"
				Unit.K_MOTHERSHIP:
					cause = "mothership"
				Unit.K_MONSTER, Unit.K_SNUB:
					cause = "derelict"
		if cause != "crash" and (di.source_team == 0 or di.source_team == 1) and di.source_team != ship.team:
			by = di.source_team
	_event({
		"k": "ship", "team": ship.team, "by": by, "pilot": killer != null, "victim": p.callsign,
		"killer": killer.callsign if killer != null else "", "hull": ship.hull_id, "size": ship.size_class,
		"lost": roundi(ship.bounty_value()), "cause": cause, "where": world.place_name(ship.global_position),
	})


## File an event at the match clock's time (the key `t` comes first).
func _event(ev: Dictionary) -> void:
	var out := {"t": _q(world.time, 10.0)}
	out.merge(ev)
	events.append(out)


## Take a sample of the match now.
func _take() -> void:
	var val := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var cr := [0.0, 0.0]
	var fly := [0, 0]
	for p: PilotProfile in world.profiles:
		if Squads.is_crew(p):
			continue
		var t := p.team
		cr[t] += p.credits
		var s: Ship = p.ship if p.state == "flying" and p.ship != null and is_instance_valid(p.ship) and p.ship.alive else null
		if s != null:
			fly[t] += 1
		var row: Array = val[t]
		if p.state != "dead" and p.hull_id != "":
			row[0] += float(Ships.HULLS[p.hull_id]["price"])
			var mods: Array = s.modules if s != null else p.modules
			for m: String in mods:
				row[1] += Modules.price_for(m, p.hull_id)
		row[2] += _gear_value(p)
	var ms := [0.0, 0.0]
	var sh := [0.0, 0.0]
	var tr := [0, 0]
	for t in 2:
		var m := world.mothership(t)
		if m != null and is_instance_valid(m):
			ms[t] = _q(m.hull_frac(), 1000.0)
			sh[t] = _q(m.shield_total() / m.shields.max_total, 1000.0) if m.shields != null and m.shields.max_total > 0.0 else 0.0
		tr[t] = roundi(world.teams[t].treasury)
	samples.append({
		"t": _q(world.time, 10.0),
		"val": [_ints(val[0]), _ints(val[1])],
		"ms": ms, "sh": sh, "cr": [roundi(cr[0]), roundi(cr[1])], "tr": tr, "fly": fly,
	})


## The list price of the gear in pilot `p`'s slots: each item at its price, a Mk II item at what it
## cost in all; repair kits are left out.
func _gear_value(p: PilotProfile) -> float:
	var v := 0.0
	for slot: Dictionary in p.inventory:
		if slot.is_empty() or slot["id"] == Items.KIT["id"]:
			continue
		v += GearMk2Feature.total_paid(String(slot["id"])) if slot.has("mk") else float(Items.ITEMS[slot["id"]]["price"])
	return v


## The numbers of `row` rounded to whole credits.
func _ints(row: Array) -> Array:
	var out: Array = []
	for x: float in row:
		out.append(roundi(x))
	return out


## `x` to the nearest 1/`per` (per 10: a tenth), as the double nearest that decimal, so that the
## file prints it short and the same every time.
func _q(x: float, per: float) -> float:
	return float(roundi(x * per)) / per


# --- the file ------------------------------------------------------------------------------

## The series as plain data, ready for JSON (see the file described at the top).
func snapshot(final: bool) -> Dictionary:
	return {
		"tool": "match_series", "version": 1, "every": EVERY, "start_t": start_t,
		"end_t": (samples[samples.size() - 1] as Dictionary)["t"] if not samples.is_empty() else start_t,
		"final": final, "winner": winner, "samples": samples, "events": events,
	}


## The file's text: the header fields, then one sample and one event to a line.
func file_text(final: bool) -> String:
	var snap := snapshot(final)
	var head := snap.duplicate()
	head.erase("samples")
	head.erase("events")
	var lines := PackedStringArray()
	for s: Dictionary in samples:
		lines.append(JSON.stringify(s, "", false))
	var evs := PackedStringArray()
	for e: Dictionary in events:
		evs.append(JSON.stringify(e, "", false))
	var head_text := JSON.stringify(head, "", false)
	return "%s,\n\"samples\":[\n%s\n],\n\"events\":[\n%s\n]}\n" % [head_text.substr(0, head_text.length() - 1), ",\n".join(lines), ",\n".join(evs)]


## Write the file now (only when `save_path` is set). `final` marks the last write of the match.
## Returns false when the file cannot be written (a warning is printed once).
func save(final: bool) -> bool:
	if save_path == "" or not _started:
		return false
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("series: cannot write %s (error %d)" % [save_path, FileAccess.get_open_error()])
		return false
	f.store_string(file_text(final))
	return true


## The window is being closed: write what we have.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_unfinished()


## The program is stopping or the player left the match (the World is still whole here: the series
## was added after it): write what we have, unless the match ended and already wrote its last file.
func _exit_tree() -> void:
	if Events.unit_killed.is_connected(_on_killed):
		Events.unit_killed.disconnect(_on_killed)
	if Events.match_over.is_connected(_on_match_over):
		Events.match_over.disconnect(_on_match_over)
	_save_unfinished()


## The last write of a match that did not end by itself (final false), with a last sample.
func _save_unfinished() -> void:
	if is_final:
		return
	final_sample()
	save(false)
	is_final = true
