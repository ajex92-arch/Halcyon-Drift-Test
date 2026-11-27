class_name JungleDirector
extends RefCounted
## WHAT THIS IS: looks after the jungle monster camps. A camp is a spot in
## the jungle (the space between the lanes) where a neutral derelict ship
## sits; killing it pays a reward. DESIGN.md A10.
##
## HOW IT WORKS: setup() spawns a derelict at every camp in the map. When
## one is killed, on_camp_killed() sets the time it comes back
## (Jungle.CAMPS[type]["respawn"]: 80 s for a gunship, 120 s for a
## carrier). tick() spawns it again once that time is reached.
##
## The practice range (and nothing else) may bring camps back at once: respawn_all() and
## respawn_camp() take the old derelict and its snub fighters away quietly (no pay, no event) and
## spawn a fresh one with its timer cleared.
##
## WHO USES IT: World makes one (World.jungle_director) in WorldSetup,
## which calls setup() unless the "no-jungle" test switch is on; World
## calls tick() every tick. Derelict calls on_camp_killed() when it dies.
## AI junglers (PilotAI) call live_camps() to find camps to clear.

## The match the camps live in.
var world: World
## One entry per camp: camp id -> {"info": the camp's map data (id, type,
## pos), "unit": its live Derelict or null, "respawn_at": match time in
## seconds when it comes back}.
var camps := {}


## Remember the world. WorldSetup makes this once per match.
func _init(w: World) -> void:
	world = w


## Make an entry for every camp in the map and spawn its derelict.
func setup() -> void:
	for c: Dictionary in world.map.camps:
		camps[c["id"]] = {"info": c, "unit": null, "respawn_at": 0.0}
		_spawn(c["id"])


## Spawn camp `id`'s derelict at the camp's position and remember it.
func _spawn(id: String) -> void:
	var e: Dictionary = camps[id]
	var c: Dictionary = e["info"]
	e["unit"] = world.spawn_derelict(id, c["type"], c["pos"])


## Called by Derelict when camp `id`'s derelict dies: forget it and set the
## time it respawns.
func on_camp_killed(id: String) -> void:
	if not camps.has(id):
		return
	var e: Dictionary = camps[id]
	e["unit"] = null
	var type_id: String = e["info"]["type"]
	e["respawn_at"] = world.time + float(Jungle.CAMPS[type_id]["respawn"])


## Called by World every tick: respawn each empty camp whose time has come.
## `_dt` is not used (we go by the match clock).
func tick(_dt: float) -> void:
	for id: String in camps:
		var e: Dictionary = camps[id]
		if e["unit"] == null and world.time >= float(e["respawn_at"]):
			_spawn(id)


## Bring every camp back now (the practice range's Respawn all camps): a live camp is replaced,
## an empty one is simply spawned. Returns "" or the text that says the match has no camps.
func respawn_all() -> String:
	if camps.is_empty():
		return PracticeSwitches.TEXT_NO_JUNGLE
	for id: String in camps:
		_replace(id)
	return ""


## Bring camp `id` back now (the practice range's Respawn nearest camp). Returns "" or the reason
## (the text for an id this match has no camp for).
func respawn_camp(id: String) -> String:
	if not camps.has(id):
		return PracticeSwitches.TEXT_NO_CAMP
	_replace(id)
	return ""


## Put a fresh derelict in camp `id`: the old one and its snub fighters are taken away quietly
## (no pay, no kill message, no respawn timer), the entry is cleared and a new derelict is made
## with its fight state and damage log empty. The new one shows one pale ring (drawing only).
func _replace(id: String) -> void:
	var e: Dictionary = camps[id]
	var old: Variant = e["unit"]
	if old != null and is_instance_valid(old):
		var d := old as Derelict
		for s: Variant in d.snubs:
			if is_instance_valid(s):
				world.combat.kill_silently(s as Unit)
		world.combat.kill_silently(d)
	e["unit"] = null
	e["respawn_at"] = 0.0
	_spawn(id)
	var at: Vector2 = (e["info"] as Dictionary)["pos"]
	world.effects.pulse(at, PracticeSwitches.PULSE_RADIUS, PracticeSwitches.PULSE_LIFE, PracticeSwitches.PULSE_COLOR)


## The derelicts currently up (alive), for AI junglers.
func live_camps() -> Array:
	var out: Array = []
	for id: String in camps:
		var u = camps[id]["unit"]
		if u != null and is_instance_valid(u) and u.alive:
			out.append(u)
	return out
