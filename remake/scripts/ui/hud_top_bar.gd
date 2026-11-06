class_name HudTopBar
extends PanelContainer
## WHAT THIS IS: the strip at the top centre of the HUD: the match clock,
## when the next minion wave launches, the test tags (UNLOCKED, shown while the
## human buys for nothing, see UnlockAll; FOG OFF, shown while the No fog test option
## is on (see FogOff); SPEED 0.75x / 0.5x / 1.5x / 2x, shown while
## the world is not at normal speed, see WorldSpeed, and "(limited)" after it when the
## PC cannot keep that speed up), and for each team its mothership's
## hull bar, any mothership trouble, and how many turrets it has in each
## lane and how many of its three defense posts stand.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_top_bar.tscn: a
## see-through dark panel (the "TopBarLook" look) 6 pixels below the top
## edge, centred, holding one row: Halcyon's column (Name, Hull bar,
## Turrets), the Middle column (Clock, Wave) and Cinder's column. Cinder's
## side is a mirror image: its text is right-aligned and its bar fills from
## the right. The mouse passes through it to the game. _ready() colours
## each team's name and bar; refresh() rewrites the text 10 times a second.
## Enemy turrets are only counted once our team has seen them (at once with No fog on, see FogOff).
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it and
## Hud._refresh() calls refresh(). It reads World (clock, motherships,
## teams, turrets) and MinionDirector (when the next wave launches).

## The match clock ("12:34").
@onready var _clock: Label = $Row/Middle/Clock
## "Next minion wave 0:21".
@onready var _wave: Label = $Row/Middle/Wave
## The test tags under the wave line ("UNLOCKED", "FOG OFF"); hidden while there are none.
@onready var _tags: Label = $Row/Middle/Tags
## Each team's mothership hull bar (index = team: 0 Aurelian, 1 Vhorr).
@onready var _ms_bars: Array[ProgressBar] = [$Row/Halcyon/Hull, $Row/Cinder/Hull]
## Each team's name, hull percent and any mothership trouble.
@onready var _ms_labels: Array[Label] = [$Row/Halcyon/Name, $Row/Cinder/Name]
## Each team's turret count per lane.
@onready var _turret_labels: Array[Label] = [$Row/Halcyon/Turrets, $Row/Cinder/Turrets]


## Godot calls this when the bar joins the HUD: give each team's name line
## and hull bar the team's colour. (The test tags pick the interface's highlight
## colour by name in the scene.)
func _ready() -> void:
	for t in 2:
		_ms_labels[t].add_theme_color_override("font_color", Palette.team(t))
		UiKit.tint_bar(_ms_bars[t], Palette.team(t))


## Rewrite the clock, the wave timer and both teams' columns.
func refresh(world: World) -> void:
	# Step 1: the clock and the wave timer (the free waves never stop).
	UiKit.set_text(_clock, Util.clock(world.time))
	UiKit.set_text(_wave, "Next minion wave %s" % Util.clock(maxf(0.0, world.minion_director.next_wave - world.time)))
	# Step 1b: the test tags: UNLOCKED while the human's purchases are free
	# (UnlockAll), FOG OFF while the No fog option shows everything (FogOff; the spectator
	# has no fog, so no tag), SPEED 0.75x / 0.5x / 1.5x / 2x while the world is not at normal
	# speed (WorldSpeed.tag(), empty at normal speed), with "(limited)" after it
	# when the PC cannot keep up; the line is hidden when there is nothing to say.
	var tags := PackedStringArray()
	if UnlockAll.is_unlocked(world.human):
		tags.append("UNLOCKED")
	if FogOff.is_on() and world.viewer_team >= 0:
		tags.append("FOG OFF")
	var speed_tag: String = world.speed.tag()
	if speed_tag != "":
		tags.append(speed_tag + (" (limited)" if SpeedControl.limited(world) else ""))
	UiKit.set_text(_tags, "  ·  ".join(tags))
	_tags.visible = not tags.is_empty()
	# Step 2: each team's column. vt = the team we watch as (-1 = we see
	# everything, as a spectator).
	var vt := world.viewer_team
	for t in 2:
		_refresh_team(world, t, vt)


## Rewrite team `t`'s hull bar, name line and turret line.
func _refresh_team(world: World, t: int, vt: int) -> void:
	var ms := world.mothership(t)
	var ts := world.teams[t]
	_ms_bars[t].value = ms.hull_frac()
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
	# Step 2: the name line, "Aurelian (us)  87%  STRAINED". Vhorr's is
	# written the other way round ("STRAINED  87%  Vhorr (enemy)"), so on
	# both sides the team name sits at the outer edge.
	var tname: String = Rules.TEAM_DISPLAY[t]
	if vt >= 0:
		tname += " (us)" if t == vt else " (enemy)"
	var txt := "%s  %d%%%s" % [tname, int(ms.hull_frac() * 100.0), extra]
	if t == 1:
		txt = "%s  %d%%  %s" % [extra.strip_edges(), int(ms.hull_frac() * 100.0), tname]
	UiKit.set_text(_ms_labels[t], txt.strip_edges())
	# Step 3: live turrets per lane.
	var lanes := _count_turrets(world, t, vt)
	UiKit.set_text(_turret_labels[t], "Turrets  top %d · mid %d · bottom %d · posts %d" % [lanes["top"], lanes["mid"], lanes["bot"], _count_posts(world, t, vt)])


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
