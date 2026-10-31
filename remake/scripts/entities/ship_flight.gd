class_name ShipFlight
extends RefCounted
## WHAT THIS IS: the "flight model" of a pilot ship (a part of Ship, kept in
## its own file): how the stick and engine buttons turn into turning,
## speeding up, sliding and bumping into asteroids.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## Each function is handed the ship and changes the ship's own rotation,
## velocity and flags. The flight is "Newtonian-lite" (ported from v1, the
## first version of the game): like in real space, a ship keeps drifting the
## way it was going until thrust pushes it elsewhere, but with a few helpers
## so it stays easy to fly:
##   - fly() turns the nose toward controls.face_point (slower at high
##     speed), fires the main engine, reverse and side thrusters, handles
##     boost, gently pulls the speed back down to the top speed, and (with
##     flight assist on) damps sideways drift. While a ship is on a torpedo
##     run (Ship.run_locked()) it holds its heading instead: it does not
##     turn, it ignores sideways thrust, and sideways drift is damped whatever
##     the flight assist says; the main engine and the brake still work.
##   - move() actually moves the ship with Godot's move_and_slide(), which
##     slides along anything solid instead of passing through it, adds a
##     small bounce, and makes hard crashes hurt (gently). Touching anything
##     solid also cancels a torpedo run that is on (RunGun.cancel()).
## Speeds are in world units per second (1 world unit is about one pixel at
## normal zoom); engine pushes are in world units per second, per second.
##
## WHO USES IT: only Ship.sim_update(), every tick: fly(), then move().
## The numbers it uses (f_max, f_accel, ...) come from ShipStats.


## Steer and thrust for one tick of `dt` seconds, following ship.controls.
## Also sets ship.boosting and the thrust_* values ShipVisual draws.
static func fly(ship: Ship, dt: float) -> void:
	# A corvette, frigate, destroyer or battlecruiser flies as a ship of the
	# line when the build says so (Ship.f_line): ShipLineFlight takes over.
	if ship.f_line:
		ShipLineFlight.fly(ship, dt)
		return
	var c := ship.controls
	# On a torpedo run (Ship.run_locked()) the heading is locked: no turning
	# and no sideways thrust. W and S still speed up and slow down along the
	# line, and sideways drift dies away even with flight assist off, so the
	# ship keeps moving the way its nose points and the torpedo goes where the
	# path line showed.
	var run := ship.run_locked()
	var strafe := 0.0 if run else c.strafe
	# Step 1: turn the nose toward face_point. Turning gets slower the
	# closer we are to top speed (turn "bleed"); the Fighter's Snap special
	# turns 1.9x faster while it is on.
	var sp0 := ship.velocity.length()
	var speed_frac := minf(1.0, sp0 / ship.f_max) if ship.f_max > 0.0 else 0.0
	var snap := Ship.SPECIAL_SNAP_TURN if (ship.hull_id == "fighter" and ship.special_t > 0.0) else 1.0
	var turn := ship.f_turn * snap * (1.0 - ship.f_bleed * speed_frac)
	var to_face := c.face_point - ship.global_position
	var rot0 := ship.rotation
	if not run and to_face.length_squared() > 4.0:
		var diff := Util.ang_diff(ship.rotation, to_face.angle())
		ship.rotation = Util.wrap_angle(ship.rotation + clampf(diff, -turn * dt, turn * dt))
	# A ship with a torpedo run notes whether the nose turned (more than a hair)
	# this tick: the Bomber's fan only closes while it flies straight (RunFan).
	if ship.run_mount != null:
		ship.turned = absf(Util.wrap_angle(ship.rotation - rot0)) > RunFan.TURN_EPS

	# Step 2: which way is ahead (f) and which way is left ("port"), and
	# are we boosting? Boost needs the button, the ability, mostly-forward
	# thrust and more than 2 energy, and it is paid every tick.
	var f := Vector2.from_angle(ship.rotation)
	var port := Util.port_of(ship.rotation)
	ship.boosting = c.boost and ship.can_boost and c.forward > 0.2 and ship.energy.value > 2.0
	if ship.boosting and not ship.energy.spend(ship.f_boost_drain * dt):
		ship.boosting = false
	var main := ship.f_accel * (ship.f_boost_mul if ship.boosting else 1.0)
	var cap := ship.f_max * (ship.f_boost_cap if ship.boosting else 1.0)

	# Step 3: add up the engine pushes (acc). Forward uses the main engine,
	# backward the weaker reverse thrusters.
	# A hull with a spool time (Ship.f_spool) builds its forward push up over
	# that many seconds and drops it at once when W is let go.
	var push := c.forward
	if ship.f_spool > 0.0:
		ship.throttle = minf(maxf(c.forward, 0.0), ship.throttle + dt / ship.f_spool)
		push = ship.throttle if c.forward > 0.0 else c.forward
	var acc := Vector2.ZERO
	if push > 0.0:
		acc += f * main * push
	elif push < 0.0:
		acc += f * ship.f_reverse * push
	# At or past the cap the main engine can still turn the velocity vector
	# but can't add speed along it (v1 fix: W alone never settles over cap).
	if sp0 >= cap and sp0 > 0.0:
		var along := acc.dot(ship.velocity) / sp0
		if along > 0.0:
			acc -= ship.velocity / sp0 * along
	acc += port * ship.f_strafe * strafe
	ship.velocity += acc * dt

	# Step 4: over the cap? Pull the speed back toward it smoothly (a bit
	# more each tick, faster with a higher cap_rate).
	var sp := ship.velocity.length()
	if sp > cap and sp > 0.0:
		var pull := 1.0 - exp(-ship.f_cap_rate * dt)
		ship.velocity *= 1.0 + (cap / sp - 1.0) * pull
	# Flight assist damps sideways drift only while not strafing (and not
	# boosting): split the velocity into "along the nose" and "sideways"
	# and shrink the sideways part.
	if (c.assist or run) and absf(strafe) < 0.12 and not ship.boosting:
		var fspd := ship.velocity.dot(f)
		var lat := ship.velocity - f * fspd
		ship.velocity = f * fspd + lat * exp(-ship.f_assist * dt)
	# A tiny drag on everything (about 1.8% of the speed per second).
	ship.velocity *= exp(-0.018 * dt)

	# Step 5: tell ShipVisual which engines are burning (0..1 each).
	ship.thrust_main = c.forward if c.forward > 0.05 else 0.0
	ship.thrust_port = strafe if strafe > 0.05 else 0.0
	ship.thrust_star = -strafe if strafe < -0.05 else 0.0


## Move with collisions. Bumps are light (slide + small bounce); impacts
## faster than Rules.COLLISION_SAFE_SPEED (world units per second) hurt,
## gently. The ship can hit asteroids, structures (motherships, turrets,
## derelicts) and the rocks of ore fields (physics layers 1, 3 and 4). A
## hard crash can destroy the ship: check ship.alive afterwards.
static func move(ship: Ship) -> void:
	var pre := ship.velocity
	ship.move_and_slide()
	var count := ship.get_slide_collision_count()
	# Touching anything solid (a rock, a structure or a wall) ends a torpedo run
	# at once, free, as letting go before the bar is full would.
	if count > 0 and ship.run_mount != null:
		ship.run_mount.run.cancel(ship.controls.fire)
	for i in count:
		# How fast were we going INTO the thing we hit? (The "normal" is
		# the direction pointing straight out of its surface.)
		var col := ship.get_slide_collision(i)
		var n := col.get_normal()
		var impact := -pre.dot(n)
		if impact <= 0.0:
			continue
		# Bounce back a little.
		ship.velocity += n * impact * Rules.COLLISION_BOUNCE
		# A hard crash hurts, at most once every 0.4 s. Bigger hulls hit
		# harder (Rules.COLLISION_SIZE_MULT); crash armour lowers it.
		if impact > Rules.COLLISION_SAFE_SPEED and ship.collide_cd <= 0.0 and ship.world != null:
			ship.collide_cd = 0.4
			var dmg := (impact - Rules.COLLISION_SAFE_SPEED) * Rules.COLLISION_DAMAGE_PER_SPEED
			dmg *= float(Rules.COLLISION_SIZE_MULT[Rules.size_index(ship.size_class)]) * (1.0 - ship.collision_resist)
			# The hit "comes from" the side we crashed on, so the shield on
			# that side takes it.
			var info := DamageInfo.new()
			info.amount = dmg
			info.kind = Rules.W_COLLISION
			info.from_pos = ship.global_position - n * ship.radius * 2.0
			ship.world.combat.apply_damage(ship, info)
			Events.cue.emit("bump", ship.global_position)
			if not ship.alive:
				return
