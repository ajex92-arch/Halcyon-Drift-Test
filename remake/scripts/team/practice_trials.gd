class_name PracticeTrials
extends RefCounted
## WHAT THIS IS: the practice range's trials: one small test of aim for each ship
## class, and the score of the one the human is flying now ("hit five moving
## drones with the Lance bolt"). A trial starts when the human launches a ship in
## a practice match, starts again on every new launch and ends with a result
## line: how many hits, and how many seconds they took. Nothing is saved.
##
## HOW IT WORKS:
##   - HullTables.TRIALS is one table, a row for each ship class (the order of Ships.ORDER).
##     A row is {hull, text, target, count, weapon, secs}: the class, the words
##     of the task, which kind of drone must be hit ("moving" or "capital"), how
##     many different drones must be hit, the weapon id whose hits count (its
##     weapon kind is compared with the kind of the hit), and the time limit in
##     seconds (0 = no limit). A class without a row of its own has none.
##   - tick() (once a World tick, from PracticeRange) looks at the human's ship.
##     A new ship starts a new trial for its class. A trial with a time limit
##     ends when the limit is up.
##   - A hit counts (Events.damage_applied) when the human's own ship dealt it, it
##     landed on a drone of the trial's kind, and its weapon kind is the trial's.
##     Each drone counts once per trial (a beam that stays on a drone is one hit),
##     so "hit five drones" means five different drones. A hit of another weapon
##     counts for nothing. A drone destroyed by the human adds to the trial's kill
##     count (Events.unit_killed), which the score line shows.
##   - The state is "idle" (no ship launched yet), "running", "done" (the count
##     was reached) or "timeout" (the limit ran out first). It only reads the
##     match: it changes nothing in it.
##
## WHO USES IT: PracticeRange makes it (World.practice_range.trials) and calls
## tick(); PracticeStatus draws its words, count and clock every frame.

## The world whose human is tried.
var world: World
## "idle", "running", "done" or "timeout" (see the top of the file).
var state := "idle"
## The row of the trial now running or last finished (empty before the first launch).
var trial: Dictionary = {}
## The uids of the drones hit so far in this trial, each once.
var hit_uids: Array[int] = []
## How many drones the human destroyed in this trial.
var kills := 0
## The match time the trial started [seconds].
var started_at := 0.0
## The match time the trial ended [seconds]; 0 while it runs.
var ended_at := 0.0
## The ship the human flew when the trial started (to see a new launch).
var _ship_id := 0


## Make the trials of world `w` and listen to the damage and kill events.
func _init(w: World) -> void:
	world = w
	Events.damage_applied.connect(_on_damage)
	Events.unit_killed.connect(_on_killed)


## The trial row of ship class `hull`, or an empty dictionary for a class with none.
static func row_for(hull: String) -> Dictionary:
	for r: Dictionary in HullTables.TRIALS:
		if r["hull"] == hull:
			return r
	return {}


## One World tick: start a new trial for a ship the human has just launched, and end
## a timed trial whose limit ran out.
func tick() -> void:
	var h := world.human
	if h != null and is_instance_valid(h.ship) and h.ship.alive and h.ship.get_instance_id() != _ship_id:
		_start(h.ship)
	if state == "running" and float(trial["secs"]) > 0.0 and world.time - started_at >= float(trial["secs"]):
		state = "timeout"
		ended_at = world.time


## Start the trial of the class of `ship`, the human's new ship.
func _start(ship: Ship) -> void:
	_ship_id = ship.get_instance_id()
	trial = row_for(ship.hull_id)
	hit_uids.clear()
	kills = 0
	ended_at = 0.0
	if trial.is_empty():
		state = "idle"
		return
	state = "running"
	started_at = world.time


## Did the human's ship deal `info`, with the weapon kind of the trial, to a drone of the
## trial's kind? Only then does it count.
func _counts(target: Node, info: RefCounted) -> bool:
	if state != "running" or not (target is PracticeDrone):
		return false
	var d := info as DamageInfo
	if d == null or d.source_profile == null or d.source_profile != world.human:
		return false
	return d.kind == Weapons.kind_id(Weapons.get_def(String(trial["weapon"])))


## Events.damage_applied: count a hit on a drone of the trial's kind, once for each drone, and
## finish the trial when the count is reached.
func _on_damage(target: Node, info: RefCounted, _amount: float, _hull_dmg: float) -> void:
	if world == null or not is_instance_valid(world) or not _counts(target, info):
		return
	var drone := target as PracticeDrone
	if drone.row_id != String(trial["target"]) or hit_uids.has(drone.uid):
		return
	hit_uids.append(drone.uid)
	if hit_uids.size() >= int(trial["count"]):
		state = "done"
		ended_at = world.time


## Events.unit_killed: a drone destroyed by the human's ship adds to the kill count of a
## trial that is running.
func _on_killed(unit: Node, info: RefCounted) -> void:
	if world == null or not is_instance_valid(world) or state != "running" or not (unit is PracticeDrone):
		return
	var d := info as DamageInfo
	if d != null and d.source_profile != null and d.source_profile == world.human:
		kills += 1


## The words of the task now, or a hint to launch while no trial has started.
func text() -> String:
	if trial.is_empty():
		return "Launch a ship to start its trial"
	return String(trial["text"])


## How many drones have been hit of how many are needed ("2 / 5"), or "" with no trial.
func count_text() -> String:
	if trial.is_empty():
		return ""
	return "%d / %d" % [hit_uids.size(), int(trial["count"])]


## The seconds the trial has run: still counting while it runs, fixed once it ended.
func seconds() -> float:
	if state == "running":
		return maxf(0.0, world.time - started_at)
	if state == "done" or state == "timeout":
		return maxf(0.0, ended_at - started_at)
	return 0.0


## The clock of the trial ("0:23.4"), or "" with no trial; with a time limit it shows
## the time left while the trial runs.
func clock_text() -> String:
	if trial.is_empty():
		return ""
	var secs := seconds()
	if state == "running" and float(trial["secs"]) > 0.0:
		secs = maxf(0.0, float(trial["secs"]) - secs)
	return "%d:%04.1f" % [floori(secs / 60.0), fmod(secs, 60.0)]


## The result once the trial has ended ("Done: 5 hits in 23.4 s", "Time up: 3 of 5 hits"),
## or "" while it has not.
func result_line() -> String:
	if state == "done":
		return "Done: %d hit%s in %.1f s" % [hit_uids.size(), "" if hit_uids.size() == 1 else "s", seconds()]
	if state == "timeout":
		return "Time up: %d of %d hits" % [hit_uids.size(), int(trial["count"])]
	return ""
