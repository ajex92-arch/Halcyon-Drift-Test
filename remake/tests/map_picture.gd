extends Node
## WHAT THIS IS: the map picture. It draws the finished map (lanes, every
## rock, ore nodes with their turret slots, monster camps with their attack
## circles, jungle entrances and the route graph) into a PNG file, with no
## window: the picture is made in memory pixel by pixel, so it works in a
## headless run. Use it to look at the whole map, or at one part of it.
##
## HOW IT WORKS: setup() takes the finished World; the first physics tick
## draws the picture, saves it and quits. Layers, bottom to top: the lane
## corridors (dark blue), the rocks as the match really has them (grey; ore
## rocks gold), the route graph (blue links for every ship, green links for
## small craft only; a link a ship would hit a rock on is pink), the entrances, the ore nodes (a gold ring of the node's
## area and a dot per turret slot), and the monster camps (a red dot with a
## ring as wide as its aggro range). The motherships are white dots.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --test=map_picture --picture=<file.png>
## Options: --scale=<world units per pixel> (default 20, so the whole map is
## 2000 x 1560 pixels) and --region=x0,y0,x1,y1 (world units; default the
## whole map) to look at a part of the map closer, for example
## --region=4000,2000,24000,16000 --scale=10.
##
## WHO USES IT: main.gd loads it for --test=map_picture. It only reads the
## match.

## The background colour.
const C_BACK := Color(0.04, 0.05, 0.09)
## The lane corridors.
const C_LANE := Color(0.10, 0.17, 0.30)
## An ordinary rock.
const C_ROCK := Color(0.45, 0.45, 0.48)
## An ore rock.
const C_ORE_ROCK := Color(0.95, 0.75, 0.15)
## A route link for every ship.
const C_LINK := Color(0.30, 0.55, 0.95)
## A route link for small craft only.
const C_JUNGLE_LINK := Color(0.25, 0.85, 0.40)
## A route link a ship would touch a rock on.
const C_BLOCKED_LINK := Color(1.0, 0.3, 0.9)
## An entrance (from the lane to its inside point).
const C_ENTRANCE := Color(1.0, 1.0, 0.3)
## A node's area and turret slots.
const C_NODE := Color(0.95, 0.75, 0.15)
## A monster camp and its attack circle.
const C_CAMP := Color(1.0, 0.25, 0.25)
## A mothership.
const C_BASE := Color(1.0, 1.0, 1.0)
## The running match (set by setup()).
var world: World
## True once the picture is made (it is made once).
var _done := false
## World units per pixel.
var _scale := 20.0
## The world rectangle drawn: its top-left corner and size.
var _origin := Vector2.ZERO
## The picture.
var _img: Image


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Godot calls this every tick. On the first one, make the picture and quit.
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	_done = true
	_run()
	get_tree().quit()


## Work out the area and the size, draw every layer and save the file.
func _run() -> void:
	_scale = maxf(0.5, float(Game.opt("scale", 20.0)))
	var region := Rect2(0.0, 0.0, MapLayout.W, MapLayout.H)
	var text := str(Game.opt("region", ""))
	if text != "":
		var v := text.split(",")
		if v.size() == 4:
			region = Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	_origin = region.position
	var w := int(ceil(region.size.x / _scale))
	var h := int(ceil(region.size.y / _scale))
	_img = Image.create(w, h, false, Image.FORMAT_RGB8)
	_img.fill(C_BACK)
	var info := world.map
	# Layer 1: the lane corridors.
	for id: String in info.lanes:
		_band(info.lanes[id], float(info.lane_half[id]), C_LANE)
	# Layer 2: the rocks as the match has them.
	var field := world.asteroids
	for i in field.pos.size():
		if field.alive[i] == 1:
			_disc(field.pos[i], field.rad[i], C_ORE_ROCK if field.node_rock[i] == 1 else C_ROCK)
	# Layer 3: the route graph.
	var route := info.route
	for a in route.adj.size():
		for e: Array in route.adj[a]:
			if int(e[0]) > a:
				# A link is pink when a ship of the size that may use it (a
				# strike craft on a jungle link, a corvette on a lane link)
				# would touch a rock on it.
				var pad := 17.0 if bool(e[1]) else 44.0
				var hit := not field.segment_hit(route.pos[a], route.pos[int(e[0])], pad).is_empty()
				_line(route.pos[a], route.pos[int(e[0])], C_BLOCKED_LINK if hit else (C_JUNGLE_LINK if bool(e[1]) else C_LINK))
	# Layer 4: entrances.
	for e: Dictionary in info.entrances:
		_line(e["lane"], e["inside"], C_ENTRANCE)
	# Layer 5: ore nodes and their turret slots.
	for n in world.nodes:
		_ring(n.global_position, MapLayout.NODE_RADIUS, C_NODE)
		for sp: Vector2 in n.slot_pos:
			_disc(sp, 60.0, C_NODE)
	# Layer 6: monster camps with their attack circles.
	for c: Dictionary in info.camps:
		var aggro := float(Jungle.CAMPS[c["type"]]["aggro"])
		_ring(c["pos"], aggro, C_CAMP)
		_disc(c["pos"], 90.0, C_CAMP)
	# Layer 7: the motherships.
	for mp: Vector2 in info.mothership_pos:
		_disc(mp, 200.0, C_BASE)
	var path := str(Game.opt("picture", "map_picture.png"))
	var err := _img.save_png(path)
	print("map_picture: %dx%d pixels, %.1f units per pixel, saved %s (error %d)" % [w, h, _scale, path, err])
	print("RESULT map_picture %d" % err)


## One world point as a pixel position in the picture.
func _px(p: Vector2) -> Vector2:
	return (p - _origin) / _scale


## Put one pixel, if it is inside the picture.
func _put(x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < _img.get_width() and y < _img.get_height():
		_img.set_pixel(x, y, col)


## A filled disc of world radius `r` at world point `p`.
func _disc(p: Vector2, r: float, col: Color) -> void:
	var c := _px(p)
	var pr := maxf(1.0, r / _scale)
	var x0 := maxi(0, int(floor(c.x - pr)))
	var x1 := mini(_img.get_width() - 1, int(ceil(c.x + pr)))
	var y0 := maxi(0, int(floor(c.y - pr)))
	var y1 := mini(_img.get_height() - 1, int(ceil(c.y + pr)))
	var r2 := pr * pr
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - c.x
			var dy := float(y) - c.y
			if dx * dx + dy * dy <= r2:
				_img.set_pixel(x, y, col)


## A thin ring of world radius `r` at world point `p`.
func _ring(p: Vector2, r: float, col: Color) -> void:
	var c := _px(p)
	var pr := maxf(2.0, r / _scale)
	var n := maxi(24, int(pr * 4.0))
	for k in n:
		var a := TAU * float(k) / float(n)
		_put(roundi(c.x + cos(a) * pr), roundi(c.y + sin(a) * pr), col)


## A straight line between two world points.
func _line(a: Vector2, b: Vector2, col: Color) -> void:
	var pa := _px(a)
	var pb := _px(b)
	var steps := maxi(1, int(ceil(pa.distance_to(pb))))
	for k in steps + 1:
		var q := pa.lerp(pb, float(k) / float(steps))
		_put(roundi(q.x), roundi(q.y), col)


## A corridor: a band `half` wide on each side of the polyline `pts`.
func _band(pts: PackedVector2Array, half: float, col: Color) -> void:
	var across := maxi(1, int(ceil(half / _scale)))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var along := (b - a).normalized()
		var n := along.orthogonal()
		var steps := maxi(1, int(ceil(a.distance_to(b) / _scale)))
		for k in steps + 1:
			var q := a.lerp(b, float(k) / float(steps))
			for s in range(-across, across + 1):
				var p := _px(q + n * (float(s) * _scale))
				_put(roundi(p.x), roundi(p.y), col)
		_disc(a, half, col)
	_disc(pts[pts.size() - 1], half, col)
