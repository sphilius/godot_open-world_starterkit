extends "res://tests/test_case.gd"
## M7: lock-on targeting (acquire, cone, line of sight, cycling, retarget, release) and the
## combat camera and player behaviour while locked.


func test_lock_picks_the_enemy_nearest_the_centre_of_view() -> void:
	var player := await _setup()
	var centre := _wolf(Vector3(0, 0, -6))
	_wolf(Vector3(3, 0, -6))                                  # ~27° off centre
	_wolf(Vector3(0, 0, 6))                                   # behind
	_wolf(Vector3(0, 0, -25))                                 # beyond radius
	await physics_frames(2)
	var targeting := player.targeting
	targeting.toggle_lock()
	check(targeting.current_target == centre, "locked the enemy in the middle of the view")
	targeting.toggle_lock()
	check(not targeting.is_locked(), "a second toggle releases the lock")


func test_cone_and_line_of_sight_filter_targets() -> void:
	var player := await _setup()
	var off_angle := _wolf(Vector3(5, 0, -5))                 # 45°: outside the 70° cone
	await physics_frames(2)
	player.targeting.toggle_lock()
	check(not player.targeting.is_locked(), "an enemy outside the cone isn't locked")
	off_angle.position = Vector3(0, 0, -8)
	_wall(Vector3(0, 1.5, -4))
	await physics_frames(2)
	player.targeting.toggle_lock()
	check(not player.targeting.is_locked(), "an enemy behind a wall isn't locked")


func test_cycling_follows_screen_position() -> void:
	var player := await _setup()
	var left := _wolf(Vector3(-2.5, 0, -8))
	var centre := _wolf(Vector3(0, 0, -8))
	var right := _wolf(Vector3(2.5, 0, -8))
	await physics_frames(2)
	var targeting := player.targeting
	targeting.toggle_lock()
	check(targeting.current_target == centre, "starts on the centre enemy")
	targeting.cycle(1)
	check(targeting.current_target == right, "next goes right")
	targeting.cycle(1)
	check(targeting.current_target == right, "nothing further right: stays")
	targeting.cycle(-1)
	targeting.cycle(-1)
	check(targeting.current_target == left, "previous goes left, one enemy at a time")


func test_right_stick_flick_cycles_once_per_flick() -> void:
	var player := await _setup()
	var centre := _wolf(Vector3(0, 0, -8))
	var right := _wolf(Vector3(2.5, 0, -8))
	var far_right := _wolf(Vector3(5, 0, -8))
	await physics_frames(2)
	var targeting := player.targeting
	targeting.set_target(centre)
	Input.action_press(&"look_right", 1.0)
	await tree.process_frame
	await tree.process_frame
	check(targeting.current_target == right, "a flick right switches once")
	Input.action_release(&"look_right")
	await tree.process_frame
	Input.action_press(&"look_right", 1.0)
	await tree.process_frame
	check(targeting.current_target == far_right, "a second flick switches again")
	Input.action_release(&"look_right")


func test_lock_moves_on_when_the_target_dies_and_releases_when_alone() -> void:
	var player := await _setup()
	var first := _wolf(Vector3(0, 0, -6))
	var second := _wolf(Vector3(1.5, 0, -7))
	await physics_frames(2)
	var targeting := player.targeting
	targeting.set_target(first)
	first.health.take_damage(HitInfo.new(999.0))
	await physics_frames(2)
	check(targeting.current_target == second, "the lock moved to the next enemy")
	player.global_position = Vector3(0, 0.05, 30)             # past break_distance
	await physics_frames(2)
	check(not targeting.is_locked(), "the lock released with nobody left in reach")
	await seconds(0.1)


func test_camera_frames_the_target_and_keeps_its_view_on_release() -> void:
	var player := await _setup()
	var target := _wolf(Vector3(8, 0, 0))                     # 90° to the right
	await physics_frames(2)
	var camera := player.camera
	var free_arm := camera.spring_arm.spring_length
	player.targeting.set_target(target)
	await seconds(1.5)
	check_near(wrapf(camera.yaw, -PI, PI), -PI / 2.0, 0.1, "camera yaw turned to look past the player at the target")
	check(camera.spring_arm.spring_length > free_arm + 0.3, "the arm lengthens to frame both")
	var yaw_locked := camera.yaw
	player.targeting.set_target(null)
	await seconds(0.5)
	check_near(camera.yaw, yaw_locked, 0.01, "releasing the lock doesn't snap the view")
	player.add_look_input(Vector2(0.3, 0.0))
	await seconds(0.5)
	check(absf(camera.yaw - yaw_locked) > 0.2, "free look works again after release")


func test_look_input_is_ignored_while_locked() -> void:
	var player := await _setup()
	player.targeting.set_target(_wolf(Vector3(0, 0, -6)))
	await physics_frames(2)
	var before := player.camera.target_yaw
	player.add_look_input(Vector2(0.5, 0.2))
	check_near(player.camera.target_yaw, before, 0.0001, "look input while locked")


func test_player_strafes_while_facing_the_target() -> void:
	var player := await _setup()
	player.targeting.set_target(_wolf(Vector3(0, 0, -8)))
	await physics_frames(2)
	var start := player.global_position
	Input.action_press(&"move_right")
	await seconds(0.6)
	Input.action_release(&"move_right")
	check(player.global_position.x - start.x > 1.0, "moved sideways (%s)" % (player.global_position - start))
	check(player.get_facing().dot(Vector3.FORWARD) > 0.95, "kept facing the target while strafing")


func test_locked_dodge_goes_sideways_and_keeps_facing() -> void:
	var player := await _setup()
	var fsm := player.get_node("Combat") as CombatStateMachine
	player.targeting.set_target(_wolf(Vector3(0, 0, -8)))
	await seconds(0.3)                                         # settle facing
	var directions: Array[Vector3] = []
	fsm.dodge_started.connect(func(direction: Vector3) -> void: directions.append(direction))
	Input.action_press(&"move_left")
	await physics_frames(2)
	fsm.combo.push_input(ComboManager.DODGE)
	check(await wait_until(func() -> bool: return not directions.is_empty(), 1.0), "the dodge never started")
	Input.action_release(&"move_left")
	if not directions.is_empty():
		check(directions[0].dot(Vector3.LEFT) > 0.9, "dodged left (%s)" % directions[0])
	check(player.get_facing().dot(Vector3.FORWARD) > 0.95, "kept facing the target through the dodge")
	check_eq(CombatStateMachine.dodge_clip(player.get_facing(), directions[0] if directions else Vector3.ZERO), &"dodge_l", "clip")


# --- Helpers ---------------------------------------------------------------------------------

## Floor plus a player at the origin facing -Z, with the camera settled behind it.
func _setup() -> PlayerController:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_to_stage(player)
	await physics_frames(3)
	return player


func _wolf(at: Vector3) -> Wolf:
	var wolf := CombatFixtures.make_idle_wolf()
	wolf.position = at
	add_to_stage(wolf)
	return wolf


func _wall(at: Vector3) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = at
	add_to_stage(wall)
