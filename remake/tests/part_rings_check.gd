extends Node
## WHAT THIS IS: the check of the part rings list (PartRings): what the HUD and the world view draw part rings
## from. The rule is the user's "own side, scanned enemies" with the scanned half waiting for scanning and jamming:
## the player's own side's ships show every part's ring; an enemy ship shows none. It prints one line per case
## ("PASS name" or "FAIL name: what") and then "part_rings_check: N checks, K failures" (and, only when K is 0,
## "part_rings_check: 0 failures").
##
## HOW IT WORKS: it builds the normal match, freezes it and launches real Battlecruisers (own side team 0, enemy
## team 1) with the parts switch on, sets part states through their health, steps ShipSystems.tick() by hand
## and reads the list. The picture itself is a thin reader of the list, so the proof is the list. It loads the new
## classes only through ResourceLoader and calls them with no static type, so on a build without them it
## prints FAIL lines and still ends.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=part_rings_check
##
## WHO USES IT: main.gd loads it for --test=part_rings_check; run_checks runs it. It only reads the game.

## Where the new class lives.
const RINGS_PATH := "res://scripts/ui/part_rings.gd"
## The keys of one ring entry (no number to print and no text).
const KEYS := ["id", "off", "cls", "state", "colour", "climb"]

## The ship's home spot (set by setup()).
var _home := Vector2.ZERO
## The running match (set by setup()).
var world: World
## How many checks were made.
var checks := 0
## How many went wrong.
var failures := 0
## The PartRings script, or null when this build has none.
var _pr = null


## main.gd calls this once, right after the World is built. Freeze the match and start the run
## on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Count one check, say what went wrong when `ok` is false, and print the PASS line of a good one.
func _expect(ok: bool, case_name: String, what: String = "") -> void:
	checks += 1
	if ok:
		print("part_rings_check: PASS %s" % case_name)
	else:
		failures += 1
		print("part_rings_check: FAIL %s: %s" % [case_name, what])


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	if ResourceLoader.exists(RINGS_PATH):
		_pr = load(RINGS_PATH)
	_expect(_pr != null, "PartRings is in this build", "part_rings.gd is missing")
	_case_no_parts()
	if _pr != null:
		_case_own()
		_case_enemy()
		_case_climb()
	print("part_rings_check: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("part_rings_check: 0 failures")
	get_tree().quit()


## Launch a pilot ship of hull `hid` for `team` with the parts switch set to `mode` at its making.
func _ship(hid: String, mode: String, team: int) -> Ship:
	var was = Game.options.get("parts", null)
	Game.options["parts"] = mode
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	if was == null:
		Game.options.erase("parts")
	else:
		Game.options["parts"] = was
	world.registry.rebuild_hashes()
	return s


## Put ship `s` away and make it dead.
func _retire(s: Ship) -> void:
	s.global_position = Vector2(-5000.0, -5000.0)
	s.alive = false


## The rings of ship `s` for a viewer of team `viewer`, from the new class (empty when this build has none).
func _rings(s: Ship, viewer: int) -> Array:
	if _pr == null:
		return []
	return _pr.rings(s, viewer)


## A ship with no parts gives an empty list (the control that holds on a build without the class too).
func _case_no_parts() -> void:
	var f := _ship("fighter", "off", 0)
	var bc := _ship("battlecruiser", "off", 0)
	_expect(_rings(f, 0).is_empty() and _rings(bc, 0).is_empty(), "a ship with no parts gives no rings", "rings %d / %d" % [_rings(f, 0).size(), _rings(bc, 0).size()])
	_retire(f)
	_retire(bc)


## The index of the first part of ship parts `p` whose class is `cls` (0 light, 1 main), or -1.
func _first_of_class(p, cls: int) -> int:
	for i in int(p.count()):
		if int((p.rows[i] as Dictionary)["cls"]) == cls:
			return i
	return -1


## An own ship's list holds every part with the right class colour; nothing in it is a number to print or text.
func _case_own() -> void:
	var bc := _ship("battlecruiser", "on", 0)
	var p = bc.get("parts")
	_expect(p != null, "the own Battlecruiser has parts", "no parts")
	if p == null:
		_retire(bc)
		return
	_expect(bool(_pr.visible_to(0, bc)), "an own ship is visible to its own team", "not visible")
	var list: Array = _rings(bc, 0)
	_expect(list.size() == int(p.count()), "the list holds every part (%d)" % list.size(), "%d rings for %d parts" % [list.size(), int(p.count())])
	var keys_ok := true
	for r: Dictionary in list:
		keys_ok = keys_ok and Array(r.keys()) == KEYS
	_expect(keys_ok, "an entry holds only id, offset, class, state, colour and climb (no number to print, no text)", "other keys")
	# The class colours: working green, degraded red, offline near black, all different, green brighter than red.
	var pi := int(p.index_of("pod_l"))
	var gi := _first_of_class(p, 1)
	var li := _first_of_class(p, 0)
	var gid := String((p.rows[gi] as Dictionary)["id"]) if gi >= 0 else ""
	var lid := String((p.rows[li] as Dictionary)["id"]) if li >= 0 else ""
	var si := int(p.index_of("sensor"))
	if gi < 0 or li < 0:
		_expect(false, "the own Battlecruiser has a main part and a light part", "main %d light %d" % [gi, li])
		_retire(bc)
		return
	p.hp[gi] = int((p.rows[gi] as Dictionary)["hp_max"]) / 4
	p.hp[pi] = 0
	p.offline[pi] = 1
	p.since[pi] = int(p.tick_n)
	list = _rings(bc, 0)
	var by_id := {}
	for r: Dictionary in list:
		by_id[String(r["id"])] = r
	var work := by_id["sensor"] as Dictionary
	var hurt := by_id[gid] as Dictionary
	var out := by_id["pod_l"] as Dictionary
	_expect(int(work["state"]) == 0 and int(hurt["state"]) == 1 and int(out["state"]) == 2, "each ring carries its part's state", "states %d %d %d" % [int(work["state"]), int(hurt["state"]), int(out["state"])])
	var cw := work["colour"] as Color
	var ch := hurt["colour"] as Color
	var co := out["colour"] as Color
	_expect(cw != ch and ch != co and cw != co, "working, degraded and offline have three colours", "%s %s %s" % [str(cw), str(ch), str(co)])
	_expect(cw.g > cw.r and ch.r > ch.g and cw.get_luminance() > ch.get_luminance() and ch.get_luminance() > co.get_luminance(), "green is working, red is degraded, black is offline, and the brightness differs", "lum %f %f %f" % [cw.get_luminance(), ch.get_luminance(), co.get_luminance()])
	_expect(si >= 0 and int(by_id[gid]["cls"]) == 1 and int(by_id[lid]["cls"]) == 0 and int(out["cls"]) == 2 and int(work["cls"]) == 3, "each ring carries its class", "classes wrong")
	_retire(bc)


## An enemy ship's list is empty and visible_to is false for it (and the viewer on the other team sees the reverse).
func _case_enemy() -> void:
	var bc := _ship("battlecruiser", "on", 1)
	_expect(not bool(_pr.visible_to(0, bc)), "an enemy ship is not visible to the viewer's team", "visible")
	_expect(_rings(bc, 0).is_empty(), "an enemy ship shows no rings", "%d rings" % _rings(bc, 0).size())
	_expect(bool(_pr.visible_to(1, bc)) and _rings(bc, 1).size() == int((bc.get("parts")).count()), "the same ship shows its rings to its own team", "not shown")
	_retire(bc)


## An offline part in its delay has climb 0, halfway through its climb 0.5 (within a tick), and the line at 1.
func _case_climb() -> void:
	var bc := _ship("battlecruiser", "on", 0)
	var p = bc.get("parts")
	var i := int(p.index_of("pod_l"))
	p.hp[i] = 0
	p.offline[i] = 1
	p.since[i] = int(p.tick_n)
	var climb := int((p.rows[i] as Dictionary)["climb"])
	var at_delay := 0.0
	for _k in 599:
		p.tick()
	var early := _ring_climb(bc, "pod_l")
	for _k in 1:
		p.tick()
	at_delay = _ring_climb(bc, "pod_l")
	_expect(early == 0.0 and at_delay == 0.0, "an offline part in its delay has climb 0", "climb %f then %f" % [early, at_delay])
	for _k in climb / 2:
		p.tick()
	var half := _ring_climb(bc, "pod_l")
	_expect(absf(half - 0.5) <= 1.0 / float(climb), "halfway through its climb the part's climb is 0.5", "climb %f" % half)
	for _k in climb / 2 + 2:
		p.tick()
	var done := _ring_climb(bc, "pod_l")
	_expect(done == 1.0 and int(p.offline[i]) == 0, "a part back online has climb 1", "climb %f offline %d" % [done, int(p.offline[i])])
	_retire(bc)


## The climb of ship `s`'s ring for part `id`.
func _ring_climb(s: Ship, id: String) -> float:
	for r: Dictionary in _rings(s, 0):
		if String(r["id"]) == id:
			return float(r["climb"])
	return -1.0
