class_name Squad
extends RefCounted
## WHAT THIS IS: the squadron record. One small plain object that says which ships
## belong together, who owns them, what they were told to do and where they gather.
## A bought squadron of three small ships is one record, a bought big ship is one
## record, and a pilot's wingman is one record each. It holds data and nothing else:
## no engine logic, no node references (ships are named by their unit id number),
## whole numbers only.
##
## HOW IT WORKS: whoever makes a squad (the yard when a build starts, the wing
## maker when a wingman is added) builds one with Squad.new(), fills the fields it
## owns and stores it in World.squads under its id. Later code reads and writes the
## fields named below; the "who sets it" note on each field says who is allowed to.
## A wing is several records that share a wing_id: the record whose own id equals
## its wing_id is the wing's first (lead) record, and an order sent to the wing is
## written to every living record with that wing_id.
##
## WHO USES IT: the yard (production, arrivals, the stand-in brain) for bought
## ships; the wingmen code and the squad engine for wings; the order handlers write
## the stances, formation and order; the Crew profile points back to its record by
## squad_id.

## The record's number. Unique in the match, taken from the world registry's counter.
## Set by the maker.
var id: int = -1

## The team: 0 or 1. Set by the maker.
var team: int = 0

## Who owns it: the Admiral's seat (5), a pilot's seat (0-4) for that pilot's wing,
## or -1 for the deputy. Set by the maker.
var owner_seat: int = -1

## What kind of record: "squadron" (3 small ships), "ship" (1 large ship) or "wing"
## (one wingman). Set by the maker.
var kind: String = ""

## The hull of every ship in the record (one hull per record). Set by the maker.
var hull_id: String = ""

## The most ships the record can hold: 3 or 1. A wing record is always 1. Set by the
## maker.
var max_members: int = 1

## The unit ids of the ships that are alive, in the order they were added. Set by the
## maker; whoever notices a death removes the dead one.
var member_uids: Array[int] = []

## For a wing: the unit id of the pilot's ship (rewritten at every launch). For a
## squadron or a ship: -1. Set by the maker, then by the squad engine.
var leader_uid: int = -1

## Fire stance: 0 at will, 1 return fire, 2 hold fire. Set by the stance order.
var fire_stance: int = 0

## Move stance: 0 hold, 1 manoeuvre, 2 roam. Set by the stance order.
var move_stance: int = 1

## Formation: 0 wedge, 1 line, 2 column, 3 loose. Set by the formation order.
var formation: int = 0

## The order that stands: {kind, target_kind, target, tick, settings}. `tick` is the
## tick on which the order was applied and `settings` is {} when the order has none.
## An empty Dictionary means idle. It has no `mode` key. Set by the order path.
var order: Dictionary = {}

## The list of orders waiting behind the standing one. Empty until the Shift list
## exists. Set by the order path.
var order_list: Array = []

## The goal a squadron is working towards, as a Dictionary. Empty until goals exist.
var goal: Dictionary = {}

## Where new or regrouping ships go, as a whole-number point in world units. Set by
## the yard and by the set-rally order.
var rally: Vector2i = Vector2i.ZERO

## What the squad is doing: 0 idle, 1 moving, 2 fighting, 3 retreating, 4 docked,
## 5 refitting, 6 launching. Set by the brain that flies it.
var state: int = 0

## Which brain flies it: "standin", "squad" or "wingman". Set by the maker.
var brain: String = ""

## The World tick count on which the record was made. Set by the maker.
var created_tick: int = 0

## For a wing: the id of the wing's lead (first) record, which has its own id here.
## For any other kind: -1. Set by the maker.
var wing_id: int = -1

## For a wing: the formation slot, 0 to 2. It never changes while the wingman lives.
## For any other kind: -1. Set by the maker.
var slot_index: int = -1

## The squad engine's private notes: smoothed heading, straggler, re-form, regroup
## and six-second skip timers (in ticks), and the record of the last order it took
## (kind, target, tick) so it can drop a repeat. Empty for the stand-in brain. It is
## not hashed and uses no dice. Set by the squad engine.
var engine: Dictionary = {}
