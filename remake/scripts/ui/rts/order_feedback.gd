class_name OrderFeedback
extends RefCounted
## WHAT THIS IS: the answer the map gives to an order click (DESIGN.md section 7, "Order feedback"): a light ring
## that shrinks from 10 to 4 screen pixels over 0.25 s at the point of a Move or Attack the moment it is sent, once for
## each order; and a grey x (RtsGlyphs.draw_x) at the clicked point when the click did nothing (no squadron
## selected, or a verb the selection does not take, which the card's result line words as "<Verb>: later stage").
## Nothing blinks: the ring plays once and the x stays steady for X_S seconds. The two other forms of section 7 are here
## too: the danger triangle at the point of an order the queue refused at once (steady for BAD_S seconds; the reason is on
## the card's result line), and, once an accepted Move or Attack has been carried out, a dashed light line from each
## squadron that took it to the point (or the unit attacked) with a dot at the end, steady for LINE_S seconds. (While an
## order still waits in the command pause, CommandOverlayDraw draws its dotted "on resume" line; this file takes over
## when the order applies.)
##
## HOW IT WORKS: one OrderFeedback for each map layer (for_overlay() makes it on first use and keeps it in the
## overlay's meta, so the overlay's own file is not touched). It listens to the overlay's result_changed, which every
## order click ends with; the order itself is read back from world.orders.last_submitted (a sent Move or Attack of
## the human, accepted this tick, not seen before), so the ring sits on the order's own target even for a click on the
## minimap. A did-nothing answer is placed at the mouse when the pointer is over the map itself (over a button or the
## minimap the x is left out: the result line says why). A second ring within RING_GAP_MS of the last shows no ring
## (the flash rule's 334 ms gap, so at most three a second). Times are real milliseconds, so the marks play in the
## command pause too. CommandOverlayDraw.draw() calls draw() every frame, with `px` the world units one screen pixel
## covers, so the ring and the x keep their screen size at any zoom. It reads the match and draws; it sends no order
## and writes nothing the simulation reads. A refused order is world.orders.last_submitted with id 0 (a record not seen
## before, so an answer that is no order, such as a tool's "Outside the map", gives no triangle); a second triangle
## within RING_GAP_MS of the last is left out. An accepted order is noted in `lines` and counts as carried out for a
## squadron when that squadron's standing order (Squad.order) has the order's kind and target and a tick not before the
## order was sent; the line then stands LINE_S real seconds. An order no squadron took by the tick after its apply tick
## is dropped; at most LINE_MAX orders are kept.
##
## WHO USES IT: CommandOverlayDraw (the draw call); tests/alert_feed_check.gd.

## The ring's radius at the start and the end (screen pixels), and its life (seconds).
const RING_FROM := 10.0
const RING_TO := 4.0
const RING_S := 0.25
## The fewest milliseconds between two rings (the flash rule: three a second at most).
const RING_GAP_MS := 334
## Seconds the grey x stays, and its size (screen pixels).
const X_S := 0.8
const X_SIZE := 14.0  # X SIZE (pixels or a count)
## The result lines that say a click did nothing (the second is the end of a "<Verb>: later stage" line).
const NOTHING_TEXT := "Select squadrons first"
const NOTHING_END := ": later stage"
## Seconds the refused order's danger triangle stays, and its size (screen pixels).
const BAD_S := 0.8
const BAD_SIZE := 14.0  # BAD SIZE (pixels or a count)
## Seconds the dashed line of a carried-out order stays, its dash and its end dot's radius (screen pixels), and the most
## orders whose lines are kept.
const LINE_S := 1.5
const LINE_DASH := 8.0
const LINE_DOT := 3.0
const LINE_MAX := 8

## The rings playing: {"p": world point, "t0": the millisecond it began}.
var rings: Array = []
## The x marks standing: {"p", "t0"}.
var xs: Array = []
## The danger triangles standing (refused orders): {"p", "t0"}.
var bads: Array = []
## The accepted orders whose line is waiting or standing: {"kind", "tick", "apply_tick", "subjects", "target_kind",
## "target", "t0": the millisecond the order was seen carried out, -1 before}.
var lines: Array = []
## When the last triangle began, and the last refused order that gave one.
var _last_bad_ms := -100000
var _last_bad: Dictionary = {}
## The map layer this listens to.
var ov: CommandOverlay
## When the last ring began, and the id of the last order that gave one.
var _last_ring_ms := -100000
var _last_order := 0


## The feedback of overlay `o`: made on first use and kept in the overlay's meta.
static func for_overlay(o: CommandOverlay) -> OrderFeedback:
	# has_meta first: get_meta with a null default still prints an error when the key is not there.
	if o.has_meta("order_feedback"):
		var fb: Variant = o.get_meta("order_feedback")
		if fb != null:
			return fb as OrderFeedback
	var made := OrderFeedback.new()
	made.attach(o)
	o.set_meta("order_feedback", made)
	return made


## Listen to overlay `o`'s answers.
func attach(o: CommandOverlay) -> void:
	ov = o
	ov.result_changed.connect(_on_result)


## The overlay said something about an order click: ring a sent Move or Attack, put an x on a click that did nothing.
func _on_result() -> void:
	var world := ov.world
	if world == null:
		return
	var now := Time.get_ticks_msec()
	if ov.result_ok:
		var o := world.orders.last_submitted
		var id := int(o.get("id", 0))
		if id <= 0 or id == _last_order or not bool(o.get("human", false)) or int(o.get("team", -1)) != ov.team:
			return
		var kind := str(o.get("kind", ""))
		if kind != OrderKinds.MOVE and kind != OrderKinds.ATTACK:
			return
		_last_order = id
		lines.append({"kind": kind, "tick": int(o.get("tick", 0)), "apply_tick": int(o.get("apply_tick", 0)), "subjects": (o.get("subjects", []) as Array).duplicate(),
			"target_kind": str(o.get("target_kind", "")), "target": o.get("target"), "t0": -1})
		if lines.size() > LINE_MAX:
			lines.pop_front()
		var p: Variant = _target_point(world, o)
		if p != null and now - _last_ring_ms >= RING_GAP_MS:
			_last_ring_ms = now
			rings.append({"p": p, "t0": now})
		return
	var text := ov.result_text
	if text != NOTHING_TEXT and not text.ends_with(NOTHING_END):
		_refused(world, now)
		return
	var hovered := ov.get_viewport().gui_get_hovered_control()
	if hovered == null:
		xs = [{"p": ov.get_global_mouse_position(), "t0": now}]


## A refusal was said: when it is the queue's answer to an order of the human just sent (id 0, not seen before), put the
## danger triangle at the order's point (one triangle at a time; none within RING_GAP_MS of the last).
func _refused(world: World, now: int) -> void:
	var o := world.orders.last_submitted
	if o.is_empty() or int(o.get("id", -1)) != 0 or is_same(o, _last_bad):
		return
	if not bool(o.get("human", false)) or int(o.get("team", -1)) != ov.team or int(o.get("tick", -1)) != world.tick_count:
		return
	_last_bad = o
	var p: Variant = _target_point(world, o)
	if p != null and now - _last_bad_ms >= RING_GAP_MS:
		_last_bad_ms = now
		bads = [{"p": p, "t0": now}]


## The centres of the squadrons that carry out noted order `l` now (see the top).
func line_starts(world: World, l: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for sid in l["subjects"]:
		var rec: Squad = world.squads.get(int(sid))
		if rec == null or rec.order.is_empty():
			continue
		var t: Variant = rec.order.get("target")
		if str(rec.order.get("kind", "")) == str(l["kind"]) and typeof(t) == typeof(l["target"]) and t == l["target"] and int(rec.order.get("tick", -1)) >= int(l["tick"]):
			out.append(RtsSelect.centre_of(world, rec))
	return out


## The world point an order of the human aims at (a point, or the unit it attacks), or null.
func _target_point(world: World, o: Dictionary) -> Variant:
	var t: Variant = o.get("target")
	if str(o.get("target_kind", "")) == "point" and (t is Vector2i or t is Vector2):
		return Vector2(t)
	if str(o.get("target_kind", "")) == "unit":
		var u: Variant = world.by_uid.get(int(t))
		if u != null and is_instance_valid(u):
			return (u as Unit).global_position
	return null


## Drop the rings and x marks whose time is up at millisecond "now".
func prune(now: int) -> void:
	rings = rings.filter(func(r: Dictionary) -> bool: return float(now - int(r["t0"])) / 1000.0 < RING_S)
	xs = xs.filter(func(r: Dictionary) -> bool: return float(now - int(r["t0"])) / 1000.0 < X_S)
	bads = bads.filter(func(r: Dictionary) -> bool: return float(now - int(r["t0"])) / 1000.0 < BAD_S)
	if lines.is_empty() or ov == null or ov.world == null:
		return
	var world := ov.world
	var kept: Array = []
	for l: Dictionary in lines:
		if int(l["t0"]) < 0:
			if not line_starts(world, l).is_empty():
				l["t0"] = now
			elif world.tick_count > int(l["apply_tick"]) + 1:
				continue
		elif float(now - int(l["t0"])) / 1000.0 >= LINE_S:
			continue
		kept.append(l)
	lines = kept


## Draw the rings and the x on the map layer `ov` (called from CommandOverlayDraw every frame). `px` is how many world
## units one screen pixel covers.
func draw(canvas: CanvasItem, px: float) -> void:
	if rings.is_empty() and xs.is_empty() and bads.is_empty() and lines.is_empty():
		return
	var now := Time.get_ticks_msec()
	prune(now)
	for l: Dictionary in lines:
		if int(l["t0"]) < 0:
			continue
		var to: Variant = _target_point(ov.world, l)
		if to == null:
			continue
		for from in line_starts(ov.world, l):
			canvas.draw_dashed_line(from, to, Palette.with_alpha(Palette.ICE, 0.8), 1.5 * px, LINE_DASH * px)
		canvas.draw_circle(to, LINE_DOT * px, Palette.ICE)
	for b: Dictionary in bads:
		canvas.draw_set_transform(b["p"], 0.0, Vector2(px, px))
		Glyphs.danger(canvas, Vector2.ZERO, BAD_SIZE)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for r: Dictionary in rings:
		var k := clampf(float(now - int(r["t0"])) / 1000.0 / RING_S, 0.0, 1.0)
		canvas.draw_arc(r["p"], lerpf(RING_FROM, RING_TO, k) * px, 0.0, TAU, 28, Palette.ICE, 1.5 * px, true)
	for m: Dictionary in xs:
		canvas.draw_set_transform(m["p"], 0.0, Vector2(px, px))
		RtsGlyphs.draw_x(canvas, Vector2.ZERO, X_SIZE)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
