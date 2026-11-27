class_name SquadronRules
extends RefCounted
## WHAT THIS IS: every number and word of the bought squadrons' jobs engine in one place: how often a
## squadron thinks, how far each move stance looks and chases, the goal words, the push and the
## "blocked" numbers, and the switch that picks the new brain or the old stand-in. Nothing here
## keeps a node or rolls a die; the numbers are the designers' tuning (a feel check may change them).
##
## HOW IT WORKS: constants and static functions only. The two brain values a squadron record can
## carry for its ships are "squad" (the new brain, SquadronBrain, thought for by SquadronThink) and
## "standin" (the old PilotAI stand-in, Standin). The yard writes "squad" while `use_squad_brain` is
## true and "standin" while it is false; the arrival code attaches the brain the record names. A test
## that checks the stand-in's own internals sets the switch false on its first line. The numbers of a
## move stance (hold, manoeuvre, roam) come from chase_limit() and scan_radius(); both are measured
## from the anchor (the slot for hold), never from the chasing ship, so a chasing ship cannot drag the
## squadron away.
##
## WHO USES IT: Production (the yard's brain value and the think call), Arrivals (the attach by brain),
## SquadronThink, SquadronBrain, GoalPoints, SquadOrders (the goal words) and tests/squad_check.gd.

## True: bought squadrons are flown by the new brain. False: by the stand-in, byte for byte as before.
## The stand-in itself is removed in a later stage.
static var use_squad_brain := true

## The brain value of a squadron flown by SquadronBrain.
const BRAIN_SQUAD := "squad"
## The brain value of a squadron flown by the stand-in.
const BRAIN_STANDIN := "standin"

## Ticks between two thinks of one squadron (four a second).
const THINK_EVERY := 15
## Ticks without a target after which the ships go back to their slots ("hold and fight nearby").
const RESUME_TICKS := 180

## Hold: chase at most this far (world units) from the ship's own slot.
const HOLD_CHASE := 250.0
## Hold: the scan radius is the ship's main gun reach plus this.
const HOLD_REACH_PAD := 200.0
## Manoeuvre: chase at most the gun reach plus this far from the anchor.
const MANOEUVRE_PAD := 1200.0
## Manoeuvre: the scan radius around the anchor.
const MANOEUVRE_SCAN := 1400.0
## Roam: chase at most this far from the anchor (the AI pilots' longest hunt).
const ROAM_CHASE := 3200.0
## Roam: the scan radius around the anchor.
const ROAM_SCAN := 2000.0

## A guide this close to its anchor counts as arrived, and the ships hold slots round the anchor.
const ANCHOR_NEAR := 300.0
## A guide farther than this from its anchor is on its way again (the arrived mark is dropped).
const ANCHOR_FAR := 900.0
## A one-off Move ends when the guide is this close to the point (and no enemy has been near for RESUME_TICKS).
const MOVE_END := 600.0
## While any member is catching up the guide flies at this fraction of the throttle.
const CATCH_THROTTLE := 0.85
## An enemy that hurt a member this many seconds ago still counts for "return fire".
const RETURN_FIRE_SECS := 6.0

## A push anchor sits this far ahead of our minion front, toward the enemy.
const PUSH_LEAD := 600.0
## A push anchor is worked again every this many ticks.
const PUSH_EVERY := 60
## A push never stands inside an enemy lane turret's reach (the fleet's own keep-out distance).
const TURRET_REACH := 2500.0
## A push that has no enemy structure left holds this far from the enemy mothership (its ion reach plus a pad).
const MOTHERSHIP_KEEP := 2600.0
## Only minions within this distance of the lane line count for the minion front.
const FRONT_BAND := 2500.0

## A guide that gains less than this on its anchor ...
const BLOCKED_GAIN := 300.0
## ... in this many ticks counts as blocked (no route).
const BLOCKED_TICKS := 600
## A blocked squadron tries again every this many ticks.
const RETRY_TICKS := 1800

## Goal order words (the same words as the order kinds).
const GOAL_KINDS := [OrderKinds.DEFEND, OrderKinds.ESCORT, OrderKinds.PUSH_LANE]


## Is `kind` one of the goal order words (Defend, Escort, Push lane)?
static func is_goal(kind: String) -> bool:
	return GOAL_KINDS.has(kind)


## How far (world units) a ship may chase from its leash point in move stance `move` (0 hold, 1 manoeuvre,
## 2 roam) when its main gun reaches `reach`.
static func chase_limit(move: int, reach: float) -> float:
	if move == 0:
		return HOLD_CHASE
	if move == 2:
		return ROAM_CHASE
	return reach + MANOEUVRE_PAD


## How far (world units) from the anchor the squadron looks for a target in move stance `move` when the
## main gun of its ships reaches `reach`.
static func scan_radius(move: int, reach: float) -> float:
	if move == 0:
		return reach + HOLD_REACH_PAD
	if move == 2:
		return ROAM_SCAN
	return MANOEUVRE_SCAN


## May a target at `dist` from the anchor still be kept (picked earlier) in move stance `move`? A hold keeps
## it up to the scan radius plus the chase leash; the others up to the chase limit.
static func keep_limit(move: int, reach: float) -> float:
	if move == 0:
		return scan_radius(0, reach) + HOLD_CHASE
	return chase_limit(move, reach)


## Turn the new brain on (true) or off (false) for the squads made from now on.
static func set_switch(on: bool) -> void:
	use_squad_brain = on


## Is the new brain on?
static func switch_on() -> bool:
	return use_squad_brain
