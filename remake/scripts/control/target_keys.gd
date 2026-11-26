class_name TargetKeys
extends RefCounted
## WHAT THIS IS: the pilot's target. One key (Caps Lock) and one click (the middle mouse button) mark an enemy as "my target": the
## enemy nearest the mouse pointer that the human's team can see. A second press on the enemy that is already the target marks the
## last enemy that hurt the pilot's ship instead. Esc lets the target go. When the target dies the next enemy nearest the pointer
## becomes the target. The target is only a mark the pilot's own screen shows (the target card); nothing in the match reads it.
##
## HOW IT WORKS: static functions only, no memory of its own. The target is stored as a uid in the held field
## ShipControls.target_id of the ship the human flies (-1 = no target), the one field this part writes. The match log's controls line
## never names it, so the log and replay formats stay as they were.
##   - my_ship(): the ship the human flies while it is flying and alive; null otherwise, and null while the Admiral's board or command
##     view is open over the flight (the ship then coasts).
##   - press(): the Caps Lock press, or the middle click released within a few pixels of where it went down (HudInput tells them
##     apart from a drag). Candidates are the live units of the other team (never neutral) that the human's team can see right now,
##     found by walking World.units (never a Dictionary's order). The pick is the candidate nearest the pointer (squared distance, the
##     lower uid on a tie). A press whose pick is the held target picks the last attacker: the entry with the newest hit time in the
##     ship's damage_log whose unit is a candidate (the lower uid on a tie); with none, the target stays.
##   - clear(): Esc. True when a target was held and is now let go.
##   - tick(): once a frame. A held target that is freed or dead is replaced by the candidate nearest the pointer (AUTO_NEXT), or let
##     go when there is none. A held target that is merely out of sight stays held.
## An enemy the team cannot see is never picked and never shown: the card draws nothing for a held target it cannot see.
##
## WHO USES IT: HudInput (the key, the middle click, Esc and the once-a-frame call), ShipRing and TargetCard (they show the ship and the
## target), tests/target_check.gd.

## When the target dies, the next enemy nearest the pointer takes its place (a constant, not a setting).
const AUTO_NEXT := true
## The value of ShipControls.target_id when there is no target.
const NONE := -1


## The ship the human flies, while it is flying and alive; otherwise null. Also null while the command view or the Admiral's board is
## open over the flight (mode 3: the ship coasts and the pilot's keys are the Admiral's). The same test as TurnCues.cue_ship().
static func my_ship(world: World) -> Ship:
	var me := world.human if world != null else null
	if me == null or me.state != "flying" or me.ship == null or not is_instance_valid(me.ship) or not me.ship.alive or world.mode3():
		return null
	return me.ship


## Can the human's team pick `u` now? It is a live unit of the other team (not neutral) and the human's team sees it.
static func is_candidate(world: World, u: Variant) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	var unit := u as Unit
	if unit == null or not unit.alive:
		return false
	if unit.team != Rules.HALCYON and unit.team != Rules.CINDER:
		return false
	if unit.team == world.human_team:
		return false
	return unit.visible_to(world.human_team)


## The candidate nearest world point `p` (squared distance; the lower uid on a tie), or null when there is none. Walks World.units.
static func nearest(world: World, p: Vector2) -> Unit:
	var best: Unit = null
	var best_d := 0.0
	for i in world.units.size():
		var o: Variant = world.units[i]
		if not is_candidate(world, o):
			continue
		var u := o as Unit
		var d := p.distance_squared_to(u.global_position)
		if best == null or d < best_d or (d == best_d and u.uid < best.uid):
			best = u
			best_d = d
	return best


## The last enemy that hurt `ship`: among the units in its damage_log that are candidates, the one with the newest hit time (the
## lower uid on a tie), or null when there is none.
static func last_attacker(world: World, ship: Ship) -> Unit:
	var best: Unit = null
	var best_t := 0.0
	for uid: Variant in ship.damage_log:
		var u: Variant = world.by_uid.get(uid)
		if not is_candidate(world, u):
			continue
		var t := float((ship.damage_log[uid] as Array)[1])
		if best == null or t > best_t or (t == best_t and int(uid) < best.uid):
			best = u as Unit
			best_t = t
	return best


## The unit the human's ship holds as its target while it is alive (seen or not), or null.
static func held_unit(world: World, ship: Ship) -> Unit:
	var id := ship.controls.target_id
	if id < 0:
		return null
	var u: Variant = world.by_uid.get(id)
	if u == null or not is_instance_valid(u) or not (u as Unit).alive:
		return null
	return u as Unit


## A press of the target key or a click of the target button: mark the enemy nearest the pointer, or the last attacker when that enemy
## is the target already. `hud` (may be null) says so in a pop-up when there is no enemy to pick.
static func press(world: World, hud: Hud) -> void:
	var ship := my_ship(world)
	if ship == null:
		return
	var pick := nearest(world, world.mouse_world())
	var held := held_unit(world, ship)
	if pick != null and held != null and pick.uid == held.uid:
		var last := last_attacker(world, ship)
		if last != null:
			ship.controls.target_id = last.uid
		return
	if pick != null:
		ship.controls.target_id = pick.uid
	elif hud != null:
		hud.toast("No enemy in sight to target")


## Esc: let the target go. True when a target was held and is now cleared (so Esc is used up); false when there was none.
static func clear(world: World) -> bool:
	var ship := my_ship(world)
	if ship == null or ship.controls.target_id < 0:
		return false
	ship.controls.target_id = NONE
	return true


## Once a frame: a held target that is freed or dead is replaced by the candidate nearest the pointer (AUTO_NEXT), or let go when there
## is none. A target that is only out of sight stays held.
static func tick(world: World) -> void:
	var ship := my_ship(world)
	if ship == null or ship.controls.target_id < 0:
		return
	if held_unit(world, ship) != null:
		return
	var next: Unit = nearest(world, world.mouse_world()) if AUTO_NEXT else null
	ship.controls.target_id = next.uid if next != null else NONE
