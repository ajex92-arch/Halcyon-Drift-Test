class_name DeputyToggle
extends RefCounted
## WHAT THIS IS: what the deputy's two command card cells (Deputy and Dep. mode, on the Base page) and the top
## strip's deputy button do: switch the deputy on or off and step its preset (Balanced, Attack, Defend, Economy),
## and the words they show.
##
## HOW IT WORKS: static functions that take the command view. Every press sends one DEPUTY order from the human
## seat through the order queue (`Order.make(OrderKinds.DEPUTY, team, Rules.ADMIRAL_SEAT, true, {"preset": word})`),
## so it is logged and replayed like any order of the human; no screen changes the match itself. The Deputy cell
## and the strip button switch it off when it is on, and on with the preset last used (Balanced the first time)
## when it is off. The Dep. mode cell steps to the next preset in the order above, from the preset in force, or from
## the one last used while the deputy is off; stepping a deputy that is off switches it on with that preset. The
## answer is said on the card's result line ("Deputy: Attack"). The strip reads "Deputy: Balanced" while it is on and
## exactly "DEPUTY off" while it is off. A match with no human Admiral has no deputy (Deputy.install makes it only
## then); the cells answer that and do nothing.
##
## WHO USES IT: CardActions (a press on either cell), CardState (the cells' words), TopStrip (the button and its
## text); tests/deputy_check.gd.


## The deputy of the view's match, or null when the match has none.
static func deputy_of(view: CommandView) -> Deputy:
	if view == null or view.world == null or view.world.orders == null:
		return null
	return view.world.orders.deputy


## The preset after `current` in the order the player sees them (Economy is followed by Balanced).
static func next_preset(current: String) -> String:
	var names: Array = AdmiralProfileData.PRESET_NAMES
	var i := names.find(current)
	return str(names[(i + 1) % names.size()]) if i >= 0 else str(names[0])


## The Deputy cell or the strip button was pressed: off when on, on with the last preset when off.
static func toggle(view: CommandView) -> void:
	var d := deputy_of(view)
	if d == null:
		view.overlay.say("The deputy helps a human Admiral only", false)
		return
	_send(view, "off" if d.preset != "off" else d.remembered)


## The Dep. mode cell was pressed: the next preset (and the deputy on, when it was off).
static func step(view: CommandView) -> void:
	var d := deputy_of(view)
	if d == null:
		view.overlay.say("The deputy helps a human Admiral only", false)
		return
	_send(view, next_preset(d.preset if d.preset != "off" else d.remembered))


## Send the DEPUTY order for `word` and say the answer on the card's result line.
static func _send(view: CommandView, word: String) -> void:
	var why: String = view.world.orders.submit(Order.make(OrderKinds.DEPUTY, view.team, Rules.ADMIRAL_SEAT, true, {"preset": word}))
	view.overlay.say("Deputy: %s" % Deputy.word(word) if why == "" else why, why == "")


## The words of the strip button: "DEPUTY off", or "Deputy: Balanced" (the preset's name) while it is on.
static func strip_text(d: Deputy) -> String:
	if d == null or d.preset == "off":
		return "DEPUTY off"
	return "Deputy: %s" % Deputy.word(d.preset)


## Fill the Dictionary `out` that the card draws for cell `cell_id` ("deputy" or "deputy_preset"): the Deputy cell is lit
## while the deputy is on, with the preset under the name; the Dep. mode cell shows the preset that a press steps from.
## A match without a deputy draws both locked.
static func cell(d: Deputy, cell_id: String, out: Dictionary) -> void:
	if d == null:
		out["state"] = "locked"
		out["sub"] = "no deputy"
		out["tip"] = "The deputy helps a human Admiral only."
		return
	if cell_id == "deputy":
		out["picked"] = d.preset != "off"
		out["sub"] = Deputy.word(d.preset)
		out["tip"] = "The deputy: a computer Admiral that builds and researches with you and takes over the fleet when you leave the keys for 30 seconds. A press switches it %s." % ("off" if d.preset != "off" else "on (%s)" % Deputy.word(d.remembered))
	else:
		var shown := d.preset if d.preset != "off" else d.remembered
		out["sub"] = Deputy.word(shown)
		out["tip"] = "The deputy's preset: Balanced, Attack, Defend or Economy. Now %s. A press steps to %s%s." % [Deputy.word(shown), Deputy.word(next_preset(shown)), " and switches the deputy on" if d.preset == "off" else ""]
