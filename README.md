# Scenic Open World: Godot 4.7 Forward+ prototype

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
| Move (camera-relative) | WASD / arrows | Thumbstick: touch anywhere on the left side |
| Look | Mouse | Drag anywhere else |
| **Attack (3-hit combo)** | **LMB / J** (keep pressing) | **ATK** (keep tapping) |
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

URL options: `?touch` forces the touch UI, and `?quality=low|medium|high` picks a preset (web defaults to LOW).

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
├─ Player              player.tscn (see below)
└─ DevHUD              FPS, quality presets, screenshots, CLI capture

Player (CharacterBody3D, player_controller.gd: movement, camera, lunge/lock hooks)
├─ Visual/SamuraiModel  generated rig: Skeleton3D + skinned mesh + HandSocket/BackSocket (BoneAttachment3D)
├─ Katana               katana.tscn: blade, Area3D Hitbox, Trail (GPUParticles3D), MeshTrail
├─ AnimationTree        StateMachine root: idle, run, attack_1..3 (physics-process callback)
├─ WeaponHolster        tweens the katana between the hand and back sockets
├─ Combat               CombatStateMachine: IDLE/RUN/ATTACK_1..3, input buffer, active frames, sheathing
└─ CameraRig/SpringArm3D/Camera3D
```

### World

| System | File | Key ideas |
|---|---|---|
| Player | `scripts/player/player_controller.gd` | Exponential look/follow smoothing; rig follows the *physics-interpolated* body; separate accel/decel and air control; `floor_snap_length` ground snapping; `begin_attack()` locks steering and lunges |
| Terrain | `scripts/world/heightmap_terrain.gd` | FBM meadow + ridged mountains; path cross-section levelled; path mask in vertex colour; triangle-exact `height_at()` |
| Grass | `scripts/world/grass_field.gd` + `shaders/grass.gdshader` | 100 MultiMesh chunks; scrolling simplex wind gusts; radial player push; distance shrink-fade |
| Path + landmarks | `scripts/world/scenic_path.gd` | Torii every 36 m, lanterns every 11 m on alternating sides, all on the terrain surface |

### Combat and mobs

| System | File | Key ideas |
|---|---|---|
| Combat FSM | `scripts/combat/combat_state_machine.gd` | Owns the logic; drives the AnimationTree with `playback.travel()`. An attack press is buffered for **0.35 s**. It chains at `max(combo_window_open, active_end)`, so presses during the wind-up aren't lost and swings are never cut short |
| Attack data | `resources/combat/attack_*.tres` (`AttackData`) | Per strike: damage, active window, combo window, lunge, hit-stop, stagger, knockback. Designer-tunable |
| Katana | `scripts/combat/katana.gd`, `scenes/weapons/katana.tscn` | `Area3D` hitbox on the weapon-bone socket. `area_entered` (hurtboxes) and `body_entered` (bodies) resolve a `HealthComponent`. One hit per target per swing; a landed hit triggers `HitStop` |
| Health | `scripts/combat/health_component.gd`, `hurtbox.gd`, `hit_info.gd` | Reusable node with `damaged` / `died` / `health_changed` signals. `HealthComponent.resolve()` accepts a Hurtbox, a HealthComponent, or a body with one as a child |
| Hit-stop | `scripts/combat/hit_stop.gd` | Static utility (not an autoload): `Engine.time_scale` 0.03 for the strike's duration. Overlapping requests extend; the timer ignores time scale |
| Sheathing | `scripts/combat/weapon_holster.gd` | After **3.0 s** without attacking, the katana reparents (keeping its world pose) and tweens position plus quaternion (slerp) from the `weapon_r` hand bone to the `scabbard` back bone. Drawing takes 0.12 s, before the first active frame |
| Sword trail | `katana.gd` → `TrailRenderer` | **GPU_PARTICLES**: one particle glued to the blade by `shaders/sword_trail_particles.gdshader`, with a `RibbonTrailMesh` skinned along its path. **MESH**: `sword_trail_mesh.gd` stitches blade base and tip samples. AUTO picks MESH on Intel iGPUs (see below) |
| Hitbox | `scripts/combat/hitbox.gd` | Shared by the katana and the wolf's jaws: arm it with an `AttackData`, open or close the active window, and it hits each target once per activation |
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

Re-run after changing bones, poses or `attack_*.tres` timings. To swap in real characters
(Mixamo, Blender), keep the animation names (`idle`, `run`, `attack_1..3`; wolf: `idle`,
`walk`, `run`, `hurt`, `death`) and the socket bones (`weapon_r`, `scabbard`). Or point the
sockets and state machine at the new names, then set the AttackData timings to match the clips.

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
| Combo feel (damage, timing, lunge, hit-stop) | `resources/combat/attack_1..3.tres` |
| Input buffer / sheathe delay | Player ▸ Combat → `input_buffer_seconds`, `sheathe_delay` |
| Wolf behaviour | `wolf.tscn` → `wander_radius`, `wander_interval`, `run_speed`, `chase_stop_distance`, `bite_cooldown`; `resources/combat/wolf_bite.tres`; HealthComponent `max_health`; DetectionArea sphere radius |
| Player toughness | `player.tscn` ▸ HealthComponent `max_health`, `invulnerability_time`; Combat `respawn_delay` |
| Touch layout / feel | `scripts/ui/touch/touch_controls.gd` (button rects, joystick size); TouchLookPad `sensitivity` |
| Wind / grass | `grass_material.tres` → `wind_*`, `push_*`; GrassField density |
| Sun / haze | Sun rotation X; Environment volumetric fog; ValleyMist density |
| Path route | Edit the ScenicPath curve, then **Terrain ▸ Regenerate** (landmarks and grass follow) |

## Command line (arguments after `--`)

```
godot --path . -- --quality=low                 # force a preset
godot --path . -- --spawn-offset=62             # start 62 m along the path
godot --path . -- --capture=C:/tmp/shot.png     # render ~6 s, save one frame, quit
```
