extends Node
## WHAT THIS IS: the check of the practice range (World.practice and everything that
## hangs on it). It builds practice matches and normal matches through WorldSetup and
## checks, item by item: the flag and the start choices, the open ship classes, the
## target drones and the score line.
##
## HOW IT WORKS: setup() runs everything, then quits. The match the run was launched
## with is the normal one (practice off); the check builds its own extra worlds for the
## practice cases (a world is made from its scene, set up in the seat of the launched
## match, paused so nothing ticks unless a check steps it, and freed after its checks).
## It sets Game.practice_start and Game.practice_others itself and puts every Game field
## back at the end. The step functions of the checks are run in order by setup().
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=practice_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --force-hud --seed=7 --test=practice_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what>
## <detail>". The last line is "practice_check: N failures"; 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=practice_check. It only reads the game it
## builds, so it is only for this check.

## The world scene every match is made from.
const WORLD_SCENE := "res://scenes/world/world.tscn"

## The match the run was launched with (a normal match; set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Game.practice_start as the run found it (put back at the end).
var _saved_start := false
## Game.practice_others as the run found it (put back at the end).
var _saved_others := PracticeRange.OTHERS_DEFAULT


## main.gd calls this once, right after the World is built. Run every check and quit.
func setup(w: World) -> void:
	world = w
	_saved_start = Game.practice_start
	_saved_others = Game.practice_others
	print("practice_check: seat=%s" % world.human_role)
	_check_flag_and_choices()
	_check_open_classes()
	_check_drones()
	await _check_drawing()
	await _check_trials()
	_finish()


## Put the Game fields and the running match back and quit with the failure count.
func _finish() -> void:
	Game.practice_start = _saved_start
	Game.practice_others = _saved_others
	Game.world = world
	print("practice_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the measured
## `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Build a match through WorldSetup in the seat of the launched match, as a practice
## match with the choice `others` when `practice` is true: made from the world scene,
## added to this node and paused (nothing ticks unless a check steps it). The Game fields are put
## back at once, so the next build starts from the launched state.
func _build(practice: bool, others: String = "nobody", role: String = "") -> World:
	Game.practice_start = practice
	Game.practice_others = others
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	add_child(w)
	w.set_physics_process(false)
	w.setup(world.human_role if role == "" else role)
	Game.practice_start = _saved_start
	Game.practice_others = _saved_others
	Game.world = world
	return w


## Free a world a check built (and tell Game the launched match is the running one).
func _drop(w: World) -> void:
	remove_child(w)
	w.free()
	Game.world = world


## How many pilot profiles of team `t` the world holds, the Admiral seats not counted.
func _pilots(w: World, t: int) -> int:
	var n := 0
	for p: PilotProfile in w.profiles:
		if p.team == t and p.role != "admiral":
			n += 1
	return n


## How many Admiral-seat profiles of team `t` the world holds (the human's and the computer's).
func _admiral_seats(w: World, t: int) -> int:
	var n := 0
	for p: PilotProfile in w.profiles:
		if p.team == t and p.role == "admiral":
			n += 1
	return n


## Item 1: the flag, the start choices and what they leave on the map.
func _check_flag_and_choices() -> void:
	var role := world.human_role
	var ours := world.human_team
	var theirs := Rules.enemy_of(ours)
	var pilot_seat := role == "pilot"
	# The launched match is a normal one: the flag is off and the seats are as they always were.
	_check("a normal match has practice off", not world.practice, str(world.practice))
	_check("a normal match has 5 pilots on each team", _pilots(world, ours) == 5 and _pilots(world, theirs) == 5, "%d and %d" % [_pilots(world, ours), _pilots(world, theirs)])
	_check("a normal match has the Admiral seats it always had", _admiral_seats(world, ours) == 1 and _admiral_seats(world, theirs) == 1, "%d and %d" % [_admiral_seats(world, ours), _admiral_seats(world, theirs)])
	# The three choices of who else is on the map, in the same seat.
	var human_here := 1 if pilot_seat else 0
	var cases := {
		"nobody": {"ours": human_here, "theirs": 0, "admirals": false},
		"allies": {"ours": 5, "theirs": 0, "admirals": false},
		"both": {"ours": 5, "theirs": 5, "admirals": true},
	}
	for others: String in PracticeRange.OTHERS:
		var want: Dictionary = cases[others]
		var w := _build(true, others)
		var tag := "practice \"%s\":" % others
		_check("%s the flag is on" % tag, w.practice)
		_check("%s your team has %d pilots and the other %d" % [tag, want["ours"], want["theirs"]], _pilots(w, ours) == want["ours"] and _pilots(w, theirs) == want["theirs"], "%d and %d" % [_pilots(w, ours), _pilots(w, theirs)])
		var ai_admirals := (w.admiral_ai[ours] != null) or (w.admiral_ai[theirs] != null)
		if want["admirals"]:
			_check("%s the computer Admirals are made" % tag, (w.admiral_ai[theirs] != null) and (w.admiral_ai[ours] != null) == pilot_seat, "ours %s, theirs %s" % [str(w.admiral_ai[ours] != null), str(w.admiral_ai[theirs] != null)])
		else:
			_check("%s no computer Admiral is made" % tag, not ai_admirals)
		_check("%s only the human's own Admiral seat is there" % tag if not want["admirals"] else "%s the Admiral seats are the human's and the computers'" % tag,
				_admiral_seats(w, ours) == (1 if (want["admirals"] or not pilot_seat) else 0) and _admiral_seats(w, theirs) == (1 if want["admirals"] else 0),
				"%d and %d" % [_admiral_seats(w, ours), _admiral_seats(w, theirs)])
		_check("%s the map is the real one (lanes, posts, turrets, camps, both motherships)" % tag, w.posts.size() == 6 and w.turrets.size() >= 18 and w.motherships.size() == 2 and not w.map.camps.is_empty(), "%d posts, %d turrets, %d camps" % [w.posts.size(), w.turrets.size(), w.map.camps.size()])
		_check_pilots_down(w, others)
		_drop(w)
	# A spectator cannot start a range.
	var spec := _build(true, "both", "spectator")
	_check("a spectator seat starts no range even with the choice made", not spec.practice, str(spec.practice))
	_drop(spec)
	# The choice itself: choose_practice() sets the two fields and starts nothing; a word that is not a choice means nobody.
	Game.practice_start = false
	Game.choose_practice("allies")
	_check("choose_practice sets the choice", Game.practice_start and Game.practice_others == "allies", "%s %s" % [str(Game.practice_start), Game.practice_others])
	Game.choose_practice("banana")
	_check("a word that is not a choice means nobody", Game.practice_start and Game.practice_others == "nobody", Game.practice_others)
	Game.clear_practice()
	_check("clear_practice puts the choice back", not Game.practice_start and Game.practice_others == "nobody")
	_check("the flag of the match that was running is unchanged", not world.practice)


## The purse of the shop checks (credits).
const PURSE := 100000.0
## Two sums closer than this many credits count as equal.
const TOLERANCE := 1e-6


## Item 2: the ship classes open to the human of a range (prices stay), the PRACTICE tag, the end
## screen's title and the practice mark in the stats record.
func _check_open_classes() -> void:
	var big := "battlecruiser"
	var price := float(Ships.HULLS[big]["price"])
	# The shop of a practice human: a class whose research the team lacks is offered, at its list price.
	var p := _build(true, "both")
	Game.world = p
	var h := p.human
	var ts: TeamState = p.teams[h.team]
	_check("practice: the team lacks the research for the %s" % big, not ts.ship_unlocked(big))
	_check("practice: the question says yes for the human's record", PracticeRange.locks_open(h))
	h.credits = PURSE
	h.hull_id = ""
	var err := h.buy_hull(big, ts)
	_check("practice: the human buys the %s without the research" % big, err == "" and h.hull_id == big, "'%s', hull %s" % [err, h.hull_id])
	_check("practice: it costs the list price (%d)" % int(price), absf((PURSE - h.credits) - price) <= TOLERANCE, "paid %.1f" % (PURSE - h.credits))
	_check("practice: the team's research is unchanged by it", not ts.ship_unlocked(big))
	# A computer pilot of either team still meets the lock and the price in the same match.
	for t in 2:
		for q: PilotProfile in p.profiles:
			if q.team == t and not q.is_human and q.role != "admiral":
				q.credits = PURSE
				q.hull_id = ""
				var e := q.buy_hull(big, p.teams[t])
				_check("practice: %s (team %d, a computer pilot) meets the lock" % [q.callsign, t], e.begins_with("Locked: needs") and not PracticeRange.locks_open(q), e)
				break
	# The top bar: PRACTICE is in the tag line in the range, and only there.
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud != null:
		var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
		hud.top_bar.refresh(p)
		_check("practice: the tag line holds PRACTICE", tags.visible and tags.text.begins_with("PRACTICE"), "'%s'" % tags.text)
		hud.top_bar.refresh(world)
		_check("a normal match: the tag line holds no PRACTICE", not tags.text.contains("PRACTICE"), "'%s'" % tags.text)
	else:
		_check("the HUD exists for the tag check", false, "no Hud node (use --force-hud)")
	# The stats record: a range marks "match", a normal match has no such key.
	var rec := StatsRecorder.new()
	rec.world = p
	var in_range: Dictionary = rec.snapshot(false, "check")["match"]
	rec.world = world
	var outside: Dictionary = rec.snapshot(false, "check")["match"]
	rec.free()
	_check("practice: the stats record's match carries \"practice\": true", in_range.get("practice", false) == true, str(in_range.keys()))
	_check("a normal match: its stats record has no practice key", not outside.has("practice"), str(outside.keys()))
	# The end screen: the title of a range reads "Practice range", a normal match's does not.
	var titles := {}
	for w: World in [p, world]:
		var es := (load("res://scenes/ui/end_screen.tscn") as PackedScene).instantiate() as EndScreen
		es.setup(w, w.human_team, "check")
		add_child(es)
		titles[w] = (es.get_node("Center/Card/Col/Title") as Label).text
		es.free()
	_check("practice: the end screen's title reads Practice range", titles[p] == "Practice range", str(titles[p]))
	_check("a normal match: the end screen's title is not Practice range", titles[world] != "Practice range", str(titles[world]))
	# A normal match refuses the class, as it always did.
	Game.world = world
	var nh := world.human
	var nts: TeamState = world.teams[nh.team]
	nh.credits = PURSE
	nh.hull_id = ""
	var ne := nh.buy_hull(big, nts)
	_check("a normal match: the human meets the lock on the %s" % big, ne.begins_with("Locked: needs") and nh.hull_id == "" and not PracticeRange.locks_open(nh), ne)
	nh.credits = Rules.START_CREDITS
	_drop(p)


## How many drones of kind `kind_id` the world holds.
func _drones_of(w: World, kind_id: String) -> int:
	var n := 0
	for d: PracticeDrone in w.practice_drones:
		if d.row_id == kind_id and d.alive:
			n += 1
	return n


## Step world `w` by `ticks` ticks (it is paused, so a check drives it by hand).
func _step(w: World, ticks: int) -> void:
	for i in ticks:
		w._physics_process(1.0 / 60.0)


## Count of Events.credits_earned messages seen while a check watches (every payment goes through it).
var _paid_events := 0


## Events.credits_earned: count one more payment.
func _on_paid(_profile: RefCounted, _amount: float, _reason: String) -> void:
	_paid_events += 1


## Item 3: the target drones: the default set, what they are to the two teams and the computer,
## a shot that destroys one, the return after 3 seconds, and that nobody is paid for one.
func _check_drones() -> void:
	# A normal match holds no drone, no range and no tick hook.
	_check("a normal match holds no drone and no range", world.practice_drones.is_empty() and world.practice_range == null, "%d drones" % world.practice_drones.size())
	var p := _build(true, "both")
	Game.world = p
	# The default set: 4 still and 4 moving beside each team's lane post, and 1 capital drone in the middle.
	_check("practice: the range holds 8 still, 8 moving and 1 capital drone", _drones_of(p, "still") == 8 and _drones_of(p, "moving") == 8 and _drones_of(p, "capital") == 1, "%d, %d, %d" % [_drones_of(p, "still"), _drones_of(p, "moving"), _drones_of(p, "capital")])
	var listed := true
	for d: PracticeDrone in p.practice_drones:
		listed = listed and p.units.has(d) and p.by_uid.get(d.uid) == d and d.team == Rules.NEUTRAL and d.kind == Unit.K_PRACTICE_DRONE
	_check("practice: every drone is a neutral unit kept in the world's lists", listed)
	var rows_ok := true
	for d: PracticeDrone in p.practice_drones:
		var row := PracticeDrones.row(d.row_id)
		rows_ok = rows_ok and d.radius == float(row["radius"]) and d.hull_max == float(row["hull"]) and d.sections == int(row["sections"])
	_check("practice: each drone has its row's radius, hull and sections", rows_ok)
	# The two teams and the computer: no team's tower, minion or computer pilot is made to shoot one.
	var d0: PracticeDrone = null
	for d: PracticeDrone in p.practice_drones:
		if d.row_id == "still" and not p.asteroids.blocked(d.position - Vector2(150.0, 0.0), 30.0) and not p.asteroids.segment_blocked(d.position - Vector2(150.0, 0.0), d.position):
			d0 = d
			break
	if d0 == null:
		_check("practice: a still drone with a clear line was found", false)
		_drop(p)
		return
	var spot := d0.position
	_check("practice: no team's search for the nearest enemy finds a drone (nearest_enemy)", not (p.nearest_enemy(spot, 400.0, 0) is PracticeDrone) and not (p.nearest_enemy(spot, 400.0, 1) is PracticeDrone))
	for t in 2:
		var view := TeamView.of(p, t, AdmiralProfile.for_team(t, Game.options))
		_check("practice: team %d's Admiral view counts no drone (enemy_near, own_near)" % t, view.enemy_near(spot, 600.0) == 0 and view.own_near(spot, 600.0) == 0)
	_check_ai_ignores(p, d0)
	# A moving drone follows its loop at its speed, facing the way it flies; a still one stays.
	var mover: PracticeDrone = null
	for d: PracticeDrone in p.practice_drones:
		if d.row_id == "moving":
			mover = d
			break
	var start := mover.position
	_step(p, 30)
	var moved := mover.position.distance_to(start)
	_check("practice: a moving drone flies (%.0f units in half a second at speed %.0f)" % [moved, mover.speed], moved > 100.0 and moved < mover.speed, "%.1f" % moved)
	_check("practice: it faces the way it flies", absf(angle_difference(mover.rotation, mover.velocity.angle())) < 0.01)
	_check("practice: a still drone stays where it was put", d0.position.is_equal_approx(spot))
	# A shot from the human's ship destroys a still drone, and it returns in 3 seconds at its place.
	var h := p.human
	var ts: TeamState = p.teams[h.team]
	h.credits = Rules.START_CREDITS
	h.hull_id = ""
	h.buy_hull("fighter", ts)
	var ship := p.launch(h)
	_check("practice: the human launches a ship", ship != null and ship.alive)
	if ship == null:
		_drop(p)
		return
	ship.global_position = spot - Vector2(150.0, 0.0)
	ship.velocity = Vector2.ZERO
	p.registry.rebuild_hashes()
	var row_id := d0.row_id
	var home := d0.home
	var before_count := p.practice_drones.size()
	p.projectiles.spawn(ship.global_position, Vector2(1200.0, 0.0), 0.5, 100000.0, Rules.W_BOLT, Weapons.get_def("fighter_cannon"), ship, null)
	_step(p, 20)
	_check("practice: the shot destroyed the drone", not is_instance_valid(d0) or not d0.alive)
	_check("practice: the world's list holds one drone less until it returns", p.practice_drones.size() == before_count - 1 and p.practice_range.pending.size() == 1, "%d of %d, %d waiting" % [p.practice_drones.size(), before_count, p.practice_range.pending.size()])
	_step(p, PracticeDrones.REPLACE_TICKS - 40)
	_check("practice: it is still gone before the 3 seconds are up", p.practice_drones.size() == before_count - 1)
	_step(p, 60)
	var back: PracticeDrone = null
	for d: PracticeDrone in p.practice_drones:
		if d.row_id == row_id and d.alive and d.home.is_equal_approx(home):
			back = d
	_check("practice: the same kind is back at the same place after 3 seconds", back != null and p.practice_drones.size() == before_count and back.hull == back.hull_max, "%d drones" % p.practice_drones.size())
	# Nobody is paid for it: no bounty, no kill credit, nothing for the treasury.
	if back != null:
		_paid_events = 0
		Events.credits_earned.connect(_on_paid)
		var earned := h.earned
		var credits := h.credits
		var treasury := [p.teams[0].treasury, p.teams[1].treasury]
		var kills := h.kills
		p.combat.kill(back, DamageInfo.from_unit(ship, 1.0, Rules.W_BOLT, ship.global_position))
		Events.credits_earned.disconnect(_on_paid)
		_check("practice: a destroyed drone pays nothing (earned, purse, both treasuries, kills)", h.earned == earned and h.credits == credits and p.teams[0].treasury == treasury[0] and p.teams[1].treasury == treasury[1] and h.kills == kills and _paid_events == 0, "%d payments" % _paid_events)
	_drop(p)


## The drawing commands one drone of kind `id` costs in a frame, counted from the code of
## UnitVisual._draw_practice_drone(): the disc, the band, the inner ring and the dot (4), the wake of
## a drone that moves or drifts (1), the ticks between sections while the disc is 16 pixels across or
## more (1, `ticks`), and the capital drone's part sockets (1).
func _draw_calls(id: String, ticks: bool) -> int:
	var n := 4
	if float(PracticeDrones.row(id)["speed"]) > 0.0:
		n += 1
	if ticks:
		n += 1
	if id == "capital":
		n += 1
	return n


## Item 4: a drone of each kind is drawn (the Bullseye) by the HUD's world without a script error: one of
## each is put in the camera's view, shown, hit once so the flash path runs, and two frames are waited;
## every painter must then have drawn. (A script error would be in the run's log, which the
## error scan reads.) The drawing commands per drone are counted from the code and printed.
func _check_drawing() -> void:
	var p := _build(true, "nobody")
	Game.world = p
	var cam := get_viewport().get_camera_2d()
	var centre := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var drones: Array[PracticeDrone] = []
	var spot := centre
	for id: String in PracticeDrones.ROWS:
		var d := p.spawn_practice_drone(id, spot)
		d.visible = true
		d.flash = 0.09 if id == "moving" else 0.0
		drones.append(d)
		spot += Vector2(300.0, 150.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var drawn := 0
	for d: PracticeDrone in drones:
		var painter := d.get_node_or_null("Visual") as UnitVisual
		if painter != null and painter._drawn:
			drawn += 1
		else:
			print("FAIL-DETAIL the %s drone's painter has not drawn (visible %s, in the tree %s)" % [d.row_id, str(d.visible), str(d.is_inside_tree())])
	_check("a drone of each kind is drawn by its painter (3 of 3 painters drew)", drawn == drones.size(), "%d of %d" % [drawn, drones.size()])
	var counts := []
	for id: String in PracticeDrones.ROWS:
		counts.append("%s %d (%d with the ticks)" % [id, _draw_calls(id, false), _draw_calls(id, true)])
	print("INFO drawing commands per drone and frame, counted from the code: %s" % ", ".join(PackedStringArray(counts)))
	_check("the capital drone costs at most 7 drawing commands and a small one at most 6", _draw_calls("capital", true) == 7 and _draw_calls("moving", true) == 6 and _draw_calls("still", true) == 5)
	_drop(p)


## Launch the human of world `p` in hull `hull` (bought at its list price with a big purse; a class the
## team has not researched is open in the range), step two ticks so the trials see the new ship, and
## return the ship (null when it could not launch).
func _launch_human(p: World, hull: String) -> Ship:
	var h := p.human
	h.credits = PURSE
	h.hull_id = ""
	var err := h.buy_hull(hull, p.teams[h.team])
	if err != "":
		print("FAIL-DETAIL buying %s: %s" % [hull, err])
		return null
	var ship := p.launch(h)
	_step(p, 2)
	return ship


## A hit of weapon kind `kind` from the human's ship `ship` on drone `d`, through Combat (the path a shot or a beam takes).
func _hit(p: World, ship: Ship, d: PracticeDrone, kind: int) -> void:
	p.combat.apply_damage(d, DamageInfo.from_unit(ship, 1.0, kind, ship.global_position))


## The first `n` drones of kind `kind_id` of world `p`, in the world's order.
func _first_drones(p: World, kind_id: String, n: int) -> Array[PracticeDrone]:
	var out: Array[PracticeDrone] = []
	for d: PracticeDrone in p.practice_drones:
		if d.row_id == kind_id and d.alive and out.size() < n:
			out.append(d)
	return out


## Item 5: the trials and the score line. In a practice match with a HUD the line exists and a normal
## match's HUD has none; the Lance trial counts five different moving drones hit with its weapon kind and
## ends with the result line; a hit with another weapon, or on the wrong kind of drone, counts for nothing;
## the Bomber's trial counts a torpedo on the capital drone; a new launch starts the trial again; a timed
## trial ends when its time is up.
func _check_trials() -> void:
	# The HUDs: the launched match's has no score line; a practice match's has one.
	var main_hud := get_tree().root.find_child("Hud", true, false) as Hud
	if main_hud != null:
		_check("a normal match's HUD has no score line", main_hud.get_node_or_null("PracticeStatus") == null)
	var p := _build(true, "nobody")
	Game.world = p
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.setup(p, null)
	_check("practice: the HUD has a score line", hud.get_node_or_null("PracticeStatus") is PracticeStatus)
	var tr := p.practice_range.trials
	_check("practice: before a launch the trial is idle and says so", tr.state == "idle" and PracticeStatus.text_line(tr).begins_with("Launch"), PracticeStatus.text_line(tr))
	# The Lance: five different moving drones with its weapon kind.
	var ship := _launch_human(p, "lance")
	if ship == null:
		_check("practice: the human launches the Lance fighter", false)
		hud.free()
		_drop(p)
		return
	_check("practice: a launch starts the Lance trial", tr.state == "running" and tr.trial["hull"] == "lance" and tr.count_text() == "0 / 5", "%s %s" % [tr.state, tr.count_text()])
	_check("practice: the score line gives the plan's words", PracticeStatus.text_line(tr) == "Trial: hit five moving drones with the Lance bolt", PracticeStatus.text_line(tr))
	var movers := _first_drones(p, "moving", 6)
	var stills := _first_drones(p, "still", 1)
	var big := _first_drones(p, "capital", 1)
	_hit(p, ship, movers[0], Rules.W_BOLT)
	_check("practice: a hit with another weapon does not count", tr.hit_uids.is_empty(), tr.count_text())
	_hit(p, ship, stills[0], Rules.W_LANCE)
	_hit(p, ship, big[0], Rules.W_LANCE)
	_check("practice: a Lance hit on the wrong kind of drone does not count", tr.hit_uids.is_empty(), tr.count_text())
	for i in 4:
		_hit(p, ship, movers[i], Rules.W_LANCE)
	_hit(p, ship, movers[0], Rules.W_LANCE)
	_check("practice: four different drones count, the same one again does not", tr.state == "running" and tr.hit_uids.size() == 4, tr.count_text())
	_hit(p, ship, movers[4], Rules.W_LANCE)
	_check("practice: the fifth drone ends the trial with a result line", tr.state == "done" and tr.result_line().begins_with("Done: 5 hits in "), tr.result_line())
	_check("practice: the score line shows the result", PracticeStatus.score_line(tr) == tr.result_line())
	_hit(p, ship, movers[5], Rules.W_LANCE)
	_check("practice: a finished trial counts no more", tr.hit_uids.size() == 5)
	# A new launch starts it again.
	p.try_dock(ship, true)
	_step(p, 2)
	var ship2 := p.launch(p.human)
	_step(p, 2)
	_check("practice: a new launch starts the trial again", ship2 != null and tr.state == "running" and tr.hit_uids.is_empty() and tr.count_text() == "0 / 5", "%s %s" % [tr.state, tr.count_text()])
	# The Bomber: a torpedo on the capital drone (its class is open in the range, so it is bought at once).
	p.try_dock(ship2, true)
	_step(p, 2)
	var bomber := _launch_human(p, "bomber")
	if bomber != null:
		_check("practice: a launch of the Bomber starts the torpedo trial", tr.state == "running" and tr.trial["hull"] == "bomber" and tr.text() == "torpedo a drifting capital drone", tr.text())
		_hit(p, bomber, movers[0], Rules.W_TORP)
		_hit(p, bomber, big[0], Rules.W_BOLT)
		_check("practice: a torpedo on a small drone and a gun hit on the capital drone do not count", tr.hit_uids.is_empty())
		_hit(p, bomber, big[0], Rules.W_TORP)
		_check("practice: a torpedo on the capital drone counts and ends the trial", tr.state == "done" and tr.result_line().begins_with("Done: 1 hit in "), tr.result_line())
		p.try_dock(bomber, true)
		_step(p, 2)
	else:
		_check("practice: the human launches the Bomber", false)
	# A timed trial ends when its time is up.
	var fighter := _launch_human(p, "fighter")
	if fighter != null:
		_check("practice: the Fighter's trial is timed", tr.state == "running" and float(tr.trial["secs"]) == 60.0)
		p.time += 61.0
		_step(p, 1)
		_check("practice: the timed trial ends when the 60 seconds are up", tr.state == "timeout" and tr.result_line() == "Time up: 0 of 5 hits", tr.result_line())
	else:
		_check("practice: the human launches the Fighter", false)
	hud.free()
	_drop(p)


## A computer pilot beside a drone never picks it as a target (while in a lane, which is where a computer
## pilot is made to fight). A pilot that is jungling would see it as any neutral unit, so what it does
## is only printed here: whether to make that stricter is the lead's call (a guard in PilotTargeting).
func _check_ai_ignores(p: World, d: PracticeDrone) -> void:
	var pilot: PilotProfile = null
	for q: PilotProfile in p.profiles:
		if q.team == Rules.enemy_of(p.human_team) and p.pilot_ai.has(q) and q.role != "admiral":
			pilot = q
			break
	if pilot == null:
		_check("practice: a computer pilot was found", false)
		return
	pilot.hull_id = "fighter"
	var ship := p.launch(pilot)
	if ship == null:
		_check("practice: the computer pilot launches", false)
		return
	ship.global_position = d.position + Vector2(120.0, 0.0)
	ship.velocity = Vector2.ZERO
	p.registry.rebuild_hashes()
	for t in 2:
		p.vision.update_team(t, p._viewers(t))
		p.visibility.refresh(t)
	var brain: PilotAI = p.pilot_ai[pilot]
	var lane_pick: Unit = brain.targeting.pick_target(ship, 3000.0)
	_check("practice: a computer pilot in a lane never targets a drone", not (lane_pick is PracticeDrone), str(lane_pick))
	brain.state = "jungle"
	var jungle_pick: Unit = brain.targeting.pick_target(ship, 3000.0)
	brain.state = "lane"
	print("INFO a jungling computer pilot next to a drone picks: %s" % ("the drone" if jungle_pick is PracticeDrone else str(jungle_pick)))
	p.combat.kill_silently(ship)


## No seat of a practice match reads as "a pilot down" while nobody has been lost, and an
## empty seat never counts as one (an Admiral's field look at a team the range emptied).
func _check_pilots_down(w: World, others: String) -> void:
	var tag := "practice \"%s\":" % others
	for t in 2:
		var field := AdmiralField.new(w, t)
		_check("%s team %d reads no pilot as down at the start" % [tag, t], field.pilots_down() == 0, str(field.pilots_down()))
	# An empty seat: a profile that is neither the human's nor flown by a computer pilot. Even when it
	# reads "dead" it is not a pilot down.
	var stray := PilotProfile.new("Empty seat", Rules.enemy_of(w.human_team), 2, false)
	stray.state = "dead"
	w.profiles.append(stray)
	_check("%s an empty seat that reads dead is no pilot down" % tag, AdmiralField.new(w, Rules.enemy_of(w.human_team)).pilots_down() == 0)
	w.profiles.erase(stray)
	# A real pilot of the human's team who is dead does count (the rule itself is as it was).
	for p: PilotProfile in w.profiles:
		if p.team == w.human_team and p.role != "admiral" and (p.is_human or w.pilot_ai.has(p)):
			p.state = "dead"
			var down := AdmiralField.new(w, w.human_team).pilots_down()
			p.state = "docked"
			_check("%s a pilot who is really down still counts" % tag, down == 1, str(down))
			break
	# Both teams' computer Admirals, where there are any, read the same.
	for t in 2:
		if w.admiral_ai[t] != null:
			_check("%s the computer Admiral of team %d reads 0 pilots down" % [tag, t], (w.admiral_ai[t] as AdmiralAI).field.pilots_down() == 0)
