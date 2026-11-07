extends Node
## WHAT THIS IS: the RTS tour: it drives the Admiral's command view (the selection, the smart right-click, the
## verbs, the card, the strip, the production panel, the command pause) the way a player does, checks what each
## screen says and prints one PASS or FAIL line per check. Windowed it also saves a picture at each picture step.
##
## HOW IT WORKS: like tests/ui_tour.gd: it waits until the HUD exists, then follows a timed list of steps
## [seconds since the HUD appeared, a function to run]. The checks of each part are static functions in
## tests/lib/ (RtsTourSelect for the selection and the orders). The tour counts the failed checks: the run ends
## with "rts_tour: done" and "rts_tour: N failures" (0 failures is a pass). If the run takes longer than --secs
## (default 120 real seconds) it prints "rts_tour: timeout" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=tour --force-hud --test=rts_tour
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --bot=tour --test=rts_tour --shots=<dir>
##   godot --headless --path remake -- --auto --role=admiral --bot=tour --force-hud --test=rts_tour --rts-perf   (the cost of the view; prints RTS_PERF lines)
##
## HOW TO READ THE OUTPUT: one "PASS rts_tour: <check>" or "FAIL rts_tour: <check>" line per check; the last lines are
## "rts_tour: done" and "rts_tour: N failures". Any SCRIPT ERROR line from Godot means a UI script broke.
##
## With --dump-layout the picture steps also print every control on screen (tests/lib/ui_dump.gd, the same lines
## tools/ui_layout_check.py reads), and --ui-size=WxH[,WxH...] runs the dump at each size in turn, as the ui_tour does.
##
## WHO USES IT: main.gd loads it for --test=rts_tour (it loads tests/<name>.gd, adds it after the World and calls
## setup()); the lead's gates run it at several window sizes.

## Prints the dumps (the UIDUMP lines).
const UiDump := preload("res://tests/lib/ui_dump.gd")

## The running match (set by setup()).
var world: World
## The HUD, once found (null until then).
var hud: Hud
## Seconds since the HUD was found.
var t := 0.0
## Which step is next (an index into the step list).
var step := 0
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True while a step is still running.
var busy := false
## The folder the pictures go into (--shots).
var dir := ""
## True with --dump or --dump-layout: picture steps also print every control (see UiDump); `layout` adds the facts the
## layout checker needs.
var dump := false
var layout := false  # the layout
## The window sizes of a headless dump (--ui-size; the first is the size the run starts and ends at).
var sizes: Array[Vector2i] = [Vector2i(1280, 720)]


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	layout = Game.opt("dump-layout", false) == true
	dump = layout or Game.opt("dump", false) == true
	sizes = _ui_sizes()
	if DisplayServer.get_name() == "headless" and (dump or Game.opt("ui-size") != null):
		get_tree().root.size = sizes[0]
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS


## The window sizes of a headless dump: --ui-size=WxH (several separated by commas); a size under 320 x 240 is
## skipped; with none left, 1280x720.
func _ui_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in str(Game.opt("ui-size", "1280x720")).split(",", false):
		var xy := part.split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	return out


## Count one check and print its line (`detail` is added to a FAIL).
func check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS rts_tour: %s" % name)
	else:
		fails += 1
		print("FAIL rts_tour: %s %s" % [name, detail])


## Find the HUD, then run each step when its time comes.
func _process(dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 1000 * int(Game.opt("secs", 120)):
		print("rts_tour: timeout")
		get_tree().quit()
		return
	if hud == null:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		return
	t += dt
	var steps := _steps()
	if step >= steps.size() or busy:
		return
	var s: Array = steps[step]
	if t >= float(s[0]):
		step += 1
		busy = true
		await (s[1] as Callable).call()
		busy = false


## Take picture `name`: windowed, save <name>.png in the --shots folder; headless, print the step name. With --dump the
## controls are printed too (at every --ui-size size in turn when headless).
func _shot(name: String) -> void:
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		print("rts_tour step ", name)
	if dump and headless and sizes.size() > 1:
		for sz in sizes:
			get_tree().root.size = sz
			for i in 8:
				await get_tree().process_frame
			hud.command_view.refresh()
			RtsTourView.pieces(self, "%s@%dx%d" % [name, sz.x, sz.y])
			UiDump.dump(hud, name, layout)
		get_tree().root.size = sizes[0]
		for i in 3:
			await get_tree().process_frame
	else:
		hud.command_view.refresh()
		RtsTourView.pieces(self, name)
		if dump:
			UiDump.dump(hud, name, layout)
	if headless:
		return
	await RenderingServer.frame_post_draw
	var path := dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## End the tour: "rts_tour: done", the failure count, and quit.
func _finish() -> void:
	if fails == 0:
		print("rts_tour: done")
	print("rts_tour: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


## The tour: [seconds since the HUD appeared, what to do].
func _steps() -> Array:
	# --rts-perf: only the cost measure (RtsTourPerf), at most 2 ms a frame more with the view, 63 ships out a team.
	if Game.opt("rts-perf", false) != false:
		return [
			[1.0, func() -> void: await RtsTourPerf.run(self)],
			[1.5, func() -> void: _finish()],
		]
	return [
		[1.0, func() -> void:
			RtsTourSelect.run(self, world)
			await _shot("r01_empty")],
		[1.5, func() -> void:
			RtsTourView.select(self, 3, true)
			await _shot("r02_selected")],
		[2.0, func() -> void: RtsTourSelect.after_ticks(self, world)],
		[2.5, func() -> void:
			RtsTourView.many(self)
			await _shot("r03_many")],
		[3.0, func() -> void:
			RtsTourCard.table(self)
			RtsTourCard.pages_and_orders(self)
			RtsTourCard.build_looks(self)
			RtsTourCard.armed(self)
			RtsTourView.select(self, 0, false)
			await _shot("r04_card_build")],
		[3.4, func() -> void:
			RtsTourCard.prep_money(self, 400.0)
			await _shot("r05_build_wash")
			RtsTourCard.prep_money(self, -1.0)],
		[3.8, func() -> void:
			RtsTourView.select(self, 2, false)
			await _shot("r06_card_orders")],
		[4.2, func() -> void:
			RtsTourView.select(self, 0, true)
			await _shot("r07_card_base")],
		[4.6, func() -> void:
			RtsTourView.select(self, 0, false)
			RtsTourStrip.strip(self)
			await _shot("r08_strip")],
		[5.0, func() -> void:
			RtsTourCard.after_ticks(self)
			RtsTourProd.fill(self)
			await _shot("r10_prod_full")
			RtsTourProd.rows(self)
			await _shot("r11_prod_after")],
		[5.6, func() -> void:
			RtsTourProd.after_ticks(self)
			RtsTourProd.fill(self)
			await RtsTourStrip.pause(self)
			await _shot("r09_after_pause")],
		[7.2, func() -> void:
			RtsTourStrip.after_resume(self)],
		[7.4, func() -> void:
			await RtsTourView.danger(self)
			await _shot("r12_danger")
			hud.world.mothership(hud.world.human_team).failure_t = 0.0],
		[8.0, func() -> void: await RtsTourView.layouts(self)],
		[9.5, func() -> void: _finish()],
	]
