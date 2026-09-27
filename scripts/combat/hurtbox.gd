class_name Hurtbox
extends Area3D
## Passive damage receiver (physics layer "hurtbox"). It never scans; hitboxes detect it
## through `area_entered` and deliver hits with receive_hit().
##
## An `evader` (CombatStateMachine, during a dodge's perfect window) gets the first look: if it
## evades the hit, nothing else happens, invulnerable or not. Then the hit runs through the
## defenders, in the order they were added (parry, then guard).
## The first defender that returns anything other than IGNORED decides the outcome. If no
## defender claims the hit, health takes the damage, and posture (optional) takes the poise
## damage.

signal hit_received(hit: HitInfo, result: HitInfo.Result)

@export var health: HealthComponent
## Optional. Receives the poise damage of hits that land: any node with
## add_posture(amount: float) -> bool (PostureComponent).
@export var posture: Node

## Optional: any object with evade(hit: HitInfo) -> bool, asked before anything else.
var evader: Object
var _defenders: Array[Object] = []


func _ready() -> void:
	monitoring = false


## Registers a defender: any object with intercept(hit: HitInfo) -> HitInfo.Result. `first`
## puts it ahead of the others (ParrySystem runs before GuardComponent).
func add_defender(defender: Object, first := false) -> void:
	if _defenders.has(defender):
		return
	if first:
		_defenders.push_front(defender)
	else:
		_defenders.append(defender)


func remove_defender(defender: Object) -> void:
	_defenders.erase(defender)


func receive_hit(hit: HitInfo) -> HitInfo.Result:
	if health == null or health.is_dead:
		return HitInfo.Result.IGNORED
	if evader and is_instance_valid(evader) and evader.call(&"evade", hit):
		return HitInfo.Result.IGNORED
	if health.is_invulnerable():
		return HitInfo.Result.IGNORED
	for defender in _defenders:
		var claimed: HitInfo.Result = defender.call(&"intercept", hit)
		if claimed != HitInfo.Result.IGNORED:
			hit_received.emit(hit, claimed)
			return claimed
	if not health.take_damage(hit):
		return HitInfo.Result.IGNORED
	var result := HitInfo.Result.KILLED if health.is_dead else HitInfo.Result.HIT
	if posture and result == HitInfo.Result.HIT and hit.poise_damage > 0.0:
		hit.broke_posture = bool(posture.call(&"add_posture", hit.poise_damage))
	hit_received.emit(hit, result)
	return result


## The Hurtbox that guards `target_health` among `node`'s direct children, or null. Lets a hitbox
## that touched a body route the hit through that body's defenders.
static func find_for(node: Node, target_health: HealthComponent) -> Hurtbox:
	for child in node.get_children():
		if child is Hurtbox and (child as Hurtbox).health == target_health:
			return child
	return null
