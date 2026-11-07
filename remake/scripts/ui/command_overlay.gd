class_name CommandOverlay
extends Node2D
## WHAT THIS IS: the human Admiral's map layer: the selection of squadrons and of the mothership (click, box,
## double-click, Shift), the smart right-click, the verbs of the command card (Move, Hold, Stop) and the map
## tools (repair bay, ward, waypoint, move the mothership, rally, turret, torpedo turret). DESIGN.md A15 and the
## RT4 design (5.1 selection, 5.3 right-click orders).
##
## HOW IT WORKS: the Admiral board or the command card "arms" a tool (arm). The next left click on the map (or on
## the minimap) sends it as an order to the order queue (world.orders): a refusal the game knows at once comes
## back at once, and the game checks the rest and carries the order out at the start of the next tick, reporting
## back via Events.admiral_result. A right click or Esc "disarms" it.
## Tools: "bay", "ward", "waypoint", "move" (the mothership), "rally" (the spot where new fleet ships gather: it
## sends no order, the card and the production panel read the spot from here), "turret" and "torpedo" (a click on
## a resource node), and "verb_move" (the next click sends the selected squadrons there).
## Selection (RtsSelect holds the rules): with no tool armed a left click ACTS ON RELEASE (the press only notes
## where it began), a drag of more than 6 screen pixels draws a box, Shift (or the sticky `add_mode`) adds and
## toggles, a double-click takes every squadron of that hull on screen and Ctrl+double-click on the whole map.
## The state is `sel_squads` (ids of squad records of our team) and `sel_base` (our mothership); every change
## sends `selection_changed`. Selection by clicking works while the Admiral is docked (or the board is open
## over a flying Admiral), never while their own ship is flying: there a click fires the guns.
## Orders: every order is `world.orders.submit(Order.make(kind, team, ADMIRAL_SEAT, true, ...))`. The smart
## right-click (smart_order_at) sends Move for a click on open ground; an enemy, our pilot, a structure or our
## mothership says "<Verb>: later stage" and sends nothing. The answer of the last click is in `result_text`
## (the card prints it) and arrives by `result_changed`.
## This node lives under World (not under the HUD), so it draws in world positions and gets the clicks the
## HUD's buttons didn't take, before the ship's guns do. For everyone it also draws the team's rally waypoint
## (CommandOverlayDraw does all the drawing).
##
## WHO USES IT: Hud makes it from scenes/ui/command_overlay.tscn (hud.overlay). AdmiralBoard arms tools and uses
## can_command(); Minimap calls apply_at() and order_at(); HudInput and HudBanner use tool, disarm() and hint();
## CommandView, CommandCard, SelectionPanel and TopStrip read and change the selection and send the verbs;
## tests/ui_tour.gd arms "bay"; tests/rts_tour.gd drives the selection.

## The selection changed (a squadron added, removed, narrowed to, cleared).
signal selection_changed
## The answer line (result_text) changed.
signal result_changed

## The instruction shown while each tool is armed (on the banner and next
## to the mouse).
const TOOL_TEXT := {
	"bay": "Click where the repair bay should anchor",
	"ward": "Click a spot your team can see to place a ward",
	"waypoint": "Click to set the rally waypoint",
	"move": "Click a spot in a lane to move the mothership",
	"rally": "Click where new ships should gather",
	"turret": "Click a resource node to build a turret there",
	"torpedo": "Click one of your inner turret sites to build a torpedo turret",
	"verb_move": "Click where the selected squadrons should move",
}
## The verb a right-click on each kind of target would be (the later stage's order).
const LATER_VERBS := {"enemy": "Attack", "pilot": "Escort", "structure": "Defend", "base": "Retreat"}

## The game world (set by setup()).
var world: World
## The team these tools command: the human Admiral's team (World.human_team).
var team := Rules.HALCYON
## The armed tool's name (see TOOL_TEXT), or "" when none is armed.
var tool := ""
## The ids of the squad records of our team that are selected (RtsSelect says which can be).
var sel_squads: Array[int] = []
## Is our mothership selected?
var sel_base := false
## The sticky Add toggle: every click and box adds to the selection (the Shift route for the mouse only).
var add_mode := false
## The squadron under the pointer now (-1 for none): it gets a dashed ring.
var hover_squad := -1
## The answer of the last order click, in words, and whether it was a success.
var result_text := ""
var result_ok := true  # false: a refusal (shown with the danger triangle)
## The spot the Admiral picked with the "rally" tool, in whole world units, and
## whether one has been picked.
var rally_spot := Vector2i.ZERO
var rally_set := false  # true once a spot was picked
## Where a box-select drag started (world position), or Vector2.INF
## ("infinity", meaning no box is being drawn).
var _drag_from := Vector2.INF
## Where the box-select drag is now (world position).
var _drag_to := Vector2.ZERO
## Where the left button went down on the screen (the window's pixels), or Vector2.INF when it is not down.
var _press_screen := Vector2.INF
## Where the left button went down in the world.
var _press_world := Vector2.ZERO
## True once a double-click took its selection (the release that follows does nothing).
var _dc_done := false
## The font for labels drawn on the map (Godot's built-in default font).
var _font: Font


## Remember the world, and draw above most of the game (z_index 20: a
## higher z_index draws on top).
func setup(w: World) -> void:
	world = w
	team = w.human_team
	z_index = 20
	_font = ThemeDB.fallback_font
	# The overlay keeps taking clicks and drawing while the match is held paused (the command pause), so the Admiral can still
	# select and give orders.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Is the human playing as the Admiral?
func is_admiral() -> bool:
	return world != null and world.human_role == "admiral"


## The Admiral commands from anywhere, even while flying their own ship
## (only moving the mothership needs them docked: AdmiralCommand checks).
func can_command() -> bool:
	return is_admiral() and world.phase == "play"


## May a map click select now: the Admiral docked, or the board open (a flying Admiral's left click fires the guns).
func select_allowed() -> bool:
	return can_command() and (world.teams[team].admiral_docked or world.board_open)


## Arm tool `t`, so the next map click uses it. The verb "verb_move" needs a selection first.
func arm(t: String) -> void:
	if not can_command():
		return
	if t == "verb_move" and sel_squads.is_empty():
		say("Select squadrons first", false)
		return
	tool = t


## Cancel the armed tool and any box-select drag.
func disarm() -> void:
	tool = ""
	_drag_from = Vector2.INF
	_press_screen = Vector2.INF


## The banner text while a tool is armed ("" when none is).
func hint() -> String:
	if tool == "":
		return ""
	return "%s.  Right-click or Esc to cancel." % tool_text()


## The instruction for the armed tool: its line in TOOL_TEXT, or (for the
## orders that feature modules add, see CommandOrders) the order's hint,
## else "Click the map".
func tool_text() -> String:
	if TOOL_TEXT.has(tool):
		return TOOL_TEXT[tool]
	var h := CommandOrders.hint(world, tool)
	return h if h != "" else "Click the map"


## The verb word the cursor carries for the armed tool ("Move" for the Move verb), or "" for the map tools.
func verb_label() -> String:
	return "Move" if tool == "verb_move" else ""


## Why the armed tool can't go at world point `p` (AdmiralCommand's
## reason), or "" when it can. The mothership also refuses the jungle.
func blocker_at(p: Vector2) -> String:
	var cmd := world.command
	match tool:
		"bay":
			return cmd.bay_blocker(team, p)
		"ward":
			return cmd.ward_blocker(team, p)
		"move":
			var b := cmd.move_blocker(team)
			if b == "" and not world.map.in_open_lane(p):
				b = "Too big for the jungle: pick a lane or the base"
			return b
		"verb_move":
			if sel_squads.is_empty():
				return "Select squadrons first"
			if not Rect2(0.0, 0.0, MapLayout.W, MapLayout.H).has_point(p):
				return "Outside the map"
		"turret", "torpedo":
			var n := node_at(p, tool == "torpedo")
			if n == null:
				return "Click a resource node" if tool == "turret" else "Click one of your inner turret sites"
			return cmd.turret_blocker(team, n.node_id, "torp" if tool == "torpedo" else "pd")
		_:
			# An order that a feature module added (CommandOrders).
			if world.command.orders.has(tool):
				return CommandOrders.blocker(world, tool, team, p)
	return ""


## The resource node nearest to world point `p` within the pick radius (14 screen pixels and the node's own size),
## or null. With `torpedo_only` only a node of a kind that takes a torpedo turret (TurretData.TORP_SITE_KINDS) counts.
func node_at(p: Vector2, torpedo_only: bool) -> ResourceNode:
	var px := 1.0 / maxf(0.0001, world.camera.zoom.x)
	var best: ResourceNode = null
	var best_d := INF
	for n: ResourceNode in world.nodes:
		if torpedo_only and n.node_kind not in TurretData.TORP_SITE_KINDS:
			continue
		var d := n.global_position.distance_to(p)
		if d <= RtsSelect.PICK_PX * px + 60.0 and d < best_d:
			best_d = d
			best = n
	return best


## Carry out the armed tool at world point `p` (a map click or a minimap
## click). AdmiralCommand returns "" when the order worked: then the tool
## is used up. On a refusal the tool stays armed so the Admiral can try
## another spot.
func apply_at(p: Vector2) -> void:
	if not can_command():
		disarm()
		return
	var cmd := world.command
	var msg := ""
	# Each tool becomes an order record for the order queue (OrderQueue.submit): a
	# refusal that the game can know at once comes back as `msg` now, the rest when the
	# order is carried out on the next tick. The click's point is rounded to whole units.
	var at := Order.point(p)
	match tool:
		"bay":
			msg = world.orders.submit(Order.make(OrderKinds.BAY, team, Rules.ADMIRAL_SEAT, true, {}, [], "point", at))
		"ward":
			msg = world.orders.submit(Order.make(OrderKinds.WARD, team, Rules.ADMIRAL_SEAT, true, {}, [], "point", at))
		"waypoint":
			# A human admiral's click: it declares a siege near the enemy
			# mothership, and it counts as a human's waypoint (by_human).
			msg = world.orders.submit(Order.make(OrderKinds.WAYPOINT, team, Rules.ADMIRAL_SEAT, true, {"siege": 1}, [], "point", at))
		"move":
			msg = world.orders.submit(Order.make(OrderKinds.MOTHERSHIP_MOVE, team, Rules.ADMIRAL_SEAT, true, {}, [], "point", at))
		"rally":
			# Not an order: the production panel and the card use the spot when they buy ships.
			rally_spot = at
			rally_set = true
		"turret", "torpedo":
			var n := node_at(p, tool == "torpedo")
			if n == null:
				msg = blocker_at(p)
			else:
				msg = world.orders.submit(Order.make(OrderKinds.TURRET, team, Rules.ADMIRAL_SEAT, true, {"ttype": "torp" if tool == "torpedo" else "pd"}, [], "node", n.node_id))
				say("%s: %s" % ["Torpedo turret" if tool == "torpedo" else "Turret", msg if msg != "" else "ordered at " + Rules.display_label(n.node_name)], msg == "")
		"verb_move":
			msg = RtsSquadOrders.send(self, OrderKinds.MOVE, "point", at, sel_squads, "Move")
		_:
			# An order that a feature module added (CommandOrders).
			if cmd.orders.has(tool):
				msg = CommandOrders.run(world, tool, team, p)
	if msg == "":
		tool = ""


## A right click at world point `p` on the minimap: cancels an armed tool; otherwise nothing (RT6 owns the minimap's
## right click).
func order_at(_p: Vector2) -> void:
	if tool != "":
		disarm()


# --- the selection -----------------------------------------------------------------------------

## Replace the selection with squadrons `ids` and the mothership `base`, or (with `add`) add them to it.
func set_selection(ids: Array[int], base: bool, add: bool = false) -> void:
	var before := _signature()
	if add:
		for id in ids:
			if not sel_squads.has(id):
				sel_squads.append(id)
		sel_base = sel_base or base
	else:
		sel_squads = ids.duplicate()
		sel_base = base
	_changed(before)


## Toggle one squadron in or out of the selection (Shift+click).
func toggle_squad(id: int) -> void:
	var before := _signature()
	if sel_squads.has(id):
		sel_squads.erase(id)
	else:
		sel_squads.append(id)
	_changed(before)


## Toggle the mothership in or out of the selection (Shift+click on it).
func toggle_base() -> void:
	var before := _signature()
	sel_base = not sel_base
	_changed(before)


## Take squadron `id` out of the selection (a tag's x, Shift+click on a tag).
func remove_squad(id: int) -> void:
	var before := _signature()
	sel_squads.erase(id)
	_changed(before)


## Empty the selection (a click on empty map, Esc's last step). The sticky Add switches off with it.
func clear_selection() -> void:
	var before := _signature()
	sel_squads.clear()
	sel_base = false
	_changed(before)


## Select every squadron we have (the M key and the strip's fleet count).
func select_all_squadrons() -> void:
	var ids: Array[int] = []
	for rec: Squad in RtsSelect.our_squads(world, team):
		ids.append(rec.id)
	set_selection(ids, false)


## The selected squad records that can still be selected (a squadron with no ship left drops out of the selection).
func selected_records() -> Array[Squad]:
	tidy()
	var out: Array[Squad] = []
	for id in sel_squads:
		var rec: Squad = world.squads.get(id)
		if rec != null:
			out.append(rec)
	return out


## Drop the squadrons that no longer exist or have no ship alive from the selection.
func tidy() -> void:
	if world == null or sel_squads.is_empty():
		return
	var live := RtsSelect.live_ids(world, team, sel_squads)
	if live.size() != sel_squads.size():
		var before := _signature()
		sel_squads = live
		_changed(before)


## The selection as one text, to tell whether it changed.
func _signature() -> String:
	return "%s/%s" % [str(sel_squads), str(sel_base)]


## Send selection_changed when the selection differs from `before`; the Add toggle goes off when it empties.
func _changed(before: String) -> void:
	if sel_squads.is_empty() and not sel_base:
		add_mode = false
	if _signature() != before:
		selection_changed.emit()


# --- orders to the selection -----------------------------------------------------------------------

## Say `text` on the card's result line (`ok` false for a refusal).
func say(text: String, ok: bool = true) -> void:
	result_text = text
	result_ok = ok
	result_changed.emit()


# --- the mouse ---------------------------------------------------------------------------------------

## Mouse clicks on the map that no button took (only for the Admiral): left click uses the armed tool, else selects
## (on release; a drag is a box); right click cancels the tool, else gives the smart order to the selection.
## Each click we use is marked "handled" so the ship's guns don't fire.
func _unhandled_input(event: InputEvent) -> void:
	if world == null or not is_admiral():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var p := get_global_mouse_position()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and tool != "":
				apply_at(p)
				get_viewport().set_input_as_handled()
			elif mb.pressed and select_allowed():
				_press(mb, p)
				get_viewport().set_input_as_handled()
			elif not mb.pressed and _press_screen != Vector2.INF:
				_release(mb, p)
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if tool != "":
				disarm()
				get_viewport().set_input_as_handled()
			elif select_allowed() and not sel_squads.is_empty():
				RtsSquadOrders.smart_order_at(self, p)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _press_screen != Vector2.INF and not _dc_done:
		var mm := event as InputEventMouseMotion
		if _drag_from == Vector2.INF and mm.position.distance_to(_press_screen) > RtsSelect.BOX_PX:
			_drag_from = _press_world
		if _drag_from != Vector2.INF:
			_drag_to = get_global_mouse_position()


## The left button went down on the map: note where (the click acts on release); a double-click acts now.
func _press(mb: InputEventMouseButton, p: Vector2) -> void:
	_press_screen = mb.position
	_press_world = p
	_drag_from = Vector2.INF
	_dc_done = false
	if not mb.double_click:
		return
	var px := 1.0 / maxf(0.0001, world.camera.zoom.x)
	var id := RtsSelect.squad_at(world, team, p, px)
	if id < 0:
		return
	var rec: Squad = world.squads[id]
	var area := Rect2() if mb.ctrl_pressed else RtsSelect.view_rect(world)
	set_selection(RtsSelect.same_hull(world, team, rec.hull_id, area), false, mb.shift_pressed or add_mode)
	_dc_done = true


## The left button came up: a box takes what is inside it, a click takes what is under it (or clears).
func _release(mb: InputEventMouseButton, p: Vector2) -> void:
	var was_box := _drag_from != Vector2.INF
	var done := _dc_done
	_press_screen = Vector2.INF
	_drag_from = Vector2.INF
	_dc_done = false
	if done:
		return
	var adding := mb.shift_pressed or add_mode
	if was_box:
		var r := Rect2(_press_world, Vector2.ZERO).expand(p)
		var got := RtsSelect.in_box(world, team, r)
		set_selection(got["squads"], bool(got["base"]), adding)
		return
	var px := 1.0 / maxf(0.0001, world.camera.zoom.x)
	var hit := RtsSelect.pick(world, team, p, px)
	match str(hit["kind"]):
		"squad":
			var id := int(hit["id"])
			if mb.shift_pressed:
				toggle_squad(id)
			elif add_mode:
				set_selection([id], false, true)
			elif not sel_squads.has(id):
				set_selection([id], false)
		"base":
			if mb.shift_pressed:
				toggle_base()
			elif add_mode:
				set_selection([], true, true)
			else:
				set_selection([], true)
		_:
			if not adding:
				clear_selection()


## Every frame: ask Godot to redraw us (queue_redraw makes it call _draw), and find the squadron under the pointer
## (it gets a dashed ring) and drop dead squadrons from the selection.
func _process(_dt: float) -> void:
	if world == null:
		return
	hover_squad = -1
	if is_admiral() and tool == "" and select_allowed():
		hover_squad = RtsSelect.squad_at(world, team, get_global_mouse_position(), 1.0 / maxf(0.0001, world.camera.zoom.x))
	tidy()
	queue_redraw()


## Draw the waypoint, the Admiral's marks and the armed tool's preview.
## The real code is in CommandOverlayDraw.draw().
func _draw() -> void:
	CommandOverlayDraw.draw(self)
