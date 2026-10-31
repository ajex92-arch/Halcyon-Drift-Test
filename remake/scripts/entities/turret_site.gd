class_name TurretSite
extends RefCounted
## WHAT THIS IS: the record of one turret site: the plain facts about a place
## where the admiral may put a turret. Every site (every ResourceNode of the
## map, whether it has ore rocks or not) owns one.
##
## HOW IT WORKS: a site has a stable id and a name (the node's own), a kind
## (the node's kind, see MapLayout.NODES), the radius of its build circle, the
## length of its clear window and its state. The state is worked out once a
## tick from the turrets that stand on the site and the rebuild lock after a
## turret died there:
##   "held"      a finished turret stands here (the team holds the site)
##   "building"  a turret is still being built here (it already holds the site)
##   "locked"    a turret died here less than the rebuild lock ago: nothing can
##               be built until the lock ends
##   "open"      none of the above
## A shared jungle site (kind "jungle_shared", where either team may build) that
## is otherwise open also tells who stands in its build circle: "contested" when
## pilot ships or minions of both teams are inside, "clear" (the team it belongs
## to is the one that is inside) when only one team is. The counts of pilots and
## minions inside are kept in pilots and minions and read from the ring at every
## SCAN_EVERY ticks; the screens show them (SiteMarks) and no rule reads them.
## Every time the state or the team it belongs to changes, the record sends one
## Events.site_state_changed message (the site's id, the new state, the team
## and the tick number). The tick number is a whole number of ticks: the game
## runs 60 ticks a second, so windows are counted in ticks, never in seconds.
## The record keeps the tick of its last change.
##
## The build circle is the round area (radius in world units) in which an enemy
## pilot ship or minion stops the admiral from building (ResourceNode.
## build_blocker reads build_radius): 1,500 on a lane site, 900 on a jungle
## site. The clear window is how many ticks that circle would have to
## stay free of enemies before a build order is accepted. No rule reads the
## window yet; it is kept here so a later rule has one place to look.
##
## WHO USES IT: ResourceNode makes one in setup() and calls update() every
## tick. Screens, tests and later rules read the fields; tests and the news
## feed listen to Events.site_state_changed.

## State: nothing stands here and nothing blocks building.
const OPEN := "open"
## State: a turret is being built here.
const BUILDING := "building"
## State: a finished turret stands here.
const HELD := "held"
## State: a turret died here recently and the site is locked.
const LOCKED := "locked"
## State: nothing stands here and pilot ships or minions of both teams are inside
## the build circle (shared jungle sites only).
const CONTESTED := "contested"
## State: nothing stands here and only one team has pilot ships or minions inside
## the build circle (shared jungle sites only); the team is state_team.
const CLEAR := "clear"
## How often (in ticks) a shared jungle site counts who is inside its circle.
const SCAN_EVERY := 6
## How many ticks make one second of game time (project.godot, physics ticks
## per second).
const TICKS_PER_SECOND := 60
## The length of the clear window on a lane site, in ticks (10 s).
const LANE_WINDOW_TICKS := 600
## The length of the clear window on a jungle site, in ticks (8 s).
const JUNGLE_WINDOW_TICKS := 480
## The site's kinds that lie in a jungle (MapLayout.NODES).
const JUNGLE_KINDS := ["jungle_team", "jungle_shared"]
## The radius of the build circle of a jungle site [world units]. It is smaller
## than a lane site's (TurretData.BUILD_CLEAR_RADIUS) because a jungle node's
## clearing is small and the camps lie close.
const JUNGLE_BUILD_RADIUS := 900.0

## The site's id (the node's id): stable for the whole match.
var site_id := ""
## The name players see (the node's name).
var display_name := ""
## The kind (the node's kind, see MapLayout.NODES).
var kind := ""
## The radius of the build circle [world units].
var build_radius := TurretData.BUILD_CLEAR_RADIUS
## The length of the clear window [ticks].
var window_ticks := LANE_WINDOW_TICKS
## The state now: OPEN, BUILDING, HELD, LOCKED, CONTESTED or CLEAR.
var state := OPEN
## The team the state belongs to (the holder for "held" and "building", the team
## inside for "clear"), or -1 for "open", "locked" and "contested".
var state_team := -1
## Pilot ships of each team inside the build circle at the last count (index =
## team; shared jungle sites only, else 0).
var pilots := [0, 0]
## Minions of each team inside the build circle at the last count.
var minions := [0, 0]
## The tick of the last count (-1000 = none yet).
var _scan_tick := -1000
## A reusable list for the spatial hash (see _count_inside()).
var _scratch: Array = []
## The tick number of the last change of state or team (0 = since the start).
var state_tick := 0


## Fill the record from its node's id, name and kind.
func _init(id: String, nm: String, node_kind: String) -> void:
	site_id = id
	display_name = nm
	kind = node_kind
	window_ticks = JUNGLE_WINDOW_TICKS if node_kind in JUNGLE_KINDS else LANE_WINDOW_TICKS
	build_radius = JUNGLE_BUILD_RADIUS if node_kind in JUNGLE_KINDS else TurretData.BUILD_CLEAR_RADIUS


## True if the site lies in a jungle (an ore node of the jungle).
func is_jungle() -> bool:
	return kind in JUNGLE_KINDS


## Count the live pilot ships and minions of each team inside the build circle
## of node `n` (the spatial hash may list units a little outside, so the
## distance is checked) into pilots and minions.
func _count_inside(n: ResourceNode) -> void:
	pilots = [0, 0]
	minions = [0, 0]
	for u: Unit in n.world.unit_hash.query(n.global_position, build_radius, _scratch):
		if not u.alive or u.team < 0 or u.team > 1 or u.global_position.distance_to(n.global_position) >= build_radius:
			continue
		if u.kind == Unit.K_SHIP:
			pilots[u.team] = int(pilots[u.team]) + 1
		elif u.kind == Unit.K_MINION:
			minions[u.team] = int(minions[u.team]) + 1


## Work out the state from node `n` and, if it differs from the recorded one,
## record it and send the message. `tick` is the world's tick number. ResourceNode
## calls this every tick.
func update(n: ResourceNode, tick: int) -> void:
	var team := -1
	var next := OPEN
	# Step 1: a turret stands here: finished means held, else building.
	for t in n.slots:
		if t != null and is_instance_valid(t) and t.alive:
			team = t.team
			if t.is_built():
				next = HELD
				break
			next = BUILDING
	# Step 2: no turret: the rebuild lock, or open.
	if next == OPEN and n.world.time < n.rebuild_lock_until:
		next = LOCKED
	# Step 3: a shared jungle site that is still open: who is inside its circle.
	if next == OPEN and kind == "jungle_shared":
		if tick - _scan_tick >= SCAN_EVERY:
			_count_inside(n)
			_scan_tick = tick
		var in0 := int(pilots[0]) + int(minions[0]) > 0
		var in1 := int(pilots[1]) + int(minions[1]) > 0
		if in0 and in1:
			next = CONTESTED
		elif in0 or in1:
			next = CLEAR
			team = 0 if in0 else 1
	# Step 4: a change is recorded once and sent once.
	if next != state or team != state_team:
		state = next
		state_team = team
		state_tick = tick
		Events.site_state_changed.emit(site_id, state, state_team, tick)
