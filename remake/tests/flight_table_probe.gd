extends Node
## WHAT THIS IS: the flight table in numbers. A measuring tool that prints how
## every pilot hull flies: top speed, how long it takes to reach it, how long
## and how far it takes to stop from top speed, how long the nose takes to
## swing 90 and 180 degrees from a stop and at cruise speed, the width of the
## tightest circle at top speed, and how hard the side thrusters push. For the
## four big classes it also prints the engine swivel time end to end. It
## asserts nothing: its numbers are put side by side for two builds of the
## game.
##
## HOW IT WORKS: it freezes the match, launches one ship of each hull with
## nobody at the controls, and for each measure puts the ship at rest on open
## ground, fills in its controls (the same ShipControls form a pilot fills in)
## and calls the real flight function, ShipFlight.fly(), tick after tick, with
## the same step as a match (1/60 s), moving the ship by its velocity each
## tick. Nothing is copied from the flight code: whatever it does to the
## velocity and the nose is what gets measured. No random numbers are used.
## Each measure is defined once, in its own function:
##   accel_run    full ahead from rest: the speed after 90 s (the top speed),
##                the seconds to 95% of it, and the distance flown by then.
##   stop_run     from top speed, brake (S held, nose ahead) until the speed
##                along the line reaches zero: seconds, distance, and how far
##                off the line the ship slid.
##   turn_run     the nose is told to point at a spot 90 or 180 degrees away:
##                seconds until it is within 2 degrees, the largest overshoot
##                after that, and the seconds until it stays within 2 degrees.
##                From a stop, or coasting at cruise speed (60% of top speed).
##   circle_run   full ahead at top speed with the nose told to keep turning:
##                the width of the circle the velocity follows, and the speed
##                it keeps.
##   strafe_run   from rest, the strafe key held for 3 s with the nose told to
##                hold still: the sideways speed gained and how far the nose
##                swung.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=flight_table_probe
##
## HOW TO READ THE OUTPUT: one "FLIGHT <hull> ..." line per hull, then one
## "PROBE_JSON {...}" line with the same numbers (time in seconds, distance in
## world units, angles in degrees, speed in world units per second).
##
## WHO USES IT: main.gd loads it for --test=flight_table_probe. It only reads
## the game and draws no random numbers (the ships it makes are launched into
## a frozen match that is thrown away).

## The length (seconds) of one step: a match tick.
const DT := 1.0 / 60.0
## The longest any one measure runs (game seconds).
const MAX_SECS := 90.0
## How far away (world units) the spot the nose is told to point at is put.
const FAR := 1000000.0
## The nose counts as "there" within this many degrees of the wanted heading.
const NOSE_OK_DEG := 2.0
## Cruise speed, as a share of the top speed.
const CRUISE := 0.6
## How long the circle is flown before it is measured (game seconds).
const CIRCLE_SETTLE := 4.0
## How long the circle is measured for (game seconds).
const CIRCLE_SPAN := 8.0

## The running match (set by setup()).
var world: World
## Where the ships are measured: open ground between the lanes.
var _home := Vector2.ZERO
## A far corner where finished ships are put away.
var _away := Vector2(-5000.0, -5000.0)
## How many ships have been put away, so each gets its own far spot.
var _put_away := 0


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Measure every hull, print the table and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var out := {}
	for hid: String in Ships.ORDER:
		var s := _launch(hid)
		var row := _measure(s)
		out[hid] = row
		print("FLIGHT %s top %.1f t95 %.2f d95 %.0f stop_t %.2f stop_d %.0f slide %.0f turn90 %.2f turn180 %.2f over180 %.1f settle180 %.2f cruise90 %.2f cruise180 %.2f circle_d %.0f circle_v %.0f strafe_v %.1f nose_swing %.1f" % [
			hid, row["top"], row["t95"], row["d95"], row["stop_t"], row["stop_d"], row["stop_slide"], row["turn90"], row["turn180"],
			row["over180"], row["settle180"], row["cruise90"], row["cruise180"], row["circle_d"], row["circle_v"], row["strafe_v"], row["strafe_nose"]])
		_put(s)
	print("PROBE_JSON ", JSON.stringify({"probe": "flight_table_probe", "dt": DT, "rows": out}))
	get_tree().quit()


## All the measures for ship `s`, as one row of numbers.
func _measure(s: Ship) -> Dictionary:
	var row := {"label": str(Ships.HULLS[s.hull_id]["label"]), "size": s.size_class}
	var a := _accel_run(s)
	row["top"] = a["top"]
	row["t95"] = a["t95"]
	row["d95"] = a["d95"]
	var st := _stop_run(s, float(a["top"]))
	row["stop_t"] = st["t"]
	row["stop_d"] = st["d"]
	row["stop_slide"] = st["slide"]
	var t90 := _turn_run(s, 90.0, 0.0, 0.0)
	var t180 := _turn_run(s, 180.0, 0.0, 0.0)
	row["turn90"] = t90["t"]
	row["turn180"] = t180["t"]
	row["over90"] = t90["over"]
	row["over180"] = t180["over"]
	row["settle90"] = t90["settle"]
	row["settle180"] = t180["settle"]
	row["cruise90"] = _turn_run(s, 90.0, CRUISE, 0.0)["t"]
	row["cruise180"] = _turn_run(s, 180.0, CRUISE, 0.0)["t"]
	var c := _circle_run(s)
	row["circle_d"] = c["d"]
	row["circle_v"] = c["v"]
	var sr := _strafe_run(s)
	row["strafe_v"] = sr["v"]
	row["strafe_nose"] = sr["nose"]
	# The four big classes: the engine swivel, end to end (from one limit to
	# the other), when the build has swivelling engines.
	if Handling.has_line(s.hull_id):
		var line: Dictionary = Handling.row(s.hull_id)["line"]
		row["rate"] = int(line["rate"])
		var rate := float(line["swivel_rate"])
		row["swivel_end_to_end"] = 2.0 * float(line["swivel_max"]) / rate if rate > 0.0 else 0.0
	return row


## Launch a pilot ship of hull `hid` for team 0 (a pilot named after the hull),
## with nobody at the controls.
func _launch(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 0, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Put ship `s` away in its own far corner and make it dead, so nothing looks
## at it again.
func _put(s: Ship) -> void:
	_put_away += 1
	s.global_position = _away - Vector2(float(_put_away) * 400.0, 0.0)
	s.alive = false
	world.registry.rebuild_hashes()


## Put ship `s` back to its start: at home, nose to the right, moving at
## `speed` along the nose (0 = at rest), full battery, controls empty and any
## engine or spin state cleared.
func _reset(s: Ship, speed: float) -> void:
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2(speed, 0.0)
	s.energy.value = s.energy.max_value
	s.emp_t = 0.0
	s.recompute_stats(true)
	s.throttle = 0.0
	if "swivel" in s:
		s.set("swivel", 0.0)
	if "ang_vel" in s:
		s.set("ang_vel", 0.0)
	var c := s.controls
	c.forward = 0.0
	c.strafe = 0.0
	c.boost = false
	c.fire = false
	c.assist = true
	c.face_point = _home + Vector2(FAR, 0.0)
	c.aim_point = c.face_point


## One step: fly the ship (the real flight function), then move it by its
## velocity, as a match does when nothing is in the way.
func _step(s: Ship) -> void:
	ShipFlight.fly(s, DT)
	s.global_position += s.velocity * DT


## The nose's angle (degrees, 0 to 180) away from heading `deg`.
func _nose_err_deg(s: Ship, deg: float) -> float:
	return absf(rad_to_deg(Util.ang_diff(s.rotation, deg_to_rad(deg))))


## Full ahead from rest, nose ahead: the top speed (the speed after MAX_SECS),
## the seconds to 95% of it and the distance flown by then.
func _accel_run(s: Ship) -> Dictionary:
	_reset(s, 0.0)
	s.controls.forward = 1.0
	var speeds := PackedFloat32Array()
	var dists := PackedFloat32Array()
	var d := 0.0
	var steps := int(MAX_SECS / DT)
	for _i in steps:
		_step(s)
		d += s.velocity.length() * DT
		speeds.append(s.velocity.length())
		dists.append(d)
	var top := speeds[steps - 1]
	var t95 := -1.0
	var d95 := -1.0
	for i in steps:
		if speeds[i] >= 0.95 * top:
			t95 = float(i + 1) * DT
			d95 = dists[i]
			break
	return {"top": top, "t95": t95, "d95": d95}


## From `speed` along the nose, brake (S held, nose told to stay ahead) until
## the speed along the line reaches zero: seconds, distance along the line, and
## the most the ship slid off the line. The step in which the speed crosses
## zero is cut where it crossed (the speed changes in a straight line inside a
## step), so a hard brake is not rounded to a whole step.
func _stop_run(s: Ship, speed: float) -> Dictionary:
	_reset(s, speed)
	s.controls.forward = -1.0
	var slide := 0.0
	var steps := int(MAX_SECS / DT)
	var prev_x := _home.x
	var prev_v := speed
	for i in steps:
		_step(s)
		slide = maxf(slide, absf(s.global_position.y - _home.y))
		if s.velocity.x <= 0.0:
			var frac := prev_v / (prev_v - s.velocity.x) if prev_v > s.velocity.x else 1.0
			return {"t": (float(i) + frac) * DT, "d": prev_x - _home.x + (s.global_position.x - prev_x) * frac, "slide": slide}
		prev_x = s.global_position.x
		prev_v = s.velocity.x
	return {"t": -1.0, "d": s.global_position.x - _home.x, "slide": slide}


## The nose told to point `deg` degrees from where it points now, flying at
## `speed_frac` of the top speed with `thrust` on the main engine: seconds
## until it is within NOSE_OK_DEG of the wanted heading, the largest error
## after that (the overshoot, in degrees), and the seconds until it stays
## within NOSE_OK_DEG for good.
func _turn_run(s: Ship, deg: float, speed_frac: float, thrust: float) -> Dictionary:
	_reset(s, 0.0)
	s.velocity = Vector2(speed_frac * s.f_max, 0.0)
	s.controls.forward = thrust
	s.controls.face_point = _home + Vector2.from_angle(deg_to_rad(deg)) * FAR
	var t_in := -1.0
	var over := 0.0
	var last_bad := 0.0
	var steps := int(40.0 / DT)
	for i in steps:
		_step(s)
		var err := _nose_err_deg(s, deg)
		var t := float(i + 1) * DT
		if err > NOSE_OK_DEG:
			last_bad = t
		elif t_in < 0.0:
			t_in = t
		if t_in >= 0.0:
			over = maxf(over, err)
	return {"t": t_in, "over": over, "settle": last_bad}


## Full ahead at top speed with the nose told every step to keep turning (to a
## spot 1 radian off where it points): the width of the circle the ship's
## velocity follows, measured over CIRCLE_SPAN seconds after CIRCLE_SETTLE
## seconds, and the speed it keeps.
func _circle_run(s: Ship) -> Dictionary:
	_reset(s, 0.0)
	s.velocity = Vector2(s.f_max, 0.0)
	s.controls.forward = 1.0
	var arc := 0.0
	var turned := 0.0
	var prev_dir := 0.0
	var v_end := 0.0
	var steps := int((CIRCLE_SETTLE + CIRCLE_SPAN) / DT)
	for i in steps:
		s.controls.face_point = s.global_position + Vector2.from_angle(s.rotation + 1.0) * FAR
		_step(s)
		var dir := s.velocity.angle()
		if float(i) * DT >= CIRCLE_SETTLE:
			arc += s.velocity.length() * DT
			turned += absf(Util.ang_diff(prev_dir, dir))
		prev_dir = dir
		v_end = s.velocity.length()
	return {"d": 2.0 * arc / maxf(turned, 0.0001), "v": v_end}


## From rest, the strafe key held (to port) for 3 s with the nose told to hold
## still: the sideways speed gained and how many degrees the nose swung.
func _strafe_run(s: Ship) -> Dictionary:
	_reset(s, 0.0)
	s.controls.strafe = 1.0
	var steps := int(3.0 / DT)
	var swing := 0.0
	for _i in steps:
		_step(s)
		swing = maxf(swing, absf(rad_to_deg(Util.wrap_angle(s.rotation))))
	var v := s.velocity.dot(Util.port_of(s.rotation))
	return {"v": v, "nose": swing}
