extends Node
## WHAT THIS IS: the check of the test option "No fog" (FogOff). The option only changes what the
## human's screen draws. This check proves that the vision (the lit and explored cells), the units'
## masks (visible_mask, seen_mask) and the rules that read them are the same with the option on and off,
## that the human's team stays the viewer, and that the screen shows everything (no fog picture, every
## unit drawn, the FOG OFF tag, the enemy turret counts, the minimap) only while the option is on.
##
## HOW IT WORKS: setup() runs the first half of the checks at tick 0, with the value that --fog-off
## launched (and the flips it makes itself, put back at the end). The match then runs on to frame 900
## (15 game seconds), where the vision and the masks are checked again and the line "fog_check: digest"
## is printed: a fingerprint of the match (the lit and explored cells, the masks, the unit count, the
## node count and the next random number). The pair runs, with the option on and off and the same seed,
## must print the same digest line: no simulation code reads the option. With a human seat the rules are
## checked too (a ward on a fogged spot is still refused). With --force-hud it also looks at the HUD.
## With --settings-check=<text> it also builds the start screen and checks the No fog toggle and the
## settings file. That writes the player's settings file, so <text> must be part of the name of the user
## data folder, as for tests/unlock_check.gd. A source scan lists the scripts that name FogOff or fog_off:
## exactly the planned files.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --fog-off --test=fog_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --force-hud --seed=7 --fog-off --test=fog_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --test=fog_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --seed=7 --fog-off --test=fog_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what> <detail>", then the
## digest line, and "fog_check: N failures" last. 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=fog_check. It reads the game, except Game.fog_off, which it
## sets and puts back after every step.

## The frame of the second half: 15 game seconds at 60 frames a second.
const SECOND_HALF_FRAME := 900
## Two sums closer than this count as equal (float noise).
const TOLERANCE := 1e-6
## The only scripts that may name FogOff or fog_off: the planned places (see the source scan).
const ALLOWED := [
	"scripts/autoload/game.gd", "scripts/world/fog_off.gd", "scripts/ui/start_screen.gd", "scripts/ui/hud_top_bar.gd",
	"scripts/world/fog_view.gd", "scripts/world/world_visibility.gd", "scripts/world/world_registry.gd", "scripts/world/world_setup.gd",
	"scripts/ui/minimap.gd", "scripts/audio/sfx.gd", "scripts/ui/site_marks.gd", "scripts/ui/scoreboard.gd",
	"scripts/entities/fan_paint.gd", "scripts/ui/help_panel.gd", "scripts/ui/note_writer.gd"
]

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Whether --fog-off was given for this run.
var _asked := false
## The value of Game.fog_off that the match was launched with (put back after every flip).
var _launched := false
## Frames of the match seen so far (the second half runs at SECOND_HALF_FRAME).
var _frames := 0
## True once the second half has run (it runs once).
var _done := false


## main.gd calls this once, right after the World is built. Runs the first half of the checks; the second
## half runs at frame SECOND_HALF_FRAME (see _physics_process).
func setup(w: World) -> void:
	world = w
	_asked = Game.opt("fog-off") != null and str(Game.opt("fog-off")) != "false" and str(Game.opt("fog-off")) != "0"
	_launched = Game.fog_off
	print("fog_check: seat=%s, --fog-off %s" % [world.human_role, "given" if _asked else "not given"])
	_check("Game.fog_off follows --fog-off", _launched == _asked, str(_launched))
	_check_identity()
	_refresh_all()
	_check_switches()
	_check_drawn("tick 0")
	_check_pairs("tick 0")
	_check_rules("tick 0")
	if Game.opt("force-hud", false):
		_check_hud()
	var marker := str(Game.opt("settings-check", ""))
	if marker != "":
		_check_settings(marker)
	_check_sources()


## Counts the frames of the match. At SECOND_HALF_FRAME it runs the second half, prints the digest line and quits.
func _physics_process(_delta: float) -> void:
	if world == null or _done:
		return
	_frames += 1
	if _frames < SECOND_HALF_FRAME:
		return
	_done = true
	_check_drawn("frame %d" % _frames)
	_check_pairs("frame %d" % _frames)
	_check_rules("frame %d" % _frames)
	_print_digest()
	print("fog_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## True with a human seat (a pilot or an Admiral): the team the screen shows is the human's.
func _seated() -> bool:
	return world.human != null and world.viewer_team >= 0


## One vision update and one visibility pass for both teams, as a tick does, but with no tick in between.
func _refresh_all() -> void:
	for t in 2:
		world.vision.update_team(t, world._viewers(t))
		world.visibility.refresh(t)


## The number of live units the screen does not draw right now.
func _count_hidden() -> int:
	var hidden := 0
	for u in world.units:
		if is_instance_valid(u) and u.alive and not u.visible:
			hidden += 1
	return hidden


## The human's team is the viewer team and is never -1 with a human seat (the end screen, the kill feed and the
## rally ring read it).
func _check_identity() -> void:
	if not _seated():
		return
	_check("the viewer team is the human's team (never -1 with a human seat)", world.viewer_team == world.human_team and world.viewer_team >= 0, "viewer %d, human %d" % [world.viewer_team, world.human_team])


## The switches that draw the fog, as launched: the fog picture is shown only while No fog is off, and the
## shot and effect copies of the viewer team are -1 (see everything) while it is on.
func _check_switches() -> void:
	var fv := world.get_node("FogView") as FogView
	var want_shown := world.viewer_team >= 0 and not _launched
	_check("the fog picture is %s (No fog %s)" % ["shown" if want_shown else "hidden", "on" if _launched else "off"], fv.visible == want_shown, "visible %s" % str(fv.visible))
	var want_copy := -1 if _launched else world.viewer_team
	_check("the shot and effect viewer copies are %d (No fog %s)" % [want_copy, "on" if _launched else "off"], world.effects.viewer_team == want_copy and world.projectiles.viewer_team == want_copy, "effects %d, projectiles %d" % [world.effects.viewer_team, world.projectiles.viewer_team])


## With a human seat: the number of live units not drawn. With No fog on it must be 0; off, the enemy units that
## are out of sight are not drawn (at the start every enemy is unseen).
func _check_drawn(tag: String) -> void:
	if not _seated():
		return
	var hidden := _count_hidden()
	if _launched:
		_check("%s with No fog on every live unit is drawn" % tag, hidden == 0, "%d hidden" % hidden)
	else:
		_check("%s with No fog off the enemy units out of sight are not drawn" % tag, hidden > 0, "%d hidden" % hidden)


## A fingerprint of the vision and the masks: the lit cells (as lit now, not the raw stamps), the explored cells,
## and every unit's uid and masks, as one hash per array.
func _digest() -> Dictionary:
	var out := {}
	var v := world.vision
	for t in 2:
		var l: PackedInt32Array = v.lit[t]
		var s: int = v.stamp[t]
		var bits := PackedByteArray()
		bits.resize(l.size())
		for i in l.size():
			bits[i] = 1 if l[i] == s else 0
		out["lit%d" % t] = hash(bits)
		out["explored%d" % t] = hash(v.explored[t])
	var m := PackedInt32Array()
	for u in world.units:
		if is_instance_valid(u):
			m.append(u.uid)
			m.append(u.visible_mask)
			m.append(u.seen_mask)
	out["masks"] = hash(m)
	return out


## The first key of `a` whose value differs from `b`'s, or "" when none does.
func _diff(a: Dictionary, b: Dictionary) -> String:
	for k in a.keys():
		if a[k] != b.get(k):
			return str(k)
	return ""


## The vision and the masks with No fog on and off. The states are read one after the other with one refresh each
## and no tick in between, so ordinary movement cannot look like a difference. With a human seat the units not drawn
## are counted in both states: on, none; off, the fog is back.
func _check_pairs(tag: String) -> void:
	var one := PackedByteArray([0, 1, 0])
	var two := PackedByteArray([1, 0, 0])
	_check("%s the digest sees a changed byte (control)" % tag, hash(one) != hash(two) and hash(one) == hash(PackedByteArray([0, 1, 0])), "")
	var digest := {}
	var hidden := {}
	for on: bool in [true, false]:
		var key := "on" if on else "off"
		Game.fog_off = on
		_refresh_all()
		digest[key] = _digest()
		hidden[key] = _count_hidden()
	Game.fog_off = _launched
	_refresh_all()
	var back := _digest()
	var diff: String = _diff(digest["on"], digest["off"])
	_check("%s the vision and the masks are the same with No fog on and off" % tag, diff == "", "first difference: '%s'" % diff)
	diff = _diff(back, digest["on"])
	_check("%s the vision and the masks are the same as launched after the flips" % tag, diff == "", "first difference: '%s'" % diff)
	if _seated():
		_check("%s with No fog on every live unit is drawn after the flip" % tag, int(hidden["on"]) == 0, "%d hidden" % int(hidden["on"]))
		_check("%s with No fog off the fog is back after the flip" % tag, int(hidden["off"]) > 0, "%d hidden" % int(hidden["off"]))
		_check("%s the units drawn are as launched after the flips" % tag, _count_hidden() == (int(hidden["on"]) if _launched else int(hidden["off"])), "%d hidden" % _count_hidden())


## The rules did not move: a ward on a spot the team cannot see is refused with No fog on and off, and an enemy unit
## answers visible_to the same way in both states (the human's placing rules and the AI read the same vision).
func _check_rules(tag: String) -> void:
	if not _seated():
		return
	var vt := world.viewer_team
	var foe := world.mothership(1 - vt)
	if foe == null:
		_check("%s the enemy mothership exists" % tag, false, "no mothership for team %d" % (1 - vt))
		return
	var p := foe.global_position
	var foe_unit: Unit = null
	for u in world.units:
		if is_instance_valid(u) and u.alive and u.team != vt:
			foe_unit = u
			break
	var seen := {}
	var ward := {}
	for on: bool in [true, false]:
		var key := "on" if on else "off"
		Game.fog_off = on
		seen[key] = world.vision.is_visible(vt, p)
		ward[key] = world.command.ward_blocker(vt, p)
		if foe_unit != null:
			seen[key + "_unit"] = foe_unit.visible_to(vt)
	Game.fog_off = _launched
	for key in ["on", "off"]:
		_check("%s with No fog %s the enemy mothership's spot is not seen and a ward there is refused" % [tag, key], not bool(seen[key]) and str(ward[key]) != "", "seen %s, '%s'" % [str(seen[key]), str(ward[key])])
	if foe_unit != null:
		_check("%s an enemy unit answers visible_to the same with No fog on and off" % tag, seen["on_unit"] == seen["off_unit"], "on %s, off %s" % [str(seen["on_unit"]), str(seen["off_unit"])])


## The screen, only with --force-hud: the FOG OFF tag beside the test tags, the enemy turret counts of the top bar and
## the minimap's fog picture follow the option. The spectator has no fog, so it gets no tag.
func _check_hud() -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("the HUD exists for the fog check", false, "no Hud node (use --force-hud)")
		return
	var vt := world.viewer_team
	for on: bool in [true, false]:
		Game.fog_off = on
		hud.top_bar.refresh(world)
		var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
		var want := on and vt >= 0
		var has := tags.text.contains("FOG OFF")
		_check("the FOG OFF tag with No fog %s" % ("on" if on else "off"), has == want, "visible %s, text '%s'" % [str(tags.visible), tags.text])
		if vt >= 0:
			var lanes: Dictionary = hud.top_bar._count_turrets(world, 1 - vt, vt)
			var counted := int(lanes["top"]) + int(lanes["mid"]) + int(lanes["bot"])
			var live := 0
			for tu in world.turrets:
				if is_instance_valid(tu) and tu.team == 1 - vt and tu.alive and tu.node != null:
					live += 1
			if on:
				_check("with No fog on the top bar counts every live enemy turret", counted == live, "counted %d, live %d" % [counted, live])
			else:
				_check("with No fog off the top bar counts no more than the live enemy turrets", counted <= live, "counted %d, live %d" % [counted, live])
	Game.fog_off = _launched
	hud.top_bar.refresh(world)
	var mm = hud.minimap
	_check("the minimap takes the fog picture only while No fog is off", (mm._fog_tex != null) == (vt >= 0 and not _launched), "fog texture %s" % str(mm._fog_tex != null))


## Builds a start screen (a new one for each step), presses the No fog toggle and checks the settings file. Needs
## `marker` in the user data folder's name, so the file written here is a scratch one.
func _check_settings(marker: String) -> void:
	var dir := OS.get_user_data_dir()
	if not dir.contains(marker):
		_check("settings check: the user data folder holds \"%s\"" % marker, false, "it is %s, so nothing was written" % dir)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	# Step 1: nothing remembered: the option is off and the toggle shows it.
	Game.fog_off = false
	Game._fog_off_open = true
	var screen := _new_screen()
	_check("settings: off when nothing is remembered", not Game.fog_off and not screen._fog_button.button_pressed, screen._fog_button.text)
	_check("settings: the toggle says No fog (test) and off", screen._fog_button.text == "No fog (test): off", screen._fog_button.text)
	# Step 2: press it: on, pressed, and in the file.
	screen._fog_button.pressed.emit()
	var cfg := ConfigFile.new()
	_check("settings: pressing it turns the option on", Game.fog_off and screen._fog_button.button_pressed and screen._fog_button.text == "No fog (test): ON", screen._fog_button.text)
	_check("settings: the file was written", cfg.load(Game.SETTINGS_FILE) == OK and cfg.get_value("game", "fog_off", false) == true)
	screen.free()
	# Step 3: a new run: the choice comes back.
	Game.fog_off = false
	Game._fog_off_open = true
	screen = _new_screen()
	_check("settings: the next run shows it on, as remembered", Game.fog_off and screen._fog_button.button_pressed)
	screen.free()
	# Step 4: the launch option beats the remembered choice (settled before the screen).
	Game.fog_off = false
	Game._fog_off_open = false
	screen = _new_screen()
	_check("settings: a launch option beats the remembered choice", not Game.fog_off and not screen._fog_button.button_pressed)
	screen.free()
	# Step 5: a damaged file is ignored.
	cfg.set_value("game", "fog_off", "banana")
	cfg.save(Game.SETTINGS_FILE)
	Game.fog_off = false
	Game._fog_off_open = true
	screen = _new_screen()
	_check("settings: a word instead of a yes is ignored", not Game.fog_off)
	screen.free()
	# Step 6: pressing it again turns it off and writes that.
	Game.choose_fog_off(true)
	screen = _new_screen()
	screen._fog_button.pressed.emit()
	_check("settings: pressing it again turns it off in the file too", not Game.fog_off and cfg.load(Game.SETTINGS_FILE) == OK and cfg.get_value("game", "fog_off", true) == false)
	screen.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	Game.fog_off = _launched


## A new start screen, added to this node (the caller frees it).
func _new_screen() -> StartScreen:
	var screen := (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate() as StartScreen
	add_child(screen)
	return screen


## The source scan: every script under res://scripts that names FogOff or fog_off must be one of the planned
## files (ALLOWED), and every planned file must name it (a forgotten place shows up as missing).
func _check_sources() -> void:
	var found: Array = []
	_scan("res://scripts", found)
	var stray: Array = []
	for f in found:
		if not ALLOWED.has(f):
			stray.append(f)
	var missing: Array = []
	for a in ALLOWED:
		if not found.has(a):
			missing.append(a)
	_check("only the planned scripts name FogOff or fog_off (%d found)" % found.size(), stray.is_empty(), "not planned: %s" % str(stray))
	_check("every planned script names FogOff or fog_off", missing.is_empty(), "missing: %s" % str(missing))


## Adds to `out` every .gd file under `dir` (and below) whose text names FogOff or fog_off, as a res-relative path.
func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			if text.contains("FogOff") or text.contains("fog_off"):
				out.append(dir.path_join(f).trim_prefix("res://"))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


## Prints the digest line: the fingerprint of the vision and the masks, the unit count, the node count and the next
## random number (the shared random sequence, so a node made or skipped by the option would change it).
func _print_digest() -> void:
	var d := _digest()
	var nodes := get_tree().get_node_count()
	var rng := randi()
	print("fog_check: digest lit0=%d lit1=%d explored0=%d explored1=%d masks=%d units=%d nodes=%d rng=%d" % [d["lit0"], d["lit1"], d["explored0"], d["explored1"], d["masks"], world.units.size(), nodes, rng])
