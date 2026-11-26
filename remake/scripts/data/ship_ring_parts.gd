class_name ShipRingParts
extends RefCounted
## WHAT THIS IS: the list of the parts the pilot's own ship ring set is made of (the shield arcs, the hull arc, the route triangle,
## the warning marks, the time-to-impact number, the hit notch, the heading tick, the turn arc and the stop-here ghost), the three
## presets that switch groups of them on (Full, Compact, Minimal), and the one question every drawing of a part asks first: is this
## part shown?
##
## HOW IT WORKS: PARTS lists the nine ids in drawing order, each with its words for the menu. PRESETS lists, for each preset, which
## parts it shows. Game keeps two remembered choices: `ring_preset` (0 Full, 1 Compact, 2 Minimal) and `ring_parts_off` (parts the
## player switched off one by one, whatever the preset says). shown() answers: the preset shows the part and the player has not
## switched it off. Nothing here draws anything and nothing here reads the match: it only reads those two settings.
##
## WHO USES IT: the turn cues (TurnCues: the heading tick, the turn arc and the ghost) ask shown() for their three parts; the ring
## drawing (the shield arcs, hull arc, route triangle, warning marks, number and notch) asks it for the others; Game remembers the
## choices (choose_ring_preset(), choose_ring_part()) and the pause menu shows them; tests/flight_cues_check.gd checks the table.

## The Full preset: every part.
const PRESET_FULL := 0
## The Compact preset: no route triangle (the ship readout shows the route), no time-to-impact number, no turn arc; the heading
## tick stays as the short tick.
const PRESET_COMPACT := 1
## The Minimal preset: the shield arcs, the warning marks and the hit notch only.
const PRESET_MINIMAL := 2

## The parts, in drawing order: id and the words the pause menu shows for it.
const PARTS := [
	{"id": "shield_arcs", "label": "Shield arcs"},
	{"id": "hull_arc", "label": "Hull arc"},
	{"id": "route_triangle", "label": "Energy route"},
	{"id": "warning_marks", "label": "Torpedo warning"},
	{"id": "impact_number", "label": "Time to impact"},
	{"id": "hit_notch", "label": "Hit direction"},
	{"id": "heading_tick", "label": "Heading tick"},
	{"id": "turn_arc", "label": "Turn arc"},
	{"id": "ghost", "label": "Stop marker"},
]

## The presets, by number: the words and the part ids each one shows.
const PRESETS := [
	{"name": "Full", "parts": ["shield_arcs", "hull_arc", "route_triangle", "warning_marks", "impact_number", "hit_notch", "heading_tick", "turn_arc", "ghost"]},
	{"name": "Compact", "parts": ["shield_arcs", "hull_arc", "warning_marks", "hit_notch", "heading_tick", "ghost"]},
	{"name": "Minimal", "parts": ["shield_arcs", "warning_marks", "hit_notch"]},
]


## Every part id, in drawing order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in PARTS:
		out.append(String(p["id"]))
	return out


## Is `part` a known part id?
static func is_part(part: String) -> bool:
	for p: Dictionary in PARTS:
		if String(p["id"]) == part:
			return true
	return false


## The part ids preset number `preset` shows (an unknown number counts as Full).
static func parts_of(preset: int) -> PackedStringArray:
	var row: Dictionary = PRESETS[preset] if preset >= 0 and preset < PRESETS.size() else PRESETS[PRESET_FULL]
	return PackedStringArray(row["parts"])


## The preset's name ("Full", "Compact", "Minimal"; an unknown number counts as Full).
static func preset_name(preset: int) -> String:
	return String((PRESETS[preset] if preset >= 0 and preset < PRESETS.size() else PRESETS[PRESET_FULL])["name"])


## Does preset number `preset` show `part`? The player's single switches (Game.ring_parts_off) are not counted here.
static func preset_has(preset: int, part: String) -> bool:
	return parts_of(preset).has(part)


## Is `part` drawn now? The chosen preset shows it and the player has not switched it off. An unknown part is never shown.
## Both builds of the ring set (the turn cues and the ring) call this before drawing a part.
static func shown(part: String) -> bool:
	if not is_part(part):
		return false
	return preset_has(Game.ring_preset, part) and not Game.ring_parts_off.has(part)
