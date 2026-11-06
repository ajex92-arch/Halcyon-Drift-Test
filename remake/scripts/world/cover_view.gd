class_name CoverView
extends Node2D
## WHAT THIS IS: the picture of the map's cover patches (gas clouds and hidden
## pockets) on the battlefield: soft haze over the cells of each patch. Everyone
## sees the haze, because a cloud is part of the map; what the fog hides is the
## ships standing in it (VisionCover). It is only decoration: it changes
## nothing in the game.
##
## HOW IT WORKS: for every cell of every patch it draws three round layers, big
## and faint, middle and inner, in the patch's colour (Palette.GAS for a cloud,
## Palette.POCKET for a pocket). Neighbouring cells overlap, so the middle of a
## patch is denser than its rim and the edge follows the cells softly. The
## shapes are fixed (no random numbers, no particles) and the picture is made
## once: Godot remembers the drawing. It is drawn above the ships (z_index 3)
## and under the shots and the fog. The discs go through a CircleBatch, so the
## hundreds of them take a few drawing commands, not one each.
##
## WHO USES IT: WorldSetup makes it and calls setup() (World child "CoverView").
## It reads World.vision.cover (the cells, ids and kinds).

## The radius of the biggest layer, as a share of the cell width.
const OUTER := 0.75
## The radius of the middle layer, as a share of the cell width.
const MIDDLE := 0.52
## The radius of the inner layer, as a share of the cell width.
const INNER := 0.3
## How see-through each layer is (alpha, 0..1): the outer, middle and inner
## layers in turn. Together with the neighbouring cells' layers they build up
## to about 0.4 in the middle of a patch.
const LAYER_ALPHA := [0.05, 0.06, 0.07]

## The world whose patches we draw.
var world: World


## Remember the world and ask Godot to draw. With --sim-only (Game.sim_only), or
## when the map has no patch, nothing is drawn: we hide ourselves.
func setup(w: World) -> void:
	world = w
	if Game.sim_only or not w.vision.cover.any:
		visible = false
		return
	z_index = 3
	queue_redraw()


## Draw every patch (nothing before setup()).
func _draw() -> void:
	if world == null:
		return
	var cover := world.vision.cover
	var vision := world.vision
	var cell := vision.cell
	# All the discs in one batch (a few drawing commands, not one for every disc), in the
	# order they are made, so they blend the way they did one by one.
	var batch := CircleBatch.new()
	for id in range(1, cover.cells.size()):
		var col := Palette.POCKET if str(cover.kinds[id]) == "pocket" else Palette.GAS
		var layers: Array = [
			[cell * OUTER, Palette.with_alpha(col, LAYER_ALPHA[0])],
			[cell * MIDDLE, Palette.with_alpha(col, LAYER_ALPHA[1])],
			[cell * INNER, Palette.with_alpha(col, LAYER_ALPHA[2])],
		]
		for c in cover.cells[id] as PackedInt32Array:
			var at := Vector2((float(c % vision.cols) + 0.5) * cell, (float(c / vision.cols) + 0.5) * cell)
			for layer: Array in layers:
				batch.add(at, float(layer[0]), layer[1] as Color)
	batch.draw(self)
