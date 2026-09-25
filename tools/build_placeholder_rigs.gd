extends SceneTree
## Placeholder art generator. Builds the skinned samurai rig and the wolf model, their animation
## libraries, and the samurai AnimationTree state machine, then saves them as editable resources.
##
##   godot --headless --path . --script res://tools/build_placeholder_rigs.gd
##
## Re-run after changing the bone layout, poses or AttackData timings (attack swings are keyed
## from the AttackData resources in ATTACK_PATHS). To swap in real art, keep the bone names
## (weapon_r, scabbard, …) and the clip names listed in docs/vertical-slice/HANDOFF_MANIFEST.md,
## or retarget the sockets and state machine.

const SAMURAI_DIR := "res://assets/characters/samurai/"
const WOLF_DIR := "res://assets/characters/wolf/"
const ATTACK_PATHS := [
	"res://resources/combat/attack_1.tres",
	"res://resources/combat/attack_2.tres",
	"res://resources/combat/attack_3.tres",
	"res://resources/combat/heavy_1.tres",
	"res://resources/combat/heavy_2.tres",
	"res://resources/combat/heavy_finisher.tres",
	"res://resources/combat/draw_attack.tres",
]
## Dodge clip length; CombatStateMachine.dodge_duration must match (tests/test_data.gd checks it).
const DODGE_LENGTH := 0.45
## Directional dodges: clip name → horizontal direction in model space (-Z forward, +X right).
const DODGES := {
	"dodge_f": Vector3(0, 0, -1), "dodge_b": Vector3(0, 0, 1),
	"dodge_l": Vector3(-1, 0, 0), "dodge_r": Vector3(1, 0, 0),
}
const WOLF_BITE_PATH := "res://resources/combat/wolf_bite.tres"
const DEG := PI / 180.0

# --- Samurai skeleton ------------------------------------------------------------------------
# [bone, parent, rest position relative to parent]. Rest rotations are identity (so a pose's
# Euler angles read directly), except the scabbard. Faces -Z, +X is its right, feet at y = 0.
const SAMURAI_BONES := [
	["root", "", Vector3.ZERO],
	["hips", "root", Vector3(0, 0.92, 0)],
	["spine", "hips", Vector3(0, 0.12, 0)],
	["chest", "spine", Vector3(0, 0.2, 0)],
	["head", "chest", Vector3(0, 0.28, 0)],
	["upper_arm_r", "chest", Vector3(0.22, 0.2, 0)],
	["forearm_r", "upper_arm_r", Vector3(0, -0.3, 0)],
	["hand_r", "forearm_r", Vector3(0, -0.27, 0)],
	["weapon_r", "hand_r", Vector3(0, -0.05, 0)],     # katana grip; blade runs along its -Z
	["upper_arm_l", "chest", Vector3(-0.22, 0.2, 0)],
	["forearm_l", "upper_arm_l", Vector3(0, -0.3, 0)],
	["hand_l", "forearm_l", Vector3(0, -0.27, 0)],
	["thigh_r", "hips", Vector3(0.1, -0.02, 0)],
	["shin_r", "thigh_r", Vector3(0, -0.44, 0)],
	["foot_r", "shin_r", Vector3(0, -0.4, 0)],
	["thigh_l", "hips", Vector3(-0.1, -0.02, 0)],
	["shin_l", "thigh_l", Vector3(0, -0.44, 0)],
	["foot_l", "shin_l", Vector3(0, -0.4, 0)],
	["scabbard", "hips", Vector3(-0.21, 0.06, -0.06)], # left hip, mouth just forward of the obi
]
## Sheathed blade direction: back and slightly down from the left hip, edge up (decision D6).
const SCABBARD_DIRECTION := Vector3(-0.1, -0.35, 1.0)
const HIPS_REST := Vector3(0, 0.92, 0)

## Bones every samurai clip keys, so AnimationTree blends are deterministic.
const SAMURAI_ANIMATED := [
	"spine", "chest", "head", "upper_arm_r", "forearm_r", "hand_r", "weapon_r",
	"upper_arm_l", "forearm_l", "hand_l", "thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l",
]

# Pose angle conventions (degrees, Godot YXZ Euler): for down-pointing limbs, +X swings them
# forward; for up-pointing bones (spine/chest/head), -X leans forward; +Y twists the torso left.

const SAMURAI_IDLE := {
	"spine": Vector3(-3, 0, 0), "head": Vector3(2, 0, 0),
	"upper_arm_r": Vector3(20, 0, 12), "forearm_r": Vector3(35, 0, 0),   # blade held up-forward (chudan)
	"upper_arm_l": Vector3(10, 0, -8), "forearm_l": Vector3(20, 0, 0),
	"thigh_r": Vector3(8, 0, 5), "shin_r": Vector3(-12, 0, 0),
	"thigh_l": Vector3(6, 0, -5), "shin_l": Vector3(-10, 0, 0),
	"hips_offset": Vector3(0, -0.02, 0),
}
## Low, wide stance shared by the horizontal slashes (left foot forward).
const SLASH_STANCE := {
	"spine": Vector3(-14, 0, 0), "head": Vector3(10, 0, 0),
	"upper_arm_l": Vector3(45, 0, -10), "forearm_l": Vector3(80, 0, 0),
	"thigh_r": Vector3(-20, 0, 6), "shin_r": Vector3(-15, 0, 0),
	"thigh_l": Vector3(30, 0, -6), "shin_l": Vector3(-30, 0, 0),
	"weapon_r": Vector3(-90, 0, 0),   # blade extends the arm for a wide arc at wolf height
	"hips_offset": Vector3(0, -0.08, 0),
}

# --- Colours (sRGB) ----------------------------------------------------------------------------
const INDIGO := Color(0.13, 0.14, 0.24)
const KIMONO := Color(0.78, 0.74, 0.66)
const SASH := Color(0.62, 0.1, 0.08)
const SKIN := Color(0.86, 0.68, 0.54)
const STRAW := Color(0.72, 0.6, 0.36)
const HAIR := Color(0.06, 0.05, 0.05)
const LACQUER := Color(0.05, 0.04, 0.04)
const FUR := Color(0.45, 0.43, 0.41)
const FUR_LIGHT := Color(0.64, 0.61, 0.57)
const FUR_DARK := Color(0.24, 0.23, 0.23)


func _initialize() -> void:
	_build_samurai()
	_build_wolf()
	print("Placeholder rigs rebuilt.")
	quit()


# ==============================================================================================
# Samurai
# ==============================================================================================

func _build_samurai() -> void:
	var root := Node3D.new()
	root.name = "SamuraiModel"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	_own(root, root, skeleton)
	for bone: Array in SAMURAI_BONES:
		var index := skeleton.add_bone(bone[0])
		if bone[1] != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
		var basis := Basis.IDENTITY
		if bone[0] == "scabbard":
			basis = Basis.looking_at(SCABBARD_DIRECTION.normalized(), Vector3.UP)
		skeleton.set_bone_rest(index, Transform3D(basis, bone[2]))
	skeleton.reset_bone_poses()

	# One skinned mesh: each primitive part is rigidly weighted to its bone.
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _skinned_mesh(skeleton, _samurai_parts())
	body.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	_own(root, skeleton, body)
	body.skin = skeleton.create_skin_from_rest_transforms()
	body.skeleton = ^".."

	# Weapon sockets: the katana moves between these two bone attachments.
	for socket: Array in [["HandSocket", "weapon_r"], ["SheathSocket", "scabbard"]]:
		var attachment := BoneAttachment3D.new()
		attachment.name = socket[0]
		_own(root, skeleton, attachment)
		attachment.bone_name = socket[1]

	var library := AnimationLibrary.new()
	library.add_animation(&"idle", _samurai_clip(2.4, true, [
		[0.0, SAMURAI_IDLE],
		[1.2, _pose(SAMURAI_IDLE, {"chest": Vector3(2, 0, 0), "upper_arm_r": Vector3(22, 0, 12),
				"hips_offset": Vector3(0, -0.03, 0)})],
		[2.4, SAMURAI_IDLE],
	]))
	library.add_animation(&"run", _samurai_run())
	for path: String in ATTACK_PATHS:
		var attack: AttackData = load(path)
		library.add_animation(attack.animation, _attack_clip(attack))
	for dodge: String in DODGES:
		library.add_animation(StringName(dodge), _dodge_clip(DODGES[dodge]))
	library.add_animation(&"hurt", _samurai_hurt())
	library.add_animation(&"death", _samurai_death())
	library = _save(library, SAMURAI_DIR + "samurai_animations.tres")

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_own(root, root, player)
	player.add_animation_library(&"", library)

	_save_scene(root, SAMURAI_DIR + "samurai_model.tscn")
	_save(_samurai_state_machine(), SAMURAI_DIR + "samurai_state_machine.tres")


func _samurai_parts() -> Array:
	# [bone, mesh, offset in bone space, colour]
	return [
		["hips", _box(0.34, 0.22, 0.24), Vector3(0, -0.02, 0), INDIGO],        # hakama
		["hips", _box(0.36, 0.07, 0.26), Vector3(0, 0.08, 0), SASH],           # obi
		["spine", _box(0.32, 0.2, 0.21), Vector3(0, 0.1, 0), KIMONO],
		["chest", _box(0.42, 0.3, 0.25), Vector3(0, 0.12, 0), KIMONO],
		["head", _sphere(0.12), Vector3(0, 0.12, 0), SKIN],
		["head", _box(0.05, 0.06, 0.08), Vector3(0, 0.25, 0.06), HAIR],        # topknot
		["head", _cone(0.02, 0.42, 0.14), Vector3(0, 0.29, 0), STRAW],         # kasa hat
		["upper_arm_r", _box(0.15, 0.3, 0.15), Vector3(0, -0.15, 0), KIMONO],  # sleeve
		["forearm_r", _box(0.09, 0.27, 0.09), Vector3(0, -0.13, 0), INDIGO],   # bracer
		["hand_r", _sphere(0.055), Vector3(0, -0.03, 0), SKIN],
		["upper_arm_l", _box(0.15, 0.3, 0.15), Vector3(0, -0.15, 0), KIMONO],
		["forearm_l", _box(0.09, 0.27, 0.09), Vector3(0, -0.13, 0), INDIGO],
		["hand_l", _sphere(0.055), Vector3(0, -0.03, 0), SKIN],
		["thigh_r", _box(0.2, 0.44, 0.22), Vector3(0, -0.22, 0), INDIGO],
		["shin_r", _box(0.22, 0.4, 0.24), Vector3(0, -0.2, 0), INDIGO],         # hakama flare
		["foot_r", _box(0.1, 0.06, 0.24), Vector3(0, -0.03, -0.05), LACQUER],
		["thigh_l", _box(0.2, 0.44, 0.22), Vector3(0, -0.22, 0), INDIGO],
		["shin_l", _box(0.22, 0.4, 0.24), Vector3(0, -0.2, 0), INDIGO],
		["foot_l", _box(0.1, 0.06, 0.24), Vector3(0, -0.03, -0.05), LACQUER],
		["scabbard", _box(0.04, 0.055, 0.84), Vector3(0, 0, -0.5), LACQUER],   # saya
	]


func _samurai_run() -> Animation:
	var base := {"spine": Vector3(-12, 0, 0), "head": Vector3(8, 0, 0),
			"forearm_r": Vector3(50, 0, 0), "forearm_l": Vector3(40, 0, 0)}
	var contact_r := _pose(base, {   # right foot forward, left arm forward
		"chest": Vector3(0, -8, 0), "upper_arm_r": Vector3(15, 0, 10), "upper_arm_l": Vector3(35, 0, -8),
		"thigh_r": Vector3(35, 0, 0), "shin_r": Vector3(-15, 0, 0),
		"thigh_l": Vector3(-30, 0, 0), "shin_l": Vector3(-55, 0, 0), "hips_offset": Vector3(0, -0.03, 0)})
	var pass_l := _pose(base, {
		"upper_arm_r": Vector3(25, 0, 10), "upper_arm_l": Vector3(5, 0, -8),
		"thigh_r": Vector3(0, 0, 0), "shin_r": Vector3(-10, 0, 0),
		"thigh_l": Vector3(15, 0, 0), "shin_l": Vector3(-80, 0, 0), "hips_offset": Vector3(0, 0.03, 0)})
	var contact_l := _pose(base, {
		"chest": Vector3(0, 8, 0), "upper_arm_r": Vector3(35, 0, 10), "upper_arm_l": Vector3(-25, 0, -8),
		"thigh_l": Vector3(35, 0, 0), "shin_l": Vector3(-15, 0, 0),
		"thigh_r": Vector3(-30, 0, 0), "shin_r": Vector3(-55, 0, 0), "hips_offset": Vector3(0, -0.03, 0)})
	var pass_r := _pose(base, {
		"upper_arm_r": Vector3(25, 0, 10), "upper_arm_l": Vector3(5, 0, -8),
		"thigh_l": Vector3(0, 0, 0), "shin_l": Vector3(-10, 0, 0),
		"thigh_r": Vector3(15, 0, 0), "shin_r": Vector3(-80, 0, 0), "hips_offset": Vector3(0, 0.03, 0)})
	return _samurai_clip(0.64, true, [[0.0, contact_r], [0.16, pass_l], [0.32, contact_l], [0.48, pass_r], [0.64, contact_r]])


## The swing shape for each strike; timing comes from its AttackData.
func _attack_clip(attack: AttackData) -> Animation:
	match attack.animation:
		&"attack_1", &"draw_attack":
			return _slash_clip(attack, 1.0)
		&"attack_2", &"heavy_finisher":
			return _slash_clip(attack, -1.0)
		&"attack_3", &"heavy_1":
			return _overhead_clip(attack)
		&"heavy_2":
			return _thrust_clip(attack)
	push_error("No placeholder swing for '%s'" % attack.animation)
	return _slash_clip(attack, 1.0)


## Thrust: draw the blade back at the hip, then drive it straight forward at chest height.
func _thrust_clip(attack: AttackData) -> Animation:
	var chambered := _pose(SLASH_STANCE, {"chest": Vector3(0, -30, 0),
			"upper_arm_r": Vector3(20, 0, 20), "forearm_r": Vector3(100, 0, 0), "weapon_r": Vector3(-100, 0, 0)})
	var coiled := _pose(chambered, {"chest": Vector3(0, -38, 0), "upper_arm_r": Vector3(10, 0, 25)})
	var extended := _pose(SLASH_STANCE, {"spine": Vector3(-22, 0, 0), "chest": Vector3(0, 10, 0),
			"upper_arm_r": Vector3(85, 0, 0), "forearm_r": Vector3(5, 0, 0), "weapon_r": Vector3(-90, 0, 0),
			"thigh_l": Vector3(45, 0, -6), "shin_l": Vector3(-40, 0, 0), "hips_offset": Vector3(0, -0.12, -0.08)})
	var recover := _pose(SAMURAI_IDLE, {"upper_arm_r": Vector3(35, 0, 10), "forearm_r": Vector3(35, 0, 0),
			"weapon_r": Vector3(-40, 0, 0), "hips_offset": Vector3(0, -0.04, 0)})
	var a := attack.active_start
	var b := attack.active_end
	return _samurai_clip(attack.duration, false, [
		[0.0, chambered], [a, coiled], [(a + b) * 0.5, extended], [b, extended], [attack.duration, recover]])


## Dodge: drop low and lean into the dash, then rise back into the guard.
func _dodge_clip(direction: Vector3) -> Animation:
	var lean := Vector3(-direction.z * -25.0, 0.0, -direction.x * 20.0)   # pitch toward travel, roll sideways
	var crouch := _pose(SAMURAI_IDLE, {
		"spine": Vector3(-20, 0, 0) + lean, "chest": Vector3(-10, 0, 0) + lean * 0.5, "head": Vector3(15, 0, 0),
		"upper_arm_r": Vector3(40, 0, 25), "forearm_r": Vector3(60, 0, 0),
		"upper_arm_l": Vector3(30, 0, -30), "forearm_l": Vector3(50, 0, 0),
		"thigh_r": Vector3(55, 0, 8), "shin_r": Vector3(-80, 0, 0),
		"thigh_l": Vector3(40, 0, -8), "shin_l": Vector3(-70, 0, 0),
		"hips_offset": Vector3(0, -0.3, 0)})
	var tucked := _pose(crouch, {"spine": Vector3(-30, 0, 0) + lean, "hips_offset": Vector3(0, -0.36, 0)})
	return _samurai_clip(DODGE_LENGTH, false, [
		[0.0, SAMURAI_IDLE], [0.08, crouch], [0.28, tucked], [DODGE_LENGTH, SAMURAI_IDLE]])


## Horizontal slash. side = +1 sweeps right → left (attack_1), -1 is the backhand (attack_2).
func _slash_clip(attack: AttackData, side: float) -> Animation:
	var stance := SLASH_STANCE if side > 0.0 else _pose(SLASH_STANCE, {
		"thigh_r": Vector3(30, 0, 6), "shin_r": Vector3(-30, 0, 0),
		"thigh_l": Vector3(-20, 0, -6), "shin_l": Vector3(-15, 0, 0)})
	var s := side
	var windup := _pose(stance, {"chest": Vector3(0, -40 * s, 0), "upper_arm_r": Vector3(50, -60 * s, 0), "forearm_r": Vector3(8, 0, 0)})
	var coiled := _pose(stance, {"chest": Vector3(0, -45 * s, 0), "upper_arm_r": Vector3(50, -68 * s, 0), "forearm_r": Vector3(8, 0, 0)})
	var through := _pose(stance, {"chest": Vector3(0, 0, 0), "upper_arm_r": Vector3(55, 0, 0)})
	var follow := _pose(stance, {"chest": Vector3(0, 45 * s, 0), "upper_arm_r": Vector3(50, 65 * s, 0), "forearm_r": Vector3(10, 0, 0)})
	var recover := _pose(SAMURAI_IDLE, {"chest": Vector3(0, 15 * s, 0), "upper_arm_r": Vector3(35, 25 * s, 10),
			"forearm_r": Vector3(30, 0, 0), "weapon_r": Vector3(-40, 0, 0), "hips_offset": Vector3(0, -0.04, 0)})
	var a := attack.active_start
	var b := attack.active_end
	return _samurai_clip(attack.duration, false, [
		[0.0, windup], [a, coiled], [(a + b) * 0.5, through], [b, follow], [attack.duration, recover]])


## Overhead finisher: rise, then cut straight down in front of the feet.
func _overhead_clip(attack: AttackData) -> Animation:
	var raised := {
		"spine": Vector3(6, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-5, 0, 0),
		"upper_arm_r": Vector3(165, 0, 15), "forearm_r": Vector3(15, 0, 0), "weapon_r": Vector3(-90, 0, 0),
		"upper_arm_l": Vector3(160, 0, -15), "forearm_l": Vector3(15, 0, 0),
		"thigh_l": Vector3(20, 0, -6), "shin_l": Vector3(-15, 0, 0),
		"thigh_r": Vector3(-10, 0, 6), "shin_r": Vector3(-10, 0, 0)}
	var peak := _pose(raised, {"chest": Vector3(14, 0, 0), "upper_arm_r": Vector3(175, 0, 12), "upper_arm_l": Vector3(170, 0, -12)})
	var through := _pose(raised, {"spine": Vector3(-5, 0, 0), "chest": Vector3(-10, 0, 0),
			"upper_arm_r": Vector3(100, 0, 8), "upper_arm_l": Vector3(95, 0, -8), "hips_offset": Vector3(0, -0.08, 0)})
	var impact := {
		"spine": Vector3(-18, 0, 0), "chest": Vector3(-22, 0, 0), "head": Vector3(15, 0, 0),
		"upper_arm_r": Vector3(40, 0, 5), "forearm_r": Vector3(5, 0, 0), "weapon_r": Vector3(-90, 0, 0),
		"upper_arm_l": Vector3(40, 0, -5), "forearm_l": Vector3(20, 0, 0),
		"thigh_l": Vector3(45, 0, -6), "shin_l": Vector3(-50, 0, 0),
		"thigh_r": Vector3(-25, 0, 6), "shin_r": Vector3(-35, 0, 0), "hips_offset": Vector3(0, -0.16, 0)}
	var recover := _pose(impact, {"spine": Vector3(-10, 0, 0), "chest": Vector3(-8, 0, 0), "head": Vector3(8, 0, 0),
			"upper_arm_r": Vector3(35, 0, 10), "forearm_r": Vector3(30, 0, 0), "weapon_r": Vector3(-50, 0, 0),
			"upper_arm_l": Vector3(25, 0, -8), "forearm_l": Vector3(40, 0, 0),
			"thigh_l": Vector3(25, 0, -6), "shin_l": Vector3(-25, 0, 0), "hips_offset": Vector3(0, -0.08, 0)})
	var a := attack.active_start
	var b := attack.active_end
	return _samurai_clip(attack.duration, false, [
		[0.0, raised], [a, peak], [(a + b) * 0.5, through], [b, impact], [attack.duration, recover]])


## Flinch: snap back from the blow, then settle into the idle guard.
func _samurai_hurt() -> Animation:
	var recoil := _pose(SAMURAI_IDLE, {
		"spine": Vector3(12, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(15, 0, 0),
		"upper_arm_r": Vector3(5, 0, 30), "forearm_r": Vector3(20, 0, 0),
		"upper_arm_l": Vector3(5, 0, -30), "forearm_l": Vector3(20, 0, 0),
		"hips_offset": Vector3(0, -0.05, 0.05)})
	return _samurai_clip(0.4, false, [[0.0, SAMURAI_IDLE], [0.08, recoil], [0.4, SAMURAI_IDLE]])


## Defeat: knees buckle, then he kneels on the right knee, head bowed (held until respawn).
func _samurai_death() -> Animation:
	var buckle := {
		"spine": Vector3(-15, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-10, 0, 0),
		"upper_arm_r": Vector3(15, 0, 20), "upper_arm_l": Vector3(15, 0, -20),
		"thigh_r": Vector3(30, 0, 5), "shin_r": Vector3(-60, 0, 0),
		"thigh_l": Vector3(45, 0, -5), "shin_l": Vector3(-60, 0, 0), "hips_offset": Vector3(0, -0.2, 0)}
	var kneel := {
		"spine": Vector3(-25, 0, 0), "chest": Vector3(-15, 0, 0), "head": Vector3(-20, 0, 0),
		"upper_arm_r": Vector3(10, 0, 20), "forearm_r": Vector3(10, 0, 0),
		"upper_arm_l": Vector3(40, 0, -10), "forearm_l": Vector3(40, 0, 0),   # hand resting on the knee
		"thigh_r": Vector3(0, 0, 5), "shin_r": Vector3(-90, 0, 0),           # right knee on the ground
		"thigh_l": Vector3(80, 0, -5), "shin_l": Vector3(-80, 0, 0),         # left foot planted
		"hips_offset": Vector3(0, -0.43, 0)}
	return _samurai_clip(1.6, false, [[0.0, SAMURAI_IDLE], [0.35, buckle], [0.9, kneel], [1.6, kneel]])


func _samurai_clip(length: float, loop: bool, keys: Array) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var poses: Array[Dictionary] = []
	for key: Array in keys:
		poses.append(_with_flat_feet(key[1]))
	for bone: String in SAMURAI_ANIMATED:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("Skeleton3D:" + bone))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		for i in keys.size():
			anim.rotation_track_insert_key(track, keys[i][0], _euler(poses[i].get(bone, Vector3.ZERO)))
	var hips := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips, ^"Skeleton3D:hips")
	anim.track_set_interpolation_type(hips, Animation.INTERPOLATION_CUBIC)
	for i in keys.size():
		anim.position_track_insert_key(hips, keys[i][0], HIPS_REST + poses[i].get("hips_offset", Vector3.ZERO))
	return anim


func _samurai_state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	var actions: Array[String] = []
	for path: String in ATTACK_PATHS:
		actions.append(String((load(path) as AttackData).animation))
	actions.append_array(DODGES.keys())
	var states: Array[String] = ["idle", "run"]
	states.append_array(actions)
	states.append_array(["hurt", "death"])
	for i in states.size():
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(states[i])
		machine.add_node(StringName(states[i]), node, Vector2(300 + 220 * (i % 4), 100 + 160 * (i / 4)))
	_link(machine, "Start", "idle", 0.0, true)
	_link(machine, "idle", "run", 0.15)
	_link(machine, "run", "idle", 0.2)
	# Every action (strike or dodge) can start from, chain into, and return to any other state;
	# CombatStateMachine decides what is allowed. Reactions can interrupt anything.
	for action in actions:
		for from: String in ["idle", "run", "hurt"] + actions:
			if from != action:
				_link(machine, from, action, 0.06 if from in actions else 0.08)
		_link(machine, action, "idle", 0.2)
		_link(machine, action, "run", 0.2)
	for from: String in ["idle", "run"] + actions:
		_link(machine, from, "hurt", 0.05)
		_link(machine, from, "death", 0.1)
	_link(machine, "hurt", "idle", 0.15)
	_link(machine, "hurt", "run", 0.15)
	_link(machine, "hurt", "death", 0.1)
	_link(machine, "death", "idle", 0.3)     # respawn
	return machine


func _link(machine: AnimationNodeStateMachine, from: String, to: String, xfade: float, auto := false) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto \
			else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED   # ENABLED: only travel() moves it
	machine.add_transition(StringName(from), StringName(to), transition)


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


## Counter-rotates each foot against its thigh and shin so the sole stays level.
static func _with_flat_feet(pose: Dictionary) -> Dictionary:
	var result := pose.duplicate()
	for side: String in ["r", "l"]:
		if result.has("foot_" + side):
			continue
		var thigh: Vector3 = result.get("thigh_" + side, Vector3.ZERO)
		var shin: Vector3 = result.get("shin_" + side, Vector3.ZERO)
		result["foot_" + side] = Vector3(-(thigh.x + shin.x), 0.0, -thigh.z)
	return result


## Bakes primitive parts into one mesh in skeleton rest space, each vertex fully weighted to its bone.
static func _skinned_mesh(skeleton: Skeleton3D, parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for part: Array in parts:
		var bone := skeleton.find_bone(part[0])
		var xform := skeleton.get_bone_global_rest(bone) * Transform3D(Basis.IDENTITY, part[2])
		var arrays := (part[1] as PrimitiveMesh).get_mesh_arrays()
		var base := verts.size()
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			verts.append(xform * v)
			colors.append(part[3])
			bones.append_array([bone, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			normals.append((xform.basis * n).normalized())
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.85
	mesh.surface_set_material(0, material)
	return mesh


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x, y, z)
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func _cone(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
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
