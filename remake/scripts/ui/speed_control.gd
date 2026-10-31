class_name SpeedControl
extends RefCounted
## WHAT THIS IS: the one place every change of the game's speed goes through: the backquote key
## (slower speeds), Shift plus it (faster speeds) and the buttons of the speed row. Speeds are
## written in hundredths of normal speed: 50, 75, 100, 150 and 200 mean 0.5x, 0.75x, 1x, 1.5x
## and 2x.
##
## HOW IT WORKS: slow_steps() and fast_steps() are the two lists the keys step through, read from
## the world-speed setting (WorldSpeed.STEPS and WorldSpeed.FAST_STEPS: 1x, 1.5x, 2x; a setting
## with no faster list gives an empty one, and then the row and the key offer the slow speeds
## only). next() gives the speed a key press goes to: the next one on the pressed key's own list,
## or normal speed when the world is at a speed that is not on that list (so Shift plus the key from
## 0.75x first returns to 1x). send() makes the change and returns the reason it was refused, or ""
## when it was made: it hands the order queue a GAME_SPEED order (OrderQueue.submit()), which carries
## it out at once, logs it and checks it (a speed of ours, and not a match with two human seats), and
## turns the queue's refusal text into the words below. allowed() says whether the player may change
## the speed at all: not when the match has two human seats (OrderQueue.human_seats()). Asking for
## something the world-speed setting may not have is done by name, so this file loads whether or
## not it has.
##
## WHO USES IT: HudInput (the two speed keys), SpeedRow (the buttons), HudTopBar (the "limited" tag
## through limited()) and tests/controls_page_check.gd.

## Every speed the game knows, in hundredths of normal speed, slowest first.
const ALL := [50, 75, 100, 150, 200]
## The words send() gives for the order queue's refusal "unbuilt" (nothing carries out the order).
const NOT_READY := "Comes with a later stage"
## The words send() gives for a number that is not a speed of ours (the queue's refusal "value").
const NOT_A_SPEED := "Not a speed we have"
## What the speed row says when a match with other people does not allow changing the speed (the
## queue's refusal "online").
const ONLINE := "Against the computer only"
## What a faster key says while there is no faster speed to go to.
const NO_FAST_YET := "Faster speeds are not ready yet"

## Test and picture scripts only: when not empty, fast_steps() gives this list instead, so the speed row
## can be photographed with its faster buttons before the game can run them. Empty in the game.
static var test_fast_steps := []


## The slower speeds in the order the backquote key steps through them: 100, 75, 50.
static func slow_steps() -> Array:
	var out := []
	for f in WorldSpeed.STEPS:
		out.append(roundi(float(f) * 100.0))
	return out


## The faster speeds in the order Shift plus the key steps through them (100, 150, 200), or an
## empty list when the world-speed setting has none (no WorldSpeed.FAST_STEPS).
static func fast_steps() -> Array:
	if not test_fast_steps.is_empty():
		return test_fast_steps.duplicate()
	var script: Script = WorldSpeed
	var consts: Dictionary = script.get_script_constant_map()
	var out := []
	if not consts.has("FAST_STEPS"):
		return out
	for f in consts["FAST_STEPS"]:
		# A speed above 10 is already in hundredths; a smaller one is a factor.
		out.append(roundi(float(f)) if float(f) > 10.0 else roundi(float(f) * 100.0))
	return out


## Every speed the row shows, slowest first, without repeats: the slow speeds and, when there are
## any, the faster ones.
static func all_steps() -> Array:
	var out := []
	for h in slow_steps() + fast_steps():
		if not out.has(h):
			out.append(h)
	out.sort()
	return out


## The world's speed now, in hundredths (a launch option such as --slow=0.3 gives 30).
static func current(world: World) -> int:
	return roundi(world.speed.factor * 100.0)


## The speed words players read for `hundredths`: "0.5x", "0.75x", "1x", "1.5x", "2x".
static func label_of(hundredths: int) -> String:
	return "%sx" % ("%.2f" % (float(hundredths) / 100.0)).rstrip("0").rstrip(".")


## The speed a press of the slower key (`faster` false) or the faster key goes to, in hundredths, or
## -1 when that key has no speed to go to. A world at a speed that is not on the key's own list
## goes to normal speed first.
static func next(world: World, faster: bool) -> int:
	var steps := fast_steps() if faster else slow_steps()
	if steps.is_empty():
		return -1
	var i := steps.find(current(world))
	return int(steps[(i + 1) % steps.size()]) if i >= 0 else 100


## Change the world's speed to `hundredths`. Returns "" when it was changed, else the reason it was
## refused (the words the screens show). The change is a GAME_SPEED order from the human's seat (the
## Admiral's, or the pilot's own; a match with no human sends it from the test seat), submitted to
## World.orders, which carries it out at once, even while the game is paused. A number that is not
## one of ALL is refused here, before an order is made. The queue's refusals are turned into words:
## "online" into ONLINE, "value" into NOT_A_SPEED, "unbuilt" into NOT_READY; any other refusal
## keeps the queue's own text.
static func send(world: World, hundredths: int) -> String:
	if not ALL.has(hundredths):
		return NOT_A_SPEED
	var seat: int = Rules.ADMIRAL_SEAT if world.human_role == "admiral" else (world.human.slot if world.human != null else OrderKinds.TEST_SEAT)
	var order := Order.make(OrderKinds.GAME_SPEED, world.human_team, seat, seat != OrderKinds.TEST_SEAT, {"hundredths": hundredths})
	var msg := world.orders.submit(order)
	match OrderKinds.reason_code(msg):
		"ok":
			return ""
		"online":
			return ONLINE
		"value":
			return NOT_A_SPEED
		"unbuilt":
			return NOT_READY
	return msg


## May the player change the speed in this match? Not when two human seats play (the order queue
## refuses the speed order then): a match against the computer, with one human or none, allows it.
static func allowed(world: World) -> bool:
	return world.orders.human_seats() < 2


## Is the world running fewer ticks than its speed asks for (a slow PC at a fast speed)? The answer
## of WorldSpeed.limited(), asked by name; false for a setting that has none. For the screen only.
static func limited(world: World) -> bool:
	return world.speed.has_method("limited") and bool(world.speed.call("limited"))
