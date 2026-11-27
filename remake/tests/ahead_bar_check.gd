extends Node
## WHAT THIS IS: the check of the who-is-ahead bar in the HUD's top bar (scripts/ui/hud_top_bar.gd,
## scenes/ui/hud_top_bar.tscn) and of the shared team value it reads (MatchSeries.team_value). It
## proves that the marker's share is the weighted sum of the parts that have data, that the words
## under the marker are the right ones for a seat and for a spectator, that a value reads as 850 or
## 14.2k, that the enemy side of the bar follows the fog of war (an enemy mothership never seen reads
## full and says so, one in view reads its hull, one out of view is held with the time since, an
## enemy ship counts only while in view, an enemy turret or post counts only once seen), that No fog
## and the spectator show the truth, that a practice range hides the new widgets, that no word of the
## bar holds a percent sign, "speed", "minion", "Hard" or "enemy earns", that the node order other
## checks read is kept, and that the bar flashes when a turret falls in view (once in a while, with no
## sound, and never for a fall out of view) while the kill feed still hears every fall.
##
## HOW IT WORKS: setup() runs every case at once, in the first moments of the match (no tick runs
## between two steps of a case, so the vision cannot overwrite a mask bit a case wrote). The script of
## the bar and of the series are held untyped and every call is made only after a has_method test, so
## a missing function is a failed check by name and never an engine error. Each case that needs a bar
## makes its own, refreshes it and frees it; whatever a case writes (a mask bit, a hull, the match
## time, the fog option, the viewer, the practice flag) it puts back. A seat with a viewer (pilot,
## Admiral) runs every case; the all-computer spectator row (viewer_team below 0) cannot ask what an
## enemy hides, so the nine fog cases are counted as not applicable there. With the option
## --ahead-watch=<seconds> no case runs: the node only prints one AHEAD_SAMPLE line every 30 match
## seconds, read from the real HUD's bar, and quits at <seconds> (a measurement of the marker). The
## last line is "ahead_bar_check: N failures (M checks, K N/A)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/;
## all three forms need the HUD, so --force-hud):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=ahead_bar_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --seed=7 --test=ahead_bar_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --force-hud --seed=7 --test=ahead_bar_check
## and the measurement: the first form with --ahead-watch=600 added.
##
## WHO USES IT: main.gd loads it for --test=ahead_bar_check (it calls setup()); run_checks lists it.

## The script of the match series (held untyped: a missing function must fail by name).
const MS_PATH := "res://scripts/match_series.gd"
## The script of the top bar.
const HB_PATH := "res://scripts/ui/hud_top_bar.gd"
## The top bar's scene.
const BAR_SCENE := "res://scenes/ui/hud_top_bar.tscn"
## Two numbers closer than this count as equal.
const TOL := 1e-6
## The weights the cases use when the bar's script holds none (the case P1 then fails).
const DEFAULT_WEIGHTS := {"ms": 0.40, "turrets": 0.25, "posts": 0.10, "value": 0.25}

## The running match (set by setup()).
var world: World
## The match series main.gd made (set by setup()).
var series: MatchSeries = null
## How many checks failed, how many ran, how many were not applicable.
var _fails := 0
## How many checks ran.
var _checks := 0
## How many cases did not apply to this seat.
var _na := 0
## The scripts under test, held untyped.
var _ms: Variant = null
## The script of the top bar, held untyped.
var _hb: Variant = null
## The constants of the bar's script.
var _consts: Dictionary = {}
## The viewer's team (-1 = a spectator), the enemy of the viewer and the viewer's bit in a mask.
var _vt := 0
## The enemy of the viewer (team 1 when there is no viewer).
var _et := 1
## The viewer's bit in a visible_mask or seen_mask (0 when there is no viewer).
var _bit := 1
## The enemy pilot ship launched by S4 (null until then).
var _fs: Ship = null
## Enemy pilots that were docked with no hull, and the hull they held (the docked-hull fixture).
var _dock_saved: Array = []
## Every label text seen in the states of B1, B2, B3, B7 and one normal state (for B9).
var _words_seen: Array[String] = []
## How many Events.cue were sent while F1 to F3 ran.
var _cues := 0
## The watch run's length in seconds (-1 = no watch run) and the match time of its next sample.
var _watch_s := -1.0
## The match time of the watch run's next sample.
var _watch_next := 0.0
## True once the result line is printed.
var _done := false


## main.gd calls this once, right after the World, the HUD and the match series are made.
func setup(w: World) -> void:
	world = w
	_ms = load(MS_PATH)
	_hb = load(HB_PATH)
	_consts = (_hb as Script).get_script_constant_map()
	_vt = world.viewer_team
	_et = (1 - _vt) if _vt >= 0 else 1
	_bit = (1 << _vt) if _vt >= 0 else 0
	var watch := str(Game.opt("ahead-watch", ""))
	if watch != "":
		_start_watch(float(watch))
		return
	series = get_parent().get("series") as MatchSeries
	_run_cases()
	_finish()


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Count one case that does not apply to this seat.
func _not_applicable(what: String) -> void:
	_na += 1
	print("N/A ", what)


## Print the result line and quit after a moment.
func _finish() -> void:
	if _done:
		return
	_done = true
	print("ahead_bar_check: %d failures (%d checks, %d N/A)" % [_fails, _checks, _na])
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


# --- helpers --------------------------------------------------------------------------------------

## Does `script` hold a function called `fn`?
func _has_fn(script: Variant, fn: String) -> bool:
	return script != null and script.has_method(fn)


## True when `script` holds `fn`; else the case fails by name (one check for the function, one for the case).
func _need(script: Variant, owner_name: String, fn: String, case_name: String) -> bool:
	var has := _has_fn(script, fn)
	_check("%s.%s exists" % [owner_name, fn], has)
	if not has:
		_check(case_name, false, "needs %s.%s" % [owner_name, fn])
	return has


## The number of member `member` of `obj`, or `default_value` when there is none.
func _num(obj: Variant, member: String, default_value: float) -> float:
	if obj == null:
		return default_value
	var v: Variant = obj.get(member)
	if v == null:
		return default_value
	return float(v)


## Entry `key` of the dictionary member `member` of `obj`, or `default_value`.
func _dict_entry(obj: Variant, member: String, key: String, default_value: Variant) -> Variant:
	var d: Variant = obj.get(member)
	if d is Dictionary:
		return (d as Dictionary).get(key, default_value)
	return default_value


## The bar's weights (the defaults when the script has none).
func _weights() -> Dictionary:
	var w: Variant = _consts.get("WEIGHTS", null)
	if w is Dictionary:
		return w as Dictionary
	return DEFAULT_WEIGHTS


## The bar's level band (0.05 when the script has none).
func _band() -> float:
	return float(_consts.get("LEVEL_BAND", 0.05))


## A parts dictionary for lead_share: each part is [team 0's number, team 1's number, has data].
func _parts(ms: Array, turrets: Array, posts: Array, value: Array) -> Dictionary:
	return {"ms": ms, "turrets": turrets, "posts": posts, "value": value}


## lead_share of `parts` (call only after the has_method test).
func _share(parts: Dictionary) -> float:
	return float(_hb.call("lead_share", parts))


## lead_words of `share` for viewer `vt` (call only after the has_method test).
func _words(share: float, vt: int) -> String:
	return str(_hb.call("lead_words", share, vt))


## A fresh bar (held untyped), added under this node, refreshed once unless `refresh` is false.
func _new_bar(refresh: bool = true) -> Variant:
	var bar: Variant = (load(BAR_SCENE) as PackedScene).instantiate()
	add_child(bar as Node)
	if refresh:
		bar.call("refresh", world)
	return bar


## Free a bar made by _new_bar (its _exit_tree runs).
func _free_bar(bar: Variant) -> void:
	if bar != null and is_instance_valid(bar):
		(bar as Node).free()


## The node at `path` under the bar, or null.
func _node(bar: Variant, path: String) -> Node:
	return (bar as Node).get_node_or_null(path)


## The text of the Label at `path`, or a marker when it is missing.
func _text_at(bar: Variant, path: String) -> String:
	var n := _node(bar, path)
	return (n as Label).text if n is Label else "<missing %s>" % path


## Is the Control at `path` visible (false when missing)?
func _shown(bar: Variant, path: String) -> bool:
	var n := _node(bar, path)
	return n is Control and (n as Control).visible


## The column name of team `t` in the bar's scene.
func _col(t: int) -> String:
	return "Row/Halcyon" if t == 0 else "Row/Cinder"


## The path of team `t`'s value label under the bar.
func _value_path(t: int) -> String:
	return _col(t) + "/HullRow/Value"


## The path of team `t`'s note label under the bar.
func _note_path(t: int) -> String:
	return _col(t) + "/Note"


## The value of team `t`'s hull bar of `bar` (-1 when the bar has none).
func _hull_of(bar: Variant, t: int) -> float:
	var bars: Variant = bar.get("_ms_bars")
	if bars is Array and (bars as Array).size() > t:
		return (((bars as Array)[t]) as ProgressBar).value
	return -1.0


## Every visible Label and Button text under `node` (a copy of admiral_ui_check's _texts).
func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for c in node.get_children():
		if c is Control and not (c as Control).visible:
			continue
		if c is Label and (c as Label).text != "":
			out.append((c as Label).text.replace("\n", " / "))
		elif c is Button and (c as Button).text != "":
			out.append((c as Button).text)
		out.append_array(_texts(c))
	return out


## Keep the bar's visible texts for B9.
func _keep_words(bar: Variant) -> void:
	_words_seen.append_array(_texts(bar as Node))


## The pilots of the enemy team that are not the human and not a bought crew.
func _enemy_pilots() -> Array[PilotProfile]:
	var out: Array[PilotProfile] = []
	for p: PilotProfile in world.profiles:
		if p.team == _et and not p.is_human and not Squads.is_crew(p):
			out.append(p)
	return out


## The docked-hull fixture on: every docked enemy pilot with no hull gets a Fighter hull (its state
## stays "docked" and it flies nothing), so a rule that counts a docked pilot reads a price.
func _dock_on() -> void:
	_dock_saved.clear()
	for p in _enemy_pilots():
		if p.state == "docked":
			_dock_saved.append([p, p.hull_id])
			p.hull_id = "fighter"


## The docked-hull fixture off: the old hulls come back.
func _dock_off() -> void:
	for e: Array in _dock_saved:
		(e[0] as PilotProfile).hull_id = String(e[1])
	_dock_saved.clear()


## The first live enemy turret that has a node (the bar skips one with none).
func _enemy_turret() -> Turret:
	for t: Turret in world.turrets:
		if t.team == _et and t.alive and not t.tdef.is_empty() and t.node != null:
			return t
	return null


## Set or clear the viewer's bit in a unit's visible_mask.
func _see(u: Unit, on: bool) -> void:
	if _bit == 0:
		return
	if on:
		u.visible_mask |= _bit
	else:
		u.visible_mask &= ~_bit


## The enemy structures' seen_mask values, saved before a case clears them: [[unit, mask], ...].
func _save_seen() -> Array:
	var out: Array = []
	for t: Turret in world.turrets:
		if t.team == _et:
			out.append([t, t.seen_mask])
	for p: DefensePost in world.posts:
		if p.team == _et:
			out.append([p, p.seen_mask])
	return out


## Put the saved seen_mask values back.
func _restore_seen(saved: Array) -> void:
	for e: Array in saved:
		var u: Unit = e[0] as Unit
		if is_instance_valid(u):
			u.seen_mask = int(e[1])


## The `by_team` the flash cases pass to the bar's handler.
func _by() -> int:
	return _vt if _vt >= 0 else 0


# --- the cases ------------------------------------------------------------------------------------

## Run every case in the order the brief lists them.
func _run_cases() -> void:
	_case_p1()
	_case_p2()
	_case_p3()
	_case_p4()
	_case_p5()
	_case_p6()
	_case_p7()
	_case_p8()
	_case_p9()
	_case_s1()
	_case_s2()
	_case_s3()
	_case_s4()
	_case_b0()
	_case_b1()
	_case_b2_b3()
	_case_b4()
	_case_b5()
	_case_b6()
	_case_b7_b8()
	_case_b9()
	_case_b10()
	_case_b11()
	_case_f1_to_f4()
	_case_f5()
	_case_f6()


## P1: the four weights add to 1.
func _case_p1() -> void:
	var w: Variant = _consts.get("WEIGHTS", null)
	var ok := w is Dictionary
	var sum := 0.0
	if ok:
		var d: Dictionary = w as Dictionary
		for k: String in ["ms", "turrets", "posts", "value"]:
			if not d.has(k):
				ok = false
			else:
				sum += float(d[k])
		ok = ok and absf(sum - 1.0) < TOL
	_check("ahead: the four weights add to 1", ok, "%s sum %s" % [str(w), str(sum)])


## P2: the level band is a sensible size.
func _case_p2() -> void:
	var band := _band()
	_check("ahead: LEVEL_BAND is between 0 and 0.25", _consts.has("LEVEL_BAND") and band > 0.0 and band < 0.25, str(band))


## P3: equal parts put the marker in the middle.
func _case_p3() -> void:
	var case_name := "ahead: equal parts give 0.5"
	if not _need(_hb, "HudTopBar", "lead_share", case_name):
		return
	var s := _share(_parts([1.0, 1.0, true], [9, 9, true], [3, 3, true], [5000.0, 5000.0, true]))
	_check(case_name, absf(s - 0.5) < TOL, str(s))


## P4: one part moves the share by its weight.
func _case_p4() -> void:
	var case_name := "ahead: a part moves the share by its weight"
	if not _need(_hb, "HudTopBar", "lead_share", case_name):
		return
	var w := _weights()
	var wm := float(w["ms"])
	var wv := float(w["value"])
	var s1 := _share(_parts([1.0, 0.0, true], [9, 9, true], [3, 3, true], [5000.0, 5000.0, true]))
	var s2 := _share(_parts([1.0, 1.0, true], [9, 9, true], [3, 3, true], [8000.0, 2000.0, true]))
	var want1 := wm * 1.0 + (1.0 - wm) * 0.5
	var want2 := wv * 0.8 + (1.0 - wv) * 0.5
	_check(case_name, absf(s1 - want1) < TOL and absf(s2 - want2) < TOL, "%s want %s, %s want %s" % [str(s1), str(want1), str(s2), str(want2)])


## P5: a part with no data is left out of the share.
func _case_p5() -> void:
	var case_name := "ahead: a part with no data is left out"
	if not _need(_hb, "HudTopBar", "lead_share", case_name):
		return
	var s := _share(_parts([0.5, 1.0, true], [9, 0, false], [3, 0, false], [5000.0, 0.0, false]))
	_check(case_name, absf(s - 0.5 / 1.5) < TOL, str(s))


## P6: with nothing to go on the share is -1.
func _case_p6() -> void:
	var case_name := "ahead: nothing to go on gives -1"
	if not _need(_hb, "HudTopBar", "lead_share", case_name):
		return
	var none := _share(_parts([1.0, 1.0, false], [1, 1, false], [1, 1, false], [1.0, 1.0, false]))
	var zero := _share(_parts([0.0, 0.0, true], [1, 1, false], [1, 1, false], [1.0, 1.0, false]))
	_check(case_name, absf(none + 1.0) < TOL and absf(zero + 1.0) < TOL, "%s %s" % [str(none), str(zero)])


## P7: the words for a seat.
func _case_p7() -> void:
	var case_name := "ahead: the words for level, you lead, they lead and no data"
	if not _need(_hb, "HudTopBar", "lead_words", case_name):
		return
	var b := _band()
	var got := [
		_words(0.5, 0), _words(0.5 + b * 0.9, 0), _words(0.5 + b + 0.01, 0), _words(0.5 + b + 0.01, 1),
		_words(0.5 - b - 0.01, 0), _words(0.5 - b - 0.01, 1), _words(-1.0, 0),
	]
	var want := ["Level", "Level", "You lead", "They lead", "They lead", "You lead", "No data seen yet"]
	_check(case_name, got == want, str(got))


## P8: the words for a spectator.
func _case_p8() -> void:
	var case_name := "ahead: the words for a spectator name the team"
	if not _need(_hb, "HudTopBar", "lead_words", case_name):
		return
	var b := _band()
	var got := [_words(0.5 + b + 0.01, -1), _words(0.5 - b - 0.01, -1), _words(0.5, -1), _words(-1.0, -1)]
	var want := [str(Rules.TEAM_DISPLAY[0]) + " ahead", str(Rules.TEAM_DISPLAY[1]) + " ahead", "Level", "No data seen yet"]
	_check(case_name, got == want, str(got))


## P9: the text of a value.
func _case_p9() -> void:
	var case_name := "ahead: a value reads 850 or 14.2k"
	if not _need(_hb, "HudTopBar", "value_text", case_name):
		return
	var got := [str(_hb.call("value_text", 850.0)), str(_hb.call("value_text", 14200.0)), str(_hb.call("value_text", 0.0))]
	_check(case_name, got == ["850", "14.2k", "0"], str(got))


## S1: the shared value equals the series sample.
func _case_s1() -> void:
	var case_name := "series: the shared value equals the sample"
	if not _need(_ms, "MatchSeries", "team_value", case_name):
		return
	if series == null:
		_check(case_name, false, "main.gd made no match series")
		return
	series._take()
	var last: Dictionary = series.samples[series.samples.size() - 1]
	var ok := true
	var detail := ""
	for t in 2:
		var mine: Array = _ms.call("team_value", world, t, -1)
		var theirs: Array = (last["val"] as Array)[t]
		for i in 3:
			if roundi(float(mine[i])) != int(theirs[i]):
				ok = false
				detail += " team %d number %d: %s vs %s" % [t, i, str(mine[i]), str(theirs[i])]
	series.samples.pop_back()
	_check(case_name, ok, detail)


## S2: a viewer sees its own team whole.
func _case_s2() -> void:
	var case_name := "series: a viewer's own team counts whole"
	if _vt < 0:
		_not_applicable(case_name)
		return
	if not _need(_ms, "MatchSeries", "team_value", case_name):
		return
	var seen: Array = _ms.call("team_value", world, _vt, _vt)
	var whole: Array = _ms.call("team_value", world, _vt, -1)
	_check(case_name, seen == whole, "%s vs %s" % [str(seen), str(whole)])


## S3: an enemy with no ship in view counts nothing.
func _case_s3() -> void:
	var case_name := "series: an enemy with no ship in view counts nothing"
	if _vt < 0:
		_not_applicable(case_name)
		return
	if not _need(_ms, "MatchSeries", "team_value", case_name):
		return
	_dock_on()
	var row: Array = _ms.call("team_value", world, _et, _vt)
	_dock_off()
	_check(case_name, row == [0.0, 0.0, 0.0], str(row))


## S4: an enemy ship counts only while in view.
func _case_s4() -> void:
	var case_name := "series: an enemy ship counts only while in view"
	if _vt < 0:
		_not_applicable(case_name)
		return
	if not _need(_ms, "MatchSeries", "team_value", case_name):
		return
	var foe: PilotProfile = null
	for p in _enemy_pilots():
		foe = p
		break
	if foe != null:
		foe.state = "docked"
		foe.respawn_t = 0.0
		foe.hull_id = "fighter"
		_fs = world.launch(foe)
	_check("series: an enemy pilot ship can be launched for the check", _fs != null)
	if _fs == null:
		_check(case_name, false, "no enemy ship")
		return
	_see(_fs, false)
	var hidden: Array = _ms.call("team_value", world, _et, _vt)
	_see(_fs, true)
	var shown: Array = _ms.call("team_value", world, _et, _vt)
	var whole: Array = _ms.call("team_value", world, _et, -1)
	_see(_fs, false)
	var ok := hidden == [0.0, 0.0, 0.0] and float(shown[0]) >= float(Ships.HULLS["fighter"]["price"])
	for i in 3:
		ok = ok and float(shown[i]) <= float(whole[i])
	_check(case_name, ok, "hidden %s shown %s whole %s" % [str(hidden), str(shown), str(whole)])


## B0: the new widgets exist.
func _case_b0() -> void:
	var bar: Variant = _new_bar(false)
	var ok := _node(bar, "Row/Middle/Lead") is ProgressBar and _node(bar, "Row/Middle/LeadText") is Label
	for t in 2:
		ok = ok and _node(bar, _value_path(t)) is Label and _node(bar, _note_path(t)) is Label
	_free_bar(bar)
	_check("bar: the lead widgets exist", ok)


## B1: an enemy mothership never seen reads full and says so.
func _case_b1() -> void:
	var case_name := "bar: an enemy mothership never seen reads full and says so"
	if _vt < 0:
		_not_applicable(case_name)
		return
	var ms := world.mothership(_et)
	var old := ms.visible_mask
	_see(ms, false)
	var bar: Variant = _new_bar()
	var ok := absf(_hull_of(bar, _et) - 1.0) < 0.002
	ok = ok and _text_at(bar, _value_path(_et)).begins_with("Seen ")
	ok = ok and _shown(bar, _note_path(_et)) and _text_at(bar, _note_path(_et)).contains("mothership not seen")
	ok = ok and _text_at(bar, _value_path(_vt)).begins_with("Value ") and not _shown(bar, _note_path(_vt))
	var detail := "hull %s value '%s' note '%s' own '%s'" % [str(_hull_of(bar, _et)), _text_at(bar, _value_path(_et)), _text_at(bar, _note_path(_et)), _text_at(bar, _value_path(_vt))]
	_keep_words(bar)
	ms.visible_mask = old
	_free_bar(bar)
	_check(case_name, ok, detail)


## B2 and B3 share one bar: first the mothership in view, then out of view with the match 90 s older.
func _case_b2_b3() -> void:
	var n2 := "bar: an enemy mothership in view reads its hull"
	var n3 := "bar: out of view the reading is held and the time since shows"
	if _vt < 0:
		_not_applicable(n2)
		_not_applicable(n3)
		return
	var ms := world.mothership(_et)
	var old_mask := ms.visible_mask
	var old_hull := ms.hull
	var old_time := world.time
	_see(ms, true)
	ms.hull = 0.6 * ms.hull_max
	var bar: Variant = _new_bar()
	var ok2 := absf(_hull_of(bar, _et) - 0.6) < 0.002 and _text_at(bar, _note_path(_et)).contains("mothership in view")
	var d2 := "hull %s note '%s'" % [str(_hull_of(bar, _et)), _text_at(bar, _note_path(_et))]
	_keep_words(bar)
	_see(ms, false)
	ms.hull = 0.3 * ms.hull_max
	world.time += 90.0
	bar.call("refresh", world)
	var ok3 := absf(_hull_of(bar, _et) - 0.6) < 0.002 and _text_at(bar, _note_path(_et)).contains("mothership 1:30 ago")
	var d3 := "hull %s note '%s'" % [str(_hull_of(bar, _et)), _text_at(bar, _note_path(_et))]
	_keep_words(bar)
	world.time = old_time
	ms.hull = old_hull
	ms.visible_mask = old_mask
	_free_bar(bar)
	_check(n2, ok2, d2)
	_check(n3, ok3, d3)


## The three reads of B4 and B5: the enemy hull bar shows 0.3, its value starts "Value " and its note is hidden.
func _truth_reads() -> Array:
	var ms := world.mothership(_et)
	var old_mask := ms.visible_mask
	var old_hull := ms.hull
	_see(ms, false)
	ms.hull = 0.3 * ms.hull_max
	var bar: Variant = _new_bar()
	var ok := absf(_hull_of(bar, _et) - 0.3) < 0.002 and _text_at(bar, _value_path(_et)).begins_with("Value ") and not _shown(bar, _note_path(_et))
	var detail := "hull %s value '%s' note shown %s" % [str(_hull_of(bar, _et)), _text_at(bar, _value_path(_et)), str(_shown(bar, _note_path(_et)))]
	ms.hull = old_hull
	ms.visible_mask = old_mask
	_free_bar(bar)
	return [ok, detail]


## B4: with No fog on the bar shows the truth.
func _case_b4() -> void:
	var old_fog := Game.fog_off
	if _vt >= 0:
		Game.fog_off = true
	var r := _truth_reads()
	Game.fog_off = old_fog
	_check("bar: with No fog on it shows the truth", bool(r[0]), str(r[1]))


## B5: the spectator view shows the truth.
func _case_b5() -> void:
	var old_vt := world.viewer_team
	world.viewer_team = -1
	var r := _truth_reads()
	world.viewer_team = old_vt
	_check("bar: the spectator view shows the truth", bool(r[0]), str(r[1]))


## B6: the marker sits at the share.
func _case_b6() -> void:
	var case_name := "bar: the marker sits at the share"
	if not _need(_hb, "HudTopBar", "lead_share", case_name):
		return
	var bar: Variant = _new_bar()
	var parts: Variant = bar.get("_parts")
	var lead := _node(bar, "Row/Middle/Lead")
	var ok := false
	var detail := "no Lead or no parts"
	if lead is ProgressBar and parts is Dictionary:
		var share := _share(parts as Dictionary)
		var want := share if share >= 0.0 else 0.5
		ok = absf((lead as ProgressBar).value - want) < TOL
		detail = "marker %s want %s" % [str((lead as ProgressBar).value), str(want)]
	_free_bar(bar)
	_check(case_name, ok, detail)


## B7 and B8: a bar that has seen nothing, then the first enemy turret seen.
func _case_b7_b8() -> void:
	var n7 := "bar: a bar that has seen nothing reads No data seen yet"
	var n8 := "bar: the first enemy turret seen starts the turret part"
	if _vt < 0:
		_not_applicable(n7)
		_not_applicable(n8)
		return
	var ms := world.mothership(_et)
	var old_mask := ms.visible_mask
	var saved := _save_seen()
	var fs_mask := 0
	if _fs != null:
		fs_mask = _fs.visible_mask
		_see(_fs, false)
	_see(ms, false)
	for e: Array in saved:
		var su: Unit = e[0] as Unit
		su.seen_mask &= ~_bit
	_dock_on()
	var bar: Variant = _new_bar()
	var lead := _node(bar, "Row/Middle/Lead")
	var ok7 := _text_at(bar, "Row/Middle/LeadText") == "No data seen yet" and lead is ProgressBar and absf((lead as ProgressBar).value - 0.5) < TOL
	var d7 := "text '%s'" % _text_at(bar, "Row/Middle/LeadText")
	_keep_words(bar)
	var tu := _enemy_turret()
	var ok8 := false
	var d8 := "no enemy turret with a node"
	if tu != null:
		tu.seen_mask |= _bit
		bar.call("refresh", world)
		var has: Variant = _dict_entry(bar, "_has", "turrets", false)
		var part: Variant = _dict_entry(bar, "_parts", "turrets", null)
		ok8 = has == true and part is Array and (part as Array).size() > 2 and (part as Array)[2] == true
		d8 = "has %s part %s" % [str(has), str(part)]
	_dock_off()
	if _fs != null:
		_fs.visible_mask = fs_mask
	ms.visible_mask = old_mask
	_restore_seen(saved)
	_free_bar(bar)
	_check(n7, ok7, d7)
	_check(n8, ok8, d8)


## B9: no word of the bar holds a word the Admiral rules forbid.
func _case_b9() -> void:
	var bar: Variant = _new_bar()
	_keep_words(bar)
	_free_bar(bar)
	var bad := ""
	for t in _words_seen:
		var low := t.to_lower()
		if t.contains("%") or low.contains("speed") or low.contains("minion") or t.contains("Hard") or t.contains("enemy earns"):
			bad = t
			break
	_check("bar: no word holds a percent sign, speed, minion, Hard or enemy earns", bad == "", "'%s' of %d texts" % [bad, _words_seen.size()])


## B10: a practice match hides the new widgets.
func _case_b10() -> void:
	var old := world.practice
	var all := ["Row/Middle/Lead", "Row/Middle/LeadText", _value_path(0), _value_path(1), _note_path(0), _note_path(1)]
	world.practice = true
	var bar: Variant = _new_bar()
	var hidden := true
	for p: String in all:
		hidden = hidden and _node(bar, p) is Control and not _shown(bar, p)
	world.practice = false
	bar.call("refresh", world)
	var shown := true
	for p: String in ["Row/Middle/Lead", "Row/Middle/LeadText", _value_path(0), _value_path(1)]:
		shown = shown and _shown(bar, p)
	world.practice = old
	_free_bar(bar)
	_check("bar: a practice match hides the lead widgets", hidden and shown, "hidden %s shown %s" % [str(hidden), str(shown)])


## The names of the children of the node at `path`, in order.
func _child_names(bar: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	var n := _node(bar, path)
	if n != null:
		for c in n.get_children():
			out.append(String(c.name))
	return out


## B11: the node order other checks read is kept.
func _case_b11() -> void:
	var bar: Variant = _new_bar(false)
	var mid := _child_names(bar, "Row/Middle")
	var ok := mid == ["Clock", "Wave", "DiffTag", "Tags", "Lead", "LeadText"]
	for t in 2:
		ok = ok and _child_names(bar, _col(t)) == ["Name", "HullRow", "Turrets", "Note"]
	ok = ok and _child_names(bar, "Row/Halcyon/HullRow") == ["Value", "Hull"] and _child_names(bar, "Row/Cinder/HullRow") == ["Hull", "Value"]
	_free_bar(bar)
	_check("bar: the node order other checks read is kept", ok, str(mid))


## A call of the bar's handler for a fall of turret `tu` (only after the has_method test).
func _fall(bar: Variant, tu: Turret) -> void:
	bar.call("_on_turret_destroyed", tu, _by())


## True when the bar has the handler; else the case fails by name.
func _need_handler(bar: Variant, case_name: String) -> bool:
	var has: bool = bar.has_method("_on_turret_destroyed")
	_check("HudTopBar._on_turret_destroyed exists", has)
	if not has:
		_check(case_name, false, "needs HudTopBar._on_turret_destroyed")
	return has


## F1 to F4: the flash on a fall in view, none out of view, at most one in FLASH_MIN_GAP, and no sound.
func _case_f1_to_f4() -> void:
	var n1 := "flash: a turret that falls in view flashes the bar"
	var n2 := "flash: a turret that falls out of view makes no flash"
	var n3 := "flash: at most one flash in FLASH_MIN_GAP seconds"
	var tu := _enemy_turret()
	var old_mask := 0
	if tu != null:
		old_mask = tu.visible_mask
	var old_fog := Game.fog_off
	var old_time := world.time
	_cues = 0
	Events.cue.connect(_on_cue)
	# F1
	var bar: Variant = _new_bar()
	if _need_handler(bar, n1):
		if tu == null:
			_check(n1, false, "no enemy turret with a node")
		else:
			_see(tu, true)
			_fall(bar, tu)
			_check(n1, _num(bar, "_flash_left", 0.0) > 0.0, str(_num(bar, "_flash_left", 0.0)))
	_free_bar(bar)
	# F2
	bar = _new_bar()
	if _need_handler(bar, n2):
		if tu == null:
			_check(n2, false, "no enemy turret with a node")
		else:
			var out_ok := true
			if _vt >= 0:
				_see(tu, false)
				bar.set("_flash_left", 0.0)
				bar.set("_flash_last", -999.0)
				_fall(bar, tu)
				out_ok = _num(bar, "_flash_left", 0.0) == 0.0
			bar.set("_flash_left", 0.0)
			bar.set("_flash_last", -999.0)
			Game.fog_off = true
			_fall(bar, tu)
			var fog_ok := _num(bar, "_flash_left", 0.0) > 0.0
			Game.fog_off = old_fog
			if _vt >= 0:
				_check(n2, out_ok and fog_ok, "out of view %s, with No fog %s" % [str(out_ok), str(fog_ok)])
			else:
				_not_applicable(n2)
				_check("flash: with No fog on a fall flashes (spectator row)", fog_ok)
	_free_bar(bar)
	# F3
	bar = _new_bar()
	_check("flash: FLASH_MIN_GAP exists", _consts.has("FLASH_MIN_GAP"))
	var gap := float(_consts.get("FLASH_MIN_GAP", 2.0))
	if _need_handler(bar, n3):
		if tu == null:
			_check(n3, false, "no enemy turret with a node")
		else:
			_see(tu, true)
			_fall(bar, tu)
			var first := _num(bar, "_flash_left", 0.0) > 0.0
			bar.set("_flash_left", 0.0)
			_fall(bar, tu)
			var second := _num(bar, "_flash_left", 0.0) > 0.0
			bar.set("_flash_left", 0.0)
			world.time += gap + 0.1
			_fall(bar, tu)
			var third := _num(bar, "_flash_left", 0.0) > 0.0
			world.time = old_time
			_check(n3, first and not second and third, "first %s second %s later %s" % [str(first), str(second), str(third)])
	_free_bar(bar)
	Events.cue.disconnect(_on_cue)
	if tu != null:
		tu.visible_mask = old_mask
	Game.fog_off = old_fog
	world.time = old_time
	# F4
	var text := FileAccess.get_file_as_string(HB_PATH)
	_check("flash: no sound", _cues == 0 and not text.contains("Sfx") and not text.contains("Events.cue") and not text.contains(".play("), "%d cues" % _cues)


## Counts the Events.cue sent while the flash cases ran.
func _on_cue(_cue_name: String, _pos: Vector2) -> void:
	_cues += 1


## F5: the kill feed is still connected to every turret fall.
func _case_f5() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	_check("flash: the HUD exists for the check", hud != null)
	if hud == null:
		_check("flash: the kill feed still hears every turret fall", false, "no HUD")
		return
	_check("flash: the kill feed still hears every turret fall", Events.turret_destroyed.is_connected(hud.feed.on_turret_destroyed))


## F6: the bar joins and leaves the turret fall signal.
func _case_f6() -> void:
	var bar: Variant = _new_bar()
	var joined := Events.turret_destroyed.is_connected(Callable(bar as Object, "_on_turret_destroyed"))
	remove_child(bar as Node)
	var left := not Events.turret_destroyed.is_connected(Callable(bar as Object, "_on_turret_destroyed"))
	(bar as Node).free()
	_check("flash: the bar joins and leaves Events.turret_destroyed", joined and left, "joined %s left %s" % [str(joined), str(left)])


# --- the watch run --------------------------------------------------------------------------------

## Start the watch run: no case runs; the node samples the real HUD's bar every 30 match seconds.
func _start_watch(seconds: float) -> void:
	_watch_s = seconds
	_watch_next = 0.0
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		print("AHEAD_SAMPLE needs --force-hud")
		_finish()
		return
	Events.match_over.connect(func(_w: int, _r: String) -> void: _finish())


## Godot calls this every tick in a watch run: one AHEAD_SAMPLE line per 30 match seconds.
func _physics_process(_dt: float) -> void:
	if _watch_s < 0.0 or _done or world == null:
		return
	var t := world.time
	if t >= _watch_next:
		var hud := get_tree().root.find_child("Hud", true, false) as Hud
		var parts: Variant = null
		if hud != null:
			parts = (hud.get("top_bar") as Object).get("_parts")
		if parts is Dictionary and not (parts as Dictionary).is_empty():
			print(_sample_line(t, hud.get("top_bar"), parts as Dictionary))
			_watch_next += 30.0
	if t >= _watch_s:
		_finish()


## The AHEAD_SAMPLE line for the bar `bar` at match time `t`.
func _sample_line(t: float, bar: Variant, parts: Dictionary) -> String:
	var lead := _node(bar, "Row/Middle/Lead")
	var share := (lead as ProgressBar).value if lead is ProgressBar else -1.0
	var ms: Array = parts.get("ms", [0.0, 0.0, false])
	var tu: Array = parts.get("turrets", [0, 0, false])
	var po: Array = parts.get("posts", [0, 0, false])
	var va: Array = parts.get("value", [0.0, 0.0, false])
	var has := "%d,%d,%d,%d" % [int(ms[2]), int(tu[2]), int(po[2]), int(va[2])]
	return "AHEAD_SAMPLE t=%d share=%.3f words=%s ms=%.3f|%.3f turrets=%d|%d posts=%d|%d value=%.0f|%.0f has=%s" % [
		int(t), share, _text_at(bar, "Row/Middle/LeadText"), float(ms[0]), float(ms[1]), int(tu[0]), int(tu[1]),
		int(po[0]), int(po[1]), float(va[0]), float(va[1]), has]
