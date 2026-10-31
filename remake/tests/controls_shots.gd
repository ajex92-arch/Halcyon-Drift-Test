extends Node
## WHAT THIS IS: the picture tour of the Controls page and the things that came with it: it saves windowed
## pictures of the page on each tab (Home with each of the three layouts, Flying, Flying with the board
## open), of a key being awaited, of a clash warning with the danger triangle, of the help's Keys page,
## of the speed row in several states, of the top bar's speed tag and of the danger sign at three sizes
## next to the team colours. A person looks at them.
##
## HOW IT WORKS: setup() waits for the HUD, then run() goes through the pictures in order. The page it
## photographs is the real one the HUD makes (Hud._toggle_controls()); it never writes the settings file
## (autosave is off) and the run should start with APPDATA pointing at an empty scratch folder anyway. The
## speed row pictures use the test hooks of SpeedControl: before the game can run faster speeds the
## faster buttons, the 2x and 0.5x "current" highlight and the greyed "Against the computer only" row are
## forced by this script (and say so in the picture's caption), and the top bar's "SPEED 2x" is a forced
## text. The pictures are named <team>_<name>.png in the --shots folder; headless, the steps only print
## their names. It prints "controls_shots: done (<team>)" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/; park
## the window off screen with --position; set APPDATA to a scratch folder first):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=admiral --team=vhorr --bot=team --test=controls_shots --shots=<dir>
##
## WHO USES IT: main.gd loads it for --test=controls_shots (it calls setup()). It calls Hud._toggle_controls(),
## Hud._toggle_help() and the page's own functions.

## The running match.
var world: World
## The HUD, found once it exists.
var hud: Hud = null
## Where the pictures go (--shots, default the user data folder).
var dir := ""


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


## Wait for the HUD, take every picture, quit.
func _run() -> void:
	for _i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null:
			break
		await get_tree().process_frame
	if hud == null:
		print("controls_shots: no HUD")
		get_tree().quit()
		return
	for _i in 20:
		await get_tree().process_frame
	KeyMap.reset_to_defaults()
	await _pages()
	await _help()
	await _speed_pictures()
	await _glyph_sheet()
	print("controls_shots: done (%s)" % Rules.TEAM_DISPLAY[world.human_team].to_lower())
	get_tree().quit()


## Save the picture `shot_name` (headless: print its name).
func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	print("controls_shots: %s" % shot_name)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := dir.path_join("%s_%s.png" % [Rules.TEAM_DISPLAY[world.human_team].to_lower(), shot_name])
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## The Controls page on each tab, with each layout, the awaited key and a clash.
func _pages() -> void:
	hud._toggle_controls()
	var page := hud.controls
	page.autosave = false
	page.show_mode("home")
	await _shot("controls_home_B")
	for id in ["A", "C"]:
		KeyMap.set_preset("home_layout", id)
		page.rebuild()
		await _shot("controls_home_" + id)
	KeyMap.set_preset("home_layout", "B")
	page.show_mode("flying")
	await _shot("controls_flying")
	page.show_mode("flying_board")
	await _shot("controls_board")
	page.show_mode("flying")
	var btn: Button = page.rows_part.by_key["flying/use_kit/0"]
	page.scroll_to_row("flying", "use_kit")
	page.begin_capture("flying", "use_kit", 0, btn)
	await _shot("controls_capture")
	page.capture.cancel()
	page.begin_capture("flying", "use_kit", 0, btn)
	page.capture_text("W")
	page.scroll_to_row("flying", "use_kit")
	await _shot("controls_clash")
	page.choose_keep()
	page.show_mode("home")
	page.begin_capture("home", "idle_next", 0)
	page.capture_text("R")
	await _shot("controls_clash_three")
	page.choose_keep()
	KeyMap.reset_all()
	hud._toggle_controls()


## The help's Keys page.
func _help() -> void:
	hud._toggle_help()
	hud.help._show("Keys")
	await _shot("help_keys")
	hud._toggle_help()


## The speed row in several states, in a panel over the HUD, and the top bar's speed tag.
func _speed_pictures() -> void:
	var panel := UiKit.panel(16)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.add_child(panel)
	var col := UiKit.vbox(10)
	panel.add_child(col)
	# The game's own row: every speed the game has (the slow and the faster ones), 1x in force.
	col.add_child(UiKit.label("The game's own row (1x in force)", 14, Palette.MIST))
	_add_row(col, -1, "")
	# Forced by this script from here on: the faster buttons exist, and the speed in force is made up.
	SpeedControl.test_fast_steps = [100, 150, 200]
	for case: Array in [[100, "", "Forced: faster buttons shown, 1x in force"], [200, "", "Forced: 2x in force"], [50, "", "Forced: 0.5x in force"], [100, SpeedControl.ONLINE, "Forced: against other people, the row is greyed"]]:
		col.add_child(UiKit.label(String(case[2]), 14, Palette.MIST))
		_add_row(col, int(case[0]), String(case[1]))
	await _shot("speed_row_states")
	SpeedControl.test_fast_steps = []
	panel.queue_free()
	# The top bar: the real tag at 0.5x, then a forced text for the faster ones.
	SpeedControl.send(world, 50)
	hud.top_bar.refresh(world)
	await _shot("topbar_speed_half")
	SpeedControl.send(world, 100)
	hud.set_process(false)
	var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
	tags.visible = true
	tags.text = "SPEED 2x   (forced text)"
	await _shot("topbar_speed_2x_forced")
	tags.text = "SPEED 2x (limited)   (forced text)"
	await _shot("topbar_speed_2x_limited_forced")
	hud.set_process(true)


## Add one speed row to `col` in the state: `current` in force (-1: the world's own), `blocked` the reason
## it is greyed ("" none).
func _add_row(col: VBoxContainer, current: int, blocked: String) -> void:
	var row := SpeedRow.new()
	row.forced_current = current
	col.add_child(row)
	row.setup(world)
	if blocked != "":
		row.show_blocked(blocked)
	row.refresh()


## A sheet with the danger sign at 10, 14 and 16 pixels on the panel colour, in colour and as a black
## shape, next to the Aurelian amber, the Vhorr red and the danger magenta.
func _glyph_sheet() -> void:
	var sheet := GlyphSheet.new()
	hud.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	await _shot("danger_glyph")
	sheet.queue_free()


## The sheet of danger signs (drawn in code).
class GlyphSheet extends Control:
	## Give the sheet its size.
	func _init() -> void:
		custom_minimum_size = Vector2(520, 230)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Draw the sheet: a panel-coloured ground, the sign at three sizes in colour and in black on light
	## grey, and three colour chips.
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.PANEL)
		draw_rect(Rect2(Vector2(250, 0), Vector2(size.x - 250, 120)), Color(0.85, 0.87, 0.9))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(14, 22), "In colour (panel ground)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.ICE)
		draw_string(font, Vector2(262, 22), "As a black shape (light ground)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
		var x := 40.0
		for s in [10.0, 14.0, 16.0]:
			Glyphs.danger(self, Vector2(x, 70), s)
			draw_string(font, Vector2(x - 12, 108), "%d px" % int(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.MIST)
			var pts := Glyphs.triangle(Vector2(x + 236.0, 70), s)
			draw_colored_polygon(pts, Color.BLACK)
			x += 70.0
		draw_string(font, Vector2(14, 150), "Beside the team colours", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.ICE)
		var chips := [["Aurelian amber", Palette.AMBER], ["Vhorr red", Palette.CINDER], ["Vhorr vein", Palette.CINDER_VEIN], ["Danger", Palette.DANGER]]
		for i in chips.size():
			var cx := 14.0 + 124.0 * i
			draw_rect(Rect2(Vector2(cx, 162), Vector2(112, 30)), chips[i][1])
			draw_string(font, Vector2(cx, 214), String(chips[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.MIST)
			Glyphs.danger(self, Vector2(cx + 56, 177), 14.0)
