extends Node
## WHAT THIS IS: the check of the camera-return flash (T-125, F40a): the outline of your own ship flashes white once when the
## camera comes back to it, and the flash never touches the match.
##
## HOW IT WORKS: it waits until the human pilot's ship is flying, then:
##   1. five Space taps within one second give one pulse (the camera is moved away before each tap, so only the one-a-second
##      limit holds the other four back); a tap after the gap gives the next one;
##   2. a Space tap while the ship is centred gives none; holding Space gives none after the first;
##   3. the camera's jump to the ship at launch (the pilot's launch step) gives one;
##   4. the Centre button's latch turned on (the mouse route) gives one, and staying on gives no more;
##   5. the hit flash wins: with the ship hit, the outline and the glow are the hit flash's, not the return flash's;
##   6. with the setting off (Game.return_flash) a tap, the launch jump and the latch give none;
##   7. the look: white (never the team colour), 5 pixels wide at the start, back to normal after 0.45 s, a glow for the first
##      0.15 s only, one more step of the kept picture at each step; no pulse for a ship that is not the human's;
##   8. no field of the Ship changes when a pulse starts (the flash lives in the camera rig and the drawing, never the simulation);
##   9. a paused match still shows the pulse (the kept picture of the hull is drawn again at each step while paused);
##  10. the numbers are in FlashTable.RETURN_FLASH and its row says one pulse a second at most.
## It ends with "return_flash_check: N failures" (0 = all good) and quits; after 90 s of real time "return_flash_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=return_flash_check
##
## WHO USES IT: main.gd loads it for --test=return_flash_check. It presses the Space action (Input.action_press) and reads
## CameraRig, ShipVisual and Game.return_flash; it changes nothing else (it puts back what it moves).

## The running match (set by setup()).
var world: World
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 90 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 90000:
		print("return_flash_check: timeout")
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
	var cam := world.camera
	await _frames(3)
	var ship := cam.followed()
	_expect(ship != null, "start: the human's ship is flying")
	var vis := ship.get_node_or_null("Visual") as ShipVisual
	_expect(vis != null, "the ship has its picture node")
	if ship == null or vis == null:
		_finish()
		return
	_expect(Game.return_flash, "the setting is on by default")
	_expect(world.human_role == "pilot", "the seat is a pilot's")
	var gap_ms := int(FlashTable.RETURN_FLASH["min_gap_ms"])
	var steps := int(FlashTable.RETURN_FLASH["steps"])
	# Step 10 first: the numbers and the table row.
	_expect(is_equal_approx(float(FlashTable.RETURN_FLASH["secs"]), 0.45) and is_equal_approx(float(FlashTable.RETURN_FLASH["width"]), 5.0) and is_equal_approx(float(FlashTable.RETURN_FLASH["glow_alpha"]), 0.35) and is_equal_approx(float(FlashTable.RETURN_FLASH["glow_secs"]), 0.15) and gap_ms == 1000 and is_equal_approx(float(FlashTable.RETURN_FLASH["centre_frac"]), 0.15), "the tunables are the design's numbers")
	var row := FlashTable.row_for("scripts/camera/camera_rig.gd")
	_expect(not row.is_empty() and String(row["rate"]) == "per event" and int(row["min_gap_ms"]) >= 334, "the flash table has the camera return row, a gap of at least 334 ms")
	# Step 1: five taps in a second, the camera away from the ship each time.
	_reset(cam, vis)
	var pulses := 0
	var last := vis._return_ms
	for i in 5:
		_away(cam, ship)
		await _tap()
		if vis._return_ms != last:
			pulses += 1
			last = vis._return_ms
	_expect(pulses == 1, "five Space taps within one second give one pulse (%d)" % pulses)
	# After the gap the next tap gives the next pulse (move the clock back instead of waiting).
	cam._flash_ms -= gap_ms + 100
	_away(cam, ship)
	await _tap()
	_expect(vis._return_ms != last, "a tap after the one-second gap gives a pulse")
	# Step 2: a tap while centred gives none; holding gives none after the first.
	_reset(cam, vis)
	_centre(cam, ship)
	await _tap()
	_expect(vis._return_ms == -100000, "a Space tap while the ship is centred gives no pulse")
	_reset(cam, vis)
	_away(cam, ship)
	Input.action_press("center_on_ship")
	await _frames(1)
	var first := vis._return_ms
	cam._flash_ms -= gap_ms + 100
	await _frames(20)
	var held_same := vis._return_ms == first
	Input.action_release("center_on_ship")
	await _frames(2)
	_expect(first != -100000 and held_same, "holding Space gives the one pulse of the press and no more")
	# Step 3: the launch jump gives one.
	_reset(cam, vis)
	_away(cam, ship)
	cam._was_flying = false
	await _frames(2)
	_expect(vis._return_ms != -100000, "the camera's jump to the ship at launch gives a pulse")
	# Step 4: the Centre button's latch (the mouse route) gives one when it turns on, and no more while it stays on.
	_reset(cam, vis)
	_away(cam, ship)
	cam.centre_latched = true
	await _frames(2)
	var latched := vis._return_ms
	cam._flash_ms -= gap_ms + 100
	await _frames(20)
	_expect(latched != -100000 and vis._return_ms == latched, "the Centre button's latch gives one pulse and no more while it stays on")
	cam.centre_latched = false
	await _frames(2)
	# Step 5: the hit flash wins.
	_reset(cam, vis)
	vis._return_ms = Time.get_ticks_msec()
	var edge := Palette.team(ship.team)
	var plain: Array = vis.outline_after_return(edge, 2.2, 0.0)
	var hit_look: Array = vis.outline_after_return(edge, 2.2, Palette.HIT_FLASH)
	_expect((plain[0] as Color).is_equal_approx(Palette.ICE) and is_equal_approx(float(plain[1]), 5.0), "at the start the outline is ICE white and 5 pixels wide, whatever the team colour")
	_expect((hit_look[0] as Color) == edge and is_equal_approx(float(hit_look[1]), 2.2), "with the hit flash on, the outline is left to the hit flash")
	var flash_was := ship.flash
	ship.flash = 0.05
	_expect(is_zero_approx(vis.glow_alpha_now()), "with the hit flash on, the glow is not shown")
	ship.flash = 0.0
	vis._return_ms = Time.get_ticks_msec()
	_expect(vis.glow_alpha_now() > 0.0, "with no hit, the glow shows at the start")
	ship.flash = flash_was
	# Step 7: the look over time.
	var now := Time.get_ticks_msec()
	vis._return_ms = now
	var q0 := vis._return_q()
	vis._return_ms = now - 200
	var q200 := vis._return_q()
	vis._return_ms = now - 500
	var q500 := vis._return_q()
	_expect(q0 == steps and q200 > 0 and q200 < q0 and q500 == 0, "the outline eases back in steps and is normal after 0.45 s (%d, %d, %d of %d)" % [q0, q200, q500, steps])
	vis._return_ms = now - 100
	var g100 := vis.glow_alpha_now()
	vis._return_ms = now - 200
	var g200 := vis.glow_alpha_now()
	_expect(g100 > 0.0 and g100 < 0.35 and g200 == 0.0, "the glow is on for the first 0.15 s only (%.3f, %.3f)" % [g100, g200])
	vis._return_ms = now - 500
	var done: Array = vis.outline_after_return(edge, 2.2, 0.0)
	_expect((done[0] as Color) == edge and is_equal_approx(float(done[1]), 2.2), "after 0.45 s the outline is the normal one")
	# Not the human's ship: no pulse at all.
	var other: ShipVisual = null
	for u: Unit in world.units:
		if u is Ship and u != ship and u.alive:
			var ov := u.get_node_or_null("Visual") as ShipVisual
			if ov != null:
				other = ov
				break
	if other != null:
		other.is_human = false
		other._return_ms = Time.get_ticks_msec()
		_expect(other._return_q() == 0 and is_zero_approx(other.glow_alpha_now()), "another pilot's ship never flashes")
		other._return_ms = -100000
	# Step 8: no Ship field changes when a pulse starts.
	_reset(cam, vis)
	var before := _fields(ship)
	cam.pulse_return()
	var after := _fields(ship)
	_expect(vis._return_ms != -100000 and before == after, "a pulse changes no field of the Ship (%d fields)" % before.size())
	# Step 9: a paused match shows the pulse: the kept picture of the hull is keyed on the step and drawn again.
	_reset(cam, vis)
	get_tree().paused = true
	cam.pulse_return()
	var key0 := vis._hull.bits >> 40
	await _frames(6)
	var key1 := vis._hull.bits >> 40
	get_tree().paused = false
	_expect(vis.return_active(), "the pulse is running while paused")
	_expect(key1 > 0 and key1 != key0 or key0 > 0, "while paused the hull's kept picture was keyed on the pulse's step (%d -> %d)" % [key0, key1])
	# Step 6: with the setting off, none.
	Game.return_flash = false
	_reset(cam, vis)
	_away(cam, ship)
	await _tap()
	var off_tap := vis._return_ms == -100000
	cam._was_flying = false
	await _frames(2)
	var off_launch := vis._return_ms == -100000
	cam.centre_latched = true
	await _frames(2)
	var off_latch := vis._return_ms == -100000
	cam.centre_latched = false
	Game.return_flash = true
	_expect(off_tap and off_launch and off_latch, "with the setting off the tap, the launch jump and the latch give no pulse")
	_reset(cam, vis)
	_finish()


## The summary line, and quit.
func _finish() -> void:
	print("return_flash_check: %d failures" % failures)
	get_tree().quit()


## Forget every pulse and the camera's one-a-second memory.
func _reset(cam: CameraRig, vis: ShipVisual) -> void:
	vis._return_ms = -100000
	cam._flash_ms = -100000
	Input.action_release("center_on_ship")
	cam.centre_latched = false


## Put the camera far from the ship (more than 15% of the view's width): it stays free there.
func _away(cam: CameraRig, ship: Ship) -> void:
	cam.free = true
	cam.global_position = ship.global_position + Vector2(4000.0, 0.0)
	cam._free_pos = cam.global_position
	cam._latch_was = cam.centre_latched


## Put the camera on the ship.
func _centre(cam: CameraRig, ship: Ship) -> void:
	cam.free = true
	cam.global_position = ship.global_position
	cam._free_pos = cam.global_position


## Tap Space: press it, let a frame pass, let go. (The press is made right after a frame starts, before the camera's own frame.)
func _tap() -> void:
	Input.action_press("center_on_ship")
	await _frames(1)
	Input.action_release("center_on_ship")
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
