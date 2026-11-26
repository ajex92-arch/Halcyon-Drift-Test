extends Node
## WHAT THIS IS: the fit of the computer Admiral's fleet strength (RT5, scripts/ai/admiral_strength.gd).
## It fights duels between mixed fleets in the arena, fits one weight per hull class (squadron,
## corvette, frigate, capital) on one part of the duels, and says how often the fitted strength names
## the winner on the other part (the held-out part), at pilot skill and at minion skill. The gate is
## 75% of the held-out winners. It also prints the three-band table (T-134): how often the stronger
## side wins when the two strengths are close, a step apart, or far apart.
##
## HOW IT WORKS:
##   1. The plan: --pairs fleet pairs. Each fleet is drawn with this test's own random numbers (seeded
##      by --seed, never the match's): a credit budget, then hulls picked class by class until the
##      budget or --max-ships is used up. The second fleet's budget is the first's times a ratio from
##      RATIOS, so even and uneven duels both come up. Every pair is fought twice: once at pilot skill
##      (each pilot keeps the skill of its seat, as a human team's AI pilots) and once at minion skill
##      (every pilot at RtsHulls.STANDIN_SKILL, the brain of a bought ship). The first fleet flies for
##      Aurelian on even pairs and for Cinder on odd ones, and the map sides swap every second pair.
##   2. The fights: arena fights, one after another in one match, exactly as tests/arena_matrix.gd
##      (tests/lib/arena_kit.gd). A fight ends when a side is gone, or at --limit seconds: then the
##      side that kept TIME_MARGIN permille more of its own fleet (price times hull left) wins "on
##      time" ("by":"time" in the line), and anything closer is a draw.
##      Every fight prints one line, "SFIT_DUEL {...}".
##   3. The fit: a duel is the four differences "ships of the class in fleet A minus in fleet B" and
##      who won. A logistic fit (plain gradient steps, no random numbers) finds the four weights on the
##      training pairs; they are scaled to a sum of 10,000 thousandths (today's size count 1+2+3+4 is
##      the same sum) and rounded to whole numbers. Draws are left out. Every --holdout'th pair is held
##      out, with both of its fights.
##   4. The check: AdmiralStrength.of_hulls with the rounded weights names the stronger fleet of each
##      held-out duel; the share it gets right is printed for each skill, beside the same share for
##      today's size count. An equal strength counts as wrong.
##   5. The bands: over every decided duel, the stronger fleet's strength over the weaker one's, in
##      three bands (under BAND_EDGE, under BAND_CLEAR, above), with how often the stronger side won.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=1 --test=strength_fit --pairs=60
## Its own options:
##   --pairs=N       fleet pairs to fight, each at both skills (default 60; 0 = fight nothing)
##   --limit=S       the time limit of one fight, in seconds (default 180)
##   --max-ships=N   the most ships in one fleet (default 8)
##   --holdout=K     every K'th pair is held out (default 3)
##   --duel-in=F;F   also read the SFIT_DUEL lines of these log files (so a night's runs with different
##                   seeds are fitted together: --pairs=0 --duel-in=a.txt;b.txt). Pairs are told apart
##                   by seed and number.
##   --fit-out=FILE  save the result as JSON in FILE and the three-band table in FILE + ".bands.txt"
##
## HOW TO READ THE OUTPUT:
##   "SFIT_DUEL {...}"  one fight: seed, pair, skill, both fleets, the winner ("a" Aurelian, "b" Cinder
##       or "draw") and its length.
##   "strength_fit: weights squadron=... corvette=... frigate=... capital=..."  the fitted weights in
##       thousandths.
##   "strength_fit: held out pilot 81.3% (13/16) ..."  the share of held-out winners named right.
##   "STRENGTH BANDS" and its rows: the three-band table.
##   "FIT_JSON {...}"  all of it in one line.
##   "RESULT strength_fit: PASS" when both skills reach GATE_PERCENT held out, else FAIL.
##
## WHO USES IT: main.gd loads it for --test=strength_fit. RT5 build 4 puts the weights in the profile
## table; the fit is run again after each change to ships or pilots (the design's re-run list).

## The arena toolkit: squads, keeping pilots in the fight, who is alive.
const ArenaKit := preload("res://tests/lib/arena_kit.gd")
## The hulls a fleet is drawn from, by class (the order of AdmiralStrength.CLASSES).
const CLASS_HULLS := [["scout", "fighter", "lance", "bomber"], ["logistics", "support"], ["flak", "ion"], ["destroyer", "battlecruiser"]]
## The second fleet's budget as a permille of the first's; pair i uses entry i modulo the size.
const RATIOS := [1000, 700, 1300, 1000, 500, 1600, 850, 1150]
## The smallest and largest budget of the first fleet (credits).
const BUDGET_MIN := 450
const BUDGET_MAX := 7000
## The pause between fights (seconds), so shots still in flight run out.
const GAP := 8.0
## The gate: this percent of the held-out winners must be named right, at each skill.
const GATE_PERCENT := 75.0
## At the time limit a side wins "on time" when it has kept this many permille more of its own fleet
## (price times hull left) than the other side; closer than that is a draw.
const TIME_MARGIN := 100
## The band edges, as the stronger strength over the weaker one in permille: under BAND_EDGE the
## fleets are "even", under BAND_CLEAR one has "an edge", above it is "clear".
const BAND_EDGE := 1200
const BAND_CLEAR := 1500
const BAND_NAMES := ["even (under 1.2)", "edge (1.2 to 1.5)", "clear (1.5 or more)"]
## The two skills, in the order of every per-skill list.
const SKILLS := ["pilot", "minion"]
## The fit: steps, step size and the pull towards small weights.
const FIT_STEPS := 4000
const FIT_RATE := 0.05
const FIT_PULL := 0.001

## The running match (set by setup()).
var world: World
## Every fight to run: {"seed", "pair", "sk", "a", "b", "swap"}.
var plan: Array = []
## Every duel known: the fights of this run and the lines of --duel-in: the plan's keys plus "win"
## and "secs".
var duels: Array = []
## The number of the fight running now (-1 while pausing), and of the next one.
var cur := -1
var next := 0
## Both squads' ships in the fight running now.
var a: Array = []
var b: Array = []
## Seconds since the fight running now began; seconds left of the pause.
var fight_t := 0.0
var pause_t := 1.0
## The time limit of one fight (seconds; --limit).
var limit := 180.0
## Every how many pairs one is held out (--holdout).
var holdout := 3
## True once the result has been printed.
var _done := false


## main.gd calls this once, right after the World is built: stop the minion waves, read the old duel
## lines and write the fight plan.
@warning_ignore("integer_division")
func setup(w: World) -> void:
	world = w
	SquadronRules.use_squad_brain = false  # this check pins the stand-in's own internals
	world.minion_director.next_wave = INF
	limit = float(Game.opt("limit", 180.0))
	holdout = maxi(2, int(Game.opt("holdout", 3)))
	var seed_n := int(Game.opt("seed", 1))
	var max_ships := maxi(1, int(Game.opt("max-ships", 8)))
	for path: String in str(Game.opt("duel-in", "")).split(";", false):
		_read_duels(path)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n * 7919 + 17
	for i in int(Game.opt("pairs", 60)):
		var budget := rng.randi_range(BUDGET_MIN, BUDGET_MAX)
		var other := maxi(BUDGET_MIN, budget * int(RATIOS[i % RATIOS.size()]) / 1000)
		var first := _draw_fleet(rng, budget, max_ships)
		var second := _draw_fleet(rng, other, max_ships)
		var first_on_a := i % 2 == 0
		for sk: String in SKILLS:
			plan.append({"seed": seed_n, "pair": i, "sk": sk, "a": first if first_on_a else second,
				"b": second if first_on_a else first, "swap": i % 4 >= 2})
	print("strength_fit: %d fights to run, %d duels read, limit %ds" % [plan.size(), duels.size(), int(limit)])


## A fleet for `budget` credits: pick a class that still has an affordable hull, then one of its
## affordable hulls, until nothing fits or the fleet has `max_ships` ships. Never empty.
func _draw_fleet(rng: RandomNumberGenerator, budget: int, max_ships: int) -> Array:
	var fleet: Array = []
	var left := budget
	while fleet.size() < max_ships:
		var classes: Array = []
		for c in CLASS_HULLS.size():
			var can: Array = []
			for hid: String in CLASS_HULLS[c]:
				if RtsHulls.unit_price(hid) <= left:
					can.append(hid)
			if not can.is_empty():
				classes.append(can)
		if classes.is_empty():
			break
		var pick: Array = classes[rng.randi_range(0, classes.size() - 1)]
		var hull: String = pick[rng.randi_range(0, pick.size() - 1)]
		fleet.append(hull)
		left -= RtsHulls.unit_price(hull)
	if fleet.is_empty():
		fleet.append("fighter")
	return fleet


## Read the SFIT_DUEL lines of log file `path` into `duels`.
func _read_duels(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("strength_fit: cannot read %s" % path)
		return
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("SFIT_DUEL "):
			var d: Variant = JSON.parse_string(line.substr(10))
			if d is Dictionary:
				duels.append(d)


## Godot calls this every tick; `dt` is the tick's length in seconds. Run the fight that is on, or count
## down the pause and start the next one; after the last fight do the fit and quit.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	if cur >= 0:
		fight_t += dt
		ArenaKit.keep_in_fight(world)
		var na := ArenaKit.alive_count(a)
		var nb := ArenaKit.alive_count(b)
		if na == 0 or nb == 0 or fight_t > limit:
			_end_fight(na, nb)
		return
	if next < plan.size():
		pause_t -= dt
		if pause_t > 0.0:
			return
		_start_fight(next)
		next += 1
	else:
		_done = true
		_finish()
		get_tree().quit()


## Start fight number `i` of the plan: both squads at the fight's skill (below 0 = each seat's own).
func _start_fight(i: int) -> void:
	var f: Dictionary = plan[i]
	var skill := -1.0 if f["sk"] == "pilot" else RtsHulls.STANDIN_SKILL
	var tag := "s%d-" % i
	a = ArenaKit.squad(world, Rules.HALCYON, PackedStringArray(f["a"]), f["swap"], skill, tag)
	b = ArenaKit.squad(world, Rules.CINDER, PackedStringArray(f["b"]), f["swap"], skill, tag)
	fight_t = 0.0
	cur = i


## The fight running now is over, with `na` Aurelian and `nb` Cinder ships alive: note and print the
## result, clear the arena (as arena_matrix does) and start the pause.
func _end_fight(na: int, nb: int) -> void:
	var d: Dictionary = plan[cur].duplicate()
	d["win"] = "draw"
	d["by"] = "kill"
	if na > 0 and nb == 0:
		d["win"] = "a"
	elif nb > 0 and na == 0:
		d["win"] = "b"
	elif na > 0 and nb > 0:
		# The time limit: the side that kept clearly more of its own fleet wins "on time".
		d["by"] = "time"
		var ka := _kept(a, d["a"])
		var kb := _kept(b, d["b"])
		d["kept"] = [ka, kb]
		if ka >= kb + TIME_MARGIN:
			d["win"] = "a"
		elif kb >= ka + TIME_MARGIN:
			d["win"] = "b"
	d["secs"] = int(fight_t)
	duels.append(d)
	print("SFIT_DUEL " + JSON.stringify(d))
	for s in a + b:
		if is_instance_valid(s) and s.alive:
			world.combat.kill_silently(s)
	for p: PilotProfile in world.pilot_ai.keys():
		world.profiles.erase(p)
		world.pilot_ai.erase(p)
	a = []
	b = []
	cur = -1
	pause_t = GAP


## How much of its fleet a side has kept, in permille: the price of each living ship times its hull
## left, over the price of the whole starting fleet `hulls`.
func _kept(ships: Array, hulls: Array) -> int:
	var start := 0.0
	for hid in hulls:
		start += float(RtsHulls.unit_price(str(hid)))
	var left := 0.0
	for s in ships:
		if is_instance_valid(s) and s.alive:
			left += float(RtsHulls.unit_price(s.hull_id)) * s.hull_frac()
	return roundi(1000.0 * left / maxf(1.0, start))


## Is duel `d` of a held-out pair?
func _held_out(d: Dictionary) -> bool:
	return int(d["pair"]) % holdout == holdout - 1


## The four class counts of fleet `hulls`.
func _counts(hulls: Array) -> Array:
	var n := [0, 0, 0, 0]
	for hid in hulls:
		n[AdmiralStrength.class_index(str(hid))] += 1
	return n


## The four weights (whole thousandths, sum 10,000) fitted on the decided training duels; the size
## count when there is nothing to fit on.
func _fit() -> Array:
	var xs: Array = []
	var ys: Array = []
	for d: Dictionary in duels:
		if d["win"] == "draw" or _held_out(d):
			continue
		var ca := _counts(d["a"])
		var cb := _counts(d["b"])
		xs.append([float(ca[0] - cb[0]), float(ca[1] - cb[1]), float(ca[2] - cb[2]), float(ca[3] - cb[3])])
		ys.append(1.0 if d["win"] == "a" else 0.0)
	if xs.is_empty():
		return AdmiralStrength.SIZE_WEIGHTS.duplicate()
	var w := [1.0, 2.0, 3.0, 4.0]
	for step in FIT_STEPS:
		var grad := [0.0, 0.0, 0.0, 0.0]
		for k in xs.size():
			var x: Array = xs[k]
			var z := 0.0
			for c in 4:
				z += float(w[c]) * float(x[c])
			var err := float(ys[k]) - 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))
			for c in 4:
				grad[c] += err * float(x[c])
		for c in 4:
			w[c] = maxf(0.01, float(w[c]) + FIT_RATE * (float(grad[c]) / float(xs.size()) - FIT_PULL * float(w[c])))
	var total := 0.0
	for c in 4:
		total += float(w[c])
	var out: Array = []
	for c in 4:
		out.append(maxi(1, roundi(float(w[c]) * 10000.0 / total)))
	return out


## Over the decided duels that pass `keep`: how many, and how many winners `weights` names right.
func _score(weights: Array, keep: Callable) -> Array:
	var n := 0
	var right := 0
	for d: Dictionary in duels:
		if d["win"] == "draw" or not keep.call(d):
			continue
		n += 1
		var sa := AdmiralStrength.of_hulls(d["a"], weights)
		var sb := AdmiralStrength.of_hulls(d["b"], weights)
		if (sa > sb and d["win"] == "a") or (sb > sa and d["win"] == "b"):
			right += 1
	return [n, right]


## [n, right] as text like "81.3% (13/16)".
func _pct_text(s: Array) -> String:
	if int(s[0]) == 0:
		return "no duels"
	return "%.1f%% (%d/%d)" % [100.0 * float(s[1]) / float(s[0]), int(s[1]), int(s[0])]


## [n, right] as a percent, -1 with no duels.
func _pct(s: Array) -> float:
	return -1.0 if int(s[0]) == 0 else snappedf(100.0 * float(s[1]) / float(s[0]), 0.1)


## The three-band table for `weights`: one row per skill ("pilot", "minion", "both") and band, as
## {"skill", "band", "duels", "stronger_won", "percent"}. Equal strengths go in the first band and
## count as not won.
@warning_ignore("integer_division")
func _bands(weights: Array) -> Array:
	var rows: Array = []
	for sk: String in SKILLS + ["both"]:
		var n := [0, 0, 0]
		var won := [0, 0, 0]
		for d: Dictionary in duels:
			if d["win"] == "draw" or (sk != "both" and d["sk"] != sk):
				continue
			var sa := AdmiralStrength.of_hulls(d["a"], weights)
			var sb := AdmiralStrength.of_hulls(d["b"], weights)
			var ratio := maxi(sa, sb) * 1000 / maxi(1, mini(sa, sb))
			var band := 0 if ratio < BAND_EDGE else (1 if ratio < BAND_CLEAR else 2)
			n[band] += 1
			if (sa > sb and d["win"] == "a") or (sb > sa and d["win"] == "b"):
				won[band] += 1
		for k in 3:
			rows.append({"skill": sk, "band": BAND_NAMES[k], "duels": n[k], "stronger_won": won[k],
				"percent": _pct([n[k], won[k]])})
	return rows


## The fit, the held-out check, the three-band table, the files and the result line.
func _finish() -> void:
	var draws := 0
	var train := 0
	var held := 0
	var timed := 0
	for d: Dictionary in duels:
		if d["win"] != "draw" and str(d.get("by", "kill")) == "time":
			timed += 1
		if d["win"] == "draw":
			draws += 1
		elif _held_out(d):
			held += 1
		else:
			train += 1
	var weights := _fit()
	print("strength_fit: %d duels, %d draws left out, %d won on time; %d to fit on, %d held out (every %d. pair)" % [duels.size(), draws, timed, train, held, holdout])
	print("strength_fit: weights squadron=%d corvette=%d frigate=%d capital=%d (thousandths, sum 10000)" % weights)
	var held_json := {}
	var size_json := {}
	var passed := held > 0
	for sk: String in SKILLS:
		var keep := func(d: Dictionary) -> bool: return _held_out(d) and d["sk"] == sk
		var fit_s := _score(weights, keep)
		var size_s := _score(AdmiralStrength.SIZE_WEIGHTS, keep)
		print("strength_fit: held out %s %s; today's size count %s" % [sk, _pct_text(fit_s), _pct_text(size_s)])
		held_json[sk] = {"duels": fit_s[0], "right": fit_s[1], "percent": _pct(fit_s)}
		size_json[sk] = {"duels": size_s[0], "right": size_s[1], "percent": _pct(size_s)}
		if _pct(fit_s) < GATE_PERCENT:
			passed = false
	var train_s := _score(weights, func(d: Dictionary) -> bool: return not _held_out(d))
	print("strength_fit: on the duels it was fitted on %s" % _pct_text(train_s))
	var rows := _bands(weights)
	var table := "STRENGTH BANDS (every decided duel; stronger over weaker strength; share the stronger side won)\n"
	table += "%-8s %-22s %6s %6s %8s\n" % ["skill", "band", "duels", "won", "percent"]
	for r: Dictionary in rows:
		table += "%-8s %-22s %6d %6d %8s\n" % [r["skill"], r["band"], int(r["duels"]), int(r["stronger_won"]),
			"-" if float(r["percent"]) < 0.0 else "%.1f%%" % float(r["percent"])]
	print(table)
	var out := {"probe": "strength_fit", "version": 1, "seed": int(Game.opt("seed", -1)), "duels": duels.size(), "draws": draws, "won_on_time": timed,
		"train": train, "held": held, "holdout": holdout, "classes": AdmiralStrength.CLASSES, "weights": weights,
		"held_out": held_json, "held_out_size_count": size_json, "train_percent": _pct(train_s),
		"gate_percent": GATE_PERCENT, "pass": passed, "bands": rows}
	print("FIT_JSON " + JSON.stringify(out))
	var path := str(Game.opt("fit-out", ""))
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		var g := FileAccess.open(path + ".bands.txt", FileAccess.WRITE)
		if f == null or g == null:
			print("strength_fit: cannot write %s" % path)
			passed = false
		else:
			f.store_string(JSON.stringify(out, "  ") + "\n")
			g.store_string(table)
			f.close()
			g.close()
	print("strength_fit: GATE %d%% of the held-out winners at each skill: %s" % [int(GATE_PERCENT), "PASS" if passed else "FAIL"])
	print("RESULT strength_fit: %s" % ("PASS" if passed else "FAIL"))
