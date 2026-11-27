class_name Ship
extends Unit
## WHAT THIS IS: a pilot ship: the spaceship that one pilot (a human player
## or an AI pilot) flies. There are ten hulls, from the small Scout to the
## huge Battlecruiser (Ships.HULLS). DESIGN.md A5.
##
## HOW IT WORKS: every tick (the game moves forward in small steps called
## ticks, 60 per second) World calls sim_update(), which in this order:
##   1. lets the controller (the human's PlayerController or an AI pilot's
##      PilotAI brain) fill in `controls`, the ship's "sticks and buttons";
##   2. counts down the timers, then carries out the button presses: shield
##      focus, energy routing, special, repair kit, dock;
##   3. works out the stats again when needed (ShipStats);
##   4. flies and moves (ShipFlight): turning, thrust, boost, sliding along
##      asteroids and gentle crash damage;
##   5. refills the battery and shields, loads blocked shield damage into the battery
##      as hard energy (a hit that no longer fits overloads the ship: guns, boost and
##      special off, shield zones dark, for a lockout; Vent clears it faster), and
##      works the guns (WeaponMount);
##   6. keeps a Logistics ship's escort repair drones topped up.
##
## A Ship node exists only while flying. Docked pilots have no node: their
## owned hull and modules live on the PilotProfile; World.launch() spawns a
## fresh Ship and World.try_dock() removes it. Death destroys the ship and
## its modules; pilot gear stays on the profile.
##
## THE PARTS: Ship keeps all the ship's variables and its public functions
## (many other files read ship.something). The detail lives in four
## "static library" parts that are handed the ship:
##   ShipStats     (ship_stats.gd)     works out speed, turning, damage,
##                                     hull, shields, battery and vision
##   ShipFlight    (ship_flight.gd)    flying, bumping and crashing
##   ShipLineFlight (ship_line_flight.gd) the flight of the corvettes,
##                                     frigates, destroyers and battlecruisers
##                                     as ships of the line (ShipFlight hands
##                                     over to it while the switch is on)
##   ShipAbilities (ship_abilities.gd) specials, repair kits, escort drones
## A Bomber's torpedo run belongs to its torpedo gun: RunGun (run_gun.gd: the hold,
## the wait for the release, the launch, the cancel and the reload; _requests()
## starts it before the flight and run_locked() holds the heading while it is on)
## and RunFan (run_fan.gd: the tightness score `fan_points` that _weapons() ticks,
## and the fan of three torpedoes).
##
## WHO USES IT: World.launch() creates it and calls setup(); World runs
## sim_update() and removes it on docking (try_dock) or death; Combat
## damages it and Unit.take_hit() asks incoming_mult() and
## shield_resist_bonus(); Economy
## reads bounty_value() and sets ace_t; World sets support_t, paint_t and
## stats_dirty and reads jam_t; PilotProfile sets stats_dirty when gear
## changes; PlayerController and PilotAI fill `controls` and read the stats
## and timers; ShipVisual draws it; the HUD (ShipStatus) shows its timers;
## WeaponMount asks homing_target(); RepairDrone reads repair_recv.
##
## To add a hull: data in ships.gd, plain outline in HullTables.OUTLINES, its
## steel Aurelian drawing in AurelianShapes.HULLS (named pieces; without one,
## Aurelian draws it as the fighter), its alien Cinder shape in
## CinderShapes.HULLS (without one, Cinder draws it as the fighter), special in
## ShipAbilities.use_special() (Ship._use_special() forwards there).

## How much faster the Fighter turns while its Snap special is on (1.9x).
const SPECIAL_SNAP_TURN := 1.9

# --- what this ship is -----------------------------------------------------------------

## Which hull this is: an id from Ships.HULLS (e.g. "fighter").
var hull_id := ""
## That hull's data from Ships.HULLS (speeds, hull, shields, guns, special).
var def: Dictionary = {}
## The pilot's record (PilotProfile): team, callsign, gear, kits, credits.
var profile: PilotProfile = null
## The pilot's "hands": anything with `func update(ship: Ship, dt: float)
## -> void`. World.launch() sets the human's PlayerController or the AI
## pilot's PilotAI brain. Null = nobody at the controls.
var controller = null
## The sticks and buttons for this tick (ShipControls), filled by the
## controller.
var controls := ShipControls.new()
## The ids of the modules fitted to this ship (Modules.MODULES).
var modules: Array[String] = []
## The summed bonuses from gear and modules (StatBlock), rebuilt by
## recompute_stats().
var stats := StatBlock.new()
## The ship's battery and energy routing (EnergyPool).
var energy := EnergyPool.new()
## The ship's guns (WeaponMount): the hull's own, then any added by modules.
var mounts: Array[WeaponMount] = []
## How many of `mounts` are the hull's own (the rest are added by modules).
## World rebuilds the module guns after a refit by cutting the list back to
## this many.
var base_mounts := 0
## The gun that makes torpedo runs (a mount whose weapon has a wind-up: the
## Bomber's torpedo), or null for a ship with none. Set in setup().
var run_mount: WeaponMount = null
## Flight assist on or off (the human can toggle it; PlayerController copies
## it into controls.assist).
var assist := true
## The Bomber's tightness score, 0 to 360: how long it has flown steady
## (RunFan.tick()). It sets how narrow the fan of its next torpedo run is
## (RunFan.half_angle()). Always 0 for a ship with no torpedo run.
var fan_points := 0
## True when the nose turned more than RunFan.TURN_EPS this tick (ShipFlight.fly()
## sets it for a ship with a torpedo run). RunFan.tick() reads it.
var turned := false

# --- worked-out flight and combat numbers (set by recompute_stats) --------------------

## Main engine push, in world units per second, per second.
var f_accel := 0.0
## Reverse thruster push, in world units per second, per second.
var f_reverse := 0.0
## Side thruster push, in world units per second, per second.
var f_strafe := 0.0
## Top speed (a soft cap), in world units per second.
var f_max := 0.0
## Turning speed, in radians per second (a full turn is about 6.28).
var f_turn := 0.0
## The fraction (0..1) of turning speed lost at top speed.
var f_bleed := 0.0
## Flight assist strength: how fast sideways drift dies away (per second).
var f_assist := 0.0
## How fast speed above the cap is pulled back down (per second).
var f_cap_rate := 2.0
## Seconds the main engine takes to go from idle to its full push (0 = at
## once).
var f_spool := 0.0
## How hard the main engine is pushing now, 0..1, while it spools up (only
## used when f_spool is above 0).
var throttle := 0.0
## True when this ship flies as a ship of the line (ShipLineFlight): the build
## has that flight on (Rules.big_hull_flight()) and the hull has a "line" entry
## in Handling.TABLE.
var f_line := false
## How far the main engines may swivel away from "pushing straight ahead", each
## way, in radians (0 for a hull that does not fly as a ship of the line).
var f_swivel_max := 0.0
## How far each of the two main engines toes out of "pushing straight back" when
## the ship brakes, in radians (0 = the engines swing round together as one
## group, and also 0 for a hull that does not fly as a ship of the line).
var f_brake_split := 0.0
## How fast the main engines swivel, in radians per second.
var f_swivel_rate := 0.0
## How far behind the centre of mass the main engines push, in world units.
var f_eng_arm := 0.0
## How far behind the centre of mass the side thrusters push, in world units.
var f_side_arm := 0.0
## How hard the hull is to spin: the square of the radius over which its weight
## is spread (world units squared).
var f_gyr2 := 1.0
## The share of the hull's flight-assist grip (f_assist) that trims sideways drift
## in a ship of the line (0 for a hull that does not fly as a ship of the line).
var f_trim := 0.0
## The strongest braking against forward motion, in world units per second, per
## second: for a ship of the line the engines swung right round plus the
## reverse thrusters; for every other hull just the reverse thrusters.
var f_brake := 0.0
## Seconds the engines need to swing from pushing ahead to their braking
## position (0 for a hull whose engines do not swivel).
var f_brake_lag := 0.0
## Where the main engines point now: the angle in radians between the way they
## push and straight ahead (0 = pushing straight ahead, 3.14 = pushing straight
## back; positive turns the push toward starboard). Only a ship of the line
## uses it.
var swivel := 0.0
## Half the angle between the two main engines, in radians (0 or more; 0 whenever
## they fly together). While a ship of the line brakes with a brake split the
## engines toe out: one points at `swivel + toe` and the other at `swivel - toe`,
## so their sideways pushes cancel. Only a ship of the line uses it.
var toe := 0.0
## The fastest the stern kick may spin the nose, in radians per second: the A and
## D keys on a ship of the line (when `kick_keys` is true) ask the side thrusters
## alone for this spin (0 for a hull that does not fly as a ship of the line).
var f_kick_cap := 0.0
## True when A and D are a stern kick, not a strafe, for this ship: its human pilot
## flies it (PlayerController sets it every tick, never while the Admiral coasts)
## and it is a ship of the line. False for every computer-flown ship, so their
## strafe stays a strafe.
var kick_keys := false
## True while a ship of the line's main engines are called in to help with a
## turn (the nose is far off the point it faces, or spinning fast); it is let go
## when the nose error and the spin are both back under those same limits (the
## let-go share is 1.0, so there is no gap between calling in and letting go; a
## share under 1.0 would add one). Only a ship of the line uses it.
var engine_help := false
## Seconds left in which the main engines stay on the side they chose for a turn
## (a ship of the line restarts it when the engines go over to the other side).
var swivel_hold_t := 0.0
## How fast the nose is turning now, in radians per second (positive =
## clockwise on screen). Only a ship of the line uses it.
var ang_vel := 0.0
## Seconds the engines stay swung round to brake after the last brake request.
var brake_t := 0.0
## Engine push multiplier while boosting.
var f_boost_mul := 1.0
## How far over top speed boosting may go (a multiplier of f_max).
var f_boost_cap := 1.0
## Energy spent per second while boosting.
var f_boost_drain := 30.0
## True if this ship can boost right now (a booster hull or a Boost Cell
## module, and not EMP'd).
var can_boost := false
## Rate-of-fire multiplier for all guns.
var fire_mult := 1.0
## Damage multiplier for all guns.
var dmg_mult := 1.0
## Reach multiplier for all guns.
var range_mult := 1.0
## Shield refill speed multiplier.
var regen_mult := 1.0
## Seconds added to the shields' wait before refilling (from gear).
var shield_delay_bonus := 0.0
## The fraction (0..0.9) of crash damage ignored.
var collision_resist := 0.0
## Multiplier on repairs this ship receives from repair drones.
var repair_recv := 1.0
## Seconds until the next routine stats rebuild (every 0.25 s).
var stats_t := 0.0
## True = rebuild the stats on the next tick (set when something changes).
var stats_dirty := true

# --- timers and effects (all in seconds; 0 = off or ready) ----------------------------

## Seconds until the special can be used again.
var special_cd := 0.0
## Seconds left on a special that lasts (Snap, Overload, Brace, Overcharge,
## Broadside).
var special_t := 0.0
## Seconds left of the charge-up of a special that starts with one: the Battlecruiser's
## Broadside (1.2 s) and the Destroyer's Overcharge (1 s warning). 0 = no charge. When it
## runs out the special's lasting effect (special_t) begins.
var charge_t := 0.0
## The side a Broadside is charged for: +1 starboard, -1 port, set when the special is
## pressed from the side of the aim point (side_of()); 0 for any other special. It stays
## set while the Broadside's faster-fire time runs. While charge_t runs, a reticle on the
## other side loses the charge.
var charge_side := 0
## True on the one tick a Broadside charge has just ended: the guns of the charged side
## fire together (read and cleared by _weapons()).
var volley_now := false
## Seconds left of the arcs cue: the main-gun wedges of the arcs view stay drawn this long after
## the reticle leaves every main arc (the human's ship only; PlayerController sets it).
var arc_cue_t := 0.0
## Seconds until the shield focus may change again.
var focus_cd := 0.0
## Seconds until the energy routing may change again.
var energy_cd := 0.0
## Seconds left of "ace" bonuses (faster, harder-hitting). Economy starts it
## (Rules.ACE_TIME) when the pilot gets Rules.ACE_KILLS kills in a row.
var ace_t := 0.0
## Seconds left of an EMP from an enemy Scout's ping: engines at 35%, no
## boost.
var emp_t := 0.0
## Seconds left of our Jam special: enemy vision near us shrinks (World).
var jam_t := 0.0
## Seconds left of being "painted" by an enemy Support ship: torpedoes do
## 30% more damage to us (Combat.PAINT_BONUS), unless the damage modifiers
## are removed: then the mark is made all the same but changes no damage.
## World sets it.
var paint_t := 0.0
## Seconds left of a friendly Support ship's aura: +6% turning, +6% damage,
## +8% reach. World sets it.
var support_t := 0.0
## Seconds until a crash can hurt us again (0.4 s after each painful crash).
var collide_cd := 0.0
## Seconds left of an overload lockout (a blocked hit overran the battery): no guns, boost
## or special, dark shield zones. 0 = none. See OverloadRules.
var overload_left := 0.0
## True while a Vent runs: movement only, the battery clears faster, shield zones dark.
## It ends by itself when the battery is clear. See OverloadRules.
var venting := false
## Our repair-kit drones that may still be flying (RepairDrone nodes).
var kit_drones: Array = []
## Our escort repair drones (Logistics ship only; RepairDrone nodes).
var escort_drones: Array = []
## Match time (seconds) of launch. PlayerController ignores the dock key for
## 0.5 s after it, so the launch key press can't also dock us.
var launched_at := 0.0

# --- read by ShipVisual for the engine flames (0..1 each) -----------------------------

## How hard the main engine burns (0..1).
var thrust_main := 0.0
## How hard the port (left-pushing) thruster burns (0..1).
var thrust_port := 0.0
## How hard the starboard (right-pushing) thruster burns (0..1).
var thrust_star := 0.0
## True while boosting this tick (also shown by the HUD).
var boosting := false
## Feature hook (Lane Slipstream, WorldSlipstream): true while this ship runs
## in the slipstream, which raises its top speed (ShipStats calls
## WorldSlipstream.apply()). Always false unless --variant=slipstream is on.
var slip := false


## Set up a freshly made ship. Called by World.launch() with the world `w`,
## the pilot `p`, hull id `hid`, module ids `mods`, start point `at` and
## facing `facing` (radians).
func setup(w: World, p: PilotProfile, hid: String, mods: Array, at: Vector2, facing: float) -> void:
	# Step 1: who we are.
	world = w
	profile = p
	team = p.team
	kind = Unit.K_SHIP
	launched_at = w.time
	hull_id = hid
	def = Ships.get_def(hid)
	size_class = int(def["size"])
	radius = float(def["radius"])
	display_name = p.callsign
	modules.assign(mods)
	# Step 2: where we start (already moving forward at 120), and how we
	# collide: we are on physics layer 2 ("pilot ships") and bump into
	# layers 1, 3 and 4 (asteroids, structures, ore-field rocks).
	position = at
	rotation = facing
	velocity = Vector2.from_angle(facing) * 120.0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
	# Step 3: shields, battery and hull from the hull's data.
	shields = ShieldZones.new()
	shields.setup(float(def["shield"]), float(def["shield_regen"]), float(Rules.SHIELD_DELAY[size_class]))
	if def.has("shield_weights"):
		shields.use_table(def["shield_weights"], float(def.get("shield_swing", 0.0)))
	shields.resist = float(def["shield_resist"])
	energy.setup(float(def["energy"]), float(def["energy_regen"]))
	hull_max = float(def["hull"])
	hull = hull_max
	hull_resist = float(def["hull_resist"])
	# Step 4: guns: the hull's own, then one AUTO gun per module that adds
	# one (mounted near the tail, free to swing all the way round).
	mounts.clear()
	var no_tail_gun := Game.opt("no-tail-gun") != null
	for m: Dictionary in def["mounts"]:
		# Test only: --no-tail-gun leaves the Bomber's rear gun off.
		if no_tail_gun and m["w"] == "tail_gun":
			continue
		var gun := WeaponMount.new(self, m["w"], m["type"], m["off"], float(m["arc"]), float(m.get("face", 0.0)))
		gun.id = String(m.get("id", ""))
		gun.battery = bool(m.get("battery", false))
		gun.idle_boost = bool(def.get("side_battery", false)) and gun.mount_type == WeaponMount.TURRET
		mounts.append(gun)
	_set_battery_groups()
	base_mounts = mounts.size()
	for mid: String in modules:
		var md: Dictionary = Modules.MODULES[mid]
		if md.has("adds_mount"):
			mounts.append(WeaponMount.new(self, md["adds_mount"], "auto", Vector2(-radius * 0.4, 0), 180.0))
	run_mount = null
	for m: WeaponMount in mounts:
		if m.windup > 0:
			run_mount = m
			break
	# Step 5: work out the stats with a full repair, and aim straight ahead.
	recompute_stats(true)
	# The armour sections, made whole from the hull the stats worked out.
	armour = ArmourSections.make(def, hull_max)
	ShipStats.apply_gear_armour(self)
	spine_len = float(def.get("spine", 0.0))
	hit_r = float(def.get("hit_r", 0.0))
	spine_off = float(def.get("spine_off", 0.0))
	# The parts (guns, engine pods, sensor) of the four big hulls, while the parts switch is on.
	parts = null
	if armour != null and ShipParts.has_parts(hid) and Rules.parts_on():
		parts = ShipSystems.make(ShipParts.build(hid, armour))
	controls.aim_point = at + Vector2.from_angle(facing) * 2000.0
	controls.face_point = controls.aim_point


## Number the battery guns in groups: the battery guns of one weapon on one side of the ship
## (the sign of their offset's y), in the row order. Each gun learns its place in its group
## (battery_i) and the size of the group (battery_n), which fix its share of the spread.
func _set_battery_groups() -> void:
	var seen := {}
	for gun: WeaponMount in mounts:
		if gun.battery:
			var key := "%s:%d" % [gun.weapon_id, int(signf(gun.offset.y))]
			gun.battery_i = int(seen.get(key, 0))
			seen[key] = gun.battery_i + 1
	for gun: WeaponMount in mounts:
		if gun.battery:
			gun.battery_n = int(seen["%s:%d" % [gun.weapon_id, int(signf(gun.offset.y))]])


## What the ship is worth in credits: hull price + module prices. Used for
## kill bounties and insurance (and by the AI when trading in a hull).
func bounty_value() -> float:
	var v := float(def.get("price", 0.0))
	for mid: String in modules:
		v += Modules.price_for(mid, hull_id)
	return v


## True for small ships (size class Rules.SIZE_SMALL).
func is_small() -> bool:
	return size_class == Rules.SIZE_SMALL


## The size rounds, beams and blasts see (see Unit.hit_radius()): a small
## pilot ship counts Rules.SMALL_PILOT_HIT_MUL (1.1) times its body's radius,
## so a shot that grazes the rim of the drawing still lands; a bigger ship is
## as big as its radius. The body itself (physics circle, pushing apart from
## other ships, rocks, walls, docking) stays the size of `radius`.
func hit_radius() -> float:
	return radius * Rules.SMALL_PILOT_HIT_MUL if size_class == Rules.SIZE_SMALL else radius


## The hit test of a round, beam or other swept line (see Unit.hit_t()): a hull
## with a capsule hit shape (hit_r above 0: the frigates, the Destroyer and the
## Battlecruiser) is hit as that capsule, the circle of hit_radius() for every
## other ship, exactly as before.
func hit_t(a: Vector2, b: Vector2, pad: float) -> float:
	if hit_r <= 0.0:
		return Util.seg_circle_t(a, b, global_position, hit_radius() + pad)
	return Util.seg_capsule_t(a, b, capsule_centre(), Vector2.from_angle(rotation), spine_len * 0.5, hit_r + pad)


## Can the special be used now? (Cooldown over and enough energy.)
func special_ready() -> bool:
	return special_cd <= 0.0 and energy.value >= float(def["special_energy"]) and not systems_off()


## Rebuild the worked-out stats from hull + modules + pilot gear + team
## upgrades + buffs. Cheap; runs every 0.25 s and whenever something
## changes. `full_heal` also fills hull, shields and battery (at launch).
## Forwarding function: the real code is ShipStats.recompute().
func recompute_stats(full_heal: bool = false) -> void:
	ShipStats.recompute(self, full_heal)


## Damage multiplier on incoming hits: 0.62 while a Flak ship's Brace
## special is on, otherwise 1.0. (Unit.take_hit() uses it.)
func incoming_mult() -> float:
	if special_t > 0.0 and String(def.get("special", "")) == "brace":
		return 0.62
	return 1.0


## Extra shield resistance from energy routing (0.15 when routing to
## Shields, else 0). Unit.take_hit() uses it.
func shield_resist_bonus() -> float:
	return energy.m("sresist")


## True while the ship is on a torpedo run: the hold or the wait for the
## release (RunGun.on). The run begins on the first tick the fire button is down
## and ends when the torpedoes have left or the run is cancelled.
func run_on() -> bool:
	return run_mount != null and run_mount.run.on


## True while the ship holds its heading for a torpedo run (ShipFlight.fly()
## turns nothing and slides nowhere; W and S still work). The lock is the run
## itself: it starts on the first tick of the hold and lasts through the tick
## the torpedoes leave, so they go along the heading the path line showed.
func run_locked() -> bool:
	return run_on()


## How far the hold of the torpedo run is, 0..1 (0 = none going). ShipVisual
## draws it as the bar under the ship.
func run_frac() -> float:
	return run_mount.run.wind_frac() if run_mount != null else 0.0


## The unit our homing torpedoes should chase: the controller's
## `lock_target` (PilotAI has one; PlayerController doesn't), if it is
## still alive. Else null.
func homing_target() -> Unit:
	if controller != null and "lock_target" in controller:
		var t = controller.lock_target
		if t != null and is_instance_valid(t) and t is Unit and t.alive:
			return t
	return null


# --- per tick ---------------------------------------------------------------------------

## One tick of `dt` seconds (see HOW IT WORKS at the top). When World's
## speed measuring ("profiling") is on, it also adds up how long each stage
## took, in microseconds, into world.prof.
func sim_update(dt: float) -> void:
	if not alive:
		return
	var prof := world != null and world.profiling
	var t0 := Time.get_ticks_usec() if prof else 0
	# Stage 1: the controller works the sticks and buttons.
	if controller != null:
		controller.update(self, dt)
	var t1 := Time.get_ticks_usec() if prof else 0
	# Stage 2: timers, then button presses.
	_timers(dt)
	_requests()
	# Docking (F) removes the ship inside _requests().
	if not alive:
		controls.clear_edges()
		return
	# Stage 3: stats if due, then fly and move.
	stats_t -= dt
	if stats_dirty or stats_t <= 0.0:
		recompute_stats()
	ShipFlight.fly(self, dt)
	var t2 := Time.get_ticks_usec() if prof else 0
	ShipFlight.move(self)
	# A hard asteroid hit can kill us inside ShipFlight.move().
	if not alive:
		return
	var t3 := Time.get_ticks_usec() if prof else 0
	# Stage 4: battery, shields, guns and escort drones.
	energy.tick(dt, OverloadRules.VENT_REFILL_MULT if venting else 1.0)
	shields.tick(dt, regen_mult, shield_delay_bonus)
	_overload_step(dt)
	_weapons(dt)
	if def.has("repair_drones"):
		ShipAbilities.manage_escort_drones(self)
	# Stage 5: one-tick button presses are used up.
	controls.clear_edges()
	if prof:
		var t4 := Time.get_ticks_usec()
		world.prof["s_ctrl"] = int(world.prof.get("s_ctrl", 0)) + (t1 - t0)
		world.prof["s_flight"] = int(world.prof.get("s_flight", 0)) + (t2 - t1)
		world.prof["s_move"] = int(world.prof.get("s_move", 0)) + (t3 - t2)
		world.prof["s_weap"] = int(world.prof.get("s_weap", 0)) + (t4 - t3)


## Count every timer down by `dt` seconds (never below 0). When a special,
## ace or EMP runs out, the stats must be worked out again.
func _timers(dt: float) -> void:
	# Cooldowns and lasting effects.
	if special_cd > 0.0:
		special_cd = maxf(0.0, special_cd - dt)
	if special_t > 0.0:
		special_t = maxf(0.0, special_t - dt)
		if special_t == 0.0:
			stats_dirty = true
			charge_side = 0
	# A special that charges up first (Broadside, Overcharge): count the charge down; the
	# special's lasting effect starts on the tick it ends.
	volley_now = false
	if charge_t > 0.0:
		_charge_step(dt)
	if arc_cue_t > 0.0:
		arc_cue_t -= dt
		if arc_cue_t <= 0.0005:
			arc_cue_t = 0.0
	if focus_cd > 0.0:
		focus_cd = maxf(0.0, focus_cd - dt)
	if energy_cd > 0.0:
		energy_cd = maxf(0.0, energy_cd - dt)
	# Buffs and debuffs from others.
	if ace_t > 0.0:
		ace_t = maxf(0.0, ace_t - dt)
		if ace_t == 0.0:
			stats_dirty = true
	if emp_t > 0.0:
		emp_t = maxf(0.0, emp_t - dt)
		if emp_t == 0.0:
			stats_dirty = true
	if jam_t > 0.0:
		jam_t = maxf(0.0, jam_t - dt)
	if paint_t > 0.0:
		paint_t = maxf(0.0, paint_t - dt)
	if support_t > 0.0:
		support_t = maxf(0.0, support_t - dt)
	# The crash timer may dip below 0 (it is only compared with 0).
	if collide_cd > 0.0:
		collide_cd -= dt
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# The parts count their own ticks (offline parts climb back); a part that changed state asks
	# for the stats to be worked out again (the engine pods set the numbers).
	if parts != null:
		parts.tick()
		if parts.dirty:
			parts.dirty = false
			stats_dirty = true


## Which side of the ship the point `point` is on: +1 starboard (to the right of the nose), -1 port.
## A point dead ahead or astern counts as port.
func side_of(point: Vector2) -> int:
	return 1 if Util.ang_diff(rotation, (point - global_position).angle()) > 0.0 else -1


## One tick of a charge (charge_t above 0). A Broadside charge is lost, with no refund, when the
## reticle goes over to the other side or the systems go off (overload or Vent); an Overcharge
## warning is lost only to the systems going off. Otherwise the charge counts down, and on the
## tick it ends the special's lasting effect starts (ShipAbilities.charge_done()) and, for a
## Broadside, the guns of the charged side fire together (volley_now).
func _charge_step(dt: float) -> void:
	if systems_off() or (charge_side != 0 and side_of(controls.aim_point) != charge_side):
		charge_t = 0.0
		charge_side = 0
		return
	charge_t -= dt
	if charge_t > 0.0005:
		return
	charge_t = 0.0
	volley_now = charge_side != 0
	ShipAbilities.charge_done(self)


## Carry out this tick's button presses from `controls`. A shield focus or
## energy routing change only happens when its cooldown is over and it is a
## real change; it then starts a new cooldown (by size class, shortened by
## "redirect" gear but never below 20%). Then the special, the repair kit
## and docking.
func _requests() -> void:
	var c := controls
	# Vent: a committed clearing of the battery, first of all so the guns below see it. Not in
	# a lockout, not twice, and only with something to clear (a ship that cannot refill could
	# never end one).
	if c.vent and overload_left <= 0.0 and not venting and energy.load_frac() > 0.0 and energy.regen > 0.0:
		venting = true
		Game.count_usage("vents_started")
	# The Bomber's torpedo run: the reload, the cancel and the start of a hold,
	# before the ship flies, so the heading is locked from the first tick.
	if run_mount != null:
		run_mount.run.pre(run_mount, c.fire and not systems_off(), c.cancel_run, energy)
	var cd_mul := maxf(0.2, stats.mul("redirect_cd_pct"))
	# Shield focus.
	if c.focus_request >= 0 and focus_cd <= 0.0 and c.focus_request != shields.focus:
		shields.set_focus(c.focus_request)
		focus_cd = float(Rules.FOCUS_COOLDOWN[size_class]) * cd_mul
		Events.cue.emit("ui", global_position)
	# Energy routing (changes the stats).
	if c.energy_request >= 0 and energy_cd <= 0.0 and c.energy_request != energy.mode:
		energy.mode = c.energy_request
		energy_cd = float(Rules.ENERGY_COOLDOWN[size_class]) * cd_mul
		stats_dirty = true
		Events.cue.emit("ui", global_position)
	# Special, repair kit, dock.
	if c.special and special_ready():
		_use_special()
	if c.use_kit:
		use_repair_kit()
	if c.dock and world != null:
		world.try_dock(self)


## Work every gun for this tick. Torpedo guns first get the team's torpedo
## research: tougher torpedoes (Armoured Torpedoes).
func _weapons(dt: float) -> void:
	var c := controls
	var t: TeamState = world.teams[team]
	# A Bomber's tightness score, before its torpedo gun is worked (a launch uses
	# the score of this tick).
	if run_mount != null:
		RunFan.tick(self)
	var off := systems_off()
	# A Broadside: the battery guns of the charged side are held while it charges and fire
	# together on the tick it ends; once it has, the whole charged side fires 50% faster for the
	# window (the chasers on the centreline never do).
	var held := charge_t > 0.0 and charge_side != 0
	var volley := volley_now
	volley_now = false
	var window := special_t > 0.0 and charge_side != 0 and String(def.get("special", "")) == "broadside"
	# The parts: a gun that is knocked out does nothing and a hurt one fires at half rate; the
	# sensor sets the turrets' swing (a ship with no parts is unchanged).
	var slew := parts.sensor_slew() if parts != null else 1.0
	for mi in mounts.size():
		var m: WeaponMount = mounts[mi]
		if m.kind == Rules.W_TORP:
			m.torp_hp_mult = 1.0 + t.torp_hp_bonus
		var mult := fire_mult
		if parts != null:
			m.slew_mult = slew
			var ps := parts.mount_state(mi) if mi < base_mounts else ShipSystems.WORKING
			if ps == ShipSystems.OFF:
				m.beam_firing = false
				m.beam_on = 0.0
				m.engaged = false
				continue
			if ps == ShipSystems.DEGRADED:
				mult *= 0.5
		# With the systems off the self-aiming guns stay quiet too (they ignore the trigger), and so do
		# the battery guns, which run the self-aiming path with no trigger when the reticle is off their side.
		if off and (m.mount_type == WeaponMount.AUTO or m.battery):
			m.beam_firing = false
			continue
		var trigger: bool = c.fire and not off
		m.hold = false
		if (held or volley or window) and m.mount_type != WeaponMount.FIXED and int(signf(m.offset.y)) == charge_side:
			if window:
				mult *= 1.5
			if m.battery and (held or volley):
				m.hold = true
				trigger = false
				if volley:
					# The volley: every held gun of the side is ready, and fires this tick if its
					# arc holds the reticle and it has swung round to it.
					m.cd = 0.0
					m.beam_off = 0.0
					trigger = true
		m.update(dt, c.aim_point, trigger, mult, dmg_mult, range_mult, energy)


## True while the ship's systems are off: an overload lockout or a Vent runs. Guns (the
## torpedo run too), boost and special do nothing then and the shield zones are dark. The
## one place everything asks.
func systems_off() -> bool:
	return overload_left > 0.0 or venting


## Fill the battery and end every overload state: no hard energy, no lockout, no Vent
## (a ship made whole, as at launch).
func fill_energy() -> void:
	energy.fill()
	overload_left = 0.0
	venting = false
	if shields != null:
		shields.dark = false
		shields.last_blocked = 0.0


## The overload step of one tick, after the battery and the shield have refilled: count the
## lockout down, load this tick's blocked shield points into the battery as hard energy
## (a hit that no longer fits overloads the ship: its lockout starts), drain the hard energy
## (half speed in a lockout, double in a Vent, otherwise only while the shield rests when
## OverloadRules.DRAIN_ONLY_RESTING), end a Vent whose battery is clear, and set the shield
## dark or lit for the next hits. A ship with no shield never loads or overloads.
## A quiet ship (no lockout, no Vent, no hard energy, nothing blocked this tick) has nothing
## to count, load, drain or end: it only lights its shield and returns at once.
func _overload_step(dt: float) -> void:
	if overload_left <= 0.0 and not venting and energy.hard <= 0.0 and (shields == null or shields.last_blocked <= 0.0):
		if shields != null:
			shields.dark = false
		return
	if overload_left > 0.0:
		overload_left = maxf(0.0, overload_left - dt)
	var blocked := 0.0
	if shields != null:
		blocked = shields.last_blocked
		shields.last_blocked = 0.0
	if blocked > 0.0 and shields.max_total > 0.0 and energy.max_value > 0.0:
		var k := OverloadRules.HARD_SHARE * energy.max_value / shields.max_total
		if energy.add_blocked(k * blocked):
			overload_left = OverloadRules.lockout_seconds(hull_id, blocked)
			venting = false
			Game.count_usage("overloads_started")
	var mult := 1.0
	if venting:
		mult = OverloadRules.VENT_DRAIN_MULT
	elif overload_left > 0.0:
		mult = OverloadRules.REST_HALF
	var resting := shields == null or shields.since_hit >= maxf(0.5, shields.delay + shield_delay_bonus)
	if systems_off() or resting or not OverloadRules.DRAIN_ONLY_RESTING:
		energy.drain_hard(dt, mult)
	if venting and ((energy.hard <= 0.0 and energy.value >= energy.max_value) or energy.regen <= 0.0):
		venting = false
	if systems_off():
		_quiet_guns()
	if shields != null:
		shields.dark = systems_off()


## Stop what the guns have going while the systems are off: a torpedo run in progress ends
## free (nothing launches; counted as torpedo_runs_cancel_overload, not as a rock cancel) and an
## ion burst under way stops.
func _quiet_guns() -> void:
	if run_mount != null:
		run_mount.run.cancel(controls.fire, "overload")
	for m in mounts:
		m.beam_on = 0.0


# --- specials and kits (forwarding) -----------------------------------------------------

## Use this hull's special ability now.
## Forwarding function: the real code is ShipAbilities.use_special().
func _use_special() -> void:
	ShipAbilities.use_special(self)


## True while a repair-kit drone of ours is still alive (gone drones are
## pruned from kit_drones).
## Forwarding function: the real code is ShipAbilities.has_active_kit().
func has_active_kit() -> bool:
	return ShipAbilities.has_active_kit(self)


## R: spend one repair kit from the inventory; a weak repair drone heals us.
## Forwarding function: the real code is ShipAbilities.use_repair_kit().
func use_repair_kit() -> void:
	ShipAbilities.use_repair_kit(self)


## Called once by Combat.kill() when we are destroyed: remove our escort and
## kit drones quietly (no bounty for them) and show an explosion.
func on_killed(_info: DamageInfo) -> void:
	for d in escort_drones + kit_drones:
		if is_instance_valid(d) and d.alive:
			world.combat.kill_silently(d)
	escort_drones.clear()
	kit_drones.clear()
	world.effects.explosion(global_position, radius, Palette.team(team))
