class_name GallerySceneCost
extends RefCounted
## WHAT THIS IS: the "what does the rest of the scene draw" listing of the hull
## gallery (--bench --bench-scene). The draw-cost bench counts the draw calls of the
## crowd of ships and minions; this lists the draw calls of everything else in the
## world, node by node and unit kind by unit kind, so a cost that does not come from
## the crowd (the starfield, the lanes, the motherships, the towers) has a name.
##
## HOW IT WORKS: with the match frozen and no crowd, it counts the draw calls of one
## frame (the RenderingServer's count), then hides each child of the world, one at a
## time, and each kind of unit, one kind at a time, counts again, and prints how many
## calls the hidden thing drew:
##   scene-cost: <what> hides <n> draw calls
## and a last line with the total. Nothing is changed for good: every node is shown
## again after its count.
##
## WHO USES IT: tests/hull_gallery.gd, for --bench --bench-scene (it runs instead of
## the other benches, on the gallery's own world).


## Count the draw calls of the latest frame, a few frames after a change.
static func _calls(gallery: Node) -> int:
	await gallery.wait_frames(4)
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## Print how many draw calls each kind of unit of the bench's crowd draws (--bench --bench-types),
## at a view `view` world units wide: every ship hull and every minion type of each team is shown
## alone, and the calls it adds to the empty scene are counted and divided by the number of units:
##   by-type: <team> <hull or type>: <n> units, <calls> draw calls (<calls per unit> each)
static func by_type(gallery: Node, view: float) -> void:
	view = float(Game.opt("bench-view", view))
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	gallery.aim_camera(gallery.home, z)
	var crowd: Array = GalleryMeasure.new(gallery)._make_crowd(size, z)
	await gallery.wait_frames(30)
	for u: Unit in crowd:
		u.visible = false
	var floor_calls := await _calls(gallery)
	print("by-type: the scene alone: %d draw calls" % floor_calls)
	var groups := {}
	for u: Unit in crowd:
		var key := "%d %s" % [u.team, (u as Ship).hull_id if u is Ship else "minion:" + (u as Minion).mtype]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(u)
	var keys: Array = groups.keys()
	keys.sort()
	for key: String in keys:
		var list: Array = groups[key]
		for u: Unit in list:
			u.visible = true
		var calls := await _calls(gallery) - floor_calls
		for u: Unit in list:
			u.visible = false
		print("by-type: %s: %d units, %d draw calls (%.1f each)" % [key, list.size(), calls, float(calls) / float(list.size())])
	print("by-type: done")


## Print the listing described above for the gallery's world.
static func scan(gallery: Node) -> void:
	await gallery.wait_frames(20)
	var world: World = gallery.world
	var base := await _calls(gallery)
	print("scene-cost: everything drawn: %d draw calls" % base)
	# Step 1: each child of the world.
	for c: Node in world.get_children():
		var ci := c as CanvasItem
		if ci == null or not ci.visible:
			continue
		ci.visible = false
		var left := await _calls(gallery)
		ci.visible = true
		print("scene-cost: node %s (%s) hides %d draw calls" % [c.name, c.get_class(), base - left])
	# Step 2: each kind of unit.
	var kinds := {}
	for u: Unit in world.units:
		if not kinds.has(u.kind):
			kinds[u.kind] = []
		kinds[u.kind].append(u)
	for kind: Variant in kinds:
		var list: Array = kinds[kind]
		var shown: Array = []
		for u: Unit in list:
			if u.visible:
				shown.append(u)
				u.visible = false
		var left := await _calls(gallery)
		for u: Unit in shown:
			u.visible = true
		print("scene-cost: %d units of kind %s hide %d draw calls" % [shown.size(), str(kind), base - left])
	print("scene-cost: done")
