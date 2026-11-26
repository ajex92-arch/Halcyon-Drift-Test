extends RtsUiCheckBase
## WHAT THIS IS: the check of the win-odds mark of the army cards (WinOdds, the option Game.win_odds): the bands of the mark, the fog
## rule, the damaged-ship floor, whole numbers only, the option off giving no mark, and the two numbers equal to AdmiralStrength's own.
##
## HOW IT WORKS: the base fills both fleets and finds the HUD. The case takes one of our fighter squadrons and one enemy destroyer
## and sets up scenes by hand: it moves enemy ships next to the squadron (or far away) and sets or clears the bit of the human's team in
## their visible_mask, the way the match's own sight would. The strength weights are given to WinOdds.of() in the test's own four
## numbers, so a ratio such as 1190 permille is exact: one class's weight is 1000 for each of our ships, the other's is the
## ratio, so the strengths are n x 1000 and n x ratio. The scene is put back at the end (the enemy ships' places and masks, the
## groups, the option). No settings file is written: the option is set on Game directly, never through choose_win_odds().
##
## HOW TO RUN IT: see RtsUiCheckBase (--test=win_odds_check).
##
## WHO USES IT: main.gd loads it for --test=win_odds_check; the run_checks list has a row for it.


func _init() -> void:
	label = "win_odds_check"


## The enemy team of the human's.
func _enemy() -> int:
	return Rules.CINDER if world.human_team == Rules.HALCYON else Rules.HALCYON


## The living enemy ships.
func _enemy_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for s: Ship in world.ships:
		if s.alive and s.team == _enemy():
			out.append(s)
	return out


## Put enemy ship `s` at `p` and make it seen (or not) by the human's team, as the sight would.
func _place(s: Ship, p: Vector2, seen: bool) -> void:
	s.global_position = p
	var bit := 1 << world.human_team
	s.visible_mask = (s.visible_mask | bit) if seen else (s.visible_mask & ~bit)


## The odds of squadron `rec` with the weights `w`.
func _odds(rec: Squad, w: Array) -> Dictionary:
	var ids: Array[int] = [rec.id]
	return WinOdds.of(world, ids, w)


## The weights that make the strength of our ships `ratio_pm`/1000 of the enemy's (mine bigger) or the other way round, for
## `n` ships of our squadron's class `cm` and one enemy ship of class `ce`: [w0, w1, w2, w3].
func _weights(cm: int, ce: int, n: int, ratio_pm: int, mine_bigger: bool) -> Array:
	var w := [1000, 1000, 1000, 1000]
	if mine_bigger:
		w[cm] = ratio_pm
		w[ce] = n * 1000
	else:
		w[cm] = 1000
		w[ce] = n * ratio_pm
	return w


func run() -> void:
	var view := hud.command_view
	var army := view.army
	var g := view.groups
	g.store_path = ProjectSettings.globalize_path("res://").path_join("tests/win_odds_check_%d.cfg" % OS.get_process_id())
	# The squadron: one of our fighter squadrons; the enemy: its destroyers (a different weight class).
	var rec: Squad = null
	for r in squads():
		if r.hull_id == "fighter" and RtsSelect.ships_of(world, r).size() >= 2:
			rec = r
			break
	check("setup: we have a fighter squadron of two ships or more", rec != null)
	var foes := _enemy_ships()
	var destroyers: Array[Ship] = []
	var small: Array[Ship] = []
	for s in foes:
		if s.hull_id == "destroyer":
			destroyers.append(s)
		elif AdmiralStrength.class_index(s.hull_id) == 0:
			small.append(s)
	check("setup: the enemy has two destroyers and some strike craft", destroyers.size() >= 2 and small.size() >= 2, "%d, %d" % [destroyers.size(), small.size()])
	if rec == null or destroyers.size() < 2 or small.size() < 2:
		return
	var mine_ships := RtsSelect.ships_of(world, rec)
	var n := mine_ships.size()
	var cm := AdmiralStrength.class_index(rec.hull_id)
	var ce := AdmiralStrength.class_index("destroyer")
	check("setup: the two classes differ", cm != ce, "%d %d" % [cm, ce])
	var centre := RtsSelect.centre_of(world, rec)
	# Remember the enemy ships' places and masks, to put them back.
	var saved: Array = []
	for s in foes:
		saved.append([s, s.global_position, s.visible_mask, s.hull])
	var far := centre + Vector2(60000.0, 0.0)
	# Our ships at full hull, so the strengths are the weights' product exactly.
	var our_hull: Array = []
	for s in mine_ships:
		our_hull.append([s, s.hull])
		s.hull = s.hull_max
	var foe := destroyers[0]
	foe.hull = foe.hull_max
	for s in foes:
		_place(s, far, false)

	# The source: no team view query, no random number, no write to the match.
	var src := FileAccess.get_file_as_string("res://scripts/ui/rts/win_odds.gd")
	check("source: win_odds.gd names no TeamView, no randf, no rand_range", src != "" and not src.contains("TeamView") and not src.contains("randf") and not src.contains("randi") and not src.contains("rand_range"))

	# No enemy seen: the mark is none.
	var o := _odds(rec, _weights(cm, ce, n, 1000, true))
	check("none: no enemy ship seen gives no mark", o["mark"] == "none" and o["theirs"] == 0 and o["ratio_pm"] == 0, str(o))
	# An enemy ship that is seen but far from the squadron does not count (the reach).
	_place(foe, centre + Vector2(RtsUiCalls.WIN_ODDS_REACH + 500.0, 0.0), true)
	o = _odds(rec, _weights(cm, ce, n, 1000, true))
	check("none: a ship seen beyond the reach gives no mark", o["mark"] == "none", str(o))
	_place(foe, centre + Vector2(RtsUiCalls.WIN_ODDS_REACH - 200.0, 0.0), true)
	o = _odds(rec, _weights(cm, ce, n, 1000, true))
	check("reach: a ship seen inside the reach counts", o["mark"] != "none" and int(o["theirs"]) > 0, str(o))
	_place(foe, centre + Vector2(400.0, 0.0), true)

	# The bands: mine over theirs, then theirs over mine.
	var band_ok := true
	var detail := ""
	for row: Array in [[1000, "even"], [1190, "even"], [1199, "even"], [1200, "win"], [1500, "win"], [2500, "win"]]:
		var ratio := int(row[0])
		var mark_mine := str(_odds(rec, _weights(cm, ce, n, ratio, true))["mark"])
		var mark_theirs := str(_odds(rec, _weights(cm, ce, n, ratio, false))["mark"])
		var want_theirs: String = "loss" if row[1] == "win" else "even"
		if mark_mine != row[1] or mark_theirs != want_theirs:
			band_ok = false
			detail += " %d: %s/%s" % [ratio, mark_mine, mark_theirs]
	check("bands: 1.0x, 1.19x and 1.199x are even; 1.2x, 1.5x and more are win, and loss when mirrored", band_ok, detail)
	o = _odds(rec, _weights(cm, ce, n, 1200, true))
	check("bands: at 1.2x the ratio is 1200 permille and the strengths are n x 1200 and n x 1000", o["ratio_pm"] == 1200 and o["mine"] == n * 1200 and o["theirs"] == n * 1000, str(o))
	o = _odds(rec, _weights(cm, ce, n, 1200, false))
	check("bands: mirrored, theirs is the larger and the ratio is still 1200", o["ratio_pm"] == 1200 and o["theirs"] == n * 1200 and o["mine"] == n * 1000 and o["mark"] == "loss", str(o))

	# Whole numbers only: every number is an int and the ratio is the integer arithmetic.
	var w_odd := _weights(cm, ce, n, 1337, true)
	o = _odds(rec, w_odd)
	var hi := maxi(int(o["mine"]), int(o["theirs"]))
	var lo := mini(int(o["mine"]), int(o["theirs"]))
	check("ints: mine, theirs and the ratio are whole numbers, the ratio is larger x 1000 / smaller", typeof(o["mine"]) == TYPE_INT and typeof(o["theirs"]) == TYPE_INT and typeof(o["ratio_pm"]) == TYPE_INT and int(o["ratio_pm"]) == _pm(hi, lo) and o["ratio_pm"] == 1337, str(o))

	# The fog rule: a ship the team cannot see changes nothing; the same ship seen counts.
	var w1 := _weights(cm, ce, n, 1000, true)
	var seen_only := _odds(rec, w1)
	var second := destroyers[1]
	second.hull = second.hull_max
	_place(second, centre + Vector2(800.0, 0.0), false)
	var with_hidden := _odds(rec, w1)
	check("fog: an enemy ship the team cannot see (visible_mask clear) changes nothing", with_hidden == seen_only, "%s vs %s" % [str(with_hidden), str(seen_only)])
	_place(second, centre + Vector2(800.0, 0.0), true)
	var with_both := _odds(rec, w1)
	check("fog: the same ship, seen, adds its strength", int(with_both["theirs"]) == 2 * int(seen_only["theirs"]), "%s vs %s" % [str(with_both), str(seen_only)])
	_place(second, far, false)

	# The floor: a damaged enemy counts less, never under 0.4 of its weight.
	var w2 := _weights(cm, ce, n, 1000, true)
	var full := int(_odds(rec, w2)["theirs"])
	foe.hull = foe.hull_max * 0.5
	var half := int(_odds(rec, w2)["theirs"])
	foe.hull = foe.hull_max * 0.001
	var wreck := int(_odds(rec, w2)["theirs"])
	check("damage: a half-hull enemy counts 0.7 of its weight (AdmiralStrength's own number)", half == AdmiralStrength.ship_strength("destroyer", 500, w2) and half < full, "%d of %d" % [half, full])
	check("damage: a wrecked enemy counts the 0.4 floor, never less", wreck == AdmiralStrength.ship_strength("destroyer", 1, w2) and wreck * 1000 >= full * AdmiralStrength.HULL_FLOOR, "%d of %d" % [wreck, full])
	foe.hull = foe.hull_max

	# The held-out run: the two numbers equal AdmiralStrength's own for the same fleets, with the profile's own weights.
	_place(foe, centre + Vector2(400.0, 0.0), true)
	_place(small[0], centre + Vector2(900.0, 100.0), true)
	_place(small[1], centre + Vector2(900.0, -100.0), false)
	small[0].hull = small[0].hull_max * 0.6
	var prof_w := WinOdds.weights_of(world)
	var held := _odds(rec, [])
	var near: Array[Ship] = [foe, small[0]]
	var want_mine := AdmiralStrength.of_ships(mine_ships, world.human_team, prof_w)
	var want_theirs := AdmiralStrength.of_ships(near, _enemy(), prof_w)
	var std := AdmiralProfile.make("standard", world.human_team)
	var std_w := []
	for key: String in AdmiralLanes.WEIGHT_KEYS:
		std_w.append(std.raw(key))
	check("held-out: the weights are the four fitted keys of the human team's profile", prof_w.size() == 4 and prof_w == std_w, str(prof_w))
	check("held-out: mine and theirs equal AdmiralStrength.of_ships for the same fleets", held["mine"] == want_mine and held["theirs"] == want_theirs, "%s vs %d / %d" % [str(held), want_mine, want_theirs])
	print("win_odds_check: held-out run: mine %d theirs %d ratio %d permille mark %s (AdmiralStrength: %d and %d)" % [held["mine"], held["theirs"], held["ratio_pm"], held["mark"], want_mine, want_theirs])
	small[0].hull = small[0].hull_max

	# No write: the match's own numbers are the same after many asks.
	var before := _fingerprint()
	for i in 20:
		_odds(rec, [])
	check("no write: twenty asks change no ship, squadron or mask", _fingerprint() == before)

	# The option and the card: off gives no mark; on gives the mark the function gives.
	g.set_group(1, [rec.id])
	Game.win_odds = false
	view.refresh()
	var card_off := _group_entry(army, 1)
	check("option off: the card's odds field is empty even with an enemy in sight", card_off.get("odds", "x") == "" and not str(card_off["tip"]).contains("Likely") and not str(card_off["tip"]).contains("ignores missiles"), str(card_off.get("odds")))
	check("option off: a shown card writes no mark", _card_of(army, 1).data.get("odds", "x") == "")
	Game.win_odds = true
	view.refresh()
	var card_on := _group_entry(army, 1)
	var want := _odds(rec, prof_w)
	var want_mark: String = "" if want["mark"] == "none" else str(want["mark"])
	check("option on: the card's odds field is the mark of WinOdds for the card's squadrons", want_mark != "" and card_on["odds"] == want_mark, "%s vs %s" % [str(card_on.get("odds")), want_mark])
	check("option on: the tooltip says it in words and what it ignores", str(card_on["tip"]).contains(WinOdds.words(want_mark)) and str(card_on["tip"]).contains("a guess from ship sizes only") and str(card_on["tip"]).contains("missiles, armour sections and energy routing"), str(card_on["tip"]))
	var card := _card_of(army, 1)
	check("option on: the shown card carries the mark", card.data.get("odds", "") == want_mark)
	# An unchanged snapshot writes nothing; a changed mark does.
	var same: Dictionary = card.data.duplicate()
	same["tip"] = "changed"
	card.show_data(same)
	check("card: an unchanged snapshot writes nothing", card.tooltip_text != "changed")
	same["odds"] = ""
	card.show_data(same)
	check("card: a changed mark writes the card", card.tooltip_text == "changed" and card.data["odds"] == "")
	view.refresh()
	# Every sign of the mark draws, and the three differ in shape.
	var draws0 := card.draws
	for mark in WinOdds.MARKS:
		var d: Dictionary = _group_entry(army, 1).duplicate()
		d["odds"] = mark
		card.show_data(d)
		await get_tree().process_frame
		await get_tree().process_frame
	check("draw: the card drew again for each of the three marks", card.draws - draws0 >= 3, "%d draws" % (card.draws - draws0))
	var shapes := {}
	for sign_name in RtsGlyphs.ODDS:
		shapes[str(RtsGlyphs.SHAPES[sign_name])] = true
	for state in RtsGlyphs.STATES:
		shapes[str(RtsGlyphs.SHAPES[state])] = true
	check("shapes: the three marks differ from each other and from every state sign", shapes.size() == RtsGlyphs.ODDS.size() + RtsGlyphs.STATES.size())
	var marks_ok := WinOdds.MARKS.size() == 3
	for i in 3:
		marks_ok = marks_ok and RtsGlyphs.has("odds_" + str(WinOdds.MARKS[i])) and RtsGlyphs.ODDS[i] == "odds_" + str(WinOdds.MARKS[i])
	check("shapes: each mark has its own sign", marks_ok)

	# The pause menu's button reads and writes the option through Game (not touched here: no settings file is written by this check).
	check("default: Game.win_odds is declared off (the source's value)", _declared_off())

	# Put everything back.
	Game.win_odds = false
	for row: Array in saved:
		var s: Ship = row[0]
		s.global_position = row[1]
		s.visible_mask = int(row[2])
		s.hull = float(row[3])
	for row: Array in our_hull:
		(row[0] as Ship).hull = float(row[1])
	for k in Groups.COUNT:
		g.set_group(k + 1, [])
	hud.overlay.clear_selection()
	view.refresh()
	if g.store_path != "" and FileAccess.file_exists(g.store_path):
		DirAccess.remove_absolute(g.store_path)


## The entry of the group card for group `n`.
func _group_entry(army: ArmyCards, n: int) -> Dictionary:
	for e: Dictionary in army.entries:
		if str(e["kind"]) == "group" and int(e["n"]) == n:
			return e
	return {}


## The shown card of group `n`.
func _card_of(army: ArmyCards, n: int) -> ArmyCard:
	for c in army._shown:
		if c.kind == "group" and int(c.data["n"]) == n:
			return c
	return null


## The ratio in permille: the larger strength over the smaller, integer division (as WinOdds.of() does it).
@warning_ignore("integer_division")
func _pm(hi: int, lo: int) -> int:
	return hi * 1000 / lo


## A fingerprint of what the mark must not change: every ship's place, hull and mask, and every squadron's state.
func _fingerprint() -> String:
	var parts: Array[String] = []
	for s: Ship in world.ships:
		parts.append("%d:%s:%s:%d" % [s.uid, str(s.global_position), str(s.hull), s.visible_mask])
	var ids: Array = world.squads.keys()
	ids.sort()
	for id: int in ids:
		var q: Squad = world.squads[id]
		parts.append("q%d:%d:%s" % [id, q.state, str(q.member_uids)])
	return "\n".join(parts)


## Is `win_odds` declared false in game.gd's source (the default, before any setting is read)?
func _declared_off() -> bool:
	var src := FileAccess.get_file_as_string("res://scripts/autoload/game.gd")
	return src.contains("\nvar win_odds := false")
