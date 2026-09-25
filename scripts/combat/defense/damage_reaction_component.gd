class_name DamageReactionComponent
extends Node
## Shared hit reactions for the player and the mobs. It listens to Hurtbox.hit_received, picks
## a stagger type and duration, applies knockback, and reports through stagger_started /
## stagger_ended; the owner plays the clip and locks its controls or AI until the stagger ends.
##
## Landed hits (HIT), by the hit's poise damage:
##   below `poise_threshold`          → a light flinch by direction: &"front", &"back",
##                                      &"left" or &"right" (where the attacker stands)
##   from `poise_threshold`           → &"heavy"
##   from `knockdown_threshold`, or
##   when the hit broke the posture   → &"knockdown" (animated; decision D8)
## GUARD_BROKEN → &"guard_break" for GuardComponent.guard_break_stagger.
## BLOCKED      → no stagger; `blocked_push` of the knockback.
## play_parried() (called by the defender's ParrySystem) → &"parried".
## Lethal hits are left to the owner's death handling.
##
## Knockback: a body with apply_knockback() (PlayerController) gets it there and brakes itself;
## any other CharacterBody3D gets its velocity set, and it decays here with `friction`.

signal stagger_started(type: StringName)
signal stagger_ended

@export var body: CharacterBody3D
@export var hurtbox: Hurtbox
## Optional: a hit that breaks it knocks down.
@export var posture: PostureComponent
## Optional: supplies the guard-break stagger time.
@export var guard: GuardComponent
@export var poise_threshold := 30.0
@export var knockdown_threshold := 60.0
## Knockback braking (m/s²) for bodies without apply_knockback().
@export var friction := 18.0

@export_group("Durations")
## Shortest flinch, whatever the hit's stagger_time (s).
@export var flinch_time := 0.3
@export var heavy_time := 0.7
## Fall and get up (s).
@export var knockdown_time := 1.8
@export var parried_time := 1.0
## Share of the knockback a blocked hit still pushes.
@export_range(0.0, 1.0) var blocked_push := 0.35

var is_staggered := false
var stagger_type := &""
var _time_left := 0.0


func _ready() -> void:
	if hurtbox:
		hurtbox.hit_received.connect(_on_hit_received)


## Staggers for `duration` seconds (replacing any current stagger).
func react(type: StringName, duration: float) -> void:
	is_staggered = true
	stagger_type = type
	_time_left = duration
	stagger_started.emit(type)


## The attacker side of a parry. A parry that also broke the posture holds for its break.
func play_parried() -> void:
	var duration := parried_time
	if posture and posture.is_broken:
		duration = maxf(duration, posture.break_duration)
	react(&"parried", duration)


## Ends a stagger early (respawn, death).
func clear() -> void:
	if not is_staggered:
		return
	is_staggered = false
	stagger_type = &""
	_time_left = 0.0
	stagger_ended.emit()


## The stagger type and duration for a landed, non-lethal hit.
func classify(hit: HitInfo, posture_broke := false) -> Array:
	if posture_broke or hit.poise_damage >= knockdown_threshold:
		return [&"knockdown", maxf(knockdown_time, hit.stagger_time)]
	if hit.poise_damage >= poise_threshold:
		return [&"heavy", maxf(heavy_time, hit.stagger_time)]
	return [direction_of(GuardComponent.facing_of(body), _attack_vector(hit)), maxf(flinch_time, hit.stagger_time)]


## Where an attack came from, relative to `facing`: &"front", &"back", &"left" or &"right"
## (90° sectors). `to_attacker` points from the victim to the attacker.
static func direction_of(facing: Vector3, to_attacker: Vector3) -> StringName:
	var flat := Vector3(to_attacker.x, 0.0, to_attacker.z)
	if flat.length_squared() < 0.0001:
		return &"front"
	var forward := flat.normalized().dot(facing)
	var right := flat.normalized().dot(facing.cross(Vector3.UP))
	if absf(forward) >= absf(right):
		return &"front" if forward >= 0.0 else &"back"
	return &"right" if right > 0.0 else &"left"


## The DamageReactionComponent among `node`'s direct children, or null.
static func find_on(node: Node) -> DamageReactionComponent:
	if node == null:
		return null
	for child in node.get_children():
		if child is DamageReactionComponent:
			return child
	return null


func _physics_process(delta: float) -> void:
	if not is_staggered:
		return
	if body and not body.has_method(&"apply_knockback"):
		var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(Vector3.ZERO, friction * delta)
		body.velocity.x = horizontal.x
		body.velocity.z = horizontal.z
	_time_left -= delta
	if _time_left <= 0.0:
		clear()


func _on_hit_received(hit: HitInfo, result: HitInfo.Result) -> void:
	match result:
		HitInfo.Result.HIT:
			var reaction := classify(hit, posture != null and posture.is_broken)
			_push(hit.knockback)
			react(reaction[0], reaction[1])
		HitInfo.Result.GUARD_BROKEN:
			_push(hit.knockback)
			react(&"guard_break", guard.guard_break_stagger if guard else 2.5)
		HitInfo.Result.BLOCKED:
			_push(hit.knockback * blocked_push)


func _push(knockback: Vector3) -> void:
	if body == null or knockback == Vector3.ZERO:
		return
	if body.has_method(&"apply_knockback"):
		body.call(&"apply_knockback", knockback)
	else:
		body.velocity.x = knockback.x
		body.velocity.z = knockback.z


func _attack_vector(hit: HitInfo) -> Vector3:
	if body == null:
		return Vector3.ZERO
	if is_instance_valid(hit.source):
		return hit.source.global_position - body.global_position
	if hit.hit_position != Vector3.ZERO:
		return hit.hit_position - body.global_position
	return -hit.knockback                                   # pushed away from the attacker
