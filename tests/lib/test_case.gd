class_name TestCase
extends Node
## Base class for tests in res://tests/test_*.gd. The runner gives every `test_*` method a
## fresh instance of the file's script, parented under an empty Node3D "stage" in the running
## scene tree. Nodes added with add_to_stage() get `_ready()` and physics like in game, and are
## freed with the stage after the test. Test methods may `await`.

var failures := PackedStringArray()


## Records a failure (with the calling line) unless `condition` holds. Returns `condition`.
func expect(condition: bool, message := "expected true") -> bool:
	if not condition:
		failures.append("%s  [%s]" % [message, _caller()])
	return condition


func expect_eq(actual: Variant, expected: Variant, message := "") -> bool:
	var equal: bool = typeof(actual) == typeof(expected) and actual == expected
	return expect(equal, "%sexpected %s, got %s" % [_prefix(message), var_to_str(expected), var_to_str(actual)])


func expect_near(actual: float, expected: float, tolerance := 0.001, message := "") -> bool:
	return expect(absf(actual - expected) <= tolerance,
			"%sexpected %s ± %s, got %s" % [_prefix(message), expected, tolerance, actual])


## Adds `node` to the stage (so it enters the tree) and returns it.
func add_to_stage(node: Node) -> Node:
	get_parent().add_child(node)
	return node


func await_physics(frames := 2) -> void:
	for i in frames:
		await get_tree().physics_frame


## Waits `seconds` of wall-clock time (unaffected by Engine.time_scale). Polls the clock rather
## than using a SceneTree timer, which fires early when a long frame (script loading) lands
## inside the wait.
func await_seconds(seconds: float) -> void:
	var end_msec := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_msec:
		await get_tree().process_frame


static func _prefix(message: String) -> String:
	return "" if message.is_empty() else message + ": "


static func _caller() -> String:
	for backtrace in Engine.capture_script_backtraces():
		for i in backtrace.get_frame_count():
			var file := backtrace.get_frame_file(i)
			if not file.ends_with("test_case.gd"):
				return "%s:%d" % [file.get_file(), backtrace.get_frame_line(i)]
	return "?"
