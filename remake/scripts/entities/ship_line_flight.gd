class_name ShipLineFlight
extends RefCounted
## WHAT THIS IS: the "ships of the line" flight model (a part of Ship, kept in
## its own file): how the corvettes, frigates, destroyers and battlecruisers
## fly while Rules.big_hull_flight() is on. They are driven by main engines at
## the stern that swivel; their reverse thrusters are weak; and their side
## thrusters sit just fore of the engines, far from the centre of the ship, so
## a side burst pushes the stern sideways and turns the nose. The engines do
## most of the turning and the braking by swinging round to where they are
## needed. (Named for the sailing ships of the line: the Battlecruiser flies
## like a first-rate, the Destroyer a third-rate, the frigates fourth-rates and
## the corvettes sixth-rates.)
##
## HOW IT WORKS: like ShipFlight it is a "static library": it keeps no memory
## of its own, and the ship holds the state (the engine angle `swivel`, the
## spin `ang_vel`). The pilot, human or computer, still asks the same things
## through ShipControls: thrust forward or back, strafe, and a point to face.
## Flight assist (this file) works out the parts from those:
##   1. The nose. The point to face gives a wanted spin: as fast as the hull
##      may turn (Ship.f_turn, less at speed), but slowing early enough to stop
##      on the point. The stop is planned with the push the side thrusters can
##      always give, plus half of what the engines can give. The push that
##      closes the gap between the wanted spin and the real one is the
##      "turning push".
##   2. The engines. The turning push goes to the side thrusters first (they
##      answer at once, but are weak). When a turn is big, what they cannot
##      give is asked of the main engines: they swing straight across to the
##      side the push is wanted from (Ship.swivel, at Ship.f_swivel_rate) and
##      burn once they are across. They also swing across ahead of time to
##      the braking side when the spin will soon need stopping. A pilot who
##      brakes (S) makes them swing right round, up to Ship.f_swivel_max each
##      way, to push against the motion; they stay swung for a moment so a
##      brake held on and off does not swing them to and fro. A hull with a
##      brake split (Ship.f_brake_split) swings its two engines the opposite
##      ways instead (they "toe out", Ship.toe, so their sideways parts cancel
##      and the ship stops straight) and they burn as soon as they point back at
##      all. While thrusting
##      forward with flight assist on, they tilt a little against any sideways
##      drift.
##   3. The forces. Every part pushes the ship where it sits: the engines
##      along their swivel angle, the reverse thrusters straight back through
##      the centre, the side thrusters sideways at the stern. A push at the
##      stern moves the ship sideways AND turns it: the farther from the
##      centre it pushes, the more it turns, and the more the weight is spread
##      out, the less. The model adds up the sideways push and the turn of
##      each part. The spin carries the nose round and the push moves the
##      ship.
## Because every turn is a push at the stern, a turn also leaves the ship with
## some sideways drift, and a hull held on a point by the pilot's mouse cancels
## the twist of a strafe key almost completely (the engines swing across to
## undo it), so the side thrusters slide a ship of the line only a little.
## Then, as in ShipFlight: boost, the cap on speed, the pull back to the cap
## and the tiny drag; flight assist also trims the sideways drift slowly.
## Speeds are in world units per second (1 world unit is about one pixel at
## normal zoom); pushes are in world units per second, per second; spins are in
## radians per second (a radian is about 57 degrees) and their pushes in
## radians per second, per second. A "turning push" is counted as the sideways
## push at the engines' distance from the centre, in the same unit as the other
## pushes.
##
## WHO USES IT: only ShipFlight.fly(), which hands over for a ship with
## Ship.f_line. The numbers come from ShipStats (from the hull's "line" entry
## in Handling.TABLE).
## How quickly the spin follows the wanted spin (seconds to close the gap, if
## the push allows): short, so the spin is mostly decided by the push the
## hull has.
const SPIN_LAG := 0.12
## On the last stretch of a turn the wanted spin is at most the angle left
## divided by this (seconds), so the nose settles on the point instead of
## hunting round it.
const SETTLE_TIME := 0.25
## The stop on the point is planned for this share of the push counted on (the
## rest is a margin against the engines being swung the wrong way).
const PLAN_MARGIN := 0.85
## How much of the engines' turning push is counted on when planning the stop,
## next to the side thrusters' (which are always available): 0..1.
const PLAN_ENGINE := 0.5
## A turning push the side thrusters fall short by less than this (world units
## per second, per second) is rounding, not a need for the engines.
const EXTRA_MIN := 0.001
## The engines help with a turn only when the nose has more than this many
## radians to go (or is already spinning fast): a small correction is left to
## the side thrusters.
const ENGINE_HELP_ERR := 0.35
## A spin faster than this share of the fastest spin also calls for the
## engines' help (to stop it).
const ENGINE_HELP_SPIN := 0.3
## With the nose this close to the point it faces (radians) and hardly spinning,
## the engines are not asked for a turn: the side thrusters finish the settle,
## so the engines do not twitch back and forth across the last degree or two.
const SWIVEL_DEAD_BAND := 0.03
## Once the engines have been called in to help with a turn, they are let go only
## when the nose error and the spin have both fallen under this share of the
## limits that called them in, so the call does not switch on and off at the
## edge. 1.0 means no hold at all (let go at the same limits that call them in):
## the flights measured with 0.6, 0.9 and 0.95 made the engines flip sides more
## often than before in a nose chasing a point that swings 20 degrees each way,
## so the share stays at 1.0 until a better one is found.
const ENGINE_HELP_OFF_SHARE := 1.0
## The engines count as committed to a side once they are swung more than this
## many radians off straight ahead.
const SWIVEL_COMMITTED := 0.3
## Committed engines go over to the other side before SWIVEL_MIN_HOLD is up only
## when the other side's wanted push is more than this share of the side
## thrusters' own push.
const SWIVEL_FLIP_SHARE := 0.3
## Seconds the engines stay on the side they chose, unless the other side's push
## is wanted hard (SWIVEL_FLIP_SHARE).
const SWIVEL_MIN_HOLD := 0.5
## The engines burn to turn the ship only when they are swung this far across
## (the sine of the angle: 0.9 is about 64 degrees). Less across, they would
## mostly speed the ship up.
const ENGINE_BURN_SIN := 0.9
## Seconds the engines stay swung round to brake after the last brake request.
const BRAKE_HOLD := 0.6
## With the engines toed out for a brake, each burns once it points back by more
## than this (the minus cosine of its angle from straight ahead: 0 is a right
## angle, so it burns from the moment it points a little back)...
const BRAKE_BURN_START := 0.0
## ...and burns fully once it points back this much (0.5 is 120 degrees from
## straight ahead); in between it burns in proportion.
const BRAKE_BURN_FULL := 0.5
## While the engines are still closing after a brake (toe above this many
## radians), the engines' single-group moves wait, so the two never fight.
const TOE_SETTLED := 0.05
## Braking works only while the ship moves forward faster than this (world
## units per second); the engines never drive a ship backward.
const BRAKE_MIN_SPEED := 4.0
## How much the engines tilt against sideways drift, with flight assist on and
## the engines pushing forward: radians per world unit per second of drift...
const ASSIST_BIAS_GAIN := 0.012
## ...and the most they tilt (radians).
const ASSIST_BIAS_MAX := 0.4
## The spin is held below this many times the hull's turning speed.
const SPIN_MARGIN := 1.25
## A strafe key (A or D) pressed less than this far counts as not pressed: it is
## neither a stern kick nor a hold on the flight assist's trim of sideways drift.
const KICK_KEY_MIN := 0.12


## Steer and thrust for one tick of `dt` seconds, following ship.controls (see
## HOW IT WORKS). Also sets ship.boosting, ship.swivel, ship.ang_vel and the
## thrust_* values ShipVisual draws.
static func fly(ship: Ship, dt: float) -> void:
	var c := ship.controls
	# Step 1: boost, as in ShipFlight: it needs the button, the ability,
	# mostly-forward thrust and more than 2 energy, and it is paid every tick.
	var sp0 := ship.velocity.length()
	var speed_frac := minf(1.0, sp0 / ship.f_max) if ship.f_max > 0.0 else 0.0
	ship.boosting = c.boost and ship.can_boost and c.forward > 0.2 and ship.energy.value > 2.0 and not ship.systems_off()
	if ship.boosting and not ship.energy.spend(ship.f_boost_drain * dt):
		ship.boosting = false
	var main := ship.f_accel * (ship.f_boost_mul if ship.boosting else 1.0)
	var cap := ship.f_max * (ship.f_boost_cap if ship.boosting else 1.0)
	var arm_e := ship.f_eng_arm
	var arm_s := ship.f_side_arm
	var k2 := ship.f_gyr2

	# Step 2: the nose. How hard the side thrusters alone can spin the ship,
	# and the engines (pushed fully sideways, and counted only when a turn
	# is big enough to call for them); the fastest the hull may spin; the spin
	# that gets the nose onto the point in time (a stop that counts on the side
	# thrusters and part of the engines); and the turning push that closes the
	# gap between the wanted spin and the real one.
	var wcap := ship.f_turn * (1.0 - ship.f_bleed * speed_frac)
	var err := 0.0
	var to_face := c.face_point - ship.global_position
	if to_face.length_squared() > 4.0:
		err = Util.ang_diff(ship.rotation, to_face.angle())
	var a_side := ship.f_strafe * arm_s / k2
	# The stern kick: for a ship whose human pilot flies it (Ship.kick_keys), the
	# A and D keys are a demand to spin the nose at the hull's kick cap, taken by
	# the side thrusters alone, instead of a sideways push. The mouse's point does
	# not count while the key is held. A brake (S) comes first: while S is held the
	# key is a strafe as before and the engines toe out for the brake.
	var kick := ship.kick_keys and absf(c.strafe) >= KICK_KEY_MIN and c.forward >= 0.0
	var help := ship.engine_help
	if absf(err) > ENGINE_HELP_ERR or absf(ship.ang_vel) > ENGINE_HELP_SPIN * wcap:
		help = true
	elif absf(err) < ENGINE_HELP_OFF_SHARE * ENGINE_HELP_ERR and absf(ship.ang_vel) < ENGINE_HELP_OFF_SHARE * ENGINE_HELP_SPIN * wcap:
		help = false
	var in_band := absf(err) <= SWIVEL_DEAD_BAND and absf(ship.ang_vel) < ENGINE_HELP_OFF_SHARE * ENGINE_HELP_SPIN * wcap
	if in_band or kick:
		help = false
	ship.engine_help = help
	var a_eng := main * arm_e / k2 if help else 0.0
	var w_des := 0.0
	if kick:
		# A (strafe +1) spins the nose to port, which lowers the rotation.
		w_des = -c.strafe * ship.f_kick_cap
	elif to_face.length_squared() > 4.0:
		var plan := (a_side + PLAN_ENGINE * a_eng) * PLAN_MARGIN
		w_des = signf(err) * minf(wcap, minf(sqrt(2.0 * plan * absf(err)), absf(err) / SETTLE_TIME))
	var a_max := a_side + a_eng
	var alpha := clampf((w_des - ship.ang_vel) / SPIN_LAG, -a_max, a_max)
	# The same push as a sideways push at the engines' distance (positive =
	# the stern is pushed to starboard, which swings the nose to port), and
	# how much of it the side thrusters can give.
	var f_yaw := -alpha * k2 / arm_e
	var cs := ship.f_strafe * arm_s / arm_e

	# Step 3: where the engines should point. Brake request: right round,
	# toward the side the turning push wants (else the side they are already
	# on). Otherwise, if the side thrusters cannot give all the turning push,
	# straight across to the side it is wanted from (and they burn once there,
	# as hard as the rest needs). Otherwise, spinning toward the point and so
	# near it that the spin will need stopping: across to the braking side,
	# early enough to be there when the stop begins. Otherwise ahead, tilted
	# against sideways drift when thrusting with flight assist on.
	var f := Vector2.from_angle(ship.rotation)
	var star := Util.starboard_of(ship.rotation)
	var v_fwd := ship.velocity.dot(f)
	var v_lat := ship.velocity.dot(star)
	if c.forward < 0.0:
		ship.brake_t = BRAKE_HOLD
	elif c.forward > 0.05:
		ship.brake_t = 0.0
	elif ship.brake_t > 0.0:
		ship.brake_t = maxf(0.0, ship.brake_t - dt)
	ship.swivel_hold_t = maxf(0.0, ship.swivel_hold_t - dt)
	var across := minf(ship.f_swivel_max, 0.5 * PI)
	var extra := absf(f_yaw) - cs
	var phi_t := 0.0
	var split_brake := ship.f_brake_split > 0.0 and ship.brake_t > 0.0 and v_fwd > BRAKE_MIN_SPEED
	if split_brake:
		phi_t = 0.0
	elif ship.brake_t > 0.0 and v_fwd > BRAKE_MIN_SPEED:
		var side := signf(f_yaw) if absf(f_yaw) > 0.05 * cs else (signf(ship.swivel) if ship.swivel != 0.0 else 1.0)
		phi_t = side * ship.f_swivel_max
	elif extra > EXTRA_MIN and not in_band:
		phi_t = _pick_side(ship, signf(f_yaw), absf(f_yaw), cs) * across
	elif not in_band and not kick and _must_stop_spin(ship, err, wcap, a_side + PLAN_ENGINE * a_eng, across):
		# Not while kicking: the kick's own spin would trip this branch and swing
		# the engines across, cutting the forward push. The brake branches above
		# come first, so S with A or D toes the engines out and the flame swings
		# (and `kick` is false while S is held, so the key is a strafe then).
		phi_t = _pick_side(ship, signf(ship.ang_vel), absf(f_yaw), cs) * across
	elif c.forward > 0.0 and c.assist and not ship.boosting:
		phi_t = -clampf(v_lat * ASSIST_BIAS_GAIN, -ASSIST_BIAS_MAX, ASSIST_BIAS_MAX)
	var side_before := signf(ship.swivel) if absf(ship.swivel) > SWIVEL_COMMITTED else 0.0
	var swing := ship.f_swivel_rate * dt
	if split_brake:
		_toe_out(ship, swing)
	elif ship.toe > 0.0:
		var closing := minf(ship.toe, swing)
		ship.toe -= closing
		if ship.toe <= TOE_SETTLED:
			ship.swivel += clampf(phi_t - ship.swivel, -(swing - closing), swing - closing)
	else:
		ship.swivel += clampf(phi_t - ship.swivel, -swing, swing)
	var side_now := signf(ship.swivel) if absf(ship.swivel) > SWIVEL_COMMITTED else 0.0
	if side_now != 0.0 and side_now != side_before:
		ship.swivel_hold_t = SWIVEL_MIN_HOLD

	# Step 4: how hard each part pushes. The forward push (built up over the
	# hull's spool time, if it has one) counts only while the engines point
	# ahead-ish; the brake only while they point back-ish and the ship moves
	# forward, and no harder than the side thrusters can hold the nose against
	# the engines' sideways part; the engines also burn to turn when they are
	# swung across to the side the turning push wants.
	var push := c.forward
	if ship.f_spool > 0.0:
		ship.throttle = minf(maxf(c.forward, 0.0), ship.throttle + dt / ship.f_spool)
		push = ship.throttle if c.forward > 0.0 else c.forward
	var cphi := cos(ship.swivel)
	var sphi := sin(ship.swivel)
	var e := 0.0
	var eng_fwd := 0.0
	var f_eng_y := 0.0
	if ship.toe > 0.0:
		# The engines are toed out (one each side of the common angle): each
		# pushes half, burning by how far back it points, so their sideways
		# parts cancel when they are mirrored.
		var a1 := ship.swivel + ship.toe
		var a2 := ship.swivel - ship.toe
		var c1 := cos(a1)
		var c2 := cos(a2)
		var e1 := 0.0
		var e2 := 0.0
		if push > 0.0:
			e1 = 0.5 * main * push * clampf((c1 - 0.2) / 0.6, 0.0, 1.0)
			e2 = 0.5 * main * push * clampf((c2 - 0.2) / 0.6, 0.0, 1.0)
		elif push < 0.0 and v_fwd > 0.0:
			var pace := clampf(v_fwd / (0.15 * ship.f_max), 0.0, 1.0)
			e1 = 0.5 * main * -push * clampf((-c1 - BRAKE_BURN_START) / (BRAKE_BURN_FULL - BRAKE_BURN_START), 0.0, 1.0) * pace
			e2 = 0.5 * main * -push * clampf((-c2 - BRAKE_BURN_START) / (BRAKE_BURN_FULL - BRAKE_BURN_START), 0.0, 1.0) * pace
		e = e1 + e2
		eng_fwd = e1 * c1 + e2 * c2
		f_eng_y = e1 * sin(a1) + e2 * sin(a2)
	else:
		if push > 0.0:
			e = main * push * clampf((cphi - 0.2) / 0.6, 0.0, 1.0)
		elif push < 0.0 and v_fwd > 0.0:
			var hold_nose := (cs + maxf(0.0, f_yaw * signf(sphi))) / maxf(absf(sphi), 0.2)
			var want := main * -push * clampf((-cphi - 0.2) / 0.6, 0.0, 1.0) * clampf(v_fwd / (0.15 * ship.f_max), 0.0, 1.0)
			e = minf(want, hold_nose)
		if extra > EXTRA_MIN and absf(sphi) > ENGINE_BURN_SIN and signf(sphi) == signf(f_yaw):
			e = maxf(e, minf(main, extra / absf(sphi)))
		eng_fwd = e * cphi
		f_eng_y = e * sphi
	# The engines' sideways push, then the side thrusters make up the rest of
	# the turning push (answering at once, within their strength) and add the
	# pilot's own strafe (port is positive on the key, starboard on the push).
	var s_need := (f_yaw - f_eng_y) * arm_e / arm_s
	# While kicking the key is not a sideways push: its spin is already asked
	# through f_yaw (adding both would turn the nose the other way).
	var key_push := 0.0 if kick else c.strafe * ship.f_strafe
	var f_side := clampf(s_need - key_push, -ship.f_strafe, ship.f_strafe)
	var r := ship.f_reverse * maxf(-push, 0.0)

	# Step 5: the spin and the nose. A push at the stern turns the ship: its
	# sideways size times its distance from the centre, over how hard the hull
	# is to spin.
	var tq := -(arm_e * f_eng_y + arm_s * f_side) / k2
	ship.ang_vel = clampf(ship.ang_vel + tq * dt, -wcap * SPIN_MARGIN, wcap * SPIN_MARGIN)
	ship.rotation = Util.wrap_angle(ship.rotation + ship.ang_vel * dt)
	# The pull aside: engine pods that push unequally yaw the nose toward the weaker one (a computer
	# captain's steering and a pilot's helm work against it, and full opposite helm always wins).
	if ship.parts != null:
		var pull := ship.parts.pull_aside(ship.f_turn, maxf(c.forward, 0.0))
		if pull != 0.0:
			ship.rotation = Util.wrap_angle(ship.rotation + pull * dt)
	f = Vector2.from_angle(ship.rotation)
	star = Util.starboard_of(ship.rotation)

	# Step 6: the speed. The engines and the reverse thrusters, then the side
	# thrusters. At or past the cap the engines can still turn the velocity
	# vector but can't add speed along it.
	var acc := f * (eng_fwd - r) + star * f_eng_y
	if sp0 >= cap and sp0 > 0.0:
		var along := acc.dot(ship.velocity) / sp0
		if along > 0.0:
			acc -= ship.velocity / sp0 * along
	acc += star * f_side
	ship.velocity += acc * dt
	# Over the cap? Pull the speed back toward it smoothly, then a tiny drag
	# on everything (about 1.8% of the speed per second).
	var sp := ship.velocity.length()
	if sp > cap and sp > 0.0:
		var pull := 1.0 - exp(-ship.f_cap_rate * dt)
		ship.velocity *= 1.0 + (cap / sp - 1.0) * pull
	# Flight assist also trims sideways drift (not while strafing or
	# boosting), at a small share of the grip other hulls get: the ship keeps
	# most of its drift until the engines' tilt against it has done its work.
	if c.assist and absf(c.strafe) < KICK_KEY_MIN and not ship.boosting:
		var fspd := ship.velocity.dot(f)
		var lat := ship.velocity - f * fspd
		ship.velocity = f * fspd + lat * exp(-ship.f_assist * ship.f_trim * dt)
	ship.velocity *= exp(-0.018 * dt)

	# Step 7: tell ShipVisual which engines are burning (0..1 each).
	ship.thrust_main = e / main if e > 0.05 * main else 0.0
	var sn := f_side / ship.f_strafe if ship.f_strafe > 0.0 else 0.0
	ship.thrust_port = -sn if sn < -0.05 else 0.0
	ship.thrust_star = sn if sn > 0.05 else 0.0


## The strongest braking against forward motion, in world units per second,
## per second: the reverse thrusters plus the main engines swung right round,
## burning no harder than the side thrusters can hold the nose against the
## engines' sideways part. ShipStats stores it as Ship.f_brake, for the AI's
## stopping distances.
static func brake_accel(ship: Ship) -> float:
	if ship.f_brake_split > 0.0:
		return ship.f_reverse + ship.f_accel * absf(cos(toe_target(ship)))
	var s := absf(sin(ship.f_swivel_max))
	var hold_nose := ship.f_strafe * ship.f_side_arm / ship.f_eng_arm / maxf(s, 0.2)
	return ship.f_reverse + minf(ship.f_accel, hold_nose) * absf(cos(ship.f_swivel_max))


## How far each engine is toed out of straight ahead when the ship brakes, in
## radians: straight back less the hull's `brake_split`, and never past how far
## the engines may swivel. ShipStats uses it for the brake's strength and for
## the time the engines take to open (Ship.f_brake_lag).
static func toe_target(ship: Ship) -> float:
	return minf(PI - ship.f_brake_split, ship.f_swivel_max)


## The side (1 or -1) the engines should be swung to for a turn when `wanted`
## is the side the turning push asks for with `push` (world units per second,
## per second; `cs` is what the side thrusters can give): the engines keep the
## side they are committed to until the other side's push is wanted hard or the
## hold time is up. The hold time (Ship.swivel_hold_t) restarts when the engines
## have swung across to a side (fly does that, not this function).
static func _pick_side(ship: Ship, wanted: float, push: float, cs: float) -> float:
	var committed := signf(ship.swivel) if absf(ship.swivel) > SWIVEL_COMMITTED else 0.0
	if committed != 0.0 and wanted != committed and ship.swivel_hold_t > 0.0 and push <= SWIVEL_FLIP_SHARE * cs:
		return committed
	return wanted


## Swing the two engines out for a brake: engine one toward `toe_target` and
## engine two toward minus that, each at most `swing` radians this tick, then
## put the pair's common angle in Ship.swivel and half the gap between them in
## Ship.toe (0 or more).
static func _toe_out(ship: Ship, swing: float) -> void:
	var target := toe_target(ship)
	var a1 := ship.swivel + ship.toe
	var a2 := ship.swivel - ship.toe
	a1 += clampf(target - a1, -swing, swing)
	a2 += clampf(-target - a2, -swing, swing)
	ship.swivel = 0.5 * (a1 + a2)
	ship.toe = 0.5 * (a1 - a2)


## Is the ship spinning toward the point it faces, and so near it that the
## spin will soon need stopping? Then the engines should already be swung
## across to the braking side: `err` is the angle still to turn (radians),
## `wcap` the fastest spin, `push` the turning push counted on for the stop and
## `across` how far the engines swing to be across.
static func _must_stop_spin(ship: Ship, err: float, wcap: float, push: float, across: float) -> bool:
	var w := ship.ang_vel
	if absf(w) < ENGINE_HELP_SPIN * wcap or signf(w) != signf(err):
		return false
	var lead := absf(signf(w) * across - ship.swivel) / maxf(ship.f_swivel_rate, 0.0001)
	var stop := w * w / (2.0 * maxf(push * PLAN_MARGIN, 0.0001))
	return absf(err) < stop + absf(w) * lead + 0.05