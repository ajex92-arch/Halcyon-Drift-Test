class_name Roster
extends RefCounted
## WHAT THIS IS: the pilots' callsigns (the short nicknames the game uses
## for its pilots in messages and on screen). Callsigns for pilots. Index 0
## of the human's team is the human when flying (so "Lancer" for Aurelian, "Ash"
## for Vhorr).
##
## HOW IT WORKS: each team has a list of 6 names. A pilot's "slot" is its
## seat number on the team (0, 1, 2, ...), and callsign() gives the name at
## that place in the list (starting again from the top if the slot number
## is past the end). Each team has 5 pilots (Rules.PILOTS_PER_TEAM) in slots
## 0-4, and the admiral's seat (Rules.ADMIRAL_SEAT, slot 5) takes the last
## name, which is the callsign of the computer admiral when it flies. (A
## human admiral's own record is called "Admiral".) So every seat gets a
## different name.
##
## WHO USES IT: WorldSetup, when it makes the pilots at the start of a
## match.

## Aurelian's callsigns, by slot ("Lancer" is slot 0, "Ardent" the admiral's seat).
const HALCYON := ["Lancer", "Wren", "Kestrel", "Marlin", "Sable", "Ardent"]
## Cinder's callsigns, by slot ("Morrow" is the admiral's seat).
const CINDER := ["Ash", "Brand", "Coil", "Drake", "Ember", "Morrow"]


## The callsign for the pilot in seat `slot` of team `team`. Any team other
## than Aurelian uses the Cinder list.
static func callsign(team: int, slot: int) -> String:
	var names: Array = HALCYON if team == Rules.HALCYON else CINDER
	return names[slot % names.size()]
