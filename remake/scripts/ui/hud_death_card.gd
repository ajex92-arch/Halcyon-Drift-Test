class_name HudDeathCard
extends Control
## WHAT THIS IS: the death card, a small panel at the bottom of the screen that takes the ship readout's place while the human pilot
## has no ship (dead, or docked after a death) and says what killed them, and the way to watch a living teammate while they wait.
## It also holds the teammate watch's label above it and the ring round the watched ship. It only reads the match; it never opens
## or closes by itself.
##
## HOW IT WORKS: the card is a fixed-size panel, 440 x 168 pixels (440 x 64 collapsed, or with nothing to show) at the 1280 x 720
## base, with its right edge where the ship readout's right edge is (HudLayout._place_death_card() puts it there; the hangar then
## stops above it, HudLayout.panel_bottom()). Every child is placed by hand inside it:
##   - Row A (always): the cause, in the kill feed's own words (HudFeed.last_cause, copied when the ship died) plus the weapon of the
##     killing blow ("Wren shot down Pike's Fighter · lance beam"); a death with no known cause says "Your ship was destroyed".
##   - Row B: the [Shop · B] button with the pilot's credits (a click does what B does: opens the hangar), the page switch
##     [Summary] [Attackers] and the [-] / [+] button that collapses the card. The collapse and the page are kept for the match.
##   - Summary page: one bar of the weapon families that hit the ship (each with its colour and its letter G, L, T, S, I, C) with the
##     total at its right ("1,240 damage in 9.2 s"); the families' shares; the side the hits came from next to the ship's shield
##     focus; how much the shields and armour stopped (an ion hit is named on its own, it only drains shields); and, when a rule
##     mattered in the death (a shield pierce, the ion rule, the turret aggro window or respawn strain), one more line naming it
##     (DeathRecap.rule_note()), in the same colour, shrunk before it is cut like the other lines and hidden when no rule applies.
##   - Attackers page: up to four lines, largest first: the team mark (a dot and the name in the team's colour), the damage, a share
##     bar and the family letters; the killing blow's line has a thick border and says "killing blow"; a pilot Economy paid an assist
##     says "assist paid". All minions of a team are one line, all turrets of a team one, the Scum and derelicts one.
##   - The teammate row at the bottom (a pilot only): one button for each living or fallen teammate in seat order (callsign and, when
##     not flying, how long until they are back or whether they are docked), the one being watched lit, and [My view] which ends the
##     watch. A click on a flying teammate calls CameraRig.watch_ship(); the C key calls watch_next() (HudInput).
##   - Above the card, while a watch is on: "Watching Wren · Destroyer · C next · Space your view", or "Wren was shot down" once
##     that ship is gone; and the ring (1.25 x the ship's radius, 2 pixels, steady) round the watched ship, drawn by this node.
## With no hit logged in the last 15 seconds (a crash at speed, a hit from something gone) the card shows rows A and B and the
## teammate row only. An Admiral's card shows for 10 seconds after their ship dies and has no teammate row.
## Drawing rules: colours come from Palette only, nothing flashes (steady under reduced motion), no animation or timer is used, the
## card refreshes four times a second, and it shows only what the human's team can know (DeathRecap hides an attacker the team could
## not see, except the killer, whom the kill feed names anyway).
##
## WHO USES IT: Hud makes one in setup(), calls refresh() from its own refresh, and connects Events.unit_killed to on_killed().
## HudLayout places it (place_at(), lift()). HudInput reads watch_allowed() for the C key. tests/death_recap_check.gd checks it.

## The card's width and its full height (pixels, at the 1280 x 720 base).
const W := 440.0
## The card's full height with a page showing.
const H_FULL := 168.0
## The card's height collapsed, or with no hit to show.
const H_SMALL := 64.0
## The least real time (milliseconds) between two refreshes: four a second.
const REFRESH_MS := 250
## How long (seconds of match time) an Admiral's card shows after their ship dies.
const ADMIRAL_SHOW_S := 10.0
## The height of the label above the card.
const LABEL_H := 22.0
## Where the rows start: row A, row B and the body (pixels from the card's top).
const ROW_A_Y := 4.0
## Row B's top.
const ROW_B_Y := 21.0
## The body's top (the page under the two rows).
const BODY_Y := 46.0
## The rule line's offset from BODY_Y (pixels): the fifth Summary line, under the four that stand 18 pixels apart.
const NOTE_Y := 72.0
## The smallest type size (pixels) the rule line shrinks to before it is cut: the card's own smallest. The line starts at 12 pixels.
const NOTE_MIN_PX := 10
## The height of every button.
const BTN_H := 20.0
## The family bar: its left, its width and its height (pixels).
const BAR_X := 8.0
## The family bar's width.
const BAR_W := 242.0
## The family bar's height.
const BAR_H := 12.0
## The height of one line of the Attackers page, and how many lines it holds.
const ROW_H := 24.0
## The most lines the Attackers page shows.
const ROWS := 4
## The most teammate buttons (a team has four other pilots and its Admiral's ship; a few more fit, narrower).
const MATES := 8

## The HUD this card belongs to (Hud.setup() sets it).
var hud: Hud
## The game world.
var world: World
## The hit log behind the card.
var recap: DeathRecap
## Which page shows: 0 the Summary, 1 the Attackers. Kept for the match.
var page := 0
## True while the card is collapsed to its rows. Kept for the match.
var collapsed := false
## The kill feed's sentence for the death (copied when the ship died; the feed clears its own at the respawn).
var cause := ""
## True when the card has a hit to show (the last refresh found hits in the window).
var has_data := false
## How many pixels HudLayout lifts the card above its usual place at the bottom (the Admiral's selection panel stands there while the
## command view shows).
var raise := 0.0
## The real time (milliseconds) of the last refresh.
var _last_ms := -1000000
## The teammates the buttons stand for at the last refresh (PilotProfile each).
var _mates: Array = []
## The card's own background look.
var _back: StyleBoxFlat
## The label above the card (the watch's words).
var _watch_label: Label
## Row A's label: the cause.
var _cause: Label
## The [Shop · B] button.
var _shop: Button
## The page switch's two buttons.
var _sum_btn: Button
## The Attackers page's button.
var _att_btn: Button
## The collapse button.
var _min_btn: Button
## The [My view] button.
var _mine_btn: Button
## The teammate buttons (made once, shown as needed).
var _mate_btns: Array[Button] = []
## The Summary page's labels: the total, the families, the side line, the shield line, the rule line.
var _sum_labels: Array[Label] = []
## The Attackers page's labels, four for each line: the name, the badge, the damage and the family letters.
var _row_labels: Array = []
## What the family bar draws: one [x, width, colour, letter] for each family that hit.
var _segs: Array = []
## What the Attackers page draws: one Dictionary (the group) for each line.
var _rows: Array = []


## Make the card's children and remember the HUD. Hud.setup() calls this once. Not made visible until a death.
func setup(h: Hud) -> void:
	hud = h
	world = h.world
	recap = DeathRecap.new()
	recap.setup(world)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	size = Vector2(W, H_FULL)
	custom_minimum_size = Vector2(W, H_SMALL)
	_back = UiKit.box(Palette.with_alpha(Palette.PANEL, 0.94), Palette.LINE, 4)
	_cause = _text("", 12, Palette.ICE, 8.0, ROW_A_Y, W - 16.0)
	_shop = _button("Shop · B", func() -> void: hud._open_hangar(), 8.0, ROW_B_Y, 104.0)
	_shop.tooltip_text = "Open the hangar and shop while you wait."
	_sum_btn = _button("Summary", func() -> void: _set_page(0), 116.0, ROW_B_Y, 62.0)
	_att_btn = _button("Attackers", func() -> void: _set_page(1), 180.0, ROW_B_Y, 68.0)
	for b: Button in [_sum_btn, _att_btn]:
		b.toggle_mode = true
	_min_btn = _button("-", func() -> void: _toggle_collapse(), W - 32.0, ROW_B_Y, 24.0)
	_min_btn.tooltip_text = "Fold the card up or open it again."
	for _i in 5:
		_sum_labels.append(_text("", 12, Palette.ICE, 8.0, BODY_Y, W - 16.0))
	for i in ROWS:
		var y := BODY_Y + float(i) * ROW_H
		_row_labels.append([_text("", 12, Palette.ICE, 20.0, y + 3.0, 170.0), _text("", 10, Palette.MIST, 194.0, y + 5.0, 74.0),
				_text("", 12, Palette.ICE, 270.0, y + 3.0, 56.0), _text("", 11, Palette.MIST, 388.0, y + 4.0, 44.0)])
		(_row_labels[i][2] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in MATES:
		var b := _button("", func() -> void: _on_mate(i), 8.0, 0.0, 60.0)
		b.toggle_mode = true
		_mate_btns.append(b)
	_mine_btn = _button("My view", func() -> void: _on_my_view(), W - 72.0, 0.0, 64.0)
	_mine_btn.tooltip_text = "Back to your own view (Space)."
	_watch_label = _text("", 12, Palette.ICE, 0.0, -LABEL_H, W)
	_watch_label.add_theme_color_override("font_outline_color", Palette.VOID)
	_watch_label.add_theme_constant_override("outline_size", 4)
	_watch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_watch_label.visible = false


## A label of `text` at font `size_px` in `col`, placed at (`x`, `y`) in the card and `w` wide, a line high; too long a text is
## cut with dots.
func _text(text: String, size_px: int, col: Color, x: float, y: float, w: float) -> Label:
	var l := UiKit.label(text, size_px, col)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(l)
	l.position = Vector2(x, y)
	l.custom_minimum_size = Vector2(w, 16.0)
	l.size = Vector2(w, 16.0)
	return l


## A small button of `text` placed at (`x`, `y`) in the card and `w` wide, BTN_H high, that calls `on_press`.
func _button(text: String, on_press: Callable, x: float, y: float, w: float) -> Button:
	var b := UiKit.button(text, on_press, BTN_H)
	b.add_theme_font_size_override("font_size", 11)
	var hi := UiKit.accent()
	b.add_theme_stylebox_override("normal", UiKit.box(Palette.INK, Palette.LINE, 2))
	b.add_theme_stylebox_override("hover", UiKit.box(Palette.INK, hi, 2))
	b.add_theme_stylebox_override("pressed", UiKit.box(Palette.PANEL, hi, 2))
	b.add_theme_stylebox_override("hover_pressed", UiKit.box(Palette.PANEL, hi, 2))
	b.add_theme_stylebox_override("disabled", UiKit.box(Palette.with_alpha(Palette.INK, 0.6), Palette.with_alpha(Palette.LINE, 0.6), 2))
	b.clip_text = true
	add_child(b)
	b.position = Vector2(x, y)
	b.custom_minimum_size = Vector2(w, BTN_H)
	b.size = Vector2(w, BTN_H)
	return b


## Take the card away when the HUD leaves the tree: the hit log gives Combat's damage events back as it found them.
func _exit_tree() -> void:
	if recap != null:
		recap.stop()


## Every frame while the card shows with a watch on: draw again, so the ring follows the watched ship.
func _process(_dt: float) -> void:
	if visible and world != null and world.camera != null and world.camera.watched_ship() != null:
		queue_redraw()


## The human's ship was destroyed (Events.unit_killed, connected after the kill feed's own line): copy the feed's sentence for
## the card, since the feed clears it at the respawn and the card stays until the launch.
func on_killed(unit: Node, _info: RefCounted) -> void:
	var s := unit as Ship
	if s != null and world != null and s.kind == Unit.K_SHIP and s.profile == world.human:
		cause = hud.feed.last_cause


## Should the card show now? A pilot's card shows from their death until the launch (from the log's freeze, or while the pilot
## is dead, which also covers a game loaded while dead); an Admiral's for ADMIRAL_SHOW_S seconds after their ship died; never
## when the human has a live ship, no seat, or the match is over.
func wanted() -> bool:
	var h := world.human if world != null else null
	if h == null or hud == null or hud.end_screen != null or world.human_role == "spectator":
		return false
	if h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		return false
	if world.human_role == "pilot":
		return recap.frozen or h.state == "dead"
	return recap.frozen and world.time - float(recap.death.get("t", -1000.0)) < ADMIRAL_SHOW_S


## Is the pilot in the state where C watches a teammate (no ship of their own after a death)? HudInput asks.
func watch_allowed() -> bool:
	return world != null and world.human_role == "pilot" and wanted()


## Hud._refresh() calls this 10 times a second: show or hide the card, and (four times a second, or at once with `force`) bring
## its words and pictures up to date. A live ship ends the last death: the log is forgotten.
func refresh(force: bool = false) -> void:
	if world == null or hud == null:
		return
	var h := world.human
	if recap.frozen and h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		recap.reset()
		cause = ""
	var want := wanted()
	if want != visible:
		visible = want
	if not want:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_ms < REFRESH_MS:
		return
	_last_ms = now
	_update()


## Bring every word, button and picture of the card up to date.
func _update() -> void:
	var h := world.human
	var s := recap.summary()
	has_data = int(s["count"]) > 0 and float(s["total"]) > 0.0
	var open := has_data and not collapsed and not _hangar_blocks()
	var height := H_FULL if open else H_SMALL
	if absf(size.y - height) > 0.5:
		size = Vector2(W, height)
	# Row A: the cause and the weapon of the killing blow.
	var line := cause if cause != "" else "Your ship was destroyed"
	if recap.frozen:
		line += " · " + DeathRecap.weapon_words(int(recap.death.get("wkind", Rules.W_BOLT)))
	_fit_text(_cause, line, W - 16.0)
	# Row B.
	UiKit.set_text(_shop, "Shop · B  %s" % num(int(h.credits)) if h != null else "Shop · B")
	_sum_btn.visible = has_data
	_att_btn.visible = has_data
	_min_btn.visible = has_data
	_sum_btn.set_pressed_no_signal(page == 0)
	_att_btn.set_pressed_no_signal(page == 1)
	UiKit.set_text(_min_btn, "+" if collapsed else "-")
	# The body: one page, or none.
	for l in _sum_labels:
		l.visible = false
	for r: Array in _row_labels:
		for l: Label in r:
			l.visible = false
	_segs = []
	_rows = []
	if open and page == 0:
		_summary_page(s)
	elif open:
		_attackers_page(s)
	_teammate_row()
	_watch_words()
	queue_redraw()


## Does the open hangar leave too little room for the full card under it? The hangar cannot be shorter than its own smallest height, so
## while it is open over a window that short the card folds to its rows (its page and collapse choice are kept) and opens again when the
## hangar closes.
func _hangar_blocks() -> bool:
	if hud.hangar == null or not hud.hangar.visible:
		return false
	var need := H_FULL + 2.0 * HudLayout.GAP + (LABEL_H if not world.camera.watch_info.is_empty() else 0.0)
	return hud.get_viewport_rect().size.y - hud.layout.panel_top(HudPanels.HANGAR_SIDE) - hud.hangar.get_combined_minimum_size().y < need


## HudLayout calls this before it places the card: fold or open the card when the hangar was opened or closed since the last refresh.
func fit() -> void:
	var want := H_FULL if has_data and not collapsed and not _hangar_blocks() else H_SMALL
	if absf(size.y - want) > 0.5:
		_update()


## Fit `text` to label `l` of width `w`: 12 pixel type, 11 and then down to `min_px` (10 unless given) when that is too long (the
## label cuts the rest with dots).
func _fit_text(l: Label, text: String, w: float, min_px := 10) -> void:
	var font := l.get_theme_font("font")
	var px := 12
	while px > min_px and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x > w:
		px -= 1
	if l.get_theme_font_size("font_size") != px:
		l.add_theme_font_size_override("font_size", px)
	UiKit.set_text(l, text)


## Fill the Summary page from summary `s`: the bar, the total, the families, the sides, the shields.
func _summary_page(s: Dictionary) -> void:
	var total := float(s["total"])
	# The bar: the families that hit, biggest first, each as wide as its share.
	var order: Array = []
	for f in DeathRecap.FAMILIES:
		if float(s["fam"][f]) > 0.0:
			order.append(f)
	order.sort_custom(func(a: int, b: int) -> bool: return float(s["fam"][a]) > float(s["fam"][b]))
	var x := BAR_X
	var names: Array[String] = []
	for f: int in order:
		var share := float(s["fam_share"][f])
		var w := BAR_W * share
		_segs.append([x, w, DeathRecap.family_colour(f), DeathRecap.FAMILY_TAGS[f]])
		x += w
		names.append("%s %d%%" % [DeathRecap.FAMILY_NAMES[f], roundi(share * 100.0)])
	var t := _sum_labels[0]
	t.position = Vector2(BAR_X + BAR_W + 8.0, BODY_Y)
	t.size = Vector2(W - BAR_X - BAR_W - 16.0, 16.0)
	t.custom_minimum_size = t.size
	UiKit.set_text(t, "%s damage in %.1f s" % [num(roundi(total)), float(s["span"])])
	t.visible = true
	_place_line(_sum_labels[1], BODY_Y + 18.0, " · ".join(names))
	# The sides and the shield focus.
	var zone_total := 0.0
	for z in 4:
		zone_total += float(s["zone"][z])
	var side := "Hit from: no side (a crash)"
	if zone_total > 0.0:
		var zs: Array = []
		for z in 4:
			if float(s["zone"][z]) > 0.0:
				zs.append(z)
		zs.sort_custom(func(a: int, b: int) -> bool: return float(s["zone"][a]) > float(s["zone"][b]))
		var parts: Array[String] = []
		for z: int in zs:
			parts.append("%s %d%%" % [DeathRecap.ZONE_NAMES[z], roundi(float(s["zone_share"][z]) * 100.0)])
		side = "Hit from: %s  ·  your shield focus: %s" % [" · ".join(parts), DeathRecap.focus_words(int(recap.death.get("focus", Rules.FOCUS_BALANCED)))]
	_place_line(_sum_labels[2], BODY_Y + 36.0, side)
	# The shields and armour (an ion hit only drains shields, so it is named on its own).
	var shield := ""
	var stopped := float(s["stopped"])
	if stopped >= 0.0:
		shield = "Shields and armour stopped %d%% · %d%% reached the hull" % [roundi(stopped * 100.0), 100 - roundi(stopped * 100.0)]
	if float(s["ion"]) > 0.0:
		var ion := "ion drained %s from your shields" % num(roundi(float(s["ion"])))
		# Only the first letter is a capital ("Ion drained 120 from your shields").
		shield = ion.left(1).to_upper() + ion.substr(1) if shield == "" else shield + " · " + ion
	_place_line(_sum_labels[3], BODY_Y + 54.0, shield)
	# The one rule that mattered in this death, if any: 12 pixel type, shrinking to NOTE_MIN_PX before it is cut.
	var note := DeathRecap.rule_note(s, recap.death)
	_place_line(_sum_labels[4], BODY_Y + NOTE_Y, String(note["text"]))
	if String(note["text"]) != "":
		_fit_text(_sum_labels[4], String(note["text"]), W - 16.0, NOTE_MIN_PX)


## Put `text` on the body label `l` at height `y`, the full width of the card, and show it (hidden when `text` is empty).
func _place_line(l: Label, y: float, text: String) -> void:
	l.position = Vector2(8.0, y)
	l.size = Vector2(W - 16.0, 16.0)
	l.custom_minimum_size = l.size
	UiKit.set_text(l, text)
	l.visible = text != ""


## Fill the Attackers page from summary `s`: up to four lines, largest first.
func _attackers_page(s: Dictionary) -> void:
	var groups: Array = s["groups"]
	for i in mini(groups.size(), ROWS):
		var g: Dictionary = groups[i]
		var r: Array = _row_labels[i]
		var col := Palette.team(int(g["team"]))
		(r[0] as Label).add_theme_color_override("font_color", col)
		UiKit.set_text(r[0], String(g["label"]))
		var badge := "killing blow" if bool(g["killer"]) else ("assist paid" if bool(g["paid"]) else "")
		UiKit.set_text(r[1], badge)
		UiKit.set_text(r[2], num(roundi(float(g["amount"]))))
		var tags := ""
		for f in DeathRecap.FAMILIES:
			if (int(g["mask"]) & (1 << f)) != 0:
				tags += String(DeathRecap.FAMILY_TAGS[f])
		UiKit.set_text(r[3], tags)
		for l: Label in r:
			l.visible = true
		_rows.append(g)


## The teammate row: the buttons for the pilots of the human's team (and their Admiral's ship) in seat order, and [My view]. Only a
## pilot has it; the Admiral's card has none.
func _teammate_row() -> void:
	var pilot := world.human_role == "pilot"
	var rig := world.camera
	var y := size.y - BTN_H - 2.0
	_mates = []
	if pilot:
		for p: PilotProfile in world.profiles:
			if p != world.human and p.team == world.human.team and not p.is_crew:
				_mates.append(p)
		_mates.sort_custom(func(a: PilotProfile, b: PilotProfile) -> bool: return a.slot < b.slot)
	var n := mini(_mates.size(), MATES)
	var room := W - 16.0 - 68.0
	var bw := minf(76.0, (room - 3.0 * float(maxi(n - 1, 0))) / float(maxi(n, 1)))
	for i in MATES:
		var b := _mate_btns[i]
		b.visible = pilot and i < n
		if not b.visible:
			continue
		var p: PilotProfile = _mates[i]
		var flying := p.ship != null and is_instance_valid(p.ship) and p.ship.alive
		var word := ""
		if not flying:
			word = " %ds" % int(ceil(p.respawn_t)) if p.state == "dead" else ""
		UiKit.set_text(b, p.callsign + word)
		b.disabled = not flying
		b.position = Vector2(8.0 + float(i) * (bw + 3.0), y)
		b.custom_minimum_size = Vector2(bw, BTN_H)
		b.size = Vector2(bw, BTN_H)
		b.set_pressed_no_signal(flying and rig.watched_ship() == p.ship)
		b.tooltip_text = ("Watch %s's %s" % [p.callsign, Formations.short_hull(p.ship.hull_id)]) if flying else ("%s: %s" % [p.callsign, "shot down, back in %d s" % int(ceil(p.respawn_t)) if p.state == "dead" else p.state])
	_mine_btn.visible = pilot
	_mine_btn.position = Vector2(W - 72.0, y)
	_mine_btn.disabled = rig.watch_info.is_empty()


## The words above the card: who is watched, or that they were shot down.
func _watch_words() -> void:
	var rig := world.camera
	if rig == null or rig.watch_info.is_empty():
		_watch_label.visible = false
		return
	var who := String(rig.watch_info["name"])
	var text := ""
	if rig.watched_ship() != null:
		text = "Watching %s · %s · %s next · %s your view" % [who, String(rig.watch_info["hull"]), KeyMapText.key_of("center_camera"), KeyMapText.key_of("center_on_ship")]
	else:
		var p := rig.watch_info["profile"] as PilotProfile
		text = "%s was shot down" % who if p != null and p.state == "dead" else "%s is out of the fight" % who
	UiKit.set_text(_watch_label, text)
	_watch_label.visible = true


## How high (pixels) the card reaches above the bottom edge, with the label above it while a watch is on, plus the gap: HudLayout
## keeps the hangar and the pop-up hint above it.
func lift() -> float:
	return size.y + HudLayout.GAP + raise + (LABEL_H if _watch_label != null and _watch_label.visible else 0.0)


## Put the card's top-left corner at window point `p` (HudLayout calls this while the card shows).
func place_at(p: Vector2) -> void:
	if position.distance_to(p) > 0.5:
		position = p


## The page buttons: show page `p` (0 Summary, 1 Attackers) and bring the card up to date at once.
func _set_page(p: int) -> void:
	page = p
	collapsed = false
	_update()


## The [-] button: fold the card up to its rows, or open it again.
func _toggle_collapse() -> void:
	collapsed = not collapsed
	_update()


## A teammate button was clicked: watch that pilot's ship if it flies.
func _on_mate(i: int) -> void:
	if i >= _mates.size():
		return
	var p: PilotProfile = _mates[i]
	if p.ship != null and is_instance_valid(p.ship) and p.ship.alive:
		world.camera.watch_ship(p.ship)
	_update()


## [My view]: end the watch (the same as Space).
func _on_my_view() -> void:
	world.camera.watch_clear()
	_update()


## Draw the card's back, the family bar or the Attackers lines' marks, and the ring round the watched ship.
func _draw() -> void:
	draw_style_box(_back, Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	for sg: Array in _segs:
		var r := Rect2(float(sg[0]), BODY_Y + 2.0, maxf(float(sg[1]), 1.0), BAR_H)
		draw_rect(r, sg[2] as Color)
		if r.size.x >= 12.0:
			draw_string(font, r.position + Vector2(3.0, BAR_H - 2.0), String(sg[3]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Palette.VOID)
	for i in _rows.size():
		var g: Dictionary = _rows[i]
		var y := BODY_Y + float(i) * ROW_H
		var col := Palette.team(int(g["team"]))
		var box := Rect2(4.0, y, W - 8.0, ROW_H - 2.0)
		if bool(g["killer"]):
			draw_rect(box, Palette.ICE, false, 3.0)
		else:
			draw_rect(box, Palette.LINE, false, 1.0)
		draw_circle(Vector2(12.0, y + 11.0), 4.0, col)
		draw_rect(Rect2(330.0, y + 8.0, 54.0, 6.0), Palette.INK)
		draw_rect(Rect2(330.0, y + 8.0, 54.0 * clampf(float(g["share"]), 0.0, 1.0), 6.0), col)
	# The ring round the watched ship: 1.25 x its radius, 2 pixels, steady, in the human's team colour.
	var ship := world.camera.watched_ship() if world != null and world.camera != null else null
	if ship != null and visible:
		var xf := get_viewport().get_canvas_transform()
		var c := xf * ship.global_position - global_position
		var rad := maxf(ship.radius * 1.25 * xf.get_scale().x, 10.0)
		draw_arc(c, rad, 0.0, TAU, 48, Palette.team(world.human_team), 2.0, true)


## `n` as text with a comma between the thousands (1240 -> "1,240").
static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
