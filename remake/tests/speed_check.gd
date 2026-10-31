extends Node
## WHAT THIS IS: the world-speed check (slow motion and the faster speeds,
## WorldSpeed). It runs a match for some game seconds and checks how the World's
## ticks follow Godot's physics frames: that a slowed world takes its tick on some
## frames only, that every tick it takes is as long as at normal speed (Godot's
## own step, 1/60 s), that Engine.time_scale is the speed above 1x and left alone
## at or below it, and that a tap on a
## key is not lost on a frame without a tick. With --speed-keys it also presses
## the backquote key and the pause key like a player and checks the speeds, the
## HUD tag and that a pause keeps the speed.
##
## HOW IT WORKS: setup() remembers the match and checks WorldSpeed on its own (the
## options, the cycle, the exact pattern of ticks). Then, every physics frame,
## _physics_process() looks at the match clock: it runs BEFORE the World each
## frame (so a key it presses lands on the frame the World reads it), which means
## a change of the clock it sees is the World's tick of the frame before. The
## change is the length of that tick. It keeps the count of frames and ticks, the
## shortest and longest tick, the step Godot hands over and a picture of the first
## frames (T = the World ticked, . = it did not). At --secs game seconds it checks
## the numbers, prints one "speed_check:" line and quits.
## --speed-keys (needs --force-hud) drives the backquote key and the pause key and
## counts ticks over windows of frames. --speed-taps (needs --auto --role=pilot
## --bot=input and a slowed start such as --slow=0.5) launches the human's ship,
## taps the repair-kit key on frames the World skips and checks the kit was used (and,
## as a control, that the same tap is lost when WorldSpeed's note of it is wiped).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=7 --secs=20 --slow=0.5 --test=speed_check
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=7 --secs=20 --test=speed_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --speed-keys --test=speed_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-admiral-ai --slow=0.5 --speed-taps --test=speed_check
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=7 --secs=20 --fast=2 --test=speed_check
##   godot --path remake --disable-vsync -- --all-ai --no-admiral-ai --seed=7 --secs=20 --fast=2 --rate --test=speed_check
## --secs is the game seconds to measure (default 20; with --rate the real seconds).
## --fixed-fps 60 makes every frame exactly 1/60 of a second, as the determinism
## runs have it. --rate (a windowed run in real time, without --fixed-fps) prints
## the World's ticks per real second and WorldSpeed.limited() once a second.
##
## HOW TO READ THE OUTPUT: PASS or FAIL lines, the line "speed_check: slow=.. frames=..
## ticks=.. tick_min=.. tick_max=.. godot_dt=.. time_scale=.. pattern=..", and the
## last line "speed_check: N failures" (0 = every check passed). tick_min and
## tick_max are the shortest and longest World tick in seconds; they are equal
## when every tick has the same length.
##
## WHO USES IT: main.gd loads it for --test=speed_check. Apart from the key taps of
## --speed-taps and --speed-keys it only reads the match.

## The most frames one run lasts, however far the match clock has got.
const MAX_FRAMES := 12000
## How many of the first frames the pattern shows.
const PATTERN_LEN := 32
## Two lengths of time closer than this many seconds count as equal.
const TOLERANCE := 1e-9
## Frames of one window in which ticks are counted (--speed-keys).
const WINDOW := 120

## The running match (set by setup()).
var world: World
## Game seconds to measure (--secs, default 20).
var secs := 20.0
## Physics frames seen so far.
var frames := 0
## Ticks the World took, as seen from the clock (one frame late: see HOW IT WORKS).
var ticks := 0
## The match clock at the start of the last frame (seconds).
var _last_time := 0.0
## The shortest World tick seen (seconds of match clock).
var tick_min := INF
## The longest World tick seen (seconds of match clock).
var tick_max := 0.0
## The step Godot handed to the last frame (seconds).
var godot_dt := 0.0
## One letter per frame for the first frames: T = the World ticked, . = not.
var pattern := ""
## How many checks failed so far.
var fails := 0
## True for --speed-keys (the key and pause steps).
var _keys := false
## True for --speed-taps (key taps on frames without a tick).
var _taps := false
## Which step of --speed-keys or --speed-taps we are on,
var _step := 0
## and the frames since it began.
var _step_frames := 0
## Ticks counted when the current window began,
var _window_ticks := 0
## and the match clock at its start (seconds).
var _window_time := 0.0
## The human's ship (--speed-taps),
var _ship: Ship = null
## the kits it had before the tap,
var _kits_before := 0
## and the number of taps done.
var _taps_done := 0
## True during the control tap of --speed-taps: the same tap, but the note of the
## tap on the frame without a tick is wiped before the World sees it, as if
## WorldSpeed did not keep it. The tap must then be lost: proof that the check
## would notice a missing note.
var _control := false
## True once the control tap is done.
var _control_done := false
## True for --rate (ticks per real second and WorldSpeed.limited()).
var _rate := false
## The real time (milliseconds) when --rate began,
var _rate_start := -1
## the real time at its last printed second,
var _rate_ms := -1
## the ticks counted at that second,
var _rate_ticks := 0
## how many printed seconds limited() answered true in,
var _rate_limited := 0
## and how many seconds were printed.
var _rate_seconds := 0


## main.gd calls this once, right after the World is built. Check WorldSpeed on its
## own, set the run up for the key and tap modes, and run before the World each frame.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 20.0))
	_keys = bool(Game.opt("speed-keys", false))
	_taps = bool(Game.opt("speed-taps", false))
	_rate = bool(Game.opt("rate", false))
	process_physics_priority = -100
	Input.use_accumulated_input = false
	if _keys:
		process_mode = Node.PROCESS_MODE_ALWAYS
	_check_world_speed_alone()
	if _taps:
		var h := world.human
		world.minion_director.next_wave = INF
		h.credits = 5000.0
		h.buy_hull("fighter", world.teams[0])
		for i in 3:
			h.buy_kit()
		_ship = world.launch(h)
		_ship.global_position = Vector2(9000, MapLayout.CY)
		_ship.velocity = Vector2.ZERO


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## How many ticks a WorldSpeed with speed `f` takes in `n` frames, and the first
## frames as a picture.
func _run_alone(f: float, n: int) -> Array:
	var ws := WorldSpeed.new()
	# A throwaway: it must never change Godot's global speed numbers.
	ws.touches_engine = false
	ws.set_factor(f)
	var count := 0
	var pic := ""
	for i in n:
		var t := ws.step()
		if t:
			count += 1
		if i < 12:
			pic += "T" if t else "."
	return [count, pic]


## WorldSpeed on its own: the launch option, the key's cycle, the tag and the
## exact pattern of ticks (no Godot frames involved).
func _check_world_speed_alone() -> void:
	var ws := WorldSpeed.new()
	ws.touches_engine = false
	_check("a new match is at normal speed", ws.factor == 1.0 and not ws.is_slow() and ws.tag() == "", "%s '%s'" % [ws.label(), ws.tag()])
	var seen := []
	for i in 4:
		ws.cycle()
		seen.append(ws.factor)
	_check("the key cycles 1x -> 0.75x -> 0.5x -> 1x -> 0.75x", seen == [0.75, 0.5, 1.0, 0.75], str(seen))
	ws.set_factor(0.75)
	_check("the tag says SPEED 0.75x", ws.tag() == "SPEED 0.75x", ws.tag())
	ws.set_factor(0.5)
	_check("the tag says SPEED 0.5x", ws.tag() == "SPEED 0.5x", ws.tag())
	for pair: Array in [["0.5", 0.5], ["0.75", 0.75], ["1", 1.0], ["banana", 1.0], ["2", 1.0], ["0", 1.0], ["true", 1.0]]:
		var o := WorldSpeed.new()
		o.touches_engine = false
		o.set_from_option(str(pair[0]))
		_check("--slow=%s gives speed %s" % [pair[0], pair[1]], o.factor == float(pair[1]), str(o.factor))
	# --fast takes any number from 1 to 2, so a determinism run can try one.
	for pair: Array in [["2", 2.0], ["1.5", 1.5], ["1", 1.0], ["3", 1.0], ["0.5", 1.0], ["banana", 1.0]]:
		var o := WorldSpeed.new()
		o.touches_engine = false
		o.set_from_fast_option(str(pair[0]))
		_check("--fast=%s gives speed %s" % [pair[0], pair[1]], o.factor == float(pair[1]), str(o.factor))
	# At 1x and above every frame takes a tick; below it, the share of the speed.
	for f: float in [1.0, 0.75, 0.5, 2.0, 1.5]:
		var want := int(1000.0 * minf(f, 1.0))
		var r := _run_alone(f, 1000)
		_check("at %sx the World takes %d ticks in 1000 frames (%s...)" % [str(f), want, r[1]], int(r[0]) == want, str(r[0]))
	_check("the first frame of a slowed match takes a tick", str(_run_alone(0.5, 4)[1]).begins_with("T") and str(_run_alone(0.75, 4)[1]).begins_with("T"))
	# The speed lists and the order words agree, and set_hundredths takes only those.
	var lists_agree := true
	for h: int in WorldSpeed.HUNDREDTHS:
		var hf: float = WorldSpeed.HUNDREDTHS[h]
		var offered := WorldSpeed.STEPS.has(hf) or WorldSpeed.FAST_STEPS.has(hf)
		var h_ws := WorldSpeed.new()
		h_ws.touches_engine = false
		lists_agree = lists_agree and h_ws.set_hundredths(h) == offered and (not offered or h_ws.factor == hf)
	for f: float in WorldSpeed.STEPS + WorldSpeed.FAST_STEPS:
		lists_agree = lists_agree and WorldSpeed.HUNDREDTHS.values().has(f)
	var odd := WorldSpeed.new()
	odd.touches_engine = false
	_check("FAST_STEPS, STEPS and HUNDREDTHS agree; set_hundredths takes only an offered speed", lists_agree and not odd.set_hundredths(137) and odd.factor == 1.0, str(WorldSpeed.FAST_STEPS))
	# A faster speed raises the engine's two numbers together and puts back what was
	# there before (a launch option --speed=N sets the time scale first).
	var ticks_before := Engine.physics_ticks_per_second
	var scale_before := Engine.time_scale
	var real := WorldSpeed.new()
	real.set_factor(2.0)
	_check("2x asks the engine for 120 ticks a second and a time scale of 2", Engine.physics_ticks_per_second == 120 and Engine.time_scale == 2.0, "%d, %s" % [Engine.physics_ticks_per_second, str(Engine.time_scale)])
	_check("2x: every frame ticks and the counter stays at 0", real.step() and real.step() and real._acc == 0.0)
	real.set_factor(1.5)
	_check("1.5x asks for 90 ticks a second and a time scale of 1.5", Engine.physics_ticks_per_second == 90 and Engine.time_scale == 1.5, "%d, %s" % [Engine.physics_ticks_per_second, str(Engine.time_scale)])
	real.cycle()
	_check("the key from a faster speed goes to 1x and gives the engine's own numbers back", real.factor == 1.0 and Engine.physics_ticks_per_second == ticks_before and Engine.time_scale == scale_before, "%d, %s" % [Engine.physics_ticks_per_second, str(Engine.time_scale)])
	real.set_factor(0.5)
	_check("a slow speed leaves the engine's numbers alone (--speed=N stays)", Engine.physics_ticks_per_second == ticks_before and Engine.time_scale == scale_before)
	real.set_factor(2.0)
	real.restore_physics()
	_check("leaving the tree puts the engine's numbers back", Engine.physics_ticks_per_second == ticks_before and Engine.time_scale == scale_before)
	# The throwaway runs above switch the physics server off on their last skipped
	# frame; the match about to run needs it on.
	PhysicsServer2D.set_active(true)


## Godot calls this every physics frame, before the World.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	frames += 1
	godot_dt = dt
	var ticked := world.time != _last_time
	if ticked:
		ticks += 1
		var step := world.time - _last_time
		tick_min = minf(tick_min, step)
		tick_max = maxf(tick_max, step)
		_last_time = world.time
	if pattern.length() < PATTERN_LEN:
		pattern += "T" if ticked else "."
	if _keys and _step_keys():
		_finish()
		return
	if _taps and _step_taps():
		_finish()
		return
	if _rate:
		if _step_rate():
			_finish()
		return
	if frames >= MAX_FRAMES or (not _keys and not _taps and (world.time >= secs or world.phase != "play")):
		_finish()


## The --rate step (a windowed run in real time): once a real second it prints the
## ticks the World took in that second and what WorldSpeed.limited() says; it ends
## after --secs real seconds (default 20). True when it is done.
func _step_rate() -> bool:
	var now := Time.get_ticks_msec()
	if _rate_start < 0:
		_rate_start = now
		_rate_ms = now
		_rate_ticks = ticks
		return false
	var lim := world.speed.limited()
	if now - _rate_ms >= 1000:
		var took := ticks - _rate_ticks
		_rate_seconds += 1
		if lim:
			_rate_limited += 1
		print("rate: second %d: %d World ticks (the speed asks for %d), limited=%s, %d physics frames so far" % [_rate_seconds, took, roundi(60.0 * world.speed.factor), str(lim), frames])
		_rate_ms = now
		_rate_ticks = ticks
	if now - _rate_start >= int(secs * 1000.0) or world.phase != "play":
		print("rate: done, limited() was true in %d of %d seconds" % [_rate_limited, _rate_seconds])
		return true
	return false


## Key `code` going down and up, pushed into the window as a keyboard sends it.
func _tap_key(code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_viewport().push_input(ev, true)


## The HUD's tag line text ("" when it is hidden), after the top bar redrew it.
func _tag_text(hud: Hud) -> String:
	hud.top_bar.refresh(world)
	var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
	return tags.text if tags.visible else ""


## Start counting ticks for a window of frames.
func _begin_window() -> void:
	_window_ticks = ticks
	_window_time = world.time
	_step_frames = 0


## Check the ticks counted over the finished window against speed `f`.
func _end_window(what: String, f: float) -> void:
	var got := ticks - _window_ticks
	var want := f * float(_step_frames)
	_check("%s: %d ticks in %d frames" % [what, got, _step_frames], absf(float(got) - want) <= 1.0, "wanted %.1f" % want)


## The --speed-keys steps; true when they are all done.
func _step_keys() -> bool:
	_step_frames += 1
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	match _step:
		# The key cycles the speed and the tag follows.
		0:
			if _step_frames < 5:
				return false
			if hud == null:
				_check("the HUD exists (use --force-hud)", false)
				return true
			_check("the match starts at normal speed, no tag", world.speed.factor == 1.0 and _tag_text(hud) == "", _tag_text(hud))
			var seen := []
			var tags := []
			for i in 3:
				_tap_key(KEY_QUOTELEFT)
				seen.append(world.speed.factor)
				tags.append(_tag_text(hud))
			_check("the backquote key steps 0.75x, 0.5x, 1x", seen == [0.75, 0.5, 1.0], str(seen))
			_check("the HUD tag follows (SPEED 0.75x, SPEED 0.5x, none)", tags == ["SPEED 0.75x", "SPEED 0.5x", ""], str(tags))
			_tap_key(KEY_QUOTELEFT)
			_step = 1
			_begin_window()
		# 0.75x: three ticks in four.
		1:
			if _step_frames >= WINDOW:
				_end_window("at 0.75x", 0.75)
				get_tree().paused = true
				_window_time = world.time
				_step = 2
				_step_frames = 0
		# Paused: the clock stands still and the speed is kept.
		2:
			if _step_frames >= 20:
				_check("paused: the match clock stands still", world.time == _window_time, "%.6f" % world.time)
				_check("paused: the speed is kept (0.75x)", world.speed.factor == 0.75, str(world.speed.factor))
				get_tree().paused = false
				_step = 3
				_begin_window()
		# Unpaused: still 0.75x.
		3:
			if _step_frames >= WINDOW:
				_end_window("after the pause, still 0.75x", 0.75)
				_tap_key(KEY_QUOTELEFT)
				_check("the key goes on to 0.5x", world.speed.factor == 0.5, str(world.speed.factor))
				_step = 4
				_begin_window()
		4:
			if _step_frames >= WINDOW:
				_end_window("at 0.5x", 0.5)
				get_tree().paused = true
				_step = 5
				_step_frames = 0
		# The key works while paused too, and the new speed holds after the unpause.
		5:
			if _step_frames >= 10:
				_tap_key(KEY_QUOTELEFT)
				_check("paused: the key still steps the speed (to 1x)", world.speed.factor == 1.0, str(world.speed.factor))
				get_tree().paused = false
				_step = 6
				_begin_window()
		6:
			if _step_frames >= 60:
				_end_window("back at 1x", 1.0)
				_check("the tick length stayed the same through all speeds", tick_max - tick_min <= TOLERANCE, "%.12f .. %.12f" % [tick_min, tick_max])
				return true
	return false


## The --speed-taps press, from _process(): a real key press arrives between two
## physics frames and counts as "just pressed" for the next one. So the press is
## made here, after a physics frame, when the World will skip the next frame
## (WorldSpeed adds the speed to its counter and ticks at 1 or more): the tap is
## then "just pressed" on a frame without a tick only. (A press made inside a
## physics frame counts from the frame after it, which is a tick: no test.)
func _process(_dt: float) -> void:
	if not _taps or world == null or _step != 0 or _step_frames < 90:
		return
	var ws := world.speed
	if _taps_done >= 3 and _control_done:
		return
	if ws._acc + ws.factor >= 1.0:
		return
	var h := world.human
	if _taps_done >= 3 and not _control:
		_control = true
		h.buy_kit()
	_ship.hull = _ship.hull_max * 0.4
	_kits_before = h.kit_count()
	Input.action_press("use_kit")
	_step = 1
	_step_frames = 0


## The --speed-taps steps; true when they are all done. _process() presses the
## repair-kit key on a frame the World will skip; here the key is let go on the next
## frame (the World's tick), and a few frames later the kit must have been used (or,
## for the control tap, not).
func _step_taps() -> bool:
	_step_frames += 1
	var h := world.human
	match _step:
		# Waiting for _process() to press the key (after the ship has settled).
		0:
			if _taps_done >= 3 and _control_done:
				return true
		1:
			Input.action_release("use_kit")
			if _control:
				world.speed._tapped.clear()
			if _step_frames >= 4:
				if _control:
					_control_done = true
					_check("control: with the note of the tap wiped the tap on a frame without a tick is lost", h.kit_count() == _kits_before, "kits %d -> %d" % [_kits_before, h.kit_count()])
				else:
					_taps_done += 1
					_check("tap %d on a frame without a tick: the kit was used" % _taps_done, h.kit_count() == _kits_before - 1, "kits %d -> %d" % [_kits_before, h.kit_count()])
				_step = 0
				_step_frames = 80
	return false

## Check the numbers, print the result line and quit.
func _finish() -> void:
	var f := world.speed.factor
	# Godot's time scale: the speed itself when it is above 1, else what the run
	# started with (1, or N under a launch option --speed=N).
	var scale_want := f if f > 1.0 else float(Game.opt("speed", 1.0))
	_check("Engine.time_scale is the speed above 1x and the run's own value otherwise", Engine.time_scale == scale_want, "%s, wanted %s" % [str(Engine.time_scale), str(scale_want)])
	_check("every World tick is as long as Godot's step", ticks > 0 and tick_max - tick_min <= TOLERANCE and absf(tick_max - godot_dt) <= TOLERANCE, "%.12f .. %.12f, Godot's step %.12f" % [tick_min, tick_max, godot_dt])
	if not _keys:
		# Above 1x every physics frame takes a tick, so the share is 1 there.
		var share := minf(f, 1.0)
		_check("the World ticked on %.0f%% of the frames" % (share * 100.0), absf(float(ticks) / float(maxi(1, frames)) - share) <= 0.01 or absf(float(ticks) - share * float(frames)) <= 2.0, "%d ticks in %d frames" % [ticks, frames])
	print("speed_check: slow=%s frames=%d ticks=%d tick_min=%.12f tick_max=%.12f godot_dt=%.12f time_scale=%.3f world_time=%.6f pattern=%s" % [
		str(Game.opt("slow", "off")), frames, ticks, tick_min, tick_max, godot_dt, Engine.time_scale, world.time, pattern])
	print("speed_check: %d failures" % fails)
	get_tree().quit()
