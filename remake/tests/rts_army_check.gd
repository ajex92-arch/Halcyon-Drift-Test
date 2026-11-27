extends RtsUiCheckBase
## WHAT THIS IS: the check of the army row (D1): a card for each group that has squadrons, a card for each hull of the squadrons in no
## group, the "F_ + save" card and the Idle card, with the counts, the key labels (from the key map) and the state sign each shows;
## a click selects, Shift+click adds, a double-click centres, the save card and the Idle card do their work, the detail opens after
## CARD_HOVER_S and closes again, past eight cards the hull cards fold into "+N" and the cards narrow to fit, the attacked frame is
## steady, and every card draws without a script error.
##
## HOW IT WORKS: the base fills both fleets and finds the HUD; the case sets groups through hud.command_view.groups, refreshes the
## view and reads the pooled cards of hud.command_view.army. A click is made by calling the row's click() with the flags a mouse
## press carries (the same function a card's gui_input reaches); the hover is made by the row's own hover functions and its
## _process() with a frame time. The held-key route (a group key held opens the detail) needs a real key down, so it is not
## driven here.
##
## HOW TO RUN IT: see RtsUiCheckBase (--test=rts_army_check).
##
## WHO USES IT: main.gd loads it for --test=rts_army_check; the run_checks list has a row for it.


func _init() -> void:
	label = "rts_army_check"


## The shown cards of kind `kind`.
func _of(kind: String) -> Array[ArmyCard]:
	var out: Array[ArmyCard] = []
	for c in hud.command_view.army._shown:
		if c.kind == kind:
			out.append(c)
	return out


func run() -> void:
	var view := hud.command_view
	var army := view.army
	var g := view.groups
	var ov := hud.overlay
	var all := squads()
	check("setup: the fleet fill made at least 12 squadrons", all.size() >= 12, "%d" % all.size())
	if all.size() < 12:
		return
	g.store_path = ProjectSettings.globalize_path("res://").path_join("tests/rts_army_check_%d.cfg" % OS.get_process_id())
	# Idle states of our own making: every squadron moving, so the row is predictable.
	for rec in all:
		rec.state = 1
		rec.order = {"kind": "move", "tick": 0}
	var a := all[0]
	var b := all[1]
	var c := all[2]
	var d := all[3]
	var e := all[4]
	g.set_group(1, [a.id, b.id, c.id])
	g.set_group(2, [d.id, e.id])
	# Group 8 takes every other squadron except those of two hulls, so the hull cards stay unfolded (2 hulls + 3 groups + save + idle).
	var kinds: Array[String] = []
	for rec in all.slice(5):
		if not kinds.has(rec.hull_id):
			kinds.append(rec.hull_id)
	check("setup: the fleet has at least three hulls past the first five squadrons", kinds.size() >= 3, str(kinds))
	var keep := kinds.slice(0, 2)
	var in_eight: Array[int] = []
	for rec in all.slice(5):
		if not keep.has(rec.hull_id):
			in_eight.append(rec.id)
	g.set_group(8, in_eight)
	var ungrouped := all.size() - 5 - in_eight.size()
	hud.layout.apply()
	view.refresh()
	check("row: the army row shows with the view", army.is_visible_in_tree() and army.size.y == ArmyCards.ROW_H, str(army.size))
	var groups_shown := _of("group")
	check("groups: a card for each of the three groups", groups_shown.size() == 3, "%d" % groups_shown.size())
	var key1 := KeyMap.first_key("shared", "group_1")
	check("groups: the first card carries the key label of group 1 (%s) from the key map" % key1, groups_shown[0].data["key"] == key1 and key1 != "", str(groups_shown[0].data["key"]))
	var ships_a := 0
	var bought_a := 0
	var hull_sum := 0.0
	for rec in [a, b, c]:
		var ships := RtsSelect.ships_of(world, rec)
		ships_a += ships.size()
		bought_a += rec.max_members
		for s: Ship in ships:
			hull_sum += s.hull_frac()
	check("groups: the count line is squadrons and ships alive of bought", groups_shown[0].data["count"] == "3 sq · %d/%d" % [ships_a, bought_a], str(groups_shown[0].data["count"]))
	check("groups: the hull bar is the hull summed over the ships bought", absf(float(groups_shown[0].data["hull"]) - hull_sum / float(bought_a)) < 0.02, str(groups_shown[0].data["hull"]))
	check("groups: moving squadrons show the moving sign", groups_shown[0].data["state"] == "moving", str(groups_shown[0].data["state"]))
	# The hull cards: every squadron in no group is counted once.
	var counted := 0
	for card in _of("class"):
		counted += int(str(card.data["count"]).split(" ")[0])
	check("hulls: the hull cards count every squadron in no group", counted == ungrouped, "%d of %d" % [counted, ungrouped])
	check("hulls: one card for each hull, with its tag", _of("class").size() >= 1 and _of("class").all(func(card: ArmyCard) -> bool: return str(card.data["tag"]) != ""))
	var save := _of("save")
	check("save: the empty card names the first free group, 3", save.size() == 1 and int(save[0].data["n"]) == 3 and save[0].data["key"] == KeyMap.first_key("shared", "group_3"), str(save.size()))
	check("idle: the Idle card is last", army._shown.back().kind == "idle" and army._shown.back().data["key"] == KeyMap.first_key("home", "idle_next"))
	# The cards lie in a row, inside the row, without overlapping.
	var ok := true
	var prev := -1.0
	for card in army._shown:
		ok = ok and card.position.x >= prev - 0.01 and card.position.x + card.size.x <= army.size.x + 0.5
		prev = card.position.x + card.size.x
	check("layout: the cards lie left to right inside the row", ok, "%s in %s" % [str(army._shown.size()), str(army.size)])
	# The win-odds mark: off by default, so no card's odds field holds a mark; with the option on and an enemy ship in sight near the
	# first group's squadrons the group card (and a hull card) carry the mark WinOdds gives, and the save and idle cards none.
	check("odds: with the option off (its default) no card's odds field holds a mark", not Game.win_odds and army.entries.all(func(e: Dictionary) -> bool: return str(e.get("odds", "")) == ""))
	var foe: Ship = null
	for s: Ship in world.ships:
		if s.alive and s.team != world.human_team:
			foe = s
			break
	if foe != null:
		var foe_at := foe.global_position
		var foe_mask := foe.visible_mask
		var near := Vector2.ZERO
		for id in g.members(1):
			near += RtsSelect.centre_of(world, world.squads[id])
		near /= float(g.members(1).size())
		foe.global_position = near + Vector2(300.0, 0.0)
		foe.visible_mask = foe_mask | (1 << world.human_team)
		Game.win_odds = true
		view.refresh()
		var want_g: Dictionary = WinOdds.of(world, g.members(1))
		check("odds: with the option on, the group card's odds field is the mark of WinOdds", want_g["mark"] != "none" and _of("group")[0].data["odds"] == want_g["mark"], "%s vs %s" % [str(_of("group")[0].data.get("odds")), str(want_g)])
		var class_ids0: Array[int] = []
		class_ids0.assign(_of("class")[0].data["ids"])
		check("odds: and a hull card's field is the mark of its own squadrons", str(_of("class")[0].data["odds"]) == ("" if WinOdds.of(world, class_ids0)["mark"] == "none" else str(WinOdds.of(world, class_ids0)["mark"])))
		check("odds: the save card and the Idle card carry none", str(_of("save")[0].data.get("odds", "")) == "" and str(_of("idle")[0].data.get("odds", "")) == "")
		foe.visible_mask = foe_mask & ~(1 << world.human_team)
		view.refresh()
		check("odds: the foe out of sight, the mark is gone on the next beat", str(_of("group")[0].data["odds"]) == "")
		Game.win_odds = false
		foe.global_position = foe_at
		foe.visible_mask = foe_mask
		view.refresh()
	# Clicks.
	ov.clear_selection()
	army.click(groups_shown[0], false, false)
	check("click: a group card selects its squadrons", ov.sel_squads == [a.id, b.id, c.id], str(ov.sel_squads))
	ov.set_selection([all[5].id], false)
	army.click(groups_shown[0], true, false)
	check("click: Shift+click adds the selection to the group", g.group_of(all[5].id) == 1, str(g.group_of(all[5].id)))
	var middle := Vector2.ZERO
	for id in g.members(1):
		middle += RtsSelect.centre_of(world, world.squads[id])
	middle /= float(g.members(1).size())
	world.camera.look_at_point(middle + Vector2(40000.0, 40000.0))
	army.click(groups_shown[0], false, true)
	check("click: a double-click selects and centres the camera", ov.sel_squads == g.members(1) and world.camera._free_pos.distance_to(middle) < 1.0)
	ov.set_selection([all[6].id, all[7].id], false)
	army.click(_of("save")[0], false, false)
	check("save: a click sets group 3 to the selection", g.members(3) == [all[6].id, all[7].id], str(g.members(3)))
	view.refresh()
	check("save: the card moves on to group 4", int(_of("save")[0].data["n"]) == 4)
	ov.clear_selection()
	army.click(_of("save")[0], false, false)
	check("save: with nothing selected it refuses and sets nothing", g.members(4).is_empty() and not ov.result_ok, ov.result_text)
	var first_class := _of("class")[0]
	var class_ids: Array[int] = []
	class_ids.assign(first_class.data["ids"])
	world.camera.look_at_point(Vector2(60000.0, 60000.0))
	army.click(first_class, false, true)
	check("click: a hull card selects its squadrons; double-click centres", ov.sel_squads == class_ids and world.camera._free_pos.distance_to(Vector2(60000.0, 60000.0)) > 1000.0, str(ov.sel_squads))
	# The Idle card: a click is next, a double-click is all.
	all[8].state = 0
	all[8].order = {}
	all[9].state = 0
	all[9].order = {}
	view.refresh()
	var idle_card: ArmyCard = _of("idle")[0]
	check("idle: the card counts the idle squadrons", idle_card.data["count"] == "2 sq" and int(str(idle_card.data["count"]).split(" ")[0]) == view.tools.idle_ids().size(), str(idle_card.data["count"]))
	army.click(idle_card, false, false)
	check("idle: a click selects the next idle squadron", ov.sel_squads == [all[8].id], str(ov.sel_squads))
	army.click(idle_card, false, true)
	check("idle: a double-click selects them all", ov.sel_squads == [all[8].id, all[9].id], str(ov.sel_squads))
	# The state sign: the most common state, fighting ahead of moving ahead of idle when they tie.
	a.state = 2
	b.state = 1
	c.state = 1
	view.refresh()
	check("state: two moving and one fighting show moving", _of("group")[0].data["state"] == "moving")
	c.state = 0
	c.order = {}
	all[5].state = 4
	view.refresh()
	check("state: a four-way tie (fighting, moving, idle, docked: group 1 holds a, b, c and the squadron added by Shift+click) shows fighting", _of("group")[0].data["state"] == "fighting", str(_of("group")[0].data["state"]))
	for rec in [a, b, c, all[5]]:
		rec.state = 0
		rec.order = {}
	view.refresh()
	check("state: all idle shows idle", _of("group")[0].data["state"] == "idle")
	for rec in [a, b, c, all[5]]:
		rec.state = 1
		rec.order = {"kind": "move", "tick": 0}
	# The detail: a row for each squadron after the hover time, gone when the mouse leaves.
	var card1: ArmyCard = _of("group")[0]
	army._on_hover(card1)
	army._process(RtsUiCalls.CARD_HOVER_S * 0.5)
	check("detail: closed before the hover time", army.open_card() == null and not army._detail.visible)
	army._process(RtsUiCalls.CARD_HOVER_S * 0.6)
	check("detail: open after the hover time", army.open_card() == card1 and army._detail.visible)
	var rows := 0
	for l in army._lines:
		if l.visible:
			rows += 1
	check("detail: a head line and a row for each of the group's squadrons", rows == 1 + g.members(1).size(), "%d rows" % rows)
	check("detail: it stands above the row", army._detail.position.y < 0.0)
	# The detail's buttons: Set, Add and Remove selection for the card's group, Set and Add with their keys from the key map.
	var btns := army._btns
	check("buttons: a group card's detail shows its three buttons", btns.size() == 3 and btns.all(func(b: Button) -> bool: return b.visible))
	check("buttons: Set and Add print the group's key from the key map; Remove has no key and prints none", btns[0].text == "Ctrl+%s  Set to selection" % key1 and btns[1].text == "Shift+%s  Add selection" % key1 and btns[2].text == "Remove selection", "%s / %s / %s" % [btns[0].text, btns[1].text, btns[2].text])
	var box := Rect2(Vector2.ZERO, army._detail.size)
	check("buttons: they lie inside the detail box, below the squadron rows", btns.all(func(b: Button) -> bool: return box.encloses(Rect2(b.position, b.size)) and b.position.y >= float(rows) * ArmyCards.DETAIL_LINE_H))
	check("buttons: the pointer on the detail keeps it open (the box touches the row); the row itself is not the detail", army.in_detail(army._detail.position + Vector2(10.0, 10.0)) and army.in_detail(Vector2(army._detail.position.x + 10.0, -1.0)) and not army.in_detail(Vector2(10.0, 10.0)))
	var members0 := g.members(1)
	var extra := all[10]
	ov.set_selection([extra.id], false)
	check("buttons: Add selection adds the selected squadron to the group (as Shift+F)", army.detail_action("add") and g.group_of(extra.id) == 1 and g.members(1).size() == members0.size() + 1, str(g.members(1)))
	btns[2].pressed.emit()
	check("buttons: a press on Remove selection takes it out again", g.group_of(extra.id) == 0 and g.members(1) == members0 and ov.result_ok, str(g.members(1)))
	check("buttons: Remove with none of the selection in the group refuses and changes nothing", not army.detail_action("remove") and g.members(1) == members0 and not ov.result_ok, ov.result_text)
	ov.set_selection([a.id, b.id], false)
	btns[0].pressed.emit()
	check("buttons: a press on Set to selection makes the group the selection (as Ctrl+F)", g.members(1) == [a.id, b.id] and ov.result_ok, str(g.members(1)))
	check("buttons: the detail is still open after a press", army.open_card() == card1 and army._detail.visible)
	ov.clear_selection()
	check("buttons: with nothing selected Set refuses and sets nothing", not army.detail_action("set") and g.members(1) == [a.id, b.id] and not ov.result_ok, ov.result_text)
	g.set_group(1, members0)
	view.refresh()
	army._on_unhover(card1)
	army._process(0.016)
	check("detail: closed when the mouse leaves", army.open_card() == null and not army._detail.visible)
	# Folding: eight groups of one squadron each leave no room for the hull cards.
	for n in range(1, Groups.COUNT + 1):
		g.set_group(n, [])
	for n in range(1, Groups.COUNT + 1):
		g.set_group(n, [all[n - 1].id])
	view.refresh()
	var fold := _of("fold")
	var hulls_left := _of("class").size()
	check("fold: with all eight groups used the hull cards fold into one +N card", fold.size() == 1 and hulls_left == 0, "%d fold, %d hull cards" % [fold.size(), hulls_left])
	check("fold: the +N card counts the folded kinds", fold.size() == 1 and str(fold[0].data["tag"]).begins_with("+") and int(str(fold[0].data["tag"]).substr(1)) == fold[0].data["classes"].size())
	check("fold: no save card when every group is used", _of("save").is_empty())
	ok = true
	prev = -1.0
	for card in army._shown:
		ok = ok and card.position.x >= prev - 0.01 and card.position.x + card.size.x <= army.size.x + 0.5 and card.size.x >= ArmyCards.MIN_W - 0.01
		prev = card.position.x + card.size.x
	check("fold: the narrowed cards still lie in the row", ok and army._shown.size() == 10, "%d cards" % army._shown.size())
	army._on_hover(fold[0])
	army._process(RtsUiCalls.CARD_HOVER_S + 0.01)
	check("fold: resting on +N lists the folded kinds", army.open_card() == fold[0] and fold[0].data["lines"].size() == fold[0].data["classes"].size())
	check("buttons: a card that is no group has no buttons in its detail", army._btns.all(func(b: Button) -> bool: return not b.visible))
	check("buttons: with no group card's detail open a button does nothing", not army.detail_action("set"))
	army._on_unhover(fold[0])
	army._process(0.016)
	# The attacked frame: a steady flag set and cleared with the state.
	g.set_group(1, [a.id, b.id, c.id])
	view.refresh()
	army.set_attacked([b.id])
	view.refresh()
	check("attacked: the group card with the squadron in danger carries the frame", _of("group")[0].data["danger"] == true and _of("group")[1].data["danger"] == false)
	army.set_attacked([])
	view.refresh()
	check("attacked: cleared with the state", _of("group")[0].data["danger"] == false)
	army.set_attacked([b.id])
	view.refresh()
	# Every shown card draws (the signs, the bars, the frame) without a script error.
	for i in 4:
		await get_tree().process_frame
	var undrawn := 0
	for card in army._shown:
		if card.draws == 0:
			undrawn += 1
	check("draw: every shown card drew its art", undrawn == 0, "%d undrawn" % undrawn)
	army.set_attacked([])
	# Restore the groups and the selection so nothing leaks into the match.
	for n in range(1, Groups.COUNT + 1):
		g.set_group(n, [])
	ov.clear_selection()
	if g.store_path != "" and FileAccess.file_exists(g.store_path):
		DirAccess.remove_absolute(g.store_path)
