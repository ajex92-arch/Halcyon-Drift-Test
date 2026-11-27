class_name CalloutData
extends RefCounted
## WHAT THIS IS: the table of the ten spoken callout lines ("Attack here", "Yes" and so on), and the
## rule for who hears one. A callout is a short voice line a team says out loud: the same line is
## said for a wheel call, an accepted order or a refusal.
##
## HOW IT WORKS: every line has an id (a name from ORDER), the words it says (text) and, until real
## recorded voices exist, a short placeholder tone pattern (notes) that Sfx bakes into a sound. Code
## that wants a line said calls say(team, line), which only sends Events.callout; it changes nothing
## in the match and uses no random number. Sfx listens and plays the line when hears() says the team
## on screen is the team that spoke. The line is heard wherever the speaker is on the map, in the fog
## or not, because it ignores the camera.
##
## WHO USES IT: Sfx (the sound player) bakes the placeholder sounds from LINES and asks hears() and
## gap_of() before each play. Anything that sends a spoken call uses say(). tests/callout_check.gd
## checks the table and the rule.

## The ten line ids, in the team wheel's order for the first eight (attack, defend, on my way, can't,
## retreat, need repair, need support, danger), then "yes" (an order was accepted) and
## "admiral_answer" (the Admiral answered a request).
const ORDER := ["attack", "defend", "on_my_way", "cant", "retreat", "need_repair", "need_support", "danger", "yes", "admiral_answer"]

## The lines. Each id maps to {"text": the words the line says, "notes": the placeholder tone
## pattern}. A note is [pitch in hertz, length in seconds, wave shape]; the notes of a line play one
## after the other. The tones stand in until recorded voices replace them.
const LINES := {
	"attack": {"text": "Attack here", "notes": [[520, 0.07, "triangle"], [780, 0.09, "triangle"]]},
	"defend": {"text": "Defend here", "notes": [[780, 0.07, "triangle"], [520, 0.09, "triangle"]]},
	"on_my_way": {"text": "On my way", "notes": [[600, 0.05, "sine"], [600, 0.05, "sine"], [820, 0.08, "sine"]]},
	"cant": {"text": "Can't", "notes": [[220, 0.14, "saw"]]},
	"retreat": {"text": "Retreat or regroup", "notes": [[700, 0.06, "triangle"], [560, 0.06, "triangle"], [420, 0.08, "triangle"]]},
	"need_repair": {"text": "Need repair", "notes": [[440, 0.1, "sine"], [330, 0.12, "sine"]]},
	"need_support": {"text": "Need support", "notes": [[440, 0.1, "sine"], [550, 0.12, "sine"]]},
	"danger": {"text": "Danger", "notes": [[880, 0.06, "square"], [880, 0.06, "square"], [880, 0.08, "square"]]},
	"yes": {"text": "Yes", "notes": [[660, 0.09, "sine"]]},
	"admiral_answer": {"text": "Understood", "notes": [[660, 0.07, "sine"], [880, 0.09, "sine"]]},
}

## The line each team wheel slice says: the slice's number is the index (the first eight ids of ORDER,
## in the wheel's order).
const SLICE_LINES := ["attack", "defend", "on_my_way", "cant", "retreat", "need_repair", "need_support", "danger"]

## The lines that nothing sends yet: the two Need slices do nothing so far, and the Admiral's answer
## waits for a request path that does not exist.
const HOOKLESS := ["need_repair", "need_support", "admiral_answer"]

## Whether a spectator (a viewer on no team) hears the lines. false: only a team's own pilots hear it.
const SPECTATOR_HEARS := false

## The least gap, in real-time seconds, between two plays of the same line. Every line has it except
## "danger", which is never held back.
const GAP_S := 0.5

## How loud a spoken line is, as a share of the sound player's full volume (1.0 = the same as other
## sounds).
const VOICE_GAIN := 1.0


## Does a viewer on team `viewer_team` hear a line said by team `sender_team`? Only the sender's own
## team does, wherever on the map the sender is. A viewer on no team (-1, a spectator) hears it as
## SPECTATOR_HEARS says.
static func hears(viewer_team: int, sender_team: int) -> bool:
	if viewer_team < 0:
		return SPECTATOR_HEARS
	return viewer_team == sender_team


## The least gap (real-time seconds) between two plays of line `line`: 0.0 for "danger" (every call
## plays), GAP_S for any other.
static func gap_of(line: String) -> float:
	if line == "danger":
		return 0.0
	return GAP_S


## Say line `line` (an id from ORDER) for team `team`: send Events.callout and nothing else. It draws no
## random number, changes no match state and does not check who is playing; the sound player decides
## who hears it.
static func say(team: int, line: String) -> void:
	Events.callout.emit(line, team)
