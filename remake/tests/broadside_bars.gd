extends Node
## WHAT THIS IS: the bars of C2, the guns of the ships of the line: a scripted duel that measures
## what a Battlecruiser and a Destroyer deal and spend, so the build can be compared with the
## base build it replaced. The same file runs on both builds.
##
## HOW IT WORKS: setup() freezes the match. For each capital (the Battlecruiser, then the
## Destroyer) it launches the ship with its controller off, and a passive enemy Destroyer on its
## starboard beam 1,015 units away (0.75 of the heavy cannon's reach). The ship holds its trigger at
## the enemy for 60 seconds (3,600 ticks), stepped by hand with Ship.sim_update() and the shared
## round list (Projectiles.tick()). The enemy is never stepped (it does not shoot, repair or
## recharge) and is made whole again whenever it falls below half, the damage counted before the
## repair. It measures:
##   - dmg_per_s: the enemy's hull and shield points lost, per second;
##   - energy_per_s: the energy the ship's guns spent, per second, worked out from the guns
##     themselves (a round's energy for each cooldown that jumped up, a beam's energy per tick)
##     so it reads the same on both builds; on the new build the battery's own counter
##     (EnergyPool.spent) is printed beside it;
##   - empty_s: the seconds the battery stood empty (under 1 point);
##   - arc_share: the share of the 60 s with at least one battery gun able to turn to the
##     enemy (the new build only; the base build has no battery guns).
## Each duel is run twice from the same random seed and the two results must be equal.
## It prints, per hull, "broadside_bars: <hull> dmg_per_s <x> energy_per_s <x> empty_s <x> arc_share <x>".
## Given the base build's numbers (the option --bars-base-<hull>=dmg,energy,empty) it prints the three
## bars for that hull as PASS or FAIL lines: damage and energy per second each within 15% of the base's,
## and the empty seconds not higher than the base's. A bar outside 15% is reported, never tuned.
## It names a new member of the build only through get(), so it runs on the base build too.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=broadside_bars
##
## WHO USES IT: main.gd loads it for --test=broadside_bars. It launches extra ships into the
## match it builds and changes only that match.

## One physics tick, in seconds.
const DT := 1.0 / 60.0
## The length of the duel, in ticks (60 seconds).
const DUEL_TICKS := 3600
## How far the enemy stands on the starboard beam, in world units.
const DISTANCE := 1015.0
## How far from the base's number a bar may be (a share of it).
const MARGIN := 0.15

## The running match (set by setup()).
var world: World
## The ground the ships stand on: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## How many bars failed.
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Both duels, twice each, then the verdict.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	for hid in ["battlecruiser", "destroyer"]:
		var r := _duel(hid)
		var again := _duel(hid)
		var same: bool = absf(float(r["dmg"]) - float(again["dmg"])) < 0.0001 and absf(float(r["energy"]) - float(again["energy"])) < 0.0001 and absf(float(r["empty"]) - float(again["empty"])) < 0.0001
		var ion := _duel(hid, true)
		print("broadside_bars: %s dmg_per_s %.4f energy_per_s %.4f empty_s %.4f arc_share %s spent_per_s %s enemy_load_per_s %.4f ion_only_dmg_per_s %.4f ion_only_load_per_s %.4f" % [hid, r["dmg"], r["energy"], r["empty"], ("%.4f" % float(r["share"])) if float(r["share"]) >= 0.0 else "n/a", ("%.4f" % float(r["spent"])) if float(r["spent"]) >= 0.0 else "n/a", r["load"], ion["dmg"], ion["load"]])
		_bar("%s: the repeat of the duel gives the same numbers" % hid, same, "dmg %.4f and %.4f, energy %.4f and %.4f" % [r["dmg"], again["dmg"], r["energy"], again["energy"]])
		var base: Variant = Game.opt("bars-base-%s" % hid)
		if base != null:
			var parts := str(base).split(",")
			if parts.size() == 3:
				var bd := float(parts[0])
				var be := float(parts[1])
				var bz := float(parts[2])
				_bar("%s: damage per second within 15%% of the base" % hid, bd > 0.0 and absf(float(r["dmg"]) / bd - 1.0) <= MARGIN, "final %.4f base %.4f (%+.1f%%)" % [r["dmg"], bd, (float(r["dmg"]) / bd - 1.0) * 100.0 if bd > 0.0 else 0.0])
				_bar("%s: energy per second within 15%% of the base" % hid, be > 0.0 and absf(float(r["energy"]) / be - 1.0) <= MARGIN, "final %.4f base %.4f (%+.1f%%)" % [r["energy"], be, (float(r["energy"]) / be - 1.0) * 100.0 if be > 0.0 else 0.0])
				_bar("%s: seconds with an empty battery not higher than the base's" % hid, float(r["empty"]) <= bz + 0.0001, "final %.4f base %.4f" % [r["empty"], bz])
	print("broadside_bars: %d bars failed" % fails)
	if fails == 0:
		print("broadside_bars: 0 failures")
	get_tree().quit()


## Print one bar's line and count a failure.
func _bar(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("broadside_bars: PASS %s (%s)" % [what, detail])
	else:
		fails += 1
		print("broadside_bars: FAIL %s (%s)" % [what, detail])


## One duel of a `hid` against a passive enemy Destroyer; returns {"dmg", "energy", "empty", "share", "spent", "load"}
## (a number below 0 for "not measured": the share and the counter on the base build). "load" is the energy the enemy
## battery would take on per second from the shield points soaked. With `ion_only` the ship keeps only its ion guns.
func _duel(hid: String, ion_only: bool = false) -> Dictionary:
	seed(20261122)
	var a := _ship(hid, Rules.HALCYON, _home)
	var b := _ship("destroyer", Rules.CINDER, _home + Vector2(0.0, DISTANCE))
	# The ion-only duel: the ship keeps only its ion guns, so what they do alone can be read.
	if ion_only:
		var keep: Array[WeaponMount] = []
		for m: WeaponMount in a.mounts:
			if m.weapon_id.begins_with("ion"):
				keep.append(m)
		a.mounts = keep
	var a_at := a.global_position
	var b_at := b.global_position
	a.controls.aim_point = b_at
	a.controls.fire = true
	var full := b.hull_max + b.shields.max_total
	b.hull = b.hull_max
	b.shields.fill()
	var prev := b.hull + b.shields.total()
	# What the enemy's battery would take on from the shield points its zones soak (the share of them that
	# becomes hard energy, as Ship._overload_step() works it out); the enemy is never stepped, so this is a tally.
	var load_k: float = OverloadRules.HARD_SHARE * b.energy.max_value / maxf(1.0, b.shields.max_total)
	var blocked_prev := b.shields.last_blocked
	var load_sum := 0.0
	var lost := 0.0
	var energy_sum := 0.0
	var empty_ticks := 0
	var bear_ticks := 0
	var has_battery := false
	for m: WeaponMount in a.mounts:
		var bv: Variant = m.get("battery")
		if bv == true:
			has_battery = true
	var spent0 := _spent(a)
	var cds: Array = []
	cds.resize(a.mounts.size())
	for _t in DUEL_TICKS:
		for i in a.mounts.size():
			cds[i] = (a.mounts[i] as WeaponMount).cd
		world.time += DT
		world.registry.rebuild_hashes()
		a.sim_update(DT)
		a.global_position = a_at
		a.rotation = 0.0
		a.velocity = Vector2.ZERO
		world.projectiles.tick(DT)
		# What the guns spent this tick, from the guns themselves.
		for i in a.mounts.size():
			var m: WeaponMount = a.mounts[i]
			var per: float = float(m.def.get("energy", 0.0))
			if m.is_beam:
				if m.beam_firing:
					energy_sum += per * DT
			elif m.cd > float(cds[i]) + 0.0001:
				energy_sum += per
		if a.energy.value < 1.0:
			empty_ticks += 1
		if has_battery:
			for m: WeaponMount in a.mounts:
				var bv: Variant = m.get("battery")
				if bv == true and m.in_swing(Util.ang_diff(a.rotation, (b_at - m.world_pos()).angle()), 0.05):
					bear_ticks += 1
					break
		# The enemy: count what it lost, then make it whole when it is low.
		var cur := b.hull + b.shields.total()
		load_sum += (b.shields.last_blocked - blocked_prev) * load_k
		blocked_prev = b.shields.last_blocked
		if _t % 600 == 0:
			print("broadside_bars: INFO %s tick %d enemy hull %.1f shield %.1f lost %.1f rounds in flight %d" % [hid, _t, b.hull, b.shields.total(), lost, world.projectiles.active.size()])
		if cur < prev:
			lost += prev - cur
		prev = cur
		if cur < 0.5 * full:
			b.hull = b.hull_max
			b.shields.fill()
			prev = b.hull + b.shields.total()
	var secs := float(DUEL_TICKS) * DT
	var spent1 := _spent(a)
	var out := {"dmg": lost / secs, "energy": energy_sum / secs, "empty": float(empty_ticks) * DT, "share": (float(bear_ticks) / float(DUEL_TICKS)) if has_battery else -1.0, "spent": ((spent1 - spent0) / secs) if spent1 >= 0.0 else -1.0, "load": load_sum / secs}
	_clear([a, b])
	return out


## The battery's own spend counter of ship `s` (EnergyPool.spent), or -1 on the base build.
func _spent(s: Ship) -> float:
	var v: Variant = s.energy.get("spent")
	return float(v) if v != null else -1.0


## Launch a ship of hull `hid` for `team`, controller off, pinned at `at` facing east, shields and
## battery full.
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


## Take the ships of a duel out of the match.
func _clear(list: Array) -> void:
	var k := 0
	for u: Unit in list:
		k += 1
		u.global_position = Vector2(-9000.0 - 400.0 * k, -9000.0)
		u.alive = false
	world.registry.rebuild_hashes()
