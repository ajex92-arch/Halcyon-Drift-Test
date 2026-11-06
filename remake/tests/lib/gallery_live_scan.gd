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
## example --late --secs=1620, the match time to stop at; --scan-rounds=N, default 2; --scan-hud also lists each child of the screens; --scan-only=A,B keeps only the parts with those words in their names).

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
	# The parts: [name, the nodes to hide, or the kind of unit to hide (-1 for none)].
	var parts: Array = []
	for c: Node in world.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			parts.append(["node " + str(c.name), [c], -1])
	var hud := gallery.get_tree().root.find_child("Hud", true, false)
	if hud != null and hud is CanvasItem:
		parts.append(["screens (Hud)", [hud], -1])
		# --scan-hud: each child of the screens on its own, too.
		if Game.opt("scan-hud", false):
			for c: Node in hud.get_children():
				if c is CanvasItem and (c as CanvasItem).visible:
					parts.append(["hud child " + str(c.name), [c], -1])
					for g: Node in c.get_children():
						if g is CanvasItem and (g as CanvasItem).visible:
							parts.append(["hud child " + str(c.name) + "/" + str(g.name), [g], -1])
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
					(n as CanvasItem).visible = true
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
	print("scan: done")


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
		(n as CanvasItem).visible = false
	return hidden


## How many live units of kind `kind` the world has.
func _count(world: World, kind: int) -> int:
	var n := 0
	for u in world.units:
		if is_instance_valid(u) and (u as Unit).alive and (u as Unit).kind == kind:
			n += 1
	return n
