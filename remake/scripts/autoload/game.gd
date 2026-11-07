extends Node
## WHAT THIS IS: the game's settings desk (the autoload "Game"). It holds
## the launch options typed on the command line, the chosen rule
## variants, the difficulty, a link to the running match, the tuned numbers
## that feature modules changed for this match, and the feature usage counts.
## It keeps the settings that are remembered between runs (the last
## difficulty pick, the team the human plays for and the test option "Unlock
## everything", the two wing switches, and the player's own key changes; all in a small settings file in the
## user's data folder), sets up the
## keyboard and mouse controls and
## listens for the fullscreen key (F11 or Alt+Enter, see WindowMode).
##
## HOW IT WORKS: an "autoload" is a script Godot starts before everything
## else and keeps running; every file can reach it by its name, `Game`.
## In _ready() it:
##   1. reads the options written after `--` on the command line
##      (_parse_options), such as `godot -- --auto --seed=7`;
##   2. fills in the rule variants: the defaults from
##      Rules.VARIANT_DEFAULTS, then the preset named by --preset (Council's
##      pick, the standard rules, when none is named; CouncilPresets), then
##      the pairs of --variant;
##   3. defines the controls ("input actions") through GameInputMap;
##   4. sets the window's smallest size, 1280 x 720 (WindowMode).
## The start screen may choose the difficulty (choose_difficulty()), the team
## (choose_team()), the test option "Unlock everything" (choose_unlock()) and the two
## wing switches (choose_test_wing(), choose_cpu_wings()) and the test option "No fog"
## (choose_fog_off())
## later, before the match is built. The rules are not chosen on a screen.
## Other files then ask Game.opt("name") or Game.variant("name").
## Two lists belong to the feature modules (scripts/features/, see
## FeatureRegistry): `tunables` (numbers a feature changed for this match;
## Rules.tune() reads them) and `usage` (how often a feature's mechanic was
## used; count_usage() adds to it). Both start empty, which means "today's
## game", and WorldSetup empties them again whenever a match is built.
##
## WHO USES IT: main.gd reads most of the options below; WorldSetup reads
## the --no-* switches, sets Game.world and empties tunables and usage;
## the mothership's retreat, the admiral board and FeatureRegistry ask
## Game.variant(), and MainReport writes all the variants into the
## end-of-match summary; feature modules write tunables and call
## count_usage(); Rules.tune() reads tunables; the fun probe prints usage;
## PilotAI and SkillJitter read --skill-jitter and --seed; tests read
## their own options (such as --secs); the end screen clears Game.world
## before a new match, and the pause menu's Restart and Quit to start go
## through restart_match() and quit_to_start() (they load the main scene again;
## main.gd then starts the match in restart_role at once, or shows the start
## screen when it is empty). The start screen calls use_remembered_difficulty() and
## choose_difficulty() (its difficulty buttons), use_remembered_team() and
## choose_team() (its team buttons) and use_remembered_unlock() and
## choose_unlock() (its Unlock everything toggle), use_remembered_fog_off() and
## choose_fog_off() (its No fog toggle), use_remembered_wings(),
## choose_test_wing() and choose_cpu_wings() (its two wing switches),
## use_remembered_keys() (the player's own
## keys, put on the controls) and reads preset_error;
## WorldSetup reads `difficulty` and `human_team` when it builds a match; UnlockAll
## is the one place that reads `unlock_everything`, FogOff the one that reads `fog_off`;
## and FeatureRegistry reads
## preset_error, difficulty_error and team_error; NoteWriter reads `preset`. ReplayOptions
## fills the options from the first line of a --replay log (while this file reads the command
## line), main.gd sets `match_seed`, and MatchRecorder, OrderLog and BuildId read the recording
## options (--record, --recordings-dir, --build ...).
##
## The options (who reads them in brackets):
##   --role=pilot|admiral|spectator   the human's seat. Without --auto (and
##                                    with a window) the start screen asks
##                                    instead; with --auto the default is
##                                    pilot. (main.gd)
##   --auto                           skip the start screen and use --role;
##                                    the human (pilot or admiral) buys a
##                                    Fighter and launches at once, unless
##                                    --bot is given. (main.gd)
##   --all-ai                         no human ship; the human only watches
##                                    (spectator) and everyone else is AI.
##                                    (main.gd)
##   --seed=N                         the match's random seed: main.gd
##                                    seeds the shared random sequence with
##                                    N before the match is built, so the
##                                    same N plays the same match. The map
##                                    layout is fixed and doesn't use it.
##   --variant=retreat:none,escort_wing:upgrade
##                                    rule variants as name:value pairs
##                                    (names and values: see
##                                    Rules.VARIANT_DEFAULTS). A variant
##                                    that has a feature module switches
##                                    it on (FeatureRegistry).
##   --variant-team0=<pairs>, --variant-team1=<pairs>
##                                    the same name:value pairs as --variant,
##                                    but each holds for ONE team's AI only
##                                    (team 0 = Aurelian, the amber team on the
##                                    left; team 1 = Vhorr, the red team). For
##                                    tests of an AI change: "the new AI against
##                                    today's AI". A name that is not in
##                                    Rules.VARIANT_DEFAULTS, or a pair that is
##                                    not name:value, stops the match at its
##                                    start (FeatureRegistry, exit code 3).
##                                    Without them every match plays as always.
##                                    Read into Game.team_variants.
##                                    (FeatureRegistry.is_on_for())
##   --preset=none|within|pick        the rules, for tests and research: a
##                                    named --variant string
##                                    (CouncilPresets). The preset is
##                                    applied first, then --variant, so
##                                    --variant can change one of its keys.
##                                    Without it the match plays "pick"
##                                    (Council's pick), the standard rules.
##                                    "none" is the old standard rules (every
##                                    variant at its default). No screen offers
##                                    the choice. An unknown name stops the
##                                    match at its start (FeatureRegistry,
##                                    exit code 3). (Game, StartScreen)
##   --difficulty=<level>             the difficulty of a single-player match
##                                    (easy, medium, hard, very_hard or
##                                    extreme; Difficulty): how much the enemy
##                                    team earns. Without it the match is on
##                                    Medium, or on the level last picked on the
##                                    start screen when a person plays. A match
##                                    with no human seat is never affected. An
##                                    unknown word stops the match at its start
##                                    (FeatureRegistry, exit code 3). Read into
##                                    Game.difficulty. (Difficulty, WorldSetup)
##   --team=aurelian|vhorr            the team the human plays for (Aurelian, the
##                                    amber team on the left of the map, or Vhorr,
##                                    the red team on the right), whichever seat
##                                    (pilot or admiral) is taken; the other team
##                                    is all computer. Without it the match is on
##                                    Aurelian, or on the team last picked on the
##                                    start screen when a person plays. A match
##                                    with no human seat is never affected. Any
##                                    capitals are fine; an unknown word stops
##                                    the match at its start (FeatureRegistry,
##                                    exit code 3). Read into Game.human_team.
##                                    (Rules.team_from_name(), WorldSetup)
##   --unlock-all                     test option: the human can buy anything at
##                                    once and for nothing (every ship class,
##                                    module, gear item and repair kit; for an
##                                    Admiral every unit, building and research,
##                                    with the research and facility rules
##                                    waived), and the HUD shows UNLOCKED. A bare
##                                    switch; "=0" or "=false" turns it off even
##                                    if the start screen remembered it on.
##                                    Computer pilots, the other team and the
##                                    computer Admirals play normally. Read into
##                                    Game.unlock_everything. (UnlockAll)
##   --fog-off                        test option: the human's screen shows everything
##                                    (no fog of war, every enemy ship and building,
##                                    shots, explosions and sounds). Only the screen
##                                    changes: the match, the AI and the Admiral's
##                                    placing rules are as they are. A bare switch;
##                                    "=0" or "=false" turns it off even if the start
##                                    screen remembered it on. Read into Game.fog_off.
##                                    (FogOff)
##   --wingmen=<hull,hull,hull>       test option: every pilot seat of both teams
##                                    gets a wing of these hulls (up to three, any
##                                    hull id; "off" or empty = none; an unknown
##                                    id is ignored with a printed warning). It
##                                    wins over the two switches below for every
##                                    seat. (Game.wing_hulls_for, Squads)
##   --test-wing                      test option: the human pilot's seat gets a
##                                    Scout, a Fighter and a Bomber as wingmen. A
##                                    bare switch; "=0" or "=false" turns it off
##                                    even if the start screen remembered it on.
##                                    Read into Game.test_wing. (Squads)
##   --cpu-wings                      test option: every computer pilot seat gets
##                                    the same three wingmen. A bare switch; "=0"
##                                    or "=false" turns it off. Read into
##                                    Game.cpu_wings. A run with no start screen
##                                    and none of these options has no wings.
##                                    (Squads)
##   --slow=<0.05 to 1>               test option: the match starts with its
##                                    world slowed to this speed (0.75 and 0.5
##                                    are the two the backquote key steps to;
##                                    1 is normal). The World takes a tick on
##                                    some physics frames only, so every tick is
##                                    the full length and the match plays out
##                                    as at normal speed, only slower to watch.
##                                    Not --speed: that scales Godot's time,
##                                    which changes the length of every tick.
##                                    (WorldSetup, WorldSpeed)
##   --fast=<1 to 2>                  test option: the match starts with its
##                                    world faster than normal (1.5 and 2 are
##                                    the speeds the game offers; any number
##                                    from 1 to 2 is taken so a determinism run
##                                    can try it). Godot's physics ticks a second
##                                    and its time scale are raised together, so
##                                    every tick is still the full length and the
##                                    match is the same, only quicker.
##                                    (WorldSetup, WorldSpeed)
##   --skill-jitter[=S]               fun tests: every AI pilot seat's skill
##                                    gets its own random nudge of up to S
##                                    either way (0.20 when no S is given),
##                                    from a generator seeded by --seed, the
##                                    same for that seat on both teams.
##                                    Without it skills are unchanged.
##                                    (PilotAI, SkillJitter)
##   --max-minutes=N                  tests: stop after N minutes of match
##                                    time. (main.gd)
##   --bot=<scenario>                 tests: a test script flies the human.
##                                    main.gd only checks that it is given
##                                    (then no automatic Fighter launch).
##   --shots=<dir>                    tests: the folder for screenshots
##                                    taken on a tour. (ui_tour,
##                                    spectate_shots)
##   --speed=N                        tests: run the game N times as fast
##                                    (Engine.time_scale). Not the faithful
##                                    speed: it stretches every tick; see
##                                    --fast. (main.gd)
##   --sim-only                       tests: a speed mode for windowless runs.
##                                    Everything that only draws or sounds
##                                    is skipped (unit pictures, shot and
##                                    effect drawing, sound cues, HUD,
##                                    camera); the match is exactly the same
##                                    as without it (tests/det_hash.gd proves
##                                    it). Read into Game.sim_only. (main.gd,
##                                    Effects, UnitVisual, ShipVisual and
##                                    others)
##   --bench-off=flames,arcs,...      tests: leave single parts of the ship
##                                    and unit drawing out, to measure what
##                                    each costs: flames, arcs, arrow,
##                                    bars, name, outline, redraw (or all).
##                                    Without it every part is drawn as
##                                    always. Read once into DrawParts.
##                                    (DrawParts, ShipVisual, UnitVisual,
##                                    CinderPaint, the hull gallery's parts
##                                    bench)
##   --no-tail-gun                    tests: the Bomber is built without its rear
##                                    gun (the tail gun), to measure what the
##                                    gunner adds. A bare switch. (Ship.setup)
##   --weapons=<ids>, --targets=<ids>  tests: the weapon ids and the target ids
##                                    the time-to-kill table measures (comma
##                                    separated; all of them when not given).
##                                    (tests/ttk_table.gd)
##   --cells=<names>, --runs=<n>      tests: the cells of the fan probe to
##                                    measure (hit, defense, ttk, fighter;
##                                    all when not given) and how many duels
##                                    each cell flies (20). (tests/fan_probe.gd)
##   --damage-modifiers-removed       play with the damage modifiers removed:
##                                    every hit does its raw damage to every
##                                    kind of target (DESIGN.md A5). A bare
##                                    switch; "=0" or "=false" turns them back
##                                    on. Without it the match uses
##                                    Rules.DAMAGE_MODIFIERS_REMOVED. Read
##                                    into Game.damage_modifiers_removed.
##                                    (Rules.damage_modifiers_removed())
##   --big-hull-flight                the corvettes, frigates, destroyers and
##                                    battlecruisers fly as ships of the line:
##                                    swivelling main engines, weak reverse and
##                                    side thrusters (DESIGN.md A5). A bare
##                                    switch; "=0" or "=false" gives them the
##                                    flight of the other hulls. Without it the
##                                    match uses Rules.BIG_HULL_FLIGHT. Read
##                                    into Game.big_hull_flight.
##                                    (Rules.big_hull_flight())
##   --profile                       print the cost of each part of the
##                                    simulation every minute. (main.gd)
##   --report=<path>                  also write the end-of-match summary
##                                    (JSON) to this file. (main.gd)
##   --big-fight=N                    the pacing warning in the match log: how
##                                    many ships a fight needs to count as
##                                    big in the first ten minutes (10 when
##                                    not given). No such fight by 10:00 =
##                                    one WARN line. (FightWatch)
##   --record-stats[=<file>]          write how each pilot fought (shots and
##                                    hits per weapon, damage dealt and
##                                    taken, kills, hulls flown ...), for the
##                                    human and every AI pilot, to this file
##                                    as JSON: once a minute and at the end.
##                                    It only watches (the match is the same
##                                    with or without it) and works in a
##                                    normal window match too. Without a
##                                    name: user://halcyon_stats.json.
##                                    (main.gd, StatsRecorder)
##   --feedback-dir=<folder>          where the note key (F9) puts its notes and
##                                    screenshots. Without it: user://feedback.
##                                    Tests use it so they never write among
##                                    the player's real notes. (NoteWriter)
##   --test=<name>                    run the test script tests/<name>.gd.
##                                    (main.gd)
##   --snap=<png>                     save one screenshot after 1.5 s and
##                                    quit. (main.gd)
##   --force-hud                      build the HUD even with no window, for
##                                    UI tests. (main.gd)
##   --no-pilots / --no-jungle / --no-admiral-ai
##                                    strip systems out for tests: no AI
##                                    pilots, no jungle monster camps, no AI
##                                    admirals. (WorldSetup)
##   --no-admiral-field               the computer admiral never takes the
##                                    field in its own ship (it keeps its
##                                    seat, so the economy is the same). For
##                                    tests that compare with and without
##                                    the trips. (AdmiralField)
##   --order-log[=<file>]             write the match log: the header, every
##                                    order that was carried out or refused (who
##                                    sent it, which tick), and a fingerprint of
##                                    the game every 300 ticks. Without a name:
##                                    user://orders_<seed>.log. The web build
##                                    writes none. (OrderLog)
##   --replay=<file>                  play a recorded match back: the human's
##                                    orders, flight controls and hangar commands
##                                    from the match log, with the settings the
##                                    log's first line names (seed, seat, team,
##                                    rules; ReplayOptions) unless an option here
##                                    says otherwise, and compare the fingerprints:
##                                    prints "replay: ok" or "replay: MISMATCH".
##                                    Headless or in a window. (OrderQueue)
##   --admiral-replay=<file>          play the computer Admirals' orders of a
##                                    match log back instead of letting them
##                                    think (use --no-admiral-field and the same
##                                    seed). (OrderQueue)
##   --det-extra                      tests/det_hash.gd prints one more line
##                                    after each hash line: orders carried
##                                    out, orders waiting, events, speed.
##                                    (det_hash)
##   --build=<text>                   a label for the build, written in the match
##                                    log's first line (build=). Without it the
##                                    build names itself: build_id.txt (the Windows
##                                    export writes it), the stamp of a version
##                                    controlled export, else "unknown". (BuildId)
##   --record / --no-record           the match recorder: --record records this
##                                    match (the match log with the human's flight
##                                    controls and hangar commands, its stats and its
##                                    match series) even in a test run; --no-record
##                                    records nothing. Without either a match a person
##                                    plays from the start screen is recorded, and no
##                                    test run is. The web build writes none.
##                                    (MatchRecorder)
##   --recordings-dir=<folder>        where the recorder puts its files. Without it:
##                                    user://recordings. Tests use it so they never
##                                    write among the player's real recordings.
##   --record-name=<name>             the recorder's file name without the extension
##                                    (the files are <name>.log, <name>.stats.json and
##                                    <name>.series.json). Without it: match_ and the
##                                    date and time, then the seed. (MatchRecorder)
##   --replay-until=<time>            with --replay: stop there, at that match time in
##                                    seconds or m:ss, and say so. (OrderQueue)
##
## The controls are defined in code (GameInputMap), not in project.godot,
## so they are easy to read and tests can press them by name.

## The running match (a World), or null between matches. WorldSetup sets
## it when a match is built; the end screen clears it before a new match.
var world: Node = null
## The seat the next match starts in at once, without the start screen: "pilot",
## "admiral" or "spectator". Empty (the usual state) means "show the start
## screen". restart_match() sets it just before the main scene loads again;
## main.gd reads it there and empties it.
var restart_role := ""
## The command-line options: name (without the "--") -> value. "--seed=7"
## gives "seed" -> "7" (always text); a bare "--auto" gives "auto" -> true.
var options := {}
## The seed the running match was built with: the --seed option, or a number picked at the match's start
## when none was given (main.gd picks it so that the match recording can name it and a replay can play
## the same match). -1 until main.gd's start() sets it.
var match_seed := -1
## The rule variants for this match: variant name -> chosen value (text).
## Starts as a copy of Rules.VARIANT_DEFAULTS; the preset (--preset, or
## CouncilPresets.STANDARD) and then --variant change entries.
var variants := {}
## The per-team rule variants (--variant-team0 and --variant-team1): two
## Dictionaries, index 0 for team 0's AI and index 1 for team 1's AI, each
## variant name -> value (text) for the names that team's AI holds on its own.
## Both are empty (the default) when no per-team option is given, and then
## every match plays as always. Set by _parse_options(); read through
## variant_for().
var team_variants: Array = [{}, {}]
## True when at least one per-team pair was given (--variant-team0 or
## --variant-team1). False (the default) = every read of a switch is the same
## for both teams, which the AI's reads use as their cheap fast path.
var team_variants_given := false
## Why a per-team option could not be used: "" when it could, else a line
## naming the unknown name (or the pair that is not name:value) and the option.
## FeatureRegistry.install() then refuses the match (exit code 3), so a typo
## never plays a night of matches without the switch.
var team_variant_error := ""
## The preset (rule set) of this match: one of CouncilPresets.ORDER. "pick"
## (the standard rules) when --preset is not given, "none" for the old
## standard rules. "" only when --preset named something unknown (see
## preset_error). Set from --preset by _parse_options().
var preset := ""
## Why the preset that was asked for could not be used: "" when it could, else
## a line naming the unknown name. FeatureRegistry.install() then refuses the
## match (exit code 3), so a typo never plays other rules by mistake. The
## start screen shows the line and keeps its seat buttons off.
var preset_error := ""
## Feature hook: tuned numbers changed for this match, by name: name ->
## new value (for example "kill_base" -> 150.0). Empty (the default) =
## every number has its normal value. A feature module sets entries in its
## install() (Game.tunables["kill_base"] = 150.0); the game reads them
## through Rules.tune(name, normal value), and Rules.TUNABLES lists every
## name that is read. WorldSetup empties it when a match is built.
var tunables := {}
## How often each feature mechanic was used this match, by name: name ->
## count (for example "escort_wing_upgrades" -> 12). Feature modules add
## to it with count_usage(); the fun probe prints it, because a mechanic
## the AI never used proves nothing. WorldSetup empties it when a match is
## built.
var usage := {}
## True when --sim-only was given: a speed mode for windowless test runs. The
## game then skips everything that only draws or sounds (the unit pictures,
## the shot and ring drawing, the sound cues, the HUD, the camera), because
## the simulation never reads any of it. The match plays out exactly the
## same, only faster. Read once from the options by _parse_options().
var sim_only := false
## True when this run plays with the damage modifiers removed (every hit does
## its raw damage to every kind of target). It starts as
## Rules.DAMAGE_MODIFIERS_REMOVED, the default of the build, and the option
## --damage-modifiers-removed (or =0 / =false) overrides it. Read once by
## _parse_options(); everything else asks Rules.damage_modifiers_removed().
var damage_modifiers_removed := Rules.DAMAGE_MODIFIERS_REMOVED
## True when this run flies the corvettes, frigates, destroyers and battlecruisers
## as ships of the line (swivelling main engines, weak reverse and side
## thrusters). It starts as Rules.BIG_HULL_FLIGHT, the default of the build, and
## the option --big-hull-flight (or =0 / =false) overrides it. Read once by
## _parse_options(); everything else asks Rules.big_hull_flight().
var big_hull_flight := Rules.BIG_HULL_FLIGHT
## The difficulty of the next match: one of Difficulty.ORDER. It is Difficulty.DEFAULT
## (Medium) until --difficulty names a level, or the start screen shows the
## remembered pick or the player chooses one (choose_difficulty()). It is the one
## place the setting is held; WorldSetup reads it when a match is built.
var difficulty := Difficulty.DEFAULT
## Why the --difficulty that was asked for could not be used: "" when it could
## (or when none was asked for), else a line naming the unknown word.
## FeatureRegistry.install() then refuses the match (exit code 3), so a typo never
## plays Medium by mistake.
var difficulty_error := ""
## The team the human plays for in the next match: Rules.HALCYON (Aurelian) or
## Rules.CINDER (Vhorr). It is Aurelian until --team names a team, or the start
## screen shows the remembered pick or the player chooses one (choose_team()). It
## is the one place the setting is held; WorldSetup reads it when a match is built
## (World.human_team). A match with no human seat (a spectator) ignores it.
var human_team := Rules.HALCYON
## Why the --team that was asked for could not be used: "" when it could (or when
## none was asked for), else a line naming the unknown word. FeatureRegistry.install()
## then refuses the match (exit code 3), so a typo never plays Aurelian by mistake.
var team_error := ""
## The file the game keeps its few remembered settings in (the last difficulty
## pick, the team, the Unlock everything toggle, the No fog toggle, the two wing switches and, in its [keys] section, the
## player's own key changes: KeyMapStore), in the user's data folder (the browser
## version keeps it in the browser's storage).
const SETTINGS_FILE := "user://halcyon_settings.cfg"
## True until the difficulty has been settled: by --difficulty, by the start
## screen reading the remembered pick, or by a pick. Only the start screen reads
## the settings file, so a test or any run without a start screen never depends
## on what was picked on this computer.
var _difficulty_open := true
## True until the team has been settled: by --team, by the start screen reading the
## remembered pick, or by a pick. Only the start screen reads the settings file, so a
## test or any run without a start screen never depends on what was picked on this
## computer.
var _team_open := true
## True when the test option "Unlock everything" is on for this run: the human
## buyer can then buy anything at once and for nothing (UnlockAll is the one
## place that asks). It is off until --unlock-all turns it on, or the start screen
## shows the remembered choice or the player toggles it (choose_unlock()). A match
## with it off is exactly the normal game.
var unlock_everything := false
## True until the Unlock everything option has been settled: by --unlock-all, by
## the start screen reading the remembered choice, or by a toggle. Only the start
## screen reads the settings file for it, like the difficulty.
var _unlock_open := true
## True when the test option "No fog" is on for this run: the human's screen then shows everything (FogOff is the one
## place that asks). Only the screen changes: what each team can see, the computer pilots and the Admiral's placing rules are
## exactly as before. It is off until --fog-off turns it on, or the start screen shows the remembered choice or the player
## toggles it (choose_fog_off()). A match with it off is exactly the normal game.
var fog_off := false
## True until the No fog option has been settled: by --fog-off, by the start screen reading the remembered choice, or by a
## toggle. Only the start screen reads the settings file for it, like Unlock everything.
var _fog_off_open := true
## True when the human pilot's seat gets the test wing (a Scout, a Fighter and a Bomber). Off until
## --test-wing turns it on or the start screen shows the remembered choice or the player toggles it
## (choose_test_wing()). Off, a match has no wing for the human.
var test_wing := false
## True when every computer pilot's seat gets the same test wing. Off until --cpu-wings turns it on or
## the start screen shows the remembered choice (on the first time) or the player toggles it
## (choose_cpu_wings()). A run with no start screen and no option has it off.
var cpu_wings := false
## True until the test wing switch has been settled (by --test-wing, by the start screen reading
## the remembered choice, or by a toggle).
var _test_wing_open := true
## True until the computer pilots' wings switch has been settled (same ways).
var _cpu_wings_open := true
## The wing the two switches give: a Scout, a Fighter and a Bomber.
const TEST_WING := ["scout", "fighter", "bomber"]
## True until the player's own key changes have been read from the settings file. Only
## the start screen reads them (use_remembered_keys()), so a test or a run without a
## start screen always has the standard keys, whatever this computer remembers.
var _keys_open := true


## Godot calls this once at startup: read the options, then set up the
## controls, and stop the window from being made smaller than 1280 x 720.
func _ready() -> void:
	_parse_options()
	_define_actions()
	WindowMode.apply_minimum_size(get_window())


## Read the command-line options into `options`, then build `variants`.
## Only words after `--` on the command line count ("user args"); of
## those, only words starting with "--" are options.
func _parse_options() -> void:
	# Step 1: each option: "--name=value" or a bare "--name" (= true).
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq := body.find("=")
		if eq < 0:
			options[body] = true
		else:
			options[body.substr(0, eq)] = body.substr(eq + 1)
	# Step 1a: --replay=<file> brings the settings its log was made with (the seed, the seat, the
	# team, the rules, the test switches) for every option the command line did not give.
	var typed_rules := options.has("variant") or options.has("preset")
	var replay_variants := ReplayOptions.fill(options)
	# Step 1b: --sim-only (a bare switch; "--sim-only=0" or "=false" turns it
	# off again) is read here once, into the plain variable `sim_only`, so
	# the many places that check it need no lookup in `options`.
	var so: String = str(options.get("sim-only", "false"))
	sim_only = so != "false" and so != "0"
	# Step 1c: --damage-modifiers-removed (a bare switch; "=0" or "=false"
	# turns the modifiers back on) overrides the build's default. It is read
	# before the variants are built, because the rule sets depend on it.
	if options.has("damage-modifiers-removed"):
		var dm: String = str(options["damage-modifiers-removed"])
		damage_modifiers_removed = dm != "false" and dm != "0"
	# Step 1c2: --big-hull-flight (a bare switch; "=0" or "=false" turns the
	# ships-of-the-line flight off) overrides the build's default.
	if options.has("big-hull-flight"):
		var bf: String = str(options["big-hull-flight"])
		big_hull_flight = bf != "false" and bf != "0"
	# Step 1d: --difficulty=<level> (one of Difficulty.ORDER) chooses the level of
	# a single-player match. An unknown word leaves the level alone and sets
	# difficulty_error, which FeatureRegistry turns into a refusal.
	if options.has("difficulty"):
		_difficulty_open = false
		var wanted := str(options["difficulty"])
		if Difficulty.is_level(wanted):
			difficulty = wanted
		else:
			difficulty_error = "unknown difficulty \"%s\" (the levels are: %s)" % [wanted, ", ".join(PackedStringArray(Difficulty.ORDER))]
	# Step 1d2: --team=<aurelian|vhorr> chooses the team the human plays for. An
	# unknown word leaves the team alone and sets team_error, which
	# FeatureRegistry turns into a refusal.
	if options.has("team"):
		_team_open = false
		var side := Rules.team_from_name(str(options["team"]))
		if side >= 0:
			human_team = side
		else:
			team_error = "unknown team \"%s\" (the teams are: aurelian, vhorr)" % str(options["team"])
	# Step 1e: --unlock-all (a bare switch; "=0" or "=false" turns it off) settles
	# the test option for this run, so the start screen shows it as given.
	if options.has("unlock-all"):
		_unlock_open = false
		var ua: String = str(options["unlock-all"])
		unlock_everything = ua != "false" and ua != "0"
	# Step 1e2: --fog-off (a bare switch; "=0" or "=false" turns it off) settles the test option "No fog" for this run, like
	# --unlock-all. It only changes what the human's screen draws: nothing in the match reads it.
	if options.has("fog-off"):
		_fog_off_open = false
		var fo: String = str(options["fog-off"])
		fog_off = fo != "false" and fo != "0"
	# Step 1f: --test-wing and --cpu-wings (bare switches; "=0" or "=false" turns them off)
	# settle the two wing switches for this run, like --unlock-all.
	if options.has("test-wing"):
		_test_wing_open = false
		var tw: String = str(options["test-wing"])
		test_wing = tw != "false" and tw != "0"
	if options.has("cpu-wings"):
		_cpu_wings_open = false
		var cw: String = str(options["cpu-wings"])
		cpu_wings = cw != "false" and cw != "0"
	# Step 2: the variants: start from the defaults, then the preset named by
	# --preset (the standard rules when none is named), then each "name:value"
	# pair of --variant (see _build_variants()). The preset is named in the log.
	_build_variants(str(options.get("preset", "")))
	# A replay plays the rules its log was made with, to the last key, unless the command line
	# named other rules.
	if not replay_variants.is_empty() and not typed_rules:
		variants = replay_variants
	if preset != "":
		var pairs := CouncilPresets.variant_string(preset)
		print("preset: %s = %s" % [preset, pairs if pairs != "" else "(every variant at its default)"])
	# Step 3: the per-team pairs (--variant-team0 and --variant-team1), kept apart
	# in `team_variants`. An unknown name sets team_variant_error, which
	# FeatureRegistry turns into a refusal.
	_read_team_variants()


## Build `variants`: start from Rules.VARIANT_DEFAULTS, then apply the pairs
## of preset `preset_name` (CouncilPresets; "" = CouncilPresets.STANDARD, the
## standard rules), then the pairs of --variant, so --variant wins where both
## set a key. Sets `preset` and `preset_error`: an unknown preset name adds
## nothing and leaves an error line for FeatureRegistry.
func _build_variants(preset_name: String) -> void:
	variants = Rules.VARIANT_DEFAULTS.duplicate()
	preset = ""
	preset_error = ""
	var wanted := preset_name if preset_name != "" else CouncilPresets.STANDARD
	if CouncilPresets.is_preset(wanted):
		preset = wanted
		_apply_pairs(CouncilPresets.variant_string(wanted))
	else:
		preset_error = "unknown preset \"%s\" (the presets are: %s)" % [wanted, ", ".join(PackedStringArray(CouncilPresets.ORDER))]
	_apply_pairs(str(options.get("variant", "")))


## Apply each "name:value" pair of `text` (pairs split by commas) to
## `variants`; a pair that isn't exactly name:value is skipped.
func _apply_pairs(text: String) -> void:
	for pair in text.split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2:
			variants[kv[0]] = kv[1]


## Read --variant-team0 and --variant-team1 into `team_variants` (see there):
## each is split into name:value pairs like --variant (see _apply_pairs()), but
## the pairs of a team go to that team's Dictionary only, and `variants` is not
## touched. Sets `team_variants_given` when any pair exists. A name that is not
## in Rules.VARIANT_DEFAULTS, or a pair that is not exactly name:value, sets
## `team_variant_error` (one line naming it and the option; the first one found
## stays), so the match is refused, and the pair is not kept.
func _read_team_variants() -> void:
	team_variants = [{}, {}]
	team_variants_given = false
	team_variant_error = ""
	for team: int in range(2):
		var opt_name := "variant-team%d" % team
		for pair in str(options.get(opt_name, "")).split(",", false):
			var kv := pair.split(":")
			if kv.size() != 2 or not Rules.VARIANT_DEFAULTS.has(kv[0]):
				if team_variant_error == "":
					team_variant_error = "--%s: \"%s\" is not a name:value pair with a name from Rules.VARIANT_DEFAULTS" % [opt_name, pair]
				continue
			team_variants[team][kv[0]] = kv[1]
			team_variants_given = true


## Put the difficulty last picked on this computer into `difficulty`, unless the
## difficulty is already settled (--difficulty was given, or this ran before). The
## start screen calls it when it is built, so only a game with a start screen
## reads the settings file. A missing or unreadable file, or a word that is not a
## level, leaves the default (Medium).
func use_remembered_difficulty() -> void:
	if not _difficulty_open:
		return
	_difficulty_open = false
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	var saved := str(cfg.get_value("game", "difficulty", ""))
	if Difficulty.is_level(saved):
		difficulty = saved


## The player picked difficulty `level` (one of Difficulty.ORDER) on the start
## screen: use it for the coming match and remember it in the settings file for
## the next run. A file that cannot be written only costs the memory (a warning).
func choose_difficulty(level: String) -> void:
	if not Difficulty.is_level(level):
		return
	difficulty = level
	difficulty_error = ""
	_difficulty_open = false
	var cfg := ConfigFile.new()
	# Keep whatever else the file holds; a missing file is fine.
	cfg.load(SETTINGS_FILE)
	cfg.set_value("game", "difficulty", level)
	var err := cfg.save(SETTINGS_FILE)
	if err != OK:
		push_warning("settings: cannot write %s (error %d); the difficulty will not be remembered" % [SETTINGS_FILE, err])


## Put the team last picked on this computer into `human_team`, unless the team is
## already settled (--team was given, or this ran before). The start screen calls it
## when it is built, so only a game with a start screen reads the settings file for
## it. A missing or unreadable file, or a word that is not a team, leaves Aurelian.
func use_remembered_team() -> void:
	if not _team_open:
		return
	_team_open = false
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	var side := Rules.team_from_name(str(cfg.get_value("game", "team", "")))
	if side >= 0:
		human_team = side


## The test switches that only change what the human sees, as the match log's header writes them
## ("fog:0" or "fog:1"): a replay with another value still plays the same match, so the header
## check leaves this word out. It lives here, with the switch, so that no other script names it.
func screen_switches() -> String:
	return "fog:%d" % int(fog_off)


## The player picked team `side` (Rules.HALCYON or Rules.CINDER) on the start screen:
## use it for the coming match and remember it in the settings file for the next run.
## A file that cannot be written only costs the memory (a warning).
func choose_team(side: int) -> void:
	if side != Rules.HALCYON and side != Rules.CINDER:
		return
	human_team = side
	team_error = ""
	_team_open = false
	var cfg := ConfigFile.new()
	# Keep whatever else the file holds; a missing file is fine.
	cfg.load(SETTINGS_FILE)
	cfg.set_value("game", "team", String(Rules.TEAM_DISPLAY[side]).to_lower())
	var err := cfg.save(SETTINGS_FILE)
	if err != OK:
		push_warning("settings: cannot write %s (error %d); the team will not be remembered" % [SETTINGS_FILE, err])


## Put the Unlock everything choice last made on this computer into
## `unlock_everything`, unless the option is already settled (--unlock-all was
## given, or this ran before). The start screen calls it when it is built, so only
## a game with a start screen reads the settings file for it. A missing or
## unreadable file leaves it off.
func use_remembered_unlock() -> void:
	if not _unlock_open:
		return
	_unlock_open = false
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	# Only a real yes counts: a damaged file (a word, a number) leaves it off.
	var saved: Variant = cfg.get_value("game", "unlock_everything", false)
	unlock_everything = typeof(saved) == TYPE_BOOL and saved


## Put the No fog choice last made on this computer into `fog_off`, unless the option is already settled (--fog-off was given,
## or this ran before). The start screen calls it when it is built, so only a game with a start screen reads the settings file
## for it. A missing or unreadable file, or an entry that is not a real yes, leaves it off.
func use_remembered_fog_off() -> void:
	if not _fog_off_open:
		return
	_fog_off_open = false
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	var saved: Variant = cfg.get_value("game", "fog_off", false)
	fog_off = typeof(saved) == TYPE_BOOL and saved


## Put the two wing switches last made on this computer into `test_wing` and `cpu_wings`, unless a
## switch is already settled (its option was given, or this ran before). The start screen calls it
## when it is built, so only a game with a start screen reads the settings file for them. A
## missing file or entry means: the human's test wing off, the computer pilots' wings on.
func use_remembered_wings() -> void:
	var cfg := ConfigFile.new()
	var have := cfg.load(SETTINGS_FILE) == OK
	if _test_wing_open:
		_test_wing_open = false
		# Only a real yes counts: a damaged entry leaves it off.
		var saved: Variant = cfg.get_value("game", "test_wing", false) if have else false
		test_wing = typeof(saved) == TYPE_BOOL and saved
	if _cpu_wings_open:
		_cpu_wings_open = false
		# The computer pilots' wings are on the first time; only a real no turns them off.
		var saved: Variant = cfg.get_value("game", "cpu_wings", true) if have else true
		cpu_wings = not (typeof(saved) == TYPE_BOOL and not saved)


## The player switched the human's test wing on or off (`on`) on the start screen: use it for the
## coming match and remember it for the next run (a file that cannot be written only costs the memory).
func choose_test_wing(on: bool) -> void:
	test_wing = on
	_test_wing_open = false
	_remember("test_wing", on, "The test wing")


## The player switched the computer pilots' wings on or off (`on`) on the start screen: use it for the
## coming match and remember it.
func choose_cpu_wings(on: bool) -> void:
	cpu_wings = on
	_cpu_wings_open = false
	_remember("cpu_wings", on, "The computer pilots' wings")


## Write `key` = `value` in the settings file's [game] section, keeping everything else; `what` names
## the setting in the warning when the file cannot be written.
func _remember(key: String, value: bool, what: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("game", key, value)
	var err := cfg.save(SETTINGS_FILE)
	if err != OK:
		push_warning("settings: cannot write %s (error %d); %s will not be remembered" % [SETTINGS_FILE, err, what])


## The hulls of the wing a pilot seat gets: --wingmen first (for every seat), else the test wing for
## the human's seat when its switch is on, or for a computer pilot's seat when that switch is on.
## Up to three hull ids, in slot order; empty = no wing.
func wing_hulls_for(is_human_seat: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var spec: Variant = options.get("wingmen")
	if spec != null:
		var text := str(spec).strip_edges().to_lower()
		if text == "" or text == "off" or text == "true" or text == "0" or text == "false":
			return out
		for part: String in text.split(",", false):
			var id := part.strip_edges()
			if not Ships.HULLS.has(id):
				push_warning("--wingmen: unknown hull \"%s\" ignored" % id)
				print("--wingmen: unknown hull \"%s\" ignored" % id)
				continue
			if out.size() < 3:
				out.append(id)
		return out
	if (test_wing if is_human_seat else cpu_wings):
		out.append_array(PackedStringArray(TEST_WING))
	return out


## Put the player's own key changes and picked key presets from the settings file on the
## controls (KeyMapStore.load_from(), then KeyMap.apply_to_input_map()), unless that was
## already done. The start screen calls it when it is built, so only a game with a start
## screen reads the settings file for the keys. A missing file or section, or an entry
## that is bad, leaves the standard keys for that row.
func use_remembered_keys() -> void:
	if not _keys_open:
		return
	_keys_open = false
	KeyMap.load_from(SETTINGS_FILE)
	KeyMap.apply_to_input_map()


## The player switched Unlock everything on or off (`on`) on the start screen: use
## it for the coming match and remember it in the settings file for the next run.
## A file that cannot be written only costs the memory (a warning).
func choose_unlock(on: bool) -> void:
	unlock_everything = on
	_unlock_open = false
	var cfg := ConfigFile.new()
	# Keep whatever else the file holds; a missing file is fine.
	cfg.load(SETTINGS_FILE)
	cfg.set_value("game", "unlock_everything", on)
	var err := cfg.save(SETTINGS_FILE)
	if err != OK:
		push_warning("settings: cannot write %s (error %d); Unlock everything will not be remembered" % [SETTINGS_FILE, err])


## The player switched No fog on or off (`on`) on the start screen: use it for the coming match and remember it in the settings
## file for the next run. A file that cannot be written only costs the memory (a warning).
func choose_fog_off(on: bool) -> void:
	fog_off = on
	_fog_off_open = false
	_remember("fog_off", on, "No fog")


## Start the match again in seat `role` (the pause menu's Restart): the same
## seat, the same team, difficulty and rules (Game keeps all of those), with
## no start screen in between. The main scene is loaded again, so the new match
## is built from nothing; the pause is lifted first, or the new match would
## start paused.
func restart_match(role: String) -> void:
	restart_role = role
	_load_main_scene_again()


## Go back to the start screen (the pause menu's Quit to start): the main scene
## is loaded again, with no seat chosen.
func quit_to_start() -> void:
	restart_role = ""
	_load_main_scene_again()


## Forget the running match, lift the pause and load the main scene again (what
## the end screen's New match does too).
func _load_main_scene_again() -> void:
	world = null
	get_tree().paused = false
	get_tree().reload_current_scene()


## The value of option `key` (the name without "--"), or `default_value`
## when it was not given. Values are text (or true for a bare option), so
## callers turn them into numbers with int() or float().
func opt(key: String, default_value = null):
	return options.get(key, default_value)


## The chosen value of rule variant `key` (such as "retreat"), or "" if
## there is no such variant.
func variant(key: String) -> String:
	return str(variants.get(key, ""))


## The value of rule variant `key` as team `team`'s AI sees it: the team's own
## value when --variant-team0 / --variant-team1 gave one for it, else the
## match-wide variant(key). A team outside 0-1 gets variant(key).
func variant_for(team: int, key: String) -> String:
	if team >= 0 and team < 2:
		var own: Dictionary = team_variants[team]
		if own.has(key):
			return str(own[key])
	return variant(key)


## Was any per-team variant given (--variant-team0 or --variant-team1)? False
## in every normal match. FeatureRegistry.active_for() uses it as its fast path.
func has_team_variants() -> bool:
	return team_variants_given


## Count `n` more uses (1 unless told otherwise) of feature mechanic `key`
## in `usage`, for example Game.count_usage("escort_wing_upgrades").
func count_usage(key: String, n: int = 1) -> void:
	usage[key] = int(usage.get(key, 0)) + n


## Godot sends every input event here first, before any screen sees it.
## The only one we act on is the fullscreen key (F11 or Alt+Enter); the
## real code is WindowMode.handle_input(). It runs here, not in the HUD,
## because the key must work on the start screen and the end screen too,
## and a web browser only allows fullscreen from inside an input callback.
func _input(event: InputEvent) -> void:
	WindowMode.handle_input(event, get_viewport())


## Define every control (input action). The real code is
## GameInputMap.define_all().
func _define_actions() -> void:
	GameInputMap.define_all()
