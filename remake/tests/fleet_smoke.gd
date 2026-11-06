extends Node
## WHAT THIS IS: a smoke test for bought ships in a real match: both teams get a full fleet
## at once (FleetFill) and the match plays on, with the pilots and the computer Admirals as
## usual. It shows that the stand-in brain flies, holds its rally, fights, and never goes home
## to shop, retreat or dock.
##
## HOW IT WORKS: on the first tick it fills both fleets, then every 30 seconds of match time it
## prints one line per team: the bought ships alive, how many are in the brain states "retreat"
## or "home" (there should be none), how far on average they are from their squads' rally spots,
## and how many bought ships died. It counts as a failure when a bought ship is ever seen docked
## or in the state "home" or "retreat", or when a team has no bought ship left at the end while it
## was never attacked. At the end it prints "fleet_smoke: N failures".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds
## remake/; --secs is the match length):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --secs=240 --test=fleet_smoke
##
## WHO USES IT: the builder of the yard, to see the stand-in fly before the computer buys.

## Seconds between two printed lines.
const EVERY := 30.0

## The running match.
var world: World
## True once the fleets were made.
var _filled := false
## How long the match has played, for the next line (seconds of match time).
var _next := EVERY
## How many bought ships the fill made.
var _made := 0
## Failures counted.
var _fails := 0
## Bought ships seen lost, per team.
var _lost := [0, 0]


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	Events.unit_killed.connect(_on_killed)


## A unit died: count it if it was a bought ship.
func _on_killed(u: Node, _info: RefCounted) -> void:
	var s := u as Ship
	if s != null and s.profile != null and s.profile.is_crew:
		_lost[s.team] = int(_lost[s.team]) + 1


## Every tick: fill once, look for the forbidden states, print every 30 s, stop at the end.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if not _filled:
		_filled = true
		_made = FleetFill.apply(world)
		print("fleet_smoke: filled %d bought ships" % _made)
	for t in 2:
		for ai: PilotAI in (world.teams[t].production.standins as Array):
			if ai.profile.state == "docked" or ai.state == "home":
				_fails += 1
				print("FAIL a bought ship is %s / %s at %.1f" % [ai.profile.state, ai.state, world.time])
	if world.time >= _next:
		_next += EVERY
		for t in 2:
			_print_team(t)
	var secs := float(Game.opt("secs", 240))
	if world.time >= secs or world.phase != "play":
		print("fleet_smoke: %d failures" % _fails)
		get_tree().quit()


## One line about team `t`'s bought ships.
func _print_team(t: int) -> void:
	var prod: Production = world.teams[t].production
	var alive := 0
	var retreating := 0
	var dist := 0.0
	for ai: PilotAI in prod.standins:
		alive += 1
		if ai.state == "retreat":
			retreating += 1
		dist += ai.profile.ship.global_position.distance_to(ai.hold_point) if ai.profile.ship != null else 0.0
	print("fleet_smoke: t=%d team=%d alive=%d retreat_state=%d mean_dist_to_hold=%d lost=%d used=%d" % [int(world.time), t, alive, retreating, int(dist / maxf(1.0, float(alive))), int(_lost[t]), prod.capacity.used()])
