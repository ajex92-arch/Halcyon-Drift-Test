extends Node
## WHAT THIS IS: the measurement for the map's cover (gas clouds and hidden
## pockets) in ONE AI-against-AI match. It runs three of the usual probes side
## by side, so a single match gives all the numbers: pilot_audit (stuck
## episodes, rock contact, crash deaths), lane_probe (minion waves reaching each
## lane's end) and fun_probe (fights of 10 or more ships, match length, the
## winner). On top it counts what only the cover changes: ships killed inside a
## cover patch, kills made by a unit that stood in one, and how many of the
## ships sampled each second stood in one and how many of those were hidden from
## the other team. It only reads the match, and it also runs on a build that has
## no cover part (then every ship counts as in the open), so the same file
## measures the "before" builds.
##
## HOW IT WORKS: setup() makes the three probes as child nodes and starts them
## (each sets itself up and prints its own result line when the match ends:
## AUDIT_JSON, LANE_JSON, FUN_JSON). They all stop on the same tick (the match
## time reaches --secs, or a mothership falls), so all of them print before the
## game quits. This node watches every kill (Events.unit_killed) and samples the
## ships once a second, and prints one line at the end: COVER_JSON {...}.
##
## HOW TO RUN IT (from the project folder, the usual gate options):
##   godot --headless --path . --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --sim-only --test=cover_gate --secs=1800
##
## WHO USES IT: main.gd loads it for --test=cover_gate (tests/<name>.gd, added
## after the World, then setup() is called). The lead's gate-3 runs go through
## run_batch with this test.

## The match's World (set by setup()).
var world: World
## The fog's cover part (Vision.cover), or null on a build without one.
var _cover: Variant = null
## The seconds to watch at most (--secs, default 1800).
var secs := 1800.0
## True once COVER_JSON was printed.
var _done := false
## The pilot_audit probe (a child node).
var _audit: Node
## The lane_probe probe (a child node).
var _lanes: Node
## The fun_probe probe (a child node).
var _fun: Node
## Ships that died (any killer).
var ships_killed := 0
## Ships that died inside a cover patch.
var ships_killed_in_cover := 0
## Kills (any victim) made by a ship or minion standing in a cover patch.
var kills_from_cover := 0
## Kills (any victim) made by a ship or minion standing in open space.
var kills_from_open := 0
## Ship samples taken (one per live ship per second).
var ship_samples := 0
## Ship samples where the ship stood in a cover patch.
var in_cover_samples := 0
## Ship samples where the ship stood in a cover patch and the other team did not
## see it (Unit.visible_to).
var hidden_samples := 0
## Seconds until the next ship sample.
var _sample_t := 1.0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	_cover = w.vision.get("cover")
	secs = float(Game.opt("secs", 1800.0))
	_audit = load("res://tests/pilot_audit.gd").new()
	_lanes = load("res://tests/lane_probe.gd").new()
	_fun = load("res://tests/fun_probe.gd").new()
	for probe: Node in [_audit, _lanes, _fun]:
		add_child(probe)
		probe.call("setup", w)
	Events.unit_killed.connect(_on_killed)


## A unit died: count it by where the victim and the killer stood.
func _on_killed(u: Node, info: RefCounted) -> void:
	var victim := u as Unit
	var di := info as DamageInfo
	if victim != null and victim.kind == Unit.K_SHIP:
		ships_killed += 1
		if _in_cover(victim.global_position):
			ships_killed_in_cover += 1
	if di != null and di.source != null and is_instance_valid(di.source):
		var killer := di.source as Unit
		if killer != null and (killer.kind == Unit.K_SHIP or killer.kind == Unit.K_MINION):
			if _in_cover(killer.global_position):
				kills_from_cover += 1
			else:
				kills_from_open += 1


## True if world point `p` lies in a cover patch (always false on a build
## without a cover part).
func _in_cover(p: Vector2) -> bool:
	return _cover != null and int(_cover.call("patch_at", p)) != 0


## Every tick: sample the ships once a second, and print COVER_JSON when the
## match ends (the same moment the three probes print theirs).
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 1.0
		for s: Ship in world.ships:
			if not s.alive:
				continue
			ship_samples += 1
			if _in_cover(s.global_position):
				in_cover_samples += 1
				if not s.visible_to(1 - s.team):
					hidden_samples += 1
	if world.time >= secs or world.phase != "play":
		_done = true
		print("COVER_JSON ", JSON.stringify({
			"time": snappedf(world.time, 1.0),
			"patches": 0 if _cover == null else int(_cover.call("count")),
			"ships_killed": ships_killed,
			"ships_killed_in_cover": ships_killed_in_cover,
			"kills_from_cover": kills_from_cover,
			"kills_from_open": kills_from_open,
			"ship_samples": ship_samples,
			"in_cover_samples": in_cover_samples,
			"hidden_samples": hidden_samples,
		}))
