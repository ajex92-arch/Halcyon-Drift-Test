extends Node
## WHAT THIS IS: the picture script of the team marks (T-126, Set 1, "Disc and Wedge"): a windowed run that saves the
## pictures the designer's sheet is matched against: the minimap at 80%, 100% and 140%, the world rings (HELD for Aurelian,
## HELD for Vhorr, CONTESTED), the hull bars with the kill feed's team names (a Vhorr kill and an Aurelian kill) and the
## scoreboard's headings. It only reads the match and makes a few ships and turrets of its own for the pictures.
## Without a window, or without a --shots folder, it prints what it would save and saves nothing (the ui_tour rule).
##
## HOW IT WORKS: setup() lists the pictures (PICTURES). Windowed with --shots, it freezes a real match (physics off
## between steps, as structure_shots does) and builds the states in three steps: a finished Aurelian turret at Top Jungle
## South (HELD), a finished Vhorr turret at Bottom Jungle South (HELD) and one Aurelian and one Vhorr pilot ship at Top
## Jungle North (CONTESTED); the match runs 20 ticks so the sites count who is inside. Then: the minimap pictures (the
## minimap cut out of the window and enlarged 3 times with no smoothing, so each pixel can be counted), the three rings,
## two kills (a Vhorr pilot shoots down an Aurelian ship and the reverse) with the picture of the hull bars and the feed, and
## the scoreboard held open; then (T-126b) the kill feed with its weapon icons, streak frame and name frame, and the five kinds
## of shot at the start zoom for both teams. Each picture is <name>.png in the --shots folder. It ends with "team_shapes_shots: 0 failures"
## (a picture that could not be taken counts as a failure).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/; park the window
## off the screen):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=pilot --bot=team --test=team_shapes_shots --shots=<dir>
##   godot --headless --path remake -- --auto --role=pilot --bot=team --test=team_shapes_shots   (lists the pictures only)
##
## WHO USES IT: main.gd loads it for --test=team_shapes_shots. It moves the World's CameraRig, sets Game.minimap_pct and puts
## it back, makes pilot ships, two turrets and two kills of its own, and shows the scoreboard through Hud._show_scoreboard().

## The pictures: [file name without .png, what it shows].
const PICTURES := [
	["minimap_80", "the minimap at 80% (the smallest step), enlarged 3 times, no smoothing"],
	["minimap_100", "the minimap at 100%, enlarged 3 times, no smoothing"],
	["minimap_140", "the minimap at 140%, enlarged 3 times, no smoothing"],
	["ring_held_aurelian", "a world ring HELD by Aurelian: the dot on the ring, the word AURELIAN HELD"],
	["ring_held_vhorr", "a world ring HELD by Vhorr: the wedge on the ring, the teeth, the word VHORR HELD"],
	["ring_contested", "a world ring CONTESTED: Aurelian's half on the left, each half with its mark, the Vhorr half with teeth"],
	["bars_and_feed", "hull bars with their team marks, and the kill feed with a Vhorr and an Aurelian kill"],
	["scoreboard", "the scoreboard with a team mark before each heading"],
	["kill_feed", "the kill feed (T-126b): an Aurelian pilot's three kills in a row (torpedo, Lance, guns: the name frame on the third), a Vhorr kill (shell), and the Vhorr kill that ends the streak (flak: the streak frame round the icon)"],
	["shots", "shots at the start zoom (T-126b): Aurelian rounds above (round beads), Vhorr rounds below (barbed heads): bolt, flak, shell, torpedo, Lance"],
	["kill_feed_own_10s", "the kill feed 10 s after (T-125 round 2): the line about the human pilot (their kill) is still there on its dark plate; two lines of other pilots' kills are gone (their life is 9 s)"],
	["kill_feed_own_15s", "the same feed 15 s after: the line about the human is gone too (its life is 14 s), so the corner is empty"],
]
## Ticks the match runs after the states are built, so the sites count who is inside.
const SETTLE_TICKS := 20
## How many times the minimap's picture is enlarged.
const ENLARGE := 3

## The running match (set by setup()).
var world: World
## The HUD, found once it exists.
var hud: Hud = null
## The folder the pictures go into (--shots); "" when none is wanted.
var dir := ""
## Where the tour is.
var stage := 0
## The tick at which the current stage began.
var stage_tick := 0
## The ships made for the pictures.
var ships: Array[Ship] = []
## Pictures saved, and checks failed.
var taken := 0
var _fails := 0
## True while a picture is being taken.
var busy := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	var headless := DisplayServer.get_name() == "headless"
	dir = str(Game.opt("shots", ""))
	for p: Array in PICTURES:
		print("team_shapes_shots: %s: %s" % [p[0], p[1]])
	if headless or dir == "":
		print("team_shapes_shots: %d pictures (nothing is saved here: it needs a window and --shots=<folder>)" % PICTURES.size())
		print("team_shapes_shots: %d failures" % _fails)
		get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())
		stage = 99
		return
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS


## A pilot ship of `team` named `callsign` standing at `pos`, without a driver.
func _ship(team: int, callsign: String, pos: Vector2) -> Ship:
	var p := PilotProfile.new(callsign, team, 20 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = pos
	s.velocity = Vector2.ZERO
	return s


## Point the camera at `p`, zoomed so `across` world units fit across the window.
func _aim(p: Vector2, across: float) -> void:
	var z := get_viewport().get_visible_rect().size.x / across
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.look_at_point(p)
	world.camera.global_position = p
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Save the window's picture as `shot_name`.png; `crop` (a rectangle in window pixels, or an empty one) cuts a part out,
## which is then enlarged ENLARGE times with no smoothing.
func _shot(shot_name: String, crop: Rect2i = Rect2i()) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop.size != Vector2i.ZERO:
		img = img.get_region(crop)
		img.resize(img.get_width() * ENLARGE, img.get_height() * ENLARGE, Image.INTERPOLATE_NEAREST)
	var path := dir.path_join("%s.png" % shot_name)
	var err := img.save_png(path)
	if err != OK:
		_fails += 1
		print("FAIL team_shapes_shots: %s could not be saved (%d)" % [shot_name, err])
	else:
		taken += 1
		print("shot ", path)
	busy = false


## A kill: `killer` (a ship) shoots down `victim` (another), so the feed writes the line.
func _kill(killer: Ship, victim: Ship, kind: int = Rules.W_BOLT) -> void:
	var info := DamageInfo.new()
	info.kind = kind
	info.source = killer
	info.source_uid = killer.uid
	info.source_team = killer.team
	info.source_is_pilot = true
	info.source_profile = killer.profile
	world.combat.kill(victim, info)


## Every frame: move the tour on.
func _process(_dt: float) -> void:
	if world == null or busy or stage >= 4:
		return
	if hud == null:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud == null:
			return
	match stage:
		0:
			if world.tick_count < 5:
				return
			world.set_physics_process(false)
			# The states: HELD for Aurelian, HELD for Vhorr, CONTESTED.
			world.spawn_turret(Rules.HALCYON, world.node_by_id("j_top_s"), 0, "pd", true)
			world.spawn_turret(Rules.CINDER, world.node_by_id("j_bot_s"), 0, "pd", true)
			var tn := world.node_by_id("j_top_n")
			ships.append(_ship(Rules.HALCYON, "Ash", tn.global_position + Vector2(300.0, 0.0)))
			ships.append(_ship(Rules.CINDER, "Wren", tn.global_position + Vector2(-300.0, 0.0)))
			# Hurt them and the turrets a little, so the hull bars are part empty.
			for s in ships:
				s.hull = s.hull_max * 0.6
			for n: String in ["j_top_s", "j_bot_s"]:
				var t: Turret = world.node_by_id(n).slots[0] as Turret
				if t != null:
					t.hull = t.hull_max * 0.5
			stage = 1
			stage_tick = world.tick_count
			world.set_physics_process(true)
		1:
			if world.tick_count - stage_tick < SETTLE_TICKS:
				return
			world.set_physics_process(false)
			stage = 2
			await _take_all()
			stage = 4
			print("team_shapes_shots: done %d pictures" % taken)
			if taken != PICTURES.size():
				_fails += 1
				print("FAIL team_shapes_shots: %d pictures taken, %d wanted" % [taken, PICTURES.size()])
			print("team_shapes_shots: %d failures" % _fails)
			get_tree().quit()


## Take every picture in order (the world is frozen).
func _take_all() -> void:
	# The minimap at 80, 100 and 140%; the size is put back to 100 after.
	for pct in [80, 100, 140]:
		Game.minimap_pct = pct
		hud.minimap.apply_size()
		await _frames(4)
		var r := hud.minimap.get_global_rect()
		await _shot("minimap_%d" % pct, Rect2i(Vector2i(r.position), Vector2i(r.size)))
	Game.minimap_pct = Game.MINIMAP_PCT_DEFAULT
	hud.minimap.apply_size()
	await _frames(4)
	# The three world rings, 5200 world units across the window.
	_aim(world.node_by_id("j_top_s").global_position, 5200.0)
	await _frames(4)
	await _shot("ring_held_aurelian")
	_aim(world.node_by_id("j_bot_s").global_position, 5200.0)
	await _frames(4)
	await _shot("ring_held_vhorr")
	var tn := world.node_by_id("j_top_n")
	_aim(tn.global_position, 5200.0)
	await _frames(4)
	await _shot("ring_contested")
	# Two kills for the feed (a Vhorr one and an Aurelian one), then the hull bars near the contested site.
	var pike := _ship(Rules.HALCYON, "Pike", tn.global_position + Vector2(0.0, 400.0))
	var vex := _ship(Rules.CINDER, "Vex", tn.global_position + Vector2(0.0, -400.0))
	_kill(ships[1], pike)
	_kill(ships[0], vex)
	_aim(tn.global_position, 1500.0)
	await _frames(6)
	await _shot("bars_and_feed")
	# The scoreboard, held open.
	hud._show_scoreboard(true)
	await _frames(6)
	await _shot("scoreboard")
	hud._show_scoreboard(false)
	# The hangar is open at the start of a match and the HUD hides the feed while a big panel is open: close it for the feed pictures.
	var hangar := hud.get("hangar") as Control
	if hangar != null:
		hangar.visible = false
	hud.layout.apply()
	await _kill_feed_picture(tn.global_position)
	await _shots_picture(tn.global_position)
	await _own_feed_pictures(tn.global_position)


## T-126b picture (4): the kill feed with the weapon icons and the two gold frames. The feed is emptied and its own count of
## kills in a row started again; then Ash (Aurelian) shoots down three Vhorr ships (a torpedo, a Lance beam, guns: the third
## makes an ace, so her name gets the frame), Wren (Vhorr) shoots down an Aurelian ship with a shell, and then Ash with
## flak: Ash had three kills in a row, so that icon gets the streak frame. The picture is the feed's corner, enlarged.
func _kill_feed_picture(at: Vector2) -> void:
	for c in hud.feed.get_children():
		hud.feed.remove_child(c)
		c.queue_free()
	hud.feed._run = {}
	var ash := ships[0]
	var wren := ships[1]
	var names := ["Vex", "Kestrel", "Thorn"]
	var kinds := [Rules.W_TORP, Rules.W_LANCE, Rules.W_BOLT]
	for i in 3:
		_kill(ash, _ship(Rules.CINDER, names[i], at + Vector2(float(i) * 120.0, -600.0)), kinds[i])
	_kill(wren, _ship(Rules.HALCYON, "Pike", at + Vector2(0.0, 600.0)), Rules.W_SHELL)
	_kill(wren, ash, Rules.W_FLAK)
	await _frames(6)
	var r := hud.feed.get_global_rect().grow(8.0)
	await _shot("kill_feed", Rect2i(Vector2i(r.position), Vector2i(r.size)))


## T-125 round 2, pictures (6) and (7): the lines about the human on their plate, and their life. The feed is emptied; then one
## line of another Aurelian pilot's kill, one line of the human's own kill (the human, World.human, shoots down a Vhorr ship),
## and one Vhorr pilot's kill: three lines, the window's corner is saved as the crop of both pictures. Each line's "born" is set
## back 10 s and HudFeed.fade_lines() run: the two other lines (life 9 s) go, the human's (life 14 s) stays on its plate:
## kill_feed_own_10s. Then 15 s: the human's line is gone too: kill_feed_own_15s.
func _own_feed_pictures(at: Vector2) -> void:
	for c in hud.feed.get_children():
		hud.feed.remove_child(c)
		c.queue_free()
	hud.feed._run = {}
	var me := world.human
	if me == null:
		_fails += 1
		print("FAIL team_shapes_shots: no human pilot for the own-line pictures (run it with --role=pilot)")
		return
	# The hangar is open at the start of a match and the HUD hides the feed while a big panel is open: close it for the pictures.
	var hangar := hud.get("hangar") as Control
	if hangar != null:
		hangar.visible = false
	var team := me.team
	var pike := _ship(team, "Pike", at + Vector2(0.0, 700.0))
	var vex := _ship(1 - team, "Vex", at + Vector2(200.0, -700.0))
	var thorn := _ship(1 - team, "Thorn", at + Vector2(400.0, -700.0))
	var kestrel := _ship(1 - team, "Kestrel", at + Vector2(600.0, -700.0))
	var row := _ship(team, "Row", at + Vector2(800.0, 700.0))
	_kill(pike, thorn, Rules.W_LANCE)
	# The human's own kill: the shot is the human's (their profile), fired by a ship made for it.
	var info := DamageInfo.new()
	info.kind = Rules.W_TORP
	info.source = pike
	info.source_uid = pike.uid
	info.source_team = team
	info.source_is_pilot = true
	info.source_profile = me
	world.combat.kill(kestrel, info)
	_kill(vex, row, Rules.W_SHELL)
	await _frames(20)
	var r := hud.feed.get_global_rect().grow(8.0)
	var crop := Rect2i(Vector2i(r.position), Vector2i(r.size))
	for age_s in [10.0, 15.0]:
		var back := Time.get_ticks_msec() - int(float(age_s) * 1000.0)
		for c in hud.feed.get_children():
			c.set_meta("born", back)
		HudFeed.fade_lines(hud.feed, HudFeed.LIFE)
		await _frames(4)
		await _shot("kill_feed_own_%ds" % int(age_s), crop)
		if int(age_s) == 15 and hud.feed.get_child_count() != 0:
			_fails += 1
			print("FAIL team_shapes_shots: %d lines are still in the feed at 15 s" % hud.feed.get_child_count())
	if hangar != null:
		hangar.visible = true


## T-126b picture (5): the five kinds of shot at the start zoom (6,000 world units across). Aurelian in the top row, Vhorr in the
## row under it, left to right: a bolt, flak, a shell, a torpedo (armed) and a Lance beam, all flying right. The rounds are made
## here and frozen (the world's physics is off); the projectile layer is told to show every team.
func _shots_picture(at: Vector2) -> void:
	var proj := world.projectiles
	var old_view := proj.viewer_team
	proj.viewer_team = -1
	var shooters := [_ship(Rules.HALCYON, "Row", at + Vector2(0.0, 2500.0)), _ship(Rules.CINDER, "Row", at + Vector2(400.0, 2500.0))]
	var beam_list: Array = []
	for row in 2:
		var y := at.y - 250.0 + 500.0 * float(row)
		var src: Unit = shooters[row]
		var specs := [[Rules.W_BOLT, 3.2], [Rules.W_FLAK, 3.4], [Rules.W_SHELL, 6.0], [Rules.W_TORP, 6.0]]
		for col in 4:
			var spec: Array = specs[col]
			var x := at.x - 1500.0 + 600.0 * float(col)
			var i := proj.spawn(Vector2(x, y), Vector2(900.0, 0.0), 100.0, 10.0, int(spec[0]), {"radius": float(spec[1])}, src, null)
			proj.arm_left[i] = 0.0
		beam_list.append([Vector2(at.x + 600.0, y), Vector2(at.x + 1100.0, y), src.team, 3.0, Rules.W_LANCE])
	proj.beams_draw = beam_list
	_aim(at, 6000.0)
	await _frames(6)
	await _shot("shots")
	proj.beams_draw = []
	proj.viewer_team = old_view
