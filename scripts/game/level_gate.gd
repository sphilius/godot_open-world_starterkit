@tool
class_name LevelGate
extends StaticBody3D
## Portcullis that seals an arena opening. Closed, it blocks (world layer); open, it's raised
## out of the way and doesn't collide. Encounter closes it behind the player and opens the way
## on when a fight is cleared. Built in code (bars) until the M2 kit's Gate_Courtyard lands.

signal opened
signal closed
## A tweened move began (not an instant set): the portcullis sound (M9b).
signal moving(opening: bool)

@export var width := 4.0
@export var height := 3.2
## Seconds the portcullis takes to drop or rise.
@export var travel_time := 0.45
@export var start_open := true
@export var metal := Color(0.22, 0.2, 0.19)

var is_open := true
var _bars: Node3D
var _shape: CollisionShape3D
var _tween: Tween


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()
	is_open = not start_open                            # force the first set_open to apply
	set_open(start_open, true)


func open(instant := false) -> void:
	set_open(true, instant)


func close(instant := false) -> void:
	set_open(false, instant)


func set_open(on: bool, instant := false) -> void:
	if on == is_open:
		return
	is_open = on
	_shape.set_deferred(&"disabled", on)
	var target := Vector3(0, height + 0.2 if on else 0.0, 0)
	if _tween:
		_tween.kill()
	if instant or not is_inside_tree():
		_bars.position = target
	else:
		moving.emit(on)
		_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_tween.tween_property(_bars, ^"position", target, travel_time).set_trans(Tween.TRANS_QUAD) \
				.set_ease(Tween.EASE_IN if not on else Tween.EASE_OUT)
	if on:
		opened.emit()
	else:
		closed.emit()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var material := StandardMaterial3D.new()
	material.albedo_color = metal
	material.metallic = 0.6
	material.roughness = 0.55
	_bars = Node3D.new()
	_bars.name = "Bars"
	add_child(_bars)
	var count := maxi(int(width / 0.45), 2)
	for i in count + 1:
		var x := -width * 0.5 + width * i / count
		_bar(Vector3(0.09, height, 0.09), Vector3(x, height * 0.5, 0), material)
	for y in [0.4, height * 0.5, height - 0.3]:
		_bar(Vector3(width, 0.1, 0.12), Vector3(0, y, 0), material)
	_shape = CollisionShape3D.new()
	_shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.5)
	_shape.shape = box
	_shape.position = Vector3(0, height * 0.5, 0)
	add_child(_shape)


func _bar(dims: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dims
	box.material = material
	mesh.mesh = box
	mesh.position = at
	_bars.add_child(mesh)
