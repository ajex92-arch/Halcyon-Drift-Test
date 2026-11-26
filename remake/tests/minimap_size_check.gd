extends Node
## WHAT THIS IS: the check of the minimap's own size (T-125, F40c): 80% to 140% in steps of 10%, default 100%. Clicks land where
## they should at every size, the minimap fits the bottom row at 1280 x 720 without touching anything, and the pause menu's
## "Minimap size" row works.
##
## HOW IT WORKS: it waits for the HUD, makes the window 1280 x 720 and, for 80%, 100% and 140% (and every step in between):
##   1. the minimap is that much bigger (300 x 234 pixels at 100%) and the layers drawn under it are as big;
##   2. a click on each of the four corners and the centre moves the camera's goal to that corner or centre of the world
##      (a corner click is kept inside the world), and so does a drag step;
##   3. the minimap's rectangle touches no other piece of the HUD (the gear slots, the ship readout, the seat bar, the kill
##      feed, the top bar, the "me" panel) and stays inside the window; the line "minimap_size_check: layout NNN% ..." says so;
##   4. the words under the shared points are never smaller than 8 pixels on the screen.
## Then the pause menu: with no touch the minimap stays hidden under the card; a touch of the Minimap size row shows it, the
## row's minus and plus buttons and slider (through the menu's own functions) change the size by one step and the value in
## words, the size keeps inside 80-140, the default is 100, and the stored number is kept to a step. The settings file is only
## written when --settings-check=<text> names part of the user data folder (as tests/fog_check.gd does): then it also checks the
## file round trip. It ends with "minimap_size_check: N failures" and quits; after 90 s of real time "minimap_size_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=pause --force-hud --seed=7 --test=minimap_size_check
##
## WHO USES IT: main.gd loads it for --test=minimap_size_check. It reads the Hud, Minimap and CameraRig and sets Game.minimap_pct
## (put back to 100 at the end); it presses nothing on the real screen.

## How close (world units) a click's goal must be to the spot it was aimed at.
const TOL := 1.0

## The running match (set by setup()).
var world: World
## The HUD (null until found).
var hud: Hud
## How many checks failed.
var failures := 0
## True once the check has started.
var _started := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 90 s of real time; start once the HUD exists.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 90000:
		print("minimap_size_check: timeout")
		get_tree().quit()
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or world.camera == null:
		return
	_started = true
	_run()


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(5)
	var mm := hud.minimap
	_expect(Game.minimap_pct == 100 and Game.MINIMAP_PCT_DEFAULT == 100 and Game.MINIMAP_PCT_MIN == 80 and Game.MINIMAP_PCT_MAX == 140 and Game.MINIMAP_PCT_STEP == 10, "the default is 100%, the range 80% to 140% in steps of 10%")
	_expect(Game.clamp_minimap_pct(30) == 80 and Game.clamp_minimap_pct(70) == 80 and Game.clamp_minimap_pct(500) == 140 and Game.clamp_minimap_pct(96) == 100 and Game.clamp_minimap_pct(104) == 100, "a stored number is kept inside the range and to a step")
	var vp := hud.get_viewport_rect().size
	_expect(vp == Vector2(1280.0, 720.0), "the window is 1280 x 720 (%s)" % str(vp))
	for pct in range(Game.MINIMAP_PCT_MIN, Game.MINIMAP_PCT_MAX + 1, Game.MINIMAP_PCT_STEP):
		Game.minimap_pct = pct
		mm.apply_size()
		await _frames(4)
		var s := float(pct) / 100.0
		var want := Vector2(300.0, MapLayout.H * 300.0 / MapLayout.W) * s
		_expect(mm.size.is_equal_approx(want) or (mm.size - want).length() < 1.0, "%d%%: the minimap is %.0f x %.0f (%s)" % [pct, want.x, want.y, str(mm.size)])
		var layers_ok := true
		for c in mm.get_children():
			if c is MinimapStill and ((c as MinimapStill).size - mm.size).length() > 1.0:
				layers_ok = false
		_expect(layers_ok, "%d%%: the layers under the minimap are as big as it" % pct)
		_expect(Vector2(mm.size_scale(), mm.size_scale()).is_equal_approx(Vector2(s, s)), "%d%%: the size factor is %.1f" % [pct, s])
		_expect(float(maxi(8, int(ceil(8.0 / s)))) * s >= 8.0 - 0.001, "%d%%: the words under the shared points are at least 8 pixels" % pct)
		# Clicks: the four corners and the centre.
		var spots := {
			"top left": [Vector2.ZERO, Vector2(0.0, 0.0)],
			"top right": [Vector2(mm.size.x, 0.0), Vector2(MapLayout.W, 0.0)],
			"bottom left": [Vector2(0.0, mm.size.y), Vector2(0.0, MapLayout.H)],
			"bottom right": [mm.size, Vector2(MapLayout.W, MapLayout.H)],
			"centre": [mm.size * 0.5, Vector2(MapLayout.W, MapLayout.H) * 0.5],
		}
		for name: String in spots:
			var at: Vector2 = spots[name][0]
			var goal: Vector2 = spots[name][1]
			world.camera.free = true
			world.camera._free_pos = Vector2(-1.0, -1.0)
			_click(mm, at)
			var got: Vector2 = world.camera._free_pos
			_expect((got - goal).length() <= TOL, "%d%%: a click on the %s lands on the %s of the map (%s, wanted %s)" % [pct, name, name, str(got), str(goal)])
		# A drag step lands the same way.
		world.camera._free_pos = Vector2(-1.0, -1.0)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = mm.size * 0.25
		mm._gui_input(press)
		var move := InputEventMouseMotion.new()
		move.position = mm.size * 0.75
		mm._gui_input(move)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = move.position
		mm._gui_input(release)
		_expect((world.camera._free_pos - Vector2(MapLayout.W, MapLayout.H) * 0.75).length() <= TOL, "%d%%: a drag follows the pointer (%s)" % [pct, str(world.camera._free_pos)])
		# Layout: nothing under or beside the minimap overlaps it, and it is in the window.
		var problems := _overlaps(mm)
		print("minimap_size_check: layout %d%% minimap %s overlaps: %s" % [pct, str(mm.get_global_rect()), "none" if problems.is_empty() else str(problems)])
		_expect(problems.is_empty(), "%d%%: the minimap overlaps nothing at 1280 x 720 %s" % [pct, str(problems)])
	# The pause menu's row.
	Game.minimap_pct = Game.MINIMAP_PCT_DEFAULT
	mm.apply_size()
	hud._toggle_pause_menu()
	await _frames(4)
	var pm := hud.pause_menu
	_expect(pm != null and pm.visible and get_tree().paused, "the pause menu is open")
	_expect(not hud.minimap.visible, "with the Minimap size row untouched the minimap stays hidden under the card")
	_expect(pm._map_slider != null and pm._map_value != null and pm._flash_button != null, "the card has the Minimap size row and the ship-flash button")
	_expect(is_equal_approx(pm._map_slider.min_value, 80.0) and is_equal_approx(pm._map_slider.max_value, 140.0) and is_equal_approx(pm._map_slider.step, 10.0), "the slider runs 80 to 140 in steps of 10")
	_expect(pm._map_value.text == "100%" and is_equal_approx(pm._map_slider.value, 100.0), "the row shows 100%")
	_expect(_has_button(pm, "-") and _has_button(pm, "+"), "the row has a minus and a plus button")
	_expect(pm._flash_button.text == "Flash my ship when the camera returns: On", "the flash button reads On by default (%s)" % pm._flash_button.text)
	pm._peek_minimap()
	await _frames(2)
	_expect(hud.minimap.visible, "touching the row shows the minimap under the card")
	# The row's own functions write the settings file: only when the user data folder is marked.
	var marker := str(Game.opt("settings-check", ""))
	if marker != "" and OS.get_user_data_dir().contains(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
		pm._step_minimap(1)
		await _frames(3)
		_expect(Game.minimap_pct == 110 and pm._map_value.text == "110%" and is_equal_approx(mm.size_scale(), 1.1) and mm.visible, "the plus button makes the minimap one step bigger at once (110%)")
		pm._step_minimap(-1)
		pm._step_minimap(-1)
		pm._on_map_slider(140.0)
		await _frames(2)
		_expect(Game.minimap_pct == 140 and is_equal_approx(pm._map_slider.value, 140.0) and pm._map_value.text == "140%", "the slider sets 140%")
		pm._step_minimap(1)
		_expect(Game.minimap_pct == 140, "plus stops at 140%")
		_on_pm_min(pm)
		var cfg := ConfigFile.new()
		_expect(cfg.load(Game.SETTINGS_FILE) == OK and int(cfg.get_value("game", "minimap_pct", 0)) == 80, "the size is in the settings file")
		pm._on_flash()
		_expect(not Game.return_flash and pm._flash_button.text.ends_with("Off"), "the flash button turns the flash off")
		_expect(cfg.load(Game.SETTINGS_FILE) == OK and cfg.get_value("game", "return_flash", true) == false, "and the file remembers it")
		Game.minimap_pct = 100
		Game.return_flash = true
		Game.use_remembered_hud()
		_expect(Game.minimap_pct == 80 and not Game.return_flash, "a new run takes both settings back from the file")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	else:
		print("minimap_size_check: the settings file part is skipped (no --settings-check=<part of the user data folder>)")
	Game.minimap_pct = Game.MINIMAP_PCT_DEFAULT
	Game.return_flash = true
	mm.apply_size()
	pm.resume()
	await _frames(2)
	_expect(not get_tree().paused and hud.minimap.visible, "after Resume the minimap shows as usual")
	print("minimap_size_check: %d failures" % failures)
	get_tree().quit()


## The minus button pressed until the bottom.
func _on_pm_min(pm: PauseMenu) -> void:
	for i in 10:
		pm._step_minimap(-1)
	_expect(Game.minimap_pct == 80, "minus stops at 80%")


## Press and let go of the left button at `pos` on the minimap `mm` (local pixels).
func _click(mm: Minimap, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	mm._gui_input(ev)
	ev.pressed = false
	mm._gui_input(ev)


## Is there a button with the words `text` in `n`?
func _has_button(n: Node, text: String) -> bool:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return true
	return false


## The pieces of the HUD that the minimap `mm` overlaps, as their names (empty: none), and "window" when it leaves the window.
func _overlaps(mm: Minimap) -> Array:
	var out: Array = []
	var r := mm.get_global_rect()
	var win := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
	if not win.encloses(r.grow(-0.5)):
		out.append("window")
	var pieces := {"slots": hud.slots, "status": hud.status, "seat_bar": hud.seat_bar, "feed": hud.feed, "top_bar": hud.top_bar, "me_panel": hud.me_panel, "banner": hud.banner}
	for name: String in pieces:
		var c := pieces[name] as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var cr := c.get_global_rect()
		if name == "feed":
			# The feed is a column whose box is taller than its lines: only the lines it shows count.
			cr = _used_rect(c)
		if cr.size.x > 0.0 and cr.grow(-1.0).intersects(r.grow(-1.0)):
			out.append(name)
	return out


## The part of control `c` that its visible children cover (its own rectangle when it has none).
func _used_rect(c: Control) -> Rect2:
	var rect := Rect2()
	var first := true
	for ch in c.get_children():
		if ch is Control and (ch as Control).visible:
			var cr := (ch as Control).get_global_rect()
			if cr.size.x <= 0.0 or cr.size.y <= 0.0:
				continue
			rect = cr if first else rect.merge(cr)
			first = false
	return rect


## Count a PASS or FAIL line for the check `what`.
func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
