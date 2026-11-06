class_name OrderCheckScreens
extends RefCounted
## WHAT THIS IS: check (v) of tests/order_check.gd: each of the Admiral screens' places
## that give an order is driven once through its real node, in a run with the HUD
## (--force-hud --role=admiral), and the order record that reached the order queue is
## compared with the table row for it. A queued order must also show on the board by the
## next frame.
##
## HOW IT WORKS: run() opens the board, presses the board's buttons with pressed.emit() and
## calls the map tools' apply_at() on the overlay. After each
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


## Check (v): drive the places and the refresh.
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

	# The Yard tab: a buy button and the buttons of a list row.
	b._set_tab("Fleet")
	await tree.physics_frame
	(b._cards["yard_buy:fighter"] as Button).pressed.emit()
	expect(t, "the Fighter buy button", OrderKinds.PRODUCE, "none", 0, {"hull": "fighter", "count": 3, "repeat": 0, "rally": "mothership"})
	(b._cards["yard_buy:destroyer"] as Button).pressed.emit()
	expect(t, "the Destroyer buy button", OrderKinds.PRODUCE, "none", 0, {"hull": "destroyer", "count": 1, "repeat": 0, "rally": "mothership"})
	await tree.physics_frame
	await tree.physics_frame
	var rows: Array = b._cards["yard_rows"]
	var first: Dictionary = rows[0]
	var first_id := str((first["row"] as Control).get_meta("item", ""))
	t.check("(v) a queued ship shows as a row of the Yard tab", (first["row"] as Control).visible and first_id != "")
	(first["hold"] as Button).pressed.emit()
	expect(t, "the hold button of a row", OrderKinds.HOLD_ITEM, "item", first_id, {"hold": 1})
	(first["down"] as Button).pressed.emit()
	expect(t, "the down button of a row", OrderKinds.MOVE_ITEM, "item", first_id, {"dir": 1})
	(first["cancel"] as Button).pressed.emit()
	expect(t, "the cancel button of a row", OrderKinds.CANCEL, "item", first_id, {})
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
	# A refusal that comes back at once shows its toast (the turret button with an empty
	# treasury: a drone, a module and a research wait for ore instead of being refused).
	b._set_tab("Build")
	await tree.physics_frame
	ts.treasury = 0.0
	(b._cards[turret_key] as Button).pressed.emit()
	await tree.physics_frame
	await tree.physics_frame
	await shot(t, "board_refused_toast")
