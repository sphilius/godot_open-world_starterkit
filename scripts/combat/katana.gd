class_name Katana
extends Node3D
## Katana: a Hitbox (Area3D) riding the weapon-bone socket, plus a ribbon trail.
##
## CombatStateMachine arms each strike (begin_swing) and opens or closes its active window
## (set_active). Hit resolution, damage and hit-stop live in the shared Hitbox component.

enum TrailRenderer {
	## GPU particles, except on Intel iGPUs and the Compatibility (web) renderer, which get MESH.
	AUTO,
	## GPUParticles3D ribbon: one particle glued to the blade, RibbonTrailMesh skinned along its path.
	GPU_PARTICLES,
	## CPU-built ImmediateMesh ribbon from blade base and tip samples.
	MESH,
}

@export var trail_renderer := TrailRenderer.AUTO
## Extra particle lifetime after the active window, so the ribbon fades rather than popping.
@export var trail_fade_time := 0.12

@onready var hitbox: Hitbox = $Hitbox
@onready var _gpu_trail: GPUParticles3D = $Trail
@onready var _mesh_trail: SwordTrailMesh = $MeshTrail

var _attack: AttackData


func _ready() -> void:
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
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	return TrailRenderer.MESH if compatibility or GpuInfo.is_intel_integrated() else TrailRenderer.GPU_PARTICLES


## Arms the blade for a new strike.
func begin_swing(attack: AttackData) -> void:
	_attack = attack
	hitbox.begin(attack)


func set_active(on: bool) -> void:
	if on == hitbox.is_active():
		return
	hitbox.set_active(on)
	if _mesh_trail:
		_mesh_trail.emitting = on
	elif _gpu_trail and on and _attack:
		_gpu_trail.lifetime = maxf(_attack.active_end - _attack.active_start, 0.05) + trail_fade_time
		_gpu_trail.restart()                  # one-shot: emits for the active window, then fades
