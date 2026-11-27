class_name KillIcons
extends RefCounted
## WHAT THIS IS: the kill-feed icons (T-126, Set 2, "Solid icons"): 17 small signs drawn in code that stand between the two
## names of a kill line ("[mark] Ash [icon] [mark] Wren (Bomber)"), so the weapon that did it reads at a glance and not only
## in words. Solid silhouettes that echo the shapes in the world (the turret, the torpedo, the shell). It also draws the two
## gold frames of the feed: the streak frame round the icon (the kill ended a streak of 3 or more) and the name frame
## round a killer's name (the kill made them an ace). It only draws: it changes nothing in the match, uses no random
## numbers and makes no particles.
##
## HOW IT WORKS: every glyph is a list of parts in a 16 x 16 box (origin top left, y down, pixels), built from its corners
## in parts() so a test can measure it. A part is a Dictionary: "op" ("poly" a filled polygon, "disc" a filled circle,
## "line", "pline" a polyline, "arc"), its numbers, and "cut" (true: a detail cut in VOID over the colour, never given a dark
## edge). Line parts are 2 px wide, details are cuts, the break of a destroyed structure is a zigzag cut. draw() paints the
## glyph twice, as the feed's text is outlined: a VOID pass first (every stroke 2 px wider, a 2 px VOID edge round every
## fill), then the colour pass (the colour for the parts, VOID for the cuts). No glyph is a plain disc, a point-down triangle
## (the team mark of Vhorr) or an upright triangle with a bar (the danger sign): the ion beam and the catch-all are rings.
## The glyph a blow gets is glyph_for(): a turret, minion, mothership or Scum as the source first, then the blow's weapon
## kind from KIND_GLYPH, a table, so a new weapon adds a row and not a code path. The structure lines take glyphs 14 to 17.
## View is a Control that holds an icon in a feed row (a slot 8 px wider than the icon, a 4 px gap each side, so the
## streak frame fits); NameTag holds a name label with the name frame; legend() is the How to play's list of all of it.
##
## WHO USES IT: HudFeed (the icons and frames of the lines), HelpPanel (the legend), tests/kill_icons_check.gd measures the
## glyphs and the mapping, tests/team_shapes_shots.gd takes the feed's picture.

## The side of the icon's box (pixels) and the gap each side of it in a feed row.
const SIZE := 16.0
const GAP := 4.0
## How many glyphs there are, and their numbers.
const COUNT := 17
const TURRET := 1
const MINION := 2
const MOTHERSHIP := 3
const SCUM := 4
const ROCK := 5
const GUNS := 6
const LANCE := 7
const TORPEDO := 8
const FLAK := 9
const SHELL := 10
const ION := 11
const SPECIAL := 12
const OTHER := 13
const TURRET_LOST := 14
const POST_LOST := 15
const BAY_LOST := 16
const DEN_CLEARED := 17
## How much wider a stroke is in the dark pass, and how far the dark edge of a fill reaches (pixels).
const STROKE_EDGE := 2.0
const FILL_EDGE := 2.0
## The streak frame: how far its corner brackets stand out of the box, their arm and their width (pixels).
const STREAK_OUT := 3.0
const STREAK_ARM := 5.0
const STREAK_W := 2.0
## The name frame: how far out of the name's box, the arm and the width.
const NAME_OUT := 2.5
const NAME_ARM := 4.0
const NAME_W := 1.5

## The glyph of a blow's weapon kind (DamageInfo.kind): the table of the mapping. A kind that is not here gets OTHER.
const KIND_GLYPH := {
	Rules.W_BOLT: GUNS,
	Rules.W_PD: GUNS,
	Rules.W_LANCE: LANCE,
	Rules.W_TORP: TORPEDO,
	Rules.W_FLAK: FLAK,
	Rules.W_SHELL: SHELL,
	Rules.W_ION: ION,
	Rules.W_COLLISION: ROCK,
	Rules.W_PURE: SPECIAL,
}
## The glyph of a blow's source when a unit, not a pilot, fired it (Unit.K_*): a turret, a minion, a mothership.
const SOURCE_GLYPH := {
	Unit.K_TURRET: TURRET,
	Unit.K_MINION: MINION,
	Unit.K_MOTHERSHIP: MOTHERSHIP,
}

## What each glyph stands for, in words (index = glyph number; 0 is unused): the legend's text.
const WORDS := [
	"",
	"killed by a turret",
	"killed by a minion",
	"killed by a mothership",
	"killed by the Scum",
	"crashed into an asteroid",
	"a pilot's guns (bolts, point defense)",
	"a Lance beam",
	"a torpedo",
	"flak",
	"a heavy shell",
	"an ion beam",
	"a special weapon",
	"anything else",
	"a turret was destroyed",
	"a defense post was destroyed",
	"a repair bay was destroyed",
	"a Scum den was cleared",
]

## The parts of each glyph, built once (glyph number -> Array of part Dictionaries).
static var _parts_cache := {}


## The glyph (1 to 13) for the blow `d`: the thing that fired it first (the Scum, a turret, a minion, a mothership), else
## the blow's weapon kind (KIND_GLYPH), else OTHER. A blow whose source unit is gone is read from what the note kept
## (source_team, source_is_minion), so a freed unit never breaks the feed.
static func glyph_for(d: DamageInfo) -> int:
	if d == null:
		return OTHER
	var src: Unit = d.source if d.source != null and is_instance_valid(d.source) else null
	if src != null:
		if src.team == Rules.NEUTRAL:
			return SCUM
		if SOURCE_GLYPH.has(src.kind):
			return int(SOURCE_GLYPH[src.kind])
	elif d.source_uid >= 0:
		if d.source_team == Rules.NEUTRAL:
			return SCUM
		if d.source_is_minion:
			return MINION
	return int(KIND_GLYPH.get(d.kind, OTHER))


## The parts of glyph `id` (1 to COUNT), in the order they are drawn; an empty list for any other number.
static func parts(id: int) -> Array:
	if id < 1 or id > COUNT:
		return []
	if _parts_cache.has(id):
		return _parts_cache[id]
	var out: Array = []
	match id:
		TURRET, TURRET_LOST:
			out = [_poly(_arc_points(Vector2(8, 13), 4.5, 180.0, 360.0, 12)), _line(Vector2(9, 10), Vector2(14, 5), 2.2), _line(Vector2(2, 13.6), Vector2(14, 13.6), 2.0)]
		MINION:
			out = [_poly(PackedVector2Array([Vector2(3, 3.5), Vector2(13.5, 8), Vector2(3, 12.5), Vector2(6, 8)]))]
		MOTHERSHIP:
			out = [_poly(PackedVector2Array([Vector2(1, 8), Vector2(4, 5), Vector2(13, 5.5), Vector2(15, 8), Vector2(13, 10.5), Vector2(4, 11)])), _cut(_line(Vector2(5, 8), Vector2(12, 8), 1.2))]
		SCUM, DEN_CLEARED:
			out = [_line(Vector2(11.95, 4.6), Vector2(4.05, 11.4), 2.6), _line(Vector2(10.4, 9.8), Vector2(5.6, 6.2), 2.6)]
		ROCK:
			out = [_poly(PackedVector2Array([Vector2(3, 9), Vector2(4.5, 4.5), Vector2(9, 3), Vector2(13, 5.5), Vector2(13.5, 10.5), Vector2(9.5, 13), Vector2(4.5, 12.5)])), _cut(_pline(PackedVector2Array([Vector2(8, 5), Vector2(9, 8), Vector2(7.5, 10.5)]), 1.3))]
		GUNS:
			out = [_arc(Vector2(8, 8), 4.8, 0.0, 360.0, 2.0), _line(Vector2(8, 1), Vector2(8, 4.2), 2.0), _line(Vector2(8, 11.8), Vector2(8, 15), 2.0), _line(Vector2(1, 8), Vector2(4.2, 8), 2.0), _line(Vector2(11.8, 8), Vector2(15, 8), 2.0), _disc(Vector2(8, 8), 1.0)]
		LANCE:
			out = [_poly(PackedVector2Array([Vector2(10.5, 1), Vector2(4, 9), Vector2(8.2, 9), Vector2(5.5, 15), Vector2(12, 7), Vector2(7.8, 7)]))]
		TORPEDO:
			out = [_poly(PackedVector2Array([Vector2(14, 8), Vector2(9.8, 5.6), Vector2(2, 6.65), Vector2(2, 9.35), Vector2(9.8, 10.4)])), _line(Vector2(3.2, 4.1), Vector2(3.2, 11.9), 2.0), _disc(Vector2(1.4, 8), 1.0)]
		FLAK:
			out = [_poly(_star(Vector2(8, 8), 7.5, 3.0, 8))]
		SHELL:
			var slug := PackedVector2Array([Vector2(2, 5.5), Vector2(10, 5.5)])
			slug.append_array(_arc_points(Vector2(10, 8), 2.5, -90.0, 90.0, 8))
			slug.append(Vector2(2, 10.5))
			out = [_poly(slug), _cut(_line(Vector2(4.2, 5.5), Vector2(4.2, 10.5), 1.3))]
		ION:
			out = [_arc(Vector2(8, 8), 6.0, 0.0, 360.0, 2.0), _arc(Vector2(8, 8), 2.6, 0.0, 360.0, 1.6)]
		SPECIAL:
			out = [_poly(_star(Vector2(8, 8.6), 7.0, 2.9, 5))]
		OTHER:
			# The crack is a colour stroke: it lies inside the ring's hollow, where a dark cut would show nothing.
			out = [_arc(Vector2(8, 8), 5.6, -20.0, 260.0, 2.4), _pline(PackedVector2Array([Vector2(10.5, 2.8), Vector2(8.6, 5.6), Vector2(10.6, 7.4), Vector2(8, 10)]), 1.6)]
		POST_LOST:
			out = [_poly(PackedVector2Array([Vector2(8, 1.5), Vector2(14.5, 8), Vector2(8, 14.5), Vector2(1.5, 8)])), _cut(_disc(Vector2(8, 8), 1.8))]
		BAY_LOST:
			out = [_poly(PackedVector2Array([Vector2(2.5, 2.5), Vector2(13.5, 2.5), Vector2(13.5, 13.5), Vector2(2.5, 13.5)])), _cut(_line(Vector2(8, 5), Vector2(8, 11), 2.0)), _cut(_line(Vector2(5, 8), Vector2(11, 8), 2.0))]
	if id == DEN_CLEARED:
		# The Scum's cross struck through: a dark gap, then the strike.
		out.append(_cut(_line(Vector2(1.5, 8), Vector2(14.5, 8), 3.6)))
		out.append(_line(Vector2(1.5, 8), Vector2(14.5, 8), 1.5))
	if id == TURRET_LOST or id == POST_LOST or id == BAY_LOST:
		# The break: a zigzag in the dark colour that cuts the glyph in two.
		out.append(_cut(_pline(PackedVector2Array([Vector2(4, 0.5), Vector2(7.5, 6.5), Vector2(6, 9), Vector2(11, 15.5)]), 2.2)))
	_parts_cache[id] = out
	return out


## The box (in the glyph's own 16 x 16 pixels) that the colour parts of glyph `id` fill, strokes included, for a test.
static func bounds(id: int) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Dictionary in parts(id):
		if bool(p["cut"]):
			continue
		var pad := 0.0
		var pts := PackedVector2Array()
		match String(p["op"]):
			"poly":
				pts = p["pts"]
			"pline":
				pts = p["pts"]
				pad = float(p["w"]) * 0.5
			"line":
				pts = PackedVector2Array([p["a"], p["b"]])
				pad = float(p["w"]) * 0.5
			"disc":
				pts = PackedVector2Array([p["c"] - Vector2.ONE * float(p["r"]), p["c"] + Vector2.ONE * float(p["r"])])
			"arc":
				var r := float(p["r"]) + float(p["w"]) * 0.5
				pts = PackedVector2Array([p["c"] - Vector2.ONE * r, p["c"] + Vector2.ONE * r])
		for q in pts:
			lo = Vector2(minf(lo.x, q.x - pad), minf(lo.y, q.y - pad))
			hi = Vector2(maxf(hi.x, q.x + pad), maxf(hi.y, q.y + pad))
	return Rect2(lo, hi - lo)


## How many drawing calls glyph `id` takes: its parts, plus one dark-pass call for each part that is not a cut.
static func calls(id: int) -> int:
	var n := 0
	for p: Dictionary in parts(id):
		n += 1 if bool(p["cut"]) else 2
	return n


## Draw glyph `id` with its top left corner at `origin`, `size` pixels across (SIZE is the usual one: every number scales), in
## colour `col`: the VOID pass, then the colour pass.
static func draw(ci: CanvasItem, id: int, origin: Vector2, col: Color, size: float = SIZE) -> void:
	var k := size / SIZE
	var ps := parts(id)
	for p: Dictionary in ps:
		if not bool(p["cut"]):
			_paint(ci, p, origin, k, Palette.VOID, true)
	for p: Dictionary in ps:
		_paint(ci, p, origin, k, Palette.VOID if bool(p["cut"]) else col, false)


## The streak frame: four corner brackets STREAK_OUT pixels out of the icon's box (its top left `origin`, `size` across),
## arms STREAK_ARM long, STREAK_W wide, in Palette.ACE. 4 calls.
static func streak_frame(ci: CanvasItem, origin: Vector2, size: float = SIZE) -> void:
	_brackets(ci, Rect2(origin, Vector2(size, size)).grow(STREAK_OUT), STREAK_ARM, STREAK_W)


## The name frame: four corner brackets NAME_OUT pixels out of `box` (the name's own box), arms NAME_ARM long, NAME_W wide,
## in Palette.ACE. 4 calls.
static func name_frame(ci: CanvasItem, box: Rect2) -> void:
	_brackets(ci, box.grow(NAME_OUT), NAME_ARM, NAME_W)


## The four corner brackets of `r` (arms `arm` long, `w` wide) in Palette.ACE.
static func _brackets(ci: CanvasItem, r: Rect2, arm: float, w: float) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		ci.draw_polyline(PackedVector2Array([c + Vector2(d.x * arm, 0.0), c, c + Vector2(0.0, d.y * arm)]), Palette.ACE, w)


## Paint one part: `grow` true is the dark pass (strokes wider, fills edged); `c` is the colour to use.
static func _paint(ci: CanvasItem, p: Dictionary, origin: Vector2, k: float, c: Color, grow: bool) -> void:
	var wide := STROKE_EDGE * k if grow else 0.0
	match String(p["op"]):
		"poly":
			var pts := _place(p["pts"], origin, k)
			if grow:
				for g in Geometry2D.offset_polygon(pts, FILL_EDGE * k, Geometry2D.JOIN_ROUND):
					if (g as PackedVector2Array).size() >= 3:
						ci.draw_colored_polygon(g, c)
			else:
				ci.draw_colored_polygon(pts, c)
		"disc":
			ci.draw_circle(origin + (p["c"] as Vector2) * k, float(p["r"]) * k + (FILL_EDGE * k if grow else 0.0), c)
		"line":
			ci.draw_line(origin + (p["a"] as Vector2) * k, origin + (p["b"] as Vector2) * k, c, float(p["w"]) * k + wide)
		"pline":
			ci.draw_polyline(_place(p["pts"], origin, k), c, float(p["w"]) * k + wide)
		"arc":
			ci.draw_arc(origin + (p["c"] as Vector2) * k, float(p["r"]) * k, deg_to_rad(float(p["a0"])), deg_to_rad(float(p["a1"])), 32, c, float(p["w"]) * k + wide)


## `pts` moved to `origin` and scaled by `k`.
static func _place(pts: PackedVector2Array, origin: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(origin + q * k)
	return out


## The corners of an arc of the circle (`centre`, `r`) from angle `a0` to `a1` degrees (0 = right, y down, so a rising angle turns
## clockwise on the screen), `steps` segments, `steps` + 1 points.
static func _arc_points(centre: Vector2, r: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		out.append(centre + Vector2.from_angle(deg_to_rad(lerpf(a0, a1, float(i) / float(steps)))) * r)
	return out


## A star of `points` points with its first point up: alternate corners on the circles of radius `ro` and `ri`.
static func _star(centre: Vector2, ro: float, ri: float, points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var r := ro if i % 2 == 0 else ri
		out.append(centre + Vector2.from_angle(-PI * 0.5 + PI * float(i) / float(points)) * r)
	return out


static func _poly(pts: PackedVector2Array) -> Dictionary:
	return {"op": "poly", "pts": pts, "cut": false}


static func _disc(c: Vector2, r: float) -> Dictionary:
	return {"op": "disc", "c": c, "r": r, "cut": false}


static func _line(a: Vector2, b: Vector2, w: float) -> Dictionary:
	return {"op": "line", "a": a, "b": b, "w": w, "cut": false}


static func _pline(pts: PackedVector2Array, w: float) -> Dictionary:
	return {"op": "pline", "pts": pts, "w": w, "cut": false}


static func _arc(c: Vector2, r: float, a0: float, a1: float, w: float) -> Dictionary:
	return {"op": "arc", "c": c, "r": r, "a0": a0, "a1": a1, "w": w, "cut": false}


## The same part as a dark cut (drawn in VOID over the colour, with no dark edge of its own).
static func _cut(p: Dictionary) -> Dictionary:
	p["cut"] = true
	return p


## An icon as a Control a feed row can hold: GAP + SIZE + GAP wide, `line_h` tall (at least SIZE), the icon centred on the
## row's middle, in colour `col`, with the streak frame when `streak` is true. The mouse passes through it.
class View extends Control:
	var glyph := 1
	var col := Palette.ICE
	var streak := false

	func _init(glyph_id: int, colour: Color, streak_frame_on: bool, line_h: float) -> void:
		glyph = glyph_id
		col = colour
		streak = streak_frame_on
		custom_minimum_size = Vector2(KillIcons.GAP * 2.0 + KillIcons.SIZE, maxf(line_h, KillIcons.SIZE))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var origin := Vector2(KillIcons.GAP, (size.y - KillIcons.SIZE) * 0.5)
		KillIcons.draw(self, glyph, origin, col)
		if streak:
			KillIcons.streak_frame(self, origin)


## A name in a feed row with the name frame round it: a label with room each side for the frame, the frame drawn behind
## the label's box. The mouse passes through it.
class NameTag extends MarginContainer:
	var label: Label

	func _init(text: String, colour: Color) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var room := int(ceil(KillIcons.NAME_OUT + KillIcons.NAME_W))
		add_theme_constant_override("margin_left", room)
		add_theme_constant_override("margin_right", room)
		label = UiKit.label(text, 13, colour)
		label.add_theme_color_override("font_outline_color", Palette.VOID)
		label.add_theme_constant_override("outline_size", 4)
		add_child(label)
		sort_children.connect(queue_redraw)

	func _draw() -> void:
		KillIcons.name_frame(self, Rect2(label.position, label.size))


## The legend of How to play: the 17 icons with their words, then the two frames. `w` is the width it may take. Returns a
## column of rows (icon, words), two columns of them side by side, in the colour the text of the help panel has.
static func legend(w: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	var words_w := maxf(120.0, (w - 4.0 * (GAP * 2.0 + SIZE) - 40.0) * 0.5)
	var rows := (COUNT + 1) / 2
	for i in rows:
		for j in 2:
			var id := i + 1 + j * rows
			if id > COUNT:
				grid.add_child(Control.new())
				grid.add_child(Control.new())
				continue
			grid.add_child(View.new(id, Palette.ICE, false, 18.0))
			var l := UiKit.label(String(WORDS[id]), 14, Palette.ICE, true)
			UiKit.pin_width(l, words_w)
			grid.add_child(l)
	var streak_row := UiKit.hbox(4)
	col.add_child(streak_row)
	streak_row.add_child(View.new(TORPEDO, Palette.ICE, true, 24.0))
	var s := UiKit.label("a gold frame round the icon: this kill ended a streak of %d or more kills in a row" % Rules.ACE_KILLS, 14, Palette.ICE, true)
	UiKit.pin_width(s, maxf(200.0, w - (GAP * 2.0 + SIZE) - 40.0))
	streak_row.add_child(s)
	var ace_row := UiKit.hbox(8)
	col.add_child(ace_row)
	ace_row.add_child(NameTag.new("Ash", Palette.ICE))
	var a := UiKit.label("a gold frame round the killer's name: this kill made them an ace", 14, Palette.ICE, true)
	UiKit.pin_width(a, maxf(200.0, w - 100.0))
	ace_row.add_child(a)
	return col
