extends Node
## WHAT THIS IS: the check of the two capitals' shields and armour: the Destroyer and the
## Battlecruiser carry their own shield-share table (thin bow and stern), a focus change moves
## their caps over 3.0 s, and their bow and stern armour sections hold 0.6 of a side section.
## It prints one "capital_shield_check: PASS <name>" or "capital_shield_check: FAIL <name>: <what>"
## line per case, then "capital_shield_check: N checks, K failures" and, only when K is 0,
## "capital_shield_check: 0 failures".
##
## HOW IT WORKS: it freezes the match, launches real ships with no controller, steps
## ShieldZones.tick() and the Ship's own tick by hand, and sends hits through Unit.take_hit(), as
## shield_gate_check does. It names no new member of the game except through get(), so on a build
## without the capitals' table it prints FAIL lines and never fails to parse. The cases:
##   - (a) the capitals' table (written out here as a literal) at every focus, after a finished swing;
##   - (b) the controls: every other pilot hull keeps Rules.FOCUS_WEIGHTS and moves its zones at once;
##   - (c) the swing: the caps move in a straight line over 3.0 s (180 ticks), nothing is made or lost;
##   - (d) a change in mid-swing starts from the blended caps;
##   - (e) a hit in the swing drains only its zone, the swing goes on, a breaking hit gates as before;
##   - (f) the focus cooldown of a capital and of a Flak Frigate;
##   - (g) the stamp that tells the drawing the caps moved, and the drawing's own copy of the caps;
##   - (h) the zone boundary (the 45-degree rule) and two real hits either side of it;
##   - (i) the armour: bow and stern sections hold 0.6 of a side section, the pool is unchanged, and
##     the same shots wear a bow section out faster;
##   - (j) the computer pilot asks for the side the enemy stands on.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=capital_shield_check
##
## WHO USES IT: main.gd loads it for --test=capital_shield_check; run_checks runs it. It changes
## only units of a frozen match that is thrown away.

## One physics tick, in seconds.
const DT := 1.0 / 60.0
## The two capitals.
const CAPITALS := ["destroyer", "battlecruiser"]
## Every other pilot hull (the controls).
const OTHERS := ["scout", "fighter", "lance", "bomber", "logistics", "support", "flak", "ion"]
## The capitals' shield table, written out (never read from the hull rows): rows Balanced,
## Front, Rear, Left, Right, each [front, rear, left, right].
const TABLE := [
	[0.15, 0.15, 0.35, 0.35],
	[0.30, 0.10, 0.30, 0.30],
	[0.10, 0.30, 0.30, 0.30],
	[0.10, 0.10, 0.55, 0.25],
	[0.10, 0.10, 0.25, 0.55],
]
## The running match (set by setup()).
var world: World
## Where the ships stand: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## How many checks have run.
var checks := 0
## How many of them went wrong.
var failures := 0


## main.gd calls this once, right after the World is built. Freeze the match and start the run
## on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_case_table()
	_case_controls()
	_case_swing()
	_case_midswing()
	_case_hit()
	_case_cooldown()
	_case_stamp()
	_case_boundary()
	_case_armour()
	_case_computer()
	print("capital_shield_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("capital_shield_check: 0 failures")
	get_tree().quit()


## Count one check and print its line: PASS with `what`, or FAIL with `what` and the reason.
func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("capital_shield_check: PASS %s%s" % [label, (" (" + detail + ")") if detail != "" else ""])
	else:
		failures += 1
		print("capital_shield_check: FAIL %s: %s" % [label, detail])


## A member of `o` read by name (null-safe for a build that does not have it): `fallback` when absent.
func _g(o: Object, member: String, fallback: Variant) -> Variant:
	var v: Variant = o.get(member)
	return fallback if v == null else v


## Launch a pilot ship of hull `hid` (team 1) and stand it still at home, facing east, with its
## shields full and not just hit.
func _ship(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.shields.fill()
	s.shields.since_hit = 999.0
	return s


## Take a ship out of the match.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()


## A hit note for a shot from `local` (the ship's own frame, ship at home facing east).
func _note(local: Vector2) -> DamageInfo:
	var d := DamageInfo.new()
	d.kind = Rules.W_BOLT
	d.from_pos = _home + local
	d.pierce = 0.0
	return d


## The share of a raw hit a shield of ship `s` lets drain its zone (its resistance).
func _keep(s: Unit) -> float:
	return 1.0 - clampf(s.shields.resist + s.shield_resist_bonus(), 0.0, 0.9)


## The four caps of `sh` as shares of its total.
func _ratios(sh: ShieldZones) -> Array:
	var out: Array = []
	for z in 4:
		out.append(sh.cap(z) / sh.max_total)
	return out


## True when the four numbers of `a` are within `tol` of those of `b`.
func _close(a: Array, b: Array, tol: float) -> bool:
	for z in 4:
		if absf(float(a[z]) - float(b[z])) > tol:
			return false
	return true


## The largest amount any zone of `sh` holds above its cap.
func _over(sh: ShieldZones) -> float:
	var m := 0.0
	for z in 4:
		m = maxf(m, sh.values[z] - sh.cap(z))
	return m


## Put `sh` at Balanced, full, then ask for focus `f` (a no-op for Balanced).
func _reset_to(sh: ShieldZones, f: int) -> void:
	sh.focus = Rules.FOCUS_BALANCED
	sh.fill()
	sh.set_focus(f)


## (a) The table: each capital at Balanced, and at each focus after a finished swing.
func _case_table() -> void:
	for hid: String in CAPITALS:
		var s := _ship(hid)
		var sh := s.shields
		var got := _ratios(sh)
		_check("a table %s Balanced at launch" % hid, _close(got, TABLE[0], 1.0e-6), "caps %s, wanted %s" % [got, TABLE[0]])
		for f in 5:
			_reset_to(sh, f)
			for _i in 200:
				sh.tick(DT, 1.0)
			var r := _ratios(sh)
			var sum := sh.cap(0) + sh.cap(1) + sh.cap(2) + sh.cap(3)
			_check("a table %s focus %d" % [hid, f], _close(r, TABLE[f], 1.0e-6) and absf(sum - sh.max_total) < 1.0e-3, "caps %s, wanted %s, sum %.3f of %.3f" % [r, TABLE[f], sum, sh.max_total])
		_put(s)


## (b) The controls: every other pilot hull keeps the global table and moves its zones at once.
func _case_controls() -> void:
	for hid: String in OTHERS:
		var s := _ship(hid)
		var sh := s.shields
		var ok_caps := true
		var ok_instant := true
		for f in 5:
			_reset_to(sh, f)
			var want: Array = Rules.FOCUS_WEIGHTS[f]
			if not _close(_ratios(sh), want, 1.0e-6):
				ok_caps = false
			for z in 4:
				if absf(sh.values[z] - sh.cap(z)) > 1.0e-3:
					ok_instant = false
		_reset_to(sh, Rules.FOCUS_LEFT)
		_check("b control %s table" % hid, ok_caps, "Left row caps %s, Rules.FOCUS_WEIGHTS Left %s" % [_ratios(sh), Rules.FOCUS_WEIGHTS[Rules.FOCUS_LEFT]])
		_check("b control %s instant move" % hid, ok_instant, "values %s, caps %.1f %.1f %.1f %.1f right after set_focus" % [sh.values, sh.cap(0), sh.cap(1), sh.cap(2), sh.cap(3)])
		_put(s)


## (c) The swing on a Battlecruiser: Balanced to Left over 180 ticks, a straight line, nothing made or lost.
func _case_swing() -> void:
	var s := _ship("battlecruiser")
	var sh := s.shields
	var tot0 := sh.total()
	var v0: Array = Array(sh.values)
	sh.set_focus(Rules.FOCUS_LEFT)
	var r0: float = sh.cap(Rules.ZONE_LEFT) / sh.max_total
	var still := true
	for z in 4:
		if absf(sh.values[z] - float(v0[z])) > 1.0e-3:
			still = false
	_check("c swing start", sh.focus == Rules.FOCUS_LEFT and absf(r0 - 0.35) <= 0.005 and still, "focus %d, Left cap share %.4f (wanted 0.35), zone values moved: %s" % [sh.focus, r0, not still])
	var r90 := -1.0
	var r180 := -1.0
	var r300 := -1.0
	var end_tick := -1
	var drift := 0.0
	var over := 0.0
	for n in range(1, 301):
		sh.tick(DT, 1.0)
		if n == 90:
			r90 = sh.cap(Rules.ZONE_LEFT) / sh.max_total
		if n == 180:
			r180 = sh.cap(Rules.ZONE_LEFT) / sh.max_total
		if n == 300:
			r300 = sh.cap(Rules.ZONE_LEFT) / sh.max_total
		over = maxf(over, _over(sh))
		if n % 10 == 0:
			drift = maxf(drift, absf(sh.total() - tot0))
		if end_tick < 0 and float(_g(sh, "swing_left", 1.0)) <= 0.0:
			end_tick = n
	_check("c swing at 90 ticks", absf(r90 - 0.45) <= 0.005, "Left cap share %.4f (wanted 0.45 within 0.005)" % r90)
	_check("c swing ends at 180 ticks", end_tick >= 179 and end_tick <= 181, "the swing ended at tick %d (wanted 179 to 181)" % end_tick)
	_check("c swing end and stays", absf(r180 - 0.55) <= 1.0e-4 and absf(r300 - 0.55) <= 1.0e-4, "Left cap share %.4f at 180 and %.4f at 300 (wanted 0.55)" % [r180, r300])
	_check("c swing keeps the total", end_tick >= 179 and drift <= 1.0e-3, "largest total drift %.5f at a tenth tick (swing ended at %d)" % [drift, end_tick])
	_check("c swing no zone over its cap", end_tick >= 179 and over <= 1.0e-3, "largest excess over a cap %.5f (swing ended at %d)" % [over, end_tick])
	_put(s)


## (d) A change in mid-swing starts from the blended caps and runs a straight line.
func _case_midswing() -> void:
	var s := _ship("battlecruiser")
	var sh := s.shields
	sh.set_focus(Rules.FOCUS_LEFT)
	for _i in 90:
		sh.tick(DT, 1.0)
	sh.set_focus(Rules.FOCUS_RIGHT)
	var l0: float = sh.cap(Rules.ZONE_LEFT) / sh.max_total
	var rt0: float = sh.cap(Rules.ZONE_RIGHT) / sh.max_total
	_check("d mid-swing start", absf(l0 - 0.45) <= 0.005, "Left cap share %.4f right after the second change (wanted 0.45), Right %.4f" % [l0, rt0])
	for _i in 90:
		sh.tick(DT, 1.0)
	var l90: float = sh.cap(Rules.ZONE_LEFT) / sh.max_total
	_check("d mid-swing straight line", absf(l90 - 0.35) <= 0.005, "Left cap share %.4f 90 ticks into the second swing (wanted 0.35, the middle of 0.45 and 0.25)" % l90)
	for _i in 100:
		sh.tick(DT, 1.0)
	var l_end: float = sh.cap(Rules.ZONE_LEFT) / sh.max_total
	var r_end: float = sh.cap(Rules.ZONE_RIGHT) / sh.max_total
	_check("d mid-swing end", absf(l_end - 0.25) <= 1.0e-4 and absf(r_end - 0.55) <= 1.0e-4, "Left %.4f (wanted 0.25), Right %.4f (wanted 0.55)" % [l_end, r_end])
	_put(s)


## (e) A hit in the swing, and a hit that breaks a zone.
func _case_hit() -> void:
	var s := _ship("battlecruiser")
	var sh := s.shields
	sh.set_focus(Rules.FOCUS_LEFT)
	for _i in 30:
		sh.tick(DT, 1.0)
	var v0: Array = Array(sh.values)
	var raw := 100.0
	s.take_hit(_note(Vector2(300.0, 0.0)), raw)
	var drained: float = float(v0[Rules.ZONE_FRONT]) - sh.values[Rules.ZONE_FRONT]
	var others_same := true
	for z in [Rules.ZONE_REAR, Rules.ZONE_LEFT, Rules.ZONE_RIGHT]:
		if absf(sh.values[z] - float(v0[z])) > 1.0e-3:
			others_same = false
	_check("e hit drains only its zone", absf(drained - raw * _keep(s)) < 0.05 and others_same, "front drained %.3f (wanted %.3f), the other zones unchanged: %s" % [drained, raw * _keep(s), others_same])
	var sl0 := float(_g(sh, "swing_left", 0.0))
	sh.tick(DT, 1.0)
	var sl1 := float(_g(sh, "swing_left", 0.0))
	_check("e swing goes on after a hit", sl0 > 0.0 and sl1 < sl0, "swing_left %.4f then %.4f one tick after the hit (during the wait for the refill)" % [sl0, sl1])
	for _i in 200:
		sh.tick(DT, 1.0)
	var end_r: Array = _ratios(sh)
	_check("e swing reaches the same end caps", _close(end_r, TABLE[Rules.FOCUS_LEFT], 1.0e-4) and _over(sh) <= 1.0e-3, "caps %s, wanted %s, excess over a cap %.5f" % [end_r, TABLE[Rules.FOCUS_LEFT], _over(sh)])
	_put(s)
	# A hit that breaks the front zone: its gate is gate_seconds(), with no swing and in a swing.
	var a := _ship("battlecruiser")
	a.take_hit(_note(Vector2(300.0, 0.0)), a.shields.values[Rules.ZONE_FRONT] / _keep(a) * 1.6)
	var ga: float = a.shields.gate_left[Rules.ZONE_FRONT]
	_check("e break gate no swing", absf(ga - a.shields.gate_seconds()) < 1.0e-4 and absf(ga - 2.25) < 1.0e-4, "gate %.4f, gate_seconds() %.4f (the Battlecruiser's longest gate is 2.25)" % [ga, a.shields.gate_seconds()])
	var b := _ship("battlecruiser")
	b.shields.set_focus(Rules.FOCUS_LEFT)
	for _i in 30:
		b.shields.tick(DT, 1.0)
	b.take_hit(_note(Vector2(300.0, 0.0)), b.shields.values[Rules.ZONE_FRONT] / _keep(b) * 1.6)
	var gb: float = b.shields.gate_left[Rules.ZONE_FRONT]
	_check("e break gate in a swing", absf(gb - b.shields.gate_seconds()) < 1.0e-4, "gate %.4f, gate_seconds() %.4f" % [gb, b.shields.gate_seconds()])
	_put(a)
	_put(b)


## (f) The focus cooldown after a press through the ship's own path: the class value times the
## redirect factor, for a Battlecruiser and (control) a Flak Frigate.
func _case_cooldown() -> void:
	for hid: String in ["battlecruiser", "flak"]:
		var s := _ship(hid)
		s.focus_cd = 0.0
		s.controls.focus_request = Rules.FOCUS_LEFT
		s.sim_update(DT)
		var cd := s.focus_cd
		var want := float(Rules.FOCUS_COOLDOWN[s.size_class]) * maxf(0.2, s.stats.mul("redirect_cd_pct"))
		_check("f cooldown %s" % hid, s.shields.focus == Rules.FOCUS_LEFT and absf(cd - want) < 1.0e-4, "focus %d, focus_cd %.4f, wanted %.4f (class value %.1f)" % [s.shields.focus, cd, want, float(Rules.FOCUS_COOLDOWN[s.size_class])])
		_put(s)


## (g) The stamp: still over idle ticks, new on every tick of a swing and on the press; the
## drawing's own copy of the caps follows a swing.
func _case_stamp() -> void:
	var s := _ship("battlecruiser")
	var sh := s.shields
	var st0: Variant = sh.get("caps_stamp")
	if st0 == null:
		_check("g stamp exists", false, "ShieldZones has no caps_stamp")
	else:
		for _i in 120:
			sh.tick(DT, 1.0)
		_check("g stamp idle", int(sh.get("caps_stamp")) == int(st0), "stamp %s then %s after 120 idle ticks" % [st0, sh.get("caps_stamp")])
		var before := int(sh.get("caps_stamp"))
		s.focus_cd = 0.0
		s.controls.focus_request = Rules.FOCUS_LEFT
		s.sim_update(DT)
		var after := int(sh.get("caps_stamp"))
		_check("g stamp on the press", after != before, "stamp %d then %d over the press (one Ship tick)" % [before, after])
		var every := true
		var last := int(sh.get("caps_stamp"))
		for _i in 20:
			sh.tick(DT, 1.0)
			var now_stamp := int(sh.get("caps_stamp"))
			if now_stamp == last:
				every = false
			last = now_stamp
		_check("g stamp every swing tick", every, "the stamp changed on each of 20 ticks of a swing: %s" % every)
	_put(s)
	# The drawing's copy of the caps (ShipVisual keeps _caps and refreshes it by the stamp).
	var t := _ship("battlecruiser")
	var v := t.get_node_or_null("Visual") as ShipVisual
	var cache: Variant = v.get("_shield") if v != null else null
	if v == null or cache == null:
		print("capital_shield_check: NOT DONE: draw cache (no ship visual or shield picture in this run: visual %s)" % [v != null])
	else:
		t.shields.set_focus(Rules.FOCUS_LEFT)
		v._update_shield(1.0)
		for _i in 90:
			t.shields.tick(DT, 1.0)
		v._update_shield(1.0)
		var caps: Variant = v.get("_caps")
		var seen: float = float(caps[Rules.ZONE_LEFT]) if caps != null else -1.0
		var now_cap: float = t.shields.cap(Rules.ZONE_LEFT)
		_check("g drawing copy follows the swing", caps != null and absf(seen - now_cap) < 1.0e-3 and v.get("_caps_stamp") != null and int(v.get("_caps_stamp")) == int(_g(t.shields, "caps_stamp", -2)), "the drawing's Left cap %.3f, the shield's %.3f, drawing stamp %s, shield stamp %s" % [seen, now_cap, v.get("_caps_stamp"), _g(t.shields, "caps_stamp", "none")])
	_put(t)


## (h) The zone boundary: the 45-degree rule, written out, and two real hits at 44 and 46 degrees.
func _case_boundary() -> void:
	var want := {44.0: Rules.ZONE_FRONT, 46.0: Rules.ZONE_RIGHT, 134.0: Rules.ZONE_RIGHT, 136.0: Rules.ZONE_REAR, -44.0: Rules.ZONE_FRONT, -46.0: Rules.ZONE_LEFT, -134.0: Rules.ZONE_LEFT, -136.0: Rules.ZONE_REAR}
	var bad: Array = []
	for deg: float in want.keys():
		var z := ShieldZones.zone_for_local(Vector2.from_angle(deg_to_rad(deg)))
		if z != int(want[deg]):
			bad.append("%d gave zone %d, wanted %d" % [int(deg), z, int(want[deg])])
	_check("h zone_for_local at the boundary", bad.is_empty(), "; ".join(bad) if not bad.is_empty() else "eight bearings read as the 45-degree rule says")
	var s := _ship("battlecruiser")
	var row: Dictionary = Ships.HULLS["battlecruiser"]
	var bow := Vector2(float(row["spine_off"]) + float(row["spine"]) / 2.0, 0.0)
	var r := float(row["hit_r"]) + 100.0
	var v0: Array = Array(s.shields.values)
	s.take_hit(_note(bow + r * Vector2.from_angle(deg_to_rad(44.0))), 100.0)
	var d_front: float = float(v0[Rules.ZONE_FRONT]) - s.shields.values[Rules.ZONE_FRONT]
	var d_right: float = float(v0[Rules.ZONE_RIGHT]) - s.shields.values[Rules.ZONE_RIGHT]
	_check("h hit at 44 degrees drains Front", d_front > 1.0 and absf(d_right) < 1.0e-3, "front drained %.3f, right %.3f" % [d_front, d_right])
	var v1: Array = Array(s.shields.values)
	s.take_hit(_note(bow + r * Vector2.from_angle(deg_to_rad(46.0))), 100.0)
	var d_front2: float = float(v1[Rules.ZONE_FRONT]) - s.shields.values[Rules.ZONE_FRONT]
	var d_right2: float = float(v1[Rules.ZONE_RIGHT]) - s.shields.values[Rules.ZONE_RIGHT]
	_check("h hit at 46 degrees drains Right", d_right2 > 1.0 and absf(d_front2) < 1.0e-3, "right drained %.3f, front %.3f" % [d_right2, d_front2])
	_put(s)


## Hit section `i` of ship `s` with the same shot until it is black. The hits it took, or -1 when
## the cap of 500 was reached (a glancing shot wears nothing: that is a failure, not a hang).
func _wear(s: Ship, i: int) -> int:
	var n := 0
	while s.armour.a_hp[i] > 0 and n < 500:
		s.armour.hit(i, 15.0, 100.0)
		n += 1
	return n if s.armour.a_hp[i] <= 0 else -1


## (i) The armour: the 0.6 ratio, the pool, the controls and the wear.
func _case_armour() -> void:
	for hid: String in CAPITALS:
		var s := _ship(hid)
		var ar: ArmourSections = s.armour
		var want_count := 10 if hid == "destroyer" else 12
		_check("i armour %s count" % hid, ar.count == want_count, "%d sections, wanted %d" % [ar.count, want_count])
		var side0: int = ar.zone_first[Rules.ZONE_LEFT]
		var worst := 0
		for z in [Rules.ZONE_FRONT, Rules.ZONE_REAR]:
			for k in ar.zone_count[z]:
				var e: int = ar.zone_first[z] + k
				for sd in range(side0, ar.count):
					worst = maxi(worst, absi(ar.a_max[e] * 5 - ar.a_max[sd] * 3))
		_check("i armour %s end sections are 0.6 of a side" % hid, worst <= 5, "largest |end x 5 - side x 3| is %d (wanted 5 or less); end %d, side %d" % [worst, ar.a_max[0], ar.a_max[side0]])
		var total := 0
		for k in ar.count:
			total += ar.a_max[k]
		var pool := int(s.hull_max * float(ArmourSections.ARMOUR_SHARE_PCT) * float(ArmourSections.UNITS_PER_POINT) / 100.0)
		_check("i armour %s pool unchanged" % hid, absi(total - pool) <= ar.count, "the sections add up to %d, the pool is %d (within %d)" % [total, pool, ar.count])
		_put(s)
	for hid: String in OTHERS:
		var s := _ship(hid)
		var ar: ArmourSections = s.armour
		var plain: bool = not Ships.HULLS[hid].has("section_weights")
		var lo: int = ar.a_max[0]
		var hi: int = ar.a_max[0]
		for k in ar.count:
			lo = mini(lo, ar.a_max[k])
			hi = maxi(hi, ar.a_max[k])
		_check("i armour control %s equal sections" % hid, plain and hi - lo <= 1, "the sections hold %d to %d, no section_weights: %s" % [lo, hi, plain])
		_put(s)
	var bc := _ship("battlecruiser")
	var bow_i: int = bc.armour.zone_first[Rules.ZONE_FRONT]
	var side_i: int = bc.armour.zone_first[Rules.ZONE_LEFT]
	var n_bow := _wear(bc, bow_i)
	var bc2 := _ship("battlecruiser")
	var n_side := _wear(bc2, side_i)
	var ratio := float(n_bow) / float(n_side) if n_bow > 0 and n_side > 0 else -1.0
	_check("i armour a bow section wears out faster", n_bow > 0 and n_side > 0 and ratio >= 0.4 and ratio <= 0.8, "hits to black: bow %d, side %d (-1 = the cap of 500 reached), ratio %.3f (wanted 0.4 to 0.8)" % [n_bow, n_side, ratio])
	_put(bc)
	_put(bc2)


## (j) The computer: an AI Destroyer with the enemy on its port beam asks for Left, with the enemy
## dead ahead for Front (the rule in PilotSystems is unchanged by the capitals' table).
func _case_computer() -> void:
	var home := Vector2(MapLayout.CX, MapLayout.H * 0.3)
	var p := PilotProfile.new("c3-destroyer", 0, 300 + world.profiles.size(), false)
	p.hull_id = "destroyer"
	p.role = "mid"
	world.profiles.append(p)
	var brain := PilotAI.new(world, p)
	world.pilot_ai[p] = brain
	var s := world.launch(p)
	var ep := PilotProfile.new("c3-enemy", 1, 300 + world.profiles.size(), false)
	ep.hull_id = "fighter"
	world.profiles.append(ep)
	var e := world.launch(ep)
	e.controller = null
	var asked: Array = []
	for offset: Vector2 in [Vector2(0.0, -500.0), Vector2(700.0, 0.0)]:
		s.global_position = home
		s.rotation = 0.0
		s.hull = s.hull_max
		s.last_damage_time = -999.0
		s.shields.focus = Rules.FOCUS_BALANCED
		brain.skill = 0.9
		brain.state = "lane"
		brain.target = null
		brain.goal = home
		e.global_position = home + offset
		world.registry.rebuild_hashes()
		s.controls.focus_request = -1
		brain.systems.set_energy_and_shields(s)
		asked.append(s.controls.focus_request)
	_check("j computer asks Left for an enemy on the port beam", asked[0] == Rules.FOCUS_LEFT, "focus_request %d (Left is %d)" % [asked[0], Rules.FOCUS_LEFT])
	_check("j computer asks Front for an enemy dead ahead", asked[1] == Rules.FOCUS_FRONT, "focus_request %d (Front is %d)" % [asked[1], Rules.FOCUS_FRONT])
	_put(s)
	_put(e)
