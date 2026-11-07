class_name Capacity
extends RefCounted
## WHAT THIS IS: the fleet limit of one team. The fleet is the ships the Admiral
## bought; the limit counts ships (a squadron of three counts 3, a big ship 1) and is
## the same all match (RtsHulls.CAP_IN_FORCE). The pilots' own ships and the
## wingmen never count.
##
## HOW IT WORKS: a place is taken when a build starts (reserve) and given back when
## the started build is cancelled or the ships have arrived (release). From the day
## a ship arrives it is counted from the squad records: every living ship of a
## record of this team whose kind is not "wing". So the places used are the living
## ships plus the places reserved by builds that have started and not yet arrived;
## a ship that dies gives its place back by leaving its record. A held build keeps
## its reserved place.
##
## WHO USES IT: Production (it asks room_for() before a build starts and calls
## reserve() and release()), the Yard tab (the "Fleet 12/63" line), the computer
## Admiral (its fill schedule) and the tests.

## The world (it holds the squad records).
var world: World
## The team this limit is for: 0 or 1.
var team := 0
## The places reserved by builds that have started and not yet arrived.
var reserved := 0


## Make the limit of team `t` in world `w`.
func _init(w: World, t: int) -> void:
	world = w
	team = t


## The most ships the team may have: RtsHulls.CAP_IN_FORCE.
func limit() -> int:
	return RtsHulls.CAP_IN_FORCE


## How many fleet ships of the team are alive: the members of its squad records that
## are not wings. The records are walked in stored order.
func alive() -> int:
	var n := 0
	for id: int in world.squads:
		var s: Squad = world.squads[id] as Squad
		if s != null and s.team == team and s.kind != "wing":
			n += s.member_uids.size()
	return n


## How many places are used: the living ships plus the reserved places.
func used() -> int:
	return alive() + reserved


## Is there room for `units` more ships?
func room_for(units: int) -> bool:
	return used() + units <= limit()


## Take `units` places for a build that has started.
func reserve(units: int) -> void:
	reserved += units


## Give back `units` reserved places (the ships have arrived, or the build was
## cancelled). The count never goes below 0.
func release(units: int) -> void:
	reserved = maxi(0, reserved - units)
