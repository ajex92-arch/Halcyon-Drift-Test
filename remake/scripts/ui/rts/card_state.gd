class_name CardState
extends RefCounted
## WHAT THIS IS: what each cell of the command card says and which look it wears right now: the snapshot of a cell
## for the card (name, second line, key, count, tip and one of the four looks of DESIGN 5.4).
##
## HOW IT WORKS: static functions that read the match through the card's view. snapshot() builds the Dictionary
## CardCell.show_data() writes. Orders cells light only when their kind is in OrderKinds.BOUGHT_KINDS and a squadron
## is selected (else they are drawn locked, with "later stage" or "select first"); the Build cells follow the
## looks: ready, cannot pay (the treasury is short: the cell stays live, "short N" with the look of
## RtsUiCalls.CANNOT_PAY_LOOK), locked (the hull's research or module is missing: the words come from
## Tech.ship_unlock_label()) and full (the fleet is full: it still takes the order and waits for room). Money never
## disables a cell.
##
## WHO USES IT: CommandCard (every beat for every shown cell), tests/rts_tour.gd.


## The snapshot of cell `id` of page `page_id`: {state, name, sub, key, digit, count, tip, share, short, picked}.
static func snapshot(card: CommandCard, page_id: String, id: String) -> Dictionary:
	var rec := CardPages.cell(page_id, id)
	var row := str(rec.get("row", ""))
	var d := {"state": "ready", "name": str(rec["name"]), "sub": "", "key": KeyMap.first_key("home", row) if row != "" else "",
		"digit": "", "count": "", "tip": str(rec["tip"]), "share": 1.0, "short": 0.0, "picked": false}
	match page_id:
		"orders":
			_orders(card, id, rec, d)
		"build":
			_build(card, id, d)
		"base":
			_base(card, id, d)
	if str(d["key"]) != "":
		d["tip"] = "%s (%s)" % [d["tip"], d["key"]]
	return d


## An Orders cell: live only for a kind a bought squadron takes, and only with squadrons selected.
static func _orders(card: CommandCard, id: String, rec: Dictionary, d: Dictionary) -> void:
	var ov := card.view.overlay
	var kind := str(rec["kind"])
	var live := kind != "" and OrderKinds.BOUGHT_KINDS.has(kind)
	if not live:
		d["state"] = "locked"
		d["sub"] = "later stage"
		d["tip"] = "%s. %s." % [rec["tip"], OrderKinds.TEXT_UNBUILT]
	elif ov.sel_squads.is_empty():
		d["state"] = "locked"
		d["sub"] = "select first"
		d["tip"] = "%s Select squadrons first." % rec["tip"]
	d["picked"] = id == "move" and ov.tool == "verb_move"


## A Build cell: a hull (one of the ten), the Capitals opener, the drone, the squadron size or Repeat.
static func _build(card: CommandCard, id: String, d: Dictionary) -> void:
	var view := card.view
	var ts: TeamState = view.world.teams[view.team]
	if Ships.HULLS.has(id):
		_hull(card, id, d)
		return
	match id:
		"capitals":
			var open := CardPages.CAPITALS.any(func(h: String) -> bool: return UnlockAll.is_unlocked(ts) or ts.ship_unlocked(h))
			d["state"] = "ready" if open else "locked"
			d["sub"] = "2 hulls" if open else "locked"
		"drone":
			_drone(card, d)
		"size":
			d["sub"] = ""
			d["name"] = "Size x%d" % int(view.yard["count"])
			d["tip"] = "%s Now %d." % [d["tip"], int(view.yard["count"])]
		"repeat":
			d["name"] = "Repeat"
			d["picked"] = bool(view.yard["repeat"])
			d["tip"] = "%s Now %s." % [d["tip"], "on" if bool(view.yard["repeat"]) else "off"]


## The cell of hull `hull`: its price, its looks and its words.
static func _hull(card: CommandCard, hull: String, d: Dictionary) -> void:
	var view := card.view
	var ts: TeamState = view.world.teams[view.team]
	var p := ts.production
	var count := mini(int(view.yard["count"]), RtsHulls.max_count(hull))
	var price := RtsHulls.price_of(hull, count)
	var label := str(Ships.HULLS[hull]["label"])
	d["name"] = Formations.short_hull(hull)
	var idx := Ships.ORDER.find(hull)
	d["digit"] = KeyMap.first_key("home", "hull_%d" % (idx + 1)) if idx >= 0 else ""
	var base_tip := "%s: %s Costs %d ore, takes %d s. You pay when the build starts." % [label, Ships.blurb(hull), price, roundi(float(RtsHulls.build_ticks(hull)) / 60.0)]
	d["tip"] = base_tip
	d["sub"] = str(price)
	if not UnlockAll.is_unlocked(ts) and not ts.ship_unlocked(hull):
		d["state"] = "locked"
		d["sub"] = "locked"
		d["tip"] = "%s Needs %s. A click opens the research board." % [label, Tech.ship_unlock_label(hull)]
	elif p.capacity.used() >= p.capacity.limit():
		d["state"] = "full"
		d["sub"] = "fleet full"
		d["tip"] = "%s The fleet is full (%d of %d): the order still goes in and waits for room." % [base_tip, p.capacity.used(), p.capacity.limit()]
	elif ts.treasury < float(price):
		var missing := float(price) - ts.treasury
		d["state"] = "cannot_pay"
		d["sub"] = _short_text(int(ceil(missing)))
		d["share"] = clampf(ts.treasury / float(maxi(1, price)), 0.0, 1.0)
		d["short"] = clampf(missing / float(maxi(1, price)), 0.0, 1.0)
		d["tip"] = "%s Short %d ore: the order still goes in and waits for the ore." % [base_tip, int(ceil(missing))]


## "short 450" or, from a thousand up, "short 1.1k": the words a cell has room for.
static func _short_text(n: int) -> String:
	return "short %d" % n if n < 1000 else "short %.1fk" % (float(n) / 1000.0)


## The mining drone cell (Build and Base pages): its price, the count of working drones, and the limit.
static func _drone(card: CommandCard, d: Dictionary) -> void:
	var view := card.view
	var ts: TeamState = view.world.teams[view.team]
	var cost := int(Structures.MINING_DRONE["cost"])
	var working := view.world.mining_drone_count(view.team)
	var most := int(Structures.MINING_DRONE["max"])
	# The count is what the limit counts (AdmiralCommand.drone_blocker): working drones plus the ones queued (being
	# built, waiting or on hold), so at the limit the cell reads 14/14, not "4/14" with ten still in the queue.
	d["count"] = "%d/%d" % [working + ts.drones_queued(), most]
	d["sub"] = str(cost)
	var why: String = view.world.command.drone_blocker(view.team)
	if why != "":
		d["state"] = "full"
		d["sub"] = "limit"
		d["tip"] = "%s %s." % [d["tip"], why]
	elif ts.treasury < float(cost):
		d["state"] = "cannot_pay"
		d["sub"] = _short_text(int(ceil(float(cost) - ts.treasury)))
		d["share"] = clampf(ts.treasury / float(cost), 0.0, 1.0)
		d["short"] = clampf((float(cost) - ts.treasury) / float(cost), 0.0, 1.0)


## A Base cell: tools, boards and the build list's newest item.
static func _base(card: CommandCard, id: String, d: Dictionary) -> void:
	var view := card.view
	var ts: TeamState = view.world.teams[view.team]
	var ov := view.overlay
	var cmd := view.world.command
	match id:
		"drone":
			_drone(card, d)
		"deputy", "deputy_preset":
			d["state"] = "locked"
			d["sub"] = "later stage"
			d["tip"] = "Comes with the deputy stage."
		"turret":
			d["picked"] = ov.tool == "turret"
		"torpedo":
			d["picked"] = ov.tool == "torpedo"
			_research_lock(d, cmd.torpedo_research_blocker(view.team))
		"repair":
			d["picked"] = ov.tool == "bay"
			d["count"] = "%d/%d" % [_alive(view.world.bays, view.team), int(Structures.REPAIR_BAY["max_per_team"])]
			_research_lock(d, cmd.bay_research_blocker(view.team))
		"ward":
			d["picked"] = ov.tool == "ward"
			d["count"] = "%d/%d" % [_alive(view.world.wards, view.team), int(Structures.WARD["max_per_team"])]
		"waypoint":
			d["picked"] = ov.tool == "waypoint"
			if ts.has_waypoint():
				d["sub"] = "%ds left" % int(maxf(0.0, ts.waypoint_until - view.world.time))
		"rally":
			d["picked"] = ov.tool == "rally"
			d["sub"] = {"mothership": "base", "lane": "lane", "point": "a spot"}.get(str(view.yard["rally"]), "base")
		"move":
			d["picked"] = ov.tool == "move"
			var why: String = cmd.move_blocker(view.team)
			if why != "":
				d["state"] = "locked"
				d["sub"] = "not now"
				d["tip"] = "%s %s." % [d["tip"], why]
		"cancel":
			if ts.production.items.is_empty():
				d["state"] = "locked"
				d["sub"] = "none"
		"production":
			d["picked"] = not view.prod.folded


## Draw cell `d` locked while its research is missing: `why` is AdmiralCommand's "Needs <research> research" (or "" with the
## research done, then nothing changes). The cell keeps no count, says "research" under its name and its tooltip names the
## research; a press starts no place mode (CardActions answers with the same words).
static func _research_lock(d: Dictionary, why: String) -> void:
	if why == "":
		return
	d["state"] = "locked"
	d["sub"] = "research"
	d["red"] = true
	d["count"] = ""
	d["picked"] = false
	d["tip"] = "%s. %s. Research it on the research board first." % [str(d["tip"]).trim_suffix("."), why]


## How many of `things` (units with a team and `alive`) team `team` has alive.
static func _alive(things: Array, team: int) -> int:
	var n := 0
	for t in things:
		if is_instance_valid(t) and t.team == team and t.alive:
			n += 1
	return n
