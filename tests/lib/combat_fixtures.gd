class_name CombatFixtures
extends RefCounted
## Builders shared by the combat tests.

const WOLF_SCENE := preload("res://scenes/mobs/wolf.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Layers as in project.godot: player_hitbox (4) scanning mobs (3) and mob_hurtbox (5).
const PLAYER_HITBOX_LAYER := 1 << 3
const PLAYER_HITBOX_MASK := (1 << 2) | (1 << 4)


## A player-side Hitbox with a box shape of `size`, like the katana's.
static func make_hitbox(size := Vector3(2, 2, 2)) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.collision_layer = PLAYER_HITBOX_LAYER
	hitbox.collision_mask = PLAYER_HITBOX_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	hitbox.add_child(shape)
	return hitbox


static func make_attack(damage := 10.0, hitstop := 0.0) -> AttackData:
	var attack := AttackData.new()
	attack.damage = damage
	attack.hitstop = hitstop
	attack.stagger_time = 0.1
	attack.knockback = 0.0
	return attack


## A wolf whose AI is off, so it stands still as a target.
static func make_idle_wolf() -> Wolf:
	var wolf: Wolf = WOLF_SCENE.instantiate()
	wolf.set_physics_process(false)
	return wolf


## A HealthComponent plus a Hurtbox guarding it, both parented to `owner`.
static func make_target(owner: Node, max_health := 100.0) -> Hurtbox:
	var health := HealthComponent.new()
	health.max_health = max_health
	owner.add_child(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	owner.add_child(hurtbox)
	return hurtbox


## A bare CharacterBody3D fighter with the whole M5 defense kit, facing -Z: HealthComponent,
## PostureComponent, a Hurtbox defended by ParrySystem then GuardComponent (added in the
## opposite order, so ParrySystem must put itself first), and a DamageReactionComponent.
## `tune` is called with each component before the fighter enters the tree, to set exports.
static func make_fighter(tune := Callable()) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var health := HealthComponent.new()
	var posture := PostureComponent.new()
	var hurtbox := Hurtbox.new()
	var guard := GuardComponent.new()
	var parry := ParrySystem.new()
	var reaction := DamageReactionComponent.new()
	health.name = "HealthComponent"
	posture.name = "PostureComponent"
	hurtbox.name = "Hurtbox"
	guard.name = "GuardComponent"
	parry.name = "ParrySystem"
	reaction.name = "DamageReaction"
	posture.health = health
	posture.guard = guard
	posture.body = body
	hurtbox.health = health
	hurtbox.posture = posture
	guard.hurtbox = hurtbox
	guard.posture = posture
	guard.body = body
	parry.hurtbox = hurtbox
	parry.guard = guard
	reaction.body = body
	reaction.hurtbox = hurtbox
	reaction.posture = posture
	reaction.guard = guard
	for node: Node in [health, posture, hurtbox, guard, parry, reaction]:
		if tune.is_valid():
			tune.call(node)
		body.add_child(node)
	return body


## A hit from `source` (or from nowhere) with the given damage and poise damage.
static func make_hit(source: Node3D, damage := 10.0, poise := 10.0) -> HitInfo:
	var hit := HitInfo.new(damage, source)
	hit.poise_damage = poise
	return hit


## Defender stub: claims every hit with `result` (IGNORED passes it through) and counts calls.
class StubDefender:
	extends RefCounted
	var result := HitInfo.Result.BLOCKED
	var calls := 0

	func _init(p_result := HitInfo.Result.BLOCKED) -> void:
		result = p_result

	func intercept(_hit: HitInfo) -> HitInfo.Result:
		calls += 1
		return result


## PostureComponent stub: sums the posture damage it receives.
class StubPosture:
	extends Node
	var total := 0.0

	func add_posture(amount: float) -> bool:
		total += amount
		return false
