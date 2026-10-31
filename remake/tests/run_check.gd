extends Node
## WHAT THIS IS: the check for the Bomber's torpedo run and its rear gun. It
## flies single Bombers by hand in a frozen match and checks the rules one by
## one, so a change that breaks one is caught in seconds.
##
## HOW IT WORKS: the match is frozen and the check steps one Bomber (and the
## rounds in flight) itself, one tick (1/60 s) at a time, pressing and
## releasing its fire button. It checks:
##   hold      the bar is full after 90 ticks of the hold and no torpedo has
##             left; the torpedoes wait while the button stays down; letting go
##             with the bar full launches three on that tick, one in each lane,
##             pays the energy and starts a 60-tick reload;
##   lock      while a run is on the ship does not turn, ignores sideways
##             thrust and loses its sideways drift, and W still works; the lock
##             holds on the tick the torpedoes leave, so they go along the
##             heading; after that the ship turns again;
##   cancel    letting go before the bar is full launches nothing and costs no
##             waiting; the cancel input ends a run in the hold and in the wait
##             for the release, free, and unlocks the heading at once; touching
##             a rock does the same; the next run needs a fresh press;
##   window    a hold that reaches 180 ticks launches by itself and then needs
##             a fresh press;
##   reload    no hold starts in the 60 ticks after a launch, a press during
##             the reload is ignored until the button is let go, and one starts
##             on the 60th tick; no hold starts below 15 energy, and a run the
##             battery cannot pay at the launch fires nothing;
##   fan       the half-angle is 18 degrees at 0 points, 14.25 at 90, 10.5 at
##             180, 6.75 at 270 and 3 at 360; the three lanes leave at those
##             angles from muzzles 12 units apart at one speed, and a real
##             launch matches; the score gains 2 a tick of steady flight, loses
##             6 a tick of turn or strafe input, stalls while boosting and
##             stays between 0 and 360;
##   arming    a torpedo that touches a ship inside 200 units of flight does
##             nothing (a dud) and one that touches it later hurts it;
##   tech      Steady Sights makes the gain 3 a tick, Armoured Torpedoes gives
##             each torpedo 30 hit points, and the Focus shot's bonus applies
##             to all three torpedoes of the next run and then is used up;
##   pierce    a hit with a pierce of 1 leaves the shields and their refill
##             wait alone and hurts the hull in full; a pierce of 0.5 splits
##             the hit; a pierce of 0 is soaked by the shield first; every
##             weapon has a whole-percent pierce and the three torpedoes
##             skip the shield completely; an ion hit never reaches the hull;
##   blast     the share of a torpedo or flak hit that a target takes follows
##             its size and speed (BlastScale), before the shield;
##   tail gun  the Bomber's rear gun faces the tail, shoots at an enemy behind
##             it, leaves an enemy ahead alone, and never takes a torpedo as
##             its target;
##   crowded   a nearer enemy ahead does not hide the one behind from the rear
##             gun: it takes the one it can reach;
##   ai rules  a computer pilot's needed fan score is 180 points against big
##             targets and 90 against small ones, and its nearest launch
##             distance is never inside the arming distance plus the target's
##             size plus 60;
##   blocked   an AI Bomber that stands in its launch window of a standing
##             target with a rock in the torpedo's width (but off the thin
##             line the hidden-target rule looks along) gives the target up
##             after 3 seconds; a rock that goes away in time costs nothing,
##             and without a rock the Bomber waits for a tight fan (180 points,
##             so about 1.5 s), starts its run and launches it; a weak pilot's
##             aim wobble does not hold the fan back;
##   touch     an AI Bomber that rests against a rock in its launch window,
##             with a target that stands still, starts a run or gives the
##             target up within about 3 seconds, instead of waiting there for
##             good;
##   settle    an AI Bomber's run that ends with the cancel input has one
##             reason counted, whoever ended it (the pilot's own check, or
##             the end of the tick: the target lost, the brain gone home, a
##             rock hiding the target), so the reasons add up to the cancel
##             inputs and the AI cancels move by one.
## It prints one line per check that fails and then "run_check: N failures"
## (0 means all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=run_check
##
## WHO USES IT: main.gd loads it for --test=run_check. It changes only units of
## a frozen match that is thrown away.

## The length of a tick (seconds).
const DT := 1.0 / 60.0
## The hold of the Bomber's torpedo run, in ticks (1.5 s).
const WIND := 90
## The wait for the release after the bar is full, in ticks (1.5 s).
const READY := 90
## The reload after a launch, in ticks (1 s).
const RELOAD := 60

## The running match (set by setup()).
var world: World
## How many checks have failed.
var failures := 0
## Where the checks happen: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## A far corner where finished units are put away.
var _away := Vector2(-5000.0, -5000.0)
## How many units have been put away, so each gets its own far spot.
var _put_away := 0


## main.gd calls this once, right after the World is built. Freeze the match
## and start the checks on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Run every check, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_check_hold()
	_check_lock()
	_check_cancel()
	_check_window()
	_check_reload()
	_check_fan()
	_check_tightness()
	_check_arming()
	_check_tech()
	_check_pierce()
	_check_blast()
	_check_tail_gun()
	_check_tail_gun_crowded()
	_check_ai_rules()
	_check_blocked_line()
	await _check_touch_wait()
	_check_settle_reasons()
	print("run_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("run_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` for team `team`, standing still at `at`
## facing east, with nobody at the controls.
func _launch(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = at
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	# Keep the nose pointing east: the controls still point at the launch
	# heading, and the ship would turn toward it.
	s.controls.aim_point = at + Vector2(2000.0, 0.0)
	s.controls.face_point = s.controls.aim_point
	world.registry.rebuild_hashes()
	return s


## Put unit `u` away in its own far corner and make it dead.
func _put(u: Unit) -> void:
	_put_away += 1
	u.global_position = _away - Vector2(float(_put_away) * 400.0, 0.0)
	u.alive = false
	world.registry.rebuild_hashes()


## Step ship `s` (and the rounds in flight) `n` ticks with its fire button
## `fire`.
func _step(s: Ship, n: int, fire: bool) -> void:
	for _i in n:
		s.controls.fire = fire
		s.sim_update(DT)
		world.projectiles.tick(DT)


## Step ship `s` one tick with its fire button `fire` and the cancel input given
## (the edge ShipControls.cancel_run, which the right click makes).
func _step_cancel(s: Ship, fire: bool) -> void:
	s.controls.cancel_run = true
	_step(s, 1, fire)


## Let every round in flight run out (the longest life is 3 seconds), so a
## torpedo or bolt fired by an earlier check cannot hit the next check's units.
func _settle() -> void:
	for _i in 200:
		world.projectiles.tick(DT)


## How many torpedo runs have launched so far in this match.
func _launched() -> int:
	return _count("torpedo_runs_launched")


## The usage counter `key` (0 when it has not been counted yet).
func _count(key: String) -> int:
	return int(Game.usage.get(key, 0))


## The live torpedoes of Bomber runs, as slot numbers sorted by lane (0 left, 1
## centre, 2 right).
func _lane_slots() -> Array:
	var out: Array = []
	var p := world.projectiles
	for i in p.active:
		if p.live[i] == 1 and p.kind[i] == Rules.W_TORP and p.lane[i] >= 0:
			out.append(i)
	out.sort_custom(func(a: int, b: int) -> bool: return world.projectiles.lane[a] < world.projectiles.lane[b])
	return out


## hold: the bar is full after 90 ticks and nothing leaves; the torpedoes wait;
## a release with the bar full launches three on that tick.
func _check_hold() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	var before := _launched()
	_step(b, WIND - 1, true)
	_expect(_launched() == before, "hold: a torpedo left before the bar was full")
	_expect(absf(b.run_frac() - float(WIND - 1) / float(WIND)) < 0.001, "hold: the bar is not at 89/90 after 89 ticks (%s)" % b.run_frac())
	_expect(b.run_on() and b.run_locked(), "hold: the run is not on, or the heading is not locked")
	_step(b, 1, true)
	_expect(_launched() == before, "hold: torpedoes left on the 90th tick of the hold (they should wait for the release)")
	_expect(b.run_frac() == 1.0 and b.run_mount.run.is_full(), "hold: the bar is not full after 90 ticks")
	_step(b, READY - 30, true)
	_expect(_launched() == before and b.run_on(), "hold: the torpedoes did not wait while the button stayed down")
	var energy0 := b.energy.value
	var slots0 := _lane_slots().size()
	_step(b, 1, false)
	_expect(_launched() == before + 1, "hold: letting go with the bar full did not launch")
	var slots := _lane_slots()
	_expect(slots.size() == slots0 + 3, "hold: the run sent %d torpedoes, wanted 3" % (slots.size() - slots0))
	var lanes := []
	for i: int in slots:
		lanes.append(world.projectiles.lane[i])
	_expect(lanes == [0, 1, 2], "hold: the lanes are %s, wanted [0, 1, 2]" % [lanes])
	_expect(not b.run_on() and b.run_mount.run.reload == RELOAD, "hold: the run did not end with a %d-tick reload (%d)" % [RELOAD, b.run_mount.run.reload])
	_expect(absf(b.run_mount.cd - 1.0) < 0.001, "hold: the gun's cooldown is %s, wanted the reload in seconds (1.0)" % b.run_mount.cd)
	_expect(energy0 - b.energy.value > 14.0, "hold: the launch took %s energy, wanted 15" % (energy0 - b.energy.value))
	_put(b)
	_settle()


## lock: no turning, no sliding, W works; the lock holds through the launch tick;
## free again after.
func _check_lock() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	b.controls.face_point = _home + Vector2(0.0, 1000.0)
	b.controls.aim_point = b.controls.face_point
	b.controls.strafe = 1.0
	b.controls.forward = 1.0
	# Free flight first: the nose turns toward the face point and the ship slides.
	_step(b, 20, false)
	_expect(absf(b.rotation) > 0.05, "lock: without a run the nose did not turn (%s)" % b.rotation)
	# Now a run: from a standstill facing east.
	b.rotation = 0.0
	b.velocity = Vector2(0.0, 150.0)
	_step(b, 40, true)
	_expect(absf(b.rotation) < 1e-6, "lock: the nose turned during a run (%s)" % b.rotation)
	_expect(absf(b.velocity.y) < 150.0 * 0.6, "lock: the sideways drift did not die away (%s)" % b.velocity.y)
	_expect(b.velocity.x > 5.0, "lock: W did not push the ship along the nose (%s)" % b.velocity.x)
	# The release tick: the heading is still locked and the torpedoes leave along it.
	_step(b, WIND - 40, true)
	_step(b, 1, false)
	_expect(_lane_slots().size() == 3, "lock: the run did not launch on the release tick")
	_expect(absf(b.rotation) < 1e-6, "lock: the nose turned on the tick the torpedoes left (%s)" % b.rotation)
	var centre := _lane_slots()[1] as int
	var want := Vector2.RIGHT * float(Weapons.get_def("torpedo")["speed"]) + b.velocity * 0.35
	_expect(world.projectiles.vel[centre].distance_to(want) < 0.01, "lock: the middle torpedo does not go along the locked heading (%s, wanted %s)" % [world.projectiles.vel[centre], want])
	_step(b, 20, false)
	_expect(absf(b.rotation) > 0.05, "lock: the nose did not turn again after the launch (%s)" % b.rotation)
	_put(b)
	_settle()


## cancel: a release before the bar is full, the cancel input and a rock all end
## a run for free; the next run needs a fresh press.
func _check_cancel() -> void:
	_settle()
	# Letting go before the bar is full.
	var b := _launch("bomber", 0, _home)
	var before := _launched()
	var cancelled := _count("torpedo_runs_cancelled")
	_step(b, WIND - 10, true)
	_step(b, 1, false)
	_expect(_launched() == before, "cancel: letting go early launched a torpedo")
	_expect(_count("torpedo_runs_cancelled") == cancelled + 1, "cancel: the release was not counted as a cancel")
	_expect(b.run_frac() == 0.0 and not b.run_on() and b.run_mount.run.reload == 0, "cancel: the bar did not empty or a reload began")
	_step(b, 1, true)
	_expect(b.run_on(), "cancel: the new press did not start a run at once")
	_put(b)
	# The cancel input, in the hold and in the wait for the release.
	for when: int in [40, WIND + 20]:
		var c := _launch("bomber", 0, _home)
		var l0 := _launched()
		var input0 := _count("torpedo_runs_cancel_input")
		_step(c, when, true)
		_expect(c.run_on(), "cancel: no run was on at tick %d" % when)
		c.controls.face_point = _home + Vector2(0.0, 1000.0)
		c.controls.aim_point = c.controls.face_point
		_step_cancel(c, true)
		_expect(not c.run_on() and c.run_frac() == 0.0, "cancel: the cancel input at tick %d did not end the run" % when)
		_expect(_launched() == l0 and c.run_mount.run.reload == 0, "cancel: the cancel input at tick %d launched or began a reload" % when)
		_expect(_count("torpedo_runs_cancel_input") == input0 + 1, "cancel: the cancel input at tick %d was not counted" % when)
		_expect(absf(c.rotation) > 0.01, "cancel: the heading was still locked on the cancel tick (%s)" % c.rotation)
		_step(c, 30, true)
		_expect(not c.run_on(), "cancel: holding on after the cancel started a run without a fresh press")
		_step(c, 1, false)
		_step(c, 1, true)
		_expect(c.run_on(), "cancel: a fresh press after the cancel did not start a run")
		_put(c)
	# The cancel input with no run on does nothing.
	var d := _launch("bomber", 0, _home)
	var input1 := _count("torpedo_runs_cancel_input")
	_step_cancel(d, false)
	_expect(_count("torpedo_runs_cancel_input") == input1 and not d.run_on(), "cancel: the cancel input did something with no run on")
	# Touching a rock (ShipFlight.move() calls this): free, and a held button needs a fresh press.
	var rock0 := _count("torpedo_runs_cancel_rock")
	_step(d, 30, true)
	d.run_mount.run.cancel(true)
	_expect(not d.run_on() and d.run_mount.run.reload == 0 and d.run_mount.run.need_press, "cancel: touching a rock did not end the run for free")
	_expect(_count("torpedo_runs_cancel_rock") == rock0 + 1, "cancel: the rock cancel was not counted")
	_put(d)
	_settle()


## window: a hold that reaches 180 ticks launches by itself, then needs a fresh press.
func _check_window() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	var before := _launched()
	var auto0 := _count("torpedo_runs_launched_auto")
	_step(b, WIND + READY - 1, true)
	_expect(_launched() == before and b.run_on(), "window: the torpedoes left before the wait ran out")
	_step(b, 1, true)
	_expect(_launched() == before + 1, "window: the torpedoes did not leave by themselves on the 180th tick")
	_expect(_count("torpedo_runs_launched_auto") == auto0 + 1, "window: the automatic launch was not counted")
	_expect(_lane_slots().size() == 3, "window: the run did not send three torpedoes")
	_step(b, RELOAD + 120, true)
	_expect(_launched() == before + 1 and not b.run_on(), "window: holding on after the launch started another run")
	_step(b, 1, false)
	_step(b, 1, true)
	_expect(b.run_on(), "window: a fresh press after the launch did not start a run")
	_put(b)
	_settle()


## reload: no hold for 60 ticks after a launch, a press during the reload needs
## the button let go, a hold starts on the 60th tick; energy under 15 starts
## nothing, and a run the battery cannot pay fires nothing.
func _check_reload() -> void:
	_settle()
	# The 60th tick after the launch tick starts a hold.
	var a := _launch("bomber", 0, _home)
	_step(a, WIND, true)
	_step(a, 1, false)
	_step(a, RELOAD - 1, false)
	_step(a, 1, true)
	_expect(a.run_on(), "reload: a press on the 60th tick after the launch did not start a run")
	_put(a)
	# A press on the 59th tick is ignored, and so is holding on after it.
	var b := _launch("bomber", 0, _home)
	_step(b, WIND, true)
	_step(b, 1, false)
	_step(b, RELOAD - 2, false)
	_step(b, 1, true)
	_expect(not b.run_on(), "reload: a press during the reload started a run")
	_step(b, 20, true)
	_expect(not b.run_on(), "reload: holding on through the end of the reload started a run without a fresh press")
	_step(b, 1, false)
	_step(b, 1, true)
	_expect(b.run_on(), "reload: a fresh press after the reload did not start a run")
	_put(b)
	# Fire-rate gear shortens the reload (never under one tick): the launch tick
	# is given by hand here, with a fire-rate multiplier of 2.
	var g := _launch("bomber", 0, _home)
	_step(g, WIND, true)
	g.run_mount.update(DT, g.controls.aim_point, false, 2.0, g.dmg_mult, g.range_mult, g.energy)
	_expect(g.run_mount.run.reload == RELOAD / 2, "reload: with a fire-rate multiplier of 2 the reload is %d ticks, wanted %d" % [g.run_mount.run.reload, RELOAD / 2])
	_put(g)
	# Energy: no hold under 15, none of the lock, none of the bar.
	var e := _launch("bomber", 0, _home)
	for _i in 10:
		e.energy.value = 14.5
		_step(e, 1, true)
	_expect(not e.run_on() and e.run_frac() == 0.0 and not e.run_locked(), "reload: a run began with the battery under 15")
	e.energy.value = 15.0
	_step(e, 1, true)
	_expect(e.run_on(), "reload: a run did not begin with 15 energy")
	# The battery runs dry during the hold: nothing is fired, there is no reload.
	var unpaid := _count("torpedo_runs_unpaid")
	var l0 := _launched()
	var in_flight := _lane_slots().size()
	_step(e, WIND - 1, true)
	e.energy.value = 5.0
	_step(e, 1, false)
	_expect(_launched() == l0 and _lane_slots().size() <= in_flight, "reload: a run the battery could not pay fired torpedoes")
	_expect(_count("torpedo_runs_unpaid") == unpaid + 1, "reload: the unpaid run was not counted")
	_expect(not e.run_on() and e.run_mount.run.reload == 0, "reload: the unpaid run left a run on or a reload")
	_put(e)
	_settle()


## fan: the half-angle table, the lanes' angles, muzzles and speed, a real launch.
func _check_fan() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	var m := b.run_mount
	var table := {0: 18.0, 90: 14.25, 180: 10.5, 270: 6.75, 360: 3.0}
	for pts: int in table:
		var got := rad_to_deg(RunFan.half_angle(m.def, pts))
		_expect(absf(got - float(table[pts])) < 0.001, "fan: at %d points the half-angle is %s degrees, wanted %s" % [pts, got, table[pts]])
	var speed := float(m.def["speed"])
	var gun := m.world_pos()
	for pts: int in [0, 180, 360]:
		var half := RunFan.half_angle(m.def, pts)
		var lanes := RunFan.lanes(m, pts)
		_expect(lanes.size() == 3, "fan: %d lanes at %d points" % [lanes.size(), pts])
		if lanes.size() != 3:
			continue
		var angles := []
		for l: Array in lanes:
			angles.append((l[1] as Vector2).angle())
			_expect(absf((l[1] as Vector2).length() - speed) < 0.01, "fan: a lane at %d points has speed %s, wanted %s" % [pts, (l[1] as Vector2).length(), speed])
		_expect(absf(float(angles[1])) < 1e-5 and absf(float(angles[0]) + half) < 1e-5 and absf(float(angles[2]) - half) < 1e-5, "fan: the lane angles at %d points are %s, wanted [-%s, 0, %s]" % [pts, angles, half, half])
		# The muzzles: 12 units apart across the nose (plus 4 ahead along each lane).
		var s0: Vector2 = lanes[0][0]
		var s1: Vector2 = lanes[1][0]
		var s2: Vector2 = lanes[2][0]
		_expect(absf(s1.y - gun.y) < 0.01 and absf((s2.y - s1.y) - (12.0 + 4.0 * sin(half))) < 0.01 and absf((s1.y - s0.y) - (12.0 + 4.0 * sin(half))) < 0.01, "fan: the muzzles at %d points are at y %s %s %s" % [pts, s0.y, s1.y, s2.y])
	# A real launch matches the lanes for the score at that tick. The ship moves
	# along its heading, so the speeds are compared as the lanes give them.
	_step(b, WIND, true)
	_step(b, 1, false)
	var slots := _lane_slots()
	_expect(slots.size() == 3, "fan: a real run sent %d torpedoes" % slots.size())
	if slots.size() == 3:
		var want := RunFan.lanes(m, b.fan_points)
		for k in 3:
			var got := world.projectiles.vel[slots[k]] as Vector2
			_expect(got.distance_to((want[k] as Array)[1]) < 0.01, "fan: lane %d flies %s, the lanes give %s at %d points" % [k, got, (want[k] as Array)[1], b.fan_points])
	_put(b)
	_settle()


## tightness: +2 a tick of steady flight, -6 a tick of turn or strafe input, a
## stall while boosting, never outside 0 to 360, and no penalty during a run.
func _check_tightness() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	_step(b, 30, false)
	_expect(b.fan_points == 60, "tightness: after 30 steady ticks the score is %d, wanted 60" % b.fan_points)
	# Turn input: the nose turns by far more than a hair each tick.
	b.controls.face_point = _home + Vector2(0.0, -2000.0)
	b.controls.aim_point = b.controls.face_point
	_step(b, 5, false)
	_expect(b.fan_points == 30, "tightness: after 5 ticks of turning the score is %d, wanted 30" % b.fan_points)
	# Settled and steady again.
	b.rotation = -PI * 0.5
	_step(b, 10, false)
	_expect(b.fan_points == 50, "tightness: after 10 more steady ticks the score is %d, wanted 50" % b.fan_points)
	# Strafe input of 0.12 or more costs 6; under 0.12 it does not.
	b.controls.strafe = 1.0
	_step(b, 3, false)
	_expect(b.fan_points == 32, "tightness: after 3 ticks of strafe input the score is %d, wanted 32" % b.fan_points)
	b.controls.strafe = 0.1
	_step(b, 1, false)
	_expect(b.fan_points == 34, "tightness: a strafe input of 0.1 changed the score to %d, wanted 34" % b.fan_points)
	b.controls.strafe = 0.0
	# Boosting stalls the score (RunFan.tick() is called by hand: the Bomber has no booster).
	b.boosting = true
	b.turned = false
	var before := b.fan_points
	RunFan.tick(b)
	_expect(b.fan_points == before, "tightness: boosting changed the score from %d to %d" % [before, b.fan_points])
	b.boosting = false
	# The score stays between 0 and 360.
	b.fan_points = 359
	RunFan.tick(b)
	RunFan.tick(b)
	_expect(b.fan_points == 360, "tightness: the score went past 360 (%d)" % b.fan_points)
	b.fan_points = 3
	b.turned = true
	RunFan.tick(b)
	_expect(b.fan_points == 0, "tightness: the score went under 0 (%d)" % b.fan_points)
	# During a run the locked heading counts as steady whatever the keys say.
	b.turned = false
	b.fan_points = 100
	b.controls.strafe = 1.0
	b.controls.face_point = _home + Vector2(0.0, 1000.0)
	_step(b, 10, true)
	_expect(b.run_on() and b.fan_points == 120, "tightness: ten ticks of a run gave %d, wanted 120" % b.fan_points)
	_put(b)
	_settle()


## arming: a torpedo that touches a ship inside 200 units of flight is a dud; later it hurts.
func _check_arming() -> void:
	_settle()
	for scene: Array in [["dud", 100.0], ["hit", 400.0]]:
		var b := _launch("bomber", 0, _home)
		var t := _launch("destroyer", 1, _home + Vector2(2000.0, 0.0))
		# The target's edge stands `scene[1]` units ahead of the muzzle.
		t.global_position = b.run_mount.world_pos() + Vector2(float(scene[1]) + t.hit_radius(), 0.0)
		world.registry.rebuild_hashes()
		var duds := _count("torpedo_dud")
		var hits := _count("torpedo_lane_hit_left") + _count("torpedo_lane_hit_centre") + _count("torpedo_lane_hit_right")
		var shield0 := t.shield_total()
		var hull0 := t.hull
		_step(b, WIND, true)
		_step(b, 1, false)
		_step(b, 120, false)
		var hits_now := _count("torpedo_lane_hit_left") + _count("torpedo_lane_hit_centre") + _count("torpedo_lane_hit_right")
		if scene[0] == "dud":
			_expect(_count("torpedo_dud") == duds + 3 and _count("torpedo_dud_big") >= 3, "arming: %d duds at 100 units, wanted 3" % (_count("torpedo_dud") - duds))
			_expect(hits_now == hits and t.hull == hull0 and t.shield_total() == shield0, "arming: a torpedo inside 200 units hurt the target (hull %s of %s)" % [t.hull, hull0])
		else:
			_expect(_count("torpedo_dud") == duds and hits_now == hits + 3, "arming: at 400 units %d duds and %d hits, wanted 0 and 3" % [_count("torpedo_dud") - duds, hits_now - hits])
			_expect(t.hull < hull0 - 100.0, "arming: the armed torpedoes took only %s from the hull" % (hull0 - t.hull))
		_put(b)
		_put(t)
		_settle()
	# The drawing question: an armed torpedo has no arming distance left.
	var src := _launch("bomber", 1, _home + Vector2(4000.0, 0.0))
	var def := Weapons.get_def("torpedo")
	var cold := world.projectiles.spawn(_home + Vector2(5000.0, 0.0), Vector2(100.0, 0.0), 3.0, 10.0, Rules.W_TORP, def, src, null)
	var warm := world.projectiles.spawn(_home + Vector2(5000.0, 500.0), Vector2(100.0, 0.0), 3.0, 10.0, Rules.W_TORP, Weapons.get_def("m_torp"), src, null)
	_expect(not world.projectiles.armed(cold) and world.projectiles.armed(warm), "arming: a Bomber's torpedo starts unarmed and a Light Bomber's armed")
	for _i in 140:
		world.projectiles.tick(DT)
	_put(src)
	_settle()


## tech: Steady Sights, Armoured Torpedoes and the Focus shot's bonus.
func _check_tech() -> void:
	_settle()
	var ts := world.teams[0]
	var gain := ts.fan_gain
	var bonus := ts.torp_hp_bonus
	_expect(str(Tech.TECHS["improvedBombs"]["label"]) == "Steady Sights", "tech: the research is called %s" % Tech.TECHS["improvedBombs"]["label"])
	ts.apply_effect(Tech.TECHS["improvedBombs"]["effect"])
	ts.apply_effect(Tech.TECHS["torpedoArmor"]["effect"])
	_expect(ts.fan_gain == gain + 1, "tech: Steady Sights did not add 1 to the gain (%s)" % ts.fan_gain)
	var b := _launch("bomber", 0, _home)
	_step(b, 10, false)
	_expect(b.fan_points == 30, "tech: Steady Sights gave %d points in 10 steady ticks, wanted 30" % b.fan_points)
	# The hold is still 90 ticks. The torpedoes have 30 hit points each (20 x 1.5).
	var before := _launched()
	_step(b, WIND - 1, true)
	_expect(_launched() == before and not b.run_mount.run.is_full(), "tech: the bar was full a tick early")
	_step(b, 1, true)
	_expect(b.run_mount.run.is_full(), "tech: the bar was not full after 90 ticks")
	# The Focus shot (its special sets this on the fixed guns): +45% on all three, once.
	b.run_mount.next_mult = 1.45
	_step(b, 1, false)
	var slots := _lane_slots()
	_expect(slots.size() == 3, "tech: the run sent %d torpedoes" % slots.size())
	var want_hp := float(Weapons.get_def("torpedo")["torp_hp"]) * 1.5
	for i: int in slots:
		_expect(absf(world.projectiles.hp[i] - want_hp) < 0.01, "tech: a torpedo has %s hit points, wanted %s" % [world.projectiles.hp[i], want_hp])
		_expect(absf(world.projectiles.dmg[i] - float(Weapons.get_def("torpedo")["dmg"]) * b.dmg_mult * 1.45) < 0.01, "tech: a torpedo of the Focus shot hits for %s" % world.projectiles.dmg[i])
	_expect(b.run_mount.next_mult == 1.0, "tech: the Focus shot's bonus was not used up by the run")
	ts.fan_gain = gain
	ts.torp_hp_bonus = bonus
	_put(b)
	_settle()


## pierce: the shield skip of a hit, in thirds.
func _check_pierce() -> void:
	var f := _launch("fighter", 1, _home + Vector2(2000.0, 0.0))
	var info := DamageInfo.new()
	info.kind = Rules.W_TORP
	info.from_pos = f.global_position + Vector2(300.0, 0.0)
	var shield0 := f.shields.total()
	var hull0 := f.hull
	# The hits are small, so the one shield zone they land on (a quarter of
	# the shield) can always soak what it is asked to.
	var hit := 8.0
	# A full pierce: shields and their wait untouched, the hull takes it all.
	f.shields.since_hit = 5.0
	info.pierce = 1.0
	f.take_hit(info, hit)
	_expect(f.shields.total() == shield0, "pierce 1: the shields lost points (%s of %s)" % [f.shields.total(), shield0])
	_expect(f.shields.since_hit == 5.0, "pierce 1: the shields' refill wait was restarted")
	_expect(absf(f.hull - (hull0 - hit * (1.0 - f.hull_resist))) < 0.001, "pierce 1: the hull took %s" % (hull0 - f.hull))
	# Half: half soaked, half through.
	f.hull = hull0
	info.pierce = 0.5
	f.take_hit(info, hit)
	_expect(absf(f.shields.total() - (shield0 - hit * 0.5)) < 0.001, "pierce 0.5: the shields lost %s, wanted %s" % [shield0 - f.shields.total(), hit * 0.5])
	_expect(absf(f.hull - (hull0 - hit * 0.5 * (1.0 - f.hull_resist))) < 0.001, "pierce 0.5: the hull took %s" % (hull0 - f.hull))
	# None: the shield soaks it.
	f.hull = hull0
	var shield1 := f.shields.total()
	info.pierce = 0.0
	f.take_hit(info, hit)
	_expect(absf(f.shields.total() - (shield1 - hit)) < 0.001, "pierce 0: the shields lost %s, wanted %s" % [shield1 - f.shields.total(), hit])
	_expect(f.hull == hull0, "pierce 0: the hull was hurt")
	_expect(f.shields.since_hit == 0.0, "pierce 0: the refill wait was not restarted")
	# Every weapon has a whole-percent pierce between 0 and 100, and the three
	# torpedoes skip the shield completely.
	for wid: String in Weapons.WEAPONS:
		var p = Weapons.get_def(wid).get("pierce")
		_expect(p is int and int(p) >= 0 and int(p) <= 100, "pierce: %s has no whole-percent pierce (%s)" % [wid, p])
	for wid: String in ["torpedo", "m_torp", "turret_torp"]:
		_expect(int(Weapons.get_def(wid)["pierce"]) == 100, "pierce: the torpedo %s does not skip the shield completely" % wid)
	# An ion hit only loads the shield: with the shield down it still does not reach the hull.
	var ion := DamageInfo.new()
	ion.kind = Rules.W_ION
	ion.from_pos = f.global_position + Vector2(300.0, 0.0)
	f.hull = hull0
	var zone := ShieldZones.zone_for_local(Vector2(300.0, 0.0))
	var zone0 := f.shields.values[zone]
	f.take_hit(ion, zone0 * 4.0)
	_expect(f.shields.values[zone] == 0.0, "ion: the shield zone was not emptied (%s)" % f.shields.values[zone])
	_expect(f.hull == hull0, "ion: a hit that broke the shield zone hurt the hull (%s of %s)" % [f.hull, hull0])
	_put(f)


## blast: the share of a torpedo or flak hit that a target takes follows its
## size and speed (BlastScale), before the shield sees the hit.
func _check_blast() -> void:
	# The lookup: a target as big as the blast takes it all, a weapon with no
	# blast size is no blast weapon, and smaller or faster means less.
	_expect(BlastScale.percent(0, 65, 400, 65.0, 0.0) == 100, "blast: a target as big as the blast takes %s percent" % BlastScale.percent(0, 65, 400, 65.0, 0.0))
	_expect(BlastScale.percent(0, 0, 0, 5.0, 900.0) == 100, "blast: a weapon with no blast size scales the hit")
	var still := BlastScale.percent(0, 65, 400, 13.0, 0.0)
	var fast := BlastScale.percent(0, 65, 400, 13.0, 640.0)
	_expect(still < 100 and fast < still and fast > 0, "blast: a small target takes %s at rest and %s at speed" % [still, fast])
	# A torpedo's hit: a Fighter takes a share, a Destroyer all of it.
	var f := _launch("fighter", 1, _home + Vector2(2000.0, 0.0))
	var d := _launch("destroyer", 1, _home + Vector2(2000.0, 1500.0))
	var torp := Weapons.get_def("torpedo")
	var note := DamageInfo.new()
	note.amount = float(torp["dmg"])
	note.blast_size = int(torp["blast_size"])
	note.blast_speed = int(torp["blast_speed"])
	note.blast_curve = int(torp["blast_curve"])
	BlastScale.apply(note, f)
	var want := float(torp["dmg"]) * float(BlastScale.percent(note.blast_curve, note.blast_size, note.blast_speed, f.hit_radius(), 0.0)) / 100.0
	_expect(note.amount < float(torp["dmg"]) * 0.5 and absf(note.amount - want) < 0.001, "blast: a torpedo hit on a Fighter is %s, wanted %s" % [note.amount, want])
	note.amount = float(torp["dmg"])
	BlastScale.apply(note, d)
	_expect(note.amount == float(torp["dmg"]), "blast: a torpedo hit on a Destroyer is %s, wanted all of it" % note.amount)
	# A flak burst right at a Fighter: the shield loses the Fighter's share of
	# the burst's damage.
	var flak := Weapons.get_def("flak_battery")
	var burst := DamageInfo.new()
	burst.amount = float(flak["dmg"])
	burst.kind = Rules.W_FLAK
	burst.blast_size = int(flak["blast_size"])
	burst.blast_speed = int(flak["blast_speed"])
	burst.blast_curve = int(flak["blast_curve"])
	var shield0 := f.shields.total()
	var at := f.global_position + Vector2(f.hit_radius() + 5.0, 0.0)
	world.combat.area(burst, at, float(flak["burst"]), 0)
	var share := float(BlastScale.percent(burst.blast_curve, burst.blast_size, burst.blast_speed, f.hit_radius(), 0.0)) / 100.0
	var lost := shield0 - f.shields.total()
	_expect(share < 1.0 and absf(lost - float(flak["dmg"]) * share) < 0.001, "blast: a flak burst took %s from a Fighter's shield, wanted %s" % [lost, float(flak["dmg"]) * share])
	_put(f)
	_put(d)


## tail gun: faces the tail, fires at an enemy behind, ignores one ahead,
## never picks a torpedo.
func _check_tail_gun() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	var tail: WeaponMount = null
	for m: WeaponMount in b.mounts:
		if m.weapon_id == "tail_gun":
			tail = m
	_expect(tail != null, "tail gun: the Bomber has none")
	if tail == null:
		_put(b)
		return
	_expect(absf(absf(tail.face) - PI) < 1e-6 and absf(tail.arc - deg_to_rad(60.0)) < 1e-6, "tail gun: it faces %s with an arc of %s" % [tail.face, tail.arc])
	_expect(absf(absf(tail.angle) - PI) < 1e-6, "tail gun: it does not start pointing at the tail (%s)" % tail.angle)
	_expect(tail.offset.x < 0.0 and tail.mount_type == WeaponMount.AUTO, "tail gun: it is not an automatic mount near the tail")
	# An enemy ahead: the gun leaves it alone.
	var e := _launch("fighter", 1, _home + Vector2(300.0, 0.0))
	_step(b, 60, false)
	_expect(not tail.engaged and tail.target == null, "tail gun: it took a target ahead of the ship")
	# The enemy behind, inside the arc: the gun swings and fires.
	e.global_position = _home + Vector2(-300.0, 40.0)
	world.registry.rebuild_hashes()
	var shots := 0
	for _i in 90:
		_step(b, 1, false)
		if tail.cd > 0.1:
			shots += 1
	_expect(tail.target == e, "tail gun: it did not take the enemy behind the ship (target %s, angle %s, engaged %s, the ship faces %s)" % [tail.target, tail.angle, tail.engaged, b.rotation])
	_expect(shots > 0, "tail gun: it did not fire at the enemy behind the ship")
	_expect(absf(Util.wrap_angle(tail.angle - PI)) < deg_to_rad(60.0) + 0.05, "tail gun: it swung out of its arc (%s)" % tail.angle)
	# Behind, outside the arc (to the side): left alone.
	e.global_position = _home + Vector2(0.0, 300.0)
	world.registry.rebuild_hashes()
	_step(b, 60, false)
	_expect(tail.target == null, "tail gun: it took a target to the side, outside its arc")
	# An enemy torpedo behind it: never its target.
	_put(e)
	var src := _launch("bomber", 1, _home + Vector2(4000.0, 0.0))
	var def := Weapons.get_def("torpedo")
	world.projectiles.spawn(_home + Vector2(-150.0, 0.0), Vector2(100.0, 0.0), 3.0, 10.0, Rules.W_TORP, def, src, null)
	_step(b, 40, false)
	_expect(tail.target_torp == -1, "tail gun: it picked an enemy torpedo")
	_put(src)
	_put(b)


## crowded: an enemy ahead (outside the gun's swing) is nearer than the one
## behind (inside it). The gun must take the one behind and shoot it.
func _check_tail_gun_crowded() -> void:
	_settle()
	var b := _launch("bomber", 0, _home)
	var tail: WeaponMount = null
	for m: WeaponMount in b.mounts:
		if m.weapon_id == "tail_gun":
			tail = m
	if tail == null:
		_put(b)
		return
	var ahead := _launch("fighter", 1, _home + Vector2(250.0, 0.0))
	var behind := _launch("fighter", 1, _home + Vector2(-300.0, 40.0))
	var shots := 0
	for _i in 90:
		_step(b, 1, false)
		if tail.cd > 0.1:
			shots += 1
	_expect(tail.target == behind, "crowded: the rear gun did not take the enemy behind the ship with a nearer one ahead (target %s)" % tail.target)
	_expect(shots > 0, "crowded: the rear gun did not fire at the enemy behind the ship (shots %d)" % shots)
	_put(ahead)
	_put(behind)
	_put(b)


## Run an AI-brained Bomber against a standing enemy Destroyer for up to
## `secs` seconds, the brain's own commands only (the match is frozen, so the
## brain is not asked to think: its target is set by hand). The Bomber starts
## in the middle of its launch window. With `rock` there is one rock beside the
## middle of the line to the target: its edge lies inside the torpedo's width
## but outside the thin line from the ship to the target. `rock_secs` is how
## long the rock stays (-1 = for good). `skill` is the pilot's skill (1.0 has no
## aim wobble). Stops at the first run it starts, or when the brain gives the
## target up. Returns {commit, declined, gave_up, secs, gap, thin_blocked,
## wide_blocked, fan, slow_ticks, hold, fan_at_launch}: the Bomber's tightness
## score at the commit, the number of ticks (after the first 30, while the pilot
## settles its nose) in which the score did not grow by 2, and with 	o_launch,
## which keeps going until the torpedoes leave: the ticks from the commit to the
## launch, and the score at the launch.
func _blocked_run(rock: bool, rock_secs: float, secs: float, skill: float = 1.0, to_launch: bool = false) -> Dictionary:
	_settle()
	var target := _launch("destroyer", 1, _home + Vector2(1200.0, 0.0))
	var b := _launch("bomber", 0, _home)
	var brain := PilotAI.new(world, b.profile)
	brain.skill = skill
	brain._reset_after_launch()
	brain.target = target
	var commits0 := int(Game.usage.get("torpedo_runs_ai_commit", 0))
	var declined0 := int(Game.usage.get("torpedo_runs_ai_declined_blocked", 0))
	# Let the brain pick its launch distance now, then stand still in the middle
	# of the window, nose at the target.
	brain.run._pick_launch(target)
	var hs := target.hit_radius()
	var reach := b.run_mount.reach * b.range_mult
	b.global_position = target.global_position - Vector2(hs + reach * brain.run._launch_frac, 0.0)
	b.rotation = 0.0
	b.velocity = Vector2.ZERO
	var gun := b.run_mount.world_pos()
	var edge := target.global_position - Vector2(hs, 0.0)
	var rock_i := -1
	if rock:
		var r := 60.0
		var at := Vector2((gun.x + edge.x) * 0.5, gun.y + r * 0.95 + 3.0)
		world.asteroids._add(at, r, false, Mulberry.new(1))
		world.asteroids.queries.make_room(world.asteroids.pos.size())
		rock_i = world.asteroids.pos.size() - 1
	world.registry.rebuild_hashes()
	var out := {"commit": 0, "declined": 0, "gave_up": false, "secs": 0.0, "gap": 0.0,
			"thin_blocked": world.asteroids.segment_blocked(b.global_position, target.global_position),
			"wide_blocked": not world.asteroids.segment_hit(gun, edge, PilotRun.TORP_RADIUS).is_empty()}
	var ticks := int(secs * 60.0)
	var slow := 0
	var last_pts := b.fan_points
	var launched0 := _launched()
	var commit_tick := -1
	for i in ticks:
		if rock_i >= 0 and rock_secs >= 0.0 and i == int(rock_secs * 60.0):
			world.asteroids.destroy(rock_i)
		world.time += DT
		brain.combat.steer(b)
		b.sim_update(DT)
		world.projectiles.tick(DT)
		# After the nose has settled the score must grow by 2 every tick the pilot waits.
		if i >= 30 and b.fan_points < 360 and b.fan_points - last_pts < 2:
			slow += 1
		last_pts = b.fan_points
		out["secs"] = float(i + 1) / 60.0
		if int(Game.usage.get("torpedo_runs_ai_commit", 0)) > commits0:
			if not to_launch:
				break
			if commit_tick < 0:
				commit_tick = i
				out["fan"] = b.fan_points
		if to_launch and _launched() > launched0:
			out["hold"] = i - commit_tick
			out["fan_at_launch"] = b.fan_points
			break
		if brain.skip_id != 0:
			break
	out["commit"] = int(Game.usage.get("torpedo_runs_ai_commit", 0)) - commits0
	out["declined"] = int(Game.usage.get("torpedo_runs_ai_declined_blocked", 0)) - declined0
	out["gave_up"] = brain.skip_id == target.get_instance_id() and brain.target == null and brain.lock_target == null \
			and absf((brain.skip_until - world.time) - 6.0) < 0.05
	out["gap"] = b.global_position.distance_to(target.global_position) - hs
	if not to_launch:
		out["fan"] = b.fan_points
	out["slow_ticks"] = slow
	# Let go of the button and clear the scene for the next check.
	b.controls.fire = false
	if rock_i >= 0:
		world.asteroids.destroy(rock_i)
	_put(b)
	_put(target)
	return out


## blocked: see the header. Without a rock the Bomber starts its run; with a
## rock beside the line it never fires and gives the target up after 3 s; a
## rock that goes away after 2 s costs nothing.
func _check_blocked_line() -> void:
	var open_line := _blocked_run(false, -1.0, 20.0)
	_expect(open_line["commit"] == 1, "blocked: with a clear line the Bomber did not start a run (%s)" % [open_line])
	_expect(not open_line["gave_up"] and not open_line["wide_blocked"], "blocked: the control scene is not clear (%s)" % [open_line])
	var blocked := _blocked_run(true, -1.0, 20.0)
	_expect(not blocked["thin_blocked"] and blocked["wide_blocked"], "blocked: the rock is not where the check wants it (%s)" % [blocked])
	_expect(blocked["commit"] == 0, "blocked: the Bomber started a run into a rock in its path (%s)" % [blocked])
	_expect(blocked["gave_up"], "blocked: after %.1f s the Bomber had not given the target up (%s)" % [blocked["secs"], blocked])
	_expect(blocked["gave_up"] and blocked["secs"] <= 4.0, "blocked: the Bomber took %.1f s to give the target up, wanted about 3 (%s)" % [blocked["secs"], blocked])
	_expect(blocked["declined"] == 1, "blocked: the give-up was not counted once (%s)" % [blocked])
	var passing := _blocked_run(true, 2.0, 20.0)
	print("run_check: blocked line, seconds until the first run starts or the target is given up: no rock %.2f (run), rock %.2f (%s), rock gone after 2 s %.2f (run)" % [open_line["secs"], blocked["secs"], "given up" if blocked["gave_up"] else "no give-up", passing["secs"]])
	_expect(passing["commit"] == 1 and not passing["gave_up"], "blocked: a rock that went away after 2 s still cost the target (%s)" % [passing])
	# The Bomber waits for the fan: no run before the score is 180 points (90
	# steady ticks, 1.5 s), and the score grows by 2 every tick it waits.
	_expect(float(open_line["secs"]) >= 1.4 and int(open_line["fan"]) >= PilotRunFan.NEED_BIG, "blocked: the Bomber started its run after %.2f s with a fan of %d points, wanted at least 1.4 s and 180 points" % [open_line["secs"], open_line["fan"]])
	_expect(int(open_line["slow_ticks"]) == 0, "blocked: the fan score grew by less than 2 in %d ticks while the Bomber waited" % open_line["slow_ticks"])
	# A weak pilot's aim wobble does not hold the fan back (the nose turns far less than 0.003 radians a tick).
	var weak := _blocked_run(false, -1.0, 20.0, 0.5)
	_expect(weak["commit"] == 1 and int(weak["fan"]) >= PilotRunFan.NEED_BIG, "blocked: a weak pilot did not commit with a tight fan (%s)" % [weak])
	_expect(int(weak["slow_ticks"]) <= 3, "blocked: a weak pilot's fan score grew by less than 2 in %d ticks while it waited" % weak["slow_ticks"])
	# The whole run: committed, held 90 ticks with the bar filling, let go with the fan still tight, launched.
	var whole := _blocked_run(false, -1.0, 30.0, 1.0, true)
	_expect(whole.has("hold") and int(whole["hold"]) == WIND and int(whole["fan_at_launch"]) >= PilotRunFan.NEED_BIG, "blocked: the run from the commit to the launch took %s ticks, the fan at the launch was %s (%s)" % [whole.get("hold"), whole.get("fan_at_launch"), whole])
	print("run_check: AI fan, a pilot of skill 1.0 started its run after %.2f s with %d points and waited with %d slow ticks; a pilot of skill 0.5 started after %.2f s with %d points and %d slow ticks; the whole run held %s ticks and launched at %s points" % [open_line["secs"], open_line["fan"], open_line["slow_ticks"], weak["secs"], weak["fan"], weak["slow_ticks"], whole.get("hold"), whole.get("fan_at_launch")])


## Run an AI-brained Bomber in the middle of its launch window against a Destroyer
## that stands still (as _blocked_run() does), with a rock pressed against the
## Bomber's side: the rock's edge lies `overlap` world units inside the Bomber's
## hull circle, and off the line to the target, so only the touch keeps the pilot
## from a run. `drift` is the Bomber's starting speed toward the rock (0 = at
## rest). `rock_secs` is how long the rock stays (-1 = for good). Stops when the
## pilot starts a run or gives the target up, or after `secs` seconds. Returns
## {commit, gave_up, declined, secs, touch_ticks, first_touch, last_touch,
## top_speed, phase, trace}: `trace` lists "tick:touches/phase/speed" every half
## second, `touch_ticks` the ticks in which the Bomber's last move touched
## something, `top_speed` its fastest speed in such a tick.
func _touch_run(overlap: float, drift: float, rock_secs: float, secs: float) -> Dictionary:
	_settle()
	var target := _launch("destroyer", 1, _home + Vector2(1200.0, 0.0))
	var b := _launch("bomber", 0, _home)
	var brain := PilotAI.new(world, b.profile)
	brain.skill = 1.0
	brain._reset_after_launch()
	brain.target = target
	var commits0 := _count("torpedo_runs_ai_commit")
	var declined0 := _count("torpedo_runs_ai_declined_touch")
	# Pick the launch distance now, then stand still in the middle of the window,
	# nose at the target, the rock against the side away from the target's line.
	brain.run._pick_launch(target)
	var hs := target.hit_radius()
	var reach := b.run_mount.reach * b.range_mult
	b.global_position = target.global_position - Vector2(hs + reach * brain.run._launch_frac, 0.0)
	b.rotation = 0.0
	b.velocity = Vector2(0.0, drift)
	var r := 60.0
	world.asteroids._add(b.global_position + Vector2(0.0, b.radius + r * 0.95 - overlap), r, false, Mulberry.new(1))
	world.asteroids.queries.make_room(world.asteroids.pos.size())
	var rock_i := world.asteroids.pos.size() - 1
	world.registry.rebuild_hashes()
	# The physics server takes the new rock into its space on its next step.
	await get_tree().physics_frame
	var out := {"commit": 0, "gave_up": false, "declined": 0, "secs": 0.0, "touch_ticks": 0, "first_touch": -1,
			"last_touch": -1, "top_speed": 0.0, "phase": brain.run.phase, "trace": ""}
	for i in int(secs * 60.0):
		if rock_secs >= 0.0 and i == int(rock_secs * 60.0):
			world.asteroids.destroy(rock_i)
		world.time += DT
		brain.combat.steer(b)
		b.sim_update(DT)
		world.projectiles.tick(DT)
		var n := b.get_slide_collision_count()
		if n > 0:
			out["touch_ticks"] += 1
			if out["first_touch"] < 0:
				out["first_touch"] = i
			out["last_touch"] = i
			out["top_speed"] = maxf(out["top_speed"], b.velocity.length())
		if i % 30 == 0:
			out["trace"] += "%d:%d/%d/%.1f " % [i, n, brain.run.phase, b.velocity.length()]
		out["secs"] = float(i + 1) / 60.0
		if _count("torpedo_runs_ai_commit") > commits0 or brain.skip_id != 0:
			break
	out["phase"] = brain.run.phase
	out["commit"] = _count("torpedo_runs_ai_commit") - commits0
	out["declined"] = _count("torpedo_runs_ai_declined_touch") - declined0
	out["gave_up"] = brain.skip_id == target.get_instance_id() and brain.target == null and brain.lock_target == null
	# Let go of the button and clear the scene for the next check.
	b.controls.fire = false
	world.asteroids.destroy(rock_i)
	_put(b)
	_put(target)
	return out


## touch: a computer Bomber that rests against a rock in its launch window, with
## a target that stands still, may not wait there for good: it starts a run (once
## it is clear) or gives the target up within about 3 seconds, and counts the
## give-up once. A rock that goes away after 2 seconds costs nothing.
func _check_touch_wait() -> void:
	var rest: Dictionary = await _touch_run(1.0, 0.0, -1.0, 6.0)
	print("run_check: touch, a Bomber at rest with a rock pressed against it: touched in %d of %d ticks (first %d, last %d, top speed %.2f), phase %d, run started %d, given up %s after %.2f s; trace tick:touches/phase/speed %s" % [rest["touch_ticks"], int(rest["secs"] * 60.0), rest["first_touch"], rest["last_touch"], rest["top_speed"], rest["phase"], rest["commit"], rest["gave_up"], rest["secs"], rest["trace"]])
	_expect(rest["touch_ticks"] >= 60, "touch: the Bomber touched the rock in only %d ticks, the case does not test the touch (%s)" % [rest["touch_ticks"], rest])
	_expect(rest["commit"] == 1 or rest["gave_up"], "touch: a Bomber that rests against a rock neither started a run nor gave the target up in %.1f s (%s)" % [rest["secs"], rest])
	_expect(rest["secs"] <= 4.0, "touch: the Bomber took %.1f s to start a run or give the target up, wanted about 3 at most (%s)" % [rest["secs"], rest])
	_expect(not rest["gave_up"] or rest["declined"] == 1, "touch: the give-up was not counted once (%s)" % [rest])
	var gone: Dictionary = await _touch_run(1.0, 0.0, 2.0, 6.0)
	print("run_check: touch, the rock goes away after 2 s: touched in %d ticks (last %d), run started %d after %.2f s, given up %s" % [gone["touch_ticks"], gone["last_touch"], gone["commit"], gone["secs"], gone["gave_up"]])
	_expect(gone["commit"] == 1 and not gone["gave_up"], "touch: a rock that went away after 2 s still cost the target (%s)" % [gone])


## One tick of an AI-brained ship `b` in the frozen match: the brain steers, the
## ship and the rounds in flight step.
func _ai_tick(b: Ship, brain: PilotAI) -> void:
	world.time += DT
	brain.combat.steer(b)
	b.sim_update(DT)
	world.projectiles.tick(DT)


## A Bomber with a computer pilot that has started its run on a Destroyer that
## stands still 1200 units off, in the middle of the launch window, and has held
## it for `hold` more ticks. Returns {b, target, brain}.
func _bomber_in_run(hold: int) -> Dictionary:
	_settle()
	var target := _launch("destroyer", 1, _home + Vector2(1200.0, 0.0))
	var b := _launch("bomber", 0, _home)
	var brain := PilotAI.new(world, b.profile)
	brain.skill = 1.0
	brain._reset_after_launch()
	brain.target = target
	brain.run._pick_launch(target)
	var reach := b.run_mount.reach * b.range_mult
	b.global_position = target.global_position - Vector2(target.hit_radius() + reach * brain.run._launch_frac, 0.0)
	b.rotation = 0.0
	b.velocity = Vector2.ZERO
	world.registry.rebuild_hashes()
	var commits0 := _count("torpedo_runs_ai_commit")
	for _i in 600:
		_ai_tick(b, brain)
		if _count("torpedo_runs_ai_commit") > commits0:
			break
	for _i in hold:
		_ai_tick(b, brain)
	return {"b": b, "target": target, "brain": brain}


## How many cancel inputs the computer pilots' reasons add up to (the reasons of
## the cancel input; "dropped", a rock's cancel, is no cancel input).
func _reason_sum() -> int:
	var n := 0
	for r: String in ["off_line", "blocked", "target", "stalled", "stopped", "lost", "hidden", "other"]:
		n += _count("torpedo_runs_ai_cancel_" + r)
	return n


## Cancel an AI Bomber's run in the way `why` names, step until the run is over,
## and return how the counters moved: {ran, over, input, sum, why, total,
## dropped}: a run was on, it ended, the cancel inputs RunGun saw, the reasons'
## sum, the counter of `why`, all AI cancels, and the "dropped" count.
func _settle_case(why: String) -> Dictionary:
	var s := _bomber_in_run(20)
	var b: Ship = s["b"]
	var target: Unit = s["target"]
	var brain: PilotAI = s["brain"]
	var out := {"ran": b.run_on()}
	var input0 := _count("torpedo_runs_cancel_input")
	var sum0 := _reason_sum()
	var why0 := _count("torpedo_runs_ai_cancel_" + why)
	var total0 := _count("torpedo_runs_ai_cancelled")
	var dropped0 := _count("torpedo_runs_ai_cancel_dropped")
	var rock_i := -1
	match why:
		"lost":
			# The target died or was removed.
			brain.target = null
		"stopped":
			# The brain goes home (a short way off here) with its target alive.
			brain.state = "home"
			brain.goal = b.global_position - Vector2(800.0, 0.0)
		"off_line":
			# The target left the line: the pilot cancels the run itself.
			target.global_position += Vector2(0.0, 600.0)
			world.registry.rebuild_hashes()
		"hidden":
			# A rock hides the target on the thin line, noticed by the hidden-target look at
			# once; the pilot's own look is five ticks away.
			while brain.run._ticks % 6 != 0:
				_ai_tick(b, brain)
			var mid := (b.global_position + target.global_position) * 0.5
			world.asteroids._add(mid, 40.0, false, Mulberry.new(1))
			world.asteroids.queries.make_room(world.asteroids.pos.size())
			rock_i = world.asteroids.pos.size() - 1
			brain.flight._hid_t = 1
	for _i in 12:
		_ai_tick(b, brain)
		if not b.run_on():
			break
	out["over"] = not b.run_on()
	# Two more ticks: the pilot looks at the run once more (a run settle() ended is not counted twice).
	for _i in 3:
		_ai_tick(b, brain)
	out["input"] = _count("torpedo_runs_cancel_input") - input0
	out["sum"] = _reason_sum() - sum0
	out["why"] = _count("torpedo_runs_ai_cancel_" + why) - why0
	out["total"] = _count("torpedo_runs_ai_cancelled") - total0
	out["dropped"] = _count("torpedo_runs_ai_cancel_dropped") - dropped0
	if rock_i >= 0:
		world.asteroids.destroy(rock_i)
	b.controls.fire = false
	_put(b)
	_put(target)
	return out


## settle: every run a computer pilot ends with the cancel input has exactly one
## reason, whether the pilot's own check (off_line) or settle() (lost, stopped,
## hidden) ended it, so the reasons add up to the cancel inputs RunGun saw, and
## the total of AI cancels moves by one.
func _check_settle_reasons() -> void:
	for why: String in ["lost", "stopped", "off_line", "hidden"]:
		var r := _settle_case(why)
		print("run_check: settle, cancel by %s: %s" % [why, r])
		_expect(r["ran"] and r["over"], "settle: %s: the run was not on before or did not end (%s)" % [why, r])
		_expect(r["input"] == 1, "settle: %s: RunGun saw %d cancel inputs, wanted 1 (%s)" % [why, r["input"], r])
		_expect(r["why"] == 1 and r["sum"] == 1, "settle: %s: the reasons moved by %d (this one by %d), wanted 1 (%s)" % [why, r["sum"], r["why"], r])
		_expect(r["total"] == 1 and r["dropped"] == 0, "settle: %s: the AI cancels moved by %d with %d dropped, wanted 1 and 0 (%s)" % [why, r["total"], r["dropped"], r])


## ai rules: the fan score a computer pilot needs (180 points against big
## targets, 90 against small ones) and its nearest launch distance.
func _check_ai_rules() -> void:
	var b := _launch("bomber", 0, _home)
	var d := _launch("destroyer", 1, _home + Vector2(4000.0, 0.0))
	var f := _launch("fighter", 1, _home + Vector2(4000.0, 800.0))
	_expect(PilotRunFan.need(d) == 180 and PilotRunFan.need(f) == 90, "ai rules: the fan needed is %d against a Destroyer and %d against a Fighter, wanted 180 and 90" % [PilotRunFan.need(d), PilotRunFan.need(f)])
	var ms := world.mothership(1)
	if ms != null:
		_expect(PilotRunFan.need(ms) == 180, "ai rules: the fan needed against a mothership is %d, wanted 180" % PilotRunFan.need(ms))
	# The nearest launch is at least the arming distance plus the target's size plus 60.
	var hs := d.hit_radius()
	_expect(absf(PilotRunFan.near_edge(b.run_mount, hs, 0.0) - (200.0 + hs + 60.0)) < 0.01, "ai rules: the nearest launch from a Destroyer is %s, wanted %s" % [PilotRunFan.near_edge(b.run_mount, hs, 0.0), 200.0 + hs + 60.0])
	_expect(PilotRunFan.near_edge(b.run_mount, hs, 1000.0) == 1000.0, "ai rules: a pilot's own farther share was cut")
	_put(b)
	_put(d)
	_put(f)
