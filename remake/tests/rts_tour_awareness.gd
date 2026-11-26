extends Node
## WHAT THIS IS: the awareness tour, RT6's tour of the Admiral's awareness screens (DESIGN.md section 10, "Tours" and
## "Muted pass"): it sets up every RT6 piece in force (a full alert feed, Recent open, eight group cards plus "+N", the
## attacked look, the icon line both ways, the command pause with a minimap order and its dotted "on resume" line),
## checks each state and, in a window, saves one picture per state. The muted pass checks that every alert kind has
## its text, its sign and its mark without any sound. One more state, after the group cards, turns the win-odds option on with enemy
## ships brought into sight and checks the marks on the army cards and their tooltips (picture a09_win_odds; with --dump-layout the
## control dump of that state, for tools/ui_layout_check.py).
##
## HOW IT WORKS: setup() waits for the HUD, builds twelve squadrons beside our mothership (as tests/icon_layer_check.gd
## does), then walks the states in order. Alerts are raised straight into the team's alert list; the group cards and
## the attacked look are driven through the command view's `army` and `groups` (RT6 steps S2 and S3): a build that has
## no army cards prints one NOTE line and tours the rest. Each state prints "PASS rts_tour_awareness: <check>" or
## "FAIL rts_tour_awareness: <check>"; the run ends with "rts_tour_awareness: done" and "rts_tour_awareness: N failures
## (M checks)" (0 failures is a pass). With --rt6-perf it runs only RT6's cost scene (RtsTourPerf.rt6: the lines
## `RT6 SCREENS MS <n>` and `ICON LAYER MS <before> -> <after>`: medians of three interleaved rounds, PASS or FAIL in a
## window, NOTE and never a fail headless, where nothing is drawn). A run longer than --secs (default 120 real seconds)
## prints "rts_tour_awareness: timeout" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=tour --no-admiral-ai --force-hud --seed=7 --test=rts_tour_awareness
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --bot=tour --no-admiral-ai --seed=7 --test=rts_tour_awareness --shots=<folder>
##   godot --headless --path remake -- --auto --role=admiral --bot=tour --no-admiral-ai --force-hud --seed=7 --test=rts_tour_awareness --rt6-perf
## The window's size is Godot's own --resolution WxH (before the "--"); a headless run takes --ui-size=WxH instead.
##
## WHO USES IT: main.gd loads it for --test=rts_tour_awareness (it calls setup()); the lead's gates run it at seven window sizes.

## Prints the control dumps (the UIDUMP lines of --dump-layout, as tests/rts_tour.gd does).
const UiDump := preload("res://tests/lib/ui_dump.gd")
## The hulls of the twelve squadrons the tour builds (the first eight go into the groups, the last four stay loose).
const HULLS := ["fighter", "fighter", "bomber", "scout", "lance", "flak", "fighter", "bomber", "scout", "lance", "flak", "destroyer"]
## The alert kinds that have no place (their row opens a page instead of jumping).
const NO_PLACE := ["research_done", "module_done"]

## The running match, its HUD and the pieces the tour drives.
var world: World
var hud: Hud
var view: CommandView
var feed: AlertFeed
var mm: Minimap
var cam: CameraRig
## The team the Admiral commands.
var team := 0
## How many checks were made and how many failed.
var checks := 0
var fails := 0
## The folder the pictures go into (--shots).
var dir := ""
## True with --dump-layout: the win-odds state also prints every control on screen (headless), and `layout` adds the facts the layout
## checker needs.
var dump := false
var layout := false
## The squadrons the tour built.
var squads: Array[Squad] = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	dir = str(Game.opt("shots", ""))
	layout = Game.opt("dump-layout", false) == true
	dump = layout or Game.opt("dump", false) == true
	if DisplayServer.get_name() == "headless" and Game.opt("ui-size") != null:
		var xy := str(Game.opt("ui-size")).split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			get_tree().root.size = Vector2i(int(xy[0]), int(xy[1]))
	_run()


## The run takes too long: say so and quit.
func _process(_dt: float) -> void:
	if world != null and Time.get_ticks_msec() > 1000 * int(Game.opt("secs", 120)):
		print("rts_tour_awareness: timeout")
		get_tree().quit()


## Count one check and print its line (`detail` is added to a FAIL). RtsTourPerf calls it too.
func check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS rts_tour_awareness: %s" % what)
	else:
		fails += 1
		print("FAIL rts_tour_awareness: %s %s" % [what, detail])


func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The state `name` is set up: refresh the screens, then (in a window, with --shots) save <name>.png; headless, print the step.
func _shot(name: String) -> void:
	feed.refresh()
	view.refresh()
	mm.queue_redraw()
	await _frames(4)
	if DisplayServer.get_name() == "headless":
		print("rts_tour_awareness step ", name)
		return
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## The whole tour.
func _run() -> void:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.command_view != null and hud.command_view.alert_feed != null and hud.overlay != null and hud.overlay.icons != null and hud.minimap != null:
			break
		await _tick()
	var found := hud != null and hud.command_view != null and hud.command_view.alert_feed != null and hud.overlay != null and hud.overlay.icons != null and hud.minimap != null
	check("the HUD, the feed, the minimap and the icon layer exist (use --force-hud --role=admiral)", found and world.human_role == "admiral")
	if not found:
		_finish()
		return
	view = hud.command_view
	feed = view.alert_feed
	mm = hud.minimap
	cam = world.camera
	team = world.human_team
	await _tick(3)
	if Game.opt("rt6-perf", false) != false:
		await RtsTourPerf.rt6(self)
		_finish()
		return
	IconLayer.set_line(RtsUiCalls.ICON_VIEW_W, false)
	Minimap.set_orders(true, false)
	for hull: String in HULLS:
		squads.append(_squad(hull, mini(2, RtsHulls.max_count(hull))))
	await _tick(3)
	var ms := world.mothership(team)
	cam.free = true
	cam.global_position = ms.global_position
	cam._free_pos = ms.global_position
	await _view(9000.0)
	await _feed_full()
	await _recent_open()
	await _cards()
	await _odds()
	await _icon_line()
	await _pause()
	await _muted()
	_finish()


## End the tour: leave the layer as a match has it, print the result lines and quit.
func _finish() -> void:
	IconLayer.active = false
	if fails == 0:
		print("rts_tour_awareness: done")
	print("rts_tour_awareness: %d failures (%d checks)" % [fails, checks])
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
func _raise(kind: String, pos: Variant, tick: int, data: Dictionary = {}) -> void:
	if kind == "post_lost":
		_list().on_event({"kind": "post_state", "team": team, "pos": pos, "data": {"state": PostSite.DESTROYED}}, tick)
	else:
		_list().on_event({"kind": kind, "team": team, "pos": pos, "data": data}, tick)


## The map's side in world units, and the whole-number point at shares (fx, fy) of it.
func _side() -> float:
	return Minimap.MAP_W / maxf(0.000001, mm.k)


func _at(fx: float, fy: float) -> Vector2i:
	return Vector2i(int(_side() * fx), int(_side() * fy))


## The feed's rows on show, and the rows of its drop-down on show.
func _shown() -> Array:
	return feed._rows.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)


func _dropped() -> Array:
	return feed._drop.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)


## A new squad of hull `hull` with `n` crew ships, beside our mothership (as tests/icon_layer_check.gd makes one).
func _squad(hull: String, n: int, for_team: int = -1) -> Squad:
	var t := team if for_team < 0 else for_team
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = t
	s.kind = RtsHulls.record_kind(hull)
	s.hull_id = hull
	s.max_members = RtsHulls.max_count(hull)
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	for i in n:
		var p := Crew.make(world, t, hull, s, s.member_uids.size())
		world.profiles.append(p)
		var ms := world.mothership(t)
		var ship := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
		ship.controller = null
		ship.velocity = Vector2.ZERO
		p.ship = ship
		p.state = "flying"
		s.member_uids.append(ship.uid)
	return s


## Put the camera at a view `width` world units across and let it settle.
func _view(width: float) -> void:
	var z := get_viewport().get_visible_rect().size.x / width
	cam.target_zoom = z
	cam.zoom = Vector2(z, z)
	await _frames(6)
	cam.zoom = Vector2(z, z)
	await _frames(3)


## A mouse button pressed and let go at minimap pixel `at` (the control's own pixels).
func _click(button: int, at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.position = at
		mm._gui_input(ev)


## The full set of alerts for a feed picture: twelve alive (five rows and seven behind "+N older"), one of them merged.
func _raise_set() -> void:
	var t := world.tick_count
	var near := Vector2i(RtsSelect.centre_of(world, squads[0]))
	_raise("squadron_idle", _at(0.2, 0.8), t - 12)
	_raise("pilot_request", _at(0.4, 0.8), t - 11)
	_raise("research_done", null, t - 10)
	_raise("build_done", Vector2i(world.mothership(team).global_position), t - 9)
	_raise("cap_full", Vector2i(world.mothership(team).global_position), t - 8)
	_raise("order_refused", null, t - 7, {"reason": "fleet full"})
	for i in 3:
		_raise("ship_lost", _at(0.5, 0.5), t - 4 + i)
	_raise("turret_lost", _at(0.35, 0.6), t - 6)
	_raise("squadron_lost", _at(0.6, 0.35), t - 5)
	_raise("structure_under_attack", _at(0.3, 0.3), t - 1)
	_raise("squadron_under_attack", near, t)
	_raise("mothership_under_attack", Vector2i(world.mothership(team).global_position), t)


# --- the states --------------------------------------------------------------------------------------

## A full feed: five rows, the most important first, each with its sign, text, place and age; the rest behind "+N older".
func _feed_full() -> void:
	_clear()
	_raise_set()
	await _shot("a01_feed_full")
	var live := _list().live(world.tick_count)
	var rows := _shown()
	check("feed: the command view and its alert slot are on show", view.is_showing() and feed.is_visible_in_tree())
	check("feed: a full feed shows ALERT_ROWS rows of %d live alerts" % live.size(), rows.size() == RtsUiCalls.ALERT_ROWS and live.size() == 12, "%d rows, %d live" % [rows.size(), live.size()])
	var ok := true
	for i in rows.size():
		var r: AlertFeed.AlertRow = rows[i]
		ok = ok and r.alert == live[i] and r._text.text != "" and r._age.text != ""
	check("feed: the rows are the top five in order, each with a text and an age", ok and str(live[0]["kind"]) == "mothership_under_attack")
	check("feed: the rest is behind +N older", feed._older.visible and feed._older.text.begins_with("+%d older" % (live.size() - RtsUiCalls.ALERT_ROWS)), feed._older.text)
	var merged := false
	for r: AlertFeed.AlertRow in rows:
		merged = merged or r._text.text.begins_with("Ship lost x3")
	check("feed: three ships lost in one cell are one row, Ship lost x3", merged)
	check("feed: the Jump and Back buttons print their keys", feed._jump.text == "%s Jump" % KeyMap.first_key("home", "alert_jump") and feed._back.text == "%s Back" % KeyMap.first_key("home", "alert_back"), feed._jump.text + " / " + feed._back.text)
	check("feed: the minimap's Alerts layer is on and reads this feed", mm.layer_alerts and mm._alert_feed() == feed)


## Recent open: three ended alerts join the list behind "+N older"; the drop-down shows the first eight of them.
func _recent_open() -> void:
	var t := world.tick_count
	for i in 3:
		_raise("post_lost", _at(0.2 + 0.2 * float(i), 0.15), t - 5000 + i)
	feed.refresh()
	check("recent: the three ended alerts are in Recent", _list().recent.size() == 3)
	feed.toggle_older()
	await _shot("a02_recent_open")
	var drop := _dropped()
	check("recent: +N older opens the drop-down (%d older)" % feed._older_list.size(), feed._open and feed._older_list.size() == 10 and drop.size() == mini(feed._older_list.size(), AlertFeed.RECENT_ROWS), "%d rows of %d" % [drop.size(), feed._older_list.size()])
	check("recent: every row of it has a text", drop.all(func(r: AlertFeed.AlertRow) -> bool: return r._text.text != ""))
	check("recent: the header says it is open", feed._older.text.ends_with("^"), feed._older.text)
	feed.toggle_older()
	check("recent: a second click closes it", not feed._open and _dropped().is_empty())


## Eight group cards plus "+N", then the attacked look (both need the army cards and the groups of RT6's steps S2 and S3).
func _cards() -> void:
	var army: Variant = view.get("army")
	var groups: Variant = view.get("groups")
	if army == null or groups == null:
		print("NOTE rts_tour_awareness: this build has no army cards or control groups (CommandView.army and .groups, RT6 steps S2 and S3), so the eight group cards, +N and the attacked look are not toured here")
		# The attacked look left on this build: the under-attack row and its ring on the minimap.
		hud.overlay.set_selection([squads[0].id] as Array[int], false)
		await _shot("a04_attacked")
		var hit := _shown().filter(func(r: AlertFeed.AlertRow) -> bool: return str(r.alert["kind"]) == "squadron_under_attack")
		check("attacked: the attacked squadron has its danger row and its place in the minimap's rings", hit.size() == 1 and (hit[0] as AlertFeed.AlertRow).glyph == "danger" and feed.chain().has((hit[0] as AlertFeed.AlertRow).alert))
		hud.overlay.clear_selection()
		return
	for n in 8:
		groups.call("set_group", n + 1, [squads[n].id] as Array[int])
	army.call("refresh")
	await _shot("a03_group_cards")
	var count := {}
	for e: Dictionary in army.get("entries"):
		count[str(e["kind"])] = int(count.get(str(e["kind"]), 0)) + 1
	check("cards: eight group cards", int(count.get("group", 0)) == 8, str(count))
	check("cards: the hull cards past them fold into +N", int(count.get("fold", 0)) == 1, str(count))
	var keys_ok := true
	for e: Dictionary in army.get("entries"):
		if str(e["kind"]) == "group":
			keys_ok = keys_ok and str(e["key"]) != ""
	check("cards: every group card prints its key", keys_ok)
	var hit_ids: Array[int] = [squads[0].id, squads[11].id]
	# The game's own way: the feed tells the army row on every refresh which squadrons the alert rules hold as under
	# attack, so a bare set_attacked() is gone by the next beat. Each of the two gets a live under-attack alert in the rules' notes.
	var before: Array = _list().live(world.tick_count)
	_raise("squadron_under_attack", _at(0.3, 0.3), world.tick_count)
	_raise("squadron_under_attack", _at(0.6, 0.3), world.tick_count)
	var fresh: Array = _list().live(world.tick_count).filter(func(a: Dictionary) -> bool: return str(a["kind"]) == "squadron_under_attack" and not before.any(func(b: Dictionary) -> bool: return is_same(a, b)))
	for i in mini(fresh.size(), hit_ids.size()):
		feed.rules._hit[hit_ids[i]] = fresh[i]
	feed.refresh()
	army.call("refresh")
	await _shot("a04_attacked")
	var danger := 0
	for e: Dictionary in army.get("entries"):
		if bool(e.get("danger", false)):
			danger += 1
	check("attacked: the card of an attacked group and the +N card wear the danger frame", danger == 2, "%d framed, %d new alerts" % [danger, fresh.size()])
	for id in hit_ids:
		feed.rules._hit.erase(id)
	for a: Dictionary in fresh:
		a["expires"] = world.tick_count
	feed.refresh()
	army.call("refresh")


## The win-odds mark: the option on and enemy ships brought into our sight beside the squadrons (moved there, so the match's own
## sight sees them; they go back afterwards). Enemy ships are added one by one until the cards show all three marks, or none are
## left; then the picture, the tooltip words and (with --dump-layout, headless) the control dump the layout check reads.
@warning_ignore("integer_division")
func _odds() -> void:
	var army: Variant = view.get("army")
	if army == null:
		return
	# The tour's match has no enemy pilot ships out yet: put a few at their mothership (a fleet of mixed sizes).
	var enemy := Rules.CINDER if team == Rules.HALCYON else Rules.HALCYON
	var spawned: Array[Squad] = []
	for hull: String in ["fighter", "destroyer", "flak", "bomber", "fighter"]:
		spawned.append(_squad(hull, mini(2, RtsHulls.max_count(hull)), enemy))
	var foes: Array[Ship] = []
	for s: Ship in world.ships:
		if s.alive and s.team != team:
			foes.append(s)
	check("odds: the enemy has ships to bring into sight", not foes.is_empty(), "%d" % foes.size())
	if foes.is_empty():
		return
	var back: Array = []
	for s in foes:
		back.append([s, s.global_position])
	var near := RtsSelect.centre_of(world, squads[0])
	Game.win_odds = true
	var marks := {}
	var placed := 0
	for s in foes:
		s.global_position = near + Vector2(450.0 + 120.0 * float(placed % 6), 250.0 * float(placed / 6 + 1))
		placed += 1
		await _tick(4)
		army.call("refresh")
		marks.clear()
		for e: Dictionary in army.get("entries"):
			if str(e.get("odds", "")) != "":
				marks[str(e["odds"])] = true
		if marks.size() >= 3:
			break
	await _shot("a09_win_odds")
	var carrying := 0
	var tips_ok := true
	for e: Dictionary in army.get("entries"):
		if str(e.get("odds", "")) != "":
			carrying += 1
			tips_ok = tips_ok and str(e["tip"]).contains(WinOdds.words(str(e["odds"]))) and str(e["tip"]).contains("ignores missiles")
	var seen_now := foes.filter(func(s: Ship) -> bool: return s.visible_to(team)).size()
	check("odds: %d enemy ships placed, %d in our sight, and the cards show %d mark(s) (%s)" % [placed, seen_now, marks.size(), ", ".join(marks.keys())], carrying >= 1 and seen_now >= 1, "%d cards" % carrying)
	check("odds: every mark's tooltip says it in words and what it ignores", tips_ok)
	if DisplayServer.get_name() == "headless" and dump:
		UiDump.dump(hud, "a09_win_odds", layout)
	Game.win_odds = false
	for row: Array in back:
		(row[0] as Ship).global_position = row[1]
	await _tick(4)
	army.call("refresh")
	var left := 0
	for e: Dictionary in army.get("entries"):
		if str(e.get("odds", "")) != "":
			left += 1
	check("odds: the option off again, no card carries a mark", left == 0, "%d" % left)
	# The five squads were only for this state: free them, so later steps (the icon line, the pause, the muted kinds) never see them.
	for s: Squad in spawned:
		_free_squad(s)
	await _tick(2)
	army.call("refresh")


## Free squad s and its ships and crew (they were made by _squad() for one state).
func _free_squad(s: Squad) -> void:
	for uid: int in s.member_uids:
		var ship := world.by_uid.get(uid) as Ship
		if ship == null:
			continue
		if ship.profile != null:
			ship.profile.ship = null
			world.profiles.erase(ship.profile)
		world.remove_unit(ship)
	world.squads.erase(s.id)


## The icon line both ways: below it the ships keep their pictures, past it one icon a squadron (three of them selected).
func _icon_line() -> void:
	var layer := hud.overlay.icons
	await _view(10000.0)
	await _shot("a05_icons_below_line")
	check("icons: below the line the icons are off", not IconLayer.active and layer.items().is_empty())
	hud.overlay.set_selection([squads[0].id, squads[2].id, squads[11].id] as Array[int], false)
	await _view(20000.0)
	await _shot("a06_icons_past_line")
	var mine := 0
	var marked := 0
	for it: Array in layer.items():
		if int(it[0]) == 0 and int(it[3]) == team:
			mine += 1
		if bool(it[7]):
			marked += 1
	check("icons: past the line the icons are on (view %.0f)" % layer.view_w, IconLayer.active)
	check("icons: one icon for each of our squadrons, the three selected marked", mine >= squads.size() and marked == 3, "%d icons, %d marked" % [mine, marked])
	check("icons: the minimap keeps its own marks (the Fleet layer is on)", mm.layer_fleet)
	hud.overlay.clear_selection()
	await _view(9000.0)
	check("icons: back below the line they are off again", not IconLayer.active)


## The command pause: the feed reads and jumps, a minimap right click queues a Move, drawn dotted and tagged "on resume".
func _pause() -> void:
	var rec := squads[0]
	hud.overlay.set_selection([rec.id, squads[1].id] as Array[int], false)
	hud.panels.toggle_command_pause()
	check("pause: the command pause holds the match, with no pause menu", get_tree().paused and hud.panels.command_paused and (hud.pause_menu == null or not hud.pause_menu.visible))
	var tick := world.tick_count
	var queue0: int = world.orders.queue.size()
	var at := Vector2(200.0, 80.0) * mm.size_scale()
	_click(MOUSE_BUTTON_RIGHT, at)
	await _shot("a07_pause_minimap_on_resume")
	check("pause: the strip reads PAUSED", (view.strip._b["clock"] as Button).text == "PAUSED")
	check("pause: a minimap right click is taken as a Move", hud.overlay.result_ok and hud.overlay.result_text.begins_with("Move"), hud.overlay.result_text)
	check("pause: the order waits in the queue and no tick runs", world.orders.queue.size() == queue0 + 1 and world.tick_count == tick, "%d then %d" % [queue0, world.orders.queue.size()])
	var queued := mm._queued_points()
	check("pause: the minimap holds the waiting point of both squadrons (the dotted on resume line)", queued.has(rec.id) and queued.has(squads[1].id) and mm.layer_lines and Vector2(queued.get(rec.id, Vector2.ZERO)).distance_to(mm.to_world(at)) < 2.0, str(queued))
	check("pause: the feed still reads", _shown().size() == RtsUiCalls.ALERT_ROWS)
	var here := Vector2(_at(0.5, 0.5))
	var was_at := cam._free_pos
	cam.global_position = here
	cam._free_pos = here
	check("pause: the Jump button moves the camera and Back returns it", feed.jump() and cam._free_pos != here and feed.back() and cam._free_pos == here, str(cam._free_pos))
	cam.global_position = was_at
	cam._free_pos = was_at
	hud.panels.toggle_command_pause()
	await _tick(6)
	check("pause: the second press resumes and the Move is carried out", not get_tree().paused and world.tick_count > tick and Minimap.order_point(rec) != null, str(rec.order))
	hud.overlay.clear_selection()


## The muted pass: each of the 15 alert kinds, alone in the list, has its text, its sign and its mark (a ring on the
## minimap at its place; a kind without a place has its sign and is passed over by the jump key). No sound is needed.
func _muted() -> void:
	for kind: String in AlertList.KINDS:
		_clear()
		var placed := not NO_PLACE.has(kind)
		_raise(kind, _at(0.4, 0.6) if placed else null, world.tick_count, {"reason": "money"} if kind == "order_refused" else {})
		feed.refresh()
		var rows := _shown()
		var ok := rows.size() == 1
		var why := "%d rows" % rows.size()
		if ok:
			var r: AlertFeed.AlertRow = rows[0]
			var glyph := AlertFeed.glyph_of(kind)
			var text_ok := r._text.text.begins_with(str((AlertList.KINDS[kind] as Dictionary)["text"])) and r.tooltip_text != "" and r._age.text != ""
			var sign_ok := r.glyph == glyph and (glyph == "danger" or RtsGlyphs.has(glyph))
			var chain: Array = feed.chain()
			# A plain kind (Under Fire!) has a place for the jump but prints none in its row.
			var plain := AlertFeed.PLAIN_KINDS.has(kind)
			var mark_ok: bool = chain.size() == 1 and chain[0] == r.alert and (plain or r._text.text.contains(" - ")) if placed else chain.is_empty()
			ok = text_ok and sign_ok and mark_ok and mm.layer_alerts
			why = "text %s, sign %s, mark %s: %s" % [text_ok, sign_ok, mark_ok, r._text.text]
		check("muted: %s has its text, its sign and its mark" % kind, ok, why)
	# All the kinds at once, with the drop-down open, for the picture.
	_clear()
	_raise_set()
	_raise("module_done", null, world.tick_count)
	_raise("post_lost", _at(0.7, 0.7), world.tick_count)
	feed.refresh()
	feed.toggle_older()
	await _shot("a08_muted_all_kinds")
	var live := _list().live(world.tick_count)
	var with_place := live.filter(func(a: Dictionary) -> bool: return a["pos"] is Vector2i).size()
	check("muted: all 14 kinds are alive, five in rows and %d in the open drop-down" % _dropped().size(), live.size() == 14 and _shown().size() == 5 and _dropped().size() == AlertFeed.RECENT_ROWS, "%d live" % live.size())
	var marks: Array = mm.alert_marks()
	var ringed := live.filter(func(a: Dictionary) -> bool: return a["pos"] is Vector2i and marks.has(a)).size()
	check("muted: every live alert with a place has a ring on the minimap, more than the jump chain holds", with_place > AlertFeed.CHAIN_MAX and ringed == with_place and marks.size() == with_place, "%d placed, %d ringed, %d marks, chain %d" % [with_place, ringed, marks.size(), feed.chain().size()])
	feed.toggle_older()
