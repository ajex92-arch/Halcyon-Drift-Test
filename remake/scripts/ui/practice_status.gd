class_name PracticeStatus
extends PanelContainer
## WHAT THIS IS: the practice range's score line: a small box under the top bar that
## shows the trial the human is on ("Trial: hit five moving drones with the Lance
## bolt"), how many drones have been hit, a clock, and the result line when the trial
## ends. It exists only in a practice match (the HUD makes it only then) and it writes
## nothing: it reads the trial state of World.practice_range every frame.
##
## HOW IT WORKS:
##   - It is a see-through panel (the "MeLook" look of the HUD's own panels) with two
##     lines: the trial's words in the interface's highlight colour, and the count and
##     clock in grey ("2 / 5  ·  0:23.4  ·  kills 1"); when the trial has ended the
##     second line is the result ("Done: 5 hits in 23.4 s" or "Time up: 3 of 5 hits").
##   - Every frame _process() rewrites the two lines (only when they changed), and places
##     the box centred right under the top bar, GAP pixels below it, wherever the layout has
##     put the bar. While a big panel is open (the hangar, the board, the help, the
##     pause menu) the box hides, as the kill feed does, so it never sits under a panel.
##   - The mouse passes through it to the game.
##
## WHO USES IT: Hud.setup() adds one for a practice match (World.practice). It reads
## World.practice_range.trials (PracticeTrials) and Hud.top_bar.

## How wide (pixels) the two lines are laid out.
const WIDTH := 340.0
## The space (pixels) between the top bar and this box.
const GAP := 4.0

## The game world whose trial this shows.
var world: World
## The first line: the trial's words.
var _text: Label
## The second line: the count and clock, or the result.
var _score: Label


## Build the box for world `w`: the two lines in a column inside the panel.
func _init(w: World) -> void:
	world = w
	name = "PracticeStatus"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"MeLook"
	var rows := UiKit.vbox(2)
	add_child(rows)
	_text = UiKit.label("", 14, UiKit.accent(), true)
	UiKit.pin_width(_text, WIDTH)
	rows.add_child(_text)
	_score = UiKit.label("", 12, Palette.MIST, true)
	UiKit.pin_width(_score, WIDTH)
	rows.add_child(_score)


## Every frame: rewrite the lines from the trial state, hide under a big panel, and sit under the top bar.
func _process(_dt: float) -> void:
	var pr: PracticeRange = world.practice_range if world != null else null
	if pr == null or pr.trials == null:
		return
	var hud := get_parent() as Hud
	visible = hud == null or not hud._any_panel_open()
	var tr := pr.trials
	UiKit.set_text(_text, text_line(tr))
	UiKit.set_text(_score, score_line(tr))
	if hud != null and hud.top_bar != null:
		var bar := hud.top_bar.get_global_rect()
		var want := Vector2(bar.position.x + (bar.size.x - size.x) * 0.5, bar.end.y + GAP)
		if position != want:
			position = want


## The first line for trials `tr`: "Trial: <the task>", or the hint to launch while no trial has started.
static func text_line(tr: PracticeTrials) -> String:
	if tr.trial.is_empty():
		return tr.text()
	return "Trial: %s" % tr.text()


## The second line for trials `tr`: the result once the trial ended, else "count  ·  clock  ·  kills n"
## (the kills only once there is one); empty while no trial has started.
static func score_line(tr: PracticeTrials) -> String:
	var result := tr.result_line()
	if result != "":
		return result
	if tr.trial.is_empty():
		return ""
	var line := "%s  ·  %s" % [tr.count_text(), tr.clock_text()]
	if tr.kills > 0:
		line += "  ·  kills %d" % tr.kills
	return line
