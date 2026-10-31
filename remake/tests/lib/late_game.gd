class_name LateGame
extends RefCounted
## WHAT THIS IS: the "skip to the late game" setup that several tests
## share: tests/endgame.gd, tests/det_hash.gd --late, tests/fun_probe.gd
## --late, tests/pilot_audit.gd --late and tests/admiral_audit.gd --late.
##
## HOW IT WORKS: apply() moves the match clock to 25:00 and makes both
## sides late-game strong at once: every facility except Fleet Command,
## all research done (with its effects), upgraded and full motherships,
## 6,000 credits in each treasury and for every pilot (enough for a
## capital ship), and Cinder's mid lane without its three lane turrets (as if
## Cinder had already lost them; the other 15 lane turrets stand from the
## start of every match). With `symmetric` true, Cinder keeps its mid lane
## turrets too, so both sides start exactly alike (the research's "symmetric
## --late start"; the fun probe's --symmetric option).
## This is a "static library": plain functions with no state of their own.
##
## WHO USES IT: tests/endgame.gd, tests/det_hash.gd (with --late),
## tests/fun_probe.gd (with --late), tests/pilot_audit.gd (with --late) and
## tests/admiral_audit.gd (with --late) call apply() from their setup().

## The match clock after apply(): 1,500 s = 25:00.
const START := 1500.0


## Set up the late game in `world` (see HOW IT WORKS). Call it right after
## the World is built, before the first tick. `symmetric` = leave Cinder's mid
## lane turrets standing (default false: the usual setup, which det_hash's
## late baseline is made with).
static func apply(world: World, symmetric: bool = false) -> void:
	# Step 1: move the clock to 25:00; the next minion wave comes 5 s later.
	world.time = START
	world.minion_director.next_wave = START + 5.0
	# Step 2: for both teams, build every facility except "fleet", finish
	# all research (and apply its effects), upgrade and refill the
	# mothership, and fill the treasury with 6,000 credits.
	for t in 2:
		var ts := world.teams[t]
		for f: String in Tech.FACILITY_ORDER:
			if f != "fleet":
				ts.facilities[f] = true
		for id: String in Tech.ORDER:
			ts.done[id] = true
			ts.apply_effect(Tech.TECHS[id]["effect"])
		var ms := world.mothership(t)
		ms.apply_upgrades(ts)
		ms.hull = ms.hull_max
		ms.shields.fill()
		ts.treasury = 6000.0
	# Step 3: every pilot gets 6,000 credits.
	for p: PilotProfile in world.profiles:
		p.credits = 6000.0
	# Step 4: the 18 lane turrets stand from the start (WorldSetup). Unless
	# `symmetric`, Cinder's mid lane has lost all three of its turrets (taken
	# away quietly: no reward, no rebuild lock).
	if not symmetric:
		for t: Turret in world.turrets.duplicate():
			if t.team == Rules.CINDER and t.node != null and t.node.lane == "mid" and MapLayout.is_lane_site_kind(t.node.node_kind):
				world.combat.kill_silently(t)
