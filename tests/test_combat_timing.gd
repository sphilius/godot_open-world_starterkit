extends "res://tests/test_case.gd"
## Phase A (playtest 1): perfect dodges, parry counters, criticals, dodging out of a wind-up,
## and the slower guard walk.

const GRUNT := preload("res://scenes/mobs/enemy_grunt.tscn")
const R := HitInfo.Result
const S := EnemyCombatController.State


func test_a_hit_in_the_perfect_window_is_evaded_and_arms_a_critical() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var grunt := _grunt(Vector3(0, 0, -2))
	var dodged: Array = []
	fsm.perfect_dodged.connect(func(attacker: Node3D) -> void: dodged.append(attacker))
	await physics_frames(2)
	fsm.combo.push_input(ComboManager.DODGE)
	await physics_frames(2)
	check_eq(fsm.state, CombatStateMachine.State.DODGE, "dodging")
	var health := player.get_node("HealthComponent") as HealthComponent
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(grunt, 20.0, 15.0)), R.IGNORED, "the strike")
	check_eq(health.current_health, health.max_health, "no damage")
	check(dodged.size() == 1 and dodged[0] == grunt, "perfect_dodged names the attacker")
	check_eq(grunt.reaction.stagger_type, &"evaded", "the attacker's opening")
	check_eq(grunt.state, S.STAGGERED, "the attacker is staggered")
	check(fsm.is_critical_armed(), "the next strike is a critical")
	_hurtbox(player).receive_hit(CombatFixtures.make_hit(grunt, 20.0, 15.0))
	check_eq(dodged.size(), 1, "one perfect dodge per dodge")
	await seconds(0.3)


func test_a_late_hit_is_only_avoided_by_the_iframes() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var grunt := _grunt(Vector3(0, 0, -2))
	var dodged: Array = []
	fsm.perfect_dodged.connect(func(attacker: Node3D) -> void: dodged.append(attacker))
	await physics_frames(2)
	fsm.combo.push_input(ComboManager.DODGE)
	await seconds(0.25)                                   # past the 0.2 s perfect window, inside the i-frames
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(grunt)), R.IGNORED, "a hit in the i-frames")
	check(dodged.is_empty(), "no perfect dodge")
	check(not fsm.is_critical_armed(), "no critical")
	check(grunt.reaction.stagger_type != &"evaded", "the attacker isn't staggered")


func test_an_enemy_strike_opening_on_a_dodging_player_is_a_perfect_dodge() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var grunt := _grunt(Vector3(0, 0, -2.2))
	var dodged: Array = []
	fsm.perfect_dodged.connect(func(attacker: Node3D) -> void: dodged.append(attacker))
	check(await wait_until(func() -> bool:
		return grunt.state == S.ATTACK_WINDUP and grunt._attack_time >= grunt.current_attack.active_start - 0.1, 5.0),
		"the grunt never wound up")
	fsm.combo.push_input(ComboManager.DODGE)             # dodge 0.1 s before the swing opens
	check(await wait_until(func() -> bool: return not dodged.is_empty(), 0.6), "no perfect dodge")
	check_eq(grunt.reaction.stagger_type, &"evaded", "the grunt staggers")
	var health := player.get_node("HealthComponent") as HealthComponent
	await seconds(0.3)
	check_eq(health.current_health, health.max_health, "the strike never landed")


func test_a_parry_opens_a_longer_window_and_arms_a_critical() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var grunt := _grunt(Vector3(0, 0, -2))
	await physics_frames(2)
	fsm.guard_pressed()
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(grunt, 20.0, 15.0)), R.PARRIED, "the strike")
	check_eq(grunt.reaction.stagger_type, &"parried", "the attacker's reaction")
	var ratio := grunt.reaction.parried_time / grunt.reaction.evaded_time
	check(ratio >= 1.5 and ratio <= 2.0, "a parry opens 1.5–2x a perfect dodge's opening (%.2fx)" % ratio)
	check(fsm.is_critical_armed(), "the counter-attack is a critical")


func test_a_parry_that_breaks_posture_keeps_the_critical_for_the_whole_break() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var grunt := _grunt(Vector3(0, 0, -2))
	await physics_frames(2)
	grunt.posture.add_posture(grunt.posture.max_posture - 5.0)
	fsm.guard_pressed()
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(grunt, 20.0, 15.0)), R.PARRIED, "the strike")
	check(grunt.posture.is_broken, "the reflected poise broke its posture")
	check(fsm._critical_left >= grunt.posture.break_duration, "armed for the whole break (%.2f s, break %.2f s)"
			% [fsm._critical_left, grunt.posture.break_duration])


func test_a_wolf_bite_opening_on_a_dodging_player_is_a_perfect_dodge() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var wolf: Wolf = CombatFixtures.WOLF_SCENE.instantiate()
	wolf.position = Vector3(0, 0.05, -1.9)
	wolf.rotation.y = PI                                      # faces +Z, toward the player
	add_to_stage(wolf)
	var dodged: Array = []
	fsm.perfect_dodged.connect(func(attacker: Node3D) -> void: dodged.append(attacker))
	check(await wait_until(func() -> bool:
		return wolf.state == Wolf.State.BITE and wolf._bite_time >= wolf.bite.active_start - 0.1, 5.0), "the wolf never bit")
	fsm.combo.push_input(ComboManager.DODGE)
	check(await wait_until(func() -> bool: return not dodged.is_empty(), 0.6), "no perfect dodge on the bite")
	if not dodged.is_empty():
		check(dodged[0] == wolf, "the wolf is the attacker")
	check_eq(wolf.state, Wolf.State.STAGGER, "the wolf staggers")

func test_a_critical_doubles_the_next_strike_only() -> void:
	_add_floor()
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_to_stage(player)
	var wolf := CombatFixtures.make_idle_wolf()
	wolf.position = Vector3(0, 0, -1.4)
	add_to_stage(wolf)
	await physics_frames(3)
	var fsm := _fsm(player)
	var hits: Array[HitInfo] = []
	wolf.hurtbox.hit_received.connect(func(hit: HitInfo, _result: R) -> void: hits.append(hit))
	fsm.arm_critical(1.0)
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return not hits.is_empty(), 1.0), "the strike never landed")
	if hits.is_empty():
		return
	check(hits[0].critical, "the armed strike is a critical")
	check_near(hits[0].damage, hits[0].attack.damage * fsm.critical_multiplier, 0.01, "critical damage")
	check_near(hits[0].poise_damage, hits[0].attack.poise_damage * fsm.critical_multiplier, 0.01, "critical poise")
	check(not fsm.is_critical_armed(), "used up")
	await seconds(0.2)


func test_a_strike_can_be_dodged_out_of_before_its_active_frames() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.combo.push_input(ComboManager.LIGHT)
	await physics_frames(2)
	check_eq(fsm.state, CombatStateMachine.State.ATTACK, "swinging")
	check(fsm._state_time < fsm.current_attack.active_start, "still winding up")
	fsm.combo.push_input(ComboManager.DODGE)
	await physics_frames(2)
	check_eq(fsm.state, CombatStateMachine.State.DODGE, "the wind-up was dodged out of")
	fsm.guard_pressed()
	await seconds(0.5)
	check_near(player.move_speed_scale, 0.4, 0.001, "guarding walks at 40%")


func test_afterimages_freeze_the_pose_and_fade_out() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.combo.push_input(ComboManager.LIGHT)             # the sword is drawn, the pose is mid-swing
	await seconds(0.25)
	var visual := player.get_node("Visual") as Node3D
	var skeleton := visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ghost := Afterimage.spawn(stage, visual, Afterimage.DEFAULT_COLOR, 0.2)
	check(ghost != null, "an afterimage")
	if ghost == null:
		return
	var copy := ghost.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand := skeleton.find_bone("hand_r")
	var pose_at_spawn := skeleton.get_bone_global_pose(hand)
	await seconds(0.1)
	check(copy.get_bone_global_pose(hand).origin.is_equal_approx(pose_at_spawn.origin), "the copy keeps the pose it was made in")
	check(not skeleton.get_bone_global_pose(hand).origin.is_equal_approx(pose_at_spawn.origin), "while the fighter moves on")
	check(ghost.find_children("*", "MeshInstance3D", true, false).size() >= 5, "the meshes came along")
	check(ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "no hitboxes in the copy")
	check(ghost.find_children("*", "GPUParticles3D", true, false).is_empty(), "no trails in the copy")
	await seconds(0.3)
	check(not is_instance_valid(ghost), "the afterimage faded and freed itself")


func _stage_player() -> PlayerController:
	_add_floor()
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_to_stage(player)
	await physics_frames(3)
	return player


func _grunt(at: Vector3) -> EnemyCombatController:
	var grunt: EnemyCombatController = GRUNT.instantiate()
	grunt.position = at + Vector3(0, 0.05, 0)
	return add_to_stage(grunt)


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)


func _fsm(player: PlayerController) -> CombatStateMachine:
	return player.get_node("Combat") as CombatStateMachine


func _hurtbox(player: PlayerController) -> Hurtbox:
	return player.get_node("Hurtbox") as Hurtbox
