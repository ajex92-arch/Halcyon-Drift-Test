class_name StatCard
extends PanelContainer
## WHAT THIS IS: the stat card of one ship class on the Admiral board's Research tab: the class's name (the hulls of that size),
## the combined bonus its ships have from research so far ("Top speed +16% · Acceleration +12% · Hull +15%") and how far up the
## tree it is ("Drive 2 of 2 · Armor 1 of 2"). Four of them sit in one row between the module grid and the research columns, one
## for each class in Tech.TIERS.
##
## HOW IT WORKS: build_row() makes the row and one card for each class; each card is remembered on the board as "class:<tier>"
## so AdmiralBoardResearch.refresh() can call refresh(ts) on it four times a second. refresh() writes the texts through
## UiKit.set_text, which changes a label only when its text differs, so a refresh with nothing new costs no layout. Every number
## comes from TechEffects (the class lines and the levels) and from the team's levels; no number is typed here. The card ignores
## the mouse, so the board's wheel scrolling passes through it.
##
## WHO USES IT: AdmiralBoardResearch (build and refresh), tests/rts_tour_research.gd.

## The class this card shows: one of Tech.TIERS.
var tier := ""
## The class's name line (the hulls of that size).
var head: Label
## The bonus line: the class lines joined with " · ".
var stats: Label
## The levels line: "Drive 2 of 2 · Armor 1 of 2".
var levels: Label


## Build the card for class `tier_name`, `w` pixels wide. Its text is filled in by the first refresh().
func _init(tier_name: String = "", w: float = 0.0) -> void:
	tier = tier_name
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(w, 0.0)
	add_theme_stylebox_override("panel", UiKit.box(Palette.with_alpha(Palette.PANEL, 0.0), Palette.LINE, 7))
	var v := UiKit.vbox(2)
	add_child(v)
	head = UiKit.label(TechEffects.tier_label(tier), 13, Palette.ICE, true)
	stats = UiKit.label("", 12, UiKit.accent(), true)
	levels = UiKit.label("", 11, Palette.MIST, true)
	for l: Label in [head, stats, levels]:
		UiKit.pin_width(l, w - 24.0)
		v.add_child(l)


## Write the card's texts from team `ts` (a label is touched only when its text changed).
func refresh(ts: TeamState) -> void:
	UiKit.set_text(stats, " · ".join(TechEffects.class_lines(ts, tier)))
	UiKit.set_text(levels, TechEffects.level_text(ts, tier))


## Make the row of cards on board `b`'s Research tab, one for each class, sharing the board's width, and remember each as
## "class:<tier>" in the board's cards.
static func build_row(b: AdmiralBoard) -> void:
	var row := UiKit.hbox(6)
	b._content.add_child(row)
	var n := Tech.TIERS.size()
	var w := floorf((b._inner_w() - float(n - 1) * 6.0) / float(n))
	for tier_name: String in Tech.TIERS:
		var c := StatCard.new(tier_name, w)
		row.add_child(c)
		b._cards["class:" + tier_name] = c
