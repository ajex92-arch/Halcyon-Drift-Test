extends Node
## WHAT THIS IS: the check of the rule warnings: the one line on the death card that names the rule that mattered in the death
## (DeathRecap.rule_note() and the card's fifth Summary line), and the warning for an empty battery on the pilot's ship ring (the
## pulse, its own sign, its own beep and its row in the flash table). All of it only reads the match: the check also proves the ring
## writes no field of the ship.
##
## HOW IT WORKS: everything this build adds is reached without a typed name (a script's own function and constant lists, and the
## live objects' get(), set() and call()), so the check always parses and a missing piece shows as a failed case, never as a script
## error. It runs in this order:
##   1. the pure cases (part A): the rule line for synthetic hit totals and death facts, the order when several rules apply, the words,
##      and the sums of the new hit-log keys for old and new entries;
##   2. the ring cases (part C): with the match paused it empties and refills the human ship's battery and reads the ring's pulse, its
##      cue, its draw count, its gap and its colour;
##   3. the card cases (part B): it makes an enemy pilot, kills the human's ship with a full-pierce torpedo and a turret bolt, first
##      measures the card's room for a fifth line (case K1, a control that passes before the line exists), then reads the line for each
##      rule and checks that it sits inside the card;
##   4. the sound and the table (parts S and T, pure): the energy beep's pitch, its gap and the table row.
## Every ship field it writes (energy, overload, vent, aggro stamp, strain timer, match time, reduced motion) is put back.
## It ends with "rule_warn_check: N failures" (0 = all good) and quits; after 120 s of real time "rule_warn_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=rule_warn_check
##
## WHO USES IT: main.gd loads it for --test=rule_warn_check. It drives the HUD, the ring and the death card and kills the human's ship,
## which is all the match it changes.

## The running match (set by setup()).
var world: World
## The HUD (found when the check starts).
var hud: Hud
## The ring round the human's ship (a child of the HUD).
var _ring: ShipRing
## How many checks failed.
var failures := 0
## How many cases were skipped because a piece this build adds does not exist.
var skipped := 0
## True once the check has started (it runs once).
var _started := false
## The numbers the next made pilot gets (far above the real slots).
var _next_slot := 40
## How many "energy_empty" cues were heard while the check listened.
var _cues := 0
## The ring's pulse count when case E3 began (the later ring cases count from it).
var _pulses0 := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 120 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 120000:
		print("rule_warn_check: timeout")
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
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	world.minion_director.next_wave = INF
	# A windowless run's mouse sits in the screen corner, where the camera's edge pan would act: put it in the middle.
	Input.use_accumulated_input = false
	var park := InputEventMouseMotion.new()
	park.position = get_viewport().get_final_transform() * (get_viewport().get_visible_rect().size * 0.5)
	park.global_position = park.position
	Input.parse_input_event(park)
	await _frames(2)
	_part_a()
	await _part_c()
	await _part_b()
	_part_s()
	_finish()


## Part A: the rule line from synthetic hit totals and death facts (no ship needed), and the sums of the new hit-log keys.
func _part_a() -> void:
	var dr: Script = DeathRecap
	var consts := dr.get_script_constant_map()
	var have := _has(dr, "rule_note")
	var words: Dictionary = consts.get("RULE_WORDS", {})
	var f := float(consts.get("PIERCE_MIN_SHARE", -1.0))
	var i := float(consts.get("ION_MIN_SHARE", -1.0))
	var window := TurretData.AGGRO_WINDOW
	var ok := have and not words.is_empty() and f > 0.0 and i > 0.0
	var l := "note: a full pierce names the shield rule with the full words"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(1000.0, (f + 0.2) * 1000.0, (f + 0.2) * 1000.0, 0.0, 0.0, 0.0), {})
		_expect(String(r["rule"]) == "pierce" and String(r["text"]) == String(words.get("pierce_full", "?")), l, str(r))
	l = "note: a light pierce below the floor names no rule"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(1000.0, (f - 0.1) * 1000.0, 0.0, 0.0, 0.0, 0.0), {})
		_expect(String(r["rule"]) == "", l, str(r))
	l = "note: a part pierce above the floor uses the part words"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(1000.0, (f + 0.1) * 1000.0, 0.0, 0.0, 0.0, 0.0), {})
		_expect(String(r["rule"]) == "pierce" and String(r["text"]) == String(words.get("pierce_part", "?")), l, str(r))
	l = "note: an ion share above the floor names the ion rule"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(1000.0, 0.0, 0.0, (i + 0.2) * 1000.0, 0.0, 0.0), {})
		_expect(String(r["rule"]) == "ion" and String(r["text"]) == String(words.get("ion", "?")), l, str(r))
	l = "note: ion on a ship with no shield says it does nothing"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(1000.0, 0.0, 0.0, (i + 0.2) * 1000.0, (i + 0.2) * 1000.0, 0.0), {})
		_expect(String(r["rule"]) == "ion" and String(r["text"]) == String(words.get("ion_bare", "?")), l, str(r))
	l = "note: turret fire in the last aggro window after hurting a ship names the aggro rule"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(1000.0, 0.0, 0.0, 0.0, 0.0, 120.0), {"aggro_age": 1.0})
		_expect(String(r["rule"]) == "aggro" and String(r["text"]) == _fill(words, "aggro", 0), l, str(r))
	l = "note: no aggro rule when the last hurt was too long ago or no turret hit came late"
	if _need(ok, l, "rule_note and its constants"):
		var old := _note(dr, _sum(1000.0, 0.0, 0.0, 0.0, 0.0, 120.0), {"aggro_age": window + 5.0})
		var none := _note(dr, _sum(1000.0, 0.0, 0.0, 0.0, 0.0, 0.0), {"aggro_age": 1.0})
		_expect(String(old["rule"]) == "" and String(none["rule"]) == "", l, "%s %s" % [str(old), str(none)])
	l = "note: respawn strain names the rule with the seconds left"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(0.0, 0.0, 0.0, 0.0, 0.0, 0.0), {"strain_s": 12.2})
		var off := _note(dr, _sum(0.0, 0.0, 0.0, 0.0, 0.0, 0.0), {"strain_s": 0.0})
		var text := String(r["text"])
		var pct := str(roundi(Rules.STRAIN_WEAPON_MULT * 100.0))
		_expect(String(r["rule"]) == "strain" and text.contains("13") and text.contains(pct) and String(off["rule"]) == "", l, "%s %s" % [text, str(off)])
	l = "note: when several rules apply the order is pierce, ion, aggro, strain"
	if _need(ok and _has(dr, "RULE_ORDER"), l, "rule_note and RULE_ORDER"):
		var order: Array = consts.get("RULE_ORDER", [])
		var death := {"aggro_age": 1.0, "strain_s": 12.0}
		var got: Array = []
		var s := _sum(1000.0, 450.0, 450.0, 450.0, 0.0, 120.0)
		got.append(String(_note(dr, s, death)["rule"]))
		s["pierced"] = 0.0
		s["pierce_full"] = 0.0
		got.append(String(_note(dr, s, death)["rule"]))
		s["ion"] = 0.0
		got.append(String(_note(dr, s, death)["rule"]))
		s["late_defence"] = 0.0
		got.append(String(_note(dr, s, death)["rule"]))
		death["strain_s"] = 0.0
		got.append(String(_note(dr, s, death)["rule"]))
		_expect(order == ["pierce", "ion", "aggro", "strain"] and got == ["pierce", "ion", "aggro", "strain", ""], l, str(got))
	l = "note: no rule, no line"
	if _need(ok, l, "rule_note and its constants"):
		var r := _note(dr, _sum(0.0, 0.0, 0.0, 0.0, 0.0, 0.0), {})
		_expect(String(r["rule"]) == "" and String(r["text"]) == "", l, str(r))
	l = "note: the words hold the numbers of the rules and no code words"
	if _need(ok, l, "RULE_WORDS"):
		var bad := ""
		for id: Variant in words:
			var text := _fill(words, String(id), 9)
			if text.strip_edges() == "":
				bad += " empty:%s" % str(id)
			for w: String in ["_", "::", "res://", "null", "%d", "%s"]:
				if text.contains(w):
					bad += " %s in %s" % [w, str(id)]
		var strain := _fill(words, "strain", 9)
		var aggro := _fill(words, "aggro", 0)
		var figures := strain.contains(str(roundi(Rules.STRAIN_WEAPON_MULT * 100.0))) and strain.contains("9") and aggro.contains(str(int(window)))
		_expect(bad == "" and figures, l, bad)
	l = "note: the strain words say the shield does not refill and never say it stopped"
	if _need(not words.is_empty(), l, "RULE_WORDS"):
		var strain_words := String(words.get("strain", ""))
		_expect(strain_words.contains("does not refill") and not strain_words.contains("stopped"), l, strain_words)
	l = "note: an entry from before the new keys still sums"
	if _need(true, l, ""):
		var rec := DeathRecap.new()
		rec.world = world
		rec.frozen = false
		var enemy := 1 - world.human_team
		rec.entries = [{"t": world.time - 1.0, "uid": 1, "key": "old", "label": "Old", "kind": -1, "team": enemy, "pilot": false, "seen": true, "wkind": Rules.W_BOLT, "family": DeathRecap.F_GUNS, "amount": 777.0, "hull": 0.0, "zones": [777.0, 0.0, 0.0, 0.0]}]
		var s := rec.summary()
		var zero := true
		for k: String in ["pierced", "pierce_full", "ion_bare", "late_defence"]:
			zero = zero and s.has(k) and is_zero_approx(float(s.get(k, -1.0)))
		_expect(zero and is_equal_approx(float(s["total"]), 777.0), l, str(s.get("pierced", "no key")))
	l = "note: the summary sums the new keys"
	if _need(true, l, ""):
		var rec := DeathRecap.new()
		rec.world = world
		rec.frozen = false
		var enemy := 1 - world.human_team
		var t := world.time - 1.0
		rec.entries = [
			{"t": t, "uid": 1, "key": "t:1", "label": "T", "kind": Unit.K_TURRET, "team": enemy, "pilot": false, "seen": true, "wkind": Rules.W_BOLT, "family": DeathRecap.F_GUNS, "amount": 350.0, "hull": 0.0, "zones": [350.0, 0.0, 0.0, 0.0], "pierced": 300.0, "full": 300.0, "bare": 0.0},
			{"t": t, "uid": 2, "key": "c:1", "label": "S", "kind": Unit.K_SHIP, "team": enemy, "pilot": false, "seen": true, "wkind": Rules.W_ION, "family": DeathRecap.F_ION, "amount": 200.0, "hull": 0.0, "zones": [200.0, 0.0, 0.0, 0.0], "pierced": 200.0, "full": 0.0, "bare": 40.0},
		]
		var s := rec.summary()
		var got := "%s %s %s %s" % [str(s.get("pierced", "-")), str(s.get("pierce_full", "-")), str(s.get("ion_bare", "-")), str(s.get("late_defence", "-"))]
		_expect(is_equal_approx(float(s.get("pierced", -1.0)), 500.0) and is_equal_approx(float(s.get("pierce_full", -1.0)), 300.0) and is_equal_approx(float(s.get("ion_bare", -1.0)), 40.0) and is_equal_approx(float(s.get("late_defence", -1.0)), 350.0), l, got)


## Part C: the ring's warning for an empty battery, in the paused match with the camera parked on the human's ship.
func _part_c() -> void:
	var cam := world.camera
	var ship := cam.followed() as Ship
	for c in hud.get_children():
		if c is ShipRing:
			_ring = c
	_expect(_ring != null and ship != null, "setup: the HUD has the ship ring and the human's ship flies")
	if _ring == null or ship == null:
		return
	var sr: Script = ShipRing
	var consts := sr.get_script_constant_map()
	var was_free := cam.free
	var was_latched := cam.centre_latched
	var was_value := ship.energy.value
	var was_overload := ship.overload_left
	var was_vent := ship.venting
	var was_reduced := Blink.reduced_motion
	var was_time := world.time
	cam.free = true
	cam.centre_latched = false
	cam.global_position = ship.global_position
	cam._free_pos = ship.global_position
	# A headless window's mouse sits at the screen corner, where the free camera would drift to: switch its own work off.
	cam.set_process(false)
	await _frames(3)
	get_tree().paused = true
	ship.overload_left = 0.0
	ship.venting = false
	ship.energy.value = ship.energy.max_value
	await _frames(3)
	var spends := false
	for m: WeaponMount in ship.mounts:
		spends = spends or float(m.def.get("energy", 0.0)) > 0.0
	_expect(spends, "setup: the human's ship has a gun that spends energy")
	var gap := float(consts.get("ENERGY_GAP", 1.0))
	# E1.
	var l := "ring: energy_empty is true below the cheapest gun's shot and false with a full battery"
	var have := _has(sr, "energy_empty")
	if _need(have, l, "ShipRing.energy_empty"):
		ship.energy.value = 0.0
		var empty: Variant = sr.call("energy_empty", ship)
		ship.energy.value = ship.energy.max_value
		var full: Variant = sr.call("energy_empty", ship)
		_expect(empty == true and full == false, l, "%s %s" % [str(empty), str(full)])
	# E2.
	l = "ring: not empty while overloaded or venting"
	if _need(have, l, "ShipRing.energy_empty"):
		ship.energy.value = 0.0
		ship.overload_left = 3.0
		var a: Variant = sr.call("energy_empty", ship)
		ship.overload_left = 0.0
		ship.venting = true
		var b: Variant = sr.call("energy_empty", ship)
		ship.venting = false
		ship.energy.value = ship.energy.max_value
		_expect(a == false and b == false, l, "%s %s" % [str(a), str(b)])
	# E3 (and E8, the fields of the ship before and after).
	ship.energy.value = ship.energy.max_value
	await _frames(3)
	_pulses0 = _geti(_ring, "energy_pulses")
	_cues = 0
	Events.cue.connect(_on_cue)
	var before := _fields(ship)
	ship.energy.value = 0.0
	await _frames(3)
	var pulses1 := _geti(_ring, "energy_pulses")
	var cues1 := _cues
	await _frames(3)
	var after := _fields(ship)
	l = "ring: an empty edge sends one energy_empty cue and starts one pulse"
	_expect(cues1 == 1 and _cues == 1 and pulses1 == _pulses0 + 1 and _geti(_ring, "energy_pulses") == _pulses0 + 1, l, "cues %d, then %d; pulses %d to %d" % [cues1, _cues, _pulses0, pulses1])
	l = "ring: the pulse writes no field of the ship"
	_expect(before == after, l)
	# E4.
	l = "ring: the pulse draws five more commands, the arc and the danger sign, and none when it ends"
	ship.energy.value = ship.energy.max_value
	_ring.set("_energy_pulse_ms", -1000000)
	await _frames(3)
	var quiet := _ring.drawn
	Blink.reduced_motion = true
	_ring.set("_energy_pulse_ms", Time.get_ticks_msec())
	await _frames(1)
	var lit := _ring.drawn
	_ring.set("_energy_pulse_ms", Time.get_ticks_msec() - 600)
	await _frames(1)
	var off := _ring.drawn
	Blink.reduced_motion = was_reduced
	_expect(lit == quiet + 5 and off == quiet, l, "quiet %d, lit %d, ended %d" % [quiet, lit, off])
	# E5.
	l = "ring: a second empty inside one second of match time gives no pulse and one after the gap does"
	ship.energy.value = ship.energy.max_value
	await _frames(3)
	ship.energy.value = 0.0
	await _frames(3)
	var same := _geti(_ring, "energy_pulses")
	world.time = was_time + gap + 0.1
	ship.energy.value = ship.energy.max_value
	await _frames(3)
	ship.energy.value = 0.0
	await _frames(3)
	var later := _geti(_ring, "energy_pulses")
	world.time = was_time
	ship.energy.value = ship.energy.max_value
	_expect(same == _pulses0 + 1 and later == _pulses0 + 2, l, "start %d, inside the gap %d, after it %d" % [_pulses0, same, later])
	Events.cue.disconnect(_on_cue)
	await _frames(2)
	# E6.
	l = "ring: reduced motion lights the pulse 480 ms, not 120"
	if _need(_has(sr, "energy_pulse_on"), l, "ShipRing.energy_pulse_on"):
		Blink.reduced_motion = false
		var p100: Variant = sr.call("energy_pulse_on", 0, 100)
		var p130: Variant = sr.call("energy_pulse_on", 0, 130)
		Blink.reduced_motion = true
		var p400: Variant = sr.call("energy_pulse_on", 0, 400)
		var p500: Variant = sr.call("energy_pulse_on", 0, 500)
		Blink.reduced_motion = was_reduced
		_expect(p100 == true and p130 == false and p400 == true and p500 == false, l, "%s %s %s %s" % [str(p100), str(p130), str(p400), str(p500)])
	# E7.
	l = "ring: the pulse colour is Palette.DANGER and its sign stands apart from the torpedo sign"
	if _need(_has(sr, "energy_colour") and _has(sr, "ENERGY_SIGN_DEG"), l, "ShipRing.energy_colour and ENERGY_SIGN_DEG"):
		var col: Variant = sr.call("energy_colour")
		var diff := fposmod(absf(float(consts.get("ENERGY_SIGN_DEG", 0.0)) - ShipRing.SIGN_DEG), 360.0)
		if diff > 180.0:
			diff = 360.0 - diff
		_expect(col is Color and (col as Color) == Palette.DANGER and diff >= 45.0, l, "%s, %.0f degrees apart" % [str(col), diff])
	# Put everything back.
	ship.energy.value = was_value
	ship.overload_left = was_overload
	ship.venting = was_vent
	Blink.reduced_motion = was_reduced
	world.time = was_time
	get_tree().paused = false
	cam.set_process(true)
	cam.free = was_free
	cam.centre_latched = was_latched
	await _frames(2)


## Part B: the death card, with the human's ship killed by a full-pierce torpedo and a turret bolt.
func _part_b() -> void:
	var h := world.human
	var ship := h.ship
	var card := hud.death_card
	var recap := card.recap
	var enemy := 1 - world.human_team
	var killer := _spawn("Boreas", enemy, "lance")
	var mate := _spawn("Tester1", world.human_team, "fighter")
	var turret: Unit = null
	for t: Turret in world.turrets:
		if t.team == enemy and t.alive:
			turret = t
			break
	_expect(killer != null and mate != null and turret != null, "setup: the test pilots and an enemy turret exist")
	var shielded := ship != null and ship.shields != null and ship.shields.max_total > 0.0
	_expect(shielded, "setup: the human's ship has shields")
	if killer == null or mate == null or turret == null or not shielded:
		return
	# The hit logs hold real hits taken earlier, which would change the shares: start clean.
	ship.damage_log.clear()
	recap.entries.clear()
	turret.visible_mask |= 1 << world.human_team
	killer.visible_mask |= 1 << world.human_team
	var team: TeamState = world.teams[world.human_team]
	var was_aggro := ship.aggro_time
	var was_strain := team.strain_t
	ship.aggro_time = world.time - 1.0
	team.strain_t = 12.0
	var front := ship.global_position + Vector2.from_angle(ship.rotation) * 600.0
	var right := ship.global_position + Vector2.from_angle(ship.rotation + PI * 0.5) * 600.0
	_hit_p(ship, killer, Rules.W_TORP, front, 500.0, 500.0, 1.0)
	_hit_p(ship, turret, Rules.W_BOLT, right, 100.0, 50.0, 0.0)
	world.combat.kill(ship, DamageInfo.from_unit(killer, 500.0, Rules.W_TORP, front))
	team.strain_t = was_strain
	ship.aggro_time = was_aggro
	h.respawn_t = 500.0
	await _frames(2)
	card.refresh(true)
	await _frames(1)
	if hud.hangar != null:
		hud.hangar.visible = false
	await _frames(8)
	card.refresh(true)
	var dr: Script = DeathRecap
	var words: Dictionary = dr.get_script_constant_map().get("RULE_WORDS", {})
	var has_line := card._sum_labels.size() > 4
	# K1: the card's room for a fifth line, measured.
	var hc: Script = HudDeathCard
	var hc_consts := hc.get_script_constant_map()
	var note_y := float(hc_consts.get("NOTE_Y", 72.0))
	var mate_top := -1.0
	for b: Button in card._mate_btns:
		if b.visible:
			mate_top = b.position.y
			break
	var top := HudDeathCard.BODY_Y + note_y
	var room := mate_top - (top + 16.0)
	print("MEASURED card room: body top %.0f, fifth line top %.0f, fifth line bottom %.0f, teammate row top %.0f, gap %.0f" % [HudDeathCard.BODY_Y, top, top + 16.0, mate_top, room])
	_expect(card.visible and card.has_data and mate_top > 0.0 and room >= 4.0, "card: room for a fifth Summary line (measured)", "gap %.0f px" % room)
	# K2.
	var age := float(recap.death.get("aggro_age", -999.0))
	var strain := float(recap.death.get("strain_s", -1.0))
	_expect(absf(age - 1.0) <= 0.05 and is_equal_approx(strain, 12.0), "card: the dying ship's aggro and strain facts are kept in the death", "aggro_age %.2f, strain_s %.2f" % [age, strain])
	# K3, with K7, K8 and K9 read in its state.
	var l := "card: a pierce death shows the shield rule line"
	var line_text := _line(card) if has_line else "(no fifth label)"
	var line_on := has_line and (card._sum_labels[4] as Label).visible
	_expect(line_on and line_text == String(words.get("pierce_full", "?")) and not words.is_empty(), l, line_text)
	l = "card: the line sits inside the card and clear of the teammate row"
	if _need(has_line, l, "the card's fifth label"):
		var lab: Label = card._sum_labels[4]
		var inside := lab.position.x >= 0.0 and lab.position.x + lab.size.x <= card.size.x and lab.position.y >= 0.0 and lab.position.y + 16.0 <= card.size.y
		_expect(inside and mate_top > 0.0 and lab.position.y + 16.0 <= mate_top - 4.0, l, "label %s, row top %.0f" % [str(lab.position), mate_top])
	l = "card: every note fits one row at the note's smallest size, uncut"
	if _need(has_line and _has(hc, "NOTE_MIN_PX") and not words.is_empty(), l, "the fifth label, NOTE_MIN_PX and RULE_WORDS"):
		var font := (card._sum_labels[4] as Label).get_theme_font("font")
		var px := int(hc_consts.get("NOTE_MIN_PX", 10))
		var worst := ""
		var widest := 0.0
		var widest_id := ""
		for id: Variant in words:
			var text := _fill(words, String(id), 99)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
			if width > widest:
				widest = width
				widest_id = str(id)
			if width > HudDeathCard.W - 16.0:
				worst += " %s %.0f" % [str(id), width]
		print("MEASURED note width: widest %s %.0f of %.0f" % [widest_id, widest, HudDeathCard.W - 16.0])
		_expect(worst == "", l, "too wide:" + worst)
	l = "card: the card is still 440 x 168"
	_expect(card.size == Vector2(440.0, 168.0), l, str(card.size))
	# K4: take the torpedo out; the turret bolt came inside the last aggro window.
	l = "card: the line changes with the facts"
	recap.entries = recap.entries.filter(func(e: Dictionary) -> bool: return int(e["wkind"]) != Rules.W_TORP)
	card.refresh(true)
	line_text = _line(card) if has_line else "(no fifth label)"
	_expect(has_line and (card._sum_labels[4] as Label).visible and line_text == _fill(words, "aggro", 0) and not words.is_empty(), l, line_text)
	# K5.
	l = "card: strain shows its seconds left"
	recap.death["aggro_age"] = 99.0
	recap.death["strain_s"] = 12.2
	card.refresh(true)
	line_text = _line(card) if has_line else "(no fifth label)"
	_expect(has_line and line_text.contains("13") and line_text == _fill(words, "strain", 13) and not words.is_empty(), l, line_text)
	# K6.
	l = "card: no rule hides the line"
	recap.death["strain_s"] = 0.0
	card.refresh(true)
	_expect(has_line and not (card._sum_labels[4] as Label).visible, l)


## Parts S and T: the energy beep and the flash table row (pure).
func _part_s() -> void:
	var sx: Script = Sfx
	var consts := sx.get_script_constant_map()
	var l := "sound: the energy beep's pitch differs from torp_warn by at least 25 percent"
	if _need(_has(sx, "ENERGY_EMPTY_HZ") and _has(sx, "TORP_WARN_HZ"), l, "Sfx.ENERGY_EMPTY_HZ and TORP_WARN_HZ"):
		var e := float(consts["ENERGY_EMPTY_HZ"])
		var t := float(consts["TORP_WARN_HZ"])
		_expect(absf(e / t - 1.0) >= 0.25, l, "%.0f against %.0f" % [e, t])
	l = "sound: the energy beep's gap is 0.4 s and under the ring's pulse gap, so the ring sets the rate (holds to 2.5x game speed; at 3x every other beep is dropped, by design for now)"
	var rx: Script = ShipRing
	var ring_consts := rx.get_script_constant_map()
	var beep_gap := float(Sfx.MIN_GAP.get("energy_empty", -1.0))
	_expect(is_equal_approx(beep_gap, 0.4) and beep_gap < float(ring_consts.get("ENERGY_GAP", 0.0)), l, "beep gap %.2f, ring gap %s" % [beep_gap, str(ring_consts.get("ENERGY_GAP", "missing"))])
	l = "sound: the torp_warn tone is still 1040 Hz"
	if _need(_has(sx, "TORP_WARN_HZ"), l, "Sfx.TORP_WARN_HZ"):
		_expect(is_equal_approx(float(consts["TORP_WARN_HZ"]), 1040.0), l)
	l = "table: the pulse has its row (per event, at least 1000 ms between pulses)"
	var found := false
	for r: Dictionary in FlashTable.rows():
		if String(r["name"]) == "Energy empty pulse":
			found = String(r["file"]) == "scripts/ui/ship_ring.gd" and String(r["kind"]) == "pulse" and String(r["rate"]) == "per event" and int(r["min_gap_ms"]) >= 1000 and not bool(r["today"])
	_expect(found, l)


## Does `script` have a function or a constant called `what`? (Read from the script's own lists, so a missing one is a plain false.)
func _has(script: Script, what: String) -> bool:
	if script == null:
		return false
	for m: Dictionary in script.get_script_method_list():
		if String(m["name"]) == what:
			return true
	return script.get_script_constant_map().has(what)


## Count a failed and skipped case `label` when `ok` is false (a piece this build adds is missing: `what`); true when `ok`.
func _need(ok: bool, label: String, what: String) -> bool:
	if ok:
		return true
	failures += 1
	skipped += 1
	print("FAIL %s (not built: %s)" % [label, what])
	print("skipped: %s" % label)
	return false


## A hit summary with the keys rule_note() reads (the amounts are in damage; `total` is the whole window).
func _sum(total: float, pierced: float, full: float, ion: float, bare: float, late: float) -> Dictionary:
	return {"total": total, "ion": ion, "pierced": pierced, "pierce_full": full, "ion_bare": bare, "late_defence": late}


## The answer of DeathRecap.rule_note(s, death) as a Dictionary (a stand-in with the rule "<none>" when the call gave none).
func _note(script: Script, s: Dictionary, death: Dictionary) -> Dictionary:
	var r: Variant = script.call("rule_note", s, death)
	if r is Dictionary and (r as Dictionary).has("rule") and (r as Dictionary).has("text"):
		return r
	return {"rule": "<none>", "text": ""}


## The words `id` of the rule table with its figures filled (`secs` is the seconds the strain words carry).
func _fill(words: Dictionary, id: String, secs: int) -> String:
	var text := String(words.get(id, ""))
	if not text.contains("%"):
		return text
	if id == "aggro":
		return text % int(TurretData.AGGRO_WINDOW)
	if id == "strain":
		return text % [roundi(Rules.STRAIN_WEAPON_MULT * 100.0), secs]
	return text


## The text of the card's fifth Summary label.
func _line(card: HudDeathCard) -> String:
	return (card._sum_labels[4] as Label).text


## The integer value of property `prop` of `o` (0 when the property does not exist).
func _geti(o: Object, prop: String) -> int:
	var v: Variant = o.get(prop)
	return int(v) if v != null else 0


## Count an "energy_empty" cue.
func _on_cue(cue: String, _pos: Vector2) -> void:
	if cue == "energy_empty":
		_cues += 1


## Every script variable of `n` as a Dictionary name -> value (a copy, to compare before and after).
func _fields(n: Object) -> Dictionary:
	var out := {}
	for p: Dictionary in n.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			var v: Variant = n.get(String(p["name"]))
			out[String(p["name"])] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## A new pilot `name` of team `team` in hull `hull`, launched and still (null when the launch gave no ship).
func _spawn(pilot_name: String, team: int, hull: String) -> Ship:
	var p := PilotProfile.new(pilot_name, team, _next_slot, false)
	_next_slot += 1
	p.hull_id = hull
	world.profiles.append(p)
	var s := world.launch(p)
	if s != null:
		s.velocity = Vector2.ZERO
		s.controller = null
	return s


## One hit by `src` (weapon kind `kind`, from point `from`, `pierce` share past the shields) of final `amount`, `hull` of it on the
## hull, on `target`: logged in the target's own damage log the way Combat does, and announced the way Combat announces it.
func _hit_p(target: Ship, src: Unit, kind: int, from: Vector2, amount: float, hull: float, pierce: float) -> void:
	var d := DamageInfo.from_unit(src, amount, kind, from)
	d.pierce = pierce
	target.log_damage(d, amount)
	Events.damage_applied.emit(target, d, amount, hull)


## The summary line, and quit.
func _finish() -> void:
	get_tree().paused = false
	print("rule_warn_check: %d cases skipped" % skipped)
	print("rule_warn_check: %d failures" % failures)
	get_tree().quit()


## Count a PASS or FAIL line for the check `what`, with `detail` after a failure.
func _expect(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		print("PASS %s" % what)
	else:
		print("FAIL %s%s" % [what, (" [" + detail + "]") if detail != "" else ""])
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
