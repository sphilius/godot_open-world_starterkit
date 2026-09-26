# Vertical Slice Prompts (rewritten for this codebase)

These replace the runbook's prompts. The runbook's versions assume an empty project; these
**extend the existing starter kit** and follow the corrections in [`PLAN.md` §3](PLAN.md#3-corrections-to-the-runbook).
Run one prompt per session. Prepend the preamble, attach
[`HANDOFF_MANIFEST.md`](HANDOFF_MANIFEST.md), and paste the prompt.

Effort tags follow the runbook's matrix: **HIGH** for kinematics, state coordination and AI;
**MEDIUM** for components; **LOW** for scaffolding and tests.

---

## Shared preamble (prepend to every coding prompt)

```text
You are working in the Godot 4.7 project at the repo root (branch off `vertical-slice-prototype`).
Read docs/vertical-slice/HANDOFF_MANIFEST.md and the files named below before writing code.
Rules:
- Statically typed GDScript, tabs, `##` doc comments; match the style of scripts/combat/*.gd.
- Extend existing classes; never rename or re-sign an existing public method without updating the manifest.
- Keep the 7 faction physics layers from the manifest. Never tween a CharacterBody3D's position.
- Engine.time_scale is only written through TimeScale (after M1).
- Add or extend tests under tests/ for what you build.
- Done means that `bash tools/ci/validate.sh` exits 0 (it installs Godot 4.7.1 if needed, imports,
  and runs every test in tests/; new tests `extends "res://tests/test_case.gd"`). Then commit with `feat(<area>): <component> (validated)`, and update the manifest if the surface changed.
```

---

## M0: Toolchain and validation (LOW–MEDIUM) ✅ implemented

```text
TASK: Make the project headlessly verifiable in CI and in cloud Claude sessions.
1. tests/run_tests.gd (extends SceneTree): discovers tests/test_*.gd. Each test file extends
   Node and has `func test_*() -> void` methods, which may `await`. For each file the runner
   adds a fresh test root Node3D to `root` (so `_ready()` runs and Area3D overlaps happen in a
   real physics world), adds the test node under it, `await`s each method, then frees the test
   root. It collects failures from a tiny assert helper (tests/test_case.gd: check, check_eq,
   check_near), prints a summary and calls quit(1) on any failure.
   Give tests a helper `await_physics(frames := 2)` that awaits `physics_frame` that many times.
2. tests/test_smoke.gd: add scenes/player/player.tscn and scenes/mobs/wolf.tscn **into the test
   root** (never test them off-tree: HealthComponent._ready() sets current_health, and
   Hitbox._ready() connects its overlap signals). Place the wolf inside the katana hitbox, call
   begin() and set_active(true), then await_physics() before asserting. Assert that Hitbox hits
   a target once per activation, that HealthComponent i-frames block a second hit, and that
   HealthComponent.resolve() works on a Hurtbox, a HealthComponent and a body.
3. .github/workflows/validate.yml: on push and PR, download the Godot 4.7.x Linux headless
   binary (cache it), run `--import`, then the runner.
4. .claude/hooks/session-start.sh (plus settings): same download, so web sessions can
   validate. Use the session-start-hook skill.
5. README: a "Validation" section.
```

## M1: Hit pipeline refactor (HIGH, and it must not change gameplay) ✅ implemented

```text
READ: scripts/combat/{hitbox,hurtbox,hit_info,health_component,hit_stop}.gd, scripts/mobs/wolf.gd,
scripts/combat/combat_state_machine.gd.
TASK:
1. scripts/core/time_scale.gd `TimeScale`: a static request map id → scale; the effective scale is
   the minimum (1.0 when empty). Rewrite HitStop.trigger() on top of it (push, real-time timer, pop).
   Keep its "overlapping requests extend" behaviour.
2. HitInfo v2: add poise_damage, damage_type, hit_position, unblockable, can_be_parried and attack
   (defaults keep old call sites valid). Add `enum Result` (HitInfo.Result) per the manifest.
3. Hurtbox v2: receive_hit(hit) -> HitInfo.Result, a defenders list (add_defender; each has
   intercept(hit) -> HitInfo.Result, where IGNORED passes through), then health.take_damage, then an
   optional posture.add_posture. Emits hit_received.
4. Hitbox: when the touched node is a Hurtbox, fill hit_position (the closest point on the
   hurtbox shape, or the hurtbox origin) and call receive_hit(). Only trigger hit-stop and
   hit_landed on HIT or KILLED. The body_entered and resolve() path stays for hurtbox-less targets.
5. HealthComponent: add grant_invulnerability(seconds: float), which extends (never shortens)
   _invulnerable_until_msec, and is_invulnerable() -> bool. Hurtbox.receive_hit returns IGNORED
   while invulnerable, before any defender runs. Dodge (M3) and the boss roar (M6) use it.
TESTS: grant_invulnerability blocks a hit and then expires; a shorter grant never cuts a longer
one; the time-scale minimum wins; hit-stop ending during a 0.25x push leaves 0.25; a defender
returning BLOCKED stops the health damage; all smoke tests still pass.
```

---

## M2: Art (Blender MCP runs on your machine, not in cloud sessions)

### 2A. Characters: import and prep, not modelling (HIGH)
The character modelling prompt is replaced because of decision D3. Use this prompt once the
source meshes are in `assets/incoming/`:

```text
You are a technical artist driving Blender via bpy (Blender MCP).
INPUT: assets/incoming/<character>.(fbx|glb) from the chosen pack, AI generator or commission.
TASK for each of player_duelist, enemy_grunt, enemy_brute and enemy_gatekeeper:
1. Scale to metres; feet at z=0; faces -Y in Blender (Blender's front view); apply transforms.
   The glTF export turns -Y into +Z, which is Godot's `Vector3.MODEL_FRONT`; the kit's
   characters face -Z, so the import wrapper (the `Visual` child) turns the model 180°.
2. Budget check: under 25k tris for the player and grunt, under 35k for the brute and boss. Decimate
   (collapse) only the non-deforming parts if over.
3. Rig: if unrigged, stop and report (it needs Mixamo auto-rig: upload, download FBX with skin).
   If rigged, rename bones to Mixamo convention so one Godot BoneMap retargets every character.
4. Materials: Principled BSDF only; pack textures; name them M_<Char>_<Part>. Grunt veins use an
   emissive mask (Emission Strength about 2) so they bloom in Godot.
5. UVs: never generate UV buffers by hand. Only if a mesh has none:
   bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02); bpy.ops.uv.pack_islands(margin=0.02)
6. Export glTF 2.0 (.glb): +Y up, skinning, no animations (clips come separately), to
   assets/characters/<name>.glb. Write a one-line entry in assets/LICENSES.md.
```

### 2B. Animation retarget and import (MEDIUM, Godot side, cloud OK)

```text
READ: assets/characters/samurai/samurai_state_machine.tres, tools/build_placeholder_rigs.gd, AttackData.
TASK:
1. Import presets for assets/characters/*.glb and assets/animations/**/*.fbx: Skeleton3D →
   BoneMap with SkeletonProfileHumanoid, "Remove Tracks: unmapped bones" and loop flags per
   clip name suffix (_loop).
2. Build AnimationLibrary resources per character. Name every clip exactly as in the
   manifest's "Animation clip names" table (those names are the contract that AttackData.animation
   and the state machines use); don't rename state-machine states.
3. tools/check_attack_timings.gd (SceneTree): for every AttackData, compare duration to the clip
   length. Warn if active_end > duration or if the clip is missing.
4. Sockets: BoneAttachment3D on RightHand, Hips and Head, with Marker3D children
   Socket_Weapon_Hand_R, Socket_Sheath_Hip_L and Socket_Telegraph_Glint (offsets as exports).
```

### 2C. Weapons, courtyard kit and shrine (HIGH; Blender MCP's strength)
The runbook prompt is kept, with these additions:

```text
You are a 3D environment and prop artist using Blender Python (bpy). EFFORT: HIGH.
Visual target: weathered dark-fantasy temple, warm stone, lacquer and brass accents; matches
the existing torii and stone lanterns in scenes/landmarks/.
1. Weapons: Duelist_Blade (curved katana profile, leather-wrapped grip, circular tsuba; pivot at
   grip centre; blade along -Y); Duelist_Scabbard (lacquered wood, brass fittings; pivot at the
   mouth); Brute_Maul (iron head, wrapped haft; pivot at the grip). Add an empty named
   Blade_Tip at the blade tip and Blade_Base at the tsuba (these drive the sword trail markers).
2. Courtyard kit (all 4 m grid, pivot at bottom-centre, 0,0,0): Floor_Flagstone_4x4 (beveled,
   2 variants), Wall_Stone_Section (4 m x 2.5 m, coping), Wall_Stone_Broken, Pillar_Temple
   (octagonal, capital), Stairs_4x2, Gate_Courtyard (a separate animated leaf mesh),
   Debris_Scatter (5 pieces), Banner_Hanging. Each gets a *_col simplified collision mesh (the
   Godot "-col" import suffix).
3. Checkpoint_Shrine: multi-tier stone lantern with a hollow chamber and an empty
   Marker3D_FlamePoint. Sanctum_Gate: a large set-piece doorway.
4. PBR via Principled BSDF; procedural noise and voronoi for roughness and bump, then BAKE them
   to 2k image textures (procedural nodes don't export to glTF).
5. UVs: bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02); bpy.ops.uv.pack_islands(margin=0.02).
6. Export assets/weapons/{duelist_blade,duelist_scabbard,brute_maul}.glb,
   assets/environment/modular_courtyard_kit.glb, assets/props/{checkpoint_shrine,sanctum_gate}.glb.
```
Step 4 corrects the runbook: procedural shader nodes don't survive glTF export, so they must
be baked.

---

## M3: Offense ✅ implemented (the quick-draw strike is `draw_attack`, not `iai_draw`)

### 3A. AttackData v2 (LOW–MEDIUM)
```text
Extend scripts/combat/attack_data.gd with the v2 fields from the manifest (keep the existing names:
`hitstop`, `knockback`). Update resources/combat/*.tres with sensible values. Add
resources/combat/{heavy_1,heavy_2,light_heavy_branch,special_1,iai_draw}.tres. Fill the new HitInfo
fields in Hitbox from the attack. Tests: defaults, knockback override direction.
```

### 3B. ComboManager (MEDIUM–HIGH)
```text
READ: scripts/combat/combat_state_machine.gd (the current buffer and chain logic is the reference behaviour).
TASK: scripts/combat/combo_manager.gd and combo_node.gd per the manifest.
- FIFO input buffer (buffer_window 0.25 s) for attack_light, attack_heavy, attack_special and dodge;
  expired entries drop.
- The combo graph is ComboNode resources: L1→L2→L3, L1→H2, L2→H_finisher, and so on. An iai_root
  applies when sheathed.
- The chain point stays max(combo_window_open, active_end) unless a cancel window allows the
  action earlier (cancel_open / cancel_into from AttackData).
- combo_reset_time 1.1 s after the last attack ends.
- Zero references to visuals, AnimationTree or the body: signals only.
Then refactor CombatStateMachine into CombatController: it listens to ComboManager signals and
keeps the IDLE/RUN/HURT/DEAD handling, plus ATTACK (generic, data-driven) and DODGE states.
Dodge: 0.45 s, cancels recovery. I-frames 0.08–0.3 s: at 0.08 s call
health.grant_invulnerability(0.22) (added in M1; see the manifest). The existing
invulnerability_time only starts after an accepted hit, so it can't provide this.
Tests: buffer expiry, branch selection, cancel windows, reset timer (simulate by stepping time),
and a hit landing 0.1 s into a dodge returns IGNORED while one at 0.35 s lands.
```

### 3C. MotionWarping (HIGH)
```text
READ: PlayerController.begin_attack() and the lunge fields; CombatStateMachine._attack_direction().
TASK: scripts/combat/motion_warping.gd per the manifest.
- Target: TargetingSystem.current_target if locked, else the soft-lock search (move the old
  _attack_direction logic here).
- Reject if the angle between facing and the target exceeds max_warp_angle, or the distance
  exceeds max_warp_distance.
- Displacement = (distance - stop_distance) clamped to [0, max_warp_distance]; never negative
  (no backward pulls).
- Drive it by calling body.begin_attack(dir, displacement / duration, duration, lunge_delay):
  velocity-based, so move_and_slide resolves collisions. Ease with an out-quad profile by
  modulating the lunge speed per tick (add an optional speed curve to PlayerController).
- AttackData.warp=false disables it (for example, the Iai draw keeps a fixed lunge).
Tests: clamp math, angle rejection, stop distance, no backward displacement.
```

### 3D. WeaponManager (LOW–MEDIUM)
```text
Evolve scripts/combat/weapon_holster.gd into WeaponManager (keep draw(), sheathe() and is_drawn()
so callers still work). Sheath socket = Socket_Sheath_Hip_L (decision D6). Add
snap_weapon_to_hand() and snap_weapon_to_sheath() for AnimationPlayer method tracks (the tween
path stays as the fallback when no clip is present). Add stance_changed and tell ComboManager to
use iai_root when an attack is pressed while sheathed. Keep the 3.0 s idle sheathe.
```

---

## M5: Defense ✅ implemented (spam lockout counts from the end of each window; a successful parry lifts it)

### 5A. PostureComponent, GuardComponent, ParrySystem (HIGH)
```text
Implement per the manifest in scripts/combat/defense/.
- Posture: recovery starts recovery_delay after the last posture hit. The rate scales with
  health ratio (lower health means slower recovery) and doubles while guarding and standing
  still. Break: emits posture_broken and resets to 0 after the break stagger.
- Guard (defender): only the frontal guard_arc_degrees. Health damage becomes 0, poise_damage
  goes to posture, and chip damage is an export (default 0). Unblockable hits pass through. A
  break returns GUARD_BROKEN and emits guard_broken (DamageReaction plays a 2.5 s stagger).
- Parry (defender, registered before Guard): on_guard_pressed opens parry_window (0.15 s, measured
  in real time, not frames). A can_be_parried hit inside the window returns PARRIED, applies
  3x poise_damage to the attacker's PostureComponent, makes the attacker's DamageReaction play
  "parried", and emits parry_successful. Spamming guard gets a 0.4 s lockout before the next
  window.
Wire the player (guard action, guard animations) and the wolf (posture only).
Tests: every branch of the defender chain, lockout, the unblockable bypass.
```

### 5B. DamageReactionComponent (HIGH)
```text
Replace the player's HURT handling and the wolf's STAGGER internals with a shared component.
- Listens to Hurtbox.hit_received.
- Direction: attacker position in the character's local basis → front, back, left or right.
- poise_damage < poise_threshold → light flinch in that direction. Above it → heavy. Above
  knockdown_threshold or posture broken → knockdown (animated; decision D8).
- Knockback: sets CharacterBody3D velocity, which decays with `friction`. Locks controls or AI
  for the stagger duration.
Tests: direction classification over 8 angles, threshold tiers.
```

---

## M6: AI ✅ implemented (executions use the light attack on a posture-broken enemy, not a separate `interact` press; the roar's trauma is a `roared(trauma)` signal until CameraTrauma lands in M9)

### 6A. CombatDirector (HIGH)
```text
scripts/ai/combat_director.gd per the manifest. Tokens are leases (the enemy must release on
attack end, stagger or death; also auto-expire after 4 s as a safety net). A 0.8 s global
cooldown before any token re-issues. Flank ring: slots evenly spaced on a ring_radius circle
around the player, starting from the player's back-left so enemies stay in front of the camera
when possible. Assign slots by the Hungarian method or a greedy nearest-slot match; don't swap
slots every frame (use hysteresis). Tests: token cap, cooldown, release on death, even slot
spacing.
```

### 6B. EnemyCombatController, Grunt and Brute (HIGH)
```text
READ: scripts/mobs/wolf.gd (reuse its navmesh chase, arrival braking, repath timer and telegraph
wind-up pattern).
TASK: scripts/ai/enemy_combat_controller.gd per the manifest. The token decides APPROACH (to
2.0 m) or FLANKING (director slot, strafe animations). ATTACK_WINDUP emits telegraph_glint 0.4 s
before active_start (red if attack.unblockable, gold otherwise). A glint VFX scene attaches at
Socket_Telegraph_Glint (a billboard star flare plus a short light, additive).
Scenes: scenes/mobs/enemy_grunt.tscn (fast, low posture, 2 attacks) and enemy_brute.tscn (slow,
high poise, slam, sweep, unblockable thrust). Both have HealthComponent, PostureComponent,
Hurtbox, DamageReaction and a Hitbox on the weapon socket.
Tests: the state machine releases its token on every exit path.
```

### 6C. Sanctum Gatekeeper boss (HIGH)
```text
scenes/mobs/enemy_gatekeeper.tscn extends the brute. Phase 2 at 50% HP: a roar (brief
invulnerability plus a camera trauma of 0.45), 20% faster recovery, adds an unblockable combo
(red glint), and posture regen doubles. A posture break opens an execution prompt (interact),
and the execution deals 40% max HP. It has its own health and posture bar at the top of the HUD.
```

---

## M7: TargetingSystem and CombatCamera3D (HIGH) ✅ implemented (the camera class is `CombatCamera`, on the CameraRig)

```text
READ: PlayerController camera code (look smoothing, interpolated follow, SpringArm3D sphere).
TASK:
1. Extract the camera into scripts/camera/combat_camera_3d.gd (SpringArm3D) with the same
   smoothing constants. PlayerController keeps add_look_input(), which forwards to it.
2. TargetingSystem: an 18 m sphere query over group "enemies" plus a 70° cone around the camera
   forward, with line-of-sight raycasts on layer 1. lock_on toggles. Cycling: the mouse wheel,
   or a right-stick flick past 0.7 then back to centre, picks the nearest target to the left or
   right in screen space (Camera3D.unproject_position). Auto-retarget on target death.
3. Locked camera: yaw toward the player→target midpoint, arm length lerps with separation
   (4.2 m → 6 m), pitch biased down. Player strafes (faces the target) while locked. Unlocking
   restores free look without a snap.
Tests: cone and radius filtering, left/right cycling order with mocked screen positions.
```

---

## M8: Level assembly (MEDIUM; the editor dressing is yours) ✅ implemented as greybox (GreyboxArena walls and LevelGate portcullises until the M2 kit lands; per-beat environments moved to M9)

```text
READ: scenes/main.tscn, scripts/world/scenic_path.gd, scripts/main.gd.
TASK:
1. Beat 1 stays in the existing valley. Place the courtyard at the ScenicPath end, levelled
   with a terrain flatten mask (extend heightmap_terrain.gd with circular flatten zones).
2. scenes/levels/courtyard.tscn from the modular kit (GridMap or hand-placed scenes).
   Gate_Courtyard closes on encounter start. scenes/levels/sanctum.tscn beyond it.
3. scripts/game/encounter.gd: an Area3D trigger, waves (Array of PackedScene + count), owns a
   CombatDirector, reset() despawns and restores, emits cleared.
4. Per-beat environment resources (golden hour → dusk → night, decision D9) that GameManager
   tweens between.
5. Add the courtyard and sanctum meshes to group navigation_source; rebake.
```

## M9: Audio, trauma, HUD and game loop (MEDIUM–HIGH)

The runbook's 6.1A, 6.1B and 6.1C are merged here in full, with the changes for this codebase
folded in. Run them as three sessions.

### 9A. Surface foley and combat audio (MEDIUM)
```text
READ: scripts/world/heightmap_terrain.gd (the path mask in vertex colour), scripts/combat/hitbox.gd,
the manifest's AttackData, HitInfo and ParrySystem.
TASK:
1. default_bus_layout.tres: Master → SFX, Music, UI. SFX has two reverb send buses (Courtyard,
   Sanctum) that the GameManager enables per beat.
2. scripts/audio/surface_foley_audio_3d.gd (AudioStreamPlayer3D on the character's feet):
   - step() is called by animation method tracks. For placeholder rigs, a fallback timer fires
     steps from planar speed (stride 0.75 m walk, 1.1 m run).
   - On each step, raycast 0.3 m down from the feet on layer 1. Surface: the collider's
     PhysicsMaterial metadata "surface" (GRASS, GRAVEL, STONE, WOOD). On the terrain, use
     HeightmapTerrain's path mask at the hit point: gravel above 0.5, grass otherwise.
   - Pick a random stream from a per-surface AudioStreamRandomizer, no immediate repeats,
     pitch_scale = randf_range(0.95, 1.05). Landing after a jump plays a heavier variant.
3. scripts/audio/combat_audio_player_3d.gd: a pool of 8 AudioStreamPlayer3D voices, so impacts
   don't cut each other off (steal the oldest voice when full).
   - play_impact_sound(attack: AttackData, hit_pos: Vector3, armoured: bool): layer a transient
     snap, then a flesh or armour thud chosen by damage_type and `armoured`, with volume scaled
     by damage.
   - play_parry_clang(contact_pos): a high metallic ring (3 variants) on the SFX bus with the
     current reverb send.
   - play_block(contact_pos), play_posture_break(pos), play_whoosh(attack) from swing start.
   - Wire them to Hurtbox.hit_received (HIT, BLOCKED, PARRIED, GUARD_BROKEN results) and to the
     katana's begin_swing.
4. Music: an AudioStreamPlayer on the Music bus with exploration, combat, boss and victory
   cues; cross-fade 1.5 s on GameManager.state_changed.
Tests: surface classification from metadata and from a mocked path-mask value; voice stealing
when all 8 are busy.
```

### 9B. CameraTrauma and CombatHUD (MEDIUM)
```text
READ: scripts/ui/player_hud.gd, scripts/camera/combat_camera_3d.gd (M7), the manifest.
TASK:
1. scripts/camera/camera_trauma.gd (child of the Camera3D):
   - add_trauma(amount) clamps trauma to [0, 1]. shake = trauma². Trauma decays at 1.5/s in
     real time, so hit-stop doesn't freeze the shake.
   - Six degrees of freedom from FastNoiseLite (one noise, a separate offset per axis):
     h_offset and v_offset up to 0.35 m, and rotation (pitch, yaw, roll) up to 4°. Write only
     Camera3D offsets and rotation; never move the SpringArm, so wall collision stays correct.
   - Presets as constants: LIGHT 0.2, HEAVY 0.45, PARRY 0.35, EXECUTION 0.75. Hook them to
     Hitbox.hit_landed (light or heavy from AttackData.trauma), parry_successful and executions.
2. scripts/ui/combat_hud.gd extends PlayerHUD (keep its drain bar, hurt flash and defeat banner):
   - Player posture bar centred under the health bar; hidden at 0, turns orange above 70%.
   - A floating gauge (health and posture) above the locked target, positioned each frame with
     Camera3D.unproject_position() at the target's head; hidden when behind the camera.
   - A lock-on reticle that pulses (scale 1.0 → 1.35 → 1.0 over 0.18 s) on parry and on hit
     confirmation.
   - A boss bar at the top of the screen while in SANCTUM_GATEKEEPER.
   - Every control ignores the mouse, like PlayerHUD, so touch input still passes through.
Tests: trauma decay and clamping; shake is quadratic; the gauge hides for targets behind the camera.
```

### 9C. GameManager and CheckpointShrine (HIGH) ✅ implemented (M9a)

Differences from the prompt below, kept on purpose:
- `GameManager` is a node in `main.tscn` (group `game_manager`, `GameManager.find(tree)`), not an
  autoload, so a scene reload or each test's fresh world starts clean.
- The title is an overlay (`GameMenus`) over the paused `main.tscn`, not a separate main scene.
- `CombatStateMachine` keeps its respawn timer; `PlayerController.respawn()` now goes to the
  checkpoint (`set_respawn_point()`). GameManager adds the slow motion (0.3 for 1.2 real s) and
  GameMenus the fade to black and back.
- Shrines light when the player walks up (no `interact` prompt), heal and reset posture.
- Clearing the courtyard unlocks the sanctum gate, so the ambush can't be walked around.
- Reverb sends and music cues move to 9A (M9b), which hooks `state_changed`.
```text
READ: scripts/main.gd, scripts/combat/combat_state_machine.gd (the current death and respawn flow),
the manifest's GameManager, TimeScale and Encounter.
TASK:
1. scripts/game/game_manager.gd as an autoload (GameManager) per the manifest.
   - Flow: START_MENU → EXPLORATION → COURTYARD_AMBUSH → SANCTUM_GATEKEEPER → VICTORY_SCREEN.
     Encounter triggers and the boss's defeat drive the transitions. Each transition blends
     the per-beat environment (D9), sets the reverb send and changes the music cue.
   - Death: on the player's HealthComponent.died, TimeScale.push(&"death", 0.25). After 1.2 s of
     real time (a timer that ignores time scale), fade to black over 0.4 s, then
     TimeScale.pop(&"death") **before** resetting anything. Then reset the active encounter
     (Encounter.reset()), restore the player's health and posture, respawn at the last active
     checkpoint and fade back in. The push and pop must pair on every path, including when the
     player quits to the menu mid-fade. Never write Engine.time_scale directly.
   - This replaces the respawn inside CombatStateMachine._on_died (keep the DEAD state and the
     kneel animation).
   - The pause action opens a pause menu with get_tree().paused (the menu uses
     PROCESS_MODE_WHEN_PAUSED); pause doesn't go through TimeScale. The start menu scene
     becomes run/main_scene and loads main.tscn.
2. scripts/game/checkpoint_shrine.gd (Area3D, on checkpoint_shrine.glb, or on the stone lantern
   until that art lands): while the player is inside, show an "interact" prompt. Interact heals
   the player fully, restores posture, saves the respawn transform with
   GameManager.set_checkpoint(), lights an OmniLight3D at Marker3D_FlamePoint with a 0.5 s
   flicker-up, and plays the ignite sound. It stays lit afterwards.
Tests: death → respawn leaves the effective time scale at 1.0; a hit-stop during the death
slow-motion doesn't restore 1.0 early; quitting mid-fade also pops &"death"; the respawn uses the
latest checkpoint.
```

## M10: Playtest and tuning (MEDIUM)

```text
Run the capture tooling (dev_hud --capture) at each beat. Log time-per-beat, deaths and parries
to user://playtest.csv from GameManager. Summarise 3 playtests against PLAN.md §6.2 and propose
AttackData and director tuning diffs. Update the README (controls, beats, credits) and
assets/LICENSES.md.
```

---

## Concept art (before M2)

Use the `nano-banana-prompt-composer` skill for character turnarounds (front, side, back,
T-pose) of the Duelist, Grunt, Brute and Gatekeeper, plus 2 courtyard mood frames (dusk
ambush, night sanctum). Save them to `docs/vertical-slice/concept/` (they're reference only;
don't ship them).
