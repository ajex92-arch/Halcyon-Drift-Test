class_name UnlockAll
extends RefCounted
## WHAT THIS IS: the one question behind the test option "Unlock everything": is
## this buyer unlocked? An unlocked buyer can buy anything at once and for
## nothing: every ship class, module, gear item, repair kit and, for an Admiral,
## every unit, building and research, without waiting for a research or a
## facility. It exists only so a tester can try any ship or unit straight away.
##
## HOW IT WORKS: the option is one setting, Game.unlock_everything (the start
## screen's toggle, remembered between runs, or the launch option --unlock-all).
## is_unlocked() is the only place that reads it, and every price check and lock
## check for a human buyer asks it. It answers true for exactly two kinds of
## buyer, and only while the option is on:
##   - the human's own pilot record (PilotProfile.is_human): the pilot seat, and
##     the Admiral's own record when the human sits in the Admiral seat;
##   - the treasury of the team whose Admiral is the human
##     (TeamState.admiral == "human"): the Admiral seat.
## For everyone else it answers false: the computer pilots (teammates too), the
## other team and the computer Admirals play by the normal prices and locks.
## Research and facilities belong to the team, so a pilot who is unlocked buys
## past a lock without completing the research or building the facility for the
## team, and nobody else is helped by it. An unlocked Admiral pays nothing from
## the treasury and may queue any facility or research at once, but the research
## and the building still take their time and, once done, help the whole team as
## research always does.
##
## WHO USES IT: PilotProfileShop (gear, kits, hulls, modules), the hangar's
## cards (HangarShips, HangarModules, HangarGear, HangarKits), GearMk2Feature,
## BuybackFeature and PilotMiningFeature (their prices), TeamState (can_afford()
## and spend(): the treasury), TeamTech (the rules for queuing a facility or a
## research, and the research queue's progress), AdmiralCommand and
## AdmiralBoardBuild (the torpedo turret and repair bay unlocks),
## AdmiralBoardResearch (its "Needs ..." line), the HUD's top bar (the UNLOCKED
## tag), NoteWriter (the note records the switch) and tests/unlock_check.gd.


## Is `buyer` (a PilotProfile or a TeamState) unlocked right now? False for
## anything else, for a missing buyer and whenever the option is off.
static func is_unlocked(buyer: Object) -> bool:
	if not Game.unlock_everything or buyer == null:
		return false
	if buyer is PilotProfile:
		return (buyer as PilotProfile).is_human
	if buyer is TeamState:
		return (buyer as TeamState).admiral == "human"
	return false
