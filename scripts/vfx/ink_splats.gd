class_name InkSplats
extends Node3D
## Dark ink splats on the ground under hits (M10 polish; the slice's take on blood decals).
## FeedbackDirector calls splat() for every hit that draws blood (HIT and KILLED); kills leave a
## bigger one.
##
## They are flat textured quads laid on the ground (a ray straight down from the hit, against
## `ground_mask`), not Decal nodes: decals don't render on the Compatibility (web) renderer.
## Each quad lines up with the ground's normal, turns to a random angle and grows in over
## `grow_time`. The oldest splat is reused once `max_splats` are down, and each one fades out
## after `lifetime` seconds. The splat shapes are generated in code (`variants` seeded masks of
## `texture_size` px), so they need no texture assets.

@export var max_splats := 24
## Seconds a splat stays before it fades.
@export var lifetime := 25.0
@export var fade_time := 3.0
@export var grow_time := 0.12
## Diameter range in metres of an ordinary hit's splat.
@export var size_range := Vector2(0.6, 1.1)
## Kills leave a splat this many times bigger.
@export var kill_scale := 1.7
@export var color := Color(0.16, 0.01, 0.03)
## What counts as ground (layer 1, world).
@export_flags_3d_physics var ground_mask := 1
## Height above the ground: enough to clear the terrain mesh between its collision samples.
@export var lift := 0.06
## How far below the hit to look for ground.
@export var max_drop := 3.0
@export var variants := 3
@export var texture_size := 96

## The splat meshes (at most max_splats; hidden ones have faded).
var splats: Array[MeshInstance3D] = []
var _textures: Array[ImageTexture] = []
var _tweens := {}                                           # splat → its grow-hold-fade tween
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	for i in variants:
		_textures.append(ImageTexture.create_from_image(make_mask(texture_size, 1000 + i)))


## Lays a splat on the ground below `at`, `scale` times the usual size. Returns it, or null
## when there's no ground within `max_drop`.
func splat(at: Vector3, scale := 1.0) -> MeshInstance3D:
	if not is_inside_tree():
		return null
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * max_drop, ground_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var mesh := _take()
	var normal: Vector3 = hit.normal
	var side := normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, normal, side.cross(normal)).rotated(normal, _rng.randf() * TAU)
	var diameter := _rng.randf_range(size_range.x, size_range.y) * scale
	mesh.global_transform = Transform3D(basis, hit.position + normal * lift)
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_texture = _textures[_rng.randi() % _textures.size()]
	material.albedo_color = color
	mesh.visible = true
	mesh.scale = Vector3.ONE * diameter * 0.35
	var tween := _tweens.get(mesh) as Tween
	if tween and tween.is_valid():
		tween.kill()
	tween = mesh.create_tween()
	tween.tween_property(mesh, ^"scale", Vector3.ONE * diameter, grow_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(lifetime)
	tween.tween_property(material, ^"albedo_color:a", 0.0, fade_time)
	tween.tween_callback(mesh.hide)
	_tweens[mesh] = tween
	return mesh


## Splats on show (not yet faded).
func visible_count() -> int:
	return splats.filter(func(mesh: MeshInstance3D) -> bool: return mesh.visible).size()


## A white splat shape in the alpha channel: a lumpy blob, satellite droplets flung outwards
## and a couple of streaks, all seeded by `seed_value`.
static func make_mask(size: int, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var harmonics: Array[Vector3] = []                      # (frequency, amplitude, phase)
	for f in [2, 3, 5, 7]:
		harmonics.append(Vector3(f, rng.randf_range(0.04, 0.12), rng.randf() * TAU))
	var drops: Array[Vector3] = []                          # (x, y, radius) in -1..1 space
	for i in rng.randi_range(6, 10):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(0.45, 0.9)
		drops.append(Vector3(cos(angle) * distance, sin(angle) * distance, rng.randf_range(0.03, 0.09)))
	for i in 2:                                             # streaks: droplets strung out in a line
		var angle := rng.randf() * TAU
		for step in 5:
			var distance := 0.35 + step * 0.1
			drops.append(Vector3(cos(angle) * distance, sin(angle) * distance, 0.06 - step * 0.01))
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var edge := 2.5 / size                                  # antialiasing width
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5) / size * 2.0 - 1.0, (y + 0.5) / size * 2.0 - 1.0)
			var angle := p.angle()
			var radius := 0.38
			for h in harmonics:
				radius += h.y * sin(h.x * angle + h.z) * 0.38
			var inside := radius - p.length()
			for d in drops:
				inside = maxf(inside, d.z - p.distance_to(Vector2(d.x, d.y)))
			var alpha := clampf(inside / edge + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return image


## The next free splat, or the oldest one.
func _take() -> MeshInstance3D:
	if splats.size() < max_splats:
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()                         # 1 x 1, facing +Y
		plane.size = Vector2.ONE
		mesh.mesh = plane
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.8                             # mostly matte: glossy ink mirrors the low sun and sky
		material.metallic_specular = 0.15
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		splats.append(mesh)
		return mesh
	var oldest := splats[_next]
	_next = (_next + 1) % splats.size()
	return oldest
