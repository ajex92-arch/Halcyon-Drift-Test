extends Node
## WHAT THIS IS: the help fit check. It opens the "How to play" panel on each of its four pages (The match,
## Flying, Admiral, Keys) at each of seven window sizes and measures the panel against the window. A panel that
## ends past the window's right or bottom edge, or starts before its left or top edge, is a failure (the Keys page
## ran 46 pixels past the right edge at 1280x720). It prints how far each page sticks out, so the same run gives the
## before and the after number of a fix.
##
## HOW IT WORKS: it waits until the HUD exists, then for each window size (--ui-size, a list; default 1280x720,
## 1920x1080, 2560x1440, 1366x657, 1024x600, 2560x1080 and 1280x1024, set on the headless window the way the tour
## sets it) it opens the help panel (key H) and shows each page with HelpPanel._show(), waits three frames and compares
## the panel's global rectangle with the window's visible rectangle (the units the game lays out in). More than half
## a pixel out at the right or the bottom, or a start before 0, counts as one failure. For the Keys page it also
## prints probe lines that never fail: for each table, the widest cell of each column and the table's own smallest
## width, which say which column makes the panel too wide. The last line is "help_fit_check: N failures".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=help_fit_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --seed=7 --test=help_fit_check
## With --ui-size=1280x720,2560x1440 the sizes are the ones named.
##
## HOW TO READ THE OUTPUT: one "help_fit_check PAGE <size> <page> right <n> bottom <n> left <n>" line per page and
## size (the pixels the panel sticks out on that side, negative when it ends inside the window), "help_fit_check
## KEYS" probe lines, "FAIL help_fit_check ..." lines, then "help_fit_check: N failures". If the run takes over 120
## seconds of real time it prints "help_fit_check: timeout" and quits.
##
## WHO USES IT: main.gd loads it for --test=help_fit_check (see ui_tour.gd for how tests are loaded); run_checks runs
## it for both seats. It reads the HUD and the help panel and changes nothing in the match.

## The window sizes tried when --ui-size is not given.
const DEFAULT_SIZES := "1280x720,1920x1080,2560x1440,1366x657,1024x600,2560x1080,1280x1024"
## How far (layout pixels) the panel may stick out before it counts as a failure.
const TOLERANCE := 0.5

## The match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## True once the check has started (it runs once).
var started := false
## The window sizes to test (--ui-size).
var sizes: Array[Vector2i] = []
## How many failures (see the header).
var failures := 0


## main.gd calls this once, right after the World is built. Remember the world and keep running even if the
## game pauses.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	sizes = _ui_sizes()


## The window sizes: --ui-size=WxH (a list separated by commas), or the seven of DEFAULT_SIZES.
func _ui_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in str(Game.opt("ui-size", DEFAULT_SIZES)).split(",", false):
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
		print("help_fit_check: timeout")
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
	await _frames(30)
	var pages: Array[String] = []
	for k: Variant in HelpPanel.PAGES.keys():
		pages.append(String(k))
	pages.append("Keys")
	for sz in sizes:
		get_tree().root.size = sz
		await _frames(12)
		hud._close_others(null)
		hud._toggle_help()
		await _frames(6)
		if hud.help == null or not hud.help.visible:
			failures += 1
			print("FAIL help_fit_check %dx%d: the help panel did not open" % [sz.x, sz.y])
			continue
		var vr := get_tree().root.get_visible_rect()
		print("help_fit_check WINDOW %dx%d, laid out in %dx%d" % [sz.x, sz.y, roundi(vr.size.x), roundi(vr.size.y)])
		for page: String in pages:
			hud.help._show(page)
			await _frames(3)
			_measure(sz, page)
			if page == "Keys":
				_probe_keys(sz)
		hud._toggle_help()
		await _frames(4)
	print("help_fit_check: %d failures" % failures)
	get_tree().quit()


## Compare the help panel's rectangle with the window's and print the line; a page that sticks out counts as a failure.
func _measure(sz: Vector2i, page: String) -> void:
	var vr := get_tree().root.get_visible_rect()
	var r := hud.help.get_global_rect()
	var right := r.end.x - vr.end.x
	var bottom := r.end.y - vr.end.y
	var left := vr.position.x - r.position.x
	var top := vr.position.y - r.position.y
	print("help_fit_check PAGE %dx%d %s right %.1f bottom %.1f left %.1f top %.1f" % [sz.x, sz.y, page, right, bottom, left, top])
	if right > TOLERANCE or bottom > TOLERANCE or left > TOLERANCE or top > TOLERANCE:
		failures += 1
		print("FAIL help_fit_check %dx%d %s: the panel leaves the window (right %.1f, bottom %.1f, left %.1f, top %.1f)" % [sz.x, sz.y, page, right, bottom, left, top])


## Print the Keys page's probe lines: for each table the widest cell's smallest width in each column and the table's own
## smallest width. They never fail; they say which column pushes the panel wide.
func _probe_keys(sz: Vector2i) -> void:
	var g := 0
	for grid in hud.help.keys_grids:
		var widest := [0.0, 0.0, 0.0, 0.0]
		var which := ["", "", "", ""]
		var kids := grid.get_children()
		for i in kids.size():
			var c := kids[i] as Control
			if c == null:
				continue
			var need := c.get_combined_minimum_size().x
			var col := i % grid.columns
			if need > float(widest[col]):
				widest[col] = need
				which[col] = (c as Label).text.left(30) if c is Label else ""
		print("help_fit_check KEYS %dx%d table %d columns %.0f %.0f %.0f %.0f table_min %.0f table_width %.0f widest_note \"%s\"" % [sz.x, sz.y, g,
			widest[0], widest[1], widest[2], widest[3], grid.get_combined_minimum_size().x, grid.size.x, which[3]])
		g += 1


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
