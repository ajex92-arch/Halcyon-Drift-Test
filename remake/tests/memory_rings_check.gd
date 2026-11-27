extends Node
## WHAT THIS IS: the check of the test option "Show the computer's memory (test)" (MemoryRings, RT5 build U).
## With the option off nothing is listed and no node is made; with it on there is exactly one ring per record
## of the computer team's view (TeamView), a ship's ring fades as its weight falls and carries its age, and
## listing the rings changes nothing in the view.
##
## HOW IT WORKS: the match runs to frame CHECK_FRAME (2.5 game seconds), so both computer Admirals have
## thought and their views hold the starting records. Then, for the team the computer plays against the
## human: the option off (no rings, no node under the top bar); the option on (the rings counted against the
## records); one made-up ship record, added to the view for the check and taken out again, whose sighting is
## moved back in time to read the fade; the view switched off for a moment (no rings); the node that
## MemoryRings.mount() keeps under the top bar; and a source scan of memory_rings.gd for anything that would
## write into the match or draw a random number. Game.show_ai_memory is put back at the end.
## The run must switch the team view on (it is off in the standard profile): without it the check says so
## and fails.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --force-hud --seed=7 --admiral-set=both:team_view=1 --test=memory_rings_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what> <detail>", then
## "memory_rings_check: N failures" last. 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=memory_rings_check.

## The frame the checks run at: 2.5 game seconds at 60 frames a second (both Admirals have thought by 1 s).
const CHECK_FRAME := 150
## Two numbers closer than this count as equal.
const TOLERANCE := 1e-4
## Words memory_rings.gd must not hold: it only reads and draws.
const FORBIDDEN := ["randi", "randf", "rng", "set_meta", "_sync(", ".think(", ".refresh(", ".reset(", "erase(", "queue_free", "world.time ="]

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Frames of the match seen so far.
var _frames := 0
## True once the checks have run (they run once).
var _done := false


## main.gd calls this once, right after the World is built. The checks run at frame CHECK_FRAME.
func setup(w: World) -> void:
	world = w


## Counts the frames of the match; at CHECK_FRAME it runs the checks, prints the result line and quits.
func _physics_process(_delta: float) -> void:
	if world == null or _done:
		return
	_frames += 1
	if _frames < CHECK_FRAME:
		return
	_done = true
	var launched: bool = Game.show_ai_memory
	_run()
	Game.show_ai_memory = launched
	print("memory_rings_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Every check, in order.
func _run() -> void:
	var teams := MemoryRings.teams_shown(world)
	_check("with a human seat the computer's team is the one shown", world.viewer_team < 0 or teams == [Rules.enemy_of(world.viewer_team)], str(teams))
	var team: int = teams[0]
	var view := TeamView.of(world, team)
	if view == null or not view.enabled() or not view._ready:
		_check("the computer team's view is on and has thought (run with --admiral-set=both:team_view=1)", false, "team %d" % team)
		return
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	# Step 1: the option off: nothing listed, and the top bar holds no rings node.
	Game.show_ai_memory = false
	_check("option off: no rings", MemoryRings.rings(world).is_empty(), "%d" % MemoryRings.rings(world).size())
	if hud != null:
		hud.top_bar.refresh(world)
		var none := hud.top_bar.get_node_or_null(MemoryRings.NODE_NAME)
		_check("option off: the top bar holds no rings node, or a hidden one", none == null or not (none as Control).visible, str(none))
	# Step 2: the option on: one ring per record, and listing them leaves the view as it was.
	Game.show_ai_memory = true
	var stamp := _stamp(view)
	var rings := MemoryRings.rings(world)
	var again := MemoryRings.rings(world)
	_check("option on: one ring per record", rings.size() == _records(view) and rings.size() > 0, "%d rings, %d records (%s)" % [rings.size(), _records(view), _kinds(rings)])
	_check("listing the rings changes nothing in the view", _stamp(view) == stamp and again.size() == rings.size(), stamp)
	var ms_rings := 0
	for r: Dictionary in rings:
		if str(r["kind"]) == "mothership":
			ms_rings += 1
			_check("the mothership's ring is at its remembered place, at full weight", (r["pos"] as Vector2) == (view._ms["pos"] as Vector2) and is_equal_approx(float(r["weight"]), 1.0), str(r["pos"]))
	_check("exactly one mothership ring", ms_rings == 1, "%d" % ms_rings)
	# Step 3: a made-up ship record: the ring fades as the weight falls, and carries the age.
	var fade := float(view.prof.raw("memory_fade_s")) / 1000.0
	var spot := Vector2(1234.0, -567.0)
	view._ships[-1] = {"pos": spot, "hp": 1000, "si": 1, "seen": world.time, "vis": false}
	_check("a new record adds one ring", MemoryRings.rings(world).size() == rings.size() + 1, "%d" % MemoryRings.rings(world).size())
	var last_alpha := 2.0
	for step: Array in [[0.0, 1.0], [0.25, 0.75], [0.5, 0.5], [1.0, 0.0], [2.0, 0.0]]:
		var age := fade * float(step[0])
		(view._ships[-1] as Dictionary)["seen"] = world.time - age
		var ring := _ring_at(spot)
		var want_alpha := lerpf(MemoryRings.MIN_ALPHA, 1.0, float(step[1]))
		var fine: bool = not ring.is_empty() and absf(float(ring["weight"]) - float(step[1])) < TOLERANCE and absf(float(ring["alpha"]) - want_alpha) < TOLERANCE and absf(float(ring["age"]) - age) < 0.01
		_check("a ship seen %d s ago: weight %.2f, opacity %.2f" % [int(age), float(step[1]), want_alpha], fine and float(ring["alpha"]) <= last_alpha, str(ring))
		_check("its words are the age in seconds", MemoryRings.age_text(ring) == "%d s" % int(age), MemoryRings.age_text(ring))
		last_alpha = float(ring.get("alpha", 0.0))
	var faded := _ring_at(spot)
	_check("a fully faded record keeps a faint ring", is_equal_approx(float(faded["alpha"]), MemoryRings.MIN_ALPHA) and MemoryRings.MIN_ALPHA > 0.0, str(faded["alpha"]))
	_check("the ring is as big as the ship's size class says", is_equal_approx(float(faded["radius"]), MemoryRings.RADIUS_SHIP * 2.0), str(faded["radius"]))
	view._ships.erase(-1)
	_check("the made-up record is gone again", MemoryRings.rings(world).size() == rings.size() and _stamp(view) == stamp, _stamp(view))
	# Step 4: a team whose Admiral does not play from memory has no rings.
	var was := view.prof.raw("team_view")
	view.prof.set_value("team_view", 0)
	_check("team view off: no rings even with the option on", MemoryRings.rings(world).is_empty(), "%d" % MemoryRings.rings(world).size())
	view.prof.set_value("team_view", was)
	# Step 5: the node under the top bar follows the option.
	if hud != null:
		hud.top_bar.refresh(world)
		var node := hud.top_bar.get_node_or_null(MemoryRings.NODE_NAME) as MemoryRings
		_check("option on: the top bar holds the rings node, showing", node != null and node.visible and node.world == world, str(node))
		if node != null:
			_check("the node lets the mouse through and is not laid out by the bar", node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.top_level, "filter %d" % node.mouse_filter)
		var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
		_check("option on: the AI MEMORY tag shows", tags.visible and tags.text.contains("AI MEMORY"), "'%s'" % tags.text)
		Game.show_ai_memory = false
		hud.top_bar.refresh(world)
		_check("option off again: the node is hidden and the tag is gone", node != null and not node.visible and not tags.text.contains("AI MEMORY"), "'%s'" % tags.text)
		_check("still one rings node at most", hud.top_bar.find_children("*", "MemoryRings", true, false).size() <= 1)
	else:
		_check("the HUD exists for the node check", false, "no Hud node (use --force-hud)")
	# Step 6: the source scan.
	var text := FileAccess.get_file_as_string("res://scripts/ui/rts/memory_rings.gd")
	var hits: Array = []
	for word: String in FORBIDDEN:
		if text.contains(word):
			hits.append(word)
	_check("memory_rings.gd only reads and draws (source scan)", text != "" and hits.is_empty(), str(hits))


## How many records the view holds that get a ring: the ships, the mothership, the turrets, the standing posts.
func _records(view: TeamView) -> int:
	var n: int = view._ships.size() + view._turrets.size() + (0 if view._ms.is_empty() else 1)
	for lane in view._posts:
		if bool((view._posts[lane] as Dictionary)["standing"]):
			n += 1
	return n


## A fingerprint of the view: when it last updated and what it holds.
func _stamp(view: TeamView) -> String:
	return "t=%s ships=%s turrets=%s posts=%s ms=%s" % [str(view._t), str(view._ships), str(view._turrets), str(view._posts), str(view._ms)]


## How many rings of each kind (for the detail text).
func _kinds(rings: Array) -> String:
	var count := {}
	for r: Dictionary in rings:
		count[r["kind"]] = int(count.get(r["kind"], 0)) + 1
	return str(count)


## The ring at world place `spot`, or {} when there is none.
func _ring_at(spot: Vector2) -> Dictionary:
	for r: Dictionary in MemoryRings.rings(world):
		if (r["pos"] as Vector2) == spot:
			return r
	return {}
