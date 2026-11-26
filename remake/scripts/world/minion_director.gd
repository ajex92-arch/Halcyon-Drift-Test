class_name MinionDirector
extends RefCounted
## WHAT THIS IS: sends out the minions (small computer-flown lane ships)
## in waves. The waves never stop for either team. DESIGN.md A8.
##
## HOW IT WORKS:
##   - Free waves: the first wave at 0:45 (Minions.FIRST_WAVE), then one
##     every 35 s (Minions.WAVE_INTERVAL; a feature module may tune it as
##     "wave_interval", see Rules.tune). Each team launches the own wave of
##     every lane (Minions.wave_for) from that lane's defense post; a lane
##     whose post is destroyed or being rebuilt sends no wave. The top and
##     bottom lanes get 1
##     Patrol Leader (type "corvette"), 3 Snub-Fighters ("fighter") and 1
##     Light Bomber ("bomber"), the middle lane 2 Patrol Leaders, 5
##     Snub-Fighters and 4 Light Bombers. On top of that every lane gets one
##     extra Patrol Leader per TeamState.wave_corvettes (the Escort Wing
##     research). The minions of a lane leave 0.35 s apart, the Patrol
##     Leaders first (the research ones last).
##   - The escort_wing rule variant can change what Escort Wing does: with
##     "upgrade" its feature module (EscortWingFeature) sets
##     escort_upgrade. Then no corvette is added: the FIRST Patrol Leader of
##     each lane's wave is marked in the queue and upgraded as it launches
##     (EscortWingFeature.upgrade: +40% hull, +15% weapon range).
##   - Waves are not spawned at once: each minion is put in `queue` with
##     its launch time, and tick() spawns the ones whose time has come.
##     Minions launch from one of the 5 launch spots of their lane's defense
##     post (PostSite.launch_point), picked at random. A wave that has already
##     been queued launches even if the post falls meanwhile.
##
##   - The practice range (and nothing else) may hold the waves: set_frozen() empties the queue,
##     quietly removes every minion marked `free_wave` (the ones tick() launched; an Admiral's bought
##     minions stay) and keeps the time left to the next wave in `held_left`; send_one_wave() queues one
##     wave for both teams through _queue_wave() (refused at 63 live free-wave minions or inside 60 ticks
##     of the last send). Both are PracticeActions' calls.
##
## WHO USES IT: World makes one (World.minion_director) in WorldSetup and
## calls tick() every tick. The HUD's top bar reads next_wave.
## EscortWingFeature sets
## escort_upgrade. tick() sends Events.minion_launched for each free-wave
## minion it launches; BreachFeature, BreachExtraFeature and LanespawnFeature
## listen (nobody does by default).

## The match we send minions into.
var world: World
## Match time (seconds) of the next free wave. Starts at 45 s.
var next_wave := Minions.FIRST_WAVE
## Minions waiting to launch. Each entry is
## [launch time (s), team, type id, lane id], plus a fifth entry `true` on
## the first corvette of a lane's wave when it is marked for the Escort Wing
## upgrade (only with escort_upgrade).
var queue: Array = []
## The escort_wing variant's switch, set by its feature module
## (EscortWingFeature.install). false (the default, "extra") = today's
## game: Escort Wing research adds one corvette per lane to every free
## wave. true ("upgrade") = waves keep their size, and while the team has
## Escort Wing the first corvette of each lane's wave launches upgraded.
var escort_upgrade := false
## True while the practice range holds the free waves (set_frozen): no wave is due, the queue is
## empty and the clock is kept in `held_left`. Always false outside a practice range.
var frozen := false
## The time (seconds) that was left to the next wave when the waves were frozen (INF when no
## wave was due ever again).
var held_left := 0.0
## The tick of the last Send one wave press that went through (a long way back at the start).
var last_send_tick := -100000


## Remember the world. WorldSetup makes this once per match.
func _init(w: World) -> void:
	world = w


## How many live minions `team` has.
func alive_count(team: int) -> int:
	var n := 0
	for m: Minion in world.minions:
		if m.team == team and m.alive:
			n += 1
	return n


## Called by World every tick: start a new free wave when it is due, then
## launch every queued minion whose time has come. `_dt` is not used (we
## go by the match clock).
func tick(_dt: float) -> void:
	# Step 1: a new wave is due. Queue it for each team. (The gap to the next
	# wave is a tuned number, normally Minions.WAVE_INTERVAL.)
	if world.time >= next_wave:
		next_wave += float(Rules.tune("wave_interval", Minions.WAVE_INTERVAL))
		for team in 2:
			_queue_wave(team)
	# Step 2: launch the due minions (in queue order) and keep the rest. A
	# corvette marked for the Escort Wing upgrade (a fifth entry) gets it
	# as it launches.
	var keep: Array = []
	for q: Array in queue:
		if world.time >= float(q[0]):
			var m := _spawn(int(q[1]), q[2], q[3], true)
			# Tell the feature modules that listen (nobody does by default).
			if m != null:
				m.free_wave = true
				Events.minion_launched.emit(m, next_wave)
			if q.size() > 4 and m != null:
				EscortWingFeature.upgrade(m)
		else:
			keep.append(q)
	queue = keep


## Put one wave for `team` into the queue: the own wave of every lane whose
## defense post stands (Minions.wave_for), with the minions of a lane 0.35 s
## apart. A lane whose post is destroyed or being rebuilt gets none. With Escort
## Wing researched, each lane also gets the research corvettes; with
## escort_upgrade set, it gets none, and the first corvette of the lane's
## wave is marked for the upgrade.
func _queue_wave(team: int) -> void:
	var t0 := world.time
	var extra := world.teams[team].wave_corvettes
	# The "upgrade" variant marks a corvette instead of adding some (when the
	# team has Escort Wing).
	var mark := escort_upgrade and extra > 0
	for lane: String in MapLayout.LANE_ORDER:
		# Step 0: a lane whose post is not standing sends no wave.
		if not world.defense_posts.standing(team, lane):
			continue
		# Step 1: this lane's own wave.
		var wave: Array = Minions.wave_for(lane)
		# Step 2: today's game adds the research corvettes to every lane's wave.
		if not escort_upgrade:
			for k in extra:
				wave.append("corvette")
		# Step 3: queue the lane's minions. Under "upgrade" only the wave's
		# first corvette is marked (the middle lane has two).
		var marked := false
		for i in wave.size():
			if mark and not marked and wave[i] == "corvette":
				marked = true
				queue.append([t0 + 0.35 * float(i), team, wave[i], lane, true])
			else:
				queue.append([t0 + 0.35 * float(i), team, wave[i], lane])


## Launch one minion now, at a random one of 5 launch spots (one random
## number): those of the lane's defense post for a free wave (`from_post`
## true), else those of the mothership's bow (nothing in the game asks for
## that now). Returns null, and the minion is dropped, if the mothership is dead.
func _spawn(team: int, type_id: String, lane: String, from_post: bool = false) -> Minion:
	var ms := world.mothership(team)
	if ms == null or not ms.alive:
		return null
	var slot := randi() % 5
	var at := world.defense_posts.site_of(team, lane).launch_point(slot) if from_post else ms.launch_point(slot)
	return world.spawn_minion(team, type_id, lane, at)


# --- the practice range's two switches (only a practice range calls these) ---------------

## How many live free-wave minions `team` has (the minions the waves launched, not the ones an
## Admiral bought).
func free_wave_count(team: int) -> int:
	var n := 0
	for m: Minion in world.minions:
		if m.team == team and m.alive and m.free_wave:
			n += 1
	return n


## Hold the free waves (`on` true) or let them run again. Holding empties the launch queue,
## removes every live free-wave minion of both teams quietly (no pay, no kill message; minions an
## Admiral bought stay), keeps the time left to the next wave and sets the clock to never.
## Letting them run again puts the next wave the kept time away, but never less than
## PracticeSwitches.UNFREEZE_FLOOR seconds (a clock that was never due stays never).
func set_frozen(on: bool) -> void:
	if on == frozen:
		return
	frozen = on
	if on:
		held_left = next_wave - world.time
		next_wave = INF
		queue.clear()
		for m: Minion in world.minions.duplicate():
			if m.free_wave and m.alive:
				world.combat.kill_silently(m)
	elif not is_inf(held_left):
		next_wave = world.time + maxf(held_left, PracticeSwitches.UNFREEZE_FLOOR)


## Why Send one wave may not go now: a team already has PracticeSwitches.WAVE_REFUSE_AT or more
## free-wave minions alive, or the last send was less than PracticeSwitches.SEND_GAP_TICKS ticks
## ago. "" when it may.
func wave_refusal() -> String:
	if free_wave_count(0) >= PracticeSwitches.WAVE_REFUSE_AT or free_wave_count(1) >= PracticeSwitches.WAVE_REFUSE_AT:
		return PracticeSwitches.TEXT_WAVES_FULL
	if world.tick_count - last_send_tick < PracticeSwitches.SEND_GAP_TICKS:
		return PracticeSwitches.TEXT_WAIT
	return ""


## Queue one free wave for both teams now, the way the clock does (the same mix, the same spacing,
## the same launch spots), whether the waves are running or held. Returns "" or the reason it was
## refused (wave_refusal).
func send_one_wave() -> String:
	var why := wave_refusal()
	if why != "":
		return why
	last_send_tick = world.tick_count
	for team in 2:
		_queue_wave(team)
	return ""
