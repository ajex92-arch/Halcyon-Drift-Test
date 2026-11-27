extends RtsUiCheckBase
## WHAT THIS IS: the check of the auto-join choice (E1): the production panel's second footer row "New <hull> join <none or
## F1-F8>" (it fits the panel, folds with it, and both buttons work with a left click), the choice saved in the settings file's
## [rts_ui] section in the way the [keys] section is (other sections kept, a bad entry left out, read back), and the rule: a
## squadron that appears after the first look joins its hull's group, a squadron that existed at the first look does not, and one
## already in a group keeps it. Auto-join only writes a group number.
##
## HOW IT WORKS: the base fills both fleets and finds the HUD. The case points the groups at a settings file of its own (in the
## project's tests folder, removed at the end: never the player's file), clicks the two buttons through their pressed signals,
## reads the file back through RtsUiStore, and makes squadron records for the rule (new records that borrow the ships of an
## existing squadron, all in one frame so the match takes no tick with them, erased again at the end).
##
## HOW TO RUN IT: see RtsUiCheckBase (--test=rts_join_check).
##
## WHO USES IT: main.gd loads it for --test=rts_join_check; the run_checks list has a row for it.


func _init() -> void:
	label = "rts_join_check"


func run() -> void:
	var view := hud.command_view
	var g := view.groups
	var prod := view.prod
	var tmp := ProjectSettings.globalize_path("res://").path_join("tests/rts_join_check_%d.cfg" % OS.get_process_id())
	g.store_path = tmp
	g.join = {}
	hud.layout.apply()
	view.refresh()
	# The row fits the panel and sits under the first footer row.
	check("panel: the panel is the old height plus the second row", is_equal_approx(prod.size.y, CommandView.PROD_H) and is_equal_approx(CommandView.PROD_H, 280.0 + ProductionPanel.JOIN_ROW_H), str(prod.size))
	var inside := true
	var below := true
	for b: Control in [prod._join_new, prod._join_hull, prod._join_word, prod._join_group]:
		inside = inside and Rect2(Vector2.ZERO, prod.size).grow(0.5).encloses(Rect2(b.position, b.size))
		below = below and b.position.y >= ProductionPanel.FOOT_Y + 24.0
	check("panel: the join row lies inside the panel", inside)
	check("panel: and under the first footer row", below)
	check("panel: the row shows when open and folds with the panel", prod._join_hull.visible and prod._join_group.visible)
	prod.set_folded(true)
	check("panel: folded, the row is hidden", not prod._join_hull.visible and not prod._join_group.visible)
	prod.set_folded(false)
	check("panel: open again it shows", prod._join_hull.visible)
	# The buttons step through their choices with a left click.
	check("row: it starts on Fighter, none", prod._join_hull.text == "Fighter" and prod._join_group.text == "none", "%s / %s" % [prod._join_hull.text, prod._join_group.text])
	prod._join_group.pressed.emit()
	check("click: the group button steps to group 1 and says its key label", g.join_of("fighter") == 1 and prod._join_group.text == KeyMap.first_key("shared", "group_1"), prod._join_group.text)
	prod._join_group.pressed.emit()
	check("click: and on to group 2", g.join_of("fighter") == 2)
	for i in 7:
		prod._join_group.pressed.emit()
	check("click: nine clicks later it is back to none", g.join_of("fighter") == 0 and prod._join_group.text == "none", "%d" % g.join_of("fighter"))
	prod._join_hull.pressed.emit()
	check("click: the hull button steps to the next hull, which has its own choice", prod._join_hull_id == "lance" and prod._join_hull.text == "Lance" and prod._join_group.text == "none", prod._join_hull.text)
	var hulls := ProductionPanel.join_hulls()
	check("row: the hulls are the buyable ones, no scout", hulls.size() == 9 and not hulls.has("scout") and hulls[0] == "fighter" and hulls[8] == "battlecruiser", str(hulls))
	for i in 9:
		prod._join_hull.pressed.emit()
	check("click: nine more hull clicks come round to Lance again", prod._join_hull_id == "lance")
	prod._join_hull.pressed.emit()
	check("click: and the next is Bomber", prod._join_hull_id == "bomber")
	# The settings file.
	DirAccess.remove_absolute(tmp)
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", "hard")
	cfg.set_value("keys", "home/hangar", "K")
	cfg.set_value("rts_ui", "other/thing", 7)
	cfg.save(tmp)
	g.set_join("fighter", 3)
	g.set_join("bomber", 5)
	var back := ConfigFile.new()
	check("file: the file loads", back.load(tmp) == OK)
	check("file: the joins are in [rts_ui] as join/<hull>", int(back.get_value("rts_ui", "join/fighter", 0)) == 3 and int(back.get_value("rts_ui", "join/bomber", 0)) == 5)
	check("file: the other sections are kept", str(back.get_value("game", "difficulty", "")) == "hard" and str(back.get_value("keys", "home/hangar", "")) == "K")
	check("file: an entry of the section with another prefix is kept", int(back.get_value("rts_ui", "other/thing", 0)) == 7)
	check("file: read back it is the same choices", RtsUiStore.load_joins(tmp) == {"fighter": 3, "bomber": 5}, str(RtsUiStore.load_joins(tmp)))
	g.set_join("fighter", 0)
	check("file: choosing none removes the entry", RtsUiStore.load_joins(tmp) == {"bomber": 5}, str(RtsUiStore.load_joins(tmp)))
	back = ConfigFile.new()
	back.load(tmp)
	back.set_value("rts_ui", "join/nothing", 2)
	back.set_value("rts_ui", "join/ion", 9)
	back.set_value("rts_ui", "join/flak", "two")
	back.set_value("rts_ui", "join/destroyer", 8)
	back.save(tmp)
	check("file: an unknown hull, group 9 and a word are left out; group 8 is kept", RtsUiStore.load_joins(tmp) == {"bomber": 5, "destroyer": 8}, str(RtsUiStore.load_joins(tmp)))
	check("file: a missing file reads as no joins", RtsUiStore.load_joins(tmp + ".none").is_empty())
	var fresh := Groups.new()
	fresh.setup(world, hud.overlay, world.human_team, tmp)
	check("file: a new match reads the joins at setup", fresh.join_of("bomber") == 5 and fresh.join_of("destroyer") == 8)
	# The rule.
	g.join = {}
	g.set_join("fighter", 3)
	var template: Squad = null
	for rec: Squad in squads():
		if rec.hull_id == "fighter":
			template = rec
			break
	check("rule: the fleet has a fighter squadron to borrow ships from", template != null)
	if template == null:
		DirAccess.remove_absolute(tmp)
		return
	var made: Array[int] = []
	var g2 := Groups.new()
	g2.setup(world, hud.overlay, world.human_team, tmp)
	g2.join = {"fighter": 3}
	g2.sync()
	var late := _clone(template, made)
	g2.sync()
	check("rule: a squadron that appears later joins its hull's group", g2.group_of(late.id) == 3 and g2.members(3) == [late.id], str(g2.members(3)))
	check("rule: the squadrons the first look found did not join", g2.group_of(template.id) == 0)
	var other: Squad = null
	for rec: Squad in squads():
		if rec.hull_id != "fighter" and not made.has(rec.id):
			other = rec
			break
	var kept := _clone(template, made)
	g2.add_group(5, [kept.id])
	g2.sync()
	check("rule: a squadron already in a group keeps it", g2.group_of(kept.id) == 5, str(g2.group_of(kept.id)))
	if other != null:
		var odd := _clone(other, made)
		g2.sync()
		check("rule: a hull with no choice joins nothing", g2.group_of(odd.id) == 0)
	# Choosing none stops it.
	g2.join = {}
	var plain := _clone(template, made)
	g2.sync()
	check("rule: with no choice a new squadron joins nothing", g2.group_of(plain.id) == 0)
	# It is screen state only: no order was queued and the squad records were not touched.
	check("safe: the join rule wrote no order into any record", late.order.is_empty() and kept.order.is_empty())
	for id in made:
		world.squads.erase(id)
	DirAccess.remove_absolute(tmp)


## A new squadron record of `src`'s hull that borrows its ships (a record for the rule only); its id is added to `made`.
func _clone(src: Squad, made: Array[int]) -> Squad:
	var rec := Squad.new()
	var id := 900001 + made.size()
	rec.id = id
	rec.team = src.team
	rec.owner_seat = src.owner_seat
	rec.kind = src.kind
	rec.hull_id = src.hull_id
	rec.max_members = src.max_members
	rec.member_uids = src.member_uids.duplicate()
	rec.state = 0
	world.squads[id] = rec
	made.append(id)
	return rec
