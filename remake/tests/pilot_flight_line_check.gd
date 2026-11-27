extends Node
## WHAT THIS IS: the check of how the computer pilots fly the ships of the line
## (corvettes, frigates, destroyers, battlecruisers; the ships with Ship.f_line):
## the look-ahead before a rock, the corner speed, and the group's pace, and
## that every other ship (and a build without the ships-of-the-line model) flies
## as it always did.
##
## HOW IT WORKS: it freezes the match, takes the rocks out of the field (and adds
## its own where a case needs one), launches ships with a computer pilot's brain
## on open ground inside the home base clearing, puts them at a place with a
## speed and heading, and calls the real flying functions by hand (PilotFlight's
## avoid_rocks() and travel()), then reads the controls. The cases:
##   - rock look-ahead: a Battlecruiser and a Destroyer with a rock inside their
##     stopping distance but beyond the 0.6 second look every ship has get the
##     rock's push and a brake command at once; the same ship with the model off,
##     and a Fighter, get none; a ship flying away from the rock gets no push; a
##     Fighter with a rock inside its 0.6 second look still brakes;
##   - the replan: a ship that cannot stop short of the rock goes back along its
##     trail once, not on every look, and again after the wait; with the model
##     off it never does; avoid_rocks() called with its default (as the fight and
##     the wingmen call it) never starts a replan, called as travel() calls it
##     (and from travel() itself) it still can; the fight's own travel() calls
##     (a big ship holding station, a strike craft's two hidden-target trips)
##     never start a replan;
##   - corners: a Destroyer takes a 90 degree corner slower than the same ship a
##     30 degree one (which has no limit), a Battlecruiser slower than a
##     Destroyer, a Support Corvette is held to nothing below its top speed, a
##     Fighter keeps its 28% cap, a ship of the line below its limit never
##     brakes, and the last leg still ends in the creep (_guide_line);
##   - the group: a Destroyer on a long trip beside a slower Battlecruiser of its
##     own team is held to the Battlecruiser's pace (1.1 times its top speed);
##     alone, beside the enemy's ship, or 4,500 from the enemy hull it is not;
##     the Battlecruiser is never held;
##   - the Admiral's crews: a ship of the line flown by a yard crew (a crew
##     profile) gets no rock look-ahead, no replan, no corner limit and no group
##     hold, while the same ship with a computer pilot still gets all of them (each
##     case compares the crew ship with the pilot ship); and a slow crew
##     Battlecruiser is not a group mate: it does not hold a pilot Destroyer.
## It prints "pilot_flight_line_check: N failures" (0 means all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=pilot_flight_line_check
##
## WHO USES IT: main.gd loads it for --test=pilot_flight_line_check. It changes
## only units of a frozen match that is thrown away.

## How far from the home mothership's centre the test place is (world units):
## inside the base clearing, so every point near it counts as open lane.
const SPOT_OFFSET := 3800.0
## The radius of the rocks the cases add (world units).
const ROCK_R := 200.0
## Seconds added to the world's clock between the two rounds of the replan case:
## a little more than PilotFlight.LINE_REPLAN_GAP.
const REPLAN_WAIT_PLUS := 3.1

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## Whether the ships-of-the-line model was on when the check began (put back at the end).
var _model_was := true
## The test place: open ground inside the home base clearing.
var _spot := Vector2.ZERO
## The heading of the test (a unit vector): from the home mothership toward the enemy's.
var _dir := Vector2.RIGHT
## The ships made so far, so that they can be parked out of each other's way.
var _ships: Array[Ship] = []
## The random number maker the field's add function wants.
var _rng := Mulberry.new(1)


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Run every group of cases, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_model_was = Game.big_hull_flight
	_prepare()
	_check_rock_lookahead()
	_check_replan()
	_check_replan_source()
	_check_replan_in_fight()
	_check_corners()
	_check_last_leg()
	_check_group()
	_check_crew()
	Game.big_hull_flight = _model_was
	print("pilot_flight_line_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("pilot_flight_line_check: FAIL %s" % what)


## Take every rock out of the field, work out the test place and heading, and
## check the place is open lane.
func _prepare() -> void:
	_clear_rocks()
	var mp0: Vector2 = world.map.mothership_pos[0]
	var mp1: Vector2 = world.map.mothership_pos[1]
	_dir = (mp1 - mp0).normalized()
	_spot = mp0 + _dir * SPOT_OFFSET
	_expect(world.map.in_open_lane(_spot), "the test place is not open lane")
	_expect(world.map.in_open_lane(_spot + _dir * 1500.0), "the test place's far side is not open lane")


## Make every rock dead and the field's clear-space map forget them.
func _clear_rocks() -> void:
	world.asteroids.alive.fill(0)
	world.asteroids.queries.reset_clear()


## Add a rock of radius `r` at `at` (the field's own add function), and make the
## field's search part ready for it. Returns its number.
func _add_rock(at: Vector2, r: float) -> int:
	world.asteroids._add(at, r, false, _rng)
	world.asteroids.queries.make_room(world.asteroids.pos.size())
	world.asteroids.queries.reset_clear()
	return world.asteroids.pos.size() - 1


## Launch a pilot ship of hull `hid` for `team` with a computer pilot's brain.
func _make(hid: String, team: int) -> Ship:
	var p := PilotProfile.new("line-" + hid, team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	p.role = "mid"
	world.profiles.append(p)
	world.pilot_ai[p] = PilotAI.new(world, p)
	var s := world.launch(p)
	s.controller = null
	_ships.append(s)
	return s


## Launch a ship of hull `hid` for `team` flown by a yard crew: the same as
## _make(), then its profile is flagged as a crew's (as Crew.make does).
func _make_crew(hid: String, team: int) -> Ship:
	var s := _make(hid, team)
	s.profile.is_crew = true
	return s


## The brain that flies ship `s`.
func _brain(s: Ship) -> PilotAI:
	return world.pilot_ai[s.profile] as PilotAI


## The flying part of ship `s`'s brain.
func _flight(s: Ship) -> PilotFlight:
	return _brain(s).flight


## Switch the ships-of-the-line model on or off (as --big-hull-flight does).
func _set_model(on: bool) -> void:
	Game.big_hull_flight = on


## Put every ship made so far in its own far corner, out of everyone's way.
func _park_all() -> void:
	var k := 0
	for s in _ships:
		s.global_position = Vector2(300.0 + 1800.0 * float(k), 300.0)
		s.velocity = Vector2.ZERO
		k += 1
	world.registry.rebuild_hashes()


## Put ship `s` at `at`, nose along the test heading, flying `speed` that way,
## with the model as it is now, its brain's state cleared and its controls set to
## full ahead with the nose straight on.
func _place(s: Ship, at: Vector2, speed: float) -> void:
	s.global_position = at
	s.rotation = _dir.angle()
	s.velocity = _dir * speed
	s.recompute_stats(true)
	var c := s.controls
	c.forward = 1.0
	c.strafe = 0.0
	c.boost = false
	c.face_point = at + _dir * 400.0
	c.aim_point = c.face_point
	var brain := _brain(s)
	brain.path = PackedVector2Array()
	brain.path_i = 0
	brain.path_goal = Vector2.INF
	brain.goal = at + _dir * 8000.0
	var f := brain.flight
	f.reset_progress()
	f._rock_t = 0
	f._rock_push = Vector2.ZERO
	f._line_replan_at = -999.0
	f._group_t = 0
	f._group_cap = INF
	f._unstick_t = 0.0
	f._line_t = 0


## The rock look-ahead: the cases are described in the file's header.
func _check_rock_lookahead() -> void:
	for hid: String in ["battlecruiser", "destroyer"]:
		var s := _make(hid, 0)
		var f := _flight(s)
		var seen := 0
		for frac: float in [0.6, 1.0]:
			_set_model(true)
			_place(s, _spot, frac * s.f_max)
			var v := s.velocity.length()
			var stop := f.line_stop_distance(s)
			# The nearest a rock edge can be and still lie beyond the 0.6 second
			# look (with the ship's size and the 30 unit margin).
			var lo := v * 0.6 + s.radius + 30.0 + 5.0
			var label := "%s at %.0f%% of top speed" % [hid, frac * 100.0]
			print("pilot_flight_line_check: %s speed %.1f stop %.1f, a rock edge between %.1f and %.1f is beyond the 0.6 s look and inside the stop" % [label, v, stop, lo, stop])
			if stop - lo < 15.0:
				_expect(frac < 1.0, "%s has no gap between the 0.6 second look and its stop (%.1f to %.1f)" % [label, lo, stop])
				continue
			seen += 1
			var gap := lo + (stop - lo) * 0.5
			_clear_rocks()
			_add_rock(_spot + _dir * (gap + ROCK_R), ROCK_R)
			# The ship of the line: pushed and braking at once.
			f.avoid_rocks(s)
			_expect(f._rock_push.length() > 1.0, "%s: no push from a rock %.0f ahead" % [label, gap])
			_expect(s.controls.forward <= -0.3, "%s: forward %.2f, wanted a brake, with a rock %.0f ahead" % [label, s.controls.forward, gap])
			# The same ship with the model off: nothing yet (the base look).
			_set_model(false)
			_place(s, _spot, frac * s.f_max)
			var before := s.controls.face_point
			f.avoid_rocks(s)
			_expect(f._rock_push.length() <= 1.0, "%s: pushed by a rock %.0f ahead with the model off" % [label, gap])
			_expect(s.controls.forward == 1.0 and s.controls.face_point == before, "%s: controls changed with the model off" % label)
			_set_model(true)
			# Flying away from the rock: no push.
			_place(s, _spot, frac * s.f_max)
			s.rotation = (-_dir).angle()
			s.velocity = -_dir * v
			s.controls.face_point = _spot - _dir * 400.0
			var before_away := s.controls.face_point
			f.avoid_rocks(s)
			_expect(f._rock_push.length() <= 1.0, "%s: pushed by a rock behind it" % label)
			_expect(s.controls.forward == 1.0 and s.controls.face_point == before_away, "%s: controls changed flying away" % label)
		_expect(seen > 0, "%s: no speed gave a case" % hid)
		_clear_rocks()
	# A Fighter has no f_line: a rock beyond its 0.6 second look changes nothing,
	# a rock inside it still pushes and brakes as it always did.
	var fighter := _make("fighter", 0)
	var ff := _flight(fighter)
	_set_model(true)
	_expect(not fighter.f_line, "a Fighter has f_line")
	_place(fighter, _spot, 300.0)
	_clear_rocks()
	_add_rock(_spot + _dir * (300.0 * 0.6 + fighter.radius + 30.0 + 80.0 + ROCK_R), ROCK_R)
	var face0 := fighter.controls.face_point
	ff.avoid_rocks(fighter)
	_expect(ff._rock_push == Vector2.ZERO and fighter.controls.forward == 1.0 and fighter.controls.strafe == 0.0 and fighter.controls.face_point == face0, "a Fighter's controls changed for a rock beyond its 0.6 second look")
	_place(fighter, _spot, 300.0)
	_clear_rocks()
	_add_rock(_spot + _dir * (300.0 * 0.6 + 10.0 + ROCK_R), ROCK_R)
	ff.avoid_rocks(fighter)
	_expect(ff._rock_push.length() > 1.0 and fighter.controls.forward <= -0.3, "a Fighter did not push and brake for a rock inside its 0.6 second look (forward %.2f)" % fighter.controls.forward)
	_clear_rocks()


## The replan: a ship of the line heading into a rock it cannot stop short of
## goes back along its trail once, and again only after LINE_REPLAN_GAP seconds.
func _check_replan() -> void:
	_park_all()
	var s := _make("battlecruiser", 0)
	var brain := _brain(s)
	var f := brain.flight
	for model: bool in [true, false]:
		_set_model(model)
		_place(s, _spot, s.f_max)
		var stop := f.line_stop_distance(s)
		var lo := s.velocity.length() * 0.6 + s.radius + 30.0 + 5.0
		var gap := lo + (stop - lo) * 0.5
		_clear_rocks()
		_add_rock(_spot + _dir * (gap + ROCK_R), ROCK_R)
		var far := _spot + _dir * 3000.0
		var replans := 0
		world.time = 100.0
		# Two rounds of 12 looks (the rock search runs on every 5th call) with the
		# route given back before each call.
		for rnd in 2:
			for _i in 12:
				brain.path = PackedVector2Array([far])
				brain.path_goal = far
				brain.goal = far
				var last := f._line_replan_at
				f.avoid_rocks(s, true)
				# The second stall in one place plans an escape path instead of
				# emptying the route, so the look's own note of the time is the proof.
				if f._line_replan_at != last:
					replans += 1
					_expect(brain.path.is_empty() or brain.path != PackedVector2Array([far]), "a replan left the route as it was")
			world.time += REPLAN_WAIT_PLUS
		var want := 2 if model else 0
		_expect(replans == want, "battlecruiser with the model %s: %d replans in 2 rounds of 12 looks, wanted %d" % ["on" if model else "off", replans, want])
	_set_model(true)
	_clear_rocks()


## The replan only from travel: avoid_rocks() called as the fight and the
## wingmen call it (the default) never goes back along the trail, called with
## `may_replan` true it does, and travel() makes that call.
func _check_replan_source() -> void:
	_park_all()
	_set_model(true)
	var s := _make("battlecruiser", 0)
	var brain := _brain(s)
	var f := brain.flight
	var far := _spot + _dir * 3000.0
	var counts := [0, 0, 0]
	for mode in 3:
		_place(s, _spot, s.f_max)
		var stop := f.line_stop_distance(s)
		var lo := s.velocity.length() * 0.6 + s.radius + 30.0 + 5.0
		var gap := lo + (stop - lo) * 0.5
		_clear_rocks()
		_add_rock(_spot + _dir * (gap + ROCK_R), ROCK_R)
		world.time = 100.0
		for _i in 12:
			brain.path = PackedVector2Array([far])
			brain.path_i = 0
			brain.path_goal = far
			brain.goal = far
			var last := f._line_replan_at
			if mode == 0:
				f.avoid_rocks(s)
			elif mode == 1:
				f.avoid_rocks(s, true)
			else:
				f.travel(s, far, 200.0)
			if f._line_replan_at != last:
				counts[mode] += 1
	print("pilot_flight_line_check: replans in 12 looks: %d by default, %d with may_replan, %d from travel()" % [counts[0], counts[1], counts[2]])
	_expect(counts[0] == 0, "avoid_rocks() called with the default started %d replans" % counts[0])
	_expect(counts[1] == 1, "avoid_rocks() called from travel's side (may_replan) made %d replans, wanted 1" % counts[1])
	_expect(counts[2] == 1, "travel() made %d replans, wanted 1" % counts[2])
	_clear_rocks()


## The replan never from the fight: PilotCombat.fight() makes three travel()
## calls, a big ship holding station (case "hold") and a strike craft's two trips
## round a rock when its target is hidden (case "hidden over 3 s", a target hidden
## for over 3 seconds, and case "hidden far", hidden and farther than
## HIDDEN_CLOSE). Each case puts a ship at top speed with a rock inside its
## stopping distance and beyond the 0.6 second look, an enemy ship beyond the
## rock, and calls fight() 12 times: none may start a replan. The same placement
## with travel() called by hand must still start exactly one (so the 0 is not a
## rock that never bites). The strike craft is a Fighter with f_line forced on:
## no strike craft is a ship of the line today, so the case guards a future one.
func _check_replan_in_fight() -> void:
	_park_all()
	_set_model(true)
	for kind: String in ["hold", "hidden over 3 s", "hidden far"]:
		var hold := kind == "hold"
		var s := _make("battlecruiser" if hold else "fighter", 0)
		var enemy := _make("destroyer", 1)
		var brain := _brain(s)
		var f := brain.flight
		var far := _spot + _dir * 3000.0
		var results := [0, 0]
		for mode in 2:
			_place(s, _spot, s.f_max)
			s.f_line = true
			var stop := f.line_stop_distance(s)
			var lo := s.velocity.length() * 0.6 + s.radius + 30.0 + 5.0
			var gap := lo + (stop - lo) * 0.5
			var target_at := _spot + _dir * (gap + 2.0 * ROCK_R + 300.0)
			if mode == 0:
				print("pilot_flight_line_check: %s setup: stop %.0f, lo %.0f, rock at %.0f, target at %.0f" % [kind, stop, lo, gap + ROCK_R, target_at.distance_to(_spot)])
			_clear_rocks()
			_add_rock(_spot + _dir * (gap + ROCK_R), ROCK_R)
			enemy.global_position = target_at
			enemy.velocity = Vector2.ZERO
			world.registry.rebuild_hashes()
			world.time = 100.0
			if hold:
				brain.intent = "push"
			for _i in 12:
				brain.path = PackedVector2Array([far])
				brain.path_i = 0
				brain.path_goal = far
				brain.goal = far
				brain.target = enemy
				f.hidden_t = 3.5 if kind == "hidden over 3 s" else 0.0
				var last := f._line_replan_at
				if mode == 0:
					brain.combat.fight(s)
				else:
					f.travel(s, far, 200.0)
				if f._line_replan_at != last:
					results[mode] += 1
		print("pilot_flight_line_check: replans in 12 looks, %s: %d" % [kind, results[0]])
		print("pilot_flight_line_check: setup control, travel() by hand, %s: %d" % [kind, results[1]])
		_expect(results[0] == 0, "fight() (%s) started %d replans in 12 looks, wanted 0" % [kind, results[0]])
		_expect(results[1] == 1, "setup control (%s): travel() by hand made %d replans, wanted 1" % [kind, results[1]])
		_park_all()
	_clear_rocks()


## Put `s` at distance `d` before the corner point W along the test heading,
## flying `speed` toward it, with the route (W, then a point `leg_out` away at
## `turn` radians from the heading, then a far goal), and call travel() once.
## Returns the ship's forward command.
func _corner_forward(s: Ship, d: float, leg_out: float, turn: float, speed: float) -> float:
	_park_all()
	_place(s, _spot, speed)
	var corner := _spot + _dir * d
	var after := corner + _dir.rotated(turn) * leg_out
	var goal := after + _dir.rotated(turn) * 3000.0
	var brain := _brain(s)
	brain.path = PackedVector2Array([corner, after, goal])
	brain.path_i = 0
	brain.path_goal = goal
	brain.goal = goal
	_flight(s).travel(s, goal, 200.0)
	return s.controls.forward


## The corner speed: the cases are described in the file's header.
func _check_corners() -> void:
	_clear_rocks()
	_set_model(true)
	var bc := _make("battlecruiser", 0)
	var de := _make("destroyer", 0)
	var su := _make("support", 0)
	var fi := _make("fighter", 0)
	for s in [bc, de, su, fi]:
		_place(s, _spot, 0.0)
	var f := _flight(de)
	var cap_d := f.line_corner_cap(de, 900.0, 900.0)
	var cap_b := f.line_corner_cap(bc, 900.0, 900.0)
	var cap_s := f.line_corner_cap(su, 900.0, 900.0)
	print("pilot_flight_line_check: corner caps with 900 legs: Battlecruiser %.1f Destroyer %.1f Support %.1f (top speeds %.1f %.1f %.1f)" % [cap_b, cap_d, cap_s, bc.f_max, de.f_max, su.f_max])
	_expect(cap_b < cap_d, "the Battlecruiser's corner cap %.1f is not below the Destroyer's %.1f" % [cap_b, cap_d])
	_expect(cap_d < de.f_max, "the Destroyer's corner cap %.1f is not below its top speed %.1f" % [cap_d, de.f_max])
	_expect(cap_b >= PilotFlight.LINE_CORNER_MIN and cap_d >= PilotFlight.LINE_CORNER_MIN, "a corner cap is below the floor")
	_expect(is_equal_approx(cap_s, su.f_max), "the Support Corvette's corner cap %.1f is not its top speed %.1f" % [cap_s, su.f_max])
	_expect(f.line_corner_cap(de, 5000.0, 5000.0) <= de.f_max and is_equal_approx(f.line_corner_cap(de, 5000.0, 5000.0), minf(de.f_max, PilotFlight.LINE_CORNER_R_MAX * de.f_turn * (1.0 - de.f_bleed))), "a long leg made the cap bigger than the radius limit allows")
	_expect(is_equal_approx(f.line_corner_cap(de, 20.0, 20.0), PilotFlight.LINE_CORNER_MIN), "a tiny corner is not held to the floor speed")
	# The Destroyer near a 90 degree corner, close to its limit: it brakes; at the
	# same place before a 30 degree corner (no limit) it does not.
	var d := 560.0
	var v := 0.97 * de.f_max
	var f90 := _corner_forward(de, d, 900.0, PI * 0.5, v)
	var f30 := _corner_forward(de, d, 900.0, PI / 6.0, v)
	print("pilot_flight_line_check: Destroyer at %.0f from the corner, speed %.1f: forward %.2f (90 degrees), %.2f (30 degrees)" % [d, v, f90, f30])
	_expect(f90 < 0.0, "the Destroyer did not brake for a 90 degree corner (forward %.2f)" % f90)
	_expect(f30 >= 0.0, "the Destroyer braked for a 30 degree corner (forward %.2f)" % f30)
	# Below the limit it never gets a negative forward at a mid-route corner.
	var slow := _corner_forward(de, d, 900.0, PI * 0.5, 0.5 * cap_d)
	_expect(slow >= 0.0, "the Destroyer below its corner limit got forward %.2f" % slow)
	# The Support Corvette has no limit below its top speed: no brake at 97% of it.
	var fs := _corner_forward(su, 560.0, 900.0, PI * 0.5, 0.97 * su.f_max)
	_expect(fs >= 0.0, "the Support Corvette braked for a corner at 97%% of its top speed (forward %.2f)" % fs)
	# A Fighter keeps today's cap (28% of top speed, never below 120): -0.8 above
	# 1.3 times it, none below it.
	var fcap := maxf(120.0, fi.f_max * 0.28)
	var ff := _corner_forward(fi, 560.0, 900.0, PI * 0.5, 0.97 * fi.f_max)
	_expect(ff == -0.8, "the Fighter's forward at 97%% of top speed before a corner was %.2f, wanted -0.8" % ff)
	var fg := _corner_forward(fi, 560.0, 900.0, PI * 0.5, 0.9 * fcap)
	_expect(fg >= 0.0, "the Fighter below its 28%% cap got forward %.2f" % fg)
	# With the model off the Destroyer is no ship of the line: today's 28% cap.
	_set_model(false)
	var foff := _corner_forward(de, 560.0, 900.0, PI * 0.5, 0.97 * de.f_max)
	_expect(not de.f_line, "the Destroyer is a ship of the line with the model off")
	var fcap_de := maxf(120.0, de.f_max * 0.28)
	_expect(0.97 * de.f_max > fcap_de * 1.3, "test setup: the Destroyer's speed is not above 1.3 times its old cap")
	print("pilot_flight_line_check: Destroyer with the model off: forward %.2f" % foff)
	_set_model(true)


## The last leg still ends in the creep: a ship of the line far too fast for
## the stop brakes, and one that is slow with room to go pushes on.
func _check_last_leg() -> void:
	_park_all()
	var s := _make("destroyer", 0)
	var f := _flight(s)
	_place(s, _spot, 0.9 * s.f_max)
	var goal := _spot + _dir * 300.0
	_brain(s).goal = goal
	f.travel(s, goal, 100.0)
	_expect(s.controls.forward < 0.0, "the Destroyer 300 from its goal at 90%% of top speed did not brake (forward %.2f)" % s.controls.forward)
	_place(s, _spot, 20.0)
	goal = _spot + _dir * 1500.0
	_brain(s).goal = goal
	f.travel(s, goal, 100.0)
	_expect(s.controls.forward > 0.0, "the Destroyer 1500 from its goal at 20 units a second did not push on (forward %.2f)" % s.controls.forward)


## Put every ship made so far out of the way, then the cases of the group's pace:
## a Destroyer (D) and a Battlecruiser (B) of team 0, a Battlecruiser (E) of team 1.
func _check_group() -> void:
	_set_model(true)
	_clear_rocks()
	var bc := _make("battlecruiser", 0)
	var de := _make("destroyer", 0)
	var fl := _make("flak", 0)
	var enemy := _make("battlecruiser", 1)
	_park_all()
	var cap := PilotFlight.LINE_GROUP_FACTOR * bc.f_max
	var v_de := cap + 0.5
	var v_bc := bc.f_max - 10.0
	# Each mate is [ship, its signed speed along the heading, how far ahead of the
	# ship under test it is along the heading]: -150 is 150 behind it.
	var bc_behind := [[bc, v_bc, -150.0]]
	# The Destroyer, ahead of the slower Battlecruiser, is held to its pace while
	# both travel...
	var alone := _group_forward(de, v_de, [])
	_expect(alone > 0.0, "test setup: the Destroyer alone is not pushing on (forward %.2f)" % alone)
	var with_b := _group_forward(de, v_de, bc_behind)
	print("pilot_flight_line_check: Destroyer at %.1f (limit %.1f): forward %.2f alone, %.2f beside the Battlecruiser" % [v_de, cap, alone, with_b])
	_expect(with_b <= 0.0, "the Destroyer was not held beside the slower Battlecruiser (forward %.2f)" % with_b)
	# ... a Destroyer behind the Battlecruiser is not held (it is not ahead) ...
	var behind := _group_forward(de, v_de, [[bc, v_bc, 150.0]])
	_expect(behind > 0.0, "the Destroyer behind the Battlecruiser was held (forward %.2f)" % behind)
	# ... the Battlecruiser is never held ...
	var b_alone := _group_forward(bc, v_bc, [])
	var b_with := _group_forward(bc, v_bc, [[de, v_de, -150.0]])
	_expect(b_alone > 0.0 and b_with == b_alone, "the Battlecruiser was held or changed beside the Destroyer (forward %.2f alone, %.2f beside)" % [b_alone, b_with])
	# ... a Flak Frigate (faster still) is held to the Battlecruiser's pace too ...
	var fl_with := _group_forward(fl, 200.0, bc_behind)
	var fl_alone := _group_forward(fl, 200.0, [])
	_expect(fl_alone > 0.0 and fl_with <= 0.0, "the Flak Frigate was not held beside the Battlecruiser (forward %.2f alone, %.2f beside)" % [fl_alone, fl_with])
	# ... a ship of the other team does not count ...
	var with_e := _group_forward(de, v_de, [[enemy, v_bc, -150.0]])
	_expect(with_e > 0.0, "the Destroyer was held by an enemy Battlecruiser (forward %.2f)" % with_e)
	# ... a ship going the other way does not count ...
	var other_way := _group_forward(de, v_de, [[bc, -v_bc, -150.0]])
	_expect(other_way > 0.0, "the Destroyer was held by a Battlecruiser flying the other way (forward %.2f)" % other_way)
	# ... a ship on a short trip is not held ...
	var short := _group_forward(de, v_de, bc_behind, 2000.0)
	_expect(short > 0.0, "the Destroyer on a short trip was held (forward %.2f)" % short)
	# ... and 4,500 from the enemy hull it is free, farther off it is held.
	var ems := world.mothership(1)
	var away: Vector2 = (world.map.mothership_pos[0] - world.map.mothership_pos[1]).normalized()
	var held_far := _group_forward_at(de, v_de, bc_behind, _point_at_hull_dist(ems, away, 4700.0), away)
	var free_near := _group_forward_at(de, v_de, bc_behind, _point_at_hull_dist(ems, away, 4300.0), away)
	print("pilot_flight_line_check: Destroyer beside the Battlecruiser, 4700 from the enemy hull: forward %.2f; 4300 from it: %.2f" % [held_far, free_near])
	_expect(held_far <= 0.0, "the Destroyer 4700 from the enemy hull was not held (forward %.2f)" % held_far)
	_expect(free_near > 0.0, "the Destroyer 4300 from the enemy hull was held (forward %.2f)" % free_near)
	# The model off: no ship of the line, nobody is held.
	_set_model(false)
	var off := _group_forward(de, v_de, bc_behind)
	_expect(not de.f_line, "test setup: the Destroyer is a ship of the line with the model off")
	print("pilot_flight_line_check: with the model off the Destroyer's forward is %.2f" % off)
	_set_model(true)


## The Admiral's crews: a ship of the line flown by a yard crew gets none of the
## rules (the cases are described in the file's header), the same hull with a
## computer pilot's brain gets all of them.
func _check_crew() -> void:
	_set_model(true)
	_clear_rocks()
	var bc_pilot := _make("battlecruiser", 0)
	var bc_crew := _make_crew("battlecruiser", 0)
	var de_pilot := _make("destroyer", 0)
	var de_crew := _make_crew("destroyer", 0)
	_park_all()
	_expect(Squads.is_crew(bc_crew.profile) and Squads.is_crew(de_crew.profile) and not Squads.is_crew(bc_pilot.profile) and not Squads.is_crew(de_pilot.profile), "test setup: the crew ships are not told from the pilot ships")
	_expect(bc_crew.f_line and de_crew.f_line, "test setup: a crew ship is not a ship of the line")
	# The rock look-ahead and the replan.
	for pair: Array in [[bc_pilot, bc_crew], [de_pilot, de_crew]]:
		var pil: Ship = pair[0]
		var cre: Ship = pair[1]
		var rp := _rock_probe(pil)
		var rc := _rock_probe(cre)
		print("pilot_flight_line_check: %s with a rock inside its stop: pilot push %.1f forward %.2f replans %d, crew push %.1f forward %.2f replans %d" % [pil.hull_id, rp["push"], rp["forward"], rp["replans"], rc["push"], rc["forward"], rc["replans"]])
		_expect(float(rp["push"]) > 1.0 and float(rp["forward"]) <= -0.3 and int(rp["replans"]) >= 1, "%s with a computer pilot did not get the look-ahead and the replan" % pil.hull_id)
		_expect(float(rc["push"]) <= 1.0 and float(rc["forward"]) == 1.0 and int(rc["replans"]) == 0, "%s flown by a crew got the look-ahead or the replan (push %.1f, forward %.2f, replans %d)" % [cre.hull_id, rc["push"], rc["forward"], rc["replans"]])
	# The corner speed: a Destroyer before a 90 degree corner, over a range of
	# distances and speeds. The old share of top speed (120 at least) is looser than
	# the ship-of-the-line limit for this corner, so the crew ship must never brake
	# harder than the pilot ship, and must brake less at some place and speed
	# (where the line limit makes the pilot ship brake).
	var looser := 0
	var tighter := 0
	for d: float in [300.0, 450.0, 560.0, 800.0]:
		for share: float in [0.5, 0.6, 0.7, 0.8, 0.9, 0.97]:
			var pilot_fwd := _corner_forward(de_pilot, d, 900.0, PI * 0.5, share * de_pilot.f_max)
			var crew_fwd := _corner_forward(de_crew, d, 900.0, PI * 0.5, share * de_crew.f_max)
			if crew_fwd > pilot_fwd + 0.01:
				looser += 1
			elif crew_fwd < pilot_fwd - 0.01:
				tighter += 1
				_expect(false, "the Destroyer flown by a crew braked harder than the one with a pilot at %.0f from a corner, %.0f%% of top speed (%.2f against %.2f)" % [d, share * 100.0, crew_fwd, pilot_fwd])
	print("pilot_flight_line_check: Destroyer before a 90 degree corner, 24 places and speeds: the crew ship brakes less than the pilot ship at %d, harder at %d" % [looser, tighter])
	_expect(looser > 0, "the Destroyer flown by a crew braked like the one with a pilot at every place: it still gets the corner limit")
	# The group's pace: a Destroyer ahead of a slower Battlecruiser is held with a
	# computer pilot and not held flown by a crew.
	var cap := PilotFlight.LINE_GROUP_FACTOR * bc_pilot.f_max
	var v_de := cap + 0.5
	var mates := [[bc_pilot, bc_pilot.f_max - 10.0, -150.0]]
	var held := _group_forward(de_pilot, v_de, mates)
	var crew_group := _group_forward(de_crew, v_de, mates)
	print("pilot_flight_line_check: Destroyer beside the Battlecruiser: forward %.2f with a pilot, %.2f flown by a crew" % [held, crew_group])
	_expect(held <= 0.0, "test setup: the Destroyer with a computer pilot was not held (forward %.2f)" % held)
	_expect(crew_group > 0.0, "the Destroyer flown by a crew was held beside the Battlecruiser (forward %.2f)" % crew_group)
	# The crews are not group mates: a pilot Destroyer ahead of a slower crew
	# Battlecruiser heading the same way is not held to the crew ship's pace.
	var crew_mate := [[bc_crew, bc_crew.f_max - 10.0, -150.0]]
	var mate_held := _group_forward(de_pilot, v_de, crew_mate)
	print("pilot_flight_line_check: pilot Destroyer beside a crew Battlecruiser: forward %.2f" % mate_held)
	_expect(mate_held > 0.0, "the pilot Destroyer was held to the pace of a crew Battlecruiser (forward %.2f)" % mate_held)
	_set_model(true)
	_clear_rocks()


## Put ship `s` (model on) at a speed where a rock between its 0.6 second look
## and its stop distance can be placed, with the rock there, then make 12 rock
## looks with a route on its brain. Returns the push and forward found by the
## first look and the number of replans (stalls) the 12 looks made.
func _rock_probe(s: Ship) -> Dictionary:
	_set_model(true)
	var f := _flight(s)
	var brain := _brain(s)
	_park_all()
	_place(s, _spot, s.f_max)
	var stop := f.line_stop_distance(s)
	var lo := s.velocity.length() * 0.6 + s.radius + 30.0 + 5.0
	if stop - lo < 15.0:
		_place(s, _spot, 0.6 * s.f_max)
		stop = f.line_stop_distance(s)
		lo = s.velocity.length() * 0.6 + s.radius + 30.0 + 5.0
	_expect(stop - lo >= 15.0, "%s has no gap between the 0.6 second look and its stop" % s.hull_id)
	_clear_rocks()
	_add_rock(_spot + _dir * (lo + (stop - lo) * 0.5 + ROCK_R), ROCK_R)
	var far := _spot + _dir * 3000.0
	world.time = 100.0
	var out := {"push": 0.0, "forward": 1.0, "replans": 0}
	for i in 12:
		brain.path = PackedVector2Array([far])
		brain.path_goal = far
		brain.goal = far
		var last := f._line_replan_at
		f.avoid_rocks(s, true)
		if i == 0:
			out["push"] = f._rock_push.length()
			out["forward"] = s.controls.forward
		if f._line_replan_at != last:
			out["replans"] = int(out["replans"]) + 1
	_clear_rocks()
	return out


## A point on the line from the enemy mothership `ems` out along `away` whose hull
## distance is `want` world units.
func _point_at_hull_dist(ems: Mothership, away: Vector2, want: float) -> Vector2:
	var at := ems.global_position + away * (want + 1000.0)
	for _i in 6:
		at += away * (want - ems.hull_dist(at))
	return at


## `_group_forward_at()` at the test place and heading.
func _group_forward(s: Ship, speed: float, mates: Array, trip := 8000.0) -> float:
	return _group_forward_at(s, speed, mates, _spot, _dir, trip)


## Put ship `s` at `at`, flying `speed` along `heading`, with its goal `trip`
## world units ahead on a one-point route, and each of `mates` (a list of
## [ship, speed, how far ahead of `s` along the heading]) beside it; then call
## travel() once and return the forward command.
func _group_forward_at(s: Ship, speed: float, mates: Array, at: Vector2, heading: Vector2, trip := 8000.0) -> float:
	_park_all()
	var saved := _dir
	_dir = heading
	_place(s, at, speed)
	for m: Array in mates:
		var o: Ship = m[0]
		var sp := float(m[1])
		_place(o, at + heading * float(m[2]), absf(sp))
		o.velocity = heading * sp
	world.registry.rebuild_hashes()
	var goal := at + heading * trip
	var brain := _brain(s)
	brain.path = PackedVector2Array([goal])
	brain.path_i = 0
	brain.path_goal = goal
	brain.goal = goal
	_flight(s).travel(s, goal, 200.0)
	_dir = saved
	return s.controls.forward
