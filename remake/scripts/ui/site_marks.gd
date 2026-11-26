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
## own ring style and its own word (the short word() here; word_world() gives the long one that names the team,
## "AURELIAN HELD", "CONTESTED: Aurelian 2 v Vhorr 1"). T-126a: the team's mark (TeamMarks) sits on the ring, Vhorr's
## rings have teeth, and Aurelian's half of a contested ring is on the left:
##   HELD       a solid ring in the holder's colour, its mark on top   "HELD"
##   BUILDING   a dim solid ring with a bright arc that fills as the
##              turret is built; the builder's mark rides its head    "BUILDING 18s"
##   LOCKED     a grey ring with a light arc that shrinks as the lock
##              runs out                                               "LOCKED 42s"
##   CONTESTED  a ring split in two halves, one in each team's colour,
##              each with its mark at its middle                      "CONTESTED 2v1"
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


## The word for a view() dictionary on the map in the world, where there is room for the team's name (T-126a):
## "AURELIAN HELD", "VHORR BUILDING 18s", "LOCKED 42s", "CONTESTED: Aurelian 2 v Vhorr 1", "AURELIAN CLEAR", "OPEN",
## or "" for a plain site. word() keeps the short words (the minimap and the Admiral board show those).
static func word_world(v: Dictionary) -> String:
	var team := int(v["team"])
	match String(v["state"]):
		TurretSite.HELD:
			return "%s HELD" % Rules.TEAM_DISPLAY[team].to_upper()
		TurretSite.BUILDING:
			return "%s BUILDING %ds" % [Rules.TEAM_DISPLAY[team].to_upper(), int(v["left"])]
		TurretSite.CONTESTED:
			return "CONTESTED: %s %d v %s %d" % [Rules.TEAM_DISPLAY[0], int(v["p0"]), Rules.TEAM_DISPLAY[1], int(v["p1"])]
	return word(v)


## The view() dictionary of a plain ring that shows a team colour: it follows HELD (the holder's ring, the mark, and for Vhorr
## the teeth) without a word. `team` is the holder.
static func held_view(team: int) -> Dictionary:
	return {"state": TurretSite.HELD, "team": team, "left": 0, "progress": 0.0, "p0": 0, "p1": 0}


## Draw the ring of a view() dictionary `v` on canvas item `ci`, centred at `c`
## with radius `r` and line width `width` (see the table at the top). T-126a: the team's mark sits on the ring
## (TeamMarks, with its VOID outline) and Vhorr's rings carry teeth, so the team shows in shape as well as in colour.
## `px` is the size of one screen pixel in the units of `r` and `width`: 1.0 on the minimap (its picture is in pixels),
## the world's px (world units per screen pixel) in the world, so the mark and the teeth keep a constant size on the
## screen at any zoom. `in_world` picks the sizes: in the world the mark is 8 px and Vhorr's 8 teeth (22.5 degrees + k
## x 45) are 4 x 4 px; on the minimap the mark is 5 px and the 4 teeth (at the diagonals) are 2.4 wide and 2.2 long.
static func draw_ring(ci: CanvasItem, c: Vector2, r: float, v: Dictionary, width: float, px: float = 1.0, in_world: bool = false) -> void:
	var team := int(v["team"])
	var col := Palette.team(team) if team >= 0 else Palette.NEUTRAL
	var mark := (8.0 if in_world else 5.0)
	var edge := r + width * 0.5
	match String(v["state"]):
		TurretSite.HELD:
			ci.draw_arc(c, r, 0.0, TAU, 96, Palette.with_alpha(col, 0.55), width, true)
			_teeth(ci, c, edge, team, col, px, in_world, -PI, PI)
			TeamMarks.mark(ci, c + Vector2(0.0, -r), mark, team, px)
		TurretSite.BUILDING:
			ci.draw_arc(c, r, 0.0, TAU, 96, Palette.with_alpha(col, 0.3), width, true)
			var head := -PI / 2.0 + TAU * float(v["progress"])
			ci.draw_arc(c, r, -PI / 2.0, head, 64, col, width * 1.6, true)
			_teeth(ci, c, edge, team, Palette.with_alpha(col, 0.55), px, in_world, -PI, PI)
			# The builder's mark rides the head of the arc.
			TeamMarks.mark(ci, c + Vector2.from_angle(head) * r, mark, team, px)
		TurretSite.LOCKED:
			ci.draw_arc(c, r, 0.0, TAU, 96, Palette.with_alpha(Palette.NEUTRAL, 0.4), width, true)
			ci.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * float(v["progress"]), 64, Palette.ICE, width * 1.6, true)
		TurretSite.CONTESTED:
			# Aurelian's half is on the LEFT, so the picture reads in the word's order (Aurelian first).
			ci.draw_arc(c, r, PI / 2.0, 3.0 * PI / 2.0, 48, Palette.team(0), width * 1.3, true)
			ci.draw_arc(c, r, -PI / 2.0, PI / 2.0, 48, Palette.team(1), width * 1.3, true)
			# Each half carries its mark at its middle (9 and 3 o'clock) and the Vhorr half its teeth.
			_teeth(ci, c, edge, 1, Palette.team(1), px, in_world, -PI / 2.0, PI / 2.0)
			TeamMarks.mark(ci, c + Vector2(-r, 0.0), mark, 0, px)
			TeamMarks.mark(ci, c + Vector2(r, 0.0), mark, 1, px)
		TurretSite.CLEAR:
			dashed_circle(ci, c, r, col, width * 1.3)
			TeamMarks.mark(ci, c + Vector2(0.0, -r), mark, team, px)
		_:
			dashed_circle(ci, c, r, Palette.with_alpha(Palette.NEUTRAL, 0.7), width)


## Vhorr's teeth on a ring (nothing for any other team): in the world 8 teeth at 22.5 degrees + k x 45 (none under the
## mark at 12 o'clock), 4 x 4 px; on the minimap 4 teeth at the diagonals, 2.4 wide and 2.2 long. Only the teeth whose angle
## (radians, 0 = right, y down) lies between `from` and `to` are drawn, for a half ring. `edge` is the ring's outer edge.
static func _teeth(ci: CanvasItem, c: Vector2, edge: float, team: int, col: Color, px: float, in_world: bool, from: float, to: float) -> void:
	if not TeamMarks.is_wedge(team):
		return
	var all := TeamMarks.ring_angles(8, deg_to_rad(22.5)) if in_world else TeamMarks.ring_angles(4, PI / 4.0)
	var angles: Array[float] = []
	for a in all:
		var w := wrapf(a, -PI, PI)
		if w > from - 0.001 and w < to + 0.001:
			angles.append(w)
	if in_world:
		TeamMarks.teeth(ci, c, edge, angles, 4.0, 4.0, col, px)
	else:
		TeamMarks.teeth(ci, c, edge, angles, 2.4, 2.2, col, px)


## Draw a dashed circle (DASHES dashes with gaps as long as the dashes) of radius
## `r` at `c`, `width` wide, on canvas item `ci`.
static func dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, width: float) -> void:
	var step := TAU / float(DASHES)
	for i in DASHES:
		var a := step * float(i)
		ci.draw_arc(c, r, a, a + step * 0.5, 6, col, width, true)
