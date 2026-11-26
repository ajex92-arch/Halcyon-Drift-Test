extends Node
## WHAT THIS IS: the tour of the research board's faster screen: the filters and the search box on the Research tab, the
## before-and-after numbers in a card's hover line, the stat card for each ship class, the small marks on upgraded ships and the U
## key. It checks each state and, in a window, saves one picture per state.
##
## HOW IT WORKS: setup() waits for the HUD, then walks the parts in order. Part A opens the board on Research and drives the
## filters through their own buttons and switches (class, can afford, queued, not done, the search, Clear), counts the cards that show
## against the research table, checks that the refresh changes nothing when nothing changed, that the cards keep the keys the order
## check presses, and that typing in the search box types and does not reach the game's keys. Part B reads a research card's hover
## line (the numbers after its text), the four class cards before and after a research is done and with everything done, and
## that the cards fit the board at two window sizes. Part C builds one ship of each class beside the mothership and reads the marks
## layer: none without research, the class's counts with everything researched, none on enemy ships, none past the icon line or
## where a ship is drawn too small, every hull the same size afterwards, and the frame cost with both fleets full. Part D feeds the
## U key to the HUD's key router: docked and flying in mode 3 it opens the board on Research and a second press closes it, and
## flying with the board and the view closed it is not taken. Each check prints
## "PASS rts_tour_research: <check>" or "FAIL rts_tour_research: <check>"; the run ends with "rts_tour_research: done" and
## "rts_tour_research: N failures (M checks)" (0 failures is a pass). A run longer than --secs (default 120 real seconds) prints
## "rts_tour_research: timeout" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=tour --no-admiral-ai --force-hud --seed=7 --test=rts_tour_research
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --bot=tour --no-admiral-ai --seed=7 --test=rts_tour_research --shots=<folder>
## The window's size is Godot's own --resolution WxH (before the "--"); a headless run takes --ui-size=WxH instead.
##
## WHO USES IT: main.gd loads it for --test=rts_tour_research (it calls setup()); the lead's run_checks list.

## The running match.
var world: World
## Its HUD.
var hud: Hud
## The Admiral board the tour drives (set once Part A has opened it).
var board: AdmiralBoard
## The team the Admiral commands.
var team := 0
## How many checks were made.
var checks := 0
## How many of them failed.
var fails := 0
## The folder the pictures go into (--shots).
var dir := ""


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	dir = str(Game.opt("shots", ""))
	if DisplayServer.get_name() == "headless" and Game.opt("ui-size") != null:
		var xy := str(Game.opt("ui-size")).split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			get_tree().root.size = Vector2i(int(xy[0]), int(xy[1]))
	_run()


## The run takes too long: say so and quit.
func _process(_dt: float) -> void:
	if world != null and Time.get_ticks_msec() > 1000 * int(Game.opt("secs", 120)):
		print("rts_tour_research: timeout")
		get_tree().quit()


## Count one check and print its line (`detail` is added to a FAIL).
func check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS rts_tour_research: %s" % what)
	else:
		fails += 1
		print("FAIL rts_tour_research: %s %s" % [what, detail])


## Wait `n` physics frames.
func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The state `name` is set up: refresh the board, then (in a window, with --shots) save <name>.png; headless, print the step.
func _shot(name: String) -> void:
	if board != null and board.visible:
		board._refresh()
	await _frames(4)
	if DisplayServer.get_name() == "headless":
		print("rts_tour_research step ", name)
		return
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", dir.path_join(name + ".png"))


## The whole tour.
func _run() -> void:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.command_view != null and hud.overlay != null and hud.overlay.icons != null:
			break
		await _tick()
	var found := hud != null and hud.command_view != null and hud.overlay != null and hud.overlay.icons != null
	check("the HUD and the command view exist (use --force-hud --role=admiral)", found and world.human_role == "admiral")
	if not found:
		_finish()
		return
	team = world.human_team
	await _tick(3)
	await _part_a()
	await _part_b()
	await _part_c()
	await _part_d()
	_finish()


## End the tour: print the result lines and quit.
func _finish() -> void:
	if fails == 0:
		print("rts_tour_research: done")
	print("rts_tour_research: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------------------------

## Our team's state.
func _ts() -> TeamState:
	return world.teams[team]


## The ids of the research cards that show now, in Tech.ORDER order.
func _shown() -> Array[String]:
	var out: Array[String] = []
	for id: String in Tech.ORDER:
		var c := board._cards.get("tech:" + id) as Control
		if c != null and c.visible:
			out.append(id)
	return out


## The module cards that show now.
func _shown_modules() -> int:
	var n := 0
	for id: String in Tech.FACILITY_ORDER:
		var c := board._cards.get("fac:" + id) as Control
		if c != null and c.visible:
			n += 1
	return n


## The row's widgets (ResearchBoard.build_row made them).
func _widgets() -> Dictionary:
	return board.get_meta(ResearchBoard.META_WIDGETS, {})


## Refresh the board at once (its own timer does it four times a second).
func _refresh() -> void:
	board._refresh()


## The count line of the row.
func _count_text() -> String:
	return (_widgets()["count"] as Label).text


## The ids of the research rows of research column `col`.
func _rows_of(col: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in Tech.ORDER:
		if Tech.TECHS[id]["column"] == col:
			out.append(id)
	return out


## Is `a` the same set of ids as `b`?
func _same(a: Array[String], b: Array[String]) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y


## A key press of `code` typing `ch` (unicode 0 for a key that types nothing), sent the way the keyboard does it.
func _key(code: Key, ch: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.unicode = ch
	ev.pressed = down
	Input.parse_input_event(ev)


## A tap (press and release) of `code` that types `ch`, then a frame.
func _tap(code: Key, ch: int = 0) -> void:
	_key(code, ch, true)
	await _frames(1)
	_key(code, ch, false)
	await _frames(1)


# --- part A: the filters and the search ---------------------------------------------------------------

## Open the board on Research and drive every filter.
func _part_a() -> void:
	var ts := _ts()
	for f: String in Tech.FACILITY_ORDER:
		if f != "fleet":
			ts.facilities[f] = true
	hud.panels.open_board_at("Research")
	await _frames(4)
	board = hud.board
	check("the board is open on the Research tab", board != null and board.visible and board.tab == "Research")
	if board == null:
		return
	var total := Tech.ORDER.size()
	var all_cards := true
	for id: String in Tech.ORDER:
		all_cards = all_cards and board._cards.has("tech:" + id)
	check("every one of the %d research rows has its card" % total, all_cards)
	await _shot("r01_research_tab")
	check("with no filter all %d research cards and all modules show" % total, _shown().size() == total and _shown_modules() == Tech.FACILITY_ORDER.size(), "%d cards, %d modules" % [_shown().size(), _shown_modules()])
	check("the count line reads Showing %d of %d" % [total, total], _count_text() == "Showing %d of %d" % [total, total], _count_text())
	# The class filter: one column's rows only.
	var col: String = Tech.COLUMNS[2]
	((_widgets()["cls"] as Dictionary)[col] as Button).button_pressed = true
	await _frames(2)
	var want := _rows_of(col)
	check("the class filter %s shows only its %d rows" % [col, want.size()], _same(_shown(), want), str(_shown()))
	check("the module grid is never filtered", _shown_modules() == Tech.FACILITY_ORDER.size())
	var hidden_columns := 0
	for c: String in Tech.COLUMNS:
		var cv := board._cards.get("col:" + c) as Control
		if cv != null and not cv.visible:
			hidden_columns += 1
	check("the other %d columns are hidden whole" % (Tech.COLUMNS.size() - 1), hidden_columns == Tech.COLUMNS.size() - 1, "%d hidden" % hidden_columns)
	check("the count line follows the class filter", _count_text() == "Showing %d of %d" % [want.size(), total], _count_text())
	await _shot("r02_class_filter")
	# A tab change and a resize rebuild the tab: the choice stays.
	board._set_tab("Pilots")
	await _frames(2)
	board._set_tab("Research")
	await _frames(3)
	check("the class filter survives a change of tab", _same(_shown(), want) and ((_widgets()["cls"] as Dictionary)[col] as Button).button_pressed, str(_shown()))
	ResearchBoard.clear_choices(board)
	await _frames(2)
	check("Clear shows everything again", _shown().size() == total and _count_text() == "Showing %d of %d" % [total, total])
	# Can afford: nothing with an empty treasury, every unblocked row with the dearest price in hand.
	var dearest := 0.0
	for id: String in Tech.ORDER:
		dearest = maxf(dearest, float(Tech.TECHS[id]["cost"]))
	ts.treasury = 0.0
	((_widgets()["flags"] as Dictionary)["afford"] as Button).button_pressed = true
	await _frames(2)
	check("Can afford with an empty treasury shows no research card", _shown().is_empty(), str(_shown()))
	ts.treasury = dearest
	_refresh()
	var open_rows: Array[String] = []
	for id: String in Tech.ORDER:
		if ts.tech_blocker(id) == "":
			open_rows.append(id)
	check("Can afford with %d credits shows the %d rows with no blocker" % [dearest, open_rows.size()], _same(_shown(), open_rows) and open_rows.size() > 3, "%d shown" % _shown().size())
	await _shot("r03_can_afford")
	ResearchBoard.clear_choices(board)
	# Queued: exactly the rows queued by two RESEARCH orders (the card's own click).
	ts.treasury = 10000.0
	var picks: Array[String] = []
	for id: String in open_rows:
		if picks.size() < 2 and (Tech.TECHS[id]["req"] as Array).is_empty() and (Tech.TECHS[id]["effect"] as Dictionary).has("unlock_ship"):
			picks.append(id)
	if picks.size() < 2:
		for id: String in open_rows:
			if picks.size() < 2 and not picks.has(id):
				picks.append(id)
	for id in picks:
		(board._cards["tech:" + id] as CardButton).pressed.emit()
	await _tick(5)
	((_widgets()["flags"] as Dictionary)["queued"] as Button).button_pressed = true
	_refresh()
	var queued: Array[String] = []
	for id: String in Tech.ORDER:
		if ts.is_researching(id):
			queued.append(id)
	check("Queued shows exactly the %d rows queued by two research orders" % queued.size(), queued.size() == 2 and _same(_shown(), queued) and _same(queued, picks), "%s shown, %s queued" % [_shown(), queued])
	ResearchBoard.clear_choices(board)
	# Not done: a finished row goes (done as the game's research tick writes it: the id in `done`, then its effect).
	var finished := ""
	for id: String in Tech.ORDER:
		if (Tech.TECHS[id]["effect"] as Dictionary).is_empty() and not queued.has(id):
			finished = id
			break
	ts.done[finished] = true
	ts.apply_effect(Tech.TECHS[finished]["effect"])
	((_widgets()["flags"] as Dictionary)["undone"] as Button).button_pressed = true
	_refresh()
	var rest: Array[String] = []
	for id: String in Tech.ORDER:
		if id != finished:
			rest.append(id)
	check("Not done hides the finished row (%s) and nothing else" % finished, finished != "" and _same(_shown(), rest), "%d shown" % _shown().size())
	ResearchBoard.clear_choices(board)
	# The search: the rows whose name or description holds the word, computed from the table.
	var box := _widgets()["search"] as LineEdit
	box.text = "DRIVE"
	box.text_changed.emit(box.text)
	_refresh()
	var found: Array[String] = []
	for id: String in Tech.ORDER:
		if String(Tech.TECHS[id]["label"]).to_lower().contains("drive") or Tech.blurb(id).to_lower().contains("drive"):
			found.append(id)
	check("the search 'DRIVE' shows exactly the %d rows whose name or text holds it" % found.size(), found.size() > 3 and _same(_shown(), found), "%d shown" % _shown().size())
	await _shot("r04_search_drive")
	ResearchBoard.clear_choices(board)
	check("Clear empties the box and shows everything", box.text == "" and _shown().size() == total and not ResearchBoard.active(board))
	# The refresh touches nothing when nothing changed.
	_refresh()
	var before := ResearchBoard.changes
	for i in 100:
		_refresh()
	check("100 refreshes with nothing changed make no visible change (%d)" % (ResearchBoard.changes - before), ResearchBoard.changes == before)
	((_widgets()["flags"] as Dictionary)["undone"] as Button).button_pressed = true
	before = ResearchBoard.changes
	for i in 100:
		_refresh()
	check("the same with a filter on (%d)" % (ResearchBoard.changes - before), ResearchBoard.changes == before)
	ResearchBoard.clear_choices(board)
	# The keys of the cards stay (the order check presses them).
	check("the module and research cards keep their keys", board._cards.get("fac:research") is CardButton and board._cards.get("tech:repairBays") is CardButton and board._cards.get("colneed:fighter") is Label)
	# Typing in the box types: B, P and U are letters there, not the hangar, the pause or a board key.
	box.grab_focus()
	await _frames(2)
	check("a click gives the search box the keyboard", box.has_focus())
	var paused_before := get_tree().paused
	await _tap(KEY_U, "u".unicode_at(0))
	await _tap(KEY_B, "b".unicode_at(0))
	await _tap(KEY_P, "p".unicode_at(0))
	await _frames(2)
	var hangar_open: bool = hud.hangar != null and hud.hangar.visible
	var menu_open: bool = hud.pause_menu != null and hud.pause_menu.visible
	check("the box holds 'ubp' (%s)" % box.text, box.text == "ubp")
	check("typing U, B and P opened no hangar, no pause menu, and paused nothing", not hangar_open and not menu_open and get_tree().paused == paused_before and not hud.panels.command_paused, "hangar %s menu %s" % [hangar_open, menu_open])
	check("the board stays open while typing", board.visible)
	# Esc gives the keyboard back and does not close the board; Enter gives it back too.
	await _tap(KEY_ESCAPE)
	check("Esc in the box gives the keyboard back and the board stays", not box.has_focus() and board.visible, "focus %s, board %s" % [box.has_focus(), board.visible])
	box.grab_focus()
	await _frames(1)
	await _tap(KEY_ENTER)
	check("Enter in the box gives the keyboard back", not box.has_focus() and board.visible)
	ResearchBoard.clear_choices(board)
	await _frames(2)
	await _shot("r05_cleared")

# --- part B: the numbers and the class cards -----------------------------------------------------------

## The class card of class 	ier (found by the key the board remembers it under).
func _class_card(tier: String) -> StatCard:
	return board._cards.get("class:" + tier) as StatCard


## The text of the card of class 	ier (its bonus line), and what TechEffects says it should read.
func _card_text(tier: String) -> String:
	return _class_card(tier).stats.text


## Every text a class card shows, joined.
func _card_all(tier: String) -> String:
	var c := _class_card(tier)
	return "%s %s %s" % [c.head.text, c.stats.text, c.levels.text]


## Does 	ext hold "nan" or "inf"?
func _odd(text: String) -> bool:
	var low := text.to_lower()
	return low.contains("nan") or low.contains("inf")


## The hover line, the class cards and their fit.
func _part_b() -> void:
	var ts := _ts()
	board._set_tab("Research")
	await _frames(3)
	var tier0: String = Tech.TIERS[0]
	var drive_id := ""
	for id: String in Tech.ORDER:
		if str((Tech.TECHS[id]["effect"] as Dictionary).get("drive", "")) == tier0:
			drive_id = id
			break
	var card := board._cards.get("tech:" + drive_id) as CardButton
	check("the first drive research of class %s has a card by its key (%s)" % [tier0, drive_id], card != null)
	if card == null:
		return
	var lines := TechEffects.lines(ts, drive_id)
	card.mouse_entered.emit()
	var tip := board._detail.text
	var blurb_at := tip.find(Tech.blurb(drive_id))
	var numbers_ok := blurb_at >= 0
	for l: String in lines:
		numbers_ok = numbers_ok and tip.find(l) > blurb_at
	var zero := "+%d%%" % roundi(0.0)
	var step := "+%d%%" % roundi(TechEffects.DRIVE_SPEED * 100.0)
	check("the hover line of %s holds the text, then the numbers %s and %s from TechEffects" % [drive_id, zero, step], numbers_ok and tip.contains(zero) and tip.contains(step), tip)
	await _shot("r06_hover_numbers")
	var level_before := ts.drive_level(tier0)
	check("class card %s reads the level before the research" % tier0, _card_text(tier0) == " · ".join(TechEffects.class_lines(ts, tier0)) and level_before == 0)
	# The research is done (the id in done, then its effect, as the game's research tick writes it).
	ts.done[drive_id] = true
	ts.apply_effect(Tech.TECHS[drive_id]["effect"])
	board._refresh()
	card.mouse_entered.emit()
	check("class card %s reads %s after the effect is applied" % [tier0, step], _card_text(tier0).contains(step), _card_text(tier0))
	check("the hover line of a done research says Done and shows its numbers as now", board._detail.text.contains("Done") and board._detail.text.contains("now"), board._detail.text)
	var all_equal := true
	for t: String in Tech.TIERS:
		all_equal = all_equal and _card_text(t) == " · ".join(TechEffects.class_lines(ts, t))
	check("every class card's text equals TechEffects.class_lines for its class", all_equal and Tech.TIERS.size() == 4)
	var named := true
	for t: String in Tech.TIERS:
		named = named and _class_card(t).head.text == TechEffects.tier_label(t) and _class_card(t).levels.text == TechEffects.level_text(ts, t)
	check("each class card names its hulls and its levels from TechEffects", named)
	# Everything done: no card holds nan or inf.
	for id: String in Tech.ORDER:
		if not ts.done.has(id):
			ts.done[id] = true
			ts.apply_effect(Tech.TECHS[id]["effect"])
	board._refresh()
	var odd := false
	for t: String in Tech.TIERS:
		odd = odd or _odd(_card_all(t))
	for id: String in Tech.ORDER:
		for l: String in TechEffects.lines(ts, id):
			odd = odd or _odd(l)
	check("with every research done no class card and no number line holds nan or inf", not odd)
	await _shot("r07_class_cards_everything_done")
	# The fit: no card wider than the board's inner width, the four with their gaps inside it, at two window sizes.
	var root := get_tree().root
	var was := root.size
	for sz: Vector2i in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = sz
		await _frames(6)
		board._set_tab("Research")
		await _frames(4)
		var inner := board._inner_w()
		var widest := 0.0
		var sum := 0.0
		for t: String in Tech.TIERS:
			var w := _class_card(t).size.x
			widest = maxf(widest, w)
			sum += w
		sum += 6.0 * float(Tech.TIERS.size() - 1)
		check("at %dx%d no class card is wider than the board's %.0f px and the row fits (widest %.0f, row %.0f)" % [sz.x, sz.y, inner, widest, sum], widest <= inner + 0.5 and sum <= inner + 0.5)
	root.size = was
	await _frames(6)
	board._set_tab("Research")
	await _frames(3)

# --- part C: the small marks on upgraded ships ----------------------------------------------------------

## The first hull of Ships.ORDER of size `tier_index` (0 small to 3 capital).
func _hull_of(tier_index: int) -> String:
	for hull_id: String in Ships.ORDER:
		if Ships.size_of(hull_id) == tier_index:
			return hull_id
	return ""


## A new squad of one crew ship of hull `hull` for team `for_team`, beside that team's mothership (as tests/icon_layer_check.gd
## makes one). Returns the ship.
func _new_ship(hull: String, for_team: int) -> Ship:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = for_team
	s.kind = RtsHulls.record_kind(hull)
	s.hull_id = hull
	s.max_members = RtsHulls.max_count(hull)
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	var p := Crew.make(world, for_team, hull, s, 0)
	world.profiles.append(p)
	var ms := world.mothership(for_team)
	var ship := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
	ship.controller = null
	ship.velocity = Vector2.ZERO
	p.ship = ship
	p.state = "flying"
	s.member_uids.append(ship.uid)
	return ship


## Put the camera at a view `width` world units across and let it settle (as tests/rts_tour_awareness.gd does).
func _view(width: float) -> void:
	var cam := world.camera
	var z := get_viewport().get_visible_rect().size.x / width
	cam.target_zoom = z
	cam.zoom = Vector2(z, z)
	await _frames(6)
	cam.zoom = Vector2(z, z)
	await _frames(3)


## The uids of the ships that should carry marks now by the rule: ours, alive, seen, a ship, with a level for its class and drawn
## at least MARK_MIN_RADIUS_PX in radius on the screen.
func _expected() -> Array[int]:
	var out: Array[int] = []
	var ts := _ts()
	var zoom := world.camera.zoom.x
	for u: Unit in world.units:
		if u == null or not is_instance_valid(u) or u.kind != Unit.K_SHIP or u.team != team or not u.alive or not u.visible:
			continue
		var c := MarksLayer.counts(ts, Tech.TIERS[u.size_class])
		if c.x + c.y > 0 and u.radius * zoom >= MarksLayer.MARK_MIN_RADIUS_PX:
			out.append(u.uid)
	return out


## The uids the layer holds records for.
func _record_uids(layer: MarksLayer) -> Array[int]:
	var out: Array[int] = []
	for r: Array in layer.records():
		out.append(int(r[6]))
	return out


## The record of ship `uid`, or an empty array.
func _record_of(layer: MarksLayer, uid: int) -> Array:
	for r: Array in layer.records():
		if int(r[6]) == uid:
			return r
	return []


## Are the arrays `a` and `b` the same set of numbers?
func _same_ints(a: Array[int], b: Array[int]) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y


## The marks: one ship of each class beside the mothership, no research, then everything researched, the enemy, the zoom, the
## sizes, the drawing and the cost with both fleets full.
func _part_c() -> void:
	board.closed.emit()
	await _frames(3)
	var ts := _ts()
	var layer := hud.overlay.marks
	check("the overlay made the marks layer", layer != null)
	if layer == null:
		return
	IconLayer.set_line(RtsUiCalls.ICON_VIEW_W, false)
	# No research: every class at level 0.
	for t: String in Tech.TIERS:
		ts.drive[t] = 0
		ts.armor[t] = 0
	var mine: Array[Ship] = []
	var smallest := INF
	var smallest_ship: Ship = null
	for i in Tech.TIERS.size():
		var hull := _hull_of(i)
		check("the table has a hull of class %s" % Tech.TIERS[i], hull != "")
		var ship := _new_ship(hull, team)
		mine.append(ship)
		if ship.radius < smallest:
			smallest = ship.radius
			smallest_ship = ship
	await _tick(3)
	var close := get_viewport().get_visible_rect().size.x / (MarksLayer.MARK_MIN_RADIUS_PX / smallest * 1.1)
	await _view(close)
	check("close view %.0f across keeps the icons off" % close, not IconLayer.active)
	check("with no research there are no records", layer.records().is_empty(), str(layer.records().size()))
	var before: Array = []
	for s in mine:
		before.append([s.radius, s.size_class])
	# Everything researched.
	for id: String in Tech.ORDER:
		ts.apply_effect(Tech.TECHS[id]["effect"])
	await _frames(4)
	var own_ok := true
	var detail := ""
	for s in mine:
		var tier: String = Tech.TIERS[s.size_class]
		var c := MarksLayer.counts(ts, tier)
		var r := _record_of(layer, s.uid)
		var ok := not r.is_empty() and int(r[4]) == c.x and int(r[5]) == c.y
		if c.x + c.y == 0:
			ok = r.is_empty()
		own_ok = own_ok and ok
		detail += " %s:%s" % [tier, str(Vector2i(int(r[4]), int(r[5]))) if not r.is_empty() else "none"]
	check("with every research done each of our ships has the marks of its class (armor stripes, drive ticks):%s" % detail, own_ok)
	check("the records are the ships the rule names (%d)" % layer.records().size(), _same_ints(_record_uids(layer), _expected()) and layer.records().size() >= mine.size(), "%s vs %s" % [_record_uids(layer), _expected()])
	await _shot("m01_marks_close_all_tiers")
	# The enemy: its team has everything too and one of its ships stands in our sight, with no record.
	var enemy := Rules.CINDER if team == Rules.HALCYON else Rules.HALCYON
	var ets: TeamState = world.teams[enemy]
	for id: String in Tech.ORDER:
		ets.apply_effect(Tech.TECHS[id]["effect"])
	var foe := _new_ship(_hull_of(1), enemy)
	foe.global_position = mine[1].global_position + Vector2(400.0, 150.0)
	await _tick(12)
	await _frames(3)
	check("an enemy ship with every research stands in our sight", foe.visible and foe.visible_to(team), "visible %s, seen %s" % [foe.visible, foe.visible_to(team)])
	check("enemy ships carry no marks", _record_of(layer, foe.uid).is_empty() and layer.records().all(func(r: Array) -> bool: return (world.by_uid.get(int(r[6])) as Unit).team == team))
	# The zoom: past the icon line there are none; between the smallest ship's size and the others', the rule decides.
	await _view(20000.0)
	check("past the icon line (view %.0f) there are no records" % (get_viewport().get_visible_rect().size.x / world.camera.zoom.x), IconLayer.active and layer.records().is_empty(), "%d records" % layer.records().size())
	await _view(close)
	check("back at close zoom the marks return", not IconLayer.active and layer.records().size() >= mine.size())
	var mid := get_viewport().get_visible_rect().size.x / (MarksLayer.MARK_MIN_RADIUS_PX / smallest * 0.7)
	await _view(mid)
	check("at a zoom where the smallest ship's radius on screen is under %.0f px it has no record" % MarksLayer.MARK_MIN_RADIUS_PX, smallest * world.camera.zoom.x < MarksLayer.MARK_MIN_RADIUS_PX and _record_of(layer, smallest_ship.uid).is_empty() and not IconLayer.active, "radius %.1f zoom %.3f" % [smallest, world.camera.zoom.x])
	check("at that zoom the records are still exactly the ships the rule names", _same_ints(_record_uids(layer), _expected()), "%s vs %s" % [_record_uids(layer), _expected()])
	await _shot("m02_marks_mid_zoom")
	await _view(close)
	# Every hull keeps its size.
	var same := true
	for i in mine.size():
		same = same and is_equal_approx(float(before[i][0]), mine[i].radius) and int(before[i][1]) == mine[i].size_class
	check("every ship's radius and size class are the same before and after the research", same)
	# 120 frames: the records hold and the layer draws what it holds.
	var count := layer.records().size()
	await _frames(120)
	check("after 120 frames the layer still holds %d records" % count, layer.records().size() == count)
	check("the layer draws one mark set for each record (%d)" % layer.marks_drawn, layer.marks_drawn == layer.records().size() and layer.marks_drawn > 0)
	# The cost with both fleets full and everything researched.
	var rounds := 0
	while FleetFill.apply(world) > 0 and rounds < 10:
		rounds += 1
		await _frames(1)
	world.set_physics_process(false)
	await _view(close)
	await _frames(20)
	var full := layer.records().size()
	await _shot("m03_marks_full_fleet")
	var with_us := await RtsTourPerf._average(self)
	layer.visible = false
	layer.set_process(false)
	await _frames(20)
	var without_us := await RtsTourPerf._average(self)
	layer.visible = true
	layer.set_process(true)
	world.set_physics_process(true)
	var extra_ms := (with_us - without_us) / 1000.0
	var headless := DisplayServer.get_name() == "headless"
	print("RT10 MARKS records %d, with %.1f us, without %.1f us, extra %.2f ms (%s)" % [full, with_us, without_us, extra_ms, DisplayServer.get_name()])
	if headless:
		print("NOTE rts_tour_research: a headless run draws nothing, so the marks' cost is the script cost only (%.2f ms); the drawn cost needs a window" % extra_ms)
	check("with both fleets full the layer holds %d records and adds at most %.1f ms a frame (%.2f ms%s)" % [full, RtsTourPerf.BUDGET_MS, extra_ms, "; headless: a note only" if headless else ""], full > mine.size() and (headless or extra_ms <= RtsTourPerf.BUDGET_MS))

# --- part D: the U key ------------------------------------------------------------------------------------

## A press of key `text` (the key map's own spelling, "U") as the HUD receives it.
func _press(text: String) -> InputEventKey:
	var ev := KeyCodes.make_event(text) as InputEventKey
	ev.pressed = true
	return ev


## The Research board key: docked it opens the board on Research and a second press closes it; from another tab it opens Research;
## flying with the view open it does the same; flying with the board and the view closed it is not taken.
func _part_d() -> void:
	var ts := _ts()
	var view := hud.command_view
	var rows := KeyMap.effective_keys("home", "research_board")
	check("the home row research_board is live and has a key (%s)" % ", ".join(rows), not rows.is_empty() and "RT10" in KeyMapData.LIVE_STAGES)
	if rows.is_empty():
		return
	var key: String = rows[0]
	hud._close_others(null)
	ts.admiral_docked = true
	await _frames(3)
	if hud.board != null:
		hud.board._set_tab("Pilots")
	var ev := _press(key)
	check("docked, the board closed: the key is taken by the command view", view.select_key(ev) or (hud.board != null and hud.board.visible))
	if hud.board != null and hud.board.visible:
		hud._close_others(null)
	hud.board._set_tab("Pilots")
	hud.router.handle(ev)
	await _frames(2)
	check("docked: %s opens the board on the Research tab" % key, hud.board.visible and hud.board.tab == "Research" and world.board_open, "visible %s, tab %s" % [hud.board.visible, hud.board.tab])
	await _shot("u01_board_opened_by_key")
	hud.router.handle(_press(key))
	await _frames(2)
	check("docked: a second press closes the board", not hud.board.visible and not world.board_open)
	hud.panels.open_board_at("Pilots")
	await _frames(2)
	hud.router.handle(_press(key))
	await _frames(2)
	check("with the board open on another tab, the key shows the Research tab", hud.board.visible and hud.board.tab == "Research", "tab %s" % hud.board.tab)
	hud.router.handle(_press(key))
	await _frames(2)
	check("and the next press closes it", not hud.board.visible)
	# Flying: the Admiral is out in their own ship. With the board and the view closed the key is not taken.
	var flying_rows := KeyMap.effective_keys("flying_board", "research_board")
	check("the flying_board row research_board is live and has a key", not flying_rows.is_empty())
	ts.admiral_docked = false
	var fev := _press(str(flying_rows[0]) if not flying_rows.is_empty() else key)
	var taken := view.select_key(fev)
	hud.router.handle(fev)
	var shut := not hud.board.visible
	world.view_open = true
	hud.router.handle(fev)
	var opened := hud.board.visible and hud.board.tab == "Research"
	# The view shows or hides on its next frame; the key goes by that state, so the tour lets it catch up without a frame of play.
	view._process(0.0)
	hud.router.handle(fev)
	var closed := not hud.board.visible
	world.view_open = false
	ts.admiral_docked = true
	await _frames(2)
	check("flying with the board and the view closed the key is not taken", not taken and shut)
	check("flying with the view open (mode 3) the key opens the board on Research", opened)
	check("flying with the board open the next press closes it", closed)
