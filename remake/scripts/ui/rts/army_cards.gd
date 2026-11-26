class_name ArmyCards
extends Control
## WHAT THIS IS: the army row (D1): one row of small cards on the line above the selection panel, always in the same place
## (with or without a selection): one card for each control group that has squadrons (F1..F8), then one card for each hull
## of the squadrons that are in no group (FTR, BMB, ...), then the empty "F5 + save" card (the first free group: a click saves the
## selection there) and the Idle card (I: a click is "next", a double-click is "all"). Eight cards fit at their size; past
## eight, the hull cards fold into one "+N" card that opens its list on hover, and when the groups alone fill the row the
## cards narrow to fit. A card shows its key label or hull tag, "3 sq - 8/9" (squadrons, ships alive of ships bought), a 2 px hull
## bar and the state sign of the most common state (fighting ahead of moving ahead of idle when they tie); a card whose
## squadrons are under attack wears a steady danger frame with the triangle (set_attacked(): the alert rules of a later
## stage call it, nothing does yet). With the win-odds option on (Game.win_odds, off by default) a group or hull card also carries the
## mark of WinOdds, "odds" in its entry: win, even or loss against the enemy ships the human's team sees near its squadrons, or "".
##
## HOW IT WORKS: a Control that lets the mouse through (only the cards take it) with a pool of 21 ArmyCards (8 group cards, 10 hull
## cards, "+N", save and idle: none is made or freed in play) and one detail box. refresh() runs on the command view's 4 Hz beat: it
## reads the squad records once, builds one entry per card (counts, hull, state, key labels from the key map) and writes only what
## changed. A click selects (a group card as F does, a hull card the squadrons of that hull); Shift+click on a group card adds the
## selection to that group (as Shift+F) and on a hull card adds its squadrons to the selection; a double-click selects and centres
## the camera (as F twice) when a selection may move it (docked, or the board open). In the command view's slim display (field mode)
## only the group cards show: the hull cards, the save card and the Idle card are left out. The detail (a row for each squadron: its tag,
## ships, state and hull) opens after the mouse has rested on a card for RtsUiCalls.CARD_HOVER_S, or while a group's key is held that long.
## A group card's detail ends in three buttons, "Set to selection", "Add selection" and "Remove selection" (the left routes of
## Ctrl+F and Shift+F, with those keys on them from the key map), and stays open while the pointer is on it.
## Counted in _process from the frame time, so it needs no timer and no tween. Everything here is screen state: it reads the match
## and gives no order; a click only changes the selection, the groups and the camera.
##
## WHO USES IT: CommandView (makes it, places it, refreshes it); tests/rts_army_check.gd.

## The row's height and the room it takes above the selection panel (the row plus its gap), in pixels.
const ROW_H := 30.0
const ROOM := 34.0
## The gap between cards, the most cards at the normal width, and the narrowest a card gets.
const GAP := 5.0
const FIT := 8
const MIN_W := 40.0
## The widest detail lines shown (the rest is "and N more").
const DETAIL_LINES := 12
## The detail box's width and its line height (pixels).
const DETAIL_W := 200.0
const DETAIL_LINE_H := 14.0
## The height of one button of a group card's detail (pixels), and the buttons in order.
const DETAIL_BTN_H := 16.0
const DETAIL_ACTS := ["set", "add", "remove"]
## The pool: where each kind starts. Group cards 0-7, hull cards 8-17, then "+N", save and idle.
const HULL_AT := 8
const FOLD_AT := 18
const SAVE_AT := 19
const IDLE_AT := 20
const POOL := 21
## The state sign of each squad state (Squad.state: idle, moving, fighting, retreating, docked, refitting, launching).
const STATE_SIGN := ["idle", "moving", "fighting", "retreating", "docked", "docked", "moving"]
## The order signs win a tie in: fighting ahead of moving ahead of idle.
const SIGN_RANK := ["fighting", "moving", "idle", "retreating", "docked"]

## The command view this belongs to (set by setup()).
var view: CommandView
## The cards of the pool, and the ones shown now (in order).
var _cards: Array[ArmyCard] = []
var _shown: Array[ArmyCard] = []
## The squadron ids under attack (set_attacked()).
var _attacked := {}
## The detail box, its lines, the card it shows and the card the mouse rests on.
var _detail: Control
var _lines: Array[Label] = []
## The three buttons of a group card's detail, in DETAIL_ACTS' order: "Set to selection", "Add selection", "Remove selection".
var _btns: Array[Button] = []
var _open: ArmyCard
var _hover: ArmyCard
## Seconds the mouse has rested on _hover and a group key has been held.
var _hover_t := 0.0
var _held_t := 0.0
## How many entries the last refresh made (the tour and the checks read it).
var entries: Array = []
## The four strength weights the win-odds mark reads this beat (empty while the option is off).
var _odds_w: Array = []


## Make the pool and the detail box and remember the view.
func setup(v: CommandView) -> void:
	view = v
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "ArmyCards"
	for i in POOL:
		var c := ArmyCard.new()
		c.setup()
		c.fit(ArmyCard.W)
		var card := c
		c.clicked.connect(func(shift: bool, double: bool) -> void: click(card, shift, double))
		c.mouse_entered.connect(func() -> void: _on_hover(card))
		c.mouse_exited.connect(func() -> void: _on_unhover(card))
		add_child(c)
		_cards.append(c)
	_detail = Control.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.visible = false
	_detail.draw.connect(func() -> void: _detail.draw_style_box(RtsTheme.look("row"), Rect2(Vector2.ZERO, _detail.size)))
	add_child(_detail)
	for i in DETAIL_LINES + 2:
		var l := UiKit.label("", 9, Palette.ICE)
		l.clip_text = true
		_detail.add_child(l)
		_lines.append(l)
	for how: String in DETAIL_ACTS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = &"RtsStrip"
		b.add_theme_font_size_override("font_size", 9)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.visible = false
		var act := how
		b.pressed.connect(func() -> void: detail_action(act))
		_detail.add_child(b)
		_btns.append(b)


## Mark the squadrons `ids` as under attack: the cards that hold one wear the steady danger frame (the alert rules of a later stage
## call this; an empty list clears it).
func set_attacked(ids: Array[int]) -> void:
	_attacked.clear()
	for id in ids:
		_attacked[id] = true


# --- refresh ------------------------------------------------------------------------------------------

## Rebuild the entries from the squad records and write the cards (the view's 4 Hz beat).
func refresh() -> void:
	var w := view.world
	# The win-odds weights are read once a beat, and only while the option is on.
	_odds_w = WinOdds.weights_of(w) if Game.win_odds else []
	var recs := RtsSelect.our_squads(w, view.team)
	var info := {}
	for rec: Squad in recs:
		var ships := RtsSelect.ships_of(w, rec)
		var hull := 0.0
		for s: Ship in ships:
			hull += s.hull_frac()
		info[rec.id] = {"rec": rec, "alive": ships.size(), "max": maxi(1, rec.max_members), "hull": hull, "sign": str(STATE_SIGN[clampi(rec.state, 0, STATE_SIGN.size() - 1)])}
	var groups := view.groups
	var picked: Array[int] = view.overlay.sel_squads
	var out: Array = []
	var grouped := {}
	for n in range(1, Groups.COUNT + 1):
		var ids := groups.members(n)
		if ids.is_empty():
			continue
		for id in ids:
			grouped[id] = true
		out.append(_entry("group", ids, info, picked, n))
	# The slim display (field mode) shows the group chips only: no hull cards, no save card, no Idle card.
	if view.is_slim():
		entries = out
		_apply(out)
		if _open != null:
			_fill_detail(_open)
		return
	var by_hull := {}
	for rec: Squad in recs:
		if not grouped.has(rec.id):
			if not by_hull.has(rec.hull_id):
				var none: Array[int] = []
				by_hull[rec.hull_id] = none
			(by_hull[rec.hull_id] as Array[int]).append(rec.id)
	var classes: Array = []
	for hull: String in Ships.ORDER:
		if by_hull.has(hull):
			classes.append(_entry("class", by_hull[hull], info, picked, 0, hull))
	var save_n := groups.first_free()
	var slots := out.size() + classes.size() + (1 if save_n > 0 else 0) + 1
	if slots > FIT and classes.size() > 1:
		out.append(_fold_entry(classes))
	else:
		out.append_array(classes)
	if save_n > 0:
		out.append(_save_entry(save_n))
	out.append(_idle_entry(info, picked))
	entries = out
	_apply(out)
	if _open != null:
		_fill_detail(_open)


## The entry of a card for squadrons `ids`: counts, hull, the state sign, the key label and tag, and the detail lines.
func _entry(kind: String, ids: Array[int], info: Dictionary, picked: Array[int], n: int, hull_id: String = "") -> Dictionary:
	var alive := 0
	var bought := 0
	var hull := 0.0
	var signs := {}
	var hulls := {}
	var danger := false
	var all_picked := not ids.is_empty()
	var lines: Array[String] = []
	for id in ids:
		if not info.has(id):
			continue
		var d: Dictionary = info[id]
		var rec: Squad = d["rec"]
		alive += int(d["alive"])
		bought += int(d["max"])
		hull += float(d["hull"])
		signs[d["sign"]] = int(signs.get(d["sign"], 0)) + 1
		hulls[rec.hull_id] = int(hulls.get(rec.hull_id, 0)) + 1
		danger = danger or _attacked.has(id)
		all_picked = all_picked and picked.has(id)
		lines.append("%s  %d/%d  %s  %d%%" % [_tag_of(rec.hull_id), int(d["alive"]), int(d["max"]), str(SelectionPanel.STATE_WORDS[clampi(rec.state, 0, SelectionPanel.STATE_WORDS.size() - 1)]), int(100.0 * float(d["hull"]) / float(d["max"]))])
	var main := hull_id
	if main == "":
		var best := 0
		for h: String in hulls:
			if int(hulls[h]) > best:
				best = int(hulls[h])
				main = h
	var key := KeyMap.first_key("shared", "group_%d" % n) if n > 0 else ""
	var tag := _tag_of(main)
	var label := str(Ships.HULLS[main]["label"]) if Ships.HULLS.has(main) else tag
	var tip := ""
	if kind == "group":
		tip = "Group %s: %s, %d of %d ships. Click selects it, Shift+click adds your selection to it, double-click selects it and centres the camera. The group's key held down opens this list." % [key, RtsSquadOrders.squads_word(ids.size()), alive, bought]
	else:
		tip = "%s squadrons in no group: %s, %d of %d ships. Click selects them, Shift+click adds them to the selection, double-click selects them and centres the camera." % [label, RtsSquadOrders.squads_word(ids.size()), alive, bought]
	# The win-odds mark (the option, off by default): "" when it is off or no enemy ship is in sight near the squadrons.
	var odds := ""
	if Game.win_odds and not ids.is_empty():
		var mark := str(WinOdds.of(view.world, ids, _odds_w)["mark"])
		odds = "" if mark == "none" else mark
	if odds != "":
		tip += " %s against the enemy ships your team sees near it: a guess from ship sizes only; it ignores missiles, armour sections and energy routing." % WinOdds.words(odds)
	return {"kind": kind, "key": key, "tag": tag, "count": "%d sq · %d/%d" % [ids.size(), alive, bought], "state": _top_sign(signs), "hull": hull / float(maxi(1, bought)),
		"danger": danger, "picked": all_picked, "tip": tip, "ids": ids, "n": n, "code": _key_code(n), "lines": lines, "odds": odds,
		"head": "%s %s  %d sq  %d/%d ships" % [key, tag, ids.size(), alive, bought]}


## The "+N" card: the hull cards that did not fit, listed in its detail.
func _fold_entry(classes: Array) -> Dictionary:
	var lines: Array[String] = []
	var ids: Array[int] = []
	for e: Dictionary in classes:
		lines.append("%s  %s  %s" % [e["tag"], e["count"], e["tip"].split(".")[0]])
		for id in e["ids"]:
			ids.append(id)
	return {"kind": "fold", "key": "", "tag": "+%d" % classes.size(), "count": "classes", "state": "", "hull": -1.0, "danger": classes.any(func(e: Dictionary) -> bool: return bool(e["danger"])),
		"picked": false, "tip": "%d more kinds of squadron in no group. Rest the mouse here to list them." % classes.size(), "ids": ids, "n": 0, "code": 0,
		"lines": lines, "head": "+%d kinds in no group" % classes.size(), "classes": classes}


## The empty "F5 + save" card: the first free group, which a click sets to the selection.
func _save_entry(n: int) -> Dictionary:
	var key := KeyMap.first_key("shared", "group_%d" % n)
	var none_ids: Array[int] = []
	var none_lines: Array[String] = []
	return {"kind": "save", "key": key, "tag": "+ save", "count": "", "state": "", "hull": -1.0, "danger": false, "picked": false,
		"tip": "Save the selection as group %s (the same as %s with Ctrl held)." % [key, key], "ids": none_ids, "n": n, "code": 0, "lines": none_lines, "head": ""}


## The Idle card: how many squadrons are idle, "next" on a click and "all" on a double-click.
func _idle_entry(info: Dictionary, picked: Array[int]) -> Dictionary:
	var ids := view.tools.idle_ids()
	var lines: Array[String] = []
	for id in ids:
		if info.has(id):
			var d: Dictionary = info[id]
			lines.append("%s  %d/%d  idle  %d%%" % [_tag_of((d["rec"] as Squad).hull_id), int(d["alive"]), int(d["max"]), int(100.0 * float(d["hull"]) / float(d["max"]))])
	var key := KeyMap.first_key("home", "idle_next")
	var all_picked := not ids.is_empty()
	for id in ids:
		all_picked = all_picked and picked.has(id)
	return {"kind": "idle", "key": key, "tag": "IDLE", "count": "%d sq" % ids.size(), "state": "idle", "hull": -1.0, "danger": false, "picked": all_picked,
		"tip": "Squadrons with nothing to do: %d. Click selects the next one and centres the camera on it (%s); double-click selects them all (%s)." % [ids.size(), key, KeyMap.first_key("home", "idle_all")],
		"ids": ids, "n": 0, "code": 0, "lines": lines, "head": "Idle  %d sq" % ids.size()}


## The tag of hull `hull_id`.
func _tag_of(hull_id: String) -> String:
	return str(HullTables.TAGS.get(hull_id, hull_id.left(3).to_upper()))


## The state sign of the most common state among `signs` ({sign -> count}); a tie goes to the sign first in SIGN_RANK.
func _top_sign(signs: Dictionary) -> String:
	var best := ""
	var best_n := 0
	for s: String in SIGN_RANK:
		if int(signs.get(s, 0)) > best_n:
			best_n = int(signs[s])
			best = s
	return best


## The key code of group `n`'s first key (0 for none), for the held-key detail.
func _key_code(n: int) -> int:
	if n <= 0:
		return 0
	for text: String in KeyMap.effective_keys("shared", "group_%d" % n):
		var p := KeyCodes.parse(text)
		if bool(p["ok"]) and not bool(p["mouse"]):
			return int(p["code"])
	return 0


## Give each entry its card, hide the others and place the shown ones in a row (narrower past eight, never wider than 74).
func _apply(list: Array) -> void:
	var gi := 0
	var hi := HULL_AT
	var shown: Array[ArmyCard] = []
	for e: Dictionary in list:
		var c: ArmyCard
		match str(e["kind"]):
			"group":
				c = _cards[gi]
				gi += 1
			"class":
				c = _cards[hi]
				hi += 1
			"fold":
				c = _cards[FOLD_AT]
			"save":
				c = _cards[SAVE_AT]
			_:
				c = _cards[IDLE_AT]
		shown.append(c)
	var n := shown.size()
	var width := clampf((size.x - GAP * float(maxi(0, n - 1))) / float(maxi(1, n)), MIN_W, ArmyCard.W)
	var x := 0.0
	for i in n:
		var c := shown[i]
		if absf(c.size.x - width) > 0.5:
			c.fit(width)
		c.position = Vector2(x, 0.0)
		c.visible = true
		c.show_data(list[i])
		x += width + GAP
	for c in _cards:
		if not shown.has(c):
			c.visible = false
			if c == _hover:
				_hover = null
	_shown = shown
	if _open != null and not shown.has(_open):
		_close()


# --- clicks -------------------------------------------------------------------------------------------

## A click on `card` (the pressed signal of its Button, with Shift and the double-click flag): what the card's kind means.
func click(card: ArmyCard, shift: bool, double: bool) -> void:
	var ov := view.overlay
	var ids: Array[int] = []
	ids.assign(card.data.get("ids", []))
	var may_move := ov.select_allowed()
	match card.kind:
		"group":
			var n := int(card.data["n"])
			if shift:
				view.groups.add_from_selection(n)
			elif double:
				if view.groups.pick(n) and may_move:
					view.groups.centre(n)
			else:
				view.groups.pick(n)
		"class":
			ov.set_selection(ids, false, shift or ov.add_mode)
			if double and may_move:
				_centre_on(ids)
		"save":
			view.groups.set_from_selection(int(card.data["n"]))
		"idle":
			if double:
				view.tools.all()
			else:
				view.tools.next(true)
		"fold":
			_hover = card
			_hover_t = RtsUiCalls.CARD_HOVER_S
	view.refresh()


## Put the camera on the middle of squadrons `ids`.
func _centre_on(ids: Array[int]) -> void:
	if ids.is_empty():
		return
	var sum := Vector2.ZERO
	for id in ids:
		sum += RtsSelect.centre_of(view.world, view.world.squads[id])
	Groups.centre_on(view.world, sum / float(ids.size()))


# --- the detail ---------------------------------------------------------------------------------------

## The mouse came onto `card`: start counting its rest.
func _on_hover(card: ArmyCard) -> void:
	_hover = card
	_hover_t = 0.0


## The mouse left `card`.
func _on_unhover(card: ArmyCard) -> void:
	if _hover == card:
		_hover = null
		_hover_t = 0.0


## Every frame: count the mouse's rest on a card and the time a group key is held; open the detail at RtsUiCalls.CARD_HOVER_S, close it
## when neither holds.
func _process(dt: float) -> void:
	if not is_visible_in_tree():
		if _open != null:
			_close()
		return
	var target: ArmyCard = null
	var held := _held_card()
	if held != null:
		_held_t += dt
		if _held_t >= RtsUiCalls.CARD_HOVER_S:
			target = held
	else:
		_held_t = 0.0
	if target == null and _hover != null:
		_hover_t += dt
		if _hover_t >= RtsUiCalls.CARD_HOVER_S:
			target = _hover
	# A group card's detail has buttons: it stays open while the pointer is on it.
	if target == null and _open != null and _open.kind == "group" and in_detail(get_local_mouse_position()):
		target = _open
	if target != _open:
		if target == null:
			_close()
		else:
			_open = target
			_fill_detail(target)


## The group card whose key is held down now (no Ctrl or Shift: those set and add), or null.
func _held_card() -> ArmyCard:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT):
		return null
	for c in _shown:
		if c.kind == "group":
			var code := int(c.data.get("code", 0))
			if code != 0 and Input.is_physical_key_pressed(code as Key):
				return c
	return null


## Write the detail box for `card`: its head and a line for each squadron (the first DETAIL_LINES, then "and N more"), above the card.
func _fill_detail(card: ArmyCard) -> void:
	var head := str(card.data.get("head", ""))
	var list: Array = card.data.get("lines", [])
	var n := mini(list.size(), DETAIL_LINES)
	var more := list.size() - n
	var shown := 1 + n + (1 if more > 0 else 0)
	for i in _lines.size():
		var l := _lines[i]
		l.visible = i < shown
		if i == 0:
			RtsBeat.set_if_changed(l, head)
		elif i <= n:
			RtsBeat.set_if_changed(l, str(list[i - 1]))
		elif i == n + 1 and more > 0:
			RtsBeat.set_if_changed(l, "and %d more" % more)
		l.position = Vector2(6.0, 4.0 + float(i) * DETAIL_LINE_H)
		l.size = Vector2(DETAIL_W - 12.0, DETAIL_LINE_H)
	var h := 8.0 + float(shown) * DETAIL_LINE_H
	# A group card's detail ends in its three buttons (the left routes of Ctrl+F and Shift+F, and Remove), each with its key.
	var group := card.kind == "group"
	var key := str(card.data.get("key", ""))
	for i in _btns.size():
		var b := _btns[i]
		RtsBeat.flag(b, group)
		if not group:
			continue
		RtsBeat.set_if_changed(b, detail_label(DETAIL_ACTS[i], key))
		b.tooltip_text = detail_tip(DETAIL_ACTS[i], key)
		b.position = Vector2(4.0, h)
		b.size = Vector2(DETAIL_W - 8.0, DETAIL_BTN_H)
		h += DETAIL_BTN_H + 1.0
	if group:
		h += 3.0
	_detail.size = Vector2(DETAIL_W, h)
	# No gap under a group's detail, so the pointer can go from the card onto the buttons.
	_detail.position = Vector2(clampf(card.position.x, 0.0, maxf(0.0, size.x - DETAIL_W)), -h - (0.0 if group else 2.0))
	_detail.visible = true
	_detail.queue_redraw()


## The words on detail button `how` ("set", "add" or "remove") of the group whose key label is `key`: the key the button
## stands for comes first (Ctrl or Shift with the group's key from the key map); Remove has no key and prints none.
static func detail_label(how: String, key: String) -> String:
	match how:
		"set":
			return "Set to selection" if key == "" else "Ctrl+%s  Set to selection" % key
		"add":
			return "Add selection" if key == "" else "Shift+%s  Add selection" % key
	return "Remove selection"


## The tip of detail button `how` of the group whose key label is `key`.
static func detail_tip(how: String, key: String) -> String:
	match how:
		"set":
			return "Make group %s the selected squadrons." % key
		"add":
			return "Add the selected squadrons to group %s." % key
	return "Take the selected squadrons out of group %s." % key


## A detail button was pressed: do `how` ("set", "add" or "remove") with the selection for the open group card's group.
## False when no group card's detail is open or the groups refused (nothing selected; the result line says so).
func detail_action(how: String) -> bool:
	if _open == null or _open.kind != "group":
		return false
	var n := int(_open.data["n"])
	var ok := false
	match how:
		"set":
			ok = view.groups.set_from_selection(n)
		"add":
			ok = view.groups.add_from_selection(n)
		"remove":
			ok = view.groups.remove_from_selection(n)
	view.refresh()
	return ok


## Is row point `p` on the open detail box (2 px around it count)?
func in_detail(p: Vector2) -> bool:
	return _detail.visible and Rect2(_detail.position, _detail.size).grow(2.0).has_point(p)


## Close the detail.
func _close() -> void:
	_open = null
	_detail.visible = false


## Is the detail open, and for which card (the checks read this).
func open_card() -> ArmyCard:
	return _open
