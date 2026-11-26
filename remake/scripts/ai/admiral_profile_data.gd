class_name AdmiralProfileData
extends RefCounted
## WHAT THIS IS: the numbers and switches of the computer Admiral, in one table. Every number the
## Admiral's parts used to carry (the drone line, the timers, the siege, the mothership mover, the
## yard's buying, the field trips) and every switch (a part on or off) is a row here, with its value in
## each of the three profiles, the range a command line may set it to, and whether the code reads it
## yet. The rows of later builds (the team view, the fitted strength, the memory times, the event
## reactions, the log's feed lines) are here too, off or at today's value, so a later build only wires
## them and a profile never needs a new key.
##
## HOW IT WORKS: TABLE maps a key to [standard, v0, weak, low, high, wired, note]. Every value is a
## whole number: the thousandths of the unit the key names (a key ending _s is seconds, so 90000 is 90
## seconds; a fraction such as 0.6 is 600; a credit price or a world distance is also in thousandths:
## 500000 is 500 credits), and a count is in thousandths too (6000 is 6). A switch is 0 or 1. The
## three profiles are the columns:
##   standard  the Admiral as played: today's numbers, and the new parts as their sign-off says
##             (team_view and fitted_strength stay 0 until their switch-on commits);
##   v0        "before RT5": today's Admiral with every new switch off (it never changes after this build);
##   weak      the weak test Admiral (--admiral-ai=weak): a plan step only every 90 s, no repair bays,
##             wards, sieges, mothership moves or fleet buying, and the feature modules' AIs stay off.
## "wired" is true when some part of scripts/ai reads the key now; tests/admiral_profile_check.gd proves
## that (the key's name is in the source of a file other than this one) and that an unknown key or a
## value out of [low, high] is refused.
##
## The four presets (PRESETS and PRESET_PLANS, at the end of the file) are the standard column with a few
## numbers changed, one fixed plan each, for the deputy (a computer Admiral that helps a human Admiral)
## and for matches between computer Admirals (--admiral-profile=0:attack;1:defend). A preset has no
## column in TABLE: it names the keys it moves and their new values, and the row ranges still hold.
##   balanced  nothing changed: exactly the standard Admiral, research in the standard order;
##   attack    more Lance and Bomber squadrons, fewer big ships between squadrons, the fleet filled earlier,
##             a smaller reserve, and the weapon research first;
##   defend    mostly Fighter squadrons, repair bays and wards earlier and from less money, a bigger
##             reserve, and the repair, shield and platform research first (turrets themselves are only
##             rebought where one was lost; the platform research makes the standing ones stronger);
##   economy   more mining drones sooner, the fleet filled later, the biggest reserve, and the income
##             research first.
## PRESET_PLANS holds the research order of each preset: steps [kind, id] that AdmiralPlan reads in front
## of its own list. The numbers are hand-set starting points, one fixed plan per preset: nothing mixes
## them during a match and nothing tunes them by machine.
##
## WHO USES IT: AdmiralProfile (the record of one team) and the constants of RtsHulls, AdmiralSiege,
## AdmiralMothershipMover, AdmiralField and AdmiralWeak, which are derived from the standard column.

## The profile names, in column order (a profile's column in TABLE is its index here).
const PROFILES := ["standard", "v0", "weak"]
## The columns of a TABLE row.
const C_STANDARD := 0
const C_V0 := 1
const C_WEAK := 2
const C_LOW := 3
const C_HIGH := 4
const C_WIRED := 5
const C_NOTE := 6

const TABLE := {
	# --- the think loop and its timers -------------------------------------------------------------
	"think_start_s": [500, 500, 500, 0, 10000, true, "seconds to the first think of team 0 (team 1 adds think_stagger_s)"],
	"think_stagger_s": [500, 500, 500, 0, 10000, true, "seconds the second team's first think comes after the first team's"],
	"think_gap_s": [1000, 1000, 1000, 100, 10000, true, "seconds between two thinks"],
	"ward_first_s": [30000, 30000, 30000, 0, 600000, true, "seconds to the first ward try"],
	"ward_gap_s": [45000, 45000, 45000, 1000, 600000, true, "seconds between two ward tries"],
	"ward_treasury": [300000, 300000, 300000, 0, 100000000, true, "treasury a ward try needs (credits)"],
	"waypoint_first_s": [60000, 60000, 60000, 0, 600000, true, "seconds to the first waypoint"],
	"waypoint_gap_s": [75000, 75000, 75000, 1000, 600000, true, "seconds between two waypoints"],
	"waypoint_defend_s": [1000, 1000, 1000, 100, 600000, true, "seconds between waypoints while the base is attacked"],
	"bay_first_s": [0, 0, 0, 0, 600000, true, "seconds to the first repair bay try"],
	"bay_gap_s": [40000, 40000, 40000, 1000, 600000, true, "seconds between two repair bay tries"],
	"bay_spare": [500000, 500000, 500000, 0, 100000000, true, "spare credits a repair bay try needs"],
	# --- the drone line ------------------------------------------------------------------------------
	"drone_base": [6000, 6000, 6000, 0, 20000, true, "drones wanted at the start (a count)"],
	"drone_every_s": [75000, 75000, 75000, 1000, 3600000, true, "seconds of match time per extra drone wanted"],
	"drone_floor": [600, 600, 600, 0, 1000, true, "fraction of the wanted drones below which a drone jumps every queue"],
	"drone_min": [4000, 4000, 4000, 0, 20000, true, "drones below which a drone jumps every queue (a count)"],
	"drone_cost": [200000, 200000, 200000, 0, 100000000, true, "treasury a first-rank drone order needs (credits)"],
	"drone_spare": [200000, 200000, 200000, 0, 100000000, true, "spare credits a second-rank drone order needs"],
	# --- the build plan ------------------------------------------------------------------------------
	"plan_gap_s": [0, 0, 90000, 0, 3600000, true, "seconds between two plan steps (0 = none)"],
	"plan_reserve": [500, 500, 500, 0, 1000, true, "fraction of the next plan step's price kept back from spare spending"],
	"plan_lookahead": [4000, 4000, 4000, 1000, 50000, true, "unfinished plan steps the Admiral may look at (a count)"],
	# --- the waypoint, repair bays and wards -----------------------------------------------------------
	"waypoint_frac": [550, 550, 550, 0, 1000, true, "how far down the pushed lane the waypoint goes (a fraction)"],
	"waypoint_late_frac": [660, 660, 660, 0, 1000, true, "...and once the wave is past the middle late in the match"],
	"waypoint_late_s": [1200000, 1200000, 1200000, 0, 36000000, true, "match seconds after which the late waypoint may be used"],
	"waypoint_late_front": [600, 600, 600, 0, 1000, true, "how far down the lane our front must be for the late waypoint (a fraction)"],
	"bay_lane_frac": [330, 330, 330, 0, 1000, true, "how far down a lane a repair bay goes (a fraction)"],
	"bay_off": [900000, 900000, 900000, 0, 20000000, true, "world units a repair bay is placed off the lane line"],
	"bay_cover": [1500000, 1500000, 1500000, 0, 20000000, true, "world units within which a bay of ours covers a spot"],
	"ward_cover": [1500000, 1500000, 1500000, 0, 20000000, true, "world units within which a ward of ours covers an entrance"],
	# --- the parts' switches ---------------------------------------------------------------------------
	"bays": [1, 1, 0, 0, 1, true, "switch: place repair bays"],
	"wards": [1, 1, 0, 0, 1, true, "switch: place wards"],
	"siege": [1, 1, 0, 0, 1, true, "switch: declare sieges"],
	"mover": [1, 1, 0, 0, 1, true, "switch: move the mothership"],
	"field": [1, 1, 1, 0, 1, true, "switch: take the field in the Admiral's own ship (the --no-admiral-field option also turns it off)"],
	"is_weak": [0, 0, 1, 0, 1, true, "marks the weak test Admiral: the feature modules' AIs stay off for it"],
	# --- the siege ---------------------------------------------------------------------------------------
	"siege_start_s": [1200000, 1200000, 1200000, 0, 36000000, true, "match seconds before which no siege is declared"],
	"siege_min_healthy": [2000, 2000, 2000, 0, 50000, true, "healthy big ships a siege needs (a count)"],
	"siege_healthy_hull": [500, 500, 500, 0, 1000, true, "hull fraction over which a big ship is healthy"],
	"siege_power_edge": [1200, 1200, 1200, 0, 20000, true, "times the enemy fleet strength ours must be to declare a siege"],
	"siege_ms_hurt": [600, 600, 600, 0, 1000, true, "enemy mothership hull fraction at or under which the edge is not needed"],
	"siege_gather_count": [2000, 2000, 2000, 0, 50000, true, "big ships massed that start the assault (a count)"],
	"siege_gather_time_s": [45000, 45000, 45000, 0, 3600000, true, "seconds of gathering after which whoever is there attacks"],
	"siege_gather_radius": [3000000, 3000000, 3000000, 0, 100000000, true, "world units from the staging point that count as massed"],
	"siege_contact_dist": [3000000, 3000000, 3000000, 0, 100000000, true, "world units from the enemy hull that count as contact"],
	"siege_stall_time_s": [120000, 120000, 120000, 0, 3600000, true, "seconds after contact at which the stall check is made"],
	"siege_stall_frac": [150, 150, 150, 0, 1000, true, "hull fraction the enemy mothership must have lost by then"],
	"siege_no_contact_s": [300000, 300000, 300000, 0, 3600000, true, "seconds of assault with no contact after which it stalls"],
	"siege_cooldown_s": [60000, 60000, 60000, 0, 3600000, true, "seconds after a call-off before another siege"],
	"siege_follow_dist": [4000000, 4000000, 4000000, 0, 100000000, true, "world units the enemy mothership may be off the siege lane"],
	"siege_parked_dist": [2500000, 2500000, 2500000, 0, 100000000, true, "world units from its home spot at which the enemy mothership counts as parked up a lane"],
	# --- the mothership mover -------------------------------------------------------------------------------
	"advance_frac": [350, 350, 350, 0, 1000, true, "how far up the mid lane the mothership advances (a fraction)"],
	"move_gap_s": [120000, 120000, 120000, 0, 3600000, true, "seconds between two advance moves"],
	"fallback_hull": [500, 500, 500, 0, 1000, true, "hull fraction under which the mothership falls back"],
	"fallback_far": [2000000, 2000000, 2000000, 0, 100000000, true, "world units from home beyond which a hurt mothership falls back"],
	"advance_dist": [2500000, 2500000, 2500000, 0, 100000000, true, "world units the advance spot must be away to go"],
	"mover_edge": [1000, 1000, 1000, 0, 20000, true, "times the enemy fleet strength ours must be to advance"],
	# --- field trips --------------------------------------------------------------------------------------------
	"field_min_down": [2000, 2000, 2000, 0, 50000, true, "dead pilots that call the Admiral out (a count)"],
	"field_min_trip_s": [20000, 20000, 20000, 0, 3600000, true, "seconds a trip lasts at least"],
	"field_cooldown_s": [15000, 15000, 15000, 0, 3600000, true, "seconds after a trip before the next launch"],
	# --- the yard's buying -------------------------------------------------------------------------------------------
	"buys": [1, 1, 0, 0, 1, true, "switch: the computer Admiral buys fleet ships (the master switch)"],
	"holds_head": [1, 1, 1, 0, 1, true, "switch: hold an unfundable head of the list"],
	"saves_capital": [1, 1, 1, 0, 1, true, "switch: save for a capital ship"],
	"repeats": [1, 1, 1, 0, 1, true, "switch: keep Fighter squadrons on repeat below the fill target"],
	"head_wait_s": [20000, 20000, 20000, 0, 3600000, true, "seconds of income an item at the head of the list may wait for"],
	"income_window_s": [60000, 60000, 60000, 1000, 3600000, true, "seconds the income is measured over"],
	"fill_t1_s": [360000, 360000, 360000, 1000, 36000000, true, "first fill time (match seconds)"],
	"fill_t2_s": [720000, 720000, 720000, 1000, 36000000, true, "second fill time"],
	"fill_t3_s": [1080000, 1080000, 1080000, 1000, 36000000, true, "third fill time"],
	"fill_p1_pct": [30000, 30000, 30000, 0, 100000, true, "percent of the fleet limit wanted at the first fill time"],
	"fill_p2_pct": [70000, 70000, 70000, 0, 100000, true, "...at the second"],
	"fill_p3_pct": [90000, 90000, 90000, 0, 100000, true, "...at the third"],
	"reserve": [300000, 300000, 300000, 0, 100000000, true, "credits kept back from fleet buying outside a saving goal"],
	"saving_lapse_s": [180000, 180000, 180000, 0, 3600000, true, "seconds after which a saving goal is given up"],
	"per_corvette": [3000, 3000, 3000, 1000, 20000, true, "squadrons per corvette (a count)"],
	"per_frigate": [2000, 2000, 2000, 1000, 20000, true, "squadrons per frigate (a count)"],
	"special_one_in": [3000, 3000, 3000, 1000, 20000, true, "one squadron in this many is a Lance or Bomber squadron (a count)"],
	"capital_max_pct": [34000, 34000, 34000, 0, 100000, true, "most capital ships, as a percent of the fleet limit"],
	# --- the decision log -----------------------------------------------------------------------------------------------------
	"decision_log": [1, 0, 1, 0, 1, true, "switch: write the decision log when --admiral-log=<file> names a file (changes no play)"],
	"log_feed": [0, 0, 0, 0, 1, true, "switch: the team's own Admiral's big lines also go to the team feed"],
	# --- the team view (RT5 build 2) and the later builds (declared now, off or at today's value; wired false until their build) ---
	"team_view": [0, 0, 0, 0, 1, true, "switch: the Admiral reads the enemy through the team view (what its team has seen), not the live world"],
	"fitted_strength": [0, 0, 0, 0, 1, true, "switch: the fitted strength (AdmiralStrength, with the four strength_w_ weights) replaces the size count in the siege's edge and the mothership mover's edge (RT5 build 4b; off until the lead's switch-on commit)"],
	"strength_w_squadron": [345, 345, 345, 0, 10000, true, "the fitted strength's weight of one strike squadron, in thousandths (read while fitted_strength is on; the night's fit over 600 fights, Thu 11-12)"],
	"strength_w_corvette": [1037, 1037, 1037, 0, 10000, true, "...of one corvette"],
	"strength_w_frigate": [1360, 1360, 1360, 0, 10000, true, "...of one frigate"],
	"strength_w_capital": [7258, 7258, 7258, 0, 10000, true, "...of one capital ship"],
	"memory_fade_s": [90000, 90000, 90000, 1000, 3600000, true, "seconds over which where an enemy ship is fades from 1 to 0 (read while team_view is on)"],
	"memory_stale_s": [300000, 300000, 300000, 1000, 7200000, true, "seconds a ship that is not seen still counts as existing (read while team_view is on)"],
	# --- the event reactions (RT5 build 4a; AdmiralReactions): wired, and off in every profile until the lead's switch-on commit ---
	"react_build_blocked": [0, 0, 0, 0, 1, true, "switch: react to a blocked build (a not-yet log line, a cancel of an item blocked by a missing unlock)"],
	"react_cap_full": [0, 0, 0, 0, 1, true, "switch: react to a full fleet cap (the Fighter repeat goes off and stays off while an item waits for room)"],
	"react_ship_lost": [0, 0, 0, 0, 1, true, "switch: react to lost pilots (with two or more down, the nearest free bought squadron fills in on the first dead pilot's lane)"],
	"react_under_attack": [0, 0, 0, 0, 1, true, "switch: react to an attacked mothership (the bought squadrons within reach go to the defend point, then back to their rally)"],
	"react_reach_small": [12000000, 12000000, 12000000, 0, 100000000, true, "world units from the defend point within which a bought strike squadron answers the base alarm (the pilots' own reach: PilotGoals reads the standard value)"],
	"react_reach_big": [18000000, 18000000, 18000000, 0, 100000000, true, "...and within which a bought corvette or bigger ship answers it"],
	"react_resend_dist": [2000000, 2000000, 2000000, 0, 100000000, true, "world units the defend point must have moved before a called squadron is sent to it again"],
	"react_resend_gap_s": [5000, 5000, 5000, 1000, 600000, true, "seconds between two sends to the same called squadron"],
	"react_cancel_s": [60000, 60000, 60000, 0, 3600000, true, "seconds an item blocked by a missing unlock waits before the Admiral cancels it (read while react_build_blocked is on)"],
	"win_odds_mark": [0, 0, 0, 0, 1, false, "switch: the win-odds mark (off until the fit passes its gate)"],
	# --- fleet play (RT8 build 8a; AdmiralFleet): the switch is off in every profile until the lead's switch-on commit; the numbers are the same in every profile ---
	"fleet_play": [0, 0, 0, 0, 1, true, "switch: the computer Admiral plays its fleet (goal lane, attack or retreat, help for outnumbered pilots) in a layer after the buying; off in every profile until the lead's switch-on commit"],
	"fleet_goal_hold_s": [60000, 60000, 60000, 1000, 3600000, true, "seconds the goal lane is held before it may change (a base alarm changes it at once)"],
	"fleet_retreat_below": [350, 350, 350, 0, 1000, true, "own / (own + enemy) strength in the fight area below which the fleet falls back (a fraction)"],
	"fleet_return_above": [600, 600, 600, 0, 1000, true, "...and above which it goes back in (a fraction)"],
	"fleet_lockout_s": [10000, 10000, 10000, 0, 600000, true, "seconds after a posture switch before the next one (counted from the switch)"],
	"fleet_help_pilot_first": [0, 0, 0, 0, 1, true, "switch: 0 = help goes to the lane in worst need, a human pilot's lane wins a tie (the recommended rule); 1 = a human pilot's own lane first whenever the pilot is outnumbered"],
	"fleet_mid_frac": [500, 500, 500, 0, 1000, true, "how far down a lane (a fraction) the fleet goes only with at least two groups together"],
	"fleet_together_dist": [4000000, 4000000, 4000000, 0, 100000000, true, "world units within which two groups count as together"],
	"fleet_group_join": [1500000, 1500000, 1500000, 0, 100000000, true, "world units within which squadrons count as one group"],
	"fleet_turret_reach": [2500000, 2500000, 2500000, 0, 100000000, true, "world units around an enemy lane turret that no squadron enters without our minions there"],
	"fleet_turret_pts": [2000, 2000, 2000, 0, 50000, true, "strength of one enemy lane turret in the fight area, in points of the size count (one full-hull strike craft is 1; a squadron counts one point for each of its ships)"],
	"fleet_area_radius": [6000000, 6000000, 6000000, 1000, 100000000, true, "world units around a lane's front that count as its fight area"],
	"fleet_help_edge": [1000, 1000, 1000, 0, 50000, true, "points of the size count by which the enemy ships seen must outnumber the pilots of a lane before help is sent"],
	"fleet_advance_step": [30, 30, 30, 0, 1000, true, "how far down the goal lane (a fraction) the fleet's advance point lies beyond the front of our minions"],
	# --- the outbox's cap and delay, and the talk lines (RT8 build 8b; AdmiralOutbox, AdmiralFleet): read only while fleet_play is on ---
	"fleet_cap_orders": [20000, 20000, 20000, 1000, 1000000, true, "the most orders of the Admiral's seat (carried out or refused, the reactions' included) inside fleet_cap_window_ticks; the outbox drops the orders over it, lowest priority first"],
	"fleet_cap_window_ticks": [300000, 300000, 300000, 1000, 6000000, true, "ticks (60 a second) the orders cap counts over"],
	"fleet_order_delay_ticks": [18000, 18000, 18000, 0, 600000, true, "ticks between the decision of a fleet order and its carrying out (18 = 0.3 s; 0 = at once)"],
	"fleet_talk_gap_s": [10000, 10000, 10000, 0, 600000, true, "seconds between two talk lines of the fleet on the team's feed (a line inside the gap is dropped)"],
	"fleet_unpark_s": [0, 0, 0, 0, 600000, true, "seconds a free squadron may stand parked on its Move target while an enemy ship or minion the team sees is within fleet_unpark_reach before it is sent at the nearest one (an Attack order; 0 = off, in every profile until the lead's switch-on commit; never a turret)"],
	"fleet_unpark_reach": [2600000, 2600000, 2600000, 0, 100000000, true, "world units from the centre of a parked squadron within which an enemy ship or minion the team sees now may be sent at by the unpark step (fleet_unpark_s); 0 means nothing is in reach"],
}


## The preset names, in the order a player sees them (the deputy's preset button steps through them).
const PRESET_NAMES := ["balanced", "attack", "defend", "economy"]

## What each preset changes in the standard column: preset name -> {key -> value in thousandths}. Every key is
## a row of TABLE and every value is inside that row's range. Balanced changes nothing.
const PRESETS := {
	"balanced": {},
	"attack": {
		"special_one_in": 2000, "per_corvette": 4000, "per_frigate": 3000,
		"fill_p1_pct": 40000, "fill_p2_pct": 80000, "fill_p3_pct": 95000, "reserve": 150000,
	},
	"defend": {
		"special_one_in": 4000, "bay_spare": 300000, "bay_gap_s": 30000, "ward_treasury": 200000, "reserve": 400000,
	},
	"economy": {
		"drone_base": 8000, "drone_every_s": 60000, "drone_floor": 800, "drone_min": 6000,
		"fill_p1_pct": 20000, "fill_p2_pct": 55000, "fill_p3_pct": 80000, "reserve": 500000,
	},
}

## The research order of each preset, as steps [kind, id] ("f" a facility of Tech.FACILITIES, "t" a tech of
## Tech.TECHS). AdmiralPlan reads them in front of its own list; Balanced has none, so it keeps the
## standard order.
const PRESET_PLANS := {
	"balanced": [],
	"attack": [["t", "fusionBombs"], ["t", "lanceBeams"], ["t", "improvedBombs"], ["t", "fighterDrive1"], ["t", "fighterDrive2"]],
	"defend": [["t", "repairBays"], ["t", "msShield1"], ["t", "bayDefenses"], ["t", "platformArmor1"], ["t", "platformMissiles"], ["t", "msPd2"], ["t", "msShield2"]],
	"economy": [["t", "improvedMining"], ["t", "droneArmor1"], ["t", "pilotStipend"], ["t", "droneArmor2"]],
}


## Is `preset_name` one of the four presets?
static func is_preset(preset_name: String) -> bool:
	return PRESETS.has(preset_name)


## The value of `key` in profile `profile_name`, in thousandths. Unknown name or key: 0 (and an error).
static func value(profile_name: String, key: String) -> int:
	var col := PROFILES.find(profile_name)
	if col < 0 or not TABLE.has(key):
		push_error("AdmiralProfileData: no value for %s in %s" % [key, profile_name])
		return 0
	return int((TABLE[key] as Array)[col])
