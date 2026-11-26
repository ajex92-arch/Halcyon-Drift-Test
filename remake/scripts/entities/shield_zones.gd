class_name ShieldZones
extends RefCounted
## WHAT THIS IS: a unit's energy shield, split into four zones: front, rear,
## left and right. A hit only drains the zone on the side it came from.
## DESIGN.md A5.
##
## HOW IT WORKS:
##   - The shield has one total size (`max_total`). The "focus" setting
##     decides how that total is shared between the four zones
##     (Rules.FOCUS_WEIGHTS): Balanced gives each zone 25%; focusing Front
##     gives the front 50%, the rear 10% and each side 20% (and so on for
##     Rear, Left and Right). A zone's share is its "cap" (its maximum). The two
##     capitals carry their own table (`table`, set by use_table() from the hull row's
##     `shield_weights`): Balanced 15% front, 15% rear and 35% on each side, Front 30, 10, 30,
##     30, Rear 10, 30, 30, 30, Left 10, 10, 55, 25 and Right 10, 10, 25, 55: thin ends.
##   - A hit drains the zone facing the attacker (absorb()). A hit that breaks
##     the zone loses its spill-over (it does not reach the hull) and the zone is
##     immune for a gate (gate_seconds(): 0.33 s on the smallest shields up to 2.25 s
##     on the biggest, by the shield's size); hits on it meanwhile are swallowed. An
##     ion hit breaks a zone as before and starts no gate. A single pool has no gate:
##     what it can't hold goes on to the hull.
##   - The shield points a zone soaks are added up in `last_blocked`, which the owning
##     ship reads once a tick to load its battery with hard energy (and maybe overload).
##     While the ship is overloaded or venting the shield is `dark`: absorb() lets every
##     hit pass whole and changes nothing.
##   - Changing focus doesn't create or lose shield: the shield you have
##     right now is moved into the new shares (set_focus()). On a hull with a swing time
##     (`swing_s`, the capitals' 3.0 s) the caps move in a straight line over that time
##     instead, and each tick of the swing trims the zones above their cap and shares the
##     excess among the zones with room (none is lost unless every zone is full); `caps_stamp`
##     goes up whenever any cap changes, so a drawing that keeps the caps knows to look again.
##   - After `delay` seconds without a hit, the shield refills (tick()),
##     topping up the emptiest zones the most.
##   - `single = true` turns it into one shared pool with no zones (minions,
##     turrets, repair bays and the mothership use this); only zone 0 holds
##     anything.
##
## WHO USES IT: every Unit has a `shields` (or null). Ship, Minion, Turret,
## RepairBay and Mothership create and set it up. Unit.take_hit() calls
## zone_for_local() and absorb(); each owner calls tick() every tick; Ship
## calls set_focus() when the pilot asks; Ship.recompute_stats() and the
## Mothership call set_max() when upgrades change the size. ShipVisual and
## the HUD draw `values`, cap() and fraction(); PlayerController and the AI
## pilots read `focus` (the AI also uses zone_for_local()).

## The total shield size over all four zones, in shield points.
var max_total := 0.0
## The shield points in each zone right now, in the order front, rear,
## left, right (Rules.ZONE_FRONT, ZONE_REAR, ZONE_LEFT, ZONE_RIGHT = 0..3).
var values := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## The focus setting: one of Rules.FOCUS_BALANCED, FOCUS_FRONT, FOCUS_REAR,
## FOCUS_LEFT or FOCUS_RIGHT (0..4).
var focus := Rules.FOCUS_BALANCED
## True for one shared pool with no zones (only values[0] is used).
var single := false
## How fast the shield refills, in shield points per second.
var regen := 0.0
## Seconds without a hit before refilling starts.
var delay := 3.5
## The fraction (0..1) of each hit the shield shrugs off (0.9 at most,
## counting any extra resistance passed to absorb()).
var resist := 0.0
## Seconds since the last hit (starts high: "not hit for ages").
var since_hit := 999.0
## Per zone: seconds left on the "this zone just broke" flash (set to 0.4 s
## when a zone is emptied; only for drawing).
var flash := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Per zone: seconds left on the gate (the zone is immune) after a hit broke it
## (see absorb() and gate_seconds()). 0 = no gate. Zoned shields only.
var gate_left := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## True while the shield is dark (its ship is overloaded or venting): absorb() lets every
## hit pass whole and changes nothing. Ship sets it each tick.
var dark := false
## The shield points blocked since the owner last read it (a running sum over every hit,
## resist applied; swallowed and passed hits add nothing). Ship loads it into the battery
## once a tick and sets it back to 0.
var last_blocked := 0.0
## The shares of the total that the focus settings give the zones: rows in the order Balanced,
## Front, Rear, Left, Right, each [front, rear, left, right]. Rules.FOCUS_WEIGHTS unless
## use_table() set a hull's own.
var table: Array = Rules.FOCUS_WEIGHTS
## How long a focus change takes to move the caps, in seconds (0.0 = at once).
var swing_s := 0.0
## Seconds left of the running swing (0.0 = not swinging).
var swing_left := 0.0
## The four zone shares (front, rear, left, right) the running swing started from.
var from_w := PackedFloat32Array([0.25, 0.25, 0.25, 0.25])
## Goes up by one every time any cap changes (a focus change, each tick of a swing, the end
## of a swing, fill()): a drawing that keeps the caps looks again when it moves.
var caps_stamp := 0

## The shortest gate, in seconds: the gate of a shield with GATE_POOL_LO points or fewer
## (Warframe's floor, 20 ticks of 60).
const GATE_MIN_S := 0.33
## The longest gate, in seconds: the gate of a shield with GATE_POOL_HI points or more
## (Warframe's top, 135 ticks of 60).
const GATE_MAX_S := 2.25
## The shield size (max_total) that gets the shortest gate: a Scout's pool.
const GATE_POOL_LO := 120.0
## The shield size (max_total) that gets the longest gate: a Battlecruiser's pool.
const GATE_POOL_HI := 3000.0


## Set up a full shield: `total` shield points, refilling at `regen_rate`
## per second after `delay_s` seconds without a hit. `single_pool` = one
## shared pool with no zones.
func setup(total: float, regen_rate: float, delay_s: float, single_pool: bool = false) -> void:
	max_total = total
	regen = regen_rate
	delay = delay_s
	single = single_pool
	fill()


## The most shield zone `zone` (0..3) can hold with the current focus. A
## single pool keeps everything in zone 0.
func cap(zone: int) -> float:
	if single:
		return max_total if zone == 0 else 0.0
	if swing_left > 0.0 and swing_s > 0.0:
		return max_total * lerpf(from_w[zone], float(table[focus][zone]), 1.0 - swing_left / swing_s)
	return max_total * float(table[focus][zone])


## The four zone shares (front, rear, left, right) in force now: the `table` row of `focus`,
## or, while a swing runs, the straight line from the shares it started from (`from_w`) to
## that row, by how much of `swing_s` has passed.
func weights_now() -> PackedFloat32Array:
	var row: Array = table[focus]
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var t := 1.0
	if swing_left > 0.0 and swing_s > 0.0:
		t = 1.0 - swing_left / swing_s
	for z in 4:
		out[z] = lerpf(from_w[z], float(row[z]), t) if t < 1.0 else float(row[z])
	return out


## Give this shield its own share table `rows` (the shape of Rules.FOCUS_WEIGHTS) and a swing
## time of `swing_seconds` (0.0 = a focus change moves the caps at once). Starts the swing's
## "from" shares at the table's Balanced row and fills the shield to the new caps. Ship.setup()
## calls it right after setup() for a hull row that has `shield_weights`.
func use_table(rows: Array, swing_seconds: float) -> void:
	table = rows
	swing_s = swing_seconds
	var bal: Array = rows[Rules.FOCUS_BALANCED]
	from_w = PackedFloat32Array([float(bal[0]), float(bal[1]), float(bal[2]), float(bal[3])])
	fill()


## Shield points left over all four zones.
func total() -> float:
	return values[0] + values[1] + values[2] + values[3]


## How full the shield is, as a 0..1 fraction (0 if it has no size).
func fraction() -> float:
	return total() / max_total if max_total > 0.0 else 0.0


## Fill every zone to its cap (and end every gate and any running swing: a new or launched
## ship starts whole).
func fill() -> void:
	swing_left = 0.0
	caps_stamp += 1
	for z in 4:
		values[z] = cap(z)
		gate_left[z] = 0.0


## Change the total size (e.g. a module or upgrade) keeping the same
## fraction full: a half-full shield stays half full.
func set_max(new_total: float) -> void:
	var f := fraction() if max_total > 0.0 else 1.0
	max_total = new_total
	for z in 4:
		values[z] = cap(z) * f


## Which zone a hit lands on. `local` is where the attacker is "in the
## ship's own frame": as if the ship were facing right, so +x is ahead and
## +y is to the right (starboard). We measure the attacker's angle: within
## 45 degrees (PI/4 radians) of the nose is the front, within 45 degrees of
## the tail is the rear, and the rest is the left or right side.
static func zone_for_local(local: Vector2) -> int:
	var a := atan2(local.y, local.x)
	if absf(a) <= PI * 0.25:
		return Rules.ZONE_FRONT
	if absf(a) >= PI * 0.75:
		return Rules.ZONE_REAR
	return Rules.ZONE_LEFT if a < 0.0 else Rules.ZONE_RIGHT


## Soak `raw` damage on zone `zone`. Resistance (our `resist` plus
## `extra_resist`, at most 0.9 together) shrinks the hit before it drains
## the zone. Returns the raw damage left over for the hull.
## SHIELD GATING (zoned shields only): while a zone's gate runs (gate_left) it is
## immune: a hit on it is swallowed whole (the zone does not change and nothing
## reaches the hull). A hit that breaks a zone (it could not hold it all) loses its
## spill-over (the hull gets 0) and starts that zone's gate (gate_seconds()), unless
## `can_gate` is false (an ion hit: it breaks a zone as before and starts no gate). A
## hit that drains a zone exactly to 0 starts no gate. A single pool never gates.
## BLOCKED POINTS: the shield points a hit drains (resist applied) are added to
## `last_blocked`, which the owning ship reads once a tick (hard energy). A dark shield
## (`dark`) passes the hit back whole and changes nothing but the refill wait.
func absorb(zone: int, raw: float, extra_resist: float = 0.0, can_gate: bool = true) -> float:
	since_hit = 0.0
	# A dark shield (the ship is overloaded or venting) lets the hit through whole.
	if dark:
		return raw
	var zi := 0 if single else zone
	# A running gate swallows the hit (checked before the empty-zone line: a broken
	# zone is empty).
	if not single and gate_left[zi] > 0.0:
		return 0.0
	var z := values[zi]
	# An empty zone lets the whole hit through.
	if z <= 0.0:
		return raw
	# Shrink the hit by our resistance. If the zone can hold it all, it
	# drains and nothing reaches the hull.
	var r := 1.0 - clampf(resist + extra_resist, 0.0, 0.9)
	var eff := raw * r
	if eff <= z:
		values[zi] = z - eff
		_note_blocked(eff, can_gate)
		return 0.0
	# Too big: the zone breaks (and flashes).
	values[zi] = 0.0
	flash[zi] = 0.4
	_note_blocked(z, can_gate)
	# A zoned shield drops the spill-over and starts the gate (an ion hit starts none
	# and keeps the spill, which Unit.take_hit zeroes for ion anyway).
	if not single and can_gate:
		gate_left[zi] = gate_seconds()
		return 0.0
	# Otherwise the hull gets the part of the raw hit the zone couldn't cover
	# (z / r is how much raw damage the zone's points were worth).
	return raw - z / r


## Add `points` of soaked shield damage to `last_blocked`. A zoned shield only (a single pool
## has no owner that reads it); an ion hit (`can_gate` false) adds only when
## OverloadRules.ION_LOADS_HARD is true.
func _note_blocked(points: float, can_gate: bool) -> void:
	if single:
		return
	if not can_gate and not OverloadRules.ION_LOADS_HARD:
		return
	last_blocked += points


## How long, in seconds, a zone is immune after a hit breaks it: a straight line
## from GATE_MIN_S (a shield of GATE_POOL_LO points or fewer) to GATE_MAX_S (GATE_POOL_HI
## or more) on the shield's total size (max_total) as it is now. The research gives only
## the two ends (20 to 135 ticks); the straight line between them is a design choice.
## Gear or research that changes max_total (set_max) changes the next gate, never a
## running one.
func gate_seconds() -> float:
	var t := clampf((max_total - GATE_POOL_LO) / (GATE_POOL_HI - GATE_POOL_LO), 0.0, 1.0)
	return GATE_MIN_S + t * (GATE_MAX_S - GATE_MIN_S)


## Switch to focus setting `f`. A hull with a swing time (`swing_s` above 0.0) starts a swing:
## the caps move to the new row in a straight line over `swing_s` seconds, from the shares in
## force at this moment (so a change in mid-swing starts from the blended caps), and no shield
## is moved here (tick() trims and re-shares it as the caps move). Any other hull moves the
## shield we have right now into the new shares at once.
func set_focus(f: int) -> void:
	if single or f == focus:
		return
	if swing_s > 0.0:
		from_w = weights_now()
		focus = f
		swing_left = swing_s
		caps_stamp += 1
		return
	# Step 1: share the current total out by the new weights (no zone above
	# its new cap) and count what didn't fit.
	var t := total()
	focus = f
	caps_stamp += 1
	var left := t
	for z in 4:
		var v := minf(cap(z), t * float(table[f][z]))
		values[z] = v
		left -= v
	# Step 2: anything that didn't fit (capped zones) tops up the others.
	for z in 4:
		if left <= 0.0:
			break
		var room := cap(z) - values[z]
		var add := minf(room, left)
		values[z] += add
		left -= add


## Refill for one tick of `dt` seconds. `mult` multiplies the refill speed
## (energy routing, gear and waypoint bonuses); `delay_bonus` adds seconds
## to the wait (gear). The wait is never shorter than 0.5 s.
func tick(dt: float, mult: float, delay_bonus: float = 0.0) -> void:
	since_hit += dt
	if single:
		# Cheap path for minions, turrets, bays and the mothership: one
		# shared pool.
		if since_hit >= maxf(0.5, delay + delay_bonus) and values[0] < max_total and regen > 0.0:
			values[0] = minf(max_total, values[0] + regen * mult * dt)
		return
	# Count down the "zone broke" flashes and the gates (in seconds, with `dt`, so
	# the world speed does not change how long a gate is).
	for z in 4:
		if flash[z] > 0.0:
			flash[z] = maxf(0.0, flash[z] - dt)
		if gate_left[z] > 0.0:
			gate_left[z] = maxf(0.0, gate_left[z] - dt)
	# A running swing: count it down in seconds, then ONE re-share step with this tick's caps
	# (it keeps running during the wait after a hit).
	if swing_left > 0.0:
		swing_left = maxf(0.0, swing_left - dt)
		caps_stamp += 1
		_reshare()
	# Still waiting after the last hit (or no refill at all)? Then stop.
	if since_hit < maxf(0.5, delay + delay_bonus) or regen <= 0.0:
		return
	var amount := regen * mult * dt
	# Fill zones in proportion to their missing shield: add up what is
	# missing, then give every zone the same share k (0..1) of its gap.
	var missing := 0.0
	for z in 4:
		missing += maxf(0.0, cap(z) - values[z])
	if missing <= 0.0:
		return
	var k := minf(1.0, amount / missing)
	for z in 4:
		values[z] += maxf(0.0, cap(z) - values[z]) * k


## One step of a swing: every zone above its cap drops to the cap, and the excess is added to
## the zones below their cap in proportion to their room (the way the refill shares out, with
## the excess as the amount). No shield is made or lost unless every zone is full.
func _reshare() -> void:
	var excess := 0.0
	for z in 4:
		var c := cap(z)
		if values[z] > c:
			var held := values[z]
			values[z] = c
			excess += held - values[z]
	if excess <= 0.0:
		return
	var room := 0.0
	var widest := 0
	for z in 4:
		var r := maxf(0.0, cap(z) - values[z])
		room += r
		if r > maxf(0.0, cap(widest) - values[widest]):
			widest = z
	if room <= 0.0:
		return
	var k := minf(1.0, excess / room)
	var added := 0.0
	for z in 4:
		var before := values[z]
		values[z] += maxf(0.0, cap(z) - values[z]) * k
		added += values[z] - before
	# Whatever the 32-bit rounding left over goes to the zone with the most room, so no shield
	# is made or lost step by step.
	if k < 1.0:
		values[widest] += excess - added
