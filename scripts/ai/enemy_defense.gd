class_name EnemyDefense
extends Node
## Enemy defence (Phase B, playtest 1): the enemy reads the player's strikes and defends.
##
## When the player starts a strike (CombatStateMachine.attack_started) within `defend_range`
## in front of a free enemy (idle, approaching, flanking or recovering, and off `cooldown`), it
## rolls once, after a human `reaction_time`:
##   `dodge_chance` → EVADE: a quick backstep with i-frames (EnemyCombatController.start_evade)
##   `block_chance` → GUARD: holds the guard (GuardComponent) for `guard_hold` seconds, longer
##                    while hits keep coming; after `counter_after_blocks` blocked hits it
##                    counter-attacks at once
## When the player's blade opens (the katana hitbox's swing_started), elites and bosses may also:
##   `parry_chance`         → if guarding, open a parry window (ParrySystem): the player is
##                            parried and the enemy counter-attacks
##   `perfect_dodge_chance` → evade on the very frame: the player staggers (&"evaded") and the
##                            enemy counter-attacks
## Seeded from `rng`, so tests can pin the rolls (or set the chances to 0 or 1).

@export var enemy: EnemyCombatController
@export var guard: GuardComponent
## Optional (elites and bosses): parries while guarding.
@export var parry: ParrySystem
@export_range(0.0, 1.0) var block_chance := 0.35
@export_range(0.0, 1.0) var dodge_chance := 0.2
@export_range(0.0, 1.0) var parry_chance := 0.0
@export_range(0.0, 1.0) var perfect_dodge_chance := 0.0
## Seconds between the player's strike starting and the enemy reacting (random in range).
@export var reaction_time := Vector2(0.12, 0.25)
## Only strikes started this close (m), in front of the enemy, draw a reaction.
@export var defend_range := 3.6
@export_range(0.0, 180.0) var defend_arc_degrees := 120.0
## Seconds the guard stays up after the last reason to hold it.
@export var guard_hold := 0.9
## Blocked hits before a counter-attack.
@export var counter_after_blocks := 2
## Seconds after a defence ends before the next one.
@export var cooldown := 0.8

var rng := RandomNumberGenerator.new()
var _player_combat: CombatStateMachine
var _pending := &""                             # &"guard" or &"evade", waiting on the reaction time
var _pending_left := 0.0
var _cooldown_left := 0.0
var _blocks := 0


func _ready() -> void:
	rng.randomize()
	if enemy == null:
		enemy = get_parent() as EnemyCombatController
	if guard:
		guard.blocked.connect(_on_blocked)
	if parry:
		parry.parry_successful.connect(func(_attacker: Node3D, _point: Vector3) -> void: _counter())


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _player_combat == null or not is_instance_valid(_player_combat):
		_bind(CombatStateMachine.find_on(enemy.target) if enemy and is_instance_valid(enemy.target) else null)
	if _pending != &"":
		_pending_left -= delta
		if _pending_left <= 0.0:
			var action := _pending
			_pending = &""
			if enemy.can_defend():
				if action == &"evade":
					enemy.start_evade(false)
				else:
					_blocks = 0
					enemy.start_guard(guard_hold)
				_cooldown_left = cooldown


## True while a defence is waiting on its reaction time.
func is_pending() -> bool:
	return _pending != &""


func _bind(combat: CombatStateMachine) -> void:
	if combat == null:
		return
	_player_combat = combat
	combat.attack_started.connect(_on_player_attack_started)
	combat.katana.hitbox.swing_started.connect(_on_player_blade_open)


func _on_player_attack_started(_attack: AttackData) -> void:
	if _pending != &"" or _cooldown_left > 0.0 or not enemy.can_defend() or not _threatened():
		return
	var roll := rng.randf()
	if roll < dodge_chance:
		_pending = &"evade"
	elif roll < dodge_chance + block_chance:
		_pending = &"guard"
	else:
		return
	_pending_left = rng.randf_range(reaction_time.x, reaction_time.y)


func _on_player_blade_open(_attack: AttackData) -> void:
	if not _threatened():
		return
	if enemy.state == EnemyCombatController.State.GUARD:
		enemy.extend_guard(guard_hold)
		if parry and rng.randf() < parry_chance:
			parry.on_guard_pressed()
		return
	if enemy.can_defend() and rng.randf() < perfect_dodge_chance:
		_pending = &""
		enemy.start_evade(true)
		var player_reaction := DamageReactionComponent.find_on(_player_combat.body)
		if player_reaction:
			player_reaction.play_evaded()
		_cooldown_left = cooldown


func _on_blocked(_hit: HitInfo) -> void:
	_blocks += 1
	if _blocks >= counter_after_blocks:
		_counter()
	else:
		enemy.extend_guard(guard_hold)


func _counter() -> void:
	_blocks = 0
	enemy.counter_attack()


## The player is close, in front, and alive.
func _threatened() -> bool:
	if enemy == null or _player_combat == null or not is_instance_valid(_player_combat.body):
		return false
	var to_player := _player_combat.body.global_position - enemy.global_position
	to_player.y = 0.0
	if to_player.length() > defend_range:
		return false
	var forward := -enemy.global_basis.z
	forward.y = 0.0
	return to_player.length() < 0.3 or forward.normalized().angle_to(to_player.normalized()) <= deg_to_rad(defend_arc_degrees * 0.5)
