extends Node
## WHAT THIS IS: the check of the lane defense posts (DefensePost, PostSite,
## DefensePosts): six stand from the start beside their lane's inhibitor turret,
## a lane's wave launches from its post, a destroyed post stops that lane's new
## waves, only the admiral rebuilds it and only after 18,000 ticks, and the
## rebuild costs a PD turret's price and builds over a PD turret's time.
##
## HOW IT WORKS: setup() checks the six posts and their numbers. Then a
## scenario runs by the match clock: every wave minion that launches before 40 s
## must appear at its lane's post (check 2); at 50 s Aurelian's top post is
## destroyed (the record must say "destroyed" with a timer of 18,000 ticks, the
## minions already out must go on, and no wave may launch on that lane for
## Aurelian at 80 s while Vhorr's and Aurelian's other lanes still do); the
## admiral's rebuild order is refused before the timer; at the tick the timer
## runs out the record says "ready" (an enemy minion standing near the post
## still blocks the order); the rebuild is then ordered (450 credits paid, the
## post starts at 30% hull, is finished after 25 s) and the next wave launches
## from it again. Every state message must carry the tick number of its moment.
## It prints one line per failed check, one line with the numbers and
## "post_check: N failures" (0 = all good).
##
## With the option --ai-rebuild the computer admiral is left on (run without
## --no-admiral-ai) and the test does not order the rebuild itself: the record must
## say "building" within 20 s of the timer running out (the computer admiral's rule,
## AdmiralBuilder.rebuild_posts), unless its team cannot pay.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=post_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --ai-rebuild --test=post_check
##
## WHO USES IT: main.gd loads it for --test=post_check. It destroys and rebuilds
## one post of its own; it changes nothing else.

## The match time (seconds) at which the scenario destroys Aurelian's top post.
const T_KILL := 50.0
## The match time (seconds) at which the second wave has launched (the first
## leaves at 45 s, the next 35 s after it, 80 s).
const T_SECOND_WAVE := 82.0
## The match time (seconds) after which the wave following the rebuild has
## launched: the timer ends at 350 s, the build at 375 s, and the waves leave
## every 35 s from 45 s (395 s is the first one after the build).
const T_AFTER_REBUILD := 397.0
## The match time (seconds) at which the scenario gives up.
const T_GIVE_UP := 420.0

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Where the scenario is: 0 = waiting to destroy the post, 1 = waiting for the
## second wave, 2 = waiting for the timer, 3 = ordering the rebuild, 4 = waiting
## for the build, 5 = waiting for the wave after the rebuild, 6 = done.
var step := 0
## The post record the scenario uses (Aurelian's top lane).
var site: PostSite = null
## The tick at which the scenario destroyed the post.
var killed_tick := -1
## The state messages about that post: [state, tick, the World's tick number].
var got: Array = []
## Launches of free-wave minions seen so far: [team, lane, position, match time].
var launches: Array = []
## Aurelian's top lane minions alive just after the kill.
var out_at_kill := 0
## The treasury just before the rebuild order.
var treasury_before := 0.0
## The enemy minion used to test the build circle.
var blocker: Minion = null
## The tick at which the rebuild was ordered.
var ordered_tick := -1
## True with --ai-rebuild: the computer admiral does the rebuilding.
var ai_mode := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	ai_mode = bool(Game.opt("ai-rebuild", false))
	_check_start()
	site = world.defense_posts.site_of(Rules.HALCYON, "top")
	Events.minion_launched.connect(_on_launch)
	Events.post_state_changed.connect(_on_state)


## Count a failed check and print it.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
		print("post_check: FAIL %s %s" % [what, detail])


## The six posts at the start, and their numbers.
func _check_start() -> void:
	_check("six defense posts stand", world.posts.size() == 6, "(%d)" % world.posts.size())
	_check("the post list holds 6 records", world.defense_posts.sites.size() == 6)
	var d: Dictionary = PostData.POST
	_check("a rebuild costs a PD turret's price", float(d["cost"]) == float(TurretData.TURRETS["pd"]["cost"]))
	_check("a rebuild takes a PD turret's build time", float(d["build"]) == float(TurretData.TURRETS["pd"]["build"]))
	_check("the rebuild timer is 18,000 ticks (5 minutes)", PostData.REBUILD_TICKS == 18000 and PostData.REBUILD_TICKS == 300 * TurretSite.TICKS_PER_SECOND)
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			var ps := world.defense_posts.site_of(team, lane)
			_check("team %d, %s: the post stands finished" % [team, lane], ps.is_standing() and ps.state == PostSite.STANDING)
			var p := ps.post
			if p == null:
				continue
			_check("team %d, %s: the post is a defense post of the right team and lane" % [team, lane], p.kind == Unit.K_POST and p.team == team and p.lane == lane and Unit.KIND_NAMES[p.kind] == "defense post")
			_check("team %d, %s: the post has hull and no weapon or shield" % [team, lane], p.hull == float(d["hull"]) and p.hull_max == float(d["hull"]) and p.shields == null)
			var turret_here: ResourceNode = null
			for n: ResourceNode in world.nodes:
				if n.node_kind == "inhibitor" and n.side == team and n.lane == lane:
					turret_here = n
			var gap := p.global_position.distance_to(turret_here.slot_pos[0]) if turret_here != null else -1.0
			_check("team %d, %s: the post stands beside the inhibitor turret (100 to 600 away)" % [team, lane], gap > 100.0 and gap < 600.0, "(%d)" % int(gap))
			_check("team %d, %s: the post is not on the lane line" % [team, lane], float(Util.project_on_polyline(p.global_position, MapLayout.lane_points(lane, team))["dist"]) > 300.0)
			_check("team %d, %s: heal() does nothing for a post" % [team, lane], p.heal(100.0) == 0.0)
			for c: Dictionary in world.map.camps:
				_check("team %d, %s: the post is more than 700 from camp %s" % [team, lane, c["id"]], p.global_position.distance_to(c["pos"]) > 700.0)


## A free-wave minion launched: note where and when.
func _on_launch(m: Node, _wave_id: float) -> void:
	var mm := m as Minion
	launches.append([mm.team, mm.lane, mm.global_position, world.time])


## A post changed state: keep the messages about the scenario's post.
func _on_state(team: int, lane: String, state: String, tick: int) -> void:
	if team == Rules.HALCYON and lane == "top":
		got.append([state, tick, world.tick_count])


## How many launches of `team` on `lane` happened since match time `since`.
func _launched(team: int, lane: String, since: float) -> int:
	var n := 0
	for l: Array in launches:
		if int(l[0]) == team and str(l[1]) == lane and float(l[3]) >= since:
			n += 1
	return n


## Every tick: move the scenario on.
func _physics_process(_dt: float) -> void:
	if world == null or step >= 6:
		return
	match step:
		0:
			if world.time >= T_KILL:
				# The first wave must have launched from the posts.
				for l: Array in launches:
					var ps := world.defense_posts.site_of(int(l[0]), str(l[1]))
					_check("a wave minion launched at its lane's post (team %d, %s)" % [int(l[0]), str(l[1])], (l[2] as Vector2).distance_to(ps.launch) < 250.0, "(%d from the launch centre)" % int((l[2] as Vector2).distance_to(ps.launch)))
				_check("the first wave launched on every lane for both teams", launches.size() == 42, "(%d minions)" % launches.size())
				var out := 0
				for m: Minion in world.minions:
					if m.team == Rules.HALCYON and m.lane == "top" and m.alive:
						out += 1
				out_at_kill = out
				var info := DamageInfo.new()
				info.source_team = Rules.CINDER
				killed_tick = world.tick_count
				world.combat.kill(site.post, info)
				_check("the record says destroyed", site.state == PostSite.DESTROYED)
				_check("the timer is exactly 18,000 ticks", site.ready_tick - killed_tick == 18000 and site.ticks_left(killed_tick) == 18000, "(ready %d, destroyed %d)" % [site.ready_tick, killed_tick])
				var refusal := world.command.rebuild_post(Rules.HALCYON, "top")
				_check("a rebuild before the timer is refused, with the time left", refusal.begins_with("The post was destroyed: rebuild in 5:00"), "('%s')" % refusal)
				step = 1
		1:
			if world.time >= T_KILL + 5.0 and out_at_kill > 0:
				var still := 0
				for m: Minion in world.minions:
					if m.team == Rules.HALCYON and m.lane == "top" and m.alive:
						still += 1
				_check("the wave that was already out goes on", still > 0, "(%d out at the kill, %d five seconds later)" % [out_at_kill, still])
				out_at_kill = -1
			if world.time >= T_SECOND_WAVE:
				_check("no new wave on Aurelian's top lane", _launched(Rules.HALCYON, "top", T_KILL) == 0, "(%d launched)" % _launched(Rules.HALCYON, "top", T_KILL))
				_check("Aurelian's other lanes launch as usual", _launched(Rules.HALCYON, "mid", T_KILL) > 0 and _launched(Rules.HALCYON, "bot", T_KILL) > 0)
				_check("Vhorr's top lane launches as usual", _launched(Rules.CINDER, "top", T_KILL) > 0)
				step = 2
		2:
			if site.state == PostSite.DESTROYED and world.tick_count >= site.ready_tick - 1:
				# A tick before the timer runs out: still refused.
				_check("a rebuild one tick before the timer is refused", world.command.rebuild_post(Rules.HALCYON, "top") != "")
			if site.state == PostSite.READY:
				_check("the record says ready at the tick the timer ran out", int(got[got.size() - 1][1]) == killed_tick + 18000, "(messages %s)" % str(got))
				# An enemy minion near the spot blocks the order, away from it the order goes through.
				if not ai_mode:
					blocker = world.spawn_minion(Rules.CINDER, "fighter", "top", site.pos + Vector2(600.0, 0.0))
				step = 3
		3:
			if ai_mode:
				# The computer admiral does it: building within 20 s of the timer.
				if site.state == PostSite.BUILDING:
					ordered_tick = site.state_tick
					_check("the computer admiral rebuilt the post within 20 s of the timer", site.state_tick - site.ready_tick <= 1200, "(%d ticks after)" % (site.state_tick - site.ready_tick))
					step = 4
				elif world.tick_count > site.ready_tick + 1200:
					_check("the computer admiral rebuilt the post within 20 s of the timer", false, "(state %s, treasury %d)" % [site.state, int(world.teams[Rules.HALCYON].treasury)])
					step = 6
					_finish()
			elif blocker != null:
				var refusal := world.command.post_blocker(Rules.HALCYON, "top")
				_check("an enemy minion near the post blocks the rebuild", refusal == "Enemy ships are too close", "('%s')" % refusal)
				world.combat.kill_silently(blocker)
				blocker = null
			else:
				treasury_before = world.teams[Rules.HALCYON].treasury
				var r := world.command.rebuild_post(Rules.HALCYON, "top")
				ordered_tick = world.tick_count
				_check("the rebuild order is accepted after the timer", r == "", "('%s')" % r)
				_check("the rebuild costs 450 credits", is_equal_approx(treasury_before - world.teams[Rules.HALCYON].treasury, 450.0))
				_check("the record says building", site.state == PostSite.BUILDING and site.post != null)
				_check("the new post starts at 30% hull", site.post != null and is_equal_approx(site.post.hull / site.post.hull_max, 0.3))
				step = 4
		4:
			if site.state == PostSite.STANDING:
				var took := float(world.tick_count - ordered_tick) / 60.0
				_check("the rebuild took 25 seconds", absf(took - 25.0) < 0.2, "(%.2f s)" % took)
				_check("the rebuilt post is at full hull", site.post != null and is_equal_approx(site.post.hull, site.post.hull_max))
				# The wave that left while the post was being rebuilt skipped the lane.
				_check("a post that is being rebuilt launches no wave", _launched(Rules.HALCYON, "top", T_KILL) == 0, "(%d launched)" % _launched(Rules.HALCYON, "top", T_KILL))
				step = 5
		5:
			# The next free wave after the rebuild (every 35 s from 45 s) leaves from the post again.
			if world.time >= T_AFTER_REBUILD and _launched(Rules.HALCYON, "top", T_KILL) >= 5:
				var from_post := true
				for l: Array in launches:
					if int(l[0]) == Rules.HALCYON and str(l[1]) == "top" and float(l[3]) >= T_KILL:
						from_post = from_post and (l[2] as Vector2).distance_to(site.launch) < 250.0
				_check("the next wave after the rebuild launches from the post", from_post and _launched(Rules.HALCYON, "top", T_KILL) == 5, "(%d launched)" % _launched(Rules.HALCYON, "top", T_KILL))
				step = 6
				_finish()
			elif world.time > T_GIVE_UP:
				_check("a wave launched on the top lane after the rebuild", false)
				step = 6
				_finish()


## Check the messages, print the numbers and quit.
func _finish() -> void:
	var states: Array = []
	for g: Array in got:
		states.append(str(g[0]))
	_check("the state messages are destroyed, ready, building, standing (one each)", states == ["destroyed", "ready", "building", "standing"], "(got %s)" % str(states))
	for g: Array in got:
		_check("a message carries the tick the World had when it was sent", int(g[1]) == int(g[2]), "(%d vs %d)" % [g[1], g[2]])
	print("post_check: %d posts, launches %d, scenario %s" % [world.posts.size(), launches.size(), str(got)])
	print("post_check: %d failures" % fails)
	get_tree().quit()
