class_name FleetFill
extends RefCounted
## WHAT THIS IS: a test tool that fills both teams' fleets toward the fleet limit at once, so a
## measurement or a picture does not have to wait for the yard. It is used by the late
## worst-case performance probe (tests/perf_probe.gd, --perf-worst) and by the pictures.
##
## HOW IT WORKS: apply() walks a fixed mix of hulls (squadrons of Fighters, Lances and
## Bombers, two corvettes, two frigates and two Destroyers: 18 ships) and asks each team's
## Production for them with spawn_now(), which skips paying and building but keeps the fleet
## limit, so a hull that no longer fits is left out. One call adds at most one mix; a caller that
## wants the limit full calls it again until it returns 0. The ships arrive at the mothership's
## launch spots with the stand-in brain.
##
## WHO USES IT: tests/perf_probe.gd, tests/yard_shots.gd and tests/arrival_check.gd.

## The mix: [hull, ships in the item], 18 ships in all.
const MIX := [["fighter", 3], ["lance", 3], ["bomber", 3], ["fighter", 3], ["logistics", 1], ["support", 1], ["flak", 1], ["ion", 1], ["destroyer", 1], ["destroyer", 1]]


## Fill both teams' fleets from MIX. Returns how many ships were made in all.
static func apply(world: World) -> int:
	var made := 0
	for t in 2:
		var prod: Production = world.teams[t].production
		for row: Array in MIX:
			var it := prod.spawn_now(str(row[0]), int(row[1]))
			if not it.is_empty():
				made += int(row[1])
	return made
