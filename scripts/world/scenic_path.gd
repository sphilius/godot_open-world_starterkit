@tool
class_name ScenicPath
extends Path3D
## The designated scenic gravel path.
##
## HeightmapTerrain reads this curve to level and paint the gravel. This node lines the
## route with torii gates (spanning the path) and stone lanterns (alternating sides),
## each dropped onto the terrain surface. The placeholder scenes can be swapped for final art.
## Edit the curve in the editor, then press Terrain ▸ Regenerate (landmarks and grass follow).

@export var terrain: HeightmapTerrain
## Half the gravel width in metres. The terrain uses it too.
@export_range(0.5, 6.0, 0.1) var path_half_width := 1.6

@export_group("Torii Gates")
@export var torii_scene: PackedScene
@export var torii_spacing := 36.0
@export var torii_first_offset := 9.0
## Push posts into the ground so gentle slopes never show a gap.
@export var torii_sink := 0.2

@export_group("Stone Lanterns")
@export var lantern_scene: PackedScene
@export var lantern_spacing := 11.0
## Distance from the centre line in metres (sits just off the gravel).
@export var lantern_side_offset := 2.7
## Leave this much path clear on either side of each gate.
@export var lantern_clearance_from_torii := 4.0
@export var lantern_sink := 0.1

@export_tool_button("Rebuild Landmarks", "Reload") var rebuild_action: Callable = rebuild_landmarks

var _landmarks: Node3D


func _ready() -> void:
	if terrain == null:
		push_warning("ScenicPath: assign a HeightmapTerrain to place landmarks.")
		return
	terrain.ensure_generated()
	rebuild_landmarks()
	if not terrain.generated.is_connected(rebuild_landmarks):
		terrain.generated.connect(rebuild_landmarks)


func rebuild_landmarks() -> void:
	if is_instance_valid(_landmarks):
		_landmarks.free()
	_landmarks = Node3D.new()
	_landmarks.name = "Landmarks"
	add_child(_landmarks)
	if terrain == null or curve == null or curve.point_count < 2:
		return

	var length := curve.get_baked_length()
	var torii_offsets: Array[float] = []
	if torii_scene:
		var offset := torii_first_offset
		while offset <= length - 4.0:
			_spawn(torii_scene, offset, 0.0, torii_sink, "Torii")
			torii_offsets.append(offset)
			offset += torii_spacing

	if lantern_scene:
		var side := 1.0
		var offset := lantern_spacing * 0.5
		while offset <= length:
			if not _is_near_any(offset, torii_offsets, lantern_clearance_from_torii):
				_spawn(lantern_scene, offset, side * lantern_side_offset, lantern_sink, "Lantern")
			side = -side
			offset += lantern_spacing


## World transform on the terrain surface at `offset` metres along the path, with -Z
## pointing along the path. Positive `lateral` shifts toward the path's right-hand side.
func ground_transform_at(offset: float, lateral := 0.0) -> Transform3D:
	var length := curve.get_baked_length()
	var o := clampf(offset, 0.0, length)
	var o0 := clampf(o - 0.25, 0.0, maxf(length - 0.5, 0.0))
	var tangent := curve.sample_baked(o0 + 0.5, true) - curve.sample_baked(o0, true)
	var forward := (global_transform.basis * Vector3(tangent.x, 0.0, tangent.z)).normalized()
	var right := forward.cross(Vector3.UP)
	var pos := global_transform * curve.sample_baked(o, true) + right * lateral
	pos.y = terrain.height_at(pos.x, pos.z)
	return Transform3D(Basis.looking_at(forward, Vector3.UP), pos)


func _spawn(scene: PackedScene, offset: float, lateral: float, sink: float, label: String) -> void:
	var xf := ground_transform_at(offset, lateral)
	if lateral != 0.0:
		xf.basis = xf.basis.rotated(Vector3.UP, signf(lateral) * PI * 0.5)   # face the path
	xf.origin.y -= sink
	var node := scene.instantiate() as Node3D
	node.name = "%s_%03d" % [label, int(offset)]
	_landmarks.add_child(node)
	node.global_transform = xf


static func _is_near_any(value: float, points: Array[float], radius: float) -> bool:
	for p in points:
		if absf(value - p) < radius:
			return true
	return false
