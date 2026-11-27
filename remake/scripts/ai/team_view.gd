class_name TeamView
extends RefCounted
## WHAT THIS IS: what ONE team knows about the match, for its computer Admiral: its own units exactly, and the
## enemy only as far as the team has SEEN it. Every part of the Admiral (lanes, siege, production, builder,
## mothership mover, field, waypoint) reads the world through this record and nowhere else (tests/teamview_check.gd
## scans for that). It is the only file of scripts/ai that may read a world unit list.
##
## HOW IT WORKS: there are two ways to answer, chosen by the team's profile switch "team_view" (a key of
## AdmiralProfileData; 0 = off, the default, and the Admiral plays as it always did).
##   - OFF: every helper returns exactly what the old live read returned (the same loop over the same list, the same
##     floats). Nothing is recorded, nothing costs time.
##   - ON: the enemy side is a set of RECORDS, brought up to date at the start of each Admiral think (think()) from
##     Unit.visible_to (the team's fog of war) and nothing else:
##       * a ship record holds where the ship was last seen, its hull then (whole thousandths), its size, and when.
##         WHERE it is fades from 1 to 0 over the profile's memory_fade_s (90 s); THAT it exists keeps full weight
##         until the team sees it die, or until memory_stale_s (300 s) pass without a sighting, then the record goes;
##       * the enemy mothership keeps its last-seen place, turn and hull with no fade, and changes only on sight;
##       * the enemy's lane turrets and defense posts are records too: standing until the team sees the place
##         without them. Before the first sight the record starts from the map's known layout (the mothership at its
##         home spot with a full hull, the lane turrets and posts standing).
##     Groups ("what is near this point") are worked out when asked, over the records, not kept.
##   Sums and hull fractions are whole numbers: a hull is in thousandths, a ship's strength is
##   (1 + size index) x (400000 + 600 x hull thousandths), so a sum is exact; enemy_strength() gives it in thousandths.
##   The view draws no random number and writes no game state (it keeps only its own records).
##   A test switch, `sees_all` (the launch option --team-view-sees-all), makes the team see every enemy unit all the
##   time: a match with team_view ON and sees_all must then be identical to a match with team_view off.
##
## WHO USES IT: AdmiralAI makes one per team (TeamView.of) and calls think() once per think; AdmiralLanes,
## AdmiralSiege, AdmiralWaypoint, AdmiralMothershipMover, AdmiralBuilder, AdmiralProduction and AdmiralField
## ask it; tests/teamview_check.gd.

## The memory's whole-number scale: a hull or a weight is in thousandths.
const PM := 1000
## Strength of one ship before its hull: size 400000 plus 600 per thousandth of hull (a micro-point scale).
const BASE_MICRO := 400000
const HULL_MICRO := 600

## The match.
var world: World
## The team this view is for: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The other team.
var enemy := 1
## The team's Admiral numbers (AdmiralProfile): the switch team_view and the two memory times.
var prof: AdmiralProfile
## Test only: the team sees every enemy unit all the time (--team-view-sees-all).
var sees_all := false
## The world time of the last sync (-1 = never).
var _t := -1.0
## True once the starting records are made.
var _ready := false
## Enemy ships: instance id -> {"pos": Vector2, "hp": int thousandths, "si": int size index, "seen": float, "vis": bool}.
var _ships := {}
## Enemy lane turrets: instance id -> {"lane": String, "pos": Vector2, "vis": bool}.
var _turrets := {}
## Enemy defense posts: lane -> {"standing": bool, "pos": Vector2}.
var _posts := {}
## The enemy mothership: {} until made, then {"pos", "rot", "half_len", "beam", "hp", "seen"}.
var _ms := {}
## A reusable list for the spatial hash (own_near).
var _scratch: Array = []


## The view of team `t` in match `w` (made and kept on the world the first time it is asked for). `p` is the team's
## profile; without one the profile the match gives the team (AdmiralProfile.for_team) is used.
static func of(w: World, t: int, p: AdmiralProfile = null) -> TeamView:
	if w == null:
		return null
	var key := "team_view_%d" % t
	if w.has_meta(key):
		return w.get_meta(key) as TeamView
	var v := TeamView.new(w, t, p)
	w.set_meta(key, v)
	return v


func _init(w: World, t: int, p: AdmiralProfile = null) -> void:
	world = w
	team = t
	enemy = Rules.enemy_of(t)
	prof = p if p != null else AdmiralProfile.for_team(t, Game.options)
	var all_text := str(Game.opt("team-view-sees-all", "false"))
	sees_all = all_text != "false" and all_text != "0"


## Is the team view switched on for this team?
func enabled() -> bool:
	return prof.on("team_view")


## Called by the Admiral once per think: bring the enemy records up to date (does nothing while the view is off).
func think() -> void:
	if enabled():
		_sync()


## Bring the records up to date now, even if they were already made at this world time (tests that change the units
## between two asks at one time; the Admiral calls think() instead).
func refresh() -> void:
	if enabled():
		_t = -1.0
		_sync()


## Forget the records (a test starts a scenario afresh; the next ask makes the starting records again).
func reset() -> void:
	_t = -1.0
	_ready = false
	_ships.clear()
	_turrets.clear()
	_posts.clear()
	_ms = {}


# --- own units: always exact ----------------------------------------------------------------------------

## Our live pilot ships, in the world's order.
func own_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for s: Ship in world.ships:
		if s.team == team and s.alive:
			out.append(s)
	return out


## Our big ships (frigates and capital ships) that are alive.
func own_bigs() -> Array[Ship]:
	var out: Array[Ship] = []
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.size_class >= Rules.SIZE_LARGE:
			out.append(s)
	return out


## How many of our live crewed ships are capital ships.
func own_capitals() -> int:
	var n := 0
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.profile != null and s.profile.is_crew and RtsHulls.is_capital(s.hull_id):
			n += 1
	return n


## Our live minions, in the world's order.
func own_minions() -> Array:
	var out: Array = []
	for m in world.minions:
		if m.team == team and m.alive:
			out.append(m)
	return out


## WHAT: the enemy ship or minion the team sees now that is nearest to point `p` within `r` of it (distance <= r), or null for
## none; a tie goes to the lower instance id. `ships` and `minions` choose the kinds that count. A turret is never returned.
## HOW: ships are read from the records (_ships), only those the team saw at the last sync (vis); a record whose unit is dead or
## freed is skipped and the next nearest is tried. Minions are read live from the world, only while the view is on and only
## those the team sees now (no minion is recorded). It does not sync: the Admiral's think does that once per think, a test calls
## refresh(). It draws no random number and writes no game state.
## WHO: AdmiralFleet's unpark step.
func nearest_seen_enemy_unit(p: Vector2, r: float, ships: bool = true, minions: bool = true) -> Unit:
	var best: Unit = null
	var best_id := 0
	var best_d := INF
	if ships:
		for id: int in _ships:
			var rec: Dictionary = _ships[id]
			if not bool(rec["vis"]):
				continue
			var d := (rec["pos"] as Vector2).distance_to(p)
			if d > r or (best != null and (d > best_d or (d == best_d and id > best_id))):
				continue
			var obj: Object = instance_from_id(id)
			if obj == null or not (obj is Ship) or not (obj as Ship).alive:
				continue
			best = obj as Ship
			best_id = id
			best_d = d
	if minions and enabled():
		for m in world.minions:
			if m.team != enemy or not m.alive or not _sees(m):
				continue
			var md: float = (m as Node2D).global_position.distance_to(p)
			var m_id: int = m.get_instance_id()
			if md > r or (best != null and (md > best_d or (md == best_d and m_id > best_id))):
				continue
			best = m as Unit
			best_id = m_id
			best_d = md
	return best


## Our live repair bays.
func own_bays() -> Array:
	var out: Array = []
	for b in world.bays:
		if b.team == team and b.alive:
			out.append(b)
	return out


## Our live wards.
func own_wards() -> Array:
	var out: Array = []
	for w in world.wards:
		if w.team == team and w.alive:
			out.append(w)
	return out


## The ore nodes on our side of the map, in the world's order (or in the order of `ordered`, a list a feature gave).
func own_nodes(ordered: Array = []) -> Array:
	var src: Array = ordered if not ordered.is_empty() else world.nodes
	var out: Array = []
	for n: ResourceNode in src:
		if n.side == team:
			out.append(n)
	return out


## Our own mothership.
func own_ms() -> Mothership:
	return world.mothership(team)


## Our pilots' profiles (live or dead), in the world's order.
func own_profiles() -> Array[PilotProfile]:
	var out: Array[PilotProfile] = []
	for p: PilotProfile in world.profiles:
		if p.team == team:
			out.append(p)
	return out


## How many of our live pilot ships and minions are within `r` of point `p`.
func own_near(p: Vector2, r: float) -> int:
	var count := 0
	for u: Unit in world.unit_hash.query(p, r, _scratch):
		if u.alive and u.team == team and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION) and u.global_position.distance_to(p) < r:
			count += 1
	return count


## How strong our flying pilot ships are, as one number: 1 for strike craft, 2 for corvettes, 3 for frigates, 4 for
## capital ships, each times 0.4 + 0.6 x its hull fraction (the Admiral's old fleet_power, unchanged).
func own_power() -> float:
	var p := 0.0
	for s: Ship in world.ships:
		if s.team == team and s.alive:
			p += float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())
	return p


# --- the enemy ---------------------------------------------------------------------------------------------

## The enemy fleet's strength as the old fleet_power number (a float): live while the view is off, the sum of the
## records (whole micro-points, so exact) while it is on.
func enemy_power() -> float:
	if not enabled():
		var p := 0.0
		for s: Ship in world.ships:
			if s.team == enemy and s.alive:
				p += float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())
		return p
	return float(enemy_strength_micro()) / float(PM * PM)


## The enemy fleet's strength in micro-points (1 point = 1,000,000), a whole number.
func enemy_strength_micro() -> int:
	if not enabled():
		var live := 0
		for s: Ship in world.ships:
			if s.team == enemy and s.alive:
				live += _micro(Rules.size_index(s.size_class), _hp(s.hull_frac()))
		return live
	_sync()
	var sum := 0
	for id: int in _ships:
		var r: Dictionary = _ships[id]
		sum += _micro(int(r["si"]), int(r["hp"]))
	return sum


## The enemy fleet's strength in thousandths of a point (a whole number): every ship the team has not seen die and
## has seen in the last memory_stale_s, at full weight.
@warning_ignore("integer_division")
func enemy_strength() -> int:
	return (enemy_strength_micro() + PM / 2) / PM


## The enemy strength near point `p` (within `r`), in thousandths of a point: each remembered ship counts by its
## strength times how much of where it is is still remembered (1 when seen now, 0 after memory_fade_s).
@warning_ignore("integer_division")
func enemy_near(p: Vector2, r: float) -> int:
	if not enabled():
		var live := 0
		for s: Ship in world.ships:
			if s.team == enemy and s.alive and s.global_position.distance_to(p) <= r:
				live += _micro(Rules.size_index(s.size_class), _hp(s.hull_frac()))
		return (live + PM / 2) / PM
	_sync()
	var sum := 0
	for id: int in _ships:
		var rec: Dictionary = _ships[id]
		if (rec["pos"] as Vector2).distance_to(p) <= r:
			sum += _micro(int(rec["si"]), int(rec["hp"])) * where_weight(rec) / PM
	return (sum + PM / 2) / PM


## enemy_near() for several places at once, in one pass over the ships: the list of the answers for `points` (each the same
## number enemy_near(point, r) gives, in thousandths of a point). RT8: the fleet layer asks about a dozen places a think.
@warning_ignore("integer_division")
func enemy_near_many(points: Array, r: float) -> Array:
	var sums: Array = []
	sums.resize(points.size())
	sums.fill(0)
	if not enabled():
		for s: Ship in world.ships:
			if s.team == enemy and s.alive:
				var pos := s.global_position
				var micro := -1
				for i in points.size():
					if pos.distance_to(points[i] as Vector2) <= r:
						if micro < 0:
							micro = _micro(Rules.size_index(s.size_class), _hp(s.hull_frac()))
						sums[i] = int(sums[i]) + micro
	else:
		_sync()
		for id: int in _ships:
			var rec: Dictionary = _ships[id]
			var rpos: Vector2 = rec["pos"]
			var weighted := -1
			for i in points.size():
				if rpos.distance_to(points[i] as Vector2) <= r:
					if weighted < 0:
						weighted = _micro(int(rec["si"]), int(rec["hp"])) * where_weight(rec) / PM
					sums[i] = int(sums[i]) + weighted
	for i in sums.size():
		sums[i] = (int(sums[i]) + PM / 2) / PM
	return sums


## How much of where a remembered ship is is still remembered, in thousandths: 1000 when seen now, falling in a
## straight line to 0 at memory_fade_s without a sighting.
@warning_ignore("integer_division")
func where_weight(rec: Dictionary) -> int:
	var age_ms := roundi((_t - float(rec["seen"])) * 1000.0)
	var fade := prof.raw("memory_fade_s")
	if fade <= 0:
		return 0
	return clampi(PM - age_ms * PM / fade, 0, PM)


## How many enemy ships the team still counts as existing (the records).
func enemy_ship_count() -> int:
	if not enabled():
		var n := 0
		for s: Ship in world.ships:
			if s.team == enemy and s.alive:
				n += 1
		return n
	_sync()
	return _ships.size()


## True while the enemy has a mothership (it always has one in a real match).
func enemy_ms_present() -> bool:
	if not enabled():
		return world.mothership(enemy) != null
	_sync()
	return not _ms.is_empty()


## Where the enemy mothership is: live while the view is off, else its last-seen place (the map's home spot until
## the first sighting).
func enemy_ms_pos() -> Vector2:
	if not enabled():
		return world.mothership(enemy).global_position
	_sync()
	return _ms["pos"] as Vector2


## The enemy mothership's hull as a fraction 0..1: live while the view is off, else the last-seen hull in whole
## thousandths (1.0 until the first sighting).
func enemy_ms_hull() -> float:
	if not enabled():
		return world.mothership(enemy).hull_frac()
	_sync()
	return float(int(_ms["hp"])) / float(PM)


## How far point `p` is from the enemy mothership's hull surface (the live ship's own maths while the view is off,
## the same maths on the last-seen place and turn while it is on).
func enemy_ms_hull_dist(p: Vector2) -> float:
	if not enabled():
		return world.mothership(enemy).hull_dist(p)
	_sync()
	var c: Vector2 = _ms["pos"]
	var f := Vector2.from_angle(float(_ms["rot"])) * float(_ms["half_len"])
	return p.distance_to(Util.closest_on_segment(p, c + f, c - f)) - float(_ms["beam"]) * 0.5


## The enemy mothership's record (a copy), for tests and the log: {} while the view is off or before the first sync.
func enemy_ms_record() -> Dictionary:
	if not enabled():
		return {}
	_sync()
	return _ms.duplicate()


## How many enemy defences stand on `lane` as far as the team knows: its lane turrets plus its defense post.
func enemy_turrets(lane: String) -> int:
	if not enabled():
		var n := 0
		for node in world.nodes:
			if node.lane == lane and MapLayout.is_lane_site_kind(node.node_kind) and node.side == enemy:
				n += node.turret_count(enemy)
		if world.defense_posts.standing(enemy, lane):
			n += 1
		return n
	_sync()
	var c := 0
	for id: int in _turrets:
		if str((_turrets[id] as Dictionary)["lane"]) == lane:
			c += 1
	if _posts.has(lane) and bool((_posts[lane] as Dictionary)["standing"]):
		c += 1
	return c


## Where our own live lane turrets stand (all lanes, or only `lane`), in the world's order (RT8: the fleet layer's turret cover).
func own_turret_points(lane: String = "") -> Array:
	var out := []
	for node in world.nodes:
		if node.side == team and MapLayout.is_lane_site_kind(node.node_kind) and (lane == "" or node.lane == lane):
			for t in node.slots:
				if t != null and is_instance_valid(t) and t.alive and t.team == team:
					out.append((t as Node2D).global_position)
	return out


## Where the enemy's lane turrets and standing defense posts are as far as the team knows (all lanes, or only `lane`): the
## live ones while the view is off, the records while it is on (RT8: the fleet layer's turret reach). The same set as
## enemy_turrets() counts.
func enemy_turret_points(lane: String = "") -> Array:
	var out := []
	if not enabled():
		for node in world.nodes:
			if node.side == enemy and MapLayout.is_lane_site_kind(node.node_kind) and (lane == "" or node.lane == lane):
				for t in node.slots:
					if t != null and is_instance_valid(t) and t.alive and t.team == enemy:
						out.append((t as Node2D).global_position)
		for ln: String in MapLayout.LANE_ORDER:
			if (lane == "" or ln == lane) and world.defense_posts.standing(enemy, ln):
				out.append(world.defense_posts.site_of(enemy, ln).pos)
		return out
	_sync()
	for id: int in _turrets:
		var rec: Dictionary = _turrets[id]
		if lane == "" or str(rec["lane"]) == lane:
			out.append(rec["pos"] as Vector2)
	for ln: String in MapLayout.LANE_ORDER:
		if (lane == "" or ln == lane) and _posts.has(ln) and bool((_posts[ln] as Dictionary)["standing"]):
			out.append((_posts[ln] as Dictionary)["pos"] as Vector2)
	return out


# --- the siege maths, on the enemy mothership the team knows ----------------------------------------------------

## Where the enemy mothership is against our copy of `lane`: Util.project_on_polyline's answer ("s", "point", "dist").
## While the view is off this is TeamSiege's own answer.
func enemy_ms_on_lane(lane: String) -> Dictionary:
	if not enabled():
		return world.teams[team].enemy_ms_on_lane(lane)
	return Util.project_on_polyline(enemy_ms_pos(), MapLayout.lane_points(lane, team))


## The siege staging point on `lane` (the same maths as TeamSiege.stage_point, on the known mothership place).
func stage_point(lane: String) -> Vector2:
	if not enabled():
		return world.teams[team].siege_stage_point(lane)
	var pts := MapLayout.lane_points(lane, team)
	var frac := float(Rules.tune("siege_stage_frac", TeamSiege.SIEGE_STAGE))
	var gap := float(Rules.tune("siege_stage_gap", TeamSiege.SIEGE_STAGE_GAP))
	var s := minf(Util.polyline_length(pts) * frac, float(enemy_ms_on_lane(lane)["s"]) - gap)
	return Util.polyline_at(pts, maxf(0.0, s))


## The siege assault point on `lane` (the same maths as TeamSiege.assault_point, on the known mothership place).
func assault_point(lane: String) -> Vector2:
	if not enabled():
		return world.teams[team].siege_assault_point(lane)
	var pts := MapLayout.lane_points(lane, team)
	var gap := float(Rules.tune("siege_assault_gap", TeamSiege.ASSAULT_GAP))
	return Util.polyline_at(pts, maxf(0.0, float(enemy_ms_on_lane(lane)["s"]) - gap))


# --- keeping the records -----------------------------------------------------------------------------------------

## Does the team see this enemy unit now? (A test may make it see everything.)
func _sees(u: Unit) -> bool:
	return sees_all or u.visible_to(team)


## Does the team see this place now (its fog is lit there)?
func _sees_point(p: Vector2) -> bool:
	return sees_all or world.vision.is_visible(team, p)


## A hull fraction as whole thousandths.
func _hp(frac: float) -> int:
	return clampi(roundi(frac * 1000.0), 0, PM)


## One ship's strength in micro-points: (1 + size index) x (400000 + 600 x hull thousandths).
func _micro(size_index: int, hp: int) -> int:
	return (1 + size_index) * (BASE_MICRO + HULL_MICRO * hp)


## Bring the records up to date, once per world time (a second ask at the same time does nothing).
func _sync() -> void:
	var now := world.time
	if _ready and now == _t:
		return
	_t = now
	if not _ready:
		_make_start()
		_ready = true
	_update_ships(now)
	_update_defences()
	_update_ms(now)


## The starting records: the map's known layout. The enemy mothership at its home spot with a full hull, every lane
## turret and defense post standing. (Read from the world at the first sync, which is at the first think, when the
## match is still in its opening and every one of these stands where the map puts it.)
func _make_start() -> void:
	var ms := world.mothership(enemy)
	if ms != null:
		_ms = {"pos": ms.global_position, "rot": ms.rotation, "half_len": ms.half_len, "beam": ms.beam, "hp": PM, "seen": -1.0}
	for n: ResourceNode in world.nodes:
		if n.side == enemy and MapLayout.is_lane_site_kind(n.node_kind):
			for t in n.slots:
				if t != null and is_instance_valid(t) and t.alive and t.team == enemy:
					_turrets[t.get_instance_id()] = {"lane": n.lane, "pos": (t as Node2D).global_position, "vis": false}
	for lane: String in MapLayout.LANE_ORDER:
		_posts[lane] = {"standing": true, "pos": world.defense_posts.site_of(enemy, lane).pos}


## Ships: note every enemy ship the team sees now; settle the ones that are gone; drop the ones too old.
func _update_ships(now: float) -> void:
	var live := {}
	for s: Ship in world.ships:
		if s.team != enemy or not s.alive:
			continue
		var id := s.get_instance_id()
		live[id] = true
		var seen := _sees(s)
		if seen:
			_ships[id] = {"pos": s.global_position, "hp": _hp(s.hull_frac()), "si": Rules.size_index(s.size_class), "seen": now, "vis": true}
		elif _ships.has(id):
			(_ships[id] as Dictionary)["vis"] = false
	var gone: Array = []
	for id: int in _ships:
		if live.has(id):
			continue
		# Not among the living: it died (or left the list). Seen dying = its last sighting was in view (or the
		# dead unit's own switch still says seen); then it is no more. Unseen: it stays until it goes stale.
		var rec: Dictionary = _ships[id]
		var obj := instance_from_id(id)
		var seen_dead := sees_all or (obj is Unit and is_instance_valid(obj) and (obj as Unit).visible_to(team)) or (not (obj is Unit and is_instance_valid(obj)) and bool(rec["vis"]))
		if seen_dead:
			gone.append(id)
	var stale := prof.raw("memory_stale_s")
	for id: int in _ships:
		var rec2: Dictionary = _ships[id]
		if roundi((now - float(rec2["seen"])) * 1000.0) > stale and not gone.has(id):
			gone.append(id)
	for id: int in gone:
		_ships.erase(id)


## Turrets and posts: a seen turret or post is recorded standing; a record whose turret is gone is dropped once the
## team sees the place (the fog is lit there).
func _update_defences() -> void:
	var live := {}
	for n: ResourceNode in world.nodes:
		if n.side != enemy or not MapLayout.is_lane_site_kind(n.node_kind):
			continue
		for t in n.slots:
			if t != null and is_instance_valid(t) and t.alive and t.team == enemy:
				var id: int = t.get_instance_id()
				live[id] = true
				if _sees(t as Unit):
					_turrets[id] = {"lane": n.lane, "pos": (t as Node2D).global_position, "vis": true}
	var gone: Array = []
	for id: int in _turrets:
		if not live.has(id) and _sees_point((_turrets[id] as Dictionary)["pos"] as Vector2):
			gone.append(id)
	for id: int in gone:
		_turrets.erase(id)
	for lane: String in MapLayout.LANE_ORDER:
		var rec: Dictionary = _posts[lane]
		var post: Unit = world.defense_posts.site_of(enemy, lane).post
		if post != null and is_instance_valid(post) and post.alive:
			if _sees(post):
				rec["standing"] = (post as DefensePost).is_built()
		elif _sees_point(rec["pos"] as Vector2):
			rec["standing"] = false


## The enemy mothership: its place, turn and hull change only when the team sees it.
func _update_ms(now: float) -> void:
	var ms := world.mothership(enemy)
	if ms == null or _ms.is_empty():
		return
	if _sees(ms):
		_ms["pos"] = ms.global_position
		_ms["rot"] = ms.rotation
		_ms["hp"] = _hp(ms.hull_frac())
		_ms["seen"] = now
