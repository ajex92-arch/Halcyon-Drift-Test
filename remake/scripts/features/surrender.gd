class_name SurrenderFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "surrender" rule variant: a
## surrender vote (docs/FUN_PLAN.md section 5, endgame_closure fork, idea B6).
## It ends hopeless matches early, the way a MOBA team votes to give up, and
## it is part of the standard rules (CouncilPresets "pick").
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "vote"   from 15:00 a team that is far behind may hold a vote. The vote is
##            open for 30 s, then counted. After a vote closes (passed or
##            failed), that team's next vote waits 3 minutes (COOLDOWN counts
##            from the opening, so it is the 30 s plus the 3 minutes).
##            The vote counts the roster's seats of each team: every pilot
##            seat plus the admiral's own seat (seats_of(): 6 with five pilots
##            a side). It passes at 80% of them, rounded up (needed(): 5 of 6;
##            4 of 5 and 11 of 13 at other team sizes). EVERY AI seat votes by
##            the SAME rule, never keyed to its skill or to the scoring
##            probe: "yes" when its team has at least 6 fewer turrets alive
##            than the enemy AND at least 15 fewer pilot kills than the
##            enemy over the last 600 s (scoreboard numbers only). A human
##            seat on that team gets a prompt (a banner and two buttons;
##            F10 = yes, Delete = no; each is read as a press, on the tick the
##            key goes down, and no other key held at the time, Shift for
##            Boost included, changes the answer; while a text box has the
##            keyboard or the match is paused the two keys are only held, so a
##            key already down when that ends casts nothing until it is let go
##            and pressed again) and counts as one seat;
##            the AI seats alone reach the needed number, so a single human
##            cannot stop a vote that passes.
##            A passed vote ends the match as a loss for that team through
##            the same end path a mothership kill uses (the winner is set,
##            MatchRules' phase becomes "end", Events.match_over is sent) but
##            the reason line says it was a surrender. When the match ends any
##            other way while a vote is open, the module hears Events.match_over
##            and closes the open votes, and the prompt hides itself once the
##            phase is "end", so nothing is left up under the end screen. The
##            fun probe prints
##            "ended_by": "surrender" instead of "mothership" (and leaves the
##            mothership-based endgame numbers null for such a match).
## The vote is held by the module itself (a tick hook, once a second), so the
## AI admiral and the pilots need no new rule. Counted in Game.usage:
## "surrender_votes" (votes opened), "surrenders" (votes that passed) and
## "surrender_loser_halcyon" / "surrender_loser_cinder" (who gave up). The
## module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it whenever the variant is on (the
## standard rules, or --variant=surrender:vote), runs it through
## World.tick_hooks and asks it for banner(). SurrenderPrompt (the Yes and No
## buttons) calls cast_vote(). tests/fun_probe.gd reads Game.usage["surrenders"]
## for "ended_by".

## The variant key this module belongs to.
const KEY := "surrender"
## Match time (seconds) from which votes are allowed: 15:00.
const START_TIME := 900.0
## Seconds a vote stays open.
const VOTE_TIME := 30.0
## Seconds from a vote's opening to the earliest next vote of that team: the vote's
## own 30 seconds, then 3 minutes after it closes.
const COOLDOWN := VOTE_TIME + 180.0
## The key that answers yes. It is also the key the prompt's banner names.
const YES_KEY := KEY_F10
## The key that answers no: one that no row of the key map names, alone or as a
## modifier, so a key held in play (Shift to boost) can never turn a yes into a no.
const NO_KEY := KEY_DELETE
## The share of the seats that must vote yes (0.8 = 80%, rounded up).
const PASS_SHARE := 0.8
## "Far behind", turrets: at least this many fewer turrets alive.
const TURRET_GAP := 6
## "Far behind", pilot kills: at least this many fewer over the window.
const KILL_GAP := 15
## The window (seconds) the pilot kills are counted over.
const KILL_WINDOW := 600.0

## The world we belong to.
var world: World
## Match time (seconds) when each team may open its next vote.
var next_vote := [START_TIME, START_TIME]
## Match time (seconds) when each team's open vote ends (0 = none open).
var vote_end := [0.0, 0.0]
## The human seat's vote on an open vote: 1 yes, -1 no, 0 none yet.
var human_vote := [0, 0]
## How many AI seats voted yes on each team's open vote (they all vote the
## moment it opens, by the same rule).
var ai_yes := [0, 0]
## Pilot kills, newest last: each entry [match time, killing team].
var _kills: Array = []
## Seconds until the next once-a-second check.
var _t := 0.0
## Was the yes key down on the last tick?
var _yes_was := false
## Was the no key down on the last tick?
var _no_was := false
## Where the keyboard is read from: a Callable that takes a key code and says
## whether that key is down. Input's physical key read by default. The module reads
## the keyboard only through it: most cases of tests/surrender_check.gd give it a
## fake keyboard, and one case sends real key events through Input to test the
## default read (a Shift read straight through Input is caught by that case).
var key_probe := Callable(Input, "is_physical_key_pressed")


## Switch the surrender vote on for match `w`. FeatureRegistry calls this
## once at match start. An unknown value only gets a warning. With a window
## the Yes and No buttons are added on a layer of their own.
func install(w: World) -> void:
	if Game.variant(KEY) != "vote":
		push_warning("surrender: unknown value \"%s\" (use off or vote); nothing changed" % Game.variant(KEY))
		return
	world = w
	Events.unit_killed.connect(_on_unit_killed)
	Events.match_over.connect(_on_match_over)
	w.tick_hooks.append(_tick)
	# The buttons need a screen; headless runs have none. This module is not a
	# node, so the layer is added under the world.
	if DisplayServer.get_name() != "headless":
		var layer := CanvasLayer.new()
		layer.layer = 4
		var prompt := SurrenderPrompt.new()
		prompt.setup(self)
		layer.add_child(prompt)
		w.add_child(layer)


## A unit died (Events.unit_killed): remember pilot kills (a pilot ship of
## the other team made the last hit on a pilot ship), for the vote rule.
func _on_unit_killed(u: Node, info: RefCounted) -> void:
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null or unit.kind != Unit.K_SHIP or d.source_profile == null:
		return
	var killer := d.source_profile as PilotProfile
	if killer != null and killer.team != unit.team and killer.team <= 1:
		_kills.append([world.time, killer.team])


## The match is over (Events.match_over), by a mothership or by a vote: close
## every open vote, so the banner and the prompt are not left up under the end
## screen when the tick hooks have stopped.
func _on_match_over(_winner: int, _reason: String) -> void:
	vote_end = [0.0, 0.0]


## How many seats team `team` has: the profiles of that team that are not
## crew, which is every pilot seat plus the admiral's own seat (a human's or
## the computer's). At least 1, so an emptied roster never passes a vote on
## no votes.
func seats_of(team: int) -> int:
	var n := 0
	for p: PilotProfile in world.profiles:
		if p.team == team and not p.is_crew:
			n += 1
	return maxi(1, n)


## How many yes votes team `team`'s vote needs: PASS_SHARE of its seats,
## rounded up.
func needed(team: int) -> int:
	return ceili(PASS_SHARE * float(seats_of(team)))


## Is the human's own team voting right now (a vote open on the team the
## human sits on)? False with no human seat.
func human_vote_open() -> bool:
	return world != null and world.human != null and float(vote_end[world.human.team]) > 0.0


## The human seat answers team `team`'s open vote: yes or no. Does nothing
## unless that vote is open and the human sits on that team. The keys and the
## prompt's buttons both come here.
func cast_vote(team: int, yes: bool) -> void:
	if world == null or world.human == null or world.human.team != team:
		return
	if float(vote_end[team]) <= 0.0:
		return
	human_vote[team] = 1 if yes else -1


## The keys' step of a tick, with the keys that are down now given as `down`
## (key code -> true): a vote is cast on the tick a key goes down, not on every
## tick it is held, so the answer comes from the key that was just pressed and
## from nothing else held at the time. Holding the yes key and then pressing the
## no key answers no. A key already down when the vote opens casts nothing until
## it is let go and pressed again. If both go down on the same tick the no wins.
## _tick feeds it the keyboard (through _read_keys) except while a text box has the
## keyboard, when it calls hold_keys() instead; tests/surrender_check.gd feeds it
## by hand and, through key_probe, drives _tick's own read.
func key_step(down: Dictionary) -> void:
	var yes_now := bool(down.get(YES_KEY, false))
	var no_now := bool(down.get(NO_KEY, false))
	var yes_edge := yes_now and not _yes_was
	var no_edge := no_now and not _no_was
	_yes_was = yes_now
	_no_was = no_now
	if not human_vote_open():
		return
	if yes_edge:
		cast_vote(world.human.team, true)
	if no_edge:
		cast_vote(world.human.team, false)


## Hold the two vote keys: remember each as down or not down right now (asking the
## yes key first and the no key second), and cast nothing. A key already down when
## this stops being called then casts nothing until it is let go and pressed again.
func hold_keys() -> void:
	_yes_was = bool(key_probe.call(YES_KEY))
	_no_was = bool(key_probe.call(NO_KEY))


## Hold the keys (hold_keys()) when a text box has the keyboard or the match is
## paused, and do nothing otherwise. No tick runs while the match is paused, so
## SurrenderPrompt calls this from its own frame.
func hold_if_blocked() -> void:
	if _typing() or (world != null and world.is_inside_tree() and world.get_tree().paused):
		hold_keys()


## Is a text box (the note box) holding the keyboard? Then typed keys are text, and
## the vote holds its keys. The same test as CameraRig._typing().
func _typing() -> bool:
	if world == null or not world.is_inside_tree():
		return false
	var f := world.get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## The keys the vote reads, as a dictionary (key code -> true when it is down
## now): the yes key and the no key, read through key_probe, and no other key, so
## nothing held in play (Shift to boost) can change an answer. It reads the
## keyboard whatever has focus: while a text box has it, _tick calls hold_keys()
## instead of this. _tick calls this on every other tick.
func _read_keys() -> Dictionary:
	return {
		YES_KEY: bool(key_probe.call(YES_KEY)),
		NO_KEY: bool(key_probe.call(NO_KEY)),
	}


## One tick (World.tick_hooks): read the human's keys (or hold them while a text
## box has the keyboard), and once a second open or count votes.
func _tick(dt: float) -> void:
	if _typing():
		hold_keys()
	else:
		key_step(_read_keys())
	_t -= dt
	if _t > 0.0:
		return
	_t = 1.0
	for t in 2:
		if float(vote_end[t]) > 0.0:
			if world.time >= float(vote_end[t]):
				_count(t)
		elif world.time >= float(next_vote[t]) and _far_behind(t):
			_open(t)


## Does the AI seat rule say "yes" for team `t` right now? (The same answer
## for every AI seat of the team.)
func _far_behind(t: int) -> bool:
	var n := _numbers(t)
	return int(n[1]) - int(n[0]) >= TURRET_GAP and int(n[3]) - int(n[2]) >= KILL_GAP


## The scoreboard numbers the rule looks at, for team `t`: [our turrets
## alive, their turrets alive, our pilot kills, their pilot kills] (kills
## over the last 600 s).
func _numbers(t: int) -> Array:
	# Step 1: turrets alive (finished ones), for both teams.
	var mine := 0
	var theirs := 0
	for tu: Turret in world.turrets:
		if tu.alive and tu.is_built():
			if tu.team == t:
				mine += 1
			elif tu.team == 1 - t:
				theirs += 1
	# Step 2: pilot kills in the last 600 s, for both teams (drop old entries).
	while not _kills.is_empty() and world.time - float((_kills[0] as Array)[0]) > KILL_WINDOW:
		_kills.pop_front()
	var k := [0, 0]
	for e: Array in _kills:
		k[int(e[1])] += 1
	return [mine, theirs, int(k[t]), int(k[1 - t])]


## Open team `t`'s vote.
func _open(t: int) -> void:
	vote_end[t] = world.time + VOTE_TIME
	next_vote[t] = world.time + COOLDOWN
	human_vote[t] = 0
	# Every AI seat votes now, by the same rule (the human seat, if any, is
	# not an AI seat).
	var human := world.human != null and world.human.team == t
	ai_yes[t] = (seats_of(t) - (1 if human else 0)) if _far_behind(t) else 0
	Game.count_usage("surrender_votes")
	Events.feed.emit("The %s fleet is voting on a surrender (%d s)." % [Rules.TEAM_NAMES[t], int(VOTE_TIME)], "info", -1)


## Count team `t`'s vote when it closes: the AI seats voted when it opened,
## the human seat (if any) has voted since.
func _count(t: int) -> void:
	vote_end[t] = 0.0
	# Step 1: the AI seats' votes, cast when the vote opened.
	var yes := int(ai_yes[t])
	var human := world.human != null and world.human.team == t
	# Step 2: the human seat votes for itself.
	if human and int(human_vote[t]) > 0:
		yes += 1
	if yes < needed(t):
		var n := _numbers(t)
		Events.feed.emit("The %s surrender vote failed (%d of %d seats; turrets %d-%d, pilot kills %d-%d)." % [Rules.TEAM_NAMES[t], yes, seats_of(t), n[0], n[1], n[2], n[3]], "info", -1)
		return
	# Step 3: it passed: the match ends as a loss for team t (the same steps
	# as MatchRules.on_mothership_destroyed, with a surrender message).
	if world.phase != "play":
		return
	Game.count_usage("surrenders")
	Game.count_usage("surrender_loser_halcyon" if t == Rules.HALCYON else "surrender_loser_cinder")
	var winner := 1 - t
	world.phase = "end"
	world.winner = winner
	var reason := "The %s fleet surrendered." % Rules.TEAM_NAMES[t]
	Events.feed.emit(reason, "info", -1)
	Events.match_over.emit(winner, reason)


## The HUD banner for the human on `team`: [] for none, else [title, sub,
## tone].
func banner(_w: World, team: int) -> Array:
	if float(vote_end[team]) > 0.0:
		return ["Surrender vote", "Our fleet is voting to surrender (%d s left). Click Yes or No, or press F10 = yes, Delete = no." %int(ceil(float(vote_end[team]) - world.time)), "cinder"]
	if float(vote_end[1 - team]) > 0.0:
		return ["Enemy surrender vote", "The %s fleet is voting to give up (%d s left)." % [Rules.TEAM_NAMES[1 - team], int(ceil(float(vote_end[1 - team]) - world.time))], "amber"]
	return []
