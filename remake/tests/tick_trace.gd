extends Node
## WHAT THIS IS: the tick trace, a diagnostic for the world speed (WorldSpeed). It
## prints one line for every tick the World takes, with the match clock and a hash
## of the whole state at full precision (every live unit's place, turn, hull and velocity,
## every pilot's credits and state, both treasuries and the shot count). Two runs of
## the same seed must print the same lines, whatever the world speed; the first line
## that differs is the first tick at which they played apart.
##
## HOW IT WORKS: setup() remembers the match. Every physics frame, after the World,
## _physics_process() looks at the match clock; when it moved the World took a tick,
## and the line is printed. With --trace-units=<first>-<last> (tick numbers) it also
## prints a line for every live unit on those ticks, so the units that differ can
## be named. At --secs game seconds it prints "tick_trace: done" and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --sim-only --secs=70 --slow=0.5 --test=tick_trace
##
## HOW TO READ THE OUTPUT: "tick <n> t=<seconds> <units> <hash>" lines, and with
## --trace-units "unit <n> <uid> <kind> <team> <x> <y> <turn> <hull> <vx> <vy>" lines.
##
## WHO USES IT: main.gd loads it for --test=tick_trace. It only reads the match.

## The running match (set by setup()).
var world: World
## Game seconds to trace (--secs, default 70).
var secs := 70.0
## The match clock at the end of the last frame (seconds).
var _last_time := 0.0
## The ticks counted so far.
var _ticks := 0
## The first tick number whose units are printed (-1: none).
var _units_from := -1
## The last tick number whose units are printed.
var _units_to := -1


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 70.0))
	var range_text := str(Game.opt("trace-units", ""))
	if range_text.contains("-"):
		_units_from = int(range_text.get_slice("-", 0))
		_units_to = int(range_text.get_slice("-", 1))


## Godot calls this every physics frame, after the World.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time != _last_time:
		_last_time = world.time
		_ticks += 1
		print("tick %d t=%.6f %s" % [_ticks, world.time, _state_hash()])
		if _ticks >= _units_from and _ticks <= _units_to:
			_print_units()
	if world.time >= secs or world.phase != "play":
		print("tick_trace: done after %d ticks" % _ticks)
		get_tree().quit()


## One short text for the whole state, at full precision.
func _state_hash() -> String:
	var parts := PackedStringArray()
	for u: Unit in world.units:
		if u.alive:
			parts.append("%d:%d:%.9f,%.9f:%.9f:%.9f:%.9f,%.9f" % [u.uid, u.team, u.global_position.x, u.global_position.y, u.rotation, u.hull, u.velocity.x, u.velocity.y])
	for p: PilotProfile in world.profiles:
		parts.append("%s:%.9f:%s" % [p.callsign, p.credits, p.state])
	for t in 2:
		parts.append("tr%d:%.9f" % [t, world.teams[t].treasury])
	parts.append("proj:%d" % world.projectiles.count())
	return "%d units, %08x" % [world.units.size(), hash("|".join(parts))]


## One line for every live unit (for the ticks asked for with --trace-units).
func _print_units() -> void:
	for u: Unit in world.units:
		if u.alive:
			print("unit %d %d %d %d %.9f %.9f %.9f %.9f %.9f %.9f" % [_ticks, u.uid, u.kind, u.team, u.global_position.x, u.global_position.y, u.rotation, u.hull, u.velocity.x, u.velocity.y])
