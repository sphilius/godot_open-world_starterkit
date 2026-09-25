extends "res://tests/test_case.gd"
## TimeScale arbiter and HitStop on top of it (M1).


func test_slowest_request_wins_and_pop_restores() -> void:
	check_eq(Engine.time_scale, 1.0, "normal speed with no requests")
	TimeScale.push(&"a", 0.5)
	TimeScale.push(&"b", 0.25)
	check_eq(Engine.time_scale, 0.25, "minimum of 0.5 and 0.25")
	TimeScale.pop(&"b")
	check_eq(Engine.time_scale, 0.5, "back to the remaining request")
	TimeScale.pop(&"a")
	check_eq(Engine.time_scale, 1.0, "normal speed once empty")


func test_push_replaces_the_same_id_and_unknown_pop_is_harmless() -> void:
	TimeScale.push(&"a", 0.2)
	TimeScale.push(&"a", 0.6)
	check_eq(Engine.time_scale, 0.6, "the second push replaces the first")
	TimeScale.pop(&"never_pushed")
	check_eq(Engine.time_scale, 0.6, "time scale")
	TimeScale.reset()
	check_eq(Engine.time_scale, 1.0, "reset drops everything")
	check(not TimeScale.has(&"a"), "request gone after reset")


func test_hit_stop_ending_during_slow_motion_keeps_the_slow_motion() -> void:
	TimeScale.push(&"death", 0.25)
	HitStop.trigger(0.05)
	check_eq(Engine.time_scale, HitStop.FROZEN_TIME_SCALE, "frozen during the hit-stop")
	await seconds(0.2)
	check_eq(Engine.time_scale, 0.25, "the death slow-motion survives the hit-stop ending")
	TimeScale.pop(&"death")
	check_eq(Engine.time_scale, 1.0, "time scale")


func test_hit_stop_rearms_after_a_reset() -> void:
	HitStop.trigger(0.5)
	TimeScale.reset()                         # a scene change drops the pending stop
	check_eq(Engine.time_scale, 1.0, "time scale")
	HitStop.trigger(0.05)                     # shorter than the stale deadline
	check_eq(Engine.time_scale, HitStop.FROZEN_TIME_SCALE, "a new hit still freezes")
	await seconds(0.6)                  # outlive the first stop's timer
	check_eq(Engine.time_scale, 1.0, "released")


func test_overlapping_hit_stops_extend() -> void:
	HitStop.trigger(0.1)
	HitStop.trigger(0.5)                      # the longer request takes over
	await seconds(0.25)
	check_eq(Engine.time_scale, HitStop.FROZEN_TIME_SCALE, "still frozen after the first stop's end")
	await seconds(0.4)
	check_eq(Engine.time_scale, 1.0, "released after the longer stop")
