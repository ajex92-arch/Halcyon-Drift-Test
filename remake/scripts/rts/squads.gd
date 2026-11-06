class_name Squads
extends RefCounted
## WHAT THIS IS: the keeper of the wings. A wing is a pilot's wingmen (up to three), each one a
## record (Squad) in World.squads and a crew profile (a pilot record flagged is_crew) that
## owns the ship. This file makes the test wings at the start of a match, launches the wingmen
## with their leader, sends them home when the leader is shot down, and gives the rest of the
## game the questions it asks about a wing: which record is the pilot's, which wingmen are
## alive, where the leader is.
##
## HOW IT WORKS: static functions; the wings' state lives in the records (Squad) and in the
## `engine` dictionary of the wing's lead record, never here. make_test_wings() runs once at
## setup, after the pilot seats are made: for every pilot seat that gets a wing it makes one
## record and one crew profile per wingman (the lead record's id is the wing's id). The wingmen
## start docked. on_leader_launch() is called by WorldHangar.launch() for every launch: when a
## pilot with a wing launches, each docked wingman launches too and appears in its formation slot
## around the leader with the leader's heading and speed. on_leader_lost() is called when the
## leader is shot down; the wingmen's brains see the leader's state at their next think and fly
## home. tick() runs once a tick while any wing exists and relaunches a wingman that docked on
## its own once the leader comes back near the mothership.
##
## WHO USES IT: WorldSetup (register, make_test_wings), WorldHangar (on_leader_launch), MatchRules
## (on_leader_lost), SquadOrders (the lookups), WingmanAI (sync, lapse, frame), the HUD
## (lead_record, wing_alive) and the tests.

## The most wingmen a pilot has.
const WING_MAX := 3
## The first crew slot number of the yard's crews (a pilot's seat is below it).
const CREW_SLOT_YARD := 100
## The first crew slot number of a pilot's wing: a wingman's slot is 200 + the pilot's seat x 10
## + its place in the wing (the yard's crews keep 100 to 199).
const CREW_SLOT_BASE := 200
## How often (ticks) tick() looks for a wingman to pick up.
const TICK_EVERY := 15
## The event kinds this file files.
const EVENT_HOME := "wing_home"
## The event kind for a launch.
const EVENT_LAUNCHED := "wing_launched"

# Record states (Squad.state).
## Idle (holding a point).
const STATE_IDLE := 0
## Moving (forming up, travelling).
const STATE_MOVING := 1
## Fighting.
const STATE_FIGHTING := 2
## Going home.
const STATE_HOME := 3
## Docked.
const STATE_DOCKED := 4
## Launching.
const STATE_LAUNCHING := 6


## Hand the squad-order handlers to the world's order queue (WorldSetup calls this once, after
## the queue exists).
static func register(w: World) -> void:
	SquadOrders.register(w)


## The match log header's `wings=` value: the hulls the human's seat gets, "hull,hull,hull", or "off".
static func wings_text() -> String:
	var hulls := Game.wing_hulls_for(true)
	return "off" if hulls.is_empty() else ",".join(hulls)


## The match log header's `cwings=` value: 1 when the computer pilots' seats get wings, else 0.
static func cwings_flag() -> int:
	return 0 if Game.wing_hulls_for(false).is_empty() else 1


## Is `p` a crew profile (a wingman's, or a yard ship's)? Reads the flag by name, and also
## knows a crew by its slot number (a pilot's seat is 0 to 5, a crew's 100 or more).
static func is_crew(p: PilotProfile) -> bool:
	return p != null and (p.get("is_crew") == true or p.slot >= CREW_SLOT_YARD)


## Give the test wings out at the start of a match (WorldSetup calls this once, after the
## "no-pilots" switch has cleared its pilots, so a removed pilot leaves no orphan wing). A pilot
## seat (0 to 4, not the Admiral's) gets the hulls Game.wing_hulls_for() names for it. Nothing
## happens when it names none for anybody: the match is then exactly the game without wings.
static func make_test_wings(w: World) -> void:
	var seats: Array[PilotProfile] = []
	seats.assign(w.profiles)
	for p: PilotProfile in seats:
		if is_crew(p) or p.role == "admiral" or p.slot >= Rules.PILOTS_PER_TEAM:
			continue
		var hulls := Game.wing_hulls_for(p.is_human)
		if hulls.is_empty():
			continue
		make_wing(w, p, hulls)


## Make a wing for pilot `pilot` from the hull ids in `hulls` (at most WING_MAX): one record and one
## docked crew profile per wingman, the first record being the wing's lead. The wing starts with the
## order "follow me", the fire stance "at will", the move stance "manoeuvre" and the wedge. Returns
## the records.
static func make_wing(w: World, pilot: PilotProfile, hulls: PackedStringArray) -> Array[Squad]:
	var out: Array[Squad] = []
	var lead_id := -1
	_ensure_tick(w)
	for i in mini(hulls.size(), WING_MAX):
		var rec := Squad.new()
		rec.id = w.next_uid()
		if lead_id < 0:
			lead_id = rec.id
		rec.team = pilot.team
		rec.owner_seat = pilot.slot
		rec.kind = "wing"
		rec.hull_id = hulls[i]
		rec.max_members = 1
		rec.leader_uid = -1
		rec.fire_stance = 0
		rec.move_stance = 1
		rec.formation = Formations.WEDGE
		rec.order = follow_order(0, w.tick_count)
		rec.state = STATE_LAUNCHING
		rec.brain = "wingman"
		rec.created_tick = w.tick_count
		rec.wing_id = lead_id
		rec.slot_index = i
		rec.engine = {}
		w.squads[rec.id] = rec
		var crew := Crew.make(w, pilot.team, hulls[i], rec, i, CREW_SLOT_BASE + pilot.slot * 10 + i, "%s W%d" % [pilot.callsign, i + 1])
		crew.income_mult = pilot.income_mult
		w.profiles.append(crew)
		Game.count_usage("wings_made")
		out.append(rec)
	return out


## Make sure the world calls tick() every tick, and that the wings' happenings are counted: the first wing
## made adds the hook and joins _count_event to the event stream (a match with no wing never has either).
static func _ensure_tick(w: World) -> void:
	if w.has_meta("squads_tick"):
		return
	w.set_meta("squads_tick", true)
	w.tick_hooks.append(func(_dt: float) -> void: tick(w))
	if not Events.rts_event.is_connected(_count_event):
		Events.rts_event.connect(_count_event)


## Count the wings' happenings in Game.usage, which a test prints with its result: "wings_launched" (wingmen
## launched, from the launch events) and "wings_lost" (wingmen destroyed, from the ship_lost events whose wing
## flag is set); "wings_made" is counted when a wing is made. Nothing the simulation reads.
static func _count_event(ev: Dictionary) -> void:
	var data: Dictionary = ev.get("data", {})
	var kind := str(ev.get("kind", ""))
	if kind == EVENT_LAUNCHED:
		Game.count_usage("wings_launched", int(data.get("count", 0)))
	elif kind == "ship_lost" and int(data.get("wing", 0)) == 1:
		Game.count_usage("wings_lost")

## The order record of "follow me": ESCORT, target the leader's ship uid `leader_uid` (0 before the
## first launch), role follow, applied on tick `tick`.
static func follow_order(leader_uid: int, tick: int) -> Dictionary:
	return {"kind": OrderKinds.ESCORT, "target_kind": "unit", "target": leader_uid, "tick": tick, "settings": {"role": "follow"}}


## The lead record of the wing of the pilot in seat `seat` of team `team`, or null (the pilot has no
## wing).
static func lead_record(w: World, team: int, seat: int) -> Squad:
	for rec: Squad in w.squads.values():
		if rec.kind == "wing" and rec.id == rec.wing_id and rec.team == team and rec.owner_seat == seat:
			return rec
	return null


## Every record of wing `wing_id`, in stored order (the lead first).
static func wing_records(w: World, wing_id: int) -> Array[Squad]:
	var out: Array[Squad] = []
	for rec: Squad in w.squads.values():
		if rec.kind == "wing" and rec.wing_id == wing_id:
			out.append(rec)
	return out


## The seat (0 to 4) of the pilot whose wingman has crew slot number `crew_slot` (200 + seat x 10 + place).
@warning_ignore("integer_division")
static func crew_seat(crew_slot: int) -> int:
	return (crew_slot - CREW_SLOT_BASE) / 10


## The record a wingman's profile belongs to, or null (read from the profile's slot number: 200 +
## the pilot's seat x 10 + the wingman's place in the wing).
static func record_of(w: World, crew: PilotProfile) -> Squad:
	if crew == null or crew.slot < CREW_SLOT_BASE:
		return null
	var lead := lead_record(w, crew.team, crew_seat(crew.slot))
	if lead == null:
		return null
	for rec: Squad in wing_records(w, lead.wing_id):
		if rec.slot_index == (crew.slot - CREW_SLOT_BASE) % 10:
			return rec
	return null


## The crew profile of record `rec` while it still exists (a destroyed wingman's is erased), or null.
static func crew_of(w: World, rec: Squad) -> PilotProfile:
	var want := CREW_SLOT_BASE + rec.owner_seat * 10 + rec.slot_index
	for p: PilotProfile in w.profiles:
		if p.slot == want and p.team == rec.team and is_crew(p):
			return p
	return null


## Does wing `wing_id` still have a wingman, docked or flying?
static func wing_alive(w: World, wing_id: int) -> bool:
	for rec: Squad in wing_records(w, wing_id):
		if crew_of(w, rec) != null:
			return true
	return false


## The pilot (not a crew profile) who leads the wing of record `rec`, or null.
static func leader_profile(w: World, rec: Squad) -> PilotProfile:
	for p: PilotProfile in w.profiles:
		if p.team == rec.team and p.slot == rec.owner_seat and not is_crew(p):
			return p
	return null


## The leader's ship while it flies, or null (docked, dead or not launched yet).
static func leader_ship(w: World, rec: Squad) -> Ship:
	var u: Variant = w.by_uid.get(rec.leader_uid)
	if u == null or not is_instance_valid(u) or not (u as Unit).alive or not (u is Ship):
		return null
	return u as Ship


## The wing's lead record's engine notes and the smoothed frame heading, brought up to the
## current tick (once per tick, whichever wingman asks first). `leader` is the leader's ship.
static func frame_heading(w: World, lead: Squad, leader: Ship) -> float:
	return SquadEngine.frame_heading(lead.engine, w.tick_count, leader.velocity, leader.rotation)


## Write the current facts of wingman `rec` (whose ship may be null) into its record: the live ship
## uid in `member_uids` (none when docked or dead) and the state 4 when docked.
static func sync(w: World, rec: Squad, crew: PilotProfile) -> void:
	var s: Variant = crew.ship if crew != null else null
	var flying: bool = s != null and is_instance_valid(s) and (s as Ship).alive and crew.state == "flying"
	rec.member_uids.clear()
	if flying:
		rec.member_uids.append((s as Ship).uid)
	elif crew != null and crew.state == "docked":
		rec.state = STATE_DOCKED


## The standing order of the whole wing goes back to "follow me": ATTACK's target died, the ward is
## gone, the regroup is over. Written into every record of the wing without an event. (The
## strip watches the records and says "forming on you".)
static func lapse_to_follow(w: World, lead: Squad) -> void:
	for rec: Squad in wing_records(w, lead.wing_id):
		rec.order = follow_order(rec.leader_uid, w.tick_count)
		rec.move_stance = 1


## Called by MatchRules when a pilot's ship was shot down. The wingmen of that pilot see the
## leader's state at their next think and fly home; this files the "wing heading home" event once.
static func on_leader_lost(w: World, p: PilotProfile) -> void:
	if is_crew(p):
		return
	var lead := lead_record(w, p.team, p.slot)
	if lead == null:
		return
	note_home(w, lead)


## File the "wing heading home" event once for the wing of `lead`, until it launches again. A wing
## with no wingman left files none.
static func note_home(w: World, lead: Squad) -> void:
	if bool(lead.engine.get("home_noted", false)) or not wing_alive(w, lead.wing_id):
		return
	lead.engine["home_noted"] = true
	for rec: Squad in wing_records(w, lead.wing_id):
		if rec.state != STATE_DOCKED:
			rec.state = STATE_HOME
	if w.events_rts != null:
		w.events_rts.push({"kind": EVENT_HOME, "team": lead.team, "uid": lead.leader_uid, "data": {"squad": lead.wing_id}})


## Called by WorldHangar.launch() after every launch, pilot `p` having flown ship `ship`. When `p`
## leads a wing, every docked wingman launches and is put into its slot around the leader (with the
## leader's heading and velocity) with a new brain; a wingman that is still flying keeps flying and
## only learns the new leader. A crew profile's own launch returns at once.
static func on_leader_launch(w: World, p: PilotProfile, ship: Ship) -> void:
	if is_crew(p):
		return
	var lead := lead_record(w, p.team, p.slot)
	if lead == null:
		return
	# Step 1: the wing learns the new leader, the frame starts along the leader's nose.
	var recs := wing_records(w, lead.wing_id)
	for rec: Squad in recs:
		rec.leader_uid = ship.uid
		if rec.order.get("kind") == OrderKinds.ESCORT and (rec.order.get("settings", {}) as Dictionary).get("role", "follow") == "follow":
			rec.order["target"] = ship.uid
	lead.engine["hs"] = ship.rotation
	lead.engine["hs_tick"] = w.tick_count
	lead.engine["home_noted"] = false
	# Step 2: every docked wingman launches into its slot.
	var launched := 0
	for rec: Squad in recs:
		var crew := crew_of(w, rec)
		if crew == null:
			continue
		if crew.state == "docked" and launch_wingman(w, lead, rec, crew, ship):
			launched += 1
	if launched > 0 and w.events_rts != null:
		w.events_rts.push({"kind": EVENT_LAUNCHED, "team": lead.team, "uid": ship.uid, "data": {"squad": lead.wing_id, "count": launched}})


## Launch docked wingman `crew` (record `rec`) beside the leader's ship `leader`: it appears in its
## formation slot with the leader's heading and velocity (`into_slot`; a pick-up keeps the mothership's
## launch point), with a fresh brain. Returns true when it launched.
static func launch_wingman(w: World, lead: Squad, rec: Squad, crew: PilotProfile, leader: Ship, into_slot: bool = true) -> bool:
	var s := w.launch(crew)
	if s == null:
		return false
	if into_slot:
		var size := SquadEngine.spacing(leader.radius)
		var h := leader.rotation
		s.global_position = SquadEngine.slot_target(leader.global_position, leader.velocity, h, lead.formation, rec.slot_index, size)
		s.rotation = h
		s.velocity = leader.velocity
	var brain := WingmanAI.new(w, crew)
	s.controller = brain
	brain.start(s)
	sync(w, rec, crew)
	rec.state = STATE_MOVING
	return true


## Give place `rec` of a wing a new wingman (its crew was lost) and launch it beside the leader's ship
## `leader` in its slot. This is what a shop will do later; for now the performance probe uses it to keep
## the wings full. Returns true when the new wingman launched.
static func replace_wingman(w: World, rec: Squad, leader: Ship) -> bool:
	var lead: Squad = w.squads.get(rec.wing_id)
	if lead == null or crew_of(w, rec) != null:
		return false
	var pilot := leader_profile(w, rec)
	var crew := Crew.make(w, rec.team, rec.hull_id, rec, rec.slot_index, CREW_SLOT_BASE + rec.owner_seat * 10 + rec.slot_index,
		"%s W%d" % [pilot.callsign if pilot != null else "Wing", rec.slot_index + 1])
	if pilot != null:
		crew.income_mult = pilot.income_mult
	w.profiles.append(crew)
	rec.member_uids.clear()
	return launch_wingman(w, lead, rec, crew, leader)


## Once every TICK_EVERY ticks: a wingman that docked on its own (a straggler) launches again when its
## leader flies within PICKUP_DIST of our mothership's centre.
static func tick(w: World) -> void:
	if w.tick_count % TICK_EVERY != 0:
		return
	for rec: Squad in w.squads.values():
		if rec.kind != "wing" or rec.id != rec.wing_id:
			continue
		var leader := leader_ship(w, rec)
		var ms := w.mothership(rec.team)
		if leader == null or ms == null or not SquadEngine.pickup_ready(leader.global_position, ms.global_position):
			continue
		for sib: Squad in wing_records(w, rec.wing_id):
			var crew := crew_of(w, sib)
			if crew != null and crew.state == "docked" and launch_wingman(w, rec, sib, crew, leader, false):
				w.events_rts.push({"kind": EVENT_LAUNCHED, "team": rec.team, "uid": leader.uid, "data": {"squad": rec.wing_id, "count": 1}})
