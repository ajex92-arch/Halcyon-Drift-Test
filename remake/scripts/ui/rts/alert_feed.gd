class_name AlertFeed
extends Control
## WHAT THIS IS: the Admiral's alert feed (DESIGN.md section 2, A1) in the command view's top left slot: a header
## (ALERTS, "+N older", and the Jump and Back buttons) and ALERT_ROWS rows of 20 pixels, one for each alert of the
## team's alert list that is alive, the most important first and then the newest. A row shows the kind's sign
## (the danger triangle, a check or a flask, so colour is never the only sign), the text with its count and place
## and its age, and ends in a small x that hides that alert for the rest of the match (left click). It also holds the jump chain: J (and Backspace) jumps the camera to the newest alert, J again steps
## back through older ones, and Shift+J puts the camera back where it was before the chain.
##
## HOW IT WORKS: a Control the size of the slot that lets the mouse through; its header buttons and rows take the
## mouse where they are. It owns an AlertRules and, four times a second (RtsBeat), polls it (the rules raise the
## alerts the match's events do not raise) and rewrites the rows from World.alerts[team]; a text is set only when it
## changed. Rows are pooled: ALERT_ROWS in the feed and RECENT_ROWS in the drop-down that "+N older" opens (the live
## alerts past the fifth, then the expired ones, newest first). A row is merged by the list (ten ships lost in one
## 2,000-unit cell are one row, "Ship lost x10"), dims to half strength in the last fifth of its life, wears a 2 px
## light bar for its first 2 seconds, and its age counts from its last raise in World ticks, so a pause stops it.
## A click on a row (or the Jump button, or J) jumps to its place; a row with no place (research done, module
## finished) opens the board at its page instead. The chain: the first jump notes where the camera was and steps to
## the top alert; a jump made while the camera is still where the last jump put it steps to the next alert (the live
## ones with a place, then the expired ones, at most CHAIN_MAX of them, then round to the top); a jump after the
## camera was moved by hand starts a new chain. Back (Shift+J, or the Back button) returns the camera there and ends
## the chain. A jump frees a camera that follows the ship (the C key); Back follows the ship again if it did. The keys
## are read here from the key map's alert_jump and alert_back rows (home, or flying with the board open), after the
## HUD's own routing has left them alone; the key labels on the buttons come from the same rows. The feed changes
## nothing the simulation reads: it moves the camera and writes the alert list only through AlertRules.
## In the command view's slim display (field mode, the Admiral flying with the view closed) the feed shows only the first
## RtsUiCalls.FIELD_ALERT_ROWS rows, in the same order (the most important first, then the newest); the rest are behind
## "+N older". With the view open (mode 3) or docked it shows RtsUiCalls.ALERT_ROWS rows.
## RT7's warning, "Under Fire!": before each poll the feed tells its rules which ship to watch (watch_ship(): the ship the readout
## shows while the Admiral flies it), and a hull hit on that ship raises the ship_under_fire alert (priority 1). Its row reads
## exactly "Under Fire!" (PLAIN_KINDS: no place, no count) and keeps its place, so J and a click jump to the ship.
##
## WHO USES IT: CommandView (makes it in the alert slot); tests/alert_feed_check.gd.

## Rows in the "+N older" drop-down.
const RECENT_ROWS := 8
## The most alerts a chain of jumps steps through before it goes round to the top.
const CHAIN_MAX := 8
## The feed's width and height (the size of CommandView's alert slot), the row height and the header height (pixels).
const W := 220.0
const SLOT_H := 120.0  # SLOT H (pixels or a count)
const ROW_H := 20.0
const HEAD_H := 20.0  # HEAD H (pixels or a count)
## Seconds a new row wears its light bar, and the share of an alert's life in which it dims.
const NEW_BAR_S := 2.0
const DIM_LAST := 0.2  # DIM LAST (pixels or a count)
## Milliseconds after a jump in which a second jump always counts as the chain going on (the camera is still sliding).
const SLIDE_MS := 700
## The kinds whose sign is a check, the flask, and the idle bars; every other kind wears the danger triangle.
const CHECK_KINDS := ["build_done", "module_done", "pilot_request"]
## The kinds whose row reads exactly the list's text, with no place and no count (RT7: "Under Fire!"). The row keeps its place, so
## J and a click still jump there.
const PLAIN_KINDS := ["ship_under_fire"]
## The width of the small x at a row's right end ("hide this alert"), in pixels, and its tip.
const HIDE_W := 14.0
const HIDE_TIP := "Hide this alert for the rest of the match."

## One row of the feed (a pooled control): the box, the sign, the text and the age.
class AlertRow extends Control:
	## The row was clicked (left button).
	signal chosen(row: AlertRow)
	## The row's small x was clicked (left button): hide this alert.
	signal hide_asked(row: AlertRow)
	## The alert on show (the list's Dictionary), or {} when the row is hidden.
	var alert: Dictionary = {}
	## What the row shows now (a signature, so an unchanged row writes nothing).
	var shown := ""
	## The sign to draw: "danger", "check", "flask" or "idle".
	var glyph := "danger"
	## Draw the new-row bar, dim the row, and is the pointer on it.
	var bar := false
	var dim := false
	var hot := false
	var _text: Label
	var _age: Label

	## Make the parts (once).
	func setup() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(W, ROW_H)
		size = custom_minimum_size
		_text = UiKit.label("", 10, Palette.ICE)
		_text.clip_text = true
		_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_text.position = Vector2(22.0, 2.0)
		_text.size = Vector2(W - 22.0 - 32.0 - HIDE_W, ROW_H - 4.0)
		add_child(_text)
		_age = UiKit.label("", 10, Palette.MIST)
		_age.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_age.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_age.position = Vector2(W - 34.0 - HIDE_W, 2.0)
		_age.size = Vector2(30.0, ROW_H - 4.0)
		add_child(_age)
		mouse_entered.connect(func() -> void:
			hot = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			hot = false
			queue_redraw())
		visible = false

	## Write a snapshot: {text, age, glyph, bar, dim, tip}. Only a changed one writes anything.
	func show_data(d: Dictionary) -> void:
		var sig := "%s|%s|%s|%s|%s" % [d["text"], d["age"], d["glyph"], d["bar"], d["dim"]]
		if sig == shown:
			return
		shown = sig
		RtsBeat.set_if_changed(_text, str(d["text"]))
		RtsBeat.set_if_changed(_age, str(d["age"]))
		tooltip_text = str(d["tip"])
		glyph = str(d["glyph"])
		bar = bool(d["bar"])
		dim = bool(d["dim"])
		modulate.a = 0.5 if dim else 1.0
		queue_redraw()

	## Is row point `p` on the small x at the row's right end?
	func on_hide(p: Vector2) -> bool:
		return p.x >= W - HIDE_W

	## A left click chooses the row; a left click on its small x asks to hide the alert.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if on_hide(mb.position):
					hide_asked.emit(self)
				else:
					chosen.emit(self)

	## The tip under the mouse: the x says what it does, the rest of the row shows the alert's whole line.
	func _get_tooltip(at_position: Vector2) -> String:
		return HIDE_TIP if on_hide(at_position) else tooltip_text

	## The box, the sign and the new-row bar.
	func _draw() -> void:
		draw_style_box(RtsTheme.look("tag_on" if hot else "row"), Rect2(Vector2.ZERO, size))
		var c := Vector2(11.0, ROW_H * 0.5)
		match glyph:
			"check":
				RtsGlyphs.draw(self, "check", c, 10.0, Palette.ICE)
			"flask":
				RtsGlyphs.draw(self, "flask", c, 11.0, Palette.ICE)
			"idle":
				RtsGlyphs.draw(self, "idle", c, 10.0, Palette.MIST)
			_:
				Glyphs.danger(self, c + Vector2(0.0, 0.5), 12.0)
		if bar:
			draw_rect(Rect2(0.0, 0.0, 2.0, ROW_H), Palette.ICE)
		RtsGlyphs.draw_x(self, Vector2(W - HIDE_W * 0.5, ROW_H * 0.5), 7.0)


## The command view and the match (set by setup()).
var view: CommandView
var world: World
var overlay: CommandOverlay  # the overlay
## The team whose alerts the feed shows.
var team := 0
## The rules that raise the alerts the events do not.
var rules := AlertRules.new()
## The beat the feed refreshes on (its own: the command view's refresh() is not the feed's).
var beat := RtsBeat.new()
## The pieces.
var _title: Label
var _older: Button
var _jump: Button
var _back: Button
var _rows: Array[AlertRow] = []
var _drop: Array[AlertRow] = []
## The live alerts past the rows and the expired ones, newest first, as of the last refresh (the drop-down's content).
var _older_list: Array = []
## Is the drop-down open?
var _open := false
## The alerts the player hid with a row's small x: the list's keys (kind and cell, reason, seat or squadron). A hidden
## key stays out of the rows, the drop-down and the jump chain for the rest of the match, also when it is raised again.
## Screen state only: the alert list itself is not touched.
var _hidden := {}
## The header's last texts and the key version they were made for.
var _head_sig := ""
## The jump chain: where the camera was before it began (and whether it followed the ship), the index of the last step,
## where the last jump put the camera and when.
var _has_origin := false
var _origin := Vector2.ZERO
var _origin_followed := false
var _step := -1
var _target := Vector2.ZERO
var _jump_ms := -100000


## Make the pieces and the rules. CommandView calls this once, with the alert slot as the parent.
func setup(v: CommandView) -> void:
	view = v
	world = v.world
	overlay = v.overlay
	team = v.team
	name = "AlertFeed"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules.setup(world, team)
	_title = UiKit.label("ALERTS", 10, Palette.MIST)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.position = Vector2(5.0, 3.0)
	add_child(_title)
	_older = _head_button("", "The alerts past the rows and the ones that ended, newest first. A click opens them; a click on one jumps there.", func() -> void: toggle_older())
	_jump = _head_button("Jump", "Jump the camera to the newest alert; again for the next older one.", func() -> void: jump())
	_back = _head_button("Back", "Put the camera back where it was before the jumps.", func() -> void: back())
	for i in RtsUiCalls.ALERT_ROWS:
		_rows.append(_make_row(Vector2(0.0, HEAD_H + float(i) * ROW_H)))
	for i in RECENT_ROWS:
		_drop.append(_make_row(Vector2(0.0, SLOT_H + float(i) * ROW_H)))
	draw.connect(_draw_head)
	beat.prime()


## One header button.
func _head_button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"RtsStrip"
	b.add_theme_font_size_override("font_size", 10)
	b.size = Vector2(40.0, HEAD_H)
	b.pressed.connect(on_press)
	add_child(b)
	return b


## One pooled row at `at`.
func _make_row(at: Vector2) -> AlertRow:
	var row := AlertRow.new()
	row.setup()
	row.position = at
	row.chosen.connect(_row_chosen)
	row.hide_asked.connect(func(r: AlertRow) -> void: hide_alert(r.alert))
	add_child(row)
	return row


## The header's box (only as tall as the header: an empty feed is one strip).
func _draw_head() -> void:
	draw_style_box(RtsTheme.look("row"), Rect2(0.0, 0.0, W, HEAD_H))


## Every frame: poll the rules and rewrite the rows on the beat (also while the view is hidden, so alerts are never
## missed behind a panel).
func _process(dt: float) -> void:
	if world == null or not _active():
		return
	if beat.tick(dt):
		poll()
		refresh()


## The human's own ship, which the rules watch for "Under Fire!": the ship the readout shows while the Admiral is out flying it;
## null while docked or when the ship is dead.
func watch_ship() -> Ship:
	if view == null or view.hud == null or view.hud.status == null or world.teams[team].admiral_docked:
		return null
	var s := view.hud.status.ship
	if s != null and is_instance_valid(s) and s.alive:
		return s
	return null


## Tell the rules which ship to watch, then poll them (the beat calls this; a test may too). Returns how many alerts it raised.
func poll() -> int:
	rules.watch = watch_ship()
	return rules.poll()


## Is a match being played with a human Admiral (the feed has nothing to do for anyone else)?
func _active() -> bool:
	return world.human_role == "admiral" and world.phase == "play"


## The alert list of the team.
func _list() -> AlertList:
	return world.alerts[team] as AlertList


## Rewrite the rows, the drop-down and the header from the alert list.
func refresh() -> void:
	var tick := world.tick_count
	var live: Array = _unhidden(_list().live(tick))
	var recent: Array = _unhidden(_list().recent)
	recent.reverse()
	var cap := row_cap()
	_older_list = []
	for i in range(cap, live.size()):
		_older_list.append(live[i])
	_older_list.append_array(recent)
	for i in _rows.size():
		_fill(_rows[i], live[i] if i < live.size() and i < cap else {}, tick)
	if _older_list.is_empty():
		_open = false
	# The drop-down starts under the last row that shows (the slim display has fewer rows).
	var drop_y := HEAD_H + float(cap) * ROW_H
	for i in _drop.size():
		if absf(_drop[i].position.y - (drop_y + float(i) * ROW_H)) > 0.5:
			_drop[i].position.y = drop_y + float(i) * ROW_H
		_fill(_drop[i], _older_list[i] if _open and i < _older_list.size() else {}, tick)
	_head(live.size(), tick)
	# The army row's attacked frame: the cards of the squadrons whose under-attack alert is alive.
	if view != null and view.army != null:
		view.army.set_attacked(rules.attacked(tick))


## How many rows the feed shows now: RtsUiCalls.FIELD_ALERT_ROWS in the command view's slim display (field mode), else
## RtsUiCalls.ALERT_ROWS. The live alerts past them are behind "+N older".
func row_cap() -> int:
	if view != null and view.is_slim():
		return mini(RtsUiCalls.FIELD_ALERT_ROWS, RtsUiCalls.ALERT_ROWS)
	return RtsUiCalls.ALERT_ROWS


## The alerts of `list` the player has not hidden (a new Array, in the same order).
func _unhidden(list: Array) -> Array:
	return list.filter(func(a: Dictionary) -> bool: return not _hidden.has(str(a["key"])))


## The small x of a row: hide `alert` (by its key) for the rest of the match and rewrite the feed. The camera stays.
func hide_alert(alert: Dictionary) -> void:
	if alert.is_empty():
		return
	_hidden[str(alert["key"])] = true
	_head_sig = ""
	refresh()


## Fill `row` with `alert` ({} hides the row).
func _fill(row: AlertRow, alert: Dictionary, tick: int) -> void:
	row.alert = alert
	RtsBeat.flag(row, not alert.is_empty())
	if alert.is_empty():
		row.shown = ""
		return
	var kind := str(alert["kind"])
	var life := int((AlertList.KINDS[kind] as Dictionary)["life"])
	var expires := int(alert["expires"])
	var last := expires - life
	var secs := int(float(maxi(0, tick - last)) / 60.0)
	var text := alert_text(alert)
	row.show_data({
		"text": text,
		"age": "%d:%02d" % [floori(float(secs) / 60.0), secs % 60],
		"glyph": glyph_of(kind),
		"bar": tick - int(alert["raised"]) < int(NEW_BAR_S * 60.0) and expires > tick,
		"dim": expires > tick and float(expires - tick) < DIM_LAST * float(life),
		"tip": text,
	})


## The line of an alert: the list's text (with its count), an order refusal's reason, and the place in words.
func alert_text(alert: Dictionary) -> String:
	var text := str(alert["text"])
	if PLAIN_KINDS.has(str(alert["kind"])):
		return text
	if str(alert["kind"]) == "order_refused":
		var parts := str(alert["key"]).split("|")
		if parts.size() > 2 and parts[2] != "":
			text += ": " + parts[2]
	if int(alert.get("seat", Rules.ADMIRAL_SEAT)) == OrderKinds.DEPUTY_SEAT:
		text += " (deputy)"
	var pos: Variant = alert["pos"]
	if pos is Vector2i:
		text += " - " + world.place_name(Vector2(pos as Vector2i))
	return text


## The sign of an alert kind: "check" for something done, "flask" for research, "idle" for an idle squadron, else "danger".
static func glyph_of(kind: String) -> String:
	if kind == "research_done":
		return "flask"
	if kind == "squadron_idle":
		return "idle"
	return "check" if CHECK_KINDS.has(kind) else "danger"


## The header: the "+N older" button, the key labels of Jump and Back, and their places.
func _head(live_count: int, _tick: int) -> void:
	var older := _older_list.size()
	var sig := "%d|%d|%s|%s|%s" % [older, live_count, _open, KeyMap.first_key("home", "alert_jump"), KeyMap.first_key("home", "alert_back")]
	if sig == _head_sig:
		return
	_head_sig = sig
	RtsBeat.set_if_changed(_title, "ALERTS" if live_count > 0 else "ALERTS none")
	_older.visible = older > 0
	RtsBeat.set_if_changed(_older, ("+%d older" % older) + (" ^" if _open else ""))
	RtsBeat.set_if_changed(_jump, _labelled("alert_jump", "Jump"))
	RtsBeat.set_if_changed(_back, _labelled("alert_back", "Back"))
	# Right to left: Back, Jump, then "+N older" in what is left of the strip.
	var x := W - 2.0
	for b: Button in [_back, _jump, _older]:
		if not b.visible:
			continue
		var w := maxf(24.0, b.get_combined_minimum_size().x)
		b.size = Vector2(w, HEAD_H)
		x -= w
		b.position = Vector2(x, 0.0)
		x -= 1.0
	queue_redraw()


## "<key> <word>", or just the word when the row has no key (a button with no key prints none).
func _labelled(row: String, word: String) -> String:
	var k := KeyMap.first_key("home", row)
	return word if k == "" else "%s %s" % [k, word]


## A row was clicked: jump there and start a chain at it, or open the page of an alert with no place.
func _row_chosen(row: AlertRow) -> void:
	if row.alert.is_empty():
		return
	if _drop.has(row):
		_open = false
	jump_to(row.alert)


## Open or close the drop-down of older alerts.
func toggle_older() -> void:
	_open = not _open and not _older_list.is_empty()
	_head_sig = ""
	refresh()


# --- the jump chain -------------------------------------------------------------------------------------

## The alerts a chain steps through, the newest and most important first: the live ones with a place, then the
## expired ones with a place, newest first; at most CHAIN_MAX.
func chain() -> Array:
	var out: Array = []
	var list := _list()
	for a: Dictionary in _unhidden(list.live(world.tick_count)):
		if a["pos"] is Vector2i:
			out.append(a)
	var recent: Array = _unhidden(list.recent)
	recent.reverse()
	for a: Dictionary in recent:
		if a["pos"] is Vector2i:
			out.append(a)
	return out.slice(0, CHAIN_MAX)


## J: jump to the newest alert, or (the camera still where the last jump put it) to the next older one, round to the
## top after the last. Returns true when the camera was sent somewhere.
func jump() -> bool:
	var alerts := chain()
	if alerts.is_empty():
		return false
	if _continuing():
		_step = (_step + 1) % alerts.size()
	else:
		_begin()
		_step = 0
	_go(alerts[_step]["pos"])
	return true


## A click on `alert`: start a chain there (the chain's index is the alert's) and jump; an alert with no place opens
## the page it belongs to. Returns true when the camera was sent somewhere.
func jump_to(alert: Dictionary) -> bool:
	if not (alert["pos"] is Vector2i):
		_open_page(str(alert["kind"]))
		return false
	var alerts := chain()
	var at := -1
	for i in alerts.size():
		if alerts[i]["key"] == alert["key"]:
			at = i
	if not _continuing():
		_begin()
	_step = maxi(at, 0)
	_go(alert["pos"])
	return true


## Shift+J or the Back button: the camera goes back to where it was before the chain, and the chain ends. Returns true
## when there was a chain to go back from.
func back() -> bool:
	if not _has_origin:
		return false
	var cam := world.camera
	if _origin_followed and cam.free:
		cam.toggle_free()
	else:
		cam.look_at_point(_origin)
	_has_origin = false
	_step = -1
	return true


## Is there a chain going on, with the camera still at (or sliding to) the place its last jump sent it to?
func _continuing() -> bool:
	if not _has_origin or _step < 0:
		return false
	if Time.get_ticks_msec() - _jump_ms < SLIDE_MS:
		return true
	var view_w := world.camera.get_viewport_rect().size.x / maxf(0.0001, world.camera.zoom.x)
	return world.camera.global_position.distance_to(_target) <= maxf(200.0, 0.15 * view_w)


## Note where the camera is now (the start of a chain).
func _begin() -> void:
	var cam := world.camera
	_origin = cam.global_position
	_origin_followed = not cam.free
	_has_origin = true


## Send the camera to point `p` (a following camera is freed first).
func _go(p: Vector2i) -> void:
	var cam := world.camera
	if not cam.free:
		cam.toggle_free()
	_target = Vector2(p)
	cam.look_at_point(_target)
	_jump_ms = Time.get_ticks_msec()


## The page of an alert that has no place: research opens the Research page of the board, a module the Mothership page.
func _open_page(kind: String) -> void:
	if view == null or view.hud == null:
		return
	if kind == "research_done":
		view.hud.panels.open_board_at("Research")
	elif kind == "module_done":
		view.hud.panels.open_board_at("Mothership")


# --- the keys -------------------------------------------------------------------------------------------

## J (and Backspace) and Shift+J, from the key map's alert_jump and alert_back rows. The HUD routes the card's keys
## before this node sees an unused key (this node is deeper in the tree, so it is asked first), and the key is used
## only when the chain keys are live: docked, or flying with the board open.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or world == null:
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo or not keys_live():
		return
	var mode := "home" if not view.flying() else "flying_board"
	if _matches(mode, "alert_back", event):
		back()
		get_viewport().set_input_as_handled()
	elif _matches(mode, "alert_jump", event):
		jump()
		get_viewport().set_input_as_handled()


## Does `event` match one of the keys of row `id` of `mode` exactly?
func _matches(mode: String, id: String, event: InputEvent) -> bool:
	for text in KeyMap.effective_keys(mode, id):
		var ev := KeyCodes.make_event(String(text))
		if ev != null and ev.is_match(event, true):
			return true
	return false


## May the chain keys act now: a match with a human Admiral, no end screen, no note box, no pause menu and no
## hangar, help, controls or scoreboard page open; docked, or flying in mode 3 (with the view and the board closed the
## pilot keys stay the pilot's).
func keys_live() -> bool:
	if not _active() or view == null or view.hud == null:
		return false
	var hud := view.hud
	if hud.end_screen != null or hud._note_is_open() or hud._pause_menu_active():
		return false
	for c: Control in [hud.hangar, hud.help, hud.controls, hud.scoreboard]:
		if c != null and c.visible:
			return false
	return not view.flying() or world.mode3()
