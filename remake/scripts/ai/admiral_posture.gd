class_name AdmiralPosture
extends RefCounted
## WHAT THIS IS: the computer Admiral's choice between ATTACK and RETREAT for its fleet, and the safety rules of where the
## fleet may go (RT8 build 8a). It is read only while the profile switch fleet_play is on.
##
## HOW IT WORKS:
##   The "chance": there is no win-chance model, so the number is own / (own + enemy): our fleet's strength against the
##   enemy strength in the fight area (the ships the team has seen there, with the view's fade, plus each enemy lane turret
##   in the area as fleet_turret_pts). The caller (AdmiralFleet) works out both sides; ratio_of() is the share.
##   The state: ATTACK or RETREAT. Below fleet_retreat_below (0.35) it falls back; above fleet_return_above (0.60) it goes
##   back in; between the two it keeps what it is doing. After a switch it does not switch again for fleet_lockout_s
##   (10 s), counted from the switch and not from each verdict (so a ratio wobbling over a threshold cannot flip the fleet
##   every second). next_state() is that rule on its own.
##   Falling back: fall_back_point() is the nearest standing turret of ours (the lane turrets), and our base when none stands.
##   Going in: attack_point() is a little beyond the front of our minions on the goal lane, with two rules. PAST THE
##   LANE'S MIDDLE (fleet_mid_frac, 0.5) the fleet goes only with its attacking squadrons together (at least 2 squadrons AND at
##   least half of the attacking strength within fleet_together_dist of one squadron's centre: gathered()), else the point
##   stays at the middle. And NO SQUADRON STANDS INSIDE AN ENEMY LANE
##   TURRET'S REACH (fleet_turret_reach) unless our minions are within that reach of the turret: the point is moved back
##   along the lane until it is clear (in_reach(), clear_of_reach()).
## The part draws no random number, reads no world state (only the team view) and sends no order.
##
## WHO USES IT: AdmiralFleet (one per team, made only while fleet_play is on); tests/admiral_fleet_check.gd.

## The two states.
const ATTACK := "attack"
const RETREAT := "retreat"  # the fall-back state
## How far (as a fraction of the lane) the attack point steps back at a time when it is inside a turret's reach, and the most
## steps.
const BACK_STEP := 0.01
const BACK_STEPS := 60  # the most steps

## The game world.
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The lane helper (lane points).
var lanes: AdmiralLanes
## What the team knows.
var view: TeamView
## This Admiral's numbers.
var prof: AdmiralProfile
## The state now, the match second of the last switch (a long time ago to start with) and how many switches there have been.
var state := ATTACK
var switched_at := -1000000.0  # the match second of the last switch
var switches := 0  # how many switches there have been
## The last own / (own + enemy) share, for the log and the tests.
var ratio := 1.0


## Make the posture of team `t` in world `w`. AdmiralFleet makes this once.
func _init(w: World, t: int, l: AdmiralLanes, p: AdmiralProfile) -> void:
	world = w
	team = t
	lanes = l
	view = l.view
	prof = p


## own / (own + enemy): 1.0 when both are 0 (nothing to fear, nothing to do).
static func ratio_of(own: float, enemy: float) -> float:
	var total := own + enemy
	if total <= 0.0:
		return 1.0
	return own / total


## The state to be in: `current` kept for `lockout` seconds after the switch at `since` (`now - since` is the time since
## the switch); otherwise ATTACK falls back below `retreat_below` and RETREAT goes in again above `return_above`.
static func next_state(current: String, share: float, since: float, now: float, retreat_below: float, return_above: float, lockout: float) -> String:
	if now - since < lockout:
		return current
	if current == ATTACK and share < retreat_below:
		return RETREAT
	if current == RETREAT and share > return_above:
		return ATTACK
	return current


## The enemy strength in the fight area at `area` (the size count: the ships seen there by the view's memory, plus
## fleet_turret_pts for each enemy lane turret or standing post within the area's radius).
func enemy_power(area: Vector2) -> float:
	var r := prof.f("fleet_area_radius")
	var power := float(view.enemy_near(area, r)) / 1000.0
	for tp: Vector2 in view.enemy_turret_points():
		if tp.distance_to(area) <= r:
			power += prof.f("fleet_turret_pts")
	return power


## One think: the share own / (own + enemy) and the state it gives (with the lockout). Returns the state.
func think(now: float, own: float, enemy: float) -> String:
	ratio = ratio_of(own, enemy)
	var next := next_state(state, ratio, switched_at, now, prof.f("fleet_retreat_below"), prof.f("fleet_return_above"), prof.f("fleet_lockout_s"))
	if next != state:
		state = next
		switched_at = now
		switches += 1
	return state


## The point a group at `from` falls back to: our nearest standing lane turret, else our base.
func fall_back_point(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for tp: Vector2 in view.own_turret_points():
		var d := tp.distance_to(from)
		if d < best_d:
			best_d = d
			best = tp
	if best != Vector2.INF:
		return best
	return MapLayout.mothership_pos(team)


## True when the attacking squadrons (their centres `centres` and strengths `strengths`, the sum of their ships' power) are
## together: taking each squadron in turn (the id order of the arrays) as the centre, at least 2 squadrons (it counts itself)
## and at least half of the total strength stand within `together` of its centre; the first centre that passes decides.
static func gathered(centres: Array, strengths: Array, together: float) -> bool:
	var total := 0.0
	for st: float in strengths:
		total += st
	for i in centres.size():
		var count := 0
		var near := 0.0
		for j in centres.size():
			if i == j or (centres[i] as Vector2).distance_to(centres[j] as Vector2) <= together:
				count += 1
				near += float(strengths[j])
		if count >= 2 and near * 2.0 >= total - 0.000001:
			return true
	return false


## Is point `p` inside the reach of an enemy lane turret (`turrets`, their places) that none of our minions (`minions`,
## their places) is within `reach` of? A turret our minions are at is not counted: they draw its fire and lift the backdoor
## protection.
static func in_reach(p: Vector2, turrets: Array, minions: Array, reach: float) -> bool:
	for tp: Vector2 in turrets:
		if tp.distance_to(p) >= reach:
			continue
		var covered := false
		for mp: Vector2 in minions:
			if mp.distance_to(tp) <= reach:
				covered = true
				break
		if not covered:
			return true
	return false


## `p` moved out of every uncovered turret's reach, straight away from the turret (an enemy turret exactly at `p` pushes it
## towards `home`). A point already clear is returned as it was.
static func clear_of_reach(p: Vector2, turrets: Array, minions: Array, reach: float, home: Vector2) -> Vector2:
	var out := p
	for tp: Vector2 in turrets:
		if tp.distance_to(out) >= reach:
			continue
		var covered := false
		for mp: Vector2 in minions:
			if mp.distance_to(tp) <= reach:
				covered = true
				break
		if covered:
			continue
		var away := out - tp
		if away.length() < 1.0:
			away = home - tp
		out = tp + away.normalized() * (reach + 50.0)
	return out


## The point the fleet goes in to on `lane`, whose minions' front is at `front` (a fraction): a little beyond the front, at
## most the lane's middle unless `together` (the squadrons are together: gathered()), then back along the lane until it is clear of every
## uncovered enemy turret's reach. `turrets` and `minions` are the places of the enemy lane turrets and our minions.
func attack_point(lane: String, front: float, together: bool, turrets: Array, minions: Array) -> Vector2:
	var frac := clampf(front + prof.f("fleet_advance_step"), 0.15, 0.90)
	var mid := prof.f("fleet_mid_frac")
	if frac > mid and not together:
		frac = mid
	var reach := prof.f("fleet_turret_reach")
	var p := lanes.lane_point(lane, frac)
	var steps := 0
	while steps < BACK_STEPS and frac > 0.10 and in_reach(p, turrets, minions, reach):
		frac -= BACK_STEP
		p = lanes.lane_point(lane, frac)
		steps += 1
	return p
