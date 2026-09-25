extends "res://tests/test_case.gd"
## Samurai combat: buffered 3-hit combo (damage, hit-stop, wolf death and cleanup), sheathing,
## and attack input gating.


func test_buffered_combo_kills_a_wolf() -> void:
	await load_world()
	var target := wolf("Wolf2")
	target.bite = null                                   # isolate the combo: this wolf won't bite back
	var attacks: Array[String] = []
	combat().state_changed.connect(func(_from: int, to: int) -> void:
		var state: String = CombatStateMachine.State.keys()[to]
		if state.begins_with("ATTACK"):
			attacks.append(state))
	var hits := [0]
	target.health.damaged.connect(func(_hit: HitInfo) -> void: hits[0] += 1)

	place_player_near(target, 6.0)
	check(await wait_until(func() -> bool: return target.state == Wolf.State.CHASE, 2.0), "wolf never started chasing")
	check(await wait_until(func() -> bool: return _gap(target) < target.chase_stop_distance + 0.4, 4.0), "wolf never closed in")

	# The 2nd and 3rd presses land during the previous strike, so they must be buffered.
	press_attack()
	await seconds(0.08)
	press_attack()
	await seconds(0.35)
	press_attack()
	var min_time_scale := 1.0
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end:
		min_time_scale = minf(min_time_scale, Engine.time_scale)
		await tree.process_frame

	check_eq(attacks, ["ATTACK_1", "ATTACK_2", "ATTACK_3"] as Array[String], "combo chain")
	check_eq(hits[0], 3, "hits landed")
	check(target.health.is_dead, "wolf should die to 20 + 20 + 40 damage")
	check(min_time_scale < 0.5, "hit-stop never slowed time")
	check(not target.is_in_group(&"enemies"), "dead wolf is still targetable")
	check((target.get_node("CollisionShape3D") as CollisionShape3D).disabled, "dead wolf still collides")
	var target_id := target.get_instance_id()            # an ID, not the object: a lambda can't hold a freed object
	check(await wait_until(func() -> bool: return not is_instance_id_valid(target_id), 6.0), "dead wolf was never freed")


func test_katana_draws_then_sheathes_after_idle() -> void:
	await load_world()                                   # spawn is ~28 m from the nearest wolf
	var katana := world.find_child("Katana", true, false) as Node3D
	check_eq(katana.get_parent().name, &"BackSocket", "katana at start")
	press_attack()
	check(await wait_until(func() -> bool: return katana.get_parent().name == &"HandSocket", 1.0), "katana was never drawn")
	await seconds(2.5)                                   # attack (0.55 s) + part of the 3 s idle timer
	check_eq(katana.get_parent().name, &"HandSocket", "katana 2.5 s after attacking")
	check(await wait_until(func() -> bool: return katana.get_parent().name == &"BackSocket", 2.0), "katana was never sheathed")


func test_attack_input_gating() -> void:
	await load_world()
	var fsm := combat()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	fsm._unhandled_input(click)
	check_eq(fsm._press_msec, CombatStateMachine._NO_PRESS, "an uncaptured click must not attack")
	var action := InputEventAction.new()
	action.action = &"attack"
	action.pressed = true
	fsm._unhandled_input(action)
	check(fsm._press_msec != CombatStateMachine._NO_PRESS, "an attack action (key or touch button) must register")


func _gap(target: Node3D) -> float:
	var offset := target.global_position - player().global_position
	return Vector2(offset.x, offset.z).length()
