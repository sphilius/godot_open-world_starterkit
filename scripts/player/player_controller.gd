class_name PlayerController
extends CharacterBody3D
## Third-person explorer.
##
## Camera   : CombatCamera on the CameraRig (free look, and lock-on framing). Mouse, touch and
##            the gamepad right stick all feed it through add_look_input().
## Movement : camera-relative, with separate acceleration and deceleration rates and
##            reduced air control. The model turns toward its travel direction, or, while
##            locked on (TargetingSystem), keeps facing the target and strafes.
## Snapping : floor_snap_length keeps the body glued to the terrain when running downhill
##            or over crests, instead of launching off every bump.
## Also publishes its feet position to the `player_position` global shader uniform (grass push).
## Combat : CombatStateMachine calls begin_attack() / begin_dodge() / end_attack() to lock
##            steering and lunge (eased out, as velocity), and lock_controls() / apply_knockback()
##            / respawn() when the samurai is hurt.
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

@export_group("Look")
## Radians per screen pixel.
@export var mouse_sensitivity := 0.0022
## Gamepad right stick, radians per second at full tilt.
@export var stick_look_speed := 3.2
## Lock-on source; while it holds a target the body faces it.
@export var targeting: TargetingSystem

@export_group("Safety")
## Respawn if the player ever falls below this height.
@export var kill_height := -40.0

# Registered at runtime (physical keys → layout-independent WASD). Rebind in Project Settings ▸
# Input Map to override. Each entry is [kind, code(, axis sign)]: "key", "mouse", "joy" (button)
# or "axis" (joypad axis). Gamepad layout: Xbox names.
const _DEFAULT_BINDINGS := {
	&"move_forward": [["key", KEY_W], ["key", KEY_UP], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
	&"move_back": [["key", KEY_S], ["key", KEY_DOWN], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
	&"move_left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
	&"move_right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
	&"jump": [["key", KEY_SPACE], ["joy", JOY_BUTTON_A]],
	&"sprint": [["key", KEY_SHIFT], ["joy", JOY_BUTTON_LEFT_STICK]],
	&"attack": [["key", KEY_J], ["mouse", MOUSE_BUTTON_LEFT], ["joy", JOY_BUTTON_X]],
	&"attack_heavy": [["key", KEY_K], ["mouse", MOUSE_BUTTON_RIGHT], ["joy", JOY_BUTTON_Y]],
	&"dodge": [["key", KEY_L], ["key", KEY_C], ["joy", JOY_BUTTON_B]],
	&"lock_on": [["mouse", MOUSE_BUTTON_MIDDLE], ["key", KEY_Q], ["joy", JOY_BUTTON_RIGHT_STICK]],
	&"target_next": [["mouse", MOUSE_BUTTON_WHEEL_DOWN], ["key", KEY_E]],
	&"target_prev": [["mouse", MOUSE_BUTTON_WHEEL_UP]],
	&"look_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
	&"look_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
	&"look_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	&"look_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],
}
## Stick deadzone for the move actions.
const _AXIS_DEADZONE := 0.2

@onready var _visual: Node3D = $Visual
@onready var camera: CombatCamera = $CameraRig

var _spawn_position := Vector3.ZERO
var _spawn_yaw := 0.0
var _look_blocked_until_msec := 0   # swallows the cursor-warp jump that follows a mouse capture
var _move_direction := Vector3.ZERO # camera-relative input, even while attacking
var _controls_locked := false      # attacking, flinching or dead: no steering or jumping
var _lunge_velocity := Vector3.ZERO   # average velocity; the lunge eases out around it
var _lunge_duration := 0.0
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
	camera.follow = self
	camera.spring_arm.add_excluded_object(get_rid())
	var yaw := rotation.y
	rotation = Vector3.ZERO          # the body stays upright/unrotated; only $Visual turns
	spawn_at(global_position, yaw)
	if TouchControls.is_touch_mode():
		mouse_capture_enabled = false
	# Browsers only grant pointer lock from a user gesture: on the web, the first click captures.
	if not OS.has_feature("web"):
		_capture_mouse()


## Place the player and make this the respawn point. Yaw 0 faces -Z.
func spawn_at(pos: Vector3, yaw: float) -> void:
	_spawn_position = pos
	_spawn_yaw = yaw
	global_position = pos
	velocity = Vector3.ZERO
	_visual.rotation.y = yaw
	reset_physics_interpolation()
	camera.snap_to(pos, yaw)


## Face `direction`, lock steering and burst forward (after `lunge_delay`). Called at the start
## of every strike. `lunge_speed` is the average: the burst starts at twice that and eases out
## (quadratic), so it covers lunge_speed × lunge_duration metres.
func begin_attack(direction: Vector3, lunge_speed: float, lunge_duration: float, lunge_delay := 0.0) -> void:
	lock_controls(true)
	direction.y = 0.0
	direction = direction.normalized()
	if direction != Vector3.ZERO:
		face(direction)
	_start_lunge(direction * lunge_speed, lunge_duration, lunge_delay)


## Dash along `direction` like a lunge. With `turn` off (strafing, locked on), the body keeps
## its facing and the dash can go sideways or backwards.
func begin_dodge(direction: Vector3, speed: float, duration: float, turn := true) -> void:
	lock_controls(true)
	direction.y = 0.0
	direction = direction.normalized()
	if turn and direction != Vector3.ZERO:
		face(direction)
	_start_lunge(direction * speed, duration, 0.0)


## Turn the model to face `direction` at once (yaw only).
func face(direction: Vector3) -> void:
	_visual.rotation.y = atan2(-direction.x, -direction.z)


func _start_lunge(average_velocity: Vector3, duration: float, delay: float) -> void:
	_lunge_velocity = average_velocity
	_lunge_duration = maxf(duration, 0.001)
	_lunge_time_left = duration
	_lunge_delay_left = delay


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


## Rotate the camera by a look delta in radians (x = yaw, y = pitch). Mouse, touch drags and the
## right stick all land here.
func add_look_input(delta: Vector2) -> void:
	camera.add_look_input(delta)


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
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		add_look_input(stick * stick_look_speed * delta)
	RenderingServer.global_shader_parameter_set(&"player_position", get_global_transform_interpolated().origin)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed(&"jump") and is_on_floor() and not _controls_locked:
		velocity.y = jump_velocity

	# Camera-relative wish direction (yaw only, so looking down never slows you).
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wish := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera.yaw)
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
			var progress := 1.0 - _lunge_time_left / _lunge_duration
			horizontal = _lunge_velocity * 2.0 * (1.0 - progress)   # ease-out quad, same distance
			_lunge_time_left -= delta
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Ground snapping runs inside move_and_slide(): while grounded and not moving upward,
	# the body is pulled down (up to floor_snap_length) onto the surface. A jump's upward
	# velocity suspends the snap automatically, so jumps are never eaten.
	move_and_slide()

	if not _controls_locked:
		var look := horizontal
		if targeting and targeting.is_locked():
			look = targeting.current_target.global_position - global_position   # strafe: face the target
			look.y = 0.0
		if look.length_squared() > 0.05:
			var facing := atan2(-look.x, -look.z)   # model faces -Z
			_visual.rotation.y = lerp_angle(_visual.rotation.y, facing, 1.0 - exp(-turn_speed * delta))

	if global_position.y < kill_height:
		spawn_at(_spawn_position, _spawn_yaw)


static func _register_default_input_actions() -> void:
	for action: StringName in _DEFAULT_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, _AXIS_DEADZONE)
		for binding: Array in _DEFAULT_BINDINGS[action]:
			InputMap.action_add_event(action, _binding_event(binding))


static func _binding_event(binding: Array) -> InputEvent:
	match binding[0]:
		"mouse":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = binding[1] as MouseButton
			return mouse_event
		"joy":
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = binding[1] as JoyButton
			return button_event
		"axis":
			var axis_event := InputEventJoypadMotion.new()
			axis_event.axis = binding[1] as JoyAxis
			axis_event.axis_value = binding[2]
			return axis_event
	var key_event := InputEventKey.new()
	key_event.physical_keycode = binding[1] as Key
	return key_event
