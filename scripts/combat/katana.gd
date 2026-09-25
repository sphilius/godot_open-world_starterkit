class_name Katana
extends Node3D
## Katana with an Area3D hitbox and a GPUParticles3D ribbon trail.
##
## CombatStateMachine opens and closes the active window. While it is open, `area_entered`
## (enemy Hurtboxes) and `body_entered` (enemy bodies) resolve the target's HealthComponent.
## Each target is hit at most once per swing, even when both its hurtbox and body overlap.
## A landed hit applies damage, knockback and stagger, and triggers hit-stop.

signal hit_landed(target: HealthComponent, attack: AttackData)

enum TrailRenderer {
	## GPU particles, except on Intel integrated GPUs, which get MESH (see SwordTrailMesh).
	AUTO,
	## GPUParticles3D ribbon: one particle glued to the blade, RibbonTrailMesh skinned along its path.
	GPU_PARTICLES,
	## CPU-built ImmediateMesh ribbon from blade base and tip samples.
	MESH,
}

@export var trail_renderer := TrailRenderer.AUTO
## Extra particle lifetime after the active window, so the ribbon fades rather than popping.
@export var trail_fade_time := 0.12

@onready var hitbox: Area3D = $Hitbox
@onready var _gpu_trail: GPUParticles3D = $Trail
@onready var _mesh_trail: SwordTrailMesh = $MeshTrail

## Set by the combat FSM: the attacker (for knockback direction and self-hit filtering).
var wielder: Node3D
var _attack: AttackData
var _active := false
var _hit_this_swing := {}   # HealthComponent -> true


func _ready() -> void:
	hitbox.monitoring = false
	hitbox.area_entered.connect(_on_struck)
	hitbox.body_entered.connect(_on_struck)
	# Keep only the chosen renderer. The scene ships with particle trails off, keeping the editor
	# safe on the affected Vulkan drivers; they're switched on here when chosen.
	if resolve_trail_renderer() == TrailRenderer.MESH:
		_gpu_trail.queue_free()
		_gpu_trail = null
	else:
		_gpu_trail.trail_enabled = true
		_mesh_trail.queue_free()
		_mesh_trail = null


func resolve_trail_renderer() -> TrailRenderer:
	if trail_renderer != TrailRenderer.AUTO:
		return trail_renderer
	return TrailRenderer.MESH if GpuInfo.is_intel_integrated() else TrailRenderer.GPU_PARTICLES


## Arms the blade for a new strike (clears the one-hit-per-target memory).
func begin_swing(attack: AttackData) -> void:
	_attack = attack
	_hit_this_swing.clear()


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	hitbox.set_deferred(&"monitoring", on)   # overlaps already present report on the next physics step
	if _mesh_trail:
		_mesh_trail.emitting = on
	elif _gpu_trail and on and _attack:
		_gpu_trail.lifetime = maxf(_attack.active_end - _attack.active_start, 0.05) + trail_fade_time
		_gpu_trail.restart()                  # one-shot: emits for the active window, then fades


func _on_struck(node: Node3D) -> void:
	if not _active or _attack == null:
		return
	var health := HealthComponent.resolve(node)
	if health == null or health.is_dead or _hit_this_swing.has(health):
		return
	if wielder and health.get_parent() == wielder:
		return
	_hit_this_swing[health] = true

	var push := Vector3.ZERO
	if wielder:
		push = node.global_position - wielder.global_position
		push.y = 0.0
		push = push.normalized()
	var hit := HitInfo.new(_attack.damage, wielder, push * _attack.knockback, _attack.stagger_time)
	if health.take_damage(hit):
		HitStop.trigger(_attack.hitstop)
		hit_landed.emit(health, _attack)
