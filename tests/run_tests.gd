extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --import                       # refresh the class cache first
##   godot --headless --path . --script res://tests/run_tests.gd [-- --filter=<text>]
##
## Runs every `test_*` method of every res://tests/test_*.gd (each extends TestCase). Each
## method gets a fresh instance under a fresh stage node in the scene tree, and may `await`.
## A test fails when an expectation fails, when the engine logs an error while it runs, or
## when it doesn't finish within TIMEOUT_SECONDS (a script error inside a coroutine aborts
## it without returning). `--filter` keeps the tests whose file or method name contains the text.
## Exits with 0 when everything passes, 1 otherwise.

const TEST_DIR := "res://tests/"
const TIMEOUT_SECONDS := 10.0
## After an error is logged, how long a still-running test gets to finish before it's abandoned.
const ERROR_GRACE_SECONDS := 0.5

var _errors := TestErrorCapture.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.get_slice("=", 1)

	var passed := 0
	var failed := PackedStringArray()
	for file in _test_files():
		var path := TEST_DIR + file
		_errors.take()
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed.append(_report(path, "failed to load", _errors.take()))
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			if not filter.is_empty() and not (filter in file or filter in test_name):
				continue
			var problems := await _run_test(script, test_name)
			if problems.is_empty():
				passed += 1
				print("  ok    %s  %s" % [file, test_name])
			else:
				failed.append(_report(file, test_name, problems))
				print("  FAIL  %s  %s" % [file, test_name])

	for report in failed:
		printerr(report)
	print("\n%d passed, %d failed" % [passed, failed.size()])
	OS.remove_logger(_errors)
	quit(0 if failed.is_empty() and passed > 0 else 1)


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd"):
			files.append(file)
	files.sort()
	return files


func _run_test(script: GDScript, method: String) -> PackedStringArray:
	_errors.take()                           # the capture window covers setup and teardown too
	var stage := Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var test: TestCase = script.new()
	test.name = method
	stage.add_child(test)

	var state := { done = false }
	_invoke(test, method, state)
	var start := Time.get_ticks_msec()
	var error_seen_msec := -1
	while not state.done:
		var now := Time.get_ticks_msec()
		if now - start > TIMEOUT_SECONDS * 1000.0:
			break
		if error_seen_msec < 0 and _errors.has_errors():
			error_seen_msec = now
		if error_seen_msec >= 0 and now - error_seen_msec > ERROR_GRACE_SECONDS * 1000.0:
			break
		await process_frame

	var problems := test.failures.duplicate()
	if not state.done:
		problems.append("did not finish (timed out, or aborted by a script error)")
	# Global state must not leak into the next test.
	TimeScale.reset()
	stage.queue_free()
	await process_frame
	problems.append_array(_errors.take())    # errors from the test, its setup and its teardown
	return problems


func _invoke(test: TestCase, method: String, state: Dictionary) -> void:
	await test.call(method)
	state.done = true


static func _report(file: String, test_name: String, problems: PackedStringArray) -> String:
	return "\nFAIL %s  %s\n    %s" % [file, test_name, "\n    ".join(problems)]
