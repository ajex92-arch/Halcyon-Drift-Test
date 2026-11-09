class_name CardPages
extends RefCounted
## WHAT THIS IS: the command card's contents as data: the three pages (Orders, Build, Base), every cell with its name,
## the key row it uses and its words, and where each cell sits for the home layout in force (B and C a 3x3 grid, A a 4x3
## grid), in the grid, the fixed extra row of three keyless buttons, the More pop-out (up to 8 entries) and the
## Capitals pop-out. It is the table of DESIGN 5.6.
##
## HOW IT WORKS: only constants and small static functions. A cell is CELLS["<page>/<id>"] = {name, row, kind, tip}:
## `row` is the id of its key row in KeyMapData (mode "home"), "" for a cell with no key; `kind` is the order word of an
## Orders cell (it lights only when OrderKinds.BOUGHT_KINDS holds it). LAYOUT_B and LAYOUT_A say, per page, the grid
## (row by row, "" for a blank place), the extra row, the More list and the Capitals list. Layout C draws layout B's
## cells with its own letters (the keys are read from the key map, never written here). `rows_without_cell()` lists any
## key row of a page that has no cell, for the tour's check that every row has a place in every layout.
##
## WHO USES IT: CommandCard (builds its buttons from it), tests/rts_tour.gd.

## The pages in tab order.
const PAGES := ["orders", "build", "base"]
## The tab names.
const LABELS := {"orders": "Orders", "build": "Build", "base": "Base"}
## How many ships the Capitals pop-out opens: destroyer and battlecruiser.
const CAPITALS := ["destroyer", "battlecruiser"]

## Every cell: "<page>/<id>" -> {name, row, kind, tip}.
const CELLS := {
	"orders/move": {"name": "Move", "row": "order_move", "kind": OrderKinds.MOVE, "tip": "Move: click it, then click where the selected squadrons should go. A right-click on open ground does the same."},
	"orders/attack_move": {"name": "Attack-move", "row": "order_attack_move", "kind": OrderKinds.ATTACK_MOVE, "tip": "Attack-move: go to a spot and fight what you meet on the way."},
	"orders/hold": {"name": "Hold", "row": "order_hold", "kind": OrderKinds.HOLD, "tip": "Hold: the selected squadrons stay where they are and fight from there."},
	"orders/stop": {"name": "Stop", "row": "order_stop", "kind": OrderKinds.STOP, "tip": "Stop: the selected squadrons stop where they are."},
	"orders/patrol": {"name": "Patrol", "row": "order_patrol", "kind": OrderKinds.PATROL, "tip": "Patrol between two spots."},
	"orders/retreat": {"name": "Retreat", "row": "order_retreat", "kind": OrderKinds.RETREAT, "tip": "Retreat to the mothership and dock."},
	"orders/defend": {"name": "Defend", "row": "order_defend", "kind": OrderKinds.DEFEND, "tip": "Defend a point or one of your structures."},
	"orders/goal": {"name": "Goal", "row": "order_goal", "kind": "", "tip": "Goal: give the squadrons a job to work towards, then click the target."},
	"orders/escort": {"name": "Escort", "row": "order_escort", "kind": OrderKinds.ESCORT, "tip": "Escort one of your pilots."},
	"orders/stance": {"name": "Stance", "row": "order_stance", "kind": OrderKinds.SET_STANCE, "tip": "Stance: how the squadrons fire and move."},
	"orders/position": {"name": "Position", "row": "order_position", "kind": OrderKinds.SET_STANCE, "tip": "Position stance: hold, manoeuvre or roam."},
	"orders/formation": {"name": "Formation", "row": "order_formation", "kind": OrderKinds.SET_FORMATION, "tip": "Formation: the shape the squadrons fly in."},
	"orders/push_lane": {"name": "Push lane", "row": "order_push_lane", "kind": OrderKinds.PUSH_LANE, "tip": "Push a lane with the selected squadrons."},
	"orders/merge": {"name": "Merge", "row": "order_merge", "kind": OrderKinds.MERGE, "tip": "Merge short squadrons into one."},
	"orders/full_assault": {"name": "Full assault", "row": "order_full_assault", "kind": "", "tip": "Full assault: every squadron attacks."},
	"orders/full_retreat": {"name": "Full retreat", "row": "order_full_retreat", "kind": "", "tip": "Full retreat: every squadron falls back."},
	"build/scout": {"name": "Scout", "row": "build_scout", "kind": "", "tip": ""},
	"build/fighter": {"name": "Fighter", "row": "build_fighter", "kind": "", "tip": ""},
	"build/lance": {"name": "Lance", "row": "build_lance", "kind": "", "tip": ""},
	"build/bomber": {"name": "Bomber", "row": "build_bomber", "kind": "", "tip": ""},
	"build/logistics": {"name": "Logistics", "row": "build_logistics", "kind": "", "tip": ""},
	"build/support": {"name": "Support", "row": "build_support", "kind": "", "tip": ""},
	"build/flak": {"name": "Flak", "row": "build_flak", "kind": "", "tip": ""},
	"build/ion": {"name": "Ion", "row": "build_ion", "kind": "", "tip": ""},
	"build/destroyer": {"name": "Destroyer", "row": "build_destroyer", "kind": "", "tip": ""},
	"build/battlecruiser": {"name": "Battlecruiser", "row": "build_battlecruiser", "kind": "", "tip": ""},
	"build/capitals": {"name": "Capitals", "row": "build_capitals", "kind": "", "tip": "Capital ships: opens the Destroyer and the Battlecruiser."},
	"build/drone": {"name": "Drone", "row": "build_drone", "kind": "", "tip": "Build a mining drone. It flies to the richest safe resource node and mines ore."},
	"build/size": {"name": "Size", "row": "", "kind": "", "tip": "Ships in a squadron (1 to 3): click to change. Small hulls only."},
	"build/repeat": {"name": "Repeat", "row": "", "kind": "", "tip": "Repeat: when a build of the hull you buy is done, the same item is queued again if the list and the fleet have room."},
	"base/research": {"name": "Research", "row": "base_research", "kind": "", "tip": "Open the research board."},
	"base/drone": {"name": "Drone", "row": "base_drone", "kind": "", "tip": "Build a mining drone."},
	"base/deputy": {"name": "Deputy", "row": "base_deputy", "kind": "", "tip": "The deputy comes with a later stage."},
	"base/deputy_preset": {"name": "Dep. mode", "row": "base_deputy_preset", "kind": "", "tip": "The deputy's preset comes with a later stage."},
	"base/turret": {"name": "Turret", "row": "base_turret", "kind": "", "tip": "Build a turret: click it, then click a resource node."},
	"base/torpedo": {"name": "Torpedo", "row": "base_torpedo", "kind": "", "tip": "Build a torpedo turret: click it, then click one of your inner turret sites."},
	"base/repair": {"name": "Repair bay", "row": "base_repair", "kind": "", "tip": "Send out a repair bay: click it, then click a spot."},
	"base/ward": {"name": "Ward", "row": "base_ward", "kind": "", "tip": "Place a ward: click it, then click a spot your team can see."},
	"base/waypoint": {"name": "Waypoint", "row": "base_waypoint", "kind": "", "tip": "Set the rally waypoint: click it, then click a spot."},
	"base/rally": {"name": "Rally", "row": "base_rally", "kind": "", "tip": "Choose where new ships gather: click it, then click a spot."},
	"base/move": {"name": "Move base", "row": "base_move", "kind": "", "tip": "Move the mothership: click it, then click a spot in a lane."},
	"base/cancel": {"name": "Undo last", "row": "base_cancel", "kind": "", "tip": "Cancel the newest item of the build list."},
	"base/production": {"name": "Panel", "row": "base_production", "kind": "", "tip": "Show or fold the production panel."},
	"base/hangar": {"name": "Hangar", "row": "hangar", "kind": "", "tip": "Open the hangar."},
	"base/defenses": {"name": "Defenses", "row": "", "kind": "", "tip": "Open the defense posts: their state and Rebuild."},
	"base/turret_list": {"name": "Turret list", "row": "", "kind": "", "tip": "Open the list of turrets at every node."},
	"base/ms_status": {"name": "Mothership", "row": "", "kind": "", "tip": "Open the mothership's status and warnings."},
	"base/doctrine": {"name": "Doctrine", "row": "", "kind": "", "tip": "Open the Fleet Doctrine card."},
}

## Layout B (and C): a 3x3 grid R T Y / F G H / V B N.
const LAYOUT_B := {
	"orders": {"cols": 3, "grid": ["attack_move", "patrol", "goal", "hold", "stop", "retreat", "stance", "formation", "merge"],
		"extra": ["move", "defend", "escort"], "more": ["position", "push_lane", "full_assault", "full_retreat"], "pop": []},
	"build": {"cols": 3, "grid": ["fighter", "lance", "bomber", "scout", "logistics", "support", "flak", "ion", "capitals"],
		"extra": ["drone", "size", "repeat"], "more": [], "pop": ["destroyer", "battlecruiser"]},
	"base": {"cols": 3, "grid": ["research", "drone", "deputy", "turret", "repair", "ward", "waypoint", "hangar", "move"],
		"extra": ["rally", "cancel", "production"], "more": ["deputy_preset", "torpedo", "defenses", "turret_list", "ms_status", "doctrine"], "pop": []},
}
## Layout A: the classic 4x3 grid Q W E R / A S D F / Z X C V (X is the pilot's order wheel: a blank place here).
const LAYOUT_A := {
	"orders": {"cols": 4, "grid": ["move", "hold", "patrol", "retreat", "attack_move", "stop", "defend", "escort", "stance", "", "push_lane", "merge"],
		"extra": ["goal", "formation", "position"], "more": ["full_assault", "full_retreat"], "pop": []},
	"build": {"cols": 4, "grid": ["scout", "fighter", "lance", "bomber", "logistics", "support", "flak", "ion", "destroyer", "", "battlecruiser", "drone"],
		"extra": ["capitals", "size", "repeat"], "more": [], "pop": ["destroyer", "battlecruiser"]},
	"base": {"cols": 4, "grid": ["turret", "torpedo", "repair", "ward", "move", "rally", "waypoint", "deputy", "deputy_preset", "", "cancel", "production"],
		"extra": ["research", "drone", "defenses"], "more": ["turret_list", "ms_status", "doctrine", "hangar"], "pop": []},
}


## The layout table for the home layout preset `preset` ("A", "B" or "C"): A has its own, B and C share B's cells.
static func layout_of(preset: String) -> Dictionary:
	return LAYOUT_A if preset == "A" else LAYOUT_B


## The place of page `page` for preset `preset`: {cols, grid, extra, more, pop}.
static func page(preset: String, page_id: String) -> Dictionary:
	return (layout_of(preset) as Dictionary)[page_id]


## The cell record of local id `id` on page `page_id` ({} for a blank place).
static func cell(page_id: String, id: String) -> Dictionary:
	return CELLS.get("%s/%s" % [page_id, id], {})


## Every local id the page shows for `preset`, in the order grid, extra, More, Capitals pop-out (blank places left out).
static func all_ids(preset: String, page_id: String) -> Array:
	var p := page(preset, page_id)
	var out: Array = []
	for list: Array in [p["grid"], p["extra"], p["more"], p["pop"]]:
		for id: String in list:
			if id != "":
				out.append(id)
	return out


## The key rows (home mode) with a `page` that have no cell on their page for preset `preset`, as "page/row" texts.
static func rows_without_cell(preset: String) -> Array:
	var out: Array = []
	for r: Dictionary in KeyMap.rows("home"):
		var pg := str(r["page"])
		if pg == "":
			continue
		var found := false
		for id: String in all_ids(preset, pg):
			if str(cell(pg, id).get("row", "")) == str(r["id"]):
				found = true
				break
		if not found:
			out.append("%s/%s" % [pg, r["id"]])
	return out
