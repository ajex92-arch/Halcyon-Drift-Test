extends Node
## WHAT THIS IS: the check of the pilot's flight cues (S1a): the ring set's parts and presets, the turn cues (heading tick, turn arc,
## stop-here ghost), the parallax dust, the pilot's follow camera on C, and the speed zoom. All of them are drawing and camera only: the
## check also proves none of them changes a field of the match.
##
## HOW IT WORKS: it waits until the human pilot's ship is flying, then runs the parts one after another:
##   1. the nine ring parts and the three presets are exactly the table (Full all nine; Compact without the route triangle, the
##      number and the turn arc; Minimal the shield arcs, the warning marks and the hit notch), and ShipRingParts.shown() follows the
##      preset and the single switches;
##   2. the turn cues: the arc radius and the stop distance are the numbers of the design; the cues draw with no script error, in
##      at most three drawing commands, and not at all below 12 units a second, not when only another ship is fast, and not for a
##      part the preset or a switch leaves out; drawing writes no field of the ship;
##   3. the dust: three layers of one drawing command each and no node for a speck, moving at 0.3, 0.6 and 0.9 of the camera, the same
##      specks for the same cells, hidden under reduced motion; and none of the new scripts uses a random number, a tween or a timer;
##   4. the pilot's camera: it starts free (PILOT_FOLLOW_DEFAULT false); C (the key, and the same click the mouse route makes) switches to
##      the follow camera and back and flashes the ship on the way in; the follow goal is the ship plus 0.3 of the way to the mouse (capped at
##      30% of half the view); the step is critically damped (no overshoot, the same at 30 and 60 frames a second, slower for heavy hulls); with Space held,
##      free or following, the ship stays on screen and the view never goes past the pilot's width; the pause menu has the Camera row;
##   5. the speed zoom: at top speed the shown zoom backs out by 12% (never more than 15%) and the wheel's own zoom is untouched; it is
##      never past the zoom-out limit; the switch (Game.speed_zoom) and reduced motion turn it off; at rest there is none;
## It ends with "flight_cues_check: N failures" (0 = all good) and quits; after 120 s of real time "flight_cues_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=flight_cues_check
##
## WHO USES IT: main.gd loads it for --test=flight_cues_check. It reads and sets Game's ring fields (in memory only: it calls no
## choose_ function, so it never writes the settings file) and puts back what it changes.

## The running match (set by setup()).
var world: World
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false
## Was the camera free when the check started (a pilot's camera starts free)?
var _started_free := false
## Where the human's ship was when the check started (the later parts bring it back here, so a long flight in one part does not
## leave it among the rocks or the turrets for the next).
var _start_pos := Vector2.ZERO


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 120 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 120000:
		print("flight_cues_check: timeout")
		get_tree().quit()
		return
	if get_tree().root.find_child("Hud", true, false) == null or world.camera == null:
		return
	if world.camera.followed() == null:
		return
	_started = true
	_run()


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(3)
	_started_free = world.camera.free
	_start_pos = world.camera.followed().global_position
	_parts()
	await _cues()
	await _dust()
	await _camera()
	await _lead_by_class()
	await _speed()
	await _dust_far()
	_finish()


## The summary line, and quit.
func _finish() -> void:
	print("flight_cues_check: %d failures" % failures)
	get_tree().quit()


## Part 1: the ring parts and the presets.
func _parts() -> void:
	var was_preset := Game.ring_preset
	var was_off := Game.ring_parts_off
	var all := ["shield_arcs", "hull_arc", "route_triangle", "warning_marks", "impact_number", "hit_notch", "heading_tick", "turn_arc", "ghost"]
	_expect(ShipRingParts.ids() == PackedStringArray(all), "the ring has the nine parts, in order")
	var want := [
		all,
		["shield_arcs", "hull_arc", "warning_marks", "hit_notch", "heading_tick", "ghost"],
		["shield_arcs", "warning_marks", "hit_notch"],
	]
	var names := ["Full", "Compact", "Minimal"]
	for p in 3:
		Game.ring_preset = p
		Game.ring_parts_off = PackedStringArray()
		var got := PackedStringArray()
		for id: String in all:
			if ShipRingParts.shown(id):
				got.append(id)
		_expect(got == PackedStringArray(want[p]), "%s shows exactly its parts (%s)" % [names[p], ", ".join(got)])
		_expect(ShipRingParts.preset_name(p) == names[p], "preset %d is called %s" % [p, names[p]])
	# The test run never reads the settings file, so what Game held at the start is the default: Full, nothing switched off.
	_expect(was_preset == ShipRingParts.PRESET_FULL and was_off.is_empty(), "the default is the Full preset with no part switched off")
	# A single switch removes one part of any preset.
	Game.ring_preset = ShipRingParts.PRESET_FULL
	Game.ring_parts_off = PackedStringArray(["ghost", "turn_arc"])
	_expect(not ShipRingParts.shown("ghost") and not ShipRingParts.shown("turn_arc") and ShipRingParts.shown("heading_tick"), "a part switched off one by one is hidden whatever the preset says")
	Game.ring_preset = ShipRingParts.PRESET_MINIMAL
	Game.ring_parts_off = PackedStringArray()
	_expect(not ShipRingParts.shown("ghost") and not ShipRingParts.shown("not_a_part"), "an unknown part is never shown, and a switch cannot add a part to a preset")
	# Out of range numbers count as Full.
	_expect(ShipRingParts.parts_of(7).size() == 9 and ShipRingParts.parts_of(-1).size() == 9, "an unknown preset number counts as Full")
	Game.ring_preset = was_preset
	Game.ring_parts_off = was_off


## Part 2: the turn cues.
func _cues() -> void:
	var ship := world.camera.followed()
	var hud := get_tree().root.find_child("Hud", true, false)
	var cues: TurnCues = null
	for c in hud.get_children():
		if c is TurnCues:
			cues = c
	_expect(cues != null and cues.cue_ship() == ship, "the HUD has the turn cues and they belong to the human's own ship")
	if cues == null or ship == null:
		return
	# The numbers of the design: radius = speed over the turn rate at that speed; stop distance = v squared over twice the braking
	# plus v times the engines' swing time; the ring is at least 24 pixels.
	_expect(is_equal_approx(TurnCues.turn_radius(300.0, 2.0, 0.5, 600.0), 200.0), "turn radius: 300 at turn 2, bleed 0.5, top speed 600 is 200")
	_expect(is_equal_approx(TurnCues.turn_radius(900.0, 2.0, 0.5, 600.0), 900.0 / (2.0 * 0.5)), "turn radius: past top speed the turn rate stops falling")
	_expect(TurnCues.turn_radius(100.0, 0.0, 0.0, 600.0) == 0.0, "turn radius: a ship that cannot turn has no arc")
	_expect(is_equal_approx(TurnCues.stop_distance(300.0, 100.0, 0.5), 600.0) and is_equal_approx(TurnCues.stop_distance(300.0, 100.0, 0.0), 450.0), "stop distance: v squared over twice the braking plus v times the swing time")
	_expect(TurnCues.stop_distance(300.0, 0.0, 0.0) == 0.0, "stop distance: a ship that cannot brake has no ghost")
	_expect(is_equal_approx(TurnCues.ring_px(10.0, 0.2), 24.0) and is_equal_approx(TurnCues.ring_px(200.0, 0.2), 48.0), "ring: at least 24 pixels, else the shield ring on screen plus 8")
	var was_preset := Game.ring_preset
	var was_off := Game.ring_parts_off
	var was_mouse: Variant = world.test_mouse
	Game.ring_preset = ShipRingParts.PRESET_FULL
	Game.ring_parts_off = PackedStringArray()
	var z := world.camera.zoom.x
	world.test_mouse = ship.global_position + Vector2(600.0, -300.0)
	# A speed whose stop mark lands on the screen: try a few until the ghost's place is within 40 to 450 pixels.
	var fast := 300.0
	for v: float in [60.0, 120.0, 240.0, 480.0]:
		var d := TurnCues.stop_distance(v, ship.f_brake, ship.f_brake_lag) * z
		if d > 40.0 and d < 450.0:
			fast = v
			break
	var vel := Vector2.from_angle(ship.rotation) * fast
	# Full: all three parts, never more than three drawing commands.
	await _hold(ship, vel)
	_expect(cues.visible and cues.drawn == 3, "Full at %.0f units a second draws all three parts (%d drawing commands, zoom %.3f)" % [fast, cues.drawn, z])
	# Below 12 units a second: nothing, and the node hides.
	await _hold(ship, vel.normalized() * 5.0)
	_expect(cues.drawn == 0 and not cues.visible, "below 12 units a second the cues draw nothing")
	# Only another ship is fast: nothing (the cues are the human's own).
	var other: Ship = null
	for s: Ship in world.ships:
		if s != ship and s.alive:
			other = s
			break
	if other != null:
		var other_was := other.velocity
		for i in 3:
			other.velocity = Vector2(500.0, 0.0)
			ship.velocity = Vector2(3.0, 0.0)
			await _frames(1)
		_expect(cues.drawn == 0 and not cues.visible, "another ship's speed never makes the cues draw")
		other.velocity = other_was
	# The presets and the single switches.
	var want := {ShipRingParts.PRESET_COMPACT: 2, ShipRingParts.PRESET_MINIMAL: 0}
	for p: int in want:
		Game.ring_preset = p
		await _hold(ship, vel)
		_expect(cues.drawn == int(want[p]), "%s draws %d of the three parts (%d)" % [ShipRingParts.preset_name(p), int(want[p]), cues.drawn])
	Game.ring_preset = ShipRingParts.PRESET_FULL
	for part: String in ["heading_tick", "turn_arc", "ghost"]:
		Game.ring_parts_off = PackedStringArray([part])
		await _hold(ship, vel)
		_expect(cues.drawn == 2, "with %s switched off, two parts are drawn (%d)" % [part, cues.drawn])
	Game.ring_parts_off = PackedStringArray()
	# Drawing writes nothing: with the match paused, no field of the ship changes over several drawn frames.
	ship.velocity = vel
	get_tree().paused = true
	var before := _fields(ship)
	for i in 4:
		cues.queue_redraw()
		await _frames(1)
	var after := _fields(ship)
	get_tree().paused = false
	_expect(before == after and cues.drawn >= 1, "drawing the cues changes no field of the ship (%d fields)" % before.size())
	Game.ring_preset = was_preset
	Game.ring_parts_off = was_off
	world.test_mouse = was_mouse


## Part 3: the parallax dust.
func _dust() -> void:
	var dust := world.get_node_or_null("SpaceDust") as SpaceDust
	_expect(dust != null and dust.get_child_count() == 3, "the world has the dust node with its three layers")
	if dust == null:
		return
	var cam := world.camera
	var ship := cam.followed()
	var was_free := cam.free
	cam.free = true
	cam.centre_latched = false
	var layers := SpaceDust.LAYERS
	_expect(is_equal_approx(float(layers[0]["factor"]), 0.3) and is_equal_approx(float(layers[1]["factor"]), 0.6) and is_equal_approx(float(layers[2]["factor"]), 0.9), "the layers follow 0.3, 0.6 and 0.9 of the camera")
	# Park the camera, let the dust catch up, then read: one drawing command for each layer, and still three child nodes.
	_park(cam, Vector2(9000.0, 6000.0))
	await _frames(3)
	var kids := dust.get_child_count()
	_expect(dust.visible and dust.drawn[0] == 1 and dust.drawn[1] == 1 and dust.drawn[2] == 1, "each layer draws its specks in one drawing command (%s)" % str(dust.drawn))
	var count0 := dust._specks[0].size() / 2
	_expect(count0 > 10, "a layer holds a few dozen specks on one screen (%d in the nearest-to-slowest layer)" % count0)
	# Move the camera: the layers slide at (1 - f) x the move in the world, so a speck is at f x the move on the screen.
	var centre0 := cam.get_screen_center_position()
	var pos0: Array[Vector2] = []
	for i in 3:
		pos0.append(dust._sheets[i].position)
	var move := Vector2(1200.0, -700.0)
	_park(cam, cam.global_position + move)
	await _frames(3)
	var moved := cam.get_screen_center_position() - centre0
	var ok := moved.length() > 100.0
	for i in 3:
		var f := float(layers[i]["factor"])
		var shift: Vector2 = dust._sheets[i].position - pos0[i]
		ok = ok and shift.distance_to(moved * (1.0 - f)) < 0.5
		ok = ok and (moved - shift).distance_to(moved * f) < 0.5
	_expect(ok, "a camera move of %.0f units slides the layers by 0.7, 0.4 and 0.1 of it, so a speck moves 0.3, 0.6 and 0.9 across the screen" % moved.length())
	_expect(dust.get_child_count() == kids and dust.get_child_count() == 3, "moving the camera makes no new node: no node for a speck")
	# The same cells give the same specks, whatever happened between (no random number).
	var cells := Vector4i(2, 9, 3, 8)
	var a := SpaceDust.make_specks(1, cells, 1.0)
	var b := SpaceDust.make_specks(1, cells, 1.0)
	_expect(a == b and a.size() > 4 and SpaceDust.cell_hash(5, -3, 7) == SpaceDust.cell_hash(5, -3, 7) and SpaceDust.cell_hash(5, -3, 7) != SpaceDust.cell_hash(5, -2, 7), "the same cells give the same specks, and neighbouring cells differ")
	# Reduced motion turns the dust off (and back on).
	var was_reduced := Blink.reduced_motion
	Blink.reduced_motion = true
	await _frames(2)
	var off := not dust.visible
	Blink.reduced_motion = was_reduced
	await _frames(2)
	_expect(off and dust.visible == (not was_reduced), "with reduced motion the dust is hidden, and it comes back")
	# The new scripts hold no random number, tween, timer or animation player (the drawing rules).
	var rx := RegEx.new()
	rx.compile("randf|randi|RandomNumberGenerator|create_tween|create_timer|Tween|AnimationPlayer|GPUParticles|CPUParticles")
	var clean := true
	for path: String in ["res://scripts/world/space_dust.gd", "res://scripts/ui/turn_cues.gd", "res://scripts/data/ship_ring_parts.gd"]:
		var text := FileAccess.get_file_as_string(path)
		var code := ""
		for line in text.split("\n"):
			if not line.strip_edges().begins_with("#"):
				code += line + "\n"
		if rx.search(code) != null:
			clean = false
			print("  found in ", path)
	_expect(clean, "no new script uses a random number, a tween, a timer or a particle node")
	cam.free = was_free
	if ship != null:
		_park(cam, ship.global_position)


## Part 4: the pilot's follow camera, the lean, the critically damped step and the view limit.
func _camera() -> void:
	var cam := world.camera
	var ship := cam.followed()
	var hud := get_tree().root.find_child("Hud", true, false)
	var vis := ship.get_node_or_null("Visual") as ShipVisual
	_expect(not CameraRig.PILOT_FOLLOW_DEFAULT and _started_free and not Game.pilot_follow, "a pilot's camera starts free (the one constant PILOT_FOLLOW_DEFAULT is false)")
	var ahead := CameraRig.PILOT_AHEAD
	var settle := CameraRig.PILOT_SETTLE
	var heavier := true
	for i in 3:
		heavier = heavier and float(ahead[i + 1]) > float(ahead[i]) and float(settle[i + 1]) > float(settle[i])
	_expect(heavier, "heavier hulls look further ahead and settle more slowly")
	_expect(CameraRig.PILOT_LEAN >= 0.2 and CameraRig.PILOT_LEAN <= 0.5 and is_equal_approx(CameraRig.PILOT_LEAN_CAP, 0.30), "the lean is 0.2 to 0.5 of the way to the mouse, capped at 30% of half the view")
	# The step: no overshoot, the same at 30 and 60 frames a second, slower for heavy hulls.
	var goal := Vector2(1000.0, 0.0)
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var overshoot := false
	for i in 180:
		var st := CameraRig.pilot_step(pos, goal, vel, 0, 1.0 / 60.0)
		pos = st[0]
		vel = st[1]
		overshoot = overshoot or pos.x > goal.x + 0.001
	_expect(not overshoot and pos.distance_to(goal) < 1.0, "the step settles on the goal in 3 s without overshoot (%.2f left)" % pos.distance_to(goal))
	var pos30 := Vector2.ZERO
	var vel30 := Vector2.ZERO
	var pos60 := Vector2.ZERO
	var vel60 := Vector2.ZERO
	for i in 30:
		var a := CameraRig.pilot_step(pos60, goal, vel60, 1, 1.0 / 60.0)
		pos60 = a[0]
		vel60 = a[1]
	for i in 15:
		var b := CameraRig.pilot_step(pos30, goal, vel30, 1, 1.0 / 30.0)
		pos30 = b[0]
		vel30 = b[1]
	_expect(pos30.distance_to(pos60) < 3.0, "half a second at 30 and at 60 frames a second ends in the same place (%.2f apart)" % pos30.distance_to(pos60))
	var small := CameraRig.pilot_step(Vector2.ZERO, goal, Vector2.ZERO, 0, 0.2)[0] as Vector2
	var big := CameraRig.pilot_step(Vector2.ZERO, goal, Vector2.ZERO, 3, 0.2)[0] as Vector2
	_expect(small.x > big.x, "after 0.2 s a small craft's camera has gone further than a capital ship's")
	# C: the key and the click both switch, the ship flashes on the way in, and the pause menu has its row.
	var was_mouse: Variant = world.test_mouse
	var was_flash := Game.return_flash
	Game.return_flash = true
	_park(world.camera, ship.global_position)
	vis._return_ms = -100000
	cam._flash_ms = -100000
	await _key(KEY_C)
	_expect(not cam.free and cam.zoom_limited(), "C switches a pilot to the follow camera")
	_expect(vis._return_ms != -100000, "C into follow mode flashes the ship (the return flash works in every camera mode)")
	hud.router.click("center_camera")
	await _frames(2)
	_expect(cam.free, "the click the mouse route makes (the same one as C) switches back to the free camera")
	# The lean: the camera settles on ship + 0.3 of the way to the mouse.
	var view := cam.get_viewport_rect().size / cam.zoom.x
	var spot := ship.global_position
	world.test_mouse = spot + Vector2(1000.0, 0.0)
	await _key(KEY_C)
	await _still(ship, spot, 180)
	view = cam.get_viewport_rect().size / cam.zoom.x
	var want := spot + Vector2(300.0, 0.0)
	_expect(cam.global_position.distance_to(want) < 3.0, "following, the camera rests at the ship plus 0.3 of the way to the mouse (%.1f off)" % cam.global_position.distance_to(want))
	# A far mouse: the lean stops at 30% of half the view.
	world.test_mouse = spot + Vector2(0.0, 20000.0)
	await _still(ship, spot, 180)
	view = cam.get_viewport_rect().size / cam.zoom.x
	var lean_len := (cam.global_position - spot).length()
	var cap := minf(view.x * 0.5 * CameraRig.PILOT_LEAN_CAP, minf(view.x * CameraRig.PILOT_OFFSET_CAP, ship.vision_radius * CameraRig.PILOT_SIGHT_SHARE))
	_expect(absf(lean_len - cap) < 3.0, "a far mouse leans the camera by the cap, %.0f units (%.0f)" % [cap, lean_len])
	# Following at speed with a far mouse: the ship stays on the screen and the view never goes past the pilot's width.
	var fly := Vector2(900.0, 0.0)
	var off_screen := false
	var widest := 0.0
	for i in 240:
		spot += fly / 60.0
		ship.global_position = spot
		ship.velocity = fly
		await _frames(1)
		if i > 120:
			var v := cam.get_viewport_rect().size / cam.zoom.x
			var d := (ship.global_position - cam.global_position).abs()
			off_screen = off_screen or d.x > v.x * 0.5 or d.y > v.y * 0.5
			widest = maxf(widest, v.x)
	var limit := float(CameraRig.PILOT_VIEW_WIDTH[Rules.size_index(ship.size_class)]) * ZoomMaxFeature.factor()
	_expect(not off_screen, "following at 900 units a second with a far mouse, the ship stays on the screen")
	_expect(widest <= limit * 1.001, "the view never goes past the pilot's width (%.0f of %.0f)" % [widest, limit])
	# Space held in the follow camera: the same goal, the ship on the screen.
	Input.action_press("center_on_ship")
	off_screen = false
	for i in 120:
		spot += fly / 60.0
		ship.global_position = spot
		ship.velocity = fly
		await _frames(1)
		var v2 := cam.get_viewport_rect().size / cam.zoom.x
		var d2 := (ship.global_position - cam.global_position).abs()
		off_screen = off_screen or d2.x > v2.x * 0.5 or d2.y > v2.y * 0.5
	Input.action_release("center_on_ship")
	_expect(not off_screen and cam.get_viewport_rect().size.x / cam.zoom.x <= limit * 1.001, "Space held while following keeps the ship on the screen and the view inside the pilot's width")
	# A Space press in the follow camera while it already follows (the ship is off the middle only by the lean and the look-ahead, here
	# well past the flash's 15% box) gives no flash; a ship thrown far from the camera's goal still does.
	var zoom_was := cam.target_zoom
	cam.target_zoom = cam.get_viewport_rect().size.x / 2500.0
	for i in 150:
		spot += fly / 60.0
		ship.global_position = spot
		ship.velocity = fly
		world.test_mouse = spot + Vector2(0.0, 20000.0)
		await _frames(1)
	var box := cam.get_viewport_rect().size.x / cam.zoom.x * float(FlashTable.RETURN_FLASH["centre_frac"])
	var offset_now := (spot - cam.global_position).length()
	vis._return_ms = -100000
	cam._flash_ms = -100000
	spot += fly / 60.0
	ship.global_position = spot
	ship.velocity = fly
	world.test_mouse = spot + Vector2(0.0, 20000.0)
	Input.action_press("center_on_ship")
	await _frames(1)
	Input.action_release("center_on_ship")
	await _frames(1)
	_expect(offset_now > box and vis._return_ms == -100000, "a Space press while the camera already follows gives no flash although the ship is %.0f off the middle (the box is %.0f)" % [offset_now, box])
	vis._return_ms = -100000
	cam._flash_ms = -100000
	cam.global_position += Vector2(0.0, 6.0) * box
	Input.action_press("center_on_ship")
	await _frames(1)
	Input.action_release("center_on_ship")
	await _frames(1)
	_expect(vis._return_ms != -100000, "a Space press while the camera is far from where it settles still flashes the ship")
	cam.target_zoom = zoom_was
	await _still(ship, spot, 200)
	# Space held in the free camera: the lean applies there too.
	await _key(KEY_C)
	_expect(cam.free, "C switches the follow camera back to free")
	world.test_mouse = spot + Vector2(1000.0, 0.0)
	Input.action_press("center_on_ship")
	await _still(ship, spot, 180)
	var held_off := cam.global_position.distance_to(spot + Vector2(300.0, 0.0))
	Input.action_release("center_on_ship")
	_expect(held_off < 3.0, "Space held in the free camera leans the same way (%.1f off)" % held_off)
	# A tap leans not at all (the goal is the ship itself), a hold leans in after a moment: the goal as the camera works it out.
	var hold_was: float = cam._hold_t
	cam._hold_t = 0.1
	var tap_goal: Vector2 = cam._center_goal(ship)
	cam._hold_t = 0.6
	var hold_goal: Vector2 = cam._center_goal(ship)
	cam._hold_t = hold_was
	_expect(tap_goal.distance_to(spot) < 1.0 and hold_goal.distance_to(spot + Vector2(300.0, 0.0)) < 1.0, "a Space tap still centres exactly on the ship; a hold leans (%.1f, %.1f)" % [tap_goal.distance_to(spot), hold_goal.distance_to(spot + Vector2(300.0, 0.0))])
	# The pause menu's Camera row exists for the pilot (it is not pressed here: its button writes the settings file).
	var menu: PauseMenu = hud.pause_menu
	hud._toggle_pause_menu()
	menu = hud.pause_menu
	await _frames(2)
	var row_ok := menu != null and menu._camera_button != null and menu._camera_button.text == "Camera: Free"
	if menu != null and menu.active:
		menu.resume()
	await _frames(2)
	_expect(row_ok, "the pause menu has the pilot's Camera row (Camera: Free)")
	Game.return_flash = was_flash
	world.test_mouse = was_mouse
	ship.velocity = Vector2.ZERO


## Part 4b: the settled look-ahead of each size class. The ship of each class in turn flies at a steady speed with the mouse on it (no
## lean) in the follow camera; the camera must come to rest PILOT_AHEAD seconds of speed ahead, so the lead grows with the hull.
func _lead_by_class() -> void:
	var cam := world.camera
	var ship := cam.followed()
	var was_class := ship.size_class
	var was_mouse: Variant = world.test_mouse
	var was_free := cam.free
	ship.global_position = _start_pos
	ship.velocity = Vector2.ZERO
	var spot := _start_pos
	var v := 100.0
	var leads: Array[float] = []
	cam.free = false
	for idx in 4:
		ship.size_class = idx
		cam._follow_vel = Vector2.ZERO
		for i in 300:
			spot += Vector2(v, 0.0) / 60.0
			ship.global_position = spot
			ship.velocity = Vector2(v, 0.0)
			world.test_mouse = ship.global_position
			await _frames(1)
		var lead := (cam.global_position.x - spot.x) / v
		leads.append(lead)
		_expect(absf(lead - float(CameraRig.PILOT_AHEAD[idx])) < 0.04, "size class %d flying at %.0f u/s: the camera rests %.3f s ahead (the table says %.2f)" % [idx, v, lead, float(CameraRig.PILOT_AHEAD[idx])])
	_expect(leads[1] > leads[0] + 0.02 and leads[2] > leads[1] + 0.02 and leads[3] > leads[2] + 0.02, "the settled look-ahead grows with the size class (%s)" % str(leads))
	# The ship's flight numbers (top speed, boost cap) follow its size class: put the class back and let the match work them out again.
	ship.size_class = was_class
	ship.velocity = Vector2.ZERO
	await _frames(120)
	world.test_mouse = was_mouse
	cam.free = was_free
	cam._follow_vel = Vector2.ZERO
	_park(cam, ship.global_position)


## Part 5: the speed zoom.
func _speed() -> void:
	var cam := world.camera
	var ship := cam.followed()
	ship.global_position = _start_pos
	ship.velocity = Vector2.ZERO
	var spot := _start_pos
	var was_target := cam.target_zoom
	var was_speed := Game.speed_zoom
	var was_reduced := Blink.reduced_motion
	_expect(CameraRig.SPEED_ZOOM_OUT > 0.0 and CameraRig.SPEED_ZOOM_OUT <= CameraRig.SPEED_ZOOM_MAX and CameraRig.SPEED_ZOOM_MAX <= 0.15, "the speed zoom is a constant in the range 0 to 15% (12%)")
	_expect(Game.speed_zoom, "the speed zoom is on by default")
	_park(cam, spot)
	Blink.reduced_motion = false
	# A wheel zoom with room to back out: 3,000 units across.
	var vw := cam.get_viewport_rect().size.x
	cam.target_zoom = vw / 3000.0
	await _fly(ship, spot, Vector2.ZERO, 120)
	var top := ship.f_max * (ship.f_boost_cap if ship.can_boost else 1.0)
	var rest := cam.zoom.x / cam._base_zoom
	_expect(absf(rest - 1.0) < 0.001, "at rest the speed zoom does nothing (%.4f)" % rest)
	var target_before := cam.target_zoom
	await _fly(ship, spot, Vector2(top, 0.0), 240)
	var ratio := cam.zoom.x / cam._base_zoom
	_expect(absf(ratio - 1.0 / (1.0 + CameraRig.SPEED_ZOOM_OUT)) < 0.004, "at top speed the view backs out by 12%% (the zoom is %.4f of the wheel's)" % ratio)
	_expect(ratio >= 1.0 / 1.15 - 0.0001 and ratio < 1.0, "the speed zoom stays within 15%% (%.4f)" % ratio)
	_expect(cam.target_zoom == target_before and absf(cam._base_zoom - target_before) < 0.0005, "the wheel's own zoom is untouched by speed")
	# Half speed: about half the way.
	await _fly(ship, spot, Vector2(top * 0.5, 0.0), 240)
	var half := cam.zoom.x / cam._base_zoom
	_expect(half > ratio and half < 1.0 and absf(half - 1.0 / (1.0 + CameraRig.SPEED_ZOOM_OUT * 0.5)) < 0.004, "at half speed the view backs out by half as much (%.4f)" % half)
	# The off switch and reduced motion turn it off.
	Game.speed_zoom = false
	await _fly(ship, spot, Vector2(top, 0.0), 240)
	var off := cam.zoom.x / cam._base_zoom
	_expect(absf(off - 1.0) < 0.001, "with the switch off the view stays where the wheel put it (%.4f)" % off)
	Game.speed_zoom = true
	Blink.reduced_motion = true
	await _fly(ship, spot, Vector2(top, 0.0), 240)
	var calm := cam.zoom.x / cam._base_zoom
	Blink.reduced_motion = was_reduced
	_expect(absf(calm - 1.0) < 0.001, "with reduced motion the view stays where the wheel put it (%.4f)" % calm)
	# Never past the zoom-out limit: ask for the widest view, at top speed.
	cam.target_zoom = 0.0001
	await _fly(ship, spot, Vector2(top, 0.0), 240)
	var lim := cam.zoom_limits()
	_expect(cam.zoom.x >= lim.x - 0.000001, "at top speed the view still stops at the pilot's width limit (%.0f of %.0f units across)" % [vw / cam.zoom.x, vw / lim.x])
	cam.target_zoom = was_target
	Game.speed_zoom = was_speed
	ship.velocity = Vector2.ZERO


## Part 3b: the dust zoomed out over the whole map. It runs last, because it turns the match's human role to Admiral for a moment.
func _dust_far() -> void:
	var dust := world.get_node_or_null("SpaceDust") as SpaceDust
	var cam := world.camera
	var ship := cam.followed()
	if dust == null:
		return
	# Zoomed out over the whole map (an Admiral's free camera, which is not zoom-limited): the dust is hidden, draws nothing and makes no
	# cell window, however the camera moves; back at a pilot's zoom it draws as before.
	var was_role := world.human_role
	var was_target := cam.target_zoom
	await _frames(2)
	world.human_role = "admiral"
	cam.free = true
	cam.target_zoom = 0.0001
	_park(cam, Vector2(9000.0, 6000.0))
	await _frames(90)
	var whole := cam.get_viewport_rect().size.x / cam.zoom.x
	_expect(not cam.zoom_limited() and whole > 20000.0, "setup: the free Admiral camera shows the whole map (%.0f units across)" % whole)
	_expect(not dust.visible, "at the whole-map zoom the dust is hidden")
	var cells_before: Array[Vector4i] = dust._cells.duplicate()
	var steps_before: Array[int] = dust._steps.duplicate()
	for i in 6:
		_park(cam, Vector2(9000.0 + 3000.0 * float(i + 1), 6000.0 - 1500.0 * float(i)))
		await _frames(2)
	_expect(dust._cells == cells_before and dust._steps == steps_before, "at the whole-map zoom no cell window is rebuilt, however the camera moves")
	world.human_role = was_role
	cam.target_zoom = was_target
	_park(cam, Vector2(9000.0, 6000.0))
	await _frames(90)
	_expect(dust.visible and dust.drawn[0] == 1 and dust.drawn[1] == 1 and dust.drawn[2] == 1 and cam.zoom_limited(), "back at a pilot's zoom the dust draws as before (%s)" % str(dust.drawn))
	cam.free = true
	if ship != null:
		_park(cam, ship.global_position)


## Hold the ship at `spot` flying at `vel` for `n` frames (the match's own steps move it, so the place is put back each frame).
func _fly(ship: Ship, spot: Vector2, vel: Vector2, n: int) -> void:
	for i in n:
		ship.global_position = spot
		ship.velocity = vel
		await _frames(1)

## Hold the ship still at `spot` for `n` frames.
func _still(ship: Ship, spot: Vector2, n: int) -> void:
	for i in n:
		ship.global_position = spot
		ship.velocity = Vector2.ZERO
		await _frames(1)


## Press and let go of keyboard key `code` through the game's input path, then two drawn frames.
func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(2)

## Put the camera at `p` and keep it there (its goal too).
func _park(cam: CameraRig, p: Vector2) -> void:
	cam.free = true
	cam.global_position = p
	cam._free_pos = p

## Set the ship's velocity before each of a few frames, so the cues see it (the match's own steps may change it between frames).
func _hold(ship: Ship, vel: Vector2) -> void:
	for i in 4:
		ship.velocity = vel
		await _frames(1)


## Every script variable of `n` as a Dictionary name -> value (a copy, to compare before and after).
func _fields(n: Object) -> Dictionary:
	var out := {}
	for p: Dictionary in n.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			var v: Variant = n.get(String(p["name"]))
			out[String(p["name"])] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## Count a PASS or FAIL line for the check `what`.
func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
