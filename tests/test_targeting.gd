extends "res://tests/test_case.gd"
## M7: lock-on targeting (acquire, cone, range, cycling, retarget, release, highlight) and the
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


func test_centring_beats_distance_when_acquiring() -> void:
	var player := await _setup()
	var centred := _wolf(Vector3(0, 0, -17))
	var off_centre := _wolf(Vector3(5.0 * sin(deg_to_rad(10.0)), 0, -5.0 * cos(deg_to_rad(10.0))))
	var tied := _wolf(Vector3(0.1, 0, -9))                    # ~0.6°: same as centred, but nearer
	await physics_frames(2)
	var targeting := player.targeting
	targeting.toggle_lock()
	check(targeting.current_target == tied, "near-equal angles fall back to distance")
	targeting.toggle_lock()
	tied.free()
	targeting.toggle_lock()
	check(targeting.current_target == centred, "a far centred enemy beats a near off-centre one")
	check(targeting.current_target != off_centre, "the 10° enemy isn't picked")


func test_any_enemy_in_range_can_be_locked_whatever_the_facing_or_cover() -> void:
	var player := await _setup()
	var behind := _wolf(Vector3(0, 0, 6))                     # behind the player and the camera
	_wall(Vector3(0, 1.5, 3))                                 # and behind a wall
	await physics_frames(2)
	player.targeting.toggle_lock()
	check(player.targeting.current_target == behind, "the enemy behind, behind cover, is locked")
	player.targeting.toggle_lock()
	var beside := _wolf(Vector3(4, 0, 1))                     # beside the player, nearer
	await physics_frames(2)
	player.targeting.toggle_lock()
	check(player.targeting.current_target == beside, "nobody in view: the nearest one is locked")
	player.targeting.toggle_lock()
	var ahead := _wolf(Vector3(1, 0, -14))                    # farther, but in view
	await physics_frames(2)
	player.targeting.toggle_lock()
	check(player.targeting.current_target == ahead, "someone in view still wins over nearer ones")
	player.targeting.toggle_lock()
	for wolf in [behind, beside, ahead]:
		wolf.position.z += 40.0                                # all out of combat range
	await physics_frames(2)
	player.targeting.toggle_lock()
	check(not player.targeting.is_locked(), "nobody within radius: no lock")


func test_the_lock_follows_the_nearest_enemy_and_clears_a_freed_target() -> void:
	var player := await _setup()
	var hud := PlayerHUD.new()
	hud.health = player.get_node("HealthComponent")
	hud.targeting = player.targeting
	add_to_stage(hud)
	var first := _wolf(Vector3(0, 0, -6))
	var near_behind := _wolf(Vector3(0, 0, 3))                # nearest, but out of view
	_wolf(Vector3(0.5, 0, -10))                               # in view, farther
	await physics_frames(2)
	var targeting := player.targeting
	targeting.set_target(first)
	check(not targeting.highlighted_meshes().is_empty(), "the target wears the highlight")
	var first_mesh := targeting.highlighted_meshes()[0]
	await physics_frames(2)
	check(hud.gauge_target() == first, "the gauge shows the target")
	first.health.take_damage(HitInfo.new(999.0))
	await physics_frames(2)
	check(targeting.current_target == near_behind, "the lock moved straight to the nearest enemy")
	await seconds(0.3)                                        # past the death's hit flash
	check(first_mesh.material_overlay == null, "the fallen target lost the highlight")
	# A fight reset frees the enemies outright: the lock and the gauge must let go.
	var survivors := player.get_tree().get_nodes_in_group(&"enemies")
	for enemy in survivors:
		enemy.free()
	await physics_frames(2)
	check(is_same(targeting.current_target, null), "a freed target is cleared, not kept as a dead reference")
	check(is_same(hud._gauge_target, null), "the gauge let go of the freed target (and redrew empty)")


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


func test_a_far_target_keeps_the_player_in_frame() -> void:
	var player := await _setup()
	player.targeting.set_target(_wolf(Vector3(0, 0, -17)))
	await seconds(1.5)
	var camera := player.camera.camera
	var head := player.global_position + Vector3.UP * 1.7
	var feet := player.global_position + Vector3.UP * 0.1
	check(not camera.is_position_behind(head), "the player is in front of the camera")
	var size := camera.get_viewport().get_visible_rect().size
	for point in [head, feet]:
		var screen := camera.unproject_position(point)
		check(Rect2(Vector2.ZERO, size).has_point(screen), "player point %s on screen (%s)" % [point, screen])
	check(camera.global_position.distance_to(player.global_position) > 3.0, "the camera stays well behind the player")

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


func test_locked_on_movement_side_steps_at_the_clips_pace() -> void:
	var player := await _setup()
	var fsm := player.get_node("Combat") as CombatStateMachine
	var playback := fsm.animation_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	player.targeting.set_target(_wolf(Vector3(0, 0, -8)))
	await seconds(0.3)                                         # settle facing
	for step: Array in [[&"move_right", &"strafe_r"], [&"move_left", &"strafe_l"], [&"move_back", &"strafe_b"]]:
		Input.action_press(step[0])
		await seconds(0.5)
		check_eq(playback.get_current_node(), step[1], "clip for %s" % step[0])
		var speed := player.get_planar_speed()
		check_near(speed, player.walk_speed * player.lock_on_speed_scale, 0.15, "locked-on speed for %s" % step[0])
		check_near(fsm.animation_tree.get(CombatStateMachine.SIDE_STEPS[step[1]]), speed / fsm.side_step_speed, 0.05,
				"%s plays at the ground speed" % step[1])
		Input.action_release(step[0])
		await seconds(0.3)
	# Toward the target is a run; without a lock, so is any direction.
	Input.action_press(&"move_forward")
	await seconds(0.4)
	check_eq(playback.get_current_node(), &"run", "clip toward the target")
	Input.action_release(&"move_forward")
	player.targeting.set_target(null)
	Input.action_press(&"move_right")
	await seconds(0.5)
	Input.action_release(&"move_right")
	check_eq(playback.get_current_node(), &"run", "clip without a lock")
	check(player.get_planar_speed() > player.walk_speed * 0.9, "full walk speed without a lock")

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


func test_a_freed_lock_target_is_harmless_before_the_lock_moves_on() -> void:
	var player := await _setup()
	var fsm := player.get_node("Combat") as CombatStateMachine
	var target := _wolf(Vector3(0, 0, -3))
	player.targeting.set_target(target)
	await physics_frames(2)
	target.free()                                              # gone before TargetingSystem notices
	check(fsm.execution_target() == null, "no execution target (and no error) for a freed lock")
	check(fsm.warping.find_target(Vector3.FORWARD) == null, "no lunge target (and no error) either")
	fsm.combo.push_input(ComboManager.DODGE)
	await physics_frames(3)
	check_eq(fsm.state, CombatStateMachine.State.DODGE, "a dodge still works")


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
