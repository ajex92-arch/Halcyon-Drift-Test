class_name SelectionTools
extends RefCounted
## WHAT THIS IS: the rest of the Admiral's selection (the "idle" keys): I selects the next idle squadron and centres the
## camera on it, Ctrl+I selects every idle squadron without moving the camera. An idle squadron is a bought squadron or
## ship whose state is idle and that holds no order.
##
## HOW IT WORKS: a plain object the command view makes once. idle_ids() reads the squad records, in id order. next() takes the
## first idle squadron after the one taken last (and wraps), so I pressed again walks through them all. Both put the
## answer into the selection through the overlay (replacing it, or adding while the Add toggle is on) and say what
## they did on the card's result line. Nothing here gives an order or changes the match: it reads the squad
## records and moves the selection and the camera, which are screen state.
##
## WHO USES IT: CommandView (owns it, calls the keys), ArmyCards (the Idle card);
## tests/rts_ui_check.gd.

## The squadron taken last by next() (-1 for none yet).
var last := -1
## The match, the Admiral's team and the map layer (set by setup()).
var world: World
var team := 0
var overlay: CommandOverlay


## Remember the match. CommandView calls this once.
func setup(w: World, ov: CommandOverlay, t: int) -> void:
	world = w
	overlay = ov
	team = t


## Is squad record `rec` idle: state idle and no order standing?
static func is_idle(rec: Squad) -> bool:
	return rec.state == 0 and rec.order.is_empty()


## The ids of our idle squadrons, in id order.
func idle_ids() -> Array[int]:
	var out: Array[int] = []
	for rec: Squad in RtsSelect.our_squads(world, team):
		if is_idle(rec):
			out.append(rec.id)
	return out


## The next idle squadron after `last` (wrapping round), or -1 when none is idle. Does not select anything.
func peek_next() -> int:
	var ids := idle_ids()
	if ids.is_empty():
		return -1
	for id in ids:
		if id > last:
			return id
	return ids[0]


## The I key (and a click on the Idle card): select the next idle squadron and, when `centre`, put the camera on it.
## Returns true when there was one.
func next(centre: bool = true) -> bool:
	var id := peek_next()
	if id < 0:
		overlay.say("No idle squadron.", true)
		return false
	last = id
	var one: Array[int] = [id]
	overlay.set_selection(one, false, overlay.add_mode)
	if centre:
		var rec: Squad = world.squads[id]
		Groups.centre_on(world, RtsSelect.centre_of(world, rec))
	overlay.say("Idle squadron selected.", true)
	return true


## The Ctrl+I key (and a double-click on the Idle card): select every idle squadron, the camera stays where it is.
## Returns true when there was any.
func all() -> bool:
	var ids := idle_ids()
	if ids.is_empty():
		overlay.say("No idle squadron.", true)
		return false
	overlay.set_selection(ids, false, overlay.add_mode)
	overlay.say("%s idle selected." % RtsSquadOrders.squads_word(ids.size()), true)
	return true

