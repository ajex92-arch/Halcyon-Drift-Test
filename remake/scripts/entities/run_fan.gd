class_name RunFan
extends RefCounted
## WHAT THIS IS: the "narrowing fan" of the Bomber's torpedo run: the score
## that says how steady the pilot has flown, the angle of the fan that score
## makes, and the three torpedoes that leave along it. A part of the Bomber's
## run (RunGun), kept in its own file.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
##   - tick() is the score. Every Bomber has a tightness score from 0 to 360
##     points (Ship.fan_points). Each tick it goes UP by 2 while the pilot gives
##     no turn and no sideways thrust and is not boosting (a tick of the hold
##     counts as steady by itself, because the heading is locked), STAYS while
##     the ship boosts, and goes DOWN by 6 on any tick with turn or sideways
##     input. So a second of steering empties 3 seconds of flying straight,
##     and 3 seconds of steady flight fill it from empty to full (the Steady
##     Sights research makes the gain 3, so 2 seconds do). Being hit,
##     the ship's speed and rock contact never change it.
##   - half_angle() turns the score into the fan: 18 degrees either side of the
##     nose at 0 points, 3 degrees at 360 points, in a straight line between.
##   - launch() sends the three torpedoes of a run on the same tick: one along
##     the nose and one along each edge of the fan, from muzzles 12 world units
##     apart. All three have the same speed and the pattern is fixed (no random
##     spread), so a run is repeatable.
##   - class_word() names what kind of thing a unit is, for the usage counters.
##
## WHO USES IT: Ship._weapons() calls tick(); WeaponMount.fire_fan() calls
## launch(); ShipFlight.fly() reads TURN_EPS; RunPaint draws the fan from
## half_angle(); the AI (PilotRun) and the tests read the constants.

## Smallest turn of the nose, in radians in one tick, that counts as turn input.
## A smaller turn (the weak computer pilots' aim wobble, a tiny correction of a
## drifting camera) leaves the score alone.
const TURN_EPS := 0.003
## Smallest sideways thrust (0..1) that counts as strafe input; the same figure
## flight assist uses for "the pilot is strafing".
const STRAFE_EPS := 0.12
## Points gained in a tick of steady flight.
const GAIN := 2
## Points lost in a tick with turn or strafe input.
const LOSS := 6
## The names of the lanes, by lane number (0 = left, 1 = centre, 2 = right).
const LANE_WORDS := ["left", "centre", "right"]


## One tick of the score for Bomber `ship` (see HOW IT WORKS). `ship.turned` is
## whether the nose turned more than TURN_EPS this tick (ShipFlight.fly() sets
## it). Called by Ship._weapons() before the guns are worked.
static func tick(ship: Ship) -> void:
	var pts := ship.fan_points
	# On a run the heading is locked and sideways thrust is ignored, so the tick
	# is steady whatever the keys say.
	var steered := not ship.run_on() and (ship.turned or absf(ship.controls.strafe) >= STRAFE_EPS)
	if steered:
		pts -= LOSS
	elif not ship.boosting:
		pts += GAIN + (ship.world.teams[ship.team] as TeamState).fan_gain
	ship.fan_points = clampi(pts, 0, int(ship.run_mount.def.get("fan_points", 360)))


## The fan's half-angle in radians for a score of `points` on the gun with entry
## `def` in Weapons: the wide angle at 0 points down to the tight angle at the
## full score.
static func half_angle(def: Dictionary, points: int) -> float:
	var top := float(def.get("fan_points", 360))
	var share := clampf(float(points) / top, 0.0, 1.0)
	return deg_to_rad(lerpf(float(def.get("fan_wide", 18.0)), float(def.get("fan_tight", 3.0)), share))


## The lanes of a launch from gun `m` with a tightness score of `points`, as a
## list with one entry for each torpedo, left to right: `[start, velocity]`, the
## world point it starts from and its velocity (world units a second). The left
## lane flies along the left edge of the fan, the middle one along the nose, the
## right one along the right edge. Each starts from a muzzle off to its own side
## (the lane gap apart) and 4 units ahead along its own direction, and has a
## third of the ship's own speed added. Used by launch(), and by the drawing and
## the alarm so they show what a launch would really do.
static func lanes(m: WeaponMount, points: int) -> Array:
	var def := m.def
	var half := half_angle(def, points)
	var gap := float(def.get("lane_gap", 12.0))
	var speed := float(def["speed"])
	var nose := m.world_angle()
	var right := Vector2.from_angle(nose + PI * 0.5)
	var mp := m.world_pos()
	var count := int(def.get("lanes", 3))
	var out: Array = []
	for k in count:
		var side := float(k) - float(count - 1) * 0.5
		var dir := Vector2.from_angle(nose + side * half)
		out.append([mp + right * (gap * side) + dir * 4.0, dir * speed + m.owner.velocity * 0.35])
	return out


## Send the three torpedoes of a run from gun `m`, all on this tick. `dmg_mult`
## scales their damage and `range_mult` their flight time. The nose is the
## heading the run locked, so they leave along the fan that was drawn.
static func launch(m: WeaponMount, dmg_mult: float, range_mult: float) -> void:
	var w := m.owner.world
	if w == null:
		return
	# A shot from inside a cover patch shows the shooter to everyone for a while.
	w.vision.note_shot(m.owner)
	# Step 1: the lanes for the score now, and the flight time.
	var def := m.def
	var ship := m.owner as Ship
	var points := ship.fan_points if ship != null else int(def.get("fan_points", 360))
	var life := float(def["life"]) * range_mult
	# Step 2: one torpedo for each lane.
	var lane_list := lanes(m, points)
	for k in lane_list.size():
		var l: Array = lane_list[k]
		var slot := w.projectiles.spawn(l[0], l[1], life, float(def["dmg"]) * dmg_mult, m.kind, def, m.owner, null)
		w.projectiles.lane[slot] = k
		# Torpedo armour research: tougher against point defense and flak.
		if m.torp_hp_mult != 1.0:
			w.projectiles.hp[slot] *= m.torp_hp_mult
	# Step 3: the firing sound (--sim-only sends no cues: only the sound player
	# listens to them).
	if not Game.sim_only:
		Events.cue.emit("torp", m.world_pos())


## What kind of thing `u` is, as one word, for the usage counters: "ms" (a
## mothership), "structure", "small", "medium" or "big" (frigates and up).
static func class_word(u: Unit) -> String:
	if u is Mothership:
		return "ms"
	if u.is_structure():
		return "structure"
	if u.size_class == Rules.SIZE_SMALL:
		return "small"
	return "medium" if u.size_class == Rules.SIZE_MEDIUM else "big"
