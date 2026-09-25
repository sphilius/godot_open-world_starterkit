extends TestCase
## TimeScale arbiter and HitStop on top of it (M1).


func test_slowest_request_wins_and_pop_restores() -> void:
	expect_eq(Engine.time_scale, 1.0, "normal speed with no requests")
	TimeScale.push(&"a", 0.5)
	TimeScale.push(&"b", 0.25)
	expect_eq(Engine.time_scale, 0.25, "minimum of 0.5 and 0.25")
	TimeScale.pop(&"b")
	expect_eq(Engine.time_scale, 0.5, "back to the remaining request")
	TimeScale.pop(&"a")
	expect_eq(Engine.time_scale, 1.0, "normal speed once empty")


func test_push_replaces_the_same_id_and_unknown_pop_is_harmless() -> void:
	TimeScale.push(&"a", 0.2)
	TimeScale.push(&"a", 0.6)
	expect_eq(Engine.time_scale, 0.6, "the second push replaces the first")
	TimeScale.pop(&"never_pushed")
	expect_eq(Engine.time_scale, 0.6)
	TimeScale.reset()
	expect_eq(Engine.time_scale, 1.0, "reset drops everything")
	expect(not TimeScale.has(&"a"))


func test_hit_stop_ending_during_slow_motion_keeps_the_slow_motion() -> void:
	TimeScale.push(&"death", 0.25)
	HitStop.trigger(0.05)
	expect_eq(Engine.time_scale, HitStop.FROZEN_TIME_SCALE, "frozen during the hit-stop")
	await await_seconds(0.2)
	expect_eq(Engine.time_scale, 0.25, "the death slow-motion survives the hit-stop ending")
	TimeScale.pop(&"death")
	expect_eq(Engine.time_scale, 1.0)


func test_overlapping_hit_stops_extend() -> void:
	HitStop.trigger(0.1)
	HitStop.trigger(0.5)                      # the longer request takes over
	await await_seconds(0.25)
	expect_eq(Engine.time_scale, HitStop.FROZEN_TIME_SCALE, "still frozen after the first stop's end")
	await await_seconds(0.4)
	expect_eq(Engine.time_scale, 1.0, "released after the longer stop")
