extends Node
## WHAT THIS IS: the check of the end screen's Quit button in the browser build. A web page cannot close itself: the game's
## quit() only stops its main loop and leaves the page frozen, so the victory (or defeat) screen of the browser build offers
## "New match" only, as the pause menu leaves out its "Quit game" there.
##
## HOW IT WORKS: on the first tick it builds the real end screen scene (scenes/ui/end_screen.tscn) with no match behind it, as
## load_all does, and looks at its two buttons. With --web-sim (a desktop run that acts as the browser build does, see
## EndScreen.quit_offered) the Quit button must not show; without it the Quit button must show. "New match" shows in both. It
## prints PASS or FAIL lines that start with "end_quit_check", then "end_quit_check: N failures (M checks)", and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --web-sim --test=end_quit_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --test=end_quit_check
## The real browser build is looked at by the web build check's way (a headless browser on the exported page).
##
## WHO USES IT: main.gd loads it for --test=end_quit_check; run_checks has a row for each of the two runs.

## The running match (set by setup()).
var world: World
## How many checks failed and how many were made.
var failures := 0
var checks := 0
## True once the cases have run (they run in the first tick).
var _ran := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Run the cases in the first tick, print the result and quit.
func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	var web := Game.opt("web-sim") != null
	var scene: PackedScene = load("res://scenes/ui/end_screen.tscn")
	var screen := scene.instantiate() as Control
	get_tree().root.add_child(screen)
	var quit := screen.get_node("Center/Card/Col/Buttons/Quit") as Button
	var again := screen.get_node("Center/Card/Col/Buttons/NewMatch") as Button
	_check(again.is_visible_in_tree(), "the New match button shows")
	if web:
		_check(not quit.visible and not quit.is_visible_in_tree(), "web build: the Quit button does not show")
	else:
		_check(quit.visible and quit.is_visible_in_tree(), "desktop: the Quit button shows")
	screen.queue_free()
	print("end_quit_check: %d failures (%d checks)" % [failures, checks])
	get_tree().quit()


## Count one check and print its line.
func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s end_quit_check: %s" % ["PASS" if ok else "FAIL", what])
