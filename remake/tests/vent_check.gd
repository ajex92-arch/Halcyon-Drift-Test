extends Node
## WHAT THIS IS: the check of the Vent action: the pilot's key that clears the battery
## faster while the ship can only move. It prints one line per case and then
## "vent_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it freezes the match, launches real ships, presses Vent through the ship's own
## controls (`controls.vent`, the edge the key sets) and steps the ship one tick at a time
## (Ship.sim_update()). It checks:
##   - (a) a press on a loaded battery starts a Vent; the edge is used up;
##   - (b) during it the guns, boost and special do nothing, the zones are dark (a hit passes
##     whole and changes nothing in the shield) and the ship still turns and flies;
##   - (c) the hard part drains at twice the normal speed and the soft part refills at twice
##     the regeneration;
##   - (d) it ends exactly when the hard part is 0 and the soft part is full, never earlier,
##     never later (checked on every tick), and the guns work again afterwards;
##   - (e) a press during a lockout, with nothing to clear, with a battery that cannot refill,
##     or a second press during a Vent, does nothing;
##   - (f) a ship that starts a Vent with its trigger held stays quiet until the Vent ends,
##     and fires again after it if the trigger is still held;
##   - (g) the key row: Z (Shift+Z in key layout C) is the Vent action and the controls have
##     the edge.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=vent_check
##
## WHO USES IT: main.gd loads it for --test=vent_check; run_checks runs it. It changes only
## units of a frozen match that is thrown away.

## How close a measured number must be to the wanted one.
const TOL := 0.01
## One physics tick, in seconds.
const DT := 1.0 / 60.0
## The running match (set by setup()).
var world: World
## Where the ships stand: open ground in the middle of the mid lane.
var _home := Vector2.ZERO
## How many things have gone wrong so far.
var failures := 0


## main.gd calls this once, right after the World is built. Freeze the match and
## start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.CY - 1400.0)
	_run.call_deferred()


## Run every case, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_case_start()
	_case_during()
	_case_rates()
	_case_end()
	_case_refused()
	_case_trigger()
	_case_keys()
	print("vent_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("vent_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` (team 1) and stand it still at home, facing east, with its
## shields and battery full and not just hit.
func _ship(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 60 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.shields.fill()
	s.shields.since_hit = 999.0
	s.fill_energy()
	return s


## A Fighter with `hard` points of hard energy and `value` of soft energy, ready to vent.
func _loaded(hard: float, value: float) -> Ship:
	var s := _ship("fighter")
	s.energy.hard = hard
	s.energy.value = value
	return s


## A hit note from the ship's front.
func _note() -> DamageInfo:
	var d := DamageInfo.new()
	d.kind = Rules.W_BOLT
	d.from_pos = _home + Vector2(300.0, 0.0)
	return d


## Step `s` for `n` ticks of one sixtieth of a second.
func _tick(s: Ship, n: int = 1) -> void:
	for _i in n:
		world.time += DT
		s.sim_update(DT)


## Press Vent on `s` for one tick.
func _press(s: Ship) -> void:
	s.controls.vent = true
	_tick(s)


## True when any gun of `s` fired or is firing in the last tick.
func _shot(s: Ship) -> bool:
	for m in s.mounts:
		if m.cd > 0.0 or m.beam_firing:
			return true
	return false


## Put unit `u` away in a far corner and make it dead.
func _put(u: Unit) -> void:
	u.global_position = Vector2(-5000.0, -5000.0)
	u.alive = false
	world.registry.rebuild_hashes()


## (a) A press on a loaded battery starts a Vent and uses the edge up.
func _case_start() -> void:
	var s := _loaded(40.0, 20.0)
	_expect(not s.venting, "(a) the ship started out venting")
	_press(s)
	_expect(s.venting, "(a) a press on a loaded battery did not start a Vent")
	_expect(not s.controls.vent, "(a) the vent edge was not used up")
	_expect(s.systems_off() and s.shields.dark, "(a) a Vent leaves the systems on or the zones lit")
	print("vent_check: (a) a press on a battery with 40 hard and 20 soft started a Vent; the edge is used up; the zones are dark")
	_put(s)


## (b) During a Vent: no shot, no boost, no special, dark zones, the ship still flies.
func _case_during() -> void:
	var s := _loaded(40.0, 20.0)
	_press(s)
	s.controls.fire = true
	s.controls.aim_point = _home + Vector2(1000.0, 0.0)
	var shots := false
	for _i in 20:
		_tick(s)
		if _shot(s):
			shots = true
	_expect(s.venting, "(b) the Vent ended before the checks")
	_expect(not shots, "(b) a gun fired during the Vent")
	_expect(not s.special_ready(), "(b) the special is ready during a Vent")
	s.controls.fire = false
	s.controls.boost = true
	s.controls.forward = 1.0
	s.controls.face_point = _home + Vector2(0.0, 1000.0)
	var rot0 := s.rotation
	var pos0 := s.global_position
	for _i in 20:
		_tick(s)
	_expect(not s.boosting, "(b) the ship boosted during a Vent")
	_expect(absf(Util.wrap_angle(s.rotation - rot0)) > 0.01, "(b) the ship did not turn during a Vent")
	_expect(s.global_position.distance_to(pos0) > 1.0, "(b) the ship did not fly during a Vent")
	_expect(s.venting, "(b) the Vent ended before the hit check")
	s.controls.boost = false
	s.controls.forward = 0.0
	s.global_position = _home
	s.rotation = 0.0
	var vals0 := Array(s.shields.values)
	var took := s.take_hit(_note(), 20.0)
	_expect(took > 1.0, "(b) a hit during a Vent took %.3f, it should pass whole" % took)
	_expect(Array(s.shields.values) == vals0 and s.shields.last_blocked == 0.0, "(b) a hit during a Vent changed the shield")
	print("vent_check: (b) during a Vent: no shot in 20 ticks, no boost, no special, the ship turned and flew, a hit took %.3f whole and left the zones alone" % took)
	_put(s)


## (c) The hard part drains at twice the normal speed and the soft part refills at twice the
## regeneration.
func _case_rates() -> void:
	var s := _loaded(60.0, 10.0)
	_press(s)
	var hard0 := s.energy.hard
	var value0 := s.energy.value
	_tick(s, 30)
	_expect(s.venting, "(c) the Vent ended in half a second")
	var drop := hard0 - s.energy.hard
	var want_drop := s.energy.regen * OverloadRules.HARD_DRAIN_PER_REGEN * OverloadRules.VENT_DRAIN_MULT * DT * 30.0
	_expect(absf(drop - want_drop) < TOL, "(c) hard dropped %s in 30 ticks, wanted %s (twice the normal speed)" % [drop, want_drop])
	var rise := s.energy.value - value0
	var want_rise := s.energy.regen * OverloadRules.VENT_REFILL_MULT * DT * 30.0
	_expect(absf(rise - want_rise) < TOL, "(c) the soft part rose %s in 30 ticks, wanted %s (twice the regeneration)" % [rise, want_rise])
	_expect(absf(OverloadRules.VENT_DRAIN_MULT - 2.0) < TOL and absf(OverloadRules.VENT_REFILL_MULT - 2.0) < TOL, "(c) the vent factors are not 2")
	print("vent_check: (c) in 30 ticks of a Vent hard dropped %.3f (wanted %.3f) and the soft part rose %.3f (wanted %.3f)" % [drop, want_drop, rise, want_rise])
	_put(s)


## (d) The Vent ends exactly when the hard part is 0 and the soft part is full.
func _case_end() -> void:
	var s := _loaded(40.0, 20.0)
	_press(s)
	var ticks := 1
	var wrong := ""
	while s.venting and ticks < 3000:
		_tick(s)
		ticks += 1
		var done := s.energy.hard <= 0.0 and s.energy.value >= s.energy.max_value
		if s.venting == done:
			wrong = "tick %d: hard %s, soft %s, venting %s" % [ticks, s.energy.hard, s.energy.value, s.venting]
			break
	_expect(wrong == "", "(d) the Vent's end does not follow the battery: %s" % wrong)
	_expect(not s.venting and ticks < 3000, "(d) the Vent never ended")
	_expect(s.energy.hard <= 0.0 and s.energy.value >= s.energy.max_value, "(d) the Vent ended with hard %s and soft %s of %s" % [s.energy.hard, s.energy.value, s.energy.max_value])
	_expect(not s.shields.dark and not s.systems_off(), "(d) the zones are still dark after the Vent")
	# Guns work again.
	s.controls.fire = true
	s.controls.aim_point = _home + Vector2(1000.0, 0.0)
	var fired := false
	for _i in 10:
		_tick(s)
		if _shot(s):
			fired = true
	_expect(fired, "(d) the guns did not fire after the Vent")
	# A bigger ship vents too (a Destroyer, hard energy from real hits).
	var d := _ship("destroyer")
	d.energy.value = d.energy.max_value * 0.5
	d.energy.hard = d.energy.max_value * 0.3
	_press(d)
	var dt_ticks := 1
	while d.venting and dt_ticks < 3000:
		_tick(d)
		dt_ticks += 1
	_expect(not d.venting and d.energy.hard <= 0.0 and d.energy.value >= d.energy.max_value, "(d) a Destroyer's Vent did not end clean after %d ticks" % dt_ticks)
	print("vent_check: (d) a Fighter's Vent from 40 hard and 20 soft lasted %d ticks (%.2f s) and ended on hard 0, soft full; a Destroyer's lasted %d ticks (%.2f s); guns fire after" % [ticks, float(ticks) * DT, dt_ticks, float(dt_ticks) * DT])
	_put(s)
	_put(d)


## (e) No Vent starts in a lockout, with nothing to clear or with a battery that cannot refill,
## and a second press does nothing.
func _case_refused() -> void:
	var a := _loaded(40.0, 0.0)
	a.overload_left = 3.0
	_press(a)
	_expect(not a.venting, "(e) a Vent started during a lockout")
	var b := _ship("fighter")
	_press(b)
	_expect(not b.venting, "(e) a Vent started on a clear battery")
	var c := _loaded(40.0, 20.0)
	c.energy.regen = 0.0
	_press(c)
	_expect(not c.venting, "(e) a Vent started on a battery that cannot refill")
	var d := _loaded(40.0, 20.0)
	_press(d)
	var started := int(Game.usage.get("vents_started", 0))
	var hard1 := d.energy.hard
	_press(d)
	_press(d)
	_expect(d.venting, "(e) a second press ended the Vent")
	_expect(int(Game.usage.get("vents_started", 0)) == started, "(e) a second press started another Vent")
	_expect(d.energy.hard < hard1, "(e) the Vent stopped draining after a second press")
	print("vent_check: (e) no Vent in a lockout, on a clear battery or with no regeneration; a second press changed nothing")
	_put(a)
	_put(b)
	_put(c)
	_put(d)


## (f) A ship that starts a Vent with its trigger held stays quiet until it ends, and fires again
## afterwards.
func _case_trigger() -> void:
	var s := _loaded(40.0, 20.0)
	s.controls.fire = true
	s.controls.aim_point = _home + Vector2(1000.0, 0.0)
	_press(s)
	var quiet := true
	var ticks := 0
	while s.venting and ticks < 3000:
		_tick(s)
		ticks += 1
		if s.venting and _shot(s):
			quiet = false
	_expect(quiet, "(f) a gun fired during the Vent with the trigger held")
	_expect(not s.venting, "(f) the Vent did not end")
	var fired := false
	for _i in 10:
		_tick(s)
		if _shot(s):
			fired = true
	_expect(fired, "(f) the guns stayed quiet after the Vent with the trigger still held")
	# The Bomber's run: held through a Vent, no run starts.
	var b := _ship("bomber")
	b.energy.hard = 40.0
	b.energy.value = 40.0
	b.controls.fire = true
	var started0 := int(Game.usage.get("torpedo_runs_started", 0))
	_press(b)
	var n := 0
	while b.venting and n < 3000:
		_tick(b)
		n += 1
	_expect(int(Game.usage.get("torpedo_runs_started", 0)) == started0, "(f) a torpedo run started during the Vent")
	print("vent_check: (f) a held trigger fired nothing in %d ticks of the Vent and fired after it; the Bomber started no run" % ticks)
	_put(s)
	_put(b)


## (g) The key row and the controls edge.
func _case_keys() -> void:
	var row := KeyMap.row("flying", "vent")
	_expect(not row.is_empty(), "(g) there is no flying row for vent")
	KeyMap.reset_to_defaults()
	_expect(KeyMap.effective_keys("flying", "vent") == ["Z"], "(g) the vent key is %s, not Z" % str(KeyMap.effective_keys("flying", "vent")))
	KeyMap.set_preset("home_layout", "C")
	_expect(KeyMap.effective_keys("flying", "vent") == ["Shift+Z"], "(g) under layout C the vent key is %s, not Shift+Z" % str(KeyMap.effective_keys("flying", "vent")))
	KeyMap.reset_to_defaults()
	var c := ShipControls.new()
	c.vent = true
	c.clear_edges()
	_expect(not c.vent, "(g) clear_edges() left the vent edge")
	print("vent_check: (g) the flying row 'vent' is Z, Shift+Z under layout C; the controls edge is cleared with the others")
