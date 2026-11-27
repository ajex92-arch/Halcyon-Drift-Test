extends Node
## WHAT THIS IS: the check of the team marks (TeamMarks, T-126 Set 1): the shapes come out of their corners at the
## sizes the design names, the Vhorr wedge points down and never up, the dark shape under a mark is 2.2 px larger across
## (a rim of 1.1 px a side), the hollow icon keeps a 1.4 px line, and a tooth is an isosceles triangle standing on the
## ring's outer edge; a mark's row View is sized to its own width; the feed's lines carry their marks and wrap by word.
##
## HOW IT WORKS: setup() runs the parts and prints "team_marks_check: N failures" (a FAIL line for each). The shapes
## are measured from the corner functions (no drawing is needed for that); a last part draws every entry once on a
## real canvas item to prove none of them errors.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=team_marks_check
##
## WHO USES IT: main.gd loads it for --test=team_marks_check (it calls setup()).

## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built (the World is not needed).
func setup(_w: World) -> void:
	_wedge()
	_disc_and_rim()
	_views()
	_shapes()
	_teeth()
	await _feed()
	await _draws()
	print("team_marks_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## The Vhorr wedge: the corners the design gives, a point at the bottom, never upright.
func _wedge() -> void:
	var d := 10.0
	var c := Vector2(100, 50)
	var p := TeamMarks.wedge(c, d)
	_check("wedge: three corners", p.size() == 3)
	_check("wedge: top left corner (-0.6d, -0.52d)", p[0].distance_to(c + Vector2(-6.0, -5.2)) < 0.001, str(p[0]))
	_check("wedge: top right corner (0.6d, -0.52d)", p[1].distance_to(c + Vector2(6.0, -5.2)) < 0.001, str(p[1]))
	_check("wedge: the point (0, 0.52d)", p[2].distance_to(c + Vector2(0.0, 5.2)) < 0.001, str(p[2]))
	_check("wedge: 1.2d wide, 1.04d tall", is_equal_approx(p[1].x - p[0].x, 12.0) and is_equal_approx(p[2].y - p[0].y, 10.4))
	_check("wedge: the point is below the flat top (it points down)", p[2].y > p[0].y and p[2].y > p[1].y and is_equal_approx(p[0].y, p[1].y))
	_check("wedge: the point is on the middle line", is_equal_approx(p[2].x, c.x))
	# Never upright, at any size: the point stays below the top corners, and the top corners stay level.
	for size in [4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 20.0]:
		var q := TeamMarks.wedge(Vector2.ZERO, size)
		_check("wedge: never upright at size %.0f" % size, q[2].y > q[0].y and q[2].y > q[1].y and is_equal_approx(q[0].y, q[1].y))
	_check("wedge: only Vhorr gets it", TeamMarks.is_wedge(Rules.CINDER) and not TeamMarks.is_wedge(Rules.HALCYON))
	# It is not the danger sign: the danger triangle is upright, its point above its base.
	var danger := Glyphs.triangle(c, 14.0)
	_check("wedge: the opposite of the danger sign", danger[0].y < danger[1].y and p[2].y > p[0].y)


## The disc and the dark shape under a mark: 2.2 px larger across, a rim of half of it.
func _disc_and_rim() -> void:
	_check("the rim grows the shape 2.2 px across", is_equal_approx(TeamMarks.GROW, 2.2))
	for size: float in [4.0, 5.0, 8.0, 10.0, 12.0]:
		var small := TeamMarks.wedge(Vector2.ZERO, size)
		var rim := TeamMarks.wedge_rim(Vector2.ZERO, size, TeamMarks.GROW * 0.5)
		# The dark wedge fully holds the coloured one (every corner of the small one is inside the rim shape).
		var holds := rim.size() >= 3
		for p: Vector2 in small:
			holds = holds and Geometry2D.is_point_in_polygon(p, rim)
		_check("wedge rim at %.0f: the dark wedge holds the coloured one" % size, holds)
		# The rim is at least 1 px wide on every side, the slanted ones included: the least distance between the two
		# outlines (both are convex and nested, so it is reached at a corner of one on a side of the other).
		var least := INF
		for i in rim.size():
			for j in small.size():
				least = minf(least, (Geometry2D.get_closest_point_to_segment(rim[i], small[j], small[(j + 1) % small.size()])).distance_to(rim[i]))
		for i in small.size():
			for j in rim.size():
				least = minf(least, (Geometry2D.get_closest_point_to_segment(small[i], rim[j], rim[(j + 1) % rim.size()])).distance_to(small[i]))
		_check("wedge rim at %.0f: at least 1 px on every side, slanted sides too" % size, least >= 1.0 - 0.001, "%.3f" % least)
		# The same at the world's scale (`unit` 3): the rim grows with it.
		var rim3 := TeamMarks.wedge_rim(Vector2.ZERO, size * 3.0, TeamMarks.GROW * 0.5 * 3.0)
		var small3 := TeamMarks.wedge(Vector2.ZERO, size * 3.0)
		var least3 := INF
		for i in rim3.size():
			for j in small3.size():
				least3 = minf(least3, (Geometry2D.get_closest_point_to_segment(rim3[i], small3[j], small3[(j + 1) % small3.size()])).distance_to(rim3[i]))
		_check("wedge rim at %.0f x3: at least 3 px on every side" % size, least3 >= 3.0 - 0.003, "%.3f" % least3)


## The View a row holds (the feed's and the scoreboard's name marks): sized to the mark's own width, nothing drawn left of
## its edge, and a 4 px gap between the coloured mark and what follows.
func _views() -> void:
	for team in 2:
		for size: float in [10.0, 12.0]:
			var v := TeamMarks.View.new(team, size, 16.0)
			var own := size * (1.2 if TeamMarks.is_wedge(team) else 1.0)
			_check("view team %d size %.0f: the mark's own width is %.1f" % [team, size, own], is_equal_approx(TeamMarks.mark_width(team, size), own))
			var pad := TeamMarks.rim_left(team, size)
			_check("view team %d size %.0f: the width is the rim room, the mark and a 4 px gap" % [team, size], is_equal_approx(v.custom_minimum_size.x, pad + own + 4.0), str(v.custom_minimum_size.x))
			# The mark is centred pad + own / 2 from the left; its dark shape's left edge must not be left of 0.
			var cx := pad + own * 0.5
			var left := cx - size * 0.5 - TeamMarks.GROW * 0.5
			if TeamMarks.is_wedge(team):
				left = INF
				for p: Vector2 in TeamMarks.wedge_rim(Vector2(cx, 0.0), size, TeamMarks.GROW * 0.5):
					left = minf(left, p.x)
			_check("view team %d size %.0f: nothing is drawn left of the control" % [team, size], left >= -0.001, "%.3f" % left)
			_check("view team %d size %.0f: the gap right of the coloured mark is 4 px" % [team, size], is_equal_approx(v.custom_minimum_size.x - (cx + own * 0.5), 4.0))
			v.free()


## The marks are on the screen's lines (a test that fails if they are dropped): a feed line naming a team has a mark as its
## first piece, the danger triangle of bad news stands outside the flow, and a long site line (one piece of 55 characters)
## wraps by word into the 330 px column.
func _feed() -> void:
	var feed := HudFeed.new()
	add_child(feed)
	feed.add_parts([0, "Aurelian can build at Top Jungle North: no enemy inside"], Palette.MIST)
	feed.add_parts([1, "Vhorr starts a turret at Bottom Jungle South (18 s)"], Palette.MIST)
	feed.add_parts(["Wren shot down ", 0, "Pike's Bomber"], Palette.DANGER)
	feed.add_parts(["plain line"], Palette.MIST)
	_check("feed: four lines", feed.get_child_count() == 4)
	for i in 2:
		var row := feed.get_child(i) as HFlowContainer
		_check("feed line %d: a team line is a flow row" % i, row != null)
		if row != null:
			_check("feed line %d: its first child is the team's mark" % i, row.get_child_count() > 0 and row.get_child(0) is TeamMarks.View and (row.get_child(0) as TeamMarks.View).team == i)
			var words := 0
			for c in row.get_children():
				if c is Label:
					words += 1
					_check("feed line %d: a word label holds one word (%s)" % [i, (c as Label).text], (c as Label).text.strip_edges().count(" ") == 0)
			_check("feed line %d: one label per word (8 or more)" % i, words >= 8, str(words))
	var danger := feed.get_child(2)
	_check("feed: the danger line holds a flow row and a layer with the triangle at the left edge", danger.get_child_count() == 2 and danger.get_child(0) is HFlowContainer and danger.get_child(1).get_child(0) is DangerMark and (danger.get_child(1).get_child(0) as DangerMark).position.x == 0.0)
	_check("feed: the danger line's row starts with words", danger.get_child(0).get_child(0) is Label)
	var has_mark := false
	for c in danger.get_child(0).get_children():
		has_mark = has_mark or c is TeamMarks.View
	_check("feed: the danger line carries the team mark", has_mark)
	_check("feed: a line with no team is a plain label", feed.get_child(3) is Label)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("feed: the column stays 330 px wide with the long site lines", feed.get_combined_minimum_size().x <= 330.5, str(feed.get_combined_minimum_size().x))
	for i in 3:
		var line := feed.get_child(i) as Control
		_check("feed line %d: no wider than the column" % i, line.get_combined_minimum_size().x <= 330.5, str(line.get_combined_minimum_size().x))
	feed.queue_free()


## The base shapes and the hollow icon.
func _shapes() -> void:
	var c := Vector2(40, 40)
	var sq := TeamMarks.shape_points(TeamMarks.SQUARE, c, 6.0)
	_check("square: side 6, centred", sq.size() == 4 and is_equal_approx(sq[1].x - sq[0].x, 6.0) and is_equal_approx(sq[2].y - sq[1].y, 6.0) and ((sq[0] + sq[2]) * 0.5).distance_to(c) < 0.001)
	var dm := TeamMarks.shape_points(TeamMarks.DIAMOND, c, 8.4)
	_check("diamond: radius 4.2, corners on the axes", dm.size() == 4 and dm[0].distance_to(c + Vector2(0, -4.2)) < 0.001 and dm[1].distance_to(c + Vector2(4.2, 0)) < 0.001 and dm[2].distance_to(c + Vector2(0, 4.2)) < 0.001 and dm[3].distance_to(c + Vector2(-4.2, 0)) < 0.001)
	_check("hollow: the line is 1.4 px and the core 0.9 VOID", is_equal_approx(TeamMarks.HOLLOW_LINE, 1.4) and is_equal_approx(TeamMarks.HOLLOW_CORE_ALPHA, 0.9))
	# The team colours stay as they are.
	_check("team colours: Aurelian amber, Vhorr cinder", Palette.team(Rules.HALCYON) == Palette.AMBER and Palette.team(Rules.CINDER) == Palette.CINDER)


## A tooth: an isosceles triangle on the ring's outer edge, pointing out.
func _teeth() -> void:
	var c := Vector2(10, 20)
	var r := 7.0
	for a in [PI / 4.0, 3.0 * PI / 4.0, -PI / 2.0, 0.0]:
		var t := TeamMarks.tooth(c, r, a, 2.4, 2.2)
		var base_mid := (t[0] + t[1]) * 0.5
		_check("tooth at %.2f: the base is 2.4 long" % a, is_equal_approx(t[0].distance_to(t[1]), 2.4))
		_check("tooth at %.2f: the base middle is on the ring's outer edge" % a, is_equal_approx(base_mid.distance_to(c), r))
		_check("tooth at %.2f: isosceles (two equal sides)" % a, is_equal_approx(t[2].distance_to(t[0]), t[2].distance_to(t[1])))
		_check("tooth at %.2f: the point is 2.2 outside the base, on the same ray" % a, is_equal_approx(t[2].distance_to(c), r + 2.2) and is_equal_approx(t[2].distance_to(base_mid), 2.2))
	var ang := TeamMarks.ring_angles(8, deg_to_rad(22.5))
	_check("ring angles: 8 teeth, 45 degrees apart, the first at 22.5", ang.size() == 8 and is_equal_approx(ang[0], deg_to_rad(22.5)) and is_equal_approx(ang[1] - ang[0], deg_to_rad(45.0)))
	# None of the 8 world teeth sits under the mark at 12 o'clock (angle -90 degrees).
	var clear := true
	for a: float in ang:
		if absf(wrapf(a - (-PI / 2.0), -PI, PI)) < deg_to_rad(10.0):
			clear = false
	_check("ring angles: no tooth under the 12 o'clock mark", clear)


## Draw every entry once on a real canvas item: none may error.
func _draws() -> void:
	var node := Node2D.new()
	add_child(node)
	node.draw.connect(func() -> void:
		for team in 2:
			TeamMarks.mark(node, Vector2(20, 20), 8.0, team)
			TeamMarks.mark(node, Vector2(40, 20), 8.0, team, 3.0)
			TeamMarks.fill(node, Vector2(60, 20), 5.0, team)
			for base in [TeamMarks.DISC, TeamMarks.SQUARE, TeamMarks.DIAMOND]:
				TeamMarks.icon(node, base, Vector2(20 + 20.0 * float(base), 50), 6.0, team, 1.0, true)
		TeamMarks.teeth(node, Vector2(60, 60), 7.0, TeamMarks.ring_angles(4, PI / 4.0), 2.4, 2.2, Palette.CINDER)
	)
	node.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("draw: every entry ran", is_instance_valid(node))
	node.queue_free()
