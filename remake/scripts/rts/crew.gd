class_name Crew
extends RefCounted
## WHAT THIS IS: the maker of a "crew" record. A bought fleet ship (or a wingman)
## is flown by the same kind of record a pilot has, because the ship, the damage
## log and about a hundred other places already work with a PilotProfile. A crew
## is a PilotProfile that is flagged is_crew: it has no money, no gear, no
## scoreboard line, no share of the ore, no respawn and no shopping trip, and a yard
## crew's ship never docks (a wingman's crew docks with its leader). When its ship dies the ship is simply lost.
##
## HOW IT WORKS: Crew.make() builds the profile for one ship of a squad record. The
## yard's crews get seat numbers from 100 to 199, handed out one after another and
## starting again at 100 after 199, so they never collide with the pilots' seats
## 0-5 (the seat number picks the launch spot and the brain's temperament, and a
## number of 100 or more gives the "dog" temperament). The wingmen's crews take
## 200 + the pilot's seat x 10 + the wing slot (200 to 249); their maker passes
## that seat in. Crew.make() does not put the profile into World.profiles and does
## not make the ship: the caller does both, and sets the profile's state to
## "flying" and its ship when the ship exists (MatchRules.on_pilot_died looks for
## exactly that when the ship is lost).
##
## WHO USES IT: the yard's arrivals (a bought ship appears with a crew), the wingmen
## code (a wingman's crew), and the crew checks.

## The first seat number of the yard's crews.
const YARD_SLOT_FIRST := 100
## How many seat numbers the yard's crews use before the counter starts again.
const YARD_SLOT_COUNT := 100
## The first seat number of the wingmen's crews (200 + seat x 10 + wing slot).
const WING_SLOT_FIRST := 200
## The name of the counter kept on the World (a plain whole number).
const _SLOT_META := "crew_yard_slot_next"


## The next seat number of the yard's crews: 100, 101 ... 199, 100 ... One counter
## per match, kept on the World, so two matches in one program never share it.
static func next_yard_slot(world: World) -> int:
	var n := int(world.get_meta(_SLOT_META, 0))
	world.set_meta(_SLOT_META, (n + 1) % YARD_SLOT_COUNT)
	return YARD_SLOT_FIRST + n


## The crew record for one ship of `squad`: team `team`, flying hull `hull_id`, the
## ship number `index` (0 to 2) inside the squad. It is named "<hull label> <index
## + 1>" unless `callsign` is given. `slot` is the seat number; -1 takes the next
## yard seat. The record has is_crew = true, is_human = false, 0 credits, no gear,
## the hull set, the squad's id and the role "mid".
static func make(world: World, team: int, hull_id: String, squad: Squad, index: int, slot: int = -1, callsign: String = "") -> PilotProfile:
	# Step 1: the name and the seat number.
	var label := str(Ships.HULLS[hull_id]["label"])
	var name_value := callsign if callsign != "" else "%s %d" % [label, index + 1]
	var seat := slot if slot >= 0 else next_yard_slot(world)
	# Step 2: the profile, flagged as a crew with nothing of its own.
	var p := PilotProfile.new(name_value, team, seat, false)
	p.is_crew = true
	p.credits = 0.0
	p.hull_id = hull_id
	p.squad_id = squad.id if squad != null else -1
	p.role = "mid"
	return p
