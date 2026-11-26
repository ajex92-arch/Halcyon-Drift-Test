class_name HudFeed
extends VBoxContainer
## WHAT THIS IS: the kill / event feed in the top-right corner of the HUD:
## short lines like "Wren shot down Pike's Bomber" or "Research complete:
## ...". It also remembers how the human's own ship last died, for the
## respawn banner.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_feed.tscn: one empty
## column, 330 pixels wide, 10 pixels in from the top-right corner and
## growing to the left, that the mouse passes through. The lines are made
## here in code, one per piece of news. Hud connects game news (Events) to
## the on_* functions here. Each one decides whether our side should hear
## about it, writes a sentence, and adds it as a line with add_line(), or with add_parts() when the sentence names teams or
## pilots (T-126a: a team mark, TeamMarks, goes before each name). A kill line reads "[mark] Ash [icon] [mark] Wren
## (Bomber)" (T-126b: the icon, KillIcons, is the weapon; a gold frame round it marks a kill that ended a streak of 3 or
## more, one round the killer's name a kill that made an ace, from the feed's own count of kills in a row); last_cause
## keeps the full sentence. T-125: a line about the human pilot (they shot a ship down, were shot down, or cleared a Scum den)
## sits on a dark plate and stays OWN_LIFE seconds instead of LIFE; its words, colours and who hears it are the same.
## Colours: amber for good news for us, cinder (red) for bad news, team
## colours for a spectator, mist (grey) for plain information. At most
## MAX_LINES lines are kept; Hud._refresh() fades each one out after LIFE
## seconds (fade_lines()).
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it. Hud.setup()
## gives it the world and connects Events.feed, unit_killed,
## turret_destroyed, site_state_changed, research_done and facility_done to it. HudBanner reads
## last_cause; Hud._on_respawned() clears it. Hud also uses fade_lines()
## for HudMePanel's earnings log.

## Most lines the feed shows at once (older ones are removed).
const MAX_LINES := 7
## How long (seconds) a feed line stays. It fades out during its last 1.5
## seconds.
const LIFE := 9.0
## T-125: how long (seconds) a line about the human pilot stays (its last 1.5 seconds fade, as any line's do).
const OWN_LIFE := 14.0
## T-125: how see-through the dark plate behind a line about the human is (the void colour at this alpha).
const OWN_PLATE_ALPHA := 0.6
## T-125: the plate's padding in pixels (UiKit.box adds 2 to the left and right margins, so the sides take 2 x (this + 2)).
const OWN_PAD := 2

## The game world (Hud.setup() sets it).
var world: World
## How the human's own ship was last destroyed ("Wren shot down Pike's
## Bomber"), shown on the respawn banner; "" after they respawn.
var last_cause := ""


## Fade out and remove the old lines of `box`. Every line remembers when it
## was made ("born" metadata, in milliseconds). A line older than `life`
## seconds is removed; during its last 1.5 seconds it fades (modulate.a is
## its see-through amount: 1 = solid, 0 = invisible). T-125: a line that carries its own "life" metadata (seconds; a line
## about the human) lives that long instead of `life`; a line without it behaves as before.
static func fade_lines(box: Container, life: float) -> void:
	var now := Time.get_ticks_msec()
	for c in box.get_children():
		var own_life := float(c.get_meta("life", life))
		var age := float(now - int(c.get_meta("born", now))) / 1000.0
		if age > own_life:
			c.queue_free()
		elif age > own_life - 1.5:
			(c as CanvasItem).modulate.a = (own_life - age) / 1.5
	# (queue_free removes a node at the end of the frame, not at once.)


## Add one line of `text` in colour `col`, right-aligned with a dark
## outline so it reads over the game. Drops the oldest lines past MAX_LINES.
func add_line(text: String, col: Color) -> void:
	var l := UiKit.label(text, 13, col, true)
	l.custom_minimum_size = Vector2(330, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Palette.VOID)
	l.add_theme_constant_override("outline_size", 4)
	l.set_meta("born", Time.get_ticks_msec())
	# News that is bad for us is in the danger colour and always carries the danger triangle (colour is never the only sign).
	if col == Palette.DANGER:
		var m := DangerMark.new(12.0)
		m.position = Vector2(0.0, 1.0)
		l.add_child(m)
	add_child(l)
	while get_child_count() > MAX_LINES:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()


## T-126a: add one line made of pieces, so each team name carries the team's mark (TeamMarks, 10 px, centred on the text's
## middle with a 4 px gap). `parts` is a list: a String is a piece of text (the line's words, in `col`, unchanged), an int
## (0 = Aurelian, 1 = Vhorr) puts that team's mark here, in the team colour. Anything else is skipped. The text of the line
## is every String joined. Without a mark it is the plain add_line(). With marks the line is a row that wraps like the
## plain one (a flow container 330 px wide, right-aligned) of one label per WORD and one mark per team, each label with the
## plain line's look; the danger triangle (bad news) stands at the column's left edge, as in the plain line. A Dictionary is
## a piece of T-126b: {"icon": glyph, "streak": bool} puts a kill icon (KillIcons.View) here, in the line's colour, framed
## when "streak" is true; {"name": text, "ace": bool} puts a name, framed when "ace" is true (its text counts in the line's
## text; an icon adds none). A row's "text" meta is those words with one space between the pieces (_speak()); the plain line's
## text, and every label on screen, are as they were. T-125: with `own` true (the line is about the human pilot) the line is
## always a row, a bit narrower, inside a plate (a PanelContainer of the void colour at OWN_PLATE_ALPHA with a 1 px mist edge)
## that carries the "born", "text" and "life" (OWN_LIFE) metadata, so the column is still 330 px wide.
func add_parts(parts: Array, col: Color, own := false) -> void:
	var text := ""
	var spoken := ""
	var marks := 0
	var extras := 0
	for p: Variant in parts:
		if p is String:
			text += p
			spoken = _speak(spoken, p)
		elif p is int:
			marks += 1
		elif p is Dictionary:
			extras += 1
			if (p as Dictionary).has("name"):
				text += String((p as Dictionary)["name"])
				spoken = _speak(spoken, String((p as Dictionary)["name"]))
	if marks == 0 and extras == 0 and not own:
		add_line(text, col)
		return
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_END
	# A line on a plate is narrower by the plate's two side margins, so the plate is as wide as the column.
	row.custom_minimum_size = Vector2(330 - (2 * (OWN_PAD + 2) if own else 0), 0)
	row.add_theme_constant_override("h_separation", 0)
	row.add_theme_constant_override("v_separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_h := ThemeDB.fallback_font.get_height(13)
	for p: Variant in parts:
		if p is String:
			# One label per word, so the row wraps between words (a long sentence is never one piece wider than the column).
			# A word keeps the space that followed it, so the spacing is the plain line's.
			var words := String(p).split(" ")
			for i in words.size():
				var w := String(words[i])
				if i < words.size() - 1:
					w += " "
				if w == "":
					continue
				var l := UiKit.label(w, 13, col)
				l.add_theme_color_override("font_outline_color", Palette.VOID)
				l.add_theme_constant_override("outline_size", 4)
				row.add_child(l)
		elif p is int:
			row.add_child(TeamMarks.View.new(int(p), 10.0, line_h))
		elif p is Dictionary:
			# T-126b: {"icon": glyph, "streak": bool} is a kill icon (KillIcons) in the line's colour, with the streak frame when
			# it is set; {"name": callsign, "ace": bool} is a name, with the ace's name frame when it is set.
			var piece := p as Dictionary
			if piece.has("icon"):
				row.add_child(KillIcons.View.new(int(piece["icon"]), col, bool(piece.get("streak", false)), line_h))
			elif piece.has("name"):
				if bool(piece.get("ace", false)):
					row.add_child(KillIcons.NameTag.new(String(piece["name"]), col))
				else:
					var nl := UiKit.label(String(piece["name"]), 13, col)
					nl.add_theme_color_override("font_outline_color", Palette.VOID)
					nl.add_theme_constant_override("outline_size", 4)
					row.add_child(nl)
	# The line is the row; news that is bad for us puts the danger triangle at the column's left edge, as add_line() does (a
	# layer of its own over the row, so the flow does not move it).
	var line: Control = row
	if col == Palette.DANGER:
		var wrap := MarginContainer.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(row)
		var layer := Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := DangerMark.new(12.0)
		m.position = Vector2(0.0, 1.0)
		layer.add_child(m)
		wrap.add_child(layer)
		line = wrap
	if own:
		# T-125: the plate round the line; it is the node the feed keeps, so the metadata sit on it.
		var plate := PanelContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", UiKit.box(Color(Palette.VOID, OWN_PLATE_ALPHA), Palette.MIST, OWN_PAD))
		plate.add_child(line)
		plate.set_meta("life", OWN_LIFE)
		line = plate
	line.set_meta("born", Time.get_ticks_msec())
	line.set_meta("text", spoken)
	add_child(line)
	while get_child_count() > MAX_LINES:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()


## `so_far` with `piece` after it, one space between them unless one side already has it: the words of a kill line as they read
## aloud ("Ash Wren (Bomber)"), where the icon and the marks between the names have no letters.
func _speak(so_far: String, piece: String) -> String:
	if so_far != "" and not so_far.ends_with(" ") and not piece.begins_with(" "):
		so_far += " "
	return so_far + piece


## `[team]` when `team` is Aurelian or Vhorr (the one mark of a name's piece list), else nothing: the Scum and "Someone" get none.
func _mk(team: int) -> Array:
	return [team] if team == Rules.HALCYON or team == Rules.CINDER else []


## The room (pixels of height) HudLayout last gave the column (fit()); no limit before the first call.
var _room := INF


## Godot calls this once when the feed enters the scene. The column fits its lines again each time it has laid them
## out (the container's sort_children signal: a new line has its real height by then), so a line added while the HUD
## is not refreshing (the game held paused, the pause menu's Look around) cannot reach over the minimap either.
func _ready() -> void:
	sort_children.connect(func() -> void: fit(_room))


## Show only as many of the newest lines as fit in `room` pixels of height (HudLayout gives the room between the
## feed's top and the minimap or the seat bar under it); the older ones are hidden, not removed, so they come back
## when there is room again. The newest line always shows. A hidden line takes no room in the column.
func fit(room: float) -> void:
	_room = room
	var sep := float(get_theme_constant("separation"))
	var used := 0.0
	var full := false
	var newest := true
	for i in range(get_child_count() - 1, -1, -1):
		var c := get_child(i) as Control
		if c == null or c.is_queued_for_deletion():
			continue
		if not full:
			used += maxf(c.size.y, c.get_combined_minimum_size().y) + (0.0 if newest else sep)
			full = used > room and not newest
		newest = false
		if c.visible == full:
			c.visible = not full
	# A column never shrinks by itself when its lines take less room: give it its smallest height again, so its box
	# (and the lines in it) end where the showing lines end.
	if size.y > get_combined_minimum_size().y + 0.5:
		size.y = 0.0
		queue_sort()


## The tick of the last contest or clear line for each shared site (site id ->
## World.tick_count), so a site gets at most one such line every 10 seconds.
var _site_line_tick := {}


## A turret site changed state (Events.site_state_changed). Only the four shared
## jungle sites speak, in three lines: a team starts a turret there (public), and
## pilot ships of both teams are there ("contest") or only one team's are ("can
## build"), lines that only a team with a pilot ship or minion inside or sight of
## the centre hears (SiteMarks.knows). At most one contest or clear line per site
## every 600 ticks (10 s); minions alone start no line.
func on_site_state(site_id: String, state: String, team: int, tick: int) -> void:
	var n := world.node_by_id(site_id)
	if n == null or n.node_kind != "jungle_shared":
		return
	var site_name := Rules.display_label(n.node_name)
	if state == TurretSite.BUILDING:
		add_parts(_mk(team) + ["%s starts a turret at %s (%d s)" % [Rules.TEAM_DISPLAY[team], site_name, int(TurretData.TURRETS["pd"]["build"])]], Palette.MIST)
		return
	if state != TurretSite.CONTESTED and state != TurretSite.CLEAR:
		return
	var s := n.site
	if tick - int(_site_line_tick.get(site_id, -100000)) < 600 or not SiteMarks.knows(world, n, _vt()):
		return
	if state == TurretSite.CONTESTED and int(s.pilots[0]) > 0 and int(s.pilots[1]) > 0:
		_site_line_tick[site_id] = tick
		add_parts([0, "%s and " % Rules.TEAM_DISPLAY[0], 1, "%s ships contest %s" % [Rules.TEAM_DISPLAY[1], site_name]], Palette.MIST)
	elif state == TurretSite.CLEAR and int(s.pilots[team]) > 0:
		_site_line_tick[site_id] = tick
		add_parts(_mk(team) + ["%s can build at %s: no enemy inside" % [Rules.TEAM_DISPLAY[team], site_name]], Palette.MIST)


## The team whose eyes we see through (-1 = a spectator who sees all).
func _vt() -> int:
	return world.viewer_team


## The colour for news that is good for `team`: amber if that is our
## team, the danger colour (with the triangle, see add_line) if not, whichever team the human plays (amber means good
## news here, it is not the interface's highlight colour). A spectator sees
## team colours instead.
func _good_bad(team: int) -> Color:
	if _vt() < 0:
		return Palette.team(team)
	return Palette.AMBER if team == _vt() else Palette.DANGER


## A plain feed message (Events.feed). `tone` is "good", "bad" or "info";
## `team` is whose news it is (-1 = everyone's). We hide the enemy's own
## good and bad news, and also their "free mining drone" info lines. The
## feature modules build their messages from the internal team labels
## (Rules.TEAM_NAMES, and place names such as "Halcyon Mid"), so the line
## goes through Rules.display_label() to show the player-facing names.
func on_feed(text: String, tone: String, team: int) -> void:
	if team >= 0 and _vt() >= 0 and team != _vt() and tone != "info":
		return
	if team >= 0 and _vt() >= 0 and team != _vt() and text.contains("free mining drone"):
		return
	add_line(Rules.display_label(text), Palette.MIST if tone == "info" else Palette.ICE)


## Something died (Events.unit_killed). `info` is the DamageInfo of the
## killing blow. Ships always get a line, repair bays and defense posts too; a cleared
## derelict only when our side cleared it. Other kills are not shown.
func on_unit_killed(u: Node, info: RefCounted) -> void:
	var d := info as DamageInfo
	var unit := u as Unit
	if unit == null:
		return
	var killer: PilotProfile = d.source_profile as PilotProfile
	match unit.kind:
		Unit.K_SHIP:
			# A ship: say who or what destroyed it, coloured for the
			# killer's side (good for us if an enemy ship died).
			var s := unit as Ship
			var victim := s.profile
			var cause := _ship_cause(s, d, killer)
			# T-126b: the feed's own count of kills in a row (UI only), read before this death clears the victim's.
			var tally := tally_kill(victim, killer, s.team)
			# T-125: a line is about the human when they killed or died (never when there is no human pilot).
			var mine := world.human != null and (killer == world.human or victim == world.human)
			add_parts(_ship_line(s, d, killer, tally["streak"], tally["ace"]), _good_bad(1 - s.team) if _vt() >= 0 else Palette.team(1 - s.team), mine)
			if victim != null and victim == world.human:
				last_cause = cause
		Unit.K_BAY:
			add_parts([{"icon": KillIcons.BAY_LOST}] + _mk(unit.team) + ["%s repair bay at %s destroyed" % [Rules.TEAM_DISPLAY[unit.team], Rules.display_label(world.place_name(unit.global_position))]], _good_bad(1 - unit.team))
		Unit.K_POST:
			add_parts([{"icon": KillIcons.POST_LOST}] + _mk(unit.team) + ["%s %s defense post destroyed" % [Rules.TEAM_DISPLAY[unit.team], str(MapLayout.LANES[(unit as DefensePost).lane]["label"]).to_lower()]], _good_bad(1 - unit.team))
		Unit.K_MONSTER:
			if killer != null and (_vt() < 0 or killer.team == _vt()):
				add_parts([{"icon": KillIcons.DEN_CLEARED}] + _mk(killer.team) + ["%s collected the bounty on a %s" % [killer.callsign, unit.display_name]], Palette.SCUM_BOLT, world.human != null and killer == world.human)


## T-126b: the feed's own count of each pilot's kills since their last death (PilotProfile -> int). Kept here because the
## economy clears the victim's streak before the feed hears the kill. UI state only: nothing in the match reads it.
var _run := {}


## Count one ship kill in the feed's own tally: pilot `victim` (null: none; a bought ship's crew is not counted, as the economy does
## not count it) of team `victim_team` was destroyed, the last hit by pilot `killer` (null: no pilot). Returns {"streak": the
## victim had Rules.ACE_KILLS or more kills in a row when they died, "ace": this kill brought the killer's count to
## Rules.ACE_KILLS}; the victim's count is then 0, the killer's one more (a kill of their own team counts for nothing).
func tally_kill(victim: PilotProfile, killer: PilotProfile, victim_team: int) -> Dictionary:
	var out := {"streak": false, "ace": false}
	if victim != null and victim.is_crew:
		return out
	if victim != null:
		out["streak"] = int(_run.get(victim, 0)) >= Rules.ACE_KILLS
		_run[victim] = 0
	if killer != null and killer.team != victim_team:
		_run[killer] = int(_run.get(killer, 0)) + 1
		out["ace"] = int(_run[killer]) == Rules.ACE_KILLS
	return out


## The line of a ship kill, as the piece list add_parts() takes: "[mark] Ash [icon] [mark] Wren (Bomber)". The killer is a
## pilot (name, with the ace's name frame when `made_ace`), or the team of the unit that fired ("[mark] Vhorr [turret icon]"), or
## nothing at all for the Scum, an asteroid and a blow with no source ("[rock icon] ..."). The icon is the blow's glyph
## (KillIcons.glyph_for), with the streak frame when the kill ended a streak (`streak_ended`). Then the victim.
func _ship_line(s: Ship, d: DamageInfo, killer: PilotProfile, streak_ended: bool, made_ace: bool) -> Array:
	var victim := s.profile
	var hull := String(Ships.HULLS[s.hull_id]["label"])
	var vname := victim.callsign if victim != null else "A pilot"
	var vteam := s.team if victim != null else -1
	if victim != null and victim.is_crew:
		vname = Rules.TEAM_DISPLAY[s.team]
	var who: Array = []
	if killer != null:
		who = _mk(killer.team) + ([{"name": killer.callsign, "ace": true}] if made_ace else [killer.callsign])
	elif d.kind != Rules.W_COLLISION and d.source != null and is_instance_valid(d.source) and d.source.team != Rules.NEUTRAL:
		who = _mk(d.source.team) + [Rules.TEAM_DISPLAY[d.source.team]]
	elif d.kind != Rules.W_COLLISION and d.source_uid >= 0 and d.source_team != Rules.NEUTRAL:
		# The firing unit is gone (a minion's round landed after it died): the note kept its team.
		who = _mk(d.source_team) + [Rules.TEAM_DISPLAY[d.source_team]]
	return who + [{"icon": KillIcons.glyph_for(d), "streak": streak_ended}] + _mk(vteam) + ["%s (%s)" % [vname, hull]]


## The sentence for ship `s` being destroyed by the blow `d` (fired by
## pilot `killer`, or null when no pilot did it): shot down by a pilot,
## crashed into an asteroid, destroyed by something else (a turret, a
## minion, a mothership, a Scum ship...), or just "destroyed".
func _ship_cause(s: Ship, d: DamageInfo, killer: PilotProfile) -> String:
	return _join_text(_ship_parts(s, d, killer))


## Every String of the piece list `parts` joined (see add_parts()): the line's sentence.
func _join_text(parts: Array) -> String:
	var text := ""
	for p: Variant in parts:
		if p is String:
			text += p
	return text


## The sentence _ship_cause() gives, as the piece list add_parts() takes: the same words, with a team mark (an int) before
## each pilot's callsign (that pilot's ship team) and before each team word ("Aurelian", "Vhorr"). A pilot with no profile
## ("A pilot") and the Scum have no mark.
func _ship_parts(s: Ship, d: DamageInfo, killer: PilotProfile) -> Array:
	var victim := s.profile
	var hull := String(Ships.HULLS[s.hull_id]["label"])
	var vname := victim.callsign if victim != null else "A pilot"
	var vteam := s.team if victim != null else -1
	# A bought ship's crew has no name worth showing: the line names its team.
	if victim != null and victim.is_crew:
		vname = Rules.TEAM_DISPLAY[s.team]
	var parts: Array = []
	if killer != null:
		parts = _mk(killer.team) + [killer.callsign + " shot down "] + _mk(vteam) + ["%s's %s" % [vname, hull]]
	elif d.kind == Rules.W_COLLISION:
		parts = _mk(vteam) + ["%s's %s crashed into an asteroid" % [vname, hull]]
	elif d.source != null and is_instance_valid(d.source):
		# Name the thing that fired, with its team: "a Vhorr turret", "an Aurelian minion",
		# "the Aurelian mothership" or "a Scum Raider".
		var by: Array = []
		var what: String = Unit.KIND_NAMES[d.source.kind]
		if d.source.kind == Unit.K_MOTHERSHIP:
			by = ["the "] + _mk(d.source.team) + ["%s mothership" % Rules.TEAM_DISPLAY[d.source.team]]
		elif d.source.team == Rules.NEUTRAL:
			by = ["a " + String(d.source.display_name)]
		else:
			var tn: String = Rules.TEAM_DISPLAY[d.source.team]
			by = ["an " if "AEIOU".contains(tn.left(1)) else "a "] + _mk(d.source.team) + ["%s %s" % [tn, what]]
		parts = _mk(vteam) + ["%s's %s was destroyed by " % [vname, hull]] + by
	else:
		parts = _mk(vteam) + ["%s's %s was destroyed" % [vname, hull]]
	return parts


## A turret was destroyed (Events.turret_destroyed) by team `by_team`
## (-1 = nobody's, shown as "Someone"). Names its resource node, or, if it
## has none, the name World.place_name() gives the spot where it stood.
func on_turret_destroyed(t: Node, by_team: int) -> void:
	var tu := t as Turret
	if tu == null:
		return
	var where := Rules.display_label(tu.node.node_name if tu.node != null else world.place_name(tu.global_position))
	add_parts([{"icon": KillIcons.TURRET_LOST}] + _mk(by_team) + ["%s destroyed the " % (Rules.TEAM_DISPLAY[by_team] if by_team >= 0 else "Someone")] + _mk(tu.team) + ["%s %s at %s" % [Rules.TEAM_DISPLAY[tu.team], String(tu.tdef["label"]), where]], _good_bad(by_team))


## Team `team` finished research `id` (Events.research_done). Only our
## own team's research is shown. If it unlocked a ship that can now be
## bought, the line says so.
func on_research_done(team: int, id: String) -> void:
	if _vt() >= 0 and team != _vt():
		return
	var d: Dictionary = Tech.TECHS[id]
	var extra := ""
	var eff: Dictionary = d["effect"]
	if eff.has("unlock_ship"):
		var sid: String = eff["unlock_ship"]
		if world.teams[team].ship_unlocked(sid):
			extra = " %s can now be bought in the hangar." % Ships.HULLS[sid]["label"]
	add_line("Research complete: %s.%s" % [d["label"], extra], Palette.REPAIR)


## Team `team` finished building mothership module `id`
## (Events.facility_done). Only our own team's modules are shown. Ships
## that this module unlocks ("fac:<id>" in Ships.HULLS) are named; if
## there are several, the last one in Ships.ORDER wins.
func on_facility_done(team: int, id: String) -> void:
	if _vt() >= 0 and team != _vt():
		return
	var extra := ""
	for sid: String in Ships.ORDER:
		if Ships.HULLS[sid]["unlock"] == "fac:" + id:
			extra = " %s can now be bought in the hangar." % Ships.HULLS[sid]["label"]
	add_line("Module built: %s.%s" % [Tech.FACILITIES[id]["label"], extra], Palette.REPAIR)
