class_name PracticeDrone
extends Unit
## WHAT THIS IS: a target drone of the practice range: a round, unarmed
## target that stands still, flies a loop or drifts, so a pilot can practise
## aim. It belongs to neither team: both teams' shots hit it, and nobody pays
## for destroying it. When one is destroyed the range puts the same kind back
## in the same place a few seconds later (PracticeRange).
##
## HOW IT WORKS:
##   - It is made through World.spawn_practice_drone() with a kind of drone
##     ("still", "moving" or "capital"); its numbers are that kind's row in
##     PracticeDrones.ROWS (radius, hull, speed, sections).
##   - It is neutral, the way the Scum's camps are (Rules.NEUTRAL): the
##     computer's turrets, minions and Scum ships never pick a neutral unit as
##     a target, and a pilot's shot from either team hits it. It is a kind of
##     its own (Unit.K_PRACTICE_DRONE), so no payment rule knows it: a
##     destroyed drone pays no bounty and gives no kill credit.
##   - A still drone does nothing. A moving or drifting one flies round a
##     circle (PracticeDrones.LOOP_LEN long) that starts at its home place, at a
##     fixed speed, and faces the way it flies. Its place is worked out from
##     the time it has lived, so it needs no random number and nothing to
##     steer by; it passes through rocks like a ward does.
##   - It has no shields and nothing heals it, so a hit does the same each
##     time. A drone of one section wears as a whole.
##   - Its painter is a UnitVisual child made in setup() (the Bullseye).
##
## WHO USES IT: WorldSpawner makes it (World.spawn_practice_drone ->
## WorldSpawner, which calls setup()); WorldRegistry keeps it in
## World.practice_drones; World calls sim_update() every tick; PracticeRange
## places the default set and schedules the replacements (on_killed);
## PracticeTrials counts hits on it; UnitVisual draws it.

## Which kind of drone this is: a key of PracticeDrones.ROWS.
var row_id := "still"
## This kind's row from PracticeDrones.ROWS.
var row: Dictionary = {}
## The place it starts from and comes back to (world position).
var home := Vector2.ZERO
## How many armour sections it has (its row's "sections"; the drawing reads it).
var sections := 1
## How fast it moves along its loop [world units a second]; 0 = it stays.
var speed := 0.0
## How long it has lived [seconds]; its place on the loop is worked out from it.
var age := 0.0


## Set up a drone of kind `id` at `at`. WorldSpawner.spawn_practice_drone()
## calls this. It draws no random number.
func setup(w: World, id: String, at: Vector2) -> void:
	# Step 1: who and what we are: neutral, the kind's numbers.
	world = w
	row_id = id
	row = PracticeDrones.row(id)
	team = Rules.NEUTRAL
	kind = Unit.K_PRACTICE_DRONE
	size_class = Rules.SIZE_CAPITAL if float(row["radius"]) >= 100.0 else Rules.SIZE_SMALL
	radius = float(row["radius"])
	hull_max = float(row["hull"])
	hull = hull_max
	speed = float(row["speed"])
	sections = int(row["sections"])
	display_name = String(row["label"])
	vision_radius = 0.0
	# Step 2: where we start. No physics bumps (layer and mask 0).
	position = at
	home = at
	collision_layer = 0
	collision_mask = 0
	# Step 3: its painter, a child node as the scene units have.
	var painter := UnitVisual.new()
	painter.name = "Visual"
	add_child(painter)


## The centre of the circle a moving drone flies round: one loop radius to the
## right of its home place.
func loop_centre() -> Vector2:
	return home + Vector2(PracticeDrones.loop_radius(row_id), 0.0)


## One tick of `dt` seconds: move along the loop (a still drone does not). World
## calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	if speed <= 0.0:
		return
	age += dt
	var r := PracticeDrones.loop_radius(row_id)
	var a := PI + speed / r * age
	position = loop_centre() + Vector2(cos(a), sin(a)) * r
	velocity = Vector2(-sin(a), cos(a)) * speed
	rotation = velocity.angle()


## Combat.kill() calls this when the drone is destroyed: a small puff of
## sparks in the drone's grey, and the range is told so it can put one back.
func on_killed(_info: DamageInfo) -> void:
	world.effects.puff(global_position, Palette.NEUTRAL, 8)
	if world.practice_range != null:
		world.practice_range.drone_lost(row_id, home)
