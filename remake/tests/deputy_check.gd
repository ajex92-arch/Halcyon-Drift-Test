extends Node
## WHAT THIS IS: the check of the deputy (scripts/ai/deputy.gd, scripts/rts/absence.gd and the seat marks): the
## computer Admiral that helps a human Admiral. Every part runs in a match of its own that the check builds and
## steps by hand (a tick at a time), in the seat of a human Admiral:
##   - THE TIMER: the deputy is off; 1,799 ticks with no input leave it off and tick 1,800 switches it on with
##     Balanced; a human order at tick 1,700 moves that to 1,800 ticks after the order; a camera move does not
##     reset the count, a flying control does; held controls count as long as they are held, a coasting ship's
##     controls (the command view open) do not; the seat-open event is filed once at 5,400 ticks of absence and
##     again only after a new absence; the same scripted input switches it on at the same tick in two matches.
##   - PRESENT AND AWAY: with the human giving an order every 600 ticks the deputy sends builds and research and
##     no waypoint, siege or mothership order; away, its fleet layer exists, there is still none of those and no
##     field trip; the first human input afterwards puts the fleet layer off and hands the seat back to the
##     human's own setting; a match whose deputy is never made sends nothing of the deputy's.
##   - THE SEAT: every order the deputy sends has the seat "deputy" (-1) and the log's "a" marker, the human's
##     orders stay seat 5 and "h"; the outbox's orders cap counts the deputy's seat on the human's team and the
##     Admiral's seat on a computer team; the deputy's seat may not send the waypoint, siege or mothership move.
##   - THE CARD AND THE STRIP (with --force-hud, which gives the check a command view): a press on the Deputy cell
##     switches the deputy on and off, the Dep. mode cell steps Balanced, Attack, Defend, Economy in that order, the
##     strip says "Deputy: <preset>" while it is on and exactly "DEPUTY off" while it is off, and its button toggles it.
##   - AFTER A MUTINY (the chair passes to a new computer Admiral): the deputy sends no order and replaces nobody, and a
##     DEPUTY order of the human, queued or handed to the handler directly, changes nothing of the deputy or the new Admiral.
##   - THE FEATURE HOOKS: with the orders, assets, Fortify, doctrine, smart and sinks features on and the deputy on, the
##     human seat's own hooks (the command assets, Fortify, the smart composition calls) act for the deputy's team only
##     while the human is away, the bounties never act for it, the wards and the doctrine research always do; the computer's
##     team acts in every row (the control).
##   - THE BUILD LIST (with --force-hud): a ship the deputy's seat bought reads "deputy" in the build list's row.
## The long part (the option --deputy-secs=<seconds>, off by default) plays the launched match itself with a
## scripted human seat that gives a drone order every 600 ticks until 5:00 and then goes silent. Two scenarios
## (--deputy-scenario=tryafter, the default, or silent): in "tryafter" the human turns the deputy on with Balanced at
## tick 0 (the try-after flow); in "silent" (the control, the first test's scenario) the deputy is off until the 30
## seconds of silence switch it on at 5:30; the third scenario "computer" (for a match started with --all-ai) has no deputy
## and no human order at all, and is judged on the fleet and the research only. A match decided before the given time PASSES if the human team won it
## and FAILS if it lost (a last look never saves a lost match); a match still on at the given time is judged on
## the team's fleet (living, building and waiting ships) being at least 30 percent of the fleet limit and more
## research being done than at 5:00. Every line of the long part names its scenario. At the end of the long part (decided
## or at the given time) one "look" line also prints both teams' mothership, kills, waypoints and field trips and the usage counters.
##
## HOW IT WORKS: setup() runs the short part and prints "deputy_check: N failures" (a FAIL line for each), or
## with --deputy-secs starts the long part in _physics_process and prints the same last line.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --seed=1 --no-jungle --force-hud --test=deputy_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --seed=1 --no-jungle --deputy-secs=900 --test=deputy_check
##   (add --deputy-scenario=silent for the control scenario; --all-ai in place of --role=admiral with --deputy-scenario=computer for the computer's own match)
##
## WHO USES IT: main.gd loads it for --test=deputy_check (it calls setup()); run_checks has one row for the short part.

## The world scene a check builds its own matches from.
const WORLD_SCENE := "res://scenes/world/world.tscn"

## The launched match (set by setup()).
var world: World
## How many checks failed and how many were made.
var _fails := 0
var _checks := 0  # the checks made
## The order and seat-open records heard while a match is stepped: "team:seat:kind" -> count, and "open:team" -> count.
var _tally := {}
## The long part's two scenarios (the option --deputy-scenario=): the human turns the deputy on at tick 0 and later goes
## silent (the try-after flow, the default), or the human never touches it and the 30 seconds of silence switch it on at 5:30.
const SCENARIO_TRY_AFTER := "tryafter"
## The control scenario: the human never touches the deputy (see above).
const SCENARIO_SILENT := "silent"
## The computer scenario (the option --deputy-scenario=computer, meant for a match started with --all-ai): team 0 plays
## with the computer Admiral and no deputy, and no human order is given, so the log shows what the computer does in the
## same match setup.
const SCENARIO_COMPUTER := "computer"

## The long part: the scenario played (set by setup()).
var _scenario := SCENARIO_TRY_AFTER
## The long part: the time to look at (in ticks; 0 = the short part is run).
var _long_end := 0
## The long part: the research done at 5:00 (-1 until then).
var _done300 := -1
## The long part: the last look taken (every 600 ticks): tick, fleet, limit, research done, deputy on, ticks with no input, the human ship out.
var _look := {}
## True while the UI part waits for the HUD and the command view of the launched match.
var _ui_wait := false
## The real time (milliseconds since the program started) at which the UI part began to wait: its 150 s are counted from there, not
## from the start of the program, because the short part before it takes longer on a busy PC.
var _ui_t0 := 0
## True once the UI part has started (it runs once).
var _ui_started := false


## An order log that keeps the lines in memory and writes no file, so a check can read what the match would log.
class MemLog extends OrderLog:
	## The lines of the orders, as OrderLog's record() would write them.
	var lines: Array[String] = []

	## Keep the order's line.
	func record(o: Dictionary, code: String) -> void:
		lines.append(Order.to_line(o, code))

	## Write nothing.
	func header() -> void:
		pass

	## Write nothing.
	func hash_line(_tick: int) -> void:
		pass

	## Write nothing.
	func controls(_tick: int, _seat: int, _c: ShipControls) -> void:
		pass

	## Write nothing.
	func command(_tick: int, _seat: int, _kind: String, _args: Array, _result: String) -> void:
		pass

	## Write nothing.
	func field(_tick: int, _team: int, _op: String, _a: String, _b: String) -> void:
		pass

	## Write nothing.
	func close(_w: World) -> void:
		pass

	## Write nothing.
	func flush() -> void:
		pass


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	w.set_physics_process(false)
	Events.rts_event.connect(_on_event)
	var secs: Variant = Game.opt("deputy-secs")
	if secs != null:
		_long_end = maxi(1800, int(str(secs)) * 60)
		_scenario = str(Game.opt("deputy-scenario", SCENARIO_TRY_AFTER))
		if _scenario != SCENARIO_TRY_AFTER and _scenario != SCENARIO_SILENT and _scenario != SCENARIO_COMPUTER:
			_scenario = SCENARIO_TRY_AFTER
		if _scenario == SCENARIO_COMPUTER:
			print("deputy_check: long part [%s], no human orders and no deputy, looking at %d s" % [_scenario, _long_end / 60])
		else:
			print("deputy_check: long part [%s], the human seat goes silent at 5:00, looking at %d s" % [_scenario, _long_end / 60])
		return
	_timer_cases()
	_controls_cases()
	_present_cases()
	_away_cases()
	_replay_cases()
	_seat_cases()
	_marks_cases()
	_mutiny_cases()
	_hook_cases()
	# The card's cells and the strip need the HUD (the option --force-hud makes one without a window).
	if Game.opt("force-hud") != null:
		_tally.clear()
		w.set_physics_process(true)
		_ui_wait = true
		_ui_t0 = Time.get_ticks_msec()
		return
	print("deputy_check: ui part skipped (no --force-hud)")
	print("deputy_check: %d failures (%d checks)" % [_fails, _checks])
	get_tree().quit()


## The long part: step the launched match in chunks, the scripted human seat acting until 5:00. A match that is decided
## before the time asked for passes only if the human team won it (the last look is only read for "the deputy was on").
func _physics_process(_dt: float) -> void:
	if _long_end == 0 or world == null:
		return
	var team := world.human_team
	var ts: TeamState = world.teams[team]
	for i in 600:
		if world.phase != "play":
			var won := world.winner == team
			print("deputy_check: long [%s] seed %s: the match was decided at tick %d, winner team %d, the human team (%d) %s" % [_scenario, str(Game.opt("seed", "?")), world.tick_count, world.winner, team, "WON" if won else "LOST"])
			_check("long: the match decided at tick %d was won by the human team (a lost match fails whatever the last look showed)" % world.tick_count, won)
			if not _look.is_empty() and _scenario != SCENARIO_COMPUTER:
				_check("long: the deputy was on at the last look (tick %d)" % int(_look["tick"]), bool(_look["on"]))
			if _look.is_empty():
				_print_look(0, 0)
			else:
				_print_look(int(_look["fleet"]), int(_look["limit"]))
			_finish_long()
			return
		if world.tick_count % 600 == 0:
			if world.tick_count == 0 and _scenario == SCENARIO_TRY_AFTER:
				_human_deputy(world, "balanced")
			if world.tick_count < 18000 and _scenario != SCENARIO_COMPUTER:
				world.orders.submit(Order.make(OrderKinds.DRONE, team, Rules.ADMIRAL_SEAT, true, {"node": ""}))
			var prod := ts.production
			var dep := world.orders.deputy as Deputy
			_look = {"tick": world.tick_count, "fleet": prod.capacity.alive() + prod.ships_in_list(), "limit": prod.capacity.limit(), "done": ts.done.size(), "on": dep != null and dep.preset != "off", "idle": dep.absence.ticks_away() if dep != null else 0, "ship": world.human != null and world.human.ship != null, "why": dep.absence.last_why if dep != null else ""}
		world._physics_process(1.0 / 60.0)
		if world.tick_count == 18000:
			_done300 = ts.done.size()
		if world.tick_count >= _long_end:
			var prod2 := ts.production
			var d := world.orders.deputy as Deputy
			var now := {"tick": world.tick_count, "fleet": prod2.capacity.alive() + prod2.ships_in_list(), "limit": prod2.capacity.limit(), "done": ts.done.size(), "on": d != null and d.preset != "off"}
			if d == null:
				print("deputy_check: long [%s] seed %s: fleet %d of %d, research done %d at 5:00 and %d now" % [_scenario, str(Game.opt("seed", "?")), int(now["fleet"]), int(now["limit"]), _done300, int(now["done"])])
			else:
				print("deputy_check: long [%s] seed %s: fleet %d of %d, research done %d at 5:00 and %d now, deputy %s, away %s" % [_scenario, str(Game.opt("seed", "?")), int(now["fleet"]), int(now["limit"]), _done300, int(now["done"]), d.preset, str(d.away)])
			_print_look(int(now["fleet"]), int(now["limit"]))
			_judge(now)
			_finish_long()
			return


## The long part's three checks on the look `v` ({tick, fleet, limit, done, on}): the deputy is on (not asked in the
## computer scenario, which has none), the fleet is at least 30 percent of the limit, and more research is done than at 5:00.
func _judge(v: Dictionary) -> void:
	if _scenario != SCENARIO_COMPUTER:
		_check("long: the deputy is on", bool(v["on"]))
	_check("long: the fleet is at least 30 percent of the limit (%d of %d)" % [int(v["fleet"]), int(v["limit"])], int(v["fleet"]) * 100 >= int(v["limit"]) * 30)
	_check("long: more research is done than at 5:00 (%d against %d)" % [int(v["done"]), _done300], int(v["done"]) > _done300)

## Print the one "look" line of the long part (test code only, it reads the match and changes nothing): the tick, the fleet
## `fleet` of `limit`, `ai_acts_seat` and `ai_acts_solo` for team 0 (AdmiralWeak), then for each team its
## mothership hull in percent, kills, waypoints placed (0 when the order counters hold none), field trips of its computer
## Admiral (0 when it has none), and the usage counters of the match.
func _print_look(fleet: int, limit: int) -> void:
	var counts: Dictionary = world.orders.counters()
	var parts: Array[String] = []
	for t in 2:
		var ms := world.mothership(t)
		var pct := roundi(ms.hull_frac() * 100.0) if is_instance_valid(ms) else 0
		var way := int(((counts.get("t%d" % t, {}) as Dictionary).get("WAYPOINT", {}) as Dictionary).get("ok", 0))
		var ai := world.admiral_ai[t] as AdmiralAI
		var trips := ai.field.trips.size() if ai != null and ai.field != null else 0
		parts.append("team %d: mothership %d%%, kills %d, waypoints %d, field trips %d" % [t, pct, world.teams[t].kills, way, trips])
	print("deputy_check: look [%s] seed %s tick %d: fleet %d of %d, ai_acts_seat %s, ai_acts_solo %s, %s, usage %s" % [_scenario, str(Game.opt("seed", "?")), world.tick_count, fleet, limit, str(AdmiralWeak.ai_acts_seat(world, 0)).to_lower(), str(AdmiralWeak.ai_acts_solo(world, 0)).to_lower(), ", ".join(parts), JSON.stringify(Game.usage)])


## The UI part waits for the HUD and the command view of the launched match, then runs; 150 s of real time at most.
func _process(_dt: float) -> void:
	if not _ui_wait or _ui_started or world == null:
		return
	if Time.get_ticks_msec() - _ui_t0 > 150000:
		print("deputy_check: ui part timed out")
		_check("ui: the HUD and the command view came up", false)
		_ui_started = true
		print("deputy_check: %d failures (%d checks)" % [_fails, _checks])
		get_tree().quit()
		return
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or hud.command_view == null or world.human == null or world.phase != "play":
		return
	_ui_started = true
	_ui_cases(hud)


## Print the last line of the long part and quit.
func _finish_long() -> void:
	print("deputy_check: %d failures (%d checks)" % [_fails, _checks])
	get_tree().quit()


# --- helpers ---------------------------------------------------------------------------------------------

## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## A new match in the seat of a human Admiral, built from the world scene and paused (the check steps it). `quiet` leaves
## the computer pilots out (the timer cases need no fighting). The random numbers start from the same seed every time.
func _new_world(quiet: bool) -> World:
	if quiet:
		Game.options["no-pilots"] = true
	seed(7)
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	add_child(w)
	w.set_physics_process(false)
	w.setup("admiral")
	if quiet:
		Game.options.erase("no-pilots")
	Game.world = world
	_tally.clear()
	return w


## Free a match the check built.
func _drop(w: World) -> void:
	remove_child(w)
	w.free()
	Game.world = world


## Step `w` by `n` ticks.
func _step(w: World, n: int) -> void:
	for i in n:
		w._physics_process(1.0 / 60.0)


## The human gives an order of the Admiral's seat (a drone) from the screen's door; returns the queue's answer.
func _human_drone(w: World) -> String:
	return w.orders.submit(Order.make(OrderKinds.DRONE, w.human_team, Rules.ADMIRAL_SEAT, true, {"node": ""}))


## The human sets the deputy through the DEPUTY order.
func _human_deputy(w: World, word: String) -> String:
	return w.orders.submit(Order.make(OrderKinds.DEPUTY, w.human_team, Rules.ADMIRAL_SEAT, true, {"preset": word}))


## Count a record of the stream (order_done, order_refused, seat_open) while a match is stepped.
func _on_event(rec: Dictionary) -> void:
	var k := str(rec.get("kind", ""))
	var data: Dictionary = rec.get("data", {})
	var key := ""
	if k == "order_done" or k == "order_refused":
		key = "%d:%d:%s" % [int(rec.get("team", -1)), int(data.get("seat", 0)), str(data.get("kind", ""))]
	elif k == "seat_open":
		key = "open:%d" % int(rec.get("team", -1))
	if key != "":
		_tally[key] = int(_tally.get(key, 0)) + 1


## How many orders of `kind` the records heard so far show for `team` and `seat`.
func _n(team: int, seat: int, kind: String) -> int:
	return int(_tally.get("%d:%d:%s" % [team, seat, kind], 0))


## The kinds of the orders heard for `team` and `seat`, sorted.
func _kinds(team: int, seat: int) -> Array:
	var out := []
	for key: String in _tally:
		var parts := key.split(":")
		if parts.size() == 3 and int(parts[0]) == team and int(parts[1]) == seat:
			out.append(parts[2])
	out.sort()
	return out


## How many orders of every kind heard for `team` and `seat`.
func _seat_total(team: int, seat: int) -> int:
	var n := 0
	for k: String in _kinds(team, seat):
		n += _n(team, seat, k)
	return n


## The deputy of match `w`.
func _dep(w: World) -> Deputy:
	return w.orders.deputy


## How many seat-open records were heard for `team`.
func _opens(team: int) -> int:
	return int(_tally.get("open:%d" % team, 0))


# --- the timer ----------------------------------------------------------------------------------------------

## The deputy is made on a human Admiral's team only; the timer switches it on at tick 1,800; the seat-open event.
func _timer_cases() -> void:
	var w := _new_world(true)
	var team := w.human_team
	var d := _dep(w)
	_check("timer: a human Admiral's match has a deputy, off at the start", d != null and d.preset == "off" and not d.away and w.admiral_ai[team] == null)
	_check("timer: the other team has no deputy business and keeps its computer Admiral", w.admiral_ai[1 - team] != null)
	_check("timer: the DEPUTY order has a handler and is applied next", w.orders.has_applier(OrderKinds.DEPUTY) and OrderKinds.APPLIES[OrderKinds.DEPUTY] == "next")
	_step(w, 1799)
	_check("timer: 1,799 ticks with no input leave the deputy off", d.preset == "off" and not d.away and w.admiral_ai[team] == null)
	_step(w, 1)
	_check("timer: tick 1,800 switches it on with Balanced", d.preset == "balanced" and d.away and w.admiral_ai[team] != null and (w.admiral_ai[team] as AdmiralAI).deputy == d, "%s %s" % [d.preset, str(d.away)])
	var ai := w.admiral_ai[team] as AdmiralAI
	_check("timer: away it plays the fleet layer too (switch on, layer made)", ai.fleet != null and ai.profile.on("fleet_play") and ai.profile.profile_name == "balanced")
	_step(w, 3599)
	_check("timer: no seat-open event before 5,400 ticks of absence", _opens(team) == 0)
	_step(w, 1)
	_check("timer: one seat-open event at 5,400 ticks", _opens(team) == 1, str(_opens(team)))
	_step(w, 300)
	_check("timer: and not again while the absence goes on", _opens(team) == 1, str(_opens(team)))
	# Input ends the absence; a new absence files the event again.
	_human_drone(w)
	_step(w, 3)
	_check("timer: the human's input hands the seat back (away over, fleet layer off, off again)", not d.away and not d.sent_open and w.admiral_ai[team] == null)
	d.absence.last_input = w.tick_count - Absence.OPEN_TICKS
	_step(w, 2)
	_check("timer: a new absence of 5,400 ticks files the event once more", _opens(team) == 2 and d.away, str(_opens(team)))
	_step(w, 120)
	_check("timer: and once only", _opens(team) == 2, str(_opens(team)))
	_drop(w)
	# A human order at tick 1,700 moves the switch-on to 1,800 ticks after the order.
	w = _new_world(true)
	team = w.human_team
	d = _dep(w)
	_step(w, 1700)
	_human_drone(w)
	_step(w, 100)
	_check("timer: an order at tick 1,700 means no switch-on at 1,800", d.preset == "off" and not d.away, d.preset)
	_step(w, 1700)
	_check("timer: and still none at tick 3,500", d.preset == "off" and not d.away, d.preset)
	_step(w, 1)
	_check("timer: on at tick 3,501, 1,800 ticks after the order took effect", d.preset == "balanced" and d.away, "%s at tick %d" % [d.preset, w.tick_count])
	_drop(w)
	# A camera move does not reset the count.
	w = _new_world(true)
	d = _dep(w)
	_step(w, 1700)
	if w.camera != null:
		(w.camera as Node2D).position += Vector2(900.0, 0.0)
	_step(w, 100)
	_check("timer: a camera move at tick 1,700 does not reset it: on at 1,800", d.preset == "balanced" and d.away, d.preset)
	_drop(w)


## The flying controls: the order queue's hook, held controls, one-off requests, the aim point that does not count, the coast.
func _controls_cases() -> void:
	var w := _new_world(true)
	var d := _dep(w)
	var ship := Ship.new()
	_step(w, 1700)
	w.orders.record_controls(ship)
	_check("controls: idle controls of a ship are no input", d.absence.last_input == 0, str(d.absence.last_input))
	ship.controls.forward = 1.0
	w.orders.record_controls(ship)
	_check("controls: the order queue hands the controls to the deputy (forward counts)", d.absence.last_input == 1700, str(d.absence.last_input))
	_step(w, 100)
	_check("controls: a control at tick 1,700 means no switch-on at 1,800", d.preset == "off" and not d.away)
	_step(w, 1700)
	_check("controls: and on at tick 3,500, 1,800 ticks after it", d.preset == "balanced" and d.away, d.preset)
	ship.free()
	_drop(w)
	# The stopwatch on its own, the clock written by hand.
	w = _new_world(true)
	var ab := Absence.new(w, w.human_team)
	var c := ShipControls.new()
	w.tick_count = 10
	ab.note_controls(c)
	ab.note_controls(c)
	_check("controls: two idle looks are no input", ab.last_input == 0, str(ab.last_input))
	w.tick_count = 11
	c.forward = 1.0
	ab.note_controls(c)
	_check("controls: thrust is input", ab.last_input == 11)
	w.tick_count = 12
	ab.note_controls(c)
	_check("controls: thrust held counts on every tick it is held", ab.last_input == 12)
	w.tick_count = 13
	c.forward = 0.0
	ab.note_controls(c)
	_check("controls: letting go is one change", ab.last_input == 13)
	w.tick_count = 14
	ab.note_controls(c)
	_check("controls: and the idle look after it is none", ab.last_input == 13)
	w.tick_count = 15
	c.aim_point = Vector2(900.0, 0.0)
	ab.note_controls(c)
	_check("controls: an aim point that moves a long way (the camera moved) is no input", ab.last_input == 13, str(ab.last_input))
	w.tick_count = 20
	c.special = true
	ab.note_controls(c)
	_check("controls: a one-off request is input", ab.last_input == 20)
	c.special = false
	c.focus_request = Rules.FOCUS_FRONT
	w.tick_count = 21
	ab.note_controls(c)
	_check("controls: so is a shield request", ab.last_input == 21)
	c.focus_request = -1
	ab.note_controls(c)
	w.tick_count = 30
	w.view_open = true
	c.forward = 1.0
	c.fire = true
	ab.note_controls(c)
	_check("controls: a ship that coasts under the command view is no input", ab.last_input == 21, str(ab.last_input))
	w.view_open = false
	_drop(w)


## While the human is present: the deputy sends builds and research and nothing that is the human seat's.
func _present_cases() -> void:
	var w := _new_world(false)
	var team := w.human_team
	var d := _dep(w)
	var mem := MemLog.new()
	w.orders.log = mem
	var human_orders := 0
	_check("present: the DEPUTY order is taken (Balanced)", _human_deputy(w, "balanced") == "")
	human_orders += 1
	for t in 4200:
		if t % 600 == 0 and t > 0:
			_human_drone(w)
			human_orders += 1
		w._physics_process(1.0 / 60.0)
	var ai := w.admiral_ai[team] as AdmiralAI
	_check("present: the deputy runs Balanced and never went away", d.preset == "balanced" and not d.away and ai != null and ai.deputy == d)
	_check("present: the fleet layer is off while the human is there", ai != null and ai.fleet == null)
	var sent := _kinds(team, OrderKinds.DEPUTY_SEAT)
	var builds := _n(team, OrderKinds.DEPUTY_SEAT, OrderKinds.DRONE) + _n(team, OrderKinds.DEPUTY_SEAT, OrderKinds.RESEARCH) + _n(team, OrderKinds.DEPUTY_SEAT, OrderKinds.MODULE)
	_check("present: the deputy sends builds and research (%s)" % str(sent), builds > 0)
	for kind: String in [OrderKinds.WAYPOINT, OrderKinds.SIEGE, OrderKinds.MOTHERSHIP_MOVE, OrderKinds.DEPUTY]:
		_check("present: no %s order from the deputy" % kind, _n(team, OrderKinds.DEPUTY_SEAT, kind) == 0)
	for kind: String in OrderKinds.SQUADRON_KINDS:
		_check("present: no %s squadron order from the deputy while the human is there" % kind, _n(team, OrderKinds.DEPUTY_SEAT, kind) == 0)
	var counts := w.orders.counters()
	var row: Dictionary = (counts.get("t%d" % team, {}) as Dictionary)
	for kind: String in [OrderKinds.WAYPOINT, OrderKinds.SIEGE, OrderKinds.MOTHERSHIP_MOVE]:
		_check("present: the queue's counters show no %s on the human team" % kind, not row.has(kind) or int((row[kind] as Dictionary).get("submitted", 0)) == 0)
	_check("present: the waypoint timer ran (the step was reached) and placed nothing", ai != null and ai.waypoint_t > 0.0 and ai.waypoint_t <= ai.profile.f("waypoint_gap_s"), str(ai.waypoint_t if ai != null else -1.0))
	_check("present: no field trip", ai != null and ai.field.trips.is_empty())
	# The seat marks.
	_check("seat: the deputy sent orders in this run", _seat_total(team, OrderKinds.DEPUTY_SEAT) > 0)
	_check("seat: the human's own orders are the only seat-5 orders (the deputy's have not taken the Admiral's seat)", _seat_total(team, Rules.ADMIRAL_SEAT) == human_orders, "%d against %d" % [_seat_total(team, Rules.ADMIRAL_SEAT), human_orders])
	var deputy_lines := 0
	var wrong := 0
	var human_lines := 0
	for line in mem.lines:
		var parts := line.split(" ")
		if parts.size() < 9 or parts[2] != str(team):
			continue
		if parts[3] == str(OrderKinds.DEPUTY_SEAT):
			deputy_lines += 1
			if parts[4] != "a":
				wrong += 1
		elif parts[3] == str(Rules.ADMIRAL_SEAT):
			human_lines += 1
			if parts[4] != "h":
				wrong += 1
	_check("seat: every deputy order is logged with seat -1 and the \"a\" marker (%d lines)" % deputy_lines, deputy_lines > 0 and wrong == 0, "%d lines, %d wrong" % [deputy_lines, wrong])
	_check("seat: the human's orders are logged with seat 5 and the \"h\" marker (%d lines)" % human_lines, human_lines > 0)
	_check("seat: the yard's items bought by the deputy carry the seat -1", _yard_seats_ok(w, team))
	_drop(w)


## Is every ship still in `team`'s build list one the deputy bought (the human bought none in the run)? Items of
## the other kinds are made with the Admiral's seat whoever orders them, so only ships are looked at.
func _yard_seats_ok(w: World, team: int) -> bool:
	var ts: TeamState = w.teams[team]
	for it: Dictionary in ts.production.items:
		if str(it.get("kind", "")) == Production.SHIP and int(it.get("seat", Rules.ADMIRAL_SEAT)) != OrderKinds.DEPUTY_SEAT:
			return false
	return true


## While the human is away: the fleet layer, none of the human seat's orders, and the hand-back.
func _away_cases() -> void:
	var w := _new_world(false)
	var team := w.human_team
	var d := _dep(w)
	_step(w, 4500)
	var ai := w.admiral_ai[team] as AdmiralAI
	_check("away: the silent seat switched the deputy on with Balanced", d.preset == "balanced" and d.away and ai != null)
	_check("away: its fleet layer exists", ai != null and ai.fleet != null)
	for kind: String in [OrderKinds.WAYPOINT, OrderKinds.SIEGE, OrderKinds.MOTHERSHIP_MOVE]:
		_check("away: still no %s order from the deputy" % kind, _n(team, OrderKinds.DEPUTY_SEAT, kind) == 0)
	_check("away: no order of the Admiral's seat on the human team", _seat_total(team, Rules.ADMIRAL_SEAT) == 0, str(_seat_total(team, Rules.ADMIRAL_SEAT)))
	_check("away: no field trip", ai != null and ai.field.trips.is_empty())
	_check("away: the deputy sent orders (%s)" % str(_kinds(team, OrderKinds.DEPUTY_SEAT)), _seat_total(team, OrderKinds.DEPUTY_SEAT) > 0)
	_drop(w)
	# The first input after being away: the fleet layer off; the seat goes back to the human's setting (off, nothing chosen).
	w = _new_world(true)
	team = w.human_team
	d = _dep(w)
	_step(w, 1801)
	_check("away: (second match) away at tick 1,801 with the layer on", d.away and (w.admiral_ai[team] as AdmiralAI).fleet != null)
	_human_drone(w)
	_step(w, 3)
	_check("away: the first human input ends the absence, the layer is gone and the deputy is off again (nothing was chosen)", not d.away and w.admiral_ai[team] == null and d.preset == "off")
	_drop(w)
	# With a preset chosen, the deputy stays on that preset and only the fleet layer goes off.
	w = _new_world(true)
	team = w.human_team
	d = _dep(w)
	_human_deputy(w, "attack")
	_step(w, 1801 + 5)
	var ai2 := w.admiral_ai[team] as AdmiralAI
	_check("away: a chosen preset (Attack) stays on while away, with the layer on", d.away and d.preset == "attack" and ai2 != null and ai2.fleet != null and ai2.profile.profile_name == "attack", d.preset)
	_human_drone(w)
	_step(w, 3)
	_check("away: back, it keeps the chosen preset and loses the fleet layer", not d.away and d.preset == "attack" and w.admiral_ai[team] != null and (w.admiral_ai[team] as AdmiralAI).fleet == null)
	_human_deputy(w, "off")
	_step(w, 2)
	_check("away: the DEPUTY order off removes it", d.preset == "off" and w.admiral_ai[team] == null and d.chosen == "off")
	_human_deputy(w, "reckless")
	_step(w, 2)
	var refused: Dictionary = ((w.orders.counters().get("t%d" % team, {}) as Dictionary).get(OrderKinds.DEPUTY, {"refused": {}}) as Dictionary)["refused"]
	_check("away: a word that is no preset is refused and changes nothing", d.preset == "off" and w.admiral_ai[team] == null and int(refused.get("value", 0)) == 1, str(refused))
	_drop(w)


## The replay property, and a match whose deputy is never made.
func _replay_cases() -> void:
	var ticks := []
	for run in 2:
		var w := _new_world(true)
		var d := _dep(w)
		_step(w, 100)
		_human_drone(w)
		var first := -1
		for t in 2100:
			w._physics_process(1.0 / 60.0)
			if d.away and first < 0:
				first = w.tick_count
		ticks.append(first)
		_drop(w)
	_check("replay: the same scripted input switches the deputy on at the same tick twice (%s)" % str(ticks), ticks[0] == ticks[1] and ticks[0] == 100 + 1 + Absence.AWAY_TICKS, str(ticks))
	# A deputy that is never made sends nothing.
	var w2 := _new_world(true)
	var team := w2.human_team
	var d2 := _dep(w2)
	for t in 1700:
		if t % 500 == 0:
			_human_drone(w2)
		w2._physics_process(1.0 / 60.0)
	var counts := w2.orders.counters()
	var row: Dictionary = (counts.get("t%d" % team, {}) as Dictionary)
	_check("replay: with no deputy made the human team's counters hold only the scripted drone orders", row.keys() == [OrderKinds.DRONE] and int((row[OrderKinds.DRONE] as Dictionary)["submitted"]) == 4, str(row))
	_check("replay: and the deputy sent nothing", d2.preset == "off" and _seat_total(team, OrderKinds.DEPUTY_SEAT) == 0)
	_drop(w2)


## The marks the lists show: the seat-open alert has its words, a refusal of the deputy's order is an alert of its own
## that says "deputy", the build list's row tag reads the seat of the item when the snapshot holds it.
func _marks_cases() -> void:
	var al := AlertList.new(0)
	var open := al.on_event({"kind": "seat_open", "team": 0, "pos": null, "uid": 0, "data": {"seat": Rules.ADMIRAL_SEAT, "ticks": 5400}}, 100)
	_check("marks: the seat-open event is an alert with its own words", not open.is_empty() and str(open["text"]) == "Seat open" and int(open["priority"]) == 9)
	var human := al.on_event({"kind": "order_refused", "team": 0, "pos": null, "uid": 0, "data": {"seat": Rules.ADMIRAL_SEAT, "reason": "money", "kind": "DRONE"}}, 200)
	var deputy := al.on_event({"kind": "order_refused", "team": 0, "pos": null, "uid": 0, "data": {"seat": OrderKinds.DEPUTY_SEAT, "reason": "money", "kind": "DRONE"}}, 210)
	_check("marks: a refusal of the deputy's order is an alert apart from the human's with the same reason", not human.is_empty() and not deputy.is_empty() and human["key"] != deputy["key"] and int(deputy["seat"]) == OrderKinds.DEPUTY_SEAT and int(human["seat"]) == Rules.ADMIRAL_SEAT, "%s | %s" % [str(human.get("key")), str(deputy.get("key"))])
	var feed := AlertFeed.new()
	_check("marks: the alert list says \"deputy\" on the deputy's refusal and not on the human's", feed.alert_text(deputy).contains("(deputy)") and feed.alert_text(deputy).begins_with("Order refused: money") and not feed.alert_text(human).contains("deputy"), "%s | %s" % [feed.alert_text(deputy), feed.alert_text(human)])
	_check("marks: the seat-open alert reads plainly", feed.alert_text(open) == "Seat open", feed.alert_text(open))
	feed.free()
	_check("marks: the build list's row tag says deputy for the deputy's seat only", ProductionRow.seat_tag({"seat": OrderKinds.DEPUTY_SEAT}).contains("deputy") and ProductionRow.seat_tag({"seat": Rules.ADMIRAL_SEAT}) == "" and ProductionRow.seat_tag({}) == "")


## After a mutiny the team has a computer Admiral and the human sits as a pilot: the deputy must issue no order and must
## not replace the new Admiral, whether it was away or not. The swap is done by hand as Mutiny.swap does it for a human
## Admiral (the team's admiral kind, the human role and a fresh AdmiralAI), because the mutiny rule is off in this match.
func _mutiny_cases() -> void:
	# The human gave an order (not away), the chair passes, then 1,900 ticks of silence: no switch-on, nobody replaced.
	var w := _new_world(true)
	var team := w.human_team
	var d := _dep(w)
	_step(w, 100)
	_human_drone(w)
	_step(w, 5)
	var fresh := _mutiny_swap(w, team)
	_step(w, 1900)
	_check("mutiny: the deputy of a mutinied team does not switch on at the end of the silence", d.preset == "off" and not d.away, "%s %s" % [d.preset, str(d.away)])
	_check("mutiny: the new computer Admiral keeps the chair and has no deputy", w.admiral_ai[team] == fresh and fresh.deputy == null)
	_check("mutiny: the deputy issued no order", _seat_total(team, OrderKinds.DEPUTY_SEAT) == 0, str(_kinds(team, OrderKinds.DEPUTY_SEAT)))
	_drop(w)
	# The deputy was away and on when the chair passed: it hands nothing back and replaces nothing.
	w = _new_world(true)
	team = w.human_team
	d = _dep(w)
	_step(w, 1801)
	var before := _seat_total(team, OrderKinds.DEPUTY_SEAT)
	_check("mutiny: (second match) the deputy is away and on before the chair passes", d.away and d.preset == "balanced")
	fresh = _mutiny_swap(w, team)
	_human_drone(w)
	_step(w, 600)
	_check("mutiny: the new computer Admiral stays after the old deputy's human acts, and the deputy sent no more orders", w.admiral_ai[team] == fresh and fresh.deputy == null and _seat_total(team, OrderKinds.DEPUTY_SEAT) == before, "%d against %d" % [_seat_total(team, OrderKinds.DEPUTY_SEAT), before])
	_drop(w)
	# The order of the human after the chair passed, through the queue and by hand: the deputy must change nothing.
	_mutiny_order_case(false, false)
	_mutiny_order_case(true, false)
	_mutiny_order_case(false, true)
	_mutiny_order_case(true, true)


## Do what Mutiny.swap does on a human Admiral's team (the admiral kind, the human's role, a fresh computer Admiral);
## returns the new Admiral.
func _mutiny_swap(w: World, team: int) -> AdmiralAI:
	var ts: TeamState = w.teams[team]
	ts.admiral = "ai"
	ts.admiral_docked = true
	var fresh := AdmiralAI.new(w, team)
	w.admiral_ai[team] = fresh
	w.human_role = "pilot"
	return fresh


## One match of the order cases after a mutiny: the chair passes to a new computer Admiral (_mutiny_swap) and then the human
## sends the DEPUTY order "attack", through the order queue (a player's only way) or, with `direct`, by calling the deputy's
## handler by hand. `away_before` makes the deputy on and away before the swap (else it is off and the human is present).
## The deputy's words must stay as they were (preset "balanced" when it was away, else "off"; chosen "off"; remembered
## "balanced"), the new Admiral keeps the chair with no deputy, and the handler called by hand answers with the seat text.
func _mutiny_order_case(away_before: bool, direct: bool) -> void:
	var tag := "mutiny: %s order, deputy %s before the swap:" % ["direct" if direct else "queued", "on and away" if away_before else "off"]
	var w := _new_world(true)
	var team := w.human_team
	var d := _dep(w)
	if away_before:
		_step(w, 1801)
		_check("%s the deputy is away and on before the chair passes" % tag, d.away and d.preset == "balanced")
	else:
		_step(w, 100)
		_human_drone(w)
		_step(w, 5)
		_check("%s the deputy is off and the human is present before the chair passes" % tag, d.preset == "off" and not d.away)
	var fresh := _mutiny_swap(w, team)
	var answer := ""
	if direct:
		answer = d.apply_order({"settings": {"preset": "attack"}})
	else:
		_human_deputy(w, "attack")
		_step(w, 2)
	var want := "balanced" if away_before else "off"
	var kept: bool = w.admiral_ai[team] == fresh and fresh.deputy == null and d.preset == want and d.chosen == "off" and d.remembered == "balanced"
	_check("%s the new Admiral keeps the chair with no deputy, and the deputy's preset, chosen and remembered words stay (%s, off, balanced)" % [tag, want], kept, "preset %s, chosen %s, remembered %s, deputy of the Admiral: %s" % [d.preset, d.chosen, d.remembered, str((w.admiral_ai[team] as AdmiralAI).deputy)])
	if direct:
		_check("%s the handler answers with the seat text" % tag, answer == OrderKinds.TEXT_SEAT, answer)
	_drop(w)


## The feature hooks that are the human seat's own buttons and calls (the command assets, Fortify, the smart composition
## calls) act for a computer Admiral and for a deputy only while the human is away; the bounties act for a computer
## Admiral that is no deputy; the wards and the doctrine research are building and research and act for a deputy always.
## One match with the variants on: the deputy on with Balanced, first PRESENT (the human gives a drone order every 600
## ticks), then AWAY (2,000 ticks with no input). Each hook is read by what it does: a timer that moves only when its hook
## acts (read twice, 90 ticks apart; it counts as moved only when the two reads differ), Fortify by firing at a mothership
## that loses 6 percent of its hull in one step, the bounty think by the bounties it posts in one call. The computer
## team is the positive control in every row (it must act in both phases). The doctrine research has no timer that shows
## its gate, so it is pinned by AdmiralWeak.ai_acts (a function pin, not a behaviour read).
func _hook_cases() -> void:
	var saved: Dictionary = Game.variants.duplicate()
	Game.variants["orders"] = "on"
	Game.variants["assets"] = "on"
	Game.variants["fortify"] = "on"
	Game.variants["doctrine"] = "on"
	Game.variants["admiral_smart"] = "on"
	Game.variants["admiral_sinks"] = "fleet"
	var w := _new_world(true)
	Game.variants = saved
	var team := w.human_team
	var other := 1 - team
	var f := _hook_features(w)
	_check("hooks: the five features are installed with their variants on", f.size() == 5)
	if f.size() < 5:
		_drop(w)
		return
	var orders: AdmiralOrdersFeature = f["orders"]
	_human_deputy(w, "balanced")
	_hook_money(w)
	for i in 4:
		_human_drone(w)
		_step(w, 600)
	var d := _dep(w)
	_check("hooks: the deputy is on with Balanced, its Admiral has it and the human is present", d.preset == "balanced" and not d.away and w.admiral_ai[team] != null and (w.admiral_ai[team] as AdmiralAI).deputy == d)
	# A diagnostic, no check: what stops the old style of bounty think (the treasury, the live bounties, the cooldown, the lane).
	_bounty_diag(w, orders, team)
	_bounty_diag(w, orders, other)
	_hook_phase(w, f, "present")
	# The human's last input is now a few hundred ticks old; 2,000 ticks of silence put the deputy away.
	_step(w, 2000)
	_check("hooks: after 2,000 ticks with no input the deputy is away", d.away)
	_hook_phase(w, f, "away")
	_drop(w)


## One phase of the hook cases in match `w` (`phase` is "present" or "away"): every row reads the deputy's team against the
## computer's. In the present phase a human drone order goes in right before each read and a read taken with the deputy
## away is a FAIL line ("not measured"), never counted as "not moved". In the away phase the deputy must be away.
func _hook_phase(w: World, f: Dictionary, phase: String) -> void:
	var team := w.human_team
	var other := 1 - team
	var d := _dep(w)
	var present := phase == "present"
	var orders: AdmiralOrdersFeature = f["orders"]
	# The timers: the smart admiral's call timer, the assets part's think timer, the sinks' ward timer.
	if present:
		_human_drone(w)
	_hook_money(w)
	var mv := _hook_moves(w, f)
	var measured := _hook_measured(d, present, phase + " timers")
	if measured:
		var a: Array = mv[team]
		var c: Array = mv[other]
		_check("hooks: %s: the computer team's three timers (call, assets, wards) all move (%s)" % [phase, str(c)], bool(c[0]) and bool(c[1]) and bool(c[2]))
		_check("hooks: %s: the smart admiral's call timer %s for the deputy's team (%s)" % [phase, "does not move" if present else "moves", str(a)], (not bool(a[0])) if present else bool(a[0]))
		_check("hooks: %s: the assets part's think timer %s for the deputy's team (%s)" % [phase, "does not move" if present else "moves", str(a)], (not bool(a[1])) if present else bool(a[1]))
		_check("hooks: %s: the sinks' ward timer moves for the deputy's team, no gate (%s)" % [phase, str(a)], bool(a[2]))
	# Fortify.
	if present:
		_human_drone(w)
	_hook_money(w)
	var fired := _fortify_fired(w, f)
	measured = _hook_measured(d, present, phase + " fortify")
	if measured:
		_check("hooks: %s: Fortify fires for the computer team at a 6 percent hull loss (the control)" % phase, bool(fired[other]))
		_check("hooks: %s: Fortify %s for the deputy's team at the same loss" % [phase, "does not fire" if present else "fires"], (not bool(fired[team])) if present else bool(fired[team]))
	# The doctrine research: a function pin.
	_check("hooks: %s: the doctrine research is not gated for the deputy's team (function pin: AdmiralWeak.ai_acts)" % phase, AdmiralWeak.ai_acts(w, team) and AdmiralWeak.ai_acts(w, other))
	# The bounty: the control first, then the deputy's team posts nothing (present and away).
	if present:
		_human_drone(w)
	var ctl := _bounty_posts(w, orders, other)
	_check("hooks: %s: the bounty think of the computer team posts one bounty (the control; posted %d, live %d)" % [phase, int(ctl[0]), int(ctl[1])], int(ctl[0]) == 1 and int(ctl[1]) == 1)
	var dep := _bounty_posts(w, orders, team)
	measured = _hook_measured(d, present, phase + " bounty")
	if measured:
		_check("hooks: %s: the bounty think of the deputy's team posts nothing (posted %d, live %d)" % [phase, int(dep[0]), int(dep[1])], int(dep[0]) == 0 and int(dep[1]) == 0)


## Is the human still in the state the phase needs ("present": not away; "away": away)? A FAIL line when not: the read is
## then not measured and nothing is counted as "not moved".
func _hook_measured(d: Deputy, present: bool, what: String) -> bool:
	var ok := (not d.away) if present else d.away
	_check("hooks: %s: the read was taken with the human %s (a read taken otherwise is not measured)" % [what, "present" if present else "away"], ok)
	return ok


## Give both teams plenty of money (the hooks think only with a treasury, and the deputy spends its own).
func _hook_money(w: World) -> void:
	for t in 2:
		(w.teams[t] as TeamState).treasury = 20000.0


## The features whose AI parts the hook cases watch, found through the match's tick hooks: "sinks", "smart", "orders",
## "assets" and "fortify" (one that is not installed is missing from the answer).
func _hook_features(w: World) -> Dictionary:
	var f := {}
	for h: Callable in w.tick_hooks:
		var o: Object = h.get_object()
		if o is AdmiralSinksFeature:
			f["sinks"] = o
		elif o is AdmiralSmartFeature:
			f["smart"] = o
		elif o is AdmiralOrdersFeature:
			f["orders"] = o
		elif o is AdmiralAssetsFeature:
			f["assets"] = o
		elif o is FortifyFeature:
			f["fortify"] = o
	return f


## The three timers that show a hook acting for `team`: the smart admiral's call timer, the assets part's think timer and
## the sinks' ward timer.
func _hook_timers(f: Dictionary, team: int) -> Array:
	var smart: AdmiralSmartFeature = f["smart"]
	var assets: AdmiralAssetsFeature = f["assets"]
	var sinks: AdmiralSinksFeature = f["sinks"]
	var part: AdmiralAssetsAI = assets.ai[team]
	return [float((smart._call_t as Array)[team]), part.think_t, float((sinks._ward_t as Array)[team])]


## Read both teams' timers, step 90 ticks, read again: per team, which of the three timers moved (the two reads differ).
func _hook_moves(w: World, f: Dictionary) -> Array:
	var a0 := _hook_timers(f, 0)
	var a1 := _hook_timers(f, 1)
	_step(w, 90)
	var b0 := _hook_timers(f, 0)
	var b1 := _hook_timers(f, 1)
	var out: Array = [[], []]
	for i in 3:
		(out[0] as Array).append(a0[i] != b0[i])
		(out[1] as Array).append(a1[i] != b1[i])
	return out


## Did Fortify fire for each team at a 6 percent hull loss? Per team: the cooldown is made ready, the mothership's hull is
## set to full, 7 s pass (the hull log is flat), the end time is read, the hull drops by 6 percent of its maximum in one
## step (over the 4 percent in 5 s of the first trigger), 3 s pass and the end time is read again. Returns [team 0 fired,
## team 1 fired].
func _fortify_fired(w: World, f: Dictionary) -> Array:
	var fort: FortifyFeature = f["fortify"]
	for t in 2:
		CommandOrders.reset_cooldown(w, "fortify", t)
		var ms0 := w.mothership(t)
		ms0.hull = ms0.hull_max
	_step(w, 420)
	var before: Array = [float(fort.until[0]), float(fort.until[1])]
	for t in 2:
		var ms1 := w.mothership(t)
		ms1.hull = ms1.hull_max * 0.94
	_step(w, 180)
	return [float(fort.until[0]) != float(before[0]), float(fort.until[1]) != float(before[1])]


## One bounty think of `team` with the five conditions set again right before it (both treasuries 20,000, the siege lane set
## to the lane of a built enemy turret that the team has seen, the bounty order ready, no live bounty, the think timer at
## zero). Returns [the bounties posted by that one call, the team's live bounties after it]; [-1, -1] when the match has
## no such turret.
func _bounty_posts(w: World, orders: AdmiralOrdersFeature, team: int) -> Array:
	_hook_money(w)
	var target: Turret = null
	for tu: Turret in w.turrets:
		if tu.team == 1 - team and tu.alive and tu.is_built() and tu.node != null and tu.node.lane != "":
			target = tu
			break
	if target == null:
		return [-1, -1]
	target.seen_mask |= 1 << team
	var ts := w.teams[team] as TeamState
	var lane_was := ts.siege_lane
	ts.siege_lane = target.node.lane
	CommandOrders.reset_cooldown(w, "bounty", team)
	orders.bounties = []
	orders._ai_t[team] = 0.0
	var before := int(Game.usage.get("bounties_posted", 0))
	orders._ai_think(team)
	var posted := int(Game.usage.get("bounties_posted", 0)) - before
	var live := orders.active_count(team)
	ts.siege_lane = lane_was
	return [posted, live]


## A diagnostic, not a check (it never prints a FAIL line): the old style of bounty think of `team` (only the think timer set
## to zero), with what could stop it printed right before: the treasury against the AI's minimum, the live bounties, the
## bounty order's cooldown, the siege lane (or the push lane) and the built enemy turrets seen on it, and how many bounties the
## call posted. The lines say which return of the think the old case took.
func _bounty_diag(w: World, orders: AdmiralOrdersFeature, team: int) -> void:
	var ts := w.teams[team] as TeamState
	var ai := w.admiral_ai[team] as AdmiralAI
	var lane := ts.siege_lane
	if lane == "" and ai != null:
		lane = ai.lanes.push_lane()
	var seen := 0
	for tu: Turret in w.turrets:
		if tu.team == 1 - team and tu.alive and tu.is_built() and tu.node != null and tu.node.lane == lane and (tu.seen_mask & (1 << team)) != 0 and not orders.has_bounty(tu):
			seen += 1
	print("deputy_check: diag old-style bounty think, team %d: treasury %d (minimum %d), live bounties %d, bounty ready in %.1f s, lane \"%s\" (siege lane \"%s\"), seen built enemy turrets on it %d" % [team, int(ts.treasury), int(AdmiralOrdersFeature.AI_MIN_TREASURY), orders.active_count(team), CommandOrders.ready_in(w, "bounty", team), lane, ts.siege_lane, seen])
	var before := int(Game.usage.get("bounties_posted", 0))
	orders._ai_t[team] = 0.0
	orders._ai_think(team)
	print("deputy_check: diag old-style bounty think, team %d: posted %d" % [team, int(Game.usage.get("bounties_posted", 0)) - before])


## The seat rules: the computer's seat per team, the orders cap, what the deputy's seat may send.
func _seat_cases() -> void:
	var w := _new_world(true)
	var team := w.human_team
	var other := 1 - team
	_check("seat: a computer order on the human team has the deputy's seat", Deputy.computer_seat(w, team) == OrderKinds.DEPUTY_SEAT)
	_check("seat: on a team with a computer Admiral it is the Admiral's seat (nothing changes there)", Deputy.computer_seat(w, other) == Rules.ADMIRAL_SEAT)
	for kind: String in [OrderKinds.WAYPOINT, OrderKinds.SIEGE, OrderKinds.MOTHERSHIP_MOVE, OrderKinds.DEPUTY]:
		_check("seat: the deputy's seat may not send %s" % kind, not OrderKinds.may_send(kind, OrderKinds.DEPUTY_SEAT))
	for kind: String in [OrderKinds.DRONE, OrderKinds.RESEARCH, OrderKinds.MODULE, OrderKinds.PRODUCE]:
		_check("seat: the deputy's seat may send %s" % kind, OrderKinds.may_send(kind, OrderKinds.DEPUTY_SEAT))
	# The outbox's orders cap counts the computer's own seat only.
	var prof := AdmiralProfile.make("standard", team)
	var ob_h := AdmiralOutbox.new(w, team, prof)
	var ob_c := AdmiralOutbox.new(w, other, AdmiralProfile.make("standard", other))
	for i in 3:
		w.events_rts.push({"kind": "order_done", "team": team, "data": {"seat": Rules.ADMIRAL_SEAT, "id": 100 + i}})
		w.events_rts.push({"kind": "order_done", "team": other, "data": {"seat": Rules.ADMIRAL_SEAT, "id": 200 + i}})
	for i in 2:
		w.events_rts.push({"kind": "order_refused", "team": team, "data": {"seat": OrderKinds.DEPUTY_SEAT, "id": 300 + i}})
		w.events_rts.push({"kind": "order_refused", "team": other, "data": {"seat": OrderKinds.DEPUTY_SEAT, "id": 400 + i}})
	ob_h._read()
	ob_c._read()
	_check("seat: the human team's cap counts the 2 deputy orders and not the human's 3 (%d)" % ob_h._load(), ob_h._load() == 2)
	_check("seat: a computer team's cap counts its 3 Admiral-seat orders and not 2 of the deputy seat (%d)" % ob_c._load(), ob_c._load() == 3)
	# The decision log hears the deputy's orders on the human team (the deputy is on) and not the human's own.
	_human_deputy(w, "balanced")
	_step(w, 3)
	var lg := AdmiralLog.new(w)
	lg.enabled = true
	var before := lg.order_lines
	lg._on_event({"kind": "order_done", "team": team, "tick": w.tick_count, "data": {"seat": Rules.ADMIRAL_SEAT, "id": 500, "kind": "DRONE"}})
	_check("seat: the decision log skips the human's own order on the human team", lg.order_lines == before)
	lg._on_event({"kind": "order_done", "team": team, "tick": w.tick_count, "data": {"seat": OrderKinds.DEPUTY_SEAT, "id": 501, "kind": "DRONE"}})
	_check("seat: and writes the deputy's", lg.order_lines == before + 1, "%d lines after %d" % [lg.order_lines, before])
	lg.enabled = false
	_drop(w)


# --- the card and the strip -------------------------------------------------------------------------------------

## Wait `n` frames (the launched match ticks meanwhile).
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait until the deputy of the launched match runs `want` (at most 60 frames); returns whether it does.
func _wait_preset(d: Deputy, want: String) -> bool:
	for i in 60:
		if d.preset == want:
			return true
		await get_tree().process_frame
	return d.preset == want


## The build list's rows (the launched match, the HUD up): a ship the deputy's seat bought reads "deputy" in the row's
## mark and one the human's seat bought reads nothing; the panel's snapshot is what the row is drawn from.
func _build_list_cases(view: CommandView) -> void:
	var prod := (world.teams[world.human_team] as TeamState).production
	var panel := view.prod
	var dep_item := prod.add_ship("fighter", 1, OrderKinds.DEPUTY_SEAT)
	var own_item := prod.add_ship("bomber", 1, Rules.ADMIRAL_SEAT)
	var dep_row := {}
	var own_row := {}
	for e: Dictionary in panel._build_entries(prod):
		var snap: Dictionary = panel._snapshot(prod, e, {})
		if str(dep_item["id"]) in (e["ids"] as Array):
			dep_row = snap
		elif str(own_item["id"]) in (e["ids"] as Array):
			own_row = snap
	_check("ui: a deputy-placed order's build-list row reads deputy", not dep_row.is_empty() and int(dep_row.get("seat", Rules.ADMIRAL_SEAT)) == OrderKinds.DEPUTY_SEAT and ProductionRow.seat_tag(dep_row).contains("deputy"), str(dep_row))
	_check("ui: the human's own order's build-list row reads no deputy mark", not own_row.is_empty() and ProductionRow.seat_tag(own_row) == "", str(own_row))


## The card's Deputy and Dep. mode cells and the strip's deputy button, in the launched match: a press on the Deputy cell
## switches the deputy on and off, the Dep. mode cell steps the four presets in order, the strip follows and the cells say
## the preset. Then the summary line.
func _ui_cases(hud: Hud) -> void:
	await _frames(40)
	hud._close_others(null)
	var view := hud.command_view
	var d: Deputy = world.orders.deputy
	if d == null or world.human_role != "admiral" or not view.is_showing():
		_check("ui: an Admiral seat with the command view showing and a deputy", false)
	else:
		var card := view.card
		card.set_page("base")
		card.refresh()
		view.refresh()
		var strip: Button = view.strip._b["deputy"]
		_check("ui: the strip says exactly DEPUTY off while the deputy is off", strip.text == "DEPUTY off", strip.text)
		_check("ui: the Deputy cell is not lit and says Off", not bool(CardState.snapshot(card, "base", "deputy").get("picked", false)) and str(CardState.snapshot(card, "base", "deputy")["sub"]) == "Off")
		CardActions.run(card, "base", "deputy")
		_check("ui: a press on the Deputy cell answers on the result line", view.overlay.result_text == "Deputy: Balanced", view.overlay.result_text)
		_check("ui: the deputy is on with Balanced after the order is carried out", await _wait_preset(d, "balanced"), d.preset)
		view.refresh()
		_check("ui: the strip reads Deputy: Balanced", strip.text == "Deputy: Balanced", strip.text)
		card.refresh()
		var on_cell := CardState.snapshot(card, "base", "deputy")
		_check("ui: the Deputy cell is lit and says Balanced", bool(on_cell.get("picked", false)) and str(on_cell["sub"]) == "Balanced", str(on_cell))
		CardActions.run(card, "base", "deputy")
		_check("ui: a second press switches it off", await _wait_preset(d, "off"), d.preset)
		view.refresh()
		_check("ui: and the strip is back to exactly DEPUTY off", strip.text == "DEPUTY off", strip.text)
		var seen: Array = []
		for i in 4:
			CardActions.run(card, "base", "deputy_preset")
			var want: String = AdmiralProfileData.PRESET_NAMES[(i + 1) % 4]
			seen.append(want if await _wait_preset(d, want) else d.preset)
		_check("ui: the preset cell steps attack, defend, economy, balanced and turns the deputy on", seen == ["attack", "defend", "economy", "balanced"], str(seen))
		card.refresh()
		_check("ui: the preset cell says the preset in force", str(CardState.snapshot(card, "base", "deputy_preset")["sub"]) == "Balanced")
		strip.pressed.emit()
		_check("ui: a click on the strip's deputy button switches it off", await _wait_preset(d, "off"), d.preset)
		strip.pressed.emit()
		_check("ui: and on again with the preset last used", await _wait_preset(d, "balanced"), d.preset)
		strip.pressed.emit()
		await _wait_preset(d, "off")
		_build_list_cases(view)
	print("deputy_check: %d failures (%d checks)" % [_fails, _checks])
	get_tree().quit()
