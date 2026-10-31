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
##      brake held on and off does not swing them to and fro. While thrusting
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
## The engines burn to turn the ship only when they are swung this far across
## (the sine of the angle: 0.9 is about 64 degrees). Less across, they would
## mostly speed the ship up.
const ENGINE_BURN_SIN := 0.9
## Seconds the engines stay swung round to brake after the last brake request.
const BRAKE_HOLD := 0.6
## Braking works only while the ship moves forward faster than this (world
## units per second); the engines never drive a ship backward.
const BRAKE_MIN_SPEED := 4.0
## How much the engines tilt against sideways drift, with flight assist on and
## the engines pushing forward: radians per world unit per second of drift...
const ASSIST_BIAS_GAIN := 0.012
## ...and the most they tilt (radians).
const ASSIST_BIAS_MAX := 0.4
## The share of the hull's flight-assist grip (Handling "assist") that trims
## sideways drift in a ship of the line.
const ASSIST_TRIM := 0.2
## The spin is held below this many times the hull's turning speed.
const SPIN_MARGIN := 1.25


## Steer and thrust for one tick of `dt` seconds, following ship.controls (see
## HOW IT WORKS). Also sets ship.boosting, ship.swivel, ship.ang_vel and the
## thrust_* values ShipVisual draws.
static func fly(ship: Ship, dt: float) -> void:
	var c := ship.controls
	# Step 1: boost, as in ShipFlight: it needs the button, the ability,
	# mostly-forward thrust and more than 2 energy, and it is paid every tick.
	var sp0 := ship.velocity.length()
	var speed_frac := minf(1.0, sp0 / ship.f_max) if ship.f_max > 0.0 else 0.0
	ship.boosting = c.boost and ship.can_boost and c.forward > 0.2 and ship.energy.value > 2.0
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
	var help := absf(err) > ENGINE_HELP_ERR or absf(ship.ang_vel) > ENGINE_HELP_SPIN * wcap
	var a_eng := main * arm_e / k2 if help else 0.0
	var w_des := 0.0
	if to_face.length_squared() > 4.0:
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
	var across := minf(ship.f_swivel_max, 0.5 * PI)
	var extra := absf(f_yaw) - cs
	var phi_t := 0.0
	if ship.brake_t > 0.0 and v_fwd > BRAKE_MIN_SPEED:
		var side := signf(f_yaw) if absf(f_yaw) > 0.05 * cs else (signf(ship.swivel) if ship.swivel != 0.0 else 1.0)
		phi_t = side * ship.f_swivel_max
	elif extra > EXTRA_MIN:
		phi_t = signf(f_yaw) * across
	elif _must_stop_spin(ship, err, wcap, a_side + PLAN_ENGINE * a_eng, across):
		phi_t = signf(ship.ang_vel) * across
	elif c.forward > 0.0 and c.assist and not ship.boosting:
		phi_t = -clampf(v_lat * ASSIST_BIAS_GAIN, -ASSIST_BIAS_MAX, ASSIST_BIAS_MAX)
	var swing := ship.f_swivel_rate * dt
	ship.swivel += clampf(phi_t - ship.swivel, -swing, swing)

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
	if push > 0.0:
		e = main * push * clampf((cphi - 0.2) / 0.6, 0.0, 1.0)
	elif push < 0.0 and v_fwd > 0.0:
		var hold_nose := (cs + maxf(0.0, f_yaw * signf(sphi))) / maxf(absf(sphi), 0.2)
		var want := main * -push * clampf((-cphi - 0.2) / 0.6, 0.0, 1.0) * clampf(v_fwd / (0.15 * ship.f_max), 0.0, 1.0)
		e = minf(want, hold_nose)
	if extra > EXTRA_MIN and absf(sphi) > ENGINE_BURN_SIN and signf(sphi) == signf(f_yaw):
		e = maxf(e, minf(main, extra / absf(sphi)))
	# The engines' sideways push, then the side thrusters make up the rest of
	# the turning push (answering at once, within their strength) and add the
	# pilot's own strafe (port is positive on the key, starboard on the push).
	var f_eng_y := e * sphi
	var s_need := (f_yaw - f_eng_y) * arm_e / arm_s
	var f_side := clampf(s_need - c.strafe * ship.f_strafe, -ship.f_strafe, ship.f_strafe)
	var r := ship.f_reverse * maxf(-push, 0.0)

	# Step 5: the spin and the nose. A push at the stern turns the ship: its
	# sideways size times its distance from the centre, over how hard the hull
	# is to spin.
	var tq := -(arm_e * f_eng_y + arm_s * f_side) / k2
	ship.ang_vel = clampf(ship.ang_vel + tq * dt, -wcap * SPIN_MARGIN, wcap * SPIN_MARGIN)
	ship.rotation = Util.wrap_angle(ship.rotation + ship.ang_vel * dt)
	f = Vector2.from_angle(ship.rotation)
	star = Util.starboard_of(ship.rotation)

	# Step 6: the speed. The engines and the reverse thrusters, then the side
	# thrusters. At or past the cap the engines can still turn the velocity
	# vector but can't add speed along it.
	var acc := f * (e * cphi - r) + star * f_eng_y
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
	if c.assist and absf(c.strafe) < 0.12 and not ship.boosting:
		var fspd := ship.velocity.dot(f)
		var lat := ship.velocity - f * fspd
		ship.velocity = f * fspd + lat * exp(-ship.f_assist * ASSIST_TRIM * dt)
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
	var s := absf(sin(ship.f_swivel_max))
	var hold_nose := ship.f_strafe * ship.f_side_arm / ship.f_eng_arm / maxf(s, 0.2)
	return ship.f_reverse + minf(ship.f_accel, hold_nose) * absf(cos(ship.f_swivel_max))


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