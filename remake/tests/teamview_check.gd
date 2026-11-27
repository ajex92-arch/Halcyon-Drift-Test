extends Node
## WHAT THIS IS: the check of the team view (scripts/ai/team_view.gd), the record of what one team knows of the enemy
## that the computer Admiral reads in place of the live world. It proves five things:
##   1. THE FILE SCAN: no file scripts/ai/admiral*.gd, and no scripts/features/admiral*.gd, reads a world unit list, a
##      mothership, the defense posts or a unit's sight masks directly; they go through TeamView. The feature modules
##      that are switched off by default and still read the world (EXEMPT, a written list) are named, counted and
##      allowed; an exempt file that no longer reads the world is reported so the list stays honest.
##   2. SWITCH OFF: with team_view off every helper gives exactly what the old live read gave.
##   3. THE HIDE CASE: every enemy ship is seen, then hidden. At 0 s, 45 s and 90 s after the last sighting, WHERE the
##      ships are (enemy_near) has weight 1000, 500 and 0 thousandths, while THAT they exist (enemy_strength) is full
##      until the stale cap (memory_stale_s, 300 s) and gone just after. A ship seen dying is dropped at once; one that
##      dies unseen stays counted. The enemy mothership keeps its last-seen place and hull with no fade, until it is
##      seen again.
##   4. A SPOT SEEN EMPTY: a lane turret that is gone is dropped from the record only when the team sees its place.
##   5. THE TEST SWITCH: with the team seeing everything (TeamView.sees_all) the view's answers are the live answers.
##
## HOW IT WORKS: setup() runs the file scan and the switch-off checks at tick 0. The match then runs on to frame
## SCENARIO_FRAME (20 game seconds, when both fleets are out), where the hide case and the rest are done on a view made
## for the check (not the Admiral's own), by writing the units' sight masks, the world clock and a few hulls directly,
## all put back at the end. It prints "teamview_check: N failures" (a FAIL line for each) and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --seed=7 --test=teamview_check
##
## WHO USES IT: main.gd loads it for --test=teamview_check (it calls setup()).

## The frame of the scenario: 20 game seconds at 60 frames a second.
const SCENARIO_FRAME := 1200
## The reads of the world that only TeamView may make in the Admiral's files (a regular expression).
const READS := "\\b(world|w)\\.(ships|minions|units|nodes|bays|wards|unit_hash|motherships|defense_posts|profiles)\\b|\\.mothership\\(|\\.visible_to\\(|visible_mask|seen_mask|any_enemy_ship_near"
## The feature modules that are off by default, are not part of the computer Admiral's standing parts, and still read the
## world themselves (the scout's list of Wed 11-11, plus admiral_assets.gd, which the scan found). They may; every other file
## that is scanned may not.
const EXEMPT := [
	"res://scripts/features/siege_fix.gd", "res://scripts/features/admiral_assets_ai.gd", "res://scripts/features/admiral_assets.gd",
	"res://scripts/features/doctrine.gd", "res://scripts/features/fortify.gd", "res://scripts/features/admiral_smart.gd",
	"res://scripts/features/admiral_orders.gd",
]

## The running match (set by setup()).
var world: World
## How many checks failed.
var _fails := 0
## Frames seen so far.
var _frames := 0
## True once the scenario has run.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	_scan()
	_off_equals_live()
	var ai0: AdmiralAI = world.admiral_ai[0]
	if ai0 != null:
		_check("fleet: the fleet layer exists exactly when fleet_play is on", (ai0.fleet != null) == ai0.profile.on("fleet_play"))


## Count the frames; at SCENARIO_FRAME run the scenario, print the result and quit.
func _physics_process(_delta: float) -> void:
	if world == null or _done:
		return
	_frames += 1
	if _frames < SCENARIO_FRAME:
		return
	_done = true
	_scenario()
	print("teamview_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


# --- 1. the file scan ----------------------------------------------------------------------------------------------

## The Admiral's files read no world unit list: every scanned file is clean, or is on the exempt list.
func _scan() -> void:
	var rx := RegEx.new()
	rx.compile(READS)
	var files: Array[String] = []
	for dir in ["res://scripts/ai", "res://scripts/features"]:
		for f in DirAccess.get_files_at(dir):
			if (f.begins_with("admiral") or f == "lane_influence.gd") and f.ends_with(".gd"):
				files.append(dir + "/" + f)
	for e: String in EXEMPT:
		if not files.has(e):
			files.append(e)
	var strict := 0
	var exempt_reads := {}
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		_check("scan: %s can be read" % path, src != "")
		var hits := 0
		for line in src.split("\n"):
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			var hash_at := code.find(" #")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			if rx.search(code) != null:
				hits += 1
		if EXEMPT.has(path):
			exempt_reads[path.get_file()] = hits
			_check("scan: exempt file %s still reads the world (else take it off the list)" % path.get_file(), hits > 0)
		else:
			strict += 1
			_check("scan: %s reads no world unit list directly" % path, hits == 0, "%d lines" % hits)
	_check("scan: the Admiral's own files were found", strict >= 10, str(strict))
	_check("scan: team_view.gd is the one place that reads the world (it does)", rx.search(FileAccess.get_file_as_string("res://scripts/ai/team_view.gd")) != null)
	print("teamview_check: scan: %d files with no direct read, %d exempt files: %s" % [strict, exempt_reads.size(), JSON.stringify(exempt_reads)])


# --- 2. team_view off: the old live answers --------------------------------------------------------------------------

## With the switch off every helper returns what the old live read returned.
func _off_equals_live() -> void:
	for t in 2:
		var v := TeamView.new(world, t, AdmiralProfile.make("standard", t))
		var e := 1 - t
		_check("off: team %d starts with the view off" % t, not v.enabled())
		_check("off: enemy_power is the old fleet_power of the enemy", v.enemy_power() == _old_power(e))
		_check("off: own_power is the old fleet_power of the team", v.own_power() == _old_power(t))
		var ms := world.mothership(e)
		_check("off: the enemy mothership is the live one", v.enemy_ms_present() and v.enemy_ms_pos() == ms.global_position and v.enemy_ms_hull() == ms.hull_frac())
		_check("off: hull distance is the live mothership's", v.enemy_ms_hull_dist(Vector2(1234.0, -777.0)) == ms.hull_dist(Vector2(1234.0, -777.0)))
		var ts := world.teams[t]
		for lane: String in MapLayout.LANE_ORDER:
			_check("off: team %d enemy_turrets on %s is the old count" % [t, lane], v.enemy_turrets(lane) == _old_turrets(e, lane))
			_check("off: stage_point on %s is TeamState's" % lane, v.stage_point(lane) == ts.siege_stage_point(lane))
			_check("off: assault_point on %s is TeamState's" % lane, v.assault_point(lane) == ts.siege_assault_point(lane))
			_check("off: enemy_ms_on_lane on %s is TeamState's" % lane, v.enemy_ms_on_lane(lane) == ts.enemy_ms_on_lane(lane))
		_check("off: own_ships are our live ships", v.own_ships().size() == _count_ships(t))
		_check("off: the view recorded nothing", v.enemy_ms_record().is_empty())
		_check("view unit: with the view off and no records the helper answers null for both kinds", v.nearest_seen_enemy_unit(Vector2.ZERO, 1.0e9) == null and v.nearest_seen_enemy_unit(Vector2.ZERO, 1.0e9, true, false) == null and v.nearest_seen_enemy_unit(Vector2.ZERO, 1.0e9, false, true) == null)


## The Admiral's old fleet_power, written out again here.
func _old_power(t: int) -> float:
	var p := 0.0
	for s: Ship in world.ships:
		if s.team == t and s.alive:
			p += float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())
	return p


## The old count of a team's lane turrets and defense post on a lane.
func _old_turrets(t: int, lane: String) -> int:
	var n := 0
	for node in world.nodes:
		if node.lane == lane and MapLayout.is_lane_site_kind(node.node_kind) and node.side == t:
			n += node.turret_count(t)
	if world.defense_posts.standing(t, lane):
		n += 1
	return n


## How many live ships a team has.
func _count_ships(t: int) -> int:
	var n := 0
	for s: Ship in world.ships:
		if s.team == t and s.alive:
			n += 1
	return n


# --- 3 to 5. the scenario --------------------------------------------------------------------------------------------

## A view for team 0 with the switch on (and the test switch as given), made for this check.
func _view(sees_all: bool = false) -> TeamView:
	var p := AdmiralProfile.make("standard", 0)
	p.set_value("team_view", 1)
	var v := TeamView.new(world, 0, p)
	v.sees_all = sees_all
	return v


## Make every enemy ship (and the enemy mothership) seen by team 0 (`on`) or not seen by it.
func _show(ships: Array, on: bool) -> void:
	for s: Ship in ships:
		if on:
			s.visible_mask |= 1
		else:
			s.visible_mask &= ~1


## The fleet layer's goal lane (LaneInfluence, fleet_play on, team view on) reads the enemy only through the view: every enemy
## ship is hidden and moved to the top lane's front, the scores of the lanes do not change and a goal lane chosen afterwards is
## the one chosen before; the same ships SEEN there do change the top lane's score (so the case has teeth). Positions and sight
## masks are put back.
func _fleet_hidden_case(enemy: Array) -> void:
	var p := AdmiralProfile.make("standard", 0)
	p.set_value("team_view", 1)
	p.set_value("fleet_play", 1)
	var v := TeamView.new(world, 0, p)
	var lanes := AdmiralLanes.new(world, 0)
	lanes.view = v
	var t0 := world.time
	var saved_pos := {}
	var saved_mask := {}
	for s: Ship in enemy:
		saved_pos[s] = s.global_position
		saved_mask[s] = s.visible_mask
		s.visible_mask &= ~1
	v.refresh()
	var inf := LaneInfluence.new(world, 0, lanes, p)
	inf.think(t0, false, Vector2.INF)
	# A second think, so the scores already carry the bonus of the lane held (the first think had no goal yet).
	inf.think(t0 + 0.5, false, Vector2.INF)
	var goal0 := inf.goal
	var scores0 := inf.scores.duplicate()
	_check("fleet: a goal lane is chosen at the first think", goal0 != "" and scores0.size() == 3, goal0)
	var spot := lanes.lane_point("top", 0.3)
	var i := 0
	for s: Ship in enemy:
		s.global_position = spot + Vector2(float(i) * 40.0, 0.0)
		i += 1
	world.time = t0 + 1.0
	v.refresh()
	inf.think(world.time, false, Vector2.INF)
	var same := true
	for lane: String in MapLayout.LANE_ORDER:
		if not is_equal_approx(float(inf.scores[lane]), float(scores0[lane])):
			same = false
	_check("fleet: a hidden enemy fleet moved to the top lane does not change any lane's score", same, "%s against %s" % [str(inf.scores), str(scores0)])
	_check("fleet: ... nor the goal lane", inf.goal == goal0, inf.goal)
	var inf2 := LaneInfluence.new(world, 0, lanes, p)
	inf2.think(world.time, false, Vector2.INF)
	_check("fleet: ... a goal lane chosen afterwards is the one chosen before the fleet moved", inf2.goal == goal0, "%s against %s" % [inf2.goal, goal0])
	for s: Ship in enemy:
		s.visible_mask |= 1
	world.time = t0 + 2.0
	v.refresh()
	inf.think(world.time, false, Vector2.INF)
	_check("fleet: the same fleet seen there lowers the top lane's score", float(inf.scores["top"]) < float(scores0["top"]) - 0.5, "%f against %f" % [float(inf.scores["top"]), float(scores0["top"])])
	# enemy_near_many gives the answers of enemy_near, place by place (the view on and, below, off).
	var asked: Array = [spot, lanes.lane_point("mid", 0.5), Vector2.ZERO, spot + Vector2(3000.0, 0.0)]
	var many := v.enemy_near_many(asked, 6000.0)
	var same_many := many.size() == asked.size()
	for k in asked.size():
		if same_many and int(many[k]) != v.enemy_near(asked[k] as Vector2, 6000.0):
			same_many = false
	_check("fleet: enemy_near_many is enemy_near place by place (view on)", same_many and int(many[0]) > 0, str(many))
	var voff := TeamView.new(world, 0, AdmiralProfile.make("standard", 0))
	var many_off := voff.enemy_near_many(asked, 6000.0)
	var same_off := many_off.size() == asked.size()
	for k in asked.size():
		if same_off and int(many_off[k]) != voff.enemy_near(asked[k] as Vector2, 6000.0):
			same_off = false
	_check("fleet: enemy_near_many is enemy_near place by place (view off, live)", same_off and int(many_off[0]) > 0, str(many_off))
	for s: Ship in enemy:
		s.global_position = saved_pos[s]
		s.visible_mask = int(saved_mask[s])
	world.time = t0


## The helper's answer worked out again over the world's own lists (this file is the scanner, so it may read them): the enemy
## (team 1) ship or minion, alive, nearest to `p` within `r`, a tie to the lower instance id; with `need_seen` only those whose sight
## bit for team 0 is set. Turrets are never in it.
func _brute_unit(p: Vector2, r: float, ships: bool, minions: bool, need_seen: bool) -> Unit:
	var best: Unit = null
	var best_d := INF
	var pool: Array = []
	if ships:
		pool.append_array(world.ships)
	if minions:
		pool.append_array(world.minions)
	for u: Unit in pool:
		if u.team != 1 or not u.alive or (need_seen and not u.visible_to(0)):
			continue
		var d := u.global_position.distance_to(p)
		if d <= r and (best == null or d < best_d or (d == best_d and u.get_instance_id() < best.get_instance_id())):
			best = u
			best_d = d
	return best


## The helper nearest_seen_enemy_unit: with the team seeing everything its answer is the brute-force scan's for ships only, minions
## only and both, at several radii; a unit the team does not see is not returned (the next nearest is), and comes back when seen
## again. Two enemy minions are made for the case, and the sight masks of the ships are put back.
func _view_unit_cases(enemy: Array) -> void:
	var saved := {}
	for s: Ship in enemy:
		saved[s] = s.visible_mask
	var first: Ship = enemy[0]
	var p := first.global_position + Vector2(137.0, 61.0)
	var made: Array = []
	for k in 2:
		var m := world.spawn_minion(1, "fighter", "mid", p + Vector2(300.0 - 1300.0 * float(k), 200.0 * float(k)))
		made.append(m)
	_check("view unit: two enemy minions were made for the case", made.size() == 2 and made[0] != null and made[1] != null)
	var all := _view(true)
	all.refresh()
	var kinds_list: Array = [[true, false], [false, true], [true, true]]
	for r: float in [1.0e9, 6000.0, 1500.0, 400.0, 1.0]:
		for kinds: Array in kinds_list:
			var got := all.nearest_seen_enemy_unit(p, r, bool(kinds[0]), bool(kinds[1]))
			var want := _brute_unit(p, r, bool(kinds[0]), bool(kinds[1]), false)
			_check("view unit: sees_all, radius %d, ships %s, minions %s: the answer is the brute-force scan's" % [roundi(r), str(kinds[0]), str(kinds[1])], got == want, "%s against %s" % [str(got), str(want)])
	_check("view unit: sees_all, the case has teeth: a ship and a minion are both found with everything in reach", all.nearest_seen_enemy_unit(p, 1.0e9, true, false) is Ship and all.nearest_seen_enemy_unit(p, 1.0e9, false, true) is Minion)
	var seen := _view()
	_show(enemy, true)
	for m in made:
		if m != null:
			(m as Unit).visible_mask |= 1
	seen.refresh()
	for kinds: Array in [[true, false], [false, true]]:
		var tag := "ships" if bool(kinds[0]) else "minions"
		var near: Unit = seen.nearest_seen_enemy_unit(p, 1.0e9, bool(kinds[0]), bool(kinds[1]))
		_check("view unit: sight, %s: with everything seen the nearest is found" % tag, near != null)
		if near == null:
			continue
		near.visible_mask &= ~1
		seen.refresh()
		var next: Unit = seen.nearest_seen_enemy_unit(p, 1.0e9, bool(kinds[0]), bool(kinds[1]))
		_check("view unit: sight, %s: a unit the team does not see is not returned" % tag, next != near)
		_check("view unit: sight, %s: the next nearest is answered instead" % tag, next == _brute_unit(p, 1.0e9, bool(kinds[0]), bool(kinds[1]), true) and next != null)
		near.visible_mask |= 1
		seen.refresh()
		_check("view unit: sight, %s: the cleared unit comes back when its bit is set again" % tag, seen.nearest_seen_enemy_unit(p, 1.0e9, bool(kinds[0]), bool(kinds[1])) == near)
	for s: Ship in enemy:
		s.visible_mask = int(saved[s])
	for m in made:
		if m != null:
			(m as Unit).alive = false


## The hide case, the seen and unseen deaths, the mothership, the spot seen empty and the test switch.
func _scenario() -> void:
	var enemy: Array = []
	for s: Ship in world.ships:
		if s.team == 1 and s.alive:
			enemy.append(s)
	_check("scenario: the enemy has ships at 20 s", enemy.size() >= 2, str(enemy.size()))
	if enemy.size() < 2:
		return
	var t0 := world.time
	var saved_masks := {}
	for s: Ship in enemy:
		saved_masks[s] = s.visible_mask
	var ems := world.mothership(1)
	var ms_mask := ems.visible_mask
	var ms_hull := ems.hull
	var ms_pos := ems.global_position

	# -- the hide case: seen now, then hidden at 0 s, 45 s, 90 s.
	var v := _view()
	_show(enemy, true)
	v.refresh()
	var live_micro := 0
	for s: Ship in enemy:
		live_micro += v._micro(Rules.size_index(s.size_class), v._hp(s.hull_frac()))
	_check("hide: seen, every enemy ship is recorded", v.enemy_ship_count() == enemy.size(), "%d of %d" % [v.enemy_ship_count(), enemy.size()])
	_check("hide: seen, the strength is the live strength in whole micro-points", v.enemy_strength_micro() == live_micro, "%d against %d" % [v.enemy_strength_micro(), live_micro])
	_check("hide: seen, the strength in thousandths is that sum rounded", v.enemy_strength() == (live_micro + 500) / 1000)
	_check("hide: seen, the old float strength is within a thousandth of the live one", absf(v.enemy_power() - _old_power(1)) < 0.005, "%f against %f" % [v.enemy_power(), _old_power(1)])
	var full_near := v.enemy_near(Vector2.ZERO, 1.0e9)
	_check("hide: seen, where is at full weight", absf(float(full_near) - float(v.enemy_strength())) <= 1.0, "%d against %d" % [full_near, v.enemy_strength()])
	_show(enemy, false)
	var full := v.enemy_strength()
	for step in [[0.0, 1000], [45.0, 500], [90.0, 0]]:
		world.time = t0 + float(step[0])
		v.refresh()
		var near := v.enemy_near(Vector2.ZERO, 1.0e9)
		var want := int(round(float(full) * float(step[1]) / 1000.0))
		_check("hide: %d s after the last sighting where is %d thousandths (near=%d, want %d)" % [int(step[0]), int(step[1]), near, want], absi(near - want) <= 1)
		_check("hide: %d s after the last sighting that they exist is still full (%d)" % [int(step[0]), v.enemy_strength()], v.enemy_strength() == full and v.enemy_ship_count() == enemy.size())
	world.time = t0 + 299.0
	v.refresh()
	_check("hide: at 299 s they still count", v.enemy_strength() == full)
	world.time = t0 + 301.0
	v.refresh()
	_check("hide: past the stale cap (300 s) they are gone", v.enemy_ship_count() == 0 and v.enemy_strength() == 0, str(v.enemy_ship_count()))

	# -- a ship seen dying is dropped at once; one that dies unseen stays.
	world.time = t0
	var a: Ship = enemy[0]
	var b: Ship = enemy[1]
	var v2 := _view()
	_show(enemy, true)
	v2.refresh()
	var n2 := v2.enemy_ship_count()
	b.visible_mask &= ~1
	world.time = t0 + 1.0
	v2.refresh()
	a.alive = false
	b.alive = false
	world.time = t0 + 2.0
	v2.refresh()
	_check("dead: a ship seen dying is dropped, one that died unseen stays", v2.enemy_ship_count() == n2 - 1, "%d of %d" % [v2.enemy_ship_count(), n2])
	world.time = t0 + 400.0
	v2.refresh()
	_check("dead: the one that died unseen goes at the stale cap (the seen ships stay)", v2.enemy_ship_count() == n2 - 2, "%d of %d" % [v2.enemy_ship_count(), n2])
	a.alive = true
	b.alive = true
	world.time = t0

	# -- the enemy mothership: kept at the last-seen place and hull, no fade, changed only on sight.
	var v3 := _view()
	var home := ems.global_position
	v3.refresh()
	var r0 := v3.enemy_ms_record()
	_check("ms: before the first sight it is at its home spot with a full hull", v3.enemy_ms_pos() == home and v3.enemy_ms_hull() == 1.0 and float(r0["seen"]) < 0.0)
	ems.visible_mask |= 1
	ems.hull = ems.hull_max * 0.5
	ems.global_position = home + Vector2(5000.0, 0.0)
	world.time = t0 + 1.0
	v3.refresh()
	_check("ms: seen, it takes the live place and hull", v3.enemy_ms_pos() == ems.global_position and absf(v3.enemy_ms_hull() - 0.5) < 0.001, str(v3.enemy_ms_hull()))
	var seen_pos := ems.global_position
	ems.visible_mask &= ~1
	ems.hull = ems.hull_max
	ems.global_position = home + Vector2(0.0, 9000.0)
	world.time = t0 + 250.0
	v3.refresh()
	_check("ms: 250 s unseen, it keeps its last-seen place and hull with no fade", v3.enemy_ms_pos() == seen_pos and absf(v3.enemy_ms_hull() - 0.5) < 0.001, str(v3.enemy_ms_hull()))
	_check("ms: its hull distance and lane maths use the last-seen place", absf(v3.enemy_ms_hull_dist(seen_pos)) <= ems.beam * 0.5 + 1.0 and v3.enemy_ms_on_lane("mid")["point"] == Util.project_on_polyline(seen_pos, MapLayout.lane_points("mid", 0))["point"])
	ems.visible_mask |= 1
	world.time = t0 + 251.0
	v3.refresh()
	_check("ms: seen again, it moves to the new place and the full hull", v3.enemy_ms_pos() == ems.global_position and v3.enemy_ms_hull() == 1.0)
	ems.visible_mask = ms_mask
	ems.hull = ms_hull
	ems.global_position = ms_pos
	world.time = t0

	# -- a spot seen empty: a gone turret leaves the record only when the team sees its place.
	var lane_turret: Unit = null
	var lane_name := ""
	for node: ResourceNode in world.nodes:
		if node.side == 1 and MapLayout.is_lane_site_kind(node.node_kind):
			for tu in node.slots:
				if tu != null and is_instance_valid(tu) and tu.alive and lane_turret == null:
					lane_turret = tu
					lane_name = node.lane
	_check("spot: an enemy lane turret was found", lane_turret != null)
	if lane_turret != null:
		var v4 := _view()
		v4.refresh()
		var before := v4.enemy_turrets(lane_name)
		var live_before := _old_turrets(1, lane_name)
		_check("spot: the record starts from the map's layout (the turrets stand)", before == live_before and before >= 1, "%d against %d" % [before, live_before])
		var seen_now: bool = world.vision.is_visible(0, lane_turret.global_position)
		lane_turret.alive = false
		world.time = t0 + 1.0
		v4.refresh()
		if not seen_now:
			_check("spot: gone but not seen, the turret still counts", v4.enemy_turrets(lane_name) == before, str(v4.enemy_turrets(lane_name)))
		var v5 := _view(true)
		world.time = t0
		lane_turret.alive = true
		v5.refresh()
		lane_turret.alive = false
		world.time = t0 + 1.0
		v5.refresh()
		_check("spot: gone and seen (the spot is in sight), the turret is dropped", v5.enemy_turrets(lane_name) == before - 1, "%d of %d" % [v5.enemy_turrets(lane_name), before])
		lane_turret.alive = true
		world.time = t0

	# -- the test switch: with the team seeing everything, the answers are the live answers.
	for s: Ship in enemy:
		s.visible_mask = int(saved_masks[s]) & ~1
	var v6 := _view(true)
	v6.refresh()
	var live6 := 0
	for s: Ship in world.ships:
		if s.team == 1 and s.alive:
			live6 += v6._micro(Rules.size_index(s.size_class), v6._hp(s.hull_frac()))
	_check("sees_all: the strength in micro-points is the live sum", v6.enemy_strength_micro() == live6, "%d against %d" % [v6.enemy_strength_micro(), live6])
	_check("sees_all: the old float strength is within a thousandth of the live one", absf(v6.enemy_power() - _old_power(1)) < 0.005)
	_check("sees_all: the mothership is the live one", v6.enemy_ms_pos() == ems.global_position and absf(v6.enemy_ms_hull() - ems.hull_frac()) <= 0.0005)
	var ts0 := world.teams[0]
	for lane: String in MapLayout.LANE_ORDER:
		_check("sees_all: turrets on %s are the live count" % lane, v6.enemy_turrets(lane) == _old_turrets(1, lane))
		_check("sees_all: the stage point on %s is TeamState's" % lane, v6.stage_point(lane) == ts0.siege_stage_point(lane))
		_check("sees_all: the assault point on %s is TeamState's" % lane, v6.assault_point(lane) == ts0.siege_assault_point(lane))

	# -- the seen enemy unit helper: the nearest enemy ship or minion the team sees.
	_view_unit_cases(enemy)

	# -- fleet play (RT8 build 8a): a hidden enemy fleet does not move the goal lane.
	_fleet_hidden_case(enemy)

	# -- put every mask back.
	for s: Ship in enemy:
		s.visible_mask = int(saved_masks[s])
	world.time = t0
