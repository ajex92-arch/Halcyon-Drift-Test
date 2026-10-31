extends RefCounted
## WHAT THIS IS: the clip maker of the photo tours. When a tour has saved its
## pictures, make() stitches them into one short video (an MP4 that a phone
## plays), so the motion and the pace of a match can be judged by watching
## it, not by paging through still pictures.
##
## HOW IT WORKS: make() gets the folder, the file names of the pictures in
## the order they were taken, and a name for the clip.
##   1. It does nothing when the tour was started with --clip=0, and says so
##      when there are fewer than 2 pictures (one picture is no clip).
##   2. It decides how long each picture stays on screen. The clip shows FPS
##      (12) frames a second. A tour with few pictures would be over in a
##      blink, so each picture is held longer until the clip lasts at least
##      MIN_SECS (4 s). A tour with very many pictures is thinned out (every
##      2nd, 3rd ... picture is kept) until the clip lasts at most MAX_SECS
##      (55 s), so a clip stays under a minute.
##   3. It writes a small list file (clip_list.txt, next to the pictures)
##      that names each picture and how long it shows, then runs the program
##      ffmpeg to turn the list into video: H.264, "yuv420p" colours, at most
##      MAX_WIDTH (1280) pixels wide and "faststart" (the first seconds play
##      before the whole file has arrived). That is the plain kind of video
##      every phone plays. ffmpeg is called by its name and found on the
##      PATH (the list of folders the computer searches for programs); no
##      place on this PC is written down here.
##   4. It prints one line: "clip <file> ..." with the number of pictures,
##      the length, the frame rate, the size in pixels and the file size, or
##      why there is no clip (ffmpeg is not on the PATH, or it failed). It
##      never fails the tour: the pictures are the result, the clip is a
##      bonus. When there is no clip, a second line gives the command that
##      makes it later from a shell that has ffmpeg, in the pictures' folder.
## Options (after the `--` on the command line, like the tour's own):
## --clip=0 makes no clip, --clip-fps=N sets the frames a second (1 to 30).
##
## WHO USES IT: tests/spectate_shots.gd and tests/ship_action_shots.gd call
## make() after their last picture, with
##   const ShotClip := preload("res://tests/lib/shot_clip.gd")
## It has no class_name on purpose: test helpers stay out of the game's list
## of global names. It reads and writes files only; it never touches the game.

## The frames a second of the clip; --clip-fps=N changes it.
const FPS := 12
## The clip is never wider than this (pixels); a smaller picture keeps its
## own width.
const MAX_WIDTH := 1280
## A clip shorter than this (seconds) is slowed down: each picture is held
## longer, so a tour with a few pictures can still be looked at.
const MIN_SECS := 4.0
## A clip longer than this (seconds) is thinned out, so it stays under a
## minute.
const MAX_SECS := 55.0
## The video quality (x264's "constant rate factor"): lower is sharper and
## bigger; 23 is the encoder's own default.
const CRF := 23
## The name of the list file that make() writes next to the pictures.
const LIST_NAME := "clip_list.txt"


## Stitch the pictures `files` (file names inside folder `dir`, in the order
## they were taken) into the clip `clip_name` in the same folder, and print
## one line about it (see HOW IT WORKS). Does nothing with --clip=0.
static func make(dir: String, files: PackedStringArray, clip_name: String) -> void:
	# Step 1: switched off, or nothing to stitch.
	var wanted := str(Game.opt("clip", "1"))
	if wanted == "0" or wanted == "false":
		return
	if files.size() < 2:
		print("clip skipped: only %d picture(s), a clip needs 2 or more" % files.size())
		return
	# Step 2: the timing: every `step`-th picture is kept and each stays for
	# `hold` frames. `kept` pictures at `hold` frames make `secs` seconds.
	var fps := clampi(int(Game.opt("clip-fps", FPS)), 1, 30)
	var timing := plan(files.size(), fps)
	var step: int = timing[0]
	var hold: int = timing[1]
	var kept := ceili(float(files.size()) / float(step))
	var secs := float(kept * hold) / float(fps)
	# Step 3: the size, from the first picture: its own width but at most
	# MAX_WIDTH, made even (the video format needs even sizes).
	var first := Image.load_from_file(dir.path_join(files[0]))
	if first == null or first.is_empty():
		print("clip skipped: cannot read the picture %s" % files[0])
		return
	var width := int(float(mini(MAX_WIDTH, first.get_width())) / 2.0) * 2
	var height := roundi(float(first.get_height()) * float(width) / float(first.get_width()) / 2.0) * 2
	# Step 4: the list file: "file <name>" and "duration <seconds>" for each
	# kept picture. The last picture is named once more without a duration,
	# because ffmpeg ignores the duration of the final entry otherwise.
	var each := "%.6f" % (float(hold) / float(fps))
	var lines := PackedStringArray(["ffconcat version 1.0"])
	var last := ""
	for i in range(0, files.size(), step):
		last = files[i].replace("'", "'\\''")
		lines.append("file '%s'" % last)
		lines.append("duration %s" % each)
	lines.append("file '%s'" % last)
	var list_path := ProjectSettings.globalize_path(dir.path_join(LIST_NAME))
	var list_file := FileAccess.open(list_path, FileAccess.WRITE)
	if list_file == null:
		print("clip skipped: cannot write the list file %s" % list_path)
		return
	list_file.store_string("\n".join(lines) + "\n")
	list_file.close()
	# Step 5: no ffmpeg on the PATH: say so, and how to make the clip later.
	var by_hand := "clip by hand, in %s from a shell that has ffmpeg: ffmpeg %s" % [dir, " ".join(_args(LIST_NAME, clip_name, secs, width, fps))]
	if not _on_path("ffmpeg"):
		print("clip skipped: ffmpeg is not on the PATH (a shell started before ffmpeg was installed does not see it). The pictures are kept.")
		print(by_hand)
		return
	# Step 6: run ffmpeg and wait for it. Then look at what it made.
	var out := ProjectSettings.globalize_path(dir.path_join(clip_name))
	var output: Array = []
	var code := OS.execute("ffmpeg", _args(list_path, out, secs, width, fps), output, true)
	var bytes := 0
	var made := FileAccess.open(out, FileAccess.READ)
	if made != null:
		bytes = made.get_length()
		made.close()
	if code != 0 or bytes == 0:
		var why := ""
		if not output.is_empty():
			var said := str(output[0]).strip_edges().split("\n", false)
			if not said.is_empty():
				why = said[said.size() - 1].strip_edges().left(200)
		print("clip FAILED: ffmpeg exit code %d %s" % [code, why])
		print(by_hand)
		return
	print("clip %s  %d pictures, %.1f s at %d fps, %dx%d, %d KB" % [out, kept, secs, fps, width, height, int(float(bytes) / 1024.0)])


## How `count` pictures are timed at `fps` frames a second: [step, hold].
## Every `step`-th picture is kept (1 = all of them) and each kept picture
## stays on screen for `hold` frames, so the clip lasts MIN_SECS to MAX_SECS
## where the number of pictures allows it: 60 pictures at 12 frames a second
## are [1, 1] (5 s), 16 pictures are [1, 3] (4 s), 3 pictures are [1, 16]
## (4 s) and 1000 pictures are [2, 1] (42 s).
static func plan(count: int, fps: int) -> Array:
	# Step 1: too many pictures for MAX_SECS: keep every step-th.
	var step := 1
	if float(count) / float(fps) > MAX_SECS:
		step = ceili(float(count) / (MAX_SECS * float(fps)))
	# Step 2: too few for MIN_SECS: hold each kept picture longer.
	var kept := ceili(float(count) / float(step))
	var hold := 1
	if float(kept) / float(fps) < MIN_SECS:
		hold = ceili(MIN_SECS * float(fps) / float(kept))
	return [step, hold]


## True when a program called `prog` (such as "ffmpeg") is in one of the
## folders of the PATH. Looking first keeps the engine from printing an error
## line for a program that is not there.
static func _on_path(prog: String) -> bool:
	var sep := ";" if OS.get_name() == "Windows" else ":"
	for folder in OS.get_environment("PATH").split(sep, false):
		var base := str(folder).strip_edges().trim_prefix("\"").trim_suffix("\"")
		if base == "":
			continue
		for file in [prog + ".exe", prog]:
			if FileAccess.file_exists(base.path_join(file)):
				return true
	return false


## The ffmpeg arguments (the command line without the program name) that turn
## the list file `list` into the clip `out`, `secs` seconds long, `width`
## pixels wide, at `fps` frames a second: read the list as a slideshow, scale
## to the width (the height follows, made even), fix the frame rate, use
## "yuv420p" colours, encode as H.264 (High profile, level 4.0) with
## "faststart", and no sound. -t cuts the clip at the planned length.
static func _args(list: String, out: String, secs: float, width: int, fps: int) -> PackedStringArray:
	return PackedStringArray([
		"-nostdin", "-y", "-loglevel", "error",
		"-f", "concat", "-safe", "0", "-i", list,
		"-t", "%.3f" % secs,
		"-vf", "scale=%d:-2:flags=lanczos,fps=%d,format=yuv420p" % [width, fps],
		"-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-crf", str(CRF), "-preset", "medium",
		"-movflags", "+faststart", "-an", out])
