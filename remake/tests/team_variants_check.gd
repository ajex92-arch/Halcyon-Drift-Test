extends Node
## WHAT THIS IS: the "per-team switch check": a quick test that the per-team
## launch options (--variant-team0 and --variant-team1, which give a rule switch
## to ONE team's AI only) are read right, that a launch without them plays
## exactly as always, and that a module switched on for one team only is
## installed but read as on for that team alone.
##
## HOW IT WORKS: setup() runs after the match is built. The launch names the case
## it is (--tvc-case=<name>); the check then asks FeatureRegistry.is_on_for() and
## FeatureRegistry.active_for() (and Game.variant_for()) for both teams and
## prints a PASS or FAIL line for each statement, then "team_variants_check: N
## failures" (0 = all good), and quits. The cases:
##   none      no per-team option: for every key of Rules.VARIANT_DEFAULTS and
##             both teams is_on_for() equals is_on(); for every module key
##             active_for() equals world.features.has(); no per-team data.
##   team0     --variant-team0=ai_calib:on: on for team 0, off for team 1, and
##             is_on("ai_calib") stays false; every other key unchanged.
##   team1     the mirror: --variant-team1=ai_calib:on.
##   module    --variant-team0=eff:on: the eff module is installed
##             (world.features.has("eff")), active_for() is true for team 0 and
##             false for team 1, and is_on("eff") is false.
##   wide      --variant=eff:on: both teams read it as on (the match-wide switch
##             still works) and there is no per-team data.
##   override  --variant=eff:on --variant-team1=eff:off: on for team 0, off for
##             team 1 (a team's own value wins over the match-wide one).
## An unknown or malformed per-team name (for example --variant-team0=not_a_key:on)
## is refused by FeatureRegistry.install() with "TEAM VARIANT UNKNOWN: ..." and exit
## code 3. The check then only says so and leaves, because a quit() of its own would
## turn that 3 into 0; the log and the exit code are read from outside. The
## "team variants:" log line is read from the launch's log as well.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/; the folder name is up to you):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --sim-only --test=team_variants_check --tvc-case=none
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --sim-only --test=team_variants_check --tvc-case=team0 --variant-team0=ai_calib:on
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --sim-only --test=team_variants_check --tvc-case=module --variant-team0=eff:on
## (and the other cases the same way).
##
## WHO USES IT: main.gd loads it for --test=team_variants_check. It only reads
## the game's switches; it changes nothing in the match.

## The module key the "module", "wide" and "override" cases use: a feature that
## the standard rules leave off.
const MODULE_KEY := "eff"
## The calibration switch (a variant key with no module).
const CALIB_KEY := "ai_calib"

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Run the case the
## launch names, print the failure count, and quit.
func setup(w: World) -> void:
	world = w
	# A refused launch: install() has already asked the game to quit with exit code
	# 3. Say so and leave without quitting here (that would make the code 0).
	if Game.team_variant_error != "":
		print("team_variants_check: refused as it should (exit code 3 follows): ", Game.team_variant_error)
		return
	var case_name := str(Game.opt("tvc-case", ""))
	match case_name:
		"none":
			_check_none()
		"team0":
			_check_calib(0)
		"team1":
			_check_calib(1)
		"module":
			_check_module()
		"wide":
			_check_wide()
		"override":
			_check_override()
		_:
			_check("a known --tvc-case was given", false, "got '%s'" % case_name)
	print("team_variants_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## The keys of Rules.VARIANT_DEFAULTS (except `skip`) for which is_on_for() does
## not equal is_on() for some team, as a readable list ("" when there is none).
func _differing_keys(skip: String) -> String:
	var bad := PackedStringArray()
	for key: String in Rules.VARIANT_DEFAULTS:
		if key == skip:
			continue
		for team: int in range(2):
			if FeatureRegistry.is_on_for(team, key) != FeatureRegistry.is_on(key):
				bad.append("%s/team%d" % [key, team])
	return ", ".join(bad)


## No per-team option: nothing differs from the match-wide switches.
func _check_none() -> void:
	_check("no per-team option: has_team_variants() is false", not Game.has_team_variants() and Game.team_variants[0].is_empty() and Game.team_variants[1].is_empty() and Game.team_variant_error == "")
	var bad := _differing_keys("")
	_check("no per-team option: is_on_for() equals is_on() for every key and both teams", bad == "", bad)
	var wrong := PackedStringArray()
	var keys: Array = [CALIB_KEY, "not_a_key"]
	for entry: Array in FeatureRegistry.FEATURES:
		keys.append(entry[0])
	for key: String in keys:
		for team: int in range(2):
			if FeatureRegistry.active_for(world, team, key) != world.features.has(key):
				wrong.append("%s/team%d" % [key, team])
	_check("no per-team option: active_for() equals world.features.has() for every module key", wrong.is_empty(), ", ".join(wrong))
	_check("no per-team option: variant_for() is variant() for every team", Game.variant_for(0, "retreat") == Game.variant("retreat") and Game.variant_for(1, "retreat") == Game.variant("retreat") and Game.variant_for(5, "retreat") == Game.variant("retreat"))


## The calibration switch on for `holder` only (0 or 1).
func _check_calib(holder: int) -> void:
	var other := 1 - holder
	_check("%s is on for team %d" % [CALIB_KEY, holder], FeatureRegistry.is_on_for(holder, CALIB_KEY))
	_check("%s is off for team %d" % [CALIB_KEY, other], not FeatureRegistry.is_on_for(other, CALIB_KEY))
	_check("%s is off match-wide (is_on)" % CALIB_KEY, not FeatureRegistry.is_on(CALIB_KEY) and Game.variant(CALIB_KEY) == "off")
	_check("has_team_variants() is true and only team %d holds a pair" % holder, Game.has_team_variants() and Game.team_variants[holder].size() == 1 and Game.team_variants[other].is_empty() and Game.team_variant_error == "", str(Game.team_variants))
	_check("a team outside 0-1 gets the match-wide value", Game.variant_for(2, CALIB_KEY) == "off" and Game.variant_for(-1, CALIB_KEY) == "off")
	var bad := _differing_keys(CALIB_KEY)
	_check("every other key reads the same for both teams", bad == "", bad)
	_check("no module was installed by the calibration switch", not world.features.has(CALIB_KEY))


## A module switched on for team 0 only.
func _check_module() -> void:
	_check("%s is installed (on for team 0)" % MODULE_KEY, world.features.has(MODULE_KEY))
	_check("%s: active_for() is true for team 0" % MODULE_KEY, FeatureRegistry.active_for(world, 0, MODULE_KEY))
	_check("%s: active_for() is false for team 1" % MODULE_KEY, not FeatureRegistry.active_for(world, 1, MODULE_KEY))
	_check("%s: is_on() (match-wide) is false" % MODULE_KEY, not FeatureRegistry.is_on(MODULE_KEY))
	var bad := _differing_keys(MODULE_KEY)
	_check("every other key reads the same for both teams", bad == "", bad)


## The match-wide switch with no per-team option still gives both teams the module.
func _check_wide() -> void:
	_check("%s is installed" % MODULE_KEY, world.features.has(MODULE_KEY))
	_check("%s: active_for() is true for both teams" % MODULE_KEY, FeatureRegistry.active_for(world, 0, MODULE_KEY) and FeatureRegistry.active_for(world, 1, MODULE_KEY))
	_check("%s: is_on() is true and has_team_variants() is false" % MODULE_KEY, FeatureRegistry.is_on(MODULE_KEY) and not Game.has_team_variants())


## Match-wide on, team 1 switched off for itself: the team's own value wins.
func _check_override() -> void:
	_check("%s is installed (on match-wide)" % MODULE_KEY, world.features.has(MODULE_KEY))
	_check("%s: active_for() is true for team 0" % MODULE_KEY, FeatureRegistry.active_for(world, 0, MODULE_KEY))
	_check("%s: active_for() is false for team 1 (its own 'off' wins)" % MODULE_KEY, not FeatureRegistry.active_for(world, 1, MODULE_KEY))
	_check("%s: is_on() (match-wide) is still true" % MODULE_KEY, FeatureRegistry.is_on(MODULE_KEY))
