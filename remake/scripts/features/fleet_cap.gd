class_name FleetCapFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "fleet_cap" rule variant. It used to set
## how many bought minions a team could have alive at once with the Fleet Command
## Module. Nothing buys minions now and the limit is ignored: the fleet limit of
## the yard is RtsHulls.CAP_IN_FORCE, its one home. The variant stays so the
## rule sets and old command lines still load.
## REQ-CHANGE: none.
##
## HOW IT WORKS: the value is the limit written as a whole number,
## --variant=fleet_cap:45. The default, "30", is the old rules and installs
## nothing (FeatureRegistry skips a key that has its default value). Any
## other whole number from 1 to MAX_CAP is stored as the tuned number
## "fleet_cap" (Game.tunables), which Minions.control_cap() reads. The limit
## is not read by anything now (it was enforced where minions were bought). A value that is not a
## whole number from 1 to MAX_CAP only gets a warning and the match keeps
## the default 30. The module draws no random numbers and makes no units. It
## records the limit it set in Game.usage as "fleet_cap_set".
##
## WHO USES IT: FeatureRegistry installs it for --variant=fleet_cap:<number>.

## The variant key this module belongs to.
const KEY := "fleet_cap"
## The most the variant accepts (a typo such as 4500 gets a warning instead of
## a match with thousands of minions).
const MAX_CAP := 300


## Set the limit for the match (FeatureRegistry calls this once at match
## start; WorldSetup empties Game.tunables for the next match). An unusable
## value only gets a warning.
func install(_w: World) -> void:
	var value := Game.variant(KEY)
	if not value.is_valid_int() or value.to_int() < 1 or value.to_int() > MAX_CAP:
		push_warning("fleet_cap: unusable value \"%s\" (use a whole number from 1 to %d); the limit stays %d" % [value, MAX_CAP, Minions.CONTROL_CAP])
		return
	var cap := value.to_int()
	Game.tunables["fleet_cap"] = cap
	Game.count_usage("fleet_cap_set", cap)
