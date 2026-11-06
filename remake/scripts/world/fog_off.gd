class_name FogOff
extends RefCounted
## WHAT THIS IS: the one question behind the test option "No fog": does the human's screen show
## everything? When it is on, the fog of war is not drawn for the human's team: every enemy ship and
## building shows, and so do the shots, explosions and sounds that the fog would hide (even in gas
## clouds and hidden pockets). It exists so a tester can see the whole match at once.
##
## HOW IT WORKS: the option is one setting, Game.fog_off (the start screen's toggle, remembered between
## runs, or the launch option --fog-off). is_on() is the only place that reads it, and every place that
## draws or shows something for the human's team asks it. It is DISPLAY ONLY: it never touches Vision's
## lists, any unit's visible_mask or seen_mask, World.viewer_team, any computer player's sight or the
## Admiral's placing rules. A match plays exactly as it would without the option.
##
## WHO USES IT: the HUD top bar (the FOG OFF tag and the enemy turret and post counts), FogView (the fog
## picture is hidden), WorldVisibility and WorldRegistry (units are shown), WorldSetup (the viewer copies
## of the shots and effects), the minimap, Sfx, SiteMarks, the scoreboard, FanPaint, the help panel, the
## recorder's note and tests/fog_check.gd.


## Is the "No fog" option on right now? True means the human's screen shows everything.
static func is_on() -> bool:
	return Game.fog_off
