class_name HudSlots
extends VBoxContainer
## WHAT THIS IS: the bottom-left corner of the HUD: a one-line reminder of
## the menu keys, and under it the pilot's 6 gear slots (what they carry:
## pilot gear and repair kits).
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_slots.tscn: a column
## 8 pixels from the bottom-left corner, growing upward, holding Keys (the
## grey key reminder, 11 px; it wraps to the width of the gear slots) and
## Gear (a grid for the slot boxes, 4 pixels apart: one row of 6, or two rows
## of 3 in a narrow window, see set_compact()). The mouse passes through it,
## except over a slot that holds a repair kit: a click there uses a kit.
## How many slots there are is game
## data (Items.SLOTS = 6), so _ready() adds the boxes to Gear: one per slot,
## each made from scenes/ui/hud_gear_slot.tscn (a dark 62 x 40 pixel box,
## the "SlotLook" look, with a centred, wrapping 10 px label, Item).
## refresh_slots() writes each slot's item name, "Kit x2 (R)" for repair
## kits, or a dash for an empty slot. refresh_keys() writes the key
## reminder for the human's seat (Admiral or pilot) from the key list, so it
## shows the player's own keys (KeyMapText.key_line).
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it; Hud._refresh()
## calls refresh_slots() and refresh_keys() 10 times a second and shows
## slots_box only to pilots (and to an Admiral who is flying a ship).
## HudLayout asks wide_width() and calls set_compact().

## One gear slot's box (scenes/ui/hud_gear_slot.tscn).
const SLOT_SCENE := preload("res://scenes/ui/hud_gear_slot.tscn")

## The grid of gear slot boxes (Hud hides it when it isn't useful).
@onready var slots_box: GridContainer = $Gear
## The key reminder line ("B hangar · F dock/launch · ...").
@onready var _keys: Label = $Keys
## One label per gear slot, in slot order.
var _slot_labels: Array[Label] = []
## One box per gear slot, in slot order.
var _boxes: Array[PanelContainer] = []
## Does each slot hold a repair kit now (refresh_slots() keeps it)? Only such a box takes the mouse.
var _is_kit: Array[bool] = []
## The slot a left press started on, or -1: the release acts only on the same slot.
var _press_slot := -1
## True while the gear slots are in two rows of 3 (set_compact).
var _compact := false
## The HUD (set by Hud.setup()): a click on a kit slot goes to its router (HudInput.click("use_kit")).
var hud: Hud = null


## Godot calls this when the corner joins the HUD: add one box per gear
## slot to the Gear grid, and remember each box's label. The key reminder is
## made as wide as the gear row, so it wraps there. Each box also listens to
## its own clicks (a box takes the mouse only while its slot holds a kit).
func _ready() -> void:
	for i in Items.SLOTS:
		var box: PanelContainer = SLOT_SCENE.instantiate()
		slots_box.add_child(box)
		_slot_labels.append(box.get_node("Item") as Label)
		_boxes.append(box)
		_is_kit.append(false)
		box.gui_input.connect(_on_box_input.bind(i))
	_keys.custom_minimum_size.x = _row_width(Items.SLOTS)


## The width (pixels) of the gear slots in one row of all of them.
func wide_width() -> float:
	return _row_width(Items.SLOTS)


## Put the gear slots in two rows of 3 (`on`), or in one row of 6, for a
## window that is too narrow (or wide enough) for the whole bottom row.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	var cols := 3 if on else Items.SLOTS
	slots_box.columns = cols
	_keys.custom_minimum_size.x = _row_width(cols)


## The width (pixels) of `cols` gear slot boxes side by side.
func _row_width(cols: int) -> float:
	var box := slots_box.get_child(0) as Control
	return float(cols) * box.get_combined_minimum_size().x + float(cols - 1) * float(slots_box.get_theme_constant("h_separation"))


## Write what is in each of pilot `h`'s gear slots (nothing to do when
## there is no human pilot profile).
func refresh_slots(h: PilotProfile) -> void:
	if h == null:
		return
	for i in Items.SLOTS:
		var s: Dictionary = h.inventory[i]
		var txt := ""
		var kit := false
		if s.is_empty():
			txt = "—"
		elif s["id"] == Items.KIT["id"]:
			txt = "Kit x%d\n(R)" % int(s["count"])
			kit = true
		else:
			txt = String(Items.ITEMS[s["id"]]["label"])
		UiKit.set_text(_slot_labels[i], txt)
		# A kit slot takes the mouse (a click uses a kit); every other slot lets a click through to the game.
		if kit != _is_kit[i]:
			_is_kit[i] = kit
			_boxes[i].mouse_filter = Control.MOUSE_FILTER_STOP if kit else Control.MOUSE_FILTER_IGNORE
			_boxes[i].tooltip_text = "Use a repair kit (%s)" % KeyMapText.key_of("use_kit") if kit else ""


## A mouse event on gear box `slot`. Only a left click on a kit slot counts: the press picks the slot, the
## release on the same slot uses a kit (HudInput.click("use_kit"), the same as R); a slide off cancels.
func _on_box_input(event: InputEvent, slot: int) -> void:
	if not (event is InputEventMouseButton) or not _is_kit[slot]:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_slot = slot
	else:
		if _press_slot == slot and Rect2(Vector2.ZERO, _boxes[slot].size).has_point(mb.position) and hud != null:
			hud.router.click("use_kit")
		_press_slot = -1
	_boxes[slot].accept_event()


## Write the key reminder for seat `role` ("admiral", "pilot" or
## "spectator"; a spectator only sees help, pause and the note key). The line is
## made from the key list (KeyMapText.key_line), with the first key of each action as it is
## now, so it follows the player's own changes; with the standard keys it reads
## "Tab Admiral board · B hangar · ..." as it always did. The line is kept until a key changes.
## `with_wing` (default false) is true for a pilot with a wing: the line then also
## ends with the order key, " · X wing orders (hold)", so the pilot sees it too.
func refresh_keys(role: String, with_wing: bool = false) -> void:
	var line := KeyMap.key_line(role)
	# A pilot with a wing also sees the order key.
	if with_wing and role == "pilot":
		line += " · %s wing orders (hold)" % KeyMapText.key_of("wheel")
	UiKit.set_text(_keys, line)
