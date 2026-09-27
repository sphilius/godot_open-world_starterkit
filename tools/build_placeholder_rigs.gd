extends SceneTree
## Placeholder art generator for the wolf: a rigid node rig (no skeleton), its animation library
## (the bite keyed from its AttackData timings) and the model scene, saved as editable resources.
##
##   godot --headless --path . --script res://tools/build_placeholder_rigs.gd
##
## The humanoids (Duelist, Grunt, Brute, Gatekeeper) are real art since M2: see
## tools/art/build_characters.py, tools/art/build_animations.py and tools/build_character_scenes.gd.

const WOLF_DIR := "res://assets/characters/wolf/"
const WOLF_BITE_PATH := "res://resources/combat/wolf_bite.tres"
const DEG := PI / 180.0
const LACQUER := Color(0.05, 0.04, 0.04)
const FUR := Color(0.45, 0.43, 0.41)
const FUR_LIGHT := Color(0.64, 0.61, 0.57)
const FUR_DARK := Color(0.24, 0.23, 0.23)


func _initialize() -> void:
	_build_wolf()
	print("Wolf placeholder rebuilt.")
	quit()


# ==============================================================================================
# Wolf (rigid node rig: no skeleton needed)
# ==============================================================================================

const WOLF_ROTATED := {
	"rig": "Rig", "body": "Rig/Body", "head": "Rig/Body/Head", "tail": "Rig/Body/Tail",
	"fl": "Rig/Body/LegFL", "fr": "Rig/Body/LegFR", "bl": "Rig/Body/LegBL", "br": "Rig/Body/LegBR"}
const WOLF_POSITIONED := {"rig_pos": ["Rig", Vector3.ZERO], "body_pos": ["Rig/Body", Vector3(0, 0.55, 0)]}
const WOLF_BASE := {"tail": Vector3(35, 0, 0), "head": Vector3(-5, 0, 0)}


func _build_wolf() -> void:
	var fur := _material(FUR)
	var fur_light := _material(FUR_LIGHT)
	var fur_dark := _material(FUR_DARK)
	var nose := _material(LACQUER)
	var eyes := _material(Color(1.0, 0.72, 0.25))
	eyes.emission_enabled = true
	eyes.emission = Color(1.0, 0.62, 0.15)
	eyes.emission_energy_multiplier = 3.0

	var root := Node3D.new()
	root.name = "WolfModel"
	var rig := _pivot(root, root, "Rig", Vector3.ZERO)
	var body := _pivot(root, rig, "Body", Vector3(0, 0.55, 0))
	_part(root, body, "Torso", _box(0.34, 0.32, 0.8), Vector3(0, 0, 0.04), fur)
	_part(root, body, "Ruff", _box(0.38, 0.38, 0.3), Vector3(0, 0.02, -0.3), fur_light)
	_part(root, body, "Back", _box(0.2, 0.06, 0.7), Vector3(0, 0.17, 0.05), fur_dark)
	var head := _pivot(root, body, "Head", Vector3(0, 0.16, -0.46))
	_part(root, head, "Skull", _box(0.24, 0.22, 0.26), Vector3(0, 0.02, -0.08), fur)
	_part(root, head, "Snout", _box(0.12, 0.1, 0.2), Vector3(0, -0.03, -0.28), fur_light)
	_part(root, head, "Nose", _box(0.05, 0.04, 0.04), Vector3(0, 0.0, -0.39), nose)
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		_part(root, head, "Ear" + suffix, _prism(0.07, 0.12, 0.05), Vector3(0.07 * side, 0.17, -0.02), fur_dark)
		_part(root, head, "Eye" + suffix, _box(0.035, 0.022, 0.01), Vector3(0.065 * side, 0.05, -0.215), eyes)
	var tail := _pivot(root, body, "Tail", Vector3(0, 0.1, 0.4))
	_part(root, tail, "TailMesh", _box(0.08, 0.08, 0.42), Vector3(0, 0, 0.2), fur_dark)
	for leg: Array in [["LegFL", Vector3(-0.12, -0.05, -0.3)], ["LegFR", Vector3(0.12, -0.05, -0.3)],
			["LegBL", Vector3(-0.12, -0.05, 0.3)], ["LegBR", Vector3(0.12, -0.05, 0.3)]]:
		var pivot := _pivot(root, body, leg[0], leg[1])
		_part(root, pivot, "Leg", _box(0.09, 0.5, 0.09), Vector3(0, -0.25, 0), fur)

	var library := AnimationLibrary.new()
	library.add_animation(&"idle", _wolf_clip(2.0, true, [
		[0.0, WOLF_BASE],
		[1.0, _pose(WOLF_BASE, {"head": Vector3(0, 15, 0), "tail": Vector3(30, 10, 0), "body_pos": Vector3(0, -0.012, 0)})],
		[2.0, WOLF_BASE]]))
	var walk_a := _pose(WOLF_BASE, {"fl": Vector3(22, 0, 0), "br": Vector3(22, 0, 0), "fr": Vector3(-22, 0, 0),
			"bl": Vector3(-22, 0, 0), "head": Vector3(-8, 0, 0), "tail": Vector3(40, 8, 0)})
	var walk_pass := _pose(WOLF_BASE, {"head": Vector3(-8, 0, 0), "tail": Vector3(40, 0, 0), "body_pos": Vector3(0, 0.02, 0)})
	var walk_b := _pose(WOLF_BASE, {"fl": Vector3(-22, 0, 0), "br": Vector3(-22, 0, 0), "fr": Vector3(22, 0, 0),
			"bl": Vector3(22, 0, 0), "head": Vector3(-8, 0, 0), "tail": Vector3(40, -8, 0)})
	library.add_animation(&"walk", _wolf_clip(0.9, true, [
		[0.0, walk_a], [0.225, walk_pass], [0.45, walk_b], [0.675, walk_pass], [0.9, walk_a]]))
	var reach := {"fl": Vector3(40, 0, 0), "fr": Vector3(35, 0, 0), "bl": Vector3(-35, 0, 0), "br": Vector3(-40, 0, 0),
			"body": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "tail": Vector3(10, 0, 0), "body_pos": Vector3(0, -0.02, 0)}
	var flight := {"fl": Vector3(-5, 0, 0), "fr": Vector3(-10, 0, 0), "bl": Vector3(10, 0, 0), "br": Vector3(5, 0, 0),
			"head": Vector3(-10, 0, 0), "tail": Vector3(5, 0, 0), "body_pos": Vector3(0, 0.06, 0)}
	var gather := {"fl": Vector3(-40, 0, 0), "fr": Vector3(-35, 0, 0), "bl": Vector3(40, 0, 0), "br": Vector3(35, 0, 0),
			"body": Vector3(6, 0, 0), "head": Vector3(-6, 0, 0), "tail": Vector3(15, 0, 0)}
	var push := {"fl": Vector3(10, 0, 0), "fr": Vector3(5, 0, 0), "bl": Vector3(-5, 0, 0), "br": Vector3(-10, 0, 0),
			"head": Vector3(-10, 0, 0), "tail": Vector3(10, 0, 0), "body_pos": Vector3(0, 0.04, 0)}
	library.add_animation(&"run", _wolf_clip(0.5, true, [
		[0.0, reach], [0.125, flight], [0.25, gather], [0.375, push], [0.5, reach]]))
	library.add_animation(&"bite", _wolf_bite_clip(load(WOLF_BITE_PATH)))
	library.add_animation(&"hurt", _wolf_clip(0.35, false, [
		[0.0, WOLF_BASE],
		[0.07, {"body": Vector3(14, 0, 0), "body_pos": Vector3(0, 0.05, 0.1), "head": Vector3(25, 0, 0),
				"tail": Vector3(60, 0, 0), "fl": Vector3(-15, 0, 0), "fr": Vector3(-15, 0, 0)}],
		[0.35, WOLF_BASE]]))
	var collapsed := {"rig": Vector3(0, 0, 90), "rig_pos": Vector3(0.42, 0.17, 0), "fl": Vector3(15, 0, 0),
			"fr": Vector3(25, 0, 0), "bl": Vector3(-15, 0, 0), "br": Vector3(-10, 0, 0),
			"head": Vector3(-10, 0, 0), "tail": Vector3(20, 0, 0)}
	library.add_animation(&"death", _wolf_clip(1.0, false, [
		[0.0, WOLF_BASE],
		[0.18, {"rig": Vector3(0, 0, -8), "body": Vector3(-10, 0, 0), "fl": Vector3(-35, 0, 0),
				"fr": Vector3(-35, 0, 0), "head": Vector3(-25, 0, 0), "tail": Vector3(50, 0, 0)}],
		[0.6, collapsed],
		[1.0, _pose(collapsed, {"head": Vector3(0, 0, 0)})]]))
	library = _save(library, WOLF_DIR + "wolf_animations.tres")

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_own(root, root, player)
	player.add_animation_library(&"", library)
	_save_scene(root, WOLF_DIR + "wolf_model.tscn")


## Bite: crouch and gather (the telegraph), spring forward with the head snapping down during
## the active window, then recover. Keyed from the bite's AttackData timings.
func _wolf_bite_clip(attack: AttackData) -> Animation:
	var gathered := {"body": Vector3(8, 0, 0), "body_pos": Vector3(0, -0.07, 0.12), "head": Vector3(15, 0, 0),
			"fl": Vector3(-25, 0, 0), "fr": Vector3(-25, 0, 0), "bl": Vector3(20, 0, 0), "br": Vector3(20, 0, 0),
			"tail": Vector3(50, 0, 0)}
	var snap := {"body": Vector3(-8, 0, 0), "body_pos": Vector3(0, 0.02, -0.18), "head": Vector3(-18, 0, 0),
			"fl": Vector3(35, 0, 0), "fr": Vector3(35, 0, 0), "bl": Vector3(-30, 0, 0), "br": Vector3(-30, 0, 0),
			"tail": Vector3(20, 0, 0)}
	return _wolf_clip(attack.duration, false, [
		[0.0, WOLF_BASE], [attack.lunge_delay, gathered], [attack.active_start, gathered],
		[(attack.active_start + attack.active_end) * 0.5, snap], [attack.active_end, snap],
		[attack.duration, WOLF_BASE]])


func _wolf_clip(length: float, loop: bool, keys: Array) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for key_name: String in WOLF_ROTATED:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(WOLF_ROTATED[key_name]))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		for key: Array in keys:
			anim.rotation_track_insert_key(track, key[0], _euler((key[1] as Dictionary).get(key_name, Vector3.ZERO)))
	for key_name: String in WOLF_POSITIONED:
		var track := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(track, NodePath(WOLF_POSITIONED[key_name][0]))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		for key: Array in keys:
			var rest: Vector3 = WOLF_POSITIONED[key_name][1]
			anim.position_track_insert_key(track, key[0], rest + (key[1] as Dictionary).get(key_name, Vector3.ZERO))
	return anim


# ==============================================================================================
# Helpers
# ==============================================================================================

static func _euler(degrees: Vector3) -> Quaternion:
	return Quaternion.from_euler(degrees * DEG)


static func _pose(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var pose := base.duplicate()
	pose.merge(overrides, true)
	return pose


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x, y, z)
	return mesh


static func _prism(x: float, y: float, z: float) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(x, y, z)
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


static func _own(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root


static func _pivot(root: Node, parent: Node, node_name: String, position: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = position
	_own(root, parent, pivot)
	return pivot


static func _part(root: Node, parent: Node, node_name: String, mesh: PrimitiveMesh, position: Vector3, material: Material) -> void:
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	_own(root, parent, instance)


## Saves and returns the file-backed copy, so scenes packed afterwards reference it externally.
static func _save(resource: Resource, path: String) -> Resource:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(resource, path)
	assert(err == OK, "Failed to save %s: %s" % [path, error_string(err)])
	print("  saved ", path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


static func _save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	assert(err == OK, "Failed to pack %s" % path)
	_save(packed, path)
	root.free()
