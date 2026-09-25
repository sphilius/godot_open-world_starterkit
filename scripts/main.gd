extends Node3D
## Scene bootstrap: once the procedural world exists, drop the player at the start of the
## scenic path, facing along it (toward the sunset).
##
## Command line (after `--`):  --spawn-offset=<metres along the path>

@export var terrain: HeightmapTerrain
@export var scenic_path: ScenicPath
@export var player: PlayerController
## Metres along the path where the player starts.
@export var spawn_offset := 1.0


func _ready() -> void:
	terrain.ensure_generated()
	var offset := spawn_offset
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn-offset="):
			offset = arg.get_slice("=", 1).to_float()
	var spawn := scenic_path.ground_transform_at(offset)
	player.spawn_at(spawn.origin + Vector3.UP * 0.1, spawn.basis.get_euler().y)
