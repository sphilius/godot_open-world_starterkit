extends TestCase
## End-to-end combat on the shipped scenes: input → combat FSM → animated katana → Hitbox →
## Hurtbox → HealthComponent, and the wolf's AI bite against the player.


func test_attack_input_lands_the_katana_on_a_wolf() -> void:
	_add_floor()
	_spawn_player(Vector3(0, 0.05, 0))                   # yaw 0 faces -Z
	var wolf := CombatFixtures.make_idle_wolf()
	wolf.position = Vector3(0, 0, -1.4)
	add_to_stage(wolf)
	await await_physics(3)

	_press_attack()
	await await_seconds(0.8)
	expect(wolf.health.current_health < wolf.health.max_health,
			"the first strike lands (wolf health %s)" % wolf.health.current_health)
	await await_seconds(0.2)                              # let hit flash and hit-stop finish


func test_wolf_bite_lands_on_the_player() -> void:
	_add_floor()
	# Inside bite range from the start: with no navmesh in the test, the wolf can't close in.
	var player := _spawn_player(Vector3(0, 0.05, -1.9))
	var wolf: Wolf = CombatFixtures.WOLF_SCENE.instantiate()
	wolf.position = Vector3(0, 0.05, 0)                  # faces -Z, toward the player
	add_to_stage(wolf)
	var player_health := HealthComponent.resolve(player)
	var deadline := Time.get_ticks_msec() + 4000
	while player_health.current_health >= player_health.max_health and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	expect(player_health.current_health < player_health.max_health, "the wolf's bite lands")
	await await_seconds(0.2)


## Positioned before entering the tree, so no two bodies ever overlap at the origin.
func _spawn_player(at: Vector3) -> PlayerController:
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = at
	add_to_stage(player)
	return player


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)


func _press_attack() -> void:
	var press := InputEventAction.new()
	press.action = &"attack"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = &"attack"
	Input.parse_input_event(release)
