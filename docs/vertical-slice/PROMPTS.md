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
- Done means that `godot --headless --path . --import` and `godot --headless --path . --script res://tests/run_tests.gd`
  both exit 0. Then commit with `feat(<area>): <component> (validated)`, and update the manifest if the surface changed.
```

---

## M0: Toolchain and validation (LOW–MEDIUM)

```text
TASK: Make the project headlessly verifiable in CI and in cloud Claude sessions.
1. tests/run_tests.gd (extends SceneTree): discovers tests/test_*.gd. Each test file extends
   RefCounted and has `func test_*() -> void` methods. The runner runs each method, collects
   failures from a tiny assert helper (tests/assert.gd: eq, near, is_true, fails_with), prints
   a summary and calls quit(1) on any failure.
2. tests/test_smoke.gd: instantiate scenes/player/player.tscn and scenes/mobs/wolf.tscn
   off-tree. Assert that Hitbox hits a target once per activation, that HealthComponent i-frames
   block a second hit, and that HealthComponent.resolve() works on a Hurtbox, a
   HealthComponent and a body.
3. .github/workflows/validate.yml: on push and PR, download the Godot 4.7.x Linux headless
   binary (cache it), run `--import`, then the runner.
4. .claude/hooks/session-start.sh (plus settings): same download, so web sessions can
   validate. Use the session-start-hook skill.
5. README: a "Validation" section.
```

## M1: Hit pipeline refactor (HIGH, and it must not change gameplay)

```text
READ: scripts/combat/{hitbox,hurtbox,hit_info,health_component,hit_stop}.gd, scripts/mobs/wolf.gd,
scripts/combat/combat_state_machine.gd.
TASK:
1. scripts/core/time_scale.gd `TimeScale`: a static request map id → scale; the effective scale is
   the minimum (1.0 when empty). Rewrite HitStop.trigger() on top of it (push, real-time timer, pop).
   Keep its "overlapping requests extend" behaviour.
2. HitInfo v2: add poise_damage, damage_type, hit_position, unblockable, can_be_parried and attack
   (defaults keep old call sites valid). Add `enum HitResult` per the manifest.
3. Hurtbox v2: receive_hit(hit) -> HitResult, a defenders list (add_defender; each has
   intercept(hit) -> HitResult, where IGNORED passes through), then health.take_damage, then an
   optional posture.add_posture. Emits hit_received.
4. Hitbox: when the touched node is a Hurtbox, fill hit_position (the closest point on the
   hurtbox shape, or the hurtbox origin) and call receive_hit(). Only trigger hit-stop and
   hit_landed on HIT or KILLED. The body_entered and resolve() path stays for hurtbox-less targets.
TESTS: the time-scale minimum wins; hit-stop ending during a 0.25x push leaves 0.25; a defender
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
1. Scale to metres; feet at z=0; faces -Y in Blender (so -Z in Godot); apply transforms.
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
2. Build AnimationLibrary resources per character from the clip list in PLAN.md §4.3, using the
   clip names in the manifest; don't rename state-machine states.
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

## M3: Offense

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
Dodge: 0.45 s, i-frames 0.08–0.3 s via HealthComponent, cancels recovery.
Tests: buffer expiry, branch selection, cancel windows, reset timer (simulate by stepping time).
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

## M5: Defense

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

## M6: AI

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

## M7: TargetingSystem and CombatCamera3D (HIGH)

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

## M8: Level assembly (MEDIUM; the editor dressing is yours)

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

The runbook's 6.1A, 6.1B and 6.1C are kept, with these changes:
- **Foley**: the surface comes from the terrain path mask (gravel) versus grass from
  `HeightmapTerrain`, and `PhysicsMaterial` metadata `surface` on props. Steps fire from
  animation method tracks, with a speed-based timer as the fallback for placeholder rigs.
- **Audio buses**: Master → SFX (Reverb send: Courtyard, Sanctum), Music, UI. A
  `CombatAudioPlayer3D` pool of 8 voices, so impacts don't cut each other off.
- **CameraTrauma** writes `Camera3D.h_offset`, `v_offset` and rotation. It never moves the
  SpringArm, so wall collision stays correct. Trauma decays at 1.5/s.
- **CombatHUD** extends `PlayerHUD` (keep the drain and hurt flash); adds a posture bar that
  sits centred and hides at 0, the enemy gauge through `unproject_position`, the reticle pulse,
  and the boss bar.
- **GameManager**: death slow-motion through `TimeScale.push(&"death", 0.25)`, never
  `Engine.time_scale` directly. Encounter reset calls `Encounter.reset()`. Add a pause menu
  (`pause` action) and a start menu scene set as `run/main_scene`, which then loads main.tscn.

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
