class_name HelpPanel
extends PanelContainer
## WHAT THIS IS: the "How to play" panel (key H), with four pages: The
## match, Flying, Admiral, and Keys (every key of the game, by mode).
##
## HOW IT WORKS: the layout is the scene scenes/ui/help_panel.tscn: a box
## (the "HelpLook" look) holding one column, Col > Head (Title, one button
## per page: TheMatch, Flying, Admiral, Keys, then Close) and Scroll > Body (the
## scrolling area, at least 120 pixels tall: it takes the height that is
## left). Each page button shows its page's name, which is also
## the page's key in PAGES, where all the text lives. _show() fills Body
## with the chosen page: each entry is a heading in the interface's highlight
## colour and a wrapped paragraph, made in code. In the browser build the notes
## paragraph ends with the browser's story (NOTES_WHERE_BROWSER) instead of
## NOTES_WHERE. The current page's button is in the highlight colour too. When
## the window's width changes, HudPanels
## calls rebuild() so the paragraphs wrap to the new width.
## The Keys page is not text in PAGES but a table made from the key list (KeyMapText.help_table):
## a block per mode with each action's name, its two keys and, for a key that
## does not work yet, what it comes with. It follows the player's own key changes. Its
## "Change keys" button sends `change_keys`.
##
## WHO USES IT: HudPanels makes it from scenes/ui/help_panel.tscn (H toggles
## it, through HudInput), hides it when `closed` is sent and opens the Controls
## page when `change_keys` is sent.

## Sent when the player presses "Close (H)".
signal closed
## Sent when the player presses "Change keys" on the Keys page.
signal change_keys

## The last sentence of the "Notes (F9)" entry: where the notes stay. In the
## browser build _show() swaps it for NOTES_WHERE_BROWSER.
const NOTES_WHERE := "Notes stay on this computer."

## What the "Notes (F9)" entry says instead of NOTES_WHERE in the browser build,
## where each note comes to the player as two downloads (the note and its
## picture) and the browser may ask once before it allows the second one. A
## browser keeps a Block answer to that question as a setting for the site and
## then drops every picture without telling the game, so the last sentence
## says how to undo it.
const NOTES_WHERE_BROWSER := "Each note comes to you as two downloads, the note and its picture. The browser may ask once whether this site may download several files: allow it. If you chose Block, the pictures stop arriving; to get them back, allow automatic downloads for this site in the browser's site settings (the padlock or page icon beside the address)."

## The paragraph of the "Difficulty" entry is not written here: its levels and
## multipliers are Difficulty's data, so _show() puts Difficulty.help_text() in
## its place (this word marks the entry).
const DIFFICULTY_FROM_DATA := "(the levels and multipliers: Difficulty.help_text())"

## The help text: page name -> list of [heading, paragraph] pairs, shown in
## this order. (Two paragraphs, "Goal" and "Turrets", read differently while
## the damage modifiers are removed: see PAGES_MODIFIERS_REMOVED. The "Notes
## (F9)" paragraph ends differently in the browser build: see NOTES_WHERE.)
## The "No fog (test)" paragraph describes a switch that lives in FogOff (scripts/world/fog_off.gd): this panel only shows the words.
const PAGES := {
	"The match": [
		["Teams", "Each side has 5 pilots and 1 Admiral (6 against 6). The Admiral spends the team treasury and gives the orders, and can also launch a ship of their own. The computer Admiral does that too: it takes the field when its mothership is attacked or when 2 or more of its pilots are down, then flies back to the bridge."],
		["Goal", "Destroy the enemy mothership. Nothing else ends the match. Motherships are huge: strike craft barely scratch them; frigates and capital ships tear into them, so late in the match fleets mass their big ships for sieges."],
		["The map", "Three lanes (top, mid, bottom) run between the motherships; the mid lane is the widest, the top and bottom lanes are narrow. Between the lanes is the jungle: dense asteroids with gaps only strike craft (Scout to Bomber) fit through. You can't see through asteroids."],
		["Minions", "From 0:45 and every 35 seconds, each side launches a wave down every lane, from that lane's defense post (see Turrets). The top and bottom lanes get 3 Snub-Fighters, 1 Light Bomber and a Patrol Leader; the middle lane gets 5 Snub-Fighters, 4 Light Bombers and 2 Patrol Leaders. They are weaker versions of the pilots' Fighter, Bomber and corvettes. Minions fight anything in their way. Finishing one off (the last hit) pays you its credits. If teammates also did at least a tenth of the damage in the last 15 seconds, they share a quarter of the credits, by damage, and you keep the rest."],
		["Turrets", "Each side starts with three turrets on every lane: an outer, an inner and an inhibitor turret. Its Admiral buys a lost one back after a while and builds more at the jungle's resource nodes. They are tough: alone, pilots deal only 30% damage to a turret, so push with your minion wave and let the minions tank. If you shoot an enemy pilot near an enemy turret, that turret targets you. Beside each lane's inhibitor turret stands that lane's defense post. It has no gun: the lane's waves launch from it, and if it is destroyed that lane sends no new waves until its Admiral rebuilds it, 5 minutes later."],
		["The jungle", "The Scum are pirates who hide in the asteroid fields between the lanes. They build their ships from the wrecks both fleets leave behind: Scum Raiders, and Scum Carriers that launch Scum Fighters. They attack anyone who comes near their dens, and both sides pay a bounty for every Scum ship destroyed, split by damage with a bonus for the last hit. Heaps of scrap and warning beacons mark a den. A cleared den is rebuilt 1-2 minutes later."],
		["Credits", "Pilots earn credits from last hits, kills and assists, Scum bounties, destroying turrets and drones, and a share of every ore delivery. Spend them in the hangar on ships, modules, pilot gear and repair kits. The Admiral spends the separate team treasury."],
		["Difficulty", DIFFICULTY_FROM_DATA],
		["Respawning", "Destroyed pilots respawn at the mothership after a few seconds (longer as the match goes on). Gear is kept; the ship and its modules are lost. When 2 or more pilots respawn within 30 seconds, the mothership is strained: its guns slow and its shields stop recharging for a while. The Admiral's own ship being shot down does not count."],
		["Pause (P) and the pause menu (Esc)", "P only pauses the match and, pressed again, resumes it; it never opens the menu. Esc opens the pause menu when there is no map tool or panel to close. The match waits while it shows. It has Resume, Look around (hides the menu so the mouse can move and zoom the camera; Esc brings the menu back, P resumes), How to play, Controls (the key settings), a row of speed buttons from 0.5x to 2x, Restart match (a new match in the same seat, on the same team and rules), Quit to start (back to the start screen), Full screen and, outside the browser, Quit game. Restart and the two quit buttons ask first. P or Esc resumes."],
		["Fullscreen", "F11 or Alt+Enter switches between the window and borderless fullscreen. The pause menu has a button for it too."],
		["Notes (F9)", "F9 pauses the match and opens a one-line note box. Type what you saw or felt (you may start with an item ID, like T-07:), then press Enter to save the note with a screenshot, or Esc to cancel. The match carries on as it was. " + NOTES_WHERE],
		["Unlock everything (test)", "A test option on the start screen, at the right of the difficulty buttons. While it is on, UNLOCKED shows at the top, and you can buy anything at once and for nothing: every ship, module, gear item and repair kit, and as the Admiral every unit, building and research. Computer pilots and the other team play as usual."],
		["No fog (test)", "A test option on the start screen, just left of Unlock everything (--fog-off launches with it on, --fog-off=0 with it off). While it is on, FOG OFF shows at the top and your screen shows everything: no fog of war, every enemy ship and building, shots, explosions and sounds, even in gas clouds and hidden pockets. Only your screen changes: what each team sees, the computer pilots and the Admiral's placing rules (wards, sensor sweeps and supply drops still need a spot your team can see) are as usual."],
		["Test wing (test)", "A test option on the start screen, in a row of its own under the difficulty text (--test-wing launches with it on). While it is on, a Scout, a Fighter and a Bomber fly with your pilot as wingmen: see Wingmen on the Flying page. It is off the first time. It changes nothing for the other pilots."],
		["Computer pilots' wings (test)", "A test option next to Test wing: while it is on (it is on the first time), every computer pilot on both teams flies with the same Scout, Fighter and Bomber. They follow their pilot and fight and are given no orders. Turn it off if the match stutters. (--cpu-wings launches with it on, --cpu-wings=0 with it off.)"],
		["Slow motion (test)", "The ` key (left of 1) steps the world speed: normal, 0.75x, 0.5x, normal. Shift plus the ` key steps the faster speeds, normal, 1.5x, 2x, and the pause menu has a row of speed buttons from 0.5x to 2x. Faster speeds are for matches against the computer only. Only the game world changes speed (ships, shots, timers and the clock): the camera, the menus and the pause keep their normal speed, the speed is kept through a pause, and the match plays out exactly as it would at normal speed. SPEED 0.75x, 0.5x, 1.5x or 2x shows at the top while the world is not at normal speed."],
	],
	"Flying": [
		["Moving", "The mouse aims and your ship turns to face it. W thrusts forward, S brakes and reverses, A / D slide sideways, Shift boosts (strike craft). Hold Ctrl to lock your heading: big ships keep their shields facing a threat while their turrets keep tracking the mouse. V toggles flight assist (off = drift)."],
		["Shooting", "Left-click fires. Right-click or G uses your ship's ability. Fixed guns fire where the nose points; turrets on bigger ships track the mouse; point-defense guns pick their own targets and shoot down torpedoes. The Bomber makes torpedo runs: fly straight and a fan of three torpedo lines closes to a thin line (steering or boosting opens it again). Hold left-click for a second and a half: your heading locks (W and S still work) and a bar fills under the ship. When it is full the torpedoes wait while the fan keeps closing; let go to launch all three, or they go by themselves after another second and a half. Right-click cancels at no cost (G still uses the ability). The first 200 units of flight are unarmed. The Bomber's torpedoes ignore shields, but point defense and flak can still shoot them down."],
		["Wingmen", "With the Test wing switch on (start screen) a Scout, a Fighter and a Bomber fly behind you and fight what comes near. Tap X with the mouse on an enemy: the wing attacks it. On one of your big ships (corvettes and up, or the mothership): the wing guards it from the place its guns cannot point. On empty space: they form on you. Hold X and a wheel opens under the mouse: six orders, four shapes (Wedge, Line, Column, Loose) and three fire settings; let go over one to give it, Esc closes it. The Wing button above your ship readout opens the same wheel. The strip over the readout shows each wingman (grey: catching up or going home). In the jungle they fall into a column. When you are shot down they fly home and launch again with you; a wingman that is destroyed is gone."],
		["Shields", "Shields have four zones: front, rear, left and right. A hit drains the zone facing the attacker; when it is empty, the hull takes the damage. Arrow keys focus shield strength into one zone (press it again to balance). Shields recharge a few seconds after the last hit. Bigger ships wait longer between focus changes."],
		["Energy", "1 Weapons (faster fire), 2 Shields (faster recharge, tougher shields), 3 Engines (speed, turning, cheaper boost), 4 Balanced. Bigger ships wait longer between changes."],
		["Asteroids", "Bumping rocks is harmless at low speed; ramming them fast hurts, bigger ships more. Capital-ship cannons break asteroids."],
		["Ship sizes", "Strike craft are fast, cheap and reward good flying; they can use the jungle. Corvettes, frigates and capital ships hit hard and see farther, but turn slowly: out of position they die quickly to bombers and flak. They are what breaks a mothership."],
		["Hangar (B)", "At the mothership (or while waiting to respawn), buy a hull, up to 2 modules, pilot gear (6 slots: flight suit, helmet, stick, cockpit layout, chair, implant) and repair kits. F launches. Inside one of your repair bays' range you can swap modules mid-flight."],
		["Repair", "R uses a repair kit: a small drone that heals your hull for 10 seconds (it can be shot down). Repair bays heal nearby ships with their drones. Docking at the mothership (F when close) repairs everything."],
		["Camera", "Mouse wheel or + / - zooms (how far out depends on your ship's size). The camera stays where you leave it, so you can look anywhere on the map: push the mouse to a screen edge, drag with the middle mouse button, or click the minimap (bottom-right); with no ship, W / A / S / D move it too. Space puts the camera on your ship (on your mothership if you have none). Hold Space to keep it centered as you fly; let go and it is free again. Launching jumps the camera to your new ship. The camera keeps working while the game is paused: the pause menu (P or Esc) covers the middle of the screen, and W / A / S / D, + / - and Space still move, zoom and center the camera behind it. Its Look around button hides the menu, and then the mouse wheel, the middle mouse button, the screen edges and the minimap work too."],
	],
	"Admiral": [
		["Your job", "Spend the team treasury to win the map: mining drones, turrets, repair bays, wards and the research tree. Tab opens the Admiral board. Your camera can go anywhere (you still see only what your team sees): move it with WASD, the screen edges, middle-drag, or by clicking the minimap. Space centers it on your ship, or on the mothership when you are docked."],
		["Turrets and posts", "Your lane turrets stand from the start. When one falls, its site unlocks after a while and the Build tab lets you buy it again. A lane's defense post launches its waves; when it is destroyed, the Build tab shows the time left until you may rebuild it (5:00 after it fell, 450 credits)."],
			["Economy", "The treasury earns a small trickle, 60% of every ore delivery, and bounties for destroyed enemy turrets and bays. Mining drones mine ore at the resource nodes; protect them, and turrets on nodes protect them too."],
		["Research", "Like Homeworld 2: build mothership modules (Research Module, Corvette / Frigate / Capital Ship Facilities, Platform Control, Sensors, Hyperspace; the Fleet Command Module has no job yet), then research in each module's column. Pilots can only buy ships you have unlocked."],
		["Map tools", "Repair bays fly to a spot and anchor for good (jungle too). Wards go only where your team can see. The rally waypoint speeds up and shields our ships inside it, and AI pilots gather there. From 20:00, move the mothership."],
		["Sieges", "Put the rally waypoint near the enemy mothership to order a siege: our AI frigates, capital ships and bombers converge on that lane and attack it. When a group of enemy frigates or capital ships pushes into OUR base, AI pilots come back and fight them on their own."],
		["The Yard", "The Admiral buys fleet ships on the board's Yard tab. A Fighter, Lance or Bomber squadron is three ships; the larger ships come one at a time. You pay when a build starts; items wait their turn for ore in the order shown, and you can move one up or down, hold it (it keeps its progress) or cancel it (a started build gives everything back). The fleet is limited to %d ships a team all match. Bought ships go to the rally you pick and fight what comes close; the free minion waves never stop." % RtsHulls.CAP_IN_FORCE],
		["Flying yourself", "You can launch a ship of your own from the hangar (B) with your personal credits. You can still give orders and look anywhere while flying (C switches the camera between your ship and free; Space centers it on your ship, and holding Space keeps it there), but moving the mothership needs you docked."],
	],
}

## The lines of PAGES that name a damage modifier, with the words shown
## instead of them while the damage modifiers are removed
## (Rules.damage_modifiers_removed()): heading -> paragraph. _show() swaps
## them in.
const PAGES_MODIFIERS_REMOVED := {
	"Goal": "Destroy the enemy mothership. Nothing else ends the match. Motherships are huge and well defended, so late in the match fleets mass their big ships for sieges.",
	"Turrets": "Each side starts with three turrets on every lane: an outer, an inner and an inhibitor turret. Its Admiral buys a lost one back after a while and builds more at the jungle's resource nodes. They are tough, so push with your minion wave and let the minions tank. If you shoot an enemy pilot near an enemy turret, that turret targets you. Beside each lane's inhibitor turret stands that lane's defense post. It has no gun: the lane's waves launch from it, and if it is destroyed that lane sends no new waves until its Admiral rebuilds it, 5 minutes later.",
}

## The page being shown (a key of PAGES, or "Keys").
var _page := "The match"
## The page buttons in the header row, in PAGES order, then Keys. Each one's text is
## its page's name.
@onready var _tabs: Array[Button] = [$Col/Head/TheMatch, $Col/Head/Flying, $Col/Head/Admiral, $Col/Head/Keys]
## The tables of the Keys page now showing, one grid of labels per mode (empty on the other pages).
var keys_grids: Array[GridContainer] = []
## The scrolling column that holds the current page's entries.
@onready var _body: VBoxContainer = $Col/Scroll/Body


## Called once when the node joins the scene: each page button shows its
## page and Close sends `closed`, and the first page is shown.
func _ready() -> void:
	for b in _tabs:
		b.pressed.connect(_show.bind(b.text))
	$Col/Head/Close.text = "Close (%s)" % KeyMapText.key_of("help")
	$Col/Head/Close.pressed.connect(func() -> void: closed.emit())
	_show(_page)


## Lay the current page out again for the width the panel now has (HudPanels
## calls this when the window's width changed).
func rebuild() -> void:
	_show(_page)


## Show page `p`: mark its button in the highlight colour, clear the old entries, and add a
## heading and a paragraph per entry. Paragraphs are pinned to the panel's
## width (UiKit.panel_width, not our `size`, which cannot shrink below the
## paragraphs) minus 60 pixels (but at least 400) so they wrap neatly.
func _show(p: String) -> void:
	_page = p
	for b in _tabs:
		b.add_theme_color_override("font_color", UiKit.accent() if b.text == p else Palette.ICE)
	# queue_free removes each old entry at the end of this frame.
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	keys_grids.clear()
	var w := maxf(400.0, UiKit.panel_width(self) - 60.0)
	if p == "Keys":
		_show_keys(w)
		return
	# The Admiral page also explains the orders that feature modules add
	# (CommandOrders); there are none in today's game.
	var entries: Array = (PAGES[p] as Array).duplicate()
	if p == "Admiral":
		entries.append_array(CommandOrders.help_entries())
	for entry: Array in entries:
		var row := UiKit.vbox(2)
		_body.add_child(row)
		row.add_child(UiKit.label(entry[0], 15, UiKit.accent()))
		# A line that names a damage modifier reads differently while the
		# damage modifiers are removed.
		var text: String = entry[1]
		if Rules.damage_modifiers_removed() and PAGES_MODIFIERS_REMOVED.has(entry[0]):
			text = PAGES_MODIFIERS_REMOVED[entry[0]]
		# The "Difficulty" paragraph is made from Difficulty's own data.
		if text == DIFFICULTY_FROM_DATA:
			text = Difficulty.help_text()
		# The browser build says where the notes go there (only the "Notes (F9)"
		# paragraph holds NOTES_WHERE).
		if OS.has_feature("web"):
			text = text.replace(NOTES_WHERE, NOTES_WHERE_BROWSER)
		var l := UiKit.label(text, 14, Palette.ICE, true)
		UiKit.pin_width(l, w)
		row.add_child(l)

## Fill Body with the Keys page: a line about it and the "Change keys" button, then for each mode
## (KeyMapData.MODES) a heading and a table made from the key list: the action, its first key, its
## second key and a note (what it comes with when it does not work yet, extra keys, why it cannot be
## changed). `w` is the width the paragraphs get.
func _show_keys(w: float) -> void:
	var top := UiKit.hbox(12)
	_body.add_child(top)
	var about := UiKit.label("Every key of the game, by mode, as they are now (your own changes included). A key marked 'comes with' belongs to a part of the game that is not built yet.", 14, Palette.ICE, true)
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.pin_width(about, maxf(300.0, w - 200.0))
	top.add_child(about)
	top.add_child(UiKit.button("Change keys", func() -> void: change_keys.emit(), 34.0))
	for m: String in KeyMapData.MODES:
		var title: String = KeyMapData.MODE_LABELS[m]
		if m == "flying_board":
			title += " (the same as Flying, except these)"
		_body.add_child(UiKit.label(title, 15, UiKit.accent()))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 3)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(grid)
		keys_grids.append(grid)
		for cell: String in ["Action", "Key", "Second key", ""]:
			grid.add_child(UiKit.label(cell, 14, Palette.MIST))
		for t: Dictionary in KeyMapText.help_table(m):
			var texts: Array[String] = [String(t["label"]), String(t["key1"]), String(t["key2"]), _keys_note(t)]
			for i in 4:
				# The action column wraps, the same for every row (a long action such as "Queue Scout squadron (Shift: to the
				# cap, Alt: ..." is 352 pixels wide and was cut off at 300: F124); the two key columns are short and clip.
				var l := UiKit.label(texts[i] if texts[i] != "" or i == 3 else "none", 14, Palette.ICE if i < 3 and texts[i] != "" else Palette.MIST, i == 0)
				l.custom_minimum_size.x = [300.0, 130.0, 130.0, 0.0][i]
				l.clip_text = i == 1 or i == 2
				grid.add_child(l)


## The last cell of a Keys table row: what the row comes with, any extra keys and its note.
func _keys_note(t: Dictionary) -> String:
	var parts := PackedStringArray()
	if String(t["comes"]) != "":
		parts.append(String(t["comes"]))
	if String(t["more"]) != "":
		parts.append("also " + String(t["more"]))
	if String(t["note"]) != "":
		parts.append(String(t["note"]))
	return "; ".join(parts)
