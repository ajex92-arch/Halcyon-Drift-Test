class_name RtsBeat
extends RefCounted
## WHAT THIS IS: the command view's refresh beat: a counter that says "yes" four times a second, and the one way the
## view sets a text, only when it changed. It keeps the panels' work small (the 2 ms budget of the design).
##
## HOW IT WORKS: tick(dt) adds the frame time and answers true once each 0.25 s of real time (so it does not
## drift, the leftover is kept). Every panel of the command view owns one RtsBeat, or all share the CommandView's, and
## rebuilds its snapshot of the match (its texts, counts and states) only on a true tick, never every frame.
## set_if_changed(control, text) writes a Label's or Button's text only when it differs, because a changed text
## makes Godot lay the screen out again; flag() does the same for a visibility.
##
## WHO USES IT: CommandView (the shared beat), TopStrip, CommandCard, SelectionPanel and ProductionPanel;
## tests/rts_tour.gd counts the beats.

## Beats a second.
const HZ := 4.0
## Seconds between two beats.
const PERIOD := 1.0 / HZ

## Seconds collected towards the next beat.
var _acc := 0.0
## Beats given so far (a test reads it).
var beats := 0


## Add `dt` seconds. True on the frame a beat falls on (four times a second), else false. A long frame gives one
## beat, not several.
func tick(dt: float) -> bool:
	_acc += dt
	if _acc < PERIOD:
		return false
	_acc = fmod(_acc, PERIOD)
	beats += 1
	return true


## Make the next tick() answer true (a panel that just opened wants its first snapshot at once).
func prime() -> void:
	_acc = PERIOD


## Set the text of Label or Button `c` only when it changed.
static func set_if_changed(c: Control, text: String) -> void:
	if c != null and c.get("text") != text:
		c.set("text", text)


## Show or hide control `c` only when that changes it.
static func flag(c: Control, on: bool) -> void:
	if c != null and c.visible != on:
		c.visible = on
