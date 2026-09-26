class_name CameraTrauma
extends Node
## Screen shake (M9b), as a child of the Camera3D. add_trauma() raises trauma (clamped to 1);
## the shake is trauma² so small knocks stay subtle and big ones bite. Trauma decays at
## `decay` per second of real time, so hit-stop doesn't freeze the shake mid-jolt.
##
## Six degrees of freedom from one FastNoiseLite sampled at separate offsets: h_offset and
## v_offset up to `max_offset` metres, pitch, yaw and roll up to `max_angle_degrees`. Only the
## Camera3D's offsets and local rotation are written, never the SpringArm, so the arm's wall
## collision stays correct. `enabled` (the pause menu's Screen shake option) turns it off.
## One per scene (group "camera_trauma", CameraTrauma.find()).

const LIGHT := 0.2
const HEAVY := 0.45
const PARRY := 0.35
const HURT := 0.35
const POSTURE_BREAK := 0.45
const EXECUTION := 0.75
const DEATH := 0.6

## Off for players who'd rather not have screen shake (persists across scene reloads).
static var enabled := true

@export var decay := 1.5
@export var max_offset := 0.35
@export var max_angle_degrees := 4.0
## Noise speed (higher = more jittery).
@export var frequency := 22.0

var trauma := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0
var _last_msec := 0

@onready var camera: Camera3D = get_parent() as Camera3D


func _ready() -> void:
	add_to_group(&"camera_trauma")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.seed = 7
	_noise.frequency = 1.0
	_last_msec = Time.get_ticks_msec()


## The CameraTrauma in `tree`'s scene, or null.
static func find(tree: SceneTree) -> CameraTrauma:
	return tree.get_first_node_in_group(&"camera_trauma") as CameraTrauma if tree else null


func add_trauma(amount: float) -> void:
	if not enabled:
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)


## How hard the camera shakes right now (0–1).
func shake() -> float:
	return trauma * trauma


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_delta := minf((now - _last_msec) / 1000.0, 0.1)
	_last_msec = now
	if get_tree().paused:
		real_delta = 0.0                                   # hold still behind the pause menu
	trauma = maxf(trauma - decay * real_delta, 0.0)
	_time += real_delta * frequency
	if camera == null:
		return
	var amount := shake() if enabled else 0.0
	camera.h_offset = max_offset * amount * _noise.get_noise_2d(_time, 0.0)
	camera.v_offset = max_offset * amount * _noise.get_noise_2d(_time, 100.0)
	var angle := deg_to_rad(max_angle_degrees) * amount
	camera.rotation = Vector3(angle * _noise.get_noise_2d(_time, 200.0), angle * _noise.get_noise_2d(_time, 300.0), angle * _noise.get_noise_2d(_time, 400.0))
