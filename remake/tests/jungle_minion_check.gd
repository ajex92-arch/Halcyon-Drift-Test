extends Node
## WHAT THIS IS: the jungle-minion check (a player's F9 note: "a minion shouldnt be in the jungle like this"). It
## asks one question: a lane minion that has strayed out of its lane's corridor with nobody to fight, how long does it
## take to fly back inside? Before the fix a minion flew straight at the lane's far corner, so one that had chased
## a target 1,600 units out of a top or bottom lane stayed outside the corridor for about 16 seconds, walking along
## the jungle's edge; one pinned by a pocket of rocks stayed for the rest of the match. The check fails any case that
## takes longer than LIMIT_S seconds.
##
## HOW IT WORKS: it freezes the match, and for each team, each of the three lane ids and each of the three minion types it
## makes a minion on the lane (40 percent of the way along), moves it OUT_BEYOND world units outside the corridor's
## edge towards the map's middle, sets its path to the lane's far corner as it is after a chase, and with no rocks
## (or, in the "pinned" cases, a pocket of rocks round its start that holds it still) flies it by calling the real MinionFlight.lane_move step after step (the step length a minion really steers with,
## two ticks) until it is back inside the corridor or MAX_S seconds have passed. The seconds taken (and where it
## came back in) are printed per case; a case over LIMIT_S is a failure. At the end it prints
## "jungle_minion_check: N failures" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=7 --test=jungle_minion_check
##
## WHO USES IT: main.gd loads it for --test=jungle_minion_check (it calls setup()); run_checks runs it as a check. It
## draws no random numbers beyond the ones minion setup draws, and the match it runs in is frozen and thrown away.

## The seconds a strayed minion may take to be back inside its corridor.
const LIMIT_S := 8.0
## The seconds a minion pinned in a pocket of rocks may take to be back inside its corridor (2 s pinned, then free).
const LIMIT_PINNED_S := 12.0
## The radius (world units) of the pocket of rocks that holds a pinned minion: inside it a rock pushes, outside it nothing does.
const POCKET := 400.0
## The most seconds a case is flown before it counts as never coming back.
const MAX_S := 60.0
## How far (world units) outside the corridor's edge the minion is put.
const OUT_BEYOND := 700.0
## The length (seconds) of one steering step: a minion steers on every second tick of 1/60 s.
const DT := 2.0 / 60.0
## How far along the lane (as a fraction of its length) the minion is put.
const ALONG := 0.4
## The three minion types.
const TYPES := ["fighter", "bomber", "corvette"]

## The running match (set by setup()).
var world: World
## How many cases failed.
var _fails := 0


## main.gd calls this once, right after the World is built. Freeze the match and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Fly every case, print the verdicts and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var cases := 0
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			for type_id: String in TYPES:
				for pinned in [false, true]:
					cases += 1
					_case(team, lane, type_id, pinned)
	print("jungle_minion_check: %d cases" % cases)
	print("jungle_minion_check: %d failures" % _fails)
	get_tree().quit()


## One case: team `team`'s minion `type_id` on lane `lane`, put out of the corridor and flown back. With `pinned`, it sits in a
## pocket of rocks round its start (as in the probe's matches, where a minion stood still for 9 minutes): while it is
## inside POCKET of its start, the rocks push it with exactly the push that undoes what its steering would do.
func _case(team: int, lane: String, type_id: String, pinned: bool) -> void:
	var pts := MapLayout.lane_points(lane, team)
	var half := float(MapLayout.LANES[lane]["half"])
	var at := Util.polyline_at(pts, Util.polyline_length(pts) * ALONG)
	var towards := -1.0 if lane == "mid" else signf(MapLayout.CY - at.y)
	var start := at + Vector2(0.0, towards * (half + OUT_BEYOND))
	var m := world.spawn_minion(team, type_id, lane, at)
	m.position = start
	m.velocity = Vector2.ZERO
	# After a chase the minion's path has moved on to the lane's far corner (path[0] is the point where it joined).
	m.path_i = mini(1, m.path.size() - 1)
	m._rock_push = Vector2.ZERO
	var t := 0.0
	var back := false
	while t < MAX_S:
		if pinned:
			m._rock_push = _pocket_push(m, start)
		MinionFlight.lane_move(m, DT)
		m.position += m.velocity * DT
		t += DT
		if Util.dist_to_polyline(m.position, pts) <= half:
			back = true
			break
	var ok := back and t <= (LIMIT_PINNED_S if pinned else LIMIT_S)
	if not ok:
		_fails += 1
	print("%s team=%d lane=%s %s%s start=(%.0f,%.0f) back=%s after %.1f s at (%.0f,%.0f)" % ["ok  " if ok else "FAIL", team, lane, type_id, " pinned" if pinned else "", start.x, start.y, str(back), t, m.position.x, m.position.y])
	m.alive = false

## The rock push of a pocket of rocks round `start` on minion `m` now: zero outside POCKET of `start`; inside it the push that
## cancels one step of the minion's own steering, found by flying one step with no push and putting everything back.
func _pocket_push(m: Minion, start: Vector2) -> Vector2:
	if m.position.distance_to(start) >= POCKET:
		return Vector2.ZERO
	var v0 := m.velocity
	var r0 := m.rotation
	var i0 := m.path_i
	var pin0: Variant = m.get("_pin_t")
	var unpin0: Variant = m.get("_unpin_t")
	m._rock_push = Vector2.ZERO
	MinionFlight.lane_move(m, DT)
	var dv := m.velocity - v0
	m.velocity = v0
	m.rotation = r0
	m.path_i = i0
	if pin0 != null:
		m.set("_pin_t", pin0)
	if unpin0 != null:
		m.set("_unpin_t", unpin0)
	return -dv / DT
