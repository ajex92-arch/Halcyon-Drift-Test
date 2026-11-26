extends Node
## WHAT THIS IS: the feed fit check. The kill feed (the column of news lines at the top right) must stay above the
## minimap: HudFeed shows only the newest lines that fit in the room above it. This check fills the feed with seven
## long lines, the way a busy fight does, in six situations (the HUD as it is; the pause menu's Look around; lines
## that arrive in the same frame as Look around, before it and after it; the game held paused; the Admiral tour's order of menu steps), at each of seven
## window sizes, twenty times each, and measures every line that shows against the top of the minimap. A line that
## ends below that top, or a feed with no line showing, is a failure. It exists because the feed reached over the
## minimap in the Admiral tour's Look around picture in some runs and not in others.
##
## HOW IT WORKS: it waits until the HUD exists, then for each window size (--ui-size, a list; default 1280x720,
## 1920x1080, 2560x1440, 1366x657, 1024x600, 2560x1080 and 1280x1024, set on the headless window the way the tour
## sets it) it repeats each situation REPEATS times. Each repeat clears the feed, sends the seven lines through
## Events.feed (the way the game does; the check prints one line when fewer than seven became lines of the feed),
## does what the situation says and measures in that frame and one, two and three frames later: every line of the feed that is visible and not
## queued for deletion must end at or above the top of the minimap's rectangle (plus half a pixel) wherever their
## widths overlap, and at least one line must show (the newest always does). It prints one "feed_fit_check STATE"
## line per size and situation with the number of repeats that overlapped and the worst overlap. The last line is
## "feed_fit_check: N failures". --minimap-pct=140 gives the minimap its largest size (the tour's switch).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=feed_fit_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --seed=7 --test=feed_fit_check
##
## HOW TO READ THE OUTPUT: "feed_fit_check STATE <size> <situation> repeats <n> over <n> worst <px> lines <n>" per size
## and situation, "feed_fit_check LOST" lines for lines that never reached the feed, "FAIL feed_fit_check ..." lines,
## then "feed_fit_check: N failures". If the run takes over 540 seconds of real time it prints "feed_fit_check:
## timeout" and quits.
##
## WHO USES IT: main.gd loads it for --test=feed_fit_check (see ui_tour.gd for how tests are loaded); run_checks runs
## it for both seats. It reads the HUD and changes nothing in the match; the game is running again when it ends.

## The window sizes tried when --ui-size is not given.
const DEFAULT_SIZES := "1280x720,1920x1080,2560x1440,1366x657,1024x600,2560x1080,1280x1024"
## How many times each situation is tried at each size, so a flake shows in one run.
const REPEATS := 20
## How far (layout pixels) a line may reach below the minimap's top before it counts as over it.
const TOLERANCE := 0.5
## The situations, in the order they are run.
const STATES := ["as_is", "look_around", "lines_after_look", "lines_before_look", "held_paused", "tour_order"]
## The feed's lines: [text, tone] (seven, as many as the feed keeps).
const LINES := [
	["Valkyrie-Nine shot down Nightingale's Capital Ship", "good"],
	["Aurelian repair bay at Upper Crossing destroyed", "good"],
	["Vhorr destroyed the Aurelian Flak Turret at Lower Asteroid Cluster", "bad"],
	["Research complete: Heavy Plating. Frigate can now be bought in the hangar.", "good"],
	["Module built: Capital Ship Facility. Capital Ship can now be bought in the hangar.", "good"],
	["Pike's Frigate was destroyed by an Aurelian turret", "good"],
	["Free mining drone queued for the Aurelian fleet", "info"],
]

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
## How many lines that were sent never became lines of the feed.
var lost := 0


## main.gd calls this once, right after the World is built. Remember the world and keep running even if the
## game pauses; --minimap-pct=N gives the minimap that size, as the tour does.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	sizes = _ui_sizes()
	if Game.opt("minimap-pct") != null:
		Game.minimap_pct = Game.clamp_minimap_pct(int(str(Game.opt("minimap-pct"))))


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


## Godot calls this every drawn frame. Quit after 540 s of real time; start the check once the HUD exists.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 540000:
		print("feed_fit_check: timeout")
		get_tree().paused = false
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
	# setup() runs after the minimap's _ready() has taken its size, so --minimap-pct has to be applied again here (the way
	# team_shapes_shots does), and the layout asked to place the feed against the new minimap.
	if Game.opt("minimap-pct") != null:
		hud.minimap.apply_size()
		hud.layout.apply()
	await _frames(30)
	for sz in sizes:
		get_tree().root.size = sz
		await _frames(12)
		var vr := get_tree().root.get_visible_rect()
		print("feed_fit_check WINDOW %dx%d, laid out in %dx%d, minimap %d percent" % [sz.x, sz.y, roundi(vr.size.x), roundi(vr.size.y), Game.minimap_pct])
		for state: String in STATES:
			var over := 0
			var worst := 0.0
			var shown := 0
			for n in REPEATS:
				await _setup_state(state, n)
				# Measured in the frame of the change (a layout dump of the tour reads the HUD there), then one, two and three frames later
				# (the column has settled): the worst of the four counts.
				var res := _measure(sz, state)
				for _wait in 3:
					await _frames(1)
					var later := _measure(sz, state)
					if float(later["over"]) > float(res["over"]):
						res["over"] = later["over"]
					res["lines"] = mini(int(res["lines"]), int(later["lines"]))
				shown = int(res["lines"])
				if n == 0:
					var first := 0.0
					for l in _live_lines():
						if l.visible:
							first = l.global_position.y - hud.feed.global_position.y
							break
					print("feed_fit_check CONTEXT %dx%d %s command view %s, feed top %.0f, column %.0f high, lines %d of %d showing, first line %.0f below the column's top, minimap top %.0f" % [sz.x, sz.y, state,
						hud.command_view != null and hud.command_view.is_showing(), hud.feed.global_position.y, hud.feed.size.y, shown, _live_lines().size(), first, hud.minimap.global_position.y])
				if float(res["over"]) > TOLERANCE or int(res["lines"]) < 1:
					over += 1
					failures += 1
				worst = maxf(worst, float(res["over"]))
				await _leave_state(state)
			print("feed_fit_check STATE %dx%d %s repeats %d over %d worst %.1f lines %d" % [sz.x, sz.y, state, REPEATS, over, worst, shown])
			if over > 0:
				print("FAIL feed_fit_check %dx%d %s: %d of %d repeats leave a line over the minimap or show no line (worst %.1f px)" % [sz.x, sz.y, state, over, REPEATS, worst])
	print("feed_fit_check: %d failures" % (failures + lost))
	get_tree().paused = false
	get_tree().quit()


## Put the HUD in situation `state` with a fresh feed; the caller measures at once, because what is made in a frame is read
## by a layout dump in that same frame.
func _setup_state(state: String, repeat: int) -> void:
	get_tree().paused = false
	hud._close_others(null)
	await _frames(1)
	_clear_feed()
	match state:
		"as_is":
			_send_lines()
		"look_around":
			_send_lines()
			hud._toggle_pause_menu()
			await _frames(2)
			hud.pause_menu.look_around()
		"lines_after_look":
			hud._toggle_pause_menu()
			await _frames(2)
			hud.pause_menu.look_around()
			_send_lines()
		"lines_before_look":
			hud._toggle_pause_menu()
			await _frames(2)
			_send_lines()
			hud.pause_menu.look_around()
		"held_paused":
			get_tree().paused = true
			_send_lines()
		"tour_order":
			# The Admiral tour's order: the menu, the question before going back to the start screen, the card again, then Look around,
			# one frame apart.
			_send_lines()
			hud._toggle_pause_menu()
			await _frames(2)
			hud.pause_menu.ask(PauseMenu.VIEW_START)
			await _frames(1 + repeat % 2)
			hud.pause_menu.show_card()
			await _frames(1)
			hud.pause_menu.look_around()


## Take the HUD out of the situation: the pause menu is closed again and the game runs.
func _leave_state(state: String) -> void:
	get_tree().paused = false
	if state != "as_is" and state != "held_paused" and hud.pause_menu != null and hud.pause_menu.active:
		hud._toggle_pause_menu()
	hud._close_others(null)
	await _frames(1)


## Remove every line of the feed (the way add_line() drops the oldest).
func _clear_feed() -> void:
	for c in hud.feed.get_children():
		hud.feed.remove_child(c)
		c.queue_free()


## Send the seven lines through Events.feed, as the game does, and count the ones that did not become lines of the feed.
func _send_lines() -> void:
	var before := _live_lines().size()
	for l: Array in LINES:
		Events.feed.emit(l[0], l[1], world.human_team)
	var got := _live_lines().size() - before
	if got < LINES.size():
		lost += LINES.size() - got
		print("feed_fit_check LOST %d of %d lines did not become lines of the feed" % [LINES.size() - got, LINES.size()])


## The children of the feed that are not queued for deletion.
func _live_lines() -> Array[Control]:
	var out: Array[Control] = []
	for c in hud.feed.get_children():
		var l := c as Control
		if l != null and not l.is_queued_for_deletion():
			out.append(l)
	return out


## Measure the feed against the minimap: {"over": the most (pixels) a showing line reaches below the minimap's top where
## their widths overlap, "lines": how many lines show}. A feed that is not shown has no lines and so reads as failed.
func _measure(sz: Vector2i, state: String) -> Dictionary:
	var over := 0.0
	var count := 0
	if not hud.feed.is_visible_in_tree():
		print("feed_fit_check %dx%d %s: the feed is not showing" % [sz.x, sz.y, state])
		return {"over": 0.0, "lines": 0}
	var map := hud.minimap.get_global_rect()
	for l in _live_lines():
		if not l.visible:
			continue
		count += 1
		if not hud.minimap.is_visible_in_tree():
			continue
		var r := l.get_global_rect()
		if r.end.x > map.position.x and r.position.x < map.end.x:
			over = maxf(over, r.end.y - map.position.y)
	return {"over": over, "lines": count}


## Wait `n` frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
