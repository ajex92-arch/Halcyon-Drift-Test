extends Node
## WHAT THIS IS: the fair-play audit of the computer's decisions. Every AI in the match (the pilots, the wingmen, the
## minions, the turrets and every gun that picks its own target) chooses a target, and a fair AI only chooses a unit that
## its own team can see (Unit.visible_to). This check watches every such choice for a whole match and counts the ones
## that used a unit the team could not see. A "decision" here means a target (what a pilot, a wing, a minion, a turret
## or a gun is shooting at, or what a pilot has locked); it is a test of targets only.
##
## HOW IT WORKS: setup() checks that the match is the one this audit is made for (fog on, no human seat, no test
## switch that lets the team view see everything) and reads the options. After every World tick _physics_process()
## looks at the target of every owner (the owners are the pilots found through World.ships, the wingmen, the minions,
## the turrets and every weapon mount), keeps the unit each owner held last tick, and when an owner holds a new unit
## that is a DECISION EVENT: it counts the event, whether the unit is an enemy of the owner, and whether the owner's
## team could not see it at that moment (hidden_at_pick, a VIOLATION: the first three of each kind are printed).
## While an owner goes on holding the same hidden enemy it counts stay_ticks (a HOLD, printed as information only: a
## target that drops out of sight after it was chosen is another question). A target is also recorded under a kind
## that says what it is: a pilot target that is a turret, a post or a mothership is PUSH, one that is a jungle camp is
## CAMP, a minion target that is a mothership is MINION_MS; every other event keeps the kind of its owner (PILOT,
## PILOT_LOCK, WING, MINION, TURRET, MOUNT). A check that sees nothing proves nothing, so the audit also fails when
## it never saw a hidden enemy, or never saw a decision of a kind it must see.
##
## THE HIDE CASES: the recorder only sees what happens to happen, so at frame 3900 (65 game seconds, after the first minion
## wave has left) the check also builds cases on purpose, for each team: it puts an enemy ship where one picker looks, asks
## the picker with the ship SEEN (it must take it: else the case has no teeth), clears the picker's memory, hides the ship from
## the team (its sight bit) and asks again (it must not take it). The pickers asked are the pilots', the wings', the minions'
## (a ship, and the enemy mothership), the turrets' and the guns', and a made team view must not learn where an unseen ship
## went. Every position, sight bit and target field a case writes is put back, also on a failed case.
##
## THE KNOWN LIST: some violations are known and written down in KNOWN (they need changes to how the AI plays). In the
## default form such a violation prints a KNOWN line and does not fail, a violation of any other kind fails, and a KNOWN
## entry that its hide case and its recorder both show clean fails as stale (remove it). The strict form fails every
## violation, known or not: it is the audit, and it is red until the list is empty. The Admiral's own team view switch is
## read too: off in the standard profile, so the computer Admiral reads the live world (KNOWN ADM_LIVE).
##
## THE CANDIDATE PRINT: at the end the check scans a list of AI files for lines that read a world unit list or a spatial
## hash with no sight check near them and prints each as "fair_play: candidate <file>:<line>" (never a failure): the
## places a reader looks at to find decisions the recorder did not catch.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/; the options are
## read with Game.opt, so no other file changes):
##   the default form (about 7 minutes of wall time with --sim-only):
##     godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --seed=7 --secs=420 --sim-only --test=fair_play_check --fair-secs=300
##   the strict form (every violation fails, the audit): add --fair-strict=1
##   the team view form (the computer Admiral's team view switched on): add --admiral-set=both:team_view=1
##   a short smoke run: --secs=150 --fair-secs=90
## --fair-secs=N is how many game seconds are watched (default 300).
##
## HOW TO READ THE OUTPUT: the first line is "fair_play: setup" with the window, the form and whether fog is off. Then
## at the end one line per kind, "fair_play: <KIND> events <n> enemy <n> hidden_at_pick <n> stay_ticks <n>": events is
## how many times an owner took a new target, enemy how many of them were enemy units, hidden_at_pick how many of those
## the owner's team could not see (the violations), stay_ticks how many ticks an owner went on holding a hidden enemy.
## "fair_play_check: <n> failures" is the last line; a FAIL line says why.
##
## WHO USES IT: main.gd loads it for --test=fair_play_check (it calls setup()).

## The kinds of decision, as the result lines print them (see the kind mapping in the header).
const KINDS := ["PILOT", "PILOT_LOCK", "WING", "MINION", "MINION_MS", "TURRET", "MOUNT", "PUSH", "CAMP"]
## The kinds that MUST show at least one decision of an enemy (else the audit saw nothing of them).
const MUST_SEE := ["PILOT", "MINION", "TURRET", "MOUNT"]
## How many violations of each kind are printed in full.
const PRINT_FIRST := 3
## The frame of the hide cases: 65 game seconds, after the first minion wave (45 s) has left its base.
const HIDE_FRAME := 3900
## The shortest window (in game seconds) that holds the hide cases.
const MIN_SECS := 70
## A hide case's answer: the picker skipped the hidden unit.
const C_CLEAN := 0
## A hide case's answer: the picker took the hidden unit (a violation).
const C_TAKES := 1
## A hide case's answer: the picker did not take the unit even when it was seen (the case has no teeth).
const C_NOTEETH := 2
## A hide case's answer: no pair could be set up.
const C_NOSETUP := 3
## The label of the pilot hide case (the probe names it).
const L_PILOT := "hide PILOT: pick_target skips a hidden enemy ship"
## The label of the wing hide case.
const L_WING := "hide WING: WingTargets.around skips a hidden enemy ship"
## The label of the minion hide case.
const L_MINION := "hide MINION: pick_target skips a hidden enemy ship"
## The label of the minion-and-mothership hide case.
const L_MINION_MS := "hide MINION_MS: pick_target skips a hidden enemy mothership"
## The label of the turret hide case.
const L_TURRET := "hide TURRET: _pick_target skips a hidden enemy ship"
## The label of the gun mount hide case.
const L_MOUNT := "hide MOUNT: pick_target skips a hidden enemy ship"
## The label of the team view hide case.
const L_TEAMVIEW := "hide TEAMVIEW: an unseen ship's new place is not known"
## How many candidate owners of each hide case are tried at most.
const MAX_X := 12
## How many enemy ships are tried at most as the hidden unit.
const MAX_Y := 3
## The violations written down at the time of writing: kind -> [the reason, where it is]. In the default form a violation of
## one of these kinds prints a KNOWN line and does not fail; a violation of any other kind fails; the strict form fails them
## all. Nobody adds a kind here to make a failure go away: the day the code is fixed the entry is removed (a kind that has
## both a hide case and a recorder kind, and shows nothing in either, fails as stale).
const KNOWN := {
	"MINION_MS": ["a minion takes the enemy mothership in reach without a look at sight", "scripts/entities/minion_targeting.gd, pick_target, step 4, lines 100-106"],
	"PUSH": ["a pilot pushes a turret, a post or the mothership without a look at sight", "scripts/ai/pilot_targeting.gd, push_target, lines 291-347; scripts/ai/pilot_goals.gd, lines 392-406"],
	"CAMP": ["a jungler takes a camp without a look at sight", "scripts/ai/pilot_goals.gd, lines 633-657; scripts/features/tfj_kit.gd, lines 90-91"],
	"ADM_LIVE": ["team view off, the Admiral reads the live world", "scripts/ai/admiral_profile_data.gd, line 130"],
}
## The kinds with both a hide case and a recorder kind (a KNOWN entry of one of them can be stale).
const STALE_CHECKED := ["TURRET", "MOUNT", "MINION_MS"]
## The files the candidate print reads (the first fifteen are the floor, the rest were found by a search for the files that
## read a world unit list or a spatial hash or set a target).
const CANDIDATE_FILES := [
	"pilot_senses.gd", "pilot_targeting.gd", "pilot_goals.gd", "team_view.gd", "wing_targets.gd", "wingman_ai.gd",
	"minion_targeting.gd", "turret.gd", "weapon_mount_targeting.gd", "admiral_assets_ai.gd", "beacons.gd",
	"comeback_bounties.gd", "epic_neutral.gd", "tfj_kit.gd", "standin.gd",
	"pilot_ai.gd", "pilot_combat.gd", "pilot_flight.gd", "pilot_run.gd", "pilot_shopping.gd", "admiral_assets.gd",
	"admiral_orders.gd", "admiral_smart.gd", "attrition.gd", "bay_shop.gd", "bomber_role_targeting.gd", "breach_extra.gd",
	"buyback.gd", "comeback_director.gd", "doctrine.gd", "escort_pd.gd", "fortify.gd", "group_late.gd", "home_vision.gd",
	"jungle_big.gd", "jungle_scale.gd", "lance_role.gd", "lanespawn.gd", "last_stand.gd", "minion_buffs.gd", "morale.gd",
	"ms_cap.gd", "ms_soft.gd", "ms_spend_weak.gd", "mutiny.gd", "node_persist.gd", "pilot_mining.gd", "recall.gd",
	"redeploy.gd", "respawn_site.gd", "routing_payoff.gd", "siege_fix.gd", "supply_drone.gd", "surrender.gd",
	"alert_rules.gd", "arrivals.gd", "order.gd", "order_apply.gd", "order_checks.gd", "production.gd", "rts_events.gd",
	"squad_orders.gd", "squads.gd",
]
## The folders of the candidate files, tried in this order for each name.
const CANDIDATE_DIRS := ["scripts/ai", "scripts/entities", "scripts/features", "scripts/rts"]
## What counts as reading a world unit list or a spatial hash (a regular expression).
const CANDIDATE_READS := "\\b(world|w)\\.(ships|minions|turrets|posts|units|wards)\\b|unit_hash|ship_hash|\\.mothership\\("
## How many lines ahead of a read a sight check (visible_to) counts as guarding it.
const CANDIDATE_LOOK := 8
## At most this many candidate lines are printed.
const MAX_CANDIDATES := 150

## How many frames are watched (set by setup(): --fair-secs times 60).
var OBSERVE_FRAMES := 18000
## True in the strict form (--fair-strict): every violation fails.
var STRICT := false
## The running match (set by setup()).
var world: World
## How many checks failed.
var _fails := 0
## Frames seen so far.
var _frames := 0
## True once the result has been printed.
var _done := false
## The unit each owner held last tick: kind -> {owner instance id -> unit instance id (0 for none)}.
var _last := {}
## The counts of each kind: kind -> {"events", "enemy", "hidden", "stay"}.
var _count := {}
## How many violations of each kind have been printed.
var _printed := {}
## True once a unit hidden from team t has been seen in a sampled tick: team -> bool.
var _hidden_seen := [false, false]
## How many hide cases of each kind took the hidden unit (kind -> count).
var _hide_taken := {}
## How many hide cases of each kind skipped the hidden unit (kind -> count).
var _hide_clean := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	for k: String in KINDS:
		_last[k] = {}
		_count[k] = {"events": 0, "enemy": 0, "hidden": 0, "stay": 0}
		_printed[k] = 0
	OBSERVE_FRAMES = int(Game.opt("fair-secs", 300)) * 60
	var strict_opt = Game.opt("fair-strict", false)
	STRICT = strict_opt != null and str(strict_opt) != "false" and str(strict_opt) != "0"
	_check("setup: fog is on (Game.fog_off is false)", not Game.fog_off)
	var all_text := str(Game.opt("team-view-sees-all", "false"))
	_check("setup: --team-view-sees-all is not given", all_text == "false" or all_text == "0")
	_check("setup: no human seat (a computer-only match)", world.human == null)
	_check("fair-secs must be %d or more for the hide cases" % MIN_SECS, OBSERVE_FRAMES >= MIN_SECS * 60)
	print("fair_play: setup observe_frames=%d strict=%s fog_off=%s" % [OBSERVE_FRAMES, str(STRICT), str(Game.fog_off)])


## Count the frames; sample after each World tick (not in the frame of the hide cases); at the end print the result and quit.
func _physics_process(_delta: float) -> void:
	if world == null or _done:
		return
	_frames += 1
	if _frames == HIDE_FRAME and OBSERVE_FRAMES >= MIN_SECS * 60:
		_hide_cases()
	else:
		_sample()
	if _frames >= OBSERVE_FRAMES:
		_done = true
		_finish()
		print("fair_play_check: %d failures" % _fails)
		get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fail(what + (("  (" + detail + ")") if detail != "" else ""))


## Count a failure and print its line.
func _fail(what: String) -> void:
	_fails += 1
	print("FAIL fair_play: ", what)


# --- the recorder --------------------------------------------------------------------------------------------------

## Look at the target of every owner in the match, once, after a tick.
func _sample() -> void:
	_note_hidden_enemies()
	for o: Variant in world.ships:
		if not is_instance_valid(o):
			continue
		var s: Ship = o
		if not s.alive:
			continue
		var ctl: Variant = s.controller
		if ctl is WingmanAI:
			_see("WING", s.get_instance_id(), s.team, str(s.name), (ctl as WingmanAI).target)
		elif ctl is PilotAI:
			_see("PILOT", s.get_instance_id(), s.team, str(s.name), (ctl as PilotAI).target)
			_see("PILOT_LOCK", s.get_instance_id(), s.team, str(s.name), (ctl as PilotAI).lock_target)
		_see_mounts(s)
	for o: Variant in world.minions:
		if not is_instance_valid(o):
			continue
		var m: Minion = o
		if not m.alive:
			continue
		_see("MINION", m.get_instance_id(), m.team, str(m.name), m.target)
		_see_mounts(m)
	for o: Variant in world.turrets:
		if not is_instance_valid(o):
			continue
		var tu: Turret = o
		if not tu.alive:
			continue
		_see("TURRET", tu.get_instance_id(), tu.team, str(tu.name), tu.target)
		_see_mounts(tu)


## Note, for each team, that an enemy unit hidden from it was there in this tick (the vacuity guard).
func _note_hidden_enemies() -> void:
	for t in 2:
		if _hidden_seen[t]:
			continue
		for o: Variant in world.units:
			if not is_instance_valid(o):
				continue
			var u: Unit = o
			if u.alive and u.team == Rules.enemy_of(t) and not u.visible_to(t):
				_hidden_seen[t] = true
				break


## Record the target of every weapon mount of unit `u`.
func _see_mounts(u: Unit) -> void:
	var mounts: Array = u.get("mounts")
	for mo: WeaponMount in mounts:
		_see("MOUNT", mo.get_instance_id(), u.team, "%s/%s" % [str(u.name), mo.id], mo.target)


## The kind a decision is counted under: the owner's kind, unless the unit it took says what it is (see the header).
func _mapped(kind: String, u: Unit) -> String:
	if kind == "PILOT" or kind == "PILOT_LOCK":
		if u.kind == Unit.K_TURRET or u.kind == Unit.K_POST or u.kind == Unit.K_MOTHERSHIP:
			return "PUSH"
		if u.kind == Unit.K_MONSTER or u.kind == Unit.K_SNUB:
			return "CAMP"
	elif kind == "MINION" and u.kind == Unit.K_MOTHERSHIP:
		return "MINION_MS"
	return kind


## One owner's target `tgt` this tick: count a decision event when it is a new live unit, a hold when it is the same
## hidden enemy as last tick. `oid` is the owner's instance id, `team` its team, `oname` its name for the printout.
func _see(kind: String, oid: int, team: int, oname: String, tgt: Variant) -> void:
	var last: Dictionary = _last[kind]
	var u: Unit = null
	var tid := 0
	if is_instance_valid(tgt):
		u = tgt as Unit
		if u != null and u.alive:
			tid = u.get_instance_id()
		else:
			u = null
	var prev := int(last.get(oid, 0))
	last[oid] = tid
	if u == null:
		return
	var enemy := u.team != team
	var hidden := enemy and not u.visible_to(team)
	var mapped := _mapped(kind, u)
	var c: Dictionary = _count[mapped]
	if tid != prev:
		c["events"] = int(c["events"]) + 1
		if enemy:
			c["enemy"] = int(c["enemy"]) + 1
		if hidden:
			c["hidden"] = int(c["hidden"]) + 1
			if int(_printed[mapped]) < PRINT_FIRST:
				_printed[mapped] = int(_printed[mapped]) + 1
				print("fair_play: VIOLATION %s tick %d owner %s team %d unit %d id %d" % [mapped, _frames, oname, team, u.kind, tid])
	elif hidden:
		c["stay"] = int(c["stay"]) + 1


## Print the result lines, the guards, the known list and the candidates at the end of the window.
func _finish() -> void:
	for k: String in KINDS:
		var c: Dictionary = _count[k]
		print("fair_play: %s events %d enemy %d hidden_at_pick %d stay_ticks %d" % [k, int(c["events"]), int(c["enemy"]), int(c["hidden"]), int(c["stay"])])
	for t in 2:
		_check("the audit saw no hidden enemy for team %d" % t, bool(_hidden_seen[t]))
	for k: String in MUST_SEE:
		_check("no %s decision of an enemy seen" % k, int(_count[k]["enemy"]) > 0)
	for k: String in ["WING", "PILOT_LOCK"]:
		if int(_count[k]["events"]) == 0:
			print("fair_play: INFO %s decision not seen (squads may not form in this window)" % k)
	_known_list()
	_scan_candidates()


## The violations: those of a KNOWN kind print a KNOWN line (default form), every other kind fails, the strict form fails them
## all; a KNOWN entry that both its hide case and its recorder kind show clean fails as stale.
func _known_list() -> void:
	for k: String in KNOWN:
		if k == "ADM_LIVE":
			continue
		var rec := int(_count[k]["hidden"])
		var hit := rec > 0 or int(_hide_taken.get(k, 0)) > 0
		if hit:
			_note_known(k)
		if k in STALE_CHECKED and not STRICT and not hit and int(_hide_clean.get(k, 0)) > 0:
			_fail("stale known entry %s: remove it" % k)
	for k: String in KINDS:
		if not KNOWN.has(k) and int(_count[k]["hidden"]) > 0:
			_fail("VIOLATION %s: %d decisions used a unit the team could not see" % [k, int(_count[k]["hidden"])])
	# The Admiral's own team view switch, read and never written.
	var tv_form := str(Game.opt("admiral-set", "")).contains("team_view")
	var off := false
	for t in 2:
		var ai: AdmiralAI = world.admiral_ai[t]
		if ai != null and not ai.profile.on("team_view"):
			off = true
	if tv_form:
		_check("the team view form switched the Admiral's view on", not off)
	elif off:
		_note_known("ADM_LIVE")
	elif not STRICT:
		_fail("stale known entry ADM_LIVE: remove it")


## Print the KNOWN line of kind `k` (default form), or fail it (strict form).
func _note_known(k: String) -> void:
	var entry: Array = KNOWN[k]
	if STRICT:
		_fail("strict: %s: %s (%s)" % [k, str(entry[0]), str(entry[1])])
	elif k == "ADM_LIVE":
		print("fair_play: KNOWN ADM_LIVE: team view off, the Admiral reads the live world (team_view on: false)")
	else:
		print("fair_play: KNOWN %s: %s (%s)" % [k, str(entry[0]), str(entry[1])])


## The candidate print: every line of the listed files that reads a world unit list or a spatial hash with no sight check
## (visible_to) in it or in the lines just after it. Never a failure: it is the list a reader works through.
func _scan_candidates() -> void:
	var rx := RegEx.new()
	rx.compile(CANDIDATE_READS)
	var printed := 0
	var total := 0
	var files := 0
	for fname: String in CANDIDATE_FILES:
		var path := ""
		for dir: String in CANDIDATE_DIRS:
			if FileAccess.file_exists("res://%s/%s" % [dir, fname]):
				path = "%s/%s" % [dir, fname]
				break
		_check("candidate file %s can be found" % fname, path != "")
		if path == "":
			continue
		files += 1
		var lines := FileAccess.get_file_as_string("res://" + path).split("\n")
		for i in lines.size():
			var code := lines[i].strip_edges()
			if code.begins_with("#"):
				continue
			var cut := code.find(" #")
			if cut >= 0:
				code = code.substr(0, cut)
			if rx.search(code) == null:
				continue
			var guarded := false
			for k in range(i, mini(i + CANDIDATE_LOOK + 1, lines.size())):
				if lines[k].contains("visible_to("):
					guarded = true
					break
			if guarded:
				continue
			total += 1
			if printed < MAX_CANDIDATES:
				printed += 1
				print("fair_play: candidate %s:%d" % [path, i + 1])
	print("fair_play: candidates %d lines in %d files (%d printed)" % [total, files, printed])

# --- the hide cases ------------------------------------------------------------------------------------------------

## Run every hide case for both teams and print PASS or FAIL for each (see the header of this file). Everything a case
## moves or writes (positions, sight bits, the owner's target fields) is put back, so the match goes on as before.
func _hide_cases() -> void:
	for t in 2:
		_report(L_PILOT, "PILOT", t, _try_case("PILOT", t))
		_report(L_WING, "WING", t, _try_case("WING", t))
		_report(L_MINION, "MINION", t, _try_case("MINION", t))
		_report(L_MINION_MS, "MINION_MS", t, _try_case("MINION_MS", t))
		_report(L_TURRET, "TURRET", t, _try_case("TURRET", t))
		_report(L_MOUNT, "MOUNT", t, _try_case("MOUNT", t))
		_report(L_TEAMVIEW, "TEAMVIEW", t, _case_teamview(t))


## Print the answer of one hide case: PASS, or the FAIL line that says why. `code` is one of the C_ answers. A case of a KNOWN
## kind that took the hidden unit prints INFO in the default form (its KNOWN line comes at the end) and fails in the strict form.
func _report(label: String, kind: String, t: int, code: int) -> void:
	var short := label.get_slice(":", 0)
	match code:
		C_CLEAN:
			_hide_clean[kind] = int(_hide_clean.get(kind, 0)) + 1
			print("fair_play: PASS %s (team %d)" % [label, t])
		C_TAKES:
			_hide_taken[kind] = int(_hide_taken.get(kind, 0)) + 1
			if KNOWN.has(kind) and not STRICT:
				print("fair_play: INFO %s (team %d): the picker took the hidden unit (known)" % [label, t])
			else:
				_fail("%s (team %d)" % [label, t])
		C_NOTEETH:
			_fail("%s: no teeth, the picker does not take Y even when seen (team %d)" % [short, t])
		_:
			_fail("%s: could not be set up (team %d)" % [short, t])


## The live ships of team `team`, in the world's order.
func _ships_of(team: int) -> Array:
	var out: Array = []
	for o: Variant in world.ships:
		if is_instance_valid(o):
			var s: Ship = o
			if s.alive and s.team == team:
				out.append(s)
	return out


## At most `cap` items of `list`, spread evenly over it (the first item always).
func _spread(list: Array, cap: int) -> Array:
	if list.size() <= cap:
		return list
	var out: Array = []
	for i in cap:
		out.append(list[floori(float(i * list.size()) / float(cap))])
	return out


## The candidate owners of hide case `id` for team `t`: units (or mounts) of that team that could make the pick.
func _owners(id: String, t: int) -> Array:
	var out: Array = []
	match id:
		"PILOT":
			for s: Ship in _ships_of(t):
				if s.controller is PilotAI and not (s.controller is WingmanAI) and world.pilot_ai.has(s.profile) and s.hull_id != "bomber":
					out.append(s)
		"WING":
			out = _ships_of(t)
		"MINION", "MINION_MS":
			for o: Variant in world.minions:
				if is_instance_valid(o) and (o as Minion).alive and (o as Minion).team == t:
					out.append(o)
		"TURRET":
			for o: Variant in world.turrets:
				if is_instance_valid(o) and (o as Turret).alive and (o as Turret).team == t and (o as Turret).build_left <= 0.0:
					out.append(o)
		"MOUNT":
			# Every live unit of the team that carries guns (ships, minions, turrets, the mothership): the guns that pick
			# their own target are the AUTO ones.
			for o: Variant in world.units:
				if not is_instance_valid(o) or not (o as Unit).alive or (o as Unit).team != t:
					continue
				var mounts: Variant = (o as Unit).get("mounts")
				if mounts == null:
					continue
				for mo: WeaponMount in (mounts as Array):
					if mo.mount_type == WeaponMount.AUTO and str(mo.def.get("prefer", "")) != "torp_small" and mo.reach > 0.0:
						out.append(mo)
	return _spread(out, MAX_X * 2 if id == "MOUNT" else MAX_X)


## Run hide case `id` for team `t`: try the candidate owners, the enemy ships (or the enemy mothership) and the offsets
## until a pair is found whose picker takes the unit when it is SEEN (a check that cannot fail proves nothing); then
## ask again with the unit hidden. Returns one of the C_ answers.
func _try_case(id: String, t: int) -> int:
	var xs := _owners(id, t)
	var ys: Array = _spread(_ships_of(1 - t), MAX_Y)
	if id == "MINION_MS":
		var ems := world.mothership(1 - t)
		ys = [ems] if ems != null and ems.alive else []
	if xs.is_empty() or ys.is_empty():
		return C_NOSETUP
	for x: Variant in xs:
		for y: Unit in ys:
			for off: Vector2 in _offsets(id):
				var res := _attempt(id, t, x, y, off)
				if res != C_NOTEETH:
					return res
	return C_NOTEETH


## The offsets (a few distances in eight directions) at which the hidden unit is put, for hide case `id`.
func _offsets(id: String) -> Array:
	var dists: Array = [300.0, 600.0, 1000.0]
	match id:
		"WING":
			dists = [40.0, 80.0]
		"MINION":
			dists = [120.0, 250.0, 450.0]
		"MINION_MS":
			dists = [150.0, 400.0, 800.0]
		"TURRET":
			dists = [300.0, 600.0, 900.0]
		"MOUNT":
			dists = [100.0, 200.0, 350.0]
	var out: Array = []
	for d: float in dists:
		for k in 8:
			out.append(Vector2.from_angle(float(k) * TAU / 8.0) * d)
	return out


## One try of a hide case: put the unit `y` at `off` from owner `x`, ask the picker with it seen, and (when it took it)
## clear the owner's fields, hide it and ask again. Everything is put back before it returns. Returns C_TAKES (took it
## hidden), C_CLEAN (skipped it hidden) or C_NOTEETH (did not take it even when seen: try another place).
func _attempt(id: String, t: int, x: Variant, y: Unit, off: Vector2) -> int:
	var bit := 1 << t
	var saved := _save(id, x)
	var ypos := y.global_position
	var ymask := y.visible_mask
	var res := C_NOTEETH
	if _place(id, x, y, off):
		world.registry.rebuild_hashes()
		_clear(id, x)
		y.visible_mask |= bit
		if _ask(id, t, x) == y:
			_clear(id, x)
			y.visible_mask &= ~bit
			res = C_TAKES if _ask(id, t, x) == y else C_CLEAN
	_load(id, x, saved)
	y.global_position = ypos
	y.visible_mask = ymask
	world.registry.rebuild_hashes()
	return res


## The PilotAI of ship `x` (found in World.pilot_ai by its profile, as the world made it).
func _brain(x: Variant) -> PilotAI:
	return world.pilot_ai[(x as Ship).profile] as PilotAI


## The fields of owner `x` that the picker writes, kept so they can be put back.
func _save(id: String, x: Variant) -> Dictionary:
	match id:
		"PILOT":
			var b := _brain(x)
			return {"target": b.target, "lock": b.lock_target, "skip_id": b.skip_id, "skip_until": b.skip_until, "think": b.think_t}
		"MINION", "MINION_MS":
			var m: Minion = x
			return {"target": m.target, "think": m.think_t, "pos": m.global_position}
		"TURRET":
			var tu: Turret = x
			return {"target": tu.target, "think": tu.think_t}
		"MOUNT":
			var mo: WeaponMount = x
			return {"target": mo.target, "torp": mo.target_torp}
	return {}


## Put back what _save() kept.
func _load(id: String, x: Variant, saved: Dictionary) -> void:
	match id:
		"PILOT":
			var b := _brain(x)
			b.target = saved["target"]
			b.lock_target = saved["lock"]
			b.skip_id = int(saved["skip_id"])
			b.skip_until = float(saved["skip_until"])
			b.think_t = float(saved["think"])
		"MINION", "MINION_MS":
			var m: Minion = x
			m.target = saved["target"]
			m.think_t = float(saved["think"])
			m.global_position = saved["pos"]
		"TURRET":
			var tu: Turret = x
			tu.target = saved["target"]
			tu.think_t = float(saved["think"])
		"MOUNT":
			var mo: WeaponMount = x
			mo.target = saved["target"]
			mo.target_torp = int(saved["torp"])


## Clear what makes a pick sticky or skipped (the current target, the lock, a given-up target), so the picker starts fresh.
func _clear(id: String, x: Variant) -> void:
	match id:
		"PILOT":
			var b := _brain(x)
			b.target = null
			b.lock_target = null
			b.skip_id = 0
			b.skip_until = 0.0
		"MINION", "MINION_MS":
			(x as Minion).target = null
		"TURRET":
			(x as Turret).target = null
		"MOUNT":
			(x as WeaponMount).target = null
			(x as WeaponMount).target_torp = -1


## Put the pair in place: the hidden unit `y` at `off` from the owner (a mount: along its swing), or, for the mothership
## case, the owner `x` next to the mothership. False when the place cannot be used.
func _place(id: String, x: Variant, y: Unit, off: Vector2) -> bool:
	match id:
		"MOUNT":
			var mo: WeaponMount = x
			if off.length() >= mo.reach:
				return false
			var swing := clampf(off.angle(), -mo.arc * 0.8, mo.arc * 0.8)
			y.global_position = mo.world_pos() + Vector2.from_angle(mo.owner.rotation + mo.face + swing) * off.length()
		"MINION_MS":
			var m: Minion = x
			m.global_position = y.global_position + off
			return (y as Mothership).hull_dist(m.global_position) < m.aggro
		_:
			y.global_position = (x as Unit).global_position + off
	return true


## Ask the picker of owner `x` for its answer (the unit it takes, or null).
func _ask(id: String, t: int, x: Variant) -> Variant:
	match id:
		"PILOT":
			return _brain(x).targeting.pick_target(x as Ship, 1500.0)
		"WING":
			return WingTargets.around(world, t, (x as Ship).global_position, 1500.0, [])
		"MINION", "MINION_MS":
			MinionTargeting.pick_target(x as Minion)
			return (x as Minion).target
		"TURRET":
			(x as Turret)._pick_target()
			return (x as Turret).target
		"MOUNT":
			WeaponMountTargeting.pick_target(x as WeaponMount, (x as WeaponMount).reach)
			return (x as WeaponMount).target
	return null


## The team view case: a view made for the check (the switch on, not the Admiral's own) is told of an enemy ship seen at a
## place; the ship is then hidden and moved far away, and the view must not know the new place. First, with the ship
## SEEN at the new place, the view must know it (else the case has no teeth). The ship's place and sight bit are put back.
func _case_teamview(t: int) -> int:
	var enemy := _ships_of(1 - t)
	if enemy.is_empty():
		return C_NOSETUP
	var y: Ship = enemy[0]
	var bit := 1 << t
	var ypos := y.global_position
	var ymask := y.visible_mask
	var prof := AdmiralProfile.make("standard", t)
	prof.set_value("team_view", 1)
	var view := TeamView.new(world, t, prof)
	var res := C_NOSETUP
	y.visible_mask |= bit
	view.refresh()
	var p1 := _quiet_place(ypos, enemy, y, 0)
	if p1 != Vector2.INF:
		y.global_position = p1
		view.refresh()
		if view.enemy_near(p1, 500.0) <= 0:
			res = C_NOTEETH
		else:
			var p2 := _quiet_place(p1, enemy, y, 4)
			if p2 != Vector2.INF:
				y.visible_mask &= ~bit
				y.global_position = p2
				view.refresh()
				res = C_CLEAN if view.enemy_near(p2, 500.0) == 0 else C_TAKES
	y.global_position = ypos
	y.visible_mask = ymask
	return res


## A place 4000 units from `from` (the direction tried first is number `first` of eight) with no ship of `ships`
## other than `skip` within 500 of it, or Vector2.INF when there is none.
func _quiet_place(from: Vector2, ships: Array, skip: Ship, first: int) -> Vector2:
	for k in 8:
		var p := from + Vector2.from_angle(float((first + k) % 8) * TAU / 8.0) * 4000.0
		var clear := true
		for s: Ship in ships:
			if s != skip and s.global_position.distance_to(p) < 500.0:
				clear = false
		if clear:
			return p
	return Vector2.INF
