extends "res://tests/test_case.gd"
## Phase C (D16–D18): stamina, gear that cracks under blocks, the defensive posture cracking into
## exhaustion, and shrines that mend and refill.

const GRUNT := preload("res://scenes/mobs/enemy_grunt.tscn")
const SHRINE := preload("res://scenes/landmarks/checkpoint_shrine.tscn")
const R := HitInfo.Result
const S := EnemyCombatController.State
const CS := CombatStateMachine.State


func test_strikes_and_dodges_spend_stamina_and_a_perfect_dodge_is_free() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var stamina := fsm.stamina
	fsm.combo.push_input(ComboManager.LIGHT)
	await physics_frames(2)
	var strike := fsm.current_attack
	check_near(stamina.current, stamina.max_stamina - (fsm.strike_stamina_base + fsm.strike_stamina_per_poise * strike.poise_damage),
			0.01, "a light strike's cost")
	stamina.reset()
	await seconds(0.8)
	fsm.combo.push_input(ComboManager.DODGE)
	await physics_frames(2)
	check_eq(fsm.state, CS.DODGE, "dodging")
	check_near(stamina.current, stamina.max_stamina - fsm.dodge_stamina, 0.01, "a dodge's cost")
	var grunt := _grunt(Vector3(0, 0, -2))
	_hurtbox(player).receive_hit(CombatFixtures.make_hit(grunt, 10.0, 10.0))
	check_near(stamina.current, stamina.max_stamina, 0.01, "a perfect dodge refunds its cost")


func test_nothing_starts_without_stamina() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.stamina.drain(1000.0)
	fsm.combo.push_input(ComboManager.LIGHT)
	await physics_frames(3)
	check(fsm.state != CS.ATTACK, "no strike on empty")
	fsm.combo.clear_buffer()
	fsm.combo.push_input(ComboManager.DODGE)
	await physics_frames(3)
	check(fsm.state != CS.DODGE, "no dodge on empty")
	fsm.guard_pressed()
	check(not fsm.guard.is_guarding, "no guard on empty")


## Review fix: a guard button held on empty doesn't raise the guard on a later tick either.
func test_a_held_guard_waits_for_stamina() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.stamina.drain(1000.0)
	fsm.stamina.regen_rate = 0.0
	fsm.guard_pressed()
	await physics_frames(4)
	check(fsm.state != CS.GUARD and not fsm.guard.is_guarding, "no guard from locomotion while empty")
	fsm.stamina.regen_rate = 1000.0
	check(await wait_until(func() -> bool: return fsm.guard.is_guarding, 1.5), "the held guard rises once stamina is back")


## Review fix: a perfect dodge gives back what the dodge actually took, not the full cost.
func test_a_perfect_dodge_refunds_only_what_it_cost() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.stamina.drain(fsm.stamina.max_stamina - 5.0)      # 5 left, less than a dodge costs
	fsm.combo.push_input(ComboManager.DODGE)
	await physics_frames(2)
	check_eq(fsm.state, CS.DODGE, "a dodge on 5 stamina")
	_hurtbox(player).receive_hit(CombatFixtures.make_hit(_grunt(Vector3(0, 0, -2)), 10.0, 10.0))
	check_near(fsm.stamina.current, 5.0, 0.01, "back to where it started, not more")


## Review fix: each item keeps its own share of the wear, cracked partner or not.
func test_gear_wears_by_its_own_share() -> void:
	var gear := EquipmentDurability.new()
	add_to_stage(gear)
	gear.weapon = 0.0                                     # the weapon is already cracked
	var before := gear.armor
	gear.absorb(40.0)
	check_near(before - gear.armor, 40.0 * (1.0 - gear.weapon_share), 0.01, "the armour takes its share, not the whole hit")

func test_blocking_wears_the_gear_until_it_cracks_and_blocks_weaken() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var gear := fsm.equipment
	var health := fsm.health
	var cracked: Array = []
	gear.item_cracked.connect(func(item: StringName) -> void: cracked.append(item))
	fsm.guard_pressed()
	await seconds(0.4)                                        # past the parry window
	var attacker := _attacker(Vector3(0, 0, -2))
	var hits := 0
	while not gear.is_cracked(EquipmentDurability.WEAPON) and hits < 20:
		check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(attacker, 40.0, 4.0)), R.BLOCKED, "block %d" % hits)
		hits += 1
		fsm.posture.reset()
		fsm.stamina.reset()
	check(cracked.has(EquipmentDurability.WEAPON), "the weapon cracked (after %d blocks)" % hits)
	check_eq(health.current_health, health.max_health, "sound gear: blocks cost no health")
	check_near(gear.block_effectiveness(), 0.5, 0.001, "one cracked item halves blocking")
	var posture_before := fsm.posture.current
	_hurtbox(player).receive_hit(CombatFixtures.make_hit(attacker, 40.0, 4.0))
	check_near(health.current_health, health.max_health - 20.0, 0.01, "half the damage leaks through")
	check_near(fsm.posture.current - posture_before, 8.0, 0.01, "posture takes double")


func test_the_defensive_posture_cracks_into_exhaustion() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	var stamina := fsm.stamina
	stamina.regen_rate = 100.0
	fsm.posture.add_posture(95.0)
	fsm.guard_pressed()
	await seconds(0.4)
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 10.0, 10.0)), R.GUARD_BROKEN,
			"the block that fills posture")
	check(stamina.is_exhausted and stamina.current == 0.0, "the crack empties stamina and exhausts")
	fsm.guard_released()
	fsm.reaction.clear()                                      # skip the stagger: exhaustion alone locks
	await physics_frames(2)
	fsm.combo.push_input(ComboManager.LIGHT)
	await physics_frames(3)
	check(fsm.state != CS.ATTACK, "no strike while exhausted")
	check(await wait_until(func() -> bool: return not stamina.is_exhausted, 2.5), "never recovered")
	check(stamina.current >= stamina.max_stamina * stamina.lockout_ratio - 0.01, "recovered past 30%")
	fsm.combo.clear_buffer()
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return fsm.state == CS.ATTACK, 0.5), "strikes again once recovered")


func test_blocking_on_empty_cracks_the_guard() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.guard_pressed()
	await seconds(0.4)
	fsm.stamina.drain(1000.0)
	await physics_frames(2)
	check(fsm.guard.is_guarding, "an empty, held guard stays up")
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 10.0, 5.0)), R.GUARD_BROKEN,
			"blocking with nothing left")
	check(fsm.stamina.is_exhausted, "exhausted")


func test_a_shrine_mends_the_gear_and_refills_stamina() -> void:
	var player := await _stage_player()
	var fsm := _fsm(player)
	fsm.equipment.absorb(1000.0)
	fsm.stamina.crack()
	var shrine: CheckpointShrine = SHRINE.instantiate()
	shrine.position = Vector3(10, 0, 10)
	add_to_stage(shrine)
	await physics_frames(2)
	shrine.rest(player)
	check_near(fsm.equipment.block_effectiveness(), 1.0, 0.001, "gear mended")
	check(not fsm.stamina.is_exhausted and is_equal_approx(fsm.stamina.current, fsm.stamina.max_stamina), "stamina full")


func test_an_exhausted_enemy_holds_back() -> void:
	var player := await _stage_player()
	var grunt := _grunt(Vector3(0, 0, -1.8))
	var defense := grunt.get_node("Defense") as EnemyDefense
	defense.block_chance = 0.0
	defense.dodge_chance = 0.0
	await seconds(0.6)
	grunt.start_guard(5.0)
	grunt.posture.add_posture(grunt.posture.max_posture - 1.0)
	check_eq(_hurtbox(grunt).receive_hit(CombatFixtures.make_hit(player, 10.0, 10.0)), R.GUARD_BROKEN, "the grunt's guard breaks")
	check(grunt.stamina.is_exhausted, "its defensive posture cracked")
	check(not grunt.can_defend(), "it can't defend while exhausted")
	grunt.reaction.clear()                                    # skip the stagger
	grunt._cooldown_left = 0.0
	var attacked := [false]
	grunt.state_changed.connect(func(_previous: S, current: S) -> void:
		if current == S.ATTACK_WINDUP and grunt.stamina.is_exhausted:
			attacked[0] = true)
	await seconds(0.8)
	check(not attacked[0], "no attack while exhausted")


func test_an_enemy_strike_spends_its_stamina() -> void:
	await _stage_player()
	var grunt := _grunt(Vector3(0, 0, -2.2))
	var defense := grunt.get_node("Defense") as EnemyDefense
	defense.block_chance = 0.0
	defense.dodge_chance = 0.0
	check(await wait_until(func() -> bool: return grunt.state == S.ATTACK_WINDUP, 4.0), "the grunt never attacked")
	check_near(grunt.stamina.current, grunt.stamina.max_stamina - grunt.strike_stamina, 0.5, "an attack's cost")


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


func _grunt(at: Vector3) -> EnemyCombatController:
	var grunt: EnemyCombatController = GRUNT.instantiate()
	grunt.position = at + Vector3(0, 0.05, 0)
	return add_to_stage(grunt)


func _attacker(at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at
	return add_to_stage(node)


func _fsm(player: PlayerController) -> CombatStateMachine:
	return player.get_node("Combat") as CombatStateMachine


func _hurtbox(node: Node) -> Hurtbox:
	return node.get_node("Hurtbox") as Hurtbox
