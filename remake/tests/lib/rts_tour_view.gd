class_name RtsTourView
extends RefCounted
## WHAT THIS IS: the checks of the RTS tour about the command view's shell: that the five pieces (the strip, the alert
## slot, the production panel, the card, the selection panel) are all there, inside the window and clear of each
## other and of the top bar and the minimap, and that 21 selected squadrons show as 12 tags plus class tags. It also
## prints each piece's rectangle and the size of the clear block of map.
##
## HOW IT WORKS: static functions that take the tour (it counts the failures and prints the lines). Each reads the
## view's own rectangles (CommandView.rects()) and the HUD's other pieces, so the numbers are the ones a player sees.
##
## WHO USES IT: tests/rts_tour.gd.


## Print "RTS_RECTS" with every piece's rectangle and the clear block, and check the pieces: shown, inside the window,
## and clear of each other and of the top bar and the minimap. `what` names the step.
static func pieces(tour: Node, what: String) -> void:
	var hud: Hud = tour.hud
	var view := hud.command_view
	hud.layout.apply()
	tour.check("view %s: the command view shows for the Admiral" % what, view != null and view.is_showing())
	if view == null or not view.is_showing():
		return
	var vp := hud.get_viewport_rect().size
	var rects := view.rects()
	var others := {"top bar": _rect_of(hud.top_bar), "minimap": _rect_of(hud.minimap)}
	if hud.seat_bar.visible:
		others["seat bar"] = _rect_of(hud.seat_bar)
	var line := "RTS_RECTS %s %dx%d" % [what, int(vp.x), int(vp.y)]
	for k: String in rects:
		var r: Rect2 = rects[k]
		line += " %s=%d,%d,%dx%d" % [k, int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
	print(line)
	var all := rects.duplicate()
	all.merge(others)
	var names := all.keys()
	var bad: Array[String] = []
	for i in names.size():
		var a: Rect2 = all[names[i]]
		if not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(a):
			bad.append("%s leaves the window %s" % [names[i], str(a)])
		for j in range(i + 1, names.size()):
			var b: Rect2 = all[names[j]]
			var hit := a.intersection(b)
			if hit.size.x > 2.0 and hit.size.y > 2.0:
				bad.append("%s overlaps %s by %dx%d" % [names[i], names[j], int(hit.size.x), int(hit.size.y)])
	tour.check("view %s: every piece is inside the window and clear of the others" % what, bad.is_empty(), "; ".join(bad))
	# The clear block of map between the card, the production panel, the top bar and the selection panel.
	var card: Rect2 = rects["card"]
	var prod: Rect2 = rects["prod"]
	var sel: Rect2 = rects["sel"]
	var bar: Rect2 = others["top bar"]
	var block := Rect2(Vector2(card.end.x, bar.end.y), Vector2(prod.position.x - card.end.x, sel.position.y - bar.end.y))
	print("RTS_CLEAR %s %dx%d clear block %dx%d at %d,%d" % [what, int(vp.x), int(vp.y), int(block.size.x), int(block.size.y), int(block.position.x), int(block.position.y)])


## The rectangle of control `c` in the HUD's pixels.
static func _rect_of(c: Control) -> Rect2:
	return Rect2(c.global_position, c.size)


## Select `n` of our squadrons (the mothership too when `base`), refresh the view and place its pieces.
static func select(tour: Node, n: int, base: bool) -> void:
	var hud: Hud = tour.hud
	var ov := hud.overlay
	var ids: Array[int] = []
	for rec: Squad in RtsSelect.our_squads(tour.world, tour.world.human_team):
		if ids.size() < n:
			ids.append(rec.id)
	ov.set_selection(ids, base)
	hud.command_view.refresh()
	hud.layout.apply()
	hud.command_view.refresh()


## With 21 squadrons selected the tags are 12 single tags plus one class tag per hull of the rest, never 21.
static func many(tour: Node) -> void:
	select(tour, 21, false)
	var sel: SelectionPanel = tour.hud.command_view.sel
	var tags := 0
	var squads := 0
	var classes := 0
	for ids: Array in sel._tag_ids:
		if ids.is_empty():
			continue
		tags += 1
		squads += ids.size()
		if ids.size() > 1:
			classes += 1
	var picked: int = tour.hud.overlay.sel_squads.size()
	tour.check("select: %d squadrons selected for the tag check" % picked, picked >= 13, str(picked))
	tour.check("select: past 12 squadrons the tags are 12 plus class tags, not one each", tags < picked and tags >= SelectionPanel.MAX_SINGLE, "%d tags for %d squadrons" % [tags, picked])
	tour.check("select: every selected squadron is in some tag", squads == picked, "%d in tags, %d selected" % [squads, picked])
	print("RTS_TAGS %d squadrons selected: %d tags (%d class tags)" % [picked, tags, classes])


## The danger sweep: a refused or lost state wears the danger colour AND the triangle: the banner while our mothership's systems
## fail, and a feed line that is bad news. The tour puts the mothership back after its picture.
static func danger(tour: Node) -> void:
	var hud: Hud = tour.hud
	var ms: Mothership = tour.world.mothership(tour.world.human_team)
	ms.failure_t = 20.0
	hud.banner.refresh()
	tour.check("danger: the banner's message is in the danger colour with the triangle", hud.banner._mark.visible and hud.banner._sub.get_theme_color("font_color") != Palette.AMBER and hud.banner._title.get_theme_color("font_color") == Palette.DANGER, str(hud.banner._sub.text))
	hud.feed.add_line("A test line of bad news", Palette.DANGER)
	var last := hud.feed.get_child(hud.feed.get_child_count() - 1)
	var has_mark := false
	for c in last.get_children():
		if c is DangerMark:
			has_mark = true
	tour.check("danger: a bad-news feed line carries the triangle", has_mark)
	hud.feed.add_line("A test line of good news", Palette.AMBER)
	var good := hud.feed.get_child(hud.feed.get_child_count() - 1)
	tour.check("danger: good news keeps its amber and has no triangle", good.get_child_count() == 0)
	# Let the containers lay the new lines out before the picture and the dump.
	for i in 4:
		await tour.get_tree().process_frame
	hud.banner.refresh()
	for i in 2:
		await tour.get_tree().process_frame
	ms.failure_t = 0.0

## Every page of the card under home layouts A and C (B is the default the other steps run in): the layout is set, the card's width and cells
## are checked, each page gets a picture and a layout dump. The layout is put back to what it was.
static func layouts(tour: Node) -> void:
	var hud: Hud = tour.hud
	var view := hud.command_view
	var before := KeyMap.preset_choice("home_layout")
	for preset: String in ["A", "C"]:
		KeyMap.set_preset("home_layout", preset)
		view.overlay.set_selection([RtsSelect.our_squads(tour.world, tour.world.human_team)[0].id], false)
		hud.layout.apply()
		view.refresh()
		tour.check("layout %s: the card is %d px wide" % [preset, int(CommandView.CARD_W_A if preset == "A" else CommandView.CARD_W)], is_equal_approx(view.card.size.x, CommandView.CARD_W_A if preset == "A" else CommandView.CARD_W), str(view.card.size))
		for pg: String in CardPages.PAGES:
			view.card.set_page(pg)
			view.refresh()
			var shown := 0
			for id: String in view.card._grid_ids:
				if id != "":
					shown += 1
			var want := (CardPages.page(preset, pg)["grid"] as Array).filter(func(s: String) -> bool: return s != "").size()
			tour.check("layout %s, page %s: the grid shows its %d cells" % [preset, pg, want], shown == want, str(shown))
			await tour._shot("r13_%s_%s" % [preset, pg])
	KeyMap.set_preset("home_layout", before)
	view.overlay.clear_selection()
	view.refresh()