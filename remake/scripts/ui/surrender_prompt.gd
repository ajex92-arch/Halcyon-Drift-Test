class_name SurrenderPrompt
extends Control
## WHAT THIS IS: the two buttons, Yes and No, that a human player clicks to
## answer their own team's surrender vote (the Surrender feature). They are
## the mouse route for the keys F10 (yes) and Delete (no), and they sit in
## a small box just under the big message in the middle of the screen, which
## names the vote and the keys.
##
## HOW IT WORKS: setup() builds the box (a question line, the two buttons and
## a line that says what you voted) and keeps the feature. refresh() shows the
## whole prompt only while the human's own team has a vote open
## (SurrenderFeature.human_vote_open()) and hides it otherwise, including while
## only the enemy team is voting and once the match is over. Every frame (_process) calls refresh(). A
## button press calls SurrenderFeature.cast_vote() and the line under the
## question then reads "You voted yes" or "You voted no"; the vote can be
## changed until it closes. The box takes the mouse, the rest of this control
## lets it through, and the mouse wheel over the box is not passed on.
## The control itself keeps running while the match is paused, so its frame can
## hold the vote keys then (SurrenderFeature.hold_if_blocked(): no tick runs while
## paused); the box and its buttons stay inert while paused (no hover, no press),
## as they always were, unless CLICK_WHILE_PAUSED is set.
##
## WHO USES IT: SurrenderFeature.install() makes one (only when there is a
## window) and puts it on a layer of its own. tests/surrender_check.gd builds
## one by hand, which needs no window.

## How far the box's top edge sits below the middle of the screen (pixels,
## negative = above it): just under the banner's two lines.
const TOP_OFFSET := -40.0
## May a click on Yes or No answer the vote while the match is paused? False: the
## box and its buttons stay inert while paused, as a paused match takes no click.
const CLICK_WHILE_PAUSED := false

## The feature whose vote this answers.
var feature: SurrenderFeature
## The Yes button.
var yes_button: Button
## The No button.
var no_button: Button
## The box that holds the question, the buttons and the vote line.
var panel: PanelContainer
## The question line.
var _question: Label
## The line that says what the human voted.
var _voted: Label


## Build the box for `f`'s vote. It starts hidden; refresh() shows it.
func setup(f: SurrenderFeature) -> void:
	feature = f
	# Keep running while the match is paused (the frame holds the vote keys then);
	# the box below is set apart from this, so it does not inherit it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_force_pass_scroll_events = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = UiKit.panel(8)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS if CLICK_WHILE_PAUSED else Node.PROCESS_MODE_PAUSABLE
	panel.mouse_force_pass_scroll_events = false
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = TOP_OFFSET
	panel.offset_bottom = TOP_OFFSET
	add_child(panel)
	var col := UiKit.vbox(6)
	panel.add_child(col)
	_question = UiKit.label("", 15, Palette.ICE)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_question)
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	yes_button = UiKit.button("Yes", _on_yes, 36.0)
	no_button = UiKit.button("No", _on_no, 36.0)
	for b: Button in [yes_button, no_button]:
		b.custom_minimum_size.x = 90.0
		b.mouse_force_pass_scroll_events = false
		row.add_child(b)
	_voted = UiKit.label("", 13, Palette.MIST)
	_voted.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_voted)
	visible = false


## Every frame, also while the match is paused: show or hide the prompt, keep its
## lines current, and hold the vote keys while a text box or a pause has them.
func _process(_dt: float) -> void:
	refresh()
	feature.hold_if_blocked()


## Show the prompt while the human's own team has a vote open, with the
## question and the human's vote so far; hide it otherwise, and always once the
## match is over (a vote left open when a mothership fell must not stay up under
## the end screen).
func refresh() -> void:
	var open := feature != null and feature.human_vote_open() and String(feature.world.phase) != "end"
	visible = open
	if not open:
		return
	var team := feature.world.human.team
	UiKit.set_text(_question, "Surrender the %s fleet?" % Rules.TEAM_DISPLAY[team])
	var vote := int(feature.human_vote[team])
	UiKit.set_text(_voted, "You voted yes" if vote > 0 else ("You voted no" if vote < 0 else ""))


## The Yes button was pressed.
func _on_yes() -> void:
	_answer(true)


## The No button was pressed.
func _on_no() -> void:
	_answer(false)


## Hand the answer to the feature (for the human's own team) and update the
## lines at once. Does nothing while the match is paused, unless CLICK_WHILE_PAUSED.
func _answer(yes: bool) -> void:
	if feature == null or feature.world == null or feature.world.human == null:
		return
	if is_inside_tree() and get_tree().paused and not CLICK_WHILE_PAUSED:
		return
	feature.cast_vote(feature.world.human.team, yes)
	refresh()
