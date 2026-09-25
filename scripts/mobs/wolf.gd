class_name Wolf
extends CharacterBody3D
## Wandering wolf mob driven by a NavigationAgent3D on the baked NavigationRegion3D.
##
## WANDER  : every `wander_interval` seconds, walk to a random navmesh point within
##           `wander_radius` of home.
## CHASE   : the player entered the detection Area3D (10 m), so run at them and stop at
##           `chase_stop_distance`. Leaving the area drops back to WANDER.
## BITE    : in range, facing the player, cooldown ready. A telegraphed wind-up (it keeps
##           tracking the player), then a lunge while the jaw Hitbox is active (AttackData
##           `bite`). Hitting the wolf during the wind-up cancels the bite.
## STAGGER : reaction to a non-lethal hit: knockback, flinch, flash. Then it resumes and aggros.
## DEAD    : lethal hit. Plays the death animation, disables collision, sinks and frees itself.

enum State { WANDER, CHASE, BITE, STAGGER, DEAD }

@export_group("Wander")
@export var wander_radius := 15.0
@export var wander_interval := 4.0
@export var walk_speed := 2.2

@export_group("Chase")
@export var run_speed := 6.5
@export var chase_stop_distance := 1.8
## Seconds between path updates toward the moving player.
@export var repath_interval := 0.25

@export_group("Bite")
## Damage, timing and lunge of the bite (resources/combat/wolf_bite.tres).
@export var bite: AttackData
## A bite starts when the wolf is within this distance of its stop line (m).
@export var bite_range_slack := 0.3
## Random pause between bites (s).
@export var bite_cooldown := Vector2(1.4, 2.2)

@export_group("Motion")
@export var acceleration := 14.0
@export var turn_speed := 8.0

@export_group("Death")
## Seconds the body lies still after the death animation before sinking away.
@export var corpse_linger := 1.5

const _FLASH_TIME := 0.08

static var _flash_material: StandardMaterial3D

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection: Area3D = $DetectionArea
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var model: Node3D = $Model
@onready var bite_hitbox: Hitbox = $BiteHitbox
@onready var anim: AnimationPlayer = $Model/AnimationPlayer

var state := State.WANDER
var _home := Vector3.ZERO
var _target: Node3D
var _target_health: HealthComponent
var _bite_time := 0.0
var _bite_cooldown_left := 0.0
var _wander_timer := 0.0
var _repath_timer := 0.0
var _stagger_timer := 0.0
var _meshes: Array[Node] = []


func _ready() -> void:
	_home = global_position
	_wander_timer = randf() * wander_interval         # de-sync the pack
	floor_snap_length = 0.5
	_meshes = model.find_children("*", "MeshInstance3D")
	detection.body_entered.connect(_on_detection_entered)
	detection.body_exited.connect(_on_detection_exited)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	bite_hitbox.source = self
	anim.play(&"idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	match state:
		State.WANDER:
			_tick_wander(delta)
		State.CHASE:
			_tick_chase(delta)
		State.BITE:
			_tick_bite(delta)
		State.STAGGER:
			_tick_stagger(delta)
	move_and_slide()
	_update_animation()


# --- States ------------------------------------------------------------------------------

func _tick_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = wander_interval
		_pick_wander_point()
	_steer(walk_speed, delta)


func _tick_chase(delta: float) -> void:
	if not is_instance_valid(_target) or (_target_health and _target_health.is_dead):
		_enter_wander()                              # target gone or defeated: lose interest
		return
	_bite_cooldown_left -= delta
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		agent.target_position = _target.global_position
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var gap := to_target.length() - chase_stop_distance
	if gap <= bite_range_slack:
		_steer(0.0, delta)
		_face(to_target, delta)                      # hold ground, stare down the player
		var facing := -global_basis.z
		if _bite_cooldown_left <= 0.0 and bite and facing.dot(to_target.normalized()) > 0.8:
			_start_bite()
	else:
		# Arrival: cap speed so braking at `acceleration` ends exactly at the stop distance (v = √(2·a·d)).
		_steer(minf(run_speed, sqrt(2.0 * acceleration * gap)), delta)


func _start_bite() -> void:
	state = State.BITE
	_bite_time = 0.0
	bite_hitbox.begin(bite)
	anim.speed_scale = 1.0
	anim.play(bite.animation, 0.08)
	anim.seek(0.0, true)


func _tick_bite(delta: float) -> void:
	_bite_time += delta
	var t := _bite_time
	var lunge_end := bite.lunge_delay + bite.lunge_duration
	if t < bite.lunge_delay:
		_steer(0.0, delta)                           # wind-up: crouch and keep tracking the target
		if is_instance_valid(_target):
			var to_target := _target.global_position - global_position
			to_target.y = 0.0
			_face(to_target, delta)
	elif t < lunge_end:
		var forward := -global_basis.z
		velocity.x = forward.x * bite.lunge_speed
		velocity.z = forward.z * bite.lunge_speed
	else:
		_steer(0.0, delta)
	bite_hitbox.set_active(t >= bite.active_start and t < bite.active_end)
	if t >= bite.duration:
		_end_bite()
		state = State.CHASE


func _end_bite() -> void:
	bite_hitbox.set_active(false)
	_bite_cooldown_left = randf_range(bite_cooldown.x, bite_cooldown.y)


func _tick_stagger(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		if is_instance_valid(_target):
			state = State.CHASE
		else:
			_enter_wander()


func _enter_wander() -> void:
	state = State.WANDER
	_target = null
	_target_health = null
	_wander_timer = 0.0                                # choose a fresh point right away


# --- Movement ----------------------------------------------------------------------------

func _pick_wander_point() -> void:
	var map := agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return                                         # navmesh not baked yet
	var angle := randf() * TAU
	var radius := sqrt(randf()) * wander_radius        # sqrt → uniform over the disc
	var candidate := _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	agent.target_position = NavigationServer3D.map_get_closest_point(map, candidate)


## Accelerate toward the next path corner at `speed` (0 = brake).
func _steer(speed: float, delta: float) -> void:
	var desired := Vector3.ZERO
	if speed > 0.0 and not agent.is_navigation_finished():
		var to_next := agent.get_next_path_position() - global_position
		to_next.y = 0.0
		if to_next.length() > 0.05:
			desired = to_next.normalized() * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if horizontal.length_squared() > 0.04:
		_face(horizontal, delta)


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var yaw := atan2(-direction.x, -direction.z)     # model faces -Z
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _update_animation() -> void:
	if state == State.STAGGER or state == State.BITE:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var next := &"idle"
	anim.speed_scale = 1.0
	if speed > 3.5:
		next = &"run"
		anim.speed_scale = clampf(speed / run_speed, 0.7, 1.3)
	elif speed > 0.3:
		next = &"walk"
		anim.speed_scale = clampf(speed / walk_speed, 0.6, 1.4)
	if anim.current_animation != next:
		anim.play(next, 0.2)


# --- Signals -----------------------------------------------------------------------------

func _on_detection_entered(body: Node3D) -> void:
	if body is PlayerController and state != State.DEAD:
		_target = body
		_target_health = HealthComponent.resolve(body)
		if state == State.WANDER:
			state = State.CHASE
			_repath_timer = 0.0


func _on_detection_exited(body: Node3D) -> void:
	if body == _target and state == State.CHASE:
		_enter_wander()


func _on_damaged(hit: HitInfo) -> void:
	if health.is_dead:
		return                                         # died() handles lethal hits
	if state == State.BITE:
		_end_bite()                                    # interrupted mid-bite
	state = State.STAGGER
	_stagger_timer = hit.stagger_time
	velocity.x = hit.knockback.x
	velocity.z = hit.knockback.z
	if hit.source:
		_target = hit.source                           # getting hit always aggros
		_target_health = HealthComponent.resolve(hit.source)
	anim.speed_scale = 1.0
	anim.play(&"hurt", 0.05)
	anim.seek(0.0, true)
	_flash()


func _on_died(_hit: HitInfo) -> void:
	state = State.DEAD
	bite_hitbox.set_active(false)
	remove_from_group(&"enemies")
	# Collision changes are deferred: we are inside the katana's physics callback.
	$CollisionShape3D.set_deferred(&"disabled", true)
	hurtbox.set_deferred(&"monitorable", false)
	detection.set_deferred(&"monitoring", false)
	set_physics_process(false)                         # no gravity, so the corpse can't fall through the world
	_flash()
	anim.speed_scale = 1.0
	anim.play(&"death", 0.1)
	var sink := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	sink.tween_interval(anim.get_animation(&"death").length + corpse_linger)
	sink.tween_property(model, ^"position:y", -0.7, 1.2).set_trans(Tween.TRANS_SINE)
	sink.tween_callback(queue_free)


func _flash() -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_color = Color(1.0, 0.95, 0.9, 0.75)
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = _flash_material
	await get_tree().create_timer(_FLASH_TIME, true, false, true).timeout
	for mesh: MeshInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
