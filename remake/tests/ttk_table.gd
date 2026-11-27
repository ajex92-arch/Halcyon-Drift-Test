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
## The shot comes from the target's front (or its broadside for the mothership; --from
## below picks another side of a pilot ship), so one of the four shield zones of a pilot ship takes it and
## the other three stay full: with Balanced focus that is a quarter of the
## shield. A mothership or minion shield is one pool.
## A target cannot really die in the test (its death would pay rewards and
## could end the match): it is given a million extra hull points and counts as
## dead when the hull has lost its true amount. The time starts at the first
## hit and stops at that moment.
##
## Four tables are printed, then the role lines:
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
##   Table 4: the same weapons and targets at rest: the percent of the armour of the
##            section facing the shot (the most worn section of the front zone) that is
##            lost when the cell ends, "-" for a unit with no sections. A weak gun on a
##            whole thick section reads 0%: its shots glance (the glancing rule).
##   ROLE 1:  fighters do not kill capital ships alone, torpedoes do.
##   ROLE 2:  flak still stops Fighters and Light Bombers.
##   ROLE 3:  the strike craft's guns against the Battlecruiser, with the armour
##            of this run (all green or all black), next to the torpedo.
##   ROLE 4:  the Lance is worse than the Bomber's torpedo against the big hulls
##            (Destroyer, Battlecruiser) and not better than the Fighter's cannon by more
##            than 5% against the small ones (Fighter, Corvette); how reliable it is the
##            table cannot say.
##   TABLE 7: the ship parts (only with the parts switch on, option --parts=on|off, default the
##            switch Rules.parts_on(); with it off every cell is "-"): the five weapons fighter_cannon,
##            torpedo, heavy_cannon, flak_battery and pd_gun against the Flak Frigate, Ion Frigate,
##            Destroyer and Battlecruiser at rest, shot from the front at the middle. A cell reads
##            "seconds to the first part degraded/seconds to the first part offline/part id" (the time
##            counts from the first hit; "-" when no part was hurt in the 300 s). The target never heals.
##   ROLE 5:  report only, never a verdict: the seconds one Fighter cannon needs to take the first
##            exposed light part of a hull offline, shot from the side that part sits on (a shot at
##            the front middle never reaches a part on the flank).
## ROLE 1's torpedo limit grows with the hull research (40 s, 52 s with --research=on), and
## ROLE 4's Lance may tie the Fighter cannon within 5% on the small hulls.
## The thresholds the verdicts use are the constants ROLE_* below.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=ttk_table
## Options of its own: --weapons=<ids> (comma separated weapon ids, default
## all), --targets=<ids> (any of TARGETS, default all) and --armour=green|black:
## green (the default) starts every armour section of every target whole, black
## starts them all breached (no armour at all), so two runs give the two columns
## of the armour tables; --gear=on gives every pilot-hull target both gear items that
## carry a hull resist (the Armored Flight Suit and the Command Throne: they raise the
## armour value), and --research=on gives the target's team both armour research items of
## every ship class (+15% hull each: the armour pool grows with the hull). The two
## switches combine with either armour setting. --from=front|rear|left|right (default front,
## today's table exactly) says which side of a pilot-hull target the shooter stands on: the
## nose (front), the tail (rear), the port beam (left) or the starboard beam (right); the
## shield zone and the armour zone the tables read are those of that side. The mothership is
## always shot from its side, whatever --from says. The torpedo's stand beside the hull (the
## arming distance) applies to the front run only: from the tail it stands along the hull's
## line, where nothing may reach, so the rear torpedo cells can read "no hit".
##
## HOW TO READ THE OUTPUT: the four tables and the role lines as text, then one
## "PROBE_JSON {...}" line with every cell.
##
## WHO USES IT: main.gd loads it for --test=ttk_table. It reads the game and
## hurts only units of a frozen match that is thrown away; it draws no random
## numbers.

## The length of a tick (seconds).
const DT := 1.0 / 60.0
## How far (world units) the muzzle is from the target's farthest reach.
const GAP := 250.0
## The farthest (world units from the target's middle) the shooter stands along the
## line of a hull: two map rocks (radius about 206, centres about 829 east and west of the
## table's spot) reach in to about 623 units, and a round that starts inside a rock is
## stopped by it, so from farther out nothing hits.
const STAND_MAX := 600.0
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
## The hull growth of one armour research item (+15% hull), as ship_stats.gd:166 reads it
## (`1.0 + 0.15 * armor`); a copy for the table, which it does not read from the game.
const RESEARCH_HULL_STEP := 0.15
## The research level the table gives every class with --research=on (two items).
const RESEARCH_LEVEL := 2
## ... and a lone Fighter must need at least this many times as long.
const ROLE_FIGHTER_MIN_RATIO := 4.0
## ROLE 2: flak must destroy a Fighter and a Light Bomber within this many
## seconds.
const ROLE_FLAK_MAX_S := 8.0
## ROLE 4: on the small hulls the Lance holds when its time is at least this share
## (1 - 0.05) of the Fighter cannon's: a near tie is not a break.
const ROLE_NEAR_TIE := 0.05

## The weapons TABLE 7 measures (the table's own weapon ids).
const PARTS_WEAPONS := ["fighter_cannon", "torpedo", "heavy_cannon", "flak_battery", "pd_gun"]
## The targets TABLE 7 measures: the four hulls that carry parts.
const PARTS_TARGETS := ["flak", "ion", "destroyer", "battlecruiser"]

## The column titles of TABLE 7 (the Ion Frigate is not a column of the other tables).
const PARTS_TITLES := {"flak": "Flak Frigate", "ion": "Ion Frigate", "destroyer": "Destroyer", "battlecruiser": "Battlecr."}

## The armour every target starts with: "green" (every section whole) or "black"
## (every section breached). Set from --armour.
var armour_mode := "green"
## True when every pilot-hull target carries both gear items with a hull resist (--gear=on).
var gear_on := false
## True when the target's team has both armour research items of every class (--research=on).
var research_on := false
## The side of a pilot-hull target the shooter stands on: "front", "rear", "left" or "right"
## (the nose, the tail, the port beam, the starboard beam). Set from --from.
var from_side := "front"
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
## The lines of TABLE 7, measured before the other tables and printed after them.
var _table7_lines := PackedStringArray()
## The ROLE 5 report lines, measured early and printed after the role lines.
var _role5_lines := PackedStringArray()
## The result cells of table 2 (target at top speed).
var _fast := {}


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	armour_mode = "black" if str(Game.opt("armour", "green")) == "black" else "green"
	gear_on = str(Game.opt("gear", "off")) == "on"
	research_on = str(Game.opt("research", "off")) == "on"
	var asked_from := str(Game.opt("from", "front"))
	from_side = asked_from if ["rear", "left", "right"].has(asked_from) else "front"
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Make the tables, print them with the role lines, and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	print("ARMOUR: all sections %s, gear %s, research %s" % [armour_mode, "on" if gear_on else "off", "on" if research_on else "off"])
	if research_on:
		for tier: String in world.teams[1].armor.keys():
			world.teams[1].armor[tier] = RESEARCH_LEVEL
	_shooter = _launch("scout", 0)
	var weapons := _weapon_ids()
	var targets := _target_ids()
	# The parts measures first (they launch ships, which the mothership's table would make impossible: it is not available after it has been shot); printed below.
	var parts_book := _parts_table(weapons, targets)
	var role5 := _role5(targets)
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
	_print_table("TABLE 3: percent of the hull already lost when the shield zone facing the shot is empty (- = it never was)", weapons, targets, _rest, "break")
	_print_table("TABLE 4: percent of the armour of the section facing the shot that is lost when the cell ends (- = the unit has no sections; 0% = the shots glanced)", weapons, targets, _rest, "armour")
	for line in _table7_lines:
		print(line)
	var roles := _roles()
	for line in _role5_lines:
		print(line)
	print("PROBE_JSON ", JSON.stringify({"probe": "ttk_table", "cap_s": CAP_S, "gap": GAP, "targets": targets,
		"rest": _rest, "fast": _fast, "roles": roles, "armour": armour_mode, "gear": gear_on, "research": research_on,
		"parts": Rules.parts_on(), "parts_table": parts_book, "role5": role5}))
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


## The direction from the target to the shooter for --from: the nose (RIGHT), the tail (LEFT),
## the port beam (UP, negative y) or the starboard beam (DOWN).
func _from_dir() -> Vector2:
	match from_side:
		"rear":
			return Vector2.LEFT
		"left":
			return Vector2.UP
		"right":
			return Vector2.DOWN
	return Vector2.RIGHT


## The zone (Rules.ZONE_*) of a pilot-hull target that the shooter faces for --from.
func _from_zone() -> int:
	match from_side:
		"rear":
			return Rules.ZONE_REAR
		"left":
			return Rules.ZONE_LEFT
		"right":
			return Rules.ZONE_RIGHT
	return Rules.ZONE_FRONT


## The zone the shooter faces on `target`: the one of --from for a pilot ship, the front zone
## (zone 0, the only one a one-pool shield uses) for every other target.
func _zone_hit(target: Unit) -> int:
	return _from_zone() if target is Ship else Rules.ZONE_FRONT


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
	if gear_on and team == 1:
		p.inventory[0] = {"id": "suit_armored", "count": 1}
		p.inventory[1] = {"id": "chair_command", "count": 1}
		p.gear_changed()
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
		return (u as Minion).speed
	if u is Mothership:
		return float((u as Mothership).def["move_speed"])
	return 0.0


# --- one cell ---------------------------------------------------------------------

## Fire weapon `wid` at `target` until it is destroyed or the cap is reached.
## `fast`: the target reports its top speed. Returns the cell: {state: "kill" |
## "cap" | "stall" | "nohit", cap: the longest fire in seconds, hits: how many
## ticks a hit landed, ttk: seconds from the first hit to the kill, share:
## 0..1 of the lost points the shield took, at_break: the hull share lost when
## the shield zone facing the shot was emptied (-1 = it never was), armour_lost:
## 0..1 of the armour the most worn front section has lost (-1 = no sections)}.
func _fire(target: Unit, wid: String, fast: bool) -> Dictionary:
	# Step 1: a fresh target: full shields, a hull that cannot die.
	var base_hull := target.hull_max
	target.hull = base_hull + BIG_HULL
	if target.shields != null:
		target.shields.fill()
		target.shields.since_hit = 999.0
	target.damage_log = {}
	# The armour sections start whole (green) or breached (black), as asked.
	if target.armour != null:
		for i in target.armour.count:
			target.armour.a_hp[i] = 0 if armour_mode == "black" else target.armour.a_max[i]
	target.velocity = Vector2(0.0, _top_speed(target)) if fast else Vector2.ZERO
	# Step 2: the shooter stands in front of the target (a mothership: at its
	# side), looking at it, with the weapon bolted on without a spread.
	var dir := Vector2.RIGHT
	if target is Mothership:
		dir = Util.starboard_of(target.rotation)
	elif target is Ship:
		dir = _from_dir()
	# A weapon with an arming distance (the torpedo) is fired at a capsule hull from
	# beside it, not along its length: the stand it needs along the hull's line
	# (past the tip by the arming distance) is on ground where nothing reaches the
	# target (the shooter would stand inside the map rock about 623 units out along the line).
	if from_side == "front" and target.hit_r > 0.0 and float(Weapons.WEAPONS[wid].get("arm", 0.0)) > 0.0:
		dir = Vector2.UP
	var aim_dir := -dir
	# The distance is measured from the target's farthest reach (Unit.hit_reach(),
	# the circle's size for a circle), so a torpedo still has its arming distance
	# to fly when the target is a long capsule hull.
	var stand := target.hit_reach() + GAP
	# Along a hull's length it stands no farther than STAND_MAX out, or the
	# Battlecruiser would be out on ground where nothing is hit.
	if dir == Vector2.RIGHT or dir == Vector2.LEFT:
		stand = minf(stand, STAND_MAX)
	_shooter.global_position = target.global_position + dir * stand
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
		if at_break < 0.0 and target.shields != null and target.shields.max_total > 0.0 and target.shields.values[_zone_hit(target)] <= 0.0:
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
	# The armour of the section facing the shot, lost by now (-1 = no sections). The shot lands on the
	# border of the two front sections of a big hull, so the most worn section of the front zone is read.
	var armour_lost := -1.0
	if target.armour != null:
		armour_lost = 0.0
		var first_sec: int = target.armour.zone_first[_zone_hit(target)]
		for k in int(target.armour.zone_count[_zone_hit(target)]):
			var sec := first_sec + k
			if target.armour.a_max[sec] > 0:
				armour_lost = maxf(armour_lost, float(target.armour.a_max[sec] - target.armour.a_hp[sec]) / float(target.armour.a_max[sec]))
	return {"state": state, "cap": int(cap), "hits": hits, "ttk": snappedf(killed - first, 0.1) if state == "kill" else -1.0,
		"share": snappedf(shield_lost / lost, 0.01) if lost > 0.0 else 0.0, "at_break": snappedf(at_break, 0.01),
		"armour_lost": snappedf(armour_lost, 0.01)}


## TABLE 7 (see the top of the file): print it and return its cells (weapon id -> target id -> cell).
## With the parts switch off nothing is fired and every cell is "-".
func _parts_table(weapons: Array, targets: Array) -> Dictionary:
	var book := {}
	var on := Rules.parts_on()
	_table7_lines.append("TABLE 7: seconds to the first part degraded / seconds to the first part offline / its id (ship parts %s; shot from the front; - = no part hurt in %d s)" % ["on" if on else "off", int(CAP_S)])
	var head := "%-17s" % "weapon"
	var shown := _parts_targets(targets)
	for tid: String in shown:
		head += "%26s" % PARTS_TITLES[tid]
	_table7_lines.append(head)
	for wid: String in PARTS_WEAPONS:
		if not weapons.has(wid):
			continue
		var row := "%-17s" % wid
		for tid: String in shown:
			var cell := {"deg": -1.0, "off": -1.0, "id": ""}
			if on:
				var target := _make_target(tid)
				_place(target, _home)
				cell = _fire_parts(target, wid, _front_dir(target, wid), Vector2.ZERO, -1.0)
				_put(target)
			_store(book, wid, tid, cell)
			row += "%26s" % _parts_text(cell)
		_table7_lines.append(row)
	return book


## The targets of TABLE 7 for this run: the four hulls with parts, those the run asked for (the Ion Frigate comes with the
## Flak Frigate, since the other tables have no column for it).
func _parts_targets(targets: Array) -> Array:
	var out: Array = []
	for tid: String in PARTS_TARGETS:
		if targets.has(tid) or (tid == "ion" and targets.has("flak")):
			out.append(tid)
	return out


## One TABLE 7 cell as text.
func _parts_text(cell: Dictionary) -> String:
	if float(cell["off"]) >= 0.0:
		return "%.1f/%.1f/%s" % [float(cell["deg"]), float(cell["off"]), String(cell["id"])]
	if float(cell["deg"]) >= 0.0:
		return "%.1f/-/%s" % [float(cell["deg"]), String(cell["id"])]
	return "-"


## The direction the shooter stands from target `target` for TABLE 7: ahead of it, or beside it for a
## weapon with an arming distance (as _fire does).
func _front_dir(target: Unit, wid: String) -> Vector2:
	if target.hit_r > 0.0 and float(Weapons.WEAPONS[wid].get("arm", 0.0)) > 0.0:
		return Vector2.UP
	return Vector2.RIGHT


## ROLE 5 (report only): for each hull of the table's four that has an exposed light part, the seconds
## one Fighter cannon needs to take the first such part offline when it is shot from the side the part
## sits on. Returns hull id -> seconds (-1 for not in the time).
func _role5(targets: Array) -> Dictionary:
	var out := {}
	if not Rules.parts_on():
		return out
	for tid: String in _parts_targets(targets):
		var target := _make_target(tid)
		_place(target, _home)
		var part := -1
		if target.parts != null:
			for i in target.parts.count():
				var pr: Dictionary = target.parts.rows[i]
				if int(pr["cls"]) == ShipParts.CLASS_LIGHT and bool(pr["exposed"]):
					part = i
					break
		if part < 0:
			_put(target)
			continue
		var row: Dictionary = target.parts.rows[part]
		var off: Vector2 = row["off"]
		# Outward from the nearest point of the hull's spine to the part (beside the hull, or past an end).
		var half := target.spine_len * 0.5
		var q := Vector2(clampf(off.x, target.spine_off - half, target.spine_off + half), 0.0)
		var n := (off - q).normalized() if off.distance_to(q) > 0.5 else Vector2.UP
		var cell := _fire_parts(target, "fighter_cannon", n, off, float(row["depth"]) + GAP, part)
		out[tid] = cell
		if float(cell["off"]) >= 0.0:
			_role5_lines.append("ROLE 5 (report only): fighter_cannon strips the first exposed light part of %s (%s) in %.1f s" % [tid, String(row["id"]), float(cell["off"])])
		else:
			_role5_lines.append("ROLE 5 (report only): fighter_cannon strips the first exposed light part of %s (%s) in more than %d s (not stripped)" % [tid, String(row["id"]), int(CAP_S)])
		_put(target)
	return out


## Fire weapon `wid` at `target` (a ship with parts) until a part is offline or the target is destroyed or
## the cap is reached, from direction `dir` (the shooter stands out along it), at the point `aim_local` (the
## target's own frame; ZERO = the middle) from `dist` units off the aim point (below 0 = the table's usual
## stand). Returns {deg: seconds to the first part degraded, off: seconds to the first part offline, id:
## that part's id}, with -1 for never. With `only` (a part index) only that part is watched.
func _fire_parts(target: Ship, wid: String, dir: Vector2, aim_local: Vector2, dist: float, only: int = -1) -> Dictionary:
	var cell := {"deg": -1.0, "off": -1.0, "id": ""}
	var parts: ShipSystems = target.parts
	if parts == null:
		return cell
	# A fresh target: full shields, a hull that cannot die, armour whole (or breached).
	var base_hull := target.hull_max
	target.hull = base_hull + BIG_HULL
	if target.shields != null:
		target.shields.fill()
		target.shields.since_hit = 999.0
	target.damage_log = {}
	for i in target.armour.count:
		target.armour.a_hp[i] = 0 if armour_mode == "black" else target.armour.a_max[i]
	target.velocity = Vector2.ZERO
	var aim_dir := -dir
	var stand := dist
	if stand < 0.0:
		stand = target.hit_reach() + GAP
		if dir == Vector2.RIGHT:
			stand = minf(stand, STAND_MAX)
	_shooter.global_position = target.global_position + aim_local + dir * stand
	_shooter.rotation = aim_dir.angle()
	_shooter.velocity = Vector2.ZERO
	_shooter.fan_points = 360
	world.registry.rebuild_hashes()
	var mount := WeaponMount.new(_shooter, wid, "fixed", Vector2.ZERO, 0.0)
	mount.def = mount.def.duplicate()
	mount.def["spread"] = 0.0
	var aim_at := _shooter.global_position + aim_dir * 1000.0
	var t := 0.0
	var first := -1.0
	var last_progress := 0.0
	var hull_lost := 0.0
	while t < CAP_S:
		var trigger := true
		if mount.run != null:
			trigger = not (mount.run.is_full() or mount.run.reload > 0)
			mount.run.pre(mount, trigger, false, null)
		var shield_before := target.shield_total()
		var hull_before := target.hull
		var hp_before := 0
		for i in parts.count():
			hp_before += parts.hp[i]
		mount.update(DT, aim_at, trigger, 1.0, 1.0, 1.0, null)
		world.projectiles.tick(DT)
		var hp_after := 0
		for i in parts.count():
			hp_after += parts.hp[i]
		hull_lost += hull_before - target.hull
		var moved := hull_before != target.hull or shield_before != target.shield_total() or hp_before != hp_after
		if moved:
			last_progress = t
			if first < 0.0:
				first = t
		if target.shields != null:
			target.shields.tick(DT, 1.0, 0.0)
		t += DT
		# The first part that left WORKING, and the first that went offline.
		for i in parts.count():
			if only >= 0 and i != only:
				continue
			var st := parts.state(i)
			if st != ShipSystems.WORKING and float(cell["deg"]) < 0.0:
				cell["deg"] = snappedf(t - first, 0.1)
				cell["id"] = String((parts.rows[i] as Dictionary)["id"])
			if st == ShipSystems.OFF and float(cell["off"]) < 0.0:
				cell["off"] = snappedf(t - first, 0.1)
				cell["id"] = String((parts.rows[i] as Dictionary)["id"])
		if float(cell["off"]) >= 0.0 or hull_lost >= base_hull:
			break
		if first < 0.0 and t >= NO_HIT_S:
			break
		if first >= 0.0 and t - last_progress >= STALL_S:
			break
	_flush()
	return cell


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


## One cell of table 4 as text: the percent of the facing section's armour lost when the cell
## ended, or "-" for a unit with no sections.
func _armour_text(c: Dictionary) -> String:
	return "-" if float(c["armour_lost"]) < 0.0 else "%d%%" % int(round(float(c["armour_lost"]) * 100.0))


## Print one table: a title, the column titles and one row per weapon.
func _print_table(title: String, weapons: Array, targets: Array, book: Dictionary, kind := "ttk") -> void:
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
			var text := _cell_text(cell)
			if kind == "break":
				text = _break_text(cell)
			elif kind == "armour":
				text = _armour_text(cell)
			row += "%11s" % text
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
		var torp_max := ROLE_TORP_MAX_S * ((1.0 + RESEARCH_HULL_STEP * float(RESEARCH_LEVEL)) if research_on else 1.0)
		var holds := td <= torp_max and tb <= torp_max and fd >= ROLE_FIGHTER_MIN_RATIO * td and fb >= ROLE_FIGHTER_MIN_RATIO * tb
		role1 = "HOLDS" if holds else "BREAKS"
		print("ROLE 1 (fighters do not kill capitals alone; torpedoes do): one Fighter cannon needs %s for a Destroyer and %s for a Battlecruiser; one Bomber torpedo needs %s and %s (torpedo within %.0f s and the Fighter at least %.0f times as long) -> %s" % [
			_secs_text(fd), _secs_text(fb), _secs_text(td), _secs_text(tb), torp_max, ROLE_FIGHTER_MIN_RATIO, role1])
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
	# ROLE 3: the strike craft's guns against the Battlecruiser, next to the torpedo.
	var r3 := {}
	var parts: Array = []
	for wid: String in ["scout_gun", "fighter_cannon", "lance_beam", "torpedo"]:
		if _rest.has(wid) and (_rest[wid] as Dictionary).has("battlecruiser"):
			var x := _ttk(wid, "battlecruiser")
			r3[wid] = _json_secs(x)
			parts.append("%s %s" % [wid, _secs_text(x)])
	if not parts.is_empty():
		print("ROLE 3 (strike craft against the Battlecruiser, armour all %s): %s" % [armour_mode, ", ".join(parts)])
	out["role3"] = r3
	# ROLE 4: the Lance is worse than the torpedo against the big hulls and worse than the Fighter's cannon against the small ones.
	var r4 := {}
	var have4 := true
	for wid: String in ["lance_beam", "torpedo", "fighter_cannon"]:
		for tid: String in ["destroyer", "battlecruiser", "fighter", "logistics"]:
			have4 = have4 and _rest.has(wid) and (_rest[wid] as Dictionary).has(tid)
	if not have4:
		out["role4"] = r4
		return out
	var big_worse := true
	var small_worse := true
	var big_parts: Array = []
	var small_parts: Array = []
	for tid: String in ["destroyer", "battlecruiser"]:
		var lt := _ttk("lance_beam", tid)
		var bt := _ttk("torpedo", tid)
		r4["lance_%s" % tid] = _json_secs(lt)
		r4["torpedo_%s" % tid] = _json_secs(bt)
		big_worse = big_worse and lt > bt
		big_parts.append("%s: Lance %s, torpedo %s" % [TITLES[tid], _secs_text(lt), _secs_text(bt)])
	for tid: String in ["fighter", "logistics"]:
		var lt := _ttk("lance_beam", tid)
		var ft := _ttk("fighter_cannon", tid)
		r4["lance_%s" % tid] = _json_secs(lt)
		r4["fighter_%s" % tid] = _json_secs(ft)
		small_worse = small_worse and lt >= ft * (1.0 - ROLE_NEAR_TIE)
		small_parts.append("%s: Lance %s, Fighter cannon %s" % [TITLES[tid], _secs_text(lt), _secs_text(ft)])
	var role4 := "HOLDS" if big_worse and small_worse else "BREAKS"
	r4["verdict"] = role4
	print("ROLE 4 (the Lance is worse than the Bomber against big targets and not better than the Fighter by more than 5%% against small ones; reliability is not read here): %s; %s -> %s" % ["; ".join(big_parts), "; ".join(small_parts), role4])
	out["role4"] = r4
	return out


## A time for the JSON line: seconds, or -1 for "never".
func _json_secs(x: float) -> float:
	return -1.0 if x == INF else x
