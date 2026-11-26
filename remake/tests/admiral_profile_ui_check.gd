extends Node
## WHAT THIS IS: the check of the start screen's COMPUTER row (RT5 build U): the buttons that choose the
## computer Admiral's profile, the refusal of a name that is not a profile, the test toggle "Show the
## computer's memory (test)", and the top bar's tags for both.
##
## HOW IT WORKS: setup() builds the row alone (StartScreen._build_computer() on a StartScreen that is not in
## the scene, into a column of its own), so the whole start screen is never made and the player's settings
## file is neither read nor written. It presses the buttons as a click does (their `pressed` signal) and
## reads Game.options, Game.admiral_profile_error and the record a match would give each team
## (AdmiralProfile.for_team). A source scan proves that the two Game functions do not touch the settings
## file. With --force-hud it also looks at the top bar's tags. Everything it changes in Game is put back.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=admiral_profile_ui_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what> <detail>", then
## "admiral_profile_ui_check: N failures" last. 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=admiral_profile_ui_check.

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Runs every check, prints the result line and quits.
func setup(w: World) -> void:
	world = w
	var had_option: bool = Game.options.has("admiral-profile")
	var old_option: Variant = Game.options.get("admiral-profile")
	var old_error: String = Game.admiral_profile_error
	var old_memory: bool = Game.show_ai_memory
	Game.options.erase("admiral-profile")
	Game.admiral_profile_error = ""
	Game.show_ai_memory = false
	_check_row()
	_check_choice_words()
	_check_sources()
	if Game.opt("force-hud", false):
		_check_tags()
	if had_option:
		Game.options["admiral-profile"] = old_option
	else:
		Game.options.erase("admiral-profile")
	Game.admiral_profile_error = old_error
	Game.show_ai_memory = old_memory
	print("admiral_profile_ui_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## The profile each team's computer Admiral would play with the options as they are now ("standard/standard").
func _played() -> String:
	return "%s/%s" % [AdmiralProfile.for_team(0, Game.options).profile_name, AdmiralProfile.for_team(1, Game.options).profile_name]


## The row itself: the buttons, a pick, the refusal, and the memory toggle.
func _check_row() -> void:
	var screen := StartScreen.new()
	var col := VBoxContainer.new()
	screen._build_computer(col, 0)
	var names: Array = screen._profile_buttons.keys()
	_check("one button per profile of the table", names == AdmiralProfileData.PROFILES, str(names))
	_check("the row and its error line are in the column", col.get_child_count() == 2 and col.get_child(1) == screen._profile_note, "%d children" % col.get_child_count())
	# Step 1: nothing chosen: Standard shows pressed, no option, no error line.
	_check("at the start Standard is pressed and no option is set", _pressed(screen) == ["standard"] and not Game.options.has("admiral-profile") and not screen._profile_note.visible, str(_pressed(screen)))
	# Step 2: each button sets the option for both teams; Standard takes it away again.
	for p_name: String in ["v0", "weak"]:
		(screen._profile_buttons[p_name] as Button).pressed.emit()
		_check("the %s button sets the option" % p_name, str(Game.options.get("admiral-profile", "")) == "both:%s" % p_name and Game.admiral_profile_error == "", str(Game.options.get("admiral-profile", "<none>")))
		_check("the %s button shows pressed, alone" % p_name, _pressed(screen) == [p_name], str(_pressed(screen)))
		_check("both computer Admirals would play %s" % p_name, _played() == "%s/%s" % [p_name, p_name], _played())
	# Step 3: a name that is not a profile is refused: the option stays, the error text shows, no button is pressed.
	var ok: bool = Game.choose_admiral_profile("banana")
	screen._show_computer()
	_check("a bad name is refused", not ok and str(Game.options.get("admiral-profile", "")) == "both:weak" and _played() == "weak/weak", str(Game.options.get("admiral-profile", "<none>")))
	_check("the refusal is Game.admiral_profile_error and names the bad name", Game.admiral_profile_error.contains("banana") and Game.admiral_profile_error == AdmiralProfile.option_error({"admiral-profile": "both:banana"}), Game.admiral_profile_error)
	_check("the row shows the error text", screen._profile_note.visible and screen._profile_note.text.contains(Game.admiral_profile_error), screen._profile_note.text)
	_check("no profile button is pressed while the error stands", _pressed(screen).is_empty(), str(_pressed(screen)))
	_check("an empty name is refused too", not Game.choose_admiral_profile("") and Game.admiral_profile_error != "", Game.admiral_profile_error)
	# Step 4: a good pick clears it; Standard leaves no option behind.
	(screen._profile_buttons["standard"] as Button).pressed.emit()
	_check("Standard clears the error and takes the option away", Game.admiral_profile_error == "" and not Game.options.has("admiral-profile") and not screen._profile_note.visible and _pressed(screen) == ["standard"], str(Game.options.get("admiral-profile", "<none>")))
	_check("with Standard both Admirals play the standard profile", _played() == "standard/standard", _played())
	# Step 5: the memory toggle: off, on, off.
	_check("the memory toggle starts off", not Game.show_ai_memory and not screen._memory_button.button_pressed and screen._memory_button.text == "Show the computer's memory (test): off", screen._memory_button.text)
	screen._memory_button.pressed.emit()
	_check("pressing it turns the option on", Game.show_ai_memory and screen._memory_button.button_pressed and screen._memory_button.text == "Show the computer's memory (test): ON", screen._memory_button.text)
	screen._memory_button.pressed.emit()
	_check("pressing it again turns it off", not Game.show_ai_memory and not screen._memory_button.button_pressed, screen._memory_button.text)
	col.free()
	screen.free()


## The names of the profile buttons that show pressed.
func _pressed(screen: StartScreen) -> Array:
	var out: Array = []
	for p_name: String in screen._profile_buttons:
		if (screen._profile_buttons[p_name] as Button).button_pressed:
			out.append(p_name)
	return out


## StartScreen.profile_choice(): the word for the options a launch line can give.
func _check_choice_words() -> void:
	var cases := {"": "standard", "both:v0": "v0", "both:weak": "weak", "both:standard": "standard", "1:weak": "custom", "0:v0;1:weak": "custom", "both:banana": "custom"}
	for text: String in cases:
		var options := {} if text == "" else {"admiral-profile": text}
		var got := StartScreen.profile_choice(options)
		_check("profile_choice('%s')" % text, got == str(cases[text]), got)
	_check("the button words", StartScreen.profile_label("standard") == "Standard" and StartScreen.profile_label("v0") == "V0" and StartScreen.profile_label("weak") == "Weak", StartScreen.profile_label("v0"))


## The source scan: neither Game function names the settings file or the function that writes it.
func _check_sources() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/autoload/game.gd")
	for fn: String in ["choose_admiral_profile", "choose_show_ai_memory"]:
		var from := text.find("\nfunc %s(" % fn)
		var to := text.find("\nfunc ", from + 1)
		var body := text.substr(from, (to - from) if to > from else -1)
		_check("Game.%s() does not touch the settings file" % fn, from >= 0 and not body.contains("_remember") and not body.contains("SETTINGS_FILE") and not body.contains("ConfigFile"), "%d characters" % body.length())


## The top bar's tags (only with --force-hud): AI <PROFILE> while the profile is not the standard one, AI MEMORY
## while the memory toggle is on, neither at the defaults.
func _check_tags() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("the HUD exists for the tag check", false, "no Hud node (use --force-hud)")
		return
	var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
	hud.top_bar.refresh(world)
	_check("no AI tag at the defaults", not tags.text.contains("AI "), "'%s'" % tags.text)
	Game.choose_admiral_profile("v0")
	hud.top_bar.refresh(world)
	_check("the AI V0 tag with the v0 profile", tags.visible and tags.text.contains("AI V0") and not tags.text.contains("AI MEMORY"), "'%s'" % tags.text)
	Game.options["admiral-profile"] = "1:weak"
	hud.top_bar.refresh(world)
	_check("the AI CUSTOM tag with a launch line of its own", tags.text.contains("AI CUSTOM"), "'%s'" % tags.text)
	Game.choose_admiral_profile("standard")
	Game.choose_show_ai_memory(true)
	hud.top_bar.refresh(world)
	_check("the AI MEMORY tag with the memory toggle on", tags.visible and tags.text.contains("AI MEMORY") and not tags.text.contains("AI V0") and not tags.text.contains("AI CUSTOM"), "'%s'" % tags.text)
	Game.choose_show_ai_memory(false)
	hud.top_bar.refresh(world)
	_check("no AI tag once both are back at the defaults", not tags.text.contains("AI "), "'%s'" % tags.text)
