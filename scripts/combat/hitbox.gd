class_name Hitbox
extends Area3D
## Damage dealer shared by the katana and the wolf's bite.
##
## The owner arms it with an AttackData (begin) and opens or closes the active window
## (set_active). While active, `area_entered` (Hurtboxes) and `body_entered` (bodies) resolve
## the target's HealthComponent. Each target is hit at most once per activation, even when its
## hurtbox and body both overlap.
## The hit goes through the target's Hurtbox (receive_hit), so its defenders (guard, parry)
## can claim it. That happens even when the body is touched first. Only targets without a
## Hurtbox take the damage directly. A landed hit applies damage, knockback and stagger, and
## triggers hit-stop.

signal hit_landed(target: HealthComponent, hit: HitInfo)

## The attacker: knockback pushes away from it, and it never hits itself.
var source: Node3D
var _attack: AttackData
var _active := false
var _hit_this_swing := {}   # HealthComponent -> true


func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_struck)
	body_entered.connect(_on_struck)


## Arms the hitbox for a new strike (clears the one-hit-per-target memory).
func begin(attack: AttackData) -> void:
	_attack = attack
	_hit_this_swing.clear()


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_deferred(&"monitoring", on)   # overlaps already present report on the next physics step


func is_active() -> bool:
	return _active


func _on_struck(node: Node3D) -> void:
	if not _active or _attack == null:
		return
	var health := HealthComponent.resolve(node)
	if health == null or health.is_dead or _hit_this_swing.has(health):
		return
	if source and health.get_parent() == source:
		return
	_hit_this_swing[health] = true

	var hit := HitInfo.new(_attack.damage, source, _knockback_direction(node) * _attack.knockback, _attack.stagger_time)
	hit.attack = _attack
	hit.poise_damage = _attack.poise_damage
	hit.damage_type = _attack.damage_type
	hit.unblockable = _attack.unblockable
	hit.can_be_parried = _attack.can_be_parried
	hit.hit_position = _contact_point(node)

	var hurtbox := node as Hurtbox
	if hurtbox == null:
		hurtbox = Hurtbox.find_for(node, health)
	var landed: bool
	if hurtbox:
		landed = HitInfo.is_landed(hurtbox.receive_hit(hit))
	else:
		landed = health.take_damage(hit)
	if landed:
		HitStop.trigger(_attack.hitstop)
		hit_landed.emit(health, hit)


## Away from the attacker, or AttackData.knockback_direction_override turned into world space
## by the attacker's facing. Horizontal, unit length (zero without a source).
func _knockback_direction(target: Node3D) -> Vector3:
	if source == null:
		return Vector3.ZERO
	var push := target.global_position - source.global_position
	if _attack.knockback_direction_override != Vector3.ZERO:
		push = _attacker_basis() * _attack.knockback_direction_override
	push.y = 0.0
	return push.normalized()


## The attacker's facing as a basis. PlayerController never rotates its body (only its model
## turns), so a source that reports get_facing() is trusted over its node rotation.
func _attacker_basis() -> Basis:
	if source.has_method(&"get_facing"):
		var forward: Vector3 = source.call(&"get_facing")
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			return Basis.looking_at(forward.normalized(), Vector3.UP)
	return source.global_basis


## Approximate contact point: midway between this hitbox's shape and the target's first shape
## (or the target's origin when it has no shape child).
func _contact_point(target: Node3D) -> Vector3:
	return _shape_center(self).lerp(_shape_center(target), 0.5)


static func _shape_center(node: Node3D) -> Vector3:
	for child in node.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).global_position
	return node.global_position
