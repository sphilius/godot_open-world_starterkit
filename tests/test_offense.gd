extends "res://tests/test_case.gd"
## M3 offense: the combo buffer and graph, motion warping, dodge (i-frames, cancels), the heavy
## branch, and AttackData fields reaching HitInfo.

const SWORD_COMBO := preload("res://resources/combat/sword_combo.tres")
const LIGHT := ComboManager.LIGHT
const HEAVY := ComboManager.HEAVY
const DODGE := ComboManager.DODGE


## Stand-in for TargetingSystem.
class StubTargeting:
	extends Node
	var current_target: Node3D


# --- ComboManager ------------------------------------------------------------------------------

func test_buffer_is_fifo_and_presses_expire() -> void:
	var combo := _combo()
	combo.buffer_window = 0.15
	combo.push_input(DODGE)
	combo.push_input(LIGHT)
	check_eq(combo.consume([LIGHT] as Array[StringName]), &"", "the older dodge blocks the light press behind it")
	check_eq(combo.consume([DODGE, LIGHT] as Array[StringName]), DODGE, "oldest first")
	check_eq(combo.consume([LIGHT] as Array[StringName]), LIGHT, "then the light press")
	combo.push_input(HEAVY)
	await seconds(0.25)
	check(not combo.has_buffered(), "a press older than buffer_window must expire")


func test_graph_branches_and_quick_draw() -> void:
	var combo := _combo()
	check_eq(_name(combo.next_attack(LIGHT)), "attack_1", "neutral light")
	check_eq(_name(combo.next_attack(HEAVY)), "heavy_2", "light → heavy branch")
	combo.reset()
	combo.next_attack(LIGHT)
	combo.next_attack(LIGHT)
	check_eq(_name(combo.next_attack(HEAVY)), "heavy_finisher", "light, light → heavy finisher")
	check(not combo.has_branch(LIGHT), "nothing chains after the finisher")
	combo.reset()
	check_eq(_name(combo.next_attack(HEAVY)), "heavy_1", "neutral heavy")
	combo.reset()
	check_eq(_name(combo.next_attack(LIGHT, true)), "draw_attack", "attacking from sheathed opens with the quick-draw")
	check_eq(_name(combo.next_attack(LIGHT, true)), "attack_2", "the quick-draw flows into the light chain")


func test_chain_survives_recovery_until_the_reset_time() -> void:
	var combo := _combo()
	combo.combo_reset_time = 0.2
	var resets := [0]
	combo.combo_reset.connect(func() -> void: resets[0] += 1)
	combo.next_attack(LIGHT)
	combo.attack_finished()
	await seconds(0.05)
	check_eq(_name(combo.next_attack(LIGHT)), "attack_2", "a press soon after recovery continues the chain")
	combo.attack_finished()
	await seconds(0.3)
	check_eq(resets[0], 1, "combo_reset emitted once")
	check_eq(_name(combo.next_attack(LIGHT)), "attack_1", "after the reset time the chain starts over")


func test_a_new_chain_can_start_right_after_a_finisher() -> void:
	var combo := _combo()
	combo.next_attack(LIGHT)
	combo.next_attack(LIGHT)
	combo.next_attack(LIGHT)                                  # attack_3: nothing chains from it
	combo.attack_finished()
	check(combo.has_branch(LIGHT), "light is available right after the finisher ends")
	check_eq(_name(combo.next_attack(LIGHT)), "attack_1", "it starts a new chain")
	combo.reset()
	combo.next_attack(HEAVY)                                  # heavy_1 only chains into light
	combo.attack_finished()
	check_eq(_name(combo.next_attack(HEAVY)), "heavy_1", "a press with no branch after recovery starts from neutral")
	combo.attack_finished()
	check_eq(_name(combo.next_attack(LIGHT)), "attack_2", "a press that does branch still continues the chain")


func test_no_branch_mid_strike_does_not_restart() -> void:
	var combo := _combo()
	combo.next_attack(LIGHT)
	combo.next_attack(LIGHT)
	combo.next_attack(LIGHT)                                  # attack_3 still playing (not finished)
	check(not combo.has_branch(LIGHT), "no restart while the finisher is still playing")


# --- MotionWarping ---------------------------------------------------------------------------

func test_warp_speed_clamps_and_never_pulls_back() -> void:
	var warping := MotionWarping.new()
	add_to_stage(warping)
	check_near(warping.warp_speed(2.2, 0.2), (2.2 - warping.stop_distance) / 0.2, 0.001, "closes the gap to stop_distance")
	check_eq(warping.warp_speed(0.5, 0.2), 0.0, "already closer than stop_distance: no pull backwards")
	check_near(warping.warp_speed(30.0, 1.0), warping.max_warp_distance, 0.001, "travel clamped to max_warp_distance")
	check_eq(warping.warp_speed(30.0, 0.1), warping.max_warp_speed, "speed clamped to max_warp_speed")


func test_soft_lock_respects_angle_and_reach() -> void:
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)                 # faces -Z
	var warping := player.get_node("Combat/MotionWarping") as MotionWarping
	var ahead := _idle_wolf(Vector3(1.2, 0, -2.0))            # ~31° off the facing
	var beside := _idle_wolf(Vector3(2.5, 0, 0))              # 90°
	await physics_frames(2)
	check(warping.find_target(player.get_facing()) == ahead, "enemy within the angle and reach is picked")
	ahead.position = Vector3(0, 0, -6.0)                      # beyond max_warp_distance + stop_distance
	await physics_frames(1)
	check(warping.find_target(player.get_facing()) == null, "enemies out of reach or off-angle are ignored")
	var targeting := StubTargeting.new()
	add_to_stage(targeting)
	targeting.current_target = beside
	warping.targeting = targeting
	check(warping.find_target(player.get_facing()) == beside, "a lock-on target always wins")
	var plan := warping.plan(load("res://resources/combat/attack_1.tres"))
	check((plan.direction as Vector3).dot(Vector3.RIGHT) > 0.99, "the lunge points at the locked target")


func test_warp_off_keeps_the_strike_own_lunge() -> void:
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)                 # faces -Z
	var warping := player.get_node("Combat/MotionWarping") as MotionWarping
	_idle_wolf(Vector3(1.2, 0, -2.0))
	await physics_frames(2)
	var attack := (load("res://resources/combat/attack_1.tres") as AttackData).duplicate() as AttackData
	attack.warp = false
	var plan := warping.plan(attack)
	check(plan.target == null, "no target with warp off")
	check((plan.direction as Vector3).dot(Vector3.FORWARD) > 0.99, "keeps the facing direction (%s)" % plan.direction)
	check_eq(plan.speed, attack.lunge_speed, "keeps its own lunge speed")


func test_eased_lunge_covers_speed_times_duration() -> void:
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)
	(player.get_node("Combat") as Node).process_mode = Node.PROCESS_MODE_DISABLED   # drive the body directly
	await physics_frames(3)
	var start := player.global_position
	player.begin_attack(Vector3.FORWARD, 4.0, 0.25)
	await seconds(0.5)
	check_near(player.global_position.distance_to(start), 1.0, 0.2, "an average 4 m/s over 0.25 s moves about 1 m")


# --- Combat state machine --------------------------------------------------------------------

func test_dodge_grants_iframes_then_ends() -> void:
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)
	var fsm := player.get_node("Combat") as CombatStateMachine
	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	await physics_frames(3)
	fsm.combo.push_input(DODGE)
	check(await wait_until(func() -> bool: return fsm.state == CombatStateMachine.State.DODGE, 1.0), "dodge never started")
	await seconds(0.12)
	check_eq(hurtbox.receive_hit(HitInfo.new(10.0)), HitInfo.Result.IGNORED, "hit during the i-frames")
	check(await wait_until(func() -> bool: return fsm.state != CombatStateMachine.State.DODGE, 1.0), "dodge never ended")
	await seconds(0.3)
	check_eq(hurtbox.receive_hit(HitInfo.new(10.0)), HitInfo.Result.HIT, "hit after the dodge")


func test_backstep_without_input_and_directional_clips() -> void:
	check_eq(CombatStateMachine.dodge_clip(Vector3.FORWARD, Vector3.FORWARD), &"dodge_f", "forward")
	check_eq(CombatStateMachine.dodge_clip(Vector3.FORWARD, Vector3.BACK), &"dodge_b", "back")
	check_eq(CombatStateMachine.dodge_clip(Vector3.FORWARD, Vector3.RIGHT), &"dodge_r", "right")
	check_eq(CombatStateMachine.dodge_clip(Vector3.FORWARD, Vector3.LEFT), &"dodge_l", "left")
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)
	var fsm := player.get_node("Combat") as CombatStateMachine
	await physics_frames(3)
	var start := player.global_position
	fsm.combo.push_input(DODGE)
	await seconds(0.5)
	var moved := player.global_position - start
	check(moved.z > 1.5, "no input: the dodge backsteps (moved %s)" % moved)
	check(player.get_facing().dot(Vector3.FORWARD) > 0.99, "a backstep keeps the facing")


func test_light_then_heavy_plays_the_branch() -> void:
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)
	var fsm := player.get_node("Combat") as CombatStateMachine
	(player.get_node("WeaponHolster") as WeaponHolster).draw()    # drawn: no quick-draw opener
	await physics_frames(3)
	var attacks: Array[String] = []
	fsm.attack_started.connect(func(attack: AttackData) -> void: attacks.append(String(attack.animation)))
	fsm.combo.push_input(LIGHT)
	await seconds(0.1)
	fsm.combo.push_input(HEAVY)
	check(await wait_until(func() -> bool: return attacks.size() >= 2, 1.5), "the heavy press never chained")
	check_eq(attacks, ["attack_1", "heavy_2"] as Array[String], "strikes")


func test_dodge_cancels_heavy_windup_and_light_recovery() -> void:
	_add_floor()
	var player := _spawn_player(Vector3.ZERO)
	var fsm := player.get_node("Combat") as CombatStateMachine
	(player.get_node("WeaponHolster") as WeaponHolster).draw()
	await physics_frames(3)
	fsm.combo.push_input(HEAVY)
	check(await wait_until(func() -> bool: return fsm.current_attack != null, 1.0), "heavy never started")
	await seconds(0.1)
	fsm.combo.push_input(DODGE)
	check(await wait_until(func() -> bool: return fsm.state == CombatStateMachine.State.DODGE, 0.3),
			"heavy_1's cancel window lets a dodge interrupt the wind-up")
	check(await wait_until(func() -> bool: return fsm.state != CombatStateMachine.State.DODGE, 1.0), "dodge never ended")
	await seconds(1.3)                                        # let the chain reset

	fsm.combo.push_input(LIGHT)
	check(await wait_until(func() -> bool: return fsm.current_attack != null, 1.0), "light never started")
	var attack := fsm.current_attack
	await seconds(0.05)
	fsm.combo.push_input(DODGE)                               # buffered during the swing
	check(await wait_until(func() -> bool: return fsm.state == CombatStateMachine.State.DODGE, 0.6), "no dodge out of recovery")
	check(fsm._state_time < attack.duration, "the dodge came during the recovery, not after the strike")


func test_attack_data_reaches_hit_info() -> void:
	var wolf := CombatFixtures.make_idle_wolf()
	add_to_stage(wolf)
	var source := Node3D.new()
	add_to_stage(source)
	source.position = Vector3(0, 0, 3)                        # behind the wolf, facing it (-Z)
	var hitbox: Hitbox = add_to_stage(CombatFixtures.make_hitbox())
	hitbox.source = source
	var attack := CombatFixtures.make_attack(5.0)
	attack.poise_damage = 33.0
	attack.damage_type = AttackData.DamageType.PIERCE
	attack.unblockable = true
	attack.knockback = 2.0
	attack.knockback_direction_override = Vector3.RIGHT      # attacker's right
	var hits: Array[HitInfo] = []
	hitbox.hit_landed.connect(func(_target: HealthComponent, hit: HitInfo) -> void: hits.append(hit))
	hitbox.begin(attack)
	hitbox.set_active(true)
	await physics_frames(4)
	if check_eq(hits.size(), 1, "hits"):
		var hit := hits[0]
		check_eq(hit.poise_damage, 33.0, "poise_damage")
		check_eq(hit.damage_type, AttackData.DamageType.PIERCE, "damage_type")
		check(hit.unblockable, "unblockable")
		check(hit.knockback.normalized().dot(Vector3.RIGHT) > 0.99, "knockback follows the override (%s)" % hit.knockback)
		check_near(hit.knockback.length(), 2.0, 0.001, "knockback speed")
	await seconds(0.15)


func test_knockback_override_follows_the_attacker_facing() -> void:
	var wolf := CombatFixtures.make_idle_wolf()
	add_to_stage(wolf)
	var source := FacingSource.new()                          # body unrotated, facing +X (like the player)
	add_to_stage(source)
	source.position = Vector3(-3, 0, 0)
	var hitbox: Hitbox = add_to_stage(CombatFixtures.make_hitbox())
	hitbox.source = source
	var attack := CombatFixtures.make_attack(5.0)
	attack.knockback = 2.0
	attack.knockback_direction_override = Vector3.RIGHT      # the attacker's right
	var hits: Array[HitInfo] = []
	hitbox.hit_landed.connect(func(_target: HealthComponent, hit: HitInfo) -> void: hits.append(hit))
	hitbox.begin(attack)
	hitbox.set_active(true)
	await physics_frames(4)
	if check_eq(hits.size(), 1, "hits"):
		# Facing +X, the attacker's right is +Z.
		check(hits[0].knockback.normalized().dot(Vector3.BACK) > 0.99, "knockback to the attacker's right (%s)" % hits[0].knockback)
	await seconds(0.15)


## An attacker whose node isn't rotated but reports a facing, like PlayerController.
class FacingSource:
	extends Node3D
	func get_facing() -> Vector3:
		return Vector3.RIGHT


# --- Helpers ---------------------------------------------------------------------------------

func _combo() -> ComboManager:
	var combo := ComboManager.new()
	combo.graph = SWORD_COMBO
	add_to_stage(combo)
	return combo


static func _name(attack: AttackData) -> String:
	return String(attack.animation) if attack else "<none>"


func _spawn_player(at: Vector3) -> PlayerController:
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = at + Vector3(0, 0.05, 0)
	add_to_stage(player)
	return player


func _idle_wolf(at: Vector3) -> Wolf:
	var wolf := CombatFixtures.make_idle_wolf()
	wolf.position = at
	add_to_stage(wolf)
	return wolf


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)
