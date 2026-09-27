class_name Afterimage
extends Node3D
## Perfect-dodge afterimages (Phase A): frozen, translucent copies of a model's current pose
## that fade out where the fighter was. Each one duplicates the model's Skeleton3D (its bone
## poses come along, and the skinned meshes follow the copy) with nothing left to animate it,
## strips scripts, physics and particles (the sword's hitbox and trails), and draws every mesh
## with one additive material. trail() drops `count` of them `interval` seconds apart (real
## time, so slow motion doesn't stretch the spacing), each fading over `fade_time`.

const DEFAULT_COLOR := Color(0.55, 0.8, 1.0, 0.38)


## One afterimage of the first Skeleton3D under `source`, added under `parent`. Returns it, or
## null when `source` has no skeleton.
static func spawn(parent: Node, source: Node3D, color := DEFAULT_COLOR, fade_time := 0.4) -> Afterimage:
	var skeletons := source.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	# Not re-instanced from scene files: the sword rebuilds its children at runtime (trail type),
	# so an instanced copy would pair properties with the wrong nodes.
	var copy := skeleton.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Skeleton3D
	_strip(copy)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	for node in copy.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.material_override = material
		mesh.material_overlay = null                    # not the lock-on highlight
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ghost := Afterimage.new()
	ghost.name = "Afterimage"
	ghost.top_level = true
	parent.add_child(ghost)
	ghost.global_transform = skeleton.global_transform
	ghost.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	var tween := ghost.create_tween().set_ignore_time_scale(true)
	tween.tween_property(material, ^"albedo_color:a", 0.0, fade_time).set_ease(Tween.EASE_IN)
	tween.tween_callback(ghost.queue_free)
	return ghost


## `count` afterimages of `source`, `interval` real seconds apart.
static func trail(parent: Node, source: Node3D, count := 3, interval := 0.06, color := DEFAULT_COLOR) -> void:
	for i in count:
		if not is_instance_valid(parent) or not is_instance_valid(source) or not source.is_inside_tree():
			return
		spawn(parent, source, color)
		if i + 1 < count:
			await source.get_tree().create_timer(interval, true, false, true).timeout


## Leaves only the skeleton, bone attachments, plain Node3Ds and unscripted meshes: no scripts,
## no physics, no particles, nothing that animates.
static func _strip(node: Node) -> void:
	for child in node.get_children():
		var scripted_mesh := child is MeshInstance3D and child.get_script() != null   # the sword trails
		if scripted_mesh or child is CollisionObject3D or child is CollisionShape3D or child is GPUParticles3D \
				or child is CPUParticles3D or child is AnimationMixer or child is Light3D or not child is Node3D:
			node.remove_child(child)
			child.free()
			continue
		if child.get_script() != null:
			child.set_script(null)                          # the sword itself keeps its meshes
		_strip(child)
