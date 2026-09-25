class_name TestErrorCapture
extends Logger
## Records every engine, script and shader error logged while a test runs, so a test that
## triggers an error fails even when all its expectations pass. Warnings are ignored.
## The engine may log from any thread, hence the mutex.

var _mutex := Mutex.new()
var _errors := PackedStringArray()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if not rationale.is_empty() else code
	_mutex.lock()
	_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
	_mutex.unlock()


func has_errors() -> bool:
	_mutex.lock()
	var any := not _errors.is_empty()
	_mutex.unlock()
	return any


## Returns the errors recorded so far and clears them.
func take() -> PackedStringArray:
	_mutex.lock()
	var taken := _errors
	_errors = PackedStringArray()
	_mutex.unlock()
	return taken
