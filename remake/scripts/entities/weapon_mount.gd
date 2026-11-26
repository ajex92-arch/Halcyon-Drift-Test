class_name WeaponMount
extends RefCounted
## WHAT THIS IS: one gun bolted onto a unit (a pilot ship, minion, turret,
## mothership, repair bay, derelict or snub fighter), together with where it
## sits, which way it points and how soon it can fire again.
##
## HOW IT WORKS: a gun is mounted in one of three ways:
##   FIXED   fires straight along the hull's nose. Strike craft aim by
##           turning the whole ship. A FIXED gun whose weapon has a "windup"
##           (the Bomber's torpedo) does not fire on the trigger: it makes a
##           "torpedo run" (hold the trigger, wait, let go to launch, reload),
##           which its RunGun part keeps (run_gun.gd).
##   TURRET  swings toward the owner's aim point, but only within its `arc`.
##           Big ships use these: the pilot aims a reticle while the hull
##           faces wherever positioning demands. A TURRET that is part of a ship of
##           the line's broadside battery (`battery`) follows the reticle only while
##           the reticle is inside its arc; with the reticle off its side it works on
##           its own like an AUTO gun (_auto_step), a Broadside charge can hold it
##           (`hold`), its shots leave with a small fixed spread (shot_offset()) and,
##           like every turret of such a ship, it swings three times as fast once it
##           has been idle for 2 s (`idle_boost`).
##   AUTO    picks its own targets (flak and point defense). This is what
##           lets a well-positioned big ship keep firing at whatever comes
##           at it (and shred small craft, while the damage modifiers are
##           kept).
##           The target picking lives in WeaponMountTargeting
##           (weapon_mount_targeting.gd).
## Every tick (one small step of the game, 60 per second) the owner calls
## update() with its aim point, its trigger and its multipliers. The gun
## turns, waits for its cooldown (`cd`), pays for the shot from the owner's
## battery (EnergyPool), and fires:
##   - Projectile guns spawn rounds through world.projectiles (_shoot).
##   - Beams deal a little damage every tick through world.combat.beam()
##     (_update_beam). "Burst" beams (the ion cannon) fire in fixed bursts.
## Minions, turrets and monsters reuse this class with a null EnergyPool,
## so their shots are free.
## Every shot and every tick of a beam also tells Vision (note_shot), because a
## unit that fires from inside a cover patch is seen by everyone for 2 seconds.
##
## Angles are in radians: a full turn is TAU (2 * PI, about 6.28), so one
## radian is about 57 degrees.
##
## WHO USES IT: Ship (from its hull's "mounts" list and from modules that
## add a gun), World (when a refit adds a module gun), Minion, Turret,
## Mothership, RepairBay, Derelict and SnubFighter create mounts and call
## update(). AI pilots read reach and mount_type; Turret reads cd and def;
## UnitVisual reads world_angle() and offset; tests read the beam and
## target fields.

## Mount type: fires along the nose.
const FIXED := 0
## Mount type: swings toward the owner's aim point within its arc.
const TURRET := 1
## Mount type: picks its own targets.
const AUTO := 2
## The mount type names used in the data files ("fixed", "turret", "auto")
## turned into the numbers above.
const TYPE_IDS := {"fixed": FIXED, "turret": TURRET, "auto": AUTO}
## How far, in radians, past the edge of its swing an AUTO gun still counts a
## direction as inside it (in_swing()).
const SWING_SLACK := 0.01
## Seconds without a shot after which a ship-of-the-line turret swings faster (idle_boost).
const IDLE_TIME := 2.0
## How many times faster that idle swing is.
const IDLE_TURN_MULT := 3.0
## The battery spread: a gun of a group of n aims (i - (n-1)/2) times this fraction of its distance
## to the aim point to the side of it.
const SPREAD_STEP := 0.012
## The shortest distance the spread is worked from, in world units (a close aim point cannot
## blow the angle up).
const SPREAD_MIN_DIST := 100.0

## The unit this gun is bolted to.
var owner: Unit
## Which weapon this is: its id in Weapons (e.g. "fighter_cannon").
var weapon_id := ""
## The gun's name on its hull, from the hull's row in Ships (e.g. "pd_fore_port"), unique
## inside the hull. "" for a gun with none: a hull row that names no guns, or a gun a
## module or a structure adds.
var id := ""
## True for a gun of the broadside battery: a heavy cannon or an ion turret on the beam
## of a ship of the line (the hull row's "battery" key; Ship.setup() sets it). false for
## every other gun.
var battery := false
## Battery guns of one weapon on one side of the ship, counted in the row order: this gun's
## place in its group (0 for the first) and how many guns the group has (1 for a lone gun).
## Ship.setup() sets them. The group aims a fixed spread (shot_offset()).
var battery_i := 0
## The size of the gun's battery group (see battery_i).
var battery_n := 1
## True while the owner holds this battery gun back (a Broadside charge on its side): it
## follows the reticle but never takes the self-aiming path. The owner sets it each tick.
var hold := false
## Seconds since this gun last fired (a burst beam: since its burst began). Counted in update()
## for a gun with idle_boost only.
var idle_t := 0.0
## True for a turret of a ship of the line (the hull row's "side_battery"): after IDLE_TIME
## seconds without a shot it swings IDLE_TURN_MULT times as fast until its next shot. Ship.setup()
## sets it.
var idle_boost := false
## The weapon's data from Weapons (damage, rate, speed, energy cost...).
var def: Dictionary
## The weapon kind: one of Rules.W_* (bolt, torpedo, flak...). It picks the
## damage-table row and the firing sound.
var kind := Rules.W_BOLT
## How it is mounted: FIXED, TURRET or AUTO.
var mount_type := FIXED
## Where the gun sits on the hull, in the owner's own frame (+x ahead, +y to
## the right), in world units.
var offset := Vector2.ZERO
## How far the mount can swing either side of its centre line, in radians
## (half of its full swing).
var arc := 0.0
## Which way the swing is centred, as an angle from the nose in radians: 0 =
## the nose (the usual case), PI = the tail (a rear gun, which covers the
## space behind the ship).
var face := 0.0
## Where the gun points right now, as an angle relative to the hull's
## facing, in radians (TURRET and AUTO; FIXED is always 0).
var angle := 0.0
## Seconds until the gun may fire again (0 or below = ready).
var cd := 0.0
## The weapon's normal reach, in world units (from Weapons.reach()).
var reach := 0.0
## True for beam weapons (continuous rays instead of rounds).
var is_beam := false
## Burst beams: seconds left in the current burst.
var beam_on := 0.0
## Burst beams: seconds left of the rest between bursts.
var beam_off := 0.0
## True while the beam is drawn and dealing damage this tick.
var beam_firing := false
## Where the beam ended this tick (world position): the first thing it hit,
## or its full length.
var beam_end := Vector2.ZERO
## A one-shot damage multiplier for the next shot or burst (the Bomber's
## Focus and the Ion ship's Capacitor Dump set it). Back to 1.0 once used.
var next_mult := 1.0
## Burst beams: the one-shot bonus locked in when the current burst
## started, so it lasts for the whole burst.
var burst_mult := 1.0
## Reach this tick after range multipliers, in world units (AUTO mounts
## drop targets that move past it).
var range_now := 0.0
## AUTO mounts: the unit we are shooting at, or null.
var target: Unit = null
## AUTO mounts: the enemy torpedo we are shooting at, as its slot number in
## world.projectiles, or -1 for none (point defense shoots torpedoes down).
var target_torp := -1
## AUTO mounts: seconds until we choose a target again (every 0.25 to 0.35 s).
var retarget_t := 0.0
## True while this mount has a valid target or a pulled trigger this tick
## (read by the AI and by tests).
var engaged := false
## How fast the gun swings (radians per second), from the weapon's data
## ("turn", 3.0 if missing). Read once in _init() instead of on every
## update (it runs for every gun on every tick).
var _turn_rate := 3.0
## FIXED guns with a wind-up (the Bomber's torpedo): how many ticks the
## trigger must be held before the bar is full, from the weapon's "windup"
## (seconds). 0 = no wind-up: the gun fires on the trigger. A tick is one
## small step of the game (60 a second).
var windup := 0
## The torpedo run of a gun with a wind-up (null for every other gun): the
## hold, the wait, the launch and the reload.
var run: RunGun = null
## Multiplier on the hit points of the torpedoes this gun fires (the owner
## sets it each tick from its research; 1.0 = the weapon's own torp_hp).
var torp_hp_mult := 1.0
## Set by _auto_step(): did the self-aiming work this tick want a shot? (Read by update().)
var _auto_fire := false
## Multiplier on how fast a turret or self-aiming gun swings (the owner sets it each tick from
## its sensor part: 1.0 = whole, 0.75 = hurt, 0.5 = out). 1.0 for a ship with no parts.
var slew_mult := 1.0


## Create a gun: owner `o`, weapon id `wid`, mount type name `type_name`
## ("fixed", "turret" or "auto"), position `off` on the hull, and swing
## `arc_deg` in degrees either side of the direction it faces: the nose, or
## `face_deg` degrees round from the nose (180 = the tail). The gun starts
## pointing that way.
func _init(o: Unit, wid: String, type_name: String = "fixed", off: Vector2 = Vector2.ZERO, arc_deg: float = 0.0, face_deg: float = 0.0) -> void:
	owner = o
	weapon_id = wid
	def = Weapons.get_def(wid)
	kind = Weapons.kind_id(def)
	mount_type = int(TYPE_IDS[type_name])
	offset = off
	arc = deg_to_rad(arc_deg)
	face = deg_to_rad(face_deg)
	angle = face
	reach = Weapons.reach(def)
	is_beam = bool(def.get("beam", false))
	_turn_rate = float(def.get("turn", 3.0))
	windup = int(round(float(def.get("windup", 0.0)) * 60.0))
	if windup > 0:
		run = RunGun.new(def)


## Where the gun is in the world right now (its offset turned with the hull).
func world_pos() -> Vector2:
	return owner.global_position + offset.rotated(owner.rotation)


## The direction the gun points in the world, in radians.
func world_angle() -> float:
	return owner.rotation + angle


## Per-tick update: aim, then fire if we can. `aim_point` is where the
## owner aims (used by TURRET mounts; FIXED mounts ignore it and AUTO mounts
## pick their own). `trigger` = the pilot is pressing fire. `fire_mult`
## speeds up the rate of fire, `dmg_mult` scales damage and `range_mult`
## scales reach. `energy` pays for shots (null = free shots).
func update(dt: float, aim_point: Vector2, trigger: bool, fire_mult: float, dmg_mult: float, range_mult: float, energy: EnergyPool) -> void:
	# Step 1: count down the cooldown and reset this tick's state.
	if cd > 0.0:
		cd -= dt
	engaged = false
	var turn_rate: float = _turn_rate * slew_mult
	# A ship-of-the-line turret that has not fired for IDLE_TIME seconds swings faster until
	# its next shot.
	if idle_boost:
		idle_t += dt
		if idle_t >= IDLE_TIME:
			turn_rate *= IDLE_TURN_MULT
	var want_local := 0.0
	var fire := false
	range_now = reach * range_mult
	var aim_at := aim_point

	# Step 2: aim, depending on how the gun is mounted.
	match mount_type:
		FIXED:
			# Nose gun: fires whenever the trigger is pulled. A gun with a
			# wind-up makes a run instead (RunGun): the run itself launches
			# the torpedoes, so `fire` stays false for it.
			angle = 0.0
			if run != null:
				run.tick(self, trigger, fire_mult, dmg_mult, range_mult, energy)
			else:
				fire = trigger
		TURRET:
			# Swing toward the aim point (never past the arc). Fire only if
			# the aim point is inside the arc (plus 0.05 rad of slack) and
			# the gun is already pointing within 0.3 rad of where it wants.
			var mp := world_pos()
			var desired := Util.ang_diff(owner.rotation, (aim_point - mp).angle())
			var off_centre := _off_centre(desired)
			if battery and not hold and absf(off_centre) > arc + 0.05:
				# A battery gun whose side the reticle is not on works on its own, as an
				# AUTO gun does: its own target, no trigger.
				aim_at = _auto_step(dt, turn_rate, aim_at)
				fire = _auto_fire
			else:
				# A battery projectile gun swings to its own place in the fixed spread
				# round the reticle (the arc and the firing test use the reticle itself).
				var want_off := off_centre
				if battery and not is_beam:
					want_off = _off_centre(Util.ang_diff(owner.rotation, (_spread_point(aim_point, mp) - mp).angle()))
				want_local = face + clampf(want_off, -arc, arc)
				angle = _slew(angle, want_local, turn_rate * dt)
				fire = trigger and absf(off_centre) <= arc + 0.05 and absf(Util.wrap_angle(want_local - angle)) < 0.3
		AUTO:
			aim_at = _auto_step(dt, turn_rate, aim_at)
			fire = _auto_fire

	if trigger and mount_type != AUTO:
		engaged = true

	# Step 3: beams work differently (damage every tick).
	if is_beam:
		_update_beam(dt, fire, dmg_mult * fire_mult, range_now, energy)
		return
	# Step 4: fire a round if we want to, the gun is ready and we can pay.
	if not fire or cd > 0.0:
		return
	var per_shot: float = float(def.get("energy", 0.0))
	if energy != null and per_shot > 0.0 and not energy.spend(per_shot):
		return
	# Keep the overshoot (cd is <= 0 here) so guns fire at their true rate
	# instead of rounding every interval up to whole ticks.
	cd += 1.0 / maxf(0.01, float(def["rate"]) * fire_mult)
	_shoot(dmg_mult * next_mult, range_mult, aim_at)
	next_mult = 1.0
	idle_t = 0.0


## The self-aiming work of one tick, for an AUTO gun and for a battery gun whose side the reticle
## is not on: choose a target every 0.25-0.35 s, swing toward the lead point inside the arc and
## say in `_auto_fire` whether to fire (within 0.12 rad of it). Returns the point the gun aims
## at: the lead point, or `aim_in` when there is no target. A battery gun aims at its own place
## in the fixed spread round the lead point.
func _auto_step(dt: float, turn_rate: float, aim_in: Vector2) -> Vector2:
	_auto_fire = false
	var aim_at := aim_in
	# Choose a target every 0.25-0.35 s (the random part spreads
	# the work over different ticks).
	retarget_t -= dt
	if retarget_t <= 0.0:
		retarget_t = 0.25 + randf() * 0.1
		WeaponMountTargeting.pick_target(self, range_now)
	# Aim at where the target will be. INF means "no target".
	var tp := WeaponMountTargeting.target_point(self)
	if tp.x != INF:
		aim_at = tp
		var mp := world_pos()
		var swing_to := _spread_point(tp, mp) if battery and not is_beam else tp
		var desired := Util.ang_diff(owner.rotation, (swing_to - mp).angle())
		if in_swing(desired, SWING_SLACK):
			# Inside our arc: swing and fire once within 0.12 rad.
			var want_local := desired
			angle = _slew(angle, want_local, turn_rate * dt)
			_auto_fire = absf(Util.wrap_angle(want_local - angle)) < 0.12
			engaged = true
		else:
			# Outside our arc: give the target up.
			target = null
			target_torp = -1
	return aim_at


## The sideways distance, in world units, the gun `i` of a group of `n` battery guns aims off the
## point it is to hit, when that point is `d` away (never counted under SPREAD_MIN_DIST):
## (i - (n-1)/2) x SPREAD_STEP x d. A pair gives -6 and +6 at 1,000; a lone gun 0.
static func shot_offset(i: int, n: int, d: float) -> float:
	return (float(i) - float(n - 1) * 0.5) * SPREAD_STEP * maxf(d, SPREAD_MIN_DIST)


## The point this battery gun aims at to hit `p` from `from`: `p` moved sideways, across the line
## from the gun to it, by shot_offset().
func _spread_point(p: Vector2, from: Vector2) -> Vector2:
	if battery_n < 2:
		return p
	var line := p - from
	var d := line.length()
	if d < 0.001:
		return p
	return p + (line / d).rotated(PI * 0.5) * shot_offset(battery_i, battery_n, d)


## Send the three torpedoes of one run (RunGun calls this at the launch):
## RunFan.launch(). `dmg_mult` scales the damage and `range_mult` the flight
## time.
func fire_fan(dmg_mult: float, range_mult: float) -> void:
	RunFan.launch(self, dmg_mult, range_mult)


## How far, in radians, the direction `desired` (an angle from the nose) is
## from the direction this gun's swing is centred on. For a gun that faces the
## nose that is `desired` itself.
func _off_centre(desired: float) -> float:
	return desired if face == 0.0 else Util.wrap_angle(desired - face)


## Can this gun turn to the direction `desired` (an angle from the nose)? True
## when it lies inside the gun's swing: no further from the direction the gun
## faces than `arc`, plus `slack` radians. An AUTO gun asks this about a
## target before it takes it (WeaponMountTargeting.pick_target()) and again
## every tick it aims (update()).
func in_swing(desired: float, slack: float) -> bool:
	return absf(_off_centre(desired)) <= arc + slack


## Turn angle `cur` toward angle `want` by at most `step` radians, the
## short way round. Returns the new angle.
func _slew(cur: float, want: float, step: float) -> float:
	var d := Util.wrap_angle(want - cur)
	return Util.wrap_angle(cur + clampf(d, -step, step))


## Fire one shot of rounds (one or more "pellets") from the gun. `dmg_mult`
## scales the damage, `range_mult` the flight time (so the reach). Homing
## rounds chase our AUTO target, or else the owner's homing_target().
func _shoot(dmg_mult: float, range_mult: float, aim_at: Vector2) -> void:
	var w := owner.world
	if w == null:
		return
	# A shot from inside a cover patch (a gas cloud, a hidden pocket) shows the
	# shooter to everyone for a while.
	w.vision.note_shot(owner)
	# Step 1: read the weapon's numbers.
	var a := world_angle()
	var pellets: int = int(def.get("pellets", 1))
	var spread: float = float(def.get("spread", 0.0))
	var speed: float = float(def["speed"])
	var life: float = float(def["life"]) * range_mult
	var mp := world_pos()
	# Step 2: choose what homing rounds chase.
	var homing_target: Unit = target if mount_type == AUTO else null
	if homing_target == null:
		homing_target = owner.homing_target()
	# Step 3: one round per pellet, each nudged by a random spread (twice
	# as wide for guns with more than 2 pellets). Rounds also carry 35% of
	# the owner's own speed.
	for i in pellets:
		# A battery gun has no dice: it leaves along the barrel, which aimed at its own place
		# in the fixed spread (update()).
		var da := 0.0 if battery else (randf() - 0.5) * spread * (2.0 if pellets > 2 else 1.0)
		var dir := Vector2.from_angle(a + da)
		var vel := dir * speed + owner.velocity * 0.35
		w.projectiles.spawn(mp + dir * 4.0, vel, life, float(def["dmg"]) * dmg_mult, kind, def, owner, homing_target)
	# Step 4: play the firing sound (--sim-only sends no cues: only the
	# sound player listens to them).
	if not Game.sim_only:
		Events.cue.emit(_cue_name(), mp)


## The name of the firing sound for our weapon kind.
func _cue_name() -> String:
	match kind:
		Rules.W_TORP:
			return "torp"
		Rules.W_FLAK:
			return "flak"
		Rules.W_SHELL:
			return "shell"
		Rules.W_PD:
			return "pd"
	return "fire"


## Beams deal damage every tick while firing. `dmg_mult` already includes
## fire_mult: energy routing, fire-rate gear, Broadside and strain scale a
## beam's damage the way they scale other guns' rate of fire. `length` is
## the beam's reach in world units; `energy` pays per second (null = free).
func _update_beam(dt: float, fire: bool, dmg_mult: float, length: float, energy: EnergyPool) -> void:
	var on_time: float = float(def.get("on", 0.0))
	var off_time: float = float(def.get("off", 0.0))
	beam_firing = false
	if beam_off > 0.0:
		beam_off -= dt
	var bonus := next_mult
	if on_time > 0.0:
		# Burst beams (ion): a trigger pull commits to a full burst, and a
		# one-shot bonus (Capacitor Dump) is latched for that whole burst.
		if beam_on <= 0.0 and fire and beam_off <= 0.0:
			beam_on = on_time
			idle_t = 0.0
			burst_mult = next_mult
			next_mult = 1.0
		if beam_on <= 0.0:
			return
		bonus = burst_mult
		# Count the burst down; when it ends, start the rest time.
		beam_on -= dt
		if beam_on <= 0.0:
			beam_off = off_time
			burst_mult = 1.0
	elif not fire:
		return
	# Pay for this tick of beam; no energy, no beam.
	var cost: float = float(def.get("energy", 0.0)) * dt
	if energy != null and cost > 0.0 and not energy.spend(cost):
		return
	# Fire: Combat damages the first thing on the line and tells us where
	# the beam stopped; Projectiles draws it.
	beam_firing = true
	# A beam that is firing is not idle: the idle swing's count starts over on every tick of the burst,
	# so the turret is never boosted inside its own burst.
	idle_t = 0.0
	engaged = true
	var w := owner.world
	# A beam fired from inside a cover patch shows the shooter, like a shot.
	w.vision.note_shot(owner)
	var mp := world_pos()
	var dir := Vector2.from_angle(world_angle())
	var dmg: float = float(def["dps"]) * dt * dmg_mult * bonus
	# The beam's strength against armour is half its damage per second.
	var strength: float = float(def["dps"]) * dmg_mult * bonus * 0.5
	beam_end = w.combat.beam(owner, mp, dir, length, dmg, kind, bool(def.get("cuts", false)), strength)
	w.projectiles.add_beam(mp, beam_end, owner.team, float(def.get("width", 3.0)), kind)
