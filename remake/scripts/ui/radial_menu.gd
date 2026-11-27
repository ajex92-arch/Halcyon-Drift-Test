class_name RadialMenu
extends RefCounted
## WHAT THIS IS: the ring of slices the order wheels share: the pilot's wing wheel (WingWheel, six slices) and the
## Admiral's fleet wheel (OrderWheel, eight). It draws the ring and says which slice a point is on; what each slice
## means, and what the rest of a wheel looks like, stay with the wheel.
##
## HOW IT WORKS: only static functions. Slice 0 is centred on the top and the slices run clockwise; with n slices
## each one is 360 / n degrees wide. draw_ring() draws onto any CanvasItem (the wheel's own _draw calls it): each slice
## is a curved wedge between the dead zone's radius and the ring's, in the panel colour, with the hovered slice
## washed in the interface colour, its edge outlined and its label (one or two lines) centred in it. A slice marked
## "dim" is drawn fainter with grey text and is never washed (an order that comes with a later stage). slice_at()
## turns a point's offset from the middle into the slice under it, or -1 for the dead zone and the outside.
##
## WHO USES IT: WingWheel (its _draw) and OrderWheel (its _draw and hit_at), and tests/field_wheel_check.gd.

## How many segments make the curve of a slice's edge.
const ARC_STEPS := 8


## Draw a ring of `labels.size()` slices around `center` (pixels) on `ci`: each entry of `labels` is the list of
## text lines of one slice, from the top clockwise. `hover` is the slice under the mouse (-1: none) and `dim` holds
## one bool per slice (an empty list: none is dim). `label_r` is the radius the label is centred on (-1: halfway
## between the dead zone and the ring) and `box_w` the width the label's lines are centred in.
static func draw_ring(ci: CanvasItem, center: Vector2, labels: Array, dead_r: float, ring_r: float, hover: int, dim: Array,
		accent: Color, font: Font, text_size: int, label_r: float = -1.0, box_w: float = 80.0) -> void:
	var n := labels.size()
	var step := 360.0 / float(n)
	for i in n:
		var is_dim := i < dim.size() and bool(dim[i])
		var mid := deg_to_rad(-90.0 + step * float(i))
		var a0 := mid - deg_to_rad(step * 0.5)
		var a1 := mid + deg_to_rad(step * 0.5)
		var pts := PackedVector2Array()
		for k in ARC_STEPS + 1:
			pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / float(ARC_STEPS))) * ring_r)
		for k in ARC_STEPS + 1:
			pts.append(center + Vector2.from_angle(lerpf(a1, a0, float(k) / float(ARC_STEPS))) * dead_r)
		ci.draw_colored_polygon(pts, Palette.with_alpha(Palette.PANEL, 0.55 if is_dim else 0.85))
		if hover == i and not is_dim:
			ci.draw_colored_polygon(pts, Palette.with_alpha(accent, 0.35))
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, Palette.LINE, 1.5, true)
		# The label: one or two lines, centred in the slice.
		var lines: Array = labels[i]
		var at := center + Vector2.from_angle(mid) * (label_r if label_r >= 0.0 else (dead_r + ring_r) * 0.5)
		for j in lines.size():
			var y := at.y + 5.0 + (float(j) - float(lines.size() - 1) * 0.5) * 16.0
			ci.draw_string(font, Vector2(at.x - box_w * 0.5, y), str(lines[j]), HORIZONTAL_ALIGNMENT_CENTER, box_w, text_size, Palette.MIST if is_dim else Palette.ICE)


## The slice of an `n`-slice ring that the point `offset` (pixels from the ring's middle) is on, or -1 inside the
## dead zone (closer than `dead_r`) and outside the ring (farther than `ring_r`).
static func slice_at(offset: Vector2, n: int, dead_r: float, ring_r: float) -> int:
	var r := offset.length()
	if r < dead_r or r > ring_r:
		return -1
	var step := 360.0 / float(n)
	# The angle clockwise from the top; slice 0 is centred on the top.
	var a := fposmod(rad_to_deg(offset.angle()) + 90.0 + step * 0.5, 360.0)
	return int(a / step) % n
