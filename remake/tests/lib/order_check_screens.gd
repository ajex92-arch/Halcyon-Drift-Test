class_name OrderCheckScreens
extends RefCounted
## WHAT THIS IS: check (v) of tests/order_check.gd: each of the Admiral screens' 14 places
## that give an order is driven once through its real node, in a run with the HUD
## (--force-hud --role=admiral), and the order record that reached the order queue is
## compared with the table row for it. A queued order must also show on the board by the
## next frame.
##
## HOW IT WORKS: run() opens the board, presses the board's buttons with pressed.emit() and
## calls the map tools' apply_at(), order_at() and order_lane() on the overlay. After each
## press it reads World.orders.last_submitted (the record submit() was given, accepted or
## not) and compares it with the expected record field by field. In a run with a window and
## --shots=<folder> it also saves a picture of the board with the toast of an accepted order and
## one with the toast of a refused order (board_accepted_toast.png, board_refused_toast.png).
##
## WHO USES IT: tests/order_check.gd (with --screens).

## Compare the last submitted record with the wanted one; report through test `t`.
static func expect(t, label: String, kind: String, target_kind: String, target, settings: Dictionary, subjects: Array = []) -> void:
	var got: Dictionary = t.world.orders.last_submitted
	var ok: bool = not got.is_empty() and got["kind"] == kind and int(got["team"]) == t.world.human_team and int(got["seat"]) == Rules.ADMIRAL_SEAT and bool(got["human"])
	ok = ok and got["target_kind"] == target_kind and typeof(got["target"]) == typeof(target) and got["target"] == target
	ok = ok and (got["settings"] as Dictionary) == settings and (got["subjects"] as Array) == subjects and got["mode"] == "replace"
	t.check("(v) %s sends %s" % [label, kind], ok, str(got))


## With --shots=<folder> and a window: save the picture of the screen as <name>.png after the
## frame has been drawn. Does nothing without a window (a headless run draws nothing).
static func shot(t, shot_name: String) -> void:
	var dir := str(Game.opt("shots", ""))
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	t.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


## The first Button under `node` whose text starts with `prefix`, or null.
static func find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).text.begins_with(prefix):
		return node as Button
	for c in node.get_children():
		var b := find_button(c, prefix)
		if b != null:
			return b
	return null


## Check (v): drive the 14 places and the refresh.
static func run(t) -> void:
	var w: World = t.world
	var tree: SceneTree = t.get_tree()
	var hud := tree.root.find_child("Hud", true, false) as Hud
	t.check("(v) the HUD exists (use --force-hud --role=admiral)", hud != null and w.human_role == "admiral")
	if hud == null:
		return
	var team := w.human_team
	var ts := w.teams[team]
	ts.treasury = 20000.0
	hud._toggle_board()
	await tree.physics_frame
	await tree.physics_frame
	var b: AdmiralBoard = hud.board
	b._set_tab("Build")
	await tree.physics_frame
	t.check("(v) the Admiral can give orders", b._ok())
	# The Build tab: drone, post, turret.
	var drone_label: Label = b._cards["drones"]
	var before := drone_label.text
	find_button(b, "Build a mining drone").pressed.emit()
	expect(t, "the drone button", OrderKinds.DRONE, "none", 0, {"node": ""})
	await tree.physics_frame
	await tree.physics_frame
	t.check("(v) a queued order shows on the board by the next frame", drone_label.text != before, "%s -> %s" % [before, drone_label.text])
	await shot(t, "board_accepted_toast")
	(b._cards["pbtn:top"] as Button).pressed.emit()
	expect(t, "the post button", OrderKinds.POST, "lane", "top", {})
	var turret_key := ""
	for key: String in b._cards:
		if key.begins_with("tbtn:") and key.ends_with(":pd"):
			turret_key = key
			break
	(b._cards[turret_key] as Button).pressed.emit()
	expect(t, "the turret button", OrderKinds.TURRET, "node", turret_key.split(":")[1], {"ttype": "pd"})
	# The Research tab: a module and a research.
	b._set_tab("Research")
	await tree.physics_frame
	(b._cards["fac:research"] as CardButton).pressed.emit()
	expect(t, "the module card", OrderKinds.MODULE, "id", "research", {})
	(b._cards["tech:repairBays"] as CardButton).pressed.emit()
	expect(t, "the research card", OrderKinds.RESEARCH, "id", "repairBays", {})
	# The Fleet tab: a minion buy.
	b._set_tab("Fleet")
	await tree.physics_frame
	var launch := find_button(b, "Launch to")
	launch.pressed.emit()
	var got: Dictionary = w.orders.last_submitted
	t.check("(v) the minion buy button sends MINION_BUY with its type and lane", got.get("kind") == OrderKinds.MINION_BUY and (got["settings"] as Dictionary).has("type") and (got["settings"] as Dictionary).has("lane") and got["target_kind"] == "none", str(got))
	# The map tools: each is armed and clicked at a point.
	var ov: CommandOverlay = hud.overlay
	var p := w.mothership(team).global_position + Vector2(700.4, 301.6)
	var pi := Order.point(p)
	for tool in ["bay", "ward", "waypoint", "move"]:
		ov.arm(tool)
		ov.apply_at(p)
		var kind := {"bay": OrderKinds.BAY, "ward": OrderKinds.WARD, "waypoint": OrderKinds.WAYPOINT, "move": OrderKinds.MOTHERSHIP_MOVE}[tool] as String
		expect(t, "the %s tool" % tool, kind, "point", pi, {"siege": 1} if tool == "waypoint" else {})
		ov.disarm()
	# The minion tools and the right click and the lane buttons.
	var m := w.spawn_minion(team, "fighter", "mid", w.mothership(team).global_position + Vector2(300, 0))
	ov.select_all()
	var ids: Array = [m.uid]
	ov.arm("fleet_move")
	ov.apply_at(p)
	expect(t, "the fleet move tool", OrderKinds.MINION_ORDER, "point", pi, {"type": "move"}, ids)
	ov.disarm()
	ov.arm("fleet_hold")
	ov.apply_at(p)
	expect(t, "the fleet hold tool", OrderKinds.MINION_ORDER, "point", pi, {"type": "hold"}, ids)
	ov.disarm()
	ts.facilities["fleet"] = true
	ov.order_at(p)
	expect(t, "the right click", OrderKinds.MINION_ORDER, "point", pi, {"type": "move"}, ids)
	ov.order_lane("bot")
	expect(t, "the lane button", OrderKinds.MINION_ORDER, "lane", "bot", {"type": "lane", "lane": "bot"}, ids)
	ts.facilities.erase("fleet")
	# A refusal that comes back at once shows its toast (the drone button with an empty treasury).
	b._set_tab("Build")
	await tree.physics_frame
	ts.treasury = 0.0
	find_button(b, "Build a mining drone").pressed.emit()
	await tree.physics_frame
	await tree.physics_frame
	await shot(t, "board_refused_toast")
