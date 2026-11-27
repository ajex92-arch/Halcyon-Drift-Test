class_name PilotLog
extends RefCounted
## WHAT THIS IS: the pilots' half of the computer Admirals' decision log (AdmiralLog). It writes one plain line
## each time a computer pilot changes its plan (turns back to repair, flies home to buy something, starts
## hunting, farming or clearing a camp) or switches to another target inside the same plan (one turret after
## another, one pilot after another). Each line says what the pilot chose, what it almost chose (or stayed on)
## and why, then a short tail for tools. Nothing is written unless the launch option --admiral-log=<file> is
## given, so a normal match pays one comparison per think and plays exactly the same.
##
## A line looks like this (the first is a first plan, the second a change of plan, the third a swap):
##   3:12 Aurelian pilot Vega (top lane) launches and attacks an enemy turret over hunting a pilot or farming minions: our minions are tanking it, and that comes before hunting or farming  [rule=pilot.push change=launch state=lane prev=none seat=0 team=0 t=192]
##   5:40 Vhorr pilot Rook (jungle) turns back to repair over staying out in the fight: its hull is down to 31%  [rule=pilot.hard change=plan state=retreat prev=camp seat=3 team=1 t=340]
##   6:02 Aurelian pilot Vega (top lane) switches to an enemy minion over staying on an enemy turret: its old target is gone  [rule=pilot.farm change=swap state=lane prev=farm seat=0 team=0 t=362]
##
## HOW IT WORKS: PilotAI calls watch() at the end of each of its thinks. watch() reads fields the brain already
## holds (its state, target, camp and timers: never a part of the brain, so no flag is set and no random number
## is drawn) and builds the pilot's "plan": the state and a mode (plan_of), plus the id of the target the plan
## acts on. A plan, or a target inside a plan, is written only after it has held PLAN_HOLD seconds of match
## time; a change that did not last is counted (AdmiralLog.pilot_held) and not written. The memory for each
## pilot lives in the log (AdmiralLog.pilot_plans), so a new match starts clean. words() turns a plan and the
## facts about the pilot into the three parts of the line (pure, so tests can call it on made-up facts).
## Only a seat pilot of a team with a computer Admiral whose decision_log is on is written.
##
## WHO USES IT: PilotAI.update() calls watch(); tests/bar7_log_check.gd checks it.

## How long (match seconds) a plan, and a target inside a plan, must hold before it is written. A pilot thinks
## every 0.23 to 0.35 seconds, so this skips the flicker of one think and keeps the changes that mean something.
const PLAN_HOLD := 2.0
## Every plan this file words ("state|mode"). A plan not in the list still gets a line, with a visible gap.
const PLANS := [
	"lane|station", "lane|push", "lane|prey", "lane|farm", "lane|fight", "lane|evade", "lane|fallback",
	"jungle|station", "jungle|camp", "jungle|fight", "jungle|push", "jungle|prey", "jungle|farm",
	"jungle|evade", "jungle|fallback",
	"retreat|hard", "retreat|soft",
	"home|hull", "home|gear", "home|recalled", "home|dock",
]
## The modes that act on a target (the plan key then also holds the target's id).
const TARGET_MODES := ["push", "prey", "farm", "fight", "camp"]
## The words for each role, as a player names the job.
const ROLE_WORDS := {"top": "top lane", "mid": "middle lane", "bot": "bottom lane", "jungle": "jungle", "flex": "flex"}


## Called by PilotAI at the end of each think: write this pilot's line when its plan or target changed and held
## long enough. `lg` is the log to write to (the match's own when none is given). With the log off this is one
## comparison.
static func watch(brain: PilotAI, ship: Ship, lg: AdmiralLog = null) -> void:
	if lg == null:
		lg = AdmiralLog.of(brain.world)
	if lg == null or not lg.enabled:
		return
	var profile := brain.profile
	if brain.world.pilot_ai.get(profile) != brain or not lg.wants(profile.team):
		return
	var plan := plan_of(brain, ship)
	var tid := _target_id(brain, plan)
	var now := brain.world.time
	var entry: Dictionary = lg.pilot_plans.get(profile, {})
	if entry.is_empty():
		entry = {"flight": brain.launched_at, "plan": "", "tid": 0, "tword": "", "has_cand": false, "cand_plan": "", "cand_tid": 0, "cand_t": 0.0}
		lg.pilot_plans[profile] = entry
	elif float(entry["flight"]) != brain.launched_at:
		# A new flight (a new ship): the next line is a "launches and" line again.
		if bool(entry["has_cand"]):
			lg.pilot_held += 1
		entry["flight"] = brain.launched_at
		entry["plan"] = ""
		entry["tid"] = 0
		entry["tword"] = ""
		entry["has_cand"] = false
	var written_plan := str(entry["plan"])
	var has_written := written_plan != ""
	if has_written and plan == written_plan and tid == int(entry["tid"]):
		# Back on what was written: a change that came and went inside the hold is only counted.
		if bool(entry["has_cand"]):
			lg.pilot_held += 1
			entry["has_cand"] = false
		return
	if not bool(entry["has_cand"]) or plan != str(entry["cand_plan"]) or tid != int(entry["cand_tid"]):
		if bool(entry["has_cand"]):
			lg.pilot_held += 1
		entry["has_cand"] = true
		entry["cand_plan"] = plan
		entry["cand_tid"] = tid
		entry["cand_t"] = now
		return
	if now - float(entry["cand_t"]) < PLAN_HOLD:
		return
	# It held: write it.
	var kind := "launch"
	if has_written:
		kind = "plan" if plan != written_plan else "swap"
	var facts := facts_of(brain, ship, entry)
	facts["first"] = kind == "launch"
	facts["swap"] = kind == "swap"
	var parts := words(plan, facts)
	var text := str(parts["chose"])
	if str(parts["over"]) != "":
		text += " over " + str(parts["over"])
	if str(parts["why"]) != "":
		text += ": " + str(parts["why"])
	lg.pilot(profile.team, who_of(brain), text, kind, {
		"rule": "pilot." + plan.get_slice("|", 1),
		"state": brain.state,
		"prev": written_plan.get_slice("|", 1) if has_written else "none",
		"seat": profile.slot,
	})
	entry["plan"] = plan
	entry["tid"] = tid
	entry["tword"] = str(facts["tword"])
	entry["has_cand"] = false


## The pilot's plan right now as "state|mode". The mode, for a lane or jungle pilot: evade (backing away from a
## turret), fallback (outnumbered and hurt), the reason it picked its target (push, prey, farm), fight (a target
## in range), camp (a jungler's camp) or station. For retreat: soft or hard. For home: recalled, hull or gear (what
## it flies home to buy) or dock.
static func plan_of(brain: PilotAI, _ship: Ship) -> String:
	var state := brain.state
	var mode := ""
	if state == "retreat":
		mode = "soft" if brain.soft_retreat else "hard"
	elif state == "home":
		var reason := brain.home_reason.get_slice(":", 0)
		if brain.recalled:
			mode = "recalled"
		elif reason == "hull" or reason == "gear":
			mode = reason
		else:
			mode = "dock"
	elif brain.evade_t > 0.0:
		mode = "evade"
	elif brain.fallback_t > 0.0:
		mode = "fallback"
	else:
		mode = _target_mode(brain)
	return state + "|" + mode


## The mode of a pilot that is neither retreating, flying home, evading nor falling back.
static func _target_mode(brain: PilotAI) -> String:
	var tgt: Variant = brain.target
	if tgt != null and is_instance_valid(tgt) and (tgt as Unit).alive:
		if brain.intent == "push" or brain.intent == "prey" or brain.intent == "farm":
			return brain.intent
		if brain.intent == "":
			return "fight"
	var camp: Variant = brain.camp
	if brain.state == "jungle" and camp != null and is_instance_valid(camp) and (camp as Unit).alive:
		return "camp"
	return "station"


## The id of the unit the plan acts on (0 when the plan acts on none).
static func _target_id(brain: PilotAI, plan: String) -> int:
	var mode := plan.get_slice("|", 1)
	var unit: Variant = null
	if mode == "camp":
		unit = brain.camp
	elif TARGET_MODES.has(mode):
		unit = brain.target
	if unit != null and is_instance_valid(unit):
		return (unit as Object).get_instance_id()
	return 0


## The plain words that name the pilot: "pilot <callsign> (<its job>)", or "Admiral's ship <callsign>".
static func who_of(brain: PilotAI) -> String:
	var profile := brain.profile
	if profile.role == "admiral":
		return "Admiral's ship %s" % profile.callsign
	return "pilot %s (%s)" % [profile.callsign, str(ROLE_WORDS.get(profile.role, profile.role))]


## The facts words() reads, from the brain's own fields: the hull and shield percentages, the labels of what it
## flies home to buy, the words for its target and for the target it last wrote (`entry`), and why that old one
## is no longer the target ("alive", "gone" or "hidden").
static func facts_of(brain: PilotAI, ship: Ship, entry: Dictionary) -> Dictionary:
	var facts := {
		"first": false, "swap": false, "hull_pct": roundi(ship.hull_frac() * 100.0), "total_pct": roundi(ship.total_frac() * 100.0),
		"hull_label": "", "gear_label": "", "tword": "an enemy ship", "old_tword": str(entry.get("tword", "")),
		"old_state": "alive", "mothership": false, "opening": not brain.opening_done,
	}
	var id := brain.home_reason.get_slice(":", 1)
	if Ships.HULLS.has(id):
		facts["hull_label"] = str((Ships.HULLS[id] as Dictionary).get("label", ""))
	if Items.ITEMS.has(id):
		facts["gear_label"] = str((Items.ITEMS[id] as Dictionary).get("label", ""))
	var mode := plan_of(brain, ship).get_slice("|", 1)
	var unit: Variant = null
	if mode == "camp":
		unit = brain.camp
	elif TARGET_MODES.has(mode):
		unit = brain.target
	if unit != null and is_instance_valid(unit):
		facts["tword"] = _target_words(unit as Unit)
		facts["mothership"] = (unit as Unit).kind == Unit.K_MOTHERSHIP
	var old_id := int(entry.get("tid", 0))
	if old_id != 0:
		var old: Variant = instance_from_id(old_id)
		if old == null or not (old is Unit) or not (old as Unit).alive:
			facts["old_state"] = "gone"
		elif brain.skip_id == old_id and brain.world.time < brain.skip_until:
			facts["old_state"] = "hidden"
	return facts


## The phrase for a target, with its article: "the enemy mothership", "an enemy Destroyer", "a derelict camp",
## "an enemy turret".
static func _target_words(unit: Unit) -> String:
	if unit.kind == Unit.K_MOTHERSHIP:
		return "the enemy mothership"
	if unit.kind == Unit.K_MONSTER:
		return "a derelict camp"
	if unit is Ship:
		var hull_id := (unit as Ship).hull_id
		if Ships.HULLS.has(hull_id):
			return "an enemy " + str((Ships.HULLS[hull_id] as Dictionary).get("label", "ship"))
		return "an enemy ship"
	if unit.kind >= 0 and unit.kind < Unit.KIND_NAMES.size():
		return "an enemy " + str(Unit.KIND_NAMES[unit.kind])
	return "an enemy unit"


## "a <label>" or "an <label>" by the label's first letter.
static func _with_article(label: String) -> String:
	if label != "" and label[0].to_lower() in ["a", "e", "i", "o", "u"]:
		return "an " + label
	return "a " + label


## The three parts of a line, as {"chose", "over", "why"}: what the pilot does, what it almost did (or stayed on)
## and why. `plan` is "state|mode"; `facts` is what facts_of() reads (the keys first, swap, hull_pct, total_pct,
## hull_label, gear_label, tword, old_tword, old_state, mothership and opening). A swap (the same plan, another
## target) has its own words; `first` puts "launches and" in front of what the pilot does. Pure: no random
## number, no world read.
static func words(plan: String, facts: Dictionary) -> Dictionary:
	var state := plan.get_slice("|", 0)
	var mode := plan.get_slice("|", 1)
	var tword := str(facts.get("tword", "an enemy ship"))
	var hull := int(facts.get("hull_pct", 0))
	var total := int(facts.get("total_pct", 0))
	var parts := {"chose": "changes its plan", "over": "keeping the old one", "why": "no reason is worded for " + plan}
	if bool(facts.get("swap", false)) and TARGET_MODES.has(mode):
		parts = _swap_words(mode, tword, facts)
	elif PLANS.has(plan):
		match mode:
			"hard":
				parts = {"chose": "turns back to repair", "over": "staying out in the fight", "why": "its hull is down to %d%%" % hull}
			"soft":
				parts = {"chose": "turns back", "over": "keeping on", "why": "its hull and shields together are down to %d%%" % total}
			"hull":
				var hl := str(facts.get("hull_label", ""))
				parts = {"chose": "flies home to buy " + (_with_article(hl) if hl != "" else "a new ship"), "over": "staying out in the fight", "why": "it can pay for it and the trip is worth it"}
			"gear":
				var gl := str(facts.get("gear_label", ""))
				parts = {"chose": "flies home to buy " + ("the " + gl if gl != "" else "new gear"), "over": "staying out in the fight", "why": "it can pay for it and the trip is worth it"}
			"recalled":
				parts = {"chose": "flies home", "over": "staying out on its trip", "why": "the Admiral called it back"}
			"dock":
				parts = {"chose": "flies home", "over": "staying out", "why": "no shopping reason was recorded"}
			"evade":
				parts = {"chose": "backs away from an enemy turret", "over": "staying on its target", "why": "the turret picked it as its target"}
			"fallback":
				parts = {"chose": "falls back toward its own side", "over": "pressing on", "why": "its hull is down to %d%% and it is outnumbered" % hull}
			"push":
				if bool(facts.get("mothership", false)):
					parts = {"chose": "attacks the enemy mothership", "over": "pushing a turret or hunting pilots", "why": "the assault has reached it"}
				else:
					parts = {"chose": "attacks " + tword, "over": "hunting a pilot or farming minions", "why": "our minions are tanking it, and that comes before hunting or farming"}
			"prey":
				parts = {"chose": "hunts " + tword, "over": "farming minions", "why": "the fight is fair and it is not hiding under a turret"}
			"farm":
				parts = {"chose": "flies out to shoot " + tword, "over": "holding its station", "why": "nothing else to shoot, no structure to push and no pilot worth hunting"}
			"fight":
				parts = {"chose": "fights " + tword, "over": "going on to its station or camp", "why": "it came into range"}
			"camp":
				parts = {"chose": "goes to clear " + tword, "over": "holding the lane", "why": "it picked the nearest camp"}
			"station":
				if state == "jungle":
					parts = {"chose": "waits in the jungle for a camp", "over": "going back to the lane", "why": "no camp is free right now"}
				elif bool(facts.get("opening", false)):
					parts = {"chose": "holds its opening spot", "over": "flying out to fight", "why": "the opening: it waits for the first wave to reach the lane"}
				else:
					parts = {"chose": "holds its station behind the wave", "over": "flying out to farm", "why": "nothing to push, hunt or farm in reach"}
	if bool(facts.get("first", false)):
		parts["chose"] = "launches and " + str(parts["chose"])
	return parts


## The words of a swap: the pilot keeps its plan and takes another target.
static func _swap_words(mode: String, tword: String, facts: Dictionary) -> Dictionary:
	var old_word := str(facts.get("old_tword", ""))
	var over := "staying on " + (old_word if old_word != "" else "the old one")
	var why := "the new one is the better pick"
	match str(facts.get("old_state", "alive")):
		"gone":
			why = "that camp is cleared" if mode == "camp" else "its old target is gone"
		"hidden":
			why = "it gave up on the old one behind the rocks"
	var chose := "goes to another derelict camp" if mode == "camp" else "switches to " + tword
	return {"chose": chose, "over": over, "why": why}
