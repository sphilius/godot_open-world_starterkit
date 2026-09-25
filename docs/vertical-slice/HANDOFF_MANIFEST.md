# Handoff Manifest: Combat Architecture Contract

Give this page to any model (Claude, Codex, Gemini) before it works on one component (runbook
§1.3, step 2). It lists the public surface only. **Do not change an existing signature without
updating this file in the same PR.**

Conventions: Godot 4.7, statically typed GDScript, tabs, `##` doc comments. Designer-facing
numbers are `@export`s or `Resource`s. No autoloads except `GameManager` (planned). Static
utilities (`HitStop`, `TimeScale`) are `RefCounted` with static members.

## Physics layers (keep them; don't adopt the runbook's 4/5 scheme)

| Bit | Name | Who sits on it | Who scans it |
|---|---|---|---|
| 1 | world | terrain, props | player, mobs |
| 2 | player | player body | mobs, detection areas |
| 3 | mobs | mob bodies | player, katana hitbox |
| 4 | player_hitbox | katana `Hitbox` | — |
| 5 | mob_hurtbox | mob `Hurtbox` | katana `Hitbox` (mask 3 and 5) |
| 6 | mob_hitbox | bite, claw and maul `Hitbox` | — |
| 7 | player_hurtbox | player `Hurtbox` | mob `Hitbox` (mask 7) |

## Existing (on `main` @ 1b73ff8)

```gdscript
class_name AttackData extends Resource        # scripts/combat/attack_data.gd
  animation: StringName; damage: float
  duration, active_start, active_end, combo_window_open: float    # seconds from clip start
  lunge_speed, lunge_duration, lunge_delay, hitstop, stagger_time, knockback: float

class_name HitInfo extends RefCounted         # scripts/combat/hit_info.gd
  damage: float; source: Node3D; knockback: Vector3; stagger_time: float

class_name Hitbox extends Area3D              # scripts/combat/hitbox.gd
  signal hit_landed(target: HealthComponent, hit: HitInfo)
  var source: Node3D
  func begin(attack: AttackData) -> void      # arm and clear the once-per-target memory
  func set_active(on: bool) -> void; func is_active() -> bool

class_name Hurtbox extends Area3D             # scripts/combat/hurtbox.gd
  @export var health: HealthComponent

class_name HealthComponent extends Node       # scripts/combat/health_component.gd
  signal damaged(hit: HitInfo); signal health_changed(current: float, maximum: float); signal died(hit: HitInfo)
  @export max_health: float; @export invulnerability_time: float
  var current_health: float; var is_dead: bool
  func take_damage(hit: HitInfo) -> bool; func heal(amount: float) -> void; func revive() -> void
  static func resolve(node: Node) -> HealthComponent

class_name HitStop extends RefCounted         # static trigger(duration: float); writes Engine.time_scale

class_name WeaponHolster extends Node         # signals drawn, sheathed; draw(); sheathe(); is_drawn()

class_name Katana extends Node3D              # hitbox: Hitbox; begin_swing(attack); set_active(on)

class_name CombatStateMachine extends Node    # player "Combat" node
  signal state_changed(previous: State, current: State)
  enum State { IDLE, RUN, ATTACK_1, ATTACK_2, ATTACK_3, HURT, DEAD }
  func is_attacking() -> bool

class_name PlayerController extends CharacterBody3D
  func spawn_at(pos: Vector3, yaw: float) -> void; func respawn() -> void
  func begin_attack(direction: Vector3, lunge_speed: float, lunge_duration: float, lunge_delay := 0.0) -> void
  func end_attack() -> void; func lock_controls(locked: bool) -> void
  func apply_knockback(knockback: Vector3) -> void; func add_look_input(delta: Vector2) -> void
  func get_move_direction() -> Vector3; func get_facing() -> Vector3; func get_planar_speed() -> float

class_name Wolf extends CharacterBody3D       # group "enemies"; enum State { WANDER, CHASE, BITE, STAGGER, DEAD }
```

Input actions: `move_forward/back/left/right`, `jump`, `sprint`, `attack` (registered at
runtime in `PlayerController._DEFAULT_BINDINGS`). Groups: `enemies`, `navigation_source`.

## Planned (the contract that new code must implement)

```gdscript
# M1: hit pipeline (implemented)
class_name TimeScale extends RefCounted       # scripts/core/time_scale.gd
  static func push(id: StringName, scale: float) -> void   # effective scale = min of all pushed
  static func pop(id: StringName) -> void
  static func has(id: StringName) -> bool; static func get_scale() -> float; static func reset() -> void
  # HitStop.trigger() becomes push(&"hitstop", 0.03) + a real-time timer + pop
  # Every push must have a pop on every exit path. The death slow-motion pops before respawn.

class_name HealthComponent                    # v2, methods added
  func grant_invulnerability(seconds: float) -> void   # extends, never shortens, the current window
  func is_invulnerable() -> bool              # dodge i-frames and the boss roar use it

class_name HitInfo                            # v2, fields added (all optional, with defaults)
  poise_damage: float; damage_type: int (AttackData.DamageType); hit_position: Vector3
  unblockable: bool; can_be_parried: bool; attack: AttackData

  enum Result { IGNORED, HIT, BLOCKED, PARRIED, GUARD_BROKEN, KILLED }   # HitInfo.Result
  static func is_landed(result: Result) -> bool   # HIT or KILLED

class_name Hurtbox                            # v2
  signal hit_received(hit: HitInfo, result: HitInfo.Result)   # not emitted for IGNORED
  @export var health: HealthComponent
  @export var posture: Node                   # optional; anything with add_posture(amount) -> bool. Retype to PostureComponent in M5
  func receive_hit(hit: HitInfo) -> HitInfo.Result   # runs defenders in order, then health and posture
  func add_defender(d: Object) -> void        # anything with intercept(hit: HitInfo) -> HitInfo.Result (IGNORED = pass through)
  func remove_defender(d: Object) -> void
  static func find_for(node: Node, health: HealthComponent) -> Hurtbox   # a body's hurtbox, so body contacts can't bypass defenders
  # Returns IGNORED while health.is_invulnerable(), before any defender runs.
  # Hitbox routes every hit through the target's Hurtbox (found with find_for() when it touched the
  # body). Only targets without a Hurtbox take damage directly. Hit-stop and hit_landed fire only
  # on HIT or KILLED.

# M3: offense
class_name AttackData                         # v2, fields added
  enum DamageType { BLUNT, SLASH, PIERCE }
  poise_damage: float; damage_type: DamageType; knockback_direction_override: Vector3
  unblockable: bool; can_be_parried: bool; trauma: float; warp: bool
  cancel_open: float; cancel_into: Array[StringName]   # e.g. [&"dodge", &"attack_light"]

class_name ComboNode extends Resource         # a combo graph node
  attack: AttackData; next: Dictionary        # StringName action -> ComboNode

class_name ComboManager extends Node          # player CombatController/ComboManager
  signal attack_triggered(attack: AttackData); signal dodge_requested(direction: Vector2); signal combo_reset
  @export buffer_window := 0.25; @export combo_reset_time := 1.1; @export root: ComboNode; @export iai_root: ComboNode
  func push_input(action: StringName) -> void
  func open_cancel_window(allowed: Array[StringName]) -> void; func close_cancel_window() -> void

class_name MotionWarping extends Node
  signal warp_started(target: Node3D); signal warp_completed
  @export max_warp_distance := 3.5; @export max_warp_angle := 60.0
  func start_warp(target: Node3D, duration: float, stop_distance := 1.2) -> void   # sets lunge velocity; never tweens position

class_name WeaponManager extends Node         # replaces WeaponHolster (keeps its API and signals)
  signal weapon_drawn; signal weapon_sheathed; signal stance_changed(stance: int)
  func snap_weapon_to_hand() -> void; func snap_weapon_to_sheath() -> void   # AnimationPlayer method tracks

# M5: defense (all children of the character; all optional per character)
class_name PostureComponent extends Node
  signal posture_changed(current: float, maximum: float); signal posture_broken; signal posture_recovered
  @export max_posture := 100.0; @export recovery_rate := 15.0; @export recovery_delay := 1.2
  func add_posture(amount: float) -> bool     # true = broke
class_name GuardComponent extends Node        # defender: intercept(hit) -> BLOCKED / GUARD_BROKEN / IGNORED
  signal guard_started; signal guard_ended; signal guard_broken
  var is_guarding: bool; @export guard_break_stagger := 2.5; @export guard_arc_degrees := 150.0
class_name ParrySystem extends Node           # defender, runs before GuardComponent
  signal parry_successful(attacker: Node3D, point: Vector3)
  @export parry_window := 0.15; @export posture_reflect_multiplier := 3.0
  func on_guard_pressed() -> void
class_name DamageReactionComponent extends Node
  signal stagger_started(type: StringName); signal stagger_ended   # &"front", &"back", &"left", &"right", &"heavy", &"knockdown", &"guard_break", &"parried"
  @export poise_threshold := 30.0; @export knockdown_threshold := 60.0; @export friction := 18.0

# M6: AI
class_name CombatDirector extends Node        # one per encounter
  @export max_attack_tokens := 2; @export max_flank_tokens := 3; @export token_cooldown := 0.8; @export ring_radius := 5.0
  func request_attack_token(enemy: Node3D) -> bool; func release_attack_token(enemy: Node3D) -> void
  func get_flank_position(enemy: Node3D, player: Node3D) -> Vector3
  func register(enemy: Node3D) -> void; func unregister(enemy: Node3D) -> void
class_name EnemyCombatController extends CharacterBody3D
  signal telegraph_glint(position: Vector3, is_unblockable: bool); signal defeated
  enum State { IDLE, APPROACH, FLANKING, ATTACK_WINDUP, ATTACK_ACTIVE, RECOVER, STAGGERED, DEAD }
  @export attacks: Array[AttackData]; @export director: CombatDirector
  func reset_to_spawn() -> void               # used by GameManager encounter reset

# M7: targeting and camera
class_name TargetingSystem extends Node
  signal target_changed(target: Node3D)       # null = unlocked
  @export radius := 18.0; @export cone_degrees := 70.0
  var current_target: Node3D; func toggle_lock() -> void; func cycle(direction: int) -> void
class_name CombatCamera3D extends SpringArm3D
  @export targeting: TargetingSystem; func add_look_input(delta: Vector2) -> void
class_name CameraTrauma extends Node          # child of the Camera3D
  func add_trauma(amount: float) -> void      # presets: LIGHT 0.2, HEAVY 0.45, PARRY 0.35, EXECUTION 0.75

# M9: loop
GameManager (autoload)
  enum GameState { START_MENU, EXPLORATION, COURTYARD_AMBUSH, SANCTUM_GATEKEEPER, VICTORY_SCREEN }
  signal state_changed(previous: GameState, current: GameState)
  func set_checkpoint(shrine: Node3D) -> void; func on_player_died() -> void; func register_encounter(e: Node) -> void
class_name CheckpointShrine extends Area3D    # "interact" action; heals, saves the respawn transform, lights the lantern
```

## Animation clip names (the contract for AnimationLibraries, state machines and AttackData.animation)

Use these exact identifiers; retargeted source clips get renamed to them on import. The
`_loop` suffix only exists in the source files; drop it here. Directional sets use the suffixes
`_f`, `_b`, `_l` and `_r`.

| Character | Clips |
|---|---|
| Duelist, locomotion | `idle`, `walk`, `run`, `sprint`, `jump_start`, `jump_loop`, `jump_land`, `strafe_l`, `strafe_r`, `strafe_b`, `turn_l`, `turn_r` |
| Duelist, offense | `attack_1`, `attack_2`, `attack_3`, `heavy_1`, `heavy_2`, `heavy_finisher`, `special_1`, `sprint_attack`, `iai_draw`, `draw`, `sheathe` |
| Duelist, defense | `guard_idle`, `guard_hit`, `guard_break`, `parry_1`, `parry_2`, `dodge_f`, `dodge_b`, `dodge_l`, `dodge_r`, `hurt_f`, `hurt_b`, `hurt_l`, `hurt_r`, `hurt_heavy`, `knockdown`, `get_up`, `death`, `execution` |
| Grunt | `idle`, `walk`, `run`, `strafe_l`, `strafe_r`, `attack_1`, `attack_2`, `hurt_f`, `hurt_b`, `parried`, `stagger`, `death` |
| Brute and Gatekeeper | the Grunt set, plus `slam`, `sweep`, `thrust_unblockable`, `posture_break`, `executed`, `roar` |
| Wolf (existing) | `idle`, `walk`, `run`, `bite`, `hurt`, `death` |

`attack_1` to `attack_3`, `hurt` and `death` keep the kit's existing names, so the current state
machine keeps working until the new clips land. The Duelist's single `hurt` state maps to
`hurt_f` until DamageReaction (M5) picks the directional clips.

New input actions (M3, M5, M7, M9): `attack_heavy`, `attack_special`, `dodge`, `guard`,
`lock_on`, `target_next`, `target_prev`, `interact`, `pause`. Register them in
`_DEFAULT_BINDINGS`, with gamepad events if D10 is approved.

## Validation (every handoff)

```
bash tools/ci/validate.sh                  # downloads Godot 4.7.1 if needed, imports, runs every test
bash tools/ci/validate.sh --filter=hit     # only tests whose file or method name contains "hit"
```
`--import` alone exits 0 even when a script doesn't parse; `tests/test_project.gd` loads every
script and scene and is the real parse gate. Tests extend `TestCase` (`tests/lib/test_case.gd`)
and fail on any engine error logged while they run. Commit only when validation passes: `git commit -m "feat(combat): <component> (validated)"`.
