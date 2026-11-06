class_name Arrivals
extends RefCounted
## WHAT THIS IS: where a finished ship item turns into ships. A squadron of small ships
## and every corvette or frigate appear at the mothership's launch spots (and slide out in
## the picture); a capital ship appears at a free spot beside the mothership, after a warp
## streak that is drawn across the map. The ships are in the game from the first tick; the
## slide and the streak are only drawings.
##
## HOW IT WORKS: static functions. Production calls on_progress() every tick for each ship
## item that is building: when a capital ship's last WARP_TICKS begin, it picks the warp spot
## then (the mothership may have moved since the order) and writes the streak's drawing
## data. When an item's time is complete Production calls arrive(): while the mothership
## cannot launch (a systems failure) it answers false and the item waits, complete, saying
## "waiting: mothership", and the ships appear on the first tick the mothership is
## available again. Otherwise arrive() makes one crew (Crew.make) and one ship for each ship
## of the item, files "ship_built" for each, puts the ships into the squad record, gives each
## the stand-in brain (Standin.attach) and answers true.
## The launch spot of a small ship has no dice: the first ship of a record takes the
## mothership's spot number (record id modulo 5), the next the following spots, wrapping.
## The warp spot is the first free one of seven tried in a fixed order around the
## mothership (WARP_ANGLES), at a distance that clears its hull; if none is free the first is
## used anyway and the ships' separation sorts it out.
## The drawing data go into Production.fx: Dictionaries {kind: "slide" or "warp", from, to,
## t0, t1 (ticks), uid, hull, team} that RtsFx draws; old ones are dropped.
##
## WHO USES IT: Production (progress, arrival and the removal of a build that stopped), the
## tests (tests/arrival_check.gd) and RtsFx (the data).


## Called every tick for the building ship item `it` of `prod`, after its count went up. At the
## start of a capital ship's last WARP_TICKS: pick the warp spot and start the streak.
static func on_progress(world: World, prod: Production, it: Dictionary) -> void:
	if not RtsHulls.is_capital(str(it["what"])) or it["warp"]:
		return
	if int(it["done"]) < int(it["ticks"]) - RtsHulls.WARP_TICKS:
		return
	var ms := world.mothership(prod.team)
	if ms == null:
		return
	it["warp"] = true
	var spot := warp_spot(world, ms, str(it["what"]))
	it["spot_x"] = spot.x
	it["spot_y"] = spot.y
	var edge := _edge_of(world, spot)
	prod.fx.append({"kind": "warp", "from": edge, "to": spot, "t0": world.tick_count, "t1": world.tick_count + RtsHulls.WARP_TICKS, "uid": 0, "hull": str(it["what"]), "team": prod.team, "item": str(it["id"])})


## The time of ship item `it` is complete. Makes its ships and files the events; returns true
## when they are there, false while the mothership cannot launch.
static func arrive(world: World, prod: Production, it: Dictionary) -> bool:
	var ms := world.mothership(prod.team)
	if ms == null or not ms.available():
		return false
	var squad: Squad = world.squads.get(int(it["squad"])) as Squad
	if squad == null:
		return true
	var hull := str(it["what"])
	var capital := RtsHulls.is_capital(hull)
	var radius := float(Ships.get_def(hull)["radius"])
	var first_slot := squad.id % 5
	prod.fx = prod.fx.filter(func(e: Dictionary) -> bool: return str(e.get("item", "")) != str(it["id"]) or e["kind"] != "warp" or int(e["uid"]) != 0)
	for i in int(it["count"]):
		# Step 1: where the ship appears.
		var pos: Vector2
		if capital:
			pos = Vector2(float(it.get("spot_x", 0)), float(it.get("spot_y", 0))) if it["warp"] else warp_spot(world, ms, hull)
		else:
			pos = ms.launch_point((first_slot + i) % 5, radius)
		# Step 2: its crew, its ship, its place in the record, its brain.
		var crew := Crew.make(world, prod.team, hull, squad, i)
		world.profiles.append(crew)
		var ship := world.spawner.spawn_pilot_ship(crew, pos, ms.rotation)
		crew.ship = ship
		crew.state = "flying"
		squad.member_uids.append(ship.uid)
		if i == 0:
			squad.rally = prod.rally_point(str(it["rally"]), int(it["rx"]), int(it["ry"]))
		Standin.attach(world, ship, squad)
		# Step 3: the event, the picture's data and the cue.
		_ship_built(world, prod, it, ship)
		if capital:
			prod.fx.append({"kind": "warp_land", "from": pos, "to": pos, "t0": world.tick_count, "t1": world.tick_count + RtsHulls.SLIDE_TICKS, "uid": ship.uid, "hull": hull, "team": prod.team, "item": str(it["id"])})
		else:
			prod.fx.append({"kind": "slide", "from": ms.global_position, "to": pos, "t0": world.tick_count, "t1": world.tick_count + RtsHulls.SLIDE_TICKS, "uid": ship.uid, "hull": hull, "team": prod.team, "item": str(it["id"])})
			Events.cue.emit("launch", pos)
	squad.state = 0
	_prune(world, prod)
	return true


## Item `it` stopped building before its ships arrived (cancelled or held): drop the streak
## that was drawn for it.
static func on_removed(_world: World, prod: Production, it: Dictionary) -> void:
	it.erase("spot_x")
	it.erase("spot_y")
	prod.fx = prod.fx.filter(func(e: Dictionary) -> bool: return str(e.get("item", "")) != str(it["id"]) or int(e["uid"]) != 0)


# --- the warp spot ----------------------------------------------------------------------

## The warp spot beside mothership `ms` for a ship of `hull`: the first free one of the
## seven tried in WARP_ANGLES order, as a whole-number point. See the top of the file.
static func warp_spot(world: World, ms: Mothership, hull: String) -> Vector2i:
	var r := float(Ships.get_def(hull)["radius"])
	var dist := ms.half_len + ms.beam * 0.5 + r + RtsHulls.WARP_BEYOND
	var clear := r + RtsHulls.WARP_CLEAR
	for deg: int in RtsHulls.WARP_ANGLES:
		var p := ms.global_position + Vector2.from_angle(ms.rotation + deg_to_rad(float(deg))) * dist
		if _is_clear(world, p, clear):
			return Order.point(p)
	return Order.point(ms.global_position + Vector2.from_angle(ms.rotation + deg_to_rad(float(RtsHulls.WARP_ANGLES[0]))) * dist)


## Is the circle of radius `clear` around `p` free of units, structures and rocks? The units
## are those of the previous tick (the spatial hashes are rebuilt once a tick).
static func _is_clear(world: World, p: Vector2, clear: float) -> bool:
	var found: Array = []
	world.unit_hash.query(p, clear + 80.0, found)
	for u: Unit in found:
		if u.alive and p.distance_to(u.global_position) < clear + u.radius:
			return false
	var big: Array = []
	world.big_hash.query(p, clear + 400.0, big)
	for u: Unit in big:
		if u.alive and p.distance_to(u.global_position) < clear + u.radius:
			return false
	return not world.asteroids.blocked(p, clear)


# --- small helpers --------------------------------------------------------------------

## Where the warp streak starts: the point on the map's edge nearest to `spot`.
static func _edge_of(world: World, spot: Vector2i) -> Vector2i:
	var w := float(MapLayout.W)
	var h := float(MapLayout.H)
	var x := float(spot.x)
	var y := float(spot.y)
	var to_left := x
	var to_right := w - x
	var to_top := y
	var to_bottom := h - y
	var nearest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if nearest == to_left:
		return Vector2i(0, spot.y)
	if nearest == to_right:
		return Vector2i(int(w), spot.y)
	if nearest == to_top:
		return Vector2i(spot.x, 0)
	return Vector2i(spot.x, int(h))


## File "ship_built" for `ship` of item `it`.
static func _ship_built(world: World, prod: Production, it: Dictionary, ship: Ship) -> void:
	if world.events_rts == null:
		return
	world.events_rts.push({"kind": "ship_built", "team": prod.team, "pos": RtsEvents.point_of(ship.global_position), "uid": ship.uid, "data": {"item": str(it["id"]), "squad": int(it["squad"])}})


## Drop the drawing data that is over.
static func _prune(world: World, prod: Production) -> void:
	prod.fx = prod.fx.filter(func(e: Dictionary) -> bool: return int(e["t1"]) > world.tick_count - 2)
