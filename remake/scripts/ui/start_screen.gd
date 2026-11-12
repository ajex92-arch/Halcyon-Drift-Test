class_name StartScreen
extends Control
## WHAT THIS IS: the first screen of the game, where the human picks their
## team (Aurelian or Vhorr) and their seat: command the team as its Admiral,
## or fly as one of its 5 pilots (then an AI admiral commands). The other
## team is all computer. The choice is locked for the whole match.
## DESIGN.md A3.
##
## HOW IT WORKS: the layout is the scene scenes/ui/start_screen.tscn: a
## dark Cover that blocks clicks to the game behind it, and a Scroll area
## with the Card (the "StartLook" box) centred in it: Scroll > Center >
## Card > Col (Tagline, Title, Rules, SeatHeading, Seats, ControlsHeading,
## Controls). Seats holds the two "seat cards" side by side, Admiral and
## Pilot (the "SeatLook" box), each a column of Title, Body and Pick (a big
## button with the same title). Body takes the spare height, so both
## cards' buttons line up. Pressing a Pick button sends `chosen(role)`.
## _ready() gives the screen the game's look (UiKit.make_theme()), and
## _layout() keeps the card at most 980 pixels wide and fits the wrapped
## text to it whenever the window is resized.
## The rules of the match are not chosen here: every match plays the standard
## rules (Game.preset, set from the launch option --preset, which is for tests
## and research). Only when the game was launched with a --preset that was not
## understood (Game.preset_error), _ready() adds one wrapping line under the
## rules text (made in code, not in the scene) that says so and to relaunch the
## game without the option or with a known name, and both seat buttons stay off,
## since no screen can clear the error. A --variant that was not understood
## (Game.variant_error) is shown the same way.
## Below that, _build_difficulty() adds the difficulty row (also made in code):
## the heading DIFFICULTY with one button per level (Difficulty.ORDER: Easy,
## Medium, Hard, Very hard, Extreme) and the chosen level's one-line description,
## which says that the setting changes the enemy's income in single player only.
## A button calls
## Game.choose_difficulty(), which also remembers the pick for the next run. The
## row starts on the level Game holds: the one last picked on this computer
## (Game.use_remembered_difficulty(), called here), Medium the first time, or the
## level the game was launched with (--difficulty).
## At the right end of the same row sits the test option "Unlock everything (test)",
## a toggle (off the first time) that Game.choose_unlock() remembers for the next
## run like the difficulty; --unlock-all turns it on at launch. While it is on, the
## human can buy anything at once and for nothing (UnlockAll). Just left of it sits the
## test toggle "No fog (test)" (FogOff), remembered the same way; --fog-off turns it on at launch.
## Under the difficulty text, a row of its own holds two more test options, toggles that
## Game.choose_test_wing() and Game.choose_cpu_wings() remember like it: "Test wing (3
## wingmen)" (off the first time; a Scout, a Fighter and a Bomber fly with the human pilot) and
## "Computer pilots' wings" (on the first time; every computer pilot gets the same three).
## --test-wing and --cpu-wings set them at launch.
## Below the difficulty row, _build_team() adds the team row (also made in code):
## the heading TEAM with two buttons, Aurelian and Vhorr (each in its team's
## colour), and the chosen team's one-line description. A button calls
## Game.choose_team(), which also remembers the pick for the next run. The row
## starts on the team Game holds: the one last picked on this computer
## (Game.use_remembered_team(), called here), Aurelian the first time, or the team
## the game was launched with (--team). The screen's highlight colour follows
## the pick: _use_team_accent() makes the theme again with Aurelian's amber or
## Vhorr's red (Palette.accent()), so the chosen buttons, the two seat buttons and
## the top line change colour the moment a team button is pressed. (The two team
## buttons keep their own team colours.)
##
## WHO USES IT: main.gd shows it from scenes/ui/start_screen.tscn and
## connects `chosen` to its start(role). The launch line reads
## Game.preset_error; the difficulty row reads Difficulty and calls
## Game.choose_difficulty(); the team row calls Game.choose_team(); the No fog toggle
## calls Game.choose_fog_off() and shows Game.fog_off.

## Sent once the player picks a seat: role is "admiral" or "pilot".
signal chosen(role: String)

## The whole card is drawn at this fraction of its size. Everything in it is laid
## out at full size, and Scroll, which holds the card, is scaled down by this one
## number (see _layout()), so the fonts, gaps, buttons and the card's own size all
## shrink together and the layout keeps its shape.
const CARD_SCALE := 0.75

## The main card (its width follows the window, up to about 1030 pixels).
@onready var _card: PanelContainer = $Scroll/Center/Card
## The wrapped texts that run across the whole card: the rules and the
## controls. A new wrapping label in the scene must be added here (or to
## _seat_texts), or it comes out far too tall (see _layout()).
@onready var _wide_texts: Array[Label] = [$Scroll/Center/Card/Col/Rules, $Scroll/Center/Card/Col/Controls]
## The wrapped texts inside the two seat cards (half the card each).
@onready var _seat_texts: Array[Label] = [$Scroll/Center/Card/Col/Seats/Admiral/Col/Body, $Scroll/Center/Card/Col/Seats/Pilot/Col/Body]
## The line under the rules text that names a launch option that was not
## understood. Null unless Game.preset_error or Game.variant_error is set. Made
## by _build_launch_note().
var _launch_note: Label = null
## The difficulty buttons, by level id (Difficulty.ORDER). Made by
## _build_difficulty().
var _difficulty_buttons := {}
## The chosen level's description, under its buttons.
var _difficulty_blurb: Label = null
## The "Unlock everything (test)" toggle, at the right end of the difficulty row.
## Made by _build_difficulty().
var _unlock_button: Button = null
## The "No fog (test)" toggle, just left of Unlock everything. Made by _build_difficulty().
var _fog_button: Button = null
## The "Test wing (3 wingmen)" toggle, in the row of test options under the difficulty text.
## Made by _build_difficulty().
var _test_wing_button: Button = null
## The "Computer pilots' wings" toggle, next to it. Made by _build_difficulty().
var _cpu_wings_button: Button = null
## The one-line description of each team the human can play for, by team number.
const TEAM_BLURBS := {
	Rules.HALCYON: "Aurelian: you play the amber team and start at its mothership on the left of the map. The computer plays Vhorr.",
	Rules.CINDER: "Vhorr: you play the red team and start at its mothership on the right of the map. The computer plays Aurelian.",
}
## The team buttons, by team number (Rules.HALCYON, Rules.CINDER). Made by
## _build_team().
var _team_buttons := {}
## The chosen team's description, under its buttons.
var _team_blurb: Label = null


## Called once when the node joins the scene: take up the difficulty, the team, the
## Unlock everything and No fog choices, the two wing switches and the player's own keys last made on this computer
## (Game.use_remembered_keys()), give the screen the
## game's look in the chosen team's highlight colour, darken the cover, make each
## seat's button send its role, add the launch line, the difficulty row and the
## team row, then fit everything to the window (now and on every resize).
func _ready() -> void:
	Game.use_remembered_difficulty()
	Game.use_remembered_team()
	Game.use_remembered_unlock()
	Game.use_remembered_fog_off()
	Game.use_remembered_wings()
	Game.use_remembered_keys()
	_use_team_accent()
	$Cover.color = Palette.with_alpha(Palette.VOID, 0.82)
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.pressed.connect(func() -> void: chosen.emit("admiral"))
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.pressed.connect(func() -> void: chosen.emit("pilot"))
	_build_launch_note()
	_build_difficulty()
	_build_team()
	resized.connect(_layout)
	_layout()


## Give the screen the game's look in the highlight colour of the team the human
## has chosen (Game.human_team): amber for Aurelian, red for Vhorr
## (Palette.accent()). The theme is made again, and every control under the screen
## takes the new one at once: the chosen difficulty, Unlock and No fog buttons, the two
## seat buttons and the top line. The launch line has a colour of its own, which
## is set by hand. Runs when the screen is made and whenever a team button is
## pressed.
func _use_team_accent() -> void:
	UiKit.set_accent_team(Game.human_team)
	theme = UiKit.make_theme()
	if _launch_note != null:
		_launch_note.add_theme_color_override("font_color", UiKit.accent())


## Add the launch line right under the rules text, but only when the game was
## launched with a --preset or a --variant that was not understood
## (Game.preset_error, Game.variant_error): the match would refuse to start and
## no screen picks other rules, so the line says to relaunch the game without
## the option or with a known name, and both seat buttons stay off
## (_refresh_seats()). Otherwise nothing is added. The line is a wrapping
## label, so it joins _wide_texts.
func _build_launch_note() -> void:
	if Game.preset_error == "" and Game.variant_error == "":
		return
	var col: VBoxContainer = $Scroll/Center/Card/Col
	var text := ""
	if Game.preset_error != "":
		text = "The launch option --preset was not understood: %s. Relaunch the game without it, or with one of those names. " % Game.preset_error
	if Game.variant_error != "":
		text += "The launch option --variant was not understood: %s. Relaunch the game without it, or with names the game knows. " % Game.variant_error
	_launch_note = UiKit.label(text + "The seat buttons stay off until you do.", 13, UiKit.accent(), true)
	col.add_child(_launch_note)
	col.move_child(_launch_note, $Scroll/Center/Card/Col/Rules.get_index() + 1)
	_wide_texts.append(_launch_note)


## Add the difficulty row right under the rules text (and the launch line,
## when it shows): a row with the heading DIFFICULTY and one button per level
## (Difficulty.ORDER), then the chosen level's description (a wrapping label,
## so it joins _wide_texts).
func _build_difficulty() -> void:
	# Step 1: the row (its heading first, then the buttons) and the description
	# go in the card's column, in that order, just below the rules text (below
	# the launch line when there is one). The heading shares the row with the
	# buttons and the text is one line, so the row takes little height and the
	# two seat buttons below it stay in view on a 1080p screen.
	var col: VBoxContainer = $Scroll/Center/Card/Col
	var above: Control = $Scroll/Center/Card/Col/Rules
	if _launch_note != null:
		above = _launch_note
	var at: int = above.get_index() + 1
	var row := UiKit.hbox(8)
	var heading := UiKit.label("DIFFICULTY", 12, Palette.MIST)
	heading.custom_minimum_size = Vector2(100, 0)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)
	_difficulty_blurb = UiKit.label("", 13, Palette.MIST, true)
	for node: Control in [row, _difficulty_blurb]:
		col.add_child(node)
		col.move_child(node, at)
		at += 1
	_wide_texts.append(_difficulty_blurb)
	# Step 2: one toggle button per level. The chosen one shows pressed (in the
	# highlight colour).
	for level: String in Difficulty.ORDER:
		var lv := level
		var b := UiKit.button(String(Difficulty.LABELS[lv]), func() -> void: _choose_difficulty(lv))
		b.toggle_mode = true
		row.add_child(b)
		_difficulty_buttons[lv] = b
	# Step 3: the test option "Unlock everything (test)" at the right end of the
	# same row: a toggle, pressed (in the highlight colour) while it is on.
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	# Step 3b: the test option "No fog (test)" just left of Unlock everything: a toggle, pressed (in the highlight colour) while
	# it is on.
	_fog_button = UiKit.button("", func() -> void: _toggle_fog())
	_fog_button.toggle_mode = true
	_fog_button.tooltip_text = "A test option. On: your screen shows everything: no fog of war, every enemy ship and building, shots, explosions and sounds, even in gas clouds and hidden pockets. Only your screen changes: what each team sees, the computer pilots and the Admiral's placing rules are as usual. It is remembered for the next run."
	row.add_child(_fog_button)
	_unlock_button = UiKit.button("", func() -> void: _toggle_unlock())
	_unlock_button.toggle_mode = true
	_unlock_button.tooltip_text = "A test option. On: you can buy anything at once and for nothing (every ship, module and research; as Admiral, everything from the treasury). Computer pilots, the other team and the computer Admirals play normally. It is remembered for the next run."
	row.add_child(_unlock_button)
	_show_difficulty()
	_show_unlock()
	_show_fog()
	# Step 4: the two wing test options, in a row of their own under the difficulty text (they do not
	# fit the difficulty row's width).
	var wing_row := UiKit.hbox(8)
	var wing_heading := UiKit.label("WINGMEN", 12, Palette.MIST)
	wing_heading.custom_minimum_size = Vector2(100, 0)
	wing_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wing_row.add_child(wing_heading)
	_test_wing_button = UiKit.button("", func() -> void: _toggle_test_wing())
	_test_wing_button.toggle_mode = true
	_test_wing_button.tooltip_text = "A test option. On: a Scout, a Fighter and a Bomber fly with your pilot. Hold X, or tap it with the mouse on an enemy, one of your big ships or empty space, to order them. Remembered for the next run."
	wing_row.add_child(_test_wing_button)
	_cpu_wings_button = UiKit.button("", func() -> void: _toggle_cpu_wings())
	_cpu_wings_button.toggle_mode = true
	_cpu_wings_button.tooltip_text = "A test option. On: every computer pilot, on both teams, flies with the same three wingmen. They follow and fight but are given no orders. Remembered for the next run; turn it off if the match stutters."
	wing_row.add_child(_cpu_wings_button)
	col.add_child(wing_row)
	col.move_child(wing_row, at)
	_show_wings()


## The "Test wing" toggle was pressed: switch it the other way for the coming match and remember it.
func _toggle_test_wing() -> void:
	Game.choose_test_wing(not Game.test_wing)
	_show_wings()


## The "Computer pilots' wings" toggle was pressed: switch it the other way and remember it.
func _toggle_cpu_wings() -> void:
	Game.choose_cpu_wings(not Game.cpu_wings)
	_show_wings()


## Show Game.test_wing and Game.cpu_wings on their toggles: pressed when on, and the text says ON or off.
func _show_wings() -> void:
	_test_wing_button.set_pressed_no_signal(Game.test_wing)
	_test_wing_button.text = "Test wing (3 wingmen): %s" % ("ON" if Game.test_wing else "off")
	_cpu_wings_button.set_pressed_no_signal(Game.cpu_wings)
	_cpu_wings_button.text = "Computer pilots' wings: %s" % ("ON" if Game.cpu_wings else "off")


## The toggle was pressed: switch Unlock everything the other way for the coming
## match and remember it for the next run (Game.choose_unlock()), and show it.
func _toggle_unlock() -> void:
	Game.choose_unlock(not Game.unlock_everything)
	_show_unlock()


## Show Game.unlock_everything on the toggle: pressed when on, and its text says
## ON or off.
func _show_unlock() -> void:
	_unlock_button.set_pressed_no_signal(Game.unlock_everything)
	_unlock_button.text = "Unlock everything (test): %s" % ("ON" if Game.unlock_everything else "off")


## The No fog toggle was pressed: switch it the other way for the coming match and remember it for the next run
## (Game.choose_fog_off()), and show it.
func _toggle_fog() -> void:
	Game.choose_fog_off(not Game.fog_off)
	_show_fog()


## Show Game.fog_off on its toggle: pressed when on, and its text says ON or off.
func _show_fog() -> void:
	_fog_button.set_pressed_no_signal(Game.fog_off)
	_fog_button.text = "No fog (test): %s" % ("ON" if Game.fog_off else "off")


## Level `level` was picked: use it for the coming match and remember it for the
## next run (Game.choose_difficulty()), and show it.
func _choose_difficulty(level: String) -> void:
	Game.choose_difficulty(level)
	_show_difficulty()


## Show the level in Game.difficulty as chosen: its button pressed, the others
## not, and its description under the row. If the game was launched with an
## unknown --difficulty (Game.difficulty_error), say so instead: the match would
## refuse to start until a level is picked here, so both seat buttons wait too
## (any level button clears the error, and this runs again).
func _show_difficulty() -> void:
	for lv: String in _difficulty_buttons:
		(_difficulty_buttons[lv] as Button).set_pressed_no_signal(lv == Game.difficulty and Game.difficulty_error == "")
	_refresh_seats()
	if Game.difficulty_error != "":
		_difficulty_blurb.text = "The launch option --difficulty was not understood: %s. Pick a level above before you choose a seat." % Game.difficulty_error
	else:
		_difficulty_blurb.text = Difficulty.blurb(Game.difficulty)


## Add the team row right under the difficulty description: a row with the
## heading TEAM and one button per team the human can play for (Aurelian, Vhorr),
## then the chosen team's description (a wrapping label, so it joins _wide_texts).
func _build_team() -> void:
	# Step 1: the row (its heading first, then the buttons) and the description
	# go in the card's column, in that order, just below the difficulty
	# description. Like the difficulty row, the heading shares the row with the
	# buttons and the text is one line.
	var col: VBoxContainer = $Scroll/Center/Card/Col
	var at: int = _difficulty_blurb.get_index() + 1
	var row := UiKit.hbox(8)
	var heading := UiKit.label("TEAM", 12, Palette.MIST)
	heading.custom_minimum_size = Vector2(100, 0)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)
	_team_blurb = UiKit.label("", 13, Palette.MIST, true)
	for node: Control in [row, _team_blurb]:
		col.add_child(node)
		col.move_child(node, at)
		at += 1
	_wide_texts.append(_team_blurb)
	# Step 2: one toggle button per team, in the team's colour. The chosen one
	# shows pressed (a box in the team's colour).
	for side: int in [Rules.HALCYON, Rules.CINDER]:
		var b := _team_button(side)
		row.add_child(b)
		_team_buttons[side] = b
	_show_team()


## A toggle button for team `side`, with the team's name in the team's colour,
## and a border in that colour when hovered or chosen (the theme's is the
## highlight colour).
func _team_button(side: int) -> Button:
	var tint := Palette.team(side)
	var b := UiKit.button(String(Rules.TEAM_DISPLAY[side]), func() -> void: _choose_team(side))
	b.toggle_mode = true
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, tint)
	b.add_theme_stylebox_override("hover", UiKit.box(Palette.INK, tint, 8))
	b.add_theme_stylebox_override("pressed", UiKit.box(Palette.PANEL, tint, 8))
	b.add_theme_stylebox_override("hover_pressed", UiKit.box(Palette.PANEL, tint, 8))
	return b


## Team `side` was picked: use it for the coming match and remember it for the
## next run (Game.choose_team()), turn the screen's highlight colour into that
## team's, and show the pick.
func _choose_team(side: int) -> void:
	Game.choose_team(side)
	_use_team_accent()
	_show_team()


## Show the team in Game.human_team as chosen: its button pressed, the other not,
## its description under the row. If the game was launched with an unknown --team
## (Game.team_error), say so instead: the match would refuse to start, so both
## seat buttons wait too (a team button clears the error, and this runs again).
func _show_team() -> void:
	for side: int in _team_buttons:
		(_team_buttons[side] as Button).set_pressed_no_signal(side == Game.human_team and Game.team_error == "")
	_refresh_seats()
	if Game.team_error != "":
		_team_blurb.text = "The launch option --team was not understood: %s. Pick a team above before you choose a seat." % Game.team_error
	else:
		_team_blurb.text = String(TEAM_BLURBS[Game.human_team])


## Enable the two seat buttons, unless a launch option was not understood (an
## unknown --preset, --variant, --difficulty or --team): the match would refuse
## to start, so both stay off. A level above clears an unknown --difficulty and
## a team above clears an unknown --team; an unknown --preset or --variant stays
## until the game is launched again.
func _refresh_seats() -> void:
	var blocked: bool = Game.preset_error != "" or Game.variant_error != "" or Game.difficulty_error != "" or Game.team_error != ""
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.disabled = blocked
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.disabled = blocked


## Fit the card to the window. The layout is made at full size: the window size
## is divided by CARD_SCALE, Scroll is sized to that and then drawn scaled down,
## so the card is drawn at CARD_SCALE of its layout size, centred, with the
## cover behind it still filling the window. w = that full width minus 80
## pixels, but at most 980. (The card comes out 52 pixels wider than w, with its padding and
## the seat cards' gap, and a scroll bar can take 6 more: 80 leaves the
## card 10 pixels from each side of the window.) Then give every wrapping
## label a fixed width (UiKit.pin_width),
## because a wrapping label can't measure its height until it knows its
## width: text inside a seat card gets (w - 74) / 2 pixels (half the card,
## after padding and the gap between the cards), all other text w - 46.
func _layout() -> void:
	var full := size / CARD_SCALE
	var scroll: ScrollContainer = $Scroll
	scroll.anchor_right = 0.0
	scroll.anchor_bottom = 0.0
	scroll.scale = Vector2.ONE * CARD_SCALE
	scroll.size = full
	var w := minf(980.0, full.x - 80.0)
	_card.custom_minimum_size = Vector2(w, 0)
	for l in _wide_texts:
		UiKit.pin_width(l, w - 46.0)
	for l in _seat_texts:
		UiKit.pin_width(l, (w - 74.0) * 0.5)
