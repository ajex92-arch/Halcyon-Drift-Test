class_name BoardHold
extends RefCounted
## WHAT THIS IS: the small stopgap for an Admiral who flies a ship of their
## own while the Admiral board is open. The board is a menu, so W A S D Q E
## must not steer the ship then: they move the camera, and the ship coasts.
##
## HOW IT WORKS: a "static library" (it keeps no memory of its own). The HUD
## keeps World.board_open up to date. While it is true and the human plays
## the Admiral, PlayerController.update() calls hold() as its last step, and
## hold() rewrites the controls the keys and mouse have just filled in:
##   - the engines are off (forward, strafe and boost are 0), so the ship
##     keeps its speed, and face_point is a spot straight ahead (the same as
##     holding Ctrl), so it keeps its heading;
##   - the guard: when something solid lies ahead on the line of the ship's
##     motion (a rock, a turret, a derelict or a mothership: everything the
##     ship bumps into), closer than the ship needs to stop plus a safety gap,
##     the engines push against the motion until the ship has stopped short
##     of it (stop_reach() works out how far that is).
## Nothing else is changed: the guns the player aims, the special, the kit
## and the dock key work as always, and the automatic guns (point defence,
## flak on auto mounts) aim and fire by themselves in WeaponMount. With no
## human Admiral flying, nothing here runs, so a match is not changed.
##
## WHO USES IT: PlayerController (hold), CameraRig (holding, to let the move
## keys pan the camera), tests/board_hold_check.gd.

## The gap (world units) kept between the ship's centre line and the safety
## pad when it has stopped (short of a rock or any other solid thing), added
## to the stopping distance.
const ROCK_GAP := 120.0
## How far (world units) beyond the ship's own radius the line of motion is
## thickened when it is tested against what lies ahead.
const LINE_PAD := 30.0
## The stopping distance is worked out for a ship that brakes at full
## strength; this factor makes it a little longer, for the drag and the turns.
const STOP_SAFETY := 1.25
## Below this speed (world units a second) the ship counts as stopped.
const MIN_SPEED := 0.5


## Is the human Admiral's board open, so that a ship they fly is held? (The
## camera asks it too.)
static func holding(world: World) -> bool:
	return world != null and world.board_open and world.human_role == "admiral"


## Rewrite `ship`'s controls for this tick when the board hold applies (see
## the top of the file); otherwise leave them alone.
static func hold(world: World, ship: Ship) -> void:
	if not holding(world):
		return
	var c := ship.controls
	var ahead := Vector2.from_angle(ship.rotation)
	c.forward = 0.0
	c.strafe = 0.0
	c.boost = false
	c.face_point = ship.global_position + ahead * 600.0
	# The guard: brake against the motion when something solid is in its way.
	var speed := ship.velocity.length()
	if speed < MIN_SPEED:
		return
	var dir := ship.velocity / speed
	var tip := ship.global_position + dir * stop_reach(ship)
	if not _blocked(world, ship.global_position, tip, ship.radius + LINE_PAD):
		return
	var against := -dir
	c.forward = against.dot(ahead)
	c.strafe = against.dot(Util.port_of(ship.rotation))


## Does anything solid lie on the line from `a` to `b`, thickened by `pad`
## world units? Rocks (ordinary and ore rocks), turrets, derelicts and both
## motherships: everything a ship bumps into (physics layers 1, 3 and 4).
static func _blocked(world: World, a: Vector2, b: Vector2, pad: float) -> bool:
	if not world.asteroids.segment_hit(a, b, pad).is_empty():
		return true
	for ms in world.motherships:
		if ms != null and ms.alive and ms.hit_t(a, b, pad) >= 0.0:
			return true
	for t in world.turrets:
		if is_instance_valid(t) and t.alive and Util.seg_circle_t(a, b, t.global_position, t.radius + pad) >= 0.0:
			return true
	for m in world.monsters:
		if m is Derelict and is_instance_valid(m) and m.alive and Util.seg_circle_t(a, b, m.global_position, m.radius + pad) >= 0.0:
			return true
	return false


## How far ahead of a moving `ship` (world units, along its motion) a rock or
## any other solid thing must be to need no braking yet: the distance it needs to stop when it
## pushes straight against its motion with the engines it has for that
## direction (the main engine, the reverse thrusters and the side thrusters
## in the mix the push needs), made longer by STOP_SAFETY, plus the distance
## flown while a ship of the line's engines swing round to brake, plus
## ROCK_GAP.
static func stop_reach(ship: Ship) -> float:
	var speed := ship.velocity.length()
	if speed <= 0.0:
		return ROCK_GAP
	var against := -ship.velocity / speed
	var fwd := against.dot(Vector2.from_angle(ship.rotation))
	var side := against.dot(Util.port_of(ship.rotation))
	var accel := (ship.f_accel if fwd > 0.0 else ship.f_brake) * fwd * fwd + ship.f_strafe * side * side
	return speed * speed / (2.0 * maxf(accel, 1.0)) * STOP_SAFETY + ROCK_GAP + speed * ship.f_brake_lag
