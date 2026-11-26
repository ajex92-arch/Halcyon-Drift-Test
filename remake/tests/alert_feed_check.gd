extends Node
## WHAT THIS IS: the check of RT6's alert feed and order feedback: the alert rules (a squadron or a structure
## under attack, a squadron lost, a build finished, nothing filed in the event stream), the feed's rows (the sort, the
## five-row limit, "+N older", the age, the signs), a click on a row, the jump chain (J, Backspace, J again, the
## eight-step round, Shift+J, a hand-moved camera starting a new chain, a following camera freed and followed
## again), the keys' gates (docked, flying with the board open, flying without it, Ctrl+J), and the order ring and
## the grey x. Since the join of RT6's builds also: the attacked frame (the feed tells the army row which squadrons
## are under attack while the alert lives) and the keys of both routes together (F1 to F8, I, Ctrl+I by the HUD's
## route and J, Backspace, Shift+J by the feed's, sent through the window: each does its own job, and all are quiet
## under the hangar, the help pages, the pause menu and the note box). RT7 build 7c adds: the slim display's three alert rows in
## field mode and the full five with the view open or docked; "Under Fire!" (a hull hit on the human's own ship, and only that, is one
## row reading exactly that text, J reaches it in mode 3, the readout's danger edge is on for 3 s, a shield hit, a squadron, a structure
## or docking give none); and the keys of both modes (J, Backspace and Shift+J do nothing in field mode and work with the view open).
##
## HOW IT WORKS: setup() waits for the HUD, takes the feed out of its own beat (set_process(false)) so this check
## is the only thing that polls, then builds a little fleet of crew ships beside our mothership the way
## tests/crew_check.gd does and drives each part through its real nodes: it marks damage stamps and kills ships through
## the combat code, polls the rules, calls refresh() and reads the rows, sends InputEventKey presses to the feed and
## order answers through the overlay. It prints a FAIL line for every check that does not hold, then
## "alert_feed_check: N failures (M checks)". It also scans alert_rules.gd for anything that would let the rules
## touch the match (an event push, an order, a random draw).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=alert_feed_check
##
## WHO USES IT: main.gd loads it for --test=alert_feed_check (it calls setup()); the lead's run_checks list.

## The running match, its HUD, the feed and the camera.
var world: World
var hud: Hud
var feed: AlertFeed
var cam: CameraRig  # the camera
## The team the Admiral commands.
var team := 0
## How many checks were made and how many failed.
var checks := 0
var fails := 0  # fails


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


## One tick passes.
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## The whole check.
func _run() -> void:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.command_view != null and hud.command_view.alert_feed != null:
			break
		await _tick()
	_check("the HUD and the feed exist (use --force-hud --role=admiral)", hud != null and world.human_role == "admiral")
	if hud == null:
		_finish()
		return
	team = world.human_team
	feed = hud.command_view.alert_feed
	cam = world.camera
	feed.set_process(false)
	await _tick(3)
	_rules()
	await _rules_damage()
	_rows()
	_click()
	_chain()
	_keys()
	await _keys_together()
	_hide()
	await _orders()
	await _field()
	await _under_fire()
	await _dock_back()
	_source_scan()
	_finish()


## Print the result line and end the run.
func _finish() -> void:
	print("alert_feed_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------------------------

## The alert list of our team.
func _list() -> AlertList:
	return world.alerts[team] as AlertList


## The live alerts of `kind`.
func _live_of(kind: String) -> Array:
	return _list().live(world.tick_count).filter(func(a: Dictionary) -> bool: return a["kind"] == kind)


## A new bought squadron of `n` crew ships of hull "fighter", still beside our mothership.
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


## A key press of key text `text` (modifiers included) as the feed's input handler sees it.
func _press(text: String) -> void:
	var ev := KeyCodes.make_event(text) as InputEventKey
	ev.pressed = true
	feed._unhandled_input(ev)


## Poll the rules and count a check that the poll filed no record in the event stream and issued no order.
func _poll(label: String) -> int:
	var total0 := world.events_rts.total
	var ids0 := world.orders.next_id
	var n := feed.rules.poll()
	_check("rules: %s (the poll filed no record and issued no order)" % label, world.events_rts.total == total0 and world.orders.next_id == ids0)
	return n


## Wait ms real milliseconds (the order ring counts real time).
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


## Raise a plain alert through the event stream.
func _event(kind: String, pos: Variant, data: Dictionary = {}) -> void:
	world.events_rts.push({"kind": kind, "team": team, "pos": pos, "data": data})


# --- the rules ----------------------------------------------------------------------------------------

## Build finished, muting, the other team, and the rules leaving the match alone.
func _rules() -> void:
	var rules := feed.rules
	rules.setup(world, team)
	var total0 := world.events_rts.total
	var next0 := world.events_rts.next_index(team)
	var ids0 := world.orders.next_id
	_event("ship_built", Vector2i(3000, 3000), {"item": "fighter", "squad": 0})
	_check("rules: ship_built is not an alert until the rules read it", _live_of("build_done").is_empty())
	var n := rules.poll()
	var built := _live_of("build_done")
	_check("rules: ship_built becomes build_done", n == 1 and built.size() == 1 and built[0]["pos"] == Vector2i(3000, 3000), str(built))
	_list().mute["build_done"] = true
	_event("ship_built", Vector2i(9000, 9000), {"item": "fighter", "squad": 0})
	_check("rules: a muted kind is not raised", rules.poll() == 0 and _live_of("build_done").size() == 1)
	_list().mute.erase("build_done")
	world.events_rts.push({"kind": "ship_built", "team": 1 - team, "pos": Vector2i(5, 5), "uid": 1, "data": {}})
	_check("rules: the other team's build raises nothing for us", rules.poll() == 0 and _live_of("build_done").size() == 1)
	var pushed := world.events_rts.total - total0
	_check("rules: the rules filed no record of their own (only the three the test pushed)", pushed == 3 and world.events_rts.next_index(team) - next0 == 2, "%d, %d" % [pushed, world.events_rts.next_index(team) - next0])
	_check("rules: no order was issued", world.orders.next_id == ids0)


## Squadron under attack, structure under attack, squadron lost folding the attack row away.
func _rules_damage() -> void:
	var rules := feed.rules
	var squad := _squad(2)
	await _tick(2)
	var a := world.by_uid[squad.member_uids[0]] as Ship
	_poll("a first look")
	await _tick(2)
	a.last_hull_damage_time = world.time
	_check("rules: a hit on a squadron ship raises one alert", _poll("a hit on a ship") == 1)
	var hit := _live_of("squadron_under_attack")
	_check("rules: it is a squadron_under_attack with a place and priority 2", hit.size() == 1 and hit[0]["pos"] is Vector2i and int(hit[0]["priority"]) == 2, str(hit))
	_check("rules: the same hit is not raised twice", _poll("the same hit again") == 0)
	a.last_damage_time = world.time + 5.0
	_check("rules: a shield hit alone is not an attack (the design's hull rule)", _poll("a shield hit") == 0)
	var ward := world.spawn_ward(team, world.mothership(team).global_position + Vector2(600.0, 0.0))
	await _tick(2)
	_poll("the ward in place")
	await _tick(2)
	ward.last_hull_damage_time = world.time
	_check("rules: a hit on a structure of ours raises one alert", _poll("a hit on a structure") == 1 and _live_of("structure_under_attack").size() == 1)
	var cell_pos: Vector2i = hit[0]["pos"]
	# Kill every ship through the combat code: the last death is the squadron lost.
	for uid: int in squad.member_uids.duplicate():
		world.combat.kill(world.by_uid[uid] as Unit, _blow())
	var raised := _poll("both ships dead")
	var lost := _live_of("squadron_lost")
	_check("rules: the last ship's death is one squadron_lost", lost.size() == 1 and int(lost[0]["count"]) == 1 and raised == 1, "%d raised, %s" % [raised, str(lost)])
	_check("rules: its under-attack row gave way to the lost row", _live_of("squadron_under_attack").is_empty(), str(cell_pos))
	var wing := _squad(2)
	await _tick(2)
	var first_uid: int = wing.member_uids[0]
	world.combat.kill(world.by_uid[first_uid] as Unit, _blow())
	rules.poll()
	_check("rules: a squadron that lost only one ship is not lost", _live_of("squadron_lost").size() == 1 and int(_live_of("squadron_lost")[0]["count"]) == 1)
	for uid: int in wing.member_uids.duplicate():
		world.combat.kill(world.by_uid[uid] as Unit, _blow())
	rules.poll()
	await _attacked()


## The attacked frame: the feed tells the army row which squadrons are under attack, for as long as the alert lives.
func _attacked() -> void:
	var rules := feed.rules
	var view := hud.command_view
	feed.refresh()
	_check("attacked: with no under-attack alert alive the army row holds no squadron", rules.attacked(world.tick_count).is_empty() and view.army._attacked.is_empty(), str(view.army._attacked))
	var hurt := _squad(1)
	var calm := _squad(1)
	await _tick(2)
	_poll("a first look at the two")
	await _tick(2)
	(world.by_uid[hurt.member_uids[0]] as Ship).last_hull_damage_time = world.time
	_poll("a hit on one of the two")
	var alert: Dictionary = _live_of("squadron_under_attack")[0] if _live_of("squadron_under_attack").size() == 1 else {}
	feed.refresh()
	_check("attacked: the feed names the hit squadron, and only it, to the army row", rules.attacked(world.tick_count) == [hurt.id] and view.army._attacked.keys() == [hurt.id], str(view.army._attacked))
	view.groups.set_group(1, [hurt.id])
	view.groups.set_group(2, [calm.id])
	view.army.refresh()
	var framed := view.army.entries.filter(func(e: Dictionary) -> bool: return bool(e.get("danger", false)))
	_check("attacked: its card, and no other, wears the attacked frame", framed.size() == 1 and (framed[0]["ids"] as Array).has(hurt.id) and int(framed[0]["n"]) == 1, str(framed.size()))
	var total0 := world.events_rts.total
	var ids0 := world.orders.next_id
	feed.refresh()
	_check("attacked: telling the army row files no record and issues no order", world.events_rts.total == total0 and world.orders.next_id == ids0)
	# The alert runs out: the frame goes with it.
	if not alert.is_empty():
		alert["expires"] = world.tick_count
	feed.refresh()
	view.army.refresh()
	framed = view.army.entries.filter(func(e: Dictionary) -> bool: return bool(e.get("danger", false)))
	_check("attacked: when the alert ends the frame ends", not alert.is_empty() and rules.attacked(world.tick_count).is_empty() and view.army._attacked.is_empty() and framed.is_empty())
	# A new hit frames it again; the squadron lost (its row gives way to the lost row) frees it.
	await _tick(2)
	(world.by_uid[hurt.member_uids[0]] as Ship).last_hull_damage_time = world.time
	_poll("a second hit")
	feed.refresh()
	_check("attacked: a new hit frames it again", view.army._attacked.keys() == [hurt.id])
	for uid: int in hurt.member_uids.duplicate():
		world.combat.kill(world.by_uid[uid] as Unit, _blow())
	rules.poll()
	feed.refresh()
	_check("attacked: a squadron that is lost is no longer framed", view.army._attacked.is_empty(), str(view.army._attacked))
	view.groups.set_group(1, [])
	view.groups.set_group(2, [])

# --- the feed -----------------------------------------------------------------------------------------

## The rows, their sort, the limit, "+N older", the age and the signs.
func _rows() -> void:
	feed.refresh()
	var shown := feed._rows.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)
	var live := _list().live(world.tick_count)
	_check("rows: one row for each live alert up to the limit", shown.size() == mini(live.size(), RtsUiCalls.ALERT_ROWS) and shown.size() >= 3, "%d rows, %d live" % [shown.size(), live.size()])
	var sorted := true
	for i in range(1, shown.size()):
		sorted = sorted and int((shown[i - 1] as AlertFeed.AlertRow).alert["priority"]) <= int((shown[i] as AlertFeed.AlertRow).alert["priority"])
	_check("rows: the most important first", sorted)
	var first: AlertFeed.AlertRow = shown[0]
	_check("rows: a row shows the kind's text and the place", first._text.text.begins_with(str(first.alert["text"])) and first._text.text.contains(" - "), first._text.text)
	_check("rows: the age reads 0:00 for a new alert", first._age.text == "0:00", first._age.text)
	_check("rows: a new row wears the light bar", first.bar)
	_check("signs: danger, check and flask by kind", AlertFeed.glyph_of("mothership_under_attack") == "danger" and AlertFeed.glyph_of("build_done") == "check" and AlertFeed.glyph_of("research_done") == "flask" and AlertFeed.glyph_of("squadron_lost") == "danger")
	var signs_ok := true
	for kind: String in AlertList.KINDS:
		var g := AlertFeed.glyph_of(kind)
		signs_ok = signs_ok and (g == "danger" or RtsGlyphs.has(g))
	_check("signs: every kind of the list has a sign that Glyphs or RtsGlyphs draws", signs_ok)
	# Ten alerts in ten far-apart cells: five rows, the rest behind "+N older".
	for i in 10:
		_event("turret_lost", Vector2i(2000 + i * 4000, 1000 + (i % 2) * 6000))
	feed.refresh()
	shown = feed._rows.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)
	_check("rows: never more than ALERT_ROWS rows", shown.size() == RtsUiCalls.ALERT_ROWS)
	_check("rows: the alerts past the rows are counted older", feed._older.visible and feed._older.text.begins_with("+") and feed._older_list.size() >= 5, feed._older.text)
	feed.toggle_older()
	var drop := feed._drop.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)
	_check("rows: +N older opens the drop-down rows", feed._open and drop.size() == mini(feed._older_list.size(), AlertFeed.RECENT_ROWS), "%d rows" % drop.size())
	_event("research_done", null, {"id": "x"})
	feed.refresh()
	feed.toggle_older()
	_check("rows: a second click closes the drop-down", not feed._open and feed._drop.all(func(r: AlertFeed.AlertRow) -> bool: return not r.visible))
	var texts := PackedStringArray()
	for r: AlertFeed.AlertRow in feed._rows:
		texts.append(r._text.text)
	feed.refresh()
	var same := true
	for i in feed._rows.size():
		same = same and feed._rows[i]._text.text == texts[i]
	_check("rows: an unchanged feed rewrites no text", same)
	var labelled := feed._jump.text.begins_with(KeyMap.first_key("home", "alert_jump") + " ") and feed._back.text.begins_with(KeyMap.first_key("home", "alert_back") + " ")
	_check("rows: the buttons print their keys from the key map", labelled and KeyMap.first_key("home", "alert_back") == "Shift+J", feed._jump.text + " / " + feed._back.text)


## A click on a row sends the camera there; a row with no place sends it nowhere.
func _click() -> void:
	cam.free = true
	cam.global_position = Vector2(100.0, 100.0)
	cam._free_pos = Vector2(100.0, 100.0)
	var row: AlertFeed.AlertRow = null
	for r: AlertFeed.AlertRow in feed._rows:
		if r.visible and r.alert["pos"] is Vector2i:
			row = r
	_check("click: a row with a place is on show", row != null)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	row._gui_input(press)
	_check("click: a left click on a row sends the camera to its place", cam._free_pos == Vector2(row.alert["pos"] as Vector2i), str(cam._free_pos))
	_check("click: it started a chain, so Back works", feed._has_origin and feed._origin == Vector2(100.0, 100.0))
	feed.back()
	var research: Dictionary = _live_of("research_done")[0]
	cam._free_pos = Vector2(100.0, 100.0)
	var moved := feed.jump_to(research)
	if hud.board != null and hud.board.visible:
		hud._toggle_board()
	_check("click: a row with no place moves nothing (it opens a page)", not moved and cam._free_pos == Vector2(100.0, 100.0))


## Is the alert with list key `key` anywhere in the feed: a row, the older list or the jump chain?
func _in_feed(key: String) -> bool:
	for r: AlertFeed.AlertRow in feed._rows + feed._drop:
		if r.visible and not r.alert.is_empty() and str(r.alert["key"]) == key:
			return true
	for a: Dictionary in feed._older_list + feed.chain():
		if str(a["key"]) == key:
			return true
	return false


## The small x of a row hides that alert for the match: it leaves the rows, the older list and the chain; the alert
## list, the camera and the match are left alone; only the left button counts.
func _hide() -> void:
	_event("turret_lost", Vector2i(30000, 14000))
	feed.refresh()
	var row: AlertFeed.AlertRow = feed._rows[0]
	_check("hide: a row is on show", row.visible and not row.alert.is_empty())
	if row.alert.is_empty():
		return
	var alert := row.alert
	var key := str(alert["key"])
	var live0 := _list().live(world.tick_count).size()
	var total0 := world.events_rts.total
	var ids0 := world.orders.next_id
	cam.free = true
	cam._free_pos = Vector2(100.0, 100.0)
	var at := Vector2(AlertFeed.W - AlertFeed.HIDE_W * 0.5, 10.0)
	_check("hide: the x is the row's right end and its tip says what it does", row.on_hide(at) and not row.on_hide(Vector2(100.0, 10.0)) and row._get_tooltip(at) == AlertFeed.HIDE_TIP and row._get_tooltip(Vector2(100.0, 10.0)) == row.tooltip_text)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = at
	row._gui_input(press)
	_check("hide: a right click on the x does nothing", feed._hidden.is_empty() and _in_feed(key))
	press.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(press)
	_check("hide: a left click on the x takes the alert out of the rows, the older list and the chain", feed._hidden.has(key) and not _in_feed(key))
	_check("hide: the camera stays (the x is not a jump)", cam._free_pos == Vector2(100.0, 100.0), str(cam._free_pos))
	_check("hide: the alert list and the match are left alone (no record, no order)", _list().live(world.tick_count).size() == live0 and world.events_rts.total == total0 and world.orders.next_id == ids0)
	if str(alert["kind"]) == "turret_lost" and alert["pos"] is Vector2i:
		_event("turret_lost", alert["pos"])
	feed.refresh()
	_check("hide: it stays hidden when the feed refreshes and when the same alert is raised again", not _in_feed(key))
	feed._hidden.clear()
	feed._head_sig = ""
	feed.refresh()
	_check("hide: nothing else was hidden (the alert is back once the hidden list is emptied)", _in_feed(key))


# --- the chain ----------------------------------------------------------------------------------------

## J, J again, the round after eight, Shift+J and the camera moved by hand.
func _chain() -> void:
	cam.free = true
	feed._has_origin = false
	feed._step = -1
	var start := Vector2(100.0, 100.0)
	cam.global_position = start
	cam._free_pos = start
	var alerts := feed.chain()
	_check("chain: at most eight alerts, each with a place, none without", alerts.size() == AlertFeed.CHAIN_MAX and alerts.all(func(a: Dictionary) -> bool: return a["pos"] is Vector2i), str(alerts.size()))
	_check("chain: the live alerts come first, the most important first", int(alerts[0]["priority"]) <= int(alerts[1]["priority"]))
	_check("chain: J goes to the newest alert", feed.jump() and cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i) and feed._origin == start)
	_check("chain: J again goes to the next one", feed.jump() and cam._free_pos == Vector2(alerts[1]["pos"] as Vector2i))
	for i in range(2, AlertFeed.CHAIN_MAX):
		feed.jump()
	_check("chain: the eighth step is the eighth alert", cam._free_pos == Vector2(alerts[AlertFeed.CHAIN_MAX - 1]["pos"] as Vector2i))
	feed.jump()
	_check("chain: after eight steps it goes round to the top", cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i))
	_check("chain: Shift+J (the Back button) returns the camera to where it was", feed.back() and cam._free_pos == start)
	_check("chain: Back with no chain does nothing", not feed.back() and cam._free_pos == start)
	# A camera moved by hand after a jump: the next J begins a new chain at the top and notes the new place.
	feed.jump()
	feed._jump_ms = -100000
	cam.global_position = Vector2(30000.0, 30000.0)
	feed.jump()
	_check("chain: a jump after the camera was moved starts a new chain at the top", feed._step == 0 and feed._origin == Vector2(30000.0, 30000.0) and cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i))
	feed.back()
	# A camera that follows the ship is freed by the jump and follows again after Back.
	cam.free = false
	feed.jump()
	_check("chain: a jump frees a camera that follows the ship", cam.free)
	feed.back()
	_check("chain: Back follows the ship again", not cam.free)
	cam.free = true
	cam.global_position = start
	cam._free_pos = start


# --- the keys -----------------------------------------------------------------------------------------

## J, Backspace and Shift+J through the feed's input handler, and the places they are live.
func _keys() -> void:
	var alerts := feed.chain()
	var ts := world.teams[team]
	var docked: bool = ts.admiral_docked
	var was_open := world.board_open
	ts.admiral_docked = true
	world.board_open = false
	feed._has_origin = false
	cam.free = true
	cam._free_pos = Vector2(100.0, 100.0)
	_press("J")
	_check("keys: J jumps to the newest alert (docked)", cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i))
	_press("Backspace")
	_check("keys: Backspace is a second J (the next step)", cam._free_pos == Vector2(alerts[1]["pos"] as Vector2i))
	_press("Shift+J")
	_check("keys: Shift+J puts the camera back", cam._free_pos == Vector2(100.0, 100.0) and not feed._has_origin)
	_press("Ctrl+J")
	_check("keys: Ctrl+J is not J", cam._free_pos == Vector2(100.0, 100.0) and not feed._has_origin)
	ts.admiral_docked = false
	_press("J")
	_check("keys: flying with the board closed, J stays unbound", cam._free_pos == Vector2(100.0, 100.0) and not feed._has_origin)
	# Field mode (flying, view and board closed): J and Backspace do nothing in the feed, and the key falls through unused.
	var was_view := world.view_open
	world.view_open = false
	_press("Backspace")
	_press("Shift+J")
	_check("keys: in field mode the feed's keys are not live and J, Backspace and Shift+J do nothing", not feed.keys_live() and cam._free_pos == Vector2(100.0, 100.0) and not feed._has_origin and feed._step == -1)
	world.board_open = true
	_press("J")
	_check("keys: flying with the board open, J jumps", cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i))
	_press("Shift+J")
	_check("keys: flying with the board open, Shift+J goes back", cam._free_pos == Vector2(100.0, 100.0))
	# Mode 3 by the view (view_open true, board closed): J jumps to the newest alert, Backspace steps on, Shift+J goes back.
	world.board_open = false
	world.view_open = true
	_check("keys: flying with the view open (mode 3) the feed's keys are live", feed.keys_live())
	_press("J")
	_check("keys: flying with the view open, J jumps to the newest alert", cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i))
	_press("Backspace")
	_check("keys: flying with the view open, Backspace is a second J (the next step)", cam._free_pos == Vector2(alerts[1]["pos"] as Vector2i))
	_press("Shift+J")
	_check("keys: flying with the view open, Shift+J goes back", cam._free_pos == Vector2(100.0, 100.0) and not feed._has_origin)
	world.view_open = was_view
	ts.admiral_docked = true
	world.board_open = false
	var ev := KeyCodes.make_event("J") as InputEventKey
	ev.pressed = false
	feed._unhandled_input(ev)
	_check("keys: a key coming up does nothing", cam._free_pos == Vector2(100.0, 100.0))
	ts.admiral_docked = docked
	world.board_open = was_open


# --- the keys of both routes together ------------------------------------------------------------------

## A key press with both key codes set, as the keyboard sends it.
func _key_event(code: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e


## Send a key press through the window, so Godot itself hands it to the feed and then the HUD (the real route). True
## when some node used it.
func _send(code: Key, ctrl: bool = false, shift: bool = false) -> bool:
	get_viewport().push_input(_key_event(code, ctrl, shift))
	return get_viewport().is_input_handled()


## What the selection keys and the chain keys can change, as one text.
func _key_state() -> String:
	var view := hud.command_view
	return str([hud.overlay.sel_squads, view.groups.current, view.groups.members(1), view.tools.last, cam._free_pos, cam.free, feed._has_origin, feed._step])


## The selection keys (the HUD's route: F1 to F8, I, Ctrl+I) and the chain keys (the feed's route: J, Backspace, Shift+J)
## on one tip: each does its own job through the real input route, neither route eats the other's key, and all are quiet
## under the hangar, the help pages, the pause menu and the note box.
func _keys_together() -> void:
	var view := hud.command_view
	var ov := hud.overlay
	var g := view.groups
	var ts := world.teams[team]
	var docked: bool = ts.admiral_docked
	var was_open := world.board_open
	ts.admiral_docked = true
	world.board_open = false
	var one := _squad(1)
	await _tick(3)
	_check("together: docked, no panel open, the command view on show", view.is_showing() and not hud._any_panel_open() and feed.keys_live())
	var start := Vector2(100.0, 100.0)
	var alerts := feed.chain()
	# F1 to F8: each picks its own group; the chain is not touched.
	var groups_ok := true
	var chain_quiet := true
	var used := true
	for n in range(1, Groups.COUNT + 1):
		g.set_group(n, [one.id])
		ov.clear_selection()
		feed._has_origin = false
		feed._step = -1
		g.fake_ms = 900000 + n * 10000
		used = _send((KEY_F1 + n - 1) as Key) and used
		groups_ok = groups_ok and ov.sel_squads == [one.id] and g.current == n
		chain_quiet = chain_quiet and not feed._has_origin and feed._step == -1
	g.fake_ms = -1
	_check("together: F1 to F8 each pick their own group through the real route", groups_ok and used, "%s, current %d" % [str(ov.sel_squads), g.current])
	_check("together: a group key starts no jump chain", chain_quiet)
	# I and Ctrl+I: the idle squadrons; the chain is not touched.
	var idle := view.tools.idle_ids()
	view.tools.last = -1
	var want := view.tools.peek_next()
	ov.clear_selection()
	used = _send(KEY_I)
	_check("together: I selects the next idle squadron", used and not idle.is_empty() and ov.sel_squads == [want], "%s, wanted %d" % [str(ov.sel_squads), want])
	used = _send(KEY_I, true)
	_check("together: Ctrl+I selects every idle squadron", used and ov.sel_squads == idle, "%s vs %s" % [str(ov.sel_squads), str(idle)])
	_check("together: the idle keys start no jump chain", not feed._has_origin and feed._step == -1)
	# J, Backspace and Shift+J: the chain; the selection and the groups are not touched.
	ov.set_selection([one.id], false)
	var current0 := g.current
	var last0 := view.tools.last
	cam.free = true
	cam.global_position = start
	cam._free_pos = start
	feed._jump_ms = -100000
	used = _send(KEY_J)
	_check("together: J jumps to the newest alert", used and cam._free_pos == Vector2(alerts[0]["pos"] as Vector2i), str(cam._free_pos))
	used = _send(KEY_BACKSPACE)
	_check("together: Backspace steps to the next alert", used and cam._free_pos == Vector2(alerts[1]["pos"] as Vector2i), str(cam._free_pos))
	used = _send(KEY_J, false, true)
	_check("together: Shift+J puts the camera back", used and cam._free_pos == start and not feed._has_origin, str(cam._free_pos))
	_check("together: the chain keys leave the selection, the groups and the idle round alone", ov.sel_squads == [one.id] and g.current == current0 and view.tools.last == last0 and g.members(Groups.COUNT) == [one.id])
	# Quiet under the hangar, the help pages, the pause menu and the note box: no key of either route changes anything.
	g.set_group(1, [one.id])
	for cover: String in ["hangar", "help", "pause menu", "note box"]:
		match cover:
			"hangar":
				hud._open_hangar()
			"help":
				hud._toggle_help()
			"pause menu":
				hud._toggle_pause_menu()
			"note box":
				hud._open_note()
		var up := false
		match cover:
			"hangar":
				up = hud.hangar != null and hud.hangar.visible
			"help":
				up = hud.help != null and hud.help.visible
			"pause menu":
				up = hud._pause_menu_active()
			"note box":
				up = hud._note_is_open()
		ov.clear_selection()
		g.fake_ms = 2000000
		var before := _key_state()
		_send(KEY_F1)
		_send(KEY_F1, true)
		_send(KEY_F1, false, true)
		_send(KEY_F8)
		_send(KEY_I)
		_send(KEY_I, true)
		_send(KEY_J)
		_send(KEY_BACKSPACE)
		_send(KEY_J, false, true)
		_check("together: under the %s every key of both routes is quiet" % cover, up and _key_state() == before, "%s -> %s (up %s)" % [before, _key_state(), str(up)])
		match cover:
			"hangar":
				if hud.hangar != null:
					hud.hangar.visible = false
			"help":
				if hud.help != null and hud.help.visible:
					hud._toggle_help()
			"pause menu":
				if hud._pause_menu_active():
					hud._toggle_pause_menu()
			"note box":
				hud.note_box.cancel()
	g.fake_ms = -1
	_check("together: the covers are closed again and the match runs", not hud._any_panel_open() and not hud._note_is_open() and not get_tree().paused)
	for n in range(1, Groups.COUNT + 1):
		g.set_group(n, [])
	ov.clear_selection()
	feed._has_origin = false
	feed._step = -1
	cam.free = true
	cam.global_position = start
	cam._free_pos = start
	ts.admiral_docked = docked
	world.board_open = was_open


# --- order feedback -----------------------------------------------------------------------------------

## The order ring once for each order, its gap, the grey x, and what draws nothing.
func _orders() -> void:
	var ov := hud.overlay
	var fb := OrderFeedback.for_overlay(ov)
	_check("orders: one feedback for the overlay", OrderFeedback.for_overlay(ov) == fb)
	var squad := _squad(2)
	await _tick(2)
	ov.set_selection([squad.id] as Array[int], false)
	fb.rings.clear()
	fb.xs.clear()
	fb._last_ring_ms = -100000
	var why := RtsSquadOrders.send(ov, OrderKinds.MOVE, "point", Vector2i(2000, 2000), ov.sel_squads, "Move")
	_check("orders: a Move is sent", why == "", why)
	_check("orders: the Move gives one ring at its point", fb.rings.size() == 1 and fb.rings[0]["p"] == Vector2(2000.0, 2000.0), str(fb.rings))
	RtsSquadOrders.send(ov, OrderKinds.MOVE, "point", Vector2i(2500, 2500), ov.sel_squads, "Move")
	_check("orders: a second order inside 334 ms shows no second ring", fb.rings.size() == 1)
	# The feedback draws on a canvas without a script error (the overlay's own draw calls the same function).
	var canvas := Control.new()
	var drawn := [0]
	canvas.draw.connect(func() -> void:
		fb.draw(canvas, 1.0)
		drawn[0] += 1)
	add_child(canvas)
	canvas.queue_redraw()
	await _tick(3)
	_check("orders: the ring and the x draw on a canvas", drawn[0] >= 1)
	canvas.queue_free()
	await _wait_ms(400)
	RtsSquadOrders.send(ov, OrderKinds.MOVE, "point", Vector2i(3000, 3000), ov.sel_squads, "Move")
	_check("orders: an order after the gap rings again, at its own point", not fb.rings.is_empty() and fb.rings[fb.rings.size() - 1]["p"] == Vector2(3000.0, 3000.0), str(fb.rings))
	var before := fb.rings.size()
	RtsSquadOrders.hold(ov)
	_check("orders: Hold has no clicked point and no ring", fb.rings.size() == before)
	ov.say("Defend: later stage", false)
	_check("orders: a click that did nothing leaves a grey x", fb.xs.size() == 1)
	fb.xs.clear()
	ov.say("Outside the map", false)
	_check("orders: a refusal is not a did-nothing x", fb.xs.is_empty())
	await _wait_ms(1000)
	fb.prune(Time.get_ticks_msec())
	_check("orders: the ring plays once and is gone", fb.rings.is_empty(), str(fb.rings.size()))
	ov.say("Select squadrons first", false)
	_check("orders: an empty selection also leaves the x", fb.xs.size() == 1)
	_check("orders: the x is still there before its time is up", fb.xs.size() == 1)
	await _wait_ms(1000)
	fb.prune(Time.get_ticks_msec())
	_check("orders: the x is steady, then gone", fb.xs.is_empty(), str(fb.xs.size()))
	# The dashed line: noted when the order is sent, standing once the squadron has taken the order.
	fb.lines.clear()
	why = RtsSquadOrders.send(ov, OrderKinds.MOVE, "point", Vector2i(3500, 3500), ov.sel_squads, "Move")
	_check("line: an accepted Move is noted, its line not yet standing", why == "" and fb.lines.size() == 1 and int(fb.lines[0]["t0"]) < 0, why + str(fb.lines))
	await _tick(3)
	fb.prune(Time.get_ticks_msec())
	_check("line: once the squadron has taken the order its line stands, from that squadron", fb.lines.size() == 1 and int(fb.lines[0]["t0"]) >= 0 and fb.line_starts(world, fb.lines[0]).size() == 1, str(fb.lines))
	# A refused order: the danger triangle at its point; an answer that is no order leaves none.
	fb.bads.clear()
	fb._last_bad_ms = -100000
	ov.say("Outside the map", false)
	_check("refused: a refusal that is no order leaves no triangle", fb.bads.is_empty())
	var gone: Array[int] = [987654]
	var ids1 := world.orders.next_id
	why = RtsSquadOrders.send(ov, OrderKinds.MOVE, "point", Vector2i(5000, 5000), gone, "Move")
	_check("refused: a Move for a squadron that is not there is refused", why != "" and not ov.result_ok and world.orders.next_id == ids1, why)
	_check("refused: the refused order leaves the danger triangle at its point", fb.bads.size() == 1 and fb.bads[0]["p"] == Vector2(5000.0, 5000.0), str(fb.bads))
	_check("refused: it gives no line", fb.lines.size() == 1)
	var t_bad := int(fb.bads[0]["t0"]) if fb.bads.size() == 1 else -1
	ov.say(why, false)
	_check("refused: the same refusal said again adds no triangle", fb.bads.size() == 1 and int(fb.bads[0]["t0"]) == t_bad)
	var canvas2 := Control.new()
	var drawn2 := [0]
	canvas2.draw.connect(func() -> void:
		fb.draw(canvas2, 1.0)
		drawn2[0] += 1)
	add_child(canvas2)
	canvas2.queue_redraw()
	await _tick(3)
	_check("line: the line and the triangle draw on a canvas", drawn2[0] >= 1)
	canvas2.queue_free()
	await _wait_ms(1700)
	fb.prune(Time.get_ticks_msec())
	_check("line: steady for 1.5 s, then gone", fb.lines.is_empty(), str(fb.lines))
	_check("refused: the triangle is steady, then gone", fb.bads.is_empty(), str(fb.bads))
	ov.clear_selection()


# --- field mode (RT7 7c) ------------------------------------------------------------------------------

## Some frames pass (the HUD and the command view work in _process).
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The Admiral takes the field in a fighter, as tests/ui_tour.gd does at its "admiral launches" step; the ship, or null.
func _launch() -> Ship:
	var h := world.human
	h.buy_hull("fighter", world.teams[team])
	return world.launch(h)


## The visible rows of the feed.
func _shown() -> Array:
	return feed._rows.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)


## Field mode (flying with the view closed) shows the slim display with FIELD_ALERT_ROWS alert rows, the rest behind "+N older";
## with the view open (mode 3) the full ALERT_ROWS rows show again.
func _field() -> void:
	var view := hud.command_view
	for i in 5:
		_event("turret_lost", Vector2i(1000 + i * 6000, 20000))
	var ship := _launch()
	_check("field: the Admiral took the field in a ship", ship != null and not world.teams[team].admiral_docked)
	world.view_open = false
	world.board_open = false
	await _frames(4)
	feed.refresh()
	_check("field: with the view closed the view shows its slim display", view.is_showing() and view.is_slim() and FieldMode.active(world, team))
	var live := _list().live(world.tick_count)
	var shown := _shown()
	_check("field: the slim display shows exactly FIELD_ALERT_ROWS rows with five alerts alive", live.size() >= 5 and shown.size() == RtsUiCalls.FIELD_ALERT_ROWS and feed.row_cap() == RtsUiCalls.FIELD_ALERT_ROWS, "%d rows, %d live" % [shown.size(), live.size()])
	var same := shown.size() == RtsUiCalls.FIELD_ALERT_ROWS
	for i in mini(shown.size(), live.size()):
		same = same and str((shown[i] as AlertFeed.AlertRow).alert["key"]) == str(live[i]["key"])
	_check("field: the slim rows are the first of live(): the most important, then the newest", same)
	_check("field: the live alerts past the slim rows are behind +N older", feed._older.visible and feed._older_list.size() >= live.size() - RtsUiCalls.FIELD_ALERT_ROWS, feed._older.text)
	world.view_open = true
	await _frames(4)
	feed.refresh()
	shown = _shown()
	_check("field: with the view open (mode 3) the full view shows and ALERT_ROWS rows come back", world.mode3() and not view.is_slim() and shown.size() == RtsUiCalls.ALERT_ROWS and feed.row_cap() == RtsUiCalls.ALERT_ROWS, "%d rows" % shown.size())
	world.view_open = false
	await _frames(4)
	feed.refresh()
	_check("field: closing the view makes it slim again", view.is_slim() and _shown().size() == RtsUiCalls.FIELD_ALERT_ROWS)


## The Admiral docks again (the ship goes into the mothership) and the full view shows ALERT_ROWS rows.
func _dock_back() -> void:
	var view := hud.command_view
	if world.human.ship != null:
		world.try_dock(world.human.ship)
	for i in 5:
		_event("turret_lost", Vector2i(1000 + i * 6000, 24000))
	await _frames(4)
	feed.refresh()
	_check("field: docked, the full view shows ALERT_ROWS rows", not view.is_slim() and _shown().size() == RtsUiCalls.ALERT_ROWS, "%d rows" % _shown().size())


## The width of `text` as the feed's row label draws it, and the room the label has (pixels).
func _fits(row: AlertFeed.AlertRow, text: String) -> bool:
	var font := row._text.get_theme_font("font")
	var fs := row._text.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= row._text.size.x


## The "Under Fire!" warning (RT7): a hull hit on the human's own ship, and only that, makes one row that reads exactly
## "Under Fire!"; J reaches it in mode 3; the readout wears the danger edge for 3 s. Runs while the Admiral flies (after _field()).
func _under_fire() -> void:
	var ship := world.human.ship
	var status := hud.status
	await _frames(40)
	_check("fire: the readout shows the human's ship", ship != null and status.ship == ship and feed.watch_ship() == ship)
	if ship == null:
		return
	# Everything else on the list steps aside, so the new row is the newest and the first.
	var tick := world.tick_count
	for a: Dictionary in _list().live(tick):
		a["expires"] = tick
	_list().live(tick)
	feed.poll()
	await _tick(2)
	ship.last_hull_damage_time = world.time
	_check("fire: a hull hit on the human's ship raises one alert", feed.poll() == 1)
	var rows := _live_of("ship_under_fire")
	_check("fire: exactly one live row, with the ship's place and priority 1", rows.size() == 1 and rows[0]["pos"] == RtsEvents.point_of(ship.global_position) and int(rows[0]["priority"]) == 1, str(rows))
	feed.refresh()
	var shown := _shown()
	var row: AlertFeed.AlertRow = shown[0] if not shown.is_empty() else null
	_check("fire: the first row reads exactly Under Fire!, with no place and no count", row != null and row._text.text == "Under Fire!" and str(rows[0]["text"]) == "Under Fire!" and row.glyph == "danger", row._text.text if row != null else "no row")
	_check("fire: the row fits its 220 px feed width with no ellipsis", row != null and AlertFeed.W == 220.0 and _fits(row, "Under Fire!"))
	await _tick(2)
	ship.last_hull_damage_time = world.time
	feed.poll()
	rows = _live_of("ship_under_fire")
	feed.refresh()
	_check("fire: a second hit inside the window is still one row, the same text, no x2", rows.size() == 1 and str(rows[0]["text"]) == "Under Fire!" and int(rows[0]["count"]) == 2 and (_shown()[0] as AlertFeed.AlertRow)._text.text == "Under Fire!", str(rows))
	# The readout's danger edge: on within 3 s of a hull hit, off after it, and a shield hit alone does not light it.
	status._process(0.0)
	_check("fire: the readout edge is on right after a hull hit", status.fire_edge_on() and status.under_fire())
	ship.last_hull_damage_time = world.time - ShipStatus.FIRE_EDGE_S + 0.5
	status._process(0.0)
	_check("fire: the readout edge is still on inside 3 s", status.fire_edge_on())
	ship.last_hull_damage_time = world.time - ShipStatus.FIRE_EDGE_S - 0.5
	status._process(0.0)
	_check("fire: the readout edge is off after 3 s", not status.fire_edge_on())
	ship.last_hull_damage_time = world.time - 20.0
	ship.last_damage_time = world.time
	status._process(0.0)
	_check("fire: a shield hit alone does not light the edge", not status.fire_edge_on())
	# Jump to it in mode 3 while it is the newest row.
	ship.last_hull_damage_time = world.time
	feed.poll()
	world.board_open = false
	world.view_open = true
	await _frames(3)
	cam.free = true
	cam.global_position = Vector2(100.0, 100.0)
	cam._free_pos = Vector2(100.0, 100.0)
	feed._has_origin = false
	feed._step = -1
	var at := Vector2(_live_of("ship_under_fire")[0]["pos"] as Vector2i)
	_press("J")
	_check("fire: in mode 3 J lands the camera on the ship while that row is newest", cam._free_pos == at, "%s vs %s" % [str(cam._free_pos), str(at)])
	_press("Shift+J")
	_check("fire: Shift+J goes back", cam._free_pos == Vector2(100.0, 100.0))
	world.view_open = false
	await _frames(3)
	# Only the human's ship raises it: a shield hit, a squadron, a structure and a ship of the other team raise nothing.
	tick = world.tick_count
	for a: Dictionary in _live_of("ship_under_fire"):
		a["expires"] = tick
	_list().live(tick)
	await _tick(2)
	ship.last_damage_time = world.time + 5.0
	_check("fire: a shield hit alone raises no row", feed.poll() == 0 and _live_of("ship_under_fire").is_empty())
	ship.last_damage_time = world.time - 20.0
	var crew := _squad(1)
	var ward := world.spawn_ward(team, world.mothership(team).global_position + Vector2(900.0, 0.0))
	await _tick(2)
	feed.poll()
	await _tick(2)
	(world.by_uid[crew.member_uids[0]] as Ship).last_hull_damage_time = world.time
	ward.last_hull_damage_time = world.time
	feed.poll()
	_check("fire: a hit on a squadron ship or a structure raises no Under Fire! row", _live_of("ship_under_fire").is_empty() and not _live_of("squadron_under_attack").is_empty())
	# Docked: the rules watch nothing.
	var ts := world.teams[team]
	ts.admiral_docked = true
	await _tick(2)
	ship.last_hull_damage_time = world.time
	_check("fire: docked, a hull hit on the ship raises no row (nothing is watched)", feed.watch_ship() == null and feed.poll() == 0 and _live_of("ship_under_fire").is_empty())
	ts.admiral_docked = false
	ship.last_hull_damage_time = world.time - 20.0
	await _tick(2)
	feed.poll()


## The rules file holds nothing that could touch the match.
func _source_scan() -> void:
	var f := FileAccess.open("res://scripts/rts/alert_rules.gd", FileAccess.READ)
	_check("scan: alert_rules.gd opens", f != null)
	if f == null:
		return
	var bad := PackedStringArray()
	for line in f.get_as_text().split("\n"):
		var code := line.split("#")[0]
		if line.strip_edges().begins_with("##"):
			continue
		for word in [".push(", ".submit(", "randi", "randf", "RandomNumberGenerator", "apply_now", "emit("]:
			if code.contains(word):
				bad.append(word)
	_check("scan: alert_rules.gd files no record, orders nothing, draws no random number", bad.is_empty(), ", ".join(bad))
