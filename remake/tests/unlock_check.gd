extends Node
## WHAT THIS IS: the check of the test option "Unlock everything" (UnlockAll).
## It checks that the one question "is this buyer unlocked?" says yes for the
## human's own pilot record and the human Admiral's treasury and no for everybody
## else (every computer pilot, teammates too, and the other team), that an
## unlocked human buys the biggest ship class, modules, gear, a repair kit and (as
## Admiral) drones, modules, research, turrets, repair bays and wards without the
## credits or the treasury going down, and that the same buying with the option
## off meets today's prices and locks.
##
## HOW IT WORKS: setup() runs everything straight away, then quits. The seat is
## the human's seat of the match (--role), the option is what the launch said
## (--unlock-all or not). With a human seat it runs the buying twice from the
## same start: once with the option on and once with it off (it sets
## Game.unlock_everything itself), so one launch covers both halves. Each attempt
## starts from the same purse or treasury, an empty hull and empty queues.
## Without a human seat (--all-ai) only the question is asked, and it must say no
## to everyone even with the option on. With --force-hud it also looks at the
## UNLOCKED tag of the HUD and at the hangar's cards (a lock, a price, a click on
## the ship card). With --settings-check=<text> it also builds the start
## screen, presses the toggle and checks the settings file (that writes the
## player's settings file, so <text> must be part of the name of the user data
## folder, as for tests/difficulty_check.gd).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --unlock-all --test=unlock_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --unlock-all --test=unlock_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --test=unlock_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --unlock-all --test=unlock_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL
## <what> <detail>". The last line is "unlock_check: N failures"; 0 means every
## check passed.
##
## WHO USES IT: main.gd loads it for --test=unlock_check. It buys and sells for
## the human of the match it builds, so it is only for this check.

## The huge purse of the attempts that look at the locks only (credits).
const BIG_PURSE := 100000.0
## Two sums closer than this many credits count as equal (float noise).
const TOLERANCE := 1e-6

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## An open spot for a repair bay (found with the option on).
var _bay_spot := Vector2.ZERO


## main.gd calls this once, right after the World is built. Run every check and
## quit.
func setup(w: World) -> void:
	world = w
	var asked := Game.opt("unlock-all") != null and str(Game.opt("unlock-all")) != "false" and str(Game.opt("unlock-all")) != "0"
	print("unlock_check: seat=%s, --unlock-all %s" % [world.human_role, "given" if asked else "not given"])
	_check("Game.unlock_everything follows --unlock-all", Game.unlock_everything == asked, str(Game.unlock_everything))
	var launched := Game.unlock_everything
	# The question, with the option on and off.
	for on: bool in [true, false]:
		Game.unlock_everything = on
		_check_question(on)
	# The buying, with the option on and off, for a human seat.
	if world.human != null:
		for on: bool in [true, false]:
			Game.unlock_everything = on
			if world.human_role == "admiral":
				_check_admiral(on)
			_check_pilot(on)
		Game.unlock_everything = true
		_check_other_teams()
	Game.unlock_everything = launched
	if Game.opt("force-hud", false):
		_check_tag(launched)
		if world.human != null:
			_check_hangar(launched)
	var marker := str(Game.opt("settings-check", ""))
	if marker != "":
		_check_settings(marker)
	print("unlock_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Check that `got` is `want` (within TOLERANCE), as the check `what`.
func _near(what: String, got: float, want: float) -> void:
	_check(what, absf(got - want) <= TOLERANCE, "got %.3f, wanted %.3f" % [got, want])


## The question UnlockAll.is_unlocked(), with the option `on`: yes for the human's
## pilot record and the human Admiral's treasury only, and only while it is on.
func _check_question(on: bool) -> void:
	var tag := "option %s:" % ("on" if on else "off")
	for p: PilotProfile in world.profiles:
		var want := on and p == world.human
		if UnlockAll.is_unlocked(p) != want:
			_check("%s the question about pilot %s (team %d, human %s) says %s" % [tag, p.callsign, p.team, str(p.is_human), str(want)], false, str(not want))
	_check("%s the question says %s for the human's pilot record" % [tag, "yes" if on and world.human != null else "no"], UnlockAll.is_unlocked(world.human) == (on and world.human != null))
	var yes_teams := 0
	for t in 2:
		if UnlockAll.is_unlocked(world.teams[t]):
			yes_teams += 1
	var want_teams := 1 if (on and world.human_role == "admiral") else 0
	_check("%s the question says yes for %d treasuries (the human Admiral's only)" % [tag, want_teams], yes_teams == want_teams, str(yes_teams))
	_check("%s nobody else is unlocked: no pilot but the human, no treasury but the Admiral's" % tag, _others_unlocked() == 0, str(_others_unlocked()))
	_check("%s the question says no for nothing and for something that is no buyer" % tag, not UnlockAll.is_unlocked(null) and not UnlockAll.is_unlocked(self))


## How many pilot records other than the human's are unlocked, plus the treasuries
## that are unlocked without a human Admiral.
func _others_unlocked() -> int:
	var n := 0
	for p: PilotProfile in world.profiles:
		if p != world.human and UnlockAll.is_unlocked(p):
			n += 1
	for t in 2:
		if world.teams[t].admiral != "human" and UnlockAll.is_unlocked(world.teams[t]):
			n += 1
	return n


## Put the human's pilot record back to a clean start with `purse` credits.
func _reset_pilot(p: PilotProfile, purse: float) -> void:
	p.credits = purse
	p.hull_id = ""
	p.modules.clear()
	for i in p.inventory.size():
		p.inventory[i] = {}


## The pilot seat's shop with the option `on`: the human buys the biggest class, a
## module pair, gear and a kit. On, nothing costs a credit and nothing is locked;
## off, today's locks and prices hold.
func _check_pilot(on: bool) -> void:
	var h := world.human
	var ts: TeamState = world.teams[h.team]
	var tag := "pilot shop, option %s:" % ("on" if on else "off")
	var team_done := ts.done.duplicate()
	var team_fac := ts.facilities.duplicate()
	var big := "battlecruiser"
	# The biggest class.
	_reset_pilot(h, Rules.START_CREDITS)
	var err := h.buy_hull(big, ts)
	if on:
		_check("%s buys the %s from the start" % [tag, big], err == "" and h.hull_id == big, "'%s', hull %s" % [err, h.hull_id])
		_near("%s the hull cost nothing" % tag, h.credits, Rules.START_CREDITS)
	else:
		_check("%s the %s is locked" % [tag, big], err.begins_with("Locked: needs"), err)
		_reset_pilot(h, BIG_PURSE)
		err = h.buy_hull(big, ts)
		_check("%s the %s stays locked with a huge purse" % [tag, big], err.begins_with("Locked: needs"), err)
	# A cheap class: the price is paid only with the option off.
	_reset_pilot(h, Rules.START_CREDITS)
	err = h.buy_hull("fighter", ts)
	var fighter_price := float(Ships.HULLS["fighter"]["price"])
	_check("%s buys a fighter" % tag, err == "" and h.hull_id == "fighter", err)
	_near("%s the fighter's price" % tag, h.credits, Rules.START_CREDITS - (0.0 if on else fighter_price))
	# Two modules on the biggest class (on) or the fighter (off), and a third refused.
	var hull := big if on else "fighter"
	_reset_pilot(h, Rules.START_CREDITS)
	if on:
		h.buy_hull(big, ts)
	else:
		h.hull_id = "fighter"
	var before := h.credits
	var paid := 0.0
	for mid: String in ["plating", "engines"]:
		err = h.toggle_module(mid)
		paid += Modules.price_for(mid, hull)
		_check("%s fits module %s on a %s" % [tag, mid, hull], err == "" and h.modules.has(mid), err)
	_near("%s the two modules cost" % tag, h.credits, before - (0.0 if on else paid))
	err = h.toggle_module("weapons")
	_check("%s a third module is refused (the 2-module rule stays)" % tag, err.contains("2 modules"), err)
	# Gear and a repair kit.
	_reset_pilot(h, Rules.START_CREDITS)
	var gid := ""
	for id: String in Items.ITEMS:
		if gid == "" or float(Items.ITEMS[id]["price"]) > float(Items.ITEMS[gid]["price"]):
			gid = id
	err = h.buy_gear(gid)
	var gear_price := float(Items.ITEMS[gid]["price"])
	if on or gear_price <= Rules.START_CREDITS:
		_check("%s buys gear %s" % [tag, gid], err == "" and h.has_item(gid), err)
		_near("%s the gear's price" % tag, h.credits, Rules.START_CREDITS - (0.0 if on else gear_price))
	else:
		_check("%s the dearest gear %s is too dear for the start purse" % [tag, gid], err.begins_with("Not enough credits"), err)
	_reset_pilot(h, Rules.START_CREDITS)
	err = h.buy_kit()
	_check("%s buys a repair kit" % tag, err == "" and h.kit_count() == 1, err)
	_near("%s the kit's price" % tag, h.credits, Rules.START_CREDITS - (0.0 if on else float(Items.KIT["price"])))
	# The team got no help from it.
	_check("%s the team's research and facilities are unchanged" % tag, ts.done == team_done and ts.facilities == team_fac and not ts.ship_unlocked(big))
	_reset_pilot(h, Rules.START_CREDITS)


## The Admiral seat's orders with the option `on`: every order is tried from the
## same treasury and empty queues. On, each one goes through for nothing (the
## research and facility rules waived); off, today's rules and prices hold.
func _check_admiral(on: bool) -> void:
	var team := world.human.team
	var ts: TeamState = world.teams[team]
	var cmd := world.command
	var tag := "Admiral orders, option %s:" % ("on" if on else "off")
	var done0 := ts.done.duplicate()
	var fac0 := ts.facilities.duplicate()
	var inner := ""
	for n: ResourceNode in world.nodes:
		if n.node_kind == "inner" and n.side == team and inner == "":
			inner = n.node_id
	# The turret that stands there from the start is taken away quietly (no
	# reward, no lock), so the turret orders below find a free slot.
	for old: Variant in world.node_by_id(inner).slots.duplicate():
		if old != null and is_instance_valid(old) and old.alive:
			world.combat.kill_silently(old)
	if on and _bay_spot == Vector2.ZERO:
		_bay_spot = _find_bay_spot(team)
	var ward_spot := world.mothership(team).global_position + Vector2(500, 300)
	# [what, the order, the reason today's game gives at the start ("" = it goes through and costs)]
	var tries := [
		["a mining drone", func() -> String: return cmd.build_drone(team), ""],
		["the Research Module", func() -> String: return cmd.build_facility(team, "research"), ""],
		["the Corvette Facility", func() -> String: return cmd.build_facility(team, "corvette"), "Needs the Research Module"],
		["the Fleet Command Module", func() -> String: return cmd.build_facility(team, "fleet"), "Needs the Capital Ship Facility"],
		["research Lance Beams", func() -> String: return cmd.research(team, "lanceBeams"), "Needs the Research Module"],
		["research Battlecruiser Chassis", func() -> String: return cmd.research(team, "battlecruiserChassis"), "Needs the Research Module"],
		["a PD turret", func() -> String: return cmd.build_turret(team, inner, "pd"), ""],
		["a torpedo turret", func() -> String: return cmd.build_turret(team, inner, "torp"), "Needs Platform Missiles research"],
		["a repair bay", func() -> String: return cmd.deploy_bay(team, _bay_spot), "Needs Repair Bays research"],
		["a ward", func() -> String: return cmd.place_ward(team, ward_spot), ""],
	]
	for purse: float in [Rules.START_TREASURY, 1.0]:
		for t: Array in tries:
			ts.treasury = purse
			_empty_lists(ts)
			var units_before := world.units.duplicate()
			var err: String = (t[1] as Callable).call()
			# An order puts its item in the build list; the item pays when it starts, on the list's next tick.
			ts.production.tick(0.0)
			# Take away what the order made (a turret, a bay, a ward), so the next
			# attempt finds the node's slots and the bay limit as they were.
			for u: Unit in world.units.duplicate():
				if not units_before.has(u):
					world.combat.kill_silently(u)
			var what := "%s %s, treasury %d" % [tag, t[0], int(purse)]
			var paid := purse - ts.treasury
			if on:
				_check(what, err == "" and absf(paid) <= TOLERANCE, "'%s', paid %.1f" % [err, paid])
			elif purse == 1.0:
				# Off with an empty purse: refused for the lock, or for the money. A drone, module or research order is not refused for money: it joins the build list and waits for the ore, and nothing is paid.
				var waits := err == "" and ts.production.items.size() > 0
				_check(what, (err != "" or waits) and absf(paid) <= TOLERANCE, "'%s'" % err)
			elif str(t[2]) == "":
				_check(what, err == "" and paid > 0.0, "'%s', paid %.1f" % [err, paid])
			else:
				_check(what, err.contains(str(t[2])) and absf(paid) <= TOLERANCE, "'%s'" % err)
	ts.treasury = Rules.START_TREASURY
	_empty_lists(ts)
	# On: a queued research runs without the Research Module and helps the team.
	if on:
		cmd.research(team, "lanceBeams")
		ts.production.tick(0.0)
		ts.tech.tick(1000.0, world.mothership(team))
		_check("%s a research runs without the Research Module and the team gets it" % tag, ts.done.has("lanceBeams") and not ts.facilities.has("research"), "done %s" % str(ts.done.keys()))
	# Put the team back as it was.
	ts.done.assign(done0)
	ts.facilities.assign(fac0)
	ts.treasury = Rules.START_TREASURY
	_empty_lists(ts)


## Empty the team's build list and the three old queues behind it (what an earlier try in this check left).
func _empty_lists(ts: TeamState) -> void:
	ts.building.clear()
	ts.research.clear()
	ts.drone_queue.clear()
	ts.production.items.clear()


## A spot near the Admiral's mothership where a repair bay may go (with the option
## on), or the mothership's own place if none is found.
func _find_bay_spot(team: int) -> Vector2:
	var ms := world.mothership(team).global_position
	for dx: float in [900.0, 1200.0, 600.0, 1500.0, -900.0]:
		for dy: float in [0.0, 400.0, -400.0, 800.0, -800.0]:
			var p := ms + Vector2(dx, dy)
			if world.command.bay_blocker(team, p) == "":
				return p
	return ms


## Nothing is unlocked for a computer buyer: a teammate and an enemy pilot meet
## the lock and the price whatever the option says, and so does a computer
## Admiral's treasury.
func _check_other_teams() -> void:
	var h := world.human
	var tag := "computer buyers, option on:"
	for team in 2:
		var p: PilotProfile = null
		for q: PilotProfile in world.profiles:
			if q.team == team and q != h and not q.is_human:
				p = q
				break
		if p == null:
			continue
		var ts: TeamState = world.teams[team]
		p.credits = BIG_PURSE
		p.hull_id = ""
		var err := p.buy_hull("battlecruiser", ts)
		_check("%s %s (team %d) meets the lock on the battlecruiser" % [tag, p.callsign, team], err.begins_with("Locked: needs"), err)
		p.hull_id = "fighter"
		p.credits = 50.0
		err = p.toggle_module("plating")
		_check("%s %s (team %d) meets the price of a module" % [tag, p.callsign, team], err.begins_with("Not enough credits") and absf(p.credits - 50.0) <= TOLERANCE, err)
		if ts.admiral != "human":
			var treasury := ts.treasury
			_check("%s team %d's computer treasury cannot buy a 10,000,000 order" % [tag, team], not ts.can_afford(1.0e7) and not ts.spend(1.0e7) and absf(ts.treasury - treasury) <= TOLERANCE)
			ts.spend(100.0)
			_near("%s team %d's computer treasury pays 100" % [tag, team], ts.treasury, treasury - 100.0)
			ts.treasury = treasury
	h.credits = Rules.START_CREDITS


## The UNLOCKED tag of the HUD (needs --force-hud): shown while the human's buying
## is free, hidden otherwise.
func _check_tag(launched: bool) -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("the HUD exists for the tag check", false, "no Hud node (use --force-hud)")
		return
	for on: bool in [true, false]:
		Game.unlock_everything = on
		hud.top_bar.refresh(world)
		var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
		var want := on and world.human != null
		_check("the UNLOCKED tag with the option %s" % ("on" if on else "off"), tags.visible == want and (not want or tags.text.contains("UNLOCKED")), "visible %s, text '%s'" % [str(tags.visible), tags.text])
	Game.unlock_everything = launched
	hud.top_bar.refresh(world)


## The hangar's cards (needs --force-hud) tell the same story as the shop: with the
## option on the biggest ship, a module, gear and a kit show no lock and no price
## and a click on the ship card buys it for nothing; with it off the lock and the
## prices show.
func _check_hangar(launched: bool) -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		return
	var h := world.human
	hud._open_hangar()
	var hg: Hangar = hud.hangar
	for on: bool in [true, false]:
		Game.unlock_everything = on
		var tag := "hangar, option %s:" % ("on" if on else "off")
		_reset_pilot(h, Rules.START_CREDITS)
		hg._set_tab("Ships")
		var ship_foot := (hg._cards["ship:battlecruiser"] as CardButton).foot.text
		if on:
			_check("%s the battlecruiser card shows no lock and no price" % tag, ship_foot.begins_with("Free"), ship_foot)
			HangarShips.buy(hg, "battlecruiser")
			_check("%s a click on the battlecruiser card buys it for nothing" % tag, h.hull_id == "battlecruiser" and absf(h.credits - Rules.START_CREDITS) <= TOLERANCE, "%s, %.0f credits" % [h.hull_id, h.credits])
		else:
			_check("%s the battlecruiser card shows the lock" % tag, ship_foot.begins_with("Locked: needs"), ship_foot)
			HangarShips.buy(hg, "battlecruiser")
			_check("%s a click on the battlecruiser card buys nothing" % tag, h.hull_id == "" and absf(h.credits - Rules.START_CREDITS) <= TOLERANCE)
		h.hull_id = "destroyer"
		hg._set_tab("Modules")
		var mod_foot := (hg._cards["mod:plating"] as CardButton).foot.text
		var want_mod := "0 credits" if on else "%d credits" % int(Modules.price_for("plating", "destroyer"))
		_check("%s the Plating card says %s" % [tag, want_mod], mod_foot.begins_with(want_mod), mod_foot)
		hg._set_tab("Gear")
		var gid := ""
		for id: String in Items.ITEMS:
			if gid == "" or float(Items.ITEMS[id]["price"]) > float(Items.ITEMS[gid]["price"]):
				gid = id
		var gear_foot := (hg._cards["gear:" + gid] as CardButton).foot.text
		var want_gear := "0 credits" if on else "%d credits" % int(Items.ITEMS[gid]["price"])
		_check("%s the dearest gear card says %s" % [tag, want_gear], gear_foot.begins_with(want_gear), gear_foot)
		hg._set_tab("Kits")
		var kit_foot := (hg._cards["kit"] as CardButton).foot.text
		var want_kit := "0 credits" if on else "%d credits" % int(Items.KIT["price"])
		_check("%s the repair kit card says %s" % [tag, want_kit], kit_foot.begins_with(want_kit), kit_foot)
	Game.unlock_everything = launched
	hud._close_others(null)
	_reset_pilot(h, Rules.START_CREDITS)


## Build a start screen as a new run would (the settings read before).
func _new_screen() -> StartScreen:
	var screen := (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate() as StartScreen
	add_child(screen)
	return screen


## The start screen's toggle and the remembered choice (see the top of the file).
## `marker` must be part of the user data folder's name, so the settings file
## written here is a scratch one.
func _check_settings(marker: String) -> void:
	var dir := OS.get_user_data_dir()
	if not dir.contains(marker):
		_check("settings check: the user data folder holds \"%s\"" % marker, false, "it is %s, so nothing was written" % dir)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	# Step 1: nothing remembered: the option is off and the toggle shows it.
	Game.unlock_everything = false
	Game._unlock_open = true
	var screen := _new_screen()
	_check("settings: off when nothing is remembered", not Game.unlock_everything and not screen._unlock_button.button_pressed, screen._unlock_button.text)
	_check("settings: the toggle says Unlock everything (test) and off", screen._unlock_button.text == "Unlock everything (test): off", screen._unlock_button.text)
	# Step 2: press it: on, pressed, and in the file.
	screen._unlock_button.pressed.emit()
	var cfg := ConfigFile.new()
	_check("settings: pressing it turns the option on", Game.unlock_everything and screen._unlock_button.button_pressed and screen._unlock_button.text == "Unlock everything (test): ON", screen._unlock_button.text)
	_check("settings: the file was written", cfg.load(Game.SETTINGS_FILE) == OK and cfg.get_value("game", "unlock_everything", false) == true)
	screen.free()
	# Step 3: a new run: the choice comes back.
	Game.unlock_everything = false
	Game._unlock_open = true
	screen = _new_screen()
	_check("settings: the next run shows it on, as remembered", Game.unlock_everything and screen._unlock_button.button_pressed)
	screen.free()
	# Step 4: the launch option beats the remembered choice (settled before the screen).
	Game.unlock_everything = false
	Game._unlock_open = false
	screen = _new_screen()
	_check("settings: a launch option beats the remembered choice", not Game.unlock_everything and not screen._unlock_button.button_pressed)
	screen.free()
	# Step 5: a damaged file is ignored.
	cfg.set_value("game", "unlock_everything", "banana")
	cfg.save(Game.SETTINGS_FILE)
	Game.unlock_everything = false
	Game._unlock_open = true
	screen = _new_screen()
	_check("settings: a word instead of a yes is ignored", not Game.unlock_everything)
	screen.free()
	# Step 6: pressing it again turns it off and writes that.
	Game.choose_unlock(true)
	screen = _new_screen()
	screen._unlock_button.pressed.emit()
	_check("settings: pressing it again turns it off in the file too", not Game.unlock_everything and cfg.load(Game.SETTINGS_FILE) == OK and cfg.get_value("game", "unlock_everything", true) == false)
	screen.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
