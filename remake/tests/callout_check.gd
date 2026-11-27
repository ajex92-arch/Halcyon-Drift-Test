extends Node
## WHAT THIS IS: the check for the spoken callout lines. It proves three things: the table of ten
## lines (CalloutData) is whole, the rule for who hears a line is right (only the team that says it),
## and the sound player (Sfx) plays a line for the viewer's own team, holds a repeat back, never holds
## Danger back and ignores a name it does not know. It only reads and sends Events.callout; it changes
## no match state and draws no random number.
##
## HOW IT WORKS: setup() waits for the first physics tick, then runs the cases once, prints one
## "PASS <what>" or "FAIL <what> <detail>" line for each and, as the last line,
## "callout_check: <n> failures", then quits. Everything this build adds (CalloutData, the
## Events.callout signal, Sfx.callouts_heard) is reached without a typed name (load() by path,
## has_signal(), get()), so a tree that lacks it fails these cases by assertion and never by a parse
## error. When CalloutData is missing only the first case of the data part and the first case of the
## sound part are printed (both FAIL) and the run ends at once. Once CalloutData exists a missing
## function or member fails its own case, and a case that could not be run is counted as skipped: the
## last case fails when any case was skipped, so a green run cannot hide one. The sound cases make one
## Sfx, set the world's viewer_team for each case and put it back. The hook cases (the team wheel's
## send path and the computer pilots' refusals) are not part of this tree yet: the part prints one INFO
## line and no FAIL.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-jungle --no-admiral-ai --seed=7 --test=callout_check
##
## WHO USES IT: main.gd loads it for --test=callout_check; the full check list runs it.

## Where the line table lives.
const DATA_PATH := "res://scripts/data/callout_data.gd"
## Where the team wheel's send path lives (it is not in every tree).
const PING_ORDERS_PATH := "res://scripts/rts/ping_orders.gd"

## The running match (set by setup()).
var world: World
## How many cases failed.
var fails := 0
## How many cases passed.
var passes := 0
## How many cases could not be run (a form that does not work). Any makes the last case fail.
var skipped := 0
## The CalloutData script, or null when the file is missing.
var _cd: Variant = null
## The constants of CalloutData (name -> value), empty while it is missing.
var _consts := {}
## True once setup() has been called and the cases have not run yet.
var _pending := false


## main.gd calls this once, right after the World is built. The cases run on the first physics tick, so
## the result line is the last thing the run prints.
func setup(w: World) -> void:
	world = w
	_pending = true


## Run the cases once, on the first tick, and quit.
func _physics_process(_dt: float) -> void:
	if not _pending:
		return
	_pending = false
	_run()
	print("callout_check: %d failures" % fails)
	get_tree().quit()


## Print one PASS or FAIL line for the case `what`, and count it.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS %s" % what)
	else:
		fails += 1
		print("FAIL %s %s" % [what, detail])


## All the cases, in order.
func _run() -> void:
	# Step 1: load the line table, only when the file exists (no engine error on a tree without it).
	if ResourceLoader.exists(DATA_PATH):
		_cd = load(DATA_PATH)
	if _cd == null:
		_check("callout data: CalloutData exists", false, "the line table script is missing")
		_check("callout sound: Events has the callout signal and Sfx counts the lines it plays", false, "CalloutData is missing, so the sound cases are not run")
		return
	_consts = (_cd as Script).get_script_constant_map()
	# Step 2: the data, the rule, the sound player, the hook part.
	_part_a()
	_part_b()
	_part_c()
	_check("callout check: no case is skipped", skipped == 0, "skipped=%d" % skipped)


## One constant of CalloutData by name, or `fallback` when it is missing.
func _const(key: String, fallback: Variant) -> Variant:
	return _consts.get(key, fallback)


## Does CalloutData have a function named `fname`?
func _has_function(fname: String) -> bool:
	if _cd == null:
		return false
	for m: Dictionary in (_cd as Script).get_script_method_list():
		if str(m.get("name", "")) == fname:
			return true
	return false


## Call the static function `fname` of CalloutData with `args`. Returns null when it does not exist.
func _call_data(fname: String, args: Array) -> Variant:
	if not _has_function(fname):
		return null
	var scr: Object = _cd
	return scr.callv(fname, args)


## Part A: the table and the rule, no match needed.
func _part_a() -> void:
	var order: Array = []
	var raw_order: Variant = _const("ORDER", [])
	if raw_order is Array:
		order = raw_order
	var lines: Dictionary = {}
	var raw_lines: Variant = _const("LINES", {})
	if raw_lines is Dictionary:
		lines = raw_lines
	_check("callout data: CalloutData exists", true)
	# A2: the ten ids in order.
	var want_order := ["attack", "defend", "on_my_way", "cant", "retreat", "need_repair", "need_support", "danger", "yes", "admiral_answer"]
	_check("callout data: ten lines in the order attack, defend, on_my_way, cant, retreat, need_repair, need_support, danger, yes, admiral_answer", order == want_order, str(order))
	# A3: each line has a short plain text and 1 to 4 notes.
	var bad := ""
	for id in want_order:
		var row: Variant = lines.get(id, null)
		if not (row is Dictionary):
			bad += " %s:no row" % id
			continue
		var text: Variant = (row as Dictionary).get("text", null)
		var notes: Variant = (row as Dictionary).get("notes", null)
		if not (text is String) or (text as String).length() < 1 or (text as String).length() > 24 or (text as String).contains("_"):
			bad += " %s:text" % id
		if not (notes is Array) or (notes as Array).size() < 1 or (notes as Array).size() > 4:
			bad += " %s:notes" % id
	_check("callout data: each line has a spoken text of 1 to 24 characters with no underscore and a placeholder of 1 to 4 notes", bad == "", bad.strip_edges())
	# A4: the ten note lists are all different.
	var seen := {}
	for id in want_order:
		var row2: Variant = lines.get(id, null)
		if row2 is Dictionary:
			seen[str((row2 as Dictionary).get("notes", null))] = true
	_check("callout data: the ten placeholder note lists are all different", seen.size() == 10, "different=%d" % seen.size())
	# A5: the wheel's eight slices are the first eight lines.
	var slice_lines: Variant = _const("SLICE_LINES", [])
	_check("callout data: the eight wheel slices map to the first eight lines in the wheel's order", slice_lines is Array and slice_lines == want_order.slice(0, 8), str(slice_lines))
	# A6: the lines nothing sends yet.
	var hookless: Variant = _const("HOOKLESS", [])
	_check("callout data: the lines with no hook yet are need_repair, need_support and admiral_answer", hookless is Array and hookless == ["need_repair", "need_support", "admiral_answer"], str(hookless))
	# A7: only the sender's team hears.
	var spectator: Variant = _const("SPECTATOR_HEARS", null)
	var h00: Variant = _call_data("hears", [0, 0])
	var h11: Variant = _call_data("hears", [1, 1])
	var h01: Variant = _call_data("hears", [0, 1])
	var h10: Variant = _call_data("hears", [1, 0])
	var hs: Variant = _call_data("hears", [-1, 0])
	var rule_ok: bool = h00 == true and h11 == true and h01 == false and h10 == false and spectator is bool and not (spectator as bool) and hs == spectator
	_check("callout rule: only the sender's team hears", rule_ok, "hears(0,0)=%s (1,1)=%s (0,1)=%s (1,0)=%s (-1,0)=%s SPECTATOR_HEARS=%s" % [h00, h11, h01, h10, hs, spectator])
	# A8: Danger has no gap, every other line has the same positive gap.
	var gap_const: Variant = _const("GAP_S", null)
	var danger_gap: Variant = _call_data("gap_of", ["danger"])
	var gap_bad := ""
	for id in want_order:
		if id == "danger":
			continue
		var g: Variant = _call_data("gap_of", [id])
		if not (g is float) or not (gap_const is float) or not is_equal_approx(g, gap_const) or g <= 0.0:
			gap_bad += " %s=%s" % [id, g]
	_check("callout rule: Danger has no gap and every other line has the same positive gap", danger_gap is float and is_equal_approx(danger_gap, 0.0) and gap_bad == "", "danger=%s others:%s" % [danger_gap, gap_bad])


## How many times the sound player started line `id` (0 when it keeps no count).
func _heard(sfx: Node, id: String) -> int:
	var d: Variant = sfx.get("callouts_heard")
	if d is Dictionary:
		return int((d as Dictionary).get(id, 0))
	return 0


## Send the callout signal for `line` from `team`, when the signal exists.
func _say(line: String, team: int) -> void:
	if Events.has_signal("callout"):
		Events.emit_signal("callout", line, team)


## Part B: the sound player, with the viewer's team set for each case.
func _part_b() -> void:
	var saved_viewer := world.viewer_team
	var sfx := Sfx.new()
	add_child(sfx)
	sfx.setup(world)
	var order: Array = []
	var raw_order: Variant = _const("ORDER", [])
	if raw_order is Array:
		order = raw_order
	# B1: the signal exists and the player counts what it plays.
	var counts: Variant = sfx.get("callouts_heard")
	_check("callout sound: Events has the callout signal and Sfx counts the lines it plays", Events.has_signal("callout") and counts is Dictionary and (counts as Dictionary).is_empty(), "has_signal=%s counts=%s" % [Events.has_signal("callout"), counts])
	# B2: the viewer's own team is heard.
	world.viewer_team = 0
	_say("attack", 0)
	_check("callout sound: a line from the viewer's own team plays", _heard(sfx, "attack") == 1, "attack=%d" % _heard(sfx, "attack"))
	# B3: the other team is not heard.
	_say("defend", 1)
	_check("callout sound: a line from the other team does not play", _heard(sfx, "defend") == 0, "defend=%d" % _heard(sfx, "defend"))
	# B4: the viewer on team 1 hears team 1 and not team 0.
	world.viewer_team = 1
	_say("retreat", 0)
	_say("on_my_way", 1)
	_check("callout sound: the viewer on the other team hears that team's line and not ours", _heard(sfx, "retreat") == 0 and _heard(sfx, "on_my_way") == 1, "retreat=%d on_my_way=%d" % [_heard(sfx, "retreat"), _heard(sfx, "on_my_way")])
	# B5: a spectator hears as SPECTATOR_HEARS says.
	world.viewer_team = -1
	_say("cant", 0)
	var spectator: Variant = _const("SPECTATOR_HEARS", null)
	var want_plays := 1 if (spectator is bool and (spectator as bool)) else 0
	_check("callout sound: a spectator hears as SPECTATOR_HEARS says", spectator is bool and _heard(sfx, "cant") == want_plays, "cant=%d SPECTATOR_HEARS=%s" % [_heard(sfx, "cant"), spectator])
	# B6: a repeat inside the gap plays once.
	world.viewer_team = 0
	_say("yes", 0)
	_say("yes", 0)
	_check("callout sound: a line repeated inside the gap plays once", _heard(sfx, "yes") == 1, "yes=%d" % _heard(sfx, "yes"))
	# B7: Danger is never held back.
	_say("danger", 0)
	_say("danger", 0)
	_say("danger", 0)
	_check("callout sound: Danger is never held back", _heard(sfx, "danger") == 3, "danger=%d" % _heard(sfx, "danger"))
	# B8: a name that is not a line is ignored.
	_say("zzz", 0)
	var after: Variant = sfx.get("callouts_heard")
	_check("callout sound: an unknown line is ignored", after is Dictionary and not (after as Dictionary).has("zzz"), str(after))
	# B9: every line has a baked stream.
	var streams: Variant = sfx.get("_streams")
	var missing := ""
	for id in order:
		if not (streams is Dictionary) or not (streams as Dictionary).has("callout_" + str(id)):
			missing += " " + str(id)
	_check("callout sound: every one of the ten lines has a baked stream", order.size() == 10 and missing == "", "order=%d missing:%s" % [order.size(), missing])
	# Step: put everything back.
	world.viewer_team = saved_viewer
	sfx.free()


## Part C: the hook cases. The team wheel is not in this tree, so there is nothing to run.
func _part_c() -> void:
	if ResourceLoader.exists(PING_ORDERS_PATH):
		print("INFO callout hook: PingOrders is in this tree, the hook cases are not part of this check yet")
	else:
		print("INFO callout hook: PingOrders is not in this tree, the hook cases are not run")
