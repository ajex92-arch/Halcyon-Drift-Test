extends "res://tests/hit_size_probe.gd"
## WHAT THIS IS: the check that the small pilot ships are 10% bigger for
## shots and no bigger anywhere else. It is the hit-size probe
## (tests/hit_size_probe.gd, whose measuring it reuses) with a verdict.
##
## HOW IT WORKS: it freezes the match, makes every pilot hull and every minion
## type, and asks the real game code how big each is for a round, a beam and
## a blast, how big its physics circle is and how close two ships of the hull
## can be before they are pushed apart (the probe's methods). It then checks:
##   - the four small pilot hulls (Scout, Fighter, Lance Fighter, Bomber) count
##     Rules.SMALL_PILOT_HIT_MUL times their radius for a round, a beam and a
##     blast, and hit_radius() says the same; a plain round that passes the
##     centre at 1.05 x radius plus the round's own radius hits, one that
##     passes at 1.15 x radius plus its own radius misses;
##   - their body does not change: the physics circle is the radius and two
##     ships are pushed apart at twice the radius;
##   - every other pilot hull and every minion type counts exactly its radius
##     (so a round that passes a minion Snub-Fighter at 1.05 x radius plus the
##     round's own radius misses);
##   - the four capsule hulls (the frigates, the Destroyer, the Battlecruiser)
##     stand nose along +x and are hit as their capsule: a round or a beam that
##     passes the flank has its edge at the capsule's radius, a blast at the bow
##     has its edge at the bow tip, Unit.edge_dist() says the same at the bow,
##     the flank and the centre, and a bolt at the flank leaves a note whose
##     impact point is on the hull. Their body (physics circle, push apart) is
##     still the circle of their radius.
## It prints one line per unit and then "hit_size_check: N failures" (0 means
## all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_size_check
##
## WHO USES IT: main.gd loads it for --test=hit_size_check; run_checks runs it.
## It changes only units of a frozen match that is thrown away.

## How close (world units) a measured size must be to the wanted one.
const TOLERANCE := 0.02
## How many things have gone wrong so far.
var failures := 0
## The note of the last hit that was applied (Events.damage_applied), or null.
var _last_note: DamageInfo = null


## Check every unit, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_src = world.mothership(0)
	for hid: String in Ships.ORDER:
		var a := _launch(hid, 1)
		var b := _launch(hid, 0)
		_check_ship("ship:" + hid, a, b)
		_put(a)
		_put(b)
	for type_id: String in MINION_TYPES:
		var m := world.spawn_minion(1, type_id, "mid", _home)
		_check_minion("minion:" + type_id, m)
		_put(m)
	print("hit_size_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("hit_size_check: FAIL %s" % what)


## Check pilot ship `a` (team 1) with its partner `b` (team 0, same hull).
func _check_ship(label: String, a: Ship, b: Ship) -> void:
	var small := a.size_class == Rules.SIZE_SMALL
	var want := a.radius * (Rules.SMALL_PILOT_HIT_MUL if small else 1.0)
	# A capsule hull stands nose along +x, so the probe lines (along x, moved up
	# and down) pass its flank and the blast comes at its bow.
	if a.hit_r > 0.0:
		a.rotation = 0.0
	_place(a, _home)
	var shape := _shape_radius(a)
	var round_edge := _edge(a, "round")
	var beam_edge := _edge(a, "beam")
	var blast_edge := _edge(a, "blast")
	var push := _push_min_d(a, b)
	_expect(absf(a.hit_radius() - want) < 1e-6, "%s hit_radius %s, wanted %s" % [label, a.hit_radius(), want])
	_expect(absf(shape - a.radius) < 1e-6, "%s physics circle %s, wanted %s" % [label, shape, a.radius])
	_expect(absf(push - 2.0 * a.radius) < TOLERANCE, "%s pushed apart at %s, wanted %s" % [label, push, 2.0 * a.radius])
	if a.hit_r > 0.0:
		_check_capsule_edges(label, a, round_edge, beam_edge, blast_edge)
		print("hit_size_check: %s capsule hit_r %s spine %s off %s shape %s push %s round %s beam %s blast %s" % [
			label, a.hit_r, a.spine_len, a.spine_off, shape, push, round_edge, beam_edge, blast_edge])
		return
	_expect(absf(round_edge - want) < TOLERANCE, "%s round edge %s, wanted %s" % [label, round_edge, want])
	_expect(absf(beam_edge - want) < TOLERANCE, "%s beam edge %s, wanted %s" % [label, beam_edge, want])
	_expect(absf(blast_edge - want) < TOLERANCE, "%s blast edge %s, wanted %s" % [label, blast_edge, want])
	# A plain round passing at 1.05 x radius plus its own radius: it hits a
	# small pilot ship and misses every other.
	_place(a, _home)
	var near_hit := _touches(a, "round", a.radius * 1.05 + ROUND_RADIUS)
	_expect(near_hit == small, "%s a round at 1.05 x radius %s, wanted %s" % [label, "hit" if near_hit else "missed", "hit" if small else "missed"])
	# A round passing at 1.15 x radius plus its own radius misses every one.
	var far_hit := _touches(a, "round", a.radius * 1.15 + ROUND_RADIUS)
	_expect(not far_hit, "%s a round at 1.15 x radius hit" % label)
	print("hit_size_check: %s radius %s hit_radius %s shape %s push %s round %s beam %s blast %s" % [
		label, a.radius, a.hit_radius(), shape, push, round_edge, beam_edge, blast_edge])


## The capsule hull `a` (team 1, standing at home with its nose along +x): the
## edge a round, a beam and a blast see is the capsule's, not a circle's. A round
## or a beam passing the flank (the straight part) has its edge at hit_r; a blast
## coming at the bow has its edge at the bow tip (spine_off + half the spine +
## hit_r). Unit.edge_dist() agrees at the bow tip, the flank and the centre, and a
## bolt that hits the flank makes a note whose impact point is where it touched
## the hull.
func _check_capsule_edges(label: String, a: Ship, round_edge: float, beam_edge: float, blast_edge: float) -> void:
	var tip := a.spine_off + a.spine_len * 0.5 + a.hit_r
	_expect(absf(round_edge - a.hit_r) < TOLERANCE, "%s round edge %s, wanted the capsule's %s" % [label, round_edge, a.hit_r])
	_expect(absf(beam_edge - a.hit_r) < TOLERANCE, "%s beam edge %s, wanted the capsule's %s" % [label, beam_edge, a.hit_r])
	_expect(absf(blast_edge - tip) < TOLERANCE, "%s blast edge %s, wanted the bow tip %s" % [label, blast_edge, tip])
	var bow := _home + Vector2(tip, 0.0)
	var flank := _home + Vector2(a.spine_off, a.hit_r)
	_expect(absf(a.edge_dist(bow)) < 0.001, "%s edge distance at the bow tip is %s" % [label, a.edge_dist(bow)])
	_expect(absf(a.edge_dist(flank)) < 0.001, "%s edge distance at the flank is %s" % [label, a.edge_dist(flank)])
	_expect(absf(a.edge_dist(bow + Vector2(25.0, 0.0)) - 25.0) < 0.001, "%s edge distance 25 off the bow is %s" % [label, a.edge_dist(bow + Vector2(25.0, 0.0))])
	_expect(a.edge_dist(_home) < 0.0, "%s centre is not inside the capsule" % label)
	# A bolt from the side, in line with the middle of the capsule: its note's
	# impact point is on the flank, not a tick back.
	var proj := world.projectiles
	world.combat.emit_damage_events = true
	Events.damage_applied.connect(_on_hit)
	_last_note = null
	var from := flank + Vector2(0.0, 400.0)
	var i := proj.spawn(from, Vector2(0.0, -1000.0), 3.0, 40.0, Rules.W_BOLT, {"radius": 3.0}, null, null)
	for _t in 200:
		if proj.live[i] == 0:
			break
		proj._step(i, 0.016)
	Events.damage_applied.disconnect(_on_hit)
	world.combat.emit_damage_events = false
	_expect(_last_note != null, "%s the bolt at the flank made no note" % label)
	if _last_note != null:
		var hit_at: Vector2 = _last_note.impact
		_expect(absf(hit_at.x - flank.x) < 15.0 and absf(hit_at.y - flank.y) < 8.0, "%s the bolt's impact point %s is not on the flank %s" % [label, hit_at, flank])
		_expect(hit_at.distance_to(proj.prev[i]) > 1.0, "%s the bolt's impact point is a tick back" % label)
	_place(a, _home)


## Remember the note of every hit that is applied.
func _on_hit(_target: Node, info: RefCounted, _amount: float, _hull_dmg: float) -> void:
	_last_note = info as DamageInfo


## Check minion `m` (team 1): it counts exactly its radius.
func _check_minion(label: String, m: Minion) -> void:
	_place(m, _home)
	var round_edge := _edge(m, "round")
	var beam_edge := _edge(m, "beam")
	var blast_edge := _edge(m, "blast")
	_expect(absf(m.hit_radius() - m.radius) < 1e-6, "%s hit_radius %s, wanted %s" % [label, m.hit_radius(), m.radius])
	_expect(absf(round_edge - m.radius) < TOLERANCE, "%s round edge %s, wanted %s" % [label, round_edge, m.radius])
	_expect(absf(beam_edge - m.radius) < TOLERANCE, "%s beam edge %s, wanted %s" % [label, beam_edge, m.radius])
	_expect(absf(blast_edge - m.radius) < TOLERANCE, "%s blast edge %s, wanted %s" % [label, blast_edge, m.radius])
	var near_hit := _touches(m, "round", m.radius * 1.05 + ROUND_RADIUS)
	_expect(not near_hit, "%s a round at 1.05 x radius hit" % label)
	print("hit_size_check: %s radius %s hit_radius %s round %s beam %s blast %s" % [label, m.radius, m.hit_radius(), round_edge, beam_edge, blast_edge])
