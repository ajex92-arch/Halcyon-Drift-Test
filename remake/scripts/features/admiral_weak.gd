class_name AdmiralWeak
extends RefCounted
## WHAT THIS IS: the "weak admiral" test option (--admiral-ai=weak). It is
## not a game rule and not a feature module: it is a measurement tool for the
## weak-admiral A/B (the normal AI admiral must beat this one in 60-90% of
## the matches, so the admiral seat matters but is not a single point of
## failure; docs/FUN_PLAN.md and the admiral_command brief).
##
## HOW IT WORKS: the option's value picks which team's AI admiral is weak:
##   --admiral-ai=weak      Vhorr (team 1) has the weak admiral
##   --admiral-ai=weak1     the same
##   --admiral-ai=weak0     Halcyon (team 0) has the weak admiral
##   --admiral-ai=weakboth  both admirals are weak
## A weak admiral (AdmiralAI.weak) still builds mining drones and the first
## turret at each inner node, but: it starts a tech plan step only every
## 90 s (WEAK_PLAN_GAP), builds more turrets only at its inner nodes (never
## at the middle nodes), and places no repair bays or wards, declares no
## sieges and moves no mothership. The waypoint is still placed. Without the
## option nothing changes at all: AdmiralAI reads the option once, when it is
## made, and every extra check is then false.
##
## WHO USES IT: AdmiralAI._init() asks is_weak(). Tests pass the option on the
## command line (tests/fun_probe.gd matches via run_batch.ps1).

## Seconds between two plan steps of a weak admiral.
const WEAK_PLAN_GAP := AdmiralProfileData.TABLE["plan_gap_s"][2] / 1000.0


## Is team `team`'s AI admiral the weak one in this match? True when the --admiral-ai option names that
## team (see HOW IT WORKS) or --admiral-profile gives it the weak profile (AdmiralProfile.for_team).
static func is_weak(team: int) -> bool:
	return AdmiralProfile.for_team(team, Game.options).on("is_weak")


## Does team `team` have a computer admiral that is NOT the weak one? The
## feature modules' AI parts (Sweep, Bounty, Fortify, the smart plan, the
## sinks) act only for such an admiral, so the weak admiral of the A/B stays
## plain.
static func ai_acts(world: World, team: int) -> bool:
	var ai: AdmiralAI = world.admiral_ai[team]
	return ai != null and not ai.weak


## Does team `team` have a computer admiral that acts in the hooks that are the human seat's own buttons and calls (the
## command assets, Fortify, the smart composition calls)? A computer admiral does; a deputy (the computer admiral that helps
## a human Admiral) does only while the human is away, never while the human is present.
static func ai_acts_seat(world: World, team: int) -> bool:
	if not ai_acts(world, team):
		return false
	var ai: AdmiralAI = world.admiral_ai[team]
	return ai.deputy == null or ai.deputy.away


## Does team `team` have a computer admiral that is no deputy? Only such an admiral acts in the hooks that a deputy never
## runs, present or away (the bounties, which steer the pilots).
static func ai_acts_solo(world: World, team: int) -> bool:
	if not ai_acts(world, team):
		return false
	var ai: AdmiralAI = world.admiral_ai[team]
	return ai.deputy == null
