extends Node
## WHAT THIS IS: the wing-follow probe. It plays a match with the test wing on (a Scout, a Fighter and a Bomber behind
## the human pilot), flies the human's Fighter along a lane, and writes down, for each wingman, how far it is from its
## pilot, how fast it flies and how much its nose turns, once a second. The number it exists for: the seconds a
## wingman spends FAR from its pilot, SLOW and TURNING (a wingman circling away from the pilot, as in a player's note),
## by hull. It changes nothing in the match; it only reads.
##
## HOW IT WORKS: setup() buys a Fighter for the human and launches it (the wing launches with it), then puts a small
## scripted controller on that Fighter: full throttle (and boost while the battery is over 40 percent) along the lane's
## points. The pilot's hull is topped up every tick, so the pilot lives through the whole run. Every tick the probe adds
## up how far each wingman's nose turned; every 60 ticks (a second of match time) it samples each wingman: the distance
## to the pilot, the speed, the turn of the last second, the distance to its place in the shape, the brain's mode, the
## torpedo run's phase, the target, and whether the wingman is "strayed" (flying home). A "WC" line is printed for each
## sample. The thresholds that make a second count (a wingman is FAR beyond FAR_DIST from the pilot, SLOW under SLOW_FRAC
## of its own hull's top speed, TURNING when its nose swung through TURN_RAD or more in the second) are constants here
## and can be changed by option. At the end (--secs, default 180 seconds of match time) it prints one "PROBE_JSON {...}"
## line with the seconds by hull, then "wing_circles_probe: N failures" and quits. The failures are the check: with
## --wc-limit=<seconds> every wingman hull whose FAR, SLOW and TURNING seconds (not counting the seconds it flies home) exceed the limit counts one failure
## (without it the probe only measures, 0 failures).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/; the queue's
## run_batch with -Raw does the same for a list of seeds):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=wingcircles --wingmen=scout,fighter,bomber --seed=7 --secs=180 --test=wing_circles_probe
## Options of its own: --wc-lane=top|mid|bot (default top), --wc-cruise=<speed> (hold that speed instead of full
## throttle), --wc-far=<units>, --wc-slow=<fraction>, --wc-turn=<radians>, --wc-limit=<seconds>, --wc-mortal (the pilot
## is not topped up and can die), --wc-quiet (no WC lines, only the summary), --wc-trace=<from>-<to> (ten "TR" lines a
## second, between those seconds of match time, for the wingman of place --wc-trace-slot, default 2 = the Bomber: its
## position, speed, nose, controls, route waypoint and stuck state).
##
## WHO USES IT: main.gd loads it for --test=wing_circles_probe (it calls setup()); run_checks runs it as a check; the
## lead runs it through the queue for the many-seed measurement.

## A wingman is far from its pilot beyond this many world units (the wing's own "catching up" line is 2.5 spacings,
## about 280; the straggler line, past which it flies home, is 6,000).
const FAR_DIST := 1500.0
## A wingman is slow below this fraction of its hull's top speed (Ship.f_max).
const SLOW_FRAC := 0.5
## A wingman is turning when the sum of its nose turns over a second is at least this many radians (a Bomber's top turn
## is 1.15 a second).
const TURN_RAD := 0.6
## How many seconds of match time a run lasts when --secs is not given.
const DEFAULT_SECS := 180.0
## What the pilot flies: a small scripted controller, set on the human's ship in place of the keyboard.
class Lead extends RefCounted:
	## The pilot has reached a point of the lane when it is this close.
	const REACH := 700.0
	## The points to fly through, in order.
	var points := PackedVector2Array()
	## The point being flown to.
	var index := 0
	## When above 0, the speed to hold instead of full throttle.
	var cruise := 0.0

	## The ship calls this every tick, as it does for a keyboard.
	func update(ship: Ship, _dt: float) -> void:
		var c := ship.controls
		while index < points.size() - 1 and ship.global_position.distance_to(points[index]) < REACH:
			index += 1
		var to: Vector2 = points[index] if points.size() > 0 else ship.global_position + Vector2(1000.0, 0.0)
		c.face_point = to
		c.aim_point = to
		c.forward = 1.0 if cruise <= 0.0 else clampf((cruise - ship.velocity.length()) / 80.0, -1.0, 1.0)
		c.strafe = 0.0
		c.boost = cruise <= 0.0 and ship.can_boost and ship.energy.fraction() > 0.4
		c.fire = false
		c.assist = true


## What the probe keeps for one wingman place (slot 0, 1 or 2).
class Track extends RefCounted:
	## The hull id of the wingman of this place (set at the first sample).
	var hull := ""
	## Seconds the wingman was flying.
	var secs := 0
	## Seconds far from the pilot.
	var far := 0
	## Seconds far and slow.
	var far_slow := 0
	## Seconds far, slow and turning.
	var far_slow_turning := 0
	## Seconds far, slow and turning while the brain was not flying home (a wingman that strayed flies home by the AI pilots' own code).
	var far_slow_turning_follow := 0
	## Seconds the brain was in its "home" mode.
	var home := 0
	## Seconds the wingman was not flying (docked, or shot down).
	var gone := 0
	## The farthest it was from the pilot (world units).
	var dist_max := 0.0
	## The sum of the distances, for the mean.
	var dist_sum := 0.0
	## The sum of the speeds, for the mean.
	var speed_sum := 0.0
	## The nose angle at the last tick (radians), valid when `has_last`.
	var last_rot := 0.0
	## True once `last_rot` holds a value for the ship now flying.
	var has_last := false
	## The sum of the nose turns since the last sample (radians, without sign).
	var turn_acc := 0.0
	## The sum of the nose turns since the last sample (radians, with sign: a circle adds up, a wobble does not).
	var turn_net := 0.0
	## The first second of match time at which the wingman was far (-1 = never).
	var first_far := -1
	## The route goal the brain held at the last tick (INF = none).
	var last_goal := Vector2.INF
	## How many times the brain planned a new route (its route goal changed) since the last sample.
	var replans_sec := 0
	## How many times the brain planned a new route in the whole run.
	var replans := 0

## The running match (set by setup()).
var world: World
## The human pilot's profile.
var pilot: PilotProfile
## The human pilot's ship.
var leader: Ship
## The pilot's controller.
var lead_ctl := Lead.new()
## One Track for each place of the wing.
var tracks: Array[Track] = []
## The wing's lead record.
var lead_rec: Squad
## When the run ends (seconds of match time).
var secs_total := DEFAULT_SECS
## The thresholds in force (the constants, or the options).
var far_dist := FAR_DIST
## The slow line (a fraction of the hull's top speed).
var slow_frac := SLOW_FRAC
## The turning line (radians a second).
var turn_rad := TURN_RAD
## The check limit in seconds (-1 = measure only).
var limit := -1.0
## True when no WC lines are printed.
var quiet := false
## True when the pilot's hull is not topped up.
var mortal := false
## The seconds of match time in which the TR trace lines are printed (trace_to 0 = no trace; --wc-trace=<from>-<to>).
var trace_from := 0
## The last second of the trace.
var trace_to := 0
## The place of the wing that the trace follows (--wc-trace-slot, default 2: the Bomber).
var trace_slot := 2
## The last tick that was sampled.
var last_tick := -1
## Seconds the pilot was alive and flying.
var pilot_secs := 0
## The sum of the pilot's speeds, for the mean.
var pilot_speed_sum := 0.0
## How many checks failed.
var fails := 0
## True once the summary was printed.
var done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_physics_priority = -100
	secs_total = float(Game.opt("secs", DEFAULT_SECS))
	far_dist = float(Game.opt("wc-far", FAR_DIST))
	slow_frac = float(Game.opt("wc-slow", SLOW_FRAC))
	turn_rad = float(Game.opt("wc-turn", TURN_RAD))
	limit = float(Game.opt("wc-limit", -1.0))
	quiet = Game.opt("wc-quiet", false) != false
	mortal = Game.opt("wc-mortal", false) != false
	lead_ctl.cruise = float(Game.opt("wc-cruise", 0.0))
	var tr := str(Game.opt("wc-trace", "")).split("-")
	if tr.size() == 2:
		trace_from = int(tr[0])
		trace_to = int(tr[1])
	trace_slot = int(Game.opt("wc-trace-slot", 2))
	var lane := str(Game.opt("wc-lane", "top"))
	var pts := MapLayout.lane_points(lane, 0)
	for i in range(1, pts.size()):
		lead_ctl.points.append(pts[i])
	for i in Squads.WING_MAX:
		tracks.append(Track.new())
	pilot = world.human
	if pilot == null:
		print("FAIL there is no human pilot (run with --auto --role=pilot)")
		fails += 1
		return
	HumanCmd.run(world, "buy_hull", ["fighter"])
	HumanCmd.run(world, "launch")
	leader = pilot.ship
	if leader == null:
		print("FAIL the human pilot did not launch")
		fails += 1
		return
	leader.controller = lead_ctl
	lead_rec = Squads.lead_record(world, pilot.team, pilot.slot)
	print("wing_circles_probe: lane=%s secs=%.0f far=%.0f slow=%.2f turn=%.2f wing=%s" % [lane, secs_total, far_dist, slow_frac, turn_rad, str(Game.wing_hulls_for(true))])


## The wingman ship of place `i`, or null when it is not flying.
func _wing_ship(i: int) -> Ship:
	if lead_rec == null:
		return null
	var recs := Squads.wing_records(world, lead_rec.wing_id)
	if i >= recs.size():
		return null
	var crew := Squads.crew_of(world, recs[i])
	if crew == null or crew.ship == null or not is_instance_valid(crew.ship):
		return null
	var s: Ship = crew.ship
	return s if s.alive and crew.state == "flying" else null


## Every tick, before the World's: keep the pilot alive, add up the nose turns, and sample once a second.
@warning_ignore("integer_division")
func _physics_process(_dt: float) -> void:
	if world == null or done or lead_rec == null:
		return
	if not is_instance_valid(leader) or not leader.alive:
		# The pilot was shot down (--wc-mortal): the run goes on, the wing flies home; the pilot is not relaunched.
		pass
	elif not mortal:
		leader.hull = leader.hull_max
	var tick := world.tick_count
	if tick == last_tick:
		return
	last_tick = tick
	if trace_to > 0 and tick % 6 == 0 and tick >= trace_from * 60 and tick <= trace_to * 60:
		_trace(tick)
	for i in tracks.size():
		var t := tracks[i]
		var s := _wing_ship(i)
		if s == null:
			t.has_last = false
			continue
		if t.has_last:
			var d := Util.wrap_angle(s.rotation - t.last_rot)
			t.turn_acc += absf(d)
			t.turn_net += d
		t.last_rot = s.rotation
		t.has_last = true
		var brain := s.controller as WingmanAI
		if brain != null:
			if brain.path_goal != Vector2.INF and brain.path_goal != t.last_goal:
				t.replans += 1
				t.replans_sec += 1
			t.last_goal = brain.path_goal
	if tick > 0 and tick % 60 == 0:
		_sample(tick / 60)
	if world.time >= secs_total:
		_finish()


## One "TR" line (ten a second) for the wingman of place `trace_slot`: where it is, how fast, its nose, what the controls
## are told (the point the nose is sent to, thrust, side thrust, boost), the route's waypoint, and the stuck and rock state.
func _trace(tick: int) -> void:
	var s := _wing_ship(trace_slot)
	if s == null:
		return
	var b := s.controller as WingmanAI
	if b == null:
		return
	var c := s.controls
	var p := s.global_position
	var face_err := absf(Util.ang_diff(s.rotation, (c.face_point - p).angle()))
	var wp := Vector2.INF
	if not b.path.is_empty():
		wp = b.path[mini(b.path_i, b.path.size() - 1)]
	var wp_err := absf(Util.ang_diff(s.rotation, (wp - p).angle())) if wp != Vector2.INF else -1.0
	var vang := absf(Util.ang_diff(s.rotation, s.velocity.angle())) if s.velocity.length() > 20.0 else 0.0
	print("TR t=%.1f x=%.0f y=%.0f v=%.0f rot=%.2f verr=%.2f ferr=%.2f fwd=%.2f str=%.2f bst=%d mode=%s rt=%d/%d wperr=%.2f wpd=%.0f open=%d unst=%.1f stuck=%.1f rb=%d" % [tick / 60.0, p.x, p.y, s.velocity.length(), s.rotation, vang, face_err, c.forward, c.strafe, 1 if c.boost else 0, b.mode, b.path_i, b.path.size(), wp_err, p.distance_to(wp) if wp != Vector2.INF else -1.0, 1 if world.map.in_open_lane(p) else 0, b.flight._unstick_t, b.flight._stuck_t, 1 if b.rock_between else 0])


## One second's sample of every wingman (second number `sec` of the run).
func _sample(sec: int) -> void:
	var pilot_alive := is_instance_valid(leader) and leader.alive
	var lp := leader.global_position if pilot_alive else Vector2.ZERO
	if pilot_alive:
		pilot_secs += 1
		pilot_speed_sum += leader.velocity.length()
		if not quiet:
			print("WC t=%d PILOT x=%.0f y=%.0f v=%.0f wp=%d" % [sec, lp.x, lp.y, leader.velocity.length(), lead_ctl.index])
	for i in tracks.size():
		var t := tracks[i]
		var s := _wing_ship(i)
		if s == null:
			t.gone += 1
			t.turn_acc = 0.0
			t.turn_net = 0.0
			continue
		var b := s.controller as WingmanAI
		t.hull = s.hull_id
		t.secs += 1
		var dist := s.global_position.distance_to(lp) if pilot_alive else INF
		var speed := s.velocity.length()
		var is_far := pilot_alive and dist > far_dist
		var is_slow := speed < slow_frac * s.f_max
		var is_turn := t.turn_acc >= turn_rad
		if is_far:
			t.far += 1
			if t.first_far < 0:
				t.first_far = sec
			if is_slow:
				t.far_slow += 1
				if is_turn:
					t.far_slow_turning += 1
					if not (b != null and b.mode == "home"):
						t.far_slow_turning_follow += 1
		if pilot_alive:
			t.dist_max = maxf(t.dist_max, dist)
			t.dist_sum += dist
		t.speed_sum += speed
		var mode := b.mode if b != null else "?"
		if mode == "home":
			t.home += 1
		if not quiet:
			var slot_d := b._slot(s).distance_to(s.global_position) if b != null and b.rec != null and pilot_alive else -1.0
			var tgt := "-"
			if b != null and b.target != null and is_instance_valid(b.target):
				tgt = b.target.display_name
			var strayed := b != null and b.rec != null and bool(b.rec.engine.get("strayed", false))
			var run_phase := b.run.phase if b != null else -1
			# The route the brain is flying: the waypoint's index and the route's length, how far the waypoint is, and how
			# far the nose is turned away from it (radians); a flight that is backing off a rock shows "unst".
			var route := "rt=-"
			if b != null and not b.path.is_empty():
				var wp_i := mini(b.path_i, b.path.size() - 1)
				var wp: Vector2 = b.path[wp_i]
				route = "rt=%d/%d wpd=%.0f err=%.2f" % [b.path_i, b.path.size(), s.global_position.distance_to(wp), absf(Util.ang_diff(s.rotation, (wp - s.global_position).angle()))]
			var unst := " unst" if b != null and b.flight._unstick_t > 0.0 else ""
			print("WC t=%d W%d %s x=%.0f y=%.0f d=%.0f v=%.0f/%.0f turn=%.2f net=%.2f slot=%.0f mode=%s run=%d tgt=%s strayed=%s %s rp=%d%s hull=%.2f%s" % [sec, i, s.hull_id, s.global_position.x, s.global_position.y, dist, speed, s.f_max, t.turn_acc, t.turn_net, slot_d, mode, run_phase, tgt, str(strayed), route, t.replans_sec, unst, s.hull_frac(), " FAR_SLOW_TURNING" if is_far and is_slow and is_turn else ""])
		t.turn_acc = 0.0
		t.turn_net = 0.0
		t.replans_sec = 0


## The end: the summary line, the check, and quit.
func _finish() -> void:
	done = true
	var by_hull := {}
	var worst := 0
	for t in tracks:
		if t.hull == "":
			continue
		var mean_d := t.dist_sum / maxf(1.0, float(t.secs))
		by_hull[t.hull] = {"secs": t.secs, "gone": t.gone, "far": t.far, "far_slow": t.far_slow, "far_slow_turning": t.far_slow_turning, "fst_follow": t.far_slow_turning_follow, "home": t.home, "dist_max": snappedf(t.dist_max, 1.0), "dist_mean": snappedf(mean_d, 1.0), "speed_mean": snappedf(t.speed_sum / maxf(1.0, float(t.secs)), 1.0), "first_far": t.first_far, "replans": t.replans}
		worst = maxi(worst, t.far_slow_turning_follow)
		if limit >= 0.0 and float(t.far_slow_turning_follow) > limit:
			fails += 1
			print("FAIL the %s wingman spent %d s far, slow and turning while following (limit %.0f)" % [t.hull, t.far_slow_turning_follow, limit])
	var summary := {"seed": int(Game.opt("seed", -1)), "secs": snappedf(world.time, 0.1), "pilot_secs": pilot_secs, "pilot_speed_mean": snappedf(pilot_speed_sum / maxf(1.0, float(pilot_secs)), 1.0), "far_dist": far_dist, "slow_frac": slow_frac, "turn_rad": turn_rad, "hulls": by_hull}
	print("PROBE_JSON %s" % JSON.stringify(summary))
	print("wing_circles_probe: %d failures" % fails)
	get_tree().quit()
