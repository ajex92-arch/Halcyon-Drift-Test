class_name AlertList
extends RefCounted
## WHAT THIS IS: one team's ranked list of things worth a look: the mothership
## is under attack, a ship or turret was lost, an order was refused, a module or
## research finished. It is data only: no screen draws it yet, and nothing blinks.
##
## HOW IT WORKS: the event stream (RtsEvents) hands every record to on_event().
## A record that matches a kind in KINDS raises an alert: it gets that kind's
## priority (1 first), a lifetime in ticks and a merge key. A new record whose key
## matches an alert that is still alive does not add a row: it adds 1 to that
## alert's count and moves the alert to the new place, so ten ships lost in one
## fight are one line, "Ship lost x10". An area kind keys on the 2,000-unit square
## (CELL) the event is in. Each raise says whether it may make a sound
## (`voice`): the same merge key may not sound again inside its kind's interval,
## the same source (the unit that caused it) may not raise the same kind again
## within SOURCE_GAP ticks, and the whole list sounds at most once every
## GLOBAL_VOICE_GAP ticks. A capped sound keeps its text and its mark; only the
## sound is dropped. live(tick) hands back what is still alive, most important
## first, and moves the expired alerts into `recent` (the last 20). Time is
## counted in World ticks, never seconds. A kind in `mute` is not raised.
##
## WHO USES IT: World keeps two (World.alerts, index = team); RtsEvents.push() feeds them;
## a later screen reads live(), recent and jump_pos(); tests/order_check.gd checks it.

## The alert kinds. `priority`: 1 is the most important; `life`: ticks an alert
## lives after its last raise; `key`: what makes two events one alert ("team" =
## the kind and team only, "cell" = also the 2,000-unit square, "reason" = also
## the refusal's reason, "seat", "squad"); `gap`: ticks before the same key may
## sound again; `text`: the line a screen shows. Kinds nothing raises yet are
## listed too (structure_under_attack, cap_full, pilot_request, squadron_*).
const KINDS := {
	"mothership_under_attack": {"priority": 1, "life": 600, "key": "team", "gap": 900, "text": "Mothership under attack"},
	"squadron_under_attack": {"priority": 2, "life": 600, "key": "cell", "gap": 900, "text": "Squadron under attack"},
	"structure_under_attack": {"priority": 3, "life": 600, "key": "cell", "gap": 900, "text": "Structure under attack"},
	"ship_lost": {"priority": 4, "life": 1800, "key": "cell", "gap": 900, "text": "Ship lost"},
	"squadron_lost": {"priority": 4, "life": 1800, "key": "cell", "gap": 900, "text": "Squadron lost"},
	"turret_lost": {"priority": 4, "life": 1800, "key": "cell", "gap": 900, "text": "Turret lost"},
	"post_lost": {"priority": 4, "life": 1800, "key": "cell", "gap": 900, "text": "Defense post lost"},
	"order_refused": {"priority": 5, "life": 300, "key": "reason", "gap": 900, "text": "Order refused"},
	"cap_full": {"priority": 6, "life": 600, "key": "team", "gap": 1800, "text": "Fleet cap full"},
	"build_done": {"priority": 7, "life": 600, "key": "team", "gap": 900, "text": "Build finished"},
	"module_done": {"priority": 7, "life": 600, "key": "team", "gap": 900, "text": "Module finished"},
	"research_done": {"priority": 8, "life": 600, "key": "team", "gap": 900, "text": "Research finished"},
	"pilot_request": {"priority": 9, "life": 1200, "key": "seat", "gap": 900, "text": "Pilot request"},
	"squadron_idle": {"priority": 10, "life": 1800, "key": "squad", "gap": 1800, "text": "Squadron awaiting orders"},
}
## An order_refused alert for these reasons may sound only this often (ticks).
const REFUSAL_GAP := {"money": 1800, "room": 1800}
## The side (world units) of the square that area alerts merge in.
const CELL := 2000
## The fewest ticks between two sounds from the whole list (one a second).
const GLOBAL_VOICE_GAP := 60
## The fewest ticks before the same source may raise the same kind again (15 s).
const SOURCE_GAP := 900
## How many expired alerts `recent` keeps.
const RECENT_MAX := 20

## The team this list belongs to.
var team := 0
## Alert kinds the player switched off: kind -> true. A muted kind is not raised.
var mute := {}
## The last expired alerts, newest last (at most RECENT_MAX).
var recent: Array = []
## The alerts still alive, in the order they were first raised.
var _live: Array = []
## For each merge key: the tick of its last sound.
var _key_voice := {}
## For each source (kind and unit): the tick of its last raise.
var _source_raise := {}
## The tick of the last sound from this list (a long time ago at the start).
var _last_voice := -GLOBAL_VOICE_GAP


## A list for `t`'s team.
func _init(t: int) -> void:
	team = t


## Take one record of the event stream. Returns the alert it raised or merged into,
## with `voice` true when it may make a sound, or {} when the record is not an alert
## kind, is muted, or belongs to the other team.
func on_event(ev: Dictionary, tick: int) -> Dictionary:
	var evt_team := int(ev.get("team", -1))
	if evt_team >= 0 and evt_team != team:
		return {}
	var kind := _alert_kind(ev)
	if kind == "" or bool(mute.get(kind, false)):
		return {}
	var row: Dictionary = KINDS[kind]
	var pos = ev.get("pos", null)
	var data: Dictionary = ev.get("data", {})
	var key := _merge_key(kind, str(row["key"]), pos, data)
	# Merge into a live alert with the same key, else raise a new one.
	var alert: Dictionary = {}
	for a: Dictionary in _live:
		if a["key"] == key and int(a["expires"]) > tick:
			alert = a
			break
	if alert.is_empty():
		alert = {"kind": kind, "key": key, "priority": int(row["priority"]), "raised": tick, "count": 0, "pos": pos, "text": str(row["text"]), "voice": false, "expires": tick}
		_live.append(alert)
	alert["count"] = int(alert["count"]) + 1
	alert["expires"] = tick + int(row["life"])
	alert["pos"] = pos
	alert["text"] = str(row["text"]) + (" x%d" % int(alert["count"]) if int(alert["count"]) > 1 else "")
	alert["voice"] = _may_voice(kind, key, tick, int(ev.get("uid", 0)), data)
	return alert


## The alerts still alive at `tick`, the most important first (then the newest
## raised first). Expired ones move into `recent`.
func live(tick: int) -> Array:
	var keep: Array = []
	for a: Dictionary in _live:
		if int(a["expires"]) > tick:
			keep.append(a)
		else:
			recent.append(a)
			if recent.size() > RECENT_MAX:
				recent.pop_front()
	_live = keep
	var out := keep.duplicate()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["priority"]) != int(y["priority"]):
			return int(x["priority"]) < int(y["priority"])
		return int(x["raised"]) > int(y["raised"]))
	return out


## Where a click on the top alert should jump the view to, or null when nothing is
## alive or the alert has no place. A whole-number point.
func jump_pos(tick: int) -> Variant:
	var list := live(tick)
	if list.is_empty():
		return null
	return list[0]["pos"]


## The alert kind a stream record raises, or "" for none. A post that turned
## "destroyed" is a post_lost alert; the other kinds carry their own name.
func _alert_kind(ev: Dictionary) -> String:
	var kind := str(ev.get("kind", ""))
	if kind == "post_state":
		var state := str((ev.get("data", {}) as Dictionary).get("state", ""))
		return "post_lost" if state == PostSite.DESTROYED else ""
	return kind if KINDS.has(kind) else ""


## What makes two records one alert: the kind and team, plus (by the kind's `key`)
## the 2,000-unit square, the refusal's reason, the seat or the squadron.
func _merge_key(kind: String, how: String, pos, data: Dictionary) -> String:
	var key := "%s|%d" % [kind, team]
	match how:
		"cell":
			if pos is Vector2i:
				var p := pos as Vector2i
				key += "|%d,%d" % [floori(float(p.x) / float(CELL)), floori(float(p.y) / float(CELL))]
		"reason":
			key += "|" + str(data.get("reason", ""))
		"seat":
			key += "|" + str(data.get("seat", ""))
		"squad":
			key += "|" + str(data.get("squad", ""))
	return key


## May this raise make a sound? Not before the kind's gap since the same key last
## sounded, not before SOURCE_GAP since the same source raised the same kind, and
## not within GLOBAL_VOICE_GAP of any sound from this list. Notes the sound when it
## is allowed. A source of 0 (no unit) has no source gap.
func _may_voice(kind: String, key: String, tick: int, source: int, data: Dictionary) -> bool:
	var gap := int((KINDS[kind] as Dictionary)["gap"])
	if kind == "order_refused":
		gap = int(REFUSAL_GAP.get(str(data.get("reason", "")), gap))
	var source_key := "%s|%d" % [kind, source]
	var source_ok := source == 0 or tick - int(_source_raise.get(source_key, -SOURCE_GAP)) >= SOURCE_GAP
	if source != 0:
		_source_raise[source_key] = tick
	var key_ok := tick - int(_key_voice.get(key, -gap)) >= gap
	var global_ok := tick - _last_voice >= GLOBAL_VOICE_GAP
	if source_ok and key_ok and global_ok:
		_key_voice[key] = tick
		_last_voice = tick
		return true
	return false
