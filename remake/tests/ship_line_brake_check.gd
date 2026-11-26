extends Node
## WHAT THIS IS: the check of the split brake and the swivel dead band of the
## ships of the line (ShipLineFlight): the new `brake_split` number of each
## hull's "line" entry reaches the ship, and (in the later groups) the engines
## toe out when the ship brakes, stop straight and as hard as the AI plans, and
## do not flicker from side to side when the nose settles.
##
## HOW IT WORKS: it freezes the match and launches ships with a flight table
## probe made as main.gd makes it (without calling its setup, which would print
## and quit), then flies the real flight function through the probe's own
## measures, tick after tick, with nobody at the controls. Nothing is copied
## from the flight code. No random numbers are used.
##   fields   every hull with a "line" entry has a `brake_split` above 0 and
##            under a half turn, and a launched ship carries it in
##            Ship.f_brake_split; a hull with no line entry carries 0; with the
##            ships-of-the-line flight off a line hull carries 0 too.
##   flips    the dead band and hysteresis on the engines' side: each line hull
##            flies five scenarios (a 90 and a 180 degree turn, a 3 degree
##            correction, the face point swung 20 degrees left and right every
##            half second, and the nose chasing a slowly moving point) for 20 s,
##            from a stop and at cruise speed; a "flip" is the engines going
##            over from one side to the other. At most two flips in a turn, none
##            (and no swing past 0.3 radians) in the 3 degree correction, and in
##            every scenario no more than the same scenario flew before the dead
##            band. A turn more than 15% slower than before prints a BAR MISS.
##   brake    each line hull brakes from top speed with the nose ahead: the nose
##            stays within half a degree and the ship slides no farther than it
##            did before the split brake; stop time against the time to 95% of
##            top speed (printed as a BAR MISS outside 1.2 to 1.7 times); the
##            push after the engines have opened is the push the AI plans with
##            (Ship.f_brake); the engines move no faster than their swivel
##            rate and close again after S is let go; a brake split of 0 flies
##            the old stop to the tick; a strike craft never toes out; a brake
##            tapped on and off keeps the engines inside their range. Also
##            printed (not asserted): the nose error four seconds after a turn
##            told while braking, with the split and without.
## It prints PASS and FAIL lines and then "ship_line_brake_check: N failures"
## (0 means all is as it should be). A hull outside an engineering bar prints a
## "BAR MISS" line with its numbers and does not fail.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=ship_line_brake_check
##
## WHO USES IT: main.gd loads it for --test=ship_line_brake_check. It changes
## only units of a frozen match that is thrown away.

## The step of the flight, in seconds (the probe's: 60 steps a second).
const DT := 1.0 / 60.0
## The nose may turn at most this many degrees over a whole straight brake.
const NOSE_DRIFT_DEG := 0.5
## The stop time over the time to 95% of top speed must lie between these two
## (the flight plan's bar: 20 to 70% longer).
const BAR_LOW := 1.2
## ...and this.
const BAR_HIGH := 1.7
## The push measured in the middle of a brake may differ from Ship.f_brake by this
## share at most.
const PUSH_TOLERANCE := 0.1
## The engines may move this much faster than their swivel rate between two
## ticks (a share: rounding).
const RATE_SLACK := 0.01
## How long (seconds) the engines may stay toed out beyond closing time after S is
## let go, on top of the hold time.
const CLOSE_SLACK := 0.1
## The tap test: S held this long (seconds)...
const TAP_ON := 0.2
## ...every this long, this many times.
const TAP_PERIOD := 0.4
## How many taps.
const TAP_COUNT := 10
## How far away (world units) the spot the nose is told to point at is put (the
## probe's value).
const FAR := 1000000.0
## Cruise speed, as a share of the top speed (the probe's value).
const CRUISE := 0.6

## What the same stop from top speed gave before the split brake, from the flight
## table probe on that code: hull id -> [top speed, seconds to stop, how far the
## ship slid off the line]. The old stop is flown again with the split put to 0.
const BEFORE_SPLIT := {
	"logistics": [351.566711425781, 1.90616712635309, 9.728515625],
	"support": [429.90087890625, 1.97223894242959, 13.09375],
	"flak": [250.923400878906, 2.8758791695228, 8.677734375],
	"ion": [261.262268066406, 2.80953509130063, 8.791015625],
	"destroyer": [175.373657226563, 3.79651201340464, 7.013671875],
	"battlecruiser": [150.815368652344, 4.45021693092638, 6.3701171875],
}

## The scenarios of the flip groups, in the order of the tables above them.
const SCENARIOS := ["turn90", "turn180", "correct3", "swing20", "chase"]
## How long (game seconds) each flip scenario runs.
const FLIP_SECS := 20.0
## The engines count as swung to a side from this many radians off straight ahead
## (a flip is a change of sign after that).
const FLIP_ARM := 0.3
## The most flips a 90 or a 180 degree turn may have: one to start it, one to stop
## the spin.
const TURN_FLIPS := 2
## A turn may be this share slower than it was before the dead band (a bar, not a
## failure).
const TURN_SLOWER := 0.15

## How many flips each scenario had before the dead band and the hysteresis, from
## the same scenarios flown on that code: hull id -> the five SCENARIOS from a stop,
## then the five at cruise speed.
const BEFORE_FLIPS := {
	"logistics": [1, 1, 0, 38, 0, 1, 1, 0, 38, 0],
	"support": [1, 1, 0, 38, 0, 1, 1, 0, 20, 0],
	"flak": [1, 1, 0, 11, 0, 1, 1, 0, 14, 0],
	"ion": [1, 1, 0, 9, 0, 1, 1, 0, 12, 0],
	"destroyer": [1, 1, 0, 0, 0, 1, 1, 0, 0, 0],
	"battlecruiser": [1, 1, 0, 0, 0, 1, 1, 0, 0, 0],
}
## How long (seconds) the turns took before the dead band, to within 2 degrees:
## hull id -> turn90 and turn180 from a stop, then both at cruise speed.
const BEFORE_TURNS := {
	"logistics": [1.267, 2.283, 1.317, 2.400],
	"support": [1.100, 1.933, 1.133, 2.000],
	"flak": [2.583, 4.667, 2.883, 5.100],
	"ion": [2.433, 4.350, 2.700, 4.717],
	"destroyer": [4.583, 8.217, 5.117, 8.883],
	"battlecruiser": [6.267, 11.333, 7.167, 12.600],
}

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## Where the probe's ships are measured: open ground between the lanes.
var _home := Vector2.ZERO
## The flight table probe whose own measures this check flies.
var _probe: Node


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Run every group of checks, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_probe = load("res://tests/flight_table_probe.gd").new()
	add_child(_probe)
	_probe.set("world", world)
	_probe.set("_home", _home)
	_check_fields()
	_check_brake()
	_check_flips()
	_check_taps()
	_check_turn_while_braking()
	_check_strike_craft()
	_probe.queue_free()
	print("ship_line_brake_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("ship_line_brake_check: FAIL %s" % what)


## The new number: in the table for each line hull, on the launched ship, 0 for
## a hull with no line entry and 0 for every hull with the model off.
func _check_fields() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		var s: Ship = _probe.call("_launch", hid)
		s.recompute_stats(true)
		if Handling.has_line(hid):
			var split := float(Handling.row(hid)["line"]["brake_split"])
			_expect(split > 0.0 and split < PI, "%s brake_split %.4f is not above 0 and under a half turn" % [hid, split])
			_expect(is_equal_approx(s.f_brake_split, split), "%s ship carries %.4f, the table has %.4f" % [hid, s.f_brake_split, split])
			print("ship_line_brake_check: PASS %s brake_split %.4f" % [hid, s.f_brake_split])
		else:
			_expect(s.f_brake_split == 0.0, "%s (no line entry) carries a brake_split of %.4f" % [hid, s.f_brake_split])
		_probe.call("_put", s)
	Game.big_hull_flight = false
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s: Ship = _probe.call("_launch", hid)
		s.recompute_stats(true)
		_expect(not s.f_line, "%s flies as a ship of the line with the model off" % hid)
		_expect(s.f_brake_split == 0.0, "%s carries a brake_split of %.4f with the model off" % [hid, s.f_brake_split])
		_probe.call("_put", s)
	Game.big_hull_flight = was


## The engines' two angles (radians from straight ahead) of ship `s`.
func _angles(s: Ship) -> Vector2:
	return Vector2(s.swivel + s.toe, s.swivel - s.toe)


## Brake ship `s` (put back at the start at `speed` along the nose) with S held
## for `hold` seconds (0 = until it has stopped) and the nose told to stay ahead,
## and record what happened: "t" the seconds to stop (-1 if it did not), "d" the
## distance, "slide" how far off the line it went, "turn" the most the nose
## turned (degrees), "speeds" the speed along the line each tick, "toe" and
## "angles" the engines each tick. `split` below 0 leaves the hull's own split;
## 0 or more is put on the ship after the reset.
func _brake_run(s: Ship, speed: float, split: float, hold: float, extra_secs: float) -> Dictionary:
	_probe.call("_reset", s, speed)
	if split >= 0.0:
		s.f_brake_split = split
	s.controls.forward = -1.0
	var out := {"t": -1.0, "d": 0.0, "slide": 0.0, "turn": 0.0, "speeds": PackedFloat32Array(), "toe": PackedFloat32Array(), "angles": PackedVector2Array(), "released": -1}
	var steps := int(60.0 / DT)
	var prev_x := _home.x
	var prev_v := speed
	var stopped := false
	var tail := 0
	for i in steps:
		if hold > 0.0 and float(i) * DT >= hold and s.controls.forward < 0.0:
			s.controls.forward = 0.0
			out["released"] = i
		_probe.call("_step", s)
		out["slide"] = maxf(float(out["slide"]), absf(s.global_position.y - _home.y))
		out["turn"] = maxf(float(out["turn"]), absf(rad_to_deg(Util.wrap_angle(s.rotation))))
		out["speeds"].append(s.velocity.x)
		out["toe"].append(s.toe)
		out["angles"].append(_angles(s))
		if not stopped and s.velocity.x <= 0.0:
			var frac := prev_v / (prev_v - s.velocity.x) if prev_v > s.velocity.x else 1.0
			out["t"] = (float(i) + frac) * DT
			out["d"] = prev_x - _home.x + (s.global_position.x - prev_x) * frac
			stopped = true
		prev_x = s.global_position.x
		prev_v = s.velocity.x
		if stopped or (hold > 0.0 and out["released"] >= 0 and s.toe == 0.0):
			tail += 1
			if tail > int(extra_secs / DT):
				break
	return out


## The largest value in `values`.
func _largest(values: PackedFloat32Array) -> float:
	var most := 0.0
	for v in values:
		most = maxf(most, v)
	return most


## Speed along the line at game second `t` of a recorded run (the nearest tick).
func _speed_at(run: Dictionary, t: float) -> float:
	var speeds: PackedFloat32Array = run["speeds"]
	return speeds[clampi(int(t / DT) - 1, 0, speeds.size() - 1)]


## The brake groups (a to g of the plan), one pass over the six line hulls.
func _check_brake() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s: Ship = _probe.call("_launch", hid)
		var acc: Dictionary = _probe.call("_accel_run", s)
		var top := float(acc["top"])
		var run := _brake_run(s, top, -1.0, 0.0, 0.0)
		var lag := s.f_brake_lag
		var stop_t := float(run["t"])
		# (a) the nose stays and the ship slides no more than before.
		_expect(float(run["turn"]) <= NOSE_DRIFT_DEG, "%s nose turned %.2f degrees in a straight stop, wanted %.1f at most" % [hid, float(run["turn"]), NOSE_DRIFT_DEG])
		_expect(float(run["slide"]) <= float(BEFORE_SPLIT[hid][2]) + 0.001, "%s slid %.2f in a straight stop, %.2f before the split brake" % [hid, float(run["slide"]), float(BEFORE_SPLIT[hid][2])])
		# (b) the bar: printed when missed.
		var ratio := stop_t / float(acc["t95"])
		print("ship_line_brake_check: %s stop %.2f s over t95 %.2f s = %.2f (%.0f units, slide %.2f, nose %.2f deg, before %.2f s)" % [hid, stop_t, float(acc["t95"]), ratio, float(run["d"]), float(run["slide"]), float(run["turn"]), float(BEFORE_SPLIT[hid][1])])
		if ratio < BAR_LOW or ratio > BAR_HIGH:
			print("ship_line_brake_check: BAR MISS %s stop %.2f s over t95 %.2f s is %.2f, the bar is %.1f to %.1f" % [hid, stop_t, float(acc["t95"]), ratio, BAR_LOW, BAR_HIGH])
		# (c) the push in the middle of the brake is the push the AI plans with.
		var t1 := lag + 0.25 * (stop_t - lag)
		var t2 := lag + 0.75 * (stop_t - lag)
		var push := (_speed_at(run, t1) - _speed_at(run, t2)) / (t2 - t1)
		_expect(absf(push - s.f_brake) <= PUSH_TOLERANCE * s.f_brake, "%s push in the middle of the brake %.1f, planned %.1f" % [hid, push, s.f_brake])
		print("ship_line_brake_check: %s mid-brake push %.1f, planned f_brake %.1f, lag %.2f s" % [hid, push, s.f_brake, lag])
		# (d) the two engines never move faster than their swivel rate, and close
		# again after S is let go.
		var rel := _brake_run(s, top, -1.0, lag + 0.3, 6.0)
		var rate := s.f_swivel_rate * DT * (1.0 + RATE_SLACK)
		var angles: PackedVector2Array = rel["angles"]
		var worst := 0.0
		for i in range(1, angles.size()):
			worst = maxf(worst, maxf(absf(angles[i].x - angles[i - 1].x), absf(angles[i].y - angles[i - 1].y)))
		_expect(worst <= rate, "%s an engine moved %.4f in one tick, the swivel rate allows %.4f" % [hid, worst, rate])
		var toes: PackedFloat32Array = rel["toe"]
		var released := int(rel["released"])
		_expect(released >= 0, "%s the brake was not let go in the release run" % hid)
		var closed := -1.0
		for i in range(maxi(released, 0), toes.size()):
			if toes[i] == 0.0:
				closed = float(i - released) * DT
				break
		var closing := ShipLineFlight.toe_target(s) / s.f_swivel_rate + ShipLineFlight.BRAKE_HOLD + CLOSE_SLACK
		_expect(closed >= 0.0 and closed <= closing, "%s the engines closed %.2f s after S was let go, wanted %.2f at most" % [hid, closed, closing])
		print("ship_line_brake_check: %s engines closed %.2f s after S let go (limit %.2f s), fastest engine %.4f per tick" % [hid, closed, closing, worst])
		# (e) a split of 0 flies the old stop to the tick.
		var old := _brake_run(s, top, 0.0, 0.0, 0.0)
		_expect(absf(float(old["t"]) - float(BEFORE_SPLIT[hid][1])) < 0.0001 and absf(top - float(BEFORE_SPLIT[hid][0])) < 0.0001, "%s a split of 0 stops in %.4f s, before the split brake it was %.4f" % [hid, float(old["t"]), float(BEFORE_SPLIT[hid][1])])
		_expect(_largest(old["toe"]) == 0.0, "%s the engines toed out with a split of 0" % hid)
		# the probe's own stop measure agrees with this check's run.
		var probe_stop: Dictionary = _probe.call("_stop_run", s, top)
		_expect(absf(float(probe_stop["t"]) - stop_t) < 0.0001, "%s the probe's stop %.4f differs from this check's %.4f" % [hid, float(probe_stop["t"]), stop_t])
		_probe.call("_put", s)
	Game.big_hull_flight = was


## (g) S tapped for 0.2 s every 0.4 s, ten times, from top speed: the engines
## stay inside their range and the gap never jumps by more than one tick of the
## swivel rate.
func _check_taps() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s: Ship = _probe.call("_launch", hid)
		var acc: Dictionary = _probe.call("_accel_run", s)
		_probe.call("_reset", s, float(acc["top"]))
		var target := ShipLineFlight.toe_target(s)
		var most := 0.0
		var jump := 0.0
		var range_ok := true
		var prev_toe := 0.0
		for i in int(float(TAP_COUNT) * TAP_PERIOD / DT):
			var phase := fmod(float(i) * DT, TAP_PERIOD)
			s.controls.forward = -1.0 if phase < TAP_ON else 0.0
			_probe.call("_step", s)
			most = maxf(most, s.toe)
			jump = maxf(jump, absf(s.toe - prev_toe))
			prev_toe = s.toe
			var a := _angles(s)
			if absf(a.x) > target + 0.0001 or absf(a.y) > target + 0.0001 or s.toe < 0.0 or s.toe > target + 0.0001:
				range_ok = false
		_expect(range_ok, "%s an engine left its range of 0 to %.3f while S was tapped" % [hid, target])
		_expect(jump <= s.f_swivel_rate * DT * (1.0 + RATE_SLACK), "%s the toe jumped %.4f in one tick while S was tapped" % [hid, jump])
		print("ship_line_brake_check: %s taps: toe at most %.3f of %.3f, biggest jump %.4f" % [hid, most, target, jump])
		_probe.call("_put", s)
	Game.big_hull_flight = was


## (h) Printed, not asserted: how far the nose is from a point 90 degrees away,
## four seconds after being told to face it while braking from cruise speed, with
## the split brake and with the split put to 0 (the old brake).
func _check_turn_while_braking() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s: Ship = _probe.call("_launch", hid)
		var errs := []
		for split in [-1.0, 0.0]:
			_probe.call("_reset", s, 0.0)
			if split >= 0.0:
				s.f_brake_split = split
			s.velocity = Vector2(CRUISE * s.f_max, 0.0)
			s.controls.forward = -1.0
			s.controls.face_point = _home + Vector2.from_angle(deg_to_rad(90.0)) * FAR
			for _i in int(4.0 / DT):
				_probe.call("_step", s)
			errs.append(absf(rad_to_deg(Util.ang_diff(s.rotation, deg_to_rad(90.0)))))
		print("ship_line_brake_check: %s nose error 4 s after a 90 degree turn told while braking from cruise: split brake %.1f deg, old brake %.1f deg" % [hid, errs[0], errs[1]])
		_probe.call("_put", s)
	Game.big_hull_flight = was


## (f) A strike craft (no ship-of-the-line flight) never toes out and brakes with
## its reverse thrusters alone.
func _check_strike_craft() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		if Handling.has_line(hid):
			continue
		var s: Ship = _probe.call("_launch", hid)
		var acc: Dictionary = _probe.call("_accel_run", s)
		var run := _brake_run(s, float(acc["top"]), -1.0, 0.0, 0.0)
		_expect(_largest(run["toe"]) == 0.0 and s.swivel == 0.0, "%s (no line flight) toed out or swivelled in a brake" % hid)
		_expect(s.f_brake == s.f_reverse and not s.f_line, "%s (no line flight) plans its brake with %.1f, its reverse push is %.1f" % [hid, s.f_brake, s.f_reverse])
		_probe.call("_put", s)
	Game.big_hull_flight = was

## Fly ship `s` through `scenario` for FLIP_SECS game seconds, from a stop or at
## cruise speed, with nobody braking and the engines at rest, and report: "flips"
## how many times the engines went over from one side to the other (a change of
## sign of Ship.swivel after it was FLIP_ARM or more away from straight ahead),
## "big" the largest the engine angle got (radians), "t_in" the seconds until the
## nose was within 2 degrees of a turn's heading (-1 for the other scenarios or
## if it never was).
func _flip_run(s: Ship, scenario: String, cruise: bool) -> Dictionary:
	_probe.call("_reset", s, 0.0)
	s.brake_t = 0.0
	if cruise:
		s.velocity = Vector2(CRUISE * s.f_max, 0.0)
	var flips := 0
	var armed := 0.0
	var big := 0.0
	var t_in := -1.0
	var turn_deg := 0.0
	for i in int(FLIP_SECS / DT):
		var t := float(i) * DT
		var deg := 0.0
		match scenario:
			"turn90":
				deg = 90.0
			"turn180":
				deg = 180.0
			"correct3":
				deg = 3.0
			"swing20":
				deg = 20.0 if fmod(t, 1.0) < 0.5 else -20.0
			"chase":
				deg = rad_to_deg(0.05 * t)
		if scenario == "turn90" or scenario == "turn180":
			turn_deg = deg
		s.controls.face_point = s.global_position + Vector2.from_angle(deg_to_rad(deg)) * FAR
		_probe.call("_step", s)
		var sw := s.swivel
		if armed != 0.0 and sw * armed < 0.0:
			flips += 1
			armed = 0.0
		if absf(sw) >= FLIP_ARM:
			armed = signf(sw)
		big = maxf(big, absf(sw))
		if turn_deg != 0.0 and t_in < 0.0 and float(_probe.call("_nose_err_deg", s, turn_deg)) <= 2.0:
			t_in = float(i + 1) * DT
	return {"flips": flips, "big": big, "t_in": t_in}


## The flip groups: every scenario for every line hull, from a stop and at cruise
## speed, against the counts and turn times from before the dead band.
func _check_flips() -> void:
	var was := Game.big_hull_flight
	Game.big_hull_flight = true
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s: Ship = _probe.call("_launch", hid)
		var turn_at := 0
		for cruise in [false, true]:
			for sc_index in SCENARIOS.size():
				var sc: String = SCENARIOS[sc_index]
				var r := _flip_run(s, sc, cruise)
				var flips := int(r["flips"])
				var before := int(BEFORE_FLIPS[hid][sc_index + (SCENARIOS.size() if cruise else 0)])
				var where := "%s %s %s" % [hid, sc, "at cruise" if cruise else "from a stop"]
				var line := "ship_line_brake_check: %s: %d flips (before %d), engines to %.2f rad" % [where, flips, before, float(r["big"])]
				_expect(flips <= before, "%s flipped %d times, %d before the dead band" % [where, flips, before])
				if sc == "turn90" or sc == "turn180":
					_expect(flips <= TURN_FLIPS, "%s flipped %d times, %d at most" % [where, flips, TURN_FLIPS])
					var was_t := float(BEFORE_TURNS[hid][turn_at])
					turn_at += 1
					line += ", within 2 degrees at %.2f s (before %.2f s)" % [float(r["t_in"]), was_t]
					if float(r["t_in"]) < 0.0 or float(r["t_in"]) > was_t * (1.0 + TURN_SLOWER):
						print("ship_line_brake_check: BAR MISS %s turn %.2f s, before %.2f s, the bar is %.0f%% slower at most" % [where, float(r["t_in"]), was_t, TURN_SLOWER * 100.0])
				if sc == "correct3":
					_expect(flips == 0 and float(r["big"]) < FLIP_ARM, "%s: %d flips, engines to %.2f rad in a 3 degree correction" % [where, flips, float(r["big"])])
				print(line)
		_probe.call("_put", s)
	Game.big_hull_flight = was