class_name CombatStateMachine
extends Node
## Samurai combat FSM: IDLE, RUN, ATTACK_1, ATTACK_2, ATTACK_3, plus the HURT and DEAD reactions.
##
## • This script owns the logic. The AnimationTree (StateMachine root) only blends, driven
##   by playback.travel().
## • Input buffer: an attack press is remembered for `input_buffer_seconds`. If it is still
##   fresh when the current strike reaches AttackData.combo_window_open, the next strike
##   chains, so a press during the wind-up is never lost. After ATTACK_3 the combo resets.
## • Active frames (AttackData.active_start → active_end) switch the katana hitbox and trail on.
## • Sheathing: after `sheathe_delay` seconds without attacking, the katana returns to the back.
## • Taking a hit (HealthComponent.damaged) cancels the swing, applies knockback, and flinches
##   for the hit's stagger time. Dying kneels, then respawns after `respawn_delay`.

signal state_changed(previous: State, current: State)

enum State { IDLE, RUN, ATTACK_1, ATTACK_2, ATTACK_3, HURT, DEAD }

@export var body: PlayerController
@export var animation_tree: AnimationTree
@export var katana: Katana
@export var holster: WeaponHolster
## The samurai's own health (hurt and death reactions).
@export var health: HealthComponent
## Strikes in combo order: index 0 plays in ATTACK_1, and so on.
@export var combo: Array[AttackData] = []
@export var input_buffer_seconds := 0.35
## Idle timer (s) before the katana is sheathed.
@export var sheathe_delay := 3.0
## Horizontal speed (m/s) above which locomotion counts as RUN.
@export var run_threshold := 0.6
## Shortest flinch, even from a light hit (s).
@export var min_hurt_time := 0.3
@export var respawn_delay := 2.5

@export_group("Soft Lock")
## Strikes snap toward the nearest enemy inside this range and cone.
@export var lock_range := 3.5
@export_range(0.0, 180.0) var lock_half_angle_degrees := 70.0

const _NO_PRESS := -1_000_000

var state := State.IDLE
var _state_time := 0.0
var _press_msec := _NO_PRESS
var _time_since_attack := 0.0
var _playback: AnimationNodeStateMachinePlayback
var _hurt_duration := 0.0


func _ready() -> void:
	_playback = animation_tree.get(&"parameters/playback")
	animation_tree.active = true
	katana.hitbox.source = body
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_playback.travel(&"idle")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"attack"):
		return
	# A click that only recaptures the mouse must not attack. Keys and touch buttons
	# (InputEventAction) always may.
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_press_msec = Time.get_ticks_msec()


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.HURT:
			_tick_hurt()
		State.DEAD:
			pass                                     # respawn is timer-driven (_on_died)
		_:
			if is_attacking():
				_tick_attack()
			else:
				_tick_locomotion(delta)


func is_attacking() -> bool:
	return state >= State.ATTACK_1 and state <= State.ATTACK_3


func _tick_locomotion(delta: float) -> void:
	if _consume_press():
		_start_attack(0)
		return
	_time_since_attack += delta
	if _time_since_attack >= sheathe_delay and holster.is_drawn():
		holster.sheathe()
	var next := State.RUN if body.get_planar_speed() > run_threshold else State.IDLE
	if next != state:
		_change_state(next)


func _tick_attack() -> void:
	var index := state - State.ATTACK_1
	var attack := combo[index]
	katana.set_active(_state_time >= attack.active_start and _state_time < attack.active_end)

	# Never chain before the active frames finish, or mashing would cut every swing short.
	var chain_time := maxf(attack.combo_window_open, attack.active_end)
	var can_chain := index + 1 < combo.size() and _state_time >= chain_time
	if can_chain and _consume_press():
		_start_attack(index + 1)
	elif _state_time >= attack.duration:
		katana.set_active(false)
		body.end_attack()
		_time_since_attack = 0.0
		_change_state(State.RUN if body.get_planar_speed() > run_threshold else State.IDLE)


func _start_attack(index: int) -> void:
	var attack := combo[index]
	katana.set_active(false)                 # close the previous strike's window, if any
	holster.draw()
	body.begin_attack(_attack_direction(), attack.lunge_speed, attack.lunge_duration, attack.lunge_delay)
	katana.begin_swing(attack)
	_time_since_attack = 0.0
	_change_state((State.ATTACK_1 + index) as State)


func _tick_hurt() -> void:
	if _state_time >= _hurt_duration:
		body.lock_controls(false)
		_change_state(State.RUN if body.get_planar_speed() > run_threshold else State.IDLE)


func _on_damaged(hit: HitInfo) -> void:
	if health.is_dead:
		return                                   # _on_died handles lethal hits
	katana.set_active(false)                     # a hit cancels the swing
	_press_msec = _NO_PRESS
	body.lock_controls(true)
	body.apply_knockback(hit.knockback)
	_hurt_duration = maxf(hit.stagger_time, min_hurt_time)
	_change_state(State.HURT)


func _on_died(_hit: HitInfo) -> void:
	katana.set_active(false)
	_press_msec = _NO_PRESS
	body.lock_controls(true)
	_change_state(State.DEAD)
	await get_tree().create_timer(respawn_delay).timeout
	health.revive()
	body.respawn()
	_time_since_attack = 0.0
	_change_state(State.IDLE)


func _change_state(next: State) -> void:
	var previous := state
	state = next
	_state_time = 0.0
	_playback.travel(_animation_for(next))
	state_changed.emit(previous, next)


func _animation_for(s: State) -> StringName:
	match s:
		State.IDLE:
			return &"idle"
		State.RUN:
			return &"run"
		State.HURT:
			return &"hurt"
		State.DEAD:
			return &"death"
	return combo[s - State.ATTACK_1].animation


## A press counts once, and only while it is younger than the buffer window.
func _consume_press() -> bool:
	if Time.get_ticks_msec() - _press_msec > int(input_buffer_seconds * 1000.0):
		return false
	_press_msec = _NO_PRESS
	return true


## Strike toward the input direction (or current facing), snapped to a nearby enemy in front.
func _attack_direction() -> Vector3:
	var direction := body.get_move_direction()
	if direction == Vector3.ZERO:
		direction = body.get_facing()
	var min_dot := cos(deg_to_rad(lock_half_angle_degrees))
	var best_distance := lock_range
	var best_direction := direction
	for enemy: Node3D in get_tree().get_nodes_in_group(&"enemies"):
		var to_enemy := enemy.global_position - body.global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance > 0.01 and distance < best_distance and direction.dot(to_enemy / distance) >= min_dot:
			best_distance = distance
			best_direction = to_enemy / distance
	return best_direction
