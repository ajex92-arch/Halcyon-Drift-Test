extends Node
## WHAT THIS IS: the check that a new build-list entry starts with Repeat off, for every hull and for the drone, however the
## Admiral queues it: Repeat comes only from a press on a Repeat button (or a click that carries Alt).
##
## HOW IT WORKS: it waits for the HUD and the command view of an Admiral seat and runs four parts, each printing PASS or
## FAIL lines that start with "repeat_default_check": "cells" presses the Build cell of each of the ten hulls (the grid, or the
## Capitals pop-out) with nothing held down, and checks that the team's Repeat flag for the hull is off and that the new row of
## the production panel shows Repeat off; "keys" does the same through the digit keys of the card; "drone" queues a mining
## drone from the Build page and checks that its row has no Repeat; "toggle" presses the Repeat cell (the next entry has
## Repeat on, the one after the second press has it off again) and then queues two hulls, to check that one hull's Repeat
## never lands on another's; "held" holds Alt down in the game's key state (a key whose release never reached the game) while
## a Build cell is clicked with the mouse, and the click itself carries no Alt (Repeat must stay off); "alt click" clicks with
## Alt in the click (Repeat on for that entry). Money is held at 0, so no item starts and each one stays in the list to be
## read. It ends with
## "repeat_default_check: N failures (M checks)" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --unlock-all --team=vhorr --difficulty=hard --test=repeat_default_check
##
## WHO USES IT: main.gd loads it for --test=repeat_default_check; run_checks has a row for it.

## The running match (set by setup()).
var world: World
## The HUD, once found.
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many checks failed and how many were made.
var failures := 0
var checks := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Quit after 120 s of real time; start once the HUD and the command view exist.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 120000:
		print("repeat_default_check: timeout")
		get_tree().quit()
		return
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or hud.command_view == null or world.human == null or world.phase != "play":
		return
	started = true
	_run()


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(30)
	hud._close_others(null)
	var view := hud.command_view
	if world.human_role != "admiral" or not view.is_showing():
		_check(false, "setup: an Admiral seat with the command view showing")
	else:
		var ts: TeamState = world.teams[view.team]
		ts.treasury = 0.0
		await _cells(view)
		await _keys(view)
		await _drone(view)
		await _toggle(view)
		await _held(view)
	print("repeat_default_check: %d failures (%d checks)" % [failures, checks])
	get_tree().quit()


## Count one check and print its line.
func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s repeat_default_check: %s" % ["PASS" if ok else "FAIL", what])


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Team 0's or 1's build list: the viewer's team.
func _prod(view: CommandView) -> Production:
	return (world.teams[view.team] as TeamState).production


## Empty the build list (nothing in it has started, the money is 0) so the next press has room.
func _clear_list(view: CommandView) -> void:
	_prod(view).items.clear()


## The newest ship item of `hull` in the list, or an empty Dictionary.
func _newest(view: CommandView, hull: String) -> Dictionary:
	var items: Array = _prod(view).items
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if it["kind"] == Production.SHIP and it["what"] == hull:
			return it
	return {}


## The production panel's snapshot of item `it`: {} when no row shows it.
func _row_of(view: CommandView, it: Dictionary) -> Dictionary:
	view.prod.refresh()
	for e: Dictionary in view.prod._entries:
		if (e["ids"] as Array).has(str(it["id"])):
			return view.prod._snapshot(_prod(view), e, {})
	return {}


## Press the Build cell of `hull` the way a click does: through the pressed signal of its button (the grid, or the Capitals pop-out).
func _press_cell(view: CommandView, hull: String) -> bool:
	var card := view.card
	card.set_page("build")
	card.close_list()
	card.refresh()
	for i in card._grid.size():
		if card._grid_ids[i] == hull and card._grid[i].visible:
			card._grid[i].pressed.emit()
			return true
	card.toggle_list("pop")
	var ids := card._list_ids()
	for i in ids.size():
		if str(ids[i]) == hull and card._entries[i].visible:
			card._entries[i].pressed.emit()
			card.close_list()
			return true
	card.close_list()
	return false


## The check of one new item of `hull`: Repeat is off in the team's flag and in the panel row.
func _judge(view: CommandView, hull: String, how: String) -> void:
	var it := _newest(view, hull)
	if it.is_empty():
		_check(false, "%s %s: the press queued nothing" % [how, hull])
		return
	var flag := int(_prod(view).repeat.get(hull, 0))
	var row := _row_of(view, it)
	var shown := bool(row.get("repeat", false)) if not row.is_empty() else false
	_check(flag == 0 and not shown and row.has("repeat"), "%s %s: a new entry starts with Repeat off (flag %d, row shows %s)" % [how, hull, flag, "on" if shown else "off"])


# --- 1. the Build cells -------------------------------------------------------------------------------

## Press each hull's Build cell with nothing held down.
func _cells(view: CommandView) -> void:
	for hull: String in Ships.ORDER:
		_clear_list(view)
		var pressed := _press_cell(view, hull)
		await _frames(3)
		_check(pressed, "cells %s: the Build page has a cell for it" % hull)
		if pressed:
			_judge(view, hull, "cells")
	_clear_list(view)


# --- 2. the digit keys --------------------------------------------------------------------------------

## The digit key of each hull, as a key event without Alt or Shift.
func _keys(view: CommandView) -> void:
	for i in Ships.ORDER.size():
		var hull := str(Ships.ORDER[i])
		_clear_list(view)
		var ev := InputEventKey.new()
		ev.pressed = true
		var keys := KeyMap.effective_keys("home", "hull_%d" % (i + 1))
		if keys.is_empty():
			_check(false, "keys %s: the hull has a digit key" % hull)
			continue
		var parsed := KeyCodes.parse(String(keys[0]))
		ev.physical_keycode = int(parsed["code"]) as Key
		ev.keycode = ev.physical_keycode
		var took := view.card.key(ev)
		await _frames(3)
		_check(took, "keys %s: the digit key is taken by the card" % hull)
		if took:
			_judge(view, hull, "keys")
	_clear_list(view)


# --- 3. the drone ---------------------------------------------------------------------------------------

## A mining drone from the Build page: its row has no Repeat, and no hull's flag moved.
func _drone(view: CommandView) -> void:
	_clear_list(view)
	_prod(view).repeat.clear()
	var card := view.card
	card.set_page("build")
	card.refresh()
	var pressed := false
	for i in 3:
		if card._extra_ids[i] == "drone" and card._extra[i].visible:
			card._extra[i].pressed.emit()
			pressed = true
	if not pressed:
		for i in card._grid.size():
			if card._grid_ids[i] == "drone" and card._grid[i].visible:
				card._grid[i].pressed.emit()
				pressed = true
	await _frames(3)
	_check(pressed, "drone: the Build page has a Drone cell")
	var it: Dictionary = {}
	for x: Dictionary in _prod(view).items:
		if x["kind"] == Production.DRONE:
			it = x
	if it.is_empty():
		_check(false, "drone: the press queued a drone")
	else:
		var row := _row_of(view, it)
		_check(not row.is_empty() and not bool(row.get("can_repeat", true)) and not bool(row.get("repeat", true)), "drone: its row has no Repeat (can_repeat %s, repeat %s)" % [str(row.get("can_repeat")), str(row.get("repeat"))])
	_check(_prod(view).repeat.is_empty(), "drone: no hull was put on repeat (%s)" % str(_prod(view).repeat))
	_clear_list(view)


# --- 4. the Repeat cell ---------------------------------------------------------------------------------

## The Repeat cell is the one way to turn Repeat on: on, the next entry has it; off again, the entry after has not.
func _toggle(view: CommandView) -> void:
	_prod(view).repeat.clear()
	var card := view.card
	card.set_page("build")
	card.refresh()
	_check(not bool(view.yard["repeat"]), "toggle: the Repeat cell starts off")
	_press_extra(view, "repeat")
	await _frames(2)
	_check(bool(view.yard["repeat"]), "toggle: a press turns the Repeat cell on")
	_clear_list(view)
	_press_cell(view, "lance")
	await _frames(3)
	_check(int(_prod(view).repeat.get("lance", 0)) == 1, "toggle: with the Repeat cell on, a Lance entry has Repeat on")
	_check(int(_prod(view).repeat.get("fighter", 0)) == 0, "toggle: another hull's Repeat is not touched (fighter)")
	_press_extra(view, "repeat")
	await _frames(2)
	_check(not bool(view.yard["repeat"]), "toggle: a second press turns the Repeat cell off")
	_clear_list(view)
	_press_cell(view, "lance")
	await _frames(3)
	_judge(view, "lance", "toggle")
	_clear_list(view)
	_prod(view).repeat.clear()


## Press the extra cell `id` of the Build page.
func _press_extra(view: CommandView, id: String) -> void:
	var card := view.card
	card.set_page("build")
	card.refresh()
	for i in 3:
		if card._extra_ids[i] == id:
			card._extra[i].pressed.emit()


# --- 5. a held key --------------------------------------------------------------------------------------

## Alt is down in the game's key state although the player holds nothing (a key whose release never reached the window, as
## can happen around the Alt+Enter that switches to full screen): a mouse click on a Build cell must not turn Repeat on by
## itself, because the click itself carries no Alt. A click that does carry Alt (the player holds it) still turns it on.
func _held(view: CommandView) -> void:
	_prod(view).repeat.clear()
	_clear_list(view)
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_ALT
	down.physical_keycode = KEY_ALT
	down.alt_pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var held := Input.is_key_pressed(KEY_ALT)
	var clicked := await _click_cell(view, "lance", false)
	await _frames(3)
	var up := InputEventKey.new()
	up.pressed = false
	up.keycode = KEY_ALT
	up.physical_keycode = KEY_ALT
	Input.parse_input_event(up)
	await _frames(2)
	_check(held, "held: the setup holds Alt in the key state")
	_check(clicked, "held: the mouse click reached the Build cell")
	_judge(view, "lance", "held")
	_clear_list(view)
	_prod(view).repeat.clear()
	# The same click with Alt in the click itself (the key state of the game is clear again): Repeat is on for that entry.
	_check(not Input.is_key_pressed(KEY_ALT), "alt click: the setup holds no Alt in the key state")
	clicked = await _click_cell(view, "lance", true)
	await _frames(3)
	_check(clicked and int(_prod(view).repeat.get("lance", 0)) == 1, "alt click: a click that carries Alt turns Repeat on for that entry (flag %d)" % int(_prod(view).repeat.get("lance", 0)))
	_clear_list(view)
	_prod(view).repeat.clear()


## Click the Build cell of `hull` with the mouse: a press and a release at the middle of its button, the click's own Alt flag
## `alt`. False when the page shows no such cell.
func _click_cell(view: CommandView, hull: String, alt: bool) -> bool:
	var card := view.card
	card.set_page("build")
	card.close_list()
	card.refresh()
	for i in card._grid.size():
		if card._grid_ids[i] == hull and card._grid[i].visible:
			var at: Vector2 = (card._grid[i] as Control).get_global_rect().get_center()
			for pressed: bool in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = at
				ev.global_position = at
				ev.alt_pressed = alt
				ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
				Input.parse_input_event(ev)
				await get_tree().process_frame
			return true
	return false
