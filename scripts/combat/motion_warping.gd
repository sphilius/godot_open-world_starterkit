class_name MotionWarping
extends Node
## Steers and stretches each strike's lunge so it lands instead of whiffing.
##
## Target: the lock-on target when the player has one (TargetingSystem), otherwise the nearest
## enemy in front (soft lock) within reach and within `max_warp_angle` of the input direction.
## The lunge then points at the target and covers the gap down to `stop_distance`, clamped to
## `max_warp_distance`, and never pulls backwards. Without a target (or for strikes with
## AttackData.warp off), the strike keeps its own lunge along the input direction or facing.
##
## This only plans the motion. The body applies it as velocity through move_and_slide(), so
## collisions stay correct; nothing here tweens the position.

signal warp_started(target: Node3D)
signal warp_completed

@export var body: PlayerController
## Optional lock-on source: any node with a `current_target: Node3D` property (TargetingSystem).
@export var targeting: Node
## Farthest the body may travel in one warped lunge (m).
@export var max_warp_distance := 3.5
## Soft lock: widest angle between the input direction and an enemy that still gets warped to.
@export_range(0.0, 180.0) var max_warp_angle := 60.0
## Distance kept from the target's centre when the lunge ends (m).
@export var stop_distance := 1.2
## Fastest a warped lunge may move (m/s), so short strikes can't teleport.
@export var max_warp_speed := 14.0


## The motion for `attack`: {direction: Vector3, speed: float, duration: float, delay: float,
## target: Node3D (or null)}. speed is the lunge's average speed.
func plan(attack: AttackData) -> Dictionary:
	var direction := body.get_move_direction()
	if direction == Vector3.ZERO:
		direction = body.get_facing()
	var result := {direction = direction, speed = attack.lunge_speed, duration = attack.lunge_duration,
			delay = attack.lunge_delay, target = null}
	var target := find_target(direction)
	if target == null:
		return result
	var to_target := _flat(target.global_position - body.global_position)
	var distance := to_target.length()
	if distance > 0.01:
		result.direction = to_target / distance
	result.target = target
	if attack.warp and attack.lunge_duration > 0.0:
		result.speed = warp_speed(distance, attack.lunge_duration)
	return result


## Average lunge speed that closes `distance` down to stop_distance in `duration` seconds.
func warp_speed(distance: float, duration: float) -> float:
	var travel := clampf(distance - stop_distance, 0.0, max_warp_distance)
	return minf(travel / duration, max_warp_speed)


## The locked target if there is one, else the nearest enemy in front within reach.
func find_target(direction: Vector3) -> Node3D:
	var locked: Node3D = targeting.get(&"current_target") if targeting else null
	if is_instance_valid(locked):
		return locked
	var min_dot := cos(deg_to_rad(max_warp_angle))
	var reach := max_warp_distance + stop_distance
	var best: Node3D
	var best_distance := reach
	for enemy: Node3D in body.get_tree().get_nodes_in_group(&"enemies"):
		var to_enemy := _flat(enemy.global_position - body.global_position)
		var distance := to_enemy.length()
		if distance > 0.01 and distance < best_distance and direction.dot(to_enemy / distance) >= min_dot:
			best = enemy
			best_distance = distance
	return best


## Called by the combat state machine when a strike starts, so listeners (camera, VFX) hear it.
func notify_started(target: Node3D, total_time: float) -> void:
	if target == null:
		return
	warp_started.emit(target)
	# A connection rather than an await: it's dropped if this node is freed first.
	get_tree().create_timer(total_time, false, true).timeout.connect(_emit_completed)


func _emit_completed() -> void:
	warp_completed.emit()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
