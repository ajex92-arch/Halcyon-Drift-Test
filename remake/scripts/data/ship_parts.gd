class_name ShipParts
extends RefCounted
## WHAT THIS IS: the parts of the four big hulls (the Flak Frigate, the Ion Frigate, the
## Destroyer and the Battlecruiser): which guns, engine pods and sensor a hull carries, where
## each sits, how tough it is and which armour section covers it. It is data and a few pure
## functions: it keeps no state (ShipSystems keeps a ship's live part health).
##
## HOW IT WORKS:
##   - build() makes the list of one hull's parts from its row in ships.gd: one part for each
##     entry of the row's `mounts` (id "m0", "m1", ...; a point-defence or flak gun is a LIGHT
##     part, any other gun a MAIN part), two engine pods "pod_l" and "pod_r" at the hull's own
##     side-flame points (aurelian_shapes.gd, the second point of the hull's `jet`), and one
##     "sensor" ahead of the middle. Pods and sensors are heavy parts, like main guns.
##   - A LIGHT part is EXPOSED when it sits so near the hull's hit surface that a round's true
##     impact point can lie inside its circle (PART_R_LIGHT world units round its offset): it is
##     hit directly and has a thin plate of its own. Every other light part is COVERED, behind
##     the armour. Heavy parts are never exposed: they take a share of what gets through the
##     armour over them (SHARE_PCT percent).
##   - Each part sits in the armour section the hull's own pick gives its offset; a part on the
##     hull's centre line (exactly on its spine, where the pick has no angle) is hosted by its x
##     instead: the front zone ahead of the spine's middle, the rear zone behind it (zone_of()).
##   - Health is a percent of the hull row's `hull`, in units of 1/256 point (the armour's
##     own unit, ArmourSections.UNITS_PER_POINT), whole numbers only.
##   - A part at 0 health is offline: after DELAY_TICKS it climbs back by itself to
##     CLIMB_PCT percent of its health, over CLIMB_TICKS_GUN or CLIMB_TICKS_POD ticks.
## The switch Rules.parts_on() decides whether any ship asks for parts at all.
##
## WHO USES IT: Ship.setup() (through ShipSystems), the checks, the time-to-kill table and
## the HUD rings read the rows and constants; PilotTargeting asks zone_of() for the shield zone
## of a part.

## The hulls that carry parts.
const HULLS_WITH_PARTS := ["flak", "ion", "destroyer", "battlecruiser"]
## Part class: a point-defence or flak gun.
const CLASS_LIGHT := 0
## Part class: any other gun (the "main" guns).
const CLASS_MAIN := 1
## Part class: an engine pod.
const CLASS_POD := 2
## Part class: the sensor.
const CLASS_SENSOR := 3
## The names of the classes, in the order of the CLASS_ numbers.
const CLASS_NAMES := ["light", "main", "pod", "sensor"]

## The radius (world units) of a light part's circle: a round whose true impact point lies inside
## it hits the part directly (when the part is exposed).
const PART_R_LIGHT := 40.0
## The health of a main gun, in tenths of a percent of the hull's points.
const PERMILLE_MAIN := 150
## The health of a light part that sits behind the armour (covered), in tenths of a percent.
const PERMILLE_COVERED := 60
## The health of an exposed light part, in tenths of a percent (with a floor of EXPOSED_FLOOR_POINTS).
const PERMILLE_EXPOSED := 15
## The least health, in points, an exposed light part has.
const EXPOSED_FLOOR_POINTS := 40
## The health of an engine pod, in tenths of a percent.
const PERMILLE_POD := 200
## The health of the sensor, in tenths of a percent.
const PERMILLE_SENSOR := 100
## The units one armour point of the hull gives a light part's own plate: armour / 4 points
## in units of 1/256 (so 64 units for each armour point).
const PLATE_UNITS_PER_ARMOUR := 64
## The share, in percent, of the damage that gets through the armour that a part behind it takes.
const SHARE_PCT := 50
## Ticks (60 a second) an offline part waits before it starts to come back: 10 seconds.
const DELAY_TICKS := 600
## The health, in percent of its full health, a part climbs back to by itself. It is brought
## back to this and no higher: only docking or repair gets it further.
const CLIMB_PCT := 15
## Ticks a gun, a light part or the sensor takes to climb back: 20 seconds.
const CLIMB_TICKS_GUN := 1200
## Ticks an engine pod takes to climb back: 30 seconds.
const CLIMB_TICKS_POD := 1800
## Seconds a computer captain whose ship has an engine pod out stands and fights before it
## goes home anyway (the hold of ShipSystems.captain_holds()).
const CAPTAIN_HOLD_S := 60.0
## Where a pod sits when its hull has no side-flame point: this share of the length astern of
## the middle ...
const PROPOSED_POD_X := -0.45
## ... and this share of the length to each side.
const PROPOSED_POD_Y := 0.10
## Where the sensor sits: this share of the length ahead of the middle.
const SENSOR_X := 0.40
## The hull row's design space is this long (aurelian_shapes.gd), scaled to the hull's length.
const DESIGN_LENGTH := 36.0


## True when hull `hid` carries parts.
static func has_parts(hid: String) -> bool:
	return HULLS_WITH_PARTS.has(hid)


## The distance (world units) from point `off` (ship frame) to the hull's hit surface, going
## inwards: how deep inside the hit shape the point is (negative = outside it). A capsule hull
## (hit_r above 0) is measured from its spine, a circle hull from the middle against its radius.
static func depth(def: Dictionary, off: Vector2) -> float:
	var hit_r := float(def.get("hit_r", 0.0))
	if hit_r <= 0.0:
		return float(def["radius"]) - off.length()
	var half := float(def.get("spine", 0.0)) * 0.5
	var along := absf(off.x - float(def.get("spine_off", 0.0)))
	var dx := maxf(0.0, along - half)
	return hit_r - sqrt(dx * dx + off.y * off.y)


## True when a light part at `off` is exposed with the part radius `r`: the part's circle reaches
## the hull's hit surface.
static func is_exposed(def: Dictionary, off: Vector2, r: float = PART_R_LIGHT) -> bool:
	return depth(def, off) <= r


## The shield zone that point `off` (ship frame) belongs to, for a hull whose spine is `spine`
## long with its middle `spine_off` ahead of the centre: the zone of the point's angle from the
## spine, as the hull's own pick reads it. A point exactly on the spine has no angle (the hull's
## own pick gives it the front), so it is told by where it sits along the hull instead: the front
## zone when it is level with the spine's middle or ahead of it, the rear zone when it is behind
## (a point exactly at the middle goes forward, the lower number).
static func zone_of(off: Vector2, spine: float, spine_off: float) -> int:
	var local := ArmourSections.from_spine(off, spine, spine_off)
	if spine > 0.0 and local == Vector2.ZERO:
		return Rules.ZONE_FRONT if off.x >= spine_off else Rules.ZONE_REAR
	return ShieldZones.zone_for_local(local)


## The armour section that point `off` (ship frame) falls in, by the hull's own pick (a capsule
## hull sorts by the spine, a point on a border goes to the lower number), or -1. A capsule hull's
## point exactly on the spine is hosted by its zone_of() instead (the first section of that
## zone, or -1 when the zone holds none).
static func host_section(def: Dictionary, armour: ArmourSections, off: Vector2) -> int:
	if armour == null:
		return -1
	var spine := float(def.get("spine", 0.0))
	var spine_off := float(def.get("spine_off", 0.0))
	if float(def.get("hit_r", 0.0)) > 0.0:
		if spine > 0.0 and ArmourSections.from_spine(off, spine, spine_off) == Vector2.ZERO:
			return armour.section_in_zone(zone_of(off, spine, spine_off), Vector2.ZERO)
		return armour.section_on_spine(off, spine, spine_off)
	return armour.section_at(ArmourSections.from_spine(off, spine, spine_off))


## The two engine pod offsets of hull `hid` [left, right] (ship frame, world units): the side
## flames' point of the hull's entry in AurelianShapes, mirrored, scaled to the hull's length;
## or the proposed offset when the entry has none. `def` is the hull's row.
static func pod_offsets(hid: String, def: Dictionary) -> Array:
	var length := float(def["length"])
	var entry: Dictionary = AurelianShapes.HULLS.get(hid, {})
	var jet: Array = entry.get("jet", [])
	if jet.size() >= 2:
		var p: Vector2 = jet[1]
		var u := length / DESIGN_LENGTH
		return [Vector2(p.x * u, -absf(p.y) * u), Vector2(p.x * u, absf(p.y) * u)]
	return [Vector2(PROPOSED_POD_X * length, -PROPOSED_POD_Y * length), Vector2(PROPOSED_POD_X * length, PROPOSED_POD_Y * length)]


## True when hull `hid`'s pods are at a proposed offset (its entry has no side-flame point).
static func pods_proposed(hid: String) -> bool:
	var entry: Dictionary = AurelianShapes.HULLS.get(hid, {})
	var jet: Array = entry.get("jet", [])
	return jet.size() < 2


## A part's full health in units, for a hull of `hull_points` and a health of `permille` tenths of a percent.
static func hp_units(hull_points: int, permille: int) -> int:
	return hull_points * permille * ArmourSections.UNITS_PER_POINT / 1000


## Build the part list of hull `hid` (see the top of the file), with each part's host section
## found from `armour` (the hull's own sections). Returns [] for a hull that has no parts. Each
## part is a Dictionary: id, cls (CLASS_), off (ship frame), sec (host section, -1 = none),
## mount (the index in the hull row's mounts, -1 for a pod or the sensor), exposed (light parts
## only), hp_max (units), plate (units, light parts only: 0 else), climb (ticks), depth (the
## distance under the hit surface, in world units). `r_light` is the light part's circle radius.
static func build(hid: String, armour: ArmourSections, r_light: float = PART_R_LIGHT) -> Array:
	var rows: Array = []
	if not has_parts(hid):
		return rows
	var def: Dictionary = Ships.get_def(hid)
	var hull_points := int(def["hull"])
	var length := float(def["length"])
	var plate := int(def.get("armour", 0)) * PLATE_UNITS_PER_ARMOUR
	var mounts: Array = def["mounts"]
	for i in mounts.size():
		var m: Dictionary = mounts[i]
		var off: Vector2 = m["off"]
		var wk := Weapons.kind_id(Weapons.get_def(String(m["w"])))
		var light := wk == Rules.W_PD or wk == Rules.W_FLAK
		var row := {"id": "m%d" % i, "cls": CLASS_LIGHT if light else CLASS_MAIN, "off": off,
			"sec": host_section(def, armour, off), "mount": i, "exposed": false,
			"hp_max": 0, "plate": 0, "climb": CLIMB_TICKS_GUN, "depth": depth(def, off)}
		if light:
			var exposed := is_exposed(def, off, r_light)
			row["exposed"] = exposed
			row["plate"] = plate
			if exposed:
				row["hp_max"] = maxi(EXPOSED_FLOOR_POINTS * ArmourSections.UNITS_PER_POINT, hp_units(hull_points, PERMILLE_EXPOSED))
			else:
				row["hp_max"] = hp_units(hull_points, PERMILLE_COVERED)
		else:
			row["hp_max"] = hp_units(hull_points, PERMILLE_MAIN)
		rows.append(row)
	var pods := pod_offsets(hid, def)
	var pod_ids := ["pod_l", "pod_r"]
	for k in 2:
		var off: Vector2 = pods[k]
		rows.append({"id": pod_ids[k], "cls": CLASS_POD, "off": off, "sec": host_section(def, armour, off), "mount": -1,
			"exposed": false, "hp_max": hp_units(hull_points, PERMILLE_POD), "plate": 0, "climb": CLIMB_TICKS_POD, "depth": depth(def, off)})
	var s_off := Vector2(SENSOR_X * length, 0.0)
	rows.append({"id": "sensor", "cls": CLASS_SENSOR, "off": s_off, "sec": host_section(def, armour, s_off), "mount": -1,
		"exposed": false, "hp_max": hp_units(hull_points, PERMILLE_SENSOR), "plate": 0, "climb": CLIMB_TICKS_GUN, "depth": depth(def, s_off)})
	return rows
