class_name FlashTable
extends RefCounted
## WHAT THIS IS: the list of every effect in the game that changes brightness over time (a hit
## flash, a pulsing glow, a blink), with how fast it goes and where its code is. The rule is that
## no new effect flashes more than three times a second; this list is how the rule is checked.
##
## HOW IT WORKS: one row per effect, a Dictionary:
##   name        what the player sees
##   file        the script that draws or times it (under remake/)
##   kind        "blink" (on and off), "pulse" (smooth up and down), "hit" (a flash after an event),
##               "slide" (a fade or a tint that is not a flash) or "streak" (a trail); slide and streak
##               have rate 0
##   rate        blinks a second for a steady blink or pulse, 0 for a slide or streak, or
##               "per event" for an effect that follows something happening
##   min_gap_ms  for a per-event row: the least time between two flashes of the same thing that the
##               code guarantees (0: none, it follows the events as fast as they come)
##   where       "screen" (HUD) or "world" (the map)
##   since       the stage that added it ("today" for the effects the game had when the rule began)
##   note        what it does in plain words
##   today       true for an effect that is allowed to stay as it is although it may break the rule
## tests/flash_check.gd fails any row above three a second, or per-event with a gap under 334 ms,
## that is not marked today, and fails any script that uses a tween, a timer or an animation
## player that is neither in this table nor on its short list of timers that draw nothing. A stage
## that adds an effect adds its row here (Blink is the helper that cannot go above three a second).
## The unit hit flash can pass three a second under fire: that is reported, not failed.
##
## WHO USES IT: tests/flash_check.gd; stages that add an effect.

## The rows. Edit this list when an effect is added, changed or removed.
const ROWS := [
	{"name": "Unit hit flash", "file": "scripts/entities/unit.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "The outline of a ship or unit turns toward white and thickens for 0.09 s after each hit (Palette.HIT_FLASH); it starts again at every hit, so a unit under rapid fire flashes as fast as it is hit."},
	{"name": "Ship hit flash", "file": "scripts/entities/ship.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for ships."},
	{"name": "Minion hit flash", "file": "scripts/entities/minion.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for minions."},
	{"name": "Turret hit flash", "file": "scripts/entities/turret.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for turrets."},
	{"name": "Defense post hit flash", "file": "scripts/entities/defense_post.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for defense posts."},
	{"name": "Derelict hit flash", "file": "scripts/entities/derelict.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for derelict monsters."},
	{"name": "Mining drone hit flash", "file": "scripts/entities/mining_drone.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for mining drones."},
	{"name": "Repair bay hit flash", "file": "scripts/entities/repair_bay.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for repair bays."},
	{"name": "Repair drone hit flash", "file": "scripts/entities/repair_drone.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for repair drones."},
	{"name": "Snub-fighter hit flash", "file": "scripts/entities/snub_fighter.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for carrier snub fighters."},
	{"name": "Ward hit flash", "file": "scripts/entities/ward.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for wards."},
	{"name": "Pilot extractor hit flash", "file": "scripts/features/pilot_extractor.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "A diamond that draws white while it flashes from a hit (a rule variant, off in the standard rules)."},
	{"name": "Supply drone hit flash", "file": "scripts/features/supply_drone.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Counts the unit hit flash down for supply drones."},
	{"name": "Mothership hit flash", "file": "scripts/entities/mothership.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "The same flash at half strength (Palette.HIT_FLASH_MOTHER), because its long outline would glare."},
	{"name": "Shield zone break flash", "file": "scripts/entities/shield_zones.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "A shield zone that has just broken flashes for 0.4 s. A zone can break again only after it has recharged."},
	{"name": "Shield zone arc on the ship readout", "file": "scripts/ui/ship_status.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "screen", "since": "today", "today": true,
		"note": "Draws the broken zone's arc in red, fading over the same 0.4 s (Palette.CINDER, a candidate for the danger colour)."},
	{"name": "Muzzle flash", "file": "scripts/entities/gun_kick.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "The tip of a gun is drawn nearly white for 0.04 s after each shot (GunKick.FLASH_TIME); it follows the gun's fire rate."},
	{"name": "Vhorr vein pulse", "file": "scripts/entities/cinder_paint.gd", "kind": "pulse", "rate": 0.72, "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "The glowing veins of a Vhorr ship brighten and dim (PULSE_RATE 0.0045 radians a millisecond, about 0.7 times a second)."},
	{"name": "Torpedo plume pulse", "file": "scripts/world/projectiles_draw.gd", "kind": "pulse", "rate": 2.23, "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "The motor dot of a torpedo grows and shrinks (14 radians a second, about 2.2 times a second). A size pulse, not a brightness one."},
	{"name": "Effect rings", "file": "scripts/world/effects.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "Explosions and special abilities (Ping, Jam, repair) send out a ring that grows and fades in 0.25 to 0.9 s; at most 60 at once."},
	{"name": "Recall ring pulse", "file": "scripts/features/recall.gd", "kind": "pulse", "rate": 0.95, "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "While a ship recalls, the ring round it swells and dims (6 radians a second, about once a second). A rule variant, off in the standard rules."},
	{"name": "Order marker pulse", "file": "scripts/features/command_orders.gd", "kind": "pulse", "rate": 1.43, "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "A map marker of an Admiral order breathes (9 radians a second, about 1.4 times a second). Used by the extra Admiral orders, which are off in the standard rules."},
	{"name": "Kill feed fade", "file": "scripts/ui/hud_feed.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "today", "today": true,
		"note": "A line of the feed fades out over its last 1.5 s (modulate by age). A fade, not a flash."},
	{"name": "Pop-up hint fade", "file": "scripts/ui/hud_toast.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "today", "today": true,
		"note": "The pop-up hint fades in and out over 0.6 s. A fade, not a flash."},
	{"name": "Salvage gold tint", "file": "scripts/features/salvage_core.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "world", "since": "today", "today": true,
		"note": "A ship carrying a salvage core is tinted gold while it carries it (set and cleared with the state, not on a timer). Not a flash."},
]

## Scripts that use a tween, a timer or an animation player and are not in ROWS because they draw
## nothing that changes brightness: path -> why.
const NOT_EFFECTS := {
	"scripts/main.gd": "A 1.5 second timer that quits a headless run after the summary is printed; it draws nothing.",
}


## The rows (a copy, so a test can read them without changing the list).
static func rows() -> Array:
	return ROWS.duplicate(true)


## The row for script `file` (a path like "scripts/entities/unit.gd"), or {} when there is none.
static func row_for(file: String) -> Dictionary:
	for r: Dictionary in ROWS:
		if String(r["file"]) == file:
			return r
	return {}
