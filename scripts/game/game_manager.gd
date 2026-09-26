class_name GameManager
extends Node
## The slice's game loop (M9): state flow, checkpoints, death slow motion, per-beat lighting
## (D9), the sanctum lock, and the run's stats. One node in main.tscn (group "game_manager"),
## not an autoload, so a scene reload or a test's fresh world always starts from scratch.
##
## START_MENU         : the world is paused behind the title (GameMenus). begin_play() starts.
## EXPLORATION        : the approach path and the breather between fights.
## COURTYARD_AMBUSH   : while the courtyard Encounter is active.
## SANCTUM_GATEKEEPER : while the sanctum Encounter is active.
## VICTORY_SCREEN     : `victory_delay` seconds after the Gatekeeper falls; the world pauses
##                      and GameMenus shows the stats.
##
## Lighting only moves forward: golden hour → dusk once the courtyard fight starts → night
## once the sanctum fight starts (beat_lighting[0..2]), blended over `beat_blend_time`.
## Dying: the world slows to `death_slow_motion_scale` for `death_slow_motion_time` real
## seconds (TimeScale request &"death"), the encounter resets itself, and the player respawns
## at the last lit CheckpointShrine (CombatStateMachine's respawn timer).

signal state_changed(previous: GameState, current: GameState)
signal checkpoint_reached(shrine: CheckpointShrine)
signal victory

enum GameState { START_MENU, EXPLORATION, COURTYARD_AMBUSH, SANCTUM_GATEKEEPER, VICTORY_SCREEN }

## Tests set this (so does `--skip-menu` on the command line): the world starts playable.
static var skip_start_menu := false

@export var player: PlayerController
@export var combat: CombatStateMachine
@export var courtyard: Encounter
@export var sanctum: Encounter
## Closed until the courtyard is cleared (the sanctum can't be reached around the ambush).
@export var sanctum_locks: Array[LevelGate] = []
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Golden hour, dusk, night.
@export var beat_lighting: Array[BeatLighting] = []
@export var beat_blend_time := 4.0
@export_range(0.05, 1.0) var death_slow_motion_scale := 0.3
## Real seconds.
@export var death_slow_motion_time := 1.2
## Seconds between the Gatekeeper's death and the victory screen.
@export var victory_delay := 3.0

var state := GameState.START_MENU
## Index into beat_lighting of the look the world has blended (or is blending) to.
var beat := 0
var checkpoint: CheckpointShrine
var deaths := 0
var parries := 0
## Seconds of play (real time, excluding the menus and pauses).
var play_time := 0.0
var _counting := false
var _last_tick_msec := 0
var _blend: Tween


func _ready() -> void:
	add_to_group(&"game_manager")
	if world_environment and world_environment.environment:
		# The tweens must not write into the shared .tres (a reload would start at night).
		var environment := world_environment.environment.duplicate(true) as Environment
		if environment.sky and environment.sky.sky_material:
			environment.sky.sky_material = environment.sky.sky_material.duplicate()
		world_environment.environment = environment
	if player:
		var health := HealthComponent.resolve(player)
		if health:
			health.died.connect(_on_player_died)
	if combat and combat.parry:
		combat.parry.parry_successful.connect(func(_attacker: Node3D, _point: Vector3) -> void: parries += 1)
	if courtyard:
		courtyard.started.connect(_set_state.bind(GameState.COURTYARD_AMBUSH))
		courtyard.was_reset.connect(_on_encounter_reset.bind(GameState.COURTYARD_AMBUSH))
		courtyard.cleared.connect(_on_courtyard_cleared)
	if sanctum:
		sanctum.started.connect(_set_state.bind(GameState.SANCTUM_GATEKEEPER))
		sanctum.was_reset.connect(_on_encounter_reset.bind(GameState.SANCTUM_GATEKEEPER))
		sanctum.cleared.connect(_on_sanctum_cleared)
	for gate in sanctum_locks:
		gate.close(true)
	for shrine in get_tree().get_nodes_in_group(&"checkpoint_shrine"):
		(shrine as CheckpointShrine).rested.connect(set_checkpoint.bind(shrine))
	if skip_start_menu or "--skip-menu" in OS.get_cmdline_user_args():
		begin_play()
	else:
		get_tree().paused = true


## The GameManager in `tree`'s current scene, or null.
static func find(tree: SceneTree) -> GameManager:
	return tree.get_first_node_in_group(&"game_manager") as GameManager if tree else null


## Leaves the title: unpauses and hands control to the player.
func begin_play() -> void:
	if state != GameState.START_MENU:
		return
	get_tree().paused = false
	_counting = true
	_last_tick_msec = Time.get_ticks_msec()
	_set_state(GameState.EXPLORATION)
	if player:
		player.capture_mouse()


## Makes `shrine` the respawn point (`checkpoint_reached` only when it changes).
func set_checkpoint(shrine: CheckpointShrine) -> void:
	if player:
		player.set_respawn_point(shrine.respawn_position(), shrine.respawn_yaw())
	if shrine == checkpoint:
		return
	checkpoint = shrine
	checkpoint_reached.emit(shrine)


## Pause menu's "Return to shrine": abandons the current fight and respawns at the checkpoint.
## Does nothing while the player is dead (the respawn is already on its way).
func return_to_checkpoint() -> void:
	var health := HealthComponent.resolve(player) if player else null
	if health and health.is_dead:
		return
	for encounter in [courtyard, sanctum]:
		if encounter and encounter.state == Encounter.State.ACTIVE:
			encounter.reset()
	if player:
		player.respawn()


## Back to the title with a fresh world.
func return_to_title() -> void:
	TimeScale.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


## The run so far: seconds played, successful parries and deaths.
func stats() -> Dictionary:
	return {&"time": play_time, &"parries": parries, &"deaths": deaths}


## True while the player is in control (not on the title or victory screen).
func is_playing() -> bool:
	return state != GameState.START_MENU and state != GameState.VICTORY_SCREEN


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _counting:
		# Real time, so hit-stop and slow motion don't stretch the clock. A pause stops
		# _process and unpausing resets the baseline; the clamp only guards long frames.
		play_time += minf((now - _last_tick_msec) / 1000.0, 0.25)
	_last_tick_msec = now


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_tick_msec = Time.get_ticks_msec()    # the pause itself never counts


func _exit_tree() -> void:
	TimeScale.pop(&"death")


func _set_state(next: GameState) -> void:
	var previous := state
	if next == previous:
		return
	state = next
	var next_beat := beat
	match next:
		GameState.COURTYARD_AMBUSH:
			next_beat = maxi(beat, 1)
		GameState.SANCTUM_GATEKEEPER:
			next_beat = maxi(beat, 2)
	if next_beat != beat:
		beat = next_beat
		_blend_to(beat)
	state_changed.emit(previous, next)


func _blend_to(index: int) -> void:
	if index >= beat_lighting.size() or beat_lighting[index] == null:
		return
	var environment := world_environment.environment if world_environment else null
	var from := BeatLighting.capture(environment, sun)
	var to := beat_lighting[index]
	if _blend and _blend.is_valid():
		_blend.kill()
	_blend = create_tween()
	_blend.tween_method(func(weight: float) -> void:
		BeatLighting.apply_blend(from, to, weight, environment, sun), 0.0, 1.0, beat_blend_time)


func _on_encounter_reset(fight: GameState) -> void:
	if state == fight:
		_set_state(GameState.EXPLORATION)


func _on_courtyard_cleared() -> void:
	for gate in sanctum_locks:
		gate.open()
	_set_state(GameState.EXPLORATION)


func _on_sanctum_cleared() -> void:
	_counting = false
	await get_tree().create_timer(victory_delay, false).timeout
	if not is_inside_tree():
		return
	_set_state(GameState.VICTORY_SCREEN)
	get_tree().paused = true
	victory.emit()


func _on_player_died(_hit: HitInfo) -> void:
	deaths += 1
	TimeScale.push(&"death", death_slow_motion_scale)
	get_tree().create_timer(death_slow_motion_time, true, false, true).timeout.connect(
		func() -> void: TimeScale.pop(&"death"))
