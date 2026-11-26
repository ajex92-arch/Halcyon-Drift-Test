extends Node
## WHAT THIS IS: the check of the edge wedges (S7A, #107 part two) that HudAlarm draws for the human's own mothership under attack.
## It proves that one "mothership_under_attack" record of the human's team gives one wedge that points at the place, that a place on
## the screen gives none, that another team's record gives none, that five places give four wedges and a "+1", that a wedge ends
## after WEDGE_LIFE_S (fading in its last second, never blinking), that a second record for the same place renews the wedge, that the
## Bomber triangles keep their own drawing and are not counted in the four, that a wedge alone shows the layer, and that a pilot who
## is not flying gets none. S7A fix pass: while the human team's defend call is on the wedge is renewed and one is made when there is
## none, it ends WEDGE_LIFE_S after the call goes off, and neither another team's call nor a pilot who is not flying renews it; the
## danger sign inside a wedge is drawn at the wedge's own strength (full while steady, fading with it).
##
## HOW IT WORKS: it makes an alarm of its own (a HudAlarm that is a child of this check, with its own _process off), sends records on
## Events.rts_event as RtsEvents does, and reads the wedges back through wedge_entries() and wedge_layout() with a screen of its own
## (1280 x 720 and no camera, so the place on the screen is the place in the world). The one drawing case lets the alarm draw for two
## frames and reads its counters. The new members are only reached through has_method() and get(), so on a tree without them every case
## that needs them prints FAIL (and the two cases that only need "no wedge" pass) and the script still parses. Every case prints
## `edge_wedge_check: PASS <case>` or `FAIL <case>`; the last lines are `edge_wedge_check: <n> checks, <k> failures` and, when k is 0,
## `edge_wedge_check: 0 failures`.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=edge_wedge_check
##
## WHO USES IT: main.gd loads it for --test=edge_wedge_check. It sends records on Events.rts_event, sets the human's state for one case
## and puts it back; the match itself is not changed.

## The middle of the check's screen and the room the wedge walks out to (the screen's half sizes less the alarm's margin of 30).
const CENTRE := Vector2(640.0, 360.0)
## The room inside the margin (HudAlarm.MARGIN is 30).
const ROOM := Vector2(610.0, 330.0)

## The running match (set by setup()).
var world: World
## How many checks ran.
var checks := 0
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false
## Frames seen so far.
var _frames := 0
## The check's own alarm.
var _alarm: HudAlarm


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	# With --bot no one launches the human (main.gd does it only without --bot), so do what main.gd does when the human is not flying yet.
	if world.human != null and world.human.ship == null:
		HumanCmd.run(world, "buy_hull", ["fighter"])
		HumanCmd.run(world, "launch")


## Every frame: wait until the human flies a ship (at most 600 frames), then run once; time out after 150 s of real time.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	_frames += 1
	if Time.get_ticks_msec() > 150000:
		print("edge_wedge_check: timeout")
		get_tree().quit()
		return
	var me := world.human
	var flying := me != null and me.state == "flying" and me.ship != null and is_instance_valid(me.ship) and me.ship.alive
	var has_foe := false
	if flying:
		for s: Ship in world.ships:
			if is_instance_valid(s) and s.alive and s.team != me.ship.team:
				has_foe = true
				break
	if not (flying and has_foe) and _frames < 600:
		return
	_started = true
	if not flying:
		_check("setup: the human flies a ship", false, "no flying ship after %d frames" % _frames)
		print("edge_wedge_check: %d checks, %d failures" % [checks, failures])
		get_tree().quit()
		return
	_run()


## The whole check, then the summary lines and quit.
func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_alarm = HudAlarm.new()
	add_child(_alarm)
	_alarm.setup(world)
	_alarm.set_process(false)
	_one_record()
	_on_screen()
	_enemy_record()
	_five()
	_life_and_fade()
	_renew()
	_attack_renews()
	_layer_and_flying()
	await _bomber()
	await _sign_alpha()
	_alarm.queue_free()
	print("edge_wedge_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("edge_wedge_check: 0 failures")
	get_tree().quit()


## Print a PASS or FAIL line for the case `what`.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("edge_wedge_check: %s %s%s" % ["PASS" if ok else "FAIL", what, ("" if detail == "" else ": " + detail)])


## Forget every wedge of the alarm (when it has any).
func _reset() -> void:
	var w: Variant = _alarm.get("_wedges")
	if w != null:
		(w as Array).clear()


## How many wedges the alarm holds (0 on a tree without them).
func _held() -> int:
	var w: Variant = _alarm.get("_wedges")
	return 0 if w == null else (w as Array).size()


## The wedges the layout gives for the alarm's wedges at match time `now`, on the check's own screen (no camera): [] when the tree has no layout.
func _rows(now: float) -> Array:
	if not _alarm.has_method("wedge_entries") or not _alarm.has_method("wedge_layout"):
		return []
	return _alarm.call("wedge_layout", _alarm.call("wedge_entries", Transform2D.IDENTITY, now), CENTRE, ROOM) as Array


## Send a "mothership_under_attack" record of `team` for place `pos` (a Vector2i, as RtsEvents sends it).
func _send(team: int, pos: Variant) -> void:
	Events.rts_event.emit({"tick": 0, "kind": "mothership_under_attack", "team": team, "pos": pos, "uid": 0, "data": {}})


## One record gives one wedge that points at the place and stands on the edge walk.
func _one_record() -> void:
	_reset()
	_send(world.human_team, Vector2i(5000, 360))
	var rows := _rows(world.time)
	var ok := _alarm.has_method("wedge_layout") and rows.size() == 1
	if ok:
		var r: Dictionary = rows[0]
		ok = (r["dir"] as Vector2).distance_to(Vector2(1.0, 0.0)) < 0.001 and (r["at"] as Vector2).distance_to(Vector2(1250.0, 360.0)) < 0.01 and int(r["more"]) == 0
	_check("one record gives one wedge pointing at the place, on the edge walk", ok, str(rows))
	# A place up and to the left points up and to the left.
	_reset()
	_send(world.human_team, Vector2i(-3000, -2000))
	var rows2 := _rows(world.time)
	var want := (Vector2(-3000.0, -2000.0) - CENTRE).normalized()
	_check("a place up and left gives a wedge pointing there", rows2.size() == 1 and (rows2[0]["dir"] as Vector2).distance_to(want) < 0.001, str(rows2))
	# A record with no place (the team has no mothership) adds nothing.
	_reset()
	_send(world.human_team, null)
	_check("a record with no place adds nothing", _alarm.has_method("add_wedge") and _held() == 0)


## A mothership on the screen gives no wedge.
func _on_screen() -> void:
	_reset()
	_send(world.human_team, Vector2i(600, 360))
	_check("a mothership on the screen gives none", _rows(world.time).is_empty())


## Another team's record gives no wedge.
func _enemy_record() -> void:
	_reset()
	var other := 1 - world.human_team
	_send(other, Vector2i(5000, 360))
	_check("an enemy team's record gives none", _held() == 0 and _rows(world.time).is_empty())
	_reset()
	Events.rts_event.emit({"tick": 0, "kind": "research_done", "team": world.human_team, "pos": Vector2i(5000, 360), "uid": 0, "data": {}})
	_check("a record of another kind gives none", _alarm.has_method("add_wedge") and _held() == 0)


## Five places (and a sixth on the screen) give four wedges and "+1".
func _five() -> void:
	var entries: Array = []
	for i in 5:
		entries.append({"at": Vector2(3000.0, 360.0 + 400.0 * float(i)), "alpha": 1.0})
	entries.append({"at": Vector2(600.0, 300.0), "alpha": 1.0})
	var rows: Array = []
	if _alarm.has_method("wedge_layout"):
		rows = _alarm.call("wedge_layout", entries, CENTRE, ROOM) as Array
	var ok := rows.size() == 4
	if ok:
		ok = int(rows[0]["more"]) == 0 and int(rows[1]["more"]) == 0 and int(rows[2]["more"]) == 0 and int(rows[3]["more"]) == 1
	_check("five places give four wedges and a +1 (a place on the screen is not counted)", ok, str(rows.size()))
	var four: Array = []
	if _alarm.has_method("wedge_layout"):
		four = _alarm.call("wedge_layout", entries.slice(0, 4), CENTRE, ROOM) as Array
	_check("four places give four wedges and no count", four.size() == 4 and int(four[3]["more"]) == 0)


## A wedge ends after WEDGE_LIFE_S, steady until its last second and then falling in a straight line to nothing.
func _life_and_fade() -> void:
	_reset()
	var life := _const("WEDGE_LIFE_S", 0.0)
	var fade := _const("WEDGE_FADE_S", 0.0)
	var t0 := world.time
	_send(world.human_team, Vector2i(5000, 360))
	var has := _alarm.has_method("prune_wedges") and _alarm.has_method("wedge_entries")
	var early := 0
	var steady := 0.0
	var fading := 0.0
	if has:
		_alarm.call("prune_wedges", t0 + life - 0.1)
		early = _held()
		steady = float((_alarm.call("wedge_entries", Transform2D.IDENTITY, t0 + life - fade - 0.01) as Array)[0]["alpha"]) if _held() > 0 else -1.0
		fading = float((_alarm.call("wedge_entries", Transform2D.IDENTITY, t0 + life - fade * 0.5) as Array)[0]["alpha"]) if _held() > 0 else -1.0
		_alarm.call("prune_wedges", t0 + life + 0.01)
	_check("a wedge is still there just before WEDGE_LIFE_S", has and early == 1)
	_check("a wedge is steady (full strength) until its last second", has and absf(steady - 1.0) < 0.001, str(steady))
	_check("a wedge fades in a straight line in its last second (half strength halfway)", has and absf(fading - 0.5) < 0.001, str(fading))
	_check("a wedge ends after WEDGE_LIFE_S", has and _held() == 0, str(_held()))
	_check("WEDGE_LIFE_S is a few seconds", life >= 2.0 and life <= 15.0 and fade > 0.0 and fade < life, "%s, %s" % [str(life), str(fade)])


## A second record for the same place renews the wedge instead of adding another.
func _renew() -> void:
	_reset()
	_send(world.human_team, Vector2i(5000, 360))
	_send(world.human_team, Vector2i(5010, 365))
	var same := _held()
	_send(world.human_team, Vector2i(-5000, 360))
	_check("a second record for the same place renews the wedge; another place adds one", same == 1 and _held() == 2, "%d then %d" % [same, _held()])


## Put the human team's defend call on (a defend point at `place` and a deadline far ahead) or off (the deadline already past).
func _call_set(ts: TeamState, place: Vector2, on: bool) -> void:
	ts.defend_point = place
	ts.defend_until = world.time + 1000.0 if on else world.time - 1.0


## Put one wedge in directly: at world place `place`, made or renewed at match time `t0`.
func _put_wedge(place: Vector2, t0: float) -> void:
	_reset()
	(_alarm.get("_wedges") as Array).append({"pos": place, "t0": t0})


## While the human team's defend call is on the wedge is renewed toward the mothership (and one is made when there is none); after the
## call goes off it stays WEDGE_LIFE_S more seconds and ends; another team's call, or a pilot who is not flying, renews nothing.
## Every case runs at once (no frame passes), and the call, the other team's call and the human's state are put back.
func _attack_renews() -> void:
	var hi := world.human_team
	var n := world.teams.size()
	var ms: Mothership = null
	if hi >= 0 and hi < n and n >= 2:
		ms = world.mothership(hi)
	if ms == null or not is_instance_valid(ms):
		_check("setup: the human team and its mothership are there", false, "teams %d, human team %d" % [n, hi])
		return
	var ts: TeamState = world.teams[hi]
	var ots: TeamState = world.teams[1 - hi]
	var keep_point := ts.defend_point
	var keep_until := ts.defend_until
	var okeep_point := ots.defend_point
	var okeep_until := ots.defend_until
	var me := world.human
	var was: String = me.state
	var place := ms.global_position
	var life := _const("WEDGE_LIFE_S", 0.0)
	_call_set(ots, Vector2.INF, false)
	# W1: with the call on, a wedge older than WEDGE_LIFE_S is kept and renewed (its t0 is now).
	_call_set(ts, place, true)
	_put_wedge(place, world.time - 100.0)
	_alarm.call("_process", 0.0)
	var t0 := -1.0
	if _held() > 0:
		t0 = float(((_alarm.get("_wedges") as Array)[0] as Dictionary)["t0"])
	_check("while the attack call is on, a wedge older than WEDGE_LIFE_S is kept", _held() == 1 and absf(t0 - world.time) < 0.001, "%d held, t0 %s, now %s" % [_held(), str(t0), str(world.time)])
	# W2 (control): with the call off the same old wedge is pruned.
	_call_set(ts, place, false)
	_put_wedge(place, world.time - 100.0)
	_alarm.call("_process", 0.0)
	_check("with the call off the same old wedge is pruned", _held() == 0, str(_held()))
	# W3: launching into an attack: with the call on and no wedge, one is added at the mothership's place.
	_call_set(ts, place, true)
	_reset()
	_alarm.call("_process", 0.0)
	var pos := Vector2.INF
	if _held() > 0:
		pos = (((_alarm.get("_wedges") as Array)[0] as Dictionary)["pos"] as Vector2)
	_check("launching into an attack: with the call on and no wedge, one is added at the mothership's place", _held() == 1 and pos.distance_to(Vector2(RtsEvents.point_of(place))) < 1.0, "%d held, pos %s" % [_held(), str(pos)])
	# W4: after the call goes off the wedge stays WEDGE_LIFE_S more seconds, then ends.
	_call_set(ts, place, true)
	_put_wedge(place, world.time - 100.0)
	_alarm.call("_process", 0.0)
	var now := world.time
	_call_set(ts, place, false)
	var before := -1
	var after := -1
	if _alarm.has_method("prune_wedges"):
		_alarm.call("prune_wedges", now + life - 0.1)
		before = _held()
		_alarm.call("prune_wedges", now + life + 0.01)
		after = _held()
	_check("after the call goes off the wedge stays WEDGE_LIFE_S more seconds, then ends", before == 1 and after == 0, "%d, then %d" % [before, after])
	# W5 (control): the other team's call does not renew.
	_call_set(ts, place, false)
	_call_set(ots, place, true)
	_put_wedge(place, world.time - 100.0)
	_alarm.call("_process", 0.0)
	_check("the other team's call does not renew", _held() == 0, str(_held()))
	# W6 (control): a pilot who is not flying gets no renewal and no wedge.
	_call_set(ots, Vector2.INF, false)
	_call_set(ts, place, true)
	_put_wedge(place, world.time - 100.0)
	me.state = "docked"
	_alarm.call("_process", 0.0)
	var docked := _held()
	me.state = was
	_check("a pilot who is not flying gets no renewal and no wedge", docked == 0, str(docked))
	ts.defend_point = keep_point
	ts.defend_until = keep_until
	ots.defend_point = okeep_point
	ots.defend_until = okeep_until
	_reset()


## A wedge alone shows the layer; a pilot who is not flying gets none.
func _layer_and_flying() -> void:
	_reset()
	_send(world.human_team, Vector2i(5000, 360))
	var before := _held()
	if _alarm.has_method("prune_wedges"):
		_alarm.call("_process", 0.0)
	_check("a wedge alone shows the layer", before == 1 and _alarm.visible)
	var me := world.human
	var was: String = me.state
	me.state = "docked"
	_send(world.human_team, Vector2i(-5000, 360))
	var added_docked := _held()
	_alarm.call("_process", 0.0)
	var after := _held()
	var shown := _alarm.visible
	me.state = was
	_check("a pilot who is not flying gets no wedge (and the ones shown are cleared)", before == 1 and added_docked == 1 and after == 0 and not shown, "%d, %d, %d, visible %s" % [before, added_docked, after, str(shown)])


## The Bomber triangles keep their own drawing and are not counted in the four: one Bomber mark and two wedges draw one triangle and two wedges.
func _bomber() -> void:
	_reset()
	var me := world.human
	var foe: Ship = null
	for s: Ship in world.ships:
		if is_instance_valid(s) and s.alive and s.team != me.ship.team:
			foe = s
			break
	var ship_pos := me.ship.global_position
	_send(world.human_team, Vector2i(roundi(ship_pos.x) + 30000, roundi(ship_pos.y)))
	_send(world.human_team, Vector2i(roundi(ship_pos.x) - 30000, roundi(ship_pos.y) + 100))
	var marks: Array = _alarm.get("_marks")
	if foe != null:
		marks.append(foe)
	_alarm.visible = true
	_alarm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var bombers: Variant = _alarm.get("drawn_bombers")
	var wedges: Variant = _alarm.get("drawn_wedges")
	_check("the Bomber triangle keeps its drawing and the wedges are drawn beside it", foe != null and bombers != null and wedges != null and int(bombers) == 1 and int(wedges) == 2, "bombers %s, wedges %s" % [str(bombers), str(wedges)])
	marks.clear()
	_reset()


## One wedge, far off the screen, drawn for two frames: the danger sign is handed the wedge's own strength (full while the wedge is
## steady, about half halfway through its last second). The alarm records the strength it drew with (drawn_sign_alpha and
## drawn_wedge_alpha); a headless run draws no pixels, so this reads the strength handed to the sign, not the colour on the screen.
func _sign_alpha() -> void:
	var ship_pos := world.human.ship.global_position
	var far := Vector2(ship_pos.x + 30000.0, ship_pos.y)
	var life := _const("WEDGE_LIFE_S", 0.0)
	var fade := _const("WEDGE_FADE_S", 0.0)
	var marks: Array = _alarm.get("_marks")
	marks.clear()
	_put_wedge(far, world.time - (life - fade * 0.5))
	_alarm.visible = true
	_alarm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var wedge_a: Variant = _alarm.get("drawn_wedge_alpha")
	var sign_a: Variant = _alarm.get("drawn_sign_alpha")
	var ok := wedge_a != null and sign_a != null and float(wedge_a) > 0.2 and float(wedge_a) < 0.8 and absf(float(sign_a) - float(wedge_a)) < 0.001
	_check("the danger sign draws at the wedge's own strength in its fade", ok, "wedge %s, sign %s" % [str(wedge_a), str(sign_a)])
	_put_wedge(far, world.time)
	_alarm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	sign_a = _alarm.get("drawn_sign_alpha")
	_check("the sign is at full strength while the wedge is steady", sign_a != null and absf(float(sign_a) - 1.0) < 0.001, str(sign_a))
	_reset()


## A constant of the alarm's script (`fallback` when this tree has none).
func _const(name: String, fallback: float) -> float:
	var map: Dictionary = (_alarm.get_script() as Script).get_script_constant_map()
	return float(map[name]) if map.has(name) else fallback
