class_name FeedbackDirector
extends Node
## Turns combat and world events into sound, sparks and screen shake (M9b), so every player
## action gets audio and VFX feedback. It watches the scene tree (including enemies that spawn
## later) and connects to:
##   Hurtbox.hit_received    HIT/KILLED → hit (hit_heavy on kills, heavy strikes and posture
##                           breaks) + sparks; BLOCKED → block; PARRIED → parry + flash;
##                           GUARD_BROKEN or a posture break → posture_break + burst
##   Hitbox.swing_started    whoosh_light / whoosh_heavy (poise damage from `heavy_poise`)
##   EnemyCombatController   telegraph_glint → glint_gold / glint_red; executed → shake;
##                           Gatekeeper.roared(trauma) → roar + shake
##   CheckpointShrine        activated → shrine_ignite
##   LevelGate               moving → gate
## Screen shake (CameraTrauma) only follows hits the player deals or takes: a landed strike
## shakes by its AttackData.trauma, and being hit, parrying, posture breaks, executions and
## death use the CameraTrauma presets. Hits on the locked target pulse the lock-on reticle.

@export var sfx: SfxPool
@export var player: PlayerController
## Where hit effects are added (a Node3D in the world). Defaults to this node's parent.
@export var effects_parent: Node3D
## Strikes with at least this much poise damage count as heavy (sound and weight).
@export var heavy_poise := 30.0

var _trauma: CameraTrauma
var _player_health: HealthComponent


func _ready() -> void:
	if effects_parent == null:
		effects_parent = get_parent() as Node3D
	_trauma = CameraTrauma.find(get_tree())
	if player:
		_player_health = HealthComponent.resolve(player)
		if _player_health:
			_player_health.died.connect(func(_hit: HitInfo) -> void: _shake(CameraTrauma.DEATH))
	get_tree().node_added.connect(watch)
	for node in get_tree().root.find_children("*", "", true, false):
		watch(node)


## Connects to `node` if it's something this director gives feedback for.
func watch(node: Node) -> void:
	if node is Hurtbox:
		_connect(node, &"hit_received", _on_hit.bind(node))
	elif node is Hitbox:
		_connect(node, &"swing_started", _on_swing.bind(node))
	elif node is EnemyCombatController:
		_connect(node, &"telegraph_glint", _on_glint)
		_connect(node, &"executed", _on_executed)
		if node.has_signal(&"roared"):
			_connect(node, &"roared", _on_roar.bind(node))
	elif node is CheckpointShrine:
		_connect(node, &"activated", _on_shrine_lit.bind(node))
	elif node is LevelGate:
		_connect(node, &"moving", _on_gate.bind(node))


func _connect(node: Node, signal_name: StringName, callable: Callable) -> void:
	if not node.is_connected(signal_name, callable):
		node.connect(signal_name, callable)


func _on_hit(hit: HitInfo, result: HitInfo.Result, hurtbox: Hurtbox) -> void:
	var at := hit.hit_position if hit.hit_position != Vector3.ZERO else hurtbox.global_position + Vector3.UP
	var heavy := hit.poise_damage >= heavy_poise or hit.broke_posture
	match result:
		HitInfo.Result.HIT:
			_play(&"hit_heavy" if heavy else &"hit", at)
			if hit.broke_posture:
				_play(&"posture_break", at, -2.0)
		HitInfo.Result.KILLED:
			_play(&"hit_heavy", at)
		HitInfo.Result.BLOCKED:
			_play(&"block", at)
		HitInfo.Result.PARRIED:
			_play(&"parry", at)
		HitInfo.Result.GUARD_BROKEN:
			_play(&"block", at)
			_play(&"posture_break", at)
		_:
			return
	if effects_parent and effects_parent.is_inside_tree():
		HitVfx.spawn(effects_parent, at, result, hit.broke_posture)

	var player_hit := _player_health != null and hurtbox.health == _player_health
	var player_struck := player != null and hit.source == player
	if player_hit:
		match result:
			HitInfo.Result.HIT, HitInfo.Result.KILLED:
				_shake(CameraTrauma.HURT)
			HitInfo.Result.PARRIED:
				_shake(CameraTrauma.PARRY)
			HitInfo.Result.GUARD_BROKEN:
				_shake(CameraTrauma.POSTURE_BREAK)
			HitInfo.Result.BLOCKED:
				_shake(CameraTrauma.LIGHT * 0.5)
	elif player_struck:
		var amount := hit.attack.trauma if hit.attack else CameraTrauma.LIGHT
		if hit.broke_posture or result == HitInfo.Result.GUARD_BROKEN:
			amount = maxf(amount, CameraTrauma.POSTURE_BREAK)
		_shake(amount)
		_pulse_reticle(hurtbox)
	if player_hit and result == HitInfo.Result.PARRIED and hit.source:
		_pulse_reticle(hit.source)


func _on_swing(attack: AttackData, hitbox: Hitbox) -> void:
	_play(&"whoosh_heavy" if attack.poise_damage >= heavy_poise else &"whoosh_light", hitbox.global_position, -4.0)


func _on_glint(at: Vector3, unblockable: bool) -> void:
	_play(&"glint_red" if unblockable else &"glint_gold", at, -2.0)


func _on_executed(_by: Node3D) -> void:
	_shake(CameraTrauma.EXECUTION)


func _on_roar(trauma: float, boss: Node3D) -> void:
	_play(&"roar", boss.global_position + Vector3.UP * 2.0)
	_shake(trauma)


func _on_shrine_lit(shrine: CheckpointShrine) -> void:
	_play(&"shrine_ignite", shrine.global_position + Vector3.UP)


func _on_gate(_opening: bool, gate: LevelGate) -> void:
	_play(&"gate", gate.global_position + Vector3.UP * 1.5)


func _play(event: StringName, at: Vector3, volume_db := 0.0) -> void:
	if sfx:
		sfx.play(event, at, volume_db)


func _shake(amount: float) -> void:
	if _trauma:
		_trauma.add_trauma(amount)


## Pops the lock-on reticle when `node` (or the body that owns it) is the locked target.
func _pulse_reticle(node: Node) -> void:
	var targeting := player.targeting if player else null
	if targeting == null or not targeting.is_locked():
		return
	var target := targeting.current_target
	if node == target or (node and node.get_parent() == target):
		targeting.pulse()
