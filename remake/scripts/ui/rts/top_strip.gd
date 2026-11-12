class_name TopStrip
extends Control
## WHAT THIS IS: the strip along the top of the command view (B1, the ledger line): one 24 px line of words and numbers
## that answers "what do I have, what does my list need, how full is my fleet": ORE (the treasury and the income a
## minute), LIST NEEDS (what the items not yet started still cost, as "needs 2,500 in 1:21" at the income, or "1,290 left"
## when the list is paid), FLEET (places used of the limit, then ships out, places held by builds that have started,
## ships waiting in the list), and at the right a pause button, the match clock, the difficulty as one word ("Hard", hidden in a
## match that names no level; its tooltip is the full sentence), the speed button and the deputy ("off").
##
## HOW IT WORKS: a Control that draws its box in the shared "row" look and holds flat buttons ("RtsStrip") placed one
## after the other by the width of their words. Every count is a button: ore and list open the production panel, fleet
## selects every squadron, the clock and the pause button pause, speed steps the match speed, the deputy opens the card's Base
## page. refresh() runs on the view's 4 Hz beat: it keeps a 60 s history of the treasury's change plus the ore spent
## (the same sum the computer Admiral keeps, admiral_production.gd) for the income, rewrites each text only when it
## changed, and places the buttons again only when a text changed. Below about 1,100 px of width the words are shortened.
## The strip never changes the match: the pause and speed buttons go through the HUD's own routes.
##
## WHO USES IT: CommandView (makes it, places it at the top, refreshes it); tests/rts_tour.gd.

## The window width (pixels) under which the words are shortened.
const COMPACT_W := 1100.0
## The gap between two parts (pixels) and the room inside a button.
const GAP := 10.0
const PAD := 8.0  # PAD (pixels or a count)
## The text size.
const FONT := 11

## The command view (set by setup()).
var view: CommandView
## The buttons by name: ore, list, fleet, pause, clock, speed, diff, deputy.
var _b := {}
## The 60 s history of income: [time, gained] pairs.
var _earn: Array = []
## The treasury and the spent total at the last sample.
var _last_money := -1.0
var _last_spent := 0.0  # the last spent
## The income now, ore a minute.
var income := 0.0
## What was shown at the last placing (to place again only when a text changed).
var _placed := ""
## True while the command pause is on (the clock reads PAUSED).
var paused := false


## Make the buttons and remember the view.
func setup(v: CommandView) -> void:
	view = v
	mouse_filter = Control.MOUSE_FILTER_STOP
	_make("ore", "ORE: what the treasury holds and what comes in a minute. A click opens the production panel.", func() -> void: view.prod.set_folded(false))
	_make("list", "LIST NEEDS: what the items of the build list that have not started still cost, less your ore, and when your income pays it. A click opens the production panel.", func() -> void: view.prod.set_folded(false))
	_make("fleet", "FLEET: places used of the limit, ships out, places held by builds that have started and ships waiting in the list. A click selects every squadron.", func() -> void: view.overlay.select_all_squadrons())
	_make("pause", "Pause the match to give orders (the card, the panel and the map keep working). A click again resumes.", func() -> void: _pause_pressed())
	_make("clock", "The match clock. A click pauses.", func() -> void: _pause_pressed())
	_make("speed", "The match speed. A click goes to the next speed.", func() -> void: _speed_pressed())
	_make("diff", "The difficulty.", func() -> void: _diff_pressed())
	_make("deputy", "The deputy: it comes with a later stage. A click opens the Base page.", func() -> void: view.card.set_page("base"))


## One strip button.
func _make(id: String, tip: String, on_press: Callable) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"RtsStrip"
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	add_child(b)
	_b[id] = b


## The pause button or the clock was pressed: the command pause (HudPanels).
func _pause_pressed() -> void:
	view.hud.panels.toggle_command_pause()


## The speed button was pressed: go to the next speed of the match's list.
func _speed_pressed() -> void:
	var steps := SpeedControl.all_steps()
	var i := steps.find(SpeedControl.current(view.world))
	var why := SpeedControl.send(view.world, int(steps[(i + 1) % steps.size()]))
	if why != "":
		view.overlay.say(why, false)


## The difficulty word was pressed: say its sentence on the card's result line (the tooltip holds it too).
func _diff_pressed() -> void:
	var mult := Difficulty.tag_mult(view.world)
	if mult >= 0.0:
		view.overlay.say(Difficulty.blurb_for(mult), true)


## Place the buttons again for the strip's size.
func relayout() -> void:
	_placed = ""
	_place()
	queue_redraw()


## Draw the box (the shared row look).
func _draw() -> void:
	draw_style_box(RtsTheme.look("row"), Rect2(Vector2.ZERO, size))


## Rewrite every text from the match (the view's beat calls this).
func refresh() -> void:
	var world := view.world
	var ts: TeamState = world.teams[view.team]
	_sample(ts)
	var compact := size.x < COMPACT_W
	var p := ts.production
	# ORE and the income.
	_text("ore", "ORE %s  +%s/min" % [Util.money(ts.treasury), Util.money(income)] if not compact else "ORE %s" % Util.money(ts.treasury))
	# LIST NEEDS: the price of every item not yet started, less the treasury.
	var total := 0.0
	var count := 0
	for it: Dictionary in p.items:
		if not bool(it["started"]):
			total += float(it["price"])
			count += 1
	var need := total - ts.treasury
	var list_text := "LIST empty"
	if count > 0:
		if need <= 0.0:
			list_text = "LIST paid  %s left" % Util.money(-need)
		elif income > 0.5:
			list_text = "LIST NEEDS %s  in %s" % [Util.money(need), Util.clock(need / income * 60.0)]
		else:
			list_text = "LIST NEEDS %s" % Util.money(need)
	_text("list", list_text)
	# FLEET.
	var cap := p.capacity
	var waiting := 0
	for it: Dictionary in p.items:
		if it["kind"] == Production.SHIP and not bool(it["running"]):
			waiting += int(it["count"])
	var fleet := "FLEET %d/%d" % [cap.used(), cap.limit()]
	if not compact:
		fleet += "  %d out" % cap.alive()
		if cap.reserved > 0:
			fleet += " · %d reserved" % cap.reserved
		if waiting > 0:
			fleet += " · %d more in list" % waiting
	_text("fleet", fleet)
	_text("pause", "Resume" if paused else "Pause")
	_text("clock", "PAUSED" if paused else Util.clock(world.time))
	_text("speed", SpeedControl.label_of(SpeedControl.current(world)))
	# The difficulty as one word (the level the enemy's income names); hidden in a match that names no level. Its tooltip is the full sentence.
	var mult := Difficulty.tag_mult(world)
	var diff: Button = _b["diff"]
	diff.visible = mult >= 0.0
	if mult >= 0.0:
		_text("diff", Difficulty.short_tag_for(mult))
		diff.tooltip_text = Difficulty.blurb_for(mult)
	_text("deputy", "DEPUTY off")
	_place()


## Add one sample to the income history and sum the last 60 s (ore a minute).
func _sample(ts: TeamState) -> void:
	var world := view.world
	if _last_money < 0.0:
		_last_money = ts.treasury
		_last_spent = ts.spent
	var gained := (ts.treasury - _last_money) + (ts.spent - _last_spent)
	_last_money = ts.treasury
	_last_spent = ts.spent
	if not paused:
		_earn.append([world.time, gained])
	while not _earn.is_empty() and world.time - float((_earn[0] as Array)[0]) > RtsHulls.INCOME_WINDOW_S:
		_earn.pop_front()
	var sum := 0.0
	for e: Array in _earn:
		sum += float(e[1])
	# An income is never below nothing (a refund or a cancelled build gives ore back; that is not a loss of income).
	income = maxf(0.0, sum / maxf(1.0, minf(RtsHulls.INCOME_WINDOW_S, world.time)) * 60.0)


## Set the text of button `id` when it changed.
func _text(id: String, text: String) -> void:
	RtsBeat.set_if_changed(_b[id], text)


## Put the buttons in a row: ORE, LIST, FLEET from the left, the pause button, clock, speed and deputy from the right,
## each as wide as its words. Only when a text or the width changed.
func _place() -> void:
	var sig := str(size.x)
	var widths := {}
	for id: String in _b:
		# The button's own least width (its words with the room the look gives them) plus a little air.
		var b: Button = _b[id]
		b.custom_minimum_size = Vector2.ZERO
		var w := b.get_combined_minimum_size().x + 6.0
		widths[id] = w
		sig += "|%d" % (int(w) if b.visible else -1)
	if sig == _placed:
		return
	_placed = sig
	var x := PAD
	for id: String in ["ore", "list", "fleet"]:
		_put(id, x, float(widths[id]))
		x += float(widths[id]) + GAP
	var rx := size.x - PAD
	for id: String in ["deputy", "speed", "diff", "clock", "pause"]:
		if not (_b[id] as Button).visible:
			continue
		rx -= float(widths[id])
		_put(id, rx, float(widths[id]))
		rx -= GAP * 0.5


## Place button `id` at x with width `w` (the strip's full height).
func _put(id: String, x: float, w: float) -> void:
	var b: Button = _b[id]
	b.position = Vector2(x, 0.0)
	b.size = Vector2(w, size.y)
	b.custom_minimum_size = Vector2(w, size.y)
