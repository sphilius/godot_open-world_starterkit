class_name Gatekeeper
extends EnemyCombatController
## Sanctum Gatekeeper: a two-phase Brute.
##
## Phase 2 starts once health falls to `phase_two_ratio`: a roar (invulnerable for
## `roar_time`, `roared` asks for camera trauma), recovery 20 % faster, the red unblockable
## combo joins its attacks, and its posture regenerates twice as fast. A posture break makes
## it executable like any enemy; its execution deals `execution_damage_ratio` (40 %) of max
## health. Engaging it shows its health and posture bar at the top of the HUD (group
## "boss_hud": set_boss()).

signal phase_changed(phase: int)
## Camera shake request for the roar (CameraTrauma, M9).
signal roared(trauma: float)

@export var boss_name := "Sanctum Gatekeeper"
@export_range(0.0, 1.0) var phase_two_ratio := 0.5
@export var phase_two_combos: Array[EnemyCombo] = []
@export var roar_time := 1.2
@export var roar_trauma := 0.45

var phase := 1


func _ready() -> void:
	super()
	health.health_changed.connect(_on_health_changed)


func reset_to_spawn() -> void:
	if phase == 2:
		for combo in phase_two_combos:
			combos.erase(combo)
		recovery_scale /= 0.8
		attack_cooldown /= 0.8
		posture.recovery_rate /= 2.0
		phase = 1
	super()


func _on_engaged() -> void:
	get_tree().call_group(&"boss_hud", &"set_boss", self)


func _on_health_changed(current: float, maximum: float) -> void:
	if phase == 1 and not health.is_dead and current <= maximum * phase_two_ratio:
		_enter_phase_two()


func _enter_phase_two() -> void:
	phase = 2
	combos.append_array(phase_two_combos)
	recovery_scale *= 0.8
	attack_cooldown *= 0.8
	posture.recovery_rate *= 2.0
	health.grant_invulnerability(roar_time)
	reaction.react(&"roar", roar_time)                  # a stagger-like beat: no attacks, roar clip
	phase_changed.emit(2)
	roared.emit(roar_trauma)
