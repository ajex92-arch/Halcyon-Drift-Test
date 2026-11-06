extends Node
## WHAT THIS IS: the exact check for the crew of a bought ship: the profile that
## flies a fleet ship (or a wingman) is not a pilot. It makes crews in a small
## world and checks that a crew gets no money of its own, no share of the ore,
## no passive income, no respawn and no dock (a yard crew's ship), that its death is one "ship_lost"
## event and nothing else, and that killing a crew ship pays the enemy pilot the
## small bounty of the table (12% of the hull's price) and counts nothing else.
##
## HOW IT WORKS: for each case it makes crew records with Crew.make(), puts a
## squad record (Squad) into World.squads, launches the ships beside their own
## mothership with no brain, and calls the game's own code: Economy for the ore,
## the trickle and the kills (World.combat.kill sends the death through the same
## path a real death takes), MatchRules for the respawn, World.try_dock for the
## dock. It reads the pilots' credits and counters before and after.
##   - The record: flags, 0 credits, no gear, the hull, the squad id, a yard seat
##     of 100-199 that wraps, the name, a given seat and name.
##   - Money: earn() and earn_quietly() pay a crew nothing; the ore split and the
##     passive trickle skip it.
##   - Death: no respawn timer, the profile is gone from World.profiles, the squad
##     record forgets the ship, exactly one ship_lost event (squad, wing flag, ship
##     id); the dock refuses a yard crew.
##   - Kill pay, for every hull of the table (Fighter 18, Lance 36, Bomber 42,
##     Logistics 60, Support 66, Flak 132, Ion 150, Destroyer 264, Battlecruiser 456,
##     Scout 0): the last-hitting enemy pilot gets it, no kill, streak or assist is
##     counted, the helpers share a quarter; a turret, a minion or another crew
##     finishing a crew ship pays nobody; a crew's last hit on anything pays nobody.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=crew_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <case> <details>" or "FAIL
## <case> <details>". The last line is "crew_check: N failures (M checks)"; 0
## failures means a crew behaves as written.
##
## WHO USES IT: main.gd loads it for --test=crew_check; it is one of the checks of
## the Feature lane for anything that changes who is paid or what a profile is.

## A payout may differ from the wanted amount by this much (credits).
const EPS := 0.0001
## The kill pay of the table, in credits, for each hull: 12% of its price.
const KILL_PAY := {"scout": 0.0, "fighter": 18.0, "lance": 36.0, "bomber": 42.0, "logistics": 60.0, "support": 66.0, "flak": 132.0, "ion": 150.0, "destroyer": 264.0, "battlecruiser": 456.0}

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True once the cases have run (they all run in the first tick).
var _ran := false
## The next id number for a damage log entry (far above the ids of real units).
var _next_uid := 91000


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF


## Run every case in the first tick, print the result and quit.
func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	_record_cases()
	_money_cases()
	_death_cases()
	_pay_cases()
	print("crew_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers -----------------------------------------------------------------------

## Print one PASS or FAIL line for the check `name` (`ok` = it passed), and count it.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## A new squad record in World.squads: team `team`, kind `kind`, hull `hull`.
func _squad(team: int, kind: String, hull: String) -> Squad:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = kind
	s.hull_id = hull
	s.max_members = 3 if kind == "squadron" else 1
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	return s


## A crew ship of hull `hull` for team `team` in `squad`, launched beside its own
## mothership, still, with no brain. The crew is in World.profiles, "flying", and
## the ship is in the squad record.
func _crew_ship(team: int, hull: String, squad: Squad) -> Ship:
	var p := Crew.make(world, team, hull, squad, squad.member_uids.size())
	world.profiles.append(p)
	var ms := world.mothership(team)
	var s := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
	s.controller = null
	s.velocity = Vector2.ZERO
	p.ship = s
	p.state = "flying"
	squad.member_uids.append(s.uid)
	return s


## A new pilot record of team `team`, in World.profiles, with no ship.
func _pilot(name: String, team: int) -> PilotProfile:
	var p := PilotProfile.new(name, team, 40 + world.profiles.size(), false)
	world.profiles.append(p)
	return p


## The killing blow of pilot `who` (a PilotProfile, pilot or crew), or of a "minion"
## or a "turret" when `who` is a String.
func _blow(who: Variant) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = 1.0
	d.kind = Rules.W_PURE
	if who is PilotProfile:
		var p: PilotProfile = who
		d.source_uid = 91999
		d.source_team = p.team
		d.source_is_pilot = true
		d.source_profile = p
	elif str(who) == "minion":
		d.source_uid = 91998
		d.source_team = 0
		d.source_is_minion = true
	else:
		d.source_uid = 91997
		d.source_team = 0
	return d


## Write into `victim`'s damage log that profile `p` did `dmg` damage just now.
func _hit(victim: Unit, p: PilotProfile, dmg: float) -> void:
	_next_uid += 1
	victim.damage_log[_next_uid] = [dmg, world.time, p]


## Add up the "ship_lost" events of team `team` filed since running index `cursor`.
func _lost_events(team: int, cursor: int) -> Array:
	var out: Array = []
	for e: Dictionary in world.events_rts.read_from(team, cursor):
		if e["kind"] == "ship_lost":
			out.append(e)
	return out


# --- the cases ---------------------------------------------------------------------

## The record Crew.make() builds.
func _record_cases() -> void:
	var squad := _squad(1, "squadron", "fighter")
	var p := Crew.make(world, 1, "fighter", squad, 1)
	_check("record: flagged as a crew, not a human, not an AI pilot", p.is_crew and not p.is_human and not p.is_ai_pilot())
	_check("record: no money and no gear", p.credits == 0.0 and p.free_slots() == Items.SLOTS, "credits %.1f free %d" % [p.credits, p.free_slots()])
	_check("record: hull, squad, team, role", p.hull_id == "fighter" and p.squad_id == squad.id and p.team == 1 and p.role == "mid")
	_check("record: named after the hull and its number", p.callsign == "Fighter 2", p.callsign)
	_check("record: a yard seat of 100-199", p.slot >= 100 and p.slot <= 199, str(p.slot))
	var first := Crew.make(world, 0, "fighter", squad, 0).slot
	var seats_ok := true
	var last := first
	for i in 99:
		var s := Crew.make(world, 0, "fighter", squad, 0).slot
		seats_ok = seats_ok and s >= 100 and s <= 199 and s != last
		last = s
	var again := Crew.make(world, 0, "fighter", squad, 0).slot
	_check("record: the yard seats wrap inside 100-199", seats_ok and again == first, "first %d, 101st %d" % [first, again])
	var given := Crew.make(world, 0, "destroyer", null, 0, 212, "Wing W2")
	_check("record: a given seat and name are kept, no squad is -1", given.slot == 212 and given.callsign == "Wing W2" and given.squad_id == -1)
	var pilot := PilotProfile.new("Pilot", 0, 0, false)
	_check("record: a pilot is still a pilot", not pilot.is_crew and pilot.squad_id == -1 and pilot.is_ai_pilot())


## Earning, the ore split and the trickle.
func _money_cases() -> void:
	var squad := _squad(0, "squadron", "fighter")
	var crew := Crew.make(world, 0, "fighter", squad, 0)
	world.profiles.append(crew)
	var pilot := _pilot("Earner", 0)
	crew.earn(50.0, "kill")
	crew.earn_quietly(50.0)
	_check("money: earn() and earn_quietly() pay a crew nothing", crew.credits == 0.0 and crew.earned == 0.0, "%.1f / %.1f" % [crew.credits, crew.earned])
	# The ore: the pilots' 40% is shared among the living pilots only.
	var living := 0
	for p: PilotProfile in world.profiles:
		if p.team == 0 and p.state != "dead" and not p.is_crew:
			living += 1
	var before := pilot.credits
	var treasury_share := float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE))
	Economy.deliver_ore(world, 0, 1000.0, null)
	var want := 1000.0 * (1.0 - treasury_share) / float(living)
	_check("money: the ore split skips a crew", absf((pilot.credits - before) - want) < EPS and crew.credits == 0.0, "pilot %.3f wanted %.3f, crew %.3f" % [pilot.credits - before, want, crew.credits])
	# The trickle.
	before = pilot.credits
	Economy.passive_income(world, 10.0)
	_check("money: the passive trickle skips a crew", pilot.credits > before and crew.credits == 0.0 and crew.earned == 0.0, "pilot +%.3f, crew %.3f" % [pilot.credits - before, crew.credits])
	world.profiles.erase(crew)


## A crew ship's death and its dock.
func _death_cases() -> void:
	for kind in ["squadron", "wing"]:
		var squad := _squad(1, kind, "fighter")
		var a := _crew_ship(1, "fighter", squad)
		var b := _crew_ship(1, "fighter", squad)
		var pa: PilotProfile = a.profile
		var uid_a := a.uid
		var uid_b := b.uid
		var killer := _pilot("Hunter", 0)
		var kills_before := killer.kills
		var cursor: int = world.events_rts.next_index(1)
		# The dock refuses a crew, next to its own mothership.
		_check("%s: a yard crew ship never docks" % kind, not world.try_dock(a) and a.alive and world.ships.has(a))
		# Kill the first ship through the normal death path.
		world.combat.kill(a, _blow(killer))
		var lost := _lost_events(1, cursor)
		_check("%s: exactly one ship_lost for the death" % kind, lost.size() == 1, str(lost.size()))
		if lost.size() == 1:
			var d: Dictionary = lost[0]["data"]
			_check("%s: the event names the squad, the wing flag and the ship" % kind, int(d["squad"]) == squad.id and int(d["wing"]) == (1 if kind == "wing" else 0) and int(lost[0]["uid"]) == uid_a, str(lost[0]))
		_check("%s: no respawn, the crew is dead and gone from the list" % kind, pa.state == "dead" and pa.ship == null and pa.respawn_t == 0.0 and not world.profiles.has(pa))
		_check("%s: the squad record forgot the ship and kept the other" % kind, not squad.member_uids.has(uid_a) and squad.member_uids.has(uid_b), str(squad.member_uids))
		_check("%s: the killer counts no kill" % kind, killer.kills == kills_before)
		# The second ship is killed by a turret: still one more event, no pay.
		world.combat.kill(b, _blow("turret"))
		_check("%s: the second death files its own ship_lost" % kind, _lost_events(1, cursor).size() == 2)
		_check("%s: an empty squad record stays for the yard to tidy" % kind, world.squads.has(squad.id) and squad.member_uids.is_empty())


## The kill pay, hull by hull, and who is paid.
func _pay_cases() -> void:
	var killer := _pilot("Hunter2", 0)
	var helper := _pilot("Helper", 0)
	for hull: String in Ships.ORDER:
		var squad := _squad(1, "squadron", hull)
		var s := _crew_ship(1, hull, squad)
		var kills := killer.kills
		var team_kills: int = world.teams[0].kills
		var credits := killer.credits
		var streak := killer.streak
		world.combat.kill(s, _blow(killer))
		var got := killer.credits - credits
		var want := float(KILL_PAY[hull])
		var computed: float = float(Ships.HULLS[hull]["price"]) * Rules.KILL_VALUE_SHARE
		_check("pay: %s pays %.0f, 12%% of its price" % [hull, want], absf(got - want) < EPS and absf(computed - want) < EPS, "got %.3f computed %.3f" % [got, computed])
		_check("pay: %s counts no kill and no streak" % hull, killer.kills == kills and killer.streak == streak and world.teams[0].kills == team_kills)
	# Helpers share a quarter of the pay, the killer keeps the rest.
	var squad := _squad(1, "squadron", "destroyer")
	var big := _crew_ship(1, "destroyer", squad)
	_hit(big, killer, 70.0)
	_hit(big, helper, 30.0)
	var k0 := killer.credits
	var h0 := helper.credits
	var assists := helper.assists
	world.combat.kill(big, _blow(killer))
	var pay := 264.0
	_check("pay: the killer keeps three quarters, the helper a quarter", absf((killer.credits - k0) - pay * 0.75) < EPS and absf((helper.credits - h0) - pay * 0.25) < EPS, "killer %.3f helper %.3f" % [killer.credits - k0, helper.credits - h0])
	_check("pay: the helper counts no assist", helper.assists == assists)
	# A turret, a minion or another crew finishing a crew ship pays nobody.
	var other_crew := Crew.make(world, 0, "fighter", null, 0)
	for who: Variant in ["turret", "minion", other_crew]:
		var sq := _squad(1, "squadron", "destroyer")
		var v := _crew_ship(1, "destroyer", sq)
		_hit(v, killer, 100.0)
		var c0 := killer.credits
		world.combat.kill(v, _blow(who))
		var label: String = who if who is String else "another crew"
		_check("pay: a crew ship finished by %s pays nobody" % label, killer.credits == c0 and other_crew.credits == 0.0)
	# A crew's last hit on a pilot's ship or a minion pays nobody (not even the crew).
	var victim_pilot := _pilot("Victim", 1)
	victim_pilot.hull_id = "fighter"
	var vs := world.launch(victim_pilot)
	vs.controller = null
	var crew_killer := Crew.make(world, 0, "fighter", null, 0)
	var c1 := killer.credits
	var m := world.spawner.spawn_minion(1, "fighter", "mid", world.mothership(1).global_position + Vector2(900, 0))
	world.combat.kill(m, _blow(crew_killer))
	world.combat.kill(vs, _blow(crew_killer))
	_check("pay: a crew's last hit on a minion or a pilot's ship pays nobody", crew_killer.credits == 0.0 and killer.credits == c1 and victim_pilot.deaths == 1)
