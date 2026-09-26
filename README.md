# Scenic Open World: Godot 4.7 Forward+ prototype

[![Deploy web build](https://github.com/sphilius/godot_open-world_starterkit/actions/workflows/deploy-web.yml/badge.svg)](https://github.com/sphilius/godot_open-world_starterkit/actions/workflows/deploy-web.yml)
**Play in the browser:** https://sphilius.github.io/godot_open-world_starterkit/ (add `?touch` for the tablet controls)

Golden-hour valley: a samurai walks a gravel path lined with torii gates and stone lanterns
through wind-rippled grass, lit by a physical sky, SDFGI and volumetric fog. Wolves roam the
meadow and bite back, and a 3-hit katana combo deals with them. It plays on desktop and in the
browser, with on-screen touch controls for tablets and phones.

## Quick start

1. Open `project.godot` in **Godot 4.7** and press **F5**. Or run from the command line:
   `godot --path .`
2. The world is procedural and builds in about 1.3 s on launch (it also previews in the editor).
   The wolves' navmesh bakes on a worker thread in ~0.3 s.

| Action | Keyboard + mouse | Touch (tablet / phone) |
|---|---|---|
| Move (camera-relative) | WASD / arrows · left stick | Thumbstick: touch anywhere on the left side |
| Look | Mouse · right stick | Drag anywhere else |
| **Lock on / release** | **MMB / Q** · right-stick click | **LOCK** |
| Switch target (left / right on screen) | Mouse wheel (E = next) · flick the right stick | **NEXT** |
| **Light attack (combo)** | **LMB / J** (keep pressing) | **ATK** (keep tapping) |
| **Heavy attack** (branches the combo) | **RMB / K** | **HVY** |
| **Dodge** (i-frames; backstep with no input) | **L / C** | **DODGE** |
| **Guard** (hold) · **parry** (press just before a hit lands) | **F / I** · LB | **GUARD** |
| **Execute** (an enemy with a broken posture, in front) | Light attack | **ATK** |
| Jump | Space | JUMP |
| Sprint | Shift (hold) | RUN (tap to toggle) |
| Quality LOW/MEDIUM/HIGH | F2 | QUAL |
| Back to the path start | — | RESET |
| Fullscreen | — | FULL |
| Screenshot | F12 | — |

Touch controls appear automatically on touchscreens. Force them with `--touch` (desktop,
where the mouse acts as one finger) or `?touch` in the web URL.

## Web build (Pixel Tablet and other browsers)

Browsers can't run Forward+, so web exports use the **Compatibility** renderer (WebGL 2).
This is set by `rendering/renderer/rendering_method.web` and needs no code changes.

1. Install the Godot 4.7.1 export templates (Editor ▸ Manage Export Templates).
2. Export: **Project ▸ Export ▸ Web**, or from the command line:
   `godot --headless --path . --export-release "Web" build/web/index.html`
3. Serve `build/web` over HTTP. It's a single-threaded build, so no special headers are needed:
   `python -m http.server 8000 --directory build/web`
4. On the tablet (same Wi-Fi), open `http://<this-PC's-IP>:8000`. Tap **FULL** for fullscreen.
   Or host the folder on any static host (itch.io, GitHub Pages).

**Auto-deploy:** every push to `main` runs `.github/workflows/deploy-web.yml`: **test → export → deploy**.
It installs Godot 4.7.1 and the web templates on a Linux runner (cached after the first run), runs the
headless test suite, and only if every test passes, exports the Web preset and publishes it to
https://sphilius.github.io/godot_open-world_starterkit/. Pull requests run the tests only.
Docs-only pushes are skipped. To redeploy by hand, use **Actions ▸ Test & deploy web build ▸ Run workflow**.

## Tests (the deploy gate)

```
godot --headless --path . --script res://tests/run_tests.gd                    # all tests, ~45 s
godot --headless --path . --script res://tests/run_tests.gd -- --filter=wolves # file or test name substring
bash tools/ci/validate.sh [--filter=hit]   # same, but downloads Godot 4.7.1 first if needed and re-imports
```

| File | Covers |
|---|---|
| `tests/test_data.gd` | Attack timing windows are sane; generated clips match `AttackData` durations (a stale rig build fails); every AnimationTree state exists |
| `tests/test_combat.gd` | Buffered 3-hit combo kills a wolf (hits, hit-stop, death, collision off, freed); draw then sheathe after 3 s; uncaptured clicks don't attack but key and touch actions do |
| `tests/test_wolves.gd` | Wander and chase on the navmesh; a bite damages and flinches the player; striking during the wind-up cancels the bite; player death, wolves disengaging, respawn |
| `tests/test_touch.gd` | Touch buttons press and release actions (multi-touch safe), RUN latches, the look pad turns the camera (one finger), RESET respawns |
| `tests/test_project.gd` | Every script compiles and every scene loads. It's the parse gate, because `godot --import` exits 0 even with broken scripts |
| `tests/test_smoke.gd` | Player and wolf scenes spawn at full health; a Hitbox hits each target once per activation; i-frames; `HealthComponent.resolve()` |
| `tests/test_time_scale.gd` | `TimeScale` requests (slowest wins); hit-stop ending mid slow-motion keeps the slow-motion; hit-stop re-arms after a reset; overlapping stops extend |
| `tests/test_hit_pipeline.gd` | `grant_invulnerability()`; Hurtbox defenders (order, claiming, pass-through); posture damage; a Hitbox touching the body still goes through the Hurtbox's defenders |
| `tests/test_combat_integration.gd` | On a bare stage: the attack input lands the animated katana on a wolf; a wolf's bite lands on the player |

A test fails on a failed check, a 60 s timeout, or **any engine or script error logged while it
runs**, including its setup and teardown (caught with a `Logger`). A test that logs an error and
then stops making progress fails after 0.5 s instead of waiting out the timeout. A test file that fails to load, or a run with zero tests, also
fails. Failures show as annotations on the GitHub Actions run.

To add a test, create `tests/test_<topic>.gd` that `extends "res://tests/test_case.gd"` and add
`test_*` methods. Start with `await load_world()` for a fresh, seeded copy of the main scene, then
use `check()`, `check_eq()`, `wait_until()` and helpers like `place_player_near()` and `press_attack()`.
For a component test that doesn't need the world, build nodes with `add_to_stage()` (a bare Node3D
in the running tree, freed after the test) and `tests/lib/combat_fixtures.gd`.
Pull requests into `vertical-slice-prototype` run the same suite (`.github/workflows/validate.yml`), and
`.claude/hooks/session-start.sh` installs Godot in Claude Code web sessions.
Headless mode doesn't dispatch input to the GUI, so feed UI events straight into `_gui_input()`
(see `test_touch.gd`).

URL options: `?touch` forces the touch UI, and `?quality=low|medium|high` picks a preset (web defaults to LOW).
The overlay shows FPS, the quality preset and the samurai's combat state (IDLE, ATTACK attack_2, DODGE, HURT…),
which helps confirm that taps register while playtesting.

What changes in the browser (handled automatically):

| Forward+ feature | Web (Compatibility) |
|---|---|
| SDFGI, volumetric fog + valley mist, SSAO | Off; the depth fog, glow and shadows remain |
| PhysicalSkyMaterial | Swapped for `golden_hour_procedural_sky.tres` (the physical sky renders nearly black there) |
| FXAA / FSR upscaling | 2× MSAA, bilinear render scale |
| GPUParticles3D sword trail | CPU mesh ribbon (`TrailRenderer.AUTO`) |
| Threaded navmesh bake | Inline bake (single-threaded build) |

The browser console shows a few one-time warnings at load: SDFGI, volumetric fog, FogVolume and
particle trails are unsupported there. They're expected. On desktop, the same Compatibility
path previews at ~60 FPS on the dev laptop's Intel UHD:
`godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 -- --touch`

## Renderer note (Windows)

Forward+ runs through **Direct3D 12** on Windows (`rendering_device/driver.windows="d3d12"`).
On the dev laptop's Intel UHD G1 (driver 31.0.101.2135), the Vulkan driver intermittently lost
the device with this scene (~30–100% of runs, depending on the preset). D3D12 went 12/12 clean
and is ~30% faster. To use Vulkan, change the setting or launch with `--rendering-driver vulkan`.
On the first D3D12 launch, expect a short hitch while shaders compile and are cached.

## Performance (i5-1035G1 / Intel UHD G1, 1600×900, D3D12)

| Preset | FPS | What's on |
|---|---|---|
| LOW | ~40 | 2-split PCF shadows, 35% grass, FSR 0.6. SDFGI and volumetric fog off |
| **MEDIUM** (auto on integrated GPUs) | ~18–19 | SDFGI (half-res, 3 cascades), volumetric fog (48×32 froxels), 50% grass, FSR 0.67 |
| HIGH (default on discrete GPUs) | discrete GPU | PCSS soft shadows, 4 splits at 4096, full-res SDFGI, 128×96 froxels, 100% grass |

On this chip SDFGI has a fixed cost of about 18 ms. The presets are a data table in
`scripts/debug/dev_hud.gd` (`PRESETS`). Integrated-GPU detection lives in
`scripts/core/gpu_info.gd`, because D3D12 reports Intel iGPUs as discrete.

## Architecture

```
Main (main.gd: drops player at path start, facing the sunset)
├─ WorldEnvironment    resources/environment/golden_hour_environment.tres
├─ Sun                 DirectionalLight3D, low and warm; PCSS soft shadows; drives the PhysicalSky
├─ ValleyMist          FogVolume, height-falloff mist hugging the valley floor
├─ Terrain             HeightmapTerrain  ─┐ one height array feeds:
├─ ScenicPath          ScenicPath        ─┤  mesh · HeightMapShape3D · path levelling/gravel paint
├─ GrassField          GrassField        ─┘  grass scatter · landmark placement
├─ NavigationRegion3D  navigation_baker.gd: bakes terrain + landmarks (group "navigation_source")
├─ Wolves              4 × wolf.tscn
├─ Encounters          SparringYard (CombatDirector, 2 Grunts, a Brute) and GatekeeperArena (the boss), at the path's end
├─ Player              player.tscn (see below)
└─ DevHUD              FPS, quality presets, screenshots, CLI capture

Player (CharacterBody3D, player_controller.gd: movement, camera, lunge/lock hooks)
├─ Visual/SamuraiModel  generated rig: Skeleton3D + skinned mesh + HandSocket/SheathSocket (BoneAttachment3D)
├─ Katana               katana.tscn: blade, Area3D Hitbox, Trail (GPUParticles3D), MeshTrail
├─ PostureComponent     posture meter: filled by poise damage and blocks, breaks when full, recovers after a delay
├─ GuardComponent       Hurtbox defender: blocks frontal hits into posture; breaks when posture fills
├─ ParrySystem          Hurtbox defender (runs first): 0.15 s window per guard press, reflects 3x poise
├─ DamageReaction       picks the stagger (directional flinch, heavy, knockdown, guard break) and knockback
├─ AnimationTree        StateMachine root: idle, run, every strike, dodge_f/b/l/r, guard/parry, hurt_f/b/l/r, hurt_heavy, knockdown, guard_break, death
├─ WeaponHolster        tweens the katana between the hand and back sockets
├─ Combat               CombatStateMachine: IDLE/RUN/ATTACK/DODGE/GUARD/HURT/DEAD, active frames, sheathing
│  ├─ ComboManager      FIFO input buffer + combo graph (resources/combat/sword_combo.tres)
│  └─ MotionWarping     steers each lunge at the lock-on target or a nearby enemy
├─ TargetingSystem      lock-on: acquire, cycle, retarget, release; reticle over the target
└─ CameraRig            CombatCamera: free look, lock-on framing → SpringArm3D/Camera3D
```

### World

| System | File | Key ideas |
|---|---|---|
| Player | `scripts/player/player_controller.gd` | Separate accel/decel and air control; `floor_snap_length` ground snapping; `begin_attack()`/`begin_dodge()` lock steering and lunge (eased out); faces the lock-on target and strafes while locked. Keyboard, mouse and gamepad bindings are registered at runtime |
| Camera | `scripts/camera/combat_camera.gd` | Exponential look/follow smoothing; the rig follows the *physics-interpolated* body. Locked on, it turns to look past the player at the target, shifts its anchor 30% toward it, pitches down and lengthens the arm (4.2 → 6 m) as they spread apart; releasing keeps the view |
| Lock-on | `scripts/combat/targeting_system.gd` | Picks the enemy nearest the view centre within 18 m and a 70° cone, in line of sight. Wheel or a right-stick flick switches by screen position. Retargets when the target dies, releases past 24 m or after 1.5 s out of sight |
| Terrain | `scripts/world/heightmap_terrain.gd` | FBM meadow + ridged mountains; path cross-section levelled; path mask in vertex colour; triangle-exact `height_at()` |
| Grass | `scripts/world/grass_field.gd` + `shaders/grass.gdshader` | 100 MultiMesh chunks; scrolling simplex wind gusts; radial player push; distance shrink-fade |
| Path + landmarks | `scripts/world/scenic_path.gd` | Torii every 36 m, lanterns every 11 m on alternating sides, all on the terrain surface |

### Combat and mobs

| System | File | Key ideas |
|---|---|---|
| Combat FSM | `scripts/combat/combat_state_machine.gd` | Owns the logic; drives the AnimationTree with `playback.travel()`. A strike chains at `max(combo_window_open, active_end)`, so presses during the wind-up aren't lost and swings are never cut short. `cancel_open`/`cancel_into` allow earlier cancels (a dodge out of a heavy wind-up), and a dodge can always cancel a strike's recovery. **Dodge**: 3.2 m eased dash, invulnerable 0.08–0.3 s; with no input it backsteps |
| Combos | `scripts/combat/combo_manager.gd`, `resources/combat/sword_combo.tres` | Light, heavy and dodge presses are buffered **0.35 s** (FIFO). The graph: L→L→L, L→H (thrust), L→L→H (finisher), H→L; from sheathed, the first press is a quick-draw strike. The chain survives **1.1 s** after a strike ends |
| Motion warping | `scripts/combat/motion_warping.gd` | Each lunge points at the lock-on target, or the nearest enemy within 60° and reach, and stretches to stop 1.2 m short of it (at most 3.5 m). It's velocity through `move_and_slide()`, eased out, so it never passes through walls |
| Attack data | `resources/combat/*.tres` (`AttackData`) | Per strike: damage, poise damage, damage type, active window, combo and cancel windows, lunge, hit-stop, stagger, knockback (and an optional direction), trauma, unblockable/parryable. Designer-tunable |
| Katana | `scripts/combat/katana.gd`, `scenes/weapons/katana.tscn` | `Area3D` hitbox on the weapon-bone socket. `area_entered` (hurtboxes) and `body_entered` (bodies) resolve a `HealthComponent`. One hit per target per swing; a landed hit triggers `HitStop` |
| Posture | `scripts/combat/defense/posture_component.gd` | Filled by the poise damage of hits that land and of blocks. Recovery starts 1.2 s after the last posture damage, slows as health drops, and doubles while guarding and standing still. Full posture **breaks**: ignored damage for `break_duration`, then back to 0. The HUD shows it under the health bar |
| Guard and parry | `scripts/combat/defense/guard_component.gd`, `parry_system.gd` | Hurtbox defenders. **Guard** (hold) blocks hits from the front 150°: no health damage (optional non-lethal chip), poise damage to posture; a block that fills posture is a **guard break** (2.5 s stagger). Unblockable hits pass. **Parry** runs first: each press opens a 0.15 s real-time window; a parryable hit inside it deals the attacker 3x its poise damage to posture and staggers them. Presses within 0.4 s after a window closes open nothing (spam lockout); a successful parry lifts it |
| Combat director | `scripts/ai/combat_director.gd` | One per encounter. At most 2 attack tokens (leases: released on attack end, stagger and death, expiring after 4 s), 0.8 s between releases and the next issue. Everyone else circles on a 5 m ring of evenly spaced slots whose gap sits behind the player, so enemies stay on screen; slots are sticky (1.5 m hysteresis) |
| Humanoid enemies | `scripts/ai/enemy_combat_controller.gd`, `scenes/mobs/enemy_grunt.tscn`, `enemy_brute.tscn` | With a token: approach to 2 m and strike; without: flank. Every strike glints 0.4 s before its active frames: **gold** (blockable and parryable) or **red** (unblockable: dodge it). Grunts are quick with low posture; Brutes are slow and heavy (slam, sweep, red thrust). A broken posture can be **executed** with a light attack |
| Gatekeeper | `scripts/ai/gatekeeper.gd`, `scenes/mobs/enemy_gatekeeper.tscn` | Two-phase Brute with a health and posture bar at the top of the HUD. At 50 % health it roars (invulnerable), recovers 20 % faster, regenerates posture twice as fast and adds a red unblockable combo. Its execution deals 40 % of its health |
| Hit reactions | `scripts/combat/defense/damage_reaction_component.gd` | Shared by the player and the wolves. Poise below 30 → a light flinch by direction (front/back/left/right); from 30 → heavy; from 60, or a posture break → animated knockdown (D8). Sets knockback; the owner plays the clip and locks controls or AI until `stagger_ended` |
| Health | `scripts/combat/health_component.gd`, `hurtbox.gd`, `hit_info.gd` | Reusable node with `damaged` / `died` / `health_changed` signals and `grant_invulnerability()` for i-frames. `Hurtbox.receive_hit()` runs registered defenders (guard, parry) before health and posture, and returns a `HitInfo.Result` (HIT, BLOCKED, PARRIED…). `HealthComponent.resolve()` accepts a Hurtbox, a HealthComponent, or a body with one as a child |
| Time scale | `scripts/core/time_scale.gd` | The only writer of `Engine.time_scale`: named requests, and the slowest one wins, so a hit-stop ending mid slow-motion can't snap time back to 1.0 |
| Hit-stop | `scripts/combat/hit_stop.gd` | Static utility (not an autoload): a `TimeScale` request at 0.03 for the strike's duration. Overlapping requests extend; the timer ignores time scale |
| Sheathing | `scripts/combat/weapon_holster.gd` | After **3.0 s** without attacking or guarding, the katana reparents (keeping its world pose) and tweens position plus quaternion (slerp) from the `weapon_r` hand bone to the `scabbard` bone on the left hip. Drawing takes 0.12 s, before the first active frame. `snap_weapon_to_hand()` / `snap_weapon_to_sheath()` are there for animation method tracks |
| Sword trail | `katana.gd` → `TrailRenderer` | **GPU_PARTICLES**: one particle glued to the blade by `shaders/sword_trail_particles.gdshader`, with a `RibbonTrailMesh` skinned along its path. **MESH**: `sword_trail_mesh.gd` stitches blade base and tip samples. AUTO picks MESH on Intel iGPUs (see below) |
| Hitbox | `scripts/combat/hitbox.gd` | Shared by the katana and the wolf's jaws: arm it with an `AttackData`, open or close the active window, and it hits each target once per activation. Hits go through the target's `Hurtbox` even when the body is touched first, so defenders can't be bypassed |
| Wolf AI | `scripts/mobs/wolf.gd`, `scenes/mobs/wolf.tscn` | **WANDER**: a random navmesh point within 15 m of home every 4 s. **CHASE**: the 10 m detection `Area3D`, repath every 0.25 s, arrival braking (v = √(2·a·d)). **BITE**: telegraphed 0.34 s wind-up that tracks you, then a lunge with an active jaw window (`wolf_bite.tres`, 12 dmg) and a 1.4–2.2 s cooldown; striking the wolf during the wind-up cancels it. **STAGGER**: knockback, flinch, white flash. **DEAD**: death animation, collision disabled (deferred), sink, `queue_free` |
| Player health | `player.tscn` HealthComponent + Hurtbox, `scripts/ui/player_hud.gd` | 100 HP, 0.8 s i-frames. The FSM adds **HURT** (flinch plus knockback) and **DEAD** (kneel, respawn after 2.5 s). The HUD has a draining health bar, a hurt flash and a defeat banner |
| Touch controls | `scripts/ui/touch/` | Godot 4.7's built-in `VirtualJoystick` (dynamic), `TouchActionButton` (fires `InputEventAction`s, so the combo buffer works unchanged), `TouchLookPad` (multi-touch camera drag) |
| Placeholder rigs | `tools/build_placeholder_rigs.gd` | Generates the samurai skeleton (19 bones, rigid-skinned single mesh), wolf model, animation libraries and state machine. Attack swings are keyed from the AttackData timings |

Physics layers: 1 world · 2 player · 3 mobs · 4 player_hitbox · 5 mob_hurtbox · 6 mob_hitbox · 7 player_hurtbox.
The katana hitbox masks 3 and 5; the wolf's bite hitbox masks 7.

## Placeholder art pipeline

```
godot --headless --path . --script res://tools/build_placeholder_rigs.gd
```

Re-run after changing bones, poses or any strike's AttackData timings (`tests/test_data.gd` fails
on a stale build). To swap in real characters (Mixamo, Blender), keep the clip names listed in
`docs/vertical-slice/HANDOFF_MANIFEST.md` (every strike's `AttackData.animation`, `dodge_f/b/l/r`,
`idle`, `run`, the guard, parry and hurt clips, `death`; wolf: `idle`, `walk`, `run`, `bite`, `hurt`, `death`) and the socket
bones (`weapon_r`, `scabbard`). Or point the sockets and state machine at the new names, then set
the AttackData timings to match the clips.

## Differences from the original spec

- **`OpenSimplexNoise` no longer exists in Godot 4.** The wind uses `FastNoiseLite`
  `TYPE_SIMPLEX_SMOOTH` (OpenSimplex2S) in a seamless `NoiseTexture2D`.
- **Godot 4.7 lights have no contact-shadow property.** Soft contact shadows come from PCSS
  (`light_angular_distance`) plus SSAO on HIGH.
- **The sword trail is a switchable renderer.** The spec's GPUParticles3D ribbon is the default,
  except on Intel integrated GPUs, where particle trails lost the Vulkan device and didn't
  render on D3D12 (UHD G1, driver 31.0.101.2135). There, a CPU mesh ribbon with the same look is
  used. Force either with Katana → `trail_renderer`.
- **Wolves use an animated death, not a ragdoll** (the spec allowed either). Collision is disabled, then the corpse sinks and frees itself.

## Tuning cheatsheet

| Want to change… | Where |
|---|---|
| Strike feel (damage, timing, lunge, hit-stop, cancels) | `resources/combat/attack_*.tres`, `heavy_*.tres`, `draw_attack.tres` |
| Combo branches | `resources/combat/sword_combo.tres` (ComboGraph: edit the nodes' `next` in the inspector) |
| Input buffer / chain reset | Player ▸ Combat ▸ ComboManager → `buffer_window`, `combo_reset_time` |
| Dodge / sheathe delay | Player ▸ Combat → `dodge_distance`, `dodge_iframes`, `sheathe_delay` |
| Lunge steering | Player ▸ Combat ▸ MotionWarping → `max_warp_distance`, `max_warp_angle`, `stop_distance` |
| Wolf behaviour | `wolf.tscn` → `wander_radius`, `wander_interval`, `run_speed`, `chase_stop_distance`, `bite_cooldown`; `resources/combat/wolf_bite.tres`; HealthComponent `max_health`; DetectionArea sphere radius |
| Player toughness | `player.tscn` ▸ HealthComponent `max_health`, `invulnerability_time`; Combat `respawn_delay` |
| Guard, parry and posture | Player ▸ ParrySystem → `parry_window`, `spam_lockout`, `posture_reflect_multiplier`; GuardComponent → `guard_arc_degrees`, `chip_damage`, `guard_break_stagger`; PostureComponent → `max_posture`, `recovery_rate`, `recovery_delay`, `break_duration`; Combat → `guard_move_scale` |
| Enemy pressure | Encounter ▸ Director → `max_attack_tokens`, `token_cooldown`, `ring_radius`; enemy scene → `attack_cooldown`, `telegraph_lead`, `approach_distance`, `aggro_radius`; strikes in `resources/combat/enemies/` |
| Stagger tiers | DamageReaction (player and `wolf.tscn`) → `poise_threshold`, `knockdown_threshold`, `flinch_time`, `heavy_time`, `knockdown_time`, `parried_time`, `blocked_push` |
| Touch layout / feel | `scripts/ui/touch/touch_controls.gd` (button rects, joystick size); TouchLookPad `sensitivity` |
| Lock-on range, cone, camera framing | Player ▸ TargetingSystem → `radius`, `cone_degrees`, `break_distance`; Player ▸ CameraRig → `lock_*` |
| Wind / grass | `grass_material.tres` → `wind_*`, `push_*`; GrassField density |
| Sun / haze | Sun rotation X; Environment volumetric fog; ValleyMist density |
| Path route | Edit the ScenicPath curve, then **Terrain ▸ Regenerate** (landmarks and grass follow) |

## Command line (arguments after `--`)

```
godot --path . -- --quality=low                 # force a preset
godot --path . -- --spawn-offset=62             # start 62 m along the path
godot --path . -- --capture=C:/tmp/shot.png     # render ~6 s, save one frame, quit
```
