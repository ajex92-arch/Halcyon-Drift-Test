extends Node
## WHAT THIS IS: the alert probe, RT6's gate on the alert feed's rules of order (DESIGN.md section 10, "Probe"): the
## priority order, merging by cell, a lost squadron folding its "under attack" row away, the order the jump key steps
## in, the round after eight steps, Back (Shift+J), and that alerts stop ageing in the command pause.
##
## HOW IT WORKS: setup() waits for the HUD and takes the feed out of its own beat (set_process(false)), so the probe is
## the only thing that polls and refreshes. Each part empties the team's alert list, raises its own alerts (straight
## into the list with AlertList.on_event(), or through the real rules and the combat code for the fold), then reads the
## list, the feed's rows and the camera. The keys go to the feed's own input handler. It prints a FAIL line for every
## check that does not hold, then "alert_probe: N failures (M checks)" (0 failures is a pass).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=alert_probe
##
## WHO USES IT: main.gd loads it for --test=alert_probe (it calls setup()); the lead's run_checks list.

## The running match, its HUD, the feed and the camera.
var world: World
var hud: Hud
var feed: AlertFeed
var cam: CameraRig
## The team the Admiral commands.
var team := 0
## How many checks were made and how many failed.
var checks := 0
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## `n` ticks pass (physics frames; none of them is a World tick while the match is held paused).
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## The whole probe.
func _run() -> void:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.command_view != null and hud.command_view.alert_feed != null:
			break
		await _tick()
	_check("the HUD and the feed exist (use --force-hud --role=admiral)", hud != null and world.human_role == "admiral")
	if hud == null or hud.command_view == null or hud.command_view.alert_feed == null:
		_finish()
		return
	team = world.human_team
	feed = hud.command_view.alert_feed
	cam = world.camera
	feed.set_process(false)
	await _tick(3)
	await _fold()
	_priority()
	_merging()
	_jump_order()
	await _paused()
	_finish()


## Print the result line and end the run.
func _finish() -> void:
	print("alert_probe: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------------------------

## The alert list of our team.
func _list() -> AlertList:
	return world.alerts[team] as AlertList


## Empty the list (the live alerts and the expired ones) and end any jump chain.
func _clear() -> void:
	_list()._live.clear()
	_list().recent.clear()
	feed._has_origin = false
	feed._step = -1


## Raise one alert of `kind` at `pos` straight into the list, as raised at `tick`.
func _raise(kind: String, pos: Variant, tick: int, data: Dictionary = {}) -> Dictionary:
	return _list().on_event({"kind": kind, "team": team, "pos": pos, "data": data}, tick)


## The live alerts of `kind`.
func _live_of(kind: String) -> Array:
	return _list().live(world.tick_count).filter(func(a: Dictionary) -> bool: return a["kind"] == kind)


## The feed's rows on show.
func _shown() -> Array:
	return feed._rows.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)


## A key press of key text `text` (modifiers included) as the feed's input handler sees it.
func _press(text: String) -> void:
	var ev := KeyCodes.make_event(text) as InputEventKey
	ev.pressed = true
	feed._unhandled_input(ev)


## Put the free camera at `p`.
func _camera_at(p: Vector2) -> void:
	cam.free = true
	cam.global_position = p
	cam._free_pos = p


## A new bought squadron of `n` crew ships of hull "fighter", beside our mothership (as tests/alert_feed_check.gd makes one).
func _squad(n: int) -> Squad:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = "squadron"
	s.hull_id = "fighter"
	s.max_members = 3
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	for i in n:
		var p := Crew.make(world, team, "fighter", s, s.member_uids.size())
		world.profiles.append(p)
		var ms := world.mothership(team)
		var ship := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def("fighter")["radius"])), ms.rotation)
		ship.controller = null
		ship.velocity = Vector2.ZERO
		p.ship = ship
		p.state = "flying"
		s.member_uids.append(ship.uid)
	return s


## The killing blow of a turret of the other team.
func _blow() -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = 1.0
	d.kind = Rules.W_PURE
	d.source_uid = 91997
	d.source_team = 1 - team
	return d


# --- lost folds attack ---------------------------------------------------------------------------------

## Through the real rules: a hit squadron is "under attack"; when its last ship dies the row gives way to "lost".
func _fold() -> void:
	_clear()
	var squad := _squad(2)
	await _tick(2)
	feed.rules.poll()
	await _tick(2)
	var a := world.by_uid[squad.member_uids[0]] as Ship
	a.last_hull_damage_time = world.time
	feed.rules.poll()
	var hit := _live_of("squadron_under_attack")
	_check("fold: a hit squadron has one under-attack row", hit.size() == 1, str(hit.size()))
	world.combat.kill(world.by_uid[squad.member_uids[0]] as Unit, _blow())
	feed.rules.poll()
	_check("fold: one ship lost of two keeps the under-attack row and raises no squadron lost", _live_of("squadron_under_attack").size() == 1 and _live_of("squadron_lost").is_empty())
	for uid: int in squad.member_uids.duplicate():
		if world.by_uid.has(uid):
			world.combat.kill(world.by_uid[uid] as Unit, _blow())
	feed.rules.poll()
	var lost := _live_of("squadron_lost")
	_check("fold: the last ship's death raises one squadron lost", lost.size() == 1 and int(lost[0]["count"]) == 1, str(lost))
	_check("fold: the under-attack row is gone", _live_of("squadron_under_attack").is_empty())
	_check("fold: the folded row is not kept in Recent either", _list().recent.all(func(r: Dictionary) -> bool: return r["kind"] != "squadron_under_attack"))
	feed.refresh()
	var kinds := PackedStringArray()
	for r: AlertFeed.AlertRow in _shown():
		kinds.append(str(r.alert["kind"]))
	_check("fold: the feed shows the lost row and no under-attack row", kinds.has("squadron_lost") and not kinds.has("squadron_under_attack"), ", ".join(kinds))
	# The list's own fold: only the cell of the loss is dropped.
	_clear()
	var t := world.tick_count
	_raise("squadron_under_attack", Vector2i(3000, 3000), t)
	_raise("squadron_under_attack", Vector2i(9000, 3000), t)
	_list().drop_in_cell("squadron_under_attack", Vector2i(3500, 3900))
	var left := _live_of("squadron_under_attack")
	_check("fold: only the under-attack row of the lost squadron's cell is dropped", left.size() == 1 and left[0]["pos"] == Vector2i(9000, 3000), str(left))


# --- the priority order --------------------------------------------------------------------------------

## Every kind raised out of order comes back most important first, then newest first; the feed shows the top five.
func _priority() -> void:
	_clear()
	var t := world.tick_count
	# Raised out of order, each in its own cell and at its own tick (t - 20 is the oldest).
	var raised := [
		["ship_under_fire", Vector2i(21000, 21000)], ["research_done", null], ["squadron_idle", Vector2i(1000, 21000)], ["ship_lost", Vector2i(5000, 1000)],
		["order_refused", Vector2i(9000, 1000)], ["squadron_under_attack", Vector2i(13000, 1000)], ["build_done", Vector2i(17000, 1000)],
		["mothership_under_attack", Vector2i(1000, 5000)], ["cap_full", Vector2i(5000, 5000)], ["structure_under_attack", Vector2i(9000, 5000)],
		["turret_lost", Vector2i(13000, 5000)], ["pilot_request", Vector2i(17000, 5000)], ["seat_open", null], ["module_done", null],
		["squadron_lost", Vector2i(1000, 9000)], ["post_lost", Vector2i(5000, 9000)],
	]
	for i in raised.size():
		var kind := str(raised[i][0])
		var data := {"reason": "money"} if kind == "order_refused" else {}
		if kind == "post_lost":
			_list().on_event({"kind": "post_state", "team": team, "pos": raised[i][1], "data": {"state": PostSite.DESTROYED}}, t - 20 + i)
		else:
			_raise(kind, raised[i][1], t - 20 + i, data)
	var live := _list().live(t)
	_check("priority: all 16 kinds of the list are alive", live.size() == AlertList.KINDS.size() and live.size() == 16, str(live.size()))
	var sorted := true
	var newest_first := true
	for i in range(1, live.size()):
		var p0 := int(live[i - 1]["priority"])
		var p1 := int(live[i]["priority"])
		sorted = sorted and p0 <= p1
		if p0 == p1:
			newest_first = newest_first and int(live[i - 1]["raised"]) > int(live[i]["raised"])
	_check("priority: the most important first (1 to 10)", sorted and str(live[0]["kind"]) == "mothership_under_attack" and str(live[live.size() - 1]["kind"]) == "squadron_idle")
	_check("priority: the priority of each alert is its kind's", live.all(func(a: Dictionary) -> bool: return int(a["priority"]) == int((AlertList.KINDS[str(a["kind"])] as Dictionary)["priority"])))
	_check("priority: the same priority, the newest raised first", newest_first)
	var order := PackedStringArray()
	for a: Dictionary in live.slice(0, 7):
		order.append(str(a["kind"]))
	_check("priority: mothership, under fire (raised first, so after it), squadron, structure, then the losses newest first", ",".join(order) == "mothership_under_attack,ship_under_fire,squadron_under_attack,structure_under_attack,post_lost,squadron_lost,turret_lost", ",".join(order))
	feed.refresh()
	var shown := _shown()
	var rows_ok := shown.size() == RtsUiCalls.ALERT_ROWS
	for i in shown.size():
		rows_ok = rows_ok and (shown[i] as AlertFeed.AlertRow).alert == live[i]
	_check("priority: the feed's five rows are the top five, in that order", rows_ok and RtsUiCalls.ALERT_ROWS == 5, str(shown.size()))
	_check("priority: the rest is counted behind +N older", feed._older.visible and feed._older.text.begins_with("+%d older" % (live.size() - RtsUiCalls.ALERT_ROWS)), feed._older.text)
	_check("priority: the top alert is where a jump goes", _list().jump_pos(t) == Vector2i(1000, 5000))


# --- merging ---------------------------------------------------------------------------------------------

## Ten ships lost in one 2,000-unit cell are one row "Ship lost x10"; another cell, another kind and another reason are rows of their own.
func _merging() -> void:
	_clear()
	var t := world.tick_count
	for i in 10:
		_raise("ship_lost", Vector2i(4000 + i * 150, 4100 + i * 100), t - 10 + i)
	var lost := _live_of("ship_lost")
	_check("merging: ten ships lost in one cell are one alert", lost.size() == 1, str(lost.size()))
	_check("merging: it counts 10 and reads Ship lost x10", int(lost[0]["count"]) == 10 and str(lost[0]["text"]) == "Ship lost x10", str(lost[0]["text"]))
	_check("merging: it sits at the last loss", lost[0]["pos"] == Vector2i(4000 + 9 * 150, 4100 + 9 * 100), str(lost[0]["pos"]))
	_check("merging: a merge renews the life (from the last raise)", int(lost[0]["expires"]) == t - 1 + int((AlertList.KINDS["ship_lost"] as Dictionary)["life"]) and int(lost[0]["raised"]) == t - 10)
	_raise("ship_lost", Vector2i(6100, 4100), t)
	_check("merging: a loss in the next cell is a second row", _live_of("ship_lost").size() == 2)
	_raise("turret_lost", Vector2i(4500, 4500), t)
	_check("merging: another kind in the same cell does not merge", _live_of("ship_lost").size() == 2 and _live_of("turret_lost").size() == 1)
	_raise("order_refused", null, t, {"reason": "money"})
	_raise("order_refused", null, t, {"reason": "money"})
	_raise("order_refused", null, t, {"reason": "room"})
	var refused := _live_of("order_refused")
	_check("merging: refusals merge by reason (money x2, room)", refused.size() == 2, str(refused.size()))
	_raise("mothership_under_attack", Vector2i(1000, 1000), t)
	_raise("mothership_under_attack", Vector2i(15000, 15000), t)
	_check("merging: a team-wide kind is one row wherever it is raised", _live_of("mothership_under_attack").size() == 1 and int(_live_of("mothership_under_attack")[0]["count"]) == 2)
	feed.refresh()
	var found := false
	for r: AlertFeed.AlertRow in _shown():
		if r._text.text.begins_with("Ship lost x10"):
			found = true
	_check("merging: the feed's row reads Ship lost x10 with its place", found)
	# An alert that ended does not take a new raise: the new one is a new row.
	_clear()
	_raise("ship_lost", Vector2i(4000, 4000), t - 5000)
	_raise("ship_lost", Vector2i(4000, 4000), t)
	_check("merging: a raise after the alert ended starts a new alert (count 1)", _live_of("ship_lost").size() == 1 and int(_live_of("ship_lost")[0]["count"]) == 1 and _list().recent.size() == 1)


# --- the jump order, the round after eight, Back --------------------------------------------------------------

## J steps through the live alerts with a place (most important first), then the expired ones (newest first), eight in
## all, then round to the top; Shift+J puts the camera back.
func _jump_order() -> void:
	_clear()
	var t := world.tick_count
	var ts := world.teams[team]
	var docked: bool = ts.admiral_docked
	var was_open := world.board_open
	ts.admiral_docked = true
	world.board_open = false
	# Six ended alerts (the last raised is the newest), then three live ones with a place and one without.
	for i in 6:
		_raise("turret_lost", Vector2i(3000 + i * 4000, 15000), t - 4000 + i)
	_raise("ship_lost", Vector2i(3000, 3000), t - 3)
	_raise("research_done", null, t - 2)
	_raise("squadron_under_attack", Vector2i(9000, 3000), t - 1)
	_raise("mothership_under_attack", Vector2i(15000, 3000), t)
	var want: Array[Vector2] = [Vector2(15000, 3000), Vector2(9000, 3000), Vector2(3000, 3000)]
	for i in 5:
		want.append(Vector2(3000 + (5 - i) * 4000, 15000))
	var alerts := feed.chain()
	_check("jump order: the chain holds eight alerts of the nine with a place", alerts.size() == AlertFeed.CHAIN_MAX and AlertFeed.CHAIN_MAX == 8, str(alerts.size()))
	_check("jump order: an alert with no place is not in the chain", alerts.all(func(a: Dictionary) -> bool: return a["pos"] is Vector2i))
	_check("jump order: six alerts ended and went to Recent", _list().recent.size() == 6)
	var start := Vector2(700.0, 700.0)
	_camera_at(start)
	var went: Array[Vector2] = []
	for i in AlertFeed.CHAIN_MAX:
		_press("J")
		went.append(cam._free_pos)
	_check("jump order: J steps live alerts most important first, then Recent newest first", went == want, "%s want %s" % [str(went), str(want)])
	_check("jump order: the first jump noted where the camera was", feed._has_origin and feed._origin == start)
	_press("J")
	_check("wrap: the ninth press goes round to the top alert", cam._free_pos == want[0] and feed._step == 0, str(cam._free_pos))
	_press("Backspace")
	_check("wrap: Backspace steps on like J", cam._free_pos == want[1], str(cam._free_pos))
	_press("Shift+J")
	_check("back: Shift+J returns the camera to where it was before the chain", cam._free_pos == start and not feed._has_origin, str(cam._free_pos))
	_press("Shift+J")
	_check("back: a second Shift+J does nothing", cam._free_pos == start)
	_press("J")
	_check("back: J after Back starts again at the top", cam._free_pos == want[0] and feed._step == 0)
	_check("back: the Back button does the same", feed.back() and cam._free_pos == start)
	_check("back: the Back key is the design's Shift+J", KeyMap.first_key("home", "alert_back") == "Shift+J" and RtsUiCalls.ALERT_BACK_KEY == "Shift+J")
	ts.admiral_docked = docked
	world.board_open = was_open


# --- the command pause ------------------------------------------------------------------------------------

## In the command pause no tick runs, so an alert's age, its life left and its dimming stand still; the feed reads and
## the jumps work; after the resume the age moves again.
func _paused() -> void:
	_clear()
	var ts := world.teams[team]
	var docked: bool = ts.admiral_docked
	ts.admiral_docked = true
	world.board_open = false
	_raise("squadron_under_attack", Vector2i(9000, 3000), world.tick_count)
	_raise("order_refused", Vector2i(3000, 9000), world.tick_count, {"reason": "money"})
	await _tick(90)
	feed.refresh()
	var rows := _shown()
	_check("paused: two rows before the pause, the first aged 0:01", rows.size() == 2 and (rows[0] as AlertFeed.AlertRow)._age.text == "0:01", str(rows.size()))
	var tick0 := world.tick_count
	var ages0 := PackedStringArray()
	var left0: Array[int] = []
	for a: Dictionary in _list().live(tick0):
		left0.append(int(a["expires"]) - tick0)
	for r: AlertFeed.AlertRow in rows:
		ages0.append(r._age.text)
	hud.panels.toggle_command_pause()
	_check("paused: the command pause holds the match", get_tree().paused and hud.panels.command_paused)
	# Far longer than the refusal's life left (300 ticks less the 90 above): it would end if alerts aged here.
	for i in 400:
		await get_tree().process_frame
	await _tick(30)
	_check("paused: no tick ran", world.tick_count == tick0, "%d then %d" % [tick0, world.tick_count])
	_check("paused: the rules raise nothing new", feed.rules.poll() == 0)
	feed.refresh()
	rows = _shown()
	var live := _list().live(world.tick_count)
	var ages1 := PackedStringArray()
	var left1: Array[int] = []
	for a: Dictionary in live:
		left1.append(int(a["expires"]) - world.tick_count)
	for r: AlertFeed.AlertRow in rows:
		ages1.append(r._age.text)
	_check("paused: both alerts are still alive, none went to Recent", live.size() == 2 and _list().recent.is_empty(), str(live.size()))
	_check("paused: the ages stand still", ages1 == ages0 and ages0.size() == 2, "%s then %s" % [str(ages0), str(ages1)])
	_check("paused: the life left stands still", left1 == left0, "%s then %s" % [str(left0), str(left1)])
	_check("paused: no row dimmed", rows.all(func(r: AlertFeed.AlertRow) -> bool: return not r.dim))
	var start := Vector2(700.0, 700.0)
	_camera_at(start)
	_press("J")
	_check("paused: J jumps to the top alert", cam._free_pos == Vector2(9000.0, 3000.0), str(cam._free_pos))
	_press("J")
	_check("paused: J again steps to the next", cam._free_pos == Vector2(3000.0, 9000.0), str(cam._free_pos))
	_press("Shift+J")
	_check("paused: Shift+J goes back", cam._free_pos == start, str(cam._free_pos))
	hud.panels.toggle_command_pause()
	_check("paused: the second press resumes", not get_tree().paused and not hud.panels.command_paused)
	await _tick(90)
	feed.refresh()
	rows = _shown()
	_check("paused: after the resume the ticks run and the age moves on", world.tick_count >= tick0 + 80 and rows.size() >= 1 and (rows[0] as AlertFeed.AlertRow)._age.text != ages0[0], str(world.tick_count - tick0))
	await _tick(150)
	_check("paused: the refusal then ends at its own time (300 ticks of play)", _live_of("order_refused").is_empty() and _list().recent.size() == 1)
	ts.admiral_docked = docked
