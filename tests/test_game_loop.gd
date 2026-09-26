extends "res://tests/test_case.gd"
## M9 game loop: the title and pause menus, checkpoint shrines, death slow motion and respawn at
## the checkpoint, per-beat lighting, the sanctum lock and the victory screen.

const GOLDEN_ENV := "res://resources/environment/golden_hour_environment.tres"
const DUSK := preload("res://resources/lighting/beat_dusk.tres")
const NIGHT := preload("res://resources/lighting/beat_night.tres")


func test_the_title_holds_the_world_until_begin() -> void:
	await load_world(false)
	var game := GameManager.find(tree)
	var menus := world.get_node("GameMenus") as GameMenus
	check_eq(game.state, GameManager.GameState.START_MENU, "state on launch")
	check(tree.paused, "the world waits behind the title")
	check_eq(menus.current_screen(), "title", "screen on launch")
	var start := player().global_position
	await physics_frames(10)
	check(player().global_position.distance_to(start) < 0.01, "the player stayed put behind the title")
	_button(menus, "Begin").pressed.emit()
	check(not tree.paused, "Begin unpauses")
	check_eq(game.state, GameManager.GameState.EXPLORATION, "state after Begin")
	check_eq(menus.current_screen(), "", "no menu in play")


func test_pause_toggles_and_return_to_shrine_respawns() -> void:
	await load_world()
	var menus := world.get_node("GameMenus") as GameMenus
	var game := GameManager.find(tree)
	await _tap(&"pause")
	check(tree.paused and menus.current_screen() == "pause", "the pause action opens the pause menu")
	await _tap(&"pause")
	check(not tree.paused and menus.current_screen() == "", "pressing it again resumes")
	var shrine := world.get_node("Shrines/PathShrine") as CheckpointShrine
	game.set_checkpoint(shrine)
	menus.set_paused(true)
	_button(menus, "Return to shrine").pressed.emit()
	check(not tree.paused, "Return to shrine resumes play")
	check(player().global_position.distance_to(shrine.respawn_position()) < 0.3, "Return to shrine puts the player at the shrine")


func test_a_shrine_heals_saves_the_checkpoint_and_death_respawns_there() -> void:
	await load_world()
	var game := GameManager.find(tree)
	var terrain := world.get_node("Terrain") as HeightmapTerrain
	var shrine := world.get_node("Shrines/PathShrine") as CheckpointShrine
	check_near(shrine.global_position.y, terrain.height_at(shrine.global_position.x, shrine.global_position.z), 0.01, "the shrine stands on the ground")
	var health := player().get_node("HealthComponent") as HealthComponent
	health.chip(60.0)
	player().spawn_at(shrine.respawn_position() + Vector3(0, 0.2, 0), 0.0)
	check(await wait_until(func() -> bool: return shrine.is_lit, 2.0), "walking up to the shrine never lit it")
	check_eq(health.current_health, health.max_health, "resting healed the player")
	check(game.checkpoint == shrine, "the lit shrine is the checkpoint")
	player().global_position = COURTYARD_APPROACH                  # walk away (spawn_at would move the checkpoint), then die
	await physics_frames(3)
	health.take_damage(CombatFixtures.make_hit(null, 9999.0, 0.0))
	check_near(TimeScale.get_scale(), game.death_slow_motion_scale, 0.001, "death slows the world down")
	check_eq(game.deaths, 1, "the death was counted")
	var menus := world.get_node("GameMenus") as GameMenus
	check(await wait_until(func() -> bool: return menus.fade_alpha() > 0.95, 3.0), "the screen never faded to black")
	check(await wait_until(func() -> bool: return not health.is_dead, 8.0), "the player never respawned")
	check(await wait_until(func() -> bool: return menus.fade_alpha() < 0.05, 2.0), "the screen never faded back in")
	check(player().global_position.distance_to(shrine.respawn_position()) < 0.5, "the player respawned at the shrine, not the path start")
	check(await wait_until(func() -> bool: return is_equal_approx(TimeScale.get_scale(), 1.0), 2.0), "the slow motion wore off")


func test_lighting_moves_forward_beat_by_beat() -> void:
	await load_world()
	var game := GameManager.find(tree)
	game.beat_blend_time = 0.2
	var environment := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := world.get_node("Sun") as DirectionalLight3D
	var courtyard := world.get_node("Courtyard/Encounter") as Encounter
	var sanctum := world.get_node("Sanctum/Encounter") as Encounter
	courtyard.start(player())
	check_eq(game.state, GameManager.GameState.COURTYARD_AMBUSH, "state once the ambush starts")
	await seconds(0.4)
	check_near(sun.light_energy, DUSK.sun_energy, 0.01, "the courtyard fight blends to dusk")
	courtyard.reset()
	check_eq(game.state, GameManager.GameState.EXPLORATION, "a reset fight goes back to exploring")
	check_eq(game.beat, 1, "the light doesn't go back to golden hour")
	sanctum.start(player())
	check_eq(game.state, GameManager.GameState.SANCTUM_GATEKEEPER, "state once the boss fight starts")
	await seconds(0.4)
	check_near(environment.volumetric_fog_density, NIGHT.volumetric_fog_density, 0.0005, "the sanctum fight blends to night")
	check_near((load(GOLDEN_ENV) as Environment).volumetric_fog_density, 0.004, 0.0001, "the shared environment resource is untouched")


func test_clearing_the_courtyard_unlocks_the_sanctum_and_the_boss_ends_the_run() -> void:
	await load_world()
	var game := GameManager.find(tree)
	game.victory_delay = 0.2
	var menus := world.get_node("GameMenus") as GameMenus
	var gate := world.get_node("Sanctum/SanctumGate") as LevelGate
	check(not gate.is_open, "the sanctum is locked at first")
	(world.get_node("Courtyard/Encounter") as Encounter).cleared.emit()
	check(gate.is_open, "clearing the courtyard unlocks the sanctum")
	var sanctum := world.get_node("Sanctum/Encounter") as Encounter
	sanctum.start(player())
	check(await wait_until(func() -> bool: return not sanctum.alive_enemies().is_empty(), 2.0), "the Gatekeeper never appeared")
	await physics_frames(3)
	for enemy in sanctum.alive_enemies():
		(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(CombatFixtures.make_hit(player(), 99999.0, 0.0))
	check(await wait_until(func() -> bool: return game.state == GameManager.GameState.VICTORY_SCREEN, 6.0), "the victory screen never came")
	check(tree.paused, "the world pauses behind the victory screen")
	check_eq(menus.current_screen(), "victory", "screen after the boss")
	check(game.stats()[&"time"] > 0.0, "the run was timed")
	check_eq(GameMenus.format_time(125.4), "2:05", "time format")


const COURTYARD_APPROACH := Vector3(-6, 3, -58)


## Presses and releases `action` across process frames (menus poll is_action_just_pressed).
func _tap(action: StringName) -> void:
	Input.action_press(action)
	await tree.process_frame
	await tree.process_frame
	Input.action_release(action)
	await tree.process_frame


func _button(menus: GameMenus, text: String) -> Button:
	for button in menus.find_children("*", "Button", true, false):
		if (button as Button).text == text and (button as Button).is_visible_in_tree():
			return button
	for button in menus.find_children("*", "Button", true, false):
		if (button as Button).text == text:
			return button
	return null
