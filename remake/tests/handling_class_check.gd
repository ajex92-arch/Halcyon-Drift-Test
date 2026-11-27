extends Node
## WHAT THIS IS: the check that the handling table keeps its class order: the
## heavier a ship of the line, the slower and weaker it is, in every column.
## It reads the table (Handling.TABLE) and asks the real game code for a few
## launched ships.
##
## HOW IT WORKS: the six hulls with a "line" entry (the corvettes, frigates,
## destroyer and battlecruiser: Handling.has_line) are grouped by their sailing
## rate (the "rate" field: 1 is the heaviest). For every pair of hulls whose
## rates differ, the heavier one must be strictly lower than the lighter one in
## the columns top speed ("max"), engine push ("accel"), turning speed
## ("turn"), engine swivel speed ("swivel_rate"), reverse share
## ("reverse_share") and side push share ("strafe_share"). Two hulls of the
## same rate (the two corvettes, the two frigates) may sit in any order. The
## check also needs a row for every hull in Ships.ORDER. As a proof that the
## order test can fail, it runs the same test on a copy of the table with one
## heavy hull made faster than a light one and expects failures.
## A second group checks the trim, the share of a hull's flight-assist grip that
## trims sideways drift: each launched ship of the line carries its row's trim in
## Ship.f_trim, a hull without a line entry carries none, and a ship left to drift
## sideways for one second ends at exactly the speed worked out from its row's trim
## (written out beside the real flight, bit for bit; for a row at the old fixed
## share of 0.2 the old expression is compared too). A third group pins the
## corvettes' trim at the share the search over 0.0 to 1.0 ended on. A fourth
## group flies each corvette in a full circle at top speed through the real flight
## and expects the circle to be under three hull lengths; it flies the same circle
## with the side push put back to its old share and expects that to fail, so the
## check is shown able to see what it guards, and it reads the class order at the
## live rows once more.
## It prints one line per hull and then "handling_class_check: N failures"
## (0 means all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=handling_class_check
##
## WHO USES IT: main.gd loads it for --test=handling_class_check. It changes
## only units of a frozen match that is thrown away.

## The step of the flight, in seconds (the probe's: 60 steps a second).
const DT := 1.0 / 60.0
## How far away (world units) the spot the nose is told to point at is put.
const FAR := 1000000.0
## The fixed share of the grip that trimmed sideways drift before the share became
## a table field. Every row starts at it.
const OLD_TRIM := 0.2
## The trim the two corvettes' rows hold (the search ended on the common share).
const CORVETTE_TRIM := 0.2
## The sailing rate of the corvettes (the "rate" field of a row's "line" entry).
const CORVETTE_RATE := 6
## The widest circle at top speed a corvette may fly, in hull lengths: the circle
## must be under it, so exactly this many lengths fails.
const CIRCLE_LIMIT := 3.0
## The game seconds a circle is flown before it is measured (the probe's value).
const CIRCLE_SETTLE := 4.0
## The game seconds a circle is measured for (the probe's value).
const CIRCLE_SPAN := 8.0
## The corvettes' side push share before it was raised: the proof that the circle
## check can fail flies the circle with this share.
const OLD_STRAFE_SHARE := 0.41

## The columns that must be in strict class order: the table's own fields and
## the fields of a hull's "line" entry. A column is a [key, in the line entry]
## pair.
const COLUMNS := [
	["max", false], ["accel", false], ["turn", false],
	["swivel_rate", true], ["reverse_share", true], ["strafe_share", true],
]

## The running match (set by setup()).
var world: World
## How many things have gone wrong so far.
var failures := 0
## Where the circles are flown: open ground between the lanes.
var _home := Vector2.ZERO
## How many circle ships have been put away, so each gets its own far spot.
var _put_away := 0


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Run every group of checks, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_check_rows()
	_check_order()
	_check_order_can_fail()
	_check_trim_carried()
	_check_trim_flight()
	_check_corvette_trim()
	_check_corvette_circle()
	print("handling_class_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("handling_class_check: FAIL %s" % what)


## Every hull of Ships.ORDER has a row in the table.
func _check_rows() -> void:
	for hid: String in Ships.ORDER:
		_expect(Handling.TABLE.has(hid), "hull %s has no row in the handling table" % hid)


## The column order of the real table, with a line printed for each hull.
func _check_order() -> void:
	for hid: String in Ships.ORDER:
		if Handling.has_line(hid):
			var row: Dictionary = Handling.row(hid)
			var line: Dictionary = row["line"]
			print("handling_class_check: hull %s rate %d max %.0f accel %.0f turn %.2f swivel %.2f reverse %.2f side %.3f" % [
				hid, int(line["rate"]), float(row["max"]), float(row["accel"]), float(row["turn"]),
				float(line["swivel_rate"]), float(line["reverse_share"]), float(line["strafe_share"])])
	for what in order_failures(Handling.TABLE):
		_expect(false, what)


## The order test is able to fail: take a copy of the table, make the
## Battlecruiser faster than the Destroyer, and the test must say so.
func _check_order_can_fail() -> void:
	var table: Dictionary = Handling.TABLE.duplicate(true)
	table["battlecruiser"]["max"] = float(table["destroyer"]["max"]) + 1.0
	_expect(order_failures(table).size() == 1, "the order test did not catch a Battlecruiser faster than the Destroyer")
	table = Handling.TABLE.duplicate(true)
	table["flak"]["line"]["reverse_share"] = float(table["logistics"]["line"]["reverse_share"])
	_expect(order_failures(table).size() == 2, "the order test did not catch a Frigate reversing as hard as a Corvette")


## What is wrong with the class order of `table` (a table shaped like
## Handling.TABLE), one text per hull pair and column that is out of order.
## A hull pair of the same rate is not tested.
func order_failures(table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Array[String] = []
	for hid: String in Ships.ORDER:
		if table[hid].has("line"):
			ids.append(hid)
	for heavy in ids:
		for light in ids:
			var rate_h := int(table[heavy]["line"]["rate"])
			var rate_l := int(table[light]["line"]["rate"])
			if rate_h >= rate_l:
				continue
			for col in COLUMNS:
				var column: String = col[0]
				var h := _value(table[heavy], column, col[1])
				var l := _value(table[light], column, col[1])
				if not h < l:
					out.append("%s (rate %d) is not strictly below %s (rate %d) in %s: %s against %s" % [heavy, rate_h, light, rate_l, column, h, l])
	return out


## The number of column `key` of hull row `row`, from its "line" entry when
## `in_line` is true.
func _value(row: Dictionary, key: String, in_line: bool) -> float:
	return float(row["line"][key]) if in_line else float(row[key])

## Launch a pilot ship of hull `hid` for team 0 with nobody at the controls.
func _launch(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 0, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Each launched ship of the line carries its row's trim in f_trim (and flies
## as a ship of the line); a hull without a line entry carries none.
func _check_trim_carried() -> void:
	for hid: String in Ships.ORDER:
		var s := _launch(hid)
		if Handling.has_line(hid):
			var want := float(Handling.row(hid)["line"]["trim"])
			_expect(s.f_line, "%s does not fly as a ship of the line" % hid)
			_expect(s.f_trim == want, "%s f_trim %s, wanted its row's trim %s" % [hid, s.f_trim, want])
			_expect(want >= 0.0 and want <= 1.0, "%s trim %s is outside 0..1" % [hid, want])
		else:
			_expect(not s.f_line, "%s flies as a ship of the line without a line entry" % hid)
			_expect(s.f_trim == 0.0, "%s f_trim %s, but it has no line entry" % [hid, s.f_trim])
		s.alive = false


## One second of sideways drift for every ship of the line: the velocity after
## 60 steps of the real flight equals, to the last bit, the one worked out here
## from the row's trim. For a row still at the old fixed share (OLD_TRIM) the
## trim factor is also compared with the old expression.
func _check_trim_flight() -> void:
	for hid: String in Ships.ORDER:
		if not Handling.has_line(hid):
			continue
		var s := _launch(hid)
		var trim := float(Handling.row(hid)["line"]["trim"])
		if is_equal_approx(trim, OLD_TRIM):
			_expect(exp(-s.f_assist * s.f_trim * DT) == exp(-s.f_assist * OLD_TRIM * DT), "%s trim factor differs from the old one" % hid)
		s.global_position = Vector2(MapLayout.CX, MapLayout.H * 0.3)
		s.rotation = 0.0
		s.velocity = Vector2(0.0, 100.0)
		s.ang_vel = 0.0
		s.swivel = 0.0
		var c := s.controls
		c.forward = 0.0
		c.strafe = 0.0
		c.boost = false
		c.assist = true
		c.face_point = s.global_position + Vector2(FAR, 0.0)
		var want := Vector2(0.0, 100.0)
		var f := Vector2.from_angle(0.0)
		for _i in 60:
			ShipFlight.fly(s, DT)
			var lat := want - f * want.dot(f)
			want = f * want.dot(f) + lat * exp(-s.f_assist * trim * DT)
			want *= exp(-0.018 * DT)
		_expect(s.velocity == want, "%s sideways drift after 1 s is %s, the trim %s gives %s" % [hid, s.velocity, trim, want])
		print("handling_class_check: hull %s trim %s sideways speed 100 -> %.6f after 1 s" % [hid, trim, s.velocity.y])
		s.alive = false

## The corvettes' trim is the share their rows hold today (CORVETTE_TRIM). A
## larger share keeps the speed in a turn and so makes the circle at top speed
## wider, and no share from 0.0 to 1.0 brings it under three hull lengths, so the
## corvettes keep the common share until another number of the row can. The
## class order check must still hold with these rows.
func _check_corvette_trim() -> void:
	for hid: String in ["logistics", "support"]:
		var trim := float(Handling.row(hid)["line"]["trim"])
		_expect(trim == CORVETTE_TRIM, "%s trim %s, wanted %s" % [hid, trim, CORVETTE_TRIM])
	_expect(order_failures(Handling.TABLE).is_empty(), "the class order broke with the corvettes' trim")


## Every corvette (a hull whose line entry has the corvettes' sailing rate) flies
## a full circle at top speed through the real flight, and the circle must be under
## CIRCLE_LIMIT hull lengths. Then the same circle is flown with the side push put
## back to its old share and must come out at CIRCLE_LIMIT lengths or more, which
## shows the check can see what it guards. The class order is read once more at
## the live rows.
func _check_corvette_circle() -> void:
	for hid: String in Ships.ORDER:
		if not _is_corvette(hid):
			continue
		var length := float(Ships.HULLS[hid]["length"])
		var s := _launch(hid)
		var c := circle_run(s)
		_put_ship_away(s)
		var lengths := float(c["d"]) / length
		var held := 100.0 * float(c["v"]) / s.f_max
		print("handling_class_check: hull %s circle %.0f units = %.2f hull lengths, holds %.0f%% of top speed (limit %.1f)" % [
			hid, float(c["d"]), lengths, held, CIRCLE_LIMIT])
		_expect(lengths < CIRCLE_LIMIT, "hull %s circles at top speed in %.2f hull lengths, the limit is under %.1f" % [hid, lengths, CIRCLE_LIMIT])
		var old := _launch(hid)
		_reset_ship(old)
		var live := old.f_accel * float(Handling.row(hid)["line"]["strafe_share"])
		_expect(is_equal_approx(old.f_strafe, live), "hull %s side push %s is not its row's share of the engine push %s" % [hid, old.f_strafe, live])
		var o := circle_run(old, OLD_STRAFE_SHARE)
		_put_ship_away(old)
		var old_lengths := float(o["d"]) / length
		print("handling_class_check: hull %s circle with the old side push %.2f hull lengths" % [hid, old_lengths])
		_expect(old_lengths >= CIRCLE_LIMIT, "the circle check cannot see the side push: hull %s with the old share circles in %.2f hull lengths, under the limit %.1f" % [hid, old_lengths, CIRCLE_LIMIT])
	_expect(order_failures(Handling.TABLE).is_empty(), "the class order broke with the corvettes' side push")


## True when hull `hid` has a line entry with the corvettes' sailing rate.
func _is_corvette(hid: String) -> bool:
	return Handling.has_line(hid) and int(Handling.row(hid)["line"]["rate"]) == CORVETTE_RATE


## Ship `s` at top speed along its nose with the engine full ahead and the nose
## told every step to keep turning (to a spot 1 radian off where it points),
## flown by the real flight: "d" is the width of the circle its velocity follows,
## measured over CIRCLE_SPAN seconds after CIRCLE_SETTLE seconds, and "v" the speed
## it keeps. A `strafe_share` of 0.0 or more replaces the side push with that share
## of the engine push (the one expression the ship's stats use), set after the
## reset because the reset works the stats out again.
func circle_run(s: Ship, strafe_share := -1.0) -> Dictionary:
	_reset_ship(s)
	if strafe_share >= 0.0:
		s.f_strafe = s.f_accel * strafe_share
	s.velocity = Vector2(s.f_max, 0.0)
	s.controls.forward = 1.0
	var arc := 0.0
	var turned := 0.0
	var prev_dir := 0.0
	var v_end := 0.0
	var steps := int((CIRCLE_SETTLE + CIRCLE_SPAN) / DT)
	for i in steps:
		s.controls.face_point = s.global_position + Vector2.from_angle(s.rotation + 1.0) * FAR
		_step_ship(s)
		var dir := s.velocity.angle()
		if float(i) * DT >= CIRCLE_SETTLE:
			arc += s.velocity.length() * DT
			turned += absf(Util.ang_diff(prev_dir, dir))
		prev_dir = dir
		v_end = s.velocity.length()
	return {"d": 2.0 * arc / maxf(turned, 0.0001), "v": v_end}


## Put ship `s` at its start: at home, nose to the right, at rest, full battery,
## controls empty, the stats worked out again and any engine or spin state cleared.
func _reset_ship(s: Ship) -> void:
	s.global_position = _home
	s.rotation = 0.0
	s.velocity = Vector2.ZERO
	s.energy.value = s.energy.max_value
	s.emp_t = 0.0
	s.recompute_stats(true)
	s.throttle = 0.0
	if "swivel" in s:
		s.set("swivel", 0.0)
	if "ang_vel" in s:
		s.set("ang_vel", 0.0)
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


## Put ship `s` away in a far spot of its own and make it dead, so the later
## flights never meet it.
func _put_ship_away(s: Ship) -> void:
	_put_away += 1
	s.global_position = Vector2(-5000.0 - float(_put_away) * 400.0, -5000.0)
	s.alive = false
	world.registry.rebuild_hashes()
