extends "res://tests/test_case.gd"
## M6 AI: CombatDirector (tokens, cooldown, leases, flank ring), EnemyCombatController (approach,
## telegraph glints, strikes, token release on every exit path, reactions, execution) and the
## Gatekeeper's phase 2 and boss bar.

const GRUNT := preload("res://scenes/mobs/enemy_grunt.tscn")
const BRUTE := preload("res://scenes/mobs/enemy_brute.tscn")
const GATEKEEPER := preload("res://scenes/mobs/enemy_gatekeeper.tscn")
const S := EnemyCombatController.State
const ATTACKING := [EnemyCombatController.State.ATTACK_WINDUP, EnemyCombatController.State.ATTACK_ACTIVE,
		EnemyCombatController.State.RECOVER]


# --- CombatDirector ----------------------------------------------------------------------------

func test_tokens_are_capped_and_reissue_after_the_cooldown() -> void:
	var director := _director()
	var a := _dummy(Vector3.ZERO)
	var b := _dummy(Vector3.ZERO)
	var c := _dummy(Vector3.ZERO)
	check(director.request_attack_token(a), "first token")
	check(director.request_attack_token(b), "second token")
	check(not director.request_attack_token(c), "a third enemy waits (max_attack_tokens = 2)")
	check(director.request_attack_token(a), "asking again while holding one is a yes")
	director.release_attack_token(a)
	check(not director.request_attack_token(c), "no token right after a release (cooldown)")
	await seconds(0.9)
	check(director.request_attack_token(c), "a token after the 0.8 s cooldown")
	check_eq(director.token_count(), 2, "tokens out")


func test_leases_expire_and_unregistering_releases() -> void:
	var director := _director()
	director.token_lease_time = 0.2
	var a := _dummy(Vector3.ZERO)
	var b := _dummy(Vector3.ZERO)
	director.register(a)
	director.register(b)
	director.request_attack_token(a)
	await seconds(0.3)
	check(not director.has_attack_token(a), "a lease older than token_lease_time expired")
	await seconds(0.9)
	check(director.request_attack_token(b), "b got a token")
	director.unregister(b)
	check_eq(director.token_count(), 0, "unregistering (death) released the token")
	check(not director.is_registered(b), "unregistered")


func test_ring_slots_are_even_and_leave_the_gap_behind_the_player() -> void:
	var director := _director()
	var player := _dummy(Vector3.ZERO)                   # faces -Z, so "behind" is +Z
	for count in [3, 4]:
		director.max_flank_tokens = count
		var angles: Array[float] = []
		for index in count:
			var direction := director.slot_direction(index, player)
			check(direction.angle_to(Vector3.BACK) > deg_to_rad(40.0), "%d slots: slot %d isn't behind the player" % [count, index])
			angles.append(atan2(direction.x, direction.z))
		angles.sort()
		for index in count:
			var gap := wrapf(angles[(index + 1) % count] - angles[index], 0.0, TAU)
			check_near(gap, TAU / count, 0.001, "%d slots: spacing" % count)


func test_slot_assignment_is_unique_and_sticky() -> void:
	var director := _director()
	director.max_flank_tokens = 3
	var player := _dummy(Vector3.ZERO)
	var slot0 := director.slot_direction(0, player) * director.ring_radius
	var slot1 := director.slot_direction(1, player) * director.ring_radius
	var a := _dummy(slot0 * 1.2)
	var b := _dummy(slot0 * 1.3)
	director.register(a)
	director.register(b)
	var spot_a := director.get_flank_position(a, player)
	var spot_b := director.get_flank_position(b, player)
	check(spot_a.distance_to(slot0) < 0.01, "the nearest enemy takes the nearest slot")
	check(spot_b.distance_to(spot_a) > 1.0, "the next enemy gets a different slot")
	a.position = slot0.lerp(slot1, 0.55)                 # a bit nearer slot 1, but not by 1.5 m
	check(director.get_flank_position(a, player).distance_to(slot0) < 0.01, "hysteresis keeps the slot")
	var fourth := _dummy(Vector3(0, 0, 9))
	director.register(fourth)
	var c := _dummy(Vector3(9, 0, 0))
	director.register(c)
	director.get_flank_position(c, player)
	var outer := director.get_flank_position(fourth, player)
	check_near(outer.length(), director.outer_ring_radius, 0.01, "with every slot taken, it waits on the outer ring")


# --- EnemyCombatController ---------------------------------------------------------------------

func test_grunt_approaches_glints_gold_and_hits_the_player() -> void:
	var player := await _stage_player()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -6), _director())
	var health := player.get_node("HealthComponent") as HealthComponent
	var glints: Array = []
	grunt.telegraph_glint.connect(func(_point: Vector3, unblockable: bool) -> void:
		glints.append([unblockable, grunt._attack_time, grunt.current_attack]))
	check(await wait_until(func() -> bool: return not glints.is_empty(), 5.0), "the grunt never telegraphed a strike")
	if glints.is_empty():
		return
	var attack: AttackData = glints[0][2]
	check(not glints[0][0], "a grunt strike is blockable")
	check_near(glints[0][1], attack.active_start - grunt.telegraph_lead, 0.05, "the glint leads the active frames by 0.4 s")
	check_eq(grunt.glint.last_color, TelegraphGlint.GOLD, "glint colour")
	check(await wait_until(func() -> bool: return health.current_health < health.max_health, 2.0), "the strike never landed")


func test_brute_thrust_glints_red_and_ignores_the_guard() -> void:
	var player := await _stage_player()
	var brute := _enemy(BRUTE, Vector3(0, 0, -5), null, func(enemy: EnemyCombatController) -> void:
		enemy.attacks = [load("res://resources/combat/enemies/brute_thrust.tres")] as Array[AttackData])
	var fsm := player.get_node("Combat") as CombatStateMachine
	var health := player.get_node("HealthComponent") as HealthComponent
	var red := [false]
	brute.telegraph_glint.connect(func(_point: Vector3, unblockable: bool) -> void: red[0] = unblockable)
	check(await wait_until(func() -> bool: return brute.state == S.ATTACK_WINDUP, 5.0), "the brute never attacked")
	fsm.guard_pressed()
	await seconds(0.2)                                   # past the parry window: guard only
	check(await wait_until(func() -> bool: return health.current_health < health.max_health, 2.0), "the thrust didn't land")
	check(red[0], "the thrust glinted red")
	check_eq(brute.glint.last_color, TelegraphGlint.RED, "glint colour")
	check(fsm.guard.is_guarding or fsm.state == CombatStateMachine.State.HURT, "the guard was up (or the hit staggered it)")


func test_the_token_is_released_on_every_exit_path() -> void:
	var player := await _stage_player()
	var director := _director()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -2.2), director)
	# 1. The attack ends normally.
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 3.0), "no attack started")
	check_eq(director.token_count(), 1, "an attacking grunt holds a token")
	check(await wait_until(func() -> bool: return grunt.state not in ATTACKING, 3.0), "the attack never ended")
	check(not director.has_attack_token(grunt), "released when the attack ended")
	# 2. Staggered mid-wind-up.
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 4.0), "no second attack")
	_hurtbox(grunt).receive_hit(CombatFixtures.make_hit(player, 1.0, 5.0))
	check_eq(grunt.state, S.STAGGERED, "state after a hit")
	check(not director.has_attack_token(grunt), "released when staggered")
	check(not grunt.weapon_hitbox.is_active(), "the weapon is off")
	# 3. Reset mid-attack.
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 5.0), "no third attack")
	grunt.reset_to_spawn()
	check(not director.has_attack_token(grunt) and director.is_registered(grunt), "released (still registered) on reset")
	check_eq(grunt.state, S.IDLE, "state after reset")
	# 4. Killed mid-attack.
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 5.0), "no fourth attack")
	_hurtbox(grunt).receive_hit(CombatFixtures.make_hit(player, 999.0, 0.0))
	check_eq(grunt.state, S.DEAD, "state after a lethal hit")
	check(not director.has_attack_token(grunt) and not director.is_registered(grunt), "released and unregistered on death")
	check(not grunt.is_in_group(&"enemies"), "a dead grunt isn't targetable")
	# 5. Freed mid-attack.
	var second := _enemy(GRUNT, Vector3(1.5, 0, -2.2), director)
	check(await wait_until(func() -> bool: return second.state == S.ATTACK_WINDUP, 5.0), "the second grunt never attacked")
	second.queue_free()
	await physics_frames(1)
	check_eq(director.token_count(), 0, "released when freed")


func test_without_a_token_enemies_flank_on_the_ring() -> void:
	var player := await _stage_player()
	var director := _director()
	director.max_attack_tokens = 1
	var grunts: Array[EnemyCombatController] = []
	for x in [-3.0, 0.0, 3.0]:
		grunts.append(_enemy(GRUNT, Vector3(x, 0, -9), director))
	await seconds(2.5)
	var attackers := 0
	var flankers: Array[EnemyCombatController] = []
	for grunt in grunts:
		if grunt.state == S.FLANKING:
			flankers.append(grunt)
		elif grunt.state == S.APPROACH or grunt.state in ATTACKING:
			attackers += 1
	check(attackers <= 1, "at most one grunt attacks with max_attack_tokens = 1 (got %d)" % attackers)
	check(flankers.size() >= 2, "the others flank (got %d)" % flankers.size())
	for grunt in flankers:
		var gap := Vector2(grunt.global_position.x - player.global_position.x, grunt.global_position.z - player.global_position.z).length()
		check(absf(gap - director.ring_radius) < 1.6, "a flanker circles near the ring (%.1f m)" % gap)


func test_a_parried_grunt_recoils_and_loses_its_token() -> void:
	var player := await _stage_player()
	var director := _director()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -2.2), director)
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 3.0), "no attack started")
	var fsm := player.get_node("Combat") as CombatStateMachine
	fsm.guard_pressed()
	var hit := CombatFixtures.make_hit(grunt, 12.0, grunt.current_attack.poise_damage)
	check_eq(_hurtbox(player).receive_hit(hit), HitInfo.Result.PARRIED, "the parry")
	check_eq(grunt.state, S.STAGGERED, "the grunt staggers")
	check_eq(grunt.anim.current_animation, &"parried", "and plays its parried recoil")
	check(not director.has_attack_token(grunt), "and gives its token back")


func test_the_player_executes_a_posture_broken_grunt() -> void:
	var player := await _stage_player()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -2.0), null)
	grunt.set_physics_process(false)                     # stand still
	await physics_frames(2)
	var fsm := player.get_node("Combat") as CombatStateMachine
	check(fsm.execution_target() == null, "no execution while its posture holds")
	grunt.posture.add_posture(999.0)
	check(fsm.execution_target() == grunt, "a broken posture in front can be executed")
	press_attack_on(fsm)
	await physics_frames(2)
	check(fsm.current_attack == fsm.execution, "a light attack becomes the execution")
	check(fsm.health.is_invulnerable(), "executing is invulnerable")
	check(await wait_until(func() -> bool: return grunt.health.is_dead, 2.0), "the execution never killed the grunt")
	check(await wait_until(func() -> bool: return fsm.state != CombatStateMachine.State.ATTACK, 2.0), "the execution never ended")


func test_brute_execution_deals_its_share_and_resets_posture() -> void:
	await _stage_player()
	var brute := _enemy(BRUTE, Vector3(0, 0, -3), null)
	brute.set_physics_process(false)
	await physics_frames(1)
	check(not brute.execute(brute), "no execution without a posture break")
	brute.posture.add_posture(999.0)
	check(brute.execute(brute), "executed")
	check_near(brute.health.current_health, 160.0 * 0.4, 0.01, "an execution deals 60 % of a brute's health")
	check(not brute.posture.is_broken and brute.posture.current == 0.0, "posture reset")
	check_eq(brute.reaction.stagger_type, &"knockdown", "a survivor is knocked down")


# --- Gatekeeper --------------------------------------------------------------------------------

func test_gatekeeper_phase_two_roars_once_and_hardens() -> void:
	var player := await _stage_player()
	var boss: Gatekeeper = _enemy(GATEKEEPER, Vector3(0, 0, -8), _director())
	var phases: Array = []
	var roars: Array = []
	boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	boss.roared.connect(func(trauma: float) -> void: roars.append(trauma))
	var rate := boss.posture.recovery_rate
	var recovery := boss.recovery_scale
	_hurtbox(boss).receive_hit(CombatFixtures.make_hit(player, 200.0, 0.0))
	check_eq(boss.phase, 1, "phase at 67 %")
	_hurtbox(boss).receive_hit(CombatFixtures.make_hit(player, 150.0, 0.0))
	check_eq(boss.phase, 2, "phase at 42 %")
	check_eq(phases, [2], "phase_changed")
	check_eq(roars, [0.45], "roared with the trauma amount")
	check(boss.health.is_invulnerable(), "invulnerable while roaring")
	check_eq(boss.reaction.stagger_type, &"roar", "the roar holds over the hit's flinch")
	check_near(boss.posture.recovery_rate, rate * 2.0, 0.001, "posture regen doubles")
	check_near(boss.recovery_scale, recovery * 0.8, 0.001, "recovery 20 % faster")
	check(boss.combos.any(func(combo: EnemyCombo) -> bool: return combo.strikes.all(func(a: AttackData) -> bool: return a.unblockable)),
			"the red unblockable combo joined its attacks")
	await seconds(1.3)
	_hurtbox(boss).receive_hit(CombatFixtures.make_hit(player, 10.0, 0.0))
	check_eq(roars.size(), 1, "it roars only once")
	boss.posture.add_posture(9999.0)
	var before := boss.health.current_health
	check(boss.execute(player), "a broken boss can be executed")
	check_near(before - boss.health.current_health, 240.0, 0.01, "its execution deals 40 % of max health")


func test_engaging_the_gatekeeper_shows_its_bar_until_it_falls() -> void:
	var player := await _stage_player()
	var hud := PlayerHUD.new()
	hud.health = player.get_node("HealthComponent")
	add_to_stage(hud)
	var boss: Gatekeeper = _enemy(GATEKEEPER, Vector3(0, 0, -8), null)
	check(await wait_until(func() -> bool: return hud.showing_boss() == boss, 2.0), "the boss bar never appeared")
	_hurtbox(boss).receive_hit(CombatFixtures.make_hit(player, 9999.0, 0.0))
	check(await wait_until(func() -> bool: return hud.showing_boss() == null, 1.0), "the boss bar stayed after its defeat")
	check(is_instance_valid(boss) and boss.state == S.DEAD, "the Gatekeeper stays as a corpse (free_on_death off)")


# --- In the world ------------------------------------------------------------------------------

func test_the_sparring_yard_engages_on_the_navmesh() -> void:
	await load_world()
	var yard := world.get_node("Encounters/SparringYard")
	var grunt := yard.get_node("Grunt1") as EnemyCombatController
	var health := player().get_node("HealthComponent") as HealthComponent
	for enemy: EnemyCombatController in [grunt, yard.get_node("Grunt2"), yard.get_node("Brute")]:
		check(await wait_until(enemy.is_on_floor, 3.0), "%s never landed on the terrain" % enemy.name)
		check_eq(enemy.state, S.IDLE, "%s with the player far away" % enemy.name)
	place_player_near(grunt, 8.0)
	var glints := [0]
	for enemy in yard.get_children():
		if enemy is EnemyCombatController:
			enemy.telegraph_glint.connect(func(_p: Vector3, _u: bool) -> void: glints[0] += 1)
	check(await wait_until(func() -> bool: return glints[0] > 0, 6.0), "nobody in the yard attacked")
	check(await wait_until(func() -> bool: return health.current_health < health.max_health, 6.0), "the yard never landed a hit")
	var director := yard.get_node("Director") as CombatDirector
	check(director.token_count() <= director.max_attack_tokens, "tokens stay within the cap")


# --- Helpers -----------------------------------------------------------------------------------

func _director() -> CombatDirector:
	return add_to_stage(CombatDirector.new())


func _dummy(at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at
	return add_to_stage(node)


func _enemy(scene: PackedScene, at: Vector3, director: CombatDirector, tune := Callable()) -> EnemyCombatController:
	var enemy: EnemyCombatController = scene.instantiate()
	enemy.position = at + Vector3(0, 0.05, 0)
	enemy.director = director
	if tune.is_valid():
		tune.call(enemy)
	return add_to_stage(enemy)


## Floor plus a player at the origin facing -Z.
func _stage_player() -> PlayerController:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_to_stage(player)
	await physics_frames(3)
	return player


func press_attack_on(fsm: CombatStateMachine) -> void:
	fsm.combo.push_input(ComboManager.LIGHT)


func _hurtbox(body: Node) -> Hurtbox:
	return body.get_node("Hurtbox")
