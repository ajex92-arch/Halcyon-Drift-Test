extends Node
## WHAT THIS IS: the check of the match series (MatchSeries, the data for the end-of-match
## graph). It proves that the series takes its first sample on the first tick and then one every
## ten seconds of match time, that the team value counts what the rules say (hull, ship modules and
## gear at list prices, Mk II gear at what it cost in all, repair kits not at all, a dead pilot
## nothing), that the events record the pilot-ship deaths with their cause, the turret and the
## defense post that are destroyed and the mothership that falls, that the file reads back as JSON
## with the promised keys, and that writing it twice gives the same text.
##
## HOW IT WORKS: setup() finds the series in main.gd (this node is its child) and points its file
## at the recordings folder. Then _physics_process() runs a list of steps by tick count: it sets up a
## known team value and takes a sample by hand, kills pilot ships with different killing blows, waits
## for the sample clock, kills a turret and a defense post, and last the mothership, which ends the
## match: the match_over handler checks the final sample, the final file and prints
## "series_check: N failures".
##
## HOW TO RUN IT ("godot" is the Godot console program; <dir> is a folder for the file):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --seed=7 --recordings-dir=<dir> --test=series_check
##
## WHO USES IT: main.gd loads it for --test=series_check; run_checks lists it.

## The running match (set by setup()).
var world: World
## The series under test.
var series: MatchSeries
## How many checks failed.
var fails := 0
## Ticks taken since setup().
var _ticks := 0
## True once the verdict is printed.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_physics_priority = -100
	series = get_parent().get("series")
	_check("main.gd made a match series", series != null)
	if series == null:
		return
	series.save_path = MatchRecorder.folder().path_join("series_check.series.json")
	DirAccess.make_dir_recursive_absolute(MatchRecorder.folder())
	Events.match_over.connect(_on_match_over)


## Count a failure and print a PASS or FAIL line.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## A blow by `src` of kind `kind`, as the shots make them.
func _blow(src: Unit, kind: int) -> DamageInfo:
	return DamageInfo.from_unit(src, 100.0, kind, world.mothership(1).global_position)


## An enemy pilot's profile (team 1, a computer pilot).
func _enemy_pilot() -> PilotProfile:
	for p: PilotProfile in world.profiles:
		if p.team == 1 and not p.is_human and not Squads.is_crew(p):
			return p
	return null


## Put the human back in the hangar with a Fighter and launch (after a kill).
func _relaunch() -> Ship:
	var h := world.human
	h.state = "docked"
	h.respawn_t = 0.0
	h.hull_id = "fighter"
	return world.launch(h)


## Kill the human's ship with `info`; returns the newest event.
func _kill_human(info: DamageInfo) -> Dictionary:
	var ship := world.human.ship
	world.combat.kill(ship, info)
	return series.events[series.events.size() - 1] if not series.events.is_empty() else {}


## Godot calls this every tick, before the World's: the steps, by tick count.
func _physics_process(_dt: float) -> void:
	if world == null or series == null or _done:
		return
	_ticks += 1
	match _ticks:
		3:
			_check_first_sample()
			_check_value()
		10:
			_check_kills()
		1210:
			_check_clock()
			_check_file()
		1215:
			_check_structures()


## The first sample: taken on the first tick, at the start time, with all the keys.
func _check_first_sample() -> void:
	_check("the first sample is taken on the first tick (%d)" % series.samples.size(), series.samples.size() == 1)
	var s: Dictionary = series.samples[0]
	_check("a sample has t, val, ms, sh, cr, tr and fly", s.keys() == ["t", "val", "ms", "sh", "cr", "tr", "fly"], str(s.keys()))
	_check("the first sample is at the start time", float(s["t"]) == 0.0 and series.start_t == 0.0)
	_check("the motherships start whole", s["ms"] == [1.0, 1.0] and s["sh"] == [1.0, 1.0], str(s["ms"]) + str(s["sh"]))


## The team value rules.
func _check_value() -> void:
	var h := world.human
	var hull := h.hull_id
	var ship := h.ship
	var gear_id := "helmet"
	for id: String in Items.ITEMS.keys():
		gear_id = id
		break
	h.inventory = [{"id": gear_id, "count": 1}, {"id": Items.KIT["id"], "count": 2}, {}, {}, {}, {}]
	var mod_id := ""
	for m: String in Modules.MODULES.keys():
		if Modules.fit_blocker(m, hull) == "":
			mod_id = m
			break
	ship.modules.clear()
	if mod_id != "":
		ship.modules.append(mod_id)
	series._take()
	var s: Dictionary = series.samples[series.samples.size() - 1]
	var v: Array = (s["val"] as Array)[0]
	var want_ship := roundi(float(Ships.HULLS[hull]["price"]) + _others_ships(h))
	_check("a flying pilot's hull counts at its list price", int(v[0]) == want_ship, "%d wanted %d" % [int(v[0]), want_ship])
	var want_mod := roundi(Modules.price_for(mod_id, hull) if mod_id != "" else 0.0)
	_check("the modules on the flying ship count (%s)" % mod_id, int(v[1]) >= want_mod and want_mod >= 0, "%d" % int(v[1]))
	var want_gear := roundi(float(Items.ITEMS[gear_id]["price"]))
	_check("gear counts at its price and repair kits not at all", int(v[2]) >= want_gear, "%d wanted at least %d" % [int(v[2]), want_gear])
	h.inventory[0]["mk"] = 2
	series._take()
	var v2: Array = ((series.samples[series.samples.size() - 1] as Dictionary)["val"] as Array)[0]
	_check("a Mk II item counts at what it cost in all", int(v2[2]) - int(v[2]) == roundi(GearMk2Feature.total_paid(gear_id) - float(Items.ITEMS[gear_id]["price"])), "%d -> %d" % [int(v[2]), int(v2[2])])
	_check("a sample's fly counts the pilot ships in space", int(((series.samples[series.samples.size() - 1] as Dictionary)["fly"] as Array)[0]) >= 1)
	series.samples.pop_back()
	series.samples.pop_back()


## The hull prices of the other pilots of the human's team (they hold hulls too).
func _others_ships(h: PilotProfile) -> float:
	var total := 0.0
	for p: PilotProfile in world.profiles:
		if p.team == h.team and p != h and not Squads.is_crew(p) and p.state != "dead" and p.hull_id != "":
			total += float(Ships.HULLS[p.hull_id]["price"])
	return total


## Pilot-ship deaths: the cause and the fields.
func _check_kills() -> void:
	var foe := _enemy_pilot()
	var h := world.human
	var n0 := series.events.size()
	var ev := _kill_human(_enemy_blow(foe))
	_check("a pilot-ship death is an event with its fields", ev.get("k") == "ship" and ev.get("team") == h.team and ev.get("by") == 1 and ev.get("pilot") == true and ev.get("cause") == "pilot" and str(ev.get("victim")) == h.callsign and str(ev.get("killer")) == foe.callsign and int(ev.get("size")) >= 0 and ev.has("hull") and ev.has("lost") and ev.has("where"), str(ev))
	_check("an event starts with its time", ev.keys()[0] == "t")
	_relaunch()
	var minion := DamageInfo.new()
	minion.source_is_minion = true
	minion.source_team = 1
	ev = _kill_human(minion)
	_check("a minion's kill is cause minion with no killer pilot", ev.get("cause") == "minion" and ev.get("pilot") == false and ev.get("killer") == "" and ev.get("by") == 1, str(ev))
	_relaunch()
	var crash := DamageInfo.new()
	crash.kind = Rules.W_COLLISION
	ev = _kill_human(crash)
	_check("a crash has cause crash and no scoring team", ev.get("cause") == "crash" and ev.get("by") == -1, str(ev))
	_relaunch()
	var shot := DamageInfo.from_unit(world.turrets[0] if not world.turrets.is_empty() else null, 50.0, Rules.W_BOLT, Vector2.ZERO)
	ev = _kill_human(shot)
	_check("a turret's kill is cause turret", ev.get("cause") == "turret", str(ev))
	_check("four ship events were filed (%d)" % (series.events.size() - n0), series.events.size() - n0 == 4)
	var after := _relaunch()
	_check("the human flies again", after != null)


## A blow by the enemy pilot's ship (a pilot ship that is not flying is made to fire from where the
## enemy mothership is, through the profile).
func _enemy_blow(foe: PilotProfile) -> DamageInfo:
	var d := DamageInfo.new()
	d.source_is_pilot = true
	d.source_profile = foe
	d.source_team = foe.team
	return d


## The clock: a sample every ten seconds.
func _check_clock() -> void:
	var times: Array = []
	for s: Dictionary in series.samples:
		times.append(float(s["t"]))
	_check("a sample every ten seconds (%s)" % str(times), times.size() >= 3 and times[0] == 0.0 and times[1] == 10.0 and times[2] == 20.0, str(times))


## The file: valid JSON with the promised keys; the same text each time.
func _check_file() -> void:
	_check("the file is written", series.save(false))
	var text := FileAccess.get_file_as_string(series.save_path)
	var data = JSON.parse_string(text)
	_check("the file is JSON", typeof(data) == TYPE_DICTIONARY)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_check("the file has the promised keys", (data as Dictionary).keys() == ["tool", "version", "every", "start_t", "end_t", "final", "winner", "samples", "events"], str((data as Dictionary).keys()))
	_check("tool, version and every", data["tool"] == "match_series" and int(data["version"]) == 1 and float(data["every"]) == 10.0 and data["final"] == false)
	_check("the file holds every sample and event (%d, %d)" % [(data["samples"] as Array).size(), (data["events"] as Array).size()], (data["samples"] as Array).size() == series.samples.size() and (data["events"] as Array).size() == series.events.size())
	_check("writing it twice gives the same text", series.file_text(false) == text)
	_check("one sample or event to a line", text.count("\n") >= series.samples.size() + series.events.size())


## A turret and a defense post that are destroyed, then the mothership.
func _check_structures() -> void:
	var n0 := series.events.size()
	var turret: Turret = world.turrets[0]
	world.combat.kill(turret, _enemy_blow(_enemy_pilot()))
	var ev: Dictionary = series.events[series.events.size() - 1]
	_check("a turret destroyed is an event with a label and a place", ev.get("k") == "turret" and ev.get("team") == turret.team and ev.get("by") == Rules.enemy_of(turret.team) and str(ev.get("label")) != "" and ev.has("where"), str(ev))
	if not world.posts.is_empty():
		var post: DefensePost = world.posts[0]
		world.combat.kill(post, _enemy_blow(_enemy_pilot()))
		ev = series.events[series.events.size() - 1]
		_check("a defense post destroyed is an event with its lane", ev.get("k") == "post" and ev.get("lane") == post.lane and ev.get("by") == Rules.enemy_of(post.team), str(ev))
	_check("two structure events were filed (%d)" % (series.events.size() - n0), series.events.size() - n0 == (2 if not world.posts.is_empty() else 1))
	# The mothership falls: the match ends, and _on_match_over prints the verdict.
	var ms := world.mothership(1)
	world.combat.kill(ms, _enemy_blow(_enemy_pilot()))


## The match is over: the final sample, the final file, the verdict.
func _on_match_over(winner: int, _reason: String) -> void:
	if _done:
		return
	_done = true
	var ev: Dictionary = series.events[series.events.size() - 1] if not series.events.is_empty() else {}
	_check("the mothership's fall is an event", ev.get("k") == "mothership" and ev.get("team") == 1, str(ev))
	_check("the series is final with the winner", series.is_final and series.winner == winner)
	var last: Dictionary = series.samples[series.samples.size() - 1]
	_check("the last sample is at the end of the match", float(last["t"]) == snappedf(world.time, 0.1) or absf(float(last["t"]) - world.time) < 0.06, "%s vs %.2f" % [str(last["t"]), world.time])
	var data = JSON.parse_string(FileAccess.get_file_as_string(series.save_path))
	_check("the last file says final", typeof(data) == TYPE_DICTIONARY and data["final"] == true and int(data["winner"]) == winner)
	print("series_check: %d failures" % fails)
