extends "res://tests/test_case.gd"
## Phase B (playtest 1): enemies block, dodge and counter; elites and bosses parry and
## perfect-dodge; light-attack spam stops interrupting them.

const GRUNT := preload("res://scenes/mobs/enemy_grunt.tscn")
const BRUTE := preload("res://scenes/mobs/enemy_brute.tscn")
const GATEKEEPER := preload("res://scenes/mobs/enemy_gatekeeper.tscn")
const R := HitInfo.Result
const S := EnemyCombatController.State


func test_the_enemy_library_has_the_defence_clips() -> void:
	var clips := load("res://assets/characters/enemy/enemy_animations.res") as AnimationLibrary
	for clip: String in ["guard_idle", "guard_hit", "strafe_b"]:
		check(clips.has_animation(clip), "enemy clip '%s' is missing" % clip)


func test_a_blocking_grunt_blocks_then_counters() -> void:
	var player := await _stage_player()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -1.6), {block = 1.0, dodge = 0.0})
	var results: Array = []
	grunt.hurtbox.hit_received.connect(func(_hit: HitInfo, result: R) -> void: results.append(result))
	await seconds(0.6)                                    # it turns to face the player
	var fsm := _fsm(player)
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return grunt.state == S.GUARD, 0.5), "the grunt never raised its guard")
	check(await wait_until(func() -> bool: return results.size() >= 1, 1.0), "the first strike never reached it")
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return results.size() >= 2, 1.5), "the second strike never reached it")
	check(results.all(func(result: R) -> bool: return result == R.BLOCKED), "both blocked (%s)" % [results])
	check_eq(grunt.health.current_health, grunt.health.max_health, "blocked: no health lost")
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 0.5), "no counter after two blocks")
	check(not grunt.guard.is_guarding, "the guard dropped for the counter")


func test_a_dodging_grunt_evades_the_strike() -> void:
	var player := await _stage_player()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -1.6), {block = 0.0, dodge = 1.0})
	await seconds(0.6)                                    # it turns to face the player
	var start := grunt.global_position
	_fsm(player).combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return grunt.state == S.EVADE, 0.5), "the grunt never evaded")
	check(grunt.health.is_invulnerable(), "the backstep has i-frames")
	await seconds(0.6)
	check(grunt.global_position.distance_to(player.global_position) > start.distance_to(player.global_position) + 0.5,
			"it stepped away from the player")
	check_eq(grunt.health.current_health, grunt.health.max_health, "the strike missed")


func test_light_attack_spam_stops_flinching_an_enemy() -> void:
	var player := await _stage_player()
	var grunt := _enemy(GRUNT, Vector3(0, 0, -4), {block = 0.0, dodge = 0.0})
	await physics_frames(3)
	for i in 3:
		_hurtbox(grunt).receive_hit(CombatFixtures.make_hit(player, 1.0, 5.0))
		check_eq(grunt.state, S.STAGGERED, "light hit %d flinches" % (i + 1))
		await seconds(0.35)                                 # the flinch (0.3 s) ends
	check(grunt.reaction.is_flinch_immune(), "three quick flinches: it shrugs off the next ones")
	var before := grunt.health.current_health
	_hurtbox(grunt).receive_hit(CombatFixtures.make_hit(player, 1.0, 5.0))
	check(grunt.state != S.STAGGERED, "the fourth light hit doesn't flinch it")
	check(grunt.health.current_health < before, "but still hurts")
	_hurtbox(grunt).receive_hit(CombatFixtures.make_hit(player, 1.0, 40.0))
	check_eq(grunt.state, S.STAGGERED, "a heavy hit still staggers")


func test_an_elite_parries_from_its_guard_and_counters() -> void:
	var player := await _stage_player()
	var brute := _enemy(BRUTE, Vector3(0, 0, -1.8), {block = 1.0, dodge = 0.0, parry = 1.0, perfect = 0.0})
	var results: Array = []
	brute.hurtbox.hit_received.connect(func(_hit: HitInfo, result: R) -> void: results.append(result))
	await seconds(0.6)                                    # it turns to face the player
	var fsm := _fsm(player)
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return not results.is_empty(), 1.0), "the strike never reached the brute")
	if results.is_empty():
		return
	check_eq(results[0], R.PARRIED, "the brute parried")
	check_eq(fsm.state, CombatStateMachine.State.HURT, "the player reels")
	check_eq(fsm.reaction.stagger_type, &"parried", "the player's reaction")
	check(await wait_until(func() -> bool: return brute.state == S.ATTACK_WINDUP, 0.5), "no counter after the parry")


func test_a_boss_perfect_dodges_the_blade_and_counters() -> void:
	var player := await _stage_player()
	var boss := _enemy(GATEKEEPER, Vector3(0, 0, -2.0), {block = 0.0, dodge = 0.0, parry = 0.0, perfect = 1.0})
	await seconds(0.6)                                    # it turns to face the player
	var fsm := _fsm(player)
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return boss.state == S.EVADE, 1.0), "the boss never evaded")
	check(boss.health.is_invulnerable(), "evading on the blade's frame: invulnerable")
	check_eq(fsm.reaction.stagger_type, &"evaded", "the player is left open")
	check(await wait_until(func() -> bool: return boss.state == S.ATTACK_WINDUP, 1.0), "no counter after the perfect dodge")
	check_eq(boss.health.current_health, boss.health.max_health, "the strike missed")


func _stage_player() -> PlayerController:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_to_stage(player)
	await physics_frames(3)
	return player


## An enemy that holds its ground (a long attack cooldown keeps it flanking in place, free to
## defend), with its defence rolls pinned and no reaction delay.
func _enemy(scene: PackedScene, at: Vector3, chances: Dictionary) -> EnemyCombatController:
	var enemy: EnemyCombatController = scene.instantiate()
	enemy.position = at + Vector3(0, 0.05, 0)
	enemy._cooldown_left = 99.0
	var defense := enemy.get_node("Defense") as EnemyDefense
	defense.block_chance = chances.get("block", 0.0)
	defense.dodge_chance = chances.get("dodge", 0.0)
	defense.parry_chance = chances.get("parry", 0.0)
	defense.perfect_dodge_chance = chances.get("perfect", 0.0)
	defense.reaction_time = Vector2.ZERO
	return add_to_stage(enemy)


func _fsm(player: PlayerController) -> CombatStateMachine:
	return player.get_node("Combat") as CombatStateMachine


func _hurtbox(node: Node) -> Hurtbox:
	return node.get_node("Hurtbox") as Hurtbox
