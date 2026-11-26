class_name Groups
extends RefCounted
## WHAT THIS IS: the Admiral's eight control groups (E1, "Your groups"): F1 to F8 select a group, Ctrl+F<n> sets it to the
## selection, Shift+F<n> adds the selection to it, and a second tap within RtsUiCalls.GROUP_DOUBLE_TAP_S centres the camera on
## it. With RtsUiCalls.GROUP_ONE_PER_SQUAD (on) a squadron is in one group at a time: setting it into a group takes it out
## of its old one. It also holds the auto-join choices: for each hull the group that a newly built squadron of that hull
## joins ("New Fighter join F2"), kept in the settings file's [rts_ui] section (RtsUiStore).
##
## HOW IT WORKS: a plain object the command view makes once, so groups survive Tab, docking and launching. A group is a
## list of squad ids; members() filters it to the squadrons still alive. Everything is screen state: the groups are never
## read by the simulation, and orders still name squadrons by id. sync() runs on the view's 4 Hz beat: the first call
## only notes the squadrons that exist, every later call finds the squadrons that appeared since (a newly built
## squadron is selectable from the moment its ships exist) and puts each one into its hull's join group. That only
## writes a group number here: it gives no order and draws no random number. key() decodes a key press by the key map
## (rows group_1 to group_8 of the "shared" mode, so a rebind is followed) and does what the keys above say; pick()
## selects without moving the camera (what RT7's wheel and the flying case need), tap() adds the double tap (it centres the camera
## where the camera may move, and always emits double_tapped, which the minimap turns into a flash ring in field mode).
##
## WHO USES IT: CommandView (owns it, calls key() and sync()), ArmyCards (the cards), SelectionPanel (the F badges),
## ProductionPanel (the join row); tests/rts_groups_check.gd, rts_join_check.gd.

## Some group's members changed (the screens read the data on their own beat; this is for RT7).
signal changed
## Group `n` (which has living squadrons) was tapped twice inside RtsUiCalls.GROUP_DOUBLE_TAP_S, whether or not the camera may
## centre on it (the minimap draws its flash ring in field mode).
signal double_tapped(n: int)

## How many groups there are.
const COUNT := 8

## The group the last pick or tap named (0 for none; RT7's wheel reads it, 0 meaning every squadron).
var current := 0
## Where the joins are saved ("" is Game.SETTINGS_FILE); a test points this at a file of its own before it changes a join.
var store_path := ""
## The auto-join choices: {hull id -> group 1 to COUNT}.
var join := {}
## The match, the Admiral's team and the map layer (set by setup()).
var world: World
var team := 0
var overlay: CommandOverlay
## A time in milliseconds a test sets in place of the clock (-1: use the clock).
var fake_ms := -1
## The squad ids of each group: {1..COUNT -> Array[int]}.
var _members := {}
## The squadrons seen by sync(), and whether the first look was made.
var _known := {}
var _primed := false
## The last tap: which group and when (milliseconds).
var _tap_n := 0
var _tap_ms := -1000000


## Remember the match and read the remembered joins (from `path`, "" for the settings file). CommandView calls this once.
func setup(w: World, ov: CommandOverlay, t: int, path: String = "") -> void:
	world = w
	overlay = ov
	team = t
	store_path = path
	join = RtsUiStore.load_joins(path)
	var empty: Array[int] = []
	for n in range(1, COUNT + 1):
		_members[n] = empty.duplicate()


## The living squadron ids of group `n`, in the order they were put in.
func members(n: int) -> Array[int]:
	var list: Array[int] = []
	if _members.has(n):
		list.assign(_members[n])
	return RtsSelect.live_ids(world, team, list)


## The group squadron `id` is in (the lowest when several), 0 for none.
func group_of(id: int) -> int:
	for n in range(1, COUNT + 1):
		if (_members[n] as Array).has(id):
			return n
	return 0


## The first group with no living member, 0 when all eight are used (the "F5 + save" card names it).
func first_free() -> int:
	for n in range(1, COUNT + 1):
		if members(n).is_empty():
			return n
	return 0


## Set group `n` to squadrons `ids` (they leave their old groups when one group per squadron is the call).
func set_group(n: int, ids: Array[int]) -> void:
	if RtsUiCalls.GROUP_ONE_PER_SQUAD:
		_take_out(ids)
	_members[n] = ids.duplicate()
	changed.emit()


## Add squadrons `ids` to group `n` (they leave their old groups when one group per squadron is the call).
func add_group(n: int, ids: Array[int]) -> void:
	if RtsUiCalls.GROUP_ONE_PER_SQUAD:
		_take_out(ids)
	for id: int in ids:
		if not (_members[n] as Array).has(id):
			(_members[n] as Array).append(id)
	changed.emit()


## Take squadrons `ids` out of every group.
func _take_out(ids: Array[int]) -> void:
	for n in range(1, COUNT + 1):
		var list: Array = _members[n]
		for id: int in ids:
			list.erase(id)


## Ctrl+F<n> (and the "F_ + save" card): set group `n` to the selected squadrons. False (with a word on the card's result line)
## when no squadron is selected.
func set_from_selection(n: int) -> bool:
	var ids := _selected()
	if ids.is_empty():
		overlay.say("Select squadrons first, then set group %d." % n, false)
		return false
	set_group(n, ids)
	overlay.say("Group %d set: %s." % [n, RtsSquadOrders.squads_word(ids.size())], true)
	return true


## Shift+F<n>: add the selected squadrons to group `n`.
func add_from_selection(n: int) -> bool:
	var ids := _selected()
	if ids.is_empty():
		overlay.say("Select squadrons first, then add them to group %d." % n, false)
		return false
	add_group(n, ids)
	overlay.say("Added to group %d: %s." % [n, RtsSquadOrders.squads_word(ids.size())], true)
	return true


## The card detail's "Remove selection": take the selected squadrons out of group `n`. False (with a word on the card's
## result line) when none of them is in it.
func remove_from_selection(n: int) -> bool:
	var list: Array = _members[n]
	var took := 0
	for id: int in _selected():
		if list.has(id):
			list.erase(id)
			took += 1
	if took == 0:
		overlay.say("None of the selection is in group %d." % n, false)
		return false
	changed.emit()
	overlay.say("Removed from group %d: %s." % [n, RtsSquadOrders.squads_word(took)], true)
	return true


## The selected squadrons that are still alive.
func _selected() -> Array[int]:
	return RtsSelect.live_ids(world, team, overlay.sel_squads)


## F<n>: select group `n` without moving the camera (the Add toggle adds instead of replacing). False when it is empty.
func pick(n: int) -> bool:
	var ids := members(n)
	if ids.is_empty():
		overlay.say("Group %d is empty." % n, false)
		return false
	overlay.set_selection(ids, false, overlay.add_mode)
	current = n
	return true


## Put the camera on the middle of group `n`'s squadrons. False when it is empty.
func centre(n: int) -> bool:
	var ids := members(n)
	if ids.is_empty():
		return false
	var sum := Vector2.ZERO
	for id: int in ids:
		sum +=RtsSelect.centre_of(world, world.squads[id])
	centre_on(world, sum / float(ids.size()))
	return true


## F<n> pressed or clicked: select group `n`; a second one within GROUP_DOUBLE_TAP_S of the first also centres the camera
## when `may_centre` (docked, or the board open), and in every case emits double_tapped(n) (RT7: the minimap flashes the group
## in field mode, where the camera stays on the ship). Returns false when the group is empty.
func tap(n: int, may_centre: bool = true) -> bool:
	var now := _now()
	var again := _tap_n == n and now - _tap_ms <= int(RtsUiCalls.GROUP_DOUBLE_TAP_S * 1000.0)
	_tap_n = 0 if again else n
	_tap_ms = now
	if not pick(n):
		return false
	if again:
		double_tapped.emit(n)
		if may_centre:
			centre(n)
	return true


## The clock in milliseconds (the test's if it set one).
func _now() -> int:
	return fake_ms if fake_ms >= 0 else Time.get_ticks_msec()


## The clock the taps are timed by, in milliseconds (the minimap spaces its flashes by it, so a test that sets fake_ms drives both).
func now_ms() -> int:
	return _now()


## The group a key press stands for, by the key map: {"n": 1..COUNT, "how": "pick", "set" or "add"} (Ctrl sets, Shift adds,
## no modifier picks), or {} when the press is no group key (Alt and Meta never count).
static func key_group(event: InputEventKey) -> Dictionary:
	if event.alt_pressed or event.meta_pressed:
		return {}
	var code := int(event.physical_keycode) if int(event.physical_keycode) != 0 else int(event.keycode)
	for n in range(1, COUNT + 1):
		for text: String in KeyMap.effective_keys("shared", "group_%d" % n):
			var p := KeyCodes.parse(String(text))
			if bool(p["ok"]) and not bool(p["mouse"]) and int(p["code"]) == code:
				return {"n": n, "how": "set" if event.ctrl_pressed else ("add" if event.shift_pressed else "pick")}
	return {}


## A key press: true when it was a group key (CommandView.key() and HudInput then mark it used). `may_centre` is whether
## the camera may move (docked, or flying with the board open; while flying with the board closed a group is only picked).
## A held key repeating does nothing more (the army card's detail opens while a group key is held).
func key(event: InputEventKey, may_centre: bool) -> bool:
	var hit := key_group(event)
	if hit.is_empty():
		return false
	if event.echo:
		return true
	var n := int(hit["n"])
	match str(hit["how"]):
		"set":
			set_from_selection(n)
		"add":
			add_from_selection(n)
		_:
			tap(n, may_centre)
	return true


## Every 0.25 s: find the squadrons that appeared since the last look and put each into its hull's join group. The first
## call only notes the squadrons that exist (the ones a match starts with are not "newly built").
func sync() -> void:
	var recs := RtsSelect.our_squads(world, team)
	if not _primed:
		_primed = true
		for rec: Squad in recs:
			_known[rec.id] = true
		return
	for rec: Squad in recs:
		if _known.has(rec.id):
			continue
		_known[rec.id] = true
		var n := int(join.get(rec.hull_id, 0))
		if n > 0 and group_of(rec.id) == 0:
			var one: Array[int] = [rec.id]
			add_group(n, one)
	for n in range(1, COUNT + 1):
		var live := members(n)
		if live.size() != (_members[n] as Array).size():
			_members[n] = live


## The group a new squadron of `hull` joins (0 for none).
func join_of(hull: String) -> int:
	return int(join.get(hull, 0))


## Choose the group (0 for none) a new squadron of `hull` joins, and save the choice. Returns Godot's error code of the save.
func set_join(hull: String, n: int) -> int:
	if n <= 0:
		join.erase(hull)
	else:
		join[hull] = clampi(n, 1, COUNT)
	changed.emit()
	return RtsUiStore.save_joins(join, store_path)

## Put the camera on world point `p`. A camera that follows the Admiral's ship is let go first (as the alert jump does),
## because a followed camera ignores look_at_point. The slide is the camera's own.
static func centre_on(w: World, p: Vector2) -> void:
	var cam := w.camera
	if cam == null:
		return
	if not cam.free:
		cam.toggle_free()
	cam.look_at_point(p)
