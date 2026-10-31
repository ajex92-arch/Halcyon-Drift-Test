extends Node
## WHAT THIS IS: the fan probe: a measuring tool for the Bomber's torpedo run
## (the narrowing fan of three torpedoes). It flies scripted duels in a frozen
## match and writes down how many of the three torpedoes land, how many point
## defense and flak shoot down, and how long one Bomber needs to kill a
## Battlecruiser. It asserts nothing and changes nothing in the game: it only
## stages ships and reads what happens.
##
## HOW IT WORKS: the match is frozen and the probe steps the ships and the
## rounds itself, one tick (1/60 s) at a time. Every cell below is RUNS duels;
## the duels differ in the target's speed, the Bomber's distance and its aim
## error, all drawn from a random generator with a fixed seed (SEED + the
## duel's number), so every run of the probe gives the same numbers and every
## cell sees the same variations. A duel is: a fresh Bomber stands still, turns
## its nose to where its torpedoes will meet the target (the lead point of the
## launch moment) plus a small aim error, holds for 90 ticks and lets go; the
## three torpedoes fly for 2.5 s; the counters of the game's Game.usage
## (torpedo_lane_hit_*, torpedo_shot_down, torpedo_dud) say what they did.
## The fan at the launch is what the rules give: the hold itself adds 182
## points (90 ticks of steady flight, plus the release tick), so the least a
## launch can have is 182 points (a half-angle of 10.4 degrees). A cell named
## "wide" forces 0 points on the release tick (a half-angle of 18 degrees),
## which the rules cannot reach; it is measured because the design asked for it.
## The cells:
##   hit        a Destroyer at about 800 units, broadside, point defense off:
##              "hold" keeps its course, "dodge" turns its bow to the Bomber and
##              brakes from the first tick of the hold (the ships-of-the-line flight);
##   defense    the same launch against a Destroyer with its guns live, a Flak
##              Frigate whose battery fires at the nearest torpedo, and a lane
##              turret (point defense) at 900 units; with Armoured Torpedoes too;
##   ttk        seconds one Bomber (and its two Fighter escorts) needs to destroy
##              a Battlecruiser with its guns live, running one fan after another;
##   fighter    what one torpedo takes from a Fighter standing still.
## The run is done twice, with the damage table on (the play build) and with
## --damage-modifiers-removed, and the probe says which it is.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=301 --test=fan_probe
## Options: --cells=hit,defense,ttk,fighter (default all), --runs=N (default 20),
## --set=key:value,... a what-if for the Bomber's torpedo (for example speed:440 or
## torp_hp:14: the numbers of its entry in weapons.gd are changed on a copy for the
## Bomber's guns, nothing else), printed in the line.
##
## HOW TO READ THE OUTPUT: the tables as text, then one "PROBE_JSON {...}" line.
## A cell is {runs, any (share of runs where at least one lane landed), all
## (share where all three landed), lanes (mean torpedoes that landed), shot (mean
## torpedoes shot down), duds}.
##
## WHO USES IT: main.gd loads it for --test=fan_probe. It reads the game and
## hurts only units of a frozen match that is thrown away.

## The length of a tick (seconds).
const DT := 1.0 / 60.0
## The hold of the run, in ticks; the release is on the tick after.
const HOLD := 90
## Ticks after the release that the torpedoes fly (2.5 s, more than their life).
const AFTER := 150
## The seed the variations of a duel start from.
const SEED := 4150
## The Bomber's distance to the target, in world units, before the variation.
const DIST := 800.0
## The Bomber's aim error, in world units at the target (uniform, either way).
const AIM_ERR := 60.0
## The lowest speed of the target, in world units a second.
const SPEED_LO := 100.0
## The highest speed of the target, in world units a second.
const SPEED_HI := 160.0
## The longest a Battlecruiser duel may last, in seconds.
const TTK_CAP_S := 250.0

## The running match (set by setup()).
var world: World
## Duels per cell (--runs).
var runs := 20
## Where the duels happen: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## A far corner where finished units are put away.
var _away := Vector2(-5000.0, -5000.0)
## How many units have been put away, so each gets its own far spot.
var _put_away := 0
## Everything measured, printed as PROBE_JSON.
var _out := {}
## The what-if numbers for the Bomber's torpedo (--set): key -> value.
var _what_if := {}


## main.gd calls this once, right after the World is built. Freeze the match
## and start on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	runs = int(Game.opt("runs", 20))
	for pair: String in str(Game.opt("set", "")).split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2:
			_what_if[kv[0]] = float(kv[1])
	_run.call_deferred()


## Measure the asked cells, print them and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var asked := str(Game.opt("cells", "all"))
	var want := func(cell: String) -> bool: return asked == "all" or asked == "true" or asked.split(",").has(cell)
	_out = {"probe": "fan_probe", "version": 1, "seed": int(Game.opt("seed", -1)), "runs": runs,
		"damage_modifiers_removed": Rules.damage_modifiers_removed(), "variants": Game.variants, "what_if": _what_if}
	if want.call("hit"):
		_cells_hit()
	if want.call("defense"):
		_cells_defense()
	if want.call("ttk"):
		_cells_ttk()
	if want.call("fighter"):
		_cell_fighter()
	print("PROBE_JSON " + JSON.stringify(_out))
	get_tree().quit()


# --- helpers ---------------------------------------------------------------------

## Launch a pilot ship of hull `hid` for team `team`, standing still at `at`
## facing east, with nobody at the controls.
func _launch(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = at
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.controls.aim_point = at + Vector2(2000.0, 0.0)
	s.controls.face_point = s.controls.aim_point
	world.registry.rebuild_hashes()
	return s


## A fresh Bomber for team 0 standing at `at`, with the what-if numbers (--set) put on a
## copy of its torpedo's entry.
func _bomber(at: Vector2) -> Ship:
	var b := _launch("bomber", 0, at)
	if not _what_if.is_empty():
		var d := b.run_mount.def.duplicate()
		for k: String in _what_if:
			d[k] = _what_if[k]
		b.run_mount.def = d
	return b


## Put unit `u` away in its own far corner and make it dead.
func _put(u: Unit) -> void:
	_put_away += 1
	u.global_position = _away - Vector2(float(_put_away) * 400.0, 0.0)
	u.alive = false
	world.registry.rebuild_hashes()


## Let every round in flight run out.
func _settle() -> void:
	for _i in 200:
		world.projectiles.tick(DT)


## The usage counter `key` (0 when it has not been counted yet).
func _count(key: String) -> int:
	return int(Game.usage.get(key, 0))


## The torpedoes that landed so far, over all three lanes.
func _landed() -> int:
	return _count("torpedo_lane_hit_left") + _count("torpedo_lane_hit_centre") + _count("torpedo_lane_hit_right")


## The variation of duel `k`: {speed, dist, err}.
func _variation(k: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + k
	return {"speed": rng.randf_range(SPEED_LO, SPEED_HI), "dist": DIST + rng.randf_range(-40.0, 40.0), "err": rng.randf_range(-AIM_ERR, AIM_ERR)}


## Turn Bomber `b` to the lead point of the launch moment on a target at `tp`
## flying `tv`, with an aim error of `err` world units at the target.
func _aim(b: Ship, tp: Vector2, tv: Vector2, err: float) -> void:
	var m := b.run_mount
	var speed := float(m.def["speed"])
	var t_launch := float(HOLD + 1) / 60.0
	var lead := Util.lead_point(m.world_pos(), Vector2.ZERO, tp + tv * t_launch, tv, speed)
	var dir := (lead - b.global_position).normalized().rotated(atan(err / maxf(1.0, b.global_position.distance_to(tp))))
	b.rotation = dir.angle()
	b.controls.face_point = b.global_position + dir * 2000.0
	b.controls.aim_point = b.controls.face_point


## One cell's numbers from its list of duels, each {lanes, shot, duds}.
func _cell(list: Array) -> Dictionary:
	var n := maxi(1, list.size())
	var any := 0
	var all := 0
	var lanes := 0
	var shot := 0
	var duds := 0
	for r: Dictionary in list:
		if int(r["lanes"]) >= 1:
			any += 1
		if int(r["lanes"]) >= 3:
			all += 1
		lanes += int(r["lanes"])
		shot += int(r["shot"])
		duds += int(r["duds"])
	return {"runs": list.size(), "any": snappedf(float(any) / float(n), 0.001), "all": snappedf(float(all) / float(n), 0.001),
		"lanes": snappedf(float(lanes) / float(n), 0.01), "shot": snappedf(float(shot) / float(n), 0.01), "duds": duds}


## A cell as one line of text.
func _line(label: String, c: Dictionary) -> String:
	return "%-46s runs %2d  one or more land %5.1f%%  all three %5.1f%%  landed %.2f  shot down %.2f  duds %d" % [label, c["runs"], float(c["any"]) * 100.0, float(c["all"]) * 100.0, c["lanes"], c["shot"], c["duds"]]


# --- one duel ----------------------------------------------------------------------

## One duel: Bomber against a `hull` (team 1) flying north at the variation's
## speed, `fan` = "tight" (360 points at the launch), "least" (the 182 the rules
## give at the least) or "wide" (0 forced on the release tick), `steer` = "hold"
## (keeps its course) or "dodge" (bow to the Bomber, brakes), `guns` = whether the
## target's own guns work, `armoured` = Armoured Torpedoes. `kind` "flak" makes
## a Flak Frigate's battery fire at the nearest torpedo. Returns {lanes, shot, duds}.
func _duel(k: int, hull: String, fan: String, steer: String, guns: bool, armoured: bool, kind: String = "") -> Dictionary:
	_settle()
	var v := _variation(k)
	var speed: float = v["speed"]
	var t := _launch(hull, 1, _home + Vector2(float(v["dist"]), 0.0))
	t.rotation = -PI * 0.5
	var vt := Vector2(0.0, -speed)
	t.velocity = vt
	if not guns:
		t.mounts.clear()
	var b := _bomber(_home)
	b.fan_points = 178 if fan == "tight" else 0
	_aim(b, t.global_position, vt, float(v["err"]))
	var ts: TeamState = world.teams[0]
	var bonus := ts.torp_hp_bonus
	if armoured:
		ts.torp_hp_bonus = 0.5
	var landed0 := _landed()
	var shot0 := _count("torpedo_shot_down")
	var duds0 := _count("torpedo_dud")
	for tick in HOLD + AFTER:
		if tick == HOLD and fan == "wide":
			b.fan_points = 0
		b.controls.fire = tick < HOLD
		b.sim_update(DT)
		_step_target(t, b, vt, steer, guns, kind)
		world.projectiles.tick(DT)
	ts.torp_hp_bonus = bonus
	var res := {"lanes": _landed() - landed0, "shot": _count("torpedo_shot_down") - shot0, "duds": _count("torpedo_dud") - duds0}
	_put(b)
	_put(t)
	return res


## One tick of the target `t` of a duel with Bomber `b`: it holds its course at
## `vt` or dodges, and its guns work or not.
func _step_target(t: Ship, b: Ship, vt: Vector2, steer: String, guns: bool, kind: String) -> void:
	if steer == "dodge":
		t.controls.face_point = b.global_position
		t.controls.forward = -1.0
	elif guns:
		# Keep the course and speed: the ship is put back on them every tick.
		t.velocity = vt
		t.rotation = -PI * 0.5
	if kind == "flak":
		# The battery fires at the nearest torpedo, aimed a little ahead of it.
		var slot := world.projectiles.nearest_enemy_torp(t.global_position, 720.0, t.team)
		t.controls.fire = slot >= 0
		if slot >= 0:
			t.controls.aim_point = world.projectiles.pos[slot] + world.projectiles.vel[slot] * 0.3
	if guns or steer == "dodge":
		t.sim_update(DT)
	else:
		t.global_position += vt * DT
	world.registry.rebuild_hashes()


# --- the cells ---------------------------------------------------------------------

## A cell: `runs` duels with the given settings.
func _run_cell(hull: String, fan: String, steer: String, guns: bool, armoured: bool = false, kind: String = "") -> Dictionary:
	var list: Array = []
	for k in runs:
		list.append(_duel(k, hull, fan, steer, guns, armoured, kind))
	return _cell(list)


## The hit-rate cells: a Destroyer with its guns off.
func _cells_hit() -> void:
	var hit := {}
	print("HIT: Destroyer at about 800 units, broadside, guns off (%d duds are torpedoes that touched it inside 200 units)" % 0)
	for steer: String in ["hold", "dodge"]:
		for fan: String in ["tight", "least", "wide"]:
			var c := _run_cell("destroyer", fan, steer, false)
			hit["%s_%s" % [steer, fan]] = c
			print(_line("Destroyer %s, fan %s" % [steer, fan], c))
	_out["hit"] = hit


## The defense cells: the target's guns live.
func _cells_defense() -> void:
	var d := {}
	print("DEFENSE: the same launch, the target's guns live")
	for fan: String in ["tight", "least", "wide"]:
		for armoured: bool in [false, true]:
			var c := _run_cell("destroyer", fan, "hold", true, armoured)
			d["destroyer_%s%s" % [fan, "_armoured" if armoured else ""]] = c
			print(_line("Destroyer, fan %s%s" % [fan, ", Armoured Torpedoes" if armoured else ""], c))
	for fan: String in ["tight", "least", "wide"]:
		var c := _run_cell("flak", fan, "hold", true, false, "flak")
		d["flak_frigate_%s" % fan] = c
		print(_line("Flak Frigate (battery fires at the torpedoes), fan %s" % fan, c))
	var turret := _cell_turret()
	d["lane_turret"] = turret
	print(_line("PD lane turret at 900 units, fan tight", turret))
	_out["defense"] = d


## The lane turret cell: a finished PD turret of team 1 stood 900 units from the Bomber.
func _cell_turret() -> Dictionary:
	var list: Array = []
	var tur := _make_turret()
	for k in runs:
		_settle()
		var v := _variation(k)
		tur.global_position = _home + Vector2(900.0, 0.0)
		world.registry.rebuild_hashes()
		var b := _bomber(_home)
		b.fan_points = 178
		_aim(b, tur.global_position, Vector2.ZERO, float(v["err"]))
		var landed0 := _landed()
		var shot0 := _count("torpedo_shot_down")
		var duds0 := _count("torpedo_dud")
		for tick in HOLD + AFTER:
			b.controls.fire = tick < HOLD
			b.sim_update(DT)
			tur.sim_update(DT)
			world.projectiles.tick(DT)
		list.append({"lanes": _landed() - landed0, "shot": _count("torpedo_shot_down") - shot0, "duds": _count("torpedo_dud") - duds0})
		_put(b)
	_put(tur)
	return _cell(list)


## A finished PD turret of team 1 on the ore node nearest to its mothership.
func _make_turret() -> Turret:
	var ms := world.mothership(1)
	var node: ResourceNode = null
	var slot := -1
	var best := INF
	for n: ResourceNode in world.nodes:
		for i in n.slots.size():
			if n.slots[i] == null and ms.global_position.distance_to(n.global_position) < best:
				best = ms.global_position.distance_to(n.global_position)
				node = n
				slot = i
	return world.spawn_turret(1, node, slot, "pd", true)


## The time-to-kill cells: one Bomber, a Battlecruiser with its guns live.
func _cells_ttk() -> void:
	var t := {}
	print("TTK: one Bomber (invulnerable) against a Battlecruiser holding still (a steady course; it does not wander into the rocks), guns live; seconds from the first hit to the kill")
	for escorts: int in [0, 2]:
		var r := _ttk(escorts)
		t["escorts_%d" % escorts] = r
		print("Battlecruiser, %d Fighter escorts within 400 units: %s s (%d runs, %d torpedoes landed, %d shot down, %d duds)" % [escorts, r["ttk"], r["runs"], r["landed"], r["shot"], r["duds"]])
	_out["ttk"] = t


## One Battlecruiser duel with `escorts` stationary Fighters beside it. The
## Bomber stands 800 units off the Battlecruiser's side, runs one fan after
## another (a hold, a release, the reload) and is put back beside the ship before
## each. Returns {ttk (seconds from the first hit to the kill, -1 = not in the cap), runs, landed, shot, duds}.
func _ttk(escorts: int) -> Dictionary:
	_settle()
	var vt := Vector2.ZERO
	var bc := _launch("battlecruiser", 1, _home + Vector2(DIST, 0.0))
	var base_hull := bc.hull_max
	bc.hull = base_hull + 1.0e6
	bc.rotation = -PI * 0.5
	bc.velocity = vt
	var b := _bomber(_home)
	b.hull += 1.0e6
	var fighters: Array = []
	for i in escorts:
		var f := _launch("fighter", 0, bc.global_position + Vector2(-320.0, -160.0 + 320.0 * float(i)))
		f.hull += 1.0e6
		fighters.append(f)
	var landed0 := _landed()
	var shot0 := _count("torpedo_shot_down")
	var duds0 := _count("torpedo_dud")
	var runs0 := _count("torpedo_runs_launched")
	var first := -1.0
	var killed := -1.0
	var t := 0.0
	var cycle := 0
	while t < TTK_CAP_S and killed < 0.0:
		# A new fan: the Bomber is put 800 units off the ship's side and aimed.
		b.global_position = bc.global_position + Vector2(-DIST, 0.0)
		b.velocity = Vector2.ZERO
		b.energy.value = b.energy.max_value
		_aim(b, bc.global_position, vt, 0.0)
		for i in fighters.size():
			(fighters[i] as Ship).global_position = bc.global_position + Vector2(-320.0, -160.0 + 320.0 * float(i))
		world.registry.rebuild_hashes()
		for tick in HOLD + 1 + 60:
			b.controls.fire = tick < HOLD
			b.sim_update(DT)
			bc.velocity = vt
			bc.rotation = -PI * 0.5
			bc.sim_update(DT)
			world.projectiles.tick(DT)
			t += DT
			if tick % 10 == 0:
				world.registry.rebuild_hashes()
			if first < 0.0 and bc.hull < base_hull + 1.0e6 - 0.01:
				first = t
			if killed < 0.0 and bc.hull <= 1.0e6:
				killed = t
				break
		cycle += 1
	for f: Ship in fighters:
		_put(f)
	_put(b)
	_put(bc)
	return {"ttk": snappedf(killed - first, 0.1) if killed >= 0.0 and first >= 0.0 else -1.0, "runs": _count("torpedo_runs_launched") - runs0,
		"landed": _landed() - landed0, "shot": _count("torpedo_shot_down") - shot0, "duds": _count("torpedo_dud") - duds0}


## What one torpedo takes from a Fighter standing still 500 units ahead of the
## Bomber (only the middle torpedo lands in a tight fan). The play build's
## small-craft rules (the x0.6 of the Bomber role and the blast share) are in it.
func _cell_fighter() -> void:
	_settle()
	var f := _launch("fighter", 1, _home + Vector2(500.0, 0.0))
	var b := _bomber(_home)
	b.fan_points = 178
	var m := b.run_mount
	var hull0 := f.hull
	var shield0 := f.shield_total()
	var landed0 := _landed()
	for tick in HOLD + 100:
		b.controls.fire = tick < HOLD
		b.sim_update(DT)
		world.projectiles.tick(DT)
	var landed := _landed() - landed0
	var lost := (hull0 - f.hull) / maxf(0.01, 1.0 - f.hull_resist) + (shield0 - f.shield_total())
	var share := float(BlastScale.percent(int(m.def["blast_curve"]), int(m.def["blast_size"]), int(m.def["blast_speed"]), f.hit_radius(), 0.0)) / 100.0
	var r := {"landed": landed, "damage_taken": snappedf(lost / float(maxi(1, landed)), 0.1), "raw": float(m.def["dmg"]), "blast_share": snappedf(share, 0.001),
		"bomber_role": str(Game.variants.get("bomber_role", "off"))}
	_out["fighter"] = r
	print("FIGHTER: one torpedo of 100 on a Fighter at rest takes %.1f from it (%d landed; the blast share alone is %.0f%% = %.1f; bomber_role variant: %s; damage modifiers removed: %s)" % [r["damage_taken"], landed, share * 100.0, share * 100.0, r["bomber_role"], str(Rules.damage_modifiers_removed())])
	_put(b)
	_put(f)
