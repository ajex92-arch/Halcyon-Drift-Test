class_name ArmourSections
extends RefCounted
## WHAT THIS IS: the armour of one ship, kept in sections. Each section sits
## inside one of the four shield zones (front, rear, left, right), has its own
## armour points, and knows where on the hull it is. This file holds the layout
## (how many sections, how big each is) and the pick (which section an impact
## point lands on). It keeps its state in whole numbers only: no decimals, no
## random numbers.
##
## HOW IT WORKS:
##   - A hull's row in ships.gd says `sections: [front, rear, side]`: how many
##     sections the front zone, the rear zone and each side zone hold (a
##     Battlecruiser has [2, 2, 4]: 12 sections). The optional `section_weights`
##     list gives each section a weight (default: all equal); the sections are
##     numbered front first, then rear, left, right, and inside a zone the front
##     and rear sections run from the ship's left to its right, the side
##     sections from the nose to the tail.
##   - One armour point is 256 units. All the sections of a ship together hold
##     ARMOUR_SHARE_PCT percent of the ship's hull points, shared out by weight. When the
##     hull grows or shrinks (research, gear, plating) resize_pool() keeps that share and
##     each section keeps the same share of its armour; a black section stays black.
##   - The armour value A is the hull row's `armour` plus what the pilot's gear adds
##     (gear_a(): armour points that make a shot of the Fighter cannon lose the item's
##     resist at full armour); a hull's gear never cuts the hull after the armour.
##   - A zone's 90 degrees are split evenly between its sections. The pick
##     (section_at) first takes the impact point measured from the hull's spine
##     (a line along the ship's length; its length is the hull's `spine` number,
##     0 for a plain circle), then finds the zone the way the shields do, then
##     tests the point against the zone's section borders with whole-number
##     cross products. A point exactly on a border goes to the lower number.
##   - A unit whose row has no `sections` has no ArmourSections at all (it is
##     null on the unit) and takes hull hits as it always did.
##   - Each section reports one of four states by the share of its armour it has
##     lost (the look of the damage art and of the HUD ring); the state is a look only,
##     the armour works until the section is black (no armour left).
##   - Each section also counts its wound: the hull damage that came through it and
##     is not repaired yet. The hull stays one number; the counters are read back
##     rescaled so they always add up to the hull the ship is missing. Repairing the
##     armour and repairing the hull are two separate calls.
##
## WHO USES IT: Ship makes one in setup() from its hull's row. Unit reads it in
## take_hit(). The HUD (ShipStatus) draws the sections' states, and the tests read the
## layout and the section numbers.

## How many armour units make one armour point.
const UNITS_PER_POINT := 256
## The share of the hull's points, in percent, that all the sections together hold.
const ARMOUR_SHARE_PCT := 60
## How finely the impact point is cut into whole numbers for the pick: sixteenths
## of a world unit.
const PICK_SCALE := 16.0
## The slopes (tangent of the border angle, times 256) that split a zone of 90
## degrees evenly into `n` sections, for n = 1 to 6, running with the angle from
## one edge of the zone to the other. A slope of 106 is 22.5 degrees, 69 is 15.
const BORDERS := {
	1: [],
	2: [0],
	3: [-69, 69],
	4: [-106, 0, 106],
	5: [-130, -41, 41, 130],
	6: [-148, -69, 0, 69, 148],
}

## The four states of a section, by the share of its armour lost: undamaged below 25
## percent, lightly damaged below 50, heavily damaged below 90, broken through from 90.
const STATE_UNDAMAGED := 0
## State: between a quarter and a half of the armour lost.
const STATE_LIGHT := 1
## State: between a half and nine tenths of the armour lost.
const STATE_HEAVY := 2
## State: nine tenths or more of the armour lost. A look only: the armour still works until it is all gone.
const STATE_BROKEN := 3
## The share of the armour lost, in percent, at which each state above the first begins.
const STATE_FROM_PCT := [25, 50, 90]
## The names of the four states, in the order of the STATE_ numbers.
const STATE_NAMES := ["undamaged", "lightly damaged", "heavily damaged", "broken through"]
## The health, in percent of a part, that repair drones bring a part up to before they
## mend the hull. Not set (-1): the drones' design names it.
const OPERATIONAL_HEALTH_PCT := -1

## The number of sections in each zone, in the order front, rear, left, right.
var zone_count := PackedInt32Array([0, 0, 0, 0])
## The number of the first section of each zone, in the same order.
var zone_first := PackedInt32Array([0, 0, 0, 0])
## The total number of sections.
var count := 0
## The armour a section holds when it is whole, in units, one entry per section.
var a_max := PackedInt32Array()
## The armour a section holds now, in units, one entry per section.
var a_hp := PackedInt32Array()
## The weight of each section: how big a share of the armour it holds.
var weight := PackedInt32Array()
## The hull damage that has come through each section and is not repaired yet, in
## units (read it through wounds(), which keeps the sum right).
var wound := PackedInt32Array()
## The match time (seconds) at which each section turned black, or -999 for never; the
## HUD pulses a section for a moment after it.
var breach_time := PackedFloat32Array()
## The length of the hull's spine, in world units (0 = the hull is a circle).
var spine := 0.0
## The hull's armour value A, in whole points: how hard a shot must hit to get
## through a whole section. Read from the row's `armour` (0 = no reduction).
var armour_value := 0
## The part of armour_value that comes from the hull's own row, in whole points.
var armour_base := 0
## The part of armour_value that the pilot's gear adds, in whole points (0 = no gear).
var armour_gear := 0
## True when the last hit() only glanced (the section was whole enough to turn the shot and
## wore nothing). The parts behind the section read it: a glancing hit passes nothing to them.
var last_glance := false

## The weapon whose strength W is the small gun gear is measured against: gear of resist g
## adds the armour that makes a shot of this gun lose a share g at full armour.
const GEAR_REF_WEAPON := "fighter_cannon"


## Build the sections of a hull from its row `def` (ships.gd), for a unit whose
## hull is `hull_points`. Returns null when the row has no `sections`, or when
## they hold no section at all.
static func make(def: Dictionary, hull_points: float) -> ArmourSections:
	if not def.has("sections"):
		return null
	var layout: Array = def["sections"]
	var a := ArmourSections.new()
	var side := int(layout[2])
	# The counts per zone: front, rear, left, right.
	var counts := [int(layout[0]), int(layout[1]), side, side]
	var n := 0
	for z in 4:
		a.zone_count[z] = counts[z]
		a.zone_first[z] = n
		n += counts[z]
	if n <= 0:
		return null
	a.count = n
	a.spine = float(def.get("spine", 0.0))
	a.armour_base = int(def.get("armour", 0))
	a.armour_value = a.armour_base
	# The weights: the row's list when it names one per section, else all equal.
	var listed: Array = def.get("section_weights", [])
	var total_w := 0
	a.weight.resize(n)
	for i in n:
		a.weight[i] = maxi(1, int(listed[i])) if listed.size() == n else 1
		total_w += a.weight[i]
	# One whole pool of units, shared out by weight.
	var pool := int(hull_points * float(ARMOUR_SHARE_PCT) * float(UNITS_PER_POINT) / 100.0)
	a.a_max.resize(n)
	a.a_hp.resize(n)
	a.wound.resize(n)
	a.breach_time.resize(n)
	for i in n:
		a.a_max[i] = pool * a.weight[i] / total_w
		a.a_hp[i] = a.a_max[i]
		a.wound[i] = 0
		a.breach_time[i] = -999.0
	return a


## The armour points one gear item of resist `g` (a share, 0.08 = 8%) adds to a hull whose
## own armour is `a`: the whole number that makes a shot of the reference gun (W) lose a
## share g at full armour, round((W + a) x g / (1 - g)). 0 for no gear (g <= 0).
static func gear_a(a: int, g: float) -> int:
	if g <= 0.0:
		return 0
	var gg := minf(g, 0.75)
	var w := float(Weapons.WEAPONS[GEAR_REF_WEAPON]["dmg"])
	return roundi((w + float(a)) * gg / (1.0 - gg))


## Set the armour the pilot's gear adds, in whole points: armour_value becomes the hull's
## own plus this. At black (a_hp 0) the sum still counts for nothing, since the curve
## reads A x a_hp / a_max.
func set_gear(points: int) -> void:
	armour_gear = maxi(0, points)
	armour_value = armour_base + armour_gear


## Make the pool follow a changed hull: all the sections together hold ARMOUR_SHARE_PCT
## percent of `hull_points`, shared out by weight, and each section keeps the same share
## of its armour it had (as the hull keeps its share when hull_max changes). A black
## section stays black; a section with any armour left keeps at least one unit.
func resize_pool(hull_points: float) -> void:
	if count <= 0:
		return
	var total_w := 0
	for i in count:
		total_w += weight[i]
	var pool := int(hull_points * float(ARMOUR_SHARE_PCT) * float(UNITS_PER_POINT) / 100.0)
	for i in count:
		var old_max := a_max[i]
		var new_max := pool * weight[i] / total_w
		if new_max == old_max:
			continue
		var held := a_hp[i]
		if held > 0 and old_max > 0:
			held = maxi(1, held * new_max / old_max)
		held = mini(held, new_max)
		a_max[i] = new_max
		a_hp[i] = held


## The share, in percent, of the damage that reaches the hull that the hull always
## takes, however thick the armour (the floor of the curve). It binds only against
## heavy armour: a section that is black has no armour and no floor. A shot the curve
## would cut below this floor glances (the hull takes the floor, the section wears nothing).
const FLOOR_PCT := 15

## Hit section `i` with a shot of strength `strength` (damage points; a beam counts
## half its damage per second), of which `raw` damage points reach the hull after
## the shield. Returns the damage the hull takes, in damage points, and wears the
## section by the damage the curve lets through (`now` is the match time, kept when the
## section turns black) and counts the hull damage in the section's wound.
##   A_eff = A x a_hp / a_max        (0 when the section is black)
##   keep  = W x 256 / (W + A_eff)
##   by_curve = R x keep / 256
##   floor    = max(15 percent of R, 1 unit)
##   hull  = max(by_curve, floor), at most R
##   wear  = by_curve                (at most what the section still holds)
## All of it is whole numbers in units (1/256 point). A black section has A_eff 0,
## so every hit from any weapon, however weak, passes whole: no floor, no cut.
## GLANCING (DESIGN.md armour section): a shot the curve would cut below the floor
## (by_curve < floor) on a section that still has armour glances: the hull takes the
## floor and the section wears NOTHING (a_hp stays). No dice and no angle. The calibre is
## the shot's strength W (there is no separate calibre field: `strength` is the
## DamageInfo.strength, or the hit's own amount when that is 0); the thickness is A_eff.
## Before the 256ths rounding a shot glances on a whole section when
## W x 100 < 15 x (W + A_eff), that is W < 0.176 x A. A Battlecruiser (A 75) glances
## shots under W 13.2 (the Fighter cannon 5.5 and the 12-point guns glance; the
## Dreadnought gun 15 and the Lance, strength 17, do not); a Destroyer (A 50) under 8.8; a
## Flak Frigate (A 25) under 4.4; an Ion Frigate (A 22) under 3.9; light craft (A 1 to 3)
## never. A section worn down by heavy shots has a smaller A_eff and glances less, so small
## guns can finish it. A black section never glances (by_curve = R, at least the floor).
func hit(i: int, strength: float, raw: float, now: float = -999.0) -> float:
	last_glance = false
	var ru := int(raw * float(UNITS_PER_POINT))
	if ru <= 0 or i < 0 or i >= count:
		return raw
	var wu := maxi(1, int(strength * float(UNITS_PER_POINT)))
	var a_eff := 0
	if a_max[i] > 0:
		a_eff = armour_value * UNITS_PER_POINT * a_hp[i] / a_max[i]
	var keep := wu * 256 / (wu + a_eff)
	var by_curve := ru * keep / 256
	var floor_u := maxi(ru * FLOOR_PCT / 100, 1)
	var held := a_hp[i]
	var hull_u := mini(ru, maxi(by_curve, floor_u))
	if held > 0 and by_curve < floor_u:
		# A glancing shot: the floor goes through and the section is not worn.
		hull_u = mini(ru, floor_u)
		last_glance = true
	else:
		a_hp[i] -= mini(by_curve, held)
		if held > 0 and a_hp[i] == 0:
			breach_time[i] = now
	wound[i] += hull_u
	if hull_u >= ru:
		return raw
	return raw * float(hull_u) / float(ru)


## The share of section `i`'s armour that is lost, in whole percent (0 = whole, 100 =
## black).
func damage_pct(i: int) -> int:
	if i < 0 or i >= count or a_max[i] <= 0:
		return 0
	return (a_max[i] - a_hp[i]) * 100 / a_max[i]


## The state of section `i`: STATE_UNDAMAGED, STATE_LIGHT, STATE_HEAVY or STATE_BROKEN,
## by the share of its armour lost. It is a look only; is_black() says whether the
## section has no armour left.
func state_of(i: int) -> int:
	var lost := damage_pct(i)
	var s := STATE_UNDAMAGED
	for k in STATE_FROM_PCT.size():
		if lost >= int(STATE_FROM_PCT[k]):
			s = k + 1
	return s


## The states of all the sections, one entry per section in section order: what the
## hull's damage art reads.
func states() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = state_of(i)
	return out


## True when section `i` is black: breached, with no armour left (every hit passes
## whole through it).
func is_black(i: int) -> bool:
	return i >= 0 and i < count and a_hp[i] <= 0


## The stretch of the hull section `i` covers, as two angles in radians measured
## from the nose in the ship's own frame (atan2 of y over x, so +PI / 2 is the right
## side): x is the start and y the end, start before end. The sections of a zone share
## its 90 degrees evenly. The HUD ring draws the section between these two angles.
func section_span(i: int) -> Vector2:
	for z in 4:
		var n := zone_count[z]
		var k := i - zone_first[z]
		if k < 0 or k >= n:
			continue
		var step := PI * 0.5 / float(n)
		var lo := 0.0
		match z:
			Rules.ZONE_FRONT:
				lo = -PI * 0.25 + float(k) * step
			Rules.ZONE_REAR:
				lo = PI * 1.25 - float(k + 1) * step
			Rules.ZONE_LEFT:
				lo = -PI * 0.25 - float(k + 1) * step
			_:
				lo = PI * 0.25 + float(k) * step
		return Vector2(lo, lo + step)
	return Vector2.ZERO

## The wound counters of unit `unit`: for each section, in units, the hull damage that
## came through it and is not repaired yet. The counters are rescaled on every read so
## that they always add up to the hull the unit is missing (a stray write to the hull,
## or a repair that does not know about sections, cannot break the sum): each keeps its
## share, and a unit that is missing hull but has no wound recorded shares the loss out
## evenly. A whole unit has no wounds.
func wounds(unit: Unit) -> PackedInt32Array:
	var missing := maxi(0, roundi((unit.hull_max - unit.hull) * float(UNITS_PER_POINT)))
	var out := PackedInt32Array()
	out.resize(count)
	if count <= 0 or missing <= 0:
		wound = out
		return out.duplicate()
	var sum := 0
	for i in count:
		sum += wound[i]
	var given := 0
	for i in count:
		out[i] = wound[i] * missing / sum if sum > 0 else missing / count
		given += out[i]
	# The rounding leftover goes to the first sections (those with a wound, if any).
	var left := missing - given
	var k := 0
	while left > 0 and k < 4 * count:
		var j := k % count
		if sum <= 0 or wound[j] > 0:
			out[j] += 1
			left -= 1
		k += 1
	wound = out
	return out.duplicate()


## Mend section `i`'s armour by up to `points` armour points (never above what the
## section held whole). The hull is not touched: this is the armour's own repair call.
## A black section that is mended is no longer black. Returns the points really mended.
func repair_armour(i: int, points: float) -> float:
	if i < 0 or i >= count or points <= 0.0:
		return 0.0
	var add := mini(int(points * float(UNITS_PER_POINT)), a_max[i] - a_hp[i])
	if add <= 0:
		return 0.0
	if a_hp[i] == 0:
		breach_time[i] = -999.0
	a_hp[i] += add
	return float(add) / float(UNITS_PER_POINT)


## Mend the hull of `unit` by up to `points` hull points through Unit.heal() (never
## above its hull_max), and take the mended points off the wound counters: section
## `section` first (when it is a section), then the biggest wound, ties to the lower
## number. The armour is not touched: this is the hull's own repair call. Returns the
## points really mended.
func repair_hull(unit: Unit, points: float, section: int = -1) -> float:
	# Settle the counters to the hull as it is before it changes.
	wounds(unit)
	var healed := unit.heal(points)
	var left := roundi(healed * float(UNITS_PER_POINT))
	if section >= 0 and section < count:
		var take := mini(left, wound[section])
		wound[section] -= take
		left -= take
	while left > 0:
		var biggest := -1
		for i in count:
			if wound[i] > 0 and (biggest < 0 or wound[i] > wound[biggest]):
				biggest = i
		if biggest < 0:
			break
		var take := mini(left, wound[biggest])
		wound[biggest] -= take
		left -= take
	return healed

## The impact point `local` (in the ship's own frame: +x ahead, +y to the right)
## measured from the hull's spine of length `spine_len`: the point's distance
## along the ship is taken from the nearest point of the spine. The middle of
## the spine sits `spine_off` ahead of the ship's centre (0 = at the centre).
## With a spine of 0 it is `local` itself.
static func from_spine(local: Vector2, spine_len: float, spine_off := 0.0) -> Vector2:
	if spine_len <= 0.0:
		return local
	var half := spine_len * 0.5
	var along := local.x - spine_off
	return Vector2(along - clampf(along, -half, half), local.y)


## The number of the section that the point `raw` (in the ship's own frame, NOT
## yet measured from the spine) lands on, for a hull with a capsule hit shape:
## the same pick as section_at() with one difference. A point beside the spine
## on a side (its zone is left or right) is sorted by where it is along the
## spine: the side's sections are laid along the spine from the nose to the tail,
## each the same length, by a whole number test; a side hit past an end of the
## spine (the round end of the capsule) counts as at that end, so it lands on
## the end section; a point exactly on a border goes to the lower number. Every
## front or rear hit keeps the angle borders, as in section_at().
## With a spine of 0 it is exactly section_at(raw).
func section_on_spine(raw: Vector2, spine_len: float, spine_off := 0.0) -> int:
	var local := from_spine(raw, spine_len, spine_off)
	if count <= 0:
		return -1
	var zone := ShieldZones.zone_for_local(local)
	if spine_len > 0.0 and (zone == Rules.ZONE_LEFT or zone == Rules.ZONE_RIGHT):
		var n := zone_count[zone]
		var half := int(spine_len * 0.5 * PICK_SCALE)
		var x := clampi(int((raw.x - spine_off) * PICK_SCALE), -half, half)
		if n > 1 and half > 0:
			# Nose first: the section number from the nose end of the spine. A
			# side hit past an end of the spine lands on that end's section. A
			# point exactly on a border goes to the lower number (the rounded
			# up quotient, less one).
			var from_nose := half - x
			return zone_first[zone] + clampi((from_nose * n + 2 * half - 1) / (2 * half) - 1, 0, n - 1)
	return section_in_zone(zone, local)


## The number of the section that impact point `local` (already measured from
## the spine, see from_spine()) lands on, or -1 when there is no section there.
func section_at(local: Vector2) -> int:
	if count <= 0:
		return -1
	return section_in_zone(ShieldZones.zone_for_local(local), local)


## The number of the section of zone `zone` that point `local` lands on, or -1
## when the zone holds no section. The tests are whole-number cross products
## against the zone's borders; a point on a border goes to the lower number.
func section_in_zone(zone: int, local: Vector2) -> int:
	if zone < 0 or zone > 3:
		return -1
	var n := zone_count[zone]
	if n <= 0:
		return -1
	var first := zone_first[zone]
	if n == 1:
		return first
	var x := int(local.x * PICK_SCALE)
	var y := int(local.y * PICK_SCALE)
	var s: Array = borders_for(n)
	var idx := 0
	if zone == Rules.ZONE_FRONT or zone == Rules.ZONE_REAR:
		# Along the zone, from the ship's left (small y) to its right.
		var along := x if zone == Rules.ZONE_FRONT else -x
		for b in s:
			if y * 256 > int(b) * along:
				idx += 1
	else:
		# A side zone: from the nose to the tail. `across` is the distance from
		# the spine out to the side, and the borders run from the nose edge.
		var across := -y if zone == Rules.ZONE_LEFT else y
		for k in range(s.size() - 1, -1, -1):
			if x * 256 < int(s[k]) * across:
				idx += 1
	return first + idx


## The border slopes for a zone split into `n` sections (BORDERS, or worked out
## once for a bigger n).
static func borders_for(n: int) -> Array:
	if BORDERS.has(n):
		return BORDERS[n]
	var out: Array = []
	for k in range(1, n):
		out.append(roundi(256.0 * tan(deg_to_rad(-45.0 + float(k) * 90.0 / float(n)))))
	return out
