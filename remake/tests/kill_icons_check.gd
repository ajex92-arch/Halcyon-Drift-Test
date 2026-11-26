extends Node
## WHAT THIS IS: the kill icons check (T-126b, Set 2, "Solid icons"). It proves the 17 glyphs of KillIcons are in their 16 x 16
## box, that none of them is a plain disc, a triangle (the Vhorr team mark is a point-down triangle, the danger sign an upright
## one) or has fewer parts than its drawing needs, that every kind of blow and every kind of source maps to the glyph the
## table gives (and anything else to glyph 13), that the feed's own count of kills in a row ends a streak and makes an ace
## at the right kill, and that a feed line holds its icon between the names with the two frames where they belong.
##
## HOW IT WORKS: setup() runs the parts and prints "kill_icons_check: N failures" (a FAIL line for each). (a) Each glyph's
## parts: the colour parts lie in the box (their strokes included), a glyph is never one filled disc, no filled part is a
## three-corner polygon, the calls per glyph follow the design's list, glyph 14 to 17 end with their break or strike. (b) The
## mapping: every Rules.W_* kind, a turret, a minion, a mothership and a Scum as the source, a source the note has lost, and a kind
## the table does not know. (c) HudFeed.tally_kill(): three kills in a row make an ace at the third, a victim with three kills ends
## a streak, a crew ship counts nothing, a kill of the killer's own team counts nothing. (d) HudFeed.add_parts() with an icon
## piece and an ace's name piece: the row's children are the mark, the name, the icon (framed when the streak is set), the second
## mark and the victim's words. (e) The legend holds all 17 icons and both frames. (f) HudFeed._ship_line() builds the real
## line's pieces in order for a pilot, a turret, the Scum, an asteroid, a crew victim, a victim with no profile and a unit that is
## already gone. (g) The shot shapes' pure helpers (ProjectilesDraw): head floor, tail base, sizes, barb and dart corners.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=kill_icons_check
##
## WHO USES IT: main.gd loads it for --test=kill_icons_check (it calls setup()); it is a row of the check list.

## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built (the World is not needed).
func setup(_w: World) -> void:
	_glyphs()
	_mapping()
	_tally()
	_feed_line()
	_ship_lines()
	_shot_helpers()
	_legend()
	print("kill_icons_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Part (a): the shapes.
func _glyphs() -> void:
	# The design's drawing calls per icon, parts only (the dark pass doubles the colour ones): turret 3, minion 1, mothership 2, Scum 2,
	# rock 2, guns 6, Lance 1, torpedo 3, flak 1, shell 2, ion 2, special 1, other 2; the structure lines add their break (turret 4,
	# post 3: diamond, dot, break; bay 4: square, two plus bars, break; den 4: the Scum cross, the gap, the strike).
	var total_parts := [0, 3, 1, 2, 2, 2, 6, 1, 3, 1, 2, 2, 1, 2, 4, 3, 4, 4]
	_check("glyphs: there are 17", KillIcons.COUNT == 17)
	_check("glyphs: glyph 0 and 18 do not exist", KillIcons.parts(0).is_empty() and KillIcons.parts(18).is_empty())
	for id in range(1, KillIcons.COUNT + 1):
		var ps := KillIcons.parts(id)
		_check("glyph %d: has parts" % id, not ps.is_empty())
		var b := KillIcons.bounds(id)
		_check("glyph %d: inside the 16 x 16 box (%s)" % [id, str(b)], b.position.x >= -0.01 and b.position.y >= -0.01 and b.end.x <= 16.01 and b.end.y <= 16.01)
		_check("glyph %d: not empty (%s)" % [id, str(b.size)], b.size.x >= 5.0 and b.size.y >= 5.0)
		var coloured := 0
		var discs := 0
		var triangle := false
		for p: Dictionary in ps:
			if not bool(p["cut"]):
				coloured += 1
				if String(p["op"]) == "disc":
					discs += 1
				if String(p["op"]) == "poly" and (p["pts"] as PackedVector2Array).size() == 3:
					triangle = true
		_check("glyph %d: not a plain disc" % id, not (coloured == 1 and discs == 1))
		_check("glyph %d: no triangle part (the team mark and the danger sign are triangles)" % id, not triangle)
		_check("glyph %d: its parts follow the design (%d)" % [id, ps.size()], ps.size() == int(total_parts[id]))
		_check("glyph %d: calls are the parts plus one dark call per colour part" % id, KillIcons.calls(id) == ps.size() + coloured)
	# The break and the strike.
	for id in [KillIcons.TURRET_LOST, KillIcons.POST_LOST, KillIcons.BAY_LOST]:
		var ps := KillIcons.parts(id)
		var last := ps[ps.size() - 1] as Dictionary
		_check("glyph %d: ends with the break, a 2.2 px zigzag cut" % id, bool(last["cut"]) and String(last["op"]) == "pline" and (last["pts"] as PackedVector2Array).size() == 4 and is_equal_approx(float(last["w"]), 2.2))
	var den := KillIcons.parts(KillIcons.DEN_CLEARED)
	_check("glyph 17: the Scum cross, a dark gap, then the 1.5 px strike", den.size() == 4 and bool((den[2] as Dictionary)["cut"]) and not bool((den[3] as Dictionary)["cut"]) and is_equal_approx(float((den[3] as Dictionary)["w"]), 1.5))
	_check("glyph 14 is glyph 1 and the break", KillIcons.parts(KillIcons.TURRET_LOST).size() == KillIcons.parts(KillIcons.TURRET).size() + 1)
	_check("glyphs 5 and 13 have a crack: ring and rock", KillIcons.parts(KillIcons.OTHER).size() == 2 and KillIcons.parts(KillIcons.ROCK).size() == 2)
	_check("every glyph has words for the legend", KillIcons.WORDS.size() == KillIcons.COUNT + 1)


## A blow of weapon `kind` from `src` (a unit, or null: no source).
func _blow(kind: int, src: Unit = null) -> DamageInfo:
	return DamageInfo.from_unit(src, 10.0, kind, Vector2.ZERO)


## A unit of `kind` and `team`, not in the tree (only its fields are read).
func _unit(kind: int, team: int) -> Unit:
	var u: Unit = Ship.new() if kind == Unit.K_SHIP else Unit.new()
	u.kind = kind
	u.team = team
	u.uid = 900 + kind
	return u


## Part (b): the mapping of blows to glyphs.
func _mapping() -> void:
	var by_kind := {Rules.W_BOLT: 6, Rules.W_PD: 6, Rules.W_LANCE: 7, Rules.W_TORP: 8, Rules.W_FLAK: 9, Rules.W_SHELL: 10, Rules.W_ION: 11, Rules.W_COLLISION: 5, Rules.W_PURE: 12}
	for k: int in by_kind:
		_check("mapping: kind %d with no source is glyph %d" % [k, by_kind[k]], KillIcons.glyph_for(_blow(k)) == by_kind[k])
	for k in range(Rules.W_BOLT, Rules.W_PURE + 1):
		_check("mapping: kind %d has a row in the table" % k, KillIcons.KIND_GLYPH.has(k))
	_check("mapping: a kind the table does not know is glyph 13", KillIcons.glyph_for(_blow(99)) == 13)
	_check("mapping: no blow at all is glyph 13", KillIcons.glyph_for(null) == 13)
	var turret := _unit(Unit.K_TURRET, Rules.CINDER)
	var minion := _unit(Unit.K_MINION, Rules.HALCYON)
	var mother := _unit(Unit.K_MOTHERSHIP, Rules.CINDER)
	var scum_ship := _unit(Unit.K_SHIP, Rules.NEUTRAL)
	var scum_den := _unit(Unit.K_MONSTER, Rules.NEUTRAL)
	var pilot := _unit(Unit.K_SHIP, Rules.HALCYON)
	_check("mapping: a turret's bolt is glyph 1", KillIcons.glyph_for(_blow(Rules.W_BOLT, turret)) == 1)
	_check("mapping: a minion's bolt is glyph 2", KillIcons.glyph_for(_blow(Rules.W_BOLT, minion)) == 2)
	_check("mapping: a mothership's shell is glyph 3", KillIcons.glyph_for(_blow(Rules.W_SHELL, mother)) == 3)
	_check("mapping: a Scum ship's bolt is glyph 4", KillIcons.glyph_for(_blow(Rules.W_BOLT, scum_ship)) == 4)
	_check("mapping: a Scum den's torpedo is glyph 4", KillIcons.glyph_for(_blow(Rules.W_TORP, scum_den)) == 4)
	_check("mapping: a pilot's torpedo is glyph 8 (the weapon, not the source)", KillIcons.glyph_for(_blow(Rules.W_TORP, pilot)) == 8)
	_check("mapping: a pilot's lance is glyph 7", KillIcons.glyph_for(_blow(Rules.W_LANCE, pilot)) == 7)
	# A source the note has lost (freed): read from what the note kept.
	var lost_minion := _blow(Rules.W_BOLT, minion)
	lost_minion.source = null
	_check("mapping: a freed minion is still glyph 2", KillIcons.glyph_for(lost_minion) == 2)
	var lost_scum := _blow(Rules.W_BOLT, scum_ship)
	lost_scum.source = null
	_check("mapping: a freed Scum ship is still glyph 4", KillIcons.glyph_for(lost_scum) == 4)
	var lost_pilot := _blow(Rules.W_FLAK, pilot)
	lost_pilot.source = null
	_check("mapping: a freed pilot is glyph 9 by its weapon", KillIcons.glyph_for(lost_pilot) == 9)
	for u in [turret, minion, mother, scum_ship, scum_den, pilot]:
		(u as Node).free()


## Part (c): the feed's own count of kills in a row.
func _tally() -> void:
	var feed := HudFeed.new()
	var ash := PilotProfile.new("Ash", Rules.HALCYON, 90, false)
	var wren := PilotProfile.new("Wren", Rules.CINDER, 91, false)
	var crew := PilotProfile.new("Crew", Rules.CINDER, 92, false)
	crew.is_crew = true
	var r1 := feed.tally_kill(wren, ash, Rules.CINDER)
	_check("tally: first kill is no ace and ends no streak", not r1["ace"] and not r1["streak"])
	var r2 := feed.tally_kill(wren, ash, Rules.CINDER)
	_check("tally: second kill is no ace", not r2["ace"])
	var r3 := feed.tally_kill(wren, ash, Rules.CINDER)
	_check("tally: the third kill in a row makes an ace", r3["ace"])
	var r4 := feed.tally_kill(wren, ash, Rules.CINDER)
	_check("tally: the fourth makes no new ace", not r4["ace"])
	var r5 := feed.tally_kill(ash, wren, Rules.HALCYON)
	_check("tally: killing a pilot with 4 kills in a row ends a streak", r5["streak"])
	var r6 := feed.tally_kill(ash, wren, Rules.HALCYON)
	_check("tally: the dead pilot's count restarted: no streak the next time", not r6["streak"])
	var r7 := feed.tally_kill(wren, ash, Rules.CINDER)
	_check("tally: the count of the pilot who died started again (one kill)", not r7["ace"] and not r7["streak"])
	var r8 := feed.tally_kill(crew, ash, Rules.CINDER)
	_check("tally: a crew ship counts nothing", not r8["ace"] and not r8["streak"])
	var before := int(feed._run.get(ash, 0))
	feed.tally_kill(ash, ash, Rules.HALCYON)
	_check("tally: a kill of the killer's own team counts nothing", int(feed._run.get(ash, 0)) == 0 and before >= 1)
	feed.tally_kill(null, null, -1)
	_check("tally: no victim and no killer is fine", true)
	feed.free()


## Part (d): a feed line holds the icon between the names and the frames where they belong.
func _feed_line() -> void:
	var feed := HudFeed.new()
	add_child(feed)
	feed.add_parts([0, "Ash", {"icon": KillIcons.TORPEDO, "streak": true}, 1, "Wren (Bomber)"], Palette.AMBER)
	feed.add_parts([0, {"name": "Ash", "ace": true}, {"icon": KillIcons.GUNS, "streak": false}, 1, "Wren (Bomber)"], Palette.AMBER)
	feed.add_parts([{"icon": KillIcons.ROCK}, 1, "Wren (Bomber)"], Palette.DANGER)
	feed.add_parts(["Ash shot down ", 1, "Wren"], Palette.AMBER)
	_check("line: four lines", feed.get_child_count() == 4)
	var row3 := feed.get_child(3) as HFlowContainer
	_check("line 3: a piece that ends in a space gets no second one", row3 != null and String(row3.get_meta("text", "")) == "Ash shot down Wren", str(row3.get_meta("text", "") if row3 != null else "no row"))
	var row0 := feed.get_child(0) as HFlowContainer
	_check("line 0: a flow row", row0 != null)
	if row0 != null:
		_check("line 0: mark, name, icon, mark, words (5 or more children)", row0.get_child_count() >= 5 and row0.get_child(0) is TeamMarks.View and row0.get_child(1) is Label and row0.get_child(2) is KillIcons.View and row0.get_child(3) is TeamMarks.View)
		var icon := row0.get_child(2) as KillIcons.View
		_check("line 0: the icon is the torpedo with the streak frame", icon != null and icon.glyph == KillIcons.TORPEDO and icon.streak)
		_check("line 0: the icon slot is the icon and a 4 px gap each side", icon != null and icon.custom_minimum_size.x == 24.0)
		_check("line 0: the icon has the line's colour", icon != null and icon.col == Palette.AMBER)
		_check("line 0: the text is the words, a space between the names", String(row0.get_meta("text", "")) == "Ash Wren (Bomber)", String(row0.get_meta("text", "")))
	var row1 := feed.get_child(1) as HFlowContainer
	if row1 != null:
		_check("line 1: an ace's name piece and the words after it have a space between", String(row1.get_meta("text", "")) == "Ash Wren (Bomber)", String(row1.get_meta("text", "")))
		_check("line 1: the ace's name is in a frame (NameTag), the icon has none", row1.get_child(1) is KillIcons.NameTag and not (row1.get_child(2) as KillIcons.View).streak)
	var danger := feed.get_child(2)
	_check("line 2: a danger line holds the flow row and the triangle layer", danger.get_child_count() == 2 and danger.get_child(0) is HFlowContainer and danger.get_child(1).get_child(0) is DangerMark)
	if danger.get_child_count() == 2:
		_check("line 2: a Scum or rock kill starts with its icon, no mark before it", danger.get_child(0).get_child(0) is KillIcons.View)
	_check("lines: the column stays 330 px wide", feed.get_combined_minimum_size().x <= 330.5, str(feed.get_combined_minimum_size().x))
	feed.queue_free()


## A Ship of the first hull in the table, of `team`, flown by `profile` (null: nobody). The caller frees it.
func _ship(team: int, profile: PilotProfile) -> Ship:
	var s := Ship.new()
	s.hull_id = String(Ships.HULLS.keys()[0])
	s.team = team
	s.profile = profile
	return s


## The words of the first hull in the table, as the feed line names a victim's ship.
func _hull_label() -> String:
	return String(Ships.HULLS[String(Ships.HULLS.keys()[0])]["label"])


## Check that the piece list `got` is exactly `want` (ints are marks, a String is words, a Dictionary is an icon or a name).
func _same(what: String, got: Array, want: Array) -> void:
	_check(what, got == want, "got %s, want %s" % [str(got), str(want)])


## Part (f): HudFeed._ship_line() builds the line's pieces, in order, for each kind of killer.
func _ship_lines() -> void:
	var feed := HudFeed.new()
	var hull := _hull_label()
	var aur := Rules.HALCYON
	var vho := Rules.CINDER
	var vho_word := String(Rules.TEAM_DISPLAY[vho])
	var aur_word := String(Rules.TEAM_DISPLAY[aur])
	var ash := PilotProfile.new("Ash", aur, 90, false)
	var wren := PilotProfile.new("Wren", vho, 91, false)
	var crew := PilotProfile.new("Crew", aur, 92, false)
	crew.is_crew = true
	var wren_ship := _ship(vho, wren)
	var ash_ship := _ship(aur, ash)
	var pilot := _unit(Unit.K_SHIP, aur)
	var turret := _unit(Unit.K_TURRET, vho)
	var scum_ship := _unit(Unit.K_SHIP, Rules.NEUTRAL)
	var scum_den := _unit(Unit.K_MONSTER, Rules.NEUTRAL)
	var minion := _unit(Unit.K_MINION, vho)
	var wren_name := "Wren (%s)" % hull
	var ash_name := "Ash (%s)" % hull
	# A pilot killer: the pilot's mark and name, the weapon's icon, the victim's mark and "name (hull)".
	var torp := _blow(Rules.W_TORP, pilot)
	_same("line: a pilot's kill", feed._ship_line(wren_ship, torp, ash, false, false), [aur, "Ash", {"icon": KillIcons.TORPEDO, "streak": false}, vho, wren_name])
	_same("line: a pilot who made an ace has the name frame", feed._ship_line(wren_ship, torp, ash, false, true), [aur, {"name": "Ash", "ace": true}, {"icon": KillIcons.TORPEDO, "streak": false}, vho, wren_name])
	_same("line: a kill that ended a streak has the icon frame", feed._ship_line(wren_ship, torp, ash, true, false), [aur, "Ash", {"icon": KillIcons.TORPEDO, "streak": true}, vho, wren_name])
	# A live turret: its team word and the turret's icon.
	_same("line: a live turret is named by its team", feed._ship_line(ash_ship, _blow(Rules.W_BOLT, turret), null, false, false), [vho, vho_word, {"icon": KillIcons.TURRET, "streak": false}, aur, ash_name])
	# The Scum and an asteroid have no mark and no team word before the icon.
	_same("line: a Scum ship's kill has no mark", feed._ship_line(ash_ship, _blow(Rules.W_BOLT, scum_ship), null, false, false), [{"icon": KillIcons.SCUM, "streak": false}, aur, ash_name])
	_same("line: a Scum den's kill has no mark", feed._ship_line(ash_ship, _blow(Rules.W_TORP, scum_den), null, false, false), [{"icon": KillIcons.SCUM, "streak": false}, aur, ash_name])
	_same("line: an asteroid crash has no mark", feed._ship_line(ash_ship, _blow(Rules.W_COLLISION, null), null, false, false), [{"icon": KillIcons.ROCK, "streak": false}, aur, ash_name])
	# A bought ship's crew shows its team word, not a name; a victim with no profile is "A pilot" with no mark.
	var crew_ship := _ship(aur, crew)
	_same("line: a crew victim is the team word", feed._ship_line(crew_ship, _blow(Rules.W_BOLT, null), null, false, false), [{"icon": KillIcons.GUNS, "streak": false}, aur, "%s (%s)" % [aur_word, hull]])
	var nobody := _ship(aur, null)
	_same("line: a victim with no profile has no mark", feed._ship_line(nobody, _blow(Rules.W_BOLT, null), null, false, false), [{"icon": KillIcons.GUNS, "streak": false}, "A pilot (%s)" % hull])
	# A unit that fired and is gone before its round lands: the note kept its team and kind. A minion keeps its team word and its
	# icon; a Scum source stays without a mark (a freed turret's icon is the weapon's today, so it is not pinned here).
	var lost_minion := _blow(Rules.W_BOLT, minion)
	lost_minion.source = null
	_same("line: a freed minion keeps its team", feed._ship_line(ash_ship, lost_minion, null, false, false), [vho, vho_word, {"icon": KillIcons.MINION, "streak": false}, aur, ash_name])
	var lost_scum := _blow(Rules.W_BOLT, scum_ship)
	lost_scum.source = null
	_same("line: a freed Scum ship has no mark", feed._ship_line(ash_ship, lost_scum, null, false, false), [{"icon": KillIcons.SCUM, "streak": false}, aur, ash_name])
	for u: Node in [wren_ship, ash_ship, crew_ship, nobody, pilot, turret, scum_ship, scum_den, minion]:
		u.free()
	feed.free()


## True when no point of `pts` has a NaN or infinite part.
func _finite(pts: PackedVector2Array) -> bool:
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y)):
			return false
	return true


## Part (g): the pure helpers of the shot shapes (ProjectilesDraw): the head floor, the tail base, the head and tail sizes, the
## barb's half-width and the corner lists. Nothing is drawn here; the drawing itself is read in the pictures.
func _shot_helpers() -> void:
	_check("shot: the head floor is 1.3 for a bolt and for point defense", is_equal_approx(ProjectilesDraw.head_floor(Rules.W_BOLT), 1.3) and is_equal_approx(ProjectilesDraw.head_floor(Rules.W_PD), 1.3))
	_check("shot: the head floor is 1.5 for flak and 1.8 for a shell", is_equal_approx(ProjectilesDraw.head_floor(Rules.W_FLAK), 1.5) and is_equal_approx(ProjectilesDraw.head_floor(Rules.W_SHELL), 1.8))
	_check("shot: the tail base is 9 x 1.6, 6 x 2 and 16 x 3", ProjectilesDraw.tail_base(Rules.W_BOLT).is_equal_approx(Vector2(9.0, 1.6)) and ProjectilesDraw.tail_base(Rules.W_FLAK).is_equal_approx(Vector2(6.0, 2.0)) and ProjectilesDraw.tail_base(Rules.W_SHELL).is_equal_approx(Vector2(16.0, 3.0)))
	_check("shot: a minion's round is 0.85, any other 1", is_equal_approx(ProjectilesDraw.minion_size(1), 0.85) and is_equal_approx(ProjectilesDraw.minion_size(0), 1.0))
	_check("shot: a small hit circle gives the floor x the minion size", is_equal_approx(ProjectilesDraw.head_radius(Rules.W_BOLT, 0.1, 1.0, 0.85), 1.3 * 0.85), str(ProjectilesDraw.head_radius(Rules.W_BOLT, 0.1, 1.0, 0.85)))
	_check("shot: a hit circle bigger than the floor wins", is_equal_approx(ProjectilesDraw.head_radius(Rules.W_SHELL, 5.0, 1.0), 5.0))
	_check("shot: the shell's tail is its base, 16 x 3", ProjectilesDraw.tail(Rules.W_SHELL, 1.8).is_equal_approx(Vector2(16.0, 3.0)), str(ProjectilesDraw.tail(Rules.W_SHELL, 1.8)))
	_check("shot: a long head grows the tail to 3 R long and R wide", ProjectilesDraw.tail(Rules.W_BOLT, 4.0).is_equal_approx(Vector2(12.0, 4.0)), str(ProjectilesDraw.tail(Rules.W_BOLT, 4.0)))
	_check("shot: the barb is half its tail width plus 0.9 when that is wider than the head", is_equal_approx(ProjectilesDraw.barb_half(1.3, 1.6), 1.7), str(ProjectilesDraw.barb_half(1.3, 1.6)))
	var barb := ProjectilesDraw.barb_polygon(Vector2.ZERO, Vector2.RIGHT, 2.0, 9.0, 1.6)
	_check("shot: the barbed head has seven points, none NaN", barb.size() == 7 and _finite(barb), str(barb))
	var dart := ProjectilesDraw.dart(Vector2.ZERO, Vector2.RIGHT, 1.0)
	_check("shot: the dart has five points, none NaN", dart.size() == 5 and _finite(dart), str(dart))


## Part (e): the legend.
func _legend() -> void:
	var legend := KillIcons.legend(600.0)
	add_child(legend)
	var icons := 0
	var framed := 0
	var tags := 0
	var stack: Array[Node] = [legend]
	var seen := {}
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is KillIcons.View:
			icons += 1
			seen[(n as KillIcons.View).glyph] = true
			if (n as KillIcons.View).streak:
				framed += 1
		if n is KillIcons.NameTag:
			tags += 1
		stack.append_array(n.get_children())
	_check("legend: 18 icons (the 17 and one framed example)", icons == 18, str(icons))
	_check("legend: every glyph is in it", seen.size() == 17, str(seen.size()))
	_check("legend: one streak frame and one name frame", framed == 1 and tags == 1)
	legend.queue_free()
