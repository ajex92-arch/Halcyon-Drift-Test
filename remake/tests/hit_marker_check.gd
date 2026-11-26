extends Node
## WHAT THIS IS: the check of the hit markers (S7A, #111 picture half): the small crosses HitMarkers draws where the human pilot's own
## shots land. It proves that a hit the shields take gives a "shield" marker, one that takes hull a "hull" marker and one that
## breaks a shield zone a "zone" marker (each through Combat.apply_damage and Events.hit_landed, the real way), that another ship's
## hit and a hit while the human is not flying give nothing, that two hits closer than 334 ms give one marker (a zone marker inside the
## gap replaces a weaker one), that a target with no shields never gives "zone", that a hit on a small craft is drawn at the pointer and
## a hit on anything bigger at the struck side, and that the flash table has the rows for the markers and the edge wedges.
##
## HOW IT WORKS: it makes a HitMarkers of its own (a child of this check, with its own _process off) and takes a real enemy ship of the
## match as the target. The kind cases set the target's shield zones and armour for the case and put them back at the end. The gap,
## the placement and the "nothing" cases call on_hit() directly with a match time of their own. HitMarkers is only reached through
## load() behind ResourceLoader.exists, so on a tree without it every case that needs it prints FAIL and the two "nothing" cases (they
## count zero markers) pass; the script still parses. Every case prints `hit_marker_check: PASS <case>` or `FAIL <case>`; the last
## lines are `hit_marker_check: <n> checks, <k> failures` and, when k is 0, `hit_marker_check: 0 failures`.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=hit_marker_check
##
## WHO USES IT: main.gd loads it for --test=hit_marker_check. It damages one enemy ship of its own match and changes the human's state
## and the test pointer for single cases, and puts them back.

## The class under test (S7A): reached only through load().
const HM_PATH := "res://scripts/ui/hit_markers.gd"

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
## The check's own HitMarkers (null on a tree without the class).
var _hm: Variant = null
## The human's ship (the shooter) and the enemy ship that is the target.
var _me: Ship
## The enemy ship the cases hit.
var _foe: Ship


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	# With --bot no one launches the human (main.gd does it only without --bot), so do what main.gd does when the human is not flying yet.
	if world.human != null and world.human.ship == null:
		HumanCmd.run(world, "buy_hull", ["fighter"])
		HumanCmd.run(world, "launch")


## Every frame: wait until the human flies and an enemy ship with shields is there (at most 600 frames), then run once; time out after 150 s.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	_frames += 1
	if Time.get_ticks_msec() > 150000:
		print("hit_marker_check: timeout")
		get_tree().quit()
		return
	var me := world.human
	var flying := me != null and me.state == "flying" and me.ship != null and is_instance_valid(me.ship) and me.ship.alive
	if flying and _enemy() != null:
		_started = true
		_run()
	elif _frames >= 600:
		_started = true
		_run()


## A live enemy ship that has shields, or null.
func _enemy() -> Ship:
	var me := world.human
	if me == null or me.ship == null:
		return null
	for s: Ship in world.ships:
		if is_instance_valid(s) and s.alive and s.team != me.ship.team and s.shields != null and s.shields.max_total > 0.0:
			return s
	return null


## The whole check, then the summary lines and quit.
func _run() -> void:
	_me = world.human.ship if world.human != null else null
	_foe = _enemy()
	if _me == null or _foe == null:
		_check("setup: the human flies and an enemy ship with shields exists", false, "ship %s, enemy %s" % [str(_me != null), str(_foe != null)])
	else:
		if ResourceLoader.exists(HM_PATH):
			var s: Script = load(HM_PATH)
			_hm = s.new()
			add_child(_hm as Node)
			_hm.call("setup", world)
			(_hm as Node).set_process(false)
		_kinds()
		_nothing()
		_gap()
		_no_shields()
		_placement()
	_table()
	if _hm != null:
		(_hm as Node).queue_free()
	print("hit_marker_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("hit_marker_check: 0 failures")
	get_tree().quit()


## Print a PASS or FAIL line for the case `what`.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("hit_marker_check: %s %s%s" % ["PASS" if ok else "FAIL", what, ("" if detail == "" else ": " + detail)])


## The markers now (an empty list on a tree without the class).
func _markers() -> Array:
	return [] if _hm == null else ((_hm as Object).get("markers") as Array)


## The kind of the only marker, or "" when there is not exactly one.
func _only_kind() -> String:
	var m := _markers()
	return str((m[0] as Dictionary)["kind"]) if m.size() == 1 else ""


## Forget the markers and the gap (when there is a HitMarkers).
func _clear() -> void:
	if _hm != null:
		(_hm as Object).call("clear")


## A hit of the human's ship on `target`, of `amount`, from `from`.
func _hit_of(src: Unit, amount: float, from: Vector2) -> DamageInfo:
	return DamageInfo.from_unit(src, amount, Rules.W_BOLT, from)


## The target's shield state as it is now, to put back: [values, gate_left, flash].
func _save_shields() -> Array:
	var sh := _foe.shields
	return [sh.values.duplicate(), sh.gate_left.duplicate(), sh.flash.duplicate()]


## Put a saved shield state back.
func _load_shields(saved: Array) -> void:
	var sh := _foe.shields
	sh.values = saved[0]
	sh.gate_left = saved[1]
	sh.flash = saved[2]


## Set every zone of the target to `value` points, with no gate and no flash running.
func _set_zones(value: float) -> void:
	var sh := _foe.shields
	for i in 4:
		sh.values[i] = value
		sh.gate_left[i] = 0.0
		sh.flash[i] = 0.0


## The three kinds, through the real chain: Combat.apply_damage -> Events.hit_landed -> HitMarkers.
func _kinds() -> void:
	var saved := _save_shields()
	var armour_was := _foe.armour
	var from := _foe.global_position + Vector2(400.0, 0.0)
	_foe.hull = _foe.hull_max
	# A hit the shield takes: a "shield" marker (the probes' damage signal is off in this run, so the marker does not depend on it).
	var probes_were := world.combat.emit_damage_events
	world.combat.emit_damage_events = false
	_set_zones(1000000.0)
	_clear()
	var ret := world.combat.apply_damage(_foe, _hit_of(_me, 5.0, from))
	_check("a human hit the shield takes gives a shield marker (with the probes' damage signal off)", ret == 0.0 and _only_kind() == "shield", "hull %s, markers %s" % [str(ret), str(_markers())])
	world.combat.emit_damage_events = probes_were
	# A hit that reaches the hull (no shield left, no armour in the way): a "hull" marker.
	_set_zones(0.0)
	_foe.armour = null
	_clear()
	ret = world.combat.apply_damage(_foe, _hit_of(_me, 30.0, from))
	_check("a human hit that takes hull gives a hull marker", ret > 0.0 and _only_kind() == "hull", "hull %s, markers %s" % [str(ret), str(_markers())])
	_foe.armour = armour_was
	_foe.hull = _foe.hull_max
	# A hit that empties a shield zone: a "zone" marker (the zone's flash has just started).
	_set_zones(1.0)
	_clear()
	ret = world.combat.apply_damage(_foe, _hit_of(_me, 30.0, from))
	var flashed := false
	for f: float in _foe.shields.flash:
		if f > 0.39:
			flashed = true
	_check("a human hit that empties a zone gives a zone marker", flashed and _only_kind() == "zone", "flash set %s, markers %s" % [str(flashed), str(_markers())])
	_load_shields(saved)
	_foe.armour = armour_was
	_foe.hull = _foe.hull_max
	# The kind from the numbers alone.
	var ok := _hm != null
	if ok:
		var o := _hm as Object
		ok = str(o.call("kind_of", 0.0, false)) == "shield" and str(o.call("kind_of", 3.0, false)) == "hull" and str(o.call("kind_of", 0.0, true)) == "zone" and str(o.call("kind_of", 3.0, true)) == "zone"
	_check("the kind follows the hit: zone over hull over shield", ok)


## Another ship's hit, and a hit while the human is not flying, give nothing.
func _nothing() -> void:
	_clear()
	var from := _foe.global_position + Vector2(400.0, 0.0)
	if _hm != null:
		# Another ship's hit (the enemy ship hits the human's ship): not drawn.
		(_hm as Object).call("on_hit", _me, _hit_of(_foe, 5.0, from), 5.0, false)
	_check("another team's hit gives nothing", _markers().is_empty())
	_clear()
	var me := world.human
	var was: String = me.state
	me.state = "docked"
	if _hm != null:
		(_hm as Object).call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false)
	var docked := _markers().size()
	me.state = was
	_check("a hit while the human is not flying gives nothing", docked == 0)
	# The same hit while the human flies is drawn (so the two cases above are not just a broken list).
	_clear()
	if _hm != null:
		(_hm as Object).call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false)
	_check("the same hit while the human flies gives one marker", _markers().size() == 1)
	_clear()


## Two events closer than 334 ms give one marker; a zone marker inside the gap replaces a weaker one.
func _gap() -> void:
	var from := _foe.global_position + Vector2(400.0, 0.0)
	var gap_ms := 0
	if _hm != null:
		var map: Dictionary = ((_hm as Object).get_script() as Script).get_script_constant_map()
		gap_ms = int(map.get("GAP_MS", 0))
	_check("GAP_MS is 334", gap_ms == 334, str(gap_ms))
	_clear()
	if _hm != null:
		var o := _hm as Object
		o.call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false, 100.0)
		o.call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false, 100.1)
	var inside := _markers().size()
	if _hm != null:
		(_hm as Object).call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false, 100.5)
	_check("two events closer than 334 ms give one marker, a later one gives a second", inside == 1 and _markers().size() == 2, "%d then %d" % [inside, _markers().size()])
	_clear()
	var kinds: Array = []
	if _hm != null:
		var o2 := _hm as Object
		o2.call("on_hit", _foe, _hit_of(_me, 5.0, from), 0.0, false, 200.0)
		o2.call("on_hit", _foe, _hit_of(_me, 5.0, from), 0.0, true, 200.1)
		kinds.append(_only_kind())
		o2.call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false, 200.2)
		kinds.append(_markers().size())
		o2.call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false, 200.4)
		kinds.append(_markers().size())
	_check("a zone marker inside the gap replaces a weaker one and does not start the gap again", kinds == ["zone", 1, 2], str(kinds))
	_clear()


## A target with no shields gives "hull" or "shield" by the hull damage and never "zone", with no error.
func _no_shields() -> void:
	var from := _foe.global_position + Vector2(400.0, 0.0)
	var shields_was := _foe.shields
	var armour_was := _foe.armour
	_foe.shields = null
	_foe.armour = null
	_foe.hull = _foe.hull_max
	_clear()
	var ret := world.combat.apply_damage(_foe, _hit_of(_me, 30.0, from))
	var via_combat := _only_kind()
	_clear()
	if _hm != null:
		(_hm as Object).call("on_hit", _foe, _hit_of(_me, 5.0, from), 0.0, false)
	var direct := _only_kind()
	_foe.shields = shields_was
	_foe.armour = armour_was
	_foe.hull = _foe.hull_max
	_check("a target with no shields: damage to the hull gives hull (never zone)", ret > 0.0 and via_combat == "hull", "hull %s, kind '%s'" % [str(ret), via_combat])
	_check("a target with no shields: no hull damage gives shield", direct == "shield", direct)
	_clear()


## A small craft's marker is at the pointer; anything bigger gets it at the struck side of its hit circle.
func _placement() -> void:
	var was_mouse: Variant = world.test_mouse
	var size_was := _foe.size_class
	var from := _foe.global_position + Vector2(3000.0, 0.0)
	var pointer_world := Vector2(1234.0, 567.0)
	world.test_mouse = pointer_world
	_foe.size_class = Rules.SIZE_SMALL
	_clear()
	if _hm != null:
		(_hm as Object).call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false)
	var m := _markers()
	var want_screen := get_viewport().get_canvas_transform() * pointer_world
	var at_pointer := m.size() == 1 and bool((m[0] as Dictionary)["screen"]) and ((m[0] as Dictionary)["pos"] as Vector2).distance_to(want_screen) < 0.01
	_check("a small craft's marker is at the pointer", at_pointer, str(m))
	_foe.size_class = Rules.SIZE_MEDIUM
	_clear()
	if _hm != null:
		(_hm as Object).call("on_hit", _foe, _hit_of(_me, 5.0, from), 5.0, false)
	var m2 := _markers()
	var want_world := _foe.global_position + Vector2(1.0, 0.0) * _foe.hit_radius()
	var at_side := m2.size() == 1 and not bool((m2[0] as Dictionary)["screen"]) and ((m2[0] as Dictionary)["pos"] as Vector2).distance_to(want_world) < 0.01
	_check("a hit on anything bigger is marked at the struck side of its hit circle", at_side, "%s, want %s" % [str(m2), str(want_world)])
	_foe.size_class = size_was
	world.test_mouse = was_mouse
	_clear()


## The flash table has a row for the hit markers (per event, a gap of 334 ms) and one for the edge wedges, each naming a script that exists.
func _table() -> void:
	var hit_ok := false
	var wedge_ok := false
	var files_ok := true
	for r: Dictionary in FlashTable.ROWS:
		if not ResourceLoader.exists("res://" + String(r["file"])):
			files_ok = false
		if String(r["file"]) == "scripts/ui/hit_markers.gd" and String(r["kind"]) == "hit" and str(r["rate"]) == "per event" and int(r["min_gap_ms"]) == 334 and not bool(r["today"]) and String(r["since"]) == "S7A":
			hit_ok = true
		if String(r["file"]) == "scripts/ui/hud_alarm.gd" and String(r["kind"]) == "slide" and not bool(r["today"]) and String(r["since"]) == "S7A":
			wedge_ok = true
	_check("the flash table has the hit markers row (per event, 334 ms) and every row names a script that exists", hit_ok and files_ok)
	_check("the flash table has the edge wedges row (a slide) and every row names a script that exists", wedge_ok and files_ok)
