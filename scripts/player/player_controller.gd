class_name PlayerController
extends CharacterBody3D
## Third-person explorer.
##
## Camera   : the mouse feeds yaw/pitch *targets*, eased with frame-rate-independent
##            exponential smoothing. A top-level rig follows the physics-*interpolated*
##            body, so the view stays smooth at any refresh rate. SpringArm3D pulls the
##            camera in when terrain or landmarks get between it and the player.
## Movement : camera-relative, with separate acceleration and deceleration rates and
##            reduced air control.
## Snapping : floor_snap_length keeps the body glued to the terrain when running downhill
##            or over crests, instead of launching off every bump.
## Also publishes its feet position to the `player_position` global shader uniform (grass push).
## Combat : CombatStateMachine calls begin_attack() / end_attack() to lock steering and lunge,
##            and lock_controls() / apply_knockback() / respawn() when the samurai is hurt.
## Look     : mouse and touch both feed add_look_input(). Touch mode turns off mouse capture.

@export_group("Movement")
@export var walk_speed := 4.5
@export var sprint_speed := 8.5
## m/s² toward the input direction.
@export var acceleration := 20.0
## m/s² of braking when there is no input.
@export var deceleration := 26.0
@export_range(0.0, 1.0) var air_control := 0.3
@export var jump_velocity := 5.2
## How quickly the body turns to face its travel direction.
@export var turn_speed := 10.0

@export_group("Ground Snapping")
## How far below the feet the body searches for ground to stick to while grounded.
@export var snap_length := 0.6
@export_range(0.0, 89.0) var max_slope_degrees := 50.0

@export_group("Camera")
## Radians per screen pixel.
@export var mouse_sensitivity := 0.0022
## Exponential-decay rate for look smoothing (higher = snappier).
@export_range(1.0, 50.0) var look_smoothing := 16.0
## Exponential-decay rate for the rig chasing the body.
@export_range(1.0, 50.0) var follow_smoothing := 12.0
@export var camera_height := 1.6
@export_range(-89.0, 0.0) var min_pitch_degrees := -65.0
@export_range(0.0, 89.0) var max_pitch_degrees := 30.0
@export var default_pitch_degrees := -6.0
@export var invert_y := false

@export_group("Safety")
## Respawn if the player ever falls below this height.
@export var kill_height := -40.0

# Registered at runtime (physical keys → layout-independent WASD). Rebind in Project Settings ▸ Input Map to override.
# MOUSE_BUTTON_* values (1, 2) never collide with Key codes, so one list can hold both.
const _DEFAULT_BINDINGS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"attack": [KEY_J, MOUSE_BUTTON_LEFT],
}

@onready var _visual: Node3D = $Visual
@onready var _camera_rig: Node3D = $CameraRig
@onready var _spring_arm: SpringArm3D = $CameraRig/SpringArm3D

var _yaw := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_pitch := 0.0
var _spawn_position := Vector3.ZERO
var _spawn_yaw := 0.0
var _look_blocked_until_msec := 0   # swallows the cursor-warp jump that follows a mouse capture
var _move_direction := Vector3.ZERO # camera-relative input, even while attacking
var _controls_locked := false      # attacking, flinching or dead: no steering or jumping
var _lunge_velocity := Vector3.ZERO
var _lunge_time_left := 0.0
var _lunge_delay_left := 0.0

## Off in touch mode (TouchControls): clicks and taps never grab the pointer.
var mouse_capture_enabled := true


func _enter_tree() -> void:
	_register_default_input_actions()


func _ready() -> void:
	floor_snap_length = snap_length
	floor_max_angle = deg_to_rad(max_slope_degrees)
	floor_constant_speed = true    # same ground speed uphill and downhill
	floor_stop_on_slope = true     # no creeping down slopes while idle
	_camera_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved by hand in _process
	_spring_arm.add_excluded_object(get_rid())
	var yaw := rotation.y
	rotation = Vector3.ZERO          # the body stays upright/unrotated; only $Visual turns
	spawn_at(global_position, yaw)
	_capture_mouse()


## Place the player and make this the respawn point. Yaw 0 faces -Z.
func spawn_at(pos: Vector3, yaw: float) -> void:
	_spawn_position = pos
	_spawn_yaw = yaw
	global_position = pos
	velocity = Vector3.ZERO
	_visual.rotation.y = yaw
	_yaw = yaw
	_target_yaw = yaw
	_pitch = deg_to_rad(default_pitch_degrees)
	_target_pitch = _pitch
	reset_physics_interpolation()
	_camera_rig.global_position = pos + Vector3.UP * camera_height
	_apply_camera_rotation()


## Face `direction`, lock steering and burst forward (after `lunge_delay`). Called at the start of every strike.
func begin_attack(direction: Vector3, lunge_speed: float, lunge_duration: float, lunge_delay := 0.0) -> void:
	lock_controls(true)
	direction.y = 0.0
	direction = direction.normalized()
	if direction != Vector3.ZERO:
		_visual.rotation.y = atan2(-direction.x, -direction.z)
	_lunge_velocity = direction * lunge_speed
	_lunge_time_left = lunge_duration
	_lunge_delay_left = lunge_delay


func end_attack() -> void:
	lock_controls(false)


## While locked, input can't steer or jump; the body just brakes (plus any lunge or knockback).
func lock_controls(locked: bool) -> void:
	_controls_locked = locked


## Shove the body horizontally (cancels any lunge). Braking then uses `deceleration`.
func apply_knockback(knockback: Vector3) -> void:
	velocity.x = knockback.x
	velocity.z = knockback.z
	_lunge_time_left = 0.0


## Back to the last spawn point with controls unlocked.
func respawn() -> void:
	spawn_at(_spawn_position, _spawn_yaw)
	lock_controls(false)


## Rotate the camera by a look delta in radians (x = yaw, y = pitch). Mouse and touch drags both land here.
func add_look_input(delta: Vector2) -> void:
	_target_yaw -= delta.x
	_target_pitch -= delta.y * (-1.0 if invert_y else 1.0)
	_target_pitch = clampf(_target_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


## Camera-relative movement input (unit length or zero). Still reported while attacking.
func get_move_direction() -> Vector3:
	return _move_direction


## Flat forward vector of the character model.
func get_facing() -> Vector3:
	var forward := -_visual.global_basis.z
	forward.y = 0.0
	return forward.normalized()


func get_planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Time.get_ticks_msec() < _look_blocked_until_msec:
			return
		# screen_relative ignores viewport stretch, so sensitivity is resolution-independent.
		add_look_input((event as InputEventMouseMotion).screen_relative * mouse_sensitivity)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()


func _capture_mouse() -> void:
	if not mouse_capture_enabled:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_look_blocked_until_msec = Time.get_ticks_msec() + 200


func _process(delta: float) -> void:
	# Mouse smoothing: exponential decay toward the target, alpha = 1 - e^(-k·dt).
	var look_t := 1.0 - exp(-look_smoothing * delta)
	_yaw = lerpf(_yaw, _target_yaw, look_t)
	_pitch = lerpf(_pitch, _target_pitch, look_t)
	_apply_camera_rotation()

	var feet := get_global_transform_interpolated().origin
	var anchor := feet + Vector3.UP * camera_height
	_camera_rig.global_position = _camera_rig.global_position.lerp(anchor, 1.0 - exp(-follow_smoothing * delta))
	RenderingServer.global_shader_parameter_set(&"player_position", feet)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed(&"jump") and is_on_floor() and not _controls_locked:
		velocity.y = jump_velocity

	# Camera-relative wish direction (yaw only, so looking down never slows you).
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wish := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _yaw)
	_move_direction = wish.normalized()
	if _controls_locked:
		wish = Vector3.ZERO           # strikes and flinches commit: no steering, just brake
	var top_speed := sprint_speed if Input.is_action_pressed(&"sprint") else walk_speed

	# Acceleration / deceleration: steer horizontal velocity toward the target at a capped rate.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if wish != Vector3.ZERO else deceleration
	if not is_on_floor():
		rate *= air_control
	horizontal = horizontal.move_toward(wish * top_speed, rate * delta)
	if _lunge_time_left > 0.0:
		if _lunge_delay_left > 0.0:
			_lunge_delay_left -= delta
		else:
			horizontal = _lunge_velocity
			_lunge_time_left -= delta
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Ground snapping runs inside move_and_slide(): while grounded and not moving upward,
	# the body is pulled down (up to floor_snap_length) onto the surface. A jump's upward
	# velocity suspends the snap automatically, so jumps are never eaten.
	move_and_slide()

	if horizontal.length_squared() > 0.05 and not _controls_locked:
		var facing := atan2(-horizontal.x, -horizontal.z)   # model faces -Z
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing, 1.0 - exp(-turn_speed * delta))

	if global_position.y < kill_height:
		spawn_at(_spawn_position, _spawn_yaw)


func _apply_camera_rotation() -> void:
	_camera_rig.rotation = Vector3(0.0, _yaw, 0.0)   # rig is top_level → global yaw
	_spring_arm.rotation = Vector3(_pitch, 0.0, 0.0)


static func _register_default_input_actions() -> void:
	for action: StringName in _DEFAULT_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code: int in _DEFAULT_BINDINGS[action]:
			var input_event: InputEvent
			if code == MOUSE_BUTTON_LEFT or code == MOUSE_BUTTON_RIGHT:
				var mouse_event := InputEventMouseButton.new()
				mouse_event.button_index = code as MouseButton
				input_event = mouse_event
			else:
				var key_event := InputEventKey.new()
				key_event.physical_keycode = code as Key
				input_event = key_event
			InputMap.action_add_event(action, input_event)
