class_name GuardComponent
extends Node
## Guard: a Hurtbox defender that blocks frontal hits while the guard is up.
##
## A blocked hit deals no health damage (except the optional `chip_damage` share, which never
## kills), and its poise damage goes to posture instead. If that breaks the posture, the guard
## breaks: intercept() returns GUARD_BROKEN, the guard drops and guard_broken fires
## (DamageReactionComponent plays the `guard_break_stagger`). Unblockable hits, hits from
## outside the frontal `guard_arc_degrees`, and any hit while the guard is down pass through.

signal guard_started
signal guard_ended
signal guard_broken
## A hit was blocked (and the guard held).
signal blocked(hit: HitInfo)

## The Hurtbox this guard defends; it registers itself there.
@export var hurtbox: Hurtbox
## Takes blocked hits' poise damage. Without one, the guard never breaks.
@export var posture: PostureComponent
## Whose facing defines the frontal arc: get_facing() if it has one, else its -Z axis.
@export var body: Node3D
## Full angle of the protected arc, centred on the facing.
@export_range(0.0, 360.0) var guard_arc_degrees := 150.0
## Seconds of stagger after a guard break.
@export var guard_break_stagger := 2.5
## Share of a blocked hit's damage that still reaches health (0 = none). Never lethal.
@export_range(0.0, 1.0) var chip_damage := 0.0

var is_guarding := false


func _ready() -> void:
	if hurtbox:
		hurtbox.add_defender(self)


func _exit_tree() -> void:
	if hurtbox:
		hurtbox.remove_defender(self)


func set_guarding(on: bool) -> void:
	if on == is_guarding:
		return
	is_guarding = on
	if on:
		guard_started.emit()
	else:
		guard_ended.emit()


func intercept(hit: HitInfo) -> HitInfo.Result:
	if not is_guarding or hit.unblockable or not covers(hit):
		return HitInfo.Result.IGNORED
	if chip_damage > 0.0 and hurtbox and hurtbox.health:
		hurtbox.health.chip(hit.damage * chip_damage)
	if posture and posture.add_posture(hit.poise_damage):
		set_guarding(false)
		guard_broken.emit()
		return HitInfo.Result.GUARD_BROKEN
	blocked.emit(hit)
	return HitInfo.Result.BLOCKED


## True if the hit comes from inside the frontal arc. A hit with no known origin counts as
## frontal.
func covers(hit: HitInfo) -> bool:
	if body == null:
		return true
	var origin := hit.hit_position
	if is_instance_valid(hit.source):
		origin = hit.source.global_position
	var to_attacker := origin - body.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return true
	var facing := facing_of(body)
	return facing.angle_to(to_attacker.normalized()) <= deg_to_rad(guard_arc_degrees) * 0.5


## Flat forward vector of `node`: its get_facing() if it has one (PlayerController turns only
## its model), else its -Z axis.
static func facing_of(node: Node3D) -> Vector3:
	var forward: Vector3 = node.call(&"get_facing") if node.has_method(&"get_facing") else -node.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
