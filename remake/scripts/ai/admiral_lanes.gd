class_name AdmiralLanes
extends RefCounted
## WHAT THIS IS: the AI admiral's "eyes on the map". It answers questions
## about the lanes and the fleets: which lane are we pushing, how far down
## a lane our minions have got, where a point part-way down a lane is, and
## how strong each side's pilot fleet is right now.
##
## HOW IT WORKS: a lane is a path made of straight pieces joined end to end
## (a "polyline", see MapLayout.LANES). It runs from one mothership's spot
## to the other's. To see how far along a lane a ship is, we find the
## closest point on that path and measure the distance along the path to it
## (Util.project_on_polyline gives this as "s", in world units). Nothing in
## this file changes the game: it only looks.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.lanes) and hands it to its
## other parts, which call it: AdmiralWaypoint, AdmiralSiege,
## AdmiralMothershipMover, AdmiralBuilder and AdmiralProduction.

## The game world (the map and the match time; its units are read through the team view).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## What our team knows (own units exactly, the enemy as far as it has been seen: TeamView).
var view: TeamView


## Remember the world and our team. AdmiralAI makes this part once.
func _init(w: World, t: int) -> void:
	world = w
	team = t
	view = TeamView.of(w, t)


## The lane we are "pushing": the one where one of our minions has got
## furthest from our base, as a fraction of the lane's length (the lanes are
## not equally long: top and bottom about 44,200 units, mid about 33,600, so
## comparing distances would hardly ever pick mid). Returns the lane id
## ("top", "mid" or "bot"), or "" when we have no living minions in any lane.
func push_lane() -> String:
	var best := ""
	# Fraction along its lane (0..1) of the furthest minion so far.
	var best_s := -1.0
	for lane: String in MapLayout.LANE_ORDER:
		# The lane's path as our team walks it: from our base outwards.
		var pts := MapLayout.lane_points(lane, team)
		var lane_len := Util.polyline_length(pts)
		# Measure every living minion of ours that is on this lane.
		for m in view.own_minions():
			if m.lane == lane:
				var s: float = float(Util.project_on_polyline(m.global_position, pts)["s"]) / lane_len
				if s > best_s:
					best_s = s
					best = lane
	return best


## How far along `lane` our furthest minion is, as a fraction from 0.0 (our
## end of the lane) to 1.0 (the enemy's end). 0.0 when none of our minions
## are on that lane.
func front_frac(lane: String) -> float:
	var pts := MapLayout.lane_points(lane, team)
	# Furthest distance along the lane (world units) found so far.
	var best := 0.0
	for m in view.own_minions():
		if m.lane == lane:
			best = maxf(best, float(Util.project_on_polyline(m.global_position, pts)["s"]))
	# Turn the distance into a fraction of the whole lane's length.
	return best / Util.polyline_length(pts)


## The point `frac` of the way along `lane`, counted from our end (0.0 =
## where our mothership starts, 1.0 = where the enemy's starts). For
## example lane_point("mid", 0.5) is the middle of the mid lane.
func lane_point(lane: String, frac: float) -> Vector2:
	var pts := MapLayout.lane_points(lane, team)
	return Util.polyline_at(pts, Util.polyline_length(pts) * frac)


## The point on `lane` a little on our side of the front of our minions (4% of the lane back, kept between 10% and 85%
## of the way): where a bought squadron's "lane" rally goes (Production.rally_point) and where a squadron that fills in
## for a dead pilot goes (AdmiralReactions).
func front_point(lane: String) -> Vector2i:
	var frac := clampf(front_frac(lane) - 0.04, 0.10, 0.85)
	return Order.point(lane_point(lane, frac))


## How strong team `t`'s flying pilot ships are, as one number. A ship
## counts by size: 1 for strike craft, 2 for corvettes, 3 for frigates, 4
## for capital ships. That is multiplied by 0.4 + 0.6 x its hull fraction
## (how much hull it has left, 0..1), so a badly damaged ship counts for
## less, but never under 0.4 of its size. Minions and turrets don't count.
func fleet_power(t: int) -> float:
	# Our own fleet is read exactly; the enemy's through the team view (live while the view is off).
	return view.own_power() if t == team else view.enemy_power()

## The four profile keys of the fitted strength's weights (thousandths), in the order of AdmiralStrength.CLASSES.
const WEIGHT_KEYS := ["strength_w_squadron", "strength_w_corvette", "strength_w_frigate", "strength_w_capital"]


## Is the fitted strength the measure of the siege and the mothership mover (profile switch fitted_strength)?
func fitted() -> bool:
	return view.prof.on("fitted_strength")


## The four weights of the profile, in thousandths, in the order of AdmiralStrength.CLASSES.
func strength_weights() -> Array:
	var out := []
	for key: String in WEIGHT_KEYS:
		out.append(view.prof.raw(key))
	return out


## The fitted strength of team `t`'s pilot fleet in thousandths (AdmiralStrength: one weight per hull class, times
## 0.4 + 0.6 x the hull left), read the way fleet_power reads: our own ships exactly, the enemy's through the team
## view (every living ship while the view is off; the records, the ships seen and not yet seen dead, while it is on).
## `weights` is for a test; none means the profile's four.
@warning_ignore("integer_division")
func strength(t: int, weights: Array = []) -> int:
	var wts: Array = weights if not weights.is_empty() else strength_weights()
	if t == team:
		return AdmiralStrength.of_ships(view.own_ships(), t, wts)
	if not view.enabled():
		# The view is off: the enemy is read live, as enemy_power does, through the enemy team's own view (the Admiral reads no world list itself).
		return AdmiralStrength.of_ships(TeamView.of(world, t).own_ships(), t, wts)
	view._sync()
	var total := 0
	for id: int in view._ships:
		var rec: Dictionary = view._ships[id]
		var share := AdmiralStrength.HULL_FLOOR + (1000 - AdmiralStrength.HULL_FLOOR) * clampi(int(rec["hp"]), 0, 1000) / 1000
		total += int(wts[clampi(int(rec["si"]), 0, 3)]) * share / 1000
	return total


## The measure the siege and the mothership mover compare, for team `t`: the fitted strength while fitted_strength is
## on, else fleet_power (the size count), the same one for both sides.
func measure(t: int) -> float:
	return float(strength(t)) if fitted() else fleet_power(t)


## "our fleet 4.0 against their 3.0" (the size count, one decimal) or "our fleet 3456 against their 2100" (the fitted
## strength, whole numbers): the two fleets as the decision log prints them.
func versus() -> String:
	if fitted():
		return "our fleet %d against their %d" % [strength(team), strength(1 - team)]
	return "our fleet %.1f against their %.1f" % [fleet_power(team), fleet_power(1 - team)]


## The name of the measure in use as the log prints it after the numbers: "" for the size count (today's text,
## unchanged) and " (fitted)" for the fitted strength.
func measure_tag() -> String:
	return " (fitted)" if fitted() else ""
