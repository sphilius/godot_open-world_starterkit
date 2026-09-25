class_name ComboManager
extends Node
## Input buffer plus combo graph. It knows nothing about animation, bodies or visuals: the
## combat state machine asks it what to do next and plays the answer.
##
## • Buffer: presses of `attack_light`, `attack_heavy` and `dodge` queue up (FIFO) and expire
##   after `buffer_window` seconds. consume() only takes the oldest live press, so the order of
##   inputs is kept, and a press that isn't allowed yet waits until it is or expires.
## • Graph: a ComboGraph of ComboNodes. From neutral, presses start at its `root` (or its
##   `draw_root` while the weapon is sheathed: the quick-draw opener). Each strike's node says which action chains
##   into which strike; a chain that has no branch for an action ends there.
## • Reset: after a strike ends, the chain is remembered for `combo_reset_time` seconds, so a
##   press soon after recovery still continues it. Then it returns to neutral.

signal attack_triggered(attack: AttackData)
signal combo_reset

const LIGHT := &"attack_light"
const HEAVY := &"attack_heavy"
const DODGE := &"dodge"

## Seconds a press stays buffered.
@export var buffer_window := 0.35
## Seconds after a strike ends before the chain returns to neutral.
@export var combo_reset_time := 1.1
## The move list: neutral openers plus quick-draw openers (resources/combat/sword_combo.tres).
@export var graph: ComboGraph

var _buffer: Array[Dictionary] = []     # [{action, msec}], oldest first
var _current: ComboNode                  # the strike playing or just played; null = neutral
var _reset_at_msec := -1                 # when to return to neutral (-1 = no reset pending)


func push_input(action: StringName) -> void:
	_buffer.append({action = action, msec = Time.get_ticks_msec()})


func has_buffered() -> bool:
	_drop_expired()
	return not _buffer.is_empty()


func clear_buffer() -> void:
	_buffer.clear()


## Takes the oldest live press if it is one of `allowed`, and returns its action (&"" if none).
func consume(allowed: Array[StringName]) -> StringName:
	_drop_expired()
	if _buffer.is_empty() or not allowed.has(_buffer[0].action):
		return &""
	return _buffer.pop_front().action


## The action of the oldest live press, without consuming it (&"" if none).
func peek() -> StringName:
	_drop_expired()
	return _buffer[0].action if not _buffer.is_empty() else &""


## True when `action` would chain from the current strike (or start a chain from neutral).
func has_branch(action: StringName, sheathed := false) -> bool:
	return _node_for(action, sheathed) != null


## Advances the chain with `action` and returns the strike to play (null if it doesn't chain).
func next_attack(action: StringName, sheathed := false) -> AttackData:
	var node := _node_for(action, sheathed)
	if node == null:
		return null
	_current = node
	_reset_at_msec = -1
	attack_triggered.emit(node.attack)
	return node.attack


## The strike that was playing ended without chaining: start the reset countdown.
func attack_finished() -> void:
	_reset_at_msec = Time.get_ticks_msec() + int(combo_reset_time * 1000.0)


## Back to neutral at once (dodge, hit, death).
func reset() -> void:
	var was_in_chain := _current != null
	_current = null
	_reset_at_msec = -1
	if was_in_chain:
		combo_reset.emit()


func current_attack() -> AttackData:
	return _current.attack if _current else null


func _process(_delta: float) -> void:
	if _reset_at_msec >= 0 and Time.get_ticks_msec() >= _reset_at_msec:
		reset()


func _node_for(action: StringName, sheathed: bool) -> ComboNode:
	if _reset_at_msec >= 0 and Time.get_ticks_msec() >= _reset_at_msec:
		reset()
	var from := _current
	if from == null and graph:
		from = graph.draw_root if sheathed and graph.draw_root else graph.root
	if from == null:
		return null
	return from.follow(action)


func _drop_expired() -> void:
	var oldest_live := Time.get_ticks_msec() - int(buffer_window * 1000.0)
	while not _buffer.is_empty() and _buffer[0].msec < oldest_live:
		_buffer.pop_front()
