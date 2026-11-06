class_name SquadEngine
extends RefCounted
## WHAT THIS IS: the maths of a pilot's wing: how far apart the wingmen sit, where each
## one's place ("slot") is around the leader, how the shape turns with the leader, how fast a
## wingman must fly to keep its place, where the wing stands to guard a big ship (in the
## pocket behind the ship's guns, where they cannot point), when a wingman has strayed too
## far, and when an order is a repeat. Nothing here keeps a node or a result: it is a static
## library, uids and numbers only, and it never rolls a die.
##
## HOW IT WORKS: every number is a named constant below. A wing flies in a frame that turns
## with its leader: the frame's heading follows the direction the leader is travelling (its
## nose when it is nearly still), smoothed (frame_step()), so a pilot who strafes or twitches
## does not swing the whole shape. A wingman's slot is the leader's position, plus LEAD_TIME
## seconds of the leader's velocity, plus the slot's offset turned into that frame
## (slot_target()). The wingman then flies the velocity that closes on the slot
## (wanted_velocity()) and the sticks that make it (stick_values()). A guard slot is worked
## from the ward's hull: the biggest swing of its aimed guns decides how wide the clear
## pocket behind it is (guard_cone()), and the slots sit in that pocket (guard_slot(),
## mothership_slot()). in_fire_lane() says whether a point lies on the line the ward is
## firing along.
##
## WHO USES IT: WingmanAI (the brain) flies by it, SquadOrders uses the dedup test, Squads uses
## the pick-up test, WingMarks draws the slots, tests/squad_engine_check.gd checks every number.

# --- spacing and the frame --------------------------------------------------------------

## The leader's radius is padded by this (world units) to get the wing's spacing.
const SPACING_PAD := 100.0
## The smallest spacing S (world units).
const SPACING_MIN := 110.0
## The largest spacing S (world units).
const SPACING_MAX := 300.0
## How fast the frame's heading catches up with the leader's, per second: each second it closes
## this many times the remaining angle (a sixth of a second to close most of it).
const FRAME_RATE := 6.0
## The leader must move faster than this (world units a second) for its velocity, not its nose,
## to give the frame its heading.
const FRAME_MIN_SPEED := 120.0
## The slot is placed this far ahead along the leader's velocity (seconds). A small lead keeps the wedge behind a
## fast leader (a quarter of a second put the places level with it or ahead of it at top speed) and still
## anticipates a little.
const LEAD_TIME := 0.10
## One tick in seconds.
const TICK_DT := 1.0 / 60.0

# --- flying to the slot ---------------------------------------------------------------------

## How hard a wingman pulls toward its slot: the wanted velocity adds this many times the
## distance (per second) to the leader's velocity.
const SLOT_PULL := 1.6
## A speed error along the nose of this many world units a second is full forward thrust.
const FORWARD_PER_SPEED := 120.0
## A sideways speed error of this many world units a second is full strafe.
const STRAFE_PER_SPEED := 80.0
## Within this many world units of its slot a wingman is "in slot".
const IN_SLOT := 60.0
## Farther than this many S from its slot a wingman is "catching up".
const CATCH_UP_S := 2.5
## Farther than this many S from its slot a wingman may boost (in the open only).
const BOOST_S := 4.0
## Farther than this many world units from its slot a wingman flies by the route finder
## (PilotFlight.travel) instead of the velocity rule.
const TRAVEL_FAR := 1200.0
## In the jungle the wanted speed is the leader's speed plus this (world units a second).
const JUNGLE_SPEED_PLUS := 40.0
## More than this many world units from the leader for STRAGGLER_TICKS ticks, a wingman goes
## home.
const STRAGGLER_DIST := 6000.0
## How many ticks (20 seconds) a wingman may stay beyond STRAGGLER_DIST.
const STRAGGLER_TICKS := 1200
## A docked wingman relaunches while its leader flies when the leader is within this many
## world units of our mothership's centre.
const PICKUP_DIST := 3000.0

# --- the orders carried out -----------------------------------------------------------------

## The fire stance "at will" looks for targets this far (world units) around the slot.
const PICK_RADIUS := 1400.0
## "Return fire" answers units that hurt the leader or the wingman in the last this many seconds.
const RETURN_FIRE_SECS := 6.0
## "Cover me" fights only enemies within this many world units of the leader...
const COVER_RADIUS := 900.0
## ...and never chases past this many world units from the leader.
const COVER_LEASH := 1200.0
## An ATTACK lapses to "follow" when the target is farther than this from the leader (the same
## 3,200 as the AI pilots' longest hunt).
const ATTACK_LEASH := 3200.0
## An ATTACK lapses when its target has stayed hidden this many ticks (3 seconds).
const ATTACK_HIDDEN_TICKS := 180
## "Hold here": a wingman fires only within its main gun reach plus this (world units)...
const HOLD_REACH_PAD := 200.0
## ...and never chases past this many world units from its hold slot.
const HOLD_LEASH := 250.0
## "Regroup" holds fire until every wingman is in its slot or this many ticks (6 seconds) pass.
const REGROUP_TICKS := 360
## After this many ticks (3 seconds) without a target a wingman goes back to its slot.
const RESUME_TICKS := 180
## A target given up on is ignored for this many seconds.
const SKIP_SECS := 6.0
## The same kind of order on the same target within this many ticks of the last one is a repeat.
const DEDUP_TICKS := 30

# --- guarding a big ship ----------------------------------------------------------------------

## The clear pocket behind a ward is never narrower than this half-angle (degrees)...
const GUARD_CONE_MIN := 16.0
## ...and never wider than this one.
const GUARD_CONE_MAX := 70.0
## A fixed gun counts as a gun that swings this many degrees either side.
const FIXED_ARC := 20.0
## The two near slots sit this far (world units) behind the ward's hull edge...
const GUARD_NEAR_PAD := 220.0
## ...and the third, dead astern, this far.
const GUARD_FAR_PAD := 420.0
## The mothership's flank slots sit this far (world units) outside its beam...
const MOTHERSHIP_FLANK_PAD := 400.0
## ...and its rear slot this far behind its stern.
const MOTHERSHIP_REAR_PAD := 450.0
## A ward is "aiming" when its aim point is more than this many world units away from it.
const LANE_MIN_AIM := 300.0
## A target within this many degrees of the line from the ward to its aim point is in the fire lane...
const LANE_DEGREES := 12.0
## ...when it is also nearer than the aim distance plus this (world units).
const LANE_REACH_PAD := 300.0
## Guard: first the units that hurt the ward in the last this many seconds, then enemies within
## GUARD_ENGAGE of it.
const GUARD_RECENT_SECS := 6.0
## Guard: any enemy within this many world units of the ward is fought (at will).
const GUARD_ENGAGE := 1200.0
## Guard: never chase past this many world units from the ward.
const GUARD_LEASH := 1500.0


# --- spacing and shapes ---------------------------------------------------------------------

## The wing's spacing S for a leader of radius `leader_radius`: the radius plus 100, kept
## between 110 and 300 world units.
static func spacing(leader_radius: float) -> float:
	return clampf(leader_radius + SPACING_PAD, SPACING_MIN, SPACING_MAX)


## Where slot `index` of shape `formation` sits in the leader's frame (x ahead, y to starboard)
## in world units, for spacing `s`. The jungle shape is drawn at JUNGLE_SCALE of S. With
## s = 1 the answer is the table's own numbers.
static func slot_offset(formation: int, index: int, s: float = 1.0) -> Vector2:
	var scale := s * (Formations.JUNGLE_SCALE if formation == Formations.JUNGLE else 1.0)
	return Formations.slot(formation, index) * scale


## The shape actually flown: the jungle shape whenever the leader is in the jungle, else the
## chosen one.
static func effective_formation(chosen: int, jungle: bool) -> int:
	return Formations.JUNGLE if jungle else chosen


## How far (world units) a wingman may chase from its slot in shape `formation`; the jungle
## shape's 400 when `jungle` is true.
static func leash(formation: int, jungle: bool) -> float:
	return Formations.leash_of(Formations.JUNGLE if jungle else formation)


## The frame's heading after `ticks` more ticks: it moves from `h_s` toward the leader's
## heading (the direction of `leader_vel` when that is faster than FRAME_MIN_SPEED, else
## `leader_nose`, both in radians) by min(1, FRAME_RATE x seconds) of the remaining angle.
## Never overshoots.
static func frame_step(h_s: float, leader_vel: Vector2, leader_nose: float, ticks: int) -> float:
	var h := leader_vel.angle() if leader_vel.length() > FRAME_MIN_SPEED else leader_nose
	var k := minf(1.0, FRAME_RATE * float(ticks) * TICK_DT)
	return h_s + Util.wrap_angle(h - h_s) * k


## The wing's frame heading at tick `tick`, kept in the wing's `engine` dictionary (keys "hs" and
## "hs_tick") so that it moves exactly once per tick whichever wingman asks first. The first call
## starts it along the leader's nose. A gap of several ticks (a wingman steers every second tick)
## moves it by that many ticks, at most one second's worth.
static func frame_heading(engine: Dictionary, tick: int, leader_vel: Vector2, leader_nose: float) -> float:
	var last := int(engine.get("hs_tick", -1))
	if last < 0:
		engine["hs"] = leader_nose
		engine["hs_tick"] = tick
		return leader_nose
	var h: float = engine["hs"]
	if last == tick:
		return h
	h = frame_step(h, leader_vel, leader_nose, clampi(tick - last, 1, 60))
	engine["hs"] = h
	engine["hs_tick"] = tick
	return h


## A frame offset (x ahead, y to starboard) turned into a world vector for frame heading `h_s`.
static func frame_to_world(h_s: float, offset: Vector2) -> Vector2:
	return Vector2.from_angle(h_s) * offset.x + Util.starboard_of(h_s) * offset.y


## The world point of slot `index` in shape `formation` for a leader at `leader_pos` with
## velocity `leader_vel`, a frame heading `h_s` and spacing `s`: the offset turned into the
## frame, placed LEAD_TIME seconds of the leader's velocity ahead of the leader.
static func slot_target(leader_pos: Vector2, leader_vel: Vector2, h_s: float, formation: int, index: int, s: float) -> Vector2:
	return leader_pos + leader_vel * LEAD_TIME + frame_to_world(h_s, slot_offset(formation, index, s))


## The velocity a wingman at `ship_pos` wants to fly to keep `slot_pos`: the leader's velocity plus
## SLOT_PULL times the way to the slot, no faster than `top_speed`. In the jungle (`jungle`
## true) no faster than the leader's speed plus JUNGLE_SPEED_PLUS.
static func wanted_velocity(leader_vel: Vector2, slot_pos: Vector2, ship_pos: Vector2, top_speed: float, jungle: bool) -> Vector2:
	var v := leader_vel + (slot_pos - ship_pos) * SLOT_PULL
	var cap := top_speed
	if jungle:
		cap = minf(cap, leader_vel.length() + JUNGLE_SPEED_PLUS)
	return v.limit_length(cap)


## The sticks that make velocity `wanted` from velocity `vel` for a ship whose nose points
## along `nose` (radians): Vector2(forward, strafe), each between -1 and 1. Forward is the
## speed error along the nose at 1 per FORWARD_PER_SPEED; strafe is the sideways error at 1
## per STRAFE_PER_SPEED (+1 slides to port).
static func stick_values(wanted: Vector2, vel: Vector2, nose: float) -> Vector2:
	var err := wanted - vel
	var fwd := clampf(err.dot(Vector2.from_angle(nose)) / FORWARD_PER_SPEED, -1.0, 1.0)
	var side := clampf(err.dot(Util.port_of(nose)) / STRAFE_PER_SPEED, -1.0, 1.0)
	return Vector2(fwd, side)


## True when a wingman `dist` world units from its slot is "in slot".
static func in_slot(dist: float) -> bool:
	return dist <= IN_SLOT


## True when a wingman `dist` from its slot is catching up (farther than CATCH_UP_S x S).
static func catching_up(dist: float, s: float) -> bool:
	return dist > CATCH_UP_S * s


## True when a wingman `dist` from its slot may boost: farther than BOOST_S x S and in the open at
## both its own place and the slot.
static func may_boost(dist: float, s: float, open_at_ship: bool, open_at_slot: bool) -> bool:
	return dist > BOOST_S * s and open_at_ship and open_at_slot


## True when a wingman `dist` from its slot should fly by the route finder: very far, or a rock
## on the straight line.
static func use_travel(dist: float, rock_between: bool) -> bool:
	return dist > TRAVEL_FAR or rock_between


## True when the leader at `leader_pos` is in the asteroid jungle (not on a lane or a base
## clearing) in `world`'s map.
static func in_jungle(world: World, leader_pos: Vector2) -> bool:
	return not world.map.in_open_lane(leader_pos)


## The straggler count after `step` more ticks (one by default): `ticks` plus `step` while the
## wingman is farther than STRAGGLER_DIST from the leader, else 0.
static func straggler_ticks(ticks: int, dist_to_leader: float, step: int = 1) -> int:
	return ticks + step if dist_to_leader > STRAGGLER_DIST else 0


## True when a straggler count says the wingman has been too far for too long.
static func is_straggler(ticks: int) -> bool:
	return ticks >= STRAGGLER_TICKS


## True when a docked wingman may relaunch while its leader flies: the leader is within
## PICKUP_DIST of our mothership's centre.
static func pickup_ready(leader_pos: Vector2, mothership_pos: Vector2) -> bool:
	return leader_pos.distance_to(mothership_pos) <= PICKUP_DIST


# --- repeats --------------------------------------------------------------------------------

## Is an order of `kind` on `target` at `tick` a repeat of the last one noted in `engine` (the
## wing's private dictionary)? It is when the kind and the target are the same and the last was
## no more than DEDUP_TICKS ticks ago.
static func is_duplicate(engine: Dictionary, kind: String, target: Variant, tick: int) -> bool:
	if not engine.has("last_kind"):
		return false
	return str(engine["last_kind"]) == kind and engine.get("last_target") == target and tick - int(engine.get("last_tick", -100000)) <= DEDUP_TICKS


## Note order `kind` on `target` at `tick` in `engine` as the wing's last order.
static func note_order(engine: Dictionary, kind: String, target: Variant, tick: int) -> void:
	engine["last_kind"] = kind
	engine["last_target"] = target
	engine["last_tick"] = tick


# --- holding a point --------------------------------------------------------------------------

## The world point of slot `index` of shape `formation` frozen around `point`, with the frame
## heading `heading_deg` (whole degrees; "Hold here" keeps the leader's heading) and spacing `s`.
static func hold_slot(point: Vector2, heading_deg: float, formation: int, index: int, s: float) -> Vector2:
	return point + frame_to_world(deg_to_rad(heading_deg), slot_offset(formation, index, s))


# --- guarding a big ship ------------------------------------------------------------------------

## The half-angle (degrees) of the clear pocket behind a ship of hull definition `def`
## (an entry of Ships.HULLS): 180 minus the widest swing of its aimed guns, kept between
## GUARD_CONE_MIN and GUARD_CONE_MAX. A turret counts as its `arc`, a fixed gun as FIXED_ARC;
## automatic guns (point defence, flak) aim by themselves and are left out.
static func guard_cone(def: Dictionary) -> float:
	var widest := 0.0
	for m: Dictionary in def.get("mounts", []):
		var kind := str(m.get("type", "fixed"))
		if kind == "auto":
			continue
		var arc := FIXED_ARC if kind == "fixed" else float(m.get("arc", 0.0))
		widest = maxf(widest, arc)
	return clampf(180.0 - widest, GUARD_CONE_MIN, GUARD_CONE_MAX)


## The world point of guard slot `index` (0 to 2) behind a ward at `ward_pos` facing
## `ward_rot` (radians), of hull radius `radius` and pocket half-angle `cone_deg`: slots 0 and 1
## at 180 -/+ cone/2 degrees from the nose, GUARD_NEAR_PAD past the hull; slot 2 dead astern,
## GUARD_FAR_PAD past it.
static func guard_slot(ward_pos: Vector2, ward_rot: float, radius: float, cone_deg: float, index: int) -> Vector2:
	var angle := 180.0
	var dist := radius + GUARD_FAR_PAD
	if index == 0:
		angle = 180.0 - cone_deg * 0.5
		dist = radius + GUARD_NEAR_PAD
	elif index == 1:
		angle = 180.0 + cone_deg * 0.5
		dist = radius + GUARD_NEAR_PAD
	return ward_pos + Vector2.from_angle(ward_rot + deg_to_rad(angle)) * dist


## The world point of guard slot `index` of a mothership at `ms_pos` facing `ms_rot`, with
## `half_len` and `beam` as the Mothership holds them: slots 0 and 1 abeam to starboard and port,
## beam/2 + MOTHERSHIP_FLANK_PAD from the keel line; slot 2 astern at half_len +
## MOTHERSHIP_REAR_PAD behind the centre. (Its guns aim by themselves, so it has no pocket.)
static func mothership_slot(ms_pos: Vector2, ms_rot: float, half_len: float, beam: float, index: int) -> Vector2:
	var side := beam * 0.5 + MOTHERSHIP_FLANK_PAD
	if index == 0:
		return ms_pos + Util.starboard_of(ms_rot) * side
	if index == 1:
		return ms_pos - Util.starboard_of(ms_rot) * side
	return ms_pos - Vector2.from_angle(ms_rot) * (half_len + MOTHERSHIP_REAR_PAD)


## Is `target_pos` in the lane a ward at `ward_pos` is firing along toward `aim_point`? It is
## when the aim point is more than LANE_MIN_AIM away, the target is within LANE_DEGREES of
## the ward-to-aim line (seen from the ward) and nearer than the aim distance plus LANE_REACH_PAD.
static func in_fire_lane(ward_pos: Vector2, aim_point: Vector2, target_pos: Vector2) -> bool:
	var to_aim := aim_point - ward_pos
	var aim_dist := to_aim.length()
	if aim_dist <= LANE_MIN_AIM:
		return false
	var to_target := target_pos - ward_pos
	var d := to_target.length()
	if d >= aim_dist + LANE_REACH_PAD or d < 1.0:
		return false
	return absf(to_aim.angle_to(to_target)) < deg_to_rad(LANE_DEGREES)
