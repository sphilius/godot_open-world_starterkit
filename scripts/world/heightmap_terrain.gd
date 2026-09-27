@tool
class_name HeightmapTerrain
extends StaticBody3D
## Procedurally sculpted heightmap terrain.
##
## One height array drives everything: the render mesh, the HeightMapShape3D collider,
## grass placement and landmark placement. What you see, what you stand on and where
## things spawn therefore always agree.
##
## Shape = rolling FBM meadow + ridged-noise mountains ringing the valley, then levelled
## (and painted as gravel via vertex colour) along the ScenicPath curve and inside the
## flatten zones (level sites for the courtyard and sanctum; no grass grows there).
## The node may be translated, but keep it unrotated and unscaled.

## Emitted after every (re)generation. GrassField and ScenicPath rebuild on it.
signal generated

@export_group("Size")
## Cells per side (1 cell = 1 m). Collision uses (size + 1)² height samples.
@export_range(32, 1024, 32) var size_cells := 256
@export var noise_seed := 1337

@export_group("Meadow")
@export var hill_height := 6.0
@export var hill_frequency := 0.011

@export_group("Mountains")
@export var ridge_height := 42.0
## Normalised distance from the centre (0 = centre, 1 = edge) where the valley starts climbing.
@export_range(0.0, 1.0) var ridge_start := 0.5
@export var ridge_frequency := 0.009

@export_group("Path")
## Path whose curve is levelled and painted as gravel. Curve points are treated as flat (y ignored).
@export var scenic_path: ScenicPath
## Blend distance (m) from the path edge back to natural terrain.
@export var path_shoulder := 3.0

@export_group("Flatten Zones")
## Circular level sites, terrain-local: (x, z, radius, height). Inside `radius` the ground is
## exactly `height` and painted like the path (so no grass); it blends back to natural terrain
## over `flatten_shoulder` metres.
@export var flatten_zones: Array[Vector4] = []
@export var flatten_shoulder := 8.0

@export_group("Rendering")
@export var terrain_material: Material

@export_tool_button("Regenerate", "Reload") var regenerate_action: Callable = generate

var _samples := 0                          # height samples per side
var _half := 0.0                           # half extent in metres
var _origin := Vector3.ZERO                # world position at generation time
var _heights := PackedFloat32Array()
var _normals := PackedVector3Array()
var _path_mask := PackedFloat32Array()     # 1 on gravel → 0 on meadow
var _is_generated := false
var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D


func _ready() -> void:
	ensure_generated()


## Safe to call from any node's _ready(): generates once, on first request.
func ensure_generated() -> void:
	if not _is_generated:
		generate()


func generate() -> void:
	_samples = size_cells + 1
	_half = size_cells * 0.5
	_origin = global_position
	var count := _samples * _samples
	_heights.resize(count)
	_path_mask.resize(count)

	var meadow := _make_noise(FastNoiseLite.FRACTAL_FBM, hill_frequency, 5, 0)
	var ridges := _make_noise(FastNoiseLite.FRACTAL_RIDGED, ridge_frequency, 4, 1)
	var curve := _path_curve_local()
	var half_width := scenic_path.path_half_width if scenic_path else 0.0
	var influence := half_width + path_shoulder

	for z in _samples:
		for x in _samples:
			var p := Vector2(x - _half, z - _half)
			var h := _natural_height(p, meadow, ridges)
			var mask := 0.0
			if curve:
				var c := curve.get_closest_point(Vector3(p.x, 0.0, p.y))
				var d := p.distance_to(Vector2(c.x, c.z))
				if d < influence:
					# Level the path's cross-section to the height at its centre line.
					var centre_h := _natural_height(Vector2(c.x, c.z), meadow, ridges)
					h = lerpf(h, centre_h, 1.0 - smoothstep(half_width, influence, d))
					mask = 1.0 - smoothstep(half_width - 0.5, half_width + 0.5, d)
			for zone in flatten_zones:
				var dz := p.distance_to(Vector2(zone.x, zone.y))
				if dz < zone.z + flatten_shoulder:
					h = lerpf(h, zone.w, 1.0 - smoothstep(zone.z, zone.z + flatten_shoulder, dz))
					mask = maxf(mask, 1.0 - smoothstep(zone.z - 1.0, zone.z, dz))
			var i := z * _samples + x
			_heights[i] = h
			_path_mask[i] = mask

	_build_mesh()
	_build_collision()
	_is_generated = true
	generated.emit()


# --- Queries (world space) -------------------------------------------------------------

## Surface height, interpolated on the same triangles the mesh renders.
func height_at(world_x: float, world_z: float) -> float:
	return _sample(_heights, world_x, world_z) + _origin.y


## 1 on the gravel path, 0 on meadow, soft in between.
func path_mask_at(world_x: float, world_z: float) -> float:
	return _sample(_path_mask, world_x, world_z)


## Nearest-sample surface normal (cheap; good enough for scatter rules).
func normal_at(world_x: float, world_z: float) -> Vector3:
	var gx := clampi(roundi(world_x - _origin.x + _half), 0, size_cells)
	var gz := clampi(roundi(world_z - _origin.z + _half), 0, size_cells)
	return _normals[gz * _samples + gx]


# --- Internals ---------------------------------------------------------------------------

func _natural_height(p: Vector2, meadow: FastNoiseLite, ridges: FastNoiseLite) -> float:
	var meadow_h := meadow.get_noise_2dv(p) * hill_height
	var rim := smoothstep(ridge_start, 1.0, p.length() / _half)   # 0 on the valley floor → 1 at the edge
	var ridge_h := (ridges.get_noise_2dv(p) * 0.5 + 0.5) * ridge_height
	return meadow_h + rim * rim * (ridge_height * 0.35 + ridge_h * 0.65)


## Triangle-exact interpolation matching the index layout in _build_mesh().
func _sample(grid: PackedFloat32Array, world_x: float, world_z: float) -> float:
	var gx := clampf(world_x - _origin.x + _half, 0.0, size_cells - 0.001)
	var gz := clampf(world_z - _origin.z + _half, 0.0, size_cells - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var i := z0 * _samples + x0
	var v00 := grid[i]
	var v10 := grid[i + 1]
	var v01 := grid[i + _samples]
	var v11 := grid[i + _samples + 1]
	if fx + fz <= 1.0:
		return v00 + (v10 - v00) * fx + (v01 - v00) * fz
	return v11 + (v01 - v11) * (1.0 - fx) + (v10 - v11) * (1.0 - fz)


func _make_noise(fractal: FastNoiseLite.FractalType, frequency: float, octaves: int, seed_offset: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed + seed_offset
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	return noise


## Copy of the path curve in terrain-local space, flattened to y = 0, with a coarse bake
## so ~66k closest-point queries stay fast.
func _path_curve_local() -> Curve3D:
	if scenic_path == null or scenic_path.curve == null or scenic_path.curve.point_count < 2:
		return null
	var to_local_xf := global_transform.affine_inverse() * scenic_path.global_transform
	var flat := Vector3(1.0, 0.0, 1.0)
	var src := scenic_path.curve
	var out := Curve3D.new()
	out.bake_interval = 1.0
	for i in src.point_count:
		out.add_point(
			(to_local_xf * src.get_point_position(i)) * flat,
			(to_local_xf.basis * src.get_point_in(i)) * flat,
			(to_local_xf.basis * src.get_point_out(i)) * flat)
	return out


func _build_mesh() -> void:
	var n := _samples
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	_normals.resize(n * n)

	for z in n:
		for x in n:
			var i := z * n + x
			verts[i] = Vector3(x - _half, _heights[i], z - _half)
			# Central differences (clamped at the borders) → smooth per-vertex normals.
			var h_left := _heights[z * n + maxi(x - 1, 0)]
			var h_right := _heights[z * n + mini(x + 1, n - 1)]
			var h_back := _heights[maxi(z - 1, 0) * n + x]
			var h_front := _heights[mini(z + 1, n - 1) * n + x]
			_normals[i] = Vector3(h_left - h_right, 2.0, h_back - h_front).normalized()
			colors[i] = Color(_path_mask[i], 0.0, 0.0)
			uvs[i] = Vector2(x, z) / float(size_cells)

	# Clockwise winding (Godot front faces); each quad splits along its (x+1,z)–(x,z+1)
	# diagonal, which _sample() mirrors exactly.
	var indices := PackedInt32Array()
	indices.resize(size_cells * size_cells * 6)
	var k := 0
	for z in size_cells:
		for x in size_cells:
			var i := z * n + x
			indices[k] = i
			indices[k + 1] = i + 1
			indices[k + 2] = i + n
			indices[k + 3] = i + 1
			indices[k + 4] = i + n + 1
			indices[k + 5] = i + n
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if terrain_material:
		mesh.surface_set_material(0, terrain_material)

	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC   # feeds the SDFGI volume


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _samples
	shape.map_depth = _samples
	shape.map_data = _heights       # centred on the node, 1 m spacing — same grid as the mesh
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "TerrainCollision"
		add_child(_collision)
	_collision.shape = shape
