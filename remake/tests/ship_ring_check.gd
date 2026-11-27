extends Node
## WHAT THIS IS: the check of the pilot's ship ring and target card: the ring round the human's own ship (shield brackets, the hull
## and route chin, the torpedo warning), the pause menu's "Ring and card" view, the target card and the readable shots. All of them are
## drawing and sound only: the check also proves none of them changes a field of the match.
##
## HOW IT WORKS: it waits until the human pilot's ship is flying, centres the camera on it, pauses the match (so nothing moves between
## two frames) and runs the parts one after another with real units, shots and the real HUD. Game's ring and card fields are set
## directly (never through a choose_ function, which would write the settings file) and put back. Parts:
##   1. the ring: it draws once with no script error and writes no field of the ship; it draws nothing for another ship, a dead or docked
##      human or a spectator; each preset draws exactly its parts and a single switched-off part is missing; a broken zone shows its caps
##      for one second of match time and its recovery arc; a quiet Full frame is at most 14 drawing commands;
##   2. the torpedo warning: one inbound torpedo on a crossing path gives one mark whose time is the distance over the closing speed;
##      a miss, a dud on arrival, a friendly, a torpedo flying away and one the team cannot see give none; the arrowhead's tip is at
##      R + 4 + 18 x (t / 3) pixels; the danger sign comes with a mark in its last second, once however many there are; the pulse is
##      steady under reduced motion; the beep's gap and its minimum; the hit notch for an off-screen shooter and none for an on-screen
##      one; the worst frame is at most 26 drawing commands;
##   3. the target card: nothing for no target, an unseen or unseen-but-held target, a spectator; the frame and the strip for a seen one
##      (Full 12, Compact 6, Minimal 1 drawing commands); the square frame; the pips; a redraw only when a key changed; the zone flash and
##      its 0.334 s gate; one pool for a one-zone target; no field of the target or the ship written;
##   4. the readable shots: every streak at least as wide as its hit circle, hostile rounds drawn after friendly ones, a minion's round
##      dimmer, a round that is not live not drawn;
##   5. the pause menu: the Ring and card button is in the menu's third row, the parts view has the two preset buttons, nine switches
##      and Back, and Back returns to the menu;
## It ends with "ship_ring_check: N failures" (0 = all good) and quits; after 150 s of real time "ship_ring_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=ship_ring_check
##
## WHO USES IT: main.gd loads it for --test=ship_ring_check. It sets Game's ring and card fields in memory only and puts them back.

## The running match (set by setup()).
var world: World
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false
## The HUD (found when the check starts).
var _hud: Hud
## The human's ship.
var _ship: Ship
## The ring (a child of the HUD).
var _ring: ShipRing
## The slots of the torpedoes the check spawned (taken away again by _kill_all()).
var _slots: Array[int] = []
## How many "torp_warn" cues the ring sent while the check listened.
var _cue_count := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 150 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 150000:
		print("ship_ring_check: timeout")
		get_tree().quit()
		return
	if get_tree().root.find_child("Hud", true, false) == null or world.camera == null:
		return
	if world.camera.followed() == null:
		return
	_started = true
	_run()


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(3)
	_hud = get_tree().root.find_child("Hud", true, false)
	_ship = world.camera.followed()
	for c in _hud.get_children():
		if c is ShipRing:
			_ring = c
	_expect(_ring != null, "the HUD has the ship ring")
	if _ring == null:
		print("ship_ring_check: %d failures" % failures)
		get_tree().quit()
		return
	var was_preset := Game.ring_preset
	var was_card := Game.card_preset
	var was_off := Game.ring_parts_off
	var was_mouse: Variant = world.test_mouse
	Game.ring_preset = ShipRingParts.PRESET_FULL
	Game.card_preset = 0
	Game.ring_parts_off = PackedStringArray()
	await _park()
	get_tree().paused = true
	await _frames(3)
	await _ring_part()
	await _warning_part()
	await _card_part()
	await _shots_part()
	await _menu_part()
	get_tree().paused = false
	world.camera.set_process(true)
	Game.ring_preset = was_preset
	Game.card_preset = was_card
	Game.ring_parts_off = was_off
	world.test_mouse = was_mouse
	print("ship_ring_check: %d failures" % failures)
	get_tree().quit()


## Centre the camera on the human's ship and keep it there.
func _park() -> void:
	var cam := world.camera
	cam.free = true
	cam.centre_latched = false
	cam.global_position = _ship.global_position
	cam._free_pos = _ship.global_position
	# A headless window's mouse sits at the screen corner, where the free camera would drift to: switch its own work off and place it by hand.
	cam.set_process(false)
	await _frames(3)


## Part 1: the ring.
func _ring_part() -> void:
	var sh := _ship.shields
	var was_mode := _ship.energy.mode
	_ship.energy.mode = Rules.ENERGY_BALANCED
	await _frames(2)
	# It draws, with no script error (the run's scan), and writes nothing: no field of the ship changes over several drawn frames.
	var before := _fields(_ship)
	for i in 4:
		_ring.queue_redraw()
		await _frames(1)
	var after := _fields(_ship)
	_expect(_ring.visible and _ring.drawn > 0 and before == after, "the ring draws and changes no field of the ship (%d fields, %d drawing commands)" % [before.size(), _ring.drawn])
	# A quiet Full frame: four brackets, the chin's track and its hull fill, no route triangle at Balanced: six commands, at most 14.
	_expect(_ring.drawn == 6 and _ring.drawn <= 14, "a quiet Full frame is six drawing commands, at most 14 (%d)" % _ring.drawn)
	# The route triangle is one more command for each of Weapons, Shields and Engines, none for Balanced.
	for mode: int in [Rules.ENERGY_WEAPONS, Rules.ENERGY_SHIELDS, Rules.ENERGY_THRUSTERS]:
		_ship.energy.mode = mode
		await _frames(2)
		_expect(_ring.drawn == 7, "the route triangle (%s) is one more drawing command (%d)" % [Rules.ENERGY_NAMES[mode], _ring.drawn])
	_ship.energy.mode = Rules.ENERGY_WEAPONS
	# Each preset draws exactly its parts: Full 4 + 2 + 1, Compact 4 + 2, Minimal 4.
	var want := {ShipRingParts.PRESET_FULL: 7, ShipRingParts.PRESET_COMPACT: 6, ShipRingParts.PRESET_MINIMAL: 4}
	for p: int in want:
		Game.ring_preset = p
		await _frames(2)
		_expect(_ring.drawn == int(want[p]), "%s draws exactly its parts, %d drawing commands (%d)" % [ShipRingParts.preset_name(p), int(want[p]), _ring.drawn])
	Game.ring_preset = ShipRingParts.PRESET_FULL
	# A single switched-off part is missing.
	var cost := {"shield_arcs": 4, "hull_arc": 2, "route_triangle": 1}
	for part: String in cost:
		Game.ring_parts_off = PackedStringArray([part])
		await _frames(2)
		_expect(_ring.drawn == 7 - int(cost[part]), "with %s switched off %d drawing commands are missing (%d left)" % [part, int(cost[part]), _ring.drawn])
	Game.ring_parts_off = PackedStringArray()
	_ship.energy.mode = Rules.ENERGY_BALANCED
	# A broken zone: a thin track, the regrowth and the caps for one second of match time.
	var saved_values := sh.values.duplicate()
	var saved_flash := sh.flash.duplicate()
	var saved_since := sh.since_hit
	var t0 := world.time
	sh.values[0] = 0.0
	sh.flash[0] = 0.4
	sh.since_hit = 0.0
	await _frames(2)
	_expect(is_equal_approx(_ring._broke_at[0], t0) and _ring.drawn == 7, "a zone that just broke: three brackets, its track, its caps and the chin (%d, broke at %.2f)" % [_ring.drawn, _ring._broke_at[0]])
	sh.since_hit = sh.delay * 0.5
	await _frames(2)
	_expect(_ring.drawn == 8, "half way through the refill wait the zone's arc grows back from its middle (%d)" % _ring.drawn)
	world.time = t0 + 1.1
	await _frames(2)
	_expect(_ring.drawn == 7, "the caps are gone after one second of match time (%d)" % _ring.drawn)
	world.time = t0 + 0.9
	await _frames(2)
	_expect(_ring.drawn == 8, "and still there at 0.9 s (%d)" % _ring.drawn)
	world.time = t0
	sh.values = saved_values
	sh.flash = saved_flash
	sh.since_hit = saved_since
	sh.flash[0] = 0.0
	await _frames(2)
	_ring._broke_at[0] = -99.0
	await _frames(2)
	_expect(_ring.drawn == 6, "with the zone back the ring is the quiet six again (%d)" % _ring.drawn)
	# A ship with no zones (one pool) draws no brackets.
	var was_single := sh.single
	sh.single = true
	await _frames(2)
	_expect(_ring.drawn == 2, "a ship with one shield pool draws no brackets (%d)" % _ring.drawn)
	sh.single = was_single
	# Nothing for a dead ship, a docked human or a spectator; nothing in mode 3.
	# (Each case is put back before the next frame, so nothing else in the HUD ever sees it: the ring's own frame step is called by hand.)
	_ship.alive = false
	_ring._process(0.0)
	_expect(not _ring.visible and _ring.drawn == 0, "nothing for a dead ship")
	_ship.alive = true
	var me := world.human
	var was_state := me.state
	me.state = "docked"
	_ring._process(0.0)
	_expect(not _ring.visible and _ring.drawn == 0, "nothing for a docked human")
	me.state = was_state
	world.human = null
	_ring._process(0.0)
	_expect(not _ring.visible and _ring.drawn == 0, "nothing in a spectator's seat")
	world.human = me
	world.view_open = true
	_ring._process(0.0)
	_expect(not _ring.visible and _ring.drawn == 0, "nothing while the command view is open over the flight")
	world.view_open = false
	await _frames(2)
	_expect(_ring.visible and _ring.drawn == 6, "and the ring is back after all that (%d)" % _ring.drawn)
	# Another ship never gets a ring: the ring is the human's own, and the ship it draws for is the human's.
	var other: Ship = null
	for s: Ship in world.ships:
		if s != _ship and s.alive:
			other = s
			break
	_expect(TargetKeys.my_ship(world) == _ship and (other == null or TargetKeys.my_ship(world) != other), "the ring belongs to the human's own ship only")
	_ship.energy.mode = was_mode


## Part 2: the torpedo warning: the arrowheads, their place, the danger sign, the pulse, the hit notch and the beep.
func _warning_part() -> void:
	var proj := world.projectiles
	var enemy := _enemy_unit()
	var was_mode := _ship.energy.mode
	var was_reduced := Blink.reduced_motion
	var was_log := _ship.damage_log
	var at := _ship.global_position
	var hr := _ship.hit_radius()
	_ship.energy.mode = Rules.ENERGY_BALANCED
	Blink.reduced_motion = false
	_expect(enemy != null, "setup: an enemy unit is there to fire the torpedoes")
	# A direction with no rock between 1500 units out and the ship, and 800 units out in the team's sight.
	var dir := Vector2.ZERO
	for ang: float in [0.0, 90.0, 180.0, 270.0, 45.0, 135.0, 225.0, 315.0]:
		var d := Vector2.from_angle(deg_to_rad(ang))
		if world.asteroids.segment_hit(at + d * 1500.0, at, 8.0).is_empty() and world.vision.is_visible(world.human_team, at + d * 1500.0):
			dir = d
			break
	_expect(dir != Vector2.ZERO, "setup: a clear lane to the ship was found")
	if enemy == null or dir == Vector2.ZERO:
		_ship.energy.mode = was_mode
		return
	var side := dir.orthogonal()
	# One inbound torpedo on a crossing path: one mark, t = the distance to the hit circle over the closing speed worked by hand.
	var a := _torp(at + dir * 800.0, -dir * 400.0, 5.0, 0.0, enemy)
	var marks := _ring.marks_of(_ship)
	var want_t := (800.0 - hr) / 400.0
	_expect(marks.size() == 1 and absf(float(marks[0]["t"]) - want_t) < 0.1, "one inbound torpedo on a crossing path gives one mark, t %.2f s (by hand %.2f s)" % [float(marks[0]["t"]) if marks.size() > 0 else -1.0, want_t])
	_expect(marks.size() == 1 and absf(angle_difference(float(marks[0]["bearing"]), dir.angle())) < 0.01, "the mark is on the bearing to the torpedo")
	_kill_all()
	# A torpedo on a missing path, a dud on arrival, a friendly one: no mark.
	_torp(at + dir * 800.0 + side * 400.0, -dir * 400.0, 5.0, 0.0, enemy)
	_expect(_ring.marks_of(_ship).is_empty(), "a torpedo on a path that misses gives no mark")
	_kill_all()
	_torp(at + dir * 800.0, -dir * 400.0, 5.0, 2000.0, enemy)
	_expect(_ring.marks_of(_ship).is_empty(), "a torpedo that is still a dud when it arrives gives no mark")
	_kill_all()
	_torp(at + dir * 800.0, -dir * 400.0, 5.0, 0.0, _ship)
	_expect(_ring.marks_of(_ship).is_empty(), "a friendly torpedo gives no mark")
	_kill_all()
	_torp(at + dir * 800.0, dir * 400.0, 5.0, 0.0, enemy)
	_expect(_ring.marks_of(_ship).is_empty(), "a torpedo flying away gives no mark")
	_kill_all()
	# One the team cannot see: a far place in the fog with a clear lane to the ship.
	var far := _unseen_lane(at)
	if far != Vector2.ZERO:
		_torp(far, (at - far).normalized() * 900.0, far.distance_to(at) / 900.0 * 1.2, 0.0, enemy)
		_expect(_ring.marks_of(_ship).is_empty(), "a torpedo the team cannot see gives no mark")
		_kill_all()
	else:
		_expect(true, "(no unseen place with a clear lane was found: the fog case is skipped)")
	# The arrowhead tip is R + 4 + 18 x (t / 3) pixels from the ship's middle.
	var r := TurnCues.ring_px(_ring.ring_world(_ship, world.camera.zoom.x), world.camera.zoom.x)
	var tip_ok := true
	for t: float in [0.0, 0.7, 1.5, 3.0, 5.0]:
		tip_ok = tip_ok and is_equal_approx(ShipRing.arrow_tip_px(r, t), r + 4.0 + 18.0 * (minf(t, 3.0) / 3.0))
	_expect(tip_ok, "the arrowhead's tip is at R + 4 + 18 x (t / 3) pixels, 3 seconds out and beyond being the far end")
	# The drawing: an early mark has no danger sign, one in its last second has it, once however many marks there are.
	await _frames(2)
	var base := _ring.drawn
	a = _torp(at + dir * 800.0, -dir * 400.0, 5.0, 0.0, enemy)
	await _frames(2)
	var early := _ring.drawn
	_expect(_ring.marks.size() == 1 and early == base + 2, "an early mark is one arrowhead and the number, no danger sign (%d, %d without)" % [early, base])
	_kill_all()
	await _frames(2)
	var near := _torp(at + dir * (hr + 200.0), -dir * 400.0, 5.0, 0.0, enemy)
	await _frames(2)
	var late := _ring.drawn
	_expect(_ring.marks.size() == 1 and float(_ring.marks[0]["t"]) < 1.0 and late == base + 2 + 4, "a mark in its last second carries the danger sign, four commands more (%d)" % late)
	a = _torp(at + dir * 800.0, -dir * 400.0, 5.0, 0.0, enemy)
	var near2 := _torp(at + dir * (hr + 120.0), -dir * 400.0, 5.0, 0.0, enemy)
	await _frames(2)
	_expect(_ring.marks.size() == 3 and _ring.drawn == base + 3 + 4 + 1, "three marks and two of them in the last second draw the danger sign once (%d)" % _ring.drawn)
	_expect(near2 > 0 and a >= 0 and near >= 0 and float(_ring.marks[0]["t"]) <= float(_ring.marks[1]["t"]), "the nearest mark is first")
	# The preset: Compact shows the arrowheads but no number; Minimal too.
	Game.ring_preset = ShipRingParts.PRESET_COMPACT
	await _frames(2)
	_expect(_ring.drawn == 4 + 2 + 3 + 4, "Compact draws the arrowheads and the sign but no number (%d)" % _ring.drawn)
	Game.ring_preset = ShipRingParts.PRESET_FULL
	_kill_all()
	# The pulse: steady under reduced motion; otherwise the nearest one moves between 0.6 and 1.
	Blink.reduced_motion = true
	var steady := true
	for i in 12:
		steady = steady and ShipRing.danger_alpha(float(i) * 0.09, true) == 1.0
	Blink.reduced_motion = false
	var lo := 9.0
	var hi := -9.0
	for i in 40:
		var v := ShipRing.danger_alpha(float(i) * 0.025, true)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_expect(steady and lo >= 0.6 - 0.0001 and hi <= 1.0 + 0.0001 and hi - lo > 0.3 and ShipRing.danger_alpha(0.2, false) == 1.0, "the nearest mark pulses between 0.6 and 1 (%.2f to %.2f) and is steady under reduced motion" % [lo, hi])
	Blink.reduced_motion = was_reduced
	# The beep: pace by the nearest mark's time, never under the minimum; the cue's gap is in Sfx.
	var pace_ok := ShipRing.PACE_MIN >= 0.34 and is_equal_approx(ShipRing.pace(3.0), 1.0) and is_equal_approx(ShipRing.pace(0.5), 0.34) and is_equal_approx(ShipRing.pace(0.0), 0.34)
	var last := 0.0
	for i in 61:
		var p := ShipRing.pace(float(i) * 0.05)
		pace_ok = pace_ok and p >= ShipRing.PACE_MIN and p >= last - 0.0001
		last = p
	_expect(pace_ok, "the beep's gap runs from 1.0 s (3 s out) to 0.34 s (half a second out) and is never under PACE_MIN")
	_expect(float(Sfx.MIN_GAP["torp_warn"]) >= 0.34, "the torp_warn cue has a minimum gap of 0.34 s or more")
	await _frames(3)
	_cue_count = 0
	Events.cue.connect(_on_cue)
	var t0 := world.time
	_torp(at + dir * (hr + 200.0), -dir * 400.0, 5.0, 0.0, enemy)
	await _frames(3)
	_expect(_cue_count == 1, "the first arrowhead sounds one beep at once (%d)" % _cue_count)
	world.time = t0 + 0.2
	await _frames(2)
	_expect(_cue_count == 1, "no second beep before the gap is over (%d)" % _cue_count)
	world.time = t0 + 0.4
	await _frames(2)
	_expect(_cue_count == 2, "the second beep comes after 0.34 s of match time when the torpedo is close (%d)" % _cue_count)
	Game.ring_parts_off = PackedStringArray(["warning_marks"])
	world.time = t0 + 2.0
	await _frames(3)
	_expect(_cue_count == 2 and _ring.marks.is_empty(), "with the torpedo warning switched off there are no marks and no beep")
	Game.ring_parts_off = PackedStringArray()
	Events.cue.disconnect(_on_cue)
	world.time = t0
	_kill_all()
	await _frames(2)
	# The hit notch: a hit from a shooter off the screen gives a notch for one second; one from a shooter on the screen gives none.
	var enemy_at := enemy.global_position
	_ship.damage_log = {enemy.uid: [5.0, world.time, null]}
	await _frames(2)
	_expect(_ring.drawn == base + 1 and is_equal_approx(_ring._notch_at, world.time), "a hit from an off-screen shooter draws the notch (%d, base %d)" % [_ring.drawn, base])
	world.time = t0 + 1.05
	await _frames(2)
	_expect(_ring.drawn == base, "the notch is gone after one second of match time (%d)" % _ring.drawn)
	world.time = t0
	_ring._notch_at = -99.0
	enemy.global_position = at + dir * 150.0
	_ship.damage_log = {enemy.uid: [9.0, world.time + 0.5, null]}
	await _frames(2)
	_expect(_ring.drawn == base and _ring._notch_at < 0.0, "a hit from a shooter on the screen gives no notch (%d; ring size %s, shooter at %s, notch at %.2f, time %.2f)" % [_ring.drawn, str(_ring.size), str(get_viewport().get_canvas_transform() * enemy.global_position), _ring._notch_at, world.time])
	enemy.global_position = enemy_at
	_ship.damage_log = was_log
	# The worst frame: four marks (one in the last second), Full, a broken zone, the route triangle, a notch: at most 26 commands.
	var sh := _ship.shields
	var saved_values := sh.values.duplicate()
	var saved_flash := sh.flash.duplicate()
	var saved_since := sh.since_hit
	_ship.energy.mode = Rules.ENERGY_WEAPONS
	sh.values[0] = 0.0
	sh.flash[0] = 0.4
	sh.since_hit = sh.delay * 0.5
	_torp(at + dir * 800.0, -dir * 400.0, 5.0, 0.0, enemy)
	_torp(at + dir * 1100.0, -dir * 400.0, 5.0, 0.0, enemy)
	_torp(at + dir * 1400.0, -dir * 400.0, 5.0, 0.0, enemy)
	_torp(at + dir * (hr + 150.0), -dir * 400.0, 5.0, 0.0, enemy)
	_ring._notch_at = -99.0
	_ship.damage_log = {enemy.uid: [5.0, world.time + 1.0, null]}
	enemy.global_position = at + dir * 20000.0
	await _frames(2)
	_expect(_ring.marks.size() == 4 and _ring.drawn == 19 and _ring.drawn <= 26, "the worst frame is 19 drawing commands, at most 26 (%d marks, %d)" % [_ring.marks.size(), _ring.drawn])
	enemy.global_position = enemy_at
	_ship.damage_log = was_log
	sh.values = saved_values
	sh.flash = saved_flash
	sh.since_hit = saved_since
	sh.flash[0] = 0.0
	_kill_all()
	_ship.energy.mode = was_mode
	world.time = t0
	await _frames(2)


## Part 3: the target card.
func _card_part() -> void:
	var card: TargetCard = null
	for c in _hud.get_children():
		if c is TargetCard:
			card = c
	_expect(card != null, "the HUD has the target card")
	if card == null:
		return
	var other := Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON
	var bit := 1 << world.human_team
	# The target of the card cases: an enemy ship with a four-zone shield when one is flying (none is in the first moments of a match),
	# else the human's own ship (the card does not care whose it is).
	var foe: Ship = _ship
	for s: Ship in world.ships:
		if s.team == other and s.alive and s.shields != null and not s.shields.single and s.shields.max_total > 0.0:
			foe = s
			break
	_expect(foe.shields != null and not foe.shields.single and foe.shields.max_total > 0.0, "setup: the target has a four-zone shield (%s)" % ("an enemy ship" if foe != _ship else "the human's own ship"))
	var sil_ok := true
	for team: int in [Rules.HALCYON, Rules.CINDER]:
		var pts := TargetCard.silhouette("fighter", team)
		var lo := 9999.0
		var hi := -9999.0
		for pt in pts:
			lo = minf(lo, pt.x)
			hi = maxf(hi, pt.x)
		sil_ok = sil_ok and pts.size() >= 3 and absf((hi - lo) - TargetCard.SIL_PX) < 0.01
	_expect(sil_ok, "the strip's outline of a fighter, for both teams' looks, is %d pixels long" % int(TargetCard.SIL_PX))
	var pool: Unit = null
	for i in world.units.size():
		var o: Variant = world.units[i]
		if o != null and is_instance_valid(o) and (o as Unit).alive and (o as Unit).team == other and (o as Unit).shields != null and (o as Unit).shields.single and (o as Unit).shields.max_total > 0.0:
			pool = o as Unit
			break
	var was_mask := foe.visible_mask if foe != null else 0
	var was_target := _ship.controls.target_id
	var was_preset := Game.card_preset
	var was_mouse: Variant = world.test_mouse
	Game.card_preset = 0
	# No target: nothing.
	_ship.controls.target_id = -1
	await _frames(2)
	_expect(card.drawn == 0 and not card._frame.visible and not card._strip.visible, "with no target the card draws nothing")
	if foe == null:
		return
	# A seen target: the frame and the strip. Full is 12 drawing commands (the frame 6, the strip 6), at most 13.
	foe.visible_mask |= bit
	_ship.controls.target_id = foe.uid
	await _frames(3)
	_expect(card._frame.visible and card._strip.visible and card.drawn == 12 and card.drawn <= 13, "a seen target gets the frame and the strip: Full is %d drawing commands, at most 13" % card.drawn)
	Game.card_preset = 1
	await _frames(3)
	_expect(card._frame.visible and not card._strip.visible and card.drawn == 6 and card.drawn <= 6, "Compact is the frame alone, %d drawing commands, at most 6" % card.drawn)
	Game.card_preset = 2
	await _frames(3)
	_expect(card._frame.visible and card.drawn == 1, "Minimal is the bare frame, %d drawing command" % card.drawn)
	Game.card_preset = 0
	await _frames(3)
	# The frame is a square of 1.7 x the drawn length, 34 to 120 pixels, and its sides are the four zones.
	var half := card._side * 0.5
	var square := true
	for k in 4:
		var s := TargetCard.side_of(k, half)
		var mid: Vector2 = s[0]
		square = square and is_equal_approx(mid.length(), half) and is_equal_approx(TargetCard._half_len(k, half), half)
		square = square and is_equal_approx(angle_difference(mid.angle(), float(ShieldArcs.CENTERS[k])), 0.0)
	_expect(square and card._side >= 34.0 and card._side <= 120.0 and card._side == roundf(card._side), "the frame is a square, %d pixels a side, each side facing its zone" % int(card._side))
	_expect(absf(TargetCard.front_half_angle() - PI * 0.25) < 0.01, "the zone spans are read from ShieldZones: the front zone is 45 degrees each side of the nose")
	# The pips: 1 to 4 squares for the four ship sizes, one bar for a structure or a mothership.
	_expect(TargetCard.pip_count(Rules.SIZE_SMALL) == 1 and TargetCard.pip_count(Rules.SIZE_MEDIUM) == 2 and TargetCard.pip_count(Rules.SIZE_LARGE) == 3 and TargetCard.pip_count(Rules.SIZE_CAPITAL) == 4 and TargetCard.pip_count(Rules.SIZE_STRUCTURE) == 1 and TargetCard.pip_count(Rules.SIZE_MOTHERSHIP) == 1, "1 to 4 pips for the four ship sizes and one bar for structures")
	# A redraw only when the key changed: process a still target twice, the draw counter does not move; a change of a fill moves it.
	var redraws0 := card.redraws
	card._process(0.0)
	card._process(0.0)
	await _frames(2)
	_expect(card.redraws == redraws0, "a still target is not drawn again (%d redraws)" % (card.redraws - redraws0))
	var sh := foe.shields
	var saved_values := sh.values.duplicate()
	var saved_flash := sh.flash.duplicate()
	sh.values[1] = sh.values[1] * 0.5
	await _frames(2)
	_expect(card.redraws == redraws0 + 1, "a zone that lost half its shield redraws the frame once (%d)" % (card.redraws - redraws0))
	sh.values[1] = sh.values[1] + 0.001
	await _frames(2)
	_expect(card.redraws == redraws0 + 1, "a change of less than a 64th does not redraw (%d)" % (card.redraws - redraws0))
	sh.values = saved_values
	await _frames(2)
	# The card changes no field of the target or of the ship while it draws.
	var foe_before := _fields(foe)
	var ship_before := _fields(_ship)
	for i in 3:
		card._frame.queue_redraw()
		card._strip.queue_redraw()
		await _frames(1)
	_expect(foe_before == _fields(foe) and ship_before == _fields(_ship), "drawing the card changes no field of the target or the ship (%d + %d fields)" % [foe_before.size(), ship_before.size()])
	# The flash: a break starts one flash; a second break 0.2 s later is not drawn; one 0.5 s later is.
	var t0 := world.time
	var f0 := card.flashes
	sh.flash[0] = 0.4
	card._process(0.0)
	sh.flash[0] = 0.0
	card._process(0.0)
	world.time = t0 + 0.2
	sh.flash[1] = 0.4
	card._process(0.0)
	sh.flash[1] = 0.0
	card._process(0.0)
	_expect(card.flashes == f0 + 1, "two breaks 0.2 s apart give one flash (%d)" % (card.flashes - f0))
	world.time = t0 + 0.5
	sh.flash[2] = 0.4
	card._process(0.0)
	_expect(card.flashes == f0 + 2, "a break 0.5 s after the last flash gives another (%d)" % (card.flashes - f0))
	sh.flash[2] = 0.0
	card._process(0.0)
	_expect(is_equal_approx(card._levels[0], 0.0) and card._levels[2] > 0.5, "the flash is strong at its start and has faded on the first zone")
	world.time = t0
	sh.flash = saved_flash
	card._flash_at = [-99.0, -99.0, -99.0, -99.0]
	await _frames(2)
	# Held but unseen: nothing at all, and the card never reads the target's values then.
	var unit := _enemy_unit()
	var unit_mask := unit.visible_mask
	unit.visible_mask &= ~bit
	_ship.controls.target_id = unit.uid
	await _frames(2)
	_expect(not unit.visible_to(world.human_team) and card.drawn == 0 and not card._frame.visible and not card._strip.visible, "a held target that the team cannot see gets nothing drawn, not even an empty frame")
	unit.visible_mask |= bit
	await _frames(3)
	_expect(unit.visible_to(world.human_team) and card.drawn > 0 and card._frame.visible, "and the card is back when the target is seen again (%d drawing commands)" % card.drawn)
	unit.visible_mask = unit_mask
	_ship.controls.target_id = foe.uid
	await _frames(3)
	# Nothing for a spectator's seat, a dead or docked human, or the command view over the flight.
	var me := world.human
	world.human = null
	card._process(0.0)
	_expect(card.drawn == 0 and not card._frame.visible, "nothing in a spectator's seat")
	world.human = me
	world.view_open = true
	card._process(0.0)
	_expect(card.drawn == 0 and not card._frame.visible, "nothing while the command view is open over the flight")
	world.view_open = false
	await _frames(2)
	# A target with one shield pool shows its four sides as one pool.
	if pool != null:
		var pool_mask := pool.visible_mask
		pool.visible_mask |= bit
		var pool_values := pool.shields.values.duplicate()
		pool.shields.values[0] = pool.shields.max_total * 0.5
		_ship.controls.target_id = pool.uid
		await _frames(3)
		var same := true
		for k in 4:
			same = same and absf(float(card._fills[k]) - 0.5) < 0.02
		_expect(same and card.drawn > 0, "a target with one shield pool draws its four sides as one pool at the pool's fill (%.2f)" % float(card._fills[0]))
		pool.shields.values = pool_values
		pool.visible_mask = pool_mask
	else:
		_expect(true, "(no enemy unit with a single shield pool: the one-pool case is skipped)")
	# The card never uses the danger colour: no script of the card or the ring names it, except the ring with its sign.
	var code := ""
	for line in FileAccess.get_file_as_string("res://scripts/ui/target_card.gd").split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	_expect(not code.contains("DANGER") and not code.contains("Glyphs"), "the card never uses the danger colour or its sign")
	foe.visible_mask = was_mask
	_ship.controls.target_id = was_target
	Game.card_preset = was_preset
	world.test_mouse = was_mouse
	await _frames(2)


## Part 4: the readable shots: every streak at least as wide as its hit circle, hostile rounds drawn after friendly ones, a minion's round
## dimmer, and a round that is no longer live not drawn.
func _shots_part() -> void:
	var proj := world.projectiles
	var enemy := _enemy_unit()
	var px := 1.0 / maxf(0.02, world.camera.zoom.x)
	var at := _ship.global_position
	# A bolt, a shell and a flak burst with a wide hit circle (40 units) are at least 80 units wide; with a tiny circle their own width stays.
	var wide := true
	for k: int in [Rules.W_BOLT, Rules.W_SHELL, Rules.W_FLAK, Rules.W_PD, Rules.W_ION]:
		wide = wide and ProjectilesDraw.streak_width(k, 40.0, px) >= 80.0
	_expect(wide, "a bolt, shell and flak line at a hit circle of radius 40 is at least the circle's width, 80 units")
	_expect(is_equal_approx(ProjectilesDraw.streak_width(Rules.W_SHELL, 0.5, px), 3.0 * px) and is_equal_approx(ProjectilesDraw.streak_width(Rules.W_FLAK, 0.5, px), 2.0 * px) and is_equal_approx(ProjectilesDraw.streak_width(Rules.W_BOLT, 0.5, px), 1.6 * px), "with a small hit circle a shell is still 3 pixels wide, flak 2 and a bolt 1.6")
	# The order: a hostile round fired first and a friendly round fired later: the friendly round is drawn first.
	var hostile_slot := _round(Rules.W_BOLT, 3.0, enemy, at + Vector2(300.0, 0.0), Vector2(100.0, 0.0))
	var friendly_slot := _round(Rules.W_BOLT, 3.0, _ship, at + Vector2(300.0, 50.0), Vector2(100.0, 0.0))
	var order := ProjectilesDraw.draw_order(proj)
	var hi := order.find(hostile_slot)
	var fi := order.find(friendly_slot)
	_expect(hi >= 0 and fi >= 0 and fi < hi, "a hostile round's draw comes after a friendly one's even though it was fired first (%d after %d)" % [hi, fi])
	var viewer := proj.viewer_team if proj.viewer_team >= 0 else Rules.HALCYON
	_expect(not ProjectilesDraw.is_hostile(viewer, proj.viewer_team) and ProjectilesDraw.is_hostile(1 - viewer, proj.viewer_team), "a round of the viewer's team is friendly and the other team's is hostile")
	# A minion's round is dimmer.
	proj.src_minion[hostile_slot] = 1
	_expect(ProjectilesDraw.round_alpha(int(proj.src_minion[hostile_slot])) < ProjectilesDraw.round_alpha(int(proj.src_minion[friendly_slot])) and is_equal_approx(ProjectilesDraw.round_alpha(1), 0.6), "a minion's round is drawn at 0.6 of its colour, a pilot's at full strength")
	proj.src_minion[hostile_slot] = 0
	# A dead slot draws nothing: a round that stops being dangerous this tick is not in the drawing order.
	proj._kill(hostile_slot)
	order = ProjectilesDraw.draw_order(proj)
	_expect(order.find(hostile_slot) < 0 and order.find(friendly_slot) >= 0, "a round that is no longer live is not drawn")
	_kill_all()
	await _frames(1)


## Spawn a round of weapon kind `kind` with hit circle `radius` for the check, fired by `src`. Returns its slot.
func _round(kind: int, radius: float, src: Unit, at: Vector2, vel: Vector2) -> int:
	var slot := world.projectiles.spawn(at, vel, 5.0, 1.0, kind, {"radius": radius}, src, null)
	_slots.append(slot)
	return slot

## Spawn a torpedo for the check: a round at `at` flying at `vel` for `life` seconds, arming after `arm` units, fired by `src`. Returns its slot.
func _torp(at: Vector2, vel: Vector2, life: float, arm: float, src: Unit) -> int:
	var slot := world.projectiles.spawn(at, vel, maxf(life, 5.0), 10.0, Rules.W_TORP, {"radius": 5.0, "arm": arm}, src, null)
	_slots.append(slot)
	return slot


## Take the check's torpedoes away again.
func _kill_all() -> void:
	var proj := world.projectiles
	for slot: int in _slots:
		if proj.live[slot] == 1:
			proj._kill(slot)
		var at := proj.active.find(slot)
		while at >= 0:
			proj.active.remove_at(at)
			at = proj.active.find(slot)
	_slots.clear()


## A live unit of the team other than the human's, far from the human's ship (the shooter of the check's torpedoes), or null.
func _enemy_unit() -> Unit:
	var other := Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON
	for i in world.units.size():
		var o: Variant = world.units[i]
		if o != null and is_instance_valid(o) and (o as Unit).alive and (o as Unit).team == other:
			return o as Unit
	return null


## A place the human's team cannot see, far from the ship, with no rock between it and the ship; Vector2.ZERO when none is found.
func _unseen_lane(at: Vector2) -> Vector2:
	for dist: float in [6000.0, 9000.0, 12000.0]:
		for ang: float in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
			var p := at + Vector2.from_angle(deg_to_rad(ang)) * dist
			if not world.vision.is_visible(world.human_team, p) and world.asteroids.segment_hit(p, at, 8.0).is_empty():
				return p
	return Vector2.ZERO


## The check counts the torpedo beeps (the cue the ring sends).
func _on_cue(cue: String, _pos: Vector2) -> void:
	if cue == "torp_warn":
		_cue_count += 1


## Part 5: the pause menu's ring and card view.
func _menu_part() -> void:
	_hud._toggle_pause_menu()
	await _frames(2)
	var menu: PauseMenu = _hud.pause_menu
	_expect(menu != null and menu.active and menu.current_view() == PauseMenu.VIEW_MENU, "setup: the pause menu is open on its buttons")
	var open_btn := _find_button(menu, "Ring and card")
	_expect(open_btn != null and open_btn.get_parent() == _find_button(menu, "How to play").get_parent(), "the menu's third button in the How to play row is Ring and card")
	menu.ask(PauseMenu.VIEW_PARTS)
	await _frames(2)
	_expect(menu.current_view() == PauseMenu.VIEW_PARTS, "ask(VIEW_PARTS) shows the parts view")
	_expect(menu._ring_button != null and menu._ring_button.text == "Ring: Full", "the parts view has the ring preset button (Ring: Full)")
	_expect(menu._card_button != null and menu._card_button.text == "Card: Full", "the parts view has the card preset button (Card: Full)")
	var switches_ok := menu._part_buttons.size() == 9
	for id in ShipRingParts.ids():
		switches_ok = switches_ok and menu._part_buttons.has(id) and (menu._part_buttons[id] as Button).text.begins_with("%s:" % _label_of(id))
	_expect(switches_ok, "the parts view has the nine switches, one for each part (%d)" % menu._part_buttons.size())
	var rows_ok := true
	var per_row := {}
	for id: String in menu._part_buttons:
		var row := (menu._part_buttons[id] as Button).get_parent()
		per_row[row] = int(per_row.get(row, 0)) + 1
	for row in per_row:
		rows_ok = rows_ok and int(per_row[row]) == 3
	_expect(rows_ok and per_row.size() == 3, "the nine switches stand in three rows of three")
	var back_btn := _find_button(menu, "Back")
	_expect(back_btn != null, "the parts view has a Back button")
	# A part the preset leaves out cannot be switched on here.
	Game.ring_preset = ShipRingParts.PRESET_MINIMAL
	menu.ask(PauseMenu.VIEW_PARTS)
	await _frames(2)
	_expect((menu._part_buttons["turn_arc"] as Button).disabled and not (menu._part_buttons["shield_arcs"] as Button).disabled, "a part the preset leaves out is greyed, the others are not")
	Game.ring_preset = ShipRingParts.PRESET_FULL
	menu.ask(PauseMenu.VIEW_PARTS)
	await _frames(1)
	menu.back()
	await _frames(2)
	_expect(menu.current_view() == PauseMenu.VIEW_MENU and menu.active, "Back returns to the menu view")
	menu.resume()
	get_tree().paused = true
	await _frames(2)


## The first Button under `node` whose text is `text`, or null.
func _find_button(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text == text:
			return c
		var inner := _find_button(c, text)
		if inner != null:
			return inner
	return null


## The pause menu's words for ring part `id`.
func _label_of(id: String) -> String:
	for p: Dictionary in ShipRingParts.PARTS:
		if String(p["id"]) == id:
			return String(p["label"])
	return id


## Every script variable of `n` as a Dictionary name -> value (a copy, to compare before and after).
func _fields(n: Object) -> Dictionary:
	var out := {}
	for p: Dictionary in n.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			var v: Variant = n.get(String(p["name"]))
			out[String(p["name"])] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## Count a PASS or FAIL line for the check `what`.
func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
