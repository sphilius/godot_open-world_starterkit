class_name CheckpointShrine
extends Area3D
## A checkpoint (M9). Walking up to it lights it: the player is healed to full, their posture
## resets, and GameManager makes its RespawnPoint the place they come back to after dying.
## Every visit heals and emits `rested` (GameManager saves it as the checkpoint again, so going
## back to an earlier shrine moves the respawn back there); only the first visit lights the
## flame and emits `activated`.
## The lantern is the stone_lantern placeholder until the M2 shrine model
## (`checkpoint_shrine.glb` with `Marker3D_FlamePoint`) lands.

signal activated
signal rested

## Light energy of the flame once lit (unlit: 0).
@export var lit_energy := 3.0
@export var ignite_time := 0.8

var is_lit := false

@onready var _flame: OmniLight3D = $Flame
@onready var _respawn_point: Marker3D = $RespawnPoint


func _ready() -> void:
	add_to_group(&"checkpoint_shrine")
	collision_layer = 0
	collision_mask = 2                    # the player's body layer
	monitorable = false
	_flame.light_energy = 0.0
	body_entered.connect(_on_body_entered)


## Where the player reappears (on the ground in front of the shrine).
func respawn_position() -> Vector3:
	return _respawn_point.global_position + Vector3.UP * 0.1


## The yaw the player faces on respawn (PlayerController.spawn_at: 0 faces -Z).
func respawn_yaw() -> float:
	var forward := -_respawn_point.global_basis.z
	return atan2(-forward.x, -forward.z)


## Heals whoever rests here; lights the shrine the first time.
func rest(body: Node3D) -> void:
	var health := HealthComponent.resolve(body)
	if health and not health.is_dead:
		health.heal(health.max_health)
	var posture := PostureComponent.find_on(body)
	if posture:
		posture.reset()
	if not is_lit:
		is_lit = true
		create_tween().tween_property(_flame, ^"light_energy", lit_energy, ignite_time)
		activated.emit()
	rested.emit()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		rest(body)
