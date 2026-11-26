class_name FieldMode
extends RefCounted
## WHAT THIS IS: the one question "is the human Admiral in field mode?": flying their own ship with the command view closed
## (World.mode3() false). In field mode the command view shows its slim display: the strip, the first few alerts, the group
## chips and the minimap, and nothing else (RtsUiCalls.FIELD_MODE_SLIM). Docked, or flying in mode 3 (the view or the board
## open), the full view shows.
##
## HOW IT WORKS: only a static function that reads the match; it keeps no state and changes nothing. CommandView asks it every
## frame to decide between the slim and the full layout, AlertFeed to decide how many rows to show, and the Minimap to decide
## whether a double tap of a group key draws its flash ring.
##
## WHO USES IT: CommandView, AlertFeed, ArmyCards (through CommandView.is_slim()), Minimap; tests/rts_groups_check.gd,
## tests/alert_feed_check.gd, tests/rts_tour_field.gd.


## Is team `team`'s human Admiral in field mode now: the slim display is on (RtsUiCalls.FIELD_MODE_SLIM), the human is the Admiral
## of that team in a match being played, flying their own ship (not docked) with the view and the board closed.
static func active(world: World, team: int) -> bool:
	if not RtsUiCalls.FIELD_MODE_SLIM or world == null:
		return false
	if world.human_role != "admiral" or world.phase != "play":
		return false
	if world.teams[team].admiral_docked:
		return false
	return not world.mode3()
