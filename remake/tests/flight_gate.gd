extends Node
## WHAT THIS IS: the flight gate: pilot_audit plus what the flight work needs
## to compare two builds of the game in one all-AI match. pilot_audit counts
## stuck episodes, rock contact, deaths (who killed whom) and where the big
## ships fight during a siege; this adds the match length, the winner and how
## it ended, how low each mothership's hull got, and how many seconds big
## ships stood inside their main reach of an enemy mothership's hull, when each
## seat first reached its lane's Crossing, and how long each big ship took to
## reach its lane after it launched.
##
## HOW IT WORKS: setup() builds a pilot_audit as a child (it takes the same
## options, --secs and --late, and prints its own "AUDIT_JSON" line at the
## end) and listens for the end of the match. Every 0.5 game seconds it looks
## at each team's mothership (its lowest hull share so far) and at every big
## ship (a corvette or bigger) flying for a computer pilot: if the ship is
## within its main reach (PilotTargeting.main_reach) of the enemy mothership's
## hull, that half second is counted for its team and hull, and the first such
## time is kept. The same look notes, per seat, when the seat's pilot first
## launched and first came within NEAR_R of the Crossing of its lane (as
## opening_probe does), and, for every big ship, how many seconds after its
## launch it first stood within LANE_R of its lane goal while flying in the lane
## state. When the match ends, or at --secs, it prints one
## "FLIGHT_GATE_JSON {...}" line just before pilot_audit prints its own, and
## pilot_audit then quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --test=flight_gate --secs=1800
##
## WHO USES IT: main.gd loads it for --test=flight_gate. It only reads the
## game; it changes nothing in the match.

## A seat counts as at its Crossing within this many world units of the node
## (the number opening_probe uses).
const NEAR_R := 1500.0
## A big ship counts as at its lane when it flies in the lane state within this
## many world units of its goal.
const LANE_R := 800.0
## pilot_audit, which this test runs inside the same match.
const PilotAuditScript := preload("res://tests/pilot_audit.gd")

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1500.0
## Seconds until the next 0.5 s look.
var _look_t := 0.0
## The pilot_audit node running beside us.
var _audit: Node
## How the match ended: the reason text of Events.match_over, or "".
var _reason := ""
## The lowest hull share (0..1) each team's mothership has had so far.
var _ms_low := [1.0, 1.0]
## Seconds the big ships of team 0 and team 1 stood inside their main reach of
## the enemy mothership's hull, by hull id: [{hull id: seconds}, {...}].
var _reach_s := [{}, {}]
## The game time of the first such moment for each team, or -1.
var _reach_first := [-1.0, -1.0]
## Per seat, key "team:slot": role, lane, t_launch (first time in space) and
## t_near (first time within NEAR_R of its lane's Crossing), -1 = not yet.
var _seats := {}
## Per big ship, key = its instance id: hull id, team, t_launch (when it was
## first seen) and t_lane (seconds after that until it first stood at its lane,
## -1 = not yet).
var _bigs := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1500.0))
	if Game.opt("late", false):
		secs += LateGame.START
	Events.match_over.connect(_on_match_over)
	_audit = PilotAuditScript.new()
	# pilot_audit runs after us in every tick, so our line comes first.
	_audit.process_priority = 1
	add_child(_audit)
	_audit.call("setup", w)


## Remember how the match ended.
func _on_match_over(_winner: int, reason: String) -> void:
	_reason = reason


## Every 0.5 s look at the motherships and the big ships; at the end print our
## line (pilot_audit prints its own right after).
func _physics_process(dt: float) -> void:
	if world == null:
		return
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = 0.5
		_look()
	if world.time >= secs or world.phase != "play":
		print("FLIGHT_GATE_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "phase": world.phase, "winner": world.winner,
			"reason": _reason, "ms_low": [snappedf(_ms_low[0], 0.001), snappedf(_ms_low[1], 0.001)],
			"reach_s": _reach_s, "reach_first": _reach_first, "seats": _seats.values(), "bigs": _bigs.values()}))
		set_physics_process(false)


## One look: each mothership's hull share, and every big ship's distance to
## the enemy mothership's hull.
func _look() -> void:
	for t in 2:
		var ms := world.mothership(t)
		if ms != null and ms.alive:
			_ms_low[t] = minf(_ms_low[t], ms.hull / maxf(ms.hull_max, 1.0))
		elif ms != null:
			_ms_low[t] = 0.0
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI) or s.size_class < Rules.SIZE_MEDIUM:
			continue
		var ems := world.mothership(1 - s.team)
		if ems == null or not ems.alive:
			continue
		if ems.hull_dist(s.global_position) <= PilotTargeting.main_reach(s):
			var by_hull: Dictionary = _reach_s[s.team]
			by_hull[s.hull_id] = float(by_hull.get(s.hull_id, 0.0)) + 0.5
			if _reach_first[s.team] < 0.0:
				_reach_first[s.team] = snappedf(world.time, 0.1)
	_look_seats()
	_look_bigs()


## The seats: note when each AI seat's pilot first launched and first came
## within NEAR_R of the Crossing of its lane.
func _look_seats() -> void:
	for p: PilotProfile in world.profiles:
		var brain: PilotAI = world.pilot_ai.get(p)
		if p.is_human or brain == null:
			continue
		var key := "%d:%d" % [p.team, p.slot]
		if not _seats.has(key):
			_seats[key] = {"team": p.team, "slot": p.slot, "role": p.role, "lane": _lane_of(brain), "t_launch": -1.0, "t_near": -1.0}
		var r: Dictionary = _seats[key]
		var ship := p.ship
		if ship == null or not is_instance_valid(ship) or not ship.alive:
			continue
		if float(r["t_launch"]) < 0.0:
			r["t_launch"] = snappedf(world.time, 0.1)
		if float(r["t_near"]) < 0.0:
			var node := _crossing(str(r["lane"]))
			if node != null and ship.global_position.distance_to(node.global_position) <= NEAR_R:
				r["t_near"] = snappedf(world.time, 0.1)


## The big ships: note when each was first seen flying and how many seconds
## later it first stood at its lane (in the lane state, within LANE_R of its
## goal).
func _look_bigs() -> void:
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI) or s.size_class < Rules.SIZE_MEDIUM:
			continue
		var key := str(s.get_instance_id())
		if not _bigs.has(key):
			_bigs[key] = {"hull": s.hull_id, "team": s.team, "t_launch": snappedf(world.time, 0.1), "t_lane": -1.0}
		var r: Dictionary = _bigs[key]
		if float(r["t_lane"]) >= 0.0:
			continue
		var brain := s.controller as PilotAI
		if brain.state == "lane" and s.global_position.distance_to(brain.goal) <= LANE_R:
			r["t_lane"] = snappedf(world.time - float(r["t_launch"]), 0.1)


## The Crossing node on `lane` (the middle node of that lane), or null.
func _crossing(lane: String) -> ResourceNode:
	for n in world.nodes:
		if n.node_kind == "middle" and n.lane == lane:
			return n
	return null


## The lane whose Crossing the pilot of `brain` is sent to: its opening lane
## when this build has one (the flex pilot has its own lane), else its lane.
func _lane_of(brain: PilotAI) -> String:
	if brain.goals.has_method("opening_lane"):
		return brain.goals.call("opening_lane")
	return brain.goals.lane_id()