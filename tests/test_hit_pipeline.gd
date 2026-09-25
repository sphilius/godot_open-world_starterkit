extends TestCase
## Hit pipeline (M1): HealthComponent invulnerability, Hurtbox defenders and posture, and the
## Hitbox routing hits through the target's Hurtbox.

const Result := HitInfo.Result


func test_grant_invulnerability_blocks_then_expires() -> void:
	var health: HealthComponent = add_to_stage(HealthComponent.new())
	health.grant_invulnerability(0.1)
	expect(health.is_invulnerable())
	expect(not health.take_damage(HitInfo.new(10.0)), "refused while invulnerable")
	await await_seconds(0.2)
	expect(not health.is_invulnerable(), "expired")
	expect(health.take_damage(HitInfo.new(10.0)), "applies after expiry")
	expect_eq(health.current_health, 90.0)


func test_a_shorter_grant_never_cuts_a_longer_one() -> void:
	var health: HealthComponent = add_to_stage(HealthComponent.new())
	health.grant_invulnerability(0.5)
	health.grant_invulnerability(0.05)
	await await_seconds(0.15)
	expect(health.is_invulnerable(), "the 0.5 s window still holds")


func test_a_claiming_defender_stops_health_damage() -> void:
	var hurtbox := CombatFixtures.make_target(self)
	var defender := CombatFixtures.StubDefender.new(Result.BLOCKED)
	hurtbox.add_defender(defender)
	var received := []
	hurtbox.hit_received.connect(func(_hit: HitInfo, result: Result) -> void: received.append(result))
	expect_eq(hurtbox.receive_hit(HitInfo.new(30.0)), Result.BLOCKED)
	expect_eq(hurtbox.health.current_health, 100.0, "no health damage")
	expect_eq(received, [Result.BLOCKED], "hit_received reports the defender's result")


func test_defenders_run_in_order_and_ignored_passes_through() -> void:
	var hurtbox := CombatFixtures.make_target(self)
	var first := CombatFixtures.StubDefender.new(Result.IGNORED)
	var second := CombatFixtures.StubDefender.new(Result.PARRIED)
	hurtbox.add_defender(first)
	hurtbox.add_defender(second)
	hurtbox.add_defender(first)               # duplicates are ignored
	expect_eq(hurtbox.receive_hit(HitInfo.new(30.0)), Result.PARRIED)
	expect_eq([first.calls, second.calls], [1, 1])
	hurtbox.remove_defender(second)
	expect_eq(hurtbox.receive_hit(HitInfo.new(30.0)), Result.HIT, "passes through to health")
	expect_eq(hurtbox.health.current_health, 70.0)


func test_invulnerability_is_checked_before_defenders() -> void:
	var hurtbox := CombatFixtures.make_target(self)
	var defender := CombatFixtures.StubDefender.new(Result.IGNORED)
	hurtbox.add_defender(defender)
	hurtbox.health.grant_invulnerability(1.0)
	expect_eq(hurtbox.receive_hit(HitInfo.new(30.0)), Result.IGNORED)
	expect_eq(defender.calls, 0, "defenders never see a hit on an invulnerable target")


func test_lethal_hit_returns_killed_and_dead_targets_ignore_hits() -> void:
	var hurtbox := CombatFixtures.make_target(self, 20.0)
	expect_eq(hurtbox.receive_hit(HitInfo.new(25.0)), Result.KILLED)
	expect(hurtbox.health.is_dead)
	expect_eq(hurtbox.receive_hit(HitInfo.new(25.0)), Result.IGNORED)


func test_posture_takes_poise_damage_only_from_landed_non_lethal_hits() -> void:
	var hurtbox := CombatFixtures.make_target(self, 50.0)
	var posture := CombatFixtures.StubPosture.new()
	add_child(posture)
	hurtbox.posture = posture
	var hit := HitInfo.new(10.0)
	hit.poise_damage = 15.0
	hurtbox.receive_hit(hit)
	expect_eq(posture.total, 15.0, "a landed hit adds its poise damage")

	var defender := CombatFixtures.StubDefender.new(Result.BLOCKED)
	hurtbox.add_defender(defender)
	hurtbox.receive_hit(hit)
	expect_eq(posture.total, 15.0, "a claimed hit leaves posture to the defender")


func test_hitbox_routes_hits_through_the_target_hurtbox_defenders() -> void:
	var wolf := add_to_stage(CombatFixtures.make_idle_wolf()) as Wolf
	wolf.hurtbox.add_defender(CombatFixtures.StubDefender.new(Result.BLOCKED))
	var hitbox: Hitbox = add_to_stage(CombatFixtures.make_hitbox())
	var landed := [0]
	hitbox.hit_landed.connect(func(_target: HealthComponent, _hit: HitInfo) -> void: landed[0] += 1)
	# The box overlaps the body too: a body contact must not bypass the hurtbox's guard.
	hitbox.begin(CombatFixtures.make_attack(10.0, 0.2))
	hitbox.set_active(true)
	await await_physics(4)
	expect_eq(wolf.health.current_health, wolf.health.max_health, "blocked: no damage")
	expect_eq(landed[0], 0, "a blocked hit doesn't count as landed")
	expect_eq(Engine.time_scale, 1.0, "no hit-stop for a blocked hit")


func test_hitbox_fills_attack_and_contact_point() -> void:
	var wolf := add_to_stage(CombatFixtures.make_idle_wolf()) as Wolf
	var hitbox: Hitbox = add_to_stage(CombatFixtures.make_hitbox())
	hitbox.global_position = Vector3(0, 0.5, 0.8)
	var attack := CombatFixtures.make_attack(10.0)
	var hits: Array[HitInfo] = []
	hitbox.hit_landed.connect(func(_target: HealthComponent, hit: HitInfo) -> void: hits.append(hit))
	hitbox.begin(attack)
	hitbox.set_active(true)
	await await_physics(4)
	if expect_eq(hits.size(), 1, "one landed hit"):
		expect(hits[0].attack == attack, "HitInfo.attack is the strike")
		var contact := hits[0].hit_position
		expect(contact.z > 0.0 and contact.z < 0.8, "contact %s lies between the wolf and the hitbox" % contact)
	await await_seconds(0.15)                  # let the wolf's hit flash finish before teardown
