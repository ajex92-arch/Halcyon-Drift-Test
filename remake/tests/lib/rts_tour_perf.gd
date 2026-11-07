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


## The average wall time of a frame (microseconds) over FRAMES frames.
static func _average(tour: Node) -> float:
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await tour.get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / float(FRAMES)