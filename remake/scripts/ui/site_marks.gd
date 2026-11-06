class_name SiteMarks
extends RefCounted
## WHAT THIS IS: how a turret site's state is shown to the player, on the map
## and on the minimap: a ring style plus a word. It only draws: it changes
## nothing in the match, uses no random numbers and makes no particles.
##
## HOW IT WORKS: view() works out what team `vt` may see of site `n` (a
## dictionary: the state, its team, the seconds left, a build or lock progress
## and the pilots of each team inside the circle). draw_ring() draws the ring in
## the style of the state, word() gives the word under it, dashed_circle() draws
## the real build circle. Colour is never the only signal: every state has its
## own ring style and its own word:
##   HELD       a solid ring in the holder's colour                    "HELD"
##   BUILDING   a dim solid ring with a bright arc that fills as the
##              turret is built                                        "BUILDING 18s"
##   LOCKED     a grey ring with a light arc that shrinks as the lock
##              runs out                                               "LOCKED 42s"
##   CONTESTED  a ring split in two halves, one in each team's colour  "CONTESTED 2v1"
##   CLEAR      a dashed ring in the team's colour                     "AURELIAN CLEAR"
##   OPEN       a dashed grey ring                                     "OPEN"
## All six are shown at the four shared jungle sites (where either team may
## build): those are the points the two teams contest. Every other site shows
## only BUILDING and LOCKED; the rest keeps its plain ring (PLAIN). Fog: a shared
## site's HELD, BUILDING and LOCKED are public (the map already shows who holds
## it, and the admiral board reads the true holder); CONTESTED and CLEAR show
## only to a team that has a pilot ship or minion inside the circle or sees its
## centre (knows()), else the site reads OPEN (with No fog on, FogOff, every site is known).
## Nothing is drawn with a flash.
##
## WHO USES IT: ResourceNode draws its ring with it, the minimap draws the
## nodes' rings with it and the news feed (HudFeed) asks knows(). The state
## itself is kept by TurretSite.

## The "state" of view() for a site that shows nothing special: its plain ring.
const PLAIN := "plain"
## How many dashes a dashed circle has.
const DASHES := 24


## What team `vt` (-1 = sees everything) may see of site `n`: a dictionary with
## "state" (TurretSite.HELD, BUILDING, LOCKED, CONTESTED, CLEAR, OPEN or PLAIN),
## "team" (the team the state belongs to, -1 for none), "left" (whole seconds left
## of a build or a lock, else 0), "progress" (0 to 1: how far the build is, or how
## much of the lock is left) and "p0" and "p1" (the pilot ships of each team
## inside the circle).
static func view(w: World, n: ResourceNode, vt: int) -> Dictionary:
	var s := n.site
	var shared := n.node_kind == "jungle_shared"
	var state := s.state
	var team := s.state_team
	# Fog: who is inside is private to a team that cannot see it.
	if (state == TurretSite.CONTESTED or state == TurretSite.CLEAR) and vt >= 0 and not knows(w, n, vt):
		state = TurretSite.OPEN
		team = -1
	var left := 0
	var progress := 0.0
	if state == TurretSite.BUILDING:
		for t in n.slots:
			if t != null and is_instance_valid(t) and t.alive and not t.is_built():
				left = int(ceil(t.build_left))
				progress = 1.0 - t.build_left / maxf(0.001, t.build_total)
	elif state == TurretSite.LOCKED:
		left = int(ceil(n.rebuild_lock_until - w.time))
		progress = clampf((n.rebuild_lock_until - w.time) / maxf(1.0, float(Rules.tune("rebuild_lock", TurretData.REBUILD_LOCK))), 0.0, 1.0)
	# A site that is not shared shows only BUILDING and LOCKED.
	if not shared and state != TurretSite.BUILDING and state != TurretSite.LOCKED:
		state = PLAIN
	return {"state": state, "team": team, "left": left, "progress": progress, "p0": int(s.pilots[0]), "p1": int(s.pilots[1])}


## May team `vt` see who stands in site `n`'s build circle? Yes with a pilot
## ship or minion of its own inside, or with sight of the site's centre.
static func knows(w: World, n: ResourceNode, vt: int) -> bool:
	if vt < 0 or FogOff.is_on():
		return true
	var s := n.site
	if int(s.pilots[vt]) + int(s.minions[vt]) > 0:
		return true
	return w.vision.is_visible(vt, n.global_position)


## The word for a view() dictionary: "HELD", "BUILDING 18s", "LOCKED 42s",
## "CONTESTED 2v1", "AURELIAN CLEAR", "OPEN", or "" for a plain site.
static func word(v: Dictionary) -> String:
	match String(v["state"]):
		TurretSite.HELD:
			return "HELD"
		TurretSite.BUILDING:
			return "BUILDING %ds" % int(v["left"])
		TurretSite.LOCKED:
			return "LOCKED %ds" % int(v["left"])
		TurretSite.CONTESTED:
			return "CONTESTED %dv%d" % [int(v["p0"]), int(v["p1"])]
		TurretSite.CLEAR:
			return "%s CLEAR" % Rules.TEAM_DISPLAY[int(v["team"])].to_upper()
		TurretSite.OPEN:
			return "OPEN"
	return ""


## Draw the ring of a view() dictionary `v` on canvas item `ci`, centred at `c`
## with radius `r` and line width `width` (see the table at the top).
static func draw_ring(ci: CanvasItem, c: Vector2, r: float, v: Dictionary, width: float) -> void:
	var team := int(v["team"])
	var col := Palette.team(team) if team >= 0 else Palette.NEUTRAL
	match String(v["state"]):
		TurretSite.HELD:
			ci.draw_arc(c, r, 0.0, TAU, 96, Palette.with_alpha(col, 0.55), width, true)
		TurretSite.BUILDING:
			ci.draw_arc(c, r, 0.0, TAU, 96, Palette.with_alpha(col, 0.3), width, true)
			ci.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * float(v["progress"]), 64, col, width * 1.6, true)
		TurretSite.LOCKED:
			ci.draw_arc(c, r, 0.0, TAU, 96, Palette.with_alpha(Palette.NEUTRAL, 0.4), width, true)
			ci.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * float(v["progress"]), 64, Palette.ICE, width * 1.6, true)
		TurretSite.CONTESTED:
			ci.draw_arc(c, r, -PI / 2.0, PI / 2.0, 48, Palette.team(0), width * 1.3, true)
			ci.draw_arc(c, r, PI / 2.0, 3.0 * PI / 2.0, 48, Palette.team(1), width * 1.3, true)
		TurretSite.CLEAR:
			dashed_circle(ci, c, r, col, width * 1.3)
		_:
			dashed_circle(ci, c, r, Palette.with_alpha(Palette.NEUTRAL, 0.7), width)


## Draw a dashed circle (DASHES dashes with gaps as long as the dashes) of radius
## `r` at `c`, `width` wide, on canvas item `ci`.
static func dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, width: float) -> void:
	var step := TAU / float(DASHES)
	for i in DASHES:
		var a := step * float(i)
		ci.draw_arc(c, r, a, a + step * 0.5, 6, col, width, true)
