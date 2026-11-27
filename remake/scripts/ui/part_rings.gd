class_name PartRings
extends RefCounted
## WHAT THIS IS: which ship parts the player may see and how each one looks: the list the HUD and the
## world view draw part rings from. It is pure and thin: it answers questions about a ship's parts and draws
## nothing, so a check can read the list with no picture. The user's rule is "own side, scanned enemies":
## rings always show on the player's own side's ships, and an enemy ship's rings show only while the
## player's team's scanners get through its jamming. Scanning and jamming do not exist yet, so for now no
## enemy ship shows any ring; visible_to() is the one place a scan test is added later.
##
## HOW IT WORKS: rings() returns one entry for each part of a visible ship: its id, its place on the hull
## (ship frame), its class, its state, its colour (bright green WORKING, dark red DEGRADED, near black OFF:
## green and red differ in brightness as the armour ring's do) and the climb: for a part that is offline,
## how far along its way back to the 15 percent line it is (0 until the delay is over, 1 at the line);
## 1 for a part that is online. There are no numbers or words in an entry: the picture shows the climb as
## an arc and nothing is ever written out.
##
## WHO USES IT: ShipStatus (the pips in the own-ship readout) and ShipVisual (the rings on big ships in
## the world view); the part rings check.

## The colour of a working part (bright green, the armour ring's whole colour).
const COLOUR_WORKING := Palette.REPAIR
## The colour of a degraded part (dark red, the armour ring's lost colour).
const COLOUR_DEGRADED := Color(0.62, 0.16, 0.14)
## The colour of an offline part (near black).
const COLOUR_OFF := Color(0.02, 0.02, 0.03)
## The colour a state has, in the order WORKING, DEGRADED, OFF (ShipSystems).
const STATE_COLOURS := [COLOUR_WORKING, COLOUR_DEGRADED, COLOUR_OFF]


## True when a player on team `viewer_team` may see the part rings of `ship`: today only the player's own
## side's ships. THE one place the scan test joins later (an enemy ship whose jamming the viewer's scanners
## get through).
static func visible_to(viewer_team: int, ship: Unit) -> bool:
	return ship != null and ship.team == viewer_team


## The rings of `ship` for a viewer on team `viewer_team`: [] when the viewer may not see them or the ship has
## no parts, else one Dictionary for each part: id, off (Vector2, ship frame), cls (ShipParts.CLASS_*), state
## (ShipSystems.WORKING, DEGRADED or OFF), colour (Color) and climb (0..1, see the top of the file).
static func rings(ship: Unit, viewer_team: int) -> Array:
	var out: Array = []
	if not visible_to(viewer_team, ship) or ship.parts == null:
		return out
	var parts: ShipSystems = ship.parts
	for i in parts.count():
		var row: Dictionary = parts.rows[i]
		var st := parts.state(i)
		out.append({"id": String(row["id"]), "off": row["off"], "cls": int(row["cls"]), "state": st,
			"colour": STATE_COLOURS[st], "climb": parts.climb_fraction(i)})
	return out
