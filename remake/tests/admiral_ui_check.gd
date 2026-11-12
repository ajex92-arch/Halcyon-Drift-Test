extends Node
## WHAT THIS IS: the Admiral screen check for the three things the user's play of Sat 2026-11-07 found: (1) every
## button of the command card leads somewhere that exists (the Doctrine button went to the Mothership tab although no
## Fleet Doctrine card was there), (2) a card button whose research is missing shows it as locked before it is pressed
## (the Repair bay and the Torpedo turret started a place mode first and gave the notice afterwards) and (3) the words
## of the top centre score box, the top-right strip and the Admiral's own panel.
##
## HOW IT WORKS: it waits for the HUD and the command view of an Admiral seat and runs three parts, each printing PASS
## or FAIL lines that start with the part's name: "cards" presses every visible button of the Base page and the Build
## page (and the Orders page when a squadron exists) through its own pressed signal, and for each one checks that its
## target exists: a board tab holding the named card, an armed tool, an open panel or a spoken answer; it also checks that
## the Doctrine button is hidden without the doctrine variant and, with it, opens the Mothership tab scrolled to the Fleet
## Doctrine card. "locked" presses the Repair bay and the Torpedo turret without their research (locked look, tooltip names the
## research, no place mode, the click answers in the result line) and again with it (lit, place mode starts). "words" reads
## every drawn string of the score box, the strip and the Admiral's panel at 1280x720 and at 3440x1279: the old words are
## gone, the new ones are there, the difficulty is a word in the top-right strip, nothing in the strip overlaps and the box
## is narrower than before. Windowed with --shots=<folder> it then saves the pictures of the Base page, the locked Repair bay
## and the score box at both sizes. It ends with "admiral_ui_check: N failures" (0 = all good) and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --force-hud --difficulty=hard --slow=0.75 --test=admiral_ui_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --force-hud --difficulty=hard --slow=0.75 --variant=doctrine:on --test=admiral_ui_check
## (the second run is the one with the Fleet Doctrine card; --slow=0.75 puts the speed word on the screen to look for.)
##
## WHO USES IT: main.gd loads it for --test=admiral_ui_check; run_checks has one row for each of the two runs.

## The window sizes the words are read at.
const SIZES := [Vector2i(1280, 720), Vector2i(3440, 1279)]
## The widest the top centre box may be (pixels): the old box was 692 wide, the new one 564.
const BOX_MAX_W := 580.0
## What each Base and Build button must lead to. A word and, after colons, its parts: "board:<tab>:<card key start>" (the
## Admiral board is open on that tab and holds a card whose key starts so), "tool:<name>" (that map tool is armed),
## "tool_or_locked:<name>" (armed, or the cell is locked and says why), "say" (the result line answers), "locked" (nothing opens,
## nothing is armed), "prod" (the production panel changed its fold), "hangar" (the hangar is open), "pop" (the pop-out is open),
## "hull" (queued, or locked and the research board opens).
const TARGETS := {
	"base/research": "board:Research", "base/drone": "say", "base/deputy": "locked", "base/deputy_preset": "locked",
	"base/turret": "tool:turret", "base/torpedo": "tool_or_locked:torpedo", "base/repair": "tool_or_locked:bay", "base/ward": "tool:ward",
	"base/waypoint": "tool:waypoint", "base/rally": "tool:rally", "base/move": "tool_or_locked:move", "base/cancel": "say",
	"base/production": "prod", "base/hangar": "hangar", "base/defenses": "board:Build:post:", "base/turret_list": "board:Build:node:",
	"base/ms_status": "board:Mothership:ms_status", "base/doctrine": "board:Mothership:doctrine_btn",
	"build/capitals": "pop", "build/drone": "say", "build/size": "say", "build/repeat": "say",
}

## The running match (set by setup()).
var world: World
## The HUD, once found.
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many checks failed and how many were made.
var failures := 0
var checks := 0  # the checks made


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = SIZES[0]
	process_mode = Node.PROCESS_MODE_ALWAYS


## Quit after 150 s of real time; start once the HUD and the command view exist.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 150000:
		print("admiral_ui_check: timeout")
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
	await _frames(40)
	hud._close_others(null)
	print("admiral_ui_check: seat %s, doctrine %s" % [world.human_role, "on" if DoctrineFeature.current() != null else "off"])
	if world.human_role != "admiral" or not hud.command_view.is_showing():
		_check(false, "setup: an Admiral seat with the command view showing")
	else:
		await _cards()
		await _locked()
		await _followup()
		await _words()
		# Windowed with --shots=<folder>: the pictures of the Base page, the locked Repair bay and the score box.
		if DisplayServer.get_name() != "headless" and Game.opt("shots") != null:
			await _shots(str(Game.opt("shots")))
	print("admiral_ui_check: %d failures (%d checks)" % [failures, checks])
	get_tree().quit()


## Count one check and print its line.
func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s admiral_ui_check: %s" % ["PASS" if ok else "FAIL", what])


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- 1. the card's buttons ----------------------------------------------------------------------------

## Press every visible button of the Base page, the Build page and (with a squadron) the Orders page.
func _cards() -> void:
	var view := hud.command_view
	var card := view.card
	var ts: TeamState = world.teams[view.team]
	view.overlay.clear_selection()
	for page_id: String in ["base", "build"]:
		await _press_page(page_id)
	var recs := RtsSelect.our_squads(world, view.team)
	if recs.is_empty():
		print("admiral_ui_check: cards: no squadron yet, the Orders page is left to rts_tour")
	else:
		view.overlay.set_selection([recs[0].id], false)
		await _press_page("orders")
		view.overlay.clear_selection()
	card.set_page("base")
	card.refresh()
	# The Doctrine button exists only with the doctrine variant.
	var on := DoctrineFeature.current() != null
	var more := _more_ids("base")
	_check(on == more.has("doctrine"), "cards: the Doctrine button is %s while the doctrine variant is %s (More list: %s)" % ["shown" if on else "hidden", "on" if on else "off", str(more)])
	if on:
		var tip := str(CardState.snapshot(card, "base", "doctrine")["tip"])
		_check(tip.contains("Mothership") and tip.contains("Fleet Doctrine"), "cards: the Doctrine tip says it opens the Mothership tab at the Fleet Doctrine card ('%s')" % tip)
	print("admiral_ui_check: cards done, treasury %d" % int(ts.treasury))


## The ids of the More list of page `page_id`, as the card would show them.
func _more_ids(page_id: String) -> Array:
	var card := hud.command_view.card
	card.set_page(page_id)
	card.refresh()
	return card._more_ids()


## Press each visible grid and extra button of page `page_id`, then each entry of its More list and Capitals pop-out.
func _press_page(page_id: String) -> void:
	var card := hud.command_view.card
	card.set_page(page_id)
	card.close_list()
	card.refresh()
	var jobs: Array = []
	for i in card._grid.size():
		if card._grid_ids[i] != "" and card._grid[i].visible:
			jobs.append(["grid", i, card._grid_ids[i]])
	for i in 3:
		if card._extra_ids[i] != "" and card._extra[i].visible:
			jobs.append(["extra", i, card._extra_ids[i]])
	for which: String in ["more", "pop"]:
		card.toggle_list(which)
		var ids := card._list_ids()
		for i in ids.size():
			if card._entries[i].visible:
				jobs.append([which, i, str(ids[i])])
		card.close_list()
	_check(not jobs.is_empty(), "cards: the %s page shows buttons (%d)" % [page_id, jobs.size()])
	for j: Array in jobs:
		await _press_one(page_id, str(j[0]), int(j[1]), str(j[2]))


## Press one button and judge where it led.
func _press_one(page_id: String, where: String, idx: int, id: String) -> void:
	var view := hud.command_view
	var card := view.card
	var ov := view.overlay
	await _reset()
	card.set_page(page_id)
	card.refresh()
	var epage := "build" if where == "pop" else page_id
	var before := CardState.snapshot(card, epage, id)
	var items_before: int = (world.teams[view.team] as TeamState).production.items.size()
	var fold_before := view.prod.folded
	match where:
		"grid":
			card._grid[idx].pressed.emit()
		"extra":
			card._extra[idx].pressed.emit()
		_:
			card.toggle_list(where)
			card._entries[idx].pressed.emit()
	await _frames(3)
	var kind := str(TARGETS.get("%s/%s" % [epage, id], ""))
	if kind == "" and epage == "build" and Ships.HULLS.has(id):
		kind = "hull"
	if kind == "" and epage == "orders":
		kind = "locked" if str(before["state"]) == "locked" else "say_or_tool"
	var why := _verdict(kind, before, items_before, fold_before)
	_check(why == "", "cards: %s/%s (%s) %s" % [epage, id, where, "leads to '%s'" % kind if why == "" else "should lead to '%s' but: %s" % [kind, why]])
	if id == "doctrine" and kind != "" and why == "":
		await _doctrine_scrolled()
	await _reset()


## "" when the press led where `kind` says, else what was missing.
func _verdict(kind: String, before: Dictionary, items_before: int, fold_before: bool) -> String:
	var view := hud.command_view
	var ov := view.overlay
	var parts := kind.split(":")
	var locked := str(before["state"]) == "locked"
	match parts[0]:
		"":
			return "no expected target is written for this button"
		"board":
			if hud.board == null or not hud.board.visible:
				return "the Admiral board did not open"
			if hud.board.tab != parts[1]:
				return "the board is on the %s tab" % hud.board.tab
			if parts.size() > 2:
				for k: String in hud.board._cards:
					if k.begins_with(parts[2]):
						return ""
				return "the %s tab holds no card '%s'" % [parts[1], parts[2]]
			return ""
		"tool":
			return "" if ov.tool == parts[1] else "no tool armed (armed: '%s')" % ov.tool
		"tool_or_locked":
			if ov.tool == parts[1]:
				return ""
			return "" if locked and ov.result_text != "" else "no tool armed and no answer (armed: '%s')" % ov.tool
		"say":
			return "" if ov.result_text != "" else "the result line is empty"
		"say_or_tool":
			return "" if ov.result_text != "" or ov.tool != "" else "nothing answered"
		"locked":
			if not locked:
				return "the cell is not locked"
			return "" if ov.tool == "" and (hud.board == null or not hud.board.visible) else "a tool or the board opened"
		"prod":
			return "" if view.prod.folded != fold_before else "the production panel did not change"
		"hangar":
			return "" if hud.hangar != null and hud.hangar.visible else "the hangar is not open"
		"pop":
			return "" if view.card._open == "pop" else "the pop-out did not open"
		"hull":
			if locked:
				return "" if hud.board != null and hud.board.visible and hud.board.tab == "Research" else "a locked hull must open the research board"
			var made: int = (world.teams[view.team] as TeamState).production.items.size() - items_before
			return "" if ov.result_text != "" else "no answer (items added: %d)" % made
	return "unknown kind %s" % kind


## After the Doctrine button: the Fleet Doctrine card is inside what the board's scroll area shows.
func _doctrine_scrolled() -> void:
	await _frames(4)
	var btn := hud.board._cards.get("doctrine_btn") as Control
	var scroll := hud.board.get_node("Col/Scroll") as ScrollContainer
	var ok := btn != null and scroll != null
	var detail := ""
	if ok:
		var b := btn.get_global_rect()
		var s := scroll.get_global_rect()
		ok = b.position.y >= s.position.y - 1.0 and b.end.y <= s.end.y + 1.0
		detail = "card %d..%d, scroll area %d..%d" % [int(b.position.y), int(b.end.y), int(s.position.y), int(s.end.y)]
	_check(ok, "cards: the Doctrine button opens the Mothership tab scrolled to the Fleet Doctrine card (%s)" % detail)


## Put the screen back between two presses: no board, no hangar, no tool, no pop-out, no answer, the production panel open.
func _reset() -> void:
	var view := hud.command_view
	if hud.board != null:
		hud.board.visible = false
	if hud.hangar != null:
		hud.hangar.visible = false
	view.overlay.disarm()
	view.overlay.result_text = ""
	view.overlay.result_ok = true
	view.card.close_list()
	view.prod.set_folded(false)
	await _frames(1)


# --- 2. the locked buttons ----------------------------------------------------------------------------

## Repair bay and Torpedo turret without and with their research, and every locked hull.
func _locked() -> void:
	var view := hud.command_view
	var card := view.card
	var ov := view.overlay
	var ts: TeamState = world.teams[view.team]
	var cases := [["repair", "repair_bays", "Repair Bays", "bay"], ["torpedo", "turret_torp", "Platform Missiles", "torpedo"]]
	for c: Array in cases:
		var id := str(c[0])
		ts.set(str(c[1]), false)
		await _reset()
		card.set_page("base")
		card.refresh()
		var d := CardState.snapshot(card, "base", id)
		_check(str(d["state"]) == "locked", "locked: %s without %s research is drawn locked before it is pressed (state '%s')" % [id, c[2], d["state"]])
		_check(str(d["tip"]).contains(str(c[2])) and str(d["tip"]).to_lower().contains("research"), "locked: the %s tooltip names the research ('%s')" % [id, d["tip"]])
		_press_id(id)
		await _frames(2)
		_check(ov.tool == "", "locked: pressing %s without the research starts no place mode (armed: '%s')" % [id, ov.tool])
		_check(not ov.result_ok and str(ov.result_text).contains(str(c[2])), "locked: the press says which research is missing ('%s')" % ov.result_text)
		await _reset()
		CardActions.run(card, "base", id)
		_check(ov.tool == "", "locked: the key route (CardActions.run) of %s starts no place mode either (armed: '%s')" % [id, ov.tool])
		await _reset()
		ts.set(str(c[1]), true)
		card.refresh()
		d = CardState.snapshot(card, "base", id)
		_check(str(d["state"]) != "locked", "locked: %s with the research is lit (state '%s')" % [id, d["state"]])
		CardActions.run(card, "base", id)
		_check(ov.tool == str(c[3]), "locked: pressing %s with the research arms '%s' (armed: '%s')" % [id, c[3], ov.tool])
		await _reset()
		ts.set(str(c[1]), false)
	# The hulls were already locked looks: their tooltip names what is missing.
	card.set_page("build")
	var bad: Array[String] = []
	for h: String in Ships.ORDER:
		if not ts.ship_unlocked(h):
			var d := CardState.snapshot(card, "build", h)
			if str(d["state"]) != "locked" or not str(d["tip"]).contains("Needs"):
				bad.append(h)
	_check(bad.is_empty(), "locked: every hull without its research is drawn locked with a tooltip that says what it needs (%s)" % str(bad))
	await _reset()


# --- 2b. the follow-up fixes (the user's play notes of Sat 2026-11-07, 15:09 and 20:42 to 20:47) -----------------

## The locked Repair bay is red, the drone cell counts what the limit counts, the paused screen has no "pause menu"
## line, and P only pauses and unpauses (also with a panel open).
func _followup() -> void:
	var view := hud.command_view
	var card := view.card
	var ts: TeamState = world.teams[view.team]
	# Fix 1: the locked Repair bay cell is drawn in the red of a refusal (Palette.DANGER), with its padlock.
	ts.set("repair_bays", false)
	await _reset()
	card.set_page("base")
	card.refresh()
	await _frames(2)
	var cell: CardCell = null
	for i in card._grid.size():
		if card._grid_ids[i] == "repair" and card._grid[i].visible:
			cell = card._grid[i]
	_check(cell != null, "followup: the Repair bay cell is on the Base page")
	if cell != null:
		var edge: Color = cell.get_theme_stylebox("normal").border_color
		_check(edge == Palette.DANGER, "followup: the locked Repair bay cell has the danger red border (border %s, danger %s)" % [str(edge), str(Palette.DANGER)])
		_check(cell._lock.visible and str(cell.data["sub"]) == "research" and str(cell.tooltip_text).contains("Repair Bays"), "followup: the locked Repair bay keeps its padlock, the word research and its tooltip")
	ts.set("repair_bays", true)
	# Fix 2: with the drone limit reached (working plus queued), the Base card's drone cell reads the limit.
	var most := int(Structures.MINING_DRONE["max"])
	var saved := ts.drone_queue.duplicate()
	ts.drone_queue.clear()
	while world.mining_drone_count(view.team) + ts.drones_queued() < most:
		ts.drone_queue.append("auto")
	var d := CardState.snapshot(card, "base", "drone")
	_check(world.command.drone_blocker(view.team).begins_with("Drone limit reached"), "followup: the limit check says the limit is reached")
	_check(str(d["count"]) == "%d/%d" % [most, most], "followup: at the limit the drone cell reads %d/%d (it reads '%s')" % [most, most, d["count"]])
	# ... and the words in the cell show whole: "14/14" fits the count label (a label too narrow showed "4/14", the user's note).
	card.refresh()
	await _frames(2)
	var dcell: CardCell = null
	for i in card._grid.size():
		if card._grid_ids[i] == "drone" and card._grid[i].visible:
			dcell = card._grid[i]
	if dcell != null:
		var shown := dcell._count.text
		var need := dcell._count.get_theme_font("font").get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_check(shown == "%d/%d" % [most, most] and need <= dcell._count.size.x, "followup: the drawn drone count '%s' fits its label (%.1f of %.1f px)" % [shown, need, dcell._count.size.x])
	ts.drone_queue.clear()
	for s in saved:
		ts.drone_queue.append(s)
	# Fix 3: the paused screen has no "pause menu" line.
	get_tree().paused = true
	hud.banner.refresh()
	var said := "%s | %s" % [hud.banner._title.text, hud.banner._sub.text]
	get_tree().paused = false
	hud.banner.refresh()
	_check(not said.to_lower().contains("pause menu"), "followup: the paused screen does not say 'pause menu' ('%s')" % said)
	# Fix 4: P only pauses and unpauses, with a panel open too; the pause menu stays closed.
	for panel: String in ["none", "Research"]:
		await _reset()
		if panel != "none":
			hud.panels.open_board_at(panel)
			await _frames(2)
		_tap_p()
		_check(get_tree().paused and not hud._pause_menu_active(), "followup: P with %s open pauses and the pause menu stays closed (paused %s, menu %s)" % [panel, str(get_tree().paused), str(hud._pause_menu_active())])
		_tap_p()
		_check(not get_tree().paused and not hud._pause_menu_active(), "followup: the second P unpauses, the menu closed (paused %s, menu %s)" % [str(get_tree().paused), str(hud._pause_menu_active())])
	hud._close_others(null)
	await _reset()


## A tap of P through the HUD's key router.
func _tap_p() -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_P
		ev.keycode = KEY_P
		ev.pressed = pressed
		hud.router.handle(ev)


# --- 3. the words ----------------------------------------------------------------------------------------

## The score box, the strip and the Admiral's panel at both window sizes.
func _words() -> void:
	var enemy := Rules.enemy_of(world.human_team)
	var word := Difficulty.name_of(world.teams[enemy].income_mult)
	for sz: Vector2i in SIZES:
		get_tree().root.size = sz
		await _frames(8)
		hud.layout.apply()
		hud.top_bar.refresh(world)
		hud.me_panel.refresh(world)
		hud.command_view.refresh()
		await _frames(2)
		var tag := "%dx%d" % [sz.x, sz.y]
		var box := _texts(hud.top_bar)
		var strip := hud.command_view.strip
		var panel := _texts(hud.me_panel)
		var strip_texts := _texts(strip)
		print("admiral_ui_check: words %s box: %s" % [tag, str(box)])
		print("admiral_ui_check: words %s strip: %s" % [tag, str(strip_texts)])
		print("admiral_ui_check: words %s panel: %s" % [tag, str(panel)])
		print("admiral_ui_check: words %s box width %d" % [tag, int(hud.top_bar.get_combined_minimum_size().x)])
		var box_all := " | ".join(box)
		_check(not box_all.contains("SPEED") and not box_all.to_lower().contains("speed"), "words %s: the score box has no speed line (%s)" % [tag, box_all])
		_check(not box_all.contains("enemy earns") and not box_all.contains("Hard") and not box_all.contains(word), "words %s: the score box has no difficulty (%s)" % [tag, box_all])
		_check(not box_all.contains("%"), "words %s: no percent beside the team names (%s)" % [tag, box_all])
		_check(box_all.contains("Next wave ") and not box_all.contains("minion"), "words %s: 'Next wave' replaces 'Next minion wave' (%s)" % [tag, box_all])
		var diff := strip._b.get("diff") as Button
		_check(diff != null and diff.visible and diff.text == word, "words %s: the difficulty is the word '%s' in the top-right strip ('%s')" % [tag, word, "" if diff == null else diff.text])
		var speed := strip._b["speed"] as Button
		_check(diff != null and diff.position.x > strip.size.x * 0.5 and diff.position.x < speed.position.x + 0.5, "words %s: the difficulty word sits in the strip's right group, left of the speed button" % tag)
		var overlap: Array[String] = []
		var names := strip._b.keys()
		for i in names.size():
			var a := strip._b[names[i]] as Button
			if a.visible and a.position.x + a.size.x > strip.size.x + 0.5:
				overlap.append("%s leaves the strip" % names[i])
			for j in range(i + 1, names.size()):
				var b := strip._b[names[j]] as Button
				if a.visible and b.visible and Rect2(a.position, a.size).intersection(Rect2(b.position, b.size)).size.x > 0.5:
					overlap.append("%s overlaps %s" % [names[i], names[j]])
		_check(overlap.is_empty(), "words %s: the strip's buttons do not overlap (%s)" % [tag, str(overlap)])
		_check(hud.top_bar.get_combined_minimum_size().x <= BOX_MAX_W, "words %s: the score box is narrower (%d wide, at most %d)" % [tag, int(hud.top_bar.get_combined_minimum_size().x), int(BOX_MAX_W)])
		var all := " | ".join(panel)
		_check(all.contains("Team treasury ") and not all.contains("Admiral  ·") and not all.contains("Treasury"), "words %s: 'Team treasury X' replaces 'Admiral - Treasury X' (%s)" % [tag, all])
		var wallet := all.find("Personal Wallet ")
		var drones := all.find("mining drones")
		_check(wallet >= 0 and drones > wallet and not all.contains("Your own ship"), "words %s: 'Personal Wallet X' stands above the mining drones line and the old line is gone (%s)" % [tag, all])
	get_tree().root.size = SIZES[0]


# --- 4. the pictures (windowed, --shots only) -------------------------------------------------------------

## For each window size: the Base page, the Base page with its More list open (the Doctrine entry is there or not), the Repair bay
## drawn locked with the pointer on it (the tooltip, as the engine draws it if it shows in a parked window, and a stand-in card with
## the same words) and the top strip of the screen with the score box, the strip and the Admiral's panel. The names carry the size
## asked for; the line "shots" prints the size the window really has (Windows may clamp it to the work area).
func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var view := hud.command_view
	var card := view.card
	var ts: TeamState = world.teams[view.team]
	for sz: Vector2i in SIZES:
		get_tree().root.size = sz
		await _frames(12)
		var tag := "%dx%d" % [sz.x, sz.y]
		await _reset()
		ts.repair_bays = false
		card.set_page("base")
		hud.layout.apply()
		hud.top_bar.refresh(world)
		hud.me_panel.refresh(world)
		view.refresh()
		await _frames(4)
		print("admiral_ui_check: shots %s asked, the window is %dx%d" % [tag, get_tree().root.size.x, get_tree().root.size.y])
		await _save(dir, "base_%s" % tag, true)
		card.toggle_list("more")
		await _frames(4)
		await _save(dir, "base_more_%s" % tag, false)
		card.close_list()
		await _frames(2)
		var cell := _cell_of("repair")
		if cell != null:
			var at := cell.get_global_rect().get_center()
			var ev := InputEventMouseMotion.new()
			ev.position = at
			ev.global_position = at
			Input.parse_input_event(ev)
			await get_tree().create_timer(1.6).timeout
			await _save(dir, "repair_locked_%s" % tag, false)
			var stand := PanelContainer.new()
			stand.theme_type_variation = &"TooltipPanel"
			stand.add_child(UiKit.label(cell.tooltip_text, 13, Palette.ICE, true))
			stand.custom_minimum_size = Vector2(330.0, 0.0)
			hud.add_child(stand)
			stand.position = Vector2(cell.get_global_rect().position.x, cell.get_global_rect().position.y - 80.0)
			await _frames(4)
			await _save(dir, "repair_locked_standin_%s" % tag, false)
			stand.queue_free()
		await _reset()
	# The follow-up pictures at 1280x720: the drone cell at the limit, and the paused screen after a P.
	get_tree().root.size = SIZES[0]
	await _frames(12)
	card.set_page("base")
	var saved: Array = ts.drone_queue.duplicate()
	while world.mining_drone_count(view.team) + ts.drones_queued() < int(Structures.MINING_DRONE["max"]):
		ts.drone_queue.append("auto")
	view.refresh()
	hud.layout.apply()
	await _frames(3)
	await _save(dir, "drone_limit_1280x720", false)
	ts.drone_queue.clear()
	for s in saved:
		ts.drone_queue.append(s)
	view.refresh()
	_tap_p()
	await _frames(6)
	await _save(dir, "paused_1280x720", false)
	_tap_p()
	await _frames(2)
	await _reset()
	get_tree().root.size = SIZES[0]


## Press the button of Base cell `id` through its pressed signal: in the grid, in the extra row or in the More list.
func _press_id(id: String) -> void:
	var card := hud.command_view.card
	var i := card._grid_ids.find(id)
	if i >= 0:
		card._grid[i].pressed.emit()
		return
	i = card._extra_ids.find(id)
	if i >= 0:
		card._extra[i].pressed.emit()
		return
	card.toggle_list("more")
	var ids := card._list_ids()
	i = ids.find(id)
	if i >= 0:
		card._entries[i].pressed.emit()


## The card cell that shows `id` on the page in force (grid or extra), or null.
func _cell_of(id: String) -> Control:
	var card := hud.command_view.card
	var i := card._grid_ids.find(id)
	if i >= 0:
		return card._grid[i]
	i = card._extra_ids.find(id)
	return card._extra[i] if i >= 0 else null


## Save the window as <name>.png (and with `strip` also the top 150 pixels as <name>_top.png) once the frame is drawn.
func _save(dir: String, shot: String, strip: bool) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(shot + ".png"))
	print("admiral_ui_check: shot %s (%dx%d)" % [shot, img.get_width(), img.get_height()])
	if strip:
		var top := img.get_region(Rect2i(0, 0, img.get_width(), mini(150, img.get_height())))
		top.save_png(dir.path_join(shot + "_top.png"))


## Every visible Label and Button text under `node`, top to bottom.
func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for c in node.get_children():
		if c is Control and not (c as Control).visible:
			continue
		if c is Label and (c as Label).text != "":
			out.append((c as Label).text.replace("\n", " / "))
		elif c is Button and (c as Button).text != "":
			out.append((c as Button).text)
		out.append_array(_texts(c))
	return out
