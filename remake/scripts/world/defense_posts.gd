class_name DefensePosts
extends RefCounted
## WHAT THIS IS: the keeper of the six lane defense posts (one per team and
## lane). It makes them at the start, moves their records on every tick (the
## rebuild timers), rebuilds one when the admiral orders it, and tells the news
## feed when a post is ready to be rebuilt or is back.
##
## HOW IT WORKS: sites holds six PostSite records, team 0's top, mid and bottom
## lane first. make_all() puts a finished post on each (the start of a match).
## tick() lets every record notice a change of state (a rebuilt post that is
## finished, a timer that ran out). rebuild() makes a new post on a record whose
## post fell and whose timer ran out (AdmiralCommand has checked the rules and
## taken the price). A lane's waves launch only from a standing post:
## MinionDirector asks standing().
##
## WHO USES IT: World makes one (World.defense_posts, in WorldSetup) and calls
## tick(); MinionDirector, AdmiralCommand, AdmiralBuilder, PilotTargeting, the
## admiral board, the HUD and the minimap read the records; PostSite calls
## announce().

## The six records: index = team x 3 + the lane's place in MapLayout.LANE_ORDER.
var sites: Array[PostSite] = []
## The match we keep posts for.
var world: World


## Make the six records (no posts yet: make_all() does that).
func _init(w: World) -> void:
	world = w
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			sites.append(PostSite.new(team, lane))


## The record of team `team`'s post on lane `lane`.
func site_of(team: int, lane: String) -> PostSite:
	return sites[team * 3 + MapLayout.LANE_ORDER.find(lane)]


## True while team `team`'s post on lane `lane` stands finished (its lane's
## waves may launch).
func standing(team: int, lane: String) -> bool:
	return site_of(team, lane).is_standing()


## How many of team `team`'s three posts stand finished.
func standing_count(team: int) -> int:
	var n := 0
	for lane: String in MapLayout.LANE_ORDER:
		if standing(team, lane):
			n += 1
	return n


## Put a finished post on every record: the start of a match.
func make_all() -> void:
	for ps in sites:
		ps.post = world.spawn_post(ps, true)


## Every tick: let each record notice a change of state.
func tick() -> void:
	for ps in sites:
		ps.update(world, world.tick_count)


## Rebuild team `team`'s post on lane `lane`: a new post that is built from 30%
## hull over PostData.POST "build" seconds. The caller has checked that the record
## is "ready" and has taken the price. Returns the new post.
func rebuild(team: int, lane: String) -> DefensePost:
	var ps := site_of(team, lane)
	ps.post = world.spawn_post(ps, false)
	ps.update(world, world.tick_count)
	return ps.post


## A post changed state: say so in the news feed. A post that fell is told by the
## kill line (HudFeed); here: ready to rebuild (the owner's team only) and a
## rebuilt post that is finished (everyone).
static func announce(w: World, ps: PostSite) -> void:
	var lane_name := str(MapLayout.LANES[ps.lane]["label"]).to_lower()
	if ps.state == PostSite.READY:
		Events.feed.emit("The %s %s defense post can be rebuilt." % [Rules.TEAM_NAMES[ps.team], lane_name], "team", ps.team)
	elif ps.state == PostSite.STANDING and ps.destroyed_tick >= 0 and w.tick_count > 1:
		Events.feed.emit("The %s %s defense post is back." % [Rules.TEAM_NAMES[ps.team], lane_name], "info", -1)
