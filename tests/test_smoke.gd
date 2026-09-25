extends TestCase
## Smoke tests on the shipped scenes and the combat components they're built from.


func test_player_and_wolf_spawn_at_full_health() -> void:
	var player: PlayerController = add_to_stage(CombatFixtures.PLAYER_SCENE.instantiate())
	player.spawn_at(Vector3(0, 0.1, 6), 0.0)
	var wolf := add_to_stage(CombatFixtures.make_idle_wolf()) as Wolf
	await await_physics(3)
	var player_health := HealthComponent.resolve(player)
	expect_eq(player_health.current_health, player_health.max_health, "player health")
	expect_eq(wolf.health.current_health, wolf.health.max_health, "wolf health")


func test_hitbox_hits_each_target_once_per_activation() -> void:
	var wolf := add_to_stage(CombatFixtures.make_idle_wolf()) as Wolf
	var hitbox: Hitbox = add_to_stage(CombatFixtures.make_hitbox())
	var attack := CombatFixtures.make_attack(10.0)
	var landed := [0]
	hitbox.hit_landed.connect(func(_target: HealthComponent, _hit: HitInfo) -> void: landed[0] += 1)

	# The box overlaps both the wolf's body and its hurtbox: still one hit per activation.
	hitbox.begin(attack)
	hitbox.set_active(true)
	await await_physics(4)
	expect_eq(wolf.health.current_health, 50.0, "after the first activation")
	await await_physics(4)
	expect_eq(wolf.health.current_health, 50.0, "no second hit in the same activation")
	expect_eq(landed[0], 1, "hit_landed count")

	hitbox.set_active(false)
	await await_physics(2)
	hitbox.begin(attack)
	hitbox.set_active(true)
	await await_physics(4)
	expect_eq(wolf.health.current_health, 40.0, "a new activation hits again")
	hitbox.set_active(false)
	await await_seconds(0.15)                  # let the wolf's hit flash finish before teardown


func test_invulnerability_time_blocks_the_next_hit() -> void:
	var health := HealthComponent.new()
	health.invulnerability_time = 0.5
	add_to_stage(health)
	expect(health.take_damage(HitInfo.new(10.0)), "first hit applies")
	expect(not health.take_damage(HitInfo.new(10.0)), "second hit inside the i-frames is refused")
	expect_eq(health.current_health, 90.0)


func test_resolve_finds_health_from_hurtbox_component_or_body() -> void:
	var body := Node3D.new()
	add_to_stage(body)
	var hurtbox := CombatFixtures.make_target(body)
	var health := hurtbox.health
	expect(HealthComponent.resolve(hurtbox) == health, "from a Hurtbox")
	expect(HealthComponent.resolve(health) == health, "from a HealthComponent")
	expect(HealthComponent.resolve(body) == health, "from a body with a HealthComponent child")
	var empty := Node3D.new()
	expect(HealthComponent.resolve(empty) == null, "null when there is none")
	empty.free()
