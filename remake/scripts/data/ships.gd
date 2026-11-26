class_name Ships
extends RefCounted
## WHAT THIS IS: the table of every ship a pilot can fly (each ship type is
## called a "hull"), from the free Scout to the huge Battlecruiser, with all
## its numbers: price, toughness, speed, guns and special ability.
## DESIGN.md A5.
##
## HOW IT WORKS: HULLS is a dictionary (a lookup table): hull id, such as
## "fighter" -> that hull's facts. ORDER lists the ids in the order the
## hangar shows them. Three tiny helper functions read the table. Nothing
## here runs by itself.
##
## The fields of each hull ([units] in brackets):
##   Shop:
##     label         the name players see
##     size          size class: 0 small (strike craft), 1 medium (corvette),
##                   2 large (frigate), 3 capital (see Rules.SIZE_*)
##     price         what it costs in the hangar [credits]; 0 = free
##     unlock        "" (available from the start), a tech id, or
##                   "fac:<facility>". A tech id (from tech.gd) means "needs
##                   that research AND the facility for this hull's size";
##                   "fac:corvette" means "needs the Corvette Facility".
##     blurb         the short text on the hull's card in the hangar, 2 to 5
##                   words (read it through blurb())
##     blurb_removed only on some hulls: the text shown instead of the blurb
##                   while the damage modifiers are removed (blurb()); it
##                   reads the same as the blurb
##   Defence:
##     hull          hit points of the hull; at 0 the ship is destroyed
##     shield        shield points, the total over the 4 shield zones
##     shield_regen  shield points refilled per second, once the shield has
##                   waited Rules.SHIELD_DELAY seconds after the last hit
##     hull_resist   the share of each hull hit that is blocked [0..1;
##                   0.2 = the hull takes 20% less damage]; 0 for every pilot hull,
##                   whose armour is its sections now (gear still adds to it)
##     armour        the armour value A of the hull's sections: a shot of strength W
##                   gets through a whole section with W / (W + A) of its damage (see
##                   ArmourSections.hit()) [damage points]
##     shield_resist the same for the shield
##     shield_weights optional (missing = Rules.FOCUS_WEIGHTS): the hull's own shield shares,
##                   five rows in the order Balanced, Front, Rear, Left, Right, each
##                   [front, rear, left, right] and adding up to 1.0 (ShieldZones.use_table())
##     shield_swing  optional (missing = 0.0, a focus change moves the caps at once): the
##                   seconds a focus change takes to move the caps (ShieldZones.swing_s)
##   Battery (energy, spent by guns, boosting and the special):
##     energy        how much the battery holds [energy points]
##     energy_regen  how fast it refills [energy per second]
##   Flight: not here. How a hull flies (speed, engine push, turning, boost)
##   is its row in the handling table, Handling.TABLE (handling.gd).
##   Body:
##     vision        how far the ship sees [world units]
##     radius        collision size, a circle [world units]
##     length        how long ShipVisual draws the ship [world units]
##     sections      the armour sections: [front, rear, side], how many sections
##                   the front zone, the rear zone and each side zone hold (see
##                   ArmourSections); optional section_weights: one whole number
##                   per section, front first, then rear, left, right (missing =
##                   all equal); the two capitals use it to make each bow and stern
##                   section hold 3/5 of a side section's armour, the pool unchanged
##     spine         the length of the hull's spine, the line along the ship
##                   that impact points are measured from [world units]; 0 = the
##                   hull is a circle
##     hit_r         optional (missing = 0): the hull's hit shape is a capsule,
##                   its spine with a round end at each end and this radius
##                   [world units]; rounds, beams and blasts see that shape (a
##                   hull without it is hit as a circle of its radius). Its
##                   spine (above) is the length of the capsule's segment
##     spine_off     optional (missing = 0): how far the middle of the spine sits
##                   ahead of the ship's centre, along the hull [world units;
##                   negative = astern]; 0 where the drawing is centred
##   Guns:
##     mounts        a list of guns, each {w: weapon id (from weapons.gd),
##                   type: fixed|turret|auto, off: local offset (where it
##                   sits on the hull, in world units: x forward, y
##                   starboard, which is the right-hand side), arc:
##                   half-angle in degrees for turret/auto (how far it can
##                   swing either side of the direction it faces), face:
##                   optional, which way the swing is centred, in degrees
##                   round from the nose (missing = 0, the nose; 180 = the
##                   tail, for a rear gun)}.
##                   Fixed mounts fire along the nose. Turret mounts track
##                   the pilot's aim point inside their arc. Auto mounts
##                   pick their own targets.
##                   id (optional): the gun's name, unique inside its
##                   hull; a launched gun carries it as WeaponMount.id.
##                   Today only the Destroyer and the Battlecruiser have ids.
##                   battery (optional, true on a heavy gun or an ion turret of a
##                   ship of the line): the gun belongs to the broadside battery. It
##                   follows the reticle inside its arc, fires on its own at its
##                   own target when the reticle is off its side, takes the
##                   Broadside charge and aims with a small fixed spread
##                   (WeaponMount.battery).
##     side_battery  optional, true on a ship of the line (the Destroyer and the
##                   Battlecruiser): its main guns sit on the beams. Its turrets
##                   swing three times faster after 2 s idle, the computer
##                   captain turns a beam to its target, and the pilot gets the
##                   arcs view and the reticle mark (ArcView).
##   Special ability (one per hull; ShipAbilities runs it):
##     special         the ability's id
##     special_cd      how long before it can be used again [seconds]
##     special_energy  what it costs [energy]
##     special_label   its name for players
##     special_info    what it does, in words for players
##   Roles (a list of tags; code asks Ships.has_role(hull_id, tag), never a
##   hull id):
##     roles           the role tags of the hull, from ROLE_TAGS:
##       torpedo       flies torpedo runs: targets big hulls, skips small ones
##       siege         a small ship that still joins and stays in a siege (big
##                     ships do by size)
##       heavy_hitter  big guns: hurts big hulls and structures
##       no_hunt       never pushes, seeks or farms
##       beam          a beam fighter: stands further in, looser aim, may take
##                     a lone carrier camp
##       fixed_beam    its main gun is fixed: turns the nose to the target at
##                     once
##   Extras only some hulls have:
##     repair_drones   repair drones it carries (Logistics Corvette)
##     aura            true = buffs nearby allies (Support Corvette;
##                     WorldSupport reads it)
##
## WHO USES IT: Ship.setup() reads a hull and builds its guns; ShipStats
## reads the defence and battery numbers (the flight numbers are in Handling);
## ShipAbilities and
## ShipVisual read the rest. Tech decides which hulls are unlocked. The
## hangar screens (HangarShips, HangarLaunch), PilotProfile and
## PilotProfileShop sell them; the AI pilots (PilotShopping, PilotCombat)
## pick them; the HUD and the scoreboard show their labels.
##
## To add a hull: add an entry and its role tags, add its id to ORDER, give it a silhouette in
## HullTables.OUTLINES, a steel Aurelian drawing in AurelianShapes.HULLS and an
## alien Cinder shape in CinderShapes.HULLS (without
## one, Cinder draws it as the fighter), and (if it needs a new special) handle it in
## Ship._use_special() (which forwards to ShipAbilities.use_special()).

## Every hull id, in the order the hangar lists them (TeamState also returns
## the unlocked hulls in this order).
const ORDER := ["scout", "fighter", "lance", "bomber", "logistics", "support", "flak", "ion", "destroyer", "battlecruiser"]

## Every pilot hull: hull id -> its facts (the fields are explained at the
## top of this file). Do not reorder or change these without a playtest.
const HULLS := {
	# Scout (small, free): the fastest ship, with the widest vision of the
	# strike craft. Its Ping shows hidden enemies.
	"scout": {
		"label": "Scout", "size": 0, "price": 0.0, "unlock": "",
		"roles": ["no_hunt"],
		"blurb": "Fastest ship, widest vision",
		"hull": 70.0, "shield": 120.0, "shield_regen": 16.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 100.0, "energy_regen": 30.0,
		"vision": 3000.0, "radius": 9.0, "length": 20.0,
		"sections": [1, 1, 1], "spine": 0.0, "armour": 1,
		"mounts": [{"w": "scout_gun", "type": "fixed", "off": Vector2(10, 0), "arc": 0.0}],
		"special": "ping", "special_cd": 14.0, "special_energy": 35.0,
		"special_label": "Ping", "special_info": "reveals every enemy within 4,500 for 3s, even behind asteroids",
	},
	# Fighter (small): the all-round dogfighter. Its cannon has a small_bonus
	# of 1.25 (weapons.gd), which is the "+25% against small ships" (applied
	# only while the damage modifiers are kept).
	"fighter": {
		"label": "Fighter", "size": 0, "price": 150.0, "unlock": "",
		"roles": [],
		"blurb": "Agile dogfighter",
		"blurb_removed": "Agile dogfighter",
		"hull": 100.0, "shield": 200.0, "shield_regen": 18.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 100.0, "energy_regen": 26.0,
		"vision": 2400.0, "radius": 12.0, "length": 26.0,
		"sections": [1, 1, 1], "spine": 0.0, "armour": 1,
		"mounts": [{"w": "fighter_cannon", "type": "fixed", "off": Vector2(12, 0), "arc": 0.0}],
		"special": "snap", "special_cd": 8.0, "special_energy": 20.0,
		"special_label": "Snap turn", "special_info": "turns twice as fast for 1.5s",
	},
	# Lance Fighter (small): a beam fighter, unlocked by Lance Beams research.
	"lance": {
		"label": "Lance Fighter", "size": 0, "price": 300.0, "unlock": "lanceBeams",
		"roles": ["heavy_hitter", "beam"],
		"blurb": "Heavy Strike Craft",
		"blurb_removed": "Heavy Strike Craft",
		"hull": 110.0, "shield": 220.0, "shield_regen": 18.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 120.0, "energy_regen": 32.0,
		"vision": 2400.0, "radius": 13.0, "length": 30.0,
		"sections": [1, 1, 1], "spine": 0.0, "armour": 2,
		"mounts": [{"w": "lance_beam", "type": "fixed", "off": Vector2(15, 0), "arc": 0.0}],
		"special": "overload", "special_cd": 12.0, "special_energy": 30.0,
		"special_label": "Overload", "special_info": "beam damage +60% for 2.5s",
	},
	# Bomber (small, but slow and without a booster): torpedoes against big
	# targets, unlocked by Fusion Bombs research.
	"bomber": {
		"label": "Bomber", "size": 0, "price": 350.0, "unlock": "fusionBombs",
		"roles": ["torpedo", "siege", "heavy_hitter"],
		"blurb": "Slow torpedo ship",
		"blurb_removed": "Slow torpedo ship",
		"hull": 170.0, "shield": 240.0, "shield_regen": 16.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 120.0, "energy_regen": 22.0,
		"vision": 2300.0, "radius": 17.0, "length": 46.0,
		"sections": [1, 1, 1], "spine": 0.0, "armour": 3,
		"mounts": [{"w": "torpedo", "type": "fixed", "off": Vector2(24, 0), "arc": 0.0},
				{"w": "tail_gun", "type": "auto", "off": Vector2(-10.9, 0), "arc": 60.0, "face": 180.0}],
		"special": "focus", "special_cd": 7.0, "special_energy": 25.0,
		"special_label": "Focus shot", "special_info": "next run's torpedoes deal +45% damage",
	},
	# Logistics Corvette (medium): the healer, unlocked by building the
	# Corvette Facility. It carries 2 repair drones.
	"logistics": {
		"label": "Logistics Corvette", "size": 1, "price": 500.0, "unlock": "fac:corvette",
		"roles": ["no_hunt"],
		"blurb": "Repair corvette",
		"hull": 380.0, "shield": 420.0, "shield_regen": 22.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 150.0, "energy_regen": 22.0,
		"vision": 2600.0, "radius": 44.0, "length": 95.0,
		"sections": [1, 1, 2], "spine": 0.0, "armour": 10,
		"mounts": [{"w": "light_turret", "type": "turret", "off": Vector2(20, 0), "arc": 100.0}],
		"repair_drones": 2,
		"special": "emergency_repair", "special_cd": 18.0, "special_energy": 50.0,
		"special_label": "Emergency repair", "special_info": "heals allies within 650 by 12% of their hull",
	},
	# Support Corvette (medium): big vision and an aura that buffs allies,
	# unlocked by Command Systems research.
	"support": {
		"label": "Support Corvette", "size": 1, "price": 550.0, "unlock": "commandSystems",
		"roles": [],
		"blurb": "Command corvette",
		"blurb_removed": "Command corvette",
		"hull": 300.0, "shield": 500.0, "shield_regen": 26.0, "hull_resist": 0.0, "shield_resist": 0.05,
		"energy": 180.0, "energy_regen": 30.0,
		"vision": 4200.0, "radius": 44.0, "length": 90.0,
		"sections": [1, 1, 2], "spine": 0.0, "armour": 5,
		"mounts": [{"w": "light_turret", "type": "turret", "off": Vector2(16, 0), "arc": 130.0}],
		"aura": true,
		"special": "jam", "special_cd": 16.0, "special_energy": 60.0,
		"special_label": "Jam", "special_info": "cuts enemy vision within 1,400 to a quarter for 7s",
	},
	# Flak Frigate (large): holds a lane against strike craft, unlocked by
	# building the Frigate Facility.
	"flak": {
		"label": "Flak Frigate", "size": 2, "price": 1100.0, "unlock": "fac:frigate",
		"roles": [],
		"blurb": "Flak lane anchor",
		"blurb_removed": "Flak lane anchor",
		"hull": 1000.0, "shield": 900.0, "shield_regen": 30.0, "hull_resist": 0.0, "shield_resist": 0.05,
		"energy": 200.0, "energy_regen": 25.0,
		"vision": 2700.0, "radius": 87.5, "length": 262.5,
		"sections": [1, 1, 3], "spine": 93.0, "hit_r": 73.0, "spine_off": -3.0, "armour": 25,
		"mounts": [
			{"w": "flak_battery", "type": "turret", "off": Vector2(50, 0), "arc": 160.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(-62.5, -50), "arc": 180.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(-62.5, 50), "arc": 180.0},
		],
		"special": "brace", "special_cd": 14.0, "special_energy": 50.0,
		"special_label": "Brace", "special_info": "takes 38% less damage for 5s",
	},
	# Ion Frigate (large): a fixed forward ion beam against big targets,
	# unlocked by Ion Cannons research.
	"ion": {
		"label": "Ion Frigate", "size": 2, "price": 1250.0, "unlock": "ionCannons",
		"roles": ["heavy_hitter", "fixed_beam"],
		"blurb": "Ion beam frigate",
		"blurb_removed": "Ion beam frigate",
		"hull": 850.0, "shield": 1000.0, "shield_regen": 30.0, "hull_resist": 0.0, "shield_resist": 0.05,
		"energy": 220.0, "energy_regen": 30.0,
		"vision": 2900.0, "radius": 85.0, "length": 275.0,
		"sections": [1, 1, 3], "spine": 148.0, "hit_r": 56.0, "spine_off": 8.0, "armour": 22,
		"mounts": [
			{"w": "ion_cannon", "type": "fixed", "off": Vector2(125, 0), "arc": 0.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(-50, 0), "arc": 180.0},
		],
		"special": "capdump", "special_cd": 14.0, "special_energy": 60.0,
		"special_label": "Capacitor dump", "special_info": "next ion burst deals +80% damage",
	},
	# Destroyer (capital): heavy cannons that can also break asteroids,
	# unlocked by Destroyer Chassis research.
	"destroyer": {
		"label": "Destroyer", "size": 3, "price": 2200.0, "unlock": "destroyerChassis",
		"roles": ["heavy_hitter"],
		"blurb": "Heavy-gun capital ship",
		"hull": 2400.0, "shield": 1800.0, "shield_regen": 45.0, "hull_resist": 0.0, "shield_resist": 0.08,
		"energy": 300.0, "energy_regen": 35.0,
		"vision": 3100.0, "radius": 180.0, "length": 630.0,
		"sections": [2, 2, 3], "spine": 382.0, "hit_r": 131.0, "spine_off": -7.0, "armour": 50,
		"section_weights": [3, 3, 3, 3, 5, 5, 5, 5, 5, 5],
		"shield_weights": [[0.15, 0.15, 0.35, 0.35], [0.30, 0.10, 0.30, 0.30], [0.10, 0.30, 0.30, 0.30], [0.10, 0.10, 0.55, 0.25], [0.10, 0.10, 0.25, 0.55]],
		"shield_swing": 3.0,
		"mounts": [
			{"id": "heavy_fore_port", "w": "heavy_cannon", "type": "turret", "off": Vector2(110, -96), "arc": 35.0, "face": -90.0, "battery": true},
			{"id": "heavy_fore_stbd", "w": "heavy_cannon", "type": "turret", "off": Vector2(110, 96), "arc": 35.0, "face": 90.0, "battery": true},
			{"id": "heavy_aft_port", "w": "heavy_cannon", "type": "turret", "off": Vector2(-70, -96), "arc": 35.0, "face": -90.0, "battery": true},
			{"id": "heavy_aft_stbd", "w": "heavy_cannon", "type": "turret", "off": Vector2(-70, 96), "arc": 35.0, "face": 90.0, "battery": true},
			{"id": "chaser_fore", "w": "light_turret", "type": "turret", "off": Vector2(190, 0), "arc": 30.0, "face": 0.0},
			{"id": "chaser_aft", "w": "light_turret", "type": "turret", "off": Vector2(-230, 0), "arc": 30.0, "face": 180.0},
			{"id": "pd_fore_port", "w": "pd_gun", "type": "auto", "off": Vector2(90, -105), "arc": 80.0, "face": -90.0},
			{"id": "pd_fore_stbd", "w": "pd_gun", "type": "auto", "off": Vector2(90, 105), "arc": 80.0, "face": 90.0},
			{"id": "pd_aft", "w": "pd_gun", "type": "auto", "off": Vector2(-210, 0), "arc": 80.0, "face": 180.0},
			{"id": "flak_port", "w": "flak_auto", "type": "auto", "off": Vector2(10, -100), "arc": 80.0, "face": -90.0},
			{"id": "flak_stbd", "w": "flak_auto", "type": "auto", "off": Vector2(10, 100), "arc": 80.0, "face": 90.0},
		],
		"side_battery": true,
		"special": "overcharge", "special_cd": 20.0, "special_energy": 80.0,
		"special_label": "Overcharge", "special_info": "every gun fires twice as fast for 5s, after a 1s warning",
	},
	# Battlecruiser (capital): the heaviest and most expensive hull, unlocked
	# by Battlecruiser Chassis research.
	"battlecruiser": {
		"label": "Battlecruiser", "size": 3, "price": 3800.0, "unlock": "battlecruiserChassis",
		"roles": ["heavy_hitter"],
		"blurb": "The heaviest hull",
		"hull": 4200.0, "shield": 3000.0, "shield_regen": 60.0, "hull_resist": 0.0, "shield_resist": 0.1,
		"energy": 400.0, "energy_regen": 40.0,
		"vision": 3300.0, "radius": 240.0, "length": 840.0,
		"sections": [2, 2, 4], "spine": 518.0, "hit_r": 170.0, "spine_off": -9.0, "armour": 75,
		"section_weights": [3, 3, 3, 3, 5, 5, 5, 5, 5, 5, 5, 5],
		"shield_weights": [[0.15, 0.15, 0.35, 0.35], [0.30, 0.10, 0.30, 0.30], [0.10, 0.30, 0.30, 0.30], [0.10, 0.10, 0.55, 0.25], [0.10, 0.10, 0.25, 0.55]],
		"shield_swing": 3.0,
		"mounts": [
			{"id": "ion_port", "w": "ion_turret", "type": "turret", "off": Vector2(150, -135), "arc": 35.0, "face": -90.0, "battery": true},
			{"id": "ion_stbd", "w": "ion_turret", "type": "turret", "off": Vector2(150, 135), "arc": 35.0, "face": 90.0, "battery": true},
			{"id": "heavy_fore_port", "w": "heavy_cannon", "type": "turret", "off": Vector2(30, -135), "arc": 35.0, "face": -90.0, "battery": true},
			{"id": "heavy_fore_stbd", "w": "heavy_cannon", "type": "turret", "off": Vector2(30, 135), "arc": 35.0, "face": 90.0, "battery": true},
			{"id": "heavy_aft_port", "w": "heavy_cannon", "type": "turret", "off": Vector2(-110, -135), "arc": 35.0, "face": -90.0, "battery": true},
			{"id": "heavy_aft_stbd", "w": "heavy_cannon", "type": "turret", "off": Vector2(-110, 135), "arc": 35.0, "face": 90.0, "battery": true},
			{"id": "chaser_fore", "w": "light_turret", "type": "turret", "off": Vector2(320, 0), "arc": 30.0, "face": 0.0},
			{"id": "chaser_aft", "w": "light_turret", "type": "turret", "off": Vector2(-300, 0), "arc": 30.0, "face": 180.0},
			{"id": "pd_fore_port", "w": "pd_gun", "type": "auto", "off": Vector2(180, -135), "arc": 80.0, "face": -90.0},
			{"id": "pd_fore_stbd", "w": "pd_gun", "type": "auto", "off": Vector2(180, 135), "arc": 80.0, "face": 90.0},
			{"id": "pd_aft_port", "w": "pd_gun", "type": "auto", "off": Vector2(-270, -120), "arc": 80.0, "face": -90.0},
			{"id": "pd_aft_stbd", "w": "pd_gun", "type": "auto", "off": Vector2(-270, 120), "arc": 80.0, "face": 90.0},
			{"id": "flak_port", "w": "flak_auto", "type": "auto", "off": Vector2(80, -130), "arc": 80.0, "face": -90.0},
			{"id": "flak_stbd", "w": "flak_auto", "type": "auto", "off": Vector2(80, 130), "arc": 80.0, "face": 90.0},
		],
		"side_battery": true,
		"special": "broadside", "special_cd": 25.0, "special_energy": 120.0,
		"special_label": "Broadside", "special_info": "the chosen side fires together after 1.2s, then 50% faster for 4s",
	},
}


## The facts of hull `id` (its entry in HULLS). Ship uses it when it is set
## up.
static func get_def(id: String) -> Dictionary:
	return HULLS[id]


## The size class of hull `id`: 0 small, 1 medium, 2 large, 3 capital.
## Modules (prices), Tech (unlocks) and PilotShopping use it.
static func size_of(id: String) -> int:
	return int(HULLS[id]["size"])


## The short text of hull `id` that players read on its card in the hangar:
## its "blurb_removed" while the damage modifiers are removed and the hull
## has one, else its "blurb". HangarShips uses it.
static func blurb(id: String) -> String:
	var d: Dictionary = HULLS[id]
	if Rules.damage_modifiers_removed() and d.has("blurb_removed"):
		return String(d["blurb_removed"])
	return String(d["blurb"])


## The role tags a hull row may carry in its "roles" list. Each tag is one
## fact about how a ship behaves; code asks has_role() instead of naming a
## hull (the meaning of each is in the header, under Roles).
const ROLE_TAGS := ["torpedo", "siege", "heavy_hitter", "no_hunt", "beam", "fixed_beam"]


## True when hull `id` is in HULLS and its "roles" list holds `tag`. False for
## the empty id and for an id that is not in the table (never an error), so a
## profile with no hull yet answers false for every tag.
static func has_role(id: String, tag: String) -> bool:
	if not HULLS.has(id):
		return false
	return (HULLS[id].get("roles", []) as Array).has(tag)


## The hull a pilot buys first and falls back to when it has no hull of its
## own (and the hull a drawing or lookup falls back to for an unknown id).
const DEFAULT_HULL := "fighter"

## The hull that costs nothing: a pilot with too few credits for anything else
## buys it, so nobody is ever stuck without a ship.
const FREE_HULL := "scout"


# --- the wish lists the AI buys from ------------------------------------------------
# Each list below names its ships on purpose and is keyed by a temperament or a call, not
# by a role tag: the order of a pick matters, and no tag could give that order. The
# readers (PilotShopping, AdmiralSmartFeature, Game) look the lists up here.

## Wish lists of hulls by temperament, best first. Heavies fly fighters
## until frigates unlock (playtest: with three Logistics corvettes per team,
## every fight was healed into a draw, so heavies don't buy them).
const HULL_PREF := {
	"heavy": ["battlecruiser", "destroyer", "flak", "ion", "fighter"],
	"heavy_ion": ["battlecruiser", "destroyer", "ion", "flak", "fighter"],
	"striker": ["bomber", "lance", "fighter"],
	"support": ["support", "logistics", "fighter"],
	# Lances melt corvettes but lose dogfights to Fighters (arena test: 3
	# Fighters beat 3 Lances 3-0), so only one laner per side flies them.
	"dog": ["fighter"],
	"lancer": ["lance", "fighter"],
	"jungle": ["lance", "fighter"],
}
## The modules we buy for each hull, in buying order (a hull holds 2).
const MOD_PREF := {
	"scout": ["engines"], "fighter": ["weapons", "engines"], "lance": ["capacitor", "weapons"],
	"bomber": ["weapons", "shield_booster"], "logistics": ["shield_booster", "plating"],
	"support": ["sensor_suite", "shield_booster"], "flak": ["plating", "shield_booster"],
	"ion": ["capacitor", "plating"], "destroyer": ["plating", "weapons"], "battlecruiser": ["plating", "shield_booster"],
}

## The hull put first on a pilot's list after 20:00 of game time (1,200 seconds), keyed by
## temperament: the dogfighters move up to flak frigates and the lancer to an ion frigate.
const WISH_LATE_FIRST := {"dog": "flak", "lancer": "ion"}

## The lists a fleet-composition call (the Admiral's "anti_capital" call) gives, keyed by
## temperament, with the seat of the pilot where the call picks one: one striker (seat 10)
## flies lances first, the other strikers bombers first, the lancer bombers first and one
## dogfighter (seat 8) a bomber.
const WISH_CALL := {
	"striker_seat10": ["lance", "bomber", "fighter"],
	"striker": ["bomber", "lance", "fighter"],
	"lancer": ["bomber", "lance", "fighter"],
	"dog_seat8": ["bomber", "fighter"],
}

## The hull the "anti_strike" call puts first for the dogfighters once the call's time has come.
const WISH_CALL_FIRST := "flak"

## The wing the two switches give: a Scout, a Fighter and a Bomber.
const TEST_WING := ["scout", "fighter", "bomber"]
