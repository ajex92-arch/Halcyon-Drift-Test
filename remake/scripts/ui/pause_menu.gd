class_name PauseMenu
extends Control
## WHAT THIS IS: the pause menu, the screen that P or Esc opens during a match.
## The game stays paused while it shows. It offers Resume, Look around (hides the
## card and keeps the pause, so the camera can be moved), How to play and Controls
## (the key settings; these two share a row), a row of speed buttons (SpeedRow),
## Restart match (the same seat and the same rules), Quit to start (back to the
## start screen), a Full screen / Windowed switch and Quit game (the browser build
## has no such button). The three buttons that end the match ask "are you sure?" first.
##
## HOW IT WORKS: the layout is the scene scenes/ui/pause_menu.tscn. This node
## covers the whole window and takes every click, so nothing behind it can be
## pressed and the mouse wheel never reaches the camera. A dim Cover darkens the
## game, and in the middle of the room the HUD leaves free (Center; HudPanels
## sets it through set_room()) stands the Card (the "PauseLook" box) with a Title,
## a Hint line and Items, the column of buttons. _build() makes the buttons of
## the view being shown: VIEW_MENU, or one of three questions (VIEW_RESTART,
## VIEW_START, VIEW_QUIT: a sentence, a "Yes" button and a "Back" button).
## The menu's pause is a "session". open() starts it and pauses the game
## (get_tree().paused); resume() ends it and gives the game back. While the
## session lasts the menu may be hidden for a while: How to play (the help pages)
## opens over it (and so does the Controls page), and when those close HudPanels
## asks show_card() to bring the menu back. Esc and P end the session from
## anywhere (HudInput; the keys are the player's own, from the key list). Restart and
## Quit to start leave through Game.restart_match() and Game.quit_to_start(),
## which load the main scene again, so a new match or the start screen is made
## from nothing. Full screen / Windowed is WindowMode.toggle_fullscreen(), the
## same switch as F11; the button's words follow the window, also when F11
## changed it.
##
## LOOK AROUND: the Look around button is the one way the card goes away while the
## session lasts. look_around() hides the card (the dim cover and the click-taking
## root go with it, so the mouse reaches the camera: the wheel, the middle-button
## drag, the screen edges and the minimap), puts an armed Admiral map tool away,
## sets `looking` and keeps `active`: the game stays paused, P still resumes, and
## HudBanner names the keys (Esc: the card comes back; P: resume). Esc is back()
## as ever, so it shows the card again. H still shows the help pages over it; when
## they close, panel_closed() leaves the look-around as it was (the card does not
## come back by itself while `looking`).
##
## WHO USES IT: HudPanels makes it from scenes/ui/pause_menu.tscn the first time
## it is needed (Hud.pause_menu), HudInput opens and closes it with P and Esc,
## and tests/ui_tour.gd, tests/wheel_check.gd and tests/pause_menu_check.gd
## drive it.

## The view with the buttons.
const VIEW_MENU := "menu"
## The question before a restart.
const VIEW_RESTART := "restart"
## The question before going back to the start screen.
const VIEW_START := "start"
## The question before closing the game.
const VIEW_QUIT := "quit"

## Each question's title: view -> text.
const QUESTION_TITLES := {
	VIEW_RESTART: "Restart the match?",
	VIEW_START: "Quit to the start screen?",
	VIEW_QUIT: "Quit the game?",
}
## Each question's "Yes" button: view -> text.
const YES_TEXTS := {
	VIEW_RESTART: "Yes, restart",
	VIEW_START: "Yes, quit to start",
	VIEW_QUIT: "Yes, close the game",
}
## The widest (pixels) the Hint line is made before it wraps.
const HINT_WIDTH := 400.0
## The room (pixels) between two groups of buttons.
const GAP := 6.0

## The HUD this menu belongs to (set by setup()).
var hud: Hud
## True from open() to resume(): the menu is holding the game paused, even in the
## moments when the menu itself is hidden behind the help pages.
var active := false
## True from the Look around button until the card comes back or the session ends: the
## card is hidden, the game stays paused and `active` stays true (so P still resumes).
var looking := false
## The view being shown (one of the VIEW_ words).
var _view := VIEW_MENU
## The Full screen / Windowed button of the menu view (null in a question view).
var _screen_button: Button = null
## The dim cover over the game.
@onready var _cover: ColorRect = $Cover
## The container that centres the card in the room the HUD leaves free.
@onready var _center: CenterContainer = $Center
## The box with the title, the hint and the buttons.
@onready var _card: PanelContainer = $Center/Card
## The card's first line.
@onready var _title: Label = $Center/Card/Col/Title
## The card's small grey line under the title.
@onready var _hint: Label = $Center/Card/Col/Hint
## The column the buttons are made in.
@onready var _items: VBoxContainer = $Center/Card/Col/Items


## Called once when the menu joins the HUD: the dim cover's colour, the title in
## the highlight colour and a wrapping hint line.
func _ready() -> void:
	visible = false
	_cover.color = Palette.with_alpha(Palette.VOID, 0.45)
	_title.add_theme_color_override("font_color", UiKit.accent())
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Remember which HUD we belong to.
func setup(h: Hud) -> void:
	hud = h


## Start the session: pause the game and show the menu (the other big panels
## close).
func open() -> void:
	active = true
	get_tree().paused = true
	_view = VIEW_MENU
	_show()


## Show the menu again, in the middle of a session (the help pages that were
## over it have closed).
func show_card() -> void:
	_view = VIEW_MENU
	_show()


## "Look around": hide the card but keep the session. The game stays paused and `active` stays true (P resumes,
## Esc brings the card back); the cover goes with the card, so the mouse reaches the camera and the minimap; and
## HudBanner shows the line that names the two keys. An armed Admiral map tool is put away first: a minimap click
## would place it, and this button is for looking, not for giving orders.
func look_around() -> void:
	hud.overlay.disarm()
	looking = true
	visible = false
	hud.layout.apply()
	hud.banner.refresh()


## End the session: hide the menu (and anything over it) and give the game back.
## The mouse buttons are read again, because a button let go while the game was
## paused never reached the World.
func resume() -> void:
	active = false
	looking = false
	visible = false
	get_tree().paused = false
	var w := hud.world
	if w != null:
		w.mouse_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		w.mouse_special = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	hud.panels.close_others(null)


## One step back (Esc): from a page over the menu to what was under it, from Look around to the
## card, from a question to the buttons, from the buttons to the game.
func back() -> void:
	if looking and not hud.panels.any_open():
		# Looking around with the card hidden: the card comes back (the game stays paused).
		show_card()
	elif not visible:
		# The help pages are over the menu (or over the look-around): closing them brings back what was under them.
		hud.panels.close_others(null)
	elif _view != VIEW_MENU:
		_view = VIEW_MENU
		_build()
	else:
		resume()


## The match ended while the menu held the game: forget the session without
## touching the pause (Hud._on_match_over gives the game back itself).
func end_session() -> void:
	active = false
	looking = false


## Show question `which` (VIEW_RESTART, VIEW_START or VIEW_QUIT) in place of the
## buttons.
func ask(which: String) -> void:
	_view = which
	_build()


## Which view is showing (one of the VIEW_ words).
func current_view() -> String:
	return _view


## Give the card the room between `top` pixels from the top of the window and
## `bottom` pixels from its bottom edge; it is centred in that room. Does
## nothing if the room is already right.
func set_room(top: float, bottom: float) -> void:
	if absf(_center.offset_top - top) > 0.5 or absf(_center.offset_bottom + bottom) > 0.5:
		_center.offset_top = top
		_center.offset_bottom = -bottom


## The width (pixels) the card asks for, so HudPanels can tell which part of the
## HUD's top row the card could touch.
func card_width() -> float:
	return _card.get_combined_minimum_size().x


## While the menu shows, keep the Full screen / Windowed button's words in step
## with the window (F11 may have changed it).
func _process(_dt: float) -> void:
	if visible and _screen_button != null:
		UiKit.set_text(_screen_button, _screen_text())


## Make the menu visible with the view in `_view`, on top of the other panels,
## which close. Showing the card ends a look-around (`looking` is false again).
func _show() -> void:
	looking = false
	_build()
	visible = true
	move_to_front()
	hud.panels.close_others(self)


## Fill the card for the view in `_view`: new words and new buttons.
func _build() -> void:
	for c in _items.get_children():
		_items.remove_child(c)
		c.queue_free()
	_screen_button = null
	if _view == VIEW_MENU:
		_title.text = "Paused"
		_hint.text = "%s or %s resumes the match." % [KeyMapText.key_of("cancel"), KeyMapText.key_of("pause")]
		_build_buttons()
	else:
		_title.text = QUESTION_TITLES[_view]
		_hint.text = _question_text()
		_build_question()
	UiKit.pin_width(_hint, HINT_WIDTH)


## The buttons of the menu view.
func _build_buttons() -> void:
	# Step 1: back to the game, a look at the map with the game still paused, and the help.
	var go := UiKit.button("Resume", resume, 44.0)
	go.theme_type_variation = &"PrimaryButton"
	_items.add_child(go)
	# Look around hides this card and keeps the pause (see look_around()).
	_items.add_child(UiKit.button("Look around", look_around))
	# How to play and Controls share a row: one more row would make the card taller than the room the HUD
	# leaves it at 1280 x 720 (a flying pilot's room is exactly the card's old height). The help and the
	# Controls page (the key settings) open over the menu.
	var pages := UiKit.hbox(8)
	for b: Button in [UiKit.button("How to play", _on_help), UiKit.button("Controls", hud._toggle_controls)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(b)
	_items.add_child(pages)
	_items.add_child(_gap())
	# The game speed: a row of buttons that follows the world's speed by itself.
	var speed_row := SpeedRow.new()
	_items.add_child(speed_row)
	speed_row.setup(hud.world)
	_items.add_child(_gap())
	# Step 2: the two that end the match.
	_items.add_child(UiKit.button("Restart match", ask.bind(VIEW_RESTART)))
	_items.add_child(UiKit.button("Quit to start", ask.bind(VIEW_START)))
	_items.add_child(_gap())
	# Step 3: the window, and leaving the game (a web page cannot close itself).
	_screen_button = UiKit.button(_screen_text(), _on_screen)
	_items.add_child(_screen_button)
	if not OS.has_feature("web"):
		_items.add_child(UiKit.button("Quit game", ask.bind(VIEW_QUIT)))


## The two buttons of a question view.
func _build_question() -> void:
	var yes := UiKit.button(YES_TEXTS[_view], _confirm.bind(_view), 44.0)
	yes.theme_type_variation = &"PrimaryButton"
	_items.add_child(yes)
	_items.add_child(UiKit.button("Back", back))


## A thin empty space between two groups of buttons.
func _gap() -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, GAP)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## What the current question says will happen.
func _question_text() -> String:
	match _view:
		VIEW_RESTART:
			return "A new match starts at once, in the same seat (%s) on the same rules. This match is lost." % _seat_text()
		VIEW_START:
			return "You go back to the start screen, where you pick a seat, a team and a difficulty again. This match is lost."
	return "The game closes. This match is lost."


## The human's seat in words: "Pilot for Aurelian, Medium difficulty".
func _seat_text() -> String:
	var w := hud.world
	if w.human_role == "spectator":
		return "watching"
	return "%s for %s, %s difficulty" % [w.human_role.capitalize(), Rules.TEAM_DISPLAY[w.human_team], String(Difficulty.LABELS[Game.difficulty])]


## "Yes" was pressed on question `which`: do it.
func _confirm(which: String) -> void:
	match which:
		VIEW_RESTART:
			Game.restart_match(hud.world.human_role)
		VIEW_START:
			Game.quit_to_start()
		VIEW_QUIT:
			get_tree().quit()


## How to play: the help pages open over the menu (and the menu waits behind).
func _on_help() -> void:
	hud._toggle_help()


## Full screen / Windowed: switch the window, as F11 does.
func _on_screen() -> void:
	WindowMode.toggle_fullscreen()
	UiKit.set_text(_screen_button, _screen_text())


## The words of the window button: what pressing it would do.
func _screen_text() -> String:
	return "Windowed" if WindowMode.is_fullscreen() else "Full screen"
