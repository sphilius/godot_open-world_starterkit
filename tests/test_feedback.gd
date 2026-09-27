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
	for surface in SurfaceFoley.SURFACES:
		check(BANK.has_sound(StringName("step_" + String(surface))), "the bank has footsteps for %s" % surface)


func test_a_surface_without_its_own_steps_falls_back_to_stone() -> void:
	var pool := SfxPool.new()
	pool.bank = BANK
	add_to_stage(pool)
	var foley := SurfaceFoley.new()
	add_to_stage(foley)
	for case in [[&"wood", &"step_wood"], [&"metal", &"step_stone"]]:
		var floor_body := StaticBody3D.new()
		floor_body.set_meta(&"surface", case[0])
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4, 1, 4)
		shape.shape = box
		shape.position.y = -0.5
		floor_body.add_child(shape)
		add_to_stage(floor_body)
		await physics_frames(2)
		check_eq(foley.step(), case[1], "a %s floor plays %s" % [case[0], case[1]])
		floor_body.free()


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
	music.crossfade_time = 0.4
	check(music.current == null, "the valley has no music yet, only wind")
	check(not music.is_reverb_on(), "no reverb outdoors")
	(world.get_node("Courtyard/Encounter") as Encounter).start(player())
	check(music.current == music.combat, "the ambush brings the combat drums")
	await seconds(0.5)
	(world.get_node("Sanctum/Encounter") as Encounter).start(player())
	check(music.current == music.boss, "the Gatekeeper has its own cue")
	await seconds(0.2)
	check(music.music_player().volume_db > -32.0, "the boss cue fades in while the drums fade out (%.1f dB)" % music.music_player().volume_db)
	(world.get_node("Courtyard/Encounter") as Encounter).reset()
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


func test_ink_splats_lie_on_the_ground_recycle_and_fade() -> void:
	var slope := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	shape.position.y = -0.5
	slope.add_child(shape)
	slope.rotation.x = deg_to_rad(20.0)
	add_to_stage(slope)
	var ink := InkSplats.new()
	ink.max_splats = 3
	ink.grow_time = 0.05
	add_to_stage(ink)
	await physics_frames(2)
	var first := ink.splat(Vector3(0, 1, 0))
	check(first != null, "a hit above the ground leaves a splat")
	if first == null:
		return
	var up := slope.global_basis.y
	check(first.global_basis.y.normalized().dot(up) > 0.99, "the splat lies along the slope")
	check_near((first.global_position - slope.global_position).dot(up), ink.lift, 0.01, "just above the ground")
	await seconds(0.1)
	check(first.scale.x >= ink.size_range.x - 0.01, "it grew to full size (%.2f m)" % first.scale.x)
	check(ink.splat(Vector3(0, 50, 0)) == null, "no ground within reach, no splat")
	for i in 3:
		ink.splat(Vector3(i, 1, 0))
	check_eq(ink.splats.size(), 3, "the pool stops at max_splats")
	check(ink.splats[0] == first and first.global_position.x > 1.5, "the oldest splat was reused for the newest hit")
	ink.lifetime = 0.05
	ink.fade_time = 0.05
	ink.splat(Vector3(0, 1, 0))
	check(await wait_until(func() -> bool: return ink.visible_count() == 2, 1.0), "a splat fades away after its lifetime")
	var mask := InkSplats.make_mask(32, 1)
	check(mask.get_pixel(16, 16).a > 0.99 and mask.get_pixel(0, 0).a < 0.01, "the mask is solid in the middle and clear in the corner")


func test_hits_and_kills_leave_ink_on_the_terrain() -> void:
	await load_world()
	var ink := world.get_node("InkSplats") as InkSplats
	var target := wolf("Wolf1")
	check(await wait_until(target.is_on_floor, 5.0), "the wolf never landed")   # wolves drop in from their spawn height
	place_player_near(target, 2.0)
	await physics_frames(3)
	var hit := CombatFixtures.make_hit(player(), 5.0, 0.0)
	hit.hit_position = target.global_position + Vector3.UP
	(target.get_node("Hurtbox") as Hurtbox).receive_hit(hit)
	check_eq(ink.visible_count(), 1, "the hit left ink under the wolf")
	var terrain := world.get_node("Terrain") as HeightmapTerrain
	var splat := ink.splats[0]
	check_near(splat.global_position.y, terrain.height_at(splat.global_position.x, splat.global_position.z), 0.1, "on the terrain")
	(target.get_node("Hurtbox") as Hurtbox).receive_hit(CombatFixtures.make_hit(player(), 9999.0, 0.0))
	check_eq(ink.visible_count(), 2, "the kill left more")
	check(ink.splats[1].scale.x > 0.0, "the kill's splat is growing")
