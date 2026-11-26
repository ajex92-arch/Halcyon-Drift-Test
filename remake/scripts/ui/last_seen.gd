class_name LastSeen
extends RefCounted
## WHAT THIS IS: the memory behind the minimap's last-seen marks (#107, part one): where each enemy ship was when the viewing team
## last saw it. While the fog hides an enemy ship, the minimap draws a faint disc at that last place, fading out over
## LAST_SEEN_FADE_S seconds, so the player can tell "it went that way" from "it is gone". Ships only: a minion gets no mark, and a
## structure keeps the last-known picture the minimap already draws for it. It draws nothing itself and changes nothing in the game
## (no field of a Unit or the World is written).
##
## HOW IT WORKS: the minimap calls update() each time it redraws (5 times a second, 10 while the pointer drags the camera; update()
## itself ignores a call less than MIN_GAP_S after the last one) and marks() when it draws. update() walks the units once. A living
## ship of another team that the viewer can see now is remembered at its place (one entry for each ship, keyed by its instance id; a
## ship seen again replaces its old place); one the viewer cannot see keeps its last place and starts to fade; a ship that died or
## left the game loses its entry, and so does an entry whose fade has run out. Whether the fog hides enemies at all is decided by the
## minimap and passed in (`fog_hides`: false with the test option No fog or with no viewing team), so this script never reads that
## option: with `fog_hides` false it remembers nothing and no mark is ever made.
## An entry is [place (Vector2), time last seen (match seconds), team, size class, the update it was last touched in, seen now (bool)].
##
## WHO USES IT: Minimap (update_last_seen() feeds it, _draw_units() draws marks()); tests/last_seen_check.gd checks it.

## How long a mark takes to fade out after the ship was last seen, in seconds of match time; the game uses 8.
const LAST_SEEN_FADE_S := 8.0
## The least time (seconds of match time) between two updates: at most 10 a second.
const MIN_GAP_S := 0.09

## The remembered ships: instance id -> an entry (see HOW IT WORKS).
var _seen := {}
## The match time of the last update that ran.
var _last := -1.0e9
## The number of the last update that ran (an entry not touched by it is gone).
var _round := 0


## Look at `units` once for the viewing team `vt` at match time `now`: remember the living enemy ships it can see, keep the ones it
## cannot, drop the dead and the faded. Does nothing when called less than MIN_GAP_S after the last update that ran. With `fog_hides`
## false (no fog, or no viewing team) it forgets everything and makes no mark.
func update(units: Array, vt: int, fog_hides: bool, now: float) -> void:
	if now >= _last and now - _last < MIN_GAP_S:
		return
	_last = now
	if not fog_hides or vt < 0:
		_seen.clear()
		return
	_round += 1
	var bit := 1 << vt
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		var unit := u as Unit
		if unit == null or not unit.alive or unit.kind != Unit.K_SHIP or unit.team == vt:
			continue
		var id := unit.get_instance_id()
		var e: Array = _seen.get(id, [])
		if (unit.visible_mask & bit) != 0:
			if e.is_empty():
				_seen[id] = [unit.global_position, now, unit.team, unit.size_class, _round, true]
			else:
				e[0] = unit.global_position
				e[1] = now
				e[2] = unit.team
				e[3] = unit.size_class
				e[4] = _round
				e[5] = true
		elif not e.is_empty():
			e[4] = _round
			e[5] = false
	var gone: Array = []
	for id in _seen:
		var e: Array = _seen[id]
		if int(e[4]) != _round or now - float(e[1]) >= LAST_SEEN_FADE_S:
			gone.append(id)
	for id in gone:
		_seen.erase(id)


## The marks to draw at match time `now`: one Dictionary for each ship that is out of sight, {"pos" (Vector2, world units), "alpha"
## (1 just after it was last seen, falling in a straight line to 0 at LAST_SEEN_FADE_S), "team", "size_class", "id"}.
func marks(now: float) -> Array:
	var out: Array = []
	for id in _seen:
		var e: Array = _seen[id]
		if bool(e[5]):
			continue
		var a := 1.0 - (now - float(e[1])) / LAST_SEEN_FADE_S
		if a <= 0.0:
			continue
		out.append({"pos": e[0], "alpha": minf(a, 1.0), "team": e[2], "size_class": e[3], "id": id})
	return out


## How many ships are remembered (seen now or out of sight), for the check.
func count() -> int:
	return _seen.size()
