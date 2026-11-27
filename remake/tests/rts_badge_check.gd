extends RtsUiCheckBase
## WHAT THIS IS: the check of the F badges on the selection tags: a tag of a squadron that is in a group shows the key
## label of that group (read from the key map, "F1"); a squadron in no group has no badge; a class tag (many squadrons
## merged) shows one only when they are all in the same group; the compact tags of a big selection show it too; and a
## badge lies inside its tag.
##
## HOW IT WORKS: the base fills both fleets and finds the HUD; the case sets groups through hud.command_view.groups, selects
## squadrons through the overlay, refreshes the view and reads the pooled tags of hud.command_view.sel.
##
## HOW TO RUN IT: see RtsUiCheckBase (--test=rts_badge_check).
##
## WHO USES IT: main.gd loads it for --test=rts_badge_check; the run_checks list has a row for it.


func _init() -> void:
	label = "rts_badge_check"


func run() -> void:
	var view := hud.command_view
	var g := view.groups
	var ov := hud.overlay
	var sel := view.sel
	var all := squads()
	check("setup: the fleet fill made at least 14 squadrons", all.size() >= 14, "%d" % all.size())
	if all.size() < 14:
		return
	var a := all[0].id
	var b := all[1].id
	var d := all[3].id
	g.set_group(1, [a, b])
	g.set_group(2, [d])
	ov.set_selection([a, b, d, all[4].id], false)
	view.refresh()
	hud.layout.apply()
	view.refresh()
	var shown := _tags()
	check("tags: four squadrons make four tags", shown.size() == 4, "%d" % shown.size())
	var want1 := KeyMap.first_key("shared", "group_1")
	var want2 := KeyMap.first_key("shared", "group_2")
	check("text: the badge text is the key label from the key map (%s, %s)" % [want1, want2], want1 != "" and want2 != "")
	check("badge: a's tag shows the label of group 1", _badge_text(sel, a) == want1, _badge_text(sel, a))
	check("badge: b's tag shows the label of group 1", _badge_text(sel, b) == want1, _badge_text(sel, b))
	check("badge: d's tag shows the label of group 2", _badge_text(sel, d) == want2, _badge_text(sel, d))
	check("badge: a squadron in no group has none", _badge_text(sel, all[4].id) == "", _badge_text(sel, all[4].id))
	for i in sel.POOL:
		var t: SelectionTag = sel._tags[i]
		if t.visible and t._badge.visible:
			var inside := Rect2(Vector2.ZERO, t.size).grow(0.5).encloses(Rect2(t._badge.position, t._badge.size))
			check("geometry: the badge of tag %d lies inside the tag" % i, inside, "%s in %s" % [str(Rect2(t._badge.position, t._badge.size)), str(t.size)])
	# A change of group shows at the next refresh, with no change of the selection.
	g.set_group(3, [d])
	view.refresh()
	check("update: d moved to group 3 and its badge follows", _badge_text(sel, d) == KeyMap.first_key("shared", "group_3"), _badge_text(sel, d))
	# A class tag: every squadron in one group shows it; a mix shows none.
	check("class: ids in one group give that badge", sel._badge_of([a, b]) == want1)
	check("class: ids in two groups give none", sel._badge_of([a, d]) == "")
	check("class: one ungrouped id gives none", sel._badge_of([a, all[4].id]) == "")
	check("class: no ids give none", sel._badge_of([]) == "")
	# A big selection: compact tags, and class tags once past twelve squadrons.
	var ids: Array[int] = []
	for rec in all:
		ids.append(rec.id)
	g.set_group(4, ids)
	ov.set_selection(ids, false)
	view.refresh()
	hud.layout.apply()
	view.refresh()
	var compact := 0
	var badged := 0
	var tags := 0
	for i in sel.POOL:
		var t: SelectionTag = sel._tags[i]
		if t.visible:
			tags += 1
			if t.compact:
				compact += 1
			if t._badge.visible and t._badge.text == KeyMap.first_key("shared", "group_4"):
				badged += 1
	check("big selection: the tags are compact", compact == tags and tags > 12, "%d of %d" % [compact, tags])
	check("big selection: every tag, class tags too, wears group 4's badge", badged == tags and tags > 0, "%d of %d" % [badged, tags])
	# Taking the squadrons out of every group clears the badges.
	for n in range(1, Groups.COUNT + 1):
		g.set_group(n, [])
	view.refresh()
	var left := 0
	for i in sel.POOL:
		if (sel._tags[i] as SelectionTag)._badge.visible and (sel._tags[i] as SelectionTag).visible:
			left += 1
	check("clear: with no groups no badge shows", left == 0, "%d" % left)


## The visible tags.
func _tags() -> Array[SelectionTag]:
	var out: Array[SelectionTag] = []
	for t: SelectionTag in hud.command_view.sel._tags:
		if t.visible:
			out.append(t)
	return out


## The badge text of the tag that stands for squadron `id` alone ("" when it has no badge or no tag of its own).
func _badge_text(sel: SelectionPanel, id: int) -> String:
	for i in sel.POOL:
		if (sel._tag_ids[i] as Array) == [id]:
			var t: SelectionTag = sel._tags[i]
			return t._badge.text if t._badge.visible else ""
	return "no tag"
