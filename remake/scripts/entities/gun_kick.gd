class_name GunKick
extends RefCounted
## WHAT THIS IS: the "kick" of a gun. When a gun or turret fires, its drawn barrel
## jumps back a few pixels along the way it points and slides home again, so a
## shot has weight: a Fighter's twin guns kick a little and quickly, a Battlecruiser's
## heavy turret kicks a lot and slowly. For a moment after the shot the muzzle also
## burns brighter. This script only works out how far and when; it draws nothing and
## changes nothing in the game: no push on the ship, no change of aim, no change of
## timing, no random numbers and no particles.
##
## HOW IT WORKS:
##   - Seeing a shot: nothing is announced to the painter, and the match never waits
##     for it. A gun's cooldown (`cd` of WeaponMount) jumps up when the gun fires and
##     then only counts down, so the painter looks at every gun of a unit once per
##     frame (look_all()) and a cooldown that is higher than at the last look means "it
##     just fired". A burst beam (the ion turret) is seen the same way: its `beam_on`
##     jumps up when a burst starts. Continuous beams fire all the time and do not
##     kick. The painter only READS these numbers; it never writes them.
##   - The clock: the painter notes the match time (World.time) of the frame it saw the
##     shot, so a kick follows the match: it stops when the match is paused and runs
##     slower in slow motion. The "age" of a shot is the match time since then.
##   - Looking again after a long gap (a ship that was too small to draw its guns, a
##     ship that has just come back from the shop) starts over: whatever the cooldown
##     is then is not taken for a shot.
##   - How far: the barrel is pushed back at once by the full distance and slides home
##     in `time` seconds, fast at first and slower at the end (the distance left is the
##     square of the time left). A turret's distance is in turret units
##     (TurretShapes), so it grows with the turret; it comes from TURRET, by weapon
##     class, one row each. A gun that is part of the hull picture (the nose guns of
##     the Scout and the Fighter, which never turn) kicks by a distance in the hull's
##     36-unit design space, from FIXED, by weapon.
##   - The muzzle flash: for FLASH_TIME after the shot the tip of a turret's barrel
##     (its coloured tip) and a nose gun are drawn nearly white. It is the same
##     triangles in other colours: no emitter, no extra shape.
##   - Drawn by: TurretPaint (the turrets of ships and structures) and AurelianPaint
##     (the nose guns of the amber hulls). A gun that is not drawn as a separate piece
##     cannot kick: the red team's nose guns are not drawn at all, nor are the guns
##     of minions, and the red mothership draws its guns as dots.
##   - Test only: set_on(false) switches the kick off (every gun sits still), so the
##     hull gallery can measure what it costs in a match.
##
## WHO USES IT: ShipVisual and UnitVisual each keep one GunKick, call look_all() with
## the unit's guns once per frame and hand it to TurretPaint (and, for a ship, ask
## AurelianPaint for the nose guns); tests/gun_kick_check.gd checks the table and the
## seeing of shots; the hull gallery's kick strip (tests/lib/gallery_kick.gd) shows it.

## How far each class of turret is pushed back, in turret units, and how long it takes to
## slide home, in seconds. Bigger guns kick further and slower: point defense and the
## tail gun the least, the heavy cannon the most.
const TURRET := {
	"pd": {"dist": 0.35, "time": 0.10},
	"tail": {"dist": 0.35, "time": 0.10},
	"light": {"dist": 0.55, "time": 0.16},
	"flak": {"dist": 0.55, "time": 0.16},
	"torp": {"dist": 0.70, "time": 0.26},
	"ion": {"dist": 0.80, "time": 0.30},
	"heavy": {"dist": 1.10, "time": 0.34},
}
## How far the nose guns that are part of a hull's picture are pushed back, in the hull's
## 36-unit design units, and how long they take to slide home, in seconds, by weapon id.
## A Fighter's twin cannons kick a little more than the Scout's single gun.
const FIXED := {
	"scout_gun": {"dist": 1.6, "time": 0.10},
	"fighter_cannon": {"dist": 2.0, "time": 0.12},
}
## How long, in seconds after a shot, the muzzle burns brighter.
const FLASH_TIME := 0.04
## How white the muzzle gets during the flash, 0 to 1 (1 = white).
const FLASH_WHITE := 0.8
## No kick lasts longer than this many seconds (a check keeps every table row under it).
const MAX_TIME := 0.4
## If more than this many seconds of match time pass between two looks at the same
## unit, the next look starts over (see HOW IT WORKS).
const RESYNC_GAP := 0.5
## "No shot yet" as a number of seconds (far longer than any kick).
const NEVER := 1.0e9

## True = guns kick (always, in play); false only while the gallery test measures.
static var _on := true

## Seconds since each gun last fired, by the gun's place in the unit's list of guns, as of
## the last look_all() (NEVER if it has not fired since the painter began looking).
var ages := PackedFloat64Array()
## The weapon id of the first fixed gun of the unit that has a row in FIXED ("" if none).
var fixed_weapon := ""
## Seconds since that gun last fired (NEVER if it has not, or if there is no such gun).
var fixed_age := NEVER

## The cooldown of each gun at the last look.
var _seen_cd := PackedFloat64Array()
## The burst time of each beam at the last look.
var _seen_burst := PackedFloat64Array()
## The match time when each gun was last seen firing (-NEVER if not).
var _t0 := PackedFloat64Array()
## The match time of the last look_all().
var _last_look := -NEVER


## Do guns kick?
static func is_on() -> bool:
	return _on


## Switch the kick on or off while the game runs (tests only).
static func set_on(is_on: bool) -> void:
	_on = is_on


## How far, in turret units, the barrel of a turret of weapon class `cls` ("pd", "flak",
## "light", "heavy", "ion", "tail" or "torp") is pushed back `age` seconds after its shot:
## 0 when the shot is long ago.
static func turret_back(cls: String, age: float) -> float:
	if age < 0.0 or age >= MAX_TIME:
		return 0.0
	var row: Dictionary = TURRET.get(cls, {})
	return _slide(row, age)


## How far, in design units, the nose gun of weapon `weapon_id` is pushed back `age`
## seconds after its shot: 0 when the shot is long ago or the weapon has no row in FIXED.
static func fixed_back(weapon_id: String, age: float) -> float:
	if age < 0.0 or age >= MAX_TIME:
		return 0.0
	var row: Dictionary = FIXED.get(weapon_id, {})
	return _slide(row, age)


## Does a muzzle burn brighter `age` seconds after its shot?
static func is_flash(age: float) -> bool:
	return age >= 0.0 and age < FLASH_TIME


## `row` ({"dist", "time"}) at `age` seconds: the full distance at the shot, then less and
## less (the square of the time left) until it is 0 after "time" seconds. An empty row is 0.
static func _slide(row: Dictionary, age: float) -> float:
	if row.is_empty():
		return 0.0
	var span: float = row["time"]
	if age >= span:
		return 0.0
	var left := 1.0 - age / span
	return float(row["dist"]) * left * left


## Look at all the guns `mounts` of one unit at match time `now` and note which ones just
## fired, so ages (and fixed_weapon, fixed_age) are right for this frame. Call it once per
## frame, before drawing the guns. It reads the guns' cooldowns and bursts and changes
## nothing in them.
func look_all(mounts: Array, now: float) -> void:
	var n := mounts.size()
	if ages.size() < n:
		_grow(n)
	fixed_weapon = ""
	fixed_age = NEVER
	# Kick off (the gallery's cost test): every gun sits still.
	if not _on:
		for i in n:
			ages[i] = NEVER
		return
	# A long gap, or the clock gone back (a new match): start over, no gun has fired yet.
	var restart := now - _last_look > RESYNC_GAP or now < _last_look
	_last_look = now
	for i in n:
		var m: WeaponMount = mounts[i]
		if restart:
			_t0[i] = -NEVER
			_seen_cd[i] = m.cd
			_seen_burst[i] = m.beam_on
		else:
			# A cooldown higher than at the last look: the gun fired since.
			if m.cd > _seen_cd[i]:
				_t0[i] = now
			_seen_cd[i] = m.cd
			# A burst beam: a burst time higher than at the last look: a burst began.
			if m.is_beam:
				if m.beam_on > _seen_burst[i]:
					_t0[i] = now
				_seen_burst[i] = m.beam_on
		var age: float = now - _t0[i]
		ages[i] = age
		if fixed_weapon == "" and m.mount_type == WeaponMount.FIXED and FIXED.has(m.weapon_id):
			fixed_weapon = m.weapon_id
			fixed_age = age


## Make room for `n` guns.
func _grow(n: int) -> void:
	var old := ages.size()
	ages.resize(n)
	_seen_cd.resize(n)
	_seen_burst.resize(n)
	_t0.resize(n)
	for i in range(old, n):
		ages[i] = NEVER
		_seen_cd[i] = 0.0
		_seen_burst[i] = 0.0
		_t0[i] = -NEVER
