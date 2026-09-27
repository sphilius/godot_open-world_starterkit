class_name StaminaComponent
extends Node
## Stamina (Phase C, decision D16): spent by strikes, dodges and blocks; refills after a pause.
##
## • spend() pays for an action: it's refused (returns false) while exhausted or empty, and never
##   takes stamina below 0. drain() takes stamina without asking (a blocked hit's impact).
## • Refill starts `regen_delay` seconds after the last spend or drain, at `regen_rate` per second
##   times `regen_scale` (the owner lowers it while guarding).
## • crack() is the defensive posture cracking (a guard break): stamina empties and the fighter
##   is exhausted, unable to act, until it refills past `lockout_ratio` of the maximum.

signal stamina_changed(current: float, maximum: float)
## The defensive posture cracked: no strikes, dodges or blocks until recovered.
signal exhausted
## Stamina refilled past the lockout threshold after exhaustion.
signal recovered

@export var max_stamina := 100.0
## Stamina refilled per second (before `regen_scale`).
@export var regen_rate := 32.0
## Seconds after the last spend or drain before refilling starts.
@export var regen_delay := 0.7
## Share of the maximum that ends exhaustion.
@export_range(0.0, 1.0) var lockout_ratio := 0.3

var current := 0.0
var is_exhausted := false
## Refill speed multiplier set by the owner (0.5 while guarding, for example).
var regen_scale := 1.0
var _delay_left := 0.0


func _ready() -> void:
	current = max_stamina


func _physics_process(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	if current >= max_stamina:
		return
	current = minf(current + regen_rate * regen_scale * delta, max_stamina)
	if is_exhausted and current >= max_stamina * lockout_ratio:
		is_exhausted = false
		recovered.emit()
	stamina_changed.emit(current, max_stamina)


## True if an action may be paid for now (not exhausted, not empty).
func can_act() -> bool:
	return not is_exhausted and current > 0.0


## Pays `amount` for an action. Refused while exhausted or empty; otherwise never goes below 0.
func spend(amount: float) -> bool:
	if not can_act():
		return false
	_take(amount)
	return true


## Takes `amount` without asking (the impact of a blocked hit).
func drain(amount: float) -> void:
	_take(amount)


## Gives `amount` back (a perfect dodge refunds its cost).
func refund(amount: float) -> void:
	current = minf(current + amount, max_stamina)
	stamina_changed.emit(current, max_stamina)


## The defensive posture cracked: empty and exhausted until `lockout_ratio` refills.
func crack() -> void:
	current = 0.0
	_delay_left = regen_delay
	var was_exhausted := is_exhausted
	is_exhausted = true
	stamina_changed.emit(current, max_stamina)
	if not was_exhausted:
		exhausted.emit()


## Full and rested (respawn, a shrine).
func reset() -> void:
	current = max_stamina
	_delay_left = 0.0
	is_exhausted = false
	stamina_changed.emit(current, max_stamina)


func ratio() -> float:
	return current / max_stamina if max_stamina > 0.0 else 0.0


func _take(amount: float) -> void:
	if amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	_delay_left = regen_delay
	stamina_changed.emit(current, max_stamina)


static func find_on(node: Node) -> StaminaComponent:
	if node == null:
		return null
	for child in node.get_children():
		if child is StaminaComponent:
			return child
	return null
