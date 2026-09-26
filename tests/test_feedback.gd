extends "res://tests/test_case.gd"
## M9b feedback: the SFX voice pool, footstep surfaces, camera trauma, hit sound/sparks/shake,
## music per beat and the lock-on gauge.

const BANK := preload("res://resources/audio/sound_bank.tres")


func test_the_voice_pool_steals_the_oldest_voice() -> void:
	var pool := SfxPool.new()
	pool.bank = BANK
	pool.voices = 3
	add_to_stage(pool)
	var first := pool.play(&"parry", Vector3.ZERO)
	for event in [&"parry", &"posture_break"]:
		await seconds(0.02)
		pool.play(event, Vector3.ZERO)
	check_eq(pool.busy_voices(), 3, "three sounds, three voices")
	await seconds(0.02)
	check(pool.play(&"roar", Vector3.ZERO) == first, "a fourth sound takes the oldest voice")
	check(pool.play(&"no_such_event", Vector3.ZERO) == null, "unknown events play nothing")
	for event in BANK.sounds:
		check(BANK.get_sound(event) != null, "the bank's %s sound loads" % event)


func test_footsteps_know_the_surface_underfoot() -> void:
	await load_world()
	var terrain := world.get_node("Terrain") as HeightmapTerrain
	var path := world.get_node("ScenicPath") as ScenicPath
	var on_path := path.ground_transform_at(30.0).origin
	check_eq(SurfaceFoley.classify(terrain, on_path), &"gravel", "the path is gravel")
	var off_path := on_path + Vector3(30, 0, 0)
	check(terrain.path_mask_at(off_path.x, off_path.z) < 0.5, "test point is off the path")
	check_eq(SurfaceFoley.classify(terrain, off_path), &"grass", "off the path is grass")
	var plank := StaticBody3D.new()
	plank.set_meta(&"surface", &"wood")
	check_eq(SurfaceFoley.classify(plank, Vector3.ZERO), &"wood", "surface metadata wins")
	var slab := StaticBody3D.new()
	check_eq(SurfaceFoley.classify(slab, Vector3.ZERO), &"stone", "other ground is stone")
	plank.free()
	slab.free()

	var foley := player().get_node("SurfaceFoley") as SurfaceFoley
	player().spawn_at(on_path + Vector3.UP * 0.1, path.ground_transform_at(30.0).basis.get_euler().y)
	await physics_frames(5)
	var before := foley.steps
	Input.action_press(&"move_forward")
	await seconds(1.5)
	Input.action_release(&"move_forward")
	check(foley.steps - before >= 3, "walking plays footsteps (%d)" % (foley.steps - before))
	check_eq(foley.last_surface, &"gravel", "on the path they sound like gravel")


func test_camera_trauma_clamps_squares_and_decays_in_real_time() -> void:
	var camera := Camera3D.new()
	var trauma := CameraTrauma.new()
	camera.add_child(trauma)
	add_to_stage(camera)
	trauma.add_trauma(0.3)
	trauma.add_trauma(0.3)
	check_near(trauma.trauma, 0.6, 0.001, "trauma adds up")
	check_near(trauma.shake(), 0.36, 0.001, "shake is trauma squared")
	trauma.add_trauma(1.0)
	check_eq(trauma.trauma, 1.0, "trauma is clamped to 1")
	TimeScale.push(&"test_freeze", 0.0)                          # a hit-stop freezes game time...
	await seconds(0.3)
	TimeScale.pop(&"test_freeze")
	check(trauma.trauma < 0.7, "...but the shake still decays (%.2f)" % trauma.trauma)
	check(camera.h_offset != 0.0 or camera.v_offset != 0.0, "the camera shook")
	CameraTrauma.enabled = false
	trauma.trauma = 0.0
	trauma.add_trauma(0.5)
	CameraTrauma.enabled = true
	check_eq(trauma.trauma, 0.0, "screen shake off ignores trauma")


func test_hits_make_sound_sparks_and_shake() -> void:
	await load_world()
	var pool := world.get_node("SfxPool") as SfxPool
	var trauma := CameraTrauma.find(tree)
	var target := wolf("Wolf1")
	place_player_near(target, 2.0)
	await physics_frames(3)
	var hit := CombatFixtures.make_hit(player(), 5.0, 0.0)
	hit.hit_position = target.global_position + Vector3.UP
	var sparks_before := HitVfx.live
	(target.get_node("Hurtbox") as Hurtbox).receive_hit(hit)
	check(pool.busy_voices() >= 1, "the hit made a sound")
	check(HitVfx.live > sparks_before, "the hit threw sparks")
	check(trauma.trauma > 0.0, "the player's hit shook the camera")
	trauma.trauma = 0.0
	(player().get_node("Hurtbox") as Hurtbox).receive_hit(CombatFixtures.make_hit(target, 5.0, 0.0))
	check_near(trauma.trauma, CameraTrauma.HURT, 0.05, "being hit shakes harder")
	var katana := combat().katana                                  # the holster reparents it to a socket
	var voices := pool.busy_voices()
	katana.hitbox.begin(load("res://resources/combat/attack_1.tres"))
	katana.hitbox.set_active(true)
	check(pool.busy_voices() > voices, "a swing whooshes")
	katana.hitbox.set_active(false)
	check(await wait_until(func() -> bool: return HitVfx.live == sparks_before, 2.0), "sparks clean themselves up")


func test_music_and_reverb_follow_the_beats() -> void:
	await load_world()
	var music := world.get_node("MusicDirector") as MusicDirector
	check(music.current == null, "the valley has no music yet, only wind")
	check(not music.is_reverb_on(), "no reverb outdoors")
	(world.get_node("Courtyard/Encounter") as Encounter).start(player())
	check(music.current == music.combat, "the ambush brings the combat drums")
	(world.get_node("Courtyard/Encounter") as Encounter).reset()
	(world.get_node("Sanctum/Encounter") as Encounter).start(player())
	check(music.current == music.boss, "the Gatekeeper has its own cue")
	check(music.is_reverb_on(), "the sanctum echoes")
	(world.get_node("Sanctum/Encounter") as Encounter).reset()


func test_the_lock_on_gauge_floats_over_the_target_in_view() -> void:
	await load_world()
	var hud := world.get_node("PlayerHUD") as PlayerHUD
	var targeting := player().get_node("TargetingSystem") as TargetingSystem
	var target := wolf("Wolf1")
	place_player_near(target, 5.0)
	await seconds(0.3)                                             # the camera settles behind the player
	targeting.set_target(target)
	await tree.process_frame
	await tree.process_frame
	check(hud.gauge_target() == target, "the gauge shows the locked target")
	var camera := tree.root.get_viewport().get_camera_3d()
	target.global_position = camera.global_position + camera.global_basis.z * 4.0   # behind the camera
	await tree.process_frame
	await tree.process_frame
	check(hud.gauge_target() == null, "no gauge for a target behind the camera")
