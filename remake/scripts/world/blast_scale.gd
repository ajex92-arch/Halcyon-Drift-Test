class_name BlastScale
extends RefCounted
## WHAT THIS IS: the blast rule of the torpedoes and the flak weapons: how much
## of a hit a target takes, by how big it is and how fast it moves. A target
## as big as the blast, or bigger, takes all of it. A small target takes a
## share of it, and a small target that is also fast takes still less.
##
## HOW IT WORKS: every torpedo and flak weapon in weapons.gd names three whole
## numbers: a blast size E (in world units, compared with a target's size), a
## blast speed Ve (world units per second, compared with a target's speed) and
## a curve (a number that picks one of the lookup tables below). A target has a
## size S (its hit radius, Unit.hit_radius()) and a speed Vt (how fast it is
## moving right now). The share of the hit it takes, in whole percent, is:
##   size_pct  = S * 100 / E, at most 100 (how much of the blast size the target fills)
##   speed_pct = Ve * 100 / Vt, at most 100 (100 when the target is no faster than the blast)
##   x         = size_pct * speed_pct / 100
##   share     = the smaller of size_pct and the table's answer for x
## The table is a list of 21 whole numbers: its answer for x = 0, 5, 10 ... 100
## percent (between two entries the answer is on the straight line between
## them). A table that holds x unchanged makes the share size times speed; a
## table that holds less than x makes a small fast target take even less.
## There is no dice, no table of target classes and no new key: only size and
## speed. The share is applied to the hit's damage before anything else happens
## to it, so the shield, and later the armour, only see the smaller hit.
##
## WHO USES IT: ProjectilesImpact (the hit of a torpedo) and CombatBeamArea.area()
## (each victim of a flak burst) call apply(); the numbers E, Ve and the curve
## number sit in the weapon rows of weapons.gd. The time-to-kill table reads the
## result through the game.

## How far apart (in percent of x) the entries of a curve are.
const STEP := 5
## The lookup tables, picked by a weapon's "blast_curve" number. Each holds the
## share (percent) for x = 0, 5, 10 ... 100.
## Curve 0 (torpedoes): x to the power 1.2, a little steeper than a straight
## line, so a small target is helped by being fast and a big one is not hurt.
## Curve 1 (flak): a straight line (x), so a target's share is exactly its size
## times its speed ratio.
const CURVES := [
	[0, 3, 6, 10, 14, 19, 24, 28, 33, 38, 44, 49, 54, 60, 65, 71, 77, 82, 88, 94, 100],
	[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100],
]


## The share (whole percent, 0 to 100) of a hit that a target of size
## `target_radius` moving at `target_speed` takes from a blast of size
## `blast_size`, speed `blast_speed` and curve `curve`. A blast size of 0 (a
## weapon that is not a blast weapon) means all of it.
static func percent(curve: int, blast_size: int, blast_speed: int, target_radius: float, target_speed: float) -> int:
	if blast_size <= 0:
		return 100
	# Step 1: how much of the blast size the target fills, and how much of the
	# target's speed the blast covers (both in whole percent, at most 100).
	var size_pct := mini(100, floori(float(roundi(target_radius) * 100) / float(blast_size)))
	var speed := roundi(target_speed)
	var speed_pct := 100
	if speed > blast_speed:
		speed_pct = floori(float(blast_speed * 100) / float(speed))
	var x := floori(float(size_pct * speed_pct) / 100.0)
	# Step 2: read the curve at x, on the straight line between two entries.
	var table: Array = CURVES[clampi(curve, 0, CURVES.size() - 1)]
	var i := mini(floori(float(x) / float(STEP)), table.size() - 2)
	var f := x - i * STEP
	var y := roundi((float(table[i]) * float(STEP - f) + float(table[i + 1]) * float(f)) / float(STEP))
	return mini(size_pct, y)


## Scale the damage of hit note `info` (a torpedo hit or a flak victim) for
## `target`: its amount becomes the share of it that `target` takes. A note
## with no blast size (every other weapon) is left alone.
static func apply(info: DamageInfo, target: Unit) -> void:
	if info.blast_size <= 0:
		return
	var share := percent(info.blast_curve, info.blast_size, info.blast_speed, target.hit_radius(), target.velocity.length())
	info.amount = info.amount * float(share) / 100.0
