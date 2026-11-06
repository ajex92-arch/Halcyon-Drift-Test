class_name TurretPaint
extends RefCounted
## WHAT THIS IS: the painter of the rotating turrets on pilot ships. Every gun
## that swings (a turret or an automatic mount, such as point defense, flak, the
## heavy cannon, the ion turret and the Bomber's tail gun) is drawn as a small
## turret at its place on the hull, turned the way the gun really points right
## now, with a silhouette that says which weapon it is. It only draws; it changes
## nothing in the game.
##
## HOW IT WORKS:
##   - TurretShapes holds one silhouette per weapon class (point defense, flak,
##     light turret, heavy cannon, ion turret, tail gun, torpedo turret) in two
##     team styles. The first time a turret of a class and team is wanted,
##     prepare() makes it ready: a rim in the team colour, then the barrels, the
##     base, the cap and the coloured tip, all cut into triangles once and kept as
##     three packed arrays (points, indices, colours).
##   - draw_mounts() goes through a ship's guns. A fixed gun (the nose guns, the
##     torpedo, the beams) gets no turret: it never turns. For every other gun it
##     finds the turret's class (from the weapon's id, else its kind), its size
##     (the hull's TurretShapes.HULL_TU times the hull's drawing scale, never
##     smaller than MIN_EXTENT_PX screen pixels so it stays readable on a small
##     ship), turns the prepared points to the gun's place and live angle with one
##     multiplication. The guns of one ship (or structure) are put into one batch (begin_batch(),
##     flush_batch()): the same triangles in the same order, drawn with one command, because every
##     command costs real time. A see-through turret (a tower still being built) is drawn alone.
##   - A ship drawn shorter than HIDE_SHIP_PX screen pixels shows no turrets.
##   - A structure (the mothership, a lane tower, the Repair Bay) gets its heads
##     from draw_unit_mounts(): the same silhouettes at the structure's own size,
##     never made bigger than they are (a structure's body is what you see far
##     away) and left out where they would be under STRUCTURE_MIN_PX; the small
##     point-defense heads are drawn last, so they stay on top of a big gun
##     beside them.
##   - The kick: a turret is built in four layers (the rim of the base, the barrels, the
##     base with its cap, the coloured tip). When a gun has just fired (GunKick has seen
##     it), the barrels and the tip are drawn pushed back along the way the turret
##     points, under the base and the cap, and the tip is drawn nearly white for a
##     moment (a muzzle flash in the same triangles, other colours). It is still one
##     drawing command (every command costs real time): the same triangles in the same
##     order, with the points of the two layers that kick put in another place
##     (kicked_points()). A turret that sits still is drawn exactly as before.
##   - Test only: set_on(false) draws no turrets, so the hull gallery can measure
##     what they cost.
##
## WHO USES IT: ShipVisual calls draw_mounts() after it has drawn the hull;
## UnitVisual calls draw_unit_mounts() after it has drawn a structure (both hand over
## their GunKick, which says which guns have just fired). The
## hull gallery's turret sheet (tests/lib/gallery_turrets.gd) draws single turrets
## through draw_turret(), and set_on() is flipped by the frame-time measurements.

## A turret is drawn at least this many screen pixels from its middle to the tip
## of its barrel.
const MIN_EXTENT_PX := 6.0
## A ship drawn shorter than this many screen pixels shows no turrets.
const HIDE_SHIP_PX := 22.0
## A structure's head that would reach less than this many screen pixels from
## its middle is not drawn (and one that is drawn is never made bigger).
const STRUCTURE_MIN_PX := 2.5
## How thick the team-coloured rim of a turret is, in turret units.
const RIM := 0.12

## The prepared turrets: "style|class|team" -> prepared turret (see prepare()).
static var _recs := {}
## The numbers 0, 1, 2, ... (as many as the biggest batch so far needed), for flush_batch().
static var _seq := PackedInt32Array()
## True = turrets are drawn (always, in play); false only while the gallery test
## measures.
static var _on := true


## Are the turrets drawn?
static func is_on() -> bool:
	return _on


## Switch the turrets on or off while the game runs (tests only).
static func set_on(is_on: bool) -> void:
	_on = is_on


## The weapon class of mount `m` ("pd", "flak", "light", "heavy", "ion", "tail"
## or "torp"): from its weapon id, else from its weapon kind.
static func class_of(m: WeaponMount) -> String:
	var cls: String = TurretShapes.CLASS_BY_WEAPON.get(m.weapon_id, "")
	if cls == "":
		cls = TurretShapes.CLASS_BY_KIND.get(m.kind, "light")
	return cls


## The prepared turret of weapon class `cls` for `team`, in the team's style
## (Vhorr's thorned turrets for Cinder, the jury-rigged scrap ones for the Scum, who are the
## neutral team, and the clean ones for Aurelian). A class the Scum have no drawing for is drawn
## the Aurelian way.
static func turret(cls: String, team: int) -> Dictionary:
	var style := "aurelian"
	if team == Rules.CINDER:
		style = "vhorr"
	elif team == Rules.NEUTRAL and TurretShapes.SCUM.has(cls):
		style = "scum"
	var key := "%s|%s|%d" % [style, cls, team]
	var rec = _recs.get(key)
	if rec == null:
		var spec: Dictionary = TurretShapes.AURELIAN[cls]
		if style == "vhorr":
			spec = TurretShapes.VHORR[cls]
		elif style == "scum":
			spec = TurretShapes.SCUM[cls]
		rec = prepare(spec, style, Palette.team(team), cls)
		_recs[key] = rec
	return rec


## Make one turret ready: the silhouette table `spec` of TurretShapes drawn in
## `style` with a rim of colour `rim` and the tip colour of class `cls`.
## Returns {"pts", "idx", "cols": the triangles of the whole turret, "extent": how
## far it reaches from its middle, in turret units, "layers": the points of the four
## layers it is made of, back to front (the rim of the base, the barrels, the base and
## cap, the tip), which together are "pts" in this order, and "cols_hot": "cols" with the
## tip nearly white (the muzzle flash)}.
static func prepare(spec: Dictionary, style: String, rim: Color, cls: String) -> Dictionary:
	var vhorr := style == "vhorr"
	var base_col := Palette.CINDER_SHADE if vhorr else Palette.TURRET_AUREL_BASE
	var cap_col := Palette.CINDER_PLATE if vhorr else Palette.TURRET_AUREL_CAP
	var barrel_col := Palette.TURRET_CINDER_BARREL if vhorr else Palette.TURRET_AUREL_BARREL
	var tip_col: Color = TurretShapes.ACCENT[cls]
	if style == "scum":
		# The Scum: a strapped-on plate for a base, a rust cap, dark gunmetal pipes under a bare
		# metal rim, and a hazard-yellow muzzle.
		base_col = Palette.SCUM_PLATE
		cap_col = Palette.SCUM_RUST
		barrel_col = Palette.SCUM_IRON
		tip_col = Palette.SCUM_HAZARD
	var rim_col := Palette.with_alpha(rim, 0.9)
	# The turret is built in four layers, back to front, each its own triangles: the rim of
	# the base, the barrels with their rim, the base with its cap, and the coloured tip. The
	# barrels and the tip are the layers that kick back (see draw_turret()).
	var under := _layer()
	var gun := _layer()
	var top := _layer()
	var tip := _layer()
	# Step 1: the rim: every base and barrel grown by RIM, in the team colour.
	for grown: PackedVector2Array in _grown(spec["base"]):
		_add(grown, rim_col, under[0], under[1], under[2])
	for grown: PackedVector2Array in _grown(spec["barrels"]):
		_add(grown, rim_col, gun[0], gun[1], gun[2])
	# Step 2: barrels, then the base over their roots, then the cap, then the tip.
	for poly: Array in spec["barrels"]:
		_add(PackedVector2Array(poly), barrel_col, gun[0], gun[1], gun[2])
	for poly: Array in spec["base"]:
		_add(PackedVector2Array(poly), base_col, top[0], top[1], top[2])
	for poly: Array in spec["cap"]:
		_add(PackedVector2Array(poly), cap_col, top[0], top[1], top[2])
	for poly: Array in spec["accent"]:
		_add(PackedVector2Array(poly), tip_col, tip[0], tip[1], tip[2])
	# The whole turret is the four layers one after the other: their points in this order in
	# one array, and the triangles pointing into it. A turret is drawn from these arrays with
	# one command, kicking or not.
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	var cols := PackedColorArray()
	var layers: Array = []
	for layer: Array in [under, gun, top, tip]:
		var first := pts.size()
		pts.append_array(layer[0])
		for t: int in layer[1]:
			idx.append(first + t)
		cols.append_array(layer[2])
		layers.append(layer[0])
	# The same colours with the tip nearly white (the muzzle flash).
	var hot := cols.duplicate()
	for i in range(pts.size() - (layers[3] as PackedVector2Array).size(), pts.size()):
		var c := hot[i]
		hot[i] = c.lerp(Color(1.0, 1.0, 1.0, c.a), GunKick.FLASH_WHITE)
	# The same triangles with no shared points (three points for every triangle): every layer
	# on its own, then all of them together with their colours. A batch of turrets
	# (begin_batch()) is put together from these, because lists of triangles with no
	# shared points can simply be put one after the other.
	var e_layers: Array = []
	var e_pts := PackedVector2Array()
	var e_cols := PackedColorArray()
	for layer: Array in [under, gun, top, tip]:
		var lp := PackedVector2Array()
		for t: int in layer[1]:
			lp.append((layer[0] as PackedVector2Array)[t])
			e_cols.append((layer[2] as PackedColorArray)[t])
		e_layers.append(lp)
		e_pts.append_array(lp)
	var e_hot := e_cols.duplicate()
	for i in range(e_pts.size() - (e_layers[3] as PackedVector2Array).size(), e_pts.size()):
		var c := e_hot[i]
		e_hot[i] = c.lerp(Color(1.0, 1.0, 1.0, c.a), GunKick.FLASH_WHITE)
	return {"pts": pts, "idx": idx, "cols": cols, "extent": float(spec["extent"]), "layers": layers, "cols_hot": hot, "e_layers": e_layers, "e_pts": e_pts, "e_cols": e_cols, "e_hot": e_hot}


## The points of prepared turret `rec`, as one array in the order of rec["pts"], with the
## layers that kick (the barrels and the tip) turned and placed by `back` and the others
## (the rim of the base, the base and the cap) by `at` (both Transform2D). With `back` =
## `at` this is `at` times rec["pts"].
static func kicked_points(rec: Dictionary, at: Transform2D, back: Transform2D) -> PackedVector2Array:
	var layers: Array = rec["layers"]
	var out: PackedVector2Array = at * (layers[0] as PackedVector2Array)
	out.append_array(back * (layers[1] as PackedVector2Array))
	out.append_array(at * (layers[2] as PackedVector2Array))
	out.append_array(back * (layers[3] as PackedVector2Array))
	return out


## A new empty layer of a turret: [points, triangle indices, colours].
static func _layer() -> Array:
	return [PackedVector2Array(), PackedInt32Array(), PackedColorArray()]


## The polygons of `polys` (a list of point lists), each grown by RIM, as a list.
static func _grown(polys: Array) -> Array:
	var out: Array = []
	for poly: Array in polys:
		out.append_array(Geometry2D.offset_polygon(PackedVector2Array(poly), RIM, Geometry2D.JOIN_ROUND))
	return out


## Cut polygon `poly` into triangles and add it, in colour `col`, to the arrays.
static func _add(poly: PackedVector2Array, col: Color, pts: PackedVector2Array, idx: PackedInt32Array, cols: PackedColorArray) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var base := pts.size()
	pts.append_array(poly)
	for _i in poly.size():
		cols.append(col)
	for t in tri:
		idx.append(base + t)


## Draw every turning gun of `ship` on `ci` (the ship's Visual node, whose
## _draw() is running). `k` is the drawing scale of the ship (1 = true size),
## `u` the world units per design unit of its hull (length * k / 36), `px` the
## world units per screen pixel and `rot` the ship's turn. `kicks` (the ship's
## GunKick, already told about this frame's guns) says which guns have just fired;
## without it no gun kicks.
static func draw_mounts(ci: CanvasItem, ship: Ship, k: float, u: float, px: float, rot: float, kicks: GunKick = null) -> void:
	if not _on or u * 36.0 / px < HIDE_SHIP_PX:
		return
	var tu: float = float(TurretShapes.HULL_TU.get(ship.hull_id, TurretShapes.DEFAULT_TU))
	var mounts := ship.mounts
	var seen := kicks != null and kicks.ages.size() >= mounts.size()
	var batch := begin_batch()
	for i in mounts.size():
		var m: WeaponMount = mounts[i]
		if m.mount_type == WeaponMount.FIXED:
			continue
		var cls := class_of(m)
		var rec := turret(cls, ship.team)
		# How far the gun kicked back after its last shot (0 when it sits still).
		var kick := 0.0
		var flash := false
		if seen:
			var age: float = kicks.ages[i]
			kick = GunKick.turret_back(cls, age)
			flash = GunKick.is_flash(age)
		_add_to_batch(batch, rec, (m.offset * k).rotated(rot), m.world_angle(), tu * u, px, MIN_EXTENT_PX, kick, flash)
	flush_batch(ci, batch)


## Draw every head of a structure's guns (`mounts`: its WeaponMounts) on `ci` (the
## structure's Visual node, whose _draw() is running), in the style of `team`.
## `size` is world units per turret unit, `px` the world units per screen pixel,
## `rot` the structure's turn and `alpha` how solid (a tower still being built is
## faded). A fixed gun gets no head. Heads too small to read on the screen are
## left out, and the point-defense ones are drawn last. `kicks` (the structure's
## GunKick, already told about this frame's guns) says which guns have just fired;
## without it no head kicks.
static func draw_unit_mounts(ci: CanvasItem, mounts: Array, team: int, size: float, px: float, rot: float, alpha: float = 1.0, kicks: GunKick = null) -> void:
	if not _on:
		return
	var seen := kicks != null and kicks.ages.size() >= mounts.size()
	# A solid structure's heads go into one command (a see-through one draws them one by one).
	var batched := alpha >= 1.0
	var batch := begin_batch()
	for last: bool in [false, true]:
		for i in mounts.size():
			var m: WeaponMount = mounts[i]
			if m.mount_type == WeaponMount.FIXED:
				continue
			var cls := class_of(m)
			if (cls == "pd") != last:
				continue
			var rec := turret(cls, team)
			if float(rec["extent"]) * size / px < STRUCTURE_MIN_PX:
				continue
			# How far the gun kicked back after its last shot (0 when it sits still).
			var kick := 0.0
			var flash := false
			if seen:
				var age: float = kicks.ages[i]
				kick = GunKick.turret_back(cls, age)
				flash = GunKick.is_flash(age)
			if batched:
				_add_to_batch(batch, rec, m.offset.rotated(rot), m.world_angle(), size, px, 0.0, kick, flash)
			else:
				draw_turret(ci, rec, m.offset.rotated(rot), m.world_angle(), size, px, alpha, 0.0, kick, flash)
	if batched:
		flush_batch(ci, batch)


## A new, empty batch of turret heads: [points, colours] of triangles with no shared points.
## Put heads in with _add_to_batch() and draw them all with one command with flush_batch().
static func begin_batch() -> Array:
	return [PackedVector2Array(), PackedColorArray()]


## Add prepared turret `rec` to `batch`, placed, turned, sized and kicked exactly as
## draw_turret() would draw it (same arguments, solid), the same triangles in the same
## order.
static func _add_to_batch(batch: Array, rec: Dictionary, pos: Vector2, ang: float, size: float, px: float, min_px: float, kick: float, flash: bool) -> void:
	var extent: float = rec["extent"]
	var s := maxf(size, min_px * px / extent)
	var at := Transform2D(ang, Vector2(s, s), 0.0, pos)
	var pts: PackedVector2Array = batch[0]
	var cols: PackedColorArray = batch[1]
	if kick > 0.0:
		var back := at.translated_local(Vector2(-kick, 0.0))
		var layers: Array = rec["e_layers"]
		pts.append_array(at * (layers[0] as PackedVector2Array))
		pts.append_array(back * (layers[1] as PackedVector2Array))
		pts.append_array(at * (layers[2] as PackedVector2Array))
		pts.append_array(back * (layers[3] as PackedVector2Array))
		cols.append_array(rec["e_hot"] if flash else rec["e_cols"])
	else:
		pts.append_array(at * (rec["e_pts"] as PackedVector2Array))
		cols.append_array(rec["e_cols"])


## Draw every head of `batch` on `ci` with one command (nothing when it is empty).
static func flush_batch(ci: CanvasItem, batch: Array) -> void:
	var pts: PackedVector2Array = batch[0]
	var n := pts.size()
	if n == 0:
		return
	# The triangles have no shared points, so the numbers pointing into them are 0, 1, 2, ...
	if _seq.size() < n:
		for i in range(_seq.size(), maxi(n, _seq.size() * 2 + 512)):
			_seq.append(i)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _seq.slice(0, n), pts, batch[1])

## Draw prepared turret `rec` at `pos` (in the Visual node's frame), turned to
## the world angle `ang`, `size` world units per turret unit big (raised so the
## turret reaches at least `min_px` screen pixels, MIN_EXTENT_PX unless told
## otherwise; 0 = never made bigger). `alpha` below 1 draws it see-through.
## `kick` (turret units, 0 = sitting still) pushes the barrels and the tip back along
## the way the turret points, under the base and the cap, and `flash` draws the tip
## nearly white (see GunKick). A kicking turret is still one command: only its points
## are put together another way (kicked_points()). A see-through turret (a tower still
## being built, which cannot fire) never kicks.
static func draw_turret(ci: CanvasItem, rec: Dictionary, pos: Vector2, ang: float, size: float, px: float, alpha: float = 1.0, min_px: float = MIN_EXTENT_PX, kick: float = 0.0, flash: bool = false) -> void:
	var extent: float = rec["extent"]
	var s := maxf(size, min_px * px / extent)
	var at := Transform2D(ang, Vector2(s, s), 0.0, pos)
	var canvas := ci.get_canvas_item()
	# A turret that kicks: the same triangles and order, with the barrels and the tip slid back.
	if kick > 0.0 and alpha >= 1.0:
		var back := at.translated_local(Vector2(-kick, 0.0))
		RenderingServer.canvas_item_add_triangle_array(canvas, rec["idx"], kicked_points(rec, at, back), rec["cols_hot"] if flash else rec["cols"])
		return
	var cols: PackedColorArray = rec["cols"]
	if alpha < 1.0:
		cols = cols.duplicate()
		for i in cols.size():
			var c := cols[i]
			c.a *= alpha
			cols[i] = c
	RenderingServer.canvas_item_add_triangle_array(canvas, rec["idx"], at * (rec["pts"] as PackedVector2Array), cols)
