class_name RunGun
extends RefCounted
## WHAT THIS IS: the "torpedo run" of the Bomber's torpedo gun: the hold, the
## wait for the release, the launch, the cancel and the reload. A part of
## WeaponMount, kept in its own file (one RunGun for each gun that has a
## "windup" in Weapons).
##
## HOW IT WORKS: a run goes through these steps, one small step of the game (a
## "tick", 60 a second) at a time:
##   1. HOLD     the pilot holds the fire button. From the first tick the ship's
##               heading is locked (Ship.run_locked()) and the bar fills for
##               `wind_ticks` ticks (90, 1.5 s). Letting go before the bar is
##               full is a free cancel: nothing is fired, nothing to wait for.
##   2. READY    the bar is full and the torpedoes wait. The pilot keeps holding
##               while the fan of torpedo lanes keeps closing, for up to
##               `ready_ticks` more ticks (90). Letting go now LAUNCHES. When
##               the READY ticks run out (180 ticks held in all) the torpedoes
##               leave by themselves.
##   3. LAUNCH   pays the run's energy once and sends the torpedoes (see
##               fire_fan() for the fan), all on the same tick. If the battery
##               cannot pay, the run ends with nothing fired and no reload
##               (counted as torpedo_runs_unpaid).
##   4. RELOAD   `reload_ticks` ticks (60, 1 s, shorter with fire-rate gear)
##               from the launch. No new hold can start before it is over, and
##               not before the fire button has been let go and pressed again.
## A run can also be cancelled at any moment of the hold and READY, free: by
## the cancel input (ShipControls.cancel_run: the human's right click, the
## computer pilots' own cancel) or by touching a rock (ShipFlight.move()).
## Nothing is fired and nothing has to reload after a cancel.
## Ship calls pre() before the ship flies (the reload, the cancel input and the
## start of a hold, so the heading is locked from the very first tick of the
## hold and stays locked on the tick the button is let go) and the mount calls
## tick() after, where the hold counts, the release is read and the launch
## happens.
## Every start, cancel and launch is counted in Game.usage (torpedo_runs_*).
##
## WHO USES IT: WeaponMount makes one for a gun with a wind-up, calls tick() and
## fire_fan(); Ship calls pre() and reads on, wind_frac(), ready_frac() and
## reload_frac(); ShipFlight.move() calls cancel(); RunPaint draws its state;
## PilotRun and the tests read its fields.

## Ticks of the hold until the bar is full (the weapon's "windup", 1.5 s).
var wind_ticks := 0
## Ticks the torpedoes may wait once the bar is full (the weapon's "ready").
var ready_ticks := 0
## Ticks of the reload after a launch (the weapon's "reload", before the
## fire-rate multiplier).
var reload_ticks := 60
## Energy a run costs, paid at the launch (the weapon's "energy"). A hold
## starts only while the battery holds at least this much.
var cost := 0.0

## True while a run is on: the hold or READY. The heading is locked while it is.
var on := false
## Ticks of the hold counted so far, 0 to `wind_ticks`.
var wind := 0
## Ticks of READY counted so far, 0 to `ready_ticks`.
var ready := 0
## Ticks of reload left after the last launch (0 = the gun is ready).
var reload := 0
## True from a launch or a cancel with the fire button still down, or from a
## press during the reload, until the fire button is let go: a new run needs a
## fresh press.
var need_press := false
## How many holds have begun. A new number marks a new run (the HUD shows an
## alarm once for each).
var serial := 0


## Read the weapon's run numbers from its entry `def` in Weapons.
func _init(def: Dictionary) -> void:
	wind_ticks = int(round(float(def.get("windup", 0.0)) * 60.0))
	ready_ticks = int(round(float(def.get("ready", 0.0)) * 60.0))
	reload_ticks = int(round(float(def.get("reload", 1.0)) * 60.0))
	cost = float(def.get("energy", 0.0))


## How far the hold is, 0..1 (0 = no run on). The bar fills with it.
func wind_frac() -> float:
	return clampf(float(wind) / float(maxi(1, wind_ticks)), 0.0, 1.0) if on else 0.0


## True when the bar is full: a release now launches.
func is_full() -> bool:
	return on and wind >= wind_ticks


## How much of the READY wait is left, 1 at the moment the bar fills and 0 when
## the torpedoes leave by themselves (0 while there is no run in READY).
func ready_frac() -> float:
	return 1.0 - clampf(float(ready) / float(maxi(1, ready_ticks)), 0.0, 1.0) if is_full() else 0.0


## How much of the reload is left, 1 at the launch and 0 when the gun is ready.
func reload_frac() -> float:
	return clampf(float(reload) / float(maxi(1, reload_ticks)), 0.0, 1.0) if reload > 0 else 0.0


## The part of the tick before the ship flies, for gun `m`: the reload counts
## down, the cancel input is carried out (`cancel_input`: the run ends, free),
## and a new hold begins when the fire button is down (`trigger`), no reload or
## fresh-press rule is in the way and the battery `energy` holds the run's cost
## (a null battery is endless). Called by Ship._requests().
func pre(m: WeaponMount, trigger: bool, cancel_input: bool, energy: EnergyPool) -> void:
	if reload > 0:
		reload -= 1
	# A press that begins while the gun is still reloading is ignored until the
	# button has been let go and pressed again.
	if not trigger:
		need_press = false
	elif reload > 0 and not on:
		need_press = true
	if cancel_input and on:
		Game.count_usage("torpedo_runs_cancelled")
		Game.count_usage("torpedo_runs_cancel_input")
		_end(trigger)
	elif not on and trigger and not need_press and reload == 0 and (energy == null or energy.value >= cost):
		on = true
		wind = 0
		ready = 0
		serial += 1
		Game.count_usage("torpedo_runs_started")
	m.cd = float(reload) / 60.0


## The part of the tick after the ship has flown: count the hold, read the
## release and launch. `trigger` is the fire button, `fire_mult` the ship's
## fire-rate multiplier (it shortens the reload), `dmg_mult` its damage
## multiplier (with the one-shot bonus of the Focus shot), `range_mult` its
## reach multiplier and `energy` its battery (null = free). Called by
## WeaponMount.update().
func tick(m: WeaponMount, trigger: bool, fire_mult: float, dmg_mult: float, range_mult: float, energy: EnergyPool) -> void:
	# The mount's cooldown is the time left of the reload, in seconds.
	m.cd = float(reload) / 60.0
	if not on:
		return
	if trigger:
		# Holding: first the bar fills, then READY counts. When the READY wait
		# runs out the torpedoes leave by themselves.
		if wind < wind_ticks:
			wind += 1
		else:
			ready += 1
			if ready >= ready_ticks:
				_launch(m, true, fire_mult, dmg_mult, range_mult, energy, true)
		return
	# The button was let go: a full bar launches, anything less is a free cancel.
	if wind >= wind_ticks:
		_launch(m, false, fire_mult, dmg_mult, range_mult, energy, false)
	else:
		Game.count_usage("torpedo_runs_cancelled")
		_end(false)


## End the run now with nothing fired and no reload, because the ship touched
## something solid (a rock, a structure or a wall). `trigger` is whether the
## fire button is still down, which then has to be let go before the next run.
## Does nothing when no run is on. Called by ShipFlight.move().
func cancel(trigger: bool) -> void:
	if not on:
		return
	Game.count_usage("torpedo_runs_cancelled")
	Game.count_usage("torpedo_runs_cancel_rock")
	_end(trigger)


## Pay for the run and send the torpedoes of gun `m`. `auto` is true when the
## READY wait ran out. The reload begins; a button still held (`trigger`) needs
## a fresh press for the next run.
func _launch(m: WeaponMount, trigger: bool, fire_mult: float, dmg_mult: float, range_mult: float, energy: EnergyPool, auto: bool) -> void:
	if energy != null and cost > 0.0 and not energy.spend(cost):
		Game.count_usage("torpedo_runs_unpaid")
		_end(trigger)
		return
	m.fire_fan(dmg_mult * m.next_mult, range_mult)
	m.next_mult = 1.0
	Game.count_usage("torpedo_runs_launched")
	if auto:
		Game.count_usage("torpedo_runs_launched_auto")
	reload = maxi(1, int(round(float(reload_ticks) / maxf(0.01, fire_mult))))
	m.cd = float(reload) / 60.0
	_end(trigger)


## The run is over: forget the hold. A fire button still held (`trigger`) must be
## let go before the next run.
func _end(trigger: bool) -> void:
	on = false
	wind = 0
	ready = 0
	need_press = trigger
