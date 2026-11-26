extends Node
## WHAT THIS IS: the UI tour. It drives the HUD (the on-screen panels:
## hangar, help, scoreboard, admiral board ...) through its screens and
## saves screenshots. Windowed, it saves a PNG at every step. Headless
## with --force-hud (which builds the HUD anyway), it clicks through the
## same screens without pictures: any script error in the UI shows up in
## the output.
##
## HOW IT WORKS: it waits until the HUD exists, then follows a timed list
## of steps: one list for a pilot (_pilot_steps) and one for an admiral
## (_admiral_steps), picked by the human's role. Each step is [seconds
## since the HUD appeared, a function to run]. Some steps open a screen,
## buy something or move the camera; the others take a picture (_shot).
## The tours also check the screens of the 6v6 teams (the user test fork):
## the scoreboard and the admiral board's Pilots tab list 5 pilots and the
## admiral's seat for each side (6 rows, one "Admiral" row, one "(you)",
## 12 different callsigns), and the help and start-screen texts say 5 pilots
## and 6 against 6. A failed check prints a "FAIL ui_tour: ..." line, and the
## "done" line is then left out.
## The last step prints "ui_tour: done (...)" and quits. If the whole run
## takes over 60 seconds of real time (60 for each window size of a
## --ui-size list), it prints "ui_tour: timeout" and quits.
## The tour covers the screens a player really meets, each in its busiest
## state: the hangar (all four tabs, and opened in flight), the docked
## message, the flying HUD with a full kill feed, earnings log and pop-up
## help pages (the Keys page too) and the Controls page, the scoreboard, the pause menu (its buttons, the
## question before a restart and Look around), both
## motherships in trouble, the dead screen with the hangar open over it,
## the end screen (with a pop-up hint shown just before the match ends)
## and the start screen; for an admiral the board's four tabs, the map
## tool, the help, the pause menu and the hangar.
##
## PAGE MODE (--page=<name>[:<variant>], optionally --at=<seconds>): instead of
## the whole tour, take ONE picture of ONE page at one moment of a live match,
## so someone who changed a page can look at that page alone. The match plays
## for real until its clock reads --at (0 to 1800 seconds, default 0; the mode
## only reads the clock, never sets it; a pilot is launched in a Fighter the
## way the tour does it, an admiral stays at the bridge), then the page is
## opened with the same HUD call the tour uses, the HUD gets 8 frames to lay
## itself out, and one picture is taken (_shot) before the run ends. The pages
## are the keys of PAGES: play (nothing opened), feed (the busy HUD), help
## (variants: the help page names and Keys), controls, pause, hangar (variants
## Ships, Gear, Modules, Kits), trouble, and for a pilot only scoreboard and
## dead, for an admiral only board (variants Research, Build, Mothership,
## Pilots). A name, variant or --at that is not valid, or a page that the seat
## does not have, prints one "FAIL ui_tour: ...; pages: ..." line (with the
## pages the seat has), takes no picture, prints no "done" line and quits. A
## seat other than the pilot's or the admiral's (--all-ai gives the spectator
## seat, or a mistyped --role) is refused the same way. A pilot shot down before
## --at is launched again (one line says so) and the run fails with no "done"
## line when there is still no ship (the page dead is exempt).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --path remake --resolution 1280x720 -- --auto --role=pilot --test=ui_tour --shots=<dir>
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --test=ui_tour --shots=<dir>
##   godot --headless --path remake -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour --dump
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour --dump-layout --ui-size=1366x657
## (--minimap-pct=140 gives the minimap that size: T-125.)
## The first two run in a window and save pictures in the folder given by
## --shots (default: Godot's user data folder). The third runs with no
## window (--headless); --bot=tour stops main.gd from buying and launching
## the human's ship by itself, so the tour starts in the hangar. The
## fourth also prints every control on screen at every picture step
## (--dump, see UiDump); with --fixed-fps 60 each step happens on the same
## game frame every run, so two builds' dumps can be compared line by line.
## The fifth is the layout check: --dump-layout adds what
## tools/ui_layout_check.py needs (see UiDump), and --ui-size=WxH is the
## window size to test (a headless window is only 64 x 64 pixels, so the
## dump uses 1280x720 when --ui-size is not given). Pipe the output of the
## fifth, one run per role and size, into the checker. Several sizes
## separated by commas (--ui-size=1280x720,1366x657,1024x600) make one run
## dump every picture step at each size in turn, resizing the window
## between the dumps the way a player resizing the browser does; that is
## the quick way to test many sizes, one run per role.
## The page mode (see PAGE MODE above), one windowed and one headless line:
##   godot --path remake --fixed-fps 60 --resolution 1280x720 -- --auto --role=pilot --bot=tour --test=ui_tour --page=help:Keys --at=60 --shots=<dir>
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour --page=help:Keys --at=60 --speed=4 --dump-layout --ui-size=1280x720
## (--role=admiral for the Admiral's pages, such as --page=board:Build.)
##
## HOW TO READ THE OUTPUT: windowed, one "shot <path>" line per picture
## (p01_hangar_ships.png ... p10_start.png for a pilot, a01_start.png ...
## a09_hangar.png for an admiral). Headless, one "ui_tour step <name>"
## line per picture step instead, plus the UIDUMP lines with --dump. The
## run ends with "ui_tour: done (pilot)" or "ui_tour: done (admiral)". Any
## SCRIPT ERROR line from Godot means a UI script broke.
## The page mode's picture is named page_<name>[_<variant>]_t<--at as four
## digits>.png (page_help_keys_t0120.png: the Keys help page at 120 s; the
## variant is in lower case). It prints "ui_tour: page <name>[:<variant>] at
## match time <seconds>" (the match clock when the picture is taken, a little
## after --at), then the picture's "shot <path>" line windowed or the
## "ui_tour step <file name>" line headless (plus the UIDUMP lines with --dump
## or --dump-layout), and ends "ui_tour: done (page <name> at <seconds>)". The
## real-time limit is 60 s plus 1.5 x --at divided by --speed; past it the run
## prints "ui_tour: timeout".
##
## USE NOTES for the page mode: pick the page by its name above (a wrong name
## lists the right ones). To see something that only exists later (a minion
## wave is on the map from about 45 s, a mothership in trouble does not
## depend on time) give --at; a high --at is slow, so add --speed=4 (headless
## or windowed; the last second before --at runs at normal speed, so the
## picture is taken within a fraction of a second of --at). Windowed, add
## --position and --disable-vsync to park the window out of sight if needed.
## A headless run prints no picture, only the step line and the dump: use
## --dump-layout --ui-size=WxH and read the UIDUMP lines of that step, or
## feed the output to tools/ui_layout_check.py. Two runs with --fixed-fps 60
## and the same --seed print the same dump (leave the "build:" line out).
##
## WHO USES IT: main.gd loads it for --test=ui_tour (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()), and
## builds the HUD headless only for --force-hud. It finds the node named
## "Hud" and calls the HUD's own functions: Hud._toggle_help(), _toggle_controls(), _toggle_pause_menu(),
## _show_scoreboard(), _toggle_board(), _on_match_over(),
## Hangar._set_tab() / launch(), AdmiralBoard._set_tab(), HelpPanel._show(),
## PauseMenu.ask() and CommandOverlay arm() / apply_at() / disarm(). tests/lib/ui_dump.gd
## prints the dumps.

## The start screen, shown once at the end of the pilot tour (--auto runs
## never show it otherwise).
const START_SCENE := preload("res://scenes/ui/start_screen.tscn")
## Prints the dumps (the UIDUMP lines).
const UiDump := preload("res://tests/lib/ui_dump.gd")
## The kill feed's lines for a busy fight: [text, tone]. They are the
## longest sentences HudFeed makes (a kill, a lost repair bay, a lost
## turret, finished research, a finished module), and there are seven, as
## many as the feed keeps (HudFeed.MAX_LINES).
const FEED_LINES := [
	["Valkyrie-Nine shot down Nightingale's Capital Ship", "good"],
	["Aurelian repair bay at Upper Crossing destroyed", "good"],
	["Vhorr destroyed the Aurelian Flak Turret at Lower Asteroid Cluster", "bad"],
	["Research complete: Heavy Plating. Frigate can now be bought in the hangar.", "good"],
	["Module built: Capital Ship Facility. Capital Ship can now be bought in the hangar.", "good"],
	["Pike's Frigate was destroyed by an Aurelian turret", "good"],
	["Free mining drone queued for the Aurelian fleet", "info"],
]
## The reasons of four earnings lines (HudMePanel keeps four).
const EARN_REASONS := ["kill", "assist", "turret", "ore"]
## The pages the page mode (--page=<name>[:<variant>]) can take a picture of, in the order an error message lists them: each name maps to
## "seats" (the human roles it works in) and "opens" (the HUD call that opens it, in plain words). A page not in this table is refused.
const PAGES := {
	"play": {"seats": ["pilot", "admiral"], "opens": "nothing (the pilot flying, the Admiral at the bridge)"},
	"feed": {"seats": ["pilot", "admiral"], "opens": "_busy_hud(): the full kill feed, earnings log and a pop-up hint"},
	"help": {"seats": ["pilot", "admiral"], "opens": "Hud._toggle_help() then HelpPanel._show(variant)"},
	"controls": {"seats": ["pilot", "admiral"], "opens": "Hud._toggle_controls()"},
	"pause": {"seats": ["pilot", "admiral"], "opens": "Hud._toggle_pause_menu()"},
	"hangar": {"seats": ["pilot", "admiral"], "opens": "Hud._open_hangar() then Hangar._set_tab(variant)"},
	"trouble": {"seats": ["pilot", "admiral"], "opens": "_trouble(true): both motherships in trouble"},
	"scoreboard": {"seats": ["pilot"], "opens": "Hud._show_scoreboard(true)"},
	"dead": {"seats": ["pilot"], "opens": "Combat.kill() on the human's ship (the dead screen)"},
	"board": {"seats": ["admiral"], "opens": "Hud._toggle_board() then AdmiralBoard._set_tab(variant)"},
}
## The variants of page "hangar" (the hangar's four tabs).
const HANGAR_TABS := ["Ships", "Gear", "Modules", "Kits"]
## The variants of page "board": the tabs AdmiralBoard._set_tab() builds (its Build and Mothership buttons are hidden, the tabs are
## still reachable by name). The variants of page "help" are the keys of HelpPanel.PAGES and "Keys".
const BOARD_TABS := ["Research", "Build", "Mothership", "Pilots"]

## The running match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## The folder the pictures go into (--shots).
var dir := ""
## Seconds since the HUD was found (the step times count from then).
var t := 0.0
## Which step is next (an index into the step list).
var step := 0
## The human's role: "pilot" or "admiral" (picks the step list).
var role := "pilot"
## True with --dump or --dump-layout: picture steps also print every
## control (see UiDump).
var dump := false
## How many of the seat checks failed (see _check_scoreboard()).
var fails := 0
## The start screen the pilot tour puts on top at the end (null before).
var _start: Node = null
## True with --dump-layout: the dump also carries the extra facts the
## layout checker needs.
var layout := false
## The window sizes of a headless dump (--ui-size; the first is the size
## the run starts and ends at).
var sizes: Array[Vector2i] = [Vector2i(1280, 720)]
## True while a step is still running (a dump at several sizes takes a few
## frames), so the next step waits for it.
var busy := false
## True with --page: the run is the page mode (one picture of one page at one match time) instead of a tour.
var page_mode := false
## The page asked (a key of PAGES).
var page_name := ""
## The variant of the page asked ("" for none).
var page_variant := ""
## The match time the page is wanted at, in seconds (--at).
var page_at := 0.0
## True once the page mode has started its run (it runs once).
var page_started := false
## True when the page mode's options were refused (the run prints a FAIL line and quits).
var page_failed := false
## Engine.time_scale as --speed set it (read in setup()), which the page mode's time limit scales with.
var page_speed := 1.0


## main.gd calls this once, right after the World is built. Remember the
## role and the picture folder, and keep running even if the game is
## paused. A pilot's camera stays where it is left (Space centers it), and a
## fresh window's mouse sits at (0, 0), the screen corner, where the free
## camera would pan away: so a pilot's tour holds Space the whole time, and
## the pictures keep the ship (while docked, the mothership) in view.
func setup(w: World) -> void:
	world = w
	role = w.human_role
	if role == "pilot":
		Input.action_press("center_on_ship")
	layout = Game.opt("dump-layout", false) == true
	dump = layout or Game.opt("dump", false) == true
	# T-125: --minimap-pct=N gives the minimap that size (70 to 140) for the pictures and the layout dump; without it the size is the
	# default 100%, whatever the settings file holds (only the start screen reads the file).
	if Game.opt("minimap-pct") != null:
		Game.minimap_pct = Game.clamp_minimap_pct(int(str(Game.opt("minimap-pct"))))
	# A headless window is only 64 x 64 pixels; give the dump the real
	# window size, so text wraps and panels sit as they do on screen.
	sizes = _ui_sizes()
	if DisplayServer.get_name() == "headless" and (dump or Game.opt("ui-size") != null):
		get_tree().root.size = sizes[0]
	_print_size(sizes[0], true)
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# --page: the page mode (one picture of one page at one match time). Without it the tours run as before.
	if Game.opt("page") != null:
		page_mode = true
		page_speed = maxf(Engine.time_scale, 0.001)
		var problem := _page_parse()
		if problem != "":
			var names := _page_names()
			print("FAIL ui_tour: %s%s" % [problem, "; pages: " + ", ".join(names) if not names.is_empty() else ""])
			fails += 1
			page_failed = true
			get_tree().quit()


## Print the size the tour runs at (F460): the size asked (--ui-size, `asked`), the window's real size, and the size
## of the layout the HUD is laid out in. The last one is what the UIVIEW lines and tools/ui_layout_check.py name: the
## project stretches a 1280 x 720 layout to the window (stretch mode canvas_items, aspect expand), so a 1366 x 657
## window is a 1496 x 720 layout drawn at 0.9125 of its size, and every 16:9 window is the 1280 x 720 layout. A
## window that is not the size asked prints a FAIL line and counts as a failed check. `first` is the tour's opening
## line (it also lists every size of the run).
func _print_size(asked: Vector2i, first: bool) -> void:
	var win := get_tree().root
	var lay := win.get_visible_rect().size
	# Only a headless dump sets the window's size (setup()); any other run keeps the window it has.
	var sized := DisplayServer.get_name() == "headless" and (dump or Game.opt("ui-size") != null)
	var ok := win.size == asked or not sized
	var all := ""
	if first and sizes.size() > 1:
		var names: Array = []
		for sz in sizes:
			names.append("%dx%d" % [sz.x, sz.y])
		all = " sizes=" + ",".join(names)
	print("ui_tour: size asked=%dx%d window=%dx%d layout=%dx%d scale=%.4f%s" % [asked.x, asked.y, win.size.x, win.size.y,
		roundi(lay.x), roundi(lay.y), win.get_final_transform().get_scale().x, all])
	if not ok:
		print("FAIL ui_tour: the window is %dx%d, not the %dx%d asked" % [win.size.x, win.size.y, asked.x, asked.y])
		fails += 1


## The window sizes for a headless dump: --ui-size=WxH (such as 1366x657),
## or several of them separated by commas. A size that is not WxH with at
## least 320 x 240 is skipped; with none left, 1280x720 (the size
## project.godot sets).
func _ui_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in str(Game.opt("ui-size", "1280x720")).split(",", false):
		var xy := part.split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	return out


## Godot calls this every drawn frame; `dt` is the frame's length in
## seconds. Find the HUD, then run each step when its time comes.
func _process(dt: float) -> void:
	if world == null or page_failed:
		return
	# Safety net: quit after 60 s of real time since the program started
	# (for each window size of a headless dump at several sizes). The page mode adds the real time its match
	# time takes: 1.5 x --at seconds, divided by --speed.
	var limit_ms := 60000.0 * sizes.size()
	if page_mode:
		limit_ms += 1500.0 * page_at / page_speed
	if Time.get_ticks_msec() > limit_ms:
		print("ui_tour: timeout")
		get_tree().quit()
	# Wait until the HUD exists (it is a node named "Hud" somewhere in the
	# scene).
	if hud == null:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud == null:
			return
		## setup() runs after the minimap's _ready() has taken its size, so --minimap-pct has to be applied again here, once the
		## HUD exists (the way feed_fit_check does), and the layout asked to place the panels against the new minimap.
		if Game.opt("minimap-pct") != null:
			hud.minimap.apply_size()
			hud.layout.apply()
	# Run the next step once its time has come, and wait for it to finish
	# ("await": a picture step waits for the frame to be drawn).
	t += dt
	# The page mode runs its one page instead of a step list (once, as a coroutine).
	if page_mode:
		if not page_started:
			page_started = true
			busy = true
			await _page_run()
			busy = false
		return
	var steps: Array = _pilot_steps() if role == "pilot" else _admiral_steps()
	if step >= steps.size() or busy:
		return
	var s: Array = steps[step]
	if t >= float(s[0]):
		step += 1
		busy = true
		await (s[1] as Callable).call()
		busy = false


## The names of the pages that this run's seat (role) has, in PAGES order (what a FAIL line lists); none for a seat that is
## neither the pilot's nor the Admiral's.
func _page_names() -> Array[String]:
	var out: Array[String] = []
	if role != "pilot" and role != "admiral":
		return out
	for n: String in PAGES:
		if (PAGES[n]["seats"] as Array).has(role):
			out.append(n)
	return out


## The variants page `n` takes: the hangar's tabs, the Admiral board's tabs, or (help) the keys of HelpPanel.PAGES and "Keys".
## An empty list means the page has no variants.
func _page_variants(n: String) -> Array[String]:
	var out: Array[String] = []
	match n:
		"hangar":
			out.assign(HANGAR_TABS)
		"board":
			out.assign(BOARD_TABS)
		"help":
			for k: String in HelpPanel.PAGES:
				out.append(k)
			out.append("Keys")
	return out


## Read --page=<name>[:<variant>] and --at=<seconds> into page_name, page_variant and page_at. Returns "" when they are good, else
## what was wrong (the FAIL line's text): a seat that is neither the pilot's nor the Admiral's (the spectator seat of --all-ai, or a
## mistyped --role), a page that is not in PAGES, a page this seat does not have, a variant the page does not
## take, or an --at that is not a number from 0 to 1800. A variant matches whatever its letter case.
func _page_parse() -> String:
	if role != "pilot" and role != "admiral":
		return "the page mode works in the pilot and admiral seats only, not '%s' (--role=pilot or --role=admiral, without --all-ai)" % role
	var raw: String = str(Game.opt("page"))
	var bits := raw.split(":", true, 1)
	var asked := bits[0].strip_edges()
	var variant := bits[1].strip_edges() if bits.size() > 1 else ""
	if not PAGES.has(asked):
		return "no page named '%s'" % raw
	if not _page_names().has(asked):
		return "page '%s' does not work in the %s seat" % [asked, role if role == "pilot" else "admiral"]
	page_name = asked
	if variant != "":
		var found := ""
		for v: String in _page_variants(asked):
			if v.to_lower() == variant.to_lower():
				found = v
		if found == "":
			var all := _page_variants(asked)
			return "page '%s' has no variant '%s' (%s)" % [asked, variant, ", ".join(all) if not all.is_empty() else "it takes none"]
		page_variant = found
	var at_text := "0" if Game.opt("at") == null else str(Game.opt("at"))
	if not at_text.is_valid_float() or not is_finite(at_text.to_float()):
		return "--at=%s is not a number of seconds" % at_text
	page_at = at_text.to_float()
	if page_at < 0.0 or page_at > 1800.0:
		return "--at=%s is outside 0 to 1800 seconds" % at_text
	return ""


## The page mode's whole run: launch the human's ship (a pilot; the Admiral stays at the bridge), let the match play until its
## time reaches `page_at` (real play: the clock is only read, never set), open the page, wait 8 frames for the HUD to lay itself
## out, print the "page ... at match time" line, take the one picture and end the run. With a high --speed the last second of the
## wait runs at normal speed, so the match time of the picture is within a frame or two of --at.
func _page_run() -> void:
	if role == "pilot" and _tour_launch() == null:
		print("FAIL ui_tour: the pilot's ship could not be launched")
		fails += 1
		_finish("page %s" % page_name)
		return
	while world.time < page_at:
		if world.time >= page_at - 1.0 and Engine.time_scale > 1.0:
			Engine.time_scale = 1.0
		await get_tree().process_frame
	Engine.time_scale = minf(Engine.time_scale, 1.0)
	# A pilot shot down before --at (--bot=tour gives no relaunch) would show the dead screen on every page but "dead": launch again
	# (_tour_launch() does nothing while the ship is alive), and fail when there is still no ship.
	if role == "pilot" and page_name != "dead" and _pilot_ship_gone():
		print("ui_tour: the pilot's ship was gone at match time %.1f; launched again" % world.time)
		_tour_launch()
		if _pilot_ship_gone():
			print("FAIL ui_tour: the pilot's ship was shot down before --at")
			fails += 1
			_finish("page %s" % page_name)
			return
	hud._close_others(null)
	_page_open()
	await _wait_frames(8)
	var label := page_name if page_variant == "" else "%s:%s" % [page_name, page_variant]
	print("ui_tour: page %s at match time %.1f" % [label, world.time])
	var file := "page_" + page_name
	if page_variant != "":
		file += "_" + page_variant.to_lower().replace(" ", "_")
	await _shot("%s_t%04d" % [file, roundi(page_at)])
	_finish("page %s at %s" % [label, String.num(page_at)])


## True when the human has no living ship (none yet, freed, or dead).
func _pilot_ship_gone() -> bool:
	var s: Ship = world.human.ship
	return s == null or not is_instance_valid(s) or not s.alive


## Open the page asked (page_name, page_variant) with the same HUD calls the tours use.
func _page_open() -> void:
	match page_name:
		"feed":
			_busy_hud()
		"help":
			hud._toggle_help()
			if page_variant != "":
				hud.help._show(page_variant)
		"controls":
			hud._toggle_controls()
		"pause":
			hud._toggle_pause_menu()
		"hangar":
			hud._open_hangar()
			if page_variant != "":
				hud.hangar._set_tab(page_variant)
		"trouble":
			_trouble(true)
		"scoreboard":
			hud._show_scoreboard(true)
		"dead":
			var s := world.human.ship
			if s != null:
				world.combat.kill(s, DamageInfo.new())
		"board":
			hud._toggle_board()
			if page_variant != "":
				hud.board._set_tab(page_variant)


## Take the picture `name`: windowed, wait for the frame to be drawn and
## save it as <name>.png in the --shots folder; headless, just print
## "ui_tour step <name>" (there is nothing to take a picture of). With
## --dump (or --dump-layout) every control on screen is printed too, in a
## window as well as headless; headless with several --ui-size sizes, once
## at each size (see _dump_sizes()).
func _shot(name: String) -> void:
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		print("ui_tour step ", name)
	if dump and headless and sizes.size() > 1:
		await _dump_sizes(name)
	elif dump:
		UiDump.dump(hud, name, layout)
	if headless:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("shot ", path)


## Check the table of Scoreboard `sb` (the pilots' scoreboard, or the Pilots
## tab of the admiral board) for the 6v6 teams: each side lists its 5
## pilots and the admiral's seat (6 rows), exactly one row on each side says
## "Admiral", exactly one cell says "(you)" when a human plays (none for a
## spectator), and all 12 callsigns differ. Prints a PASS or FAIL line.
func _check_scoreboard(sb: Scoreboard, what: String) -> void:
	if sb == null:
		print("FAIL ui_tour: %s: there is no scoreboard" % what)
		fails += 1
		return
	# Write the table now (it normally rewrites itself twice a second).
	sb._refresh()
	var names := {}
	var you := 0
	var ok := true
	var parts: Array = []
	for team in 2:
		var g: GridContainer = sb._grids[team]
		var rows := int(float(g.get_child_count()) / float(g.columns)) - 1
		var admirals := 0
		for r in rows:
			var who := (g.get_child((r + 1) * g.columns) as Label).text
			var status := (g.get_child((r + 1) * g.columns + g.columns - 1) as Label).text
			names[who.replace(" (you)", "")] = true
			if who.ends_with("(you)"):
				you += 1
			if status.begins_with("Admiral"):
				admirals += 1
		parts.append("%s %d rows, %d admiral" % [Rules.TEAM_NAMES[team], rows, admirals])
		if rows != Rules.PILOTS_PER_TEAM + 1 or admirals != 1:
			ok = false
	if names.size() != 2 * (Rules.PILOTS_PER_TEAM + 1) or you != (0 if world.human == null else 1):
		ok = false
	print("%s ui_tour: %s: %s, %s, %d callsigns, %d you" % ["PASS" if ok else "FAIL", what, parts[0], parts[1], names.size(), you])
	if not ok:
		fails += 1


## Check the words the player reads about the teams: the help pages (data in
## HelpPanel.PAGES) say 5 pilots and strain at 2 respawns, and the start
## screen (once it is on top, see the pilot tour) says 6 against 6 and has
## no leftover "12 pilots" (its short texts name no number of pilots).
func _check_texts(what: String, text: String, wanted: Array, unwanted: Array) -> void:
	var ok := true
	for w: String in wanted:
		if not text.contains(w):
			ok = false
			print("FAIL ui_tour: %s: missing '%s'" % [what, w])
	for u: String in unwanted:
		if text.contains(u):
			ok = false
			print("FAIL ui_tour: %s: still has '%s'" % [what, u])
	if ok:
		print("PASS ui_tour: %s" % what)
	else:
		fails += 1


## The text of every label under `n`, joined (for _check_texts()).
func _all_label_text(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out


## End the tour: "ui_tour: done (...)" when every check passed (run_checks
## wants that line), otherwise the failure count, and quit.
func _finish(what: String) -> void:
	if fails == 0:
		print("ui_tour: done (%s)" % what)
	else:
		print("FAIL ui_tour: %d checks failed (%s)" % [fails, what])
	get_tree().quit()


## Dump picture step `name` at every window size in turn: resize the window,
## let the HUD lay itself out again (8 frames: the panels rebuild their
## cards when their width changes, and the big message and the HUD's other
## texts refresh 10 times a second, every 6 frames) and print the dump. The
## window goes back to the first size at the end.
func _dump_sizes(name: String) -> void:
	for sz in sizes:
		_keep_lines_alive()
		get_tree().root.size = sz
		for i in 8:
			await get_tree().process_frame
		_print_size(sz, false)
		UiDump.dump(hud, name, layout)
	get_tree().root.size = sizes[0]
	for i in 3:
		await get_tree().process_frame


## Make the kill feed's and the earnings log's lines new again. They fade
## out after 9 and 5 real seconds, and a dump at many sizes takes longer
## than that, so the last sizes would see an empty feed.
func _keep_lines_alive() -> void:
	for box: Container in [hud.feed, hud.me_panel.earn_box]:
		for c in box.get_children():
			c.set_meta("born", Time.get_ticks_msec())
			(c as CanvasItem).modulate.a = 1.0


## Fill the HUD the way a long fight does: the kill feed full (FEED_LINES),
## four earnings lines under the credits, and (`with_toast`) a pop-up hint.
## The layout check needs the HUD at its fullest, since an empty HUD hides
## overlaps.
func _busy_hud(with_toast: bool = true) -> void:
	for l: Array in FEED_LINES:
		Events.feed.emit(l[0], l[1], world.human_team)
	for r: String in EARN_REASONS:
		Events.credits_earned.emit(world.human, 40.0, r)
	if with_toast:
		Events.toast.emit("Pick a ship in the hangar and launch. H explains everything.")


## Put both motherships in trouble (`on` = true: a systems failure with 25
## seconds to go, which writes the longest top bar and banner texts) or
## clear it again.
func _trouble(on: bool) -> void:
	for team in 2:
		world.mothership(team).failure_t = 25.0 if on else 0.0


## The pilot's tour: [seconds since the HUD appeared, what to do]. Each
## "func() -> void: ..." is a small function written in place (a lambda).
func _pilot_steps() -> Array:
	return [
		# The hangar's Ships tab, then its Gear tab.
		[1.0, func() -> void:
			_check_texts("help pages", str(HelpPanel.PAGES), ["5 pilots and 1 Admiral", "2 or more pilots respawn within 30"], ["4 or more pilots", "12 pilots"])
			await _shot("p01_hangar_ships")],
		[1.5, func() -> void:
			hud.hangar._set_tab("Gear")],
		[2.0, func() -> void: await _shot("p02_hangar_gear")],
		# Buy a fighter and a repair kit, then the Modules tab, then Kits.
		[2.5, func() -> void:
			world.human.buy_hull("fighter", world.teams[world.human_team])
			world.human.buy_kit()
			hud.hangar._set_tab("Modules")],
		[3.0, func() -> void: await _shot("p03_hangar_modules")],
		[3.2, func() -> void:
			hud.hangar._set_tab("Kits")],
		[3.4, func() -> void: await _shot("p03a_hangar_kits")],
		# Close the hangar while still docked: the "Docked at the mothership"
		# message, then launch and take a picture in flight.
		[3.5, func() -> void: hud.hangar.visible = false],
		[3.9, func() -> void: await _shot("p03b_docked")],
		[4.0, func() -> void: hud.hangar.launch()],
		[7.0, func() -> void: await _shot("p04_flying")],
		# The busiest flying HUD: full kill feed, earnings and a hint.
		[7.1, func() -> void: _busy_hud()],
		[7.4, func() -> void: await _shot("p04a_feed")],
		# The hangar opened in flight (B): its longest status line.
		[7.6, func() -> void: hud._open_hangar()],
		[8.0, func() -> void: await _shot("p04b_hangar_flying")],
		[8.1, func() -> void: hud.hangar.visible = false],
		# The help screen (its longest page too), then the scoreboard.
		[8.2, func() -> void: hud._toggle_help()],
		[8.6, func() -> void: await _shot("p05_help")],
		[8.8, func() -> void: hud.help._show("Admiral")],
		[9.0, func() -> void: await _shot("p05a_help_admiral")],
		# The help section about the jungle and the Scum (the sixth entry of the page "The match", scrolled to the top of the list).
		[9.005, func() -> void: hud.help._show("The match")],
		[9.01, func() -> void:
			await get_tree().process_frame
			var scroll := hud.help.get_node("Col/Scroll") as ScrollContainer
			scroll.scroll_vertical = int((hud.help._body.get_child(5) as Control).position.y)
			await get_tree().process_frame
			await _shot("p05a1_help_jungle")],
		# The help's Keys page, then the Controls page that its button opens (which hides the help).
		[9.02, func() -> void: hud.help._show("Keys")],
		[9.04, func() -> void: await _shot("p05b_help_keys")],
		[9.06, func() -> void: hud._toggle_controls()],
		[9.08, func() -> void: await _shot("p05c_controls")],
		[9.1, func() -> void:
			hud._toggle_controls()
			hud._show_scoreboard(true)],
		[9.5, func() -> void:
			_check_scoreboard(hud.scoreboard, "pilot scoreboard")
			await _shot("p06_scoreboard")],
		# Close the scoreboard and jump the match clock to 64 s, past the
		# first minion wave's time (45 s), for a picture of a wave. Open the
		# pause menu for its pictures first: the buttons, then the question
		# before a restart, then resume.
		[10.0, func() -> void:
			hud._show_scoreboard(false)
			world.time = 64.0
			hud._toggle_pause_menu()],
		[10.4, func() -> void: await _shot("p06a_pause")],
		[10.45, func() -> void: hud.pause_menu.ask(PauseMenu.VIEW_RESTART)],
		[10.48, func() -> void: await _shot("p06b_pause_ask")],
		# The pause menu's ring and card view (its third button's page), then back to the buttons.
		[10.482, func() -> void: hud.pause_menu.ask(PauseMenu.VIEW_PARTS)],
		[10.484, func() -> void: await _shot("p06b1_pause_parts")],
		# Back to the buttons, then Look around: the card goes, the game stays paused, the big message names the keys.
		[10.485, func() -> void: hud.pause_menu.show_card()],
		[10.49, func() -> void: hud.pause_menu.look_around()],
		[10.495, func() -> void: await _shot("p06c_look")],
		[10.5, func() -> void: hud._toggle_pause_menu()],
		# After the pause menu: the ring round the ship and the card on the target: a held target, a torpedo coming in, and each preset in turn.
		[11.0, func() -> void: await _ring_tour()],
		[14.5, func() -> void: await _shot("p07_wave")],
		# Both motherships in trouble: the longest top bar and banner text.
		[14.7, func() -> void: _trouble(true)],
		[15.1, func() -> void: await _shot("p07a_trouble")],
		[15.3, func() -> void: _trouble(false)],		# Destroy our own ship, for a picture of the "dead" screen.
		[15.5, func() -> void:
			var s := world.human.ship
			if s != null:
				world.combat.kill(s, DamageInfo.new())],
		[16.5, func() -> void: await _shot("p08_dead")],
		# The hangar over the dead screen, as the HUD opens it on a respawn,
		# with the kill feed busy.
		[16.7, func() -> void:
			_busy_hud(false)
			hud._open_hangar()],
		[17.1, func() -> void: await _shot("p08a_dead_hangar")],
		[17.3, func() -> void: hud.hangar.visible = false],
		# The death card in each state: a crash, a kill by a pilot (both pages, collapsed), a watch (with the hangar over it, the
		# watched ship shot down), the launch, and a kill by a turret with minions.
		[17.35, func() -> void: await _death_tour()],
		# The end screen, shown the way the HUD shows it when a match ends
		# (Hud._on_match_over). The match itself goes on: a real ending
		# closes headless test runs at once (main.gd), before the picture.
		[17.7, func() -> void:
			Events.toast.emit("Rally waypoint set.")
			hud._on_match_over(Rules.HALCYON, "The Cinder mothership was destroyed.")],
		[18.7, func() -> void: await _shot("p09_end")],
		# The start screen on top of everything, for one last picture (--auto
		# runs never show it otherwise).
		[18.9, func() -> void:
			_start = START_SCENE.instantiate()
			hud.add_child(_start)],
		[19.1, func() -> void:
			_check_texts("start screen", _all_label_text(_start), ["6 VS 6"], ["12 pilots", "13 VS 13", "12 AI pilots"])
			await _shot("p10_start")],
		[19.2, func() -> void: _finish("pilot")],
	]


## The admiral's tour: [seconds since the HUD appeared, what to do].
func _admiral_steps() -> Array:
	return [
		# The start, with a busy HUD, then the admiral board (it opens on
		# Research).
		[1.0, func() -> void: await _shot("a01_start")],
		[1.1, func() -> void: _busy_hud()],
		[1.3, func() -> void: await _shot("a01a_feed")],
		[1.5, func() -> void: hud._toggle_board()],
		[2.0, func() -> void: await _shot("a02_board_research")],
		# Order the research facility and the repair bay research (the
		# admiral's order desk queues them), and visit the Build,
		# Mothership and Pilots tabs.
		[2.5, func() -> void:
			world.command.build_facility(0, "research")
			world.command.research(0, "repairBays")
			hud.board._set_tab("Build")],
		[3.0, func() -> void: await _shot("a03_board_build")],
		[3.5, func() -> void: hud.board._set_tab("Mothership")],
		[4.0, func() -> void: await _shot("a04_board_mothership")],
		# The command orders that feature modules add (none in today's game) are entries of the command card's Orders
		# More list: press each and look at the map tool.
		[5.2, func() -> void: await _tour_orders()],
		[5.5, func() -> void: hud.board._set_tab("Pilots")],
		[6.0, func() -> void:
			_check_scoreboard(hud.board._scoreboard, "admiral board, Pilots tab")
			await _shot("a06_board_pilots")],
		# The admiral takes the field in a ship of their own (the board shows
		# its "away" note) and docks again.
		[6.1, func() -> void:
			var h := world.human
			h.buy_hull("fighter", world.teams[0])
			var out := world.launch(h)
			print("ui_tour: admiral launches: ", out != null, " chair empty: ", not world.teams[0].admiral_docked)],
		[6.3, func() -> void: await _shot("a06b_board_away")],
		[6.4, func() -> void:
			var h := world.human
			var back := h.ship != null and world.try_dock(h.ship)
			print("ui_tour: admiral docks: ", back, " chair full: ", world.teams[0].admiral_docked)],
		# Close the board, allow repair bays, pick the "place a bay" tool on
		# the map, and look at the spot 9000 along the mid lane.
		[6.5, func() -> void:
			hud._toggle_board()
			world.teams[world.human_team].repair_bays = true
			hud.overlay.arm("bay")
			world.camera.look_at_point(_my_side(Vector2(9000, MapLayout.CY)))],
		[8.0, func() -> void: await _shot("a07_tool_bay")],
		# Place the bay there, put the tool away, and look at the middle
		# of the map (the centre line, the middle line).
		[8.5, func() -> void:
			hud.overlay.apply_at(_my_side(Vector2(9000, MapLayout.CY)))
			hud.overlay.disarm()
			world.camera.look_at_point(Vector2(MapLayout.CX, MapLayout.CY))],
		[11.0, func() -> void: await _shot("a08_map_mid")],
		# The help (the Admiral page), the pause menu (its buttons, then the
		# question before going back to the start screen), the hangar an
		# admiral can open with B, and both motherships in trouble.
		[11.2, func() -> void:
			hud._toggle_help()
			hud.help._show("Admiral")],
		[11.6, func() -> void: await _shot("a08a_help")],
		# The Keys page and the Controls page (which hides the help), then closed again.
		[11.62, func() -> void: hud.help._show("Keys")],
		[11.64, func() -> void: await _shot("a08a1_help_keys")],
		[11.66, func() -> void: hud._toggle_controls()],
		[11.68, func() -> void: await _shot("a08a2_controls")],
		[11.8, func() -> void:
			hud._toggle_controls()
			hud._toggle_pause_menu()],
		[12.2, func() -> void: await _shot("a08b_pause")],
		[12.22, func() -> void: hud.pause_menu.ask(PauseMenu.VIEW_START)],
		[12.26, func() -> void: await _shot("a08c_pause_ask")],
		[12.27, func() -> void: hud.pause_menu.show_card()],
		[12.28, func() -> void: hud.pause_menu.look_around()],
		# The feed's lines are a few seconds old by now and fade after 9: put them in again, so the picture and the dump always
		# measure the full feed, whatever the speed of the run.
		[12.285, func() -> void: _busy_hud(false)],
		[12.29, func() -> void: await _shot("a08d_look")],
		[12.3, func() -> void:
			hud._toggle_pause_menu()
			hud._open_hangar()],
		[12.8, func() -> void: await _shot("a09_hangar")],
		[13.0, func() -> void:
			hud.hangar.visible = false
			_trouble(true)],
		[13.4, func() -> void: await _shot("a09a_trouble")],
		# The Admiral's death card (it shows for 10 seconds, with no teammate row).
		[13.5, func() -> void: await _admiral_death_tour()],
		[13.6, func() -> void:
			_trouble(false)
			_finish("admiral")],
	]


## A map point written for Aurelian's side of the map, as the human's side has it:
## the same point for Aurelian, its mirror image across the centre line for Vhorr.
func _my_side(p: Vector2) -> Vector2:
	return p if world.human_team == Rules.HALCYON else MapLayout.mirror(p)


## The admiral tour's order step: for each command order that a feature
## module added (CommandOrders; there are none unless --variant switches one
## on), press its entry in the command card's Orders More list. An order that needs a spot arms
## its map tool: take a picture of the tool, then click a spot near our
## mothership (the order may be refused there, which is printed). Prints one
## "ui_tour: order <id> ..." line per order, puts the tool away and reopens
## the board if the tool closed it.
func _tour_orders() -> void:
	var orders: Dictionary = world.command.orders
	if orders.is_empty():
		return
	world.teams[world.human_team].treasury = 20000.0
	var spot := _my_side(world.mothership(Rules.HALCYON).global_position + Vector2(2500, 0))
	hud._close_others(null)
	var card := hud.command_view.card
	for id in orders:
		card.set_page("orders")
		card.toggle_list("more")
		var btn: Button = null
		var ids := card._list_ids()
		for i in ids.size():
			if str(ids[i]) == "feat:" + str(id):
				btn = card._entries[i]
		if btn == null:
			print("ui_tour: order %s has NO BUTTON" % id)
			continue
		if btn.disabled:
			print("ui_tour: order %s button is disabled" % id)
			continue
		btn.pressed.emit()
		if hud.overlay.tool != "":
			world.camera.look_at_point(spot)
			await _shot("a05b_tool_" + str(id))
			print("ui_tour: order %s armed; hint: %s; spot check: '%s'" % [id, hud.overlay.hint(), hud.overlay.blocker_at(spot)])
			hud.overlay.apply_at(spot)
			hud.overlay.disarm()
		else:
			print("ui_tour: order %s given from its button" % id)
		card.close_list()
	if not hud.board.visible:
		hud._toggle_board()
	await _shot("a05c_orders_done")


## The ring round the pilot's ship and the card on its target, on screen (the pilot's tour): a held enemy (put close to the ship so the
## team sees it), a torpedo coming in on a crossing path, and each preset of the ring and the card in turn, with a picture of each.
## Game's fields are set directly (no choose_ call, so the settings file is never written) and put back.
func _ring_tour() -> void:
	var ship := world.human.ship if world.human != null else null
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	var other := Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON
	var foe: Unit = null
	for s: Ship in world.ships:
		if s.team == other and s.alive:
			foe = s
			break
	if foe == null:
		for m: Minion in world.minions:
			if m.team == other and m.alive:
				foe = m
				break
	if foe != null:
		foe.global_position = ship.global_position + Vector2(650.0, -300.0)
		ship.controls.target_id = foe.uid
	var from := ship.global_position + Vector2(-900.0, 200.0)
	world.projectiles.spawn(from, (ship.global_position - from).normalized() * 250.0, 9.0, 5.0, Rules.W_TORP, {"radius": 5.0, "arm": 0.0}, foe, null)
	var was_ring := Game.ring_preset
	var was_card := Game.card_preset
	for p in 3:
		Game.ring_preset = p
		Game.card_preset = p
		await _wait_frames(8)
		await _shot("p04c_ring_card_%s" % ShipRingParts.preset_name(p).to_lower())
	Game.ring_preset = was_ring
	Game.card_preset = was_card
	ship.controls.target_id = -1


## A made ship of pilot `name` of team `team` in hull `hull`, launched, still and seen by the human's team (the death tour's attackers and
## teammates).
func _tour_ship(name: String, team: int, hull: String) -> Ship:
	var p := PilotProfile.new(name, team, 60 + world.profiles.size(), false)
	p.hull_id = hull
	world.profiles.append(p)
	var s := world.launch(p)
	if s != null:
		s.velocity = Vector2.ZERO
		s.controller = null
		s.visible_mask |= 1 << world.human_team
	return s


## The human in a live Fighter: the ship they have, or a new one (the dead pilot is let out of the wait, given the price and launched).
func _tour_launch() -> Ship:
	var h := world.human
	if h.ship == null or not is_instance_valid(h.ship) or not h.ship.alive:
		h.credits = 3000.0
		if h.state == "dead":
			h.state = "docked"
		h.respawn_t = 0.0
		h.buy_hull("fighter", world.teams[world.human_team])
		world.launch(h)
	return h.ship


## One hit of weapon kind `kind` on `target` from `src` at `angle` (radians from the target's nose), `amount` of it final and `hull` of it
## on the hull: logged in the target's own damage log and announced the way Combat announces it.
func _tour_hit(target: Ship, src: Unit, kind: int, angle: float, amount: float, hull: float) -> void:
	var d := DamageInfo.from_unit(src, amount, kind, target.global_position + Vector2.from_angle(target.rotation + angle) * 600.0)
	target.log_damage(d, amount)
	Events.damage_applied.emit(target, d, amount, hull)


## Let the dead pilot's card settle: two refreshes of the HUD and of the card.
func _death_refresh() -> void:
	for i in 2:
		await _wait_frames(6)
		hud.death_card.refresh(true)
	await _wait_frames(2)


## Check that the death card is `shown` (and print a PASS or FAIL line for `what`).
func _death_check(shown: bool, what: String) -> void:
	var ok := hud.death_card.visible == shown
	print("%s ui_tour: death card %s: %s" % ["PASS" if ok else "FAIL", "shown" if shown else "gone", what])
	if not ok:
		fails += 1


## The death card's pictures on the pilot's tour (the dead pilot's screen in each state): a crash with nothing logged (Row 1 only),
## a kill by a pilot (the Summary page, the Attackers page, collapsed), a watch (the hangar open over it, the watched ship shot down),
## the launch (the card gone) and a kill by a turret with minions (grouped lines). A dead pilot stays dead until the next launch, and the
## Space hold of this tour is let go while watching (Space ends a watch).
func _death_tour() -> void:
	var h := world.human
	var card := hud.death_card
	var cam := world.camera
	var foe := Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON
	# Park the pointer in the middle (a window's pointer at the corner pans the camera and ends a watch).
	var park := InputEventMouseMotion.new()
	park.position = get_viewport().get_final_transform() * (get_viewport().get_visible_rect().size * 0.5)
	park.global_position = park.position
	Input.parse_input_event(park)
	# The crash: the pilot is dead already (the p08 step) and nothing was logged, so the card has Row 1 only.
	h.respawn_t = 500.0
	await _death_refresh()
	_death_check(true, "a crash (Row 1 only)")
	await _shot("p08b_death_crash")
	# A kill by a pilot: bolts from the rear, a torpedo from the front.
	var atlas := _tour_ship("Atlas", foe, "lance")
	var boreas := _tour_ship("Boreas", foe, "fighter")
	var ship := _tour_launch()
	if ship == null or atlas == null or boreas == null:
		print("FAIL ui_tour: the death tour could not make its ships")
		fails += 1
		return
	await _wait_frames(4)
	for i in 3:
		_tour_hit(ship, atlas, Rules.W_BOLT, PI, 120.0, 30.0)
	_tour_hit(ship, boreas, Rules.W_TORP, 0.0, 500.0, 500.0)
	world.combat.kill(ship, DamageInfo.from_unit(boreas, 500.0, Rules.W_TORP, ship.global_position + Vector2(600.0, 0.0)))
	h.respawn_t = 500.0
	await _death_refresh()
	_death_check(true, "killed by a pilot")
	await _shot("p08c_death_pilot")
	card._set_page(1)
	await _death_refresh()
	await _shot("p08d_death_attackers")
	card._set_page(0)
	card._toggle_collapse()
	await _death_refresh()
	await _shot("p08e_death_collapsed")
	card._toggle_collapse()
	# Watching a teammate: C once, the hangar over the card, then the watched ship shot down.
	Input.action_release("center_on_ship")
	hud.router._camera_key()
	await _death_refresh()
	await _wait_frames(20)
	_death_check(true, "watching a teammate")
	print("%s ui_tour: death card: the watch label shows (%s)" % ["PASS" if card._watch_label.visible else "FAIL", card._watch_label.text])
	if not card._watch_label.visible:
		fails += 1
	await _shot("p08f_death_watch")
	hud._open_hangar()
	await _death_refresh()
	await _shot("p08g_death_watch_hangar")
	hud.hangar.visible = false
	if cam.watched != null:
		world.combat.kill(cam.watched, DamageInfo.new())
	await _death_refresh()
	await _shot("p08h_death_watch_lost")
	# The launch: the card and the watch are gone.
	cam.watch_clear()
	ship = _tour_launch()
	await _death_refresh()
	_death_check(false, "after the launch")
	await _shot("p08i_death_launch")
	# A kill by a turret with minions: grouped lines.
	var turret: Unit = null
	for t: Turret in world.turrets:
		if t.team == foe and t.alive:
			turret = t
			break
	var minions: Array[Unit] = []
	for m: Minion in world.minions:
		if m.team == foe and m.alive and minions.size() < 3:
			m.visible_mask |= 1 << world.human_team
			minions.append(m)
	if ship != null and turret != null:
		turret.visible_mask |= 1 << world.human_team
		_tour_hit(ship, turret, Rules.W_BOLT, PI * 0.5, 300.0, 60.0)
		for m: Unit in minions:
			_tour_hit(ship, m, Rules.W_BOLT, -PI * 0.5, 90.0, 20.0)
		world.combat.kill(ship, DamageInfo.from_unit(turret, 300.0, Rules.W_BOLT, ship.global_position + Vector2(0.0, 600.0)))
		h.respawn_t = 500.0
		await _death_refresh()
		card._set_page(1)
		await _death_refresh()
		_death_check(true, "killed by a turret with minions")
		await _shot("p08j_death_turret")
	# Back to the pilot's tour: a live ship, the card gone, Space held again.
	ship = _tour_launch()
	await _death_refresh()
	card._set_page(0)
	Input.action_press("center_on_ship")


## The Admiral's death card: the Admiral flies a Fighter, is shot down and the card shows (no teammate row) for 10 seconds.
func _admiral_death_tour() -> void:
	var h := world.human
	var card := hud.death_card
	var foe := Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON
	# The motherships' trouble of the step before ends here: a mothership in trouble launches nobody.
	_trouble(false)
	h.credits = 3000.0
	h.buy_hull("fighter", world.teams[world.human_team])
	var ship := world.launch(h)
	var atlas := _tour_ship("Atlas", foe, "lance")
	if ship == null or atlas == null:
		print("FAIL ui_tour: the Admiral's death tour could not make its ships")
		fails += 1
		return
	await _wait_frames(4)
	for i in 3:
		_tour_hit(ship, atlas, Rules.W_BOLT, PI, 120.0, 30.0)
	world.combat.kill(ship, DamageInfo.from_unit(atlas, 120.0, Rules.W_BOLT, ship.global_position + Vector2(-600.0, 0.0)))
	await _death_refresh()
	_death_check(true, "the Admiral's ship shot down")
	var no_row := not card._mine_btn.visible
	print("%s ui_tour: death card: the Admiral's card has no teammate row" % ("PASS" if no_row else "FAIL"))
	if not no_row:
		fails += 1
	await _shot("a09b_death_admiral")


## Wait `n` drawn frames (a step of the tour that has to let the HUD draw before its picture).
func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
