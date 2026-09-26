extends "res://tests/test_case.gd"
## M8 level assembly: flatten zones, greybox arenas and gates, the Encounter wave flow (on a
## bare stage), and the courtyard ambush and sanctum boss in the real world.

const GRUNT := preload("res://scenes/mobs/enemy_grunt.tscn")
const COURTYARD_CENTRE := Vector3(-6, 1, -80)
const SANCTUM_CENTRE := Vector3(26, 1, -80)


# --- Encounter on a bare stage ------------------------------------------------------------------

func test_waves_follow_each_other_and_clearing_opens_the_exit() -> void:
	var player := await _stage_player()
	var setup := _stage_encounter([[GRUNT, GRUNT], [GRUNT]])
	var encounter: Encounter = setup[0]
	var entry: LevelGate = setup[1]
	var exit: LevelGate = setup[2]
	var events: Array = []
	encounter.wave_started.connect(func(index: int) -> void: events.append("wave %d" % index))
	encounter.cleared.connect(func() -> void: events.append("cleared"))
	check(entry.is_open and not exit.is_open, "gates before the fight")
	encounter.start(player)
	check_eq(encounter.state, Encounter.State.ACTIVE, "state after start")
	check(not entry.is_open, "the entry gate closed behind the player")
	check_eq(encounter.alive_enemies().size(), 2, "wave 1 size")
	for enemy in encounter.alive_enemies():
		check((enemy as EnemyCombatController).director == encounter.director, "spawned enemies use the encounter's director")
	_kill_all(encounter, player)
	check_eq(encounter.alive_enemies().size(), 0, "wave 1 dead")
	check(await wait_until(func() -> bool: return encounter.alive_enemies().size() == 1, 3.0), "wave 2 never arrived")
	_kill_all(encounter, player)
	await physics_frames(1)
	check_eq(encounter.state, Encounter.State.CLEARED, "state after the last wave")
	check(entry.is_open and exit.is_open, "both gates open once cleared")
	check_eq(events, ["wave 0", "wave 1", "cleared"], "event order")


func test_reset_despawns_and_cancels_a_pending_wave() -> void:
	var player := await _stage_player()
	var setup := _stage_encounter([[GRUNT], [GRUNT]])
	var encounter: Encounter = setup[0]
	var entry: LevelGate = setup[1]
	encounter.start(player)
	_kill_all(encounter, player)                         # wave 2 is now pending (wave_delay)
	encounter.reset()
	check_eq(encounter.state, Encounter.State.IDLE, "state after reset")
	check(entry.is_open, "the entry gate reopened")
	await seconds(encounter.wave_delay + 0.3)
	check_eq(encounter.alive_enemies().size(), 0, "the pending wave was cancelled")
	encounter.start(player)
	check_eq(encounter.wave_index, 0, "a restart begins at wave 1")
	encounter.reset()
	await physics_frames(2)
	var living := stage.find_children("*", "EnemyCombatController", true, false).filter(
			func(enemy: Node) -> bool: return (enemy as EnemyCombatController).state != EnemyCombatController.State.DEAD)
	check(living.is_empty(), "reset freed every living enemy (%d left); corpses sink on their own" % living.size())


func test_the_player_dying_resets_an_active_encounter() -> void:
	var player := await _stage_player()
	var setup := _stage_encounter([[GRUNT]])
	var encounter: Encounter = setup[0]
	encounter.start(player)
	(player.get_node("HealthComponent") as HealthComponent).take_damage(HitInfo.new(9999.0))
	await physics_frames(2)
	check_eq(encounter.state, Encounter.State.IDLE, "a death mid-fight resets it")


func test_gates_block_when_closed() -> void:
	var gate := LevelGate.new()
	gate.start_open = false
	add_to_stage(gate)
	await physics_frames(1)
	var shape := gate.get_node("CollisionShape3D") as CollisionShape3D
	check(not gate.is_open and not shape.disabled, "a closed gate collides")
	gate.open(true)
	await physics_frames(1)
	check(gate.is_open and shape.disabled, "an open gate doesn't")
	check((gate.get_node("Bars") as Node3D).position.y > gate.height, "its bars are raised clear")


func test_greybox_walls_leave_their_openings() -> void:
	var arena := GreyboxArena.new()
	arena.size = Vector2(10, 10)
	arena.openings = [Vector3(0, 0, 4)] as Array[Vector3]
	arena.pillar_spacing = -1.0
	add_to_stage(arena)
	await physics_frames(2)
	var space := arena.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -8), Vector3(0, 1, 0))
	check(space.intersect_ray(ray).is_empty(), "nothing blocks the north opening")
	ray = PhysicsRayQueryParameters3D.create(Vector3(3.5, 1, -8), Vector3(3.5, 1, 0))
	check(not space.intersect_ray(ray).is_empty(), "the north wall blocks beside the opening")
	ray = PhysicsRayQueryParameters3D.create(Vector3(0, 1, 8), Vector3(0, 1, 0))
	check(not space.intersect_ray(ray).is_empty(), "the south wall is solid")


# --- In the world -------------------------------------------------------------------------------

func test_the_arenas_sit_on_level_ground_and_the_navmesh() -> void:
	await load_world()
	var terrain := world.get_node("Terrain") as HeightmapTerrain
	for centre in [COURTYARD_CENTRE, SANCTUM_CENTRE]:
		for offset in [Vector3.ZERO, Vector3(8, 0, 8), Vector3(-8, 0, 6)]:
			var p: Vector3 = centre + offset
			check_near(terrain.height_at(p.x, p.z), 1.0, 0.05, "ground under the arena at %s" % p)
			check(terrain.path_mask_at(p.x, p.z) > 0.99, "no grass inside the arena at %s" % p)
	check(world.get_node("Courtyard/EntryGate").is_open, "the courtyard's entry gate (facing the path) starts open")
	check(not world.get_node("Courtyard/EastGate").is_open, "its east gate starts closed")
	check(world.get_node("Sanctum/SanctumGate").is_open, "the sanctum gate starts open")
	var map := (world.get_node("NavigationRegion3D") as NavigationRegion3D).get_navigation_map()
	var on_floor := func() -> bool:                      # the bake lands on the map a frame or two later
		var point := NavigationServer3D.map_get_closest_point(map, COURTYARD_CENTRE + Vector3(4, 0.5, 4))
		return point.distance_to(COURTYARD_CENTRE + Vector3(4, 0, 4)) < 0.6
	check(await wait_until(on_floor, 3.0), "the courtyard floor is on the navmesh")
	var goal := COURTYARD_CENTRE + Vector3(0, 0, -4)
	var path := NavigationServer3D.map_get_path(map, Vector3(-6, 0, -63), goal, true)
	check(not path.is_empty() and path[path.size() - 1].distance_to(goal) < 1.0, "the path's end leads into the courtyard")
	var gate := COURTYARD_CENTRE + Vector3(0, 0, 12)
	var through_gate := Array(path).any(func(point: Vector3) -> bool:
		return Vector2(point.x - gate.x, point.z - gate.z).length() < 3.0)
	check(through_gate or path.size() == 2, "and that route runs through the entry gate, not around")


func test_walking_off_the_end_of_the_path_enters_the_courtyard() -> void:
	await load_world()
	var encounter := world.get_node("Courtyard/Encounter") as Encounter
	var terrain := world.get_node("Terrain") as HeightmapTerrain
	var start := Vector3(-6, 0, -61)
	start.y = terrain.height_at(start.x, start.z) + 0.1
	player().spawn_at(start, 0.0)                        # facing -Z, down the path toward the courtyard
	Input.action_press(&"move_forward")
	var entered := await wait_until(func() -> bool: return encounter.state == Encounter.State.ACTIVE, 6.0)
	Input.action_release(&"move_forward")
	check(entered, "walking straight off the path's end never reached the courtyard trigger (stuck at %s)" % player().global_position)
	check(not world.get_node("Courtyard/EntryGate").is_open, "the entry gate closed behind the player")


func test_the_courtyard_ambush_runs_its_three_waves() -> void:
	await load_world()
	var encounter := world.get_node("Courtyard/Encounter") as Encounter
	var health := player().get_node("HealthComponent") as HealthComponent
	health.grant_invulnerability(999.0)                  # this test is about the waves, not survival
	var sizes: Array = []
	encounter.wave_started.connect(func(_index: int) -> void: sizes.append(encounter.alive_enemies().size()))
	player().spawn_at(COURTYARD_CENTRE + Vector3(0, 0.3, 6), PI)
	check(await wait_until(func() -> bool: return encounter.state == Encounter.State.ACTIVE, 2.0), "walking in never started the ambush")
	check(not world.get_node("Courtyard/EntryGate").is_open, "the entry gate slammed shut")
	for wave in 3:
		check(await wait_until(func() -> bool: return encounter.wave_index == wave and not encounter.alive_enemies().is_empty(), 4.0),
				"wave %d never arrived" % (wave + 1))
		check(await wait_until(func() -> bool:
			return encounter.alive_enemies().all(func(e: Node) -> bool: return (e as EnemyCombatController).is_on_floor()), 3.0),
			"wave %d didn't land on the courtyard floor" % (wave + 1))
		check(encounter.director.token_count() <= 2, "at most 2 attackers")
		_kill_all(encounter, player())
	check_eq(sizes, [3, 4, 4], "wave sizes (3 grunts; 3 grunts + a brute; 2 brutes + 2 grunts)")
	check(await wait_until(func() -> bool: return encounter.state == Encounter.State.CLEARED, 2.0), "the courtyard never cleared")
	check(world.get_node("Courtyard/EastGate").is_open, "the way to the sanctum opened")


func test_the_sanctum_seals_the_player_in_with_the_gatekeeper() -> void:
	await load_world()
	var encounter := world.get_node("Sanctum/Encounter") as Encounter
	var hud := world.get_node("PlayerHUD") as PlayerHUD
	(player().get_node("HealthComponent") as HealthComponent).grant_invulnerability(999.0)
	player().spawn_at(SANCTUM_CENTRE + Vector3(-5, 0.3, 0), -PI * 0.5)
	check(await wait_until(func() -> bool: return encounter.state == Encounter.State.ACTIVE, 2.0), "the boss fight never started")
	check(not world.get_node("Sanctum/SanctumGate").is_open, "the sanctum gate closed")
	var boss := encounter.alive_enemies()[0] as Gatekeeper
	check(boss != null, "the Gatekeeper spawned")
	check(await wait_until(func() -> bool: return hud.showing_boss() == boss, 3.0), "the boss bar never appeared")
	_kill_all(encounter, player())
	check(await wait_until(func() -> bool: return encounter.state == Encounter.State.CLEARED, 2.0), "the sanctum never cleared")
	check(world.get_node("Sanctum/SanctumGate").is_open, "the gate reopened")


# --- Helpers ------------------------------------------------------------------------------------

## [Encounter, entry gate, exit gate] on a flat stage, with the given waves (arrays of scenes).
func _stage_encounter(wave_scenes: Array) -> Array:
	var entry := LevelGate.new()
	entry.position = Vector3(0, 0, 6)
	add_to_stage(entry)
	var exit := LevelGate.new()
	exit.position = Vector3(0, 0, -20)
	add_to_stage(exit)
	var encounter := Encounter.new()
	encounter.wave_delay = 0.3
	for scenes: Array in wave_scenes:
		var wave := EncounterWave.new()
		for scene: PackedScene in scenes:
			wave.enemies.append(scene)
		encounter.waves.append(wave)
	encounter.entry_gates = [entry] as Array[LevelGate]
	encounter.exit_gates = [exit] as Array[LevelGate]
	var points := Node3D.new()
	points.name = "SpawnPoints"
	encounter.add_child(points)
	for x in [-3.0, 3.0]:
		var marker := Marker3D.new()
		marker.position = Vector3(x, 0.05, -8)
		points.add_child(marker)
	add_to_stage(encounter)
	return [encounter, entry, exit]


func _kill_all(encounter: Encounter, killer: Node3D) -> void:
	for enemy in encounter.alive_enemies():
		(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(CombatFixtures.make_hit(killer, 99999.0, 0.0))


## Floor plus a player at the origin facing -Z.
func _stage_player() -> PlayerController:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_to_stage(floor_body)
	var player: PlayerController = CombatFixtures.PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_to_stage(player)
	await physics_frames(3)
	return player
