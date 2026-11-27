extends Node
## WHAT THIS IS: the check of the death card and the teammate watch: the hit log (DeathRecap), the card (HudDeathCard), the camera's
## watch (CameraRig.watch_next() and friends) and the key and the banner that go with them. The card and the watch only read the
## match, so the check also proves that nothing of the match is written by them.
##
## HOW IT WORKS: it waits until the human's ship flies, makes a few ships (two enemy pilots, three teammates, one of them a
## Destroyer), then:
##   1. the log: the flag of Combat's damage events is turned on by the card and put back by stop(); a real hit on the human's ship
##      is logged with the amount Combat worked out (the same as the ship's own damage log), a hit on a computer pilot's ship is not
##      logged, and a hit more than 15 s old is not listed;
##   2. the accuracy: the human's ship takes bolts of 300 (an enemy pilot, three hits that merge), 200 (an enemy turret) and a
##      torpedo of 500 (a second enemy pilot) and is killed by the torpedo: the card's total is 1,000, the killer is the torpedo's
##      pilot, the shares add up to 100%, the side split is the zones that were hit, the pilots on the Attackers page are the pilots
##      Economy.contributors() gives for the same death, and the "assist paid" marks are the pilots Economy pays;
##   3. the card: it shows while the pilot is dead, says the cause and the weapon, is 440 x 168 pixels at 1280 x 720 and at 1366 x 657,
##      the hangar stops above it, and the page switch, the collapse and the [Shop · B] button work by simulated clicks;
##   4. the watch (pilot): the first press picks the teammate who was hit, then the others in seat order and round again; the lowest
##      seat when none was hit; a minimap jump, a move key, a middle press, Space and the [My view] button end it; the zoom limit is the
##      watched ship's size class; the camera follows the ship; a watched ship that is shot down leaves the camera where it was; the
##      teammate buttons and the C key (and "No teammate in flight") work; no field of any ship changes;
##   5. the launch: the card stays through the docked time, then goes with the launch and the watch ends;
##   6. the Admiral's seat (--role=admiral): the card shows for 10 seconds, has no teammate row, and C keeps its free or follow meaning.
## It ends with "death_recap_check: N failures" (0 = all good) and quits; after 120 s of real time "death_recap_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=death_recap_check
## (and the same with --role=admiral).
##
## WHO USES IT: main.gd loads it for --test=death_recap_check. It reads and drives the HUD, the camera and the hit log; it makes a few
## extra ships and kills the human's, which is all the match it changes.

## The running match (set by setup()).
var world: World
## The HUD (found when the check starts).
var hud: Hud
## How many checks failed.
var failures := 0
## True once the check has started (it runs once).
var _started := false
## The numbers the next made pilot gets (far above the real slots).
var _next_slot := 40


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Every frame: time out after 120 s of real time; start once the HUD exists and the human's ship flies.
func _process(_dt: float) -> void:
	if world == null or _started:
		return
	if Time.get_ticks_msec() > 120000:
		print("death_recap_check: timeout")
		get_tree().quit()
		return
	if get_tree().root.find_child("Hud", true, false) == null or world.camera == null:
		return
	if world.camera.followed() == null:
		return
	_started = true
	_run()


## The whole check, then the summary line and quit.
func _run() -> void:
	await _frames(3)
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	world.minion_director.next_wave = INF
	# A windowless run's mouse sits in the screen corner, where the camera's edge pan would act: put it in the middle.
	Input.use_accumulated_input = false
	var park := InputEventMouseMotion.new()
	park.position = get_viewport().get_final_transform() * (get_viewport().get_visible_rect().size * 0.5)
	park.global_position = park.position
	Input.parse_input_event(park)
	await _frames(2)
	var pilot := world.human_role == "pilot"
	var cam := world.camera
	var card := hud.death_card
	var recap := card.recap
	_expect(card != null and recap != null, "the HUD has the death card and its log")
	# --- 1. the flag of Combat's damage events ---
	_expect(recap.listening and world.combat.emit_damage_events, "the card's log listens, so Combat's damage events are on")
	recap.stop()
	_expect(not world.combat.emit_damage_events and not recap.listening, "stop() puts the flag back as it was before the log began (off)")
	recap.setup(world)
	_expect(recap.listening and world.combat.emit_damage_events, "setup() turns the flag on again")
	# --- the ships ---
	var enemy := 1 - world.human_team
	var a := _spawn("Atlas", enemy, "fighter")
	var b := _spawn("Boreas", enemy, "lance")
	var c := _spawn("Caelum", enemy, "fighter")
	var mates: Array[Ship] = [_spawn("Tester1", world.human_team, "fighter"), _spawn("Tester2", world.human_team, "destroyer"), _spawn("Tester3", world.human_team, "fighter")]
	var turret: Unit = null
	for t: Turret in world.turrets:
		if t.team == enemy and t.alive:
			turret = t
			break
	_expect(a != null and b != null and c != null and not mates.has(null) and turret != null, "the test ships and an enemy turret exist")
	if a == null or b == null or c == null or mates.has(null) or turret == null:
		_finish()
		return
	var ship := world.human.ship
	var h := world.human
	# --- 1. a real hit, and the computer pilots ---
	c.visible_mask &= ~(1 << world.human_team)
	var n0 := recap.entries.size()
	var before := ship.damage_log.get(c.uid, [0.0, 0.0, null])[0] as float
	world.combat.apply_damage(ship, DamageInfo.from_unit(c, 40.0, Rules.W_BOLT, ship.global_position + Vector2(500.0, 0.0)))
	var after := float(ship.damage_log.get(c.uid, [0.0, 0.0, null])[0])
	_expect(recap.entries.size() == n0 + 1, "a real hit on the human's ship is logged")
	var e: Dictionary = recap.entries[recap.entries.size() - 1]
	_expect(is_equal_approx(float(e["amount"]), after - before) and float(e["amount"]) > 0.0, "the logged amount is the one Combat worked out (%.3f)" % float(e["amount"]))
	_expect(not bool(e["seen"]), "an attacker the team could not see is marked unseen")
	var sg := recap.summary()
	_expect(String(sg["groups"][0]["label"]) == "an unseen attacker", "the Attackers page does not name an unseen attacker")
	var n1 := recap.entries.size()
	var mate_ship := mates[0]
	Events.damage_applied.emit(mate_ship, DamageInfo.from_unit(a, 70.0, Rules.W_BOLT, mate_ship.global_position + Vector2(300.0, 0.0)), 70.0, 10.0)
	_expect(recap.entries.size() == n1, "a hit on a computer pilot's ship is not logged")
	# --- 2. the scripted hits ---
	ship.damage_log.clear()
	recap.entries.clear()
	recap.entries.append({"t": world.time - 20.0, "uid": 1, "key": "old", "label": "Old", "kind": -1, "team": enemy, "pilot": false, "seen": true, "wkind": Rules.W_BOLT, "family": DeathRecap.F_GUNS, "amount": 777.0, "hull": 0.0, "zones": [777.0, 0.0, 0.0, 0.0]})
	for s: Unit in [a, b, turret]:
		s.visible_mask |= 1 << world.human_team
	var rear := ship.global_position + Vector2.from_angle(ship.rotation + PI) * 600.0
	var right := ship.global_position + Vector2.from_angle(ship.rotation + PI * 0.5) * 600.0
	var front := ship.global_position + Vector2.from_angle(ship.rotation) * 600.0
	for i in 3:
		_hit(ship, a, Rules.W_BOLT, rear, 100.0, 20.0)
	_hit(ship, turret, Rules.W_BOLT, right, 200.0, 50.0)
	_hit(ship, b, Rules.W_TORP, front, 500.0, 500.0)
	var window := float(Rules.tune("assist_window", Rules.ASSIST_WINDOW))
	var who := Economy.contributors(world, ship, window, 0.0)
	var paid := Economy.contributors(world, ship, window, float(Rules.tune("assist_min_fraction", Rules.ASSIST_MIN_FRACTION)))
	var killer_info := DamageInfo.from_unit(b, 500.0, Rules.W_TORP, front)
	_expect(not recap.frozen, "the log is live before the death")
	world.combat.kill(ship, killer_info)
	_expect(recap.frozen, "the log freezes when the human's ship dies")
	var s := recap.summary()
	_expect(is_equal_approx(float(s["total"]), 1000.0), "the card's total is 1,000 (%.2f)" % float(s["total"]))
	_expect(int(s["count"]) == 3, "a hit older than 15 s is not listed and three bolts of one pilot are one entry (%d entries)" % int(s["count"]))
	_expect(String(recap.death["killer"]["key"]) == "p:" + b.profile.callsign and int(recap.death["wkind"]) == Rules.W_TORP, "the killer is the torpedo's pilot")
	var fam_sum := 0.0
	for f in DeathRecap.FAMILIES:
		fam_sum += float(s["fam_share"][f])
	var zone_sum := 0.0
	for z in 4:
		zone_sum += float(s["zone_share"][z])
	var group_sum := 0.0
	for g: Dictionary in s["groups"]:
		group_sum += float(g["share"])
	_expect(is_equal_approx(fam_sum, 1.0) and is_equal_approx(zone_sum, 1.0) and is_equal_approx(group_sum, 1.0), "the shares add up to 100 percent (%.3f, %.3f, %.3f)" % [fam_sum, zone_sum, group_sum])
	_expect(is_equal_approx(float(s["zone_share"][Rules.ZONE_REAR]), 0.3) and is_equal_approx(float(s["zone_share"][Rules.ZONE_RIGHT]), 0.2) and is_equal_approx(float(s["zone_share"][Rules.ZONE_FRONT]), 0.5) and is_zero_approx(float(s["zone_share"][Rules.ZONE_LEFT])), "the side split is the zones that were hit: rear 30 percent, right 20 percent, front 50 percent")
	_expect(is_equal_approx(float(s["fam_share"][DeathRecap.F_GUNS]), 0.5) and is_equal_approx(float(s["fam_share"][DeathRecap.F_TORP]), 0.5), "the weapon mix is guns 50 percent and torpedoes 50 percent")
	_expect(is_equal_approx(float(s["stopped"]), 1.0 - 610.0 / 1000.0), "the shields and armour stopped 39 percent (%.3f)" % float(s["stopped"]))
	var pilot_keys := {}
	for g: Dictionary in s["groups"]:
		if bool(g["pilot"]):
			pilot_keys[String(g["key"])] = true
	var want_keys := {}
	for p: PilotProfile in who:
		want_keys["p:" + p.callsign] = true
	_expect(pilot_keys.size() == want_keys.size() and pilot_keys.keys().all(func(k: Variant) -> bool: return want_keys.has(k)), "the pilots on the Attackers page are the pilots Economy.contributors() gives")
	var marks := {}
	var killers := 0
	for g: Dictionary in s["groups"]:
		if bool(g["paid"]):
			marks[String(g["key"])] = true
		if bool(g["killer"]):
			killers += 1
	var want_paid := {}
	for p: PilotProfile in paid:
		if p != b.profile and p.team != ship.team:
			want_paid["p:" + p.callsign] = true
	_expect(marks.size() == want_paid.size() and marks.keys().all(func(k: Variant) -> bool: return want_paid.has(k)) and want_paid.has("p:" + a.profile.callsign), "the \"assist paid\" marks are the pilots Economy pays (%s)" % str(marks.keys()))
	_expect(killers == 1 and bool(s["groups"][0]["killer"]), "one line has the killing blow, the largest")
	_expect(String(s["groups"][2]["label"]) == "Vhorr turret" or String(s["groups"][2]["label"]) == "Aurelian turret", "the turret is one line of its own team's turret")
	# --- 3. the card ---
	h.respawn_t = 500.0
	await _frames(2)
	card.refresh(true)
	await _frames(1)
	if hud.hangar != null:
		hud.hangar.visible = false
	await _frames(8)
	card.refresh(true)
	_expect(card.visible and card.has_data, "the card shows while the pilot is dead" if pilot else "the card shows after the Admiral's ship dies")
	_expect(card.size == Vector2(440.0, 168.0), "the card is 440 x 168 at 1280 x 720 (%s)" % str(card.size))
	var cause := card._cause.text
	_expect(cause.contains(b.profile.callsign) and cause.contains("torpedo"), "the cause names the killer and the weapon (%s)" % cause)
	if not pilot:
		await _admiral_part(cam, card, recap)
		_finish()
		return
	hud._open_hangar()
	await _frames(8)
	var rect := card.get_global_rect()
	_expect(hud.hangar.visible and hud.hangar.get_global_rect().end.y <= rect.position.y + 1.0, "the hangar stops above the card at 1280 x 720 (hangar %s, card %s)" % [str(hud.hangar.get_global_rect()), str(rect)])
	_expect(card.size == Vector2(440.0, 64.0), "the card folds to its rows while the hangar is open over a window this short (%s)" % str(card.size))
	hud.hangar.visible = false
	await _frames(8)
	_expect(card.size == Vector2(440.0, 168.0), "the card opens again when the hangar closes (%s)" % str(card.size))
	get_tree().root.size = Vector2i(1366, 657)
	await _frames(8)
	card.refresh(true)
	await _frames(2)
	rect = card.get_global_rect()
	_expect(card.size == Vector2(440.0, 168.0) and rect.end.y <= hud.get_viewport_rect().size.y + 0.5, "the card is 440 x 168 and on screen at 1366 x 657 (%s at %s)" % [str(card.size), str(rect.position)])
	hud._open_hangar()
	await _frames(8)
	rect = card.get_global_rect()
	_expect(hud.hangar.get_global_rect().end.y <= rect.position.y + 1.0 and card.size.y == 64.0, "the hangar stops above the card at 1366 x 657 (hangar %s, card %s)" % [str(hud.hangar.get_global_rect()), str(rect)])
	hud.hangar.visible = false
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(8)
	# The page switch, the collapse and the shop button, by simulated clicks.
	card.refresh(true)
	await _click(card._att_btn)
	_expect(card.page == 1 and (card._row_labels[0][0] as Label).visible, "a click on Attackers shows the Attackers page")
	_expect((card._row_labels[0][1] as Label).text == "killing blow", "the killer's line says killing blow")
	await _click(card._sum_btn)
	_expect(card.page == 0 and (card._sum_labels[0] as Label).visible and not (card._row_labels[0][0] as Label).visible, "a click on Summary shows the Summary page")
	await _click(card._min_btn)
	_expect(card.collapsed and card.size.y == 64.0, "a click on the collapse button folds the card to 440 x 64")
	await _click(card._min_btn)
	_expect(not card.collapsed and card.size.y == 168.0, "a second click opens it again")
	hud.hangar.visible = false
	await _click(card._shop)
	_expect(hud.hangar.visible, "a click on Shop opens the hangar")
	hud.hangar.visible = false
	# --- 4. the watch ---
	hud.banner.refresh()
	_expect(hud.banner._sub.text.contains("watch a teammate"), "the banner's small line offers the watch while a teammate flies (%s)" % hud.banner._sub.text)
	await _watch_part(cam, card, mates)
	# --- 5. the launch ---
	var watching := cam.watch_next()
	_expect(watching and cam.watched != null, "a teammate is watched while the pilot is docked after a death")
	get_tree().paused = false
	h.respawn_t = 0.05
	var guard := 0
	while h.state != "docked" and guard < 600:
		await _frames(1)
		guard += 1
	_expect(h.state == "docked" and card.visible, "the card stays through the docked time until the launch")
	h.credits = 3000.0
	h.buy_hull("fighter", world.teams[world.human_team])
	HumanCmd.run(world, "launch")
	await _frames(4)
	card.refresh(true)
	_expect(h.ship != null and not card.visible and not recap.frozen, "the launch ends the card")
	_expect(cam.watched == null, "the launch ends the watch")
	_finish()


## The Admiral's seat: the card shows for 10 seconds without the teammate row, and C keeps its meaning.
func _admiral_part(cam: CameraRig, card: HudDeathCard, recap: DeathRecap) -> void:
	_expect(not card._mine_btn.visible and not card._mate_btns[0].visible, "the Admiral's card has no teammate row")
	_expect(not card.watch_allowed(), "C is not the watch key for the Admiral")
	var free_before := cam.free
	hud.router._camera_key()
	_expect(cam.free != free_before and cam.watched == null, "C keeps its free or follow meaning for the Admiral")
	hud.router._camera_key()
	world.time = float(recap.death["t"]) + 11.0
	await _frames(2)
	card.refresh(true)
	_expect(not card.visible, "the Admiral's card goes 10 seconds after their ship died")


## The teammate watch, in the paused match (the camera and the HUD keep running).
func _watch_part(cam: CameraRig, card: HudDeathCard, mates: Array[Ship]) -> void:
	get_tree().paused = true
	await _frames(2)
	var list := cam.watch_candidates()
	_expect(list.size() >= 3 and not list.has(null), "the dead pilot has living teammates to watch (%d)" % list.size())
	var slots_ok := true
	for i in range(1, list.size()):
		slots_ok = slots_ok and list[i - 1].profile.slot <= list[i].profile.slot
	_expect(slots_ok, "the teammates are in seat order")
	# The fields of every ship of the human's team before the watch: nothing may change.
	var snap := _snapshot(list)
	# The first press: the teammate who was hit, else the lowest seat.
	for s: Ship in list:
		s.last_damage_time = -999.0
		s.aggro_time = -999.0
	snap = _snapshot(list)
	_expect(cam.watch_next() and cam.watched == list[0], "with no one hit, the first press picks the lowest seat")
	cam.watch_clear()
	mates[2].last_damage_time = world.time
	snap = _snapshot(list)
	_expect(cam.watch_next() and cam.watched == mates[2], "the first press picks the teammate who took a hit in the last 5 seconds")
	var first := list.find(cam.watched)
	var picks: Array[Ship] = []
	for i in list.size():
		_expect(cam.watch_next(), "press %d goes on" % (i + 2))
		picks.append(cam.watched)
	var order_ok := true
	for i in list.size():
		order_ok = order_ok and picks[i] == list[(first + 1 + i) % list.size()]
	_expect(order_ok and picks[list.size() - 1] == mates[2], "later presses go in seat order and wrap round to the first pick")
	# The camera follows the watched ship, with that ship's size for the zoom limit.
	cam.watch_clear()
	_expect(cam.watch_ship(mates[1]), "a teammate button can pick a ship (the Destroyer)")
	await _frames(40)
	_expect(cam.global_position.distance_to(mates[1].global_position) < 60.0, "the camera follows the watched ship (%.1f away)" % cam.global_position.distance_to(mates[1].global_position))
	var vw := get_viewport().get_visible_rect().size.x
	var limit := vw / (float(CameraRig.PILOT_VIEW_WIDTH[Rules.size_index(mates[1].size_class)]) * ZoomMaxFeature.factor())
	_expect(is_equal_approx(cam.zoom_limits().x, limit) and not is_equal_approx(limit, vw / (float(CameraRig.PILOT_VIEW_WIDTH[0]) * ZoomMaxFeature.factor())), "the zoom limit is the watched ship's size class")
	card.refresh(true)
	_expect(card._watch_label.visible and card._watch_label.text.begins_with("Watching Tester2 · Destroyer"), "the label names the watched ship (%s)" % card._watch_label.text)
	# The ways out.
	cam.look_at_point(Vector2(3000.0, 3000.0))
	_expect(cam.watched == null, "a minimap jump ends the watch")
	cam.watch_ship(mates[0])
	var mid := InputEventMouseButton.new()
	mid.button_index = MOUSE_BUTTON_MIDDLE
	mid.pressed = true
	cam._unhandled_input(mid)
	mid.pressed = false
	cam._unhandled_input(mid)
	_expect(cam.watched == null, "a middle press ends the watch")
	cam.watch_ship(mates[0])
	Input.action_press("strafe_right")
	await _frames(3)
	Input.action_release("strafe_right")
	_expect(cam.watched == null, "a move key ends the watch")
	cam.watch_ship(mates[0])
	Input.action_press("center_on_ship")
	await _frames(3)
	Input.action_release("center_on_ship")
	await _frames(2)
	_expect(cam.watched == null, "Space ends the watch")
	_expect(cam.global_position.distance_to(cam._home_spot()) < 400.0 or cam._free_pos.distance_to(cam._home_spot()) < 1.0, "Space takes the camera to the mothership")
	# The buttons and the key, by clicks.
	card.refresh(true)
	var bi := -1
	for i in card._mates.size():
		var mp: PilotProfile = card._mates[i]
		if mp.ship != null and is_instance_valid(mp.ship) and mp.ship.alive:
			bi = i
			break
	_expect(bi >= 0 and card._mate_btns[bi].visible and not card._mate_btns[bi].disabled, "a flying teammate's button is on and ready (%d)" % bi)
	await _click(card._mate_btns[bi])
	_expect(cam.watched != null and cam.watched == (card._mates[bi] as PilotProfile).ship, "a click on a teammate button starts the watch")
	card.refresh(true)
	_expect(card._mate_btns[bi].button_pressed, "the watched teammate's button is lit")
	await _click(card._mine_btn)
	_expect(cam.watched == null, "a click on My view ends the watch")
	var key := InputEventKey.new()
	key.keycode = KEY_C
	key.physical_keycode = KEY_C
	key.pressed = true
	hud.router.handle(key)
	_expect(cam.watched != null, "the C key starts the watch for a pilot after a death")
	var w1 := cam.watched
	hud.router.handle(key)
	_expect(cam.watched != w1 and cam.watched != null, "the C key goes on to the next teammate")
	# A watched ship that is shot down leaves the camera where it was.
	var target := cam.watched
	var others: Array = []
	for o in list:
		if o != target:
			others.append(o)
	var goal := cam._free_pos
	await _frames(20)
	world.combat.kill(target, DamageInfo.new())
	await _frames(20)
	_expect(not cam.watch_info.is_empty() and cam.watched_ship() == null, "the watched ship was shot down: the watch stays, with no ship in it")
	_expect(cam._free_pos.distance_to(goal) < 5.0, "the camera stays where it was (%.2f)" % cam._free_pos.distance_to(goal))
	card.refresh(true)
	_expect(card._watch_label.text.contains("was shot down"), "the label says the ship was shot down (%s)" % card._watch_label.text)
	# Nothing of the match was written by any of this: the ships' fields are the same as before the first press.
	var now := _snapshot(others)
	var same := true
	for k: Variant in now:
		if k != target and snap.has(k):
			same = same and now[k] == snap[k]
	_expect(same, "no field of a teammate's ship changed (%d ships compared)" % now.size())
	cam.watch_clear()


## The fields of every ship in `ships`, copied: ship -> Dictionary of script variables (without the ones that change by themselves:
## nothing runs while the match is paused, so all of them are compared).
func _snapshot(ships: Array) -> Dictionary:
	var out := {}
	for s in ships:
		if is_instance_valid(s):
			var f := {}
			for p: Dictionary in (s as Object).get_property_list():
				if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
					var v: Variant = (s as Object).get(String(p["name"]))
					f[String(p["name"])] = v.duplicate(true) if (v is Array or v is Dictionary) else v
			out[s] = f
	return out


## A new pilot `name` of team `team` in hull `hull`, launched and still (null when the launch gave no ship).
func _spawn(name: String, team: int, hull: String) -> Ship:
	var p := PilotProfile.new(name, team, _next_slot, false)
	_next_slot += 1
	p.hull_id = hull
	world.profiles.append(p)
	var s := world.launch(p)
	if s != null:
		s.velocity = Vector2.ZERO
		s.controller = null
	return s


## One hit by `src` (weapon kind `kind`, from point `from`) of final `amount`, `hull` of it on the hull, on `target`: logged in the
## target's own damage log the way Combat does, and announced the way Combat announces it.
func _hit(target: Ship, src: Unit, kind: int, from: Vector2, amount: float, hull: float) -> void:
	var d := DamageInfo.from_unit(src, amount, kind, from)
	target.log_damage(d, amount)
	Events.damage_applied.emit(target, d, amount, hull)


## Click control `c` with the left mouse button through the viewport's GUI path: the pointer moves onto its middle, goes down and
## up there.
func _click(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	get_viewport().push_input(mv, true)
	await _frames(1)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(1)
	# Let the HUD lay itself out again (the card may move) before the next click.
	await _frames(8)


## The summary line, and quit.
func _finish() -> void:
	get_tree().paused = false
	print("death_recap_check: %d failures" % failures)
	get_tree().quit()


## Count a PASS or FAIL line for the check `what`.
func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
