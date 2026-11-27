class_name Absence
extends RefCounted
## WHAT THIS IS: a stopwatch for "the human Admiral has not touched anything". It counts ticks (a tick is
## one small step of game time, 60 a second) since the human Admiral's last input, so the deputy knows
## when the seat has been left alone for 30 seconds and for 90 seconds.
##
## HOW IT WORKS: two things count as input.
##   - An order of the Admiral's seat on the human's team, done or refused: the order queue files
##     "order_done" and "order_refused" records in the team's event stream, and read_orders() reads the
##     new ones once a tick (the deputy's own orders have the deputy seat and never count).
##   - A change of the flying controls of the human's own ship, or any control held down (thrust, strafe,
##     boost, guns, a one-off button, a shield or energy request): note_controls() compares them with the
##     last tick's. The aim point is left out: it is a point of the world under the mouse, so it moves with
##     the camera (a drifting ship, a hit that shakes the view) and cannot be told from a camera move. While
##     the command view or the Admiral board is open the ship coasts by itself and its controls are not the
##     player's (CoastController), so they are ignored then.
## A camera move, the mouse moving over the map, a pause and the hangar keys never count. The stopwatch
## draws no random number and reads no keyboard or mouse: it reads the order stream and the controls
## the order queue hands it, and a replay of the human puts the same orders and controls in, so it counts
## the same ticks.
##
## WHO USES IT: Deputy (one per human-Admiral team) asks ticks_away() and calls read_orders() every tick;
## OrderQueue.record_controls() reaches note_controls() through Deputy; tests/deputy_check.gd.

## Ticks of no input after which the deputy counts the human as away (30 seconds).
const AWAY_TICKS := 1800
## Ticks of no input after which the seat counts as open (90 seconds).
const OPEN_TICKS := 5400
## The game world.
var world: World
## The team of the human Admiral.
var team := 0
## The tick of the last input (the tick the stopwatch was made, until there is one).
var last_input := 0
## What the last input was (order, or the control that was held, pressed or changed): for tests and the log of a check.
var last_why := "start"
## The next index of the team's event stream to read.
var _cursor := 0
## The held controls of the last tick that were looked at: [forward, strafe, boost, fire], or [] for none yet.
var _last: Array = []


## Start the stopwatch for `t`'s human Admiral in world `w`: the count starts now and only the orders from now on are read.
func _init(w: World, t: int) -> void:
	world = w
	team = t
	last_input = w.tick_count
	if w.events_rts != null:
		_cursor = w.events_rts.next_index(t)


## Read the team's new records: each order of the Admiral's seat, done or refused, is an input on its tick.
func read_orders() -> void:
	if world.events_rts == null:
		return
	var next := world.events_rts.next_index(team)
	for rec: Dictionary in world.events_rts.read_from(team, _cursor):
		var k := str(rec.get("kind", ""))
		if k != "order_done" and k != "order_refused":
			continue
		var data: Dictionary = rec.get("data", {})
		if int(data.get("seat", -1)) == Rules.ADMIRAL_SEAT:
			if int(rec.get("tick", 0)) >= last_input:
				last_input = int(rec.get("tick", 0))
				last_why = "order"
	_cursor = next


## Look at the flying controls `c` of the human's ship on this tick: any control held down, any one-off request, or any
## change of a held control since the last tick is an input. The aim point is not looked at (see the top). Nothing is
## counted while the ship coasts.
func note_controls(c: ShipControls) -> void:
	if CoastController.holding(world):
		_last = []
		return
	var now: Array = [c.forward, c.strafe, c.boost, c.fire]
	var why := ""
	if c.forward != 0.0 or c.strafe != 0.0:
		why = "thrust"
	elif c.boost or c.fire:
		why = "boost or fire"
	elif c.special or c.cancel_run or c.use_kit or c.dock or c.focus_request != -1 or c.energy_request != -1:
		why = "one-off request"
	elif not _last.is_empty() and now != _last:
		why = "change of a held control"
	if why != "":
		last_input = world.tick_count
		last_why = why
	_last = now


## How many ticks have passed since the last input that read_orders() and note_controls() have seen.
func ticks_away() -> int:
	return world.tick_count - last_input
