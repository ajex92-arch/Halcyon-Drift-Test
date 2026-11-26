extends Node
## WHAT THIS IS: the check for the surrender vote (scripts/features/surrender.gd)
## and its Yes and No buttons (scripts/ui/surrender_prompt.gd). It prints one
## PASS or FAIL line for each thing it looks at, then "surrender_check: N
## failures", and quits.
##
## HOW IT WORKS: setup() keeps the running match; the first physics frame runs
## every case in one go, against the real feature object (world.features["surrender"]),
## so no match time passes while they run, except in the one case that sends real
## key events through Input and waits a few frames for them. The
## cases set the match clock by hand and call the feature's own once-a-second
## step (its tick hook with the second's timer at zero), so a vote opens,
## closes and cools down exactly as it does in play. The cases:
##   the seats: a team's seats are its roster (pilot seats and the admiral's
##   seat), the number of yes votes needed is 80% of them rounded up (5 of 6
##   here, 4 of 5 and 11 of 13 for other roster sizes);
##   the timing: no vote opens one second before 15:00 and one opens at 15:00
##   when a team is far behind (nine turrets down and sixteen pilot kills for
##   the other side, staged the way tests/fc_smoke.gd stages it); after a
##   failed vote (opened at 15:00, closed at 15:30) no new vote opens 179 s
##   after it closed (nor 150 s after, where the old wait from the opening
##   ended), and one opens 180 s after it closed;
##   the standard rules: the "pick" preset carries surrender:vote, "within" and
##   "none" do not, and a default launch has the feature (a launch with
##   --preset=none has none, and the check then only reads the presets);
##   the human seat: cast_vote() changes nothing with no vote open, and sets
##   yes or no while one is open; the keys (F10 yes, Delete no) are read as
##   presses through the module's key_step() with the keys that are down given
##   by hand: F10 with Boost's key held
##   is a yes, Delete is a no, a held key casts once, and no row of the key map
##   names Delete; then the same keys through the module's own tick (_tick, with
##   the keyboard replaced by a fake one through key_probe): F10 is yes, Delete is
##   no, a held Shift changes nothing, and only the two vote keys are asked about;
##   one case sends real key events through Input (the module's default read) and
##   checks that a held Shift alone casts nothing, F10 with Shift held casts yes
##   and Delete with Shift held casts no;
##   while a LineEdit has the keyboard the two vote keys are held, not read (a held
##   Delete or F10 casts nothing, a Delete still down when the focus is let go
##   casts nothing, and a fresh press after it casts no), and hold_keys() and
##   hold_if_blocked() (which holds them while a text box or a pause has the
##   keyboard) do the same, with the match paused and with it running;
##   the prompt keeps running while the match is paused, its vote box and buttons
##   stay inert then (a click on Yes casts nothing), and its own frame holds the
##   keys; with the match running a click on Yes casts a yes;
##   the prompt is hidden with no vote, shown for
##   the human's own team's vote, hidden for the other team's, and its Yes
##   button casts a yes; once the match is over (phase "end") the prompt is
##   hidden even with a vote open, and the module's match-over handler closes both
##   teams' votes (called by hand here, because the signal's own emit would also run
##   the game's end handler; the signal is tested in the end cases);
##   the end: five yes votes of six end the match as a loss for the voting
##   team and, through Events.match_over, close the other team's open vote, four do
##   not, and a human's "no" cannot stop five computer seats.
## The two cases that end the match come last, because a match that ends quits
## the game.
##
## HOW TO RUN IT ("godot" is the Godot console program; the roster must be
## whole, so no --no-pilots and no --no-admiral-ai):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=1 --test=surrender_check
## and once more with --preset=none, which must print that no feature is
## installed. It needs no match time, so it finishes in a few seconds.
##
## WHO USES IT: main.gd loads it for --test=surrender_check (it loads
## tests/<name>.gd, adds it after the World and calls setup()). Nothing in the
## game reads it.

## The running match (set by setup()).
var world: World
## The surrender feature of the match, or null when the rules do not have it.
var sf: SurrenderFeature
## How many checks failed.
var _failures := 0
## True once the cases have run.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	sf = w.features.get("surrender") as SurrenderFeature


## Godot calls this every tick: run the cases once, print the result and quit.
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	_done = true
	_standard_rules()
	if sf == null:
		print("surrender_check: no surrender feature is installed (variant is %s)" % Game.variant("surrender"))
	else:
		_seats()
		_timing()
		_human_seat()
		_keys()
		_tick_keys()
		_typing_keys()
		_hold_cases()
		await _real_keys()
		_prompt()
		_endings()
	print("surrender_check: %d failures" % _failures)
	get_tree().quit()


## Print one PASS or FAIL line and count a failure.
func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s %s" % [label, detail])


## The presets: the standard rules carry the vote, the other two do not; and
## the match has the feature exactly when the launch variant is on.
func _standard_rules() -> void:
	_check("the standard rules (pick) carry surrender:vote", CouncilPresets.variant_string(CouncilPresets.STANDARD).split(",").has("surrender:vote"))
	_check("the within preset has no surrender pair", not CouncilPresets.variant_string("within").contains("surrender"))
	_check("the none preset has no surrender pair", not CouncilPresets.variant_string("none").contains("surrender"))
	var vote_on := Game.variant("surrender") == "vote"
	_check("the match has the feature exactly when the launch variant is vote", vote_on == (sf != null), "variant %s" % Game.variant("surrender"))
	if str(Game.opt("preset", "")) == "":
		_check("a default launch plays surrender:vote", vote_on)
	if str(Game.opt("preset", "")) == CouncilPresets.OLD_RULES:
		_check("--preset=none installs no surrender feature", sf == null and not world.features.has("surrender"))


## The roster's seats and the number of yes votes needed.
func _seats() -> void:
	_check("team 0 has 6 seats (five pilots and the admiral)", sf.seats_of(0) == 6, str(sf.seats_of(0)))
	_check("team 1 has 6 seats (five pilots and the admiral)", sf.seats_of(1) == 6, str(sf.seats_of(1)))
	_check("6 seats need 5 yes votes", sf.needed(0) == 5 and sf.needed(1) == 5, "%d %d" % [sf.needed(0), sf.needed(1)])
	# Other roster sizes: take a seat away (5 left) and add seven (13).
	var saved: Array[PilotProfile] = world.profiles.duplicate()
	for p: PilotProfile in saved:
		if p.team == 0:
			world.profiles.erase(p)
			break
	_check("5 seats need 4 yes votes", sf.seats_of(0) == 5 and sf.needed(0) == 4, "%d %d" % [sf.seats_of(0), sf.needed(0)])
	_check("the other team's seats are not changed", sf.seats_of(1) == 6)
	world.profiles.assign(saved)
	for i in 7:
		world.profiles.append(PilotProfile.new("Extra%d" % i, 0, 10 + i, false))
	_check("13 seats need 11 yes votes", sf.seats_of(0) == 13 and sf.needed(0) == 11, "%d %d" % [sf.seats_of(0), sf.needed(0)])
	world.profiles.assign(saved)
	# A crew profile is not a seat.
	var crew := PilotProfile.new("Crew", 0, 20, false)
	crew.is_crew = true
	world.profiles.append(crew)
	_check("a crew profile is not a seat", sf.seats_of(0) == 6)
	world.profiles.assign(saved)
	_check("the roster is back as it was", sf.seats_of(0) == 6 and sf.seats_of(1) == 6)


## Run the feature's once-a-second step with the clock at `t` seconds.
func _tick_at(t: float) -> void:
	world.time = t
	sf._t = 0.0
	sf._tick(0.0)


## Make team 1 far behind: nine of its turrets destroyed and sixteen pilot
## kills for team 0 on the book, stamped with the clock as it is now.
func _stage_far_behind() -> void:
	var n := 0
	for t: Turret in world.turrets.duplicate():
		if t.team == Rules.CINDER and n < 9:
			n += 1
			world.combat.kill(t, DamageInfo.from_unit(null, 1.0, Rules.W_BOLT, t.global_position))
	for i in 16:
		sf._kills.append([world.time, Rules.HALCYON])


## When a vote may open and how long a team waits after one.
func _timing() -> void:
	world.time = 899.0
	_stage_far_behind()
	_check("the staged team is far behind", sf._far_behind(1) and not sf._far_behind(0))
	_tick_at(899.0)
	_check("no vote opens at 14:59", float(sf.vote_end[1]) == 0.0 and float(sf.vote_end[0]) == 0.0)
	_tick_at(900.0)
	_check("a vote opens at 15:00 for the team that is far behind", float(sf.vote_end[1]) > 0.0, str(sf.vote_end))
	_check("the vote is open for 30 seconds", is_equal_approx(float(sf.vote_end[1]), 930.0))
	_check("the other team has no vote", float(sf.vote_end[0]) == 0.0)
	_check("all 6 computer seats voted yes", int(sf.ai_yes[1]) == 6, str(sf.ai_yes))
	# A failed vote (4 yes of 6): the match goes on and the next vote waits.
	sf.ai_yes[1] = 4
	_tick_at(930.0)
	_check("four yes votes of six fail", float(sf.vote_end[1]) == 0.0 and world.phase == "play")
	# The wait is 3 minutes after the vote closed (opened at 900, closed at 930).
	_tick_at(1080.0)
	_check("no new vote 150 seconds after the failed vote closed", float(sf.vote_end[1]) == 0.0)
	_tick_at(1109.0)
	_check("no new vote 179 seconds after the failed vote closed", float(sf.vote_end[1]) == 0.0)
	_tick_at(1110.0)
	_check("a new vote opens 180 seconds after the failed vote closed", float(sf.vote_end[1]) > 0.0, str(sf.vote_end))
	# Close it again so the later cases start clean.
	sf.ai_yes[1] = 0
	_tick_at(1140.0)
	_check("the match is still on", world.phase == "play")


## Put the cases' votes back to nothing, with the clock at 2000 s.
func _clean() -> void:
	sf.vote_end = [0.0, 0.0]
	sf.human_vote = [0, 0]
	sf.ai_yes = [0, 0]
	sf.next_vote = [0.0, 0.0]
	world.time = 2000.0


## The first profile of `team`.
func _profile_of(team: int) -> PilotProfile:
	for p: PilotProfile in world.profiles:
		if p.team == team and not p.is_crew:
			return p
	return null


## The human seat: cast_vote() and the count of a seat that is human.
func _human_seat() -> void:
	_clean()
	var saved_human := world.human
	world.human = _profile_of(1)
	_check("a human seat is still one of the seats", sf.seats_of(1) == 6)
	sf.cast_vote(1, true)
	_check("cast_vote with no vote open changes nothing", int(sf.human_vote[1]) == 0)
	sf._open(1)
	sf.ai_yes[1] = 5
	sf.cast_vote(1, true)
	_check("cast_vote(true) with a vote open sets a yes", int(sf.human_vote[1]) == 1)
	sf.cast_vote(1, false)
	_check("cast_vote(false) sets a no", int(sf.human_vote[1]) == -1)
	sf.cast_vote(0, true)
	_check("cast_vote for the other team changes nothing", int(sf.human_vote[0]) == 0)
	_clean()
	world.human = saved_human
	# The seat count of a vote that opens while a human sits on the team: five
	# computer seats vote.
	_clean()
	world.human = _profile_of(1)
	world.time = 1000.0
	_stage_far_behind()
	sf._open(1)
	_check("with a human seat on a far behind team, 5 computer seats vote yes", int(sf.ai_yes[1]) == 5, str(sf.ai_yes))
	_clean()
	world.human = saved_human


## Does a row's key text (or a preset's value for a row: text, or a dictionary
## with "keys") name key code `code`, alone or as a modifier? `word` is the key's
## name as Godot writes it, since a key the translator cannot read has no code.
func _names_key(value: Variant, code: int, word: String) -> bool:
	var text := String((value as Dictionary)["keys"]) if value is Dictionary else String(value)
	for part in text.split("|", false):
		var p := KeyCodes.parse(String(part))
		if bool(p["ok"]) and int(p["code"]) == code:
			return true
		for piece in String(part).split("+", false):
			if String(piece).to_lower() == word.to_lower():
				return true
	return false


## The keys: F10 and the no key read as presses, and the no key is free.
func _keys() -> void:
	_clean()
	var saved_human := world.human
	world.human = _profile_of(1)
	var yes_key := SurrenderFeature.YES_KEY
	var no_key := SurrenderFeature.NO_KEY
	# The key the Boost row holds, read from the key map.
	var boost := int(KeyCodes.parse(String(KeyMap.effective_keys("flying", "boost")[0]))["code"])
	_check("Boost is a key of its own, not the yes or the no key", boost != yes_key and boost != no_key and boost != 0, str(boost))
	# F10 pressed while Boost's key is held: a yes.
	sf._yes_was = false
	sf._no_was = false
	sf._open(1)
	sf.key_step({yes_key: true, boost: true})
	_check("F10 pressed with Boost's key held casts yes", int(sf.human_vote[1]) == 1, str(sf.human_vote))
	# Delete pressed: a no (Boost held again, still a plain press of one key).
	sf.key_step({})
	sf.key_step({no_key: true, boost: true})
	_check("the no key casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# A key held over several ticks casts once: a button press for no between the
	# ticks is not undone by the held F10.
	_clean()
	sf._yes_was = false
	sf._no_was = false
	sf._open(1)
	sf.key_step({yes_key: true})
	_check("F10 going down casts yes", int(sf.human_vote[1]) == 1)
	sf.cast_vote(1, false)
	for i in 5:
		sf.key_step({yes_key: true})
	_check("holding F10 over several ticks casts once", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# Holding F10 and then pressing the no key is a no, and the held F10 does not undo it.
	_clean()
	sf._yes_was = false
	sf._no_was = false
	sf._open(1)
	sf.key_step({yes_key: true})
	sf.key_step({yes_key: true, no_key: true})
	_check("holding F10 and then pressing the no key casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	sf.key_step({yes_key: true, no_key: true})
	sf.key_step({yes_key: true})
	_check("the held F10 does not turn it back into a yes", int(sf.human_vote[1]) == -1)
	# Let go and press F10 again: a yes.
	sf.key_step({})
	sf.key_step({yes_key: true})
	_check("F10 let go and pressed again casts yes", int(sf.human_vote[1]) == 1)
	# A key already down when the vote opens casts nothing until it is pressed again.
	_clean()
	sf._yes_was = false
	sf._no_was = false
	sf.key_step({yes_key: true})
	sf._open(1)
	sf.key_step({yes_key: true})
	_check("F10 held from before the vote opened casts nothing", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	# The keys do nothing for a vote of the other team, or with no human seat.
	sf.key_step({})
	sf.key_step({yes_key: true})
	_check("the vote is cast once the key is pressed again", int(sf.human_vote[1]) == 1)
	_clean()
	sf._open(0)
	sf.key_step({})
	sf.key_step({yes_key: true})
	_check("F10 does nothing for the other team's vote", int(sf.human_vote[0]) == 0 and int(sf.human_vote[1]) == 0)
	_clean()
	world.human = null
	sf._open(1)
	sf.key_step({})
	sf.key_step({yes_key: true})
	_check("F10 does nothing with no human seat", int(sf.human_vote[1]) == 0)
	# The no key is named by no row of any mode, in no preset, and is not a modifier.
	var word := OS.get_keycode_string(no_key)
	var named := []
	for m: String in KeyMapData.MODES:
		for r: Dictionary in KeyMap.rows(m):
			for k in KeyMap.effective_keys(m, String(r["id"])):
				if _names_key(k, no_key, word):
					named.append("%s/%s" % [m, r["id"]])
	for g: Dictionary in KeyMapData.PRESETS:
		for pid: String in g["presets"]:
			var rows: Dictionary = (g["presets"][pid] as Dictionary)["rows"]
			for m: String in rows:
				for id: String in rows[m]:
					if _names_key(rows[m][id], no_key, word):
						named.append("preset %s/%s %s/%s" % [g["id"], pid, m, id])
	_check("no row of the key map names the no key (%s)" % word, named.is_empty(), ",".join(named))
	_check("the no key is not a modifier", not KeyCodes.MODIFIER_CODES.has(no_key))
	_check("the vote's keys are listed with the keys other features read", _variant_key_listed(word))
	_clean()
	world.human = saved_human


## The fake keyboard of _tick_keys: the key codes "held down" now.
var _held := {}
## The key codes _tick asked the fake keyboard about, in order.
var _asked: Array = []


## The module's key_probe in these cases: is key `code` in _held? Remembers
## what was asked.
func _fake_key(code: int) -> bool:
	_asked.append(code)
	return bool(_held.get(code, false))


## One tick of the module itself (its tick hook) with `held` as the keys down. The
## second's timer is set so the once-a-second step does not run: only the key read does.
func _key_tick(held: Dictionary) -> void:
	_held = held
	_asked = []
	sf._t = 5.0
	sf._tick(0.0)


## Open team 1's vote with no key remembered as down, for the _tick cases.
func _fresh_vote() -> void:
	_clean()
	sf._yes_was = false
	sf._no_was = false
	sf._open(1)


## The keys through _tick itself (not key_step): the module's own key read, with the
## keyboard replaced by the fake one. F10 casts yes and Delete casts no, a held Shift
## changes nothing, and _tick asks about the two vote keys on every tick and no others.
func _tick_keys() -> void:
	_clean()
	var saved_human := world.human
	var saved_probe := sf.key_probe
	world.human = _profile_of(1)
	sf.key_probe = _fake_key
	var yes_key := SurrenderFeature.YES_KEY
	var no_key := SurrenderFeature.NO_KEY
	# F10 alone: a yes (a swap of the two keys would cast no).
	_fresh_vote()
	_key_tick({yes_key: true})
	_check("_tick: F10 casts yes", int(sf.human_vote[1]) == 1, str(sf.human_vote))
	_check("_tick asks about the yes key and the no key, once each, and no other key", _asked == [yes_key, no_key], str(_asked))
	# Delete alone: a no.
	_fresh_vote()
	_key_tick({no_key: true})
	_check("_tick: Delete casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# Shift held, F10 pressed: a yes (a read of Shift would make it a no).
	_fresh_vote()
	_key_tick({KEY_SHIFT: true})
	_key_tick({KEY_SHIFT: true, yes_key: true})
	_check("_tick: F10 pressed with Shift held casts yes", int(sf.human_vote[1]) == 1, str(sf.human_vote))
	# Shift and Delete: still a no.
	_fresh_vote()
	_key_tick({KEY_SHIFT: true, no_key: true})
	_check("_tick: Delete pressed with Shift held casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# Nothing held on any tick: nothing cast (so a vote the key read caused is the key's).
	_fresh_vote()
	_key_tick({})
	_key_tick({})
	_check("_tick: no key held casts nothing", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	# A key that is not a vote key is never asked about, so it casts nothing.
	_key_tick({KEY_SPACE: true, KEY_F9: true})
	_check("_tick: other keys cast nothing", int(sf.human_vote[1]) == 0 and _asked == [yes_key, no_key], str(_asked))
	sf.key_probe = saved_probe
	_clean()
	world.human = saved_human


## A text box with the keyboard: the vote keys are held, not read. A Delete down
## before hold_keys() casts nothing after it; with a vote open and a LineEdit focused
## in the tree, a held Delete (or F10) casts nothing through _tick, the keyboard is
## asked about the two vote keys only to hold them, and a Delete still down when the
## focus is let go casts nothing; a fresh press after that casts.
func _typing_keys() -> void:
	_clean()
	var saved_human := world.human
	var saved_probe := sf.key_probe
	world.human = _profile_of(1)
	sf.key_probe = _fake_key
	var yes_key := SurrenderFeature.YES_KEY
	var no_key := SurrenderFeature.NO_KEY
	var edit := LineEdit.new()
	world.add_child(edit)
	_check("no text box has the keyboard yet", not sf._typing())
	# A Delete down on the fake keyboard before the keys are held: the hold remembers
	# it as down, so the next tick sees no press.
	_held = {no_key: true}
	_fresh_vote()
	sf.hold_keys()
	_key_tick({no_key: true})
	_check("a Delete held before the tick casts nothing after hold_keys", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	_key_tick({})
	_key_tick({no_key: true})
	_check("a fresh Delete press after the hold casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	edit.grab_focus()
	_check("a focused LineEdit counts as typing", sf._typing(), str(world.get_viewport().gui_get_focus_owner()))
	_fresh_vote()
	_key_tick({yes_key: true})
	_check("a held F10 casts nothing while a text box has focus", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	_key_tick({no_key: true})
	_check("a held Delete casts nothing while a text box has focus", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	_check("while typing only the two vote keys are asked, to hold them", _asked == [yes_key, no_key] and int(sf.human_vote[1]) == 0, str(_asked))
	# Focus let go with Delete still down: nothing is cast, and a fresh press casts no.
	edit.release_focus()
	_check("a LineEdit that let go no longer counts as typing", not sf._typing())
	_key_tick({no_key: true})
	_check("a Delete held through the focus release casts nothing", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	_key_tick({})
	_key_tick({no_key: true})
	_check("a fresh Delete press after the release casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	edit.free()
	sf.key_probe = saved_probe
	_clean()
	world.human = saved_human


## hold_if_blocked() and the prompt while the match is paused. Every case that
## expects the no key to be remembered as down sets the fake keyboard and the
## module's memory by hand first, and every pause is let go straight after the case
## that needed it. Nothing here waits for a frame, so none runs while the tree is
## paused or while the prompt is in the tree. The prompt cases read the prompt's
## process mode: its own frame call below passes with or without it, so the mode is
## the one thing that catches a prompt that stops running while the match is paused.
func _hold_cases() -> void:
	_clean()
	var saved_human := world.human
	var saved_probe := sf.key_probe
	world.human = _profile_of(1)
	sf.key_probe = _fake_key
	var no_key := SurrenderFeature.NO_KEY
	# The match running, no text box focused: nothing is held, so a fresh press casts.
	_fresh_vote()
	_held = {no_key: true}
	sf._no_was = false
	sf.hold_if_blocked()
	_check("hold_if_blocked does nothing while the match runs and no text box has the keyboard", not sf._no_was)
	_key_tick({no_key: true})
	_check("after hold_if_blocked a fresh Delete press casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# The match paused: the keys are held.
	_fresh_vote()
	_held = {no_key: true}
	sf._no_was = false
	get_tree().paused = true
	sf.hold_if_blocked()
	get_tree().paused = false
	_check("hold_if_blocked holds the keys while the match is paused", sf._no_was)
	# The prompt, in the tree under the world.
	var prompt := SurrenderPrompt.new()
	prompt.setup(sf)
	world.add_child(prompt)
	_check("the prompt keeps running while the match is paused", prompt.process_mode == Node.PROCESS_MODE_ALWAYS, str(prompt.process_mode))
	if not SurrenderPrompt.CLICK_WHILE_PAUSED:
		_check("the vote box and its buttons stay inert while the match is paused", prompt.panel.process_mode == Node.PROCESS_MODE_PAUSABLE, str(prompt.panel.process_mode))
	_fresh_vote()
	_held = {no_key: true}
	sf._no_was = false
	get_tree().paused = true
	prompt._process(0.0)
	get_tree().paused = false
	_check("the prompt's own frame holds the keys while paused", sf._no_was)
	_fresh_vote()
	if not SurrenderPrompt.CLICK_WHILE_PAUSED:
		get_tree().paused = true
		prompt.yes_button.pressed.emit()
		get_tree().paused = false
		_check("a click on Yes while the match is paused casts nothing", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	_fresh_vote()
	prompt.yes_button.pressed.emit()
	_check("a click on Yes with the match running casts a yes", int(sf.human_vote[1]) == 1, str(sf.human_vote))
	prompt.free()
	_held = {}
	sf.key_probe = saved_probe
	_clean()
	world.human = saved_human


## A key event as the keyboard would send it (the keycode and the physical keycode
## both set), pressed or let go.
func _key_event(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	return e


## Send key `code` down or up through Input, flush the buffered events and wait two
## frames for it to show.
func _send_key(code: Key, down: bool) -> void:
	Input.parse_input_event(_key_event(code, down))
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame


## One tick of the module itself with the human seat `seat` set for that tick only
## and the second's timer set so the once-a-second step does not run.
func _real_tick(seat: PilotProfile) -> void:
	var saved_human := world.human
	world.human = seat
	sf._t = 5.0
	sf._tick(0.0)
	world.human = saved_human


## The default key read, with real key events sent through Input: F10 is down after
## the send, a held Shift alone casts nothing, F10 with Shift held casts yes, and
## Delete with Shift held casts no. Prints how F10 reads right after the send, after
## the flush and after two frames. The module's tick hook is out of the world's tick
## hooks while this runs, so only the cases' own ticks read the keys; the keys are all
## let go, and the hook, the key probe and the human seat put back, at the end.
func _real_keys() -> void:
	var saved_human := world.human
	var saved_probe := sf.key_probe
	var seat := _profile_of(1)
	sf.key_probe = Callable(Input, "is_physical_key_pressed")
	var hook_at := world.tick_hooks.find(sf._tick)
	if hook_at >= 0:
		world.tick_hooks.remove_at(hook_at)
	# The three readings of one key.
	Input.parse_input_event(_key_event(KEY_F10, true))
	var r1 := Input.is_physical_key_pressed(KEY_F10)
	Input.flush_buffered_events()
	var r2 := Input.is_physical_key_pressed(KEY_F10)
	await get_tree().process_frame
	await get_tree().process_frame
	var r3 := Input.is_physical_key_pressed(KEY_F10)
	print("real keys: F10 reads after send, after flush, after two frames: %s %s %s" % [r1, r2, r3])
	_check("real keys: Input takes a key event (F10 is down after the send)", r3, "%s %s %s" % [r1, r2, r3])
	# Shift alone, then F10 with Shift held.
	await _send_key(KEY_F10, false)
	_fresh_vote()
	await _send_key(KEY_SHIFT, true)
	_real_tick(seat)
	_check("real keys: Shift alone casts nothing", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	await _send_key(KEY_F10, true)
	_real_tick(seat)
	_check("real keys: F10 pressed with Shift held casts yes", int(sf.human_vote[1]) == 1, str(sf.human_vote))
	# Shift alone again, then Delete with Shift held.
	await _send_key(KEY_F10, false)
	await _send_key(KEY_SHIFT, false)
	_fresh_vote()
	await _send_key(KEY_SHIFT, true)
	_real_tick(seat)
	_check("real keys: Shift alone casts nothing (before Delete)", int(sf.human_vote[1]) == 0, str(sf.human_vote))
	await _send_key(KEY_DELETE, true)
	_real_tick(seat)
	_check("real keys: Delete pressed with Shift held casts no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# The end: every key up, the hook, the probe and the seat back.
	for code: Key in [KEY_F10, KEY_DELETE, KEY_SHIFT]:
		Input.parse_input_event(_key_event(code, false))
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame
	var left := Input.is_physical_key_pressed(KEY_F10) or Input.is_physical_key_pressed(KEY_DELETE) or Input.is_physical_key_pressed(KEY_SHIFT)
	_check("real keys: no key is left down", not left)
	if hook_at >= 0:
		world.tick_hooks.insert(mini(hook_at, world.tick_hooks.size()), sf._tick)
	sf.key_probe = saved_probe
	_clean()
	world.human = saved_human


## Is `word` one of the keys the key map's list of rule-variant keys gives the
## surrender vote?
func _variant_key_listed(word: String) -> bool:
	for v: Dictionary in KeyMapClash.VARIANT_KEYS:
		if String(v["variant"]) == "surrender" and String(v["key"]) == word:
			return true
	return false


## The Yes and No buttons.
func _prompt() -> void:
	_clean()
	var saved_human := world.human
	world.human = _profile_of(1)
	var prompt := SurrenderPrompt.new()
	prompt.setup(sf)
	prompt.refresh()
	_check("the prompt is hidden with no vote open", not prompt.visible)
	_check("the prompt has a Yes and a No button", prompt.yes_button != null and prompt.no_button != null)
	sf._open(0)
	prompt.refresh()
	_check("the prompt is hidden while only the other team votes", not prompt.visible)
	sf._open(1)
	prompt.refresh()
	_check("the prompt is shown while the human's own team votes", prompt.visible)
	prompt.yes_button.pressed.emit()
	_check("pressing Yes casts a yes", int(sf.human_vote[1]) == 1, str(sf.human_vote))
	prompt.no_button.pressed.emit()
	_check("pressing No casts a no", int(sf.human_vote[1]) == -1, str(sf.human_vote))
	# The match ends while the vote is open (a mothership falls): the prompt hides.
	_check("the vote is still open before the match ends", sf.human_vote_open() and prompt.visible)
	world.phase = "end"
	prompt.refresh()
	_check("the prompt is hidden once the match is over, with the vote still open", not prompt.visible and sf.human_vote_open())
	world.phase = "play"
	prompt.refresh()
	_check("the prompt is shown again with the match on (the phase hid it)", prompt.visible)
	# And the module closes the open votes when it hears the match is over: the
	# handler is called by hand here (the signal's own emit would also run the game's
	# end handler and print a false summary); the connection is tested in _endings.
	sf._open(0)
	sf._open(1)
	_check("both teams have a vote open before the handler", float(sf.vote_end[0]) > 0.0 and float(sf.vote_end[1]) > 0.0, str(sf.vote_end))
	sf._on_match_over(0, "a mothership fell")
	_check("the match-over handler closes every open vote", float(sf.vote_end[0]) == 0.0 and float(sf.vote_end[1]) == 0.0 and not sf.human_vote_open(), str(sf.vote_end))
	prompt.refresh()
	_check("the prompt is hidden once the votes are closed", not prompt.visible)
	prompt.free()
	_clean()
	world.human = saved_human


## The two cases that end the match.
func _endings() -> void:
	_clean()
	world.time = 3000.0
	world.human = null
	# Five yes votes of six pass; the match ends as a loss for the voting team.
	sf._open(1)
	sf.ai_yes[1] = 5
	sf._open(0)
	sf._count(1)
	# Only the module's match_over handler, reached through the signal, closes team
	# 0's vote: _count(1) closes team 1's own.
	_check("a passed vote closes the other team's open vote (the match_over connection)", float(sf.vote_end[0]) == 0.0, str(sf.vote_end))
	_check("five yes votes of six end the match", world.phase == "end", world.phase)
	_check("the other team wins", world.winner == 0, str(world.winner))
	# A human's no cannot stop five computer seats.
	world.phase = "play"
	world.winner = -1
	_clean()
	world.time = 4000.0
	world.human = _profile_of(1)
	sf._open(1)
	sf.ai_yes[1] = 5
	sf.cast_vote(1, false)
	sf._count(1)
	_check("a human no cannot stop five computer yes votes of six", world.phase == "end" and world.winner == 0, "%s %d" % [world.phase, world.winner])
	world.human = null

	# A human's yes is one of the seats counted: four computer seats fail alone and
	# pass with the human's yes (the human's no or no answer adds nothing).
	world.phase = "play"
	world.winner = -1
	_clean()
	world.time = 5000.0
	world.human = _profile_of(1)
	sf._open(1)
	sf.ai_yes[1] = 4
	sf._count(1)
	_check("four computer yes votes and no human answer fail", world.phase == "play", world.phase)
	_clean()
	world.time = 5100.0
	sf._open(1)
	sf.ai_yes[1] = 4
	sf.cast_vote(1, false)
	sf._count(1)
	_check("four computer yes votes and a human no fail", world.phase == "play", world.phase)
	_clean()
	world.time = 5200.0
	sf._open(1)
	sf.ai_yes[1] = 4
	sf.cast_vote(1, true)
	sf._count(1)
	_check("four computer yes votes and a human yes pass (the human's yes is counted)", world.phase == "end" and world.winner == 0, "%s %d" % [world.phase, world.winner])
	world.human = null