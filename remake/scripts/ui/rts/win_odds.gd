class_name WinOdds
extends RefCounted
## WHAT THIS IS: the win-odds mark of the Admiral's army cards (an option, off until the player turns it on): for a squadron or a
## group, a guess whether it would win ("win"), is about level with ("even") or would lose ("loss") against the enemy ships the
## human's team can see near it. It is the computer Admiral's strength model (AdmiralStrength: one whole-number weight for each hull
## class, scaled by the hull a ship has left) read for the card's squadrons and for those enemy ships, nothing more.
##
## HOW IT WORKS: only static functions and only whole numbers. of() adds up the strength of the ships of the squadrons (mine) and of
## every living enemy pilot ship that the human's team sees right now (Unit.visible_to) and that lies within
## RtsUiCalls.WIN_ODDS_REACH of the middle of those ships (theirs). The ratio is the larger strength over the smaller in permille
## (integer division, as the strength fit's bands are). Under RtsUiCalls.WIN_ODDS_EDGE_PM the mark is "even"; at or over it the
## larger side wins the mark: "win" when mine is larger, "loss" when theirs is. With no enemy ship seen near the squadrons (or no
## ship of ours) the mark is "none" and nothing is drawn. Fog is kept: a ship the team cannot see is never counted, and no team view
## query is used (with the team view switched off those read every enemy ship, hidden ones too). The weights are the four profile
## keys of the human team's profile (the same in every profile), thousandths. The guess comes from ship sizes and hulls alone, so it
## knows nothing of guided weapons, armour sections or energy routing, and the card's tooltip says so. Nothing is written, no order
## is given, no random number is drawn, and the computer Admiral reads nothing of it.
##
## WHO USES IT: ArmyCards (the card's "odds" field), tests/win_odds_check.gd.

## The three marks, in the order the card's signs are named ("odds_win", "odds_even", "odds_loss").
const MARKS := ["win", "even", "loss"]


## The four strength weights (thousandths, in the order of AdmiralStrength.CLASSES) of the human team's profile.
static func weights_of(world: World) -> Array:
	var prof := AdmiralProfile.for_team(world.human_team, Game.options)
	var out := []
	for key: String in AdmiralLanes.WEIGHT_KEYS:
		out.append(prof.raw(key))
	return out


## The odds of the squadrons `squad_ids` (ids of World.squads) against the enemy ships the human's team sees near them:
## {"mark": "none" | "win" | "even" | "loss", "mine": int, "theirs": int, "ratio_pm": int}. `weights` is for a test (or for a caller
## that asks many cards in one beat); none means the profile's four (weights_of). "mine" and "theirs" are strengths in thousandths,
## "ratio_pm" the larger over the smaller in permille (0 when the mark is "none").
@warning_ignore("integer_division")
static func of(world: World, squad_ids: Array[int], weights: Array = []) -> Dictionary:
	var wts: Array = weights if not weights.is_empty() else weights_of(world)
	var mine := 0
	var sum := Vector2.ZERO
	var n := 0
	for id in squad_ids:
		var rec: Squad = world.squads.get(id)
		if rec == null:
			continue
		for s: Ship in RtsSelect.ships_of(world, rec):
			mine += AdmiralStrength.ship_strength(s.hull_id, AdmiralStrength.permille(s.hull_frac()), wts)
			sum += s.global_position
			n += 1
	var out := {"mark": "none", "mine": mine, "theirs": 0, "ratio_pm": 0}
	if n == 0:
		return out
	var centre := sum / float(n)
	var reach2 := RtsUiCalls.WIN_ODDS_REACH * RtsUiCalls.WIN_ODDS_REACH
	var viewer := world.human_team
	var theirs := 0
	var seen := 0
	for s: Ship in world.ships:
		if not s.alive or s.team == viewer or not s.visible_to(viewer):
			continue
		if s.global_position.distance_squared_to(centre) > reach2:
			continue
		theirs += AdmiralStrength.ship_strength(s.hull_id, AdmiralStrength.permille(s.hull_frac()), wts)
		seen += 1
	out["theirs"] = theirs
	if seen == 0 or mine <= 0 or theirs <= 0:
		return out
	var ratio := maxi(mine, theirs) * 1000 / mini(mine, theirs)
	out["ratio_pm"] = ratio
	out["mark"] = "even" if ratio < RtsUiCalls.WIN_ODDS_EDGE_PM else ("win" if mine > theirs else "loss")
	return out


## The words of mark `mark` for a tooltip ("" for none).
static func words(mark: String) -> String:
	match mark:
		"win":
			return "Likely win"
		"even":
			return "Even"
		"loss":
			return "Likely loss"
	return ""
