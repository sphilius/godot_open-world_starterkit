class_name CombatStateMachine
extends Node
## Player combat FSM: IDLE, RUN, ATTACK, DODGE, GUARD, plus the HURT and DEAD reactions.
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
## • Guard (hold): walks slowly with the facing held, blocks frontal hits (GuardComponent),
##   and each press opens a parry window (ParrySystem). Guard can start from locomotion, from a
##   strike's recovery and from a dodge's recovery; strikes and dodges can leave it.
## • Execution: a light attack pressed while an enemy with a broken posture stands in front
##   (within `execute_range` and `execute_angle`, the lock-on target first) plays the
##   `execution` strike instead: invulnerable, no hitbox, and at its active frame the enemy's
##   execute() deals its execution damage.
## • Sheathing: after `sheathe_delay` seconds without attacking or guarding, the weapon is
##   sheathed.
## • Reactions come from DamageReactionComponent: a stagger cancels the swing or guard and plays
##   its clip (directional flinch, heavy, knockdown, guard break) in HURT until it ends. Dying
##   kneels, then respawns after `respawn_delay`.

signal state_changed(previous: State, current: State)
signal attack_started(attack: AttackData)
signal dodge_started(direction: Vector3)

enum State { IDLE, RUN, ATTACK, DODGE, HURT, DEAD, GUARD }

const LIGHT := ComboManager.LIGHT
const HEAVY := ComboManager.HEAVY
const DODGE := ComboManager.DODGE
const ALL_ACTIONS: Array[StringName] = [ComboManager.LIGHT, ComboManager.HEAVY, ComboManager.DODGE]
## DamageReactionComponent stagger type → clip.
const STAGGER_CLIPS := {
	&"front": &"hurt_f", &"back": &"hurt_b", &"left": &"hurt_l", &"right": &"hurt_r",
	&"heavy": &"hurt_heavy", &"parried": &"hurt_heavy", &"knockdown": &"knockdown",
	&"guard_break": &"guard_break",
}

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
@export var guard: GuardComponent
@export var parry: ParrySystem
@export var reaction: DamageReactionComponent
## Reset on respawn.
@export var posture: PostureComponent
## The deathblow strike (resources/combat/execution.tres).
@export var execution: AttackData
## Farthest an executable enemy can be (m), and widest angle off the facing.
@export var execute_range := 2.8
@export_range(0.0, 180.0) var execute_angle := 70.0
## Idle timer (s) before the weapon is sheathed.
@export var sheathe_delay := 3.0
## Horizontal speed (m/s) above which locomotion counts as RUN.
@export var run_threshold := 0.6
@export var respawn_delay := 2.5
## Walk speed multiplier while guarding.
@export var guard_move_scale := 0.45

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
var _iframes_granted := false
var _guard_held := false
var _parries := 0
var _execution_target: Node3D
var _executed := false


func _ready() -> void:
	_playback = animation_tree.get(&"parameters/playback")
	animation_tree.active = true
	katana.hitbox.source = body
	health.died.connect(_on_died)
	reaction.stagger_started.connect(_on_stagger_started)
	reaction.stagger_ended.connect(_on_stagger_ended)
	guard.blocked.connect(_on_blocked)
	parry.parry_successful.connect(_on_parried)
	_playback.travel(&"idle")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"guard"):
		guard_pressed()
		return
	if event.is_action_released(&"guard"):
		guard_released()
		return
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
		State.GUARD:
			_tick_guard()
		State.HURT:
			pass                                     # ends with reaction.stagger_ended
		State.DEAD:
			pass                                     # respawn is timer-driven (_on_died)
		_:
			_tick_locomotion(delta)


func is_attacking() -> bool:
	return state == State.ATTACK


## Guard pressed (held from now on). Opens a parry window and raises the guard if the current
## state allows it; otherwise the guard goes up as soon as it does, without a parry window.
func guard_pressed() -> void:
	_guard_held = true
	if _can_guard_now():
		parry.on_guard_pressed()
		_start_guard()


func guard_released() -> void:
	_guard_held = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_guard_held = false                      # the release may never arrive


func _can_guard_now() -> bool:
	match state:
		State.IDLE, State.RUN, State.GUARD:
			return true
		State.ATTACK:
			return _state_time >= current_attack.active_end
		State.DODGE:
			return _state_time >= dodge_cancel_time
	return false


func _tick_locomotion(delta: float) -> void:
	if _take_action(ALL_ACTIONS):
		return
	if _guard_held:
		_start_guard()
		return
	_time_since_attack += delta
	if _time_since_attack >= sheathe_delay and holster.is_drawn():
		holster.sheathe()
	var next := _locomotion_state()
	if next != state:
		_change_state(next, &"run" if next == State.RUN else &"idle")


func _tick_attack() -> void:
	var attack := current_attack
	if attack == execution:
		_tick_execution()
		return
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
	if _guard_held and _state_time >= attack.active_end:
		_start_guard()
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
	if _guard_held and _state_time >= dodge_cancel_time:
		_start_guard()
		return
	if _state_time >= dodge_duration:
		body.end_attack()
		_enter_locomotion()


func _tick_execution() -> void:
	if not _executed and _state_time >= execution.active_start:
		_executed = true
		if is_instance_valid(_execution_target) and _execution_target.call(&"execute", body):
			HitStop.trigger(execution.hitstop)
	if _state_time >= execution.duration:
		body.end_attack()
		combo.reset()
		_time_since_attack = 0.0
		_execution_target = null
		_enter_locomotion()


## The enemy a light attack would execute right now, or null: posture broken, in front and in
## reach. The lock-on target wins when it qualifies.
func execution_target() -> Node3D:
	if execution == null:
		return null
	var locked: Node3D = targeting.get(&"current_target") if targeting else null
	if _can_execute(locked):
		return locked
	var best: Node3D
	var best_distance := execute_range
	for enemy: Node3D in get_tree().get_nodes_in_group(&"enemies"):
		if _can_execute(enemy):
			var distance := (enemy.global_position - body.global_position).length()
			if distance <= best_distance:
				best = enemy
				best_distance = distance
	return best


func _can_execute(enemy: Node3D) -> bool:
	if not is_instance_valid(enemy) or not enemy.has_method(&"is_executable") or not enemy.call(&"is_executable"):
		return false
	var to_enemy := enemy.global_position - body.global_position
	to_enemy.y = 0.0
	if to_enemy.length() > execute_range:
		return false
	return to_enemy.length() < 0.3 or body.get_facing().angle_to(to_enemy.normalized()) <= deg_to_rad(execute_angle)


func _start_execution(enemy: Node3D) -> void:
	_end_guard()
	katana.set_active(false)
	holster.draw()
	combo.reset()
	var to_enemy := enemy.global_position - body.global_position
	to_enemy.y = 0.0
	var direction := to_enemy.normalized() if to_enemy.length() > 0.01 else body.get_facing()
	body.face(direction)
	var travel := maxf(to_enemy.length() - 1.3, 0.0)
	body.begin_attack(direction, travel / execution.lunge_duration if execution.lunge_duration > 0.0 else 0.0,
			execution.lunge_duration, execution.lunge_delay)
	health.grant_invulnerability(execution.duration)
	current_attack = execution
	_execution_target = enemy
	_executed = false
	_time_since_attack = 0.0
	_change_state(State.ATTACK, execution.animation)
	attack_started.emit(execution)


func _tick_guard() -> void:
	_time_since_attack = 0.0                     # the weapon stays out while guarding
	if not _guard_held:
		_end_guard()
		_enter_locomotion()
		return
	_take_action(ALL_ACTIONS)                    # strikes and dodges leave the guard


func _start_guard() -> void:
	katana.set_active(false)
	if state == State.ATTACK:
		combo.attack_finished()
	body.end_attack()                            # guarding walks
	holster.draw()
	guard.set_guarding(true)
	body.move_speed_scale = guard_move_scale
	body.hold_facing = true
	current_attack = null
	if state != State.GUARD:
		_change_state(State.GUARD, &"guard_idle")


func _end_guard() -> void:
	guard.set_guarding(false)
	body.move_speed_scale = 1.0
	body.hold_facing = false


## Starts the oldest buffered action if it's allowed now and leads somewhere. Returns true if
## something started.
func _take_action(allowed: Array[StringName]) -> bool:
	if LIGHT in allowed and combo.peek() == LIGHT:
		var victim := execution_target()
		if victim:
			combo.consume([LIGHT] as Array[StringName])
			_start_execution(victim)
			return true
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
	_end_guard()
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
	_end_guard()
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


## The clip for a DamageReactionComponent stagger type.
static func stagger_clip(type: StringName) -> StringName:
	return STAGGER_CLIPS.get(type, &"hurt_f")


func _on_stagger_started(type: StringName) -> void:
	if health.is_dead or state == State.DEAD:
		return                                   # _on_died handles lethal hits
	_end_guard()
	katana.set_active(false)                     # a stagger cancels the swing
	combo.clear_buffer()
	combo.reset()
	current_attack = null
	body.lock_controls(true)
	_change_state(State.HURT, stagger_clip(type))


func _on_stagger_ended() -> void:
	if state != State.HURT:
		return
	body.lock_controls(false)
	_enter_locomotion()


func _on_blocked(_hit: HitInfo) -> void:
	if state == State.GUARD:
		_replay(&"guard_hit")


func _on_parried(_attacker: Node3D, _point: Vector3) -> void:
	_parries += 1
	if state == State.GUARD:
		_replay(&"parry_1" if _parries % 2 == 1 else &"parry_2")


func _on_died(_hit: HitInfo) -> void:
	_end_guard()
	katana.set_active(false)
	combo.clear_buffer()
	combo.reset()
	current_attack = null
	body.lock_controls(true)
	_change_state(State.DEAD, &"death")
	reaction.clear()                             # after DEAD, so stagger_ended is a no-op
	await get_tree().create_timer(respawn_delay).timeout
	health.revive()
	posture.reset()
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
	if next == State.ATTACK or next == State.DODGE or next == State.HURT:
		_replay(clip)
	else:
		_playback.travel(clip)
	if previous != next:
		state_changed.emit(previous, next)


## Travels to `clip`, restarting it if it's already playing (a dodge right after a dodge, a
## second flinch, a block during the last block's clip).
func _replay(clip: StringName) -> void:
	if _playback.get_current_node() == clip:
		_playback.start(clip, true)
	else:
		_playback.travel(clip)
