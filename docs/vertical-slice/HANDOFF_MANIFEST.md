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

class_name WeaponHolster extends Node         # (runbook: WeaponManager) signals drawn, sheathed; draw(); sheathe(); is_drawn()
  @export hand_socket, sheath_socket: BoneAttachment3D   # sheath = `scabbard` bone on the left hip (D6)
  func snap_weapon_to_hand() -> void; func snap_weapon_to_sheath() -> void   # AnimationPlayer method-track hooks

class_name Katana extends Node3D              # hitbox: Hitbox; begin_swing(attack); set_active(on)

class_name CombatStateMachine extends Node    # player "Combat" node (runbook: CombatController)
  signal state_changed(previous: State, current: State)   # not emitted for ATTACK → ATTACK chains
  signal attack_started(attack: AttackData); signal dodge_started(direction: Vector3)
  enum State { IDLE, RUN, ATTACK, DODGE, HURT, DEAD }
  const ALL_ACTIONS := [ComboManager.LIGHT, ComboManager.HEAVY, ComboManager.DODGE]
  @export combo: ComboManager; @export warping: MotionWarping; @export targeting: Node   # targeting optional (M7)
  @export dodge_duration := 0.45; dodge_distance := 3.2; dodge_move_time := 0.32; dodge_iframes := Vector2(0.08, 0.3); dodge_cancel_time := 0.3
  var state: State; var current_attack: AttackData   # null outside ATTACK
  func is_attacking() -> bool; static func dodge_clip(facing: Vector3, direction: Vector3) -> StringName

class_name PlayerController extends CharacterBody3D
  func spawn_at(pos: Vector3, yaw: float) -> void; func respawn() -> void
  func begin_attack(direction: Vector3, lunge_speed: float, lunge_duration: float, lunge_delay := 0.0) -> void   # lunge_speed = average; eases out
  func begin_dodge(direction: Vector3, speed: float, duration: float, turn := true) -> void; func face(direction: Vector3) -> void
  func end_attack() -> void; func lock_controls(locked: bool) -> void
  func apply_knockback(knockback: Vector3) -> void; func add_look_input(delta: Vector2) -> void
  func get_move_direction() -> Vector3; func get_facing() -> Vector3; func get_planar_speed() -> float

class_name Wolf extends CharacterBody3D       # group "enemies"; enum State { WANDER, CHASE, BITE, STAGGER, DEAD }
```

Input actions: `move_forward/back/left/right`, `jump`, `sprint`, `attack` (light), `attack_heavy`,
`dodge` (registered at runtime in `PlayerController._DEFAULT_BINDINGS`, keyboard, mouse and gamepad).
Groups: `enemies`, `navigation_source`.

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
  func chip(amount: float) -> void           # guard chip damage: no `damaged`, never below 1 health
  func is_invulnerable() -> bool              # dodge i-frames and the boss roar use it

class_name HitInfo                            # v2, fields added (all optional, with defaults)
  poise_damage: float; damage_type: int (AttackData.DamageType); hit_position: Vector3
  unblockable: bool; can_be_parried: bool; attack: AttackData
  broke_posture: bool                        # set by the Hurtbox (M5): this hit, not an earlier one, broke posture

  enum Result { IGNORED, HIT, BLOCKED, PARRIED, GUARD_BROKEN, KILLED }   # HitInfo.Result
  static func is_landed(result: Result) -> bool   # HIT or KILLED

class_name Hurtbox                            # v2
  signal hit_received(hit: HitInfo, result: HitInfo.Result)   # not emitted for IGNORED
  @export var health: HealthComponent
  @export var posture: Node                   # optional; a PostureComponent, or anything with add_posture(amount) -> bool (kept duck-typed for test stubs)
  func receive_hit(hit: HitInfo) -> HitInfo.Result   # runs defenders in order, then health and posture
  func add_defender(d: Object, first := false) -> void   # anything with intercept(hit: HitInfo) -> HitInfo.Result (IGNORED = pass through); first = ahead of the rest (ParrySystem)
  func remove_defender(d: Object) -> void
  static func find_for(node: Node, health: HealthComponent) -> Hurtbox   # a body's hurtbox, so body contacts can't bypass defenders
  # Returns IGNORED while health.is_invulnerable(), before any defender runs.
  # Hitbox routes every hit through the target's Hurtbox (found with find_for() when it touched the
  # body). Only targets without a Hurtbox take damage directly. Hit-stop and hit_landed fire only
  # on HIT or KILLED.

# M3: offense (implemented)
class_name AttackData                         # v2, fields added
  enum DamageType { BLUNT, SLASH, PIERCE }
  poise_damage: float; damage_type: DamageType; knockback_direction_override: Vector3   # override is attacker-local (-Z forward)
  unblockable: bool; can_be_parried: bool; trauma: float; warp: bool
  cancel_open: float (-1 = none); cancel_into: Array[StringName]   # e.g. [&"dodge"]
  # Strikes: attack_1..3, heavy_1, heavy_2, heavy_finisher, draw_attack (resources/combat/)

class_name ComboNode extends Resource         # attack: AttackData; next: Dictionary[StringName, Resource] (ComboNodes); follow(action) -> ComboNode
class_name ComboGraph extends Resource        # root: ComboNode; draw_root: ComboNode (openers while sheathed)
  # resources/combat/sword_combo.tres: L→L→L, L→H(heavy_2), L→L→H(heavy_finisher), H(heavy_1)→L; sheathed: draw_attack → L2 / H2

class_name ComboManager extends Node          # child of Combat
  signal attack_triggered(attack: AttackData); signal combo_reset
  const LIGHT := &"attack_light"; const HEAVY := &"attack_heavy"; const DODGE := &"dodge"
  @export buffer_window := 0.35; @export combo_reset_time := 1.1; @export graph: ComboGraph
  func push_input(action) -> void; func consume(allowed: Array[StringName]) -> StringName   # FIFO: only the oldest live press
  func peek() -> StringName; func has_buffered() -> bool; func clear_buffer() -> void
  func has_branch(action, sheathed := false) -> bool; func next_attack(action, sheathed := false) -> AttackData
  func attack_finished() -> void; func reset() -> void; func current_attack() -> AttackData

class_name MotionWarping extends Node         # child of Combat
  signal warp_started(target: Node3D); signal warp_completed
  @export body: PlayerController; @export targeting: Node   # anything with `current_target: Node3D`
  @export max_warp_distance := 3.5; max_warp_angle := 60.0; stop_distance := 1.2; max_warp_speed := 14.0
  func plan(attack: AttackData) -> Dictionary   # {direction, speed, duration, delay, target}; velocity only, never tweens position
  func warp_speed(distance: float, duration: float) -> float; func find_target(direction: Vector3) -> Node3D

# M5: defense (implemented; scripts/combat/defense/, all children of the character, all optional per character)
class_name PostureComponent extends Node      # the Hurtbox's `posture`
  signal posture_changed(current: float, maximum: float); signal posture_broken; signal posture_recovered
  @export max_posture := 100.0; recovery_rate := 15.0; recovery_delay := 1.2; break_duration := 2.0; wounded_recovery_scale := 0.25
  @export health: HealthComponent; guard: GuardComponent; body: CharacterBody3D   # optional: health scaling, x2 while guarding still
  var current: float; var is_broken: bool
  func add_posture(amount: float) -> bool     # true = broke; ignored while broken
  func current_recovery_rate() -> float; func reset() -> void
  static func find_on(node: Node) -> PostureComponent
class_name GuardComponent extends Node        # defender: intercept(hit) -> BLOCKED / GUARD_BROKEN / IGNORED
  signal guard_started; signal guard_ended; signal guard_broken; signal blocked(hit: HitInfo)
  @export hurtbox: Hurtbox; posture: PostureComponent; body: Node3D
  @export guard_arc_degrees := 150.0; guard_break_stagger := 2.5; chip_damage := 0.0 (share of damage, non-lethal)
  var is_guarding: bool
  func set_guarding(on: bool) -> void; func covers(hit: HitInfo) -> bool
  static func facing_of(node: Node3D) -> Vector3   # get_facing() if the node has it, else -Z
class_name ParrySystem extends Node           # defender, registers itself first on the Hurtbox
  signal parry_successful(attacker: Node3D, point: Vector3)
  @export hurtbox: Hurtbox; guard: GuardComponent (optional: frontal arc)
  @export parry_window := 0.15 (real time); spam_lockout := 0.4 (after a window closes); posture_reflect_multiplier := 3.0; parry_hitstop := 0.08
  func on_guard_pressed() -> bool             # true if a window opened; a successful parry lifts the lockout
  func is_window_open() -> bool
class_name DamageReactionComponent extends Node   # node name "DamageReaction"
  signal stagger_started(type: StringName); signal stagger_ended   # &"front", &"back", &"left", &"right", &"heavy", &"knockdown", &"guard_break", &"parried"
  @export body: CharacterBody3D; hurtbox: Hurtbox; posture: PostureComponent; guard: GuardComponent
  @export poise_threshold := 30.0; knockdown_threshold := 60.0; friction := 18.0
  @export flinch_time := 0.3; heavy_time := 0.7; knockdown_time := 1.8; parried_time := 1.0; blocked_push := 0.35
  var is_staggered: bool; var stagger_type: StringName
  func react(type: StringName, duration: float) -> void   # a held knockdown / guard_break / parried with more time left isn't cut short
  func play_parried(broke_posture := false) -> void; func clear() -> void; func classify(hit: HitInfo) -> Array   # [type, duration]
  # A hit that breaks posture knocks down for max(knockdown_time, stagger_time, posture.break_duration).
  static func direction_of(facing: Vector3, to_attacker: Vector3) -> StringName; static func find_on(node: Node) -> DamageReactionComponent
  # Knockback: bodies with apply_knockback() (PlayerController) brake themselves; others brake here with `friction`.
CombatStateMachine: State adds GUARD; exports guard, parry, reaction, posture; guard_pressed() / guard_released();
  static stagger_clip(type) -> StringName (STAGGER_CLIPS). PlayerController: move_speed_scale, hold_facing.
Wolf: PostureComponent (60) + DamageReaction; a parried bite staggers it.

# M6: AI (implemented; scripts/ai/, scenes/mobs/enemy_*.tscn)
class_name CombatDirector extends Node        # one per encounter (real-time leases)
  @export max_attack_tokens := 2; max_flank_tokens := 3; token_cooldown := 0.8 (after any release); token_lease_time := 4.0
  @export ring_radius := 5.0; outer_ring_radius := 8.0; slot_hysteresis := 1.5
  func request_attack_token(enemy: Node3D) -> bool; func release_attack_token(enemy: Node3D) -> void
  func has_attack_token(enemy: Node3D) -> bool; func token_count() -> int
  func get_flank_position(enemy: Node3D, player: Node3D) -> Vector3   # ring slot, or the outer ring when full
  func slot_direction(index: int, player: Node3D) -> Vector3            # evenly spaced; the gap sits behind the player (camera side)
  func register(enemy: Node3D) -> void; func unregister(enemy: Node3D) -> void   # unregister releases the token
  static func view_forward(player: Node3D) -> Vector3                   # camera yaw if the player has one, else its facing
class_name EnemyCombo extends Resource         # strikes: Array[AttackData], played on one token
class_name EnemyCombatController extends CharacterBody3D   # group "enemies"; target = first node in group "player"
  signal telegraph_glint(position: Vector3, is_unblockable: bool); signal defeated; signal executed(by: Node3D)
  signal state_changed(previous: State, current: State)
  enum State { IDLE, APPROACH, FLANKING, ATTACK_WINDUP, ATTACK_ACTIVE, RECOVER, STAGGERED, DEAD }
  @export attacks: Array[AttackData]; combos: Array[EnemyCombo]; director: CombatDirector
  @export walk_speed, run_speed, approach_distance := 2.0, aggro_radius := 14.0, telegraph_lead := 0.4, attack_cooldown, recovery_scale := 1.0
  @export execution_damage_ratio := 1.0 (grunt; brute 0.6, gatekeeper 0.4); free_on_death := true
  const STAGGER_CLIPS                         # DamageReaction type → enemy clip
  var state; var target: Node3D; var current_attack: AttackData; var glint: TelegraphGlint
  func is_executable() -> bool; func execute(by: Node3D) -> bool; func has_attack_token() -> bool
  func reset_to_spawn() -> void               # used by GameManager encounter reset; releases the token
  # Children: HealthComponent, PostureComponent, Hurtbox, DamageReaction, WeaponHitbox (moved under the
  # model's WeaponSocket at runtime), NavigationAgent3D, Model (with AnimationPlayer, WeaponSocket/Socket_Telegraph_Glint).
class_name Gatekeeper extends EnemyCombatController
  signal phase_changed(phase: int); signal roared(trauma: float)   # roar trauma 0.45 → CameraTrauma (M9)
  @export boss_name; phase_two_ratio := 0.5; phase_two_combos: Array[EnemyCombo]; roar_time := 1.2
  var phase: int                              # phase 2: invulnerable roar, recovery x0.8, posture regen x2, red combo added
class_name TelegraphGlint extends Node3D      # scenes/vfx/telegraph_glint.tscn: flash(unblockable); GOLD / RED; last_color
CombatStateMachine: execution: AttackData (execution.tres); execute_range := 2.8; execute_angle := 70;
  func execution_target() -> Node3D           # a light attack on a posture-broken enemy in front executes it
PlayerHUD: combat (execution prompt); group "boss_hud": set_boss(enemy), showing_boss()

# M7: targeting and camera (implemented)
class_name TargetingSystem extends Node       # player child "TargetingSystem"
  signal target_changed(target: Node3D)       # null = unlocked
  @export body: PlayerController; camera: CombatCamera
  @export radius := 18.0; cone_degrees := 70.0 (full angle); break_distance := 24.0; lost_sight_time := 1.5; sight_mask := 1; aim_height := 0.7
  var current_target: Node3D
  func is_locked() -> bool; func toggle_lock() -> void; func set_target(t: Node3D) -> void
  func cycle(direction: int) -> void          # +1 = next to the right on screen, -1 = left
  func find_best_target(exclude: Node3D = null) -> Node3D
class_name CombatCamera extends Node3D         # the player's top-level "CameraRig" (SpringArm3D → Camera3D)
  @export follow: Node3D; targeting: TargetingSystem; look/follow smoothing, height, pitch limits; lock_* framing
  var yaw, pitch, target_yaw, target_pitch: float; spring_arm: SpringArm3D; camera: Camera3D
  func add_look_input(delta: Vector2) -> void # ignored while locked
  func snap_to(feet: Vector3, yaw: float) -> void; func is_locked() -> bool
PlayerController: `camera: CombatCamera`, `@export targeting`; faces the target while locked (strafe).
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
| Duelist, offense | `attack_1`, `attack_2`, `attack_3`, `heavy_1`, `heavy_2`, `heavy_finisher`, `special_1`, `sprint_attack`, `draw_attack` (quick-draw from sheathed), `draw`, `sheathe` |
| Duelist, defense | `guard_idle`, `guard_hit`, `guard_break`, `parry_1`, `parry_2`, `dodge_f`, `dodge_b`, `dodge_l`, `dodge_r`, `hurt_f`, `hurt_b`, `hurt_l`, `hurt_r`, `hurt_heavy`, `knockdown` (includes the get-up; a separate `get_up` is optional), `death`, `execution` |
| Grunt | `idle`, `walk`, `run`, `strafe_l`, `strafe_r`, `attack_1`, `attack_2`, `hurt_f`, `hurt_b`, `parried`, `stagger`, `death` |
| Brute and Gatekeeper | the Grunt set, plus `slam`, `sweep`, `thrust_unblockable`, `posture_break`, `executed`, `roar` |
| Wolf (existing) | `idle`, `walk`, `run`, `bite`, `hurt`, `death` |

`attack_1` to `attack_3` and `death` keep the kit's existing names. Since M5 the Duelist has no
single `hurt` clip: CombatStateMachine.STAGGER_CLIPS maps each DamageReaction stagger type to
`hurt_f/b/l/r`, `hurt_heavy` (also used when parried), `knockdown` or `guard_break`. The wolf keeps
one `hurt` clip for every type (slowed for heavy ones).

Still to add (M9): `attack_special`, `interact`, `pause`. (`attack_heavy` and `dodge` landed in M3;
`lock_on`, `target_next`, `target_prev` and the right-stick `look_*` axes in M7; `guard` in M5.) Register them in
`_DEFAULT_BINDINGS`, with gamepad events if D10 is approved.

## Validation (every handoff)

```
bash tools/ci/validate.sh                  # downloads Godot 4.7.1 if needed, imports, runs every test
bash tools/ci/validate.sh --filter=hit     # only tests whose file or method name contains "hit"
```
`--import` alone exits 0 even when a script doesn't parse; `tests/test_project.gd` loads every
script and scene and is the real parse gate. Tests `extends "res://tests/test_case.gd"` (`check`, `check_eq`, `check_near`, `wait_until`, `load_world()` for the full scene, `add_to_stage()` for component tests; builders in `tests/lib/combat_fixtures.gd`)
and fail on any engine error logged while they run. Commit only when validation passes: `git commit -m "feat(combat): <component> (validated)"`.
