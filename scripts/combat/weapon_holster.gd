class_name WeaponHolster
extends Node
## Moves the katana between two BoneAttachment3D sockets: the hand bone (drawn) and the
## back-scabbard bone (sheathed). It reparents while keeping the world transform, then tweens
## the local position and rotation to the new socket, so the blade travels instead of teleporting.

signal drawn
signal sheathed

@export var katana: Node3D
@export var hand_socket: BoneAttachment3D
@export var back_socket: BoneAttachment3D
## Fast, so the blade is in hand before the first active frame.
@export var draw_time := 0.12
@export var sheathe_time := 0.45
@export var start_sheathed := true

var _drawn := false
var _tween: Tween


func _ready() -> void:
	_drawn = not start_sheathed
	# Deferred: the player is still adding its children, so nothing can be reparented yet.
	_snap_to.call_deferred(hand_socket if _drawn else back_socket)


func is_drawn() -> bool:
	return _drawn


func draw() -> void:
	if _drawn:
		return
	_drawn = true
	_move_to(hand_socket, draw_time)
	drawn.emit()


func sheathe() -> void:
	if not _drawn:
		return
	_drawn = false
	_move_to(back_socket, sheathe_time)
	sheathed.emit()


func _snap_to(socket: Node3D) -> void:
	katana.reparent(socket, false)
	katana.transform = Transform3D.IDENTITY
	katana.reset_physics_interpolation()


func _move_to(socket: Node3D, duration: float) -> void:
	if _tween:
		_tween.kill()
	katana.reparent(socket, true)          # same world pose, new parent space
	katana.reset_physics_interpolation()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS) \
			.set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(katana, ^"position", Vector3.ZERO, duration)
	_tween.tween_property(katana, ^"quaternion", Quaternion.IDENTITY, duration)   # slerp, no shear
