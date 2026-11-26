class_name PracticeRange
extends RefCounted
## WHAT THIS IS: the practice range's own rules, in one place. A practice
## match is a normal match on the real map that was started from the start
## screen's Practice range button (World.practice is true for the whole match).
## This file holds what only the range does: which seats stay empty, the one
## question that opens every ship class to the human, the default set of target
## drones and the way a destroyed drone comes back.
##
## HOW IT WORKS:
##   - clear_seats() runs while the match is built. The start choice "who else is
##     on the map" (Game.practice_others) says which computer pilots stay:
##     "nobody" (the default) clears the computer pilots of both teams, "allies"
##     clears only the other team's, "both" clears none. A cleared seat has no
##     profile at all, so it is never counted as a pilot who is down. The
##     computer Admirals are made only for "both" (see admirals_wanted()).
##   - locks_open() is the one question the shop asks: may this pilot buy a ship
##     class the team has not researched? It says yes for the human's own pilot
##     record while the match is a practice match, and no for everybody else
##     (computer pilots, the other team, a normal match). Prices are not touched.
##     It borrows UnlockAll's one-question pattern, and neither reads the
##     other's switch.
##   - install() runs when the match is built, at the end of the directors'
##     step: it makes the PracticeRange object (World.practice_range), puts the
##     default set of drones on the map (4 still and 4 moving ones beside each
##     team's lane post, one capital drone in the middle) and hooks the range's
##     tick into the World's tick hooks (the last step of every tick).
##   - tick() runs every tick: it puts back a drone that was destroyed 3 seconds
##     ago (a timer counts ticks), and lets the trials (PracticeTrials) look at
##     the human's ship.
##   - The four switches (PracticeSwitches) are carried out by PracticeActions when a PRACTICE
##     order (PracticeOrders) is applied. This object keeps what they leave: `uses` (each switch's
##     presses and the tick of the first), `money_given` and `no_cooldowns`. While No cooldowns is on,
##     tick() makes the human's timers ready again; on the first tick it sends the toggles the player
##     left on (Game.practice_frozen, Game.practice_no_cd) as orders.
##   - Nothing here draws a random number, and none of it runs while
##     World.practice is false.
##
## WHO USES IT: WorldSetup (clear_seats, admirals_wanted, install);
## PilotProfileShop (locks_open); PracticeDrone (drone_lost); PracticeStatus reads
## the trials through World.practice_range; Game (the choices).

## The values of the start choice "who else is on the map" (Game.practice_others).
const OTHERS := ["nobody", "allies", "both"]
## The default of the start choice.
const OTHERS_DEFAULT := "nobody"

## The world this range belongs to.
var world: World
## The trials of the ship classes (PracticeTrials): what the human is practising now.
var trials: PracticeTrials
## The drones waiting to come back: records {"row": kind, "at": place, "tick": the
## tick they come back on}, in the order they were lost.
var pending: Array[Dictionary] = []
## How many drones the default set made.
var placed := 0
## The switches that worked at least once: switch word -> {"count": how many presses worked,
## "tick": the tick of the first one}. PracticeOrders fills it (note_use).
var uses := {}
## The credits the money switches have added so far (the purse and the treasury together), for
## the panel's "Practice money so far" line. Only the amount that really went on counts.
var money_given := 0.0
## True while No cooldowns is on: tick() makes the human's timers ready again every
## PracticeSwitches.RESET_EVERY_TICKS ticks, so every death waits only the short countdown.
var no_cooldowns := false
## True once the toggles the player left on (Game.practice_frozen, Game.practice_no_cd) have been sent as
## orders; that is done on the range's first tick.
var _sent_remembered := false


## May this pilot record buy a ship class the team has not researched? True only
## for the human's own record while the running match is a practice match.
static func locks_open(profile: PilotProfile) -> bool:
	if profile == null or not profile.is_human:
		return false
	var w := Game.world
	return w != null and is_instance_valid(w) and w.practice


## Take the computer pilots the start choice `others` leaves out of match `w`
## (their profiles and brains), for the practice match being built: "nobody"
## clears both teams, "allies" the team the human does not play for, "both"
## none. Run it after the pilots are made and before the computer Admirals are.
static func clear_seats(w: World, others: String) -> void:
	var cleared: Array[int] = []
	if others == "nobody":
		cleared = [Rules.HALCYON, Rules.CINDER]
	elif others == "allies":
		cleared = [Rules.enemy_of(w.human_team)]
	for p: PilotProfile in w.pilot_ai.keys():
		if cleared.has(p.team):
			w.profiles.erase(p)
			w.pilot_ai.erase(p)


## Are the computer Admirals made in the practice match being built? Only for the
## choice "both"; off by default so the range has no computer commander.
static func admirals_wanted(others: String) -> bool:
	return others == "both"


## Make the range of match `w`: the object, the default drones and the tick
## hook. WorldSetup calls it once, only for a practice match.
static func install(w: World) -> void:
	var pr := PracticeRange.new()
	pr.world = w
	pr.trials = PracticeTrials.new(w)
	w.practice_range = pr
	w.tick_hooks.append(pr.tick)
	# The trials count hits from the damage events, which Combat sends only when asked.
	w.combat.emit_damage_events = true
	pr.place_default_set()


## Put the default set of drones on the map: each team's beside its lane post
## (still ones, then moving ones), and the capital drone in the middle.
func place_default_set() -> void:
	for team in 2:
		var post := MapLayout.lane_post(PracticeDrones.POST_LANE, team)
		var origin: Vector2 = post["pos"]
		var along: Vector2 = post["along"]
		var side: Vector2 = post["side"]
		for kind: String in ["still", "moving"]:
			var plan: Dictionary = PracticeDrones.PLACEMENT[kind]
			for s: float in plan["side"]:
				var want := origin + along * float(plan["along"]) + side * s
				_place(kind, want, along)
	_place("capital", PracticeDrones.CAPITAL_AT, Vector2.RIGHT)


## Make a drone of kind `kind` as near `want` as a clear spot allows: the place
## is moved along `step` (a length-1 arrow) in steps of PracticeDrones.NUDGE
## until no rock is in the way of the drone and its loop.
func _place(kind: String, want: Vector2, step: Vector2) -> void:
	var r := float(PracticeDrones.row(kind)["radius"]) + PracticeDrones.loop_radius(kind) + 20.0
	var at := want
	for i in PracticeDrones.NUDGE_STEPS:
		if not world.asteroids.blocked(at + Vector2(PracticeDrones.loop_radius(kind), 0.0), r):
			break
		at = want + step * PracticeDrones.NUDGE * float(i + 1)
	world.spawn_practice_drone(kind, at)
	placed += 1


## A drone of kind `kind` whose home is `at` was destroyed: put the same kind
## back there after PracticeDrones.REPLACE_TICKS ticks. PracticeDrone calls it.
func drone_lost(kind: String, at: Vector2) -> void:
	pending.append({"row": kind, "at": at, "tick": world.tick_count + PracticeDrones.REPLACE_TICKS})


## Switch `sw` worked on tick `tick_no`: count it, and remember the tick of the first one.
func note_use(sw: String, tick_no: int) -> void:
	if not uses.has(sw):
		uses[sw] = {"count": 0, "tick": tick_no}
	(uses[sw] as Dictionary)["count"] = int((uses[sw] as Dictionary)["count"]) + 1


## One tick (a World tick hook): bring back the drones that are due, then let the
## trials look at the human.
func tick(_dt: float) -> void:
	while not pending.is_empty() and int((pending[0] as Dictionary)["tick"]) <= world.tick_count:
		var rec: Dictionary = pending.pop_front()
		world.spawn_practice_drone(String(rec["row"]), rec["at"])
	if not _sent_remembered:
		_sent_remembered = true
		# The toggles the player left on come back as orders (so the order log holds them), unless
		# a recording is being replayed: its log already has them.
		if not world.orders.replaying:
			if Game.practice_frozen:
				PracticeOrders.send(world, PracticeSwitches.FREEZE, 1)
			if Game.practice_no_cd:
				PracticeOrders.send(world, PracticeSwitches.CD_AUTO, 1)
	if no_cooldowns and world.tick_count % PracticeSwitches.RESET_EVERY_TICKS == 0:
		PracticeActions.reset_cooldowns(world)
	trials.tick()
