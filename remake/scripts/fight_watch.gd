class_name FightWatch
extends RefCounted
## WHAT THIS IS: the pacing watch of the match log. It looks for team fights
## and, once, at 10:00 of match time, prints one WARN line if no fight of 10
## or more ships has happened by then. A match like that has a thin, quiet
## first ten minutes, so the log shows a pacing problem in numbers before
## anyone has to play the match to notice it. It only watches: it reads the
## ships and their damage logs and changes nothing, so the match plays out
## exactly the same with it.
##
## HOW IT WORKS: MainReport calls sample() on every physics tick, but the
## real work runs once every STEP (2) seconds of match time. A "fight" is
## found by the same rule as the fun probe's fights (tests/lib/
## fun_probe_fights.gd, its "v2" definition), so the two agree:
##   1. Take the live pilot ships (minions, drones and turrets are not
##      counted). Two ships are LINKED when they are LINK (2,500) world units
##      apart or closer (a world unit is about one pixel at normal zoom), and
##      every chain of links is one crowd.
##   2. A crowd is a FIGHT when it holds MIN_PER_TEAM (3) or more ships of
##      each team AND, in the last HOT (4) seconds, one of its ships was hit
##      by an enemy PILOT who is in the same crowd. That is read from the
##      ship's damage log (Unit.damage_log: who hurt it, and when; Combat
##      keeps it anyway for kill rewards), so hits by minions and turrets do
##      not count, and neither does a crowd that only flies together (at
##      launch, or parked in a minion brawl) without trading hits.
##   3. A fight's size is the number of ships in its crowd. The biggest
##      fight seen so far is remembered, with its time.
## At WATCH_UNTIL (600 s, 10:00) the verdict comes, once: if the biggest
## fight has fewer than BIG (10) ships, or there was no fight at all, it
## prints
##   WARN pacing: no fight of 10 or more ships in the first 10:00 (biggest: 7 ships at 6:42)
## (the "WARN <what> <detail>" shape that map_check's lines have). Nothing is
## printed when a big enough fight happened, nothing for a match that is cut
## off or ends before 10:00, and nothing for a run that starts late (the
## --late tests start at 25:00 and never see the first ten minutes).
## --big-fight=N changes the number of ships for a test: 99 always warns and
## shows the biggest fight; 6 warns only when there was no fight at all.
##
## WHO USES IT: MainReport makes one (its `fight_watch`) and calls sample()
## each tick. Test tools read the printed lines, so the WARN line is printed
## only in the case above and its wording stays as it is.

## Ships this close (world units) or closer are linked into one crowd.
const LINK := 2500.0
## A hit this recent (seconds) makes a crowd a fight.
const HOT := 4.0
## A crowd needs this many ships of EACH team to be a fight.
const MIN_PER_TEAM := 3
## How often sample() looks for fights (seconds of match time).
const STEP := 2.0
## The match time (seconds) when the verdict comes: 10:00.
const WATCH_UNTIL := 600.0
## A fight of this many ships or more is what the first ten minutes should
## hold; --big-fight=N changes it.
const BIG := 10

## The biggest fight seen so far, in ships (0 = no fight yet).
var biggest := 0
## The match time (seconds) when that fight was first seen.
var biggest_at := 0.0
## The match time (seconds) of the next look for fights.
var _next_look := 0.0
## The match time (seconds) of the first call of sample(), or -1 before it.
var _from := -1.0
## True once the verdict has been given, or when there will be none (it is
## given only once).
var _done := false


## Look for fights if STEP seconds have passed since the last look, and give
## the verdict once the match clock reaches WATCH_UNTIL. MainReport calls it
## every physics tick with the running match.
func sample(world: World) -> void:
	# Step 1: the first call tells where the watching began. A run that begins
	# more than STEP seconds into the match (the --late tests begin at 25:00)
	# never saw the first ten minutes, so it gets no verdict.
	if _from < 0.0:
		_from = world.time
		_done = _from >= STEP
	# Step 2: the verdict at 10:00, once. After it there is nothing to do.
	if _done:
		return
	if world.time >= WATCH_UNTIL:
		_done = true
		var big := int(Game.opt("big-fight", BIG))
		if biggest < big:
			print(_warn_line(big))
		return
	# Step 3: look only every STEP seconds.
	if world.time < _next_look:
		return
	_next_look = world.time + STEP
	# Step 4: group the live pilot ships into crowds and keep the biggest
	# fight (the first time a size is reached is the time that is kept).
	var ships: Array = []
	for s: Ship in world.ships:
		if s.alive:
			ships.append(s)
	for crowd: Array in _crowds(ships):
		if crowd.size() > biggest and _is_fight(crowd, world.time):
			biggest = crowd.size()
			biggest_at = world.time


## The WARN line for a bar of `big` ships (see HOW IT WORKS).
func _warn_line(big: int) -> String:
	var seen := "no fight at all"
	if biggest > 0:
		seen = "%d ships at %s" % [biggest, Util.clock(biggest_at)]
	return "WARN pacing: no fight of %d or more ships in the first %s (biggest: %s)" % [big, Util.clock(WATCH_UNTIL), seen]


## Single-linkage crowds of `ships`: two ships that are LINK (2,500) world
## units apart or closer are linked, and every group of ships joined by links
## is one crowd. Returns a list of crowds (each a list of ships). It uses a
## "union-find" table: parent[i] points toward the representative ship of
## i's group.
func _crowds(ships: Array) -> Array:
	# Step 1: link every close pair.
	var n := ships.size()
	var parent: Array = range(n)
	for i in n:
		var pos_i: Vector2 = (ships[i] as Ship).global_position
		for j in range(i + 1, n):
			if pos_i.distance_to((ships[j] as Ship).global_position) <= LINK:
				var ra := _root(parent, i)
				var rb := _root(parent, j)
				if ra != rb:
					parent[ra] = rb
	# Step 2: file each ship under its group's representative.
	var groups := {}
	for i in n:
		var r := _root(parent, i)
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(ships[i])
	return groups.values()


## The representative of ship number `i`'s group in the union-find table
## `parent`. It also shortens the path on the way, so later look-ups are
## quick.
func _root(parent: Array, i: int) -> int:
	var x := i
	while int(parent[x]) != x:
		parent[x] = parent[int(parent[x])]
		x = int(parent[x])
	return x


## Is `crowd` a fight at match time `now`: MIN_PER_TEAM or more ships of each
## team, and a member hit by a pilot of the other team, from inside the crowd,
## within the last HOT seconds?
func _is_fight(crowd: Array, now: float) -> bool:
	# Step 1: enough ships on both sides? Also note every member's id.
	var per_team := [0, 0]
	var ids := {}
	for s: Ship in crowd:
		if s.team == 0 or s.team == 1:
			per_team[s.team] = int(per_team[s.team]) + 1
		ids[s.uid] = true
	if int(per_team[0]) < MIN_PER_TEAM or int(per_team[1]) < MIN_PER_TEAM:
		return false
	# Step 2: a recent hit by an enemy pilot who is in the crowd too. A
	# damage log entry is attacker id -> [damage, time of its last hit, its
	# PilotProfile or null]; only pilots have a profile.
	for s: Ship in crowd:
		for uid in s.damage_log:
			var e: Array = s.damage_log[uid]
			if e[2] != null and now - float(e[1]) <= HOT and ids.has(uid) and (e[2] as PilotProfile).team != s.team:
				return true
	return false
