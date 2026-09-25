class_name HitInfo
extends RefCounted
## Damage payload passed from a hitbox to a Hurtbox (or straight to a HealthComponent).

## What happened to a hit. Hurtbox.receive_hit() returns it; defenders (guard, parry) return
## IGNORED to let the hit through to the next defender and then to health.
enum Result {
	## Not applied: the target is dead or invulnerable, or no defender or health took it.
	IGNORED,
	## Health damage applied.
	HIT,
	## A guard absorbed the health damage.
	BLOCKED,
	## A parry deflected it.
	PARRIED,
	## A guard took it, and its posture broke.
	GUARD_BROKEN,
	## Health damage applied, and it was lethal.
	KILLED,
}

var damage: float
## The attacker (used for aggro, knockback direction and parry recoil).
var source: Node3D
## Horizontal velocity to apply to the target (m/s).
var knockback: Vector3
var stagger_time: float
## Damage to posture (PostureComponent) rather than health.
var poise_damage := 0.0
## An AttackData.DamageType value (BLUNT, SLASH or PIERCE); SLASH by default.
var damage_type := 1
## World-space contact point, for sparks, sounds and directional reactions.
var hit_position := Vector3.ZERO
## Guards can't absorb it (red telegraph glint): it has to be dodged.
var unblockable := false
var can_be_parried := true
## The strike that produced this hit, if any.
var attack: AttackData


func _init(p_damage := 0.0, p_source: Node3D = null, p_knockback := Vector3.ZERO, p_stagger_time := 0.0) -> void:
	damage = p_damage
	source = p_source
	knockback = p_knockback
	stagger_time = p_stagger_time


## True when health damage was applied (HIT or KILLED).
static func is_landed(result: Result) -> bool:
	return result == Result.HIT or result == Result.KILLED
