class_name Blink
extends RefCounted
## WHAT THIS IS: the one small helper that anything on the screen uses when it needs to
## blink or pulse. It cannot blink faster than three times a second, so no new effect
## can break the three-flashes-a-second rule.
##
## HOW IT WORKS: it answers "is the light on right now?" (phase) or "how bright is it, 0 to 1?"
## (pulse) from real time, not game time, because the HUD runs at full speed whatever the
## game speed is. The rate you ask for is clamped to MAX_HZ (a period of at least 333
## milliseconds); a rate of 0 or less means a steady light. The common blinks come with
## their own timings: an attention blink (ATTENTION_HZ, for ATTENTION_SECS seconds, then
## steady), a quieter caution blink (CAUTION_HZ, for CAUTION_SECS seconds, then steady) and
## a confirm flash (one pulse of CONFIRM_MS milliseconds, never repeated). Setting
## reduced_motion to true turns every blink into a steady light, for players who asked
## for less motion. The functions that end in _at take the time in milliseconds, so a test
## can ask about any moment; the others read the clock.
##
## WHO USES IT: any new blinking HUD mark; tests/flash_check.gd proves the limits. Every
## effect that changes brightness over time is listed in FlashTable.

## The most blinks a second anything may make (one on-off cycle is one blink).
const MAX_HZ := 3.0
## How fast an attention blink goes (blinks a second).
const ATTENTION_HZ := 2.0
## How long an attention blink lasts before it stays lit (seconds).
const ATTENTION_SECS := 3.0
## How fast a caution blink goes (blinks a second).
const CAUTION_HZ := 1.0
## How long a caution blink lasts before it stays lit (seconds).
const CAUTION_SECS := 3.0
## How long the one pulse of a confirm flash lasts (milliseconds).
const CONFIRM_MS := 120

## True makes every blink a steady light (a player's "reduced motion" choice sets it).
static var reduced_motion := false


## The rate to use for a request of `rate_hz` blinks a second: at most MAX_HZ, never negative.
static func clamp_rate(rate_hz: float) -> float:
	return clampf(rate_hz, 0.0, MAX_HZ)


## Is the light on at time `t_ms` (milliseconds) for a blink of `rate_hz` and a share `duty`
## (0 to 1) of each cycle spent on? A rate of 0 is always on. Does not look at reduced_motion.
static func phase_at(t_ms: int, rate_hz: float, duty: float = 0.5) -> bool:
	var hz := clamp_rate(rate_hz)
	if hz <= 0.0:
		return true
	var period := 1000.0 / hz
	return fposmod(float(t_ms), period) < clampf(duty, 0.0, 1.0) * period


## Is the light on now? Steady (true) while reduced_motion is on.
static func phase(rate_hz: float, duty: float = 0.5) -> bool:
	return true if reduced_motion else phase_at(Time.get_ticks_msec(), rate_hz, duty)


## How bright the light is at time `t_ms`, 0 to 1, rising and falling smoothly once per
## cycle at `rate_hz` (clamped). A rate of 0 is steady at 1. Does not look at reduced_motion.
static func pulse_at(t_ms: int, rate_hz: float) -> float:
	var hz := clamp_rate(rate_hz)
	if hz <= 0.0:
		return 1.0
	return 0.5 - 0.5 * cos(TAU * hz * float(t_ms) / 1000.0)


## How bright the light is now, 0 to 1; steady (1) while reduced_motion is on.
static func pulse(rate_hz: float) -> float:
	return 1.0 if reduced_motion else pulse_at(Time.get_ticks_msec(), rate_hz)


## An attention blink that started at `started_ms` (a Time.get_ticks_msec() value): on or off now
## while it runs, steady after ATTENTION_SECS seconds. For things that need the player's eye
## (under attack, lost).
static func attention(started_ms: int, now_ms: int = -1) -> bool:
	return _timed(started_ms, now_ms, ATTENTION_HZ, ATTENTION_SECS)


## A caution blink: like attention() but slower (CAUTION_HZ) and for CAUTION_SECS seconds.
static func caution(started_ms: int, now_ms: int = -1) -> bool:
	return _timed(started_ms, now_ms, CAUTION_HZ, CAUTION_SECS)


## A confirm flash that started at `started_ms`: 1 (lit) for CONFIRM_MS milliseconds, then 0 and
## never again.
static func confirm(started_ms: int, now_ms: int = -1) -> float:
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var age := now - started_ms
	if reduced_motion:
		return 1.0 if age >= 0 and age < CONFIRM_MS * 4 else 0.0
	return 1.0 if age >= 0 and age < CONFIRM_MS else 0.0


## The shared part of attention() and caution(): blink at `hz` for `secs` seconds from `started_ms`,
## then stay on. Steady while reduced_motion is on.
static func _timed(started_ms: int, now_ms: int, hz: float, secs: float) -> bool:
	if reduced_motion:
		return true
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var age := now - started_ms
	if age < 0 or float(age) >= secs * 1000.0:
		return true
	return phase_at(age, hz)
