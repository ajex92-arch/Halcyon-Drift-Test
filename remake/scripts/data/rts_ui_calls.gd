class_name RtsUiCalls
extends RefCounted
## WHAT THIS IS: the small design calls of the command view (the Admiral's docked screen), each held as ONE
## constant, so a call that the user answers differently is a one-word change here and nowhere else.
##
## HOW IT WORKS: only constants, no code. Every screen of the command view (the card, the selection panel, the
## production panel, the strip, the command pause) reads the value from here and never copies it. Decisions 4 to 9
## of the design hold the designer's picks until the user answers; decisions 1 to 3 (who may pause, whether the
## team sees the orders given in a pause, orders while paused with humans on both teams) are data only, because
## only a match with one human is built.
##
## WHO USES IT: CommandView, CommandCard, SelectionPanel, ProductionPanel, TopStrip, CommandOverlay and HudPanels
## (the command pause); tests/rts_tour.gd checks that each screen follows the value in force.

## Decision 4: a left click on a selection tag narrows the selection to that squadron (its x removes it; Shift+click
## removes). False: a click on a tag does nothing and only the x removes.
const CHIP_CLICK_NARROWS := true
## Decision 5: the card page of a mixed selection (squadrons and the mothership). "orders": the squadrons win;
## "base": the mothership wins.
const MIXED_SELECTION_PAGE := "orders"
## Decision 6: every card cell prints its key in its top left corner. False hides the labels.
const KEY_LABELS_ON := true
## Decision 7: the look of a build cell the treasury cannot pay yet (the cell stays live: money never disables a
## cell). "bar": "short N" and a 2 px ore bar of the share you have; "wash": the cell is washed over in the danger
## colour, deeper the bigger the shortfall, with "short N" and the danger triangle. The user chose "wash" (Fri 11-06,
## box "Cannot pay": "Red wash").
const CANNOT_PAY_LOOK := "wash"
## Decision 8: dragging a production row's grip reorders the list. False: only the pick-then-arrows route works.
const DRAG_REORDER_ON := true
## Decision 9: seconds a started item's Cancel asks again ("sure?") before it cancels. 0.0 cancels at once.
const CANCEL_STARTED_CONFIRM_S := 3.0

## Decision 1: who may pause a match with more than one human ("any_seat": any human seat).
const PAUSE_WHO := "any_seat"
## Decision 1: seconds after a pause during which only the player who paused may resume.
const PAUSE_RESUME_LOCK_S := 10.0
## Decision 1: pauses a seat may call when humans play on both teams (no cap against the computer).
const PAUSE_MAX_PER_SEAT := 3
## Decision 2: do teammates see the orders given in a pause (dotted "on resume" lines)?
const PAUSE_TEAM_SEES_ORDERS := true
## Decision 3: are orders taken while paused when humans play on both teams?
const PAUSE_ORDERS_BOTH_TEAMS := false

## The command view also shows while the Admiral flies a ship (the grid keys are then the pilot's and off; every
## cell still clicks).
const COMMAND_VIEW_WHILE_FLYING := true
## RT7 A3: while the Admiral flies with the view closed (field mode) the view shows only its slim display: the strip, the
## first FIELD_ALERT_ROWS alerts, the group chips and the minimap. False: the full view shows in flight as before.
const FIELD_MODE_SLIM := true
## The alert rows the slim display shows (the full view shows ALERT_ROWS).
const FIELD_ALERT_ROWS := 3
## The Build page's Mothership-side facts: a card cell opens the board at the page that holds them (true), instead
## of a second copy of the page on the card.
const BOARD_BUILD_MOTHERSHIP_VIA_CARD := true

# --- the awareness screens (the alert feed, groups, army cards, minimap orders, far-zoom icons) ---------------

## The alert feed shows this many rows; older live alerts are behind its "+N older".
const ALERT_ROWS := 5
## The key that takes the camera back to where it was before a chain of alert jumps (the alert_back row).
const ALERT_BACK_KEY := "Shift+J"
## Idle squadrons are a count on the Idle card (false), not rows of the alert feed (true).
const IDLE_IN_FEED := false
## A squadron is in at most one group: setting it into a group takes it out of its old one. False: several.
const GROUP_ONE_PER_SQUAD := true
## Two taps of a group's key within this many seconds jump the camera to the group.
const GROUP_DOUBLE_TAP_S := 0.35
## Seconds the mouse rests on an army card before its detail opens.
const CARD_HOVER_S := 0.4
## A right click on the minimap gives Move to the selection (the setting's value until the player changes it).
const MINIMAP_ORDERS_ON := true
## The far-zoom icons replace the ships when the view is wider than this many world units (the icon line)...
const ICON_VIEW_W := 16000
## ...which the player may move between these two widths (the least, the most).
const ICON_VIEW_RANGE := [11000, 30000]
## The gap round the icon line, as a share of it: icons come on above the line and go off only this far under
## it, so a view resting on the line never flickers.
const ICON_GAP := 0.10

## The win-odds mark of the army cards (an option, off until the player turns it on in the pause menu): only enemy ships the
## human's team sees now count, and only those within this many world units of the middle of the card's squadrons (the radius the
## team view groups a fleet by)...
const WIN_ODDS_REACH := 3000.0
## ...and the stronger side's strength over the weaker one's, in permille, from which the mark says "likely win" or "likely loss"
## (under it: "even"). 1200 is the edge the strength fit measured: the stronger side won 89% from 1.2 to 1.5 and 96% from 1.5 up.
const WIN_ODDS_EDGE_PM := 1200
