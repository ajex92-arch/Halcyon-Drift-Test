extends Node
## WHAT THIS IS: the time-to-kill table: a measuring tool that puts every
## weapon of the game (every row of weapons.gd) against one target of each
## hull class, with full shields, and prints how many seconds it takes to
## destroy the target and how much of the damage the shield took. It asserts
## nothing: its numbers are put side by side for two builds of the game.
##
## HOW IT WORKS: it freezes the match and steps it by hand, one tick (1/60
## second) at a time. For each target it makes a fresh unit at open ground, and
## for each weapon it mounts a real WeaponMount on a parked ship 250 world
## units from the target's edge, pulls the trigger and keeps it pulled. The
## rounds and beams are the game's own, so everything the game does to a hit
## is done here too (the damage rules, the shield zone facing the shot, the
## shield skip, the hull's resistance, the shield refill after a pause). What
## is taken out so the table is repeatable:
##   - no dice: the gun has no spread, so every round flies at the middle of
##     the target and every pellet of a flak shot bursts on it;
##   - no aiming error, no energy limit, no gear, no research; a gun with a
##     wind-up makes one torpedo run after another (a hold of 90 ticks, a
##     release, the reload), each with the tightest fan, so its row counts the
##     three torpedoes of every run;
##   - the target does not shoot back, does not move and never refills its
##     hull. A target that is meant to be fast only reports its top speed (to
##     the rules that read it) in the second table; it stays where it is.
## The shot always comes from the target's front (or its broadside for the
## mothership), so one of the four shield zones of a pilot ship takes it and
## the other three stay full: with Balanced focus that is a quarter of the
## shield. A mothership or minion shield is one pool.
## A target cannot really die in the test (its death would pay rewards and
## could end the match): it is given a million extra hull points and counts as
## dead when the hull has lost its true amount. The time starts at the first
## hit and stops at that moment.
##
## Three tables are printed, then two role lines:
##   Table 1: each weapon against each target at rest. A cell reads
##            "seconds/percent": the seconds to destroy the target and the
##            percent of the points it lost (shield and hull together) that
##            the shield took. ">300" = not destroyed in 300 s of fire (900 s for the mothership),
##            "no dmg" = the target lost nothing for 60 s, "1 hit" = one hit
##            destroyed it, "no hit" = nothing touched it in 10 s.
##   Table 2: the same for the blast weapons (torpedoes and flak) when the
##            target reports its top speed.
##   Table 3: the same weapons and targets at rest: the percent of the hull
##            that is already gone when the shield zone facing the shot is
##            empty. This is what a shield skip (pierce) changes.
##   ROLE 1:  fighters do not kill capital ships alone, torpedoes do.
##   ROLE 2:  flak still stops Fighters and Light Bombers.
## The thresholds the two verdicts use are the constants ROLE_* below.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=ttk_table
## Options of its own: --weapons=<ids> (comma separated weapon ids, default
## all) and --targets=<ids> (any of TARGETS, default all).
##
## HOW TO READ THE OUTPUT: the three tables and the role lines as text, then one
## "PROBE_JSON {...}" line with every cell.
##
## WHO USES IT: main.gd loads it for --test=ttk_table. It reads the game and
## hurts only units of a frozen match that is thrown away; it draws no random
## numbers.

## The length of a tick (seconds).
const DT := 1.0 / 60.0
## How far (world units) the muzzle is from the target's edge.
const GAP := 250.0
## The longest time (seconds) of fire at one target.
const CAP_S := 300.0
## The longest time (seconds) of fire at the mothership, which has far more to lose.
const CAP_MOTHERSHIP_S := 900.0
## A cell stops as "no dmg" when neither the shield nor the hull has lost a
## point for this many seconds.
const STALL_S := 60.0
## A cell stops as "no hit" when nothing touched the target after this many
## seconds.
const NO_HIT_S := 10.0
## The extra hull points a target is given so that it cannot die in the test.
const BIG_HULL := 1000000.0
## The targets, in column order: a Fighter (light craft), a Logistics Corvette,
## a Flak Frigate, a Destroyer, a Battlecruiser, the mothership, a PD lane
## turret, then the minions' Snub-Fighter and Light Bomber.
const TARGETS := ["fighter", "logistics", "flak", "destroyer", "battlecruiser", "mothership", "turret_pd", "m_fighter", "m_bomber"]
## The short column titles of TARGETS.
const TITLES := {"fighter": "Fighter", "logistics": "Corvette", "flak": "Frigate", "destroyer": "Destroyer",
	"battlecruiser": "Battlecr.", "mothership": "Mothership", "turret_pd": "Turret", "m_fighter": "Snub-Ftr", "m_bomber": "Lt Bomber"}
## The weapon kinds whose hits can depend on the target's size and speed
## (torpedoes and flak): table 2 covers these.
const BLAST_KINDS := ["torp", "flak"]
## ROLE 1: a torpedo must destroy a Destroyer and a Battlecruiser within this
## many seconds ...
const ROLE_TORP_MAX_S := 40.0
## ... and a lone Fighter must need at least this many times as long.
const ROLE_FIGHTER_MIN_RATIO := 4.0
## ROLE 2: flak must destroy a Fighter and a Light Bomber within this many
## seconds.
const ROLE_FLAK_MAX_S := 8.0

## The running match (set by setup()).
var world: World
## The parked ship that carries the guns.
var _shooter: Ship
## Where the target stands: open ground between the lanes.
var _home := Vector2.ZERO
## A far corner where finished units are put away.
var _away := Vector2(-5000.0, -5000.0)
## How many units have been put away, so each gets its own far spot.
var _put_away := 0
## The result cells: weapon id -> target id -> cell (table 1).
var _rest := {}
## The result cells of table 2 (target at top speed).
var _fast := {}


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Make the tables, print them with the role lines, and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_shooter = _launch("scout", 0)
	var weapons := _weapon_ids()
	var targets := _target_ids()
	for tid: String in targets:
		var target := _make_target(tid)
		_place(target, _home)
		for wid: String in weapons:
			_store(_rest, wid, tid, _fire(target, wid, false))
			if _is_blast(wid):
				_store(_fast, wid, tid, _fire(target, wid, true))
		_put(target)
	_print_table("TABLE 1: seconds to destroy / percent taken by the shield, target at rest", weapons, targets, _rest)
	var blast: Array = weapons.filter(func(x: String) -> bool: return _is_blast(x))
	_print_table("TABLE 2: the blast weapons (torpedoes and flak), target at its top speed", blast, targets, _fast)
	_print_table("TABLE 3: percent of the hull already lost when the shield zone facing the shot is empty (- = it never was)", weapons, targets, _rest, true)
	var roles := _roles()
	print("PROBE_JSON ", JSON.stringify({"probe": "ttk_table", "cap_s": CAP_S, "gap": GAP, "targets": targets,
		"rest": _rest, "fast": _fast, "roles": roles}))
	get_tree().quit()


## The weapon ids to measure: --weapons, or every row of Weapons.WEAPONS.
func _weapon_ids() -> Array:
	var asked := str(Game.opt("weapons", "all"))
	if asked == "all" or asked == "true":
		return Weapons.WEAPONS.keys()
	var out: Array = []
	for w: String in asked.split(","):
		if Weapons.WEAPONS.has(w):
			out.append(w)
	return out


## The target ids to measure: --targets, or all of TARGETS.
func _target_ids() -> Array:
	var asked := str(Game.opt("targets", "all"))
	if asked == "all" or asked == "true":
		return TARGETS.duplicate()
	var out: Array = []
	for t: String in asked.split(","):
		if TARGETS.has(t):
			out.append(t)
	return out


## True if weapon `wid` is a torpedo or a flak weapon.
func _is_blast(wid: String) -> bool:
	return BLAST_KINDS.has(str(Weapons.get_def(wid)["kind"]))


## Remember `cell` for weapon `wid` against target `tid` in `book`.
func _store(book: Dictionary, wid: String, tid: String, cell: Dictionary) -> void:
	if not book.has(wid):
		book[wid] = {}
	(book[wid] as Dictionary)[tid] = cell


# --- the targets ------------------------------------------------------------------

## Make one unit of target `tid` (team 1): a pilot hull, a minion type, the
## mothership or a PD lane turret.
func _make_target(tid: String) -> Unit:
	if tid == "mothership":
		return world.mothership(1)
	if tid == "turret_pd":
		return _make_turret()
	if tid == "m_fighter":
		return world.spawn_minion(1, "fighter", "mid", _home)
	if tid == "m_bomber":
		return world.spawn_minion(1, "bomber", "mid", _home)
	return _launch(tid, 1)


## A finished PD turret of team 1 on the ore node nearest to its mothership.
func _make_turret() -> Unit:
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


## Launch a pilot ship of hull `hid` for team `team`, with nobody at the
## controls.
func _launch(hid: String, team: int) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Stand unit `u` at `at`, not moving, facing east, and tell the spatial
## hashes.
func _place(u: Unit, at: Vector2) -> void:
	u.global_position = at
	u.rotation = 0.0
	u.velocity = Vector2.ZERO
	world.registry.rebuild_hashes()


## Put unit `u` away in its own far corner and make it dead so nothing looks
## at it again.
func _put(u: Unit) -> void:
	_put_away += 1
	u.global_position = _away - Vector2(float(_put_away) * 400.0, 0.0)
	u.alive = false
	world.registry.rebuild_hashes()


## The top speed (world units per second) target `u` reports in table 2: a
## pilot hull's or minion's top speed, the mothership's move speed, 0 for a
## turret.
func _top_speed(u: Unit) -> float:
	if u is Ship:
		return (u as Ship).f_max
	if u is Minion:
		return float(Minions.TYPES[(u as Minion).mtype]["speed"])
	if u is Mothership:
		return float((u as Mothership).def["move_speed"])
	return 0.0


# --- one cell ---------------------------------------------------------------------

## Fire weapon `wid` at `target` until it is destroyed or the cap is reached.
## `fast`: the target reports its top speed. Returns the cell: {state: "kill" |
## "cap" | "stall" | "nohit", cap: the longest fire in seconds, hits: how many
## ticks a hit landed, ttk: seconds from the first hit to the kill, share:
## 0..1 of the lost points the shield took, at_break: the hull share lost when
## the shield zone facing the shot was emptied (-1 = it never was)}.
func _fire(target: Unit, wid: String, fast: bool) -> Dictionary:
	# Step 1: a fresh target: full shields, a hull that cannot die.
	var base_hull := target.hull_max
	target.hull = base_hull + BIG_HULL
	if target.shields != null:
		target.shields.fill()
		target.shields.since_hit = 999.0
	target.damage_log = {}
	target.velocity = Vector2(0.0, _top_speed(target)) if fast else Vector2.ZERO
	# Step 2: the shooter stands in front of the target (a mothership: at its
	# side), looking at it, with the weapon bolted on without a spread.
	var dir := Vector2.RIGHT
	if target is Mothership:
		dir = Util.starboard_of(target.rotation)
	var aim_dir := -dir
	_shooter.global_position = target.global_position + dir * (target.hit_radius() + GAP)
	_shooter.rotation = aim_dir.angle()
	_shooter.velocity = Vector2.ZERO
	# A torpedo run leaves along the fan of the shooter's tightness score: the
	# table uses the tightest, steady fan.
	_shooter.fan_points = 360
	world.registry.rebuild_hashes()
	var mount := WeaponMount.new(_shooter, wid, "fixed", Vector2.ZERO, 0.0)
	mount.def = mount.def.duplicate()
	mount.def["spread"] = 0.0
	# Step 3: fire, tick by tick.
	var t := 0.0
	var first := -1.0
	var last_progress := 0.0
	var hits := 0
	var hull_lost := 0.0
	var shield_lost := 0.0
	var state := "cap"
	var killed := -1.0
	var at_break := -1.0
	var aim_at := _shooter.global_position + aim_dir * 1000.0
	var cap := CAP_MOTHERSHIP_S if target is Mothership else CAP_S
	while t < cap:
		# A gun with a wind-up makes runs: the trigger is held until the bar is full
		# and let go to launch, and a new run starts as soon as the reload is over.
		var trigger := true
		if mount.run != null:
			trigger = not (mount.run.is_full() or mount.run.reload > 0)
			mount.run.pre(mount, trigger, false, null)
		var shield_before := target.shield_total()
		var hull_before := target.hull
		mount.update(DT, aim_at, trigger, 1.0, 1.0, 1.0, null)
		world.projectiles.tick(DT)
		var dh := hull_before - target.hull
		var ds := maxf(0.0, shield_before - target.shield_total())
		hull_lost += dh
		shield_lost += ds
		if dh > 0.0 or ds > 0.0:
			hits += 1
			last_progress = t
			if first < 0.0:
				first = t
		# The shield refills only when it has not been hit for a while.
		if target.shields != null:
			target.shields.tick(DT, 1.0, 0.0)
		# The first time the shield zone facing the shot is empty: how much of the hull is gone then.
		if at_break < 0.0 and target.shields != null and target.shields.max_total > 0.0 and target.shields.values[0] <= 0.0:
			at_break = minf(1.0, hull_lost / base_hull)
		t += DT
		if hull_lost >= base_hull:
			state = "kill"
			killed = t
			break
		if first < 0.0 and t >= NO_HIT_S:
			state = "nohit"
			break
		if first >= 0.0 and t - last_progress >= STALL_S:
			state = "stall"
			break
	# Step 4: let every round in flight run out, so none is left for the next
	# cell.
	_flush()
	var lost := hull_lost + shield_lost
	return {"state": state, "cap": int(cap), "hits": hits, "ttk": snappedf(killed - first, 0.1) if state == "kill" else -1.0,
		"share": snappedf(shield_lost / lost, 0.01) if lost > 0.0 else 0.0, "at_break": snappedf(at_break, 0.01)}


## Step the rounds in flight until none is left (the longest life is a few
## seconds), without any gun firing.
func _flush() -> void:
	for _i in 600:
		if world.projectiles.count() == 0:
			return
		world.projectiles.tick(DT)


# --- the printout -----------------------------------------------------------------

## One cell as text: "seconds/percent", or the reason there is no time.
func _cell_text(c: Dictionary) -> String:
	match str(c["state"]):
		"kill":
			if int(c["hits"]) == 1:
				return "1 hit/%d" % int(round(float(c["share"]) * 100.0))
			var secs := float(c["ttk"])
			var s := "%.1f" % secs if secs < 100.0 else "%d" % int(secs)
			return "%s/%d" % [s, int(round(float(c["share"]) * 100.0))]
		"stall":
			return "no dmg"
		"nohit":
			return "no hit"
	return ">%d" % int(c["cap"])


## One cell of table 3 as text: the percent of the hull lost when the shield
## zone facing the shot was emptied, or "-" when it never was.
func _break_text(c: Dictionary) -> String:
	return "-" if float(c["at_break"]) < 0.0 else "%d%%" % int(round(float(c["at_break"]) * 100.0))


## Print one table: a title, the column titles and one row per weapon.
func _print_table(title: String, weapons: Array, targets: Array, book: Dictionary, at_break := false) -> void:
	print(title)
	var head := "%-17s" % "weapon"
	for tid: String in targets:
		head += "%11s" % TITLES[tid]
	print(head)
	for wid: String in weapons:
		if not book.has(wid):
			continue
		var row := "%-17s" % wid
		for tid: String in targets:
			var cell: Dictionary = (book[wid] as Dictionary)[tid]
			row += "%11s" % (_break_text(cell) if at_break else _cell_text(cell))
		print(row)


## The seconds to destroy target `tid` with weapon `wid` at rest, or INF when
## it was not destroyed (or the pair was not measured).
func _ttk(wid: String, tid: String) -> float:
	if not _rest.has(wid) or not (_rest[wid] as Dictionary).has(tid):
		return INF
	var c: Dictionary = (_rest[wid] as Dictionary)[tid]
	return float(c["ttk"]) if str(c["state"]) == "kill" else INF


## Seconds as text for a role line ("never" for INF).
func _secs_text(x: float) -> String:
	return "never" if x == INF else "%.1f s" % x


## Print the two role lines and return their numbers.
func _roles() -> Dictionary:
	var out := {}
	# ROLE 1: fighters do not kill capital ships alone; torpedoes do.
	var fd := _ttk("fighter_cannon", "destroyer")
	var fb := _ttk("fighter_cannon", "battlecruiser")
	var td := _ttk("torpedo", "destroyer")
	var tb := _ttk("torpedo", "battlecruiser")
	var role1 := "n/a"
	if _rest.has("fighter_cannon") and _rest.has("torpedo") and (_rest["fighter_cannon"] as Dictionary).has("destroyer") and (_rest["fighter_cannon"] as Dictionary).has("battlecruiser"):
		var holds := td <= ROLE_TORP_MAX_S and tb <= ROLE_TORP_MAX_S and fd >= ROLE_FIGHTER_MIN_RATIO * td and fb >= ROLE_FIGHTER_MIN_RATIO * tb
		role1 = "HOLDS" if holds else "BREAKS"
		print("ROLE 1 (fighters do not kill capitals alone; torpedoes do): one Fighter cannon needs %s for a Destroyer and %s for a Battlecruiser; one Bomber torpedo needs %s and %s (torpedo within %.0f s and the Fighter at least %.0f times as long) -> %s" % [
			_secs_text(fd), _secs_text(fb), _secs_text(td), _secs_text(tb), ROLE_TORP_MAX_S, ROLE_FIGHTER_MIN_RATIO, role1])
	out["role1"] = {"verdict": role1, "fighter_destroyer": _json_secs(fd), "fighter_battlecruiser": _json_secs(fb),
		"torpedo_destroyer": _json_secs(td), "torpedo_battlecruiser": _json_secs(tb)}
	# ROLE 2: flak still stops Fighters and Light Bombers.
	var fl := {}
	var all_in := true
	var worst := 0.0
	for wid: String in ["flak_battery", "flak_auto"]:
		for tid: String in ["fighter", "m_bomber"]:
			if not _rest.has(wid) or not (_rest[wid] as Dictionary).has(tid):
				all_in = false
				continue
			var x := _ttk(wid, tid)
			fl["%s_%s" % [wid, tid]] = _json_secs(x)
			worst = maxf(worst, x)
	var role2 := "n/a"
	if all_in:
		role2 = "HOLDS" if worst <= ROLE_FLAK_MAX_S else "BREAKS"
		print("ROLE 2 (flak still stops Fighters and Light Bombers): Flak Frigate battery needs %s for a Fighter and %s for a Light Bomber, the Flak mount %s and %s (all within %.0f s) -> %s" % [
			_secs_text(_ttk("flak_battery", "fighter")), _secs_text(_ttk("flak_battery", "m_bomber")),
			_secs_text(_ttk("flak_auto", "fighter")), _secs_text(_ttk("flak_auto", "m_bomber")), ROLE_FLAK_MAX_S, role2])
	fl["verdict"] = role2
	out["role2"] = fl
	return out


## A time for the JSON line: seconds, or -1 for "never".
func _json_secs(x: float) -> float:
	return -1.0 if x == INF else x
