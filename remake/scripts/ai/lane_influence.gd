class_name LaneInfluence
extends RefCounted
## WHAT THIS IS: the computer Admiral's choice of the GOAL LANE (RT8 build 8a): the lane its fleet pushes. The old push
## lane (AdmiralLanes.push_lane) is simply where our furthest minion is; the goal lane is chosen by advantage. It is read
## only while the profile switch fleet_play is on; push_lane() itself is unchanged.
##
## HOW IT WORKS: each lane gets a score from four things, all read through the team view (own units exactly, the enemy as
## far as the team has seen it, faded over memory_fade_s):
##   own strength    our flying ships within the fight area (fleet_area_radius) of the lane's front, by size (1 strike
##                   craft, 2 corvette, 3 frigate, 4 capital, times 0.4 + 0.6 x hull);
##   enemy strength  the enemy ships the team has seen there (TeamView.enemy_near, the view's fade included);
##   own turret cover  our standing lane turrets on the lane (a lane we can fall back into);
##   route danger    the enemy strength seen ahead of the front on the way to their base, and their standing turrets.
## score = own - enemy + COVER x cover - DANGER x (route enemy + TURRET x enemy turrets) + FRONT x front + STICKY (the
## lane held now). The goal lane changes at most once every fleet_goal_hold_s (60 s) unless the base alarm is on: then it
## is the lane the defend point is on, at once. The lane's "front" is the place of our furthest minion (kept between 15% and
## 85% of the lane; 30% when we have no minion there).
## The part draws no random number, reads no world state and sends no order.
##
## WHO USES IT: AdmiralFleet (one per team, made only while fleet_play is on); tests/admiral_fleet_check.gd.

## Weights of the score (points of the size count): our cover per turret, the danger per point of enemy strength ahead and
## per enemy turret, the progress bonus (times the front's fraction) and the bonus of the lane held now.
const COVER := 0.5
const DANGER := 0.5  # the danger per point of enemy strength ahead
const TURRET := 1.5  # the danger per enemy turret
const FRONT := 3.0  # the progress bonus (times the front's fraction)
const STICKY := 1.0  # the bonus of the lane held now
## Where along a lane (as fractions beyond the front) the route danger is sampled.
const ROUTE_STEPS := [0.15, 0.30, 0.45]

## The game world.
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The lane helper (fronts and lane points).
var lanes: AdmiralLanes
## What the team knows.
var view: TeamView
## This Admiral's numbers.
var prof: AdmiralProfile
## The goal lane now ("" before the first choice), the match second it was chosen, and how many times it has changed (the
## first choice is not a change).
var goal := ""
var goal_since := -1.0  # the match second it was chosen
var changes := 0  # how many times it has changed
## The last scores, lane -> float, and the last fight-area point of each lane, for the log and the tests.
var scores := {}
var areas := {}  # the last fight-area point of each lane
## Each lane's path and length as our team walks it, kept (they never change), and the fronts worked out at the start of a think.
var _pts := {}  # lane -> its path
var _len := {}  # lane -> its length
var _fronts := {}  # lane -> its front as a fraction, from the last think


## Make the lane choice of team `t` in world `w`. AdmiralFleet makes this once.
func _init(w: World, t: int, l: AdmiralLanes, p: AdmiralProfile) -> void:
	world = w
	team = t
	lanes = l
	view = l.view
	prof = p
	for lane: String in MapLayout.LANE_ORDER:
		_pts[lane] = MapLayout.lane_points(lane, t)
		_len[lane] = Util.polyline_length(_pts[lane])


## The path of `lane` as our team walks it (kept).
func lane_pts(lane: String) -> PackedVector2Array:
	return _pts[lane]


## The point `frac` of the way along `lane` (the same answer as AdmiralLanes.lane_point, from the kept path).
func point_at(lane: String, frac: float) -> Vector2:
	return Util.polyline_at(_pts[lane], float(_len[lane]) * frac)


## The lane the defend point `p` is on: the lane whose path is nearest (the first in the lane order on a tie).
func lane_of_point(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for lane: String in MapLayout.LANE_ORDER:
		var d := Util.dist_to_polyline(p, _pts[lane])
		if d < best_d:
			best_d = d
			best = lane
	return best


## The fronts of all lanes in one pass over our minions (the same numbers AdmiralLanes.front_frac gives), kept until the next
## think.
func _work_out_fronts() -> void:
	var best := {}
	for lane: String in MapLayout.LANE_ORDER:
		best[lane] = 0.0
	for m in view.own_minions():
		if best.has(m.lane):
			best[m.lane] = maxf(float(best[m.lane]), float(Util.project_on_polyline(m.global_position, _pts[m.lane])["s"]))
	_fronts.clear()
	for lane: String in MapLayout.LANE_ORDER:
		_fronts[lane] = float(best[lane]) / float(_len[lane])


## The front of `lane` as a fraction (our furthest minion; 0.30 for none, kept between 0.15 and 0.85).
func front_of(lane: String) -> float:
	var f: float = float(_fronts[lane]) if _fronts.has(lane) else lanes.front_frac(lane)
	if f <= 0.0:
		return 0.30
	return clampf(f, 0.15, 0.85)


## The fight-area point of `lane`: its front.
func area_point(lane: String) -> Vector2:
	return point_at(lane, front_of(lane))


## Our flying ships' strength within `r` of `p` (the size count: 1, 2, 3, 4 times 0.4 + 0.6 x hull), from `ships` (our ships,
## read once by the caller).
static func own_near(ships: Array, p: Vector2, r: float) -> float:
	var sum := 0.0
	for s: Ship in ships:
		if s.global_position.distance_to(p) <= r:
			sum += float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())
	return sum


## The scores of all lanes (see the top), lane -> float. `ships` is our live ships, read once by the caller. The enemy
## strength of every place asked about (each lane's front and its route samples) comes from one pass (TeamView.enemy_near_many).
func score_all(ships: Array) -> Dictionary:
	var r := prof.f("fleet_area_radius")
	var points: Array = []
	var fronts := {}
	for lane: String in MapLayout.LANE_ORDER:
		var front := front_of(lane)
		fronts[lane] = front
		points.append(point_at(lane, front))
		for step: float in ROUTE_STEPS:
			points.append(point_at(lane, clampf(front + step, 0.0, 1.0)))
	var enemy_at := view.enemy_near_many(points, r)
	var out := {}
	var k := 0
	for lane: String in MapLayout.LANE_ORDER:
		var area: Vector2 = points[k]
		areas[lane] = area
		var own := own_near(ships, area, r)
		var enemy := float(int(enemy_at[k])) / 1000.0
		k += 1
		var route := 0.0
		for step: float in ROUTE_STEPS:
			route += float(int(enemy_at[k])) / 1000.0
			k += 1
		var cover := float(view.own_turret_points(lane).size())
		var danger := route + TURRET * float(view.enemy_turrets(lane))
		var s := own - enemy + COVER * cover - DANGER * danger + FRONT * float(fronts[lane])
		if lane == goal:
			s += STICKY
		out[lane] = s
	return out


## The score of `lane` alone (the same number score_all gives it).
func score(lane: String, ships: Array) -> float:
	return float(score_all(ships)[lane])


## The goal lane to hold, from the scores (lane -> float). A base alarm with a known lane (`alarm_lane` not "") gives that
## lane at once. With no goal yet the best lane is taken. A goal younger than `hold` seconds (`now - since`) is kept.
## Otherwise the best lane (the first in the lane order on a tie).
static func pick(lane_scores: Dictionary, current: String, since: float, now: float, hold: float, alarm_lane: String) -> String:
	if alarm_lane != "":
		return alarm_lane
	if current != "" and now - since < hold:
		return current
	var best := current
	var best_s := -INF
	for lane: String in MapLayout.LANE_ORDER:
		if lane_scores.has(lane) and float(lane_scores[lane]) > best_s:
			best_s = float(lane_scores[lane])
			best = lane
	return best


## One think: work out the fronts, score the lanes and settle the goal lane. `alarm` is TeamState.defending (the base alarm);
## `defend_point` its place. Returns the goal lane.
func think(now: float, alarm: bool, defend_point: Vector2) -> String:
	_work_out_fronts()
	scores = score_all(view.own_ships())
	var alarm_lane := lane_of_point(defend_point) if alarm and defend_point != Vector2.INF else ""
	var chosen := pick(scores, goal, goal_since, now, prof.f("fleet_goal_hold_s"), alarm_lane)
	if chosen != goal:
		if goal != "":
			changes += 1
		goal = chosen
		goal_since = now
	return goal