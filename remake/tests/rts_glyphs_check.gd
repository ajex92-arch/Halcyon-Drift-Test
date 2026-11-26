extends Node
## WHAT THIS IS: the check of the awareness screens' small signs (RtsGlyphs): every sign has strokes that stay
## inside its box, the five squadron states and the three win-odds marks are all there, and each sign draws once without a script error.
##
## HOW IT WORKS: setup() first measures the strokes of every sign (at least one stroke, every stroke at least
## two points, every point inside the box round the centre). It then adds one Control whose draw signal draws
## every sign once in the light colour, the grey x and the danger triangle beside them, waits a few frames
## for that draw, and prints "rts_glyphs_check: N failures" (a FAIL line for each).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=rts_glyphs_check
##
## WHO USES IT: main.gd loads it for --test=rts_glyphs_check (it calls setup()).

## How many checks failed.
var _fails := 0
## How many signs the canvas drew.
var _drawn := 0


## main.gd calls this once, right after the World is built (the World is not needed).
func setup(_w: World) -> void:
	_shapes()
	var canvas := Control.new()
	canvas.size = Vector2(320, 40)
	canvas.draw.connect(func() -> void: _draw_all(canvas))
	add_child(canvas)
	canvas.queue_redraw()
	for i in 5:
		await get_tree().process_frame
	_check("draw: every sign was drawn once", _drawn == RtsGlyphs.SHAPES.size() + 2, "%d drawn" % _drawn)
	canvas.queue_free()
	print("rts_glyphs_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## The strokes of every sign.
func _shapes() -> void:
	var centre := Vector2(100, 50)
	for state: String in RtsGlyphs.STATES:
		_check("shapes: the state %s has a sign" % state, RtsGlyphs.has(state))
	for kind: String in ["check", "flask", "x"]:
		_check("shapes: %s has a sign" % kind, RtsGlyphs.has(kind))
	_check("shapes: the three win-odds marks (up chevron, two level bars, down chevron) have a sign, and they are the three of RtsGlyphs.ODDS", RtsGlyphs.ODDS.size() == 3 and RtsGlyphs.ODDS.all(func(k: String) -> bool: return RtsGlyphs.has(k)))
	_check("shapes: an unknown kind has no strokes", RtsGlyphs.strokes("nothing", centre).is_empty())
	var seen := {}
	for kind: String in RtsGlyphs.SHAPES:
		var strokes := RtsGlyphs.strokes(kind, centre, 12.0)
		_check("shapes: %s has a stroke" % kind, not strokes.is_empty())
		var inside := true
		var long_enough := true
		for pts: PackedVector2Array in strokes:
			long_enough = long_enough and pts.size() >= 2
			for p in pts:
				inside = inside and absf(p.x - centre.x) <= 6.001 and absf(p.y - centre.y) <= 6.001
		_check("shapes: every stroke of %s has two points or more" % kind, long_enough)
		_check("shapes: %s stays inside its box" % kind, inside)
		# No two signs are the same strokes (a sign reads by its shape, not its colour).
		var key := str(RtsGlyphs.SHAPES[kind])
		_check("shapes: %s is not the shape of another sign" % kind, not seen.has(key))
		seen[key] = true


## Draw every sign once on `canvas`, in a row: the light colour, then the grey x and the danger triangle.
func _draw_all(canvas: Control) -> void:
	var x := 12.0
	for kind: String in RtsGlyphs.SHAPES:
		RtsGlyphs.draw(canvas, kind, Vector2(x, 20.0))
		_drawn += 1
		x += 20.0
	RtsGlyphs.draw_x(canvas, Vector2(x, 20.0))
	_drawn += 1
	Glyphs.danger(canvas, Vector2(x + 20.0, 20.0))
	_drawn += 1
