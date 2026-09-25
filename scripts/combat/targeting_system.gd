class_name TargetingSystem
extends Node
## Hard lock-on.
##
## lock_on (MMB / Q / right-stick click / LOCK) toggles. Locking picks the enemy (group
## "enemies") closest to the centre of view, within `radius` and a `cone_degrees` cone around
## the camera's forward direction, with a clear line of sight (world layer). While locked:
## • target_next / target_prev (mouse wheel, NEXT button) or a right-stick flick switch to the
##   nearest visible enemy to the right or left of the current one on screen;
## • if the target dies (leaves the group), is freed or gets farther than `break_distance`, the
##   lock moves to the next best enemy, or releases when there is none;
## • losing sight of the target for `lost_sight_time` seconds releases the lock.
## A small reticle floats over the locked target. The camera, dodges and lunges read
## `current_target`.

signal target_changed(target: Node3D)

@export var body: PlayerController
@export var camera: CombatCamera
## Farthest an enemy can be to get locked (m).
@export var radius := 18.0
## Full angle of the lock-on cone around the camera's forward direction.
@export_range(1.0, 360.0) var cone_degrees := 70.0
## A lock releases (or moves on) past this distance (m).
@export var break_distance := 24.0
## Seconds without line of sight before the lock releases.
@export var lost_sight_time := 1.5
## Physics layers that block line of sight (1 = world).
@export_flags_3d_physics var sight_mask := 1
## Height above a target's origin for the reticle and sight checks (m).
@export var aim_height := 0.7
## Right-stick flick: past `x` it switches target; it must fall back under `y` before the next.
@export var flick_thresholds := Vector2(0.7, 0.3)

var current_target: Node3D
var _unseen_time := 0.0
var _flick_ready := true
var _reticle: Label3D


func _ready() -> void:
	_reticle = Label3D.new()
	_reticle.name = "Reticle"
	_reticle.text = "◆"
	_reticle.font_size = 48
	_reticle.pixel_size = 0.004
	_reticle.modulate = Color(1.0, 0.85, 0.55, 0.95)
	_reticle.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	_reticle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_reticle.no_depth_test = true
	_reticle.fixed_size = true
	_reticle.top_level = true
	_reticle.visible = false
	add_child(_reticle)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"lock_on"):
		toggle_lock()
	elif event.is_action_pressed(&"target_next"):
		cycle(1)
	elif event.is_action_pressed(&"target_prev"):
		cycle(-1)


func is_locked() -> bool:
	return is_instance_valid(current_target)


func toggle_lock() -> void:
	if is_locked():
		set_target(null)
	else:
		set_target(find_best_target())


func set_target(target: Node3D) -> void:
	if target == current_target:
		return
	current_target = target
	_unseen_time = 0.0
	target_changed.emit(target)


## The enemy nearest the centre of view inside the cone, within reach and in sight, or null.
func find_best_target(exclude: Node3D = null) -> Node3D:
	var forward := _view_forward()
	var min_dot := cos(deg_to_rad(cone_degrees * 0.5))
	var best: Node3D
	var best_score := INF
	for enemy in _candidates(exclude):
		var to_enemy := _flat(enemy.global_position - body.global_position)
		var distance := to_enemy.length()
		var dot := forward.dot(to_enemy / distance) if distance > 0.01 else 1.0
		if dot < min_dot:
			continue
		var score := acos(clampf(dot, -1.0, 1.0)) + distance * 0.02   # angle first, distance breaks ties
		if score < best_score:
			best = enemy
			best_score = score
	return best


## Switch to the nearest visible enemy to the right (direction > 0) or left of the current one,
## by screen position. Does nothing when unlocked or when there is nobody on that side.
func cycle(direction: int) -> void:
	if not is_locked():
		return
	var view := camera.camera
	var current_x := view.unproject_position(_aim_point(current_target)).x
	var best: Node3D
	var best_gap := INF
	for enemy in _candidates(current_target):
		var point := _aim_point(enemy)
		if view.is_position_behind(point):
			continue
		var gap := (view.unproject_position(point).x - current_x) * signf(direction)
		if gap > 0.0 and gap < best_gap:
			best = enemy
			best_gap = gap
	if best:
		set_target(best)


func _process(_delta: float) -> void:
	if is_locked():
		_poll_stick_flick()
	_update_reticle()


func _physics_process(delta: float) -> void:
	if current_target == null:
		return
	if not _still_valid(current_target):
		set_target(find_best_target(current_target))
		return
	if _in_sight(current_target):
		_unseen_time = 0.0
	else:
		_unseen_time += delta
		if _unseen_time >= lost_sight_time:
			set_target(null)


func _poll_stick_flick() -> void:
	if not InputMap.has_action(&"look_left"):
		return
	var x := Input.get_axis(&"look_left", &"look_right")
	if _flick_ready and absf(x) > flick_thresholds.x:
		_flick_ready = false
		cycle(int(signf(x)))
	elif absf(x) < flick_thresholds.y:
		_flick_ready = true


func _update_reticle() -> void:
	_reticle.visible = is_locked()
	if _reticle.visible:
		_reticle.global_position = _aim_point(current_target) + Vector3.UP * 0.45


## Live enemies within `radius` and in sight.
func _candidates(exclude: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in body.get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy == exclude or not is_instance_valid(enemy):
			continue
		if _flat(enemy.global_position - body.global_position).length() > radius:
			continue
		if _in_sight(enemy):
			found.append(enemy)
	return found


func _still_valid(target: Node3D) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and target.is_in_group(&"enemies") \
			and _flat(target.global_position - body.global_position).length() <= break_distance


func _in_sight(target: Node3D) -> bool:
	var from := body.global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, _aim_point(target), sight_mask, [body.get_rid()])
	return body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _aim_point(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * aim_height


func _view_forward() -> Vector3:
	var forward := _flat(-camera.global_basis.z) if camera else Vector3.ZERO
	if forward.length_squared() < 0.0001:
		forward = body.get_facing()
	return forward.normalized()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
