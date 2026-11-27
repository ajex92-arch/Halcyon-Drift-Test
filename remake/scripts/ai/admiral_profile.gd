class_name AdmiralProfile
extends RefCounted
## WHAT THIS IS: the record of every number and switch of one team's computer Admiral (standard, v0, weak
## or one of the four presets balanced, attack, defend and economy). The parts of
## scripts/ai read their numbers from it (f, i, on) instead of carrying them as constants; the rows, their
## profiles and their ranges are in AdmiralProfileData.
##
## HOW IT WORKS: make() builds the record of a named profile (standard, v0 or weak) for a team. for_team()
## builds the record a match gives a team: the profile --admiral-profile names for it (the weak test
## option --admiral-ai=weak counts as the weak profile), then every --admiral-set pair for it. The two
## launch options:
##   --admiral-profile=<team>:<name>[;<team>:<name>...]
##   --admiral-set=<team>:<key>=<value>[;<team>:<key>=<value>...]
## <team> is 0, 1, aurelian, vhorr or both; <name> is a profile name; <key> is a row of AdmiralProfileData
## and <value> a whole number in thousandths ("1500" is 1.5, "90000" is 90 seconds, a switch is 0 or 1) or
## a decimal with at most three places ("1.5"). A repeated option adds its pairs (Game joins them with ";").
## option_error() checks all of it and gives the first error as one line, "" when the options are fine:
## Game keeps it in admiral_profile_error and FeatureRegistry.install() refuses the match (exit code 3),
## so a typo never plays a night of matches with the standard Admiral. switch_line() gives the one line a match
## prints at its start when a team's record is not the plain standard one.
## The record draws no random number and reads no world state.
##
## WHO USES IT: AdmiralAI (one record for its team, handed to every part), the parts that can be made on
## their own (a part made without one asks for_team), AdmiralWeak, Game and FeatureRegistry (the error),
## tests/admiral_profile_check.gd.

## The profile this record was made from ("standard", "v0", "weak" or a preset name such as "attack").
var profile_name := "standard"
## The team it is for.
var team := 0
## key -> value in thousandths.
var _v := {}


## The record of profile `p_name` for team `p_team`, or null when there is no such profile.
static func make(p_name: String, p_team: int = 0) -> AdmiralProfile:
	# A preset is the standard record with the preset's own numbers put in through the range-checked setter.
	if AdmiralProfileData.is_preset(p_name):
		var preset := make("standard", p_team)
		var changes: Dictionary = AdmiralProfileData.PRESETS[p_name]
		for key: String in changes:
			preset.set_value(key, int(changes[key]))
		preset.profile_name = p_name
		return preset
	var col := AdmiralProfileData.PROFILES.find(p_name)
	if col < 0:
		return null
	var p := AdmiralProfile.new()
	p.profile_name = p_name
	p.team = p_team
	for key: String in AdmiralProfileData.TABLE:
		p._v[key] = int((AdmiralProfileData.TABLE[key] as Array)[col])
	return p


## The research steps a profile puts in front of the standard plan: a preset's own list (a copy), and an empty
## list for standard, v0, weak or any name that is not a preset.
static func plan_front(p_name: String) -> Array:
	if not AdmiralProfileData.is_preset(p_name):
		return []
	return (AdmiralProfileData.PRESET_PLANS[p_name] as Array).duplicate(true)


## The value of `key` as a float (thousandths divided by 1000: 1200 gives 1.2, exactly the literal 1.2).
func f(key: String) -> float:
	if not _v.has(key):
		push_error("AdmiralProfile: unknown key %s" % key)
		return 0.0
	return float(_v[key]) / 1000.0


## The value of `key` as a whole number (a count: 2000 gives 2).
@warning_ignore("integer_division")
func i(key: String) -> int:
	if not _v.has(key):
		push_error("AdmiralProfile: unknown key %s" % key)
		return 0
	return int(_v[key]) / 1000


## Is switch `key` on (any value but 0)?
func on(key: String) -> bool:
	if not _v.has(key):
		push_error("AdmiralProfile: unknown key %s" % key)
		return false
	return int(_v[key]) != 0


## The value of `key` in thousandths (a switch: 0 or 1).
func raw(key: String) -> int:
	if not _v.has(key):
		push_error("AdmiralProfile: unknown key %s" % key)
		return 0
	return int(_v[key])


## Set `key` to `thousandths`. Returns "" or the reason it was refused (an unknown key, a value out of its
## range); a refused value changes nothing.
func set_value(key: String, thousandths: int) -> String:
	if not AdmiralProfileData.TABLE.has(key):
		return "unknown key \"%s\" (the keys are in AdmiralProfileData.TABLE)" % key
	var row: Array = AdmiralProfileData.TABLE[key]
	var lo := int(row[AdmiralProfileData.C_LOW])
	var hi := int(row[AdmiralProfileData.C_HIGH])
	if thousandths < lo or thousandths > hi:
		return "%s=%d is out of range (%d to %d)" % [key, thousandths, lo, hi]
	_v[key] = thousandths
	return ""


## Every key with its value, as a Dictionary copy (for the replay header and tests).
func values() -> Dictionary:
	return _v.duplicate()


## The one line a match prints when this team's Admiral is not the plain standard one, so a night's matches can
## show that a switch took: "admiral switches: team 0 Aurelian profile=standard fleet_play=1". It names the profile
## and then each row whose value differs from that profile's own, in the table's order, each in the form the
## --admiral-set option takes (thousandths). "" for the standard profile with no row changed. Pure: no random
## number, no world read.
static func switch_line(p: AdmiralProfile) -> String:
	var own := make(p.profile_name, p.team)
	if own == null:
		return ""
	var changed := PackedStringArray()
	for key: String in AdmiralProfileData.TABLE:
		if p.raw(key) != own.raw(key):
			changed.append("%s=%d" % [key, p.raw(key)])
	if p.profile_name == "standard" and changed.is_empty():
		return ""
	var line := "admiral switches: team %d %s profile=%s" % [p.team, Rules.TEAM_DISPLAY[p.team], p.profile_name]
	for part: String in changed:
		line += " " + part
	return line


# --- the launch options ------------------------------------------------------------------------------------

## The record the match gives team `p_team`, from the launch options `options` (Game.options): see the top.
## A part of the options that cannot be used is skipped here (option_error() names it).
static func for_team(p_team: int, options: Dictionary) -> AdmiralProfile:
	var base := "standard"
	var legacy := str(options.get("admiral-ai", ""))
	if legacy == "weakboth" or (legacy == "weak0" and p_team == Rules.HALCYON) or ((legacy == "weak" or legacy == "weak1") and p_team == Rules.CINDER):
		base = "weak"
	for part in str(options.get("admiral-profile", "")).split(";", false):
		var kv := str(part).split(":")
		if kv.size() == 2 and _teams_of(kv[0]).has(p_team) and (AdmiralProfileData.PROFILES.has(kv[1]) or AdmiralProfileData.is_preset(kv[1])):
			base = kv[1]
	var p := make(base, p_team)
	for part in str(options.get("admiral-set", "")).split(";", false):
		var parsed := _parse_set(str(part))
		if parsed.is_empty() or not (parsed["teams"] as Array).has(p_team):
			continue
		p.set_value(str(parsed["key"]), int(parsed["value"]))
	return p


## The first fault in the options --admiral-profile and --admiral-set, as one line naming the option and
## the pair, or "" when there is none. A bare option with no value is a fault too.
static func option_error(options: Dictionary) -> String:
	for opt_name: String in ["admiral-profile", "admiral-set"]:
		if not options.has(opt_name):
			continue
		var text := str(options[opt_name])
		if options[opt_name] is bool or text == "" or text == "true":
			return "--%s needs a value (see AdmiralProfile)" % opt_name
		for part in text.split(";", false):
			var err := _profile_pair_error(str(part)) if opt_name == "admiral-profile" else _set_pair_error(str(part))
			if err != "":
				return "--%s: %s" % [opt_name, err]
	return ""


## The teams a team word names: [0], [1] or [0, 1] ("both" or "all"); [] when the word is not a team.
static func _teams_of(word: String) -> Array:
	var w := word.strip_edges().to_lower()
	if w == "0":
		return [0]
	if w == "1":
		return [1]
	if w == "both" or w == "all":
		return [0, 1]
	var t := Rules.team_from_name(w)
	return [t] if t >= 0 else []


## The fault of one "<team>:<name>" pair, "" when it is fine.
static func _profile_pair_error(part: String) -> String:
	var kv := part.split(":")
	if kv.size() != 2 or kv[0] == "" or kv[1] == "":
		return "\"%s\" is not a <team>:<name> pair" % part
	if _teams_of(kv[0]).is_empty():
		return "\"%s\": \"%s\" is not a team (0, 1, aurelian, vhorr or both)" % [part, kv[0]]
	if not AdmiralProfileData.PROFILES.has(kv[1]) and not AdmiralProfileData.is_preset(kv[1]):
		return "\"%s\": unknown profile \"%s\" (the profiles are: %s, and the presets %s)" % [part, kv[1], ", ".join(PackedStringArray(AdmiralProfileData.PROFILES)), ", ".join(PackedStringArray(AdmiralProfileData.PRESET_NAMES))]
	return ""


## The fault of one "<team>:<key>=<value>" pair, "" when it is fine.
static func _set_pair_error(part: String) -> String:
	var parsed := _parse_set(part)
	if parsed.has("error"):
		return "\"%s\": %s" % [part, str(parsed["error"])]
	return ""


## One "<team>:<key>=<value>" pair as {"teams": [...], "key": String, "value": int}, or {"error": text}.
## The range is checked here against the table (a value out of range is an error).
static func _parse_set(part: String) -> Dictionary:
	var colon := part.find(":")
	var eq := part.find("=")
	if colon <= 0 or eq < colon + 2 or eq >= part.length() - 1:
		return {"error": "not a <team>:<key>=<value> pair"}
	var teams := _teams_of(part.substr(0, colon))
	if teams.is_empty():
		return {"error": "\"%s\" is not a team (0, 1, aurelian, vhorr or both)" % part.substr(0, colon)}
	var key := part.substr(colon + 1, eq - colon - 1)
	var text := part.substr(eq + 1)
	var thousandths: Variant = parse_thousandths(text)
	if thousandths == null:
		return {"error": "\"%s\" is not a whole number (thousandths) or a decimal with at most three places" % text}
	var probe := make("standard", 0)
	var why := probe.set_value(key, int(thousandths))
	if why != "":
		return {"error": why}
	return {"teams": teams, "key": key, "value": int(thousandths)}


## `text` as thousandths: a whole number is taken as it is ("1500"), a decimal is scaled ("1.5" is 1500; at most
## three places). Null when it is neither.
static func parse_thousandths(text: String) -> Variant:
	var t := text.strip_edges()
	if t.is_valid_int():
		return int(t)
	var dot := t.find(".")
	if dot <= 0 or dot >= t.length() - 1 or t.length() - dot - 1 > 3:
		return null
	var whole := t.substr(0, dot)
	var frac := t.substr(dot + 1)
	if not whole.is_valid_int() or not frac.is_valid_int() or frac.begins_with("-") or frac.begins_with("+"):
		return null
	var scaled := int(frac) * int(pow(10.0, float(3 - frac.length())))
	return int(whole) * 1000 + (-scaled if whole.begins_with("-") else scaled)
