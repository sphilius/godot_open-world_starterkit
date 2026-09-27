class_name PlaytestLogger
extends Node
## Playtest log (M10): one CSV row per beat of a run, appended to `log_path` when the run ends
## (victory, Quit to title, or quitting the game), so three playtests can be summarised against
## PLAN.md §6.2 with `python3 tools/playtest/summarize.py <csv files>`.
##
## Beats follow the furthest point reached, so retries count toward the beat they happen in:
##   approach  : from Begin until the courtyard ambush first starts
##   courtyard : until the courtyard is cleared (deaths and resets included)
##   breather  : until the Gatekeeper fight first starts
##   sanctum   : until the Gatekeeper falls
## Per beat: play seconds (GameManager's clock: no menus or pauses), deaths, parries, fight
## attempts, average FPS, the worst frame and the number of hitches (real frame time over
## `hitch_ms`, the §6.2 limit). The first `warmup_time` seconds after Begin (shader and navmesh
## warm-up), paused frames and the wait for the victory screen after the Gatekeeper falls (the
## play clock has stopped by then) aren't measured. Each run also gets a `total` row.
##
## Where the file lands: user:// is %APPDATA%/Godot/app_userdata/<project name>/ on Windows,
## ~/.local/share/godot/app_userdata/<project name>/ on Linux. The rows are also printed, for
## the web build (read them in the browser console). An empty `log_path` turns logging off
## (the test runner does that for every test that doesn't check the logger).

const BEATS: Array[StringName] = [&"approach", &"courtyard", &"breather", &"sanctum"]
const HEADER := "run,date,platform,renderer,quality,outcome,beat,seconds,deaths,parries,attempts,avg_fps,worst_frame_ms,hitches"

## Where runs are appended. Empty disables the log.
static var log_path := "user://playtest.csv"

@export var game: GameManager
## Optional: the quality preset is logged with each row.
@export var dev_hud: DevHUD
## A frame slower than this (real milliseconds) is a hitch.
@export var hitch_ms := 50.0
## Real seconds after Begin before frame times count.
@export var warmup_time := 2.0

## Index into BEATS of the furthest beat reached, or -1 before Begin.
var beat := -1
## True once this run has been written (a run is written once).
var written := false
## False once play is over (the Gatekeeper fell): frames stop counting with the play clock.
var sampling := true
var _rows: Array[Dictionary] = []
var _last_usec := 0
var _warm_until_msec := 0
var _id_rng := RandomNumberGenerator.new()               # its own: a seeded global RNG would repeat ids


func _init() -> void:
	_id_rng.randomize()


func _ready() -> void:
	if game == null:
		return
	game.state_changed.connect(_on_state_changed)
	game.victory.connect(func() -> void: finish(&"victory"))
	game.returning_to_title.connect(func() -> void: finish(&"title"))
	if game.courtyard:
		game.courtyard.cleared.connect(func() -> void: _reach(2))
	if game.sanctum:
		game.sanctum.cleared.connect(func() -> void: sampling = false)
	if game.is_playing():
		_on_state_changed(GameManager.GameState.START_MENU, game.state)


## The rows of this run so far, one Dictionary per beat reached (keys as in HEADER).
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in _rows:
		out.append(row.duplicate())
	if not _rows.is_empty():
		_close(out[-1])
	return out


## Writes this run to `log_path` (once). `outcome`: victory, title or quit.
func finish(outcome: StringName) -> void:
	if written or beat < 0:
		return
	written = true
	var run_rows := rows()
	var total := {
		&"beat": &"total", &"seconds": 0.0, &"deaths": 0, &"parries": 0, &"attempts": 0,
		&"frames": 0, &"frame_seconds": 0.0, &"worst_frame_ms": 0.0, &"hitches": 0,
	}
	for row in run_rows:
		for key in [&"seconds", &"deaths", &"parries", &"attempts", &"frames", &"frame_seconds", &"hitches"]:
			total[key] += row[key]
		total[&"worst_frame_ms"] = maxf(total[&"worst_frame_ms"], row[&"worst_frame_ms"])
	run_rows.append(total)
	var prefix := [
		Time.get_datetime_string_from_system().replace(":", "") + "-%04d" % _id_rng.randi_range(0, 9999),
		Time.get_date_string_from_system(), OS.get_name(),
		RenderingServer.get_current_rendering_method(),
		dev_hud.quality_name() if dev_hud else "", outcome,
	]
	var lines: PackedStringArray = []
	for row in run_rows:
		var avg_fps: float = row[&"frames"] / row[&"frame_seconds"] if row[&"frame_seconds"] > 0.0 else 0.0
		var fields := prefix + [row[&"beat"], "%.1f" % row[&"seconds"], row[&"deaths"], row[&"parries"],
				row[&"attempts"], "%.1f" % avg_fps, "%.1f" % row[&"worst_frame_ms"], row[&"hitches"]]
		lines.append(",".join(fields.map(func(field: Variant) -> String: return str(field))))
	if OS.has_feature("web"):
		for line in lines:
			print("playtest: ", line)                    # user:// is IndexedDB on the web
	if log_path != "":
		_append(lines)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if sampling and beat >= 0 and _last_usec > 0 and Time.get_ticks_msec() >= _warm_until_msec:
		# Real frame time: hit-stop and slow motion scale `delta`, not the wall clock.
		var ms := (now - _last_usec) / 1000.0
		var row := _rows[-1]
		row[&"frames"] += 1
		row[&"frame_seconds"] += ms / 1000.0
		row[&"worst_frame_ms"] = maxf(row[&"worst_frame_ms"], ms)
		if ms > hitch_ms:
			row[&"hitches"] += 1
	_last_usec = now


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_usec = 0                                   # the pause itself isn't a frame


func _exit_tree() -> void:
	finish(&"quit")                                      # quitting frees the scene: the run ends here


func _on_state_changed(_previous: GameManager.GameState, state: GameManager.GameState) -> void:
	match state:
		GameManager.GameState.EXPLORATION:
			if beat < 0:
				_warm_until_msec = Time.get_ticks_msec() + int(warmup_time * 1000.0)
				_reach(0)
		GameManager.GameState.COURTYARD_AMBUSH:
			_reach(1)
			_rows[1][&"attempts"] += 1                   # rows[i] is BEATS[i]
		GameManager.GameState.SANCTUM_GATEKEEPER:
			_reach(3)
			_rows[3][&"attempts"] += 1


## Moves on to beat `index` if it's further than the current one.
func _reach(index: int) -> void:
	if index <= beat:
		return
	if not _rows.is_empty():
		_close(_rows[-1])
	for next in range(beat + 1, index + 1):              # one row per beat, even one passed through at once
		_rows.append({
			&"beat": BEATS[next], &"seconds": 0.0, &"deaths": 0, &"parries": 0, &"attempts": 0,
			&"frames": 0, &"frame_seconds": 0.0, &"worst_frame_ms": 0.0, &"hitches": 0,
			&"_time0": game.play_time, &"_deaths0": game.deaths, &"_parries0": game.parries,
		})
	beat = index


## Fills in a row's clock and counters from GameManager (the row stays open to later calls).
func _close(row: Dictionary) -> void:
	row[&"seconds"] = game.play_time - row[&"_time0"]
	row[&"deaths"] = game.deaths - row[&"_deaths0"]
	row[&"parries"] = game.parries - row[&"_parries0"]


func _append(lines: PackedStringArray) -> void:
	var fresh := not FileAccess.file_exists(log_path)
	var file := FileAccess.open(log_path, FileAccess.WRITE if fresh else FileAccess.READ_WRITE)
	if file == null:
		push_warning("PlaytestLogger: can't write %s (%s)" % [log_path, error_string(FileAccess.get_open_error())])
		return
	if fresh:
		file.store_line(HEADER)
	else:
		file.seek_end()
	for line in lines:
		file.store_line(line)
	print("playtest: run appended to ", ProjectSettings.globalize_path(log_path))
