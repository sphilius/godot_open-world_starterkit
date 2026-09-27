class_name CombatCamera
extends Node3D
## Third-person camera rig (the player's top-level CameraRig, with SpringArm3D → Camera3D).
##
## Free look : look input (mouse, touch, right stick) feeds yaw/pitch *targets*, eased with
##             frame-rate-independent exponential smoothing. The rig follows the physics-
##             *interpolated* body, so the view stays smooth at any refresh rate. The spring arm
##             (sphere shape) pulls the camera in when terrain or props get between it and the
##             player.
## Locked on : while the TargetingSystem holds a target, the rig turns to look past the player
##             at it, biases its anchor toward the target so both stay in frame, pitches down a
##             little, and lengthens the arm as the two spread apart. Look input is ignored.
##             Unlocking leaves the view where it is: no snap back.

## The body being followed (the player).
@export var follow: Node3D
@export var targeting: TargetingSystem

@export_group("Free Look")
## Exponential-decay rate for look smoothing (higher = snappier).
@export_range(1.0, 50.0) var look_smoothing := 16.0
## Exponential-decay rate for the rig chasing the body.
@export_range(1.0, 50.0) var follow_smoothing := 12.0
@export var height := 1.6
@export_range(-89.0, 0.0) var min_pitch_degrees := -65.0
@export_range(0.0, 89.0) var max_pitch_degrees := 30.0
@export var default_pitch_degrees := -6.0
@export var invert_y := false

@export_group("Lock-On")
## Exponential-decay rate for turning toward the target (lower = lazier, more cinematic).
@export_range(1.0, 50.0) var lock_turn_smoothing := 7.0
@export_range(-89.0, 0.0) var lock_pitch_degrees := -14.0
## Arm length at the near and far ends of `lock_separation`.
@export var lock_arm_length := Vector2(4.2, 6.0)
## Player-to-target distance (m) mapped onto `lock_arm_length`.
@export var lock_separation := Vector2(2.0, 12.0)
## How far the framing anchor slides from the player toward the target (0 = none, 0.5 = midpoint).
@export_range(0.0, 0.5) var lock_focus_bias := 0.3
## Exponential-decay rate for arm length changes.
@export_range(0.5, 20.0) var arm_smoothing := 4.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var yaw := 0.0
var pitch := 0.0
var target_yaw := 0.0
var target_pitch := 0.0
var _free_arm_length := 4.2


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved by hand in _process
	_free_arm_length = spring_arm.spring_length


## Rotate by a look delta in radians (x = yaw, y = pitch). Ignored while locked on.
func add_look_input(delta: Vector2) -> void:
	if is_locked():
		return
	target_yaw -= delta.x
	target_pitch -= delta.y * (-1.0 if invert_y else 1.0)
	target_pitch = clampf(target_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


## Jump straight to a view behind `feet`, looking along `p_yaw` (spawn, respawn).
func snap_to(feet: Vector3, p_yaw: float) -> void:
	yaw = p_yaw
	target_yaw = p_yaw
	pitch = deg_to_rad(default_pitch_degrees)
	target_pitch = pitch
	global_position = feet + Vector3.UP * height
	if is_node_ready():
		spring_arm.spring_length = _free_arm_length
		_apply_rotation()


func is_locked() -> bool:
	return targeting != null and is_instance_valid(targeting.current_target)


func _process(delta: float) -> void:
	var feet := follow.get_global_transform_interpolated().origin if follow is Node3D and follow.is_inside_tree() \
			else global_position - Vector3.UP * height
	var anchor := feet + Vector3.UP * height
	var arm := _free_arm_length
	var turn_rate := look_smoothing
	if is_locked():
		var to_target := targeting.current_target.global_position - feet
		to_target.y = 0.0
		var separation := to_target.length()
		if separation > 0.01:
			# Keep yaw continuous: aim at the shortest turn from where the camera is now.
			target_yaw = yaw + wrapf(atan2(-to_target.x, -to_target.z) - yaw, -PI, PI)
			anchor += to_target * lock_focus_bias
		target_pitch = deg_to_rad(lock_pitch_degrees)
		var t := clampf(inverse_lerp(lock_separation.x, lock_separation.y, separation), 0.0, 1.0)
		arm = lerpf(lock_arm_length.x, lock_arm_length.y, t)
		turn_rate = lock_turn_smoothing

	# Exponential decay toward the targets, alpha = 1 - e^(-k·dt).
	var look_t := 1.0 - exp(-turn_rate * delta)
	yaw = lerpf(yaw, target_yaw, look_t)
	pitch = lerpf(pitch, target_pitch, look_t)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, arm, 1.0 - exp(-arm_smoothing * delta))
	global_position = global_position.lerp(anchor, 1.0 - exp(-follow_smoothing * delta))
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)       # top level → global yaw
	spring_arm.rotation = Vector3(pitch, 0.0, 0.0)
