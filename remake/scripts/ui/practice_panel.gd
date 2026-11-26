class_name PracticePanel
extends PanelContainer
## WHAT THIS IS: the practice range's control panel: a column on the left edge between the
## "me" panel and the gear slots with the four switches (waves, camps, money, cooldowns), each a
## button. It exists only in a practice match (the HUD makes it only then). It changes nothing in
## the world itself: every press sends one PRACTICE order (PracticeOrders.send) and the world
## carries it out at the start of the next tick.
##
## HOW IT WORKS:
##   - A title row (PRACTICE and a collapse arrow) and four sections: WAVES (Freeze waves with its
##     state in words, Send one wave, and a line "Next wave 0:21" or "Waves frozen"), CAMPS
##     (Respawn all camps, Respawn nearest camp), MONEY (+5,000 credits, and for the Admiral +5,000
##     treasury, and the line "Practice money so far: N") and COOLDOWNS (Reset cooldowns, No cooldowns
##     with its state in words; the Admiral sees this section only while flying or dead).
##   - Collapsed, it is the title row alone: a small tab to click to open. It shows as the tab whenever
##     the free band of the left edge (under the me panel, or under the Admiral's alert list while the
##     command view shows, and above the gear slots or the command card) is lower than the open panel,
##     unless the player opened it by hand. While a big panel is open (the hangar, the board, the help...)
##     it steps aside completely and comes back, as the player left it, when that closes.
##   - Every frame _process() rewrites the words that changed, counts down the refusal lines and
##     places the panel on the left edge, centred in the room between the me panel and the gear
##     slots. A refused press writes its reason under its button for PracticeSwitches.REFUSAL_SECONDS
##     seconds, counted down here in _process (no timer node, no animation). No tooltip and no particle.
##   - "Respawn nearest camp" picks the camp nearest the centre of the screen within
##     PracticeSwitches.CAMP_REACH and sends its id: the order carries the id, not the place.
##   - press() takes a `remember` flag: the clicks pass true (the toggles and the open or closed
##     state go into the settings file for the next range); the check passes false.
##   - The O key (the action practice_panel, read exactly: Shift+O under wing preset B) opens or
##     closes the panel.
##
## WHO USES IT: Hud.setup() adds one for a practice match (World.practice). It reads the World's
## minion director and practice range and Hud's me panel, gear slots and big-panel question.

## The room (pixels) kept clear above and below the panel.
const GAP := 6.0
## The space (pixels) the panel's look keeps at both sides together (its box margins), so that the
## buttons plus this are the table's panel width.
const PAD := 20.0
## The pixel width a refusal or status line wraps at.
const LINE_WIDTH := 200.0

## The game world this panel sends its orders to.
var world: World
## What the player chose: true = the full panel, false = the tab.
var _open := true
## The part of the panel that is hidden when it is a tab.
var _body: VBoxContainer
## The title.
var _title: Label
## The collapse arrow.
var _arrow: Button
## The buttons by switch word.
var _buttons := {}
## The refusal line under each button, by switch word.
var _notes := {}
## Seconds each refusal line still shows, by switch word.
var _note_left := {}
## The wave line under the wave buttons.
var _wave_line: Label
## The money line.
var _money_line: Label
## The COOLDOWNS section (hidden for a docked Admiral).
var _cd_box: VBoxContainer
## Frames since the panel was made.
var _frames := 0
## True when the player opened the panel by hand: it then shows in full even where it is tight.
var _force := false
## The room (pixels) the last placement found between the me panel and the gear slots.
var last_room := 0.0
## The height (pixels) of the open panel the last placement measured.
var last_open_height := 0.0


## Build the panel for world `w`: the title row and the four sections.
func _init(w: World) -> void:
	world = w
	name = "PracticePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme_type_variation = &"MeLook"
	_open = Game.practice_panel_open
	var col := UiKit.vbox(4)
	add_child(col)
	var head := UiKit.hbox(6)
	col.add_child(head)
	_title = UiKit.label("PRACTICE", 13, UiKit.accent())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	_arrow = UiKit.button("-", _on_arrow, float(PracticeSwitches.BUTTON_HEIGHT))
	_arrow.custom_minimum_size = Vector2(float(PracticeSwitches.BUTTON_HEIGHT), float(PracticeSwitches.BUTTON_HEIGHT))
	head.add_child(_arrow)
	_body = UiKit.vbox(3)
	col.add_child(_body)
	_section(_body, "WAVES")
	_add_button(_body, PracticeSwitches.FREEZE, "Freeze waves: Running")
	_add_button(_body, PracticeSwitches.WAVE, "Send one wave")
	_wave_line = UiKit.label("", 12, Palette.MIST, true)
	UiKit.pin_width(_wave_line, LINE_WIDTH)
	_body.add_child(_wave_line)
	_section(_body, "CAMPS")
	_add_button(_body, PracticeSwitches.CAMPS, "Respawn all camps")
	_add_button(_body, PracticeSwitches.CAMP_NEAR, "Respawn nearest camp")
	_section(_body, "MONEY")
	_add_button(_body, PracticeSwitches.MONEY, "+%s credits" % _commas(PracticeSwitches.CREDITS_PER_PRESS))
	if world.human_role == "admiral":
		_add_button(_body, PracticeSwitches.TREASURY, "+%s treasury" % _commas(PracticeSwitches.TREASURY_PER_PRESS))
	_money_line = UiKit.label("", 12, Palette.MIST, true)
	UiKit.pin_width(_money_line, LINE_WIDTH)
	_body.add_child(_money_line)
	_cd_box = UiKit.vbox(3)
	_body.add_child(_cd_box)
	_section(_cd_box, "COOLDOWNS")
	_add_button(_cd_box, PracticeSwitches.CD_RESET, "Reset cooldowns")
	_add_button(_cd_box, PracticeSwitches.CD_AUTO, "No cooldowns: Off")
	_apply_open(_open)


## The whole number `n` with commas ("5,000").
static func _commas(n: float) -> String:
	var s := str(int(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## A small section heading in `parent`.
func _section(parent: Control, text: String) -> void:
	parent.add_child(UiKit.heading(text))


## A button for switch `key` (its words `text`) in `parent`, with its refusal line below it.
func _add_button(parent: Control, key: String, text: String) -> void:
	var b := UiKit.button(text, _on_button.bind(key), float(PracticeSwitches.BUTTON_HEIGHT))
	b.custom_minimum_size = Vector2(float(PracticeSwitches.PANEL_WIDTH) - PAD, float(PracticeSwitches.BUTTON_HEIGHT))
	parent.add_child(b)
	_buttons[key] = b
	var note := UiKit.label("", 12, Palette.AMBER, true)
	UiKit.pin_width(note, LINE_WIDTH)
	note.visible = false
	parent.add_child(note)
	_notes[key] = note


## A click on the button of switch `key`: send it, and remember the toggles.
func _on_button(key: String) -> void:
	press(key, true)


## A click on the collapse arrow or the tab: open or close.
func _on_arrow() -> void:
	toggle_open(true)


## Open the panel when it is the tab and the other way round. With `remember` the choice goes into the
## settings file (the check passes false).
func toggle_open(remember: bool) -> void:
	# What the player sees decides: a panel that shows as the tab for lack of room opens (and stays
	# open, though it is tight), a panel that shows in full closes.
	if _body.visible:
		_open = false
		_force = false
	else:
		_open = true
		_force = true
	_apply_open(_open)
	if remember:
		Game.choose_practice_panel(_open)


## Is the full panel the player's choice now (the tab is the other)?
func is_open() -> bool:
	return _open


## Press the button of switch `key` (a word of PracticeSwitches.WORDS): send its order. A toggle is
## sent as the opposite of its state now. Returns "" when the order was accepted, else the reason,
## which is also written under the button for a moment. With `remember` a toggle is kept for the next
## range (the check passes false).
func press(key: String, remember: bool) -> String:
	var msg := ""
	match key:
		PracticeSwitches.FREEZE:
			var on := not world.minion_director.frozen
			msg = PracticeOrders.send(world, key, 1 if on else 0)
			if msg == "" and remember:
				Game.choose_practice_toggle(key, on)
		PracticeSwitches.CD_AUTO:
			var on2 := not world.practice_range.no_cooldowns
			msg = PracticeOrders.send(world, key, 1 if on2 else 0)
			if msg == "" and remember:
				Game.choose_practice_toggle(key, on2)
		PracticeSwitches.CAMP_NEAR:
			var id := nearest_camp()
			if id == "":
				msg = PracticeSwitches.TEXT_NO_CAMP
			else:
				msg = PracticeOrders.send(world, key, -1, id)
		_:
			msg = PracticeOrders.send(world, key)
	if msg != "":
		_note_left[key] = PracticeSwitches.REFUSAL_SECONDS
		var note: Label = _notes.get(key)
		if note != null:
			UiKit.set_text(note, msg)
			note.visible = true
	return msg


## The id of the camp nearest the centre of the screen, within PracticeSwitches.CAMP_REACH, or "" when
## none is in reach.
func nearest_camp() -> String:
	var centre := Vector2.ZERO
	if world.camera != null:
		centre = world.camera.get_screen_center_position()
	var best := ""
	var best_d := PracticeSwitches.CAMP_REACH
	for id: String in world.jungle_director.camps:
		var at: Vector2 = (world.jungle_director.camps[id]["info"] as Dictionary)["pos"]
		var d := at.distance_to(centre)
		if d <= best_d:
			best_d = d
			best = id
	return best


## Show the full panel (`show_body` true) or the tab.
func _apply_open(show_body: bool) -> void:
	if _body.visible != show_body:
		_body.visible = show_body
		custom_minimum_size = Vector2(float(PracticeSwitches.PANEL_WIDTH) if show_body else 0.0, 0.0)
		reset_size()
	UiKit.set_text(_arrow, "-" if show_body else "+")


## Does `event` ask to show or hide the panel: a fresh press of the key of the action practice_panel,
## read exactly (the O key; Shift+O is another key, and under wing preset B it is the panel's)?
static func key_toggles(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	return k.pressed and not k.echo and k.is_action("practice_panel", true)


## The practice_panel key opens or closes the panel.
func _unhandled_input(event: InputEvent) -> void:
	if key_toggles(event):
		toggle_open(true)
		get_viewport().set_input_as_handled()


## Every frame: the words, the refusal lines, the tab or the full panel, the place.
func _process(dt: float) -> void:
	_frames += 1
	_count_down_notes(dt)
	_refresh()
	var hud := get_parent() as Hud
	if hud != null and hud.me_panel != null and hud.slots != null:
		# A big panel (the hangar, the board, the help) covers the left edge: the panel steps aside
		# while one is open and comes back, as the player left it, when it closes.
		visible = not hud._any_panel_open()
		var room := measure(hud)
		_apply_open(_open and (_force or room.x >= room.y))
		_place(hud)
	else:
		_apply_open(_open)


## The band of the left edge that nothing else uses, as Vector2(top, bottom) in pixels: under the me
## panel (or, while the Admiral's command view shows, under its alert list) and above the gear slots
## (or above the command card, or above the army row in the slim display).
func _band(hud: Hud) -> Vector2:
	var top := GAP
	if hud.me_panel.visible:
		top = hud.me_panel.get_global_rect().end.y + GAP
	var bottom := hud.get_viewport_rect().size.y - GAP
	if hud.slots.visible:
		bottom = hud.slots.get_global_rect().position.y - GAP
	var cv := hud.command_view
	if cv != null and cv.is_showing():
		top = maxf(top, cv.alert_slot.get_global_rect().end.y + GAP)
		var low: Control = cv.army if cv.is_slim() else cv.card
		bottom = minf(bottom, low.get_global_rect().position.y - GAP)
	return Vector2(top, bottom)


## The room in that band and the open panel's height, in pixels: Vector2(room, height). The panel
## shows in full only when it fits (or the player opened it by hand). Both are also kept in
## last_room and last_open_height.
func measure(hud: Hud) -> Vector2:
	var band := _band(hud)
	last_room = band.y - band.x
	last_open_height = 2.0 * 8.0 + float(PracticeSwitches.BUTTON_HEIGHT) + 4.0 + _body.get_combined_minimum_size().y
	return Vector2(last_room, last_open_height)


## Put the panel on the left edge, centred in the band.
func _place(hud: Hud) -> void:
	var band := _band(hud)
	var left := hud.me_panel.get_global_rect().position.x
	var y := band.x + maxf(0.0, (band.y - band.x - size.y) * 0.5)
	var want := Vector2(left, y)
	if position != want:
		position = want


## Count down the refusal lines and hide the one whose time is up.
func _count_down_notes(dt: float) -> void:
	for key: String in _note_left.keys():
		var left := float(_note_left[key]) - dt
		if left <= 0.0:
			_note_left.erase(key)
			(_notes[key] as Label).visible = false
		else:
			_note_left[key] = left


## Rewrite the words that show a state: the toggles, the wave line, the money and its limit, and the
## cooldown section's presence.
func _refresh() -> void:
	var md := world.minion_director
	var pr := world.practice_range
	UiKit.set_text(_buttons[PracticeSwitches.FREEZE], "Freeze waves: %s" % ("Frozen" if md.frozen else "Running"))
	UiKit.set_text(_wave_line, HudTopBar.wave_line(md, world.time))
	var h := world.human
	var credits_full := h != null and h.credits >= PracticeSwitches.LIMIT
	var b_money: Button = _buttons[PracticeSwitches.MONEY]
	UiKit.set_text(b_money, "Purse full" if credits_full else "+%s credits" % _commas(PracticeSwitches.CREDITS_PER_PRESS))
	b_money.disabled = credits_full
	if _buttons.has(PracticeSwitches.TREASURY):
		var full := h != null and world.teams[h.team].treasury >= PracticeSwitches.LIMIT
		var b_t: Button = _buttons[PracticeSwitches.TREASURY]
		UiKit.set_text(b_t, "Treasury full" if full else "+%s treasury" % _commas(PracticeSwitches.TREASURY_PER_PRESS))
		b_t.disabled = full
	UiKit.set_text(_money_line, "Practice money so far: %s" % _commas(pr.money_given))
	UiKit.set_text(_buttons[PracticeSwitches.CD_AUTO], "No cooldowns: %s" % ("On" if pr.no_cooldowns else "Off"))
	var flies := world.human_role != "admiral" or (h != null and (h.state == "flying" or h.state == "dead"))
	if _cd_box.visible != flies:
		_cd_box.visible = flies
		reset_size()
