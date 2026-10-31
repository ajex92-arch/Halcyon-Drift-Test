extends Node
## WHAT THIS IS: the Bomber probe: a measuring tool for AI-against-AI matches
## that writes down what the pilot Bombers do (torpedoes launched and landed,
## damage and kills against each kind of target, their own deaths), how fast
## the big ships (Destroyers and Battlecruisers) die and how fast the
## motherships fall, so two builds of the game can be put side by side. It
## asserts nothing and changes nothing: it only reads the match.
##
## HOW IT WORKS: it listens to the game's events (a unit killed, a hit
## landed) and, every tick, looks at the Bombers' torpedo guns and at the big
## ships. Every five seconds it takes both motherships' hull and, once a
## minute, writes the pair down. At the end (--secs, or when a mothership
## dies) it prints one "PROBE_JSON {...}" line and quits. What it writes down:
##   launches   runs the pilot Bombers launched (a torpedo gun's cooldown
##              jumping up is one launch), by what the brain was aiming at;
##              "torpedoes" is how many torpedoes those runs sent (the weapon's
##              "lanes" a run, 1 for a gun without lanes), and "fan_points_mean"
##              the mean tightness of the Bombers' fan at the launch (-1 for a
##              build without a fan)
##   hits       torpedoes that touched an enemy, by what they touched, and
##              the hit rate (hits / launches: the torpedoes that land in
##              each run); "lane_hits" splits them by lane and "duds" and
##              "shot_down" count the torpedoes that did nothing or were shot
##              down, all read from the usage counters (zero in a build
##              without lanes)
##   damage     what the Bombers dealt ("torp" = the torpedo gun, "gun" = any
##              other gun) and what everyone dealt, to each kind of target:
##              [damage before shields, damage that reached the hull, hits]
##   kills      what the Bombers killed (and with which gun), how many
##              Bombers died, and what killed them
##   ttk        seconds a Destroyer or Battlecruiser was under fire before it
##              died (a hit more than 4 s after the last starts the count)
##   motherships  the hull of both, once a minute, when each first lost hull
##              and who dealt the hull damage ("bomber" or everyone)
##   rock_cancels  the runs that ended on the ship touching something solid:
##              [match second, ship uid, ticks of the hold counted, speed]
##   usage      Game.usage (how often the AI used each new mechanic)
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --sim-only --test=bomber_probe --secs=3600
## --secs is how many game seconds to watch at most (default 3600); the probe
## also stops when a mothership dies. With --late the match starts at 25:00
## with both sides fully teched (LateGame.apply) and --secs counts from there.
##
## HOW TO READ THE OUTPUT: PROBE_JSON holds the groups above. "T|S" keys are
## "weapon|target": the weapon is "torp" or "gun", the target is "ship:<hull>",
## "minion", "turret", "ms", "bay" or "other". Times are match seconds
## (minutes where the name says so), "team" 0 (Halcyon) or 1 (Cinder).
##
## WHO USES IT: main.gd loads it for --test=bomber_probe. It only reads the
## game and draws no random numbers, so the match plays exactly as without it.
## A script outside the game turns the lines of two builds into the tables.

## The fun probe's helper maths (median, rounding), loaded by path so test
## code stays out of the game's names.
const FunStats := preload("res://tests/lib/fun_stats.gd")
## A hit more than this many seconds after the previous one starts a new
## damage chain (the same gap as the fun probe's stopwatch).
const CHAIN_GAP := 4.0
## Seconds between two looks at the motherships' hulls.
const HULL_STEP := 5.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 3600.0
## The match clock (seconds) when watching began: 0, or 1,500 with --late.
var start_t := 0.0
## True once the line has been printed.
var _done := false
## Seconds until the next look at the motherships' hulls.
var _hull_t := 0.0

## Each Bomber's torpedo-gun cooldown at the last tick: ship uid -> seconds.
var _cd := {}
## Whether each Bomber's torpedo run was on at the last tick: ship uid -> true.
var _run_on := {}
## How many ticks of its hold each Bomber's run had counted at the last tick:
## ship uid -> ticks.
var _run_wind := {}
## The "torpedo_runs_cancel_rock" counter at the last tick.
var _rock_seen := 0
## The runs that ended on touching something solid: [match second, ship uid,
## ticks of the hold counted, speed in world units a second].
var _rock_events: Array = []
## Every Bomber seen: ship uid -> true.
var _bombers_seen := {}
## Ship-seconds the pilot Bombers spent flying.
var _bomber_secs := 0.0
## True once a Bomber with a tail gun has been seen.
var _tail_seen := false
## Runs launched by the pilot Bombers.
var _launches := 0
## Torpedoes those runs sent (the torpedo gun's "lanes" for each run).
var _torpedoes := 0
## The fan tightness of the launching Bomber at each launch, added up.
var _fan_sum := 0.0
## How many launches had a fan tightness (a build without a fan has none).
var _fan_n := 0
## Launches by the target class the pilot's brain had at that moment ("none"
## when it had none or the pilot is a person).
var _launch_at := {}
## Torpedo hits by the target class they touched.
var _hit_at := {}
## What the Bombers dealt: "weapon|target" -> [damage, hull damage, hits].
var _bomber_dmg := {}
## What everyone dealt: target class -> [damage, hull damage, hits].
var _all_dmg := {}
## What the Bombers killed: "weapon|target" -> count.
var _bomber_kills := {}
## Bombers that died.
var _bomber_deaths := 0
## What killed the Bombers: a word for the killer -> count.
var _bomber_killed_by := {}
## Each Destroyer's or Battlecruiser's damage chain: ship uid -> [start, last hit].
var _chain := {}
## Seconds under fire of every Destroyer and Battlecruiser that died, per hull.
var _ttk := {"destroyer": [], "battlecruiser": []}
## Hull damage taken by each mothership, by who dealt it: [team] -> {"bomber",
## "all"} -> hull points.
var _ms_hull_dmg: Array = [{"bomber": 0.0, "all": 0.0}, {"bomber": 0.0, "all": 0.0}]
## Damage before shields taken by each mothership: the same shape.
var _ms_amt: Array = [{"bomber": 0.0, "all": 0.0}, {"bomber": 0.0, "all": 0.0}]
## The first moment (seconds) each mothership lost hull; -1 = never.
var _ms_first_hit := [-1.0, -1.0]
## The motherships' hull fractions once a minute: [minute, team 0, team 1].
var _ms_curve: Array = []
## Seconds until the next minute entry of _ms_curve.
var _curve_t := 60.0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 3600.0))
	# Step 1: --late: the late-game setup (tests/lib/late_game.gd); --secs then
	# counts from 25:00.
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
		secs += LateGame.START
	start_t = world.time
	# Step 2: the game's events. The hit event is only sent when asked for;
	# asking changes nothing in the match.
	Events.unit_killed.connect(_on_killed)
	world.combat.emit_damage_events = true
	Events.damage_applied.connect(_on_damage)


## What kind of target `u` is, as a short word: "ship:<hull>" for a pilot
## ship, else "minion", "turret", "ms", "bay" or "other".
func _target_class(u: Unit) -> String:
	if u == null:
		return "other"
	match u.kind:
		Unit.K_SHIP:
			return "ship:" + (u as Ship).hull_id
		Unit.K_MINION:
			return "minion"
		Unit.K_TURRET:
			return "turret"
		Unit.K_MOTHERSHIP:
			return "ms"
		Unit.K_BAY:
			return "bay"
	return "other"


## Is the shooter of hit `info` a pilot Bomber? The shooter node is checked
## when it still exists; if it died while its round flew, a pilot's torpedo
## can only have come from a Bomber (no other pilot ship carries one).
func _from_bomber(info: DamageInfo) -> bool:
	if info.source != null and is_instance_valid(info.source):
		return info.source is Ship and (info.source as Ship).hull_id == "bomber"
	return info.source_is_pilot and info.kind == Rules.W_TORP


## Add one hit (`amount` before the shields, `hull` that reached the hull) to
## the box `key` of tally `book`.
func _tally(book: Dictionary, key: String, amount: float, hull: float) -> void:
	var e: Array = book.get(key, [0.0, 0.0, 0])
	e[0] = float(e[0]) + amount
	e[1] = float(e[1]) + hull
	e[2] = int(e[2]) + 1
	book[key] = e


## One hit (Events.damage_applied): `target` was hit by `info` for `amount`
## damage, `hull_dmg` of it to the hull.
func _on_damage(target: Node, info: RefCounted, amount: float, hull_dmg: float) -> void:
	var u := target as Unit
	var d := info as DamageInfo
	if u == null or d == null:
		return
	var cls := _target_class(u)
	var bomber := _from_bomber(d)
	# Step 1: everyone's damage by target class, and the Bombers' by weapon.
	_tally(_all_dmg, cls, amount, hull_dmg)
	if bomber:
		_tally(_bomber_dmg, ("torp|" if d.kind == Rules.W_TORP else "gun|") + cls, amount, hull_dmg)
		if d.kind == Rules.W_TORP:
			_hit_at[cls] = int(_hit_at.get(cls, 0)) + 1
	# Step 2: a mothership's hull: when it first lost hull, and who took it.
	if u.kind == Unit.K_MOTHERSHIP and u.team <= 1:
		if hull_dmg > 0.0 and _ms_first_hit[u.team] < 0.0:
			_ms_first_hit[u.team] = world.time
		(_ms_hull_dmg[u.team] as Dictionary)["all"] += hull_dmg
		(_ms_amt[u.team] as Dictionary)["all"] += amount
		if bomber:
			(_ms_hull_dmg[u.team] as Dictionary)["bomber"] += hull_dmg
			(_ms_amt[u.team] as Dictionary)["bomber"] += amount


## A unit died (`u`; `info` is the DamageInfo of the killing blow).
func _on_killed(u: Node, info: RefCounted) -> void:
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null:
		return
	# Step 1: what a Bomber killed, and with which gun.
	if _from_bomber(d):
		var key := ("torp|" if d.kind == Rules.W_TORP else "gun|") + _target_class(unit)
		_bomber_kills[key] = int(_bomber_kills.get(key, 0)) + 1
	# Step 2: a Bomber died: count it and say what killed it.
	if unit is Ship and (unit as Ship).hull_id == "bomber":
		_bomber_deaths += 1
		var by := "environment"
		if d.source != null and is_instance_valid(d.source):
			by = _target_class(d.source)
		elif d.source_is_minion:
			by = "minion"
		elif d.source_is_pilot:
			by = "ship"
		_bomber_killed_by[by] = int(_bomber_killed_by.get(by, 0)) + 1
	# Step 3: a Destroyer or Battlecruiser died: how long was it under fire?
	# The killing hit landed this tick, so the tick look has not seen it: if
	# it came more than CHAIN_GAP after the last hit seen, it starts (and
	# ends) a chain of its own.
	if unit is Ship and _ttk.has((unit as Ship).hull_id):
		var s := unit as Ship
		var chain: Array = _chain.get(s.uid, [])
		var start := world.time
		if not chain.is_empty():
			start = float(chain[0])
			if s.last_damage_time - float(chain[1]) > CHAIN_GAP:
				start = s.last_damage_time
		(_ttk[s.hull_id] as Array).append(maxf(0.0, world.time - start))
		_chain.erase(s.uid)


## Godot calls this every tick; `dt` is the tick's length in seconds.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	# Step 1: the Bombers' torpedo guns, and the big ships' damage chains.
	for s: Ship in world.ships:
		if not s.alive:
			continue
		if s.hull_id == "bomber":
			_look_at_bomber(s, dt)
		elif _ttk.has(s.hull_id):
			_look_at_big(s)
	_rock_seen = int(Game.usage.get("torpedo_runs_cancel_rock", 0))
	# Step 2: both motherships' hulls, every 5 s (the first hit) and once a
	# minute (the curve).
	_hull_t += dt
	if _hull_t >= HULL_STEP:
		_hull_t -= HULL_STEP
		for t in 2:
			var ms := world.mothership(t)
			if ms != null and _ms_first_hit[t] < 0.0 and ms.hull < ms.hull_max - 1.0:
				_ms_first_hit[t] = world.time
	_curve_t -= dt
	if _curve_t <= 0.0:
		_curve_t += 60.0
		_ms_curve.append([int(world.time / 60.0), _hull(0), _hull(1)])
	# Step 3: the end: time is up, or a mothership died.
	if world.time >= secs or world.phase != "play":
		_done = true
		print("PROBE_JSON " + JSON.stringify(_results()))
		get_tree().quit()


## Bomber `s`: count it, and count a launch when its torpedo gun's cooldown
## jumped up since the last tick.
func _look_at_bomber(s: Ship, dt: float) -> void:
	_bombers_seen[s.uid] = true
	_bomber_secs += dt
	for m: WeaponMount in s.mounts:
		if m.weapon_id == "tail_gun":
			_tail_seen = true
		if m.weapon_id != "torpedo":
			continue
		# A run that ended without a launch on a tick when the rock counter rose is a
		# rock cancel: note how far into the hold it was and how fast the ship went.
		if m.run != null:
			if bool(_run_on.get(s.uid, false)) and not m.run.on and m.run.reload == 0 and int(Game.usage.get("torpedo_runs_cancel_rock", 0)) > _rock_seen:
				_rock_events.append([int(world.time), s.uid, int(_run_wind.get(s.uid, 0)), int(s.velocity.length())])
			_run_on[s.uid] = m.run.on
			_run_wind[s.uid] = m.run.wind
		var before := float(_cd.get(s.uid, 0.0))
		_cd[s.uid] = m.cd
		if m.cd > before + 0.01:
			_launches += 1
			_torpedoes += int(m.def.get("lanes", 1))
			var points = s.get("fan_points")
			if points != null:
				_fan_sum += float(points)
				_fan_n += 1
			var at := "none"
			if s.controller is PilotAI and (s.controller as PilotAI).target != null:
				var t: Unit = (s.controller as PilotAI).target
				if is_instance_valid(t) and t.alive:
					at = _target_class(t)
			_launch_at[at] = int(_launch_at.get(at, 0)) + 1


## Big ship `s`: a hit since the last look starts a new chain when the one
## before it is more than CHAIN_GAP old.
func _look_at_big(s: Ship) -> void:
	var lt := s.last_damage_time
	var chain: Array = _chain.get(s.uid, [])
	if chain.is_empty() or (lt > float(chain[1]) and lt - float(chain[1]) > CHAIN_GAP):
		if lt > -900.0:
			_chain[s.uid] = [lt, lt]
	elif lt > float(chain[1]):
		chain[1] = lt


## Mothership `t`'s hull as a 0..1 fraction (0 once destroyed).
func _hull(t: int) -> float:
	var ms := world.mothership(t)
	return snappedf(ms.hull_frac(), 0.001) if ms != null and ms.alive else 0.0


## Every usage counter whose name starts with `prefix`, as name -> count (the
## counters of one kind, such as the hits of each lane; empty when the build
## never counts them).
func _usage_group(prefix: String) -> Dictionary:
	var out := {}
	for k: String in Game.usage:
		if k.begins_with(prefix):
			out[k] = int(Game.usage[k])
	return out


## A match time in minutes (2 decimals), or -1 for "never happened".
func _min_or_never(t: float) -> float:
	return snappedf(t / 60.0, 0.01) if t >= 0.0 else -1.0


## A tally book turned into whole numbers for printing.
func _whole(book: Dictionary) -> Dictionary:
	var out := {}
	for k: String in book:
		var e: Array = book[k]
		out[k] = [int(e[0]), int(e[1]), int(e[2])]
	return out


## Every number, in one dictionary (printed as PROBE_JSON).
func _results() -> Dictionary:
	# Step 1: the match, the torpedoes that landed, and the two tables.
	var ended := world.phase != "play"
	var hits := 0
	for k: String in _hit_at:
		hits += int(_hit_at[k])
	var ttk_out := {}
	for h: String in _ttk:
		ttk_out[h] = {"n": (_ttk[h] as Array).size(), "med_s": FunStats.snap(FunStats.median(_ttk[h]), 0.01), "all": FunStats.snap_all(_ttk[h], 0.1)}
	var ms_dmg := []
	for t in 2:
		var h: Dictionary = _ms_hull_dmg[t]
		var a: Dictionary = _ms_amt[t]
		ms_dmg.append({"hull_bomber": int(h["bomber"]), "hull_all": int(h["all"]), "amt_bomber": int(a["bomber"]), "amt_all": int(a["all"])})
	return {
		"probe": "bomber_probe",
		"version": 1,
		"seed": int(Game.opt("seed", -1)),
		"late_start": start_t > 0.0,
		"secs_cap": int(secs),
		"variants": Game.variants,
		"ended": ended,
		"winner": world.winner if ended else -1,
		"minutes": snappedf(world.time / 60.0, 0.01),
		"tail_gun": _tail_seen,
		"bombers_seen": _bombers_seen.size(),
		"bomber_secs": int(_bomber_secs),
		"launches": _launches,
		"torpedoes": _torpedoes,
		"fan_points_mean": snappedf(_fan_sum / float(_fan_n), 0.1) if _fan_n > 0 else -1.0,
		"launch_at": _launch_at,
		"hits": hits,
		"hit_at": _hit_at,
		"hit_rate": snappedf(float(hits) / float(maxi(1, _launches)), 0.001),
		"lane_hits": _usage_group("torpedo_lane_hit_"),
		"duds": _usage_group("torpedo_dud"),
		"shot_down": _usage_group("torpedo_shot_down"),
		"bomber_dmg": _whole(_bomber_dmg),
		"all_dmg": _whole(_all_dmg),
		"bomber_kills": _bomber_kills,
		"bomber_deaths": _bomber_deaths,
		"bomber_killed_by": _bomber_killed_by,
		"ttk": ttk_out,
		"ms_first_hull_hit_min": [_min_or_never(_ms_first_hit[0]), _min_or_never(_ms_first_hit[1])],
		"ms_hull_dmg": ms_dmg,
		"ms_curve": _ms_curve,
		"ms_hull_now": [_hull(0), _hull(1)],
		"rock_cancels": _rock_events,
		"usage": Game.usage.duplicate(true),
	}
