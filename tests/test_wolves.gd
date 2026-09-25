extends "res://tests/test_case.gd"
## Wolf AI: wander and chase on the baked navmesh, the bite (damage, player flinch, interrupt),
## and the player's death and respawn.


func test_wolves_wander_then_chase() -> void:
	await load_world()
	var wolves := world.get_node("Wolves").get_children()
	var homes := {}
	for w: Wolf in wolves:
		homes[w] = w.global_position
	await seconds(6.0)                                   # the wander interval is 4 s (staggered per wolf)
	var moved := 0
	for w: Wolf in wolves:
		var offset: Vector3 = w.global_position - homes[w]
		if Vector2(offset.x, offset.z).length() > 1.0:
			moved += 1
		check(w.is_on_floor(), "%s isn't standing on the terrain" % w.name)
		check_eq(w.state, Wolf.State.WANDER, "%s state with no player around" % w.name)
	check(moved >= 3, "only %d of %d wolves wandered" % [moved, wolves.size()])

	var target := wolf("Wolf3")
	place_player_near(target, 7.0)                       # inside the 10 m detection sphere
	check(await wait_until(func() -> bool: return target.state == Wolf.State.CHASE, 2.0), "wolf didn't chase a player 7 m away")


func test_bite_hurts_and_staggers_the_player() -> void:
	await load_world()
	var biter := wolf("Wolf2")
	var health := player().get_node("HealthComponent") as HealthComponent
	var flinched := [false]
	combat().state_changed.connect(func(_from: int, to: int) -> void:
		if to == CombatStateMachine.State.HURT:
			flinched[0] = true)
	var bites := [0]
	biter.bite_hitbox.hit_landed.connect(func(_target: HealthComponent, _hit: HitInfo) -> void: bites[0] += 1)

	place_player_near(biter, 5.0)
	check(await wait_until(func() -> bool: return bites[0] >= 1, 8.0), "the wolf never landed a bite")
	check(health.current_health <= health.max_health - biter.bite.damage, "a bite didn't cost health")
	check(flinched[0], "the player didn't flinch (HURT) when bitten")


func test_striking_a_winding_up_wolf_cancels_its_bite() -> void:
	await load_world()
	var biter := wolf("Wolf3")
	var health := player().get_node("HealthComponent") as HealthComponent
	place_player_near(biter, 4.0)
	var caught := await wait_until(func() -> bool:
		return biter.state == Wolf.State.BITE and biter._bite_time > 0.02 and biter._bite_time < 0.12, 8.0)
	if not check(caught, "never caught a bite wind-up to interrupt"):
		return
	var health_before := health.current_health
	press_attack()
	check(await wait_until(func() -> bool: return biter.state == Wolf.State.STAGGER, 1.0), "the wolf wasn't staggered")
	check(not biter.bite_hitbox.is_active(), "the cancelled bite's hitbox is still active")
	await seconds(0.5)
	check_eq(health.current_health, health_before, "player health after a cancelled bite")


func test_player_death_and_respawn() -> void:
	await load_world()
	var biter := wolf("Wolf2")
	var health := player().get_node("HealthComponent") as HealthComponent
	place_player_near(biter, 5.0)
	var spawn := player()._spawn_position
	health.current_health = 5.0                          # the next bite is lethal
	check(await wait_until(func() -> bool: return health.is_dead, 8.0), "the player never died")
	check_eq(combat().state, CombatStateMachine.State.DEAD, "player state on death")
	check(await wait_until(func() -> bool:
		return biter.state != Wolf.State.CHASE and biter.state != Wolf.State.BITE, 2.0), "the wolf kept hunting a defeated player")
	check(await wait_until(func() -> bool: return not health.is_dead, combat().respawn_delay + 1.0), "the player never respawned")
	check_eq(health.current_health, health.max_health, "health after respawn")
	check_eq(combat().state, CombatStateMachine.State.IDLE, "player state after respawn")
	check(player().global_position.distance_to(spawn) < 0.5, "the player didn't respawn at the spawn point")
