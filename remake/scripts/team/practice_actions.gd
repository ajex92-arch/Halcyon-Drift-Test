class_name PracticeActions
extends RefCounted
## WHAT THIS IS: what the practice range's switches change in the world, and the only place
## that changes it: money onto a purse or the treasury, the free waves, the camps and the
## human's own timers. Nothing else in the game touches a purse, a treasury, a timer, a minion
## or a camp on a switch's behalf. PracticeOrders calls it when a PRACTICE order is carried out,
## on the start of a tick.
##
## HOW IT WORKS: static functions that take the world. run() picks the function of a switch
## word and gives back "" when it worked or the refusal text. Money is added straight onto the
## purse (PilotProfile.credits) or the team's treasury (TeamState.treasury) and never through
## earn(): the difficulty does not scale it, no payment message is sent, and it does not count
## as earned, so the stats, the catch-up pay, the running bounty and the economy counters never
## see it. Both are held at PracticeSwitches.LIMIT. The computer pilots and the computer Admirals
## are never touched.
##
## WHO USES IT: PracticeOrders (the handler) and the range's own tick (PracticeRange).

## Carry out switch `sw` in world `w`. `on` is the toggles' state and `camp` the camp id of the
## nearest-camp switch. Returns "" or the refusal text.
static func run(w: World, sw: String, on: bool, camp: String) -> String:
	match sw:
		PracticeSwitches.FREEZE:
			w.minion_director.set_frozen(on)
			return ""
		PracticeSwitches.WAVE:
			return w.minion_director.send_one_wave()
		PracticeSwitches.CAMPS:
			return w.jungle_director.respawn_all()
		PracticeSwitches.CAMP_NEAR:
			return w.jungle_director.respawn_camp(camp)
		PracticeSwitches.MONEY:
			return add_credits(w)
		PracticeSwitches.TREASURY:
			return add_treasury(w)
		PracticeSwitches.CD_RESET:
			return reset_cooldowns(w)
		PracticeSwitches.CD_AUTO:
			w.practice_range.no_cooldowns = on
			return ""
	return OrderKinds.TEXT_UNBUILT


## Is there nothing for the cooldown reset to take hold of? True unless the human is dead (the
## respawn countdown) or has a live ship (its timers).
static func nothing_to_reset(w: World) -> bool:
	var h := w.human
	if h == null:
		return true
	if h.state == "dead":
		return false
	return h.ship == null or not is_instance_valid(h.ship) or not h.ship.alive


## Make the human's own timers ready: the hull special, the energy and shield-focus locks and
## every gun timer whose gun waits PracticeSwitches.WEAPON_FLOOR seconds or more between shots
## (a quick gun keeps its fire rate). The special's running effect, the ace timer and every
## effect already going are not touched. A dead human's respawn countdown is cut to
## PracticeSwitches.DEAD_RESPAWN. Nobody else's ship or pilot is ever touched. Returns "" or
## "Nothing to reset" (no ship, and not dead).
static func reset_cooldowns(w: World) -> String:
	if nothing_to_reset(w):
		return PracticeSwitches.TEXT_NOTHING_TO_RESET
	var h := w.human
	if h.state == "dead":
		h.respawn_t = minf(h.respawn_t, PracticeSwitches.DEAD_RESPAWN)
		return ""
	var ship := h.ship
	ship.special_cd = 0.0
	ship.energy_cd = 0.0
	ship.focus_cd = 0.0
	for m: WeaponMount in ship.mounts:
		if weapon_interval(m) >= PracticeSwitches.WEAPON_FLOOR:
			m.cd = 0.0
			## A run gun (the Bomber's torpedo) keeps its reload in its own counter and writes `cd`
			## from it every tick, so the counter is cleared too or `cd` would come straight back.
			if m.run != null:
				m.run.reload = 0
	return ""


## The seconds gun `m` waits between shots, from its weapon's `rate` (shots a second): 1 / rate.
## A weapon with no rate (a beam) counts as 0, so it is never taken as a long timer. The Bomber's
## torpedo has a rate and a run gun's reload counter, and the reset clears both.
static func weapon_interval(m: WeaponMount) -> float:
	var rate := float(m.def.get("rate", 0.0))
	return 1.0 / rate if rate > 0.0 else 0.0


## Add one press of credits to the human's own purse, never above the limit. Returns "" or "Purse full".
static func add_credits(w: World) -> String:
	var h := w.human
	if h == null:
		return OrderKinds.TEXT_SEAT
	if h.credits >= PracticeSwitches.LIMIT:
		return PracticeSwitches.TEXT_PURSE_FULL
	var after := minf(PracticeSwitches.LIMIT, h.credits + PracticeSwitches.CREDITS_PER_PRESS)
	if w.practice_range != null:
		w.practice_range.money_given += after - h.credits
	h.credits = after
	return ""


## Add one press of credits to the human team's treasury, never above the limit. Returns "" or "Treasury full".
static func add_treasury(w: World) -> String:
	if w.human == null:
		return OrderKinds.TEXT_SEAT
	var ts: TeamState = w.teams[w.human.team]
	if ts.treasury >= PracticeSwitches.LIMIT:
		return PracticeSwitches.TEXT_TREASURY_FULL
	var after := minf(PracticeSwitches.LIMIT, ts.treasury + PracticeSwitches.TREASURY_PER_PRESS)
	if w.practice_range != null:
		w.practice_range.money_given += after - ts.treasury
	ts.treasury = after
	return ""
