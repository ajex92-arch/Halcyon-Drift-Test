class_name ShipSystems
extends RefCounted
## WHAT THIS IS: the live parts of one ship: the health of each gun, engine pod and sensor
## that ShipParts lists for its hull, which of them are offline and when they come back. One
## is made for each ship of the four big hulls in Ship.setup(), only while Rules.parts_on().
## It keeps whole numbers only: health in units of 1/256 point, time in ticks (60 a second) that
## it counts itself, once for each call of tick(); it never reads the match clock and uses no
## random numbers.
##
## HOW IT WORKS:
##   - A hit reaches the parts in two ways (Unit.take_hit() calls both). Path 1, direct_hit():
##     a round whose true impact point lies inside an EXPOSED light part's circle hurts that
##     part through its own plate (loss = hit x W / (W + plate), the armour's own curve with no
##     floor and no glance); a COVERED light part is hit the same way once the armour section
##     over it is black. What the part cannot hold goes on as a normal hit. Path 2, share():
##     after the armour section has taken a hit, every heavy part (main gun, pod, sensor) and
##     every covered light part hosted by that section takes half of the damage that got
##     through it. A glancing hit passes nothing.
##   - A part at 0 goes offline: it takes nothing while it is out, after DELAY_TICKS it climbs
##     to CLIMB_PCT percent of its health over its climb time, and is then online again.
##     The climb runs whatever the crew does. A part's state is WORKING (half its health or
##     more), DEGRADED (less than half, above 0) or OFF (offline).
##   - The effects read state(): a gun that is OFF does not fire and a DEGRADED one fires at
##     half rate (Ship._weapons); the engine pods set the thrust, top speed and turning of the
##     ship (apply_pods, ShipStats) and pull it toward the weaker pod (pull_aside); the sensor
##     slows the turrets' swing (sensor_slew); a computer captain with a pod out stands and
##     fights for a while before it goes home (captain_holds).
##
## WHO USES IT: Ship makes and ticks it; Unit.take_hit() hits it; ShipStats, Ship._weapons,
## the two flight models and the pilot AI read its answers; PartAim and PartRings read its
## parts; the checks drive it by hand.

## State: working normally (half its health or more).
const WORKING := 0
## State: hurt (above 0 and under half its health).
const DEGRADED := 1
## State: knocked out (offline).
const OFF := 2

## The engine pods' thrust factor by state (WORKING, DEGRADED, OFF).
const POD_THRUST := [1.0, 0.7, 0.2]
## The engine pods' top speed and turning factor by state (WORKING, DEGRADED, OFF).
const POD_SPEED := [1.0, 0.85, 0.6]
## The sensor's factor on the turrets' swing rate by state (WORKING, DEGRADED, OFF).
const SENSOR_SLEW := [1.0, 0.75, 0.5]
## The pull aside as a share of the turn rate for a full thrust difference of 0.8, ...
const PULL_SHARE := 0.15
## ... the thrust difference that gives it (one pod off against one working) ...
const PULL_FULL_DIFF := 0.8
## ... and the most it can be, as a share of the turn rate: full opposite helm always wins.
const PULL_CAP := 0.30

## The part rows (ShipParts.build()), one Dictionary for each part.
var rows: Array = []
## Each part's health now, in units.
var hp := PackedInt32Array()
## 1 while the part is offline.
var offline := PackedByteArray()
## The tick at which the part went offline.
var since := PackedInt32Array()
## The ticks counted so far (one for each tick() call).
var tick_n := 0
## True when some part changed state (the ship works its numbers out again, and clears it).
var dirty := false
## The index of the left pod in rows, -1 when there is none.
var pod_l := -1
## The index of the right pod in rows, -1 when there is none.
var pod_r := -1
## The index of the sensor in rows, -1 when there is none.
var sensor := -1
## For each mount of the hull row, the index of its part in rows (-1 for none).
var mount_part := PackedInt32Array()
## The part the most recent direct hit (path 1) reached, as an index in rows, -1 for none. Tests read it.
var last_hit := -1
## The strike craft pilots now aiming at one of the parts: each entry is [pilot uid, pilot team, part
## index, match tick the aim is held until]. PilotTargeting writes it (mark_aim) and PartAim counts
## from it (friends_on); entries that have run out are dropped when read.
var aim_marks: Array = []


## Make the live parts from the rows `part_rows` (ShipParts.build()): every part whole and online.
static func make(part_rows: Array) -> ShipSystems:
	var s := ShipSystems.new()
	s.rows = part_rows
	var n := part_rows.size()
	s.hp.resize(n)
	s.offline.resize(n)
	s.since.resize(n)
	var top := -1
	for i in n:
		var row: Dictionary = part_rows[i]
		s.hp[i] = int(row["hp_max"])
		s.offline[i] = 0
		s.since[i] = 0
		match String(row["id"]):
			"pod_l":
				s.pod_l = i
			"pod_r":
				s.pod_r = i
			"sensor":
				s.sensor = i
		top = maxi(top, int(row["mount"]))
	s.mount_part.resize(top + 1)
	for k in top + 1:
		s.mount_part[k] = -1
	for i in n:
		var m := int((part_rows[i] as Dictionary)["mount"])
		if m >= 0:
			s.mount_part[m] = i
	return s


## The number of parts.
func count() -> int:
	return rows.size()


## The index of the part with id `part_id`, or -1.
func index_of(part_id: String) -> int:
	for i in rows.size():
		if String((rows[i] as Dictionary)["id"]) == part_id:
			return i
	return -1


## The state of part `i`: OFF while offline, else WORKING at half its health or more, else DEGRADED.
func state(i: int) -> int:
	if i < 0 or i >= rows.size():
		return WORKING
	if offline[i] != 0:
		return OFF
	if hp[i] * 2 >= int((rows[i] as Dictionary)["hp_max"]):
		return WORKING
	return DEGRADED


## The state of the part of mount number `mount_index` (an index in the hull row's mounts); a mount
## with no part (one a module added) is WORKING.
func mount_state(mount_index: int) -> int:
	if mount_index < 0 or mount_index >= mount_part.size():
		return WORKING
	var p := mount_part[mount_index]
	return state(p) if p >= 0 else WORKING


## True when part `i` is offline.
func is_offline(i: int) -> bool:
	return i >= 0 and i < rows.size() and offline[i] != 0


## Count one tick and bring offline parts back: after DELAY_TICKS the health climbs to CLIMB_PCT
## percent of the part's full health over its climb time, and the part is online again at the end.
## Returns true when some part came back (so the ship works its numbers out again).
func tick() -> bool:
	tick_n += 1
	var back := false
	for i in rows.size():
		if offline[i] == 0:
			continue
		var k := tick_n - since[i] - ShipParts.DELAY_TICKS
		if k <= 0:
			continue
		var row: Dictionary = rows[i]
		var climb := int(row["climb"])
		var top := int(row["hp_max"]) * ShipParts.CLIMB_PCT / 100
		if k >= climb:
			hp[i] = top
			offline[i] = 0
			back = true
		else:
			hp[i] = int(row["hp_max"]) * ShipParts.CLIMB_PCT * k / (100 * climb)
	if back:
		dirty = true
	return back


## The fraction (0..1) of the way back part `i` has climbed toward its CLIMB_PCT line while it is
## offline: 0 until the delay is over, 1 when it is online. A part that is online gives 1.
func climb_fraction(i: int) -> float:
	if i < 0 or i >= rows.size() or offline[i] == 0:
		return 1.0
	var k := tick_n - since[i] - ShipParts.DELAY_TICKS
	if k <= 0:
		return 0.0
	return minf(1.0, float(k) / float(int((rows[i] as Dictionary)["climb"])))


## Take `loss` units off part `i` (never below 0). At 0 the part goes offline now. Returns the part's
## health that was taken (at most what it had).
func _wear(i: int, loss: int) -> int:
	var before := state(i)
	var take := mini(loss, hp[i])
	hp[i] -= take
	if hp[i] <= 0:
		hp[i] = 0
		offline[i] = 1
		since[i] = tick_n
	if state(i) != before:
		dirty = true
	return take


## Path 1: a hit of `raw` damage points and strength `strength` (points), whose true impact point
## is `local` (ship frame). `host` is the armour section the hit lands on and `armour` the ship's
## sections (the breach rule: a covered light part in a black host section is hit directly). If a
## light part is hit directly, it loses raw x W / (W + plate) (all in units) and the damage that it
## could not hold goes on; returns the damage (points) that goes on to the armour: the whole hit when
## no part was hit, 0 when the part held it all, the overflow when the part went to 0.
func direct_hit(local: Vector2, host: int, armour: ArmourSections, strength: float, raw: float) -> float:
	last_hit = -1
	var pick := -1
	var best := INF
	for i in rows.size():
		var row: Dictionary = rows[i]
		if int(row["cls"]) != ShipParts.CLASS_LIGHT or offline[i] != 0:
			continue
		var at: Vector2 = row["off"]
		var d := local.distance_to(at)
		if bool(row["exposed"]):
			if d > ShipParts.PART_R_LIGHT:
				continue
		else:
			# A covered part: only when its host section is black and the hit lands in that section.
			if host < 0 or armour == null or int(row["sec"]) != host or not armour.is_black(host):
				continue
		# The nearer centre takes it, ties to the lower part id (the rows run in id order).
		if d < best:
			best = d
			pick = i
	if pick < 0:
		return raw
	var ru := int(raw * float(ArmourSections.UNITS_PER_POINT))
	if ru <= 0:
		return raw
	var wu := maxi(1, int(strength * float(ArmourSections.UNITS_PER_POINT)))
	var plate := int((rows[pick] as Dictionary)["plate"])
	var loss := ru * wu / (wu + plate)
	last_hit = pick
	var held := hp[pick]
	_wear(pick, loss)
	if loss <= held:
		return 0.0
	var over_ru := ru * (loss - held) / loss
	return float(over_ru) / float(ArmourSections.UNITS_PER_POINT)


## Path 2: the armour section `section` has just taken a hit and let `through` damage points go on to
## the hull (`glanced`: the hit only glanced). Every online heavy part, and every online covered light
## part whose section is not black, that is hosted by `section` loses SHARE_PCT percent of that damage.
## A glancing hit passes nothing.
func share(section: int, through: float, glanced: bool, armour: ArmourSections) -> void:
	if glanced or section < 0 or through <= 0.0:
		return
	var du := int(through * float(ArmourSections.UNITS_PER_POINT))
	var each := du * ShipParts.SHARE_PCT / 100
	if each <= 0:
		return
	var black := armour != null and armour.is_black(section)
	for i in rows.size():
		var row: Dictionary = rows[i]
		if offline[i] != 0 or int(row["sec"]) != section:
			continue
		var cls := int(row["cls"])
		if cls == ShipParts.CLASS_LIGHT:
			# An exposed one has its own plate and is hit directly; a covered one takes the share
			# while its section holds (once it is black, it was hit directly).
			if bool(row["exposed"]) or black:
				continue
		_wear(i, each)


## The thrust factor of the pod in state `s`.
static func pod_thrust(s: int) -> float:
	return float(POD_THRUST[s])


## The mean thrust factor of the two pods (1.0 for a ship with none).
func thrust_factor() -> float:
	if pod_l < 0 or pod_r < 0:
		return 1.0
	return (pod_thrust(state(pod_l)) + pod_thrust(state(pod_r))) * 0.5


## The mean top speed and turning factor of the two pods (1.0 for a ship with none).
func speed_factor() -> float:
	if pod_l < 0 or pod_r < 0:
		return 1.0
	return (float(POD_SPEED[state(pod_l)]) + float(POD_SPEED[state(pod_r)])) * 0.5


## Scale the engine numbers of `ship` by its pods: f_accel by the mean thrust, f_max and f_turn by the
## mean speed factor. Reverse and side thrust are not pods and keep their numbers. ShipStats calls it.
func apply_pods(ship: Ship) -> void:
	var t := thrust_factor()
	var v := speed_factor()
	if t == 1.0 and v == 1.0:
		return
	ship.f_accel *= t
	ship.f_max *= v
	ship.f_turn *= v


## The pull aside, in radians a second (positive turns the nose to starboard, the right): while the two
## pods push unequally the ship yaws toward the weaker pod's side. 0.15 of the turn rate `turn_rate` for
## a thrust difference of 0.8 and a full `throttle` (0..1), never more than 0.30 of the turn rate.
func pull_aside(turn_rate: float, throttle: float) -> float:
	if pod_l < 0 or pod_r < 0 or throttle <= 0.0:
		return 0.0
	var diff := pod_thrust(state(pod_l)) - pod_thrust(state(pod_r))
	if diff == 0.0:
		return 0.0
	var amount := PULL_SHARE * turn_rate * clampf(throttle, 0.0, 1.0) * absf(diff) / PULL_FULL_DIFF
	amount = minf(amount, PULL_CAP * turn_rate)
	# A weaker left pod pushes less on the left: the nose swings to port (negative).
	return amount if diff > 0.0 else -amount


## Note that pilot `uid` of team `team` aims at part `part` until match tick `until` (it replaces the pilot's
## older mark).
func mark_aim(uid: int, team: int, part: int, until: int) -> void:
	for m in aim_marks:
		if int(m[0]) == uid:
			m[1] = team
			m[2] = part
			m[3] = until
			return
	aim_marks.append([uid, team, part, until])


## How many pilots of team `team`, other than `uid`, are aiming at part `part` at match tick `now`.
func friends_on(part: int, team: int, uid: int, now: int) -> int:
	var n := 0
	var keep: Array = []
	for m in aim_marks:
		if int(m[3]) < now:
			continue
		keep.append(m)
		if int(m[2]) == part and int(m[1]) == team and int(m[0]) != uid:
			n += 1
	aim_marks = keep
	return n


## The factor on the turrets' swing rate from the sensor's state.
func sensor_slew() -> float:
	if sensor < 0:
		return 1.0
	return float(SENSOR_SLEW[state(sensor)])


## True while a computer captain should hold: one of the two pods is offline (including its climb back
## to the CLIMB_PCT line) and ShipParts.CAPTAIN_HOLD_S seconds have not passed since it went out. A ship
## with both pods online does not hold.
func captain_holds() -> bool:
	for p in [pod_l, pod_r]:
		if p >= 0 and offline[p] != 0 and float(tick_n - since[p]) < ShipParts.CAPTAIN_HOLD_S * 60.0:
			return true
	return false
