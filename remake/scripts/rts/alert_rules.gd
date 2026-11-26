class_name AlertRules
extends RefCounted
## WHAT THIS IS: the rules that raise the alerts the match's own events do not raise: a bought squadron or a
## structure of ours takes damage, a squadron loses its last ship, a ship leaves the yard. Together with what
## RtsEvents already files (the mothership under attack, a ship, turret or post lost, a refusal, research and
## module done, the fleet cap full) these are the kinds of the alert list that the alert feed shows.
##
## HOW IT WORKS: a screen-side reader. The alert feed owns one AlertRules and calls poll() a few times a second.
## poll() READS the match (the units' damage stamps, the squadron records, the event stream from its own cursor)
## and writes only to the team's AlertList (World.alerts[team].on_event): it files no record in the event stream,
## issues no order, draws no random number and changes nothing the simulation reads. Five rules:
##   squadron_under_attack: a ship of a bought squadron (kind "squadron" or "ship") took hull damage since the last
##     poll; the place is the middle of the squadron's ships. (The list merges by 2,000-unit cell.)
##   structure_under_attack: a turret, defense post, repair bay or ward of ours took hull damage since the last poll.
##   squadron_lost: the event stream's "ship_lost" of a crew ship says which squadron it was in; when that record has
##     no ship left, the squadron is lost, and its live "under attack" rows in that cell give way to the "lost" row.
##   build_done: arrivals.gd files "ship_built" (not a kind of the list); the rule files it as "build_done".
##   ship_under_fire (RT7, "Under Fire!"): the human's own ship (`watch`, which the feed sets before each poll: null while the
##     Admiral is docked or the ship is dead) took a hull hit since the last poll (_was_hit, so a shield hit does not count);
##     the place is the ship's, so J reaches it. A wingman, a turret and a squadron never raise it.
## ANY_DAMAGE true makes shield hits count too (the design says hull damage; a shielded squadron is attacked sooner).
## Times are World ticks, never seconds, so a pause stops alert lifetimes; poll() in a pause finds nothing new.
##
## attacked() names the squadrons whose squadron_under_attack alert is still alive (the army row's attacked frame).
##
## WHO USES IT: AlertFeed (poll, attacked); tests/alert_feed_check.gd.

## Count a hit on the shield as an attack too (false: only hull damage, as the design says).
const ANY_DAMAGE := false

## The team whose alerts are raised.
var team := 0
## The world.
var world: World
## The match time (seconds) of the last poll: damage stamped after it is new.
var _last_time := 0.0
## The event stream's cursor (the next record this rule has not read).
var _cursor := 0
## The squadrons already reported lost (a squadron whose ships die in one tick is lost once): id -> true.
var _lost := {}
## The alert each attacked squadron was raised or merged into: squadron id -> that alert of the list (attacked()).
var _hit := {}
## The alert the last _raise() got from the list ({} when the list took nothing).
var _last_alert := {}
## The ship whose hull hits raise "Under Fire!": the human's own ship, set by the feed before each poll (null for none).
var watch: Ship = null


## Read from now on: nothing that already happened raises an alert.
func setup(w: World, t: int) -> void:
	world = w
	team = t
	_last_time = w.time
	if w.events_rts != null:
		_cursor = w.events_rts.next_index(t)


## One look at the match. Returns how many alerts it raised or merged.
func poll() -> int:
	if world == null or world.alerts[team] == null:
		return 0
	var n := 0
	n += _read_events()
	n += _damage()
	n += _ship_fire()
	_last_time = world.time
	return n


## Read the new records of the team's stream: ship_built becomes build_done, a crew ship lost may end a squadron.
func _read_events() -> int:
	if world.events_rts == null:
		return 0
	var n := 0
	var recs := world.events_rts.read_from(team, _cursor)
	_cursor = world.events_rts.next_index(team)
	for rec: Dictionary in recs:
		match str(rec["kind"]):
			"ship_built":
				n += _raise("build_done", rec["pos"], int(rec["uid"]), {}, int(rec["tick"]))
			"ship_lost":
				var id := int((rec["data"] as Dictionary).get("squad", 0))
				var squad := world.squads.get(id) as Squad
				if squad != null and _is_bought(squad) and squad.member_uids.is_empty() and not _lost.has(id):
					_lost[id] = true
					var list: AlertList = world.alerts[team]
					list.drop_in_cell("squadron_under_attack", rec["pos"])
					n += _raise("squadron_lost", rec["pos"], id, {"squad": id}, int(rec["tick"]))
	return n


## Raise the damage alerts for what was hit since the last poll.
func _damage() -> int:
	var n := 0
	for squad: Squad in world.squads.values():
		if squad.team != team or not _is_bought(squad):
			continue
		var hit := false
		var sum := Vector2.ZERO
		var count := 0
		for uid: int in squad.member_uids:
			var u: Variant = world.by_uid.get(uid)
			if u == null or not is_instance_valid(u) or not (u as Unit).alive:
				continue
			var unit := u as Unit
			sum += unit.global_position
			count += 1
			hit = hit or _was_hit(unit)
		if hit and count > 0:
			var got := _raise("squadron_under_attack", RtsEvents.point_of(sum / float(count)), squad.id, {"squad": squad.id}, world.tick_count)
			n += got
			if got > 0:
				_hit[squad.id] = _last_alert
	for list: Array in [world.turrets, world.posts, world.bays, world.wards]:
		for s: Variant in list:
			if s == null or not is_instance_valid(s):
				continue
			var unit := s as Unit
			if unit.team == team and unit.alive and _was_hit(unit):
				n += _raise("structure_under_attack", RtsEvents.point_of(unit.global_position), unit.uid, {}, world.tick_count)
	return n


## "Under Fire!": 1 when the watched ship (the human's) is alive and took a hull hit since the last poll (a second hit while the
## row lives merges into it: the list keeps its text without a count).
func _ship_fire() -> int:
	if watch == null or not is_instance_valid(watch) or not watch.alive or not _was_hit(watch):
		return 0
	return _raise("ship_under_fire", RtsEvents.point_of(watch.global_position), watch.uid, {}, world.tick_count)


## Did `u` take a hit since the last poll (a hull hit, or any hit with ANY_DAMAGE)?
func _was_hit(u: Unit) -> bool:
	var stamp := u.last_damage_time if ANY_DAMAGE else u.last_hull_damage_time
	return stamp > _last_time


## Is `squad` one the Admiral bought (a squadron or one big ship, not a wingman)?
func _is_bought(squad: Squad) -> bool:
	return squad.kind == "squadron" or squad.kind == "ship"


## File one alert of `kind` into the team's list; 1 when the list took it.
func _raise(kind: String, pos: Variant, uid: int, data: Dictionary, tick: int) -> int:
	var list: AlertList = world.alerts[team]
	var got := list.on_event({"tick": tick, "kind": kind, "team": team, "pos": pos, "uid": uid, "data": data}, tick)
	_last_alert = got
	return 0 if got.is_empty() else 1


## The squadrons under attack at `tick`, lowest id first: the ones whose squadron_under_attack alert is still alive in the
## list (an alert that ran out, or gave way to "Squadron lost", frees its squadrons). It reads the list and writes only
## this rule's own notes.
func attacked(tick: int) -> Array[int]:
	var out: Array[int] = []
	if world == null or world.alerts[team] == null or _hit.is_empty():
		return out
	var live: Array = (world.alerts[team] as AlertList).live(tick)
	for id: int in _hit.keys():
		var alive := false
		for a: Dictionary in live:
			if is_same(a, _hit[id]):
				alive = true
				break
		if alive and world.squads.has(id):
			out.append(id)
		else:
			_hit.erase(id)
	out.sort()
	return out
