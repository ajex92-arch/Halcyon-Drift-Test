class_name RtsTourPerf
extends RefCounted
## WHAT THIS IS: the cost measure of the RTS tour (--rts-perf): how much a frame costs more with the command view than without it,
## with both fleets full (63 ships a team out), in two scenes: all squadrons selected on the Orders page (the busiest the selection
## panel and the card get), and the Build page with nothing selected. The design's gate is at most 2 ms a frame more at 1280x720.
##
## HOW IT WORKS: static functions that take the tour. The fleets are filled with FleetFill until it adds nothing, 21 squadrons are
## selected, the match is frozen (World physics off, so the frames hold only the screens), and the average frame time over 600
## frames is taken with the view on and with it off (hidden, its process stopped, its layout skipped); the difference is printed as
## `RTS_PERF {json}` for each scene. A headless run has no drawing, so its number is the script cost only; the draw cost needs a window
## (the queue's windowed run). The check fails when a scene is over the budget.
##
## WHO USES IT: tests/rts_tour.gd (the --rts-perf mode).

## The frames each average is taken over.
const FRAMES := 600
## The most the view may add to a frame (milliseconds).
const BUDGET_MS := 2.0
## The rounds of the icon-layer measure (each round: one average with the icons off, then one with them on).
const ICON_ROUNDS := 3


## Run both scenes.
static func run(tour: Node) -> void:
	var hud: Hud = tour.hud
	var world: World = tour.world
	var view := hud.command_view
	var rounds := 0
	while FleetFill.apply(world) > 0 and rounds < 10:
		rounds += 1
		await tour.get_tree().process_frame
	var ships := 0
	for t in 2:
		ships += (world.teams[t] as TeamState).production.capacity.alive()
	world.set_physics_process(false)
	# Scene 1: every squadron selected, the Orders page.
	var ids: Array[int] = []
	for rec: Squad in RtsSelect.our_squads(world, world.human_team):
		if ids.size() < 21:
			ids.append(rec.id)
	hud.overlay.set_selection(ids, false)
	view.card.set_page("orders")
	await _scene(tour, "orders_%d_squadrons" % ids.size(), ships)
	# Scene 2: nothing selected, the Build page.
	hud.overlay.clear_selection()
	view.card.set_page("build")
	await _scene(tour, "build_nothing_selected", ships)
	world.set_physics_process(true)


## Measure one scene: the average frame with the view and without it, print RTS_PERF, check the budget.
static func _scene(tour: Node, name: String, ships: int) -> void:
	var view: CommandView = tour.hud.command_view
	for i in 20:
		await tour.get_tree().process_frame
	var with_us := await _average(tour)
	view.visible = false
	view.set_process(false)
	var was := view._show
	view._show = false
	for i in 20:
		await tour.get_tree().process_frame
	var without_us := await _average(tour)
	view._show = was
	view.set_process(true)
	view.visible = true
	var extra_ms := (with_us - without_us) / 1000.0
	print("RTS_PERF %s" % JSON.stringify({"scene": name, "ships_out": ships, "frames": FRAMES, "with_us": snappedf(with_us, 0.1), "without_us": snappedf(without_us, 0.1), "extra_ms": snappedf(extra_ms, 0.01), "budget_ms": BUDGET_MS, "window": DisplayServer.get_name()}))
	tour.check("perf: %s costs at most %.1f ms a frame more with the view (%.2f ms)" % [name, BUDGET_MS, extra_ms], extra_ms <= BUDGET_MS)


# --- RT6 (the awareness screens) ---------------------------------------------------------------------------

## RT6's scene (DESIGN.md 8.4), run by tests/rts_tour_awareness.gd with --rt6-perf: both fleets full (63 ships a team out), 21
## squadrons all selected, 5 live alerts, and 8 group cards plus 4 class cards where the build has the army cards (a build without
## them says so in its RTS_PERF line). The frame time over 600 frames with RT6's screens (the alert feed, the army cards, the
## minimap's Fleet, Alerts and Lines layers, an order's feedback marks) minus without them is printed as `RT6 SCREENS MS <n> PASS`
## (FAIL over 2.0). Then the icon layer on its own: the whole-map frame time with the icon line out of reach (every ship draws its
## own picture) and with the line in force (icons), measured interleaved over three rounds (off, on, off, on, off, on) and compared
## by their medians. In a window it prints `ICON LAYER MS <before> -> <after> PASS` (FAIL when the median did not go down, no
## tolerance). Headless there is no drawing, so both scenes are the script cost only and the icons' saving (draw cost) cannot
## show: the line is `ICON LAYER MS <before> -> <after> NOTE (headless: script cost only)` and its check passes whatever the times
## (F484); the draw cost needs a window.
static func rt6(tour: Node) -> void:
	var hud: Hud = tour.hud
	var world: World = tour.world
	var view := hud.command_view
	var feed := view.alert_feed
	var mm := hud.minimap
	var rounds := 0
	while FleetFill.apply(world) > 0 and rounds < 10:
		rounds += 1
		await tour.get_tree().process_frame
	var ships := 0
	for t in 2:
		ships += (world.teams[t] as TeamState).production.capacity.alive()
	world.set_physics_process(false)
	var ids: Array[int] = []
	for rec: Squad in RtsSelect.our_squads(world, world.human_team):
		if ids.size() < 21:
			ids.append(rec.id)
	hud.overlay.set_selection(ids, false)
	view.card.set_page("orders")
	# Five live alerts, each in its own cell.
	var list := world.alerts[view.team] as AlertList
	var side := Minimap.MAP_W / maxf(0.000001, mm.k)
	var kinds := ["mothership_under_attack", "squadron_under_attack", "structure_under_attack", "ship_lost", "build_done"]
	for i in kinds.size():
		list.on_event({"kind": kinds[i], "team": view.team, "pos": Vector2i(int(side * (0.15 + 0.17 * float(i))), int(side * 0.3)), "data": {}}, world.tick_count)
	var live_alerts := list.live(world.tick_count).size()
	# Eight group cards and four class cards (only a build with the army cards has them).
	var cards := _rt6_cards(view, ids)
	# One order, for its feedback marks and the minimap's lines.
	RtsSquadOrders.send(hud.overlay, OrderKinds.MOVE, "point", Vector2i(int(side * 0.5), int(side * 0.5)), hud.overlay.sel_squads, "Move")
	feed.refresh()
	view.refresh()
	for i in 20:
		await tour.get_tree().process_frame
	var with_us := await _average(tour)
	var army: Variant = view.get("army")
	var was_layers := [mm.layer_fleet, mm.layer_alerts, mm.layer_lines]
	feed.visible = false
	feed.set_process(false)
	if army is Control:
		(army as Control).visible = false
		(army as Control).set_process(false)
	mm.layer_fleet = false
	mm.layer_alerts = false
	mm.layer_lines = false
	var fb := OrderFeedback.for_overlay(hud.overlay)
	fb.rings.clear()
	fb.xs.clear()
	for i in 20:
		await tour.get_tree().process_frame
	var without_us := await _average(tour)
	feed.visible = true
	feed.set_process(true)
	if army is Control:
		(army as Control).visible = true
		(army as Control).set_process(true)
	mm.layer_fleet = was_layers[0]
	mm.layer_alerts = was_layers[1]
	mm.layer_lines = was_layers[2]
	var extra_ms := (with_us - without_us) / 1000.0
	print("RTS_PERF %s" % JSON.stringify({"scene": "rt6_screens", "ships_out": ships, "squadrons_selected": ids.size(), "live_alerts": live_alerts, "cards": cards, "frames": FRAMES, "with_us": snappedf(with_us, 0.1), "without_us": snappedf(without_us, 0.1), "extra_ms": snappedf(extra_ms, 0.01), "budget_ms": BUDGET_MS, "window": DisplayServer.get_name()}))
	print("RT6 SCREENS MS %.2f %s" % [extra_ms, "PASS" if extra_ms <= BUDGET_MS else "FAIL"])
	tour.check("perf: the scene is the design's (fleet 63 a team, 21 squadrons selected, 5 live alerts)", ships >= 126 and ids.size() == 21 and live_alerts == 5, "%d ships, %d squadrons, %d alerts" % [ships, ids.size(), live_alerts])
	tour.check("perf: RT6's screens cost at most %.1f ms a frame (%.2f ms)" % [BUDGET_MS, extra_ms], extra_ms <= BUDGET_MS)
	# The icon layer on its own: the whole map in view, the line out of reach (before) and in force (after).
	hud.overlay.clear_selection()
	var cam := world.camera
	var was_zoom := cam.zoom
	var was_target := cam.target_zoom
	var was_line := IconLayer.line_w
	var whole := minf(side, float(RtsUiCalls.ICON_VIEW_RANGE[1]) - 1000.0)
	var z := tour.get_viewport().get_visible_rect().size.x / whole
	cam.target_zoom = z
	cam.zoom = Vector2(z, z)
	# F484: before and after interleaved, ICON_ROUNDS rounds (off, on, off, on, ...), and the medians compared, so one slow
	# stretch of the PC cannot decide the check.
	var off_ok := true
	var on_ok := true
	var icons := 0
	var seen_w := 0.0
	var befores: Array[float] = []
	var afters: Array[float] = []
	var pairs: Array = []
	for r in ICON_ROUNDS:
		IconLayer.set_line(int(RtsUiCalls.ICON_VIEW_RANGE[1]), false)
		IconLayer.active = false
		for i in 20:
			await tour.get_tree().process_frame
		off_ok = off_ok and not IconLayer.active
		var b := await _average(tour)
		IconLayer.set_line(RtsUiCalls.ICON_VIEW_W, false)
		for i in 20:
			await tour.get_tree().process_frame
		on_ok = on_ok and IconLayer.active
		icons = hud.overlay.icons.items().size()
		seen_w = hud.overlay.icons.view_w
		var a := await _average(tour)
		befores.append(b)
		afters.append(a)
		pairs.append([snappedf(b, 0.1), snappedf(a, 0.1)])
	IconLayer.set_line(was_line, false)
	cam.target_zoom = was_target
	cam.zoom = was_zoom
	var before := _median(befores)
	var after := _median(afters)
	var headless := DisplayServer.get_name() == "headless"
	print("RTS_PERF %s" % JSON.stringify({"scene": "rt6_icon_layer", "ships_out": ships, "view_w": snappedf(seen_w, 1.0), "icons": icons, "frames": FRAMES, "rounds": ICON_ROUNDS, "before": snappedf(before, 0.1), "after": snappedf(after, 0.1), "pairs": pairs, "window": DisplayServer.get_name()}))
	if headless:
		print("ICON LAYER MS %.2f -> %.2f NOTE (headless: script cost only)" % [before / 1000.0, after / 1000.0])
	else:
		print("ICON LAYER MS %.2f -> %.2f %s" % [before / 1000.0, after / 1000.0, "PASS" if after < before else "FAIL"])
	tour.check("perf: the icons are off before and on after, with the whole map in view", off_ok and on_ok and icons > 0, "off %s, on %s, %d icons, view %.0f" % [off_ok, on_ok, icons, seen_w])
	# Headless nothing is drawn, so the icons' saving (draw cost) cannot show: a note, never a fail. In a window: the medians, no tolerance.
	tour.check("perf: the whole-map frame is cheaper with the icon layer (medians %.2f -> %.2f ms%s)" % [before / 1000.0, after / 1000.0, "; headless: a note only" if headless else ""], headless or after < before)
	world.set_physics_process(true)


## Put the squadrons `ids` into eight groups, but for one squadron of each of four hulls (four class cards). Returns what the
## cards then hold, or "none: no army cards in this build" (the army cards and the groups are RT6 steps S2 and S3).
static func _rt6_cards(view: CommandView, ids: Array[int]) -> String:
	var army: Variant = view.get("army")
	var groups: Variant = view.get("groups")
	if army == null or groups == null:
		return "none: no army cards in this build"
	var loose_hulls := {}
	var n := 0
	for id in ids:
		var rec: Squad = view.world.squads.get(id)
		if rec == null:
			continue
		if loose_hulls.size() < 4 and not loose_hulls.has(rec.hull_id):
			loose_hulls[rec.hull_id] = id
			continue
		var one: Array[int] = [id]
		groups.call("add_group", 1 + n % 8, one)
		n += 1
	army.call("refresh")
	var count := {}
	for e: Dictionary in army.get("entries"):
		count[str(e["kind"])] = int(count.get(str(e["kind"]), 0)) + 1
	return "%d group, %d class, %d fold" % [int(count.get("group", 0)), int(count.get("class", 0)), int(count.get("fold", 0))]


## The middle value of `v` (the mean of the middle two when the count is even); 0 for none.
static func _median(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0


## The average wall time of a frame (microseconds) over FRAMES frames.
static func _average(tour: Node) -> float:
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await tour.get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / float(FRAMES)