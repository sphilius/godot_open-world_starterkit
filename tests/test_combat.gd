extends "res://tests/test_case.gd"
## Samurai combat: buffered 3-hit combo from sheathed (quick-draw opener, damage, hit-stop,
## wolf death and cleanup), sheathing, and attack input gating.


func test_buffered_combo_kills_a_wolf() -> void:
	await load_world()
	var target := wolf("Wolf2")
	target.bite = null                                   # isolate the combo: this wolf won't bite back
	var attacks: Array[String] = []
	combat().attack_started.connect(func(attack: AttackData) -> void: attacks.append(String(attack.animation)))
	var hits := [0]
	target.health.damaged.connect(func(_hit: HitInfo) -> void: hits[0] += 1)

	place_player_near(target, 6.0)
	check(await wait_until(func() -> bool: return target.state == Wolf.State.CHASE, 2.0), "wolf never started chasing")
	# The wolf stops steering once it's within chase_stop_distance + bite_range_slack (3D) and then
	# brakes, so its flat gap settles just around that line: allow a margin, and time for the
	# chase path (1.8-3.5 s here). Motion warping covers the rest of the gap.
	check(await wait_until(func() -> bool:
		return _gap(target) < target.chase_stop_distance + target.bite_range_slack + 0.3, 6.0), "wolf never closed in")

	# The 2nd and 3rd presses land during the previous strike, so they must be buffered. The
	# katana starts sheathed, so the chain opens with the quick-draw strike.
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

	check_eq(attacks, ["draw_attack", "attack_2", "attack_3"] as Array[String], "combo chain")
	check_eq(hits[0], 3, "hits landed")
	check(target.health.is_dead, "wolf should die to 28 + 20 + 40 damage")
	check(min_time_scale < 0.5, "hit-stop never slowed time")
	check(not target.is_in_group(&"enemies"), "dead wolf is still targetable")
	check((target.get_node("CollisionShape3D") as CollisionShape3D).disabled, "dead wolf still collides")
	var target_id := target.get_instance_id()            # an ID, not the object: a lambda can't hold a freed object
	check(await wait_until(func() -> bool: return not is_instance_id_valid(target_id), 6.0), "dead wolf was never freed")


func test_katana_draws_then_sheathes_after_idle() -> void:
	await load_world()                                   # spawn is ~28 m from the nearest wolf
	var katana := world.find_child("Katana", true, false) as Node3D
	check_eq(katana.get_parent().name, &"SheathSocket", "katana at start")
	press_attack()
	check(await wait_until(func() -> bool: return katana.get_parent().name == &"HandSocket", 1.0), "katana was never drawn")
	await seconds(2.5)                                   # attack (0.5 s) + part of the 3 s idle timer
	check_eq(katana.get_parent().name, &"HandSocket", "katana 2.5 s after attacking")
	check(await wait_until(func() -> bool: return katana.get_parent().name == &"SheathSocket", 2.0), "katana was never sheathed")


func test_attack_input_gating() -> void:
	await load_world()
	var fsm := combat()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	fsm._unhandled_input(click)
	check(not fsm.combo.has_buffered(), "an uncaptured click must not attack")
	var action := InputEventAction.new()
	action.action = &"attack"
	action.pressed = true
	fsm._unhandled_input(action)
	check_eq(fsm.combo.peek(), ComboManager.LIGHT, "an attack action (key or touch button) must register")


func _gap(target: Node3D) -> float:
	var offset := target.global_position - player().global_position
	return Vector2(offset.x, offset.z).length()
