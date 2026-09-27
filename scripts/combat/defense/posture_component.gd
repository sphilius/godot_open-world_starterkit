class_name PostureComponent
extends Node
## Posture: a second meter, filled by poise damage (hits that land, and blocks), that breaks
## when full. Health decides who dies; posture decides who gets opened up.
##
## • Recovery starts `recovery_delay` seconds after the last posture damage. Its rate scales
##   with the health ratio (a wounded fighter recovers slower, down to `wounded_recovery_scale`)
##   and doubles while guarding (GuardComponent) and standing still.
## • Filling it breaks it: posture_broken fires, further posture damage is ignored, and after
##   `break_duration` it resets to 0 and posture_recovered fires.
## Hurtbox.posture points here so landed hits add their poise damage; GuardComponent adds
## blocked hits' poise damage itself.

signal posture_changed(current: float, maximum: float)
signal posture_broken
signal posture_recovered

@export var max_posture := 100.0
## Posture recovered per second at full health.
@export var recovery_rate := 15.0
## Seconds after the last posture damage before recovery starts.
@export var recovery_delay := 1.2
## Seconds a broken posture stays broken before resetting to 0.
@export var break_duration := 2.0
## Recovery rate multiplier at (near) zero health; it rises linearly to 1 at full health.
@export_range(0.0, 1.0) var wounded_recovery_scale := 0.25
## Optional: scales recovery by the health ratio.
@export var health: HealthComponent
## Optional: recovery doubles while this guard is up and `body` stands still.
@export var guard: GuardComponent
@export var body: CharacterBody3D
## Planar speed (m/s) under which `body` counts as standing still.
@export var still_speed := 0.3

var current := 0.0
var is_broken := false
var _recovery_wait := 0.0
var _break_left := 0.0


## Adds posture damage. Returns true if this broke the posture.
func add_posture(amount: float) -> bool:
	if is_broken or amount <= 0.0:
		return false
	current = minf(current + amount, max_posture)
	_recovery_wait = recovery_delay
	if current >= max_posture:
		is_broken = true
		_break_left = break_duration
		posture_changed.emit(current, max_posture)
		posture_broken.emit()
		return true
	posture_changed.emit(current, max_posture)
	return false


## Posture recovered per second right now (0 while waiting or broken).
func current_recovery_rate() -> float:
	if is_broken or _recovery_wait > 0.0:
		return 0.0
	var rate := recovery_rate
	if health and health.max_health > 0.0:
		rate *= lerpf(wounded_recovery_scale, 1.0, clampf(health.current_health / health.max_health, 0.0, 1.0))
	if guard and guard.is_guarding and (body == null or Vector2(body.velocity.x, body.velocity.z).length() < still_speed):
		rate *= 2.0
	return rate


## Empties the meter and clears a break (respawn, encounter reset).
func reset() -> void:
	var was_broken := is_broken
	current = 0.0
	is_broken = false
	_recovery_wait = 0.0
	_break_left = 0.0
	posture_changed.emit(current, max_posture)
	if was_broken:
		posture_recovered.emit()


func _physics_process(delta: float) -> void:
	if is_broken:
		_break_left -= delta
		if _break_left <= 0.0:
			reset()
		return
	if _recovery_wait > 0.0:
		_recovery_wait -= delta
		return
	if current > 0.0:
		current = maxf(current - current_recovery_rate() * delta, 0.0)
		posture_changed.emit(current, max_posture)


## The PostureComponent among `node`'s direct children, or null.
static func find_on(node: Node) -> PostureComponent:
	if node == null:
		return null
	for child in node.get_children():
		if child is PostureComponent:
			return child
	return null
