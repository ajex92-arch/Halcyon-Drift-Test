extends Node
## WHAT THIS IS: the flash check and the look rules. It proves the three-flashes-a-second rule
## holds (no table row above it unless it is an old effect, no script with a tween or a timer that the
## table does not know), that Blink really cannot go above three a second, and that no colour of the
## palette comes near the danger colour.
##
## HOW IT WORKS: setup() runs four parts and prints "flash_check: N failures" (a FAIL line for each).
## (a) Every row of FlashTable: a rate above 3 a second fails, and so does a per-event row whose
## min_gap_ms is under 334, unless the row is marked `today` (an effect the game had when the rule
## began). The unit hit flash is reported with the rate it can reach under fire (the fastest weapon),
## not failed. Every row must name a script that exists. (b) The scan: every script under scripts/ that
## uses `create_tween`, `create_timer`, `Tween` or `AnimationPlayer`, except blink.gd, must have a row
## in the table or be one of FlashTable.NOT_EFFECTS; the scan prints how many scripts it looked at
## and how many matched. It looks for those four names only; writes to `modulate` are not scanned
## (the table's notes name the three that exist). (c) Blink: a request for 10 blinks a second is
## given 3, no blink makes more than 3 cycles in a second, `reduced_motion` makes every blink steady,
## the attention and confirm timings are as documented. (d) The look rule: no Color constant of Palette,
## other than DANGER, lies within a distance of 0.15 (in red, green, blue) of Palette.DANGER; the
## nearest is reported. It also measures the danger triangle's shape.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=flash_check
##
## WHO USES IT: main.gd loads it for --test=flash_check (it calls setup()); run_checks runs it.

## The most blinks a second allowed.
const MAX_HZ := 3.0
## The shortest gap between two flashes (milliseconds) that keeps a per-event effect at three a second.
const MIN_GAP_MS := 334
## How near (in red, green, blue) another palette colour may come to the danger colour.
const LOOK_DISTANCE := 0.15

## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built (the World is not needed).
func setup(_w: World) -> void:
	_table()
	_scan()
	_blink()
	_look()
	_glyph()
	print("flash_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## Part (a): the rows of FlashTable.
func _table() -> void:
	var fastest := 0.0
	for w: String in Weapons.WEAPONS:
		fastest = maxf(fastest, float((Weapons.WEAPONS[w] as Dictionary).get("rate", 0.0)))
	var names := {}
	for r: Dictionary in FlashTable.rows():
		var n := String(r["name"])
		_check("table: '%s' is listed once" % n, not names.has(n))
		names[n] = true
		_check("table: '%s' names a script that exists" % n, FileAccess.file_exists("res://" + String(r["file"])), String(r["file"]))
		_check("table: '%s' has a known kind" % n, ["blink", "pulse", "hit", "slide", "streak"].has(String(r["kind"])))
		var today := bool(r["today"])
		var rate: Variant = r["rate"]
		if typeof(rate) == TYPE_STRING:
			_check("table: '%s' (per event) keeps %d ms between flashes, or is marked today" % [n, MIN_GAP_MS], int(r["min_gap_ms"]) >= MIN_GAP_MS or today)
		else:
			_check("table: '%s' stays at or under %.0f a second, or is marked today" % [n, MAX_HZ], float(rate) <= MAX_HZ or today, "%.2f" % float(rate))
			if String(r["kind"]) in ["slide", "streak"]:
				_check("table: '%s' (a %s) has rate 0" % [n, r["kind"]], float(rate) == 0.0)
	print("flash_check: %d table rows; the unit hit flash restarts with every hit, so under fire it can reach %.1f a second (the fastest weapon fires %.1f shots a second): reported, not failed" % [FlashTable.rows().size(), fastest, fastest])


## Part (b): the scan for tweens, timers and animation players.
func _scan() -> void:
	var files := _gd_files("res://scripts")
	var matched := 0
	var unlisted := []
	var rx := RegEx.new()
	rx.compile("create_tween|create_timer|Tween|AnimationPlayer")
	for path in files:
		if path.ends_with("/ui/blink.gd"):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		if rx.search(f.get_as_text()) == null:
			continue
		matched += 1
		var rel: String = path.trim_prefix("res://")
		if FlashTable.row_for(rel).is_empty() and not FlashTable.NOT_EFFECTS.has(rel):
			unlisted.append(rel)
	_check("scan: every script with a tween or timer is in the table or on the short list", unlisted.is_empty(), str(unlisted))
	print("flash_check: scan looked at %d scripts; %d use a tween, timer or animation player (%d of them in the table or on the short list)" % [files.size(), matched, matched - unlisted.size()])


## Every .gd file under `dir`, as full res:// paths.
func _gd_files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out += _gd_files(dir.path_join(sub))
	return out


## Part (c): Blink's limits.
func _blink() -> void:
	var was := Blink.reduced_motion
	Blink.reduced_motion = false
	_check("blink: 10 a second is clamped to 3", Blink.clamp_rate(10.0) == 3.0 and Blink.MAX_HZ == 3.0)
	_check("blink: a negative rate is steady", Blink.clamp_rate(-2.0) == 0.0 and Blink.phase_at(123, 0.0))
	# Count the on-to-off turns over one second at a requested 10 a second: no more than 3.
	for hz: float in [1.0, 2.0, 3.0, 10.0, 60.0]:
		var turns := 0
		var last := Blink.phase_at(0, hz)
		for t in range(1, 3000):
			var now := Blink.phase_at(t, hz)
			if last and not now:
				turns += 1
			last = now
		_check("blink: a request for %.0f a second makes at most 3 blinks a second (made %.2f)" % [hz, float(turns) / 3.0], float(turns) / 3.0 <= 3.0 + 0.001)
	var peak := 0.0
	for t in range(0, 1000):
		peak = maxf(peak, Blink.pulse_at(t, 10.0))
	_check("blink: pulse_at stays in 0 to 1", peak <= 1.0 and Blink.pulse_at(0, 10.0) >= 0.0)
	# The attention blink runs 3 s and then stays lit; the confirm flash is one pulse.
	_check("blink: attention blinks at the start", Blink.attention(0, 100) != Blink.attention(0, 300))
	_check("blink: attention is steady after 3 s", Blink.attention(0, 3000) and Blink.attention(0, 3100) and Blink.attention(0, 3300))
	_check("blink: caution is steady after 3 s", Blink.caution(0, 3600) and Blink.caution(0, 4100))
	_check("blink: confirm is one pulse of 120 ms", Blink.confirm(0, 60) == 1.0 and Blink.confirm(0, 130) == 0.0 and Blink.confirm(0, 5000) == 0.0)
	# Reduced motion makes every blink steady.
	Blink.reduced_motion = true
	_check("blink: reduced motion makes phase steady", Blink.phase(10.0) and Blink.attention(0, 100) and Blink.caution(0, 600))
	_check("blink: reduced motion makes pulse steady", Blink.pulse(2.0) == 1.0 and Blink.confirm(0, 5000) == 0.0)
	Blink.reduced_motion = was


## Part (d): no Palette colour near DANGER.
func _look() -> void:
	var palette_script: Script = Palette
	var map: Dictionary = palette_script.get_script_constant_map()
	var danger: Color = Palette.DANGER
	var nearest := ""
	var best := 9.0
	var colours := 0
	for n: String in map:
		if n == "DANGER" or typeof(map[n]) != TYPE_COLOR:
			continue
		colours += 1
		var c: Color = map[n]
		var d := Vector3(c.r - danger.r, c.g - danger.g, c.b - danger.b).length()
		if d < best:
			best = d
			nearest = n
		_check("look: %s is not within %.2f of DANGER" % [n, LOOK_DISTANCE], d > LOOK_DISTANCE, "%.3f" % d)
	print("flash_check: look rule over %d palette colours; the nearest to DANGER is %s at %.3f (the rule wants more than %.2f)" % [colours, nearest, best, LOOK_DISTANCE])


## The danger triangle: upright, equilateral, side as asked, middle where asked.
func _glyph() -> void:
	var p := Glyphs.triangle(Vector2(100, 50), 14.0)
	_check("glyph: three corners", p.size() == 3)
	_check("glyph: the top point is above the base", p[0].y < p[1].y and is_equal_approx(p[1].y, p[2].y))
	_check("glyph: the three sides are 14", is_equal_approx(p[0].distance_to(p[1]), 14.0) and is_equal_approx(p[1].distance_to(p[2]), 14.0) and is_equal_approx(p[2].distance_to(p[0]), 14.0))
	var mid := (p[0] + p[1] + p[2]) / 3.0
	_check("glyph: the middle of the corners is the centre", mid.distance_to(Vector2(100, 50)) < 0.001)
	_check("glyph: DANGER is the magenta and not a team colour", Palette.DANGER == Color(0.80, 0.4745, 0.6549) and Palette.DANGER != Palette.AMBER and Palette.DANGER != Palette.CINDER)
