class_name SurfaceFoley
extends Node3D
## Footsteps (M9b). Until the M2 animations call step() from their method tracks, steps fire
## from distance travelled on the ground: every `walk_stride` metres, or `run_stride` above
## `run_speed`. Each step looks at what's underfoot:
##   the terrain      → gravel on the path (HeightmapTerrain.path_mask_at above 0.5), grass off it
##   anything else    → its "surface" metadata (grass, gravel, stone, wood), or stone
## and plays step_<surface> through the SfxPool. Landing after `landing_air_time` seconds in the
## air plays a louder step.

@export var body: CharacterBody3D
@export var walk_stride := 0.75
@export var run_stride := 1.1
@export var run_speed := 6.0
@export var landing_air_time := 0.35
@export var volume_db := -4.0

## The surface of the last step (for tests and debugging).
var last_surface := &""
var steps := 0
var _travelled := 0.0
var _air_time := 0.0


func _physics_process(delta: float) -> void:
	if body == null:
		return
	if not body.is_on_floor():
		_air_time += delta
		return
	if _air_time > landing_air_time:
		step(4.0)
		_travelled = 0.0
	_air_time = 0.0
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	_travelled += speed * delta
	var stride := run_stride if speed > run_speed else walk_stride
	if _travelled >= stride:
		_travelled -= stride
		step()


## Plays one footstep for whatever is underfoot (animation method tracks can call this).
func step(extra_db := 0.0) -> void:
	var surface := surface_under(body.global_position if body else global_position)
	last_surface = surface
	steps += 1
	var pool := SfxPool.find(get_tree())
	if pool:
		pool.play(StringName("step_" + String(surface)), global_position, volume_db + extra_db, randf_range(0.94, 1.06))


## The surface under `feet`: a ray 0.4 m up to 0.6 m down on the world layer.
func surface_under(feet: Vector3) -> StringName:
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.4, feet + Vector3.DOWN * 0.6, 1)
	if body:
		query.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return &"grass"
	return classify(hit.collider, hit.position)


## The surface of `collider` at `point` (see the class notes).
static func classify(collider: Object, point: Vector3) -> StringName:
	if collider is HeightmapTerrain:
		return &"gravel" if (collider as HeightmapTerrain).path_mask_at(point.x, point.z) > 0.5 else &"grass"
	if collider and collider.has_meta(&"surface"):
		return StringName(collider.get_meta(&"surface"))
	return &"stone"
