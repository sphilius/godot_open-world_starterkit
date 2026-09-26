class_name HitVfx
extends Node3D
## One-shot hit effects (M9b), built in code so they need no textures: a burst of glowing
## spark streaks (CPUParticles3D, so it also runs on the web renderer) and, for the big moments,
## a short light pop. spawn() picks the look for a HitInfo.Result; the node frees itself.
##
##   HIT        warm sparks          KILLED        more, bigger sparks
##   BLOCKED    pale yellow sparks   GUARD_BROKEN  a wide orange burst and a light pop
##   PARRIED    blue-white sparks and a bright flash
##   posture break (a HIT that broke it): the orange burst on top of the hit sparks

const WARM := Color(1.0, 0.55, 0.2)
const PALE := Color(1.0, 0.9, 0.55)
const STEEL := Color(0.75, 0.88, 1.0)
const BREAK := Color(1.0, 0.4, 0.12)

## Every live effect (tests count them).
static var live := 0

var _lifetime := 0.5


## Spawns the effect for `result` at `at` under `parent`. Returns it (null for IGNORED).
static func spawn(parent: Node, at: Vector3, result: HitInfo.Result, broke_posture := false) -> HitVfx:
	var vfx := HitVfx.new()
	match result:
		HitInfo.Result.HIT:
			vfx._sparks(WARM, 14, 5.0)
		HitInfo.Result.KILLED:
			vfx._sparks(WARM, 26, 7.0)
		HitInfo.Result.BLOCKED:
			vfx._sparks(PALE, 12, 4.0)
		HitInfo.Result.PARRIED:
			vfx._sparks(STEEL, 30, 8.5)
			vfx._flash(STEEL, 6.0, 5.0)
		HitInfo.Result.GUARD_BROKEN:
			vfx._sparks(BREAK, 36, 6.0)
			vfx._flash(BREAK, 4.0, 6.0)
		_:
			vfx.free()
			return null
	if broke_posture and result == HitInfo.Result.HIT:
		vfx._sparks(BREAK, 30, 6.0)
		vfx._flash(BREAK, 4.0, 6.0)
	parent.add_child(vfx)
	vfx.global_position = at
	return vfx


func _enter_tree() -> void:
	live += 1


func _exit_tree() -> void:
	live -= 1


func _ready() -> void:
	get_tree().create_timer(_lifetime, false).timeout.connect(queue_free)


func _sparks(color: Color, amount: int, speed: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.16, 0.018)
	mesh.material = material
	var sparks := CPUParticles3D.new()
	sparks.mesh = mesh
	sparks.amount = amount
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = 0.35
	sparks.local_coords = false
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = speed * 0.4
	sparks.initial_velocity_max = speed
	sparks.gravity = Vector3(0, -12, 0)
	sparks.damping_min = 2.0
	sparks.damping_max = 4.0
	sparks.particle_flag_align_y = true                  # streaks point along their flight
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 1.0) * Color(1.6, 1.6, 1.6, 1.0))
	fade.set_color(1, Color(color, 0.0))
	sparks.color_ramp = fade
	sparks.emitting = true
	add_child(sparks)
	_lifetime = maxf(_lifetime, sparks.lifetime + 0.1)


func _flash(color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	add_child(light)
	light.create_tween().tween_property(light, ^"light_energy", 0.0, 0.18)
