class_name Hud
extends Control
## WHAT THIS IS: the HUD ("heads-up display"): everything drawn on top of
## the game during a match, such as the clock, your credits, the kill feed,
## your ship's shields and the minimap. It is also the screen manager: it
## decides which big panel (hangar, Admiral board, help...) is open and what
## the menu keys do.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud.tscn: one node
## ("Hud") that covers the whole window, lets mouse clicks pass through to
## the game, and keeps running while the game is paused (so the pause
## message and the P key still work). Inside it are the widgets (a
## "widget": one small, self-contained part of the screen, each with its
## own scene and script), in this order: later ones draw on top of earlier
## ones.
##   TopBar      top centre: HudTopBar: clock, next minion wave, both
##               motherships' hull bars and how many turrets each side
##               has per lane
##   MePanel     top left: HudMePanel: you (credits, or the Admiral's
##               treasury), K/D/A, ship, and a short log of what just
##               paid you
##   Feed        top right, under the top bar: HudFeed: the kill / event
##               feed
##   Banner      centre: HudBanner: big messages (respawn timer, docked, a
##               turret targeting you, mothership trouble, the armed
##               Admiral map tool, pause)
##   Toast       bottom centre: HudToast: short pop-up hints
##   ShipStatus  bottom centre, 8 pixels up: shields, hull, energy,
##               routing, ability (it draws itself)
##   Minimap     bottom right, 8 pixels in from both edges (it draws
##               itself)
##   Slots       bottom left: HudSlots: the 6 gear slots and a reminder of
##               the keys
##   Alarm       over the whole screen, hidden until needed: HudAlarm: the
##               sound and the edge marker that warn you a Bomber's run is
##               aimed at your ship (made in code by setup())
##   WingStrip   a child of ShipStatus, just above it: the pilot's wing, one chip
##               for each wingman and a Wing button (WingStrip; made in code by
##               setup(); hidden without a wing)
##   SeatBar     right of ShipStatus: the block of buttons that are click twins of keys
##               (Dock, Hangar, Scores or Board, Centre or Camera, Assist, Help, Menu;
##               SeatBar; made in code by setup())
##   WingWheel   the order wheel, over the whole HUD while it is open (WingWheel;
##               made in code by setup())
## The wing's marks on the map (WingMarks) are a child of the World, like the overlay.
## _ready() gives the HUD the game's look (UiKit.make_theme()). setup()
## then sets the interface's highlight colour to the human's team (amber for
## Aurelian and for a spectator, red for Vhorr: UiKit.set_accent_team(), and a
## new theme if that changed the colour) and wires everything up: it makes the
## Admiral's map-tool layer, tells
## the widgets which world they show, and listens to game news from
## Events. (A "signal" is a message a script sends out; any other script
## can "connect" a function to it, and that function then runs every time
## the message is sent.) Each piece of news goes to the widget that shows
## it. Every 0.1 seconds (10 times a second) _refresh() tells every widget
## to update its text.
## Big panels: Hangar (B), Admiral board (Tab, admiral), Scoreboard (hold
## Tab, pilots), Help (H), the Controls page (from the help's Keys page), the
## Pause menu (P or Esc) and the End screen. They are made from their own
## scenes when first needed. HudPanels keeps only one of them open at a
## time. HudLayout keeps the pieces out of each other's way: it moves the
## top bar, the gear slots and the ship readout aside when the window is
## narrow, and hides the pieces a big panel would cover while it is open.
## HudInput routes the keys: Esc closes panels, cancels a map tool, or (with
## nothing to close) opens the pause menu, C switches the Admiral's camera
## between free and following their ship, P opens the pause menu (or resumes),
## X and the wing keys give a pilot's wing orders, F launches when docked (in
## flight, PlayerController uses F to dock instead), and F9 opens the note box
## (NoteBox: it pauses the match, and Enter saves a one-line note with a
## screenshot). The note box is made the first time F9 is pressed. DESIGN.md
## A15 shows the layout.
## Mouse-only play (T-114): the buttons, the readout and a kit gear slot call router.click(), which does
## what the key does. Every frame _process() also sets World.ui_hold: true while the pointer is on one of
## them and the player is not firing, which keeps the ship's aim still (_pointer_on_buttons()). The hold also starts a
## fraction of a second BEFORE the pointer arrives at the ship readout (_pointer_nears_readout(): the pointer's smoothed
## velocity carries it onto the readout within AIM_HOLD_LEAD_S), so the hull does not turn toward the readout on the way.
##
## WHO USES IT: main.gd loads scenes/ui/hud.tscn and calls setup(world).
## tests/ui_tour.gd finds the "Hud" node and uses hud.hangar, hud.board,
## hud.overlay, _toggle_help(), _toggle_pause_menu(), _show_scoreboard() and
## _toggle_board(); tests/note_check.gd uses hud.note_box. Its parts: the widgets
## above, HudPanels (opens and closes panels) and HudInput (menu keys).

## The end-of-match screen (who won, totals, top pilots).
const END_SCENE := preload("res://scenes/ui/end_screen.tscn")
## The Admiral's map-tool layer (drawn in the game world, not on the HUD).
const OVERLAY_SCENE := preload("res://scenes/ui/command_overlay.tscn")
## The note box (F9).
const NOTE_SCENE := preload("res://scenes/ui/note_box.tscn")
## The aim hold starts this many seconds before the pointer reaches the ship readout, when it is heading straight for it
## (the shield-aim-hold change; 0 gives the old behaviour: the hold starts when the pointer is on the readout).
const AIM_HOLD_LEAD_S := 0.4
## The slowest pointer speed (pixels a second) that counts as heading for the readout: a slower pointer is resting or
## drifting, and its aim is not held before it is on the readout.
const AIM_HOLD_MIN_SPEED := 90.0
## How long (seconds) the pointer's velocity is smoothed over, so one jittery frame does not start or stop the hold.
const AIM_VEL_SMOOTH_S := 0.05

## The pop-up text shown when one of the human Admiral's orders worked,
## keyed by the order's name (as sent in Events.admiral_result). Orders not
## listed here succeed silently. A failed order shows AdmiralCommand's own
## reason instead.
const RESULT_OK := {"facility": "Module queued.", "research": "Research queued.", "turret": "Turret under construction.", "post": "Defense post being rebuilt.",
	"bay": "Repair bay launched: it will fly there and anchor.", "ward": "Ward launched.", "waypoint": "Rally waypoint set.",
	"move": "The mothership is moving.", "drone": "Mining drone queued.", "produce": "Queued in the yard."}

## The game world this HUD shows (set by setup()).
var world: World
## The Admiral's map tools (CommandOverlay). It is a child of World, not of
## the HUD, so it can draw in world positions.
var overlay: CommandOverlay
## The minimap in the bottom-right corner.
@onready var minimap: Minimap = $Minimap
## The ship readout at the bottom centre (hidden while you have no ship).
@onready var status: ShipStatus = $ShipStatus
## The hangar panel (B). Made the first time it opens; null until then.
var hangar: Hangar = null
## The Admiral board (Tab, Admiral only). Made on first use; null until then.
var board: AdmiralBoard = null
## The pilots' scoreboard (hold Tab). Made on first use; null until then.
var scoreboard: Scoreboard = null
## The help pages (H). Made on first use; null until then.
var help: HelpPanel = null
## The Controls page (opened from the help's Keys page). Made on first use; null until then.
var controls: ControlsPage = null
## The pause menu (P or Esc). Made on first use; null until then.
var pause_menu: PauseMenu = null
## The end-of-match screen. Made when the match ends; null until then.
var end_screen: EndScreen = null
## The match series (MatchSeries) that main.gd made for this match, or null: the end screen gets it
## for its graph.
var series: MatchSeries = null
## The note box (F9). Made the first time the key is pressed; null until then.
var note_box: NoteBox = null

## Widget: clock, next wave, mothership bars, turret counts (top centre).
@onready var top_bar: HudTopBar = $TopBar
## Widget: your name, credits, K/D/A and earnings log (top left).
@onready var me_panel: HudMePanel = $MePanel
## Widget: the kill / event feed (top right).
@onready var feed: HudFeed = $Feed
## Widget: the big centre messages.
@onready var banner: HudBanner = $Banner
## Widget: the short pop-up hint box (see toast()).
@onready var toast_box: HudToast = $Toast
## Widget: the gear slots and key reminder (bottom left).
@onready var slots: HudSlots = $Slots
## Part: opens and closes the big panels (only one at a time).
var panels: HudPanels
## Part: keeps the HUD's pieces out of each other's way.
var layout: HudLayout
## Part: decides what each menu key does.
var router: HudInput
## The pilot's wing strip above the ship readout (a child of the readout; hidden without a wing).
var wing_strip: WingStrip
## The block of buttons right of the ship readout (SeatBar: Dock, Hangar, Scores or Board, Centre or Camera, Assist, Help, Menu).
var seat_bar: SeatBar
##The pilot's order wheel (hidden until the order key is held or the Wing button is clicked).
var wing_wheel: WingWheel
## The marks the wing puts on the map (a child of the World, like the overlay).
var wing_marks: WingMarks
## The Admiral's command view (the strip, the card, the selection and production panels); shows for the human
## Admiral only (made in code by setup()).
var command_view: CommandView

## Seconds until the next full refresh (counts down from 0.1).
var _t := 0.0
## Where the pointer was at the last frame (window pixels).
var _ptr_last := Vector2.ZERO
## True once the pointer has been seen at a frame (the first frame has no velocity yet).
var _ptr_seen := false
## The pointer's velocity (pixels a second), smoothed over AIM_VEL_SMOOTH_S.
var _ptr_vel := Vector2.ZERO
## The pointer's place from the last mouse-motion event the HUD saw (the viewport's own mouse position does not follow
## the events a test pushes).
var _ptr_event := Vector2.ZERO
## True once the HUD has seen a mouse-motion event.
var _ptr_event_seen := false


## Called once when the node joins the scene: give the HUD (and every
## widget inside it) the game's look. Each widget picks its own named look
## from this theme.
func _ready() -> void:
	theme = UiKit.make_theme()
	RtsTheme.extend(theme)


## Wire the HUD to world `w` and start listening to game news. main.gd
## calls this once, right after adding the HUD to the screen.
func setup(w: World, match_series: MatchSeries = null) -> void:
	world = w
	series = match_series
	# Step 0: the highlight colour is the human's team's (a spectator's World
	# says Aurelian). The panels made from here on take it from UiKit, and the
	# theme made in _ready() is made again if it had another team's.
	if UiKit.accent_team != w.human_team:
		UiKit.set_accent_team(w.human_team)
		theme = UiKit.make_theme()
		RtsTheme.extend(theme)
	# Step 1: the Admiral's map-tool layer lives in the game world.
	overlay = OVERLAY_SCENE.instantiate()
	world.add_child(overlay)
	overlay.setup(world)
	# The wing's marks on the map sit just under the overlay.
	wing_marks = WingMarks.new()
	world.add_child(wing_marks)
	wing_marks.setup(self)
	layout = HudLayout.new(self)
	panels = HudPanels.new(self)
	resized.connect(layout.apply)
	router = HudInput.new(self)
	# The wing strip rides on the ship readout (so it follows the layout's sideways shift and hides with it);
	# the order wheel covers the whole HUD while it is open.
	wing_strip = WingStrip.new()
	status.add_child(wing_strip)
	wing_strip.setup(self)
	# The seat bar (the button block right of the readout) and the readout's and the gear slots' clicks go
	# through the router. The bar is made before the order wheel, so the wheel draws over it.
	status.hud = self
	slots.hud = self
	seat_bar = SeatBar.new()
	add_child(seat_bar)
	seat_bar.setup(self)
	# The Admiral's command view sits over the map under the order wheel (made for every seat; it shows for the Admiral only).
	command_view = CommandView.new()
	add_child(command_view)
	command_view.setup(self)
	wing_wheel = WingWheel.new()
	add_child(wing_wheel)
	wing_wheel.setup(self)
	# Step 2: tell the widgets (already in the scene) what they show.
	me_panel.world = w
	feed.world = w
	banner.hud = self
	toast_box.hud = self
	minimap.setup(world, overlay)
	# The warning for the pilot a Bomber is aiming at (a sound and an edge marker).
	# It is the last child, so it draws on top, and it stays hidden until needed.
	var alarm := HudAlarm.new()
	add_child(alarm)
	alarm.setup(world)
	# Step 3: listen to game news. Each signal goes to the widget that
	# shows it (the order of these lines is kept from the original code).
	Events.feed.connect(feed.on_feed)
	Events.toast.connect(toast)
	Events.unit_killed.connect(feed.on_unit_killed)
	Events.turret_destroyed.connect(feed.on_turret_destroyed)
	Events.site_state_changed.connect(feed.on_site_state)
	Events.research_done.connect(feed.on_research_done)
	Events.facility_done.connect(feed.on_facility_done)
	Events.credits_earned.connect(me_panel.on_credits)
	Events.respawned.connect(_on_respawned)
	Events.admiral_result.connect(_on_admiral_result)
	Events.rts_event.connect(_on_rts_event)
	Events.match_over.connect(_on_match_over)
	# Step 4: a first hint. Pilots start in the hangar to pick a ship.
	if world.human_role == "pilot":
		_open_hangar()
		toast("Pick a ship in the hangar and launch. %s explains everything." % KeyMapText.key_of("help"))
	elif world.human_role == "admiral":
		toast("You command %s. %s opens the Admiral board; %s explains everything." % [Rules.TEAM_DISPLAY[world.human_team], KeyMapText.key_of("admiral_board"), KeyMapText.key_of("help")])
	_refresh()


# --- panels (the real code lives in HudPanels) --------------------------------

## Open the hangar. Forwards to HudPanels.open_hangar().
func _open_hangar() -> void:
	panels.open_hangar()


## Show or hide the Admiral board. Forwards to HudPanels.toggle_board().
func _toggle_board() -> void:
	panels.toggle_board()


## Show (`on` = true) or hide the scoreboard. Forwards to
## HudPanels.show_scoreboard().
func _show_scoreboard(on: bool) -> void:
	panels.show_scoreboard(on)


## Show or hide the help pages. Forwards to HudPanels.toggle_help().
func _toggle_help() -> void:
	panels.toggle_help()


## Show or hide the Controls page. Forwards to HudPanels.toggle_controls().
func _toggle_controls() -> void:
	panels.toggle_controls()


## Open the pause menu (and pause the game), or end the pause if the menu holds
## it. Forwards to HudPanels.toggle_pause_menu().
func _toggle_pause_menu() -> void:
	panels.toggle_pause_menu()


## Is the game being held paused by the pause menu (also while the help pages
## are open over it)?
func _pause_menu_active() -> bool:
	return pause_menu != null and pause_menu.active


## Hide every big panel except `keep` (null hides them all). Forwards to
## HudPanels.close_others().
func _close_others(keep: Control) -> void:
	panels.close_others(keep)


## Is any big panel showing? Forwards to HudPanels.any_open().
func _any_panel_open() -> bool:
	return panels.any_open()


# --- the note key (the real code lives in NoteBox) ------------------------------

## Open the note box (F9), making it first if needed. It pauses the match
## until the note is saved or cancelled.
func _open_note() -> void:
	if note_box == null:
		note_box = NOTE_SCENE.instantiate()
		add_child(note_box)
	note_box.open(world)


## Is the note box open? (HudInput ignores the keys while it is, and the big
## centre message stops saying how to resume.)
func _note_is_open() -> bool:
	return note_box != null and note_box.is_open()


# --- input ---------------------------------------------------------------------

## Godot sends here every key the game didn't use. HudInput.handle()
## decides what each menu key does.
func _unhandled_input(event: InputEvent) -> void:
	router.handle(event)


# --- events ----------------------------------------------------------------------

## Pop up a short hint for 3.5 seconds (see HudToast). Connected to
## Events.toast, so any script can show one. Not once the match is over:
## the end screen has the whole window. With `danger` the hint is a refusal: danger
## colour and the danger triangle.
func toast(text: String, danger: bool = false) -> void:
	if end_screen == null:
		toast_box.show_text(text, danger)


# --- the pilot's wing (the real code lives in SquadOrders, WingStrip and WingWheel) -----------

## Can the human give their wing an order now: a pilot with a live ship and a wing, the match
## being played, no board and no big panel open?
func wing_ready() -> bool:
	var h := world.human
	if h == null or world.human_role != "pilot" or world.phase != "play" or world.board_open or _any_panel_open():
		return false
	if h.ship == null or not is_instance_valid(h.ship) or not h.ship.alive:
		return false
	var lead := Squads.lead_record(world, h.team, h.slot)
	return lead != null and Squads.wing_alive(world, lead.wing_id)


## The world point under the reticle now (the pilot's aim point), or under the mouse with no ship.
func wing_aim() -> Vector2:
	var h := world.human
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		return h.ship.controls.aim_point
	return world.mouse_world()


## Give the human pilot's wing the gesture `name` ("tap", "follow", "cover", "attack", "guard", "hold",
## "regroup", "formation", "fire", "next_formation", "next_fire"; `arg` is a formation or fire value) with
## the reticle at `aim` (the aim point now when it is Vector2.INF). The one door the tap, the wheel and the
## key preset use. A refusal is shown at once as a danger pop-up; what was carried out is confirmed when it
## is (wing_event). Returns the refusal text or "".
func wing_command(name: String, arg: int = 0, aim: Vector2 = Vector2.INF) -> String:
	var h := world.human
	if h == null or world.human_role != "pilot":
		return ""
	var g := SquadOrders.gesture(world, h, name, arg, wing_aim() if aim == Vector2.INF else aim)
	var sent := SquadOrders.send(world, g)
	var why := str(sent["text"])
	if why != "":
		toast(why, true)
	return why


## The Wing button was clicked: open the order wheel under the mouse as a click wheel, or close it.
func wing_wheel_toggle() -> void:
	if wing_wheel.is_open:
		wing_wheel.close()
	elif wing_ready():
		wing_wheel.open_at(get_viewport().get_mouse_position(), wing_aim(), true)


## A happening on the event stream (Events.rts_event): the pop-ups of the human pilot's wing. An order of
## theirs that was carried out is confirmed (and the strip pulses once); one refused when it was carried
## out is explained (a refusal at the moment of sending was shown by wing_command()); the wing going home,
## launching and a wingman lost say so. A repeated order says nothing.
func _on_rts_event(ev: Dictionary) -> void:
	var h := world.human
	if h == null or world.human_role != "pilot" or int(ev.get("team", -1)) != h.team:
		return
	var data: Dictionary = ev.get("data", {})
	var lead := Squads.lead_record(world, h.team, h.slot)
	match str(ev.get("kind", "")):
		"order_done":
			var kind := str(data.get("kind", ""))
			if int(data.get("seat", -1)) == h.slot and OrderKinds.SQUADRON_KINDS.has(kind):
				var text := SquadOrders.confirm_text(world, kind, int(data.get("squad", 0)))
				if text != "":
					toast(text)
					wing_strip.confirm()
		"order_refused":
			if int(data.get("seat", -1)) == h.slot and OrderKinds.SQUADRON_KINDS.has(str(data.get("kind", ""))) and str(data.get("at", "")) == "apply":
				var why := SquadOrders.refusal_text(str(data.get("reason", "")))
				if why != "":
					toast(why, true)
		"wing_home":
			if lead != null and int(data.get("squad", -1)) == lead.wing_id:
				toast("Wing heading home")
		"wing_launched":
			if lead != null and int(data.get("squad", -1)) == lead.wing_id:
				toast("Wing launched (%d)" % int(data.get("count", 0)))
		"ship_lost":
			if int(data.get("wing", 0)) == 1:
				var rec: Squad = world.squads.get(int(data.get("squad", 0)))
				if rec != null and rec.owner_seat == h.slot and rec.team == h.team:
					toast("Wingman lost (%s)" % Formations.short_hull(rec.hull_id), true)


## Someone respawned. If it is the human pilot, open the hangar so they can
## shop before launching, and forget how they died.
func _on_respawned(p: RefCounted) -> void:
	if p == world.human and world.human_role == "pilot":
		_open_hangar()
		feed.last_cause = ""


## One of an Admiral's orders was carried out (`ok`) or refused. Only the
## human Admiral (the one of the human's team) gets a pop-up: the RESULT_OK text
## when it worked, or the reason (`message`) when it didn't.
func _on_admiral_result(team: int, action: String, ok: bool, message: String) -> void:
	if world.human_role != "admiral" or team != world.human_team:
		return
	if ok:
		var m: String = RESULT_OK.get(action, "")
		if m != "":
			toast(m)
	else:
		toast(message)


## The match ended: unpause, close every panel and map tool, and show the
## end screen on top of everything (a pop-up hint still showing goes: it
## would be drawn over the end screen's text).
func _on_match_over(winner: int, reason: String) -> void:
	get_tree().paused = false
	panels.command_paused = false
	if pause_menu != null:
		pause_menu.end_session()
	_close_others(null)
	overlay.disarm()
	toast_box.visible = false
	end_screen = END_SCENE.instantiate()
	end_screen.setup(world, winner, reason, series)
	add_child(end_screen)


# --- refresh -----------------------------------------------------------------------

## Runs every frame (dt = seconds since the last frame). Fades the pop-up
## hint, and every 0.1 seconds refreshes all the widgets.
func _process(dt: float) -> void:
	if world == null:
		return
	toast_box.tick(dt)
	router.wing_tick()
	_track_pointer(dt)
	world.ui_hold = (_pointer_on_buttons() or _pointer_nears_readout()) and not world.mouse_fire
	_t -= dt
	if _t <= 0.0:
		_t = 0.1
		_refresh()


## Is the pointer over a HUD control that takes clicks and is showing: the ship readout (and the wing strip on it), the
## button block or a kit gear slot? Asked every frame; World.ui_hold keeps the ship's aim still while it is true.
func _pointer_on_buttons() -> bool:
	var over := get_viewport().gui_get_hovered_control()
	if over == null or not over.is_visible_in_tree():
		return false
	return over == status or status.is_ancestor_of(over) or seat_bar.is_ancestor_of(over) or over == seat_bar \
			or slots.is_ancestor_of(over)


## Note where the pointer is from every mouse-motion event.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_ptr_event = (event as InputEventMouseMotion).position
		_ptr_event_seen = true


## Keep the pointer's smoothed velocity up to date (every frame, so it is right on the frame the pointer nears the readout).
func _track_pointer(dt: float) -> void:
	var p := _ptr_event if _ptr_event_seen else get_viewport().get_mouse_position()
	if _ptr_seen and dt > 0.0:
		_ptr_vel = _ptr_vel.lerp((p - _ptr_last) / dt, 1.0 - exp(-dt / AIM_VEL_SMOOTH_S))
	_ptr_seen = true
	_ptr_last = p


## Is the pointer outside the ship readout but heading straight for it and about to arrive: moving at AIM_HOLD_MIN_SPEED or
## more, on a straight line that enters the readout within AIM_HOLD_LEAD_S seconds? Then World.ui_hold is on already, so the
## aim keeps the direction it has and the hull does not turn toward the readout on the way down to it. A pointer that sweeps
## past, stops short or turns away is not heading for it, and its aim is the mouse as ever.
func _pointer_nears_readout() -> bool:
	if status == null or not status.is_visible_in_tree() or _ptr_vel.length() < AIM_HOLD_MIN_SPEED:
		return false
	var r := status.get_global_rect()
	var p := _ptr_last
	if r.has_point(p):
		return false
	# The straight line p + v * t against the readout's box (slabs): the time it first enters, or never.
	var t_in := 0.0
	var t_out := INF
	for axis in 2:
		var o := p.x if axis == 0 else p.y
		var d := _ptr_vel.x if axis == 0 else _ptr_vel.y
		var lo := r.position.x if axis == 0 else r.position.y
		var hi := r.end.x if axis == 0 else r.end.y
		if absf(d) < 0.001:
			if o < lo or o > hi:
				return false
			continue
		var t1 := (lo - o) / d
		var t2 := (hi - o) / d
		t_in = maxf(t_in, minf(t1, t2))
		t_out = minf(t_out, maxf(t1, t2))
	return t_in <= t_out and t_in <= AIM_HOLD_LEAD_S


## Update every widget's text from the game state. Old feed lines fade out
## after HudFeed.LIFE seconds and earnings lines after HudMePanel.EARN_LIFE.
func _refresh() -> void:
	# Step 1: the text widgets.
	top_bar.refresh(world)
	me_panel.refresh(world)
	banner.refresh()
	slots.refresh_slots(world.human)
	HudFeed.fade_lines(feed, HudFeed.LIFE)
	HudFeed.fade_lines(me_panel.earn_box, HudMePanel.EARN_LIFE)
	# Step 2: the ship readout only shows while our ship is alive.
	var h := world.human
	var ship: Ship = null
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		ship = h.ship
	status.visible = ship != null
	status.set_ship(ship)
	wing_strip.refresh()
	seat_bar.refresh()
	# Step 3: gear slots for pilots (and for an Admiral flying a ship).
	slots.slots_box.visible = h != null and (world.human_role == "pilot" or ship != null)
	slots.refresh_keys(world.human_role, h != null and Squads.lead_record(world, h.team, h.slot) != null)
	# Step 4: move the pieces out of each other's way (after step 2, which
	# may have shown the ship readout again).
	layout.apply()
