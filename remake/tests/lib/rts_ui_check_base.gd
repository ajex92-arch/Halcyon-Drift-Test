class_name RtsUiCheckBase
extends Node
## WHAT THIS IS: the shared frame of the small checks of the awareness screens (groups, idle keys, badges, auto-join,
## army row): it waits until the HUD of the human Admiral exists and the match is being played, gives the check a
## match with both fleets filled (FleetFill), runs the check's cases and prints "<name>: N failures (M checks)".
##
## HOW IT WORKS: a check extends this class, sets `label` in _init() and writes run(). setup() is called by main.gd right
## after the World is built; _process() finds the HUD, waits a few frames and then calls run() once. The helpers:
## check() counts a case and prints its PASS or FAIL line; key() sends a key press through the HUD's real key router
## (HudInput.handle), the path a player's keyboard takes; squads() lists our selectable squadrons.
##
## HOW TO RUN A CHECK ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=tour --force-hud --test=<name>
##
## WHO USES IT: tests/rts_groups_check.gd, rts_idle_check.gd, rts_badge_check.gd, rts_join_check.gd, rts_army_check.gd.

## The running match (set by setup()).
var world: World
## The HUD, once found.
var hud: Hud
## The name printed in front of the result line.
var label := "rts_ui_check"
## How many cases failed and how many were made.
var fails := 0
var checks := 0
## Frames waited, and whether run() has started.
var _frames := 0
var _started := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS


## Find the HUD, wait a few frames, then run the cases once.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	_frames += 1
	if hud == null:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
	if _frames > 900 and (hud == null or hud.command_view == null):
		_started = true
		check("setup: the HUD and the command view exist", false)
		_finish()
		return
	if hud == null or hud.command_view == null or _frames < 12 or world.phase != "play":
		return
	_started = true
	var rounds := 0
	while FleetFill.apply(world) > 0 and rounds < 6:
		rounds += 1
	hud.command_view.refresh()
	await run()
	_finish()


## The cases (a check overrides this; it may await).
func run() -> void:
	pass


## Print the result line and quit.
func _finish() -> void:
	print("%s: %d failures (%d checks)" % [label, fails, checks])
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one case and print its line.
func check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Our selectable squadrons, in id order.
func squads() -> Array[Squad]:
	return RtsSelect.our_squads(world, world.human_team)


## Send a key press (physical key `code`, with Ctrl and Shift as asked) through the HUD's key router.
func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	hud.router.handle(e)


## The ids of `list` as an Array[int].
func ids_of(list: Array[Squad]) -> Array[int]:
	var out: Array[int] = []
	for rec: Squad in list:
		out.append(rec.id)
	return out
