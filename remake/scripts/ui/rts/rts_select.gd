class_name RtsSelect
extends RefCounted
## WHAT THIS IS: the Admiral's selection rules as plain functions: which of our squadrons (and our mothership) a
## click, a box or a double-click takes, and the numbers the screens show about a squadron (its ships, its centre,
## its size on the map). It reads the match and never changes it.
##
## HOW IT WORKS: only static functions. A selectable squadron is a record of our team whose kind is "squadron" or
## "ship" (a bought squadron; a pilot's wingman is kind "wing" and is never selectable) with at least one ship alive.
## pick() answers a click: a squadron within the pick radius beats the mothership, which beats the map. The pick
## radius is the same on screen at any zoom: 14 screen pixels = 14 * px world units (px = 1 / zoom), grown by the
## ship's own size so a big hull is easy to hit. in_box() answers a box: the squadrons with a ship inside it, and
## the mothership only when there is no squadron. same_hull() answers a double-click: every squadron of one hull,
## inside a rectangle (the screen) or on the whole map. The answers are ids of squad records (World.squads); a
## screen keeps the ids and asks again each time it draws, because a squadron can lose its last ship.
##
## WHO USES IT: CommandOverlay (clicks, boxes, rings), SelectionPanel (the tags), CommandView and CommandCard
## (what is selected), tests/rts_tour.gd.

## The pick radius in screen pixels (the same for every icon at any zoom).
const PICK_PX := 14.0
## A drag longer than this many screen pixels is a box, not a click.
const BOX_PX := 6.0


## The selectable squadron records of `team`, in id order: bought squadrons and ships with a ship alive.
static func our_squads(world: World, team: int) -> Array[Squad]:
	var out: Array[Squad] = []
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var rec: Squad = world.squads[id]
		if rec.team == team and is_selectable(world, rec):
			out.append(rec)
	return out


## Can `rec` be selected: a bought squadron or ship (not a wingman) that still has a ship alive?
static func is_selectable(world: World, rec: Squad) -> bool:
	if rec == null or not (rec.kind == "squadron" or rec.kind == "ship"):
		return false
	return not ships_of(world, rec).is_empty()


## The ships of `rec` that are alive, in the record's order.
static func ships_of(world: World, rec: Squad) -> Array[Ship]:
	var out: Array[Ship] = []
	for uid: int in rec.member_uids:
		var u: Variant = world.by_uid.get(uid)
		if u != null and is_instance_valid(u) and (u as Unit).alive and u is Ship:
			out.append(u as Ship)
	return out


## The middle of `rec`'s ships (the origin when it has none).
static func centre_of(world: World, rec: Squad) -> Vector2:
	var ships := ships_of(world, rec)
	if ships.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for s: Ship in ships:
		sum += s.global_position
	return sum / float(ships.size())


## How far from `centre` the farthest ship of `rec` reaches, hull included (world units).
static func reach_of(world: World, rec: Squad, centre: Vector2) -> float:
	var r := 0.0
	for s: Ship in ships_of(world, rec):
		r = maxf(r, s.global_position.distance_to(centre) + s.radius)
	return r


## The nearest of our squadrons to world point `p`, within PICK_PX screen pixels (`px` world units a pixel) of
## one of its ships' hulls: its id, or -1.
static func squad_at(world: World, team: int, p: Vector2, px: float) -> int:
	var best := -1
	var best_d := INF
	for rec: Squad in our_squads(world, team):
		for s: Ship in ships_of(world, rec):
			var d := maxf(0.0, s.global_position.distance_to(p) - s.radius)
			if d <= PICK_PX * px and d < best_d:
				best_d = d
				best = rec.id
	return best


## Is our mothership within the pick radius of world point `p`?
static func base_at(world: World, team: int, p: Vector2, px: float) -> bool:
	var ms := world.mothership(team)
	return ms != null and is_instance_valid(ms) and ms.alive and ms.hull_dist(p) <= PICK_PX * px


## What a click at world point `p` takes: {"kind": "squad", "id"}, {"kind": "base", "id": -1} or {"kind": "none", "id": -1}
## (squadrons beat the mothership, which beats the map).
static func pick(world: World, team: int, p: Vector2, px: float) -> Dictionary:
	var id := squad_at(world, team, p, px)
	if id >= 0:
		return {"kind": "squad", "id": id}
	if base_at(world, team, p, px):
		return {"kind": "base", "id": -1}
	return {"kind": "none", "id": -1}


## What a box `r` (world rectangle) takes: {"squads": ids of our squadrons with a ship inside, "base": the mothership
## is inside and no squadron was}.
static func in_box(world: World, team: int, r: Rect2) -> Dictionary:
	var ids: Array[int] = []
	for rec: Squad in our_squads(world, team):
		for s: Ship in ships_of(world, rec):
			if r.has_point(s.global_position):
				ids.append(rec.id)
				break
	var base := false
	if ids.is_empty():
		var ms := world.mothership(team)
		base = ms != null and is_instance_valid(ms) and ms.alive and r.has_point(ms.global_position)
	return {"squads": ids, "base": base}


## The ids of our squadrons of hull `hull_id`: those with a ship inside `r`, or every one when `r` has no area
## (the Ctrl+double-click: the whole map).
static func same_hull(world: World, team: int, hull_id: String, r: Rect2) -> Array[int]:
	var ids: Array[int] = []
	for rec: Squad in our_squads(world, team):
		if rec.hull_id != hull_id:
			continue
		if r.size == Vector2.ZERO:
			ids.append(rec.id)
			continue
		for s: Ship in ships_of(world, rec):
			if r.has_point(s.global_position):
				ids.append(rec.id)
				break
	return ids


## The world rectangle the camera shows now.
static func view_rect(world: World) -> Rect2:
	var cam: Camera2D = world.camera
	var size := cam.get_viewport_rect().size / cam.zoom
	var c := cam.get_screen_center_position()
	return Rect2(c - size * 0.5, size)


## Keep only the ids of `ids` that are still selectable squadrons of `team` (in the same order, no repeats).
static func live_ids(world: World, team: int, ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in ids:
		var rec: Squad = world.squads.get(id)
		if rec != null and rec.team == team and is_selectable(world, rec) and not out.has(id):
			out.append(id)
	return out
