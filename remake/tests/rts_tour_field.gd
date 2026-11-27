extends Node
## WHAT THIS IS: RT7 build 7c's tour of the Admiral's field display: the Admiral takes the field in a ship of their own and the
## command view shows its slim display (the strip, the first three alerts, the group chips and the minimap); the tour checks that
## display, then the full view with the view open (mode 3), then that the two flip within two frames, then the "Under Fire!" row in
## the slim feed (and the readout's danger edge), then the minimap flash of a group's double tap. At every step every piece on show gets
## the fit check: it lies inside the window and overlaps no other piece by more than 2 pixels. Windowed it saves a picture at each
## picture step (f01_field, f02_mode3, f03_underfire, f04_flash); with --dump-layout it prints every control on screen at each
## step for tools/ui_layout_check.py.
##
## HOW IT WORKS: setup() waits for the HUD, builds twelve squadrons beside our mothership (as tests/rts_tour_awareness.gd does), puts
## five of them into groups, buys a fighter for the Admiral and launches it (as tests/ui_tour.gd does at its "admiral launches"
## step), raises five alerts through the alert list and some lines in the kill feed, then walks the steps. It reads the pieces'
## rectangles from the HUD (CommandView.rects() and the controls themselves), so the numbers are the ones a player sees. Each check
## prints "PASS rts_tour_field: <check>" or "FAIL rts_tour_field: <check>"; the run ends with "rts_tour_field: done" and
## "rts_tour_field: N failures (M checks)" (0 failures is a pass). A run longer than --secs (default 180 real seconds) prints
## "rts_tour_field: timeout" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=tour --no-admiral-ai --force-hud --seed=7 --test=rts_tour_field
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --bot=tour --no-admiral-ai --force-hud --seed=7 --test=rts_tour_field --shots=<folder>
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=tour --no-admiral-ai --force-hud --seed=7 --test=rts_tour_field --dump-layout --ui-size=1366x657
## The window's size is Godot's own --resolution WxH (before the "--"); a headless run takes --ui-size=WxH[,WxH...] instead.
##
## WHO USES IT: main.gd loads it for --test=rts_tour_field (it calls setup()); the lead's gates run it at two window sizes.

## Prints the control dumps (the UIDUMP lines of --dump-layout, as tests/rts_tour.gd does).
const UiDump := preload("res://tests/lib/ui_dump.gd")
## The hulls of the twelve squadrons the tour builds (the first five go into groups, the rest stay loose).
const HULLS := ["fighter", "fighter", "bomber", "scout", "lance", "flak", "fighter", "bomber", "scout", "lance", "flak", "destroyer"]
## The pixels a piece may overlap another by (and leave the window by) before the fit check fails.
const TOL := 2.0

## The running match, its HUD and the pieces the tour drives.
var world: World
var hud: Hud  # the HUD
var view: CommandView  # the command view
var feed: AlertFeed  # the alert feed
var mm: Minimap  # the minimap
var cam: CameraRig  # the camera
## The team the Admiral commands, and the Admiral's own ship once launched.
var team := 0
var ship: Ship  # the Admiral's own ship (null until launched)
## How many checks were made and how many failed.
var checks := 0
var fails := 0  # fails
## The folder the pictures go into (--shots).
var dir := ""
## True with --dump or --dump-layout: picture steps also print every control (see UiDump); `layout` adds the facts the layout
## checker needs.
var dump := false
var layout := false  # the layout
## The window sizes of a headless dump (--ui-size; the first is the size the run starts and ends at).
var sizes: Array[Vector2i] = [Vector2i(1280, 720)]
## The squadrons the tour built.
var squads: Array[Squad] = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	dir = str(Game.opt("shots", ""))
	layout = Game.opt("dump-layout", false) == true
	dump = layout or Game.opt("dump", false) == true
	sizes = _ui_sizes()
	if DisplayServer.get_name() == "headless":
		get_tree().root.size = sizes[0]
	_run()


## The window sizes of a headless dump: --ui-size=WxH (several separated by commas); a size under 320 x 240 is skipped; with none
## left, 1280x720.
func _ui_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in str(Game.opt("ui-size", "1280x720")).split(",", false):
		var xy := part.split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	return out


## The run takes too long: say so and quit.
func _process(_dt: float) -> void:
	if world != null and Time.get_ticks_msec() > 1000 * int(Game.opt("secs", 180)):
		print("rts_tour_field: timeout")
		get_tree().quit()


## Count one check and print its line (`detail` is added to a FAIL).
func check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS rts_tour_field: %s" % what)
	else:
		fails += 1
		print("FAIL rts_tour_field: %s %s" % [what, detail])


## `n` physics ticks pass.
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## `n` drawn frames pass (the HUD works in _process).
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The whole tour.
func _run() -> void:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.command_view != null and hud.command_view.alert_feed != null and hud.overlay != null and hud.minimap != null:
			break
		await _tick()
	var found := hud != null and hud.command_view != null and hud.command_view.alert_feed != null and hud.overlay != null and hud.minimap != null
	check("the HUD, the feed and the minimap exist (use --force-hud --role=admiral)", found and world.human_role == "admiral")
	if not found:
		_finish()
		return
	view = hud.command_view
	feed = view.alert_feed
	mm = hud.minimap
	cam = world.camera
	team = world.human_team
	await _tick(3)
	await _setup_match()
	if ship == null:
		_finish()
		return
	await _field()
	await _mode3()
	await _flip()
	await _fire()
	await _flash()
	_finish()


## End the tour: print the result lines and quit.
func _finish() -> void:
	if fails == 0:
		print("rts_tour_field: done")
	print("rts_tour_field: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- the set-up -----------------------------------------------------------------------------------------

## A new squad of hull `hull` with `n` crew ships, beside our mothership (as tests/rts_tour_awareness.gd makes one).
func _squad(hull: String, n: int) -> Squad:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = RtsHulls.record_kind(hull)
	s.hull_id = hull
	s.max_members = RtsHulls.max_count(hull)
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	for i in n:
		var p := Crew.make(world, team, hull, s, s.member_uids.size())
		world.profiles.append(p)
		var ms := world.mothership(team)
		var sh := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
		sh.controller = null
		sh.velocity = Vector2.ZERO
		p.ship = sh
		p.state = "flying"
		s.member_uids.append(sh.uid)
	return s


## Raise one alert of `kind` at `pos` straight into the list, as raised at `tick`.
func _raise(kind: String, pos: Variant, tick: int) -> void:
	(world.alerts[team] as AlertList).on_event({"kind": kind, "team": team, "pos": pos, "data": {}}, tick)


## The squadrons, five groups, the Admiral's ship in the field, five alerts and some kill feed lines.
func _setup_match() -> void:
	for hull: String in HULLS:
		squads.append(_squad(hull, mini(2, RtsHulls.max_count(hull))))
	await _tick(3)
	for n in 5:
		view.groups.set_group(n + 1, [squads[n].id] as Array[int])
	var h := world.human
	h.buy_hull("fighter", world.teams[team])
	ship = world.launch(h)
	check("setup: the Admiral took the field in a ship of their own", ship != null and not world.teams[team].admiral_docked)
	if ship == null:
		return
	world.view_open = false
	world.board_open = false
	var t := world.tick_count
	var ms := world.mothership(team)
	# Kinds whose line fits the feed's 152 px label with a place (the longer "... under attack - <place>" lines are trimmed there
	# today, a limit of the feed itself that this tour does not test).
	_raise("research_done", null, t - 4)
	_raise("build_done", Vector2i(ms.global_position), t - 3)
	_raise("turret_lost", Vector2i(ms.global_position) + Vector2i(0, 4000), t - 2)
	_raise("squadron_lost", Vector2i(RtsSelect.centre_of(world, squads[0])), t - 1)
	_raise("ship_lost", Vector2i(ms.global_position) + Vector2i(4000, 0), t)
	hud.feed.add_line("A ship was lost", Palette.DANGER)
	hud.feed.add_line("The enemy built a turret", Palette.AMBER)
	hud.feed.add_line("Research finished", Palette.AMBER)
	await _frames(40)
	feed.refresh()
	view.refresh()


# --- the fit check ----------------------------------------------------------------------------------------

## The pieces on show now, by name: the command view's own pieces, the HUD's top bar, minimap, seat bar, ship readout, gear slots and
## the kill feed's column (the part that has lines).
func _pieces() -> Dictionary:
	var out := {}
	for pair: Array in [["strip", view.strip], ["alert", view.alert_slot], ["army", view.army], ["prod", view.prod], ["card", view.card], ["sel", view.sel],
			["top bar", hud.top_bar], ["minimap", hud.minimap], ["seat bar", hud.seat_bar], ["readout", hud.status], ["gear slots", hud.slots], ["wing strip", hud.wing_strip]]:
		var c: Control = pair[1]
		if c != null and c.is_visible_in_tree():
			out[pair[0]] = Rect2(c.global_position, c.size)
	if hud.feed.is_visible_in_tree() and hud.feed.get_child_count() > 0:
		var fs := hud.feed.get_combined_minimum_size()
		if fs.y > 0.0:
			out["kill feed"] = Rect2(hud.feed.global_position, fs)
	return out


## The fit check of step `what`: every piece on show lies inside the window and overlaps no other by more than TOL pixels
## (both ways); the rectangles are printed so a failure can be read.
func _fit(what: String) -> void:
	hud.layout.apply()
	var vp := hud.get_viewport_rect().size
	var all := _pieces()
	var names := all.keys()
	var line := "RTS_FIELD_RECTS %s %dx%d" % [what, int(vp.x), int(vp.y)]
	var bad: Array[String] = []
	for i in names.size():
		var a: Rect2 = all[names[i]]
		line += " %s=%d,%d,%dx%d" % [names[i], int(a.position.x), int(a.position.y), int(a.size.x), int(a.size.y)]
		if not Rect2(Vector2.ZERO, vp).grow(TOL).encloses(a):
			bad.append("%s leaves the window %s" % [names[i], str(a)])
		for j in range(i + 1, names.size()):
			var b: Rect2 = all[names[j]]
			var hit := a.intersection(b)
			if hit.size.x > TOL and hit.size.y > TOL:
				bad.append("%s overlaps %s by %dx%d" % [names[i], names[j], int(hit.size.x), int(hit.size.y)])
	print(line)
	check("fit %s: every piece on show is inside the window and overlaps no other by more than %d px" % [what, int(TOL)], bad.is_empty(), "; ".join(bad))


## The step `name`: refresh, check the fit, print the dump, and (windowed, with --shots) save <name>.png. Headless with several
## --ui-size sizes it does the first three at each size in turn.
func _shot(name: String) -> void:
	feed.refresh()
	view.refresh()
	mm.queue_redraw()
	await _frames(4)
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		print("rts_tour_field step ", name)
	if dump and headless and sizes.size() > 1:
		for sz in sizes:
			get_tree().root.size = sz
			await _frames(8)
			hud.layout.apply()
			view.refresh()
			_fit("%s@%dx%d" % [name, sz.x, sz.y])
			UiDump.dump(hud, name, layout)
		get_tree().root.size = sizes[0]
		await _frames(3)
	else:
		view.refresh()
		_fit(name)
		if dump:
			UiDump.dump(hud, name, layout)
	if headless or dir == "":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## The feed's rows on show.
func _shown() -> Array:
	return feed._rows.filter(func(r: AlertFeed.AlertRow) -> bool: return r.visible)


## Are `a` and `b` within 2 pixels of each other?
func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOL


# --- the steps --------------------------------------------------------------------------------------------

## Field mode (acceptance a to e): the strip, the first three alerts, the group chips and the minimap, and nothing else.
func _field() -> void:
	var live := (world.alerts[team] as AlertList).live(world.tick_count)
	check("field: five alerts are alive", live.size() >= 5, "%d" % live.size())
	check("field: the Admiral is in field mode and the view shows its slim display", FieldMode.active(world, team) and view.is_showing() and view.is_slim())
	check("field (a): the production panel, the card and the selection panel are not visible", not view.prod.is_visible_in_tree() and not view.card.is_visible_in_tree() and not view.sel.is_visible_in_tree())
	var rows := _shown()
	check("field (b): at most %d alert rows are visible (%d of %d alerts)" % [RtsUiCalls.FIELD_ALERT_ROWS, rows.size(), live.size()], rows.size() <= RtsUiCalls.FIELD_ALERT_ROWS and rows.size() == RtsUiCalls.FIELD_ALERT_ROWS)
	var kinds := {}
	for e: Dictionary in view.army.entries:
		kinds[str(e["kind"])] = true
	var group_cards := 0
	for c: ArmyCard in view.army._shown:
		if c.visible and c.kind == "group":
			group_cards += 1
	check("field (c): the chips row holds group cards only (%d)" % group_cards, kinds.keys() == ["group"] and group_cards == 5 and view.army._shown.size() == 5, str(kinds))
	check("field (d): the strip and the minimap are visible", view.strip.is_visible_in_tree() and hud.minimap.is_visible_in_tree())
	await _shot("f01_field")


## Mode 3 (acceptance f): the view open, and every piece where the full layout puts it (tolerance 2 px).
func _mode3() -> void:
	world.view_open = true
	await _frames(3)
	view.refresh()
	hud.layout.apply()
	check("mode 3: with the view open the full view shows", world.mode3() and view.is_showing() and not view.is_slim() and view.prod.is_visible_in_tree() and view.card.is_visible_in_tree() and view.sel.is_visible_in_tree())
	_full_rects("mode 3")
	feed.refresh()
	var rows := _shown()
	check("mode 3: the feed shows its %d rows again" % RtsUiCalls.ALERT_ROWS, rows.size() == mini(RtsUiCalls.ALERT_ROWS, (world.alerts[team] as AlertList).live(world.tick_count).size()) and feed.row_cap() == RtsUiCalls.ALERT_ROWS, "%d rows" % rows.size())
	var kinds := {}
	for e: Dictionary in view.army.entries:
		kinds[str(e["kind"])] = true
	check("mode 3: the army row holds the hull cards, the save card and the Idle card as well as the groups", kinds.has("group") and kinds.has("idle") and kinds.has("save") and (kinds.has("class") or kinds.has("fold")), str(kinds.keys()))
	await _shot("f02_mode3")


## The full layout's pieces where the layout rules put them: strip at the top, alert slot under it at the left, production panel at
## the right, card above the key line, selection panel on the same line (above the readout while it shows), army row above it.
func _full_rects(what: String) -> void:
	var vp := hud.get_viewport_rect().size
	var r := view.rects()
	var key_h := hud.slots.get_combined_minimum_size().y
	var base := vp.y - CommandView.GAP - key_h - 4.0
	var bottom := minf(base, vp.y - HudLayout.READOUT_ROOM) if hud.status.visible else base
	var ph := CommandView.PROD_FOLD_H if view.prod.folded else CommandView.PROD_H
	var army_y := bottom - CommandView.SEL_H - (ArmyCards.ROOM - ArmyCards.ROW_H) - ArmyCards.ROW_H
	var strip: Rect2 = r["strip"]
	var alert: Rect2 = r["alert"]
	var prod: Rect2 = r["prod"]
	var card: Rect2 = r["card"]
	var sel: Rect2 = r["sel"]
	var army: Rect2 = r["army"]
	check("%s: the strip is at (0,0) with the window's width and STRIP_H" % what, _near(strip.position.x, 0.0) and _near(strip.position.y, 0.0) and _near(strip.size.x, vp.x) and _near(strip.size.y, CommandView.STRIP_H), str(strip))
	check("%s: the alert slot is at (GAP, STRIP_H + 4), ALERT_W x ALERT_H" % what, _near(alert.position.x, CommandView.GAP) and _near(alert.position.y, CommandView.STRIP_H + 4.0) and _near(alert.size.x, CommandView.ALERT_W) and _near(alert.size.y, CommandView.ALERT_H), str(alert))
	check("%s: the production panel is at the top right, PROD_W x its height" % what, _near(prod.position.x, vp.x - CommandView.GAP - CommandView.PROD_W) and _near(prod.position.y, CommandView.STRIP_H + 4.0) and _near(prod.size.x, CommandView.PROD_W) and _near(prod.size.y, ph), str(prod))
	check("%s: the card is at x GAP with its bottom edge on the line above the key line" % what, _near(card.position.x, CommandView.GAP) and _near(card.end.y, base), "%s, line %d" % [str(card), int(base)])
	check("%s: the selection panel's bottom edge is on that line (above the readout while it shows)" % what, _near(sel.end.y, bottom), "%s, line %d" % [str(sel), int(bottom)])
	check("%s: the army row's top is where the full layout puts it" % what, _near(army.position.y, army_y), "%s, wanted y %d" % [str(army), int(army_y)])


## The two modes flip within two frames and leave no piece stranded (acceptance g).
func _flip() -> void:
	world.view_open = false
	await _frames(2)
	var vp := hud.get_viewport_rect().size
	var key_h := hud.slots.get_combined_minimum_size().y
	var ay := vp.y - CommandView.GAP - key_h - 4.0 - ArmyCards.ROW_H
	var r := view.rects()
	var army: Rect2 = r["army"]
	var alert: Rect2 = r["alert"]
	check("flip: view_open off makes the slim display within 2 frames (the three pieces gone, the army row on the key line, the alert slot short)", view.is_slim() and not view.prod.is_visible_in_tree() and not view.card.is_visible_in_tree() and not view.sel.is_visible_in_tree() and _near(army.position.y, ay) and _near(army.position.x, CommandView.GAP) and _near(alert.size.y, AlertFeed.HEAD_H + float(RtsUiCalls.FIELD_ALERT_ROWS) * AlertFeed.ROW_H), "%s %s" % [str(army), str(alert)])
	_fit("flip off")
	world.view_open = true
	await _frames(2)
	_full_rects("flip on")
	check("flip: view_open on makes the full view within 2 frames", not view.is_slim() and view.prod.is_visible_in_tree() and view.card.is_visible_in_tree() and view.sel.is_visible_in_tree())
	_fit("flip on")
	world.view_open = false
	await _frames(2)
	check("flip: and off again", view.is_slim() and not view.sel.is_visible_in_tree())
	_fit("flip off again")


## "Under Fire!" in the slim feed: a hull hit on the Admiral's ship makes the first row, exactly that text, and the readout wears
## its danger edge.
func _fire() -> void:
	ship.last_hull_damage_time = world.time
	await _frames(40)
	feed.refresh()
	var rows := _shown()
	var first: AlertFeed.AlertRow = rows[0] if not rows.is_empty() else null
	check("fire: the first alert row of the slim feed reads exactly Under Fire!", first != null and first._text.text == "Under Fire!", first._text.text if first != null else "no row")
	check("fire: the slim feed still shows only %d rows" % RtsUiCalls.FIELD_ALERT_ROWS, rows.size() == RtsUiCalls.FIELD_ALERT_ROWS and view.is_slim())
	check("fire: the readout wears its danger edge", hud.status.fire_edge_on() and hud.status.is_visible_in_tree())
	await _shot("f03_underfire")


## A double tap of F1 in field mode flashes the group on the minimap and leaves the camera where it is.
func _flash() -> void:
	mm.hook_groups()
	var g := view.groups
	var before := mm.flash_count
	var at := cam.global_position
	for i in 2:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_F1
		e.keycode = KEY_F1
		e.pressed = true
		view.select_key(e)
	check("flash: a double tap of F1 in field mode starts one flash", mm.flash_count == before + 1, "%d then %d" % [before, mm.flash_count])
	var ringed := mm.flash_ids()
	check("flash: it rings the squadrons of group 1", ringed == g.members(1) and not ringed.is_empty(), str(ringed))
	check("flash: the camera does not move", cam.global_position.is_equal_approx(at))
	mm.queue_redraw()
	await _frames(2)
	await _shot("f04_flash")
