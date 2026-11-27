extends Node
## WHAT THIS IS: the check of RT6's minimap as a command surface (B1): a right click on the minimap gives the selected squadrons a
## Move to that point (and never an Attack), the armed Move verb's left click does the same, the setting "Minimap orders" off
## refuses the click, nothing selected says "Select squadrons first", an armed map tool is only cancelled, a right click with
## an attack verb armed still gives Move (even over an enemy), the layer buttons toggle on a left click, and the marks (the rally
## lines and flag, the alert rings) draw without a script error.
##
## HOW IT WORKS: setup() waits for the HUD, builds a little fleet of crew ships beside our mothership (as tests/alert_feed_check.gd
## does), then sends real InputEventMouseButton events to the real Minimap node (_gui_input), and reads what the order queue got
## (world.orders.last_submitted, next_id) and what the overlay said. It never saves a setting (Minimap.set_orders(.., false)).
## It prints a FAIL line for every check that does not hold, then "minimap_orders_check: N failures (M checks)".
##
## SCRIPTED MODE (--minimap-script): the same node plays the part of tests/order_replay.gd's --script run, with one human order that
## is a minimap Move. It adds the det_hash test as its child (the hash lines the runs are compared by), buys a squadron at
## tick 2400 through the order queue, and when it exists selects it and right-clicks the minimap at a fixed pixel. Run 1 adds
## --order-log, run 2 adds --replay=<that log>: the replay must compare fingerprints, agree on the header and play every order.
## In the replay run it makes no click (the log carries the Move).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/). Two runs at the same time
## must not share a log file: give each pair its own name (--order-log=<file> in run 1, the same file in --replay=<file> in run 2).
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=minimap_orders_check
##   run 1: godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --seed=7 --secs=200 --minimap-script --order-log=<file> --force-hud --test=minimap_orders_check
##   run 2: godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --seed=7 --secs=200 --replay=<that log> --force-hud --minimap-script --test=minimap_orders_check
##
## WHO USES IT: main.gd loads it for --test=minimap_orders_check (it calls setup()); the lead's run_checks list.

var world: World
var hud: Hud
var team := 0
var checks := 0
var fails := 0
## Scripted mode: the det_hash test, the minimap Move's results.
var _det: Node
var _clicked := false
var _click_msg := ""
var _click_at := Vector2.ZERO
var _produced := false
var _scripted := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scripted = bool(Game.opt("minimap-script", false))
	if _scripted:
		_det = load("res://tests/det_hash.gd").new()
		add_child(_det)
		_det.call("setup", w)
		_script_loop()
	else:
		_run()


func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## Windowed pictures: with --shots=<folder> (and a window) save the viewport as <folder>/<name>.png. Nothing in a headless run.
func _shot(name: String) -> void:
	var dir := str(Game.opt("shots", ""))
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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


## A mouse button event at minimap pixel `at` (the control's own pixels), pressed.
func _click(button: int, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = at
	hud.minimap._gui_input(ev)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = at
	hud.minimap._gui_input(up)


## The minimap pixel of world point `p` at the minimap's own size.
func _pixel_of(p: Vector2) -> Vector2:
	return p * hud.minimap.k * hud.minimap.size_scale()


func _find_hud() -> bool:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.command_view != null and hud.overlay != null and hud.minimap != null:
			return true
		await _tick()
	return false


# --- the quick check ---------------------------------------------------------------------------------

func _run() -> void:
	var ok := await _find_hud()
	_check("the HUD exists (use --force-hud --role=admiral)", ok and world.human_role == "admiral")
	if not ok:
		_finish()
		return
	team = world.human_team
	await _tick(3)
	var ov := hud.overlay
	var mm := hud.minimap
	Minimap.set_orders(true, false)
	var squad := _squad(2)
	await _tick(2)
	_check("the setting is on by default", Minimap.orders_on and RtsUiCalls.MINIMAP_ORDERS_ON)

	# 1. A right click gives Move at the clicked point.
	ov.set_selection([squad.id] as Array[int], false)
	var at := Vector2(150.0, 100.0) * mm.size_scale()
	var next0 := world.orders.next_id
	var cam_before := world.camera.global_position
	_click(MOUSE_BUTTON_RIGHT, at)
	var o: Dictionary = world.orders.last_submitted
	var want := Order.point(mm.to_world(at))
	_check("right click: one order was taken", world.orders.next_id == next0 + 1, "%d -> %d" % [next0, world.orders.next_id])
	_check("right click: it is a Move (never an Attack)", str(o.get("kind", "")) == OrderKinds.MOVE, str(o.get("kind", "")))
	_check("right click: it aims at the clicked point", str(o.get("target_kind", "")) == "point" and o.get("target") == want, "%s want %s" % [str(o.get("target")), str(want)])
	_check("right click: it goes to the selected squadron, as a human order", o.get("subjects") == [squad.id] and bool(o.get("human", false)))
	_check("right click: the card's line says Move", ov.result_ok and ov.result_text.begins_with("Move:"), ov.result_text)
	_check("right click: the camera stays put", world.camera.global_position == cam_before)
	_check("right click: it is in the order queue (the log carries it)", int(o.get("id", 0)) > 0)

	# 2. With the setting off the click is refused: no order, and it says so.
	Minimap.set_orders(false, false)
	var next1 := world.orders.next_id
	var last1: Dictionary = world.orders.last_submitted
	_click(MOUSE_BUTTON_RIGHT, at + Vector2(10.0, 0.0))
	_check("setting off: no order is taken", world.orders.next_id == next1 and world.orders.last_submitted == last1)
	_check("setting off: the card says so", not ov.result_ok and ov.result_text.contains("off"), ov.result_text)
	Minimap.set_orders(true, false)

	# 3. Nothing selected: nothing sent, "Select squadrons first".
	ov.clear_selection()
	var next2 := world.orders.next_id
	_click(MOUSE_BUTTON_RIGHT, at)
	_check("nothing selected: no order is taken", world.orders.next_id == next2)
	_check("nothing selected: it says Select squadrons first", ov.result_text == "Select squadrons first", ov.result_text)

	# 4. A map tool armed: the right click only cancels it.
	ov.set_selection([squad.id] as Array[int], false)
	ov.arm("ward")
	var next3 := world.orders.next_id
	_click(MOUSE_BUTTON_RIGHT, at)
	_check("map tool armed: the right click cancels it", ov.tool == "")
	_check("map tool armed: and sends no order", world.orders.next_id == next3)

	# 5. The armed Move verb: a right click cancels it; the left click sends it (the left route).
	ov.arm("verb_move")
	_check("the Move verb arms with a selection", ov.tool == "verb_move")
	_click(MOUSE_BUTTON_RIGHT, at)
	_check("Move verb armed: the right click cancels it", ov.tool == "")
	ov.arm("verb_move")
	var next4 := world.orders.next_id
	_click(MOUSE_BUTTON_LEFT, at + Vector2(0.0, 20.0))
	var o2: Dictionary = world.orders.last_submitted
	_check("left route: the left click sends a Move at its point", world.orders.next_id == next4 + 1 and str(o2.get("kind", "")) == OrderKinds.MOVE and o2.get("target") == Order.point(mm.to_world(at + Vector2(0.0, 20.0))), str(o2))
	_check("left route: the verb is used up", ov.tool == "")

	# 6. An attack verb armed (none arms today; the name is the one a later stage will use): the right click still gives Move, over an
	# enemy as well.
	var enemy := world.mothership(1 - team)
	var over_enemy := _pixel_of(enemy.global_position)
	ov.arm("verb_attack")
	_check("an attack verb can be armed for this check", ov.tool == "verb_attack")
	var next5 := world.orders.next_id
	_click(MOUSE_BUTTON_RIGHT, over_enemy)
	var o3: Dictionary = world.orders.last_submitted
	_check("attack armed: the right click still gives Move", world.orders.next_id == next5 + 1 and str(o3.get("kind", "")) == OrderKinds.MOVE, str(o3.get("kind", "")))
	_check("attack armed: and the verb is put away", ov.tool == "")
	_check("a Move over the enemy mothership is a point, not a target unit", str(o3.get("target_kind", "")) == "point")

	# 7. The layer buttons: a left click toggles, a right click does nothing; neither moves the camera or sends an order.
	var chip := mm.chip_rect(0).get_center() * mm.size_scale()
	var next6 := world.orders.next_id
	_check("chip: Fleet is under its own pixel", mm.chip_at(chip) == 0 and mm.chip_at(mm.chip_rect(1).get_center() * mm.size_scale()) == 1 and mm.chip_at(mm.chip_rect(2).get_center() * mm.size_scale()) == 2)
	_check("chip: the layers start on", mm.layer_fleet and mm.layer_alerts and mm.layer_lines)
	_click(MOUSE_BUTTON_LEFT, chip)
	_check("chip: a left click switches Fleet off", not mm.layer_fleet)
	_click(MOUSE_BUTTON_RIGHT, chip)
	_check("chip: a right click on it does nothing (no order, no toggle)", not mm.layer_fleet and world.orders.next_id == next6)
	_click(MOUSE_BUTTON_LEFT, chip)
	_check("chip: a second left click switches it on", mm.layer_fleet)
	_check("chip: the camera never moved", world.camera.global_position == cam_before)

	# 8. The marks draw: a selected squadron with a standing Move, a rally spot, a live alert and an expired one.
	ov.set_selection([squad.id] as Array[int], false)
	ov.rally_spot = Vector2i(9000, 9000)
	ov.rally_set = true
	world.alerts[team].on_event({"kind": "ship_lost", "team": team, "pos": Vector2i(6000, 6000), "uid": 1, "data": {}}, world.tick_count)
	await _tick(2)
	mm.queue_redraw()
	await _frames(3)
	ov.set_selection([squad.id] as Array[int], false)
	_click(MOUSE_BUTTON_RIGHT, Vector2(200.0, 60.0) * mm.size_scale())
	await _tick(5)
	mm.queue_redraw()
	await _frames(6)
	await _shot("minimap_orders_marks")
	_check("marks: a point order is read as a world point", Minimap.order_point(_rec_with_order()) == Vector2(2500.0, 2500.0))
	await _frames(20)
	_check("marks: the layer buttons off draw too", true)
	mm.toggle_layer(0)
	mm.toggle_layer(1)
	mm.toggle_layer(2)
	mm.queue_redraw()
	await _frames(3)
	mm.toggle_layer(0)
	mm.toggle_layer(1)
	mm.toggle_layer(2)
	ov.rally_set = false
	mm.queue_redraw()
	await _frames(3)
	_check("marks: the layers are back on", mm.layer_fleet and mm.layer_alerts and mm.layer_lines)
	_finish()


## A record whose standing order is a Move to (2500, 2500) (made for the order_point check).
func _rec_with_order() -> Squad:
	var r := Squad.new()
	r.order = {"kind": OrderKinds.MOVE, "target_kind": "point", "target": Vector2i(2500, 2500)}
	return r


func _finish() -> void:
	print("minimap_orders_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- the scripted mode (for the replay pair) ---------------------------------------------------------

## The scripted run: buy a squadron at tick 2400, then when it exists select it and right-click the minimap once. In a replay
## run only the buying is skipped too: the log carries every order.
func _script_loop() -> void:
	var ok := await _find_hud()
	if not ok:
		print("FAIL scripted: no HUD")
		return
	team = world.human_team
	var replaying := world.orders.replay != null
	while is_inside_tree() and not _clicked:
		await _tick()
		var tc := world.tick_count
		if not replaying and not _produced and tc >= 2400:
			_produced = true
			var why := world.orders.submit(Order.make(OrderKinds.PRODUCE, team, Rules.ADMIRAL_SEAT, true, {"hull": "fighter", "count": 3, "rally": "mothership"}, [], "none", 0))
			_check("scripted: the squadron is bought", why == "", why)
		if tc >= 3300 and tc % 30 == 0:
			var mine := RtsSelect.our_squads(world, team)
			if not mine.is_empty():
				if replaying:
					_clicked = true
					break
				var ov := hud.overlay
				ov.set_selection([mine[0].id] as Array[int], false)
				_click_at = Vector2(180.0, 110.0) * hud.minimap.size_scale()
				_click(MOUSE_BUTTON_RIGHT, _click_at)
				_click_msg = ov.result_text
				_clicked = true
		if tc > 9000:
			break


## The match is over (the hash test quit): print the verdict, as order_replay does.
func _exit_tree() -> void:
	if world == null or not _scripted:
		return
	world.orders.flush()
	var q := world.orders
	# A replay that was asked for but could not start (the log file is missing or unreadable) would fall into the non-replay branch
	# below and blame the wrong thing; this names the real cause.
	if Game.opt("replay") is String or Game.opt("admiral-replay") is String:
		_check("scripted: the replay started (the log could be read)", q.replay != null)
	var replaying := q.replay != null
	if not replaying:
		_check("scripted: the minimap Move was sent", _clicked and _click_msg.begins_with("Move:"), _click_msg)
		if q.log == null:
			_check("scripted: the match log is open (use --order-log)", false)
		else:
			var read := OrderLog.read(q.log.path)
			var moves := 0
			for o: Dictionary in read["orders"]:
				if str(o.get("kind", "")) == OrderKinds.MOVE and Order.marker(o) == "h":
					moves += 1
			_check("scripted: the log holds the Move, marked h (%d)" % moves, moves >= 1)
			_check("scripted: the log has its header", str(read["header"]).begins_with("log v2 seed="))
			_check("scripted: the log has fingerprint lines (%d)" % (read["hashes"] as Dictionary).size(), (read["hashes"] as Dictionary).size() > 0)
			_check("scripted: the log has its end line", str(read["end"]) != "")
	else:
		var r := q.replay
		# The replay itself only prints a warning for a log made by another build, which is easy to miss in a gate; a log
		# overwritten by another run's build shows up here. A build that is not known on either side cannot be judged and passes.
		var logged_build := str((r.data["head"] as Dictionary).get("build", ""))
		var live_build := BuildId.get_id()
		var builds_known := logged_build != "" and logged_build != BuildId.UNKNOWN and live_build != BuildId.UNKNOWN
		_check("scripted: the log was written by build %s, this run is build %s" % [logged_build, live_build], not builds_known or logged_build == live_build)
		_check("scripted: the replay compared fingerprint lines (%d)" % r.compared, r.compared > 0)
		_check("scripted: the replay's header agreed with the match", r.header_ok)
		_check("scripted: no fingerprint line differed (%d differ)" % r.mismatches, r.mismatches == 0)
		_check("scripted: every order of the log was played (%d left over)" % r.left_over(), r.left_over() == 0)
	print("minimap_orders_check: %d failures (%d checks)" % [fails, checks])
