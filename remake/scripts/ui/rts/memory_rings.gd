class_name MemoryRings
extends Control
## WHAT THIS IS: the picture of the test option "Show the computer's memory (test)" (Game.show_ai_memory, the
## start screen's toggle or --show-ai-memory). While it is on, the human's screen shows what the computer
## Admiral remembers of its enemy: a ring at the last place of every record of its team view (TeamView). A
## ship's ring fades as the memory of where it is fades (its weight) and carries the record's age in seconds.
## It only reads the team view and draws: it writes nothing into the match and draws no random number, so
## a match plays out the same with it on or off.
##
## HOW IT WORKS: rings() lists what is to be drawn, one entry per record, and _draw() draws the list.
##   - The teams shown: the team the computer plays against the human (the enemy of the team the screen
##     watches as); both teams when nobody is seated. A team whose Admiral does not play from memory (the
##     profile switch team_view is off, as in the standard profile) has no records, so no rings.
##   - A ship record: a ring at its last seen place, sized by the ship's size class; weight 1 when seen now,
##     falling in a straight line to 0 over the profile's memory_fade_s, as TeamView.where_weight() does but
##     measured at the present moment (the record itself is brought up to date once per Admiral think).
##   - The enemy mothership record: a ring as long as the hull at its last seen place, weight 1 (it does not
##     fade); its age is the time since it was seen, or "start" while it is only known from the map.
##   - A lane turret record and a standing defense post record: a small ring, weight 1, no age (the records
##     keep no time). A post the team knows has fallen gets no ring.
##   A ring's opacity is MIN_ALPHA at weight 0 (the record still counts as existing until it goes stale) and
##   full at weight 1. The rings never ask the view to update: they read the records as the last think left
##   them, and they never make a view (a team with none yet has no rings).
## mount() is called by the HUD's top bar at every refresh: it adds the one MemoryRings node to the bar the
## first time the option is on (so with the option off there is no node at all), and hides it when the
## option goes off. The node covers the screen, lets the mouse through and is not laid out by the bar.
##
## WHO USES IT: HudTopBar, at each refresh (mount); tests/memory_rings_check.gd (rings, mount).

## A ring's opacity at weight 0.
const MIN_ALPHA := 0.15
## No ring is drawn smaller than this on the screen (pixels).
const MIN_RADIUS_PX := 7.0
## A ship ring's radius in the world, per size class (the size index 0, 1, 2 ...: RADIUS_SHIP x (1 + index)).
const RADIUS_SHIP := 90.0
## A turret ring's and a defense post ring's radius in the world.
const RADIUS_TURRET := 70.0
const RADIUS_POST := 110.0
## The name of the node mount() adds.
const NODE_NAME := "MemoryRings"

## The match whose records are drawn (set by mount()).
var world: World


## The teams whose memory is shown in match `w`: the computer's team against the human, or both teams when
## the screen watches as nobody.
static func teams_shown(w: World) -> Array:
	if w.viewer_team < 0:
		return [0, 1]
	return [Rules.enemy_of(w.viewer_team)]


## What is to be drawn in match `w` now: one Dictionary per record, {"team", "kind" ("ship", "mothership",
## "turret" or "post"), "pos" (the last place, in the world), "radius" (in the world), "weight" (0 to 1),
## "age" (seconds since it was seen; -1.0 when the record keeps no time), "alpha" (the ring's opacity)}.
## Empty while the option is off. It reads the team views and changes nothing.
static func rings(w: World) -> Array:
	var out: Array = []
	if w == null or not Game.show_ai_memory:
		return out
	for t: int in teams_shown(w):
		if not w.has_meta("team_view_%d" % t):
			continue   # no Admiral has made this team's view: nothing is remembered
		var view := TeamView.of(w, t)
		if view == null or not view.enabled():
			continue
		var fade := float(view.prof.raw("memory_fade_s")) / 1000.0
		for id in view._ships:
			var rec: Dictionary = view._ships[id]
			var age := maxf(0.0, w.time - float(rec["seen"]))
			var weight := clampf(1.0 - age / fade, 0.0, 1.0) if fade > 0.0 else 0.0
			out.append(_ring(t, "ship", rec["pos"] as Vector2, RADIUS_SHIP * float(1 + int(rec["si"])), weight, age))
		if not view._ms.is_empty():
			var seen := float(view._ms["seen"])
			out.append(_ring(t, "mothership", view._ms["pos"] as Vector2, float(view._ms["half_len"]), 1.0, (w.time - seen) if seen >= 0.0 else -1.0))
		for id in view._turrets:
			out.append(_ring(t, "turret", (view._turrets[id] as Dictionary)["pos"] as Vector2, RADIUS_TURRET, 1.0, -1.0))
		for lane in view._posts:
			var post: Dictionary = view._posts[lane]
			if bool(post["standing"]):
				out.append(_ring(t, "post", post["pos"] as Vector2, RADIUS_POST, 1.0, -1.0))
	return out


## One entry of rings().
static func _ring(team: int, kind: String, pos: Vector2, radius: float, weight: float, age: float) -> Dictionary:
	return {"team": team, "kind": kind, "pos": pos, "radius": radius, "weight": weight, "age": age, "alpha": lerpf(MIN_ALPHA, 1.0, weight)}


## Keep the one MemoryRings node under `host` (the HUD's top bar) in step with the option: made the first
## time the option is on, shown while it is on, hidden while it is off. Returns the node, or null when there
## is none (the option was never on).
static func mount(host: Node, w: World) -> MemoryRings:
	var have := host.get_node_or_null(NODE_NAME) as MemoryRings
	if not Game.show_ai_memory:
		if have != null:
			have.visible = false
		return have
	if have == null:
		have = MemoryRings.new()
		have.name = NODE_NAME
		have.top_level = true
		have.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(have)
	have.world = w
	have.visible = true
	return have


## Every frame while it shows: cover the screen and draw again (the camera moves between HUD refreshes).
func _process(_delta: float) -> void:
	if not visible:
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


## Draw every ring of rings() that is on the screen, in its team's colour, with the age beside a ring that has one.
func _draw() -> void:
	if world == null or not is_instance_valid(world):
		return
	var xf := get_viewport().get_canvas_transform()
	var zoom := xf.get_scale().x
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	for r: Dictionary in rings(world):
		var at: Vector2 = xf * (r["pos"] as Vector2)
		var rad := maxf(MIN_RADIUS_PX, float(r["radius"]) * zoom)
		if at.x < -rad or at.y < -rad or at.x > screen.x + rad or at.y > screen.y + rad:
			continue
		var tint := Palette.with_alpha(Palette.team(int(r["team"])), float(r["alpha"]))
		draw_arc(at, rad, 0.0, TAU, 48, tint, 2.0, true)
		var words := age_text(r)
		if words != "":
			draw_string(font, at + Vector2(rad + 4.0, 4.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, tint)


## The words beside ring `r`: its age in whole seconds ("42 s"), "start" for a mothership only known from the
## map, nothing for a record that keeps no time.
static func age_text(r: Dictionary) -> String:
	var age := float(r["age"])
	if age >= 0.0:
		return "%d s" % int(age)
	return "start" if str(r["kind"]) == "mothership" else ""
