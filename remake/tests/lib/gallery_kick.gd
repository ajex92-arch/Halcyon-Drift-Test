class_name GalleryKick
extends RefCounted
## WHAT THIS IS: the kick strip of the hull gallery (tests/hull_gallery.gd with --kick): one
## picture, kick_strip.png, that shows a gun firing and its barrel sliding home, frame by
## frame, for a few guns: the Aurelian Fighter's twin cannons, the Destroyer's fore heavy
## cannon of both teams and the Battlecruiser's fore ion turret (the Battlecruiser's own
## heavy cannon sits under its flak mount, so it hardly shows). Each row is one gun; the columns are the moments
## before the shot and 0, 0.02, 0.05, 0.10, 0.18 and 0.30 seconds after it.
##
## HOW IT WORKS: it uses the real ships, painters and guns of the frozen gallery, and makes
## the shot the way the match does: the gun's cooldown jumps up (a burst beam's burst time
## too), and the match clock is moved to each moment, so GunKick sees the shot and ages it
## exactly as in play. The camera is put on the gun, each frame is saved by the viewport, the
## part round the gun is cut out and put into the sheet, and the moment is written on it.
## Nothing here touches the simulation: the match is frozen, and it is thrown away.
##
## WHO USES IT: tests/hull_gallery.gd calls strip() for --kick. It uses the gallery's world,
## units, home, labels, dir, aim_camera(), wait_frames() and _label().

## The guns of the strip, one row each: the team (0 Aurelian, 1 Cinder), the hull, the
## weapon id of the gun, the camera zoom, how far ahead of the gun the picture is centred
## (in turret units; for a nose gun, in design units from the middle of the hull), and the
## words written on the row.
const ROWS := [
	{"team": 0, "hull": "fighter", "weapon": "fighter_cannon", "zoom": 10.0, "ahead": 14.0, "title": "Aurelian Fighter, twin cannons"},
	{"team": 0, "hull": "destroyer", "weapon": "heavy_cannon", "zoom": 1.0, "ahead": 1.4, "title": "Aurelian Destroyer, heavy cannon"},
	{"team": 1, "hull": "destroyer", "weapon": "heavy_cannon", "zoom": 1.0, "ahead": 1.4, "title": "Vhorr Destroyer, heavy cannon"},
	{"team": 0, "hull": "battlecruiser", "weapon": "ion_turret", "zoom": 1.2, "ahead": 1.0, "title": "Aurelian Battlecruiser, ion turret"},
]
## The moments of the columns, in seconds after the shot (-1 = before the shot).
const AGES := [-1.0, 0.0, 0.02, 0.05, 0.10, 0.18, 0.30]
## The size of one picture of the sheet, in the game's own screen units (the window may
## show them bigger: the sheet keeps the window's pixels).
const CELL := Vector2i(260, 130)

## The hull gallery test that owns this part.
var gallery: Node
## The sheet (made when the first frame has shown how many pixels one screen unit is).
var _sheet: Image
## The size of one picture of the sheet, in the window's pixels.
var _cell := Vector2i.ZERO


## Remember the gallery that made us.
func _init(g: Node) -> void:
	gallery = g


## Make the strip, save it as kick_strip.png in the gallery's folder and print its path.
func strip() -> void:
	for r in ROWS.size():
		await _row(r, ROWS[r])
	var path: String = gallery.dir.path_join("kick_strip.png")
	_sheet.save_png(path)
	print("shot ", path)
	gallery.count += 1
	print("hull_gallery: done %d rows of %d moments" % [ROWS.size(), AGES.size()])


## One row of the sheet: fire the gun of `row` and save each moment.
func _row(r: int, row: Dictionary) -> void:
	var world: World = gallery.world
	# Only this one ship is on the stage, nose to the right, its gun pointing straight ahead.
	for t in 2:
		for key: String in gallery.units[t]:
			(gallery.units[t][key] as Node2D).visible = false
	var ship: Ship = gallery.units[int(row["team"])]["ship:" + str(row["hull"])]
	ship.visible = true
	gallery._put(ship, gallery.home)
	var gun: WeaponMount = null
	for m: WeaponMount in ship.mounts:
		m.cd = 0.0
		m.beam_on = 0.0
		if gun == null and m.weapon_id == str(row["weapon"]):
			gun = m
	if gun.mount_type != WeaponMount.FIXED:
		gun.angle = 0.0
	# Where the picture is centred: ahead of the gun.
	var length := float(ship.def["length"])
	var du := length / 36.0
	var centre := gallery.home as Vector2
	if gun.mount_type == WeaponMount.FIXED:
		centre += Vector2(float(row["ahead"]) * du, 0.0)
	else:
		var tu := float(TurretShapes.HULL_TU.get(ship.hull_id, TurretShapes.DEFAULT_TU)) * du
		centre = gun.world_pos() + Vector2(float(row["ahead"]) * tu, 0.0)
	gallery.aim_camera(centre, float(row["zoom"]))
	var base := 1000.0 + 10.0 * float(r)
	world.time = base - 0.5
	await gallery.wait_frames(3)
	for col in AGES.size():
		var age: float = AGES[col]
		world.time = base + maxf(age, -0.1)
		if age == 0.0:
			# The shot: the cooldown jumps up, the way WeaponMount.update() does it.
			gun.cd = 0.5
			gun.beam_on = 2.5 if gun.is_beam else 0.0
		elif age > 0.0:
			gun.cd = maxf(0.0, 0.5 - age)
			gun.beam_on = maxf(0.0, 2.5 - age) if gun.is_beam else 0.0
		await gallery.wait_frames(3)
		# The words on the picture: the moment, and on the first picture of the row what it is.
		var screen: Vector2 = gallery.get_viewport().get_visible_rect().size
		var top_left := Vector2(screen * 0.5) - Vector2(CELL) * 0.5
		gallery._label("before the shot" if age < 0.0 else "%.2f s after" % age, top_left + Vector2(CELL.x * 0.5, 10.0), 13, Palette.ICE)
		if col == 0:
			gallery._label(str(row["title"]), top_left + Vector2(CELL.x * 0.5, CELL.y - 10.0), 12, Palette.MIST)
		await gallery.wait_frames(1)
		await RenderingServer.frame_post_draw
		var frame: Image = gallery.get_viewport().get_texture().get_image()
		frame.convert(Image.FORMAT_RGBA8)
		# The picture is in the window's pixels, the labels and the camera are in screen units:
		# one screen unit is `unit` pixels (1.5 for a 1920 wide window on the game's 1280 wide screen).
		var unit := float(frame.get_width()) / screen.x
		if _sheet == null:
			_cell = Vector2i(Vector2(CELL) * unit)
			_sheet = Image.create_empty(_cell.x * AGES.size(), _cell.y * ROWS.size(), false, Image.FORMAT_RGBA8)
		_sheet.blit_rect(frame, Rect2i(Vector2i(top_left * unit), _cell), Vector2i(col * _cell.x, r * _cell.y))
		for l in gallery.labels.get_children():
			l.queue_free()
		await gallery.wait_frames(1)
