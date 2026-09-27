extends "res://tests/test_case.gd"
## M10 playtest log: per-beat time, deaths, parries, attempts and frame hitches, appended to a
## CSV once per run.

const LOG := "user://test_playtest.csv"


func test_a_run_logs_one_row_per_beat_and_a_total() -> void:
	await load_world(false)
	_fresh_log()
	var game := GameManager.find(tree)
	var logger := world.get_node("PlaytestLogger") as PlaytestLogger
	logger.warmup_time = 0.0
	check_eq(logger.beat, -1, "nothing is logged on the title")
	game.begin_play()
	check_eq(logger.beat, 0, "Begin starts the approach")
	await seconds(0.3)
	OS.delay_msec(90)                                    # one long frame
	await tree.process_frame
	await tree.process_frame

	var courtyard := world.get_node("Courtyard/Encounter") as Encounter
	courtyard.start(player())
	check_eq(logger.beat, 1, "the ambush starts the courtyard beat")
	combat().parry.parry_successful.emit(null, Vector3.ZERO)
	var health := player().get_node("HealthComponent") as HealthComponent
	health.take_damage(CombatFixtures.make_hit(null, 9999.0, 0.0))
	check(await wait_until(func() -> bool: return not health.is_dead, 8.0), "the player never respawned")
	check_eq(game.state, GameManager.GameState.EXPLORATION, "the death reset the ambush")
	check_eq(logger.beat, 1, "walking back after a death still counts as the courtyard")
	courtyard.start(player())
	courtyard.cleared.emit()
	check_eq(logger.beat, 2, "clearing the courtyard starts the breather")

	var sanctum := world.get_node("Sanctum/Encounter") as Encounter
	sanctum.start(player())
	check_eq(logger.beat, 3, "the Gatekeeper fight starts the sanctum beat")
	check(await wait_until(func() -> bool: return not sanctum.alive_enemies().is_empty(), 2.0), "the Gatekeeper never appeared")
	await physics_frames(3)
	game.victory_delay = 0.6
	for enemy in sanctum.alive_enemies():
		(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(CombatFixtures.make_hit(player(), 99999.0, 0.0))
	check(await wait_until(func() -> bool: return sanctum.state == Encounter.State.CLEARED, 2.0), "the Gatekeeper never fell")
	await tree.process_frame
	OS.delay_msec(160)                                   # a long frame while the victory screen is on its way
	await tree.process_frame
	check(await wait_until(func() -> bool: return logger.written, 6.0), "the victory never wrote the run")

	var rows := _read_log()
	check_eq(rows.size(), 5, "four beats and a total")
	if rows.size() != 5:
		return
	check_eq(rows.map(func(row: Dictionary) -> String: return row.beat), ["approach", "courtyard", "breather", "sanctum", "total"], "beat order")
	check_eq(rows[0].outcome, "victory", "outcome")
	check(int(rows[0].hitches) >= 1 and float(rows[0].worst_frame_ms) >= 85.0, "the long frame is a hitch (%s ms)" % rows[0].worst_frame_ms)
	check(float(rows[0].avg_fps) > 0.0, "the approach has a frame rate")
	check_eq(int(rows[1].deaths), 1, "the courtyard death")
	check_eq(int(rows[1].parries), 1, "the courtyard parry")
	check_eq(int(rows[1].attempts), 2, "two tries at the courtyard")
	check_eq(int(rows[3].attempts), 1, "one try at the Gatekeeper")
	check(float(rows[3].worst_frame_ms) < 150.0, "frames after the Gatekeeper falls aren't measured (worst %s ms)" % rows[3].worst_frame_ms)
	check_eq(int(rows[4].deaths), 1, "the total adds up the deaths")
	var beat_seconds := 0.0
	for row in rows.slice(0, 4):
		beat_seconds += float(row.seconds)
	check_near(float(rows[4].seconds), beat_seconds, 0.25, "the total adds up the beats")
	check_near(float(rows[4].seconds), game.play_time, 0.25, "the beats cover the whole play time")
	check_eq(rows[0].run, rows[4].run, "one run id per run")
	logger.finish(&"quit")
	check_eq(_read_log().size(), 5, "a run is only written once")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))


func test_quit_to_title_and_quitting_close_the_run() -> void:
	await load_world()
	_fresh_log()
	var game := GameManager.find(tree)
	var logger := world.get_node("PlaytestLogger") as PlaytestLogger
	check_eq(logger.beat, 0, "a --skip-menu start logs from the first frame")
	game.returning_to_title.emit()                      # return_to_title() would reload the test runner's scene
	var rows := _read_log()
	check_eq(rows.size(), 2, "the approach and a total")
	check(rows.size() == 2 and rows[0].outcome == "title", "outcome of Quit to title")
	world.queue_free()                                   # quitting frees the scene
	world = null
	await tree.process_frame
	await load_world()
	PlaytestLogger.log_path = LOG
	world.queue_free()
	world = null
	await tree.process_frame
	rows = _read_log()
	check_eq(rows.size(), 4, "a second run is appended under the same header")
	check(rows.size() == 4 and rows[2].outcome == "quit", "outcome of quitting")
	check(rows.size() == 4 and rows[0].run != rows[2].run, "each run has its own id")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))


func _fresh_log() -> void:
	PlaytestLogger.log_path = LOG
	if FileAccess.file_exists(LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))


## The log as one Dictionary per data row, keyed by the header.
func _read_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file := FileAccess.open(LOG, FileAccess.READ)
	if file == null:
		return out
	var header := file.get_csv_line()
	check_eq(",".join(header), PlaytestLogger.HEADER, "the header")
	while not file.eof_reached():
		var fields := file.get_csv_line()
		if fields.size() != header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = fields[i]
		out.append(row)
	return out
