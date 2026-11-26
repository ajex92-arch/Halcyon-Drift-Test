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

## T-125: the numbers of the return flash (the outline flash of the player's own ship when the camera comes back to it:
## CameraRig starts it, ShipVisual draws it). One place, so the look is tuned here and nowhere else.
##   secs         how long the outline takes to ease back to normal (seconds)
##   width        the outline's width at the start (pixels; the human's ship is 2.2 normally)
##   glow_alpha   how strong the faint white glow round the ship is at its start
##   glow_px      how wide the glow is (pixels)
##   glow_secs    how long the glow lasts (seconds)
##   min_gap_ms   the least time between two pulses (milliseconds)
##   centre_frac  a Space tap only pulses when the ship is further than this share of the view's width from the screen's centre
##   steps        how many steps the outline's fade is drawn in (the ship's kept picture is drawn again at each step)
const RETURN_FLASH := {
	"secs": 0.45, "width": 5.0, "glow_alpha": 0.35, "glow_px": 10.0, "glow_secs": 0.15,
	"min_gap_ms": 1000, "centre_frac": 0.15, "steps": 16,
}

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
	{"name": "Undock slide", "file": "scripts/world/rts_fx.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "world", "since": "RT3", "today": false,
		"note": "A bought small ship is drawn moving from the middle of the mothership to its launch spot over 1.5 s. A movement drawn once, not a flash."},
	{"name": "Warp streak", "file": "scripts/world/rts_fx.gd", "kind": "streak", "rate": 0, "min_gap_ms": 0, "where": "world", "since": "RT3", "today": false,
		"note": "A bright head with a trail runs from the map's edge to a capital ship's warp spot over 4 s, and a ring opens round the ship when it appears. It grows, moves and fades once, with no blinking."},
	{"name": "Attacked frame", "file": "scripts/ui/rts/army_cards.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "RT6", "today": false,
		"note": "An army card whose squadrons are under attack wears a steady danger-colour frame with the triangle (ArmyCard draws it from the card's danger flag, set and cleared with the state, 4 times a second at most). It never blinks and nothing times it."},
	{"name": "wing confirm", "file": "scripts/ui/wing_strip.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 334, "where": "screen", "since": "wingmen", "today": false,
		"note": "When a wing order is carried out, the border of the wing strip's chips lights ICE white for one 120 ms pulse (WingStrip.PULSE_MS). It is never repeated, and a new order less than 334 ms after the last one gives no pulse (WingStrip.PULSE_GAP_MS), so it flashes at most three times a second."},
	{"name": "Order ring", "file": "scripts/ui/rts/order_feedback.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 334, "where": "screen", "since": "RT6", "today": false,
		"note": "One ring shrinks from 10 to 4 screen pixels over 0.25 s at the point of a Move or Attack when it is sent, once for each order. A ring that would begin less than 334 ms after the last one is not drawn (OrderFeedback.RING_GAP_MS), so it appears at most three times a second. The grey x of a click that did nothing is steady for 0.8 s and does not blink."},
	{"name": "Order refused mark", "file": "scripts/ui/rts/order_feedback.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 334, "where": "screen", "since": "RT6", "today": false,
		"note": "The danger triangle stands at the point of an order the queue refused, steady for 0.8 s (OrderFeedback.BAD_S), one at a time. A triangle that would begin less than 334 ms after the last one is not drawn (OrderFeedback.RING_GAP_MS), so it appears at most three times a second. It does not blink."},
	{"name": "Order line", "file": "scripts/ui/rts/order_feedback.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "RT6", "today": false,
		"note": "When a Move or Attack is carried out, a dashed light line runs from each squadron that took it to the point, with a dot at the end, steady for 1.5 s (OrderFeedback.LINE_S) and then gone. It is drawn once for each order and never blinks."},
	{"name": "Alert ring pulse", "file": "scripts/ui/minimap.gd", "kind": "pulse", "rate": 2.0, "min_gap_ms": 0, "where": "screen", "since": "RT6", "today": false,
		"note": "A new alert's ring on the minimap pulses twice at 2 Hz (on for a quarter second, off for a quarter, from the tick the alert was raised: Minimap.ALERT_PULSES) and then holds steady, so two flashes in one second and never more than the 3 a second the rule allows. The minimap draws five times a second, so a pulse is drawn in about two pictures."},
	{"name": "Camera return flash", "file": "scripts/camera/camera_rig.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 1000, "where": "world", "since": "T-125", "today": false,
		"note": "When the camera comes back to your ship (Space tapped while the ship is off centre, the launch jump, the Centre button, an Admiral switching to follow mode) your ship's outline turns ICE white, widens to 5 pixels and eases back over 0.45 s, with a faint white glow for the first 0.15 s (RETURN_FLASH). One pulse per return, at most one a second, on your screen only; the hit flash wins if both happen; it can be switched off in the pause menu."},
	{"name": "Group double-tap flash", "file": "scripts/ui/minimap.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 334, "where": "screen", "since": "RT7", "today": false,
		"note": "In field mode (the Admiral flying with the view closed) a double tap of a group's key draws one ring round the minimap dot of each squadron of that group for 0.3 s (Minimap.GROUP_FLASH_S), steady, once for each double tap. A flash that would begin less than 334 ms after the last one is not drawn (Minimap.GROUP_FLASH_GAP_MS), so it appears at most three times a second. It is drawn on the minimap's own 5 Hz redraw and nothing times it: no tween, no timer. Docked or with the view open the double tap centres the camera instead and draws no ring."},
	{"name": "Ship readout danger edge", "file": "scripts/ui/ship_status.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "RT7", "today": false,
		"note": "While the Admiral's ship is under fire (it took a hull hit under 3 s ago, ShipStatus.FIRE_EDGE_S) the ship readout wears a steady 2 px edge in the danger colour (Palette.DANGER, the colour of the army card's attacked frame), the mark of the Under Fire! alert. It is set from the ship's state in _process, never blinks and nothing times it."},
	{"name": "Warning mark pulse", "file": "scripts/ui/ship_ring.gd", "kind": "pulse", "rate": 2.0, "min_gap_ms": 0, "where": "screen", "since": "S1", "today": false,
		"note": "In its last second before it arrives, the nearest torpedo's arrow round your ship's ring pulses between 60% and 100% strength at 2 Hz (Blink.pulse_at); the danger sign beside the ring stays steady. Steady at full strength under reduced motion. Never above the 3 a second the rule allows."},
	{"name": "Energy empty pulse", "file": "scripts/ui/ship_ring.gd", "kind": "pulse", "rate": "per event", "min_gap_ms": 1000, "where": "screen", "since": "rulewarn", "today": false,
		"note": "When the battery cannot pay your cheapest gun, one pulse of 120 ms (480 ms under reduced motion) lights a full circle on your ship's ring with the danger sign below the ship, in the danger colour (Palette.DANGER), with its own beep. At most one pulse a second (ShipRing.ENERGY_GAP), so never above the 3 a second the rule allows, and it does not blink."},
	{"name": "Ring hit notch", "file": "scripts/ui/ship_ring.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "S1", "today": false,
		"note": "When your ship is hit by a shooter that is off the screen, a short notch on its ring shows the bearing and fades out over 1.0 s of match time. A fade, once for each hit; it does not blink."},
	{"name": "Target card zone flash", "file": "scripts/ui/target_card.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 334, "where": "screen", "since": "S1", "today": false,
		"note": "When a shield zone of your target breaks, that side's bar on the target card flashes toward ICE and fades over 0.4 s, once for each break. A flash that would begin less than 334 ms after the card's last one is not drawn (TargetCard.FLASH_GAP), so it appears at most three times a second. Never red, and it does not blink."},
	{"name": "hit markers", "file": "scripts/ui/hit_markers.gd", "kind": "hit", "rate": "per event", "min_gap_ms": 334, "where": "screen", "since": "S7A", "today": false,
		"note": "A shot of the human's own ship that lands draws a small cross, at the pointer for a small craft and at the struck side of anything bigger: ICE for a hit the shields took, AMBER for one that reached the hull, a larger CINDER one when it broke a shield zone. It fades out over 0.4 s of match time and never blinks. A marker that would start less than 334 ms after the last one is not drawn (HitMarkers.GAP_MS), except that a zone marker replaces a weaker one inside that gap, so it appears at most three times a second."},
	{"name": "edge wedges", "file": "scripts/ui/hud_alarm.gd", "kind": "slide", "rate": 0, "min_gap_ms": 0, "where": "screen", "since": "S7A", "today": false,
		"note": "When your own mothership is attacked, a steady wedge in the danger colour (with the danger sign) stands at the screen edge toward it while it is off the screen: steady while the attack goes on, then for 8 s more (HudAlarm.WEDGE_LIFE_S), fading out once in its last second. At most four are drawn; more fold into the last as a +N count. It never blinks and nothing times it: it is drawn from the match clock."},
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
