extends Node
## WHAT THIS IS: the check of the wing maths. It proves the numbers of SquadEngine and Formations
## (spacing, the five shapes, the turning frame, the guard pocket and its slots, the fire lane, the
## repeat window, the straggler and pick-up tests), and that the wing code rolls no dice.
##
## HOW IT WORKS: setup() runs the parts below and prints "squad_engine_check: N failures" (a FAIL line
## for each). It reads the game and changes nothing. Every expected number is written out in the part
## that tests it, taken from the design of the wings.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=squad_engine_check
##
## WHO USES IT: main.gd loads it for --test=squad_engine_check (it calls setup()); run_checks runs it.

## The files of the wing code that must roll no dice (no random number calls).
const NO_DICE_FILES := [
	"res://scripts/ai/wingman_ai.gd", "res://scripts/rts/squad_engine.gd", "res://scripts/rts/squad_orders.gd",
	"res://scripts/rts/squads.gd", "res://scripts/data/formations.gd", "res://scripts/ui/wing_wheel.gd",
	"res://scripts/ui/wing_strip.gd", "res://scripts/ui/wing_marks.gd",
]

## How many checks failed.
var _fails := 0


## main.gd calls this once, right after the World is built (the World is not needed).
func setup(_w: World) -> void:
	_spacing()
	_shapes()
	_frame()
	_speed()
	_guard()
	_lane()
	_repeats()
	_limits()
	_picks()
	_options()
	_no_dice()
	print("squad_engine_check: %d failures" % _fails)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## Count one check; print a FAIL line when it did not hold.
func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what, ("  (" + detail + ")") if detail != "" else "")


## The angle (degrees, 0 to 360) of point `p` seen from `from`, counted from a nose at `rot`.
func _deg_from_nose(from: Vector2, p: Vector2, rot: float) -> float:
	return fposmod(rad_to_deg((p - from).angle() - rot), 360.0)


## Part 1: the spacing of every hull.
func _spacing() -> void:
	var want := {"scout": 110.0, "fighter": 112.0, "lance": 113.0, "bomber": 117.0, "logistics": 144.0, "support": 144.0,
		"flak": 187.5, "ion": 185.0, "destroyer": 280.0, "battlecruiser": 300.0}
	for id: String in Ships.ORDER:
		var r := float(Ships.get_def(id)["radius"])
		var got := SquadEngine.spacing(r)
		_check("spacing of %s" % id, absf(got - float(want[id])) < 0.01, "got %s, wanted %s" % [got, want[id]])
	_check("spacing never under 110", SquadEngine.spacing(0.0) == 110.0)
	_check("spacing never over 300", SquadEngine.spacing(900.0) == 300.0)


## Part 2: the five shapes. Every place is clear of the leader and of the other places, for every hull as
## the leader (a Bomber, the widest strike craft, is the wingman), and at the two ends of S.
func _shapes() -> void:
	var wing_r := float(Ships.get_def("bomber")["radius"])
	var table := {
		Formations.WEDGE: [Vector2(-1.1, -1.0), Vector2(-1.1, 1.0), Vector2(-2.2, 0.0)],
		Formations.LINE: [Vector2(0.0, -1.5), Vector2(0.0, 1.5), Vector2(0.0, -3.0)],
		Formations.COLUMN: [Vector2(-1.4, 0.0), Vector2(-2.8, 0.0), Vector2(-4.2, 0.0)],
		Formations.LOOSE: [Vector2(-1.6, -2.6), Vector2(-1.6, 2.6), Vector2(-3.4, 0.0)],
		Formations.JUNGLE: [Vector2(-1.0, 0.0), Vector2(-2.0, 0.0), Vector2(-3.0, 0.0)],
	}
	var leashes := {Formations.WEDGE: 900.0, Formations.LINE: 900.0, Formations.COLUMN: 700.0, Formations.LOOSE: 1600.0, Formations.JUNGLE: 400.0}
	for f: int in table:
		for i in 3:
			_check("%s slot %d offset" % [Formations.formation_name(f), i], SquadEngine.slot_offset(f, i).is_equal_approx((table[f] as Array)[i] * (0.8 if f == Formations.JUNGLE else 1.0)))
		_check("%s leash" % Formations.formation_name(f), SquadEngine.leash(f, false) == float(leashes[f]))
	_check("jungle leash is 400 whatever the shape", SquadEngine.leash(Formations.LOOSE, true) == 400.0)
	_check("a jungle leader flies the jungle shape", SquadEngine.effective_formation(Formations.LINE, true) == Formations.JUNGLE and SquadEngine.effective_formation(Formations.LINE, false) == Formations.LINE)
	# The two ends of S, with a leader of the matching size.
	var pairs := [[110.0, float(Ships.get_def("scout")["radius"])], [300.0, float(Ships.get_def("battlecruiser")["radius"])]]
	for pair: Array in pairs:
		_clear_places(float(pair[0]), float(pair[1]), wing_r, "S=%d" % int(pair[0]), float(pair[1]) <= 44.0)
	# Every hull as the leader, its own S. The jungle shape is flown by hulls that can be in the jungle only.
	for id: String in Ships.ORDER:
		var r := float(Ships.get_def(id)["radius"])
		_clear_places(SquadEngine.spacing(r), r, wing_r, "leader %s" % id, Ships.size_of(id) <= 1)
	# The cycling helpers never produce a toggle: explicit values only.
	_check("next formation wraps 3 -> 0", Formations.next_formation(3) == 0 and Formations.next_formation(0) == 1)
	_check("next fire wraps 2 -> 0", Formations.next_fire(2) == 0 and Formations.next_fire(0) == 1)


## Every place of the four shapes (and the jungle one when `with_jungle`) is farther from the leader than
## the two radii plus 20, and from the other places too.
func _clear_places(s: float, leader_r: float, wing_r: float, what: String, with_jungle := true) -> void:
	var shapes := [Formations.WEDGE, Formations.LINE, Formations.COLUMN, Formations.LOOSE]
	if with_jungle:
		shapes.append(Formations.JUNGLE)
	for f: int in shapes:
		var spots: Array[Vector2] = []
		for i in 3:
			spots.append(SquadEngine.slot_offset(f, i, s))
		for i in 3:
			_check("%s %s slot %d clear of the leader" % [what, Formations.formation_name(f), i], spots[i].length() > leader_r + wing_r + 20.0, "%.1f vs %.1f" % [spots[i].length(), leader_r + wing_r + 20.0])
			for j in range(i + 1, 3):
				_check("%s %s slots %d and %d clear of each other" % [what, Formations.formation_name(f), i, j], spots[i].distance_to(spots[j]) > wing_r * 2.0 + 20.0)


## Part 3: the frame turns with the leader: a 90 degree step is mostly turned within half a second and
## never overshoots; a slow leader gives the frame its nose; a fast one its velocity.
func _frame() -> void:
	var h := 0.0
	var target := PI * 0.5
	var over := false
	var prev := h
	var monotone := true
	for tick in 30:
		h = SquadEngine.frame_step(h, Vector2(0, 600), 0.0, 1)
		if h > target + 0.0001:
			over = true
		if h < prev - 0.0001:
			monotone = false
		prev = h
	_check("the frame turns within 0.5 s (error under 5 degrees)", absf(target - h) < deg_to_rad(5.0), "error %.2f degrees" % rad_to_deg(target - h))
	_check("the frame never overshoots and never turns back", not over and monotone)
	# A step past the half turn goes the short way round.
	var h2 := SquadEngine.frame_step(deg_to_rad(170.0), Vector2(-600, -100), 0.0, 5)
	_check("the frame takes the short way round", absf(Util.ang_diff(h2, Vector2(-600, -100).angle())) < absf(Util.ang_diff(deg_to_rad(170.0), Vector2(-600, -100).angle())))
	# A slow leader: the nose gives the heading.
	var h3 := SquadEngine.frame_step(0.0, Vector2(50, 0), PI * 0.5, 600)
	_check("a slow leader gives the frame its nose", absf(h3 - PI * 0.5) < 0.01)
	# A step of many ticks at once (a wingman that steers every second tick) closes the same ground.
	var one := SquadEngine.frame_step(0.0, Vector2(0, 500), 0.0, 2)
	var two := SquadEngine.frame_step(SquadEngine.frame_step(0.0, Vector2(0, 500), 0.0, 1), Vector2(0, 500), 0.0, 1)
	_check("two ticks in one step turn about as far as two steps", absf(one - two) < 0.02)


## Part 4: the slot target, the wanted velocity and the sticks.
func _speed() -> void:
	# A wedge behind a leader heading east (+x) at 400: slot 0 is behind and to port (north, -y).
	var p := SquadEngine.slot_target(Vector2(1000, 1000), Vector2(400, 0), 0.0, Formations.WEDGE, 0, 110.0)
	var want := Vector2(1000, 1000) + Vector2(400, 0) * SquadEngine.LEAD_TIME + Vector2(-1.1 * 110.0, -1.0 * 110.0)
	_check("slot target in the frame, with the lead", p.is_equal_approx(want), "%s vs %s" % [p, want])
	# Heading south (+y): the frame turns, so slot 0 (port of a south-bound leader) lies east (+x).
	var q := SquadEngine.slot_target(Vector2.ZERO, Vector2.ZERO, PI * 0.5, Formations.WEDGE, 0, 100.0)
	_check("the slot turns with the frame", q.distance_to(Vector2(100.0, -110.0)) < 0.01, str(q))
	# Wanted velocity: the leader's plus 1.6 x the way to the slot, capped.
	var wv := SquadEngine.wanted_velocity(Vector2(300, 0), Vector2(100, 0), Vector2.ZERO, 720.0, false)
	_check("wanted velocity = leader + 1.6 x gap", wv.is_equal_approx(Vector2(460, 0)), str(wv))
	var wc := SquadEngine.wanted_velocity(Vector2(300, 0), Vector2(5000, 0), Vector2.ZERO, 640.0, false)
	_check("wanted velocity is capped at the ship's top speed", absf(wc.length() - 640.0) < 0.01)
	var wj := SquadEngine.wanted_velocity(Vector2(200, 0), Vector2(5000, 0), Vector2.ZERO, 640.0, true)
	_check("in the jungle the cap is leader speed + 40", absf(wj.length() - 240.0) < 0.01)
	# The sticks: 120 along the nose is full forward; 80 sideways is full strafe; port of an east nose is -y.
	var sv := SquadEngine.stick_values(Vector2(120, 0), Vector2.ZERO, 0.0)
	_check("120 units a second along the nose is full forward", is_equal_approx(sv.x, 1.0) and is_equal_approx(sv.y, 0.0))
	var sp := SquadEngine.stick_values(Vector2(0, -80), Vector2.ZERO, 0.0)
	_check("80 units a second to port is full strafe left (+1)", is_equal_approx(sp.y, 1.0), str(sp))
	var sh := SquadEngine.stick_values(Vector2(60, 40), Vector2.ZERO, 0.0)
	_check("half the error is half the stick", is_equal_approx(sh.x, 0.5) and is_equal_approx(sh.y, -0.5), str(sh))
	var sc := SquadEngine.stick_values(Vector2(9000, 9000), Vector2.ZERO, 0.0)
	_check("the sticks are clamped to 1", sc.x == 1.0 and sc.y == -1.0)
	# The little rules.
	_check("in slot is within 60", SquadEngine.in_slot(60.0) and not SquadEngine.in_slot(60.5))
	_check("catching up is beyond 2.5 S", SquadEngine.catching_up(276.0, 110.0) and not SquadEngine.catching_up(274.0, 110.0))
	_check("boost needs 4 S and the open at both ends", SquadEngine.may_boost(500.0, 110.0, true, true) and not SquadEngine.may_boost(500.0, 110.0, false, true) and not SquadEngine.may_boost(500.0, 110.0, true, false) and not SquadEngine.may_boost(400.0, 110.0, true, true))
	_check("the route finder is used beyond 1200 or with a rock between", SquadEngine.use_travel(1201.0, false) and SquadEngine.use_travel(100.0, true) and not SquadEngine.use_travel(1200.0, false))
	var hs := SquadEngine.hold_slot(Vector2(500, 500), 90.0, Formations.COLUMN, 0, 100.0)
	_check("hold slots turn with the held heading", hs.distance_to(Vector2(500, 500) + Vector2(0, -140)) < 0.01, str(hs))


## Part 5: the guard pocket and its slots.
func _guard() -> void:
	var cones := {"scout": 70.0, "fighter": 70.0, "lance": 70.0, "bomber": 70.0, "logistics": 70.0, "support": 50.0, "flak": 20.0,
		"ion": 70.0, "destroyer": 30.0, "battlecruiser": 30.0}
	for id: String in Ships.ORDER:
		_check("guard cone of %s" % id, absf(SquadEngine.guard_cone(Ships.get_def(id)) - float(cones[id])) < 0.01, str(SquadEngine.guard_cone(Ships.get_def(id))))
	# A cone is always inside 16 to 70.
	_check("a hull with only automatic guns gets the widest pocket", SquadEngine.guard_cone({"mounts": [{"type": "auto", "arc": 180.0}]}) == 70.0)
	_check("a very wide turret gets the narrowest pocket", SquadEngine.guard_cone({"mounts": [{"type": "turret", "arc": 175.0}]}) == 16.0)
	# The slots of the Destroyer and the Battlecruiser, seen from the ward's nose.
	var pos := Vector2(3000, 2000)
	var rot := 0.7
	var dd := Ships.get_def("destroyer")
	var dc := SquadEngine.guard_cone(dd)
	var d0 := SquadEngine.guard_slot(pos, rot, float(dd["radius"]), dc, 0)
	var d1 := SquadEngine.guard_slot(pos, rot, float(dd["radius"]), dc, 1)
	var d2 := SquadEngine.guard_slot(pos, rot, float(dd["radius"]), dc, 2)
	_check("Destroyer slot 0 at 165 degrees", absf(_deg_from_nose(pos, d0, rot) - 165.0) < 0.01, str(_deg_from_nose(pos, d0, rot)))
	_check("Destroyer slot 1 at 195 degrees", absf(_deg_from_nose(pos, d1, rot) - 195.0) < 0.01)
	_check("Destroyer slot 2 dead astern", absf(_deg_from_nose(pos, d2, rot) - 180.0) < 0.01)
	_check("Destroyer slots at 400, 400 and 600", absf(pos.distance_to(d0) - 400.0) < 0.01 and absf(pos.distance_to(d1) - 400.0) < 0.01 and absf(pos.distance_to(d2) - 600.0) < 0.01)
	var bd := Ships.get_def("battlecruiser")
	var bc := SquadEngine.guard_cone(bd)
	var b0 := SquadEngine.guard_slot(pos, rot, float(bd["radius"]), bc, 0)
	var b1 := SquadEngine.guard_slot(pos, rot, float(bd["radius"]), bc, 1)
	var b2 := SquadEngine.guard_slot(pos, rot, float(bd["radius"]), bc, 2)
	_check("Battlecruiser slots at 165 and 195 degrees", absf(_deg_from_nose(pos, b0, rot) - 165.0) < 0.01 and absf(_deg_from_nose(pos, b1, rot) - 195.0) < 0.01)
	_check("Battlecruiser slots at 460, 460 and 660", absf(pos.distance_to(b0) - 460.0) < 0.01 and absf(pos.distance_to(b1) - 460.0) < 0.01 and absf(pos.distance_to(b2) - 660.0) < 0.01)
	# The mothership: abeam at 90 and 270 degrees, 570 from the keel line; astern 1,080 (half_len 630 + 450).
	var m0 := SquadEngine.mothership_slot(pos, rot, 630.0, 340.0, 0)
	var m1 := SquadEngine.mothership_slot(pos, rot, 630.0, 340.0, 1)
	var m2 := SquadEngine.mothership_slot(pos, rot, 630.0, 340.0, 2)
	_check("mothership flank slots at 90 and 270 degrees", absf(_deg_from_nose(pos, m0, rot) - 90.0) < 0.01 and absf(_deg_from_nose(pos, m1, rot) - 270.0) < 0.01)
	_check("mothership flank slots 570 from the keel line", absf(pos.distance_to(m0) - 570.0) < 0.01 and absf(pos.distance_to(m1) - 570.0) < 0.01)
	_check("mothership rear slot 1,080 astern", absf(_deg_from_nose(pos, m2, rot) - 180.0) < 0.01 and absf(pos.distance_to(m2) - 1080.0) < 0.01)


## Part 6: the fire lane (10 degrees off the aim line is in, 14 is out; nearer than the aim distance plus 300).
func _lane() -> void:
	var ward := Vector2(1000, 1000)
	var aim := ward + Vector2(2000, 0)
	var ten := ward + Vector2(1500, 0).rotated(deg_to_rad(10.0))
	var fourteen := ward + Vector2(1500, 0).rotated(deg_to_rad(14.0))
	_check("a point 10 degrees off the aim line is in the lane", SquadEngine.in_fire_lane(ward, aim, ten))
	_check("a point 14 degrees off the aim line is out of the lane", not SquadEngine.in_fire_lane(ward, aim, fourteen))
	_check("a point on the line but beyond the aim distance + 300 is out", not SquadEngine.in_fire_lane(ward, aim, ward + Vector2(2400, 0)))
	_check("a point on the line just inside the reach is in", SquadEngine.in_fire_lane(ward, aim, ward + Vector2(2250, 0)))
	_check("a point behind the ward is out", not SquadEngine.in_fire_lane(ward, aim, ward + Vector2(-500, 0)))
	_check("an aim point within 300 of the ward makes no lane", not SquadEngine.in_fire_lane(ward, ward + Vector2(250, 0), ward + Vector2(100, 0)))


## Part 7: the repeat window.
func _repeats() -> void:
	var engine := {}
	_check("the first order is not a repeat", not SquadEngine.is_duplicate(engine, "ATTACK", 918, 100))
	SquadEngine.note_order(engine, "ATTACK", 918, 100)
	_check("the same order 30 ticks later is a repeat", SquadEngine.is_duplicate(engine, "ATTACK", 918, 130))
	_check("the same order 31 ticks later is not", not SquadEngine.is_duplicate(engine, "ATTACK", 918, 131))
	_check("another target is not a repeat", not SquadEngine.is_duplicate(engine, "ATTACK", 919, 110))
	_check("another kind is not a repeat", not SquadEngine.is_duplicate(engine, "GUARD", 918, 110))
	SquadEngine.note_order(engine, "HOLD", Vector2i(10, 20), 200)
	_check("a point target repeats by value", SquadEngine.is_duplicate(engine, "HOLD", Vector2i(10, 20), 210) and not SquadEngine.is_duplicate(engine, "HOLD", Vector2i(11, 20), 210))


## Part 8: the straggler and pick-up tests.
func _limits() -> void:
	var n := 0
	for tick in 1199:
		n = SquadEngine.straggler_ticks(n, 6001.0)
	_check("not yet a straggler after 1199 ticks", not SquadEngine.is_straggler(n))
	n = SquadEngine.straggler_ticks(n, 6001.0)
	_check("a straggler after 1200 ticks beyond 6,000", SquadEngine.is_straggler(n))
	_check("coming back within 6,000 clears the count", SquadEngine.straggler_ticks(n, 5999.0) == 0)
	_check("the pick-up needs the leader within 3,000 of the mothership", SquadEngine.pickup_ready(Vector2(2900, 0), Vector2.ZERO) and not SquadEngine.pickup_ready(Vector2(3100, 0), Vector2.ZERO))


## Part 9: the tap's pick on a synthetic list, and what makes two orders the same order.
func _picks() -> void:
	var pick := SquadOrders.pick_from([{"uid": 1, "d": 250.0}, {"uid": 2, "d": 100.0}], [{"uid": 3, "d": 50.0}])
	_check("the nearest enemy within 300 is attacked, even beside a big ship of ours", str(pick["kind"]) == "attack" and int(pick["uid"]) == 2)
	pick = SquadOrders.pick_from([{"uid": 1, "d": 301.0}], [{"uid": 3, "d": 599.0}])
	_check("an enemy at 301 is not picked: the big ship at 599 is guarded", str(pick["kind"]) == "guard" and int(pick["uid"]) == 3)
	pick = SquadOrders.pick_from([], [{"uid": 3, "d": 601.0}])
	_check("a big ship at 601 is not picked", str(pick["kind"]) == "none")
	pick = SquadOrders.pick_from([{"uid": 1, "d": 300.0}], [])
	_check("an enemy at exactly 300 is picked", str(pick["kind"]) == "attack" and int(pick["uid"]) == 1)
	pick = SquadOrders.pick_from([{"uid": 7, "d": 120.0}, {"uid": 8, "d": 120.0}], [])
	_check("a tie goes to the first in the list", int(pick["uid"]) == 7)
	pick = SquadOrders.pick_from([], [{"uid": 4, "d": 500.0}, {"uid": 5, "d": 200.0}])
	_check("the nearest big ship is guarded", str(pick["kind"]) == "guard" and int(pick["uid"]) == 5)
	pick = SquadOrders.pick_from([], [])
	_check("nothing near gives nothing", str(pick["kind"]) == "none" and int(pick["uid"]) == 0)
	# What counts as the same order.
	var wedge := Order.make(OrderKinds.SET_FORMATION, 0, 0, true, {"formation": 0})
	var line := Order.make(OrderKinds.SET_FORMATION, 0, 0, true, {"formation": 1})
	_check("two formations are not the same order", SquadOrders.dedup_key(wedge) != SquadOrders.dedup_key(line))
	var follow := Order.make(OrderKinds.ESCORT, 0, 0, true, {"role": "follow"}, [1], "unit", 55)
	var cover := Order.make(OrderKinds.ESCORT, 0, 0, true, {"role": "defend"}, [1], "unit", 55)
	_check("follow and cover are not the same order", SquadOrders.dedup_key(follow) != SquadOrders.dedup_key(cover))
	var fire0 := Order.make(OrderKinds.SET_STANCE, 0, 0, true, {"fire": 0})
	var fire2 := Order.make(OrderKinds.SET_STANCE, 0, 0, true, {"fire": 2})
	_check("two fire settings are not the same order", SquadOrders.dedup_key(fire0) != SquadOrders.dedup_key(fire2))
	# The words.
	_check("the data word defend shows as Cover me", str(SquadOrders.ROLE_LABELS["defend"]) == "Cover me" and str(SquadOrders.ROLE_LABELS["follow"]) == "Form on me")


## Part 10: which hulls a seat gets, for every combination of the launch option and the two switches.
func _options() -> void:
	var saved_wingmen: Variant = Game.options.get("wingmen")
	var saved_test := Game.test_wing
	var saved_cpu := Game.cpu_wings
	Game.options.erase("wingmen")
	Game.test_wing = false
	Game.cpu_wings = false
	_check("no option, no switch: no wing for anybody", Game.wing_hulls_for(true).is_empty() and Game.wing_hulls_for(false).is_empty())
	Game.test_wing = true
	_check("the human's switch: a Scout, a Fighter and a Bomber for the human only", Game.wing_hulls_for(true) == PackedStringArray(["scout", "fighter", "bomber"]) and Game.wing_hulls_for(false).is_empty())
	Game.test_wing = false
	Game.cpu_wings = true
	_check("the computer switch: the same three for the computers only", Game.wing_hulls_for(false) == PackedStringArray(["scout", "fighter", "bomber"]) and Game.wing_hulls_for(true).is_empty())
	Game.test_wing = true
	_check("both switches: both", not Game.wing_hulls_for(true).is_empty() and not Game.wing_hulls_for(false).is_empty())
	Game.options["wingmen"] = "lance,bomber"
	_check("--wingmen wins for every seat", Game.wing_hulls_for(true) == PackedStringArray(["lance", "bomber"]) and Game.wing_hulls_for(false) == PackedStringArray(["lance", "bomber"]))
	Game.options["wingmen"] = "off"
	_check("--wingmen=off gives nobody a wing, whatever the switches", Game.wing_hulls_for(true).is_empty() and Game.wing_hulls_for(false).is_empty())
	Game.options["wingmen"] = ""
	_check("--wingmen= with nothing gives nobody a wing", Game.wing_hulls_for(true).is_empty())
	Game.options["wingmen"] = "scout,nonsense,fighter"
	_check("an unknown hull is ignored", Game.wing_hulls_for(true) == PackedStringArray(["scout", "fighter"]))
	Game.options["wingmen"] = "scout,fighter,bomber,lance"
	_check("only three wingmen", Game.wing_hulls_for(true).size() == 3)
	Game.options["wingmen"] = " Scout , FIGHTER "
	_check("spaces and capitals do not matter", Game.wing_hulls_for(true) == PackedStringArray(["scout", "fighter"]))
	if saved_wingmen == null:
		Game.options.erase("wingmen")
	else:
		Game.options["wingmen"] = saved_wingmen
	Game.test_wing = saved_test
	Game.cpu_wings = saved_cpu


## Part 11: the wing code rolls no dice: none of the listed files calls randf, randi or randomize.
func _no_dice() -> void:
	var looked := 0
	for path: String in NO_DICE_FILES:
		if not FileAccess.file_exists(path):
			continue
		looked += 1
		var text := FileAccess.get_file_as_string(path)
		for word in ["randf", "randi", "randomize", "CPUParticles2D"]:
			_check("%s has no %s" % [path.get_file(), word], not text.contains(word))
	print("squad_engine_check: looked at %d wing files for dice" % looked)
