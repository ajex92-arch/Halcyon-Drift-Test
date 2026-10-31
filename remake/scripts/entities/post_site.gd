class_name PostSite
extends RefCounted
## WHAT THIS IS: the record of one team's defense post on one lane: where it
## stands, which post (if any) stands there now, and its state. A team has three
## (one a lane), so the match has six. The record outlives the post: when the
## post is destroyed the record keeps the timer that says when the admiral may
## rebuild it.
##
## HOW IT WORKS: the state is one of
##   "standing"   a finished post stands: its lane's minion waves launch from it
##   "destroyed"  the post was destroyed and the rebuild timer runs
##                (PostData.REBUILD_TICKS ticks, counted in whole ticks)
##   "ready"      the timer ran out: the admiral may order a rebuild
##   "building"   a rebuilt post is being built (it launches no wave yet)
## DefensePosts calls update() every tick, and also at the moment a post dies
## (note_destroyed()). Every change of state sends one Events.post_state_changed
## message (team, lane, the new state, the tick number). A post destroyed again
## while it is being rebuilt starts the timer again.
##
## WHO USES IT: DefensePosts makes the six and updates them; MinionDirector asks
## is_standing() and launch_point(); AdmiralCommand and AdmiralBuilder ask state
## and ticks_left(); the admiral board, the HUD and the minimap read it.

## State: a finished post stands.
const STANDING := "standing"
## State: the post was destroyed and the rebuild timer runs.
const DESTROYED := "destroyed"
## State: the timer ran out, the admiral may order a rebuild.
const READY := "ready"
## State: a rebuilt post is being built.
const BUILDING := "building"

## Whose post it is: 0 Aurelian, 1 Vhorr.
var team := 0
## The lane it launches ("top", "mid" or "bot").
var lane := "mid"
## Where the post's body stands (world position).
var pos := Vector2.ZERO
## The centre of the five launch spots (world position).
var launch := Vector2.ZERO
## A length-1 arrow across the lane, along which the launch spots are spread.
var side := Vector2.DOWN
## A length-1 arrow along the lane toward the enemy (the post faces that way).
var along := Vector2.RIGHT
## The post that stands here now (finished or being rebuilt), or null while it
## is destroyed.
var post: DefensePost = null
## The state now (STANDING, DESTROYED, READY or BUILDING).
var state := STANDING
## The tick number of the last change of state.
var state_tick := 0
## The tick number at which the post was last destroyed (-1 = never).
var destroyed_tick := -1
## The first tick at which the admiral may rebuild it (-1 = it never fell).
var ready_tick := -1


## Make the record for team `t`'s post on lane `ln`, with its place from the
## map plan (MapLayout.lane_post).
func _init(t: int, ln: String) -> void:
	team = t
	lane = ln
	var plan := MapLayout.lane_post(ln, t)
	pos = plan["pos"]
	launch = plan["launch"]
	side = plan["side"]
	along = plan["along"]


## True while a finished post stands (its lane's waves may launch).
func is_standing() -> bool:
	return post != null and is_instance_valid(post) and post.alive and post.is_built()


## Where launch spot `slot` (0 to 4, wrapping) of this post is: on the lane,
## PostData.LAUNCH_SPACING apart across it, the way the mothership's bow spots
## are.
func launch_point(slot: int) -> Vector2:
	return launch + side * float((slot % 5) - 2) * PostData.LAUNCH_SPACING


## How many ticks are left before the admiral may rebuild the post (0 once the
## timer has run out, or while the post stands), counted from tick `tick`.
func ticks_left(tick: int) -> int:
	if ready_tick < 0:
		return 0
	return maxi(0, ready_tick - tick)


## The post was just destroyed at tick `tick`: start the rebuild timer.
func note_destroyed(w: World, tick: int) -> void:
	post = null
	destroyed_tick = tick
	ready_tick = tick + PostData.REBUILD_TICKS
	update(w, tick)


## Work out the state at tick `tick`, and when it differs from the recorded one,
## record it and send the message.
func update(w: World, tick: int) -> void:
	var next := state
	if post != null and is_instance_valid(post) and post.alive:
		next = STANDING if post.is_built() else BUILDING
	else:
		# No live post: destroyed, until the timer runs out.
		if state == STANDING or state == BUILDING:
			next = DESTROYED
		if next == DESTROYED and tick >= ready_tick:
			next = READY
	if next != state:
		state = next
		state_tick = tick
		Events.post_state_changed.emit(team, lane, state, tick)
		DefensePosts.announce(w, self)
