extends Node
## WHAT THIS IS: the tooltip check. It opens every tooltip the game's screens have, the way a player
## does (the pointer rests on a control), at three window sizes, and measures the box that Godot shows
## against the window. A tooltip that leaves the window is a failure (the user's bug of Thu 2026-11-05:
## the start screen's long toggle texts ran off the right edge at 2560x1440). It prints how many leave
## the screen and by how many pixels, so the same run gives the before and the after number of a fix.
##
## HOW IT WORKS: it waits until the HUD exists, then for each window size (--ui-size, a list; default
## 1280x720, 1920x1080 and 2560x1440, set on the headless window the way ui_tour does) it collects
## every control that shows with a tooltip: under the HUD (the seat bar, the wing button, the gear
## slots, the ship readout's parts, which have their words from _get_tooltip), the Admiral board's
## tabs (the Admiral seat) and the start screen (put on top of the HUD last, the pilot seat). For
## each one it pushes a mouse move onto the control and waits for Godot's tooltip: a PopupPanel that
## becomes a child of the control, holding the Label. The panel's rectangle and the label's (the
## label can be wider than the panel Godot makes for it) are compared with the window's visible
## rectangle; "off" is how far the worst one sticks out, in window pixels (the window's size) and in
## the units the game lays out in. A control the pointer cannot reach (covered or scrolled away) is
## reported as MISSED and does not count as a failure; a screen that gives fewer tooltips than it
## should (the minimum below) does, so a check that opens nothing cannot pass. The last line is
## "tooltip_check: N failures": one for every tooltip that leaves the window, and one for every
## screen that fell short.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --test-wing --seed=7 --test=tooltip_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --seed=7 --test=tooltip_check
## With --ui-size=1280x720,2560x1440 the sizes are the ones named. --test-wing gives the pilot a wing, so
## the wing button (and its tooltip) shows (a pilot with no --bot buys a Fighter and launches at once, which the flying HUD needs).
##
## HOW TO READ THE OUTPUT: one "tooltip_check TIP ..." line per tooltip (the size, the screen, the control,
## the start of its words, the panel's and the label's rectangle, and "off"), one "tooltip_check SIZE ..." line
## per window size (the count and the worst), "FAIL tooltip_check ..." lines, then "tooltip_check: N
## failures". If the run takes over 120 seconds of real time it prints "tooltip_check: timeout" and quits.
##
## WHO USES IT: main.gd loads it for --test=tooltip_check (see ui_tour.gd for how tests are loaded);
## run_checks runs it for both seats. It reads the HUD, the Admiral board and the start screen and changes
## nothing in the match (it gives the pilot a repair kit, so the kit slot has its tooltip).

## The start screen, put on top of the HUD for its own set of tooltips.
const START_SCENE := preload("res://scenes/ui/start_screen.tscn")
## The Admiral board's tabs, in the order the board lists them.
const BOARD_TABS := ["Research", "Build", "Mothership", "Pilots"]
## The most frames to wait for one tooltip to show after the pointer arrives.
const WAIT_FRAMES := 90
## How many tooltips a screen must give at least (a seat's HUD; the start screen), so an empty run fails.
const MIN_HUD := {"pilot": 12, "admiral": 7}
## ... and how many the start screen must give (its four test toggles).
const MIN_START := 4
## How much of a tooltip's text a line shows.
const TEXT_SHOWN := 28

## The match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## True once the check has started (it runs once).
var started := false
## The window sizes to test (--ui-size).
var sizes: Array[Vector2i] = []
## How many tooltips were measured.
var measured := 0
## How many of them leave the window.
var off_screen := 0
## How many controls the pointer could not reach (not counted as failures).
var missed := 0
## How many failures (see the header).
var failures := 0
## How many tooltips the screen being measured now has given so far.
var _count := 0


## main.gd calls this once, right after the World is built. Remember the world and keep running even if the
## game pauses.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	sizes = _ui_sizes()


## The window sizes: --ui-size=WxH (a list separated by commas), or 1280x720, 1920x1080 and 2560x1440.
func _ui_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in str(Game.opt("ui-size", "1280x720,1920x1080,2560x1440")).split(",", false):
		var xy := part.split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	return out


## Godot calls this every drawn frame. Quit after 120 s of real time; start the check once the HUD exists.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 120000:
		print("tooltip_check: timeout")
		get_tree().quit()
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		return
	started = true
	_run()


## The whole check (see HOW IT WORKS), then the summary line and quit.
func _run() -> void:
	# The pointer rests for half a second before Godot shows a tooltip; a short wait keeps the run short.
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", 0.05)
	var seat := world.human_role
	if seat == "pilot" and world.human != null:
		world.human.inventory[0] = {"id": Items.KIT["id"], "count": 2}
	await _frames(30)
	await _wait_for_seat(seat)
	for sz in sizes:
		get_tree().root.size = sz
		await _frames(12)
		var vr := get_tree().root.get_visible_rect()
		print("tooltip_check WINDOW %dx%d, laid out in %dx%d (scale %.2f)" % [sz.x, sz.y, roundi(vr.size.x), roundi(vr.size.y), float(sz.x) / vr.size.x])
		var before := off_screen
		var total := 0
		# The HUD's own tooltips.
		_count = 0
		await _probe_under(hud, "hud", sz)
		total += _count
		_expect_at_least(_count, int(MIN_HUD.get(seat, 0)), "hud %dx%d" % [sz.x, sz.y])
		# The Admiral board, tab by tab.
		if seat == "admiral":
			hud._toggle_board()
			await _frames(6)
			if hud.board != null:
				for tab: String in BOARD_TABS:
					hud.board._set_tab(tab)
					await _frames(6)
					_count = 0
					await _probe_under(hud.board, "board " + tab, sz)
					total += _count
			hud._toggle_board()
			await _frames(6)
		# The start screen, on top of everything (the pilot's run only, so it is measured once per size).
		if seat == "pilot":
			var start := START_SCENE.instantiate()
			hud.add_child(start)
			await _frames(12)
			_count = 0
			await _probe_under(start, "start", sz)
			total += _count
			_expect_at_least(_count, MIN_START, "start %dx%d" % [sz.x, sz.y])
			hud.remove_child(start)
			start.queue_free()
			await _frames(4)
		print("tooltip_check SIZE %dx%d: %d tooltips, %d leave the window" % [sz.x, sz.y, total, off_screen - before])
	print("tooltip_check TOTAL: %d tooltips measured, %d leave the window, %d not reached" % [measured, off_screen, missed])
	print("tooltip_check: %d failures" % failures)
	get_tree().quit()


## Open the tooltip of every control under `root` that has one and measure it (`screen` names the place in the
## lines; `sz` is the window's size).
func _probe_under(root: Node, screen: String, sz: Vector2i) -> void:
	var targets: Array[Dictionary] = []
	_collect(root, targets)
	for t: Dictionary in targets:
		var at: Vector2 = t["at"]
		await _open_and_measure(t["control"] as Control, at, str(t["name"]), screen, sz)


## Every control under `n` that shows and would show a tooltip: its own words (tooltip_text) or, for the ship
## readout, the words of each of its parts (it answers _get_tooltip). Each entry is {control, at, name}: the
## point (window units) to rest the pointer on.
func _collect(n: Node, out: Array[Dictionary]) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		if c is ShipStatus:
			_collect_parts(c as ShipStatus, out)
		elif c.tooltip_text.strip_edges() != "" and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var at: Variant = _visible_point(c, c.get_global_rect())
			if at != null:
				out.append({"control": c, "at": at, "name": _short_name(c)})
	for child in n.get_children():
		_collect(child, out)


## One entry for each part of the ship readout that has its own tooltip (the first point found for the part).
func _collect_parts(s: ShipStatus, out: Array[Dictionary]) -> void:
	var seen := {}
	var step := 3
	for y in range(0, int(ShipStatus.H), step):
		for x in range(0, int(ShipStatus.W), step):
			var p := Vector2(float(x), float(y))
			var part := s.part_at(p)
			if part == "" or seen.has(part):
				continue
			seen[part] = true
			var at: Variant = _visible_point(s, Rect2(s.get_global_transform() * p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)))
			if at != null:
				out.append({"control": s, "at": at, "name": "ShipStatus/" + part})


## The point to rest the pointer on for control `c`, whose box is `box` (window units): the middle of the part of the box that
## shows, inside the window and inside every scroll area and clipping control above `c`; null when none of it shows.
func _visible_point(c: Control, box: Rect2) -> Variant:
	var r := box.intersection(get_tree().root.get_visible_rect())
	var p := c.get_parent()
	while p != null and r.size.x > 0.0 and r.size.y > 0.0:
		if p is Control and (p is ScrollContainer or (p as Control).clip_contents):
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	if r.size.x < 1.0 or r.size.y < 1.0:
		return null
	return r.get_center()


## A short name for a control: its class and its text (a button's words) or its tooltip's start.
func _short_name(c: Control) -> String:
	var label := ""
	if c is Button:
		label = (c as Button).text
	label = label.replace("\n", " ").strip_edges()
	if label == "":
		label = c.tooltip_text.strip_edges().replace("\n", " ").left(12)
	return "%s[%s]" % [c.get_class(), label]


## Rest the pointer on `target` at `at`, wait for its tooltip, measure it and print the line.
func _open_and_measure(target: Control, at: Vector2, who: String, screen: String, sz: Vector2i) -> void:
	_pointer(at)
	var pop: PopupPanel = null
	for i in WAIT_FRAMES:
		await get_tree().process_frame
		pop = _tooltip_of(target)
		if pop != null:
			await get_tree().process_frame
			break
	if pop == null:
		missed += 1
		var hovered := get_viewport().gui_get_hovered_control()
		print("tooltip_check MISSED %dx%d %s %s (under the pointer: %s)" % [sz.x, sz.y, screen, who, "nothing" if hovered == null else _short_name(hovered)])
		_pointer(Vector2(-50.0, -50.0))
		await _frames(2)
		return
	var label: Label = null
	if pop.get_child_count() > 0:
		label = pop.get_child(0) as Label
	var vr := get_tree().root.get_visible_rect()
	var panel := Rect2(Vector2(pop.position), Vector2(pop.size))
	var drawn := panel
	var text := ""
	if label != null:
		text = label.text
		# The label's own place inside the panel; it can be wider than the panel Godot made for it.
		var need := label.get_combined_minimum_size()
		drawn = Rect2(Vector2(pop.position) + label.position, Vector2(maxf(label.size.x, need.x), maxf(label.size.y, need.y)))
	var off := maxf(_out_of(panel, vr), _out_of(drawn, vr))
	var scale := float(sz.x) / vr.size.x
	measured += 1
	_count += 1
	var leaves := off > 0.5
	if leaves:
		off_screen += 1
		failures += 1
	print("tooltip_check TIP %dx%d %s %s \"%s\" panel=%d,%d %dx%d label=%d,%d %dx%d off=%dpx%s" % [sz.x, sz.y, screen, who, text.replace("\n", " ").left(TEXT_SHOWN),
		roundi(panel.position.x), roundi(panel.position.y), roundi(panel.size.x), roundi(panel.size.y), roundi(drawn.position.x), roundi(drawn.position.y),
		roundi(drawn.size.x), roundi(drawn.size.y), roundi(off * scale), " (%d in layout units)" % roundi(off) if leaves else ""])
	if leaves:
		print("FAIL tooltip_check %dx%d %s %s: the tooltip leaves the window by %d px" % [sz.x, sz.y, screen, who, roundi(off * scale)])
	_pointer(Vector2(-50.0, -50.0))
	await _frames(2)


## The tooltip Godot shows for `target`: a PopupPanel that is a child of the control and visible, or null.
func _tooltip_of(target: Control) -> PopupPanel:
	for child in target.get_children():
		if child is PopupPanel and (child as PopupPanel).visible:
			return child as PopupPanel
	return null


## How far rectangle `r` sticks out of rectangle `window` (0 when it lies inside).
func _out_of(r: Rect2, window: Rect2) -> float:
	var worst := maxf(window.position.x - r.position.x, r.end.x - window.end.x)
	worst = maxf(worst, maxf(window.position.y - r.position.y, r.end.y - window.end.y))
	return maxf(0.0, worst)


## Move the pointer to `at` (window units): a real mouse move pushed into the window.
func _pointer(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	get_viewport().push_input(ev, true)


## A pilot starts docked in the hangar (a bot launches it); wait until the flying HUD shows (the seat bar, the ship readout
## and, with --test-wing, the wing button), so its tooltips can be opened. At most 1800 frames; the screens then fall short and fail.
func _wait_for_seat(seat: String) -> void:
	for i in 1800:
		# The hangar is open when a match starts and stays open after an automatic launch: close every big panel, which hides
		# the seat bar and the wing button.
		hud._close_others(null)
		var flying :=world.human != null and world.human.ship != null and is_instance_valid(world.human.ship) and world.human.ship.alive
		var ready := hud.seat_bar != null and hud.seat_bar.visible
		if seat == "pilot":
			ready = ready and flying
			if Game.opt("test-wing", false) == true:
				ready = ready and hud.wing_strip != null and hud.wing_strip.visible
		if ready:
			await _frames(12)
			return
		await get_tree().process_frame
	print("tooltip_check: the %s's HUD never showed all its parts (flying %s, seat bar shown %s, wanted %s, a panel open %s, wing button shown %s)" % [seat,
		world.human != null and world.human.ship != null and is_instance_valid(world.human.ship), hud.seat_bar != null and hud.seat_bar.visible,
		hud.seat_bar != null and hud.seat_bar.wanted(), hud._any_panel_open(), hud.wing_strip != null and hud.wing_strip.visible])


## A screen must give at least `want` tooltips (a check that opens nothing must not pass).
func _expect_at_least(have: int, want: int, what: String) -> void:
	if have < want:
		failures += 1
		print("FAIL tooltip_check %s: only %d tooltips opened, wanted at least %d" % [what, have, want])


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
