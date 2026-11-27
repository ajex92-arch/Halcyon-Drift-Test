extends Node
## WHAT THIS IS: the check of the kill feed's lines about you (T-125, round 2): a line where the human pilot killed or died sits
## on a dark plate and lives 14 seconds instead of 9; every other line is as it was.
##
## HOW IT WORKS: setup() runs the cases on feeds of its own (a HudFeed with the real World) and prints "feed_own_check: N
## failures" (a FAIL line for each). It needs a human pilot (--role=pilot, or --role=admiral). (a) A ship kill by the human, one
## of the human, and a cleared Scum den by the human each get the plate (a PanelContainer whose background is the void colour at
## alpha 0.6, with a 1 px edge) and the "life" metadata 14.0; so does a plain sentence given the own flag. (b) The same kill
## between two other pilots gets neither. (c) A bay line, a turret line and a plain feed message get neither. (d) With no human
## pilot no line gets a plate. (e) The fade: a line about the human is still solid at 10 s, fading at 13 s, gone at 15 s; a
## plain line at 10 s is gone (its life is 9 s). (f) The column is at most 330.5 px wide with a plate line and a danger plate
## line in it. (g) The sentence kept for the respawn banner (last_cause) and the line's "text" metadata are the same as without a
## plate. (h) The human, the viewer's team and the human's streak are unchanged after all of it.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=feed_own_check
##
## WHO USES IT: main.gd loads it for --test=feed_own_check (it calls setup()); it is a row of the check list.

## How many checks failed.
var _fails := 0
## The running match (set by setup()).
var world: World


## main.gd calls this once, right after the World is built. It waits a few frames for the fade cases, then prints the result.
func setup(w: World) -> void:
	world = w
	if world.human == null:
		_fails += 1
		print("FAIL feed_own_check: the match has no human pilot (run it with --role=pilot or --role=admiral)")
		_finish()
		return
	var keep_human := world.human
	var keep_team := world.viewer_team
	var keep_streak := world.human.streak
	_plates()
	_other_lines()
	_no_human()
	_width()
	_same_words()
	await _fades()
	_check("human: world.human is unchanged", world.human == keep_human)
	_check("human: the viewer's team is unchanged", world.viewer_team == keep_team)
	_check("human: the human's streak is unchanged", world.human.streak == keep_streak)
	_finish()


## Print the result and end the run.
func _finish() -> void:
	print("feed_own_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## A feed of its own, with the real World, in the tree.
func _fresh() -> HudFeed:
	var f := HudFeed.new()
	f.world = world
	add_child(f)
	return f


## A pilot of `team` named `callsign`, not in the match.
func _pilot(callsign: String, team: int) -> PilotProfile:
	return PilotProfile.new(callsign, team, 90 + callsign.length(), false)


## The ship of `victim` (team `team`) is shot down by `killer`'s bolt: the feed hears it. Returns the ship (the caller frees it).
func _kill(f: HudFeed, killer: PilotProfile, victim: PilotProfile, team: int) -> Ship:
	var s := Ship.new()
	s.hull_id = String(Ships.HULLS.keys()[0])
	s.team = team
	s.profile = victim
	var info := DamageInfo.from_unit(null, 10.0, Rules.W_BOLT, Vector2.ZERO)
	info.source_profile = killer
	f.on_unit_killed(s, info)
	return s


## The newest line of `f`.
func _last(f: HudFeed) -> Node:
	return f.get_child(f.get_child_count() - 1)


## True when `n` is a plate: a PanelContainer whose background is the void colour at alpha 0.6, with a 1 px edge in mist.
func _is_plate(n: Node) -> bool:
	if not (n is PanelContainer):
		return false
	var sb := (n as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	return sb != null and sb.bg_color.is_equal_approx(Color(Palette.VOID, 0.6)) and sb.border_width_left == 1 and sb.border_color.is_equal_approx(Palette.MIST)


## True when `n` carries the long life.
func _has_long_life(n: Node) -> bool:
	return n.has_meta("life") and is_equal_approx(float(n.get_meta("life")), 14.0)


## Part (a): the lines about the human have the plate and the long life.
func _plates() -> void:
	var me := world.human
	var foe := _pilot("Wren", 1 - me.team)
	var f := _fresh()
	var s1 := _kill(f, me, foe, foe.team)
	var l1 := _last(f)
	_check("own: the human's kill has the plate", _is_plate(l1))
	_check("own: the human's kill has the life 14", _has_long_life(l1))
	_check("own: the plate holds the flow row", l1.get_child_count() == 1 and l1.get_child(0) is HFlowContainer)
	_check("own: the plate carries the born and text metadata", l1.has_meta("born") and String(l1.get_meta("text", "")) != "")
	var s2 := _kill(f, foe, me, me.team)
	var l2 := _last(f)
	_check("own: the human's death has the plate", _is_plate(l2))
	_check("own: the human's death has the life 14", _has_long_life(l2))
	_check("own: the death line (danger) holds the row and the triangle layer", l2.get_child_count() == 1 and l2.get_child(0) is MarginContainer and l2.get_child(0).get_child_count() == 2 and l2.get_child(0).get_child(1).get_child(0) is DangerMark)
	var den := Unit.new()
	den.kind = Unit.K_MONSTER
	den.team = Rules.NEUTRAL
	den.display_name = "Scum den"
	var info := DamageInfo.from_unit(null, 10.0, Rules.W_BOLT, Vector2.ZERO)
	info.source_profile = me
	var before := f.get_child_count()
	f.on_unit_killed(den, info)
	_check("own: a cleared den by the human is a line", f.get_child_count() == before + 1)
	if f.get_child_count() == before + 1:
		var l3 := _last(f)
		_check("own: the den line has the plate", _is_plate(l3))
		_check("own: the den line has the life 14", _has_long_life(l3))
	f.add_parts(["Plain words"], Palette.MIST, true)
	var l4 := _last(f)
	_check("own: a plain sentence given the flag is a plate round a row", _is_plate(l4) and l4.get_child(0) is HFlowContainer)
	# (b) The same kill between two other pilots: no plate, no life.
	var g := _fresh()
	var ash := _pilot("Ash", me.team)
	var s3 := _kill(g, ash, foe, foe.team)
	var l5 := _last(g)
	_check("other: two other pilots' kill has no plate", not _is_plate(l5) and not (l5 is PanelContainer))
	_check("other: two other pilots' kill has no life", not l5.has_meta("life"))
	var s4 := _kill(g, foe, ash, ash.team)
	_check("other: a kill of another pilot by the foe has no plate or life", not (_last(g) is PanelContainer) and not _last(g).has_meta("life"))
	for n: Node in [s1, s2, s3, s4, den]:
		n.free()
	f.queue_free()
	g.queue_free()


## Part (c): a bay line, a turret line and a plain feed message have no plate and no life.
func _other_lines() -> void:
	var me := world.human
	var f := _fresh()
	var bay := Unit.new()
	bay.kind = Unit.K_BAY
	bay.team = 1 - me.team
	f.on_unit_killed(bay, DamageInfo.from_unit(null, 10.0, Rules.W_BOLT, Vector2.ZERO))
	var turret := Turret.new()
	turret.tdef = TurretData.TURRETS["pd"]
	turret.team = 1 - me.team
	f.on_turret_destroyed(turret, me.team)
	f.on_feed("Something happened", "info", -1)
	_check("lines: a bay, a turret and a feed message are three lines", f.get_child_count() == 3, str(f.get_child_count()))
	for c in f.get_children():
		_check("lines: %s has no plate and no life" % c.name, not (c is PanelContainer) and not c.has_meta("life"))
	bay.free()
	turret.free()
	f.queue_free()


## Part (d): with no human pilot no line gets a plate (a spectator's feed). The human is put back.
func _no_human() -> void:
	var me := world.human
	var foe := _pilot("Wren", 1 - me.team)
	var f := _fresh()
	world.human = null
	var s1 := _kill(f, me, foe, foe.team)
	var s2 := _kill(f, foe, me, me.team)
	var den := Unit.new()
	den.kind = Unit.K_MONSTER
	den.team = Rules.NEUTRAL
	den.display_name = "Scum den"
	var info := DamageInfo.from_unit(null, 10.0, Rules.W_BOLT, Vector2.ZERO)
	info.source_profile = me
	f.on_unit_killed(den, info)
	world.human = me
	_check("spectator: the three lines were made", f.get_child_count() == 3, str(f.get_child_count()))
	for c in f.get_children():
		_check("spectator: no plate and no life", not (c is PanelContainer) and not c.has_meta("life"))
	for n: Node in [s1, s2, den]:
		n.free()
	f.queue_free()


## Part (f): the column's smallest width with a plate line and a danger plate line in it.
func _width() -> void:
	var me := world.human
	var foe := _pilot("Wren", 1 - me.team)
	var f := _fresh()
	var s1 := _kill(f, me, foe, foe.team)
	_check("width: the column with one plate line", f.get_combined_minimum_size().x <= 330.5, str(f.get_combined_minimum_size().x))
	var s2 := _kill(f, foe, me, me.team)
	f.add_parts(["A long line of words about you that runs well past the width of the column so it has to wrap onto a second row"], Palette.MIST, true)
	_check("width: the column with a plate line and a danger plate line stays 330 px wide", f.get_combined_minimum_size().x <= 330.5, str(f.get_combined_minimum_size().x))
	s1.free()
	s2.free()
	f.queue_free()


## Part (g): the plate changes no text: last_cause and the line's text are those of the same kill without a plate.
func _same_words() -> void:
	var me := world.human
	var foe := _pilot("Wren", 1 - me.team)
	var f := _fresh()
	var s := _kill(f, foe, me, me.team)
	var plate := _last(f)
	var d := DamageInfo.from_unit(null, 10.0, Rules.W_BOLT, Vector2.ZERO)
	d.source_profile = foe
	var want := f._ship_cause(s, d, foe)
	_check("words: last_cause is the kill's sentence", f.last_cause == want and want != "", f.last_cause + " / " + want)
	f.add_parts(f._ship_line(s, d, foe, false, false), Palette.DANGER)
	var plain := _last(f)
	_check("words: the line's text is the same with and without the plate", String(plate.get_meta("text", "x")) == String(plain.get_meta("text", "y")), String(plate.get_meta("text", "")) + " / " + String(plain.get_meta("text", "")))
	s.free()
	f.queue_free()


## Part (e)'s step: `age_s` seconds are taken off `line`'s birth, fade_lines() runs once on `f`, and a frame passes.
func _aged(f: HudFeed, line: Node, age_s: float) -> void:
	line.set_meta("born", Time.get_ticks_msec() - int(age_s * 1000.0))
	HudFeed.fade_lines(f, HudFeed.LIFE)
	await get_tree().process_frame


## Part (e): a line about the human is solid at 10 s, fading at 13 s, gone at 15 s; a plain line is gone at 10 s.
func _fades() -> void:
	var me := world.human
	var foe := _pilot("Wren", 1 - me.team)
	var ash := _pilot("Ash", me.team)
	var f := _fresh()
	var s1 := _kill(f, me, foe, foe.team)
	var l1 := _last(f)
	await _aged(f, l1, 10.0)
	_check("fade: a line about the human is still there at 10 s", is_instance_valid(l1) and not l1.is_queued_for_deletion())
	if is_instance_valid(l1):
		_check("fade: and still solid", is_equal_approx((l1 as CanvasItem).modulate.a, 1.0), str((l1 as CanvasItem).modulate.a))
	if is_instance_valid(l1):
		await _aged(f, l1, 13.0)
	_check("fade: still there at 13 s", is_instance_valid(l1) and not l1.is_queued_for_deletion())
	if is_instance_valid(l1):
		_check("fade: fading at 13 s", (l1 as CanvasItem).modulate.a < 1.0 and (l1 as CanvasItem).modulate.a > 0.0, str((l1 as CanvasItem).modulate.a))
	if is_instance_valid(l1):
		await _aged(f, l1, 15.0)
	_check("fade: gone at 15 s", not is_instance_valid(l1))
	# The control: a plain line (two other pilots) at 10 s is gone, its life is 9 s.
	var s2 := _kill(f, ash, foe, foe.team)
	var l2 := _last(f)
	await _aged(f, l2, 10.0)
	_check("fade: a plain line is gone at 10 s", not is_instance_valid(l2))
	s1.free()
	s2.free()
	f.queue_free()
