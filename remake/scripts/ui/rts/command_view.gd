class_name CommandView
extends Control
## WHAT THIS IS: the Admiral's command view: the screen the human Admiral plays on while docked (and while flying
## their own ship, RtsUiCalls.COMMAND_VIEW_WHILE_FLYING). It is the design's "A1 Corners": separate see-through
## pieces in the corners with the map open in the middle: the strip along the top (TopStrip), the production
## panel top right (ProductionPanel, folds to its header), an empty slot top left for the alert list (a later
## stage fills it), the command card bottom left (CommandCard), the selection panel bottom centre
## (SelectionPanel) and, as before, the minimap and the seat bar bottom right.
##
## HOW IT WORKS: a Control the size of the HUD that lets the mouse through; its pieces take the mouse where they are.
## It shows only for the human Admiral, in a match being played, with no big panel (board, hangar, help, pause
## menu) open (the board lies over the view). A pilot and a spectator never see it. Every 0.25 s (RtsBeat) the
## pieces refresh from the match; every frame it follows the window: HudLayout.apply() calls layout(), which puts
## each piece in its corner (the card above the key line, the selection panel between the card and the seat bar or
## the minimap, above the ship readout while flying). The view also owns `yard`, the player's choices for new
## ships (size, repeat, rally), and hands the same Dictionary to the Admiral board's old Yard tab, so both agree
## until that tab goes. The card's keys come through key(), called by HudInput before the other keys.
## The top bar is moved TOP_DROP pixels down under the strip while the view shows (HudLayout), the Admiral's lines
## of the "me" panel are hidden (the strip has them) and the kill feed moves under the production panel.
## While the Admiral flies with the view closed (field mode, FieldMode.active(); RtsUiCalls.FIELD_MODE_SLIM) the view shows its
## slim display instead: only the strip, the alert feed with its first RtsUiCalls.FIELD_ALERT_ROWS rows, the group chips of the
## army row (on the line above the key line, at the left) and the minimap. The production panel, the card and the selection
## panel are hidden and not refreshed (the yard, the card's state and CardState.snapshot keep working), and a group card's double
## click does not centre the camera (it centres only where a selection may move it). Flying with the view open (mode 3) or docked
## the full view shows. _process() tracks the change and asks HudLayout.apply() to place everything again.
##
## WHO USES IT: Hud (makes it in setup()), HudLayout (layout(), is_showing(), prod_bottom()), HudInput (key()),
## HudPanels (the yard); tests/rts_tour.gd reads the pieces and their rectangles.

## The height of the strip along the top (pixels).
const STRIP_H := 24.0
## The command card's height and its width in layouts B and C (the 3x3 grid) and A (the 4x3 grid).
const CARD_H := 228.0
const CARD_W := 216.0  # CARD W (pixels or a count)
const CARD_W_A := 284.0  # CARD W A (pixels or a count)
## The selection panel's widest and its height with a selection and with none (the hint line).
const SEL_W := 630.0
const SEL_H := 112.0  # SEL H (pixels or a count)
const SEL_HINT_H := 24.0  # SEL HINT H (pixels or a count)
## The production panel's width and height open, and its height folded (the header only).
const PROD_W := 280.0
const PROD_H := 280.0 + ProductionPanel.JOIN_ROW_H  # PROD H (pixels or a count): the footer's second row (auto-join) makes it taller
const PROD_FOLD_H := 26.0  # PROD FOLD H (pixels or a count)
## The alert slot's size (the alert list of a later stage goes here).
const ALERT_W := 220.0
const ALERT_H := 120.0  # ALERT H (pixels or a count)
## How far (pixels) the top bar moves down under the strip while the view shows.
const TOP_DROP := 30.0
## The space between pieces and the window edge (pixels).
const GAP := 8.0

## The HUD this view belongs to (set by setup()).
var hud: Hud
## The match (set by setup()).
var world: World
## The Admiral's map layer: selection and orders (set by setup()).
var overlay: CommandOverlay
## The team the Admiral commands.
var team := Rules.HALCYON
## The beat that refreshes the pieces four times a second.
var beat := RtsBeat.new()
## The player's choices for new ships, shared with the board's old Yard tab: "count" (ships in a squadron, 1 to 3),
## "repeat" (buy again when done) and "rally" ("mothership", "lane" or "point").
var yard := {"count": 3, "repeat": false, "rally": "mothership"}
## The pieces.
var strip: TopStrip
var card: CommandCard  # the card
var sel: SelectionPanel  # the sel
var prod: ProductionPanel  # the prod
## The army row above the selection panel (the cards of the groups, the hulls and the idle squadrons).
var army: ArmyCards
## The Admiral's eight control groups (screen state, kept for the whole match: they survive Tab, docking and launching).
var groups := Groups.new()
## The idle keys (I, Ctrl+I) and the Idle card's clicks.
var tools := SelectionTools.new()
## The empty slot top left (the alert list's place; the tour measures it).
var alert_slot: Control
## The alert feed that fills the slot (AlertFeed).
var alert_feed: AlertFeed
## True while the view is shown.
var _show := false
## True while the view shows its slim display (field mode: FieldMode.active() while the view is shown).
var _slim := false
## The window size the pieces were last placed for, and the card width (to place again when they change).
var _placed := ""


## Make the pieces and remember the HUD. Hud.setup() calls this once.
func setup(h: Hud) -> void:
	hud = h
	world = h.world
	overlay = h.overlay
	team = world.human_team
	groups.setup(world, overlay, team)
	tools.setup(world, overlay, team)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "CommandView"
	alert_slot = Control.new()
	alert_slot.name = "AlertSlot"
	alert_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alert_slot)
	alert_feed = AlertFeed.new()
	alert_slot.add_child(alert_feed)
	alert_feed.setup(self)
	strip = TopStrip.new()
	add_child(strip)
	prod = ProductionPanel.new()
	add_child(prod)
	card = CommandCard.new()
	add_child(card)
	sel = SelectionPanel.new()
	add_child(sel)
	army = ArmyCards.new()
	add_child(army)
	strip.setup(self)
	prod.setup(self)
	card.setup(self)
	sel.setup(self)
	army.setup(self)
	visible = false


## Is the view showing now (the HUD asks before it places the top bar, the me panel and the feed)?
func is_showing() -> bool:
	return _show


## Is the view showing its slim display (field mode: flying with the view closed)? Only the strip, the first alerts, the group
## chips and the minimap show then; the production panel, the card and the selection panel are hidden and not refreshed.
func is_slim() -> bool:
	return _slim


## Should the view show: the human Admiral in a match being played, with no big panel open, the note box closed
## and the match not over (and, with COMMAND_VIEW_WHILE_FLYING off, docked).
func _wants() -> bool:
	if world.human_role != "admiral" or world.phase != "play":
		return false
	if hud.end_screen != null or hud._any_panel_open() or hud._note_is_open():
		return false
	return RtsUiCalls.COMMAND_VIEW_WHILE_FLYING or world.teams[team].admiral_docked


## Is the Admiral out flying their own ship (the grid keys are then the pilot's)?
func flying() -> bool:
	return not world.teams[team].admiral_docked


## Every frame: show or hide with the match state, and refresh the pieces on the beat.
func _process(dt: float) -> void:
	if world == null:
		return
	var want := _wants()
	var slim := want and FieldMode.active(world, team)
	if want != _show or slim != _slim:
		var came := want and not _show
		var flipped := want and not came and slim != _slim
		_show = want
		_slim = slim
		visible = want
		# The three pieces the slim display drops are hidden with it (and not refreshed), and shown again with the full view.
		for piece: Control in [prod, card, sel]:
			piece.visible = not slim
		if came:
			beat.prime()
		hud.layout.apply()
		# A flip between the two displays refreshes at once: the pieces coming back were not refreshed in the slim display, and
		# the group chips fit their new room.
		if flipped:
			refresh()
			alert_feed.refresh()
	if _show and beat.tick(dt):
		refresh()


## Refresh every piece from the match (the beat calls this four times a second). The slim display refreshes only the strip
## and the group chips: the hidden production panel, card and selection panel are not worked out.
func refresh() -> void:
	groups.sync()
	strip.refresh()
	if not _slim:
		prod.refresh()
		card.refresh()
		sel.refresh()
	army.refresh()


## A key press for the card: true when the page in force owns the key (HudInput then marks it used). Only while the
## view shows, docked, and not in the pause.
func key(event: InputEvent) -> bool:
	# Asked live, not from the last frame: with a big panel open (the hangar, whose F launches) the card keys are not the card's.
	if not _show or hud._any_panel_open() or hud._note_is_open():
		return false
	# M selects every squadron (it works while flying too: it only changes the selection).
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and event.is_action("all_squadrons", true):
		overlay.select_all_squadrons()
		return true
	if select_key(event):
		return true
	if flying():
		return false
	return card.key(event)


## The selection keys of the awareness stage: F1 to F8 (a tap selects, Ctrl sets, Shift adds, a second tap centres the
## camera), I (the next idle squadron, centred) and Ctrl+I (every idle squadron). They work wherever a selection works:
## docked, or flying in mode 3 (the view or the board open); flying with both closed a group is only picked (the camera stays on the
## ship) and I stays the pilot's key. HudInput also asks this when the view itself is hidden under the board. True when
## the key was one of them.
func select_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return false
	if world.human_role != "admiral" or world.phase != "play" or hud._note_is_open():
		return false
	if hud._any_panel_open() and not world.mode3():
		return false
	var k := event as InputEventKey
	if groups.key(k, overlay.select_allowed()):
		return true
	if _idle_key(k):
		return true
	return _research_key(k)


## U by the key map's row research_board (home mode docked, flying_board mode with the board or the view open while flying; only
## where a selection works): it opens the Admiral board on the Research tab, and closes the board when it is already open there.
## A pilot's U is the wing's own key and is not touched (the row exists only in the Admiral's modes). True when the key was it.
func _research_key(k: InputEventKey) -> bool:
	if not overlay.select_allowed():
		return false
	var mode := "flying_board" if flying() else "home"
	for text: String in KeyMap.effective_keys(mode, "research_board"):
		var ev := KeyCodes.make_event(text)
		if ev != null and ev.is_match(k, true):
			if hud.board != null and hud.board.visible and hud.board.tab == "Research":
				hud.panels.toggle_board()
			else:
				hud.panels.open_board_at("Research")
			return true
	return false


## I and Ctrl+I by the key map's rows idle_next and idle_all (home mode docked, flying_board mode with the board open
## while flying; only where a selection works).
func _idle_key(k: InputEventKey) -> bool:
	if not overlay.select_allowed():
		return false
	var mode := "flying_board" if flying() else "home"
	for id: String in ["idle_all", "idle_next"]:
		if id == "idle_all" and mode != "home":
			continue
		for text: String in KeyMap.effective_keys(mode, id):
			var ev := KeyCodes.make_event(text)
			if ev != null and ev.is_match(k, true):
				if id == "idle_all":
					tools.all()
				else:
					tools.next(true)
				return true
	return false


## Esc with nothing armed, no panel open: close an open pop-out, else empty the selection (and the Add toggle). True when
## it did something, so the pause menu does not open on the same press.
func cancel_key() -> bool:
	if not _show:
		return false
	if card.close_list():
		return true
	if not overlay.sel_squads.is_empty() or overlay.sel_base or overlay.add_mode:
		overlay.clear_selection()
		overlay.add_mode = false
		return true
	return false


## Where the production panel ends (pixels from the top), for the kill feed to start under it.
func prod_bottom() -> float:
	if _slim:
		return strip.position.y + strip.size.y
	return prod.position.y + prod.size.y


## Where the top of the selection panel is when it is open (pixels from the top): the pop-up hint rides above this, so it
## never lies over the panel when a selection opens under it. In the slim display it is the top of the group chips.
func sel_top_open() -> float:
	if _slim:
		return army.position.y
	return sel.position.y + sel.size.y - SEL_H - ArmyCards.ROOM


## The width the card has under the home layout in force: 284 for A (a 4x3 grid), else 216.
func card_width() -> float:
	return CARD_W_A if KeyMap.preset_choice("home_layout") == "A" else CARD_W


## Put every piece in its corner for a window of size `vp` (HudLayout.apply() calls it after the bottom row is placed).
func layout(vp: Vector2) -> void:
	if not _show:
		return
	if _slim:
		_layout_slim(vp)
		return
	_put(strip, Vector2.ZERO, Vector2(vp.x, STRIP_H))
	_put(alert_slot, Vector2(GAP, STRIP_H + 4.0), Vector2(ALERT_W, ALERT_H))
	var ph := PROD_FOLD_H if prod.folded else PROD_H
	_put(prod, Vector2(vp.x - GAP - PROD_W, STRIP_H + 4.0), Vector2(PROD_W, ph))
	# The card sits above the key line (and the gear slots while a ship is out).
	var key_h := hud.slots.get_combined_minimum_size().y
	var cw := card_width()
	var base := vp.y - GAP - key_h - 4.0
	_put(card, Vector2(GAP, base - CARD_H), Vector2(cw, CARD_H))
	# The selection panel stands on the same line as the card (above the key line, which is wider than the card), from the
	# card to whatever stands in its band at the right (the seat bar, the minimap), and above the ship readout while one shows.
	var bottom := minf(base, vp.y - HudLayout.READOUT_ROOM) if hud.status.visible else base
	var h := sel.wanted_size(SEL_W).y
	var x0 := GAP + cw + GAP
	var x1 := vp.x - GAP
	for c: Control in [hud.seat_bar, hud.minimap]:
		if c.visible:
			var r := Rect2(c.global_position, c.size)
			if r.end.y > bottom - h and r.position.y < bottom:
				x1 = minf(x1, r.position.x - GAP)
	var w := clampf(x1 - x0, 260.0, SEL_W)
	var sx := x0 + maxf(0.0, (x1 - x0 - w) * 0.5)
	_put(sel, Vector2(sx, bottom - h), Vector2(w, h))
	# The army row stands on the line above the selection panel's full height, so it never moves with the selection; it keeps
	# clear of the seat bar and the minimap if they reach up into its band.
	var ay := bottom - SEL_H - (ArmyCards.ROOM - ArmyCards.ROW_H) - ArmyCards.ROW_H
	var aw := w
	for c: Control in [hud.seat_bar, hud.minimap]:
		if c.visible:
			var r := Rect2(c.global_position, c.size)
			if r.end.y > ay and r.position.y < ay + ArmyCards.ROW_H and r.position.x > sx:
				aw = minf(aw, r.position.x - GAP - sx)
	_put(army, Vector2(sx, ay), Vector2(maxf(aw, 120.0), ArmyCards.ROW_H))
	var sig := "%s|%s|%s|%s" % [str(vp), str(w), str(h), str(cw)]
	if sig != _placed:
		_placed = sig
		sel.relayout()
		card.relayout()
		prod.relayout()
		strip.relayout()


## The slim display's layout (field mode): the strip along the top, the alert slot under it at the left (the header and
## RtsUiCalls.FIELD_ALERT_ROWS rows), and the group chips on the line above the key line at the left, as wide as the room up to
## the ship readout (and the seat bar and the minimap, when they stand in that band). The production panel, the card and the
## selection panel are hidden, so they are not placed.
func _layout_slim(vp: Vector2) -> void:
	_put(strip, Vector2.ZERO, Vector2(vp.x, STRIP_H))
	_put(alert_slot, Vector2(GAP, STRIP_H + 4.0), Vector2(ALERT_W, AlertFeed.HEAD_H + float(RtsUiCalls.FIELD_ALERT_ROWS) * AlertFeed.ROW_H))
	var key_h := hud.slots.get_combined_minimum_size().y
	var ay := vp.y - GAP - key_h - 4.0 - ArmyCards.ROW_H
	var x1 := vp.x - GAP
	for c: Control in [hud.status, hud.seat_bar, hud.minimap]:
		if c.visible:
			var r := Rect2(c.global_position, c.size)
			if r.end.y > ay and r.position.y < ay + ArmyCards.ROW_H and r.position.x > GAP:
				x1 = minf(x1, r.position.x - GAP)
	_put(army, Vector2(GAP, ay), Vector2(maxf(x1 - GAP, 120.0), ArmyCards.ROW_H))
	var sig := "slim|%s|%s" % [str(vp), str(army.size)]
	if sig != _placed:
		_placed = sig
		strip.relayout()


## Put control `c` at `pos` with `sz` (only when it differs).
func _put(c: Control, pos: Vector2, sz: Vector2) -> void:
	if c.position.distance_to(pos) > 0.5:
		c.position = pos
	if c.size.distance_to(sz) > 0.5:
		c.size = sz


## The rectangle of each piece (HUD pixels), for the tour's report: {"strip", "alert", "prod", "card", "sel"}.
func rects() -> Dictionary:
	var out := {}
	for pair: Array in [["strip", strip], ["alert", alert_slot], ["prod", prod], ["card", card], ["sel", sel], ["army", army]]:
		var c: Control = pair[1]
		out[pair[0]] = Rect2(c.position, c.size)
	return out
