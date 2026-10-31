extends Node
## WHAT THIS IS: the check of the turret site records (TurretSite): every
## node of the map has one with the right id, name, kind, build circle and clear
## window, and the state messages (Events.site_state_changed) come once per
## change with the right team and the World's tick number.
##
## HOW IT WORKS: setup() looks at every node's record. Then the scenario runs
## on one team's own jungle node, which has no turret at the start: the first
## admiral order builds a PD turret (the record must say "building", then
## "held" once it is finished), the test destroys it (the record must say
## "locked", then "open" when the rebuild lock ends). Every message must carry
## the tick number the World had when it was sent, the numbers must grow, and no
## message may repeat the state before it. The 18 lane turret sites are checked
## too: where they lie, and that a finished PD turret stands on each from the
## start. It prints one line per failed check, one line with the numbers, and
## "site_check: N failures" (0 = all good).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=site_check
##
## WHO USES IT: main.gd loads it for --test=site_check. It builds and destroys one
## turret of its own; it changes nothing else.

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## The node the scenario uses (a jungle node of Aurelian's).
var node: ResourceNode = null
## The messages about that node so far: [state, team, tick, the World's tick
## number when it arrived].
var got: Array = []
## Where the scenario is: 0 = nothing ordered yet, 1 = waiting for the turret
## to be finished, 2 = waiting for the rebuild lock to end, 3 = done; -2 and -1
## are the two build circle tests that come first (an enemy minion far outside
## the circle, then one inside it).
var step := -2
## The enemy minion the circle test uses.
var minion: Minion = null
## The turret the scenario built.
var turret: Turret = null
## The match time (seconds) when the turret was destroyed.
var killed_at := 0.0
## All the messages of the whole match (any node), counted.
var all_messages := 0
## True once the lane turret sites were checked (on the third tick).
var lane_checked := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	_check_records()
	for n: ResourceNode in world.nodes:
		if n.node_kind == "jungle_team" and n.side == Rules.HALCYON:
			node = n
			break
	_check("a jungle node of Aurelian's exists for the scenario", node != null)
	if node == null:
		_finish()
		return
	Events.site_state_changed.connect(_on_message)


## Print a PASS-free line for a failed check, and count it.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
		print("site_check: FAIL %s %s" % [what, detail])


## Every node has a record that agrees with the node.
func _check_records() -> void:
	for n: ResourceNode in world.nodes:
		var s := n.site
		_check("node %s has a site record" % n.node_id, s != null)
		if s == null:
			continue
		_check("%s: the record's id is the node's id" % n.node_id, s.site_id == n.node_id)
		_check("%s: the record's name is the node's name" % n.node_id, s.display_name == n.node_name)
		_check("%s: the record's kind is the node's kind" % n.node_id, s.kind == n.node_kind)
		var jungle: bool = n.node_kind in ["jungle_team", "jungle_shared"]
		var want_r := 900.0 if jungle else 1500.0
		_check("%s: the build circle is %d" % [n.node_id, int(want_r)], s.build_radius == want_r, "(is %s)" % s.build_radius)
		var want := TurretSite.JUNGLE_WINDOW_TICKS if jungle else TurretSite.LANE_WINDOW_TICKS
		_check("%s: the clear window is %d ticks" % [n.node_id, want], s.window_ticks == want, "(is %d)" % s.window_ticks)
		_check("%s: a clear window is a whole number of ticks" % n.node_id, s.window_ticks % 1 == 0 and s.window_ticks > 0)


## The 18 lane turret sites (T-51): a team has one of each kind on each lane, the
## turret stands off the lane line and clear of every camp, the kinds come in
## order from the lane's middle to the team's mothership, and (checked from the
## third tick on, `after_start`) a finished PD turret stands on every one.
func _check_lane_sites(after_start: bool) -> void:
	var count := 0
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			var pts := MapLayout.lane_points(lane, team)
			var along := {}
			for n: ResourceNode in world.nodes:
				if n.side != team or n.lane != lane or not MapLayout.is_lane_site_kind(n.node_kind):
					continue
				count += 1
				along[n.node_kind] = float(Util.project_on_polyline(n.slot_pos[0], pts)["s"])
				var off := float(Util.project_on_polyline(n.slot_pos[0], pts)["dist"])
				_check("%s: the turret stands off the lane line (300 to 600)" % n.node_id, off > 300.0 and off < 600.0, "(%d)" % int(off))
				_check("%s: one turret slot" % n.node_id, n.slot_pos.size() == 1)
				for c: Dictionary in world.map.camps:
					_check("%s: the turret is more than 700 from camp %s" % [n.node_id, c["id"]], n.slot_pos[0].distance_to(c["pos"]) > 700.0)
				if after_start:
					var t := n.slots[0] as Turret
					_check("%s: a finished PD turret of team %d stands there from the start" % [n.node_id, team], t != null and is_instance_valid(t) and t.alive and t.is_built() and t.ttype == "pd" and t.team == team)
					_check("%s: the site is held by its team" % n.node_id, n.site.state == TurretSite.HELD and n.site.state_team == team)
			_check("team %d, %s lane: an outer, an inner and an inhibitor site" % [team, lane], along.size() == 3)
			if along.size() == 3:
				_check("team %d, %s lane: from the team's mothership the order is inhibitor, inner, outer" % [team, lane], float(along["inhibitor"]) < float(along["inner"]) and float(along["inner"]) < float(along["outer"]))
	_check("18 lane turret sites in all", count == 18, "(%d)" % count)


## A site changed state: keep the message if it is about the scenario's node.
func _on_message(site_id: String, state: String, team: int, tick: int) -> void:
	all_messages += 1
	if node != null and site_id == node.node_id:
		got.append([state, team, tick, world.tick_count])


## Every tick: move the scenario on.
func _physics_process(_dt: float) -> void:
	if world == null or node == null or step >= 3:
		return
	if not lane_checked and world.tick_count >= 3:
		lane_checked = true
		_check_lane_sites(true)
	if step < 0:
		# The build circle: a minion of the enemy 1,200 away is outside a jungle
		# node's circle (900), one 600 away is inside it.
		if minion == null:
			var gap := 1200.0 if step == -2 else 600.0
			minion = world.spawn_minion(Rules.CINDER, "fighter", node.lane, node.global_position + Vector2(gap, 0.0))
		else:
			var blocked := node.build_blocker(Rules.HALCYON, "pd") != ""
			_check("an enemy minion %s the circle %s the build" % ["outside" if step == -2 else "inside", "does not block" if step == -2 else "blocks"], blocked == (step == -1), "(blocker: %s)" % node.build_blocker(Rules.HALCYON, "pd"))
			world.combat.kill_silently(minion)
			minion = null
			step += 1
		return
	if step == 0:
		var r := world.command.build_turret(Rules.HALCYON, node.node_id, "pd")
		_check("the order to build at the scenario node is accepted", r == "", "(%s)" % r)
		turret = node.slots[0] as Turret
		step = 1
	elif step == 1:
		if turret != null and turret.alive and turret.is_built():
			var info := DamageInfo.new()
			info.source_team = Rules.CINDER
			world.combat.kill(turret, info)
			killed_at = world.time
			step = 2
		elif world.time > 120.0:
			_check("the turret was finished in time", false)
			_finish()
	elif step == 2:
		if world.time >= node.rebuild_lock_until + 0.5:
			step = 3
			_finish()
		elif world.time > 400.0:
			_check("the rebuild lock ended in time", false)
			_finish()


## Check the messages, print the numbers and quit.
func _finish() -> void:
	step = 3
	var states: Array = []
	for g: Array in got:
		states.append("%s/%d" % [g[0], g[1]])
	var want := ["building/0", "held/0", "locked/-1", "open/-1"]
	_check("the messages about the scenario node are building, held, locked, open (one each)", states == want, "(got %s)" % str(states))
	var last_tick := -1
	for g: Array in got:
		_check("a message carries the tick the World had when it was sent", int(g[2]) == int(g[3]), "(%d vs %d)" % [g[2], g[3]])
		_check("the tick numbers grow", int(g[2]) > last_tick)
		last_tick = int(g[2])
	if node != null:
		_check("the record's state ends as open", node.site.state == TurretSite.OPEN)
	print("site_check: %d nodes, %d messages in all, scenario %s" % [world.nodes.size(), all_messages, str(got)])
	print("site_check: %d failures" % fails)
	get_tree().quit()
