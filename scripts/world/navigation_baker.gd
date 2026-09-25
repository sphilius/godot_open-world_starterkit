extends NavigationRegion3D
## Bakes this region's navmesh at startup, on a worker thread, from the procedural terrain
## and landmarks (nodes in the NavigationMesh's source group). Mobs idle until it lands.
##
## To ship a pre-baked mesh instead: select this node in the editor and click
## "Bake NavigationMesh" (Terrain is @tool, so its collider exists there), then untick `bake_on_ready`.

@export var terrain: HeightmapTerrain
@export var bake_on_ready := true


func _ready() -> void:
	if not bake_on_ready:
		return
	terrain.ensure_generated()
	await get_tree().process_frame                     # landmarks and colliders all exist by now
	var started := Time.get_ticks_msec()
	bake_finished.connect(func() -> void:
		print("Navmesh baked in %d ms (%d polygons)" % [
			Time.get_ticks_msec() - started, navigation_mesh.get_polygon_count()]),
		CONNECT_ONE_SHOT)
	bake_navigation_mesh(true)
