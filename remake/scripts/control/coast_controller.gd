class_name CoastController
extends RefCounted
## WHAT THIS IS: the coast of an Admiral who flies a ship of their own while mode 3 is open (the command view or the
## Admiral board open while flying). The view and the board are menus, so W A S D Q E must not steer the ship then: they
## move the camera, and the ship coasts. (It was BoardHold, the stage 1 stopgap, which only knew the board.)
##
## HOW IT WORKS: a "static library" (it keeps no memory of its own). The HUD keeps World.board_open and World.view_open up
## to date; World.mode3() is true when either is. While it is true and the human plays the Admiral,
## PlayerController.update() calls coast() as its last step but one (the match log's controls line is written after it),
## and coast() rewrites the controls the keys and mouse have just filled in:
##   - the player's guns are off (fire is false: a left button held across Tab fires nothing);
##   - the engines are off (forward, strafe and boost are 0), so the ship
##     keeps its speed, and face_point is a spot straight ahead (the same as
##     holding Ctrl), so it keeps its heading;
##   - the guard: when something solid lies ahead on the line of the ship's
##     motion (a rock, a turret, a derelict or a mothership: everything the
##     ship bumps into), closer than the ship needs to stop plus a safety gap,
##     the engines push against the motion until the ship has stopped short
##     of it (stop_reach() works out how far that is).
## Nothing else is changed: the special and the kit work as always, the dock key too, and the automatic guns (point
## defence, flak on auto mounts) aim and fire by themselves in WeaponMount. (The aim holds and the clicks fire
## nothing: PlayerController and World handle those.) With no human Admiral flying, nothing here runs, so a match is not changed.
## DETERMINISM: the coast reads only the match (the ship's velocity, the rocks, turrets, derelicts and motherships) and
## the screen flag that opened it: no Input, no frame time, no random numbers. The controls it writes are recorded after it, so a replay of
## a recorded match plays the same coast without running it (PlayerController returns before this step then).
##
## WHO USES IT: PlayerController (coast), World (holding, to keep the guns quiet), CameraRig (holding, to let the move
## keys pan the camera), tests/coast_check.gd and tests/board_hold_check.gd.

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
## The length of one tick (seconds): the World always ticks at 60 a second. The braking push is eased down so that one tick's push
## never takes away more speed than the ship has left (a small craft brakes so hard that a full push in the last tick would swing
## it round to drift away from the rock instead of stopping).
const TICK := 1.0 / 60.0


## Is mode 3 open for the human Admiral (the command view or the board, World.mode3()), so that a ship they fly coasts?
## Only the human Admiral's seat: a pilot is never held, and no computer Admiral asks. (The camera and World ask it too.)
static func holding(world: World) -> bool:
	return world != null and world.mode3() and world.human_role == "admiral"


## Rewrite the human Admiral's `ship`'s controls for this tick when the coast applies (see the top of the file);
## otherwise leave them alone. PlayerController is the only caller, so `ship` is the human's.
static func coast(world: World, ship: Ship) -> void:
	if not holding(world):
		return
	var c := ship.controls
	var ahead := Vector2.from_angle(ship.rotation)
	c.forward = 0.0
	c.strafe = 0.0
	c.boost = false
	# The player's guns stay quiet in mode 3, also with the left button held across Tab (the mouse works the view).
	c.fire = false
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
	var soft := minf(1.0, speed / (brake_accel(ship) * TICK))
	c.forward = against.dot(ahead) * soft
	c.strafe = against.dot(Util.port_of(ship.rotation)) * soft


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
	return speed * speed / (2.0 * brake_accel(ship)) * STOP_SAFETY + ROCK_GAP + speed * ship.f_brake_lag


## How hard (world units a second, every second) ship can push against its own motion with the engines it has for that
## direction (the main engine, the reverse thrusters and the side thrusters in the mix the push needs); at least 1.
static func brake_accel(ship: Ship) -> float:
	var speed := ship.velocity.length()
	if speed <= 0.0:
		return 1.0
	var against := -ship.velocity / speed
	var fwd := against.dot(Vector2.from_angle(ship.rotation))
	var side := against.dot(Util.port_of(ship.rotation))
	var accel := (ship.f_accel if fwd > 0.0 else ship.f_brake) * fwd * fwd + ship.f_strafe * side * side
	return maxf(accel, 1.0)
