extends Node
## WHAT THIS IS: the check for the stern kick: on the six ships of the line (the
## hulls with a "line" entry in Handling.TABLE) the A and D keys do not slide the
## ship but kick its stern, so the nose turns left or right at a rate set per
## class (the "kick_cap" of the row), and when the key is let go the nose comes
## back to the mouse. It prints one line per hull and then
## "stern_kick_check: N failures" (0 means all is as it should be).
##
## HOW IT WORKS: it freezes the match, launches pilot ships with nobody at the
## controls and flies them through the real flight function (ShipFlight.fly, one
## 1/60 s step at a time), as tests/handling_class_check.gd does. The groups:
##   1. The data. Every hull with a "line" entry has a kick_cap above 0 and below
##      the hull's own turning speed ("turn"), a hull without one has none, a
##      launched ship carries it in Ship.f_kick_cap (0.0 when the build flies
##      without the ships-of-the-line model, Game.big_hull_flight off), and
##      Ship.kick_keys is false on every launched ship.
##   2. The kick in the flight model. With kick_keys on, a ship of each hull at
##      rest with the nose on the mouse's point and the strafe key held for 1 s
##      turns its nose to port (A, strafe +1: the rotation falls) or to
##      starboard (D, -1), the engines do not swing (the engine angle stays
##      within 0.01 radians of straight ahead: this is run with no W held, since
##      with W the assist's tilt against the slide the kick leaves may pass that),
##      a W held beside the key keeps the forward push: the speed reached in 1 s
##      is within 4% of the same run without the key; and at every step of that
##      second, with A and with D, the engines swing no more than the flight
##      assist's own tilt (ShipLineFlight.ASSIST_BIAS_MAX, read from the code,
##      plus 0.01 radians) and the forward push, the burn times the cosine of the
##      swing, is at least the cosine of that swing's limit (0.92) of the W-alone
##      run's push at the same step, with the burn itself within 1% of it. The
##      speed bar alone cannot see a partial steal: the burn stays full until the
##      engines are far across, so a ship swung 30 degrees would still pass it. The
##      little speed lost comes from the assist's tilt (W held, flight assist on:
##      the engines tilt against the slide the kick leaves, up to that limit),
##      which turns the velocity onto the new nose, as a mouse turn does; it is
##      not the engines' push being spent. Copies of the W-alone run doctored as if
##      the engines swung to 0.6 radians, and as if the push were cut by a fifth,
##      are run through the same bars to show they can fail. S held beside the key
##      brakes as without the key (the kick applies only without S: the whole
##      ship state equals the same run with kick_keys off). With kick_keys off a
##      held strafe key is the old strafe: the sideways speed and nose swing after
##      3 s equal the flight table probe's old columns at the base for two hulls.
##      Let go after 1 s, the nose comes back to the mouse's point (within 2
##      degrees, for good) in under 15 s for every hull.
##   3. The key. PlayerController sets Ship.kick_keys for the human's ship. This
##      group needs a human seat, so it runs only when the match has one (run
##      with --auto --role=pilot, and again with --role=admiral --force-hud, as
##      tests/board_hold_check.gd is run; with --all-ai there is no human and it
##      prints SKIP). It holds the keys with Input.action_press, as
##      tests/bot_pilot.gd does, and lets them go again; the settings file is
##      never written. The human's Flak Frigate with the strafe-left key held for 1
##      s turns its nose to port by an angle inside the class cap and with the
##      strafe-right key to starboard, and the nose comes back to the mouse after
##      each. (Group 3b needs no seat and runs in every run: a Flak Frigate flown
##      by a live PilotAI with the strafe key forced on never gets kick_keys and
##      flies the plain strafe.) With the Admiral board open the Admiral's ship does not kick
##      (kick_keys false, the heading holds); a pilot's ship does, even with
##      World.board_open forced on. The human's Fighter keeps strafing
##      (kick_keys false, speed to the side). Not a test of a recorded replay.
##   4. The bar. The swing in degrees after 1 s of the key (the flight table
##      probe's kick_deg, flown here the same way) sits in a band per class: 10 to
##      15 for the corvettes and the frigates, 3.5 to 6.5 for the Destroyer (about
##      5) and 1.5 to 3.5 for the Battlecruiser (about 2.5); and it falls with the
##      class (the corvettes at least the frigates, the frigates above the
##      Destroyer, the Destroyer above the Battlecruiser). A copy of the swings
##      with one hull out of its band is run through the same test to show it can
##      fail. The bands are engineering readings of the user's "about" numbers.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=1 --no-pilots --no-jungle --no-admiral-ai --test=stern_kick_check
## and for group 3 as well:
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=stern_kick_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-pilots --no-admiral-ai --force-hud --test=stern_kick_check
##
## WHO USES IT: main.gd loads it for --test=stern_kick_check. It changes only
## units of a frozen match that is thrown away, and puts back the one game option
## it flips.

## The step of the flight, in seconds (the probe's: 60 steps a second).
const DT := 1.0 / 60.0
## How far away (world units) the spot the nose is told to point at is put.
const FAR := 1000000.0
## The nose counts as back on the mouse's point within this many degrees (the
## probe's value).
const NOSE_OK_DEG := 2.0
## The longest the nose may take to come back to the mouse's point after a kick,
## in game seconds.
const RETURN_LIMIT := 15.0
## How long a kick key is held in the checks, in game seconds.
const KICK_SECS := 1.0
## The most the engines may swing off straight ahead during a kick, in radians:
## the flame does not swing.
const SWIVEL_STILL := 0.01
## How much less speed a ship may reach in a second of W when A is held beside it,
## as a share of the speed without the key. With W held the flight assist tilts
## the engines against the slide the kick leaves and turns the velocity onto the
## new nose (as a mouse turn does), so a little speed is lost to that; the engines'
## push itself is checked apart (THRUST_KEPT, SWIVEL_SLACK, _push_kept()).
const SPEED_KEPT := 0.04
## The engines' burn (0..1, Ship.thrust_main) with W and a key held must stay at
## least this share of the burn with W alone, at every step of the second.
const THRUST_KEPT := 0.99
## With W and a key held the engines may swing the flight assist's own tilt
## (ShipLineFlight.ASSIST_BIAS_MAX) and this much more, in radians, and no more.
const SWIVEL_SLACK := 0.01
## The swing in degrees after KICK_SECS that each class may have: hull id -> [least,
## most]. The user's numbers are 10 to 15 for the Corvettes and Frigates, about 5
## for the Destroyer and about 2.5 for the Battlecruiser; the bands for "about" are
## an engineering reading.
const BAR := {
	"logistics": [10.0, 15.0], "support": [10.0, 15.0], "flak": [10.0, 15.0], "ion": [10.0, 15.0],
	"destroyer": [3.5, 6.5], "battlecruiser": [1.5, 3.5],
}
## The probe's old columns at the base for the strafe held for 3 s with the nose
## told to hold still (sideways speed in world units a second, nose swing in
## degrees), for two hulls: the Logistics Corvette and the Destroyer.
const BASE_STRAFE := {"logistics": [0.386881, 20.813752], "destroyer": [1.790317, 2.143165]}
## How close the strafe numbers must be to the base's (the same unit as each).
const STRAFE_TOL := 0.01

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## Where the ships are flown: open ground between the lanes.
var _home := Vector2.ZERO
## How many ships have been put away, so each gets its own far spot.
var _put_away := 0
## True while the live group (group 3) runs: the match is not frozen then.
var _live := false
## Which step of the live group is running (see _physics_process).
var _step := 0
## The seconds since the live step began.
var _step_t := 0.0
## The human's ship in the live group.
var _ship: Ship
## The match's camera (the live group parks it to aim the mouse).
var _cam: CameraRig
## The HUD (found once it exists; the Admiral run only).
var _hud: Hud
## The nose's angle when the live step began (radians).
var _mark := 0.0
## Which way the live step's key kicks: 1 for strafe left (A), -1 for strafe right.
var _side := 1.0


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	if world.human == null:
		print("stern_kick_check: SKIP group 3 (the key): the match has no human seat")
		world.set_physics_process(false)
		_run.call_deferred()
		return
	# A human seat: the live group runs first, with the match going, then the
	# frozen groups.
	_live = true
	_cam = w.camera
	process_physics_priority = 100
	world.minion_director.next_wave = INF
	world.teams[0].facilities["frigate"] = true
	world.human.credits = 6000.0
	var err := world.human.buy_hull("flak", world.teams[0])
	if err != "":
		_expect(false, "the human can buy a Flak Frigate: %s" % err)
		_live = false
		world.set_physics_process(false)
		_run.call_deferred()


## Run every frozen group of checks, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_check_data()
	_check_kick_flight()
	_check_strafe_unchanged()
	_check_ai_seat()
	_check_kick_return()
	_check_bar()
	print("stern_kick_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("stern_kick_check: FAIL %s" % what)


## Launch a pilot ship of hull `hid` for team 0 with nobody at the controls.
func _launch(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 0, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Put ship `s` away in a far spot of its own and make it dead, so the later
## flights never meet it.
func _put_ship_away(s: Ship) -> void:
	_put_away += 1
	s.global_position = Vector2(-5000.0 - float(_put_away) * 400.0, -5000.0)
	s.alive = false
	world.registry.rebuild_hashes()


## Group 1, the data: the rows, the ships' copies and the key flag.
func _check_data() -> void:
	for hid: String in Ships.ORDER:
		var s := _launch(hid)
		if Handling.has_line(hid):
			var row: Dictionary = Handling.row(hid)
			var line: Dictionary = row["line"]
			_expect(line.has("kick_cap"), "%s has a line entry but no kick_cap" % hid)
			var cap := float(line.get("kick_cap", 0.0))
			_expect(cap > 0.0, "%s kick_cap %s is not above 0" % [hid, cap])
			_expect(cap < float(row["turn"]), "%s kick_cap %s is not below its turn %s" % [hid, cap, row["turn"]])
			_expect(s.f_line, "%s does not fly as a ship of the line" % hid)
			_expect(s.f_kick_cap == cap, "%s f_kick_cap %s, wanted its row's %s" % [hid, s.f_kick_cap, cap])
			print("stern_kick_check: hull %s kick_cap %.3f turn %.2f" % [hid, cap, float(row["turn"])])
		else:
			_expect(not Handling.row(hid).has("line"), "%s has a line entry but Handling.has_line says no" % hid)
			_expect(s.f_kick_cap == 0.0, "%s f_kick_cap %s, but it has no line entry" % [hid, s.f_kick_cap])
		_expect(not s.kick_keys, "%s was launched with kick_keys on" % hid)
		_put_ship_away(s)
	# The build without the ships-of-the-line model: no hull flies it, so no ship
	# carries a kick cap. The option goes back as it was.
	var model := Game.big_hull_flight
	Game.big_hull_flight = false
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s := _launch(hid)
		_expect(not s.f_line, "%s flies as a ship of the line with the model off" % hid)
		_expect(s.f_kick_cap == 0.0, "%s f_kick_cap %s with the model off" % [hid, s.f_kick_cap])
		_put_ship_away(s)
	Game.big_hull_flight = model

## Put ship `s` at its start: at home, nose to the right, at rest, full battery,
## controls empty (flight assist on, the face point far ahead), the stats worked
## out again and every engine and spin state cleared.
func _reset_ship(s: Ship) -> void:
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.energy.value = s.energy.max_value
	s.emp_t = 0.0
	s.recompute_stats(true)
	s.throttle = 0.0
	s.swivel = 0.0
	s.ang_vel = 0.0
	s.toe = 0.0
	s.brake_t = 0.0
	s.engine_help = false
	s.swivel_hold_t = 0.0
	s.kick_keys = false
	var c := s.controls
	c.forward = 0.0
	c.strafe = 0.0
	c.boost = false
	c.fire = false
	c.assist = true
	c.face_point = _home + Vector2(FAR, 0.0)
	c.aim_point = c.face_point


## One step: fly the ship (the real flight function), then move it by its
## velocity, as a match does when nothing is in the way.
func _step_ship(s: Ship) -> void:
	ShipFlight.fly(s, DT)
	s.global_position += s.velocity * DT


## Hull `hid` from rest with kick_keys `kick_keys`, `strafe` and `forward` held for
## `secs` seconds, the nose told to hold still: "deg" is the rotation at the end in
## degrees (negative = the nose went to port), "swivel" the largest the engine
## angle went off zero (radians), "speed" the speed at the end, "burn" the
## lowest the engines' burn (0..1) went and "pushes" the forward push (the burn
## times the cosine of the engine angle) at every step.
func _kick_run(hid: String, kick_keys: bool, strafe: float, forward: float, secs: float) -> Dictionary:
	var s := _launch(hid)
	_reset_ship(s)
	s.kick_keys = kick_keys
	s.controls.strafe = strafe
	s.controls.forward = forward
	var swivel := 0.0
	var burn := 1.0
	var pushes: Array[float] = []
	for _i in int(secs / DT + 0.5):
		_step_ship(s)
		swivel = maxf(swivel, absf(s.swivel))
		burn = minf(burn, s.thrust_main)
		pushes.append(s.thrust_main * cos(s.swivel))
	var out := {"deg": rad_to_deg(Util.wrap_angle(s.rotation)), "swivel": swivel, "speed": s.velocity.length(), "burn": burn, "pushes": pushes}
	_put_ship_away(s)
	return out


## The least, over the steps, of the forward push of run `key` as a share of the
## push of run `plain` at the same step (steps where the plain run pushes nothing
## are left out; 1.0 when none is left).
func _push_kept(key: Dictionary, plain: Dictionary) -> float:
	var a: Array = key["pushes"]
	var b: Array = plain["pushes"]
	var least := 1.0
	for i in mini(a.size(), b.size()):
		if float(b[i]) > 0.001:
			least = minf(least, float(a[i]) / float(b[i]))
	return least


## What is wrong with run `key` (W and the key `key_name` held for KICK_SECS) of
## hull `hid` against run `plain` (W alone): one text each for the speed, the
## burn, the engine swing and the forward push that fall outside their bars.
func _w_key_failures(hid: String, key_name: String, key: Dictionary, plain: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var swivel_max := ShipLineFlight.ASSIST_BIAS_MAX + SWIVEL_SLACK
	var push_min := cos(swivel_max)
	var kept := float(key["speed"]) / maxf(float(plain["speed"]), 0.0001)
	var push := _push_kept(key, plain)
	if kept < 1.0 - SPEED_KEPT:
		out.append("%s: W with %s reached only %.1f%% of the speed W alone reaches" % [hid, key_name, 100.0 * kept])
	if float(key["burn"]) < THRUST_KEPT * float(plain["burn"]):
		out.append("%s: W with %s cut the engines' burn to %.3f of %.3f" % [hid, key_name, float(key["burn"]), float(plain["burn"])])
	if float(key["swivel"]) > swivel_max:
		out.append("%s: W with %s swung the engines %.3f radians, over the assist's tilt %.3f" % [hid, key_name, float(key["swivel"]), swivel_max])
	if push < push_min:
		out.append("%s: W with %s cut the forward push to %.3f of W alone's (least allowed %.3f)" % [hid, key_name, push, push_min])
	return out


## Show the W bars can fail: a copy of `plain` as if the kick swung the engines
## 0.6 radians (the push is the cosine of that) must fail the swing bar and the
## push bar; a copy with the push cut by a fifth and the swing within the bar must
## fail the push bar alone.
func _check_w_bars_bite(hid: String, plain: Dictionary) -> void:
	var pushes: Array[float] = []
	var cut: Array[float] = []
	var steps: Array = plain["pushes"]
	for p in steps:
		pushes.append(float(p) * cos(0.6))
		cut.append(float(p) * 0.8)
	var swung := plain.duplicate()
	swung["swivel"] = 0.6
	swung["pushes"] = pushes
	var swung_texts := _w_key_failures(hid, "A", swung, plain)
	_expect(swung_texts.size() >= 2, "the W bars did not catch the engines swung to 0.6 radians (%d texts)" % swung_texts.size())
	var thin := plain.duplicate()
	thin["pushes"] = cut
	var thin_texts := _w_key_failures(hid, "A", thin, plain)
	_expect(thin_texts.size() == 1, "the W bars did not catch a forward push cut by a fifth with the swing in the bar (%d texts)" % thin_texts.size())
	print("stern_kick_check: W bars bite: engines at 0.6 rad give %d failures, a push cut by a fifth gives %d" % [swung_texts.size(), thin_texts.size()])


## Group 2a, the kick in the flight: direction, still engines, kept thrust and
## the brake coming first.
func _check_kick_flight() -> void:
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var a := _kick_run(hid, true, 1.0, 0.0, KICK_SECS)
		var d := _kick_run(hid, true, -1.0, 0.0, KICK_SECS)
		print("stern_kick_check: hull %s kick 1 s: A %.2f deg, D %.2f deg, engines off straight at most %.4f rad" % [
			hid, float(a["deg"]), float(d["deg"]), float(a["swivel"])])
		_expect(float(a["deg"]) < 0.0, "%s: A turned the nose to starboard (%.2f degrees)" % [hid, float(a["deg"])])
		_expect(float(d["deg"]) > 0.0, "%s: D turned the nose to port (%.2f degrees)" % [hid, float(d["deg"])])
		_expect(float(a["swivel"]) <= SWIVEL_STILL, "%s: the engines swung %.4f radians during the A kick" % [hid, float(a["swivel"])])
		_expect(float(d["swivel"]) <= SWIVEL_STILL, "%s: the engines swung %.4f radians during the D kick" % [hid, float(d["swivel"])])
		# W beside the key, with A and with D: the speed, the burn, the engine swing
		# and the forward push against the W-alone run.
		var w_plain := _kick_run(hid, true, 0.0, 1.0, KICK_SECS)
		if hid == "logistics":
			_check_w_bars_bite(hid, w_plain)
		for strafe: float in [1.0, -1.0]:
			var key_name := "A" if strafe > 0.0 else "D"
			var w_key := _kick_run(hid, true, strafe, 1.0, KICK_SECS)
			var kept := float(w_key["speed"]) / maxf(float(w_plain["speed"]), 0.0001)
			var push := _push_kept(w_key, w_plain)
			print("stern_kick_check: hull %s W with %s: speed %.2f against %.2f without the key (%.1f%%), engines off straight at most %.3f rad, forward push at least %.3f of W alone" % [
				hid, key_name, float(w_key["speed"]), float(w_plain["speed"]), 100.0 * kept, float(w_key["swivel"]), push])
			for what in _w_key_failures(hid, key_name, w_key, w_plain):
				_expect(false, what)
		# S beside the key: the brake wins, so the ship flies as if kick_keys were off.
		var s_on := _kick_run_moving(hid, true)
		var s_off := _kick_run_moving(hid, false)
		_expect(s_on == s_off, "%s: S with A is not the same flight with kick_keys on and off" % hid)


## Hull `hid` moving at half its top speed with S and A both held for 1 s, the
## nose told to hold still: the ship's final state (see _kick_run).
func _kick_run_moving(hid: String, kick_keys: bool) -> Array:
	var s := _launch(hid)
	_reset_ship(s)
	s.velocity = Vector2(0.5 * s.f_max, 0.0)
	s.kick_keys = kick_keys
	s.controls.strafe = 1.0
	s.controls.forward = -1.0
	for _i in int(KICK_SECS / DT + 0.5):
		_step_ship(s)
	var out := [s.global_position, s.rotation, s.ang_vel, s.velocity, s.swivel, s.toe]
	_put_ship_away(s)
	return out


## Launch a pilot ship of hull `hid` for team 0 flown by a live computer pilot's
## brain (the controller World.launch gives it, left in place).
func _launch_ai(hid: String) -> Ship:
	var p := PilotProfile.new("ai-" + hid, 0, 20 + world.profiles.size(), false)
	p.hull_id = hid
	p.role = "mid"
	world.profiles.append(p)
	world.pilot_ai[p] = PilotAI.new(world, p)
	return world.launch(p)


## Put the controls of `s` to the strafe key held alone, the nose told to hold
## still (the way _kick_run sets them).
func _hold_strafe(s: Ship) -> void:
	var c := s.controls
	c.forward = 0.0
	c.strafe = 1.0
	c.boost = false
	c.fire = false
	c.assist = true
	c.face_point = _home + Vector2(FAR, 0.0)
	c.aim_point = c.face_point


## Group 3b, the computer pilot's seat (needs no human seat, so it runs in every
## run): a Flak Frigate flown by a live PilotAI, its brain run every step, with
## the strafe key held after the brain's turn never gets kick_keys and flies the
## old strafe: its flight equals that of the same hull with no brain and
## kick_keys off, and not the kick's.
func _check_ai_seat() -> void:
	var hid := "flak"
	var s_ai := _launch_ai(hid)
	if s_ai == null:
		_expect(false, "the computer pilot's Flak Frigate launched")
		return
	_reset_ship(s_ai)
	var s_ref := _launch(hid)
	_reset_ship(s_ref)
	var ever_kick := false
	for _i in int(KICK_SECS / DT + 0.5):
		s_ai.controller.update(s_ai, DT)
		_hold_strafe(s_ai)
		_hold_strafe(s_ref)
		ever_kick = ever_kick or s_ai.kick_keys
		_step_ship(s_ai)
		_step_ship(s_ref)
	var kicked := _kick_run(hid, true, 1.0, 0.0, KICK_SECS)
	var ai_deg := rad_to_deg(Util.wrap_angle(s_ai.rotation))
	var ref_deg := rad_to_deg(Util.wrap_angle(s_ref.rotation))
	print("stern_kick_check: computer pilot's flak, strafe held 1 s: kick_keys %s, nose %.3f degrees (no brain, keys off: %.3f; the kick would turn it %.2f)" % [ever_kick, ai_deg, ref_deg, float(kicked["deg"])])
	_expect(not ever_kick, "the computer pilot's line ship got kick_keys")
	_expect(absf(ai_deg - ref_deg) < 0.05, "the computer pilot's line ship swung its nose %.3f degrees with the strafe key held, the plain strafe %.3f" % [ai_deg, ref_deg])
	_expect(absf(ai_deg - float(kicked["deg"])) > 1.0, "the computer pilot's line ship turned its nose like a kick (%.2f degrees)" % ai_deg)
	_put_ship_away(s_ai)
	_put_ship_away(s_ref)


## Group 2b, kick_keys off: the key is the old strafe. Two hulls hold the strafe
## key for 3 s and the sideways speed and the nose swing are the base's.
func _check_strafe_unchanged() -> void:
	for hid: String in BASE_STRAFE:
		var want: Array = BASE_STRAFE[hid]
		var s := _launch(hid)
		_reset_ship(s)
		s.controls.strafe = 1.0
		var swing := 0.0
		for _i in int(3.0 / DT):
			_step_ship(s)
			swing = maxf(swing, absf(rad_to_deg(Util.wrap_angle(s.rotation))))
		var v := s.velocity.dot(Util.port_of(s.rotation))
		print("stern_kick_check: hull %s strafe 3 s with the keys off: %.4f units/s, nose %.4f degrees (base %.4f and %.4f)" % [hid, v, swing, float(want[0]), float(want[1])])
		_expect(absf(v - float(want[0])) <= STRAFE_TOL, "%s: the old strafe gives %.4f units/s, the base %.4f" % [hid, v, float(want[0])])
		_expect(absf(swing - float(want[1])) <= STRAFE_TOL, "%s: the old strafe swings the nose %.4f degrees, the base %.4f" % [hid, swing, float(want[1])])
		_put_ship_away(s)


## Group 2c, the way back: a kick of KICK_SECS and then the key let go, the nose
## told to hold the heading it started on: the seconds until it is within
## NOSE_OK_DEG of that heading for good (RETURN_LIMIT at most).
func _check_kick_return() -> void:
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s := _launch(hid)
		_reset_ship(s)
		s.kick_keys = true
		s.controls.strafe = 1.0
		for _i in int(KICK_SECS / DT + 0.5):
			_step_ship(s)
		var swung := absf(rad_to_deg(Util.wrap_angle(s.rotation)))
		s.controls.strafe = 0.0
		var last_bad := 0.0
		var steps := int(30.0 / DT)
		for i in steps:
			_step_ship(s)
			if absf(rad_to_deg(Util.wrap_angle(s.rotation))) > NOSE_OK_DEG:
				last_bad = float(i + 1) * DT
		print("stern_kick_check: hull %s kicked %.2f degrees, back on the mouse's point in %.2f s" % [hid, swung, last_bad])
		_expect(last_bad < RETURN_LIMIT, "%s: the nose took %.2f s to come back after the kick (limit %.0f s)" % [hid, last_bad, RETURN_LIMIT])
		_put_ship_away(s)

## Where the live group puts the ship: a quiet spot (the bot pilot's).
func _spot() -> Vector2:
	return Vector2(9000.0, MapLayout.CY)


## Put the live ship at rest at the quiet spot, nose to the right, the engines
## and the spin cleared, and aim the mouse straight ahead of it.
func _place_live() -> void:
	_ship.global_position = _spot()
	_ship.rotation = 0.0
	_ship.velocity = Vector2.ZERO
	_ship.ang_vel = 0.0
	_ship.swivel = 0.0
	_ship.toe = 0.0
	_ship.brake_t = 0.0
	_ship.throttle = 0.0
	_ship.controls.face_point = _spot() + Vector2(600.0, 0.0)
	_aim_mouse_at(_spot() + Vector2(2500.0, 0.0))
	_mark = 0.0


## Put the mouse a quarter of the way in from the screen's top left corner and
## park the camera so that this screen point is world point `p`: the mouse then
## points the hull at `p`.
func _aim_mouse_at(p: Vector2) -> void:
	var vs := _cam.get_viewport_rect().size
	var m := vs * Vector2(0.25, 0.25)
	var at := p - (m - vs * 0.5) / _cam.zoom.x
	_cam.look_at_point(at)
	_cam.global_position = at
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * m
	ev.global_position = ev.position
	Input.parse_input_event(ev)


## Move to the next live step, restart its clock and let go of the strafe keys.
func _next() -> void:
	_step += 1
	_step_t = 0.0
	Input.action_release("strafe_left")
	Input.action_release("strafe_right")
	Input.action_release("thrust_forward")


## The angle the live ship's nose has turned since `_mark`, in degrees (negative
## = to port).
func _turned_deg() -> float:
	return rad_to_deg(Util.wrap_angle(_ship.rotation - _mark))


## Say the live group is over: put the match's physics to sleep and run the
## frozen groups.
func _finish_live() -> void:
	Input.action_release("strafe_left")
	Input.action_release("strafe_right")
	_live = false
	world.board_open = false
	world.set_physics_process(false)
	_run.call_deferred()


## Godot calls this every tick. Runs the live group's current step (group 3).
func _physics_process(dt: float) -> void:
	if not _live:
		return
	_step_t += dt
	var first := _step_t <= dt * 1.5
	var cap_deg := 0.0
	match _step:
		0:
			# Wait for the HUD (the Admiral run needs it for the board), launch the
			# human in the Flak Frigate.
			if world.human_role == "admiral":
				_hud = get_tree().root.find_child("Hud", true, false) as Hud
				if _hud == null:
					return
			_ship = world.launch(world.human)
			if _ship == null:
				_expect(false, "the human launched the Flak Frigate")
				_finish_live()
				return
			_expect(_ship.f_line, "the human's Flak Frigate flies as a ship of the line")
			_next()
		1, 3:
			# The kick: strafe left (A) on step 1, strafe right (D) on step 3, held for
			# KICK_SECS with the mouse straight ahead.
			_side = 1.0 if _step == 1 else -1.0
			if first:
				_place_live()
				Input.action_press("strafe_left" if _side > 0.0 else "strafe_right")
			if _step_t >= KICK_SECS:
				var deg := _turned_deg()
				cap_deg = rad_to_deg(float(Handling.row("flak")["line"]["kick_cap"]) * KICK_SECS)
				print("stern_kick_check: human flak, key %s held %.1f s: nose turned %.2f degrees (cap %.2f), kick_keys %s" % [
					"A" if _side > 0.0 else "D", _step_t, deg, cap_deg, _ship.kick_keys])
				_expect(_ship.kick_keys, "the human's line ship has no kick_keys")
				_expect(deg * -_side > 1.0, "%s turned the nose %.2f degrees, the wrong way or not at all" % ["A" if _side > 0.0 else "D", deg])
				_expect(absf(deg) <= cap_deg + 0.5, "%s turned the nose %.2f degrees, over the class cap %.2f" % ["A" if _side > 0.0 else "D", absf(deg), cap_deg])
				_next()
		2, 4:
			# The way back: the key let go (by _next), the nose returns to the mouse's
			# point straight ahead.
			var err := absf(_turned_deg())
			if err <= NOSE_OK_DEG or _step_t >= RETURN_LIMIT:
				print("stern_kick_check: human flak, key let go: nose back within %.0f degrees after %.2f s" % [NOSE_OK_DEG, _step_t])
				_expect(err <= NOSE_OK_DEG, "the nose did not come back to the mouse in %.0f s (%.2f degrees off)" % [RETURN_LIMIT, err])
				_next()
		5:
			# Mode 3: the Admiral with the board open coasts and does not kick; a
			# pilot with the flag forced on still kicks.
			if first:
				_place_live()
				_ship.velocity = Vector2(60.0, 0.0)
				if world.human_role == "admiral":
					_hud._toggle_board()
					_expect(CoastController.holding(world), "the board is open but the coast does not hold the Admiral")
				else:
					world.board_open = true
				Input.action_press("strafe_left")
			if _step_t >= KICK_SECS:
				var deg := _turned_deg()
				if world.human_role == "admiral":
					print("stern_kick_check: Admiral with the board open, A held: kick_keys %s, nose turned %.3f degrees" % [_ship.kick_keys, deg])
					_expect(not _ship.kick_keys, "kick_keys is on for the Admiral with the board open")
					_expect(absf(deg) < 1.0, "the Admiral's nose turned %.2f degrees with the board open" % deg)
					_hud._toggle_board()
				else:
					print("stern_kick_check: pilot with World.board_open forced on, A held: kick_keys %s, nose turned %.2f degrees" % [_ship.kick_keys, deg])
					_expect(_ship.kick_keys, "kick_keys is off for a pilot with World.board_open forced on")
					_expect(deg < -1.0, "a pilot's nose turned %.2f degrees with World.board_open forced on" % deg)
					world.board_open = false
				_next()
		6:
			# A non-line hull: the human's Fighter keeps strafing.
			if first:
				var back := world.try_dock(_ship, true)
				_expect(back, "the Flak Frigate docked")
				var err := world.human.buy_hull("fighter", world.teams[0])
				_expect(err == "", "the human can buy a Fighter: %s" % err)
				_ship = world.launch(world.human)
				if _ship == null:
					_expect(false, "the human launched the Fighter")
					_finish_live()
					return
				_place_live()
				Input.action_press("strafe_left")
			if _step_t >= 0.6:
				var lat := _ship.velocity.dot(Util.port_of(_ship.rotation))
				print("stern_kick_check: human fighter, A held 0.6 s: port speed %.0f, kick_keys %s" % [lat, _ship.kick_keys])
				_expect(not _ship.kick_keys, "kick_keys is on for the human's Fighter")
				_expect(lat > 100.0, "the Fighter's A did not slide it to port (port speed %.0f)" % lat)
				_next()
		_:
			_finish_live()

## What is wrong with `swings` (hull id -> degrees of nose swing after KICK_SECS of
## the key): one text per hull outside its band in BAR, and per class pair out of
## order (the Corvettes at least the Frigates, the Frigates above the Destroyer, the
## Destroyer above the Battlecruiser).
func bar_failures(swings: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for hid: String in BAR:
		var deg := float(swings[hid])
		var band: Array = BAR[hid]
		if deg < float(band[0]) or deg > float(band[1]):
			out.append("%s swings %.2f degrees, outside %.1f to %.1f" % [hid, deg, float(band[0]), float(band[1])])
	var corvette := minf(float(swings["logistics"]), float(swings["support"]))
	var frigate_hi := maxf(float(swings["flak"]), float(swings["ion"]))
	var frigate_lo := minf(float(swings["flak"]), float(swings["ion"]))
	if corvette < frigate_hi:
		out.append("a corvette swings %.2f degrees, less than a frigate (%.2f)" % [corvette, frigate_hi])
	if frigate_lo <= float(swings["destroyer"]):
		out.append("a frigate swings %.2f degrees, not above the Destroyer (%.2f)" % [frigate_lo, float(swings["destroyer"])])
	if float(swings["destroyer"]) <= float(swings["battlecruiser"]):
		out.append("the Destroyer swings %.2f degrees, not above the Battlecruiser (%.2f)" % [float(swings["destroyer"]), float(swings["battlecruiser"])])
	return out


## Group 4, the bar: the same one-second kick as the probe's, for the six hulls,
## read against the bands and the class order; then a doctored copy that must
## fail.
func _check_bar() -> void:
	var swings := {}
	for hid: String in BAR:
		swings[hid] = absf(float(_kick_run(hid, true, 1.0, 0.0, KICK_SECS)["deg"]))
		print("stern_kick_check: bar: hull %s swings %.2f degrees (band %.1f to %.1f)" % [hid, float(swings[hid]), float(BAR[hid][0]), float(BAR[hid][1])])
	for what in bar_failures(swings):
		_expect(false, what)
	var doctored := swings.duplicate()
	doctored["flak"] = 20.0
	_expect(bar_failures(doctored).size() >= 1, "the bar did not catch a Flak Frigate swinging 20 degrees")
	doctored = swings.duplicate()
	doctored["battlecruiser"] = float(swings["destroyer"])
	_expect(bar_failures(doctored).size() >= 1, "the bar did not catch a Battlecruiser swinging as far as the Destroyer")
