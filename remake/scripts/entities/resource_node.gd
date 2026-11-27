class_name ResourceNode
extends Node2D
## WHAT THIS IS: a node: a round area of the map with spots ("slots") around
## it where turrets can be built. An ore node (in the jungle) is also a field of
## asteroid rocks full of ore (the game's money); a turret site (in a lane) has
## no ore. It can't be destroyed. DESIGN.md A4, A9.
##
## HOW IT WORKS:
##   - Ore: each rock starts with MapLayout.ORE_PER_ROCK (1,600) x the
##     node's `value` and slowly grows back (MapLayout.ORE_REGEN: 6 x value
##     ore per second, per rock). Only the admiral's mining drones mine it
##     (pilots can't): they ask best_rock() and call take_ore().
##   - Turrets: each node has turret slots on the side facing its lane (or the
##     way the plan says). The lane turret sites ("outer", "inner" and
##     "inhibitor": three a team on every lane, each with one slot) and
##     "jungle_team" nodes (a team's own ore nodes in the jungle) belong to
##     one team: only that team may build there. The "inner" and "inhibitor"
##     sites, the ones nearer the team's mothership, take PD or torpedo
##     turrets, the others PD. A lane site starts the match with a finished PD
##     turret on it (WorldSetup); the admiral only builds there again after the
##     turret was destroyed and the rebuild lock ended. "jungle_shared" nodes
##     (ore nodes on the centre line of the jungle) take PD turrets from
##     either team, as long as no enemy turret stands there.
##     build_blocker() checks every rule, including "no enemy ships close"
##     and "not within 60 s of a turret dying here".
##   - Owner: the team with a live turret here holds the node
##     (owner_team()). The node draws a ring in that team's colour, or
##     neutral grey when nobody holds it. The picture is drawn again only when something it
##     shows has changed (_look_key(): the holder, the site's state, each rock's ore, the
##     turrets standing, the zoom) and only while the node is near the camera's view
##     (ViewCull), not on every tick.
##   - The figure: every ore node shows one figure "X/Y" under its ring, close up only. X is how
##     many of the viewer's team's drones are going to or mining at the node. Y is the most
##     drones the node supports without running dry (its breakeven): the ore it grows back each
##     second over the ore one drone really brings in each second over a whole trip (cutting plus
##     the flight home and back), as a whole number rounded down. Both are worked out by numbers();
##     the figure is coloured by how full the node is (fullness_band): green at 75% or more,
##     yellow from 15% up to 75%, and below 15% the danger colour with the danger triangle
##     (never the colour alone). Pulling the camera out fades the figure away (figure_alpha) and
##     the whole node takes a faint tint in the same colour (tint_alpha); the triangle stays at
##     every zoom. The figure shows for the viewer's team only (none for a spectator).
## It is not a Unit: it extends Node2D (a plain 2D thing in the scene), so
## it can't be shot and has no sim_update(); World calls tick() instead.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: WorldSetup makes one per node of the map (setup()). World
## calls tick() every tick and finds nodes by id (World.node_by_id).
## Turrets put themselves in `slots` and set rebuild_lock_until when they
## die; MiningDrone mines it; AdmiralCommand and the AI admiral
## (AdmiralBuilder) use build_blocker(), free_slot() and turret_count();
## WorldMining scores nodes for drones; the minimap, the admiral's board,
## the HUD and the news read its name, owner and ore. The site record
## (TurretSite) holds the id, the kind, the build circle and the state that
## the screens and the tests read. The map's picture of the node (and so the
## figure, its colour and the tint) is drawn by this class itself.

## The fullest band (see fullness_band): green.
const BAND_GREEN := 0
## The middle band (see fullness_band): yellow.
const BAND_YELLOW := 1
## The emptiest band (see fullness_band): low, drawn in the danger colour with the danger triangle.
const BAND_LOW := 2
## A node is in the green band from this fullness (ore left over its most ore) up.
const GREEN_FROM := 0.75
## A node is in the yellow band from this fullness up to GREEN_FROM; below it is the low band.
const YELLOW_FROM := 0.15
## The colour of the green band.
const NODE_GREEN := Palette.REPAIR
## The colour of the yellow band (kept clear of the team, scum and danger colours).
const NODE_YELLOW := Color(0.98, 0.88, 0.25)
## The colour of the low band: the game's danger colour, always drawn with the danger triangle.
const NODE_LOW := Palette.DANGER
## The figure is fully shown when the view is this many world units across or narrower.
const FIGURE_FULL_VIEW_W := 3000.0
## The figure is gone when the view is this many world units across or wider (it fades linearly in between).
const FIGURE_GONE_VIEW_W := 5000.0
## How strong the tint of the whole node is once the figure is gone.
const TINT_ALPHA := 0.22
## The haul is worked out again only when the drop-off point has moved more than this many world units.
const HAUL_REDO := 100.0

## Its id, used to find it (World.node_by_id) and in drone orders.
var node_id := ""
## Its name on the map and in the news.
var node_name := ""
## The kind (see MapLayout.NODES): "outer", "inner" or "inhibitor" (a lane
## turret site of one team: only that team builds; PD, and also torpedo turrets
## at "inner" and "inhibitor"), "jungle_team" (one team's ore node in the
## jungle: only that team builds, PD) or "jungle_shared" (a shared ore node in
## the jungle: PD turrets from either team).
var node_kind := "jungle_shared"
## Team that may build here (lane sites and jungle-team nodes) or -1 (shared
## nodes: either).
var side := -1
## The lane it sits beside ("top", "mid" or "bot").
var lane := "mid"
## Richness multiplier for ore per rock and ore regrowth (1.0 = normal).
var value := 1.0
## The game world it belongs to.
var world: World = null
## Where each turret slot is (world positions).
var slot_pos: PackedVector2Array = PackedVector2Array()
## The turret on each slot, or null for an empty slot (Turret.setup() fills
## it, Turret.on_killed() empties it). To be safe, the functions below also
## skip dead or freed turrets.
var slots: Array = []
## Where each ore rock is (world positions).
var ore_pos: PackedVector2Array = PackedVector2Array()
## Each rock's radius, in world units.
var ore_r: PackedFloat32Array = PackedFloat32Array()
## The ore left in each rock right now.
var ore: PackedFloat32Array = PackedFloat32Array()
## The most ore each rock can hold.
var ore_max: PackedFloat32Array = PackedFloat32Array()
## No turret can be built here until this match time, in seconds
## (TurretData.REBUILD_LOCK after one is destroyed).
var rebuild_lock_until := 0.0
## The site's record: its id, name, kind, build circle, clear window and state
## (see TurretSite). Made by setup().
var site: TurretSite = null
## What the picture last drawn showed (see _look_key()); empty before the first drawing.
var _look := PackedInt32Array()
## The last haul worked out for each team (team -> {"at": the drop-off point it was worked out for, "len": the route length}).
var _hauls := {}


## Fill the node in from the map's description `info` (id, name, kind,
## side, lane, value, position, turret slots and ore rocks). WorldSetup
## calls this once per node.
func setup(w: World, info: Dictionary) -> void:
	world = w
	# --sim-only: nothing is drawn, so the node hides its picture.
	if Game.sim_only:
		visible = false
	node_id = info["id"]
	node_name = info["name"]
	node_kind = info["kind"]
	side = int(info["side"])
	lane = info["lane"]
	value = float(info["value"])
	position = info["pos"]
	site = TurretSite.new(node_id, node_name, node_kind)
	# One empty entry per turret slot.
	slot_pos = info["slot_pos"]
	slots.resize(slot_pos.size())
	# Every rock starts full: ORE_PER_ROCK x value.
	for r: Dictionary in info["ore"]:
		ore_pos.append(r["pos"])
		ore_r.append(float(r["r"]))
		var amount := MapLayout.ORE_PER_ROCK * value
		ore.append(amount)
		ore_max.append(amount)
	# Draw the node below the units.
	z_index = -1


## The team holding this node (it has a live turret here), or -1 for
## nobody.
func owner_team() -> int:
	for t in slots:
		if t != null and is_instance_valid(t) and t.alive:
			return t.team
	return -1


## How many live turrets team `team` has here.
func turret_count(team: int) -> int:
	var n := 0
	for t in slots:
		if t != null and is_instance_valid(t) and t.alive and t.team == team:
			n += 1
	return n


## The first slot with no live turret (an index), or -1 if all are taken.
func free_slot() -> int:
	for i in slots.size():
		var t = slots[i]
		if t == null or not is_instance_valid(t) or not t.alive:
			return i
	return -1


## Why `team` can't build a turret of type `ttype` here, as a sentence for
## the player, or "" if it can. The rules are checked in this order.
func build_blocker(team: int, ttype: String) -> String:
	if MapLayout.is_lane_site_kind(node_kind) and side != team:
		return "That turret site belongs to the enemy team"
	if node_kind == "jungle_team" and side != team:
		return "That jungle node belongs to the enemy team"
	if world.time < rebuild_lock_until:
		return "A turret was just destroyed here: no building for %ds" % int(ceil(rebuild_lock_until - world.time))
	if ttype == "torp" and node_kind not in TurretData.TORP_SITE_KINDS:
		return "Torpedo turrets only go at the inner and inhibitor sites near our mothership"
	var holder := owner_team()
	if holder >= 0 and holder != team:
		return "The enemy has turrets here"
	if free_slot() < 0:
		return "Every turret slot here is taken"
	# An enemy pilot ship or minion within the site's build circle.
	if world.any_enemy_ship_near(global_position, site.build_radius, team):
		var near := world.enemy_ships_summary(global_position, site.build_radius, team)
		return "Enemy ships are too close: %s within %s, nearest %s" % [_count_text(int(near["pilots"]), int(near["minions"])), Util.money(site.build_radius), Util.money(float(near["nearest"]))]
	return ""


## "2 pilot ships and 4 minions", "1 pilot ship", "3 minions": the enemy ships
## named in the reason a build is refused.
func _count_text(pilots: int, minions: int) -> String:
	var parts := PackedStringArray()
	if pilots > 0:
		parts.append("%d pilot ship%s" % [pilots, "" if pilots == 1 else "s"])
	if minions > 0:
		parts.append("%d minion%s" % [minions, "" if minions == 1 else "s"])
	return " and ".join(parts)


## All the ore left here, over every rock.
func total_ore() -> float:
	var s := 0.0
	for v in ore:
		s += v
	return s


## The most ore this node can hold, over every rock.
func total_ore_max() -> float:
	var s := 0.0
	for v in ore_max:
		s += v
	return s


## The ore a drone brings in each second over a whole trip: its hold of `capacity` ore is cut at
## `mine_rate` ore a second, then it flies `haul` world units home and `haul` back at `speed`
## (the speeding up and slowing down are ignored). A static function, so a test can call it.
static func trip_draw(capacity: float, mine_rate: float, speed: float, haul: float) -> float:
	if capacity <= 0.0 or mine_rate <= 0.0 or speed <= 0.0:
		return 0.0
	return capacity / (capacity / mine_rate + 2.0 * haul / speed)


## How many drones a node supports without running dry (its breakeven, Y of the figure): the ore
## it grows back each second (`refill`) over the ore one drone brings in each second (`draw`),
## as a whole number rounded down. 0 when `draw` is not above 0.0001, so there is never a division
## by zero.
static func drones_supported(refill: float, draw: float) -> int:
	if draw <= 0.0001 or refill <= 0.0:
		return 0
	return int(floorf(refill / draw))


## Which band a node's fullness (ore left over its most ore, 0 to 1) is in: BAND_GREEN from
## GREEN_FROM up, BAND_YELLOW from YELLOW_FROM up to GREEN_FROM, else BAND_LOW.
static func fullness_band(fullness: float) -> int:
	if fullness >= GREEN_FROM:
		return BAND_GREEN
	if fullness >= YELLOW_FROM:
		return BAND_YELLOW
	return BAND_LOW


## The colour of band `band` (NODE_GREEN, NODE_YELLOW or NODE_LOW).
static func band_color(band: int) -> Color:
	if band == BAND_GREEN:
		return NODE_GREEN
	if band == BAND_YELLOW:
		return NODE_YELLOW
	return NODE_LOW


## Does band `band` go with the danger triangle? Only the low band does: the triangle goes with the
## danger colour and with nothing else, so the colour is never the only sign of danger.
static func shows_danger(band: int) -> bool:
	return band == BAND_LOW


## How strongly the figure shows when the view is `view_w` world units across: 1.0 at
## FIGURE_FULL_VIEW_W or narrower, 0.0 at FIGURE_GONE_VIEW_W or wider, a straight line between.
static func figure_alpha(view_w: float) -> float:
	return clampf((FIGURE_GONE_VIEW_W - view_w) / (FIGURE_GONE_VIEW_W - FIGURE_FULL_VIEW_W), 0.0, 1.0)


## How strongly the whole node is tinted when the view is `view_w` world units across: nothing while
## the figure shows fully, TINT_ALPHA once it is gone, so the figure fades out as the tint fades in.
static func tint_alpha(view_w: float) -> float:
	return TINT_ALPHA * (1.0 - figure_alpha(view_w))


## The numbers of this node as seen by `team`: {} for a node with no rocks or a `team` below 0,
## else `drones` (how many of the team's drones are going to or mining at this node: X),
## `refill` (the most ore the node grows back each second: every rock's regrowth added up),
## `draw` (the ore one drone of the team brings in each second over a whole trip, see trip_draw),
## `breakeven` (refill over draw, a float: the figure's Y is its whole part) and `fullness` (the
## ore left over the most ore, 0 to 1). Reads the world and changes nothing.
func numbers(team: int) -> Dictionary:
	if ore.is_empty() or team < 0 or world == null:
		return {}
	var drones := 0
	for d in world.mining_drones:
		if d.team == team and d.node_id == node_id:
			drones += 1
	var refill := MapLayout.ORE_REGEN * value * float(ore.size())
	var spec: Dictionary = Structures.MINING_DRONE
	var capacity := float(spec["capacity"]) * (1.0 + world.teams[team].mining_capacity)
	var draw := trip_draw(capacity, float(spec["mine_rate"]), float(spec["speed"]), _haul(team))
	var ore_max_total := total_ore_max()
	return {
		"drones": drones,
		"refill": refill,
		"draw": draw,
		"breakeven": refill / draw if draw > 0.0001 else 0.0,
		"fullness": total_ore() / ore_max_total if ore_max_total > 0.0 else 0.0,
	}


## How far a drone of `team` flies from this node to its drop-off point, in world units: the length
## of the route it flies (the same route call as MiningDrone, over the jungle roads). Kept per team
## and worked out again only when the drop-off point has moved more than HAUL_REDO.
func _haul(team: int) -> float:
	var drop := WorldMining.drop_off_point(world, team, global_position)
	var kept: Dictionary = _hauls.get(team, {})
	if not kept.is_empty() and (kept["at"] as Vector2).distance_to(drop) <= HAUL_REDO:
		return float(kept["len"])
	var route := world.map.route.path(drop, global_position, true)
	var length := 0.0
	if route.size() < 2:
		length = drop.distance_to(global_position)
	else:
		for i in range(1, route.size()):
			length += route[i - 1].distance_to(route[i])
	_hauls[team] = {"at": drop, "len": length}
	return length


## The figure of this node for `team`: "X/Y" (for example "2/4"), X the team's drones at the node
## and Y the most it supports without running dry; "" for a node with no rocks or a `team` below 0.
func figure_text(team: int) -> String:
	var nums := numbers(team)
	if nums.is_empty():
		return ""
	return "%d/%d" % [int(nums["drones"]), drones_supported(float(nums["refill"]), float(nums["draw"]))]


## The rock a drone at `from` should mine (an index), or -1 if the node is
## dry. Rocks with under 20 ore are skipped; of the rest, the best score
## wins: its ore minus 0.2 x its distance from `from`, so a rich rock wins
## unless it is much further away.
func best_rock(from: Vector2) -> int:
	var best := -1
	var score := -INF
	for i in ore.size():
		if ore[i] < 20.0:
			continue
		var s := ore[i] - from.distance_to(ore_pos[i]) * 0.2
		if s > score:
			score = s
			best = i
	return best


## Take up to `amount` ore from rock `i`. Returns how much was taken (less
## if the rock has less).
func take_ore(i: int, amount: float) -> float:
	var got := minf(ore[i], amount)
	ore[i] -= got
	return got


## One tick of `dt` seconds: every rock grows back a little (never above
## its maximum) and the site's record notes a change of state. World calls this
## every tick. (The picture is asked for in _process(), not here: a frame can hold
## several ticks.)
func tick(dt: float) -> void:
	var regen := MapLayout.ORE_REGEN * value * dt
	for i in ore.size():
		ore[i] = minf(ore_max[i], ore[i] + regen)
	site.update(self, world.tick_count)


## Every frame: ask for a new picture only when what the picture shows has changed (see
## _look_key()), and only while the node is near the camera's view (a node far from it is
## brought up to date on the first frame it comes near). A frame can hold several ticks of
## the match, and the picture used to be asked for on every one of them.
func _process(_dt: float) -> void:
	if world == null or Game.sim_only or not is_visible_in_tree():
		return
	if not ViewCull.near(get_viewport(), global_position, MapLayout.NODE_RADIUS + 900.0):
		return
	var key := _look_key()
	if key != _look:
		_look = key
		queue_redraw()


## What _draw() shows, as a list of whole numbers that changes when the picture must: who
## holds the node and who is looking, the site's state (its build or lock progress in 64ths),
## each rock's ore in 128ths (and whether it is dry), whether each slot has a live turret, and
## the camera zoom in steps of 2%. The last five entries are what the figure shows: the fullness
## band, X, Y, how strongly the figure shows in 20ths, and 1 when the danger triangle shows
## (-1, -1, -1, 0, 0 when the viewer has no figure: a spectator, or a node with no rocks).
func _look_key() -> PackedInt32Array:
	var v := SiteMarks.view(world, self, world.viewer_team)
	var z := _px()
	var key := PackedInt32Array([owner_team(), world.viewer_team, String(v["state"]).hash(), int(v["team"]), int(v["left"]), int(float(v["progress"]) * 64.0), int(v["p0"]) * 16 + int(v["p1"]), int(floor(log(z) / 0.0198))])
	for i in ore.size():
		var left := ore[i] / ore_max[i] if ore_max[i] > 0.0 else 0.0
		key.append(int(left * 128.0) + (1024 if left > 0.05 else 0))
	for t in slots:
		key.append(1 if (t != null and is_instance_valid(t) and t.alive) else 0)
	var nums := numbers(world.viewer_team)
	if nums.is_empty():
		key.append_array(PackedInt32Array([-1, -1, -1, 0, 0]))
	else:
		var band := fullness_band(float(nums["fullness"]))
		key.append(band)
		key.append(int(nums["drones"]))
		key.append(drones_supported(float(nums["refill"]), float(nums["draw"])))
		key.append(int(roundf(figure_alpha(_view_w()) * 20.0)))
		key.append(1 if shows_danger(band) else 0)
	return key


## How many world units across the camera's view is: the viewport's width over the camera zoom
## (zoom limited to at least 0.02, as _px() does). 0.0 with no camera, which counts as close.
func _view_w() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 0.0
	return get_viewport().get_visible_rect().size.x / maxf(0.02, cam.zoom.x)


## World units per screen pixel at the current camera zoom (zoom limited to at
## least 0.02), so lines and words keep their size on screen.
func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(0.02, cam.zoom.x if cam != null else 1.0)


## Write `text` (a SiteMarks word) in white with a dark outline, centred under
## the ring of radius `r`; nothing for "".
func _draw_word(text: String, r: float) -> void:
	if text == "":
		return
	var px := _px()
	var font := ThemeDB.fallback_font
	var size := int(maxf(10.0, 13.0 * px))
	var at := Vector2(-300.0 * px, r + 20.0 * px + float(size))
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 600.0 * px, size, int(4.0 * px), Palette.VOID)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 600.0 * px, size, Palette.ICE)


## Godot calls this to draw the node (after queue_redraw()). Positions here
## are relative to the node's centre.
func _draw() -> void:
	# Step 1: the ring, 120 outside the node's radius, with a faint fill in the
	# holder's colour (or neutral grey). A shared jungle node and any site that
	# is being built or locked show their state as a ring style and a word
	# (SiteMarks); the other sites keep the plain ownership ring.
	var holder := owner_team()
	var col := Palette.team(holder) if holder >= 0 else Palette.NEUTRAL
	var r := MapLayout.NODE_RADIUS + 120.0
	var v := SiteMarks.view(world, self, world.viewer_team)
	if String(v["state"]) == SiteMarks.PLAIN:
		# A ring that shows a team colour follows HELD (the team's mark, and Vhorr's teeth) without a word; a plain grey one stays plain.
		if holder >= 0:
			SiteMarks.draw_ring(self, Vector2.ZERO, r, SiteMarks.held_view(holder), 6.0, _px(), true)
		else:
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Palette.with_alpha(col, 0.55), 6.0, true)
	else:
		SiteMarks.draw_ring(self, Vector2.ZERO, r, v, 6.0, _px(), true)
		_draw_word(SiteMarks.word_world(v), r)
	draw_circle(Vector2.ZERO, r, Palette.with_alpha(col, 0.04))
	# The tint: as the camera pulls out the figure fades and the whole node takes a faint tint in its
	# fullness colour (under the rocks, so they stay visible). A viewer with no figure gets none.
	var px := _px()
	var nums := numbers(world.viewer_team)
	var band := -1
	if not nums.is_empty():
		band = fullness_band(float(nums["fullness"]))
		draw_circle(Vector2.ZERO, r, Palette.with_alpha(band_color(band), tint_alpha(_view_w())))
	# The real build circle of a shared jungle node, thin and dashed.
	if node_kind == "jungle_shared":
		SiteMarks.dashed_circle(self, Vector2.ZERO, site.build_radius, Palette.with_alpha(Palette.NEUTRAL, 0.35), 1.5 * _px())
	# Step 2: each rock: a dot (dry-coloured at 5% ore or less) and an arc
	# around it showing how much ore is left, starting at the top and going
	# clockwise.
	for i in ore_pos.size():
		var local := ore_pos[i] - global_position
		var left := ore[i] / ore_max[i] if ore_max[i] > 0.0 else 0.0
		draw_circle(local, ore_r[i] * 0.55, Palette.ORE_ROCK if left > 0.05 else Palette.ORE_DRY)
		draw_arc(local, ore_r[i] + 14.0, -PI / 2.0, -PI / 2.0 + TAU * left, 24, Palette.with_alpha(Palette.ORE, 0.8), 4.0, true)
	# Step 3: a faint circle on every slot without a live turret.
	for i in slot_pos.size():
		var sp := slot_pos[i] - global_position
		var t = slots[i]
		if t == null or not is_instance_valid(t) or not t.alive:
			draw_arc(sp, 70.0, 0.0, TAU, 24, Palette.with_alpha(col, 0.35), 3.0, true)
	# Step 4: the figure "X/Y" under the ring (below the node's word when it has one), in the fullness
	# colour, fading out as the camera pulls out; and, at every zoom, the danger triangle just above
	# the ring while the node is in the low band (never colour alone). Nothing for a viewer with no figure.
	if nums.is_empty():
		return
	var fa := figure_alpha(_view_w())
	if fa > 0.0:
		var font := ThemeDB.fallback_font
		var size := int(maxf(14.0, 20.0 * px))
		var top := r + 20.0 * px
		if String(v["state"]) != SiteMarks.PLAIN and SiteMarks.word_world(v) != "":
			top += float(int(maxf(10.0, 13.0 * px))) + 6.0 * px
		var at := Vector2(-300.0 * px, top + float(size))
		var text := figure_text(world.viewer_team)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 600.0 * px, size, int(4.0 * px), Palette.with_alpha(Palette.VOID, fa))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 600.0 * px, size, Palette.with_alpha(band_color(band), fa))
	if shows_danger(band):
		Glyphs.danger(self, Vector2(0.0, -(r + 20.0 * px + 0.5 * Glyphs.SIDE * px)), Glyphs.SIDE * px)
