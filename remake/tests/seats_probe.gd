extends Node
## WHAT THIS IS: the "seats probe", the test for the 6v6 teams of the user
## test fork (docs/USER_FORK_PLAN.md, stage 1). It checks that each side has
## 5 pilot seats and 1 admiral's seat, that the human can sit in either the
## pilot's or the admiral's seat, that a human admiral can launch and dock
## (and be shot down), and that the computer admiral takes the field and
## docks again, with its edge cases (see AdmiralField), and logs every trip.
##
## HOW IT WORKS: setup() first checks the seats the World just built (how many
## pilots, their jobs, the callsigns, who is the human, who has a computer
## admiral). Then _physics_process() runs numbered phases in game time:
##   - a human admiral buys a hull, launches, docks, launches and is shot down
##     (the admiral's chair is empty only while the ship flies);
##   - two pilots of each side are shot down: the computer admiral must take
##     the field ("pilots_down"), keep thinking once a second while it flies,
##     and dock again once the pilots are back and the trip has lasted long
##     enough. On the human admiral's side nothing launches the human's seat,
##     and a human pilot's seat is not touched either;
##   - the defend call is switched on: a second trip ("defend");
##   - a forced trip is made and the admiral's ship shot down: the trip ends
##     "destroyed", the chair is full at once and the thinking goes on;
##   - another forced trip, with money to spend: orders keep going out while
##     the ship is away and the mothership mover does not try to move it; a
##     badly hurt ship goes home, repairs and goes out again (the same trip);
##     a recall is cancelled when the trigger comes back; a hurt ship that is
##     recalled still docks;
##   - a ship that retreats on its way home keeps its retreat when the recall
##     is cancelled (a fifth, forced trip);
##   - the mothership's fall-back: with the engines switched on for the
##     question, each mothership is put 25% up the mid lane at 45% hull. An
##     admiral in the field is recalled at once and, once its seat is back in
##     the chair, the move order home goes out in the very next think; a docked
##     admiral does not launch while that fall-back is due;
##   - the admiral's own ship, shot down together with one pilot, does not
##     count toward the respawn strain; two pilots shot down still strain the
##     mothership;
##   - in the opening, the spot the admiral's ship takes at its lane's anchor is
##     nobody else's (checked while the first trip is out).
## Last it checks that the log of trips (AdmiralField.trips) and the
## Events.admiral_field messages agree, and prints how many FIELD_TRIP lines
## the run must have written (one per trip). The minion waves are stopped so
## nothing else attacks the base.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/; run it three times, one for each seat):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=test --no-jungle --test=seats_probe
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=test --no-jungle --test=seats_probe
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-jungle --test=seats_probe
## --bot=test tells main.gd not to buy and launch the human's ship by itself.
## It takes about 6 minutes of game time (a few minutes of real time).
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>". Then "seats_probe: expects N FIELD_TRIP lines" (the
## runner counts them in the same log) and the last line, "seats_probe: N
## failures"; 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=seats_probe (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()). It
## reads World.profiles, World.admiral_profile, World.admiral_ai and
## AdmiralField, and uses WorldHangar (through World.launch / try_dock).

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Which phase of the test we are in (see HOW IT WORKS).
var _phase := 0
## The game time at which the current phase began waiting.
var _mark := 0.0
## True once the end line has been printed.
var _done := false
## The human admiral's ship while the test flies it.
var _ship: Ship = null
## Per team: the admiral's think count at the first moment it is noted.
var _thinks_a := [0, 0]
## Per team: the admiral's think count at the second moment.
var _thinks_b := [0, 0]
## Per team: the admiral's think count at the third moment.
var _thinks_c := [0, 0]
## Per team: the lane the "pilots_down" trip should cover.
var _exp_lane := ["", ""]
## Per team: the match time the last trip ended.
var _ended_t := [0.0, 0.0]
## Per team: how many starts Events.admiral_field announced.
var _ev_starts := [0, 0]
## Per team: how many ends Events.admiral_field announced.
var _ev_ends := [0, 0]
## Per team: how many admiral orders worked (Events.admiral_result).
var _ok := [0, 0]
## Per team: the _ok count at a marked moment.
var _ok_mark := [0, 0]
## Per team: how many "move" orders were answered at all.
var _move_ev := [0, 0]
## Per team: the _move_ev count at a marked moment.
var _move_mark := [0, 0]
## Per team: how many trips the admiral had when a group of phases began.
var _trips_mark := [0, 0]
## Per team: the match time the admiral's seat came back to the chair in the
## fall-back phases (-1 = not yet).
var _chair_t := [-1.0, -1.0]
## Per team: the match time of the last "move" order that worked (-1 = none).
var _move_t := [-1.0, -1.0]
## Per team: the mothership's hull fraction at that order.
var _move_hull := [-1.0, -1.0]
## Per team: how many respawns of ordinary pilots Events.respawned announced
## since the strain phases began.
var _resp_pilot := [0, 0]
## Per team: how many respawns of the admiral's seat were announced then.
var _resp_admiral := [0, 0]
## Per team: the pilots and the admiral's seat shot down in a strain phase.
var _victims := [[], []]
## The match time the mothership was hurt in the fall-back phases.
var _hurt_at := 0.0
## True from the moment a mothership is hurt until the fall-back phase ends: every
## tick notes when the admiral's seat is back in the chair (_chair_t).
var _watch_chair := false


## main.gd calls this once, right after the World is built. Stop the minion
## waves, listen for the admiral's field trips and orders, and check the seats.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	Events.admiral_field.connect(_on_field)
	Events.admiral_result.connect(_on_result)
	Events.respawned.connect(_on_respawned)
	print("seats_probe: role=%s" % world.human_role)
	_check_seats()


## Print one PASS or FAIL line for the check `name` (`ok` = it passed), with
## the measured `detail`, and count the failures.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## The admiral took the field or came back (Events.admiral_field): count it.
func _on_field(team: int, started: bool, _reason: String) -> void:
	if started:
		_ev_starts[team] += 1
	else:
		_ev_ends[team] += 1


## An admiral order was answered (Events.admiral_result): count the ones that
## worked, and every answer to a "move" order.
func _on_result(team: int, action: String, ok: bool, _message: String) -> void:
	if team < 0 or team > 1:
		return
	if ok:
		_ok[team] += 1
	if action == "move":
		_move_ev[team] += 1
		if ok:
			_move_t[team] = world.time
			_move_hull[team] = world.mothership(team).hull_frac()


## A pilot came back from the dead (Events.respawned): count the pilots and the
## admiral's seats apart (the respawn strain counts only pilots).
func _on_respawned(p: RefCounted) -> void:
	var prof := p as PilotProfile
	if prof == null or prof.team < 0 or prof.team > 1:
		return
	if prof.role == "admiral":
		_resp_admiral[prof.team] += 1
	else:
		_resp_pilot[prof.team] += 1


# --- the seats ---------------------------------------------------------------------------

## Step 1 of the test: the seats the World built. 5 pilots and 1 admiral's
## seat on each side, the right jobs, different callsigns, and the human in
## the seat the --role option asked for.
func _check_seats() -> void:
	var role := world.human_role
	_check("%d profiles in all" % world.profiles.size(), world.profiles.size() == 2 * (Rules.PILOTS_PER_TEAM + 1), "want %d" % (2 * (Rules.PILOTS_PER_TEAM + 1)))
	var names := {}
	for t in 2:
		# The pilots and the admiral's seat of this team.
		var pilots: Array = []
		var admirals: Array = []
		for p: PilotProfile in world.profiles:
			if p.team == t:
				names[p.callsign] = true
				if p.role == "admiral":
					admirals.append(p)
				else:
					pilots.append(p)
		var tn: String = Rules.TEAM_NAMES[t]
		_check("%s has %d pilot seats" % [tn, Rules.PILOTS_PER_TEAM], pilots.size() == Rules.PILOTS_PER_TEAM, "%d" % pilots.size())
		_check("%s has one admiral seat" % tn, admirals.size() == 1, "%d" % admirals.size())
		# The jobs: top 1, mid 2, bottom 1, jungle 1; seats 0-4.
		var jobs := {}
		var slots := {}
		for p: PilotProfile in pilots:
			jobs[p.role] = int(jobs.get(p.role, 0)) + 1
			slots[p.slot] = true
		_check("%s jobs top 1, mid 2, bot 1, jungle 1" % tn, jobs == {"top": 1, "mid": 2, "bot": 1, "jungle": 1}, str(jobs))
		_check("%s pilot seats are 0-4" % tn, slots.size() == Rules.PILOTS_PER_TEAM and slots.keys().min() == 0 and slots.keys().max() == Rules.PILOTS_PER_TEAM - 1, str(slots.keys()))
		if admirals.size() == 1:
			var ap: PilotProfile = admirals[0]
			_check("%s admiral seat is %d" % [tn, Rules.ADMIRAL_SEAT], ap.slot == Rules.ADMIRAL_SEAT and world.admiral_profile[t] == ap, "slot %d" % ap.slot)
		# Every seat has a pilot brain, except the human's.
		var brains := 0
		for p: PilotProfile in world.profiles:
			if p.team == t and world.pilot_ai.has(p):
				brains += 1
		var humans := 0
		for p: PilotProfile in world.profiles:
			if p.team == t and p.is_human:
				humans += 1
		_check("%s: every seat but the human's has a pilot brain" % tn, brains == Rules.PILOTS_PER_TEAM + 1 - humans, "%d brains, %d human" % [brains, humans])
	_check("12 different callsigns", names.size() == world.profiles.size(), str(names.keys()))
	# The human's seat.
	var h := world.human
	match role:
		"pilot":
			_check("pilot seat: the human is Aurelian seat 0", h != null and h.team == Rules.HALCYON and h.slot == 0 and h.role == "top" and h.is_human, "" if h == null else "%s slot %d" % [h.callsign, h.slot])
			_check("pilot seat: Aurelian has a computer admiral", world.admiral_ai[0] != null and not (world.admiral_profile[0] as PilotProfile).is_human, "")
		"admiral":
			_check("admiral seat: the human has the admiral's seat", h != null and h == world.admiral_profile[0] and h.is_human and h.slot == Rules.ADMIRAL_SEAT, "" if h == null else "%s slot %d" % [h.callsign, h.slot])
			_check("admiral seat: no computer admiral for Aurelian", world.admiral_ai[0] == null and world.teams[0].admiral == "human", "")
		_:
			_check("spectator: no human", h == null, "")
			_check("spectator: Aurelian has a computer admiral", world.admiral_ai[0] != null, "")
	_check("Cinder has a computer admiral", world.admiral_ai[1] != null and world.admiral_ai[1].field.profile == world.admiral_profile[1], "")


# --- the phases --------------------------------------------------------------------------

## Godot calls this every tick. Run the phase we are in (see HOW IT WORKS).
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	var now := world.time
	if _watch_chair:
		for t in _ai_teams():
			if _chair_t[t] < 0.0 and world.teams[t].admiral_docked:
				_chair_t[t] = now
	match _phase:
		# Before anything happens: the computer admirals are on the bridge,
		# have not made a trip, and think once a second.
		0:
			if now >= 4.0:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					_check("%s admiral starts on the bridge" % Rules.TEAM_NAMES[t], ai.field.profile.state == "docked" and ai.field.trips.is_empty() and world.teams[t].admiral_docked, ai.field.profile.state)
					_check("%s admiral thinks once a second" % Rules.TEAM_NAMES[t], ai.think_count >= 2 and ai.think_count <= 5, "%d thoughts in 4 s" % ai.think_count)
					_thinks_a[t] = ai.think_count
				_goto(1 if world.human_role == "admiral" else 3, now)
		# A human admiral buys a fighter and launches.
		1:
			if now >= 6.0:
				var h := world.human
				h.credits = 2000.0
				h.buy_hull("fighter", world.teams[0])
				_ship = world.launch(h)
				_check("human admiral launches", _ship != null and h.state == "flying" and h.ship == _ship, h.state)
				_check("the chair is empty while the admiral flies", not world.teams[0].admiral_docked, "")
				_goto(2, now)
		# ...docks (the chair is full again), launches once more and is shot
		# down (the chair is full at once).
		2:
			if now >= _mark + 2.0:
				var h := world.human
				var ok := world.try_dock(_ship)
				_check("human admiral docks", ok and h.state == "docked" and h.ship == null, h.state)
				_check("the chair is full again after docking", world.teams[0].admiral_docked, "")
				_ship = world.launch(h)
				_check("human admiral launches a second time", _ship != null and h.state == "flying", h.state)
				world.combat.kill_silently(_ship)
				_check("a shot-down human admiral is dead and back in the chair", h.state == "dead" and world.teams[0].admiral_docked, h.state)
				_goto(3, now)
		# Two pilots of each side are shot down. The sides with a computer
		# admiral must answer; on a human admiral's side the same trigger
		# exists, but nothing launches the human's seat.
		3:
			if now >= maxf(20.0, _mark + 8.0):
				for t in 2:
					# Team 0 loses seats 1 and 2 (mid, bot), team 1 seats 0
					# and 2 (top, bot): the lane to cover is the lowest seat's.
					var slots: Array = [1, 2] if t == 0 else [0, 2]
					var killed := 0
					for p: PilotProfile in world.profiles:
						if p.team == t and p.slot in slots and p.state == "flying" and p.ship != null and is_instance_valid(p.ship):
							if p.slot == int(slots[0]):
								_exp_lane[t] = p.role
							world.combat.kill_silently(p.ship)
							killed += 1
					var down := 0
					for p: PilotProfile in world.profiles:
						if p.team == t and p.role != "admiral" and p.state == "dead":
							down += 1
					_check("%s: two pilots shot down" % Rules.TEAM_NAMES[t], killed == 2 and down == 2, "%d killed, %d down" % [killed, down])
				_goto(4, now)
		# The admiral takes the field for the "pilots_down" call.
		4:
			if now >= _mark + 5.0:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					var f := ai.field
					var r := str(_trip(f, 1)["reason"])
					_check("%s admiral takes the field for 2 pilots down" % Rules.TEAM_NAMES[t], f.trips.size() == 1 and r == "pilots_down" and f.profile.state == "flying" and f.on_trip, "%d trips, reason %s, %s" % [f.trips.size(), r, f.profile.state])
					_check("%s: the chair is empty while the admiral flies" % Rules.TEAM_NAMES[t], not world.teams[t].admiral_docked, "")
					_check("%s: the admiral covers lane %s" % [Rules.TEAM_NAMES[t], _exp_lane[t]], f.brain.cover_lane == _exp_lane[t], f.brain.cover_lane)
					_check_opening_spot(t, f)
					_check("%s: the mothership cannot move while the admiral flies" % Rules.TEAM_NAMES[t], _move_blocker(t).contains("docked"), _move_blocker(t))
					_thinks_b[t] = ai.think_count
				# The seat of the human is never launched by the computer.
				var hs: PilotProfile = world.admiral_profile[0] if world.human_role == "admiral" else world.human
				if hs != null:
					_check("the human's seat stays docked while 2 pilots are down", hs.state == "docked", hs.state)
				_goto(5, now)
		# It keeps thinking once a second while it flies.
		5:
			if now >= _mark + 10.0:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					var d: int = ai.think_count - int(_thinks_b[t])
					_check("%s admiral still thinks once a second in the field" % Rules.TEAM_NAMES[t], ai.field.profile.state == "flying" and d >= 9 and d <= 11, "%d thoughts in 10 s" % d)
				_goto(6, now)
		# The pilots are back, the trip is long enough: it docks.
		6:
			if _all_trips_over(1) or now >= _mark + 200.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var rec := _trip(f, 1)
					var dur := float(rec["end"]) - float(rec["start"])
					_check("%s admiral docks when the trip is over" % Rules.TEAM_NAMES[t], str(rec["ended"]) == "docked" and f.profile.state == "docked" and world.teams[t].admiral_docked, "ended %s, %s" % [rec["ended"], f.profile.state])
					_check("%s trip lasted at least %d s" % [Rules.TEAM_NAMES[t], int(AdmiralField.MIN_TRIP)], dur >= AdmiralField.MIN_TRIP and dur < 150.0, "%.1f s" % dur)
					_ended_t[t] = float(rec["end"]) if float(rec["end"]) >= 0.0 else now
				_goto(7, now)
		# The defend call goes on: after the cooldown, a second trip.
		7:
			if now >= maxf(_ended_t[0], _ended_t[1]) + AdmiralField.COOLDOWN + 3.0:
				for t in _ai_teams():
					var ms := world.mothership(t)
					var ts := world.teams[t]
					ts.defend_point = ms.global_position + Vector2.from_angle(ms.rotation) * 3000.0
					ts.defend_until = now + 22.0
				_goto(8, now)
		8:
			if now >= _mark + 4.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var r := str(_trip(f, 2)["reason"])
					_check("%s admiral takes the field to defend" % Rules.TEAM_NAMES[t], f.trips.size() == 2 and r == "defend" and f.profile.state == "flying", "%d trips, reason %s, %s" % [f.trips.size(), r, f.profile.state])
					_check("%s: a defend trip covers no lane" % Rules.TEAM_NAMES[t], f.brain.cover_lane == "", f.brain.cover_lane)
				_goto(9, now)
		9:
			if _all_trips_over(2) or now >= _mark + 200.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var rec := _trip(f, 2)
					var dur := float(rec["end"]) - float(rec["start"])
					_check("%s admiral docks after the defend call" % Rules.TEAM_NAMES[t], str(rec["ended"]) == "docked" and f.profile.state == "docked" and world.teams[t].admiral_docked, "ended %s, %s" % [rec["ended"], f.profile.state])
					_check("%s defend trip lasted at least %d s" % [Rules.TEAM_NAMES[t], int(AdmiralField.MIN_TRIP)], dur >= AdmiralField.MIN_TRIP, "%.1f s" % dur)
					_ended_t[t] = float(rec["end"]) if float(rec["end"]) >= 0.0 else now
				_goto(10, now)
		# A forced trip, and the admiral's ship shot down on it.
		10:
			if now >= maxf(_ended_t[0], _ended_t[1]) + AdmiralField.COOLDOWN + 3.0:
				for t in _ai_teams():
					(world.admiral_ai[t] as AdmiralAI).field.force_reason = "forced"
				_goto(11, now)
		11:
			if now >= _mark + 4.0:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					var f := ai.field
					var r := str(_trip(f, 3)["reason"])
					_check("%s admiral takes a forced trip" % Rules.TEAM_NAMES[t], f.trips.size() == 3 and r == "forced" and f.profile.state == "flying", "%d trips, reason %s, %s" % [f.trips.size(), r, f.profile.state])
					_thinks_c[t] = ai.think_count
					if f.profile.ship != null and is_instance_valid(f.profile.ship):
						world.combat.kill_silently(f.profile.ship)
				_goto(12, now)
		# The ship is destroyed: the trip ends, the chair is full at once (the
		# mothership may move again) and the thinking never stopped.
		12:
			if now >= _mark + 2.5:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					var f := ai.field
					f.force_reason = ""
					var ended := str(_trip(f, 3)["ended"])
					_check("%s trip ends 'destroyed' when the ship is shot down" % Rules.TEAM_NAMES[t], ended == "destroyed" and world.teams[t].admiral_docked and not f.on_trip, "ended '%s'" % ended)
					_check("%s: the admiral is in the chair while the ship is dead" % Rules.TEAM_NAMES[t], f.profile.state == "dead" and _move_blocker(t) == "", "%s, '%s'" % [f.profile.state, _move_blocker(t)])
					var d: int = ai.think_count - int(_thinks_c[t])
					_check("%s: the admiral keeps thinking while the ship is dead" % Rules.TEAM_NAMES[t], d >= 2 and d <= 3, "%d thoughts in 2.5 s" % d)
				_goto(13, now)
		# After the respawn: a fourth, forced trip with money to spend. No
		# kits, so a hurt ship must go home to be repaired.
		13:
			if now >= _mark + 12.0:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					var f := ai.field
					_check("%s admiral is back in the hangar after its respawn" % Rules.TEAM_NAMES[t], f.profile.state == "docked" and not f.on_trip, f.profile.state)
					world.teams[t].treasury = 20000.0
					_ok_mark[t] = _ok[t]
					f.force_reason = "forced"
				_goto(14, now)
		# The ship is out on trip 4. Orders keep going out, the mothership
		# mover does not try to move the mothership; then the ship is hurt.
		14:
			if now >= _mark + 4.0:
				for t in _ai_teams():
					var ai := world.admiral_ai[t] as AdmiralAI
					var f := ai.field
					var r := str(_trip(f, 4)["reason"])
					_check("%s admiral takes a fourth trip" % Rules.TEAM_NAMES[t], f.trips.size() == 4 and r == "forced" and f.profile.state == "flying", "%d trips, reason %s, %s" % [f.trips.size(), r, f.profile.state])
					_move_mark[t] = _move_ev[t]
					ai.mothership_mover.maybe_move()
					_check("%s: the mothership mover does not try to move it" % Rules.TEAM_NAMES[t], _move_ev[t] == _move_mark[t], "%d answers" % (_move_ev[t] - _move_mark[t]))
					_hurt(f)
				_goto(15, now)
		# A hurt ship goes home, is repaired, and goes out again: still the
		# same trip.
		15:
			if _all_resupplied() or now >= _mark + 90.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var rec := _trip(f, 4)
					_check("%s: a hurt ship goes home and out again on the same trip" % Rules.TEAM_NAMES[t], int(rec["resupplies"]) >= 1 and f.trips.size() == 4 and f.on_trip, "%d resupplies, %d trips" % [int(rec["resupplies"]), f.trips.size()])
				_goto(16, now)
		# Wait until the trip is old enough to be recalled, then take the
		# trigger away.
		16:
			if _all_older_than(4, AdmiralField.MIN_TRIP + 2.0) and now >= _mark + 2.0:
				for t in _ai_teams():
					(world.admiral_ai[t] as AdmiralAI).field.force_reason = ""
				_goto(17, now)
		# The recall is on; the trigger comes back: the recall is cancelled.
		17:
			if now >= _mark + 1.6:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s: the ship is recalled when the call is over" % Rules.TEAM_NAMES[t], f.brain.recalled and f.on_trip, "recalled %s" % f.brain.recalled)
					f.force_reason = "forced"
				_goto(18, now)
		18:
			if now >= _mark + 1.6:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s: the recall is cancelled when the call comes back" % Rules.TEAM_NAMES[t], not f.brain.recalled and f.on_trip and f.brain.state != "home" and f.trips.size() == 4, "recalled %s, state %s" % [f.brain.recalled, f.brain.state])
					f.force_reason = ""
				_goto(19, now)
		# Recalled again, and now the ship is badly hurt on the way home: it
		# still docks. (The real calls are not under the test's control: a
		# real "pilots_down" or "defend" call that holds keeps the ship out, and
		# then it is right not to recall it.)
		19:
			if now >= _mark + 1.6:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s: recalled again (unless a real call holds)" % Rules.TEAM_NAMES[t], f.brain.recalled or f.trigger(world.teams[t]) != "", "recalled %s, state %s, trigger '%s', %s, on trip %s" % [f.brain.recalled, f.brain.state, f.trigger(world.teams[t]), f.profile.state, f.on_trip])
					_hurt(f)
				_goto(20, now)
		20:
			if _all_trips_over(4) or now >= _mark + 120.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var rec := _trip(f, 4)
					_check("%s: a hurt, recalled ship still docks" % Rules.TEAM_NAMES[t], str(rec["ended"]) == "docked" and f.profile.state == "docked" and world.teams[t].admiral_docked, "ended %s, %s" % [rec["ended"], f.profile.state])
					_check("%s: orders kept going out during the trip" % Rules.TEAM_NAMES[t], _ok[t] - int(_ok_mark[t]) >= 3, "%d orders worked" % (_ok[t] - int(_ok_mark[t])))
					_check("%s: the mothership may move again once docked" % Rules.TEAM_NAMES[t], _move_blocker(t) == "", _move_blocker(t))
				_goto(21, now)
		# After the respawn nothing calls the admiral out any more. Last, the
		# log and the messages must agree.
		21:
			if now >= _mark + 20.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s admiral back on the bridge, no new trip" % Rules.TEAM_NAMES[t], f.trips.size() == 4 and f.profile.state == "docked" and not f.on_trip, "%d trips, %s" % [f.trips.size(), f.profile.state])
					_check("%s: log and messages agree (4 starts, 4 ends)" % Rules.TEAM_NAMES[t], _ev_starts[t] == f.trips.size() and _ev_ends[t] == f.trips.size(), "%d starts, %d ends" % [_ev_starts[t], _ev_ends[t]])
					var sane := true
					for rec: Dictionary in f.trips:
						if float(rec["end"]) <= float(rec["start"]) or str(rec["ended"]) == "":
							sane = false
					_check("%s: every trip has a start, an end and a result" % Rules.TEAM_NAMES[t], sane, "")
				# The sequel: a fifth, forced trip (the retreat), the mothership's
				# fall-back and the respawn strain; the last phase prints the totals.
				for t in _ai_teams():
					(world.admiral_ai[t] as AdmiralAI).field.force_reason = "forced"
				_goto(22, now)
		# A fifth, forced trip. Once it is old enough the trigger goes away (the
		# recall), and then the ship, flying home, is hurt to 30%: it retreats.
		22:
			if now >= _mark + 4.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var r := str(_trip(f, 5)["reason"])
					_check("%s admiral takes a fifth trip" % Rules.TEAM_NAMES[t], f.trips.size() == 5 and r == "forced" and f.profile.state == "flying", "%d trips, reason %s, %s" % [f.trips.size(), r, f.profile.state])
				_goto(23, now)
		23:
			if (_all_older_than(5, AdmiralField.MIN_TRIP + 2.0) and now >= _mark + 2.0) or now >= _mark + 90.0:
				for t in _ai_teams():
					(world.admiral_ai[t] as AdmiralAI).field.force_reason = ""
				_goto(24, now)
		24:
			if now >= _mark + 1.6:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s: the fifth trip is recalled when the call is over (or a real call holds)" % Rules.TEAM_NAMES[t], (f.brain.recalled or f.trigger(world.teams[t]) != "") and f.on_trip, "recalled %s, trigger '%s', %s" % [f.brain.recalled, f.trigger(world.teams[t]), f.profile.state])
					_hurt_to(f, 0.3)
				_goto(25, now)
		# The hurt ship retreats on its way home. The call comes back while it
		# is at half hull: the recall is cancelled, but the retreat goes on
		# until the hull is back to 85%, like every other pilot's.
		25:
			if now >= _mark + 1.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s: a ship hurt to 30%% on its way home retreats" % Rules.TEAM_NAMES[t], f.brain.state == "retreat", "state %s, recalled %s" % [f.brain.state, f.brain.recalled])
					_hurt_to(f, 0.5)
					f.force_reason = "forced"
				_goto(26, now)
		26:
			if now >= _mark + 1.6:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var s := f.profile.ship
					var hull := s.hull_frac() if s != null and is_instance_valid(s) else -1.0
					_check("%s: the recall is cancelled when the call comes back (hurt ship)" % Rules.TEAM_NAMES[t], not f.brain.recalled and f.on_trip, "recalled %s, on trip %s" % [f.brain.recalled, f.on_trip])
					_check("%s: a ship at half hull keeps retreating when the recall is cancelled" % Rules.TEAM_NAMES[t], f.brain.state == "retreat", "state %s, hull %.2f" % [f.brain.state, hull])
					f.force_reason = ""
				_goto(27, now)
		27:
			if _all_idle() or now >= _mark + 120.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var rec := _trip(f, 5)
					_check("%s: the retreating ship docks and the fifth trip ends" % Rules.TEAM_NAMES[t], str(rec["ended"]) == "docked" and f.profile.state == "docked" and not f.on_trip, "ended '%s', %s" % [rec["ended"], f.profile.state])
					_ended_t[t] = float(rec["end"]) if float(rec["end"]) >= 0.0 else now
				_goto(28, now)
		# The mothership's fall-back (the engines are switched on for these
		# phases only). A forced trip is out when each mothership is moved 12%
		# up the mid lane and hurt to 45%: the ship must be recalled at once,
		# and the order home must go out in the think after the seat is back.
		28:
			if now >= maxf(_ended_t[0], _ended_t[1]) + AdmiralField.COOLDOWN + 3.0:
				Game.tunables["mothership_move_unlock"] = 0.0
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_trips_mark[t] = f.trips.size()
					f.force_reason = "forced"
				_goto(29, now)
		29:
			if now >= _mark + 4.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s admiral is out on a forced trip when the mothership is hurt" % Rules.TEAM_NAMES[t], f.trips.size() == _trips_mark[t] + 1 and f.profile.state == "flying", "%d trips (had %d), %s" % [f.trips.size(), _trips_mark[t], f.profile.state])
					_hurt_mothership(t)
				_goto(30, now)
		30:
			if now >= _mark + 2.2:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_check("%s: the ship is recalled at once when the mothership needs its fall-back" % Rules.TEAM_NAMES[t], f.brain.recalled, "recalled %s, trigger '%s', %s" % [f.brain.recalled, f.trigger(world.teams[t]), f.profile.state])
				_goto(31, now)
		31:
			var waiting := false
			var last := 0.0
			for t in _ai_teams():
				if _chair_t[t] < 0.0:
					if world.teams[t].admiral_docked:
						_chair_t[t] = now
					else:
						waiting = true
				last = maxf(last, _chair_t[t])
			if (not waiting and now >= last + 1.2) or now >= _mark + 150.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var ms := world.mothership(t)
					var home: Vector2 = world.map.mothership_pos[t]
					var gap: float = _move_t[t] - _chair_t[t]
					_check("%s: the seat is back in the chair after the recall" % Rules.TEAM_NAMES[t], _chair_t[t] >= 0.0, ("%.1f s after the hurt" % (_chair_t[t] - _hurt_at)) if _chair_t[t] >= 0.0 else "never")
					_check("%s: the fall-back order goes out in the think after the seat is back" % Rules.TEAM_NAMES[t], _chair_t[t] >= 0.0 and _move_t[t] >= _chair_t[t] and gap <= 1.05, "order %s, hull %.2f" % [("%.2f s after the chair" % gap) if _move_t[t] >= 0.0 else "never", _move_hull[t]])
					_check("%s: the order sends the mothership home" % Rules.TEAM_NAMES[t], ms.move_target != Vector2.INF and ms.move_target.distance_to(home) < 100.0, "target %s" % str(ms.move_target))
					print("FALLBACK_PROBE team=%d hull_at_order=%.2f hurt_to_chair=%.1f chair_to_order=%.2f" % [t, _move_hull[t], (_chair_t[t] - _hurt_at) if _chair_t[t] >= 0.0 else -1.0, gap])
					f.force_reason = ""
					_stop_mothership(t)
				_watch_chair = false
				_goto(32, now)
		32:
			if _all_idle() or now >= _mark + 120.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var rec := _trip(f, _trips_mark[t] + 1)
					_ended_t[t] = float(rec["end"]) if float(rec["end"]) >= 0.0 else now
				_goto(33, now)
		# A docked admiral, with the call on and the cooldown over, does not
		# launch while the mothership needs its fall-back; the order goes out.
		33:
			if now >= maxf(_ended_t[0], _ended_t[1]) + AdmiralField.COOLDOWN + 3.0:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					_trips_mark[t] = f.trips.size()
					_hurt_mothership(t)
					f.force_reason = "forced"
				_goto(34, now)
		34:
			if now >= _mark + 2.2:
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					var ms := world.mothership(t)
					var home: Vector2 = world.map.mothership_pos[t]
					_check("%s: the docked admiral does not launch while the mothership needs its fall-back" % Rules.TEAM_NAMES[t], f.trips.size() == _trips_mark[t] and f.profile.state == "docked" and not f.on_trip, "%d trips (had %d), %s" % [f.trips.size(), _trips_mark[t], f.profile.state])
					_check("%s: the fall-back order goes out at the first think" % Rules.TEAM_NAMES[t], _move_t[t] >= 0.0 and ms.move_target != Vector2.INF and ms.move_target.distance_to(home) < 100.0, "order at %.1f, hull %.2f" % [_move_t[t], _move_hull[t]])
					f.force_reason = ""
					_stop_mothership(t)
					ms.global_position = home
					ms.hull = ms.hull_max
				Game.tunables.erase("mothership_move_unlock")
				_watch_chair = false
				_goto(35, now)
		# The respawn strain. First the admiral's own ship and one pilot are
		# shot down: only the pilot's respawn counts. The computer admirals do
		# not take the field in these phases (their trips would add noise).
		35:
			if now >= _mark + 1.0:
				for t in _ai_teams():
					(world.admiral_ai[t] as AdmiralAI).field.enabled = false
				for t in 2:
					_shoot_down(t, true)
				_goto(36, now)
		36:
			if _victims_back() or now >= _mark + 60.0:
				for t in 2:
					var ts := world.teams[t]
					_check("%s: the admiral's own respawn is not counted by the strain" % Rules.TEAM_NAMES[t], ts.respawn_log.size() == _resp_pilot[t] and _resp_admiral[t] == 1, "log %d, pilots back %d, admiral back %d" % [ts.respawn_log.size(), _resp_pilot[t], _resp_admiral[t]])
					_check("%s: the admiral's ship and one pilot shot down do not strain the mothership" % Rules.TEAM_NAMES[t], (ts.strain_t > 0.0) == (_resp_pilot[t] >= 2), "strain %.1f s, pilots back %d" % [ts.strain_t, _resp_pilot[t]])
				_goto(37, now)
		# Then two pilots: that still strains the mothership.
		37:
			if now >= _mark + 1.0:
				for t in 2:
					_shoot_down(t, false)
				_goto(38, now)
		38:
			if _victims_back() or now >= _mark + 60.0:
				for t in 2:
					var ts := world.teams[t]
					_check("%s: two pilots shot down still strain the mothership" % Rules.TEAM_NAMES[t], ts.respawn_log.size() >= 2 and ts.strain_t > 0.0, "log %d, strain %.1f s" % [ts.respawn_log.size(), ts.strain_t])
				_goto(39, now)
		39:
			if now >= _mark + 3.0:
				world.end_field_trips("match_end")
				var lines := 0
				for t in _ai_teams():
					var f := (world.admiral_ai[t] as AdmiralAI).field
					lines += f.trips.size()
					_check("%s: log and messages agree after the extra trips (%d starts, %d ends)" % [Rules.TEAM_NAMES[t], f.trips.size(), f.trips.size()], _ev_starts[t] == f.trips.size() and _ev_ends[t] == f.trips.size(), "%d starts, %d ends" % [_ev_starts[t], _ev_ends[t]])
					var sane := true
					for rec: Dictionary in f.trips:
						if float(rec["end"]) <= float(rec["start"]) or str(rec["ended"]) == "":
							sane = false
					_check("%s: every trip, the extra ones too, has a start, an end and a result" % Rules.TEAM_NAMES[t], sane, "")
				print("seats_probe: expects %d FIELD_TRIP lines" % lines)
				print("seats_probe: %d failures" % fails)
				_done = true
				get_tree().quit()


## Go on to phase `p`, noting the game time `now`.
func _goto(p: int, now: float) -> void:
	_phase = p
	_mark = now


## The teams that have a computer admiral (the human admiral's team has none).
func _ai_teams() -> Array:
	var out: Array = []
	for t in 2:
		if world.admiral_ai[t] != null:
			out.append(t)
	return out


## Why team `t`'s mothership cannot get a move order right now, with the
## engines switched on for this one question (the real unlock is at 20:00);
## "" if it can.
func _move_blocker(t: int) -> String:
	Game.tunables["mothership_move_unlock"] = 0.0
	var b := world.command.move_blocker(t)
	Game.tunables.erase("mothership_move_unlock")
	return b


## Make the admiral's ship of admiral part `f` badly hurt (a fifth of its
## hull), after taking away its repair kits so only a dock can mend it.
func _hurt(f: AdmiralField) -> void:
	_hurt_to(f, 0.2)


## Trip number `n` (1 = the first one) of admiral part `f`, or a "none"
## record (never ended, 0 s long) when it has not made that many.
func _trip(f: AdmiralField, n: int) -> Dictionary:
	if f.trips.size() >= n:
		return f.trips[n - 1]
	return {"reason": "", "ended": "none", "start": 0.0, "end": 0.0, "resupplies": 0}


## Have all computer admirals ended trip number `n` (1 = the first one)?
func _all_trips_over(n: int) -> bool:
	for t in _ai_teams():
		var f := (world.admiral_ai[t] as AdmiralAI).field
		if f.trips.size() < n or str(f.trips[n - 1]["ended"]) == "":
			return false
	return true


## Has the fourth trip of every computer admiral been out for repairs and
## launched again, with the ship flying?
func _all_resupplied() -> bool:
	for t in _ai_teams():
		var f := (world.admiral_ai[t] as AdmiralAI).field
		if int(_trip(f, 4)["resupplies"]) < 1 or f.profile.state != "flying":
			return false
	return true


## Is trip number `n` of every computer admiral at least `secs` old, with the
## ship flying?
func _all_older_than(n: int, secs: float) -> bool:
	for t in _ai_teams():
		var f := (world.admiral_ai[t] as AdmiralAI).field
		if f.trips.size() < n or world.time - float(f.trips[n - 1]["start"]) < secs or f.profile.state != "flying":
			return false
	return true


## Is every computer admiral's field part between trips (no trip running)?
func _all_idle() -> bool:
	for t in _ai_teams():
		if (world.admiral_ai[t] as AdmiralAI).field.on_trip:
			return false
	return true


## Take away admiral part `f`'s repair kits, so only a dock can mend the
## ship, and set its hull to `frac` of the full hull.
func _hurt_to(f: AdmiralField, frac: float) -> void:
	while f.profile.consume_kit():
		pass
	var s := f.profile.ship
	if s != null and is_instance_valid(s):
		s.hull = s.hull_max * frac


## Put team `t`'s mothership 25% up the mid lane (farther than 2,000 from its
## home spot, as after an advance) and hurt it to 45% of its hull, with no move
## order under way, and start the clocks of the fall-back phases.
func _hurt_mothership(t: int) -> void:
	var ms := world.mothership(t)
	ms.global_position = (world.admiral_ai[t] as AdmiralAI).lanes.lane_point("mid", 0.25)
	ms.hull = ms.hull_max * 0.45
	_stop_mothership(t)
	_chair_t[t] = -1.0
	_move_t[t] = -1.0
	_move_hull[t] = -1.0
	_hurt_at = world.time
	_watch_chair = true


## Cancel any move order of team `t`'s mothership.
func _stop_mothership(t: int) -> void:
	var ms := world.mothership(t)
	ms.move_target = Vector2.INF
	ms.move_path = PackedVector2Array()
	ms.move_i = 0


## Shoot down some of team `t`'s ships for a strain phase: the admiral's own
## ship (launched first if the seat is docked) and one pilot, or two pilots.
## The team's respawn log, its strain and the respawn counts start from zero,
## and the victims are noted in _victims[t].
func _shoot_down(t: int, with_admiral: bool) -> void:
	var ts := world.teams[t]
	ts.respawn_log.clear()
	ts.strain_t = 0.0
	_resp_pilot[t] = 0
	_resp_admiral[t] = 0
	var victims: Array = []
	if with_admiral:
		var ap: PilotProfile = world.admiral_profile[t]
		if ap.state == "docked":
			ap.credits = maxf(ap.credits, 3000.0)
			ap.buy_hull("fighter", ts)
			world.launch(ap)
		if ap.state == "flying" and ap.ship != null and is_instance_valid(ap.ship):
			world.combat.kill_silently(ap.ship)
			victims.append(ap)
	var want := 1 if with_admiral else 2
	for p: PilotProfile in world.profiles:
		if want == 0:
			break
		if p.team == t and p.role != "admiral" and not p.is_human and p.state == "flying" and p.ship != null and is_instance_valid(p.ship):
			world.combat.kill_silently(p.ship)
			victims.append(p)
			want -= 1
	_victims[t] = victims


## Have all the ships shot down by _shoot_down() respawned?
func _victims_back() -> bool:
	for t in 2:
		for p: PilotProfile in _victims[t]:
			if p.state == "dead":
				return false
	return true


## While the first trip is out in the opening, the anchor spot the admiral's
## ship takes (PilotGoals.opening_goal) must be nobody else's: it is compared
## with the spot of every other seat of the team that works the same lane.
func _check_opening_spot(t: int, f: AdmiralField) -> void:
	var ship := f.profile.ship
	if ship == null or not is_instance_valid(ship) or f.brain.opening_done:
		_check("%s: the opening is on while the admiral's first trip is out" % Rules.TEAM_NAMES[t], false, "opening done %s" % f.brain.opening_done)
		return
	var lane := f.brain.goals.opening_lane()
	var mine := f.brain.goals.opening_goal(ship)
	var nearest := INF
	var who := "nobody"
	for p: PilotProfile in world.profiles:
		if p.team != t or p == f.profile:
			continue
		var b := world.pilot_ai.get(p) as PilotAI
		if b == null or b.opening_done or b.fallback_t > 0.0 or b.goals.opening_lane() != lane:
			continue
		var d := mine.distance_to(b.goals.opening_goal(ship))
		if d < nearest:
			nearest = d
			who = "seat %d" % p.slot
	_check("%s: the admiral's opening spot at the %s anchor is nobody else's" % [Rules.TEAM_NAMES[t], lane], nearest > PilotGoals.OPENING_SPACING * 0.5, "nearest %s at %.0f" % [who, nearest])
