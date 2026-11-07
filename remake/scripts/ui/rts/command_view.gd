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
const PROD_H := 280.0  # PROD H (pixels or a count)
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
## The empty slot top left (the alert list's place; the tour measures it).
var alert_slot: Control
## True while the view is shown.
var _show := false
## The window size the pieces were last placed for, and the card width (to place again when they change).
var _placed := ""


## Make the pieces and remember the HUD. Hud.setup() calls this once.
func setup(h: Hud) -> void:
	hud = h
	world = h.world
	overlay = h.overlay
	team = world.human_team
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "CommandView"
	alert_slot = Control.new()
	alert_slot.name = "AlertSlot"
	alert_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alert_slot)
	strip = TopStrip.new()
	add_child(strip)
	prod = ProductionPanel.new()
	add_child(prod)
	card = CommandCard.new()
	add_child(card)
	sel = SelectionPanel.new()
	add_child(sel)
	strip.setup(self)
	prod.setup(self)
	card.setup(self)
	sel.setup(self)
	visible = false


## Is the view showing now (the HUD asks before it places the top bar, the me panel and the feed)?
func is_showing() -> bool:
	return _show


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
	if want != _show:
		_show = want
		visible = want
		if want:
			beat.prime()
		hud.layout.apply()
	if _show and beat.tick(dt):
		refresh()


## Refresh every piece from the match (the beat calls this four times a second).
func refresh() -> void:
	strip.refresh()
	prod.refresh()
	card.refresh()
	sel.refresh()


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
	if flying():
		return false
	return card.key(event)


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
	return prod.position.y + prod.size.y


## Where the top of the selection panel is when it is open (pixels from the top): the pop-up hint rides above this, so it
## never lies over the panel when a selection opens under it.
func sel_top_open() -> float:
	return sel.position.y + sel.size.y - SEL_H


## The width the card has under the home layout in force: 284 for A (a 4x3 grid), else 216.
func card_width() -> float:
	return CARD_W_A if KeyMap.preset_choice("home_layout") == "A" else CARD_W


## Put every piece in its corner for a window of size `vp` (HudLayout.apply() calls it after the bottom row is placed).
func layout(vp: Vector2) -> void:
	if not _show:
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
	_put(sel, Vector2(x0 + maxf(0.0, (x1 - x0 - w) * 0.5), bottom - h), Vector2(w, h))
	var sig := "%s|%s|%s|%s" % [str(vp), str(w), str(h), str(cw)]
	if sig != _placed:
		_placed = sig
		sel.relayout()
		card.relayout()
		prod.relayout()
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
	for pair: Array in [["strip", strip], ["alert", alert_slot], ["prod", prod], ["card", card], ["sel", sel]]:
		var c: Control = pair[1]
		out[pair[0]] = Rect2(c.position, c.size)
	return out
