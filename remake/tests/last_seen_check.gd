extends Node
## WHAT THIS IS: the check of the minimap's last-seen marks (S7A, #107 part one): the memory (LastSeen) of where each enemy ship
## was when our team last saw it, and the minimap's use of it. It proves that a ship the fog now hides keeps a mark at its last place
## that fades out in a straight line over LAST_SEEN_FADE_S, that a dead ship, a minion and a structure get none (a structure keeps
## the last-known picture the minimap already draws), that a ship never seen is not marked, that a ship seen again replaces its
## mark, that with No fog (fog_hides false) none is ever made, and that the minimap's own LastSeen holds one mark after an enemy
## ship is fogged.
##
## HOW IT WORKS: the pure cases build fake Unit nodes (never added to the match) and give LastSeen the viewing team, the "fog hides"
## decision and a match time of the case's own. The integration case waits for the HUD, takes a real enemy ship of the match, flips
## its visible_mask and asks the minimap (hud.minimap) to update, with a time of its own, then puts everything back. The new class
## is only ever reached through load() behind ResourceLoader.exists, so on a tree without it every case prints FAIL (or passes
## where it only needs "no mark") and the script still parses. Every case prints `last_seen_check: PASS <case>` or `FAIL <case>`;
## the last lines are `last_seen_check: <n> checks, <k> failures` and, when k is 0, `last_seen_check: 0 failures`.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=last_seen_check
##
## WHO USES IT: main.gd loads it for --test=last_seen_check. It changes Game.fog_off, one enemy ship's visible_mask and the minimap's
## memory in memory only, and puts them back.

## The class under test (S7A): reached only through load().
const LS_PATH := "res://scripts/ui/last_seen.gd"

## The running match (set by setup()).
var world: World
## How many checks ran and how many failed.
var checks := 0
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false
## Frames seen so far.
var _frames := 0
## The fake units made by a case, freed at the end of it.
var _fakes: Array = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: wait for the HUD (at most 90 frames), then run once; time out after 150 s of real time.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	_frames += 1
	if Time.get_ticks_msec() > 150000:
		print("last_seen_check: timeout")
		get_tree().quit()
		return
	var hud := get_tree().root.find_child("Hud", true, false)
	if (hud == null or world.human == null or world.human.ship == null) and _frames < 90:
		return
	_started = true
	_run(hud)


## The whole check, then the summary lines and quit.
func _run(hud: Node) -> void:
	_fade()
	_death()
	_minion_and_structure()
	_never_seen()
	_seen_again()
	_no_fog()
	_own_team()
	_gap()
	_integration(hud)
	for f: Node in _fakes:
		if is_instance_valid(f):
			f.free()
	_fakes.clear()
	print("last_seen_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("last_seen_check: 0 failures")
	get_tree().quit()


## Print a PASS or FAIL line for the case `what`.
func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("last_seen_check: %s %s%s" % ["PASS" if ok else "FAIL", what, ("" if detail == "" else ": " + detail)])


## A new LastSeen, or null when this tree has none (the base).
func _ls() -> Variant:
	if not ResourceLoader.exists(LS_PATH):
		return null
	var s: Script = load(LS_PATH)
	return s.new() if s != null else null


## A fake unit (never added to the match): of `kind` and `team`, at `pos`, visible to team 0 when `seen` is true.
func _unit(kind: int, team: int, pos: Vector2, seen: bool) -> Unit:
	var u := Unit.new()
	u.kind = kind
	u.team = team
	u.global_position = pos
	u.visible_mask = 1 if seen else 0
	_fakes.append(u)
	return u


## The marks of `ls` at `now` ([] when there is no LastSeen).
func _marks(ls: Variant, now: float) -> Array:
	return [] if ls == null else (ls.call("marks", now) as Array)


## Update `ls` (when there is one) for viewing team 0.
func _upd(ls: Variant, units: Array, fog: bool, now: float) -> void:
	if ls != null:
		ls.call("update", units, 0, fog, now)


## The fade length of `ls` (8 s when there is no LastSeen, so the arithmetic below still runs).
func _fade_s(ls: Variant) -> float:
	return 8.0 if ls == null else float(ls.get("LAST_SEEN_FADE_S"))


## Fade: the mark stays at the last seen place and falls in a straight line to nothing over LAST_SEEN_FADE_S.
func _fade() -> void:
	var ls: Variant = _ls()
	var f := _fade_s(ls)
	var u := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(100.0, 200.0), true)
	_upd(ls, [u], true, 0.0)
	_check("fade: a ship in sight has no mark", ls != null and _marks(ls, 0.0).is_empty() and int(ls.call("count")) == 1)
	u.visible_mask = 0
	u.global_position = Vector2(900.0, 900.0)
	_upd(ls, [u], true, 2.0)
	var m := _marks(ls, 2.0)
	_check("fade: a ship the fog hides keeps a mark at the place it was last seen", m.size() == 1 and (m[0]["pos"] as Vector2) == Vector2(100.0, 200.0), str(m))
	_check("fade: the mark's strength is 1 minus the seconds since seen over the fade", m.size() == 1 and absf(float(m[0]["alpha"]) - (1.0 - 2.0 / f)) < 0.001, str(m))
	var half := _marks(ls, f * 0.5)
	_check("fade: half the fade length after, the mark is at half strength", half.size() == 1 and absf(float(half[0]["alpha"]) - 0.5) < 0.001, str(half))
	_upd(ls, [u], true, f + 0.5)
	_check("fade: when the fade has run out the mark is gone", ls != null and _marks(ls, f + 0.5).is_empty() and int(ls.call("count")) == 0)


## Death: a ship that dies, in sight or out of it, loses its mark.
func _death() -> void:
	var ls: Variant = _ls()
	var u := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(50.0, 50.0), true)
	_upd(ls, [u], true, 0.0)
	u.visible_mask = 0
	_upd(ls, [u], true, 1.0)
	var before := _marks(ls, 1.0).size()
	u.alive = false
	_upd(ls, [u], true, 2.0)
	_check("death: a ship that dies out of sight loses its mark", ls != null and before == 1 and _marks(ls, 2.0).is_empty() and int(ls.call("count")) == 0)
	var v := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(60.0, 60.0), true)
	var ls2: Variant = _ls()
	_upd(ls2, [v], true, 0.0)
	v.alive = false
	_upd(ls2, [v], true, 1.0)
	_check("death: a ship that dies in sight is forgotten", ls2 != null and int(ls2.call("count")) == 0)
	var w := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(70.0, 70.0), true)
	var ls3: Variant = _ls()
	_upd(ls3, [w], true, 0.0)
	w.visible_mask = 0
	_upd(ls3, [], true, 1.0)
	_check("death: a ship that left the game is forgotten", ls3 != null and _marks(ls3, 1.0).is_empty() and int(ls3.call("count")) == 0)


## A minion gets no mark, and a structure keeps only the ghost the minimap already draws (no second mark).
func _minion_and_structure() -> void:
	var ls: Variant = _ls()
	var minion := _unit(Unit.K_MINION, Rules.CINDER, Vector2(10.0, 10.0), true)
	_upd(ls, [minion], true, 0.0)
	minion.visible_mask = 0
	_upd(ls, [minion], true, 1.0)
	_check("a minion gets no mark", _marks(ls, 1.0).is_empty())
	var ls2: Variant = _ls()
	var turret := _unit(Unit.K_TURRET, Rules.CINDER, Vector2(20.0, 20.0), true)
	turret.seen_mask = 1
	_upd(ls2, [turret], true, 0.0)
	turret.visible_mask = 0
	_upd(ls2, [turret], true, 1.0)
	_check("a structure keeps its existing ghost", _marks(ls2, 1.0).is_empty())


## A ship that was never in sight is not marked.
func _never_seen() -> void:
	var ls: Variant = _ls()
	var u := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(30.0, 30.0), false)
	_upd(ls, [u], true, 0.0)
	_upd(ls, [u], true, 1.0)
	_check("a ship never seen is not marked", _marks(ls, 1.0).is_empty())


## A ship seen again replaces its mark: one entry, at the new place, at full strength again after the next hiding.
func _seen_again() -> void:
	var ls: Variant = _ls()
	var u := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(100.0, 100.0), true)
	_upd(ls, [u], true, 0.0)
	u.visible_mask = 0
	_upd(ls, [u], true, 3.0)
	var first := _marks(ls, 3.0)
	u.visible_mask = 1
	u.global_position = Vector2(500.0, 600.0)
	_upd(ls, [u], true, 4.0)
	var live := _marks(ls, 4.0)
	u.visible_mask = 0
	u.global_position = Vector2(900.0, 900.0)
	_upd(ls, [u], true, 4.2)
	var again := _marks(ls, 4.2)
	_check("seen again: the first mark is at the first place", first.size() == 1 and (first[0]["pos"] as Vector2) == Vector2(100.0, 100.0))
	_check("seen again: while it is in sight again it has no mark, and one entry", ls != null and live.is_empty() and int(ls.call("count")) == 1)
	_check("seen again: the new mark replaces the old one (one mark, the new place, nearly full strength)", again.size() == 1 and (again[0]["pos"] as Vector2) == Vector2(500.0, 600.0) and float(again[0]["alpha"]) > 0.95, str(again))


## With No fog (fog_hides false) no mark is ever made, and a mark made before is forgotten.
func _no_fog() -> void:
	var ls: Variant = _ls()
	var u := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(10.0, 10.0), true)
	_upd(ls, [u], true, 0.0)
	u.visible_mask = 0
	_upd(ls, [u], false, 1.0)
	_check("No fog gives none (and forgets the old one)", ls != null and _marks(ls, 1.0).is_empty() and int(ls.call("count")) == 0)
	var ls2: Variant = _ls()
	var v := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(10.0, 10.0), true)
	_upd(ls2, [v], false, 0.0)
	v.visible_mask = 0
	_upd(ls2, [v], false, 1.0)
	_check("No fog from the start gives none", ls2 != null and _marks(ls2, 1.0).is_empty() and int(ls2.call("count")) == 0)


## A ship of the viewing team itself is never marked.
func _own_team() -> void:
	var ls: Variant = _ls()
	var u := _unit(Unit.K_SHIP, Rules.HALCYON, Vector2(10.0, 10.0), true)
	_upd(ls, [u], true, 0.0)
	u.visible_mask = 0
	_upd(ls, [u], true, 1.0)
	_check("a ship of our own team is never marked", ls != null and _marks(ls, 1.0).is_empty() and int(ls.call("count")) == 0)


## At most 10 updates a second: a second call less than 0.09 s after the first is ignored.
func _gap() -> void:
	var ls: Variant = _ls()
	var u := _unit(Unit.K_SHIP, Rules.CINDER, Vector2(10.0, 10.0), true)
	_upd(ls, [u], true, 0.0)
	u.visible_mask = 0
	_upd(ls, [u], true, 0.05)
	var early := _marks(ls, 0.05).size()
	_upd(ls, [u], true, 0.12)
	_check("updates are at most 10 a second", ls != null and early == 0 and _marks(ls, 0.12).size() == 1)


## The minimap's own LastSeen: after a real enemy ship is fogged it holds one mark; with No fog on it holds none.
func _integration(hud: Node) -> void:
	var mm: Variant = hud.get("minimap") if hud != null else null
	var vt := world.viewer_team
	var foe: Unit = null
	for u: Variant in world.units:
		if u != null and is_instance_valid(u) and (u as Unit).alive and (u as Unit).kind == Unit.K_SHIP and (u as Unit).team != vt:
			foe = u as Unit
			break
	var ready: bool = mm != null and mm.has_method("update_last_seen") and "last_seen" in mm and foe != null and vt >= 0 and ResourceLoader.exists(LS_PATH)
	_check("integration: the minimap, a viewing team and an enemy ship exist and the minimap has its LastSeen", ready, "minimap %s, viewer %d, enemy ship %s" % [str(mm != null), vt, str(foe != null)])
	if not ready:
		_check("integration: after an enemy ship is fogged the minimap's LastSeen holds one mark", false, "not ready")
		_check("integration: with No fog on the minimap's LastSeen holds none", false, "not ready")
		return
	var was_fog := Game.fog_off
	var was_mask := foe.visible_mask
	var was_ls: Variant = mm.get("last_seen")
	var s: Script = load(LS_PATH)
	mm.set("last_seen", s.new())
	var bit := 1 << vt
	Game.fog_off = false
	foe.visible_mask = was_mask | bit
	mm.call("update_last_seen", vt, 100.0)
	foe.visible_mask = was_mask & ~bit
	mm.call("update_last_seen", vt, 101.0)
	var held: Array = (mm.get("last_seen") as RefCounted).call("marks", 101.0)
	_check("integration: after an enemy ship is fogged the minimap's LastSeen holds one mark", held.size() == 1 and int(held[0]["id"]) == foe.get_instance_id(), str(held.size()))
	Game.fog_off = true
	mm.call("update_last_seen", vt, 102.0)
	var none: Array = (mm.get("last_seen") as RefCounted).call("marks", 102.0)
	_check("integration: with No fog on the minimap's LastSeen holds none", none.is_empty() and int((mm.get("last_seen") as RefCounted).call("count")) == 0, str(none.size()))
	Game.fog_off = was_fog
	foe.visible_mask = was_mask
	mm.set("last_seen", was_ls)
