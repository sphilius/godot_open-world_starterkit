@tool
class_name GreyboxArena
extends Node3D
## Greybox arena, built in code until the modular courtyard kit (M2) replaces it: a flagstone
## floor slab (top at y = 0), perimeter walls with gate openings, pillars and low cover walls.
## Everything is a StaticBody3D on the world layer, so it collides and bakes into the navmesh
## (put this node in the NavigationMesh's source group). Previews in the editor.

## Floor size (x, z) in metres, centred on this node.
@export var size := Vector2(24, 24):
	set(value):
		size = value
		_queue_build()
@export var walls := true:
	set(value):
		walls = value
		_queue_build()
@export var wall_height := 3.0
@export var wall_thickness := 0.6
## Gaps in the walls: (side, offset, width). Side 0 = north (-Z), 1 = east (+X), 2 = south (+Z),
## 3 = west (-X); offset is along the side from its centre (m).
@export var openings: Array[Vector3] = []:
	set(value):
		openings = value
		_queue_build()
## Pillars every this many metres along the walls (0 = corners only, -1 = none).
@export var pillar_spacing := 6.0
## Low broken walls for cover: (x, z, length, yaw in degrees), local.
@export var cover: Array[Vector4] = []:
	set(value):
		cover = value
		_queue_build()
## Optional raised dais at the centre: (x, z, half size); 0 half size = none.
@export var dais := Vector3.ZERO
@export var stone := Color(0.46, 0.42, 0.38)
@export var dark_stone := Color(0.3, 0.28, 0.27)

var _pending := false


func _ready() -> void:
	build()


func _queue_build() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	_pending = false
	build()


func build() -> void:
	for child in get_children():
		if child.has_meta(&"greybox"):
			remove_child(child)
			child.queue_free()
	var floor_material := _material(stone.lerp(Color(0.55, 0.5, 0.42), 0.4), 0.95)
	var wall_material := _material(stone, 0.9)
	var trim_material := _material(dark_stone, 0.85)
	_box("Floor", Vector3(size.x, 0.4, size.y), Vector3(0, -0.2, 0), floor_material)
	if walls:
		_build_walls(wall_material, trim_material)
	for index in cover.size():
		var c := cover[index]
		var body := _box("Cover%d" % index, Vector3(c.z, 1.1, 0.6), Vector3(c.x, 0.55, c.y), wall_material)
		body.rotation.y = deg_to_rad(c.w)
	if dais.z > 0.0:
		_box("Dais", Vector3(dais.z * 2.0, 0.35, dais.z * 2.0), Vector3(dais.x, 0.175, dais.y), trim_material)


func _build_walls(wall_material: Material, trim_material: Material) -> void:
	var half := size * 0.5
	# side → (centre, along-axis unit, length)
	var sides := [
		[Vector3(0, 0, -half.y), Vector3.RIGHT, size.x],
		[Vector3(half.x, 0, 0), Vector3.BACK, size.y],
		[Vector3(0, 0, half.y), Vector3.RIGHT, size.x],
		[Vector3(-half.x, 0, 0), Vector3.BACK, size.y],
	]
	for side in 4:
		var centre: Vector3 = sides[side][0]
		var along: Vector3 = sides[side][1]
		var length: float = sides[side][2] + wall_thickness
		# Split the side into solid runs around its openings.
		var gaps: Array[Vector2] = []
		for opening in openings:
			if int(opening.x) == side:
				gaps.append(Vector2(opening.y - opening.z * 0.5, opening.y + opening.z * 0.5))
		gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var start := -length * 0.5
		var runs: Array[Vector2] = []
		for gap in gaps:
			if gap.x > start:
				runs.append(Vector2(start, gap.x))
			start = maxf(start, gap.y)
		if start < length * 0.5:
			runs.append(Vector2(start, length * 0.5))
		for index in runs.size():
			var run := runs[index]
			var mid := (run.x + run.y) * 0.5
			var extent := run.y - run.x
			var dims := Vector3(extent, wall_height, wall_thickness) if along == Vector3.RIGHT \
					else Vector3(wall_thickness, wall_height, extent)
			_box("Wall%d_%d" % [side, index], dims, centre + along * mid + Vector3.UP * wall_height * 0.5, wall_material)
			var cap := dims + Vector3(0.15, 0.0, 0.15)
			cap.y = 0.2
			_box("Coping%d_%d" % [side, index], cap, centre + along * mid + Vector3.UP * (wall_height + 0.1), trim_material)
		if pillar_spacing >= 0.0:
			_build_pillars(centre, along, length, gaps, trim_material, side)


func _build_pillars(centre: Vector3, along: Vector3, length: float, gaps: Array[Vector2], material: Material, side: int) -> void:
	var positions: Array[float] = [-length * 0.5 + 0.3, length * 0.5 - 0.3]
	if pillar_spacing > 0.0:
		var steps := int(length / pillar_spacing)
		for step in range(1, steps):
			positions.append(-length * 0.5 + step * length / steps)
	for gap in gaps:                                     # flank every gate
		positions.append(gap.x - 0.5)
		positions.append(gap.y + 0.5)
	var index := 0
	for t in positions:
		var blocked := false
		for gap in gaps:
			if t > gap.x - 0.4 and t < gap.y + 0.4 and not (is_equal_approx(t, gap.x - 0.5) or is_equal_approx(t, gap.y + 0.5)):
				blocked = true
		if blocked:
			continue
		_box("Pillar%d_%d" % [side, index], Vector3(0.9, wall_height + 0.8, 0.9),
				centre + along * t + Vector3.UP * (wall_height + 0.8) * 0.5, material)
		index += 1


func _box(box_name: String, dims: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"greybox", true)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = dims
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dims
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
