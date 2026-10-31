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
##                   0.2 = the hull takes 20% less damage]
##     shield_resist the same for the shield
##   Battery (energy, spent by guns, boosting and the special):
##     energy        how much the battery holds [energy points]
##     energy_regen  how fast it refills [energy per second]
##   Flight: not here. How a hull flies (speed, engine push, turning, boost)
##   is its row in the handling table, Handling.TABLE (handling.gd).
##   Body:
##     vision        how far the ship sees [world units]
##     radius        collision size, a circle [world units]
##     length        how long ShipVisual draws the ship [world units]
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
##   Special ability (one per hull; ShipAbilities runs it):
##     special         the ability's id
##     special_cd      how long before it can be used again [seconds]
##     special_energy  what it costs [energy]
##     special_label   its name for players
##     special_info    what it does, in words for players
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
## To add a hull: add an entry, add its id to ORDER, give it a silhouette in
## ShipVisual.HULLS, a steel Aurelian drawing in AurelianShapes.HULLS and an
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
		"blurb": "Fastest ship, widest vision",
		"hull": 70.0, "shield": 120.0, "shield_regen": 16.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 100.0, "energy_regen": 30.0,
		"vision": 3000.0, "radius": 9.0, "length": 20.0,
		"mounts": [{"w": "scout_gun", "type": "fixed", "off": Vector2(10, 0), "arc": 0.0}],
		"special": "ping", "special_cd": 14.0, "special_energy": 35.0,
		"special_label": "Ping", "special_info": "reveals every enemy within 4,500 for 3s, even behind asteroids",
	},
	# Fighter (small): the all-round dogfighter. Its cannon has a small_bonus
	# of 1.25 (weapons.gd), which is the "+25% against small ships" (applied
	# only while the damage modifiers are kept).
	"fighter": {
		"label": "Fighter", "size": 0, "price": 150.0, "unlock": "",
		"blurb": "Agile dogfighter",
		"blurb_removed": "Agile dogfighter",
		"hull": 100.0, "shield": 200.0, "shield_regen": 18.0, "hull_resist": 0.0, "shield_resist": 0.0,
		"energy": 100.0, "energy_regen": 26.0,
		"vision": 2400.0, "radius": 12.0, "length": 26.0,
		"mounts": [{"w": "fighter_cannon", "type": "fixed", "off": Vector2(12, 0), "arc": 0.0}],
		"special": "snap", "special_cd": 8.0, "special_energy": 20.0,
		"special_label": "Snap turn", "special_info": "turns twice as fast for 1.5s",
	},
	# Lance Fighter (small): a beam fighter, unlocked by Lance Beams research.
	"lance": {
		"label": "Lance Fighter", "size": 0, "price": 300.0, "unlock": "lanceBeams",
		"blurb": "Heavy Strike Craft",
		"blurb_removed": "Heavy Strike Craft",
		"hull": 110.0, "shield": 220.0, "shield_regen": 18.0, "hull_resist": 0.05, "shield_resist": 0.0,
		"energy": 120.0, "energy_regen": 32.0,
		"vision": 2400.0, "radius": 13.0, "length": 30.0,
		"mounts": [{"w": "lance_beam", "type": "fixed", "off": Vector2(15, 0), "arc": 0.0}],
		"special": "overload", "special_cd": 12.0, "special_energy": 30.0,
		"special_label": "Overload", "special_info": "beam damage +60% for 2.5s",
	},
	# Bomber (small, but slow and without a booster): torpedoes against big
	# targets, unlocked by Fusion Bombs research.
	"bomber": {
		"label": "Bomber", "size": 0, "price": 350.0, "unlock": "fusionBombs",
		"blurb": "Slow torpedo ship",
		"blurb_removed": "Slow torpedo ship",
		"hull": 170.0, "shield": 240.0, "shield_regen": 16.0, "hull_resist": 0.1, "shield_resist": 0.0,
		"energy": 120.0, "energy_regen": 22.0,
		"vision": 2300.0, "radius": 17.0, "length": 46.0,
		"mounts": [{"w": "torpedo", "type": "fixed", "off": Vector2(24, 0), "arc": 0.0},
				{"w": "tail_gun", "type": "auto", "off": Vector2(-10.9, 0), "arc": 60.0, "face": 180.0}],
		"special": "focus", "special_cd": 7.0, "special_energy": 25.0,
		"special_label": "Focus shot", "special_info": "next run's torpedoes deal +45% damage",
	},
	# Logistics Corvette (medium): the healer, unlocked by building the
	# Corvette Facility. It carries 2 repair drones.
	"logistics": {
		"label": "Logistics Corvette", "size": 1, "price": 500.0, "unlock": "fac:corvette",
		"blurb": "Repair corvette",
		"hull": 380.0, "shield": 420.0, "shield_regen": 22.0, "hull_resist": 0.1, "shield_resist": 0.0,
		"energy": 150.0, "energy_regen": 22.0,
		"vision": 2600.0, "radius": 44.0, "length": 95.0,
		"mounts": [{"w": "light_turret", "type": "turret", "off": Vector2(20, 0), "arc": 100.0}],
		"repair_drones": 2,
		"special": "emergency_repair", "special_cd": 18.0, "special_energy": 50.0,
		"special_label": "Emergency repair", "special_info": "heals allies within 650 by 12% of their hull",
	},
	# Support Corvette (medium): big vision and an aura that buffs allies,
	# unlocked by Command Systems research.
	"support": {
		"label": "Support Corvette", "size": 1, "price": 550.0, "unlock": "commandSystems",
		"blurb": "Command corvette",
		"blurb_removed": "Command corvette",
		"hull": 300.0, "shield": 500.0, "shield_regen": 26.0, "hull_resist": 0.05, "shield_resist": 0.05,
		"energy": 180.0, "energy_regen": 30.0,
		"vision": 4200.0, "radius": 44.0, "length": 90.0,
		"mounts": [{"w": "light_turret", "type": "turret", "off": Vector2(16, 0), "arc": 130.0}],
		"aura": true,
		"special": "jam", "special_cd": 16.0, "special_energy": 60.0,
		"special_label": "Jam", "special_info": "cuts enemy vision within 1,400 to a quarter for 7s",
	},
	# Flak Frigate (large): holds a lane against strike craft, unlocked by
	# building the Frigate Facility.
	"flak": {
		"label": "Flak Frigate", "size": 2, "price": 1100.0, "unlock": "fac:frigate",
		"blurb": "Flak lane anchor",
		"blurb_removed": "Flak lane anchor",
		"hull": 1000.0, "shield": 900.0, "shield_regen": 30.0, "hull_resist": 0.15, "shield_resist": 0.05,
		"energy": 200.0, "energy_regen": 25.0,
		"vision": 2700.0, "radius": 87.5, "length": 262.5,
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
		"blurb": "Ion beam frigate",
		"blurb_removed": "Ion beam frigate",
		"hull": 850.0, "shield": 1000.0, "shield_regen": 30.0, "hull_resist": 0.12, "shield_resist": 0.05,
		"energy": 220.0, "energy_regen": 30.0,
		"vision": 2900.0, "radius": 85.0, "length": 275.0,
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
		"blurb": "Heavy-gun capital ship",
		"hull": 2400.0, "shield": 1800.0, "shield_regen": 45.0, "hull_resist": 0.2, "shield_resist": 0.08,
		"energy": 300.0, "energy_regen": 35.0,
		"vision": 3100.0, "radius": 180.0, "length": 630.0,
		"mounts": [
			{"w": "heavy_cannon", "type": "turret", "off": Vector2(180, 0), "arc": 150.0},
			{"w": "heavy_cannon", "type": "turret", "off": Vector2(-90, 0), "arc": 150.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(90, -105), "arc": 180.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(90, 105), "arc": 180.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(-210, 0), "arc": 180.0},
			{"w": "flak_auto", "type": "auto", "off": Vector2(0, 0), "arc": 180.0},
		],
		"special": "overcharge", "special_cd": 20.0, "special_energy": 80.0,
		"special_label": "Overcharge", "special_info": "every gun fires twice as fast for 5s",
	},
	# Battlecruiser (capital): the heaviest and most expensive hull, unlocked
	# by Battlecruiser Chassis research.
	"battlecruiser": {
		"label": "Battlecruiser", "size": 3, "price": 3800.0, "unlock": "battlecruiserChassis",
		"blurb": "The heaviest hull",
		"hull": 4200.0, "shield": 3000.0, "shield_regen": 60.0, "hull_resist": 0.25, "shield_resist": 0.1,
		"energy": 400.0, "energy_regen": 40.0,
		"vision": 3300.0, "radius": 240.0, "length": 840.0,
		"mounts": [
			{"w": "ion_turret", "type": "turret", "off": Vector2(255, 0), "arc": 140.0},
			{"w": "ion_turret", "type": "turret", "off": Vector2(-195, 0), "arc": 140.0},
			{"w": "heavy_cannon", "type": "turret", "off": Vector2(45, 0), "arc": 150.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(180, -135), "arc": 180.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(180, 135), "arc": 180.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(-270, -120), "arc": 180.0},
			{"w": "pd_gun", "type": "auto", "off": Vector2(-270, 120), "arc": 180.0},
			{"w": "flak_auto", "type": "auto", "off": Vector2(90, 0), "arc": 180.0},
			{"w": "flak_auto", "type": "auto", "off": Vector2(-120, 0), "arc": 180.0},
		],
		"special": "broadside", "special_cd": 25.0, "special_energy": 120.0,
		"special_label": "Broadside", "special_info": "all weapons fire 50% faster for 6s",
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

