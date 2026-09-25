extends "res://tests/test_case.gd"
## M5 defense: PostureComponent, GuardComponent, ParrySystem and DamageReactionComponent on a
## bare fighter (every branch of the defender chain), then the player and wolf wiring.

const R := HitInfo.Result


# --- Posture -----------------------------------------------------------------------------------

func test_posture_breaks_when_full_and_resets_after_the_break() -> void:
	var fighter := _fighter(func(node: Node) -> void:
		if node is PostureComponent:
			node.break_duration = 0.2)
	var posture := _posture(fighter)
	var counts := {broken = 0, recovered = 0}
	posture.posture_broken.connect(func() -> void: counts.broken += 1)
	posture.posture_recovered.connect(func() -> void: counts.recovered += 1)
	check(not posture.add_posture(60.0), "60 of 100 doesn't break")
	check(posture.add_posture(50.0), "filling the meter breaks it")
	check(posture.is_broken and counts.broken == 1, "posture_broken fired once")
	check_eq(posture.current, 100.0, "the meter caps at max")
	check(not posture.add_posture(10.0), "posture damage while broken is ignored")
	await seconds(0.35)
	check(not posture.is_broken, "the break ended after break_duration")
	check_eq(posture.current, 0.0, "a break resets the meter to 0")
	check_eq(counts.recovered, 1, "posture_recovered count")


func test_posture_recovery_waits_then_scales_with_health_and_guard() -> void:
	var fighter := _fighter(func(node: Node) -> void:
		if node is PostureComponent:
			node.recovery_delay = 0.2)
	var posture := _posture(fighter)
	var health := fighter.get_node("HealthComponent") as HealthComponent
	posture.add_posture(50.0)
	await seconds(0.1)
	check_eq(posture.current, 50.0, "no recovery during recovery_delay")
	check_eq(posture.current_recovery_rate(), 0.0, "rate while waiting")
	await seconds(0.2)
	check_near(posture.current_recovery_rate(), 15.0, 0.001, "full-health rate")
	check(posture.current < 50.0, "posture recovers after the delay")
	health.current_health = 0.0
	check_near(posture.current_recovery_rate(), 15.0 * 0.25, 0.001, "near-dead rate (wounded_recovery_scale)")
	health.current_health = health.max_health
	_guard(fighter).set_guarding(true)
	check_near(posture.current_recovery_rate(), 30.0, 0.001, "guarding and standing still doubles it")
	fighter.velocity = Vector3(2, 0, 0)
	check_near(posture.current_recovery_rate(), 15.0, 0.001, "guarding while moving doesn't")


# --- Guard -------------------------------------------------------------------------------------

func test_guard_blocks_frontal_hits_into_posture() -> void:
	var fighter := _fighter()
	var front := _attacker(Vector3(0.5, 0, -3))
	var guard := _guard(fighter)
	var blocked := [0]
	guard.blocked.connect(func(_hit: HitInfo) -> void: blocked[0] += 1)
	guard.set_guarding(true)
	check_eq(_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(front, 20.0, 15.0)), R.BLOCKED, "frontal hit on a raised guard")
	check_eq(_health(fighter).current_health, 100.0, "a block costs no health")
	check_eq(_posture(fighter).current, 15.0, "a block adds its poise damage to posture")
	check_eq(blocked[0], 1, "blocked signal count")
	check(not _reaction(fighter).is_staggered, "a block doesn't stagger")


func test_guard_lets_rear_unblockable_and_unguarded_hits_through() -> void:
	var fighter := _fighter()
	var guard := _guard(fighter)
	var hurtbox := _hurtbox(fighter)
	guard.set_guarding(true)
	check_eq(hurtbox.receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, 3)), 5.0)), R.HIT, "a hit from behind")
	check_eq(hurtbox.receive_hit(CombatFixtures.make_hit(_attacker(Vector3(3, 0, -1.5)), 5.0)), R.BLOCKED,
			"a hit from 63° off the facing, inside the 150° arc")
	check_eq(hurtbox.receive_hit(CombatFixtures.make_hit(_attacker(Vector3(3, 0, 0)), 5.0)), R.HIT,
			"a hit from 90° off the facing, outside the arc")
	var unblockable := CombatFixtures.make_hit(_attacker(Vector3(0, 0, -3)), 5.0)
	unblockable.unblockable = true
	check_eq(hurtbox.receive_hit(unblockable), R.HIT, "an unblockable frontal hit")
	guard.set_guarding(false)
	check_eq(hurtbox.receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -3)), 5.0)), R.HIT, "a frontal hit with the guard down")
	check_eq(_health(fighter).current_health, 80.0, "health after the four hits that got through")


func test_guard_breaks_when_posture_fills() -> void:
	var fighter := _fighter(func(node: Node) -> void:
		if node is PostureComponent:
			node.max_posture = 30.0)
	var guard := _guard(fighter)
	var broke := [0]
	guard.guard_broken.connect(func() -> void: broke[0] += 1)
	guard.set_guarding(true)
	check_eq(_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 20.0, 40.0)), R.GUARD_BROKEN,
			"a block that fills posture")
	check(not guard.is_guarding, "the guard dropped")
	check_eq(broke[0], 1, "guard_broken count")
	check_eq(_health(fighter).current_health, 100.0, "a guard break still costs no health")
	check_eq(_reaction(fighter).stagger_type, &"guard_break", "the reaction")
	check_near(_reaction(fighter)._time_left, guard.guard_break_stagger, 0.05, "guard-break stagger time")


func test_chip_damage_hurts_but_never_kills() -> void:
	var fighter := _fighter(func(node: Node) -> void:
		if node is HealthComponent:
			node.max_health = 10.0
		elif node is GuardComponent:
			node.chip_damage = 0.5)
	var damaged := [0]
	_health(fighter).damaged.connect(func(_hit: HitInfo) -> void: damaged[0] += 1)
	_guard(fighter).set_guarding(true)
	var front := _attacker(Vector3(0, 0, -2))
	check_eq(_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(front, 8.0, 0.0)), R.BLOCKED, "first chipped block")
	check_eq(_health(fighter).current_health, 6.0, "half of 8 chipped off")
	_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(front, 100.0, 0.0))
	check_eq(_health(fighter).current_health, 1.0, "chip damage stops at 1")
	check(not _health(fighter).is_dead, "chip damage never kills")
	check_eq(damaged[0], 0, "chip damage doesn't emit damaged")


# --- Parry -------------------------------------------------------------------------------------

func test_parry_in_the_window_reflects_posture_and_staggers_the_attacker() -> void:
	var defender := _fighter()
	var attacker := _fighter()
	attacker.position = Vector3(0, 0, -2)
	await physics_frames(1)
	_guard(defender).set_guarding(true)               # registered first, yet parry must win
	var parried := []
	_parry(defender).parry_successful.connect(func(who: Node3D, _point: Vector3) -> void: parried.append(who))
	check(_parry(defender).on_guard_pressed(), "a fresh press opens a window")
	check_eq(_hurtbox(defender).receive_hit(CombatFixtures.make_hit(attacker, 20.0, 10.0)), R.PARRIED, "a hit inside the window")
	check_eq(_health(defender).current_health, 100.0, "a parry costs no health")
	check_eq(_posture(defender).current, 0.0, "a parry costs the defender no posture")
	check_eq(_posture(attacker).current, 30.0, "the attacker takes 3x the poise damage")
	check_eq(_reaction(attacker).stagger_type, &"parried", "the attacker's reaction")
	check(parried.size() == 1 and parried[0] == attacker, "parry_successful names the attacker")
	check(not _parry(defender).is_window_open(), "one parry per press")


func test_after_the_window_the_guard_takes_over() -> void:
	var fighter := _fighter()
	_guard(fighter).set_guarding(true)
	_parry(fighter).on_guard_pressed()
	await seconds(0.2)                                # parry_window is 0.15 s
	check_eq(_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)))), R.BLOCKED, "a late hit")


func test_unparryable_hits_fall_to_the_guard_and_unblockable_ones_land() -> void:
	var fighter := _fighter()
	var front := _attacker(Vector3(0, 0, -2))
	_guard(fighter).set_guarding(true)
	_parry(fighter).on_guard_pressed()
	var unparryable := CombatFixtures.make_hit(front)
	unparryable.can_be_parried = false
	check_eq(_hurtbox(fighter).receive_hit(unparryable), R.BLOCKED, "can_be_parried = false inside the window")
	check(_parry(fighter).is_window_open(), "an unparryable hit doesn't use up the window")
	var unblockable := CombatFixtures.make_hit(front)
	unblockable.unblockable = true
	check_eq(_hurtbox(fighter).receive_hit(unblockable), R.HIT, "unblockable inside the window")
	check_eq(_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, 3)))), R.HIT,
			"a hit from behind inside the window")


func test_spamming_guard_locks_the_parry_out() -> void:
	var fighter := _fighter()
	var parry := _parry(fighter)
	check(parry.on_guard_pressed(), "first press opens a window")
	check(not parry.on_guard_pressed(), "an immediate second press doesn't")
	await seconds(0.3)
	check(not parry.on_guard_pressed(), "still locked out 0.3 s later (window 0.15 + lockout 0.4)")
	check(not parry.is_window_open(), "a locked-out press opens nothing")
	await seconds(0.35)
	check(parry.on_guard_pressed(), "a press after the lockout opens a window")
	_hurtbox(fighter).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2))))
	check(parry.on_guard_pressed(), "a successful parry lifts the lockout")


# --- Damage reactions --------------------------------------------------------------------------

func test_direction_is_classified_over_eight_angles() -> void:
	# Rotating -Z by +90° around UP points at -X, the left of a -Z-facing body.
	var expected := {0.0: &"front", 30.0: &"front", 90.0: &"left", 150.0: &"back",
			180.0: &"back", 210.0: &"back", 270.0: &"right", 330.0: &"front"}
	for degrees: float in expected:
		var to_attacker := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(degrees)) * 3.0
		check_eq(DamageReactionComponent.direction_of(Vector3.FORWARD, to_attacker), expected[degrees], "attack from %d°" % degrees)
	# Facing +X instead: an attacker at +X is in front, one at +Z is on the right.
	check_eq(DamageReactionComponent.direction_of(Vector3.RIGHT, Vector3(4, 0, 0.5)), &"front", "facing +X, attacker at +X")
	check_eq(DamageReactionComponent.direction_of(Vector3.RIGHT, Vector3(0, 0, 4)), &"right", "facing +X, attacker at +Z")


func test_reaction_tiers_follow_poise_damage_and_posture() -> void:
	var fighter := _fighter(func(node: Node) -> void:
		if node is PostureComponent:
			node.max_posture = 1000.0)
	var reaction := _reaction(fighter)
	var hurtbox := _hurtbox(fighter)
	var behind := _attacker(Vector3(0, 0, 3))
	hurtbox.receive_hit(CombatFixtures.make_hit(behind, 1.0, 10.0))
	check_eq(reaction.stagger_type, &"back", "light poise from behind")
	check_near(reaction._time_left, reaction.flinch_time, 0.05, "a light flinch lasts at least flinch_time")
	hurtbox.receive_hit(CombatFixtures.make_hit(behind, 1.0, 35.0))
	check_eq(reaction.stagger_type, &"heavy", "poise at or past poise_threshold (30)")
	hurtbox.receive_hit(CombatFixtures.make_hit(behind, 1.0, 70.0))
	check_eq(reaction.stagger_type, &"knockdown", "poise at or past knockdown_threshold (60)")

	var fragile := _fighter(func(node: Node) -> void:
		if node is PostureComponent:
			node.max_posture = 20.0)
	_hurtbox(fragile).receive_hit(CombatFixtures.make_hit(behind, 1.0, 25.0))
	check_eq(_reaction(fragile).stagger_type, &"knockdown", "a light hit that breaks posture knocks down")


func test_stagger_ends_and_knockback_decays_with_friction() -> void:
	var fighter := _fighter()
	var reaction := _reaction(fighter)
	var ended := [0]
	reaction.stagger_ended.connect(func() -> void: ended[0] += 1)
	var hit := CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 1.0, 5.0)
	hit.knockback = Vector3(0, 0, 6)
	hit.stagger_time = 0.2
	_hurtbox(fighter).receive_hit(hit)
	check_eq(fighter.velocity, Vector3(0, 0, 6), "knockback sets the body's velocity")
	check(reaction.is_staggered, "staggered")
	await physics_frames(3)
	check(fighter.velocity.z < 6.0 and fighter.velocity.z > 0.0, "friction brakes the knockback")
	check(await wait_until(func() -> bool: return not reaction.is_staggered, 1.0), "the stagger never ended")
	check_eq(ended[0], 1, "stagger_ended count")

	var blocked := CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 1.0, 5.0)
	blocked.knockback = Vector3(0, 0, 10)
	fighter.velocity = Vector3.ZERO
	_guard(fighter).set_guarding(true)
	_hurtbox(fighter).receive_hit(blocked)
	check_near(fighter.velocity.z, 10.0 * reaction.blocked_push, 0.001, "a block pushes by blocked_push")
	check(not reaction.is_staggered, "and doesn't stagger")


# --- Player and wolf wiring --------------------------------------------------------------------

func test_player_guard_blocks_and_each_press_opens_a_parry_window() -> void:
	var player := await _stage_player()
	var fsm := player.get_node("Combat") as CombatStateMachine
	fsm.guard_pressed()
	check_eq(fsm.state, CombatStateMachine.State.GUARD, "state after pressing guard")
	check(fsm.guard.is_guarding, "the guard is up")
	check(fsm.parry.is_window_open(), "the press opened a parry window")
	check(player.move_speed_scale < 1.0 and player.hold_facing, "guarding walks slowly and holds the facing")
	await seconds(0.2)
	var health := player.get_node("HealthComponent") as HealthComponent
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 15.0, 10.0)), R.BLOCKED,
			"a frontal hit after the window")
	check_eq(health.current_health, health.max_health, "blocked: no health lost")
	fsm.guard_released()
	await physics_frames(2)
	check_eq(fsm.state, CombatStateMachine.State.IDLE, "state after releasing guard")
	check(not fsm.guard.is_guarding and player.move_speed_scale == 1.0 and not player.hold_facing, "guard fully lowered")


func test_player_parries_a_wolf_bite_and_the_wolf_staggers() -> void:
	var player := await _stage_player()
	var fsm := player.get_node("Combat") as CombatStateMachine
	var wolf := CombatFixtures.make_idle_wolf()
	wolf.position = Vector3(0, 0, -1.6)
	add_to_stage(wolf)
	await physics_frames(2)
	fsm.guard_pressed()
	var bite := CombatFixtures.make_hit(wolf, wolf.bite.damage, wolf.bite.poise_damage)
	check_eq(_hurtbox(player).receive_hit(bite), R.PARRIED, "a bite inside the parry window")
	check_eq(wolf.posture.current, wolf.bite.poise_damage * 3.0, "the wolf's posture took the reflected poise")
	check_eq(wolf.state, Wolf.State.STAGGER, "the parried wolf staggers")
	await physics_frames(2)
	check_eq(fsm._playback.get_current_node(), &"parry_1", "the player plays the parry clip")


func test_player_flinches_by_direction_and_weight() -> void:
	var player := await _stage_player()
	var fsm := player.get_node("Combat") as CombatStateMachine
	_hurtbox(player).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, 3)), 5.0, 5.0))
	check_eq(fsm.state, CombatStateMachine.State.HURT, "state after a hit")
	await physics_frames(2)
	check_eq(fsm._playback.get_current_node(), &"hurt_b", "a light hit from behind")
	check(await wait_until(func() -> bool: return fsm.state == CombatStateMachine.State.IDLE, 1.5), "the flinch never ended")
	await seconds(0.6)                                # past the 0.8 s post-hit invulnerability
	_hurtbox(player).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -3)), 5.0, 40.0))
	await physics_frames(2)
	check_eq(fsm._playback.get_current_node(), &"hurt_heavy", "a heavy hit from the front")


func test_a_broken_guard_staggers_the_player() -> void:
	var player := await _stage_player()
	var fsm := player.get_node("Combat") as CombatStateMachine
	fsm.posture.add_posture(95.0)
	fsm.guard_pressed()
	await seconds(0.2)                                # past the parry window
	check_eq(_hurtbox(player).receive_hit(CombatFixtures.make_hit(_attacker(Vector3(0, 0, -2)), 10.0, 10.0)), R.GUARD_BROKEN,
			"a block that fills posture")
	check_eq(fsm.state, CombatStateMachine.State.HURT, "state after a guard break")
	check(not fsm.guard.is_guarding, "the guard is down")
	await physics_frames(2)
	check_eq(fsm._playback.get_current_node(), &"guard_break", "the guard-break clip")


func test_guard_interrupts_recovery_and_strikes_leave_the_guard() -> void:
	var player := await _stage_player()
	var fsm := player.get_node("Combat") as CombatStateMachine
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool:
		return fsm.state == CombatStateMachine.State.ATTACK and fsm._state_time >= fsm.current_attack.active_end, 1.5),
		"never reached the strike's recovery")
	fsm.guard_pressed()
	check_eq(fsm.state, CombatStateMachine.State.GUARD, "guard cancels a strike's recovery")
	fsm.combo.push_input(ComboManager.LIGHT)
	await physics_frames(2)
	check_eq(fsm.state, CombatStateMachine.State.ATTACK, "a strike from the guard")
	check(not fsm.guard.is_guarding, "striking lowers the guard")


func test_guard_pressed_during_a_wind_up_opens_no_window() -> void:
	var player := await _stage_player()
	var fsm := player.get_node("Combat") as CombatStateMachine
	fsm.combo.push_input(ComboManager.LIGHT)
	check(await wait_until(func() -> bool: return fsm.state == CombatStateMachine.State.ATTACK, 1.0), "the strike never started")
	fsm.guard_pressed()
	check_eq(fsm.state, CombatStateMachine.State.ATTACK, "the wind-up commits")
	check(not fsm.parry.is_window_open(), "no parry window from inside a wind-up")
	check(await wait_until(func() -> bool: return fsm.state == CombatStateMachine.State.GUARD, 1.5),
			"a held guard goes up once the strike allows it")


# --- Helpers -----------------------------------------------------------------------------------

func _fighter(tune := Callable()) -> CharacterBody3D:
	return add_to_stage(CombatFixtures.make_fighter(tune))


func _attacker(at: Vector3) -> Node3D:
	var attacker := Node3D.new()
	attacker.position = at
	return add_to_stage(attacker)


## Floor plus a player at the origin facing -Z.
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


func _health(body: Node) -> HealthComponent:
	return body.get_node("HealthComponent")


func _posture(body: Node) -> PostureComponent:
	return body.get_node("PostureComponent")


func _hurtbox(body: Node) -> Hurtbox:
	return body.get_node("Hurtbox")


func _guard(body: Node) -> GuardComponent:
	return body.get_node("GuardComponent")


func _parry(body: Node) -> ParrySystem:
	return body.get_node("ParrySystem")


func _reaction(body: Node) -> DamageReactionComponent:
	return body.get_node("DamageReaction")
