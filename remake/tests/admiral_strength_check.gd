extends Node
## WHAT THIS IS: the check of the fitted fleet strength's function (scripts/ai/admiral_strength.gd, RT5):
## that it gives whole numbers, puts every hull in the right class, keeps the 0.4 hull floor, and with
## today's size weights gives exactly today's size count for undamaged ships.
##
## HOW IT WORKS: setup() runs the parts and prints "admiral_strength_check: N failures" (a FAIL line for
## each). The last part launches two small arena squads (tests/lib/arena_kit.gd) and compares
## AdmiralStrength.of_ships with the sum worked out by hand from the same ships.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=admiral_strength_check
##
## RT5 build 4b adds _switch: the profile switch fitted_strength (AdmiralLanes.strength, measure, versus), with scenarios built
## from arena squads: switch 0 keeps fleet_power's verdicts; switch 1 with the size count as the four weights keeps the same
## verdicts; switch 1 with the fitted weights flips a capital against four corvettes; the team view's records give the live
## answer; the siege and the mover call the one helper.
##
## WHO USES IT: main.gd loads it for --test=admiral_strength_check. RT5 build 4 runs it before and after
## it wires the strength in.

const ArenaKit := preload("res://tests/lib/arena_kit.gd")
## A set of weights that is not the size count (thousandths).
const W := [700, 2600, 2900, 3800]

var _fails := 0


func setup(w: World) -> void:
	_classes()
	_numbers()
	_world(w)
	_switch(w)
	print("admiral_strength_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL %s %s" % [what, detail])


## Every hull of Ships.HULLS is in the class of its size, and the four classes are RtsHulls' own.
func _classes() -> void:
	_check("classes: four", AdmiralStrength.CLASSES.size() == 4 and AdmiralStrength.SIZE_WEIGHTS.size() == 4)
	for hid: String in Ships.HULLS:
		var c := AdmiralStrength.class_index(hid)
		_check("classes: %s" % hid, c == Ships.size_of(hid) and AdmiralStrength.CLASSES[c] == RtsHulls.class_of(hid), str(c))


## The whole-number rules of one ship and of lists.
func _numbers() -> void:
	_check("numbers: undamaged counts its weight", AdmiralStrength.ship_strength("flak", 1000, W) == 2900)
	_check("numbers: half hull counts 0.7", AdmiralStrength.ship_strength("flak", 500, W) == 2030)
	_check("numbers: no hull counts the floor", AdmiralStrength.ship_strength("flak", 0, W) == 1160)
	_check("numbers: over 1000 is 1000", AdmiralStrength.ship_strength("scout", 5000, W) == 700)
	_check("numbers: under 0 is 0", AdmiralStrength.ship_strength("scout", -5, W) == 280)
	_check("numbers: a whole number", typeof(AdmiralStrength.ship_strength("ion", 333, W)) == TYPE_INT)
	_check("numbers: permille rounds", AdmiralStrength.permille(0.4996) == 500 and AdmiralStrength.permille(1.2) == 1000 and AdmiralStrength.permille(-1.0) == 0)
	var hulls := ["fighter", "support", "ion", "battlecruiser", "scout"]
	_check("numbers: of_hulls sums the weights", AdmiralStrength.of_hulls(hulls, W) == 700 + 2600 + 2900 + 3800 + 700)
	_check("numbers: size count of undamaged hulls", AdmiralStrength.of_hulls(hulls, AdmiralStrength.SIZE_WEIGHTS) == 1000 * (1 + 2 + 3 + 4 + 1))
	_check("numbers: of_entries", AdmiralStrength.of_entries([["flak", 500], ["scout", 1000]], W) == 2030 + 700)
	_check("numbers: empty is 0", AdmiralStrength.of_hulls([], W) == 0 and AdmiralStrength.of_entries([], W) == 0)


## Two arena squads: of_ships counts only the asked team's living ships and equals today's size count
## (times 1000) for undamaged ships.
func _world(w: World) -> void:
	w.minion_director.next_wave = INF
	var a := ArenaKit.squad(w, Rules.HALCYON, PackedStringArray(["fighter", "flak"]), false, 0.7, "sc-")
	var b := ArenaKit.squad(w, Rules.CINDER, PackedStringArray(["destroyer"]), false, 0.7, "sc-")
	_check("world: squads launched", a.size() == 2 and b.size() == 1)
	_check("world: team 0", AdmiralStrength.of_ships(w.ships, Rules.HALCYON, AdmiralStrength.SIZE_WEIGHTS) == 4000,
		str(AdmiralStrength.of_ships(w.ships, Rules.HALCYON, AdmiralStrength.SIZE_WEIGHTS)))
	_check("world: team 1", AdmiralStrength.of_ships(w.ships, Rules.CINDER, W) == 3800)
	var by_hand := 0.0
	for s: Ship in w.ships:
		if s.team == Rules.HALCYON and s.alive:
			by_hand += float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())
	_check("world: equals today's fleet power", AdmiralStrength.of_ships(w.ships, Rules.HALCYON, AdmiralStrength.SIZE_WEIGHTS) == roundi(by_hand * 1000.0), str(by_hand))

## The edges tried against every scenario (the siege's is 1.2, the mover's 1.0).
const EDGES := [0.8, 1.0, 1.2, 1.5, 2.5]
## The scenarios: [our hulls, their hulls, our first ship's hull fraction]. Squadron: fighter, scout; corvette: support;
## frigate: flak, ion; capital: battlecruiser, destroyer.
const SCENARIOS := [
	[["fighter", "flak"], ["destroyer"], 1.0],
	[["battlecruiser"], ["support", "support", "support", "support"], 1.0],
	[["support", "support", "support", "support"], ["battlecruiser"], 1.0],
	[["fighter", "fighter", "fighter", "support"], ["ion"], 1.0],
	[["battlecruiser", "battlecruiser"], ["battlecruiser", "ion"], 1.0],
	[["support", "support", "scout"], ["fighter", "fighter", "fighter", "fighter"], 0.5],
]


## The siege's test with an edge: true when we are too weak (the siege waits, the mover holds).
func _weaker(lanes: AdmiralLanes, edge: float) -> bool:
	return lanes.measure(0) < lanes.measure(1) * edge


## The same test on today's size count (AdmiralLanes.fleet_power), the way the code read it before the switch.
func _weaker_old(lanes: AdmiralLanes, edge: float) -> bool:
	return lanes.fleet_power(0) < lanes.fleet_power(1) * edge


## A profile with the fitted switch as given and the four weights as given (thousandths, CLASSES order).
func _profile(on: bool, weights: Array, view_on: bool = false) -> AdmiralProfile:
	var p := AdmiralProfile.make("standard", 0)
	p.set_value("fitted_strength", 1 if on else 0)
	p.set_value("team_view", 1 if view_on else 0)
	for i in 4:
		p.set_value(AdmiralLanes.WEIGHT_KEYS[i], int(weights[i]))
	return p


## Lanes for team 0 over world `w` whose team view has profile `p` (and sees everything while it is on).
func _lanes(w: World, p: AdmiralProfile) -> AdmiralLanes:
	var lanes := AdmiralLanes.new(w, 0)
	lanes.view = TeamView.new(w, 0, p)
	lanes.view.sees_all = true
	return lanes


## Launch a scenario's two squads (the earlier ones are put out first); returns the ships.
func _launch(w: World, sc: Array) -> void:
	for s: Ship in w.ships:
		s.alive = false
	var a := ArenaKit.squad(w, Rules.HALCYON, PackedStringArray(sc[0]), false, 0.7, "sw-")
	ArenaKit.squad(w, Rules.CINDER, PackedStringArray(sc[1]), false, 0.7, "sw-")
	if float(sc[2]) < 1.0:
		(a[0] as Ship).hull = (a[0] as Ship).hull_max * float(sc[2])


## The switch, the measure and the log text.
func _switch(w: World) -> void:
	var fitted_w: Array = []
	for key: String in AdmiralLanes.WEIGHT_KEYS:
		fitted_w.append(AdmiralProfileData.value("standard", key))
	_check("switch: the table's four weights are the night's fit", fitted_w == [345, 1037, 1360, 7258], str(fitted_w))
	var n := 0
	for sc: Array in SCENARIOS:
		n += 1
		_launch(w, sc)
		var off := _lanes(w, _profile(false, fitted_w))
		var sized := _lanes(w, _profile(true, AdmiralStrength.SIZE_WEIGHTS))
		# Switch 0: the measure is fleet_power itself, for both sides, and the profile's weights change nothing.
		_check("switch 0 #%d: the measure is fleet_power for both sides" % n, off.measure(0) == off.fleet_power(0) and off.measure(1) == off.fleet_power(1) and not off.fitted())
		_check("switch 0 #%d: the text is the size count's" % n, off.versus() == "our fleet %.1f against their %.1f" % [off.fleet_power(0), off.fleet_power(1)] and off.measure_tag() == "")
		# Switch 1 with the size count as the four weights: the strength is fleet_power times 1000 (a ship may round a thousandth).
		var ships: int = (sc[0] as Array).size() + (sc[1] as Array).size()
		for t in 2:
			_check("size weights #%d: team %d's strength is fleet_power x 1000" % [n, t], absi(sized.strength(t) - roundi(sized.fleet_power(t) * 1000.0)) <= ships, "%d against %f" % [sized.strength(t), sized.fleet_power(t)])
		_check("switch 1 #%d: the text names the fitted strength with whole numbers" % n, sized.fitted() and sized.measure_tag() == " (fitted)" and sized.versus() == "our fleet %d against their %d" % [sized.strength(0), sized.strength(1)])
		for edge: float in EDGES:
			var v0 := _weaker(off, edge)
			_check("switch 0 #%d edge %.1f: the verdict is fleet_power's" % [n, edge], v0 == _weaker_old(off, edge))
			_check("size weights #%d edge %.1f: the verdict is switch 0's" % [n, edge], _weaker(sized, edge) == v0, "%d against %d" % [sized.strength(0), sized.strength(1)])
		# Switch 1 with the fitted weights: both sides are measured the fitted way (never one side counted by size).
		var fit := _lanes(w, _profile(true, fitted_w))
		_check("fitted #%d: both sides are the fitted strength" % n, fit.measure(0) == float(AdmiralStrength.of_ships(w.ships, 0, fitted_w)) and fit.measure(1) == float(AdmiralStrength.of_ships(w.ships, 1, fitted_w)))
		# With the team view on (and seeing everything) the enemy's records give the live fitted strength.
		var viewed := _lanes(w, _profile(true, fitted_w, true))
		_check("fitted #%d: the team view's records give the live strength" % n, viewed.strength(1) == fit.strength(1) and viewed.strength(0) == fit.strength(0), "%d against %d" % [viewed.strength(1), fit.strength(1)])
	# The case: one capital against four corvettes. The size count says 4 against 8, the fit says 7258 against 4148.
	_launch(w, SCENARIOS[1])
	var o1 := _lanes(w, _profile(false, fitted_w))
	var f1 := _lanes(w, _profile(true, fitted_w))
	_check("flip: one capital against four corvettes, the size count says it is too weak at the siege's 1.2", _weaker(o1, 1.2))
	_check("flip: ... and the fit says it has the edge", not _weaker(f1, 1.2), "%d against %d" % [f1.strength(0), f1.strength(1)])
	_check("flip: the fitted numbers are 7258 against 4148", f1.strength(0) == 7258 and f1.strength(1) == 4148, "%d against %d" % [f1.strength(0), f1.strength(1)])
	_launch(w, SCENARIOS[2])
	var o2 := _lanes(w, _profile(false, fitted_w))
	var f2 := _lanes(w, _profile(true, fitted_w))
	_check("flip: four corvettes against one capital, the size count says it has the edge", not _weaker(o2, 1.2))
	_check("flip: ... and the fit says it is too weak", _weaker(f2, 1.2), "%d against %d" % [f2.strength(0), f2.strength(1)])
	# The siege and the mover both call the one helper and no longer read fleet_power themselves.
	for path in ["res://scripts/ai/admiral_siege.gd", "res://scripts/ai/admiral_mothership_mover.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_check("callers: %s compares with lanes.measure" % path, src.contains("lanes.measure(team) < lanes.measure(1 - team)"))
		_check("callers: %s calls no lanes.fleet_power" % path, not src.contains("lanes.fleet_power("))
