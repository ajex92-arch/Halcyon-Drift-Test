class_name BuildId
extends RefCounted
## WHAT THIS IS: the name of the build that is running, so that a match recording can say
## which build made it and a replay can warn when it is played by another one. The name is a
## short text such as the first twelve letters of the commit the build was made from.
##
## HOW IT WORKS: get_id() looks in three places, the first that has something wins:
##   1. the launch option --build=<text> (a test or a hand-made build names itself);
##   2. the file build_id.txt next to project.godot, which the export of a Windows build
##      writes before it packs the game (the exported game carries no commit of its own);
##   3. the stamp file .vc_source that a version-controlled export of the project carries:
##      its third field is the full commit, of which the first twelve letters are used.
## When none of them has anything the id is "unknown". The result is looked up once and kept.
## A text is made safe for the log's first line: spaces become underscores and it is cut at
## 40 characters.
##
## WHO USES IT: OrderLog.make_header() writes it as build=<id>; ReplayPlayer.check_header()
## compares the log's id with this build's; main.gd prints "build: <id>" when a match starts.

## The file the Windows export writes into the project folder.
const FILE := "res://build_id.txt"
## The stamp file of a version-controlled export (tab separated: repo, ref, commit, ...).
const STAMP := "res://.vc_source"
## What get_id() says when nothing names the build.
const UNKNOWN := "unknown"
## The longest id kept.
const MAX_LENGTH := 40

## The id once it has been looked up ("" before the first call).
static var _id := ""


## The id of this build (see HOW IT WORKS).
static func get_id() -> String:
	if _id == "":
		_id = _find()
	return _id


## Forget the id that was looked up (a test that changes --build calls this).
static func forget() -> void:
	_id = ""


## `text` made safe for the log's header: no spaces, no tabs, at most MAX_LENGTH characters.
static func clean(text: String) -> String:
	var out := text.strip_edges().replace(" ", "_").replace("\t", "_")
	return out.substr(0, MAX_LENGTH) if out != "" else UNKNOWN


## Look in the three places.
static func _find() -> String:
	var opt: Variant = Game.opt("build")
	if opt is String and (opt as String).strip_edges() != "":
		return clean(opt as String)
	var named := _first_line(FILE)
	if named != "":
		return clean(named)
	var stamp := _first_line(STAMP).split("\t")
	if stamp.size() >= 3 and stamp[2].length() >= 7:
		return clean(stamp[2].substr(0, 12))
	return UNKNOWN


## The first line of file `path`, or "" when it cannot be read.
static func _first_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_line().strip_edges()
