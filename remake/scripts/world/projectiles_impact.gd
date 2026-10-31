class_name ProjectilesImpact
extends RefCounted
## WHAT THIS IS: what happens when a round hits something or runs out of
## time: the damage, the sparks and the flak bursts. A part of Projectiles,
## kept in its own file.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## Projectiles hands it itself and the round's slot number, and it reads
## that slot's facts (damage, burst radius, ...):
##   - hit(): the round touched a unit, a mothership or an asteroid.
##       * Flak that touches a unit bursts at that point: area damage to
##         every enemy inside its burst radius (Combat.area) and a burst
##         ring.
##       * Any other round damages just the unit it hit
##         (Combat.apply_damage; a torpedo's damage is first scaled by the
##         size and speed of that unit, BlastScale) and makes a spark in the team's colour
##         (a bigger one for torpedoes and shells). A torpedo of a Bomber's run
##         also counts the lane it flew in (Game.usage, torpedo_lane_hit_*).
##       * An asteroid stops the round. Capital guns ("cuts") chip it
##         (AsteroidField.damage). Flak shows its burst ring there but deals
##         no area damage; other rounds make a small rock-coloured spark.
##   - expire(): a flak round that runs out of time bursts where it is
##     (area damage and a ring). Other rounds just vanish.
##   - info(): fills in the DamageInfo note for a hit.
##   - dud(): a torpedo that touched something before it was armed.
## It never removes the round: Projectiles does that right after.
##
## WHO USES IT: only Projectiles._step().


## Round `i` of pool `proj` (weapon kind `k`, fired by team `my_team`) hit
## something at point `at`. `hit_unit` is the unit or mothership it hit, or
## null when it hit the asteroid described by `rock` ({"index", "t"} from
## AsteroidField.segment_hit()).
static func hit(proj: Projectiles, i: int, at: Vector2, hit_unit: Unit, rock: Dictionary, k: int, my_team: int) -> void:
	var w := proj.world
	if hit_unit != null:
		# A unit: flak bursts for area damage; anything else hurts only
		# the unit it hit.
		if k == Rules.W_FLAK:
			w.combat.area(info(proj, i, at), at, proj.burst[i], my_team)
			w.effects.flak_burst(at, proj.burst[i], Palette.bolt(my_team))
		else:
			# A torpedo's hit is scaled by the size and speed of what it hit
			# first (BlastScale); other rounds carry no blast size.
			var note := info(proj, i, at)
			BlastScale.apply(note, hit_unit)
			# A torpedo of a Bomber's run counts the lane it flew in, and what it
			# hit (counted before the hit, which may destroy the target).
			if proj.lane[i] >= 0:
				var lane_word: String = RunFan.LANE_WORDS[proj.lane[i]]
				Game.count_usage("torpedo_lane_hit_" + lane_word)
				Game.count_usage("torpedo_lane_hit_%s_%s" % [lane_word, RunFan.class_word(hit_unit)])
			w.combat.apply_damage(hit_unit, note)
			w.effects.spark(at, Palette.bolt(my_team), k == Rules.W_TORP or k == Rules.W_SHELL)
	else:
		# An asteroid: capital guns chip it, then show a burst or a spark.
		if proj.cuts[i] == 1:
			w.asteroids.damage(int(rock["index"]), proj.dmg[i])
		if k == Rules.W_FLAK:
			w.effects.flak_burst(at, proj.burst[i], Palette.bolt(my_team))
		else:
			w.effects.spark(at, Palette.ROCK_EDGE, false)


## Round `i` of pool `proj`, a torpedo that has not flown its arming distance
## yet, touched `hit_unit` (or a rock when it is null) at point `at`: it is a
## dud. It does nothing to the target (no damage, no shield touch, no blast, no
## sparks) and dies in a small grey puff. Game.usage counts it as torpedo_dud and
## torpedo_dud_<what it touched> ("rock", "small", "medium", "big", "structure"
## or "ms").
static func dud(proj: Projectiles, i: int, at: Vector2, hit_unit: Unit) -> void:
	proj.world.effects.puff(at, Palette.MIST, 5, 70.0)
	var word := "rock" if hit_unit == null else RunFan.class_word(hit_unit)
	Game.count_usage("torpedo_dud")
	Game.count_usage("torpedo_dud_" + word)


## Round `i` of pool `proj` (weapon kind `k`, team `my_team`) ran out of
## time at point `b`. Flak bursts there; other rounds do nothing here.
static func expire(proj: Projectiles, i: int, b: Vector2, k: int, my_team: int) -> void:
	if k == Rules.W_FLAK:
		proj.world.combat.area(info(proj, i, b), b, proj.burst[i], my_team)
		proj.world.effects.flak_burst(b, proj.burst[i], Palette.bolt(my_team))


## A new DamageInfo note for a hit by round `i` of pool `proj`: its raw
## damage, weapon kind, small-target bonus, shield skip (pierce), blast
## numbers and everything known about the shooter. The hit "comes from" where the round was one tick ago
## (prev[i]), so the shield zone facing the shot takes it. `_at` (the hit
## point) is not used.
static func info(proj: Projectiles, i: int, _at: Vector2) -> DamageInfo:
	var d := DamageInfo.new()
	# How hard, with what, and who fired it.
	d.amount = proj.dmg[i]
	d.kind = proj.kind[i]
	d.source_uid = proj.src_uid[i]
	d.source_team = proj.team[i]
	d.source_size = proj.src_size[i]
	d.source_is_minion = proj.src_minion[i] == 1
	d.source_is_pilot = proj.src_pilot[i] == 1
	d.source_profile = proj.src_profile[i]
	# The shooter itself, only if it still exists.
	var s = proj.src_ref[i]
	if s != null and is_instance_valid(s):
		d.source = s
	# Where it came from, its bonus against small targets and how much of it
	# skips the shields.
	d.from_pos = proj.prev[i]
	d.small_bonus = proj.small_bonus[i]
	d.pierce = proj.pierce[i]
	# The weapon's blast numbers, for BlastScale (0 for a weapon with none).
	d.blast_size = proj.blast_size[i]
	d.blast_speed = proj.blast_speed[i]
	d.blast_curve = proj.blast_curve[i]
	return d
