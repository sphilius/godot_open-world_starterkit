extends SceneTree
## Headless test runner. It's the CI gate before the web build deploys.
##
##   godot --headless --path . --script res://tests/run_tests.gd [-- --filter=<substring>]
##
## Runs every `test_*` method in res://tests/test_*.gd, each on a fresh instance (and usually
## a fresh world). A test fails on a failed check, a timeout, or any engine or script error
## logged while it runs, including its setup and teardown (captured with a Logger). A test
## that logs an error and then doesn't finish within ERROR_GRACE seconds was aborted by that
## error, so it fails at once instead of waiting out the timeout. Failures are also printed
## as GitHub Actions annotations. Exits 0 when everything passes, 1 otherwise.
## `godot --import` exits 0 even with scripts that don't parse; test_project.gd is the parse gate.

const TESTS_DIR := "res://tests/"
const TEST_TIMEOUT := 60.0
## After an error is logged, how long an unfinished test gets before it counts as aborted.
const ERROR_GRACE := 0.5


class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()           # engine errors can arrive from worker threads (e.g. the navmesh bake)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		errors.append("%s (%s:%d in %s)" % [text, file.get_file(), line, function])
		_mutex.unlock()

	func has_errors() -> bool:
		_mutex.lock()
		var any := not errors.is_empty()
		_mutex.unlock()
		return any

	func take() -> Array[String]:
		_mutex.lock()
		var taken := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return taken


var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(_catcher)
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.get_slice("=", 1)

	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for file in _test_files():
		_catcher.take()
		var script := load(TESTS_DIR + file) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1                         # a broken test file must fail the gate, not vanish
			var reason := "; ".join(_catcher.take())
			print("  FAIL  %s  (failed to load: %s)" % [file, reason])
			print("::error title=%s::failed to load: %s" % [file, reason])
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_") or (filter != "" and not (file + test_name).contains(filter)):
				continue
			var result := await _run_test(script, test_name)
			var label := "%s::%s" % [file.get_basename(), test_name]
			if result.failures.is_empty():
				passed += 1
				print("  PASS  %s  (%.1f s)" % [label, result.seconds])
			else:
				failed += 1
				print("  FAIL  %s  (%.1f s)" % [label, result.seconds])
				for failure: String in result.failures:
					print("        - " + failure)
					print("::error title=%s::%s" % [label, failure.replace("\n", " ")])
			if result.timed_out:
				print("Aborting: a timed-out test may still be running.")
				_finish(passed, failed, started)
				return
	_finish(passed, failed, started)


func _run_test(script: GDScript, test_name: String) -> Dictionary:
	_catcher.take()                         # drop anything logged between tests
	var case: RefCounted = script.new()
	case.tree = self
	var state := {"done": false}
	var start := Time.get_ticks_msec()
	var body := func() -> void:
		await Callable(case, test_name).call()
		state.done = true
	body.call()
	var error_seen := -1
	while not state.done and Time.get_ticks_msec() - start < TEST_TIMEOUT * 1000.0:
		if error_seen < 0 and _catcher.has_errors():
			error_seen = Time.get_ticks_msec()
		if error_seen >= 0 and Time.get_ticks_msec() - error_seen > ERROR_GRACE * 1000.0:
			break                               # the error aborted the test's coroutine
		await process_frame
	var failures: PackedStringArray = case.failures.duplicate()
	if not state.done:
		if error_seen >= 0:
			failures.append("aborted by an error")
		else:
			failures.append("timed out after %d s" % TEST_TIMEOUT)
	if state.done or error_seen >= 0:
		await case.free_world()
	for error in _catcher.take():           # errors from the test, its setup and its teardown
		failures.append("engine/script error: " + error)
	return {"failures": failures, "seconds": (Time.get_ticks_msec() - start) / 1000.0,
			"timed_out": not state.done and error_seen < 0}


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(TESTS_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()
	return files


func _finish(passed: int, failed: int, started: int) -> void:
	print("\n%d passed, %d failed in %.1f s" % [passed, failed, (Time.get_ticks_msec() - started) / 1000.0])
	if passed + failed == 0:
		print("::error title=tests::no tests ran")    # discovery broke: never let that pass as green
		failed = 1
	OS.remove_logger(_catcher)
	quit(1 if failed > 0 else 0)
