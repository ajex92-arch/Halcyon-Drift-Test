extends Node
## WHAT THIS IS: the check that a held bought ship does not step away from an enemy turret (T-13
## note 29). A bought ship flies on the stand-in brain (Standin), which is the pilot brain held to
## its squadron's point. The pilot brain makes a small or medium ship that an enemy turret targets
## fly 2,600 units out and back (PilotAI step 3 and 5), so a Logistics Corvette told to hold or move
## to a point inside a turret's range used to circle there. A crew whose squadron stands under a Move
## or a Hold order now stays on its point (Standin.holds_position()); every other crew, and every
## pilot, still steps away.
##
## HOW IT WORKS: each run is one case, picked with --hold-case=<a to e>. setup() stops the minion
## waves; the first tick takes the live built turret of team 1 nearest team 0's mothership, buys one
## Logistics Corvette for team 0 the way arrival_check does, puts it at the turret's range minus 300
## units, and spawns three team 0 minions inside the turret's range (so PilotGoals.think_lane() does
## not push the ship out: three of its minions tank the turret). Every tick it puts the minions back
## at their places with full hull, keeps the ship's hull full, and stamps the ship as the one that
## just hurt the turret's side (aggro_time and aggro_victim_pos), which is the only thing that makes
## a turret shoot a ship while minions stand beside it. It runs 120 game seconds, counts the evade
## cycles (a tick where the brain's evade_t goes from 0 to above 0) and the greatest distance from
## the hold point, and prints "HOLD_CASE <x> evade_cycles=<n> max_dist=<d> turret_targeted=<n>".
##   a  a Hold order at the ship's place: 0 evade cycles, at most 600 units away.
##   b  a Move order to it: the same.
##   c  no order (the rally is the ship's place): at least 1 evade cycle (the rule stays narrow).
##   d  an Attack order on the turret: at least 1 evade cycle.
##   e  a pilot-profile Logistics Corvette (not a crew) holding that place: at least 1 evade cycle.
## Every case first asserts that the turret targeted the ship at least once (else it did not reach
## the code under test) and that the ship's size class is below SIZE_LARGE.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --sim-only --test=standin_hold_check --hold-case=a
## (and b to e).
##
## HOW TO READ THE OUTPUT: the HOLD_CASE line, one PASS or FAIL line per check, and the last line
## "standin_hold_check: N failures"; 0 failures means the case holds.
##
## WHO USES IT: main.gd loads it for --test=standin_hold_check; run_checks runs the five cases.

## One tick, in seconds.
const DT := 1.0 / 60.0
## Game seconds a case runs.
const RUN_SECS := 120.0
## Units inside the turret's range the ship stands.
const INSET := 300.0
## The most a held ship may wander from its point (units).
const MAX_WANDER := 600.0
## How many minions tank the turret.
const MINIONS := 3

## The running match (set by setup()).
var world: World
## The case: "a" to "e".
var case_id := "a"
## How many checks failed.
var fails := 0
## True once the scenario is built (the first tick).
var _built := false
## The turret under test.
var turret: Turret
## The ship under test.
var ship: Ship
## The brain of the ship under test.
var brain: PilotAI
## The hold point: where the ship stands.
var place := Vector2.ZERO
## A point inside the turret's range, the aggro stamp's victim place.
var victim_pos := Vector2.ZERO
## The three minions of team 0.
var minions: Array = []
## The places the minions are kept at, one for each.
var minion_places: Array = []
## Measurement: ticks where the brain's evade_t went from 0 to above 0.
var evade_cycles := 0
## Measurement: the greatest distance (units) the ship got from its place.
var max_dist := 0.0
## Measurement: ticks on which the turret had the ship as its target.
var turret_targeted := 0
## The brain's evade_t at the last tick.
var _prev_evade := 0.0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	SquadronRules.use_squad_brain = false  # this check pins the stand-in's own internals
	case_id = str(Game.opt("hold-case", "a"))
	world.minion_director.next_wave = INF


## Print one PASS or FAIL line for the check `name` (`ok` = it passed), and count it.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Build the scenario in the first tick, then measure every tick and report at the end.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if not _built:
		_built = true
		if not _build():
			_finish()
		return
	_keep()
	_measure()
	if world.time >= RUN_SECS:
		_finish()


## Print the result and quit.
func _finish() -> void:
	print("HOLD_CASE %s evade_cycles=%d max_dist=%d turret_targeted=%d" % [case_id, evade_cycles, roundi(max_dist), turret_targeted])
	if ship != null:
		_check("the ship is below SIZE_LARGE (size %d)" % ship.size_class, ship.size_class < Rules.SIZE_LARGE)
		_check("the turret targeted the ship at least once (else the case did not reach the code)", turret_targeted >= 1, "%d ticks" % turret_targeted)
		if case_id == "a" or case_id == "b":
			_check("%s: no evade cycle" % case_id, evade_cycles == 0, "%d cycles" % evade_cycles)
			_check("%s: never more than %d units from its point" % [case_id, roundi(MAX_WANDER)], max_dist <= MAX_WANDER, "%d units" % roundi(max_dist))
		else:
			_check("%s: at least one evade cycle (the rule is narrow)" % case_id, evade_cycles >= 1, "%d cycles" % evade_cycles)
	print("standin_hold_check: %d failures" % fails)
	get_tree().quit()


## Make the scenario. Returns false (after a FAIL line) when it cannot be built.
func _build() -> bool:
	if not case_id in ["a", "b", "c", "d", "e"]:
		_check("the case is a to e", false, case_id)
		return false
	var ms0 := world.mothership(0)
	turret = null
	var best := INF
	for t: Turret in world.turrets:
		if t.team != 1 or not t.alive or not t.is_built():
			continue
		var d := t.global_position.distance_to(ms0.global_position)
		if d < best:
			best = d
			turret = t
	if turret == null:
		_check("an enemy turret is built", false)
		return false
	# The place: range minus 300 from the turret, toward our mothership; turn away from rocks.
	var base := (ms0.global_position - turret.global_position).angle()
	var found := false
	for k in 25:
		var steps := int(float(k + 1) * 0.5)
		var ang := base + deg_to_rad(float(steps * 15) * (1.0 if k % 2 == 1 else -1.0))
		var dir := Vector2.from_angle(ang)
		var at := turret.global_position + dir * (turret.range_r - INSET)
		var inner := turret.global_position + dir * (turret.range_r - 800.0)
		if world.asteroids.blocked(at, 120.0) or world.asteroids.segment_blocked(turret.global_position, at):
			continue
		var side := Vector2(-dir.y, dir.x)
		var ok := true
		var spots: Array = []
		for j in MINIONS:
			var sp := inner + side * float(j - 1) * 250.0
			if world.asteroids.blocked(sp, 60.0):
				ok = false
			spots.append(sp)
		if not ok:
			continue
		place = at
		victim_pos = inner
		minion_places = spots
		found = true
		break
	if not found:
		_check("a clear place inside the turret's range", false)
		return false
	_make_ship()
	if ship == null:
		_check("the ship was made", false)
		return false
	for sp: Vector2 in minion_places:
		var m := world.spawn_minion(0, "fighter", "mid", sp)
		minions.append(m)
	print("standin_hold_check: case %s, turret at (%d,%d) range %d, ship at (%d,%d)" % [case_id, turret.global_position.x, turret.global_position.y, roundi(turret.range_r), place.x, place.y])
	return true


## Make the ship of the case at `place`, with its brain.
func _make_ship() -> void:
	if case_id == "e":
		var p := PilotProfile.new("holdcheck", 0, 0, false)
		p.hull_id = "logistics"
		p.role = "mid"
		world.profiles.append(p)
		brain = PilotAI.new(world, p)
		brain.skill = 0.7
		world.pilot_ai[p] = brain
		ship = world.launch(p)
		if ship == null:
			return
		ship.global_position = place
		ship.velocity = Vector2.ZERO
		ship.rotation = (turret.global_position - place).angle() + PI
		brain._reset_after_launch()
		brain.hold_point = place
		return
	var prod := world.teams[0].production
	var it := prod.spawn_now("logistics", 1)
	var sq: Squad = world.squads.get(int(it["squad"])) as Squad
	for uid: int in sq.member_uids:
		ship = world.by_uid.get(uid) as Ship
	if ship == null:
		return
	ship.global_position = place
	ship.velocity = Vector2.ZERO
	ship.rotation = (turret.global_position - place).angle() + PI
	brain = ship.controller as PilotAI
	sq.rally = Vector2i(place)
	var seat := Rules.ADMIRAL_SEAT
	if case_id == "a" or case_id == "b":
		var kind := OrderKinds.HOLD if case_id == "a" else OrderKinds.MOVE
		var r := world.orders.submit(Order.make(kind, 0, seat, true, {}, [sq.id], "point", Vector2i(place)))
		_check("the order is accepted", r == "", r)
		world.tick_count += 1
		world.orders.run_due()
	elif case_id == "d":
		sq.order = {"kind": OrderKinds.ATTACK, "target_kind": "unit", "target": turret.uid, "tick": world.tick_count, "settings": {}}
	brain.hold_point = Standin.hold_point_of(sq, ship)


## Every tick: the minions back at their places with full hull, the ship's hull full and
## stamped as the one that just hurt the turret's side.
func _keep() -> void:
	for i in minions.size():
		var m: Variant = minions[i]
		if is_instance_valid(m) and (m as Minion).alive:
			(m as Minion).global_position = minion_places[i]
			(m as Minion).hull = (m as Minion).hull_max
	if not is_instance_valid(ship) or not ship.alive:
		return
	ship.hull = ship.hull_max
	ship.aggro_time = world.time
	ship.aggro_victim_pos = victim_pos
	if case_id == "e":
		brain.launched_at = world.time


## Every tick: the evade cycles, the wander and the ticks the turret had the ship as its target.
func _measure() -> void:
	if not is_instance_valid(ship) or not ship.alive:
		return
	if _prev_evade <= 0.0 and brain.evade_t > 0.0:
		evade_cycles += 1
	_prev_evade = brain.evade_t
	max_dist = maxf(max_dist, ship.global_position.distance_to(place))
	if is_instance_valid(turret) and turret.target == ship:
		turret_targeted += 1
