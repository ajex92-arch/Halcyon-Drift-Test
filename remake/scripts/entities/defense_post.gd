class_name DefensePost
extends Unit
## WHAT THIS IS: a lane defense post: the unarmed station at the home end of a
## lane, beside the lane's inhibitor turret, from which that lane's minion waves
## launch. A team has one on each lane. DESIGN.md A9.
##
## HOW IT WORKS:
##   - It has hull and armour and no weapon and no shield: the inhibitor turret
##     next to it guards it. Pilots and minions can shoot it like a turret (a pilot
##     alone does 30% unless one of its team's minions is near, minions do 35%),
##     and nothing repairs it (Unit.heal refuses it).
##   - While it stands finished, its lane's free minion waves launch from it
##     (MinionDirector, PostSite.launch_point). When it is destroyed no new wave
##     comes from it; waves already out go on. The admiral may rebuild it once the
##     timer has run out (DefensePosts, AdmiralCommand.rebuild_post).
##   - A post made by a rebuild starts at 30% hull and grows to full over its build
##     time (PostData.POST "build"); it launches no wave until it is finished.
## Distances are in world units (1 world unit is about one pixel at normal zoom).
##
## WHO USES IT: DefensePosts makes it (World.defense_posts, through
## WorldSpawner); World calls sim_update() every tick; MinionDirector,
## PilotTargeting, the Admiral board, the HUD and the minimap read it; UnitVisual
## draws it.

## The record of the place this post stands at (its team, its lane and its state).
var site: PostSite = null
## The lane it launches ("top", "mid" or "bot").
var lane := "mid"
## Seconds of building left (0 = finished).
var build_left := 0.0
## Seconds the whole build takes (PostData.POST "build").
var build_total := 1.0


## Set the post up for the place `ps`. `instant` = finished at once with full
## hull (the six at the start of a match); otherwise it starts at 30% hull and
## builds up. WorldSpawner.spawn_post() calls it.
func setup(w: World, ps: PostSite, instant: bool) -> void:
	# Step 1: who and what we are.
	world = w
	site = ps
	team = ps.team
	lane = ps.lane
	kind = Unit.K_POST
	size_class = Rules.SIZE_STRUCTURE
	var d: Dictionary = PostData.POST
	radius = float(d["radius"])
	hull_max = float(d["hull"])
	hull_resist = float(d["resist"])
	vision_radius = float(d["vision"])
	display_name = "%s %s %s" % [Rules.TEAM_NAMES[team], MapLayout.LANES[lane]["label"].to_lower(), String(d["label"]).to_lower()]
	# Step 2: stand at the place, facing along the lane toward the enemy. The
	# collision layer is the "structures" layer (4) that pilot ships bump into; the
	# mask is 0: the post never checks for bumps itself.
	position = ps.pos
	rotation = ps.along.angle()
	collision_layer = 4
	collision_mask = 0
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
	# Step 3: start building (or be finished at once).
	build_total = float(d["build"])
	build_left = 0.0 if instant else build_total
	hull = hull_max if instant else hull_max * 0.3


## True once building is finished.
func is_built() -> bool:
	return build_left <= 0.0


## One tick of `dt` seconds: the hit flash, and, while building, the hull grows
## by 70% of its maximum spread over the build time (on top of the 30% it
## started with). World calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	if build_left > 0.0:
		build_left -= dt
		hull = minf(hull_max, hull + hull_max * 0.7 * dt / build_total)


## Combat.kill() calls this when we die: an explosion, and the place's rebuild
## timer starts (PostSite.note_destroyed).
func on_killed(_info: DamageInfo) -> void:
	world.effects.explosion(global_position, radius * 2.5, Palette.team(team))
	if site != null and site.post == self:
		site.note_destroyed(world, world.tick_count)
