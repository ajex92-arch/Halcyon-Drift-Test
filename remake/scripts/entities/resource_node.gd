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
##     neutral grey when nobody holds it.
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
## the screens and the tests read.

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
## its maximum), the site's record notes a change of state, and the node
## redraws (not with --sim-only, Game.sim_only: then nothing is drawn). World
## calls this every tick.
func tick(dt: float) -> void:
	var regen := MapLayout.ORE_REGEN * value * dt
	for i in ore.size():
		ore[i] = minf(ore_max[i], ore[i] + regen)
	site.update(self, world.tick_count)
	if not Game.sim_only:
		queue_redraw()


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
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Palette.with_alpha(col, 0.55), 6.0, true)
	else:
		SiteMarks.draw_ring(self, Vector2.ZERO, r, v, 6.0)
		_draw_word(SiteMarks.word(v), r)
	draw_circle(Vector2.ZERO, r, Palette.with_alpha(col, 0.04))
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
