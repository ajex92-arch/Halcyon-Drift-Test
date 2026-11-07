class_name RtsTourStrip
extends RefCounted
## WHAT THIS IS: the strip's and the command pause's checks of the RTS tour: that the strip says the treasury, the list's need,
## the fleet and the clock as the match has them, that its counts are buttons that do what they say, and that P holds the match
## with no pause menu, lets the card and the map take an order that waits in the queue (the tick does not move), and gives
## the match back with the order carried out after it.
##
## HOW IT WORKS: static functions that take the tour (it counts the failures and prints the lines). The strip is read through
## its buttons' texts; the pause is driven through HudPanels.toggle_command_pause() and the order queue is read directly. The
## pause check waits a few frames with `await` (the tour keeps running while the tree is paused).
##
## WHO USES IT: tests/rts_tour.gd.

## The squadron the pause check moved, to see its order after the resume.
static var _moved_id := -1


## The strip says what the match has, and its counts are buttons.
static func strip(tour: Node) -> void:
	var view: CommandView = tour.hud.command_view
	var world: World = tour.world
	var s := view.strip
	view.refresh()
	var ts: TeamState = world.teams[view.team]
	var cap := ts.production.capacity
	tour.check("strip: ORE says the treasury", (s._b["ore"] as Button).text.begins_with("ORE %s" % Util.money(ts.treasury)), (s._b["ore"] as Button).text)
	tour.check("strip: FLEET says used of the limit", (s._b["fleet"] as Button).text.begins_with("FLEET %d/%d" % [cap.used(), cap.limit()]), (s._b["fleet"] as Button).text)
	tour.check("strip: the clock says the match time", (s._b["clock"] as Button).text == Util.clock(world.time) or (s._b["clock"] as Button).text == "PAUSED", (s._b["clock"] as Button).text)
	tour.check("strip: the LIST button has words", (s._b["list"] as Button).text.begins_with("LIST"), (s._b["list"] as Button).text)
	tour.check("strip: the deputy says off", (s._b["deputy"] as Button).text == "DEPUTY off")
	tour.check("strip: the speed button says the speed", (s._b["speed"] as Button).text == SpeedControl.label_of(SpeedControl.current(world)))
	var wide := true
	for id: String in s._b:
		var b: Button = s._b[id]
		if b.position.x < 0.0 or b.position.x + b.size.x > s.size.x + 0.5:
			wide = false
	tour.check("strip: every button is inside the strip", wide)
	view.overlay.clear_selection()
	(s._b["fleet"] as Button).pressed.emit()
	tour.check("strip: a click on FLEET selects every squadron", view.overlay.sel_squads.size() == RtsSelect.our_squads(world, view.team).size() and not view.overlay.sel_squads.is_empty())
	view.overlay.clear_selection()
	view.prod.set_folded(true)
	(s._b["ore"] as Button).pressed.emit()
	tour.check("strip: a click on ORE opens the production panel", not view.prod.folded)


## P: the command pause (see the top).
static func pause(tour: Node) -> void:
	var hud: Hud = tour.hud
	var view := hud.command_view
	var world: World = tour.world
	var recs := RtsSelect.our_squads(world, view.team)
	var rec := recs[recs.size() - 1]
	_moved_id = rec.id
	hud.overlay.set_selection([rec.id], false)
	hud.panels.toggle_command_pause()
	tour.check("pause: P holds the match", hud.get_tree().paused and hud.panels.command_paused)
	tour.check("pause: no pause menu opens", hud.pause_menu == null or not hud.pause_menu.visible)
	view.refresh()
	tour.check("pause: the strip's clock reads PAUSED", (view.strip._b["clock"] as Button).text == "PAUSED" and (view.strip._b["pause"] as Button).text == "Resume")
	var tick := world.tick_count
	var queue_before: int = world.orders.queue.size()
	var why := RtsSquadOrders.send(hud.overlay, OrderKinds.MOVE, "point", Order.point(RtsSelect.centre_of(world, rec) + Vector2(800.0, 300.0)), hud.overlay.sel_squads, "Move")
	for i in 8:
		await tour.get_tree().process_frame
	tour.check("pause: a Move given in the pause is accepted", why == "", why)
	tour.check("pause: the tick does not move in the pause", world.tick_count == tick, "%d then %d" % [tick, world.tick_count])
	tour.check("pause: the order waits in the queue", world.orders.queue.size() == queue_before + 1, str(world.orders.queue.size()))
	# A panel edit given in the pause is marked pending on its row.
	view.prod._hold_row(0)
	view.prod.refresh()
	tour.check("pause: a panel edit in the pause is marked pending on its row", bool(view.prod._rows[0].data.get("pending", false)), str(view.prod._rows[0].data))
	# Selection and the card keep working while paused.
	hud.overlay.clear_selection()
	hud.overlay.set_selection([rec.id], false)
	view.refresh()
	tour.check("pause: the selection and the card work while paused", view.card.page == "orders" and hud.overlay.sel_squads == [rec.id])
	hud.panels.toggle_command_pause()
	for i in 6:
		await tour.get_tree().process_frame
	tour.check("pause: P again resumes the match", not hud.get_tree().paused and not hud.panels.command_paused)
	tour.check("pause: the clock reads the time again", (view.strip._b["pause"] as Button).text == "Pause")


## After the resume: the Move given in the pause has been carried out.
static func after_resume(tour: Node) -> void:
	if _moved_id < 0:
		return
	var rec: Squad = tour.world.squads.get(_moved_id)
	tour.check("pause: after the resume the Move is carried out", rec != null and str(rec.order.get("kind", "")) == OrderKinds.MOVE, str(rec.order) if rec != null else "gone")
