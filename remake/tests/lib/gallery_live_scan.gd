class_name GalleryLiveScan
extends RefCounted
## WHAT THIS IS: the "where does a real match's frame go" listing of the hull gallery
## (--live --live-look=scan). The crowd bench measures only ships and minions on an empty map;
## a real match also draws the rock fields, the ore nodes, the fog, the shots, the effects,
## the minimap and the screens. This plays a real match (from 25:00 with --late, fully teched) to --secs of match time, puts the
## camera on the busiest fight at play zoom, and measures one thing at a time: the frame with
## everything on, then with ONE part of the world (or of the screens) hidden, then everything
## on again, round after round, and prints how much each part costs.
##
## HOW IT WORKS: GalleryMeasure's _measure() times a run of frames (the script ms before the
## drawing starts, the render ms of the drawing, the draw calls). The parts are each child of the
## world, the screens, and each kind of unit. A part's cost is the mean of the "all on" runs next to
## it minus its own run. The match is not frozen, so the numbers drift; the rounds average that out.
##   scan: <part>: <frame ms saved> ms (script <ms>, render <ms>), <draw calls saved> draw calls
## and a last line with the "all on" mean.
##
## WHO USES IT: tests/hull_gallery.gd, for --live --live-look=scan (give --late and --secs, for
## example --late --secs=1620, the match time to stop at; --scan-rounds=N, default 2; --scan-hud also lists what the screens are made of and measures each part of them, --scan-hud-depth=N levels down (default 2; a CanvasLayer is a part too); --scan-freeze stops the world while the parts are measured, so the draw calls are exact; --scan-hold stops the screens' own per-frame work, which otherwise puts a hidden part back on show within 0.1 s; --scan-alone[=Path,Path] measures each part of the screens (or of Hud/Path) on its own, so the numbers add up; --scan-only=A,B keeps only the parts with those words in their names).

## How many frames each measurement takes.
const FRAMES := 90
## How many rounds of every part are measured.
const ROUNDS := 2

## The hull gallery test that owns this part.
var gallery: Node
## The measurer.
var meter: GalleryMeasure


## Remember the gallery that made us.
func _init(g: Node) -> void:
	gallery = g
	meter = GalleryMeasure.new(g)
	meter.frames = FRAMES


## Play the real match to --secs of match time, then measure and print as described above.
func scan(view: float) -> void:
	var secs := float(Game.opt("secs", 1620.0))
	var world: World = gallery.world
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	var z := size.x / view
	world.camera.free = true
	world.camera.set_process(false)
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	# With --late the match starts at 25:00, fully teched, as the late-game probes do (this test does not do it by itself).
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
	var stretch := 0
	while world.time < secs:
		await gallery.get_tree().process_frame
		stretch += 1
		if stretch % 120 == 1:
			world.camera.global_position = meter._busiest(world)
	# A human seat (a pilot or an Admiral, not --all-ai): close any big panel, so the seat's own screens are the ones measured, and say
	# whether the pilot's ship is flying (the readout and the gear slots show only then).
	if world.human != null:
		var seat_hud := gallery.get_tree().root.find_child("Hud", true, false)
		if seat_hud != null:
			seat_hud.call("_close_others", null)
			await gallery.wait_frames(5)
		var ship_ok: bool = world.human.ship != null and is_instance_valid(world.human.ship) and world.human.ship.alive
		print("scan: seat %s, the ship is flying: %s" % [world.human_role, ship_ok])
	# The parts: [name, the nodes to hide, or the kind of unit to hide (-1 for none)].
	var parts: Array = []
	for c: Node in world.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			parts.append(["node " + str(c.name), [c], -1])
	var hud := gallery.get_tree().root.find_child("Hud", true, false)
	if hud != null and hud is CanvasItem:
		parts.append(["screens (Hud)", [hud], -1])
		# --scan-hud: each part of the screens on its own, too (--scan-hud-depth=N levels down, default 2; a CanvasLayer
		# counts as a part), and a listing of what the screens are made of.
		if Game.opt("scan-hud", false):
			var depth := int(Game.opt("scan-hud-depth", 2))
			_list_tree(hud, "Hud", depth + 1)
			_add_hud_parts(parts, hud, "", depth)
	var kinds := {}
	for u: Unit in world.units:
		if u.visible:
			kinds[u.kind] = int(kinds.get(u.kind, 0)) + 1
	for kind: Variant in kinds:
		parts.append(["units of kind %s (%d at the start)" % [str(kind), int(kinds[kind])], [], int(kind)])
	# --scan-only=A,B: only the parts whose name has one of these words in it.
	var only := str(Game.opt("scan-only", ""))
	if only != "" and only != "true":
		var words := only.split(",", false)
		var kept: Array = []
		for part: Array in parts:
			for w: String in words:
				if str(part[0]).contains(w):
					kept.append(part)
					break
		parts = kept
	var rounds := int(Game.opt("scan-rounds", ROUNDS))
	# --scan-freeze: the world stops (its nodes stop processing) while the parts are measured, so the units, the shots and the
	# fog stay as they are, a part's draw calls are exact and the screens' own cost is not drowned in the match's.
	if Game.opt("scan-freeze", false):
		world.process_mode = Node.PROCESS_MODE_DISABLED
	# --scan-hold: the screens' own per-frame work stops (Hud._process), so what the scan hides stays hidden: the screens put
	# their pieces back on show every 0.1 s (HudLayout.apply()), which undoes a part hidden for longer than that.
	var hold: bool = bool(Game.opt("scan-hold", false)) and hud != null
	if hold:
		hud.set_process(false)
	# --scan-alone[=Path,Path]: instead of the parts above, each visible part of the screens (or of Hud/Path) ALONE, with its siblings
	# hidden, against all of them hidden: its own draw calls and milliseconds, which add up (the calls of one part hidden among the
	# rest do not: neighbours that draw the same way are drawn in one call).
	var alone = Game.opt("scan-alone")
	if alone != null and hud != null:
		for under: String in ([""] if alone is bool else str(alone).split(",", false)):
			await _alone(hud, "" if under == "Hud" else under, rounds)
		world.process_mode = Node.PROCESS_MODE_INHERIT
		if hold:
			hud.set_process(true)
		print("scan: done")
		return
	var saved := {}
	var on_runs: Array = []
	for part: Array in parts:
		saved[part[0]] = [0.0, 0.0, 0.0, 0.0, 0]
	for _r in rounds:
		for part: Array in parts:
			var before: Array = await meter._measure()
			on_runs.append(before)
			var hidden := _hide(world, part)
			var off: Array = await meter._measure()
			for n in hidden:
				if is_instance_valid(n):
					n.set("visible", true)
			var s: Array = saved[part[0]]
			s[0] += float(before[0]) - float(off[0])
			s[1] += float(before[4]) - float(off[4])
			s[2] += float(before[5]) - float(off[5])
			s[3] += float(before[3]) - float(off[3])
			s[4] += 1
	var mean := [0.0, 0.0, 0.0, 0.0]
	for r: Array in on_runs:
		mean[0] += float(r[0])
		mean[1] += float(r[4])
		mean[2] += float(r[5])
		mean[3] += float(r[3])
	var n := float(maxi(1, on_runs.size()))
	print("scan: all on: frame %.2f ms (script %.2f + render %.2f), %d draw calls, at match time %d s, %d ships %d minions" % [mean[0] / n, mean[1] / n, mean[2] / n, int(mean[3] / n), int(world.time), _count(world, Unit.K_SHIP), _count(world, Unit.K_MINION)])
	for part: Array in parts:
		var s: Array = saved[part[0]]
		var k := float(maxi(1, int(s[4])))
		print("scan: %-34s saves %6.2f ms (script %6.2f, render %6.2f), %5d draw calls" % [part[0], s[0] / k, s[1] / k, s[2] / k, int(s[3] / k)])
	world.process_mode = Node.PROCESS_MODE_INHERIT
	if hold:
		hud.set_process(true)
	print("scan: done")


## The --scan-alone listing: the visible canvas items just below `hud` (or below its child `under`, a path), each measured on its own
## with the others hidden, against none of them showing. Prints "scan-alone: <path> alone: <draw calls>, script, render" lines.
func _alone(hud: Node, under: String, rounds: int) -> void:
	var root: Node = hud if under == "" else hud.get_node_or_null(under)
	if root == null:
		print("scan-alone: no such part: ", under)
		return
	var kids: Array = []
	for c: Node in root.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			kids.append(c)
	var calls := {}
	var script := {}
	var render := {}
	for c: Node in kids:
		calls[c.name] = 0.0
		script[c.name] = 0.0
		render[c.name] = 0.0
	# What the screens' own per-frame work (Hud._process: the pointer checks, the 0.1 s refresh and layout) costs: the frame with it
	# on against with it off (only for the whole screens).
	if under == "":
		var was_on := hud.is_processing()
		hud.set_process(true)
		var p_on: Array = await meter._measure()
		hud.set_process(false)
		var p_off: Array = await meter._measure()
		hud.set_process(was_on)
		print("scan-alone: Hud._process costs: script %.2f ms, render %.2f ms, %.0f draw calls" % [float(p_on[4]) - float(p_off[4]), float(p_on[5]) - float(p_off[5]), float(p_on[3]) - float(p_off[3])])
	# The three reference measurements: everything showing, every part hidden, and the whole of `root` hidden.
	var ref := [0.0, 0.0, 0.0]
	for _r in rounds:
		var full: Array = await meter._measure()
		(root as CanvasItem).visible = false
		var gone: Array = await meter._measure()
		(root as CanvasItem).visible = true
		ref[0] += float(full[3])
		ref[2] += float(gone[3])
		for c: Node in kids:
			(c as CanvasItem).visible = false
		var off: Array = await meter._measure()
		ref[1] += float(off[3])
		# What still shows below `root` with every listed part hidden (the calls that stay are drawn by these).
		if _r == 0:
			var left: PackedStringArray = []
			for d: Node in root.find_children("*", "CanvasItem", true, false):
				if (d as CanvasItem).is_visible_in_tree():
					left.append("%s [%s]" % [root.get_path_to(d), d.get_class()])
			print("scan-alone: still showing with every part of %s hidden: %d: %s" % [root.name, left.size(), ", ".join(left.slice(0, 12))])
			var layers: PackedStringArray = []
			for d: Node in root.find_children("*", "CanvasLayer", true, false):
				layers.append(str(root.get_path_to(d)))
			print("scan-alone: canvas layers below %s: %s" % [root.name, ", ".join(layers)])
		for c: Node in kids:
			(c as CanvasItem).visible = true
			var on: Array = await meter._measure()
			(c as CanvasItem).visible = false
			calls[c.name] += float(on[3]) - float(off[3])
			script[c.name] += float(on[4]) - float(off[4])
			render[c.name] += float(on[5]) - float(off[5])
		for c: Node in kids:
			(c as CanvasItem).visible = true
	var path := "Hud" if under == "" else "Hud/" + under
	var sum_calls := 0.0
	var n := float(maxi(1, rounds))
	for c: Node in kids:
		sum_calls += float(calls[c.name]) / n
		print("scan-alone: %-44s alone: %5.0f draw calls, script %6.2f ms, render %6.2f ms" % [path + "/" + str(c.name), float(calls[c.name]) / n, float(script[c.name]) / n, float(render[c.name]) / n])
	print("scan-alone: %s: the parts add up to %.0f draw calls; draw calls with all showing %.0f, all parts hidden %.0f, %s hidden %.0f" % [path, sum_calls, float(ref[0]) / n, float(ref[1]) / n, path, float(ref[2]) / n])


## Add a part for each visible CanvasItem (and each visible CanvasLayer) below `node`, down `depth` levels. A part is named
## "hud child <path under the screens>". A node that is not a canvas item (a plain Node, a CanvasLayer) is walked through
## without a level counted for a plain Node, and counts as a level of its own when it is a layer.
func _add_hud_parts(parts: Array, node: Node, path: String, depth: int) -> void:
	if depth <= 0:
		return
	for c: Node in node.get_children():
		var shown := (c is CanvasItem and (c as CanvasItem).visible) or (c is CanvasLayer and (c as CanvasLayer).visible)
		var sub := (path + "/" if path != "" else "") + str(c.name)
		if shown:
			parts.append(["hud child " + sub, [c], -1])
		if c is CanvasItem and not shown:
			continue
		_add_hud_parts(parts, c, sub, depth - 1 if (c is CanvasItem or c is CanvasLayer) else depth)


## Print one "scan-tree:" line for `node` and for every node below it down `depth` levels: its path, class, whether it
## shows, and how many canvas items it holds (all, and the ones showing), so the listing names where a part's draw calls sit.
func _list_tree(node: Node, path: String, depth: int) -> void:
	var all := 0
	var shown := 0
	for d: Node in node.find_children("*", "CanvasItem", true, false):
		all += 1
		if (d as CanvasItem).is_visible_in_tree():
			shown += 1
	var vis := "-"
	if node is CanvasItem:
		vis = "yes" if (node as CanvasItem).is_visible_in_tree() else "no"
	elif node is CanvasLayer:
		vis = "yes" if (node as CanvasLayer).visible else "no"
	print("scan-tree: %-46s %-18s shows=%-3s items=%d showing=%d" % [path, node.get_class(), vis, all, shown])
	if depth <= 0:
		return
	for c: Node in node.get_children():
		_list_tree(c, path + "/" + str(c.name), depth - 1)


## Hide the nodes of part (its listed nodes, or every visible unit of its kind) and return the ones hidden.
func _hide(world: World, part: Array) -> Array:
	var hidden: Array = []
	if int(part[2]) >= 0:
		for u in world.units:
			if is_instance_valid(u) and (u as Unit).kind == int(part[2]) and (u as CanvasItem).visible:
				hidden.append(u)
	else:
		for n in part[1]:
			if is_instance_valid(n):
				hidden.append(n)
	for n in hidden:
		n.set("visible", false)
	return hidden


## How many live units of kind `kind` the world has.
func _count(world: World, kind: int) -> int:
	var n := 0
	for u in world.units:
		if is_instance_valid(u) and (u as Unit).alive and (u as Unit).kind == kind:
			n += 1
	return n
