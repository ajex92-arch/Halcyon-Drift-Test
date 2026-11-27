extends Node
## WHAT THIS IS: the check of RT6's far-zoom icon layer (C1): below the icon line nothing is drawn and the ships keep their own
## drawings; past it there is one icon for each squadron (a pip for each ship, lit if alive) and the ships' own drawings are
## handed over (hidden); the line keeps its 10% gap (a view resting between the two keeps what it was); the line the player
## chooses is held between 11,000 and 30,000 in steps of 1,000 and a line moved out makes the icons wait for a wider view;
## every hull has a shape, none is a reserved one; the selected squadron is marked; motherships keep their pictures; and the
## icons draw without a script error.
##
## HOW IT WORKS: setup() waits for the HUD (the overlay makes the layer), builds three squadrons and a big ship beside our
## mothership, then sets the camera's zoom for a chosen view width and reads the layer (active, items(), icons_drawn) and the ships'
## "Visual" nodes. It never saves a setting (IconLayer.set_line(.., false)). It prints a FAIL line for every check that does
## not hold, then "icon_layer_check: N failures (M checks)".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-admiral-ai --force-hud --seed=7 --test=icon_layer_check
##
## WHO USES IT: main.gd loads it for --test=icon_layer_check (it calls setup()); the lead's run_checks list.

var world: World
var hud: Hud
var layer: IconLayer
var team := 0
var checks := 0
var fails := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _check(what: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


func _tick(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


## Windowed pictures: with --shots=<folder> (and a window) save the viewport as <folder>/<name>.png. Nothing in a headless run.
func _shot(name: String) -> void:
	var dir := str(Game.opt("shots", ""))
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A new squad of hull `hull` with `n` crew ships (kind "squadron" for a small hull, else "ship"), beside our mothership.
func _squad(hull: String, n: int) -> Squad:
	var s := Squad.new()
	s.id = world.next_uid()
	s.team = team
	s.kind = RtsHulls.record_kind(hull)
	s.hull_id = hull
	s.max_members = RtsHulls.max_count(hull)
	s.created_tick = world.tick_count
	world.squads[s.id] = s
	for i in n:
		var p := Crew.make(world, team, hull, s, s.member_uids.size())
		world.profiles.append(p)
		var ms := world.mothership(team)
		var ship := world.spawner.spawn_pilot_ship(p, ms.launch_point(p.slot, float(Ships.get_def(hull)["radius"])), ms.rotation)
		ship.controller = null
		ship.velocity = Vector2.ZERO
		p.ship = ship
		p.state = "flying"
		s.member_uids.append(ship.uid)
	return s


## Put the camera at a view `width` world units across and let it settle.
func _view(width: float) -> void:
	var cam := world.camera
	var z := get_viewport().get_visible_rect().size.x / width
	cam.target_zoom = z
	cam.zoom = Vector2(z, z)
	await _frames(6)
	cam.zoom = Vector2(z, z)
	await _frames(3)


## The "Visual" node of ship `uid`.
func _visual(uid: int) -> CanvasItem:
	var u: Variant = world.by_uid.get(uid)
	return (u as Unit).get_node_or_null("Visual") as CanvasItem if u != null else null


func _run() -> void:
	for i in 600:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null and hud.overlay != null and hud.overlay.icons != null:
			break
		await _tick()
	_check("the HUD and the icon layer exist (use --force-hud --role=admiral)", hud != null and world.human_role == "admiral" and hud.overlay != null and hud.overlay.icons != null)
	if hud == null or hud.overlay == null or hud.overlay.icons == null:
		_finish()
		return
	team = world.human_team
	layer = hud.overlay.icons
	IconLayer.set_line(RtsUiCalls.ICON_VIEW_W, false)
	await _tick(3)
	_check("the icon line starts at the design's 16,000", IconLayer.line_w == 16000 and RtsUiCalls.ICON_VIEW_W == 16000)
	var sq_a := _squad("fighter", 3)
	var sq_b := _squad("bomber", 2)
	var sq_c := _squad("flak", 1)
	var big := _squad("destroyer", 1)
	await _tick(3)

	# Below the line: nothing drawn, the ships keep their pictures.
	await _view(10000.0)
	await _shot("icons_1_below_line")
	_check("below the line: the icons are off", not IconLayer.active)
	_check("below the line: the snapshot is empty and nothing is drawn", layer.items().is_empty() and layer.icons_drawn == 0)
	var vis_a := _visual(sq_a.member_uids[0])
	_check("below the line: a ship keeps its own picture", vis_a != null and vis_a.visible)

	# Past the line: one icon for each squadron, the pictures handed over.
	await _view(20000.0)
	await _shot("icons_2_past_line")
	_check("past the line: the icons are on", IconLayer.active, "view %.0f" % layer.view_w)
	_check("past the line: the view is measured in world units", absf(layer.view_w - 20000.0) < 200.0, "%.1f" % layer.view_w)
	var mine := 0
	for it: Array in layer.items():
		if int(it[0]) == 0 and int(it[3]) == team:
			mine += 1
	var squads_ours := 0
	for rec: Squad in RtsSelect.our_squads(world, team):
		squads_ours += 1
	_check("past the line: one icon for each of our squadrons and big ships (%d)" % squads_ours, mine == squads_ours and squads_ours >= 4, "%d icons, %d squads" % [mine, squads_ours])
	_check("past the line: all of them are drawn", layer.icons_drawn == layer.items().size() and layer.icons_drawn > 0, "%d of %d" % [layer.icons_drawn, layer.items().size()])
	_check("past the line: a ship's own picture is handed over", vis_a != null and not vis_a.visible)
	var m := world.mothership(team)
	var mv := m.get_node_or_null("Visual") as CanvasItem
	_check("past the line: the mothership keeps its picture", mv != null and mv.visible)
	var by_shape := {}
	var pips_ok := true
	for it: Array in layer.items():
		if int(it[0]) == 0 and int(it[3]) == team:
			by_shape[str(it[4])] = int(by_shape.get(str(it[4]), 0)) + 1
			var most := int(it[6])
			if most != 0 and (int(it[5]) < 1 or int(it[5]) > most):
				pips_ok = false
	_check("past the line: the shapes are the classes' (chevron, bowtie, hex_s, hex_l)", by_shape.has("chevron") and by_shape.has("bowtie") and by_shape.has("hex_s") and by_shape.has("hex_l"), str(by_shape))
	_check("past the line: the pips count the ships alive", pips_ok)
	var rec_a: Array = []
	for it: Array in layer.items():
		if str(it[4]) == "chevron" and int(it[3]) == team and int(it[5]) == 3:
			rec_a = it
	_check("past the line: the three-ship squadron shows three lit pips of three", not rec_a.is_empty() and int(rec_a[6]) == 3 and int(rec_a[5]) == 3, str(rec_a))
	_check("past the line: nothing is selected, so no icon is marked", layer.items().all(func(it: Array) -> bool: return not bool(it[7])))
	hud.overlay.set_selection([sq_a.id] as Array[int], false)
	await _frames(3)
	await _shot("icons_3_selected")
	var marked := 0
	for it: Array in layer.items():
		if bool(it[7]):
			marked += 1
	_check("past the line: the selected squadron is marked (and only it)", marked == 1, str(marked))
	hud.overlay.clear_selection()

	# One ship of a squadron dies: one pip goes dim, the icon stays.
	var lost_uid: int = sq_a.member_uids.pop_back()
	await _frames(3)
	rec_a = []
	for it: Array in layer.items():
		if str(it[4]) == "chevron" and int(it[3]) == team and int(it[6]) == 3:
			rec_a = it
	_check("a ship lost: the squadron's icon stays with two lit pips", not rec_a.is_empty() and int(rec_a[5]) == 2, str(rec_a))
	sq_a.member_uids.append(lost_uid)

	# The gap: a view between 14,400 and 16,000 keeps what it was.
	await _view(15200.0)
	_check("the gap: on stays on at 15,200", IconLayer.active)
	await _view(14000.0)
	_check("the gap: below 14,400 it goes off", not IconLayer.active)
	_check("the gap: the pictures come back", vis_a != null and vis_a.visible)
	await _view(15200.0)
	_check("the gap: off stays off at 15,200", not IconLayer.active)
	_check("the gap: decide() agrees (16,000 on, 14,399 off, in between as it was)", IconLayer.decide(16000.0, false, 16000.0) and not IconLayer.decide(14399.0, true, 16000.0) and IconLayer.decide(15000.0, true, 16000.0) and not IconLayer.decide(15000.0, false, 16000.0))

	# The setting: held between 11,000 and 30,000, in steps of 1,000; a line moved out makes the icons wait.
	IconLayer.set_line(5000, false)
	_check("setting: below the range is held at 11,000", IconLayer.line_w == 11000, str(IconLayer.line_w))
	IconLayer.set_line(99999, false)
	_check("setting: above the range is held at 30,000", IconLayer.line_w == 30000, str(IconLayer.line_w))
	IconLayer.set_line(16400, false)
	_check("setting: a value is rounded to a step", IconLayer.line_w == 16000, str(IconLayer.line_w))
	_check("setting: the range is the design's 11,000 to 30,000", int(RtsUiCalls.ICON_VIEW_RANGE[0]) == 11000 and int(RtsUiCalls.ICON_VIEW_RANGE[1]) == 30000)
	IconLayer.set_line(30000, false)
	await _view(20000.0)
	_check("setting: with the line at 30,000 a 20,000 view shows no icons", not IconLayer.active)
	IconLayer.set_line(11000, false)
	await _view(12000.0)
	_check("setting: with the line at 11,000 a 12,000 view shows icons", IconLayer.active)
	IconLayer.set_line(16000, false)
	await _view(10000.0)
	_check("setting: back at 16,000 a 10,000 view shows none", not IconLayer.active and layer.items().is_empty())

	# Every hull has a shape; no shape is a reserved one.
	var ok := true
	for h: String in Ships.ORDER:
		if not IconLayer.SHAPES.has(IconLayer.shape_of(h)) or not HullTables.ICON_SHAPES.has(h):
			ok = false
	_check("every hull has a shape", ok)
	var reserved_free := true
	for name: String in IconLayer.SHAPES:
		if name in ["disc", "triangle", "square", "diamond"]:
			reserved_free = false
	_check("no class shape is a reserved one (disc, triangle, square, diamond)", reserved_free)
	_check("the strike craft share the chevron, the bomber is a bow-tie, the corvettes a plus, the frigates a short hexagon", IconLayer.shape_of("scout") == "chevron" and IconLayer.shape_of("lance") == "chevron" and IconLayer.shape_of("bomber") == "bowtie" and IconLayer.shape_of("support") == "plus" and IconLayer.shape_of("ion") == "hex_s")
	_check("the destroyer and the battlecruiser have the two long hexagons", IconLayer.shape_of("destroyer") == "hex_l" and IconLayer.shape_of("battlecruiser") == "hex_xl")
	_finish()


func _finish() -> void:
	# Leave the camera and the layer as a match would have them.
	IconLayer.active = false
	print("icon_layer_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()
