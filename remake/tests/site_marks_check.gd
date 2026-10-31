extends Node
## WHAT THIS IS: the check of how a turret site's state is shown (SiteMarks, the
## state words and the fog rule) and of the reason a build is refused. It reads
## the state of the sites, so it needs no window; the drawing itself (ring styles
## and words on the map and the minimap) is looked at in pictures.
##
## HOW IT WORKS: it runs a scenario on the shared jungle node "Top Jungle North"
## by the match clock: open (word OPEN), a lone Aurelian pilot ship inside its build
## circle (AURELIAN CLEAR to Aurelian and to a spectator, OPEN to Vhorr, who
## has no unit inside and no sight there), two Vhorr pilot ships as well
## (CONTESTED 1v2, now to everyone who has a unit inside), the refusal text the
## admiral reads ("Enemy ships are too close: 2 pilot ships within 900, nearest
## ..."), then the ships go, Aurelian builds a turret (BUILDING 25s, then HELD)
## and it is destroyed (LOCKED 150s). A lane site shows nothing special (PLAIN)
## until its turret is destroyed (LOCKED). It prints one line per failed check and
## "site_marks_check: N failures" (0 = all good).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=site_marks_check
##
## WHO USES IT: main.gd loads it for --test=site_marks_check. It makes two pilot
## ships, a turret and a destroyed turret of its own; it changes nothing else.

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Where the scenario is (see _physics_process).
var step := 0
## The tick at which the current step began.
var step_tick := 0
## The shared jungle node of the scenario.
var node: ResourceNode = null
## The pilot ships the scenario made.
var ships: Array[Ship] = []
## The turret the scenario built.
var turret: Turret = null


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	node = world.node_by_id("j_top_n")


## Count a failed check and print it.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
		print("site_marks_check: FAIL %s %s" % [what, detail])


## Make a pilot ship of `team` standing at `pos`, without a driver.
func _ship(team: int, pos: Vector2) -> Ship:
	var p := PilotProfile.new("Mark%d" % world.profiles.size(), team, 20 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = pos
	s.velocity = Vector2.ZERO
	return s


## The word the map shows at the node for team `vt`.
func _word(vt: int) -> String:
	return SiteMarks.word(SiteMarks.view(world, node, vt))


## Every tick: move the scenario on one step at a time, each after a few ticks
## (the site counts who is inside every 6 ticks).
func _physics_process(_dt: float) -> void:
	if world == null or node == null or step >= 9:
		return
	if world.tick_count - step_tick < 14:
		return
	step_tick = world.tick_count
	match step:
		0:
			_check("an open shared site says OPEN to a spectator", _word(-1) == "OPEN", "('%s')" % _word(-1))
			_check("a shared site's state is open", node.site.state == TurretSite.OPEN)
			var lane_site := world.node_by_id("hal_top_outer")
			_check("a lane site that holds its turret shows nothing special", String(SiteMarks.view(world, lane_site, -1)["state"]) == SiteMarks.PLAIN)
			ships.append(_ship(Rules.HALCYON, node.global_position + Vector2(300.0, 0.0)))
		1:
			_check("one Aurelian pilot ship inside: Aurelian reads CLEAR", _word(Rules.HALCYON) == "AURELIAN CLEAR", "('%s')" % _word(Rules.HALCYON))
			_check("a spectator reads the same", _word(-1) == "AURELIAN CLEAR")
			_check("Vhorr, with no unit inside and no sight there, reads OPEN", _word(Rules.CINDER) == "OPEN", "('%s')" % _word(Rules.CINDER))
			ships.append(_ship(Rules.CINDER, node.global_position + Vector2(-300.0, 0.0)))
			ships.append(_ship(Rules.CINDER, node.global_position + Vector2(-300.0, 200.0)))
		2:
			_check("pilot ships of both teams inside: CONTESTED 1v2 to a spectator", _word(-1) == "CONTESTED 1v2", "('%s')" % _word(-1))
			_check("Aurelian, with a unit inside, reads CONTESTED 1v2", _word(Rules.HALCYON) == "CONTESTED 1v2")
			_check("Vhorr, with units inside, reads CONTESTED 1v2", _word(Rules.CINDER) == "CONTESTED 1v2")
			var why := node.build_blocker(Rules.HALCYON, "pd")
			_check("the refusal names the enemy ships and how close they are", why.begins_with("Enemy ships are too close: 2 pilot ships within 900, nearest "), "('%s')" % why)
			for s in ships:
				world.combat.kill_silently(s)
			ships.clear()
		3:
			_check("with the ships gone the site is open again", _word(-1) == "OPEN", "('%s')" % _word(-1))
			_check("the order to build is accepted", world.command.build_turret(Rules.HALCYON, node.node_id, "pd") == "")
			turret = node.slots[0] as Turret
		4:
			_check("a turret being built shows BUILDING 25s (or just under)", _word(-1).begins_with("BUILDING 2"), "('%s')" % _word(-1))
			_check("... to both teams (public)", _word(Rules.CINDER) == _word(-1))
			# Finish the turret at once for the rest of the scenario.
			turret.build_left = 0.0
		5:
			_check("a finished turret shows HELD", _word(-1) == "HELD", "('%s')" % _word(-1))
			var info := DamageInfo.new()
			info.source_team = Rules.CINDER
			world.combat.kill(turret, info)
		6:
			_check("a destroyed turret locks the site: LOCKED 150s (or just under)", _word(-1).begins_with("LOCKED 1"), "('%s')" % _word(-1))
			_check("... to both teams (public)", _word(Rules.CINDER) == _word(-1))
			# A lane turret destroyed: that site shows LOCKED, its neighbours nothing.
			var lane_site := world.node_by_id("hal_top_outer")
			world.combat.kill(lane_site.slots[0] as Turret, DamageInfo.new())
		7:
			var lane_site := world.node_by_id("hal_top_outer")
			_check("a lane site whose turret was destroyed shows LOCKED", _word_of(lane_site, -1).begins_with("LOCKED"), "('%s')" % _word_of(lane_site, -1))
			_check("the next lane site shows nothing special", String(SiteMarks.view(world, world.node_by_id("hal_top_inner"), -1)["state"]) == SiteMarks.PLAIN)
		8:
			print("site_marks_check: %d failures" % fails)
			get_tree().quit()
	step += 1


## The word the map shows at node `n` for team `vt`.
func _word_of(n: ResourceNode, vt: int) -> String:
	return SiteMarks.word(SiteMarks.view(world, n, vt))
