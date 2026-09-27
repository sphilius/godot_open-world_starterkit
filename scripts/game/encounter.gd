class_name Encounter
extends Node3D
## A fight in a closed arena (courtyard ambush, sanctum boss).
##
## IDLE    : waiting. The player entering `trigger` starts it.
## ACTIVE  : the `entry_gates` close behind the player and the waves spawn one after another at
##           the SpawnPoints markers (each wave once the previous one is dead, `wave_delay`
##           seconds later). Every enemy is wired to this encounter's CombatDirector.
## CLEARED : the last wave fell: `exit_gates` open, `cleared` fires. It stays cleared.
## reset() (the player died mid-fight, or GameManager's encounter reset in M9) despawns every
## enemy and goes back to IDLE with the gates as they started.

signal started
signal wave_started(index: int)
signal cleared
signal was_reset

enum State { IDLE, ACTIVE, CLEARED }

@export var waves: Array[EncounterWave] = []
@export var trigger: Area3D
## Close when the fight starts; reopen on reset (and on clear).
@export var entry_gates: Array[LevelGate] = []
## Open once it's cleared.
@export var exit_gates: Array[LevelGate] = []
## Seconds between one wave dying and the next arriving.
@export var wave_delay := 1.5
## Director tokens for this fight (runbook: 2 in the courtyard).
@export var max_attack_tokens := 2
## Spawned enemies aggro across the whole arena.
@export var enemy_aggro_radius := 40.0

var state := State.IDLE
var wave_index := -1
var director: CombatDirector
var _alive: Array[Node] = []
var _spawn_points: Array[Node3D] = []
var _generation := 0                                  # bumps on reset: cancels pending waves
var _player_health: HealthComponent


func _ready() -> void:
	director = CombatDirector.new()
	director.name = "Director"
	director.max_attack_tokens = max_attack_tokens
	add_child(director)
	var points := get_node_or_null(^"SpawnPoints")
	if points:
		for point in points.get_children():
			if point is Node3D:
				_spawn_points.append(point)
	if trigger:
		trigger.body_entered.connect(_on_trigger_body_entered)
	for gate in exit_gates:
		gate.close(true)


## Starts the fight (the trigger calls this when the player walks in).
func start(player: Node3D = null) -> void:
	if state != State.IDLE:
		return
	state = State.ACTIVE
	for gate in entry_gates:
		gate.close()
	if player:
		_player_health = HealthComponent.resolve(player)
		if _player_health and not _player_health.died.is_connected(_on_player_died):
			_player_health.died.connect(_on_player_died)
	started.emit()
	_spawn_wave(0)


## Despawns everything and waits for the player again; gates go back to how they started.
func reset() -> void:
	_generation += 1
	for enemy in _alive.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	_alive.clear()
	state = State.IDLE
	wave_index = -1
	for gate in entry_gates:
		gate.open()
	for gate in exit_gates:
		gate.close()
	was_reset.emit()


func alive_enemies() -> Array[Node]:
	return _alive.filter(func(enemy: Node) -> bool: return is_instance_valid(enemy))


func _spawn_wave(index: int) -> void:
	wave_index = index
	var wave := waves[index]
	for i in wave.enemies.size():
		var enemy: Node3D = wave.enemies[i].instantiate()
		if enemy is EnemyCombatController:
			(enemy as EnemyCombatController).director = director
			(enemy as EnemyCombatController).aggro_radius = enemy_aggro_radius
		var point := _spawn_points[i % _spawn_points.size()] if not _spawn_points.is_empty() else self
		var jitter := Vector3((i / maxi(_spawn_points.size(), 1)) * 1.2, 0.0, 0.0)
		add_child(enemy)
		enemy.global_position = point.global_position + jitter
		enemy.global_rotation.y = point.global_rotation.y
		_alive.append(enemy)
		if enemy.has_signal(&"defeated"):
			enemy.connect(&"defeated", _on_enemy_gone.bind(enemy), CONNECT_ONE_SHOT)
		enemy.tree_exited.connect(_on_enemy_gone.bind(enemy), CONNECT_ONE_SHOT)
	wave_started.emit(index)


func _on_enemy_gone(enemy: Node) -> void:
	if not _alive.has(enemy):
		return
	if not is_inside_tree():
		return                                           # the whole level is unloading, not a kill
	_alive.erase(enemy)
	if state != State.ACTIVE or not _alive.is_empty():
		return
	if wave_index + 1 >= waves.size():
		_clear()
		return
	var generation := _generation
	var next := wave_index + 1
	get_tree().create_timer(wave_delay, false).timeout.connect(func() -> void:
		if generation == _generation and state == State.ACTIVE:
			_spawn_wave(next))


func _clear() -> void:
	state = State.CLEARED
	for gate in entry_gates:
		gate.open()
	for gate in exit_gates:
		gate.open()
	cleared.emit()


func _on_trigger_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		start(body)


func _on_player_died(_hit: HitInfo) -> void:
	if state == State.ACTIVE:
		reset.call_deferred()
