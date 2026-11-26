extends Node
## WHAT THIS IS: the picture tour of the ship readout's ability line and Vent button. It saves three pictures
## of the human pilot's readout (ShipStatus) at a readable size: the ability ready, the ship overloaded (a
## lockout) and the ship venting. It is for people to look at, not a pass/fail check: in each picture the
## Vent button must not touch any line of text, and the ability line must say "offline", not "ready", in the
## last two. It prints "vent_readout_shots: N pictures" as its last line.
##
## HOW IT WORKS: setup() reads --shots, freezes the match, launches a Support Corvette (its ability, "Emergency
## repair", has the longest name) and lays an opaque layer over the world with the readout made from its scene,
## scaled up, and a caption. For each state it sets the ship's numbers by hand (the match is frozen, so nothing
## moves them), waits for the frame to draw and saves the viewport. Headless it takes no picture.
##
## HOW TO RUN IT (needs a window; park it off the screen):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto
##       --all-ai --no-pilots --no-admiral-ai --no-jungle --test=vent_readout_shots --shots=<dir>
##
## WHO USES IT: main.gd loads it for --test=vent_readout_shots; the lead and builders run it through the windowed
## queue.

## How many times the readout is enlarged in the picture.
const SCALE := 2.5

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## Pictures saved so far.
var taken := 0
## The caption drawn over each picture.
var caption: Label
## The readout under test.
var status: ShipStatus
## The ship it shows.
var ship: Ship


## Main calls this once the match is built: read the options, freeze the match, lay the readout over it and start.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	world.set_physics_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.08)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	caption = Label.new()
	caption.position = Vector2(24.0, 24.0)
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(caption)
	var p := PilotProfile.new("Support", 0, 90, false)
	p.hull_id = "support"
	world.profiles.append(p)
	ship = world.launch(p)
	ship.controller = null
	status = (load("res://scenes/ui/ship_status.tscn") as PackedScene).instantiate() as ShipStatus
	status.position = Vector2(24.0, 110.0)
	status.scale = Vector2(SCALE, SCALE)
	layer.add_child(status)
	_run.call_deferred()


## Take one picture named `file` (without the extension) with `text` as its caption.
func _shoot(file: String, text: String) -> void:
	caption.text = text
	status.set_ship(ship)
	if DisplayServer.get_name() == "headless":
		return
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(file + ".png"))
	taken += 1
	print("shot ", file)


## The whole tour: ready, overloaded, venting.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	ship.global_position = Vector2(MapLayout.CX, MapLayout.CY)
	ship.fill_energy()
	ship.shields.fill()
	ship.special_cd = 0.0
	ship.overload_left = 0.0
	ship.venting = false
	await _shoot("vent_readout_ready", "Ability ready: the Vent button is on the bottom row")
	ship.energy.hard = 55.0
	ship.energy.value = 30.0
	ship.overload_left = 3.4
	await _shoot("vent_readout_overloaded", "Overloaded: the ability line says offline, the Vent button is dim")
	ship.overload_left = 0.0
	ship.venting = true
	ship.energy.hard = 40.0
	ship.energy.value = 20.0
	await _shoot("vent_readout_venting", "Venting: the ability line says offline, the Vent button is lit")
	print("vent_readout_shots: %d pictures" % taken)
	get_tree().quit()
