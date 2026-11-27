class_name Deputy
extends RefCounted
## WHAT THIS IS: the deputy, a computer Admiral that helps a human Admiral. It exists only in a match
## where a human plays the Admiral's seat: it is made on demand (the DEPUTY order, from the card or the
## top strip) and loaded with one of four presets (AdmiralProfileData: balanced, attack, defend, economy).
## Every order it sends carries the seat "deputy" (OrderKinds.DEPUTY_SEAT), so the build list, the alert
## list and the match log can tell its orders from the human's.
##
## HOW IT WORKS: while the human is there (some input in the last 30 seconds) the deputy builds and
## researches: the drone line, repair bays and wards, the research plan with the preset's own steps first,
## and the yard's buying. It never does what only the human seat may do: it places no waypoint, declares
## no siege, moves no mothership and flies no ship (allows() says no to those steps), and it sends no
## squadron order. After 30 seconds with no input (Absence, in ticks of the match, so a replay repeats
## it) it switches itself on with the Balanced preset if it was off, and also plays the fleet layer
## (goals and orders for the bought squadrons); it still places no waypoint, siege or mothership move. The
## human's first input hands the seat back: the fleet layer goes off and the deputy goes back to the
## preset the human last chose (or off). After 90 seconds with no input it files one "seat_open" event
## for the team (only filed: another player taking the seat is online play, not built). The preset is
## changed only by a DEPUTY order from the human seat. After a mutiny (the team's Admiral is no longer "human": a new
## computer Admiral holds the chair) tick() does nothing, so the deputy never replaces that Admiral. Nothing here draws
## a random number or reads the keyboard or mouse.
##
## WHO USES IT: WorldSetup calls Deputy.install() once the computer Admirals are made; OrderQueue holds the
## object (OrderQueue.deputy), calls tick() once a tick and note_controls() with the human ship's controls;
## AdmiralAI asks allows() before each of its human-seat steps; the Admiral's screens read `preset` and
## `away`; the computer's order makers call computer_seat(); tests/deputy_check.gd checks all of it.

## The game world.
var world: World
## The team of the human Admiral (the deputy's team).
var team := 0
## The preset the deputy runs now: "off" or one of AdmiralProfileData.PRESET_NAMES.
var preset := "off"
## The setting the human last chose with a DEPUTY order ("off" until they choose): what the seat goes back to.
var chosen := "off"
## The preset the human last switched on (Balanced until they choose another): what the card's Deputy cell
## switches on again.
var remembered := "balanced"
## True from the moment the human has been away for 30 seconds until their next input.
var away := false
## True once the "seat_open" event of this absence has been filed.
var sent_open := false
## The stopwatch of the human's input.
var absence: Absence


## Make the deputy of `t`'s human Admiral in world `w`.
func _init(w: World, t: int) -> void:
	world = w
	team = t
	absence = Absence.new(w, t)


## Make the match's deputy when a human plays the Admiral's seat (a no-op in every other match): the object goes
## into the order queue and the DEPUTY order gets its handler. WorldSetup calls this after the computer
## Admirals are made, because the teams' seats are only known then.
static func install(w: World) -> void:
	if w.orders == null or w.human_team < 0 or w.human_team >= w.teams.size():
		return
	if w.teams[w.human_team].admiral != "human":
		return
	var d := Deputy.new(w, w.human_team)
	w.orders.deputy = d
	w.orders.handlers[OrderKinds.DEPUTY] = Callable(d, "apply_order")


## The seat the computer's orders on `team` carry: the deputy's seat on a team with a human Admiral (a computer
## order there can only be the deputy's), else the Admiral's seat.
static func computer_seat(w: World, t: int) -> int:
	if t >= 0 and t < w.teams.size() and w.teams[t].admiral == "human":
		return OrderKinds.DEPUTY_SEAT
	return Rules.ADMIRAL_SEAT


## The word a preset is shown as ("Off", "Balanced", "Attack", ...).
static func word(p_preset: String) -> String:
	return "Off" if p_preset == "off" else p_preset.capitalize()


## Once a tick (OrderQueue.run_due): read the human's input, switch the away state, and file the seat-open event.
func tick() -> void:
	# After a mutiny the team's Admiral is "ai" (a new computer Admiral holds the chair): the deputy has no seat to help and
	# must never replace it, so it does nothing from then on.
	if world.teams[team].admiral != "human":
		return
	absence.read_orders()
	var gone := absence.ticks_away()
	if gone >= Absence.AWAY_TICKS:
		if not away:
			_go_away()
	elif away:
		_come_back()
	if gone >= Absence.OPEN_TICKS:
		if not sent_open:
			sent_open = true
			if world.events_rts != null:
				world.events_rts.push({"kind": "seat_open", "team": team, "data": {"seat": Rules.ADMIRAL_SEAT, "ticks": gone}})
	else:
		sent_open = false


## The human's flying controls of this tick (OrderQueue.record_controls hands them over).
func note_controls(ship: Ship) -> void:
	absence.note_controls(ship.controls)


## May the deputy's Admiral do `step` now? The waypoint, sieges, the mothership move and the ship's field trips are
## the human seat's, never the deputy's; the fleet layer plays only while the human is away; the rest is allowed.
func allows(step: String) -> bool:
	match step:
		"waypoint", "siege", "mover", "field":
			return false
		"fleet":
			return away
	return true


## The handler of the DEPUTY order (the human seat's): `o` carries the setting "preset", one of the four preset
## names or "off". Returns "" or the refusal text. A team whose Admiral is no longer "human" (a mutiny made a new computer
## Admiral the chair) gets the seat refusal and nothing is changed.
func apply_order(o: Dictionary) -> String:
	if world.teams[team].admiral != "human":
		return OrderKinds.TEXT_SEAT
	var word_in := str((o["settings"] as Dictionary).get("preset", ""))
	if word_in != "off" and not AdmiralProfileData.is_preset(word_in):
		return "Unknown preset"
	chosen = word_in
	if word_in != "off":
		remembered = word_in
	_apply(word_in)
	return ""


## Run `p_preset` now: "off" removes the team's computer Admiral, a preset replaces it with a new one built from that
## preset's record (the deputy's own timers are kept). It does nothing once the team's Admiral is no longer "human", so the
## deputy never replaces the Admiral a mutiny made the chair.
func _apply(p_preset: String) -> void:
	if world.teams[team].admiral != "human":
		return
	preset = p_preset
	if p_preset == "off":
		world.admiral_ai[team] = null
		return
	var ai := AdmiralAI.new(world, team, AdmiralProfile.make(p_preset, team))
	ai.deputy = self
	if away:
		ai.set_fleet(true)
	world.admiral_ai[team] = ai


## The human has been away for 30 seconds: switch on with Balanced if off, and play the fleet layer too.
func _go_away() -> void:
	away = true
	if preset == "off":
		_apply("balanced")
	var ai := world.admiral_ai[team] as AdmiralAI
	if ai != null:
		ai.set_fleet(true)


## The human is back: the fleet layer goes off, and the deputy goes back to the human's own setting.
func _come_back() -> void:
	away = false
	if chosen == preset:
		var ai := world.admiral_ai[team] as AdmiralAI
		if ai != null:
			ai.set_fleet(false)
	else:
		_apply(chosen)
