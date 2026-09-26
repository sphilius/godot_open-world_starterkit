class_name CombatDirector
extends Node
## One per encounter: decides who may attack and where everyone else waits.
##
## • Attack tokens are leases. At most `max_attack_tokens` enemies hold one; an enemy releases it
##   when its attack ends, when it's staggered and when it dies (unregister() releases too), and
##   a lease older than `token_lease_time` expires anyway, as a safety net. After any release,
##   no token is issued for `token_cooldown` seconds, so attacks come in a rhythm rather than
##   a pile-on.
## • Flank ring: everyone without a token circles the player on `ring_radius`. The ring has
##   `max_flank_tokens` evenly spaced slots, anchored to the view so the gap between slots sits
##   behind the player (between the player and the camera) and enemies stay on screen. Slots are
##   assigned greedily, nearest first, and an enemy only swaps to a better slot when it's closer
##   by more than `slot_hysteresis`, so enemies don't shuffle every frame. Enemies beyond the
##   ring's capacity wait further out (`outer_ring_radius`).
## Times are real time (Time.get_ticks_msec), like the parry window.

@export var max_attack_tokens := 2
@export var max_flank_tokens := 3
## Seconds after a release before any token is issued again.
@export var token_cooldown := 0.8
## Seconds after which an unreleased token expires.
@export var token_lease_time := 4.0
@export var ring_radius := 5.0
@export var outer_ring_radius := 8.0
## Metres a free slot must beat the current one by before an enemy switches to it.
@export var slot_hysteresis := 1.5

var _enemies: Array[Node3D] = []
var _tokens := {}          # enemy -> issue time (msec)
var _slots := {}           # enemy -> slot index
var _next_issue_msec := 0


func register(enemy: Node3D) -> void:
	if not _enemies.has(enemy):
		_enemies.append(enemy)


func unregister(enemy: Node3D) -> void:
	release_attack_token(enemy)
	_enemies.erase(enemy)
	_slots.erase(enemy)


func is_registered(enemy: Node3D) -> bool:
	return _enemies.has(enemy)


## True if `enemy` holds (or was just given) an attack token.
func request_attack_token(enemy: Node3D) -> bool:
	_expire_leases()
	if _tokens.has(enemy):
		return true
	var now := Time.get_ticks_msec()
	if _tokens.size() >= max_attack_tokens or now < _next_issue_msec:
		return false
	_tokens[enemy] = now
	_slots.erase(enemy)                                 # it leaves the ring to attack
	return true


func release_attack_token(enemy: Node3D) -> void:
	_drop_token(enemy)


# Untyped, so a freed enemy's stale key can still be dropped.
func _drop_token(key: Variant) -> void:
	if _tokens.erase(key):
		_next_issue_msec = Time.get_ticks_msec() + int(token_cooldown * 1000.0)


func has_attack_token(enemy: Node3D) -> bool:
	_expire_leases()
	return _tokens.has(enemy)


func token_count() -> int:
	_expire_leases()
	return _tokens.size()


## Where `enemy` should wait around `player`: its ring slot, or a spot on the outer ring when
## every slot is taken.
func get_flank_position(enemy: Node3D, player: Node3D) -> Vector3:
	var slot := _assign_slot(enemy, player)
	var centre := player.global_position
	if slot < 0:
		var away := enemy.global_position - centre
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3.BACK
		return centre + away.normalized() * outer_ring_radius
	return centre + slot_direction(slot, player) * ring_radius


## Unit direction from the player to slot `index`: evenly spaced, with the ring's gap behind
## the player (toward the camera).
func slot_direction(index: int, player: Node3D) -> Vector3:
	var forward := view_forward(player)
	var step := TAU / float(max_flank_tokens)
	# Slots sit at ±step/2, ±3step/2… from straight ahead, so none is directly behind for an
	# even count; for an odd count the middle slot is straight ahead and the gap is behind.
	var angle := (index - (max_flank_tokens - 1) * 0.5) * step
	return forward.rotated(Vector3.UP, angle)


## The player's view direction: its camera's yaw when it has one (stable while the model
## turns during attacks), else its facing.
static func view_forward(player: Node3D) -> Vector3:
	var camera: Variant = player.get(&"camera")
	if camera is Object and (camera as Object).get(&"yaw") != null:
		var yaw: float = (camera as Object).get(&"yaw")
		return Vector3(-sin(yaw), 0.0, -cos(yaw))
	return GuardComponent.facing_of(player)


func _assign_slot(enemy: Node3D, player: Node3D) -> int:
	var taken := {}
	for other: Variant in _slots:
		if other != enemy:
			taken[_slots[other]] = true
	var current: int = _slots.get(enemy, -1)
	var best := current
	var best_distance := INF if current < 0 else _slot_distance(enemy, current, player) - slot_hysteresis
	for index in max_flank_tokens:
		if taken.has(index) or index == current:
			continue
		var distance := _slot_distance(enemy, index, player)
		if distance < best_distance:
			best = index
			best_distance = distance
	if best < 0:
		_slots.erase(enemy)
	else:
		_slots[enemy] = best
	return best


func _slot_distance(enemy: Node3D, index: int, player: Node3D) -> float:
	var spot := player.global_position + slot_direction(index, player) * ring_radius
	var offset := spot - enemy.global_position
	offset.y = 0.0
	return offset.length()


func _expire_leases() -> void:
	var now := Time.get_ticks_msec()
	for key: Variant in _tokens.keys():
		if not is_instance_valid(key) or now - int(_tokens[key]) > int(token_lease_time * 1000.0):
			_drop_token(key)
	for key: Variant in _slots.keys():
		if not is_instance_valid(key):
			_slots.erase(key)
