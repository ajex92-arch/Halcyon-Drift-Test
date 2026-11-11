extends Node
## WHAT THIS IS: the "difficulty check": a quick test that the difficulty setting
## multiplies the right money by the right number, and nothing else. It builds
## the match, makes a few payments straight through the game's own gates and
## compares what each team receives with what the chosen level promises.
##
## HOW IT WORKS: setup() looks at who is human and at Game.difficulty, and works
## out the multiplier each team should have (its own table, written out here
## again so the check does not copy the game's numbers): the chosen level's number
## for the team without the human, exactly 1.0 for the human's team, and 1.0 for
## both teams when nobody is human. For each team it then checks that the team's
## notebook (TeamState.income_mult) and every pilot (PilotProfile.income_mult)
## hold that number, and pays 100 credits through each gate and compares the
## change with 100 times the multiplier: TeamState.earn() into the treasury,
## PilotProfile.earn() (also the amount sent on Events.credits_earned) and
## PilotProfile.earn_quietly() to a pilot, an ore delivery of 1,000 ore
## (Economy.deliver_ore(): 600 into the treasury, 400 among the pilots), and one
## second of the steady trickle (Economy.passive_income()). It also checks that
## money which is not income is not scaled: a pilot buys the cheapest gear item
## and sells it back, and must end with exactly what the sale rules say. It
## prints a PASS or FAIL line for each check and ends with
## "difficulty_check: N failures" (0 = all good), then quits.
## With --settings-check=<text> it also checks the start screen's picker and the
## remembered pick: it builds the start screen, presses a level's button, checks
## the game's setting, the texts and the settings file, then builds the screen
## again as a new run would (the pick must come back), and checks that
## --difficulty beats the remembered pick and that a damaged file is ignored.
## That writes the settings file, so <text> must be part of the name of the user
## data folder (a scratch one: start the game with the environment variable
## APPDATA pointing at an empty folder whose name holds the text); with any other
## folder this part only reports a failure and writes nothing.
## It also checks the difficulty tag (T-124). Always: the words of each level (the
## top bar's short tag, the scoreboard heading's end and the end screen's line, written
## out here again), the Custom reading of a number that is none of the five, and the
## How to play entry. With --force-hud, on the screens of the match it built: the top
## bar's tag (its words, its hover sentence, its place under the wave line and above the
## test tags, size 12, grey, the pass filter), the scoreboard's enemy heading and the end
## screen's line all name the level of the ENEMY TEAM's income_mult, also after
## Game.difficulty is set to another level (what a loaded saved game meets; saved games,
## T-113, are not in the base this was written on), and all go away with a second human
## (OrderQueue.human_seats_override = 2); with no human seat none of them names a level.
## In a window (not headless), --shots=<folder> also saves two pictures of the tag's hover
## sentence there (hover.png, hover_card.png) once the checks are done.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --difficulty=hard --test=difficulty_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --difficulty=extreme --test=difficulty_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --team=vhorr --difficulty=hard --test=difficulty_check
## The first has a human pilot (so the enemy team is scaled), the second has no
## human (so nothing is scaled), the third also reads the tag on the screens. Try
## every level, with --role=pilot and --role=admiral, and with --all-ai.
##
## WHO USES IT: main.gd loads it for --test=difficulty_check. It changes the
## credits of the match it builds, so it is only for this check.

## The enemy income multiplier of each level, as the check expects it.
const EXPECTED := {"easy": 0.75, "medium": 1.0, "hard": 1.25, "very_hard": 1.5, "extreme": 2.0}
## The top bar's tag of each level, written out here again (not copied from Difficulty).
const TAGS := {"easy": "Easy", "medium": "Medium", "hard": "Hard", "very_hard": "Very hard", "extreme": "Extreme"}
## What the scoreboard's enemy heading ends with, after "  ·  ".
const HEADS := {"easy": "Easy: earns 75%", "medium": "Medium: normal income", "hard": "Hard: earns 125%", "very_hard": "Very hard: earns 150%", "extreme": "Extreme: earns 200%"}
## The end screen's difficulty line.
const LINES := {"easy": "Difficulty: Easy. The enemy earned 75% of its normal income.", "medium": "Difficulty: Medium. The enemy earned its normal income.", "hard": "Difficulty: Hard. The enemy earned 125% of its normal income.", "very_hard": "Difficulty: Very hard. The enemy earned 150% of its normal income.", "extreme": "Difficulty: Extreme. The enemy earned 200% of its normal income."}
## The credits paid through each gate.
const AMOUNT := 100.0
## The ore of the test delivery (1 ore is worth 1 credit).
const ORE := 1000.0
## Two sums closer than this many credits count as equal (float noise).
const TOLERANCE := 1e-9

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## The amounts of the credits_earned messages the check itself caused.
var _heard: Array = []


## main.gd calls this once, right after the World is built. Run every check and
## quit.
func setup(w: World) -> void:
	world = w
	Events.credits_earned.connect(_on_credits)
	var human_team := -1
	if world.human != null:
		human_team = world.human.team
	var enemy_mult := float(EXPECTED.get(Game.difficulty, 1.0)) if human_team >= 0 else 1.0
	print("difficulty_check: level=%s human_team=%d, the enemy team should earn x%.2f" % [Game.difficulty, human_team, enemy_mult])
	for t in 2:
		var mult := enemy_mult if (human_team >= 0 and t != human_team) else 1.0
		_check_team(t, mult)
	_check_not_income()
	_check_tag_texts()
	if Game.opt("force-hud", false):
		_check_screens()
	var marker := str(Game.opt("settings-check", ""))
	if marker != "":
		_check_settings(marker)
	print("difficulty_check: %d failures" % fails)
	var shots := str(Game.opt("shots", ""))
	if shots != "" and DisplayServer.get_name() != "headless":
		await _hover_shots(shots)
	get_tree().quit()


## A pilot was paid: keep the amount of the check's own payments.
func _on_credits(_profile: RefCounted, amount: float, reason: String) -> void:
	if reason == "difficulty_check":
		_heard.append(amount)


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Check that `got` is `want` (within TOLERANCE), as the check `what`.
func _near(what: String, got: float, want: float) -> void:
	_check(what, absf(got - want) <= TOLERANCE, "got %.9f, wanted %.9f" % [got, want])


## The credits of all the pilots of team `t`.
func _pilot_credits(t: int) -> float:
	var sum := 0.0
	for p: PilotProfile in world.profiles:
		if p.team == t:
			sum += p.credits
	return sum


## Check team `t`, which should have the multiplier `mult`: the numbers it
## holds, and what each gate pays.
func _check_team(t: int, mult: float) -> void:
	var ts: TeamState = world.teams[t]
	var tag := "team %d (x%.2f)" % [t, mult]
	# Step 1: the multiplier is held by the team and by every one of its pilots.
	_near(tag + " TeamState.income_mult", ts.income_mult, mult)
	var pilots: Array = []
	for p: PilotProfile in world.profiles:
		if p.team == t:
			pilots.append(p)
			if absf(p.income_mult - mult) > TOLERANCE:
				_check(tag + " pilot " + p.callsign + " income_mult", false, "got %.9f, wanted %.9f" % [p.income_mult, mult])
	# Step 2: the treasury gate.
	var before := ts.treasury
	ts.earn(AMOUNT)
	_near(tag + " TeamState.earn(100) into the treasury", ts.treasury - before, AMOUNT * mult)
	# Step 3: the two pilot gates: credits, earned, and the message.
	var p0: PilotProfile = pilots[0]
	var c0 := p0.credits
	var e0 := p0.earned
	_heard.clear()
	p0.earn(AMOUNT, "difficulty_check")
	_near(tag + " PilotProfile.earn(100) credits", p0.credits - c0, AMOUNT * mult)
	_near(tag + " PilotProfile.earn(100) earned", p0.earned - e0, AMOUNT * mult)
	_check(tag + " PilotProfile.earn(100) message", _heard.size() == 1 and absf(float(_heard[0]) - AMOUNT * mult) <= TOLERANCE, "heard %s" % str(_heard))
	c0 = p0.credits
	e0 = p0.earned
	_heard.clear()
	p0.earn_quietly(AMOUNT)
	_near(tag + " PilotProfile.earn_quietly(100) credits", p0.credits - c0, AMOUNT * mult)
	_near(tag + " PilotProfile.earn_quietly(100) earned", p0.earned - e0, AMOUNT * mult)
	_check(tag + " PilotProfile.earn_quietly(100) sends no message", _heard.is_empty())
	# Step 4: an ore delivery: 60% into the treasury, 40% among the pilots.
	before = ts.treasury
	var purse := _pilot_credits(t)
	Economy.deliver_ore(world, t, ORE, null)
	_near(tag + " ore delivery, treasury share", ts.treasury - before, ORE * float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE)) * mult)
	_near(tag + " ore delivery, pilots' share", _pilot_credits(t) - purse, ORE * (1.0 - float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE))) * mult)
	# Step 5: one second of the steady trickle, for each pilot of the team.
	var each: Array = []
	for p: PilotProfile in pilots:
		each.append(p.credits)
	Economy.passive_income(world, 1.0)
	var rate := float(Rules.tune("passive_income", Rules.PASSIVE_INCOME))
	var worst := 0.0
	for i in pilots.size():
		var p: PilotProfile = pilots[i]
		worst = maxf(worst, absf(p.credits - float(each[i]) - (rate + p.gear_stats().g("income")) * mult))
	_check(tag + " trickle, one second, every pilot", worst <= TOLERANCE, "largest error %.12f" % worst)


## The texts of the difficulty tag (T-124), with no screen: every level's short tag,
## scoreboard heading end and end screen line are the words written out above, a
## multiplier that is none of the five reads Custom, and the How to play entry
## "Difficulty" lists the five levels (made from Difficulty's data).
func _check_tag_texts() -> void:
	for level: String in EXPECTED:
		var mult: float = EXPECTED[level]
		var tag := "tag text, " + level
		_check(tag + ": short_tag(level) and short_tag_for(multiplier) read '%s'" % TAGS[level], Difficulty.short_tag(level) == TAGS[level] and Difficulty.short_tag_for(mult) == TAGS[level], "'%s' / '%s'" % [Difficulty.short_tag(level), Difficulty.short_tag_for(mult)])
		_check(tag + ": the scoreboard heading ends '%s'" % HEADS[level], Difficulty.heading_tag(mult) == HEADS[level], Difficulty.heading_tag(mult))
		_check(tag + ": the end screen line reads '%s'" % LINES[level], Difficulty.result_line(mult) == LINES[level], Difficulty.result_line(mult))
		_check(tag + ": the multiplier finds its level and the hover sentence is blurb()", Difficulty.level_of(mult) == level and Difficulty.blurb_for(mult) == Difficulty.blurb(level), "level_of %s" % Difficulty.level_of(mult))
	_check("tag text: a multiplier that is none of the five reads Custom", Difficulty.level_of(1.4) == "" and Difficulty.short_tag_for(1.4) == "Custom" and Difficulty.heading_tag(1.4) == "Custom: earns 140%" and Difficulty.result_line(1.4) == "Difficulty: Custom. The enemy earned 140% of its normal income." and Difficulty.blurb_for(1.4).begins_with("Custom: the enemy earns 140%"), Difficulty.short_tag_for(1.4))
	var help := Difficulty.help_text()
	var listed := true
	for part in ["Easy 75%", "Medium 100%", "Hard 125%", "Very hard 150%", "Extreme 200%", "Only the enemy's income changes"]:
		listed = listed and help.contains(part)
	_check("tag text: help_text() lists the five levels and says only the enemy's income changes", listed, help)
	var panel := (load("res://scenes/ui/help_panel.tscn") as PackedScene).instantiate() as HelpPanel
	add_child(panel)
	var entry := ""
	for row in panel._body.get_children():
		if row.get_child_count() == 2 and (row.get_child(0) as Label).text == "Difficulty":
			entry = (row.get_child(1) as Label).text
	_check("How to play: the match page has the Difficulty entry, made from Difficulty's data", entry == help, entry)
	panel.free()


## The difficulty tag on the screens (needs --force-hud), for the level this run built
## the match with. With a human seat: the top bar's tag, its hover sentence and place,
## the scoreboard's enemy heading and the end screen's line all say the level the
## ENEMY TEAM's income_mult names, also when the picker (Game.difficulty) now holds
## another level (what a loaded saved game meets; saved games, T-113, are not in this
## base), and all hide when two humans sit in the match. With no human seat nothing
## names a level.
func _check_screens() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("the HUD exists for the tag check", false, "no Hud node (use --force-hud)")
		return
	var level := Game.difficulty
	var seat := world.human != null and world.human_role != "spectator"
	var enemy := Rules.enemy_of(world.human_team)
	var middle := hud.top_bar.get_node("Row/Middle")
	var diff: Label = middle.get_node("DiffTag")
	var admiral := world.human_role == "admiral"
	# The Admiral reads the level as a word in the strip at the top right; everyone else under the wave line in the top bar.
	var tag_ctl: Control = hud.command_view.strip._b["diff"] if admiral else diff
	var tag := "%s %s:" % [world.human_role, level]
	# Step 1: with the picker on the level of the match, then on another level.
	var other := "easy" if level != "easy" else "extreme"
	for picker: String in [level, other]:
		Game.difficulty = picker
		_refresh_tags(hud)
		var sb := (load("res://scenes/ui/scoreboard.tscn") as PackedScene).instantiate() as Scoreboard
		add_child(sb)
		sb.setup(world)
		var es := _end_screen()
		var line: Label = es.get_node("Center/Card/Col/Difficulty")
		var where := "picker on %s" % picker
		if seat:
			_near("%s the enemy team's income_mult is the level's number (%s)" % [tag, where], world.teams[enemy].income_mult, float(EXPECTED[level]))
			_check("%s the tag reads '%s' (%s)" % [tag, TAGS[level], where], tag_ctl.visible and str(tag_ctl.get("text")) == TAGS[level] and (not admiral or not diff.visible), "visible %s, '%s'" % [str(tag_ctl.visible), str(tag_ctl.get("text"))])
			_check("%s the tag's hover is blurb(): %s" % [tag, where], tag_ctl.tooltip_text == Difficulty.blurb(level) and tag_ctl.tooltip_text.begins_with(String(Difficulty.LABELS[level]) + ":"), tag_ctl.tooltip_text)
			_check("%s the enemy team's heading ends '  ·  %s' and the other team's has none (%s)" % [tag, HEADS[level], where], sb._heads[enemy].text.ends_with("  ·  " + HEADS[level]) and not sb._heads[world.human_team].text.contains(": earns") and not sb._heads[world.human_team].text.contains("normal income"), "'%s' / '%s'" % [sb._heads[enemy].text, sb._heads[world.human_team].text])
			_check("%s the end screen's line reads '%s' (%s)" % [tag, LINES[level], where], line.visible and line.text == LINES[level], "visible %s, '%s'" % [str(line.visible), line.text])
		else:
			_check("%s no human seat: no tag, no heading level, no end screen line (%s)" % [tag, where], not tag_ctl.visible and not sb._heads[0].text.contains(": earns") and not sb._heads[1].text.contains(": earns") and not sb._heads[0].text.contains("normal income") and not sb._heads[1].text.contains("normal income") and not line.visible, "tag visible %s '%s', line visible %s" % [str(tag_ctl.visible), str(tag_ctl.get("text")), str(line.visible)])
		sb.free()
		es.free()
	Game.difficulty = level
	# Step 2: the tag's place and looks (a human seat): under the wave line and above the test tags, size 12, grey, and it takes the pointer with the pass filter.
	if seat:
		var wave: Label = middle.get_node("Wave")
		var tags: Label = middle.get_node("Tags")
		if admiral:
			_check("%s the top bar has no tag (the strip has the word) and the strip's word is not under the box" % tag, not diff.visible and tag_ctl.visible, "tag visible %s" % str(diff.visible))
		else:
			_check("%s the tag sits between the wave line and the test tags" % tag, diff.get_index() == wave.get_index() + 1 and tags.get_index() == diff.get_index() + 1, "index %d, wave %d, tags %d" % [diff.get_index(), wave.get_index(), tags.get_index()])
		_check("%s the tag is size 12, grey (MIST) and takes the pointer with the pass filter" % tag, diff.get_theme_font_size("font_size") == 12 and diff.get_theme_color("font_color") == Palette.MIST and diff.mouse_filter == Control.MOUSE_FILTER_PASS and hud.top_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE, "size %d, colour %s, filter %d" % [diff.get_theme_font_size("font_size"), str(diff.get_theme_color("font_color")), diff.mouse_filter])
		# Step 3: humans on both teams (an online match): nothing names a level.
		world.orders.human_seats_override = 2
		_refresh_tags(hud)
		var sb2 := (load("res://scenes/ui/scoreboard.tscn") as PackedScene).instantiate() as Scoreboard
		add_child(sb2)
		sb2.setup(world)
		var es2 := _end_screen()
		_check("%s humans on both teams: no tag, no heading level, no end screen line" % tag, not diff.visible and not tag_ctl.visible and not sb2._heads[enemy].text.contains(": earns") and not sb2._heads[enemy].text.contains("normal income") and not (es2.get_node("Center/Card/Col/Difficulty") as Label).visible, "tag visible %s" % str(tag_ctl.visible))
		sb2.free()
		es2.free()
		world.orders.human_seats_override = -1
		_refresh_tags(hud)
		# Step 4: the bar is one line taller with the tag; the kill feed starts under it in a window 1280 wide, where
		# the two share ground, and keeps its own place in one 1920 wide, where they do not (HudLayout._place_feed()).
		var feed_tops := {}
		for win: Vector2 in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
			hud.layout._place_top_bar(win)
			hud.layout._place_feed(win)
			feed_tops[int(win.x)] = hud.feed.offset_top
		var bar_bottom: float = hud.top_bar.offset_top + hud.top_bar.get_combined_minimum_size().y
		# The narrower bar may no longer reach over the feed's ground at 1280 wide; then the feed keeps its own place (HudLayout._place_feed()).
		var shares: bool = 640.0 + hud.top_bar.offset_left + hud.top_bar.get_combined_minimum_size().x * 0.5 + HudLayout.GAP > 1280.0 + hud.feed.offset_right - hud.feed.get_combined_minimum_size().x
		_check("%s the kill feed starts under the top bar at 1280 wide (%d, the bar ends at %d) and at %d at 1920 wide (%d)" % [tag, int(feed_tops[1280]), int(bar_bottom), int(HudLayout.FEED_TOP), int(feed_tops[1920])], (float(feed_tops[1280]) >= bar_bottom or not shares) and is_equal_approx(float(feed_tops[1920]), HudLayout.FEED_TOP))
		hud.layout.apply()


## Rewrite the difficulty tag on both places it can stand: the top bar and, for an Admiral, the strip at the top right.
func _refresh_tags(hud: Hud) -> void:
	hud.top_bar.refresh(world)
	if hud.command_view != null and world.human_role == "admiral":
		hud.command_view.strip.refresh()


## Only in a window, with --shots=<folder>: the pictures of the tag's hover sentence, in the
## folder. The pointer is moved over the tag (hover.png: the window as the engine's tooltip
## draws it, if it shows in a parked window) and a stand-in card with the same words in the
## same tooltip look is put under the tag (hover_card.png), so the sentence is seen either way.
func _hover_shots(dir: String) -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var diff: Label = hud.top_bar.get_node("Row/Middle/DiffTag")
	await get_tree().create_timer(1.5).timeout
	var at := diff.get_global_rect().get_center()
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("hover.png"))
	var card := PanelContainer.new()
	card.theme_type_variation = &"TooltipPanel"
	card.add_child(UiKit.label(diff.tooltip_text, 13, Palette.ICE, true))
	card.custom_minimum_size = Vector2(330.0, 0.0)
	hud.add_child(card)
	card.position = Vector2(diff.get_global_rect().position.x, diff.get_global_rect().end.y + 26.0)
	await get_tree().create_timer(0.3).timeout
	await _save_shot(dir.path_join("hover_card.png"))


## Save the window's picture as `path` (after the frame is drawn).
func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## An end screen for the running match, added to the check's own node so its
## _ready() fills it in (the winner does not matter here).
func _end_screen() -> EndScreen:
	var es := (load("res://scenes/ui/end_screen.tscn") as PackedScene).instantiate() as EndScreen
	es.setup(world, 0, "The check ended the match.")
	add_child(es)
	return es


## Make a start screen as a new run would: the setting is open again, then the
## scene is added to the tree (which builds the rows).
func _new_screen() -> StartScreen:
	Game.difficulty = Difficulty.DEFAULT
	Game.difficulty_error = ""
	Game._difficulty_open = true
	var screen: StartScreen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	return screen


## The level whose button is pressed on start screen `screen` ("" if none, or
## more than one).
func _pressed_level(screen: StartScreen) -> String:
	var found := ""
	for lv: String in screen._difficulty_buttons:
		if (screen._difficulty_buttons[lv] as Button).button_pressed:
			found = lv if found == "" else "more than one"
	return found


## The start screen's picker and the remembered pick (see the top of the file).
## `marker` must be part of the user data folder's name, so the settings file
## written here is a scratch one.
func _check_settings(marker: String) -> void:
	var dir := OS.get_user_data_dir()
	if not dir.contains(marker):
		_check("settings check: the user data folder holds \"%s\"" % marker, false, "it is %s, so nothing was written" % dir)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	# Step 1: nothing remembered yet: Medium is pressed, and the text names it.
	var screen := _new_screen()
	_check("settings: Medium is pressed when nothing is remembered", _pressed_level(screen) == "medium", "pressed: " + _pressed_level(screen))
	# Step 2: press Hard: the setting, the text and the file follow.
	(screen._difficulty_buttons["hard"] as Button).pressed.emit()
	_check("settings: pressing Hard sets Game.difficulty", Game.difficulty == "hard", Game.difficulty)
	_check("settings: Hard is the pressed button", _pressed_level(screen) == "hard", "pressed: " + _pressed_level(screen))
	_check("settings: the text names Hard, 125% and single player only", screen._difficulty_blurb.text.begins_with("Hard:") and screen._difficulty_blurb.text.contains("125%") and screen._difficulty_blurb.text.contains("single player only"), screen._difficulty_blurb.text)
	var cfg := ConfigFile.new()
	_check("settings: the file was written", cfg.load(Game.SETTINGS_FILE) == OK and str(cfg.get_value("game", "difficulty", "")) == "hard")
	screen.free()
	# Step 3: a new run: the pick comes back.
	screen = _new_screen()
	_check("settings: the next run shows Hard, as remembered", Game.difficulty == "hard" and _pressed_level(screen) == "hard", "setting %s, pressed: %s" % [Game.difficulty, _pressed_level(screen)])
	screen.free()
	# Step 4: --difficulty beats the remembered pick (the game settles it at launch, before the screen).
	Game.difficulty = "easy"
	Game._difficulty_open = false
	screen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	_check("settings: a launch option beats the remembered pick", Game.difficulty == "easy" and _pressed_level(screen) == "easy", "setting %s, pressed: %s" % [Game.difficulty, _pressed_level(screen)])
	screen.free()
	# Step 5: a damaged file is ignored.
	cfg.set_value("game", "difficulty", "banana")
	cfg.save(Game.SETTINGS_FILE)
	screen = _new_screen()
	_check("settings: a word that is not a level is ignored", Game.difficulty == "medium" and _pressed_level(screen) == "medium", "setting %s" % Game.difficulty)
	screen.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))


## Money that is not income must not be scaled: a pilot of each team buys the
## cheapest gear item and sells it back, and ends with exactly what is left
## after paying the price and getting Rules.SELL_BACK of it back.
func _check_not_income() -> void:
	var cheapest := ""
	for id: String in Items.ITEMS:
		if cheapest == "" or float(Items.ITEMS[id]["price"]) < float(Items.ITEMS[cheapest]["price"]):
			cheapest = id
	var price := float(Items.ITEMS[cheapest]["price"])
	for t in 2:
		var p: PilotProfile = null
		for q: PilotProfile in world.profiles:
			if q.team == t and q.state != "dead":
				p = q
				break
		p.credits = 5000.0
		var err := p.buy_gear(cheapest)
		var slot := -1
		for i in p.inventory.size():
			if not (p.inventory[i] as Dictionary).is_empty() and (p.inventory[i] as Dictionary)["id"] == cheapest:
				slot = i
		if err != "" or slot < 0:
			_check("team %d buys %s" % [t, cheapest], false, err)
			continue
		p.sell_slot(slot)
		_near("team %d buys and sells back %s: the sale is not scaled" % [t, cheapest], p.credits, 5000.0 - price + price * Rules.SELL_BACK)
