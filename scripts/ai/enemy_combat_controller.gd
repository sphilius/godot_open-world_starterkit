class_name EnemyCombatController
extends CharacterBody3D
## Humanoid melee enemy (Grunt, Brute, and the Gatekeeper built on it). Generalises the wolf:
## navmesh chase with arrival braking and repaths, a telegraphed wind-up, posture and shared
## hit reactions.
##
## IDLE          : no player within `aggro_radius`.
## APPROACH      : holds the CombatDirector's attack token (or has no director): closes to
##                 `approach_distance`, then attacks.
## FLANKING      : no token: circles at its director ring slot, facing the player and strafing,
##                 and asks for a token every `token_retry` seconds once its cooldown is over.
## ATTACK_WINDUP : the strike's wind-up (it keeps turning toward the player). `telegraph_glint`
##                 fires `telegraph_lead` seconds before the active frames: red for unblockable
##                 strikes, gold otherwise.
## ATTACK_ACTIVE : weapon hitbox on (AttackData active window).
## RECOVER       : the strike's recovery (`recovery_scale` shortens it), then the next strike of
##                 a combo or back to deciding.
## STAGGERED     : a DamageReaction stagger (hit, knockdown, parried, posture break, roar).
## DEAD          : death clip; frees itself (`free_on_death`) or stays until reset_to_spawn().
## The attack token is released on every way out of an attack: its end, a stagger, death,
## reset, and leaving the tree. A posture break makes it executable: execute() deals
## `execution_damage_ratio` of max health.

signal telegraph_glint(position: Vector3, is_unblockable: bool)
signal state_changed(previous: State, current: State)
signal defeated
signal executed(by: Node3D)

enum State { IDLE, APPROACH, FLANKING, ATTACK_WINDUP, ATTACK_ACTIVE, RECOVER, STAGGERED, DEAD }

## DamageReaction stagger type → clip (enemy animation library).
const STAGGER_CLIPS := {
	&"front": &"hurt_f", &"left": &"hurt_f", &"right": &"hurt_f", &"back": &"hurt_b",
	&"heavy": &"stagger", &"guard_break": &"stagger", &"knockdown": &"posture_break",
	&"parried": &"parried", &"roar": &"roar",
}
const GLINT_SCENE := preload("res://scenes/vfx/telegraph_glint.tscn")

## Single strikes to pick from.
@export var attacks: Array[AttackData] = []
## Strings of strikes played on one token.
@export var combos: Array[EnemyCombo] = []
## The encounter's director. Without one, the enemy always approaches.
@export var director: CombatDirector

@export_group("Movement")
@export var walk_speed := 2.0
@export var run_speed := 4.5
@export var acceleration := 14.0
@export var turn_speed := 8.0
## Stops this far from the player (m) before striking.
@export var approach_distance := 2.0
@export var aggro_radius := 14.0
## Seconds between path updates toward a moving destination.
@export var repath_interval := 0.25

@export_group("Attack")
## Seconds of warning between the glint and the active frames.
@export var telegraph_lead := 0.4
## Random pause after an attack before asking for the next token (s).
@export var attack_cooldown := Vector2(0.6, 1.2)
## Seconds between token requests while flanking.
@export var token_retry := 0.3
## Multiplies each strike's recovery (after its active frames).
@export var recovery_scale := 1.0

@export_group("Execution and death")
## Share of max health an execution deals (1 = always kills).
@export_range(0.0, 1.0) var execution_damage_ratio := 1.0
@export var free_on_death := true
@export var corpse_linger := 1.5

@onready var health: HealthComponent = $HealthComponent
@onready var posture: PostureComponent = $PostureComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var reaction: DamageReactionComponent = $DamageReaction
@onready var weapon_hitbox: Hitbox = $WeaponHitbox
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $Model/AnimationPlayer

var state := State.IDLE
var target: Node3D
## The strike playing (null outside attacks).
var current_attack: AttackData
var glint: TelegraphGlint
var _spawn_transform: Transform3D
var _strikes: Array[AttackData] = []
var _strike_index := 0
var _attack_time := 0.0
var _glinted := false
var _cooldown_left := 0.0
var _retry_left := 0.0
var _repath_left := 0.0
var _engaged := false
var _sink: Tween


func _ready() -> void:
	_spawn_transform = global_transform
	add_to_group(&"enemies")
	floor_snap_length = 0.5
	var socket := model.find_child("WeaponSocket", true, false) as Node3D
	if socket:
		weapon_hitbox.reparent(socket, false)           # the hitbox rides the weapon bone
		var marker := socket.find_child("Socket_Telegraph_Glint", true, false) as Node3D
		glint = GLINT_SCENE.instantiate()
		(marker if marker else socket).add_child(glint)
	weapon_hitbox.source = self
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	reaction.stagger_started.connect(_on_stagger_started)
	reaction.stagger_ended.connect(_on_stagger_ended)
	if _director():
		_director().register(self)
	anim.play(&"idle")


func _exit_tree() -> void:
	if _director():
		_director().unregister(self)                    # releases a held token too


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	match state:
		State.IDLE:
			_tick_idle(delta)
		State.APPROACH:
			_tick_approach(delta)
		State.FLANKING:
			_tick_flanking(delta)
		State.ATTACK_WINDUP, State.ATTACK_ACTIVE, State.RECOVER:
			_tick_attack(delta)
		State.STAGGERED:
			pass                                         # DamageReaction brakes it and ends it
	move_and_slide()
	_update_locomotion_clip()


## True while its posture is broken: an execution is possible.
func is_executable() -> bool:
	return state != State.DEAD and not health.is_dead and posture.is_broken


## Deathblow on a broken posture: deals `execution_damage_ratio` of max health. Returns true if
## it happened.
func execute(by: Node3D) -> bool:
	if not is_executable():
		return false
	var hit := HitInfo.new(health.max_health * execution_damage_ratio, by)
	hit.unblockable = true
	hit.can_be_parried = false
	posture.reset()
	health.take_damage(hit)
	executed.emit(by)
	if not health.is_dead:
		reaction.react(&"knockdown", reaction.knockdown_time)
	return true


func has_attack_token() -> bool:
	if _director():
		return _director().has_attack_token(self)
	return state in [State.APPROACH, State.ATTACK_WINDUP, State.ATTACK_ACTIVE, State.RECOVER]


## Encounter reset: back to the spawn point, alive and idle.
func reset_to_spawn() -> void:
	_abort_attack()
	if _sink:
		_sink.kill()
	model.position = Vector3.ZERO
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	health.revive()
	posture.reset()
	reaction.clear()
	target = null
	_engaged = false
	_cooldown_left = 0.0
	add_to_group(&"enemies")
	$CollisionShape3D.set_deferred(&"disabled", false)
	hurtbox.set_deferred(&"monitorable", true)
	if _director():
		_director().register(self)
	set_physics_process(true)
	_set_state(State.IDLE)
	anim.play(&"idle")


# --- States ------------------------------------------------------------------------------

func _tick_idle(delta: float) -> void:
	_brake(delta)
	if _acquire_target():
		_decide()


func _tick_approach(delta: float) -> void:
	if not _target_valid() or (_director() and not _director().has_attack_token(self)):
		_decide()                                        # target gone, or the lease expired
		return
	var to_target := _flat(target.global_position - global_position)
	if to_target.length() <= approach_distance + 0.3:
		_brake(delta)
		_face(to_target, delta)
		if _facing_error(to_target) < deg_to_rad(25.0):
			_start_attack()
		return
	_steer_to(target.global_position, run_speed, delta, true)


func _tick_flanking(delta: float) -> void:
	if not _target_valid():
		_decide()
		return
	var spot := _director().get_flank_position(self, target) if _director() else global_position
	if _flat(spot - global_position).length() > 0.6:
		_steer_to(spot, walk_speed, delta, false)
	else:
		_brake(delta)
	_face(_flat(target.global_position - global_position), delta)
	_retry_left -= delta
	if _retry_left <= 0.0 and _cooldown_left <= 0.0:
		_retry_left = token_retry
		if not _director() or _director().request_attack_token(self):
			_set_state(State.APPROACH)


func _tick_attack(delta: float) -> void:
	var attack := current_attack
	_attack_time += delta
	if not _glinted and _attack_time >= attack.active_start - telegraph_lead:
		_glinted = true
		var point := glint.global_position if glint else global_position + Vector3.UP * 1.6
		if glint:
			glint.flash(attack.unblockable)
		telegraph_glint.emit(point, attack.unblockable)
	# Track the player during the wind-up; commit once the swing starts.
	if _attack_time < attack.active_start - 0.1 and _target_valid():
		_face(_flat(target.global_position - global_position), delta)
	# Lunge (eased out, like the player's), otherwise brake.
	var lunge_end := attack.lunge_delay + attack.lunge_duration
	if attack.lunge_duration > 0.0 and _attack_time >= attack.lunge_delay and _attack_time < lunge_end:
		var progress := (_attack_time - attack.lunge_delay) / attack.lunge_duration
		var push := _forward() * attack.lunge_speed * 2.0 * (1.0 - progress)
		velocity.x = push.x
		velocity.z = push.z
	else:
		_brake(delta)
	var active := _attack_time >= attack.active_start and _attack_time < attack.active_end
	weapon_hitbox.set_active(active)
	if active:
		_set_state(State.ATTACK_ACTIVE)
	elif _attack_time >= attack.active_end:
		_set_state(State.RECOVER)
	var end_time := attack.active_end + (attack.duration - attack.active_end) * recovery_scale
	if _attack_time >= end_time:
		if _strike_index + 1 < _strikes.size():
			_begin_strike(_strike_index + 1)
		else:
			_finish_attack()


# --- Attacks -----------------------------------------------------------------------------

func _start_attack() -> void:
	var pool: Array = []
	pool.append_array(attacks)
	pool.append_array(combos)
	if pool.is_empty():
		_finish_attack()
		return
	var pick: Variant = pool[randi() % pool.size()]
	_strikes.clear()
	if pick is EnemyCombo:
		_strikes.append_array((pick as EnemyCombo).strikes)
	else:
		_strikes.append(pick)
	_begin_strike(0)


func _begin_strike(index: int) -> void:
	_strike_index = index
	current_attack = _strikes[index]
	_attack_time = 0.0
	_glinted = false
	weapon_hitbox.begin(current_attack)
	weapon_hitbox.set_active(false)
	anim.speed_scale = 1.0
	anim.play(current_attack.animation, 0.08)
	anim.seek(0.0, true)
	_set_state(State.ATTACK_WINDUP)


func _finish_attack() -> void:
	_abort_attack()
	_cooldown_left = randf_range(attack_cooldown.x, attack_cooldown.y)
	_decide()


## Stops any strike and hands the token back.
func _abort_attack() -> void:
	weapon_hitbox.set_active(false)
	current_attack = null
	_strikes.clear()
	if _director():
		_director().release_attack_token(self)


func _decide() -> void:
	if not _acquire_target():
		_set_state(State.IDLE)
		return
	if not _director():
		_set_state(State.APPROACH if _cooldown_left <= 0.0 else State.FLANKING)
		return
	if _cooldown_left <= 0.0 and _director().request_attack_token(self):
		_set_state(State.APPROACH)
	else:
		_retry_left = token_retry
		_set_state(State.FLANKING)


## Called once, the first time a target is acquired (the Gatekeeper shows its HUD bar).
func _on_engaged() -> void:
	pass


# --- Helpers -----------------------------------------------------------------------------

## The director, or null once it's gone (encounter teardown frees it first sometimes).
func _director() -> CombatDirector:
	return director if is_instance_valid(director) else null


func _acquire_target() -> bool:
	if not _target_valid():
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if not _target_valid():
		target = null
		return false
	if not _engaged:
		if _flat(target.global_position - global_position).length() > aggro_radius:
			return false
		_engaged = true
		_on_engaged()
	return true


func _target_valid() -> bool:
	if not is_instance_valid(target):
		return false
	var target_health := HealthComponent.resolve(target)
	return target_health == null or not target_health.is_dead


func _steer_to(destination: Vector3, speed: float, delta: float, turn: bool) -> void:
	_repath_left -= delta
	if _repath_left <= 0.0 or agent.target_position.distance_to(destination) > 1.0:
		_repath_left = repath_interval
		agent.target_position = destination
	var next := destination
	if not agent.get_current_navigation_path().is_empty() and not agent.is_navigation_finished():
		next = agent.get_next_path_position()
	var to_next := _flat(next - global_position)
	var desired := to_next.normalized() * speed if to_next.length() > 0.05 else Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if turn and horizontal.length_squared() > 0.04:
		_face(horizontal, delta)


func _brake(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var yaw := atan2(-direction.x, -direction.z)         # model faces -Z
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _forward() -> Vector3:
	return _flat(-global_basis.z).normalized()


func _facing_error(direction: Vector3) -> float:
	return _forward().angle_to(direction.normalized()) if direction.length_squared() > 0.0001 else 0.0


func _set_state(next: State) -> void:
	if next == state:
		return
	var previous := state
	state = next
	state_changed.emit(previous, next)


func _update_locomotion_clip() -> void:
	if state not in [State.IDLE, State.APPROACH, State.FLANKING]:
		return
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar.length()
	var clip := &"idle"
	if speed > 0.3:
		var side := planar.normalized().dot(_forward().cross(Vector3.UP))
		if state == State.FLANKING and absf(side) > 0.6:
			clip = &"strafe_r" if side > 0.0 else &"strafe_l"
		else:
			clip = &"run" if speed > walk_speed + 0.5 else &"walk"
	if anim.current_animation != clip:
		anim.play(clip, 0.2)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Signals -----------------------------------------------------------------------------

func _on_damaged(hit: HitInfo) -> void:
	if is_instance_valid(hit.source) and hit.source.is_in_group(&"player"):
		target = hit.source                              # getting hit always aggros
		if not _engaged:
			_engaged = true
			_on_engaged()


func _on_stagger_started(type: StringName) -> void:
	if state == State.DEAD:
		return
	_abort_attack()
	_set_state(State.STAGGERED)
	var clip: StringName = STAGGER_CLIPS.get(type, &"hurt_f")
	anim.speed_scale = 1.0
	anim.play(clip if anim.has_animation(clip) else &"hurt_f", 0.05)
	anim.seek(0.0, true)


func _on_stagger_ended() -> void:
	if state == State.STAGGERED:
		_decide()


func _on_died(_hit: HitInfo) -> void:
	_abort_attack()
	reaction.clear()
	_set_state(State.DEAD)
	if _director():
		_director().unregister(self)
	remove_from_group(&"enemies")
	# Deferred: we are inside the attacker's physics callback.
	$CollisionShape3D.set_deferred(&"disabled", true)
	hurtbox.set_deferred(&"monitorable", false)
	set_physics_process(false)
	anim.speed_scale = 1.0
	anim.play(&"death", 0.1)
	defeated.emit()
	if not free_on_death:
		return
	_sink = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_sink.tween_interval(anim.get_animation(&"death").length + corpse_linger)
	_sink.tween_property(model, ^"position:y", -1.0, 1.2).set_trans(Tween.TRANS_SINE)
	_sink.tween_callback(queue_free)
