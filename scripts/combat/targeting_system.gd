class_name TargetingSystem
extends Node
## Hard lock-on.
##
## lock_on (MMB / Q / right-stick click / LOCK) toggles. Any enemy (group "enemies") within
## `radius` can be locked, whichever way the player faces and whatever stands between them:
## the one closest to the centre of view inside the `cone_degrees` cone around the camera's
## forward direction, or else the nearest one. While locked:
## • target_next / target_prev (mouse wheel, NEXT button) or a right-stick flick switch to the
##   nearest enemy to the right or left of the current one on screen;
## • if the target dies (leaves the group), is freed or gets farther than `break_distance`, the
##   lock moves straight to the nearest enemy in reach, or releases when there is none.
## The target glows with a faint pulsing red rim (shaders/lock_on_outline.gdshader, as a
## material_overlay on its meshes); pulse() flares it on a hit or parry. The camera, dodges
## and lunges read `current_target`.

signal target_changed(target: Node3D)

## Meta flag on the meshes wearing the lock-on highlight.
const HIGHLIGHT_META := &"lock_on_highlight"

@export var body: PlayerController
@export var camera: CombatCamera
## Combat range: the farthest an enemy can be to get locked (m).
@export var radius := 18.0
## Full angle of the cone around the camera's forward direction where the most centred enemy
## wins. Outside it, the nearest enemy in range is locked instead.
@export_range(1.0, 360.0) var cone_degrees := 70.0
## A lock releases (or moves on) past this distance (m).
@export var break_distance := 24.0
## Height above a target's origin used to place it on screen when cycling (m).
@export var aim_height := 0.7
## The lock-on highlight drawn over the target's meshes.
@export var highlight: ShaderMaterial = preload("res://resources/materials/lock_on_outline.tres")
## Enemies whose angles off the view centre differ by less than this count as equally
## centred, and the nearer one wins.
@export var tie_degrees := 2.0
## Right-stick flick: past `x` it switches target; it must fall back under `y` before the next.
@export var flick_thresholds := Vector2(0.7, 0.3)

var current_target: Node3D
var _flick_ready := true
## The meshes carrying the highlight (the current target's).
var _highlighted: Array = []
var _flare: Tween


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"lock_on"):
		toggle_lock()
	elif event.is_action_pressed(&"target_next"):
		cycle(1)
	elif event.is_action_pressed(&"target_prev"):
		cycle(-1)


## Flares the highlight (boost 0 → 1.2 → 0 over 0.25 s) to confirm a hit or parry on the target.
func pulse() -> void:
	if not is_locked() or highlight == null:
		return
	if _flare:
		_flare.kill()
	_flare = create_tween()
	_flare.tween_property(highlight, ^"shader_parameter/boost", 1.2, 0.05)
	_flare.tween_property(highlight, ^"shader_parameter/boost", 0.0, 0.2)


## The meshes wearing the lock-on highlight (empty when unlocked).
func highlighted_meshes() -> Array[GeometryInstance3D]:
	var meshes: Array[GeometryInstance3D] = []
	for mesh: Variant in _highlighted:                     # Variant: some may have been freed
		if is_instance_valid(mesh):
			meshes.append(mesh)
	return meshes


func is_locked() -> bool:
	return is_instance_valid(current_target)


func toggle_lock() -> void:
	if is_locked():
		set_target(null)
	else:
		set_target(find_best_target())


func set_target(target: Node3D) -> void:
	if is_same(target, current_target):          # is_same: a freed target equals null under ==
		return
	current_target = target if is_instance_valid(target) else null
	_set_highlight(current_target)
	target_changed.emit(current_target)


## The enemy nearest the centre of view inside the cone, else the nearest one, within `radius`;
## null when there's nobody in range.
func find_best_target(exclude: Node3D = null) -> Node3D:
	var forward := _view_forward()
	var min_dot := cos(deg_to_rad(cone_degrees * 0.5))
	var tie := deg_to_rad(tie_degrees)
	var best: Node3D
	var best_angle := INF
	var best_distance := INF
	for enemy in _candidates(exclude):
		var to_enemy := _flat(enemy.global_position - body.global_position)
		var distance := to_enemy.length()
		var dot := forward.dot(to_enemy / distance) if distance > 0.01 else 1.0
		if dot < min_dot:
			continue
		# Angle first; distance only breaks near-ties.
		var angle := acos(clampf(dot, -1.0, 1.0))
		if angle < best_angle - tie or (absf(angle - best_angle) <= tie and distance < best_distance):
			best = enemy
			best_angle = angle
			best_distance = distance
	return best if best else find_nearest_target(exclude)


## The nearest enemy within `radius`, in any direction, or null.
func find_nearest_target(exclude: Node3D = null) -> Node3D:
	var best: Node3D
	var best_distance := INF
	for enemy in _candidates(exclude):
		var distance := _flat(enemy.global_position - body.global_position).length()
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


## Switch to the nearest visible enemy to the right (direction > 0) or left of the current one,
## by screen position. Does nothing when unlocked or when there is nobody on that side.
func cycle(direction: int) -> void:
	if not is_locked():
		return
	var view := camera.camera
	var current_x := view.unproject_position(_aim_point(current_target)).x
	var best: Node3D
	var best_gap := INF
	for enemy in _candidates(current_target):
		var point := _aim_point(enemy)
		if view.is_position_behind(point):
			continue
		var gap := (view.unproject_position(point).x - current_x) * signf(direction)
		if gap > 0.0 and gap < best_gap:
			best = enemy
			best_gap = gap
	if best:
		set_target(best)


func _process(_delta: float) -> void:
	if is_locked():
		_poll_stick_flick()


func _physics_process(_delta: float) -> void:
	if is_same(current_target, null):
		return
	if not is_instance_valid(current_target):              # freed (a fight reset): typed calls would fail
		set_target(find_nearest_target())
	elif not _still_valid(current_target):
		set_target(find_nearest_target(current_target))    # the target fell: straight to the next


func _poll_stick_flick() -> void:
	if not InputMap.has_action(&"look_left"):
		return
	var x := Input.get_axis(&"look_left", &"look_right")
	if _flick_ready and absf(x) > flick_thresholds.x:
		_flick_ready = false
		cycle(int(signf(x)))
	elif absf(x) < flick_thresholds.y:
		_flick_ready = true


## Moves the highlight overlay to `target`'s meshes (skipping the telegraph glint's). Each
## highlighted mesh carries the HIGHLIGHT_META flag, so a hit flash that swaps the overlay out
## for a moment (Wolf) only puts the highlight back while the lock still owns it.
func _set_highlight(target: Node3D) -> void:
	for mesh in highlighted_meshes():
		mesh.remove_meta(HIGHLIGHT_META)
		if mesh.material_overlay == highlight:
			mesh.material_overlay = null
	_highlighted.clear()
	if target == null or highlight == null:
		return
	for node in target.find_children("*", "GeometryInstance3D", true, false):
		var mesh := node as GeometryInstance3D
		if mesh is MeshInstance3D and not _is_glint(mesh) and mesh.material_overlay == null:
			mesh.material_overlay = highlight
			mesh.set_meta(HIGHLIGHT_META, true)
			_highlighted.append(mesh)


static func _is_glint(node: Node) -> bool:
	while node:
		if node is TelegraphGlint:
			return true
		node = node.get_parent()
	return false


## Live enemies within `radius`.
func _candidates(exclude: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in body.get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy) or is_same(enemy, exclude):
			continue
		if _flat(enemy.global_position - body.global_position).length() <= radius:
			found.append(enemy)
	return found


func _still_valid(target: Node3D) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and target.is_in_group(&"enemies") \
			and _flat(target.global_position - body.global_position).length() <= break_distance


func _aim_point(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * aim_height


func _view_forward() -> Vector3:
	var forward := _flat(-camera.global_basis.z) if camera else Vector3.ZERO
	if forward.length_squared() < 0.0001:
		forward = body.get_facing()
	return forward.normalized()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
