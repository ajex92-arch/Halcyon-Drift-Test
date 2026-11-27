extends Node
## WHAT THIS IS: the check of the computer Admiral's profile record (scripts/ai/admiral_profile_data.gd
## and admiral_profile.gd). It proves the table is whole (every row has its seven columns, every value
## of every profile inside the row's range, a note on every row), that the standard profile still holds
## the numbers the Admiral's files carried before they moved into it (the list in OLD_NUMBERS is typed
## from those files, not read from the table), that the v0 and weak profiles differ from the standard
## one only where they should, that an unknown key, an unknown profile or team and a value out of range
## are refused (the command line options --admiral-profile and --admiral-set), that the old test
## option --admiral-ai=weak gives exactly the weak profile, and that every key marked wired is named in
## a file of scripts/ai that reads it.
##
## HOW IT WORKS: setup() runs the parts and prints "admiral_profile_check: N failures" (a FAIL line for
## each). When the match has computer Admirals it also checks that each holds a record and that its
## weak flag agrees with AdmiralWeak.is_weak().
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=admiral_profile_check
##
## WHO USES IT: main.gd loads it for --test=admiral_profile_check (it calls setup()).

## The numbers the Admiral's files carried before RT5 moved them into the table, in thousandths: the
## profile's own units (a key ending _s is seconds). Typed from admiral_ai.gd, admiral_siege.gd,
## admiral_mothership_mover.gd, admiral_field.gd, admiral_weak.gd, admiral_builder.gd,
## admiral_waypoint.gd, admiral_plan.gd and rts_hulls.gd at the fork tip adadf12.
const OLD_NUMBERS := {
	"think_start_s": 500, "think_stagger_s": 500, "think_gap_s": 1000, "ward_first_s": 30000, "ward_gap_s": 45000,
	"ward_treasury": 300000, "waypoint_first_s": 60000, "waypoint_gap_s": 75000, "waypoint_defend_s": 1000,
	"bay_first_s": 0, "bay_gap_s": 40000, "bay_spare": 500000, "drone_base": 6000, "drone_every_s": 75000,
	"drone_floor": 600, "drone_min": 4000, "drone_cost": 200000, "drone_spare": 200000, "plan_reserve": 500,
	"plan_lookahead": 4000, "waypoint_frac": 550, "waypoint_late_frac": 660, "waypoint_late_s": 1200000,
	"waypoint_late_front": 600, "bay_lane_frac": 330, "bay_off": 900000, "bay_cover": 1500000, "ward_cover": 1500000,
	"siege_start_s": 1200000, "siege_min_healthy": 2000, "siege_healthy_hull": 500, "siege_power_edge": 1200,
	"siege_ms_hurt": 600, "siege_gather_count": 2000, "siege_gather_time_s": 45000, "siege_gather_radius": 3000000,
	"siege_contact_dist": 3000000, "siege_stall_time_s": 120000, "siege_stall_frac": 150, "siege_no_contact_s": 300000,
	"siege_cooldown_s": 60000, "siege_follow_dist": 4000000, "siege_parked_dist": 2500000,
	"advance_frac": 350, "move_gap_s": 120000, "fallback_hull": 500, "fallback_far": 2000000, "advance_dist": 2500000,
	"mover_edge": 1000, "field_min_down": 2000, "field_min_trip_s": 20000, "field_cooldown_s": 15000,
	"head_wait_s": 20000, "income_window_s": 60000, "fill_t1_s": 360000, "fill_t2_s": 720000, "fill_t3_s": 1080000,
	"fill_p1_pct": 30000, "fill_p2_pct": 70000, "fill_p3_pct": 90000, "reserve": 300000, "saving_lapse_s": 180000,
	"per_corvette": 3000, "per_frigate": 2000, "special_one_in": 3000, "capital_max_pct": 34000,
	"bays": 1, "wards": 1, "siege": 1, "mover": 1, "field": 1, "is_weak": 0, "buys": 1, "holds_head": 1,
	"saves_capital": 1, "repeats": 1, "plan_gap_s": 0,
}
## The keys the weak profile sets differently from the standard one (admiral_weak.gd: a plan step every
## 90 s, no repair bays, wards, sieges, mothership moves or fleet buying).
const WEAK_DIFFERS := ["plan_gap_s", "bays", "wards", "siege", "mover", "buys", "is_weak"]
## The keys that stay off in every profile until their build wires them (their names are not read yet).
const LATER_OFF := ["win_odds_mark"]
## The four event-reaction switches (RT5 build 4a): wired (AdmiralReactions reads them) and off in every profile until the lead's switch-on commit.
const REACT_SWITCHES := ["react_build_blocked", "react_cap_full", "react_ship_lost", "react_under_attack"]
## The numbers of the reactions, in thousandths, the same in every profile: key -> [value, low, high].
const REACT_NUMBERS := {
	"react_cancel_s": [60000, 0, 3600000],
	"react_reach_small": [12000000, 0, 100000000],
	"react_reach_big": [18000000, 0, 100000000],
	"react_resend_dist": [2000000, 0, 100000000],
	"react_resend_gap_s": [5000, 1000, 600000],
}

## The fleet play's switch (RT8 build 8a): off in every profile until the lead's switch-on commit.
const FLEET_SWITCH := "fleet_play"
## The fleet play's numbers (RT8 build 8a), in thousandths, the same in every profile: key -> [value, low, high]. The
## help rule is a 0/1 switch row (0 = the lane in worst need first, a human pilot's lane wins a tie).
const FLEET_NUMBERS := {
	"fleet_goal_hold_s": [60000, 1000, 3600000],
	"fleet_retreat_below": [350, 0, 1000],
	"fleet_return_above": [600, 0, 1000],
	"fleet_lockout_s": [10000, 0, 600000],
	"fleet_help_pilot_first": [0, 0, 1],
	"fleet_mid_frac": [500, 0, 1000],
	"fleet_together_dist": [4000000, 0, 100000000],
	"fleet_group_join": [1500000, 0, 100000000],
	"fleet_turret_reach": [2500000, 0, 100000000],
	"fleet_turret_pts": [2000, 0, 50000],
	"fleet_area_radius": [6000000, 1000, 100000000],
	"fleet_help_edge": [1000, 0, 50000],
	"fleet_advance_step": [30, 0, 1000],
	"fleet_cap_orders": [20000, 1000, 1000000],
	"fleet_cap_window_ticks": [300000, 1000, 6000000],
	"fleet_order_delay_ticks": [18000, 0, 600000],
	"fleet_talk_gap_s": [10000, 0, 600000],
	"fleet_unpark_s": [0, 0, 600000],
	"fleet_unpark_reach": [2600000, 0, 100000000],
}

## The fitted strength's switch (RT5 build 4b): wired (AdmiralLanes reads it) and off in every profile until the lead's switch-on commit.
const FITTED_SWITCH := "fitted_strength"
## The four weights of the fitted strength (RT5 build 4b), in thousandths, in the order of AdmiralStrength.CLASSES: key -> [value, low, high]. The night's fit over 600 fights (Thu 11-12); the same in every profile.
const STRENGTH_WEIGHTS := {
	"strength_w_squadron": [345, 0, 10000],
	"strength_w_corvette": [1037, 0, 10000],
	"strength_w_frigate": [1360, 0, 10000],
	"strength_w_capital": [7258, 0, 10000],
}

## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	_table()
	_old_numbers()
	_profiles()
	_delay_gap()
	_options()
	_wired()
	_presets()
	if w != null:
		_preset_walks(w)
		_world(w)
		_log(w)
	print("admiral_profile_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## The table's shape: seven columns, ordered range, every profile's value in range, a note, switches 0 or 1.
func _table() -> void:
	_check("table: three profiles named standard, v0, weak", AdmiralProfileData.PROFILES == ["standard", "v0", "weak"])
	var n := 0
	for key: String in AdmiralProfileData.TABLE:
		var row: Array = AdmiralProfileData.TABLE[key]
		n += 1
		_check("table: %s has seven columns" % key, row.size() == 7, str(row.size()))
		if row.size() != 7:
			continue
		var lo := int(row[AdmiralProfileData.C_LOW])
		var hi := int(row[AdmiralProfileData.C_HIGH])
		_check("table: %s has an ordered range" % key, lo <= hi)
		for col in 3:
			var v: Variant = row[col]
			_check("table: %s in %s is a whole number" % [key, AdmiralProfileData.PROFILES[col]], typeof(v) == TYPE_INT)
			_check("table: %s in %s is inside %d to %d" % [key, AdmiralProfileData.PROFILES[col], lo, hi], int(v) >= lo and int(v) <= hi, str(v))
		_check("table: %s has a note" % key, str(row[AdmiralProfileData.C_NOTE]) != "")
		_check("table: %s wired flag is a bool" % key, typeof(row[AdmiralProfileData.C_WIRED]) == TYPE_BOOL)
		if str(row[AdmiralProfileData.C_NOTE]).begins_with("switch:") or key == "is_weak":
			_check("table: switch %s has the range 0 to 1" % key, lo == 0 and hi == 1)
	_check("table: has at least 80 rows", n >= 80, str(n))
	# The later builds' keys are declared and off (or at today's value).
	for key: String in LATER_OFF:
		_check("later: %s is declared" % key, AdmiralProfileData.TABLE.has(key))
		if AdmiralProfileData.TABLE.has(key):
			for p: String in AdmiralProfileData.PROFILES:
				_check("later: %s is off in %s" % [key, p], AdmiralProfileData.value(p, key) == 0)
			_check("later: %s is not wired yet" % key, not bool((AdmiralProfileData.TABLE[key] as Array)[AdmiralProfileData.C_WIRED]))
	# The four reactions' switches (build 4a) are wired now and off in every profile; their numbers are the same in every profile.
	for key: String in REACT_SWITCHES:
		_check("react: %s is declared and wired" % key, AdmiralProfileData.TABLE.has(key) and bool((AdmiralProfileData.TABLE[key] as Array)[AdmiralProfileData.C_WIRED]))
		if AdmiralProfileData.TABLE.has(key):
			for p: String in AdmiralProfileData.PROFILES:
				_check("react: %s is off in %s" % [key, p], AdmiralProfileData.value(p, key) == 0)
	for key: String in REACT_NUMBERS:
		var spec: Array = REACT_NUMBERS[key]
		_check("react: %s is declared, wired and in the table" % key, AdmiralProfileData.TABLE.has(key) and bool((AdmiralProfileData.TABLE[key] as Array)[AdmiralProfileData.C_WIRED]))
		if AdmiralProfileData.TABLE.has(key):
			var row: Array = AdmiralProfileData.TABLE[key]
			for p: String in AdmiralProfileData.PROFILES:
				_check("react: %s is %d in %s" % [key, spec[0], p], AdmiralProfileData.value(p, key) == int(spec[0]))
			_check("react: %s has the range %d to %d" % [key, spec[1], spec[2]], int(row[AdmiralProfileData.C_LOW]) == int(spec[1]) and int(row[AdmiralProfileData.C_HIGH]) == int(spec[2]))
	_check("react: the pilots' reaches are the table's 12,000 and 18,000 (one rule for pilots and squadrons)", PilotGoals.DEFEND_REACH_SMALL == float(AdmiralProfileData.value("standard", "react_reach_small")) / 1000.0 and PilotGoals.DEFEND_REACH_BIG == float(AdmiralProfileData.value("standard", "react_reach_big")) / 1000.0 and PilotGoals.DEFEND_REACH_SMALL == 12000.0 and PilotGoals.DEFEND_REACH_BIG == 18000.0)
	var listed := AdmiralReactions.SWITCHES.duplicate()
	listed.sort()
	var wanted := REACT_SWITCHES.duplicate()
	wanted.sort()
	_check("react: AdmiralReactions reads exactly the four switches", listed == wanted)
	# The four weights of the fitted strength (build 4b): declared, the same fitted numbers in every profile, in range 0 to 10000.
	for key: String in STRENGTH_WEIGHTS:
		var wspec: Array = STRENGTH_WEIGHTS[key]
		_check("strength: %s is declared and wired" % key, AdmiralProfileData.TABLE.has(key) and bool((AdmiralProfileData.TABLE[key] as Array)[AdmiralProfileData.C_WIRED]))
		if AdmiralProfileData.TABLE.has(key):
			var wrow: Array = AdmiralProfileData.TABLE[key]
			for p: String in AdmiralProfileData.PROFILES:
				_check("strength: %s is %d in %s" % [key, wspec[0], p], AdmiralProfileData.value(p, key) == int(wspec[0]))
			_check("strength: %s has the range %d to %d" % [key, wspec[1], wspec[2]], int(wrow[AdmiralProfileData.C_LOW]) == int(wspec[1]) and int(wrow[AdmiralProfileData.C_HIGH]) == int(wspec[2]))
	_check("strength: the four weights are in the order of AdmiralStrength.CLASSES", STRENGTH_WEIGHTS.keys() == ["strength_w_squadron", "strength_w_corvette", "strength_w_frigate", "strength_w_capital"] and AdmiralStrength.CLASSES == ["squadron", "corvette", "frigate", "capital"])
	_check("strength: fitted_strength is declared, wired and off in every profile", AdmiralProfileData.TABLE.has(FITTED_SWITCH) and bool((AdmiralProfileData.TABLE[FITTED_SWITCH] as Array)[AdmiralProfileData.C_WIRED]) and AdmiralProfileData.value("standard", FITTED_SWITCH) == 0 and AdmiralProfileData.value("v0", FITTED_SWITCH) == 0 and AdmiralProfileData.value("weak", FITTED_SWITCH) == 0)
	var wstd := AdmiralProfile.make("standard", 0)
	_check("strength: set_value takes the edges 0 and 10000 and refuses 10001 and -1", wstd.set_value("strength_w_capital", 0) == "" and wstd.set_value("strength_w_capital", 10000) == "" and wstd.set_value("strength_w_capital", 10001) != "" and wstd.set_value("strength_w_capital", -1) != "" and wstd.raw("strength_w_capital") == 10000)
	# The fleet play (RT8 build 8a): the switch is off in every profile and the numbers are the note's, the same in every profile.
	_check("fleet: fleet_play is declared and off in every profile", AdmiralProfileData.TABLE.has(FLEET_SWITCH) and AdmiralProfileData.value("standard", FLEET_SWITCH) == 0 and AdmiralProfileData.value("v0", FLEET_SWITCH) == 0 and AdmiralProfileData.value("weak", FLEET_SWITCH) == 0)
	for key: String in FLEET_NUMBERS:
		var fspec: Array = FLEET_NUMBERS[key]
		_check("fleet: %s is declared" % key, AdmiralProfileData.TABLE.has(key))
		if AdmiralProfileData.TABLE.has(key):
			var frow: Array = AdmiralProfileData.TABLE[key]
			for p: String in AdmiralProfileData.PROFILES:
				_check("fleet: %s is %d in %s" % [key, fspec[0], p], AdmiralProfileData.value(p, key) == int(fspec[0]))
			_check("fleet: %s has the range %d to %d" % [key, fspec[1], fspec[2]], int(frow[AdmiralProfileData.C_LOW]) == int(fspec[1]) and int(frow[AdmiralProfileData.C_HIGH]) == int(fspec[2]))
	var fstd := AdmiralProfile.make("standard", 0)
	_check("fleet: the posture thresholds are 0.35 and 0.60, the goal hold 60 s and the lockout 10 s", fstd.f("fleet_retreat_below") == 0.35 and fstd.f("fleet_return_above") == 0.6 and fstd.f("fleet_goal_hold_s") == 60.0 and fstd.f("fleet_lockout_s") == 10.0)
	# The team view (build 2) is wired now (TeamView reads it) and still off in every profile until its switch-on commit.
	_check("later: team_view is declared, wired and off in every profile", AdmiralProfileData.TABLE.has("team_view") and bool((AdmiralProfileData.TABLE["team_view"] as Array)[AdmiralProfileData.C_WIRED]) and AdmiralProfileData.value("standard", "team_view") == 0 and AdmiralProfileData.value("v0", "team_view") == 0 and AdmiralProfileData.value("weak", "team_view") == 0)
	for pair: Array in [["memory_fade_s", 90000], ["memory_stale_s", 300000]]:
		_check("later: %s is declared at %d" % [pair[0], pair[1]], AdmiralProfileData.TABLE.has(pair[0]) and AdmiralProfileData.value("standard", pair[0]) == pair[1])


## The standard profile still holds the numbers the files carried, and the derived constants agree.
func _old_numbers() -> void:
	for key: String in OLD_NUMBERS:
		_check("old number: %s is %d in the standard profile" % [key, OLD_NUMBERS[key]], AdmiralProfileData.TABLE.has(key) and AdmiralProfileData.value("standard", key) == int(OLD_NUMBERS[key]))
	_check("old number: every standard number of the table is in the list or is a later key", _every_key_known())
	# The constants of the files are the standard column.
	_check("const: RtsHulls.HEAD_WAIT_S is 20", RtsHulls.HEAD_WAIT_S == 20.0)
	_check("const: RtsHulls.INCOME_WINDOW_S is 60", RtsHulls.INCOME_WINDOW_S == 60.0)
	_check("const: RtsHulls.FILL_SECONDS is [360, 720, 1080]", RtsHulls.FILL_SECONDS == [360.0, 720.0, 1080.0])
	_check("const: RtsHulls.FILL_PERCENT is [30, 70, 90]", RtsHulls.FILL_PERCENT == [30.0, 70.0, 90.0])
	_check("const: RtsHulls.RESERVE is 300 and SAVING_LAPSE_S 180", RtsHulls.RESERVE == 300.0 and RtsHulls.SAVING_LAPSE_S == 180.0)
	_check("const: RtsHulls.CAPITAL_MAX_PERCENT is 34", RtsHulls.CAPITAL_MAX_PERCENT == 34.0)
	_check("const: the buying switches are on", RtsHulls.COMPUTER_BUYS and RtsHulls.COMPUTER_HOLDS_HEAD and RtsHulls.COMPUTER_SAVES_CAPITAL and RtsHulls.COMPUTER_REPEATS)
	_check("const: RtsHulls mix is 3 squadrons per corvette, 2 per frigate, 1 in 3 special", RtsHulls.SQUADRONS_PER_CORVETTE == 3.0 and RtsHulls.SQUADRONS_PER_FRIGATE == 2.0 and RtsHulls.SPECIAL_ONE_IN == 3.0)
	_check("const: the siege's constants are the old numbers", AdmiralSiege.START_TIME == 1200.0 and AdmiralSiege.MIN_HEALTHY == 2 and AdmiralSiege.POWER_EDGE == 1.2 and AdmiralSiege.MS_HURT == 0.6
		and AdmiralSiege.GATHER_COUNT == 2 and AdmiralSiege.GATHER_TIME == 45.0 and AdmiralSiege.GATHER_RADIUS == 3000.0 and AdmiralSiege.CONTACT_DIST == 3000.0
		and AdmiralSiege.STALL_TIME == 120.0 and AdmiralSiege.STALL_FRAC == 0.15 and AdmiralSiege.NO_CONTACT_TIME == 300.0 and AdmiralSiege.COOLDOWN == 60.0
		and AdmiralSiege.FOLLOW_DIST == 4000.0 and AdmiralSiege.PARKED_DIST == 2500.0)
	_check("const: the mover's constants are the old numbers", AdmiralMothershipMover.ADVANCE_FRAC == 0.35 and AdmiralMothershipMover.MOVE_GAP == 120.0
		and AdmiralMothershipMover.FALLBACK_HULL == 0.5 and AdmiralMothershipMover.FALLBACK_FAR == 2000.0)
	_check("const: the field's constants are the old numbers", AdmiralField.MIN_DOWN == 2 and AdmiralField.MIN_TRIP == 20.0 and AdmiralField.COOLDOWN == 15.0)
	_check("const: the weak plan gap is 90", AdmiralWeak.WEAK_PLAN_GAP == 90.0)
	_check("const: the plan's lookahead is 4", AdmiralPlan.LOOKAHEAD == 4)


## True when every key of the table is in OLD_NUMBERS or one of the later or log keys.
func _every_key_known() -> bool:
	var extra := LATER_OFF + REACT_SWITCHES + REACT_NUMBERS.keys() + ["team_view", "fitted_strength", "memory_fade_s", "memory_stale_s", "decision_log", "log_feed", FLEET_SWITCH] + STRENGTH_WEIGHTS.keys() + FLEET_NUMBERS.keys()
	for key: String in AdmiralProfileData.TABLE:
		if not OLD_NUMBERS.has(key) and not extra.has(key):
			print("  key not in the old-number list: ", key)
			return false
	return true


## The three profiles: v0 and weak differ from standard only where they should.
func _profiles() -> void:
	var std := AdmiralProfile.make("standard", 0)
	var v0 := AdmiralProfile.make("v0", 0)
	var weak := AdmiralProfile.make("weak", 1)
	_check("profiles: standard, v0 and weak can be made, an unknown name cannot", std != null and v0 != null and weak != null and AdmiralProfile.make("loud") == null)
	_check("profiles: the record knows its team", weak.team == 1 and std.team == 0)
	var v0_diff := _diff(std, v0)
	_check("profiles: v0 differs from standard only in decision_log", v0_diff == ["decision_log"], str(v0_diff))
	var weak_diff := _diff(std, weak)
	weak_diff.sort()
	var expect := WEAK_DIFFERS.duplicate()
	expect.sort()
	_check("profiles: weak differs from standard exactly in the seven weak keys", weak_diff == expect, str(weak_diff))
	_check("profiles: the weak plan gap is 90 s and the weak marker is on", weak.f("plan_gap_s") == 90.0 and weak.on("is_weak") and not std.on("is_weak"))
	_check("profiles: f, i and on read thousandths", std.f("siege_power_edge") == 1.2 and std.i("siege_min_healthy") == 2 and std.on("siege") and not weak.on("siege"))
	_check("profiles: f is exactly the old literal", std.f("siege_stall_frac") == 0.15 and std.f("advance_frac") == 0.35 and std.f("drone_floor") == 0.6 and std.f("fill_p2_pct") == 70.0)
	_check("profiles: raw gives the thousandths", std.raw("drone_base") == 6000)
	_check("profiles: the team view and the fitted strength are off in every profile", not std.on("team_view") and not std.on("fitted_strength") and not v0.on("team_view") and not weak.on("fitted_strength"))
	# set_value
	var p := AdmiralProfile.make("standard", 0)
	_check("set: a value in range is taken", p.set_value("drone_base", 7000) == "" and p.i("drone_base") == 7)
	_check("set: an unknown key is refused and says so", p.set_value("no_such_key", 1) != "")
	_check("set: a value out of range is refused and changes nothing", p.set_value("drone_base", 999999999) != "" and p.i("drone_base") == 7)
	_check("set: a switch takes only 0 or 1", p.set_value("siege", 2) != "" and p.set_value("siege", 0) == "" and not p.on("siege"))


## The fleet's order delay stays below the think gap in standard, v0 and weak (RT8 build 8c), so a delayed order lands before
## the next think; and the rule itself rejects the delay of 18 ticks against a gap of 0.1 s.
func _delay_gap() -> void:
	for p: String in ["standard", "v0", "weak"]:
		_check("delay: fleet_order_delay_ticks is below think_gap_s in %s" % p, AdmiralOutbox.delay_below_gap(AdmiralProfileData.value(p, "fleet_order_delay_ticks"), AdmiralProfileData.value(p, "think_gap_s")))
	_check("delay: 18 ticks against a gap of 0.1 s is not below it", not AdmiralOutbox.delay_below_gap(18000, 100))
	_check("delay: 18 ticks against a gap of 1 s is below it", AdmiralOutbox.delay_below_gap(18000, 1000))


## The keys whose value in `a` differs from `b`.
func _diff(a: AdmiralProfile, b: AdmiralProfile) -> Array:
	var out := []
	for key: String in AdmiralProfileData.TABLE:
		if a.raw(key) != b.raw(key):
			out.append(key)
	return out


## The command line: what is refused, what is taken, the old --admiral-ai option.
func _options() -> void:
	_check("options: no options is fine", AdmiralProfile.option_error({}) == "")
	_check("options: a profile for a team is fine", AdmiralProfile.option_error({"admiral-profile": "1:weak"}) == "")
	_check("options: a profile for both teams in two pairs is fine", AdmiralProfile.option_error({"admiral-profile": "0:v0;1:weak"}) == "")
	_check("options: team words work", AdmiralProfile.option_error({"admiral-profile": "vhorr:weak"}) == "" and AdmiralProfile.option_error({"admiral-set": "aurelian:siege=0"}) == "" and AdmiralProfile.option_error({"admiral-set": "both:siege=0"}) == "")
	_check("options: an unknown profile name is refused", AdmiralProfile.option_error({"admiral-profile": "1:loud"}) != "")
	_check("options: an unknown team is refused", AdmiralProfile.option_error({"admiral-profile": "2:weak"}) != "" and AdmiralProfile.option_error({"admiral-set": "x:siege=0"}) != "")
	_check("options: a pair that is not team:name is refused", AdmiralProfile.option_error({"admiral-profile": "weak"}) != "")
	_check("options: a bare option with no value is refused", AdmiralProfile.option_error({"admiral-profile": true}) != "" and AdmiralProfile.option_error({"admiral-set": true}) != "")
	_check("options: an unknown key is refused", AdmiralProfile.option_error({"admiral-set": "1:no_such_key=5"}) != "")
	_check("options: a value out of range is refused", AdmiralProfile.option_error({"admiral-set": "1:drone_base=999999999"}) != "" and AdmiralProfile.option_error({"admiral-set": "1:siege=2"}) != "")
	_check("options: a value that is no number is refused", AdmiralProfile.option_error({"admiral-set": "1:drone_base=many"}) != "" and AdmiralProfile.option_error({"admiral-set": "1:drone_base=1.2345"}) != "")
	_check("options: a pair with no value is refused", AdmiralProfile.option_error({"admiral-set": "1:drone_base="}) != "" and AdmiralProfile.option_error({"admiral-set": "1:drone_base"}) != "")
	_check("options: the first fault is named with its option", AdmiralProfile.option_error({"admiral-set": "1:siege=0;1:nope=1"}).begins_with("--admiral-set"))
	# Numbers on the command line.
	_check("parse: a whole number is thousandths", AdmiralProfile.parse_thousandths("1500") == 1500)
	_check("parse: a decimal is scaled", AdmiralProfile.parse_thousandths("1.5") == 1500 and AdmiralProfile.parse_thousandths("0.25") == 250 and AdmiralProfile.parse_thousandths("90.000") == 90000)
	_check("parse: a negative decimal", AdmiralProfile.parse_thousandths("-0.5") == -500)
	_check("parse: too many places or words give null", AdmiralProfile.parse_thousandths("1.2345") == null and AdmiralProfile.parse_thousandths("abc") == null and AdmiralProfile.parse_thousandths("1.") == null)
	# What the match gives each team.
	var o := {"admiral-profile": "1:weak", "admiral-set": "1:plan_gap_s=60000;both:drone_base=7000;0:siege_power_edge=1.5"}
	var t0 := AdmiralProfile.for_team(0, o)
	var t1 := AdmiralProfile.for_team(1, o)
	_check("for_team: team 0 stays standard with its own sets", t0.profile_name == "standard" and t0.i("drone_base") == 7 and t0.f("siege_power_edge") == 1.5 and not t0.on("is_weak"))
	_check("for_team: team 1 is weak with its own sets", t1.profile_name == "weak" and t1.i("drone_base") == 7 and t1.f("plan_gap_s") == 60.0 and t1.f("siege_power_edge") == 1.2 and t1.on("is_weak"))
	var plain := AdmiralProfile.for_team(0, {})
	_check("for_team: no options gives the standard record", plain.values() == AdmiralProfile.make("standard", 0).values())
	# --admiral-ai=weak is exactly the weak profile.
	var weak_ref := AdmiralProfile.make("weak", 1).values()
	_check("legacy: --admiral-ai=weak is the weak profile for team 1 and standard for team 0", AdmiralProfile.for_team(1, {"admiral-ai": "weak"}).values() == weak_ref and AdmiralProfile.for_team(0, {"admiral-ai": "weak"}).values() == AdmiralProfile.make("standard", 0).values())
	_check("legacy: weak1 is weak for team 1, weak0 for team 0, weakboth for both", AdmiralProfile.for_team(1, {"admiral-ai": "weak1"}).on("is_weak") and AdmiralProfile.for_team(0, {"admiral-ai": "weak0"}).on("is_weak") and not AdmiralProfile.for_team(1, {"admiral-ai": "weak0"}).on("is_weak")
		and AdmiralProfile.for_team(0, {"admiral-ai": "weakboth"}).on("is_weak") and AdmiralProfile.for_team(1, {"admiral-ai": "weakboth"}).on("is_weak"))
	_check("legacy: --admiral-profile=1:weak equals --admiral-ai=weak", AdmiralProfile.for_team(1, {"admiral-profile": "1:weak"}).values() == AdmiralProfile.for_team(1, {"admiral-ai": "weak"}).values())
	_check("legacy: the weak profile is v0-like in everything but the weak keys", _diff(AdmiralProfile.make("weak", 1), AdmiralProfile.make("v0", 1)).size() == WEAK_DIFFERS.size() + 1)


## Every key marked wired is named in a script of scripts/ai (or the weak option's file) other than the table and the record.
func _wired() -> void:
	var text := ""
	for dir in ["res://scripts/ai", "res://scripts/features/admiral_weak.gd"]:
		if dir.ends_with(".gd"):
			text += FileAccess.get_file_as_string(dir)
			continue
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") and f != "admiral_profile_data.gd" and f != "admiral_profile.gd":
				text += FileAccess.get_file_as_string(dir + "/" + f)
	_check("wired: the sources were read", text.length() > 20000, str(text.length()))
	var unwired := 0
	for key: String in AdmiralProfileData.TABLE:
		var wired: bool = (AdmiralProfileData.TABLE[key] as Array)[AdmiralProfileData.C_WIRED]
		var used := text.contains("\"%s\"" % key)
		if wired:
			_check("wired: %s is read by a part" % key, used)
		else:
			unwired += 1
			_check("wired: %s is marked not wired but a part reads it" % key, not used)
	print("admiral_profile_check: %d keys, %d declared for later builds" % [AdmiralProfileData.TABLE.size(), unwired])


## The four presets as data: the names and their order, every changed key is a table row and the new value is
## inside its range, Balanced is exactly the standard record, the others change exactly their own keys, the
## four differ pairwise, every research step names a real facility or tech, and the launch option takes a
## preset name (and refuses an unknown one).
func _presets() -> void:
	var names: Array = AdmiralProfileData.PRESET_NAMES
	_check("presets: the four names, in the user's order", names == ["balanced", "attack", "defend", "economy"])
	_check("presets: PRESETS and PRESET_PLANS hold exactly those names", AdmiralProfileData.PRESETS.keys() == names and AdmiralProfileData.PRESET_PLANS.keys() == names)
	var std := AdmiralProfile.make("standard", 0)
	var recs := {}
	for p_name: String in names:
		var changes: Dictionary = AdmiralProfileData.PRESETS[p_name]
		for key: String in changes:
			var in_table := AdmiralProfileData.TABLE.has(key)
			_check("presets: %s's key %s is a table row" % [p_name, key], in_table)
			if not in_table:
				continue
			var row: Array = AdmiralProfileData.TABLE[key]
			var v := int(changes[key])
			_check("presets: %s's %s=%d is inside %d to %d" % [p_name, key, v, row[AdmiralProfileData.C_LOW], row[AdmiralProfileData.C_HIGH]], typeof(changes[key]) == TYPE_INT and v >= int(row[AdmiralProfileData.C_LOW]) and v <= int(row[AdmiralProfileData.C_HIGH]))
		var rec := AdmiralProfile.make(p_name, 1)
		_check("presets: %s can be made, knows its name and its team" % p_name, rec != null and rec.profile_name == p_name and rec.team == 1)
		if rec == null:
			continue
		recs[p_name] = rec
		var moved := _diff(std, rec)
		moved.sort()
		var wanted: Array = changes.keys()
		wanted.sort()
		_check("presets: %s changes exactly its own keys" % p_name, moved == wanted, str(moved))
		for key: String in changes:
			_check("presets: %s has %s at %d" % [p_name, key, changes[key]], rec.raw(key) == int(changes[key]))
		for step: Array in AdmiralProfileData.PRESET_PLANS[p_name]:
			var known: bool = Tech.FACILITIES.has(step[1]) if step[0] == "f" else (step[0] == "t" and Tech.TECHS.has(step[1]))
			_check("presets: %s's research step %s is a real facility or tech" % [p_name, str(step)], known)
	_check("presets: Balanced is the standard record on every key and has no research front", recs.has("balanced") and (recs["balanced"] as AdmiralProfile).values() == std.values() and (AdmiralProfileData.PRESET_PLANS["balanced"] as Array).is_empty())
	for a in names.size():
		for b in range(a + 1, names.size()):
			var same_plan: bool = AdmiralProfileData.PRESET_PLANS[names[a]] == AdmiralProfileData.PRESET_PLANS[names[b]]
			_check("presets: %s and %s differ on at least one key" % [names[a], names[b]], recs.has(names[a]) and recs.has(names[b]) and not _diff(recs[names[a]], recs[names[b]]).is_empty() and not same_plan)
	_check("presets: plan_front gives a preset's steps as a copy and nothing for the other profiles", AdmiralProfile.plan_front("attack") == AdmiralProfileData.PRESET_PLANS["attack"] and AdmiralProfile.plan_front("standard").is_empty() and AdmiralProfile.plan_front("weak").is_empty() and AdmiralProfile.plan_front("loud").is_empty())
	var copy := AdmiralProfile.plan_front("attack")
	copy.clear()
	_check("presets: changing the copy leaves the table's list alone", not (AdmiralProfileData.PRESET_PLANS["attack"] as Array).is_empty())
	# The launch option takes preset names.
	_check("presets: --admiral-profile=0:attack builds the attack record", AdmiralProfile.option_error({"admiral-profile": "0:attack"}) == "" and AdmiralProfile.for_team(0, {"admiral-profile": "0:attack"}).values() == AdmiralProfile.make("attack", 0).values() and AdmiralProfile.for_team(0, {"admiral-profile": "0:attack"}).profile_name == "attack")
	_check("presets: a pair of presets gives each team its own", AdmiralProfile.option_error({"admiral-profile": "0:attack;1:defend"}) == "" and AdmiralProfile.for_team(0, {"admiral-profile": "0:attack;1:defend"}).profile_name == "attack" and AdmiralProfile.for_team(1, {"admiral-profile": "0:attack;1:defend"}).profile_name == "defend")
	_check("presets: both:economy reaches both teams, then --admiral-set still applies on top", AdmiralProfile.for_team(1, {"admiral-profile": "both:economy", "admiral-set": "1:reserve=1000"}).profile_name == "economy" and AdmiralProfile.for_team(1, {"admiral-profile": "both:economy", "admiral-set": "1:reserve=1000"}).raw("reserve") == 1000 and AdmiralProfile.for_team(0, {"admiral-profile": "both:economy"}).raw("drone_base") == 8000)
	_check("presets: 0:nonsense is an option error that names the pair", AdmiralProfile.option_error({"admiral-profile": "0:nonsense"}).contains("0:nonsense"))
	_check("presets: the old profiles are untouched (standard, v0, weak keep their names)", AdmiralProfile.make("v0", 0).profile_name == "v0" and AdmiralProfile.make("weak", 1).profile_name == "weak" and AdmiralProfile.for_team(0, {}).profile_name == "standard")


## The plan with a research front. First: with no front the new next_step gives the step the old code gave (the
## old algorithm is copied below), for 20 scripted states of the team (the first 2k plan steps done, k = 0 to
## 19). Then the walk: for each preset a fresh team state is walked 120 times, each time taking the step and
## marking it done at once; the walk never gets an empty answer while a step of the front is unfinished, and ends
## with every front step done. `w` is the match world the check runs in.
func _preset_walks(w: World) -> void:
	for k in 20:
		var ts := TeamState.new(0, w)
		for i in mini(2 * k, AdmiralPlan.PLAN.size()):
			_mark_done(ts, AdmiralPlan.PLAN[i])
		var old := _old_next_step(ts, 4.0)
		_check("walk: no front gives the old step (state %d)" % k, AdmiralPlan.next_step(ts, 4.0) == old and AdmiralPlan.next_step(ts, 4.0, []) == old, "%s against %s" % [str(AdmiralPlan.next_step(ts, 4.0)), str(old)])
	for p_name: String in AdmiralProfileData.PRESET_NAMES:
		var front := AdmiralProfile.plan_front(p_name)
		var ts := TeamState.new(0, w)
		var stalled := ""
		var taken := 0
		for n in 120:
			var step := AdmiralPlan.next_step(ts, 4.0, front)
			if step.is_empty():
				stalled = _front_open(ts, front)
				break
			_mark_done(ts, [step["kind"], step["id"]])
			taken += 1
		_check("walk: %s never gets an empty answer while a front step is open" % p_name, stalled == "", stalled)
		_check("walk: %s ends with every front step done" % p_name, _front_open(ts, front) == "", _front_open(ts, front))
		_check("walk: %s took plan steps as well as its own" % p_name, taken >= front.size() + 5, str(taken))


## Mark one plan step [kind, id] as finished on a throwaway team state.
func _mark_done(ts: TeamState, step: Array) -> void:
	if step[0] == "f":
		ts.facilities[step[1]] = true
	else:
		ts.done[step[1]] = true


## The id of the first step of `front` that is not finished on `ts`, "" when all are.
func _front_open(ts: TeamState, front: Array) -> String:
	for s: Array in front:
		if not (ts.facilities.has(s[1]) if s[0] == "f" else ts.done.has(s[1])):
			return str(s[1])
	return ""


## AdmiralPlan.next_step as it was before the optional front list: a copy to compare the new function with.
func _old_next_step(ts: TeamState, lookahead: float) -> Dictionary:
	var pending := 0
	var plan: Array = AdmiralPlan.PLAN if ts.plan_override.is_empty() else ts.plan_override
	if ts.plan_hook.is_valid():
		plan = ts.plan_hook.call(ts, plan)
	for s: Array in plan:
		var kind: String = s[0]
		var id: String = s[1]
		if kind == "f":
			if ts.facilities.has(id) or ts.is_building(id):
				continue
		elif ts.done.has(id) or ts.is_researching(id):
			continue
		pending += 1
		if pending > lookahead:
			return {}
		if kind == "f":
			if ts.facility_blocker(id) != "":
				continue
			return {"kind": "f", "id": id, "cost": float(Tech.FACILITIES[id]["cost"])}
		if ts.tech_blocker(id) != "":
			continue
		return {"kind": "t", "id": id, "cost": float(Tech.TECHS[id]["cost"])}
	return {}


## The decision log's rules (AdmiralLog), on a log of its own that writes no file: a "not yet" line only when its
## reason changes and at most once per rule per 60 s, an order line for an Admiral-seat order (and none for another seat
## or a team whose decision_log is off), a refused order says so, feed() sends nothing while log_feed is off.
func _log(w: World) -> void:
	var ai: AdmiralAI = w.admiral_ai[0]
	if ai == null:
		return
	var lg := AdmiralLog.new(w)
	_check("log: with no --admiral-log the log is off", not lg.enabled and not lg.wants(0))
	lg.enabled = true
	var saved_time := w.time
	w.time = 100.0
	lg.not_yet(0, "r", "a", "no siege yet: because a")
	lg.not_yet(0, "r", "a", "no siege yet: because a")
	_check("log: the same reason twice writes one not-yet line", lg.lines == 1, str(lg.lines))
	lg.not_yet(0, "r", "b", "no siege yet: because b")
	_check("log: a changed reason within 60 s writes nothing", lg.lines == 1, str(lg.lines))
	lg.not_yet(0, "other_rule", "a", "holds: other rule")
	_check("log: another rule writes its own line", lg.lines == 2, str(lg.lines))
	w.time = 161.0
	lg.not_yet(0, "r", "b", "no siege yet: because b")
	lg.not_yet(0, "r", "b", "no siege yet: because b")
	_check("log: a changed reason after 60 s writes one line", lg.lines == 3, str(lg.lines))
	_check("log: a not-yet line has the team name, the clock and the tail", lg.recent[0].begins_with("1:40 Aurelian Admiral no siege yet") and lg.recent[0].contains("[rule=r nogo=1 team=0 t=100]"), lg.recent[0])
	lg.expect(0, "DRONE", "drones.floor", "orders a mining drone", "a fleet ship", "only 3 drones")
	lg._on_event({"kind": "order_done", "team": 0, "data": {"seat": Rules.ADMIRAL_SEAT, "kind": "DRONE", "id": 5}})
	_check("log: an Admiral order makes one order line with the runner-up, the reason and the tail", lg.order_lines == 1 and lg.recent[-1].contains("orders a mining drone over a fleet ship: only 3 drones") and lg.recent[-1].contains("kind=DRONE res=ok id=5"), lg.recent[-1])
	lg._on_event({"kind": "order_refused", "team": 0, "data": {"seat": Rules.ADMIRAL_SEAT, "kind": "WARD", "id": 6, "reason": "place"}})
	_check("log: an order with no note gets a plain line and a refusal says so", lg.order_lines == 2 and lg.recent[-1].contains("places a ward, but it was refused (place)") and lg.recent[-1].contains("res=place"), lg.recent[-1])
	lg._on_event({"kind": "order_done", "team": 0, "data": {"seat": 0, "kind": "MOVE", "id": 7}})
	_check("log: an order of a pilot's seat is not logged", lg.order_lines == 2)
	lg.note(0, "yard.save", "saves for a Destroyer (3000)")
	_check("log: a note is a line but not an order line", lg.lines == 6 and lg.order_lines == 2, "%d %d" % [lg.lines, lg.order_lines])
	var was_on := ai.profile.raw("decision_log")
	ai.profile.set_value("decision_log", 0)
	lg.note(0, "x", "silent")
	_check("log: a team whose decision_log is off writes nothing", lg.lines == 6)
	ai.profile.set_value("decision_log", was_on)
	w.time = saved_time
	lg.enabled = false


## The match's own Admirals each hold a record that agrees with the weak option.
func _world(w: World) -> void:
	for t in 2:
		var ai: AdmiralAI = w.admiral_ai[t]
		if ai == null:
			continue
		_check("world: team %d's Admiral holds a profile record" % t, ai.profile != null and ai.profile.team == t)
		if ai.profile == null:
			continue
		_check("world: team %d's weak flag agrees with AdmiralWeak.is_weak" % t, ai.weak == AdmiralWeak.is_weak(t) and ai.weak == ai.profile.on("is_weak"))
		_check("world: team %d's parts share its record" % t, ai.siege.prof == ai.profile and ai.production.prof == ai.profile and ai.mothership_mover.prof == ai.profile and ai.field.prof == ai.profile and ai.builder.prof == ai.profile and ai.waypoint.prof == ai.profile and ai.react.prof == ai.profile and not ai.react.any_on())
