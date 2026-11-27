class_name DeathRecap
extends RefCounted
## WHAT THIS IS: the hit log behind the death card. While the human has a ship it keeps a short list of the hits that ship took
## (who or what hit it, with which weapon, how much, and from which side). When the ship dies the list is frozen, and the card
## (HudDeathCard) reads the last 15 seconds of it: the total, the weapon mix, the side the hits came from, how much the shields
## and armour stopped and who the attackers were.
##
## HOW IT WORKS: it listens to Events.damage_applied, which Combat sends only while Combat.emit_damage_events is true, so setup()
## turns that on (and stop() puts the old value back); nothing else in the match changes. Only hits on the human's own ship are
## kept (a computer pilot's death is never logged). Every entry is a Dictionary with plain copies, because the attacking unit may
## be freed a moment later: "t" (match time), "uid", "key" (the line it belongs to on the Attackers page), "label", "kind" (the
## attacker's unit kind), "team", "pilot", "seen" (could the human's team see the attacker when it hit), "wkind" (the weapon kind,
## Rules.W_*), "family" (one of the F_* numbers), "amount" and "hull" (what the hit did to the shields and hull together and to the
## hull alone) and "zones" (the amount by shield zone: front, rear, left, right). Hits from one attacker with one weapon family
## less than MERGE_S apart become one entry, and the list holds LOG_MAX entries (the oldest go first). The side of a hit is read the
## way Unit.take_hit() reads it (ShieldZones.zone_for_local of the attacker's place in the ship's own frame). The weapon families:
## Guns (bolt, flak, point defense and the pure damage of features), Lance, Torpedoes, Shells, Ion and Crash.
## When the human's ship is destroyed (Events.unit_killed) the list freezes and `death` keeps the facts of the kill: who landed the
## killing blow, with what, and which pilots Economy paid an assist (the same call the payment uses, so the card and the money
## agree). The frozen list stays until the human has a live ship again (reset(), called by the card), so the card can be read
## through the docked time. It reads the match and never writes it: no Unit, Ship, World or Combat field is changed, no random
## number is drawn and no input is read.
## Each entry also keeps what the shield rules did to its hits ("pierced", "full" and "bare") and `death` keeps two facts about the
## dying ship ("aggro_age" and "strain_s"); summary() adds them up and rule_note() turns them into the one line the card shows for
## the rule that mattered (a shield pierce, the ion rule, the aggro window or respawn strain), or none.
##
## WHO USES IT: HudDeathCard makes one when the HUD is set up and reads recent(), summary() and the `death` facts; tests/death_recap_check.gd
## checks it.

## Hits from one attacker with one weapon family closer together than this (seconds of match time) are one entry.
const MERGE_S := 0.25
## The most entries the list keeps; the oldest are dropped.
const LOG_MAX := 128
## The family of guns: bolts, flak, point defense and pure damage.
const F_GUNS := 0
## The family of lance beams.
const F_LANCE := 1
## The family of torpedoes.
const F_TORP := 2
## The family of shells.
const F_SHELL := 3
## The family of ion hits.
const F_ION := 4
## The family of crashes into an asteroid.
const F_CRASH := 5
## How many families there are.
const FAMILIES := 6
## The family names, in family order.
const FAMILY_NAMES := ["Guns", "Lance", "Torpedoes", "Shells", "Ion", "Crash"]
## The one letter that marks each family where colour is not enough, in family order.
const FAMILY_TAGS := ["G", "L", "T", "S", "I", "C"]
## The shield zone names, in zone order (Rules.ZONE_FRONT ... ZONE_RIGHT).
const ZONE_NAMES := ["front", "rear", "left", "right"]
## The shield focus names, in focus order (Rules.FOCUS_BALANCED ... FOCUS_RIGHT).
const FOCUS_NAMES := ["balanced", "front", "rear", "left", "right"]
## The least share of the window's damage that was pierce damage for the pierce rule to count as the rule that mattered (0 to 1).
const PIERCE_MIN_SHARE := 0.25
## The least share of the window's damage that was ion damage for the ion rule to count as the rule that mattered (0 to 1).
const ION_MIN_SHARE := 0.25
## The order rule_note() tests the rules in: the first one that holds is the line.
const RULE_ORDER := ["pierce", "ion", "aggro", "strain"]
## PLACEHOLDER: the words of the rule line, the one table of them (the final words are the designer's call). The aggro words take
## the seconds of the turret aggro window; the strain words take the mothership's gun percent and the seconds of strain left.
const RULE_WORDS := {
	"pierce_full": "This shot ignores shields",
	"pierce_part": "Part of this shot skips your shields",
	"ion": "Ion: drains shields only, your hull is safe",
	"ion_bare": "Ion does nothing without a shield",
	"aggro": "Turrets and minions target a ship that hurts a ship for %d s",
	"strain": "Strain: mothership guns at %d%% speed, its shield does not refill for %d s",
}

## The match this log belongs to (set by setup()).
var world: World
## The live list of entries (see HOW IT WORKS), oldest first.
var entries: Array = []
## True once the human's ship died and the list is frozen, until reset().
var frozen := false
## The facts of the kill that froze the list: "t" (match time), "uid" (the ship's), "killer" (describe() of the killing blow),
## "wkind" (its weapon kind), "paid" (a Dictionary of attacker key -> true for every pilot Economy paid an assist), "focus" (the
## ship's shield focus), "hull" (its hull's label), "aggro_age" (seconds since the ship last hurt an enemy ship, which is what makes
## turrets and minions pick it) and "strain_s" (the seconds of respawn strain its team had left). Empty while the list is live.
var death := {}
## True while setup() has turned Combat's damage events on and stop() has not yet put them back.
var listening := false
## Combat's emit_damage_events as it was before setup() (put back by stop()).
var _was_emitting := false


## Start listening for the human's hits, when the human has a ship seat (a pilot or an Admiral) and the match draws (not --sim-only).
## Turns Combat's damage events on and remembers the old value. Returns whether it listens.
func setup(w: World) -> bool:
	world = w
	if listening or w == null or w.human == null or Game.sim_only or w.combat == null:
		return listening
	if w.human_role != "pilot" and w.human_role != "admiral":
		return false
	_was_emitting = w.combat.emit_damage_events
	w.combat.emit_damage_events = true
	Events.damage_applied.connect(_on_damage)
	Events.unit_killed.connect(_on_killed)
	listening = true
	return true


## Stop listening and put Combat's damage events back as they were before setup().
func stop() -> void:
	if not listening:
		return
	listening = false
	if Events.damage_applied.is_connected(_on_damage):
		Events.damage_applied.disconnect(_on_damage)
	if Events.unit_killed.is_connected(_on_killed):
		Events.unit_killed.disconnect(_on_killed)
	if world != null and world.combat != null:
		world.combat.emit_damage_events = _was_emitting


## Forget the list and the facts of the last death (the human has a ship again).
func reset() -> void:
	entries.clear()
	death = {}
	frozen = false


## The weapon family (an F_* number) of weapon kind `kind` (Rules.W_*).
static func family_of(kind: int) -> int:
	match kind:
		Rules.W_LANCE:
			return F_LANCE
		Rules.W_TORP:
			return F_TORP
		Rules.W_SHELL:
			return F_SHELL
		Rules.W_ION:
			return F_ION
		Rules.W_COLLISION:
			return F_CRASH
	return F_GUNS


## The colour of family `f` on the card's bar (all from Palette; the letter marks it too, so colour is never the only sign).
static func family_colour(f: int) -> Color:
	match f:
		F_LANCE:
			return Palette.VEIL
		F_TORP:
			return Palette.ORE
		F_SHELL:
			return Palette.MIST
		F_ION:
			return Palette.SHIELD
		F_CRASH:
			return Palette.NEUTRAL
	return Palette.ICE


## The words for the weapon of the killing blow of weapon kind `kind` ("lance beam", "torpedo", "guns").
static func weapon_words(kind: int) -> String:
	match kind:
		Rules.W_LANCE:
			return "lance beam"
		Rules.W_TORP:
			return "torpedo"
		Rules.W_FLAK:
			return "flak"
		Rules.W_PD:
			return "point defense"
		Rules.W_SHELL:
			return "shell"
		Rules.W_ION:
			return "ion"
		Rules.W_COLLISION:
			return "collision"
		Rules.W_PURE:
			return "raw damage"
	return "guns"


## The words for the shield focus number `focus` ("front", "balanced").
static func focus_words(focus: int) -> String:
	return String(FOCUS_NAMES[clampi(focus, 0, FOCUS_NAMES.size() - 1)])


## The team's display name for `team` (Rules.TEAM_DISPLAY), or "Scum" for anything else.
static func team_word(team: int) -> String:
	if team >= 0 and team < Rules.TEAM_DISPLAY.size():
		return String(Rules.TEAM_DISPLAY[team])
	return "Scum"


## The one rule that mattered in a death, for summary `s` (see summary()) and the facts of the death `death` (see `death`): the rules
## are tried in RULE_ORDER and the first that holds wins. Returns {"rule": its id ("pierce", "ion", "aggro" or "strain"), "text": its
## words from RULE_WORDS with the numbers filled in}, or {"rule": "", "text": ""} when none holds. The pierce rule holds when
## PIERCE_MIN_SHARE of the damage went past the shield (the words say the whole shot did when at least half of it was a full pierce),
## the ion rule when ION_MIN_SHARE of it was ion (the bare words when at least half of that hit a ship with no shield), the aggro
## rule when turrets or minions hit the ship in its last TurretData.AGGRO_WINDOW seconds and it had hurt a ship that recently, and
## the strain rule when the team's respawn strain was still running at the death. Reads only its two arguments.
static func rule_note(s: Dictionary, death: Dictionary) -> Dictionary:
	var total := float(s.get("total", 0.0))
	for id: String in RULE_ORDER:
		match id:
			"pierce":
				var pierced := float(s.get("pierced", 0.0))
				if total > 0.0 and pierced / total >= PIERCE_MIN_SHARE:
					var key := "pierce_full" if float(s.get("pierce_full", 0.0)) * 2.0 >= pierced else "pierce_part"
					return {"rule": "pierce", "text": String(RULE_WORDS[key])}
			"ion":
				var ion := float(s.get("ion", 0.0))
				if total > 0.0 and ion / total >= ION_MIN_SHARE:
					var key := "ion_bare" if float(s.get("ion_bare", 0.0)) * 2.0 >= ion else "ion"
					return {"rule": "ion", "text": String(RULE_WORDS[key])}
			"aggro":
				if float(s.get("late_defence", 0.0)) > 0.0 and float(death.get("aggro_age", 999.0)) <= TurretData.AGGRO_WINDOW:
					return {"rule": "aggro", "text": String(RULE_WORDS["aggro"]) % int(TurretData.AGGRO_WINDOW)}
			"strain":
				var left := float(death.get("strain_s", 0.0))
				if left > 0.0:
					return {"rule": "strain", "text": String(RULE_WORDS["strain"]) % [roundi(Rules.STRAIN_WEAPON_MULT * 100.0), int(ceil(left))]}
	return {"rule": "", "text": ""}


## Describe the attacker of hit `d` with plain copies (the attacker may be gone later): "key" (what groups it on the Attackers page:
## one line for each pilot, one for all minions of a team, one for all turrets of a team, one for the Scum and the derelicts),
## "label" (its words), "kind" (its unit kind, -1 for none), "team", "pilot" (a pilot's ship) and "seen" (could `viewer_team` see
## it now; a hit with no attacker counts as seen). Reads only; call it while d.source is still valid.
static func describe(d: DamageInfo, viewer_team: int) -> Dictionary:
	var out := {"key": "none", "label": "Something else", "kind": -1, "team": Rules.NEUTRAL, "pilot": false, "seen": true}
	var s: Unit = d.source if d.source != null and is_instance_valid(d.source) else null
	var prof := d.source_profile as PilotProfile
	if s != null:
		out["kind"] = s.kind
		out["team"] = s.team
		out["seen"] = s.visible_to(viewer_team)
	if prof != null and not prof.is_crew:
		var hull := ""
		if s is Ship and Ships.HULLS.has((s as Ship).hull_id):
			hull = String(Ships.HULLS[(s as Ship).hull_id]["label"])
		out["key"] = "p:" + prof.callsign
		out["label"] = prof.callsign if hull == "" else "%s · %s" % [prof.callsign, hull]
		out["pilot"] = true
		out["team"] = prof.team
		return out
	if s == null:
		if d.kind == Rules.W_COLLISION:
			out["key"] = "crash"
			out["label"] = "An asteroid"
		return out
	if s.team == Rules.NEUTRAL:
		out["key"] = "n"
		out["label"] = "Scum and derelicts"
		return out
	var tn := team_word(s.team)
	match s.kind:
		Unit.K_SHIP:
			out["key"] = "c:%d" % s.team
			out["label"] = "%s crew ship" % tn
		Unit.K_MINION:
			out["key"] = "m:%d" % s.team
			out["label"] = "%s minions" % tn
		Unit.K_TURRET, Unit.K_POST:
			out["key"] = "t:%d" % s.team
			out["label"] = "%s turret" % tn
		Unit.K_MOTHERSHIP:
			out["key"] = "ms:%d" % s.team
			out["label"] = "the %s mothership" % tn
		_:
			out["key"] = "k:%d:%d" % [s.kind, s.team]
			out["label"] = "%s %s" % [tn, String(Unit.KIND_NAMES[s.kind])]
	return out


## One hit on a unit reached Combat's signal: keep it when it hit the human's own ship and the list is live.
func _on_damage(target: Node, info: RefCounted, amount: float, hull_dmg: float) -> void:
	var h := world.human
	var u := target as Unit
	if h == null or u == null or u.kind != Unit.K_SHIP or (u as Ship).profile != h:
		return
	var d := info as DamageInfo
	if d == null:
		return
	if frozen:
		# A hit on a new ship of the human's: the old death is over (it launched), so start again.
		if u.uid == int(death.get("uid", -1)):
			return
		reset()
	var now := world.time
	var who := describe(d, world.human_team)
	var fam := family_of(d.kind)
	# The zone this hit lands on, read the way Unit.take_hit() reads it. A crash has no side.
	var zone := -1
	if fam != F_CRASH:
		zone = ShieldZones.zone_for_local((d.from_pos - u.global_position).rotated(-u.rotation))
	# What the shield rules did to this hit, read the way Unit.take_hit() reads it: a hit on a shielded ship sends its `pierce` share past
	# the shield (all of it at 1), an ion hit is never pierce damage, and an ion hit on a ship with no shield does nothing at all.
	var shielded := (u as Ship).shields != null and (u as Ship).shields.max_total > 0.0
	var pierced := amount * d.pierce if shielded and d.kind != Rules.W_ION else 0.0
	var full := amount if shielded and d.kind != Rules.W_ION and d.pierce >= 1.0 else 0.0
	var bare := amount if d.kind == Rules.W_ION and not shielded else 0.0
	# Hits from one attacker with one weapon family within MERGE_S are one entry.
	var i := entries.size() - 1
	while i >= 0 and now - float(entries[i]["t"]) <= MERGE_S:
		var e: Dictionary = entries[i]
		if int(e["uid"]) == d.source_uid and int(e["family"]) == fam and String(e["key"]) == String(who["key"]):
			e["t"] = now
			e["amount"] = float(e["amount"]) + amount
			e["hull"] = float(e["hull"]) + hull_dmg
			e["pierced"] = float(e.get("pierced", 0.0)) + pierced
			e["full"] = float(e.get("full", 0.0)) + full
			e["bare"] = float(e.get("bare", 0.0)) + bare
			e["seen"] = bool(e["seen"]) or bool(who["seen"])
			if zone >= 0:
				e["zones"][zone] = float(e["zones"][zone]) + amount
			return
		i -= 1
	var zones := [0.0, 0.0, 0.0, 0.0]
	if zone >= 0:
		zones[zone] = amount
	entries.append({"t": now, "uid": d.source_uid, "key": who["key"], "label": who["label"], "kind": who["kind"], "team": who["team"],
			"pilot": who["pilot"], "seen": who["seen"], "wkind": d.kind, "family": fam, "amount": amount, "hull": hull_dmg, "zones": zones,
			"pierced": pierced, "full": full, "bare": bare})
	while entries.size() > LOG_MAX:
		entries.pop_front()


## Something died: when it is the human's ship, freeze the list and keep the facts of the kill.
func _on_killed(unit: Node, info: RefCounted) -> void:
	var h := world.human
	var u := unit as Ship
	if h == null or u == null or u.kind != Unit.K_SHIP or u.profile != h or frozen:
		return
	var d := info as DamageInfo
	var killer := describe(d, world.human_team) if d != null else describe(DamageInfo.new(), world.human_team)
	killer["seen"] = true
	var paid := {}
	var killer_prof: PilotProfile = d.source_profile as PilotProfile if d != null else null
	var window := float(Rules.tune("assist_window", Rules.ASSIST_WINDOW))
	var who := Economy.contributors(world, u, window, float(Rules.tune("assist_min_fraction", Rules.ASSIST_MIN_FRACTION)))
	for p: PilotProfile in who:
		if p != killer_prof and p.team != u.team:
			paid["p:" + p.callsign] = true
	var hull := String(Ships.HULLS[u.hull_id]["label"]) if Ships.HULLS.has(u.hull_id) else ""
	# The seconds of respawn strain the human's team has left, read once (0 when there is no such team).
	var strain := 0.0
	if world.human_team >= 0 and world.human_team < world.teams.size():
		strain = float(world.teams[world.human_team].strain_t)
	death = {"t": world.time, "uid": u.uid, "killer": killer, "wkind": d.kind if d != null else Rules.W_BOLT, "paid": paid,
			"focus": u.shields.focus if u.shields != null else Rules.FOCUS_BALANCED, "hull": hull,
			"aggro_age": world.time - u.aggro_time, "strain_s": strain}
	frozen = true


## The entries of the last `window` seconds before the death (or before now while the list is live), oldest first.
func recent() -> Array:
	var window := float(Rules.tune("assist_window", Rules.ASSIST_WINDOW))
	var ref := float(death["t"]) if frozen else world.time
	var out: Array = []
	for e: Dictionary in entries:
		if float(e["t"]) >= ref - window:
			out.append(e)
	return out


## The numbers the card shows, worked out from recent(): "total" (all damage), "hull" (what reached the hull), "ion" (the ion
## part of the total), "count" (entries), "span" (seconds from the first of those hits to the death), "fam" (the amount of each
## family), "fam_share" (each family's share, adding up to 1), "zone" and "zone_share" (the same by side: front, rear, left, right;
## a crash has no side), "stopped" (the share the shields and armour stopped, 0 to 1, of the non-ion damage; -1 when there is none),
## and "groups" (the Attackers page: one Dictionary per line, largest first, each with "key", "label", "team", "pilot", "amount",
## "share", "mask" (the families it used, as bits), "count" (how many different attackers), "killer" and "paid"). It also holds the
## sums rule_note() reads: "pierced" (damage that went past a shield), "pierce_full" (the part of it that was a full pierce),
## "ion_bare" (ion damage on a ship with no shield) and "late_defence" (damage from turrets, defense posts and minions in the last
## TurretData.AGGRO_WINDOW seconds before the death). Empty when no hit is in the window.
func summary() -> Dictionary:
	var list := recent()
	var out := {"total": 0.0, "hull": 0.0, "ion": 0.0, "count": list.size(), "span": 0.0, "fam": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
			"fam_share": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "zone": [0.0, 0.0, 0.0, 0.0], "zone_share": [0.0, 0.0, 0.0, 0.0],
			"stopped": -1.0, "groups": [], "pierced": 0.0, "pierce_full": 0.0, "ion_bare": 0.0, "late_defence": 0.0}
	if list.is_empty():
		return out
	var ref := float(death["t"]) if frozen else world.time
	var first := ref
	var total := 0.0
	var hull := 0.0
	var non_ion := 0.0
	var non_ion_hull := 0.0
	var zone_total := 0.0
	var fam: Array = out["fam"]
	var zone: Array = out["zone"]
	var groups := {}
	var killer_key := String(death.get("killer", {}).get("key", "")) if frozen else ""
	var paid: Dictionary = death.get("paid", {}) if frozen else {}
	for e: Dictionary in list:
		var amt := float(e["amount"])
		var f := int(e["family"])
		total += amt
		hull += float(e["hull"])
		out["pierced"] = float(out["pierced"]) + float(e.get("pierced", 0.0))
		out["pierce_full"] = float(out["pierce_full"]) + float(e.get("full", 0.0))
		out["ion_bare"] = float(out["ion_bare"]) + float(e.get("bare", 0.0))
		var attacker := int(e.get("kind", -1))
		if float(e["t"]) >= ref - TurretData.AGGRO_WINDOW and (attacker == Unit.K_TURRET or attacker == Unit.K_POST or attacker == Unit.K_MINION):
			out["late_defence"] = float(out["late_defence"]) + amt
		fam[f] = float(fam[f]) + amt
		first = minf(first, float(e["t"]))
		if f == F_ION:
			out["ion"] = float(out["ion"]) + amt
		else:
			non_ion += amt
			non_ion_hull += float(e["hull"])
		for z in 4:
			zone[z] = float(zone[z]) + float(e["zones"][z])
			zone_total += float(e["zones"][z])
		var key := String(e["key"])
		if not groups.has(key):
			groups[key] = {"key": key, "label": String(e["label"]), "team": int(e["team"]), "pilot": bool(e["pilot"]), "amount": 0.0, "share": 0.0,
					"mask": 0, "uids": {}, "count": 0, "killer": key == killer_key, "paid": paid.has(key), "seen": false}
		var g: Dictionary = groups[key]
		g["amount"] = float(g["amount"]) + amt
		g["mask"] = int(g["mask"]) | (1 << f)
		g["uids"][int(e["uid"])] = true
		g["seen"] = bool(g["seen"]) or bool(e["seen"])
	out["total"] = total
	out["hull"] = hull
	out["span"] = maxf(0.0, ref - first)
	if total > 0.0:
		var shares: Array = out["fam_share"]
		for f in FAMILIES:
			shares[f] = float(fam[f]) / total
	if zone_total > 0.0:
		var zs: Array = out["zone_share"]
		for z in 4:
			zs[z] = float(zone[z]) / zone_total
	if non_ion > 0.0:
		out["stopped"] = clampf(1.0 - non_ion_hull / non_ion, 0.0, 1.0)
	out["groups"] = _lines(groups, total)
	return out


## The Attackers page's lines from the grouped attackers `groups` (key -> group) of a window with `total` damage: largest first,
## at most four; with more, the killer's line is always kept and the rest are one "others" line. Each line's "count" is how many
## different attackers it holds, an unseen attacker (not the killer) is named only "an unseen attacker", and shares add up to 1.
func _lines(groups: Dictionary, total: float) -> Array:
	var list: Array = []
	for key: String in groups:
		var g: Dictionary = groups[key]
		g["count"] = (g["uids"] as Dictionary).size()
		g["share"] = float(g["amount"]) / total if total > 0.0 else 0.0
		if not bool(g["seen"]) and not bool(g["killer"]):
			g["label"] = "an unseen attacker"
		elif int(g["count"]) > 1 and not bool(g["pilot"]):
			g["label"] = "%s x%d" % [g["label"], int(g["count"])]
		list.append(g)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["amount"]), float(b["amount"])):
			return String(a["key"]) < String(b["key"])
		return float(a["amount"]) > float(b["amount"]))
	if list.size() <= 4:
		return list
	var keep: Array = list.slice(0, 3)
	var rest: Array = list.slice(3)
	var has_killer := false
	for g: Dictionary in keep:
		has_killer = has_killer or bool(g["killer"])
	if not has_killer:
		for i in range(rest.size()):
			if bool(rest[i]["killer"]):
				var swap: Dictionary = keep[2]
				keep[2] = rest[i]
				rest[i] = swap
				break
	var other := {"key": "others", "label": "", "team": Rules.NEUTRAL, "pilot": false, "amount": 0.0, "share": 0.0, "mask": 0, "count": 0,
			"killer": false, "paid": false, "seen": true}
	for g: Dictionary in rest:
		other["amount"] = float(other["amount"]) + float(g["amount"])
		other["mask"] = int(other["mask"]) | int(g["mask"])
		other["count"] = int(other["count"]) + int(g["count"])
	other["label"] = "%d others" % rest.size()
	other["share"] = float(other["amount"]) / total if total > 0.0 else 0.0
	keep.append(other)
	return keep
