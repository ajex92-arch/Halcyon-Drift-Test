class_name RtsEvents
extends RefCounted
## WHAT THIS IS: the match's list of happenings, one for each team: an order
## carried out or refused, research done, a module built, a turret lost, a post
## changing state, a ship lost, the mothership coming under attack. It is data
## only: nothing here draws, and nothing in the simulation reads it back.
##
## HOW IT WORKS: every happening is one small record,
## {tick, kind, team, pos, uid, data}: the tick it happened on (whole number), a
## kind word, the team it belongs to (0, 1, or -1 for both), a place (a Vector2i
## or null), a unit id (0 for none) and `data`, a Dictionary of whole numbers and
## short words. push() files it in the team's ring (the newest 512 are kept; the
## oldest is dropped) and sends it to that team's AlertList and to the signal
## Events.rts_event. A reader keeps its own cursor: read_from(team, cursor) gives
## everything from that running index on, and next_index(team) is the cursor to
## keep afterwards. RtsEvents listens to the signals the game already sends
## (research_done, facility_done, turret_destroyed, post_state_changed,
## site_state_changed, unit_killed) and turns them into records; tick() adds the
## "mothership under attack" record when a team's defend call turns on. The
## order queue pushes order_done, order_refused and game_speed; later stages push
## their own kinds through push().
##
## WHO USES IT: World keeps one (World.events_rts); WorldSetup makes it; World
## calls tick() once a tick; OrderQueue pushes the order records; AlertList (World.alerts)
## and the HUD read the stream; tests/order_check.gd checks it.

## How many records one team's ring keeps.
const RING := 512

## The game world.
var world: World
## Each team's ring: the newest records, oldest first. Index = team.
var _rings: Array = [[], []]
## For each team: how many records have ever been filed (the running index of the
## next one).
var _next: Array = [0, 0]
## For each team: was the mothership under attack at the last tick()?
var _was_defending: Array = [false, false]
## How many records have been pushed (a record for both teams counts once).
var total := 0


## Remember the world and listen to the game's signals. The listening ends when
## the world leaves the tree, so a new match does not feed an old stream.
func _init(w: World) -> void:
	world = w
	Events.research_done.connect(_on_research_done)
	Events.facility_done.connect(_on_facility_done)
	Events.turret_destroyed.connect(_on_turret_destroyed)
	Events.post_state_changed.connect(_on_post_state)
	Events.site_state_changed.connect(_on_site_state)
	Events.unit_killed.connect(_on_unit_killed)
	world.tree_exiting.connect(_disconnect)


## Stop listening (the world is leaving the tree).
func _disconnect() -> void:
	var pairs: Array = [
		[Events.research_done, _on_research_done],
		[Events.facility_done, _on_facility_done],
		[Events.turret_destroyed, _on_turret_destroyed],
		[Events.post_state_changed, _on_post_state],
		[Events.site_state_changed, _on_site_state],
		[Events.unit_killed, _on_unit_killed],
	]
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var fn: Callable = pair[1]
		if sig.is_connected(fn):
			sig.disconnect(fn)


## File a record. `ev` may leave out any key: the tick is the World's tick
## count, the team -1 (both teams), the place null, the unit 0 and `data` empty.
## A record for team -1 goes into both rings. Returns the filled-in record.
func push(ev: Dictionary) -> Dictionary:
	var rec := {
		"tick": int(ev.get("tick", world.tick_count)),
		"kind": str(ev.get("kind", "")),
		"team": int(ev.get("team", -1)),
		"pos": ev.get("pos", null),
		"uid": int(ev.get("uid", 0)),
		"data": ev.get("data", {}),
	}
	var teams: Array = [0, 1] if int(rec["team"]) < 0 else [int(rec["team"])]
	for t: int in teams:
		var ring: Array = _rings[t]
		ring.append(rec)
		if ring.size() > RING:
			ring.pop_front()
		_next[t] = int(_next[t]) + 1
		var list: AlertList = world.alerts[t] as AlertList
		if list != null:
			list.on_event(rec, int(rec["tick"]))
	total += 1
	Events.rts_event.emit(rec)
	return rec


## The running index of the next record of `team`: the cursor to keep after a read.
func next_index(team: int) -> int:
	return int(_next[team])


## Every record of `team` from running index `cursor` on (the oldest ones may have
## been dropped from the ring, then it starts at the oldest kept). Oldest first.
func read_from(team: int, cursor: int) -> Array:
	var ring: Array = _rings[team]
	var oldest := int(_next[team]) - ring.size()
	var start := maxi(cursor, oldest) - oldest
	return ring.slice(start)


## Once a tick (step 1a of the World's tick): note when a team's defend call turns
## on, which is the mothership coming under attack.
func tick() -> void:
	if world.teams.size() < 2:
		return
	for t in 2:
		var now: bool = world.teams[t].defending(world.time)
		if now and not bool(_was_defending[t]):
			var ms := world.mothership(t)
			push({"kind": "mothership_under_attack", "team": t, "pos": point_of(ms.global_position) if ms != null else null, "uid": ms.uid if ms != null else 0})
		_was_defending[t] = now


## A world position as the whole-number point records carry.
static func point_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.y))


## Research `id` finished for `team`.
func _on_research_done(team: int, id: String) -> void:
	push({"kind": "research_done", "team": team, "data": {"id": id}})


## Facility (module) `id` finished for `team`.
func _on_facility_done(team: int, id: String) -> void:
	push({"kind": "module_done", "team": team, "data": {"id": id}})


## A turret was destroyed: the record belongs to the team that lost it.
func _on_turret_destroyed(turret: Node, _by_team: int) -> void:
	if turret == null or not is_instance_valid(turret):
		return
	var u := turret as Unit
	push({"kind": "turret_lost", "team": u.team, "pos": point_of(u.global_position), "uid": u.uid})


## A defense post changed state.
func _on_post_state(team: int, lane: String, state: String, tick: int) -> void:
	push({"kind": "post_state", "team": team, "tick": tick, "data": {"lane": lane, "state": state}})


## A turret site changed state (`team` is -1 when nobody holds it).
func _on_site_state(site_id: String, state: String, team: int, tick: int) -> void:
	push({"kind": "site_state", "team": team, "tick": tick, "data": {"site": site_id, "state": state}})


## A unit died: a pilot's ship (not a crew ship, whose records are the squad
## code's) becomes one "ship_lost" record.
func _on_unit_killed(unit: Node, _info: RefCounted) -> void:
	if not (unit is Ship):
		return
	var ship := unit as Ship
	if ship.profile == null or ship.profile.get("is_crew") == true:
		return
	push({"kind": "ship_lost", "team": ship.team, "pos": point_of(ship.global_position), "uid": ship.uid, "data": {"squad": 0, "wing": 0}})
