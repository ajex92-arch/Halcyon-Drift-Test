class_name RtsTourSelect
extends RefCounted
## WHAT THIS IS: the selection and order checks of the RTS tour (tests/rts_tour.gd): a click, Shift+click, a box,
## a double-click, the smart right-click, the Move verb, Hold and Stop, and the camera keys of home layout A.
##
## HOW IT WORKS: static functions that take the tour (it counts the failures and prints the lines). The mouse is
## driven by calling the overlay's own press and release handlers with a built mouse event and a world point (a
## headless window has no real pointer), so the checks see the same code a click reaches. `run()` makes the fleets
## (FleetFill) and runs the checks that need no waiting; `after_ticks()` runs the checks that need the match to
## have taken a few ticks (the orders are carried out at the start of the next tick).
##
## WHO USES IT: tests/rts_tour.gd.

## The squadron the first checks used (its id), kept for the checks after the ticks.
static var _held_id := -1
## The squadrons the Stop check used.
static var _stopped: Array[int] = []


## A left-button event at screen point `at` with Shift (`shift`), Ctrl (`ctrl`) and the double-click flag.
static func _mb(at: Vector2, pressed: bool, shift: bool = false, ctrl: bool = false, double: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.double_click = double
	return e


## A click at world point `p` (press then release), as the overlay's handlers see it.
static func click(ov: CommandOverlay, p: Vector2, shift: bool = false, ctrl: bool = false, double: bool = false) -> void:
	ov._press(_mb(Vector2(100, 100), true, shift, ctrl, double), p)
	ov._release(_mb(Vector2(100, 100), false, shift, ctrl), p)


## A box from world point `a` to `b`: the press, a move past the box threshold, then the release.
static func box(ov: CommandOverlay, a: Vector2, b: Vector2, shift: bool = false) -> void:
	ov._press(_mb(Vector2(100, 100), true, shift), a)
	ov._drag_from = a
	ov._drag_to = b
	ov._release(_mb(Vector2(300, 300), false, shift), b)


## Make the fleets, then run every selection check that needs no waiting.
static func run(tour: Node, world: World) -> void:
	var ov: CommandOverlay = tour.hud.overlay
	var team := world.human_team
	var rounds := 0
	while FleetFill.apply(world) > 0 and rounds < 6:
		rounds += 1
	var squads := RtsSelect.our_squads(world, team)
	tour.check("select: the fleet fill made our squadrons", squads.size() >= 10, "%d squadrons" % squads.size())
	tour.check("select: a wingman is never selectable", RtsSelect.our_squads(world, team).all(func(r: Squad) -> bool: return r.kind != "wing"))
	if squads.size() < 3:
		return
	ov.clear_selection()
	var a := squads[0]
	var b := squads[1]
	var pa := (RtsSelect.ships_of(world, a)[0] as Ship).global_position
	var pb := (RtsSelect.ships_of(world, b)[0] as Ship).global_position
	var px := 1.0 / maxf(0.0001, world.camera.zoom.x)
	tour.check("select: pick finds the squadron under a ship", int(RtsSelect.pick(world, team, pa, px)["id"]) == a.id)
	click(ov, pa)
	tour.check("select: a click takes the squadron", ov.sel_squads == [a.id] and not ov.sel_base, str(ov.sel_squads))
	click(ov, pb, true)
	tour.check("select: Shift+click adds a second", ov.sel_squads == [a.id, b.id], str(ov.sel_squads))
	click(ov, pa, true)
	tour.check("select: Shift+click on a selected one removes it", ov.sel_squads == [b.id], str(ov.sel_squads))
	click(ov, Vector2(-90000.0, -90000.0))
	tour.check("select: a click on empty map clears", ov.sel_squads.is_empty() and not ov.sel_base)
	# A box around one squadron's ships takes it; a box over nothing takes nothing.
	var r := Rect2(pa, Vector2.ZERO).grow(30.0)
	box(ov, r.position, r.end)
	tour.check("select: a box takes the squadron inside it", ov.sel_squads.has(a.id), str(ov.sel_squads))
	box(ov, Vector2(-90000.0, -90000.0), Vector2(-89900.0, -89900.0))
	tour.check("select: a box over nothing clears", ov.sel_squads.is_empty())
	# The mothership: a click on its hull takes it, and a squadron beats it.
	var ms := world.mothership(team)
	var on_base := RtsSelect.squad_at(world, team, ms.global_position, px) < 0
	if on_base:
		click(ov, ms.global_position)
		tour.check("select: a click on the mothership takes it", ov.sel_base and ov.sel_squads.is_empty())
	click(ov, pa)
	tour.check("select: a click on a squadron replaces the mothership", not ov.sel_base and ov.sel_squads == [a.id])
	# A double-click takes every squadron of that hull; Ctrl takes the whole map.
	var by_hull := {}
	for rec in squads:
		by_hull[rec.hull_id] = int(by_hull.get(rec.hull_id, 0)) + 1
	var hull := ""
	for h: String in by_hull:
		if int(by_hull[h]) >= 2:
			hull = h
			break
	if hull != "":
		var first: Squad = null
		for rec in squads:
			if rec.hull_id == hull:
				first = rec
				break
		var pf := (RtsSelect.ships_of(world, first)[0] as Ship).global_position
		click(ov, pf, false, true, true)
		var want := RtsSelect.same_hull(world, team, hull, Rect2())
		tour.check("select: Ctrl+double-click takes every squadron of the hull on the map", ov.sel_squads.size() == want.size() and want.size() >= 2, "%d of %d" % [ov.sel_squads.size(), want.size()])
	# Add mode: a plain click adds instead of replacing; it goes off with an empty selection.
	ov.set_selection([a.id], false)
	ov.add_mode = true
	click(ov, pb)
	tour.check("select: with Add on a click adds", ov.sel_squads == [a.id, b.id], str(ov.sel_squads))
	ov.clear_selection()
	tour.check("select: Add goes off when the selection empties", not ov.add_mode)
	_orders(tour, world, ov, a, b, pa)
	_layout_a(tour)


## The order checks that need no waiting: the refusals and the lines said; Hold is kept for after the ticks.
static func _orders(tour: Node, world: World, ov: CommandOverlay, a: Squad, b: Squad, pa: Vector2) -> void:
	var sent_before: int = world.orders.next_id
	ov.clear_selection()
	var why := RtsSquadOrders.send(ov, OrderKinds.MOVE, "point", Order.point(pa), ov.sel_squads, "Move")
	tour.check("orders: Move with nothing selected says so and sends nothing", why == "Select squadrons first" and world.orders.next_id == sent_before)
	ov.set_selection([a.id, b.id], true)
	# Open ground: 2,500 units from the squadron toward the middle of the map (whichever team plays, no mothership is there).
	var ground := pa + (Vector2(MapLayout.CX, MapLayout.CY) - pa).normalized() * 2500.0
	why = RtsSquadOrders.smart_order_at(ov, ground)
	tour.check("orders: a right-click on open ground sends Move to the squadrons", why == "" and ov.result_text.begins_with("Move: 2 squadrons") and world.orders.next_id == sent_before + 1, ov.result_text)
	tour.check("orders: a mixed selection says the mothership stays", ov.result_text.contains("the mothership stays"), ov.result_text)
	var ms_pos := world.mothership(world.human_team).global_position
	var kind := RtsSquadOrders.target_kind_at(ov, ms_pos)
	var next_before: int = world.orders.next_id
	why = RtsSquadOrders.smart_order_at(ov, ms_pos)
	tour.check("orders: a right-click on our mothership says later stage and sends nothing", kind == "base" and ov.result_text == "Retreat: later stage" and world.orders.next_id == next_before, "%s / %s" % [kind, ov.result_text])
	ov.set_selection([a.id], false)
	ov.arm("verb_move")
	tour.check("orders: the Move verb arms the tool", ov.tool == "verb_move" and ov.verb_label() == "Move")
	ov.apply_at(ground)
	tour.check("orders: the next click sends Move and uses the tool up", ov.tool == "" and ov.result_text == "Move: 1 squadron", ov.result_text)
	tour.check("orders: the tool says a refusal outside the map", _blocked(ov, a))
	ov.set_selection([a.id], false)
	why = RtsSquadOrders.hold(ov)
	tour.check("orders: Hold is accepted", why == "" and ov.result_text == "Hold: 1 squadron", ov.result_text)
	_held_id = a.id
	ov.set_selection([b.id], false)
	why = RtsSquadOrders.stop(ov)
	tour.check("orders: Stop is accepted", why == "" and ov.result_text == "Stop: 1 squadron", ov.result_text)
	_stopped = [b.id]
	ov.clear_selection()


## Does the armed Move verb refuse a point outside the map (the danger look)?
static func _blocked(ov: CommandOverlay, a: Squad) -> bool:
	ov.set_selection([a.id], false)
	ov.tool = "verb_move"
	var out := ov.blocker_at(Vector2(-5.0, -5.0)) != "" and ov.blocker_at(Vector2(MapLayout.W * 0.5, MapLayout.H * 0.5)) == ""
	ov.tool = ""
	return out


## Home layout A moves the camera on the arrow keys: its camera rows hold them, and layout B keeps W A S D.
static func _layout_a(tour: Node) -> void:
	var before := KeyMap.preset_choice("home_layout")
	KeyMap.set_preset("home_layout", "A")
	var up := KeyMap.effective_keys("home", "camera_up")
	tour.check("camera: layout A moves the camera on the arrow keys", up == ["Up"], str(up))
	KeyMap.set_preset("home_layout", "B")
	up = KeyMap.effective_keys("home", "camera_up")
	tour.check("camera: layout B keeps W", up == ["W"], str(up))
	KeyMap.set_preset("home_layout", before)


## The checks that need the match to have taken ticks since run(): Move, Hold and Stop were carried out.
static func after_ticks(tour: Node, world: World) -> void:
	if _held_id < 0:
		return
	var held: Squad = world.squads.get(_held_id)
	tour.check("orders: after the tick the held squadron holds", held != null and str(held.order.get("kind", "")) == OrderKinds.HOLD, str(held.order) if held != null else "gone")
	if not _stopped.is_empty():
		var s: Squad = world.squads.get(_stopped[0])
		tour.check("orders: after the tick the stopped squadron stops", s != null and str(s.order.get("kind", "")) == OrderKinds.STOP, str(s.order) if s != null else "gone")
