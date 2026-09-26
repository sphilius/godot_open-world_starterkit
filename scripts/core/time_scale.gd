class_name TimeScale
extends RefCounted
## The only writer of Engine.time_scale. Systems that slow time (hit-stop, death slow-motion,
## executions) each push a named request, and the slowest request wins. When a request is
## popped, time returns to the slowest remaining one, or 1.0 when none are left. A hit-stop
## that ends during a death slow-motion therefore leaves time at the slow-motion scale instead
## of snapping back to normal speed.
##
## Every push must have a pop on every exit path. Pause doesn't use this: it uses
## SceneTree.paused.

static var _requests := {}   # StringName -> float


## Adds or replaces the request `id`.
static func push(id: StringName, scale: float) -> void:
	_requests[id] = maxf(scale, 0.0)
	_apply()


## Removes the request `id`. Popping an id that isn't pushed does nothing.
static func pop(id: StringName) -> void:
	if _requests.erase(id):
		_apply()


static func has(id: StringName) -> bool:
	return _requests.has(id)


## The scale currently applied: the minimum of all requests, or 1.0 when there are none.
static func get_scale() -> float:
	var scale := 1.0
	for value: float in _requests.values():
		scale = minf(scale, value)
	return scale


## Drops every request and restores normal speed (scene changes, tests).
static func reset() -> void:
	_requests.clear()
	_apply()


static func _apply() -> void:
	Engine.time_scale = get_scale()
