class_name AttackData
extends Resource
## One strike of a combo. Times are seconds from the start of the attack's animation.
##
## tools/build_placeholder_rigs.gd shapes each placeholder swing from these same numbers,
## so animation poses and gameplay windows always line up. With imported animations,
## set the timings to match the clip instead.

enum DamageType { BLUNT, SLASH, PIERCE }

## State name in the AnimationTree state machine.
@export var animation: StringName = &"attack_1"
@export var damage := 20.0
## Damage to the target's posture (PostureComponent), separate from health.
@export var poise_damage := 10.0
@export var damage_type := DamageType.SLASH

@export_group("Timing")
## Full length of the strike; the attack ends here unless it chains.
@export var duration := 0.55
## Hitbox and trail switch on…
@export var active_start := 0.14
## …and off.
@export var active_end := 0.3
## Earliest moment a buffered press chains into the next strike. Clamped to at least
## active_end, so a strike's active frames always play out.
@export var combo_window_open := 0.22
## Earlier cancel window: from this time on (negative = never), the actions in `cancel_into`
## may interrupt the strike, even during its wind-up or active frames.
@export var cancel_open := -1.0
## Actions allowed in the cancel window, e.g. [&"dodge"].
@export var cancel_into: Array[StringName] = []

@export_group("Feel")
## Forward burst (m/s) at the start of the strike (average speed; it eases out).
@export var lunge_speed := 3.0
@export var lunge_duration := 0.15
## Seconds after the strike starts before the lunge kicks in (a bite's wind-up, for example).
@export var lunge_delay := 0.0
## Real-time seconds the world freezes when this strike connects.
@export var hitstop := 0.06
## How long the target is staggered (movement and AI interrupted).
@export var stagger_time := 0.3
## Horizontal knockback speed applied to the target (m/s).
@export var knockback := 3.0
## Knockback direction in the attacker's local space (-Z is forward); zero pushes straight
## away from the attacker.
@export var knockback_direction_override := Vector3.ZERO
## Camera shake added when this strike lands (0..1, CameraTrauma).
@export var trauma := 0.2

@export_group("Rules")
## Guards can't absorb it (red telegraph glint): it has to be dodged.
@export var unblockable := false
@export var can_be_parried := true
## MotionWarping may steer and stretch the lunge toward a nearby or locked target.
@export var warp := true
