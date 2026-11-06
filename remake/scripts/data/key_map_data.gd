class_name KeyMapData
extends RefCounted
## WHAT THIS IS: the list of every key the game uses, as plain data: one row
## per action (a "thing a key does"), with its keys, a mouse way to do the
## same, and which part of the game makes it work. The Controls page, the
## "Keys" help page, the HUD's key line and the key check all read this list;
## nothing else in the game keeps a second copy of a key.
##
## HOW IT WORKS: the rows are grouped in four modes. "shared" keys work in every
## mode. "home" is the docked command view (the Admiral at the mothership).
## "flying" is the pilot's view with the board closed. "flying_board" is the
## command view opened while flying; it inherits "flying" and has rows only for
## what differs. A row is a Dictionary:
##   id       the action's name (the InputMap action of a live row, for example
##            "thrust_forward"); it is unique inside a mode
##   mode     one of MODES
##   label    the name shown on the Controls page
##   keys     the keys as text, "KEY1|KEY2" (a third and later key are extras that
##            stay when the first two are changed); "" is unbound. A key is
##            "A", "Shift+QuoteLeft", "Ctrl+F12" or "Mouse4": the modifiers Ctrl, Alt
##            and Shift first, then one key or mouse button 3 to 5 (KeyMap
##            parses them)
##   route    a button, menu or panel that does the same with the mouse; "" is
##            allowed for now and counted as a warning by the key check
##   since    the stage that makes the row work: "today", "RT2" or "wingmen" (LIVE_STAGES)
##            work now; any later name only labels the "comes with" column
##   group    where the page files it: Camera, Selection, Orders, Build, Base,
##            Pilot or Shared
## and, only when they differ from the default:
##   page     "orders", "build" or "base" for a cell of the command card (two rows
##            clash only on the same page, or when either row has no page)
##   link     the row follows another action's keys (the camera keys are the
##            pilot's movement keys): edit them in one place
##   fixed    true: shown and checked for clashes but not rebindable (read
##            straight from the keyboard by the flight code, or a mouse click)
##   action   false: not an InputMap action (the heading lock is read directly)
##   web_skip key texts left out in the web build (the browser keeps F11)
##   note     one more plain line for the page
## Only rows whose stage is in LIVE_STAGES, in the shared and flying modes,
## become InputMap actions (KeyMap.apply_to_input_map); the other modes and
## every link row are data for the page and the check until the screens that use
## them are built.
##
## PRESETS are groups of alternative key sets for part of the game. Each
## preset lists, per mode, the rows it changes: "action": "KEY1|KEY2", or a
## Dictionary {"keys": ..., "page": ...} when the page differs too. The player's
## choice per group is stored; the keys of a row are the player's own change if
## any, else the chosen preset's row, else the row above.
##
## WHO USES IT: KeyMap (parsing, bindings, storage), GameInputMap (the live
## actions), the Controls page, the Keys help page, HudSlots (the key line) and
## tests/key_map_check.gd. Later stages append rows (one block per mode) and
## preset groups; they never edit a row of another stage.

## The modes, in the order the page shows them.
const MODES := ["shared", "home", "flying", "flying_board"]

## The name of each mode as the page shows it.
const MODE_LABELS := {
	"shared": "Every mode",
	"home": "Home",
	"flying": "Flying",
	"flying_board": "Flying with the board open",
}

## The stages whose rows work now (only these become InputMap actions). A later
## stage appends its name here, which is the one edit that makes its rows live.
const LIVE_STAGES := ["today", "RT2", "wingmen"]

## What the "comes with" column says for a row that is not live yet, by stage.
const COMES_WITH := {
	"RT4": "the command view",
	"RT6": "the alert list",
	"RT7": "flying with the command view",
	"RT10": "the research board",
	"RT11": "the team wheel",
	"RT12": "squadron groups",
}

## Notes for the builder of Vent (the pilot's vent key, which is bound to Z):
## Z is reserved in the flying and flying_board modes, and at home under layout B,
## until that builder appends a flying row "vent" with keys "Z". Layout C spends Z at
## home, so the same builder also gives layout C (in PRESETS, group home_layout)
## a row {"flying": {"vent": "Shift+Z"}}. Shift+Z is proven free in the flying mode in
## every combination of presets by tests/key_map_check.gd (the wing preset B of
## the wingmen, which spends Y U I O K L N and Shift+N there, included). Not K.
##
## The rows (see the header for the fields). Editing a key means editing its row.
const ROWS := [
	# --- shared: every mode ------------------------------------------------------
	{"id": "cancel", "mode": "shared", "label": "Cancel, then close", "keys": "Esc", "route": "Close buttons", "since": "today", "group": "Shared"},
	{"id": "pause", "mode": "shared", "label": "Pause", "keys": "P", "route": "Menu button", "since": "RT2", "group": "Shared"},
	{"id": "note", "mode": "shared", "label": "Write a note", "keys": "F9", "route": "", "since": "today", "group": "Shared"},
	{"id": "slow_motion", "mode": "shared", "label": "Speed: slower", "keys": "QuoteLeft", "route": "Speed row", "since": "today", "group": "Shared"},
	{"id": "fast_motion", "mode": "shared", "label": "Speed: faster", "keys": "Shift+QuoteLeft", "route": "Speed row", "since": "RT2", "group": "Shared"},
	{"id": "toggle_fullscreen", "mode": "shared", "label": "Full screen", "keys": "F11|Alt+Enter|Alt+KPEnter", "route": "Menu > Full screen", "since": "today", "group": "Shared", "web_skip": "F11"},
	{"id": "admiral_board", "mode": "shared", "label": "Admiral board, command view", "keys": "Tab", "route": "Board button (Admiral)", "since": "today", "group": "Shared"},
	{"id": "debug_launch", "mode": "shared", "label": "Debug launch (text overlay only)", "keys": "Ctrl+F12", "route": "", "since": "RT2", "group": "Shared"},
	{"id": "zoom_in", "mode": "shared", "label": "Zoom in", "keys": "Equal|KPAdd", "route": "Mouse wheel", "since": "today", "group": "Camera"},
	{"id": "zoom_out", "mode": "shared", "label": "Zoom out", "keys": "Minus|KPSubtract", "route": "Mouse wheel", "since": "today", "group": "Camera"},
	{"id": "center_on_ship", "mode": "shared", "label": "Centre the camera on your ship", "keys": "Space", "route": "Centre button (click again to let go)", "since": "today", "group": "Camera"},
	{"id": "wheel", "mode": "shared", "label": "Order wheel (hold)", "keys": "X|Mouse5", "route": "Wing button", "since": "RT2", "group": "Shared", "note": "Hold: the wing's order wheel; tap: a quick order."},
	{"id": "all_squadrons", "mode": "shared", "label": "Every squadron", "keys": "M", "route": "Select-all button", "since": "RT4", "group": "Selection"},
	{"id": "group_1", "mode": "shared", "label": "Group 1 (Ctrl sets, Shift adds)", "keys": "F1", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_2", "mode": "shared", "label": "Group 2", "keys": "F2", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_3", "mode": "shared", "label": "Group 3", "keys": "F3", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_4", "mode": "shared", "label": "Group 4", "keys": "F4", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_5", "mode": "shared", "label": "Group 5", "keys": "F5", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_6", "mode": "shared", "label": "Group 6", "keys": "F6", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_7", "mode": "shared", "label": "Group 7", "keys": "F7", "route": "Group buttons", "since": "RT4", "group": "Selection"},
	{"id": "group_8", "mode": "shared", "label": "Group 8", "keys": "F8", "route": "Group buttons", "since": "RT4", "group": "Selection"},

	# --- flying: the pilot's keys, exactly as before --------------------------------
	{"id": "thrust_forward", "mode": "flying", "label": "Thrust forward", "keys": "W", "route": "", "since": "today", "group": "Pilot"},
	{"id": "thrust_back", "mode": "flying", "label": "Brake and reverse", "keys": "S", "route": "", "since": "today", "group": "Pilot"},
	{"id": "strafe_left", "mode": "flying", "label": "Slide left", "keys": "A|Q", "route": "", "since": "today", "group": "Pilot"},
	{"id": "strafe_right", "mode": "flying", "label": "Slide right", "keys": "D|E", "route": "", "since": "today", "group": "Pilot"},
	{"id": "boost", "mode": "flying", "label": "Boost", "keys": "Shift", "route": "", "since": "today", "group": "Pilot"},
	{"id": "fire", "mode": "flying", "label": "Fire", "keys": "Mouse1", "route": "Left click", "since": "today", "group": "Pilot", "fixed": true, "note": "The left mouse button is the click."},
	{"id": "special", "mode": "flying", "label": "Ship ability", "keys": "G|Mouse2", "route": "Right click", "since": "today", "group": "Pilot", "fixed": true, "note": "Read directly by the flight code."},
	{"id": "face_lock", "mode": "flying", "label": "Hold your heading (face lock)", "keys": "Ctrl", "route": "", "since": "today", "group": "Pilot", "fixed": true, "action": false, "note": "Read directly by the flight code."},
	{"id": "shield_front", "mode": "flying", "label": "Shields: front", "keys": "Up", "route": "Shield zone on the readout", "since": "today", "group": "Pilot"},
	{"id": "shield_rear", "mode": "flying", "label": "Shields: rear", "keys": "Down", "route": "Shield zone on the readout", "since": "today", "group": "Pilot"},
	{"id": "shield_left", "mode": "flying", "label": "Shields: left", "keys": "Left", "route": "Shield zone on the readout", "since": "today", "group": "Pilot"},
	{"id": "shield_right", "mode": "flying", "label": "Shields: right", "keys": "Right", "route": "Shield zone on the readout", "since": "today", "group": "Pilot"},
	{"id": "energy_weapons", "mode": "flying", "label": "Energy: weapons", "keys": "1", "route": "Energy button on the readout", "since": "today", "group": "Pilot"},
	{"id": "energy_shields", "mode": "flying", "label": "Energy: shields", "keys": "2", "route": "Energy button on the readout", "since": "today", "group": "Pilot"},
	{"id": "energy_thrusters", "mode": "flying", "label": "Energy: engines", "keys": "3", "route": "Energy button on the readout", "since": "today", "group": "Pilot"},
	{"id": "energy_balanced", "mode": "flying", "label": "Energy: balanced", "keys": "4", "route": "Energy button on the readout", "since": "today", "group": "Pilot"},
	{"id": "use_kit", "mode": "flying", "label": "Use a repair kit", "keys": "R", "route": "Kit gear slot", "since": "today", "group": "Pilot"},
	{"id": "assist_toggle", "mode": "flying", "label": "Flight assist on or off", "keys": "V", "route": "Assist button", "since": "today", "group": "Pilot"},
	{"id": "hangar", "mode": "flying", "label": "Hangar", "keys": "B", "route": "Hangar button", "since": "today", "group": "Pilot"},
	{"id": "dock", "mode": "flying", "label": "Dock, or launch from the hangar", "keys": "F", "route": "Dock button; Launch when docked", "since": "today", "group": "Pilot"},
	{"id": "help", "mode": "flying", "label": "Help", "keys": "H|F12", "route": "Help button", "since": "today", "group": "Pilot"},
	{"id": "center_camera", "mode": "flying", "label": "Camera: free or follow", "keys": "C", "route": "Camera button (Admiral)", "since": "today", "group": "Camera"},
	{"id": "team_wheel", "mode": "flying", "label": "Team wheel", "keys": "T|Mouse4", "route": "Team strip", "since": "RT11", "group": "Pilot"},
	# The wing's orders on a key each (the "wing_commands" preset B gives them keys; with the standard one-key
	# way (preset A) they have none and the page leaves them out). The mouse way is the strip's Wing button.
	{"id": "wing_follow", "mode": "flying", "label": "Wing: form on me", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_cover", "mode": "flying", "label": "Wing: cover me", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_attack", "mode": "flying", "label": "Wing: attack my target", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_guard", "mode": "flying", "label": "Wing: guard that ship", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_hold", "mode": "flying", "label": "Wing: hold here", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_regroup", "mode": "flying", "label": "Wing: regroup", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_formation", "mode": "flying", "label": "Wing: next formation", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},
	{"id": "wing_fire", "mode": "flying", "label": "Wing: next fire setting", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot"},

	# --- flying with the board open: only the rows that differ from flying --------------
	{"id": "camera_up", "mode": "flying_board", "label": "Camera up", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "thrust_forward"},
	{"id": "camera_down", "mode": "flying_board", "label": "Camera down", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "thrust_back"},
	{"id": "camera_left", "mode": "flying_board", "label": "Camera left", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "strafe_left"},
	{"id": "camera_right", "mode": "flying_board", "label": "Camera right", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "strafe_right"},
	{"id": "thrust_forward", "mode": "flying_board", "label": "Thrust forward (rests)", "keys": "", "route": "", "since": "today", "group": "Pilot", "note": "The ship coasts; this key moves the camera."},
	{"id": "thrust_back", "mode": "flying_board", "label": "Brake and reverse (rests)", "keys": "", "route": "", "since": "today", "group": "Pilot", "note": "The ship coasts; this key moves the camera."},
	{"id": "strafe_left", "mode": "flying_board", "label": "Slide left (rests)", "keys": "", "route": "", "since": "today", "group": "Pilot", "note": "The ship coasts; these keys move the camera."},
	{"id": "strafe_right", "mode": "flying_board", "label": "Slide right (rests)", "keys": "", "route": "", "since": "today", "group": "Pilot", "note": "The ship coasts; these keys move the camera."},
	{"id": "fire", "mode": "flying_board", "label": "Fire (rests)", "keys": "", "route": "", "since": "today", "group": "Pilot", "fixed": true, "note": "Map clicks select; they never fire the guns."},
	{"id": "alert_jump", "mode": "flying_board", "label": "Jump to the newest alert", "keys": "J|Backspace", "route": "Alert list", "since": "RT6", "group": "Selection"},
	{"id": "idle_next", "mode": "flying_board", "label": "Next idle squadron", "keys": "I", "route": "Idle button", "since": "RT6", "group": "Selection"},
	# The wing's attack and cover keys (preset B: I and U) stay the Admiral's while the board is open: these rows
	# of the same names take the preset's keys off in this mode.
	{"id": "wing_attack", "mode": "flying_board", "label": "Wing: attack my target (rests)", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot", "note": "While the board is open this key is the Admiral's."},
	{"id": "wing_cover", "mode": "flying_board", "label": "Wing: cover me (rests)", "keys": "", "route": "Wing button", "since": "wingmen", "group": "Pilot", "note": "While the board is open this key is the Admiral's."},
	{"id": "research_board", "mode": "flying_board", "label": "Research board", "keys": "U", "route": "Research tab", "since": "RT10", "group": "Base"},

	# --- home: the docked command view -----------------------------------------------
	{"id": "camera_up", "mode": "home", "label": "Camera up", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "thrust_forward"},
	{"id": "camera_down", "mode": "home", "label": "Camera down", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "thrust_back"},
	{"id": "camera_left", "mode": "home", "label": "Camera left", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "strafe_left"},
	{"id": "camera_right", "mode": "home", "label": "Camera right", "keys": "", "route": "Screen edge", "since": "today", "group": "Camera", "link": "strafe_right"},
	{"id": "hull_1", "mode": "home", "label": "Queue Scout squadron (Shift: to the cap, Alt: repeat)", "keys": "1", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_2", "mode": "home", "label": "Queue Fighter squadron", "keys": "2", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_3", "mode": "home", "label": "Queue Lance squadron", "keys": "3", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_4", "mode": "home", "label": "Queue Bomber squadron", "keys": "4", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_5", "mode": "home", "label": "Queue Logistics corvette", "keys": "5", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_6", "mode": "home", "label": "Queue Support corvette", "keys": "6", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_7", "mode": "home", "label": "Queue Flak frigate", "keys": "7", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_8", "mode": "home", "label": "Queue Ion frigate", "keys": "8", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_9", "mode": "home", "label": "Queue Destroyer", "keys": "9", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "hull_10", "mode": "home", "label": "Queue Battlecruiser", "keys": "0", "route": "Production buttons", "since": "RT4", "group": "Build"},
	{"id": "idle_next", "mode": "home", "label": "Next idle squadron", "keys": "I", "route": "Idle button", "since": "RT6", "group": "Selection"},
	{"id": "idle_all", "mode": "home", "label": "Every idle squadron", "keys": "Ctrl+I", "route": "Idle button", "since": "RT6", "group": "Selection"},
	{"id": "alert_jump", "mode": "home", "label": "Jump to the newest alert", "keys": "J|Backspace", "route": "Alert list", "since": "RT6", "group": "Selection"},
	{"id": "research_board", "mode": "home", "label": "Research board", "keys": "U", "route": "Research tab", "since": "RT10", "group": "Base"},
	{"id": "hangar", "mode": "home", "label": "Hangar", "keys": "B", "route": "Hangar button", "since": "today", "group": "Base"},
	{"id": "help", "mode": "home", "label": "Help", "keys": "H|F12", "route": "Help button", "since": "today", "group": "Base"},
	{"id": "center_camera", "mode": "home", "label": "Camera: free or follow ship", "keys": "C", "route": "Camera button", "since": "today", "group": "Camera"},
	{"id": "team_wheel", "mode": "home", "label": "Team wheel", "keys": "T|Mouse4", "route": "Team strip", "since": "RT11", "group": "Shared"},
	# The command card: every action of the card, unbound here; the chosen layout (PRESETS) gives them keys.
	{"id": "order_move", "mode": "home", "label": "Move", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_attack_move", "mode": "home", "label": "Attack-move", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_hold", "mode": "home", "label": "Hold position", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_stop", "mode": "home", "label": "Stop", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_patrol", "mode": "home", "label": "Patrol", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_retreat", "mode": "home", "label": "Retreat and dock", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_defend", "mode": "home", "label": "Defend (guard) a point or structure", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_goal", "mode": "home", "label": "Goal (then click the target)", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_escort", "mode": "home", "label": "Escort a pilot", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_stance", "mode": "home", "label": "Stance (fire)", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_position", "mode": "home", "label": "Position stance", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_formation", "mode": "home", "label": "Formation", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_push_lane", "mode": "home", "label": "Push the lane", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_merge", "mode": "home", "label": "Merge short squadrons", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_full_assault", "mode": "home", "label": "Full assault", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "order_full_retreat", "mode": "home", "label": "Full retreat", "keys": "", "route": "Command card", "since": "RT4", "group": "Orders", "page": "orders"},
	{"id": "build_scout", "mode": "home", "label": "Scout squadron", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_fighter", "mode": "home", "label": "Fighter squadron", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_lance", "mode": "home", "label": "Lance squadron", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_bomber", "mode": "home", "label": "Bomber squadron", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_logistics", "mode": "home", "label": "Logistics corvette", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_support", "mode": "home", "label": "Support corvette", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_flak", "mode": "home", "label": "Flak frigate", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_ion", "mode": "home", "label": "Ion frigate", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_destroyer", "mode": "home", "label": "Destroyer", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_battlecruiser", "mode": "home", "label": "Battlecruiser", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_capitals", "mode": "home", "label": "Capital ships (Destroyer, Battlecruiser)", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "build_drone", "mode": "home", "label": "Mining drone", "keys": "", "route": "Command card", "since": "RT4", "group": "Build", "page": "build"},
	{"id": "base_research", "mode": "home", "label": "Research board", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_drone", "mode": "home", "label": "Mining drone", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_deputy", "mode": "home", "label": "Deputy on or off", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_deputy_preset", "mode": "home", "label": "Deputy preset", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_turret", "mode": "home", "label": "Turret tool", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_torpedo", "mode": "home", "label": "Torpedo turret tool", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_repair", "mode": "home", "label": "Repair bay tool", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_ward", "mode": "home", "label": "Ward tool", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_waypoint", "mode": "home", "label": "Waypoint tool", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_rally", "mode": "home", "label": "Rally point for new ships", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_move", "mode": "home", "label": "Move the mothership", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_cancel", "mode": "home", "label": "Cancel the newest item", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
	{"id": "base_production", "mode": "home", "label": "Production panel open or closed", "keys": "", "route": "Command card", "since": "RT4", "group": "Base", "page": "base"},
]

## The key presets, in the order the page shows them. A group is {id, label, tab
## (the mode whose tab holds its picker), default (the preset id), presets}; a preset
## is {label, text (one plain line under the picker), rows: {mode: {action: ...}}}.
## "home_layout" is the home keys: B (W A S D move the camera, a 3x3 grid R T Y / F G H
## / V B N beside them), A (the classic grid Q W E R / A S D F / Z X C V, the camera on
## the arrows) and C (a letter for each order, no grid). Until the command view exists
## the home layouts change the page, the Keys help page and the key check, not what a key
## does in play. "wing_commands" (the second group) does change play: preset B sends
## the wing orders.
const PRESETS := [
	{
		"id": "home_layout",
		"label": "Home layout",
		"tab": "home",
		"default": "B",
		"presets": {
			"B": {
				"label": "B: W A S D camera, grid beside it",
				"text": "The camera stays on W A S D Q E, as when you fly. The orders, the ships and the base tools sit on a 3x3 grid, R T Y / F G H / V B N, and the card's page follows what is selected. T is the grid's, so the team wheel is on the mouse button.",
				"rows": {"home": {
					"base_research": "R", "base_drone": "T", "base_deputy": "Y", "base_deputy_preset": "Shift+Y", "base_turret": "F",
					"base_torpedo": "Shift+F", "base_repair": "G", "base_ward": "H", "base_waypoint": "V", "base_move": "N",
					"hangar": {"keys": "B", "page": "base"},
					"order_attack_move": "R", "order_patrol": "T", "order_goal": "Y", "order_hold": "F", "order_stop": "G",
					"order_retreat": "H", "order_stance": "V", "order_position": "Shift+V", "order_formation": "B", "order_merge": "N",
					"build_fighter": "R", "build_lance": "T", "build_bomber": "Y", "build_scout": "F", "build_logistics": "G",
					"build_support": "H", "build_flak": "V", "build_ion": "B", "build_capitals": "N",
					"help": "F12", "team_wheel": "Mouse4",
				}},
			},
			"A": {
				"label": "A: the classic grid Q W E R / A S D F / Z X C V",
				"text": "The command card sits on Q W E R / A S D F / Z X C V with the classic letters (A attack-move, S stop, D defend, F escort, R retreat), X is the order wheel, and the camera moves on the arrow keys.",
				"rows": {"home": {
					"camera_up": "Up", "camera_down": "Down", "camera_left": "Left", "camera_right": "Right", "center_camera": "",
					"order_move": "Q", "order_hold": "W", "order_patrol": "E", "order_retreat": "R", "order_attack_move": "A",
					"order_stop": "S", "order_defend": "D", "order_escort": "F", "order_stance": "Z", "order_formation": "Shift+Z",
					"order_push_lane": "C", "order_merge": "V",
					"build_scout": "Q", "build_fighter": "W", "build_lance": "E", "build_bomber": "R", "build_logistics": "A",
					"build_support": "S", "build_flak": "D", "build_ion": "F", "build_destroyer": "Z", "build_battlecruiser": "C",
					"build_drone": "V",
					"base_turret": "Q", "base_torpedo": "W", "base_repair": "E", "base_ward": "R", "base_move": "A", "base_rally": "S",
					"base_waypoint": "D", "base_deputy": "F", "base_deputy_preset": "Z", "base_cancel": "C", "base_production": "V",
				}},
			},
			"C": {
				"label": "C: a letter for each order, no grid",
				"text": "No grid to learn: every order is a word around W A S D (R attack-move, G guard, V patrol, Z hold, F retreat, N merge, Shift+Z stop). The ships are on the number row only. The base tools have no key; use the mouse.",
				"rows": {"home": {
					"order_attack_move": "R", "order_defend": "G", "order_patrol": "V", "order_hold": "Z", "order_stop": "Shift+Z",
					"order_retreat": "F", "order_merge": "N", "order_position": "Ctrl+Z", "order_stance": "Ctrl+X",
					"order_formation": "Ctrl+V", "order_full_assault": "Ctrl+R", "order_full_retreat": "Ctrl+F",
				}},
			},
		},
	},
	{
		"id": "wing_commands",
		"label": "Wing commands",
		"tab": "flying",
		"default": "A",
		"presets": {
			"A": {
				"label": "A: one key, X (hold for the wheel)",
				"text": "Hold X for the order wheel, or tap it: an enemy under the mouse is attacked, one of your big ships guarded, empty space means form on me. The strip's Wing button opens the same wheel. The eight keys below have none.",
				"rows": {},
			},
			"B": {
				"label": "B: a key for each order",
				"text": "Y form on me, U cover me, I attack my target, O guard that ship, K hold here, L regroup, N next formation, Shift+N next fire setting. The X wheel still works. While the Admiral's board is open I and U stay the Admiral's.",
				"rows": {"flying": {
					"wing_follow": "Y", "wing_cover": "U", "wing_attack": "I", "wing_guard": "O", "wing_hold": "K", "wing_regroup": "L",
					"wing_formation": "N", "wing_fire": "Shift+N",
				}},
			},
		},
	},
]
