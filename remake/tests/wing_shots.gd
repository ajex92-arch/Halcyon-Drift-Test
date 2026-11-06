extends Node
## WHAT THIS IS: the picture tour of the pilot's wing. It saves the pictures the user is shown: the four shapes
## of a wing on a straight lane for both teams (at the play zoom and close), the two guards (a Destroyer and the
## mothership) the same way, the HUD with the wing strip in its states, the order wheel, a refusal pop-up, the
## attack and guard brackets, the held-key lines and rings, and the start screen with its two wing switches.
## It is for people to look at, not a pass/fail check.
##
## HOW IT WORKS: setup() reads the options and starts one coroutine. --part picks what to photograph:
## "shapes" and "guards" (a spectator match: the test makes a leader pilot for each team and gives it a wing),
## "hud" (a human pilot with the test wing: --role=pilot --test-wing), "start" (the start screen's scene, made
## here). Every picture freezes the match, puts the camera where it is wanted (--view units across the picture),
## waits for the frame to draw and saves the viewport; then the match goes on. The leader is flown by a small
## scripted controller (tests/wing_probe.gd's Scripted) so the wing has something to follow.
##
## HOW TO RUN IT (needs a window; park it off the screen; start it with APPDATA pointing at an empty scratch folder
## because the start screen reads and a toggle writes the remembered settings):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto
##       --all-ai --no-pilots --no-admiral-ai --no-jungle --seed=7 --test=wing_shots --part=shapes --shots=<dir>
##   (hud: --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --no-jungle --test-wing --part=hud;
##    start: --auto --part=start --settings-check=<marker>, with APPDATA pointing at an empty folder whose name holds the marker)
## --view=N is how many world units fit across a "play" picture (default 2400); a "close" picture is 1100. The HUD part shows 2400 (--hud-near) or 3600 (--hud-view).
##
## WHO USES IT: main.gd loads it for --test=wing_shots; the lead and builders run it through the windowed queue.

## The test controller of the scripted leader (the probe's).
const Probe := preload("res://tests/wing_probe.gd")
## Where a straight run starts for the Aurelian team (west toward its mothership) and for the Vhorr team.
const START := [Vector2(19000.0, 15000.0), Vector2(21500.0, 15000.0)]
## The heading of that run for each team (radians).
const HEADING := [PI, 0.0]
## The cruise speed of the leader (world units a second): slow enough for the Bomber to keep its place.
const CRUISE := 260.0
## How many world units fit across the mothership guard picture: wide enough for both flank places (570 abeam) and the one astern.
const MS_VIEW := 3000.0
## How many world units fit across a close picture.
const CLOSE_VIEW := 1100.0

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## What to photograph (--part).
var part := "shapes"
## How wide the "play" pictures are, in world units (--view).
var view_w := 2400.0
## Pictures saved so far.
var taken := 0
## The caption drawn over each picture.
var caption: Label
## How many ships were made here (for their names).
var _made := 0


## Main calls this once the match is built: read the options, add the caption layer, free the camera and start.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	part = str(Game.opt("part", "shapes"))
	view_w = float(Game.opt("view", 2400.0))
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24, 96)
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	caption.visible = false
	layer.add_child(caption)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.camera.free = true
	world.minion_director.next_wave = INF
	_run()


## Wait for `n` ticks of the World.
func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Take one picture named `file` (without the extension) with the camera at `at`, `width` world units across, and
## `text` as its caption, the subject `lower` pixels below the middle (so the top panel does not cover it). The match
## stands still while the picture is made.
func _shoot(file: String, at: Vector2, width: float, text: String, lower: float = 60.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	world.set_physics_process(false)
	world.camera.set_process(false)
	var z: float = get_viewport().get_visible_rect().size.x / width
	world.camera.global_position = at - Vector2(0.0, lower / z)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	caption.text = text
	caption.visible = true
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(file + ".png"))
	taken += 1
	print("shot ", file)
	caption.visible = false
	world.camera.set_process(true)
	world.set_physics_process(true)


## The whole tour.
func _run() -> void:
	await _ticks(2)
	match part:
		"shapes":
			await _shapes()
		"guards":
			await _guards()
		"hud":
			await _hud()
		"start":
			await _start()
	print("wing_shots: done %d pictures" % taken)
	get_tree().quit()


## A leader pilot of `team` flying a Fighter with a Scout, a Fighter and a Bomber behind it, standing at the start of
## its straight run. Returns [pilot, ship, controller, lead record].
func _make_leader(team: int) -> Array:
	var p := PilotProfile.new("Lead%d" % team, team, 0, false)
	p.role = "mid"
	p.hull_id = "fighter"
	world.profiles.append(p)
	var recs := Squads.make_wing(world, p, PackedStringArray(["scout", "fighter", "bomber"]))
	var ship := world.launch(p)
	var ctl := Probe.Scripted.new()
	ship.controller = ctl
	var lead := recs[0]
	_place(ship, lead, team, ctl)
	return [p, ship, ctl, lead]


## Put the leader of `team` and its wing at the start of the run, heading along it, at a cruise.
func _place(ship: Ship, lead: Squad, team: int, ctl: Object) -> void:
	ship.global_position = START[team]
	ship.rotation = HEADING[team]
	ship.velocity = Vector2.from_angle(HEADING[team]) * CRUISE
	ctl.heading = HEADING[team]
	ctl.cruise = CRUISE
	lead.engine["hs"] = HEADING[team]
	lead.engine["hs_tick"] = world.tick_count
	var s := SquadEngine.spacing(ship.radius)
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		var crew := Squads.crew_of(world, rec)
		if crew != null and crew.ship != null and is_instance_valid(crew.ship):
			crew.ship.global_position = SquadEngine.slot_target(ship.global_position, ship.velocity, HEADING[team], lead.formation, rec.slot_index, s)
			crew.ship.rotation = HEADING[team]
			crew.ship.velocity = ship.velocity


## Bring the wingmen of `lead` to the leader `ship` (when the leader has been moved far away, so the picture does not wait
## for a long flight).
func _gather(ship: Ship, lead: Squad) -> void:
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		var crew := Squads.crew_of(world, rec)
		if crew != null and crew.ship != null and is_instance_valid(crew.ship):
			crew.ship.global_position = ship.global_position + Vector2(0.0, 120.0 * float(rec.slot_index + 1))
			crew.ship.velocity = Vector2.ZERO


## Put the wingmen of `lead` in their places around the leader `ship` after it was moved to the start of the run (the wing
## would otherwise still be flying over from the mothership), heading and speed as the leader's.
func _form_up(ship: Ship, lead: Squad, team: int) -> void:
	lead.engine["hs"] = HEADING[team]
	lead.engine["hs_tick"] = world.tick_count
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		var crew := Squads.crew_of(world, rec)
		if crew != null and crew.ship != null and is_instance_valid(crew.ship):
			crew.ship.global_position = _slot_of(ship, lead, rec.slot_index)
			crew.ship.rotation = HEADING[team]
			crew.ship.velocity = ship.velocity


## The box round a group: the leader and the wingmen that fly.
func _box(ship: Ship, lead: Squad) -> Rect2:
	var lo := ship.global_position
	var hi := ship.global_position
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		var crew := Squads.crew_of(world, rec)
		if crew != null and crew.ship != null and is_instance_valid(crew.ship):
			lo = Vector2(minf(lo.x, crew.ship.global_position.x), minf(lo.y, crew.ship.global_position.y))
			hi = Vector2(maxf(hi.x, crew.ship.global_position.x), maxf(hi.y, crew.ship.global_position.y))
	return Rect2(lo, hi - lo)


## The width of a close picture of the group: CLOSE_VIEW, or more when the group is taller than the picture (the
## Line and the Loose shape), so no wingman is cut off at the edge.
func _close_width(box: Rect2) -> float:
	return maxf(CLOSE_VIEW, maxf((box.size.y + 200.0) * 16.0 / 9.0, box.size.x + 300.0))


## Remove a team's leader and wing quietly (so the next team has the lane to itself).
func _clear(group: Array) -> void:
	for rec: Squad in Squads.wing_records(world, (group[3] as Squad).wing_id):
		var crew := Squads.crew_of(world, rec)
		if crew != null and crew.ship != null and is_instance_valid(crew.ship):
			world.combat.kill_silently(crew.ship)
	if is_instance_valid(group[1]):
		world.combat.kill_silently(group[1])


## The four shapes on a straight lane for both teams, at the play zoom and close.
func _shapes() -> void:
	for team in 2:
		var g := _make_leader(team)
		var ship: Ship = g[1]
		var lead: Squad = g[3]
		for f in Formations.COUNT:
			# The order writes the shape to every record of the wing (a record's own field is what its brain reads).
			SquadOrders.send(world, SquadOrders.gesture(world, g[0], "formation", f))
			await _ticks(2)
			_place(ship, lead, team, g[2])
			await _ticks(420)
			var shape_name := Formations.formation_name(f).to_lower()
			var side := "aurelian" if team == 0 else "vhorr"
			await _shoot("wing_%s_%s_play" % [shape_name, side], _box(ship, lead).get_center(), view_w, "%s, %s, play zoom" % [Formations.formation_name(f), side])
			await _shoot("wing_%s_%s_close" % [shape_name, side], _box(ship, lead).get_center(), _close_width(_box(ship, lead)), "%s, %s, close" % [Formations.formation_name(f), side])
		_clear(g)
		await _ticks(10)


## The two guards (a Destroyer and the mothership), both teams, at the play zoom and close.
func _guards() -> void:
	for team in 2:
		var g := _make_leader(team)
		var ship: Ship = g[1]
		var lead: Squad = g[3]
		var side := "aurelian" if team == 0 else "vhorr"
		# A Destroyer ward of the same team, standing still across the lane.
		var wp := PilotProfile.new("Ward%d" % team, team, 1, false)
		wp.role = "mid"
		wp.hull_id = "destroyer"
		world.profiles.append(wp)
		var ward := world.launch(wp)
		var wctl := Probe.Scripted.new()
		ward.controller = wctl
		wctl.heading = HEADING[team]
		ward.global_position = START[team] + Vector2.from_angle(HEADING[team]) * 900.0 + Vector2(0.0, 700.0)
		ward.rotation = HEADING[team]
		ward.velocity = Vector2.ZERO
		_place(ship, lead, team, g[2])
		(g[2] as Object).set("cruise", 0.0)
		ship.velocity = Vector2.ZERO
		await _ticks(30)
		var gesture := SquadOrders.gesture(world, g[0], "guard", 0, ward.global_position)
		SquadOrders.send(world, gesture)
		await _ticks(1500)
		# The camera sits 250 astern of the ward, so the places behind it clear the minimap and the top panel.
		var astern_at := ward.global_position - Vector2.from_angle(ward.rotation) * 250.0
		await _shoot("wing_guard_destroyer_%s_play" % side, astern_at, view_w, "Guard on a Destroyer, %s, play zoom" % side)
		await _shoot("wing_guard_destroyer_%s_close" % side, astern_at, CLOSE_VIEW, "Guard on a Destroyer, %s, close" % side)
		# The mothership, with the leader beside it.
		var ms := world.mothership(team)
		ship.global_position = ms.global_position + Vector2.from_angle(ms.rotation) * 1500.0
		ship.velocity = Vector2.ZERO
		_gather(ship, lead)
		var gesture2 :=SquadOrders.gesture(world, g[0], "guard", 0, ms.global_position)
		SquadOrders.send(world, gesture2)
		await _ticks(1500)
		await _shoot("wing_guard_mothership_%s_play" % side, ms.global_position, MS_VIEW, "Guard on the mothership, %s, play zoom" % side)
		await _shoot("wing_guard_mothership_%s_close" % side, ms.global_position.lerp(_wingman(lead, 0).global_position, 0.6), CLOSE_VIEW, "Guard on the mothership, %s, close" % side)
		world.combat.kill_silently(ward)
		_clear(g)
		await _ticks(10)


## The HUD with the wing: the strip in its states, the wheel, a refusal pop-up, the brackets, the held-key lines.
func _hud() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	var h := world.human
	if hud == null or h == null:
		print("wing_shots: no HUD or no human pilot (run with --role=pilot --force-hud or in a window)")
		return
	h.credits = 5000.0
	h.buy_hull("fighter", world.teams[h.team])
	var ship := world.launch(h)
	if hud.hangar != null:
		hud.hangar.visible = false
	var team := h.team
	ship.global_position = START[team]
	ship.rotation = HEADING[team]
	ship.velocity = Vector2.from_angle(HEADING[team]) * CRUISE
	var lead := Squads.lead_record(world, h.team, h.slot)
	_form_up(ship, lead, team)
	var ahead := Vector2.from_angle(HEADING[team])
	var tag := "aurelian" if team == 0 else "vhorr"
	# Most pictures show the wing close (2,400 across); the ones with a far target or a trailing wingman show 3,600.
	var near := float(Game.opt("hud-near", 2400.0))
	var view := float(Game.opt("hud-view", 3600.0))
	await _ticks(300)
	await _hud_shot(hud, ship, "hud_strip_in_slot_%s" % tag, near, "Wing strip: all in slot")
	# One wingman catching up: the Bomber is put far behind.
	var bomber := _wingman(lead, 2)
	bomber.global_position -= ahead * 900.0
	await _ticks(45)
	await _hud_shot(hud, ship, "hud_strip_catching_up_%s" % tag, view, "Wing strip: one catching up")
	bomber.global_position = _slot_of(ship, lead, 2)
	# An enemy ahead: attack it (brackets and the confirm pop-up).
	var foe_profile := PilotProfile.new("Foe", 1 - team, 1, false)
	foe_profile.role = "mid"
	foe_profile.hull_id = "fighter"
	world.profiles.append(foe_profile)
	var foe := world.launch(foe_profile)
	foe.global_position = ship.global_position + ahead * 1500.0 + Vector2(0.0, -400.0)
	foe.velocity = Vector2.ZERO
	foe.controller = Probe.Scripted.new()
	await _ticks(90)
	hud.wing_command("attack", 0, foe.global_position)
	await _ticks(20)
	await _hud_shot(hud, ship, "hud_attack_brackets_%s" % tag, view, "An attack stands: brackets, border, pop-up")
	# A hurt wingman.
	var fighter := _wingman(lead, 1)
	fighter.hull = fighter.hull_max * 0.2
	await _ticks(10)
	await _hud_shot(hud, ship, "hud_strip_hurt_%s" % tag, near, "Wing strip: a hurt wingman (danger colour and triangle)")
	# The wheel open, with the held-key marks.
	hud.wing_wheel.open_at(Vector2(640.0, 330.0), foe.global_position)
	await _ticks(2)
	await _hud_shot(hud, ship, "hud_wheel_open_%s" % tag, near, "The order wheel (held X)")
	hud.wing_wheel.close()
	# A refusal.
	hud.wing_command("guard", 0, ship.global_position + Vector2(0.0, 6000.0))
	await _ticks(2)
	await _hud_shot(hud, ship, "hud_refusal_%s" % tag, near, "A refusal: danger colour and triangle")
	# X held without the wheel: the lines and rings.
	world.wheel_hold = true
	await _ticks(5)
	await _hud_shot(hud, ship, "hud_x_held_marks_%s" % tag, near, "X held: lines to the leader and rings at the places")
	world.wheel_hold = false
	# A guard on a Destroyer of ours: brackets around the ward.
	var wp := PilotProfile.new("Ward", team, 2, false)
	wp.role = "mid"
	wp.hull_id = "destroyer"
	world.profiles.append(wp)
	var ward := world.launch(wp)
	ward.global_position = ship.global_position + ahead * 900.0 + Vector2(0.0, 600.0)
	ward.velocity = Vector2.ZERO
	ward.controller = Probe.Scripted.new()
	await _ticks(60)
	hud.wing_command("guard", 0, ward.global_position)
	await _ticks(300)
	await _hud_shot(hud, ship, "hud_guard_brackets_%s" % tag, view, "A guard stands: brackets round the ward, the wing in its pocket")
	# An empty place: a wingman is lost.
	world.combat.kill_silently(_wingman(lead, 0))
	await _ticks(30)
	await _hud_shot(hud, ship, "hud_strip_empty_slot_%s" % tag, near, "Wing strip: an empty place and the 'lost' pop-up")


## One HUD picture: the camera on the leader's ship, the HUD refreshed.
func _hud_shot(hud: Hud, ship: Ship, file: String, view: float, text: String) -> void:
	hud._refresh()
	await _shoot(file, ship.global_position, view, text, 0.0)


## The ship of wingman `index` of `lead`'s wing.
func _wingman(lead: Squad, index: int) -> Ship:
	for rec: Squad in Squads.wing_records(world, lead.wing_id):
		if rec.slot_index == index:
			var crew := Squads.crew_of(world, rec)
			if crew != null and crew.ship != null and is_instance_valid(crew.ship):
				return crew.ship
	return null


## Where slot `index` of the wing of `lead` is now.
func _slot_of(ship: Ship, lead: Squad, index: int) -> Vector2:
	return SquadEngine.slot_target(ship.global_position, ship.velocity, float(lead.engine.get("hs", ship.rotation)), lead.formation, index, SquadEngine.spacing(ship.radius))


## The start screen with its two wing switches, off and on.
func _start() -> void:
	var scene := load("res://scenes/ui/start_screen.tscn") as PackedScene
	var screen := scene.instantiate() as Control
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	layer.add_child(screen)
	await _ticks(10)
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("wing_start_screen_first_run.png"))
		taken += 1
		print("shot wing_start_screen_first_run")
	# A press of a toggle writes the remembered settings: only under a scratch folder that holds the marker.
	var marker := str(Game.opt("settings-check", ""))
	if marker == "" or not OS.get_user_data_dir().contains(marker):
		print("wing_shots: the toggles are not pressed; run with --settings-check=<marker> and APPDATA pointing at a folder whose name holds it")
		return
	screen.call("_toggle_test_wing")
	screen.call("_toggle_cpu_wings")
	if headless:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("wing_start_screen_toggled.png"))
	taken += 1
	print("shot wing_start_screen_toggled")
