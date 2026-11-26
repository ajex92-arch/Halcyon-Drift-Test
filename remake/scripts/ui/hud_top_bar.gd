class_name HudTopBar
extends PanelContainer
## WHAT THIS IS: the strip at the top centre of the HUD: the match clock,
## when the next minion wave launches ("Next wave 0:21"), the difficulty tag (the level the match is
## played at, one word, "Hard", for a match with a human seat that is not the Admiral's: the Admiral's
## strip at the top right (TopStrip) has it, and the speed, instead; see Difficulty), the tag PRACTICE (first in the tag line, shown for
## the whole of a practice range: World.practice), the test tags (UNLOCKED, shown while the
## human buys for nothing, see UnlockAll; FOG OFF, shown while the No fog test option
## is on (see FogOff); AI V0 / AI WEAK / AI CUSTOM, shown while the computer Admiral's profile is not the
## standard one, and AI MEMORY, shown while the memory rings are on (MemoryRings); SPEED 0.75x / 0.5x / 1.5x / 2x, shown while
## the world is not at normal speed, see WorldSpeed, and "(limited)" after it when the
## PC cannot keep that speed up), and for each team its mothership's
## hull bar, any mothership trouble, and how many turrets it has in each
## lane and how many of its three defense posts stand. It is also the who-is-ahead bar: each
## team's value (its pilots' ships, modules and gear at list prices) sits beside its hull bar, and
## one thin two-colour bar in the middle column has a marker that slides towards the team that is
## ahead, with a few plain words under it ("Level", "You lead", "They lead", or the team's name for a
## spectator, "No data seen yet" while nothing of the enemy has been seen). The marker is worked out
## from the motherships' hulls, the turrets, the defense posts and the team values (lead_share()).
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_top_bar.tscn: a
## see-through dark panel (the "TopBarLook" look) 6 pixels below the top
## edge, centred, holding one row: Halcyon's column (Name, the hull row with the team's value and
## its Hull bar, Turrets, Note), the Middle column (Clock, Wave, DiffTag, Tags, the Lead bar and its
## words) and Cinder's column. Cinder's
## side is a mirror image: its text is right-aligned and its bar fills from
## the right. The mouse passes through it to the game (the difficulty tag takes
## the pointer only to show its tooltip, with the pass filter, so clicks under it
## still reach the map). _ready() colours
## each team's name and bar; refresh() rewrites the text 10 times a second.
## Enemy turrets are only counted once our team has seen them (at once with No fog on, see FogOff).
## The same fog rule runs the rest: with fog (a seat with a viewer team, No fog off) our own team is
## shown whole, an enemy mothership's hull bar holds what it read the last time the mothership was in
## view (full while it was never seen) with a note under the turret line ("mothership in view", "not
## seen" or "1:30 ago"), and the enemy's value counts only the pilot ships in view and reads "Seen
## 4.2k" instead of "Value 4.2k". Without fog (a spectator, or No fog on) everything is the truth.
## The marker's score is the weighted share (WEIGHTS) of four parts: the mothership readings, the
## turret counts, the post counts and the team values. A part joins the score once the viewer has data
## on the enemy side of it and stays in (a latch per part, `_has`), so a bar that has seen nothing says
## "No data seen yet". While an enemy side is only partly seen the marker leans to the viewer's side.
## In a practice range the new widgets are hidden: there is no match to be ahead in.
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it and
## Hud._refresh() calls refresh(). It reads World (clock, motherships,
## teams, turrets) and MinionDirector (when the next wave launches), and each team's value
## through MatchSeries.team_value(); tests/ahead_bar_check.gd checks the marker, the fog rule and the
## words.

## How much the motherships' hull readings count in the score (the four weights add up to 1). A
## guess, not a final balance: the mothership counts most, a defense post least.
const WEIGHT_MS := 0.40
## How much the turret counts count in the score.
const WEIGHT_TURRETS := 0.25
## How much the defense post counts count in the score.
const WEIGHT_POSTS := 0.10
## How much the team values count in the score.
const WEIGHT_VALUE := 0.25
## The four weights by part name.
const WEIGHTS := {"ms": WEIGHT_MS, "turrets": WEIGHT_TURRETS, "posts": WEIGHT_POSTS, "value": WEIGHT_VALUE}
## The marker counts as level while its share is within this of the middle (0.5): 5 either way, the designer's pick.
const LEVEL_BAND := 0.05
## How long, in seconds, the marker bar's flash fades after a turret falls in view. A guess.
const FLASH_SECONDS := 0.6
## The fewest match seconds between two flashes: a fall inside the gap is dropped, not queued. A guess.
const FLASH_MIN_GAP := 2.0
## How bright the marker bar gets at the start of a flash (1 = no change). A guess.
const FLASH_BRIGHT := 2.2

## The match clock ("12:34").
@onready var _clock: Label = $Row/Middle/Clock
## "Next wave 0:21" (or that no more waves are due: wave_line()).
@onready var _wave: Label = $Row/Middle/Wave
## The difficulty tag under the wave line ("Hard"); hidden for the Admiral and in a match
## with no human seat. Pointing at it shows the full sentence.
@onready var _diff: Label = $Row/Middle/DiffTag
## The test tags under the difficulty tag ("UNLOCKED", "FOG OFF"); hidden while there are none.
@onready var _tags: Label = $Row/Middle/Tags
## Each team's mothership hull bar (index = team: 0 Aurelian, 1 Vhorr).
@onready var _ms_bars: Array[ProgressBar] = [$Row/Halcyon/HullRow/Hull, $Row/Cinder/HullRow/Hull]
## Each team's name, hull percent and any mothership trouble.
@onready var _ms_labels: Array[Label] = [$Row/Halcyon/Name, $Row/Cinder/Name]
## Each team's turret count per lane.
@onready var _turret_labels: Array[Label] = [$Row/Halcyon/Turrets, $Row/Cinder/Turrets]
## The who-is-ahead bar in the middle column: team 0's colour fills from the left, team 1's is the
## rest, and the two meet at the marker.
@onready var _lead: ProgressBar = $Row/Middle/Lead
## The words under the marker ("Level", "You lead", ...).
@onready var _lead_text: Label = $Row/Middle/LeadText
## Each team's value beside its hull bar ("Value 4.2k", or "Seen 4.2k" for a fogged enemy).
@onready var _values: Array[Label] = [$Row/Halcyon/HullRow/Value, $Row/Cinder/HullRow/Value]
## Each team's note under its turret line: the fogged enemy mothership's last-seen line.
@onready var _notes: Array[Label] = [$Row/Halcyon/Note, $Row/Cinder/Note]
## The world the last refresh read (null until the first refresh).
var _world: World = null
## Each team's mothership hull reading as it was last in view (1.0 until the first sight).
var _ms_seen := [1.0, 1.0]
## The match time each mothership was last in view (-1 = never).
var _ms_seen_t := [-1.0, -1.0]
## One latch per part of the score: true once the viewer has data on the enemy side of that part.
var _has := {"ms": false, "turrets": false, "posts": false, "value": false}
## Each team's four numbers of the last refresh: the mothership reading shown, the turret count, the
## post count and the value.
var _nums: Array[Dictionary] = [{}, {}]
## The parts the last refresh gave the marker: per part [team 0's number, team 1's number, has data].
var _parts := {}
## Seconds of the flash left (0 = no flash).
var _flash_left := 0.0
## The match time of the last flash (far in the past until the first).
var _flash_last := -999.0
## The team that brought down the turret of the last flash (-1 until the first).
var _flash_team := -1


## Godot calls this when the bar joins the HUD: give each team's name line
## and hull bar the team's colour, and the lead bar the two team colours, and listen for the
## turrets that fall. (The test tags pick the interface's highlight colour by name in the scene.)
func _ready() -> void:
	for t in 2:
		_ms_labels[t].add_theme_color_override("font_color", Palette.team(t))
		UiKit.tint_bar(_ms_bars[t], Palette.team(t))
	UiKit.tint_bar(_lead, Palette.team(0))
	var rest := StyleBoxFlat.new()
	rest.bg_color = Palette.team(1)
	_lead.add_theme_stylebox_override("background", rest)
	Events.turret_destroyed.connect(_on_turret_destroyed)
	set_process(false)


## Godot calls this when the bar leaves the HUD: stop listening for fallen turrets.
func _exit_tree() -> void:
	if Events.turret_destroyed.is_connected(_on_turret_destroyed):
		Events.turret_destroyed.disconnect(_on_turret_destroyed)


## A turret fell (Events.turret_destroyed, sent while the turret is still whole). Flash the marker
## bar, with no sound, unless the viewer cannot see the fall (with fog, an enemy turret that is not
## in view) or the last flash was less than FLASH_MIN_GAP match seconds ago. The kill feed is not
## touched: it still prints every fall.
func _on_turret_destroyed(turret: Node, by_team: int) -> void:
	if _world == null or not is_instance_valid(turret):
		return
	var vt := _world.viewer_team
	var unit := turret as Unit
	if vt >= 0 and not FogOff.is_on() and unit.team != vt and not unit.visible_to(vt):
		return
	if _world.time - _flash_last < FLASH_MIN_GAP:
		return
	_flash_last = _world.time
	_flash_left = FLASH_SECONDS
	_flash_team = by_team
	set_process(true)


## Godot calls this every frame while a flash lasts: fade the marker bar from bright back to normal.
func _process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	var bright := Color(FLASH_BRIGHT, FLASH_BRIGHT, FLASH_BRIGHT)
	_lead.modulate = Color(1, 1, 1).lerp(bright, _flash_left / FLASH_SECONDS)
	if _flash_left <= 0.0:
		_lead.modulate = Color(1, 1, 1)
		set_process(false)


## Rewrite the clock, the wave timer and both teams' columns.
func refresh(world: World) -> void:
	# Step 1: the clock and the wave timer (the free waves never stop; wave_line()).
	UiKit.set_text(_clock, Util.clock(world.time))
	UiKit.set_text(_wave, wave_line(world.minion_director, world.time))
	# Step 1a: the difficulty tag, from the number the enemy team really earns by
	# (Difficulty.tag_mult(), -1 when the match names no level: no human seat, or
	# humans on both teams); its hover is the full sentence. The Admiral's strip at the
	# top right (TopStrip) shows the word, so the Admiral's box does not.
	var admiral := world.human_role == "admiral"
	var enemy_mult := Difficulty.tag_mult(world)
	_diff.visible = enemy_mult >= 0.0 and not admiral
	if _diff.visible:
		UiKit.set_text(_diff, Difficulty.short_tag_for(enemy_mult))
		_diff.tooltip_text = Difficulty.blurb_for(enemy_mult)
	# Step 1b: the test tags: UNLOCKED while the human's purchases are free
	# (UnlockAll), FOG OFF while the No fog option shows everything (FogOff; the spectator
	# has no fog, so no tag), SPEED 0.75x / 0.5x / 1.5x / 2x while the world is not at normal
	# speed (WorldSpeed.tag(), empty at normal speed), with "(limited)" after it
	# when the PC cannot keep up; the line is hidden when there is nothing to say.
	var tags := PackedStringArray()
	if world.practice:
		tags.append("PRACTICE")
		if world.minion_director.frozen:
			tags.append("WAVES FROZEN")
		if world.practice_range != null and world.practice_range.no_cooldowns:
			tags.append("NO COOLDOWNS")
	if UnlockAll.is_unlocked(world.human):
		tags.append("UNLOCKED")
	if FogOff.is_on() and world.viewer_team >= 0:
		tags.append("FOG OFF")
	# The computer Admiral's test options: AI V0 / AI WEAK / AI CUSTOM while its profile is not the standard one
	# (StartScreen.profile_choice()), AI MEMORY while the memory rings are on (MemoryRings, kept in step here).
	var ai_profile := StartScreen.profile_choice(Game.options)
	if ai_profile != "standard":
		tags.append("AI " + ai_profile.to_upper())
	if Game.show_ai_memory:
		tags.append("AI MEMORY")
	MemoryRings.mount(self, world)
	var speed_tag: String = world.speed.tag()
	if speed_tag != "" and not admiral:   # the Admiral's strip has the speed button
		tags.append(speed_tag + (" (limited)" if SpeedControl.limited(world) else ""))
	UiKit.set_text(_tags, "  ·  ".join(tags))
	_tags.visible = not tags.is_empty()
	# Step 2: each team's column. vt = the team we watch as (-1 = we see
	# everything, as a spectator).
	var vt := world.viewer_team
	_world = world
	for t in 2:
		_refresh_team(world, t, vt)
	# Step 3: the who-is-ahead marker and its words (not in a practice range: no match to be ahead in).
	var live := not world.practice
	_lead.visible = live
	_lead_text.visible = live
	if live:
		_refresh_lead(vt, vt >= 0 and not FogOff.is_on())


## The wave timer's text at match time `time` (seconds). The free waves never
## stop on their own, but when no wave is due ever again (next_wave is INF: the
## waves_late variant "none") there is no countdown to show.
static func wave_line(md: MinionDirector, time: float) -> String:
	if md.frozen:
		return "Waves frozen"
	if is_inf(md.next_wave):
		return "No more minion waves"
	return "Next wave %s" % Util.clock(maxf(0.0, md.next_wave - time))


## Rewrite team `t`'s hull bar, name line, turret line, value and note. With fog (a viewer team and
## No fog off) the other team's mothership is read only while the viewer can see it: the bar then
## holds the last reading, and the note says how long ago that was.
func _refresh_team(world: World, t: int, vt: int) -> void:
	var ms := world.mothership(t)
	var ts := world.teams[t]
	var foe := vt >= 0 and not FogOff.is_on() and t != vt
	var in_view := false
	var shown: float
	if foe:
		in_view = ms.visible_to(vt)
		if in_view:
			_ms_seen[t] = ms.hull_frac()
			_ms_seen_t[t] = world.time
		shown = _ms_seen[t]
	else:
		shown = ms.hull_frac()
	_ms_bars[t].value = shown
	# Step 1: mothership trouble. At 35% hull a mothership can have one
	# emergency, a "systems failure" (it counts down in seconds).
	# "Strained" means too many pilots respawned at once. "Plating holding"
	# means the ms_cap variant is capping the hull damage right now.
	var extra := ""
	if ms.failure_t > 0.0:
		extra = "  SYSTEMS FAILURE %ds" % int(ceil(ms.failure_t))
	elif ts.strain_t > 0.0:
		extra = "  STRAINED"
	elif ms.incoming_mults.has("ms_cap"):
		# The ms_cap variant (MsCapFeature) is holding the hull damage down.
		extra = "  PLATING HOLDING"
	# The status tags of the orders that feature modules add (for example
	# "FORTIFIED 3s"); none in today's game.
	if not world.command.orders.is_empty():
		extra += CommandOrders.hud_tag(world, t, vt)
	# Step 2: the name line, "Aurelian (us)  STRAINED" (the hull bar under it
	# shows the hull, so no percent). Vhorr's is written the other way round
	# ("STRAINED  Vhorr (enemy)"), so on both sides the team name sits at the
	# outer edge.
	var tname: String = Rules.TEAM_DISPLAY[t]
	if vt >= 0:
		tname += " (us)" if t == vt else " (enemy)"
	var txt := "%s%s" % [tname, extra]
	if t == 1:
		txt = "%s  %s" % [extra.strip_edges(), tname]
	UiKit.set_text(_ms_labels[t], txt.strip_edges())
	# Step 3: live turrets per lane.
	var lanes := _count_turrets(world, t, vt)
	var posts := _count_posts(world, t, vt)
	UiKit.set_text(_turret_labels[t], "Turrets  top %d · mid %d · bottom %d · posts %d" % [lanes["top"], lanes["mid"], lanes["bot"], posts])
	# Step 4: the value beside the hull bar and the note (a practice range shows neither).
	var live := not world.practice
	_values[t].visible = live
	_notes[t].visible = live and foe
	if not live:
		return
	var row := MatchSeries.team_value(world, t, vt if foe else -1)
	var v: float = row[0] + row[1] + row[2]
	UiKit.set_text(_values[t], ("Seen " if foe else "Value ") + value_text(v))
	if foe:
		var when := "in view"
		if not in_view:
			when = "not seen" if _ms_seen_t[t] < 0.0 else Util.clock(world.time - float(_ms_seen_t[t])) + " ago"
		UiKit.set_text(_notes[t], "mothership " + when)
	_nums[t] = {"ms": shown, "turrets": int(lanes["top"]) + int(lanes["mid"]) + int(lanes["bot"]), "posts": posts, "value": v}


## Work out the marker, put it on the lead bar and write the words under it. `fog` is true while
## the viewer sees only what the fog shows. A part joins the score once the viewer has data on the
## enemy side of it, and then stays in.
func _refresh_lead(vt: int, fog: bool) -> void:
	var enemy := (1 - vt) if vt >= 0 else 1
	for key: String in WEIGHTS:
		if not fog:
			_has[key] = true
		elif not bool(_has[key]):
			match key:
				"ms":
					_has[key] = float(_ms_seen_t[enemy]) >= 0.0
				"value":
					_has[key] = float((_nums[enemy] as Dictionary).get(key, 0.0)) > 0.0
				_:
					_has[key] = int((_nums[enemy] as Dictionary).get(key, 0)) > 0
		_parts[key] = [float((_nums[0] as Dictionary).get(key, 0.0)), float((_nums[1] as Dictionary).get(key, 0.0)), _has[key]]
	var share := lead_share(_parts)
	_lead.value = share if share >= 0.0 else 0.5
	UiKit.set_text(_lead_text, lead_words(share, vt))


## The share of the score team 0 holds, from 0 to 1 (0.5 = level), or -1 when no part has any data.
## `parts` maps each name in WEIGHTS to [team 0's number, team 1's number, has data]: a part counts
## when it has data and the two numbers are not both 0, at its weight times team 0's part of the two;
## the share is the weighted sum over the weights of the parts that count.
static func lead_share(parts: Dictionary) -> float:
	var sum := 0.0
	var weight := 0.0
	for key: String in WEIGHTS:
		var part: Array = parts.get(key, [])
		if part.size() < 3 or not bool(part[2]):
			continue
		var a0 := float(part[0])
		var a1 := float(part[1])
		if a0 + a1 <= 0.0:
			continue
		sum += float(WEIGHTS[key]) * a0 / (a0 + a1)
		weight += float(WEIGHTS[key])
	return sum / weight if weight > 0.0 else -1.0


## The words under the marker for `share` (team 0's share, or -1 for no data) as seen by team `vt`
## (-1 for a spectator, who gets the team's name).
static func lead_words(share: float, vt: int) -> String:
	if share < 0.0:
		return "No data seen yet"
	var d := share - 0.5
	if absf(d) <= LEVEL_BAND:
		return "Level"
	if vt >= 0:
		return "You lead" if (d > 0.0) == (vt == 0) else "They lead"
	return str(Rules.TEAM_DISPLAY[0 if d > 0.0 else 1]) + " ahead"


## A team value as short text: "850", or "14.2k" from a thousand up.
static func value_text(v: float) -> String:
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % roundi(v)


## Count team `t`'s live defense posts (finished or being rebuilt, 0 to 3). Like
## the turrets, the other team's only count once our team (vt) has seen them (with No fog on,
## FogOff, every one counts at once).
func _count_posts(world: World, t: int, vt: int) -> int:
	var n := 0
	for p: DefensePost in world.posts:
		if p.team != t or not p.alive:
			continue
		if vt >= 0 and not FogOff.is_on() and t != vt and (p.seen_mask & (1 << vt)) == 0:
			continue
		n += 1
	return n


## Count team `t`'s live turrets in each lane ("top", "mid", "bot").
## Turrets of the other team only count once our team (vt) has seen them (with No fog on,
## FogOff, they all count):
## seen_mask is a row of on/off switches ("bits"), one per team, and bit
## number vt (the value 1 << vt) is switched on once team vt has seen it.
func _count_turrets(world: World, t: int, vt: int) -> Dictionary:
	var lanes := {"top": 0, "mid": 0, "bot": 0}
	for tu: Turret in world.turrets:
		if tu.team != t or not tu.alive or tu.node == null:
			continue
		if vt >= 0 and not FogOff.is_on() and t != vt and (tu.seen_mask & (1 << vt)) == 0:
			continue
		lanes[tu.node.lane] = int(lanes[tu.node.lane]) + 1
	return lanes
