class_name PracticeSwitches
extends RefCounted
## WHAT THIS IS: the practice range's four switches (waves, camps, money, cooldowns) as plain
## data: the eight switch words and the one table of numbers they use, and the words of the
## refusals. Nothing else in the game keeps a second copy of these numbers.
##
## HOW IT WORKS: constants only. A switch is named by one of the words in WORDS; the panel
## sends it as one order (PracticeOrders) and the world carries it out at the start of the
## next tick (PracticeActions). Every number here is a tuning knob of the range alone: a normal
## match never reads any of them, so retuning one changes nothing outside the range.
##
## WHO USES IT: PracticeOrders (the checks), PracticeActions (the changes), PracticePanel (the
## buttons and their words), MinionDirector and JungleDirector (the refusal texts), OrderKinds
## (the refusal texts, mapped to codes) and tests/practice_switch_check.gd.

# --- the eight switch words -----------------------------------------------------------------
## Hold the free waves, or let them run again (the order's `on` is 1 or 0).
const FREEZE := "freeze"
## Send one wave now for both teams.
const WAVE := "wave"
## Bring every jungle camp back at once.
const CAMPS := "camps"
## Bring back the one camp whose id the order carries.
const CAMP_NEAR := "camp_near"
## Add credits to the human's own purse.
const MONEY := "money"
## Add credits to the human team's treasury (the Admiral seat only).
const TREASURY := "treasury"
## Make the human's own ship's long timers ready now.
const CD_RESET := "cd_reset"
## Keep the human's timers ready every tick while on (the order's `on` is 1 or 0).
const CD_AUTO := "cd_auto"
## Every switch word, in the order the panel shows them.
const WORDS := [FREEZE, WAVE, CAMPS, CAMP_NEAR, MONEY, TREASURY, CD_RESET, CD_AUTO]
## The switches that are toggles: their order carries `on`.
const TOGGLES := [FREEZE, CD_AUTO]

# --- the numbers -----------------------------------------------------------------------------
## Credits one money press adds to the human's purse.
const CREDITS_PER_PRESS := 5000.0
## Credits one treasury press adds to the human team's treasury.
const TREASURY_PER_PRESS := 5000.0
## The most the purse or the treasury may hold after a press.
const LIMIT := 100000.0
## Send one wave is refused while a team has this many free-wave minions alive (three waves).
const WAVE_REFUSE_AT := 63
## The least number of ticks between two Send one wave presses (one second).
const SEND_GAP_TICKS := 60
## The least time (seconds) left to the next wave when the waves run again.
const UNFREEZE_FLOOR := 3.0
## The farthest (world units) a camp may be from the centre of the screen to count as the nearest.
const CAMP_REACH := 4000.0
## A weapon timer counts for the reset when its gun waits this long (seconds) or longer between shots.
const WEAPON_FLOOR := 1.0
## The respawn countdown (seconds) a dead pilot is given by a reset.
const DEAD_RESPAWN := 1.0
## How many ticks apart No cooldowns resets the timers (1: every tick).
const RESET_EVERY_TICKS := 1
## The panel's width (pixels at HUD scale 1).
const PANEL_WIDTH := 220
## The height (pixels) of each button on the panel.
const BUTTON_HEIGHT := 28
## The size (pixels) of the collapsed tab.
const TAB_SIZE := 32
## How long (seconds) a refused press shows its reason under its button.
const REFUSAL_SECONDS := 2.0
## The colour of the ring a respawned camp shows (drawing only).
const PULSE_COLOR := Color(0.85, 0.92, 1.0, 0.9)
## The radius (world units) of that ring.
const PULSE_RADIUS := 260.0
## How long (seconds) that ring lasts.
const PULSE_LIFE := 0.6

# --- the refusal texts -----------------------------------------------------------------------
## Any practice order in a match that is not a practice range.
const TEXT_ONLY_RANGE := "Only in the practice range"
## The purse already holds the limit.
const TEXT_PURSE_FULL := "Purse full"
## The treasury already holds the limit.
const TEXT_TREASURY_FULL := "Treasury full"
## A team already has too many free-wave minions alive.
const TEXT_WAVES_FULL := "Too many minions on the lanes"
## The press came inside the gap after the last one.
const TEXT_WAIT := "Wait a second"
## No camp the order names (or none in reach of the screen centre).
const TEXT_NO_CAMP := "No camp near the centre of the screen"
## The match has no jungle camps (the "no-jungle" switch).
const TEXT_NO_JUNGLE := "No jungle camps in this match"
## There is no timer to reset (no ship, or a pilot who is not dead and has no ship).
const TEXT_NOTHING_TO_RESET := "Nothing to reset"
