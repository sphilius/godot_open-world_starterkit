extends SceneTree
## Builds the M2 character scenes from the GLBs that tools/art/build_characters.py and
## tools/art/build_animations.py write (run those first, then import):
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/build_character_scenes.gd
##
## Writes, keeping the paths and node names the game and the tests use:
##   assets/characters/samurai/samurai_model.tscn     Duelist (inherits duelist.glb)
##   assets/characters/samurai/samurai_animations.res Duelist clips
##   assets/characters/samurai/samurai_state_machine.tres  the Duelist's AnimationTree states
##   assets/characters/enemy/{grunt,brute,gatekeeper}_model.tscn, enemy_animations.res
## The scenes are written as text so they inherit the GLB (the mesh stays in the GLB, and a
## re-export flows through) and turn the glTF model's armature (+Z front) to face -Z like the
## rest of the kit. Sockets are Node3Ds under bone attachments: HandSocket (the grip, blade
## along -Z) and SheathSocket (left hip) for the Duelist; WeaponSocket with
## Socket_Telegraph_Glint at the weapon's tip, and a primitive weapon mesh, for the enemies.
## The clips get their exact lengths, and the Sword_Idle-based ones a turned wrist (READY_CLIPS).

const DUELIST_GLB := "res://assets/characters/duelist/duelist.glb"
const ENEMY_GLBS := {
	"GruntModel": ["res://assets/characters/grunt/grunt.glb", "sword", "res://assets/characters/enemy/grunt_model.tscn"],
	"BruteModel": ["res://assets/characters/brute/brute.glb", "maul", "res://assets/characters/enemy/brute_model.tscn"],
	"GatekeeperModel": ["res://assets/characters/gatekeeper/gatekeeper.glb", "greatsword", "res://assets/characters/enemy/gatekeeper_model.tscn"],
}
const DUELIST_CLIPS := "res://assets/characters/humanoid/duelist_animations.glb"
const ENEMY_CLIPS := "res://assets/characters/humanoid/enemy_animations.glb"
const SAMURAI_DIR := "res://assets/characters/samurai/"
const ENEMY_DIR := "res://assets/characters/enemy/"
const SKELETON := "Armature/Skeleton3D"
## Bones whose position is animated. The others keep their own rest offsets: the outfits'
## rig is a little narrower at the shoulders and hips than the animation library's.
const POSITION_TRACKS: Array[String] = ["root", "pelvis"]
## The sheathed katana in the idle stance, in model space (-Z forward, +X right): its mouth at
## the left hip (offset from the pelvis) and the blade back and down from there (decision D6).
const SHEATH_OFFSET := Vector3(-0.2, 0.03, -0.06)
const SHEATH_DIRECTION := Vector3(-0.1, -0.35, 1.0)
## Weapon tip distance from the grip (the telegraph glint's marker), per weapon.
const WEAPON_TIPS := {"sword": 0.95, "maul": 1.15, "greatsword": 1.25}
## The Duelist's strikes, in the state machine (each clip's length is its AttackData duration:
## tools/art/build_animations.py retimes them).
const ATTACK_PATHS := [
	"res://resources/combat/attack_1.tres",
	"res://resources/combat/attack_2.tres",
	"res://resources/combat/attack_3.tres",
	"res://resources/combat/heavy_1.tres",
	"res://resources/combat/heavy_2.tres",
	"res://resources/combat/heavy_finisher.tres",
	"res://resources/combat/draw_attack.tres",
	"res://resources/combat/execution.tres",
]
const DODGES: Array[String] = ["dodge_f", "dodge_b", "dodge_l", "dodge_r"]
## The held guard loops; a block or parry plays once and returns to it.
const GUARD_CLIPS: Array[String] = ["guard_idle", "guard_hit", "parry_1", "parry_2"]
## One per DamageReactionComponent stagger type (CombatStateMachine.STAGGER_CLIPS).
const REACTION_CLIPS: Array[String] = ["hurt_f", "hurt_b", "hurt_l", "hurt_r", "hurt_heavy", "knockdown", "guard_break"]
## Clips on the libraries' Sword_Idle stance, whose fist would hold a blade out to the side:
## _ready_grip turns the wrist so the blade points at the opponent instead.
const READY_CLIPS: Array[String] = ["idle", "strafe_l", "strafe_r", "strafe_b"]
## The blade's direction in those clips (model space: -Z forward, +X right): forward and up at
## chest height, a little out to the right.
const READY_BLADE := Vector3(0.2, 0.5, -0.85)
## Locked-on side-steps (strafe left, right, back), keyed by tools/art/build_animations.py.
const SIDE_STEPS: Array[String] = ["strafe_l", "strafe_r", "strafe_b"]


func _initialize() -> void:
	var duelist_lib := SAMURAI_DIR + "samurai_animations.res"
	var duelist_clips := _library(DUELIST_CLIPS, "res://assets/characters/humanoid/duelist_clips.json")
	_save(duelist_clips, duelist_lib)
	var enemy_lib := ENEMY_DIR + "enemy_animations.res"
	_save(_library(ENEMY_CLIPS, "res://assets/characters/humanoid/enemy_clips.json"), enemy_lib)

	var duelist := SceneText.new("SamuraiModel", DUELIST_GLB, duelist_lib)
	var skeleton := _rest_skeleton(DUELIST_GLB)
	duelist.socket(skeleton, "hand_r", "HandBone", "HandSocket", _in_bone_at_rest(skeleton, "hand_r", _grip(skeleton)))
	duelist.socket(skeleton, "pelvis", "SheathBone", "SheathSocket", _sheath(skeleton, duelist_clips.get_animation(&"idle")))
	duelist.save(SAMURAI_DIR + "samurai_model.tscn")
	skeleton.free()
	_save(_state_machine(), SAMURAI_DIR + "samurai_state_machine.tres")

	for root_name: String in ENEMY_GLBS:
		var spec: Array = ENEMY_GLBS[root_name]
		var enemy := SceneText.new(root_name, spec[0], enemy_lib)
		var enemy_skeleton := _rest_skeleton(spec[0])
		var socket := enemy.socket(enemy_skeleton, "hand_r", "WeaponBone", "WeaponSocket",
				_in_bone_at_rest(enemy_skeleton, "hand_r", _grip(enemy_skeleton)))
		enemy_skeleton.free()
		_weapon(enemy, socket, spec[1])
		enemy.node("Socket_Telegraph_Glint", "Marker3D", socket,
				["position = Vector3(0, 0, %s)" % -float(WEAPON_TIPS[spec[1]])])
		enemy.save(spec[2])
	print("Character scenes rebuilt.")
	quit()


## The clips of an animation GLB as a library: scale tracks dropped, position tracks kept only
## for POSITION_TRACKS, lengths and loop flags from the build's clips json.
func _library(glb: String, json_path: String) -> AnimationLibrary:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var scene := (load(glb) as PackedScene).instantiate()
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var library := AnimationLibrary.new()
	for clip: String in info:
		# The importer reads a `_loop` suffix as a loop hint and drops it from the name.
		var source := clip if player.has_animation(clip) else clip.trim_suffix("_loop")
		var anim := player.get_animation(source).duplicate(true) as Animation
		for track in range(anim.get_track_count() - 1, -1, -1):
			var path := String(anim.track_get_path(track))
			var bone := path.get_slice(":", 1)
			var type := anim.track_get_type(track)
			if type == Animation.TYPE_SCALE_3D or (type == Animation.TYPE_POSITION_3D and bone not in POSITION_TRACKS):
				anim.remove_track(track)
			elif not path.begins_with(SKELETON + ":"):
				anim.track_set_path(track, NodePath(SKELETON + ":" + bone))
		# glTF stores keys, not a length: the importer ends a clip on its last key, which can sit
		# up to a frame past the fitted length.
		anim.length = info[clip]["length"]
		anim.loop_mode = Animation.LOOP_LINEAR if info[clip]["loop"] else Animation.LOOP_NONE
		if clip in READY_CLIPS:
			_ready_grip(anim, skeleton)
		library.add_animation(StringName(clip), anim)
	scene.free()
	return library


## Turns the right wrist through the whole of `anim` by the rotation that points the blade (held
## as _grip holds it) along READY_BLADE on the first frame, so the stance's sway survives.
func _ready_grip(anim: Animation, skeleton: Skeleton3D) -> void:
	var track := anim.find_track(NodePath(SKELETON + ":hand_r"), Animation.TYPE_ROTATION_3D)
	if track < 0:
		return
	var hand := skeleton.find_bone("hand_r")
	var blade_in_hand := skeleton.get_bone_global_rest(hand).basis.inverse() * -_grip(skeleton).basis.z
	var hand_now := _pose(anim, skeleton, hand, 0.0).basis
	var target := Basis(Vector3.UP, PI) * READY_BLADE.normalized()      # model space to skeleton space
	var turn := Quaternion(blade_in_hand.normalized(), (hand_now.inverse() * target).normalized())
	for key in anim.track_get_key_count(track):
		anim.track_set_key_value(track, key, (anim.track_get_key_value(track, key) as Quaternion) * turn)


## A bone's transform in skeleton space at `time` in `anim` (the rest pose where a bone has no
## track). Composed by hand: a skeleton outside the tree doesn't update its global poses.
func _pose(anim: Animation, skeleton: Skeleton3D, bone: int, time: float) -> Transform3D:
	var pose := Transform3D()
	while bone >= 0:
		var path := NodePath(SKELETON + ":" + skeleton.get_bone_name(bone))
		var rest := skeleton.get_bone_rest(bone)
		var rotation_track := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		var position_track := anim.find_track(path, Animation.TYPE_POSITION_3D)
		var local := Transform3D(
				Basis(anim.rotation_track_interpolate(rotation_track, time)) if rotation_track >= 0 else rest.basis,
				anim.position_track_interpolate(position_track, time) if position_track >= 0 else rest.origin)
		pose = local * pose
		bone = skeleton.get_bone_parent(bone)
	return pose


## The GLB's skeleton, detached, for its rest poses.
func _rest_skeleton(glb: String) -> Skeleton3D:
	var scene := (load(glb) as PackedScene).instantiate()
	var skeleton := scene.get_node(SKELETON) as Skeleton3D
	skeleton.get_parent().remove_child(skeleton)
	scene.free()
	for child in skeleton.get_children():
		child.free()
	return skeleton


## The right hand's grip in skeleton space at rest: the fist's axis runs from the little
## finger's knuckle to the index finger's, so the blade leaves the fist along it (-Z); the edge
## faces the way the fingers point (+Y).
func _grip(skeleton: Skeleton3D) -> Transform3D:
	var hand := _rest(skeleton, "hand_r")
	var blade := (_rest(skeleton, "index_01_r") - _rest(skeleton, "pinky_01_r")).normalized()
	var fingers := (_rest(skeleton, "middle_02_r") - hand).normalized()
	var z := -blade
	var x := fingers.cross(z).normalized()
	var y := z.cross(x).normalized()
	var centre := (hand + _rest(skeleton, "middle_02_r")) * 0.5
	return Transform3D(Basis(x, y, z), centre)


func _rest(skeleton: Skeleton3D, bone: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin


## `target` (skeleton space, at rest) relative to `bone`.
func _in_bone_at_rest(skeleton: Skeleton3D, bone: String, target: Transform3D) -> Transform3D:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse() * target


## The sheath relative to the pelvis, placed in the first frame of `idle`: the stance crouches and
## tips the pelvis forward, and the idle is where the sheathed katana is seen most. (Skeleton
## space is model space turned 180 degrees, so X and Z flip.)
func _sheath(skeleton: Skeleton3D, idle: Animation) -> Transform3D:
	var pelvis := _pose(idle, skeleton, skeleton.find_bone("pelvis"), 0.0)
	var flip := Basis(Vector3.UP, PI)
	var z := -(flip * SHEATH_DIRECTION).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	return pelvis.affine_inverse() * Transform3D(Basis(x, y, z), pelvis.origin + flip * SHEATH_OFFSET)


## A primitive stand-in weapon (M2 §2C models replace them) under `socket`, blade along -Z.
func _weapon(scene: SceneText, socket: String, kind: String) -> void:
	var steel := scene.sub_resource("StandardMaterial3D", "steel",
			["albedo_color = Color(0.62, 0.64, 0.68, 1)", "metallic = 0.85", "roughness = 0.35"])
	var wrap := scene.sub_resource("StandardMaterial3D", "wrap",
			["albedo_color = Color(0.2, 0.14, 0.1, 1)", "roughness = 0.8"])
	var tip: float = WEAPON_TIPS[kind]
	var parts: Array = []     # [size, material, position]
	match kind:
		"sword", "greatsword":
			var width := 0.06 if kind == "sword" else 0.1
			parts = [[Vector3(width, 0.015, tip - 0.15), steel, Vector3(0, 0, -(tip + 0.15) / 2.0)],
					[Vector3(0.22 if kind == "sword" else 0.3, 0.03, 0.03), steel, Vector3(0, 0, -0.1)],
					[Vector3(0.035, 0.035, 0.22), wrap, Vector3(0, 0, 0.02)]]
		"maul":
			parts = [[Vector3(0.05, 0.05, tip), wrap, Vector3(0, 0, -tip / 2.0 + 0.15)],
					[Vector3(0.18, 0.18, 0.3), steel, Vector3(0, 0, -tip + 0.1)]]
	for i in parts.size():
		var mesh := scene.sub_resource("BoxMesh", "part%d" % i, ["size = %s" % SceneText.vec(parts[i][0])])
		scene.node("Weapon%d" % i, "MeshInstance3D", socket, [
			"position = %s" % SceneText.vec(parts[i][2]),
			"mesh = SubResource(\"%s\")" % mesh,
			"material_override = SubResource(\"%s\")" % parts[i][1],
		])


## The Duelist's AnimationTree states: one per clip the combat code travels to. Every action
## (strike or dodge) can start from, chain into and return to any other state (CombatStateMachine
## decides what's allowed); reactions interrupt anything. Locomotion is idle, run and the
## locked-on side-steps.
func _state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	var actions: Array[String] = []
	for path: String in ATTACK_PATHS:
		actions.append(String((load(path) as AttackData).animation))
	actions.append_array(DODGES)
	var moving: Array[String] = ["run"]
	moving.append_array(SIDE_STEPS)
	var locomotion: Array[String] = ["idle"]
	locomotion.append_array(moving)
	var guards: Array[String] = []
	guards.append_array(GUARD_CLIPS)
	var reactions: Array[String] = []
	reactions.append_array(REACTION_CLIPS)
	var states: Array = locomotion + actions + guards + reactions + ["death"]
	for i in states.size():
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(states[i])
		var state: AnimationRootNode = node
		if states[i] in SIDE_STEPS:
			# Clip -> TimeScale "speed" -> output: CombatStateMachine matches the playback to the
			# ground speed through parameters/<step>/speed/scale.
			var tree := AnimationNodeBlendTree.new()
			tree.add_node(&"clip", node, Vector2(0, 0))
			tree.add_node(&"speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
			tree.connect_node(&"speed", 0, &"clip")
			tree.connect_node(&"output", 0, &"speed")
			state = tree
		machine.add_node(StringName(states[i]), state, Vector2(300 + 220 * (i % 4), 100 + 160 * (i / 4)))
	_link(machine, "Start", "idle", 0.0, true)
	for move in moving:
		_link(machine, "idle", move, 0.15)
		_link(machine, move, "idle", 0.2)
		for other in moving:
			if other != move:
				_link(machine, move, other, 0.15)
	for action in actions:
		for from: String in locomotion + reactions + guards + actions:
			if from != action:
				_link(machine, from, action, 0.06 if from in actions else 0.08)
		for to in locomotion:
			_link(machine, action, to, 0.2)
	# Guard: raised from locomotion, strike or dodge recovery; blocks and parries play once and
	# return to the held guard on their own. A press from locomotion or a recovery can parry (or
	# block) on its first frame, so those clips are one hop away too.
	for from: String in locomotion + actions:
		for guard in guards:
			_link(machine, from, guard, 0.1 if guard == "guard_idle" else 0.05)
	for guard in guards:
		for to in locomotion:
			_link(machine, guard, to, 0.15)
		for other in guards:
			if other != guard and other != "guard_idle":
				_link(machine, guard, other, 0.04)
		if guard != "guard_idle":
			_link(machine, guard, "guard_idle", 0.12, true)
	for reaction in reactions:
		for from: String in locomotion + actions + guards + reactions:
			if from != reaction:
				_link(machine, from, reaction, 0.05)
		for to in locomotion:
			_link(machine, reaction, to, 0.15)
	for from: String in locomotion + actions + guards + reactions:
		_link(machine, from, "death", 0.1)
	_link(machine, "death", "idle", 0.3)     # respawn
	return machine


## `auto` from Start fires at once; from any other state it waits for the clip to end.
func _link(machine: AnimationNodeStateMachine, from: String, to: String, xfade: float, auto := false) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END if auto and from != "Start" \
			else AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto \
			else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED   # ENABLED: only travel() moves it
	machine.add_transition(StringName(from), StringName(to), transition)


func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("Couldn't save %s: %s" % [path, error_string(err)])


## A .tscn written as text: a scene inheriting a GLB with nodes added to it. (PackedScene.pack
## can't record inheritance from a script, so it would copy the whole model into the scene.)
class SceneText:
	var _root_name: String
	var _ext: PackedStringArray = []
	var _sub: PackedStringArray = []
	var _nodes: PackedStringArray = []

	func _init(root_name: String, glb: String, library: String) -> void:
		_root_name = root_name
		_ext.append('[ext_resource type="PackedScene" path="%s" id="1_model"]' % glb)
		_ext.append('[ext_resource type="AnimationLibrary" path="%s" id="2_clips"]' % library)
		_nodes.append('[node name="%s" instance=ExtResource("1_model")]' % root_name)
		# The armature (the imported one is at identity) turns to face -Z, the glTF front being
		# +Z; the root stays free for the transform (scale) scenes give the instance.
		_nodes.append('[node name="Armature" parent="."]\ntransform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)')
		node("AnimationPlayer", "AnimationPlayer", ".", ['libraries/ = ExtResource("2_clips")'])

	## Adds a node under `parent` (a path from the root) and returns its path.
	func node(node_name: String, type: String, parent: String, properties: Array = []) -> String:
		var lines := PackedStringArray(['[node name="%s" type="%s" parent="%s"]' % [node_name, type, parent]])
		for property: String in properties:
			lines.append(property)
		_nodes.append("\n".join(lines))
		return node_name if parent == "." else parent + "/" + node_name

	## Adds a sub-resource and returns its id.
	func sub_resource(type: String, id: String, properties: Array) -> String:
		var full_id := "%s_%s" % [type, id]
		var lines := PackedStringArray(['[sub_resource type="%s" id="%s"]' % [type, full_id]])
		for property: String in properties:
			lines.append(property)
		_sub.append("\n".join(lines))
		return full_id

	## A BoneAttachment3D `attachment_name` on `bone` with a child `socket_name` at `local` (in
	## the bone's space). Returns the socket's path.
	func socket(skeleton: Skeleton3D, bone: String, attachment_name: String, socket_name: String, local: Transform3D) -> String:
		var index := skeleton.find_bone(bone)
		var attachment := node(attachment_name, "BoneAttachment3D", String(SKELETON),
				['bone_name = "%s"' % bone, "bone_idx = %d" % index])
		return node(socket_name, "Node3D", attachment, ["transform = %s" % xform(local)])

	func save(path: String) -> void:
		var text := "[gd_scene format=3]\n\n" + "\n".join(_ext) + "\n\n"
		if not _sub.is_empty():
			text += "\n\n".join(_sub) + "\n\n"
		text += "\n\n".join(_nodes) + "\n"
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Couldn't write %s: %s" % [path, error_string(FileAccess.get_open_error())])
			return
		file.store_string(text)

	static func vec(v: Vector3) -> String:
		return "Vector3(%s, %s, %s)" % [_num(v.x), _num(v.y), _num(v.z)]

	static func xform(t: Transform3D) -> String:
		var b := t.basis
		var values := [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z]
		return "Transform3D(%s)" % ", ".join(values.map(func(value: float) -> String: return _num(value)))

	static func _num(value: float) -> String:
		var text := "%.6f" % value
		text = text.rstrip("0").trim_suffix(".")
		return "0" if text == "-0" else text
