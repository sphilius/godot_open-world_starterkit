class_name ParrySystem
extends Node
## Parry: a Hurtbox defender that runs before GuardComponent.
##
## Pressing guard calls on_guard_pressed(), which opens a `parry_window` (real time, so hit-stop
## and slow motion don't stretch it). A parryable, blockable hit from the front (the guard's
## arc, when a guard is set) inside the window is PARRIED: the attacker's PostureComponent takes
## `posture_reflect_multiplier` times the hit's poise damage, the attacker's
## DamageReactionComponent plays "parried", and parry_successful fires.
## Spamming is punished: after a window closes, presses during `spam_lockout` open nothing. A
## successful parry lifts the lockout, so each strike of a combo can be parried in turn.

signal parry_successful(attacker: Node3D, point: Vector3)

## The Hurtbox this parries for; it registers itself there, ahead of every other defender.
@export var hurtbox: Hurtbox
## Optional: parries only cover this guard's frontal arc.
@export var guard: GuardComponent
## Seconds (real time) a guard press can parry.
@export var parry_window := 0.15
## Seconds after a window closes during which presses open no new window.
@export var spam_lockout := 0.4
@export var posture_reflect_multiplier := 3.0
## Real-time freeze when a parry lands.
@export var parry_hitstop := 0.08

var _window_end_msec := 0
var _locked_until_msec := 0


func _ready() -> void:
	if hurtbox:
		hurtbox.add_defender(self, true)


func _exit_tree() -> void:
	if hurtbox:
		hurtbox.remove_defender(self)


## Opens a parry window unless locked out. Returns true if a window opened.
func on_guard_pressed() -> bool:
	var now := Time.get_ticks_msec()
	if now < _locked_until_msec:
		return false
	_window_end_msec = now + int(parry_window * 1000.0)
	_locked_until_msec = _window_end_msec + int(spam_lockout * 1000.0)
	return true


func is_window_open() -> bool:
	return Time.get_ticks_msec() < _window_end_msec


func intercept(hit: HitInfo) -> HitInfo.Result:
	if not is_window_open() or not hit.can_be_parried or hit.unblockable:
		return HitInfo.Result.IGNORED
	if guard and not guard.covers(hit):
		return HitInfo.Result.IGNORED
	var now := Time.get_ticks_msec()
	_window_end_msec = now                              # one parry per press
	_locked_until_msec = now                            # but the next press may parry again
	var attacker := hit.source if is_instance_valid(hit.source) else null
	var attacker_posture := PostureComponent.find_on(attacker)
	if attacker_posture:
		attacker_posture.add_posture(hit.poise_damage * posture_reflect_multiplier)
	var attacker_reaction := DamageReactionComponent.find_on(attacker)
	if attacker_reaction:
		attacker_reaction.play_parried()
	HitStop.trigger(parry_hitstop)
	parry_successful.emit(attacker, hit.hit_position)
	return HitInfo.Result.PARRIED
