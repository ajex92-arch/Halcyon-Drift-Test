extends Node
## WHAT THIS IS: the check of the gun kick (GunKick, TurretPaint, AurelianPaint, ShipVisual):
## when a gun fires its drawn barrel kicks back and slides home, bigger guns further and
## slower, and all of it is drawing only: the match is not touched and the shared random
## numbers stay where they were.
##
## HOW IT WORKS: setup() freezes the match and then checks, in this order:
##   1. the table: every weapon class has a row, no row lasts longer than GunKick.MAX_TIME,
##      the bigger the gun the further and the slower it kicks, and the nose guns' rows
##      name real weapons;
##   2. the curve: the full distance at the shot, less and less after, none after the
##      time of its row (and none for a shot that has not happened);
##   3. the seeing of shots, with stand-in guns: a cooldown that jumps up is a shot, one
##      that counts down is not, the first look and a look after a long gap or a clock that
##      went back never find a shot, a burst beam's start is a shot and a continuous beam
##      is not, and looking changes nothing in the gun;
##   4. the dice: the shared random sequence after all that is where it was;
##   5. the pictures' arrays: a turret's four layers make up exactly the triangles it had
##      before the kick, and kicking moves only the points of its barrels and tip (and of
##      the nose guns of the Scout and the Fighter), by the slide, in the same single
##      array of points, so a kicking gun costs no more drawing commands than a still one;
##   6. real ships: a Fighter, a Scout and a Battlecruiser of both teams are launched, a shot
##      is made up in the match clock and a stand-in cooldown, and each painter (in a few
##      drawn frames) sees it and ages it with the clock. Nothing in the ship changes.
## It prints one line per check ("PASS ..." or "FAIL ...") and then
## "gun_kick_check: N failures" (0 means every check passed).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=gun_kick_check
## (Not with --sim-only: that draws nothing and the painters do not look at the guns.)
##
## WHO USES IT: main.gd loads it for --test=gun_kick_check. It changes only a frozen match
## that is thrown away.

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Run every check and quit.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Every check, then the verdict.
func _run() -> void:
	for _i in 3:
		await get_tree().process_frame
	if Game.sim_only:
		_check("run without --sim-only (it draws nothing and the painters do not look)", false)
	_table()
	_curve()
	_seeing()
	_dice()
	_arrays()
	await _ships()
	print("gun_kick_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed) and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Check 1: the table.
func _table() -> void:
	var rows_ok := true
	for cls: String in TurretShapes.CLASSES:
		var row: Dictionary = GunKick.TURRET.get(cls, {})
		rows_ok = rows_ok and not row.is_empty() and float(row["time"]) < GunKick.MAX_TIME and float(row["dist"]) > 0.0
	_check("every weapon class has a kick row under MAX_TIME", rows_ok)
	var t: Dictionary = GunKick.TURRET
	_check("a bigger gun kicks further: point defense < light turret < torpedo turret < ion turret < heavy cannon",
		float(t["pd"]["dist"]) < float(t["light"]["dist"]) and float(t["light"]["dist"]) < float(t["torp"]["dist"]) and float(t["torp"]["dist"]) < float(t["ion"]["dist"]) and float(t["ion"]["dist"]) < float(t["heavy"]["dist"]))
	_check("a bigger gun kicks slower: point defense < light turret < torpedo turret < ion turret < heavy cannon",
		float(t["pd"]["time"]) < float(t["light"]["time"]) and float(t["light"]["time"]) < float(t["torp"]["time"]) and float(t["torp"]["time"]) < float(t["ion"]["time"]) and float(t["ion"]["time"]) < float(t["heavy"]["time"]))
	var fixed_ok := true
	for wid: String in GunKick.FIXED:
		var row: Dictionary = GunKick.FIXED[wid]
		fixed_ok = fixed_ok and Weapons.WEAPONS.has(wid) and float(row["time"]) < GunKick.MAX_TIME and float(row["dist"]) > 0.0
	_check("the nose guns' rows name real weapons and last under MAX_TIME", fixed_ok)
	_check("the Fighter's twin cannons kick a little more than the Scout's gun", float(GunKick.FIXED["fighter_cannon"]["dist"]) >= float(GunKick.FIXED["scout_gun"]["dist"]))
	_check("the flash is shorter than the shortest kick", GunKick.FLASH_TIME < float(t["pd"]["time"]))


## Check 2: the curve.
func _curve() -> void:
	var full: float = GunKick.TURRET["heavy"]["dist"]
	var span: float = GunKick.TURRET["heavy"]["time"]
	_check("the heavy cannon's barrel is back by the full distance at the shot", absf(GunKick.turret_back("heavy", 0.0) - full) < 0.0001)
	var last := full + 1.0
	var falling := true
	for i in 12:
		var d := GunKick.turret_back("heavy", span * float(i) / 12.0)
		falling = falling and d < last
		last = d
	_check("and slides home, less and less", falling)
	_check("home after its time, and for a shot long ago or not yet fired", GunKick.turret_back("heavy", span) == 0.0 and GunKick.turret_back("heavy", 5.0) == 0.0 and GunKick.turret_back("heavy", -1.0) == 0.0 and GunKick.turret_back("heavy", GunKick.NEVER) == 0.0)
	_check("an unknown weapon class or weapon does not kick", GunKick.turret_back("nonsense", 0.0) == 0.0 and GunKick.fixed_back("nonsense", 0.0) == 0.0)
	_check("a nose gun kicks by its row", absf(GunKick.fixed_back("fighter_cannon", 0.0) - float(GunKick.FIXED["fighter_cannon"]["dist"])) < 0.0001)
	_check("the flash is on for the first moment only", GunKick.is_flash(0.0) and not GunKick.is_flash(GunKick.FLASH_TIME) and not GunKick.is_flash(-1.0) and not GunKick.is_flash(GunKick.NEVER))


## Check 3: the seeing of shots, with stand-in guns that belong to nothing.
func _seeing() -> void:
	var gun := WeaponMount.new(null, "fighter_cannon", "fixed", Vector2.ZERO, 0.0)
	var k := GunKick.new()
	var list: Array = [gun]
	k.look_all(list, 10.0)
	_check("the first look finds no shot", k.ages[0] > GunKick.MAX_TIME and k.fixed_weapon == "fighter_cannon" and k.fixed_age > GunKick.MAX_TIME)
	gun.cd = 0.15
	k.look_all(list, 10.02)
	_check("a cooldown that jumped up is a shot, seen at once", k.ages[0] == 0.0 and k.fixed_age == 0.0)
	gun.cd = 0.09
	k.look_all(list, 10.08)
	_check("a cooldown counting down is not a new shot, and the shot ages with the clock", absf(k.ages[0] - 0.06) < 0.0001)
	gun.cd = 0.0
	k.look_all(list, 10.3)
	_check("ready again: the shot is old", absf(k.ages[0] - 0.28) < 0.0001)
	gun.cd = 0.15
	k.look_all(list, 10.32)
	_check("the next shot starts the kick again", k.ages[0] == 0.0)
	# A long gap: the gun is mid-cooldown when the painter looks again.
	gun.cd = 0.0
	k.look_all(list, 10.34)
	gun.cd = 0.1
	k.look_all(list, 13.0)
	_check("after a long gap the first look finds no shot", k.ages[0] > GunKick.MAX_TIME)
	# The clock went back (a new match in the same run).
	gun.cd = 0.1
	k.look_all(list, 2.0)
	_check("a clock that went back starts over and finds no shot", k.ages[0] > GunKick.MAX_TIME)
	# Switched off: every gun sits still.
	GunKick.set_on(false)
	gun.cd = 0.0
	k.look_all(list, 2.02)
	gun.cd = 0.15
	k.look_all(list, 2.04)
	var off_still: bool = k.ages[0] > GunKick.MAX_TIME
	GunKick.set_on(true)
	_check("switched off: no gun kicks", off_still)
	# A burst beam (the ion turret) kicks when a burst starts; a continuous beam never does.
	var ion := WeaponMount.new(null, "ion_turret", "turret", Vector2.ZERO, 140.0)
	var lance := WeaponMount.new(null, "lance_beam", "fixed", Vector2.ZERO, 0.0)
	var k2 := GunKick.new()
	var beams: Array = [ion, lance]
	k2.look_all(beams, 20.0)
	ion.beam_on = 2.5
	lance.beam_firing = true
	k2.look_all(beams, 20.02)
	_check("a burst beam's start is a shot", k2.ages[0] == 0.0)
	_check("a continuous beam is never a shot", k2.ages[1] > GunKick.MAX_TIME)
	ion.beam_on = 2.3
	k2.look_all(beams, 20.2)
	_check("a burst counting down is not a new shot", absf(k2.ages[0] - 0.18) < 0.0001)
	# Looking changes nothing in the gun.
	var before := [gun.cd, gun.beam_on, gun.angle, gun.next_mult, gun.engaged]
	k.look_all(list, 2.1)
	k.look_all(list, 2.2)
	var after := [gun.cd, gun.beam_on, gun.angle, gun.next_mult, gun.engaged]
	_check("looking at a gun changes nothing in it", before == after, str(before))


## Check 4: the dice. The shared random sequence after the looking and the curves is
## the one a plain run gives.
func _dice() -> void:
	seed(4242)
	var plain: Array = [randi(), randi(), randi()]
	seed(4242)
	var gun := WeaponMount.new(null, "heavy_cannon", "turret", Vector2.ZERO, 150.0)
	var k := GunKick.new()
	var list: Array = [gun]
	for i in 200:
		gun.cd = 1.4 if i % 40 == 0 else maxf(0.0, gun.cd - 0.016)
		k.look_all(list, float(i) * 0.016)
		GunKick.turret_back("heavy", k.ages[0])
		GunKick.is_flash(k.ages[0])
	var got: Array = [randi(), randi(), randi()]
	_check("the dice: looking and the curves leave the next three random numbers where they were", got == plain, "%s against %s" % [str(got), str(plain)])


## The old way of making a turret (before the layers): the rim of every base, the rim of
## every barrel, the barrels, the base, the cap, the tip, all in one set of arrays. The
## layered turret must be these triangles exactly.
func _old_turret(spec: Dictionary, style: String, rim: Color, cls: String) -> Dictionary:
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	var cols := PackedColorArray()
	var vhorr := style == "vhorr"
	var base_col := Palette.CINDER_SHADE if vhorr else Palette.TURRET_AUREL_BASE
	var cap_col := Palette.CINDER_PLATE if vhorr else Palette.TURRET_AUREL_CAP
	var barrel_col := Palette.TURRET_CINDER_BARREL if vhorr else Palette.TURRET_AUREL_BARREL
	for group: String in ["base", "barrels"]:
		for poly: Array in spec[group]:
			for grown: PackedVector2Array in Geometry2D.offset_polygon(PackedVector2Array(poly), TurretPaint.RIM, Geometry2D.JOIN_ROUND):
				TurretPaint._add(grown, Palette.with_alpha(rim, 0.9), pts, idx, cols)
	for poly: Array in spec["barrels"]:
		TurretPaint._add(PackedVector2Array(poly), barrel_col, pts, idx, cols)
	for poly: Array in spec["base"]:
		TurretPaint._add(PackedVector2Array(poly), base_col, pts, idx, cols)
	for poly: Array in spec["cap"]:
		TurretPaint._add(PackedVector2Array(poly), cap_col, pts, idx, cols)
	for poly: Array in spec["accent"]:
		TurretPaint._add(PackedVector2Array(poly), TurretShapes.ACCENT[cls], pts, idx, cols)
	return {"pts": pts, "idx": idx, "cols": cols}


## Check 5: the arrays of the pictures.
func _arrays() -> void:
	var same := 0
	var layers_ok := 0
	var moves_ok := 0
	var total := 0
	# A turret placed at (10, 5), turned and made 3 times as big; its barrels slid back 0.5.
	var at := Transform2D(0.7, Vector2(3.0, 3.0), 0.0, Vector2(10.0, 5.0))
	var back := at.translated_local(Vector2(-0.5, 0.0))
	var slid := at.basis_xform(Vector2(-0.5, 0.0))
	for team in [Rules.HALCYON, Rules.CINDER]:
		var style := "vhorr" if team == Rules.CINDER else "aurelian"
		for cls: String in TurretShapes.CLASSES:
			var spec: Dictionary = TurretShapes.VHORR[cls] if style == "vhorr" else TurretShapes.AURELIAN[cls]
			var rec := TurretPaint.turret(cls, team)
			var old := _old_turret(spec, style, Palette.team(team), cls)
			total += 1
			if rec["pts"] == old["pts"] and rec["idx"] == old["idx"] and rec["cols"] == old["cols"]:
				same += 1
			# The four layers make up the whole, and the flash has a colour for every point.
			var layers: Array = rec["layers"]
			var n := 0
			for layer: PackedVector2Array in layers:
				n += layer.size()
			var pts: PackedVector2Array = rec["pts"]
			if layers.size() == 4 and n == pts.size() and (rec["cols_hot"] as PackedColorArray).size() == (rec["cols"] as PackedColorArray).size():
				layers_ok += 1
			# Not kicking, the points are the whole turret's; kicking, only the barrels and the tip move,
			# and by the slide.
			var plain := TurretPaint.kicked_points(rec, at, at)
			var kicked := TurretPaint.kicked_points(rec, at, back)
			var first_gun: int = (layers[0] as PackedVector2Array).size()
			var after_gun: int = first_gun + (layers[1] as PackedVector2Array).size()
			var first_tip: int = after_gun + (layers[2] as PackedVector2Array).size()
			var ok := plain == at * pts and kicked.size() == pts.size()
			for i in pts.size():
				var moves := (i >= first_gun and i < after_gun) or i >= first_tip
				var want: Vector2 = plain[i] + (slid if moves else Vector2.ZERO)
				ok = ok and kicked[i].distance_to(want) < 0.0001
			if ok:
				moves_ok += 1
	_check("every turret of both teams is exactly the triangles it had before the layers", same == total, "%d of %d" % [same, total])
	_check("its four layers make up the whole, and the flash has a colour for every point", layers_ok == total, "%d of %d" % [layers_ok, total])
	_check("not kicking its points are the whole turret's; kicking, only the barrels and the tip move, by the slide", moves_ok == total, "%d of %d" % [moves_ok, total])
	var kickers := 0
	var split_ok := 0
	var xf := Transform2D(0.3, Vector2(2.0, 2.0), 0.0, Vector2(7.0, 1.0))
	var guns_at := xf.translated_local(Vector2(-1.5, 0.0))
	var guns_slid := xf.basis_xform(Vector2(-1.5, 0.0))
	for hid: String in Ships.ORDER:
		var rec := AurelianPaint.hull(hid)
		var kick: Dictionary = rec["kick"]
		if kick.is_empty():
			continue
		kickers += 1
		var pts: PackedVector2Array = rec["pts"]
		var plain := AurelianPaint.kicked_points(rec, xf, xf)
		var kicked := AurelianPaint.kicked_points(rec, xf, guns_at)
		var moved := 0
		var others_ok := true
		for i in pts.size():
			var d: Vector2 = kicked[i] - plain[i]
			if d.length() > 0.0001:
				moved += 1
				others_ok = others_ok and d.distance_to(guns_slid) < 0.0001
		var gun_points := 0
		for seg: Array in kick["segs"]:
			gun_points += (seg[0] as PackedVector2Array).size() if seg[1] else 0
		if plain == xf * pts and kicked.size() == pts.size() and others_ok and moved == gun_points and moved > 0 and (kick["cols_hot"] as PackedColorArray).size() == (rec["cols"] as PackedColorArray).size() and (kick["gun_segs"] as PackedVector2Array).size() % 2 == 0 and not (kick["gun_segs"] as PackedVector2Array).is_empty():
			split_ok += 1
	_check("exactly the Scout and the Fighter have nose guns that kick", kickers == 2 and not AurelianPaint.hull("scout")["kick"].is_empty() and not AurelianPaint.hull("fighter")["kick"].is_empty(), str(kickers))
	_check("their points are the whole picture's; kicking, only the guns' points move, by the slide", split_ok == kickers, "%d of %d" % [split_ok, kickers])
	var structures_ok := true
	for sid: String in StructureShapes.SHAPES:
		structures_ok = structures_ok and (AurelianPaint.structure(sid, false)["kick"] as Dictionary).is_empty()
	_check("no structure has nose guns that kick", structures_ok)

## Check 6: real ships. A shot is made up the way the match makes one (the gun's cooldown
## jumps up) and the match clock moves on; each ship's painter must see it.
func _ships() -> void:
	var ships: Array[Ship] = []
	for team in [Rules.HALCYON, Rules.CINDER]:
		for hid in ["scout", "fighter", "battlecruiser"]:
			var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
			p.hull_id = hid
			world.profiles.append(p)
			var s := world.launch(p)
			s.controller = null
			ships.append(s)
	for _i in 5:
		await get_tree().process_frame
	var t0 := world.time
	# The shot: every gun's cooldown jumps up, the way WeaponMount.update() does it.
	var cds := {}
	for s: Ship in ships:
		for m: WeaponMount in s.mounts:
			m.cd = 0.5
		cds[s] = (s.mounts[0] as WeaponMount).cd
	world.time = t0 + 0.01
	for _i in 3:
		await get_tree().process_frame
	for s: Ship in ships:
		var v := s.get_node("Visual") as ShipVisual
		var tname := "Aurelian" if s.team == Rules.HALCYON else "Cinder"
		var label := "%s %s" % [tname, s.hull_id]
		var seen := 0
		for i in s.mounts.size():
			seen += 1 if v._kicks.ages[i] < 0.5 else 0
		_check("%s: the painter saw the shot of every one of its %d guns" % [label, s.mounts.size()], seen == s.mounts.size(), "%d seen" % seen)
		_check("%s: looking left the cooldown alone" % label, (s.mounts[0] as WeaponMount).cd == cds[s])
		if s.hull_id == "scout" or s.hull_id == "fighter":
			_check("%s: its nose gun is the one the painter follows" % label, v._kicks.fixed_weapon == ("scout_gun" if s.hull_id == "scout" else "fighter_cannon"))
		else:
			_check("%s: no nose gun that kicks" % label, v._kicks.fixed_weapon == "")
	# The clock moves on: the shot ages.
	world.time = t0 + 0.2
	for _i in 3:
		await get_tree().process_frame
	var aged := 0
	for s: Ship in ships:
		var v := s.get_node("Visual") as ShipVisual
		aged += 1 if absf(float(v._kicks.ages[0]) - 0.19) < 0.011 else 0
	_check("a shot ages with the match clock, in every ship", aged == ships.size(), "%d of %d" % [aged, ships.size()])
