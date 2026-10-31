class_name PilotRun
extends RefCounted
## WHAT THIS IS: how an AI pilot flies a Bomber's torpedo runs (a part of
## PilotAI, one per brain). A run is the Bomber's way to shoot: hold fire for
## the wind-up (1.5 s) with the heading locked, then let go to launch a fan of
## three torpedoes (see RunGun and Ship.run_locked()). The pilot has to pick the
## moment well, because for 1.5 s or more it cannot steer, and the fan is only
## tight after the pilot has flown straight (RunFan; PilotRunFan has the rules
## for it).
##
## HOW IT WORKS: PilotCombat.fight() hands the Bomber's whole attack to fly(),
## every tick, with the target it chose. The part is in one of three phases:
##   IDLE    getting ready. The pilot picks a launch distance for this target
##           (a share of the torpedo's reach; the big ones from a long way, the
##           small ones closer, never closer than the arming distance plus the
##           target's size plus 60 units), flies to it, brakes, and turns the
##           nose to the lead point of the LAUNCH moment: where the target will
##           be when the wind-up is over and the torpedo arrives, worked out
##           with the ship's own coasting included. It then steers no more and
##           does not boost, so the fan closes. When all of this holds it commits:
##             - the fan is tight enough (PilotRunFan.need(): 180 points
##               against medium and bigger ships, structures and motherships, 90
##               against small ships; the wait is at most 1.5 s);
##             - the middle torpedo's predicted miss is under 60% of the
##               target's size (the outer torpedoes are a bonus, not aimed);
##             - the pilot is nearly still sideways (under 30 units a second);
##             - no rock lies on the line to the target (as wide as the torpedo).
##               A rock that stays on it for BLOCKED_SECS while the pilot waits
##               in the window makes the pilot give that target up for a while
##               instead of hovering there for good: a rock can block the
##               torpedo's width without blocking the thin line PilotCombat's
##               hidden-target rule looks along, and a target that stands still
##               never leaves the rock's shadow by itself;
##             - the battery can pay the torpedo;
##             - the ship is not touching a rock, a structure or a wall (that
##               would end the run at once: RunGun.cancel()). A ship that rests
##               against one for TOUCH_SECS while the pilot waits in the window
##               gives that target up for a while too, because nothing in the
##               window moves it off (the pilot holds still);
##             - a moving target (not a structure or mothership) has been
##               flying steadily for half a second (no sharp turns lately);
##             - it is not a run into heavy point-defense cover with a low hull
##               (hull under half and two or more point-defense guns near the
##               target): the pilot gives that target up for 8 seconds instead.
##   COMMIT  the fire button is held until the bar is full. Every 6 ticks the
##           pilot works out the miss again with what is left of the wait and
##           cancels (the cancel input, a free cancel: no torpedoes, no
##           waiting) when the target left the line, when a rock now blocks it,
##           or when the target was changed or lost. Once the bar is full it
##           lets go of the button on the first tick the fan is still at least
##           as tight as the commit needed, and the torpedoes launch. (If the
##           fan has opened, it keeps holding, until the wait for the release
##           runs out and the torpedoes go by themselves, unless a check cancels
##           first.) A cancelled run waits a second before the next.
##   BREAK   the torpedoes have left (the gun is reloading): the pilot turns
##           about 60 degrees off the line and burns for 1.2 seconds, which
##           covers the reload, then gets ready again.
## A friendly ship in the way does not matter: a torpedo only ever hits
## enemies (ProjectilesHitScan). An enemy in the way takes the torpedo and is
## hurt by it, so only rocks count as a blocked line.
## Every start, cancel (with its reason) and launch is counted in Game.usage
## (torpedo_runs_ai_*, also per kind of target: small, medium, big, structure
## or ms), which the Bomber probe prints. Every run that is cancelled with the
## cancel input has exactly one reason, the pilot's own (off_line, blocked,
## target, stalled) or what settle() sees (stopped, lost, hidden, other), so the
## reasons add up to RunGun's torpedo_runs_cancel_input. A run a rock ended is
## counted as "dropped" (it is no cancel input).
##
## WHO USES IT: PilotAI makes one (brain.run); PilotCombat.fight() calls fly()
## for a Bomber, abandon() when the brain stops fighting, settle() at the end
## of every tick, and PilotAI calls reset() for a fresh ship. Nothing else.

## Phase: getting ready (see HOW IT WORKS).
const IDLE := 0
## Phase: the fire button is held for the wind-up and until the pilot lets go.
const COMMIT := 1
## Phase: the torpedoes have left and the pilot turns off the line.
const BREAK := 2
## How long the BREAK phase lasts, in seconds.
const BREAK_SECS := 1.2
## Seconds to wait after a cancelled run before committing again.
const COOL_SECS := 1.0
## Seconds a target is ignored after the pilot refused a run into point-defense
## cover.
const COVER_SKIP_SECS := 8.0
## Seconds the line to the target may stay blocked by a rock while the pilot
## waits in the launch window before the target is given up.
const BLOCKED_SECS := 3.0
## Seconds a target is ignored after its line stayed blocked for BLOCKED_SECS
## (or the ship stayed touching something for TOUCH_SECS).
const BLOCKED_SKIP_SECS := 6.0
## Seconds the ship may stay in contact with something solid (a rock, a structure
## or a wall) while the pilot waits in the launch window before the target is
## given up.
const TOUCH_SECS := 3.0
## The commit check: the predicted miss, as a share of the target's size.
const COMMIT_MISS := 0.6
## The cancel check: the predicted miss, as a share of the target's size, plus
## CANCEL_PAD world units. Wider than the commit check so a run does not flip
## between the two on a hair.
const CANCEL_MISS := 1.1
## World units added to the cancel check's width.
const CANCEL_PAD := 8.0
## Quarter-second looks in a row a moving target must have flown steadily
## before a run may start on it (structures and motherships need none).
const STEADY_LOOKS := 2
## A target slower than this (world units a second) counts as steady without
## any looks.
const SLOW_SPEED := 60.0
## Largest sideways speed (world units a second) at which a run may start.
const MAX_SIDEWAYS := 30.0
## The torpedo's own radius, in world units, added to the target's size in the
## miss checks (the weapon's "radius").
const TORP_RADIUS := 6.0
## The hull share under which a pilot will not start a run into heavy cover.
const LOW_HULL := 0.5
## Point-defense guns near the target at which the cover counts as heavy.
const HEAVY_COVER := 2
## How near the target (world units) a gun counts as cover.
const COVER_RADIUS := 800.0
## Ticks between two looks at a running wind-up (the miss and the rocks).
const CHECK_EVERY := 6
## Extra ticks past the longest a run can last (the wind-up plus the wait for the
## release) that the pilot waits for the torpedoes to leave (no energy, say)
## before it cancels.
const STALL_TICKS := 30
## The launch distance as a share of the torpedo's reach, for big targets
## (medium and up, turrets, motherships): the lowest share.
const BIG_FRAC := 0.62
## How much more than BIG_FRAC a big target's share may be (a random pick
## between the two).
const BIG_SPREAD := 0.18
## The lowest launch share for small targets.
const SMALL_FRAC := 0.40
## How much more than SMALL_FRAC a small target's share may be.
const SMALL_SPREAD := 0.15
## How much either side of the chosen launch distance a run may start, as a
## share of the reach.
const WINDOW := 0.07

## The pilot brain this part belongs to. It is reached through a weak link:
## see `_ai_ref`.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain (the brain holds this part strongly, so a strong
## link back would keep both alive forever).
var _ai_ref: WeakRef

## What the pilot is doing: IDLE, COMMIT or BREAK.
var phase := IDLE
## Ticks the current run has been held.
var _ticks := 0
## The target the current run was started on.
var _target: Unit = null
## What kind of target that was (RunFan.class_word()), for the usage counters.
var _word := "small"
## The tightness score the run was committed at (PilotRunFan.need()): the pilot
## lets go once the bar is full and the score is still at least this.
var _need := PilotRunFan.NEED_BIG
## Seconds left of the BREAK phase.
var _break_t := 0.0
## Seconds left of the wait after a cancelled run.
var _cool_t := 0.0
## The chosen launch distance, as a share of the torpedo's reach.
var _launch_frac := 0.7
## The instance id of the target `_launch_frac` was chosen for (0 = none).
var _frac_for := 0
## Seconds the line to the target has been found blocked by a rock, counted
## while the pilot waits in the launch window (it restarts from 0 when the line
## is clear, the pilot leaves the window or the target changes).
var _blocked_t := 0.0
## Seconds the ship's last moves have touched something solid in a row, counted
## while the pilot waits in the launch window (it restarts from 0 on the first
## tick without a touch, when the pilot leaves the window, and when the target
## changes or is given up).
var _touch_t := 0.0
## The unit direction the nose should have for the launch moment's lead point
## (set by _solve()).
var _dir := Vector2.RIGHT
## The predicted miss, in world units, of a torpedo launched along the nose at
## the end of the wind-up (set by _solve()).
var _miss := 0.0
## The target's velocity at the last steadiness look.
var _tv_prev := Vector2.ZERO
## Seconds since that look.
var _tv_t := 0.0
## How many quarter-second looks in a row the target has been flying steadily
## (its velocity changed little since the look before). A new target starts
## at 0.
var _steady_n := 0
## A reusable list for the spatial hash search of point-defense cover.
var _scratch: Array = []
## True for the tick the pilot lets go of the fire button on purpose, to launch
## (_hold() sets it, settle() reads it).
var _launching := false
## True for the tick _cancel() ended a run (settle() reads it, so the run is
## counted once).
var _cancelled_now := false
## True after settle() cancelled a run that the pilot still held as its own (the
## fight let go of the button, so COMMIT stays until the pilot's next look). The
## next _cancel() then finds the run gone and does not count it again.
var _settled := false


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## A fresh ship starts with nothing going on.
func reset() -> void:
	phase = IDLE
	_ticks = 0
	_target = null
	_break_t = 0.0
	_cool_t = 0.0
	_frac_for = 0
	_blocked_t = 0.0
	_touch_t = 0.0
	_settled = false


## The brain stopped fighting (it went home, retreats, or lost its target):
## drop any run. The fire button is let go by PilotCombat anyway; this only
## forgets the phase.
func abandon() -> void:
	phase = IDLE
	_ticks = 0
	_target = null
	_break_t = 0.0
	_blocked_t = 0.0
	_touch_t = 0.0
	_settled = false


## The end of a tick's steering (PilotCombat.steer() calls it for a Bomber): a run
## that is on while the pilot has let go of the fire button for any reason but
## launching (the target was lost, the brain went home, a cancel check failed) is
## cancelled with the cancel input, because letting go with the bar full would
## launch it. A run that _cancel() ended this tick has its reason already; any
## other is counted here with the reason settle() can tell (see _count_settled()).
func settle(ship: Ship) -> void:
	var c := ship.controls
	if ship.run_on() and not c.fire and not _launching:
		c.cancel_run = true
		if not _cancelled_now:
			_count_settled()
	_launching = false
	_cancelled_now = false


## Count the cancel of a run that settle() ends, with the reason it can tell from
## the pilot's state: "lost" (abandon() let the run go and the brain has no
## target: it died or was removed), "stopped" (abandon() let it go with a target
## still alive: the brain went home, retreats, falls back or the target is far),
## "hidden" (the fight let go of the fire button because a rock hides the
## target), else "other".
func _count_settled() -> void:
	var why := "other"
	if phase == IDLE:
		why = "lost" if ai.target == null else "stopped"
	elif phase == COMMIT:
		why = "hidden"
		# The pilot still holds the run as its own: its next look finds the run gone
		# and must not count it a second time (_cancel("dropped")).
		_settled = true
	_count_cancel(why)


## Fly the Bomber's attack on `target` for one tick (see HOW IT WORKS).
## `tp` is where the target is (for a mothership the closest point on its
## spine), `d` the distance to it and `reach` the torpedo's reach in world
## units. It fills in the ship's controls.
func fly(ship: Ship, target: Unit, tp: Vector2, d: float, reach: float) -> void:
	_cool_t = maxf(0.0, _cool_t - 1.0 / 60.0)
	_look_at_target(target)
	if phase == COMMIT and _hold(ship, target, tp):
		return
	if phase == BREAK and _break_off(ship, tp):
		return
	_get_ready(ship, target, tp, d, reach)


## Note whether the target is flying steadily: every quarter second, its
## velocity must not have changed much since the last look. A new target
## starts as not steady.
func _look_at_target(target: Unit) -> void:
	var id := target.get_instance_id()
	if id != _frac_for:
		_tv_prev = target.velocity
		_tv_t = 0.0
		_steady_n = 0
		return
	_tv_t += 1.0 / 60.0
	if _tv_t >= 0.25:
		_tv_t = 0.0
		var steady := (target.velocity - _tv_prev).length() < 30.0 + 0.15 * target.velocity.length()
		_steady_n = _steady_n + 1 if steady else 0
		_tv_prev = target.velocity


## The size of `target` for the miss checks, in world units: the half width
## of a mothership's hull, else the hit size (Unit.hit_radius()).
func _hit_size(target: Unit) -> float:
	if target is Mothership:
		return (target as Mothership).beam * 0.5
	return target.hit_radius()


## Choose the launch distance for `target`, once for each new target: a long
## way off for the big ones, closer for the small ones.
func _pick_launch(target: Unit) -> void:
	_frac_for = target.get_instance_id()
	_blocked_t = 0.0
	_touch_t = 0.0
	if target.size_class >= Rules.SIZE_MEDIUM or target.is_structure():
		_launch_frac = BIG_FRAC + BIG_SPREAD * randf()
	else:
		_launch_frac = SMALL_FRAC + SMALL_SPREAD * randf()


## Work out, for a torpedo launched `wind_left` ticks from now: the nose
## direction that would hit (`_dir`) and, for the nose as it points now, how
## far the torpedo would pass from the target at its closest (`_miss`). The
## ship is taken to coast on its present velocity until the launch, and the
## target to fly on its own.
func _solve(ship: Ship, target: Unit, tp: Vector2, wind_left: int) -> void:
	var m := ship.run_mount
	var speed := float(m.def["speed"])
	var life := float(m.def["life"]) * ship.range_mult
	var tw := float(wind_left) / 60.0
	var tv := target.velocity
	# Where the target and the ship will be at the launch.
	var p_l := tp + tv * tw
	var s_l := ship.global_position + ship.velocity * tw
	var lead := Util.lead_point(s_l, ship.velocity * 0.35, p_l, tv, speed)
	var to_lead := lead - s_l
	_dir = to_lead.normalized() if to_lead.length_squared() > 1.0 else Vector2.from_angle(ship.rotation)
	# The torpedo leaves the gun along the nose with a third of the ship's own
	# speed added; the closest approach of the two straight tracks.
	var nose := Vector2.from_angle(ship.rotation)
	var w := nose * speed + ship.velocity * 0.35
	var rel0 := p_l - (s_l + nose * m.offset.x)
	var relv := tv - w
	var t_best := clampf(-rel0.dot(relv) / maxf(relv.length_squared(), 1.0), 0.0, life)
	_miss = (rel0 + relv * t_best).length()


## Is the line from the gun to `tp` free of rocks, up to the target's edge?
func _line_clear(ship: Ship, tp: Vector2, hs: float) -> bool:
	var from := ship.run_mount.world_pos()
	var line := tp - from
	var len := line.length()
	if len < 1.0:
		return true
	var to := from + line / len * maxf(0.0, len - hs)
	return ai.world.asteroids.segment_hit(from, to, TORP_RADIUS).is_empty()


## How many point-defense guns stand near `tp` on the other side: the guns of
## enemy ships, turrets and repair bays within COVER_RADIUS, one per unit,
## and two for an enemy mothership whose hull is that near.
func _pd_cover(ship: Ship, tp: Vector2) -> int:
	var world := ai.world
	var n := 0
	for u: Unit in world.unit_hash.query(tp, COVER_RADIUS, _scratch):
		if not u.alive or u.team == ship.team or u.team == Rules.NEUTRAL:
			continue
		var mounts = u.get("mounts")
		if mounts == null:
			continue
		for gm: WeaponMount in mounts:
			if str(gm.def.get("prefer", "")) == "torp_small":
				n += 1
				break
	var ems := world.mothership(1 - ship.team)
	if ems != null and ems.alive and ems.hull_dist(tp) < COVER_RADIUS:
		n += 2
	return n


## IDLE: fly to the launch distance, brake, line the nose up, and commit when
## everything holds (see HOW IT WORKS).
func _get_ready(ship: Ship, target: Unit, tp: Vector2, d: float, reach: float) -> void:
	var brain := ai
	var c := ship.controls
	var m := ship.run_mount
	var hs := _hit_size(target)
	if _frac_for != target.get_instance_id():
		_pick_launch(target)
	var near := PilotRunFan.near_edge(m, hs, hs + reach * (_launch_frac - WINDOW))
	var far := hs + reach * (_launch_frac + WINDOW)
	# The blocked-line and touch counts (step 3) run only while we wait in the window.
	if d < near or d > far:
		_blocked_t = 0.0
		_touch_t = 0.0
	# Step 1: turn the nose to where the launch's lead point will be. Weaker
	# pilots aim a little off, swinging slowly back and forth (as in
	# PilotCombat.fight()).
	_solve(ship, target, tp, m.run.wind_ticks + 1)
	var err := (1.0 - brain.skill) * 0.12 * sin(brain.world.time * 1.3 + float(brain.profile.slot))
	var want := _dir.rotated(err)
	c.face_point = ship.global_position + want * 1000.0
	c.strafe = 0.0
	var ang_err := absf(Util.ang_diff(ship.rotation, want.angle()))
	# Step 2: where to be. Too close to turn away safely: burn straight out
	# past it. Too near: back off. Too far: close in. In the window: stop.
	if d < hs + 380.0:
		c.face_point = ship.global_position + (ship.global_position - tp).rotated(brain.orbit * 0.6) * 2.0
		c.forward = 1.0
		return
	if d < near:
		c.forward = -1.0
		return
	if d > far:
		c.forward = 1.0 if ang_err < 0.4 else 0.2
		return
	var closing := ship.velocity.dot((tp - ship.global_position).normalized())
	c.forward = -0.6 if closing > 40.0 else (0.3 if closing < -40.0 else 0.0)
	# Step 3: in the window: count how long the ship has been touching something
	# solid, and give the target up when it will not come clear (the pilot holds
	# still here, so a ship resting against a rock would wait for good).
	var touching := ship.get_slide_collision_count() > 0
	_touch_t = _touch_t + 1.0 / 60.0 if touching else 0.0
	if _touch_t > TOUCH_SECS:
		_give_up(brain, target, BLOCKED_SKIP_SECS)
		Game.count_usage("torpedo_runs_ai_declined_touch")
		return
	# Then commit if all the conditions hold.
	if _cool_t > 0.0 or m.run.reload > 0 or ship.energy.value < float(m.def.get("energy", 0.0)) * 1.2:
		return
	# A ship that is touching something solid would see its run end on the same
	# tick (ShipFlight.move() cancels it): wait until it is clear.
	if touching:
		return
	if d > reach + hs - 60.0:
		return
	if not target.is_structure() and _steady_n < STEADY_LOOKS and target.velocity.length() > SLOW_SPEED:
		return
	var nose := Vector2.from_angle(ship.rotation)
	if absf(ship.velocity.cross(nose)) > MAX_SIDEWAYS:
		return
	if _miss > COMMIT_MISS * (hs + TORP_RADIUS):
		return
	if not _line_clear(ship, tp, hs):
		# A blocked line is not a reason to wait for good: a rock inside the
		# torpedo's width but off the thin line the hidden-target rule tests
		# never goes away against a target that stands still.
		_blocked_t += 1.0 / 60.0
		if _blocked_t > BLOCKED_SECS:
			_give_up(brain, target, BLOCKED_SKIP_SECS)
			Game.count_usage("torpedo_runs_ai_declined_blocked")
		return
	_blocked_t = 0.0
	# A low hull stays out of heavy point-defense cover: give the target up.
	if ship.hull_frac() < LOW_HULL and _pd_cover(ship, tp) >= HEAVY_COVER:
		_give_up(brain, target, COVER_SKIP_SECS)
		Game.count_usage("torpedo_runs_ai_declined_cover")
		return
	# The fan must be tight enough: hold the course (no steering, no boost) until
	# it is. The nose already points at the lead point, so the score only grows.
	if ship.fan_points < PilotRunFan.need(target):
		return
	# Commit: hold fire from this tick. The focus shot (+45%) goes with a run
	# on a medium or bigger target.
	phase = COMMIT
	_ticks = 0
	_settled = false
	_target = target
	_word = RunFan.class_word(target)
	_need = PilotRunFan.need(target)
	c.fire = true
	c.special = ship.special_ready() and (target.size_class >= Rules.SIZE_MEDIUM or target.is_structure())
	Game.count_usage("torpedo_runs_ai_commit")
	Game.count_usage("torpedo_runs_ai_commit_" + _word)


## Give `target` up for `secs` seconds: the brain stops aiming at it (it picks
## another target, or goes back to its station) and ignores it until the time
## is up (PilotAI.skip_id and skip_until, as PilotCombat's hidden-target rule
## does).
func _give_up(brain: PilotAI, target: Unit, secs: float) -> void:
	brain.skip_id = target.get_instance_id()
	brain.skip_until = brain.world.time + secs
	brain.target = null
	brain.lock_target = null
	_blocked_t = 0.0
	_touch_t = 0.0


## COMMIT: keep holding fire; every few ticks check the run is still good.
## Returns true when it handled this tick (the run goes on, or the torpedo has
## left and the BREAK phase took over), false when it let go.
func _hold(ship: Ship, target: Unit, tp: Vector2) -> bool:
	var c := ship.controls
	var m := ship.run_mount
	_ticks += 1
	# The torpedoes have left (the gun is reloading): break off.
	if m.run.reload > 0:
		phase = BREAK
		_break_t = BREAK_SECS
		Game.count_usage("torpedo_runs_ai_launched")
		Game.count_usage("torpedo_runs_ai_launched_" + _word)
		return _break_off(ship, tp)
	# The run ended without a launch (a rock touched the ship, say).
	if not m.run.on and _ticks > 2:
		return _cancel("dropped")
	if target != _target:
		return _cancel("target")
	if _ticks > m.run.wind_ticks + m.run.ready_ticks + STALL_TICKS:
		return _cancel("stalled")
	# Look at the run again every few ticks.
	if _ticks % CHECK_EVERY == 0:
		var hs := _hit_size(target)
		_solve(ship, target, tp, maxi(0, m.run.wind_ticks - m.run.wind) + 1)
		if _miss > CANCEL_MISS * (hs + TORP_RADIUS) + CANCEL_PAD:
			return _cancel("off_line")
		if not _line_clear(ship, tp, hs):
			return _cancel("blocked")
	# Hold fire until the bar is full, then let go while the fan is still at least
	# as tight as the commit needed: a release with the bar full launches. If the
	# fan has opened since, the pilot keeps holding (the run launches by itself
	# when the wait for the release runs out). The heading is locked by the flight
	# (the face point does not matter), the throttle stays where it is.
	if m.run.is_full() and ship.fan_points >= _need:
		_launching = true
		c.fire = false
	else:
		c.fire = true
	c.face_point = ship.global_position + Vector2.from_angle(ship.rotation) * 600.0
	c.strafe = 0.0
	c.forward = 0.0
	return true


## Count one cancelled run with its `reason`, in total and per kind of target.
func _count_cancel(reason: String) -> void:
	Game.count_usage("torpedo_runs_ai_cancelled")
	Game.count_usage("torpedo_runs_ai_cancel_" + reason)
	Game.count_usage("torpedo_runs_ai_cancel_%s_%s" % [reason, _word])


## Let go of the run: no torpedo, no waiting (a free cancel). Counts the
## reason (unless settle() counted this run already) and waits COOL_SECS before
## the next. Returns false.
func _cancel(reason: String) -> bool:
	if _settled:
		_settled = false
	else:
		_count_cancel(reason)
	_cancelled_now = true
	phase = IDLE
	_ticks = 0
	_target = null
	_cool_t = COOL_SECS
	return false


## BREAK: turn about 60 degrees off the line to the target and burn. Returns
## true while it is in charge, false once the BREAK_SECS are over.
func _break_off(ship: Ship, tp: Vector2) -> bool:
	var c := ship.controls
	_break_t -= 1.0 / 60.0
	if _break_t <= 0.0:
		phase = IDLE
		_target = null
		return false
	c.fire = false
	var away := (ship.global_position - tp).normalized()
	c.face_point = ship.global_position + away.rotated(ai.orbit * 1.05) * 800.0
	c.forward = 1.0
	c.strafe = 0.0
	return true
