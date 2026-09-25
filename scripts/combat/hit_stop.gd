class_name HitStop
extends RefCounted
## Global hit-stop: time nearly freezes for a few frames when a strike lands, which sells the
## weight of the impact. Overlapping requests extend the stop instead of stacking, and the
## timer ignores time scale, so the freeze always ends on schedule.
## A static utility rather than an autoload, so it works in-game, in the editor and in tests.
## It goes through TimeScale, so a stop that ends during a slower request (a death slow-motion)
## leaves that request in force.

## Time scale while frozen. Not 0, so tweens and physics interpolation stay stable.
const FROZEN_TIME_SCALE := 0.03
const REQUEST_ID := &"hitstop"

static var _end_msec := 0
static var _token := 0


static func trigger(duration: float) -> void:
	if duration <= 0.0:
		return
	var end_msec := Time.get_ticks_msec() + int(duration * 1000.0)
	if end_msec <= _end_msec and TimeScale.has(REQUEST_ID):
		return                        # an ongoing, longer stop already covers this
	# (Without the request, a TimeScale.reset() cleared the stop: the old deadline is stale.)
	_end_msec = end_msec
	_token += 1
	var token := _token
	TimeScale.push(REQUEST_ID, FROZEN_TIME_SCALE)
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(duration, true, false, true).timeout
	if token == _token:               # only the most recent request ends the stop
		TimeScale.pop(REQUEST_ID)
