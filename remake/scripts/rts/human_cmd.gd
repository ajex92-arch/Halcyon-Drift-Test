class_name HumanCmd
extends RefCounted
## WHAT THIS IS: the one door for everything the human does on a screen that changes the match
## but is not an order of the Admiral's queue and not a flight control: buying a ship, gear or a
## repair kit in the hangar, selling a slot, fitting a module, launching, a hyperspace launch.
## The hangar screens call run() instead of the shop and the launch directly. The point is that
## the match recorder can write each command down (a `b` line of the match log, with the tick
## it was given) and a replay can give the same command again at the same moment.
##
## HOW IT WORKS: run(world, kind, args) does the command for the human pilot (World.human) and
## returns "" or the reason it was refused, exactly what the function it calls returns. Then it
## tells the order queue (OrderQueue.record_command) so that the log gets its line. The commands:
##   buy_hull <id>        PilotProfile.buy_hull        sell_slot <i>      PilotProfile.sell_slot
##   buy_gear <id>        PilotProfile.buy_gear        toggle_module <id> PilotProfile.toggle_module
##   buy_kit              PilotProfile.buy_kit         swap_module <id>   World.swap_module_in_bay
##   upgrade_gear <i>     GearMk2Feature.upgrade       launch             World.launch
##   hyperspace <uid>     World.hyperspace_launch to the repair bay with that unit id
##   buyback              BuybackFeature.press
## A command needs a human pilot (World.human); in a match with none, or while a replay plays the
## human (the replay's own commands pass `from_replay`), a screen's command is refused. The
## computer pilots never come through here: they call the shop and the launch themselves.
## Because the hangar screens used to call those functions directly, a match played without a
## recording is exactly the match it was.
##
## WHO USES IT: the hangar screens (hangar_ships, hangar_gear, hangar_kits, hangar_modules,
## hangar_launch), main.gd and the debug launch (the automatic Fighter of a test run), and
## OrderQueue.run_commands() (a replay). tests/record_check.gd checks it.

## The reason given for a screen's command during a replay.
const TEXT_REPLAYING := "Replaying a recorded match"


## Do command `kind` with `args` for the human pilot of `w` and record it. `from_replay` is true only
## for a replay's own commands. Returns "" when it worked, else the reason it did not.
static func run(w: World, kind: String, args: Array = [], from_replay: bool = false) -> String:
	var p := w.human
	if p == null:
		return "No human pilot"
	if w.orders.replaying and not from_replay:
		return TEXT_REPLAYING
	var result := _do(w, p, kind, args)
	w.orders.record_command(kind, args, result)
	return result


## The command itself (see the table at the top). Returns "" or the reason.
static func _do(w: World, p: PilotProfile, kind: String, args: Array) -> String:
	match kind:
		"buy_hull":
			return p.buy_hull(str(args[0]), w.teams[p.team])
		"buy_gear":
			return p.buy_gear(str(args[0]))
		"buy_kit":
			return p.buy_kit()
		"sell_slot":
			p.sell_slot(int(args[0]))
			return ""
		"toggle_module":
			return p.toggle_module(str(args[0]))
		"swap_module":
			return w.swap_module_in_bay(p, str(args[0]))
		"upgrade_gear":
			return GearMk2Feature.upgrade(p, int(args[0]))
		"launch":
			return "" if w.launch(p) != null else "Can't launch right now."
		"hyperspace":
			var bay: Variant = w.by_uid.get(int(args[0]))
			return w.hyperspace_launch(p, bay as Unit) if bay != null else "That repair bay is gone"
		"buyback":
			return BuybackFeature.press(p)
	return "Unknown command %s" % kind
