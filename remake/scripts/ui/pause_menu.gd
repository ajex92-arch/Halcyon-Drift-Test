class_name PauseMenu
extends Control
## WHAT THIS IS: the pause menu, the screen that Esc (or the Menu button) opens during a match; P never opens it, it only resumes it.
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
## SETTINGS (T-125): two rows of the menu change a setting of the HUD and keep it in the settings file (Game): "Flash my ship when
## the camera returns" (an On / Off button, Game.return_flash) and "Minimap size" (a slider from 80% to 140% with a minus and a plus
## button and the value; Game.minimap_pct). The minimap size applies at once (Minimap.apply_size()), and the minimap, which the HUD
## hides under every big panel, stays visible while that row is in use (`minimap_peek`, see HudLayout.apply()). An Admiral's menu has one
## more button, "Win odds on the army cards" (On / Off, Game.win_odds, off by default; WinOdds): it is for the army row, so a pilot's and
## a spectator's menu has none.
##
## FLIGHT ROW (S1, pilots only): one row holds the pilot's camera switch ("Camera: Free" / "Camera: Follow": CameraRig.toggle_free(), remembered by
## Game.choose_pilot_follow()), the mouse route of the C key, and the speed zoom switch ("Speed zoom: On" / "Off": Game.speed_zoom, remembered).
##
## RING AND CARD (pilots and Admirals): a third button in the How to play row opens the parts view (VIEW_PARTS, asked for like a
## question): "Ring: Full / Compact / Minimal" and "Card: Full / Compact / Minimal" buttons (Game.choose_ring_preset(),
## Game.choose_card_preset(), remembered), one On / Off switch for each of the nine ring parts in three rows of three
## (Game.choose_ring_part(), remembered) and Back. It adds no row to the menu, whose card has no spare height.
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
## The view of the ring and the target card: their presets and one switch for each part.
const VIEW_PARTS := "parts"

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
## T-125: true from the first touch of the Minimap size row until the card is built again or closes: the minimap then stays
## visible under the card, so the player sees the result (HudLayout.apply() reads it).
var minimap_peek := false
## The view being shown (one of the VIEW_ words).
var _view := VIEW_MENU
## The Full screen / Windowed button of the menu view (null in a question view).
var _screen_button: Button = null
## T-125: the "Flash my ship ..." button (null in a question view).
var _flash_button: Button = null
## T-125: the Minimap size slider (null in a question view).
var _map_slider: HSlider = null
## S1: the pilot's Camera button (null in a question view and for an Admiral).
var _camera_button: Button = null
## S1: the pilot's Speed zoom button (null in a question view and for an Admiral).
var _speed_button: Button = null
## T-125: the Minimap size value in words, "100%" (null in a question view).
var _map_value: Label = null
## RT6: the Minimap orders button, and the value of the icon line's row (made by _orders_row()).
var _orders_button: Button = null
var _icon_value: Label = null
## The win-odds button ("Win odds on the army cards: Off/On"; null in a question view, and for a pilot or a spectator, who have no army row).
var _odds_button: Button = null
## The parts view's "Ring: Full" and "Card: Full" buttons (null in the other views).
var _ring_button: Button = null
## The parts view's Card preset button (null in the other views).
var _card_button: Button = null
## The parts view's nine switches, by ShipRingParts id (empty in the other views).
var _part_buttons := {}
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
	minimap_peek = false
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
	minimap_peek = false
	visible = false
	get_tree().paused = false
	var w := hud.world
	if w != null:
		# Not in mode 3: a button still held when the pause or note closes fires nothing there (the view works the mouse).
		w.mouse_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not CoastController.holding(w)
		w.mouse_special = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not CoastController.holding(w)
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
	_flash_button = null
	_camera_button = null
	_speed_button = null
	_map_slider = null
	_map_value = null
	_orders_button = null
	_icon_value = null
	_odds_button = null
	_ring_button = null
	_card_button = null
	_part_buttons = {}
	minimap_peek = false
	if _view == VIEW_MENU:
		_title.text = "Paused"
		_hint.text = "%s or %s resumes the match." % [KeyMapText.key_of("cancel"), KeyMapText.key_of("pause")]
		_build_buttons()
	elif _view == VIEW_PARTS:
		_title.text = "Ring and card"
		_hint.text = "What your ship's ring and the target card show: step each between Full, Compact and Minimal, then switch single parts on or off."
		_build_parts()
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
	# An Admiral's menu shares that row with the win-odds button (its own row made the card taller than its room).
	var look := UiKit.button("Look around", look_around)
	if hud.world.human_role == "admiral":
		var look_row := UiKit.hbox(8)
		look_row.add_child(look)
		_odds_button = UiKit.button(_odds_text(), _on_odds)
		_odds_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		look_row.add_child(_odds_button)
		_items.add_child(look_row)
	elif hud.world.human_role == "pilot":
		# A pilot's menu shares it with the two flight settings (S1: Camera, Speed zoom): one row, not two (the card was 30 px too tall).
		var fly_row := UiKit.hbox(8)
		fly_row.add_child(look)
		for b: Button in _flight_buttons():
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fly_row.add_child(b)
		_items.add_child(fly_row)
	else:
		_items.add_child(look)
	# How to play and Controls share a row: one more row would make the card taller than the room the HUD
	# leaves it at 1280 x 720 (a flying pilot's room is exactly the card's old height). The help and the
	# Controls page (the key settings) open over the menu.
	var pages := UiKit.hbox(8)
	var page_buttons: Array[Button] = [UiKit.button("How to play", _on_help), UiKit.button("Controls", hud._toggle_controls)]
	# The third button opens the ring and card view (the same row: a row of its own would make the card too tall). A spectator has no ship.
	if hud.world.human_role != "spectator":
		page_buttons.append(UiKit.button("Ring and card", ask.bind(VIEW_PARTS)))
	for b: Button in page_buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(b)
	_items.add_child(pages)
	_items.add_child(_gap())
	# The game speed: a row of buttons that follows the world's speed by itself.
	var speed_row := SpeedRow.new()
	_items.add_child(speed_row)
	speed_row.setup(hud.world)
	# T-125: the two settings of the HUD: the size of the minimap, and the flash of your ship when the camera returns.
	_items.add_child(_minimap_row())
	_flash_button = UiKit.button(_flash_text(), _on_flash, 30.0)
	_items.add_child(_flash_button)
	_items.add_child(_orders_row())
	_items.add_child(_gap())
	# Step 2: the two that end the match (one row: the card must fit the room at 1280 x 720 with the two new rows).
	var ends := UiKit.hbox(8)
	for b: Button in [UiKit.button("Restart match", ask.bind(VIEW_RESTART)), UiKit.button("Quit to start", ask.bind(VIEW_START))]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ends.add_child(b)
	_items.add_child(ends)
	_items.add_child(_gap())
	# Step 3: the window, and leaving the game (a web page cannot close itself); one row when both are there.
	_screen_button = UiKit.button(_screen_text(), _on_screen)
	_screen_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var window := UiKit.hbox(8)
	window.add_child(_screen_button)
	if not OS.has_feature("web"):
		var quit := UiKit.button("Quit game", ask.bind(VIEW_QUIT))
		quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		window.add_child(quit)
	_items.add_child(window)


## T-125: the "Minimap size" row: the words, a minus button, the slider (80% to 140% in steps of 10%), a plus button and the value.
## Mouse only: the slider and the buttons take no keyboard focus, so the arrow keys never change the size.
func _minimap_row() -> Control:
	var row := UiKit.hbox(6)
	row.add_child(UiKit.label("Minimap size", 15, Palette.MIST))
	var minus := UiKit.button("-", _step_minimap.bind(-1), 30.0)
	minus.custom_minimum_size.x = 34.0
	row.add_child(minus)
	_map_slider = HSlider.new()
	_map_slider.min_value = float(Game.MINIMAP_PCT_MIN)
	_map_slider.max_value = float(Game.MINIMAP_PCT_MAX)
	_map_slider.step = float(Game.MINIMAP_PCT_STEP)
	_map_slider.set_value_no_signal(float(Game.minimap_pct))
	_map_slider.custom_minimum_size = Vector2(110.0, 24.0)
	_map_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map_slider.value_changed.connect(_on_map_slider)
	row.add_child(_map_slider)
	var plus := UiKit.button("+", _step_minimap.bind(1), 30.0)
	plus.custom_minimum_size.x = 34.0
	row.add_child(plus)
	_map_value = UiKit.label("%d%%" % Game.minimap_pct, 15, Palette.ICE)
	_map_value.custom_minimum_size.x = 46.0
	_map_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_map_value)
	for c: Control in [minus, _map_slider, plus]:
		c.focus_mode = Control.FOCUS_NONE
		c.mouse_entered.connect(_peek_minimap)
	return row


## T-125: the minimap stays visible while its row is in use.
func _peek_minimap() -> void:
	if minimap_peek:
		return
	minimap_peek = true
	hud.layout.apply()


## T-125: the minus or plus button: one step (10%) smaller or bigger.
func _step_minimap(dir: int) -> void:
	_set_minimap(Game.minimap_pct + dir * Game.MINIMAP_PCT_STEP)


## T-125: the slider moved.
func _on_map_slider(v: float) -> void:
	_set_minimap(int(round(v)))


## T-125: use minimap size `pct` now and remember it; the slider and the value follow.
func _set_minimap(pct: int) -> void:
	Game.choose_minimap_pct(pct)
	if _map_slider != null:
		_map_slider.set_value_no_signal(float(Game.minimap_pct))
	if _map_value != null:
		_map_value.text = "%d%%" % Game.minimap_pct
	hud.minimap.apply_size()
	_peek_minimap()
	hud.layout.apply()


## RT6: one row with the two settings of the awareness screens: the "Minimap orders" button (On <-> Off: a right click on the minimap
## gives Move to the selection; Minimap.orders_on) and the icon line (the view width in world units past which the ships are
## drawn as icons: a minus button, the value, a plus button; IconLayer.line_w, 11,000 to 30,000 in steps of 1,000). Both are
## saved in the settings file's [game] section.
func _orders_row() -> Control:
	var row := UiKit.hbox(6)
	_orders_button = UiKit.button(_orders_text(), _on_orders, 30.0)
	_orders_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_orders_button)
	row.add_child(UiKit.label("Icons from", 15, Palette.MIST))
	var minus := UiKit.button("-", _step_icon_line.bind(-1), 30.0)
	minus.custom_minimum_size.x = 34.0
	row.add_child(minus)
	_icon_value = UiKit.label(_icon_text(), 15, Palette.ICE)
	_icon_value.custom_minimum_size.x = 52.0
	_icon_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_icon_value)
	var plus := UiKit.button("+", _step_icon_line.bind(1), 30.0)
	plus.custom_minimum_size.x = 34.0
	row.add_child(plus)
	return row


## RT6: the Minimap orders button: On <-> Off.
func _on_orders() -> void:
	Minimap.set_orders(not Minimap.orders_on)
	UiKit.set_text(_orders_button, _orders_text())


## RT6: the Minimap orders button's words.
func _orders_text() -> String:
	return "Minimap orders: %s" % ("On" if Minimap.orders_on else "Off")


## RT6: the minus or plus button of the icon line: one step (1,000 units) less or more.
func _step_icon_line(dir: int) -> void:
	IconLayer.set_line(IconLayer.line_w + dir * IconLayer.LINE_STEP)
	if _icon_value != null:
		_icon_value.text = _icon_text()


## RT6: the icon line's value, in thousands with a separator ("16,000").
func _icon_text() -> String:
	var n := IconLayer.line_w
	return "%d,%03d" % [n / 1000, n % 1000]


## S1: the pilot's flight buttons: the Camera button (free <-> follow) and the Speed zoom button (On <-> Off); they share the Look around row.
func _flight_buttons() -> Array[Button]:
	_camera_button = UiKit.button(_camera_text(), _on_camera)
	_speed_button = UiKit.button(_speed_text(), _on_speed)
	return [_camera_button, _speed_button]


## S1: the Camera button: the pilot's camera goes between free and following the ship, and the choice is remembered for the next match.
func _on_camera() -> void:
	var cam := hud.world.camera
	cam.toggle_free()
	Game.choose_pilot_follow(not cam.free)
	UiKit.set_text(_camera_button, _camera_text())


## S1: the Speed zoom button: On <-> Off, remembered.
func _on_speed() -> void:
	Game.choose_speed_zoom(not Game.speed_zoom)
	UiKit.set_text(_speed_button, _speed_text())


## S1: the Speed zoom button's words.
func _speed_text() -> String:
	return "Speed zoom: %s" % ("On" if Game.speed_zoom else "Off")


## S1: the Camera button's words.
func _camera_text() -> String:
	return "Camera: %s" % ("Free" if hud.world.camera.free else "Follow")


## The win-odds button: On <-> Off (remembered; the army cards show or hide their mark on the next beat).
func _on_odds() -> void:
	Game.choose_win_odds(not Game.win_odds)
	UiKit.set_text(_odds_button, _odds_text())


## The win-odds button's words.
func _odds_text() -> String:
	return "Win odds on the army cards: %s" % ("On" if Game.win_odds else "Off")


## T-125: the flash button: On <-> Off.
func _on_flash() -> void:
	Game.choose_return_flash(not Game.return_flash)
	UiKit.set_text(_flash_button, _flash_text())


## T-125: the flash button's words.
func _flash_text() -> String:
	return "Flash my ship when the camera returns: %s" % ("On" if Game.return_flash else "Off")


## The buttons of the parts view: the ring preset and the card preset (each button steps to the next of Full, Compact, Minimal), the
## nine ring parts in three rows of three (each a switch, remembered), and Back. A part the chosen preset leaves out shows Off and cannot
## be switched on here (the preset decides what is on offer).
func _build_parts() -> void:
	var presets := UiKit.hbox(8)
	_ring_button = UiKit.button(_ring_text(), _on_ring_preset)
	_card_button = UiKit.button(_card_text(), _on_card_preset)
	for b: Button in [_ring_button, _card_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(b)
	_items.add_child(presets)
	_items.add_child(_gap())
	var ids := ShipRingParts.ids()
	for row in 3:
		var line := UiKit.hbox(8)
		for col in 3:
			var id := String(ids[row * 3 + col])
			var b := UiKit.button(_part_text(id), _on_part.bind(id), 32.0)
			b.add_theme_font_size_override("font_size", 13)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = not ShipRingParts.preset_has(Game.ring_preset, id)
			_part_buttons[id] = b
			line.add_child(b)
		_items.add_child(line)
	_items.add_child(_gap())
	_items.add_child(UiKit.button("Back", back))


## The ring preset button: the next preset, remembered.
func _on_ring_preset() -> void:
	Game.choose_ring_preset((Game.ring_preset + 1) % ShipRingParts.PRESETS.size())
	_refresh_parts()


## The card preset button: the next preset, remembered.
func _on_card_preset() -> void:
	Game.choose_card_preset((Game.card_preset + 1) % Game.CARD_PRESETS.size())
	_refresh_parts()


## Switch ring part `id` on or off, remembered.
func _on_part(id: String) -> void:
	Game.choose_ring_part(id, Game.ring_parts_off.has(id))
	_refresh_parts()


## The words and the state of every button of the parts view, after a change.
func _refresh_parts() -> void:
	if _ring_button != null:
		UiKit.set_text(_ring_button, _ring_text())
	if _card_button != null:
		UiKit.set_text(_card_button, _card_text())
	for id: String in _part_buttons:
		var b: Button = _part_buttons[id]
		UiKit.set_text(b, _part_text(id))
		b.disabled = not ShipRingParts.preset_has(Game.ring_preset, id)


## The ring preset button's words.
func _ring_text() -> String:
	return "Ring: %s" % ShipRingParts.preset_name(Game.ring_preset)


## The card preset button's words.
func _card_text() -> String:
	return "Card: %s" % String(Game.CARD_PRESETS[Game.card_preset])


## The words of part `id`'s switch: its name and On or Off.
func _part_text(id: String) -> String:
	var label := id
	for p: Dictionary in ShipRingParts.PARTS:
		if String(p["id"]) == id:
			label = String(p["label"])
	return "%s: %s" % [label, "On" if ShipRingParts.shown(id) else "Off"]


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
