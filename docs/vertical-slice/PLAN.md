# Vertical Slice Plan: Scenic Open World → 10-Minute Martial Arts Combat Demo

Branch: `vertical-slice-prototype` · Source runbook: *Production Runbook: 10-Minute Martial Arts
Combat Vertical Slice (Godot 4.7)* · Drafted 2026-09-25 against `main` @ `1b73ff8`.

This plan compares the runbook with what the starter kit already ships. It lists what must be
**built**, **prompted**, **uploaded**, **purchased** and **approved** to turn the kit into a
polished (non-greybox) 10-minute demo. Companion files:

- [`PROMPTS.md`](PROMPTS.md): the runbook's prompts, rewritten to extend this codebase instead of
  replacing it.
- [`HANDOFF_MANIFEST.md`](HANDOFF_MANIFEST.md): the class and signal contract that the runbook's
  handoff protocol (§1.3) asks for. Hand it to any model before a task.

---

## 1. Summary

The starter kit covers roughly **35% of the runbook's code surface**, and those systems are
often more robust than the runbook's versions. The missing pieces are the defensive layer
(posture, guard, parry), the encounter layer (director, humanoid enemies, lock-on, boss), the
game loop (menu, checkpoints, beats, victory) and **all production art and audio**. The kit
has no audio files and no non-procedural meshes. Every character and animation comes from
`tools/build_placeholder_rigs.gd`.

**The critical path is art, not code.** Specifically, it's the animations, which the runbook
never mentions. Each component in the runbook takes an AI session hours. A polished duelist
needs about 45 animation clips, and the runbook has no step that produces them.

| Area | Runbook section | Kit status | Work |
|---|---|---|---|
| Toolchain / validation | 1.0 | Forward+, SDFGI, volumetric fog, Jolt, web export all set up. **No tests, no CI, no Godot binary in cloud sessions** | Add test runner, CI and a session hook |
| Art and environment | 2.0 | Procedural terrain, grass, torii and lanterns. **Placeholder rigid-skinned rigs only** | Everything (see §4) |
| Offensive core | 3.0 | `AttackData`, `Hitbox`, `CombatStateMachine` (buffer and 3-hit chain), `WeaponHolster`, soft-lock lunge, `HitStop`, sword trails | Extend: branching combos, heavy, special, dodge, Iai, motion warp |
| Defensive and reaction | 4.0 | `HealthComponent` with i-frames, `Hurtbox`, player HURT and DEAD, wolf STAGGER | Build posture, guard, parry and directional stagger. Refactor the hit pipeline |
| AI and cameras | 5.0 | Wolf FSM (wander, chase, telegraphed bite, stagger, dead) on a navmesh. Camera is built into `PlayerController` | Build the director, humanoid enemy controller, boss, targeting and combat camera |
| Audio, polish and loop | 6.0 | Health bar HUD, dev HUD, touch controls | Build audio, trauma, combat HUD, GameManager, checkpoints and the 3-beat level |

---

## 2. Gap Analysis (runbook component → codebase)

Legend: ✅ exists and meets the spec · 🟡 partial, extend it · ❌ missing · ⚠️ the runbook spec
should be changed (see §3).

### 2.1 Offensive core (runbook §3)

| Runbook component | Existing equivalent | Status | Delta |
|---|---|---|---|
| `AttackData.gd` | `scripts/combat/attack_data.gd` | 🟡 | Has damage, timing windows, lunge, `hitstop`, `stagger_time` and `knockback`. **Add** `poise_damage`, `damage_type` (BLUNT, SLASH, PIERCE), `knockback_direction_override`, `unblockable`, `can_be_parried`, `trauma` and `cancel_windows`. Keep the existing field names; the runbook's `hit_stop_duration` and `knockback_force` duplicate them |
| `HitboxArea3D.gd` | `scripts/combat/hitbox.gd` (`Hitbox`) | ✅⚠️ | Already hits each target once per activation, has faction-safe `source` and hit-stop. **Change:** route hits through `Hurtbox.receive_hit()` instead of `HealthComponent.take_damage()` directly, so guard and parry can intercept them. Add a `hit_position` to `HitInfo` |
| `ComboManager.gd` | `CombatStateMachine` (`scripts/combat/combat_state_machine.gd`) | 🟡 | Has a single-press 0.35 s buffer and a linear chain of three. **Missing:** a FIFO multi-action buffer, heavy and special attacks, dodge, branching chains, stances, animation-driven cancel windows and a `combo_reset` signal. Split the combo graph out of the FSM into a `ComboManager` node and a `ComboNode` resource graph |
| `MotionWarping.gd` | `_attack_direction()` soft-lock plus `PlayerController.begin_attack()` lunge | 🟡⚠️ | Snaps facing to the nearest enemy within 3.5 m and a 70° half-angle, then lunges at a fixed speed. **Missing:** distance-aware warp with a stop distance, and a hard-lock target from `TargetingSystem`. Must drive `velocity` through `move_and_slide()`, never tween `position` (see §3) |
| `WeaponManager.gd` | `scripts/combat/weapon_holster.gd` (`WeaponHolster`) | 🟡 | Tweens between hand and back sockets, 3.0 s sheathe. **Missing:** hip-left sheath socket, Iai quick-draw attack from sheathed, `stance_changed`, animation method-track hooks |
| `Player.tscn` hierarchy | `scenes/player/player.tscn` | 🟡 | Same shape. Rename and reparent `Combat` → `CombatController` with `ComboManager`, `MotionWarping` and `WeaponManager` children. Add `TargetingSystem`, `PostureComponent`, `GuardComponent`, `ParrySystem`, `DamageReactionComponent` and `CameraTrauma` |

### 2.2 Defensive and reaction (runbook §4)

| Runbook component | Existing | Status | Delta |
|---|---|---|---|
| `HealthComponent.gd` | `scripts/combat/health_component.gd` | ✅⚠️ | Has i-frames and damaged, died and health_changed signals, plus revive and heal. **Keep `take_damage(hit: HitInfo)`.** The runbook's `take_damage(amount: float)` would drop the source, knockback and stagger |
| `HurtboxArea3D.gd` | `scripts/combat/hurtbox.gd` (10 lines) | 🟡 | Add `receive_hit(hit: HitInfo) -> HitInfo.Result`, a defender chain (parry → guard → health and posture), and a `hit_received` signal |
| `PostureComponent.gd` | — | ❌ | New |
| `GuardComponent.gd` | — | ❌ | New. Needs a `guard` input action, guard animations and a guard-break state |
| `ParrySystem.gd` | — | ❌ | New. 0.15 s window on guard *press*; reflects posture damage and recoils the attacker |
| `DamageReactionComponent.gd` | Player `HURT` state, wolf `STAGGER` | 🟡 | Not directional, no poise threshold, no knockdown. Lift the reaction into a shared component used by the player and every enemy |

### 2.3 AI and cameras (runbook §5)

| Runbook component | Existing | Status | Delta |
|---|---|---|---|
| `CombatDirector.gd` | — | ❌ | New per-encounter node (not an autoload), so arena resets are trivial |
| `EnemyCombatController.gd` | `scripts/mobs/wolf.gd` | 🟡 | The wolf FSM already has a 0.34 s telegraphed wind-up, a navmesh chase, stagger and death. **Generalise** into a humanoid controller: FLANKING state, token requests, glint telegraphs, attack patterns from `AttackData` arrays, and posture. Keep the wolves as Beat 1 fodder |
| Boss / Gatekeeper | — | ❌ | Not in the runbook's prompts, but the loop requires one (`SANCTUM_GATEKEEPER`). A two-phase brute variant with red-glint unblockables |
| `TargetingSystem.gd` | Soft-lock only | ❌ | New: 18 m radius, 70° cone, hard lock, cycling |
| `CombatCamera3D.gd` | Camera code in `PlayerController` (SpringArm3D and sphere already) | 🟡 | Extract it from `PlayerController` into its own node, then add lock-on dual-focus framing |

### 2.4 Audio, polish and loop (runbook §6)

| Runbook component | Existing | Status | Delta |
|---|---|---|---|
| `SurfaceFoleyAudio3D.gd` | — (terrain has a gravel path mask in vertex colour) | ❌ | New. Surface comes from the path mask on the terrain and from `PhysicsMaterial` or metadata on courtyard props |
| `CombatAudioPlayer3D.gd` | — | ❌ | New, and needs sourced audio (§5) |
| `CameraTrauma.gd` | — | ❌ | New. Attach to `Camera3D` h/v offset and rotation, not the SpringArm |
| `CombatHUD.gd` | `scripts/ui/player_hud.gd` (health bar, hurt flash, defeat banner) | 🟡 | Add a posture bar, enemy gauge and lock reticle. Keep the drain and flash code |
| `GameManager.gd` | `scripts/main.gd` (spawn only) | ❌ | New autoload: state flow, death slow-motion and respawn, encounter reset |
| `CheckpointShrine.gd` | `scenes/landmarks/stone_lantern.tscn` | 🟡 | Reuse the lantern as the shrine's placeholder until the art lands |
| Start menu, pause, victory | — | ❌ | New scenes |
| Tests (`res://tests/…`) | — | ❌ | New |

---

## 3. Corrections to the Runbook

These are places where following the runbook literally would break working code or ship a
worse result.

1. **Physics layers conflict.** The runbook puts all hurtboxes on layer 4 and all hitboxes on
   layer 5. The kit already has faction-split layers (4 player_hitbox, 5 mob_hurtbox,
   6 mob_hitbox, 7 player_hurtbox), which stop enemies hitting each other without any code.
   **Keep the kit's layers.** Every prompt in `PROMPTS.md` has been rewritten to match.
2. **`take_damage(amount: float)` is a regression.** `HitInfo` already carries the source,
   knockback and stagger, and parry needs the attacker reference. Extend `HitInfo` instead.
3. **Guard and parry need an interception point that doesn't exist yet.** `Hitbox` calls
   `HealthComponent.take_damage()` directly, so guard and parry would have to monkey-patch it.
   Refactor this first:
   `Hitbox → Hurtbox.receive_hit(hit) → [ParrySystem → GuardComponent] → HealthComponent + PostureComponent`.
4. **Engine.time_scale has no owner.** `HitStop` sets `Engine.time_scale` and restores it to
   `1.0`. The runbook adds 0.25× death slow-motion and possibly execution slow-motion. The first
   hit-stop that ends during a slow-motion would snap time back to 1.0. **Add a `TimeScale`
   arbiter first** (a stack of requests; the minimum wins), and route `HitStop` through it.
5. **MotionWarping must not tween `position`.** A tween on a `CharacterBody3D` position skips
   collision and pushes the player into walls and enemies. Warp by setting the lunge velocity
   in `PlayerController` and let `move_and_slide()` resolve collisions. The existing lunge path
   already works this way.
6. **Organic characters shouldn't be modelled by LLM-driven `bpy`.** Prompt 2.2A asks a model
   to script a 15–25k-tri character, then weight it with `ARMATURE_AUTO`. Automatic weights on
   a scripted mesh deform badly at shoulders and hips, and that is the first thing a combat
   camera shows. Blender MCP is a good fit for **hard-surface** work (blade, scabbard, courtyard
   kit, shrine). Characters should come from a pack, AI generation plus clean-up, or a
   commission (decision D3).
7. **The runbook has no animation step.** This is the biggest hidden cost. The minimum clip list
   is in §4.3.
8. **Socket bones versus socket markers.** Custom bones (`Socket_Weapon_Hand_R` and others) must
   survive retargeting. Purchased or Mixamo rigs won't have them. Use `BoneAttachment3D` on the
   standard `RightHand`, `Hips` and `Head` bones, with `Marker3D` offset children named with the
   runbook's socket names. That works with any humanoid rig. Retarget clips through Godot's
   `SkeletonProfileHumanoid` `BoneMap` on import.
9. **`godot --headless --script res://tests/test_validation.gd` is not a validation step by
   itself.** A `--script` entry point must extend `SceneTree`, and it doesn't parse the rest of
   the project. `godot --import` doesn't catch parse errors either: it exits 0 with a broken
   script in the project (verified on 4.7.1). Validation is `bash tools/ci/validate.sh`: import,
   then a `SceneTree` runner whose `test_project.gd` loads every script and scene, and which
   fails any test that logs an engine error (§6, M0).
10. **UNARMED stance doubles the animation bill.** It needs a second locomotion and attack set.
    Cut it for the slice, and keep "sheathed" only as the Iai quick-draw entry (decision D7).
11. **"Knockdown ragdoll"** needs a `PhysicalBoneSimulator3D` setup per character plus a
    get-up blend. Use animated knockdowns in the slice, and ragdoll on death only if time allows
    (decision D8).
12. **The 0.15 s parry window collides with frame rate.** The README measures MEDIUM at about
    18 FPS on the dev laptop. At 18 FPS, 0.15 s is under 3 frames, and input-to-screen latency
    eats most of it. Either target a discrete GPU or a LOW or new COMBAT preset at 60 FPS, or
    widen the window. Decision D5.

---

## 4. Art and Animation Bill of Materials

### 4.1 Characters

| Asset | Runbook spec | Recommended source | Kit replacement target |
|---|---|---|---|
| Duelist (player) | 15–25k tris, tunic, bracers, sash, boots | Pack, AI-gen plus clean-up, or commission (D3). Mixamo auto-rig if it comes unrigged | `assets/characters/samurai/` → `assets/characters/player_duelist.glb` |
| Corrupted Grunt | Slender, tattered robe, emissive veins, glint socket | Same route. Shares the humanoid skeleton | new `enemy_grunt.glb` |
| Armored Brute | 1.25× height, 1.5× bulk, maul | Same route. Shares the skeleton, scaled | new `enemy_brute.glb` |
| Sanctum Gatekeeper (boss) | *Not in the runbook* | Brute variant: new material set, helm, larger weapon | new `enemy_gatekeeper.glb` |
| Wolf | — | Keep the placeholder for Beat 1, or replace it with a CC0 or pack wolf | `assets/characters/wolf/` |

### 4.2 Props and environment (Blender MCP is a good fit)

`duelist_blade.glb`, `duelist_scabbard.glb`, `brute_maul.glb`, and
`modular_courtyard_kit.glb` (flagstone floor 4×4, 4 m wall section, octagonal pillar, plus
**gate / portcullis**, **stairs**, **broken wall variant**, **debris scatter** and **banner**
for a non-greybox read). Also `checkpoint_shrine.glb` with `Marker3D_FlamePoint`, and a
`sanctum_gate.glb` set piece. The existing torii and lanterns stay as the Beat 1 dressing.

### 4.3 Animation clip list (minimum for "polished")

| Set | Clips | Count |
|---|---|---|
| Duelist locomotion | idle, walk, run, sprint, jump start/loop/land, strafe L/R/B (lock-on), turn-in-place | ~11 |
| Duelist offense | light 1–3, heavy 1–2, light→heavy branch, special, Iai quick-draw, draw, sheathe, sprint attack | ~11 |
| Duelist defense | guard idle, guard hit, guard break, parry ×2 (alternate), dodge F/B/L/R, hurt F/B/L/R, knockdown + get-up, death | ~14 |
| Grunt | idle, walk, run, strafe L/R, attack ×2, hurt ×2, parried recoil, stagger, death | ~12 (shared rig, so many clips can be reused for the Brute) |
| Brute and Gatekeeper | slam, sweep, unblockable thrust, recoil, posture break, execution victim, phase-2 roar | ~8 extra |
| Execution / deathblow | player finisher on posture break | 1–2 |

**Total: about 55 clips.** Mixamo covers locomotion, hurt and death reasonably well; its katana
coverage is thin. Sword-specific sets usually need a paid mocap pack or a mocap session
(decision D3b).

### 4.4 Audio bill

Footsteps (grass, gravel, stone, wood, 4–6 variants each). Blade whoosh (light, heavy),
impacts (flesh, armour, 3 layers), parry clang (×3), guard block (×3), posture break, dodge
cloth, draw and sheathe, Iai "shing", enemy vocals (grunt, brute, boss), glint cue (gold
parryable, red unblockable), checkpoint ignite, UI (confirm, back), ambient beds (valley wind,
courtyard, sanctum), and music (exploration, combat loop, boss, victory sting). About 70–90
files.

---

## 5. Decisions Needing Approval

Recommendations are marked ⭐. Nothing past M0 should start until D1–D5 are answered.

| # | Decision | Options | Why it matters |
|---|---|---|---|
| **D1** | Extend or rebuild | ⭐ **Extend the kit** (keep `Hitbox`, `HitInfo`, `HealthComponent` and the layers; add runbook components around them) · Rebuild to the runbook's names | Rebuilding throws away working, tested-in-play code, including the web and touch paths |
| **D2** | Physics layers | ⭐ Keep the kit's 7 faction layers · Adopt the runbook's shared 4/5 | See §3.1 |
| **D3** | Character art route | (a) CC0 packs (Quaternius, Kenney: free, stylised, low-poly) · (b) ⭐ **paid stylised pack plus Mixamo or a mocap pack** · (c) AI 3D generation (Hyper3D Rodin, Hunyuan3D, Meshy and similar) plus manual retopo and Mixamo rig · (d) commission a character artist | Sets the visual bar and the budget. (c) is fastest, but its topology needs clean-up before it animates well |
| **D3b** | Sword animation source | Mixamo only (free, thin katana set) · ⭐ **paid katana mocap pack** · self-capture (Rokoko, Move.ai) | Combat feel lives here |
| **D4** | Platform target for the slice | ⭐ **Desktop Forward+ only; web is best-effort** · Keep web and touch at parity | Web has no SDFGI or fog, and skinned-mesh crowds on WebGL2 tablets are a performance risk. Touch needs 4 new buttons (guard, dodge, lock, heavy) |
| **D5** | Performance target | ⭐ **60 FPS on a discrete GPU; a 30 FPS COMBAT preset on the Intel UHD laptop** · Tune everything for the laptop | Parry and dodge windows depend on it (§3.12) |
| **D6** | Sheath position | ⭐ **Hip-left (runbook)**: needed to sell the Iai quick-draw · Keep the kit's back scabbard | Changes the socket, the draw animations and the holster tween |
| **D7** | UNARMED stance | ⭐ **Cut** (sheathed is only the Iai entry) · Keep | Halves the duelist's animation bill |
| **D8** | Ragdolls | ⭐ **Animated knockdown; ragdoll on death only if M9 has slack** · Full ragdoll | Scope |
| **D9** | Art direction | ⭐ **Golden-hour approach (Beat 1) → dusk courtyard (Beat 2) → night sanctum with volumetric shafts (Beat 3)**, which shifts the kit's calm look toward the runbook's dark fantasy · Keep golden hour throughout | Environment presets per beat; needs `WorldEnvironment` blending in the GameManager |
| **D10** | Input devices | ⭐ **KBM plus gamepad** (the runbook's right-stick target cycling implies a gamepad) · KBM only | Adds gamepad bindings to `_DEFAULT_BINDINGS` |
| **D11** | Test framework | ⭐ **Custom `SceneTree` runner** (no dependency) · GUT addon (MIT) | CI simplicity versus richer assertions |
| **D12** | Branch strategy | ⭐ **`vertical-slice-prototype` as the integration branch; one PR per milestone into it; merge to `main` at M10** · Commit straight to the branch | Reviewability, plus the runbook's "clean baseline per step" rule |
| **D13** | Wolves | ⭐ **Keep them as Beat 1 tutorial enemies** · Remove | Free content that is already tuned |
| **D14** | Multi-model routing | The runbook splits work across Claude, Gemini and Codex. ⭐ **Any model, with `HANDOFF_MANIFEST.md` plus one component per session, validated by CI** | Credit budget; the manifest and CI make the handoff safe regardless of model |

### 5.1 Decision log (approved 2026-09-25)

| # | Decision |
|---|---|
| D1, D2, D5–D14 | ⭐ defaults approved |
| D3 / D3b | **AI 3D generation plus free assets**: AI-generated characters and props, rigged and animated with **Mixamo**, filled out with **Quaternius** and **Kenney** (CC0) assets and animation sets. No paid packs for now |
| D4 | **Keep web and touch at parity, best effort.** Every new player action gets a touch button (heavy, dodge, guard, lock-on, interact) in the milestone that adds it, and `?quality=low` web builds must stay playable. Web-only fallbacks (no SDFGI or volumetric fog) are acceptable |

Consequences:
- **Katana animation is now the biggest art risk.** Mixamo and Quaternius have generic sword
  sets, not katana-specific ones. Plan on retiming generic clips through `AttackData` and
  hand-keying Iai, parry and execution in Blender. If combat feel falls short at the M5
  playtest, revisit D3b.
- AI-generated meshes need a clean-up pass (retopology or decimation, UV check, weight check)
  before Mixamo auto-rigging. Budget it as part of M2.
- Web parity means skinned-mesh counts and tri budgets have to be checked on the tablet at M6
  and M8, not only at M10.

---

## 6. Milestones (mapped to runbook §7 steps 01–10)

Time columns: **AI** = agent implementation plus validation time; **Human** = what a mid-level
Godot developer would need for the same work. The AI figures assume the decisions above are
already made and assets are on disk. Art and animation production dominate calendar time
either way.

| M | Runbook step | Deliverable | Key files | Blocks on | AI | Human |
|---|---|---|---|---|---|---|
| **M0** ✅ | 01 | Godot 4.7 headless in CI and in the Claude session hook; `tests/run_tests.gd` runner; parse gate that loads every script and scene; smoke tests for the existing `Hitbox`, `HealthComponent` and `CombatStateMachine` | `.github/workflows/validate.yml`, `tests/`, `.claude/hooks/` | D11 | 1–2 h | 1–2 d |
| **M1** ✅ | — (prereq) | **Hit pipeline refactor**: `TimeScale` arbiter, `HitInfo` v2, `Hurtbox.receive_hit`, `HitInfo.Result`. No gameplay change; the wolves and the samurai play the same | `scripts/core/time_scale.gd`, `scripts/combat/hit*.gd`, `hurtbox.gd` | D1, D2 | 1–2 h | 1–2 d |
| **M2** | 02 | Art pass 1: blade, scabbard, courtyard kit and shrine via Blender MCP; characters via the D3 route; animation set via D3b; import presets with `BoneMap` retarget | `assets/**` | D3, D3b, D6, **purchases** | 2–4 h agent + user Blender sessions | 3–6 wk (art) |
| **M3** | 03 | Offense: `AttackData` v2, `ComboManager` (FIFO buffer, branching graph, cancel windows), heavy, special, dodge with i-frames, `MotionWarping`, `WeaponManager` (hip sheath, Iai) | `scripts/combat/` | M1 (placeholder rig is fine until M2 lands) | 4–6 h | 1–2 wk |
| **M4** | 04 | Headless validation #1: `tests/test_combat_core.gd` covers the buffer, chain branching, warp clamps and hitbox once-per-target | `tests/` | M3 | 1 h | 1–2 d |
| **M5** | 05 | Defense: `PostureComponent`, `GuardComponent`, `ParrySystem`, `DamageReactionComponent` (directional, poise, knockdown); player and wolves wired up; tests | `scripts/combat/defense/` | M1 | 4–6 h | 1–2 wk |
| **M6** | 06 | AI: `CombatDirector` (tokens, flank ring), `EnemyCombatController` (humanoid), Grunt and Brute scenes, telegraph glint VFX, Gatekeeper boss (2 phases) | `scripts/ai/`, `scenes/mobs/` | M5, M2 characters (or placeholder humanoid) | 6–10 h | 2–3 wk |
| **M7** | 07 | `TargetingSystem` (hard lock, cycling on mouse wheel and right stick), `CombatCamera3D` extracted from `PlayerController` with dual focus; strafe locomotion while locked | `scripts/camera/`, `player_controller.gd` | M3 | 3–5 h | 1 wk |
| **M8** | 08 | Level assembly: Beat 1 on the existing scenic path, then the courtyard at the path's end, then the sanctum gate. Encounter volumes, arena gates, navmesh, per-beat environments (D9) | `scenes/levels/`, `scenes/main.tscn` | M2 environment kit, M6 | 3–5 h agent + editor dressing | 1–2 wk |
| **M9** | 09 | Audio (foley, impacts, parry, music), `CameraTrauma`, `CombatHUD`, VFX (hit sparks, parry flash, glints, blood or ink decals), `GameManager`, `CheckpointShrine`, menu, pause, victory | `scripts/audio/`, `scripts/ui/`, `scripts/game/` | M6–M8, **audio purchases** | 5–8 h | 2–3 wk |
| **M10** | 10 | End-to-end 10-minute playtest, tuning pass, performance pass per D5, desktop export (plus web if D4), README update, capture a demo video | — | all | 2–4 h + human playtests | 1–2 wk |

**Totals (rough):** agent ≈ 35–55 h of implementation spread over many sessions. A solo human
developer would need about **10–16 weeks**, with art and animation as the long pole. With AI
code assistance and purchased art, calendar time is roughly **4–6 weeks**, gated by asset
availability and playtest iterations.

**Parallel tracks.** M2 (art) runs alongside M1, M3, M5 and M7, which work on the placeholder
rig. The runbook's order puts art at step 02, which would idle the code track for weeks.

### 6.1 The 10-minute beat sheet (design target for M8 and M10)

| Time | Beat | GameManager state | Content | Teaches |
|---|---|---|---|---|
| 0:00–0:30 | Title | `START_MENU` | Menu, then fade in on the path start | — |
| 0:30–3:00 | Approach path (the kit's valley, recoloured toward dusk) | `EXPLORATION` | 2 wolf encounters (1, then 2 wolves); **Shrine 1** at the torii before the courtyard | Light combo, dodge, guard, then parry via context prompts |
| 3:00–6:30 | Courtyard ambush | `COURTYARD_AMBUSH` | Gates close. Wave 1: 3 grunts. Wave 2: 3 grunts and 1 brute. Wave 3: 2 brutes and 2 grunts. Director tokens = 2 | Lock-on, heavy branch, posture breaks, gold vs red glint |
| 6:30–7:00 | Breather | `EXPLORATION` | **Shrine 2** at the sanctum steps; gate opens | Checkpoint |
| 7:00–9:30 | Sanctum Gatekeeper | `SANCTUM_GATEKEEPER` | Boss phase 1 (slams, sweeps), phase 2 at 50% HP (unblockable thrusts, faster posture regen), execution on posture break | Everything |
| 9:30–10:00 | Victory | `VICTORY_SCREEN` | Stats (time, parries, deaths), then return to menu | — |

### 6.2 Acceptance criteria for "polished vertical slice"

- [ ] No placeholder or greybox mesh visible on the golden path. Every visible asset has a
  documented license in `assets/LICENSES.md`.
- [ ] Every player action has animation, audio and VFX feedback (the hit, parry, guard, dodge
  and posture-break "trinity").
- [ ] A first-time player finishes in 8–12 minutes (median of 3 playtests) with fewer than 5
  deaths.
- [ ] Holds the D5 frame-rate target through the full playthrough; no hitch over 50 ms outside
  loading.
- [ ] Death, respawn at the checkpoint and encounter reset work in every beat, with no
  soft-locks after 3 deliberate deaths per beat.
- [ ] CI is green: import parse gate plus all tests.
- [ ] One-click desktop export; the README describes the controls for the new actions.

---

## 7. Checklist: What You (Sasha) Need to Provide

### 7.1 Approve
- [ ] Decisions D1–D14 (§5). The ⭐ defaults stand unless you override them.
- [ ] A budget ceiling for art, animation and audio purchases (§7.3).
- [ ] The branch strategy: milestone PRs into `vertical-slice-prototype` (D12).

### 7.2 Upload or provide
- [ ] **Concept or reference images** for the Duelist, Grunt, Brute, Gatekeeper and the
  courtyard mood (your Nano Banana prompt composer can produce these).
- [ ] **Character and animation files** from the D3 and D3b route, as `.glb` or `.fbx`, into
  `assets/incoming/` for the import pipeline to process.
- [ ] **Audio files** (`.ogg` for loops and music, `.wav` for short SFX) into
  `assets/incoming/audio/`, each with its license or attribution line.
- [ ] **Blender MCP sessions run on your machine.** This cloud session has no Blender and no
  Godot editor. Run the §2 prompts in `PROMPTS.md` locally, or with your
  `godot-asset-pipeline` skill, and commit the `.glb` outputs.
- [ ] **Playtest recordings and notes** at M8 and M10.

### 7.3 Purchase (all optional; free routes exist)

Prices change often; check each vendor's current price and license before buying. Every entry
needs a license that allows **commercial redistribution inside a game built in a
non-original engine**. Some asset-store licences restrict use to their own engine or require
a separate grant.

| Item | Free route | Paid route | Priority |
|---|---|---|---|
| Stylised humanoid characters | Quaternius, Kenney (CC0) | Stylised fantasy character packs; AI 3D generation subscription; commission | High |
| Katana combat animations | Mixamo (free with an Adobe ID) | Katana or sword mocap pack | **Highest**: combat feel |
| SFX | Freesound (CC0 or CC-BY), Sonniss GDC bundles (royalty-free) | Sword and impact SFX libraries | High |
| Music | CC-BY tracks (for example from the Free Music Archive) | Licensed or commissioned score (4 cues) | Medium |
| Fonts | Google Fonts (OFL) | — | Low |
| VFX textures | Kenney particle pack (CC0) | — | Low |

### 7.4 Session and connector setup
- [ ] Allow the cloud environment to download the Godot 4.7.x Linux binary and export
  templates (network allowlist for GitHub releases), or approve a setup script (M0).
- [ ] Optional: a SessionStart hook so every Claude session can run the headless validation.

---

## 8. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Animation sourcing slips | High | High | Start D3b purchases now. Build M3, M5 and M7 on the placeholder rig with the same clip names |
| Retargeted clips break attack timing | High | Med | `AttackData` timings are per clip; add an importer tool that reads clip lengths and warns on mismatched windows |
| Frame rate too low for parry on the dev laptop | High | High | D5 COMBAT preset: SDFGI off in arenas, baked `LightmapGI` or `VoxelGI` for the courtyard |
| `Engine.time_scale` fights (hit-stop, slow-motion, pause) | Certain without M1 | Med | M1 `TimeScale` arbiter |
| Mixed licences on assets | Med | High | `assets/LICENSES.md` is required in every art PR |
| Multi-model handoff breaks contracts | Med | Med | `HANDOFF_MANIFEST.md` plus CI on every PR |
| Scope creep (unarmed stance, ragdolls, more enemies) | High | Med | D7 and D8 cuts. Anything new goes in `docs/vertical-slice/BACKLOG.md` |
