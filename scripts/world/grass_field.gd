@tool
class_name GrassField
extends Node3D
## High-density wind grass built from MultiMeshInstance3D chunks.
##
## Blades are scattered across the HeightmapTerrain, skipping the gravel path, steep
## slopes and mountain tops. Chunking gives per-chunk frustum and distance culling.
## Blade order is random, so quality presets can thin the field uniformly by lowering
## visible_instance_count, with no rebuild. All motion (wind ripples and player push)
## lives in shaders/grass.gdshader.
## Keep this node unrotated and unscaled; it may be translated.

@export var terrain: HeightmapTerrain
@export var grass_material: ShaderMaterial

@export_group("Coverage")
## Metres, centred on this node.
@export var field_size := Vector2(150.0, 160.0)
@export_range(4.0, 64.0) var chunk_size := 16.0
@export_range(1.0, 60.0) var blades_per_square_metre := 12.0
## Lighter preview while editing, so opening the scene stays snappy.
@export_range(0.05, 1.0) var editor_density_scale := 0.25
## Ground steeper than this (normal.y below it, ~35°) stays bare.
@export_range(0.0, 1.0) var min_ground_normal_y := 0.82
@export var max_altitude := 14.0
@export var scatter_seed := 7

@export_group("Blades")
@export var blade_height_range := Vector2(0.45, 1.0)
@export var blade_base_width := 0.07
@export_range(2, 8) var blade_segments := 4
## Random lean in radians, so the field isn't a bed of vertical needles.
@export_range(0.0, 0.5) var max_lean := 0.18

@export_group("Distance")
@export var draw_distance := 60.0

@export_tool_button("Regenerate", "Reload") var regenerate_action: Callable = generate

const _FLOATS_PER_BLADE := 16   # 12 (Transform3D, row-major 3×4) + 4 (INSTANCE_CUSTOM)

var _chunks: Array[MultiMeshInstance3D] = []
var _density_scale := 1.0


func _ready() -> void:
	if terrain == null:
		push_warning("GrassField: assign a HeightmapTerrain.")
		return
	terrain.ensure_generated()
	generate()
	if not terrain.generated.is_connected(generate):
		terrain.generated.connect(generate)


func generate() -> void:
	for chunk in _chunks:
		if is_instance_valid(chunk):
			chunk.free()
	_chunks.clear()
	if terrain == null or grass_material == null:
		return

	var blade := _build_blade_mesh()
	var density := blades_per_square_metre * (editor_density_scale if Engine.is_editor_hint() else 1.0)
	var clump_noise := FastNoiseLite.new()
	clump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clump_noise.seed = scatter_seed
	clump_noise.frequency = 0.035

	var cols := ceili(field_size.x / chunk_size)
	var rows := ceili(field_size.y / chunk_size)
	var start := Vector2(global_position.x, global_position.z) - field_size * 0.5
	for cz in rows:
		for cx in cols:
			var chunk_min := start + Vector2(cx, cz) * chunk_size
			var chunk := _build_chunk(chunk_min, density, blade, clump_noise, hash([scatter_seed, cx, cz]))
			if chunk:
				chunk.name = "GrassChunk_%d_%d" % [cx, cz]
				_chunks.append(chunk)

	_apply_draw_distance()
	set_density_scale(_density_scale)


## Uniformly thin the field at runtime (quality presets). 1.0 = everything that was generated.
func set_density_scale(scale: float) -> void:
	_density_scale = clampf(scale, 0.0, 1.0)
	for chunk in _chunks:
		var mm := chunk.multimesh
		mm.visible_instance_count = -1 if _density_scale >= 0.999 else int(mm.instance_count * _density_scale)


func set_draw_distance(distance: float) -> void:
	draw_distance = distance
	_apply_draw_distance()


func _apply_draw_distance() -> void:
	# Shader shrinks blades between fade_start and fade_end; whole chunks cull just beyond.
	if grass_material and not Engine.is_editor_hint():   # don't dirty the .tres in the editor
		grass_material.set_shader_parameter(&"fade_start", draw_distance * 0.7)
		grass_material.set_shader_parameter(&"fade_end", draw_distance)
	for chunk in _chunks:
		chunk.visibility_range_end = draw_distance + chunk_size * 0.75


func _build_chunk(chunk_min: Vector2, density: float, blade: Mesh, clump_noise: FastNoiseLite, chunk_seed: int) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed
	var candidates := int(chunk_size * chunk_size * density)
	var centre := chunk_min + Vector2.ONE * (chunk_size * 0.5)
	var base_y := global_position.y
	var buffer := PackedFloat32Array()
	buffer.resize(candidates * _FLOATS_PER_BLADE)
	var count := 0

	for i in candidates:
		var wx := chunk_min.x + rng.randf() * chunk_size
		var wz := chunk_min.y + rng.randf() * chunk_size
		# Ragged edge along the gravel: acceptance falls off with the path mask.
		if terrain.path_mask_at(wx, wz) > rng.randf() * 0.35:
			continue
		if terrain.normal_at(wx, wz).y < min_ground_normal_y:
			continue
		var ground_y := terrain.height_at(wx, wz)
		if ground_y > max_altitude:
			continue

		# Clumps: low-frequency noise makes patches of taller grass.
		var clump := clump_noise.get_noise_2d(wx, wz) * 0.5 + 0.5
		var height := lerpf(blade_height_range.x, blade_height_range.y,
				clampf(clump * 0.75 + rng.randf() * 0.35, 0.0, 1.0))
		var width := rng.randf_range(0.8, 1.25)
		var lean_angle := rng.randf() * TAU
		var lean_axis := Vector3(cos(lean_angle), 0.0, sin(lean_angle))
		var basis := Basis(lean_axis, rng.randf() * max_lean) * Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis * Basis.from_scale(Vector3(width, height, width))
		var origin := Vector3(wx - centre.x, ground_y - base_y, wz - centre.y)

		var k := count * _FLOATS_PER_BLADE
		buffer[k] = basis.x.x
		buffer[k + 1] = basis.y.x
		buffer[k + 2] = basis.z.x
		buffer[k + 3] = origin.x
		buffer[k + 4] = basis.x.y
		buffer[k + 5] = basis.y.y
		buffer[k + 6] = basis.z.y
		buffer[k + 7] = origin.y
		buffer[k + 8] = basis.x.z
		buffer[k + 9] = basis.y.z
		buffer[k + 10] = basis.z.z
		buffer[k + 11] = origin.z
		buffer[k + 12] = rng.randf()   # dryness → tip colour
		buffer[k + 13] = rng.randf()   # flutter phase
		buffer[k + 14] = clump
		buffer[k + 15] = 0.0
		count += 1

	if count == 0:
		return null
	buffer.resize(count * _FLOATS_PER_BLADE)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true          # must be set before instance_count
	mm.mesh = blade
	mm.instance_count = count
	mm.buffer = buffer

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED   # keep ~200k blades out of the SDFGI volume
	mmi.extra_cull_margin = 1.5                          # wind and push displacement leave the static AABB
	mmi.position = Vector3(centre.x - global_position.x, 0.0, centre.y - global_position.z)
	add_child(mmi)
	return mmi


## Tapered, gently arched blade: 1 m tall (scaled per instance), UV.y 0 at root → 1 at tip.
func _build_blade_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half_w := blade_base_width * 0.5
	var arch := 0.15
	for row in blade_segments:
		var t := float(row) / blade_segments
		var w := half_w * (1.0 - pow(t, 1.4))
		var z := t * t * arch
		verts.append_array([Vector3(-w, t, z), Vector3(w, t, z)])
		# Rounded normals so a flat card shades like a curved blade.
		normals.append_array([Vector3(-0.4, 0.0, 1.0).normalized(), Vector3(0.4, 0.0, 1.0).normalized()])
		uvs.append_array([Vector2(0.0, t), Vector2(1.0, t)])
	var tip := verts.size()
	verts.append(Vector3(0.0, 1.0, arch))
	normals.append(Vector3.BACK)
	uvs.append(Vector2(0.5, 1.0))

	for row in blade_segments - 1:
		var a := row * 2
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var last := (blade_segments - 1) * 2
	indices.append_array([last, tip, last + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
