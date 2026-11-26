extends Node
## WHAT THIS IS: the check of the guns of the two ships of the line (C2): the side mounts and
## their arcs, the Broadside charge and its side lock, the guns on the side away from the
## reticle, the captain's beam rule, the idle swing and the fixed battery spread, the arcs view
## and the always-on reticle mark, and the reach line of the hangar card.
##
## HOW IT WORKS: setup() freezes the match, launches real ships (a Destroyer, a Battlecruiser,
## a Flak Frigate and targets, each with its own controller off, the aim point and the trigger set
## by the check) and steps them by hand with Ship.sim_update(). One group of cases per part of
## the build (_cases_item1 to _cases_item4). Each case prints "broadside_check: PASS <name>" or
## "broadside_check: FAIL <name>: <what>". The last lines are "broadside_check: <n> checks, <k>
## failures" and, only when k is 0, "broadside_check: 0 failures".
## The check names a class or a member of the build only through load(), get(), set() and
## call(), so on the base build, which has none of them, it prints FAIL lines and never fails to
## parse (the probe branch runs it there).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=broadside_check
##
## WHO USES IT: main.gd loads it for --test=broadside_check. It launches extra ships into the
## match it builds and changes only that match.

## One physics tick, in seconds.
const DT := 1.0 / 60.0
## The mount count of every other hull on the base build (a literal table).
const OTHER_COUNTS := {"scout": 1, "fighter": 1, "lance": 1, "bomber": 2, "logistics": 1, "support": 1, "flak": 3, "ion": 2}

## The running match (set by setup()).
var world: World
## How many cases ran and how many failed.
var checks := 0
## How many of them failed.
var fails := 0
## The ground the ships stand on: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## The "broadside_charge" cues heard (Events.cue), counted by _on_cue().
var _charge_cues := 0


## main.gd calls this once, right after the World is built. Freeze the match and run on the
## next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	Events.cue.connect(_on_cue)
	_run.call_deferred()


## Every group of cases, then the verdict.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_cases_item1()
	_cases_item2()
	_cases_item3()
	_cases_item4()
	await _draw_probe()
	print("broadside_check: %d checks, %d failures" % [checks, fails])
	if fails == 0:
		print("broadside_check: 0 failures")
	get_tree().quit()


## Count one case and print its line.
func _case(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("broadside_check: PASS %s" % what)
	else:
		fails += 1
		print("broadside_check: FAIL %s: %s" % [what, detail])


## Count the cue "broadside_charge".
func _on_cue(cue_name: String, _at: Vector2) -> void:
	if cue_name == "broadside_charge":
		_charge_cues += 1


## Launch a ship of hull `hid` for `team`, controller off, standing still at `at` facing east,
## shields and battery full.
func _ship(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 60 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = at
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.shields.fill()
	s.shields.since_hit = 999.0
	s.fill_energy()
	s.controls.aim_point = at + Vector2(2000.0, 0.0)
	s.controls.face_point = s.controls.aim_point
	s.controls.fire = false
	return s


## Where each pinned ship stands: instance id -> [position, rotation]. _step() puts a pinned ship
## back there after its tick, so the geometry of a case never drifts.
var _pins := {}


## Pin ship `s` where it is now (or, with `rot`, at that heading).
func _pin(s: Ship, rot: float = 0.0) -> void:
	s.rotation = rot
	_pins[s.get_instance_id()] = [s.global_position, rot]


## Step every ship of `ships` one tick (the match clock, the spatial hashes, the ship's own tick) and
## put the pinned ones back where they stood.
func _step(ships: Array, pin: bool = true) -> void:
	world.time += DT
	world.registry.rebuild_hashes()
	for s: Ship in ships:
		s.sim_update(DT)
		if pin and _pins.has(s.get_instance_id()):
			var pr: Array = _pins[s.get_instance_id()]
			s.global_position = pr[0]
			s.rotation = float(pr[1])
			s.velocity = Vector2.ZERO


## Step `n` ticks.
func _steps(ships: Array, n: int) -> void:
	for _i in n:
		_step(ships)


## Step ship `s` (with `others`) one tick and return the indexes of the guns of `s` that fired on
## it: a cooldown that jumped up is a round, a beam burst that began is a burst.
func _step_fired(s: Ship, others: Array = []) -> Array:
	var cds: Array = []
	var ons: Array = []
	for m: WeaponMount in s.mounts:
		cds.append(m.cd)
		ons.append(m.beam_on)
	_step([s] + others)
	var out: Array = []
	for i in s.mounts.size():
		var m: WeaponMount = s.mounts[i]
		if m.cd > float(cds[i]) + 0.0001 or m.beam_on > float(ons[i]) + 0.0001:
			out.append(i)
	return out


## The gun of `s` with id `id`, or null.
func _mount(s: Ship, id: String) -> WeaponMount:
	for m: WeaponMount in s.mounts:
		if m.id == id:
			return m
	return null


## The guns of `s` whose id is in `ids`, in the order of `ids`; fewer than asked when one is missing.
func _mounts(s: Ship, ids: Array) -> Array:
	var out: Array = []
	for id: String in ids:
		var m := _mount(s, id)
		if m != null:
			out.append(m)
	return out


## The index of gun `m` in `s.mounts`.
func _idx(s: Ship, m: WeaponMount) -> int:
	return s.mounts.find(m)


## Member `prop` of `o` as a number; `missing` when the member does not exist (the base build).
func _f(o: Object, prop: String, missing: float = -1.0) -> float:
	var v: Variant = o.get(prop)
	return float(v) if v != null else missing


## Take the ships of one scene out of the match (dead, far away) so they never meet another case.
func _clear(list: Array) -> void:
	var k := 0
	for u: Unit in list:
		k += 1
		u.global_position = Vector2(-9000.0 - 400.0 * k, -9000.0)
		u.alive = false
	world.registry.rebuild_hashes()


## Make a Halcyon ship `hid` at the home ground and enemy Cinder Destroyers at `offsets` from it
## (local offsets, turned with nothing: the ship faces east). Returns [ship, enemy, enemy...]. The ship's aim
## point is its first enemy, or far to the starboard when there is none.
func _scene(hid: String, offsets: Array) -> Array:
	var a := _ship(hid, Rules.HALCYON, _home)
	_pin(a)
	var out: Array = [a]
	for off: Vector2 in offsets:
		var t := _ship("destroyer", Rules.CINDER, _home + off)
		## Seen by the Halcyon team now: turret sight's fog rule makes every gun skip an enemy its team cannot
		## see, and the fog system that sets this bit every tick does not run in this frozen match.
		t.visible_mask |= 1 << Rules.HALCYON
		_pin(t)
		out.append(t)
	a.controls.aim_point = (out[1] as Ship).global_position if out.size() > 1 else _home + Vector2(0.0, 2000.0)
	a.controls.fire = false
	return out


## True when `s` has an arc-35 starboard main gun of id `id` etc.: every id of `ids` is a gun of `s`.
## Prints a FAIL for the case `what` when one is missing (the base build has none of the new ids).
func _need(what: String, s: Ship, ids: Array) -> bool:
	var have := _mounts(s, ids).size()
	if have != ids.size():
		_case(what, false, "the ship lacks guns %s (has %d of %d)" % [str(ids), have, ids.size()])
		return false
	return true


## How many rows of hull `hid` use weapon `wid`.
func _rows_of(hid: String, wid: String) -> int:
	var n := 0
	for row: Dictionary in Ships.HULLS[hid]["mounts"]:
		if row["w"] == wid:
			n += 1
	return n


# --- item 1: the mounts, arcs, ids and their sockets -------------------------------------------

## The rows of the two capitals, the launched guns' battery flag, and the other hulls' counts.
func _cases_item1() -> void:
	var counts := {
		"destroyer": {"rows": 11, "heavy_cannon": 4, "light_turret": 2, "pd_gun": 3, "flak_auto": 2},
		"battlecruiser": {"rows": 14, "ion_turret": 2, "heavy_cannon": 4, "light_turret": 2, "pd_gun": 4, "flak_auto": 2},
	}
	for hid: String in counts:
		var want: Dictionary = counts[hid]
		var rows: Array = Ships.HULLS[hid]["mounts"]
		_case("%s holds %d mounts" % [hid, int(want["rows"])], rows.size() == int(want["rows"]), str(rows.size()))
		var mix := ""
		var mix_ok := true
		for wid: String in want:
			if wid == "rows":
				continue
			var n := _rows_of(hid, wid)
			mix += "%s %d " % [wid, n]
			mix_ok = mix_ok and n == int(want[wid])
		_case("%s weapon mix is %s" % [hid, str(want).replace("\n", " ")], mix_ok, mix)
		var arcs_bad: Array[String] = []
		var seen := {}
		for row: Dictionary in rows:
			var id := String(row.get("id", ""))
			seen[id] = true
			var arc := float(row["arc"])
			var face := float(row.get("face", 0.0))
			match String(row["w"]):
				"heavy_cannon", "ion_turret":
					# The port guns (negative y) face -90, the starboard ones +90.
					if arc != 35.0 or absf(face) != 90.0 or not bool(row.get("battery", false)) or face * float((row["off"] as Vector2).y) <= 0.0:
						arcs_bad.append(id)
				"light_turret":
					if arc != 30.0 or bool(row.get("battery", false)):
						arcs_bad.append(id)
				"pd_gun", "flak_auto":
					# The Destroyer's one aft PD faces the tail; every other PD and flak is a side gun.
					if arc != 80.0 or not (absf(face) == 90.0 or (hid == "destroyer" and id == "pd_aft" and face == 180.0)):
						arcs_bad.append(id)
		_case("%s: every heavy and ion gun arc 35 face +-90 battery, chasers arc 30, side PD and flak arc 80" % hid, arcs_bad.is_empty(), str(arcs_bad))
		_case("%s: %d distinct ids, one per row" % [hid, int(want["rows"])], seen.size() == int(want["rows"]) and seen.size() == rows.size(), "%d of %d rows" % [seen.size(), rows.size()])
		_case("%s row carries side_battery" % hid, bool(Ships.HULLS[hid].get("side_battery", false)))
		var first: Dictionary = rows[0]
		_case("%s: the first row is a battery main gun" % hid, bool(first.get("battery", false)) and String(first["w"]) in ["heavy_cannon", "ion_turret"], String(first["w"]))
		# A launched ship carries the battery flag on exactly the heavy and ion guns.
		var s := _ship(hid, Rules.HALCYON, _home)
		var flagged := 0
		var wrong := 0
		for m: WeaponMount in s.mounts:
			var bv: Variant = m.get("battery")
			var b: bool = bv == true
			if b:
				flagged += 1
			if b != (m.weapon_id in ["heavy_cannon", "ion_turret"]):
				wrong += 1
		var want_flagged := 4 if hid == "destroyer" else 6
		_case("%s launched: battery true on exactly the %d heavy and ion guns" % [hid, want_flagged], flagged == want_flagged and wrong == 0, "%d flagged, %d wrong" % [flagged, wrong])
	# Every other hull keeps its mount count (a control: green on the base too).
	var other_bad: Array[String] = []
	for hid: String in OTHER_COUNTS:
		var n: int = (Ships.HULLS[hid]["mounts"] as Array).size()
		if n != int(OTHER_COUNTS[hid]):
			other_bad.append("%s %d" % [hid, n])
	_case("control: the eight other hulls keep their mount counts", other_bad.is_empty(), str(other_bad))
	# Cinder drawings are not edited: say which new mount sits outside their outline (INFO only).
	for hid in ["destroyer", "battlecruiser"]:
		var u := float(Ships.HULLS[hid]["length"]) / 36.0
		var sil: PackedVector2Array = CinderShapes.HULLS[hid]["sil"]
		for row: Dictionary in Ships.HULLS[hid]["mounts"]:
			var at := (row["off"] as Vector2) / u
			if not Geometry2D.is_point_in_polygon(at, sil):
				print("broadside_check: INFO cinder %s %s at design %s lies outside the Vhorr outline" % [hid, row["id"], at])


# --- item 2: the Broadside charge, its side lock, the volley, the sound, the Overcharge warning ---

## Ticks from the press (tick 0) to each stage of a Broadside, and what the guns did.
func _cases_item2() -> void:
	var ids_s := ["ion_stbd", "heavy_fore_stbd", "heavy_aft_stbd"]
	var ids_p := ["ion_port", "heavy_fore_port", "heavy_aft_port"]
	# The press alone: the cooldown and the energy are spent at the press, as they always were (a control).
	var sc := _scene("battlecruiser", [])
	var bc: Ship = sc[0]
	var v0 := bc.energy.value
	bc.controls.special = true
	_step([bc])
	_case("control: the press spends 120 energy and starts the 25 s cooldown", absf(bc.special_cd - 25.0) < 0.01 and v0 - bc.energy.value > 118.0 and v0 - bc.energy.value < 121.0, "cooldown %s energy spent %s" % [bc.special_cd, v0 - bc.energy.value])
	_clear(sc)

	# The charge, the volley, the window: a target on the starboard beam, the trigger held from the press.
	sc = _scene("battlecruiser", [Vector2(0.0, 1000.0)])
	bc = sc[0]
	if _need("broadside charge cases", bc, ids_s + ids_p):
		_steps([bc], 30)
		bc.controls.fire = true
		bc.controls.special = true
		_charge_cues = 0
		var first := {}
		var early := 0
		var port_fired := 0
		var win_first := -1
		var win_len := 0
		var cues_at_press := 0
		for i in 340:
			var fired := _step_fired(bc)
			if i == 0:
				cues_at_press = _charge_cues
			for fi: int in fired:
				var fm: WeaponMount = bc.mounts[fi]
				if fm.id in ids_s:
					if not first.has(fm.id):
						first[fm.id] = i
					if i < 72:
						early += 1
				elif fm.id in ids_p and i < 120:
					port_fired += 1
			if _f(bc, "special_t") > 0.0:
				if win_first < 0:
					win_first = i
				win_len += 1
			bc.controls.special = false
		var vols: Array = []
		for id: String in ids_s:
			vols.append(int(first.get(id, -1)))
		var same: bool = vols[0] == vols[1] and vols[1] == vols[2]
		var v_first: int = vols[0]
		_case("charge: the starboard battery volley is on tick 72 after the press", same and v_first >= 71 and v_first <= 73, "volley ticks %s" % str(vols))
		_case("charge: the starboard battery holds fire during the charge", early == 0, "%d shots from the starboard battery before tick 72" % early)
		_case("charge: the port battery takes no part in the volley", port_fired == 0, "%d port battery shots in the first 120 ticks" % port_fired)
		_case("window: the faster fire starts on tick 72 after the press", win_first >= 71 and win_first <= 73, "starts on tick %d" % win_first)
		_case("window: it lasts 4 s", win_len >= 239 and win_len <= 241, "lasts %d ticks" % win_len)
		_case("sound: the cue broadside_charge is emitted once at the press", cues_at_press == 1 and _charge_cues == 1, "%d at the press, %d in all" % [cues_at_press, _charge_cues])
		# The ion's alignment on the volley tick: report it.
		var ion_s := _mount(bc, "ion_stbd")
		print("broadside_check: INFO the ion turret fired on tick %d (it is a beam: beam_firing %s now)" % [int(first.get("ion_stbd", -1)), str(ion_s.beam_firing)])
	_clear(sc)

	# The window's fire rate: the charged side fires 1.5 times as fast as the side that is not charged.
	sc = _scene("battlecruiser", [Vector2(0.0, 1000.0), Vector2(0.0, -1000.0)])
	bc = sc[0]
	var hs := _mount(bc, "heavy_fore_stbd")
	var hp := _mount(bc, "heavy_fore_port")
	if hs != null and hp != null:
		_steps([bc], 30)
		bc.controls.fire = true
		bc.controls.special = true
		var cd_s: Array = []
		var cd_p: Array = []
		for i in 330:
			var cs := hs.cd
			var cp := hp.cd
			_step([bc])
			bc.controls.special = false
			if i >= 80 and i <= 305:
				if hs.cd > cs + 0.0001:
					cd_s.append(hs.cd)
				if hp.cd > cp + 0.0001:
					cd_p.append(hp.cd)
		var avg_s := 0.0
		var avg_p := 0.0
		for c: float in cd_s:
			avg_s += c / float(cd_s.size())
		for c: float in cd_p:
			avg_p += c / float(cd_p.size())
		var ratio := avg_p / avg_s if avg_s > 0.0 and avg_p > 0.0 else 0.0
		_case("window: the charged side's heavy cannon fires 1.5 times as fast as the other side's", ratio > 1.4 and ratio < 1.6, "cooldown after a shot %.3f (charged, %d shots) against %.3f (other, %d shots), ratio %.3f" % [avg_s, cd_s.size(), avg_p, cd_p.size(), ratio])
	else:
		_case("window: the charged side fires 1.5 times as fast as the other side", false, "no heavy_fore_stbd or heavy_fore_port")
	_clear(sc)

	# The side lock: the reticle goes to the other side during the charge.
	sc = _scene("battlecruiser", [])
	bc = sc[0]
	var aim_port := _home + Vector2(0.0, -1000.0)
	bc.controls.aim_point = _home + Vector2(0.0, 1000.0)
	v0 = bc.energy.value
	bc.controls.special = true
	var win_seen := false
	var stbd_fired := 0
	var e12 := 0.0
	var cd100 := 0.0
	for i in 101:
		var fired := _step_fired(bc)
		bc.controls.special = false
		if i == 10:
			bc.controls.aim_point = aim_port
		for fi: int in fired:
			if (bc.mounts[fi] as WeaponMount).id in ids_s:
				stbd_fired += 1
		if _f(bc, "special_t") > 0.0:
			win_seen = true
		if i == 12:
			e12 = bc.energy.value
			_case("side lock: the reticle on the other side loses the charge", _f(bc, "charge_t", 99.0) == 0.0, "charge_t %s on tick 12" % str(_f(bc, "charge_t", 99.0)))
		if i == 100:
			cd100 = bc.special_cd
	_case("side lock: no volley and no faster fire come, and nothing is refunded", not win_seen and stbd_fired == 0 and cd100 > 23.0 and cd100 < 24.0 and v0 - e12 > 105.0, "window seen %s, %d starboard shots, cooldown %.2f on tick 100, energy %.1f of %.1f on tick 12" % [str(win_seen), stbd_fired, cd100, e12, v0])
	_clear(sc)

	# The reticle moves off the arc but stays on the same side: the battery stays held and the volley still comes.
	sc = _scene("battlecruiser", [Vector2(0.0, 1000.0)])
	bc = sc[0]
	if _need("side lock: the reticle off the arc on the same side", bc, ids_s):
		_steps([bc], 30)
		bc.controls.fire = true
		bc.controls.special = true
		var shots_held := 0
		var shots_on_volley := 0
		var win_at := -1
		var charge_alive := true
		for i in 100:
			var fired := _step_fired(bc)
			bc.controls.special = false
			if i == 10:
				bc.controls.aim_point = _home + Vector2(900.0, 400.0)
			for fi: int in fired:
				if (bc.mounts[fi] as WeaponMount).id in ids_s:
					if i >= 1 and i < 72:
						shots_held += 1
					if i >= 72 and i <= 73:
						shots_on_volley += 1
			if i == 70:
				charge_alive = _f(bc, "charge_t") > 0.0
			if _f(bc, "special_t") > 0.0 and win_at < 0:
				win_at = i
		_case("side lock: a reticle off the arc on the same side leaves the starboard battery held", shots_held == 0 and shots_on_volley == 0, "%d starboard shots during the charge, %d on the volley ticks" % [shots_held, shots_on_volley])
		_case("side lock: and the charge is kept, the window still starts", charge_alive and win_at >= 71 and win_at <= 73, "charge alive on tick 70 %s, window starts on tick %d" % [str(charge_alive), win_at])
	_clear(sc)

	# A running ion burst stops at the press.
	sc = _scene("battlecruiser", [Vector2(0.0, 1000.0)])
	bc = sc[0]
	var ion := _mount(bc, "ion_stbd")
	if ion != null:
		_steps([bc], 30)
		bc.controls.fire = true
		var burning := false
		for i in 60:
			_step([bc])
			if ion.beam_firing:
				burning = true
				break
		bc.controls.special = true
		_step([bc])
		bc.controls.special = false
		_step([bc])
		_case("a running ion burst stops at the press", burning and not ion.beam_firing and ion.beam_on == 0.0, "burning before %s, beam_firing %s, beam_on %s" % [str(burning), str(ion.beam_firing), str(ion.beam_on)])
	else:
		_case("a running ion burst stops at the press", false, "no ion_stbd")
	_clear(sc)

	# The systems go off during the charge: it is lost.
	sc = _scene("battlecruiser", [])
	bc = sc[0]
	bc.controls.special = true
	var any_window := false
	for i in 200:
		_step([bc])
		bc.controls.special = false
		if i == 10:
			bc.overload_left = 10.0
		if _f(bc, "special_t") > 0.0:
			any_window = true
		if i == 12:
			_case("systems off during the charge cancels it", _f(bc, "charge_t", 99.0) == 0.0, "charge_t %s on tick 12" % str(_f(bc, "charge_t", 99.0)))
	_case("systems off during the charge: no volley or window comes", not any_window)
	_clear(sc)

	# The Destroyer's Overcharge: a 1 s warning, then double fire for 5 s, and no side lock.
	sc = _scene("destroyer", [])
	var ds: Ship = sc[0]
	var base_mult := ds.fire_mult
	ds.controls.special = true
	var d_first := -1
	var d_len := 0
	var warn_at_30 := -1.0
	var side_at_press := 99
	for i in 420:
		_step([ds])
		ds.controls.special = false
		if i == 0:
			side_at_press = int(_f(ds, "charge_side", 99.0))
		if i == 10:
			ds.controls.aim_point = _home + Vector2(0.0, -1000.0)
		if i == 30:
			warn_at_30 = _f(ds, "charge_t", -1.0)
		if ds.fire_mult > base_mult * 1.9:
			if d_first < 0:
				d_first = i
			d_len += 1
	_case("overcharge: the double fire rate begins 1 s after the press and lasts 5 s", d_first >= 59 and d_first <= 61 and d_len >= 299 and d_len <= 301, "begins on tick %d, lasts %d ticks" % [d_first, d_len])
	_case("overcharge: it has no side (charge_side 0) and no lock (the charge runs on with the reticle across)", side_at_press == 0 and warn_at_30 > 0.0, "charge_side %d, charge_t %s on tick 30" % [side_at_press, str(warn_at_30)])
	_clear(sc)


# --- item 3: the off-side guns, the idle swing, the battery spread, the captain's beam rule -------

## Step `s` for `n` ticks and count the shots of every gun of `s`, by index.
func _count_shots(s: Ship, n: int) -> Dictionary:
	var out := {}
	for _i in n:
		for fi: int in _step_fired(s):
			out[fi] = int(out.get(fi, 0)) + 1
	return out


## How many shots the guns of `ms` made in `counts` (a _count_shots result).
func _shots_of(s: Ship, counts: Dictionary, ms: Array) -> int:
	var n := 0
	for m: WeaponMount in ms:
		n += int(counts.get(_idx(s, m), 0))
	return n


## The guns of ship `s` that use weapon `wid`, on the side `side` (+1, -1; 0 = any side).
func _guns(s: Ship, wid: String, side: int = 0) -> Array:
	var out: Array = []
	for m: WeaponMount in s.mounts:
		if m.weapon_id == wid and (side == 0 or int(signf(m.offset.y)) == side):
			out.append(m)
	return out


## Does the script `script` have a method called `name` (a static one too)?
func _has_script_method(script: Script, name: String) -> bool:
	if script == null:
		return false
	for md: Dictionary in script.get_script_method_list():
		if String(md["name"]) == name:
			return true
	return false


## The off-side guns, the idle swing, the battery spread and the captain's beam rule.
func _cases_item3() -> void:
	# The side flak and PD shoot only inside their arcs.
	var sc := _scene("battlecruiser", [Vector2(900.0, 0.0)])
	var bc: Ship = sc[0]
	bc.controls.fire = false
	var flaks := _guns(bc, "flak_auto")
	var counts := _count_shots(bc, 600)
	var ahead := _shots_of(bc, counts, flaks) + _shots_of(bc, counts, _guns(bc, "pd_gun"))
	_case("a target dead ahead draws no shot from a side flak or a side PD (the arc rejects it)", ahead == 0 and flaks.size() == 2 and (flaks[0] as WeaponMount).face != 0.0, "%d shots, %d flak guns" % [ahead, flaks.size()])
	_clear(sc)
	sc = _scene("battlecruiser", [Vector2(0.0, -400.0)])
	bc = sc[0]
	bc.controls.fire = false
	counts = _count_shots(bc, 400)
	var f_port := _shots_of(bc, counts, _guns(bc, "flak_auto", -1))
	var p_port := _shots_of(bc, counts, _guns(bc, "pd_gun", -1))
	var f_stbd := _shots_of(bc, counts, _guns(bc, "flak_auto", 1))
	var p_stbd := _shots_of(bc, counts, _guns(bc, "pd_gun", 1))
	_case("a target on the port beam draws shots from the port flak and PD and none from the starboard ones", f_port > 0 and p_port > 0 and f_stbd == 0 and p_stbd == 0, "port flak %d pd %d, starboard flak %d pd %d" % [f_port, p_port, f_stbd, p_stbd])
	_clear(sc)

	# An off-side heavy cannon: the reticle on the starboard beam, an enemy in the port arc, no trigger.
	sc = _scene("destroyer", [Vector2(0.0, -800.0)])
	var ds: Ship = sc[0]
	ds.controls.aim_point = _home + Vector2(0.0, 2000.0)
	ds.controls.fire = false
	var port_heavy := _guns(ds, "heavy_cannon", -1)
	counts = _count_shots(ds, 300)
	var off_shots := _shots_of(ds, counts, port_heavy)
	var port_ids_ok := port_heavy.size() == 2 and (port_heavy[0] as WeaponMount).arc < 0.7
	_case("an off-side heavy cannon fires at an enemy in its arc with the trigger up", off_shots > 0 and port_ids_ok, "%d shots from %d port heavy cannons" % [off_shots, port_heavy.size()])
	# The first heavy cannon of the hull (one that exists on the base build too) follows the reticle
	# when it is inside its arc (a control: a turret follows the aim point). The reticle goes to the port beam.
	var heavies := _guns(ds, "heavy_cannon")
	ds.controls.aim_point = _home + Vector2(0.0, -1000.0)
	# Long enough for the slowest swing: from the starboard beam to the port beam is 3.3 rad at 0.9 rad/s.
	_steps([ds], 300)
	var want := Util.ang_diff(ds.rotation, (ds.controls.aim_point - (heavies[0] as WeaponMount).world_pos()).angle()) if not heavies.is_empty() else 9.0
	var got := (heavies[0] as WeaponMount).angle if not heavies.is_empty() else -9.0
	_case("control: a turret gun with the reticle inside its arc follows the reticle", absf(Util.wrap_angle(want - got)) < 0.05, "wants %.3f, points %.3f" % [want, got])
	# Off-side-silent: with the systems off the port battery makes no shot; with them on it does.
	ds.controls.aim_point = _home + Vector2(0.0, 2000.0)
	ds.overload_left = 30.0
	counts = _count_shots(ds, 300)
	var silent := _shots_of(ds, counts, port_heavy)
	ds.overload_left = 0.0
	counts = _count_shots(ds, 300)
	var loud := _shots_of(ds, counts, port_heavy)
	_case("off-side guns are silent through an overload lockout and fire again after it", silent == 0 and loud > 0 and off_shots > 0, "%d shots with the systems off, %d with them on" % [silent, loud])
	_clear(sc)

	# A Flak Frigate's flak battery is a turret of a hull with no side battery: it keeps following the trigger.
	sc = _scene("flak", [Vector2(500.0, 0.0)])
	var ff: Ship = sc[0]
	var fb := _guns(ff, "flak_battery")
	ff.controls.aim_point = _home + Vector2(-2000.0, 0.0)
	counts = _count_shots(ff, 200)
	var quiet := _shots_of(ff, counts, fb)
	ff.controls.aim_point = (sc[1] as Ship).global_position
	ff.controls.fire = true
	counts = _count_shots(ff, 200)
	var noisy := _shots_of(ff, counts, fb)
	_case("control: a Flak Frigate's flak battery fires only on the trigger", quiet == 0 and noisy > 0 and fb.size() == 1, "%d shots with the trigger up, %d with it held, %d guns" % [quiet, noisy, fb.size()])
	_clear(sc)

	# T-89: the idle swing.
	_idle_cases()
	# T-91: the battery spread.
	_spread_cases()
	# The captain's beam rule.
	_captain_cases()


## T-89: a ship-of-the-line turret idle for 2 s swings 3 times as fast; a Flak Frigate's does not.
func _idle_cases() -> void:
	var sc := _scene("destroyer", [])
	var ds: Ship = sc[0]
	var m := _mount(ds, "heavy_fore_stbd")
	if m == null:
		_case("T-89: an idle heavy cannon swings 3 times as fast", false, "no heavy_fore_stbd")
	else:
		var face := m.face
		var edge := face + 0.55
		var at_edge := m.world_pos() + Vector2.from_angle(edge) * 1000.0
		var at_face := m.world_pos() + Vector2.from_angle(face) * 1000.0
		ds.controls.aim_point = at_face
		_steps([ds], 130)
		var a0 := m.angle
		ds.controls.aim_point = at_edge
		_steps([ds], 6)
		var d_idle := absf(Util.wrap_angle(m.angle - a0))
		ds.controls.aim_point = at_face
		_steps([ds], 40)
		m.set("idle_t", 10.0 / 60.0)
		var a1 := m.angle
		ds.controls.aim_point = at_edge
		_steps([ds], 6)
		var d_fresh := absf(Util.wrap_angle(m.angle - a1))
		var ratio := d_idle / d_fresh if d_fresh > 0.0 else 0.0
		_case("T-89: a heavy cannon idle for 2 s swings 3.0 times as fast as 10 ticks after a shot", ratio > 2.9 and ratio < 3.1, "swung %.4f idle, %.4f fresh, ratio %.3f" % [d_idle, d_fresh, ratio])
	_clear(sc)
	# The boost ends at the first shot.
	sc = _scene("destroyer", [Vector2(0.0, 1000.0)])
	ds = sc[0]
	m = _mount(ds, "heavy_fore_stbd")
	if m == null:
		_case("T-89: the boost ends at the first shot", false, "no heavy_fore_stbd")
	else:
		ds.controls.fire = false
		_steps([ds], 130)
		ds.controls.fire = true
		var shot_tick := -1
		for i in 60:
			var cd0 := m.cd
			_step([ds])
			if m.cd > cd0 + 0.0001:
				shot_tick = i
				break
		var idle_after := _f(m, "idle_t", 99.0)
		_case("T-89: the first shot starts the idle count over", shot_tick >= 0 and idle_after < 0.1, "shot on tick %d, idle_t %s after it" % [shot_tick, str(idle_after)])
	_clear(sc)
	# The ion is not boosted in the last half second of its own burst.
	sc = _scene("battlecruiser", [Vector2(0.0, 1000.0)])
	var bcs: Ship = sc[0]
	var ion := _mount(bcs, "ion_stbd")
	if ion == null:
		_case("T-89: the ion turret is not boosted late in its own burst", false, "no ion_stbd")
	else:
		bcs.controls.fire = false
		_steps([bcs], 130)
		bcs.controls.fire = true
		var burst_tick := -1
		for i in 200:
			_step([bcs])
			if burst_tick < 0 and ion.beam_firing:
				burst_tick = i
			if burst_tick >= 0 and i - burst_tick == 130:
				break
		var firing := ion.beam_firing
		var i0 := ion.angle
		bcs.controls.aim_point = ion.world_pos() + Vector2.from_angle(ion.face + 0.5) * 1000.0
		_steps([bcs], 6)
		var d_ion := absf(Util.wrap_angle(ion.angle - i0))
		_case("T-89: the ion turret is not boosted late in its own burst (6 ticks swing 1.0 times its 0.8 rad/s)", burst_tick >= 0 and firing and d_ion > 0.04 and d_ion < 0.12, "burst began on tick %d, firing %s, swung %.4f in 6 ticks (0.08 unboosted, 0.24 boosted)" % [burst_tick, str(firing), d_ion])
	_clear(sc)
	# A Flak Frigate's turret is not boosted (a control).
	sc = _scene("flak", [])
	var ff: Ship = sc[0]
	var fm := _guns(ff, "flak_battery")[0] as WeaponMount
	var aim_face := fm.world_pos() + Vector2.from_angle(0.0) * 1000.0
	var aim_edge := fm.world_pos() + Vector2.from_angle(0.5) * 1000.0
	ff.controls.aim_point = aim_face
	_steps([ff], 130)
	var b0 := fm.angle
	ff.controls.aim_point = aim_edge
	_steps([ff], 6)
	var f_idle := absf(Util.wrap_angle(fm.angle - b0))
	ff.controls.aim_point = aim_face
	_steps([ff], 40)
	var b1 := fm.angle
	ff.controls.aim_point = aim_edge
	_steps([ff], 6)
	var f_fresh := absf(Util.wrap_angle(fm.angle - b1))
	_case("control: a Flak Frigate's turret idle for 2 s swings 1.0 times as fast", f_fresh > 0.0 and absf(f_idle / f_fresh - 1.0) < 0.05, "swung %.4f idle, %.4f at once" % [f_idle, f_fresh])
	_clear(sc)


## T-91: the fixed spread of a battery pair, and the random spread kept for every other gun.
func _spread_cases() -> void:
	var wm: Script = load("res://scripts/entities/weapon_mount.gd")
	var has_fn := _has_script_method(wm, "shot_offset")
	var o2a: Variant = wm.call("shot_offset", 0, 2, 1000.0) if has_fn else null
	var o2b: Variant = wm.call("shot_offset", 1, 2, 1000.0) if has_fn else null
	var o1: Variant = wm.call("shot_offset", 0, 1, 1000.0) if has_fn else null
	var o3: Array = [wm.call("shot_offset", 0, 3, 1000.0), wm.call("shot_offset", 1, 3, 1000.0), wm.call("shot_offset", 2, 3, 1000.0)] if has_fn else []
	var ok := has_fn and absf(float(o2a) + 6.0) < 0.001 and absf(float(o2b) - 6.0) < 0.001 and absf(float(o1)) < 0.001 and o3.size() == 3 and absf(float(o3[0]) + 12.0) < 0.001 and absf(float(o3[1])) < 0.001 and absf(float(o3[2]) - 12.0) < 0.001
	_case("T-91: the shot offset is -6 and +6 for a pair, 0 for one, -12, 0, +12 for three, at 1,000", ok, "pair %s %s, single %s, three %s" % [str(o2a), str(o2b), str(o1), str(o3)])
	# Ten shots of one gun leave the same way, and the two guns of a pair 0.012 x d apart at the reticle.
	var sc := _scene("battlecruiser", [])
	var bc: Ship = sc[0]
	var aim := _home + Vector2(0.0, 1000.0)
	var gf := _mount(bc, "heavy_fore_stbd")
	var ga := _mount(bc, "heavy_aft_stbd")
	if gf == null or ga == null:
		_case("T-91: a battery gun's shots leave in one direction, a pair apart", false, "no heavy_fore_stbd or heavy_aft_stbd")
	else:
		bc.controls.aim_point = aim
		bc.controls.fire = false
		_steps([bc], 90)
		bc.controls.fire = true
		var angs: Array = []
		var sep := -1.0
		var d_avg := 0.0
		var pr := world.projectiles
		for i in 1000:
			var cf := gf.cd
			var ca := ga.cd
			var n0 := pr.active.size()
			_step([bc])
			var fore_shot := gf.cd > cf + 0.0001
			var aft_shot := ga.cd > ca + 0.0001
			if fore_shot and angs.size() < 10:
				angs.append(gf.world_angle())
			if fore_shot and aft_shot and sep < 0.0 and pr.active.size() >= n0 + 2:
				var e: Array = []
				var d_sum := 0.0
				for k in [pr.active.size() - 2, pr.active.size() - 1]:
					var slot: int = pr.active[k]
					var o: Vector2 = pr.pos[slot]
					var dir: Vector2 = (pr.vel[slot] as Vector2).normalized()
					var to_aim := aim - o
					e.append(dir.x * to_aim.y - dir.y * to_aim.x)
					d_sum += to_aim.length()
				sep = absf(float(e[0]) - float(e[1]))
				d_avg = d_sum * 0.5
			if angs.size() >= 10 and sep >= 0.0:
				break
		var spread := 0.0
		if angs.size() > 0:
			var lo: float = angs.min()
			var hi: float = angs.max()
			spread = hi - lo
		_case("T-91: ten shots of one battery gun leave in the same direction (no dice)", angs.size() == 10 and spread < 0.00001, "%d shots, spread %.8f rad" % [angs.size(), spread])
		var want_sep := 0.012 * d_avg
		_case("T-91: the two guns of a side pair leave 0.012 x d apart at the reticle", sep > 0.0 and absf(sep - want_sep) < 0.1 * want_sep, "%.2f apart, wanted %.2f (d %.1f)" % [sep, want_sep, d_avg])
	_clear(sc)
	# The random spread is kept for every other gun: a chaser, a Logistics turret and a Flak Frigate's battery.
	sc = _scene("battlecruiser", [])
	bc = sc[0]
	bc.controls.aim_point = _home + Vector2(1500.0, 0.0)
	var chaser := _mount(bc, "chaser_fore")
	if chaser == null:
		_case("a light chaser's shots still vary (the random spread is kept)", false, "no chaser_fore")
	else:
		_case("a light chaser's shots still vary (the random spread is kept)", _varies(bc, chaser), "all shots left in one direction")
	_clear(sc)
	for hid in ["logistics", "flak"]:
		sc = _scene(hid, [])
		var ls: Ship = sc[0]
		ls.controls.aim_point = _home + Vector2(1500.0, 0.0)
		var gun: WeaponMount = ls.mounts[0] if hid == "logistics" else _guns(ls, "flak_battery")[0]
		_case("control: the %s's gun still has its random spread" % hid, _varies(ls, gun), "all shots left in one direction")
		_clear(sc)


## Hold the trigger on `s` and read the direction of the newest round after each shot of `gun`: true
## when the rounds do not all leave the same way.
func _varies(s: Ship, gun: WeaponMount) -> bool:
	s.controls.fire = true
	var pr := world.projectiles
	var dirs: Array = []
	for _i in 400:
		var c0 := gun.cd
		_step([s])
		if gun.cd > c0 + 0.0001 and pr.active.size() > 0:
			dirs.append((pr.vel[pr.active[pr.active.size() - 1]] as Vector2).angle())
		if dirs.size() >= 8:
			break
	if dirs.size() < 3:
		return false
	var lo: float = dirs.min()
	var hi: float = dirs.max()
	return hi - lo > 0.0001


## The captain's beam rule: a ship of the line turns its nearer beam to the target.
func _captain_cases() -> void:
	var pc: Script = load("res://scripts/ai/pilot_combat.gd")
	var has_fn := _has_script_method(pc, "face_toward")
	for hid in ["destroyer", "battlecruiser"]:
		var sc := _scene(hid, [])
		var s: Ship = sc[0]
		var worst := 0.0
		var tried := 0
		var small_turn := true
		for head in [0.0, PI * 0.5, PI]:
			for bearing in [0.3, 1.7, -2.4]:
				s.rotation = head
				var tp: Vector2 = s.global_position + Vector2.from_angle(bearing) * 1200.0
				var fp: Vector2 = pc.call("face_toward", s, tp) if has_fn else tp
				var nose := (fp - s.global_position).angle()
				# The beam that points at the target after the hull turns to `nose`: the nearer of the two.
				var off := minf(absf(Util.wrap_angle(nose + PI * 0.5 - bearing)), absf(Util.wrap_angle(nose - PI * 0.5 - bearing)))
				worst = maxf(worst, off)
				small_turn = small_turn and absf(Util.wrap_angle(nose - head)) <= PI * 0.5 + 0.001
				tried += 1
		_case("%s: the captain's face point puts the target on a beam (10 degrees or less) with the smaller turn" % hid, has_fn and worst < deg_to_rad(10.0) and small_turn, "worst %.1f degrees over %d tries, the function exists %s" % [rad_to_deg(worst), tried, str(has_fn)])
		_clear(sc)
	# The point-blank branch keeps the nose-ahead spot, and the Ion Frigate keeps its face point (controls).
	var f := FileAccess.open("res://scripts/ai/pilot_combat.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	_case("control: inside 200 units the captain still holds the nose ahead", src.contains("else ship.global_position + Vector2.from_angle(ship.rotation) * 400.0"), "the line is gone")
	var sc2 := _scene("ion", [])
	var ion_ship: Ship = sc2[0]
	var tp2 := ion_ship.global_position + Vector2(900.0, 300.0)
	var fp2: Vector2 = pc.call("face_toward", ion_ship, tp2) if has_fn else tp2
	_case("control: the Ion Frigate's face point is the target itself", fp2 == tp2, "%s" % str(fp2))
	_clear(sc2)


# --- item 4: the arcs view, the reticle mark, the range bands ---------------------------------------

## A small node that paints through ArcView.draw() inside its own _draw(), so the drawing code
## runs once (the arcs cue is on, so the wedges are painted too). `painted` says it ran.
class DrawProbe extends Node2D:
	## The ArcView script to paint with.
	var view: Script
	## The ship to paint the arcs view and the mark for.
	var ship: Ship
	## True once _draw() has run.
	var painted := false

	## Paint the arcs view and the mark through ArcView.draw().
	func _draw() -> void:
		view.call("draw", self, ship, 1.0)
		painted = true


## Run ArcView.draw() on a Battlecruiser with the arcs cue on, from a node's _draw(). The case passes when
## the drawing code ran without an error (a script error would also show in the log); when the engine
## (headless) never calls _draw(), an INFO line says so.
func _draw_probe() -> void:
	if not ResourceLoader.exists("res://scripts/ui/arc_view.gd"):
		_case("draw: ArcView paints the wedges and the mark", false, "no ArcView script (the base build)")
		return
	var sc := _scene("battlecruiser", [Vector2(0.0, 1000.0)])
	var bc: Ship = sc[0]
	bc.set("arc_cue_t", 1.0)
	var probe := DrawProbe.new()
	probe.view = load("res://scripts/ui/arc_view.gd")
	probe.ship = bc
	add_child(probe)
	for _i in 3:
		probe.queue_redraw()
		await get_tree().process_frame
	if probe.painted:
		_case("draw: ArcView paints the wedges and the mark", true)
	else:
		print("broadside_check: INFO the engine never called _draw() in this run, so ArcView.draw was not run here")
	probe.queue_free()
	_clear(sc)


## The wedges, the arcs cue, the reticle mark and the reach line of the hangar card.
func _cases_item4() -> void:
	var av: Script = load("res://scripts/ui/arc_view.gd") if ResourceLoader.exists("res://scripts/ui/arc_view.gd") else null
	if av == null:
		for what in ["wedges: six on the Destroyer with Ctrl and none without", "the cue", "the mark"]:
			_case(what, false, "no ArcView script (the base build)")
	else:
		var sc := _scene("destroyer", [])
		var ds: Ship = sc[0]
		var on: Array = av.call("wedges", ds, true)
		var off: Array = av.call("wedges", ds, false)
		var reach_ok := on.size() == 6
		var heavy_n := 0
		var light_n := 0
		for w: Dictionary in on:
			var wid := _mount(ds, String(w["id"])).weapon_id
			if wid == "heavy_cannon":
				heavy_n += 1
				reach_ok = reach_ok and absf(float(w["reach"]) - Weapons.reach(Weapons.get_def("heavy_cannon")) * ds.range_mult) < 0.01
			elif wid == "light_turret":
				light_n += 1
				reach_ok = reach_ok and absf(float(w["reach"]) - Weapons.reach(Weapons.get_def("light_turret")) * ds.range_mult) < 0.01
		_case("wedges: six on the Destroyer with Ctrl (4 heavy and 2 chasers, at their reach) and none without", reach_ok and heavy_n == 4 and light_n == 2 and off.is_empty(), "%d wedges (%d heavy, %d light), %d without Ctrl" % [on.size(), heavy_n, light_n, off.size()])
		_clear(sc)
		sc = _scene("battlecruiser", [])
		var bc: Ship = sc[0]
		var bw: Array = av.call("wedges", bc, true)
		_case("wedges: eight on the Battlecruiser with Ctrl", bw.size() == 8, "%d wedges" % bw.size())
		# The cue: it starts on the tick the reticle leaves every main arc and is not restarted while it stays out.
		var starboard := _home + Vector2(0.0, 1000.0)
		var ahead := _home + Vector2(2000.0, 0.0)
		var prev: int = av.call("cue_tick", bc, starboard, 0)
		var cue_before := _f(bc, "arc_cue_t")
		prev = av.call("cue_tick", bc, ahead, prev)
		var cue_start := _f(bc, "arc_cue_t")
		_steps([bc], 10)
		var cue_mid := _f(bc, "arc_cue_t")
		prev = av.call("cue_tick", bc, ahead, prev)
		var cue_still := _f(bc, "arc_cue_t")
		_case("cue: the reticle leaving every arc sets the cue to 1 s, and it is not restarted while the reticle stays out", cue_before == 0.0 and cue_start == 1.0 and cue_mid < 1.0 and cue_still == cue_mid, "before %s, start %s, after 10 ticks %s, next call %s" % [str(cue_before), str(cue_start), str(cue_mid), str(cue_still)])
		var shown: Array = av.call("wedges", bc, false)
		_steps([bc], 60)
		var gone: Array = av.call("wedges", bc, false)
		_case("cue: the wedges show while it runs and are gone after 60 more ticks", shown.size() == 8 and gone.is_empty() and _f(bc, "arc_cue_t") == 0.0, "%d wedges at 10 ticks, %d after 70, cue %s" % [shown.size(), gone.size(), str(_f(bc, "arc_cue_t"))])
		_clear(sc)
		# The mark: side, how many guns bear, dim.
		var mark_ok := true
		var detail := ""
		for hid in ["destroyer", "battlecruiser"]:
			var ms := _scene(hid, [])
			var s: Ship = ms[0]
			var want_n := 2 if hid == "destroyer" else 3
			var mp: Dictionary = av.call("mark", s, _home + Vector2(0.0, -1000.0))
			var ms2: Dictionary = av.call("mark", s, _home + Vector2(0.0, 1000.0))
			var md: Dictionary = av.call("mark", s, _home + Vector2(2000.0, 0.0))
			var ok1: bool = int(mp["side"]) == -1 and int(mp["bearing"]) == want_n and not bool(mp["dim"])
			var ok2: bool = int(ms2["side"]) == 1 and int(ms2["bearing"]) == want_n and not bool(ms2["dim"])
			var ok3: bool = int(md["bearing"]) == 0 and bool(md["dim"])
			mark_ok = mark_ok and ok1 and ok2 and ok3
			detail += "%s port %s starboard %s ahead %s; " % [hid, str(mp), str(ms2), str(md)]
			_clear(ms)
		_case("mark: the side, the number of guns bearing and dim, for both hulls on both beams and dead ahead", mark_ok, detail)
	# The range bands on the hangar card.
	var dtext := HangarShips.card_text("destroyer")
	var btext := HangarShips.card_text("battlecruiser")
	_case("card: the Destroyer's card lists its reach with 1,353 and the Battlecruiser's with 1,600", dtext.contains("Reach:") and dtext.contains("1,353") and btext.contains("Reach:") and btext.contains("1,600"), "%s | %s" % [dtext.replace("\n", " / "), btext.replace("\n", " / ")])
	var card_bad: Array[String] = []
	for hid: String in Ships.ORDER:
		if hid == "destroyer" or hid == "battlecruiser":
			continue
		var d: Dictionary = Ships.HULLS[hid]
		var size_label: String = ["Strike craft", "Corvette", "Frigate", "Capital ship"][int(d["size"])]
		var sub := "%s\n%s" % [size_label, Ships.blurb(hid)]
		var times := FlightTimes.line_for(hid)
		var want_text := sub if times == "" else "%s\n%s" % [sub, times]
		if HangarShips.card_text(hid) != want_text:
			card_bad.append(hid)
	_case("control: the card text of every other hull is as it was", card_bad.is_empty(), str(card_bad))
