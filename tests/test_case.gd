extends RefCounted
## Base class for the headless integration tests run by res://tests/run_tests.gd.
##
## A test file extends this script and defines `test_*` methods (they may `await`). Each test
## method runs on its own instance. World-level tests start with `await load_world()` to get a
## fresh copy of the main scene; component tests build only what they need with add_to_stage().
## Checks record failures instead of stopping, so one run reports everything that broke.

const MAIN_SCENE := "res://scenes/main.tscn"

## Set by the runner.
var tree: SceneTree
var world: Node
## Holds whatever add_to_stage() adds; freed with the world after the test.
var stage: Node3D
var failures: PackedStringArray = []


# --- Checks --------------------------------------------------------------------------------

func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func check_eq(actual: Variant, expected: Variant, what: String) -> bool:
	return check(actual == expected, "%s: expected %s, got %s" % [what, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, what: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
			"%s: expected %s ± %s, got %s" % [what, expected, tolerance, actual])


# --- Time ----------------------------------------------------------------------------------

func seconds(duration: float) -> void:
	var end := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < end:
		await tree.process_frame


func physics_frames(count := 2) -> void:
	for i in count:
		await tree.physics_frame


## Waits until `condition` returns true or `timeout` seconds pass. Returns the final result.
func wait_until(condition: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await tree.process_frame
	return condition.call()


# --- World ---------------------------------------------------------------------------------

## Instances the main scene with seeded randomness and sparse grass (grass isn't under test,
## and full density costs ~1 s per load), then waits for the navmesh bake.
func load_world() -> void:
	seed(20260925)
	world = (load(MAIN_SCENE) as PackedScene).instantiate()
	(world.get_node("GrassField") as GrassField).blades_per_square_metre = 1.0
	tree.root.add_child(world)
	await tree.process_frame
	var region := world.get_node("NavigationRegion3D") as NavigationRegion3D
	var baked := func() -> bool:
		return NavigationServer3D.map_get_iteration_id(region.get_navigation_map()) > 0 and region.navigation_mesh.get_polygon_count() > 0
	check(await wait_until(baked, 10.0), "navmesh never finished baking")


## Adds `node` to a bare Node3D stage in the running tree, so `_ready()`, physics and Area3D
## overlaps work without loading the whole world. Returns `node`.
func add_to_stage(node: Node) -> Node:
	if not is_instance_valid(stage):
		stage = Node3D.new()
		stage.name = "TestStage"
		tree.root.add_child(stage)
	stage.add_child(node)
	return node


## Called by the runner after every test: frees the world and undoes global side effects.
func free_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
		world = null
	if is_instance_valid(stage):
		stage.queue_free()
		stage = null
	HitStop._token += 1                      # cancel any pending hit-stop restore
	TimeScale.reset()                        # never write Engine.time_scale directly: TimeScale owns it
	for action in InputMap.get_actions():
		Input.action_release(action)
	await tree.process_frame


# --- Scene helpers -------------------------------------------------------------------------

func player() -> PlayerController:
	return world.get_node("Player")


func combat() -> CombatStateMachine:
	return world.get_node("Player/Combat")


func wolf(wolf_name: String) -> Wolf:
	return world.get_node("Wolves/" + wolf_name)


## Puts the player `distance` metres north of `target`, facing it (south).
func place_player_near(target: Node3D, distance: float) -> void:
	var spot := target.global_position + Vector3(0.0, 0.0, -distance)
	spot.y = (world.get_node("Terrain") as HeightmapTerrain).height_at(spot.x, spot.z) + 0.1
	player().spawn_at(spot, PI)


## A buffered attack press, exactly as CombatStateMachine records one.
func press_attack() -> void:
	combat()._press_msec = Time.get_ticks_msec()
