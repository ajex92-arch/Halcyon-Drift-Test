class_name SeatBar
extends Control
## WHAT THIS IS: the small block of buttons right of the ship readout (T-114, mouse-only play): Dock (Launch
## while docked), Hangar, Scores (the Admiral's Board), Centre (the Admiral's Camera), Assist, Help and Menu.
## Every button is a click twin of a key and does exactly what the key does. The block is the same two columns
## by four rows in both seats; the last place (right column, bottom) is kept free for a later button.
##
## HOW IT WORKS: Hud.setup() makes one (hud.seat_bar) and Hud._refresh() calls refresh() ten times a second,
## which sets each button's words, tooltip (the key, from KeyMapText so it follows a rebind), lit look and
## disabled state for the seat. HudLayout places it (place()) at the readout's right edge plus a gap, and
## shows it only while wanted() and no big panel is open. A press on a button runs HudInput.click(action), the
## menu door; ship actions (Dock in flight, Assist) become a WorldSpeed.tap() there, so PlayerController runs its
## own lines for them on the next tick, exactly as for the key. The buttons are UiKit buttons (they never take the
## keyboard focus, act on release, and a slide off cancels). The block's own root takes the mouse too, so a click
## in a gap or on the free place never reaches the guns.
## Lit (the interface's highlight colour): Dock while the ship is within docking range of its mothership; Centre
## while it is latched; Camera while the camera follows the ship. Disabled (does nothing): Dock with no live ship
## (dead or spooling) and, for an Admiral, while docked (the hangar's own Launch button does that); Assist with no
## live ship; Scores for a pilot (the table closes only when Tab is let go in this build); and, while the pause
## menu's Look around holds the game, every button but Menu, which brings the card back.
##
## WHO USES IT: Hud (makes it, refreshes it, hover hold for the aim), HudLayout (place(), wanted()).

## The block's width (pixels): two buttons and a gap. It is as wide as the bottom row has room for at 1280: the gear slots (416), readout (430), block and minimap (300) with five gaps of 8 add up to exactly 1280.
const W := 94.0
## The block's height (pixels): four buttons and three gaps, the readout's height.
const H := 132.0
## The width (pixels) of the left and of the right column of buttons. The right column is wider: its words (Hangar,
## Camera) are the longest. Together with COL_GAP they make W.
const COL_W := [42.0, 48.0]
## One button's height (pixels).
const BTN_H := 30.0
## The gap between the two columns (pixels).
const COL_GAP := 4.0
## The gap between the rows (pixels).
const ROW_GAP := 4.0
## The text size on a button (pixels).
const FONT := 11
## The places: [id, column, row]. The id picks the button; the key behind it comes from _action_of().
const PLACES := [["dock", 0, 0], ["hangar", 1, 0], ["seat", 0, 1], ["view", 1, 1], ["assist", 0, 2], ["help", 1, 2], ["menu", 0, 3]]

## The HUD (set by setup()).
var hud: Hud
## The button of each place, by id.
var buttons := {}
## What each button shows now (a text), so refresh() only restyles a button that changed.
var _shown := {}


## Called by Hud.setup(): remember the HUD and make the seven buttons in their places.
func setup(h: Hud) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	for pl: Array in PLACES:
		var id := str(pl[0])
		var b := UiKit.button(id, func() -> void: _press(id), BTN_H)
		var col_w := float(COL_W[int(pl[1])])
		b.custom_minimum_size = Vector2(col_w, BTN_H)
		b.size = Vector2(col_w, BTN_H)
		b.position = Vector2(0.0 if int(pl[1]) == 0 else float(COL_W[0]) + COL_GAP, float(pl[2]) * (BTN_H + ROW_GAP))
		b.add_theme_font_size_override("font_size", FONT)
		b.clip_text = true
		_skin(b, false)
		add_child(b)
		buttons[id] = b
	visible = false


## Put the block's top-left corner at `p` (the HUD's pixels). Does nothing if it is there already.
func place(p: Vector2) -> void:
	if position.distance_to(p) > 0.5:
		position = p


## Should the block show: the match is being played, a human sits in a seat (not a spectator), the note box is
## closed, and the game is not held paused (except in the pause menu's Look around, where the Menu button is the
## way back). HudLayout also hides it while a big panel is open.
func wanted() -> bool:
	var w := hud.world
	if w == null or w.phase != "play" or w.human == null or w.human_role == "spectator":
		return false
	if hud._note_is_open():
		return false
	if hud.get_tree().paused:
		return _looking()
	return true


## Is the pause menu holding the game with its card hidden (Look around)?
func _looking() -> bool:
	return hud._pause_menu_active() and hud.pause_menu.looking


## The key action behind place `id` for this seat.
func _action_of(id: String) -> String:
	match id:
		"dock":
			return "dock"
		"hangar":
			return "hangar"
		"seat":
			return "admiral_board"
		"view":
			return "center_camera" if hud.world.human_role == "admiral" else "center_on_ship"
		"assist":
			return "assist_toggle"
		"help":
			return "help"
	return "pause"


## A button was pressed: do what its key does.
func _press(id: String) -> void:
	hud.router.click(_action_of(id))


## Write every button's words, tooltip, lit look and disabled state (see the header for the rules).
func refresh() -> void:
	var w := hud.world
	var admiral := w.human_role == "admiral"
	var h := w.human
	var ship: Ship = null
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		ship = h.ship
	var docked := h != null and h.state == "docked"
	var looking := _looking()
	# Dock / Launch.
	var in_range := false
	if ship != null:
		var ms := w.mothership(ship.team)
		in_range = ms != null and is_instance_valid(ms) and ms.available() and ms.hull_dist(ship.global_position) <= ms.dock_radius() \
				and w.time - ship.launched_at > 0.5
	var key_f := KeyMapText.key_of("dock")
	if docked:
		_place_text("dock", "Launch", "Launch from the dock (%s)" % key_f if not admiral else "Launch with the hangar's Launch button (%s with the hangar open)" % key_f, false, admiral or looking)
	else:
		_place_text("dock", "Dock", "Dock at the mothership (%s). It lights up when you are close enough." % key_f, in_range, ship == null or looking)
	_place_text("hangar", "Hangar", "Open the hangar (%s)" % KeyMapText.key_of("hangar"), false, looking)
	if admiral:
		_place_text("seat", "Board", "Admiral board (%s)" % KeyMapText.key_of("admiral_board"), false, looking)
		_place_text("view", "Camera", "Camera: free or follow your ship (%s)" % KeyMapText.key_of("center_camera"), not w.camera.free, looking)
	else:
		_place_text("seat", "Scores", "Score table: hold %s (a click for it comes in a later build)" % KeyMapText.key_of("admiral_board"), false, true)
		_place_text("view", "Centre", "Keep the camera on your ship; click again to let go (%s)" % KeyMapText.key_of("center_on_ship"), w.camera.centre_latched, looking)
	_place_text("assist", "Assist", "Flight assist on or off (%s)" % KeyMapText.key_of("assist_toggle"), false, ship == null or looking)
	_place_text("help", "Help", "Help (%s)" % KeyMapText.key_of("help"), false, looking)
	var menu_tip := "Bring the pause menu back (Esc)" if looking else "Pause menu: speed, full screen, controls (%s)" % KeyMapText.key_of("pause")
	_place_text("menu", "Menu", menu_tip, false, false)


## Set one button: its words, tooltip, lit look and whether it does nothing (disabled).
func _place_text(id: String, text: String, tip: String, lit: bool, off: bool) -> void:
	var b: Button = buttons[id]
	var sig := "%s|%s|%s|%s" % [text, tip, lit, off]
	if _shown.get(id, "") == sig:
		return
	_shown[id] = sig
	b.text = text
	b.tooltip_text = tip
	# A button grows to the room its first word asked for and never shrinks back: put it at its own size.
	b.reset_size()
	b.disabled = off
	_skin(b, lit and not off)


## The button's look: the plain button, or the highlight colour filled when lit. Side margins are 1 pixel so a
## word of 11 pixels fits its column.
func _skin(b: Button, lit: bool) -> void:
	var hi := UiKit.accent()
	var look := {
		"normal": _box(hi if lit else Palette.INK, hi if lit else Palette.LINE),
		"hover": _box(hi.lightened(0.12) if lit else Palette.INK, hi),
		"pressed": _box(hi.darkened(0.15) if lit else Palette.PANEL, hi),
		"hover_pressed": _box(hi.darkened(0.15) if lit else Palette.PANEL, hi),
		"disabled": _box(Palette.with_alpha(Palette.INK, 0.6), Palette.with_alpha(Palette.LINE, 0.6)),
		"focus": StyleBoxEmpty.new(),
	}
	for sb_name: String in look:
		b.add_theme_stylebox_override(sb_name, look[sb_name])
	var text_col := Palette.VOID if lit else Palette.ICE
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, text_col)


## A flat box with 1 pixel side margins and 2 pixel top and bottom margins.
func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := UiKit.box(bg, border, 0)
	s.content_margin_left = 1.0
	s.content_margin_right = 1.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	return s
