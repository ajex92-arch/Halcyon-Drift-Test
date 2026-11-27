extends Node
## WHAT THIS IS: the check of the practice range's switches (PracticeSwitches): the one order
## that carries them (PracticeOrders), what they change (PracticeActions), the panel
## (PracticePanel) and the record they leave. It builds practice matches and normal matches
## through WorldSetup and checks, item by item: the refusal outside a range and the money
## switches, the waves and the camps, the cooldowns, the panel and the key, the record.
##
## HOW IT WORKS: setup() runs everything, then quits. The match the run was launched with is the
## normal one (practice off); the check builds its own extra worlds for the practice cases (a
## world is made from its scene, set up in a seat, paused so nothing ticks unless a check steps
## it, and freed after its checks). It sets Game.practice_start and Game.practice_others itself
## and puts every Game field back at the end. It never calls a function that writes the settings
## file (the panel's presses are made with remember false).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --force-hud --seed=7 --test=practice_switch_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --force-hud --seed=7 --test=practice_switch_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or "FAIL <what> <detail>".
## The last line is "practice_switch_check: N failures"; 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=practice_switch_check. It only reads the game it
## builds, so it is only for this check.

## The world scene every match is made from.
const WORLD_SCENE := "res://scenes/world/world.tscn"
## A purse big enough to buy any hull (credits).
const PURSE := 50000.0

## The match the run was launched with (a normal match; set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## Game.practice_start as the run found it (put back at the end).
var _saved_start := false
## Game.practice_others as the run found it (put back at the end).
var _saved_others := PracticeRange.OTHERS_DEFAULT
## Game.usage as the run found it (put back at the end).
var _saved_usage := {}
## Count of Events.credits_earned messages seen while a check watches (every payment goes through it).
var _paid_events := 0


## main.gd calls this once, right after the World is built. Run every check and quit.
func setup(w: World) -> void:
	world = w
	_saved_start = Game.practice_start
	_saved_others = Game.practice_others
	_saved_usage = Game.usage.duplicate(true)
	print("practice_switch_check: seat=%s" % world.human_role)
	_check_normal_refusals()
	for role: String in ["pilot", "admiral"]:
		_check_money(role)
	_check_round_trip()
	_check_freeze()
	_check_send_wave()
	_check_camps()
	_check_cooldowns()
	_check_weapon_timers()
	_check_remembered()
	_check_panel()
	_check_record()
	_finish()


## Put the Game fields and the running match back and quit with the failure count.
func _finish() -> void:
	Game.practice_start = _saved_start
	Game.practice_others = _saved_others
	Game.usage = _saved_usage
	Game.world = world
	print("practice_switch_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the measured
## `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Build a match through WorldSetup in seat `role` (the launched seat when empty), as a practice
## match with the choice `others` when `practice` is true: made from the world scene, added to
## this node and paused (nothing ticks unless a check steps it). The Game fields are put back
## at once, so the next build starts from the launched state.
func _build(practice: bool, others: String = "nobody", role: String = "") -> World:
	Game.practice_start = practice
	Game.practice_others = others
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	add_child(w)
	w.set_physics_process(false)
	w.setup(world.human_role if role == "" else role)
	Game.practice_start = _saved_start
	Game.practice_others = _saved_others
	Game.world = world
	return w


## Free a world a check built (and tell Game the launched match is the running one).
func _drop(w: World) -> void:
	remove_child(w)
	w.free()
	Game.world = world


## Step world `w` by `ticks` ticks (it is paused, so a check drives it by hand; Game knows it as the running match).
func _step(w: World, ticks: int) -> void:
	Game.world = w
	for i in ticks:
		w._physics_process(1.0 / 60.0)
	Game.world = world


## Events.credits_earned: count one more payment.
func _on_paid(_profile: RefCounted, _amount: float, _reason: String) -> void:
	_paid_events += 1


## The switch word's order sent from `w`'s human seat: the toggles are sent on, the nearest camp with
## the id "camp_x". Returns the refusal text or "".
func _send(w: World, sw: String) -> String:
	var on := 1 if PracticeSwitches.TOGGLES.has(sw) else -1
	return PracticeOrders.send(w, sw, on, "camp_x" if sw == PracticeSwitches.CAMP_NEAR else "")


## Item 1 (a): in a normal match every switch is refused at the door with the range's words, its code
## is "seat", and nothing changes: the queue, Game.usage and the match fingerprint are as they were.
func _check_normal_refusals() -> void:
	var q := world.orders
	var queue_before := q.queue.size()
	var id_before := q.next_id
	var usage_before := Game.usage.duplicate(true)
	var fp_before := OrderLog.fingerprint_pair(world)
	var bad := PackedStringArray()
	for sw: String in PracticeSwitches.WORDS:
		var msg := _send(world, sw)
		if msg != "Only in the practice range" or OrderKinds.reason_code(msg) != "seat":
			bad.append("%s: '%s'" % [sw, msg])
	_check("a normal match refuses all %d switches with 'Only in the practice range' (code seat)" % PracticeSwitches.WORDS.size(), bad.is_empty(), "; ".join(bad))
	_check("a normal match: the queue, the order numbers, Game.usage and the fingerprint are unchanged", q.queue.size() == queue_before and q.next_id == id_before and Game.usage == usage_before and OrderLog.fingerprint_pair(world) == fp_before, "%d %d %s" % [q.queue.size(), q.next_id, OrderLog.fingerprint_pair(world)])
	_check("a normal match: the handler is installed (the refusal is the range's, not 'later stage')", q.has_applier(OrderKinds.PRACTICE) and q.handlers.has(OrderKinds.PRACTICE))


## The change of credits and treasury over one tick of `w` with no order, and how many payment
## messages came: [credits, treasury, earned, messages] (what the world does by itself in a tick).
func _idle_tick(w: World) -> Array:
	var h := w.human
	var ts: TeamState = w.teams[h.team]
	var before := [h.credits, ts.treasury, h.earned]
	_paid_events = 0
	Events.credits_earned.connect(_on_paid)
	_step(w, 1)
	Events.credits_earned.disconnect(_on_paid)
	return [h.credits - float(before[0]), ts.treasury - float(before[1]), h.earned - float(before[2]), _paid_events]


## Item 1 (b): the money switches in a practice match of seat `role`.
func _check_money(role: String) -> void:
	var tag := "practice (%s seat)" % role
	var p := _build(true, "nobody", role)
	var h := p.human
	var ts: TeamState = p.teams[h.team]
	var used_before := int(Game.usage.get("practice_money", 0))
	# What the world does by itself in one tick (a trickle of pay and income), so the grant can be told from it.
	var idle := _idle_tick(p)
	# One press: the order waits for the next tick, then adds 5,000 and nothing else.
	h.income_mult = 1.0
	h.credits = 700.0
	var earned0 := h.earned
	var tick_sent := p.tick_count
	var msg := PracticeOrders.send(p, PracticeSwitches.MONEY)
	_check("%s: a money press is accepted" % tag, msg == "", msg)
	_step(p, 0)
	_check("%s: before the next tick nothing has changed (the order waits)" % tag, h.credits == 700.0 and p.orders.queue.size() == 1, "%s, %d queued" % [str(h.credits), p.orders.queue.size()])
	_paid_events = 0
	Events.credits_earned.connect(_on_paid)
	_step(p, 1)
	Events.credits_earned.disconnect(_on_paid)
	var gained := h.credits - 700.0
	var trickle := h.earned - earned0
	_check("%s: one tick later the purse is 5,000 higher (%s)" % [tag, str(gained)], absf(gained - trickle - 5000.0) < 0.01 and p.tick_count == tick_sent + 1, "gained %s of which trickle %s" % [str(gained), str(trickle)])
	_check("%s: the grant is not earned and sends no payment message" % tag, absf(trickle - float(idle[2])) < 0.01 and _paid_events == int(idle[3]), "earned +%s (idle +%s), %d messages (idle %d)" % [str(trickle), str(idle[2]), _paid_events, int(idle[3])])
	var rec: Dictionary = p.practice_range.uses.get("money", {})
	_check("%s: Game.usage counts practice_money once and the range keeps its first tick" % tag, int(Game.usage.get("practice_money", 0)) == used_before + 1 and int(rec.get("count", 0)) == 1 and int(rec.get("tick", -1)) == tick_sent + 1, "%d, %s" % [int(Game.usage.get("practice_money", 0)) - used_before, str(rec)])
	# The difficulty does not scale it: with the pay doubled the grant is still 5,000.
	h.income_mult = 2.0
	var idle2 := _idle_tick(p)
	h.credits = 700.0
	earned0 = h.earned
	PracticeOrders.send(p, PracticeSwitches.MONEY)
	_step(p, 1)
	gained = h.credits - 700.0
	trickle = h.earned - earned0
	_check("%s: with income_mult 2.0 the grant is still 5,000" % tag, absf(gained - trickle - 5000.0) < 0.01 and absf(trickle - float(idle2[2])) < 0.01, "gained %s, earned +%s" % [str(gained), str(trickle)])
	# The limit: 98,000 gets exactly to 100,000, and then the press is refused.
	h.income_mult = 0.0
	h.credits = 98000.0
	PracticeOrders.send(p, PracticeSwitches.MONEY)
	_step(p, 1)
	_check("%s: at 98,000 a press gives exactly 100,000" % tag, h.credits == 100000.0, str(h.credits))
	msg = PracticeOrders.send(p, PracticeSwitches.MONEY)
	_check("%s: the next press is refused 'Purse full' (code room)" % tag, msg == "Purse full" and OrderKinds.reason_code(msg) == "room" and p.orders.queue.is_empty(), msg)
	# The treasury: the Admiral's seat only.
	ts.treasury = 700.0
	if role == "admiral":
		var tidle := _idle_tick(p)
		ts.treasury = 700.0
		msg = PracticeOrders.send(p, PracticeSwitches.TREASURY)
		_step(p, 1)
		var tgain := ts.treasury - 700.0
		_check("%s: the treasury press adds 5,000 to the team's treasury" % tag, msg == "" and absf(tgain - float(tidle[1]) - 5000.0) < 0.5, "'%s' gained %s (idle %s)" % [msg, str(tgain), str(tidle[1])])
		ts.treasury = 98000.0
		PracticeOrders.send(p, PracticeSwitches.TREASURY)
		var tidle2 := ts.treasury
		_step(p, 1)
		_check("%s: at 98,000 a treasury press stops at the limit" % tag, ts.treasury >= 100000.0 and ts.treasury - tidle2 < 2100.0, str(ts.treasury))
		ts.treasury = 100000.0
		msg = PracticeOrders.send(p, PracticeSwitches.TREASURY)
		_check("%s: a full treasury refuses 'Treasury full' (code room)" % tag, msg == "Treasury full" and OrderKinds.reason_code(msg) == "room", msg)
	else:
		msg = PracticeOrders.send(p, PracticeSwitches.TREASURY)
		_check("%s: the treasury press is refused from a pilot seat ('Not yours to order', code seat)" % tag, msg == "Not yours to order" and OrderKinds.reason_code(msg) == "seat" and p.orders.queue.is_empty(), msg)
	_check("%s: the money in the range's line adds up" % tag, p.practice_range.money_given > 0.0, str(p.practice_range.money_given))
	_drop(p)


## The live free-wave minions of `team` in world `p` by lane: {"top": n, "mid": n, "bot": n}.
func _lanes(p: World, team: int) -> Dictionary:
	var out := {"top": 0, "mid": 0, "bot": 0}
	for m: Minion in p.minions:
		if m.team == team and m.alive and m.free_wave:
			out[m.lane] = int(out[m.lane]) + 1
	return out


## How many live free-wave minions world `p` holds, both teams.
func _free_minions(p: World) -> int:
	var n := 0
	for m: Minion in p.minions:
		if m.alive and m.free_wave:
			n += 1
	return n


## Item 2: Freeze waves. After one tick no free-wave minion is alive and the queue is empty; a minion
## made some other way survives; 60 s of match time frozen launches no wave (the first is due at 45 s);
## letting the waves run again keeps the time left and never less than 3 s.
func _check_freeze() -> void:
	var p := _build(true, "nobody")
	var md := p.minion_director
	PracticeOrders.send(p, PracticeSwitches.WAVE)
	_step(p, 120)
	var out_before := _free_minions(p)
	var unmarked := 0
	for m: Minion in p.minions:
		if m.alive and not m.free_wave:
			unmarked += 1
	_check("every minion a wave launched is marked free_wave (%d marked, %d not)" % [out_before, unmarked], out_before > 0 and unmarked == 0)
	var queued_before := md.queue.size()
	_check("before the freeze the wave is out (%d minions) and some are still queued (%d)" % [out_before, queued_before], out_before > 0 and queued_before > 0)
	var hand := p.spawn_minion(0, "fighter", "mid", p.mothership(0).global_position + Vector2(0.0, 600.0))
	md.next_wave = p.time + 2.0
	var msg := PracticeOrders.send(p, PracticeSwitches.FREEZE, 1)
	_check("a freeze press is accepted", msg == "", msg)
	_step(p, 1)
	_check("one tick after the freeze no free-wave minion is alive and the queue is empty", _free_minions(p) == 0 and md.queue.is_empty() and md.frozen, "%d alive, %d queued" % [_free_minions(p), md.queue.size()])
	_check("a minion made another way survives the freeze", hand.alive and is_instance_valid(hand) and not hand.free_wave)
	_check("the clock is held: the time left (about 2 s) is kept and the next wave is never", is_inf(md.next_wave) and md.held_left > 1.9 and md.held_left <= 2.0, str(md.held_left))
	var line := HudTopBar.wave_line(md, p.time)
	_check("the top bar says 'Waves frozen'", line == "Waves frozen", line)
	_step(p, 3600)
	_check("60 s of match time frozen launches no wave (%s s)" % str(snappedf(p.time, 0.1)), _free_minions(p) == 0 and md.queue.is_empty() and p.time > 60.0)
	msg = PracticeOrders.send(p, PracticeSwitches.FREEZE, 0)
	_step(p, 1)
	var left := md.next_wave - p.time
	_check("letting the waves run again leaves at least 3 s (%s)" % str(snappedf(left, 0.01)), not md.frozen and left >= 2.999 and left < 3.1, str(left))
	# A long time left is kept: frozen for 5 s, 30 s are still left.
	md.next_wave = p.time + 30.0
	PracticeOrders.send(p, PracticeSwitches.FREEZE, 1)
	_step(p, 1)
	_step(p, 300)
	PracticeOrders.send(p, PracticeSwitches.FREEZE, 0)
	_step(p, 1)
	left = md.next_wave - p.time
	_check("a long time left is kept over the freeze (%s of 30 s)" % str(snappedf(left, 0.01)), left > 29.5 and left <= 30.0, str(left))
	_drop(p)


## Item 2: Send one wave. One press gives 5, 11 and 5 minions per team on the top, middle and bottom
## lanes (after the 0.35 s spacing has run); a lane whose post is down gets none; a second press inside
## 60 ticks is refused (code time) and one at 63 live minions is refused (code room).
func _check_send_wave() -> void:
	var p := _build(true, "nobody")
	var md := p.minion_director
	var msg := PracticeOrders.send(p, PracticeSwitches.WAVE)
	_check("a send is accepted", msg == "", msg)
	_step(p, 1)
	var again := PracticeOrders.send(p, PracticeSwitches.WAVE)
	_check("a second send inside 60 ticks is refused 'Wait a second' (code time)", again == "Wait a second" and OrderKinds.reason_code(again) == "time", again)
	_step(p, 240)
	var ok := true
	var detail := PackedStringArray()
	for team in 2:
		var lanes := _lanes(p, team)
		detail.append("team %d: top %d mid %d bot %d" % [team, lanes["top"], lanes["mid"], lanes["bot"]])
		ok = ok and lanes["top"] == 5 and lanes["mid"] == 11 and lanes["bot"] == 5
	_check("one send gives 5, 11 and 5 minions per team on top, middle and bottom", ok, "; ".join(detail))
	# A press 60 ticks after the first goes through (the gap is over).
	var third := PracticeOrders.send(p, PracticeSwitches.WAVE)
	_check("a press after the gap is accepted", third == "", third)
	# A lane whose post is down gets none: wipe the minions (a freeze), destroy a post, send again.
	PracticeOrders.send(p, PracticeSwitches.FREEZE, 1)
	_step(p, 1)
	_check("the freeze took every free-wave minion away (both sends)", _free_minions(p) == 0)
	var site := p.defense_posts.site_of(1, "mid")
	var info := DamageInfo.new()
	info.source_team = 0
	p.combat.kill(site.post, info)
	_check("the middle post of team 1 is down", not p.defense_posts.standing(1, "mid"))
	_step(p, 60)
	msg = PracticeOrders.send(p, PracticeSwitches.WAVE)
	_step(p, 241)
	var l0 := _lanes(p, 0)
	var l1 := _lanes(p, 1)
	_check("while frozen a send still works; the lane without a standing post gets none (team 1: %d/%d/%d)" % [l1["top"], l1["mid"], l1["bot"]], msg == "" and l1["mid"] == 0 and l1["top"] == 5 and l1["bot"] == 5 and l0["mid"] == 11, msg)
	# 63 live free-wave minions on one team: refused 'room'.
	for i in PracticeSwitches.WAVE_REFUSE_AT:
		var m := p.spawn_minion(0, "fighter", "mid", p.mothership(0).global_position + Vector2(0.0, 800.0))
		m.free_wave = true
	_step(p, 61)
	msg = PracticeOrders.send(p, PracticeSwitches.WAVE)
	_check("a send with 63 or more live minions on a team is refused (code room)", msg == "Too many minions on the lanes" and OrderKinds.reason_code(msg) == "room", msg)
	_check("the refusal changes nothing: the queue is empty", p.orders.queue.is_empty() and md.queue.is_empty())
	_drop(p)


## Item 2: the camps. After Respawn all every camp holds a live derelict at full hull (a damaged one and a
## destroyed one included) and a carrier's snubs are gone; Respawn nearest changes only that camp; nobody is
## paid and `earned` does not move; an id the match lacks is refused.
func _check_camps() -> void:
	var p := _build(true, "nobody")
	var jd := p.jungle_director
	var h := p.human
	h.income_mult = 0.0
	var ids: Array = jd.camps.keys()
	_check("the range has camps to respawn (%d)" % ids.size(), ids.size() >= 10)
	# Spoil three camps: one damaged, one destroyed, and a carrier with a snub out.
	var damaged: Derelict = jd.camps[ids[0]]["unit"]
	damaged.hull = damaged.hull_max * 0.4
	var info := DamageInfo.new()
	info.source_team = 0
	var killed_id := str(ids[1])
	p.combat.kill(jd.camps[killed_id]["unit"], info)
	var carrier: Derelict = null
	var carrier_id := ""
	for id: String in ids:
		var u: Derelict = jd.camps[id]["unit"]
		if u != null and u.ctype == "carrier" and id != killed_id and id != str(ids[0]):
			carrier = u
			carrier_id = id
			break
	var snub: SnubFighter = null
	if carrier != null:
		snub = p.spawn_snub(carrier)
		carrier.snubs.append(snub)
	var before := {}
	for id: String in ids:
		var u: Variant = jd.camps[id]["unit"]
		before[id] = u.get_instance_id() if u != null and is_instance_valid(u) else 0
	var earned0 := h.earned
	_paid_events = 0
	Events.credits_earned.connect(_on_paid)
	# Respawn nearest first: only that camp changes.
	var msg := PracticeOrders.send(p, PracticeSwitches.CAMP_NEAR, -1, str(ids[0]))
	_check("a nearest-camp press is accepted", msg == "", msg)
	_step(p, 1)
	var changed := PackedStringArray()
	for id: String in ids:
		var u: Variant = jd.camps[id]["unit"]
		var now: int = u.get_instance_id() if u != null and is_instance_valid(u) else 0
		if now != int(before[id]):
			changed.append(id)
	var fresh: Derelict = jd.camps[ids[0]]["unit"]
	_check("Respawn nearest changes only that camp (changed: %s)" % ", ".join(changed), changed.size() == 1 and changed[0] == str(ids[0]) and fresh != null and fresh.alive and fresh.hull == fresh.hull_max, "%s hull %s of %s" % [str(ids[0]), str(fresh.hull), str(fresh.hull_max)])
	_check("the replaced derelict is gone", not is_instance_valid(damaged) or not damaged.alive)
	# Respawn all.
	msg = PracticeOrders.send(p, PracticeSwitches.CAMPS)
	_check("a respawn-all press is accepted", msg == "", msg)
	_step(p, 1)
	var bad := PackedStringArray()
	for id: String in ids:
		var u: Derelict = jd.camps[id]["unit"]
		if u == null or not is_instance_valid(u) or not u.alive or u.hull != u.hull_max or float(jd.camps[id]["respawn_at"]) != 0.0:
			bad.append(id)
	_check("after Respawn all every camp (%d) has a live derelict at full hull" % ids.size(), bad.is_empty(), ", ".join(bad))
	var killed: Derelict = jd.camps[killed_id]["unit"]
	_check("the destroyed camp is back at once", killed != null and killed.alive)
	if snub != null:
		_check("the carrier's snub fighter is gone with its carrier", not is_instance_valid(snub) or not snub.alive, carrier_id)
	Events.credits_earned.disconnect(_on_paid)
	_check("nobody is paid for the replaced camps: no payment message and `earned` unchanged", _paid_events == 0 and h.earned == earned0, "%d messages, earned %s" % [_paid_events, str(h.earned - earned0)])
	_check("the camp-near order's Game.usage and the range's record are counted", int(Game.usage.get("practice_camp_near", 0)) >= 1 and int(Game.usage.get("practice_camps", 0)) >= 1 and (p.practice_range.uses as Dictionary).has("camps"))
	msg = PracticeOrders.send(p, PracticeSwitches.CAMP_NEAR, -1, "no_such_camp")
	_check("an id the match lacks is refused 'No camp near the centre of the screen' (code place)", msg == "No camp near the centre of the screen" and OrderKinds.reason_code(msg) == "place", msg)
	var all_camps: Dictionary = jd.camps
	jd.camps = {}
	msg = PracticeOrders.send(p, PracticeSwitches.CAMPS)
	jd.camps = all_camps
	_check("a match without a jungle says so (code gone)", msg == "No jungle camps in this match" and OrderKinds.reason_code(msg) == "gone", msg)
	_drop(p)


## Launch the human of world `p` in hull `hull` (bought at its list price with a big purse; a class the
## team has not researched is open in the range), step two ticks and return the ship (null when it
## could not launch).
func _launch_human(p: World, hull: String) -> Ship:
	var h := p.human
	h.credits = PURSE
	h.hull_id = ""
	# The range's open classes ask the running match (Game.world), so it is the range for the purchase.
	Game.world = p
	var err := h.buy_hull(hull, p.teams[h.team])
	Game.world = world
	if err != "":
		print("FAIL-DETAIL buying %s: %s" % [hull, err])
		return null
	var ship := p.launch(h)
	_step(p, 2)
	return ship


## Item 3: the cooldowns. A reset makes the human's special, energy and focus timers ready and leaves
## the special's running time alone; a dead human's countdown becomes 1 s; with nothing to reset it is
## refused; No cooldowns keeps the timers ready over ten uses and a death short; a computer pilot's
## ship is never touched.
func _check_cooldowns() -> void:
	var p := _build(true, "allies")
	var h := p.human
	var msg := PracticeOrders.send(p, PracticeSwitches.CD_RESET)
	_check("a reset with no ship (docked) is refused 'Nothing to reset' (code gone)", msg == "Nothing to reset" and OrderKinds.reason_code(msg) == "gone" and p.orders.queue.is_empty(), msg)
	var ship := _launch_human(p, "fighter")
	if ship == null:
		_check("the human launches a fighter", false)
		_drop(p)
		return
	# A computer pilot's ship on the same team, with a special still counting down.
	var mate: PilotProfile = null
	for q: PilotProfile in p.profiles:
		if q.team == h.team and not q.is_human and q.role != "admiral":
			mate = q
			break
	var mate_ship: Ship = null
	if mate != null:
		mate.credits = PURSE
		mate.hull_id = ""
		mate.buy_hull("fighter", p.teams[mate.team])
		mate_ship = p.launch(mate)
		_step(p, 2)
	ship.special_cd = 7.0
	ship.energy_cd = 3.0
	ship.focus_cd = 2.0
	ship.special_t = 3.5
	if mate_ship != null:
		mate_ship.special_cd = 5.0
	msg = PracticeOrders.send(p, PracticeSwitches.CD_RESET)
	_check("a reset press is accepted", msg == "", msg)
	_check("before the next tick the timers are as they were", ship.special_cd == 7.0 and ship.energy_cd == 3.0 and ship.focus_cd == 2.0)
	_step(p, 1)
	_check("one tick later the special, energy and focus timers are ready", ship.special_cd <= 0.0 and ship.energy_cd <= 0.0 and ship.focus_cd <= 0.0, "%s %s %s" % [str(ship.special_cd), str(ship.energy_cd), str(ship.focus_cd)])
	_check("the special's running time is not touched", ship.special_t > 3.0, str(ship.special_t))
	if mate_ship != null:
		_check("a computer pilot's special is not touched by the reset (%s)" % str(snappedf(mate_ship.special_cd, 0.01)), mate_ship.special_cd > 4.9, str(mate_ship.special_cd))
	else:
		_check("a computer pilot is on the human's team in 'allies'", false)
	_check("the reset is counted (Game.usage practice_cd_reset)", int(Game.usage.get("practice_cd_reset", 0)) >= 1)
	# No cooldowns: ten uses in a row.
	msg = PracticeOrders.send(p, PracticeSwitches.CD_AUTO, 1)
	_check("a No cooldowns press is accepted", msg == "", msg)
	_step(p, 1)
	_check("No cooldowns is on", p.practice_range.no_cooldowns)
	var stuck := 0
	for i in 10:
		ship.special_cd = 7.0
		ship.energy_cd = 3.0
		ship.focus_cd = 2.0
		_step(p, 1)
		if ship.special_cd > 0.0 or ship.energy_cd > 0.0 or ship.focus_cd > 0.0:
			stuck += 1
	_check("with No cooldowns on, the timers are ready after each of ten uses (%d stuck)" % stuck, stuck == 0)
	# A death waits one second.
	var info := DamageInfo.new()
	info.source_team = Rules.enemy_of(h.team)
	p.combat.kill(ship, info)
	_step(p, 2)
	_check("with No cooldowns on, a death waits at most one second (state %s, %s s)" % [h.state, str(snappedf(h.respawn_t, 0.01))], h.state != "dead" or h.respawn_t <= PracticeSwitches.DEAD_RESPAWN, str(h.respawn_t))
	PracticeOrders.send(p, PracticeSwitches.CD_AUTO, 0)
	_step(p, 1)
	_check("No cooldowns is off again", not p.practice_range.no_cooldowns)
	# A dead human: the reset cuts the countdown to one second.
	var ship2 := _launch_human(p, "fighter")
	if ship2 != null:
		p.combat.kill(ship2, info)
		_step(p, 2)
		var long_wait := h.state == "dead" and h.respawn_t > PracticeSwitches.DEAD_RESPAWN
		_check("a dead human has a countdown longer than a second (%s s)" % str(snappedf(h.respawn_t, 0.01)), long_wait)
		msg = PracticeOrders.send(p, PracticeSwitches.CD_RESET)
		_step(p, 1)
		_check("a reset while dead gives a respawn countdown of at most 1 s (%s s)" % str(snappedf(h.respawn_t, 0.01)), msg == "" and h.respawn_t <= PracticeSwitches.DEAD_RESPAWN, "'%s' %s" % [msg, str(h.respawn_t)])
	_drop(p)


## Item 3, the weapon timers: a reset makes ready the timer of a gun that waits 1 s or more between
## shots (the Bomber's torpedo) and leaves a quick gun's timer (its tail gun) alone. The list of
## every hull's guns the rule takes is printed, for the question of which timers the reset should take.
func _check_weapon_timers() -> void:
	var taken := PackedStringArray()
	for hull: String in Ships.ORDER:
		var names := {}
		for mt: Dictionary in Ships.HULLS[hull]["mounts"]:
			var wid := str(mt["w"])
			var rate := float((Weapons.WEAPONS[wid] as Dictionary).get("rate", 0.0))
			if rate > 0.0 and 1.0 / rate >= PracticeSwitches.WEAPON_FLOOR:
				names[wid] = int(names.get(wid, 0)) + 1
		for wid: String in names:
			taken.append("%s %s x%d (%s s)" % [hull, wid, int(names[wid]), str(snappedf(1.0 / float((Weapons.WEAPONS[wid] as Dictionary)["rate"]), 0.01))])
	print("INFO the cooldown reset takes these guns (a gun that waits %s s or more between shots): %s" % [str(PracticeSwitches.WEAPON_FLOOR), "; ".join(taken)])
	var p := _build(true, "nobody")
	var ship := _launch_human(p, "bomber")
	if ship == null:
		_check("the human launches a bomber", false)
		_drop(p)
		return
	var slow: WeaponMount = null
	var quick: WeaponMount = null
	for m: WeaponMount in ship.mounts:
		var rate := float(m.def.get("rate", 0.0))
		if slow == null and rate > 0.0 and 1.0 / rate >= PracticeSwitches.WEAPON_FLOOR:
			slow = m
		elif quick == null and rate > 0.0 and 1.0 / rate < PracticeSwitches.WEAPON_FLOOR:
			quick = m
	_check("the bomber has a slow gun (%s) and a quick one (%s)" % [slow.weapon_id if slow != null else "none", quick.weapon_id if quick != null else "none"], slow != null and quick != null)
	if slow != null and quick != null:
		# The torpedo is a run gun: RunGun rewrites cd from its own reload counter every tick, so the
		# reload counter is set too (a bare cd of 4 would fall back to 0 by itself and prove nothing).
		_check("the slow gun is a run gun with a reload counter (%s)" % slow.weapon_id, slow.run != null)
		if slow.run != null:
			slow.run.reload = 240
		slow.cd = 4.0
		quick.cd = 0.1
		PracticeOrders.send(p, PracticeSwitches.CD_RESET)
		_step(p, 1)
		_check("a reset makes the slow gun's timer ready (%s)" % str(slow.cd), slow.cd <= 0.0)
		if slow.run != null:
			_check("a reset also clears the run gun's reload counter (%d)" % slow.run.reload, slow.run.reload == 0)
		_check("a reset leaves the quick gun's timer alone (%s)" % str(snappedf(quick.cd, 0.001)), quick.cd > 0.05)
		# No cooldowns: ten uses, each with the reload counter loaded again, each ready after one tick.
		PracticeOrders.send(p, PracticeSwitches.CD_AUTO, 1)
		_step(p, 1)
		var ready := 0
		for i in 10:
			if slow.run != null:
				slow.run.reload = 240
			slow.cd = 4.0
			_step(p, 1)
			if slow.cd <= 0.0 and (slow.run == null or slow.run.reload == 0):
				ready += 1
		_check("under No cooldowns the run gun is ready after one tick, ten times of ten (%d)" % ready, ready == 10)
		PracticeOrders.send(p, PracticeSwitches.CD_AUTO, 0)
		_step(p, 1)
	_drop(p)


## Item 4: the toggles the player left on come back as orders on the range's first tick (the fields are
## set by hand and put back; nothing is written to the settings file).
func _check_remembered() -> void:
	var was_frozen := Game.practice_frozen
	var was_no_cd := Game.practice_no_cd
	Game.practice_frozen = true
	Game.practice_no_cd = true
	var p := _build(true, "nobody")
	_step(p, 3)
	Game.practice_frozen = was_frozen
	Game.practice_no_cd = was_no_cd
	var pr := p.practice_range
	_check("a range with the toggles left on starts with the waves frozen and No cooldowns on", p.minion_director.frozen and pr.no_cooldowns, "%s %s" % [str(p.minion_director.frozen), str(pr.no_cooldowns)])
	var rec_f: Dictionary = pr.uses.get("freeze", {})
	var rec_c: Dictionary = pr.uses.get("cd_auto", {})
	_check("the remembered toggles went through the order queue (the range counts them, on tick %s and %s)" % [str(rec_f.get("tick", -1)), str(rec_c.get("tick", -1))], int(rec_f.get("count", 0)) == 1 and int(rec_c.get("count", 0)) == 1 and int(rec_f.get("tick", 0)) <= 3)
	_drop(p)
	var q := _build(true, "nobody")
	_step(q, 3)
	_check("a range with nothing left on starts with the waves running", not q.minion_director.frozen and not q.practice_range.no_cooldowns and q.practice_range.uses.is_empty())
	_drop(q)


## Item 4: the panel. It is in a practice world's HUD and not in a normal one; one press of each button
## sends one order and the world applies it on the next tick; a refusal is written under its button and
## goes away after 2 s; it is a tab while a big panel is open; the Admiral's section follows the Admiral
## flying; the O key opens and closes it and Shift+O does not; the top bar shows the two tags. The check
## calls press() with remember false, and never calls a function that writes the settings file.
func _check_panel() -> void:
	var main_hud := get_tree().root.find_child("Hud", true, false) as Hud
	if main_hud != null:
		_check("a normal match's HUD has no practice panel", main_hud.get_node_or_null("PracticePanel") == null)
	else:
		_check("the launched match has a HUD (use --force-hud)", false)
	var p := _build(true, "nobody")
	Game.world = p
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.setup(p, null)
	var panel := hud.get_node_or_null("PracticePanel") as PracticePanel
	_check("a practice match's HUD has the panel", panel != null)
	if panel == null:
		hud.free()
		_drop(p)
		return
	var role := p.human_role
	var h := p.human
	h.income_mult = 0.0
	panel._process(0.0)
	var m := panel.measure(hud)
	print("INFO the panel measured: room %s px between the me panel and the gear slots, the open panel is %s px high (window %s)" % [str(snappedf(m.x, 1.0)), str(snappedf(m.y, 1.0)), str(hud.get_viewport_rect().size)])
	var button_ok := true
	for key: String in panel._buttons:
		var b: Button = panel._buttons[key]
		button_ok = button_ok and b.custom_minimum_size.y == float(PracticeSwitches.BUTTON_HEIGHT) and b.mouse_filter == Control.MOUSE_FILTER_STOP
	_check("every button is %d px high and takes the mouse (a click on it never reaches the guns)" % PracticeSwitches.BUTTON_HEIGHT, button_ok and panel.mouse_filter == Control.MOUSE_FILTER_STOP and not p.mouse_fire)
	_check("the treasury button is there for the Admiral only", panel._buttons.has("treasury") == (role == "admiral"))
	# A pilot starts with the hangar open: the panel is its tab; closing the hangar gives the panel back.
	if role == "pilot":
		_check("while the hangar is open the panel steps aside", hud._any_panel_open() and not panel.visible)
		hud._close_others(null)
		panel._process(0.0)
		_check("with the hangar closed the panel is back and open again, %d px wide" % PracticeSwitches.PANEL_WIDTH, not hud._any_panel_open() and panel.visible and panel._body.visible and panel.get_combined_minimum_size().x >= float(PracticeSwitches.PANEL_WIDTH), str(panel.get_combined_minimum_size()))
	else:
		_check("an Admiral starts with the panel open, %d px wide" % PracticeSwitches.PANEL_WIDTH, panel._body.visible and panel.get_combined_minimum_size().x >= float(PracticeSwitches.PANEL_WIDTH), str(panel.get_combined_minimum_size()))
	# One press, one order, applied on the next tick.
	var queue0 := p.orders.queue.size()
	var msg := panel.press(PracticeSwitches.FREEZE, false)
	_check("the Freeze press sends one order, applied on the next tick", msg == "" and p.orders.queue.size() == queue0 + 1 and not p.minion_director.frozen)
	_step(p, 1)
	panel._process(0.0)
	hud.top_bar.refresh(p)
	var tags: Label = hud.top_bar.get_node("Row/Middle/Tags")
	_check("the world is frozen, the button says Frozen, the wave line and the tag line say so", p.minion_director.frozen and panel._buttons["freeze"].text == "Freeze waves: Frozen" and panel._wave_line.text == "Waves frozen" and tags.text.contains("WAVES FROZEN"), "'%s' '%s'" % [panel._buttons["freeze"].text, tags.text])
	msg = panel.press(PracticeSwitches.FREEZE, false)
	_step(p, 1)
	panel._process(0.0)
	_check("a second Freeze press lets the waves run again", msg == "" and not p.minion_director.frozen and panel._buttons["freeze"].text == "Freeze waves: Running")
	queue0 = p.orders.queue.size()
	msg = panel.press(PracticeSwitches.WAVE, false)
	_check("the Send one wave press sends one order", msg == "" and p.orders.queue.size() == queue0 + 1, msg)
	_step(p, 2)
	_check("the wave is out on the next tick", p.minion_director.last_send_tick == p.tick_count - 1 and _free_minions(p) > 0, "%d minions" % _free_minions(p))
	msg = panel.press(PracticeSwitches.WAVE, false)
	_check("a second Send one wave press at once is refused and the line shows under its button", msg == "Wait a second" and panel._notes["wave"].visible and panel._notes["wave"].text == "Wait a second", msg)
	panel._process(1.0)
	_check("the refusal line is still there after 1 s", panel._notes["wave"].visible)
	panel._process(1.1)
	_check("the refusal line is gone after 2 s", not panel._notes["wave"].visible)
	# Camps: the nearest one to the centre of the screen.
	var jd := p.jungle_director
	var camp_id := str(jd.camps.keys()[0])
	var camp_at: Vector2 = (jd.camps[camp_id]["info"] as Dictionary)["pos"]
	if p.camera != null:
		p.camera.look_at_point(camp_at)
		p.camera.global_position = camp_at
		p.camera.force_update_scroll()
	var near := panel.nearest_camp()
	_check("with the camera on camp %s the nearest camp is that one (%s)" % [camp_id, near], near == camp_id)
	var before_id: int = (jd.camps[camp_id]["unit"] as Derelict).get_instance_id()
	queue0 = p.orders.queue.size()
	msg = panel.press(PracticeSwitches.CAMP_NEAR, false)
	_check("the Respawn nearest camp press sends one order carrying the camp's id", msg == "" and p.orders.queue.size() == queue0 + 1 and str((p.orders.queue.back() as Dictionary)["target"]) == camp_id, msg)
	_step(p, 1)
	_check("the nearest camp is a new derelict next tick", (jd.camps[camp_id]["unit"] as Derelict).get_instance_id() != before_id)
	queue0 = p.orders.queue.size()
	msg = panel.press(PracticeSwitches.CAMPS, false)
	_check("the Respawn all camps press sends one order", msg == "" and p.orders.queue.size() == queue0 + 1, msg)
	_step(p, 1)
	# Money: +5,000, then a press at the limit is refused.
	h.credits = 700.0
	msg = panel.press(PracticeSwitches.MONEY, false)
	_step(p, 1)
	panel._process(0.0)
	_check("the money press adds 5,000 on the next tick and the line says so", msg == "" and h.credits == 5700.0 and panel._money_line.text == "Practice money so far: 5,000", "%s '%s'" % [str(h.credits), panel._money_line.text])
	h.credits = 96000.0
	panel.press(PracticeSwitches.MONEY, false)
	_step(p, 1)
	panel._process(0.0)
	_check("at the limit the button says Purse full and is greyed", h.credits == 100000.0 and panel._buttons["money"].disabled and panel._buttons["money"].text == "Purse full")
	msg = panel.press(PracticeSwitches.MONEY, false)
	_check("a press at the limit is refused (Purse full) and shows its line", msg == "Purse full" and panel._notes["money"].visible, msg)
	# Cooldowns: the Admiral has the section only while flying.
	if role == "admiral":
		_check("a docked Admiral has no cooldown section", not panel._cd_box.visible)
		var ship_a := _launch_human(p, "fighter")
		panel._process(0.0)
		_check("a flying Admiral has the cooldown section", ship_a != null and panel._cd_box.visible)
	else:
		_check("a pilot has the cooldown section", panel._cd_box.visible)
		_launch_human(p, "fighter")
	msg = panel.press(PracticeSwitches.CD_RESET, false)
	_check("the Reset cooldowns press with a ship is accepted", msg == "", msg)
	msg = panel.press(PracticeSwitches.CD_AUTO, false)
	_step(p, 1)
	panel._process(0.0)
	hud.top_bar.refresh(p)
	_check("the No cooldowns press turns it on: the button, the world and the tag line say so", msg == "" and p.practice_range.no_cooldowns and panel._buttons["cd_auto"].text == "No cooldowns: On" and tags.text.contains("NO COOLDOWNS"), "'%s' '%s'" % [panel._buttons["cd_auto"].text, tags.text])
	panel.press(PracticeSwitches.CD_AUTO, false)
	_step(p, 1)
	_check("a second press turns it off", not p.practice_range.no_cooldowns)
	_check("no press set the guns' mouse_fire", not p.mouse_fire)
	# The O key.
	var was_open := panel.is_open()
	var ev_o := InputEventKey.new()
	ev_o.keycode = KEY_O
	ev_o.physical_keycode = KEY_O
	ev_o.pressed = true
	var ev_shift_o := InputEventKey.new()
	ev_shift_o.keycode = KEY_O
	ev_shift_o.physical_keycode = KEY_O
	ev_shift_o.shift_pressed = true
	ev_shift_o.pressed = true
	_check("an O key press asks the panel to open or close (wing preset A)", PracticePanel.key_toggles(ev_o) and KeyMap.preset_choice("wing_commands") == "A")
	_check("Shift+O does not (it is another key)", not PracticePanel.key_toggles(ev_shift_o))
	panel.toggle_open(false)
	_check("the toggle closes an open panel and opens a closed one", panel.is_open() != was_open)
	panel.toggle_open(false)
	_check("and back again", panel.is_open() == was_open)
	hud.free()
	_drop(p)


## Item 5: the record. After one press of each switch the stats record's match holds "practice_uses" with
## each switch counted once and the tick of its first press, and so does the note's description; the log's
## header names the range; a normal match has none of these.
func _check_record() -> void:
	var p := _build(true, "nobody")
	p.human.income_mult = 0.0
	var ship := _launch_human(p, "fighter")
	_check("the human launches a fighter for the record case", ship != null)
	var sent := PackedStringArray()
	for sw: String in PracticeSwitches.WORDS:
		if sw == PracticeSwitches.TREASURY and p.human_role != "admiral":
			continue
		var on := 1 if PracticeSwitches.TOGGLES.has(sw) else -1
		var camp := str(p.jungle_director.camps.keys()[0]) if sw == PracticeSwitches.CAMP_NEAR else ""
		var msg := PracticeOrders.send(p, sw, on, camp)
		if msg != "":
			sent.append("%s: %s" % [sw, msg])
	_check("one press of each switch is accepted", sent.is_empty(), "; ".join(sent))
	_step(p, 2)
	var rec := StatsRecorder.new()
	rec.world = p
	var in_range: Dictionary = rec.snapshot(false, "check")["match"]
	rec.world = world
	var outside: Dictionary = rec.snapshot(false, "check")["match"]
	rec.free()
	var uses: Dictionary = in_range.get("practice_uses", {})
	var counted := true
	for sw: String in PracticeSwitches.WORDS:
		if sw == PracticeSwitches.TREASURY and p.human_role != "admiral":
			counted = counted and not uses.has(sw)
			continue
		var row: Dictionary = uses.get(sw, {})
		counted = counted and int(row.get("count", 0)) == 1 and int(row.get("tick", 0)) > 0
	_check("the stats record's match has practice_uses: each switch once, with the tick of its first press", counted, str(uses))
	_check("a normal match's stats record has neither practice nor practice_uses", not outside.has("practice") and not outside.has("practice_uses"), str(outside.keys()))
	var note_in: Dictionary = NoteWriter.describe(p, "check", false, "")["setup"]
	var note_out: Dictionary = NoteWriter.describe(world, "check", false, "")["setup"]
	var practice: Dictionary = note_in.get("practice", {})
	_check("the note's setup has the practice entry (the choice and the uses)", str(practice.get("others", "")) == "nobody" and (practice.get("uses", {}) as Dictionary) == uses, str(practice))
	_check("a normal match's note has no practice entry", not note_out.has("practice"))
	var head_in := OrderLog.make_header(p)
	var head_out := OrderLog.make_header(world)
	_check("the log's header of a range holds practice= before fp0=", head_in.contains(" practice=nobody fp0="), head_in.left(200))
	_check("a normal match's header has no practice word", not head_out.contains("practice="))
	_drop(p)


## Item 1 (c): the order record of every switch survives a write to the log's line and a read back,
## equal in value and type.
func _check_round_trip() -> void:
	var bad := PackedStringArray()
	var n := 0
	for role: String in ["pilot", "admiral"]:
		var seat: int = 0 if role == "pilot" else Rules.ADMIRAL_SEAT
		for sw: String in PracticeSwitches.WORDS:
			var on := 1 if PracticeSwitches.TOGGLES.has(sw) else -1
			var camp := "camp_7" if sw == PracticeSwitches.CAMP_NEAR else ""
			var settings := {"switch": sw}
			if on >= 0:
				settings["on"] = on
			var r: Dictionary
			if camp != "":
				r = Order.make(OrderKinds.PRACTICE, 0, seat, true, settings, [], "id", camp)
			else:
				r = Order.make(OrderKinds.PRACTICE, 0, seat, true, settings)
			n += 1
			r["id"] = n
			r["apply_tick"] = 300 + n
			r["tick"] = 299 + n
			var line := Order.to_line(r, "ok")
			var back := Order.from_line(line)
			var same := back.size() == r.size() and line.split(" ").size() == 9
			for k in r:
				if typeof(back.get(k)) != typeof(r[k]) or back.get(k) != r[k]:
					same = false
			if not same:
				bad.append("%s/%s: %s" % [role, sw, line])
	_check("the record of each of the %d switches (both seats) is equal in value and type after a write and a read" % n, bad.is_empty(), "; ".join(bad))
