class_name VisionCover
extends RefCounted
## WHAT THIS IS: the "hidden from outside" rule of the fog of war, kept in its
## own file. A cover patch is a group of fog cells (a gas cloud or a hidden
## pocket) where ships can hide: a unit standing in a patch is seen by the
## other team only when one of that team's units is inside the same patch, or
## when it stands inside an active reveal circle (the Scout Ping, a sweep
## that sees through rocks), or when it is touching one of the team's units
## (Rules.VISION_TOUCH, decided by WorldVisibility), or while it is revealed
## by firing (also WorldVisibility). A part of Vision.
##
## HOW IT WORKS: the fog grid gets one more number per cell: 0 for open
## space, or the id (1, 2, 3 ...) of the patch the cell belongs to. A patch
## never blocks a ray: ships inside see out normally, and sight passes
## through a patch to what lies beyond it. The patch only decides whether the
## UNITS standing in it are seen. For that, each team has an "open" stamp per
## cell (the same stamp trick as Vision.lit): at every Vision update, a team
## that has a viewer inside a patch opens every cell of that patch, and a
## reveal circle opens the patch cells it covers. Vision.is_visible() then
## says a point is seen only when its cell is lit AND is open (or has no
## cover). With no patch added, nothing here runs.
##
## WHO USES IT: Vision makes one (Vision.cover), fills it from MapCover and
## asks it from is_visible() and update_team(). FogView reads id_of and open
## to draw lit-but-hidden cells lighter. The map drawing (MapDecor) reads
## ids, kinds and cells to draw the patches.

## The fog grid we belong to (we read its size, cell width and stamps).
var vision: Vision
## Per cell: 0 = open space, else the id of the cover patch the cell is in.
var id_of := PackedByteArray()
## Per patch id (index 0 is unused): the numbers of the cells in the patch.
var cells: Array = [PackedInt32Array()]
## Per patch id: "cloud" or "pocket" (index 0 is unused).
var kinds: Array = [""]
## Per patch id: its name from the map plan (MapCover), or "" for a patch made
## by a test (index 0 is unused).
var names: Array = [""]
## Per team (0, 1): per cell, the stamp of the Vision update that opened the
## cell for that team. A cell is open right now when its number equals the
## team's current stamp.
var open: Array = []
## Per team: per patch id, the stamp of the latest update in which the team had
## a viewer inside the patch (so a crowd in one patch opens it only once).
## Index 0 is unused, like in `cells`.
var _occupied: Array = [PackedInt32Array([0]), PackedInt32Array([0])]
## True once the first patch has been added. While false, every call here is
## skipped.
var any := false


## Remember the grid and make the per-cell lists. Vision calls this once, in
## setup(), after it knows the grid size.
func _init(owner: Vision) -> void:
	vision = owner
	id_of.resize(owner.cols * owner.rows)
	for t in 2:
		var o := PackedInt32Array()
		o.resize(owner.cols * owner.rows)
		open.append(o)


## Add one patch made of the cells whose centres lie inside an ellipse
## (centre `centre`, half-width `half_w` and half-height `half_h`, world
## units). `kind` is "cloud" or "pocket" and `patch_name` the patch's name. A
## cell that already belongs to a patch stays with the first one. Returns the
## new patch's id, or 0 if no cell qualified.
func add_ellipse(kind: String, centre: Vector2, half_w: float, half_h: float, patch_name: String = "") -> int:
	var cell := vision.cell
	var x0 := clampi(int((centre.x - half_w) / cell), 0, vision.cols - 1)
	var x1 := clampi(int((centre.x + half_w) / cell), 0, vision.cols - 1)
	var y0 := clampi(int((centre.y - half_h) / cell), 0, vision.rows - 1)
	var y1 := clampi(int((centre.y + half_h) / cell), 0, vision.rows - 1)
	var list := PackedInt32Array()
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var dx := ((float(cx) + 0.5) * cell - centre.x) / half_w
			var dy := ((float(cy) + 0.5) * cell - centre.y) / half_h
			if dx * dx + dy * dy <= 1.0 and id_of[cx + cy * vision.cols] == 0:
				list.append(cx + cy * vision.cols)
	return add_cells(kind, list, patch_name)


## Add one patch made of the given cell numbers (cells already in a patch are
## skipped). Returns the new patch's id (1, 2, 3 ...), or 0 if the list had
## no free cell or the 255 ids are used up.
func add_cells(kind: String, list: PackedInt32Array, patch_name: String = "") -> int:
	var id := cells.size()
	if id > 255:
		return 0
	var mine := PackedInt32Array()
	for c in list:
		if id_of[c] == 0:
			id_of[c] = id
			mine.append(c)
	if mine.is_empty():
		return 0
	cells.append(mine)
	kinds.append(kind)
	names.append(patch_name)
	for t in 2:
		var occ: PackedInt32Array = _occupied[t]
		occ.append(0)
		_occupied[t] = occ
	any = true
	return id


## The id of the patch that contains world point `p`, or 0 for open space.
func patch_at(p: Vector2) -> int:
	return id_of[vision.cell_of(p)]


## How many patches there are.
func count() -> int:
	return cells.size() - 1


## True if cell `c` is open for team `team` right now: a unit of that team is
## inside the same patch, or a reveal circle of that team covers it. Cells with
## no cover are not asked (Vision checks the cover id first).
func is_open(team: int, c: int) -> bool:
	return (open[team] as PackedInt32Array)[c] == int(vision.stamp[team])


## Vision.update_team() calls this with the team's viewers and the new stamp
## `s`: every patch that holds one of the viewers opens, all its cells at once.
func open_occupied(team: int, viewers: Array, s: int) -> void:
	var o: PackedInt32Array = open[team]
	var occ: PackedInt32Array = _occupied[team]
	for v: Vector3 in viewers:
		var id := id_of[vision.cell_of(Vector2(v.x, v.y))]
		if id == 0 or occ[id] == s:
			continue
		occ[id] = s
		for c in cells[id] as PackedInt32Array:
			o[c] = s


## Vision.update_team() calls this for every cell a reveal circle lights: a
## cover cell inside an active reveal opens for the team.
func open_cell(team: int, c: int, s: int) -> void:
	if id_of[c] != 0:
		var o: PackedInt32Array = open[team]
		o[c] = s
