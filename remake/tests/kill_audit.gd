extends Node
## WHAT THIS IS: the kill audit: a measuring tool for a whole AI-against-AI
## match that counts who killed what, with which kind of weapon. It asserts
## nothing and changes nothing: its numbers are put side by side for two
## builds of the game.
##
## HOW IT WORKS: it listens to every kill and every hit of the match. For each
## kill it writes down the weapon family of the killing blow (bolt, lance,
## torp, flak, pd, shell, ion, collision, pure) and the class of what died:
## a pilot ship by size ("light", "corvette", "frigate") or by hull for the
## two capitals ("destroyer", "battlecruiser"), "minion", "turret",
## "mothership" or the kind of anything else. For every pilot ship it also
## writes down the cause of the death (a pilot, a minion, a turret, the
## mothership, a derelict, a rock). A big ship (frigate or capital) that dies
## is listed on its own with who killed it, in what, and with which weapon
## family. Turrets and motherships lost are counted per team. Every hit is
## added to the damage book of its weapon family (how much arrived and how
## much of it reached the hull). At the end (match time `--secs`, default
## 1800, or a mothership down) it prints the book.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --test=kill_audit --secs=1800
##
## HOW TO READ THE OUTPUT: one "KILL_AUDIT_JSON {...}" line: seed, minutes
## played, whether the match ended and who won (team 0 = Aurelian, 1 =
## Vhorr, -1 = none), "kills" (weapon family -> class -> number), "deaths_by"
## (cause -> number of pilot ship deaths), "big" (one entry per big ship
## lost: time in seconds, team, hull, killer's kind and hull, weapon family),
## "turrets_lost" and "motherships_lost" (a number per team), and "damage"
## (weapon family -> [damage that arrived, damage that reached the hull]).
##
## WHO USES IT: main.gd loads it for --test=kill_audit. It only reads the game
## (it connects to Events.unit_killed and Events.damage_applied and switches on
## Combat.emit_damage_events so the second one is sent) and draws no random
## numbers.

## The weapon family names, by Rules.W_* number.
const FAMILIES := ["bolt", "lance", "torp", "flak", "pd", "shell", "ion", "collision", "pure"]
## The pilot hulls that count as big ships.
const BIG_HULLS := ["flak", "ion", "destroyer", "battlecruiser"]

## The running match (set by setup()).
var world: World
## Match time (seconds) at which to stop.
var secs := 1800.0
## True once the result has been printed.
var _done := false
## Kills: weapon family -> class of the victim -> number.
var kills := {}
## Pilot ship deaths: cause -> number.
var deaths_by := {}
## One entry per big ship lost.
var big: Array = []
## Turrets lost, per team.
var turrets_lost := [0, 0]
## Motherships lost, per team.
var motherships_lost := [0, 0]
## Damage book: weapon family -> [damage that arrived, damage to the hull].
var damage := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	Events.unit_killed.connect(_on_unit_killed)
	if Events.has_signal("damage_applied") and world.combat.get("emit_damage_events") != null:
		world.combat.set("emit_damage_events", true)
		Events.connect("damage_applied", _on_damage_applied)


## The weapon family name of weapon kind number `k`.
func _family(k: int) -> String:
	return FAMILIES[k] if k >= 0 and k < FAMILIES.size() else "other"


## The class of the victim `u`, as the audit names it.
func _class_of(u: Unit) -> String:
	if u is Ship:
		var hid := (u as Ship).hull_id
		var size := Ships.size_of(hid)
		if size == Rules.SIZE_SMALL:
			return "light"
		if size == Rules.SIZE_MEDIUM:
			return "corvette"
		if size == Rules.SIZE_LARGE:
			return "frigate"
		return hid
	if u.kind == Unit.K_MINION:
		return "minion"
	if u.kind == Unit.K_TURRET:
		return "turret"
	if u.kind == Unit.K_MOTHERSHIP:
		return "mothership"
	return Unit.KIND_NAMES[u.kind]


## What killed: "pilot", "minion", "rock" or the kind of the killing unit.
func _cause_of(info: DamageInfo) -> String:
	if info.kind == Rules.W_COLLISION:
		return "rock"
	if info.source_is_pilot:
		return "pilot"
	if info.source_is_minion:
		return "minion"
	if info.source != null and is_instance_valid(info.source):
		return Unit.KIND_NAMES[info.source.kind]
	return "other"


## A unit died: write it into the books.
func _on_unit_killed(u: Node, info: RefCounted) -> void:
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null:
		return
	var fam := _family(d.kind)
	var cls := _class_of(unit)
	if not kills.has(fam):
		kills[fam] = {}
	var by_class: Dictionary = kills[fam]
	by_class[cls] = int(by_class.get(cls, 0)) + 1
	var team := clampi(unit.team, 0, 1)
	if unit.kind == Unit.K_SHIP:
		var cause := _cause_of(d)
		deaths_by[cause] = int(deaths_by.get(cause, 0)) + 1
		var hid := (unit as Ship).hull_id
		if BIG_HULLS.has(hid):
			var killer_hull := ""
			if d.source is Ship:
				killer_hull = (d.source as Ship).hull_id
			big.append([int(world.time), unit.team, hid, cause, killer_hull, fam])
	elif unit.kind == Unit.K_TURRET:
		turrets_lost[team] += 1
	elif unit.kind == Unit.K_MOTHERSHIP:
		motherships_lost[team] += 1


## A hit: add it to its weapon family's damage book.
func _on_damage_applied(_target: Node, info: RefCounted, amount: float, hull_dmg: float) -> void:
	var d := info as DamageInfo
	if d == null:
		return
	var fam := _family(d.kind)
	if not damage.has(fam):
		damage[fam] = [0.0, 0.0]
	var e: Array = damage[fam]
	e[0] = float(e[0]) + amount
	e[1] = float(e[1]) + hull_dmg


## Every tick: stop when time is up or a mothership has died.
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	if world.time >= secs or world.phase != "play":
		_done = true
		var rounded := {}
		for fam: String in damage:
			var e: Array = damage[fam]
			rounded[fam] = [snappedf(float(e[0]), 1.0), snappedf(float(e[1]), 1.0)]
		print("KILL_AUDIT_JSON ", JSON.stringify({"probe": "kill_audit", "seed": int(Game.opt("seed", -1)),
			"minutes": snappedf(world.time / 60.0, 0.01), "ended": world.phase != "play", "winner": world.winner,
			"kills": kills, "deaths_by": deaths_by, "big": big, "turrets_lost": turrets_lost,
			"motherships_lost": motherships_lost, "damage": rounded}))
		get_tree().quit()
