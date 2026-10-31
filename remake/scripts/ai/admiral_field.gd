class_name AdmiralField
extends RefCounted
## WHAT THIS IS: the part of the computer admiral that takes the field. The
## admiral has a seat of its own (a pilot record, role "admiral", see
## Rules.ADMIRAL_SEAT) and a pilot brain (PilotAI), just like a human
## admiral who launches a ship from the hangar. Most of the match it stays
## on the bridge. It flies a "field trip" in two cases:
##   - "defend": the mothership is under attack (TeamState.defending(), the
##     same alarm that calls every pilot home);
##   - "pilots_down": 2 or more of the team's pilots are dead and waiting to
##     respawn (MIN_DOWN), so the admiral fills in for them on their lane.
## When neither is true any more, it flies home and docks on the bridge.
##
## HOW IT WORKS: AdmiralAI calls update() once a second at the end of its
## think, so the admiral keeps managing the team (money, research, waypoint,
## sieges) while the ship is out. update() looks at the admiral's seat:
##   - docked and a trigger is on (and the last trip ended at least COOLDOWN
##     seconds ago): shop with the seat's own credits (PilotShopping), launch,
##     and open a new trip;
##   - flying, on a trip, the trigger is over and the trip has lasted at
##     least MIN_TRIP seconds: recall the ship (PilotAI.recalled), which then
##     flies to the mothership and docks by itself. If the trigger comes back
##     before it docks, the recall is cancelled;
##   - docked while on a trip: the trip ends ("docked"), unless a trigger is
##     still on (a damaged ship that went home to repair): then it launches
##     again and the same trip goes on (`resupplies` counts these);
##   - dead: the trip ends ("destroyed").
## The mothership's fall-back comes first (chair_needed()): while the
## mothership is under half hull and far from home, only a docked admiral can
## order it back (AdmiralCommand.move_blocker()). Then the admiral does not
## launch, and a ship in the field is recalled at once, whatever the trigger
## and the age of the trip. The order goes out in the think after the seat is
## back in the chair (a docked or destroyed admiral is in it at once).
## Every trip is written to `trips` (start, end, reason, how it ended),
## announced on Events.admiral_field and printed as ONE line when it ends,
##   FIELD_TRIP t=<start s> team=<0|1> reason=<...> dur=<s> result=<...> hull=<id> resupplies=<n>
## where result is "docked", "destroyed" or "match_end" (the match, or the
## test run, ended while the ship was out: World.end_field_trips()). The
## cloud logs can be counted with these lines. The two team news lines
## go to the admiral's own team.
##
## THE EDGE CASES (all tested in tests/seats_probe.gd):
##   - The ship is destroyed: MatchRules.on_pilot_died() puts the admiral back
##     in the chair at once (TeamState.admiral_docked), so every order works
##     again, including moving the mothership. AdmiralAI never stops thinking,
##     so nothing is missed. The trip ends "destroyed" at the next think and
##     COOLDOWN starts. When the seat has respawned (it waits like any pilot)
##     it may launch for a new trip if a trigger is still on.
##   - The trigger ends in the middle of a fight: the recall comes after
##     MIN_TRIP seconds whatever the ship is doing. PilotGoals.think_home()
##     shoots only what is within 900 units on the way and flies on; a hurt
##     ship retreats home the same way (PilotAI keeps `recalled` through a
##     retreat). If the mothership cannot take it (systems failure), the ship
##     waits at the bow, and the trip stays open.
##   - The trigger comes back while the ship is on its way home: the recall is
##     cancelled and the ship goes back to its lane. A ship that is retreating
##     (hurt on the way home) keeps retreating until its hull is back to 85%.
##   - Decisions per minute: the admiral's thinking, spending and orders are
##     the same whether the ship is out or not. Only moving the mothership
##     needs the admiral docked (AdmiralCommand.move_blocker()), exactly as
##     for a human admiral; AdmiralMothershipMover then does not try (and
##     does not use up its 2-minute timer).
##   - A human and the computer never share an admiral seat: the seat is
##     chosen at the start and locked, and a team with a human admiral has no
##     AdmiralAI (so no AdmiralField). A human pilot's seat is never launched
##     by this part.
##
## RANDOM NUMBERS: none of its choices uses a random number. The trigger, the
## lane to cover, and when to launch or recall depend only on the match state
## and clock (World.time). The only random draws near it are the ones the
## game's normal launch makes (World.launch, through the game's one shared
## random sequence, seeded by --seed) and PilotAI's creation at the start of
## the match; no real-world clock is read.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.field) and calls update().
## Tests read `trips` and may set `force_reason` (tests/perf_probe.gd keeps
## the admiral in space for its worst-case runs; tests/seats_probe.gd).
## World.end_field_trips() closes a running trip at the end of a match.
## The option --no-admiral-field switches the trips off.

## This many dead pilots (waiting to respawn) call the admiral out.
const MIN_DOWN := 2
## A trip lasts at least this long (seconds) before the admiral is recalled,
## so that a trigger that flickers does not make it launch and dock again
## and again.
const MIN_TRIP := 20.0
## After a trip ends the admiral waits this long (seconds) before it may
## launch for a new one.
const COOLDOWN := 15.0

## The game world (the admiral's seat, the team's pilots and the clock).
var world: World
## Our team: 0 = Aurelian, 1 = Cinder.
var team := 0
## The admiral's seat (World.admiral_profile[team]); null if there is none,
## and then update() does nothing.
var profile: PilotProfile
## The pilot brain that flies the admiral's ship (World.pilot_ai).
var brain: PilotAI
## False with the option --no-admiral-field: the admiral never takes the
## field.
var enabled := true
## Tests only: a name here (for example "forced") makes the trigger always
## on, with that reason, and lets the admiral launch again at once after a
## trip. "" = the real triggers (see trigger()).
var force_reason := ""
## True while a field trip is running (from the launch until the admiral is
## docked again, dead, or the trip is closed).
var on_trip := false
## The running trip's record (an entry of `trips`); empty between trips.
var trip := {}
## Every trip so far, oldest first. Each entry is a Dictionary: "team",
## "start" (match time in seconds), "end" (match time, -1 while it runs),
## "reason" ("defend", "pilots_down" or the forced name), "ended" ("" while it
## runs, then "docked", "destroyed" or "match_end"), "hull" (the hull id it
## flew), "resupplies" (how many times a damaged ship went home and out
## again) and "reasons" (every reason that held during the trip).
var trips: Array = []
## Match time (seconds) before which the admiral may not launch again.
var cooldown_until := 0.0


## Remember the world and our team, and find the admiral's seat and brain
## (WorldSetup made them just before the admiral). AdmiralAI makes this part
## once.
func _init(w: World, t: int) -> void:
	world = w
	team = t
	profile = w.admiral_profile[t]
	brain = w.pilot_ai.get(profile) if profile != null else null
	enabled = not Game.opt("no-admiral-field", false)


## One look at the admiral's seat (see HOW IT WORKS). AdmiralAI calls it
## once a second, at the end of its think. `ts` is our team's shared state.
func update(ts: TeamState) -> void:
	if not enabled or profile == null or brain == null:
		return
	# Step 1: which trigger is on right now ("" = none), and whether the
	# mothership needs the chair for its fall-back.
	var reason := trigger(ts)
	var now := world.time
	var chair := chair_needed()
	# Step 2: act by what the admiral's seat is doing.
	match profile.state:
		"flying":
			if on_trip:
				_while_flying(reason, now, chair)
		"docked":
			if on_trip:
				# Docked in the middle of a trip. With a trigger still on it
				# was a repair stop: out again (if it cannot launch, the trip
				# is over). Otherwise the trip is over.
				if reason != "" and not chair and _launch():
					trip["resupplies"] = int(trip["resupplies"]) + 1
				else:
					_end("docked")
			elif reason != "" and not chair and (force_reason != "" or now >= cooldown_until):
				var ms := world.mothership(team)
				if ms != null and ms.alive and _launch():
					_begin(reason)
		"dead":
			if on_trip:
				_end("destroyed")


## Which reason the admiral should be in the field for right now: the forced
## name (tests), "defend" (the base is under attack), "pilots_down"
## (MIN_DOWN or more pilots are dead), or "" for none. "defend" comes first.
func trigger(ts: TeamState) -> String:
	if force_reason != "":
		return force_reason
	if ts.defending(world.time):
		return "defend"
	if pilots_down() >= MIN_DOWN:
		return "pilots_down"
	return ""


## Does the mothership need the admiral in the chair right now? True while
## its fall-back is due (AdmiralMothershipMover.fallback_due(): under half
## hull and more than 2,000 from home) and the order needs a docked admiral.
## A weak admiral (test option) never moves the mothership, so it never does.
func chair_needed() -> bool:
	if AdmiralWeak.is_weak(team) or not bool(Rules.tune("mothership_move_needs_dock", true)):
		return false
	return AdmiralMothershipMover.fallback_due(world, team)


## How many of our pilots are dead and waiting to respawn (the admiral's own
## seat does not count).
func pilots_down() -> int:
	var n := 0
	for p: PilotProfile in world.profiles:
		if p.team == team and p.role != "admiral" and p.state == "dead":
			n += 1
	return n


## The lane the admiral covers on a "pilots_down" trip: the lane of the first
## dead pilot (lowest seat number) who holds one; the mid lane if only the
## jungler is down.
func cover_lane() -> String:
	var best: PilotProfile = null
	for p: PilotProfile in world.profiles:
		if p.team == team and p.role != "admiral" and p.state == "dead" and (best == null or p.slot < best.slot):
			best = p
	if best != null and best.role in ["top", "mid", "bot"]:
		return best.role
	return "mid"


## Close the running trip because the match (or the test run) is ending while
## the ship is out: it ends with `result` ("match_end") and its line is
## printed. Does nothing when no trip is running. World.end_field_trips()
## calls it for both teams.
func close_open(result: String) -> void:
	_end(result)


# --- the trip -----------------------------------------------------------------------------

## The admiral's ship is flying on a trip. Recall it at once while the
## mothership needs the chair (`chair`). Otherwise, once the trigger is over
## and the trip has lasted MIN_TRIP, recall it; if a trigger comes back before
## it has docked, cancel the recall.
func _while_flying(reason: String, now: float, chair: bool) -> void:
	if reason != "" and not (trip["reasons"] as Array).has(reason):
		# Keep a list of every reason that held (the trip's "reasons").
		(trip["reasons"] as Array).append(reason)
	if chair:
		if not brain.recalled:
			brain.recalled = true
			brain.home_reason = "recall"
	elif reason == "":
		if not brain.recalled and now - float(trip["start"]) >= MIN_TRIP:
			brain.recalled = true
			brain.home_reason = "recall"
	elif brain.recalled:
		# Back to work: the ship leaves the "home" state it was in. A ship that
		# is retreating (hurt on its way home) keeps its retreat, which ends at
		# 85% hull like every pilot's.
		brain.recalled = false
		brain.home_reason = ""
		if brain.state == "home":
			brain.state = "lane"


## Shop with the seat's own credits and launch the admiral's ship. Returns
## false if it could not launch (no mothership and no repair bay). A
## "pilots_down" trip sets the lane to cover; every other trip holds the mid
## lane (and the defend call sends the ship to the base anyway).
func _launch() -> bool:
	var ts := world.teams[team]
	# Step 1: buy a hull the same way an AI pilot does at the hangar; with
	# the mothership offline, only a free scout.
	var ms := world.mothership(team)
	if ms != null and ms.available():
		brain.shopping.shop()
	if profile.hull_id == "":
		profile.buy_hull("scout", ts)
	# Step 2: launch. A fresh ship starts a fresh plan, on the right lane.
	if world.launch(profile) == null:
		return false
	brain._reset_after_launch()
	brain.cover_lane = cover_lane() if trigger(ts) == "pilots_down" else ""
	return true


## Open a new trip record for a launch that just worked (`reason` is why),
## announce it and tell the team.
func _begin(reason: String) -> void:
	on_trip = true
	trip = {"team": team, "start": world.time, "end": -1.0, "reason": reason, "ended": "",
		"hull": profile.hull_id, "resupplies": 0, "reasons": [reason]}
	trips.append(trip)
	Events.admiral_field.emit(team, true, reason)
	var why := "to defend the mothership" if reason == "defend" else ("to fill in for pilots who are down" if reason == "pilots_down" else "(%s)" % reason)
	Events.feed.emit("The %s admiral takes the field %s." % [Rules.TEAM_DISPLAY[team], why], "team", team)


## Close the running trip: it ended in the way `result` says ("docked",
## "destroyed" or "match_end"). Prints the trip's FIELD_TRIP line. A trip
## that ended by a landing or a loss starts the cooldown for the next launch.
func _end(result: String) -> void:
	if not on_trip:
		return
	on_trip = false
	trip["end"] = world.time
	trip["ended"] = result
	cooldown_until = world.time + COOLDOWN
	Events.admiral_field.emit(team, false, result)
	print("FIELD_TRIP t=%.1f team=%d reason=%s dur=%.1f result=%s hull=%s resupplies=%d" % [float(trip["start"]), team, trip["reason"],
		world.time - float(trip["start"]), result, trip["hull"], int(trip["resupplies"])])
	if result == "docked":
		Events.feed.emit("The %s admiral is back on the bridge." % Rules.TEAM_DISPLAY[team], "team", team)
	elif result == "destroyed":
		Events.feed.emit("The %s admiral's ship was shot down." % Rules.TEAM_DISPLAY[team], "team", team)
	trip = {}
