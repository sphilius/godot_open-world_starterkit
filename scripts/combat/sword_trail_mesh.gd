class_name SwordTrailMesh
extends MeshInstance3D
## CPU-built ribbon trail. While emitting, it samples the blade's base and tip every physics
## tick and stitches the samples into a fading triangle strip (world space).
##
## It's the renderer Katana picks for Intel integrated GPUs. In testing (UHD G1, driver
## 31.0.101.2135), GPUParticles3D trails lost the Vulkan device, and on D3D12 they didn't render.
## It also stays smooth at low frame rates, because samples follow the physics tick rather
## than the render rate. Hit-stop freezes it with the world.

@export var base_marker: Node3D
@export var tip_marker: Node3D
## Seconds each sample stays visible (the ribbon's length in time).
@export var sample_lifetime := 0.14
@export var trail_color := Color(1.0, 0.8, 0.55)

var emitting := false
var _bases := PackedVector3Array()     # newest first
var _tips := PackedVector3Array()
var _ages := PackedFloat32Array()
var _immediate := ImmediateMesh.new()


func _ready() -> void:
	top_level = true                      # vertices are written in world space
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _immediate


func _physics_process(delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[_ages.size() - 1] > sample_lifetime:
		_bases.remove_at(_bases.size() - 1)
		_tips.remove_at(_tips.size() - 1)
		_ages.remove_at(_ages.size() - 1)
	if emitting:
		_bases.insert(0, base_marker.global_position)
		_tips.insert(0, tip_marker.global_position)
		_ages.insert(0, 0.0)
	_rebuild()


func _rebuild() -> void:
	_immediate.clear_surfaces()
	if _ages.size() < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _ages.size():
		var age := _ages[i] / sample_lifetime
		var color := Color(trail_color, 1.0 - age)
		_immediate.surface_set_color(color)
		_immediate.surface_set_uv(Vector2(0.0, age))
		_immediate.surface_add_vertex(_bases[i])
		_immediate.surface_set_color(color)
		_immediate.surface_set_uv(Vector2(1.0, age))
		_immediate.surface_add_vertex(_tips[i])
	_immediate.surface_end()
