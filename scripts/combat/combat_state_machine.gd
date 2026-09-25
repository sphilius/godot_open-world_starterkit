class_name CombatStateMachine
extends Node
## Player combat FSM: IDLE, RUN, ATTACK, DODGE, plus the HURT and DEAD reactions.
## (The runbook calls this node CombatController.)
##
## • This script owns the logic. The AnimationTree (StateMachine root) only blends, driven by
##   playback.travel(); every strike names its own clip (AttackData.animation).
## • Which strike comes next is ComboManager's job: presses of attack (light), attack_heavy and
##   dodge go into its FIFO buffer, and its combo graph maps them to strikes. Presses made
##   while sheathed start the quick-draw opener.
## • Chaining: a buffered press chains at max(combo_window_open, active_end), so a press during
##   the wind-up is never lost and swings are never cut short. AttackData.cancel_open /
##   cancel_into allow earlier cancels (a dodge out of a heavy wind-up, for example), and a
##   dodge may always cancel a strike's recovery (after active_end).
## • Active frames (active_start → active_end) switch the weapon hitbox and trail on.
## • MotionWarping plans each lunge toward the lock-on target or a nearby enemy.
## • Dodge: a dash with invulnerability frames. With a lock-on target it keeps facing the
##   target and plays the directional clip; otherwise it turns into the dash (dodge_f), or
##   backsteps (dodge_b) when there's no movement input.
## • Sheathing: after `sheathe_delay` seconds without attacking, the weapon is sheathed.
## • Taking a hit (HealthComponent.damaged) cancels the swing, applies knockback, and flinches
##   for the hit's stagger time. Dying kneels, then respawns after `respawn_delay`.

signal state_changed(previous: State, current: State)
signal attack_started(attack: AttackData)
signal dodge_started(direction: Vector3)

enum State { IDLE, RUN, ATTACK, DODGE, HURT, DEAD }

const LIGHT := ComboManager.LIGHT
const HEAVY := ComboManager.HEAVY
const DODGE := ComboManager.DODGE
const ALL_ACTIONS: Array[StringName] = [ComboManager.LIGHT, ComboManager.HEAVY, ComboManager.DODGE]

@export var body: PlayerController
@export var animation_tree: AnimationTree
@export var katana: Katana
@export var holster: WeaponHolster
## The samurai's own health (hurt and death reactions, dodge invulnerability).
@export var health: HealthComponent
@export var combo: ComboManager
@export var warping: MotionWarping
## Optional lock-on source (TargetingSystem): its `current_target` makes dodges strafe.
@export var targeting: Node
## Idle timer (s) before the weapon is sheathed.
@export var sheathe_delay := 3.0
## Horizontal speed (m/s) above which locomotion counts as RUN.
@export var run_threshold := 0.6
## Shortest flinch, even from a light hit (s).
@export var min_hurt_time := 0.3
@export var respawn_delay := 2.5

@export_group("Dodge")
## Must match the dodge clips' length (tools/build_placeholder_rigs.gd DODGE_LENGTH).
@export var dodge_duration := 0.45
## Distance covered (m); the dash eases out over `dodge_move_time`.
@export var dodge_distance := 3.2
@export var dodge_move_time := 0.32
## Invulnerable from x to y seconds into the dodge.
@export var dodge_iframes := Vector2(0.08, 0.3)
## From this time on, strikes may cancel the dodge's recovery.
@export var dodge_cancel_time := 0.3

var state := State.IDLE
## The strike playing in ATTACK (null otherwise).
var current_attack: AttackData
var _state_time := 0.0
var _time_since_attack := 0.0
var _playback: AnimationNodeStateMachinePlayback
var _hurt_duration := 0.0
var _iframes_granted := false


func _ready() -> void:
	_playback = animation_tree.get(&"parameters/playback")
	animation_tree.active = true
	katana.hitbox.source = body
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_playback.travel(&"idle")


func _unhandled_input(event: InputEvent) -> void:
	var action := &""
	if event.is_action_pressed(&"attack"):
		action = LIGHT
	elif event.is_action_pressed(&"attack_heavy"):
		action = HEAVY
	elif event.is_action_pressed(&"dodge"):
		action = DODGE
	else:
		return
	# A click that only recaptures the mouse must not attack. Keys, gamepad buttons and touch
	# buttons (InputEventAction) always may.
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if state != State.DEAD:
		combo.push_input(action)


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.ATTACK:
			_tick_attack()
		State.DODGE:
			_tick_dodge()
		State.HURT:
			_tick_hurt()
		State.DEAD:
			pass                                     # respawn is timer-driven (_on_died)
		_:
			_tick_locomotion(delta)


func is_attacking() -> bool:
	return state == State.ATTACK


func _tick_locomotion(delta: float) -> void:
	if _take_action(ALL_ACTIONS):
		return
	_time_since_attack += delta
	if _time_since_attack >= sheathe_delay and holster.is_drawn():
		holster.sheathe()
	var next := _locomotion_state()
	if next != state:
		_change_state(next, &"run" if next == State.RUN else &"idle")


func _tick_attack() -> void:
	var attack := current_attack
	katana.set_active(_state_time >= attack.active_start and _state_time < attack.active_end)
	# Never chain before the active frames finish, or mashing would cut every swing short.
	var allowed: Array[StringName] = []
	if _state_time >= maxf(attack.combo_window_open, attack.active_end):
		allowed = ALL_ACTIONS
	else:
		if attack.cancel_open >= 0.0 and _state_time >= attack.cancel_open:
			allowed.append_array(attack.cancel_into)
		if _state_time >= attack.active_end and not allowed.has(DODGE):
			allowed.append(DODGE)                    # recovery can always be dodged out of
	if _take_action(allowed):
		return
	if _state_time >= attack.duration:
		katana.set_active(false)
		body.end_attack()
		combo.attack_finished()
		_time_since_attack = 0.0
		_enter_locomotion()


func _tick_dodge() -> void:
	if not _iframes_granted and _state_time >= dodge_iframes.x:
		_iframes_granted = true
		health.grant_invulnerability(dodge_iframes.y - dodge_iframes.x)
	if _state_time >= dodge_cancel_time and _take_action([LIGHT, HEAVY] as Array[StringName]):
		return
	if _state_time >= dodge_duration:
		body.end_attack()
		_enter_locomotion()


func _tick_hurt() -> void:
	if _state_time >= _hurt_duration:
		body.lock_controls(false)
		_enter_locomotion()


## Starts the oldest buffered action if it's allowed now and leads somewhere. Returns true if
## something started.
func _take_action(allowed: Array[StringName]) -> bool:
	var sheathed := not holster.is_drawn()
	var ready: Array[StringName] = []
	for action in allowed:
		if action == DODGE or combo.has_branch(action, sheathed):
			ready.append(action)
	var action := combo.consume(ready)
	if action == &"":
		return false
	if action == DODGE:
		_start_dodge()
	else:
		_start_attack(combo.next_attack(action, sheathed))
	return true


func _start_attack(attack: AttackData) -> void:
	katana.set_active(false)                     # close the previous strike's window, if any
	holster.draw()
	var motion := warping.plan(attack)
	body.begin_attack(motion.direction, motion.speed, motion.duration, motion.delay)
	warping.notify_started(motion.target, motion.delay + motion.duration)
	katana.begin_swing(attack)
	current_attack = attack
	_time_since_attack = 0.0
	_change_state(State.ATTACK, attack.animation)
	attack_started.emit(attack)


func _start_dodge() -> void:
	katana.set_active(false)
	combo.reset()
	var target: Node3D = targeting.get(&"current_target") if targeting else null
	var input := body.get_move_direction()
	var direction := input
	var clip := &"dodge_f"
	if is_instance_valid(target):
		# Strafing: keep facing the target and dash relative to it.
		var to_target := target.global_position - body.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			body.face(to_target.normalized())
		if direction == Vector3.ZERO:
			direction = -body.get_facing()
		clip = dodge_clip(body.get_facing(), direction)
		body.begin_dodge(direction, dodge_distance / dodge_move_time, dodge_move_time, false)
	elif direction == Vector3.ZERO:
		direction = -body.get_facing()               # no input: backstep
		clip = &"dodge_b"
		body.begin_dodge(direction, dodge_distance / dodge_move_time, dodge_move_time, false)
	else:
		body.begin_dodge(direction, dodge_distance / dodge_move_time, dodge_move_time, true)
	current_attack = null
	_iframes_granted = false
	_change_state(State.DODGE, clip)
	dodge_started.emit(direction)


## The directional dodge clip for dashing along `direction` while facing `facing`.
static func dodge_clip(facing: Vector3, direction: Vector3) -> StringName:
	var forward := facing.dot(direction)
	var right := facing.cross(Vector3.UP).dot(direction)
	if absf(forward) >= absf(right):
		return &"dodge_f" if forward >= 0.0 else &"dodge_b"
	return &"dodge_r" if right > 0.0 else &"dodge_l"


func _on_damaged(hit: HitInfo) -> void:
	if health.is_dead:
		return                                   # _on_died handles lethal hits
	katana.set_active(false)                     # a hit cancels the swing
	combo.clear_buffer()
	combo.reset()
	current_attack = null
	body.lock_controls(true)
	body.apply_knockback(hit.knockback)
	_hurt_duration = maxf(hit.stagger_time, min_hurt_time)
	_change_state(State.HURT, &"hurt")


func _on_died(_hit: HitInfo) -> void:
	katana.set_active(false)
	combo.clear_buffer()
	combo.reset()
	current_attack = null
	body.lock_controls(true)
	_change_state(State.DEAD, &"death")
	await get_tree().create_timer(respawn_delay).timeout
	health.revive()
	body.respawn()
	_time_since_attack = 0.0
	_change_state(State.IDLE, &"idle")


func _enter_locomotion() -> void:
	current_attack = null
	var next := _locomotion_state()
	_change_state(next, &"run" if next == State.RUN else &"idle")


func _locomotion_state() -> State:
	return State.RUN if body.get_planar_speed() > run_threshold else State.IDLE


func _change_state(next: State, clip: StringName) -> void:
	var previous := state
	state = next
	_state_time = 0.0
	# Replaying the clip already playing (a dodge right after a dodge) must restart it.
	if _playback.get_current_node() == clip and (next == State.ATTACK or next == State.DODGE):
		_playback.start(clip, true)
	else:
		_playback.travel(clip)
	if previous != next:
		state_changed.emit(previous, next)
