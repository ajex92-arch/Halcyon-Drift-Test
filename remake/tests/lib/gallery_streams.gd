class_name GalleryStreams
extends RefCounted
## WHAT THIS IS: the engine-stream pictures of the hull gallery (tests/hull_gallery.gd,
## run with --streams): the four big hulls (Flak Frigate, Ion Frigate, Destroyer,
## Battlecruiser) of both teams, each cruising and boosting, close enough to see every
## stream. It is for judging the engine streams (EngineStreams), one stream from
## each nozzle. It draws nothing itself and changes no game rule.
##
## HOW IT WORKS: the gallery's match is frozen (nothing moves), so this makes its own
## ships through the gallery's make_ship() (the real hangar and the real ShipVisual,
## flames and all): for every big hull and team one ship that cruises (the main engine at
## 0.7) and one that boosts (the engine at full, boosting on). Then it takes one picture
## per hull (Aurelian on the left, Cinder on the right, cruising above, boosting below,
## at a zoom where the hull fills most of its half) and one "play zoom" picture with all
## four hulls of both teams, cruising and boosting, at about the size they have in a
## match. The gallery's _snap() waits half a second first, so the streams fill in.
##
## --stream-size=N makes the streams N times as long and their dots N times as big as the
## rule (1; see EngineStreams.set_size()), to look at other sizes; the file names then end in "_size_N".
##
## WHO USES IT: tests/hull_gallery.gd calls pictures() for --streams.

## The play zoom picture: pixels across the screen one world unit takes (zoom).
const PLAY_ZOOM := 0.22
## The gap between two hulls in the play zoom picture, in screen pixels.
const GAP := 40.0


## Take every stream picture (see the top of this file) and tidy up.
static func pictures(gallery: Node) -> void:
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	var scale := float(Game.opt("stream-size", 1.0))
	var suffix := "" if is_equal_approx(scale, 1.0) else "_size_" + String.num(scale, 1)
	EngineStreams.set_size(scale)
	var ships := {}
	for t in 2:
		for hid: String in EngineStreams.HULLS:
			for boost in 2:
				var s: Ship = gallery.make_ship(t, hid)
				if boost == 1:
					s.boosting = true
					s.thrust_main = 1.0
				ships["%d:%s:%d" % [t, hid, boost]] = s
	# One picture per hull: both teams, cruising above and boosting below.
	for hid: String in EngineStreams.HULLS:
		_hide_all(gallery, ships)
		var def: Dictionary = Ships.HULLS[hid]
		var length := float(def["length"])
		var z := minf(size.x * 0.40 / length, size.y * 0.19 / float(def["radius"]))
		gallery.aim_camera(gallery.home, z)
		for t in 2:
			for boost in 2:
				var s: Ship = ships["%d:%s:%d" % [t, hid, boost]]
				var spot := Vector2(size.x * (0.25 + 0.5 * float(t)), size.y * (0.30 + 0.42 * float(boost)))
				_stand(gallery, s, spot, z)
				gallery._label("boosting" if boost == 1 else "cruising", spot + Vector2(0.0, size.y * 0.17), 14, Palette.MIST)
		await gallery._snap("streams_" + hid + suffix, "%s: an engine stream from each nozzle (zoom %.2f, stream size x%s)" % [str(Ships.HULLS[hid]["label"]), z, String.num(scale, 1)])
	# One play zoom picture: every big hull of both teams.
	_hide_all(gallery, ships)
	gallery.aim_camera(gallery.home, PLAY_ZOOM)
	for t in 2:
		var total := GAP * float(EngineStreams.HULLS.size() - 1)
		for hid: String in EngineStreams.HULLS:
			total += float(Ships.HULLS[hid]["length"]) * PLAY_ZOOM
		var x := size.x * (0.25 + 0.5 * float(t)) - total * 0.5
		for hid: String in EngineStreams.HULLS:
			var w := float(Ships.HULLS[hid]["length"]) * PLAY_ZOOM
			for boost in 2:
				var s: Ship = ships["%d:%s:%d" % [t, hid, boost]]
				_stand(gallery, s, Vector2(x + w * 0.5, size.y * (0.32 + 0.38 * float(boost))), PLAY_ZOOM)
			x += w + GAP
	await gallery._snap("streams_play" + suffix, "the four big hulls, cruising (top) and boosting (bottom), at about play zoom (zoom %.2f, stream size x%s)" % [PLAY_ZOOM, String.num(scale, 1)])
	EngineStreams.set_size(1.0)


## Hide the gallery's own units and every ship of `ships`.
static func _hide_all(gallery: Node, ships: Dictionary) -> void:
	gallery._show([])
	for key: String in ships:
		(ships[key] as Ship).visible = false


## Show ship `s` at screen point `spot` (nose right, not moving) for the camera
## set by aim_camera() at zoom `z`.
static func _stand(gallery: Node, s: Ship, spot: Vector2, z: float) -> void:
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	s.visible = true
	gallery._put(s, gallery.home + (spot - size * 0.5) / z)
